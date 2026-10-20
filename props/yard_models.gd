extends RefCounted

## Authority: local, cosmetic. Modeled meshes for things in and around the yard,
## built with props/mesh_kit.gd and drawn with props/stylized.gd: the rake, leaf
## bags, trash cans, the wheelbarrow, the gnome, hiding spots (a shed, a wheelie
## dumpster, a hedge), cars, and fence runs. Each returns a node to add where it
## goes; meshes are cached per kind and color, so many copies cost one build.
## Art rules: docs/ART.md. 1 unit = 1 meter, Y up, faces -Z, origin at the base.

const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")

const WOOD := Color(0.66, 0.48, 0.3)
const STEEL := Color(0.62, 0.64, 0.66)
const KRAFT := Color(0.72, 0.55, 0.34)
const LEAVES: Array[Color] = [Color(0.9, 0.48, 0.15), Color(0.93, 0.72, 0.22), Color(0.75, 0.25, 0.14)]
const SMOOTH := {"detail": 2, "lumps": 0.0, "flat": false, "jitter": 0.0}

static var _cache: Dictionary = {}


static func node(kind: String, color: Color = Color.WHITE, size: Vector3 = Vector3.ONE, options: Dictionary = {}) -> MeshInstance3D:
	var key := "%s|%s|%s" % [kind, color.to_html(), size]
	if not _cache.has(key):
		_cache[key] = _build(kind, color, size)
	return _Stylized.instance(_cache[key], options if not options.is_empty() else {"roughness": 0.8, "specular": 0.15})


static func _build(kind: String, color: Color, size: Vector3) -> ArrayMesh:
	var kit := _MeshKit.new()
	match kind:
		"rake":
			_rake(kit)
		"leaf_bag":
			_leaf_bag(kit)
		"trash":
			_trash_can(kit, color)
		"wheelbarrow":
			_wheelbarrow(kit, color)
		"gnome":
			_gnome(kit)
		"shed":
			_shed(kit, color, size)
		"dumpster":
			_dumpster(kit, color, size)
		"hedge":
			_hedge(kit, color, size)
		"car":
			_car(kit, color)
		"fence":
			_fence(kit, color, size)
		"leaf_blower":
			_leaf_blower(kit)
		"lawn_mower":
			_lawn_mower(kit)
		"ladder":
			_ladder(kit)
		"hose":
			_hose(kit)
		"pressure_washer":
			_pressure_washer(kit)
		"hedge_trimmer":
			_hedge_trimmer(kit)
		"paint_roller":
			_paint_roller(kit)
		"hydrant":
			_hydrant(kit)
		"spigot":
			_spigot(kit)
		"water_tank":
			_water_tank(kit)
		"nozzle":
			_nozzle(kit)
		_:
			kit.rbox(Vector3(0.0, size.y * 0.5, 0.0), size * 0.5, color, 6.0)
	return kit.commit()


## The job's one rake, standing up: a wooden handle with a rubber grip, a metal
## collar, and a fan of springy tines curling forward at the tips.
static func _rake(kit: RefCounted) -> void:
	kit.call("tube", PackedVector3Array([Vector3(0, 0.14, 0), Vector3(0, 0.9, 0), Vector3(0, 1.58, 0)]), PackedFloat32Array([0.022, 0.022, 0.021]), WOOD, 8, {"jitter": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(0, 1.42, 0), Vector3(0, 1.62, 0)]), PackedFloat32Array([0.03, 0.03]), Color(0.85, 0.3, 0.15), 8, {"jitter": 0.0, "cap_start": true})
	kit.call("tube", PackedVector3Array([Vector3(0, 0.1, 0), Vector3(0, 0.2, 0)]), PackedFloat32Array([0.03, 0.026]), STEEL, 8, {"jitter": 0.0, "cap_start": true})
	var tines := 15
	var tine_color := Color(0.25, 0.6, 0.32)
	for index: int in tines:
		var spread := lerpf(-1.0, 1.0, float(index) / float(tines - 1))
		var mid := Vector3(spread * 0.2, -0.02, 0.0)
		var tip := Vector3(spread * 0.4, -0.22 + absf(spread) * 0.06, -0.05)
		var curl := tip + Vector3(spread * 0.01, -0.04, -0.07)
		kit.call("tube", PackedVector3Array([Vector3(spread * 0.02, 0.11, 0.0), mid, tip, curl]), PackedFloat32Array([0.012, 0.012, 0.011, 0.01]), tine_color, 5, {"jitter": 0.0})
	# The cross wire that holds the fan in shape.
	var wire := PackedVector3Array()
	var radii := PackedFloat32Array()
	for step: int in 9:
		var spread := lerpf(-1.0, 1.0, float(step) / 8.0)
		wire.append(Vector3(spread * 0.3, -0.1 + absf(spread) * 0.025, -0.01))
		radii.append(0.011)
	kit.call("tube", wire, radii, STEEL.darkened(0.15), 4, {"jitter": 0.0})


