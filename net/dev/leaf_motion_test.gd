extends Node

## Authority: host drives, both peers check. --leaf-motion-test checks that leaves
## travel between cells instead of teleporting (leaves/leaf_motion.gd; raking R1
## chunk 3): every unit is conserved every tick (on the view, in flight or still
## to land), every flake that leaves or appears does so through a launch, a
## landing, a kick or a morph, rake leaves launch when the tines pass them and
## land ahead of where they lay, bags slurp, burst bags fountain, running and
## diving kick up the same flakes, the view settles back onto the field exactly,
## resets snap, and a heavy load stays inside the caps. Run with --start-zone=lot
## --all-tools --job-seed=777 --yard-size=1 and --leaf-motion-headless on both
## peers (the client joins with --leaf-motion-test --sim-lag=120 too).
## Uses the real leaf view when the field's LeafRenderer has the C3 API (raking:2),
## else net/dev/leaf_view_stub.gd. Uses the field's stroke events when it has them
## (raking:1), else sends the same events itself.
## Windowed with --leaf-motion-shots=<dir>: also films frame sequences of each
## moment in slow motion into <dir> (side view and first person).

static var result: Dictionary = {}

const _Stub = preload("res://net/dev/leaf_view_stub.gd")
## The fake rake head's swing, shaped like raking:4's RakeStroke at its defaults
## (RAKE_SWING_BITES, RAKE_HEAD_NEAR/FAR): 0.6 s, plant at 0.2, drive to 0.7.
const SWING_SECONDS: float = 0.6
const BITES: Array[float] = [0.2, 0.5]
const DRIVE := Vector2(0.2, 0.7)
const HEAD_NEAR: float = 0.85
const HEAD_FAR: float = 2.25
const HEAD_HALF: float = 0.475
## Load step: synthetic rakers and hands, and how long.
const LOAD_RAKERS: int = 4
const LOAD_HANDS: int = 2
const LOAD_SECONDS: float = 20.0
const QUIET_SECONDS: float = 2.0
## "snap" is the real view's one entry per hard reset (raking:2), which the hard reset step makes.
const ALLOWED_LOG: Array[String] = ["launch", "land", "kick_take", "kick_return", "morph_in", "morph_out", "snap"]

var _started: bool = false
var _field: Node3D
var _view: Node
var _motion: Node
var _stub: bool = false
var _events: bool = false
var _head: Node3D
var _seq: int = 0
var _checks: Dictionary = {}
var _notes: Dictionary = {}
var _client_report: Dictionary = {}
var _conservation_bad: int = 0
var _conservation_samples: int = 0
var _conservation_first: String = ""
var _dup_watch: bool = false
var _dup_bad: int = 0
var _dup_samples: int = 0
var _frame: int = 0
var _last_morph: int = -1
var _hard_check: Dictionary = {}
var _shots: String = ""
var _side: Camera3D
## Motion clock at the last plant bite (-1 until one), for the films.
var _bite_clock: float = -1.0
## Bites so far (the sink step waits on it).
var _bites: int = 0


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--leaf-motion-shots="):
			_shots = argument.trim_prefix("--leaf-motion-shots=")
	if DisplayServer.get_name() == "headless":
		_shots = ""


func _process(_delta: float) -> void:
	if not _started:
		if get_tree().get_first_node_in_group("leaf_field") == null or _own_player() == null:
			return
		if Net.is_host() and get_tree().get_first_node_in_group("job_tasks") == null:
			return
		_started = true
		if Net.is_host():
			_run()
		else:
			_setup()
		return
	if Net.is_host() and not bool(result.get("done", false)):
		# No NICE BOYS raid mid-test: one that catches the host carries its camera
		# off the yard, and every later batch is out of motion range (LOD-skipped),
		# so the load steps would pass with nothing flying (seen at the R1 merge).
		var director := get_tree().get_first_node_in_group("run_director")
		if director != null and "_next_roll" in director:
			director.set("_next_roll", Net.server_time() + 60.0)
	if _motion == null or _view == null or not is_instance_valid(_view):
		return
	_frame += 1
	if _frame % 3 == 0:
		_check_conservation()
	if _dup_watch:
		_check_duplicates()


# ---- setup

func _setup() -> bool:
	_field = get_tree().get_first_node_in_group("leaf_field") as Node3D
	_events = _field.has_signal("stroke_event")
	var renderer := _field.get_node_or_null("LeafRenderer")
	if renderer != null and renderer.has_method("take_launch"):
		_view = renderer
	else:
		_stub = true
		if renderer != null:
			(renderer as Node3D).visible = false
		_view = _Stub.new()
		_view.name = "LeafViewStub"
		_field.add_child(_view)
	var waited := 0.0
	while get_tree().get_first_node_in_group("leaf_motion") == null and waited < 4.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	_motion = get_tree().get_first_node_in_group("leaf_motion")
	if _motion == null:
		print("[LeafMotionTest] no LeafMotion (headless without --leaf-motion-headless?)")
		return false
	_view.call("set_flake_log", true)
	_view.connect("targets_changed", _on_targets_changed)
	print("[LeafMotionTest] view %s, stroke events %s, cap %d" % ["stub" if _stub else "real", _events, int(_motion.call("stats")["cap"])])
	return true


# ---- the host's run

