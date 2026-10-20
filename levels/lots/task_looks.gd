extends Node3D

## Authority: local, cosmetic. What the job's work looks like and how it changes
## as it gets done (net/work/job_tasks.gd): grime on windows that fades as you
## spray it, gunk in the gutters, weeds in the beds, shaggy hedge tops, faded
## fence panels that turn fresh white, litter on the lawn, tall grass that mows
## down into stripes, and oil stains on the driveway. Plus a burst of water,
## clippings, gunk, or paint wherever work lands, for everyone to see.
## Built by levels/lots/lot_generator.gd, which tells it where each spot is.

const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const _Surfaces = preload("res://props/surfaces.gd")
const _Grass = preload("res://props/grass.gd")
const FRESH_PAINT := Color(0.96, 0.95, 0.9)
const FADED_PAINT := Color(0.62, 0.58, 0.52)
## Tufts drawn per lawn cell, and how tall uncut grass stands compared to mowed.
const TUFTS_PER_CELL: int = 3
const MOWED_SCALE: float = 0.3

var _tasks: Node
## spot index -> {kind, node, ...}
var _spots: Dictionary = {}
var _lawns: Dictionary = {}
var _stains: Dictionary = {}
static var _grime: Texture2D
static var _meshes: Dictionary = {}


func _ready() -> void:
	add_to_group("task_looks")


func setup(tasks: Node) -> void:
	_tasks = tasks
	tasks.connect("spot_changed", _on_spot_changed)
	tasks.connect("cell_changed", _on_cell_changed)
	for index: int in _spots:
		_on_spot_changed(index, int(tasks.call("spot", index)["amount"]))
	for grid: int in _lawns:
		_build_lawn(grid)
	for grid: int in _stains:
		_build_stains(grid)


# ---------------------------------------------------------------- spots

func add_window(index: int, at: Vector3, normal: Vector3) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(1.38, 1.32) if absf(normal.z) > 0.5 else Vector2(1.18, 1.18)
	var material := StandardMaterial3D.new()
	material.albedo_texture = _grime_texture()
	material.albedo_color = Color(0.45, 0.38, 0.28, 0.85)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 1.0
	var view := MeshInstance3D.new()
	view.mesh = quad
	view.material_override = material
	view.set_meta("keep_material", true)
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(view)
	view.global_position = at
	view.look_at(at + normal, Vector3.UP)
	view.rotate_object_local(Vector3.UP, PI)
	_spots[index] = {"kind": "window", "node": view, "material": material}


func add_gutter(index: int, at: Vector3) -> void:
	var view := _Stylized.instance(_mesh("gunk"), {"roughness": 1.0})
	add_child(view)
	view.global_position = at + Vector3(0.0, -0.05, 0.0)
	view.rotation.y = randf() * TAU
	_spots[index] = {"kind": "shrink", "node": view, "full": Vector3.ONE}


func add_weed(index: int, at: Vector3) -> void:
	var view := _Stylized.instance(_mesh("weed"), {"wind": 0.03, "roughness": 1.0, "double_sided": true})
	add_child(view)
	view.global_position = at
	view.rotation.y = randf() * TAU
	_spots[index] = {"kind": "shrink", "node": view, "full": Vector3.ONE}


func add_shaggy(index: int, at: Vector3) -> void:
	var view := _Stylized.instance(_mesh("shaggy"), {"wind": 0.05, "roughness": 1.0})
	add_child(view)
	view.global_position = at
	view.rotation.y = randf() * TAU
	_spots[index] = {"kind": "shrink", "node": view, "full": Vector3.ONE}


## A pile of leaves lying on the roof, tipped to the roof's slope.
func add_roof_leaves(index: int, at: Vector3, normal: Vector3) -> void:
	var view := _Stylized.instance(_mesh("roof_leaves"), {"roughness": 1.0, "double_sided": true})
	add_child(view)
	# Lying flat on the slope: up is the roof's normal, across is along the ridge.
	var across := Vector3.RIGHT
	view.global_transform = Transform3D(Basis(across, normal, across.cross(normal)), at)
	view.rotate_object_local(Vector3.UP, randf() * TAU)
	_spots[index] = {"kind": "shrink", "node": view, "full": Vector3.ONE}


func add_fence_panel(index: int, holder: Node3D) -> void:
	_spots[index] = {"kind": "paint", "node": holder, "bucket": -1}


