extends Node

## Authority: host for who is in the crossing and who finishes.
## Hits are reported by the owning player. Hazard positions are not replicated.
## OQ-011: a miss resets one player. OQ-027: players finish one at a time.
## OQ-022: difficulty scales the hazard timeline. OQ-023: the lot keeps running.

const _Layout: Script = preload("res://border/lane_layout.gd")
const _Timeline: Script = preload("res://border/hazard_timeline.gd")

## OQ-011. Set true to send the whole cohort back and restart the clock.
const RESET_WHOLE_COHORT: bool = false
## OQ-027. Set true to hold everyone until the last player reaches the exit.
const FINISH_AS_GROUP: bool = false
## OQ-022. 1 is the workbook pace.
const DIFFICULTY: float = 1.0

var _roster: Array[int] = []
var _finished: Array[int] = []
var _seed: int = 0
var _start_time: float = 0.0
var _staging: bool = false
var _staging_left: float = 0.0
var _running: bool = false
var _local_done: bool = false
var _threw_back: bool = false
var _reported_finish: bool = false
var _status: String = ""
var _hazards: Array[MeshInstance3D] = []
var _camera: Camera3D
var _exit_mark: Label3D


func _ready() -> void:
	add_to_group("border_return")
	_camera = Camera3D.new()
	_camera.current = false
	add_child(_camera)


func status_line() -> String:
	return _status


## Host only. Called when the van arrives at the border.
func begin(roster: Array, seed: int) -> void:
	if not Net.is_host() or roster.is_empty():
		return
	_rpc_begin.rpc(roster, seed)
	for index: int in roster.size():
		var peer_id := int(roster[index])
		var lane := index % int(_Layout.LANE_COUNT)
		Net.move_player_to_zone(peer_id, Net.Zone.BORDER, StringName("Lane%d" % lane))


func _process(delta: float) -> void:
	if _staging and Net.is_host():
		_staging_left -= delta
		if _staging_left <= 0.0:
			_staging = false
			_rpc_go.rpc(Net.server_time())
	_place_hazards()
	_update_status()
	_check_local_player()
	_update_camera()


func _duration() -> float:
	return Balance.BORDER_RETURN_TARGET_DURATION_MINUTES * 60.0


func _elapsed() -> float:
	if not _running:
		return 0.0
	return maxf(Net.server_time() - _start_time, 0.0)


func _place_hazards() -> void:
	if _hazards.is_empty():
		return
	var border := get_parent().get_node_or_null("BorderZone") as Node3D
	if border == null:
		return
	var elapsed := _elapsed()
	for index: int in _hazards.size():
		var local: Vector3 = _Timeline.call("position", _seed, index, elapsed, DIFFICULTY)
		_hazards[index].global_position = border.to_global(local)


func _update_status() -> void:
	if _local_done or (_roster.is_empty() and not _staging and not _running):
		_status = ""
		return
	if _staging:
		_status = "Step off the van"
		return
	if not _running:
		_status = ""
		return
	if _threw_back:
		_status = "Thrown back"
		return
	var left := _duration() - _elapsed()
	if left > 0.0:
		_status = "Cross back. Exit opens in %d s" % int(ceil(left))
	else:
		_status = "Exit is open. Reach the far line."


func _check_local_player() -> void:
	if _local_done or not _running or not _roster.has(Net.local_peer_id()):
		return
	var body := _player(Net.local_peer_id())
	if body == null:
		return
	if bool(body.call("is_throwing_back")):
		_threw_back = true
		return
	_threw_back = false
	if _touching_hazard(body):
		_reported_finish = false
		_throw_local(body)
		if Net.is_host():
			_handle_hit(Net.local_peer_id())
		else:
			_rpc_hit.rpc_id(1)
		return
	if _reported_finish or _elapsed() < _duration() or not _at_exit(body):
		return
	_reported_finish = true
	if Net.is_host():
		_handle_finish(Net.local_peer_id())
	else:
		_rpc_finish.rpc_id(1)


