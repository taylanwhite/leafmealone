extends Node

## Authority: host for who is in the crossing and who finishes.
## Hits are reported by the owning player. Hazard positions are not replicated.
## OQ-011: a miss resets one player. OQ-027: players finish one at a time.
## OQ-022: difficulty scales the hazard timeline. OQ-023: the lot keeps running.

const _Layout: Script = preload("res://border/lane_layout.gd")
const _Timeline: Script = preload("res://border/hazard_timeline.gd")
const _Strings = preload("res://ui/strings.gd")

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
var _guides: Array[Node3D] = []
var _camera: Camera3D
var _exit_mark: Label3D


func _ready() -> void:
	add_to_group("border_return")
	_camera = Camera3D.new()
	_camera.current = false
	add_child(_camera)


func status_line() -> String:
	return _status


## True while the local player is being thrown back to the start of their lane.
## ui/quip_player.gd plays its border_fail line on this, not on the status text.
func is_thrown_back() -> bool:
	return _running and not _local_done and _threw_back


## Host only. Called when the van arrives at the border.
func begin(roster: Array, seed: int) -> void:
	if not Net.is_host() or roster.is_empty():
		return
	_rpc_begin.rpc(roster, seed)
	var telemetry := get_tree().get_first_node_in_group("telemetry")
	if telemetry != null:
		telemetry.call("mark_border_start")
	for index: int in roster.size():
		var peer_id := int(roster[index])
		var lane := index % int(_Layout.LANE_COUNT)
		Net.move_player_to_zone(peer_id, Net.Zone.BORDER, StringName("Lane%d" % lane))
		_apply_bounds(peer_id)


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
		var lane := index % int(_Layout.LANE_COUNT)
		var show := _lane_is_used(lane)
		_hazards[index].visible = show
		if not show:
			continue
		var local: Vector3 = _Timeline.call("position", _seed, index, elapsed, DIFFICULTY)
		_hazards[index].global_position = border.to_global(local)


func _update_status() -> void:
	if _local_done or (_roster.is_empty() and not _staging and not _running):
		_status = ""
		return
	if _staging:
		_status = _Strings.UI["border_step_off"]
		return
	if not _running:
		_status = ""
		return
	if _threw_back:
		_status = _Strings.UI["border_thrown_back"]
		return
	var left := Constants.BORDER_CROSSING_SECONDS - _elapsed()
	if left > 0.0:
		_status = _Strings.UI["border_lanes"] % int(ceil(left))
	else:
		_status = _Strings.UI["border_exit_open"]


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
	if _reported_finish or _elapsed() < Constants.BORDER_CROSSING_SECONDS or not _at_exit(body):
		return
	_reported_finish = true
	if Net.is_host():
		_handle_finish(Net.local_peer_id())
	else:
		_rpc_finish.rpc_id(1)


func _touching_hazard(body: Node3D) -> bool:
	for index: int in _hazards.size():
		if not _hazards[index].visible:
			continue
		# The bar's own footprint, grown by the body's radius: standing anywhere
		# it sweeps gets you, including pressed against the lane's edge.
		var size: Vector3 = _Layout.call("mesh_size", index)
		var reach := float(_Layout.call("hit_radius", index))
		var offset := body.global_position - _hazards[index].global_position
		if absf(offset.x) <= size.x * 0.5 + reach and absf(offset.z) <= size.z * 0.5 + reach:
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
	_bonk_fx(body)
	body.call("play_throwback", start)


## Local presentation: the boing where you were hit, its slide whistle falling
## while play_throwback flies you back (both BORDER_THROWBACK_SECONDS long).
func _bonk_fx(body: Node) -> void:
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null and body is Node3D and not bool(body.call("is_throwing_back")):
		sfx.call("play_at", "crossing_bonk", (body as Node3D).global_position)


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
	if _elapsed() < Constants.BORDER_CROSSING_SECONDS:
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
	# The crew finished and went home while you were crossing: back to the store.
	var slot := get_parent().get_node_or_null("LotZone/LotSlot")
	var yard_waiting := slot != null and slot.get_child_count() > 0
	Net.move_player_to_zone(peer_id, Net.Zone.LOT if yard_waiting else Net.Zone.STORE)
	var telemetry := get_tree().get_first_node_in_group("telemetry")
	if telemetry != null:
		telemetry.call("mark_border_finish", peer_id)
	_rpc_clear.rpc(peer_id)
	var still := 0
	for id: int in _roster:
		if not _finished.has(id):
			still += 1
	if still == 0:
		_rpc_end.rpc()


