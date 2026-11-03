extends Node3D

## Authority: the owner predicts its own dives and climb-outs; everything else
## here is local presentation from replicated state. Hiding, as the hider and as
## everyone watching them (R2 chunk 3, docs/GAME.md "Hiding"). A child of the
## player ("HideView"), made on first use by player.gd.
##
## - Getting in: E plays the dive at once on your own screen (a hop over a hedge,
##   a vault into a bin, a step through the shed door, a cannonball into a pile);
##   the host confirms. Refused, you bonk off the outside and land where you
##   started. The body follows a curve; nothing teleports.
## - The view stays live: your camera is never under a hidden node. The body,
##   head, nameplate and first-person arms stop being drawn (set_body_drawn), the
##   camera moves to the spot's eye (a StageCam shot, R2 chunk 1) and turns with
##   the mouse within Constants.HIDE_YAW_CLAMP of the spot's facing. Third person
##   orbits the spot instead. Hold secondary to peek: the eye rises, the view
##   widens, and everyone sees the lid lift, the door crack or the eyes glint.
## - Inside, the world is muffled (music and effects through a low-pass), your
##   voice chat is muffled for everyone, and during a chase the music asks for
##   its "hide" section (audio, R2 chunk 5).
## - Getting out: E bursts out on the clear side nearest where you look (the host
##   sweeps for room), with a leaf on your head for a few seconds.
## - Found by a NICE BOY: lifted out toward him into the gotcha.
## - The pile: a taller, darker mound with your shoe poking out, and the same
##   suspicion and inspection a hide spot has (player.gd's inspect_* methods).

const _HideSpotLook = preload("res://props/hide_spot.gd")
const _HideFrame = preload("res://player/hide_frame.gd")
const _Buses = preload("res://audio/buses.gd")
const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const _CartoonBody = preload("res://player/cartoon_body.gd")
const _HideGestures = preload("res://player/hide_gestures.gd")

enum Move { NONE, DIVE, EXIT, BONK, PULL, PILE_DIVE, PILE_POP }

## The bus a hider's voice goes through (a low-pass, then the Voice bus).
const VOICE_MUFFLED := &"VoiceMuffled"
const SHOT_PEEK := &"hide_peek"
const SHOT_ORBIT := &"hide_orbit"
const SHOT_PRIORITY: int = 20
## Closer than this to a shed's doorstep (m), the step goes straight in.
const SHED_DOORSTEP_SNAP: float = 0.25
## The pile's eye: this high over the body and this far ahead (m).
const PILE_EYE_HEIGHT: float = 0.42
const PILE_EYE_AHEAD: float = 0.3

var player: CharacterBody3D

var _move: Move = Move.NONE
var _move_t: float = 0.0
var _move_length: float = 0.0
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _peak: float = 0.0
## Where the dive in front of the camera turned around (refusals bounce from here).
var _start := Vector3.ZERO
## A shed step from off to one side goes by the doorstep first (INF: straight).
var _via := Vector3.INF
## Owner: the spot a dive is waiting on the host for, and since when (msec).
var _waiting: Node3D
var _waiting_since: int = 0
var _waiting_pile: bool = false
## Every peer: the spot this player is in, its side and slot, and when the host
## put them there (server time).
var _spot: Node3D
var _side: int = 0
var _slot: int = 0
var _in_at: float = -1000.0
## Every peer but the owner: the body stops being drawn at this msec (or when it
## reaches inside).
var _hide_by_ms: int = 0
var _shot: StringName = &""
var _shot_first_person: bool = true
var _peek: float = 0.0
var _peeking_shot: bool = false
var _frame_layer: CanvasLayer
var _frame_fade: float = 0.0
## Every peer but the owner: when this player went into a pile (local msec).
var _pile_since_ms: int = 0
var _frame: Control
var _muffled: bool = false
var _sfx_filter: AudioEffectLowPassFilter
var _voice_muffled: bool = false
var _mound: Node3D
var _pile_anchor: Marker3D
var _hat_leaf: Node3D
var _hat_left: float = 0.0
var _last_yaw: float = INF
var _turn_rate: float = 0.0
var _rng := RandomNumberGenerator.new()
## Host only, for the pile: suspicion and the inspection.
var _pile_suspicion: float = 0.0
var _pile_used_at: float = -1000.0
var _pile_inspected_at: float = -1000.0
var _pile_inspector: Node
var _pile_inspect_began: float = -1.0
var _pile_last_seen := Vector3.INF
var _pile_rustle_cool: float = 0.0


func _ready() -> void:
	_rng.randomize()
	_HideGestures.register()


func is_owner_view() -> bool:
	return player != null and player.is_multiplayer_authority()


## True while the body is on a dive, climb-out, bonk or lift: player.gd's
## movement leaves it alone.
func is_moving() -> bool:
	return _move != Move.NONE


## True while waiting on the host for a dive (E is ignored meanwhile).
func is_waiting() -> bool:
	return _waiting != null or _waiting_pile


# ---------------------------------------------------------------- owner: in and out

## E by a free spot: dive now, ask the host (player.gd sends the request).
func predict_enter(spot: Node3D) -> void:
	if not is_owner_view() or is_moving() or spot == null:
		return
	var side := int(spot.call("side_toward", player.global_position))
	var slot := int(spot.call("free_slot")) if spot.has_method("free_slot") else 0
	_waiting = spot
	_waiting_since = Time.get_ticks_msec()
	if spot.has_method("predict_enter"):
		spot.call("predict_enter", player.name.to_int(), side)
	_begin_dive(spot, side, slot)


