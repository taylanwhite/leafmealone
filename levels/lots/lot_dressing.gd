extends Node3D

## Authority: local, cosmetic. Set dressing for lot 1, built when the lot loads
## on each peer: the house's roof, windows, door, and chimney, picket fences
## along the edges, yard trees that drop the leaves, a driveway, and a mailbox.
## Nothing here has collision, so raking, the crew's navigation, and line of
## sight are unchanged. The house body itself is the solid box in lot_01.tscn.

const _LowPoly = preload("res://props/low_poly.gd")
const PICKET := Color(0.92, 0.9, 0.84)
const ROOF := Color(0.42, 0.24, 0.2)
const GLASS := Color(0.5, 0.65, 0.78)
const DOOR := Color(0.32, 0.22, 0.16)
const TRUNK := Color(0.42, 0.3, 0.2)

## House body center and size, matching the House node in lot_01.tscn.
@export var house_center := Vector3(-8.0, 2.5, -6.0)
@export var house_size := Vector3(8.0, 5.0, 6.0)


func _ready() -> void:
	_house()
	_fences()
	for spot: Vector3 in [Vector3(-17.0, 0.0, 3.0), Vector3(6.0, 0.0, 12.0), Vector3(17.0, 0.0, -6.0)]:
		_LowPoly.round_tree(self, spot, 7.0, Color(0.88, 0.5, 0.16))
	_LowPoly.box(self, Vector3(3.2, 0.03, 10.0), Vector3(-3.0, 0.015, 11.0), Color(0.55, 0.55, 0.52))
	_LowPoly.box(self, Vector3(0.12, 1.1, 0.12), Vector3(3.5, 0.55, 17.5), TRUNK)
	_LowPoly.box(self, Vector3(0.45, 0.35, 0.7), Vector3(3.5, 1.25, 17.5), Color(0.25, 0.3, 0.42))


func _house() -> void:
	var top := house_center.y + house_size.y * 0.5
	var front := house_center.z + house_size.z * 0.5 + 0.03
	var roof := _LowPoly.roof(self, house_size.z + 0.8, 2.6, house_size.x + 0.8, Vector3(house_center.x, top + 1.3, house_center.z), ROOF)
	roof.rotation.y = PI * 0.5
	_LowPoly.box(self, Vector3(0.9, 2.2, 0.9), Vector3(house_center.x + 2.4, top + 1.6, house_center.z - 1.0), Color(0.55, 0.3, 0.25))
	_LowPoly.box(self, Vector3(1.2, 2.2, 0.06), Vector3(house_center.x, 1.1, front), DOOR)
	for x: float in [-2.6, 2.6]:
		_LowPoly.box(self, Vector3(1.6, 1.2, 0.06), Vector3(house_center.x + x, 2.9, front), GLASS)
	_LowPoly.box(self, Vector3(3.0, 0.2, 1.4), Vector3(house_center.x, 0.1, front + 0.7), Color(0.6, 0.58, 0.55))


## A low picket fence just inside the back and side edges, open at the front gate.
func _fences() -> void:
	for x: float in range(-19, 20, 1):
		_picket(Vector3(x, 0.0, -19.4))
	for z: float in range(-18, 13, 1):
		_picket(Vector3(-19.4, 0.0, z))
		_picket(Vector3(19.4, 0.0, z))
	for z: float in [-19.4]:
		_LowPoly.box(self, Vector3(39.0, 0.08, 0.06), Vector3(0.0, 0.55, z), PICKET)
	for x: float in [-19.4, 19.4]:
		_LowPoly.box(self, Vector3(0.06, 0.08, 31.0), Vector3(x, 0.55, -3.0), PICKET)


func _picket(at: Vector3) -> void:
	_LowPoly.box(self, Vector3(0.12, 0.9, 0.06), at + Vector3(0.0, 0.45, 0.0), PICKET)
