extends Node

## Authority: host. --playtest-tools-test (docs/PLAYTEST.md, CI port 7820): every
## scenario jump reaches its moment through the real game code, and the
## recorder writes evenly spaced frames, a contact sheet and an events log that
## saw the raid happen. Headless: the recorder draws stand-in frames there (no
## window), so this checks the timing, the files and the log, not the pictures;
## run it with --fixed-fps 30 (tools/ci_local.ps1's Engine args) so frames are
## evenly spaced in game time. Run it with --start-zone=lot --job-seed=777.

const _RecorderScript = preload("res://net/dev/recorder.gd")
const _HideSpot = preload("res://net/components/hide_spot.gd")
const _ScenariosScript = preload("res://net/dev/scenarios.gd")
const _RemotePlayScript = preload("res://net/dev/remote_play.gd")
## The test recording: this many seconds at this rate.
const CLIP_SECONDS: float = 3.0
const CLIP_FPS: float = 10.0
## How long a NICE BOY gets to catch someone standing still in front of him.
const CATCH_SECONDS: float = 8.0

static var result: Dictionary = {}

var _scenarios: _ScenariosScript


func _ready() -> void:
	if not Net.is_host():
		return
	_run()


func _run() -> void:
	var waited := 0.0
	while (_own_player() == null or get_tree().get_first_node_in_group("leaf_field") == null) and waited < 30.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	_scenarios = get_parent().get_node_or_null("Scenarios") as _ScenariosScript
	if _own_player() == null or _scenarios == null:
		_finish(false, {}, ["no player, yard or Scenarios node after %.0f s" % waited])
		return
	await get_tree().create_timer(1.0).timeout
	var problems: Array[String] = []
	var reached := {}
	var me := Net.local_peer_id()
	var director := get_tree().get_first_node_in_group("run_director")
	if bool(get_tree().get_first_node_in_group("world").call("is_town_map")):
		# The connected town (--town-map): the jump that needs it, into Chefty's driver's seat.
		var drove: Dictionary = await _scenarios.run("drive")
		var chefty := get_tree().get_first_node_in_group("chefty")
		reached["drive"] = _check(drove, chefty != null and int(chefty.call("driver")) == me, "driver %d" % (int(chefty.call("driver")) if chefty != null else 0), problems)
		var shopping: Dictionary = await _scenarios.run("store")
		reached["store"] = _check(shopping, _zone() == "STORE", "zone %s" % _zone(), problems)
		_finish(problems.is_empty(), {"scenarios": reached, "town_map": true}, problems)
		return

	var out: Dictionary = await _scenarios.run("rake_fresh")
	var ahead := _own_player().global_position + (-_own_player().global_basis.z) * 1.5
	reached["rake_fresh"] = _check(out, _held() == "rake" and _zone() == "LOT" and int(_field().call("sample_world", ahead)) >= 30, "holding %s in %s, %d leaves ahead" % [_held(), _zone(), int(_field().call("sample_world", ahead))], problems)

	out = await _scenarios.run("rake_pile")
	reached["rake_pile"] = _check(out, _held() == "rake" and bool(out.get("is_pile", false)), "holding %s, a pile of %s units ahead" % [_held(), str(out.get("pile_units", 0))], problems)

	out = await _scenarios.run("raid_warn")
	reached["raid_warn"] = _check(out, _phase(director) == 1 and bool(_scenarios.call("_reached_raid_warn")), "phase %d, facing the curb %s" % [_phase(director), _scenarios.call("_reached_raid_warn")], problems)

	# raid_arrive, recorded: the arrival must show up in the log, on evenly spaced frames.
	out = await _scenarios.run("raid_arrive")
	var arrives_in := float(out.get("arrives_in", -1.0))
	var recorder := _RecorderScript.new()
	recorder.name = "TestRecorder"
	recorder.set("state_source", func() -> Dictionary: return {"zone": _zone(), "held": _held()})
	add_child(recorder)
	var base := ProjectSettings.globalize_path("user://playtest_test_%d" % Net.listen_port())
	var started: Dictionary = recorder.call("start", base, CLIP_FPS, "raid_arrive")
	await get_tree().create_timer(CLIP_SECONDS).timeout
	var clip: Dictionary = recorder.call("stop")
	var arrived := _phase(director) == 2 and not get_tree().get_nodes_in_group("crew").is_empty()
	reached["raid_arrive"] = _check(out, arrives_in > 0.0 and arrives_in <= _ScenariosScript.ARRIVE_LEAD_SECONDS + 0.3 and arrived, "arrival in %.2f s, then phase %d with %d NICE BOYS" % [arrives_in, _phase(director), get_tree().get_nodes_in_group("crew").size()], problems)
	var recording := _check_recording(started, clip, problems)

	out = await _scenarios.run("caught")
	var chasing := _phase(director) == 2
	var caught := false
	var watched := 0.0
	while watched < CATCH_SECONDS and not caught:
		await get_tree().create_timer(0.25).timeout
		watched += 0.25
		caught = bool(director.call("is_captured", me))
	reached["caught"] = _check(out, chasing and caught, "chase %s, caught after %.2f s: %s" % [chasing, watched, caught], problems)

	out = await _scenarios.run("hide")
	var spot: Node = _own_player().call("_nearest_free_spot")
	var in_spot := false
	if spot != null:
		spot.call("request_enter")
		for _tick: int in 10:
			await get_tree().physics_frame
		in_spot = _HideSpot.spot_of(get_tree(), me) != null and bool(_own_player().call("is_hidden"))
	reached["hide"] = _check(out, _phase(director) == 1 and spot != null and in_spot, "warning %s, a spot in reach %s, hidden in it %s" % [_phase(director) == 1, spot != null, in_spot], problems)

	out = await _scenarios.run("store")
	reached["store"] = _check(out, _zone() == "STORE", "zone %s" % _zone(), problems)

	out = await _scenarios.run("van_ride")
	# The Courtesy Shuttle (nice_boys:4): buckled in at the yard's curb, about to leave.
	var seated := bool(_scenarios.call("_reached_van_ride"))
	reached["van_ride"] = _check(out, _zone() == "LOT" and seated, "zone %s, in a van seat %s" % [_zone(), seated], problems)
	for moment: String in ["van_seated", "van_straggler", "dropoff"]:
		out = await _scenarios.run(moment)
		reached[moment] = _check(out, bool(_scenarios.call("_reached_" + moment)), "reached %s" % moment, problems)

	# Every other scenario (the Annex's, and each R2 chunk's) says itself whether it
	# got there: scenarios.gd's _reached_<name>(). One that needs a second player
	# (annex_visit) must say so instead of pretending.
	for name: String in _ScenariosScript.NAMES:
		if reached.has(name) or name in ["drive", "border_return"]:
			continue
		var probe := "_reached_%s" % name
		if not _scenarios.has_method(probe):
			continue
		out = await _scenarios.run(name)
		if name == "annex_visit" and Net.peer_ids().size() < 2:
			reached[name] = not bool(out.get("ok", true)) and str(out.get("error", "")).contains("second player")
			print("[PlaytestToolsTest] annex_visit alone: %s" % out.get("error", "no error"))
			if not reached[name]:
				problems.append("annex_visit didn't say it needs a second player: %s" % out)
			continue
		reached[name] = _check(out, bool(_scenarios.call(probe)), "%s reached: %s" % [name, out.get("note", "")], problems)
	# The old name still lands at the Annex for one wave.
	out = await _scenarios.run("border_return")
	reached["border_return"] = _check(out, _zone() == "BORDER" and bool(_scenarios.call("_reached_annex")), "zone %s, %s" % [_zone(), str(out.get("note", ""))], problems)

	# drive needs the connected town; in this legacy world it must say so, not pretend.
	out = await _scenarios.run("drive")
	reached["drive_refuses_legacy"] = not bool(out.get("ok", true)) and str(out.get("error", "")).contains("--town-map")
	print("[PlaytestToolsTest] drive in the legacy world: %s" % out.get("error", "no error"))
	if not reached["drive_refuses_legacy"]:
		problems.append("drive didn't refuse the legacy world: %s" % out)

	# Remote play's cmd.json numbers arrive as floats: "follow <peer id>" must still name the peer.
	var parsed_steps: Variant = JSON.parse_string('[["follow", %d, 4, 1.6, 80]]' % me)
	var follow_word := _RemotePlayScript._word((parsed_steps as Array)[0][1])
	reached["follow_peer_id"] = follow_word == str(me)
	if not reached["follow_peer_id"]:
		problems.append("follow by peer id reads %s, not %d" % [follow_word, me])

	# Leave the session as it was: no raid, nobody in the crossing.
	await _scenarios.reset()
	_finish(problems.is_empty(), {"scenarios": reached, "recording": recording}, problems)


