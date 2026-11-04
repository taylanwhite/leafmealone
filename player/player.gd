extends CharacterBody3D

## Authority: owning peer for movement, look, and the values replicated below.
## Remote peers display those values. NetSmoother only moves the visual on remotes.

enum AnimState { IDLE, WALK, SPRINT, CROUCH, AIR, KNOCKED, SKATE, SKATE_AIR }

# TODO(balance): add movement speeds to the workbook.
const WALK_SPEED: float = 5.0
const SPRINT_SPEED: float = 8.0
const CROUCH_SPEED: float = 2.5
const JUMP_VELOCITY: float = 4.5
const _WaterSources = preload("res://net/work/water_sources.gd")
const STAND_HEIGHT: float = 1.8
const CROUCH_HEIGHT: float = 1.1
const PITCH_LIMIT: float = 1.2
## Nameplate color while that player is talking.
const SPEAKING_TINT := Color(1.0, 0.86, 0.35)
const _Strings = preload("res://ui/strings.gd")
const _CartoonBody = preload("res://player/cartoon_body.gd")
const _CharacterLife = preload("res://player/character_life.gd")
const _FirstPersonArms = preload("res://player/first_person_arms.gd")
const _SnackEater = preload("res://player/snack_eater.gd")
const _PlayerFoley = preload("res://audio/player_foley.gd")
const _PropLooks = preload("res://props/prop_looks.gd")
const _Pockets = preload("res://player/pockets.gd")
const _Hotbar = preload("res://net/components/hotbar.gd")
const _ToolTiers = preload("res://core/tool_tiers.gd")
const _KitRules = preload("res://core/kit_rules.gd")
const _Seated = preload("res://player/seated.gd")
const _Hats = preload("res://player/hats.gd")
const _HudMode = preload("res://ui/hud_mode.gd")

const _Skate = preload("res://player/skate.gd")
const _SkateView = preload("res://player/skate_view.gd")
## Share of jumps that get a "hup". Every jump would get old fast.
const HUP_CHANCE: float = 0.6

## Yaw of the body in radians. Replicated.
@export var body_yaw: float = 0.0
## Pitch of the head in radians. Replicated.
@export var head_pitch: float = 0.0
## Coarse pose shared with other peers. Replicated.
@export var anim_state: AnimState = AnimState.IDLE
## True while holding a throw too long. Replicated, so everyone sees the strain.
@export var straining: bool = false
## Hurt from a bad fall: walking with a limp and a bandaged leg. Replicated.
@export var limping: bool = false
## Run over by a mower: 1 a cut foot (bandaged, limping), 2 the foot came off
## (hopping on the other one until the job is paid). Replicated.
@export var foot_hurt: int = 0
## Equipped tool id. Empty until tools exist. Replicated.
## Dived into a pile of leaves (docs/FUN.md): hidden from the NICE BOYS unless
## one watched you go in. Replicated; the host decides (leaf_field.gd).
@export var in_pile: bool = false
## Peeking out of a hiding spot or a pile (hold secondary while hidden): the
## lid lifts, the door cracks, eyes glint in the hedge. Replicated; the owner sets it.
@export var peeking: bool = false
## Wearing something: 1 paint, 2 water. Replicated; the host decides (job_tasks.gd).
@export var coat: int = 0
## Brawling (net/components/brawl.gd): who this player carries, who carries
## them, whether they're flying through the air, and whether they're winding
## up a punch. Replicated; the host decides, the owner sets.
@export var carrying: int = 0
@export var carried_by: int = 0
@export var thrown: bool = false
@export var winding: bool = false
@export var equipment_id: String = ""
## The Gutter Shredder (player/skate.gd, driving chunk G1): riding the board, what
## the board is doing (skate.gd's TRICK_* values), down after a bail, and hanging
## on behind Chefty (driving G2). Replicated; the owner sets them.
@export var on_board: bool = false
@export var skate_trick: int = 0
@export var wipeout: bool = false
@export var skitch: bool = false
## Off a seat, as this player's own peer has it (p1-arrive): SEAT_STATE_SEATED on
## a seat or waiting on it for their turn to hop down, SEAT_STATE_SLIDING sliding
## out of a cab seat still sitting, 0 neither. Replicated with the position
## (always, in the same update), so another peer keeps drawing the rider on its
## own seat while the rider's own truck is still catching up and lets go only
## when the hop starts (net/components/net_smoother.gd), and draws them sitting
## on the way out of the door. The owner sets it.
@export var seat_state: int = 0
const SEAT_STATE_SEATED: int = 1
const SEAT_STATE_SLIDING: int = 2

var _look := Vector2.ZERO
var _ride: Node3D
var _seat_index: int = -1
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
## Hiding spot this player is inside, set by the host through net/components/hide_spot.gd.
var _hidden_spot: Node3D
var _last_anim: AnimState = AnimState.IDLE
var _on_seat: bool = false
## _dress_up has already waited once for this player's name.
var _dress_waited: bool = false
## The seed the body's own look comes from (the name), and when it was dressed
## (shops chunk 7: a look that lands right after is put on without the show).
var _dress_seed: int = 0
var _dressed_msec: int = 0
## World/Shops, looked up once (snack_buff).
var _shops_node: Node
var _step_wait: float = 0.0
## When H may honk again on Chefty's ride (game seconds).
var _honk_ready_at: float = 0.0
## Bonked by a thrown item: no control for this long. Knocked flat if the item was heavy.
var _stun_left: float = 0.0
var _knocked: bool = false
## A bonk that arrived over the network, applied on the next physics tick.
var _pending_bonk: Array = []
## Up a ladder: which one, and how far up (0 at the foot, 1 at the top).
var _ladder: Node3D
var _climb: float = 0.0
var _climb_target: float = 1.0
## Falling: the highest point since leaving the ground, whether a hard landing
## already bounced you (the next one knocks you out), and how long the limp lasts.
var _airborne: bool = false
var _fall_peak: float = 0.0
var _bounced: bool = false
var _limp_left: float = 0.0
## Holding G with something in hand: how long it's been wound up, and when the
## next strained noise is due.
var _wind_up: float = -1.0
var _coat_left: float = 0.0
var _punch_wind: float = -1.0
## What the left click held now went down as (crew-04): &"punch", &"hands" (a
## hand-raking stroke), &"spent" (it spun you out), or &"" while it's up.
var _press_kind: StringName = &""
## A test's left click for the punch (net/dev/hands_test.gd; a headless run has
## no captured mouse): -1 the real one, 0 up, 1 held.
var dev_primary: int = -1
var _punch_cool: float = 0.0
var _swing_left: float = 0.0
var _struggle: int = 0
var _thrown_left: float = 0.0
var _coat_shown: int = 0
var _next_strain: float = 0.0
## A notice over your head (flash_hint) and when it goes (ticks msec).
var _notice_text: String = ""
var _notice_until: int = 0
## The ride whose seat this player is on and which seat (every peer, from the
## ride's riders), and, on the owner, how far the head is turned from the seat's
## facing (player/seated.gd).
var _seat_ride: Node
var _seat_slot: int = -1
var seat_look: float = 0.0


func _enter_tree() -> void:
	add_to_group("players")
	# Runs after rides each tick, so a rider is placed where the seat is now.
	process_physics_priority = 100
	var peer_id := name.to_int()
	if peer_id <= 0:
		return
	# The synchronizer has to share this peer's authority or the client cannot publish its pose.
	set_multiplayer_authority(peer_id, true)


func _ready() -> void:
	%Collision.shape = %Collision.shape.duplicate()
	%CameraRig.set_active(is_multiplayer_authority())
	%Nameplate.visible = not is_multiplayer_authority()
	_refresh_name()
	if not Net.player_joined.is_connected(_on_player_joined):
		Net.player_joined.connect(_on_player_joined)
	if not Net.player_zone_changed.is_connected(_on_zone_changed):
		Net.player_zone_changed.connect(_on_zone_changed)
	if not Net.speaking_changed.is_connected(_on_speaking_changed):
		Net.speaking_changed.connect(_on_speaking_changed)
	if not is_multiplayer_authority():
		_attach_voice()
	else:
		# A toggle crouch tapped before this body existed doesn't spawn it crouched.
		Settings.release_toggles()
	if get_node_or_null("Pockets") == null:
		var pockets_node := _Pockets.new()
		pockets_node.name = "Pockets"
		add_child(pockets_node)
	_dress_up()
	_build_stage()
	_build_skate()
	_apply_presentation()


## The hotbar's player side (player/pockets.gd): the selected slot and what's in them.
func pockets() -> Node:
	return get_node_or_null("Pockets")


## The Gutter Shredder (driving G1): the riding (player/skate.gd, owner) and how it
## looks and sounds (player/skate_view.gd, every peer).
func skate() -> Node:
	return get_node_or_null("Skate")


func _build_skate() -> void:
	if get_node_or_null("Skate") == null:
		var riding := _Skate.new()
		riding.name = "Skate"
		riding.player = self
		add_child(riding)
	if get_node_or_null("SkateView") == null:
		var view := _SkateView.new()
		view.name = "SkateView"
		view.player = self
		add_child(view)


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	# A control lock still holds its actions back when _input let them through
	# to an open window that didn't want them.
	if not _locks.is_empty():
		for action: StringName in _STAGE_HELD_ACTIONS:
			if event.is_action(action) and not control_allows(String(action)):
				return
	# In a drivable vehicle's seat, E, F and the camera key are the seat's.
	if _Seated.handle_input(self, event):
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("board") and bool(skate().call("toggle")):
		get_viewport().set_input_as_handled()
	# On the board, jump and the clicks are tricks, never a punch or a swing.
	elif on_board and (event.is_action_pressed("jump") or event.is_action_pressed("primary") or event.is_action_pressed("secondary")):
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_camera"):
		%CameraRig.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("honk") and _honk():
		get_viewport().set_input_as_handled()
	# E is decided in _input (e_choice), ahead of everything else that listens for
	# it, so only the thing whose prompt is showing answers.
	elif event.is_action_pressed("take") and _take_ladder():
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("jump") and _ladder != null:
		_climb_target = 0.0
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("primary") and _whack():
		get_viewport().set_input_as_handled()
	# G (drop) is wound up and released in _wind_up, on physics ticks.
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_look += motion.relative


func _physics_process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	_seat_on_ride()
	if not _pending_bonk.is_empty():
		var bonk := _pending_bonk
		_pending_bonk = []
		_apply_bonk(bonk[0], bonk[1])
	if is_multiplayer_authority():
		_note_seat_state()
		if _stage_hold(delta): return
		_step_wind_up(delta)
		_step_punch(delta)
		if thrown:
			_thrown_left -= delta
			if _thrown_left < 1.2 and is_on_floor():
				thrown = false
				# Flung into a big pile: you're in it now.
				if _on_pile():
					get_tree().get_first_node_in_group("leaf_field").call("request_pile_hide")
		if _coat_left > 0.0:
			_coat_left -= delta
			if _coat_left <= 0.0:
				coat = 0
		# In a pile you're crouched down in the leaves; walking forward climbs out.
		# Standing in Chefty's bed you look out over the cab, not into the back of
		# its roof (driving C3: from a plain standing eye the cab filled half the view).
		# The bed's lift eases on and off (thrown out of the bed, it dropped 0.6 m in a frame).
		var eye_lift := Constants.CHEFTY_BED_EYE_LIFT if _Seated.pose_for(self) == 2 or _in_legacy_bed() else 0.0
		if in_pile:
			%FirstPerson.position.y = -1.05
		elif %FirstPerson.position.y < 0.0:
			%FirstPerson.position.y = eye_lift
		else:
			%FirstPerson.position.y = move_toward(%FirstPerson.position.y, eye_lift, Constants.CHEFTY_BED_EYE_EASE * delta)
		if in_pile and (Input.is_action_just_pressed("move_forward") or Input.is_action_just_pressed("jump")) and not bool(_hide_view().call("is_found")):
			set_pile(false)
		var seated_in_vehicle := in_vehicle()
		if not seated_in_vehicle:
			_apply_look()
		if seated_in_vehicle:
			_Seated.step(self, delta)
		elif is_stepping_down():
			_step_down(delta)
		elif _hidden_spot != null or in_pile or _hide_moving():
			velocity = Vector3.ZERO
		elif _step_sleep(delta):
			pass
		elif carried_by != 0:
			_step_carried(delta)
		elif _ladder != null:
			_step_climb(delta)
		elif _stun_left > 0.0 and _ride == null:
			_step_stunned(delta)
		elif _ride != null and _seat_index >= 0 and _ride.has_method("seat_transform"):
			var seat: Transform3D = _ride.call("seat_transform", _seat_index)
			global_position = seat.origin
			_follow_seat_yaw(seat)
		elif _on_seat and _seat_ride != null and _seat_ride.has_method("seat_transform"):
			# Still on a ride's seat after the zone changed (a client's truck easing
			# into the curb, ride.gd _step_catchup): no walking off it mid-drive.
			var held_seat: Transform3D = _seat_ride.call("seat_transform", _seat_slot)
			global_position = held_seat.origin
			velocity = Vector3.ZERO
			_follow_seat_yaw(held_seat)
		elif on_board:
			skate().call("step", delta)
		elif not _step_hydrant(delta):
			_simulate(delta)
		_track_fall(delta)
	_apply_presentation()
	# Seated in a drivable vehicle the body turns with the seat this tick
	# (player/seated.gd sets body_yaw after the seat placed the Visual): put the
	# Visual back where the seat has it, or it's drawn turned by that much for a
	# tick (fx-chefty: a 90-degree flick of the view as you sat down).
	if _on_seat and is_multiplayer_authority() and in_vehicle():
		$Visual.global_transform = _seat_visual


## Where _seat_on_ride drew the Visual this tick.
var _seat_visual := Transform3D()


## Follow a seat until the ride arrives. Movement stays off; looking still works.
## While riding, every peer puts this player on their seat each physics tick,
## right after the vehicle moves (process_physics_priority in _enter_tree), and
## physics interpolation smooths both the same way. Going through the network
## smoother's delay instead made riders slide back and forth against the vehicle.
func _seat_on_ride() -> void:
	var was_ride := _seat_ride
	var was_slot := _seat_slot
	var seat := _current_seat()
	var was_on_seat := _on_seat
	_on_seat = seat != Transform3D()
	if was_on_seat != _on_seat:
		if not is_multiplayer_authority():
			_pin_visual(_on_seat)
		reset_physics_interpolation()
	if is_multiplayer_authority() and (was_ride != _seat_ride or was_slot != _seat_slot) and ((was_ride != null and was_ride.is_in_group("vehicles")) or (_seat_ride != null and _seat_ride.is_in_group("vehicles"))):
		_Seated.on_seat_changed(self, _on_seat, _seat_slot)
	if not _on_seat:
		return
	if is_multiplayer_authority():
		global_position = seat.origin
		velocity = Vector3.ZERO
	# A drivable vehicle's riders face the way it does on every peer (their own
	# peer turns just the head); a legacy ride's keep their own facing.
	var facing := seat.basis.orthonormalized() if _seat_ride != null and _seat_ride.is_in_group("vehicles") else global_basis
	$Visual.global_transform = Transform3D(facing, seat.origin)
	_seat_visual = $Visual.global_transform


## For net/components/net_smoother.gd: while true, the smoother leaves the visual alone.
func is_riding_visual() -> bool:
	return _on_seat or is_staged()


func _current_seat() -> Transform3D:
	var peer_id := name.to_int()
	for ride: Node in get_tree().get_nodes_in_group("rides"):
		var index := int(ride.call("seat_of", peer_id))
		if index >= 0:
			_seat_ride = ride
			_seat_slot = index
			return ride.call("seat_transform", index)
	_seat_ride = null
	_seat_slot = -1
	return Transform3D()


## In a drivable vehicle's seat (Chefty in the connected town), on every peer.
func in_vehicle() -> bool:
	return _on_seat and _Seated.vehicle_of(self) != null


