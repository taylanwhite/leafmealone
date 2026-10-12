extends Node3D

## Authority: local presentation. Rebuilds a chunk's mesh only after that chunk's density changes.

const LEAF_COLOR := Color(0.62, 0.34, 0.12, 1)

var _field: Node3D
var _views: Array[MultiMeshInstance3D] = []
var _leaf_mesh: BoxMesh
var _material: StandardMaterial3D


func _ready() -> void:
	_field = get_parent() as Node3D
	if _field == null or not _field.has_signal("chunk_changed"):
		push_error("[Leaves] renderer must be a child of a leaf field")
		return
	_leaf_mesh = BoxMesh.new()
	_leaf_mesh.size = Vector3(0.42, 1.0, 0.28)
	_material = StandardMaterial3D.new()
	_material.albedo_color = LEAF_COLOR
	var chunks := int(_field.call("chunk_count"))
	for _index: int in chunks:
		var view := MultiMeshInstance3D.new()
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
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
	var multi := _views[chunk_index].multimesh
	multi.instance_count = cells.size()
	for index: int in cells.size():
		var cell: Vector3 = cells[index]
		var height := 0.12 + (cell.y / 255.0) * 0.85
		var yaw := float((int(cell.x * 10.0) * 17 + int(cell.z * 10.0) * 31) % 628) / 100.0
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3(1.0, height, 1.0))
		var origin := Vector3(cell.x, grid_height(height), cell.z)
		multi.set_instance_transform(index, Transform3D(basis, origin))


func grid_height(height: float) -> float:
	var origin: Vector3 = _field.get("grid_origin")
	return origin.y + height * 0.5


func _burst(at: Vector3) -> void:
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 10
	particles.lifetime = 0.55
	particles.mesh = _leaf_mesh
	particles.material_override = _material
	particles.direction = Vector3.UP
	particles.spread = 40.0
	particles.initial_velocity_min = 1.2
	particles.initial_velocity_max = 2.4
	particles.gravity = Vector3(0, -6.0, 0)
	particles.emitting = true
	add_child(particles)
	particles.global_position = at
	get_tree().create_timer(1.0).timeout.connect(particles.queue_free)
