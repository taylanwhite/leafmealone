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
## Scenarios with a second player in them: alone, they must say so; with the
## CI's client (a friend who plays) they must get there.
const TWO_PLAYER_SCENARIOS: Array[String] = ["annex_visit", "annex_heist_seen", "cite_rescue", "van_unbuckle", "two_caught", "two_caught_far", "recatch"]
## record_stop returns at once: the files are written on the recorder's thread.
const STOP_MAX_MS: float = 50.0
## cite_rescue: the friend within this of your line to the NICE BOY is behind his body.
const RESCUE_SHIELD_METERS: float = 0.45
## lunge: the wind-up must start this soon after the scenario returns.
const LUNGE_WINDUP_WITHIN: float = 1.2
## How long the two-player section waits for CI's client (the friend) to join.
const FRIEND_WAIT_SECONDS: float = 30.0
## The client: at least this many of the host's resets must reach it, each
## leaving its caption stack empty (the three two-player moments and their resets).
const CLIENT_MIN_RESETS: int = 3
## tools:crew: the crew bot this test launches (tools/play.ps1 -Bots names them
## Bot1..Bot3), how long it gets to boot and join, how long to take up the rake
## and rake, and how many of its strokes must move leaves.
const CREW_BOT_NAME: String = "Bot1"
const CREW_JOIN_SECONDS: float = 45.0
const CREW_WORK_SECONDS: float = 70.0
const CREW_MIN_STROKES: int = 3
## The host steps this far back (m) from the rake it set down and stands there
## with empty hands: inside bot_job.gd's RAKE_DEFER_METERS, so the bot leaves the
## rake to the host for RAKE_DEFER_SECONDS and then takes it up.
const CREW_STEP_BACK: float = 8.0
## The bot may take the rake no sooner than RAKE_DEFER_SECONDS after it joined,
## less this (s): the 0.25 s poll. Real time since the join is measured, and the
## bot's own clock (which times the wait) never runs ahead of real time.
const CREW_DEFER_SLACK: float = 0.5

static var result: Dictionary = {}

var _scenarios: _ScenariosScript
## Client side: resets seen, and the most caption lines left right after one.
var _resets: int = 0
var _lines_after_reset: int = 0


func _ready() -> void:
	if not Net.is_host():
		# CI's client runs this node too (Extra): the host's reset must clear this
		# screen as well. Scenarios (added first, so called first) clears; this checks.
		add_to_group("scenario_listeners")
		_report_client()
		return
	_run()


## Client: called right after the Scenarios node's own on_scenario_reset (tree order).
func on_scenario_reset() -> void:
	_resets += 1
	_lines_after_reset = maxi(_lines_after_reset, _caption_lines())
	_report_client()