## In a seat in the legacy Chefty's bed (net/components/ride.gd: the ride, or its
## honk-and-wait), not hopping out over the tailgate. The bed's eye lift applies
## here too: from a plain standing eye the cab roof filled the lower half of the
## view while the crew climbed in (review of p1-depart, rec_dep3_1p frame 150).
func _in_legacy_bed() -> bool:
	if _seat_ride == null or not is_instance_valid(_seat_ride) or _seat_ride.is_in_group("vehicles") or not _seat_ride.is_in_group("chefty"):
		return false
	return _seat_slot >= 0 and _seat_slot < int(_seat_ride.call("seat_count"))


## The ride this player's seat is on (every peer knows), or null.
func seat_ride() -> Node:
	return _seat_ride


## Which seat on seat_ride(), or -1.
func seat_slot() -> int:
	return _seat_slot


## For player/first_person_arms.gd: the driver's hands on the wheel, [right,
## left] in world space, or [] when not driving.
func wheel_grips() -> Array:
	return _Seated.wheel_grips(self)


func set_riding(ride: Node3D, seat_index: int) -> void:
	_ride = ride
	_seat_index = seat_index
	_ride_seat_yaw = NAN
	velocity = Vector3.ZERO


func clear_riding() -> void:
	_ride = null
	_seat_index = -1


func _on_zone_changed(peer_id: int, zone: Net.Zone) -> void:
	if peer_id != name.to_int():
		return
	if zone != Net.Zone.TRANSIT:
		clear_riding()
		return
	var director := get_tree().get_first_node_in_group("run_director")
	if director != null and bool(director.call("is_captured", peer_id)):
		say("vo_yelp")


# ---- R2:1 the stage (docs/DECISIONS.md, R2): one stage camera, staged bodies,
# control locks. Other chunks call these; nothing here decides gameplay.
const _StageCam = preload("res://player/stage_cam.gd")
const _StageBody = preload("res://player/stage_body.gd")
## Why this player can't move right now (set_control_lock): reason -> true.
var _locks: Dictionary = {}
## The yaw a lock with a look limit started from.
var _lock_yaw: float = 0.0
## The pose a stage gave the body (set_body_pose).
var _stage_pose: StringName = &"stand"


## StageBody on every peer; StageCam under CameraRig on the owner only.
func _build_stage() -> void:
	if get_node_or_null("StageBody") == null:
		var stage_body := _StageBody.new()
		stage_body.name = "StageBody"
		stage_body.player = self
		add_child(stage_body)
	if is_multiplayer_authority() and %CameraRig.get_node_or_null("StageCam") == null:
		var cam := _StageCam.new()
		cam.name = "StageCam"
		cam.player = self
		%CameraRig.add_child(cam)


## Push a stage shot (player/stage_cam.gd has the shot keys). Owner only; a no-op elsewhere.
func stage_push(id: StringName, shot: Dictionary) -> void:
	var cam := stage_cam()
	if cam != null:
		cam.call("push", id, shot)


func stage_pop(id: StringName, blend_out := -1.0) -> void:
	var cam := stage_cam()
	if cam != null:
		cam.call("pop", id, blend_out)


## The shot on top, or &"" when your own camera has the view.
func stage_top() -> StringName:
	var cam := stage_cam()
	return StringName(cam.call("top")) if cam != null else &""


## The stage camera (owner only), else null.
func stage_cam() -> Camera3D:
	return %CameraRig.get_node_or_null("StageCam") as Camera3D


## Every peer, from the caller's reliable RPC: the body follows anchor * offset
## (player/stage_body.gd), blending in over `blend` seconds, in `pose`. clear_of
## (R2c): someone the blend goes round, never through (the escort's link).
func set_staged(anchor: Node3D, offset: Transform3D, blend: float, pose: StringName, clear_of: Node3D = null) -> void:
	# A stage takes the body from wherever a hop off a seat had it.
	_step_t = -1.0
	var stage_body := get_node_or_null("StageBody")
	if stage_body != null:
		stage_body.call("set_staged", anchor, offset, blend, pose, clear_of)


func clear_staged() -> void:
	var stage_body := get_node_or_null("StageBody")
	if stage_body != null:
		stage_body.call("clear_staged")


func is_staged() -> bool:
	var stage_body := get_node_or_null("StageBody")
	return stage_body != null and bool(stage_body.call("is_staged"))


## Lock this player's controls for a reason (Constants.STAGE_LOCK_ALLOW lists
## what each still lets through: a wriggle, a knock on the glass, looking).
## Locks stack; controls come back when the last one goes.
func set_control_lock(reason: StringName, on: bool) -> void:
	if on:
		if _locks.is_empty():
			_lock_yaw = body_yaw
		_locks[reason] = true
	else:
		_locks.erase(reason)


func is_control_locked() -> bool:
	return not _locks.is_empty()


func control_locks() -> Array:
	return _locks.keys()


## Whether every lock on now lets `what` through ("jump", "primary", "look").
func control_allows(what: String) -> bool:
	for reason: StringName in _locks:
		var allow: Dictionary = Constants.STAGE_LOCK_ALLOW.get(reason, {})
		if not bool(allow.get(what, false)):
			return false
	return true


## How far a lock lets you turn from where it started, in radians (INF = free).
func _lock_look_limit() -> float:
	var limit := INF
	for reason: StringName in _locks:
		var allow: Dictionary = Constants.STAGE_LOCK_ALLOW.get(reason, {})
		if allow.has("look_deg"):
			limit = minf(limit, deg_to_rad(float(allow["look_deg"])))
	return limit


## The body's pose for a stage: &"stand", &"escorted", &"sit_buckled", &"walk_behind".
func set_body_pose(pose: StringName) -> void:
	_stage_pose = pose
	var body := get_node_or_null("Visual/CartoonBody")
	if body != null:
		body.set("mood", "worried" if pose == &"escorted" else "neutral")


## Owner, each physics tick: while staged or locked, nothing moves the body but
## the stage (and gravity, when merely locked). Returns true to skip the rest.
func _stage_hold(delta: float) -> bool:
	var staged := is_staged()
	if not staged and _locks.is_empty():
		return false
	for action: StringName in _STAGE_HELD_ACTIONS:
		if Input.is_action_pressed(action) and not control_allows(String(action)):
			Input.action_release(action)
	if not staged:
		if control_allows("look"):
			_apply_look()
			var limit := _lock_look_limit()
			if limit < INF:
				body_yaw = _lock_yaw + clampf(wrapf(body_yaw - _lock_yaw, -PI, PI), -limit, limit)
		else:
			_look = Vector2.ZERO
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * delta
		move_and_slide()
		anim_state = AnimState.IDLE if is_on_floor() else AnimState.AIR
	else:
		_look = Vector2.ZERO
		velocity = Vector3.ZERO
		anim_state = AnimState.IDLE
	_apply_presentation()
	return true


## The actions a control lock holds back unless the lock allows them.
const _STAGE_HELD_ACTIONS: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right", &"jump", &"sprint", &"crouch", &"interact", &"primary", &"secondary", &"drop", &"take", &"honk", &"board", &"slot_1", &"slot_2", &"slot_3", &"slot_4", &"slot_5", &"slot_next", &"slot_prev"]


## Before anyone else's input handling: a stage shot takes the mouse look, and a
## control lock swallows what it holds back.
func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	var cam := stage_cam()
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if cam != null and StringName(cam.call("top")) != &"":
			cam.call("add_look", (event as InputEventMouseMotion).relative)
			get_viewport().set_input_as_handled()
		elif not _locks.is_empty() and not control_allows("look"):
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact") and not event.is_echo() and _press_e(event):
		get_viewport().set_input_as_handled()
		return
	if _locks.is_empty():
		return
	# A window or the pause menu has the mouse: its buttons get every click and
	# key (Node._input runs before the GUI). _stage_hold still releases anything
	# held, so nothing leaks into the world.
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var ui := get_tree().get_first_node_in_group("game_ui")
	if ui != null and ui.has_method("any_window_open") and bool(ui.call("any_window_open")):
		return
	for action: StringName in _STAGE_HELD_ACTIONS:
		if event.is_action(action) and not control_allows(String(action)):
			Input.action_release(action)
			get_viewport().set_input_as_handled()
			return


## Lying on a cot (net/day/day_clock.gd decides who sleeps): still, eyes low,
## lying on the n-th cot. Any movement key gets you up. Returns true while asleep.
var _was_sleeping: bool = false


## On a cot right now, by the host's day clock. Every peer can ask.
func is_sleeping() -> bool:
	var clock := get_tree().get_first_node_in_group("day_clock")
	return clock != null and bool(clock.call("is_sleeping", name.to_int()))


func _step_sleep(delta: float) -> bool:
	var clock := get_tree().get_first_node_in_group("day_clock")
	var asleep := clock != null and bool(clock.call("is_sleeping", name.to_int()))
	if not asleep:
		if _was_sleeping:
			_was_sleeping = false
			# Up off the canvas: a step down off the cot's foot while the body sits
			# up (cartoon_body.gd), never standing on the canvas or dropping through it.
			if _sleep_cot != null and is_instance_valid(_sleep_cot):
				var side := _sleep_cot.global_basis.x
				side.y = 0.0
				_sleep_from = Transform3D(Basis(Vector3.UP, body_yaw), global_position)
				_wake_to = Vector3(global_position.x, _sleep_cot.global_position.y, global_position.z) + side.normalized() * Constants.SLEEP_GET_UP_SIDE
				_sleep_climb = 0.0
			_sleep_cot = null
		if _wake_to.is_finite():
			velocity = Vector3.ZERO
			_sleep_climb = minf(1.0, _sleep_climb + delta / (Constants.SLEEP_CLIMB_SECONDS * Constants.SLEEP_GET_UP_SHARE))
			var up := smoothstep(0.0, 1.0, _sleep_climb)
			global_position = _sleep_from.origin.lerp(_wake_to, up)
			if _sleep_climb >= 1.0:
				_wake_to = Vector3.INF
			return true
		return false
	var cot := _my_cot(clock)
	if not _was_sleeping:
		_was_sleeping = true
		_wake_to = Vector3.INF
		_stow_hands()
		_sleep_from = Transform3D(Basis(Vector3.UP, body_yaw), global_position)
		_sleep_climb = 0.0
		_sleep_look = 0.0
	_sleep_cot = cot
	velocity = Vector3.ZERO
	if cot != null:
		# Climbed onto the cot over a moment (a little hop up onto the canvas),
		# turned so the head goes down on the pillow: everyone sees it, nobody
		# sees a teleport (crew-06).
		var spot := sleep_spot(cot)
		var spot_yaw := spot.basis.get_euler().y
		_sleep_climb = minf(1.0, _sleep_climb + delta / Constants.SLEEP_CLIMB_SECONDS)
		var share := smoothstep(0.0, 1.0, _sleep_climb)
		if _sleep_climb < 1.0:
			global_position = _sleep_from.origin.lerp(spot.origin, share) + Vector3.UP * sin(PI * share) * Constants.SLEEP_CLIMB_HOP
			body_yaw = lerp_angle(_sleep_from.basis.get_euler().y, spot_yaw, share)
		else:
			global_position = spot.origin
			# Lying there the mouse turns your head on the pillow, never the body:
			# the body pivots at the heels, so turning it swung the whole sleeper
			# off the cot for everyone (review of crew-06). The turn is this
			# peer's own (_apply_presentation); the body stays on the cot's line.
			_sleep_look = clampf(_sleep_look + angle_difference(spot_yaw, body_yaw), -Constants.SLEEP_YAW_CLAMP, Constants.SLEEP_YAW_CLAMP)
			body_yaw = spot_yaw
	for action: StringName in [&"move_forward", &"move_back", &"move_left", &"move_right", &"jump"]:
		if Input.is_action_just_pressed(action) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			clock.call("request_sleep", false)
	return true


var _sleep_from := Transform3D()
var _sleep_climb: float = 0.0
## Owner only: how far (radians, + left) the sleeper's head is turned on the
## pillow. Not replicated: to everyone else a sleeper's face looks straight up.
var _sleep_look: float = 0.0
## Whether _apply_presentation left the head turned (so it puts it back once).
var _sleep_head_turned: bool = false
var _sleep_cot: Node3D
## Getting up: where the step off the cot ends (INF when not getting up).
var _wake_to := Vector3.INF


func _my_cot(clock: Node) -> Node3D:
	if clock == null:
		return null
	var spot := int(clock.call("cot_of", name.to_int()))
	for cot: Node in get_tree().get_nodes_in_group("cots"):
		if int(cot.get("index")) == spot:
			return cot as Node3D
	return null


## Where a sleeper lies on a cot, the same on every peer: the heels toward the
## cot's foot (+x, the rolled blanket), turned so lying back puts the head on
## the pillow (-x). The origin is the heels on the canvas.
static func sleep_spot(cot: Node3D) -> Transform3D:
	var bed: Transform3D = cot.call("bed_transform")
	var along := bed.basis.x
	along.y = 0.0
	along = along.normalized()
	# Lying back tips the head toward the body's +Z: point it at the pillow.
	var yaw := atan2(-along.x, -along.z)
	return Transform3D(Basis(Vector3.UP, yaw), bed.origin + along * Constants.SLEEP_FOOT_OFFSET)


## Every peer: lying on the cot now (asleep, and close enough to it to have
## climbed on), so the body lies down there and not where it stood.
func is_lying_on_cot() -> bool:
	if not is_sleeping():
		return false
	var cot := _my_cot(get_tree().get_first_node_in_group("day_clock"))
	return cot != null and global_position.distance_to(sleep_spot(cot).origin) <= Constants.SLEEP_ON_COT_NEAR


## Called on every peer by the host's hide spot (net/components/hide_spot.gd):
## in spot by side from server time at, or out (spot null) toward exit_to, lifted
## out by a NICE BOY if pulled. Nothing here teleports or hides $Visual: the body
## dives, climbs and is lifted along a curve (player/hide_view.gd), and only the
## drawn body stops being drawn (set_body_drawn), so the camera stays live.
func set_hidden_in(spot: Node3D, side: int = -1, at: float = -1.0, exit_to: Vector3 = Vector3.INF, pulled: bool = false) -> void:
	var view := _hide_view()
	_hidden_spot = spot
	if spot != null:
		%Collision.disabled = true
		if is_multiplayer_authority():
			_stow_hands()
			velocity = Vector3.ZERO
		view.call("on_hidden", spot, side if side >= 0 else int(spot.call("side_of", name.to_int())), at if at >= 0.0 else Net.server_time())
		return
	if is_multiplayer_authority() and not exit_to.is_finite() and not bool(view.call("is_moving")):
		%Collision.disabled = false
	view.call("on_unhidden", exit_to, pulled)
	if not is_multiplayer_authority():
		%Collision.disabled = false


func is_hidden() -> bool:
	return _hidden_spot != null or in_pile


## The hiding spot this player is in (every peer), or null.
func hidden_spot() -> Node3D:
	return _hidden_spot


## Owner, from player/hide_view.gd: a climb-out, lift or bonk has landed.
func on_hide_move_done() -> void:
	if _hidden_spot == null:
		%Collision.disabled = false
	velocity = Vector3.ZERO
	_fall_peak = global_position.y


## Owner, from the hide spot: the host said no. The dive bonks off.
func on_hide_refused(spot: Node3D, _reason: String) -> void:
	_hide_view().call("on_refused", spot)


func _hide_moving() -> bool:
	var view := get_node_or_null("HideView")
	return view != null and bool(view.call("is_moving"))


## The hiding presentation (player/hide_view.gd), made on first use.
func _hide_view() -> Node:
	var view := get_node_or_null("HideView")
	if view == null:
		view = load("res://player/hide_view.gd").new()
		view.name = "HideView"
		view.set("player", self)
		add_child(view)
	return view


## Whether this player's body is drawn: not while hidden in a spot or a pile
## (every peer). The camera, Visual and Head stay in the tree either way.
func is_body_drawn() -> bool:
	return _body_drawn


