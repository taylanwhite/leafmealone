extends Node3D

## Authority: local presentation, dev only. A minimal leaf view implementing
## contract C3 (gap-specs/raking.json) so the leaf motion layer (leaves/leaf_motion.gd)
## builds, tests and captures before raking:2's real view (leaves/leaf_renderer.gd)
## lands. Hashed hero slots, an eased mound height, and one plain MultiMesh per
## chunk. --leaf-motion-test puts it under the field in place of a renderer without
## the C3 API; nothing in a normal game creates it.
##
## Units: the field's density bytes. Per cell: target (the field at the last
## flush), displayed (units drawn), pending (units the motion layer claimed and
## will deliver), reserved (landing slots handed out but not landed yet). What
## nobody claimed morphs: displayed eases toward target over MORPH_SECONDS.

signal targets_changed(changes: PackedInt32Array, hard: bool)

## Mirrors of raking:2's look constants (LEAF_HERO_UNITS, LEAF_HERO_MAX,
## LEAF_MORPH_SECONDS, LEAF_MOUND_*, LEAF_SIZE), local to this dev stub so it
## compiles without raking:2.
const HERO_UNITS: int = 22
const HERO_MAX: int = 8
const MORPH_SECONDS: float = 0.35
const MOUND_BASE: float = 0.015
const MOUND_HEIGHT: float = 0.75
const MOUND_EXP: float = 1.35
## How fast a cell's drawn height follows its goal (1/s).
const MOUND_EASE: float = 12.0
const LEAF_SIZE := Vector2(0.17, 0.26)
const SLOT_SPREAD: float = 0.3
const SLOT_LIFT: float = 0.004
const SLOT_STEP: float = 0.011
const COLORS: Array[Color] = [
	Color(0.96, 0.66, 0.20), Color(0.82, 0.30, 0.10), Color(0.90, 0.36, 0.15),
	Color(0.96, 0.82, 0.30), Color(0.84, 0.48, 0.18), Color(0.88, 0.56, 0.12),
]
const RIMS: Array[Color] = [
	Color(0.82, 0.30, 0.10), Color(0.58, 0.11, 0.10), Color(0.58, 0.11, 0.10),
	Color(0.88, 0.56, 0.12), Color(0.52, 0.22, 0.10), Color(0.82, 0.30, 0.10),
]

var _field: Node3D
var _w: int = 0
var _d: int = 0
var _cell: float = 0.5
var _origin := Vector3.ZERO
var _chunk_size: int = 16
var _chunks_x: int = 0
var _target := PackedInt32Array()
var _displayed := PackedInt32Array()
var _pending := PackedInt32Array()
var _reserved := PackedInt32Array()
var _height := PackedFloat32Array()
var _height_goal := PackedFloat32Array()
var _moving: Dictionary = {}
var _morphing: Dictionary = {}
var _kicked: Dictionary = {}
var _queued: Dictionary = {}
var _hard_next: bool = true
var _has_reset: bool = false
var _in_emit: bool = false
var _gpu: bool = true
var _views: Array[MultiMeshInstance3D] = []
var _dirty_chunks: Dictionary = {}
var _mesh: ArrayMesh
var _hero_material: StandardMaterial3D
var _mover_material: StandardMaterial3D
var _log_on: bool = false
var _log: Array = []
var _stats := {"hero_instances": 0, "fading": 0, "instant": 0, "morph_units": 0, "rebuild_ms_peak": 0.0, "rebuilds": 0, "slot_mismatch": 0}


