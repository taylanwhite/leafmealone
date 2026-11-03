extends RefCounted

## Authority: local, cosmetic. Modeled meshes for what the shops sell and how
## they show it (docs/GAME.md "Shops"; gap-specs shops chunk 4): the boxes of
## lawn and contractor bags, the red gas can, the fertilizer, seed and salt
## sacks, a delivery crate and pallet, and the blue tarp over anything your rank
## can't buy yet. Built with props/mesh_kit.gd and drawn with props/stylized.gd,
## cached per model, like props/yard_models.gd (which hands its "gas_can" kind to
## gas_can() here). Art rules: docs/ART.md. 1 unit = 1 meter, Y up, faces -Z,
## origin at the base. Every model is a few hundred triangles.

const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")

const KRAFT := Color(0.72, 0.55, 0.34)
const LEAF_GREEN := Color(0.3, 0.5, 0.24)
const ORANGE := Color(0.95, 0.5, 0.15)
const INK := Color(0.12, 0.12, 0.13)
const PAPER := Color(0.95, 0.93, 0.86)
const TARP := Color(0.18, 0.38, 0.72)
const PLANK := Color(0.68, 0.52, 0.34)
const FLAT := {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0}
## Every model this file builds (node() of anything else is an empty box).
const MODELS: Array[String] = [
	"bag_roll", "bag_roll_big", "gas_can", "fertilizer_bag", "grass_seed", "rock_salt",
	"crate", "pallet", "tarp",
	"junk_old_tv", "junk_tire", "junk_grill", "junk_toilet", "junk_bike", "junk_flamingo",
	"junk_mannequin", "junk_boombox", "dial_scale", "dial_needle", "tire_stack",
]
## Junk for Rusty's (shops chunk 5; Constants.JUNK_TYPES has the weights and
## values): each type's collision box (x wide, y tall, z deep; its base on the
## ground at the prop's origin), the size of the model it wears.
const JUNK_BOX: Dictionary = {
	"old_tv": Vector3(0.56, 0.5, 0.48), "tire": Vector3(0.8, 0.24, 0.8),
	"grill": Vector3(0.58, 0.92, 0.58), "toilet": Vector3(0.42, 0.82, 0.68),
	"bike": Vector3(0.3, 0.95, 1.5), "flamingo": Vector3(0.22, 0.86, 0.4),
	"mannequin": Vector3(0.5, 1.74, 0.36), "boombox": Vector3(0.5, 0.32, 0.18),
}
## How each junk type is carried (the props/prop_looks.gd HOLDS shape: at, yaw,
## tilt, roll, pivot, grips [right, left] in the model's space). Heavy, wide
## things are hugged in front at the chest; a flamingo by the neck and a boombox
## by its handle hang from one hand; a bike rolls along at your side; the
## mannequin goes under your arm like a battering ram, head first.
const JUNK_HOLDS: Dictionary = {
	"old_tv": {"at": Vector3(0.0, 0.6, -0.46), "grips": [Vector3(0.29, 0.24, 0.02), Vector3(-0.29, 0.24, 0.02)]},
	"tire": {"at": Vector3(0.0, 0.86, -0.55), "grips": [Vector3(0.39, 0.13, 0.0), Vector3(-0.39, 0.13, 0.0)]},
	"grill": {"at": Vector3(0.0, 0.27, -0.5), "grips": [Vector3(0.29, 0.62, 0.0), Vector3(-0.29, 0.62, 0.0)]},
	"toilet": {"at": Vector3(0.0, 0.5, -0.5), "yaw": PI, "grips": [Vector3(-0.21, 0.42, -0.08), Vector3(0.21, 0.42, -0.08)]},
	"bike": {"at": Vector3(0.48, 0.12, -0.05), "grips": [Vector3(0.0, 0.76, -0.1), Vector3.INF]},
	"flamingo": {"at": Vector3(0.3, 0.22, -0.32), "grips": [Vector3(0.0, 0.66, -0.1), Vector3.INF]},
	"mannequin": {"at": Vector3(0.36, 0.22, -0.18), "tilt": -PI * 0.5, "pivot": Vector3(0.0, 0.85, 0.0), "grips": [Vector3(-0.16, 0.95, 0.0), Vector3.INF]},
	"boombox": {"at": Vector3(0.32, 0.42, -0.18), "grips": [Vector3(0.0, 0.33, 0.0), Vector3.INF]},
}
const TIRE := Color(0.12, 0.12, 0.13)
const CHROME := Color(0.82, 0.83, 0.85)
const PORCELAIN := Color(0.95, 0.95, 0.92)
const FLAMINGO_PINK := Color(0.98, 0.47, 0.66)
const MANNEQUIN := Color(0.92, 0.86, 0.76)
const RUST := Color(0.55, 0.27, 0.14)
const STEEL := Color(0.55, 0.57, 0.6)