func _run() -> void:
	var waited := 0.0
	while Net.peer_ids().size() < 2 and waited < 8.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	if not await _setup():
		_finish(false, "no motion layer")
		return
	await _seconds(2.0)
	_motion.call("set_trace", true)
	var lot := get_tree().get_first_node_in_group("job_lot") as Node3D
	var me := _own_player()
	_head = Node3D.new()
	_head.name = "FakeRakeHead"
	add_child(_head)
	_head.set_meta("actor", Net.local_peer_id())
	_head.set_meta("phase", -1.0)
	_head.set_meta("down", false)
	_head.set_meta("head_a", Vector3.ZERO)
	_head.set_meta("head_b", Vector3.ZERO)
	_head.set_meta("half_width", HEAD_HALF)
	_head.add_to_group("rake_heads")
	await _grab(_prop("rake"))
	# 1. Rake toward +X on fresh carpet: three swings, two bites each.
	var strip := _find_strip(lot, Vector3(1.0, 0.0, 0.0))
	if strip == Vector3.INF:
		_finish(false, "no untouched strip")
		return
	_motion.call("set_trace", true)
	for swing: int in 3:
		var stand := strip + Vector3(float(swing) * 1.0 - 1.5, 0.0, 0.0)
		if _shots != "" and swing == 0:
			_film("fresh_carpet", stand, Vector3(1.0, 0.0, 0.0), true)
		if _shots != "" and swing == 2:
			_film("onto_pile", stand, Vector3(1.0, 0.0, 0.0), true)
		await _swing(stand, Vector3(1.0, 0.0, 0.0))
	await _quiet()
	_judge_direction("plus_x", Vector3(1.0, 0.0, 0.0))
	_judge_contact()
	var pile := _pile_near(strip + Vector3(4.5, 0.0, 0.0), Vector3(1.0, 0.0, 0.0))
	# 2. Running through the pile and diving into it: the same flakes, no duplicates.
	await _kick_check(pile)
	# 3. Bagging the pile: the leaves spiral into the bag.
	await _bag_check(pile)
	# 4. Rake toward -Z on another strip.
	var strip_z := _find_strip(lot, Vector3(0.0, 0.0, -1.0))
	if strip_z != Vector3.INF:
		# The dive put the rake down.
		_move_to(strip_z + Vector3(0.0, 0.0, 1.5), PI)
		await _ticks(2)
		await _grab(_prop("rake"))
		print("[LeafMotionTest] holding %s for -Z" % _held_kind())
		_motion.call("set_trace", true)
		for swing: int in 3:
			await _swing(strip_z + Vector3(0.0, 0.0, 1.5 - float(swing) * 1.0), Vector3(0.0, 0.0, -1.0))
		await _quiet()
		_judge_direction("minus_z", Vector3(0.0, 0.0, -1.0))
	else:
		_note("minus_z", "no untouched strip")
		_checks["minus_z"] = false
	# 4b. Bag, then mow, a ridge while the rake's leaves are still flying into it.
	await _sink_soon_check(lot, "bag")
	await _sink_soon_check(lot, "mulch")
	# 5. A burst bag fountains leaves out of its mouth.
	await _scatter_check(lot)
	# 6. Resyncs nothing explains: a small one animates, a big one morphs.
	await _resync_check(lot)
	# 7. Hard resets snap: no movers, the view equals the field the same frame.
	await _hard_check_run(lot)
	# 8. Prediction (needs raking:1's ledger and the client's own strokes).
	if not _events:
		_note("prediction", "skipped: the field has no stroke_event yet (raking:1)")
	# 9. Load: four rakers and two hands at once, then on the 'low' preset's pool,
	# where it fills and splits have no room.
	await _load_check(lot, 0, LOAD_SECONDS, "load")
	await _quiet()
	await _load_check(lot, int(Constants.LEAF_DETAIL["low"][0]), LOAD_SECONDS * 0.4, "load_low")
	_motion.call("set_pool_limit", 0)
	# 10. Quiet again: everything lands, the view equals the field, nothing left over.
	await _quiet()
	_quiescence("quiescence_host")
	_judge_log()
	var stats: Dictionary = _motion.call("stats")
	_checks["no_pops"] = int(stats["pops"]) == 0 and int((_view.call("stats") as Dictionary).get("instant", 0)) == 0
	# Every leaf homed into its slot; none had to jump the last bit at LEAF_SETTLE_MAX.
	_checks["no_snaps"] = int(stats["snaps"]) == 0 and float(stats["max_handoff"]) <= 0.02
	_checks["max_step"] = float(stats["max_step"]) <= Constants.LEAF_MAX_STEP + 0.001
	_checks["max_age"] = float(stats["max_age"]) <= Constants.LEAF_SETTLE_MAX + 0.1
	_checks["conservation_host"] = _conservation_bad == 0 and _conservation_samples > 50
	_checks["no_duplicates_host"] = _dup_bad == 0 and _dup_samples > 10
	# The gate itself, for each display: headless runs it only with the flag.
	var flag := PackedStringArray(["--leaf-motion-headless"])
	_checks["headless_default"] = not LeafMotion.allowed(PackedStringArray(), "headless") and LeafMotion.allowed(flag, "headless") and LeafMotion.allowed(PackedStringArray(), "Windows")
	# Hinted batches fly every unit they move: nothing shrinks away instead (the
	# host gets each change whole; a client before raking:1 gets it chunk by chunk).
	_note("fades", "host faded %d units in hinted batches (%d in all), pool overflow morphed %d" % [int(stats["fade_units_hinted"]), int(stats["fade_units"]), int(stats["morph_units"])])
	_checks["no_hinted_fades_host"] = int(stats["fade_units_hinted"]) == 0
	# The client's half.
	if Net.peer_ids().size() > 1:
		_rpc_final.rpc()
		var wait := 0.0
		while _client_report.is_empty() and wait < 5.0:
			await get_tree().create_timer(0.1).timeout
			wait += 0.1
		if _client_report.is_empty():
			_checks["client"] = false
			_note("client", "no report")
		else:
			for key: String in _client_report.get("checks", {}):
				_checks["client_" + key] = bool(_client_report["checks"][key])
			var theirs: Dictionary = _client_report.get("motion", {})
			# Before raking:1 a client gets a stroke's chunks in separate frames, so part
			# of each stroke shrinks away and drops in instead of flying (asserted once
			# the field sends stroke events).
			_note("client_fades", "client faded %d units in hinted batches, dropped %d batches" % [int(theirs.get("fade_units_hinted", 0)), int(theirs.get("drops", 0))])
			if _events:
				_checks["client_no_hinted_fades"] = int(theirs.get("fade_units_hinted", 0)) == 0
	else:
		_note("client", "no client joined")
	var ok := true
	for key: String in _checks:
		if not bool(_checks[key]):
			ok = false
			print("[LeafMotionTest] FAILED %s %s" % [key, _notes.get(key, "")])
	_finish(ok, "")


