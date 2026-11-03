extends Node3D

## Authority: the owner predicts its own dives and climb-outs; everything else
## here is local presentation from replicated state. Hiding, as the hider and as
## everyone watching them (R2 chunk 3, R2b hide; docs/GAME.md "Hiding"). A child
## of the player ("HideView"), made on first use by player.gd.
##
## - Getting in: E plays the dive at once on your own screen (a hop over a hedge,
##   a vault into a bin, a step through the shed door, a cannonball into a pile);
##   the host confirms. Refused, you bonk off the outside and land where you
##   started. The body follows a curve; nothing teleports.
## - The view stays live: your camera is never under a hidden node. The body,
##   head, nameplate and first-person arms stop being drawn (set_body_drawn). In
##   first person the camera rides the HideEye, which this script carries from
##   your eyes to the spot's eye on an eased path (turning round as you land),
##   holds there, and carries back to your eyes on the way out, so nothing whips
##   or cuts. It turns with the mouse within Constants.HIDE_YAW_CLAMP of the
##   spot's facing. Third person orbits the spot instead. Hold secondary to peek:
##   the eye rises, the view widens, and everyone sees the lid lift, the door
##   crack or the eyes glint.
## - Inside a hedge or bin your own machine stops drawing the spot's outside and
##   draws its inside around your eye (make_shell): leaves, or the tub's walls; in
##   a shed it stops drawing the door you're behind. Everyone else sees the spot.
## - Inside, the world is muffled (music and effects through a low-pass that
##   sweeps down as you settle), your voice chat is muffled for everyone, and
##   during a chase the music holds its "hide" section (audio, R2 chunk 5).
## - A NICE BOY looking in: your view is drawn to his face in the gap, the leaves
##   (lid, door) part as he pokes, and when he finds you the spot comes open, his
##   hands close on you and you're pulled out onto your feet looking at him.
## - Getting out: E bursts out on the clear side nearest where you look (the host
##   sweeps for room), with a leaf on your head for a few seconds.
## - The pile: a taller, darker mound with your shoe poking out that grows as you
##   sink into it, and the same suspicion and inspection a hide spot has
##   (player.gd's inspect_* methods).

const _HideSpotLook = preload("res://props/hide_spot.gd")
const _HideFrame = preload("res://player/hide_frame.gd")
const _Buses = preload("res://audio/buses.gd")
const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const _CartoonBody = preload("res://player/cartoon_body.gd")
const _HideGestures = preload("res://player/hide_gestures.gd")

enum Move { NONE, DIVE, EXIT, BONK, PULL, PILE_DIVE, PILE_POP }
enum Eye { NONE, IN, HELD, OUT }

## The bus a hider's voice goes through (a low-pass, then the Voice bus).
const VOICE_MUFFLED := &"VoiceMuffled"
const SHOT_PEEK := &"hide_peek"
const SHOT_ORBIT := &"hide_orbit"
## The eye on its way back to your own camera (no mouse look, just the move).
const SHOT_MOVE := &"hide_move"
const SHOT_PRIORITY: int = 20
## Closer than this to a shed's doorstep (m), the step goes straight in.
const SHED_DOORSTEP_SNAP: float = 0.25
## The pile's eye: this high over the body and this far ahead (m): at the mound's
## face, looking out from under its leaves (R2c hide; it was 0.42 up and 0.3
## ahead, in the middle of the raked pile's own big cards).
const PILE_EYE_HEIGHT: float = Constants.HIDE_PILE_EYE_HEIGHT
const PILE_EYE_AHEAD: float = Constants.HIDE_PILE_FACE

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
## Owner: the spot, side and place the dive in progress is headed for.
var _dive_spot: Node3D
var _dive_side: int = 0
var _dive_slot: int = 0
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
var _muffle_t: float = 0.0
var _music_hide: bool = false
var _sfx_filter: AudioEffectLowPassFilter
var _voice_muffled: bool = false
var _mound: Node3D
var _mound_since_ms: int = 0
## How far the mound sits up on the leaf heap (m), and how far out a pile's eye
## looks from (m, at the heap's face; 0 before it's placed).
var _mound_lift: float = 0.0
var _eye_lift: float = 0.0
## ...and how high over the lawn it is (m; over the heap's skin, R2c hide fixes).
var _eye_rise: float = 0.0
var _pile_anchor: Marker3D
var _hat_leaf: Node3D
var _hat_left: float = 0.0
var _last_yaw: float = INF
var _turn_rate: float = 0.0
var _rng := RandomNumberGenerator.new()
## Owner, first person: the eye the hide shots hang off, and its move.
var _eye: Marker3D
var _eye_mode: Eye = Eye.NONE
var _eye_from := Transform3D()
var _eye_t: float = 0.0
var _eye_len: float = 0.1
## Owner: how far the view is drawn to a NICE BOY's face (0..1), and the face.
var _aim: float = 0.0
var _aim_point := Vector3.INF
## Owner: the inside of the spot drawn around your eye, and the spot whose
## outside this machine has stopped drawing.
var _shell: Node3D
var _inside_of: Node3D
## ...what kind of shell it is, where it sits, and how far it's been swept open
## on the way out (0..1; R2c hide).
var _shell_kind: String = ""
var _shell_at := Transform3D.IDENTITY
var _shell_open: float = 0.0
## ...and the 2D frame's, the same way (0..1).
var _leave_open: float = 0.0
var _shake: float = 0.0
var _knocks_heard: int = 0
## Every peer: a NICE BOY patting this player's pile ({crew} and the server times
## his pats began, he found them, or he gave up).
var _pile_poke_crew: Node3D
var _pile_poke_at: float = -1000.0
var _pile_found_at: float = -1000.0
var _pile_miss_at: float = -1000.0
var _sunk: float = 0.0
## Every peer: the spot a NICE BOY is pulling this player out of.
var _pulled_from: Node3D
## Every peer (R2c hide): how far the body is sunk into a hedge or bin now (m),
## and what was last put on its CartoonBody; how far the head rides the torso.
var _dive_drop: float = 0.0
var _dive_sink: float = 0.0
var _dropped: float = 0.0
var _carry: float = 0.0
## Every peer but the owner: where the body was when the host said it dove in
## (INF: no dive to pose), and how far along the arc it is now (-1: none); the
## spot it's climbing or being hauled out of, from where to where, until when.
var _remote_dive_from := Vector3.INF
var _remote_progress: float = -1.0
var _remote_out_spot: Node3D
var _remote_out_from := Vector3.INF
var _remote_out_to := Vector3.INF
var _remote_out_until: int = 0
## Owner: the spot the climb-out in progress left.
var _exit_spot: Node3D
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
	# Poses on other bodies (the NICE BOY over your pile, your sinking body, the
	# mound) go on after every body has ticked: with physics interpolation on,
	# only what a physics tick leaves behind is drawn.
	var late := _LateTick.new()
	late.name = "LateTick"
	late.process_physics_priority = 150
	late.tick = _late_tick
	add_child(late)


class _LateTick extends Node:
	var tick: Callable

	func _physics_process(delta: float) -> void:
		if tick.is_valid():
			tick.call(delta)


func _late_tick(delta: float) -> void:
	if player == null:
		return
	_present_mound()
	_pose_remote_dive(delta)
	_apply_drop()
	_carry_head(delta)
	_pose_pile_inspector()


## The hide moves' gestures the head rides along with (it hangs off the player's
## Head node, not the torso, so a gesture that bends the body left it standing).
const CARRY_GESTURES: Array[String] = ["hedge_dive", "bin_vault", "shed_step", "pile_cannonball", "burst_out", "upsy_daisy_victim"]


## Every peer but the owner, a dive into a spot (R2c hide): the pose follows how far
## the body has really come along the arc, not the clock, so under lag the arms
## and the tuck are still on when the body reaches the crown, and it sinks into
## the spot before it stops being drawn. Every peer: how far the body sinks into
## a hedge or a bin as it dives in or climbs (or is hauled) out.
func _pose_remote_dive(delta: float) -> void:
	_dive_drop = 0.0
	_dive_sink = 0.0
	_remote_progress = -1.0
	var body := player.get_node_or_null("Visual/CartoonBody") as Node3D
	var visual := player.get_node_or_null("Visual") as Node3D
	if body == null or visual == null:
		return
	if is_owner_view():
		var spot := _spot if _spot != null else (_dive_spot if _move == Move.DIVE else _exit_spot)
		if spot == null or not is_instance_valid(spot):
			return
		_dive_sink = _sink_of(spot)
		var t := clampf(_move_t / maxf(_move_length, 0.01), 0.0, 1.0)
		match _move:
			Move.DIVE:
				_dive_drop = _sink_of(spot) * _HideSpotLook._smooth((t - 0.55) / 0.45)
			Move.EXIT, Move.PULL:
				_dive_drop = _sink_of(spot) * (1.0 - _HideSpotLook._smooth(t / 0.55))
			Move.NONE:
				_dive_drop = _sink_of(spot) if _spot != null else 0.0
		return
	if _remote_out_spot != null and is_instance_valid(_remote_out_spot) and _remote_out_from.is_finite():
		# Out of a spot: low inside it, rising as the body comes clear.
		var out_span := maxf(0.3, Vector2(_remote_out_to.x - _remote_out_from.x, _remote_out_to.z - _remote_out_from.z).length())
		var gone := Vector2(visual.global_position.x - _remote_out_from.x, visual.global_position.z - _remote_out_from.z).length() / out_span
		_dive_sink = _sink_of(_remote_out_spot)
		_dive_drop = _dive_sink * (1.0 - _HideSpotLook._smooth(gone / 0.6))
		if gone >= 1.0 or Time.get_ticks_msec() > _remote_out_until:
			_remote_out_spot = null
		return
	if _spot == null or not is_instance_valid(_spot):
		return
	_dive_sink = _sink_of(_spot)
	if not _remote_dive_from.is_finite() or Time.get_ticks_msec() >= _hide_by_ms:
		# In: crouched down inside, out of sight.
		_remote_dive_from = Vector3.INF
		_dive_drop = _sink_of(_spot)
		return
	var inside: Vector3 = _spot.call("inside_point", _side, _slot)
	var entry: Vector3 = _spot.call("entry_point", _side, _slot)
	var span := maxf(0.3, maxf(_flat_distance(_remote_dive_from, inside), _flat_distance(entry, inside)))
	var p := clampf(1.0 - _flat_distance(visual.global_position, inside) / span, 0.0, 1.0)
	_remote_progress = p
	if p >= Constants.HIDE_REMOTE_DIVE_IN:
		_remote_dive_from = Vector3.INF
	var poses := _HideGestures._HideGesturePoses
	match str(_spot.get("spot_kind")):
		"shed":
			poses.shed_step(body, 0.5 * p, delta)
		"bin":
			poses.bin_vault(body, 0.45 * p, delta)
			_dive_drop = _sink_of(_spot) * _HideSpotLook._smooth((p - 0.5) / 0.5)
		_:
			# Up to the tuck's peak, and held there: arms forward, knees up.
			poses.hedge_dive(body, 0.62 * p, delta)
			_dive_drop = _sink_of(_spot) * _HideSpotLook._smooth((p - 0.55) / 0.45)