## E on a pile: the cannonball now; the host turns it into hiding (leaf_field.gd).
func predict_pile_dive() -> void:
	if not is_owner_view() or is_moving():
		return
	_waiting_pile = true
	_waiting_since = Time.get_ticks_msec()
	_from = player.global_position
	_start = _from
	var ahead := -player.global_basis.z
	ahead.y = 0.0
	_to = _from + ahead.normalized() * 0.25
	_peak = 0.75
	_start_move(Move.PILE_DIVE, Constants.HIDE_ENTER_SECONDS)
	_gesture("pile_cannonball", "startle")
	player.call("say_to_all", "vo_heave")
	_push_pile_shot()


## E inside: burst out toward the side the view faces (the host decides).
func request_exit() -> void:
	if not is_owner_view() or is_moving() or _spot == null:
		return
	var ahead := _view_forward()
	var hint := int(_spot.call("side_toward", _spot.global_position + ahead * 10.0))
	var slot := _slot
	var exit_to: Vector3 = _spot.call("entry_point", hint, slot)
	_begin_exit(exit_to, false)
	_spot.call("request_exit", hint)


func _begin_dive(spot: Node3D, side: int, slot: int) -> void:
	_from = player.global_position
	_start = _from
	_to = spot.call("inside_point", side, slot)
	var kind := str(spot.get("spot_kind"))
	var top: float = (spot.get("box_size") as Vector3).y
	var via := Vector3.INF
	match kind:
		"shed":
			_peak = 0.0
			_gesture("shed_step", "shuffle")
			# From off to one side of the door: across to the doorway first (no
			# farther out than you already are, never backing off), then in.
			var doorstep: Vector3 = spot.call("entry_point", side, slot)
			var out: Vector3 = spot.call("side_direction", side)
			var inside: Vector3 = _to
			var step_out := (doorstep - inside).dot(out)
			var depth := clampf((_from - inside).dot(out), step_out - Constants.HIDE_EXIT_GAP, step_out)
			var doorway := inside + out * depth
			doorway.y = _from.y
			if Vector2(doorway.x - _from.x, doorway.z - _from.z).length() > SHED_DOORSTEP_SNAP:
				via = doorway
		"bin":
			# Hands on the rim, knees tucked over it: the feet needn't clear the top.
			_peak = top * 0.78 - _from.y + spot.global_position.y
			_gesture("bin_vault", "startle")
		_:
			_peak = top * 0.7 - _from.y + spot.global_position.y
			_gesture("hedge_dive", "startle")
	_face_toward(_to if not via.is_finite() else via)
	_start_move(Move.DIVE, Constants.HIDE_ENTER_SECONDS)
	_via = via
	player.call("say_to_all", "vo_hup")
	_push_spot_shot(spot, side, slot, Constants.HIDE_ENTER_SECONDS)


func _begin_exit(to: Vector3, pulled: bool) -> void:
	_from = player.global_position
	_to = to
	var top := 1.6
	if _spot != null:
		top = (_spot.get("box_size") as Vector3).y
		if str(_spot.get("spot_kind")) == "shed":
			top = 0.0
	_peak = (top * (0.85 if pulled else 0.6)) if top > 0.0 else 0.0
	_face_toward(to)
	_start_move(Move.PULL if pulled else Move.EXIT, Constants.HIDE_PULL_SECONDS if pulled else Constants.HIDE_EXIT_SECONDS)
	_gesture("upsy_daisy_victim" if pulled else "burst_out", "flail" if pulled else "startle")
	player.call("say_to_all", "vo_yelp" if pulled else "vo_hup")
	_pop_shot(Constants.HIDE_EXIT_SECONDS if not pulled else Constants.HIDE_PULL_SECONDS)


## The host said no (full, too far, caught): bounce off and land where you were.
func on_refused(spot: Node3D) -> void:
	if not is_owner_view():
		return
	if _waiting != spot and not (_move == Move.DIVE and _spot == null):
		return
	_waiting = null
	_bonk(spot)


func _bonk(spot: Node3D) -> void:
	_from = player.global_position
	_to = _start
	_peak = 0.35
	_start_move(Move.BONK, Constants.HIDE_BONK_SECONDS)
	_gesture("stumble", "stumble")
	player.call("say_to_all", "vo_oof")
	var at := spot.global_position if spot != null else player.global_position
	if spot != null and spot.has_method("top_point"):
		at = (spot.call("top_point") as Vector3).lerp(_from, 0.5)
	_play_at("hide_bonk", at)
	_pop_shot(Constants.HIDE_BONK_SECONDS)


## Pile: the host turned you out (a rake, a mower, a bag) or you climbed out.
func pile_pop(pulled_to: Vector3 = Vector3.INF) -> void:
	_waiting_pile = false
	_burst_pile(player.global_position)
	_play_at("pile_pop", player.global_position)
	_hat_leaf_on()
	if not is_owner_view():
		_gesture("burst_out", "startle")
		return
	_from = player.global_position
	var ahead := _view_forward()
	_to = pulled_to if pulled_to.is_finite() else _from + ahead * 0.7
	_peak = 0.9 if pulled_to.is_finite() else 0.6
	_start_move(Move.PULL if pulled_to.is_finite() else Move.PILE_POP, Constants.HIDE_PULL_SECONDS if pulled_to.is_finite() else Constants.HIDE_EXIT_SECONDS)
	_gesture("burst_out", "startle")
	_pop_shot(Constants.HIDE_EXIT_SECONDS)


## The host picked another side or slot mid-move: carry on from right here to
## the new end in the time that's left, on a smaller arc. No jump.
func _retarget(to: Vector3) -> void:
	var left := maxf(0.15, _move_length - _move_t)
	var share := left / maxf(_move_length, 0.01)
	_from = player.global_position
	_to = to
	_peak *= share
	_move_t = 0.0
	_move_length = left
	_via = Vector3.INF