static var _cache: Dictionary = {}


static func has(model: String) -> bool:
	return MODELS.has(model)


## A model to add where it goes (cached per model; instances share the mesh).
static func node(model: String) -> MeshInstance3D:
	if not _cache.has(model):
		var kit := _MeshKit.new()
		build_into(kit, model)
		_cache[model] = kit.commit()
	return _Stylized.instance(_cache[model], {"roughness": 0.85, "specular": 0.12})


static func build_into(kit: RefCounted, model: String) -> void:
	match model:
		"bag_roll":
			_bag_box(kit, Vector3(0.17, 0.12, 0.13), KRAFT, LEAF_GREEN)
		"bag_roll_big":
			_bag_box(kit, Vector3(0.2, 0.14, 0.15), INK.lightened(0.08), ORANGE)
		"gas_can":
			gas_can(kit)
		"fertilizer_bag":
			_sack(kit, Vector3(0.22, 0.3, 0.11), Color(0.36, 0.6, 0.3), Color(0.95, 0.85, 0.3))
		"grass_seed":
			_sack(kit, Vector3(0.18, 0.24, 0.09), Color(0.92, 0.82, 0.42), Color(0.3, 0.6, 0.28))
		"rock_salt":
			_sack(kit, Vector3(0.2, 0.26, 0.1), Color(0.86, 0.9, 0.95), Color(0.25, 0.45, 0.8))
		"crate":
			_crate(kit)
		"pallet":
			_pallet(kit)
		"tarp":
			_tarp(kit)
		"junk_old_tv":
			_old_tv(kit)
		"junk_tire":
			_tire(kit, Vector3(0.0, 0.12, 0.0))
		"junk_grill":
			_grill(kit)
		"junk_toilet":
			_toilet(kit)
		"junk_bike":
			_bike(kit)
		"junk_flamingo":
			_flamingo(kit)
		"junk_mannequin":
			_mannequin(kit)
		"junk_boombox":
			_boombox(kit)
		"dial_scale":
			_dial_scale(kit)
		"dial_needle":
			_dial_needle(kit)
		"tire_stack":
			for layer: int in 4:
				_tire(kit, Vector3(float(layer % 2) * 0.05 - 0.025, 0.12 + float(layer) * 0.22, float((layer + 1) % 2) * 0.04))
		_:
			kit.call("rbox", Vector3(0.0, 0.15, 0.0), Vector3(0.15, 0.15, 0.15), KRAFT, 6.0)


## A carton of bag rolls: a printed box with a band round it and a leaf on the
## front, so a shelf of them reads as "bags" from the aisle.
static func _bag_box(kit: RefCounted, half: Vector3, body: Color, band: Color) -> void:
	kit.call("rbox", Vector3(0.0, half.y, 0.0), half, body, 6.0, {"detail": 2})
	kit.call("rbox", Vector3(0.0, half.y * 1.15, 0.0), Vector3(half.x + 0.004, half.y * 0.22, half.z + 0.004), band, 4.0, FLAT)
	kit.call("leaf_card", Vector3(0.0, half.y * 0.75, -half.z - 0.006), Vector3(0.0, 0.0, -1.0), half.y * 0.5, ORANGE if band != ORANGE else Color(0.93, 0.72, 0.22), 0.0, 0.4)
	# A roll peeking out of the open top.
	kit.call("tube", PackedVector3Array([Vector3(-half.x * 0.6, half.y * 2.0, 0.0), Vector3(half.x * 0.6, half.y * 2.0, 0.0)]), PackedFloat32Array([half.y * 0.32, half.y * 0.32]), band.lightened(0.25) if band == ORANGE else PAPER.darkened(0.1), 8, {"jitter": 0.0, "cap_start": true})