## How far a hider's body sinks into a spot of this kind (m): crouched down in a
## hedge, down in the bin, standing in a shed.
static func _sink_of(spot: Node3D) -> float:
	match str(spot.get("spot_kind")):
		"hedge":
			return Constants.HIDE_HEDGE_CROUCH
		"bin":
			return Constants.HIDE_BIN_CROUCH
	return 0.0


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## The body's sink into a pile, a hedge or a bin, on its CartoonBody (every peer).
## Sunk into a hedge or a bin, the legs hang straight down inside it, whatever the
## dive's tuck or the climb-out's kick is doing (R2c hide fixes: kicking 0.6 m
## down, the shoes stuck out of the hedge's foot under the cap on its crown).
func _apply_drop() -> void:
	var drop := Constants.HIDE_PILE_SINK * _sunk * _sunk + _dive_drop
	if drop <= 0.0 and _dropped <= 0.0:
		return
	_dropped = drop
	var body := player.get_node_or_null("Visual/CartoonBody") as Node3D
	if body == null:
		return
	body.position.y = -drop
	if _dive_sink <= 0.0 or _dive_drop <= 0.0 or not body.has_method("pose_part"):
		return
	var held := clampf(_dive_drop / _dive_sink / Constants.HIDE_LEGS_HANG_FROM, 0.0, 1.0)
	for side: String in ["leg_l", "leg_r"]:
		var leg := body.call("pose_part", side) as Node3D
		if leg != null:
			leg.rotation = leg.rotation.lerp(Vector3.ZERO, held)


## The head rides the body through the hide moves (every peer, and your own
## body seen from over the shoulder; never your own first-person camera, which
## lives in that head): on the torso's collar as it bends, tucks and sinks, the
## face tipped with it. Eased on and off so it never jumps.
func _carry_head(delta: float) -> void:
	var body := player.get_node_or_null("Visual/CartoonBody") as Node3D
	var head := player.get_node_or_null("Visual/Head") as Node3D
	if body == null or head == null or not body.has_method("pose_part"):
		return
	if is_owner_view() and _first_person():
		_carry = 0.0
		return
	var gesture := str(body.call("current_gesture")) if body.has_method("current_gesture") else ""
	var want := CARRY_GESTURES.has(gesture) or _dropped > 0.0 or _remote_progress > 0.0
	_carry = move_toward(_carry, 1.0 if want else 0.0, delta / maxf(Constants.HIDE_HEAD_CARRY_EASE, 0.01))
	if _carry <= 0.0:
		return
	var torso := body.call("pose_part", "torso") as Node3D
	var face := body.call("pose_part", "face") as Node3D
	if torso == null or head.get_parent() == body:
		return
	var neck := float(body.get("_head_base_y")) - 0.82 if "_head_base_y" in body else 0.78
	var collar := torso.global_position + torso.global_basis.orthonormalized() * Vector3(0.0, neck, 0.0)
	var parent := head.get_parent() as Node3D
	var w := _HideSpotLook._smooth(_carry)
	head.position = head.position.lerp(parent.global_transform.affine_inverse() * collar, w)
	if face != null:
		face.rotation.x += torso.rotation.x * 0.8 * w


func is_owner_view() -> bool:
	return player != null and player.is_multiplayer_authority()


## True while the body is on a dive, climb-out, bonk or lift: player.gd's
## movement leaves it alone.
func is_moving() -> bool:
	return _move != Move.NONE


## True while waiting on the host for a dive (E is ignored meanwhile).
func is_waiting() -> bool:
	return _waiting != null or _waiting_pile


## True from the moment a NICE BOY finds this player in a spot or a pile until
## they're out: his hands are on them, so E and walking don't climb out. Only
## the one he found (not a shed's other occupant), and only for as long as the
## find plays out: an old find in a spot never holds whoever dives in next.
func is_found() -> bool:
	if _spot == null and not bool(player.get("in_pile")):
		return false
	return _find_on_me(_inspection()) > -999.0


## The server time a NICE BOY found this player in view (an _inspection()), or
## -1000 when the find there is on someone else, over, or not a find at all.
func _find_on_me(view: Dictionary) -> float:
	var found_at := float(view.get("found_at", -1000.0))
	if found_at < -999.0 or found_at < float(view.get("poke_at", -1000.0)) - 0.01:
		return -1000.0
	var peer := int(view.get("found_peer", 0))
	if peer != 0 and player != null and peer != player.name.to_int():
		return -1000.0
	if Net.server_time() - found_at > _HideSpotLook.found_hold_seconds():
		return -1000.0
	return found_at


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
	ahead = ahead.normalized() if ahead.length() > 0.01 else Vector3.FORWARD
	_to = _pile_landing(_from, ahead)
	_peak = 0.75
	_start_move(Move.PILE_DIVE, Constants.HIDE_ENTER_SECONDS)
	_gesture("pile_cannonball", "startle")
	player.call("say_to_all", "vo_heave")
	_duck_music()
	_place_pile_anchor(ahead)
	_push_pile_shot(Constants.HIDE_ENTER_SECONDS)


## Where the cannonball lands (R2c hide fixes): a short hop in, or farther into a
## deep heap, so its face (where the eye looks out, and the NICE BOY reaches in)
## is HIDE_PILE_FACE ahead of the body and inside the mound over it. Never
## through a wall or a fence.
func _pile_landing(from: Vector3, ahead: Vector3) -> Vector3:
	var hop := from + ahead * 0.25
	var face := _face_out(hop, ahead, PILE_EYE_AHEAD, PILE_EYE_AHEAD + Constants.HIDE_PILE_DIVE_REACH)
	var carry := clampf(face - PILE_EYE_AHEAD, 0.0, Constants.HIDE_PILE_DIVE_REACH)
	if carry > 0.0 and player.is_inside_tree():
		var lift := Vector3(0.0, 0.5, 0.0)
		# The world's walls and fences (layer 1), not whatever's in your hands.
		var ray := PhysicsRayQueryParameters3D.create(from + lift, hop + ahead * (carry + 0.35) + lift, 1)
		ray.exclude = [player.get_rid()]
		var hit := player.get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty():
			carry = clampf(Vector2(hit["position"].x - hop.x, hit["position"].z - hop.z).length() - 0.35, 0.0, carry)
	return hop + ahead * carry


## How far out from base along ahead (m, from `start`, at most `limit`) the raked
## heap first stands no taller than the pile's eye.
func _face_out(base: Vector3, ahead: Vector3, start: float, limit: float) -> float:
	var out := start
	while out < limit and _heap_above_ground(base + ahead * out) > PILE_EYE_HEIGHT - Constants.HIDE_PILE_EYE_UNDER:
		out += 0.1
	return minf(out, limit)


## E inside: burst out toward the side the view faces (the host decides).
func request_exit() -> void:
	if not is_owner_view() or is_moving() or _spot == null or is_found():
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
	_dive_spot = spot
	_dive_side = side
	_dive_slot = slot
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
	_duck_music()
	_push_spot_shot(spot, side, slot, Constants.HIDE_ENTER_SECONDS)