func _ready() -> void:
	add_to_group("leaf_view")
	_field = get_parent() as Node3D
	if _field == null or not _field.has_method("density_at_cell"):
		push_error("[LeafViewStub] must be a child of a leaf field")
		return
	if not _field.is_node_ready():
		await _field.ready
	_w = int(_field.get("grid_width"))
	_d = int(_field.get("grid_depth"))
	_cell = float(_field.get("cell_size"))
	_origin = _field.global_transform * (_field.get("grid_origin") as Vector3)
	_chunk_size = int(_field.get("CHUNK_SIZE"))
	_chunks_x = int(ceil(float(_w) / float(_chunk_size)))
	var cells := _w * _d
	_target.resize(cells)
	_displayed.resize(cells)
	_pending.resize(cells)
	_reserved.resize(cells)
	_height.resize(cells)
	_height_goal.resize(cells)
	var headless := DisplayServer.get_name() == "headless"
	var motion_flag := OS.get_cmdline_user_args().has("--leaf-motion-headless")
	_gpu = not headless
	_mesh = leaf_mesh()
	_hero_material = _flake_material_new()
	_mover_material = _flake_material_new()
	if _gpu:
		for _index: int in int(_field.call("chunk_count")):
			var view := MultiMeshInstance3D.new()
			view.multimesh = MultiMesh.new()
			view.multimesh.transform_format = MultiMesh.TRANSFORM_3D
			view.multimesh.use_colors = true
			view.multimesh.use_custom_data = true
			view.multimesh.mesh = _mesh
			view.material_override = _hero_material
			view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			# Slots are world positions (contract C3), so the draw ignores the field's transform.
			view.top_level = true
			add_child(view)
			view.global_transform = Transform3D.IDENTITY
			_views.append(view)
	_has_reset = _field.has_signal("field_reset")
	if _field.has_signal("leaves_changed"):
		_field.connect("leaves_changed", _on_chunk)
	else:
		_field.connect("chunk_changed", _on_chunk)
	if _has_reset:
		_field.connect("field_reset", _on_field_reset)
	for chunk_index: int in int(_field.call("chunk_count")):
		_queued[chunk_index] = true
	if ResourceLoader.exists("res://leaves/leaf_motion.gd") and (not headless or motion_flag):
		var motion: Node3D = (load("res://leaves/leaf_motion.gd") as GDScript).new()
		motion.name = "LeafMotion"
		_field.get_parent().add_child.call_deferred(motion)
		motion.call_deferred("attach", self, _field)


func _on_chunk(chunk_index: int) -> void:
	_queued[chunk_index] = true


func _on_field_reset(hard: bool) -> void:
	if hard:
		_hard_next = true


func _process(delta: float) -> void:
	if _w == 0:
		return
	if not _queued.is_empty():
		_flush()
	_morph(delta)
	_ease_heights(delta)
	if _gpu and not _dirty_chunks.is_empty():
		var started := Time.get_ticks_usec()
		for chunk_index: int in _dirty_chunks:
			_rebuild(chunk_index)
		_dirty_chunks.clear()
		_stats["rebuild_ms_peak"] = maxf(float(_stats["rebuild_ms_peak"]), float(Time.get_ticks_usec() - started) / 1000.0)


func _flush() -> void:
	var all := _queued.size() >= int(_field.call("chunk_count"))
	# Without the field's field_reset (before raking:1), a refresh of every chunk at
	# once is a new field: shape_initial or a join snapshot.
	var hard := _hard_next or (not _has_reset and all)
	_hard_next = false
	if hard:
		_queued.clear()
		_in_emit = true
		targets_changed.emit(PackedInt32Array(), true)
		_in_emit = false
		for z: int in _d:
			for x: int in _w:
				var index := x + z * _w
				var units := int(_field.call("density_at_cell", x, z))
				_target[index] = units
				_displayed[index] = units
				_pending[index] = 0
				_reserved[index] = 0
				_height_goal[index] = mound_height(units)
				_height[index] = _height_goal[index]
		_moving.clear()
		_morphing.clear()
		_kicked.clear()
		for chunk_index: int in int(_field.call("chunk_count")):
			_dirty_chunks[chunk_index] = true
		return
	var changes := PackedInt32Array()
	for chunk_index: int in _queued:
		var cx := (chunk_index % _chunks_x) * _chunk_size
		var cz := int(chunk_index / _chunks_x) * _chunk_size
		for dz: int in _chunk_size:
			for dx: int in _chunk_size:
				var x := cx + dx
				var z := cz + dz
				if x >= _w or z >= _d:
					continue
				var index := x + z * _w
				var units := int(_field.call("density_at_cell", x, z))
				if units != _target[index]:
					changes.append_array([x, z, units - _target[index]])
					_target[index] = units
	_queued.clear()
	if changes.is_empty():
		return
	_in_emit = true
	targets_changed.emit(changes, false)
	_in_emit = false
	for triple: int in changes.size() / 3:
		var index := changes[triple * 3] + changes[triple * 3 + 1] * _w
		if _target[index] - _displayed[index] - _pending[index] != 0:
			_morphing[index] = true