## The crew's red gas can: a flat jerry can with an X pressed in each side, a
## handle across the top (where it's held, prop_looks.gd HOLDS), and a yellow
## spout up front (-Z). Also the yard prop "gas_can" (props/yard_models.gd).
static func gas_can(kit: RefCounted) -> void:
	var red := Color(0.84, 0.14, 0.1)
	kit.call("rbox", Vector3(0.0, 0.17, 0.0), Vector3(0.08, 0.16, 0.13), red, 5.0, {"detail": 2})
	for side: float in [-1.0, 1.0]:
		for lean: float in [-1.0, 1.0]:
			kit.call("rbox", Vector3(side * 0.083, 0.17, 0.0), Vector3(0.006, 0.012, 0.15), red.darkened(0.25), 3.0, {"detail": 1, "basis": Basis(Vector3.RIGHT, lean * 0.82)})
	kit.call("tube", PackedVector3Array([Vector3(0, 0.32, -0.07), Vector3(0, 0.4, -0.045), Vector3(0, 0.4, 0.045), Vector3(0, 0.32, 0.07)]), PackedFloat32Array([0.016, 0.017, 0.017, 0.016]), INK, 6, {"jitter": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(0, 0.3, -0.1), Vector3(0, 0.37, -0.17), Vector3(0, 0.43, -0.22)]), PackedFloat32Array([0.022, 0.016, 0.012]), Color(0.95, 0.8, 0.2), 8, {"jitter": 0.0, "cap": true})
	kit.call("blob", Vector3(0.0, 0.335, 0.09), Vector3(0.025, 0.012, 0.025), INK, FLAT)


## A stuffed paper sack, folded over at the top, with a label on the front.
static func _sack(kit: RefCounted, half: Vector3, body: Color, label: Color) -> void:
	kit.call("blob", Vector3(0.0, half.y, 0.0), half, body, {"detail": 2, "lumps": 0.06, "flat": false, "jitter": 0.0, "seed": 5})
	kit.call("rbox", Vector3(0.0, half.y * 1.92, 0.0), Vector3(half.x * 0.9, half.y * 0.1, half.z * 0.55), body.darkened(0.12), 4.0, FLAT)
	kit.call("rbox", Vector3(0.0, half.y * 1.05, -half.z * 0.9), Vector3(half.x * 0.62, half.y * 0.4, 0.01), label, 4.0, {"detail": 1, "shade": false})
	kit.call("leaf_card", Vector3(0.0, half.y * 1.08, -half.z * 0.9 - 0.012), Vector3(0.0, 0.0, -1.0), half.y * 0.32, body.darkened(0.3), 0.0, 0.2)


## A slatted wooden crate (a delivery off the pallet).
static func _crate(kit: RefCounted) -> void:
	var half := Vector3(0.3, 0.25, 0.3)
	kit.call("rbox", Vector3(0.0, half.y, 0.0), half * 0.96, PLANK.darkened(0.25), 3.0, FLAT)
	for side: float in [-1.0, 1.0]:
		for slat: int in 3:
			var y := 0.08 + float(slat) * 0.17
			kit.call("rbox", Vector3(0.0, y, side * half.z), Vector3(half.x, 0.06, 0.012), PLANK.darkened(float(slat % 2) * 0.08), 3.0, FLAT)
			kit.call("rbox", Vector3(side * half.x, y, 0.0), Vector3(0.012, 0.06, half.z), PLANK.darkened(float((slat + 1) % 2) * 0.08), 3.0, FLAT)
	kit.call("rbox", Vector3(0.0, half.y * 2.0, 0.0), Vector3(half.x + 0.01, 0.015, half.z + 0.01), PLANK, 3.0, FLAT)


## A wooden shipping pallet: three runners under seven deck boards.
static func _pallet(kit: RefCounted) -> void:
	for x: float in [-0.55, 0.0, 0.55]:
		kit.call("rbox", Vector3(x, 0.05, 0.0), Vector3(0.05, 0.05, 0.5), PLANK.darkened(0.15), 2.0, FLAT)
	for board: int in 7:
		var z := -0.45 + float(board) * 0.15
		kit.call("rbox", Vector3(0.0, 0.115, z), Vector3(0.62, 0.015, 0.055), PLANK.darkened(float(board % 3) * 0.05), 2.0, FLAT)


## A blue tarp thrown over something lumpy, tied down at the corners: 1 m wide
## (x), 1 m deep (z), 1 m tall, scaled to the slot it covers.
static func _tarp(kit: RefCounted) -> void:
	kit.call("blob", Vector3(0.0, 0.42, 0.0), Vector3(0.5, 0.42, 0.5), TARP, {"detail": 2, "lumps": 0.12, "lump_scale": 1.4, "flat": false, "jitter": 0.0, "seed": 9})
	kit.call("rbox", Vector3(0.0, 0.03, 0.0), Vector3(0.52, 0.03, 0.52), TARP.darkened(0.15), 6.0, FLAT)
	for side: float in [-1.0, 1.0]:
		kit.call("tube", PackedVector3Array([Vector3(-0.5, 0.1, side * 0.3), Vector3(0.0, 0.86, side * 0.3), Vector3(0.5, 0.1, side * 0.3)]), PackedFloat32Array([0.012, 0.012, 0.012]), Color(0.85, 0.82, 0.7), 4, {"jitter": 0.0})


