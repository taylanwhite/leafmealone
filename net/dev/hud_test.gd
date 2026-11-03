extends Node

## --hud-test (R2b hud, docs/GAME.md "What's on screen during the encounter";
## port 7834, host plus a Target client, both with --sim-lag=150 --hud-test).
## What's on screen while the NICE BOYS have you, checked in the running game:
##   free      on the yard and in control: no cinematic mode, the yard HUD up
##             (on both peers).
##   caught    the host catches the client (the real catch, over the network):
##             on the client the cinematic mode comes on, the yard HUD (job
##             panel, hotbar, goal line, cash rows, heat, clock) eases out within
##             R2B_HUD_FADE_OUT (+ slack) and never pops back while held, and no
##             interact prompt shows on any of those frames.
##   stack     on the held client: a spoken line lands with its sound (readable
##             within R2B_HUD_SUBTITLE_ONSET + a frame), shows over a quip and
##             the radio, at most R2B_HUD_CINEMATIC_LINES lines, low on the
##             screen, each on its soft plate.
##   back      let go (out of the van, out of the cohort): the HUD waits
##             R2B_HUD_RETURN_DELAY, then eases back in, with no frame popping.
##   once      on the host: a NICE BOY's line in plain view and far enough off is
##             a bubble and not a subtitle; up close it's a subtitle and not a
##             bubble. Each line is on screen exactly once.
##   clamp     a bubble over a head at the screen's edge glides back inside it,
##             and a long line wraps as a line (at most 3 rows), not a column.
##   tags      a name tag behind a wall fades out and comes back; two tags over
##             two heads show only the nearer; a NICE BOY sat in the van shows none.
##   R2c (docs/GAME.md "What's on screen, between the beats"):
##   grab      a friend the NICE BOYS have can't be grabbed (no "[E] Grab" for
##             nothing); free, they can.
##   apart     two bubbles at once don't touch; a narrow lens or a head a metre
##             off never makes a bubble line or a tag bigger than its cap.
##   held_seams  on the held client: spoken lines in a row with one on its way
##             out: never more than R2B_HUD_CINEMATIC_LINES drawn (the leaving one
##             counted), never one twice, the newest always on.
##   stack_seams  the same in the yard (CAPTION_STACK_MAX); a wrapped line is
##             balanced.
##   hedge     a hiding spot's leaves (no collider) hide a tag behind them.
##   back      also: a corner quip triggered while held waits, and plays after
##             (its line up in the corner).
##   bubble_gone  a bubble that's up goes once his head leaves the picture (not
##             pinned in a corner), and at once across a camera cut.
## Each step prints a [HudTest] line. The client reports its half by RPC.

const _HudMode = preload("res://ui/hud_mode.gd")
const _Overheads = preload("res://ui/overheads.gd")
const _Prompt = preload("res://ui/interaction_prompt.gd")
const _TextFit = preload("res://ui/text_fit.gd")
const _Strings = preload("res://ui/strings.gd")
const _QuipPlayer = preload("res://ui/quip_player.gd")
const CLIENT_WAIT_SECONDS: float = 30.0
const CAUGHT_WAIT_SECONDS: float = 15.0
const BACK_WAIT_SECONDS: float = 10.0
const REPORT_WAIT_SECONDS: float = 10.0
## Slack on the fades for frame timing (s).
const FADE_SLACK: float = 0.25
const CLEAR_METERS: float = 16.0
## Every step a passing run reports.
const STEPS: Array[String] = ["free_host", "free", "caught", "stack", "held_seams", "back", "once", "clamp", "tags", "grab", "apart", "stack_seams", "hedge", "bubble_gone"]
const LONG_LINE :="This yard was selected for a random friendliness check! Please remain delightful."

static var result: Dictionary = {}

var _started: bool = false
var _steps: Dictionary = {}
var _report: Dictionary = {}
var _phase: String = ""

## Client: what it saw, frame by frame, while caught and after.
var _seen_cinematic_at: float = INF
var _seen_hidden_at: float = INF
var _prompt_frames: int = 0
var _pop_frames: int = 0
var _free_at: float = INF
var _back_at: float = INF
var _early_frames: int = 0
var _last_alpha: float = 1.0
## Frames the prompt was drawn while still free in the caught phase (want > 0).
var _prompt_free_frames: int = 0
## Every HudMode reason seen while held.
var _reasons: Dictionary = {}
var _held_last: bool = false
## When this hold began (s), INF while free, and how much frame time has passed in it.
var _held_since: float = INF
var _held_for: float = 0.0
## R2c: a corner quip triggered while held was kept waiting.
var _quip_waited: bool = false
var _source: FakeSource = null


## A prompt source that always offers one, at the client's own feet: while held
## the prompt must stay down anyway.
class FakeSource extends Node:
	var at: Node3D

	func prompt() -> Dictionary:
		if at == null or not is_instance_valid(at):
			return {}
		# In front of the camera (R2c: a prompt whose spot is off screen isn't drawn).
		var camera := at.get_viewport().get_camera_3d()
		if camera != null:
			return {"text": "Test", "at": camera.global_position - camera.global_basis.z * 1.5 - camera.global_basis.y * 0.3}
		return {"text": "Test", "at": at.global_position + Vector3(0.0, 1.0, -0.8)}


