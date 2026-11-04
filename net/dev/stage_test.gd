extends Node

## --stage-test (R2 chunk 1, gap-specs/nice_boys.json; port 7826, host plus a
## Target client, both with --sim-lag=150 --stage-test). The seams every R2 chunk
## builds on, checked in the running game:
##   staged    the host stages the client's body on a moving anchor (one reliable
##             RPC, every peer places it): within STAGE_TOLERANCE of the anchor on
##             both peers every tick after the blend, no tick over
##             STAGE_MAX_STEP_METERS, and released mid-move with no jump (the owner
##             stays put; the host's view eases back without a step over it).
##             It starts once the client's clock has settled (a join stall
##             snaps it by a second or more, and the anchor runs on that time).
##   agree     the client's own body against the host's anchor at the same
##             wall-clock moment (both run on this machine): within
##             CROSS_TOLERANCE, so the peers really agree, not each with itself.
##   freed     an anchor freed under a staged body (a van left) still releases
##             it: standing pose, no collision exception, interpolation back.
##   camera    StageCam lives under CameraRig, not Visual; nested pushes, an orbit
##             with clamped look, a toggle while a shot is live, pops, a cut and an
##             anchor freed under a shot: exactly one current camera (and never
##             none) on every frame for about 6 s. Then the rig switched off
##             under a live shot (the crossing camera): no push or pop takes
##             the view back until it's switched on again.
##   lock      a control lock holds movement and the held keys, lets its
##             allowances through, never eats a click meant for a window's
##             button, and movement comes back when it's lifted.
##   gesture   register_gesture poses a body by name; an unknown name is a no-op;
##             set_anim_speed(0) freezes the body mid-gesture.
##   iris      closes and opens on the server times given, held shut IRIS_HOLD_MIN.
##   captions  4 lines at the normal and the largest caption size: 3 show, none
##             touches the goal line, the job panel or the heat meter or each
##             other; captions off hides every line (subtitles, quips, radio
##             and teammate lines alike, critic.md C19).
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
## Both peers run on this machine, so the system clock lines their samples up:
## where the client put its own body at a wall-clock moment, against where the
## host's clock says the anchor was at that same moment.
const CROSS_TOLERANCE: float = 0.05
## The client's clock estimate must hold this still (and this long) before the
## stage starts, so the step measures the stage and not the join settling.
const CLOCK_SETTLE_DRIFT: float = 0.01
const CLOCK_SETTLE_SECONDS: float = 1.5
const CLOCK_SETTLE_WAIT: float = 20.0
## A ping slower than this (the join's loading stalls) can't be trusted yet: the
## first good one after it moves the estimate by as much as the stall was long.
const CLOCK_SETTLE_RTT: float = 0.6
## Every second physics tick of the client's staged body goes in its report.
const WALL_SAMPLE_EVERY: int = 2
## The system clock read either side of a server time: further apart than this
## (s), the process was switched out between them and the pair can't date it.
const WALL_READ_MAX: float = 0.002

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
var _anchor_seen_at: float = INF
var _anchor_local_at: float = 0.0
## Client: [system unix time, body position] on its physics ticks after the blend.
var _wall_samples: Array = []
## The system clock at the moment this tick's anchor time was read, and whether
## the two reads round it came within WALL_READ_MAX (else the tick isn't sampled).
var _anchor_wall: float = 0.0
var _anchor_wall_sure: bool = false
var _wall_tick: int = 0
## Client: watching its clock offset settle; host: told it has.
var _clock_settled: bool = false
var _offset_seen: float = INF
var _offset_still_since: float = INF


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
	_watch_clock()
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
	# The system clock read on both sides of the server time the anchor is placed
	# by: the agree step pairs the body with this moment, not one read later in the
	# tick (fx-net: a loaded machine can switch this process out between the two
	# for a scheduler slice, 27 ms, which the step read as the clocks disagreeing).
	var wall_before := Time.get_unix_time_from_system()
	var placed_at := Net.server_time()
	var wall_after := Time.get_unix_time_from_system()
	_anchor_wall = (wall_before + wall_after) * 0.5
	_anchor_wall_sure = wall_after - wall_before <= WALL_READ_MAX
	_anchor.global_transform = _anchor_xform(placed_at)
	var at := _anchor.global_position
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