# ---------------------------------------------------------------- junk (shops chunk 5)

## A junk type's model, cached like everything here ("" or an unknown type: an empty box).
static func junk(type: String) -> MeshInstance3D:
	return node("junk_" + type)


## Whether this file knows a junk type.
static func is_junk(type: String) -> bool:
	return JUNK_BOX.has(type)


## Points round an ellipse in a plane: across and along are the two half axes as
## vectors, so the same ring lies flat (a tire) or stands up (a bike wheel).
static func _ring(center: Vector3, across: Vector3, along: Vector3, points: int = 16, wobble: Vector3 = Vector3.ZERO) -> PackedVector3Array:
	var out := PackedVector3Array()
	for index: int in points + 1:
		var angle := TAU * float(index % points) / float(points)
		out.append(center + across * cos(angle) + along * sin(angle) + wobble * sin(angle * 2.0))
	return out


static func _fill(count: int, radius: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(count)
	out.fill(radius)
	return out


## A tube along a ring (closed, no caps).
static func _loop(kit: RefCounted, ring: PackedVector3Array, radius: float, color: Color, sides: int = 6) -> void:
	kit.call("tube", ring, _fill(ring.size(), radius), color, sides, {"jitter": 0.0, "cap": false})


## A CRT television in a wood-look cabinet, its screen a dusty green, two knobs,
## and rabbit ears bent the way the last owner left them.
static func _old_tv(kit: RefCounted) -> void:
	var wood := Color(0.42, 0.28, 0.18)
	kit.call("rbox", Vector3(0.0, 0.25, 0.02), Vector3(0.28, 0.24, 0.22), wood, 6.0, {"detail": 2})
	kit.call("rbox", Vector3(-0.045, 0.265, -0.19), Vector3(0.2, 0.175, 0.035), INK.lightened(0.1), 6.0, {"detail": 1})
	kit.call("blob", Vector3(-0.045, 0.265, -0.222), Vector3(0.165, 0.14, 0.022), Color(0.22, 0.3, 0.27), {"detail": 2, "lumps": 0.0, "flat": false, "jitter": 0.0, "shade": false})
	# A glint on the glass, top left.
	kit.call("blob", Vector3(-0.12, 0.33, -0.243), Vector3(0.04, 0.018, 0.004), Color(0.6, 0.7, 0.68), {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0, "shade": false})
	kit.call("rbox", Vector3(0.205, 0.265, -0.2), Vector3(0.045, 0.175, 0.025), Color(0.62, 0.6, 0.55), 6.0, {"detail": 1})
	for y: float in [0.34, 0.25]:
		kit.call("blob", Vector3(0.205, y, -0.232), Vector3(0.024, 0.024, 0.016), INK, FLAT)
	kit.call("rbox", Vector3(0.205, 0.15, -0.226), Vector3(0.03, 0.012, 0.004), INK.lightened(0.3), 4.0, {"detail": 1})
	kit.call("blob", Vector3(0.02, 0.5, 0.06), Vector3(0.05, 0.022, 0.04), INK, FLAT)
	kit.call("tube", PackedVector3Array([Vector3(0.0, 0.51, 0.06), Vector3(-0.1, 0.66, 0.08), Vector3(-0.16, 0.77, 0.1)]), PackedFloat32Array([0.006, 0.005, 0.004]), CHROME, 4, {"jitter": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(0.04, 0.51, 0.06), Vector3(0.12, 0.62, 0.05), Vector3(0.24, 0.66, 0.03)]), PackedFloat32Array([0.006, 0.005, 0.004]), CHROME, 4, {"jitter": 0.0})


## A bald tire lying flat: a fat ring, worn smooth, with a lighter band where
## the tread used to be.
static func _tire(kit: RefCounted, center: Vector3) -> void:
	_loop(kit, _ring(center, Vector3(0.29, 0.0, 0.0), Vector3(0.0, 0.0, 0.29), 14), 0.115, TIRE, 8)
	_loop(kit, _ring(center, Vector3(0.405, 0.0, 0.0), Vector3(0.0, 0.0, 0.405), 14), 0.012, TIRE.lightened(0.18), 4)