## A brown paper lawn bag, stuffed full, rim rolled over, leaves poking out.
static func _leaf_bag(kit: RefCounted) -> void:
	kit.call("blob", Vector3(0.0, 0.38, 0.0), Vector3(0.27, 0.38, 0.23), KRAFT, {"detail": 2, "lumps": 0.12, "lump_scale": 1.6, "flat": false, "jitter": 0.0, "seed": 3})
	kit.call("rbox", Vector3(0.0, 0.42, 0.0), Vector3(0.25, 0.36, 0.21), KRAFT, 4.0)
	kit.call("tube", PackedVector3Array([Vector3(0, 0.74, 0), Vector3(0, 0.8, 0)]), PackedFloat32Array([0.25, 0.25]), KRAFT.darkened(0.12), 14, {"jitter": 0.0})
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for index: int in 9:
		var at := Vector3(rng.randf_range(-0.16, 0.16), 0.8 + rng.randf_range(0.0, 0.06), rng.randf_range(-0.13, 0.13))
		kit.call("leaf_card", at, Vector3(rng.randf_range(-0.6, 0.6), 1.0, rng.randf_range(-0.6, 0.6)), rng.randf_range(0.07, 0.1), LEAVES[index % LEAVES.size()], 0.0, rng.randf() * TAU)
	# A printed band so it reads as a lawn bag from across the yard.
	kit.call("tube", PackedVector3Array([Vector3(0, 0.3, 0), Vector3(0, 0.38, 0)]), PackedFloat32Array([0.262, 0.262]), Color(0.3, 0.45, 0.22), 14, {"jitter": 0.0, "cap": false})


static func _trash_can(kit: RefCounted, color: Color) -> void:
	kit.call("tube", PackedVector3Array([Vector3(0, 0.0, 0), Vector3(0, 0.66, 0)]), PackedFloat32Array([0.27, 0.31]), color, 16, {"jitter": 0.0, "cap_start": true, "cap": false})
	for y: float in [0.16, 0.36, 0.56]:
		kit.call("tube", PackedVector3Array([Vector3(0, y - 0.015, 0), Vector3(0, y + 0.015, 0)]), PackedFloat32Array([0.285 + y * 0.06, 0.285 + y * 0.06]), color.darkened(0.15), 16, {"jitter": 0.0, "cap": false})
	kit.call("blob", Vector3(0.0, 0.68, 0.0), Vector3(0.34, 0.07, 0.34), color.lightened(0.05), SMOOTH)
	kit.call("rbox", Vector3(0.0, 0.77, 0.0), Vector3(0.11, 0.025, 0.03), color.darkened(0.3), 4.0)
	for side: float in [-1.0, 1.0]:
		kit.call("rbox", Vector3(side * 0.33, 0.55, 0.0), Vector3(0.03, 0.025, 0.08), color.darkened(0.3), 4.0)