func _check(out: Dictionary, ok: bool, line: String, problems: Array[String]) -> bool:
	var name := str(out.get("scenario", "?"))
	var passed := ok and bool(out.get("ok", false))
	print("[PlaytestToolsTest] %s: %s (%s)%s" % [name, "ok" if passed else "FAIL", line, "" if bool(out.get("ok", false)) else " error: %s" % out.get("error", "")])
	if not passed:
		problems.append("%s: %s %s" % [name, line, out.get("error", "")])
	return passed


## The recording: frames at the asked rate, exactly evenly spaced in game time
## (with --fixed-fps), files on disk, and the arrival in its events.
func _check_recording(started: Dictionary, clip: Dictionary, problems: Array[String]) -> Dictionary:
	var report := {}
	if started.has("error") or clip.has("error"):
		problems.append("recorder: %s %s" % [started.get("error", ""), clip.get("error", "")])
		return {"ok": false}
	var spacing: Dictionary = clip.get("spacing", {})
	var frames := int(clip.get("frames", 0))
	var want := int(CLIP_SECONDS * float(clip.get("fps", CLIP_FPS)))
	var fixed := bool(clip.get("fixed_step", false))
	var even := bool(spacing.get("even", false)) and absf(float(spacing.get("mean", 0.0)) - 1.0 / float(clip.get("fps", CLIP_FPS))) < 0.001
	var files := FileAccess.file_exists(str(clip["sheet"])) and FileAccess.file_exists(str(clip["events_json"])) and FileAccess.file_exists(str(clip["dir"]).path_join("frame_000.png")) and FileAccess.file_exists(str(clip["dir"]).path_join("frame_%03d.png" % (frames - 1)))
	var sheet := Image.load_from_file(str(clip["sheet"])) if files else null
	var sheet_ok := sheet != null and sheet.get_width() <= 2048 and sheet.get_height() > 0
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(clip["events_json"]))) if files else null
	var kinds := {}
	var stamps_ok := false
	var misfiled: Array = []
	if typeof(parsed) == TYPE_DICTIONARY:
		for entry: Variant in (parsed as Dictionary).get("events", []):
			kinds[str((entry as Dictionary).get("kind"))] = true
		var listed: Array = (parsed as Dictionary).get("frames", [])
		stamps_ok = listed.size() == frames and not listed.is_empty() and (listed[0] as Dictionary).has("state") and (listed[0] as Dictionary).has("camera")
		misfiled = _misfiled_events(listed, float(clip.get("fps", CLIP_FPS)), int(clip.get("session_fixed_fps", 0)))
	# The crew ride in seated from the call (nice_boys:4): the van pulling up is the arrival.
	var saw_arrival := kinds.has("raid_phase") and (kinds.has("crew") or kinds.has("van_leg"))
	report = {"frames": frames, "want_about": want, "fixed_step": fixed, "spacing": spacing, "files": files, "sheet": sheet_ok, "stamps": stamps_ok, "saw_arrival": saw_arrival, "kinds": kinds.keys(), "misfiled_events": misfiled.slice(0, 6)}
	var ok := fixed and even and absi(frames - want) <= 2 and files and sheet_ok and stamps_ok and saw_arrival and misfiled.is_empty()
	report["ok"] = ok
	print("[PlaytestToolsTest] recorder: %s %s" % ["ok" if ok else "FAIL", report])
	if not fixed:
		problems.append("recorder: no fixed step (launch with --fixed-fps 30)")
	elif not ok:
		problems.append("recorder: %s" % report)
	return report