func _finish(ok: bool, why: String) -> void:
	var stats: Dictionary = _motion.call("stats") if _motion != null else {}
	result = {"ok": ok, "done": true, "why": why, "checks": _checks.duplicate(), "notes": _notes.duplicate(), "view": "stub" if _stub else "real", "events": _events, "motion": stats, "view_stats": _view.call("stats") if _view != null else {}, "client": _client_report}
	print("[LeafMotionTest] motion %s" % JSON.stringify(stats))
	print("[LeafMotionTest] all ok: %s %s" % [ok, why])


func _note(key: String, text: String) -> void:
	_notes[key] = text
	print("[LeafMotionTest] %s: %s" % [key, text])


# ---- strokes

## One swing of the fake head from stand along dir, with a field stroke at each bite.
func _swing(stand: Vector3, dir: Vector3) -> void:
	_move_to(stand, atan2(-dir.x, -dir.z))
	await _ticks(1)
	var t := 0.0
	var fired := 0
	while t < SWING_SECONDS:
		var phase := t / SWING_SECONDS
		_pose_head(stand, dir, phase)
		if fired < BITES.size() and phase >= BITES[fired]:
			_bite(stand, dir, fired)
			fired += 1
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_pose_head(stand, dir, -1.0)


func _pose_head(stand: Vector3, dir: Vector3, phase: float) -> void:
	var drive := clampf((phase - DRIVE.x) / (DRIVE.y - DRIVE.x), 0.0, 1.0)
	var smooth := drive * drive * drive * (drive * (drive * 6.0 - 15.0) + 10.0)
	var reach := lerpf(HEAD_NEAR, HEAD_FAR, smooth) if phase >= DRIVE.x else HEAD_NEAR
	if phase > DRIVE.y:
		reach = lerpf(HEAD_FAR, HEAD_NEAR, clampf((phase - DRIVE.y) / (1.0 - DRIVE.y), 0.0, 1.0))
	var mid := stand + dir * reach
	mid.y = float(_view.call("surface_y", Vector2(mid.x, mid.z))) + 0.02
	var right := dir.cross(Vector3.UP).normalized()
	var down := phase >= DRIVE.x and phase <= DRIVE.y
	_head.set_meta("phase", phase)
	_head.set_meta("down", down)
	_head.set_meta("head_a", mid - right * HEAD_HALF)
	_head.set_meta("head_b", mid + right * HEAD_HALF)
	_head.set_meta("drive_dir", dir)
	_head.global_position = mid


func _bite(stand: Vector3, dir: Vector3, bite: int) -> void:
	_bites += 1
	if bite == 0:
		_bite_clock = float(_motion.call("clock"))
	var at := stand + dir * 1.5 + Vector3(0.0, 0.2, 0.0)
	var before := int(_field.call("units_within_world", at + dir, Constants.RAKE_WIDTH))
	if _events:
		_field.call("request_rake", at, dir, Constants.RAKE_WIDTH, Constants.RAKE_STRENGTH, bite, SWING_SECONDS)
		return
	_field.call("request_rake", at, dir, Constants.RAKE_WIDTH, Constants.RAKE_STRENGTH)
	_hint({"kind": "rake", "actor": Net.local_peer_id(), "bite": bite, "at": at, "dir": dir, "width": Constants.RAKE_WIDTH, "cells": Constants.RAKE_STROKE_CELLS, "moved": maxi(before / 3, 0), "tempo": SWING_SECONDS})


## A stroke event the field does not send yet (before raking:1): here and on the client.
func _hint(ev: Dictionary) -> void:
	_seq += 1
	ev["seq"] = _seq
	ev["t"] = Net.server_time()
	if not ev.has("step"):
		var flat: Vector3 = ev.get("dir", Vector3.ZERO)
		var step := Vector2i(int(round(flat.x)), int(round(flat.z)))
		ev["step"] = step if step != Vector2i.ZERO else Vector2i(0, 1)
	var mine := ev.duplicate()
	mine["local"] = true
	_motion.call("add_hint", mine)
	if Net.peer_ids().size() > 1:
		var theirs := ev.duplicate()
		theirs["local"] = false
		_rpc_hint.rpc(theirs)


@rpc("authority", "call_remote", "reliable")
func _rpc_hint(ev: Dictionary) -> void:
	if _motion != null:
		_motion.call("add_hint", ev)


# ---- judging

func _judge_direction(key: String, dir: Vector3) -> void:
	var trace: Dictionary = _motion.call("trace")
	var along := 0.0
	var count := 0
	var behind := 0
	for entry: Dictionary in trace["finished"]:
		if str(entry["kind"]) != "rake":
			continue
		var moved := ((entry["end"] as Vector3) - (entry["start"] as Vector3)).dot(dir)
		along += moved
		count += 1
		if moved < 0.0:
			behind += 1
	var mean := along / float(maxi(count, 1))
	var share := float(behind) / float(maxi(count, 1))
	_note(key, "%d rake leaves landed, mean %.2f m along the stroke, %.1f%% behind their start" % [count, mean, share * 100.0])
	_checks[key] = count >= 20 and mean >= 0.5 and share < 0.02