func _begin_exit(to: Vector3, pulled: bool) -> void:
	_from = player.global_position
	_to = to
	var top := 1.6
	if _spot != null:
		top = (_spot.get("box_size") as Vector3).y
		if str(_spot.get("spot_kind")) == "shed":
			top = 0.0
	if pulled:
		# Hauled out through the gap he opened, onto your feet: a hop, not a lift
		# over the top (a bin's rim still has to be cleared).
		_peak = Constants.HIDE_FOUND_HOP
		if _spot != null and str(_spot.get("spot_kind")) == "bin":
			_peak = maxf(_peak, top * 0.55 - _from.y + _spot.global_position.y)
	else:
		# Out through the side with a hop, not a leap over the top.
		_peak = (top * 0.4) if top > 0.0 else 0.0
	_face_toward(to)
	_start_move(Move.PULL if pulled else Move.EXIT, Constants.HIDE_PULL_SECONDS if pulled else Constants.HIDE_EXIT_SECONDS)
	_gesture("upsy_daisy_victim" if pulled else "burst_out", "flail" if pulled else "startle")
	player.call("say_to_all", "vo_yelp" if pulled else "vo_hup")
	# The eye settles a beat after the feet land, so the landing's last drop eases.
	_pop_shot((Constants.HIDE_EXIT_SECONDS if not pulled else Constants.HIDE_PULL_SECONDS) + 0.15)


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
	_dive_spot = null
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
	_pulled_from = null
	_burst_pile(player.global_position)
	_play_at("pile_pop", player.global_position)
	_hat_leaf_on()
	if not is_owner_view():
		_gesture("upsy_daisy_victim" if pulled_to.is_finite() else "burst_out", "startle")
		return
	_from = player.global_position
	var ahead := _view_forward()
	_to = pulled_to if pulled_to.is_finite() else _from + ahead * 0.7
	_to.y = _from.y
	_peak = Constants.HIDE_FOUND_HOP if pulled_to.is_finite() else 0.6
	if pulled_to.is_finite():
		_face_toward(_to)
	_start_move(Move.PULL if pulled_to.is_finite() else Move.PILE_POP, Constants.HIDE_PULL_SECONDS if pulled_to.is_finite() else Constants.HIDE_EXIT_SECONDS)
	_gesture("upsy_daisy_victim" if pulled_to.is_finite() else "burst_out", "startle")
	_pop_shot(Constants.HIDE_PULL_SECONDS if pulled_to.is_finite() else Constants.HIDE_EXIT_SECONDS)


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
		_pop_shot(0.3)
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
	# Pulled out, you're set down by his hands, so the move eases in and out.
	var across := t * (1.12 - 0.12 * t) if _peak > 0.0 and _move != Move.PULL else eased
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
		if _move == Move.PULL:
			# Yanked up fast and set down on your feet by his hands, not dropped:
			# the arc flattens out as it lands (R2c hide: the eye fell 0.09 m in
			# the landing frame and stopped dead).
			lift = 6.75 * t * (1.0 - t) * (1.0 - t)
		at.y = lerpf(_from.y, _to.y, across) + maxf(0.0, _peak) * lift
	player.global_position = at
	player.velocity = Vector3.ZERO
	if _move == Move.PULL:
		_look_at_puller(delta)
		# Carried, not falling: no airborne flail, and no landing squash dipping
		# the eye as he sets you down.
		player.set("anim_state", 0)
	if t >= 1.0:
		var finished := _move
		_move = Move.NONE
		if finished == Move.EXIT or finished == Move.PULL or finished == Move.BONK or finished == Move.PILE_POP:
			player.call("on_hide_move_done")
		if finished == Move.PILE_DIVE and not bool(player.get("in_pile")) and not _waiting_pile:
			_pop_shot(0.3)
		if finished == Move.DIVE or finished == Move.PILE_DIVE:
			# Settled in, looking out the way the view does (the body isn't drawn now).
			player.set("body_yaw", facing_yaw())
			player.set("head_pitch", 0.0)


## Pulled out: your eyes stay on his face the whole way (your own camera rides
## your head, so the body and head turn to him).
func _look_at_puller(delta: float) -> void:
	var crew := _inspection().get("crew") as Node3D
	var face := _face_of(crew)
	if not face.is_finite():
		return
	var head := player.get_node_or_null("Visual/Head") as Node3D
	var eye := head.global_position if head != null else player.global_position + Vector3(0.0, 1.6, 0.0)
	var to := face - eye
	var flat := Vector2(to.x, to.z).length()
	if flat < 0.05:
		return
	var follow := clampf(delta * 12.0, 0.0, 1.0)
	player.set("body_yaw", lerp_angle(float(player.get("body_yaw")), atan2(-to.x, -to.z), follow))
	player.set("head_pitch", lerpf(float(player.get("head_pitch")), clampf(atan2(to.y, flat), -0.6, 0.6), follow))


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
			if _dive_side != _side or _dive_slot != _slot:
				_dive_side = _side
				_dive_slot = _slot
		elif _move != Move.DIVE:
			# Not predicted (a scenario, a late confirmation): dive now from here.
			_begin_dive(spot, _side, _slot)
		else:
			# Predicted, but the host picked another side or slot: aim there.
			_retarget(spot.call("inside_point", _side, _slot))
			_dive_side = _side
			_dive_slot = _slot
			_push_spot_shot(spot, _side, _slot, maxf(0.1, _move_length - _move_t))
	else:
		_remote_out_spot = null
		# Everyone else sees the same dive the owner plays, posed from how far the
		# body has come along it (_pose_remote_dive), so lag can't strand it upright
		# on the crown; it stops being drawn once it's in, or after a beat at most.
		var visual := player.get_node_or_null("Visual") as Node3D
		if Net.server_time() - at < Constants.BEAT_SKIP and visual != null:
			_remote_dive_from = visual.global_position
			_hide_by_ms = Time.get_ticks_msec() + int((Constants.HIDE_ENTER_SECONDS + Constants.HIDE_REMOTE_DIVE_SLACK) * 1000.0)
		else:
			_remote_dive_from = Vector3.INF
			_hide_by_ms = Time.get_ticks_msec() + int((Constants.HIDE_ENTER_SECONDS + 0.35) * 1000.0)
	_set_voice_muffled(true)


## From player.set_hidden_in(null, ...): out, toward exit_to (INF: where you are).
func on_unhidden(exit_to: Vector3, pulled: bool) -> void:
	var was := _spot
	var was_side := _side
	var was_slot := _slot
	_spot = null
	_dive_spot = null
	_pulled_from = was if pulled else null
	_exit_spot = was
	_remote_dive_from = Vector3.INF
	_set_voice_muffled(bool(player.get("in_pile")))
	if was != null and str(was.get("spot_kind")) == "hedge":
		_hat_leaf_on()
	if not is_owner_view():
		_gesture("upsy_daisy_victim" if pulled else "burst_out", "flail" if pulled else "startle")
		# Low in the spot, rising as the body comes clear of it (_pose_remote_dive).
		if was != null and is_instance_valid(was) and exit_to.is_finite():
			_remote_out_spot = was
			_remote_out_from = was.call("inside_point", was_side, was_slot)
			_remote_out_to = exit_to
			_remote_out_until = Time.get_ticks_msec() + int(((Constants.HIDE_PULL_SECONDS if pulled else Constants.HIDE_EXIT_SECONDS) + Constants.HIDE_REMOTE_DIVE_SLACK) * 1000.0)
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
		_pop_shot(0.3)


## From player.set_pile on every peer. fresh false: they were already in when
## this peer first saw them (a late join), so nothing replays; the mound is just there.
func on_pile(hidden: bool, fresh: bool = true) -> void:
	if hidden:
		# A new dive: whatever a NICE BOY found or missed in your last pile is over.
		_pile_poke_at = -1000.0
		_pile_found_at = -1000.0
		_pile_miss_at = -1000.0
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
			landing = Constants.HIDE_ENTER_SECONDS * 0.6
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
			_push_pile_shot(Constants.HIDE_CAM_BLEND)
	_set_voice_muffled(hidden or _spot != null)


## Every peer, from player._rpc_pile_inspect: a NICE BOY's pats on this player's
## pile (phase &"begin", &"near_miss", &"found" or &"cancel"), from server time at.
func on_pile_inspect(crew: Node3D, phase: StringName, at: float) -> void:
	match phase:
		&"begin":
			if crew != null:
				_pile_poke_crew = crew
			_pile_poke_at = at
			_pile_found_at = -1000.0
			_pile_miss_at = -1000.0
		&"found":
			if crew != null:
				_pile_poke_crew = crew
			_pile_found_at = at
			# Heard as long as the find is still playing out here (R2c hide: a lagged
			# peer used to drop the snatch).
			if Net.server_time() - at < Constants.HIDE_FOUND_REVEAL + Constants.HIDE_PULL_SECONDS:
				_later(maxf(0.0, Constants.HIDE_FOUND_REVEAL - Constants.HIDE_FOUND_GRAB_LEAD - (Net.server_time() - at)), func() -> void:
					_play_at("hide_grab", player.global_position + Vector3(0.0, 0.5, 0.0), 0.0, is_owner_view()))
				_burst_pile(player.global_position + Vector3(0.0, 0.4, 0.0))
		_:
			_pile_miss_at = at


## The inspection this player is under, from the spot or their own pile:
## {crew, poke_at, found_at, miss_at} (props/hide_spot.gd inspect_view).
func _inspection() -> Dictionary:
	if _spot != null and is_instance_valid(_spot) and _spot.has_method("inspect_view"):
		return _spot.call("inspect_view")
	if bool(player.get("in_pile")) or _move == Move.PULL:
		if _pile_poke_crew != null and is_instance_valid(_pile_poke_crew):
			return {"crew": _pile_poke_crew, "poke_at": _pile_poke_at, "found_at": _pile_found_at, "miss_at": _pile_miss_at}
	if _move == Move.PULL and _pulled_from != null and is_instance_valid(_pulled_from) and _pulled_from.has_method("inspect_view"):
		return _pulled_from.call("inspect_view")
	return {}


# ---------------------------------------------------------------- what gets drawn

## Whether the body, head, nameplate and arms should be drawn now (every peer).
func body_should_draw() -> bool:
	if player == null:
		return true
	var in_pile := bool(player.get("in_pile"))
	if is_owner_view():
		match _move:
			Move.DIVE, Move.PILE_DIVE:
				return _move_t / _move_length < 0.85
			Move.EXIT, Move.PULL, Move.BONK, Move.PILE_POP:
				return true
		return _spot == null and not in_pile
	if _spot != null:
		# Drawn until it has sunk all the way in (_pose_remote_dive), and never again
		# while they're in: the owner's climb-out reaches us before the host's word.
		return Time.get_ticks_msec() < _hide_by_ms and _remote_dive_from.is_finite() and _remote_progress < Constants.HIDE_REMOTE_DIVE_IN
	# The cannonball plays out (the replicated arc) and sinks into the leaves
	# before they close over them.
	return not in_pile or _pile_t() < 0.85


## Other peers: how far through the cannonball they are (0..1+, by local time).
func _pile_t() -> float:
	return float(Time.get_ticks_msec() - _pile_since_ms) / (Constants.HIDE_ENTER_SECONDS * 1000.0)