## Every event is filed under the first frame at or after it, and its time is a
## whole engine frame (a multiple of the fixed step): frame k holds events with
## t_{k-1} < t <= t_k (frame 0 only t = 0; the last frame also holds what fired
## up to record_stop, within one frame gap). Returns the ones that aren't.
func _misfiled_events(listed: Array, fps: float, step_fps: int) -> Array:
	var bad: Array = []
	for k: int in listed.size():
		var frame: Dictionary = listed[k]
		var t_k := float(frame["t"])
		var low := float(listed[k - 1]["t"]) if k > 0 else -0.0001
		var high := t_k + (1.0 / fps if k == listed.size() - 1 else 0.0)
		for entry: Dictionary in frame.get("events", []):
			var t := float(entry["t"])
			var whole := absf(t * float(step_fps) - round(t * float(step_fps))) < 0.01
			if (k == 0 and absf(t) > 0.0001) or (k > 0 and t <= low + 0.0001) or t > high + 0.0001 or not whole:
				bad.append({"frame": k, "frame_t": t_k, "kind": entry.get("kind"), "t": t})
	return bad


func _finish(ok: bool, details: Dictionary, problems: Array) -> void:
	result = {"ok": ok, "done": true}
	result.merge(details)
	if not problems.is_empty():
		result["error"] = "; ".join(problems)
	print("[PlaytestToolsTest] all ok: %s%s" % [ok, "" if problems.is_empty() else " (%s)" % "; ".join(problems)])


func _phase(director: Node) -> int:
	return int(director.call("phase")) if director != null else -1


func _zone() -> String:
	return Net.Zone.keys()[Net.player_zone(Net.local_peer_id())]


func _held() -> String:
	var held: Node = _own_player().call("_held_prop")
	return str(held.get("kind")) if held != null else ""


func _field() -> Node:
	return get_tree().get_first_node_in_group("leaf_field")


func _own_player() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as Node3D
	return null
