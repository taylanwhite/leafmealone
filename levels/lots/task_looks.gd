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
const _GrassPress = preload("res://leaves/grass_press.gd")
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
## shops:9: the seasonal grids (fertilize_lawn, seed_lawn, salt_walk): grid ->
## {task, layers: [{multi, slots, look}]}, null until setup builds them.
var _seasonal: Dictionary = {}
## The seed grid while overseeding is asked for: the lawn's tufts on its bare
## patches are dirt-short (_place_lawn_cell).
var _bare_grid: int = -1
## The feed grid while feeding is asked for: the lawn's tufts are tinted by it.
var _feed_grid: int = -1
static var _grime: Texture2D
static var _speckle: Texture2D
static var _meshes: Dictionary = {}


func _ready() -> void:
	add_to_group("task_looks")


func setup(tasks: Node) -> void:
	_tasks = tasks
	tasks.connect("spot_changed", _on_spot_changed)
	tasks.connect("cell_changed", _on_cell_changed)
	for index: int in _spots:
		_on_spot_changed(index, int(tasks.call("spot", index)["amount"]))
	# shops:9: before the lawn, which leaves the bare patches bare.
	for grid: Variant in _seasonal.keys():
		_build_seasonal(int(grid))
	for grid: int in _lawns:
		_build_lawn(grid)
	for grid: int in _stains:
		_build_stains(grid)


# ---------------------------------------------------------------- spots

## Grime on a window facing normal. size: the window's (HouseSpec "windows"),
## the grime a little bigger; zero for the classic house's two sizes.
func add_window(index: int, at: Vector3, normal: Vector3, size: Vector2 = Vector2.ZERO) -> void:
	var quad := QuadMesh.new()
	if size.x > 0.0 and size.y > 0.0:
		quad.size = size + Vector2(0.08, 0.07)
	else:
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


## A fence panel the paint task refreshes from faded to fresh (the hood's own
## colors and surface: levels/town/hood_styles.gd "job_fence").
func add_fence_panel(index: int, holder: Node3D, fresh: Color = FRESH_PAINT, faded: Color = FADED_PAINT, surface: String = "planks") -> void:
	_spots[index] = {"kind": "paint", "node": holder, "bucket": -1, "fresh": fresh, "faded": faded, "surface": surface}


func add_litter(index: int, at: Vector3, seed_value: int) -> void:
	var kinds := ["can", "paper", "bottle"]
	var view := _Stylized.instance(_mesh(kinds[absi(seed_value) % kinds.size()]), {"roughness": 0.5, "specular": 0.4})
	add_child(view)
	view.global_position = at
	view.rotation = Vector3(0.0, float(seed_value % 628) / 100.0, 0.0)
	_spots[index] = {"kind": "gone", "node": view}


## A big yard's above-ground pool: a ribbed blue wall, a white rim, and water.
func add_pool(at: Vector3, radius: float, height: float) -> void:
	var kit := _MeshKit.new()
	var ring := PackedVector3Array()
	var sides := 28
	for side: int in sides + 1:
		var angle := TAU * float(side) / float(sides)
		ring.append(Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))
	# The wall, as upright panels with a post between each.
	for side: int in sides:
		var a := ring[side]
		var b := ring[side + 1]
		var middle := (a + b) * 0.5
		var facing := Basis.looking_at(middle.normalized(), Vector3.UP)
		kit.box(middle + Vector3(0.0, height * 0.5, 0.0), Vector3(a.distance_to(b) + 0.02, height, 0.05), Color(0.32, 0.58, 0.82), facing)
		kit.tube(PackedVector3Array([a * 1.03, a * 1.03 + Vector3(0.0, height + 0.02, 0.0)]), PackedFloat32Array([0.045, 0.045]), Color(0.9, 0.92, 0.94), 6, {"jitter": 0.0})
	var rim := PackedFloat32Array()
	rim.resize(ring.size())
	rim.fill(0.08)
	kit.tube(ring_up(ring, height + 0.03), rim, Color(0.95, 0.96, 0.97), 6, {"jitter": 0.0})
	var view := _Stylized.instance(kit.commit(), {"roughness": 0.45, "specular": 0.4})
	view.name = "Pool"
	add_child(view)
	view.global_position = at
	var water := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius - 0.04
	disc.bottom_radius = radius - 0.04
	disc.height = 0.04
	disc.radial_segments = 32
	water.mesh = disc
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.35, 0.72, 0.85, 0.82)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.08
	material.metallic_specular = 0.9
	water.material_override = material
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	water.global_position = at + Vector3(0.0, height - 0.14, 0.0)