func _judge_contact() -> void:
	var trace: Dictionary = _motion.call("trace")
	var contact := 0
	var timeout := 0
	var waited_max := 0.0
	for entry: Dictionary in trace["finished"]:
		if str(entry["kind"]) != "rake":
			continue
		waited_max = maxf(waited_max, float(entry["waited"]))
		if int(entry["rule"]) != LeafMovers.R_TINE:
			continue
		match int(entry["how"]):
			LeafMovers.HOW_CONTACT:
				contact += 1
			LeafMovers.HOW_TIMEOUT:
				timeout += 1
	var share := float(contact) / float(maxi(contact + timeout, 1))
	_note("head_contact", "%d leaves under the head launched as the tines passed, %d timed out (%.0f%%); longest wait %.2f s" % [contact, timeout, share * 100.0, waited_max])
	_checks["head_contact"] = contact >= 10 and share >= 0.9 and waited_max <= Constants.LEAF_MOVER_WAIT_MAX + 0.034


func _judge_log() -> void:
	var log: Array = _view.call("flake_log")
	var bad := 0
	for entry: Dictionary in log:
		if not ALLOWED_LOG.has(str(entry["what"])):
			bad += 1
	_note("flake_log", "%d flake changes, %d not a launch, landing, kick or morph" % [log.size(), bad])
	_checks["flake_log"] = bad == 0 and log.size() > 0


## Units on the view + still to land - still to launch == the field target, per cell.
func _check_conservation() -> void:
	# Morphs are the view's own unclaimed easing; skip frames with any running (the
	# stub calls them "fading", the real view "morphing").
	var view_stats: Dictionary = _view.call("stats")
	if int(view_stats.get("fading" if _stub else "morphing", 0)) > 0:
		return
	var ledger: Dictionary = _motion.call("ledger")
	var grid := Vector2i(int(_field.get("grid_width")), int(_field.get("grid_depth")))
	_conservation_samples += 1
	for z: int in grid.y:
		for x: int in grid.x:
			var cell := Vector2i(x, z)
			var gap := int(_view.call("target_units", cell)) - int(_view.call("displayed_units", cell))
			if gap != int(ledger.get(x + z * grid.x, 0)):
				_conservation_bad += 1
				if _conservation_first == "":
					_conservation_first = "cell %s: target - displayed %d, in flight %d" % [cell, gap, int(ledger.get(x + z * grid.x, 0))]
					print("[LeafMotionTest] conservation broke at %s" % _conservation_first)
				return


func _check_duplicates() -> void:
	var view_stats: Dictionary = _view.call("stats")
	var grid := Vector2i(int(_field.get("grid_width")), int(_field.get("grid_depth")))
	var heroes := 0
	for z: int in grid.y:
		for x: int in grid.x:
			heroes += int(_view.call("hero_count", int(_view.call("displayed_units", Vector2i(x, z)))))
	_dup_samples += 1
	if int(view_stats["hero_instances"]) + int(_motion.call("kick_count")) != heroes:
		_dup_bad += 1


func _quiescence(key: String) -> void:
	var grid := Vector2i(int(_field.get("grid_width")), int(_field.get("grid_depth")))
	var wrong := 0
	for z: int in grid.y:
		for x: int in grid.x:
			if int(_view.call("displayed_units", Vector2i(x, z))) != int(_field.call("density_at_cell", x, z)):
				wrong += 1
	var stats: Dictionary = _motion.call("stats")
	var view_stats: Dictionary = _view.call("stats")
	_note(key, "%d cells off the field, %d movers, %d fading, %d parked" % [wrong, int(stats["movers_alive"]), int(view_stats.get("fading", 0)), int(stats["parked"])])
	_checks[key] = wrong == 0 and int(stats["movers_alive"]) == 0 and int(view_stats.get("fading", 0)) == 0 and int(stats["parked"]) == 0


func _on_targets_changed(_changes: PackedInt32Array, hard: bool) -> void:
	if not hard or _hard_check.get("armed", false) == false:
		return
	_hard_check["armed"] = false
	# LeafMotion is connected first, so it already dropped every mover.
	_hard_check["movers"] = int(_motion.call("stats")["movers_alive"])
	_after_hard.call_deferred()


func _after_hard() -> void:
	var grid := Vector2i(int(_field.get("grid_width")), int(_field.get("grid_depth")))
	var wrong := 0
	for z: int in grid.y:
		for x: int in grid.x:
			var cell := Vector2i(x, z)
			if int(_view.call("displayed_units", cell)) != int(_view.call("target_units", cell)):
				wrong += 1
	_hard_check["wrong"] = wrong
	_hard_check["done"] = true


# ---- steps