## The anchor at a server time (the same function on every peer).
func _anchor_xform(server_t: float) -> Transform3D:
	var t := maxf(0.0, server_t - _anchor_at)
	var angle := t * ANCHOR_RATE
	var at := _anchor_base + Vector3(sin(angle) * ANCHOR_RADIUS, 0.0, (1.0 - cos(angle)) * ANCHOR_RADIUS)
	var tangent := Vector3(cos(angle), 0.0, sin(angle))
	return Transform3D(Basis.looking_at(tangent, Vector3.UP), at)


func _physics_process(_delta: float) -> void:
	_measure_owner()


## Client: tell the host once the clock estimate has stopped moving.
func _watch_clock() -> void:
	if Net.is_host() or _clock_settled or not _started:
		return
	var offset := Net.clock_offset_seconds()
	var now := Time.get_ticks_msec() / 1000.0
	if _offset_seen == INF or absf(offset - _offset_seen) > CLOCK_SETTLE_DRIFT or Net.clock_rtt_seconds() > CLOCK_SETTLE_RTT:
		_offset_seen = offset
		_offset_still_since = now
		return
	if now - _offset_still_since >= CLOCK_SETTLE_SECONDS:
		_clock_settled = true
		print("[StageTest] client: clock offset settled at %.3f s (last round trip %.0f ms)" % [offset, Net.clock_rtt_seconds() * 1000.0])
		_rpc_settled.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_settled() -> void:
	if Net.is_host():
		_clock_settled = true


# ---------------------------------------------------------------- host

func _run_host() -> void:
	var waited := 0.0
	while _mate() == null and waited < CLIENT_WAIT_SECONDS:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	if _mate() == null:
		_finish("the Target client never joined")
		return
	# Past the join's loading hitches, so the moving anchor isn't caught mid-stall,
	# and past the client's clock settling: its first good ping can snap its
	# server time by a second or more, and the anchor is a function of that time.
	await get_tree().create_timer(4.0).timeout
	var settle_waited := 0.0
	while not _clock_settled and settle_waited < CLOCK_SETTLE_WAIT:
		await get_tree().create_timer(0.25).timeout
		settle_waited += 0.25
	if not _clock_settled:
		_finish("the Target client's clock never settled")
		return
	await _staged_step()
	await _freed_step()
	await _camera_step()
	await _pivot_step()
	await _lock_step()
	await _gesture_step()
	await _iris_step()
	await _boarding_release_step()
	await _caption_step()
	await _goal_step()
	var waited_report := 0.0
	while _report.is_empty() and waited_report < REPORT_WAIT_SECONDS:
		await get_tree().create_timer(0.25).timeout
		waited_report += 0.25
	_cross_step()
	var shown := _report.duplicate()
	shown.erase("wall")
	_step("client", bool(_report.get("ok", false)), "client report %s" % JSON.stringify(shown))
	_finish("")


## The two peers against each other: where the client put its own staged body at
## a wall-clock moment, against where the host's anchor was at that moment.
func _cross_step() -> void:
	var samples: Array = _report.get("wall", [])
	# This machine's system clock minus the host's server time: the tightest of a
	# few reads with the system clock either side (see _move_anchor).
	var wall_minus_server := 0.0
	var tightest := INF
	for _read: int in 16:
		var wall_before := Time.get_unix_time_from_system()
		var server := Net.server_time()
		var wall_after := Time.get_unix_time_from_system()
		if wall_after - wall_before < tightest:
			tightest = wall_after - wall_before
			wall_minus_server = (wall_before + wall_after) * 0.5 - server
	var offset := Transform3D(Basis.IDENTITY, Vector3(0.6, 0.0, 0.0))
	var err_max := 0.0
	var err_sum := 0.0
	var worst_at := ""
	for index: int in samples.size():
		var pair: Array = samples[index]
		var want := (_anchor_xform(float(pair[0]) - wall_minus_server) * offset).origin
		var err := (pair[1] as Vector3).distance_to(want)
		if err > err_max:
			# The client's clock then: how far its applied offset trailed its estimate,
			# and how wide the estimate's bounds were (net/clock_sync.gd).
			var clock: Vector2 = pair[2] if pair.size() > 2 else Vector2.ZERO
			worst_at = "sample %d of %d, client clock trailing its estimate by %.1f ms, bounds %.1f ms wide" % [index, samples.size(), clock.x * 1000.0, clock.y * 1000.0]
		err_max = maxf(err_max, err)
		err_sum += err
	var mean := err_sum / float(samples.size()) if not samples.is_empty() else 0.0
	var ok := samples.size() > 30 and err_max <= CROSS_TOLERANCE
	_step("agree", ok, "the client's own staged body against the host's anchor at the same moment: worst %.3f m (%s), mean %.3f m over %d samples (want <= %.2f)" % [err_max, worst_at, mean, samples.size(), CROSS_TOLERANCE])


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
	_step("staged", ok, "the host draws the client's staged body within %.3f m of its anchor over %d frames (want <= %.2f), %d frame steps over %.2f m (StageBody log %s, anchor hitches %d), release: largest frame step %.3f m (want <= %.2f)" % [_err_max, _err_samples, STAGE_TOLERANCE, _pops, Constants.STAGE_MAX_STEP_METERS, JSON.stringify(stats), _anchor_hitches, _release_step_max, RELEASE_STEP_MAX])


