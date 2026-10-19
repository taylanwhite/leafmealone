extends RefCounted

## Authority: local, cosmetic. Low-poly looks for the rides in net/components/ride.gd.
## Both face -Z. Seats sit two across at bed height (y 1.0) from z -1.2 back, so
## riders are always visible: Chefty has an open bed, and the van has its right
## side cut away so the captured players can be counted at a glance (docs/ART.md).
## Chefty carries the Chefty logo (DEC-006). The van is the fictional crew's and
## has no lettering or insignia until the crew is designed (OQ-012).

const _LowPoly = preload("res://props/low_poly.gd")
const GLASS := Color(0.16, 0.2, 0.26)
const TIRE := Color(0.1, 0.1, 0.11)
const TRIM := Color(0.85, 0.84, 0.8)


## Chefty: a cab up front and an open bed behind it.
static func build_truck(parent: Node3D, color: Color) -> Node3D:
	var look := _root(parent, "TruckLook")
	_chassis(look, color, 5.6)
	_LowPoly.box(look, Vector3(2.3, 1.45, 1.4), Vector3(0.0, 1.72, -2.0), color)
	_LowPoly.box(look, Vector3(2.1, 0.62, 0.06), Vector3(0.0, 2.05, -2.72), GLASS)
	for side: float in [-1.0, 1.0]:
		_LowPoly.box(look, Vector3(0.06, 0.55, 0.9), Vector3(side * 1.16, 2.05, -2.0), GLASS)
		_LowPoly.box(look, Vector3(0.12, 0.55, 3.9), Vector3(side * 1.15, 1.28, 0.75), color.darkened(0.12))
		_LowPoly.text_sign(look, "Chefty", Vector3(side * 1.2, 1.55, -1.95), 64, TRIM, side * PI * 0.5)
	_LowPoly.box(look, Vector3(2.4, 0.55, 0.12), Vector3(0.0, 1.28, 2.7), color.darkened(0.12))
	_LowPoly.text_sign(look, "Chefty", Vector3(0.0, 1.3, 2.78), 56, TRIM)
	_LowPoly.box(look, Vector3(2.2, 0.25, 0.25), Vector3(0.0, 0.85, -2.85), TRIM)
	return look


## The crew van: a long body with a roof, a solid left side, and an open right side.
static func build_van(parent: Node3D, color: Color) -> Node3D:
	var look := _root(parent, "VanLook")
	_chassis(look, color, 6.4)
	_LowPoly.box(look, Vector3(2.3, 1.9, 1.3), Vector3(0.0, 1.95, -2.55), color)
	_LowPoly.box(look, Vector3(2.1, 0.7, 0.06), Vector3(0.0, 2.3, -3.22), GLASS)
	_LowPoly.box(look, Vector3(2.4, 0.14, 4.8), Vector3(0.0, 3.05, 0.5), color)
	_LowPoly.box(look, Vector3(0.12, 2.05, 4.8), Vector3(-1.16, 2.0, 0.5), color)
	_LowPoly.box(look, Vector3(2.4, 2.05, 0.12), Vector3(0.0, 2.0, 2.9), color)
	# Open right side: two posts and a roof edge frame the riders.
	for z: float in [-1.85, 2.85]:
		_LowPoly.box(look, Vector3(0.14, 2.05, 0.14), Vector3(1.16, 2.0, z), color.darkened(0.15))
	# One amber stripe so it reads as a vehicle from far away, not as any agency's livery.
	_LowPoly.box(look, Vector3(0.04, 0.22, 4.8), Vector3(-1.23, 1.6, 0.5), Color(0.95, 0.62, 0.15))
	return look


static func _root(parent: Node3D, look_name: String) -> Node3D:
	var old := parent.get_node_or_null(look_name)
	if old != null:
		old.free()
	var look := Node3D.new()
	look.name = look_name
	parent.add_child(look)
	return look


static func _chassis(look: Node3D, color: Color, length: float) -> void:
	_LowPoly.box(look, Vector3(2.4, 0.5, length), Vector3(0.0, 0.75, 0.0), color.darkened(0.25))
	for side: float in [-1.0, 1.0]:
		for z: float in [-length * 0.32, length * 0.32]:
			var wheel := _LowPoly.cylinder(look, 0.45, 0.35, Vector3(side * 1.22, 0.45, z), TIRE)
			wheel.rotation.z = PI * 0.5
