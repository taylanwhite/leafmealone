extends Node3D

## Authority: local, cosmetic. The garden hose itself, from where it's hooked up
## to the nozzle in your hands: a rope of points under gravity (verlet), so it
## sags across the lawn, drags along as you walk, and goes taut at full length.
## When it snaps loose (snap()) the far end flies free and whips around for a
## moment before it's put away. While hooked up, the reel sits at the source and
## you hold just the nozzle. Every peer simulates its own copy.

const _WaterSources = preload("res://net/work/water_sources.gd")
const _YardModels = preload("res://props/yard_models.gd")
const SEGMENTS: int = 28
const RADIUS: float = 0.028
const GREEN := Color(0.2, 0.55, 0.28)
const FREE_SECONDS: float = 1.8

var _points := PackedVector3Array()
var _previous := PackedVector3Array()
var _anchored: bool = false
var _free_left: float = 0.0
var _view: MeshInstance3D
var _mesh := ImmediateMesh.new()
var _reel: Node3D


func _ready() -> void:
	top_level = true
	_view = MeshInstance3D.new()
	_view.mesh = _mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = GREEN
	material.roughness = 0.5
	_view.material_override = material
	_view.set_meta("keep_material", true)
	add_child(_view)
	_reel = _YardModels.node("hose")
	_reel.visible = false
	add_child(_reel)


## The hose came loose from where it was hooked up: that end flies free.
func snap(from: Vector3) -> void:
	_free_left = FREE_SECONDS
	_anchored = false
	if _points.size() > 1:
		var toward := (_points[_points.size() - 1] - _points[0]).normalized()
		_previous[0] = _points[0] - toward * 0.35 - Vector3.UP * 0.15


func _physics_process(delta: float) -> void:
	var prop := get_parent() as Node3D
	if prop == null:
		return
	var source_kind := str(prop.get("hose_source"))
	var source := _WaterSources.find(get_tree(), source_kind) if source_kind != "" else null
	var nozzle := _nozzle_point(prop)
	var connected := source != null
	_show_nozzle(prop, connected)
	_reel.visible = connected
	if connected:
		_reel.global_position = source.global_position + Vector3(0.0, -0.3, 0.0)
	if not connected and _free_left <= 0.0:
		_view.visible = false
		_points.clear()
		return
	_free_left = maxf(0.0, _free_left - delta)
	_view.visible = true
	if _points.is_empty():
		var start := source.global_position if connected else nozzle
		_points.resize(SEGMENTS + 1)
		_previous.resize(SEGMENTS + 1)
		for index: int in SEGMENTS + 1:
			var at := start.lerp(nozzle, float(index) / float(SEGMENTS))
			_points[index] = at
			_previous[index] = at
	_anchored = connected
	# Move: keep going, fall, and lose a little to drag.
	var gravity := Vector3(0.0, -9.8, 0.0) * delta * delta
	for index: int in _points.size():
		var now := _points[index]
		_points[index] = now + (now - _previous[index]) * 0.97 + gravity
		_previous[index] = now
	var rest := Constants.HOSE_LENGTH / float(SEGMENTS)
	for _pass: int in 12:
		if _anchored:
			_points[0] = source.global_position
		_points[SEGMENTS] = nozzle
		for index: int in SEGMENTS:
			var a := _points[index]
			var b := _points[index + 1]
			var gap := b - a
			var length := gap.length()
			if length <= rest or length < 0.0001:
				continue
			var fix := gap * (1.0 - rest / length) * 0.5
			var a_free := index != 0 or not _anchored
			var b_free := index + 1 != SEGMENTS
			if a_free and b_free:
				_points[index] = a + fix
				_points[index + 1] = b - fix
			elif a_free:
				_points[index] = a + fix * 2.0
			elif b_free:
				_points[index + 1] = b - fix * 2.0
		for index: int in _points.size():
			if _points[index].y < RADIUS + 0.02:
				_points[index].y = RADIUS + 0.02
	_draw_tube()


func _nozzle_point(prop: Node3D) -> Vector3:
	var visual := prop.get_node_or_null("Visual") as Node3D
	return (visual.global_position if visual != null else prop.global_position) + Vector3(0.0, -0.05, 0.0)


## Hooked up, you hold the nozzle; otherwise the whole reel.
func _show_nozzle(prop: Node3D, connected: bool) -> void:
	var look := prop.get_node_or_null("Visual/Look") as Node3D
	if look == null:
		return
	var nozzle := look.get_node_or_null("Nozzle") as Node3D
	if nozzle == null:
		nozzle = _YardModels.node("nozzle")
		nozzle.name = "Nozzle"
		look.add_child(nozzle)
		nozzle.position = Vector3(0.0, 0.4, 0.0)
	for child: Node in look.get_children():
		if child is Node3D:
			(child as Node3D).visible = (child == nozzle) == connected


func _draw_tube() -> void:
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 5
	for index: int in _points.size() - 1:
		var a := _points[index]
		var b := _points[index + 1]
		var along := (b - a).normalized()
		if along.length() < 0.5:
			continue
		var side := along.cross(Vector3.UP)
		if side.length() < 0.1:
			side = Vector3.RIGHT
		side = side.normalized()
		var other := along.cross(side).normalized()
		for step: int in sides:
			var angle_a := TAU * float(step) / float(sides)
			var angle_b := TAU * float(step + 1) / float(sides)
			var out_a := side * cos(angle_a) + other * sin(angle_a)
			var out_b := side * cos(angle_b) + other * sin(angle_b)
			for corner: Array in [[a, out_a], [b, out_b], [b, out_a], [a, out_a], [a, out_b], [b, out_b]]:
				_mesh.surface_set_normal(corner[1])
				_mesh.surface_add_vertex((corner[0] as Vector3) + (corner[1] as Vector3) * RADIUS)
	_mesh.surface_end()
