extends RefCounted

## Authority: local, cosmetic. Set dressing for the store zone: the Homie Depot
## building along the west edge, a garden-center rack corner, lamp posts, and
## parking lines. Keeps clear of the counter (0, -8), the gate to the lot
## (0, -16), the spawns near (1, 6), and Chefty's pad at (10, 8).

const _LowPoly = preload("res://props/low_poly.gd")
const WALL := Color(0.86, 0.8, 0.66)
const ROOF := Color(0.3, 0.32, 0.36)
const ORANGE := Color(0.95, 0.5, 0.15)
const DARK := Color(0.16, 0.17, 0.2)
const SHELF := Color(0.5, 0.36, 0.24)
const LINE := Color(0.95, 0.94, 0.88)


static func dress(zone: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Dressing"
	zone.add_child(root)
	_building(root)
	_racks(root)
	for corner: Vector3 in [Vector3(17, 0, 17), Vector3(17, 0, -17), Vector3(-9, 0, 17), Vector3(-9, 0, -17)]:
		_lamp(root, corner)
	for index: int in 5:
		_LowPoly.box(root, Vector3(0.12, 0.02, 4.0), Vector3(-6.0 + float(index) * 3.0, 0.01, 15.0), LINE)


## A big box store: solid walls, a flat roof with a lip, an orange band, the
## entrance, and the name in big letters facing the lot.
static func _building(root: Node3D) -> void:
	var at := Vector3(-16.0, 0.0, -2.0)
	_LowPoly.paint(_LowPoly.box(root, Vector3(8.0, 7.0, 24.0), at + Vector3(0, 3.5, 0), WALL, true), "concrete")
	_LowPoly.paint(_LowPoly.box(root, Vector3(8.6, 0.5, 24.6), at + Vector3(0, 7.25, 0), ROOF), "metal")
	_LowPoly.paint(_LowPoly.box(root, Vector3(0.2, 1.4, 24.0), at + Vector3(4.05, 5.6, 0), ORANGE), "metal")
	_LowPoly.text_sign(root, "HOMIE DEPOT", at + Vector3(4.2, 5.6, 0), 260, Color.WHITE, PI * 0.5)
	# Entrance: glass sliding doors in a dark frame, under an orange canopy.
	_LowPoly.box(root, Vector3(0.1, 3.0, 5.0), at + Vector3(4.02, 1.5, 0), DARK)
	for z: float in [-1.2, 1.2]:
		_LowPoly.window(root, 2.2, 2.6, at + Vector3(4.08, 1.35, z), DARK, PI * 0.5)
	_LowPoly.paint(_LowPoly.box(root, Vector3(2.0, 0.25, 6.4), at + Vector3(5.0, 3.4, 0), ORANGE), "metal")
	for z: float in [-3.0, 3.0]:
		_LowPoly.box(root, Vector3(0.2, 3.4, 0.2), at + Vector3(5.9, 1.7, z), DARK)
	for z: float in [-9.0, -6.0, 6.0, 9.0]:
		_LowPoly.window(root, 2.4, 1.6, at + Vector3(4.03, 2.4, z), Color(0.85, 0.85, 0.82), PI * 0.5)
	_carts(root, Vector3(-7.5, 0.0, 9.0))


## Garden-center corner: shelving with stacked boxes and bags.
static func _racks(root: Node3D) -> void:
	var colors: Array[Color] = [ORANGE, Color(0.3, 0.55, 0.3), Color(0.75, 0.68, 0.45), Color(0.45, 0.5, 0.62)]
	for row: int in 3:
		var at := Vector3(10.0 + float(row) * 3.0, 0.0, -13.0)
		_LowPoly.paint(_LowPoly.box(root, Vector3(1.0, 2.4, 5.0), at + Vector3(0, 1.2, 0), SHELF, true), "planks")
		for level: int in 3:
			for slot: int in 4:
				var color := colors[(row + level + slot) % colors.size()]
				_stock(root, at + Vector3(0, 0.34 + float(level) * 0.8, -1.8 + float(slot) * 1.2), color, (row * 7 + level * 3 + slot) % 3)


static func _lamp(root: Node3D, at: Vector3) -> void:
	_LowPoly.paint(_LowPoly.cylinder(root, 0.1, 6.0, at + Vector3(0, 3.0, 0), DARK, true, 6), "metal")
	_LowPoly.paint(_LowPoly.box(root, Vector3(1.2, 0.2, 0.4), at + Vector3(0, 6.0, 0), DARK), "metal")
	_LowPoly.glow(root, Vector3(0.9, 0.08, 0.3), at + Vector3(0, 5.88, 0), Color(1.0, 0.92, 0.7), 2.0)


## One shelf slot's worth of products: fat bags, a row of cans, or boxes.
static func _stock(root: Node3D, at: Vector3, color: Color, kind: int) -> void:
	match kind:
		0:
			for index: int in 2:
				var bag := _LowPoly.ball(root, 0.22, at + Vector3(0, 0.2, -0.22 + index * 0.44), color)
				bag.scale = Vector3(1.6, 1.0, 1.0)
				_LowPoly.paint(bag, "fabric")
		1:
			for index: int in 3:
				_LowPoly.paint(_LowPoly.cylinder(root, 0.11, 0.3, at + Vector3(0, 0.15, -0.3 + index * 0.3), color), "metal")
		_:
			_LowPoly.paint(_LowPoly.box(root, Vector3(0.7, 0.4, 0.8), at + Vector3(0, 0.2, 0), color), "planks")


## A cart corral by the parking lot: a rail frame and a few nested carts.
static func _carts(root: Node3D, at: Vector3) -> void:
	for side: float in [-1.0, 1.0]:
		_LowPoly.paint(_LowPoly.box(root, Vector3(0.08, 0.08, 4.0), at + Vector3(side * 0.6, 0.9, 0), Color(0.85, 0.85, 0.82)), "metal")
		for z: float in [-2.0, 2.0]:
			_LowPoly.paint(_LowPoly.box(root, Vector3(0.08, 0.9, 0.08), at + Vector3(side * 0.6, 0.45, z), Color(0.85, 0.85, 0.82)), "metal")
	for index: int in 3:
		_cart(root, at + Vector3(0, 0, -1.2 + index * 0.7))


static func _cart(root: Node3D, at: Vector3) -> void:
	var red := Color(0.85, 0.3, 0.15)
	var wire := Color(0.8, 0.8, 0.78)
	_LowPoly.paint(_LowPoly.box(root, Vector3(0.6, 0.45, 0.9), at + Vector3(0, 0.75, 0), wire), "metal")
	_LowPoly.paint(_LowPoly.box(root, Vector3(0.62, 0.06, 0.06), at + Vector3(0, 1.05, 0.5), red), "metal")
	for x: float in [-0.25, 0.25]:
		for z: float in [-0.35, 0.35]:
			_LowPoly.paint(_LowPoly.cylinder(root, 0.06, 0.04, at + Vector3(x, 0.07, z), Color(0.12, 0.12, 0.13)), "metal")