## A kettle grill that has seen things: the bowl dented, the lid knocked
## askew, rust coming through, on three legs (two on wheels).
static func _grill(kit: RefCounted) -> void:
	var black := Color(0.13, 0.13, 0.14)
	kit.call("blob", Vector3(0.0, 0.62, 0.0), Vector3(0.28, 0.17, 0.28), black, {"detail": 2, "lumps": 0.07, "lump_scale": 1.8, "flat": false, "jitter": 0.0, "seed": 4})
	kit.call("blob", Vector3(0.07, 0.78, 0.05), Vector3(0.265, 0.12, 0.265), black.lightened(0.05), {"detail": 2, "lumps": 0.05, "flat": false, "jitter": 0.0, "seed": 7})
	kit.call("tube", PackedVector3Array([Vector3(-0.0, 0.89, 0.05), Vector3(0.05, 0.93, 0.05), Vector3(0.16, 0.93, 0.05), Vector3(0.2, 0.89, 0.05)]), PackedFloat32Array([0.012, 0.012, 0.012, 0.012]), Color(0.5, 0.36, 0.22), 5, {"jitter": 0.0})
	for patch: Vector3 in [Vector3(0.2, 0.6, -0.17), Vector3(-0.24, 0.57, 0.08), Vector3(0.05, 0.53, 0.24)]:
		kit.call("blob", patch, Vector3(0.06, 0.04, 0.06), RUST, {"detail": 1, "lumps": 0.2, "flat": false, "jitter": 0.0})
	for index: int in 3:
		var angle := TAU * float(index) / 3.0 + 0.4
		var top := Vector3(cos(angle) * 0.18, 0.52, sin(angle) * 0.18)
		var foot := Vector3(cos(angle) * 0.28, 0.04, sin(angle) * 0.28)
		kit.call("tube", PackedVector3Array([top, foot]), PackedFloat32Array([0.015, 0.013]), STEEL, 5, {"jitter": 0.0})
		if index < 2:
			kit.call("wheel", foot, 0.045, 0.03, TIRE, STEEL)
	# The ash pan between the legs.
	kit.call("tube", PackedVector3Array([Vector3(0.0, 0.24, 0.0), Vector3(0.0, 0.26, 0.0)]), PackedFloat32Array([0.15, 0.15]), STEEL.darkened(0.3), 10, {"jitter": 0.0, "cap_start": true})


## A toilet, front to -Z: the bowl on its pedestal, a seat, the lid up, and the
## tank with its chrome handle. Clean. Rusty checks.
static func _toilet(kit: RefCounted) -> void:
	kit.call("rbox", Vector3(0.0, 0.14, -0.04), Vector3(0.12, 0.14, 0.17), PORCELAIN.darkened(0.04), 4.0, {"detail": 2})
	kit.call("blob", Vector3(0.0, 0.36, -0.12), Vector3(0.19, 0.11, 0.23), PORCELAIN, {"detail": 2, "lumps": 0.0, "flat": false, "jitter": 0.0})
	kit.call("blob", Vector3(0.0, 0.44, -0.13), Vector3(0.14, 0.03, 0.17), Color(0.62, 0.74, 0.8), {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0, "shade": false})
	_loop(kit, _ring(Vector3(0.0, 0.47, -0.13), Vector3(0.165, 0.0, 0.0), Vector3(0.0, 0.0, 0.205), 14), 0.026, PORCELAIN.darkened(0.02), 6)
	kit.call("rbox", Vector3(0.0, 0.64, 0.1), Vector3(0.17, 0.19, 0.018), PORCELAIN.darkened(0.03), 5.0, {"detail": 1, "basis": Basis(Vector3.RIGHT, -0.18)})
	kit.call("rbox", Vector3(0.0, 0.6, 0.22), Vector3(0.2, 0.18, 0.09), PORCELAIN, 6.0, {"detail": 2})
	kit.call("rbox", Vector3(0.0, 0.79, 0.22), Vector3(0.21, 0.016, 0.1), PORCELAIN.darkened(0.05), 6.0, {"detail": 1})
	kit.call("rbox", Vector3(-0.15, 0.71, 0.125), Vector3(0.035, 0.009, 0.01), CHROME, 4.0, {"detail": 1})


