extends Node3D

## Authority: local presentation. Rebuilds a chunk's mesh only after that chunk's density changes.

const _Palette: Script = preload("res://assets/materials/palette.gd")
const _COLORS: Array[Color] = [
	_Palette.LEAF_ORANGE,
	_Palette.LEAF_RED,
	_Palette.LEAF_YELLOW,
	_Palette.LEAF_ORANGE,
	Color(0.62, 0.36, 0.18),
	Color(0.8, 0.62, 0.22),
	_Palette.LEAF_RED,
	Color(0.55, 0.58, 0.22),
]
## Leaf length in meters. The mesh is a five-lobed maple leaf (_maple_mesh).
const LEAF_LENGTH: float = 0.3

## Density per drawn flake, and the most flakes one cell draws.
const FLAKE_UNIT: float = 9.0
const MAX_FLAKES: int = 18

var _field: Node3D
var _views: Array[MultiMeshInstance3D] = []
var _leaf_mesh: ArrayMesh
var _material: StandardMaterial3D


func _ready() -> void:
	_field = get_parent() as Node3D
	if _field == null or not _field.has_signal("chunk_changed"):
		push_error("[Leaves] renderer must be a child of a leaf field")
		return
	# Children are ready before their parent, and the field sizes its grid in its
	# own _ready. Asking for chunks before then got 0, and no leaves were drawn.
	if not _field.is_node_ready():
		await _field.ready
	_leaf_mesh = _maple_mesh(LEAF_LENGTH)
	# Each flake's color comes from the multimesh, lit like everything else.
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color.WHITE
	_material.vertex_color_use_as_albedo = true
	# Palette colors are sRGB. Read as linear, they came out pale.
	_material.vertex_color_is_srgb = true
	_material.roughness = 0.9
	# Leaves are one sheet, seen from either side.
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var chunks := int(_field.call("chunk_count"))
	for _index: int in chunks:
		var view := MultiMeshInstance3D.new()
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.mesh = _leaf_mesh
		view.multimesh = multi
		view.material_override = _material
		add_child(view)
		_views.append(view)
	_field.connect("chunk_changed", _rebuild)
	_field.connect("stroke_visual", _burst)
	for chunk_index: int in chunks:
		_rebuild(chunk_index)


func _rebuild(chunk_index: int) -> void:
	if chunk_index < 0 or chunk_index >= _views.size():
		return
	var cells: Array = _field.call("chunk_cells", chunk_index)
	var clean := int(_field.call("clean_density"))
	var spots: Array[Transform3D] = []
	var colors: Array[Color] = []
	for cell: Vector3 in cells:
		var density := int(cell.y)
		var count := _flake_count(density, clean)
		for flake: int in count:
			spots.append(_flake_transform(cell, flake))
			colors.append(_flake_color(cell, flake))
	var multi := _views[chunk_index].multimesh
	multi.instance_count = spots.size()
	for index: int in spots.size():
		multi.set_instance_transform(index, spots[index])
		multi.set_instance_color(index, colors[index])


## A palette leaf color, a little lighter or darker per flake so a carpet of them has texture.
func _flake_color(cell: Vector3, flake: int) -> Color:
	var mix := _mix(cell, flake)
	var base := _COLORS[mix % _COLORS.size()]
	var shade := 0.82 + float((mix / 7) % 6) * 0.06
	return Color(base.r * shade, base.g * shade, base.b * shade)


func _flake_count(density: int, clean: int) -> int:
	if density <= clean:
		return 0
	# One flake per FLAKE_UNIT of density: a fresh lot shows a carpet of four,
	# and a raked pile stacks up into a heap you can see from across the yard.
	return clampi(int(ceil(float(density) / FLAKE_UNIT)), 1, MAX_FLAKES)


func _flake_transform(cell: Vector3, flake: int) -> Transform3D:
	var mix := _mix(cell, flake)
	var along := float(mix % 17) / 16.0 - 0.5
	var across := float((mix / 17) % 17) / 16.0 - 0.5
	var yaw := float(mix % 628) / 100.0
	var tilt := (float((mix / 13) % 41) / 100.0 - 0.2)
	var size := 0.75 + float((mix / 11) % 9) * 0.07
	var basis := Basis.from_euler(Vector3(tilt, yaw, tilt * 0.6)).scaled(Vector3(size, size, size))
	var ground: Vector3 = _field.get("grid_origin")
	# Higher flakes sit closer to the middle, so a pile mounds up instead of a flat stack.
	var spread := 0.5 * (1.0 - float(flake) / float(MAX_FLAKES) * 0.6)
	# The field's origin sits a little above the yard; leaves lie right on the grass.
	var origin := Vector3(cell.x + along * spread, 0.008 + float(flake) * 0.028, cell.z + across * spread)
	return Transform3D(basis, origin)


## A maple leaf lying flat, pointing along -Z: five lobes around a raised
## midrib, edges cupped up a little, and a short stem. About 20 triangles.
static func _maple_mesh(length: float) -> ArrayMesh:
	var outline := PackedVector2Array()
	var points := 25
	for index: int in points:
		var angle := TAU * float(index) / float(points)
		# Five lobes, the front one longest, with a notch between each.
		var lobes := 0.62 + 0.38 * pow(absf(cos(angle * 2.5)), 0.6)
		var front := 0.8 + 0.25 * cos(angle)
		var radius := lobes * front * length * 0.5
		outline.append(Vector2(sin(angle), -cos(angle)) * radius)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var center := Vector3(0.0, 0.018, 0.02 * length)
	for index: int in points:
		var a := outline[index]
		var b := outline[(index + 1) % points]
		# Cupped: the rim rises with distance from the midrib.
		var lift_a := absf(a.x) * 0.12
		var lift_b := absf(b.x) * 0.12
		vertices.append(center)
		vertices.append(Vector3(b.x, lift_b, b.y))
		vertices.append(Vector3(a.x, lift_a, a.y))
		for _corner: int in 3:
			normals.append(Vector3.UP)
	# The stem, a thin sliver off the back.
	var stem_a := Vector3(-0.006, 0.01, length * 0.3)
	var stem_b := Vector3(0.006, 0.01, length * 0.3)
	var stem_end := Vector3(0.0, 0.012, length * 0.48)
	vertices.append_array([stem_a, stem_end, stem_b])
	normals.append_array([Vector3.UP, Vector3.UP, Vector3.UP])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _mix(cell: Vector3, flake: int) -> int:
	var x := int(round(cell.x * 10.0))
	var z := int(round(cell.z * 10.0))
	return absi(x * 73 + z * 151 + flake * 29)


func _burst(at: Vector3) -> void:
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 12
	particles.lifetime = 0.55
	particles.mesh = _leaf_mesh
	var burst_material := _material.duplicate() as StandardMaterial3D
	burst_material.albedo_color = _COLORS[0]
	particles.material_override = burst_material
	particles.direction = Vector3.UP
	particles.spread = 40.0
	particles.initial_velocity_min = 1.2
	particles.initial_velocity_max = 2.4
	particles.gravity = Vector3(0, -6.0, 0)
	particles.emitting = true
	add_child(particles)
	particles.global_position = at
	get_tree().create_timer(1.0).timeout.connect(particles.queue_free)