## Whether the interaction prompt (ui/interaction_prompt.gd's Label3D) is drawn.
func _prompt_drawn() -> bool:
	var world := get_tree().get_first_node_in_group("world")
	var label := world.get_node_or_null("InteractionPrompt") as Label3D if world != null else null
	return label != null and label.is_visible_in_tree() and label.text != "" and label.transparency < 0.99


func _process(delta: float) -> void:
	if not _started and get_tree().get_first_node_in_group("world") != null and _me() != null and get_tree().get_first_node_in_group("job_lot") != null:
		_started = true
		if Net.is_host():
			_run_host()
	if not Net.is_host():
		_watch_client(delta)


# ---------------------------------------------------------------- client

func _ui() -> Node:
	return get_tree().get_first_node_in_group("game_ui")


func _alpha() -> float:
	var ui := _ui()
	return float(ui.call("yard_hud_alpha")) if ui != null and ui.has_method("yard_hud_alpha") else -1.0


## The client's frames while it's held and let go.
func _watch_client(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var why := _HudMode.reason(get_tree(), Net.local_peer_id())
	var alpha := _alpha()
	if _phase == "caught":
		if why != &"" and _seen_cinematic_at == INF:
			_seen_cinematic_at = now
		if _seen_cinematic_at != INF:
			if alpha <= 0.01 and _seen_hidden_at == INF:
				_seen_hidden_at = now
			# Once eased out, it stays out while you're held.
			if _seen_hidden_at != INF and alpha > 0.01 and why != &"":
				_pop_frames += 1
			# The drawn prompt itself, with a source offering one the whole time
			# (from the second held frame: the prompt may update after this node).
			# R2c: the prompt fades out over R2C_HUD_PROMPT_FADE instead of
			# vanishing in a frame, so it gets that long (and a frame) to be gone.
			# Counted in the frames' own time, as the fade is: a loaded machine's
			# long or clamped frames made wall time run ahead of it (a flaky fail).
			var holding := why != &"" and why != &"annex"
			var held_before := _held_for
			if holding and _held_since == INF:
				_held_since = now
				_held_for = 0.0
				held_before = 0.0
			elif not holding:
				_held_since = INF
				_held_for = 0.0
			else:
				_held_for += delta
			if holding and _held_last and _prompt_drawn() and held_before > Constants.R2C_HUD_PROMPT_FADE + 0.001:
				_prompt_frames += 1
			if why != &"":
				_reasons[why] = true
		elif _prompt_drawn():
			# Before the catch lands the same source's prompt is up: the check can fail.
			_prompt_free_frames += 1
		_held_last = why != &"" and why != &"annex"
	elif _phase == "back":
		if why == &"" and _free_at == INF:
			_free_at = now
		if _free_at != INF:
			if now - _free_at < Constants.R2B_HUD_RETURN_DELAY - 0.05 and alpha > 0.01:
				_early_frames += 1
			if alpha >= 0.99 and _back_at == INF:
				_back_at = now
			# Easing back in: never a jump of more than a frame's worth and a bit.
			if alpha - _last_alpha > 0.25:
				_pop_frames += 1
	_last_alpha = alpha


@rpc("authority", "call_remote", "reliable")
func _rpc_client(phase: String) -> void:
	_phase = phase
	match phase:
		"free":
			var why := _HudMode.reason(get_tree(), Net.local_peer_id())
			_rpc_report.rpc_id(1, "free", why == &"" and _alpha() >= 0.99, "client: reason '%s', yard HUD %.2f" % [why, _alpha()])
		"caught":
			_seen_cinematic_at = INF
			_seen_hidden_at = INF
			_prompt_frames = 0
			_prompt_free_frames = 0
			_reasons.clear()
			_pop_frames = 0
			_source = FakeSource.new()
			_source.name = "HudTestPromptSource"
			_source.at = _me()
			add_child(_source)
			_source.add_to_group("prompt_sources")
			_wait_caught()
		"back":
			_free_at = INF
			_back_at = INF
			_early_frames = 0
			_pop_frames = 0
			_wait_back()


func _wait_caught() -> void:
	var waited := 0.0
	while (_seen_hidden_at == INF) and waited < CAUGHT_WAIT_SECONDS:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	# Held a while longer: no pop back, no prompt.
	await get_tree().create_timer(1.5).timeout
	var fade := _seen_hidden_at - _seen_cinematic_at
	var hud_parts_away := true
	var ui := _ui()
	for name_of: String in ["HudRows", "TaskList", "HotbarHud", "HeatMeter", "DayHud", "JobGoal"]:
		var node := ui.get_node_or_null(name_of) as CanvasItem if ui != null else null
		if node != null and node.modulate.a > 0.01:
			hud_parts_away = false
	var why := _HudMode.reason(get_tree(), Net.local_peer_id())
	if _source != null:
		_source.queue_free()
		_source = null
	var ok := _seen_cinematic_at != INF and fade <= Constants.R2B_HUD_FADE_OUT + FADE_SLACK and _pop_frames == 0 and _prompt_frames == 0 and _prompt_free_frames > 0 and hud_parts_away and why != &""
	_rpc_report.rpc_id(1, "caught", ok, "client: cinematic (%s; reasons seen %s) seen %s, HUD eased out in %.2f s (want <= %.2f), %d pop-back frames, prompt drawn on %d free frames (want > 0) and %d held frames (want 0), every yard piece away %s" % [why, _reasons.keys(), _seen_cinematic_at != INF, fade, Constants.R2B_HUD_FADE_OUT + FADE_SLACK, _pop_frames, _prompt_free_frames, _prompt_frames, hud_parts_away])
	await _stack_step()


## While held: a spoken line lands with its sound, beats a quip and the radio, two
## lines at most, low on the screen, each on its plate.
func _stack_step() -> void:
	var stack := get_tree().get_first_node_in_group("caption_stack")
	if stack == null:
		_rpc_report.rpc_id(1, "stack", false, "client: no caption stack")
		return
	var ids: Array[int] = []
	ids.append(int(stack.call("push", &"radio", "RADIO: testing, testing.", 4.0, 1)))
	ids.append(int(stack.call("push", &"quip", "Industrial optimism. No refunds.", 4.0)))
	await get_tree().create_timer(0.4).timeout
	var said := int(stack.call("push", &"subtitle", "Gotcha! Have a NICE day!", 4.0))
	ids.append(said)
	var pushed_at := Time.get_ticks_msec() / 1000.0
	var onset := INF
	while Time.get_ticks_msec() / 1000.0 - pushed_at < 0.5:
		await get_tree().process_frame
		var label := stack.call("line_label", said) as Label
		if label != null and label.modulate.a >= 0.9 and label.is_visible_in_tree():
			onset = Time.get_ticks_msec() / 1000.0 - pushed_at
			break
	ids.append(int(stack.call("push", &"subtitle", "Arm in arm, like neighbors!", 4.0)))
	await get_tree().create_timer(0.4).timeout
	var kinds: Array = (stack.call("shown_lines") as Array).map(func(line: Dictionary) -> String: return str(line["kind"]))
	var rects: Array = stack.call("line_rects")
	var view := (stack as Control).get_viewport_rect().size
	var low := true
	var plates := true
	for rect: Rect2 in rects:
		low = low and rect.position.y >= view.y * 0.7 and rect.end.y <= view.y
	for id: int in ids:
		var label := stack.call("line_label", id) as Label
		if label != null and label.is_visible_in_tree():
			var plate := label.get_node_or_null("Plate") as Control
			plates = plates and plate != null and plate.visible and plate.size.x > 0.0
	for id: int in ids:
		stack.call("drop", id)
	await get_tree().create_timer(0.8).timeout
	# A receipt being read (any caption blocker): the radio waits for it, a spoken
	# line doesn't (it lands with its sound), and shows clear of it.
	var slip := ColorRect.new()
	slip.name = "HudTestReceipt"
	slip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slip.size = Vector2(view.x * 0.3, view.y * 0.35)
	slip.position = Vector2(view.x * 0.35, view.y * 0.65)
	slip.add_to_group("caption_blockers")
	(stack as Control).get_parent().add_child(slip)
	var radio := int(stack.call("push", &"radio", "RADIO: still testing.", 3.0, 1))
	var spoken := int(stack.call("push", &"subtitle", "Lovely paperwork, folks!", 3.0))
	var spoken_onset := INF
	var spoken_at := Time.get_ticks_msec() / 1000.0
	while Time.get_ticks_msec() / 1000.0 - spoken_at < 0.5:
		await get_tree().process_frame
		var label := stack.call("line_label", spoken) as Label
		if label != null and label.modulate.a >= 0.9 and label.is_visible_in_tree():
			spoken_onset = Time.get_ticks_msec() / 1000.0 - spoken_at
			break
	await get_tree().create_timer(0.4).timeout
	var blocked_kinds: Array = (stack.call("shown_lines") as Array).map(func(line: Dictionary) -> String: return str(line["kind"]))
	var clear := true
	for rect: Rect2 in stack.call("line_rects"):
		clear = clear and not rect.intersects(slip.get_global_rect())
	slip.queue_free()
	stack.call("drop", radio)
	stack.call("drop", spoken)
	var receipt_ok := spoken_onset <= Constants.R2B_HUD_SUBTITLE_ONSET + 0.1 and blocked_kinds == ["subtitle"] and clear
	await get_tree().create_timer(0.8).timeout
	await _held_seams(stack)
	# R2c: a corner quip triggered now waits for the moment to end (back step).
	var quips := _ui().get_node_or_null("Quips") if _ui() != null else null
	if quips != null:
		quips.call("_try", "store_arrival")
		_quip_waited = str(quips.call("waiting_trigger")) == "store_arrival"
	var ok := onset <= Constants.R2B_HUD_SUBTITLE_ONSET + 0.1 and kinds.size() <= Constants.R2B_HUD_CINEMATIC_LINES and not kinds.has("quip") and kinds.count("subtitle") == 2 and low and plates and receipt_ok
	_rpc_report.rpc_id(1, "stack", ok, "client: spoken line readable after %.3f s (want <= %.2f), shown %s (want two subtitles, no quip), low on the screen %s %s, plates %s; with a receipt up a spoken line after %.3f s, shown %s (want only the subtitle), clear of the receipt %s" % [onset, Constants.R2B_HUD_SUBTITLE_ONSET + 0.1, kinds, low, rects, plates, spoken_onset, blocked_kinds, clear])


## R2c: the held stack's seams (the e2e takes' three lines and doubled line):
## spoken lines in a row while held, the oldest dropped as each new one comes so
## a line is on its way out, one said twice. Never more drawn than the held stack
## holds (R2B_HUD_CINEMATIC_LINES, the leaving line counted), never one twice,
## the newest always on.
func _held_seams(stack: Node) -> void:
	var most := int(stack.call("most_lines"))
	var lines := ["Slow down! My lanyard's tangling!", "Hold STILL, please!", "Slow down! My lanyard's tangling!", "Ah-ah-AH!", "Gotcha! Have a NICE day!"]
	var ids: Array[int] = []
	var tally := {"crowded": 0, "doubled": 0, "leaving": 0, "most": 0}
	for line: String in lines:
		# The older of the two on screen starts on its way out, and the next line
		# comes while it's still fading.
		if ids.size() >= 2:
			stack.call("drop", ids[ids.size() - 2])
			await _tally_drawn(stack, most, tally, 3)
		ids.append(int(stack.call("push", &"subtitle", line, 3.0)))
		await _tally_drawn(stack, most, tally, 6)
	var shown: Array = (stack.call("shown_lines") as Array).map(func(line: Dictionary) -> String: return str(line["text"]))
	var newest_on := shown.has(lines[-1])
	for id: int in ids:
		stack.call("drop", id)
	await get_tree().create_timer(0.6).timeout
	var ok := most == Constants.R2B_HUD_CINEMATIC_LINES and int(tally["crowded"]) == 0 and int(tally["doubled"]) == 0 and newest_on and int(tally["leaving"]) > 0 and int(tally["most"]) == most
	_rpc_report.rpc_id(1, "held_seams", ok, "client, held: the stack holds %d (want %d), at most %d drawn, %d crowded frames, %d doubled, a line on its way out on %d frames (want > 0), the newest on %s (%s)" % [most, Constants.R2B_HUD_CINEMATIC_LINES, int(tally["most"]), int(tally["crowded"]), int(tally["doubled"]), int(tally["leaving"]), newest_on, shown])


## Over the next frames: the caption lines drawn (box shown, not faded out), how
## many, whether one is on its way out, and any drawn twice.
func _tally_drawn(stack: Node, most: int, tally: Dictionary, frames: int) -> void:
	for frame: int in frames:
		await get_tree().process_frame
		var drawn: Array[String] = []
		var leaving := false
		for entry: Dictionary in stack.get("_lines"):
			var box := entry["box"] as Control
			if box.visible and float(entry["alpha"]) > 0.0:
				drawn.append(str(entry["text"]))
				leaving = leaving or not bool(entry["shown"])
		tally["most"] = maxi(int(tally["most"]), drawn.size())
		if leaving:
			tally["leaving"] = int(tally["leaving"]) + 1
		if drawn.size() > most:
			tally["crowded"] = int(tally["crowded"]) + 1
		for text: String in drawn:
			if drawn.count(text) > 1:
				tally["doubled"] = int(tally["doubled"]) + 1


func _wait_back() -> void:
	var waited := 0.0
	while _back_at == INF and waited < BACK_WAIT_SECONDS:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	var took := _back_at - _free_at
	var want_max := Constants.R2B_HUD_RETURN_DELAY + Constants.R2B_HUD_FADE_IN + FADE_SLACK
	await get_tree().create_timer(0.3).timeout
	var quips := _ui().get_node_or_null("Quips") if _ui() != null else null
	# R2c: and it really played: the corner caption is up with its line (captions
	# on), not just no longer waiting.
	var caption := quips.get_node_or_null("Caption") as Label if quips != null else null
	var want_line := ""
	for row: Dictionary in _Strings.LINES:
		if str(row["trigger"]) == "store_arrival":
			want_line = _Strings.keyed(str(row["line"]))
			break
	var quip_shown := caption != null and caption.is_visible_in_tree() and want_line != "" and caption.text == want_line
	var quip_played := quips != null and str(quips.call("waiting_trigger")) == "" and (quip_shown or not _QuipPlayer.captions_on())
	var ok := _free_at != INF and _back_at != INF and took <= want_max and took >= Constants.R2B_HUD_RETURN_DELAY and _early_frames == 0 and _pop_frames == 0 and _quip_waited and quip_played
	_rpc_report.rpc_id(1, "back", ok, "client: free %s, HUD back after %.2f s (want %.2f to %.2f), %d early frames, %d popping frames; a quip triggered while held waited %s and played once the HUD was back %s (corner caption '%s')" % [_free_at != INF, took, Constants.R2B_HUD_RETURN_DELAY, want_max, _early_frames, _pop_frames, _quip_waited, quip_played, caption.text if caption != null and caption.visible else ""])
	_phase = ""


@rpc("any_peer", "call_remote", "reliable")
func _rpc_report(step_name: String, ok: bool, detail: String) -> void:
	if not Net.is_host():
		return
	_report[step_name] = ok
	_step(step_name, ok, detail)


# ---------------------------------------------------------------- host

func _run_host() -> void:
	var waited := 0.0
	while _mate() == null and waited < CLIENT_WAIT_SECONDS:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	if _mate() == null:
		_finish("the Target client never joined")
		return
	await get_tree().create_timer(4.0).timeout
	var target := int(str(_mate().name))
	var mine := _HudMode.reason(get_tree(), Net.local_peer_id())
	_step("free_host", mine == &"" and _alpha() >= 0.99, "host: reason '%s', yard HUD %.2f" % [mine, _alpha()])
	_rpc_client.rpc_id(target, "free")
	await _await_report("free")
	# The real catch: no chase, so straight to the van door (director.force_capture).
	_rpc_client.rpc_id(target, "caught")
	await get_tree().create_timer(0.3).timeout
	var director := get_tree().get_first_node_in_group("run_director")
	if director == null:
		_finish("no run director")
		return
	var free_grab := bool(_mate().call("can_be_grabbed"))
	director.call("force_capture", target)
	await _await_report("caught", CAUGHT_WAIT_SECONDS + 4.0)
	# R2c: no "[E] Grab" over a friend the NICE BOYS have: the host's grab check
	# (brawl.gd) and the prompt ask the same question.
	var held_grab := bool(_mate().call("can_be_grabbed"))
	_step("grab", free_grab and not held_grab, "the friend can be grabbed while free %s, while caught %s (want true, false)" % [free_grab, held_grab])
	await _await_report("stack")
	# Let go: out of the van and the cohort, the raid over.
	_rpc_client.rpc_id(target, "back")
	await get_tree().create_timer(0.3).timeout
	director.rpc("_rpc_drop_rider", target)
	director.call("dev_reset")
	var shuttle := get_tree().get_first_node_in_group("nice_shuttle")
	if shuttle != null:
		shuttle.call("dev_reset")
	await _await_report("back", BACK_WAIT_SECONDS + 4.0)
	await _overhead_steps()
	_finish("")


func _await_report(step_name: String, seconds: float = REPORT_WAIT_SECONDS) -> void:
	var waited := 0.0
	while not _report.has(step_name) and waited < seconds:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	if not _report.has(step_name):
		_step(step_name, false, "the client never reported")


# ---------------------------------------------------------------- the overheads (host)

## A stand-in NICE BOY: his body, his name tag and his bark label as the crew
## scene has them (npcs/crew_member.tscn), and a mode.
class FakeCrew extends StaticBody3D:
	enum Mode { PATROL, SEATED }
	var mode: int = Mode.PATROL

	func build(tag_text: String) -> void:
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.35
		capsule.height = 1.8
		shape.shape = capsule
		shape.position = Vector3(0.0, 0.9, 0.0)
		add_child(shape)
		var visual := Node3D.new()
		visual.name = "Visual"
		add_child(visual)
		var tag := Label3D.new()
		tag.name = "Label"
		tag.position = Vector3(0.0, 2.2, 0.0)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.fixed_size = true
		tag.font_size = 44
		tag.outline_size = 10
		tag.pixel_size = minf(Constants.CREW_TAG_PIXEL_SIZE, Constants.CREW_TAG_MAX_PX)
		tag.text = tag_text
		visual.add_child(tag)
		var bark := Label3D.new()
		bark.name = "Bark"
		bark.position = Vector3(0.0, 2.62, 0.0)
		bark.visible = false
		bark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		bark.fixed_size = true
		bark.font_size = 40
		bark.outline_size = 14
		bark.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bark.width = 320.0
		bark.pixel_size = minf(Constants.CREW_BARK_PIXEL_SIZE, Constants.CREW_TAG_MAX_PX)
		visual.add_child(bark)


## A hedge's leaves: a box with no collider (R2c seams).
class FakeHedge extends Node3D:
	var box_size := Vector3(4.0, 2.2, 1.2)


## Turns the host to the longest clear view (no house or fence in the first
## CLEAR_METERS), level, so the stand-ins have open ground in front.
func _face_open_ground() -> void:
	var me := _me()
	var camera := get_viewport().get_camera_3d()
	if me == null or camera == null:
		return
	var space := me.get_world_3d().direct_space_state
	var best_yaw := float(me.get("body_yaw"))
	var best := -1.0
	for step: int in 16:
		var yaw := TAU * float(step) / 16.0
		var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
		var query := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position + dir * CLEAR_METERS, 1)
		var hit := space.intersect_ray(query)
		var clear := CLEAR_METERS if hit.is_empty() else camera.global_position.distance_to(hit["position"])
		if clear > best:
			best = clear
			best_yaw = yaw
	me.set("body_yaw", best_yaw)
	me.set("head_pitch", 0.0)
	for frame: int in 3:
		await get_tree().process_frame


