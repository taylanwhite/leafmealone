extends Node

## --stage-test (R2 chunk 1, gap-specs/nice_boys.json; port 7826, host plus a
## Target client, both with --sim-lag=150 --stage-test). The seams every R2 chunk
## builds on, checked in the running game:
##   staged    the host stages the client's body on a moving anchor (one reliable
##             RPC, every peer places it): within STAGE_TOLERANCE of the anchor on
##             both peers every tick after the blend, no tick over
##             STAGE_MAX_STEP_METERS, and released mid-move with no jump (the owner
##             stays put; the host's view eases back without a step over it).
##   camera    StageCam lives under CameraRig, not Visual; nested pushes, an orbit
##             with clamped look, a toggle while a shot is live, pops, a cut and an
##             anchor freed under a shot: exactly one current camera (and never
##             none) on every frame for about 6 s.
##   lock      a control lock holds movement and the held keys, lets its
##             allowances through, and movement comes back when it's lifted.
##   gesture   register_gesture poses a body by name; an unknown name is a no-op;
##             set_anim_speed(0) freezes the body mid-gesture.
##   iris      closes and opens on the server times given, held shut IRIS_HOLD_MIN.
##   captions  4 lines at the normal and the largest caption size: 3 show, none
##             touches the goal line, the job panel or the heat meter or each
##             other; captions off hides subtitles, quips and radio but not a
##             teammate line.
##   goal      the goal line dims in WARNING, CHASE and DEPARTING and comes back.
## Each step prints a [StageTest] line. The client reports its half by RPC.

const _CartoonBody = preload("res://player/cartoon_body.gd")
const _UiRoot = preload("res://ui/ui_root.gd")
const _StageCam = preload("res://player/stage_cam.gd")
const _StageBody = preload("res://player/stage_body.gd")
const CLIENT_WAIT_SECONDS: float = 30.0
const REPORT_WAIT_SECONDS: float = 8.0
## The staged body's anchor: a circle walked at about escort speed.
const STAGE_SECONDS: float = 4.0
const STAGE_BLEND: float = 0.25
const ANCHOR_RADIUS: float = 3.0
const ANCHOR_RATE: float = 0.8
const STAGE_TOLERANCE: float = 0.05
## The host's view of the release: no frame may step more than this.
const RELEASE_STEP_MAX: float = 0.12
const RELEASE_WATCH_SECONDS: float = 0.8

static var result: Dictionary = {}

var _started: bool = false
var _steps: Dictionary = {}
var _report: Dictionary = {}
var _anchor: Node3D
var _anchor_base := Vector3.INF
var _anchor_at: float = INF
var _staged_peer: int = 0
var _staged_since: float = INF
var _err_max: float = 0.0
var _err_samples: int = 0
var _release_at: float = INF
var _release_from := Vector3.INF
var _release_jump: float = 0.0
var _release_step_max: float = 0.0
var _last_drawn := Vector3.INF
var _watch_frames: bool = false
var _frames: int = 0
var _null_frames: int = 0
var _wrong_current: int = 0
var _anchor_jumped: bool = false
var _anchor_hitches: int = 0
## The body's own steps over STAGE_MAX_STEP_METERS when its anchor didn't jump.
var _pops: int = 0
var _last_owner := Vector3.INF
var _last_anchor_view := Vector3.INF
var _anchor_seen_at: float = INF
var _anchor_local_at: float = 0.0


func _ready() -> void:
	# Measures after StageBody (110) has placed the body, on frames and ticks.
	process_priority = 120
	process_physics_priority = 120
	_anchor = Node3D.new()
	_anchor.name = "Anchor"
	add_child(_anchor)
	# The anchor moves before any node's physics tick.
	get_tree().physics_frame.connect(_move_anchor)


func _process(_delta: float) -> void:
	_watch_cameras()
	_measure_view()
	if _started or get_tree().get_first_node_in_group("world") == null or _me() == null:
		return
	if get_tree().get_first_node_in_group("job_lot") == null:
		return
	_started = true
	if Net.is_host():
		_run_host()