func _lane_is_used(lane: int) -> bool:
	for peer_id: int in _roster:
		if _lane_of(peer_id) == lane:
			return true
	return false


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
	for guide: Node3D in _guides:
		guide.queue_free()
	_guides.clear()
	_exit_mark = null
	var border := get_parent().get_node_or_null("BorderZone") as Node3D
	if border == null:
		return
	for peer_id: int in _roster:
		_build_lane(border, _lane_of(peer_id))
	for index: int in int(_Layout.call("hazard_count")):
		var mesh := BoxMesh.new()
		mesh.size = _Layout.call("mesh_size", index)
		var view := MeshInstance3D.new()
		view.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.95, 0.18, 0.08)
		material.emission_enabled = true
		material.emission = Color(0.85, 0.12, 0.05)
		view.material_override = material
		# Glowing on purpose: the shared look must not repaint it.
		view.set_meta("keep_material", true)
		add_child(view)
		_hazards.append(view)


func _build_lane(border: Node3D, lane: int) -> void:
	var center_x := float(_Layout.call("lane_center_x", lane))
	var length := float(_Layout.HALF_LENGTH) * 2.0
	var strip := MeshInstance3D.new()
	var strip_mesh := BoxMesh.new()
	strip_mesh.size = Vector3(3.2, 0.06, length)
	strip.mesh = strip_mesh
	var strip_material := StandardMaterial3D.new()
	strip_material.albedo_color = Color(0.85, 0.78, 0.35)
	strip.material_override = strip_material
	strip.position = Vector3(center_x, 0.04, 0.0)
	border.add_child(strip)
	_guides.append(strip)
	var exit_pad := MeshInstance3D.new()
	var exit_mesh := BoxMesh.new()
	exit_mesh.size = Vector3(3.2, 0.08, 1.4)
	exit_pad.mesh = exit_mesh
	var exit_material := StandardMaterial3D.new()
	exit_material.albedo_color = Color(0.2, 0.75, 0.28)
	exit_material.emission_enabled = true
	exit_material.emission = Color(0.15, 0.55, 0.2)
	exit_pad.material_override = exit_material
	exit_pad.set_meta("keep_material", true)
	exit_pad.position = Vector3(center_x, 0.06, float(_Layout.HALF_LENGTH) - 0.6)
	border.add_child(exit_pad)
	_guides.append(exit_pad)
	var exit_label := Label3D.new()
	exit_label.text = _Strings.UI["border_exit_mark"]
	exit_label.font_size = 96
	exit_label.modulate = Color(0.4, 1.0, 0.45)
	exit_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	exit_label.position = Vector3(center_x, 2.4, float(_Layout.HALF_LENGTH))
	border.add_child(exit_label)
	_guides.append(exit_label)
	var hint := Label3D.new()
	hint.text = _Strings.UI["border_hint"]
	hint.font_size = 48
	hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hint.position = Vector3(center_x, 2.6, -float(_Layout.HALF_LENGTH))
	border.add_child(hint)
	_guides.append(hint)
	_exit_mark = exit_label


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
	_camera.global_position = body.global_position + Vector3(0.0, 7.0, -9.0)
	_camera.look_at(body.global_position + Vector3(0.0, 1.0, 7.0), Vector3.UP)


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
	# The starting pistol, for the ones crossing (local presentation).
	if _roster.has(Net.local_peer_id()) and not _finished.has(Net.local_peer_id()):
		var sfx := get_tree().get_first_node_in_group("sfx")
		if sfx != null:
			sfx.call("play", "crossing_go")
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
		_bonk_fx(body)
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
	# "Made It Back" over the music (local presentation).
	var music := get_tree().get_first_node_in_group("music_director")
	if music != null:
		music.call("stinger", &"st_made_it")
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
	for guide: Node3D in _guides:
		guide.queue_free()
	_guides.clear()
	_exit_mark = null
	_status = ""
	_camera.current = false
