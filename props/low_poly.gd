extends RefCounted

## Authority: local, cosmetic. Small builders for low-poly set dressing made of
## primitive meshes. Colors are snapped to the shared palette by
## levels/shared_look.gd when the nodes enter the tree, so pass the color you mean
## and let the palette decide. Nothing here is networked.
## Art rules: docs/ART.md. 1 unit = 1 meter, Y up, models face -Z.
## paint() says what something is made of (brick, planks, ...), from props/surfaces.gd.


const _SharedLook = preload("res://levels/shared_look.gd")


## Say what node (and every mesh under it) is made of, and repaint it now.
static func paint(node: Node, surface: String) -> Node:
	var meshes: Array[Node] = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.append(node)
	for mesh: Node in meshes:
		mesh.set_meta("surface", surface)
		_SharedLook.restyle(mesh)
	return node


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


## A window set into a wall that faces +Z (rotate the result to face elsewhere):
## glass, a painted frame, a crossbar, and a sill. at is the window's center on
## the wall's surface.
static func window(parent: Node3D, width: float, height: float, at: Vector3, frame_color: Color, yaw: float = 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Window"
	parent.add_child(root)
	root.position = at
	root.rotation.y = yaw
	var glass := box(root, Vector3(width, height, 0.04), Vector3(0, 0, 0.02), Color(0.55, 0.7, 0.82))
	glass.set_meta("keep_material", true)
	(glass as MeshInstance3D).material_override = _glass_material()
	var bar := 0.09
	for side: float in [-1.0, 1.0]:
		paint(box(root, Vector3(bar, height + bar * 2.0, 0.1), Vector3(side * (width * 0.5 + bar * 0.5), 0, 0.05), frame_color), "planks")
		paint(box(root, Vector3(width + bar * 2.0, bar, 0.1), Vector3(0, side * (height * 0.5 + bar * 0.5), 0.05), frame_color), "planks")
	box(root, Vector3(0.05, height, 0.07), Vector3(0, 0, 0.05), frame_color)
	box(root, Vector3(width, 0.05, 0.07), Vector3(0, 0, 0.05), frame_color)
	paint(box(root, Vector3(width + 0.35, 0.08, 0.22), Vector3(0, -height * 0.5 - bar - 0.03, 0.11), frame_color.darkened(0.1)), "planks")
	return root


## A shiny, slightly see-into-able glass for windows: reflective sky tint.
static func _glass_material() -> StandardMaterial3D:
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.42, 0.58, 0.72)
	glass.metallic = 0.4
	glass.roughness = 0.08
	glass.metallic_specular = 0.9
	return glass


## Something that glows, like a lamp head or headlight. Kept out of the shared look.
static func glow(parent: Node3D, size: Vector3, at: Vector3, color: Color, energy: float = 1.5) -> Node3D:
	var light := box(parent, size, at, color) as MeshInstance3D
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	light.material_override = material
	light.set_meta("keep_material", true)
	return light


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
