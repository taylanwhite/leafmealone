extends RefCounted

## Authority: local, cosmetic. Real shapes for the yard props in
## props/yard_prop.tscn, built inside the prop's smoothed Visual node so they
## move with it, in place of the gray-box cube. The prop's color is the base.
## The wheelbarrow shows the bags it's carrying.

const _LowPoly = preload("res://props/low_poly.gd")
## The Visual node sits this high above the prop's base.
const VISUAL_HEIGHT: float = 0.35
const BAG_COLOR := Color(0.62, 0.42, 0.2)


static func dress(prop: Node3D, kind: String, color: Color) -> void:
	var visual := prop.get_node_or_null("Visual") as MeshInstance3D
	if visual == null:
		return
	# Rebuild only when the kind changes (it can arrive after the prop is ready).
	var old := visual.get_node_or_null("Look")
	if old != null:
		if str(old.get_meta("kind", "")) == kind:
			return
		old.free()
	var look := Node3D.new()
	look.set_meta("kind", kind)
	look.name = "Look"
	look.position.y = -VISUAL_HEIGHT
	visual.add_child(look)
	match kind:
		"trash":
			_trash_can(look, color)
		"wheelbarrow":
			_wheelbarrow(look, color)
		"gnome":
			_gnome(look)
		"leaf_bag":
			_leaf_bag(look)
		_:
			_LowPoly.paint(_LowPoly.box(look, Vector3(0.7, 0.7, 0.7), Vector3(0, 0.35, 0), color), "planks")
	# The cube stays for its color code, but nothing draws it now.
	visual.mesh = null


## Show this many bags in the wheelbarrow's tray.
static func show_bags(prop: Node3D, count: int) -> void:
	var bags := prop.get_node_or_null("Visual/Look/Bags") as Node3D
	if bags == null:
		return
	for index: int in bags.get_child_count():
		(bags.get_child(index) as Node3D).visible = index < count


static func _trash_can(look: Node3D, color: Color) -> void:
	_LowPoly.paint(_LowPoly.cylinder(look, 0.3, 0.66, Vector3(0, 0.33, 0), color, false, 12), "metal")
	for y: float in [0.15, 0.35, 0.55]:
		_LowPoly.paint(_LowPoly.cylinder(look, 0.315, 0.03, Vector3(0, y, 0), color.darkened(0.2), false, 12), "metal")
	_LowPoly.paint(_LowPoly.cylinder(look, 0.34, 0.06, Vector3(0, 0.69, 0), color.lightened(0.05), false, 12), "metal")
	_LowPoly.paint(_LowPoly.box(look, Vector3(0.22, 0.05, 0.05), Vector3(0, 0.76, 0), color.darkened(0.3)), "metal")


static func _wheelbarrow(look: Node3D, color: Color) -> void:
	# Tray, wheel at the front (-Z), handles and legs at the back.
	_LowPoly.paint(_LowPoly.box(look, Vector3(0.68, 0.06, 0.86), Vector3(0, 0.42, 0), color), "metal")
	for side: float in [-1.0, 1.0]:
		var wall := _LowPoly.box(look, Vector3(0.05, 0.26, 0.86), Vector3(side * 0.34, 0.55, 0), color)
		wall.rotation.z = side * -0.25
		_LowPoly.paint(wall, "metal")
		_LowPoly.paint(_LowPoly.box(look, Vector3(0.05, 0.05, 0.75), Vector3(side * 0.22, 0.45, 0.65), Color(0.5, 0.35, 0.2)), "planks")
		_LowPoly.paint(_LowPoly.box(look, Vector3(0.05, 0.36, 0.05), Vector3(side * 0.22, 0.2, 0.32), Color(0.3, 0.3, 0.32)), "metal")
	for z: float in [-0.43, 0.43]:
		_LowPoly.paint(_LowPoly.box(look, Vector3(0.68, 0.24, 0.05), Vector3(0, 0.55, z), color), "metal")
	var wheel := _LowPoly.cylinder(look, 0.18, 0.1, Vector3(0, 0.18, -0.5), Color(0.12, 0.12, 0.13), false, 10)
	wheel.rotation.z = PI * 0.5
	var bags := Node3D.new()
	bags.name = "Bags"
	look.add_child(bags)
	for index: int in 8:
		var spot := Vector3(-0.15 + (index % 2) * 0.3, 0.62 + floorf(index / 4.0) * 0.22, -0.28 + (index / 2 % 2) * 0.32)
		var bag := _LowPoly.ball(bags, 0.16, spot, BAG_COLOR)
		bag.scale = Vector3(1.0, 0.85, 1.1)
		_LowPoly.paint(bag, "fabric")
		bag.visible = false


## A garden gnome: red pointy hat, white beard, round nose, blue coat.
static func _gnome(look: Node3D) -> void:
	_LowPoly.paint(_LowPoly.cylinder(look, 0.17, 0.3, Vector3(0, 0.15, 0), Color(0.25, 0.4, 0.75), false, 10), "fabric")
	_LowPoly.paint(_LowPoly.box(look, Vector3(0.36, 0.08, 0.22), Vector3(0, 0.04, -0.02), Color(0.2, 0.16, 0.12)), "metal")
	_LowPoly.paint(_LowPoly.ball(look, 0.15, Vector3(0, 0.42, 0), Color(0.95, 0.8, 0.68)), "skin")
	var beard := _LowPoly.cone(look, 0.16, 0.28, Vector3(0, 0.3, -0.06), Color(0.96, 0.96, 0.94))
	beard.rotation.x = PI
	_LowPoly.paint(beard, "fabric")
	_LowPoly.paint(_LowPoly.ball(look, 0.05, Vector3(0, 0.4, -0.15), Color(0.95, 0.6, 0.55)), "skin")
	for side: float in [-1.0, 1.0]:
		_LowPoly.box(look, Vector3(0.035, 0.035, 0.02), Vector3(side * 0.055, 0.47, -0.135), Color(0.05, 0.05, 0.06))
	_LowPoly.paint(_LowPoly.cone(look, 0.17, 0.42, Vector3(0, 0.72, 0.02), Color(0.85, 0.15, 0.12), 10), "fabric")


## A stuffed leaf bag, tied off at the top.
static func _leaf_bag(look: Node3D) -> void:
	var sack := _LowPoly.ball(look, 0.32, Vector3(0, 0.34, 0), BAG_COLOR)
	sack.scale = Vector3(1.0, 1.15, 0.95)
	_LowPoly.paint(sack, "fabric")
	var tie := _LowPoly.cone(look, 0.1, 0.18, Vector3(0, 0.74, 0), BAG_COLOR.darkened(0.15))
	tie.rotation.x = PI
	_LowPoly.paint(tie, "fabric")