func _touching_hazard(body: Node3D) -> bool:
	for index: int in _hazards.size():
		var radius := float(_Layout.call("hit_radius", index))
		var flat := Vector2(body.global_position.x, body.global_position.z)
		var hazard := _hazards[index].global_position
		if flat.distance_to(Vector2(hazard.x, hazard.z)) <= radius:
			return true
	return false


func _at_exit(body: Node3D) -> bool:
	var border := get_parent().get_node_or_null("BorderZone") as Node3D
	if border == null:
		return false
	var local: Vector3 = border.to_local(body.global_position)
	return local.z >= float(_Layout.HALF_LENGTH) - 2.0


func _throw_local(body: Node) -> void:
	var border := get_parent().get_node("BorderZone") as Node3D
	var lane := _lane_of(Net.local_peer_id())
	var start := border.to_global(Vector3(float(_Layout.call("lane_center_x", lane)), 0.1, -float(_Layout.HALF_LENGTH)))
	body.call("play_throwback", start)


func _handle_hit(peer_id: int) -> void:
	if not Net.is_host() or not _roster.has(peer_id) or _finished.has(peer_id):
		return
	if Net.player_zone(peer_id) != Net.Zone.BORDER:
		return
	if RESET_WHOLE_COHORT:
		_rpc_go.rpc(Net.server_time())
		for id: int in _roster:
			if id != peer_id and not _finished.has(id):
				_send_throwback(id)


func _send_throwback(peer_id: int) -> void:
	if peer_id == Net.local_peer_id():
		return
	var border := get_parent().get_node("BorderZone") as Node3D
	var lane := _lane_of(peer_id)
	var start := border.to_global(Vector3(float(_Layout.call("lane_center_x", lane)), 0.1, -float(_Layout.HALF_LENGTH)))
	_rpc_throwback.rpc_id(peer_id, start)


func _handle_finish(peer_id: int) -> void:
	if not Net.is_host() or not _running or not _roster.has(peer_id) or _finished.has(peer_id):
		return
	if _elapsed() < _duration():
		return
	var body := _player(peer_id)
	if body == null or not _at_exit(body):
		return
	_finished.append(peer_id)
	if FINISH_AS_GROUP and _finished.size() < _roster.size():
		return
	var leaving: Array[int] = []
	if FINISH_AS_GROUP:
		leaving = _finished.duplicate()
	else:
		leaving.append(peer_id)
	for id: int in leaving:
		_send_home(id)


func _send_home(peer_id: int) -> void:
	var director := get_parent().get_node_or_null("RunDirector")
	if director != null and director.has_method("release_peer"):
		director.call("release_peer", peer_id)
	Net.move_player_to_zone(peer_id, Net.Zone.LOT)
	_rpc_clear.rpc(peer_id)
	var still := 0
	for id: int in _roster:
		if not _finished.has(id):
			still += 1
	if still == 0:
		_rpc_end.rpc()


func _lane_of(peer_id: int) -> int:
	var index := _roster.find(peer_id)
	if index < 0:
		return 0
	return index % int(_Layout.LANE_COUNT)


func _apply_bounds(peer_id: int) -> void:
	var border := get_parent().get_node("BorderZone") as Node3D
	var center_x := float(_Layout.call("lane_center_x", _lane_of(peer_id)))
	var origin := border.global_position
	var min_corner := origin + Vector3(center_x - 1.6, 0.0, -float(_Layout.HALF_LENGTH) - 1.0)
	var max_corner := origin + Vector3(center_x + 1.6, 3.0, float(_Layout.HALF_LENGTH) + 1.0)
	_rpc_bounds.rpc(peer_id, true, min_corner, max_corner)


