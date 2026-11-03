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
## Each step prints a [HudTest] line. The client reports its half by RPC.

const _HudMode = preload("res://ui/hud_mode.gd")
const _Overheads = preload("res://ui/overheads.gd")
const _Prompt = preload("res://ui/interaction_prompt.gd")
const CLIENT_WAIT_SECONDS: float = 30.0
const CAUGHT_WAIT_SECONDS: float = 15.0
const BACK_WAIT_SECONDS: float = 10.0
const REPORT_WAIT_SECONDS: float = 10.0
## Slack on the fades for frame timing (s).
const FADE_SLACK: float = 0.25
const CLEAR_METERS: float = 16.0
## Every step a passing run reports.
const STEPS: Array[String] = ["free_host", "free", "caught", "stack", "back", "once", "clamp", "tags"]
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


func _process(_delta: float) -> void:
	if not _started and get_tree().get_first_node_in_group("world") != null and _me() != null and get_tree().get_first_node_in_group("job_lot") != null:
		_started = true
		if Net.is_host():
			_run_host()
	if not Net.is_host():
		_watch_client()


# ---------------------------------------------------------------- client

func _ui() -> Node:
	return get_tree().get_first_node_in_group("game_ui")


func _alpha() -> float:
	var ui := _ui()
	return float(ui.call("yard_hud_alpha")) if ui != null and ui.has_method("yard_hud_alpha") else -1.0


## The client's frames while it's held and let go.
func _watch_client() -> void:
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
			if why != &"" and why != &"annex" and not _Prompt.current_hint(get_tree()).is_empty():
				_prompt_frames += 1
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
			_pop_frames = 0
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
	var ok := _seen_cinematic_at != INF and fade <= Constants.R2B_HUD_FADE_OUT + FADE_SLACK and _pop_frames == 0 and _prompt_frames == 0 and hud_parts_away and why != &""
	_rpc_report.rpc_id(1, "caught", ok, "client: cinematic (%s) seen %s, HUD eased out in %.2f s (want <= %.2f), %d pop-back frames, %d frames with a prompt, every yard piece away %s" % [why, _seen_cinematic_at != INF, fade, Constants.R2B_HUD_FADE_OUT + FADE_SLACK, _pop_frames, _prompt_frames, hud_parts_away])
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
	var ok := onset <= Constants.R2B_HUD_SUBTITLE_ONSET + 0.1 and kinds.size() <= Constants.R2B_HUD_CINEMATIC_LINES and not kinds.has("quip") and kinds.count("subtitle") == 2 and low and plates
	_rpc_report.rpc_id(1, "stack", ok, "client: spoken line readable after %.3f s (want <= %.2f), shown %s (want two subtitles, no quip), low on the screen %s %s, plates %s" % [onset, Constants.R2B_HUD_SUBTITLE_ONSET + 0.1, kinds, low, rects, plates])
	for id: int in ids:
		stack.call("drop", id)


func _wait_back() -> void:
	var waited := 0.0
	while _back_at == INF and waited < BACK_WAIT_SECONDS:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	var took := _back_at - _free_at
	var want_max := Constants.R2B_HUD_RETURN_DELAY + Constants.R2B_HUD_FADE_IN + FADE_SLACK
	var ok := _free_at != INF and _back_at != INF and took <= want_max and took >= Constants.R2B_HUD_RETURN_DELAY and _early_frames == 0 and _pop_frames == 0
	_rpc_report.rpc_id(1, "back", ok, "client: free %s, HUD back after %.2f s (want %.2f to %.2f), %d early frames, %d popping frames" % [_free_at != INF, took, Constants.R2B_HUD_RETURN_DELAY, want_max, _early_frames, _pop_frames])
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
	director.call("force_capture", target)
	await _await_report("caught", CAUGHT_WAIT_SECONDS + 4.0)
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
	await get_tree().create_timer(0.5).timeout
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
	await get_tree().create_timer(0.5).timeout
	var after_wall := far_tag.transparency <= 0.05
	far.mode = FakeCrew.Mode.SEATED
	await get_tree().create_timer(0.5).timeout
	var seated := far_tag.transparency >= 0.95
	_step("tags", stacked and behind_wall and after_wall and seated, "two heads in a line show the nearer tag only %s (near %.2f, far %.2f transparent), behind a wall it fades %s and comes back %s, sat in the van it's down %s" % [stacked, far_tag.transparency, near_tag.transparency, behind_wall, after_wall, seated])
	far.queue_free()
	near.queue_free()


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
