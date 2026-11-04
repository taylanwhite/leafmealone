extends Node

## Authority: host and client. --rake-stroke-test checks the rake swing (raking
## chunk 4; equipment/rake_stroke.gd, props/rake_motion.gd; docs/GAME.md "Raking:
## the push-sweep"). Run with --start-zone=lot --job-seed=777 --yard-size=1
## --rank=22 on both peers (a joined client named Target).
##
## Host: holding the button 3 s makes 10 field strokes at the swing's bite times
## (0.12, 0.30, 0.72, 0.90 s ...); a tap makes one; letting go mid-swing finishes
## it; dropping the rake before the plant cancels it, and dropping it mid-drive
## leaves no lowered head behind in "rake_heads". All through the hold the
## tines ride the ground (within 0.03 m at the bites and through the drive), the
## head never jumps more than 0.15 m a tick, stays ahead (0.8-2.3 m), within 0.25 m
## of center and 15 degrees of straight; both hands are on the handle
## RAKE_HAND_SPAN_MIN-RAKE_HAND_SPAN apart and within reach, and the body really
## works (rakefeel:look): the feet plant in the stance, the knees bend, and the
## lunge carries the head at least MIN_TRAVEL each swing. A hired hand swings its own rake at its own pace, its
## strokes at its bite and as actor RAKE_ACTOR_HAND_BASE + N, gliding (at most
## 0.03 m a tick) instead of jumping.
## Client: the host's rake really swings (the frozen-rake regression): it travels
## forward each swing, the swing starts on the stroke and stops after the last
## one, the host's body leans into the drive, and the head plants where the owner's
## does. It knows the host's wallet from joining, and draws the host's rake with
## the Tune-Up head once the host buys it. Each step prints a [RakeStrokeTest] line.

static var result: Dictionary = {}

const _PropLooks = preload("res://props/prop_looks.gd")
const _YardModels = preload("res://props/yard_models.gd")
## The client's look at the host's swing: this many swings, then this long idle.
const SWINGS_TO_WATCH: int = 4
## The head's forward travel each swing must be at least this (m): the lunge
## carries it RAKE_HEAD_NEAR to RAKE_HEAD_FAR (1.25 m; rakefeel:look), so this
## catches a frozen or twitching rake, and a drag cut back to R1's 0.7 m.
const MIN_TRAVEL: float = 1.1
## The host creeps forward this much a tick while it holds the button (0.48 m/s).
const WALK_PER_TICK: float = 0.008

var _started: bool = false
## Host: bites heard this step, as [tick, bite].
var _bites: Array = []
## Per-tick samples while recording.
var _recording: bool = false
var _samples: Array = []
var _watch: Callable
## Host: the client is in the yard and watching.
var _client_ready: bool = false


## Host: the client has finished its half.
var _client_done: bool = false


## Client -> host: watching now.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_watching() -> void:
	if Net.is_host():
		_client_ready = true


## Client -> host: finished.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_finished() -> void:
	if Net.is_host():
		_client_done = true


func _ready() -> void:
	# After every pose (props pose at 110), so a sample sees this tick's rake.
	process_physics_priority = 200


func _process(_delta: float) -> void:
	if _started or _own_player() == null or get_tree().get_first_node_in_group("leaf_field") == null:
		return
	if Net.is_host() and get_tree().get_first_node_in_group("job_tasks") == null:
		return
	_started = true
	if Net.is_host():
		_run_host()
	else:
		_run_client()


func _physics_process(_delta: float) -> void:
	if _recording and _watch.is_valid():
		_samples.append(_watch.call())


# ---- host


