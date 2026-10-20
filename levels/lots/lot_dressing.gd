extends Node3D

## Authority: local, cosmetic. Set dressing for lot 1, built when the lot loads
## on each peer: the house's roof, windows, door, and chimney, picket fences
## along the edges, yard trees that drop the leaves, a driveway, and a mailbox.
## Nothing here has collision, so raking, the crew's navigation, and line of
## sight are unchanged. The house body itself is the solid box in lot_01.tscn.

const _LowPoly = preload("res://props/low_poly.gd")
const _Trees = preload("res://props/trees.gd")
const PICKET := Color(0.92, 0.9, 0.84)
const ROOF := Color(0.42, 0.24, 0.2)
const GLASS := Color(0.5, 0.65, 0.78)
const DOOR := Color(0.32, 0.22, 0.16)
const TRIM := Color(0.93, 0.91, 0.86)
const SHUTTER := Color(0.22, 0.38, 0.3)
const TRUNK := Color(0.42, 0.3, 0.2)

## House body center and size, matching the House node in lot_01.tscn.
@export var house_center := Vector3(-8.0, 2.5, -6.0)
@export var house_size := Vector3(8.0, 5.0, 6.0)


func _ready() -> void:
	_house()
	_fences()
	# Clear of the homeowner and the truck by the front gate.
	var crowns: Array[String] = ["orange", "red", "yellow"]
	var spots: Array[Vector3] = [Vector3(-17.0, 0.0, 3.0), Vector3(11.0, 0.0, 15.0), Vector3(17.0, 0.0, -6.0)]
	for index: int in spots.size():
		_Trees.spawn(self, spots[index], 8.0, "broadleaf", crowns[index], index, false, float(index) * 2.1)
	# The driveway Chefty pulls up, from the street to the porch.
	_LowPoly.paint(_LowPoly.box(self, Vector3(4.2, 0.03, 16.0), Vector3(0.0, 0.015, 12.0), Color(0.62, 0.6, 0.57)), "concrete")


func _house() -> void:
	var top := house_center.y + house_size.y * 0.5
	var front := house_center.z + house_size.z * 0.5 + 0.03
	var roof := _LowPoly.roof(self, house_size.z + 0.8, 2.6, house_size.x + 0.8, Vector3(house_center.x, top + 1.3, house_center.z), ROOF)
	roof.rotation.y = PI * 0.5
	_LowPoly.paint(roof, "shingles")
	_LowPoly.paint(_LowPoly.box(self, Vector3(0.9, 2.2, 0.9), Vector3(house_center.x + 2.4, top + 1.6, house_center.z - 1.0), Color(0.55, 0.3, 0.25)), "brick")
	_LowPoly.paint(_LowPoly.box(self, Vector3(1.2, 2.2, 0.06), Vector3(house_center.x, 1.1, front), DOOR), "planks")
	for x: float in [-2.6, 2.6]:
		_LowPoly.window(self, 1.5, 1.2, Vector3(house_center.x + x, 2.9, front), TRIM)
		for side: float in [-1.0, 1.0]:
			_LowPoly.paint(_LowPoly.box(self, Vector3(0.38, 1.38, 0.06), Vector3(house_center.x + x + side * 1.05, 2.9, front + 0.03), SHUTTER), "planks")
	# Side and back windows, so the house isn't a flat box from any angle.
	var half_x := house_size.x * 0.5 + 0.03
	for side: float in [-1.0, 1.0]:
		_LowPoly.window(self, 1.2, 1.1, Vector3(house_center.x + side * half_x, 2.9, house_center.z), TRIM, side * PI * 0.5)
	for x: float in [-2.2, 2.2]:
		_LowPoly.window(self, 1.2, 1.0, Vector3(house_center.x + x, 3.0, house_center.z - house_size.z * 0.5 - 0.03), TRIM, PI)
	# Door frame and knob.
	for side: float in [-1.0, 1.0]:
		_LowPoly.paint(_LowPoly.box(self, Vector3(0.12, 2.35, 0.1), Vector3(house_center.x + side * 0.66, 1.17, front + 0.02), TRIM), "planks")
	_LowPoly.paint(_LowPoly.box(self, Vector3(1.44, 0.12, 0.1), Vector3(house_center.x, 2.32, front + 0.02), TRIM), "planks")
	_LowPoly.paint(_LowPoly.ball(self, 0.05, Vector3(house_center.x + 0.4, 1.05, front + 0.08), Color(0.85, 0.7, 0.3)), "metal")
	# A little porch roof on two posts over the front steps.
	_LowPoly.paint(_LowPoly.box(self, Vector3(3.2, 0.14, 1.7), Vector3(house_center.x, 2.65, front + 0.85), ROOF), "shingles")
	for side: float in [-1.0, 1.0]:
		_LowPoly.paint(_LowPoly.box(self, Vector3(0.14, 2.6, 0.14), Vector3(house_center.x + side * 1.45, 1.3, front + 1.6), TRIM), "planks")
	# A gutter along the front roof edge.
	_LowPoly.paint(_LowPoly.box(self, Vector3(house_size.x + 0.9, 0.12, 0.14), Vector3(house_center.x, top - 0.02, front + 0.42), Color(0.75, 0.75, 0.72)), "metal")
	_LowPoly.paint(_LowPoly.box(self, Vector3(3.0, 0.2, 1.4), Vector3(house_center.x, 0.1, front + 0.7), Color(0.6, 0.58, 0.55)), "concrete")


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
	_LowPoly.paint(_LowPoly.box(self, Vector3(0.12, 0.9, 0.06), at + Vector3(0.0, 0.45, 0.0), PICKET), "planks")