## Every frame on every peer, from player._process: the mound, the leaf on the
## head, the NICE BOY over a pile, the peek, the eye and the frame, the muffle.
func present(delta: float) -> void:
	if player == null:
		return
	_present_hat(delta)
	if not is_owner_view():
		# The eye rides along to where the cannonball lands, still facing the dive.
		if _pile_anchor != null and bool(player.get("in_pile")):
			_place_pile_anchor(-_pile_anchor.global_basis.z)
		return
	var hidden := _spot != null or bool(player.get("in_pile"))
	if bool(player.get("in_pile")) and _pile_anchor != null and not is_moving():
		_place_pile_anchor(-_pile_anchor.global_basis.z)
	_step_peek(delta, hidden)
	_keep_shot()
	_step_aim(delta, hidden)
	_step_eye(delta)
	_present_lens_clear()
	_present_inside(hidden, delta)
	_present_frame(hidden, delta)
	# The dive's own rustle lands crisp; the world goes muffled once you're in.
	_set_muffled(hidden and not is_moving())
	_sweep_muffle(delta)


func _step_peek(delta: float, hidden: bool) -> void:
	# Headless (tests, bots) has no mouse to capture.
	var mouse_ok := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or DisplayServer.get_name() == "headless"
	var want := hidden and not is_moving() and Input.is_action_pressed("secondary") and mouse_ok and not is_found()
	if bool(player.get("peeking")) != want:
		player.set("peeking", want)
	_peek = move_toward(_peek, 1.0 if want else 0.0, delta / maxf(Constants.HIDE_PEEK_EASE, 0.01))
	if hidden and want != _peeking_shot and _shot != &"" and _shot != SHOT_MOVE:
		_peeking_shot = want
		if _shot == SHOT_PEEK:
			# The rise is the eye's own; the wider view blends with the shot.
			player.call("stage_push", SHOT_PEEK, _peek_shot(Constants.HIDE_PEEK_EASE))
		elif _spot != null:
			_push_spot_shot(_spot, _side, _slot, Constants.HIDE_PEEK_EASE)
		elif bool(player.get("in_pile")):
			_push_pile_shot(Constants.HIDE_PEEK_EASE)


## A NICE BOY looking in: the frame parts where he pokes, the shed's boards jolt
## at each knock, and your view is drawn to his face (and your look eases back
## toward him, slower than a turn that would shake the hedge).
func _step_aim(delta: float, hidden: bool) -> void:
	var view := _inspection()
	var crew := view.get("crew") as Node3D
	var want := 0.0
	_aim_point = Vector3.INF
	if crew != null and (hidden or _move == Move.PULL):
		var found_at := float(view["found_at"])
		var miss_at := float(view["miss_at"])
		if found_at > -999.0 and _find_on_me(view) < -999.0:
			# He found someone else in here (a shed's other place): to you it's
			# him turning away with them, and your look is your own again.
			miss_at = maxf(miss_at, found_at)
			found_at = -1000.0
		var weights := _HideSpotLook.peer_weights(Net.server_time(), float(view["poke_at"]), found_at, miss_at)
		if not weights.is_empty():
			want = maxf(float(weights["lean"]), float(weights["grab"]))
			_aim_point = _face_of(crew)
	if not _aim_point.is_finite():
		want = 0.0
	_aim = move_toward(_aim, want, delta / maxf(Constants.HIDE_PEER_AIM_SECONDS, 0.01))
	if _aim > 0.0 and _shot == SHOT_PEEK:
		var cam := player.call("stage_cam") as Camera3D
		if cam != null:
			var look: Vector2 = cam.call("look_angles")
			var step := Constants.HIDE_PEER_LOOK_RETURN * _aim * delta
			var back := Vector2(signf(look.x) * minf(absf(look.x), step), signf(look.y) * minf(absf(look.y), step))
			var turn := Settings.look_scale()
			if back != Vector2.ZERO and turn.x != 0.0 and turn.y != 0.0:
				cam.call("add_look", Vector2(back.x / turn.x, back.y / turn.y))
	_shake = maxf(0.0, _shake - delta * 40.0)
	# The shed's three knocks (props/hide_spot.gd _poke).
	if _spot != null and str(_spot.get("spot_kind")) == "shed" and crew != null:
		var since := Net.server_time() - float(view["poke_at"])
		var knocks := 0
		for knock: int in 3:
			if since >= Constants.HIDE_POKE_SHED_KNOCKS.x + Constants.HIDE_POKE_SHED_KNOCKS.y * float(knock) and since < Constants.HIDE_INSPECT_SECONDS:
				knocks = knock + 1
		if knocks > _knocks_heard:
			_shake = 7.0
		_knocks_heard = knocks
	else:
		_knocks_heard = 0


## The world point of a NICE BOY's face (INF when there's none).
func _face_of(crew: Node3D) -> Vector3:
	if crew == null or not is_instance_valid(crew):
		return Vector3.INF
	var body := crew.get_node_or_null("Visual/CartoonBody")
	var face := body.call("pose_part", "face") as Node3D if body != null and body.has_method("pose_part") else null
	if face != null:
		return face.global_position
	return crew.global_position + Vector3(0.0, 1.6, 0.0)


## How far the spot has been pulled open around your eye (0..1): a little with
## each poke at a hedge or bin lid, all the way on a find.
func _part_now() -> float:
	var view := _inspection()
	if view.is_empty():
		return 0.0
	var now := Net.server_time()
	var poke_at := float(view["poke_at"])
	var found_at := float(view["found_at"])
	if found_at > -999.0 and found_at >= poke_at - 0.01:
		# Yanked open around his face; the lid or door drops shut again once
		# whoever he found is out (props/hide_spot.gd _found), so a shed's other
		# occupant sees it close, and an old find is just a shut spot.
		var since_found := now - found_at
		var shut := Constants.HIDE_FOUND_REVEAL + Constants.HIDE_PULL_SECONDS + Constants.HIDE_FOUND_SHUT_DELAY
		return _HideSpotLook._smooth(since_found / (Constants.HIDE_FOUND_REVEAL * 0.55)) * (1.0 - _HideSpotLook._smooth((since_found - shut) / Constants.HIDE_PEER_OUT_SECONDS))
	var miss_at := float(view["miss_at"])
	if poke_at < -999.0 or (miss_at > -999.0 and miss_at >= poke_at - 0.01) or now - poke_at > Constants.HIDE_INSPECT_SECONDS:
		return 0.0
	var kind := _frame_kind()
	var since := now - poke_at
	match kind:
		"bin":
			# He lifts the lid a crack and holds it (props/hide_spot.gd LID_POKE).
			return Constants.HIDE_POKE_BIN_PART * _HideSpotLook._smooth((since - Constants.HIDE_POKE_BIN_CRACK_AT) / 0.3)
		"pile":
			return Constants.HIDE_POKE_PILE_PART * absf(sin(since * 5.0)) * _HideSpotLook._smooth(since / 0.3)
		"hedge":
			# His two pushes into the hedge, each held a moment.
			var open := 0.0
			for push: float in Constants.HIDE_POKE_HEDGE_PUSHES:
				var x := since - push
				if x > 0.0:
					open = maxf(open, Constants.HIDE_POKE_HEDGE_PART * (_HideSpotLook._smooth(x / 0.12) - _HideSpotLook._smooth((x - 0.45) / 0.3)))
			return open
	return 0.0


func _frame_kind() -> String:
	var source := _spot if _spot != null else _waiting
	if source == null and _move == Move.DIVE:
		source = _dive_spot
	if source != null and is_instance_valid(source):
		return str(source.get("spot_kind"))
	if bool(player.get("in_pile")) or _waiting_pile or _move == Move.PILE_DIVE:
		return "pile"
	return ""


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
	var kind := _frame_kind()
	if kind != "":
		_frame.set("kind", kind)
	_frame.set("peek", _peek)
	_frame.set("turn_rate", _turn_rate)
	# Bursting out sweeps the frame open as it goes (the leaves off the edges with
	# the shell's, the lid up, the door aside) rather than fading it in place.
	if show:
		_leave_open = 0.0
	else:
		_leave_open = move_toward(_leave_open, 1.0, delta / maxf(Constants.HIDE_SHELL_OPEN_SECONDS, 0.01))
	_frame.set("part", maxf(_part_now(), _leave_open))
	_frame.set("shake", _shake)


# ---------------------------------------------------------------- the camera

## The hide shot for a spot: first person from the HideEye (carried to the spot's
## eye over `blend`, the view turning with the mouse, clamped round the spot's
## facing), third person orbiting it.
func _push_spot_shot(spot: Node3D, side: int, slot: int, blend: float) -> void:
	if not is_owner_view() or not player.has_method("stage_push"):
		return
	var first_person := _first_person()
	if first_person:
		_dive_spot = spot if _dive_spot == null else _dive_spot
		_eye_in(blend)
		return
	var id := SHOT_ORBIT
	if _shot != &"" and _shot != id:
		player.call("stage_pop", _shot, blend)
	_shot = id
	_shot_first_person = false
	player.call("stage_push", id, {
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
	})


## The pile: eyes just over the leaves, facing the way you dove.
func _push_pile_shot(blend: float = Constants.HIDE_ENTER_SECONDS) -> void:
	if not is_owner_view() or not player.has_method("stage_push"):
		return
	if _shot == &"" or _pile_anchor == null:
		_place_pile_anchor(-player.global_basis.z)
	var first_person := _first_person()
	if first_person:
		_eye_in(blend)
		return
	var id := SHOT_ORBIT
	if _shot != &"" and _shot != id:
		player.call("stage_pop", _shot, Constants.HIDE_CAM_BLEND)
	_shot = id
	_shot_first_person = false
	player.call("stage_push", id, {
		"anchor": _pile_anchor,
		"offset": _orbit_offset(),
		"blend_in": blend,
		"blend_out": Constants.HIDE_EXIT_SECONDS,
		"yaw_clamp": Vector2(-PI, PI),
		"pitch_clamp": Vector2(-0.9, 0.3),
		"orbit": true,
		"spring": true,
		"fov": 0.0,
		"lag": 0.0,
		"priority": SHOT_PRIORITY,
	})