func _run_host() -> void:
	var waited := 0.0
	# The client says when it's watching (it has the yard and sees this player).
	while not _client_ready and waited < 25.0:
		await _seconds(0.25)
		waited += 0.25
	print("[RakeStrokeTest] client watching: %s (after %.1f s)" % [_client_ready, waited])
	await _seconds(1.0)
	if _capture_dir() != "":
		await _capture_host()
		return
	var ok := true
	var report := {}
	var field := get_tree().get_first_node_in_group("leaf_field")
	var lot := get_tree().get_first_node_in_group("job_lot") as Node3D
	var me := _own_player()
	var rake := _prop("rake")
	var rake_node := me.get_node("Rake")
	rake_node.connect("stroke_bite", func(bite: int, _moved: int) -> void: _bites.append([Engine.get_physics_frames(), bite]))
	# Fresh leaves, facing along +X, room ahead.
	var spot := _leafy_spot(field, lot)
	_move_to(spot, -PI * 0.5)
	await _grab(rake)
	await _seconds(0.6)
	# 1. Hold 2.95 s: 5 swings, 10 strokes, on the bite times.
	_bites.clear()
	_samples.clear()
	_watch = _host_sample.bind(me, rake)
	await get_tree().physics_frame
	var start := Engine.get_physics_frames()
	Input.action_press(&"primary")
	_recording = true
	# Walking slowly behind the rake, the way people rake, so every stroke has leaves.
	var ahead := -me.global_basis.z
	ahead = Vector3(ahead.x, 0.0, ahead.z).normalized()
	for _tick: int in 177:
		await get_tree().physics_frame
		me.global_position += ahead * WALK_PER_TICK
	Input.action_release(&"primary")
	await _ticks(36)
	_recording = false
	var expected: Array = []
	var cycle := RakeStroke.cycle_seconds(me.name.to_int())
	for swing: int in 5:
		for bite_at: float in Constants.RAKE_SWING_BITES:
			expected.append((float(swing) + bite_at) * cycle)
	var times: Array = []
	var timing_ok := _bites.size() >= 9 and _bites.size() <= 11
	for index: int in _bites.size():
		var at := float(int(_bites[index][0]) - start) / 60.0
		times.append(snappedf(at, 0.001))
		if index < expected.size() and absf(at - float(expected[index])) > 1.0 / 60.0 + 0.0005:
			timing_ok = false
	var first_ok := not times.is_empty() and float(times[0]) <= 0.12 + 0.0005
	print("[RakeStrokeTest] held 2.95 s: %d strokes at %s s (expected %s), first after %s s: %s" % [_bites.size(), times, expected.map(func(t: float) -> float: return snappedf(t, 0.001)), times[0] if not times.is_empty() else "never", timing_ok and first_ok])
	ok = ok and timing_ok and first_ok
	report["hold_strokes"] = _bites.size()
	# 2. The head through the hold.
	var head := _judge_head(me)
	print("[RakeStrokeTest] head through the hold: biggest step %.3f m/tick, worst tine height off the leaves %.3f m (drive and bites), ahead %.2f-%.2f m, sideways %.2f m, turned %.1f deg: %s" % [head["step"], head["off_ground"], head["near"], head["far"], head["lateral"], rad_to_deg(head["yaw"]), head["ok"]])
	ok = ok and bool(head["ok"])
	report["head"] = head
	var grips := _judge_grips()
	print("[RakeStrokeTest] hands on the handle: %.2f-%.2f m apart, farthest from a shoulder %.2f m (reach %.2f): %s" % [grips["gap_min"], grips["gap_max"], grips["reach"], Constants.HOLD_GRIP_REACH, grips["ok"]])
	ok = ok and bool(grips["ok"])
	report["grips"] = grips
	var legs := _judge_legs()
	print("[RakeStrokeTest] the body works: feet in the stance %.2f of the way, knees bent up to %.0f deg in the drive, lean %.2f rad; creeping, a planted foot slid at most %.4f m/tick (limit %.3f, body %.3f), steps %s: %s" % [legs["stance"], rad_to_deg(legs["knee"]), legs["lean"], legs["slide"], FOOT_SLIDE_MAX, WALK_PER_TICK, legs["steps"], legs["ok"]])
	ok = ok and bool(legs["ok"])
	report["legs"] = legs
	# 3. A tap: one swing, one stroke.
	await _seconds(0.6)
	_bites.clear()
	await get_tree().physics_frame
	Input.action_press(&"primary")
	await get_tree().physics_frame
	Input.action_release(&"primary")
	await _seconds(0.9)
	var tap_ok := _bites.size() == 1 and int(_bites[0][1]) == 0
	print("[RakeStrokeTest] a tap: %d stroke(s): %s" % [_bites.size(), tap_ok])
	ok = ok and tap_ok
	# 4. Let go mid-swing: the swing finishes (phase reaches the end, then -1).
	await _seconds(0.4)
	_bites.clear()
	var phases: Array = []
	_watch = func() -> float: return float(rake_node.call("stroke_phase"))
	_samples.clear()
	_recording = true
	await get_tree().physics_frame
	Input.action_press(&"primary")
	await _ticks(12)
	Input.action_release(&"primary")
	await _seconds(0.8)
	_recording = false
	phases = _samples.duplicate()
	var top := -1.0
	var ended := false
	for phase: float in phases:
		if phase >= 0.0 and not ended:
			top = maxf(top, phase)
		elif top >= 0.0 and phase < 0.0:
			ended = true
	var release_ok := top >= 0.95 and ended and _bites.size() == 1
	print("[RakeStrokeTest] let go at 0.2 s: the swing ran to %.2f, then stopped %s, %d stroke(s): %s" % [top, ended, _bites.size(), release_ok])
	ok = ok and release_ok
	# 4b. Drop the rake mid-drive: its head stops counting for the leaves (contract
	# C4: no node in rake_heads for this actor still says down mid-swing).
	await _seconds(0.4)
	await get_tree().physics_frame
	Input.action_press(&"primary")
	await _ticks(20)
	var lowered_before := _lowered_heads(me.name.to_int())
	rake.call("request_drop")
	await _ticks(6)
	Input.action_release(&"primary")
	var lowered_after := _lowered_heads(me.name.to_int())
	var stale_ok := lowered_before > 0 and lowered_after == 0
	print("[RakeStrokeTest] dropped the rake mid-drive: %d lowered head(s) before, %d after: %s" % [lowered_before, lowered_after, stale_ok])
	ok = ok and stale_ok
	report["stale_heads"] = lowered_after
	await _seconds(0.8)
	await _grab(rake)
	await _seconds(0.6)
	# 5. Put the rake down before the tines plant: no stroke.
	await _seconds(0.3)
	_bites.clear()
	await get_tree().physics_frame
	Input.action_press(&"primary")
	await _ticks(2)
	rake.call("request_drop")
	await _ticks(20)
	Input.action_release(&"primary")
	var cancel_ok := _bites.is_empty()
	print("[RakeStrokeTest] dropped the rake before the plant: %d stroke(s): %s" % [_bites.size(), cancel_ok])
	ok = ok and cancel_ok
	# The host's rake becomes a Mk II (p2-kit: the tier is the rake's own, replicated
	# on the prop): the client must draw it with the Mk II's orange head.
	if _prop("rake") != null:
		_prop("rake").set("tier", Catalog.TIER_MK2)
	# 6. A hired hand: its own swing, pace, actor and glide.
	var hand_ok: bool = await _hand_check(me, lot, report)
	ok = ok and hand_ok
	# Stay up until the client has judged what it saw (it quits when the host does).
	waited = 0.0
	while not _client_done and waited < 20.0:
		await _seconds(0.25)
		waited += 0.25
	result = {"ok": ok, "done": true, "report": report}
	print("[RakeStrokeTest] all ok: %s" % ok)


