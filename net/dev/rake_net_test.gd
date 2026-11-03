extends Node

## --rake-net-test (raking:1, port 7821, host plus a Target client, both with
## --sim-lag=150 --sim-loss=2 --rake-net-test). Both peers run this node; the host
## drives and cues the client through this node's own RPCs.
##
## Host: the golden density rules (net/dev/leaf_golden.gd) first; then its own
## stroke (one event, local, leaves_changed the same frame) and 3 s of a running
## mower (at most 11 mulch events a second); then it clears a bare patch, gives
## the blower tier 2 and a full tank, picks the spots and cues the client.
## Client: holding the rake it rakes a lane 30 times toward +X and 20 toward -Z,
## 0.3 s apart, plus 3 strokes on the bare patch (moved 0) and one out of reach;
## then 10 tier-2 blower puffs, a bag of its pile and a bag of the bare patch
## (refused: thin). Throughout, every cell it shows is checked every frame against
## what its own strokes left there: no cell a stroke raised ever falls back
## (reversals), and nothing changes that its own strokes didn't do (corrections).
## The ledger never holds more than 4 and empties within 1 s; every stroke is
## one event on each peer (its own local, the echo never re-emitted); the
## out-of-reach stroke and the refused bag make no event but a soft reset; the
## join was a hard one. At the end both peers' bytes are the same, and so are
## leaf_units, cleaned_fraction and units_within_world, against a reference field
## that replayed the client's strokes on a copy. Event logs and the cell trace go
## to build/r1/net/. Each step prints a [RakeNetTest] line.

const _Golden = preload("res://net/dev/leaf_golden.gd")
const _FieldScript: Script = preload("res://net/leaf_field/leaf_field.gd")
const LANE_X_STROKES: int = 30
const LANE_Z_STROKES: int = 20
const LANE_STEP: float = 0.25
const STROKE_SECONDS: float = 0.3
const BARE_STROKES: int = 3
const BLOWER_PUFFS: int = 10
const BLOWER_TIER: int = 2
## The swing tempo the lane strokes claim (raking:4's 0.6 s swing), carried on the events.
const TEMPO: float = 0.6
const LEDGER_MAX: int = 4
const LEDGER_EMPTY_SECONDS: float = 1.0
const MULCH_PER_SECOND_MAX: int = 11
const MOW_SECONDS: float = 3.0
const CLIENT_WAIT_SECONDS: float = 30.0
const REPORT_WAIT_SECONDS: float = 55.0

static var result: Dictionary = {}

var _started: bool = false
var _steps: Dictionary = {}
var _field_node: Node3D
# Every stroke event this peer saw: {kind, actor, seq, moved, ack, local, bite, frame, msec}.
var _events: Array[Dictionary] = []
var _resets: Array[bool] = []
var _changed_frames: Dictionary = {}
var _refusals: Array[String] = []
var _bags_requested: int = 0
# Client: the host's cue, and what the field should show from its own strokes.
var _cue: Dictionary = {}
var _tracking: bool = false
var _expected := PackedByteArray()
var _raised := PackedByteArray()
var _reversals: int = 0
var _corrections: int = 0
var _trace: Array[Dictionary] = []
var _ledger_peak: int = 0
var _reference: Node3D
var _report: Dictionary = {}


func _process(_delta: float) -> void:
	_hook_field()
	if _tracking:
		_track()
		var field := _field()
		if field != null:
			_ledger_peak = maxi(_ledger_peak, int(field.call("pending_count")))
	if _started:
		return
	var lot := get_tree().get_first_node_in_group("job_lot")
	if lot == null or not bool(lot.get("is_generated")) or _field() == null or _me() == null:
		return
	_started = true
	if Net.is_host():
		_run_host(lot as Node3D)
	else:
		_run_client()