## The anchor walks its circle on physics ticks, the same on every peer (a pure
## function of server time), before StageBody (110) places the body.
func _move_anchor() -> void:
	if _anchor_base == Vector3.INF:
		return
	var before := _anchor.global_position
	var t := maxf(0.0, Net.server_time() - _anchor_at)
	var angle := t * ANCHOR_RATE
	var at := _anchor_base + Vector3(sin(angle) * ANCHOR_RADIUS, 0.0, (1.0 - cos(angle)) * ANCHOR_RADIUS)
	var tangent := Vector3(cos(angle), 0.0, sin(angle))
	_anchor.global_transform = Transform3D(Basis.looking_at(tangent, Vector3.UP), at)
	# A hitch (a frame that took far longer than a tick) moves a time-driven anchor
	# a long way at once; that's the anchor catching up, not the stage popping.
	_anchor_jumped = before.distance_to(at) > Constants.STAGE_MAX_STEP_METERS * 0.5
	var server_now := Net.server_time()
	var local_now := Time.get_ticks_usec() / 1000000.0
	if _anchor_jumped and _anchor_seen_at != INF:
		_anchor_hitches += 1
		print("[StageTest] the anchor jumped %.2f m in one tick: server time moved %.3f s while this machine's clock moved %.3f s" % [before.distance_to(at), server_now - _anchor_seen_at, local_now - _anchor_local_at])
	_anchor_seen_at = server_now
	_anchor_local_at = local_now


func _physics_process(_delta: float) -> void:
	_measure_owner()


# ---------------------------------------------------------------- host

func _run_host() -> void:
	var waited := 0.0
	while _mate() == null and waited < CLIENT_WAIT_SECONDS:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	if _mate() == null:
		_finish("the Target client never joined")
		return
	# Past the join's loading hitches, so the moving anchor isn't caught mid-stall.
	await get_tree().create_timer(4.0).timeout
	await _staged_step()
	await _camera_step()
	await _lock_step()
	await _gesture_step()
	await _iris_step()
	await _caption_step()
	await _goal_step()
	var waited_report := 0.0
	while _report.is_empty() and waited_report < REPORT_WAIT_SECONDS:
		await get_tree().create_timer(0.25).timeout
		waited_report += 0.25
	_step("client", bool(_report.get("ok", false)), "client report %s" % JSON.stringify(_report))
	_finish("")


## The client's body on a moving anchor, staged by one reliable RPC on every peer.
func _staged_step() -> void:
	var mate := _mate()
	var base := mate.global_position
	_StageBody.reset_log()
	_rpc_stage.rpc(int(str(mate.name)), base, Net.server_time() + Constants.BEAT_LEAD)
	await get_tree().create_timer(STAGE_SECONDS).timeout
	_rpc_unstage.rpc(Net.server_time())
	await get_tree().create_timer(RELEASE_WATCH_SECONDS + 0.2).timeout
	var stats: Dictionary = _StageBody.log.duplicate()
	var ok := _err_samples > 30 and _err_max <= STAGE_TOLERANCE and _pops == 0 and _release_step_max <= RELEASE_STEP_MAX
	_step("staged", ok, "the host draws the client's staged body within %.3f m of its anchor over %d frames (want <= %.2f), %d steps over %.2f m its anchor didn't make (StageBody log %s, anchor hitches %d), release: largest frame step %.3f m (want <= %.2f)" % [_err_max, _err_samples, STAGE_TOLERANCE, _pops, Constants.STAGE_MAX_STEP_METERS, JSON.stringify(stats), _anchor_hitches, _release_step_max, RELEASE_STEP_MAX])