func _start_move(kind: Move, seconds: float) -> void:
	_move = kind
	_move_t = 0.0
	_move_length = maxf(seconds, 0.05)
	_via = Vector3.INF


func _physics_process(delta: float) -> void:
	if player == null:
		return
	_track_turn(delta)
	if is_owner_view():
		_step_owner(delta)


func _step_owner(delta: float) -> void:
	# A dive the host never answered bonks off, so you're never stuck half in.
	if _waiting != null and Time.get_ticks_msec() - _waiting_since > int(Constants.HIDE_CONFIRM_TIMEOUT * 1000.0) and _spot != _waiting:
		var spot := _waiting
		_waiting = null
		_bonk(spot)
	if _waiting_pile and Time.get_ticks_msec() - _waiting_since > int(Constants.HIDE_CONFIRM_TIMEOUT * 1000.0) and not bool(player.get("in_pile")):
		_waiting_pile = false
		_pop_shot(0.25)
	if _move == Move.NONE:
		return
	# A staged body (the gotcha, R2 chunk 2) takes over from any lift in progress.
	if player.has_method("is_staged") and bool(player.call("is_staged")):
		_move = Move.NONE
		return
	_move_t += delta
	var t := clampf(_move_t / _move_length, 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t)
	# A hop is ballistic: steady across, up and down on the arc. A walk eases.
	var across := t * (1.12 - 0.12 * t) if _peak > 0.0 else eased
	var at := _from.lerp(_to, across)
	if _via.is_finite():
		# Two legs at one pace: to the doorstep, then through the door.
		var first := _from.distance_to(_via)
		var split := first / maxf(first + _via.distance_to(_to), 0.001)
		if across < split:
			at = _from.lerp(_via, across / maxf(split, 0.001))
		else:
			at = _via.lerp(_to, (across - split) / maxf(1.0 - split, 0.001))
		# Turning to the door on the way to the step, not snapping round on it.
		if across > split * 0.5:
			var door := atan2(-(_to.x - _via.x), -(_to.z - _via.z))
			player.set("body_yaw", lerp_angle(float(player.get("body_yaw")), door, clampf(delta * 14.0, 0.0, 1.0)))
	# The arc: up over the top and down again (a bonk bounces lower).
	if _peak > 0.0:
		var lift := 4.0 * t * (1.0 - t)
		at.y = lerpf(_from.y, _to.y, across) + maxf(0.0, _peak) * lift
	player.global_position = at
	player.velocity = Vector3.ZERO
	if t >= 1.0:
		var finished := _move
		_move = Move.NONE
		if finished == Move.EXIT or finished == Move.PULL or finished == Move.BONK or finished == Move.PILE_POP:
			player.call("on_hide_move_done")
		if finished == Move.PILE_DIVE and not bool(player.get("in_pile")) and not _waiting_pile:
			_pop_shot(0.25)
		if finished == Move.DIVE or finished == Move.PILE_DIVE:
			# Settled in, looking out the way the view does (the body isn't drawn now).
			player.set("body_yaw", facing_yaw())
			player.set("head_pitch", 0.0)


# ---------------------------------------------------------------- every peer: state from the host

## From player.set_hidden_in on every peer: now inside spot by side.
func on_hidden(spot: Node3D, side: int, at: float) -> void:
	_spot = spot
	_side = maxi(side, 0)
	_slot = int(spot.call("slot_of", player.name.to_int())) if spot.has_method("slot_of") else 0
	_in_at = at
	_last_yaw = INF
	if is_owner_view():
		if _waiting == spot:
			_waiting = null
		elif _move != Move.DIVE:
			# Not predicted (a scenario, a late confirmation): dive now from here.
			_begin_dive(spot, _side, _slot)
		else:
			# Predicted, but the host picked another side or slot: aim there.
			_retarget(spot.call("inside_point", _side, _slot))
			_push_spot_shot(spot, _side, _slot, maxf(0.1, _move_length - _move_t))
	else:
		_hide_by_ms = Time.get_ticks_msec() + int((Constants.HIDE_ENTER_SECONDS + 0.35) * 1000.0)
		# Everyone else sees the same dive the owner plays (gestures are local).
		if Net.server_time() - at < Constants.BEAT_SKIP:
			_gesture(str({"shed": "shed_step", "bin": "bin_vault"}.get(str(spot.get("spot_kind")), "hedge_dive")), "startle")
	_set_voice_muffled(true)


## From player.set_hidden_in(null, ...): out, toward exit_to (INF: where you are).
func on_unhidden(exit_to: Vector3, pulled: bool) -> void:
	var was := _spot
	_spot = null
	_set_voice_muffled(bool(player.get("in_pile")))
	if was != null and str(was.get("spot_kind")) == "hedge":
		_hat_leaf_on()
	if not is_owner_view():
		_gesture("upsy_daisy_victim" if pulled else "burst_out", "flail" if pulled else "startle")
		return
	if _move == Move.EXIT and not pulled:
		# Predicted: the host may have picked another side; aim there.
		if exit_to.is_finite() and exit_to.distance_to(_to) > 0.05:
			_retarget(exit_to)
		return
	if exit_to.is_finite():
		_spot = was
		_begin_exit(exit_to, pulled)
		_spot = null
	else:
		_pop_shot(0.2)