func _host_sample(me: Node3D, rake: Node3D) -> Dictionary:
	var pose := rake.get_node_or_null("Visual/Look/Pose") as Node3D
	var tines := pose.get_node_or_null("Rake/Tines") as Node3D if pose != null else null
	var body := me.get_node_or_null("Visual/CartoonBody")
	var out := {"tick": Engine.get_physics_frames(), "phase": RakeStroke.phase_of(me.name.to_int()), "me": me.global_position, "forward": -me.global_basis.z}
	if pose == null or not pose.has_meta("head_at"):
		return out
	out["at"] = pose.get_meta("head_at")
	out["dir"] = pose.get_meta("drive_dir")
	out["down"] = pose.get_meta("down")
	out["tip"] = tines.global_transform * _YardModels.RAKE_TINE_TIP if tines != null else Vector3.INF
	out["ground"] = RakeMotion.surface_y(pose, out["at"] as Vector3, me.global_position.y)
	var grips := RakeMotion.grips_of(pose)
	out["grips"] = grips
	if body != null:
		out["shoulders"] = [body.call("shoulder_position", 0), body.call("shoulder_position", 1)]
		out["work"] = body.call("work_pose")
		if body.has_method("stance"):
			out["stance"] = float(body.call("stance"))
			out["knee"] = maxf(float(body.call("knee_bend", 0)), float(body.call("knee_bend", 1)))
		if body.has_method("foot_planted"):
			out["feet"] = [body.call("foot_position", 0), body.call("foot_position", 1)]
			out["planted"] = [body.call("foot_planted", 0), body.call("foot_planted", 1)]
	return out