static func ring_up(ring: PackedVector3Array, height: float) -> PackedVector3Array:
	var raised := PackedVector3Array()
	for point: Vector3 in ring:
		raised.append(point + Vector3(0.0, height, 0.0))
	return raised


## A clump of leaves floating in the pool, gone once it's scooped out.
func add_pool_leaves(index: int, at: Vector3, seed_value: int) -> void:
	var view := _Stylized.instance(_mesh("pool_leaves"), {"roughness": 0.4, "specular": 0.5, "double_sided": true})
	add_child(view)
	view.global_position = at
	view.rotation.y = float(absi(seed_value) % 628) / 100.0
	_spots[index] = {"kind": "gone", "node": view}


## A spot's look flies from one place to another in an arc (litter flung by the mower).
func fling(index: int, from: Vector3, to: Vector3) -> void:
	if not _spots.has(index):
		return
	var node := _spots[index]["node"] as Node3D
	var tween := create_tween()
	tween.tween_method(func(t: float) -> void:
		if is_instance_valid(node):
			node.global_position = from.lerp(to, t) + Vector3.UP * sin(t * PI) * 2.5
			node.rotation = Vector3(t * 14.0, t * 9.0, 0.0)
	, 0.0, 1.0, 0.7)


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
			var color := (entry.get("fresh", FRESH_PAINT) as Color).lerp(entry.get("faded", FADED_PAINT), float(bucket) / 10.0)
			var material := _Surfaces.material(str(entry.get("surface", "planks")), color)
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
	# Long grass lies flat under the leaves too (raking:2, leaves/grass_press.gd).
	view.material_override = _GrassPress.material({"wind": 0.07, "roughness": 1.0, "specular": 0.05, "translucency": 0.25, "double_sided": true})
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
	# shops:9: a lawn waiting to be fed is straw-yellow under the green, and
	# greens up as the prills land (the tufts show it, however tall they stand).
	if _feed_grid >= 0:
		tint = tint * Color.WHITE.lerp(HUNGRY_TINT, _feed_left(corner + Vector3((float(x) + 0.5) * cell_size, 0.0, (float(z) + 0.5) * cell_size)))
	# shops:9: a bare patch waiting for seed has only stubble, gone brown.
	if _bare_grid >= 0 and _is_bare(corner + Vector3((float(x) + 0.5) * cell_size, 0.0, (float(z) + 0.5) * cell_size)):
		height = BARE_STUBBLE
		tint = BARE_TINT
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
	elif _seasonal.has(grid_index) and _seasonal[grid_index] != null:
		_color_seasonal(grid_index, cell, amount)


# ---------------------------------------------------------------- seasonal work (shops:9)

## How short a bare patch's stubble stands (a share of uncut grass), and its tint.
const BARE_STUBBLE: float = 0.06
const BARE_TINT := Color(0.62, 0.5, 0.34)
## A hungry lawn's tufts, multiplied in where it hasn't been fed (all of it at the start).
const HUNGRY_TINT := Color(1.3, 1.08, 0.42)
## Each seasonal task's look, layer by layer: what's left to do fades out as the
## cells are worked ("left"), what was spread fades in ("done"), or stays put
## ("always"). Per layer: the quad's size (in cells), its height over the
## ground (m), its texture (grime: soft blotches, speckle: granules), its color
## at full strength, and whether it's glossy (ice).
## - fertilize_lawn: a hungry lawn's straw-yellow blotches give way to blue-white prills.
## - seed_lawn: brown bare patches stay brown, and fill with straw-colored seed.
## - salt_walk: glossy ice on the drive gives way to wet, dark concrete and white salt.
const SEASONAL_LOOKS: Dictionary = {
	"fertilize_lawn": [
		{"when": "left", "size": 1.25, "y": 0.02, "texture": "grime", "color": Color(0.82, 0.74, 0.3, 0.6)},
		{"when": "done", "size": 1.0, "y": 0.026, "texture": "speckle", "color": Color(0.86, 0.92, 1.0, 1.0)},
	],
	"seed_lawn": [
		{"when": "always", "size": 1.7, "y": 0.018, "texture": "grime", "color": Color(0.42, 0.3, 0.19, 0.95)},
		{"when": "done", "size": 1.2, "y": 0.024, "texture": "speckle", "color": Color(0.93, 0.84, 0.52, 1.0)},
	],
	"salt_walk": [
		{"when": "left", "size": 1.7, "y": 0.042, "texture": "grime", "color": Color(0.5, 0.7, 0.95, 0.85), "gloss": true},
		{"when": "done", "size": 1.5, "y": 0.041, "texture": "grime", "color": Color(0.2, 0.21, 0.24, 0.6)},
		{"when": "done", "size": 1.0, "y": 0.046, "texture": "speckle", "color": Color(0.98, 0.98, 0.96, 1.0)},
	],
}