## Listen to whichever leaf field is current (a new lot makes a new one).
func _hook_field() -> void:
	var field := _field()
	if field == null or field == _field_node or not field.has_signal("stroke_event"):
		return
	_field_node = field
	field.connect("stroke_event", func(ev: Dictionary) -> void:
		_events.append({"kind": str(ev["kind"]), "actor": int(ev["actor"]), "seq": int(ev["seq"]), "moved": int(ev["moved"]),
			"ack": int(ev["ack_tick"]), "local": bool(ev["local"]), "bite": int(ev["bite"]), "tempo": float(ev["tempo"]),
			"frame": Engine.get_process_frames(), "msec": Time.get_ticks_msec()}))
	field.connect("field_reset", func(hard: bool) -> void: _resets.append(hard))
	field.connect("leaves_changed", func(_chunk: int) -> void: _changed_frames[Engine.get_process_frames()] = true)
	field.connect("bag_refused", func(_peer: int, reason: String) -> void: _refusals.append(reason))
	field.connect("bag_requested", func(_at: Vector3, _units: int) -> void: _bags_requested += 1)


# ---- host

func _run_host(lot: Node3D) -> void:
	var waited := 0.0
	while Net.peer_ids().size() < 2 and waited < CLIENT_WAIT_SECONDS:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	if Net.peer_ids().size() < 2:
		_finish_host("the Target client never joined")
		return
	await get_tree().create_timer(2.0).timeout
	var field := _field()
	var mate := _mate_id()
	# 1. The density rules are 0.4.5's.
	var golden := _Golden.run(self)
	_step("golden", bool(golden["ok"]), str(golden.get("why", "")))
	result["golden"] = {"hash": golden["hash"], "leaf_units": golden["leaf_units"], "cleaned": golden["cleaned"]}
	var spots := _pick_spots(field)
	if spots.is_empty():
		_finish_host("no room on this yard for the test's lanes")
		return
	# 2. The host's own stroke: one local event, the view told the same frame.
	var host_spot: Vector3 = spots["host"]
	await _stand(host_spot - Vector3.RIGHT * 1.5, Vector3.RIGHT)
	var before := _events.size()
	var frame := Engine.get_process_frames()
	var moved := int(field.call("request_rake", host_spot, Vector3.RIGHT, Constants.RAKE_WIDTH, Constants.RAKE_STRENGTH))
	await _ticks(2)
	var mine := _events.slice(before)
	_step("host_stroke", mine.size() == 1 and bool(mine[0]["local"]) and int(mine[0]["actor"]) == Net.local_peer_id() and int(mine[0]["moved"]) == moved \
		and moved > 0 and int(mine[0]["frame"]) == frame and _changed_frames.has(frame),
		"%d events, moved %d, local %s, leaves_changed the same frame %s" % [mine.size(), moved, mine[0]["local"] if not mine.is_empty() else "-", _changed_frames.has(frame)])
	# 3. A running mower is told at most 11 times a second.
	await _mow(field, spots["mow"] as Vector3)
	# 4. The client's half. A bare patch first (strokes there move nothing), and
	# the blower at tier 2 with a full tank.
	await get_tree().create_timer(0.8).timeout
	var bare: Vector3 = spots["bare"]
	field.call("_apply_collect", bare, 4.5, false)
	var blower := _prop("leaf_blower")
	var rake := _prop("rake")
	if blower == null or rake == null:
		_finish_host("no rake (%s) or leaf blower (%s) on the job" % [rake != null, blower != null])
		return
	blower.set("tier", BLOWER_TIER)
	blower.set("fuel", 100.0)
	# The host stands well away from everything the client does.
	await _stand(spots["host"] as Vector3 + Vector3(0.0, 0.0, 3.0), Vector3.RIGHT)
	await get_tree().create_timer(1.0).timeout
	var events_before := _events.size()
	var bags_before := _bags_requested
	_rpc_cue.rpc_id(mate, spots, rake.get_path(), blower.get_path())
	waited = 0.0
	while _report.is_empty() and waited < REPORT_WAIT_SECONDS:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	if _report.is_empty():
		_finish_host("the client never reported")
		return
	if not _report.has("sent"):
		_finish_host("the client stopped early: %s" % _report.get("steps", {}))
		return
	# 5. What the host saw of the client's strokes, against what the client did.
	var theirs := _events.slice(events_before).filter(func(ev: Dictionary) -> bool: return int(ev["actor"]) == mate)
	var counts := {}
	var empty := 0
	for ev: Dictionary in theirs:
		counts[ev["kind"]] = int(counts.get(ev["kind"], 0)) + 1
		if str(ev["kind"]) == "rake" and int(ev["moved"]) == 0:
			empty += 1
	var sent: Dictionary = _report["sent"]
	var rakes_in_reach := int(sent["rake"])
	_step("host_events", int(counts.get("rake", 0)) == rakes_in_reach and int(counts.get("blower", 0)) == int(sent["blower"]) \
		and int(counts.get("bag", 0)) == int(sent["bag_ok"]) and empty >= BARE_STROKES and not counts.has("hand"),
		"host saw %s from the client (it sent %s), %d empty rakes" % [counts, sent, empty])
	_step("host_bag", _bags_requested - bags_before == int(sent["bag_ok"]) and int(sent["bag_ok"]) == 1, "bag_requested %d" % (_bags_requested - bags_before))
	# 6. Same bytes, same scoring, as the client's reference replay.
	await get_tree().create_timer(0.5).timeout
	var host_values := _values(field, _report["checkpoints"] as Array)
	_step("same_bytes", str(field.call("density_hash")) == str(_report["hash"]) and str(_report["hash"]) == str(_report["reference_hash"]),
		"host %s, client %s, reference %s" % [str(field.call("density_hash")).left(12), str(_report["hash"]).left(12), str(_report["reference_hash"]).left(12)])
	_step("same_scores", _same_values(host_values, _report["values"] as Dictionary) and _same_values(host_values, _report["reference_values"] as Dictionary),
		"host %s, client %s, reference %s" % [host_values, _report["values"], _report["reference_values"]])
	result["client"] = _report
	_finish_host("")