## Draw or stop drawing the body, head, nameplate and first-person arms (hands
## are stowed on the way in, so nothing is held). Never $Visual itself: the
## first-person camera lives under it.
func set_body_drawn(on: bool) -> void:
	if on == _body_drawn:
		return
	_body_drawn = on
	for path: String in ["Visual/CartoonBody", "Visual/Head/CartoonHead", "Visual/Head/Arms", "Visual/Head/HatLeaf"]:
		var part := get_node_or_null(path) as Node3D
		if part != null:
			part.visible = on
	%Nameplate.visible = on and not is_multiplayer_authority()


var _body_drawn: bool = true


## Hanging on to a hydrant-fed hose with the water on: the spray shoves you back
## and up and whips you side to side, slowly enough to stay believable. Let go
## (release left click) to drop. Returns true while it's in charge.
var _yelp_wait: float = 0.0


func _step_hydrant(delta: float) -> bool:
	var held := _held_prop()
	if held == null or str(held.get("hose_source")) != "hydrant" or not Input.is_action_pressed("primary") or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return false
	var head := get_node_or_null("Visual/Head") as Node3D
	var look := -head.global_basis.z if head != null else -global_basis.z
	var aim: Vector3 = load("res://equipment/rake.gd").hose_aim(self, look)
	var ground := 0.0
	var lift := Constants.HYDRANT_LIFT if global_position.y - ground < 2.4 else 0.0
	# Shoved back the way the water goes (along the ground), and hauled up off your feet.
	var back := Vector3(-aim.x, 0.0, -aim.z)
	velocity += (back.normalized() * Constants.HYDRANT_PUSH + Vector3.UP * lift) * delta
	velocity.y -= _gravity * delta
	var flat := Vector2(velocity.x, velocity.z).limit_length(Constants.HYDRANT_MAX_SPEED)
	velocity = Vector3(flat.x, clampf(velocity.y, -8.0, Constants.HYDRANT_MAX_SPEED * 0.7), flat.y)
	move_and_slide()
	anim_state = AnimState.AIR
	var body := get_node_or_null("Visual/CartoonBody")
	if body != null and not bool(body.call("is_gesturing")):
		body.call("gesture", "flail")
	_yelp_wait -= delta
	if _yelp_wait <= 0.0:
		_yelp_wait = randf_range(1.2, 2.4)
		say_to_all("vo_yelp" if randf() < 0.6 else "vo_ah")
	_stay_on_the_pad()
	return true


## E by a water source with the hose: hook up (or unhook); with the pressure
## washer: fill it up.
func _water_hookup() -> bool:
	var held := _held_prop()
	if held == null:
		return false
	var kind := str(held.get("kind"))
	if kind == "paint_roller":
		if _nearest_bucket() == null:
			return false
		held.call("request_hookup")
		return true
	if kind != "hose" and kind != "pressure_washer":
		return false
	if _WaterSources.nearest(get_tree(), global_position, Constants.WATER_REACH) == null:
		return false
	held.call("request_hookup")
	return true


## E with the gas can in hand by a gas tool that isn't full: fill it up
## (net_prop.gd request_refuel; the host pours).
func _refuel() -> bool:
	var held := _held_prop()
	if held == null or str(held.get("kind")) != "gas_can" or held.call("refuel_target") == null:
		return false
	held.call("request_refuel")
	return true


## Local: a notice over your head for a few seconds ("Out of bags."), shown by
## the interaction prompt ahead of everything else.
func flash_hint(text: String) -> void:
	_notice_text = text
	_notice_until = Time.get_ticks_msec() + int(Constants.SUPPLY_NOTICE_SECONDS * 1000.0)


## What's keeping the tool in hand from working, as a plain hint, when the world
## can't show it: a rake with the crew out of bags. {} when nothing. (x1:text: an
## empty gas tool sputters and its gauge reads empty, and an empty can's gauge
## does too, so neither says anything.)
func _supply_hint() -> Dictionary:
	var held := _held_prop() as Node3D
	if held == null:
		return {}
	var held_kind := str(held.get("kind"))
	var above := held.global_position + Vector3(0.0, 1.0, 0.0)
	if held_kind == "rake" and Net.player_zone(name.to_int()) == Net.Zone.LOT:
		var field := get_tree().get_first_node_in_group("leaf_field")
		if field != null and str(field.call("bag_type")) == "":
			return {"text": _Strings.SHOP_UI["hud_out_of_bags"], "at": above, "plain": true}
	return {}


func _nearest_bucket() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("paint_buckets"):
		var bucket := node as Node3D
		if bucket != null and bucket.global_position.distance_to(global_position) < Constants.WATER_REACH + 0.5:
			return bucket
	return null


## Up at the top of a set-up ladder, where gutters can be reached. Worked out
## from where this player is, so the host can tell for anyone.
func is_climbing() -> bool:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) != "ladder" or not bool(node.call("is_set_up")):
			continue
		var top: Vector3 = node.get("ladder_top")
		if Vector2(global_position.x - top.x, global_position.z - top.z).length() < 1.7 and global_position.y > top.y - 2.6:
			return true
	return false


## F at a set-up ladder's foot takes it down (into your hands).
func _take_ladder() -> bool:
	if not _hands_can_pick_up():
		return false
	var ladder := _nearest_ladder()
	if ladder == null:
		return false
	ladder.call("request_grab")
	return true


## E at a set-up ladder's foot climbs it; E up on one climbs down.
func _toggle_climb() -> bool:
	if _ladder != null:
		_climb_target = 0.0
		return true
	# On the roof by a ladder's top: climb back down it.
	var from_roof := _nearest_ladder_top()
	if from_roof != null:
		_ladder = from_roof
		_climb = 1.0
		_climb_target = 0.0
		return true
	var ladder := _nearest_ladder()
	if ladder == null:
		return false
	_ladder = ladder
	_climb = 0.0
	_climb_target = 1.0
	return true


func _nearest_ladder_top() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("props"):
		var prop := node as Node3D
		if prop == null or str(prop.get("kind")) != "ladder" or not bool(prop.call("is_set_up")):
			continue
		var top: Vector3 = prop.get("ladder_top")
		if Vector2(global_position.x - top.x, global_position.z - top.z).length() < 1.8 and global_position.y > top.y - 1.0:
			return prop
	return null


## Up on a roof or a ladder: high enough to work the gutters and the roof.
func is_up_high() -> bool:
	return _ladder != null or global_position.y > 1.8


## A mower got your foot (net/components/net_prop.gd tells every peer). Everyone
## hears it and, if it came off, sees it fly; your own peer starts the limp or
## the hop. It heals when the job is paid.
func hurt_foot(level: int, heading: Vector3) -> void:
	say("vo_yelp")
	var body := get_node_or_null("Visual/CartoonBody")
	if body != null:
		body.call("gesture", "flail")
		if level >= 2 and int(body.get("foot_hurt")) < 2:
			var lot := get_tree().get_first_node_in_group("job_lot")
			load("res://props/lost_foot.gd").launch(lot if lot != null else get_parent(), global_position, heading, Color(0.18, 0.14, 0.12), body.get("skin"))
	if not is_multiplayer_authority():
		return
	foot_hurt = maxi(foot_hurt, level)
	if foot_hurt == 1:
		limping = true
		_limp_left = Constants.LIMP_SECONDS
	if _held_prop() != null:
		_release_held(false)
	_stun_left = 0.6
	if not Campaign.payout_ready.is_connected(_heal_feet):
		Campaign.payout_ready.connect(_heal_feet)


func _heal_feet(_results: Array[Dictionary]) -> void:
	foot_hurt = 0


## Falls: a hard landing bounces you; the next touchdown knocks you out, and you
## limp for a while after. Climbing, riding, and teleports don't count as falls.
func _track_fall(delta: float) -> void:
	if limping:
		_limp_left -= delta
		if _limp_left <= 0.0:
			limping = false
	if _ladder != null or _on_seat or _hidden_spot != null or _hide_moving() or is_stepping_down():
		_airborne = false
		_fall_peak = global_position.y
		return
	if not is_on_floor():
		if not _airborne:
			_airborne = true
			_fall_peak = global_position.y
		_fall_peak = maxf(_fall_peak, global_position.y)
		return
	if not _airborne:
		return
	_airborne = false
	if _bounced:
		_bounced = false
		_stun_left = Constants.FALL_KNOCKOUT_SECONDS
		_knocked = true
		limping = true
		_limp_left = Constants.LIMP_SECONDS
		if _held_prop() != null:
			_release_held(false)
		say_to_all("vo_oof")
		return
	if _fall_peak - global_position.y >= Constants.FALL_HURT_HEIGHT:
		_bounced = true
		velocity.y = Constants.FALL_BOUNCE_SPEED
		velocity.x *= 0.5
		velocity.z *= 0.5
		say_to_all("vo_yelp")


func _nearest_ladder() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("props"):
		var prop := node as Node3D
		if prop != null and str(prop.get("kind")) == "ladder" and bool(prop.call("is_set_up")) and prop.global_position.distance_to(global_position) < 1.8:
			return prop
	return null


## On the ladder: up or down its rungs, facing the wall, until back at the foot.
## If someone takes the ladder away, down you go.
func _step_climb(delta: float) -> void:
	# Someone took the ladder away: you're just up in the air now.
	if not is_instance_valid(_ladder) or not bool(_ladder.call("is_set_up")):
		_ladder = null
		say_to_all("vo_yelp")
		return
	var foot := _ladder.global_position
	var top: Vector3 = _ladder.get("ladder_top")
	var up := top - foot
	var out := Vector3(-up.x, 0.0, -up.z).normalized()
	# Better ladders climb faster; the Mk III twice as fast (core/tool_tiers.gd).
	_climb = move_toward(_climb, _climb_target, delta / Constants.LADDER_CLIMB_SECONDS * _ToolTiers.climb_speed(_ToolTiers.tier_of(_ladder)))
	# At the top your feet are a rung below the gutter, so it's at chest height.
	var reach := maxf(0.0, (up.length() - 1.45) / up.length())
	global_position = foot + up * (reach * _climb) + out * 0.35
	velocity = Vector3.ZERO
	body_yaw = atan2(out.x, out.z)
	anim_state = AnimState.IDLE
	# At the top, walk forward to step off onto the roof.
	if _climb >= 0.99 and _climb_target >= 1.0 and Input.is_action_pressed("move_forward"):
		_ladder = null
		global_position = top - out * 1.1 + Vector3.UP * 0.5
		_fall_peak = global_position.y
		reset_physics_interpolation()
		return
	if _climb <= 0.0 and _climb_target <= 0.0:
		_ladder = null
		global_position = foot + out * 0.8
		reset_physics_interpolation()


## Bare-hands work: E by litter picks it up; E by a weed tugs at it.
## Returns true when there was something here to do.
func _hand_task() -> bool:
	var spot := _nearest_hand_task()
	if spot.is_empty():
		return false
	var tasks := get_tree().get_first_node_in_group("job_tasks")
	tasks.call("request_work", spot["task"], spot["at"], -global_basis.z)
	var body := get_node_or_null("Visual/CartoonBody")
	if body != null and not bool(body.call("is_gesturing")):
		body.call("gesture", "scratch" if spot["task"] == "pull_weeds" else "shuffle")
	return true


## The nearest litter or weed within reach, with empty hands: {task, at}, or {}.
func _nearest_hand_task() -> Dictionary:
	# A pocket tool in hand doesn't stop you; something big does.
	if not _hands_can_pick_up():
		return {}
	var tasks := get_tree().get_first_node_in_group("job_tasks")
	if tasks == null:
		return {}
	for task: String in ["pick_litter", "pull_weeds", "skim_pool"]:
		var index := int(tasks.call("nearest_spot", task, global_position, float(Constants.TASK_REACH[task])))
		if index >= 0:
			return {"task": task, "index": index, "at": (tasks.call("spot", index) as Dictionary)["at"]}
	return {}


## E at Chefty's tailgate with junk in the bed (and nothing to pick up closer):
## the junk hops out over it (net/components/junk_bed.gd, gap-specs critic C22).
func _unload_junk() -> bool:
	var bed := _junk_tailgate()
	if bed == null:
		return false
	bed.call("request_unload")
	return true


## Chefty's junk bed when you stand at its tailgate, hands free of anything
## that goes in the bed, and it has junk to unload; else null.
func _junk_tailgate() -> Node:
	var held := _held_prop()
	if held != null and ["junk", "leaf_bag", "wheelbarrow"].has(str(held.get("kind"))):
		return null
	var chefty := get_tree().get_first_node_in_group("chefty")
	var bed := chefty.get_node_or_null("Body/JunkBed") if chefty != null else null
	if bed == null or not bool(bed.call("can_unload_from", self)):
		return null
	return bed


## E by Chefty with a bag (or a piece of junk for Rusty's) tosses it in; with a
## loaded wheelbarrow, dumps it.
func _load_truck() -> bool:
	var held := _held_prop()
	if held == null or not bool(held.call("near_truck")):
		return false
	var held_kind := str(held.get("kind"))
	if held_kind != "leaf_bag" and held_kind != "junk" and not (held_kind == "wheelbarrow" and int(held.get("stored_bags")) > 0):
		return false
	held.call("request_load_truck")
	return true


## E inside a hiding spot bursts out toward where you look. E next to one with
## room dives in at once (player/hide_view.gd) and asks the host. Mid-dive or
## mid-climb, E does nothing else.
func _toggle_hiding() -> bool:
	var view := _hide_view()
	if bool(view.call("is_moving")) or bool(view.call("is_waiting")):
		return true
	if _hidden_spot != null:
		view.call("request_exit")
		return true
	if in_pile:
		if not bool(view.call("is_found")):
			set_pile(false)
		return true
	var closest := _nearest_free_spot()
	if closest != null:
		view.call("predict_enter", closest)
		closest.call("request_enter")
		return true
	# No spot, but a big enough pile underfoot: dive in.
	if _on_pile():
		view.call("predict_pile_dive")
		get_tree().get_first_node_in_group("leaf_field").call("request_pile_hide")
		return true
	return false


## True when the leaves under this player are thick enough to dive into.
func _on_pile() -> bool:
	var field := get_tree().get_first_node_in_group("leaf_field")
	return field != null and is_on_floor() and bool(field.call("is_pile_at", global_position))


# ---------------------------------------------------------------- brawling

## Hold left click with empty hands to wind up a punch: the arm goes round and
## round, and the longer it winds the harder it lands, until you wind so long
## you spin out and fall over. Release to swing at whoever's in front.
func _step_punch(delta: float) -> void:
	_punch_cool = maxf(0.0, _punch_cool - delta)
	_swing_left = maxf(0.0, _swing_left - delta)
	var can := not on_board and _held_prop() == null and carrying == 0 and carried_by == 0 and _stun_left <= 0.0 and not in_pile and _hidden_spot == null and _ladder == null and _ride == null and not in_vehicle() and not is_up_high() and not is_sleeping()
	var held_down := Input.is_action_pressed("primary") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if dev_primary >= 0:
		held_down = dev_primary == 1
	# What this click is, from the moment it went down (crew-04): a punch when
	# someone was in front or there's no yard to rake by hand, else a hand stroke.
	# A stroke that runs out of leaves just stops; it never turns into a wind-up.
	if not held_down:
		_press_kind = &""
	elif _press_kind == &"":
		_press_kind = &"punch" if can and _punch_opens_here() else &"hands"
	var pressing := can and _punch_cool <= 0.0 and held_down and _press_kind != &"spent"
	# Empty hands on leaves rake by hand (equipment/rake.gd). A wind-up only
	# starts there when someone is in front to hit; once started it keeps going.
	if pressing and _punch_wind < 0.0 and not wants_punch():
		pressing = false
	if pressing:
		if _punch_wind < 0.0:
			_punch_wind = 0.0
		_punch_wind += delta
		winding = true
		if _punch_wind >= Constants.PUNCH_DIZZY_SECONDS:
			_spin_out()
		return
	if _punch_wind < 0.0:
		winding = false
		return
	var wound := _punch_wind
	_punch_wind = -1.0
	winding = false
	_punch_cool = 0.5
	var tier := "heavy"
	if wound < float(Constants.PUNCH_WIND_TIERS[0]):
		tier = "light"
	elif wound < float(Constants.PUNCH_WIND_TIERS[1]):
		tier = "medium"
	get_tree().get_first_node_in_group("brawl").call("request_punch", tier)
	say_to_all("vo_heave" if tier == "heavy" else "vo_hup")