## An anchor freed under a staged body (a van left): the body still gets a full
## release, on the owner and on a peer that only draws it. Local to the host (no
## RPC): the host's own body, and its view of the client's.
func _freed_step() -> void:
	var problems: Array[String] = []
	for body: Node3D in [_me(), _mate()]:
		var who := "owner" if body.is_multiplayer_authority() else "view"
		var exceptions_before := (body as PhysicsBody3D).get_collision_exceptions().size()
		var carrier := AnimatableBody3D.new()
		add_child(carrier)
		carrier.global_position = body.global_position + Vector3(0.0, 0.0, 0.5)
		var anchor := Node3D.new()
		carrier.add_child(anchor)
		body.call("set_staged", anchor, Transform3D.IDENTITY, 0.1, &"escorted")
		await get_tree().create_timer(0.3).timeout
		var excepted := (body as PhysicsBody3D).get_collision_exceptions().has(carrier)
		carrier.queue_free()
		await get_tree().create_timer(Constants.STAGE_RELEASE_BLEND + 0.2).timeout
		var visual := body.get_node("Visual") as Node3D
		if bool(body.call("is_staged")):
			problems.append("%s still staged" % who)
		if StringName(body.get("_stage_pose")) != &"stand":
			problems.append("%s left in pose %s" % [who, body.get("_stage_pose")])
		if not excepted:
			problems.append("%s never excepted from its carrier" % who)
		if (body as PhysicsBody3D).get_collision_exceptions().size() > exceptions_before:
			problems.append("%s kept a collision exception" % who)
		if visual.physics_interpolation_mode != Node.PHYSICS_INTERPOLATION_MODE_INHERIT:
			problems.append("%s visual interpolation left %d" % [who, visual.physics_interpolation_mode])
		# A late clear from the caller after that is harmless.
		body.call("clear_staged")
	_step("freed", problems.is_empty(), "an anchor freed under a staged body releases it fully on the owner and a viewer: %s" % [problems])


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
	# Something else takes the view under a live shot (the Border Return camera,
	# player.set_crossing_view): the shot never takes it back, pushed or popped.
	var other := Camera3D.new()
	_marker(me.global_position).add_child(other)
	me.call("stage_push", &"t_away", {"anchor": a, "blend_in": 0.2, "priority": 10})
	await get_tree().create_timer(0.1).timeout
	other.make_current()
	rig.call("set_active", false)
	await get_tree().process_frame
	if cam.current or not other.current:
		problems.append("an inactive rig's live shot kept the view")
	me.call("stage_push", &"t_away2", {"anchor": b, "blend_in": 0.1, "priority": 20})
	me.call("stage_pop", &"t_away2", 0.1)
	me.call("stage_pop", &"t_away", 0.2)
	await get_tree().create_timer(0.4).timeout
	if not other.current or cam.current or StringName(me.call("stage_top")) != &"":
		problems.append("a shot pushed or popped while the rig was off took the view from the other camera")
	rig.call("set_active", true)
	await get_tree().process_frame
	if not (rig.call("current_base_camera") as Camera3D).current:
		problems.append("the rig didn't take its view back when set active again")
	other.get_parent().queue_free()
	a.queue_free()
	b.queue_free()
	var stats: Dictionary = _StageCam.log.duplicate()
	var ok := placed and problems.is_empty() and _null_frames == 0 and _wrong_current == 0 and int(stats["null_frames"]) == 0 and _frames > 100
	_step("camera", ok, "StageCam under CameraRig %s; %d frames, %d with no camera, %d with not exactly one of ours current; log %s; %s" % [placed, _frames, _null_frames, _wrong_current, JSON.stringify(stats), problems])