## The first-person hide shot: hung off the HideEye, which carries the rise, the
## dive and the pull; mouse look on top of it within the clamps.
func _peek_shot(blend: float) -> Dictionary:
	# A knot hole lets you look about only a little: turned farther, the hole
	# would frame the shed's own planks (R2c hide).
	var shed := _frame_kind() == "shed"
	var yaw := Constants.HIDE_SHED_YAW_CLAMP if shed else Constants.HIDE_YAW_CLAMP
	return {
		"anchor": _ensure_eye(),
		"offset": Transform3D.IDENTITY,
		"blend_in": blend,
		"blend_out": Constants.HIDE_EXIT_SECONDS,
		"yaw_clamp": Vector2(-yaw, yaw),
		"pitch_clamp": Constants.HIDE_SHED_PITCH_CLAMP if shed else Constants.HIDE_PITCH_CLAMP,
		"orbit": false,
		"spring": false,
		"fov": _fov(),
		"lag": 0.0,
		"priority": SHOT_PRIORITY,
		"hide_self": true,
	}


func _ensure_eye() -> Marker3D:
	if _eye == null:
		_eye = Marker3D.new()
		_eye.name = "HideEye"
		_eye.top_level = true
		_eye.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(_eye)
		_eye.global_transform = _drawn_view()
	return _eye


## Carry the eye into the hide view over `seconds` (from wherever it's drawn now,
## or onward from where it is if it's already moving), under the peek shot.
func _eye_in(seconds: float) -> void:
	_ensure_eye()
	if _eye_mode == Eye.NONE or _eye_mode == Eye.OUT or _shot != SHOT_PEEK:
		_eye.global_transform = _drawn_view()
	_eye_from = _eye.global_transform
	_eye_t = 0.0
	_eye_len = maxf(seconds, 0.05)
	_eye_mode = Eye.IN
	if _shot != SHOT_PEEK:
		var was := _shot
		_shot = SHOT_PEEK
		_shot_first_person = true
		player.call("stage_push", SHOT_PEEK, _peek_shot(0.06 if was == &"" or was == SHOT_MOVE else Constants.HIDE_CAM_BLEND))
		if was != &"":
			player.call("stage_pop", was, 0.0)


## Carry the eye from where it's drawn now back to your own camera over
## `seconds` (no mouse look on the way), then hand the view back with no blend:
## by then they're the same.
func _eye_out(seconds: float) -> void:
	_ensure_eye()
	_eye.global_transform = _drawn_view()
	_eye_from = _eye.global_transform
	_eye_t = 0.0
	_eye_len = maxf(seconds, 0.1)
	_eye_mode = Eye.OUT
	player.call("stage_push", SHOT_MOVE, {
		"anchor": _eye,
		"offset": Transform3D.IDENTITY,
		"blend_in": 0.12,
		"blend_out": 0.0,
		"yaw_clamp": Vector2.ZERO,
		"pitch_clamp": Vector2.ZERO,
		"fov": Settings.fov(),
		"lag": 0.0,
		"priority": SHOT_PRIORITY + 1,
		"hide_self": true,
	})
	if _shot == SHOT_PEEK:
		player.call("stage_pop", SHOT_PEEK, 0.0)
	_shot = SHOT_MOVE


func _step_eye(delta: float) -> void:
	if _eye_mode == Eye.NONE or _eye == null:
		return
	_eye_t += delta
	var t := clampf(_eye_t / _eye_len, 0.0, 1.0)
	match _eye_mode:
		Eye.IN:
			var target := _eye_target()
			if t >= 1.0:
				_eye.global_transform = target
				_eye_mode = Eye.HELD
			else:
				var view := _blend_view(_eye_from, target, t, true)
				if _pile_eye():
					# Over the heap's skin all the way down to its face, never under it
					# (from under the skin the lawn beneath the heap showed as a band).
					# ...and never back up over a crest it's already under: it only goes down.
					var over := _heap_top(view.origin) + Constants.HIDE_PILE_EYE_OVER
					var held := minf(maxf(view.origin.y, over), _eye.global_position.y)
					view.origin.y = lerpf(maxf(held, view.origin.y), view.origin.y, _HideSpotLook._smooth((t - 0.85) / 0.15))
				_eye.global_transform = view
		Eye.HELD:
			if _shot != SHOT_PEEK:
				_eye_mode = Eye.NONE
				return
			_eye.global_transform = _eye_target()
		Eye.OUT:
			var target := _base_view()
			if t >= 1.0 or _shot != SHOT_MOVE:
				_eye.global_transform = target
				_eye_mode = Eye.NONE
				if _shot == SHOT_MOVE:
					player.call("stage_pop", SHOT_MOVE, 0.0)
					_shot = &""
			else:
				_eye.global_transform = _blend_view(_eye_from, target, t, false)


## Where the eye is going while hidden: the spot's eye (or the pile's), raised by
## the peek, turned toward the NICE BOY's face as far as _aim says.
func _eye_target() -> Transform3D:
	var target := _eye.global_transform
	var pile := false
	if _spot != null and is_instance_valid(_spot):
		target = _spot.call("peek_transform", _side, _slot)
	elif _dive_spot != null and is_instance_valid(_dive_spot):
		target = _dive_spot.call("peek_transform", _dive_side, _dive_slot)
	elif _pile_anchor != null:
		target = _pile_anchor.global_transform
		pile = true
	else:
		return target
	var p := _peek * _peek * (3.0 - 2.0 * _peek)
	target.origin.y += Constants.HIDE_PEEK_RISE * (1.5 if pile else 1.0) * p
	if _aim > 0.0 and _aim_point.is_finite():
		var to := _aim_point - target.origin
		var flat := Vector2(to.x, to.z).length()
		if flat > 0.05:
			var base_yaw := _yaw_of(target.basis)
			var w := _aim * _aim * (3.0 - 2.0 * _aim)
			var yaw := base_yaw + clampf(angle_difference(base_yaw, atan2(-to.x, -to.z)), -Constants.HIDE_PEER_AIM_MAX, Constants.HIDE_PEER_AIM_MAX) * w
			var pitch := clampf(atan2(to.y, flat), -Constants.HIDE_PEER_AIM_PITCH_MAX, Constants.HIDE_PEER_AIM_PITCH_MAX) * w
			target.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	return target


## An eased move between two views with no roll: position and pitch smoothstep
## in and out; on a dive the turn round starts a little late, as you land.
func _blend_view(from: Transform3D, to: Transform3D, t: float, dive: bool) -> Transform3D:
	var s := t * t * (3.0 - 2.0 * t)
	var turn_t := clampf((t - 0.15) / 0.85, 0.0, 1.0) if dive else t
	var turn := turn_t * turn_t * (3.0 - 2.0 * turn_t)
	var yaw := lerp_angle(_yaw_of(from.basis), _yaw_of(to.basis), turn)
	var pitch := lerpf(_pitch_of(from.basis), _pitch_of(to.basis), s)
	return Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch), from.origin.lerp(to.origin, s))


static func _yaw_of(basis: Basis) -> float:
	var forward := -basis.z
	return atan2(-forward.x, -forward.z)


static func _pitch_of(basis: Basis) -> float:
	return asin(clampf(-basis.z.normalized().y, -1.0, 1.0))


## Where the view is really drawn from right now.
func _drawn_view() -> Transform3D:
	var cam := player.call("stage_cam") as Camera3D if player != null and player.has_method("stage_cam") else null
	if cam != null and cam.current:
		return cam.global_transform
	var shown := get_viewport().get_camera_3d() if is_inside_tree() else null
	if shown != null:
		return shown.get_global_transform_interpolated()
	return player.global_transform


## Your own camera (first person or over the shoulder), where it is now.
func _base_view() -> Transform3D:
	var cam := player.call("stage_cam") as Camera3D if player.has_method("stage_cam") else null
	var base := cam.call("base_camera") as Camera3D if cam != null else null
	if base != null and base.is_inside_tree():
		return base.get_global_transform_interpolated()
	return _drawn_view()


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
	var at := _to if is_owner_view() and _move == Move.PILE_DIVE else player.global_position
	# At the heap's face: out along the dive until the raked leaves there are no
	# taller than the eye (R2c hide: inside a big raked heap the eye sat among its
	# own leaf cards, a hand across at the lens), eased as the heap settles.
	# No farther out than the mound over the body reaches (HIDE_PILE_FACE_MAX):
	# the cannonball already carried the body in to where the face is near.
	var base := Vector3(at.x, player.global_position.y, at.z)
	var out := _face_out(base, ahead, PILE_EYE_AHEAD, Constants.HIDE_PILE_FACE_MAX)
	_eye_lift = lerpf(_eye_lift, out, 0.1) if bool(player.get("in_pile")) and _pile_anchor.is_inside_tree() and _eye_lift > 0.0 else out
	# A heap deeper than the mound reaches still has its skin over that point: the
	# eye rides up to just over it, peering out across the top of the leaves
	# (from under the skin the lawn beneath the heap showed as a flat green band).
	var rise := maxf(PILE_EYE_HEIGHT, _heap_above_ground(base + ahead * _eye_lift) + Constants.HIDE_PILE_EYE_OVER)
	_eye_rise = lerpf(_eye_rise, rise, 0.1) if bool(player.get("in_pile")) and _pile_anchor.is_inside_tree() and _eye_rise > 0.0 else rise
	var eye := base + Vector3(0.0, _eye_rise, 0.0) + ahead * _eye_lift
	_pile_anchor.global_transform = Transform3D(Basis.looking_at(ahead, Vector3.UP), eye)


## Back to your own camera: in first person the eye is carried home (_eye_out);
## the orbit blends out.
func _pop_shot(blend: float) -> void:
	_peeking_shot = false
	if _shot == &"" or not player.has_method("stage_pop"):
		_shot = &""
		return
	if _shot == SHOT_PEEK and is_owner_view():
		_eye_out(blend)
		return
	if _shot == SHOT_MOVE:
		return
	player.call("stage_pop", _shot, blend)
	_shot = &""