## Tray up top, one wheel at the front (-Z), handles and legs at the back.
static func _wheelbarrow(kit: RefCounted, color: Color) -> void:
	var tilt := Basis(Vector3.RIGHT, 0.0)
	kit.call("rbox", Vector3(0.0, 0.43, 0.0), Vector3(0.3, 0.035, 0.4), color, 6.0)
	for side: float in [-1.0, 1.0]:
		kit.call("rbox", Vector3(side * 0.36, 0.56, 0.0), Vector3(0.03, 0.15, 0.43), color, 6.0, {"basis": Basis(Vector3.FORWARD, side * 0.3)})
	kit.call("rbox", Vector3(0.0, 0.56, -0.46), Vector3(0.36, 0.15, 0.03), color, 6.0, {"basis": Basis(Vector3.RIGHT, -0.35)})
	kit.call("rbox", Vector3(0.0, 0.56, 0.44), Vector3(0.36, 0.15, 0.03), color, 6.0, {"basis": tilt})
	# A rolled rim along the top edge.
	kit.call("rbox", Vector3(0.0, 0.71, 0.45), Vector3(0.42, 0.025, 0.025), color.darkened(0.15), 4.0)
	kit.call("rbox", Vector3(0.0, 0.71, -0.52), Vector3(0.42, 0.025, 0.025), color.darkened(0.15), 4.0)
	for side: float in [-1.0, 1.0]:
		kit.call("tube", PackedVector3Array([Vector3(side * 0.12, 0.3, -0.62), Vector3(side * 0.2, 0.38, 0.0), Vector3(side * 0.24, 0.48, 0.75), Vector3(side * 0.25, 0.52, 0.95)]), PackedFloat32Array([0.022, 0.022, 0.022, 0.026]), WOOD.darkened(0.1), 6, {"jitter": 0.0})
		kit.call("blob", Vector3(side * 0.25, 0.525, 0.98), Vector3(0.03, 0.03, 0.07), Color(0.15, 0.15, 0.16), SMOOTH)
		kit.call("tube", PackedVector3Array([Vector3(side * 0.22, 0.4, 0.35), Vector3(side * 0.24, 0.0, 0.42)]), PackedFloat32Array([0.018, 0.018]), STEEL.darkened(0.3), 6, {"jitter": 0.0})
	kit.call("wheel", Vector3(0.0, 0.19, -0.62), 0.19, 0.1, Color(0.12, 0.12, 0.13), Color(0.8, 0.75, 0.2))


## A garden gnome: red pointy hat, white beard, round nose, blue coat, boots.
static func _gnome(kit: RefCounted) -> void:
	kit.call("blob", Vector3(-0.07, 0.04, -0.03), Vector3(0.07, 0.04, 0.1), Color(0.3, 0.2, 0.15), SMOOTH)
	kit.call("blob", Vector3(0.07, 0.04, -0.03), Vector3(0.07, 0.04, 0.1), Color(0.3, 0.2, 0.15), SMOOTH)
	kit.call("blob", Vector3(0.0, 0.2, 0.0), Vector3(0.17, 0.17, 0.15), Color(0.25, 0.42, 0.78), SMOOTH)
	kit.call("tube", PackedVector3Array([Vector3(0, 0.15, 0), Vector3(0, 0.19, 0)]), PackedFloat32Array([0.175, 0.17]), Color(0.25, 0.2, 0.15), 14, {"jitter": 0.0})
	kit.call("blob", Vector3(0.0, 0.43, 0.0), Vector3(0.13, 0.12, 0.12), Color(0.96, 0.8, 0.68), SMOOTH)
	kit.call("blob", Vector3(0.0, 0.33, -0.07), Vector3(0.13, 0.14, 0.08), Color(0.97, 0.97, 0.95), {"detail": 2, "lumps": 0.2, "lump_scale": 3.0, "outward": true, "flat": false, "jitter": 0.0})
	kit.call("blob", Vector3(0.0, 0.42, -0.125), Vector3(0.04, 0.035, 0.035), Color(0.95, 0.55, 0.5), SMOOTH)
	for side: float in [-1.0, 1.0]:
		kit.call("blob", Vector3(side * 0.05, 0.47, -0.11), Vector3(0.016, 0.02, 0.01), Color(0.05, 0.05, 0.06), SMOOTH)
		kit.call("blob", Vector3(side * 0.16, 0.24, -0.02), Vector3(0.05, 0.08, 0.05), Color(0.25, 0.42, 0.78), SMOOTH)
	kit.call("cone", Vector3(0.0, 0.5, 0.01), 0.15, 0.36, Color(0.85, 0.16, 0.12), 14, {"lumps": 0.0})