func _kick_check(pile: Vector3) -> void:
	var me := _own_player()
	if pile == Vector3.INF:
		_checks["kicks"] = false
		_note("kicks", "no pile")
		return
	var before: Dictionary = _motion.call("stats")
	_dup_watch = true
	if _shots != "":
		_film("wading", pile - Vector3(2.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0))
	# Run through it at 4 m/s (game time: the films run in slow motion).
	var ran := 0.0
	while ran < 4.0:
		_move_to(pile + Vector3(-2.0 + ran, 0.1, 0.0), -PI * 0.5)
		await get_tree().physics_frame
		ran += 4.0 * get_physics_process_delta_time()
	await _seconds(1.2)
	var after_run: Dictionary = _motion.call("stats")
	# Dive in.
	_move_to(Vector3(pile.x, 0.1, pile.z), 0.0)
	await _ticks(3)
	if _shots != "":
		_film("dive", pile, Vector3(1.0, 0.0, 0.0))
	_field.call("request_pile_hide")
	await _ticks(4)
	var dived := bool(me.get("in_pile"))
	await _seconds(1.4)
	var after: Dictionary = _motion.call("stats")
	me.call("set_pile", false)
	await _ticks(2)
	var kicks := int(after_run["kicks"]) - int(before["kicks"])
	var dives := int(after["dives"]) - int(before["dives"])
	var thrown := int(after["kicks"]) - int(after_run["kicks"])
	# Run through it again and rake just behind the runner while the flakes they
	# kicked are in the air: a launch from a cell whose top flake is airborne must
	# not draw that flake twice (it goes on as the launching leaf).
	var ran_again := 0.0
	var next_bite := 0.9
	while ran_again < 4.0:
		var runner := pile + Vector3(-2.0 + ran_again, 0.1, 0.0)
		_move_to(runner, -PI * 0.5)
		if ran_again >= next_bite:
			# The dive pocketed the rake: stroke the field directly (as the load step does).
			next_bite += 0.5
			var at := runner - Vector3(0.8, 0.0, 0.0)
			var dir := Vector3(1.0, 0.0, 0.0)
			if _events:
				_field.call("host_hand_rake", at, dir, 1.0, Net.local_peer_id())
			else:
				_field.call("_stroke_cells", at, dir, Constants.RAKE_WIDTH, Constants.RAKE_STRENGTH, Constants.RAKE_STROKE_CELLS)
				_hint({"kind": "rake", "actor": Net.local_peer_id(), "at": at, "dir": dir, "width": Constants.RAKE_WIDTH, "cells": Constants.RAKE_STROKE_CELLS, "moved": 1500})
		await get_tree().physics_frame
		ran_again += 4.0 * get_physics_process_delta_time()
	await _seconds(1.2)
	var after_rake: Dictionary = _motion.call("stats")
	_dup_watch = false
	var handed := int(after_rake["kick_handovers"]) - int(after["kick_handovers"])
	_note("kick_launch", "running and raking at once: %d kicks, %d handed over to a launch, %d faded, %d duplicate frames of %d" % [int(after_rake["kicks"]) - int(after["kicks"]), handed, int(after_rake["kicks_faded"]) - int(after["kicks_faded"]), _dup_bad, _dup_samples])
	_checks["kick_launch"] = _dup_bad == 0 and handed > 0
	_note("kicks", "running kicked up %d flakes; the dive (in the pile %s) threw up %d; %d duplicate frames of %d" % [kicks, dived, thrown, _dup_bad, _dup_samples])
	_checks["kicks"] = kicks > 0 and (not dived or (dives > 0 and thrown > 0)) and _dup_bad == 0


func _bag_check(pile: Vector3) -> void:
	if pile == Vector3.INF:
		_checks["bag"] = false
		return
	var me := _own_player()
	_motion.call("set_trace", true)
	var at := pile + Vector3(0.0, 0.2, 0.0)
	_move_to(pile - Vector3(1.4, 0.0, 0.0), -PI * 0.5)
	await _ticks(2)
	if _shots != "":
		_film("bagging", pile - Vector3(1.4, 0.0, 0.0), Vector3(1.0, 0.0, 0.0))
	var units := int(_field.call("units_within_world", at, Constants.BAG_RADIUS))
	_field.call("request_collect", at, Constants.BAG_RADIUS)
	if not _events:
		_hint({"kind": "bag", "actor": Net.local_peer_id(), "at": at, "dir": Vector3(1.0, 0.0, 0.0), "width": Constants.BAG_RADIUS * 2.0, "cells": 0, "moved": units})
	await _seconds(1.2)
	var trace: Dictionary = _motion.call("trace")
	var count := 0
	var late := 0
	var off := 0.0
	for entry: Dictionary in trace["finished"]:
		if str(entry["kind"]) != "bag":
			continue
		count += 1
		if float(entry["waited"]) + float(entry["age"]) > 0.55:
			late += 1
		var mouth := Vector3(at.x, at.y + Constants.LEAF_BAG_MOUTH, at.z)
		off = maxf(off, Vector2((entry["end"] as Vector3).x - mouth.x, (entry["end"] as Vector3).z - mouth.z).length())
	_note("bag", "%d leaves went into the bag (%d units under it, me at %s), %d later than 0.55 s, farthest %.2f m off the mouth" % [count, units, me.global_position, late, off])
	_checks["bag"] = count >= 4 and late == 0 and off < 0.3


## Rakes a strip and, while the swing's leaves are still on their way, bags (or
## mows) where most of them are heading: the leaves in the air must go into the
## sink from the air, the cell must not launch leaves it does not show, and the
## books must still balance and settle onto the field (the hired hands' rake, then
## bag right away).
func _sink_soon_check(lot: Node3D, kind: String) -> void:
	var key := "sink_soon_" + kind
	var dir := Vector3(1.0, 0.0, 0.0)
	var strip := _find_strip(lot, dir)
	if strip == Vector3.INF:
		_note(key, "no untouched strip")
		_checks[key] = false
		return
	if _held_kind() != "rake":
		_move_to(strip, -PI * 0.5)
		await _ticks(2)
		await _grab(_prop("rake"))
	var bad_before := _conservation_bad
	var before: Dictionary = _motion.call("stats")
	var stand := strip + dir * 0.5
	var bites := _bites
	_swing(stand, dir)
	while _bites < bites + 2:
		await get_tree().physics_frame
	# One field flush (10 Hz before raking:1) and its batch.
	await _seconds(0.15)
	var spot := _incoming_spot()
	if spot == Vector3.INF:
		_note(key, "nothing in flight after the swing")
		_checks[key] = false
		await _quiet()
		return
	var in_flight := 0
	for coming: int in (_motion.call("ledger") as Dictionary).values():
		in_flight += maxi(coming, 0)
	var at := spot + Vector3(0.0, 0.2, 0.0)
	var units := int(_field.call("units_within_world", at, Constants.BAG_RADIUS))
	if kind == "bag":
		_move_to(spot - dir * 1.4, -PI * 0.5)
		await get_tree().physics_frame
		if _shots != "":
			_film("bag_from_air", spot - dir * 2.4, dir)
		_field.call("request_collect", at, Constants.BAG_RADIUS)
	else:
		_field.call("host_mulch", at, 0.8)
	if not _events:
		_hint({"kind": kind, "actor": Net.local_peer_id(), "at": at, "dir": dir, "width": (Constants.BAG_RADIUS if kind == "bag" else 0.8) * 2.0, "cells": 0, "moved": units})
	await _quiet()
	var after: Dictionary = _motion.call("stats")
	var redirected := int(after["sink_redirects"]) - int(before["sink_redirects"])
	var overdrawn := int(after["overdrawn"]) - int(before["overdrawn"])
	var left := int(_field.call("units_within_world", at, Constants.BAG_RADIUS))
	_quiescence(key + "_settled")
	_note(key, "%s %d units at %s (%d left, %d in flight then): %d leaves went in from the air, %d launches took leaves their cell did not show yet, conservation breaks %d, pops %d, max step so far %.3f m" % [kind, units, spot, left, in_flight, redirected, overdrawn, _conservation_bad - bad_before, int(after["pops"]) - int(before["pops"]), float(after["max_step"])])
	_checks[key] = redirected > 0 and overdrawn == 0 and left < units and _conservation_bad == bad_before and int(after["pops"]) == int(before["pops"]) and bool(_checks[key + "_settled"])
	_checks.erase(key + "_settled")