## The camera key while hidden swaps the peek for the orbit and back.
func _keep_shot() -> void:
	if _shot == &"" or _shot == SHOT_MOVE or is_moving():
		return
	if _first_person() != _shot_first_person:
		if _first_person():
			var was := _shot
			_ensure_eye()
			_eye.global_transform = _eye_target()
			_eye_mode = Eye.HELD
			_shot = SHOT_PEEK
			_shot_first_person = true
			player.call("stage_push", SHOT_PEEK, _peek_shot(Constants.HIDE_CAM_BLEND))
			player.call("stage_pop", was, 0.0)
		elif _spot != null:
			_push_spot_shot(_spot, _side, _slot, Constants.HIDE_CAM_BLEND)
		elif bool(player.get("in_pile")):
			_push_pile_shot(Constants.HIDE_CAM_BLEND)


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
		return _yaw_of((_spot.call("peek_transform", _side, _slot) as Transform3D).basis)
	if _pile_anchor != null:
		var ahead := -_pile_anchor.global_basis.z
		return atan2(-ahead.x, -ahead.z)
	return float(player.get("body_yaw"))


# ---------------------------------------------------------------- the inside of the spot

## In first person, settled in a hedge or bin: this machine draws the inside
## around your eye instead of the spot's own outside (its outer leaves, walls and
## lid would fill the view as you turn); a shed just loses the door you're behind.
## A pile gets its own shell of leaves (R2c hide). On the way out (climbing out,
## pulled out, or found: his hands tear it open) the shell is swept open off the
## edges of the view rather than dropped, and the spot's outside comes back only
## once the eye is clear of it, so neither pops nor sits at the lens.
func _present_inside(hidden: bool, delta: float) -> void:
	var pile := _spot == null and _dive_spot == null and (bool(player.get("in_pile")) or _waiting_pile or _move == Move.PILE_DIVE)
	var spot := _spot if _spot != null else _dive_spot
	if spot != null and not is_instance_valid(spot):
		spot = null
	var kind := "pile" if pile else (str(spot.get("spot_kind")) if spot != null else "")
	var arrived := _eye_mode == Eye.HELD or (_eye_mode == Eye.IN and _eye_t / _eye_len > (Constants.HIDE_SHED_DOOR_HIDE_AT if kind == "shed" else 0.85))
	var inside := kind != "" and _first_person() and _shot == SHOT_PEEK and arrived
	inside = inside and (hidden or _move == Move.DIVE or _move == Move.PILE_DIVE)
	# The spot whose outside this machine stops drawing (a pile has none).
	if inside and spot != null and _inside_of != spot:
		if _inside_of != null:
			_show_outside(_inside_of, true)
		_inside_of = spot
		_show_outside(spot, false)
	if _inside_of != null and not inside and (not _first_person() or _eye_clear_of(_inside_of)):
		_show_outside(_inside_of, true)
		_inside_of = null
	if inside and (_shell == null or _shell_kind != kind):
		if _shell != null:
			_shell.queue_free()
		_shell_kind = kind
		# A pile's leaves close in from the edges of the view as you sink, not in
		# one frame (R2c hide fixes); a hedge's or bin's outside is already gone.
		_shell_open = 1.0 if kind == "pile" else 0.0
		_shell = make_shell(kind)
		if _shell != null:
			_shell.top_level = true
			_shell.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			add_child(_shell)
	if _shell == null:
		return
	if inside:
		_shell_open = move_toward(_shell_open, 0.0, delta / maxf(Constants.HIDE_PILE_SHELL_RISE_SECONDS, 0.01)) if kind == "pile" else 0.0
		var base: Transform3D
		if pile and _eye != null:
			# A pile's leaves close round the lens itself, wherever it is on its way
			# down (R2c hide fixes: set at the end of the move, the eye still above it
			# saw the shell's outside as huge dark cards), facing the way it looks.
			base = Transform3D(Basis(Vector3.UP, _yaw_of(_eye.global_basis)) * Basis(Vector3.RIGHT, _pitch_of(_eye.global_basis)), _eye.global_position)
		else:
			base = _pile_anchor.global_transform if pile and _pile_anchor != null else spot.call("peek_transform", _side if _spot != null else _dive_side, _slot if _spot != null else _dive_slot)
			# The shell rises with the peeking eye, so peeking parts it instead of
			# lifting the eye into its top leaves.
			var p := _peek * _peek * (3.0 - 2.0 * _peek)
			base.origin.y += Constants.HIDE_PEEK_RISE * (1.5 if pile else 1.0) * p
		_shell_at = base
		# Your own peek's eye glints sit on your lens; others see them, you don't.
		var glint := spot.get_node_or_null("EyeGlint") as Node3D if spot != null else null
		if glint != null:
			glint.visible = false
	else:
		_shell_open = move_toward(_shell_open, 1.0, delta / maxf(Constants.HIDE_SHELL_OPEN_SECONDS, 0.01))
	var open := maxf(_shell_open, _found_tear())
	if open >= 1.0 and not inside:
		_shell.queue_free()
		_shell = null
		_shell_kind = ""
		return
	_shell.global_transform = _shell_at
	# Peeking parts the whole tangle a little (the wider peek view would otherwise
	# show more of its edge: the eye rose into leaves, R2c hide).
	var peek := _peek * _peek * (3.0 - 2.0 * _peek)
	if inside and _shell_kind == "pile" and _shell_open > 0.0:
		# A pile's leaves rise round you from below as you sink in (R2c hide fixes:
		# they came in one frame, or swept in as huge stretched shards); they're
		# swept open like a hedge's on the way out.
		_shell.global_position.y -= Constants.HIDE_PILE_SHELL_RISE * _HideSpotLook._smooth(_shell_open)
		open = _found_tear()
	var spread := 1.0 + Constants.HIDE_SHELL_OPEN_SPREAD * _HideSpotLook._smooth(open) + Constants.HIDE_PEEK_SPREAD * peek
	_shell.scale = Vector3(spread, spread, 1.0)
	# His hands part the leaves at its mouth; peeking parts them more.
	var rim := _shell.get_node_or_null("Rim") as Node3D
	if rim != null:
		var part := _part_now()
		rim.scale = Vector3(1.0 + part * 1.3 + peek * Constants.HIDE_PEEK_PART.x, 1.0 + part * 0.9 + peek * Constants.HIDE_PEEK_PART.y, 1.0)


## How far a find has torn the inside open around his hands (0..1, every frame on
## the hider's machine): it's all the way open before he pulls.
func _found_tear() -> float:
	var view := _inspection()
	var found_at := _find_on_me(view) if not view.is_empty() else -1000.0
	if found_at < -999.0:
		return 0.0
	return _HideSpotLook._smooth((Net.server_time() - found_at) / (Constants.HIDE_FOUND_REVEAL * Constants.HIDE_FOUND_TEAR_SHARE))


## Whether the eye is out of the spot's box (and a little more): its outside
## can be drawn again without a wall at the lens.
func _eye_clear_of(spot: Node3D) -> bool:
	if spot == null or not is_instance_valid(spot):
		return true
	var eye := spot.to_local(_drawn_view().origin)
	var half: Vector3 = (spot.get("box_size") as Vector3) * 0.5 + Vector3.ONE * Constants.HIDE_SHELL_CLEAR
	return absf(eye.x) > half.x or absf(eye.z) > half.z or eye.y > half.y * 2.0 or eye.y < -Constants.HIDE_SHELL_CLEAR


func _show_outside(spot: Node3D, on: bool) -> void:
	if spot == null or not is_instance_valid(spot):
		return
	var parts: Array = ["Look/Door"] if str(spot.get("spot_kind")) == "shed" else ["Look", "Tells", "Notices"]
	for path: String in parts:
		var node := spot.get_node_or_null(path) as Node3D
		if node != null:
			node.visible = on


## The inside of a spot around the eye, in the eye's own space (looking down -Z):
## a hedge's dim tangle of leaves and twigs with a ragged opening ahead ("Rim",
## the leaves his hands pull apart, and "Back"), or a bin's dark tub walls round
## the slit. null for a shed (its own walls are there).
static func make_shell(kind: String) -> Node3D:
	match kind:
		"hedge":
			return _hedge_shell()
		"bin":
			return _bin_shell()
		"pile":
			# Under the leaves (R2c hide): a dim tangle of orange and brown round a low,
			# ragged opening at ground level, the lawn and the raked pile's own big
			# cards hidden behind it.
			var autumn: Array[Color] = [Color(0.62, 0.3, 0.09), Color(0.7, 0.48, 0.13), Color(0.52, 0.18, 0.08), Color(0.42, 0.26, 0.1), Color(0.58, 0.4, 0.12)]
			return _hedge_shell(autumn, Constants.HIDE_PILE_SHELL_OPENING, Constants.HIDE_PILE_SHELL_OPENING_DIP, 7177, 0.0)
	return null


const HEDGE_SHELL_GREENS: Array[Color] = [Color(0.13, 0.28, 0.12), Color(0.18, 0.36, 0.15), Color(0.1, 0.22, 0.1), Color(0.26, 0.42, 0.16)]