## From player.set_pile on every peer. fresh false: they were already in when
## this peer first saw them (a late join), so nothing replays; the mound is just there.
func on_pile(hidden: bool, fresh: bool = true) -> void:
	if hidden and not fresh:
		_pile_used_at = Net.server_time() - Constants.SUSPICION_RECENT_SECONDS
		_in_at = _pile_used_at
		_pile_since_ms = Time.get_ticks_msec() - int(Constants.HIDE_ENTER_SECONDS * 1000.0)
		_last_yaw = INF
		if not is_owner_view():
			_place_pile_anchor(-player.global_basis.z)
	elif hidden:
		_waiting_pile = false
		_pile_used_at = Net.server_time()
		_in_at = Net.server_time()
		_pile_since_ms = Time.get_ticks_msec()
		if not is_owner_view():
			_gesture("pile_cannonball", "startle")
			_place_pile_anchor(-player.global_basis.z)
		_last_yaw = INF
		# The owner's own cannonball lands a moment from now: the whump goes there.
		var landing := 0.0
		if is_owner_view() and _move == Move.PILE_DIVE:
			landing = maxf(0.0, _move_length * 0.72 - _move_t)
		elif not is_owner_view():
			landing = Constants.HIDE_ENTER_SECONDS * 0.75
		var where := _to if landing > 0.0 and is_owner_view() else player.global_position
		if landing > 0.0:
			var owner_view := is_owner_view()
			get_tree().create_timer(landing).timeout.connect(func() -> void:
				if is_instance_valid(self) and is_instance_valid(player):
					# Elsewhere, where they're seen to land by now.
					var at := where if owner_view else player.global_position
					_play_at("pile_dive", at)
					_burst_pile(at + Vector3(0.0, 0.3, 0.0)))
		else:
			_play_at("pile_dive", where)
			_burst_pile(where + Vector3(0.0, 0.3, 0.0))
		if is_owner_view() and _shot == &"":
			_push_pile_shot()
	_set_voice_muffled(hidden or _spot != null)


# ---------------------------------------------------------------- what gets drawn

## Whether the body, head, nameplate and arms should be drawn now (every peer).
func body_should_draw() -> bool:
	if player == null:
		return true
	var in_pile := bool(player.get("in_pile"))
	if is_owner_view():
		match _move:
			Move.DIVE, Move.PILE_DIVE:
				return _move_t / _move_length < 0.72
			Move.EXIT, Move.PULL, Move.BONK, Move.PILE_POP:
				return true
		return _spot == null and not in_pile
	if _spot != null:
		if Time.get_ticks_msec() >= _hide_by_ms:
			return false
		var visual := player.get_node_or_null("Visual") as Node3D
		var inside: Vector3 = _spot.call("inside_point", _side, _slot)
		return visual == null or visual.global_position.distance_to(inside) > 0.35
	# The cannonball plays out (the replicated arc) before the leaves close over them.
	return not in_pile or not _pile_landed()


## Other peers: the dive into the pile has had time to land.
func _pile_landed() -> bool:
	return Time.get_ticks_msec() - _pile_since_ms >= int(Constants.HIDE_ENTER_SECONDS * 0.75 * 1000.0)


## Every frame on every peer, from player._process: the mound, the leaf on the
## head, the peek, the shot and the frame, the muffle.
func present(delta: float) -> void:
	if player == null:
		return
	_present_mound()
	_present_hat(delta)
	if not is_owner_view():
		# The eye rides along to where the cannonball lands, still facing the dive.
		if _pile_anchor != null and bool(player.get("in_pile")):
			_place_pile_anchor(-_pile_anchor.global_basis.z)
		return
	var hidden := _spot != null or bool(player.get("in_pile"))
	_step_peek(delta, hidden)
	_keep_shot()
	_present_frame(hidden, delta)
	# The dive's own rustle lands crisp; the world goes muffled once you're in.
	_set_muffled(hidden and not is_moving())


func _step_peek(delta: float, hidden: bool) -> void:
	# Headless (tests, bots) has no mouse to capture.
	var mouse_ok := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or DisplayServer.get_name() == "headless"
	var want := hidden and not is_moving() and Input.is_action_pressed("secondary") and mouse_ok
	if bool(player.get("peeking")) != want:
		player.set("peeking", want)
	_peek = move_toward(_peek, 1.0 if want else 0.0, delta / maxf(Constants.HIDE_PEEK_EASE, 0.01))
	if hidden and want != _peeking_shot and _shot != &"":
		_peeking_shot = want
		if _spot != null:
			_push_spot_shot(_spot, _side, _slot, Constants.HIDE_PEEK_EASE)
		elif bool(player.get("in_pile")):
			_push_pile_shot()


func _present_frame(hidden: bool, delta: float) -> void:
	# In as the eye arrives (the second half of the dive), out as you climb out.
	var arriving := (_move == Move.DIVE or _move == Move.PILE_DIVE) and _move_t / _move_length > 0.5
	var show := _shot == SHOT_PEEK and ((hidden and not is_moving()) or arriving)
	_frame_fade = move_toward(_frame_fade, 1.0 if show else 0.0, delta / maxf(Constants.HIDE_CAM_BLEND, 0.01))
	if _frame_fade <= 0.0:
		if _frame_layer != null:
			_frame_layer.visible = false
		return
	if _frame_layer == null:
		_frame_layer = CanvasLayer.new()
		_frame_layer.name = "HideFrame"
		# Under the HUD (layer 1+), over the 3D view.
		_frame_layer.layer = 0
		add_child(_frame_layer)
		_frame = _HideFrame.new()
		_frame_layer.add_child(_frame)
	_frame_layer.visible = true
	_frame.modulate.a = _frame_fade
	var source := _spot if _spot != null else _waiting
	if source != null:
		_frame.set("kind", str(source.get("spot_kind")))
	elif bool(player.get("in_pile")) or _waiting_pile:
		_frame.set("kind", "pile")
	_frame.set("peek", _peek)
	_frame.set("turn_rate", _turn_rate)