func _mow(field: Node, line: Vector3) -> void:
	var mower := _prop("lawn_mower")
	if mower == null:
		_step("mulch_rate", false, "no mower on the job")
		return
	await _stand(line - Vector3.RIGHT * 1.0, Vector3.RIGHT)
	mower.global_position = _me().global_position + Vector3(0.0, 0.3, -0.8)
	mower.set("linear_velocity", Vector3.ZERO)
	await _ticks(2)
	mower.call("request_grab")
	await _ticks(3)
	for _pull: int in 20:
		if bool(mower.get("spraying")):
			break
		mower.call("request_start")
		await _ticks(2)
	var units_before := float(field.call("leaf_units"))
	var start := Time.get_ticks_msec()
	var first := _events.size()
	var me := _me()
	me.set("body_yaw", atan2(-1.0, 0.0))
	me.rotation.y = float(me.get("body_yaw"))
	var step := 0
	while Time.get_ticks_msec() - start < int(MOW_SECONDS * 1000.0):
		me.call("apply_network_teleport", Transform3D(me.global_basis, line + Vector3.RIGHT * (float(step) * 0.07)))
		step += 1
		await get_tree().physics_frame
	# Switch it off before letting go, or it drives off on its own.
	for _pull: int in 6:
		if not bool(mower.get("spraying")):
			break
		mower.call("request_start")
		await _ticks(2)
	mower.call("request_drop")
	await get_tree().create_timer(0.3).timeout
	var times: Array[int] = []
	for ev: Dictionary in _events.slice(first):
		if str(ev["kind"]) == "mulch":
			times.append(int(ev["msec"]))
	var peak := 0
	for index: int in times.size():
		var count := 0
		for other: int in range(index, times.size()):
			if times[other] - times[index] < 1000:
				count += 1
		peak = maxi(peak, count)
	var mulched := units_before - float(field.call("leaf_units"))
	result["mulch_events"] = times.size()
	_step("mulch_rate", times.size() >= 5 and peak <= MULCH_PER_SECOND_MAX and mulched > 0.0,
		"%d mulch events in %.1f s, at most %d in a second, %.1f units mulched" % [times.size(), MOW_SECONDS, peak, mulched])


## The client's report (its last step): what it sent, its checks, its bytes.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_report(report: Dictionary) -> void:
	if Net.is_host():
		_report = report


func _finish_host(why: String) -> void:
	if why != "":
		_steps["setup"] = false
		print("[RakeNetTest] %s" % why)
	var ok := not _steps.is_empty()
	for step: String in _steps:
		ok = ok and bool(_steps[step])
	if not _report.is_empty():
		ok = ok and bool(_report.get("ok", false))
	result["steps"] = _steps.duplicate()
	result["ledger"] = _field().call("ledger_stats") if _field() != null else {}
	_save_log("host")
	result["ok"] = ok
	result["done"] = true
	print("[RakeNetTest] all ok: %s" % ok)


# ---- client

