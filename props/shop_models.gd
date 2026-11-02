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
]

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