func add_litter(index: int, at: Vector3, seed_value: int) -> void:
	var kinds := ["can", "paper", "bottle"]
	var view := _Stylized.instance(_mesh(kinds[absi(seed_value) % kinds.size()]), {"roughness": 0.5, "specular": 0.4})
	add_child(view)
	view.global_position = at
	view.rotation = Vector3(0.0, float(seed_value % 628) / 100.0, 0.0)
	_spots[index] = {"kind": "gone", "node": view}


func _on_spot_changed(index: int, amount: int) -> void:
	if not _spots.has(index):
		return
	var entry: Dictionary = _spots[index]
	var node := entry["node"] as Node3D
	match str(entry["kind"]):
		"window":
			var material := entry["material"] as StandardMaterial3D
			material.albedo_color.a = 0.85 * float(amount) / 100.0
			node.visible = amount > 0
		"shrink":
			var share := float(amount) / 100.0
			node.scale = (entry["full"] as Vector3) * maxf(share, 0.001)
			node.visible = amount > 0
		"gone":
			node.visible = amount > 0
		"paint":
			# Ten shades from faded to fresh, so panels share materials.
			var bucket := int(round(float(amount) / 10.0))
			if bucket == int(entry["bucket"]):
				return
			entry["bucket"] = bucket
			var color := FRESH_PAINT.lerp(FADED_PAINT, float(bucket) / 10.0)
			var material := _Surfaces.material("planks", color)
			for mesh: Node in node.find_children("*", "MeshInstance3D", true, false):
				(mesh as MeshInstance3D).set_meta("surface_base", color)
				(mesh as MeshInstance3D).material_override = material


# ---------------------------------------------------------------- grids

func add_lawn(grid: int) -> void:
	_lawns[grid] = null


func add_stains(grid: int) -> void:
	_stains[grid] = null


## Long grass on every lawn cell that needs mowing; short striped grass where it's done.
func _build_lawn(grid_index: int) -> void:
	var entry: Dictionary = _tasks.call("grid", grid_index)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = _Grass.tuft_mesh(0.55, 7)
	var mask: PackedByteArray = entry["mask"]
	var included := PackedInt32Array()
	for index: int in mask.size():
		if mask[index] == 1:
			included.append(index)
	multi.instance_count = included.size() * TUFTS_PER_CELL
	var view := MultiMeshInstance3D.new()
	view.multimesh = multi
	view.material_override = _Stylized.material({"wind": 0.07, "roughness": 1.0, "specular": 0.05, "translucency": 0.25, "double_sided": true})
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(view)
	view.global_transform = Transform3D.IDENTITY
	var slots: Dictionary = {}
	for slot: int in included.size():
		slots[included[slot]] = slot
	_lawns[grid_index] = {"multi": multi, "slots": slots, "entry": entry}
	var amounts: PackedByteArray = entry["amounts"]
	for cell: int in slots:
		_place_lawn_cell(grid_index, cell, amounts[cell])


func _place_lawn_cell(grid_index: int, cell: int, amount: int) -> void:
	var lawn: Dictionary = _lawns[grid_index]
	var entry: Dictionary = lawn["entry"]
	var slot := int((lawn["slots"] as Dictionary)[cell])
	var multi := lawn["multi"] as MultiMesh
	var width: int = entry["width"]
	var cell_size: float = entry["cell"]
	var corner: Vector3 = entry["corner"]
	var x := cell % width
	var z := cell / width
	var rng := RandomNumberGenerator.new()
	rng.seed = cell * 13 + grid_index
	var height := lerpf(MOWED_SCALE, 1.0, float(amount) / 100.0)
	# Mowed rows alternate a little lighter and darker: lawn stripes.
	var stripe := Color(1.06, 1.06, 0.98) if x % 2 == 0 else Color(0.9, 0.95, 0.9)
	var tint := Color.WHITE if amount > 0 else stripe
	for tuft: int in TUFTS_PER_CELL:
		var at := corner + Vector3((float(x) + rng.randf()) * cell_size, 0.0, (float(z) + rng.randf()) * cell_size)
		var size := rng.randf_range(0.8, 1.2)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size, size * height, size))
		multi.set_instance_transform(slot * TUFTS_PER_CELL + tuft, Transform3D(basis, at))
		multi.set_instance_color(slot * TUFTS_PER_CELL + tuft, tint)