@rpc("authority", "call_remote", "reliable")
func _rpc_cue(spots: Dictionary, rake_path: NodePath, blower_path: NodePath) -> void:
	_cue = {"spots": spots, "rake": rake_path, "blower": blower_path}


func _run_client() -> void:
	var waited := 0.0
	while _cue.is_empty() and waited < 50.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	if _cue.is_empty():
		_finish_client("the host never cued")
		return
	var field := _field()
	var me := Net.local_peer_id()
	var spots: Dictionary = _cue["spots"]
	var stats: Dictionary = field.call("ledger_stats")
	# The join's snapshot snapped the field in.
	_step("join_hard_reset", int(stats["snapshot_hard"]) >= 1 and int(stats["snapshots_in"]) >= 1, "snapshots %d, hard %d" % [int(stats["snapshots_in"]), int(stats["snapshot_hard"])])
	# Other peers' strokes arrive as news: the host's one stroke (bare hands: the
	# host never holds the rake here) and its mulch.
	var host_rakes := _events.filter(func(ev: Dictionary) -> bool: return int(ev["actor"]) == 1 and ["rake", "hand"].has(str(ev["kind"])))
	var mulch := _events.filter(func(ev: Dictionary) -> bool: return str(ev["kind"]) == "mulch")
	_step("others_events", host_rakes.size() == 1 and not bool(host_rakes[0]["local"]) and mulch.size() >= 5,
		"%d host rakes, %d mulch events" % [host_rakes.size(), mulch.size()])
	# Pick up the rake.
	var rake := get_node_or_null(_cue["rake"] as NodePath) as Node3D
	var blower := get_node_or_null(_cue["blower"] as NodePath) as Node3D
	if rake == null or blower == null:
		_finish_client("no rake or blower here")
		return
	if not await _grab(rake):
		_finish_client("could not pick up the rake")
		return
	await _settle(field)
	_start_tracking(field)
	var sent := {"rake": 0, "blower": 0, "bag_ok": 0, "out_of_reach": 0}
	var own_before := _own_events(true).size()
	# Lane toward +X, then -Z.
	var lane_x: Vector3 = spots["lane_x"]
	await _stand(lane_x - Vector3.RIGHT * 1.5, Vector3.RIGHT)
	await get_tree().create_timer(0.8).timeout
	var first_frame := -1
	for index: int in LANE_X_STROKES:
		var at := lane_x + Vector3.RIGHT * (LANE_STEP * float(index))
		await _stand(at - Vector3.RIGHT * 1.5, Vector3.RIGHT)
		if index == 0:
			first_frame = Engine.get_process_frames()
		_rake(field, at, Vector3.RIGHT, index % 2)
		sent["rake"] = int(sent["rake"]) + 1
		await get_tree().create_timer(STROKE_SECONDS).timeout
	_step("leaves_changed_same_frame", _changed_frames.has(first_frame), "a predicted stroke in frame %d" % first_frame)
	var lane_z: Vector3 = spots["lane_z"]
	await _stand(lane_z - Vector3.FORWARD * 1.5, Vector3.FORWARD)
	await get_tree().create_timer(0.8).timeout
	var last_request := 0
	for index: int in LANE_Z_STROKES:
		var at := lane_z + Vector3.FORWARD * (LANE_STEP * float(index))
		await _stand(at - Vector3.FORWARD * 1.5, Vector3.FORWARD)
		_rake(field, at, Vector3.FORWARD, index % 2)
		sent["rake"] = int(sent["rake"]) + 1
		last_request = Time.get_ticks_msec()
		if index < LANE_Z_STROKES - 1:
			await get_tree().create_timer(STROKE_SECONDS).timeout
	var emptied := -1.0
	while Time.get_ticks_msec() - last_request < 3000:
		if int(field.call("pending_count")) == 0:
			emptied = float(Time.get_ticks_msec() - last_request) / 1000.0
			break
		await get_tree().process_frame
	# The field's own peak counts the instant inside a frame that the per-frame sample misses.
	_ledger_peak = maxi(_ledger_peak, int((field.call("ledger_stats") as Dictionary)["pending_peak"]))
	_step("ledger", _ledger_peak <= LEDGER_MAX and emptied >= 0.0 and emptied <= LEDGER_EMPTY_SECONDS,
		"peak %d, empty %.2f s after the last stroke" % [_ledger_peak, emptied])
	await get_tree().create_timer(0.6).timeout
	_step("no_snap_back", _reversals == 0 and _corrections == 0, "%d reversals, %d corrections over %d strokes" % [_reversals, _corrections, int(sent["rake"])])
	# Empty strokes on the bare patch still make events.
	var bare: Vector3 = spots["bare"]
	await _stand(bare - Vector3.RIGHT * 1.5, Vector3.RIGHT)
	await get_tree().create_timer(0.8).timeout
	var empty_before := _own_events(true).filter(func(ev: Dictionary) -> bool: return int(ev["moved"]) == 0).size()
	var empty_moved := 0
	for index: int in BARE_STROKES:
		empty_moved += _rake(field, bare + Vector3.RIGHT * (LANE_STEP * float(index)), Vector3.RIGHT, 0)
		sent["rake"] = int(sent["rake"]) + 1
		await get_tree().create_timer(STROKE_SECONDS).timeout
	var empty_events := _own_events(true).filter(func(ev: Dictionary) -> bool: return int(ev["moved"]) == 0).size() - empty_before
	_step("empty_strokes", empty_moved == 0 and empty_events == BARE_STROKES, "moved %d, %d empty events" % [empty_moved, empty_events])
	# Out of reach: no prediction, no event, a soft resync.
	var soft_before := _resets.count(false)
	var events_before := _events.size()
	var far: Vector3 = spots["far"]
	var oor := int(field.call("request_rake", far, Vector3.RIGHT, Constants.RAKE_WIDTH, Constants.RAKE_STRENGTH))
	sent["out_of_reach"] = 1
	_stop_tracking()
	waited = 0.0
	while _resets.count(false) == soft_before and waited < 3.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	await get_tree().create_timer(0.3).timeout
	_step("out_of_reach", oor == 0 and _resets.count(false) == soft_before + 1 and _events.size() == events_before,
		"moved %d, soft resets +%d, events +%d" % [oor, _resets.count(false) - soft_before, _events.size() - events_before])
	# The blower at tier 2: predicted with the host's numbers, so no correction.
	rake.call("request_drop")
	await _wait_for(func() -> bool: return int(rake.get("held_by")) == 0, 3.0)
	if not await _grab(blower):
		_finish_client("could not pick up the blower")
		return
	await _wait_for(func() -> bool: return int(blower.get("tier")) == BLOWER_TIER and float(blower.get("fuel")) > 50.0, 3.0)
	var puff_at: Vector3 = spots["blower"]
	await _stand(puff_at - Vector3.RIGHT * 1.5, Vector3.RIGHT)
	await get_tree().create_timer(0.8).timeout
	await _settle(field)
	_start_tracking(field)
	var blower_events := _own_events(true).size()
	for index: int in BLOWER_PUFFS:
		_rake(field, puff_at, Vector3.RIGHT, 0, Constants.BLOWER_WIDTH, Constants.BLOWER_STRENGTH)
		sent["blower"] = int(sent["blower"]) + 1
		await get_tree().create_timer(Constants.BLOWER_PUFF_SECONDS).timeout
	var blown := _own_events(true).slice(blower_events)
	await _settle(field)
	_track()
	_step("blower_no_corrections", _corrections == 0 and _reversals == 0 and blown.size() == BLOWER_PUFFS and blown.all(func(ev: Dictionary) -> bool: return str(ev["kind"]) == "blower"),
		"%d puffs told as %s, %d corrections" % [blown.size(), blown.map(func(ev: Dictionary) -> String: return str(ev["kind"])).slice(0, 2), _corrections])
	_stop_tracking()
	blower.call("request_drop")
	await _wait_for(func() -> bool: return int(blower.get("held_by")) == 0, 3.0)
	# A bag of the lane's pile: predicted, told as a bag.
	var pile := _pile_spot(field, lane_x)
	await _stand(pile - Vector3.RIGHT * 1.5, Vector3.RIGHT)
	await get_tree().create_timer(0.8).timeout
	await _settle(field)
	var bags_before := _own_events(true).filter(func(ev: Dictionary) -> bool: return str(ev["kind"]) == "bag").size()
	var bagged := int(field.call("request_collect", pile, Constants.BAG_RADIUS))
	_reference_collect(field, pile, Constants.BAG_RADIUS)
	sent["bag_ok"] = 1 if bagged > 0 else 0
	await _settle(field)
	var bag_events := _own_events(true).filter(func(ev: Dictionary) -> bool: return str(ev["kind"]) == "bag").size() - bags_before
	_step("bag", bagged > 0 and bag_events == 1, "bagged %d, %d bag events" % [bagged, bag_events])
	# A bag of the bare patch: thin, refused, resynced softly, no event.
	soft_before = _resets.count(false)
	events_before = _events.size()
	await _stand(bare - Vector3.RIGHT * 1.5, Vector3.RIGHT)
	await get_tree().create_timer(0.8).timeout
	var thin := int(field.call("request_collect", bare, Constants.BAG_RADIUS))
	await _wait_for(func() -> bool: return not _refusals.is_empty() and _resets.count(false) > soft_before, 3.0)
	await get_tree().create_timer(0.3).timeout
	_step("thin_bag", thin == 0 and _refusals.has("thin") and _resets.count(false) == soft_before + 1 and _events.size() == events_before,
		"refused %s, soft resets +%d, events +%d" % [_refusals, _resets.count(false) - soft_before, _events.size() - events_before])
	# Every stroke this peer made was told here once, as its own; no echo came back as news.
	var own_local := _own_events(true).size() - own_before
	var own_echoes := _own_events(false).size()
	var told := int(sent["rake"]) + int(sent["blower"]) + int(sent["bag_ok"])
	_step("exactly_once", own_local == told and own_echoes == 0, "%d strokes, %d told locally, %d echoes re-told" % [told, own_local, own_echoes])
	# The end: same bytes as the host, and as the reference replay.
	await _settle(field)
	var checkpoints := [lane_x, lane_x + Vector3.RIGHT * 6.0, pile, lane_z, lane_z + Vector3.FORWARD * 4.0, bare, puff_at + Vector3.RIGHT * 3.0]
	_report = {
		"sent": sent,
		"hash": str(field.call("density_hash")),
		"reference_hash": str(_reference.call("density_hash")) if _reference != null else "",
		"checkpoints": checkpoints,
		"values": _values(field, checkpoints),
		"reference_values": _values(_reference, checkpoints) if _reference != null else {},
		"ledger": field.call("ledger_stats"),
		"reversals": _reversals,
		"corrections": _corrections,
		"ledger_peak": _ledger_peak,
	}
	_finish_client("")