## Whether left click with empty hands means a punch rather than hand raking
## (crew-04): a click that went down as a punch stays one, and otherwise only
## someone in reach in front turns it into one. On a yard, bare ground with no
## leaves is still hand raking (a scrape that moves nothing), never a wind-up.
func wants_punch() -> bool:
	if _punch_wind >= 0.0 or _press_kind == &"punch" or _press_kind == &"spent":
		return true
	return _person_ahead()


## Whether a click going down now is a punch: someone to hit, or nowhere to
## rake by hand (off a job yard).
func _punch_opens_here() -> bool:
	if _person_ahead():
		return true
	return get_tree().get_first_node_in_group("leaf_field") == null or Net.player_zone(name.to_int()) != Net.Zone.LOT


func _person_ahead() -> bool:
	var brawl := get_tree().get_first_node_in_group("brawl")
	return brawl != null and brawl.call("person_in_front", self, Constants.PUNCH_REACH, name.to_int()) != null


## Wound up so long the world spun: down you go for a moment. The click that
## did it is spent: holding on doesn't wind up again (crew-04).
func _spin_out() -> void:
	_punch_wind = -1.0
	_press_kind = &"spent"
	winding = false
	_punch_cool = 1.0
	_stun_left = Constants.FAINT_SECONDS * 0.8
	_knocked = true
	velocity = Vector3.ZERO
	var body := get_node_or_null("Visual/CartoonBody")
	if body != null:
		body.call("dizzy", _stun_left)
	say_to_all("vo_oof")


## Left click with something heavy in hand swings it at whoever's in front.
func _whack() -> bool:
	var held := _held_prop()
	if held == null or Constants.TOOL_PRICES.has(str(held.get("kind"))) or str(held.get("kind")) == "rake":
		return false
	if _stun_left > 0.0 or carried_by != 0 or is_up_high() or _ladder != null:
		return false
	get_tree().get_first_node_in_group("brawl").call("request_whack")
	return true


## E with empty hands by another player picks them up; E while carrying sets them down.
func _grab_player() -> bool:
	var brawl := get_tree().get_first_node_in_group("brawl")
	if brawl == null:
		return false
	if carrying != 0:
		brawl.call("request_release_player", "drop")
		return true
	var target := _grabbable_player()
	if target == null:
		return false
	brawl.call("request_grab_player", target.name.to_int())
	return true


## The other player you're looking right at, up close, with empty hands, or
## null (p1-hands: a friend walking beside you, or standing at Chefty's
## tailgate with you, is not an offer to pick them up).
func _grabbable_player() -> Node3D:
	if _held_prop() != null or carried_by != 0 or carrying != 0 or _stun_left > 0.0 or in_pile or _hidden_spot != null or is_sleeping():
		return null
	var best: Node3D = null
	var best_distance := Constants.E_GRAB_REACH
	for node: Node in get_tree().get_nodes_in_group("players"):
		var other := node as Node3D
		# A dev observer (net/dev/remote_play.gd) is invisible and not in the game.
		if other == null or other == self or Net.is_watcher(other.name.to_int()) or not other.has_method("can_be_grabbed") or not bool(other.call("can_be_grabbed")):
			continue
		var offset := other.global_position - global_position
		var flat := Vector3(offset.x, 0.0, offset.z)
		if absf(offset.y) > 1.5 or flat.length() > best_distance:
			continue
		# Looking at them: the line of sight passes within reach of their body
		# somewhere between the knees and the top of the head.
		var miss := INF
		for height: float in Constants.E_GRAB_LOOK_HEIGHTS:
			miss = minf(miss, _look_miss(other.global_position + Vector3(0.0, height, 0.0), Constants.E_GRAB_REACH + Constants.E_LOOK_REACH_SLACK))
		if miss > Constants.E_GRAB_LOOK_MISS:
			continue
		best = other
		best_distance = flat.length()
	return best


## R2c: whether a friend can pick this player up now. Not while hidden, asleep,
## carried, carrying or flying; not while a NICE BOY has them (caught, cited,
## walked to the van) or a moment stages them; not seated (the Courtesy Shuttle,
## Chefty); not when their body isn't drawn (a watcher's ghost). The prompt
## (interaction_hint) and the host (net/components/brawl.gd) ask the same
## question of the same replicated state, so no "[E] Grab" shows for a grab that
## does nothing.
func can_be_grabbed() -> bool:
	if is_hidden() or is_sleeping() or carried_by != 0 or carrying != 0 or thrown:
		return false
	if is_staged() or in_vehicle() or _on_seat:
		return false
	var visual := get_node_or_null("Visual") as Node3D
	if visual != null and not visual.visible:
		return false
	var peer := name.to_int()
	var director := get_tree().get_first_node_in_group("run_director") if is_inside_tree() else null
	if director != null and director.has_method("is_captured") and bool(director.call("is_captured", peer)):
		return false
	var shuttle := get_tree().get_first_node_in_group("nice_shuttle") if is_inside_tree() else null
	if shuttle != null and shuttle.has_method("seat_info") and not (shuttle.call("seat_info", peer) as Dictionary).is_empty():
		return false
	return true


## From the host: now carrying someone, carried by someone, or neither.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_carry(now_carrying: int, now_carried_by: int) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		set_carry_state(now_carrying, now_carried_by)


func set_carry_state(now_carrying: int, now_carried_by: int) -> void:
	var was_carried := carried_by != 0
	carrying = now_carrying
	carried_by = now_carried_by
	_struggle = 0
	if carried_by != 0:
		_release_held(false)
		_wind_up = -1.0
		_punch_wind = -1.0
		winding = false
		straining = false
		velocity = Vector3.ZERO
		say_to_all("vo_yelp")
	elif was_carried:
		velocity = Vector3.ZERO
		reset_physics_interpolation()


## From the host: thrown by someone, with this much speed.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_thrown(velocity_now: Vector3, thrower: int) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		set_thrown(velocity_now, thrower)


func set_thrown(velocity_now: Vector3, _thrower: int) -> void:
	# A bail out of Chefty (chefty_drive.gd host_eject) clears the seat and throws
	# in the same breath: on the host in one call, on a client in one poll (the
	# seats and the throw ride the same reliable channel, in order). Catch the seat
	# up now, or _apply_bonk still sees us seated and drops the fling.
	var was_in := _seat_ride if _seat_ride != null and is_instance_valid(_seat_ride) and _seat_ride.has_method("solid_body") else null
	_seat_on_ride()
	# Out of Chefty (driving C3): you go through its cab roof and rails on the way
	# out instead of slamming into the back of the cab and dropping into the bed.
	if was_in != null:
		var solid := was_in.call("solid_body") as PhysicsBody3D
		if solid != null:
			add_collision_exception_with(solid)
			get_tree().create_timer(Constants.CHEFTY_SPILL_CLEAR_SECONDS, true, true).timeout.connect(func() -> void:
				if is_instance_valid(solid):
					remove_collision_exception_with(solid))
	carried_by = 0
	thrown = true
	_thrown_left = Constants.THROWN_SECONDS
	_apply_bonk(velocity_now, "heavy")
	say_to_all("vo_yelp")


## Every peer, from brawl.gd: this player just swung (for the first-person arms).
func note_swing(_tier: String) -> void:
	_swing_left = 0.45


## Carried: you hang in front of whoever's got you, kicking. Mash the movement
## keys to wriggle free.
func _step_carried(_delta: float) -> void:
	var carrier := _player_named(carried_by)
	if carrier == null:
		return
	var forward := -carrier.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP)
	# Slung over their right shoulder, legs out front, so they can still see.
	global_position = carrier.global_position + forward * 0.3 + right * 0.5 + Vector3(0.0, 0.95, 0.0)
	body_yaw = atan2(-forward.x, -forward.z) + PI * 0.5
	velocity = Vector3.ZERO
	anim_state = AnimState.AIR
	for action: String in ["move_left", "move_right", "move_forward", "move_back", "jump"]:
		if Input.is_action_just_pressed(action):
			_struggle += 1
	if _struggle >= Constants.STRUGGLE_PRESSES:
		_struggle = 0
		get_tree().get_first_node_in_group("brawl").call("request_break_free")


