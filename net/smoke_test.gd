extends Node

## Authority: host decides pass or fail. The client only reports what it can see.
## Covers connection, handshake, player replication, the world mode arriving with
## the world, a zone change without a teleport, and a host-ordered zone move.

## The test fails as hung when it makes no progress for a while, not when the
## machine is slow: the client's launch and join (a whole second Godot starting and
## building the world: 8.6 s alone, 15.5 s next to 24 busy processes) may take up
## to JOIN_TIMEOUT_SECONDS, each later step STAGE_TIMEOUT_SECONDS (the longest is
## Chefty's ride, 8 s of game time), and the whole run TIMEOUT_SECONDS. One 30 s
## limit for everything timed out 12 runs in 12 on a loaded machine
## (docs/DECISIONS.md, 2026-11-03 "The bot soaks' flakes").
const TIMEOUT_SECONDS: float = 150.0
const JOIN_TIMEOUT_SECONDS: float = 60.0
const STAGE_TIMEOUT_SECONDS: float = 30.0
## How far a zone change without a teleport may move the player (they stand still).
const QUIET_ZONE_MAX_METERS: float = 0.5
## Where the client steps from its spawn slot before that check, so a wrong
## teleport back to a spawn slot moves it measurably.
const QUIET_STEP_OFF: Vector3 = Vector3(4.0, 0.0, 0.0)
## How close to the job site a player sent to the LOT must land.
const LOT_ARRIVAL_METERS: float = 60.0
## Satellite Annex B's pure schedule (R2 chunk 6): the same 200 samples on both peers.
const _Schedule: Script = preload("res://net/annex/annex_schedule.gd")
const SCHEDULE_SAMPLES: int = 200

var _started_msec: int = 0
var _child_pid: int = -1
var _client_id: int = 0
var _saw_players: bool = false
var _moved: bool = false
var _reported_players: bool = false
var _leaf_phase: String = ""
var _watching_leaf: bool = false
var _leaf_at: Vector3 = Vector3.ZERO
var _leaf_expected: int = -1
var _watching_prop: bool = false
var _prop_at: Vector3 = Vector3.ZERO
var _next_clock_probe: float = 0.0
var _reported_van: bool = false
var _quiet_from: Vector3 = Vector3.ZERO
## Each host stage reached and when (seconds since _ready), printed on the way out,
## and when the last one was reached.
var _stages: PackedStringArray = []
var _progress_at: float = 0.0


func _ready() -> void:
	_started_msec = Time.get_ticks_msec()
	if Net.is_smoke_host():
		_launch_client()


func _process(_delta: float) -> void:
	var stuck_for := _elapsed() - _progress_at
	var allowed := JOIN_TIMEOUT_SECONDS if _stages.is_empty() else STAGE_TIMEOUT_SECONDS
	if _elapsed() > TIMEOUT_SECONDS or (Net.is_smoke_host() and stuck_for > allowed):
		_finish(false, "timed out %.0f s in, %.0f s after the last step (steps: %s; saw players %s, moved %s, phase '%s')" % [_elapsed(), stuck_for, ", ".join(_stages), _saw_players, _moved, _leaf_phase])
		return
	if Net.is_smoke_host():
		_host_leaf_step()
		_host_ride_step()
	if Net.is_smoke_client():
		_client_process()


func _on_zone_changed(peer_id: int, zone: Net.Zone) -> void:
	if peer_id != Net.local_peer_id():
		return
	var body := _find_player(peer_id)
	if body == null:
		return
	# Net.set_player_zone: re-labelled where they stand, never teleported.
	if zone == Net.Zone.TOWN:
		_rpc_status.rpc_id(1, "zone_quiet", body.global_position.distance_to(_quiet_from))
		return
	if zone != Net.Zone.LOT:
		return
	# The job site moves in the connected town, so measure from wherever it is.
	var world := _world()
	var site: Node3D = null
	if world != null:
		site = world.get_node_or_null("LotZone") as Node3D
	if site == null or body.global_position.distance_to(site.global_position) > LOT_ARRIVAL_METERS:
		return
	_rpc_status.rpc_id(1, "zone_moved", 0.0)


func _launch_client() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	var arguments := PackedStringArray([
		"--headless",
		"--path",
		project_path,
		"--",
		"--join=127.0.0.1",
		"--port=%d" % Net.listen_port(),
		"--smoke-client",
		"--name=SmokeClient",
	])
	_child_pid = OS.create_process(OS.get_executable_path(), arguments)
	if _child_pid <= 0:
		_finish(false, "could not launch the smoke client")