## A bike frame on its wheels, front to -Z: rust-red tubes, a ripped seat, the
## back wheel bent out of true.
static func _bike(kit: RefCounted) -> void:
	var paint := Color(0.62, 0.2, 0.15)
	for z: float in [-0.52, 0.52]:
		var bent := Vector3(0.05, 0.0, 0.0) if z > 0.0 else Vector3.ZERO
		_loop(kit, _ring(Vector3(0.0, 0.33, z), Vector3(0.0, 0.31, 0.0), Vector3(0.0, 0.0, 0.31), 16, bent), 0.022, TIRE, 5)
		kit.call("blob", Vector3(0.0, 0.33, z), Vector3(0.03, 0.03, 0.03), STEEL, FLAT)
		for spoke: int in 4:
			var angle := PI * 0.25 * float(spoke)
			var out := Vector3(0.0, cos(angle), sin(angle)) * 0.29
			kit.call("tube", PackedVector3Array([Vector3(0.0, 0.33, z) - out, Vector3(0.0, 0.33, z) + out]), PackedFloat32Array([0.003, 0.003]), STEEL, 3, {"jitter": 0.0, "cap": false})
	var rear := Vector3(0.0, 0.33, 0.52)
	var seat := Vector3(0.0, 0.75, 0.2)
	var crank := Vector3(0.0, 0.33, 0.06)
	var head_top := Vector3(0.0, 0.78, -0.37)
	var head_low := Vector3(0.0, 0.64, -0.41)
	var front := Vector3(0.0, 0.33, -0.52)
	for pair: Array in [[rear, seat], [seat, crank], [crank, rear], [seat, head_top], [crank, head_low], [head_top, head_low], [head_low, front]]:
		kit.call("tube", PackedVector3Array([pair[0], pair[1]]), PackedFloat32Array([0.019, 0.019]), paint, 5, {"jitter": 0.0})
	kit.call("tube", PackedVector3Array([seat, seat + Vector3(0.0, 0.08, 0.02)]), PackedFloat32Array([0.012, 0.012]), STEEL, 4, {"jitter": 0.0})
	kit.call("blob", seat + Vector3(0.0, 0.1, 0.03), Vector3(0.06, 0.028, 0.12), INK, {"detail": 1, "lumps": 0.15, "flat": false, "jitter": 0.0, "seed": 3})
	kit.call("blob", seat + Vector3(0.025, 0.12, 0.08), Vector3(0.03, 0.012, 0.03), Color(0.9, 0.85, 0.6), FLAT)
	kit.call("tube", PackedVector3Array([head_top, head_top + Vector3(0.0, 0.12, -0.04)]), PackedFloat32Array([0.013, 0.013]), STEEL, 4, {"jitter": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(-0.23, 0.92, -0.39), Vector3(-0.1, 0.9, -0.42), Vector3(0.1, 0.9, -0.42), Vector3(0.23, 0.92, -0.39)]), PackedFloat32Array([0.012, 0.012, 0.012, 0.012]), STEEL, 5, {"jitter": 0.0})
	for side: float in [-1.0, 1.0]:
		kit.call("tube", PackedVector3Array([Vector3(side * 0.2, 0.92, -0.395), Vector3(side * 0.26, 0.925, -0.38)]), PackedFloat32Array([0.018, 0.018]), INK, 5, {"jitter": 0.0})
	kit.call("tube", PackedVector3Array([crank + Vector3(-0.06, 0.0, 0.0), crank + Vector3(0.06, 0.0, 0.0)]), PackedFloat32Array([0.05, 0.05]), STEEL.darkened(0.2), 8, {"jitter": 0.0, "cap_start": true})


## A plastic lawn flamingo on wire legs, faded by a hundred summers. Its
## vintage cousin (Constants.JUNK_JACKPOT) looks exactly the same. That's the joke.
static func _flamingo(kit: RefCounted) -> void:
	var wire := Color(0.3, 0.3, 0.32)
	for side: float in [-1.0, 1.0]:
		kit.call("tube", PackedVector3Array([Vector3(side * 0.03, 0.0, 0.02), Vector3(side * 0.012, 0.47, 0.03)]), PackedFloat32Array([0.006, 0.006]), wire, 4, {"jitter": 0.0})
	kit.call("blob", Vector3(0.0, 0.56, 0.04), Vector3(0.1, 0.095, 0.17), FLAMINGO_PINK, {"detail": 2, "lumps": 0.0, "flat": false, "jitter": 0.0})
	kit.call("blob", Vector3(0.0, 0.6, 0.18), Vector3(0.05, 0.04, 0.06), FLAMINGO_PINK.darkened(0.1), FLAT)
	for side: float in [-1.0, 1.0]:
		kit.call("blob", Vector3(side * 0.085, 0.58, 0.05), Vector3(0.02, 0.06, 0.12), FLAMINGO_PINK.darkened(0.12), FLAT)
	kit.call("tube", PackedVector3Array([Vector3(0.0, 0.6, -0.1), Vector3(0.0, 0.69, -0.15), Vector3(0.0, 0.77, -0.1), Vector3(0.0, 0.82, -0.12)]), PackedFloat32Array([0.03, 0.024, 0.022, 0.024]), FLAMINGO_PINK, 6, {"jitter": 0.0})
	kit.call("blob", Vector3(0.0, 0.84, -0.14), Vector3(0.035, 0.035, 0.045), FLAMINGO_PINK, FLAT)
	kit.call("tube", PackedVector3Array([Vector3(0.0, 0.84, -0.18), Vector3(0.0, 0.81, -0.215), Vector3(0.0, 0.78, -0.235)]), PackedFloat32Array([0.016, 0.011, 0.006]), PAPER, 5, {"jitter": 0.0})
	kit.call("blob", Vector3(0.0, 0.783, -0.232), Vector3(0.008, 0.01, 0.01), INK, FLAT)
	for side: float in [-1.0, 1.0]:
		kit.call("blob", Vector3(side * 0.03, 0.85, -0.15), Vector3(0.007, 0.009, 0.009), INK, FLAT)


