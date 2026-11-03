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
	# Food (shops chunk 6): held in the hand, so centered on the grip, not
	# standing on a base. Long things lie along Z, the end you bite toward +Z.
	"hot_dog", "sandwich", "coffee_cup", "turbo_can", "turbo_can_warm",
	# The Snak-o-Matic's cabinet (props/vending_machine.gd adds its screen and glass).
	"vending_machine",
]
## Which food model each snack is, and whether you drink it.
const SNACK_MODELS: Dictionary = {
	"hot_dog": "hot_dog", "vend_sandwich": "sandwich", "coffee": "coffee_cup",
	"turbo_juice": "turbo_can", "vend_turbo": "turbo_can_warm",
}
const DRINKS: Array[String] = ["coffee", "turbo_juice", "vend_turbo"]
## The Snak-o-Matic's teal, and the size of its cabinet (m): x wide, y tall, z deep.
const VENDING_TEAL := Color(0.15, 0.55, 0.62)
const VENDING_SIZE := Vector3(1.0, 1.95, 0.78)
## Its window (in the cabinet's space, on the -Z face): x from, x to, y from, y to.
const VENDING_WINDOW := Rect2(-0.44, 0.62, 0.62, 1.12)
## How deep the window's recess goes into the cabinet (m): the glass sits on its
## front, the snacks on shelves inside it.
const VENDING_RECESS: float = 0.28
## The lit header's middle, over the window (m up from the base).
const VENDING_HEADER_Y: float = 1.86
## Its shelves of snacks behind the glass: how many rows and slots a row, and
## how many of the slots hold the 10-bag rolls (vending_slot_item). One slot a
## unit of Constants.SHOP_DAILY_STOCK.snak_o_matic: 6 cans, 4 rolls, 6 sandwiches.
const VENDING_ROWS: int = 4
const VENDING_SLOTS: int = 4
const VENDING_BAG_SLOTS: int = 4
## The tray behind the push flap, where a snack lands (cabinet space).
const VENDING_TRAY := Vector3(-0.13, 0.36, -0.37)

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
		"hot_dog":
			_hot_dog(kit)
		"sandwich":
			_sandwich(kit)
		"coffee_cup":
			_coffee_cup(kit)
		"turbo_can":
			_turbo_can(kit, Color(0.12, 0.75, 0.35))
		"turbo_can_warm":
			# The machine's Turbo Juice: the same can, a little faded from the sun.
			_turbo_can(kit, Color(0.4, 0.72, 0.5))
		"vending_machine":
			_vending_machine(kit)
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


# ---- food (shops chunk 6): what a snack looks like in your hand

## A hot dog in its bun, mustard zigzag on top: 17 cm, along Z.
static func _hot_dog(kit: RefCounted) -> void:
	var bun := Color(0.9, 0.66, 0.36)
	for side: float in [-1.0, 1.0]:
		kit.call("blob", Vector3(side * 0.018, -0.004, 0.0), Vector3(0.022, 0.02, 0.075), bun, {"detail": 2, "lumps": 0.0, "flat": false, "jitter": 0.0})
	kit.call("tube", PackedVector3Array([Vector3(0.0, 0.012, -0.088), Vector3(0.0, 0.016, 0.0), Vector3(0.0, 0.012, 0.088)]), PackedFloat32Array([0.014, 0.017, 0.014]), Color(0.72, 0.28, 0.18), 8, {"jitter": 0.0, "cap": true, "cap_start": true})
	var zig := PackedVector3Array()
	for step: int in 9:
		zig.append(Vector3(0.008 * (1.0 if step % 2 == 0 else -1.0), 0.031, -0.064 + float(step) * 0.016))
	var radii := PackedFloat32Array()
	radii.resize(zig.size())
	radii.fill(0.0035)
	kit.call("tube", zig, radii, Color(0.98, 0.8, 0.15), 4, {"jitter": 0.0})


## A gas-station-adjacent sandwich: a triangle of white bread in a plastic
## wedge, a frill of lettuce, along Z.
static func _sandwich(kit: RefCounted) -> void:
	var bread := Color(0.95, 0.9, 0.78)
	for layer: float in [-0.012, 0.012]:
		kit.call("rbox", Vector3(0.0, layer, 0.0), Vector3(0.045, 0.008, 0.06), bread, 3.0, {"detail": 1})
	kit.call("rbox", Vector3(0.0, 0.0, 0.0), Vector3(0.047, 0.005, 0.062), Color(0.45, 0.72, 0.3), 3.0, {"detail": 1})
	kit.call("rbox", Vector3(0.0, 0.0, 0.004), Vector3(0.042, 0.004, 0.056), Color(0.92, 0.6, 0.55), 3.0, {"detail": 1})


