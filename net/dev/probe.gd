extends Node

## Authority: local. Samples this peer once a second and writes a JSON report
## to the --measure path when the run ends. tools/soak_report.py reads the
## reports from every peer and decides pass or fail.

const _SmootherScript = preload("res://net/components/net_smoother.gd")
const _VoiceScript = preload("res://net/voice/voice.gd")
const _RunCuesScript = preload("res://ui/run_cues.gd")
const _HideSpotScript = preload("res://net/components/hide_spot.gd")
## A frame longer than this stalls sending, so hitches can come from a busy
## machine rather than the network. The report counts them so the two can be told apart.
const LONG_FRAME_SECONDS: float = 0.05

var _long_frames: int = 0
var _throttle_opened: bool = false
## Lowest ENet throttle seen toward any peer after the first second. 32 is full.
var _throttle_min: int = -1
var _throttle_samples: int = 0
## Throttle toward each linked peer, once a second, for diagnosing drops.
var _throttle_trace: Array[int] = []

var _started_msec: int = 0
var _session_msec: int = -1
var _wait: float = 0.0
var _rtt_ms: Array[float] = []
var _fps: Array[float] = []
var _players_seen_max: int = 0
var _errors: Array[String] = []


## Godot's own frame timing, sampled once a second, to tell script time from physics time.
var _process_ms: Array[float] = []
var _physics_ms: Array[float] = []
var _active_bodies: int = 0
var _collision_pairs: int = 0
## This peer's own zones in order, for following captures and returns.
var _zones: Array[String] = []


func _ready() -> void:
	_started_msec = Time.get_ticks_msec()
	Net.player_zone_changed.connect(func(peer_id: int, zone: Net.Zone) -> void:
		if peer_id == Net.local_peer_id():
			_zones.append(Net.Zone.keys()[zone])
	)


## Judder: how unevenly the camera moves from one rendered frame to the next
## while it moves at a steady speed. 0 is perfectly even. Rendering more frames
## than physics ticks without interpolation shows up as steps alternating
## between zero and double.
var _cam_last := Vector3.INF
var _cam_step_last: float = -1.0
var _judder_sum: float = 0.0
var _step_sum: float = 0.0
var _judder_frames: int = 0


## Ride wobble: how far the camera moves relative to the vehicle per frame while
## seated, in meters. 0 means you sit perfectly still in your seat.
var _wobble_sum: float = 0.0
var _wobble_frames: int = 0
var _ride_rel_last := Vector3.INF
var _ride_body_last := Vector3.INF
var _ride_step_last: float = -1.0
var _ride_judder_sum: float = 0.0
var _ride_step_sum: float = 0.0


func _measure_ride_wobble(camera_at: Vector3) -> void:
	var ride_body: Node3D = null
	for ride: Node in get_tree().get_nodes_in_group("rides"):
		if int(ride.call("seat_of", Net.local_peer_id())) >= 0:
			ride_body = ride.get_node_or_null("Body") as Node3D
	if ride_body == null:
		_ride_rel_last = Vector3.INF
		return
	var body_at := ride_body.get_global_transform_interpolated().origin
	var rel := ride_body.get_global_transform_interpolated().affine_inverse() * camera_at
	if _ride_rel_last != Vector3.INF:
		_wobble_sum += rel.distance_to(_ride_rel_last)
		_wobble_frames += 1
		# How evenly the vehicle itself moves from frame to frame.
		var step := body_at.distance_to(_ride_body_last)
		if _ride_step_last >= 0.0:
			_ride_judder_sum += absf(step - _ride_step_last)
			_ride_step_sum += step
		_ride_step_last = step
	_ride_rel_last = rel
	_ride_body_last = body_at


func _measure_judder() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var at := camera.get_global_transform_interpolated().origin
	_measure_ride_wobble(at)
	var walking := false
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()) and node is CharacterBody3D:
			var velocity := (node as CharacterBody3D).velocity
			walking = Vector2(velocity.x, velocity.z).length() > 1.0
	if _cam_last != Vector3.INF:
		var step := Vector2(at.x - _cam_last.x, at.z - _cam_last.z).length()
		# Only steady walking counts. Frames that don't move at all while walking
		# are the judder, so they count too. Teleports and rides don't.
		if walking and step < 0.5 and _cam_step_last >= 0.0 and _cam_step_last < 0.5:
			_judder_sum += absf(step - _cam_step_last)
			_step_sum += step
			_judder_frames += 1
		_cam_step_last = step
	_cam_last = at