func _player_named(peer_id: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node as Node3D
	return null


## From the host (leaf_field.gd): in or out of a pile. Out, you pop up where you were.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_pile(hidden: bool) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		set_pile(hidden)


## The owner sets its own flag (the host decided, or this player climbs out).
## Out, you pop up out of the leaves (player/hide_view.gd), the leaves burst.
func set_pile(hidden: bool) -> void:
	if hidden == in_pile:
		return
	in_pile = hidden
	if hidden:
		_stow_hands()
		velocity = Vector3.ZERO
		_hide_view().call("on_pile", true)
	else:
		say_to_all("vo_yelp")
		_hide_view().call("on_pile", false)
		_hide_view().call("pile_pop")
		_rpc_pile_popped.rpc()


## Every other peer (P1 catch, audit nb7): this player just threw themselves at a
## pile, at server time `at`, to land at `to`. The cannonball plays from then, not
## from the host's word that they're in (which reached a watcher after they'd landed
## standing up), and lands where they're seen to get to.
@rpc("authority", "call_remote", "reliable")
func _rpc_pile_dive(at: float, to: Vector3) -> void:
	_hide_view().call("on_pile_dive", at, to)


## Every other peer: this player just popped out of their pile (the burst and
## the sound play where they see them; the owner played its own).
@rpc("authority", "call_remote", "reliable")
func _rpc_pile_popped() -> void:
	var view := _hide_view()
	view.call("on_pile", false)
	view.call("pile_pop")


## Every peer, from in_pile replicating: the dive's leaves and sound where others see it.
var _pile_seen_in: bool = false
## When this body appeared on this peer (msec). A pile seen within
## PILE_STALE_AFTER_SPAWN_MS of it came with the spawn: old news.
var _spawned_ms: int = Time.get_ticks_msec()
const PILE_STALE_AFTER_SPAWN_MS: int = 1000


func _watch_pile() -> void:
	if is_multiplayer_authority() or in_pile == _pile_seen_in:
		return
	_pile_seen_in = in_pile
	if in_pile:
		# Already in when this peer first saw them (a late join): no replayed dive.
		var fresh := Time.get_ticks_msec() - _spawned_ms > PILE_STALE_AFTER_SPAWN_MS
		_hide_view().call("on_pile", true, fresh)


# ---------------------------------------------------------------- the pile, inspected
# The crew brain (R2 chunk 2) treats a player in a pile like a hide spot
# (net/components/hide_spot.gd has the same methods). Host only.

func suspicion() -> float:
	return float(_hide_view().call("pile_suspicion"))


func inspect_score(from: Vector3, last_seen: Vector3) -> float:
	return float(_hide_view().call("pile_inspect_score", from, last_seen))


func inspect_point() -> Vector3:
	return _hide_view().call("pile_inspect_point")


func occupants() -> Array:
	return [name.to_int()] if in_pile else []


func peek_anchor() -> Node3D:
	if not in_pile:
		return null
	return _hide_view().get("_pile_anchor") as Node3D


## The pats stopped short (he was bonked, stunned or sent home): no outcome,
## and the pile can be looked at again.
func host_inspect_cancel(crew: Node) -> void:
	if Net.is_host():
		_hide_view().call("pile_inspect_cancel", crew)
		_rpc_pile_inspect.rpc(_crew_number(crew), Net.server_time(), &"cancel")


## His line walking over, and after a near miss (R2b hide).
func inspect_bark() -> String:
	return "inspect_pile"


func near_miss_bark() -> String:
	return "near_miss_pile"


## A NICE BOY pats the pile: everyone sees the telegraph and the pats.
func host_inspect_begin(crew: Node) -> void:
	if not Net.is_host() or not in_pile:
		return
	_hide_view().call("pile_inspect_begin", crew)
	_rpc_pile_inspect.rpc(_crew_number(crew), Net.server_time(), &"begin")


## {outcome: &"found" | &"near_miss", peer}. Found turns you out toward him
## into the gotcha (without the R2 Encounter the director takes you at once).
func host_inspect_resolve(crew: Node) -> Dictionary:
	if not Net.is_host():
		return {"outcome": &"near_miss", "peer": 0}
	var result: Dictionary = _hide_view().call("pile_inspect_resolve")
	_rpc_pile_inspect.rpc(_crew_number(crew), Net.server_time(), result["outcome"])
	if result["outcome"] == &"found":
		var toward := global_position
		if crew is Node3D:
			var crew_at := (crew as Node3D).global_position
			var away := crew_at - global_position
			away.y = 0.0
			toward = crew_at - away.normalized() * Constants.HIDE_PILE_PULL_STANDOFF if away.length() > 0.1 else crew_at
			toward.y = global_position.y
		# The leaves part around his face first, then out you come (R2b hide); the
		# gotcha stands you where you land (encounter.gd reads the meta).
		set_meta(&"hide_pulled_to", [toward, Net.server_time() + Constants.HIDE_FOUND_REVEAL + Constants.HIDE_PULL_SECONDS])
		get_tree().create_timer(Constants.HIDE_FOUND_REVEAL).timeout.connect(func() -> void:
			if is_instance_valid(self) and in_pile:
				_rpc_pile_pulled.rpc(toward))
		if get_tree().get_first_node_in_group("nice_encounter") == null:
			var director := get_tree().get_first_node_in_group("run_director")
			if director != null:
				var peer_id := name.to_int()
				get_tree().create_timer(Constants.HIDE_FOUND_REVEAL + Constants.HIDE_PULL_SECONDS).timeout.connect(func() -> void:
					if is_instance_valid(director):
						director.call("note_capture", peer_id))
	return result


func _crew_number(crew: Node) -> int:
	if crew == null:
		return 0
	return int(crew.call("crew_index")) if crew.has_method("crew_index") else str(crew.name).trim_prefix("Crew").to_int()


## Every peer: a NICE BOY's pats on this player's pile (phase &"begin",
## &"near_miss" or &"found"), from server time at.
@rpc("any_peer", "call_local", "reliable")
func _rpc_pile_inspect(crew_index: int, at: float, phase: StringName) -> void:
	if multiplayer.get_remote_sender_id() != 1 and multiplayer.get_remote_sender_id() != 0:
		return
	var crew: Node3D = null
	for group: String in ["nice_crew", "crew"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			if _crew_number(node) == crew_index:
				crew = node as Node3D
	var where := global_position + Vector3(0.0, 0.4, 0.0)
	var sfx := get_tree().get_first_node_in_group("sfx")
	# He bends over the pile, and the hider's view is drawn to him (R2b hide).
	_hide_view().call("on_pile_inspect", crew, phase, at)
	if phase == &"cancel":
		return
	match phase:
		&"begin":
			load("res://props/hide_spot.gd").crew_gesture(crew, "pile_pat", "scribble")
			if sfx != null and maxf(0.0, Net.server_time() - at) < 0.5:
				for pat: int in 3:
					get_tree().create_timer(0.3 + 0.45 * float(pat)).timeout.connect(func() -> void:
						if is_instance_valid(sfx):
							# Yours land right over your head: past the muffle (R2c hide).
							sfx.call("play_clear" if is_multiplayer_authority() and in_pile and sfx.has_method("play_clear") else "play_at", "peek_rustle", where, -2.0))
		&"near_miss":
			load("res://props/hide_spot.gd").crew_gesture(crew, "shrug_notice", "scratch")
		_:
			load("res://props/hide_spot.gd").crew_gesture(crew, "upsy_daisy", "point")


## The owner: found in the pile, lifted out toward the NICE BOY.
@rpc("any_peer", "call_local", "reliable")
func _rpc_pile_pulled(toward: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != 1 and multiplayer.get_remote_sender_id() != 0:
		return
	if is_multiplayer_authority():
		in_pile = false
		_hide_view().call("on_pile", false)
		_hide_view().call("pile_pop", toward)
		_rpc_pile_popped.rpc()


## From the host (net/work/job_tasks.gd): paint (1) or water (2) landed on you.
## Water washes paint off, and you slip for a moment.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_coat(kind: int) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		set_coat(kind)


## The owner wears what the host says landed on them.
func set_coat(kind: int) -> void:
	coat = kind
	_coat_left = Constants.PAINT_SECONDS if kind == 1 else Constants.SOAK_SECONDS
	if kind == 2:
		say_to_all("vo_yelp")
		if _stun_left <= 0.0 and _ladder == null and not in_pile:
			_stun_left = Constants.SOAK_SLIP_SECONDS
	else:
		say_to_all("vo_eh")


## What was in this player's hands last frame, so their arms carry it to its
## pocket while it's being put away (_process).
var _last_hand_prop: Node3D = null


## Every peer: what this player looks like right now beyond the body's own
## animation: gone into a pile (with a mound of leaves over them), paint, water.
func _process(_delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	# Hidden, only the drawn body goes; Visual (and the camera under it) stays
	# (R2 chunk 3: hiding $Visual froze the first-person view). The mound, the
	# tells, the shot and the muffle are player/hide_view.gd's.
	_watch_pile()
	if _hidden_spot != null or in_pile or has_node("HideView"):
		var view := _hide_view()
		set_body_drawn(bool(view.call("body_should_draw")))
		view.call("present", _delta)
	var body_now := get_node_or_null("Visual/CartoonBody")
	# Asleep on a cot: lying down on it, for everyone (crew-06).
	if body_now != null:
		body_now.call("lie_down", is_lying_on_cot())
	# Everyone sees this player's hands on what they hold (the grips their own
	# first-person arms use too), except when they're flat on their back.
	if body_now != null:
		var held := _held_prop() as Node3D
		# Just put away: the hands go with it to its pocket (hotbar chunk D).
		if held != null:
			_last_hand_prop = held
		elif _last_hand_prop != null and is_instance_valid(_last_hand_prop) and _PropLooks.is_stowing(_last_hand_prop):
			held = _last_hand_prop
		else:
			_last_hand_prop = null
		# Sitting in Chefty's cab, standing in its bed, hands on the wheel if driving.
		body_now.call("sit", 1 if (_stage_pose == &"sit_buckled" and is_staged()) or _step_sitting() or seat_state == SEAT_STATE_SLIDING else _Seated.pose_for(self))
		var wheel := _Seated.wheel_grips(self)
		if not wheel.is_empty():
			body_now.call("set_hold", wheel[0], wheel[1])
		elif has_meta(&"body_hands") and anim_state != AnimState.KNOCKED and carried_by == 0:
			# Hands on something that isn't held as a prop, as everyone else sees
			# them (R2c annex: a window's stamp out of its hatch): world points
			# {"right", "left"}, either one left out to leave that arm be.
			var hands: Dictionary = get_meta(&"body_hands")
			body_now.call("set_hold", hands.get("right", Vector3.INF), hands.get("left", Vector3.INF))
		elif held != null and anim_state != AnimState.KNOCKED and carried_by == 0:
			var grips := _PropLooks.grip_points(held, self)
			body_now.call("set_hold", grips[0], grips[1])
		else:
			body_now.call("set_hold", Vector3.INF, Vector3.INF)
	if body_now != null and not bool(body_now.call("is_gesturing")):
		if carried_by != 0:
			body_now.call("gesture", "flail")
		elif winding:
			body_now.call("gesture", "windmill")
	if coat != _coat_shown:
		_coat_shown = coat
		var body := get_node_or_null("Visual/CartoonBody")
		if body != null:
			match coat:
				1:
					body.call("set_coat", Color(0.97, 0.96, 0.93), 0.9)
				2:
					body.call("set_coat", Color(0.45, 0.65, 0.95), 0.35)
				_:
					body.call("set_coat", Color.WHITE, 0.0)


## Host only: put this player somewhere. The owning peer moves its own character
## (NETCODE.md, host-to-owner pattern). Used right after spawning: the host's
## starting position doesn't reach a client that owns its own movement, so every
## client used to start at the origin, inside each other.
func send_teleport(at: Transform3D) -> void:
	if not Net.is_host():
		return
	if name.to_int() == Net.local_peer_id():
		apply_network_teleport(at)
	else:
		_rpc_teleport.rpc_id(name.to_int(), at)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_teleport(at: Transform3D) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	apply_network_teleport(at)


## Host: off a seat and down onto at, a hop from where they are (step_down_to),
## never a teleport (p1-arrive: getting out of Chefty popped you 1.9 m). path: how
## the hop clears the vehicle (net/components/step_down.gd hop_path).
func send_step_down(at: Transform3D, wait: float = 0.0, path := Vector4.ZERO) -> void:
	if not Net.is_host():
		return
	if name.to_int() == Net.local_peer_id():
		step_down_to(at, wait, path)
	else:
		_rpc_step_down.rpc_id(name.to_int(), at, wait, path)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_step_down(at: Transform3D, wait: float, path: Vector4) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	step_down_to(at, wait, path)


## Host (net/components/personal_space.gd): ease this player along push (m/s,
## flat) for a moment, out of someone they're standing inside.
func send_nudge(push: Vector3) -> void:
	if not Net.is_host():
		return
	if name.to_int() == Net.local_peer_id():
		nudge(push)
	else:
		_rpc_nudge.rpc_id(name.to_int(), push)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_nudge(push: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	nudge(push)


## Host-ordered teleport. Runs on the owning peer only.
func apply_network_teleport(at: Transform3D) -> void:
	# A host-ordered move ends any step off a cot (_step_sleep).
	_wake_to = Vector3.INF
	global_position = at.origin
	_fall_peak = at.origin.y
	_airborne = false
	_bounced = false
	velocity = Vector3.ZERO
	body_yaw = at.basis.get_euler().y
	_apply_presentation()
	# With physics interpolation on, a teleport would smear across the map for a frame.
	reset_physics_interpolation()


func _grab_nearby() -> bool:
	var held := _held_prop()
	if held != null and str(held.get("kind")) == "leaf_bag":
		var barrow := _nearest_kind("wheelbarrow", 2.4)
		if barrow != null:
			barrow.call("request_load_held")
			return true
	# Something big in both hands: nothing else fits. A pocket item in hand goes
	# in its pocket on the host when the new thing comes up (net/components/hotbar.gd).
	if not _hands_can_pick_up():
		return false
	var closest := _best_pickup()
	if closest == null:
		return false
	closest.call("request_grab")
	return true


## What E picks up: whatever is in reach, favoring what you're looking at, and
## a leaf bag over the rake you just put down beside it.
func _best_pickup() -> Node3D:
	var forward := -global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var best: Node3D = null
	var best_score := INF
	for node: Node in get_tree().get_nodes_in_group("props"):
		var prop := node as Node3D
		# A bag you just tossed is on its way, not something to pick up.
		if prop == null or not bool(prop.call("is_loose")) or bool(prop.call("is_flying")):
			continue
		var offset := prop.global_position - global_position
		var distance := offset.length()
		if distance >= Constants.PICKUP_REACH:
			continue
		var flat := Vector3(offset.x, 0.0, offset.z)
		var facing := flat.normalized().dot(forward) if flat.length() > 0.05 else 1.0
		# In front counts as closer; behind counts as farther.
		var score := distance * (1.25 - 0.45 * facing)
		if str(prop.get("kind")) == "leaf_bag":
			score -= Constants.PICKUP_BAG_PREFERENCE
		if score < best_score:
			best_score = score
			best = prop
	return best


## What E would do right now, for the prompt in ui/interaction_prompt.gd: the
## same decision E itself acts on (e_choice), so E never does a thing whose
## prompt isn't showing. Empty when E does nothing here, or does something the
## world already shows (climbing out of a hedge, heaving a bag into Chefty).
func interaction_hint() -> Dictionary:
	# Seated in Chefty: a key over the seat or the hired hand you look at, else
	# nothing (p1-dash: E gets you out the way it got you in).
	if in_vehicle():
		var vehicle := _Seated.vehicle_of(self)
		return vehicle.call("seat_hint", self) if vehicle != null and vehicle.has_method("seat_hint") else {}
	var choice := e_choice()
	var hint: Dictionary = choice["hint"]
	# A fresh notice (out of bags) shows only while E has nothing else to say.
	if hint.is_empty() and StringName(choice["do"]) == &"none" and _notice_text != "" and Time.get_ticks_msec() < _notice_until:
		return {"text": _notice_text, "at": global_position + Vector3(0.0, 2.2, 0.0), "plain": true}
	return hint


## E, decided once (p1-hands, docs/GAME.md "What E does"): {do, hint, target}.
## do is what E does (&"none" when nothing), hint the prompt that says so ({}
## when the world already says it), target what it acts on. In order:
##   1. what has you or your hands: hidden (E climbs out), the paint bucket, the
##      water, the gas can, a ladder, carrying a teammate (put down), held by one;
##   2. in a raid, the nearest hiding spot or a pile underfoot;
##   3. what your hands are full of: a bag or junk into Chefty, a loaded
##      wheelbarrow dumped, a bag into the wheelbarrow;
##   4. what you're looking right at: a teammate close enough to grab, the junk
##      at Chefty's tailgate, a thing to pick up;
##   5. a leaf bag in reach (the work comes first);
##   6. what the place is for: Board at Chefty's pad, Talk by the homeowner, a
##      cot, a window, a shelf (anything in the "prompt_sources" group);
##   7. whatever else is in reach: a thing to pick up, litter, a weed, the junk,
##      a seat;
##   8. outside a raid, a hiding spot or a pile, last of all.
func e_choice() -> Dictionary:
	var none := {"do": &"none", "hint": {}, "target": null}
	# Seated in Chefty the seat has E (player/seated.gd); the drive HUD shows its keys.
	if in_vehicle():
		return none
	# Sitting in Chefty's bed (the ride, or its honk-and-wait): E is the truck's
	# (hold to hit the road, net/components/ride.gd polls it), not the junk or a
	# bag nearby; its prompt is the ride's own (integration of p1-depart and p1-hands).
	if _ride != null:
		var ride_hint: Dictionary = _ride.call("prompt") if _ride.has_method("prompt") else {}
		return {"do": &"ride", "hint": ride_hint, "target": _ride}
	# Hidden, or on the way in or out: E gets you out, which you already know.
	if _hidden_spot != null or in_pile or _hide_moving():
		return {"do": &"hide_toggle", "hint": {}, "target": null}
	var held := _held_prop()
	var held_kind := str(held.get("kind")) if held != null else ""
	if held_kind == "paint_roller" and _nearest_bucket() != null:
		var bucket := _nearest_bucket()
		return {"do": &"water", "hint": {"text": _Strings.UI["prompt_dip"], "at": bucket.global_position + Vector3(0.0, 0.6, 0.0), "source": bucket}, "target": held}
	if held_kind == "hose" or held_kind == "pressure_washer":
		var source := _WaterSources.nearest(get_tree(), global_position, Constants.WATER_REACH)
		# Chefty's own tap sits beside its bed: looking at the bed rather than the
		# tap with a tool that fits aboard, E loads it (below) instead.
		if source != null and str(source.get_meta("kind")) == "chefty" and _looking_to_load(held, held_kind, source.global_position):
			source = null
		if source != null:
			var key := "prompt_refill"
			if held_kind == "hose":
				key = "prompt_unhook" if str(held.get("hose_source")) == str(source.get_meta("kind")) else "prompt_hook_" + str(source.get_meta("kind"))
			return {"do": &"water", "hint": {"text": _Strings.UI[key], "at": source.global_position + Vector3(0.0, 0.9, 0.0), "source": source}, "target": held}
	# The gas can by a gas tool that isn't full: fill it up (gap-specs critic C29).
	if held_kind == "gas_can":
		var thirsty := held.call("refuel_target") as Node3D
		if thirsty != null:
			return {"do": &"refuel", "hint": {"text": _Strings.SHOP_UI["prompt_refuel"] % int(float(thirsty.get("fuel"))), "at": thirsty.global_position + Vector3(0.0, 0.9, 0.0), "source": thirsty}, "target": held}
	if _ladder != null:
		return {"do": &"climb", "hint": {"text": _Strings.UI["prompt_climb_down"], "at": global_position + Vector3(0.0, 2.2, 0.0) - global_basis.z * 0.6}, "target": null}
	var ladder := _nearest_ladder()
	if ladder != null and (held == null or held_kind == "leaf_blower"):
		return {"do": &"climb", "hint": {"text": _Strings.UI["prompt_climb_up"], "at": ladder.global_position + Vector3(0.0, 1.8, 0.0), "source": ladder}, "target": null}
	var ladder_top := _nearest_ladder_top()
	if ladder_top != null:
		return {"do": &"climb", "hint": {"text": _Strings.UI["prompt_climb_down"], "at": (ladder_top.get("ladder_top") as Vector3) + Vector3(0.0, 0.8, 0.0), "source": ladder_top}, "target": null}
	# Carried: you can see you are, and mashing to wriggle is what anyone tries.
	if carried_by != 0:
		return {"do": &"held", "hint": {}, "target": null}
	if carrying != 0:
		return {"do": &"put_down", "hint": {"text": _Strings.UI["prompt_put_down"], "at": global_position - global_basis.z * 0.9 + Vector3(0.0, 1.9, 0.0)}, "target": null}
	var raid := _raid_on()
	if raid:
		var hide := _hide_choice()
		if not hide.is_empty():
			return hide
	# p2-kit: the crew's kit on Chefty's rack. The one you look at is yours to
	# take ("[E] Take", ahead of loading the one in your hands: the thing you
	# look at wins); a tool in your hands by the bed goes on it ("[E] Load").
	var tool_bed := _tool_bed()
	var bed_look: Dictionary = tool_bed.call("looked_at", self) if tool_bed != null and (held == null or _KitRules.is_kit_kind(held_kind)) else {}
	if not bed_look.is_empty():
		return {"do": &"take_kit", "hint": {"text": _Strings.SHOP_UI["prompt_take_kit"], "at": (bed_look["at"] as Vector3) + Vector3(0.0, 0.45, 0.0), "source": "tool_bed/" + str(bed_look["slot"])}, "target": bed_look}
	if held != null and _KitRules.is_kit_kind(held_kind) and tool_bed != null and bool(tool_bed.call("can_load_from", self)) and bool(tool_bed.call("has_room_for", held_kind)):
		return {"do": &"load_truck", "hint": {"text": _Strings.SHOP_UI["prompt_load_kit"], "at": tool_bed.call("load_point") as Vector3, "source": "tool_bed/load"}, "target": held}
	# Hands full: what they're full of goes where it goes. A bag (or junk) heaved
	# in over Chefty's side needs no words: the bag in your arms by the bed says it.
	if held != null and bool(held.call("near_truck")):
		if held_kind == "leaf_bag" or held_kind == "junk":
			return {"do": &"load_truck", "hint": {}, "target": held}
		if held_kind == "wheelbarrow" and int(held.get("stored_bags")) > 0:
			return {"do": &"load_truck", "hint": {"text": _Strings.UI["prompt_dump_truck"], "at": held.global_position + Vector3(0.0, 1.0, 0.0), "source": held}, "target": held}
	if held_kind == "leaf_bag":
		var barrow := _nearest_kind("wheelbarrow", 2.4) as Node3D
		if barrow != null:
			return {"do": &"load_barrow", "hint": {"text": _Strings.UI["prompt_load_bag"], "at": barrow.global_position + Vector3(0.0, 1.4, 0.0), "source": barrow}, "target": barrow}
	var can_pick := _hands_can_pick_up()
	# Looking right at it.
	var mate := _grabbable_player()
	if mate != null:
		return {"do": &"grab_player", "hint": {"text": _Strings.UI["prompt_grab"], "at": mate.global_position + Vector3(0.0, 2.0, 0.0), "source": mate}, "target": mate}
	var junk_bed := _junk_tailgate()
	if junk_bed != null and _look_miss(junk_bed.call("tailgate_point") as Vector3, Constants.PICKUP_REACH + Constants.E_LOOK_JUNK_SLACK) <= Constants.E_LOOK_MISS:
		return _junk_choice(junk_bed)
	var looked := _looked_at_pickup() if can_pick else null
	if looked != null:
		return _pickup_choice(looked)
	var best := _best_pickup() if can_pick else null
	# A leaf bag in reach: the work comes before the place.
	if best != null and str(best.get("kind")) == "leaf_bag":
		return _pickup_choice(best)
	# What the place is for.
	for source: Node in get_tree().get_nodes_in_group("prompt_sources"):
		var hint: Dictionary = source.call("prompt")
		if not hint.is_empty():
			return {"do": &"source", "hint": hint, "target": source}
	if best != null:
		return _pickup_choice(best)
	var hand := _nearest_hand_task()
	if not hand.is_empty():
		var key := {"pick_litter": "prompt_pick_litter", "pull_weeds": "prompt_pull_weed", "skim_pool": "prompt_skim_pool"}.get(str(hand["task"]), "prompt_pick_litter") as String
		return {"do": &"hand_task", "hint": {"text": _Strings.UI[key], "at": (hand["at"] as Vector3) + Vector3(0.0, 0.6, 0.0), "source": "%s:%d" % [hand["task"], int(hand["index"])]}, "target": hand}
	if junk_bed != null:
		return _junk_choice(junk_bed)
	var seat_hint := _Seated.hint(self)
	if not seat_hint.is_empty():
		return {"do": &"seat", "hint": seat_hint, "target": null}
	# Outside a raid a hedge is a hedge: diving in comes last, and never with
	# something big in your arms (NB-07: E for the bag beside it dove in).
	if not raid and can_pick:
		var hide := _hide_choice()
		if not hide.is_empty():
			return hide
	# Nothing to do with E: say what's wrong with the tool in hand, if anything.
	var supply := _supply_hint()
	return {"do": &"none", "hint": supply, "target": null}


## E, acted on (from _input, ahead of every other listener). True when E was
## this player's to act on; false leaves it to whatever else listens (the
## Shuttle's unbuckle, Annex B's windows, a seat).
func _press_e(event: InputEvent) -> bool:
	if not is_multiplayer_authority() or in_vehicle():
		return false
	if not _locks.is_empty() and not control_allows("interact"):
		return false
	# A window, the pause menu or a text box has the keys.
	var ui := get_tree().get_first_node_in_group("game_ui")
	if ui != null and ui.has_method("any_window_open") and bool(ui.call("any_window_open")):
		return false
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return false
	# The moment has you (caught, the van, Annex B): no prompts, and E is the
	# moment's (ui/hud_mode.gd).
	if _HudMode.reason(get_tree(), name.to_int()) != &"":
		return false
	# Unbuckling a friend from the Courtesy Shuttle is the Shuttle's (shuttle.gd).
	var shuttle := get_tree().get_first_node_in_group("nice_shuttle")
	if shuttle != null and shuttle.has_method("_unbuckle_target") and not (shuttle.call("_unbuckle_target") as Dictionary).is_empty():
		return false
	var choice := e_choice()
	var target: Variant = choice["target"]
	match StringName(choice["do"]):
		&"hide_toggle", &"hide":
			_toggle_hiding()
		&"water":
			_water_hookup()
		&"refuel":
			_refuel()
		&"climb":
			_toggle_climb()
		&"held", &"ride":
			pass
		&"put_down", &"grab_player":
			_grab_player()
		&"load_truck":
			(target as Node).call("request_load_truck")
		&"take_kit":
			var bed := _tool_bed()
			if bed != null:
				bed.call("request_take", int((target as Dictionary)["index"]))
		&"load_barrow":
			(target as Node).call("request_load_held")
		&"pick_up":
			(target as Node).call("request_grab")
		&"unload_junk":
			(target as Node).call("request_unload")
		&"source":
			# The source answers E itself, the way it always has; only it hears this
			# one. If it passed (a cot that isn't the nearest), the rest hear it.
			(target as Node).call("_unhandled_input", event)
			return get_viewport().is_input_handled()
		&"hand_task":
			_hand_task()
		&"seat":
			_Seated.try_enter(self)
		_:
			return false
	return true


## Chefty's kit aboard (net/components/tool_bed.gd), or null. Not while a ride
## has you: the seat has E then.
func _tool_bed() -> Node:
	var chefty := get_tree().get_first_node_in_group("chefty")
	return chefty.call("tool_bed") as Node if chefty != null and chefty.has_method("tool_bed") else null


## Whether the kit tool in hand could go aboard now and the look is on Chefty's
## bed more than on this point (its water tap): the load wins there.
func _looking_to_load(held: Node, held_kind: String, tap: Vector3) -> bool:
	var tool_bed := _tool_bed()
	if held == null or tool_bed == null or not _KitRules.is_kit_kind(held_kind):
		return false
	if not bool(tool_bed.call("can_load_from", self)) or not bool(tool_bed.call("has_room_for", held_kind)):
		return false
	var reach := Constants.KIT_LOAD_REACH + Constants.E_LOOK_REACH_SLACK
	return _look_miss(tool_bed.call("load_point") as Vector3, reach) < _look_miss(tap, reach)


## The nearest hiding spot with room, or the pile underfoot, as an E choice; {} for neither.
func _hide_choice() -> Dictionary:
	var spot := _nearest_free_spot()
	if spot != null:
		return {"do": &"hide", "hint": {"text": _Strings.UI["prompt_hide"], "at": spot.call("prompt_point", global_position) as Vector3, "source": spot}, "target": spot}
	if _on_pile():
		return {"do": &"hide", "hint": {"text": _Strings.UI["prompt_pile_dive"], "at": global_position + Vector3(0.0, 0.5, 0.0) - global_basis.z * 0.8}, "target": null}
	return {}


func _junk_choice(bed: Node) -> Dictionary:
	return {"do": &"unload_junk", "hint": {"text": _Strings.SHOP_UI["prompt_unload_junk"], "at": (bed.call("tailgate_point") as Vector3) + Vector3(0.0, 1.5, 0.0)}, "target": bed}


## Picking a thing up, as an E choice. A pocket item with every pocket full (and
## no stack of its kind to join) shows no prompt: E shakes the full bar (x1:text).
func _pickup_choice(prop: Node3D) -> Dictionary:
	var kind_of := str(prop.get("kind"))
	if _Hotbar.is_pocketable(kind_of) and not _Hotbar.has_room(get_tree(), name.to_int(), kind_of):
		return {"do": &"pick_up", "hint": {}, "target": prop}
	# x1:text: the key and the verb; the thing is right there under the prompt.
	return {"do": &"pick_up", "hint": {"text": _Strings.UI["prompt_pick_up_plain"], "at": prop.global_position + Vector3(0.0, 1.2, 0.0), "source": prop}, "target": prop}


## The NICE BOYS are warning, chasing or leaving (net/run_events/director.gd), as this peer knows it.
func _raid_on() -> bool:
	var director := get_tree().get_first_node_in_group("run_director")
	return director != null and director.has_method("phase") and int(director.call("phase")) != 0


## How far your line of sight passes from a point (m, square to the look), or
## INF when it's behind you or farther than reach from your eye.
func _look_miss(point: Vector3, reach: float) -> float:
	var head := get_node_or_null("Visual/Head") as Node3D
	var eye := head.global_position if head != null else global_position + Vector3(0.0, 1.6, 0.0)
	var aim := -(head.global_basis.z if head != null else global_basis.z).normalized()
	var to := point - eye
	var along := to.dot(aim)
	if along <= 0.0 or to.length() > reach:
		return INF
	return (to - aim * along).length()


## The thing in reach you're looking right at (the nearest along your look), or null.
func _looked_at_pickup() -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for node: Node in get_tree().get_nodes_in_group("props"):
		var prop := node as Node3D
		if prop == null or not bool(prop.call("is_loose")) or bool(prop.call("is_flying")):
			continue
		if prop.global_position.distance_to(global_position) >= Constants.PICKUP_REACH:
			continue
		# Anywhere from its foot to its top counts (a wheelbarrow's handles, a bag's neck).
		var middle := prop.global_position + Vector3(0.0, _PropLooks.VISUAL_HEIGHT, 0.0)
		var miss := INF
		for height: float in [Constants.E_LOOK_PROP_FOOT, _PropLooks.VISUAL_HEIGHT, _PropLooks.VISUAL_HEIGHT * 2.0]:
			miss = minf(miss, _look_miss(prop.global_position + Vector3(0.0, height, 0.0), Constants.PICKUP_REACH + Constants.E_LOOK_REACH_SLACK))
		if miss > Constants.E_LOOK_MISS:
			continue
		var distance := middle.distance_to(global_position)
		if distance < best_distance:
			best_distance = distance
			best = prop
	return best


## The nearest hiding spot with room that can be got into from here, measured
## to its edge (a long hedge is as easy to get into at its end), or null.
func _nearest_free_spot() -> Node3D:
	var closest: Node3D = null
	var closest_distance := Constants.HIDE_REACH_EDGE
	for node: Node in get_tree().get_nodes_in_group("hide_spots"):
		var spot := node as Node3D
		if spot == null or not bool(spot.call("has_room")):
			continue
		# A shed only from before its door.
		if spot.has_method("can_enter_from") and not bool(spot.call("can_enter_from", global_position)):
			continue
		var distance := float(spot.call("reach_distance", global_position))
		if distance <= closest_distance:
			closest = spot
			closest_distance = distance
	return closest


func _held_prop() -> Node:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if int(node.get("held_by")) == name.to_int():
			return node
	return null


func _nearest_kind(prop_kind: String, reach: float) -> Node:
	var closest: Node = null
	var closest_distance := reach
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) != prop_kind or not node is Node3D:
			continue
		var distance := global_position.distance_to((node as Node3D).global_position)
		if distance < closest_distance:
			closest = node
			closest_distance = distance
	return closest


## Hands away (hiding, a pile, a cot): a pocket item goes back in its pocket, a
## big item is set down. Knockouts and faints still drop what's in hand (_release_held).
func _stow_hands() -> void:
	if not is_multiplayer_authority():
		return
	var held := _held_prop()
	if held == null:
		return
	if _Hotbar.is_pocketable(str(held.get("kind"))) and pockets() != null:
		pockets().call("select", -1)
	else:
		_release_held(false)


## True when what's in hand can go in a pocket (or nothing is in hand), so E may
## still pick something up: the host pockets the one in hand first.
func _hands_can_pick_up() -> bool:
	var held := _held_prop()
	return held == null or _Hotbar.is_pocketable(str(held.get("kind")))


func _release_held(throw_it: bool) -> void:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if int(node.get("held_by")) != name.to_int():
			continue
		if throw_it:
			node.call("request_throw", -global_transform.basis.z)
		else:
			node.call("request_drop")
		return


func holding_prop() -> bool:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if int(node.get("held_by")) == name.to_int():
			return true
	return false


## Mouse sensitivity and invert look are this machine's settings (core/settings.gd).
func _apply_look() -> void:
	var turn := Settings.look_scale()
	body_yaw -= _look.x * turn.x
	head_pitch = clampf(head_pitch - _look.y * turn.y, -PITCH_LIMIT, PITCH_LIMIT)
	_look = Vector2.ZERO
	# Hidden: the look turns round the spot's facing, within its clamps, so the
	# replicated yaw (the hedge's tremble, the pile's rustle) is the real look.
	# The peek shot (StageCam) takes the mouse; the body turns with it.
	if (_hidden_spot != null or in_pile) and not _hide_moving():
		var facing := float(_hide_view().call("facing_yaw"))
		var cam := stage_cam()
		if cam != null and stage_top() == &"hide_peek":
			var angles: Vector2 = cam.call("look_angles")
			body_yaw = facing + angles.x
			head_pitch = angles.y
		elif cam != null and stage_top() == &"hide_orbit":
			# Swinging the orbit round turns the hider too (within the peek's
			# clamp), so a hard turn still shakes the hedge.
			var orbit: Vector2 = cam.call("look_angles")
			body_yaw = facing + clampf(orbit.x, -Constants.HIDE_YAW_CLAMP, Constants.HIDE_YAW_CLAMP)
		else:
			body_yaw = facing + clampf(angle_difference(facing, body_yaw), -Constants.HIDE_YAW_CLAMP, Constants.HIDE_YAW_CLAMP)
			head_pitch = clampf(head_pitch, Constants.HIDE_PITCH_CLAMP.x, Constants.HIDE_PITCH_CLAMP.y)


func _simulate(delta: float) -> void:
	# Hold or toggle, as the player chose (Settings controls/toggle_crouch).
	var crouching := Settings.is_held(&"crouch")
	_apply_stance(crouching)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump") and not crouching:
		velocity.y = JUMP_VELOCITY
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var speed := WALK_SPEED
	if crouching:
		speed = CROUCH_SPEED
	elif Settings.is_held(&"sprint"):
		speed = SPRINT_SPEED
	speed *= carry_speed_scale() * snack_buff("speed")
	if foot_hurt >= 2:
		speed = minf(speed, WALK_SPEED) * Constants.HOP_SPEED_SHARE
	elif limping:
		speed = minf(speed, WALK_SPEED) * Constants.LIMP_SPEED_SHARE
	if direction.is_zero_approx():
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)
	else:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	_apply_nudge(delta)
	move_and_slide()
	_update_anim(crouching, direction)
	_stay_on_the_pad()
	_steps(delta)


## How far the throw is wound up, 0 to 1, or -1 when G isn't held. Past 1 is
## straining (ui/throw_meter.gd draws it).
func wind_up_share() -> float:
	if _punch_wind >= 0.0:
		return _punch_wind / float(Constants.PUNCH_WIND_TIERS[1])
	if _wind_up < 0.0:
		return -1.0
	return _wind_up / Constants.THROW_CHARGE_SECONDS


## Seconds G has been held, or -1.
func wind_up_seconds() -> float:
	return _wind_up


## Hold G to wind up a throw, release to let it fly; a tap just sets it down.
## Hold on too long and you strain, then faint and drop it.
func _step_wind_up(delta: float) -> void:
	var held := _held_prop()
	var pressing := Input.is_action_pressed("drop") and (held != null or carrying != 0) and _stun_left <= 0.0 and _hidden_spot == null and not in_vehicle()
	if pressing:
		# Burnt coffee: you hold on longer before you strain, and before you faint.
		var hold := snack_buff("strain")
		if _wind_up < 0.0:
			_wind_up = 0.0
			_next_strain = Constants.THROW_STRAIN_SECONDS * hold
		_wind_up += delta
		straining = _wind_up >= Constants.THROW_STRAIN_SECONDS * hold
		if straining:
			if _wind_up >= _next_strain:
				_next_strain = _wind_up + 1.3
				say_to_all("vo_strain")
		if _wind_up >= Constants.THROW_FAINT_SECONDS * hold:
			_faint()
		return
	if _wind_up < 0.0:
		return
	var seconds := _wind_up
	_wind_up = -1.0
	straining = false
	var body := get_node_or_null("Visual/CartoonBody")
	# Carrying someone: a tap sets them down, a wind-up throws them.
	if carrying != 0:
		var brawl := get_tree().get_first_node_in_group("brawl")
		if seconds < Constants.THROW_TAP_SECONDS:
			brawl.call("request_release_player", "drop")
		else:
			var throw_share := clampf(seconds / Constants.THROW_CHARGE_SECONDS, 0.0, 1.0)
			brawl.call("request_release_player", "throw", -global_transform.basis.z, lerpf(Constants.THROW_POWER_MIN, Constants.THROW_POWER_MAX, throw_share))
			say_to_all("vo_heave")
		return
	if held == null:
		return
	if seconds < Constants.THROW_TAP_SECONDS:
		_release_held(false)
		return
	var share := clampf(seconds / Constants.THROW_CHARGE_SECONDS, 0.0, 1.0)
	var power := lerpf(Constants.THROW_POWER_MIN, Constants.THROW_POWER_MAX, share)
	# From where you stand as you let go: at 150 ms the host has you a step back,
	# and a toss at Chefty's bed must leave from your feet (Constants.THROW_FROM_TOLERANCE).
	held.call("request_throw", -global_transform.basis.z, power, global_position)
	say_to_all("vo_heave" if share > 0.7 else "vo_hup")
	if body != null and not bool(body.call("is_gesturing")):
		body.call("gesture", "startle")


## Held it up too long: the world spins, you drop it and go down for a moment.
func _faint() -> void:
	_wind_up = -1.0
	straining = false
	_release_held(false)
	if carrying != 0:
		get_tree().get_first_node_in_group("brawl").call("request_release_player", "drop")
	_stun_left = Constants.FAINT_SECONDS
	_knocked = true
	say_to_all("vo_oof")


## A noise from this player that every peer hears from their head.
func say_to_all(sound_name: String) -> void:
	_rpc_say.rpc(sound_name)


@rpc("authority", "call_local", "unreliable")
func _rpc_say(sound_name: String) -> void:
	say(sound_name)


## H on Chefty's ride to or from a job (the legacy path ride, net/components/
## ride.gd): Chefty's meep-meep, heard by everyone where the truck is. A seat in
## the drivable Chefty honks through its own controls (player/seated.gd).
func _honk() -> bool:
	if _ride == null or not is_instance_valid(_ride) or not _ride.is_in_group("chefty"):
		return false
	# Game time (physics ticks), so a slowed run holds the cooldown as a player feels it.
	var now := float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)
	if now >= _honk_ready_at:
		_honk_ready_at = now + Constants.HORN_COOLDOWN_SECONDS
		say_to_all("truck_horn")
	return true


## Heavy things slow you down while you carry them (Constants.CARRY_SLOWDOWN_PER_KG).
func carry_speed_scale() -> float:
	# Something set on this player from outside (the Annex's big stamp, R2 chunk 6).
	if has_meta(&"speed_share"):
		return float(get_meta(&"speed_share"))
	if carrying != 0:
		return Constants.CARRY_PLAYER_SPEED_SHARE
	var kg := 0.0
	var held := _held_prop()
	if held != null and held.has_method("weight_kg"):
		kg = float(held.call("weight_kg"))
		if Constants.ROLLING_KINDS.has(str(held.get("kind"))):
			kg *= Constants.ROLLING_WEIGHT_SHARE
	# What's in your pockets counts for a share of its weight (Constants.POCKET_WEIGHT_SHARE).
	if pockets() != null:
		kg += float(pockets().call("pocket_weight_kg")) * Constants.POCKET_WEIGHT_SHARE
	if kg <= 0.0:
		return 1.0
	# A hot dog in you: heavy things slow you half as much.
	return maxf(Constants.CARRY_SPEED_FLOOR, 1.0 - kg * Constants.CARRY_SLOWDOWN_PER_KG * snack_buff("carry"))


## What this player's snacks do to one effect ("speed", "carry", "strain",
## "stroke"; Constants.BUFFS), 1.0 with none. Read from World/Shops, which every
## peer has, so the owner moves by it and everyone agrees on it.
func snack_buff(effect: String) -> float:
	if _shops_node == null or not is_instance_valid(_shops_node):
		_shops_node = get_tree().get_first_node_in_group("shops") if is_inside_tree() else null
		if _shops_node == null:
			return 1.0
	return float(_shops_node.call("buff", name.to_int(), effect))


## Hit by a thrown item (net/components/net_prop.gd tells every peer). Everyone
## sees the flinch, stumble, or fall and hears the noise; this player's own peer
## is shoved by push and loses control for a moment, and drops what it holds
## when the hit was heavy.
func on_bonked(push: Vector3, tier: String) -> void:
	# It arrives with the network message; everything that moves waits for a physics tick.
	_pending_bonk = [push, tier]


func _apply_bonk(push: Vector3, tier: String) -> void:
	var body := get_node_or_null("Visual/CartoonBody")
	if body != null:
		match tier:
			"light":
				body.call("gesture", "startle")
			"medium":
				body.call("gesture", "stumble")
			_:
				# Thrown, the stars wait for the landing (the body's knocked flop).
				if not thrown:
					body.call("dizzy", float(Constants.BONK_STUN_SECONDS["heavy"]))
	say("vo_oof" if tier != "light" else "vo_eh")
	if not is_multiplayer_authority() or _hidden_spot != null or _on_seat:
		return
	# Any bonk on a board is a wipeout (player/skate.gd).
	if on_board:
		skate().call("wipeout", "bonk", push)
		return
	_stun_left = float(Constants.BONK_STUN_SECONDS.get(tier, 0.5))
	_knocked = tier == "heavy"
	velocity = push
	if _knocked and _held_prop() != null:
		_release_held(false)


## Owner (P1 catch, the haul-up, net/run_events/encounter.gd): hauled up off the
## grass by a NICE BOY, the knock is over now; the body gets up from here.
func end_knockdown() -> void:
	if not is_multiplayer_authority():
		return
	_stun_left = 0.0
	_knocked = false
	if anim_state == AnimState.KNOCKED:
		anim_state = AnimState.IDLE


## Stunned: sliding with the shove, no control, flat on your back if knocked.
func _step_stunned(delta: float) -> void:
	_stun_left = maxf(0.0, _stun_left - delta)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	var flat := Vector2(velocity.x, velocity.z).move_toward(Vector2.ZERO, (9.0 if is_on_floor() else 1.5) * delta)
	velocity.x = flat.x
	velocity.z = flat.y
	move_and_slide()
	# Thrown (a toss, a crash out of Chefty's bed): flailing through the air, eyes
	# on where you're headed, and flat on your back with stars only when you land.
	var flying := thrown and (_thrown_left > Constants.THROWN_SECONDS - Constants.THROWN_LIFTOFF_SECONDS or not is_on_floor())
	anim_state = AnimState.KNOCKED if _knocked and not flying else (AnimState.AIR if not is_on_floor() else AnimState.IDLE)
	if _stun_left <= 0.0:
		_knocked = false


## A thrown prop can spike velocity. Cap it, and put the player back if they leave the pad.
func _stay_on_the_pad() -> void:
	var flat := Vector2(velocity.x, velocity.z)
	# Turbo Juice runs you a little past a sprint, and no further. A board rolls
	# faster and pops higher (player/skate.gd keeps its own caps).
	var cap := SPRINT_SPEED * maxf(snack_buff("speed"), 1.0)
	if on_board:
		cap = Constants.SKATE_TOP_SPEED
	if flat.length() > cap:
		flat = flat.normalized() * cap
		velocity.x = flat.x
		velocity.z = flat.y
	if velocity.y > JUMP_VELOCITY and not on_board:
		velocity.y = JUMP_VELOCITY
	var world := get_tree().get_first_node_in_group("world") as Node3D
	if world == null:
		return
	var zone := Net.player_zone(name.to_int())
	# The connected town has no pads to stay on (driving chunk D): walk out of the
	# store, the yard and down the street. Only a fall out of the world, or
	# wandering off the edge of the map, puts you back.
	if zone != Net.Zone.BORDER and zone != Net.Zone.TRANSIT and bool(world.call("is_town_map")):
		_stay_in_town()
		return
	var pad := _pad_for_zone(world, zone)
	if pad == null:
		return
	var offset := global_position - pad.global_position
	var rect: Rect2 = Constants.PAD_RECTS.get(String(pad.name), Rect2(-20.0, -20.0, 40.0, 40.0))
	var past_edge := not rect.grow(1.0).has_point(Vector2(offset.x, offset.z))
	if not past_edge and global_position.y >= -2.0:
		return
	var at: Transform3D = world.call("get_spawn_transform", zone, &"", name.to_int())
	global_position = at.origin
	velocity = Vector3.ZERO


## The town's own rules: fallen below the world, back up on the nearest sidewalk;
## past the town's edge, held at it.
func _stay_in_town() -> void:
	if global_position.y < -2.0:
		global_position = TownMap.respawn_point(global_position)
		velocity = Vector3.ZERO
		reset_physics_interpolation()
		return
	var bounds := TownMap.TOWN_BOUNDS
	global_position.x = clampf(global_position.x, bounds.position.x, bounds.end.x)
	global_position.z = clampf(global_position.z, bounds.position.z, bounds.end.z)


func _pad_for_zone(world: Node3D, zone: Net.Zone) -> Node3D:
	match zone:
		Net.Zone.LOT:
			return world.get_node_or_null("LotZone") as Node3D
		Net.Zone.BORDER:
			return world.get_node_or_null("BorderZone") as Node3D
		Net.Zone.STORE:
			return world.get_node_or_null("StoreZone") as Node3D
		_:
			return null


func _steps(delta: float) -> void:
	if not is_on_floor() or Vector2(velocity.x, velocity.z).length() < 1.2:
		return
	_step_wait -= delta
	if _step_wait > 0.0:
		return
	_step_wait = 0.42 if not limping else 0.55
	# The footsteps themselves (and a full set of pockets jangling) are every
	# peer's, off the drawn stride (audio/player_foley.gd); a limp grumbles.
	if limping and randf() < 0.25:
		say("vo_eh" if randf() < 0.5 else "vo_oof")


func _update_anim(crouching: bool, direction: Vector3) -> void:
	if not is_on_floor():
		anim_state = AnimState.AIR
	elif crouching:
		anim_state = AnimState.CROUCH
	elif direction.is_zero_approx():
		anim_state = AnimState.IDLE
	elif Settings.is_held(&"sprint"):
		anim_state = AnimState.SPRINT
	else:
		anim_state = AnimState.WALK


func _apply_stance(crouching: bool) -> void:
	var shape := %Collision.shape as CapsuleShape3D
	var height := CROUCH_HEIGHT if crouching else STAND_HEIGHT
	shape.height = height
	%Collision.position.y = height * 0.5
	%BodyMesh.scale.y = height / STAND_HEIGHT
	%BodyMesh.position.y = height * 0.5


func _apply_presentation() -> void:
	rotation.y = body_yaw
	# Knocked flat, the head lies back with the body and stares at the sky.
	var fallen := float(get_node("Visual/CartoonBody").get("fallen")) if has_node("Visual/CartoonBody") else 0.0
	%Head.rotation.x = lerpf(head_pitch, 0.0, fallen) + fallen * 1.35
	# Lying on a cot the eyes look up at the tarp, and the mouse still turns them
	# (down toward your feet, back over the pillow).
	var lying := float(get_node("Visual/CartoonBody").get("lie")) if has_node("Visual/CartoonBody") else 0.0
	if lying > 0.0 and fallen <= 0.01:
		var resting := smoothstep(0.0, 1.0, lying)
		var pitch := lerpf(head_pitch, clampf(Constants.SLEEP_LIE_ANGLE + head_pitch * Constants.SLEEP_LOOK_SHARE, Constants.SLEEP_HEAD_PITCH_MIN, Constants.SLEEP_HEAD_PITCH_MAX), resting)
		%Head.rotation.x = pitch
		# Your own head rolls on the pillow toward your shoulder (about the
		# spine, which lies along the body's +Z), eased in and out with the pose.
		if is_multiplayer_authority() and (_sleep_look != 0.0 or _sleep_head_turned):
			%Head.basis = Basis(Vector3.BACK, _sleep_look * resting) * Basis(Vector3.RIGHT, pitch)
			_sleep_head_turned = _sleep_look != 0.0
	elif _sleep_head_turned:
		_sleep_head_turned = false
		_sleep_look = 0.0
		%Head.rotation.y = 0.0
		%Head.rotation.z = 0.0
	# Some jumps get a little "hup". anim_state and velocity replicate, so everyone hears it.
	if anim_state == AnimState.AIR and _last_anim != AnimState.AIR and velocity.y > 1.0 and randf() < HUP_CHANCE:
		say("vo_hup")
	_last_anim = anim_state


## Swap the gray-box capsule for a cartoon person (player/cartoon_body.gd). Looks
## come from the player's name, so a friend looks the same every session.
func _dress_up() -> void:
	if $Visual.has_node("CartoonBody"):
		return
	var shown := Net.player_name(name.to_int())
	# A body that spawns on a client before the session's names reach it waits
	# for its name (_on_player_joined), or that client dresses it by peer id and
	# everyone else by name: two looks for one person (the host's outfit at the
	# Annex in 0.4.5). A short ceiling, so nobody stays a capsule if it never comes.
	if shown == "" and not _dress_waited:
		_dress_waited = true
		get_tree().create_timer(Constants.DRESS_NAME_WAIT_SECONDS).timeout.connect(_dress_up)
		return
	var body := _CartoonBody.new()
	body.name = "CartoonBody"
	_dress_seed = hash(shown) if shown != "" else name.to_int()
	body.dress_from_seed(_dress_seed)
	# What they bought over what their name gives them (shops chunk 7): their
	# hat and shirt, from World/Shops' replicated looks.
	var shops := get_tree().get_first_node_in_group("shops")
	if shops != null:
		_Hats.wear(body, shops.call("look_of", name.to_int()))
		if not shops.is_connected("looks_changed", _on_looks_changed):
			shops.connect("looks_changed", _on_looks_changed)
	_dressed_msec = Time.get_ticks_msec()
	$Visual.add_child(body)
	body.build(%Head, is_multiplayer_authority())
	var life := _CharacterLife.new()
	life.name = "Life"
	life.root = self
	life.body = body
	life.role = "player"
	body.add_child(life)
	# Eating a snack and wearing what it does (Lunch Money, the Snak-o-Matic),
	# after the body each tick; every peer, from World/Shops' snapshot.
	var eater := _SnackEater.new()
	eater.name = "SnackEater"
	eater.player = self
	eater.body = body
	body.add_child(eater)
	# What this body sounds like (its footsteps, splats, thumps), on every peer.
	var foley := _PlayerFoley.new()
	foley.name = "Foley"
	foley.player = self
	foley.body = body
	body.add_child(foley)
	%BodyMesh.visible = false
	var old_head := %Head.get_node_or_null("HeadMesh") as Node3D
	if old_head != null:
		old_head.visible = false
	# Other players' cameras are never used here, and their Visual is moved by the
	# network smoother outside physics ticks, which interpolation warns about.
	if not is_multiplayer_authority():
		for camera: Camera3D in [%FirstPerson, get_node_or_null("CameraRig/OverShoulder")]:
			if camera != null:
				camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Your own eyes would sit right in front of your first-person camera.
	if is_multiplayer_authority():
		%FirstPerson.cull_mask &= ~(1 << (_CartoonBody.HEAD_LAYER - 1))
		# And in its place, your own arms, reaching for whatever you're doing.
		if not Net.is_automated() and DisplayServer.get_name() != "headless":
			var arms := _FirstPersonArms.new()
			arms.name = "Arms"
			%Head.add_child(arms)
			arms.setup(self, body, %FirstPerson)


## Someone's look changed (World/Shops looks_changed, every peer; shops chunk 7):
## if it's this player, the body puts on the new hat and shirt in place
## (CartoonBody.rebuild keeps the pivots, the arms' holds and everything hung on
## it) and, for your own, the first-person sleeves follow the shirt. A body only
## just dressed (a late joiner's first snapshot) changes without the show.
func _on_looks_changed(peer_id: int) -> void:
	if peer_id != name.to_int():
		return
	var body := $Visual.get_node_or_null("CartoonBody")
	var shops := get_tree().get_first_node_in_group("shops")
	if body == null or shops == null:
		return
	body.call("dress_from_seed", _dress_seed)
	_Hats.wear(body, shops.call("look_of", peer_id))
	var animate := Time.get_ticks_msec() - _dressed_msec > int(Constants.DRESS_ANIMATE_AFTER_SECONDS * 1000.0) \
		and not bool(shops.get("first_snapshot"))
	body.call("rebuild", %Head, is_multiplayer_authority(), animate)
	var arms := %Head.get_node_or_null("Arms")
	if arms != null and arms.has_method("recolor"):
		arms.call("recolor", body.get("shirt"))


## A silly character noise (docs/ART.md, "Audio") from this player's head, in
## their own voice. Cosmetic and local: each peer plays it for itself.
## A sound that isn't a voice (audio/sound_bank.gd says, like Chefty's horn) plays
## from the head through Sfx instead, riding along with it, with no mouth moving.
func say(sound_name: String) -> void:
	var bank := preload("res://audio/sound_bank.gd")
	if bank.has(sound_name) and not bank.is_voice(sound_name):
		var sfx := get_tree().get_first_node_in_group("sfx")
		if sfx != null:
			sfx.call("play_on", sound_name, %Head, 0.0, true, name.to_int())
		return
	if Net.is_automated():
		return
	var paths := bank.files(sound_name)
	var path := paths[randi_range(0, paths.size() - 1)]
	var stream := load(path) as AudioStream if ResourceLoader.exists(path) else null
	if stream == null:
		return
	var mouth := get_node_or_null("Visual/Head/Mouth") as AudioStreamPlayer3D
	if mouth == null:
		mouth = AudioStreamPlayer3D.new()
		mouth.name = "Mouth"
		mouth.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		mouth.unit_size = Constants.VOICE_CLEAR_DISTANCE * 1.5
		mouth.max_distance = Constants.VOICE_MAX_DISTANCE
		$Visual/Head.add_child(mouth)
	mouth.bus = preload("res://audio/sound_bank.gd").bus(sound_name)
	mouth.stream = stream
	mouth.pitch_scale = _voice_pitch() * randf_range(0.96, 1.04)
	mouth.play()
	var body := $Visual.get_node_or_null("CartoonBody")
	if body != null:
		body.call("talk", stream.get_length() / mouth.pitch_scale)


## Each character's voice sits a little higher or lower, so you can tell who yelped.
func _voice_pitch() -> float:
	return 0.85 + float(absi(hash(name)) % 7) * 0.05


func _refresh_name() -> void:
	var shown := Net.player_name(name.to_int())
	if shown == "":
		return
	var speaking := Net.is_player_speaking(name.to_int())
	%Nameplate.text = _Strings.UI["speaking_nameplate"] % shown if speaking else shown
	%Nameplate.modulate = SPEAKING_TINT if speaking else Color.WHITE


func _on_player_joined(peer_id: int) -> void:
	if peer_id == name.to_int():
		_refresh_name()
		_dress_up()


func _on_speaking_changed(peer_id: int, _is_speaking: bool) -> void:
	if peer_id == name.to_int():
		_refresh_name()


func _exit_tree() -> void:
	# A voice generator still playing when it is freed outlives the engine at quit.
	# A plain path: unique names can't be resolved while the node leaves the tree.
	var voice := get_node_or_null("Visual/Head/Voice") as AudioStreamPlayer3D
	if voice != null:
		voice.stop()
		voice.stream = null


## Remote players speak through their head, so distance does the mixing.
func _attach_voice() -> void:
	# _ready runs again if the node re-enters the tree. Keep one voice player.
	if %Head.get_node_or_null("Voice") != null:
		return
	var voice := AudioStreamPlayer3D.new()
	voice.name = "Voice"
	voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	voice.unit_size = Constants.VOICE_CLEAR_DISTANCE
	voice.max_distance = Constants.VOICE_MAX_DISTANCE
	voice.bus = preload("res://audio/buses.gd").VOICE
	%Head.add_child(voice)
	Net.attach_voice_output(name.to_int(), voice)


# ---- p1-arrive: stepping off a seat, and room to stand (docs/GAME.md "Stepping
# off Chefty"). Both are the owner's own movement, so every peer sees them through
# the synchronizer like any walk: nothing staged, no RPC per frame.
## The hop off a seat: from and to (world), how far along (0..1; -1 when not
## stepping), and how much of the turn to the landing's facing is done (radians).
var _step_from := Transform3D()
var _step_to := Transform3D()
var _step_t: float = -1.0
var _step_turned: float = 0.0
## Seconds before this rider's hop starts (riders get off one after another).
var _hop_wait: float = 0.0
## How the hop clears the vehicle (step_down.gd hop_path; step_down_point).
var _step_path := Vector4.ZERO
## hop_timing for this hop: [crouch share, landing starts, seconds, top, top at].
var _step_timing := hop_timing(0.0, 0.0)
## A legacy ride's seat yaw last tick (NAN: just sat down, so face the seat's way).
var _ride_seat_yaw: float = NAN
## Room to stand: the host's last nudge (m/s, flat) and how long it still lasts.
var _nudge := Vector3.ZERO
var _nudge_left: float = 0.0


## Owner: off whatever you're on, down onto at: the knees bend, a hop over the
## rail (or out of the door) and a landing, turning to at's facing on the way,
## from exactly where you are now, so it never pops on any screen. Further than
## STEP_DOWN_MAX_METERS is a teleport instead.
func step_down_to(at: Transform3D, wait: float = 0.0, path := Vector4.ZERO) -> void:
	if not is_multiplayer_authority():
		return
	if global_position.distance_to(at.origin) > Constants.STEP_DOWN_MAX_METERS:
		apply_network_teleport(at)
		return
	_step_from = Transform3D(Basis(Vector3.UP, body_yaw), global_position)
	_step_to = at
	_step_path = path
	_step_timing = hop_timing(_step_from.origin.y, at.origin.y, path)
	_step_t = 0.0
	_hop_wait = maxf(wait, 0.0)
	_step_turned = 0.0
	_nudge_left = 0.0
	velocity = Vector3.ZERO


## Owner: mid-hop off a seat (step_down_to).
func is_stepping_down() -> bool:
	return _step_t >= 0.0


## How the hop goes, from the seat's height (from_y) to the ground's (to_y):
## [the share of it the knees bend first, where the landing starts (0..1), how
## long it all takes (s), the top of the jump (world height), where along the
## flight (0..1) it's at the top]. Over a rail or the tailgate (path, step_down.gd
## hop_path) it's a jump like a thrown thing's, under STEP_DOWN_GRAVITY: up to a
## top high enough that the feet are over the wall all the way across it, and
## the flight takes as long as rising and falling that far does (review,
## p1-arrive: a curve forced over the 1.65 m rail in the old time came down at
## 11 m/s). Otherwise (the cab's door, a flat step) there's no top (0) and
## step_down_point curves as before.
static func hop_timing(from_y: float, to_y: float, path := Vector4.ZERO) -> PackedFloat32Array:
	var base := Constants.STEP_DOWN_SECONDS
	var crouch_s := base * Constants.STEP_DOWN_CROUCH_SHARE
	var land_s := base * Constants.STEP_DOWN_LAND_SHARE
	var flight := base - crouch_s - land_s
	var apex := 0.0
	var top_at := 0.5
	if path.y > path.x and path.w <= 0.0:
		var start_y := from_y - Constants.STEP_DOWN_CROUCH
		var gravity := Constants.STEP_DOWN_GRAVITY
		apex = maxf(maxf(start_y, to_y) + Constants.STEP_DOWN_MIN_RISE, path.z)
		var samples := maxi(Constants.STEP_DOWN_WALL_SAMPLES, 2)
		for _pass: int in 4:
			var rise := sqrt(2.0 * maxf(apex - start_y, 0.0) / gravity)
			var fall := sqrt(2.0 * maxf(apex - to_y, 0.0) / gravity)
			top_at = rise / maxf(rise + fall, 0.001)
			var need := apex
			for index: int in samples:
				var u := lerpf(path.x, path.y, float(index) / float(samples - 1))
				var low := start_y if u <= top_at else to_y
				var r := (top_at - u) / maxf(top_at, 0.001) if u <= top_at else (u - top_at) / maxf(1.0 - top_at, 0.001)
				if r * r < 0.98:
					need = maxf(need, (path.z - low * r * r) / (1.0 - r * r))
			apex = need
		var rise := sqrt(2.0 * maxf(apex - start_y, 0.0) / gravity)
		var fall := sqrt(2.0 * maxf(apex - to_y, 0.0) / gravity)
		top_at = rise / maxf(rise + fall, 0.001)
		flight = maxf(flight, rise + fall)
	var seconds := crouch_s + flight + land_s
	return PackedFloat32Array([crouch_s / seconds, (crouch_s + flight) / seconds, seconds, apex, top_at])


## Where the hop has the body at k (0..1; timing from hop_timing): still while the
## knees bend, then the jump from the crouch to the ground, then the knees take
## the landing in place. path (step_down.gd hop_path): over the bed's rail or
## tailgate it's hop_timing's jump; out of a cab seat (w > 0) you slide out
## through the door at the seat's height and drop off the sill at w.
static func step_down_point(from: Vector3, to: Vector3, k: float, path := Vector4.ZERO, timing := PackedFloat32Array()) -> Vector3:
	if timing.size() < 5:
		timing = hop_timing(from.y, to.y, path)
	var crouch := timing[0]
	var land := timing[1]
	var door := path.w
	# Sitting, there are no knees to bend first.
	var dip := 0.0 if door > 0.0 else Constants.STEP_DOWN_CROUCH
	if k <= crouch:
		return from + Vector3.DOWN * dip * sin(k / crouch * PI * 0.5)
	if k >= land:
		return to
	var u := (k - crouch) / (land - crouch)
	var start := from + Vector3.DOWN * dip
	var at := start.lerp(to, u)
	if door > 0.0:
		# Out of the door at the bench's height, then down off the sill, falling.
		var v := clampf((u - door) / maxf(1.0 - door, 0.001), 0.0, 1.0)
		at.y = lerpf(start.y, to.y, v * v)
		return at
	if path.y > path.x:
		var apex := timing[3]
		# Up to the top, slowing, then falling to the ground (a parabola each side).
		var top_at := timing[4]
		if u <= top_at:
			var r := (top_at - u) / maxf(top_at, 0.001)
			at.y = apex - (apex - start.y) * r * r
		else:
			var r := (u - top_at) / maxf(1.0 - top_at, 0.001)
			at.y = apex - (apex - to.y) * r * r
		return at
	# Up off the knees and down: a curve through a point STEP_DOWN_HOP x 2 over the
	# higher end; out of a low seat it's barely a hop, more a step out.
	var drop := clampf(absf(start.y - to.y), Constants.STEP_DOWN_DROP_RANGE.x, Constants.STEP_DOWN_DROP_RANGE.y)
	var over := maxf(start.y, to.y) + Constants.STEP_DOWN_HOP * 2.0 * drop * drop
	at.y = (1.0 - u) * (1.0 - u) * start.y + 2.0 * u * (1.0 - u) * over + u * u * to.y
	return at


## Owner, each physics tick: seat_state, for the other peers.
func _note_seat_state() -> void:
	if _on_seat or (is_stepping_down() and _hop_wait > 0.0):
		seat_state = SEAT_STATE_SEATED
	else:
		seat_state = SEAT_STATE_SLIDING if _step_sitting() else 0


## Owner, mid-hop out of a cab seat: still sitting until you're out of the door,
## so the eyes stay under the cab's roof (cartoon_body sit()).
func _step_sitting() -> bool:
	if not is_stepping_down() or _step_path.w <= 0.0 or _step_timing.size() < 5:
		return false
	var crouch := _step_timing[0]
	var land := _step_timing[1]
	return _hop_wait > 0.0 or (_step_t - crouch) / (land - crouch) < _step_path.w


func _step_down(delta: float) -> void:
	if carried_by != 0 or thrown:
		_step_t = -1.0
		return
	velocity = Vector3.ZERO
	# Your turn yet (the crew gets off one after another, by seat)?
	if _hop_wait > 0.0:
		_hop_wait -= delta
		anim_state = AnimState.IDLE
		_step_from.origin = global_position
		_step_timing = hop_timing(_step_from.origin.y, _step_to.origin.y, _step_path)
		return
	var before := global_position
	_step_t = minf(_step_t + delta / maxf(_step_timing[2], 0.01), 1.0)
	var k := _step_t
	global_position = step_down_point(_step_from.origin, _step_to.origin, k, _step_path, _step_timing)
	# The turn to the landing's facing, on top of any looking around meanwhile.
	var total := angle_difference(_step_from.basis.get_euler().y, _step_to.basis.get_euler().y)
	var turned := total * smoothstep(0.0, 1.0, minf(k / Constants.STEP_DOWN_TURN_DONE, 1.0))
	body_yaw += turned - _step_turned
	_step_turned = turned
	# What the body does (every peer draws it from anim_state and velocity): the
	# knees bend, it flies, the knees take the landing, it stands.
	var crouch := _step_timing[0]
	var land := _step_timing[1]
	if k < crouch or (k >= land and k < land + (1.0 - land) * Constants.STEP_DOWN_LAND_CROUCH):
		anim_state = AnimState.CROUCH
	elif k < land:
		anim_state = AnimState.AIR
	else:
		anim_state = AnimState.IDLE
	velocity = (global_position - before) / maxf(delta, 0.0001)
	velocity.y = maxf(velocity.y, -Constants.STEP_DOWN_MAX_FALL)
	if _step_t >= 1.0:
		_step_t = -1.0
		velocity = Vector3.ZERO
		_fall_peak = global_position.y
		_airborne = false


## Owner, a legacy ride: you start facing the way your seat does (out over the
## side), and turn with the truck from there; looking around still turns you.
func _follow_seat_yaw(seat: Transform3D) -> void:
	var yaw := seat.basis.orthonormalized().get_euler().y
	if is_nan(_ride_seat_yaw):
		# fx-chefty: you turn to the seat's way over the climb in, not in a frame
		# (the view swung 84 degrees in one, play: rec_board_fr frame 72).
		_seat_turn_left = angle_difference(body_yaw, yaw)
		_seat_turn_rate = absf(_seat_turn_left) / maxf(Constants.CHEFTY_BOARD_TURN_SECONDS, 0.01)
	else:
		body_yaw += angle_difference(_ride_seat_yaw, yaw)
	if _seat_turn_left != 0.0:
		var step := signf(_seat_turn_left) * minf(absf(_seat_turn_left), _seat_turn_rate * get_physics_process_delta_time())
		body_yaw += step
		_seat_turn_left -= step
	_ride_seat_yaw = yaw


## A legacy seat's turn to its facing still to come (radians), and how fast it goes.
var _seat_turn_left: float = 0.0
var _seat_turn_rate: float = 0.0


## Another peer's view of a rider: while seated the Visual is top_level, so the
## body's replicated pose landing mid-frame (it trails the seat by the link's
## delay) can't drag the drawn rider off the seat. At the drop-off that drag drew
## a rider up to 5 m past the truck for a frame, then pulled them back (play and
## --arrive-test, p1-arrive). Off the seat, the smoother carries on from exactly
## where they're drawn (net_smoother.gd resume_from_drawn).
func _pin_visual(on: bool) -> void:
	var visual := get_node_or_null("Visual") as Node3D
	if visual == null or visual.top_level == on:
		return
	var drawn := visual.global_transform
	visual.top_level = on
	visual.global_transform = drawn
	if not on:
		var smoother := get_node_or_null("NetSmoother")
		if smoother != null and smoother.has_method("resume_from_drawn"):
			smoother.call("resume_from_drawn")


## Owner (personal_space.gd through send_nudge): slide along push for a moment.
func nudge(push: Vector3) -> void:
	if not is_multiplayer_authority() or is_stepping_down():
		return
	_nudge = Vector3(push.x, 0.0, push.z)
	_nudge_left = Constants.PERSONAL_SPACE_NUDGE_SECONDS


## _simulate: a nudge adds to whatever the player's own keys do, and walls still stop it.
func _apply_nudge(delta: float) -> void:
	if _nudge_left <= 0.0:
		return
	_nudge_left -= delta
	velocity.x += _nudge.x
	velocity.z += _nudge.z