## A garden shed filling size: plank walls, a pitched roof with overhangs, a
## door with a handle, and a little window.
static func _shed(kit: RefCounted, color: Color, size: Vector3) -> void:
	var half := size * 0.5
	var wall_height := size.y * 0.72
	kit.call("rbox", Vector3(0.0, wall_height * 0.5, 0.0), Vector3(half.x, wall_height * 0.5, half.z), color, 14.0)
	# Vertical board seams on the front and sides.
	for index: int in int(size.x / 0.25):
		var x := -half.x + 0.125 + float(index) * 0.25
		kit.call("rbox", Vector3(x, wall_height * 0.5, -half.z - 0.005), Vector3(0.008, wall_height * 0.48, 0.008), color.darkened(0.25), 4.0)
	var roof_color := Color(0.32, 0.27, 0.25)
	var rise := size.y - wall_height
	var slope := atan2(rise, half.x)
	var panel := Vector2(half.x + 0.25, rise).length()
	for side: float in [-1.0, 1.0]:
		kit.call("rbox", Vector3(side * (half.x * 0.5 + 0.06), wall_height + rise * 0.5, 0.0), Vector3(panel * 0.5 + 0.06, 0.05, half.z + 0.25), roof_color, 6.0, {"basis": Basis(Vector3.BACK, -side * slope)})
	# Gable ends, door, handle, and window.
	kit.call("cone", Vector3(0.0, wall_height, -half.z + 0.02), half.x, rise * 0.98, color, 4, {"lumps": 0.0, "top_radius": 0.0})
	kit.call("rbox", Vector3(0.0, wall_height * 0.42, -half.z - 0.03), Vector3(0.42, wall_height * 0.42, 0.03), color.darkened(0.18), 6.0)
	kit.call("rbox", Vector3(0.3, wall_height * 0.42, -half.z - 0.07), Vector3(0.03, 0.05, 0.03), STEEL, 4.0)
	kit.call("rbox", Vector3(half.x + 0.01, wall_height * 0.62, 0.0), Vector3(0.03, 0.22, 0.3), Color(0.22, 0.28, 0.34), 6.0, {"shade": false})


## A wheelie dumpster filling size: a rounded bin with a lid hinged at the back,
## a front lip, and wheels.
static func _dumpster(kit: RefCounted, color: Color, size: Vector3) -> void:
	var half := size * 0.5
	kit.call("rbox", Vector3(0.0, half.y * 0.95, 0.0), Vector3(half.x, half.y * 0.85, half.z), color, 5.0)
	kit.call("rbox", Vector3(0.0, size.y * 0.93, 0.03), Vector3(half.x + 0.04, 0.05, half.z + 0.05), color.darkened(0.2), 5.0, {"basis": Basis(Vector3.RIGHT, 0.04)})
	kit.call("rbox", Vector3(0.0, size.y * 0.84, -half.z - 0.03), Vector3(half.x * 0.85, 0.04, 0.04), color.darkened(0.3), 4.0)
	for side: float in [-1.0, 1.0]:
		for z: float in [-half.z * 0.6, half.z * 0.6]:
			kit.call("wheel", Vector3(side * (half.x - 0.12), 0.1, z), 0.1, 0.08, Color(0.12, 0.12, 0.13), STEEL)
	# Pockets in the sides, the way molded bins have them.
	for side: float in [-1.0, 1.0]:
		kit.call("rbox", Vector3(side * (half.x + 0.005), half.y, 0.0), Vector3(0.02, half.y * 0.45, half.z * 0.7), color.darkened(0.12), 6.0)


## A clipped hedge filling size: lumpy, with lighter tips on top.
static func _hedge(kit: RefCounted, color: Color, size: Vector3) -> void:
	var half := size * 0.5
	var long_axis_x := size.x >= size.z
	var length := size.x if long_axis_x else size.z
	var count := maxi(1, int(ceil(length / 0.9)))
	for index: int in count:
		var t := (float(index) + 0.5) / float(count) - 0.5
		var at := Vector3(t * length, half.y, 0.0) if long_axis_x else Vector3(0.0, half.y, t * length)
		var lump := maxf(length / float(count) * 0.7, 0.45)
		var radius := Vector3(lump, half.y * 1.02, half.z * 1.05) if long_axis_x else Vector3(half.x * 1.05, half.y * 1.02, lump)
		kit.call("blob", at, radius, color.lightened(0.04 * float(index % 2)), {"detail": 2, "lumps": 0.22, "lump_scale": 2.6, "flat": true, "soft": 0.7, "jitter": 0.03, "seed": index})
	kit.call("grade", 0, 0.0, size.y, 0.65, 1.12)