func _build_visuals() -> void:
	for hazard: MeshInstance3D in _hazards:
		hazard.queue_free()
	_hazards.clear()
	if _exit_mark != null:
		_exit_mark.queue_free()
		_exit_mark = null
	var border := get_parent().get_node_or_null("BorderZone") as Node3D
	if border == null:
		return
	for index: int in int(_Layout.call("hazard_count")):
		var mesh := BoxMesh.new()
		mesh.size = _Layout.call("mesh_size", index)
		var view := MeshInstance3D.new()
		view.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.55, 0.32, 0.14) if int(_Layout.call("kind", index)) == 0 else Color(0.72, 0.55, 0.16)
		view.material_override = material
		var label := Label3D.new()
		label.text = str(_Layout.call("label_for", index))
		label.font_size = 42
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(0.0, 0.8, 0.0)
		view.add_child(label)
		add_child(view)
		_hazards.append(view)
	_exit_mark = Label3D.new()
	_exit_mark.text = "Exit"
	_exit_mark.font_size = 72
	_exit_mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_exit_mark.position = Vector3(0.0, 2.2, float(_Layout.HALF_LENGTH))
	border.add_child(_exit_mark)


func _update_camera() -> void:
	if _camera == null:
		return
	if _local_done or not _roster.has(Net.local_peer_id()) or (not _staging and not _running):
		_camera.current = false
		return
	var body := _player(Net.local_peer_id())
	if body == null:
		_camera.current = false
		return
	_camera.current = true
	_camera.global_position = body.global_position + Vector3(0.0, 9.0, -8.0)
	_camera.look_at(body.global_position + Vector3(0.0, 0.5, 8.0), Vector3.UP)


func _player(peer_id: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id) and node is Node3D:
			return node as Node3D
	return null


@rpc("authority", "call_local", "reliable")
func _rpc_begin(roster: Array, seed: int) -> void:
	_roster.clear()
	_finished.clear()
	for entry: Variant in roster:
		_roster.append(int(entry))
	_seed = seed
	_running = false
	_local_done = false
	_threw_back = false
	_reported_finish = false
	_staging = true
	_staging_left = Constants.BORDER_STAGING_SECONDS
	_build_visuals()
	if _roster.has(Net.local_peer_id()):
		var body := _player(Net.local_peer_id())
		if body != null and body.has_method("set_crossing_view"):
			body.call("set_crossing_view", true)


@rpc("authority", "call_local", "reliable")
func _rpc_go(start_time: float) -> void:
	_staging = false
	_running = true
	_start_time = start_time
	if Net.is_host():
		for peer_id: int in _roster:
			if not _finished.has(peer_id):
				_apply_bounds(peer_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_hit() -> void:
	if Net.is_host():
		_handle_hit(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_finish() -> void:
	if Net.is_host():
		_handle_finish(multiplayer.get_remote_sender_id())


@rpc("authority", "call_remote", "reliable")
func _rpc_throwback(to: Vector3) -> void:
	var body := _player(Net.local_peer_id())
	if body != null and body.has_method("play_throwback"):
		body.call("play_throwback", to)


@rpc("authority", "call_local", "reliable")
func _rpc_bounds(peer_id: int, enabled: bool, min_corner: Vector3, max_corner: Vector3) -> void:
	if peer_id != Net.local_peer_id():
		return
	var body := _player(peer_id)
	if body != null and body.has_method("set_crossing_bounds"):
		body.call("set_crossing_bounds", enabled, min_corner, max_corner)


@rpc("authority", "call_local", "reliable")
func _rpc_clear(peer_id: int) -> void:
	if not _finished.has(peer_id):
		_finished.append(peer_id)
	if peer_id != Net.local_peer_id():
		return
	_local_done = true
	_camera.current = false
	var body := _player(peer_id)
	if body == null:
		return
	if body.has_method("set_crossing_view"):
		body.call("set_crossing_view", false)
	if body.has_method("set_crossing_bounds"):
		body.call("set_crossing_bounds", false, Vector3.ZERO, Vector3.ZERO)


@rpc("authority", "call_local", "reliable")
func _rpc_end() -> void:
	_running = false
	_staging = false
	_roster.clear()
	for hazard: MeshInstance3D in _hazards:
		hazard.queue_free()
	_hazards.clear()
	if _exit_mark != null:
		_exit_mark.queue_free()
		_exit_mark = null
	_status = ""
	_camera.current = false