## shops:9: a seasonal grid (lot_generator.gd _seasonal_grids). It's drawn only
## when the homeowner asked for it; a yard that didn't shows nothing of it.
func add_seasonal(grid: int) -> void:
	_seasonal[grid] = null


func _build_seasonal(grid_index: int) -> void:
	var entry: Dictionary = _tasks.call("grid", grid_index)
	var task := str(entry["task"])
	if not (_tasks.get("active") as PackedStringArray).has(task) or not SEASONAL_LOOKS.has(task):
		_seasonal.erase(grid_index)
		return
	if task == "seed_lawn":
		_bare_grid = grid_index
	if task == "fertilize_lawn":
		_feed_grid = grid_index
	var mask: PackedByteArray = entry["mask"]
	var included := PackedInt32Array()
	for index: int in mask.size():
		if mask[index] == 1:
			included.append(index)
	var slots: Dictionary = {}
	for slot: int in included.size():
		slots[included[slot]] = slot
	var width: int = entry["width"]
	var cell_size: float = entry["cell"]
	var corner: Vector3 = entry["corner"]
	var layers: Array = []
	for look: Dictionary in (SEASONAL_LOOKS[task] as Array):
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * cell_size * float(look["size"])
		quad.orientation = PlaneMesh.FACE_Y
		multi.mesh = quad
		multi.instance_count = included.size()
		var material := StandardMaterial3D.new()
		material.albedo_texture = _speckle_texture() if str(look["texture"]) == "speckle" else _grime_texture()
		material.vertex_color_use_as_albedo = true
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.roughness = 0.06 if bool(look.get("gloss", false)) else 0.8
		material.metallic_specular = 0.9 if bool(look.get("gloss", false)) else 0.3
		var view := MultiMeshInstance3D.new()
		view.multimesh = multi
		view.material_override = material
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		view.name = "Seasonal_%s_%d" % [task, layers.size()]
		add_child(view)
		view.global_transform = Transform3D.IDENTITY
		for slot: int in included.size():
			var cell := included[slot]
			var rng := RandomNumberGenerator.new()
			rng.seed = cell * 31 + grid_index * 7 + layers.size()
			var at := corner + Vector3((float(cell % width) + 0.5) * cell_size, float(look["y"]), (float(cell / width) + 0.5) * cell_size)
			at += Vector3(rng.randf_range(-0.2, 0.2), 0.0, rng.randf_range(-0.2, 0.2)) * cell_size
			multi.set_instance_transform(slot, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.85, 1.2)), at))
		layers.append({"multi": multi, "look": look})
	_seasonal[grid_index] = {"task": task, "slots": slots, "layers": layers}
	var amounts: PackedByteArray = entry["amounts"]
	for cell: int in slots:
		_color_seasonal(grid_index, cell, amounts[cell])


func _color_seasonal(grid_index: int, cell: int, amount: int) -> void:
	var data: Dictionary = _seasonal[grid_index]
	var slots: Dictionary = data["slots"]
	if not slots.has(cell):
		return
	var left := float(amount) / 100.0
	for layer: Dictionary in (data["layers"] as Array):
		var look: Dictionary = layer["look"]
		var color: Color = look["color"]
		var share := 1.0
		match str(look["when"]):
			"left":
				share = left
			"done":
				share = 1.0 - left
		(layer["multi"] as MultiMesh).set_instance_color(int(slots[cell]), Color(color.r, color.g, color.b, color.a * share))
	if grid_index == _feed_grid:
		_retint_lawn_under(grid_index, cell)


