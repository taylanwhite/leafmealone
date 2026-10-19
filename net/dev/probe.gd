extends Node

## Authority: local. Samples this peer once a second and writes a JSON report
## to the --measure path when the run ends. tools/soak_report.py reads the
## reports from every peer and decides pass or fail.

const _SmootherScript = preload("res://net/components/net_smoother.gd")
const _VoiceScript = preload("res://net/voice/voice.gd")
const _RunCuesScript = preload("res://ui/run_cues.gd")
## A frame longer than this stalls sending, so hitches can come from a busy
## machine rather than the network. The report counts them so the two can be told apart.
const LONG_FRAME_SECONDS: float = 0.05

## Once-a-second throttle samples ignored at the start of a session.
const THROTTLE_SETTLE_SAMPLES: int = 3

var _long_frames: int = 0
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


func _process(delta: float) -> void:
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
		"zones": _zones,
		"audio_driver": AudioServer.get_driver_name(),
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
	# ENet only raises the throttle on its first round-trip measurement, so the
	# first seconds of a connection read low before Net opens it.
	if _throttle_samples <= THROTTLE_SETTLE_SAMPLES:
		return
	for packet_peer: ENetPacketPeer in enet.host.get_peers():
		if packet_peer.get_state() != ENetPacketPeer.STATE_CONNECTED:
			continue
		var value := int(packet_peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE))
		_throttle_min = value if _throttle_min < 0 else mini(_throttle_min, value)
		if _throttle_trace.size() < 600:
			_throttle_trace.append(value)


func _percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return -1.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(int(round(fraction * (sorted.size() - 1))), 0, sorted.size() - 1)]