# ---------------------------------------------------------------- the camera

## The hide shot for a spot: first person from the spot's eye (the view turns
## with the mouse, clamped round the spot's facing), third person orbiting it.
func _push_spot_shot(spot: Node3D, side: int, slot: int, blend: float) -> void:
	if not is_owner_view() or not player.has_method("stage_push"):
		return
	var first_person := _first_person()
	var id := SHOT_PEEK if first_person else SHOT_ORBIT
	if _shot != &"" and _shot != id:
		player.call("stage_pop", _shot, blend)
	_shot = id
	_shot_first_person = first_person
	var shot: Dictionary
	if first_person:
		var rise := Constants.HIDE_PEEK_RISE if _peeking_shot else 0.0
		shot = {
			"anchor": spot.call("peek_anchor", side, slot),
			"offset": Transform3D(Basis.IDENTITY, Vector3(0.0, rise, 0.0)),
			"blend_in": blend,
			"blend_out": Constants.HIDE_EXIT_SECONDS,
			"yaw_clamp": Vector2(-Constants.HIDE_YAW_CLAMP, Constants.HIDE_YAW_CLAMP),
			"pitch_clamp": Constants.HIDE_PITCH_CLAMP,
			"orbit": false,
			"spring": false,
			"fov": _fov(),
			"lag": 0.0,
			"priority": SHOT_PRIORITY,
			"hide_self": true,
		}
	else:
		shot = {
			"anchor": _orbit_anchor(spot),
			"offset": _orbit_offset(),
			"blend_in": blend,
			"blend_out": Constants.HIDE_EXIT_SECONDS,
			"yaw_clamp": Vector2(-PI, PI),
			"pitch_clamp": Vector2(-0.9, 0.3),
			"orbit": true,
			"spring": true,
			"fov": 0.0,
			"lag": 0.05,
			"priority": SHOT_PRIORITY,
		}
	player.call("stage_push", id, shot)


## The pile: eyes just over the leaves, facing the way you dove.
func _push_pile_shot() -> void:
	if not is_owner_view() or not player.has_method("stage_push"):
		return
	if _shot == &"" or _pile_anchor == null:
		_place_pile_anchor(-player.global_basis.z)
	var first_person := _first_person()
	var id := SHOT_PEEK if first_person else SHOT_ORBIT
	if _shot != &"" and _shot != id:
		player.call("stage_pop", _shot, Constants.HIDE_CAM_BLEND)
	_shot = id
	_shot_first_person = first_person
	var rise := Constants.HIDE_PEEK_RISE * 1.5 if _peeking_shot else 0.0
	var shot := {
		"anchor": _pile_anchor,
		"hide_self": first_person,
		"offset": Transform3D(Basis.IDENTITY, Vector3(0.0, rise, 0.0)) if first_person else _orbit_offset(),
		"blend_in": Constants.HIDE_ENTER_SECONDS,
		"blend_out": Constants.HIDE_EXIT_SECONDS,
		"yaw_clamp": Vector2(-Constants.HIDE_YAW_CLAMP, Constants.HIDE_YAW_CLAMP) if first_person else Vector2(-PI, PI),
		"pitch_clamp": Constants.HIDE_PITCH_CLAMP if first_person else Vector2(-0.9, 0.3),
		"orbit": not first_person,
		"spring": not first_person,
		"fov": _fov() if first_person else 0.0,
		"lag": 0.0,
		"priority": SHOT_PRIORITY,
	}
	player.call("stage_push", id, shot)


## The pile's eye, just over the leaves and facing ahead (flat). Made on every
## peer, so the host's crew brain has a peek_anchor for anyone's pile.
func _place_pile_anchor(ahead: Vector3) -> void:
	if _pile_anchor == null:
		_pile_anchor = Marker3D.new()
		_pile_anchor.name = "PileEye"
		player.get_parent().add_child(_pile_anchor)
	ahead.y = 0.0
	if ahead.length() < 0.01:
		ahead = Vector3.FORWARD
	ahead = ahead.normalized()
	var eye := player.global_position + Vector3(0.0, PILE_EYE_HEIGHT, 0.0) + ahead * PILE_EYE_AHEAD
	_pile_anchor.global_transform = Transform3D(Basis.looking_at(ahead, Vector3.UP), eye)


func _pop_shot(blend: float) -> void:
	_peeking_shot = false
	if _shot == &"" or not player.has_method("stage_pop"):
		_shot = &""
		return
	player.call("stage_pop", _shot, blend)
	_shot = &""


## The camera key while hidden swaps the peek for the orbit and back.
func _keep_shot() -> void:
	if _shot == &"" or is_moving():
		return
	if _first_person() != _shot_first_person:
		if _spot != null:
			_push_spot_shot(_spot, _side, _slot, Constants.HIDE_CAM_BLEND)
		elif bool(player.get("in_pile")):
			_push_pile_shot()


## Out past the facing side and up, tipped down to look at the spot.
func _orbit_offset() -> Transform3D:
	var out := Vector3(0.0, Constants.HIDE_ORBIT_RISE, Constants.HIDE_ORBIT)
	return Transform3D(Basis(Vector3.RIGHT, -atan2(Constants.HIDE_ORBIT_RISE, Constants.HIDE_ORBIT)), out)