## StageCam: pushes, blends, an orbit, a toggle, pops, a cut and a freed anchor,
## with exactly one current camera on every frame.
func _camera_step() -> void:
	var me := _me()
	var rig := me.get_node("CameraRig")
	var cam := me.call("stage_cam") as Camera3D
	var placed := cam != null and cam.get_parent() == rig and not me.get_node("Visual").is_ancestor_of(cam)
	if cam == null:
		_step("camera", false, "no StageCam on the host's player")
		return
	_StageCam.reset_log()
	_frames = 0
	_null_frames = 0
	_wrong_current = 0
	_watch_frames = true
	var problems: Array[String] = []
	var ahead := -me.global_basis.z
	var a := _marker(me.global_position + ahead * 3.0 + Vector3.UP * 1.4)
	var b := _marker(me.global_position + ahead * 2.0 + Vector3.UP * 1.0)
	me.call("stage_push", &"t_a", {"anchor": a, "offset": Transform3D(Basis.IDENTITY, Vector3(0.0, 0.3, 2.5)), "blend_in": 0.4, "priority": 10})
	if not cam.current:
		problems.append("not current the frame it was pushed")
	await get_tree().create_timer(0.6).timeout
	if StringName(me.call("stage_top")) != &"t_a":
		problems.append("t_a not on top")
	me.call("stage_push", &"t_b", {"anchor": b, "offset": Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, 3.0)), "blend_in": 0.3, "orbit": true, "yaw_clamp": Vector2(-0.7, 0.7), "pitch_clamp": Vector2(-0.3, 0.3), "priority": 20})
	await get_tree().create_timer(0.15).timeout
	cam.call("add_look", Vector2(4000.0, 0.0))
	var look: Vector2 = cam.call("look_angles")
	if StringName(me.call("stage_top")) != &"t_b" or absf(look.x) < 0.69 or absf(look.x) > 0.7001:
		problems.append("orbit look %s not clamped to 0.7 on t_b (top %s)" % [look, me.call("stage_top")])
	# A lower-priority shot pushed later stays under the top one.
	me.call("stage_push", &"t_low", {"anchor": a, "priority": 5})
	if StringName(me.call("stage_top")) != &"t_b":
		problems.append("a lower priority shot took the top")
	me.call("stage_pop", &"t_low")
	await get_tree().create_timer(0.3).timeout
	rig.call("toggle")
	await get_tree().process_frame
	if not cam.current or rig.call("current_base_camera") != rig.get_node("OverShoulder"):
		problems.append("the toggle took the view from a live shot")
	me.call("stage_pop", &"t_b")
	await get_tree().create_timer(0.5).timeout
	if StringName(me.call("stage_top")) != &"t_a":
		problems.append("t_a not back on top after t_b popped")
	me.call("stage_pop", &"t_a", 0.4)
	await get_tree().create_timer(0.1).timeout
	if not cam.current:
		problems.append("handed back before the blend out finished")
	await get_tree().create_timer(0.5).timeout
	if cam.current or not (rig.get_node("OverShoulder") as Camera3D).current:
		problems.append("the over-shoulder camera didn't get the view back")
	rig.call("toggle")
	await get_tree().process_frame
	if not (me.get_node("Visual/Head/FirstPerson") as Camera3D).current:
		problems.append("first person not current after toggling back")
	# A cut each way (only ever behind a closed iris in the game).
	me.call("stage_push", &"t_cut", {"anchor": b, "blend_in": 0.0, "priority": 10})
	if not cam.current:
		problems.append("a cut in wasn't current at once")
	await get_tree().create_timer(0.3).timeout
	me.call("stage_pop", &"t_cut", 0.0)
	await get_tree().create_timer(0.2).timeout
	# An anchor freed under a live shot: the shot goes, the view comes home.
	var gone := _marker(me.global_position + ahead * 4.0 + Vector3.UP * 1.5)
	me.call("stage_push", &"t_gone", {"anchor": gone, "blend_in": 0.2, "priority": 10})
	await get_tree().create_timer(0.4).timeout
	gone.queue_free()
	await get_tree().create_timer(0.7).timeout
	if StringName(me.call("stage_top")) != &"" or cam.current:
		problems.append("a freed anchor left the stage live (top %s)" % me.call("stage_top"))
	# Quick pushes and pops at odd times for the rest of the 6 s.
	for index: int in 8:
		me.call("stage_push", &"t_quick", {"anchor": a if index % 2 == 0 else b, "blend_in": 0.05 * float(index % 4), "priority": 10})
		await get_tree().create_timer(0.07 + 0.03 * float(index % 3)).timeout
		me.call("stage_pop", &"t_quick", 0.04 * float(index % 3))
		await get_tree().create_timer(0.05).timeout
	await get_tree().create_timer(0.6).timeout
	_watch_frames = false
	a.queue_free()
	b.queue_free()
	var stats: Dictionary = _StageCam.log.duplicate()
	var ok := placed and problems.is_empty() and _null_frames == 0 and _wrong_current == 0 and int(stats["null_frames"]) == 0 and _frames > 100
	_step("camera", ok, "StageCam under CameraRig %s; %d frames, %d with no camera, %d with not exactly one of ours current; log %s; %s" % [placed, _frames, _null_frames, _wrong_current, JSON.stringify(stats), problems])