## A rounded little sedan, facing -Z.
static func _car(kit: RefCounted, color: Color) -> void:
	var glass := Color(0.2, 0.26, 0.32)
	kit.call("rbox", Vector3(0.0, 0.62, 0.0), Vector3(0.95, 0.32, 2.15), color, 5.0)
	kit.call("rbox", Vector3(0.0, 1.12, 0.2), Vector3(0.85, 0.33, 1.15), color, 4.0)
	kit.call("rbox", Vector3(0.0, 1.13, 0.2), Vector3(0.87, 0.24, 1.0), glass, 5.0, {"shade": false})
	kit.call("rbox", Vector3(0.0, 1.13, 0.2), Vector3(0.05, 0.25, 1.02), color, 6.0)
	kit.call("rbox", Vector3(0.0, 0.42, -2.18), Vector3(0.95, 0.09, 0.08), Color(0.85, 0.85, 0.83), 4.0)
	kit.call("rbox", Vector3(0.0, 0.42, 2.18), Vector3(0.95, 0.09, 0.08), Color(0.85, 0.85, 0.83), 4.0)
	for side: float in [-1.0, 1.0]:
		kit.call("rbox", Vector3(side * 0.62, 0.7, -2.12), Vector3(0.18, 0.08, 0.04), Color(1.0, 0.95, 0.8), 4.0, {"shade": false})
		kit.call("rbox", Vector3(side * 0.66, 0.72, 2.13), Vector3(0.16, 0.07, 0.03), Color(0.85, 0.15, 0.1), 4.0, {"shade": false})
		for z: float in [-1.35, 1.35]:
			kit.call("wheel", Vector3(side * 0.88, 0.34, z), 0.34, 0.24, Color(0.12, 0.12, 0.13), Color(0.75, 0.75, 0.74))


## A wooden privacy fence run filling size along its longer axis: boards with
## dog-eared tops, two rails, and posts.
static func _fence(kit: RefCounted, color: Color, size: Vector3) -> void:
	var along_x := size.x >= size.z
	var length := size.x if along_x else size.z
	var boards := int(length / 0.16)
	var rng := RandomNumberGenerator.new()
	rng.seed = boards
	for index: int in boards:
		var t := -length * 0.5 + (float(index) + 0.5) * length / float(boards)
		var tint := color.darkened(rng.randf_range(0.0, 0.12))
		var at := Vector3(t, size.y * 0.5, 0.0) if along_x else Vector3(0.0, size.y * 0.5, t)
		var half := Vector3(0.07, size.y * 0.5, 0.012) if along_x else Vector3(0.012, size.y * 0.5, 0.07)
		kit.call("rbox", at, half, tint, 8.0, {"detail": 1})
	for y: float in [size.y * 0.25, size.y * 0.75]:
		var at := Vector3(0.0, y, 0.04) if along_x else Vector3(0.04, y, 0.0)
		var half := Vector3(length * 0.5, 0.04, 0.025) if along_x else Vector3(0.025, 0.04, length * 0.5)
		kit.call("rbox", at, half, color.darkened(0.2), 8.0, {"detail": 1})
	for post: int in int(length / 2.4) + 1:
		var t := -length * 0.5 + float(post) * length / float(int(length / 2.4))
		var at := Vector3(t, size.y * 0.52, 0.05) if along_x else Vector3(0.05, size.y * 0.52, t)
		kit.call("rbox", at, Vector3(0.06, size.y * 0.53, 0.06), color.darkened(0.25), 8.0, {"detail": 1})


# ---------------------------------------------------------------- tools (face -Z)

## A handheld blower: a chunky orange motor, a top handle, and a long nozzle.
static func _leaf_blower(kit: RefCounted) -> void:
	var orange := Color(0.95, 0.5, 0.12)
	kit.call("rbox", Vector3(0.0, 0.2, 0.08), Vector3(0.14, 0.16, 0.18), orange, 4.0)
	kit.call("rbox", Vector3(0.0, 0.2, 0.08), Vector3(0.145, 0.07, 0.12), Color(0.2, 0.2, 0.22), 6.0)
	kit.call("tube", PackedVector3Array([Vector3(0, 0.36, 0.0), Vector3(0, 0.44, 0.08), Vector3(0, 0.36, 0.2)]), PackedFloat32Array([0.025, 0.025, 0.025]), Color(0.15, 0.15, 0.16), 6, {"jitter": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(0, 0.16, -0.08), Vector3(0, 0.13, -0.4), Vector3(0, 0.1, -0.75)]), PackedFloat32Array([0.07, 0.055, 0.045]), orange.lightened(0.1), 10, {"jitter": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(0, 0.1, -0.74), Vector3(0, 0.1, -0.8)]), PackedFloat32Array([0.05, 0.05]), Color(0.15, 0.15, 0.16), 10, {"jitter": 0.0})