func _report_client() -> void:
	result = {"ok": _resets >= CLIENT_MIN_RESETS and _lines_after_reset == 0, "resets": _resets, "lines_after_reset": _lines_after_reset}
	if not bool(result["ok"]):
		result["error"] = "client: %d resets reached it (at least %d), %d caption lines left after one" % [_resets, CLIENT_MIN_RESETS, _lines_after_reset]


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
		# Lined up on a parked car with a load in the bed (driving C3's crash moment).
		var lined: Dictionary = await _scenarios.run("crash")
		reached["crash"] = _check(lined, chefty != null and int(chefty.call("driver")) == me and int(chefty.call("bag_count")) > 0 and float(chefty.call("speed")) < 0.5, "driver %d, %d bags" % [int(chefty.call("driver")) if chefty != null else 0, int(chefty.call("bag_count")) if chefty != null else 0], problems)
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
	# A label with a digit after an underscore keeps its name (R2b tools: it was rec_raid_arrive_2_1p).
	var started: Dictionary = recorder.call("start", base, CLIP_FPS, "raid_arrive2_1p")
	await get_tree().create_timer(CLIP_SECONDS).timeout
	# record_stop only closes the take: the files are written on a thread while the game runs.
	var stop_at := Time.get_ticks_usec()
	var clip: Dictionary = recorder.call("stop")
	var stop_ms := float(Time.get_ticks_usec() - stop_at) / 1000.0
	var frames_during := Engine.get_process_frames()
	await recorder.wait_written()
	frames_during = Engine.get_process_frames() - frames_during
	var arrived := _phase(director) == 2 and not get_tree().get_nodes_in_group("crew").is_empty()
	reached["raid_arrive"] = _check(out, arrives_in > 0.0 and arrives_in <= _ScenariosScript.ARRIVE_LEAD_SECONDS + 0.3 and arrived, "arrival in %.2f s, then phase %d with %d NICE BOYS" % [arrives_in, _phase(director), get_tree().get_nodes_in_group("crew").size()], problems)
	var recording := _check_recording(started, clip, problems)
	recording["stop_ms"] = snappedf(stop_ms, 0.1)
	recording["frames_while_writing"] = frames_during
	recording["label_kept"] = str(clip.get("dir", "")).ends_with("rec_raid_arrive2_1p")
	if stop_ms > STOP_MAX_MS or not bool(recording["label_kept"]) or clip.has("writing"):
		problems.append("recorder: stop took %.1f ms (at most %.0f), dir %s, still writing %s" % [stop_ms, STOP_MAX_MS, clip.get("dir", ""), clip.has("writing")])
	reached["tools_units"] = _check_units(problems)

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
	# CI's client is the friend: wait for it, and report whether it came, so CI
	# fails a run where it never did instead of passing on the refusals alone.
	var friend_wait := 0.0
	while int(_scenarios.call("_friend_id")) == 0 and friend_wait < FRIEND_WAIT_SECONDS:
		await get_tree().create_timer(0.25).timeout
		friend_wait += 0.25
	var with_friend := int(_scenarios.call("_friend_id")) != 0
	print("[PlaytestToolsTest] friend: %s (waited %.2f s)" % [with_friend, friend_wait])
	for name: String in _ScenariosScript.NAMES:
		if reached.has(name) or name in ["drive", "border_return"]:
			continue
		var probe := "_reached_%s" % name
		if not _scenarios.has_method(probe):
			continue
		out = await _scenarios.run(name)
		# Moments with a friend in them (annex_visit, cite_rescue, van_unbuckle) must
		# say they need one when there's nobody else (R2 integration: chunks 2 and 4
		# added two more).
		if name in TWO_PLAYER_SCENARIOS and not with_friend:
			var error := str(out.get("error", ""))
			reached[name] = not bool(out.get("ok", true)) and error.contains("second player") and error.contains("-Friend")
			print("[PlaytestToolsTest] %s alone: %s" % [name, out.get("error", "no error")])
			if not reached[name]:
				problems.append("%s didn't say it needs a second player: %s" % [name, out])
			continue
		var line := "%s reached: %s" % [name, out.get("note", "")]
		var extra_ok := true
		if name == "lunge":
			# R2b tools: he's on his feet already, and winds up promptly.
			var waited_for := await _windup_within(LUNGE_WINDUP_WITHIN)
			extra_ok = waited_for >= 0.0
			line += "; wind-up after %.2f s" % waited_for
		elif name == "cite_rescue":
			# The friend is behind the NICE BOY from where you stand, inside his
			# shoulders' width of your line: a throw at him can't reach them first.
			var behind := _friend_behind_crew()
			extra_ok = behind.x > 0.0 and behind.y < RESCUE_SHIELD_METERS
			line += "; the friend is %.2f m behind him, %.2f m off your line" % [behind.x, behind.y]
		reached[name] = _check(out, bool(_scenarios.call(probe)) and extra_ok, line, problems)
		if name in TWO_PLAYER_SCENARIOS:
			# The next scenario starts clean: nobody seated, caught or held anywhere.
			out = await _scenarios.run("store")
			var friend := int(_scenarios.call("_friend_id"))
			var shuttle := get_tree().get_first_node_in_group("nice_shuttle")
			var friend_seated := shuttle != null and not (shuttle.call("seat_info", friend) as Dictionary).is_empty()
			var friend_stage := int(get_tree().get_first_node_in_group("nice_encounter").call("stage_of", friend))
			var lines := _caption_lines()
			var clean := not friend_seated and friend_stage == 0 and not bool(director.call("is_captured", friend)) and lines == 0
			reached[name + "_reset"] = clean
			print("[PlaytestToolsTest] after %s, reset: seated %s, stage %d, captions %d" % [name, friend_seated, friend_stage, lines])
			if not clean:
				problems.append("after %s the reset left: seated %s, stage %d, caught %s, %d caption lines" % [name, friend_seated, friend_stage, director.call("is_captured", friend), lines])
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

	# tools:crew: a bot teammate (tools/play.ps1 -Bots) joins and works the job.
	var crew := await _check_crew_bot(problems)

	# Leave the session as it was: no raid, nobody in the crossing.
	await _scenarios.reset()
	_finish(problems.is_empty(), {"scenarios": reached, "recording": recording, "friend": with_friend, "crew": crew}, problems)