## The lawn's 1 m cells under one feed cell, placed again for its new tint.
func _retint_lawn_under(grid_index: int, cell: int) -> void:
	var feed: Dictionary = _tasks.call("grid", grid_index)
	var size := float(feed["cell"])
	var origin := (feed["corner"] as Vector3) + Vector3(float(cell % int(feed["width"])) * size, 0.0, float(cell / int(feed["width"])) * size)
	for lawn_index: Variant in _lawns:
		var lawn: Variant = _lawns[lawn_index]
		if lawn == null:
			continue
		var entry: Dictionary = (lawn as Dictionary)["entry"]
		var step := float(entry["cell"])
		var corner: Vector3 = entry["corner"]
		var slots: Dictionary = (lawn as Dictionary)["slots"]
		var amounts: PackedByteArray = entry["amounts"]
		var from := Vector2i(floori((origin.x - corner.x) / step + 0.01), floori((origin.z - corner.z) / step + 0.01))
		var count := maxi(roundi(size / step), 1)
		for dz: int in count:
			for dx: int in count:
				var x := from.x + dx
				var z := from.y + dz
				if x < 0 or z < 0 or x >= int(entry["width"]) or z >= int(entry["depth"]):
					continue
				var index := x + z * int(entry["width"])
				if slots.has(index):
					_place_lawn_cell(int(lawn_index), index, amounts[index])


## How much feeding is left where a world point is (0 to 1; 0 off the feed grid).
func _feed_left(at: Vector3) -> float:
	var entry: Dictionary = _tasks.call("grid", _feed_grid)
	var cell := float(entry["cell"])
	var local := at - (entry["corner"] as Vector3)
	var x := int(floor(local.x / cell))
	var z := int(floor(local.z / cell))
	if x < 0 or z < 0 or x >= int(entry["width"]) or z >= int(entry["depth"]):
		return 0.0
	return float((entry["amounts"] as PackedByteArray)[x + z * int(entry["width"])]) / 100.0


## Whether a world point is on a bare patch of the seed grid (_bare_grid).
func _is_bare(at: Vector3) -> bool:
	var entry: Dictionary = _tasks.call("grid", _bare_grid)
	var cell := float(entry["cell"])
	var local := at - (entry["corner"] as Vector3)
	var x := int(floor(local.x / cell))
	var z := int(floor(local.z / cell))
	if x < 0 or z < 0 or x >= int(entry["width"]) or z >= int(entry["depth"]):
		return false
	return (entry["mask"] as PackedByteArray)[x + z * int(entry["width"])] == 1


## Granules, made once: a scatter of small dots on nothing.
static func _speckle_texture() -> Texture2D:
	if _speckle != null:
		return _speckle
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	for _dot: int in 70:
		var center := Vector2(rng.randf_range(5.0, 59.0), rng.randf_range(5.0, 59.0))
		var radius := rng.randf_range(0.9, 1.8)
		var shade := rng.randf_range(0.82, 1.0)
		for y: int in range(int(center.y - 3.0), int(center.y + 4.0)):
			for x: int in range(int(center.x - 3.0), int(center.x + 4.0)):
				var d := Vector2(x, y).distance_to(center)
				if d <= radius:
					image.set_pixel(x, y, Color(shade, shade, shade, 1.0))
	image.generate_mipmaps()
	_speckle = ImageTexture.create_from_image(image)
	return _speckle


# ---------------------------------------------------------------- effects

## What task work sounds like at the spot (audio chunk 6; tools/sfx_foley.py).
## The mower, the pressure washer and the roller have their own running loops
## (audio/tool_sound.gd), so they have none here.
const TASK_SOUNDS: Dictionary = {
	"pick_litter": "litter_crinkle", "pull_weeds": "weed_pluck", "clean_gutters": "gutter_gloop",
	"wash_windows": "squeegee", "trim_hedges": "snip", "skim_pool": "splash_small", "clear_roof": "rake",
}
## "task:patch" -> the msec before which that patch's task sound waits.
var _sound_next: Dictionary = {}