## The cell most units are still flying into (from the motion layer's ledger).
func _incoming_spot() -> Vector3:
	var ledger: Dictionary = _motion.call("ledger")
	var best := -1
	var most := 0
	for index: int in ledger:
		if int(ledger[index]) > most:
			most = int(ledger[index])
			best = index
	var width := int(_field.get("grid_width"))
	if best < 0:
		return Vector3.INF
	return _view.call("cell_center_world", Vector2i(best % width, best / width))


func _scatter_check(lot: Node3D) -> void:
	_motion.call("set_trace", true)
	var at := lot.global_position + Vector3(6.0, 0.1, 10.0)
	var me := _own_player()
	_move_to(at - Vector3(3.0, 0.0, 0.0), -PI * 0.5)
	await _ticks(2)
	if _shots != "":
		_film("burst_bag", at - Vector3(3.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0))
	var lot_density := float(int(_field.get("grid_width")) * int(_field.get("grid_depth")) * int(_field.get("INITIAL_DENSITY")))
	var whole := float(Balance.CREDITS_PER_1_PERCENT_LOT_CLEANUP) * 100.0
	# About 40 units a cell over a 1 m radius.
	var dollars := maxi(1, int(40.0 * 13.0 * whole / lot_density))
	_field.call("host_scatter", at, 1.0, dollars)
	if not _events:
		_hint({"kind": "scatter", "actor": 0, "at": at, "dir": Vector3.ZERO, "width": 2.0, "cells": 0, "moved": 500})
	await _seconds(1.8)
	var trace: Dictionary = _motion.call("trace")
	var count := 0
	var far := 0.0
	var spread := 0.0
	var high := 0.0
	for entry: Dictionary in trace["finished"]:
		if str(entry["kind"]) != "scatter":
			continue
		count += 1
		far = maxf(far, (entry["start"] as Vector3).distance_to(at))
		var end: Vector3 = entry["end"]
		spread += Vector2(end.x - at.x, end.z - at.z).length()
		high = maxf(high, float(entry.get("peak", 0.0)) - at.y)
	spread /= float(maxi(count, 1))
	# A fountain: the leaves go up well above the mouth and come down spread round it.
	_note("scatter", "%d leaves came out of the burst bag, farthest start %.2f m from it, landed %.2f m out on average, highest %.2f m up (me at %s)" % [count, far, spread, high, me.global_position])
	_checks["scatter"] = count >= 4 and far <= 0.6 and spread >= 0.25 and high >= 0.5


func _resync_check(lot: Node3D) -> void:
	var before: Dictionary = _motion.call("stats")
	var view_before := int((_view.call("stats") as Dictionary)["morph_units"])
	# About 50 flakes' worth over ten cells nobody stroked.
	var base := _cell_near(lot.global_position + Vector3(-12.0, 0.1, -12.0))
	for index: int in 10:
		_field.call("_add_density", base.x + index, base.y, 110)
	await _seconds(1.5)
	var after: Dictionary = _motion.call("stats")
	var view_after := int((_view.call("stats") as Dictionary)["morph_units"])
	var drops := int(after["drops"]) - int(before["drops"])
	_note("resync_small", "a small unexplained change made %d dropping leaves, view morphed %d units" % [drops, view_after - view_before])
	_checks["resync_small"] = drops > 0 and view_after == view_before
	# About 2,000 flakes' worth: morphed by the view.
	var big := _cell_near(lot.global_position + Vector3(4.0, 0.1, -16.0))
	for dz: int in 20:
		for dx: int in 20:
			_field.call("_add_density", big.x + dx, big.y + dz, 110)
	await _seconds(1.5)
	var later: Dictionary = _motion.call("stats")
	var view_later := int((_view.call("stats") as Dictionary)["morph_units"])
	var morphed := int(later["resyncs_morphed"]) - int(after["resyncs_morphed"])
	_note("resync_big", "a big unexplained change: morphed batches %d, view morphed %d units, new drops %d" % [morphed, view_later - view_after, int(later["drops"]) - int(after["drops"])])
	_checks["resync_big"] = morphed > 0 and view_later > view_after
	await _quiet()