## A control lock holds movement and the held keys; its allowances pass.
func _lock_step() -> void:
	var me := _me()
	var start := me.global_position
	me.call("set_control_lock", &"nice_cite", true)
	Input.action_press(&"move_forward")
	await get_tree().create_timer(0.5).timeout
	var held_moved := _flat(me.global_position - start)
	var still_pressed := Input.is_action_pressed(&"move_forward")
	var allows := bool(me.call("control_allows", "jump")) and bool(me.call("control_allows", "look")) and not bool(me.call("control_allows", "primary")) and not bool(me.call("control_allows", "interact"))
	me.call("set_control_lock", &"van_seat", true)
	var stacked := not bool(me.call("control_allows", "jump")) and not bool(me.call("control_allows", "primary")) and bool(me.call("control_allows", "look"))
	me.call("set_control_lock", &"van_seat", false)
	me.call("set_control_lock", &"nice_cite", false)
	var unlocked := not bool(me.call("is_control_locked"))
	var free_start := me.global_position
	Input.action_press(&"move_forward")
	await get_tree().create_timer(0.4).timeout
	Input.action_release(&"move_forward")
	var free_moved := _flat(me.global_position - free_start)
	var ok := held_moved < 0.05 and not still_pressed and allows and stacked and unlocked and free_moved > 0.3
	_step("lock", ok, "locked: moved %.3f m with forward held (key released %s), allows jump+look not primary/interact %s, two locks allow only both's %s; unlocked moved %.2f m" % [held_moved, not still_pressed, allows, stacked, free_moved])


## register_gesture poses a body; an unknown name does nothing; anim speed 0 freezes it.
func _gesture_step() -> void:
	var me := _me()
	var body := me.get_node("Visual/CartoonBody")
	_CartoonBody.register_gesture("stage_test_reach", 1.2, func(on: Node3D, t01: float, _delta: float) -> void:
		var arm := on.call("pose_part", "arm_r") as Node3D
		if arm != null:
			arm.rotation.z = 2.4 * sin(t01 * PI))
	var known := bool(_CartoonBody.has_gesture("stage_test_reach")) and bool(_CartoonBody.has_gesture("wave")) and not bool(_CartoonBody.has_gesture("no_such_gesture"))
	var parts := true
	for part: String in ["hips", "torso", "head", "face", "arm_l", "arm_r", "leg_l", "leg_r", "prop_hand"]:
		parts = parts and body.call("pose_part", part) != null
	await get_tree().create_timer(0.1).timeout
	body.call("gesture", "no_such_gesture")
	var ignored := str(body.call("current_gesture")) != "no_such_gesture"
	body.call("gesture", "stage_test_reach")
	await get_tree().create_timer(0.6).timeout
	var arm := body.call("pose_part", "arm_r") as Node3D
	var raised := arm.rotation.z
	body.call("set_anim_speed", 0.0)
	await get_tree().physics_frame
	var frozen_arm := arm.transform
	var frozen_torso := (body.call("pose_part", "torso") as Node3D).transform
	await get_tree().create_timer(0.3).timeout
	var held := arm.transform.is_equal_approx(frozen_arm) and (body.call("pose_part", "torso") as Node3D).transform.is_equal_approx(frozen_torso)
	body.call("set_anim_speed", 1.0)
	await get_tree().create_timer(0.25).timeout
	var resumed := not arm.transform.is_equal_approx(frozen_arm)
	var ok := known and parts and ignored and raised > 1.5 and held and resumed
	_step("gesture", ok, "registered %s, parts %s, unknown ignored %s, arm raised to %.2f rad, frozen at speed 0 %s, moving again %s" % [known, parts, ignored, raised, held, resumed])