static func _hedge_shell(greens: Array[Color] = HEDGE_SHELL_GREENS, opening: Vector2 = Constants.HIDE_SHELL_OPENING, dip: float = 0.0, seed_value: int = 6061, twig_count: float = 9.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Shell"
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var radius := Constants.HIDE_SHELL_RADIUS
	var rim_kit := _MeshKit.new()
	var back_kit := _MeshKit.new()
	# Two layers of leaves: small ones close round the eye, and big dark ones
	# behind them so no sky shows through the gaps; the opening ahead stays clear.
	for layer: int in 2:
		var count := 460 if layer == 0 else 760
		for index: int in count:
			# A point on the sphere, not in the opening ahead.
			var u := rng.randf_range(-1.0, 1.0)
			var a := rng.randf() * TAU
			var r2 := sqrt(1.0 - u * u)
			var d := Vector3(r2 * cos(a), u, r2 * sin(a))
			var ahead := -d.z
			var across := atan2(d.x, ahead)
			# A pile's opening sits low, at ground level (dip rad under the axis).
			var up := atan2(d.y, ahead) + dip
			var widen := 1.0 if layer == 0 else 1.25
			if ahead > 0.0 and absf(across) < opening.x * widen and absf(up) < opening.y * widen:
				continue
			var near_mouth := layer == 0 and ahead > 0.25 and absf(across) < opening.x * 1.7 and absf(up) < opening.y * 1.9
			var at := d * radius * (rng.randf_range(0.78, 1.08) if layer == 0 else rng.randf_range(1.2, 1.45))
			# Facing in toward the eye, tipped every which way.
			var normal := (-d + Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5))).normalized()
			var green := greens[rng.randi() % greens.size()]
			# Light comes in at the mouth; it's dark at the back and deep in.
			var lit := 0.35 * clampf(ahead, 0.0, 1.0) + rng.randf_range(-0.05, 0.08) - (0.45 if layer == 1 else 0.0)
			var color := green.lightened(lit) if lit > 0.0 else green.darkened(-lit)
			var kit: RefCounted = rim_kit if near_mouth else back_kit
			var leaf_size := rng.randf_range(0.04, 0.075) if layer == 0 else rng.randf_range(0.11, 0.18)
			kit.call("leaf_card", at, normal, leaf_size, color, 0.6, rng.randf() * TAU)
	# A few twigs crossing the tangle.
	for index: int in int(twig_count):
		var a := rng.randf() * TAU
		var start := Vector3(cos(a) * radius * 1.15, rng.randf_range(-0.6, 0.6) * radius, rng.randf_range(0.0, 0.9) * radius)
		var end := start + Vector3(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.1))
		back_kit.tube(PackedVector3Array([start, end]), PackedFloat32Array([0.005, 0.003]), Color(0.28, 0.2, 0.12), 5, {"jitter": 0.0})
	for pair: Array in [["Back", back_kit], ["Rim", rim_kit]]:
		var mesh := _Stylized.instance((pair[1] as RefCounted).call("commit"), {"roughness": 0.95, "double_sided": true, "wind": 0.03, "translucency": 0.25})
		mesh.name = str(pair[0])
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mesh)
	return root


static func _bin_shell() -> Node3D:
	var root := Node3D.new()
	root.name = "Shell"
	var kit := _MeshKit.new()
	# The tub around you (R2c hide: it was flat black slabs): molded plastic in the
	# bin's dark green, lit from the slit ahead and falling off into the dark at
	# the back, with ribs down the walls, a rolled rim at the slit and the lid's
	# ribbed underside over it.
	var plastic := Color(0.13, 0.19, 0.16)
	var slices := 6
	for slice: int in slices:
		var z0 := -0.06 + 0.72 * float(slice) / float(slices)
		var depth := 0.72 / float(slices)
		var light := 1.0 - float(slice) / float(slices - 1)
		var wall := plastic.darkened(0.55 - 0.45 * light)
		for side: float in [-1.0, 1.0]:
			kit.box(Vector3(side * 0.42, -0.35, z0 + depth * 0.5), Vector3(0.03, 1.0, depth + 0.002), wall)
			# A molded rib standing off the wall, catching the light.
			kit.box(Vector3(side * 0.4, -0.35, z0 + depth * 0.5), Vector3(0.02, 0.98, 0.035), wall.lightened(0.12))
		kit.box(Vector3(0.0, -0.85, z0 + depth * 0.5), Vector3(0.87, 0.03, depth + 0.002), wall.darkened(0.35))
		# The lid's underside: ribs across it.
		kit.box(Vector3(0.0, 0.16, z0 + depth * 0.5), Vector3(0.87, 0.03, depth + 0.002), wall.darkened(0.15))
		kit.box(Vector3(0.0, 0.14, z0 + depth * 0.5), Vector3(0.85, 0.02, 0.03), wall.lightened(0.08))
	kit.box(Vector3(0.0, -0.35, 0.67), Vector3(0.87, 1.0, 0.03), plastic.darkened(0.6))
	# The rolled rim along the bottom of the slit and the lid's lip along its top.
	kit.tube(PackedVector3Array([Vector3(-0.43, -0.13, -0.05), Vector3(0.43, -0.13, -0.05)]), PackedFloat32Array([0.025, 0.025]), plastic.lightened(0.15), 8, {"jitter": 0.0})
	kit.box(Vector3(0.0, 0.12, -0.04), Vector3(0.87, 0.05, 0.04), plastic.lightened(0.05))
	# A crumpled bag and a juice box keeping you company.
	kit.blob(Vector3(0.18, -0.7, 0.42), Vector3(0.16, 0.12, 0.14), Color(0.12, 0.13, 0.12), {"detail": 1, "lumps": 0.5, "seed": 3})
	kit.box(Vector3(-0.2, -0.78, 0.25), Vector3(0.06, 0.1, 0.04), Color(0.7, 0.3, 0.2))
	var mesh := _Stylized.instance(kit.commit(), {"roughness": 0.6, "double_sided": true})
	mesh.name = "Back"
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mesh)
	return root


# ---------------------------------------------------------------- sound

## The world through the wall: music and effects muffled while you're inside,
## and the chase music's "hide" section whenever you're hidden in a chase (asked
## again whenever that changes, so hiding during the warning holds it once the
## chase starts).
func _set_muffled(on: bool) -> void:
	var music := get_tree().get_first_node_in_group("music_director")
	if on:
		# Re-asserted every frame: the phone or pause menu closing must not undo it.
		if not _Buses.is_muffled():
			_Buses.set_muffled(true)
		# ...and the effects filter, if anything took it off the bus.
		if not world_muffled():
			_set_sfx_filter(true)
	var director := get_tree().get_first_node_in_group("run_director")
	var chasing := director != null and director.has_method("phase") and int(director.call("phase")) == 2
	var want_section := on and chasing
	if music != null and music.has_method("request_section") and want_section != _music_hide:
		_music_hide = want_section
		music.call("request_section", &"hide", want_section)
	if on == _muffled:
		return
	_muffled = on
	_muffle_t = 0.0
	if not on:
		var keep := music != null and music.has_method("is_muffling") and bool(music.call("is_muffling"))
		_Buses.set_muffled(keep)
	_set_sfx_filter(on)


## Settling in: the world's top end goes away over a beat, not in one frame.
func _sweep_muffle(delta: float) -> void:
	if not _muffled or _sfx_filter == null:
		return
	_muffle_t += delta
	var s := clampf(_muffle_t / maxf(Constants.HIDE_MUFFLE_SWEEP_SECONDS, 0.01), 0.0, 1.0)
	s = s * s * (3.0 - 2.0 * s)
	_sfx_filter.cutoff_hz = Constants.HIDE_MUFFLE_FROM_HZ * pow(Constants.HIDE_MUFFLE_HZ / Constants.HIDE_MUFFLE_FROM_HZ, s)


func _set_sfx_filter(on: bool) -> void:
	var bus := AudioServer.get_bus_index(_Buses.SFX)
	if bus < 0:
		return
	if _sfx_filter == null:
		_sfx_filter = AudioEffectLowPassFilter.new()
		# 24 dB an octave: a 6 dB slope left birds, wind and the chase's hats ringing through.
		_sfx_filter.db = AudioEffectFilter.FILTER_24DB
	_sfx_filter.cutoff_hz = Constants.HIDE_MUFFLE_FROM_HZ
	var slot := -1
	for index: int in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, index) == _sfx_filter:
			slot = index
	if on and slot < 0:
		AudioServer.add_bus_effect(bus, _sfx_filter)
	elif not on and slot >= 0:
		AudioServer.remove_bus_effect(bus, slot)


## The music dips under your own dive (your lid, your clang, your rustle).
func _duck_music() -> void:
	var music := get_tree().get_first_node_in_group("music_director") if is_inside_tree() else null
	if music != null and music.has_method("duck"):
		music.call("duck", Constants.HIDE_DIVE_DUCK_DB, Constants.HIDE_DIVE_DUCK_SECONDS)


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
## (Constants.HIDE_CLEAR_CREW_METERS): SfxClear skips the muffle and keeps the
## effects volume (audio/buses.gd).
static func clear_bus_for(tree: SceneTree, at: Vector3) -> StringName:
	for node: Node in tree.get_nodes_in_group("players"):
		var body := node as Node3D
		if body != null and body.is_multiplayer_authority() and bool(body.call("is_hidden")) and body.global_position.distance_to(at) <= Constants.HIDE_CLEAR_CREW_METERS:
			return _Buses.SFX_CLEAR
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
	low_pass.db = AudioEffectFilter.FILTER_18DB
	AudioServer.add_bus_effect(index, low_pass)


func is_voice_muffled() -> bool:
	return _voice_muffled


# ---------------------------------------------------------------- the pile and the leaf hat