func _hard_check_run(lot: Node3D) -> void:
	# Leaves in the air when the reset lands.
	var strip := _find_strip(lot, Vector3(1.0, 0.0, 0.0))
	if strip == Vector3.INF:
		strip = lot.global_position + Vector3(-10.0, 0.1, 4.0)
	_hard_check = {"armed": true}
	_rpc_arm_hard.rpc()
	var stand := strip - Vector3(1.5, 0.0, 0.0)
	_move_to(stand, -PI * 0.5)
	await _ticks(1)
	_bite(stand, Vector3(1.0, 0.0, 0.0), 0)
	await _seconds(0.25)
	var flying := int(_motion.call("stats")["movers_alive"])
	# The client: a snapshot (a join or a resync). Here: the field's reset signal, or
	# every chunk at once (a new field, before raking:1).
	for peer: int in Net.peer_ids():
		if peer != Net.local_peer_id():
			_field.call("_send_snapshot", peer, true)
	if _field.has_signal("field_reset"):
		_field.emit_signal("field_reset", true)
	var changed_signal := "leaves_changed" if _field.has_signal("leaves_changed") else "chunk_changed"
	for chunk_index: int in int(_field.call("chunk_count")):
		_field.emit_signal(changed_signal, chunk_index)
	var waited := 0.0
	while not bool(_hard_check.get("done", false)) and waited < 1.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	_note("hard_reset", "%d leaves in the air; after the reset %s movers, %s cells off" % [flying, _hard_check.get("movers", "?"), _hard_check.get("wrong", "?")])
	_checks["hard_reset"] = bool(_hard_check.get("done", false)) and int(_hard_check.get("movers", -1)) == 0 and int(_hard_check.get("wrong", -1)) == 0 and flying > 0
	await _quiet()


func _load_check(lot: Node3D, limit: int, seconds: float, key: String) -> void:
	_motion.call("set_pool_limit", limit)
	var bad_before := _conservation_bad
	var pops_before := int(_motion.call("stats")["pops"])
	var rakers: Array[Vector3] = []
	for index: int in LOAD_RAKERS + LOAD_HANDS:
		rakers.append(lot.global_position + Vector3(-16.0 + float(index % 3) * 10.0, 0.2, -10.0 + float(index / 3) * 14.0))
	var started := Time.get_ticks_msec()
	var strokes := 0
	var peak := 0
	var t := 0.0
	var next: Array[float] = []
	for index: int in rakers.size():
		next.append(float(index) * 0.05)
	while t < seconds:
		for index: int in rakers.size():
			if t < next[index]:
				continue
			var hand := index >= LOAD_RAKERS
			var count := strokes + index
			var at: Vector3 = rakers[index] + Vector3(float(count % 16) * 0.5, 0.0, float((count / 16) % 4) * 3.0)
			var dir := Vector3(1.0, 0.0, 0.0)
			var strength := Constants.RAKE_STRENGTH * (0.7 if hand else 1.0)
			# Contract C1: hired hand N is actor 1000 + N (raking:4's RAKE_ACTOR_HAND_BASE).
			var actor := 1000 + index if hand else 100 + index
			if _events:
				_field.call("host_hand_rake", at, dir, 0.7 if hand else 1.0, actor)
			else:
				_field.call("_stroke_cells", at, dir, Constants.RAKE_WIDTH, strength, Constants.RAKE_STROKE_CELLS)
				_hint({"kind": "crew_rake" if hand else "rake", "actor": actor, "at": at, "dir": dir, "width": Constants.RAKE_WIDTH, "cells": Constants.RAKE_STROKE_CELLS, "moved": 1500})
			next[index] = t + (0.8 if hand else 0.3)
			strokes += 1
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if int(t * 60.0) % 6 == 0:
			peak = maxi(peak, int(_motion.call("stats")["movers_alive"]))
	var stats: Dictionary = _motion.call("stats")
	var pool := int(stats["pool_limit"])
	# The books must balance through it, full pool or not (once it settles, too).
	await _quiet()
	var bad := _conservation_bad - bad_before
	var wrong := 0
	var grid := Vector2i(int(_field.get("grid_width")), int(_field.get("grid_depth")))
	for z: int in grid.y:
		for x: int in grid.x:
			if int(_view.call("displayed_units", Vector2i(x, z))) != int(_field.call("density_at_cell", x, z)):
				wrong += 1
	_note(key, "%d strokes in %.0f s: movers peak %d of %d, pops %d, max step %.3f m, sim %.2f ms avg %.2f ms p99, perf scale %.2f, pool overflow morphed %d units, conservation breaks %d, %d cells off after, view rebuild peak %.2f ms (wall %.1f s)" % [strokes, seconds, peak, pool, int(stats["pops"]) - pops_before, float(stats["max_step"]), float(stats["sim_ms_avg"]), float(stats["sim_ms_p99"]), float(stats["perf_scale"]), int(stats["morph_units"]), bad, wrong, float((_view.call("stats") as Dictionary).get("rebuild_ms_peak", 0.0)), float(Time.get_ticks_msec() - started) / 1000.0])
	_checks[key] = peak > 0 and peak <= pool and int(stats["pops"]) == pops_before and float(stats["max_step"]) <= Constants.LEAF_MAX_STEP + 0.001 and float(stats["sim_ms_avg"]) < 8.0 and bad == 0 and wrong == 0


## Waits until nothing moves (and a little longer), at most a few seconds.
func _quiet() -> void:
	var waited := 0.0
	while waited < 6.0:
		await _seconds(0.25)
		waited += 0.25
		var stats: Dictionary = _motion.call("stats")
		if int(stats["movers_alive"]) == 0 and int((_view.call("stats") as Dictionary).get("fading", 0)) == 0 and waited >= QUIET_SECONDS:
			return


# ---- the client's half

@rpc("authority", "call_remote", "reliable")
func _rpc_arm_hard() -> void:
	_hard_check = {"armed": true}


@rpc("authority", "call_remote", "reliable")
func _rpc_final() -> void:
	_finish_client()