func _client_process() -> void:
	if not _reported_players and _player_count() >= 2 and _world() != null:
		_reported_players = true
		_report_players_visible()
	if _watching_leaf:
		var field := get_tree().get_first_node_in_group("leaf_field")
		if field != null and _elapsed() >= _next_clock_probe and Net.has_clock_sample() and int(field.call("sample_world", _leaf_at)) == _leaf_expected:
			_next_clock_probe = _elapsed() + 0.5
			_rpc_clock_probe.rpc_id(1, Time.get_ticks_usec() / 1000000.0)
	if not _reported_van:
		# The Courtesy Shuttle (nice_boys:4) has someone in a seat.
		var shuttle := get_tree().get_first_node_in_group("nice_shuttle")
		if shuttle != null and (shuttle.call("boarded_riders") as Array).size() >= 1:
			_reported_van = true
			_rpc_status.rpc_id(1, "van_match", float((shuttle.call("boarded_riders") as Array).size()))
	if _watching_prop:
		var gnome := get_tree().root.find_child("Gnome", true, false) as Node3D
		if gnome != null and gnome.global_position.distance_to(_prop_at) < 1.0:
			_watching_prop = false
			_rpc_status.rpc_id(1, "prop_match", Net.server_time())


func _report_players_visible() -> void:
	Net.player_zone_changed.connect(_on_zone_changed)
	var me := _find_player(Net.local_peer_id())
	if me != null:
		# Step off the spawn slot first (the client owns its body), so a stray
		# teleport on the quiet TOWN change would land back on the slot and show.
		me.global_position += QUIET_STEP_OFF
		await get_tree().physics_frame
		await get_tree().physics_frame
		if not is_instance_valid(me):
			return
		_quiet_from = me.global_position
	# The world mode came with the world's spawn data; the host checks it matches.
	_rpc_status.rpc_id(1, "players_visible", 1.0 if bool(_world().call("is_town_map")) else 0.0)


func _host_leaf_step() -> void:
	if _leaf_phase != "poke":
		return
	var body := _find_player(1)
	var field := get_tree().get_first_node_in_group("leaf_field")
	if body == null or field == null:
		return
	_leaf_phase = "wait"
	field.call("request_collect", body.global_position, 1.2)
	var sampled := int(field.call("sample_world", body.global_position))
	_rpc_leaf_target.rpc_id(_client_id, body.global_position, sampled)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_leaf_target(at: Vector3, expected: int) -> void:
	if not Net.is_smoke_client():
		return
	_leaf_at = at
	_leaf_expected = expected
	_watching_leaf = true


@rpc("any_peer", "call_remote", "reliable")
func _rpc_prop_target(at: Vector3) -> void:
	if not Net.is_smoke_client():
		return
	_prop_at = at
	_watching_prop = true


@rpc("any_peer", "call_remote", "unreliable", 1)
func _rpc_clock_probe(sent_local_seconds: float) -> void:
	if not Net.is_smoke_host():
		return
	_rpc_clock_probe_reply.rpc_id(multiplayer.get_remote_sender_id(), sent_local_seconds, Net.server_time())


@rpc("authority", "call_remote", "unreliable", 1)
func _rpc_clock_probe_reply(sent_local_seconds: float, host_seconds: float) -> void:
	if not Net.is_smoke_client() or not _watching_leaf:
		return
	var received := Time.get_ticks_usec() / 1000000.0
	var rtt := received - sent_local_seconds
	var residual := absf(Net.server_time() - (host_seconds + rtt * 0.5))
	if residual > 0.05:
		return
	_watching_leaf = false
	_rpc_status.rpc_id(1, "leaf_match", residual)


@rpc("authority", "call_remote", "reliable")
func _rpc_schedule_probe(seed: int) -> void:
	if not Net.is_smoke_client():
		return
	_rpc_schedule_sample.rpc_id(1, int(_Schedule.call("hash_samples", seed, SCHEDULE_SAMPLES)))


@rpc("any_peer", "call_remote", "reliable")
func _rpc_schedule_sample(fingerprint: int) -> void:
	if not Net.is_smoke_host() or _leaf_phase != "schedule":
		return
	var director := get_tree().get_first_node_in_group("run_director")
	if director == null:
		_finish(false, "director missing")
		return
	var expected := int(_Schedule.call("hash_samples", int(director.call("hazard_seed")), SCHEDULE_SAMPLES))
	if fingerprint != expected:
		_finish(false, "the Annex schedule differs on the client (%d vs %d)" % [fingerprint, expected])
		return
	_finish(true, "")