## One stroke the way the rake does it, and the same stroke on the reference copy.
func _rake(field: Node, at: Vector3, dir: Vector3, bite: int, width: float = Constants.RAKE_WIDTH, strength: float = Constants.RAKE_STRENGTH) -> int:
	_track()
	var me := Net.local_peer_id()
	var in_reach := bool(field.call("_player_in_reach", me, at))
	var params: Dictionary = field.call("_stroke_params", me, width, strength)
	var moved := int(field.call("request_rake", at, dir, width, strength, bite, TEMPO))
	if in_reach and _reference != null:
		_reference.call("_stroke_cells", at, dir, float(params["width"]), float(params["strength"]), int(params["cells"]))
	_expect(field)
	return moved


func _reference_collect(field: Node, at: Vector3, radius: float) -> void:
	if _reference == null:
		return
	var supply := str(field.call("bag_type"))
	var scoop: float = field.call("bag_radius", supply, minf(radius, Constants.BAG_RADIUS))
	if int(_reference.call("units_within_world", at, scoop)) >= int(Constants.MIN_BAG_CELLS * float(field.get("INITIAL_DENSITY"))):
		_reference.call("_apply_collect", at, scoop, false)


## From here on, the client's field must only change by its own strokes. The
## first call also copies the field into the reference, which then only ever
## changes by the same strokes replayed on it (nothing else touches the yard
## while the client works).
func _start_tracking(field: Node) -> void:
	if _reference == null:
		_reference = _FieldScript.new() as Node3D
		_reference.set("scratch", true)
		_reference.name = "Reference"
		add_child(_reference)
		_reference.set_process(false)
		_reference.global_transform = (field as Node3D).global_transform
		_reference.set("_density", (field.get("_density") as PackedByteArray).duplicate())
		_reference.set("_clean_at_start", int(field.get("_clean_at_start")))
	_expected = (field.get("_density") as PackedByteArray).duplicate()
	_raised = PackedByteArray()
	_raised.resize(_expected.size())
	_tracking = true