## A push mower: a red deck on four wheels, a motor on top, a grass bag at the
## back, and the handle rising behind (+Z) where you push.
static func _lawn_mower(kit: RefCounted) -> void:
	var red := Color(0.82, 0.18, 0.14)
	kit.call("rbox", Vector3(0.0, 0.2, 0.0), Vector3(0.3, 0.08, 0.32), red, 5.0)
	kit.call("tube", PackedVector3Array([Vector3(0, 0.26, -0.02), Vector3(0, 0.42, -0.02)]), PackedFloat32Array([0.13, 0.11]), Color(0.2, 0.2, 0.22), 12, {"jitter": 0.0})
	kit.call("blob", Vector3(0.0, 0.45, -0.02), Vector3(0.1, 0.04, 0.1), Color(0.75, 0.75, 0.72), {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0})
	for side: float in [-1.0, 1.0]:
		for z: float in [-0.26, 0.26]:
			kit.call("wheel", Vector3(side * 0.31, 0.1, z), 0.1, 0.06, Color(0.12, 0.12, 0.13), Color(0.8, 0.8, 0.78))
		kit.call("tube", PackedVector3Array([Vector3(side * 0.18, 0.25, 0.3), Vector3(side * 0.2, 0.7, 0.75), Vector3(side * 0.2, 0.95, 0.95)]), PackedFloat32Array([0.018, 0.018, 0.018]), Color(0.25, 0.25, 0.27), 6, {"jitter": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(-0.21, 0.95, 0.95), Vector3(0.21, 0.95, 0.95)]), PackedFloat32Array([0.025, 0.025]), Color(0.12, 0.12, 0.13), 8, {"jitter": 0.0, "cap_start": true})
	kit.call("blob", Vector3(0.0, 0.3, 0.45), Vector3(0.2, 0.14, 0.16), Color(0.25, 0.45, 0.28), {"detail": 2, "lumps": 0.1, "flat": false, "jitter": 0.0})


## An aluminum step ladder, carried flat: two rails along Z and rungs between.
static func _ladder(kit: RefCounted) -> void:
	var metal := Color(0.78, 0.8, 0.82)
	for side: float in [-1.0, 1.0]:
		kit.call("rbox", Vector3(side * 0.22, 0.0, 0.0), Vector3(0.025, 0.05, 1.2), metal, 8.0)
	for rung: int in 7:
		kit.call("tube", PackedVector3Array([Vector3(-0.21, 0.0, -1.05 + float(rung) * 0.35), Vector3(0.21, 0.0, -1.05 + float(rung) * 0.35)]), PackedFloat32Array([0.018, 0.018]), metal.darkened(0.1), 6, {"jitter": 0.0})
	for side: float in [-1.0, 1.0]:
		kit.call("rbox", Vector3(side * 0.22, 0.0, 1.22), Vector3(0.035, 0.06, 0.04), Color(0.15, 0.15, 0.16), 4.0)


## A garden hose coiled on a little reel, with a spray nozzle.
static func _hose(kit: RefCounted) -> void:
	var green := Color(0.2, 0.58, 0.3)
	for loop: int in 4:
		var points := PackedVector3Array()
		var radii := PackedFloat32Array()
		for step: int in 17:
			var angle := TAU * float(step) / 16.0
			points.append(Vector3(-0.09 + float(loop) * 0.06, 0.3 + sin(angle) * 0.2, cos(angle) * 0.2))
			radii.append(0.022)
		kit.call("tube", points, radii, green.darkened(float(loop % 2) * 0.1), 6, {"jitter": 0.0})
	for side: float in [-1.0, 1.0]:
		kit.call("tube", PackedVector3Array([Vector3(side * 0.16, 0.3, 0.0), Vector3(side * 0.14, 0.0, 0.0)]), PackedFloat32Array([0.02, 0.025]), Color(0.3, 0.3, 0.32), 6, {"jitter": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(0, 0.3, -0.2), Vector3(0, 0.25, -0.35), Vector3(0, 0.25, -0.5)]), PackedFloat32Array([0.022, 0.022, 0.022]), green, 6, {"jitter": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(0, 0.25, -0.5), Vector3(0, 0.25, -0.62)]), PackedFloat32Array([0.03, 0.02]), Color(0.85, 0.75, 0.2), 8, {"jitter": 0.0})