## R2b: a shot about someone (a pivot) swings round them instead of through them,
## never moves faster than STAGE_CAM_MAX_SPEED, and keeps its eye on this side
## of a wall put between the pivot and where the shot wants to be.
func _pivot_step() -> void:
	var me := _me()
	var cam := me.call("stage_cam") as Camera3D
	if cam == null:
		_step("pivot", false, "no StageCam")
		return
	var ahead := -me.global_basis.z
	ahead.y = 0.0
	ahead = ahead.normalized()
	var side := ahead.cross(Vector3.UP).normalized()
	# A: the shot wants the far side of someone 3 m ahead of you. A straight blend
	# goes through them (about 0.2 m off the pivot); a swing round keeps its
	# distance. A wide wall (no corner to graze) 1.6 m beyond them: the eye settles
	# on this side of it and no frame of the swing is past its face.
	var pivot_a := me.global_position + ahead * 3.0 + Vector3.UP * 1.4
	var a: Dictionary = await _pivot_run(cam, pivot_a, pivot_a + ahead * 3.0, ahead, 1.6)
	# B: the gotcha's case: someone right in front of you, the shot to the side,
	# and a wall just behind you. The swing pulls back first; the eye drawn on
	# every frame of it is kept clear, not just where it ends.
	var pivot_b := me.global_position + ahead * 0.55 + Vector3.UP * Constants.CATCH_CAM_HEIGHT
	var start := get_viewport().get_camera_3d().global_position if get_viewport().get_camera_3d() != null else me.global_position
	var behind := maxf(1.6, (start - pivot_b).dot(-ahead) + 1.0)
	var b: Dictionary = await _pivot_run(cam, pivot_b, pivot_b + side * 3.0, -ahead, behind)
	var face_a := 1.6 - 0.15
	var settled_ok := float(a["settled"]) < 1.6 - Constants.STAGE_CAM_RADIUS + 0.05
	var ok := float(a["nearest"]) > 1.0 and int(a["speed_over"]) == 0 and int(a["past_wall"]) == 0 and settled_ok \
		and int(b["speed_over"]) == 0 and int(b["past_wall"]) == 0
	_step("pivot", ok, "round: closest to the pivot %.2f m (> 1.0), fastest %.1f m/s (%d frames over %.1f), %d frames past the wall, settled %.2f m from it behind a wall face at %.2f m; back to a wall %.2f m behind: deepest %.2f m, %d frames past it, fastest %.1f m/s (%d over)" % [
		a["nearest"], a["fastest"], a["speed_over"], Constants.STAGE_CAM_MAX_SPEED, a["past_wall"], a["settled"], face_a,
		behind - 0.15, b["deepest"], b["past_wall"], b["fastest"], b["speed_over"]])