func _stop_tracking() -> void:
	_track()
	_tracking = false


func _expect(field: Node) -> void:
	var now: PackedByteArray = field.get("_density")
	if _tracking and now != _expected:
		for index: int in now.size():
			if now[index] > _expected[index]:
				_raised[index] = 1
	_expected = now.duplicate()


## Anything the field shows that this peer's own strokes didn't leave there.
func _track() -> void:
	var field := _field()
	if not _tracking or field == null:
		return
	var now: PackedByteArray = field.get("_density")
	if now == _expected:
		return
	var width := int(field.get("grid_width"))
	for index: int in now.size():
		if now[index] == _expected[index]:
			continue
		_corrections += 1
		var fell := now[index] < _expected[index] and _raised[index] == 1
		if fell:
			_reversals += 1
		if _trace.size() < 400:
			_trace.append({"msec": Time.get_ticks_msec(), "cell": [index % width, index / width], "expected": _expected[index], "got": now[index], "reversal": fell,
				"pending": int(field.call("pending_count"))})
	_expected = now.duplicate()


## Waits for this peer's ledger to empty and the field to stop changing.
func _settle(field: Node) -> void:
	await _wait_for(func() -> bool: return int(field.call("pending_count")) == 0, 3.0)
	await get_tree().create_timer(0.5).timeout