## A yellow pressure washer on wheels, with its long spray wand clipped on.
static func _pressure_washer(kit: RefCounted) -> void:
	var yellow := Color(0.98, 0.78, 0.15)
	kit.call("rbox", Vector3(0.0, 0.38, 0.0), Vector3(0.22, 0.24, 0.18), yellow, 4.0)
	kit.call("rbox", Vector3(0.0, 0.42, -0.19), Vector3(0.14, 0.1, 0.02), Color(0.15, 0.15, 0.16), 6.0)
	for side: float in [-1.0, 1.0]:
		kit.call("wheel", Vector3(side * 0.25, 0.1, 0.1), 0.1, 0.06, Color(0.12, 0.12, 0.13), Color(0.7, 0.7, 0.7))
	kit.call("tube", PackedVector3Array([Vector3(-0.16, 0.6, 0.12), Vector3(-0.16, 0.95, 0.18), Vector3(0.16, 0.95, 0.18), Vector3(0.16, 0.6, 0.12)]), PackedFloat32Array([0.018, 0.018, 0.018, 0.018]), Color(0.2, 0.2, 0.22), 6, {"jitter": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(0.24, 0.3, -0.05), Vector3(0.26, 0.75, -0.15), Vector3(0.26, 0.9, -0.5)]), PackedFloat32Array([0.014, 0.014, 0.012]), Color(0.2, 0.2, 0.22), 6, {"jitter": 0.0})


## A hedge trimmer: a red motor body with a handle and a long toothed blade forward.
static func _hedge_trimmer(kit: RefCounted) -> void:
	kit.call("rbox", Vector3(0.0, 0.15, 0.12), Vector3(0.09, 0.09, 0.16), Color(0.85, 0.22, 0.15), 4.0)
	kit.call("tube", PackedVector3Array([Vector3(0, 0.25, 0.04), Vector3(0, 0.32, 0.12), Vector3(0, 0.25, 0.22)]), PackedFloat32Array([0.02, 0.02, 0.02]), Color(0.15, 0.15, 0.16), 6, {"jitter": 0.0})
	kit.call("rbox", Vector3(0.0, 0.14, -0.35), Vector3(0.035, 0.012, 0.33), Color(0.8, 0.82, 0.85), 6.0)
	for tooth: int in 12:
		for side: float in [-1.0, 1.0]:
			kit.call("rbox", Vector3(side * 0.045, 0.14, -0.07 - float(tooth) * 0.05), Vector3(0.012, 0.008, 0.01), Color(0.75, 0.77, 0.8), 4.0, {"detail": 1})


## A paint roller: a handle, a bent frame, and a roller loaded with white paint.
static func _paint_roller(kit: RefCounted) -> void:
	kit.call("tube", PackedVector3Array([Vector3(0, 0.0, 0.3), Vector3(0, 0.0, 0.0)]), PackedFloat32Array([0.022, 0.02]), Color(0.3, 0.45, 0.8), 8, {"jitter": 0.0, "cap_start": true})
	kit.call("tube", PackedVector3Array([Vector3(0, 0.0, 0.0), Vector3(0, 0.0, -0.12), Vector3(0.1, 0.0, -0.18)]), PackedFloat32Array([0.008, 0.008, 0.008]), Color(0.75, 0.75, 0.75), 5, {"jitter": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(0.1, 0.0, -0.18), Vector3(-0.12, 0.0, -0.18)]), PackedFloat32Array([0.045, 0.045]), Color(0.97, 0.96, 0.93), 12, {"jitter": 0.0, "cap_start": true})


# ---------------------------------------------------------------- water