func _judge_head(me: Node3D) -> Dictionary:
	var step := 0.0
	var off := 0.0
	var near := INF
	var far := -INF
	var lateral := 0.0
	var yaw := 0.0
	var last := Vector3.INF
	var bite_ticks := {}
	for entry: Array in _bites:
		bite_ticks[int(entry[0])] = true
	for sample: Dictionary in _samples:
		if not sample.has("at"):
			continue
		var at: Vector3 = sample["at"]
		if last != Vector3.INF:
			step = maxf(step, at.distance_to(last))
		last = at
		var forward: Vector3 = sample["forward"]
		forward = Vector3(forward.x, 0.0, forward.z).normalized()
		var right := forward.cross(Vector3.UP)
		var rel := at - (sample["me"] as Vector3)
		near = minf(near, rel.dot(forward))
		far = maxf(far, rel.dot(forward))
		lateral = maxf(lateral, absf(rel.dot(right)))
		yaw = maxf(yaw, (sample["dir"] as Vector3).angle_to(forward))
		var phase := float(sample["phase"])
		var driving := phase >= float(Constants.RAKE_SWING_PHASES["plant"]) and phase <= float(Constants.RAKE_SWING_PHASES["drive_end"])
		if driving or bite_ticks.has(int(sample["tick"])):
			var tip: Vector3 = sample["tip"]
			off = maxf(off, absf(tip.y - RakeMotion.SURFACE_GAP - float(sample["ground"])))
	var ok := step <= 0.15 and off <= 0.03 and near >= 0.8 and far <= 2.3 and lateral <= 0.25 + 0.001 and yaw <= deg_to_rad(15.0) + 0.001 and far - near >= MIN_TRAVEL
	return {"ok": ok, "step": step, "off_ground": off, "near": near, "far": far, "lateral": lateral, "yaw": yaw}


## rakefeel:look: the stance plants, the knees bend into the drive (more than
## 20 degrees), and the back leans into it. The host creeps forward through the
## hold, so the feet must step rather than skate: a planted foot moves at most
## FOOT_SLIDE_MAX a tick across the ground (the body moves WALK_PER_TICK), and
## each foot takes at least one step.
const FOOT_SLIDE_MAX: float = 0.003


func _judge_legs() -> Dictionary:
	var stance := 0.0
	var knee := 0.0
	var lean := 0.0
	var slide := 0.0
	var steps: Array[int] = [0, 0]
	var last: Dictionary = {}
	for sample: Dictionary in _samples:
		if not sample.has("stance"):
			continue
		stance = maxf(stance, float(sample["stance"]))
		var phase := float(sample["phase"])
		if phase >= float(Constants.RAKE_SWING_PHASES["plant"]) and phase <= float(Constants.RAKE_SWING_PHASES["drive_end"]):
			knee = maxf(knee, float(sample["knee"]))
			lean = minf(lean, (sample["work"] as Vector3).x)
		if sample.has("feet") and last.has("feet") and int(sample["tick"]) == int(last["tick"]) + 1:
			for index: int in 2:
				var now_planted := bool(sample["planted"][index])
				var was_planted := bool(last["planted"][index])
				if now_planted and was_planted:
					var a: Vector3 = last["feet"][index]
					var b: Vector3 = sample["feet"][index]
					slide = maxf(slide, Vector2(b.x - a.x, b.z - a.z).length())
				elif was_planted and not now_planted and float(sample["stance"]) >= 1.0:
					steps[index] += 1
		last = sample
	var ok := stance >= 0.99 and knee >= deg_to_rad(20.0) and lean <= -0.4 and slide <= FOOT_SLIDE_MAX and steps[0] >= 1 and steps[1] >= 1
	return {"ok": ok, "stance": stance, "knee": knee, "lean": lean, "slide": slide, "steps": steps}


func _judge_grips() -> Dictionary:
	var gap_min := INF
	var gap_max := 0.0
	var reach := 0.0
	var worst := ""
	for sample: Dictionary in _samples:
		if not sample.has("grips") or not sample.has("shoulders"):
			continue
		var grips: Array = sample["grips"]
		if not (grips[0] as Vector3).is_finite() or not (grips[1] as Vector3).is_finite():
			continue
		var gap := (grips[0] as Vector3).distance_to(grips[1])
		gap_min = minf(gap_min, gap)
		gap_max = maxf(gap_max, gap)
		for side: int in 2:
			var miss := (grips[side] as Vector3).distance_to(sample["shoulders"][side])
			if miss > reach:
				reach = miss
				worst = "phase %.2f %s hand, grip %s from feet, shoulder %s, body work %s" % [float(sample["phase"]), "right" if side == 0 else "left", (grips[side] as Vector3) - (sample["me"] as Vector3), (sample["shoulders"][side] as Vector3) - (sample["me"] as Vector3), sample.get("work", Vector3.ZERO)]
	var ok := gap_min >= Constants.RAKE_HAND_SPAN_MIN - 0.01 and gap_max <= Constants.RAKE_HAND_SPAN + 0.01 and reach <= Constants.HOLD_GRIP_REACH
	if not ok:
		print("[RakeStrokeTest] (farthest reach at %s)" % worst)
	return {"ok": ok, "gap_min": gap_min, "gap_max": gap_max, "reach": reach}