func _finish_client(why: String) -> void:
	if why != "":
		_steps["setup"] = false
		print("[RakeNetTest] %s" % why)
	var ok := not _steps.is_empty()
	for step: String in _steps:
		ok = ok and bool(_steps[step])
	result["steps"] = _steps.duplicate()
	result["reversals"] = _reversals
	result["corrections"] = _corrections
	result["ledger_peak"] = _ledger_peak
	result["ledger"] = _field().call("ledger_stats") if _field() != null else {}
	_save_log("client")
	result["ok"] = ok
	result["done"] = true
	_report["ok"] = ok
	_report["steps"] = _steps.duplicate()
	_rpc_report.rpc_id(1, _report)
	print("[RakeNetTest] all ok: %s" % ok)


# ---- shared

## Where the lanes, the bare patch, the mower's line and the blower go: open
## leafy ground, not overlapping (field-local rectangles, world spots back).
func _pick_spots(field: Node) -> Dictionary:
	var used: Array[Rect2] = []
	var spots := {}
	# name: [rect offset from the spot, size]
	var wanted := [
		["lane_x", Vector2(-2.0, -2.0), Vector2(12.5, 4.0)],
		["lane_z", Vector2(-2.0, -8.0), Vector2(4.0, 10.5)],
		["mow", Vector2(-1.5, -1.2), Vector2(14.5, 2.4)],
		["blower", Vector2(-2.0, -2.0), Vector2(9.0, 4.0)],
		["host", Vector2(-2.0, -1.5), Vector2(6.0, 5.5)],
		["bare", Vector2(-5.0, -5.0), Vector2(10.0, 10.0)],
	]
	for want: Array in wanted:
		var offset: Vector2 = want[1]
		var size: Vector2 = want[2]
		var found := false
		for z: int in range(-17, 18):
			for x: int in range(-17, 18):
				var rect := Rect2(Vector2(x, z) + offset, size)
				if rect.position.x < -19.0 or rect.position.y < -19.0 or rect.end.x > 19.0 or rect.end.y > 19.0:
					continue
				if used.any(func(other: Rect2) -> bool: return other.grow(0.5).intersects(rect)):
					continue
				if str(want[0]) != "bare" and not _leafy(field, rect):
					continue
				used.append(rect)
				spots[want[0]] = (field as Node3D).to_global(Vector3(float(x), 0.25, float(z)))
				found = true
				break
			if found:
				break
		if not found:
			print("[RakeNetTest] no room for %s" % want[0])
			return {}
	# Out of reach of the bare patch's stroke spot, still on the grid.
	var bare_local := (field as Node3D).to_local(spots["bare"] as Vector3)
	var far_z := bare_local.z + 8.0 if bare_local.z < 8.0 else bare_local.z - 8.0
	spots["far"] = (field as Node3D).to_global(Vector3(bare_local.x, 0.25, far_z))
	return spots