## One pivot shot from the view you have now: the eye (looking at the pivot) at
## `wanted`, a 10 m wide wall `wall_at` m from the pivot along `wall_dir`. Reports
## the closest it came to the pivot, how fast it moved, how many frames the eye
## was past the wall's near face, how deep along wall_dir it went, where it settled.
func _pivot_run(cam: Camera3D, pivot: Vector3, wanted: Vector3, wall_dir: Vector3, wall_at: float) -> Dictionary:
	var me := _me()
	var eye := _marker(wanted)
	eye.global_transform = Transform3D(Basis.looking_at(pivot - wanted, Vector3.UP), wanted)
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.0, 4.0, 0.3)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	wall.global_transform = Transform3D(Basis.looking_at(wall_dir, Vector3.UP), pivot + wall_dir * wall_at)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var face := wall_at - 0.15
	var nearest := INF
	var fastest := 0.0
	var speed_over := 0
	var past := 0
	var deepest := -INF
	# A half turn at 3 m in 0.8 s is faster than STAGE_CAM_MAX_SPEED: it's paced
	# along its arc (slowed), never clamped into a chord through the pivot.
	me.call("stage_push", &"t_pivot", {"anchor": eye, "blend_in": 0.8, "priority": 10, "pivot": pivot, "collide": true})
	var last := cam.global_position
	var until := Time.get_ticks_msec() + 2600
	var last_delta := 0.0
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
		var now := cam.global_position
		var step := now.distance_to(last)
		# This node reads the camera before it moves each frame (StageCam runs late),
		# so a step can belong to the frame before: allow the longer of the two.
		var delta := maxf(maxf(get_process_delta_time(), last_delta), 0.001)
		last_delta = get_process_delta_time()
		fastest = maxf(fastest, step / delta)
		if step > Constants.STAGE_CAM_MAX_SPEED * delta + 0.02:
			speed_over += 1
		nearest = minf(nearest, now.distance_to(pivot))
		var depth := (now - pivot).dot(wall_dir)
		deepest = maxf(deepest, depth)
		if depth > face:
			past += 1
		last = now
	var settled := cam.global_position.distance_to(pivot)
	me.call("stage_pop", &"t_pivot", 0.0)
	wall.queue_free()
	eye.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	return {"nearest": nearest, "fastest": fastest, "speed_over": speed_over, "past_wall": past, "deepest": deepest, "settled": settled}


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
	# A lock never eats a click meant for a window's button (left click is
	# "primary", which nice_cite holds back): the mouse is free, so the GUI gets it.
	var clicked := await _click_through_lock()
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
	var ok := held_moved < 0.05 and not still_pressed and allows and clicked and stacked and unlocked and free_moved > 0.3
	_step("lock", ok, "locked: moved %.3f m with forward held (key released %s), allows jump+look not primary/interact %s, a window button still takes a click %s, two locks allow only both's %s; unlocked moved %.2f m" % [held_moved, not still_pressed, allows, clicked, stacked, free_moved])


## Under a lock with the mouse free (a window up), a left click reaches a button.
func _click_through_lock() -> bool:
	var mode_before := Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var layer := CanvasLayer.new()
	layer.layer = 128
	add_child(layer)
	var button := Button.new()
	button.position = Vector2(20.0, 20.0)
	button.size = Vector2(120.0, 40.0)
	layer.add_child(button)
	var hits: Array[int] = [0]
	button.pressed.connect(func() -> void: hits[0] += 1)
	await get_tree().process_frame
	for down: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = down
		# In the viewport's own (canvas) coordinates: a headless window is tiny and scaled.
		click.position = button.get_global_rect().get_center()
		click.global_position = click.position
		get_viewport().push_input(click, true)
		await get_tree().process_frame
	layer.queue_free()
	Input.mouse_mode = mode_before
	return hits[0] == 1


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