func _hand_check(me: Node3D, lot: Node3D, report: Dictionary) -> bool:
	var hires := get_tree().get_first_node_in_group("hires")
	if hires == null:
		print("[RakeStrokeTest] no hires node: skipped the hired hand")
		return false
	# Out of the hand's way, so it finds work on the yard.
	_move_to(lot.global_position + Vector3(0.0, 0.1, 16.0), 0.0)
	hires.call("dev_add_hand", "Gravy")
	await _seconds(0.3)
	hires.call("spawn_on_lot")
	await _seconds(0.5)
	var hands := get_tree().get_nodes_in_group("crew_hands")
	if hands.is_empty():
		print("[RakeStrokeTest] the hand never showed up")
		return false
	var hand := hands[0] as Node3D
	var actor := int(hand.call("actor"))
	var events: Array = []
	var field := get_tree().get_first_node_in_group("leaf_field")
	if field.has_signal("stroke_event"):
		field.connect("stroke_event", func(ev: Dictionary) -> void:
			if str(ev.get("kind", "")) == "crew_rake":
				events.append(ev)
		)
	var strokes: Array = []
	hand.connect("raked", func(_at: Vector3) -> void: strokes.append(Engine.get_physics_frames()))
	_samples.clear()
	_watch = func() -> Dictionary:
		var pose := hand.get_node_or_null("Visual/HandRake/Pose") as Node3D
		return {"tick": Engine.get_physics_frames(), "at": hand.global_position, "action": str(hand.get("action")), "head": pose.get_meta("head_at", Vector3.INF) if pose != null else Vector3.INF, "ahead": hand.global_basis.z}
	_recording = true
	var waited := 0.0
	while strokes.size() < 5 and waited < 30.0:
		await _seconds(0.5)
		waited += 0.5
	_recording = false
	# Pace: the gap between strokes is the hand's swing.
	var cycle := Constants.HIRE_STROKE_SECONDS / maxf(float(hand.get("skill")), 0.3)
	var pace_ok := strokes.size() >= 4
	var mean := 0.0
	if strokes.size() >= 2:
		mean = float(int(strokes[strokes.size() - 1]) - int(strokes[0])) / 60.0 / float(strokes.size() - 1)
		pace_ok = pace_ok and absf(mean - cycle) <= cycle * 0.05
	# Bite phase, from the hand's own log.
	var phase_ok := true
	for entry: Dictionary in hand.get("stroke_log"):
		if absf(float(entry["phase"]) - Constants.RAKE_CREW_BITES[0]) > 0.05:
			phase_ok = false
	# Actor id in the events (raking:1), else the hand's own id.
	var actor_ok := actor == Constants.RAKE_ACTOR_HAND_BASE + hand.name.to_int()
	# Once the field has stroke events (raking:1), the hand's strokes must be among them.
	if field.has_signal("stroke_event"):
		actor_ok = actor_ok and not events.is_empty()
	# Each event carries the hand's own swing, so every peer's sounds keep to it (R1b).
	for ev: Dictionary in events:
		actor_ok = actor_ok and int(ev.get("actor", 0)) == actor
		actor_ok = actor_ok and absf(float(ev.get("tempo", 0.0)) - cycle) <= Constants.LEAF_EVENT_TEMPO_STEP
	# Glide and the rake's travel while raking.
	var biggest := 0.0
	var travel := 0.0
	var last := Vector3.INF
	var swing_near := INF
	var swing_far := -INF
	for sample: Dictionary in _samples:
		if str(sample["action"]) != "rake":
			last = Vector3.INF
			continue
		var at: Vector3 = sample["at"]
		if last != Vector3.INF:
			biggest = maxf(biggest, Vector2(at.x - last.x, at.z - last.z).length())
		last = at
		var head: Vector3 = sample["head"]
		if head.is_finite():
			var ahead: Vector3 = sample["ahead"]
			ahead = Vector3(ahead.x, 0.0, ahead.z).normalized()
			var along := (head - at).dot(ahead)
			swing_near = minf(swing_near, along)
			swing_far = maxf(swing_far, along)
	travel = swing_far - swing_near
	var glide_ok := biggest <= 0.03 + 0.001
	var swings_ok := travel >= MIN_TRAVEL
	print("[RakeStrokeTest] hired hand %s (actor %d): %d strokes, %.3f s apart (its swing %.3f s), at its bite %s, %d events with its actor %s, steps at most %.3f m a tick, rake travels %.2f m: %s" % [hand.name, actor, strokes.size(), mean, cycle, phase_ok, events.size(), actor_ok, biggest, travel, pace_ok and phase_ok and actor_ok and glide_ok and swings_ok])
	report["hand"] = {"strokes": strokes.size(), "mean": mean, "cycle": cycle, "phase_ok": phase_ok, "actor_ok": actor_ok, "step": biggest, "travel": travel}
	return pace_ok and phase_ok and actor_ok and glide_ok and swings_ok