## Whatever nobody claimed eases toward the target.
func _morph(delta: float) -> void:
	if _morphing.is_empty():
		return
	var done: Array[int] = []
	for index: int in _morphing:
		var left := _target[index] - _displayed[index] - _pending[index]
		if left == 0:
			done.append(index)
			continue
		var step := maxi(1, int(ceil(float(absi(left)) * delta / MORPH_SECONDS * 2.0)))
		step = mini(step, absi(left)) * signi(left)
		var before := hero_count(_displayed[index])
		_displayed[index] += step
		_stats["morph_units"] = int(_stats["morph_units"]) + absi(step)
		var after := hero_count(_displayed[index])
		var cell := Vector2i(index % _w, index / _w)
		for k: int in range(mini(before, after), maxi(before, after)):
			_note(cell, k, "morph_in" if after > before else "morph_out")
		_touch(index)
	for index: int in done:
		_morphing.erase(index)
	_stats["fading"] = _morphing.size()


func _ease_heights(delta: float) -> void:
	if _moving.is_empty():
		return
	var blend := 1.0 - exp(-MOUND_EASE * delta)
	var done: Array[int] = []
	for index: int in _moving:
		var goal := _height_goal[index]
		var now := _height[index] + (goal - _height[index]) * blend
		if absf(goal - now) < 0.0005:
			now = goal
			done.append(index)
		_height[index] = now
		if _gpu:
			_dirty_chunks[_chunk_of(index)] = true
	for index: int in done:
		_moving.erase(index)


## The displayed units changed at a cell: its mound eases to the new height.
func _touch(index: int) -> void:
	# Exact units (contract C3: never clamped); only the drawing clamps.
	_height_goal[index] = mound_height(maxi(0, _displayed[index]))
	if not is_equal_approx(_height_goal[index], _height[index]):
		_moving[index] = true
	if _gpu:
		_dirty_chunks[_chunk_of(index)] = true


# ---- contract C3

func claim(cell: Vector2i, delta: int) -> void:
	if not _in_emit:
		push_warning("[LeafViewStub] claim outside targets_changed")
	var index := _index(cell)
	if index >= 0:
		_pending[index] += delta


func take_launch(cell: Vector2i, units: int) -> Dictionary:
	var index := _index(cell)
	if index < 0:
		return _skin(cell, 0)
	var before := hero_count(_displayed[index])
	_displayed[index] -= units
	_pending[index] += units
	var after := hero_count(_displayed[index])
	_touch(index)
	if after >= before:
		return _skin(cell, units)
	for k: int in range(after, before):
		_note(cell, k, "launch")
	return _slot_info(cell, before - 1)


func reserve_landing(cell: Vector2i, units: int) -> Dictionary:
	var index := _index(cell)
	if index < 0:
		return _skin(cell, 1)
	var before := hero_count(_displayed[index] + _reserved[index])
	_reserved[index] += units
	var after := hero_count(_displayed[index] + _reserved[index])
	if after > before:
		return _slot_info(cell, after - 1)
	return _skin(cell, _reserved[index])


func land(cell: Vector2i, units: int, slot: int) -> int:
	var index := _index(cell)
	if index < 0:
		return Engine.get_physics_frames()
	var before := hero_count(_displayed[index])
	_displayed[index] += units
	_reserved[index] = maxi(0, _reserved[index] - units)
	_pending[index] -= units
	var after := hero_count(_displayed[index])
	for k: int in range(before, after):
		_note(cell, k, "land")
	if slot >= 0 and (slot < before or slot >= after):
		_stats["slot_mismatch"] = int(_stats["slot_mismatch"]) + 1
	_touch(index)
	return Engine.get_physics_frames() + 1


func take_slot(cell: Vector2i, k: int) -> Dictionary:
	var index := _index(cell)
	if index >= 0:
		if not _kicked.has(index):
			_kicked[index] = {}
		(_kicked[index] as Dictionary)[k] = true
		_note(cell, k, "kick_take")
		if _gpu:
			_dirty_chunks[_chunk_of(index)] = true
	return _slot_info(cell, k)


func return_slot(cell: Vector2i, k: int) -> void:
	var index := _index(cell)
	if index < 0 or not _kicked.has(index):
		return
	var kicked: Dictionary = _kicked[index]
	kicked.erase(k)
	if kicked.is_empty():
		_kicked.erase(index)
	_note(cell, k, "kick_return")
	if _gpu:
		_dirty_chunks[_chunk_of(index)] = true