## Dark blotches on the driveway that fade as the pressure washer hits them.
func _build_stains(grid_index: int) -> void:
	var entry: Dictionary = _tasks.call("grid", grid_index)
	var mask: PackedByteArray = entry["mask"]
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.75, 0.75)
	quad.orientation = PlaneMesh.FACE_Y
	multi.mesh = quad
	var included := PackedInt32Array()
	for index: int in mask.size():
		if mask[index] == 1:
			included.append(index)
	multi.instance_count = included.size()
	var material := StandardMaterial3D.new()
	material.albedo_texture = _grime_texture()
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.6
	var view := MultiMeshInstance3D.new()
	view.multimesh = multi
	view.material_override = material
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(view)
	view.global_transform = Transform3D.IDENTITY
	var slots: Dictionary = {}
	var width: int = entry["width"]
	var cell_size: float = entry["cell"]
	var corner: Vector3 = entry["corner"]
	for slot: int in included.size():
		var cell := included[slot]
		slots[cell] = slot
		var rng := RandomNumberGenerator.new()
		rng.seed = cell * 7 + 3
		var at := corner + Vector3((float(cell % width) + 0.5) * cell_size, 0.04, (float(cell / width) + 0.5) * cell_size)
		multi.set_instance_transform(slot, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.9, 1.5)), at))
	_stains[grid_index] = {"multi": multi, "slots": slots}
	var amounts: PackedByteArray = entry["amounts"]
	for cell: int in slots:
		_color_stain(grid_index, cell, amounts[cell])


func _color_stain(grid_index: int, cell: int, amount: int) -> void:
	var stains: Dictionary = _stains[grid_index]
	var slot := int((stains["slots"] as Dictionary)[cell])
	(stains["multi"] as MultiMesh).set_instance_color(slot, Color(0.16, 0.14, 0.12, 0.8 * float(amount) / 100.0))


func _on_cell_changed(grid_index: int, cell: int, amount: int) -> void:
	if _lawns.has(grid_index) and _lawns[grid_index] != null and (_lawns[grid_index]["slots"] as Dictionary).has(cell):
		_place_lawn_cell(grid_index, cell, amount)
	elif _stains.has(grid_index) and _stains[grid_index] != null and (_stains[grid_index]["slots"] as Dictionary).has(cell):
		_color_stain(grid_index, cell, amount)


# ---------------------------------------------------------------- effects

## A quick burst where work just landed, in the task's colors.
func work_fx(task: String, at: Vector3) -> void:
	var colors := {
		"wash_windows": [Color(0.6, 0.8, 1.0, 0.8), Vector3.UP, 1.5],
		"power_wash": [Color(0.85, 0.92, 1.0, 0.8), Vector3.UP, 2.5],
		"mow_lawn": [Color(0.4, 0.62, 0.25), Vector3(0.0, 1.0, 0.6), 2.5],
		"clean_gutters": [Color(0.38, 0.27, 0.16), Vector3.DOWN, 1.0],
		"trim_hedges": [Color(0.3, 0.52, 0.25), Vector3.UP, 2.0],
		"paint_fence": [Color(0.97, 0.96, 0.92), Vector3.UP, 0.8],
		"pull_weeds": [Color(0.4, 0.28, 0.18), Vector3.UP, 2.5],
		"pick_litter": [Color(0.9, 0.9, 0.85), Vector3.UP, 2.0],
	}
	var style: Array = colors.get(task, [Color.WHITE, Vector3.UP, 1.5])
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.amount = 14
	particles.lifetime = 0.7
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.06, 0.06, 0.06)
	particles.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = style[0]
	if (style[0] as Color).a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particles.material_override = material
	particles.direction = style[1]
	particles.spread = 45.0
	particles.initial_velocity_min = float(style[2]) * 0.5
	particles.initial_velocity_max = float(style[2])
	particles.gravity = Vector3(0.0, -7.0, 0.0)
	particles.emitting = true
	add_child(particles)
	particles.global_position = at
	get_tree().create_timer(1.0).timeout.connect(particles.queue_free)


# ---------------------------------------------------------------- meshes