## A quick burst where work just landed, in the task's colors, and its sound
## (TASK_SOUNDS) unless with_sound is false (a mower hitting things borrows the
## bursts, net_prop.gd _rpc_mower_fx, and has its own sounds).
func work_fx(task: String, at: Vector3, with_sound := true) -> void:
	if with_sound:
		_work_sound(task, at)
	var colors := {
		"wash_windows": [Color(0.6, 0.8, 1.0, 0.8), Vector3.UP, 1.5],
		"power_wash": [Color(0.85, 0.92, 1.0, 0.8), Vector3.UP, 2.5],
		"mow_lawn": [Color(0.4, 0.62, 0.25), Vector3(0.0, 1.0, 0.6), 2.5],
		"clean_gutters": [Color(0.38, 0.27, 0.16), Vector3.DOWN, 1.0],
		"trim_hedges": [Color(0.3, 0.52, 0.25), Vector3.UP, 2.0],
		"paint_fence": [Color(0.97, 0.96, 0.92), Vector3.UP, 0.8],
		"pull_weeds": [Color(0.4, 0.28, 0.18), Vector3.UP, 2.5],
		"pick_litter": [Color(0.9, 0.9, 0.85), Vector3.UP, 2.0],
		"skim_pool": [Color(0.6, 0.85, 1.0, 0.85), Vector3.UP, 2.2],
		# shops:9: granules bouncing where the throw lands (the throw itself is the sack's).
		"fertilize_lawn": [Color(0.86, 0.92, 1.0), Vector3.UP, 0.9],
		"seed_lawn": [Color(0.93, 0.84, 0.52), Vector3.UP, 0.8],
		"salt_walk": [Color(0.98, 0.98, 0.96), Vector3.UP, 1.1],
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


## A task's sound at the spot, held to its gap per patch (Constants.
## TASK_SFX_GAP_MS, TASK_SFX_PATCH_METERS), so two of the crew on two windows both squeak and one held
## trimmer doesn't buzz-saw the snips together.
func _work_sound(task: String, at: Vector3) -> void:
	var id := str(TASK_SOUNDS.get(task, ""))
	var sfx := get_tree().get_first_node_in_group("sfx")
	if id == "" or sfx == null:
		return
	var patch := Vector2i(floori(at.x / Constants.TASK_SFX_PATCH_METERS), floori(at.z / Constants.TASK_SFX_PATCH_METERS))
	var key := "%s:%d:%d" % [task, patch.x, patch.y]
	var now := Time.get_ticks_msec()
	if now < int(_sound_next.get(key, 0)):
		return
	_sound_next[key] = now + int(Constants.TASK_SFX_GAP_MS.get(id, Constants.SFX_DEFAULT_GAP_MS))
	if _sound_next.size() > Constants.TASK_SFX_PATCH_MEMORY:
		for old: String in _sound_next.keys():
			if int(_sound_next[old]) < now:
				_sound_next.erase(old)
	sfx.call("play_at", id, at, 0.0, true, 1 + posmod(patch.x, 1000) * 1000 + posmod(patch.y, 1000))


# ---------------------------------------------------------------- meshes

## The cached mesh for a task look (gunk, pool_leaves, roof_leaves, weed, shaggy,
## can, paper, bottle), read-only: tools/studio/icon_recipes.gd builds the task
## badges' vignettes from these.
static func mesh(kind: String) -> ArrayMesh:
	return _mesh(kind)


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
		"pool_leaves":
			for leaf: int in 14:
				var spot := Vector3(randf_range(-0.45, 0.45), randf_range(0.0, 0.03), randf_range(-0.45, 0.45))
				kit.leaf_card(spot, Vector3(randf_range(-0.15, 0.15), 1.0, randf_range(-0.15, 0.15)), randf_range(0.1, 0.15), [Color(0.88, 0.45, 0.15), Color(0.9, 0.7, 0.2), Color(0.72, 0.25, 0.14), Color(0.55, 0.4, 0.2)][leaf % 4], 0.0, randf() * TAU)
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