## Burnt coffee: a white paper cup with a brown sleeve and a lid, 11 cm tall.
static func _coffee_cup(kit: RefCounted) -> void:
	kit.call("tube", PackedVector3Array([Vector3(0.0, -0.055, 0.0), Vector3(0.0, 0.05, 0.0)]), PackedFloat32Array([0.03, 0.039]), Color(0.96, 0.95, 0.92), 12, {"jitter": 0.0, "cap": true, "cap_start": true})
	kit.call("tube", PackedVector3Array([Vector3(0.0, -0.022, 0.0), Vector3(0.0, 0.022, 0.0)]), PackedFloat32Array([0.0345, 0.0375]), Color(0.55, 0.36, 0.22), 12, {"jitter": 0.0, "cap": false})
	kit.call("tube", PackedVector3Array([Vector3(0.0, 0.048, 0.0), Vector3(0.0, 0.062, 0.0)]), PackedFloat32Array([0.041, 0.036]), Color(0.18, 0.16, 0.16), 12, {"jitter": 0.0, "cap": true})


## Turbo Juice: a tall can with a lightning band and a ring pull, 12 cm.
static func _turbo_can(kit: RefCounted, body: Color) -> void:
	kit.call("tube", PackedVector3Array([Vector3(0.0, -0.06, 0.0), Vector3(0.0, -0.052, 0.0), Vector3(0.0, 0.052, 0.0), Vector3(0.0, 0.06, 0.0)]), PackedFloat32Array([0.028, 0.033, 0.033, 0.027]), body, 12, {"jitter": 0.0, "cap": true, "cap_start": true})
	kit.call("tube", PackedVector3Array([Vector3(0.0, -0.012, 0.0), Vector3(0.0, 0.012, 0.0)]), PackedFloat32Array([0.0335, 0.0335]), Color(1.0, 0.86, 0.15), 12, {"jitter": 0.0, "cap": false})
	# The bolt, front and back.
	var bolt: Array = [
		[Vector3(-0.008, 0.03, 0.0), Vector3(0.01, 0.002, 0.0), Vector3(-0.004, 0.002, 0.0)],
		[Vector3(0.006, 0.004, 0.0), Vector3(-0.01, -0.028, 0.0), Vector3(0.002, 0.004, 0.0)],
	]
	for side: float in [-1.0, 1.0]:
		var out := Vector3(0.0, 0.0, side * 0.0345)
		for tri: Array in bolt:
			# Wound the other way on the back, so both faces face out.
			var b: Vector3 = tri[1] if side > 0.0 else tri[2]
			var c: Vector3 = tri[2] if side > 0.0 else tri[1]
			kit.call("triangle", (tri[0] as Vector3) + out, b + out, c + out, Vector3(0.0, 0.0, side), Color(1.0, 0.95, 0.4))
	kit.call("blob", Vector3(0.0, 0.062, -0.01), Vector3(0.008, 0.002, 0.012), Color(0.8, 0.82, 0.84), FLAT)


# ---- the Snak-o-Matic's cabinet (props/vending_machine.gd)