static func _mesh(kind: String) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var kit := _MeshKit.new()
	var smooth := {"detail": 2, "lumps": 0.0, "flat": false, "jitter": 0.0}
	match kind:
		"gunk":
			kit.blob(Vector3(0.0, 0.05, 0.0), Vector3(0.45, 0.12, 0.12), Color(0.33, 0.24, 0.15), {"detail": 2, "lumps": 0.4, "lump_scale": 3.0, "flat": true, "soft": 0.5, "jitter": 0.05})
			for leaf: int in 7:
				kit.leaf_card(Vector3(-0.35 + float(leaf) * 0.12, 0.15, randf_range(-0.05, 0.05)), Vector3(0.0, 1.0, 0.3), 0.08, [Color(0.75, 0.38, 0.15), Color(0.55, 0.35, 0.18), Color(0.8, 0.6, 0.2)][leaf % 3], 0.0, randf() * TAU)
		"roof_leaves":
			for leaf: int in 26:
				var spot := Vector3(randf_range(-0.6, 0.6), randf_range(0.0, 0.12), randf_range(-0.6, 0.6))
				kit.leaf_card(spot, Vector3(randf_range(-0.3, 0.3), 1.0, randf_range(-0.3, 0.3)), randf_range(0.09, 0.14), [Color(0.88, 0.45, 0.15), Color(0.9, 0.7, 0.2), Color(0.72, 0.25, 0.14), Color(0.6, 0.38, 0.18)][leaf % 4], 0.0, randf() * TAU)
			kit.blob(Vector3(0.0, 0.03, 0.0), Vector3(0.45, 0.06, 0.45), Color(0.62, 0.36, 0.16), {"detail": 1, "lumps": 0.4, "lump_scale": 3.0, "flat": true, "jitter": 0.06})
		"weed":
			for blade: int in 9:
				var angle := TAU * float(blade) / 9.0
				var tip := Vector3(cos(angle) * 0.18, 0.32 + float(blade % 3) * 0.08, sin(angle) * 0.18)
				kit.tube(PackedVector3Array([Vector3.ZERO, tip * 0.5 + Vector3(0, 0.06, 0), tip]), PackedFloat32Array([0.025, 0.018, 0.004]), Color(0.32, 0.48, 0.18), 4, {"jitter": 0.05, "sway_to": 1.0})
			kit.blob(Vector3(0.05, 0.42, 0.0), Vector3(0.05, 0.04, 0.05), Color(0.98, 0.85, 0.2), {"detail": 1, "lumps": 0.4, "flat": true, "jitter": 0.0, "sway": 1.0})
		"shaggy":
			for tuft: int in 6:
				var spot := Vector3(randf_range(-0.6, 0.6), randf_range(0.0, 0.2), randf_range(-0.5, 0.5))
				kit.blob(spot, Vector3(0.22, 0.28, 0.22), Color(0.3, 0.5, 0.24).lightened(randf() * 0.1), {"detail": 1, "lumps": 0.5, "lump_scale": 3.0, "flat": true, "soft": 0.4, "jitter": 0.06, "sway": 1.0, "seed": tuft})
				kit.tube(PackedVector3Array([spot, spot + Vector3(randf_range(-0.2, 0.2), 0.45, randf_range(-0.2, 0.2))]), PackedFloat32Array([0.02, 0.008]), Color(0.36, 0.3, 0.2), 4, {"jitter": 0.0, "sway_to": 1.0})
		"can":
			kit.tube(PackedVector3Array([Vector3(-0.06, 0.035, 0), Vector3(0.06, 0.035, 0)]), PackedFloat32Array([0.034, 0.034]), [Color(0.85, 0.15, 0.15), Color(0.2, 0.5, 0.85), Color(0.3, 0.7, 0.3)][randi() % 3], 10, {"jitter": 0.0, "cap_start": true})
			kit.tube(PackedVector3Array([Vector3(0.06, 0.035, 0), Vector3(0.065, 0.035, 0)]), PackedFloat32Array([0.03, 0.03]), Color(0.8, 0.8, 0.82), 10, {"jitter": 0.0})
		"paper":
			kit.blob(Vector3(0.0, 0.05, 0.0), Vector3(0.07, 0.05, 0.07), Color(0.95, 0.94, 0.88), {"detail": 1, "lumps": 0.5, "lump_scale": 3.0, "flat": true, "jitter": 0.05})
		_:
			kit.tube(PackedVector3Array([Vector3(-0.1, 0.04, 0), Vector3(0.06, 0.04, 0), Vector3(0.12, 0.04, 0)]), PackedFloat32Array([0.04, 0.04, 0.015]), Color(0.35, 0.6, 0.35, 1.0), 10, {"jitter": 0.0, "cap_start": true})
	_meshes[kind] = kit.commit()
	return _meshes[kind]


## Blotchy grime, made once: soft spots and streaks.
static func _grime_texture() -> Texture2D:
	if _grime != null:
		return _grime
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.08
	for y: int in 64:
		for x: int in 64:
			var edge := minf(minf(float(x), 63.0 - float(x)), minf(float(y), 63.0 - float(y))) / 10.0
			var value := clampf(noise.get_noise_2d(x, y) * 0.9 + 0.55, 0.0, 1.0) * clampf(edge, 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, value))
	image.generate_mipmaps()
	_grime = ImageTexture.create_from_image(image)
	return _grime