## R2b: freed (or reset) while boarding, the iris the boarding asked for never
## stays shut: a close that hasn't started never shows, one under way opens again.
func _boarding_release_step() -> void:
	var iris := get_tree().get_first_node_in_group("iris")
	var me := _me()
	if iris == null or me == null:
		_step("boarding release", false, "no iris or no player")
		return
	var encounter := get_tree().get_first_node_in_group("nice_encounter")
	var own := encounter == null
	if own:
		encounter = (load("res://net/run_events/encounter.gd") as GDScript).new()
		encounter.name = "StageTestEncounter"
		add_child(encounter)
	var anchor := _marker(me.global_position + Vector3(0.0, 2.0, 3.0))
	var me_id := Net.local_peer_id()
	# Freed before the close starts.
	me.call("stage_push", &"t_board", {"anchor": anchor, "blend_in": 0.0, "priority": 10})
	encounter.call("_board_behind_iris", me)
	await get_tree().create_timer(0.1).timeout
	encounter.call("_clear_peer", me_id)
	var shown_early := 0.0
	var until := Time.get_ticks_msec() + int((Constants.BOARD_IRIS_DELAY + Constants.IRIS_CLOSE + 0.3) * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
		shown_early = maxf(shown_early, float(iris.call("amount_at", Net.server_time())))
	# Freed halfway through the close.
	me.call("stage_push", &"t_board", {"anchor": anchor, "blend_in": 0.0, "priority": 10})
	encounter.call("_board_behind_iris", me)
	await get_tree().create_timer(Constants.BOARD_IRIS_DELAY + Constants.IRIS_CLOSE * 0.5).timeout
	var closing := float(iris.call("amount_at", Net.server_time())) > 0.0
	encounter.call("_clear_peer", me_id)
	await get_tree().create_timer(Constants.IRIS_CLOSE + Constants.IRIS_HOLD_MIN + Constants.IRIS_OPEN + 0.4).timeout
	var reopened := not bool(iris.call("is_closed")) and float(iris.call("amount_at", Net.server_time())) <= 0.0
	me.call("stage_pop", &"t_board", 0.0)
	anchor.queue_free()
	if own:
		encounter.queue_free()
	await get_tree().process_frame
	var ok := shown_early < 0.01 and closing and reopened
	_step("boarding release", ok, "freed before the close: it showed %.2f (want 0); freed mid-close (closing %s): open again %s" % [shown_early, closing, reopened])


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
	# Captions off: every line goes, a teammate line too.
	Settings.set_value("interface", "captions", false, false)
	var off_ids: Array[int] = []
	off_ids.append(int(stack.call("push", &"subtitle", "Upsy-daisy!", 3.0)))
	off_ids.append(int(stack.call("push", &"radio", "RADIO: testing, testing.", 3.0)))
	off_ids.append(int(stack.call("push", &"quip", "Industrial optimism. No refunds.", 3.0)))
	off_ids.append(int(stack.call("push", &"teammate", "They took Target. Target had the good rake.", 3.0)))
	await get_tree().process_frame
	var off_kinds: Array = (stack.call("shown_lines") as Array).map(func(line: Dictionary) -> String: return str(line["kind"]))
	if not off_kinds.is_empty():
		problems.append("captions off shows %s, want none" % [off_kinds])
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
	# The director's own tick would end a DEPARTING with no van or crew at once
	# (R2:2), so it holds still while the test sets the phases by hand.
	var was_processing := director.is_processing()
	director.set_process(false)
	for phase: int in [1, 2, 3]:
		director.rpc("_rpc_phase", phase, Net.server_time(), "")
		await get_tree().create_timer(0.5).timeout
		if goal.modulate.a > 0.05 or not _UiRoot.goal_hidden_by_raid(get_tree(), me):
			dimmed.append("phase %d alpha %.2f" % [phase, goal.modulate.a])
	director.rpc("_rpc_phase", 0, Net.server_time(), "")
	director.set_process(was_processing)
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
	_wall_samples.clear()
	_wall_tick = 0
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
		# Every step over the limit counts, a jump of the anchor's clock included:
		# the player sees the pop whatever caused it.
		if _last_owner != Vector3.INF and body.global_position.distance_to(_last_owner) > Constants.STAGE_MAX_STEP_METERS:
			_pops += 1
		_last_owner = body.global_position
		if Net.server_time() - _staged_since > STAGE_BLEND + 0.05:
			var want := (_anchor.global_transform * Transform3D(Basis.IDENTITY, Vector3(0.6, 0.0, 0.0))).origin
			_err_max = maxf(_err_max, body.global_position.distance_to(want))
			_err_samples += 1
			_wall_tick += 1
			if _wall_tick % WALL_SAMPLE_EVERY == 0 and _anchor_wall_sure:
				var clock: RefCounted = Net.get("_clock")
				_wall_samples.append([_anchor_wall, body.global_position, clock.call("lag_and_width") if clock != null else Vector2.ZERO])
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
	if bool(body.call("is_staged")):
		if _last_drawn != Vector3.INF and drawn.distance_to(_last_drawn) > Constants.STAGE_MAX_STEP_METERS:
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
	var report := {"ok": ok, "err_max": _err_max, "samples": _err_samples, "pops": _pops, "anchor_hitches": _anchor_hitches, "steps_over": stats["steps_over"], "max_step": stats["max_step_m"], "release_jump": _release_jump, "null_frames": cam_stats["null_frames"], "wall": _wall_samples.duplicate()}
	print("[StageTest] client: my staged body within %.4f m of its anchor over %d ticks, %d ticks stepping over %.2f m (StageBody log: %d over, max %.3f; anchor hitches %d), released with a %.4f m slide, %d frames with no camera: %s" % [_err_max, _err_samples, _pops, Constants.STAGE_MAX_STEP_METERS, int(stats["steps_over"]), float(stats["max_step_m"]), _anchor_hitches, _release_jump, int(cam_stats["null_frames"]), ok])
	result = report.duplicate()
	result.erase("wall")
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