## A taller, darker mound over a hidden player, with their shoe poking out,
## breathing a little (every peer). It grows up around them as the cannonball
## lands and they sink into it, and the leaves close over the top.
func _present_mound() -> void:
	var in_pile := bool(player.get("in_pile"))
	var landing := 1.0
	if is_owner_view():
		landing = _move_t / _move_length if _move == Move.PILE_DIVE else 1.0
	else:
		landing = _pile_t()
	var show := in_pile and landing >= 0.55
	if show and _mound == null:
		_mound = _make_mound()
		# On the drawn body (smoothed on other peers), so it sits where they see them land.
		var visual := player.get_node_or_null("Visual") as Node3D
		(visual if visual != null else player).add_child(_mound)
		_mound_since_ms = Time.get_ticks_msec()
		_mound.scale = Vector3.ONE * Constants.HIDE_PILE_MOUND_FROM
		_mound_lift = _heap_above_ground(player.global_position) - Constants.HIDE_PILE_MOUND_SEAT
	elif not show and _mound != null:
		# Flattened as they burst out of it, not gone in a frame (R2c hide fixes).
		var old := _mound
		_mound = null
		# It stays where it was while the body leaves.
		if player.get_parent() != null:
			old.reparent(player.get_parent())
		var tween := old.create_tween().set_parallel()
		tween.tween_property(old, "scale", Vector3(old.scale.x * 0.8, 0.02, old.scale.z * 0.8), Constants.HIDE_PILE_MOUND_FLATTEN).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(old, "position:y", old.position.y - 0.15, Constants.HIDE_PILE_MOUND_FLATTEN)
		tween.chain().tween_callback(old.queue_free)
	# The body sinks into the leaves between the landing and being gone.
	var sink := clampf((landing - 0.55) / 0.3, 0.0, 1.0) if in_pile else 0.0
	if not in_pile:
		sink = 0.0
	_sunk = sink
	if _mound != null:
		_mound.global_rotation = Vector3.ZERO
		# On top of the raked heap it's in, not at lawn level (R2c hide: the leaves
		# still landing on a fresh pile buried it, and the hider's pile read as any
		# other one).
		_mound_lift = lerpf(_mound_lift, _heap_above_ground(player.global_position) - Constants.HIDE_PILE_MOUND_SEAT, clampf(get_physics_process_delta_time() * 6.0, 0.0, 1.0))
		_mound.position.y = maxf(0.0, _mound_lift)
		var grow := clampf(float(Time.get_ticks_msec() - _mound_since_ms) / (Constants.HIDE_PILE_MOUND_GROW * 1000.0), 0.0, 1.0)
		grow = 1.0 - pow(1.0 - grow, 3.0)
		var size := lerpf(Constants.HIDE_PILE_MOUND_FROM, 1.0, grow)
		# Scooped open around his hands when he finds you.
		var scoop := 0.0
		var since_found := Net.server_time() - _pile_found_at
		if _pile_found_at > -999.0 and _pile_found_at >= _pile_poke_at - 0.01 and since_found <= _HideSpotLook.found_hold_seconds():
			scoop = _HideSpotLook._smooth(since_found / (Constants.HIDE_FOUND_REVEAL * 0.6))
		_mound.scale = Vector3(size * (1.0 + 0.25 * scoop), size * (1.0 - 0.45 * scoop), size * (1.0 + 0.25 * scoop))
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
	# A dark lumpy heart under the leaves (only glimpsed between them), then the
	# leaves themselves: a thick shag of cards over every part of it.
	kit.blob(Vector3(0.0, 0.18 * size.y, 0.0), Vector3(0.62 * size.x, 0.36 * size.y, 0.62 * size.z), Color(0.36, 0.18, 0.07).darkened(dark), {"detail": 1, "lumps": 0.45, "lump_scale": 2.6, "flat": true, "jitter": 0.12, "seed": 7})
	var rng := RandomNumberGenerator.new()
	rng.seed = player.name.to_int() * 31 + 5
	for index: int in 150:
		var a := rng.randf() * TAU
		var up := sqrt(rng.randf())
		var normal := Vector3(cos(a) * (1.0 - up * 0.8), up, sin(a) * (1.0 - up * 0.8)).normalized()
		var at := Vector3(normal.x * 0.7 * size.x, 0.2 * size.y + normal.y * 0.42 * size.y, normal.z * 0.7 * size.z) * rng.randf_range(0.92, 1.06)
		var tipped := (normal + Vector3(rng.randf_range(-0.7, 0.7), rng.randf_range(-0.2, 0.5), rng.randf_range(-0.7, 0.7))).normalized()
		kit.leaf_card(at, tipped, rng.randf_range(0.09, 0.15), colors[rng.randi() % colors.size()].darkened(dark * rng.randf_range(0.3, 1.0)), 0.3, rng.randf() * TAU)
	var mesh := _Stylized.instance(kit.commit(), {"roughness": 0.92, "double_sided": true, "wind": 0.02})
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


## How high the leaf heap stands at a point over the lawn (m; 0 with no leaf view).
func _heap_above_ground(at: Vector3) -> float:
	var view := get_tree().get_first_node_in_group("leaf_view") if is_inside_tree() else null
	if view == null or not view.has_method("surface_y"):
		return 0.0
	return maxf(0.0, float(view.call("surface_y", Vector2(at.x, at.z))) - player.global_position.y)


## The leaf heap's skin over a point (world y; -INF with no leaf view).
func _heap_top(at: Vector3) -> float:
	var view := get_tree().get_first_node_in_group("leaf_view") if is_inside_tree() else null
	if view == null or not view.has_method("surface_y"):
		return -INF
	return float(view.call("surface_y", Vector2(at.x, at.z)))


## The leaves a pile throws up; on your own screen in first person they keep off
## your lens (R2c hide fixes: one hung across the view as the eye went in).
func _burst_pile(at: Vector3) -> void:
	var lens := Vector3.INF
	if is_owner_view() and _first_person():
		lens = _pile_anchor.global_position if _pile_anchor != null and bool(player.get("in_pile")) else _drawn_view().origin
	_HideSpotLook.burst(player.get_parent(), at, 16, _HideSpotLook.LEAF_COLORS, 3.0, _rng, lens, Constants.HIDE_PILE_BURST_CLEAR)


## Owner, first person: whether the eye is on its way into, in, or out of a pile.
func _pile_eye() -> bool:
	return _spot == null and _dive_spot == null and _pile_anchor != null and (bool(player.get("in_pile")) or _waiting_pile or _move == Move.PILE_DIVE or _move == Move.PILE_POP)


## Owner, first person, in or around a pile: the heap's own leaf cards fold away
## near the lens (leaves/leaf_shaders.gd leaf_clear), so none hangs across the
## view on the way in, inside, or climbing out. Off everywhere else.
var _lens_clear_until_ms: int = 0
var _lens_clear_on: bool = false


func _present_lens_clear() -> void:
	var now := Time.get_ticks_msec()
	if _first_person() and (_pile_eye() or (_move == Move.PULL and _pulled_from == null and _spot == null)):
		_lens_clear_until_ms = now + 600
	if now < _lens_clear_until_ms and _first_person():
		var eye := _drawn_view().origin
		RenderingServer.global_shader_parameter_set("leaf_clear", Vector4(eye.x, eye.y, eye.z, Constants.HIDE_PILE_LENS_CLEAR))
		_lens_clear_on = true
	elif _lens_clear_on:
		RenderingServer.global_shader_parameter_set("leaf_clear", Vector4.ZERO)
		_lens_clear_on = false


## A NICE BOY bent over this player's pile (every peer): props/hide_spot.gd's
## peer pose, as he does at a spot.
func _pose_pile_inspector() -> void:
	if _pile_poke_crew == null:
		return
	if not is_instance_valid(_pile_poke_crew):
		_pile_poke_crew = null
		return
	var weights := _HideSpotLook.peer_weights(Net.server_time(), _pile_poke_at, _pile_found_at, _pile_miss_at)
	var body := _pile_poke_crew.get_node_or_null("Visual/CartoonBody") as Node3D
	if weights.is_empty():
		_HideSpotLook.release_props(body)
		_pile_poke_crew = null
		return
	if body != null:
		var eye := _pile_anchor.global_transform if _pile_anchor != null else Transform3D(player.global_basis, player.global_position + Vector3(0.0, PILE_EYE_HEIGHT, 0.0))
		# His hands go into the mound's face at the hider's eye, not a gap's width
		# out in front of it (R2c hide fixes: they closed on air short of the leaves).
		var out := -eye.basis.z
		out.y = 0.0
		var in_mound := eye
		in_mound.origin -= out.normalized() * Constants.HIDE_GRIP_OUT if out.length() > 0.01 else Vector3.ZERO
		var grips := _HideSpotLook.grip_points(in_mound, player if _pile_found_at > -999.0 else null, float(weights["haul"]))
		_HideSpotLook.peer_pose(body, "pile", float(weights["lean"]), float(weights["grab"]), float(weights["haul"]), Net.server_time() - _pile_poke_at, grips, eye.origin)


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
		# Smoothed the way the hedge's shiver is (props/hide_spot.gd).
		_turn_rate = lerpf(_turn_rate, angle_difference(_last_yaw, yaw) / delta, 1.0 - exp(-delta / Constants.HIDE_TREMBLE_SMOOTH))
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
	return player.global_position + ahead.normalized() * (maxf(_eye_lift, Constants.HIDE_PILE_FACE) + Constants.HIDE_PILE_STAND)


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


## clear: at your own ears while you hide, past the muffle (audio/sfx.gd play_clear).
func _play_at(id: String, at: Vector3, db: float = 0.0, clear: bool = false) -> void:
	var sfx := get_tree().get_first_node_in_group("sfx") if is_inside_tree() else null
	if sfx == null:
		return
	if clear and sfx.has_method("play_clear"):
		sfx.call("play_clear", id, at, db)
	else:
		sfx.call("play_at", id, at, db)


func _later(seconds: float, what: Callable) -> void:
	if not is_inside_tree():
		return
	if seconds <= 0.0:
		what.call()
		return
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		if is_instance_valid(self) and is_inside_tree():
			what.call())


func _exit_tree() -> void:
	if _muffled:
		_set_muffled(false)
	if _music_hide:
		var music := get_tree().get_first_node_in_group("music_director")
		if music != null and music.has_method("request_section"):
			music.call("request_section", &"hide", false)
	if _inside_of != null:
		_show_outside(_inside_of, true)
	if _pile_anchor != null and is_instance_valid(_pile_anchor):
		_pile_anchor.queue_free()
	if _lens_clear_on:
		RenderingServer.global_shader_parameter_set("leaf_clear", Vector4.ZERO)