## A tall teal cabinet facing -Z, its base at the origin: a lit header, the big
## window on the left (its snacks on coiled shelves; the glass itself is the
## machine's own node), the control panel on the right with a coin slot, a bill
## slot and a keypad (the screen is a Label3D the machine writes on), and the
## push-flap tray at the bottom where a snack lands.
static func _vending_machine(kit: RefCounted) -> void:
	var size := VENDING_SIZE
	var half := size * 0.5
	var front := -half.z
	var dark := VENDING_TEAL.darkened(0.35)
	var win := VENDING_WINDOW
	# The cabinet is a shell round the window's recess (VENDING_RECESS deep): the
	# back block, then the front's four sides of the window.
	var recess_back := front + VENDING_RECESS
	var back_depth := half.z - recess_back
	kit.call("rbox", Vector3(0.0, half.y, recess_back + back_depth * 0.5), Vector3(half.x, half.y, back_depth * 0.5), VENDING_TEAL, 14.0, {"detail": 2})
	var face_z := front + VENDING_RECESS * 0.5
	var face_half := VENDING_RECESS * 0.5 + 0.01
	var left_w := (win.position.x + half.x) * 0.5
	kit.call("rbox", Vector3(-half.x + left_w, half.y, face_z), Vector3(left_w, half.y, face_half), VENDING_TEAL, 14.0, {"detail": 1})
	var right_w := (half.x - win.end.x) * 0.5
	kit.call("rbox", Vector3(half.x - right_w, half.y, face_z), Vector3(right_w, half.y, face_half), VENDING_TEAL, 14.0, {"detail": 1})
	var top_h := (size.y - win.end.y) * 0.5
	kit.call("rbox", Vector3(win.position.x + win.size.x * 0.5, size.y - top_h, face_z), Vector3(win.size.x * 0.5 + 0.02, top_h, face_half), VENDING_TEAL, 14.0, {"detail": 1})
	var low_h := win.position.y * 0.5
	kit.call("rbox", Vector3(win.position.x + win.size.x * 0.5, low_h, face_z), Vector3(win.size.x * 0.5 + 0.02, low_h, face_half), VENDING_TEAL, 14.0, {"detail": 1})
	# Little feet, so it stands on something.
	for x: float in [-0.4, 0.4]:
		for z: float in [-0.3, 0.3]:
			kit.call("rbox", Vector3(x, 0.02, z), Vector3(0.05, 0.02, 0.05), INK, 4.0, {"detail": 1})
	# The header: a pale lit panel (the name is a text sign on it).
	kit.call("rbox", Vector3(0.0, VENDING_HEADER_Y, front - 0.012), Vector3(half.x - 0.06, 0.068, 0.02), Color(1.0, 0.86, 0.32), 6.0, {"detail": 1, "shade": false})
	# The window's inside: a dark back, the shelves and their snacks in rows.
	var center := Vector3((win.position.x + win.size.x * 0.5), win.position.y + win.size.y * 0.5, front + VENDING_RECESS * 0.5)
	kit.call("rbox", Vector3(center.x, center.y, recess_back - 0.012), Vector3(win.size.x * 0.5, win.size.y * 0.5, 0.012), Color(0.12, 0.14, 0.16), 6.0, {"detail": 1, "shade": false})
	# The window's frame, standing out a little from the face.
	for y: float in [win.position.y - 0.025, win.end.y + 0.025]:
		kit.call("rbox", Vector3(center.x, y, front - 0.012), Vector3(win.size.x * 0.5 + 0.035, 0.025, 0.02), dark, 5.0, {"detail": 1})
	for x: float in [win.position.x - 0.025, win.end.x + 0.025]:
		kit.call("rbox", Vector3(x, center.y, front - 0.012), Vector3(0.025, win.size.y * 0.5 + 0.05, 0.02), dark, 5.0, {"detail": 1})
	for row: int in VENDING_ROWS:
		var y := win.position.y + 0.04 + float(row) * (win.size.y / float(VENDING_ROWS))
		kit.call("box", Vector3(center.x, y - 0.012, center.z), Vector3(win.size.x - 0.02, 0.012, 0.22), Color(0.62, 0.64, 0.68))
		for slot: int in VENDING_SLOTS:
			# The back one of each pair; the front one is the machine's own node
			# (props/vending_machine.gd), so it can fall when you buy it.
			vending_snack(kit, row, slot, vending_slot(row, slot, 1))
			var x := vending_slot(row, slot, 0).x
			kit.call("tube", PackedVector3Array([Vector3(x, y + 0.01, center.z - 0.11), Vector3(x, y + 0.01, center.z + 0.11)]), PackedFloat32Array([0.006, 0.006]), Color(0.8, 0.8, 0.82), 4, {"jitter": 0.0})
	# The control panel: a darker strip, the screen's black bezel, slots and keys.
	var panel_x := (win.end.x + half.x) * 0.5
	kit.call("rbox", Vector3(panel_x, center.y, front - 0.008), Vector3((half.x - win.end.x) * 0.5 - 0.05, win.size.y * 0.5, 0.012), dark, 6.0, {"detail": 1})
	# The screen's bezel: boxy, so its black face is nearly all of its 22 x 14 cm
	# (the marquee's six letters fit inside it, props/vending_machine.gd).
	kit.call("rbox", Vector3(panel_x, win.end.y - 0.14, front - 0.022), Vector3(0.11, 0.07, 0.008), Color(0.05, 0.06, 0.05), 14.0, {"detail": 3, "shade": false})
	kit.call("rbox", Vector3(panel_x, win.end.y - 0.32, front - 0.022), Vector3(0.06, 0.012, 0.008), INK, 4.0, {"detail": 1})
	kit.call("rbox", Vector3(panel_x, win.end.y - 0.4, front - 0.024), Vector3(0.012, 0.03, 0.008), Color(0.75, 0.76, 0.78), 4.0, {"detail": 1})
	for row: int in 4:
		for column: int in 3:
			kit.call("rbox", Vector3(panel_x - 0.05 + float(column) * 0.05, win.end.y - 0.52 - float(row) * 0.05, front - 0.024), Vector3(0.018, 0.016, 0.008), Color(0.85, 0.86, 0.88), 4.0, {"detail": 1})
	kit.call("rbox", Vector3(panel_x, win.position.y + 0.1, front - 0.022), Vector3(0.045, 0.045, 0.008), Color(0.75, 0.76, 0.78), 4.0, {"detail": 1})
	# The tray: a dark opening with a flap you push to reach in.
	kit.call("rbox", Vector3(center.x, 0.36, front - 0.004), Vector3(0.28, 0.12, 0.015), INK, 6.0, {"detail": 1})
	kit.call("rbox", Vector3(center.x, 0.4, front - 0.02), Vector3(0.26, 0.07, 0.008), Color(0.25, 0.27, 0.3), 6.0, {"detail": 1})
	# A dent where someone kicked it. More than once.
	kit.call("blob", Vector3(0.3, 0.3, front - 0.003), Vector3(0.07, 0.05, 0.01), VENDING_TEAL.darkened(0.2), {"detail": 1, "lumps": 0.3, "flat": false, "jitter": 0.0, "seed": 3})