## The iris closes and opens on the server times given.
func _iris_step() -> void:
	var iris := get_tree().get_first_node_in_group("iris")
	if iris == null:
		_step("iris", false, "no iris")
		return
	var t0 := Net.server_time()
	iris.call("close", t0 + 0.2, 0.35, &"seal")
	await get_tree().create_timer(0.1).timeout
	var open_before := not bool(iris.call("is_closed")) and float(iris.call("amount_at", Net.server_time())) < 0.01
	await get_tree().create_timer(0.6).timeout
	var shut := bool(iris.call("is_closed"))
	iris.call("open", Net.server_time(), 0.35)
	await get_tree().create_timer(0.08).timeout
	# Opened at once, it still stays shut until IRIS_HOLD_MIN after it closed.
	var held := bool(iris.call("is_closed"))
	await get_tree().create_timer(0.7).timeout
	var open_after := not bool(iris.call("is_closed")) and float(iris.call("amount_at", Net.server_time())) <= 0.0
	iris.call("close", Net.server_time(), 0.2, &"door")
	await get_tree().create_timer(0.3).timeout
	var door := bool(iris.call("is_closed"))
	iris.call("open", Net.server_time(), 0.2)
	await get_tree().create_timer(0.8).timeout
	var ok := open_before and shut and held and open_after and door and not bool(iris.call("is_closed"))
	_step("iris", ok, "open before %s, shut on time %s, held shut %s, open again %s, the door shape %s" % [open_before, shut, held, open_after, door])


## The caption stack's layout at the normal and largest caption sizes, and captions off.
func _caption_step() -> void:
	var ui := get_tree().get_first_node_in_group("game_ui")
	var stack := get_tree().get_first_node_in_group("caption_stack")
	if stack == null or ui == null:
		_step("captions", false, "no caption stack")
		return
	Settings.reset_section("interface")
	var problems: Array[String] = []
	var obstacles_seen := 0
	for size_index: int in [1, Constants.CAPTION_SCALES.size() - 1]:
		Settings.set_value("interface", "caption_size", size_index, false)
		var ids: Array[int] = []
		ids.append(int(stack.call("push", &"radio", "RADIO: Courtesy Patrol to all units, we have a yard situation at this address.", 6.0, 1)))
		ids.append(int(stack.call("push", &"quip", "The lawn has requested additional documentation.", 6.0)))
		ids.append(int(stack.call("push", &"teammate", "They took Target. Target had the good rake.", 6.0, 2)))
		ids.append(int(stack.call("push", &"subtitle", "Ah-ah-ah! That hedge is not a permitted hiding structure.", 6.0)))
		# Settled: every slot open (the lines grow in, GROW_SECONDS).
		await get_tree().create_timer(0.4).timeout
		var rects: Array = stack.call("line_rects")
		var obstacles: Array = stack.call("obstacle_rects")
		obstacles_seen = maxi(obstacles_seen, obstacles.size())
		var screen := (stack as Control).get_viewport_rect()
		if rects.size() != Constants.CAPTION_STACK_MAX:
			problems.append("scale %.1f: %d lines shown, want %d" % [Settings.caption_scale(), rects.size(), Constants.CAPTION_STACK_MAX])
		for i: int in rects.size():
			var r: Rect2 = rects[i]
			if not screen.encloses(r):
				problems.append("scale %.1f: line %d %s leaves the screen" % [Settings.caption_scale(), i, r])
			for o: Rect2 in obstacles:
				if r.intersects(o):
					problems.append("scale %.1f: line %d %s covers %s" % [Settings.caption_scale(), i, r, o])
			for j: int in range(i + 1, rects.size()):
				if r.intersects(rects[j] as Rect2):
					problems.append("scale %.1f: lines %d and %d overlap" % [Settings.caption_scale(), i, j])
		# The fourth waits its turn and shows when one goes.
		stack.call("drop", ids[0])
		for frame: int in 4:
			await get_tree().process_frame
		var kinds: Array = (stack.call("shown_lines") as Array).map(func(line: Dictionary) -> String: return str(line["kind"]))
		if not kinds.has("subtitle"):
			problems.append("the waiting line didn't show after a drop: %s" % [kinds])
		for id: int in ids:
			stack.call("drop", id)
		await get_tree().create_timer(0.5).timeout
	if obstacles_seen < 2:
		problems.append("only %d of the goal line, job panel and heat meter were on screen to keep clear of" % obstacles_seen)
	# Captions off: spoken lines go, a teammate line stays.
	Settings.set_value("interface", "captions", false, false)
	var off_ids: Array[int] = []
	off_ids.append(int(stack.call("push", &"subtitle", "Upsy-daisy!", 3.0)))
	off_ids.append(int(stack.call("push", &"radio", "RADIO: testing, testing.", 3.0)))
	off_ids.append(int(stack.call("push", &"quip", "Industrial optimism. No refunds.", 3.0)))
	off_ids.append(int(stack.call("push", &"teammate", "They took Target. Target had the good rake.", 3.0)))
	await get_tree().process_frame
	var off_kinds: Array = (stack.call("shown_lines") as Array).map(func(line: Dictionary) -> String: return str(line["kind"]))
	if off_kinds != ["teammate"]:
		problems.append("captions off shows %s, want only the teammate line" % [off_kinds])
	for id: int in off_ids:
		stack.call("drop", id)
	Settings.reset_section("interface")
	_step("captions", problems.is_empty(), "caption scales 1.0 and %.1f, %d obstacles kept clear; %s" % [Constants.CAPTION_SCALES[Constants.CAPTION_SCALES.size() - 1], obstacles_seen, problems])