## A red fire hydrant: a domed body, side caps, and a chain.
static func _hydrant(kit: RefCounted) -> void:
	var red := Color(0.85, 0.15, 0.12)
	kit.call("tube", PackedVector3Array([Vector3(0, 0.0, 0), Vector3(0, 0.12, 0)]), PackedFloat32Array([0.2, 0.2]), red.darkened(0.2), 12, {"jitter": 0.0, "cap_start": true})
	kit.call("tube", PackedVector3Array([Vector3(0, 0.1, 0), Vector3(0, 0.62, 0)]), PackedFloat32Array([0.15, 0.14]), red, 12, {"jitter": 0.0})
	kit.call("blob", Vector3(0.0, 0.64, 0.0), Vector3(0.16, 0.12, 0.16), red.lightened(0.05), {"detail": 2, "lumps": 0.0, "flat": false, "jitter": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(0, 0.74, 0), Vector3(0, 0.82, 0)]), PackedFloat32Array([0.05, 0.04]), Color(0.75, 0.7, 0.3), 8, {"jitter": 0.0})
	for side: float in [-1.0, 1.0]:
		kit.call("tube", PackedVector3Array([Vector3(side * 0.12, 0.42, 0), Vector3(side * 0.24, 0.42, 0)]), PackedFloat32Array([0.06, 0.06]), red.darkened(0.1), 10, {"jitter": 0.0})
		kit.call("tube", PackedVector3Array([Vector3(side * 0.24, 0.42, 0), Vector3(side * 0.27, 0.42, 0)]), PackedFloat32Array([0.07, 0.07]), Color(0.75, 0.7, 0.3), 10, {"jitter": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(0, 0.42, -0.12), Vector3(0, 0.42, -0.2)]), PackedFloat32Array([0.08, 0.08]), Color(0.75, 0.7, 0.3), 10, {"jitter": 0.0})


## A brass spigot on the wall (facing -Z out of it), with a little round handle.
static func _spigot(kit: RefCounted) -> void:
	var brass := Color(0.8, 0.62, 0.25)
	kit.call("tube", PackedVector3Array([Vector3(0, 0, 0.0), Vector3(0, 0, -0.1), Vector3(0, -0.04, -0.15), Vector3(0, -0.1, -0.16)]), PackedFloat32Array([0.022, 0.02, 0.02, 0.02]), brass, 8, {"jitter": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(0, 0, -0.06), Vector3(0, 0.07, -0.06)]), PackedFloat32Array([0.008, 0.008]), brass.darkened(0.2), 6, {"jitter": 0.0})
	kit.call("blob", Vector3(0.0, 0.08, -0.06), Vector3(0.04, 0.012, 0.04), Color(0.25, 0.45, 0.75), {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0})
	kit.call("rbox", Vector3(0.0, 0.0, 0.01), Vector3(0.06, 0.06, 0.012), brass.darkened(0.3), 4.0)


## A blue water barrel with a valve, strapped in Chefty's bed.
static func _water_tank(kit: RefCounted) -> void:
	var blue := Color(0.22, 0.48, 0.82)
	kit.call("tube", PackedVector3Array([Vector3(0, 0.0, 0), Vector3(0, 0.75, 0)]), PackedFloat32Array([0.32, 0.32]), blue, 14, {"jitter": 0.0, "cap_start": true})
	for y: float in [0.2, 0.55]:
		kit.call("tube", PackedVector3Array([Vector3(0, y - 0.02, 0), Vector3(0, y + 0.02, 0)]), PackedFloat32Array([0.335, 0.335]), blue.darkened(0.25), 14, {"jitter": 0.0, "cap": false})
	kit.call("tube", PackedVector3Array([Vector3(0, 0.12, 0.3), Vector3(0, 0.12, 0.42)]), PackedFloat32Array([0.035, 0.03]), Color(0.75, 0.75, 0.72), 8, {"jitter": 0.0})
	kit.call("blob", Vector3(0.0, 0.18, 0.4), Vector3(0.05, 0.015, 0.05), Color(0.85, 0.2, 0.15), {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0})


## The hose's spray nozzle, held when the hose is hooked up (points -Z).
static func _nozzle(kit: RefCounted) -> void:
	kit.call("tube", PackedVector3Array([Vector3(0, 0, 0.15), Vector3(0, 0, -0.05)]), PackedFloat32Array([0.03, 0.03]), Color(0.2, 0.58, 0.3), 8, {"jitter": 0.0, "cap_start": true})
	kit.call("tube", PackedVector3Array([Vector3(0, 0, -0.05), Vector3(0, 0, -0.2)]), PackedFloat32Array([0.035, 0.022]), Color(0.85, 0.72, 0.2), 10, {"jitter": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(0, 0, 0.02), Vector3(0, -0.12, 0.06)]), PackedFloat32Array([0.018, 0.018]), Color(0.15, 0.15, 0.16), 6, {"jitter": 0.0})