## Where a snack sits in the Snak-o-Matic's window (cabinet space): row 0 is
## the bottom shelf, slot 0 the left; depth 0 the front one, 1 the one behind.
static func vending_slot(row: int, slot: int, depth: int) -> Vector3:
	var win := VENDING_WINDOW
	var y := win.position.y + 0.04 + float(row) * (win.size.y / float(VENDING_ROWS))
	var x := win.position.x + (float(slot) + 0.5) * (win.size.x / float(VENDING_SLOTS))
	return Vector3(x, y + 0.07, -VENDING_SIZE.z * 0.5 + VENDING_RECESS * 0.5 - 0.05 + float(depth) * 0.1)


## Whether a slot holds cans (true) or bagged and boxed snacks.
static func vending_slot_is_can(row: int, slot: int) -> bool:
	return (row + slot) % 3 == 0


## What a slot sells (a Snak-o-Matic catalog item), the same on every peer: the
## cans are the warm Turbo Juice, the first VENDING_BAG_SLOTS of the other slots
## from the bottom are the 10-bag rolls, and the rest are sandwiches. A sale
## drops the front one of a slot of that item (props/vending_machine.gd).
static func vending_slot_item(row: int, slot: int) -> String:
	if vending_slot_is_can(row, slot):
		return "vend_turbo"
	var boxes_before := 0
	for index: int in row * VENDING_SLOTS + slot:
		if not vending_slot_is_can(index / VENDING_SLOTS, index % VENDING_SLOTS):
			boxes_before += 1
	return "vend_bags" if boxes_before < VENDING_BAG_SLOTS else "vend_sandwich"


## One snack of a slot's item, centered on at: a warm Turbo can (the faded green
## and its yellow band), a sandwich in its plastic wedge standing on end, or a
## roll of bags in a kraft sleeve.
static func vending_snack(kit: RefCounted, row: int, slot: int, at: Vector3) -> void:
	match vending_slot_item(row, slot):
		"vend_turbo":
			var body := Color(0.4, 0.72, 0.5)
			kit.call("tube", PackedVector3Array([at + Vector3(0.0, -0.065, 0.0), at + Vector3(0.0, 0.065, 0.0)]), PackedFloat32Array([0.03, 0.03]), body, 8, {"jitter": 0.0, "cap": true, "cap_start": true})
			kit.call("tube", PackedVector3Array([at + Vector3(0.0, -0.012, 0.0), at + Vector3(0.0, 0.012, 0.0)]), PackedFloat32Array([0.0305, 0.0305]), Color(1.0, 0.86, 0.15), 8, {"jitter": 0.0, "cap": false})
		"vend_sandwich":
			var bread := Color(0.95, 0.9, 0.78)
			kit.call("rbox", at, Vector3(0.05, 0.062, 0.022), bread, 4.0, {"detail": 1})
			# The filling seen through the wedge: lettuce over ham.
			kit.call("rbox", at + Vector3(0.0, 0.0, -0.023), Vector3(0.045, 0.008, 0.002), Color(0.45, 0.72, 0.3), 4.0, {"detail": 1, "shade": false})
			kit.call("rbox", at + Vector3(0.0, -0.014, -0.023), Vector3(0.042, 0.006, 0.002), Color(0.92, 0.6, 0.55), 4.0, {"detail": 1, "shade": false})
		_:
			kit.call("rbox", at, Vector3(0.05, 0.065, 0.022), KRAFT, 4.0, {"detail": 1})
			kit.call("rbox", at + Vector3(0.0, 0.01, -0.023), Vector3(0.05, 0.02, 0.002), LEAF_GREEN, 4.0, {"detail": 1, "shade": false})


## A food model to hold (SNACK_MODELS), its own instance.
static func food(item: String) -> MeshInstance3D:
	return node(str(SNACK_MODELS.get(item, "hot_dog")))