func _overhead_steps() -> void:
	await _face_open_ground()
	var camera := get_viewport().get_camera_3d()
	var overheads := _ui().get_node_or_null("Overheads") if _ui() != null else null
	var stack := get_tree().get_first_node_in_group("caption_stack")
	if camera == null or overheads == null or stack == null:
		_step("once", false, "camera %s, overheads %s, stack %s" % [camera, overheads, stack])
		return
	var view := get_viewport().get_visible_rect().size
	var ahead := -camera.global_basis.z
	ahead.y = 0.0
	ahead = ahead.normalized()
	var eye := camera.global_position
	var ground := _me().global_position.y
	var far := _fake("NICE BOY FAR", eye + ahead * 9.0, ground)
	var near := _fake("NICE BOY NEAR", eye + ahead * 1.6 + camera.global_basis.x * 0.9, ground)
	await get_tree().create_timer(0.3).timeout
	# One line, shown once: a bubble from far off, a subtitle up close.
	var far_line := "Doo doo doo, lovely day for it!"
	var near_line := "Ah-ah-AH! Hands where I can compliment them!"
	var far_how := _Overheads.present(far, far.get_node("Visual/Bark") as Label3D, far_line, 2.2)
	var near_how := _Overheads.present(near, near.get_node("Visual/Bark") as Label3D, near_line, 2.2)
	await get_tree().create_timer(0.3).timeout
	var far_count := _times_on_screen(stack, far, far_line)
	var near_count := _times_on_screen(stack, near, near_line)
	_step("once", far_how == &"bubble" and near_how == &"subtitle" and far_count == 1 and near_count == 1, "far off: %s, on screen %d time(s); up close: %s, on screen %d time(s) (want bubble once, subtitle once)" % [far_how, far_count, near_how, near_count])
	(near.get_node("Visual/Bark") as Label3D).visible = false
	# A bubble at the left edge glides back inside, and a long line wraps as a line.
	var bark := far.get_node("Visual/Bark") as Label3D
	bark.text = LONG_LINE
	bark.visible = true
	far.global_position = camera.project_position(Vector2(6.0, view.y * 0.5), 9.0)
	far.global_position.y = ground
	await get_tree().create_timer(0.8).timeout
	var bubble := Rect2()
	for entry: Dictionary in overheads.get("last_rects"):
		if str(entry["kind"]) == "bubble":
			bubble = entry["rect"]
	var margin := Constants.R2B_HUD_SAFE_MARGIN - 2.0
	var inside := bubble.size != Vector2.ZERO and bubble.position.x >= margin and bubble.end.x <= view.x - margin and bubble.position.y >= margin
	var font := ThemeDB.fallback_font
	var row := font.get_height(bark.font_size)
	var rows := roundi(font.get_multiline_string_size(LONG_LINE, HORIZONTAL_ALIGNMENT_CENTER, bark.width, bark.font_size).y / row)
	_step("clamp", inside and rows <= 3, "bubble %s inside %s less %.0f px: %s; the long line wraps to %d rows (want <= 3)" % [bubble, view, margin, inside, rows])
	bark.visible = false
	# Tags: behind a wall, stacked, and sat in the van.
	far.global_position = eye + ahead * 8.0
	far.global_position.y = ground
	# Behind him and a little aside: his tag lands on the nearer one, but nothing
	# solid stands between you and it.
	near.global_position = eye + ahead * 12.0 + camera.global_basis.x * 0.5
	near.global_position.y = ground
	# A tag comes back after R2C_HUD_TAG_DWELL in the clear, then fades in.
	await get_tree().create_timer(0.8).timeout
	var far_tag := far.get_node("Visual/Label") as Label3D
	var near_tag := near.get_node("Visual/Label") as Label3D
	var stacked := far_tag.transparency <= 0.05 and near_tag.transparency >= 0.95
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 6.0, 0.3)
	wall_shape.shape = box
	wall.add_child(wall_shape)
	add_child(wall)
	wall.global_position = eye + ahead * 4.0
	wall.look_at(eye, Vector3.UP)
	await get_tree().create_timer(0.5).timeout
	var behind_wall := far_tag.transparency >= 0.95
	wall.queue_free()
	await get_tree().create_timer(0.8).timeout
	var after_wall := far_tag.transparency <= 0.05
	far.mode = FakeCrew.Mode.SEATED
	await get_tree().create_timer(0.5).timeout
	var seated := far_tag.transparency >= 0.95
	far.mode = FakeCrew.Mode.PATROL
	var near_clear := near_tag.transparency
	near.queue_free()
	# A Courtesy Shuttle on the move between you and him: its Solid is off every
	# layer while it drives (shuttle._set_solid), and the tag still fades.
	var behind_van := false
	var shuttle := get_tree().get_first_node_in_group("nice_shuttle")
	if shuttle != null:
		await get_tree().create_timer(0.5).timeout
		var trip := Node3D.new()
		trip.name = "HudTestTrip"
		var look := Node3D.new()
		look.name = "VanLook"
		trip.add_child(look)
		var solid := AnimatableBody3D.new()
		solid.name = "Solid"
		solid.collision_layer = 0
		solid.collision_mask = 0
		# As props/nice_van.gd builds it: moved by its look, not by physics.
		solid.sync_to_physics = false
		var van_shape := CollisionShape3D.new()
		var van_box := BoxShape3D.new()
		van_box.size = Vector3(2.3, 2.4, 6.4)
		van_shape.shape = van_box
		van_shape.position = Vector3(0.0, 1.2, 0.0)
		solid.add_child(van_shape)
		look.add_child(solid)
		shuttle.add_child(trip)
		trip.global_position = eye + ahead * 4.0 + Vector3.DOWN * (eye.y - ground)
		trip.look_at(trip.global_position + camera.global_basis.x, Vector3.UP)
		await get_tree().create_timer(0.5).timeout
		behind_van = far_tag.transparency >= 0.95
		trip.queue_free()
	_step("tags", stacked and behind_wall and after_wall and seated and behind_van, "two heads in a line show the nearer tag only %s (near %.2f, far %.2f transparent), behind a wall it fades %s and comes back %s, sat in the van it's down %s, behind a driving van it fades %s" % [stacked, far_tag.transparency, near_clear, behind_wall, after_wall, seated, behind_van])
	far.queue_free()
	await _seam_steps(camera, overheads, stack, eye, ahead, ground)


