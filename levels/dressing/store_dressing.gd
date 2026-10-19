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
	_LowPoly.box(root, Vector3(8.0, 7.0, 24.0), at + Vector3(0, 3.5, 0), WALL, true)
	_LowPoly.box(root, Vector3(8.6, 0.5, 24.6), at + Vector3(0, 7.25, 0), ROOF)
	_LowPoly.box(root, Vector3(0.2, 1.4, 24.0), at + Vector3(4.05, 5.6, 0), ORANGE)
	_LowPoly.text_sign(root, "HOMIE DEPOT", at + Vector3(4.2, 5.6, 0), 260, Color.WHITE, PI * 0.5)
	# Entrance: a dark doorway under an orange canopy.
	_LowPoly.box(root, Vector3(0.1, 3.0, 5.0), at + Vector3(4.02, 1.5, 0), DARK)
	_LowPoly.box(root, Vector3(2.0, 0.25, 6.4), at + Vector3(5.0, 3.4, 0), ORANGE)
	for z: float in [-3.0, 3.0]:
		_LowPoly.box(root, Vector3(0.2, 3.4, 0.2), at + Vector3(5.9, 1.7, z), DARK)
	for z: float in [-9.0, 9.0]:
		_LowPoly.box(root, Vector3(0.1, 1.6, 3.0), at + Vector3(4.02, 2.6, z), Color(0.5, 0.65, 0.78))


## Garden-center corner: shelving with stacked boxes and bags.
static func _racks(root: Node3D) -> void:
	var colors: Array[Color] = [ORANGE, Color(0.3, 0.55, 0.3), Color(0.75, 0.68, 0.45), Color(0.45, 0.5, 0.62)]
	for row: int in 3:
		var at := Vector3(10.0 + float(row) * 3.0, 0.0, -13.0)
		_LowPoly.box(root, Vector3(1.0, 2.4, 5.0), at + Vector3(0, 1.2, 0), SHELF, true)
		for level: int in 3:
			for slot: int in 4:
				var color := colors[(row + level + slot) % colors.size()]
				_LowPoly.box(root, Vector3(0.8, 0.45, 0.9), at + Vector3(0, 0.55 + float(level) * 0.8, -1.8 + float(slot) * 1.2), color)


static func _lamp(root: Node3D, at: Vector3) -> void:
	_LowPoly.cylinder(root, 0.1, 6.0, at + Vector3(0, 3.0, 0), DARK, true, 6)
	_LowPoly.box(root, Vector3(1.2, 0.2, 0.4), at + Vector3(0, 6.0, 0), DARK)
	_LowPoly.box(root, Vector3(0.9, 0.08, 0.3), at + Vector3(0, 5.88, 0), Color(1.0, 0.95, 0.7))