## The connected town's ZoneTracker (driving chunk D), on or off; nothing in the
## legacy world.
func _set_tracking(on: bool) -> void:
	var tracker := _world().get_node_or_null("ZoneTracker") if _world() != null else null
	if tracker != null:
		tracker.set_physics_process(on)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_status(stage: String, client_time: float) -> void:
	if not Net.is_smoke_host():
		return
	_client_id = multiplayer.get_remote_sender_id()
	_note_stage(stage)
	if stage == "players_visible" and not _saw_players:
		_saw_players = true
		if _player_count() < 2:
			_finish(false, "host cannot see both players")
			return
		var host_town := _world() != null and bool(_world().call("is_town_map"))
		if (client_time > 0.5) != host_town:
			_finish(false, "client world mode differs from the host's (host town_map %s)" % host_town)
			return
		# In the connected town the host's ZoneTracker would re-label the client
		# (standing on the store's lot) as STORE at once; this step checks Net's own
		# no-teleport relabel, so the tracker waits until the client is sent on.
		_set_tracking(false)
		Net.set_player_zone(_client_id, Net.Zone.TOWN)
	elif stage == "zone_quiet" and _saw_players and not _moved:
		if client_time > QUIET_ZONE_MAX_METERS:
			_finish(false, "a zone change without a teleport moved the client %.2f m" % client_time)
			return
		if Net.player_zone(_client_id) != Net.Zone.TOWN:
			_finish(false, "host registry lost the client's TOWN zone")
			return
		Net.move_player_to_zone(_client_id, Net.Zone.LOT)
		_moved = true
		_set_tracking(true)
	elif stage == "zone_moved" and _moved and _leaf_phase == "":
		Net.move_player_to_zone(1, Net.Zone.LOT)
		_leaf_phase = "poke"
	elif stage == "leaf_match" and _leaf_phase == "wait":
		if client_time > 0.05:
			_finish(false, "clock off by %.3f s" % client_time)
			return
		var gnome := get_tree().root.find_child("Gnome", true, false) as Node3D
		if gnome == null:
			_finish(false, "gnome missing")
			return
		gnome.global_position += Vector3(2.0, 0.5, 0.0)
		_leaf_phase = "prop"
		_rpc_prop_target.rpc_id(_client_id, gnome.global_position)
	elif stage == "prop_match" and _leaf_phase == "prop":
		var ride := get_tree().get_first_node_in_group("rides")
		if ride == null:
			_finish(false, "truck missing")
			return
		_leaf_phase = "ride"
		ride.call("depart", [1], Net.Zone.LOT)
	elif stage == "van_match" and _leaf_phase == "capture":
		var director := get_tree().get_first_node_in_group("run_director")
		if director == null:
			_finish(false, "director missing")
			return
		# Seats taken in the shuttle on both peers == the cohort the host boarded.
		var cohort := int(director.call("cohort_size"))
		var shuttle := get_tree().get_first_node_in_group("nice_shuttle")
		var seats := (shuttle.call("boarded_riders") as Array).size() if shuttle != null else 0
		if cohort < 1 or cohort != seats or int(client_time) != seats:
			_finish(false, "van seats %d (client %d) do not match cohort %d" % [seats, int(client_time), cohort])
			return
		_leaf_phase = "schedule"
		_rpc_schedule_probe.rpc_id(_client_id, int(director.call("hazard_seed")))


func _host_ride_step() -> void:
	if _leaf_phase != "ride":
		return
	var ride := get_tree().get_first_node_in_group("rides")
	if ride != null and not bool(ride.call("is_riding")) and Net.player_zone(1) == Net.Zone.LOT:
		var director := get_tree().get_first_node_in_group("run_director")
		if director == null:
			_finish(false, "director missing")
			return
		_leaf_phase = "capture"
		_note_stage("ride over")
		director.call("force_capture", 1)


func _world() -> Node:
	return get_tree().get_first_node_in_group("world")


func _player_count() -> int:
	return get_tree().get_nodes_in_group("players").size()


func _find_player(peer_id: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node as Node3D
	return null


func _note_stage(stage: String) -> void:
	_stages.append("%s %.1f s" % [stage, _elapsed()])
	_progress_at = _elapsed()


func _elapsed() -> float:
	return float(Time.get_ticks_msec() - _started_msec) / 1000.0


func _finish(ok: bool, reason: String) -> void:
	set_process(false)
	if _child_pid > 0:
		var kill_error := OS.kill(_child_pid)
		if kill_error != OK:
			push_warning("[Smoke] could not kill client pid %d: %s" % [_child_pid, error_string(kill_error)])
	if ok:
		print("[Smoke] passed (%s)" % ", ".join(_stages))
		get_tree().quit(0)
	else:
		push_error("[Smoke] failed: %s" % reason)
		print("[Smoke] failed: %s" % reason)
		get_tree().quit(1)