func _finish_client() -> void:
	await _quiet()
	_quiescence("quiescence")
	var stats: Dictionary = _motion.call("stats") if _motion != null else {}
	var checks := {
		"conservation": _conservation_bad == 0 and _conservation_samples > 50,
		"quiescence": bool(_checks.get("quiescence", false)),
		"hard_reset": bool(_hard_check.get("done", false)) and int(_hard_check.get("movers", -1)) == 0 and int(_hard_check.get("wrong", -1)) == 0,
		"no_pops": int(stats.get("pops", 1)) == 0,
		"no_snaps": int(stats.get("snaps", 1)) == 0 and float(stats.get("max_handoff", 1.0)) <= 0.02,
		"max_step": float(stats.get("max_step", 9.0)) <= Constants.LEAF_MAX_STEP + 0.001,
		"animated": int(stats.get("landed", 0)) > 50,
	}
	var bad_log := 0
	for entry: Dictionary in _view.call("flake_log"):
		if not ALLOWED_LOG.has(str(entry["what"])):
			bad_log += 1
	checks["flake_log"] = bad_log == 0
	var report := {"checks": checks, "notes": _notes.duplicate(), "motion": stats, "conservation_samples": _conservation_samples, "conservation_first": _conservation_first, "hard": _hard_check.duplicate()}
	result = report.duplicate()
	result["done"] = true
	print("[LeafMotionTest] client %s" % JSON.stringify(checks))
	_rpc_client_report.rpc_id(1, report)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_client_report(report: Dictionary) -> void:
	if Net.is_host():
		_client_report = report


# ---- frame sequences (windowed, --leaf-motion-shots)

## Films a moment in slow motion from the side and in first person: frames 1/30 s
## apart for 0.4 s, then 0.45, 0.6 and 0.9 s, from the side; first person at 0,
## 0.08, 0.16, 0.24, 0.32, 0.45, 0.6, 0.9 s.
func _film(label: String, stand: Vector3, dir: Vector3, at_bite: bool = false) -> void:
	if _shots == "":
		return
	_bite_clock = -1.0
	DirAccess.make_dir_recursive_absolute(_shots)
	var me := _own_player()
	me.set("head_pitch", -0.62)
	if _side == null:
		_side = Camera3D.new()
		_side.name = "LeafShotsSide"
		_side.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		_side.fov = 50.0
		add_child(_side)
	var focus := stand + dir * 2.4
	focus.y = float(_view.call("surface_y", Vector2(focus.x, focus.z))) + 0.15
	var side := dir.cross(Vector3.UP).normalized()
	_side.look_at_from_position(focus + side * 3.6 + Vector3(0.0, 1.0, 0.0) - dir * 0.4, focus, Vector3.UP)
	var first := _own_camera()
	var times: Array[float] = []
	for index: int in 13:
		times.append(float(index) / 30.0)
	times.append_array([0.45, 0.6, 0.9])
	var fp_times: Array[float] = [0.0, 0.08, 0.16, 0.24, 0.32, 0.45, 0.6, 0.9]
	Engine.time_scale = 0.05
	var t0 := float(_motion.call("clock"))
	if at_bite:
		while _bite_clock < 0.0:
			await get_tree().process_frame
		t0 = _bite_clock
	var shot := 0
	var all: Array = []
	for t: float in times:
		all.append([t, "side"])
	for t: float in fp_times:
		all.append([t + 0.001, "fp"])
	all.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for entry: Array in all:
		while float(_motion.call("clock")) - t0 < float(entry[0]):
			await get_tree().process_frame
		var camera: Camera3D = _side if str(entry[1]) == "side" else first
		if camera == null:
			continue
		camera.current = true
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var path := "%s/%s_%s_%02d_%03dms.png" % [_shots, label, entry[1], shot, int(round(float(entry[0]) * 1000.0))]
		get_viewport().get_texture().get_image().save_png(path)
		shot += 1
	if first != null:
		first.current = true
	Engine.time_scale = 1.0


# ---- helpers

func _find_strip(lot: Node3D, dir: Vector3) -> Vector3:
	var side := dir.cross(Vector3.UP).normalized()
	for a: float in [-6.0, -10.0, 2.0, 6.0, -14.0, 10.0, -2.0]:
		for b: float in [-15.0, -9.0, 3.0, 9.0, -3.0]:
			var origin := lot.global_position + side * a - dir * b + Vector3(0.0, 0.1, 0.0)
			var fine := true
			for step: int in 14:
				for lateral: float in [-1.0, 0.0, 1.0]:
					var spot := origin + dir * (float(step) * 0.5) + side * lateral
					var density := int(_field.call("sample_world", spot))
					if density < 36 or density > 120:
						fine = false
			if fine:
				return origin
	return Vector3.INF


func _pile_near(around: Vector3, dir: Vector3) -> Vector3:
	var best := Vector3.INF
	var most := 0
	for ahead: float in [-1.0, -0.5, 0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0]:
		var at := around + dir * ahead
		var units := int(_field.call("units_within_world", at, Constants.PILE_HIDE_RADIUS))
		if units > most:
			most = units
			best = at
	return best


func _cell_near(world: Vector3) -> Vector2i:
	return _view.call("cell_of", world)


func _grab(item: Node3D) -> void:
	if item == null:
		return
	var me := _own_player()
	if int(item.get("held_by")) == Net.local_peer_id():
		return
	# Diving into a pile pockets what you held: draw it again.
	if "pocketed_by" in item and int(item.get("pocketed_by")) == Net.local_peer_id():
		var hotbar := get_tree().get_first_node_in_group("hotbar")
		if hotbar != null:
			hotbar.call("request_select", int(item.get("pocket_slot")))
			await _ticks(4)
			return
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


func _seconds(count: float) -> void:
	await get_tree().create_timer(count).timeout


func _ticks(count: int) -> void:
	for _tick: int in count:
		await get_tree().physics_frame


func _held_kind() -> String:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if int(node.get("held_by")) == Net.local_peer_id():
			return str(node.get("kind"))
	return ""


func _own_player() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as Node3D
	return null


func _own_camera() -> Camera3D:
	var player := _own_player()
	if player == null:
		return null
	return player.get_node_or_null("Visual/Head/FirstPerson") as Camera3D


func _prop(kind: String) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) == kind and not node.is_queued_for_deletion():
			return node as Node3D
	return null