# ---- client


func _run_client() -> void:
	var ok := true
	var host := _player(1)
	var waited := 0.0
	while (host == null or host.get_node_or_null("Rake") == null) and waited < 20.0:
		await _seconds(0.25)
		waited += 0.25
		host = _player(1)
	if host == null:
		result = {"ok": false, "done": true, "error": "no host player"}
		return
	# Joining brings the wallets of everyone already here (the host's rake tier).
	waited = 0.0
	while not (Campaign.get("_peer_keys") as Dictionary).has(1) and waited < 5.0:
		await _seconds(0.25)
		waited += 0.25
	var wallet_ok := (Campaign.get("_peer_keys") as Dictionary).has(1)
	print("[RakeStrokeTest] client has the host's wallet on joining: %s" % wallet_ok)
	ok = ok and wallet_ok
	var rake_node := host.get_node("Rake")
	var events: Array = []
	rake_node.connect("remote_bite", func(bite: int) -> void: events.append([Engine.get_physics_frames(), bite]))
	_samples.clear()
	_watch = _client_sample.bind(host)
	_recording = true
	# The yard's leaves are in (the snapshot came) before the host starts.
	var field := get_tree().get_first_node_in_group("leaf_field")
	waited = 0.0
	while float(field.call("leaf_units")) <= 0.0 and waited < 10.0:
		await _seconds(0.25)
		waited += 0.25
	await _seconds(0.5)
	_rpc_watching.rpc_id(1)
	if _capture_dir() != "":
		_recording = false
		var capture: Node = load("res://net/dev/rake_capture.gd").new()
		capture.set("dir", _capture_dir())
		add_child(capture)
		await capture.call("run_observer", host)
		result = {"ok": true, "done": true, "capture": true}
		_rpc_finished.rpc_id(1)
		return
	# Watch until a few swings went by and the rake has been still a while.
	waited = 0.0
	while waited < 30.0:
		await _seconds(0.25)
		waited += 0.25
		var starts := events.filter(func(e: Array) -> bool: return int(e[1]) == 0).size()
		if is_equal_approx(fmod(waited, 3.0), 0.0):
			print("[RakeStrokeTest] client watching %.0f s: %d strokes seen, host phase %.2f, host holds %s" % [waited, events.size(), RakeStroke.phase_of(1), str(host.call("_held_prop").get("kind")) if host.call("_held_prop") != null else "nothing"])
		if starts >= SWINGS_TO_WATCH and Engine.get_physics_frames() - int(events[events.size() - 1][0]) > 75:
			break
	_recording = false
	var report := _judge_remote(events)
	print("[RakeStrokeTest] client saw %d strokes of the host's: travel per swing %s m, swinging %.2f s after the first, still %.2f s after the last, leaning %.2f mid-drive, plants %.2f m off: %s" % [events.size(), report["travel"], report["start_after"], report["stop_after"], report["lean"], report["plant_off"], report["ok"]])
	ok = ok and bool(report["ok"])
	# The hired hand's rake swings here too.
	var hand_report := {}
	waited = 0.0
	var hand: Node3D = null
	while waited < 25.0 and hand == null:
		var hands := get_tree().get_nodes_in_group("crew_hands")
		if not hands.is_empty():
			hand = hands[0] as Node3D
		await _seconds(0.25)
		waited += 0.25
	if hand != null:
		_samples.clear()
		_watch = func() -> Dictionary:
			var pose := hand.get_node_or_null("Visual/HandRake/Pose") as Node3D
			var visual := hand.get_node("Visual") as Node3D
			return {"at": hand.global_position, "action": str(hand.get("action")), "head": pose.get_meta("head_at", Vector3.INF) if pose != null else Vector3.INF, "ahead": hand.global_basis.z, "visual": visual.global_basis.z, "vat": visual.global_position}
		_recording = true
		waited = 0.0
		var before := int(hand.get("stroke_count"))
		while waited < 20.0 and int(hand.get("stroke_count")) < before + 3:
			await _seconds(0.25)
			waited += 0.25
		_recording = false
		var near := INF
		var far := -INF
		for sample: Dictionary in _samples:
			var head: Vector3 = sample["head"]
			if str(sample["action"]) != "rake" or not head.is_finite():
				continue
			# The drawn body (100 ms behind) has turned to where the hand faces.
			var ahead: Vector3 = sample["visual"]
			ahead = Vector3(ahead.x, 0.0, ahead.z).normalized()
			if ahead.dot((sample["ahead"] as Vector3).normalized()) < 0.98:
				continue
			var along := (head - (sample["vat"] as Vector3)).dot(ahead)
			near = minf(near, along)
			far = maxf(far, along)
		var strokes := int(hand.get("stroke_count")) - before
		var hand_ok := strokes >= 3 and far - near >= MIN_TRAVEL and far - near <= Constants.RAKE_HEAD_FAR - Constants.RAKE_HEAD_NEAR + 0.4
		hand_report = {"strokes": strokes, "travel": far - near, "ok": hand_ok}
		print("[RakeStrokeTest] client saw the hired hand's rake: %d strokes, travels %.2f m: %s" % [strokes, far - near, hand_ok])
		ok = ok and hand_ok
	else:
		print("[RakeStrokeTest] client never saw a hired hand")
		ok = false
	# The host bought the Tune-Up: its rake here has the Tune-Up head too.
	var tier := -1
	waited = 0.0
	while waited < 8.0:
		var pose := _prop("rake").get_node_or_null("Visual/Look/Pose") if _prop("rake") != null else null
		tier = int(pose.get_meta("tier", -1)) if pose != null else -1
		if tier == 1:
			break
		await _seconds(0.25)
		waited += 0.25
	var tier_ok := tier == 1
	print("[RakeStrokeTest] client draws the host's Mk II rake: head %d: %s" % [tier, tier_ok])
	ok = ok and tier_ok
	result = {"ok": ok, "done": true, "remote": report, "hand": hand_report, "tier": tier}
	print("[RakeStrokeTest] client all ok: %s" % ok)
	_rpc_finished.rpc_id(1)