## tools:crew: a crew bot is its own Godot process, launched the way tools/play.ps1
## -Bots launches one (--bot-crew, the session's port, named Bot1). It must join
## this session and work the job: walk to the rake the host just set down on
## untouched leaves, take it up, and rake (strokes of its own that move leaves).
## The bot is killed afterwards; its --run-seconds is a ceiling if this run dies.
func _check_crew_bot(problems: Array[String]) -> Dictionary:
	var out: Dictionary = await _scenarios.run("rake_fresh")
	var rake: Node = _own_player().call("_held_prop") if bool(out.get("ok", false)) else null
	if rake == null:
		problems.append("crew: rake_fresh gave no rake to set down")
		return {"ok": false}
	rake.call("request_drop")
	# Then step back along the strip: a crew bot leaves a rake to a person nearby
	# for a while (net/dev/bot_job.gd _mine_to_take), then takes it up.
	await get_tree().create_timer(0.5).timeout
	var me := _own_player()
	me.global_position -= Vector3(-me.global_basis.z.x, 0.0, -me.global_basis.z.z).normalized() * CREW_STEP_BACK
	var log_path := ProjectSettings.globalize_path("user://playtest_crew_bot_%d.log" % Net.listen_port())
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--log-file", log_path, "--",
		"--join=127.0.0.1", "--port=%d" % Net.listen_port(), "--no-steam", "--name=" + CREW_BOT_NAME, "--bot", "--bot-crew",
		"--run-seconds=%d" % int(CREW_JOIN_SECONDS + CREW_WORK_SECONDS + 20.0)])
	var pid := OS.create_process(OS.get_executable_path(), args)
	var report := {"pid_ok": pid > 0, "joined_after": -1.0, "took_rake_after": -1.0, "rake_strokes": 0, "moved": 0}
	if pid <= 0:
		problems.append("crew: couldn't launch a bot process")
		report["ok"] = false
		return report
	var bot := 0
	var waited := 0.0
	while bot == 0 and waited < CREW_JOIN_SECONDS:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
		for peer_id: int in Net.peer_ids():
			if Net.player_name(peer_id) == CREW_BOT_NAME:
				bot = peer_id
	report["joined_after"] = waited if bot != 0 else -1.0
	var joined_ms := Time.get_ticks_msec()
	var tally := {"strokes": 0, "moved": 0}
	var on_stroke := func(ev: Dictionary) -> void:
		if int(ev.get("actor", 0)) == bot and str(ev.get("kind")) == "rake" and int(ev.get("moved", 0)) > 0:
			tally["strokes"] = int(tally["strokes"]) + 1
			tally["moved"] = int(tally["moved"]) + int(ev.get("moved", 0))
	_field().connect("stroke_event", on_stroke)
	var worked := 0.0
	while bot != 0 and worked < CREW_WORK_SECONDS and int(tally["strokes"]) < CREW_MIN_STROKES:
		await get_tree().create_timer(0.25).timeout
		worked += 0.25
		if float(report["took_rake_after"]) < 0.0 and is_instance_valid(rake) and int(rake.get("held_by")) == bot:
			report["took_rake_after"] = worked
			report["took_rake_real"] = float(Time.get_ticks_msec() - joined_ms) / 1000.0
		if fmod(worked, 5.0) < 0.01:
			print("[PlaytestToolsTest] crew bot at %.0f s: %s" % [worked, _crew_bot_where(bot, rake)])
	report["last_seen"] = _crew_bot_where(bot, rake)
	_field().disconnect("stroke_event", on_stroke)
	OS.kill(pid)
	report["rake_strokes"] = tally["strokes"]
	report["moved"] = tally["moved"]
	# The bot said it plays as one of the crew (its --bot-crew reached net/dev/bot.gd).
	var said := FileAccess.get_file_as_string(log_path).contains("as a crew member")
	report["crew_mode"] = said
	# It left the rake to the host standing near it with empty hands for the whole
	# wait first (net/dev/bot_job.gd _mine_to_take): a bot that took it at once fails.
	var defer: float = load("res://net/dev/bot_job.gd").RAKE_DEFER_SECONDS
	var waited_out := float(report.get("took_rake_real", -1.0)) >= defer - CREW_DEFER_SLACK
	report["waited_out_defer"] = waited_out
	var ok := bot != 0 and float(report["took_rake_after"]) >= 0.0 and waited_out and int(tally["strokes"]) >= CREW_MIN_STROKES and said
	report["ok"] = ok
	print("[PlaytestToolsTest] crew bot: %s %s" % ["ok" if ok else "FAIL", report])
	if not ok:
		problems.append("crew bot: %s (log %s)" % [report, log_path])
	return report