func _orbit_anchor(spot: Node3D) -> Node3D:
	var anchor := spot.get_node_or_null("OrbitAnchor") as Node3D
	if anchor == null:
		anchor = Marker3D.new()
		anchor.name = "OrbitAnchor"
		spot.add_child(anchor)
	var facing: Vector3 = spot.call("side_direction", _side)
	anchor.global_transform = Transform3D(Basis.looking_at(-facing, Vector3.UP), spot.call("top_point"))
	return anchor


func _first_person() -> bool:
	var rig := player.get_node_or_null("CameraRig")
	return rig == null or bool(rig.get("first_person"))


func _fov() -> float:
	return Settings.fov() + (Constants.HIDE_PEEK_FOV if _peeking_shot else 0.0)


## Which way the view looks now (flat), for the exit side and the pile's pop.
func _view_forward() -> Vector3:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var forward := -camera.global_basis.z if camera != null else -player.global_basis.z
	forward.y = 0.0
	return forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD


## The facing a hidden player's look turns around: out of the side they came
## in by (a spot) or the way they dove (a pile), as a body_yaw.
func facing_yaw() -> float:
	if _spot != null:
		var out: Vector3 = _spot.call("side_direction", _side)
		return atan2(-out.x, -out.z)
	if _pile_anchor != null:
		var ahead := -_pile_anchor.global_basis.z
		return atan2(-ahead.x, -ahead.z)
	return float(player.get("body_yaw"))


# ---------------------------------------------------------------- sound

## The world through the wall: music and effects muffled while you're inside,
## and the chase music's "hide" section during a chase (audio, R2 chunk 5).
func _set_muffled(on: bool) -> void:
	var music := get_tree().get_first_node_in_group("music_director")
	if on:
		# Re-asserted every frame: the phone or pause menu closing must not undo it.
		if not _Buses.is_muffled():
			_Buses.set_muffled(true)
	if on == _muffled:
		return
	_muffled = on
	if not on:
		var keep := music != null and music.has_method("is_muffling") and bool(music.call("is_muffling"))
		_Buses.set_muffled(keep)
	_set_sfx_filter(on)
	if music != null and music.has_method("request_section"):
		var director := get_tree().get_first_node_in_group("run_director")
		var chasing := director != null and int(director.call("phase")) == 2
		music.call("request_section", &"hide", on and chasing)


func _set_sfx_filter(on: bool) -> void:
	var bus := AudioServer.get_bus_index(_Buses.SFX)
	if bus < 0:
		return
	if _sfx_filter == null:
		_sfx_filter = AudioEffectLowPassFilter.new()
		_sfx_filter.cutoff_hz = Constants.HIDE_MUFFLE_HZ
	var slot := -1
	for index: int in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, index) == _sfx_filter:
			slot = index
	if on and slot < 0:
		AudioServer.add_bus_effect(bus, _sfx_filter)
	elif not on and slot >= 0:
		AudioServer.remove_bus_effect(bus, slot)


## Whether the local player's world is muffled now (for tests and the probe).
static func world_muffled() -> bool:
	var bus := AudioServer.get_bus_index(_Buses.SFX)
	if bus < 0:
		return false
	for index: int in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, index) is AudioEffectLowPassFilter:
			return true
	return false


## The bus a sound at `at` should use so a hider still hears the NICE BOYS clearly
## (Constants.HIDE_CLEAR_CREW_METERS): the Chatter bus skips the muffle.
static func clear_bus_for(tree: SceneTree, at: Vector3) -> StringName:
	for node: Node in tree.get_nodes_in_group("players"):
		var body := node as Node3D
		if body != null and body.is_multiplayer_authority() and bool(body.call("is_hidden")) and body.global_position.distance_to(at) <= Constants.HIDE_CLEAR_CREW_METERS:
			return _Buses.CHATTER
	return _Buses.SFX


## This player's voice, heard through the hedge by everyone else.
func _set_voice_muffled(on: bool) -> void:
	if on == _voice_muffled:
		return
	_voice_muffled = on
	var voice := player.get_node_or_null("Visual/Head/Voice") as AudioStreamPlayer3D
	if voice == null:
		return
	if on:
		_ensure_voice_bus()
		voice.bus = VOICE_MUFFLED
	else:
		voice.bus = _Buses.VOICE


static func _ensure_voice_bus() -> void:
	if AudioServer.get_bus_index(VOICE_MUFFLED) >= 0:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, VOICE_MUFFLED)
	AudioServer.set_bus_send(index, _Buses.VOICE)
	var low_pass := AudioEffectLowPassFilter.new()
	low_pass.cutoff_hz = Constants.HIDE_VOICE_MUFFLE_HZ
	AudioServer.add_bus_effect(index, low_pass)


func is_voice_muffled() -> bool:
	return _voice_muffled


# ---------------------------------------------------------------- the pile and the leaf hat