func _client_sample(host: Node3D) -> Dictionary:
	var out := {"tick": Engine.get_physics_frames(), "phase": RakeStroke.phase_of(host.name.to_int()), "me": host.global_position, "forward": -host.global_basis.z}
	var held: Node = host.call("_held_prop")
	var pose := held.get_node_or_null("Visual/Look/Pose") as Node3D if held != null and str(held.get("kind")) == "rake" else null
	if pose != null and pose.has_meta("head_at"):
		out["at"] = pose.get_meta("head_at")
	var body := host.get_node_or_null("Visual/CartoonBody")
	if body != null and body.has_method("work_pose"):
		out["lean"] = (body.call("work_pose") as Vector3).x
	return out


func _judge_remote(events: Array) -> Dictionary:
	var starts: Array = []
	for entry: Array in events:
		if int(entry[1]) == 0:
			starts.append(int(entry[0]))
	var travel: Array = []
	var lean := 0.0
	var plant_off := 0.0
	var start_after := INF
	var stop_after := INF
	if events.is_empty():
		return {"ok": false, "travel": travel, "lean": lean, "plant_off": plant_off, "start_after": start_after, "stop_after": stop_after}
	var first := int(events[0][0])
	var last := int(events[events.size() - 1][0])
	# Group samples by swing (from one plant to the next).
	for index: int in starts.size():
		var from := int(starts[index])
		var to := int(starts[index + 1]) if index + 1 < starts.size() else from + 40
		var near := INF
		var far := -INF
		for sample: Dictionary in _samples:
			var tick := int(sample["tick"])
			if tick < from or tick >= to or not sample.has("at"):
				continue
			var forward: Vector3 = sample["forward"]
			forward = Vector3(forward.x, 0.0, forward.z).normalized()
			var along := ((sample["at"] as Vector3) - (sample["me"] as Vector3)).dot(forward)
			near = minf(near, along)
			far = maxf(far, along)
			# Just after the plant the head is where the owner's planted.
			if tick == from + 1:
				plant_off = maxf(plant_off, absf(along - Constants.RAKE_HEAD_NEAR))
			var phase := float(sample["phase"])
			if phase >= 0.4 and phase <= 0.6 and sample.has("lean"):
				lean = minf(lean, float(sample["lean"]))
		travel.append(snappedf(far - near, 0.01))
	for sample: Dictionary in _samples:
		var tick := int(sample["tick"])
		if tick >= first and float(sample["phase"]) >= 0.0 and start_after == INF:
			start_after = float(tick - first) / 60.0
		if tick > last and float(sample["phase"]) < 0.0 and stop_after == INF:
			stop_after = float(tick - last) / 60.0
	var travel_ok := travel.size() >= SWINGS_TO_WATCH
	# The last swing may be cut short by the end of the hold: judge all but it.
	for index: int in maxi(travel.size() - 1, 0):
		travel_ok = travel_ok and float(travel[index]) >= MIN_TRAVEL
	var ok := travel_ok and start_after <= 0.35 and stop_after <= 0.9 and lean < -0.05 and plant_off <= 0.2
	return {"ok": ok, "travel": travel, "lean": lean, "plant_off": plant_off, "start_after": start_after, "stop_after": stop_after}