## A shop mannequin on its base plate: blank face, one arm up in a wave,
## standing like it's been waiting for you.
static func _mannequin(kit: RefCounted) -> void:
	var skin := MANNEQUIN
	kit.call("tube", PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.025, 0.0)]), PackedFloat32Array([0.2, 0.2]), INK.lightened(0.15), 12, {"jitter": 0.0, "cap_start": true})
	kit.call("tube", PackedVector3Array([Vector3(0.0, 0.02, 0.0), Vector3(0.09, 0.3, 0.02)]), PackedFloat32Array([0.012, 0.012]), CHROME, 4, {"jitter": 0.0})
	for side: float in [-1.0, 1.0]:
		kit.call("tube", PackedVector3Array([Vector3(side * 0.09, 0.07, -0.02), Vector3(side * 0.09, 0.45, 0.0), Vector3(side * 0.095, 0.84, 0.0)]), PackedFloat32Array([0.045, 0.058, 0.075]), skin, 7, {"jitter": 0.0})
		kit.call("blob", Vector3(side * 0.09, 0.05, -0.06), Vector3(0.045, 0.035, 0.09), skin, FLAT)
	kit.call("blob", Vector3(0.0, 0.89, 0.0), Vector3(0.17, 0.1, 0.11), skin, FLAT)
	kit.call("tube", PackedVector3Array([Vector3(0.0, 0.88, 0.0), Vector3(0.0, 1.05, 0.0), Vector3(0.0, 1.25, 0.0), Vector3(0.0, 1.38, 0.0)]), PackedFloat32Array([0.15, 0.135, 0.165, 0.12]), skin, 9, {"jitter": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(0.0, 1.38, 0.0), Vector3(0.0, 1.47, 0.0)]), PackedFloat32Array([0.045, 0.045]), skin, 7, {"jitter": 0.0, "cap": false})
	kit.call("blob", Vector3(0.0, 1.59, -0.01), Vector3(0.095, 0.125, 0.105), skin, {"detail": 2, "lumps": 0.0, "flat": false, "jitter": 0.0})
	# The wave, and the arm that gave up.
	kit.call("tube", PackedVector3Array([Vector3(0.19, 1.33, 0.0), Vector3(0.31, 1.5, -0.04), Vector3(0.34, 1.68, -0.05)]), PackedFloat32Array([0.04, 0.035, 0.032]), skin, 6, {"jitter": 0.0})
	kit.call("blob", Vector3(0.345, 1.74, -0.05), Vector3(0.03, 0.055, 0.018), skin, FLAT)
	kit.call("tube", PackedVector3Array([Vector3(-0.19, 1.33, 0.0), Vector3(-0.23, 1.06, 0.01), Vector3(-0.24, 0.85, -0.03)]), PackedFloat32Array([0.04, 0.035, 0.032]), skin, 6, {"jitter": 0.0})
	kit.call("blob", Vector3(-0.245, 0.79, -0.035), Vector3(0.03, 0.055, 0.02), skin, FLAT)


## A silver boombox: two speakers, a tape deck, a handle and its antenna up.
static func _boombox(kit: RefCounted) -> void:
	kit.call("rbox", Vector3(0.0, 0.14, 0.0), Vector3(0.25, 0.13, 0.075), Color(0.7, 0.72, 0.75), 6.0, {"detail": 2})
	for side: float in [-1.0, 1.0]:
		kit.call("tube", PackedVector3Array([Vector3(side * 0.14, 0.13, -0.07), Vector3(side * 0.14, 0.13, -0.082)]), PackedFloat32Array([0.085, 0.085]), INK.lightened(0.1), 12, {"jitter": 0.0})
		kit.call("blob", Vector3(side * 0.14, 0.13, -0.085), Vector3(0.03, 0.03, 0.012), CHROME, FLAT)
	kit.call("rbox", Vector3(0.0, 0.16, -0.078), Vector3(0.048, 0.04, 0.006), INK, 4.0, {"detail": 1})
	kit.call("rbox", Vector3(0.0, 0.245, -0.07), Vector3(0.1, 0.008, 0.006), INK.lightened(0.25), 4.0, {"detail": 1})
	kit.call("tube", PackedVector3Array([Vector3(-0.17, 0.26, 0.0), Vector3(-0.15, 0.33, 0.0), Vector3(0.15, 0.33, 0.0), Vector3(0.17, 0.26, 0.0)]), PackedFloat32Array([0.014, 0.014, 0.014, 0.014]), INK, 5, {"jitter": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(0.2, 0.26, 0.03), Vector3(0.33, 0.62, 0.03)]), PackedFloat32Array([0.005, 0.003]), CHROME, 4, {"jitter": 0.0})