func is_kicked(cell: Vector2i, k: int) -> bool:
	var index := _index(cell)
	return index >= 0 and _kicked.has(index) and (_kicked[index] as Dictionary).has(k)


func surface_y(world_xz: Vector2) -> float:
	var u := (world_xz.x - _origin.x) / _cell - 0.5
	var v := (world_xz.y - _origin.z) / _cell - 0.5
	var x0 := int(floor(u))
	var z0 := int(floor(v))
	var fx := u - float(x0)
	var fz := v - float(z0)
	var h00 := _h(x0, z0)
	var h10 := _h(x0 + 1, z0)
	var h01 := _h(x0, z0 + 1)
	var h11 := _h(x0 + 1, z0 + 1)
	return _origin.y + lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)


func slot_world(cell: Vector2i, k: int) -> Transform3D:
	var hash := LeafFlow.hash(cell.x, cell.y, k)
	var near := 1.0 - 0.6 * float(clampi(k, 0, HERO_MAX)) / float(HERO_MAX)
	var off := Vector2(float(hash & 1023) / 1023.0 - 0.5, float((hash >> 10) & 1023) / 1023.0 - 0.5) * 2.0 * SLOT_SPREAD * near
	var yaw := float((hash >> 20) & 255) / 255.0 * TAU
	var tilt := (float((hash >> 4) & 63) / 63.0 - 0.5) * 0.5
	var roll := (float((hash >> 14) & 63) / 63.0 - 0.5) * 0.5
	var size := lerpf(LEAF_SIZE.x, LEAF_SIZE.y, float((hash >> 8) & 31) / 31.0)
	var center := cell_center_world(cell)
	var xz := Vector2(center.x + off.x, center.z + off.y)
	var origin := Vector3(xz.x, surface_y(xz) + SLOT_LIFT + SLOT_STEP * float(k), xz.y)
	return Transform3D(Basis.from_euler(Vector3(tilt, yaw, roll)).scaled(Vector3(size, size, size)), origin)


static func hero_count(units: int) -> int:
	if units <= 8:
		return 0
	return clampi(int(ceil(float(units) / float(HERO_UNITS))), 1, HERO_MAX)


static func mound_height(units: int) -> float:
	return MOUND_BASE * float(mini(units, 60)) / 60.0 + MOUND_HEIGHT * pow(float(maxi(units - 60, 0)) / 195.0, MOUND_EXP)


func cell_of(world: Vector3) -> Vector2i:
	return Vector2i(int(floor((world.x - _origin.x) / _cell)), int(floor((world.z - _origin.z) / _cell)))


func cell_center_world(cell: Vector2i) -> Vector3:
	return Vector3(_origin.x + (float(cell.x) + 0.5) * _cell, _origin.y, _origin.z + (float(cell.y) + 0.5) * _cell)


func species_mesh(_i: int) -> Mesh:
	return _mesh


func flake_material(mode: String) -> Material:
	return _mover_material if mode == "mover" else _hero_material


func displayed_units(cell: Vector2i) -> int:
	var index := _index(cell)
	return _displayed[index] if index >= 0 else 0


func target_units(cell: Vector2i) -> int:
	var index := _index(cell)
	return _target[index] if index >= 0 else 0


func stats() -> Dictionary:
	var heroes := 0
	for index: int in _displayed.size():
		var count := hero_count(_displayed[index])
		if count == 0:
			continue
		heroes += count
		if _kicked.has(index):
			for k: int in _kicked[index]:
				if int(k) < count:
					heroes -= 1
	_stats["hero_instances"] = heroes
	return _stats.duplicate()


func set_flake_log(on: bool) -> void:
	_log_on = on
	_log.clear()


func flake_log() -> Array:
	return _log.duplicate()


## The field's grid size in cells (beyond C3: LeafFlow's edge test).
func grid_size() -> Vector2i:
	return Vector2i(_w, _d)


# ---- helpers