## The goal line dims in WARNING, CHASE and DEPARTING and comes back after.
func _goal_step() -> void:
	var ui := get_tree().get_first_node_in_group("game_ui")
	var goal := ui.get_node_or_null("JobGoal") as Control if ui != null else null
	var director := get_tree().get_first_node_in_group("run_director")
	if goal == null or director == null:
		_step("goal", false, "no goal line or director")
		return
	var me := Net.local_peer_id()
	var dimmed: Array[String] = []
	for phase: int in [1, 2, 3]:
		director.rpc("_rpc_phase", phase, Net.server_time(), "")
		await get_tree().create_timer(0.5).timeout
		if goal.modulate.a > 0.05 or not _UiRoot.goal_hidden_by_raid(get_tree(), me):
			dimmed.append("phase %d alpha %.2f" % [phase, goal.modulate.a])
	director.rpc("_rpc_phase", 0, Net.server_time(), "")
	await get_tree().create_timer(0.6).timeout
	var back := goal.modulate.a > 0.95 and not _UiRoot.goal_hidden_by_raid(get_tree(), me)
	_step("goal", dimmed.is_empty() and back, "dimmed in WARNING, CHASE, DEPARTING %s, back after %s (alpha %.2f)" % [dimmed.is_empty() if dimmed.is_empty() else dimmed, back, goal.modulate.a])


# ---------------------------------------------------------------- both peers

@rpc("authority", "call_local", "reliable")
func _rpc_stage(peer: int, base: Vector3, at: float) -> void:
	var body := _player(peer)
	if body == null:
		return
	_StageBody.reset_log()
	_anchor_base = base
	_anchor_at = at
	_anchor_seen_at = INF
	_move_anchor()
	_anchor_hitches = 0
	_pops = 0
	_last_owner = Vector3.INF
	_staged_peer = peer
	_staged_since = Net.server_time()
	_err_max = 0.0
	_err_samples = 0
	body.call("set_staged", _anchor, Transform3D(Basis.IDENTITY, Vector3(0.6, 0.0, 0.0)), STAGE_BLEND, &"escorted")


@rpc("authority", "call_local", "reliable")
func _rpc_unstage(_at: float) -> void:
	var body := _player(_staged_peer)
	if body == null:
		return
	_release_from = _drawn(body)
	_last_drawn = _release_from
	body.call("clear_staged")
	_release_at = Net.server_time()
	_release_jump = 0.0
	_release_step_max = 0.0
	if not Net.is_host():
		_client_report.call_deferred()


## The owner measures its own body against the anchor on physics ticks.
func _measure_owner() -> void:
	if _staged_peer == 0 or _staged_peer != Net.local_peer_id():
		return
	var body := _player(_staged_peer)
	if body == null:
		return
	if bool(body.call("is_staged")):
		if _last_owner != Vector3.INF and body.global_position.distance_to(_last_owner) > Constants.STAGE_MAX_STEP_METERS and not _anchor_jumped:
			_pops += 1
		_last_owner = body.global_position
		if Net.server_time() - _staged_since > STAGE_BLEND + 0.05:
			var want := (_anchor.global_transform * Transform3D(Basis.IDENTITY, Vector3(0.6, 0.0, 0.0))).origin
			_err_max = maxf(_err_max, body.global_position.distance_to(want))
			_err_samples += 1
	elif _release_at != INF and Net.server_time() - _release_at < RELEASE_WATCH_SECONDS:
		# Across the ground: the body settles onto the floor under gravity as it should.
		_release_jump = maxf(_release_jump, _flat(body.global_position - _release_from))