func _process(delta: float) -> void:
	_measure_judder()
	if _session_msec >= 0 and delta > LONG_FRAME_SECONDS:
		_long_frames += 1
	if _session_msec < 0 and Net.current_state() == Net.State.IN_SESSION:
		_session_msec = Time.get_ticks_msec()
	_wait += delta
	if _wait < 1.0:
		return
	_wait = 0.0
	_track_throttle()
	_process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	_active_bodies = maxi(_active_bodies, int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)))
	_collision_pairs = maxi(_collision_pairs, int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)))
	_fps.append(Engine.get_frames_per_second())
	_players_seen_max = maxi(_players_seen_max, Net.peer_ids().size())
	if not Net.is_host() and Net.has_clock_sample():
		_rtt_ms.append(Net.clock_rtt_seconds() * 1000.0)


func write_report() -> void:
	var path := str(Net.dev_options().get("measure_path"))
	var session_seconds := 0.0
	if _session_msec >= 0:
		session_seconds = float(Time.get_ticks_msec() - _session_msec) / 1000.0
	var totals := Net.bandwidth_totals()
	var link := multiplayer.multiplayer_peer
	var dropped := int(link.get("packets_dropped")) if link != null and "packets_dropped" in link else 0
	var report := {
		"peer_id": Net.local_peer_id(),
		"name": Net.player_name(Net.local_peer_id()),
		"is_host": Net.is_host(),
		"state": Net.State.keys()[Net.current_state()],
		"zone": Net.Zone.keys()[Net.player_zone(Net.local_peer_id())],
		"simulated_lag_ms": Net.simulated_lag_ms(),
		"session_seconds": session_seconds,
		"players_seen_max": _players_seen_max,
		"players_seen_final": Net.peer_ids().size(),
		"player_nodes_final": get_tree().get_nodes_in_group("players").size(),
		"rtt_ms_median": _percentile(_rtt_ms, 0.5),
		"rtt_ms_p95": _percentile(_rtt_ms, 0.95),
		"bytes_in": totals.x,
		"bytes_out": totals.y,
		"bytes_in_per_second": float(totals.x) / session_seconds if session_seconds > 0.0 else 0.0,
		"bytes_out_per_second": float(totals.y) / session_seconds if session_seconds > 0.0 else 0.0,
		"packets_dropped": dropped,
		"smoother": _SmootherScript.stats.duplicate(),
		"voice": _voice_report(),
		"run_cues": _RunCuesScript.log.duplicate(),
		"job_test": preload("res://net/dev/job_test.gd").result.duplicate(),
		"bonk_test": preload("res://net/dev/bonk_test.gd").result.duplicate(),
		"work_test": preload("res://net/dev/work_test.gd").result.duplicate(),
		"throw_test": preload("res://net/dev/throw_test.gd").result.duplicate(),
		"water_test": preload("res://net/dev/water_test.gd").result.duplicate(),
		"mower_test": preload("res://net/dev/mower_test.gd").result.duplicate(),
		"board_test": preload("res://net/dev/board_test.gd").result.duplicate(),
		"board": _board(),
		"lot_layout": _lot_layout(),
		"job_progress": _job_progress(),
		"hide_spots": _HideSpotScript.stats.duplicate(),
		"zones": _zones,
		"audio_driver": AudioServer.get_driver_name(),
		"leaf_instances": _leaf_instances(),
		"lot_work": _lot_work(),
		"judder": _judder_sum / maxf(_step_sum, 0.0001),
		"judder_frames": _judder_frames,
		"ride_wobble_m": _wobble_sum / maxf(float(_wobble_frames), 1.0),
		"ride_frames": _wobble_frames,
		"ride_judder": _ride_judder_sum / maxf(_ride_step_sum, 0.0001),
		"process_ms_median": _percentile(_process_ms, 0.5),
		"physics_ms_median": _percentile(_physics_ms, 0.5),
		"physics_active_bodies_max": _active_bodies,
		"physics_collision_pairs_max": _collision_pairs,
		"long_frames": _long_frames,
		"enet_throttle_min": _throttle_min,
		"enet_throttle_trace": _throttle_trace,
		"fps_median": _percentile(_fps, 0.5),
		"fps_min": _fps.min() if not _fps.is_empty() else 0.0,
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[Probe] cannot write %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("[Probe] wrote %s" % path)


## The job board's offers (their seeds) and the pick, as this peer sees them.
func _board() -> Dictionary:
	var board := get_tree().get_first_node_in_group("job_board")
	if board == null:
		return {}
	var seeds: Array = []
	for offer: Dictionary in (board.get("offers") as Array):
		seeds.append(int(offer["seed"]))
	return {"seeds": seeds, "chosen": int(board.get("chosen"))}


## The job yard's layout hash (levels/lots/lot_generator.gd), the same on every peer.
func _lot_layout() -> int:
	var lot := get_tree().get_first_node_in_group("job_lot")
	return int(lot.get_meta("layout_hash", 0)) if lot != null else 0


## How far along each task on this job is, as this peer sees it.
func _job_progress() -> Dictionary:
	var tasks := get_tree().get_first_node_in_group("job_tasks")
	var progress: Dictionary = {}
	if tasks != null:
		for task: String in (tasks.get("active") as PackedStringArray):
			progress[task] = snappedf(float(tasks.call("progress", task)), 0.01)
	return progress


## What got done on the lot: how clean it is, bags lying around, and what Chefty
## holds. Bots work the job, so a soak shows whether the loop still runs.
func _lot_work() -> Dictionary:
	var field := get_tree().get_first_node_in_group("leaf_field")
	var chefty := get_tree().get_first_node_in_group("chefty")
	var loose := 0
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) == "leaf_bag":
			loose += 1
	return {
		"cleaned_fraction": float(field.call("cleaned_fraction")) if field != null else 0.0,
		"loose_bags": loose,
		"truck_bags": int(chefty.call("bag_count")) if chefty != null else 0,
		"truck_value": int(chefty.call("bag_value")) if chefty != null else 0,
	}