## A taller, darker mound over a hidden player, with their shoe poking out,
## breathing a little (every peer).
func _present_mound() -> void:
	var in_pile := bool(player.get("in_pile"))
	var show := in_pile and (_pile_landed() if not is_owner_view() else not (_move == Move.PILE_DIVE and _move_t / _move_length < 0.7))
	if show and _mound == null:
		_mound = _make_mound()
		# On the drawn body (smoothed on other peers), so it sits where they see them land.
		var visual := player.get_node_or_null("Visual") as Node3D
		(visual if visual != null else player).add_child(_mound)
		_mound.scale = Vector3(1.0, 0.2, 1.0)
		var tween := _mound.create_tween()
		tween.tween_property(_mound, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	elif not show and _mound != null:
		_mound.queue_free()
		_mound = null
	if _mound != null:
		_mound.global_rotation = Vector3.ZERO
		var breathe := 1.0 + sin(Time.get_ticks_msec() / 1000.0 * 2.4) * 0.03
		if _mound.get_child_count() > 0:
			(_mound.get_child(0) as Node3D).scale = Vector3(1.0, breathe, 1.0)


func _make_mound() -> Node3D:
	var root := Node3D.new()
	root.name = "Mound"
	var kit := _MeshKit.new()
	var size := Constants.HIDE_PILE_MOUND_SCALE
	var dark := Constants.HIDE_PILE_MOUND_DARKEN
	var colors: Array[Color] = [Color(0.78, 0.4, 0.12), Color(0.85, 0.62, 0.18), Color(0.66, 0.24, 0.12), Color(0.55, 0.34, 0.14)]
	kit.blob(Vector3(0.0, 0.22 * size.y, 0.0), Vector3(0.75 * size.x, 0.45 * size.y, 0.75 * size.z), colors[0].darkened(dark), {"detail": 1, "lumps": 0.3, "lump_scale": 2.0, "flat": true, "jitter": 0.08, "seed": 7})
	var rng := RandomNumberGenerator.new()
	rng.seed = player.name.to_int() * 31 + 5
	for index: int in 48:
		var a := rng.randf() * TAU
		var up := rng.randf_range(0.1, 1.0)
		var normal := Vector3(cos(a) * (1.0 - up * 0.7), up, sin(a) * (1.0 - up * 0.7)).normalized()
		var at := Vector3(normal.x * 0.75 * size.x, 0.22 * size.y + normal.y * 0.45 * size.y, normal.z * 0.75 * size.z)
		kit.leaf_card(at, normal, rng.randf_range(0.08, 0.13), colors[rng.randi() % colors.size()].darkened(dark * rng.randf_range(0.5, 1.0)), 0.3, rng.randf() * TAU)
	var mesh := _Stylized.instance(kit.commit(), {"roughness": 0.9, "double_sided": true, "wind": 0.02})
	mesh.name = "Leaves"
	root.add_child(mesh)
	# The hider's shoe sticking out the side, in their own shoe color.
	var shoe_kit := _MeshKit.new()
	shoe_kit.blob(Vector3.ZERO, Vector3(0.07, 0.06, 0.13), Color(0.18, 0.14, 0.12), {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0})
	shoe_kit.blob(Vector3(0.0, -0.045, 0.0), Vector3(0.075, 0.02, 0.135), Color(0.82, 0.78, 0.7), {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0})
	var shoe := _Stylized.instance(shoe_kit.commit(), {"roughness": 0.7})
	shoe.name = "Shoe"
	shoe.position = Vector3(0.62 * size.x, 0.12, 0.25)
	shoe.rotation = Vector3(0.3, 0.9, 0.2)
	root.add_child(shoe)
	if is_owner_view():
		# Your own mound would sit in front of your own eyes.
		for node: Node in root.find_children("*", "MeshInstance3D", true, false):
			(node as MeshInstance3D).layers = 1 << (_CartoonBody.HEAD_LAYER - 1)
	return root


func _burst_pile(at: Vector3) -> void:
	_HideSpotLook.burst(player.get_parent(), at, 16, _HideSpotLook.LEAF_COLORS, 3.0, _rng)


## A leaf stuck on your head for a few seconds after you come out (every peer).
func _hat_leaf_on() -> void:
	_hat_left = Constants.HIDE_LEAF_HAT_SECONDS
	if _hat_leaf != null:
		return
	var head := player.get_node_or_null("Visual/Head") as Node3D
	if head == null:
		return
	var kit := _MeshKit.new()
	kit.leaf_card(Vector3.ZERO, Vector3.UP, 0.11, _HideSpotLook.LEAF_COLORS[_rng.randi() % _HideSpotLook.LEAF_COLORS.size()], 0.0)
	_hat_leaf = _Stylized.instance(kit.commit(), {"roughness": 0.9, "double_sided": true})
	_hat_leaf.name = "HatLeaf"
	_hat_leaf.position = Vector3(0.05, 0.36, 0.02)
	_hat_leaf.rotation = Vector3(0.25, _rng.randf() * TAU, 0.1)
	if is_owner_view():
		(_hat_leaf as MeshInstance3D).layers = 1 << (_CartoonBody.HEAD_LAYER - 1)
	head.add_child(_hat_leaf)


func _present_hat(delta: float) -> void:
	if _hat_leaf == null:
		return
	_hat_left -= delta
	_hat_leaf.visible = bool(player.call("is_body_drawn"))
	if _hat_left <= 0.0:
		var leaf := _hat_leaf
		_hat_leaf = null
		var start := leaf.global_position
		var tween := leaf.create_tween()
		tween.tween_method(func(t: float) -> void:
			if is_instance_valid(leaf):
				leaf.global_position = start + Vector3(sin(t * 7.0) * 0.2, -t * 1.6, t * 0.3)
				leaf.rotation.z = sin(t * 9.0) * 0.8, 0.0, 1.0, 1.0)
		tween.tween_callback(leaf.queue_free)


# ---------------------------------------------------------------- tells and the pile's suspicion

func _track_turn(delta: float) -> void:
	var yaw := float(player.get("body_yaw"))
	if _last_yaw != INF and delta > 0.0:
		_turn_rate = lerpf(_turn_rate, angle_difference(_last_yaw, yaw) / delta, clampf(delta * 12.0, 0.0, 1.0))
	_last_yaw = yaw
	if not Net.is_host() or not bool(player.get("in_pile")):
		return
	_pile_suspicion = maxf(0.0, _pile_suspicion - Constants.SUSPICION_DECAY_PER_S * delta)
	_pile_rustle_cool = maxf(0.0, _pile_rustle_cool - delta)
	if Net.server_time() - _in_at < Constants.HIDE_SETTLE_SECONDS:
		return
	var watched := _crew_sees(player.global_position + Vector3(0.0, 0.5, 0.0))
	if not watched:
		return
	if bool(player.get("peeking")):
		_pile_suspicion = minf(1.0, _pile_suspicion + Constants.SUSPICION_PEEK_PER_S * delta)
	if absf(_turn_rate) > Constants.HIDE_TREMBLE_TURN_RATE and _pile_rustle_cool <= 0.0:
		_pile_rustle_cool = Constants.HIDE_TREMBLE_SECONDS
		_pile_suspicion = minf(1.0, _pile_suspicion + Constants.SUSPICION_RUSTLE)


## How fast this player is turning now (rad/s, smoothed), for the tells.
func turn_rate() -> float:
	return _turn_rate


## Host, pile: seen diving in sets a high base (leaf_field.gd marks pile_seen).
func pile_suspicion() -> float:
	if not bool(player.get("in_pile")):
		return 0.0
	var seen := Constants.SUSPICION_SEEN_ENTERING if bool(player.get_meta("pile_seen", false)) else 0.0
	var recent := Constants.SUSPICION_RECENT_USE if Net.server_time() - _pile_used_at < Constants.SUSPICION_RECENT_SECONDS else 0.0
	return clampf(maxf(_pile_suspicion, seen) + recent, 0.0, 1.0)


func pile_inspect_score(from: Vector3, last_seen: Vector3) -> float:
	# A poke nobody resolved (he was bonked or sent home) stops holding the pile.
	if _pile_inspector != null and (not is_instance_valid(_pile_inspector) or Net.server_time() - _pile_inspect_began > Constants.HIDE_INSPECT_SECONDS + Constants.HIDE_INSPECT_STALE_SLACK):
		_pile_inspector = null
	if not bool(player.get("in_pile")) or _pile_inspector != null or Net.server_time() - _pile_inspected_at < Constants.HIDE_INSPECT_COOLDOWN:
		return -1.0
	_pile_last_seen = last_seen
	return pile_suspicion() + _near_bonus(last_seen) + Constants.HIDE_INSPECT_BASE - from.distance_to(player.global_position) / Constants.HIDE_INSPECT_METERS_PER_POINT


func pile_inspect_point() -> Vector3:
	var ahead := -_pile_anchor.global_basis.z if _pile_anchor != null else -player.global_basis.z
	ahead.y = 0.0
	return player.global_position + ahead.normalized() * (0.75 + Constants.HIDE_INSPECT_STAND)


func pile_inspect_begin(crew: Node) -> void:
	_pile_inspector = crew
	_pile_inspect_began = Net.server_time()


## Host: the pats stopped short; the pile can be looked at again.
func pile_inspect_cancel(crew: Node) -> void:
	if crew == null or not is_instance_valid(_pile_inspector) or crew == _pile_inspector:
		_pile_inspector = null


## Host: {outcome, peer} for the pile the player is in.
func pile_inspect_resolve() -> Dictionary:
	_pile_inspector = null
	_pile_inspected_at = Net.server_time()
	var total := clampf(pile_suspicion() + _near_bonus(_pile_last_seen), 0.0, 1.0)
	var director := get_tree().get_first_node_in_group("run_director")
	var catchable := director == null or bool(director.call("can_capture", player.name.to_int()))
	if bool(player.get("in_pile")) and catchable and total >= Constants.HIDE_FOUND_AT:
		_pile_suspicion = 0.0
		return {"outcome": &"found", "peer": player.name.to_int()}
	_pile_suspicion *= 0.5
	return {"outcome": &"near_miss", "peer": 0}


func _near_bonus(last_seen: Vector3) -> float:
	if not last_seen.is_finite():
		return 0.0
	return Constants.SUSPICION_NEAR_LAST_SEEN if Vector2(last_seen.x - player.global_position.x, last_seen.z - player.global_position.z).length() <= Constants.SUSPICION_NEAR_METERS else 0.0


func _crew_sees(point: Vector3) -> bool:
	for group: String in ["nice_crew", "crew"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var crew := node as Node3D
			if crew == null or crew.global_position.distance_to(point) > Constants.SUSPICION_CONE_METERS:
				continue
			if crew.has_method("sees_point"):
				if bool(crew.call("sees_point", point)):
					return true
				continue
			var forward := crew.global_basis.z
			var to := point - crew.global_position
			forward.y = 0.0
			to.y = 0.0
			if to.length() < 1.0 or rad_to_deg(forward.normalized().angle_to(to.normalized())) <= Constants.SUSPICION_CONE_HALF_DEG:
				return true
	return false


# ---------------------------------------------------------------- helpers

func _gesture(wanted: String, fallback: String) -> void:
	var body := player.get_node_or_null("Visual/CartoonBody")
	if body == null:
		return
	body.call("gesture", wanted if _CartoonBody.has_gesture(wanted) else fallback)


func _face_toward(point: Vector3) -> void:
	var flat := Vector3(point.x - player.global_position.x, 0.0, point.z - player.global_position.z)
	if flat.length() > 0.05:
		player.set("body_yaw", atan2(-flat.x, -flat.z))


func _play_at(id: String, at: Vector3, db: float = 0.0) -> void:
	var sfx := get_tree().get_first_node_in_group("sfx") if is_inside_tree() else null
	if sfx != null:
		sfx.call("play_at", id, at, db)


func _exit_tree() -> void:
	if _muffled:
		_set_muffled(false)
	if _pile_anchor != null and is_instance_valid(_pile_anchor):
		_pile_anchor.queue_free()