## Other peers measure the body they draw against their anchor, every frame.
func _measure_view() -> void:
	if _staged_peer == 0 or _staged_peer == Net.local_peer_id():
		return
	var body := _player(_staged_peer)
	if body == null:
		return
	var drawn := _drawn(body)
	var anchor_now := _anchor.get_global_transform_interpolated().origin
	var anchor_step := anchor_now.distance_to(_last_anchor_view) if _last_anchor_view != Vector3.INF else 0.0
	_last_anchor_view = anchor_now
	if bool(body.call("is_staged")):
		if _last_drawn != Vector3.INF and drawn.distance_to(_last_drawn) > Constants.STAGE_MAX_STEP_METERS and anchor_step < Constants.STAGE_MAX_STEP_METERS * 0.5:
			_pops += 1
		if Net.server_time() - _staged_since > STAGE_BLEND + 0.05:
			var want := (_anchor.get_global_transform_interpolated() * Transform3D(Basis.IDENTITY, Vector3(0.6, 0.0, 0.0))).origin
			_err_max = maxf(_err_max, drawn.distance_to(want))
			_err_samples += 1
	elif _release_at != INF and Net.server_time() - _release_at < RELEASE_WATCH_SECONDS:
		if _last_drawn != Vector3.INF:
			_release_step_max = maxf(_release_step_max, drawn.distance_to(_last_drawn))
	_last_drawn = drawn


func _client_report() -> void:
	await get_tree().create_timer(RELEASE_WATCH_SECONDS + 0.1).timeout
	var stats: Dictionary = _StageBody.log.duplicate()
	var cam_stats: Dictionary = _StageCam.log.duplicate()
	var ok := _err_samples > 30 and _err_max <= STAGE_TOLERANCE and _pops == 0 and _release_jump <= 0.01 and int(cam_stats["null_frames"]) == 0
	var report := {"ok": ok, "err_max": _err_max, "samples": _err_samples, "pops": _pops, "anchor_hitches": _anchor_hitches, "steps_over": stats["steps_over"], "max_step": stats["max_step_m"], "release_jump": _release_jump, "null_frames": cam_stats["null_frames"]}
	print("[StageTest] client: my staged body within %.4f m of its anchor over %d ticks, %d steps over %.2f m its anchor didn't make (StageBody log: %d over, max %.3f; anchor hitches %d), released with a %.4f m slide, %d frames with no camera: %s" % [_err_max, _err_samples, _pops, Constants.STAGE_MAX_STEP_METERS, int(stats["steps_over"]), float(stats["max_step_m"]), _anchor_hitches, _release_jump, int(cam_stats["null_frames"]), ok])
	result = report.duplicate()
	result["done"] = true
	_rpc_report.rpc_id(1, report)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_report(report: Dictionary) -> void:
	if Net.is_host():
		_report = report


# ---------------------------------------------------------------- helpers

func _watch_cameras() -> void:
	if not _watch_frames:
		return
	var me := _me()
	if me == null:
		return
	_frames += 1
	if get_viewport().get_camera_3d() == null:
		_null_frames += 1
	var current := 0
	for path: String in ["Visual/Head/FirstPerson", "CameraRig/OverShoulder", "CameraRig/StageCam"]:
		var camera := me.get_node_or_null(path) as Camera3D
		if camera != null and camera.current:
			current += 1
	if current != 1:
		_wrong_current += 1


func _drawn(body: Node3D) -> Vector3:
	if body.is_multiplayer_authority():
		return body.global_position
	var visual := body.get_node_or_null("Visual") as Node3D
	return visual.global_position if visual != null else body.global_position


func _marker(at: Vector3) -> Node3D:
	var node := Node3D.new()
	add_child(node)
	node.global_position = at
	return node


func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


func _step(step_name: String, ok: bool, detail: String) -> void:
	_steps[step_name] = ok
	print("[StageTest] %s: %s (%s)" % [step_name, detail, "ok" if ok else "FAIL"])


func _finish(why: String) -> void:
	if why != "":
		_steps["setup"] = false
		print("[StageTest] %s" % why)
	var ok := not _steps.is_empty()
	for step: String in _steps:
		ok = ok and bool(_steps[step])
	result = {"ok": ok, "done": true, "steps": _steps.duplicate(), "client": _report.duplicate()}
	print("[StageTest] all ok: %s" % ok)


func _me() -> Node3D:
	return _player(Net.local_peer_id())


func _mate() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name != str(Net.local_peer_id()):
			return node as Node3D
	return null


func _player(peer: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer):
			return node as Node3D
	return null
