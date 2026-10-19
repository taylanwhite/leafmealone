extends RefCounted

## Authority: local, cosmetic. Small builders for low-poly set dressing made of
## primitive meshes. Colors are snapped to the shared palette by
## levels/flat_look.gd when the nodes enter the tree, so pass the color you mean
## and let the palette decide. Nothing here is networked.
## Art rules: docs/ART.md. 1 unit = 1 meter, Y up, models face -Z.


static func box(parent: Node3D, size: Vector3, at: Vector3, color: Color, solid: bool = false) -> Node3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _place(parent, mesh, at, color, solid, _box_shape(size))


static func cylinder(parent: Node3D, radius: float, height: float, at: Vector3, color: Color, solid: bool = false, sides: int = 8) -> Node3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	return _place(parent, mesh, at, color, solid, shape)


static func cone(parent: Node3D, radius: float, height: float, at: Vector3, color: Color, sides: int = 7) -> Node3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	return _place(parent, mesh, at, color, false, null)


static func ball(parent: Node3D, radius: float, at: Vector3, color: Color) -> Node3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 7
	mesh.rings = 4
	return _place(parent, mesh, at, color, false, null)


## A gable roof: a triangular prism lying along Z, its ridge at the top.
static func roof(parent: Node3D, width: float, height: float, depth: float, at: Vector3, color: Color) -> Node3D:
	var mesh := PrismMesh.new()
	mesh.size = Vector3(width, height, depth)
	return _place(parent, mesh, at, color, false, null)


## A tree: a trunk with a few stacked low-poly cones. Solid at the trunk only.
static func tree(parent: Node3D, at: Vector3, height: float, leaf_color: Color, solid: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "Tree"
	parent.add_child(root)
	root.position = at
	var trunk_height := height * 0.35
	cylinder(root, height * 0.05, trunk_height, Vector3(0.0, trunk_height * 0.5, 0.0), Color(0.42, 0.3, 0.2), solid, 6)
	var tiers := 3
	for tier: int in tiers:
		var size := 1.0 - float(tier) * 0.22
		var radius := height * 0.28 * size
		var tier_height := height * 0.32
		cone(root, radius, tier_height, Vector3(0.0, trunk_height + tier_height * 0.5 + float(tier) * tier_height * 0.55, 0.0), leaf_color)
	return root


## A round tree: a trunk and a lumpy ball, for the yard.
static func round_tree(parent: Node3D, at: Vector3, height: float, leaf_color: Color, solid: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "RoundTree"
	parent.add_child(root)
	root.position = at
	var trunk_height := height * 0.45
	cylinder(root, height * 0.06, trunk_height, Vector3(0.0, trunk_height * 0.5, 0.0), Color(0.42, 0.3, 0.2), solid, 6)
	var crown := height * 0.33
	ball(root, crown, Vector3(0.0, trunk_height + crown * 0.7, 0.0), leaf_color)
	ball(root, crown * 0.7, Vector3(crown * 0.6, trunk_height + crown * 0.4, crown * 0.2), leaf_color.darkened(0.08))
	ball(root, crown * 0.65, Vector3(-crown * 0.5, trunk_height + crown * 0.5, -crown * 0.3), leaf_color.lightened(0.05))
	return root


## Flat text on a surface, readable from far away. Faces +Z unless rotated.
static func text_sign(parent: Node3D, text: String, at: Vector3, font_size: int, color: Color, yaw: float = 0.0) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.outline_size = maxi(4, font_size / 8)
	label.modulate = color
	label.outline_modulate = Color(0.08, 0.08, 0.1)
	label.position = at
	label.rotation.y = yaw
	label.double_sided = false
	parent.add_child(label)
	return label


static func _place(parent: Node3D, mesh: Mesh, at: Vector3, color: Color, solid: bool, shape: Shape3D) -> Node3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.material_override = material
	if not solid or shape == null:
		parent.add_child(view)
		view.position = at
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return view
	var body := StaticBody3D.new()
	parent.add_child(body)
	body.position = at
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	body.add_child(view)
	return body


static func _box_shape(size: Vector3) -> BoxShape3D:
	var shape := BoxShape3D.new()
	shape.size = size
	return shape
