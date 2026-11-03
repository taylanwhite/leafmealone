extends RefCounted

## Authority: local, cosmetic. Gear that lives in your wallet, not in the truck
## (driving chunk G1; docs/GAME.md "The Gutter Shredder"): Marty's nephew's old
## skateboard, built in code like every model (docs/ART.md), small enough for the
## props budget. 1 unit = 1 meter, Y up; the board's nose points to -Z.

const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")

## The deck: length, width, thickness, and the kicked-up nose and tail (each this
## long, tipped up this far, in radians).
const DECK_LENGTH: float = 0.80
const DECK_WIDTH: float = 0.21
const DECK_THICK: float = 0.024
const KICK_LENGTH: float = 0.12
const KICK_ANGLE: float = 0.38
## The trucks sit this far from the middle; the wheels this far out from it, this big.
const TRUCK_Z: float = 0.25
const WHEEL_X: float = 0.082
const WHEEL_RADIUS: float = 0.03
const WHEEL_WIDTH: float = 0.034
## Old wood, black grip tape (scuffed), Homie Depot orange underneath, raw metal,
## and fat yellow wheels from a garage sale.
const WOOD := Color(0.86, 0.62, 0.34)
const GRIP := Color(0.16, 0.16, 0.17)
const GRIP_SCUFF := Color(0.32, 0.31, 0.3)
const PRINT := Color(0.93, 0.47, 0.13)
const PRINT_LEAF := Color(0.98, 0.83, 0.3)
const METAL := Color(0.7, 0.72, 0.76)
const URETHANE := Color(0.98, 0.84, 0.32)

static var _deck_mesh: ArrayMesh
static var _wheels_mesh: ArrayMesh


## The Gutter Shredder: a Node3D whose wheels stand on y 0 and whose deck's top is
## at Constants.SKATE_DECK_HEIGHT. Children: "Deck" (one mesh: deck, grip, trucks)
## and the pivots "AxleFront" (-Z) and "AxleBack", each with its two wheels: turn
## them about X to roll the wheels.
static func build_skateboard() -> Node3D:
	var root := Node3D.new()
	root.name = "Skateboard"
	var deck := _Stylized.instance(_deck(), {"roughness": 0.85, "specular": 0.2})
	deck.name = "Deck"
	root.add_child(deck)
	for axle_name: String in ["AxleFront", "AxleBack"]:
		var axle := Node3D.new()
		axle.name = axle_name
		axle.position = Vector3(0.0, WHEEL_RADIUS, -TRUCK_Z if axle_name == "AxleFront" else TRUCK_Z)
		root.add_child(axle)
		var wheels := _Stylized.instance(_wheels(), {"roughness": 0.6, "specular": 0.3})
		wheels.name = "Wheels"
		axle.add_child(wheels)
	return root


## Where the deck's top is, in the board's own space, along its length (z): the
## middle is flat, the kicks rise. For posing feet on it.
static func deck_top(z: float) -> float:
	var flat := DECK_LENGTH * 0.5 - KICK_LENGTH
	var top := Constants.SKATE_DECK_HEIGHT
	if absf(z) <= flat:
		return top
	return top + (absf(z) - flat) * tan(KICK_ANGLE)


static func _deck() -> ArrayMesh:
	if _deck_mesh != null:
		return _deck_mesh
	var kit := _MeshKit.new()
	var top := Constants.SKATE_DECK_HEIGHT
	var middle_y := top - DECK_THICK * 0.5
	var flat := DECK_LENGTH * 0.5 - KICK_LENGTH
	# The flat middle, then the nose (-Z) and tail kicked up.
	kit.rbox(Vector3(0.0, middle_y, 0.0), Vector3(DECK_WIDTH * 0.5, DECK_THICK * 0.5, flat), WOOD, 9.0, {"detail": 2})
	kit.box(Vector3(0.0, top + 0.001, 0.0), Vector3(DECK_WIDTH - 0.012, 0.002, flat * 2.0 - 0.01), GRIP)
	for end: float in [-1.0, 1.0]:
		var tilt := Basis(Vector3.RIGHT, KICK_ANGLE * -end)
		var reach := Vector3(0.0, 0.0, end * KICK_LENGTH * 0.5)
		var at := Vector3(0.0, middle_y, end * flat) + tilt * reach
		kit.rbox(at, Vector3(DECK_WIDTH * 0.5, DECK_THICK * 0.5, KICK_LENGTH * 0.5 + 0.012), WOOD, 9.0, {"detail": 2, "basis": tilt})
		kit.box(at + tilt * Vector3(0.0, DECK_THICK * 0.5 + 0.001, 0.0), Vector3(DECK_WIDTH - 0.014, 0.002, KICK_LENGTH - 0.01), GRIP, tilt)
	# Scuffs in the grip where the feet go.
	for spot: float in [-0.17, 0.19]:
		kit.box(Vector3(0.03, top + 0.0025, spot), Vector3(0.07, 0.001, 0.05), GRIP_SCUFF)
	# Underneath: Homie Depot orange with a big yellow leaf, the nephew's own paint job.
	kit.box(Vector3(0.0, top - DECK_THICK - 0.0005, 0.0), Vector3(DECK_WIDTH - 0.02, 0.002, flat * 2.0 - 0.04), PRINT)
	kit.blob(Vector3(0.0, top - DECK_THICK - 0.002, 0.0), Vector3(0.06, 0.002, 0.14), PRINT_LEAF, {"detail": 1, "lumps": 0.0, "flat": true, "jitter": 0.0, "shade": false})
	# The trucks: a baseplate under the deck, a kingpin block, the hanger out to the wheels.
	for end: float in [-1.0, 1.0]:
		var z := end * TRUCK_Z
		var under := top - DECK_THICK
		kit.box(Vector3(0.0, under - 0.007, z), Vector3(0.055, 0.014, 0.075), METAL.darkened(0.15))
		kit.box(Vector3(0.0, (under - 0.014 + WHEEL_RADIUS) * 0.5, z - end * 0.008), Vector3(0.04, under - 0.014 - WHEEL_RADIUS + 0.02, 0.04), METAL)
		kit.tube(PackedVector3Array([Vector3(-WHEEL_X + 0.012, WHEEL_RADIUS, z), Vector3(WHEEL_X - 0.012, WHEEL_RADIUS, z)]), PackedFloat32Array([0.011, 0.011]), METAL, 8, {"jitter": 0.0})
		kit.tube(PackedVector3Array([Vector3(-0.05, WHEEL_RADIUS + 0.006, z), Vector3(0.05, WHEEL_RADIUS + 0.006, z)]), PackedFloat32Array([0.017, 0.017]), METAL.lightened(0.08), 8, {"jitter": 0.0})
	_deck_mesh = kit.commit()
	return _deck_mesh


## Two wheels on one axle, centered on it (the pivot is at the axle).
static func _wheels() -> ArrayMesh:
	if _wheels_mesh != null:
		return _wheels_mesh
	var kit := _MeshKit.new()
	for side: float in [-1.0, 1.0]:
		kit.wheel(Vector3(side * WHEEL_X, 0.0, 0.0), WHEEL_RADIUS, WHEEL_WIDTH, URETHANE, METAL.lightened(0.15))
		# A worn flat spot, so you can see them turn.
		kit.box(Vector3(side * WHEEL_X, WHEEL_RADIUS * 0.9, 0.0), Vector3(WHEEL_WIDTH * 0.9, 0.006, 0.012), URETHANE.darkened(0.35))
	_wheels_mesh = kit.commit()
	return _wheels_mesh