## Where the crew bot and the rake are, for the report.
func _crew_bot_where(bot: int, rake: Node) -> String:
	var body: Node3D = null
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(bot):
			body = node as Node3D
	var at := body.global_position if body != null else Vector3.INF
	var rake_at := (rake as Node3D).global_position if is_instance_valid(rake) else Vector3.INF
	return "zone %s at %s, rake at %s held by %d loose %s" % [Net.Zone.keys()[Net.player_zone(bot)] if bot != 0 else "-", at.snappedf(0.1), rake_at.snappedf(0.1), int(rake.get("held_by")) if is_instance_valid(rake) else -1, bool(rake.call("is_loose")) if is_instance_valid(rake) else false]


## Seconds until a NICE BOY winds up at you (the Encounter's WINDUP or a grab
## on you), or -1 when none comes within `limit`.
func _windup_within(limit: float) -> float:
	var encounter := get_tree().get_first_node_in_group("nice_encounter")
	var me := Net.local_peer_id()
	var waited := 0.0
	while waited <= limit:
		if encounter != null and (int(encounter.call("stage_of", me)) >= 1 or bool(encounter.call("is_grabbed", me))):
			return waited
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	return -1.0


## Where the cited friend stands from the NICE BOY, along your line to him (x,
## positive: beyond him) and across it (y, meters off the line).
func _friend_behind_crew() -> Vector2:
	var friend := _scenarios.call("_other_player") as Node3D
	var crew := get_tree().get_nodes_in_group("crew")
	if friend == null or crew.is_empty():
		return Vector2(-1.0, INF)
	var me := _own_player().global_position
	var him: Vector3 = _scenarios.call("_drawn_at", crew[0])
	var them: Vector3 = _scenarios.call("_drawn_at", friend)
	var line := Vector3(him.x - me.x, 0.0, him.z - me.z).normalized()
	var off := Vector3(them.x - him.x, 0.0, them.z - him.z)
	return Vector2(line.dot(off), (off - line * line.dot(off)).length())


## Raid lines still on screen (the caption stack).
func _caption_lines() -> int:
	var stack := get_tree().get_first_node_in_group("caption_stack")
	return (stack.call("shown_lines") as Array).size() if stack != null else 0


## The playtest tools' own small rules (R2b tools).
func _check_units(problems: Array[String]) -> bool:
	var failures: Array[String] = []
	if _RecorderScript.clean_label("pile2_1p") != "pile2_1p" or _RecorderScript.clean_label(" Hide Bin.2 ") != "hide_bin_2":
		failures.append("labels: %s, %s" % [_RecorderScript.clean_label("pile2_1p"), _RecorderScript.clean_label(" Hide Bin.2 ")])
	# A big look is eased over frames, none of them over LOOK_EASE_ABOVE, adding up exactly.
	var parts := _RemotePlayScript.look_steps(Vector2(600.0, -90.0))
	var total := Vector2.ZERO
	var biggest := 0.0
	for part: Vector2 in parts:
		total += part
		biggest = maxf(biggest, part.length())
	if parts.size() < 10 or biggest > _RemotePlayScript.LOOK_EASE_ABOVE or not total.is_equal_approx(Vector2(600.0, -90.0)) or _RemotePlayScript.look_steps(Vector2(40.0, 0.0)).size() != 1:
		failures.append("look steps: %d parts, biggest %.1f px, total %s" % [parts.size(), biggest, total])
	# The spectator never films a pair lined up along its view: a yaw straight down
	# their axis turns side-on, a side-on one stays.
	var axis := Vector3(0.0, 0.0, 1.0)
	var lined := _RemotePlayScript.side_on_yaw(0.0, axis)
	var side := _RemotePlayScript.side_on_yaw(deg_to_rad(90.0), axis)
	if absf(Vector3(sin(lined), 0.0, cos(lined)).dot(axis)) > 0.01 or absf(side - deg_to_rad(90.0)) > 0.001:
		failures.append("side-on yaw: %.1f deg for a lined-up pair, %.1f for a side-on one" % [rad_to_deg(lined), rad_to_deg(side)])
	if _RemotePlayScript.state_value({"zone": "LOT", "annex": {"stage": "inside"}}, "annex.stage") != "inside" or _RemotePlayScript.state_value({}, "raid") != "":
		failures.append("until's dotted fields")
	print("[PlaytestToolsTest] tools units: %s" % ("ok" if failures.is_empty() else ", ".join(failures)))
	if not failures.is_empty():
		problems.append("tools units: %s" % ", ".join(failures))
	return failures.is_empty()


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