# ---- captures (net/dev/rake_capture.gd)


## --rake-capture=<dir>: film the swing instead of testing it (windowed runs).
func _capture_dir() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--rake-capture="):
			return argument.trim_prefix("--rake-capture=")
	return ""


func _capture_host() -> void:
	var field := get_tree().get_first_node_in_group("leaf_field")
	var lot := get_tree().get_first_node_in_group("job_lot") as Node3D
	var me := _own_player()
	_move_to(_leafy_spot(field, lot), -PI * 0.5)
	await _grab(_prop("rake"))
	await _seconds(1.0)
	var capture: Node = load("res://net/dev/rake_capture.gd").new()
	capture.set("dir", _capture_dir())
	add_child(capture)
	await capture.call("run_host", me)
	var waited := 0.0
	while not _client_done and waited < 10.0:
		await _seconds(0.25)
		waited += 0.25
	result = {"ok": true, "done": true, "capture": true}


# ---- helpers


## Untouched leaves with room ahead along +X.
func _leafy_spot(field: Node, lot: Node3D) -> Vector3:
	for z: float in [-6.0, -10.0, 2.0, 6.0, -14.0, 10.0]:
		for x: float in [-15.0, -9.0, 3.0, 9.0]:
			var fine := true
			for step: int in 8:
				if int(field.call("sample_world", lot.global_position + Vector3(x + float(step) * 0.5, 0.2, z))) < 36:
					fine = false
			if fine:
				return lot.global_position + Vector3(x, 0.1, z)
	return lot.global_position + Vector3(-9.0, 0.1, -6.0)


func _grab(item: Node3D) -> void:
	var me := _own_player()
	await get_tree().physics_frame
	item.global_position = me.global_position + Vector3(0.0, 0.4, 0.0) + (-me.global_basis.z) * 0.8
	item.set("linear_velocity", Vector3.ZERO)
	await _ticks(2)
	item.call("request_grab")
	await _ticks(3)


func _move_to(at: Vector3, yaw: float) -> void:
	var me := _own_player()
	me.call("apply_network_teleport", Transform3D(Basis(Vector3.UP, yaw), at))
	me.set("body_yaw", yaw)


## How many published rake heads (contract C4) say this actor's tines are down mid-swing.
func _lowered_heads(actor: int) -> int:
	var count := 0
	for node: Node in get_tree().get_nodes_in_group("rake_heads"):
		if int(node.get_meta("actor", -1)) == actor and bool(node.get_meta("down", false)) and float(node.get_meta("phase", -1.0)) >= 0.0:
			count += 1
	return count


func _seconds(count: float) -> void:
	await get_tree().create_timer(count).timeout


func _ticks(count: int) -> void:
	for _tick: int in count:
		await get_tree().physics_frame


func _own_player() -> Node3D:
	return _player(Net.local_peer_id())


func _player(peer_id: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node as Node3D
	return null


func _prop(kind: String) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) == kind and not node.is_queued_for_deletion():
			return node as Node3D
	return null