## R2c (docs/GAME.md "What's on screen, between the beats"): the seams between
## the beats. Two NICE BOYS talking at once get two bubbles that don't touch; a
## two-shot's narrow lens or a head a metre away never makes a word huge; the
## caption stack never shows more lines than it holds (a line on its way out
## counted), never the same line twice, and the newest spoken line always gets on;
## wrapped lines are balanced; a hiding spot's leaves hide a tag.
func _seam_steps(camera: Camera3D, overheads: Node, stack: Node, eye: Vector3, ahead: Vector3, ground: float) -> void:
	var view := get_viewport().get_visible_rect().size
	var side := camera.global_basis.x
	var left := _fake("NICE BOY LEFT", eye + ahead * 9.0 - side * 0.5, ground)
	var right := _fake("NICE BOY RIGHT", eye + ahead * 9.5 + side * 0.5, ground)
	await get_tree().create_timer(0.2).timeout
	for crew: FakeCrew in [left, right]:
		var said := crew.get_node("Visual/Bark") as Label3D
		_Overheads.setup_bubble(said)
		said.text = "We just want to talk! It's a short form!" if crew == left else "Eleven pages!"
		said.visible = true
	await get_tree().create_timer(0.6).timeout
	var bubbles: Array[Rect2] = []
	for entry: Dictionary in overheads.get("last_rects"):
		if str(entry["kind"]) == "bubble":
			bubbles.append(entry["rect"])
	var apart := bubbles.size() == 2 and not bubbles[0].intersects(bubbles[1])
	for crew: FakeCrew in [left, right]:
		(crew.get_node("Visual/Bark") as Label3D).visible = false
	# Sizes: a fixed-size bubble through a 30 degree lens, a player's tag a metre off.
	var lens := Camera3D.new()
	lens.fov = 30.0
	add_child(lens)
	lens.global_position = eye
	var probe := Label3D.new()
	probe.fixed_size = true
	probe.font_size = 40
	probe.pixel_size = Constants.CREW_BARK_PIXEL_SIZE
	add_child(probe)
	probe.global_position = eye + ahead * 3.0
	_Overheads.fit_size(probe, lens, view, Constants.R2C_HUD_BUBBLE_LINE_MIN, Constants.R2C_HUD_BUBBLE_LINE_MAX)
	var bubble_share := float(probe.font_size) * probe.pixel_size / (2.0 * tan(deg_to_rad(lens.fov) * 0.5))
	var plate := Label3D.new()
	plate.font_size = 48
	add_child(plate)
	plate.global_position = eye + ahead * 1.0
	_Overheads.fit_size(plate, lens, view, Constants.R2C_HUD_TAG_LINE_MIN, Constants.R2C_HUD_TAG_LINE_MAX)
	var tag_share := float(plate.font_size) * plate.pixel_size / (2.0 * 1.0 * tan(deg_to_rad(lens.fov) * 0.5))
	lens.queue_free()
	probe.queue_free()
	plate.queue_free()
	var sizes := bubble_share <= Constants.R2C_HUD_BUBBLE_LINE_MAX + 0.001 and tag_share <= Constants.R2C_HUD_TAG_LINE_MAX + 0.001
	_step("apart", apart and sizes, "two bubbles at once: %s, apart %s; through a 30 degree lens a bubble line is %.3f of the view (want <= %.3f), a tag a metre off %.3f (want <= %.3f)" % [bubbles, apart, bubble_share, Constants.R2C_HUD_BUBBLE_LINE_MAX, tag_share, Constants.R2C_HUD_TAG_LINE_MAX])
	# The caption stack: four spoken lines in a row, one said twice.
	var most := int(stack.call("most_lines"))
	var lines := ["Slow down! My lanyard's tangling!", "Hold STILL, please!", "Slow down! My lanyard's tangling!", "Ah-ah-AH!", "Gotcha! Have a NICE day!"]
	var ids: Array[int] = []
	var crowded := 0
	var doubled := 0
	for line: String in lines:
		ids.append(int(stack.call("push", &"subtitle", line, 3.0)))
		for frame: int in 4:
			await get_tree().process_frame
			var drawn: Array[String] = []
			for entry: Dictionary in stack.get("_lines"):
				var box := entry["box"] as Control
				if box.visible and float(entry["alpha"]) > 0.0:
					drawn.append(str(entry["text"]))
			if drawn.size() > most:
				crowded += 1
			for text: String in drawn:
				if drawn.count(text) > 1:
					doubled += 1
	var shown: Array = (stack.call("shown_lines") as Array).map(func(line: Dictionary) -> String: return str(line["text"]))
	var newest_on := shown.has(lines[-1])
	for id: int in ids:
		stack.call("drop", id)
	# Balanced: the narrowest width keeping the row count, and no narrower.
	var font := ThemeDB.fallback_font
	var long := "Reminder: courtesy waves are mandatory at every stop sign. Every one."
	var wide := font.get_string_size(long, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x * 0.93
	var even := _TextFit.balanced_width(font, long, 22, wide)
	var rows_wide := _TextFit.rows(font, long, 22, wide)
	var balanced := _TextFit.rows(font, long, 22, even) == rows_wide and even < wide * 0.8 and _TextFit.rows(font, long, 22, even - 8.0) > rows_wide
	_step("stack_seams", crowded == 0 and doubled == 0 and newest_on and balanced, "at most %d lines drawn: %d crowded frames, %d doubled; the newest spoken line on %s (%s); %d rows at %.0f px balanced to %.0f px %s" % [most, crowded, doubled, newest_on, shown, rows_wide, wide, even, balanced])
	# A hedge between you and him hides his tag (leaves have no layer-1 collider).
	left.global_position = eye + ahead * 8.0
	left.global_position.y = ground
	right.queue_free()
	await get_tree().create_timer(0.8).timeout
	var tag := left.get_node("Visual/Label") as Label3D
	var open := tag.transparency <= 0.05
	# A hiding spot's box, as net/components/hide_spot.gd has it (no collider).
	var hedge := FakeHedge.new()
	hedge.name = "HudTestHedge"
	hedge.add_to_group(_Overheads.VIEW_BLOCKERS)
	add_child(hedge)
	hedge.global_position = Vector3(eye.x, ground, eye.z) + ahead * 4.0
	hedge.look_at(Vector3(eye.x, ground, eye.z), Vector3.UP)
	await get_tree().create_timer(0.5).timeout
	var leafed := tag.transparency >= 0.95
	hedge.queue_free()
	_step("hedge", open and leafed, "a tag in the open %s, behind a hedge's leaves %s (%.2f transparent)" % [open, leafed, tag.transparency])
	await _bubble_gone_step(camera, overheads, left, eye, ahead, ground)
	left.queue_free()


## R2c (the escort's "After you!" pinned in a corner after the iris): a bubble
## that's up goes once his head leaves the picture, comes back when it's in it
## again, and is gone on the first frame of a cut to a shot without him.
func _bubble_gone_step(camera: Camera3D, overheads: Node, crew: FakeCrew, eye: Vector3, ahead: Vector3, ground: float) -> void:
	var view := get_viewport().get_visible_rect().size
	var bark := crew.get_node("Visual/Bark") as Label3D
	crew.global_position = Vector3(eye.x, ground, eye.z) + ahead * 9.0
	_Overheads.setup_bubble(bark)
	bark.text = "After you!"
	bark.visible = true
	await get_tree().create_timer(0.5).timeout
	var up := bark.transparency <= 0.05 and _bubble_count(overheads) == 1
	# Off the left edge of the picture, well past where his bubble could glide in.
	var aside := camera.project_position(Vector2(-view.x * 0.4, view.y * 0.5), 9.0)
	crew.global_position = Vector3(aside.x, ground, aside.z)
	await get_tree().create_timer(0.5).timeout
	var gone := bark.transparency >= 0.95 and _bubble_count(overheads) == 0
	crew.global_position = Vector3(eye.x, ground, eye.z) + ahead * 9.0
	await get_tree().create_timer(0.6).timeout
	var back := bark.transparency <= 0.05
	# A cut to another camera turned well away (he's still in front of it, just
	# out of the picture): gone on its first frame, no fade.
	var lens := Camera3D.new()
	add_child(lens)
	lens.global_position = eye
	lens.look_at(eye + ahead.rotated(Vector3.UP, deg_to_rad(80.0)), Vector3.UP)
	lens.current = true
	await get_tree().process_frame
	await get_tree().process_frame
	var cut_gone := bark.transparency >= 0.99 and _bubble_count(overheads) == 0
	camera.current = true
	lens.queue_free()
	bark.visible = false
	_step("bubble_gone", up and gone and back and cut_gone, "a bubble up %s; his head out of the picture, gone %s; back in it, back %s; across a cut, gone on the first frame %s" % [up, gone, back, cut_gone])


func _bubble_count(overheads: Node) -> int:
	var count := 0
	for entry: Dictionary in overheads.get("last_rects"):
		if str(entry["kind"]) == "bubble":
			count += 1
	return count


func _fake(tag_text: String, at: Vector3, ground: float) -> FakeCrew:
	var crew := FakeCrew.new()
	crew.name = tag_text.replace(" ", "")
	crew.build(tag_text)
	add_child(crew)
	# Not "nice_crew": the director frees those when no raid is on.
	crew.add_to_group(_Overheads.SPEAKERS)
	crew.global_position = Vector3(at.x, ground, at.z)
	return crew


## How many times a line is on screen now: its bubble (shown) plus caption lines.
func _times_on_screen(stack: Node, crew: Node, line: String) -> int:
	var count := 0
	var bark := crew.get_node("Visual/Bark") as Label3D
	if bark.visible and bark.text == line:
		count += 1
	for shown: Dictionary in stack.call("shown_lines"):
		if str(shown["text"]) == line:
			count += 1
	return count


# ---------------------------------------------------------------- helpers

func _step(step_name: String, ok: bool, detail: String) -> void:
	_steps[step_name] = ok
	print("[HudTest] %s: %s (%s)" % [step_name, detail, "ok" if ok else "FAIL"])


func _finish(why: String) -> void:
	if why != "":
		_steps["setup"] = false
		print("[HudTest] %s" % why)
	var ok := not _steps.is_empty()
	for step: String in STEPS:
		if not _steps.has(step):
			_steps[step] = false
			print("[HudTest] %s: never ran (FAIL)" % step)
	for step: String in _steps:
		ok = ok and bool(_steps[step])
	result = {"ok": ok, "done": true, "steps": _steps.duplicate()}
	print("[HudTest] all ok: %s" % ok)
	if Net.is_host():
		_rpc_done.rpc(ok)


## The client's half ends with the host's verdict on what it reported.
@rpc("authority", "call_remote", "reliable")
func _rpc_done(ok: bool) -> void:
	result = {"ok": ok, "done": true}


func _me() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as Node3D
	return null


func _mate() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name != str(Net.local_peer_id()):
			return node as Node3D
	return null