# ---------------------------------------------------------------- Rusty's yard

## Rusty's dial scale, front to -Z: a diamond-plate platform you set the junk on
## and a post at the back with a big round dial (the needle is dial_needle,
## turned by levels/dressing/shop_sites.gd). The dial's middle is DIAL_AT.
const DIAL_AT := Vector3(0.0, 1.38, 0.62)
const DIAL_RADIUS: float = 0.3
## The needle's sweep: from -DIAL_SWEEP (empty) to +DIAL_SWEEP (full), radians from straight up.
const DIAL_SWEEP: float = 2.4


static func _dial_scale(kit: RefCounted) -> void:
	kit.call("rbox", Vector3(0.0, 0.06, -0.02), Vector3(0.62, 0.06, 0.62), STEEL, 8.0, {"detail": 2})
	for row: int in 5:
		for column: int in 5:
			kit.call("rbox", Vector3(-0.48 + float(column) * 0.24, 0.123, -0.5 + float(row) * 0.24), Vector3(0.06, 0.004, 0.02), STEEL.lightened(0.15), 4.0, {"detail": 1, "basis": Basis(Vector3.UP, 0.6 if (row + column) % 2 == 0 else -0.6)})
	kit.call("tube", PackedVector3Array([Vector3(0.0, 0.1, DIAL_AT.z + 0.02), Vector3(0.0, DIAL_AT.y - 0.2, DIAL_AT.z + 0.02)]), PackedFloat32Array([0.045, 0.04]), STEEL.darkened(0.2), 8, {"jitter": 0.0})
	kit.call("tube", PackedVector3Array([DIAL_AT + Vector3(0.0, 0.0, 0.07), DIAL_AT + Vector3(0.0, 0.0, -0.03)]), PackedFloat32Array([DIAL_RADIUS + 0.03, DIAL_RADIUS + 0.03]), Color(0.75, 0.18, 0.12), 20, {"jitter": 0.0, "cap_start": true})
	kit.call("tube", PackedVector3Array([DIAL_AT + Vector3(0.0, 0.0, -0.03), DIAL_AT + Vector3(0.0, 0.0, -0.034)]), PackedFloat32Array([DIAL_RADIUS, DIAL_RADIUS]), PAPER, 20, {"jitter": 0.0})
	for tick: int in 11:
		var angle := lerpf(-DIAL_SWEEP, DIAL_SWEEP, float(tick) / 10.0)
		var at := DIAL_AT + dial_direction(angle) * (DIAL_RADIUS - 0.045) + Vector3(0.0, 0.0, -0.038)
		var long := tick % 5 == 0
		kit.call("box", at, Vector3(0.01, 0.05 if long else 0.03, 0.004), INK, Basis(Vector3.BACK, angle))
	# A red zone at the top end: past it, Rusty says "that's not junk, that's a car".
	for tick: int in 4:
		var angle := lerpf(DIAL_SWEEP * 0.72, DIAL_SWEEP, float(tick) / 3.0)
		kit.call("box", DIAL_AT + dial_direction(angle) * (DIAL_RADIUS - 0.02) + Vector3(0.0, 0.0, -0.037), Vector3(0.05, 0.02, 0.004), Color(0.85, 0.2, 0.15), Basis(Vector3.BACK, angle))


## Where a dial angle points on the face (radians, clockwise from straight up as
## you look at the dial from the front, its -Z side): a needle node turned by
## rotation.z = angle points the same way.
static func dial_direction(angle: float) -> Vector3:
	return Vector3(-sin(angle), cos(angle), 0.0)


## The needle, pointing straight up from its hub (turned about Z to read).
static func _dial_needle(kit: RefCounted) -> void:
	kit.call("tube", PackedVector3Array([Vector3(0.0, -0.05, 0.0), Vector3(0.0, DIAL_RADIUS - 0.06, 0.0)]), PackedFloat32Array([0.009, 0.004]), Color(0.85, 0.12, 0.1), 4, {"jitter": 0.0})
	kit.call("blob", Vector3.ZERO, Vector3(0.025, 0.025, 0.012), INK, FLAT)