func _slot_info(cell: Vector2i, k: int) -> Dictionary:
	var hash := LeafFlow.hash(cell.x, cell.y, k + 101)
	var pick := hash % COLORS.size()
	var shade := 0.88 + float((hash >> 6) & 31) / 31.0 * 0.22
	var base: Color = COLORS[pick]
	return {"xform": slot_world(cell, k), "color": Color(base.r * shade, base.g * shade, base.b * shade), "custom": RIMS[pick], "species": hash % 3, "slot": k}


## A point on the litter skin inside the cell (no hero flake there to take).
func _skin(cell: Vector2i, salt: int) -> Dictionary:
	var info := _slot_info(cell, HERO_MAX + (salt % 7))
	var xform: Transform3D = info["xform"]
	xform.origin.y = surface_y(Vector2(xform.origin.x, xform.origin.z)) + SLOT_LIFT
	info["xform"] = xform
	info["slot"] = -1
	return info


func _note(cell: Vector2i, k: int, what: String) -> void:
	if _gpu:
		_dirty_chunks[_chunk_of(cell.x + cell.y * _w)] = true
	if _log_on:
		_log.append({"cell": cell, "slot": k, "what": what, "frame": Engine.get_physics_frames()})


func _h(x: int, z: int) -> float:
	return _height[clampi(x, 0, _w - 1) + clampi(z, 0, _d - 1) * _w]


func _index(cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= _w or cell.y >= _d:
		return -1
	return cell.x + cell.y * _w


func _chunk_of(index: int) -> int:
	return int((index % _w) / _chunk_size) + int((index / _w) / _chunk_size) * _chunks_x


func _rebuild(chunk_index: int) -> void:
	if chunk_index < 0 or chunk_index >= _views.size():
		return
	_stats["rebuilds"] = int(_stats["rebuilds"]) + 1
	var cx := (chunk_index % _chunks_x) * _chunk_size
	var cz := int(chunk_index / _chunks_x) * _chunk_size
	var buffer := PackedFloat32Array()
	var count := 0
	for dz: int in _chunk_size:
		for dx: int in _chunk_size:
			var x := cx + dx
			var z := cz + dz
			if x >= _w or z >= _d:
				continue
			var index := x + z * _w
			var heroes := hero_count(_displayed[index])
			var kicked: Dictionary = _kicked.get(index, {})
			for k: int in heroes:
				if kicked.has(k):
					continue
				var info := _slot_info(Vector2i(x, z), k)
				var xform: Transform3D = info["xform"]
				var color: Color = info["color"]
				var rim: Color = info["custom"]
				var b := xform.basis
				buffer.append_array([b.x.x, b.y.x, b.z.x, xform.origin.x, b.x.y, b.y.y, b.z.y, xform.origin.y, b.x.z, b.y.z, b.z.z, xform.origin.z, color.r, color.g, color.b, 1.0, rim.r, rim.g, rim.b, 0.0])
				count += 1
	var multi := _views[chunk_index].multimesh
	multi.instance_count = count
	if count > 0:
		multi.buffer = buffer


func _flake_material_new() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.85
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


## A maple leaf one metre long lying flat along -Z: five lobes round a midrib,
## a slight cup, a stem. Scaled per flake to LEAF_SIZE.
static func leaf_mesh() -> ArrayMesh:
	var outline := PackedVector2Array()
	var points := 25
	for index: int in points:
		var angle := TAU * float(index) / float(points)
		var lobes := 0.62 + 0.38 * pow(absf(cos(angle * 2.5)), 0.6)
		var front := 0.8 + 0.25 * cos(angle)
		outline.append(Vector2(sin(angle), -cos(angle)) * lobes * front * 0.5)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var center := Vector3(0.0, 0.03, 0.02)
	for index: int in points:
		var a := outline[index]
		var b := outline[(index + 1) % points]
		vertices.append(center)
		vertices.append(Vector3(b.x, absf(b.x) * 0.14, b.y))
		vertices.append(Vector3(a.x, absf(a.x) * 0.14, a.y))
		normals.append_array([Vector3.UP, (Vector3.UP + Vector3(b.x, 0.0, b.y) * 0.4).normalized(), (Vector3.UP + Vector3(a.x, 0.0, a.y) * 0.4).normalized()])
	vertices.append_array([Vector3(-0.012, 0.01, 0.3), Vector3(0.0, 0.03, 0.5), Vector3(0.012, 0.01, 0.3)])
	normals.append_array([Vector3.UP, Vector3.UP, Vector3.UP])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