## Leaf flakes drawn by every leaf renderer on this peer, and where the first one sits.
func _leaf_instances() -> Dictionary:
	var total := 0
	var views := 0
	var first := Vector3.INF
	for field: Node in get_tree().get_nodes_in_group("leaf_field"):
		for child: Node in field.find_children("*", "MultiMeshInstance3D", true, false):
			var view := child as MultiMeshInstance3D
			views += 1
			if view.multimesh == null:
				continue
			total += view.multimesh.instance_count
			if first == Vector3.INF and view.multimesh.instance_count > 0:
				first = view.global_transform * view.multimesh.get_instance_transform(0).origin
	return {"total": total, "views": views, "first_at": str(first)}


func _voice_report() -> Dictionary:
	var voice := Net.get_node_or_null("Voice")
	if voice == null or not bool(voice.call("is_available")):
		return {}
	var stats: Dictionary = _VoiceScript.stats
	var latency: Array[float] = voice.call("latency_samples")
	var received := int(stats["received_packets"])
	var lost := int(stats["lost_packets"])
	return {
		"sent_packets": stats["sent_packets"],
		"sent_bytes": stats["sent_bytes"],
		"received_packets": received,
		"lost_packets": lost,
		"loss_rate": float(lost) / float(maxi(received + lost, 1)),
		"heard_from": (stats["heard_from"] as Dictionary).size(),
		"decode_failures": stats["decode_failures"],
		"underruns": stats["underruns"],
		"dropped_seconds": stats["dropped_seconds"],
		"speaking_changes": stats["speaking_changes"],
		"latency_ms_median": _percentile(latency, 0.5),
		"latency_ms_p95": _percentile(latency, 0.95),
	}


func _track_throttle() -> void:
	var enet := Net.enet_peer()
	if enet == null or Net.current_state() != Net.State.IN_SESSION:
		return
	_throttle_samples += 1
	for packet_peer: ENetPacketPeer in enet.host.get_peers():
		if packet_peer.get_state() != ENetPacketPeer.STATE_CONNECTED:
			continue
		var value := int(packet_peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE))
		if _throttle_trace.size() < 600:
			_throttle_trace.append(value)
		# ENet only raises the throttle on its first round-trip measurement after
		# Net opens it, which can take a few seconds while a session loads. What
		# matters is it falling again once it has been full.
		if value >= ENetPacketPeer.PACKET_THROTTLE_SCALE:
			_throttle_opened = true
		if _throttle_opened:
			_throttle_min = value if _throttle_min < 0 else mini(_throttle_min, value)


func _percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return -1.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(int(round(fraction * (sorted.size() - 1))), 0, sorted.size() - 1)]