## At least 95% of the rectangle has leaves (no house, no path, nothing heaped).
func _leafy(field: Node, rect: Rect2) -> bool:
	var total := 0
	var leafy := 0
	var x := rect.position.x + 0.25
	while x < rect.end.x:
		var z := rect.position.y + 0.25
		while z < rect.end.y:
			var density := int(field.call("sample_world", (field as Node3D).to_global(Vector3(x, 0.25, z))))
			total += 1
			if density > int(field.call("clean_density")) and density < 200:
				leafy += 1
			z += 0.5
		x += 0.5
	return total > 0 and float(leafy) >= 0.95 * float(total)


## The thickest spot ahead of the +X lane (its pile).
func _pile_spot(field: Node, lane_x: Vector3) -> Vector3:
	var best := lane_x + Vector3.RIGHT * 8.5
	var most := -1
	for step: int in 16:
		var at := lane_x + Vector3.RIGHT * (5.0 + 0.5 * float(step))
		var units := int(field.call("units_within_world", at, Constants.BAG_RADIUS))
		if units > most:
			most = units
			best = at
	return best


func _values(field: Node, checkpoints: Array) -> Dictionary:
	if field == null:
		return {}
	var within: Array[int] = []
	for at: Variant in checkpoints:
		within.append(int(field.call("units_within_world", at as Vector3, Constants.BAG_RADIUS)))
	return {"leaf_units": snappedf(float(field.call("leaf_units")), 0.0001), "cleaned": snappedf(float(field.call("cleaned_fraction")), 0.000001), "within": within}


func _same_values(a: Dictionary, b: Dictionary) -> bool:
	return absf(float(a.get("leaf_units", -1.0)) - float(b.get("leaf_units", -2.0))) < 0.001 \
		and absf(float(a.get("cleaned", -1.0)) - float(b.get("cleaned", -2.0))) < 0.00001 \
		and str(a.get("within", [])) == str(b.get("within", []))


func _own_events(local: bool) -> Array[Dictionary]:
	var me := Net.local_peer_id()
	return _events.filter(func(ev: Dictionary) -> bool: return int(ev["actor"]) == me and bool(ev["local"]) == local)


func _grab(prop: Node3D) -> bool:
	await _stand(prop.global_position + Vector3(0.0, 0.0, 1.0), Vector3.FORWARD)
	await get_tree().create_timer(0.8).timeout
	for _try: int in 4:
		prop.call("request_grab")
		if await _wait_for(func() -> bool: return int(prop.get("held_by")) == Net.local_peer_id(), 1.5):
			return true
		await _stand(prop.global_position + Vector3(0.0, 0.0, 1.0), Vector3.FORWARD)
		await get_tree().create_timer(0.5).timeout
	return false


func _wait_for(ready: Callable, seconds: float) -> bool:
	var waited := 0.0
	while not bool(ready.call()) and waited < seconds:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	return bool(ready.call())


func _stand(at: Vector3, face: Vector3) -> void:
	var me := _me()
	if me == null:
		return
	me.global_position = Vector3(at.x, at.y - 0.15, at.z)
	if me is CharacterBody3D:
		(me as CharacterBody3D).velocity = Vector3.ZERO
	me.set("body_yaw", atan2(-face.x, -face.z))
	me.rotation.y = float(me.get("body_yaw"))
	await get_tree().physics_frame


func _save_log(role: String) -> void:
	var dir := ProjectSettings.globalize_path("res://build/r1/net")
	DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open("%s/%s_%d.json" % [dir, role, int(Net.dev_options().get("port"))], FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"steps": _steps, "events": _events, "resets": _resets, "trace": _trace,
		"ledger": _field().call("ledger_stats") if _field() != null else {}}, "  "))
	file.close()


func _step(step: String, ok: bool, detail: String = "") -> void:
	_steps[step] = ok
	print("[RakeNetTest] %s: %s%s" % [step, ok, "" if detail == "" else " (%s)" % detail])


func _ticks(count: int) -> void:
	for _tick: int in count:
		await get_tree().physics_frame


func _field() -> Node3D:
	return get_tree().get_first_node_in_group("leaf_field") as Node3D


func _me() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as Node3D
	return null


func _mate_id() -> int:
	for peer_id: int in Net.peer_ids():
		if peer_id != Net.local_peer_id():
			return peer_id
	return -1


func _prop(kind: String) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) == kind and not node.is_queued_for_deletion():
			return node as Node3D
	return null
