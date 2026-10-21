extends CharacterBody3D

## Authority: owning peer for movement, look, and the values replicated below.
## Remote peers display those values. NetSmoother only moves the visual on remotes.

enum AnimState { IDLE, WALK, SPRINT, CROUCH, AIR, KNOCKED }

# TODO(balance): add movement speeds to the workbook.
const WALK_SPEED: float = 5.0
const SPRINT_SPEED: float = 8.0
const CROUCH_SPEED: float = 2.5
const JUMP_VELOCITY: float = 4.5
const MOUSE_SENSITIVITY: float = 0.003
const _WaterSources = preload("res://net/work/water_sources.gd")
const STAND_HEIGHT: float = 1.8
const CROUCH_HEIGHT: float = 1.1
const PITCH_LIMIT: float = 1.2
## Nameplate color while that player is talking.
const SPEAKING_TINT := Color(1.0, 0.86, 0.35)
const _Strings = preload("res://ui/strings.gd")
const _CartoonBody = preload("res://player/cartoon_body.gd")
const _CharacterLife = preload("res://player/character_life.gd")
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
@export var equipment_id: String = ""

var _look := Vector2.ZERO
var _ride: Node3D
var _seat_index: int = -1
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _throwback_left: float = 0.0
var _throwback_from: Vector3 = Vector3.ZERO
var _throwback_to: Vector3 = Vector3.ZERO
var _crossing_bounded: bool = false
var _crossing_drive: bool = false
## Hiding spot this player is inside, set by the host through net/components/hide_spot.gd.
var _hidden_spot: Node3D
var _last_anim: AnimState = AnimState.IDLE
var _on_seat: bool = false
var _crossing_min: Vector3 = Vector3.ZERO
var _crossing_max: Vector3 = Vector3.ZERO
var _step_wait: float = 0.0
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
var _next_strain: float = 0.0


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
	_dress_up()
	_apply_presentation()


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event.is_action_pressed("toggle_camera"):
		%CameraRig.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and _water_hookup():
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and _toggle_climb():
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("take") and _take_ladder():
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("jump") and _ladder != null:
		_climb_target = 0.0
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and _toggle_hiding():
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and _load_truck():
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and _hand_task():
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and _grab_nearby():
		get_viewport().set_input_as_handled()
	# G (drop) is wound up and released in _wind_up, on physics ticks.
		get_viewport().set_input_as_handled()
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
		_step_wind_up(delta)
		if _crossing_drive:
			_look = Vector2.ZERO
			body_yaw = PI
		else:
			_apply_look()
		if _hidden_spot != null:
			velocity = Vector3.ZERO
		elif _throwback_left > 0.0:
			_step_throwback(delta)
		elif _ladder != null:
			_step_climb(delta)
		elif _stun_left > 0.0 and _ride == null:
			_step_stunned(delta)
		elif _ride != null and _seat_index >= 0 and _ride.has_method("seat_transform"):
			var seat: Transform3D = _ride.call("seat_transform", _seat_index)
			global_position = seat.origin
		elif not _step_hydrant(delta):
			_simulate(delta)
		_track_fall(delta)
	_apply_presentation()


## Follow a seat until the ride arrives. Movement stays off; looking still works.
## While riding, every peer puts this player on their seat each physics tick,
## right after the vehicle moves (process_physics_priority in _enter_tree), and
## physics interpolation smooths both the same way. Going through the network
## smoother's delay instead made riders slide back and forth against the vehicle.
func _seat_on_ride() -> void:
	var seat := _current_seat()
	var was_on_seat := _on_seat
	_on_seat = seat != Transform3D()
	if was_on_seat != _on_seat:
		reset_physics_interpolation()
	if not _on_seat:
		return
	if is_multiplayer_authority():
		global_position = seat.origin
		velocity = Vector3.ZERO
	$Visual.global_transform = Transform3D(global_basis, seat.origin)


## For net/components/net_smoother.gd: while true, the smoother leaves the visual alone.
func is_riding_visual() -> bool:
	return _on_seat


func _current_seat() -> Transform3D:
	var peer_id := name.to_int()
	for ride: Node in get_tree().get_nodes_in_group("rides"):
		var index := int(ride.call("seat_of", peer_id))
		if index >= 0:
			return ride.call("seat_transform", index)
	return Transform3D()


func set_riding(ride: Node3D, seat_index: int) -> void:
	_ride = ride
	_seat_index = seat_index
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


## Called on every peer by the host's hide spot. Null means this player came out.
func set_hidden_in(spot: Node3D) -> void:
	var leaving := _hidden_spot
	_hidden_spot = spot
	$Visual.visible = spot == null
	%Collision.disabled = spot != null
	if not is_multiplayer_authority():
		return
	velocity = Vector3.ZERO
	if spot != null:
		_release_held(false)
		global_position = spot.global_position + Vector3(0.0, 0.1, 0.0)
	elif leaving != null and leaving.has_method("exit_position"):
		global_position = leaving.call("exit_position")
	reset_physics_interpolation()


func is_hidden() -> bool:
	return _hidden_spot != null


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
	if _held_prop() != null:
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
	if _ladder != null or _on_seat or _hidden_spot != null:
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
	_climb = move_toward(_climb, _climb_target, delta / Constants.LADDER_CLIMB_SECONDS)
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
	if _held_prop() != null:
		return {}
	var tasks := get_tree().get_first_node_in_group("job_tasks")
	if tasks == null:
		return {}
	for task: String in ["pick_litter", "pull_weeds"]:
		var index := int(tasks.call("nearest_spot", task, global_position, float(Constants.TASK_REACH[task])))
		if index >= 0:
			return {"task": task, "at": (tasks.call("spot", index) as Dictionary)["at"]}
	return {}


## E by Chefty with a bag tosses it in; with a loaded wheelbarrow, dumps it.
func _load_truck() -> bool:
	var held := _held_prop()
	if held == null or not bool(held.call("near_truck")):
		return false
	var held_kind := str(held.get("kind"))
	if held_kind != "leaf_bag" and not (held_kind == "wheelbarrow" and int(held.get("stored_bags")) > 0):
		return false
	held.call("request_load_truck")
	return true


## E inside a hiding spot comes out. E next to a free one asks the host to get in.
func _toggle_hiding() -> bool:
	if _hidden_spot != null:
		_hidden_spot.call("request_exit")
		return true
	var closest := _nearest_free_spot()
	if closest == null:
		return false
	closest.call("request_enter")
	return true


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


## Host-ordered teleport. Runs on the owning peer only.
func apply_network_teleport(at: Transform3D) -> void:
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
	# One thing at a time.
	if held != null:
		return false
	var closest: Node = null
	var closest_distance := 2.4
	for node: Node in get_tree().get_nodes_in_group("props"):
		if not node is Node3D:
			continue
		var distance := global_position.distance_to((node as Node3D).global_position)
		if distance < closest_distance:
			closest = node
			closest_distance = distance
	if closest == null:
		return false
	closest.call("request_grab")
	return true


## What E would do right now, for the prompt in ui/interaction_prompt.gd, in the
## same order _unhandled_input tries them. Empty when E does nothing here.
func interaction_hint() -> Dictionary:
	if _hidden_spot != null:
		return {"text": _Strings.UI["prompt_unhide"], "at": _hidden_spot.global_position + Vector3(0.0, 2.2, 0.0)}
	var paint_held := _held_prop()
	if paint_held != null and str(paint_held.get("kind")) == "paint_roller" and _nearest_bucket() != null:
		return {"text": _Strings.UI["prompt_dip"], "at": _nearest_bucket().global_position + Vector3(0.0, 0.6, 0.0)}
	var water_held := _held_prop()
	if water_held != null and (str(water_held.get("kind")) == "hose" or str(water_held.get("kind")) == "pressure_washer"):
		var source := _WaterSources.nearest(get_tree(), global_position, Constants.WATER_REACH)
		if source != null:
			var key := "prompt_refill"
			if str(water_held.get("kind")) == "hose":
				key = "prompt_unhook" if str(water_held.get("hose_source")) == str(source.get_meta("kind")) else "prompt_hook_" + str(source.get_meta("kind"))
			return {"text": _Strings.UI[key], "at": source.global_position + Vector3(0.0, 0.9, 0.0)}
	if _ladder != null:
		return {"text": _Strings.UI["prompt_climb_down"], "at": global_position + Vector3(0.0, 2.2, 0.0) - global_basis.z * 0.6}
	var ladder := _nearest_ladder()
	if ladder != null and _held_prop() == null or (ladder != null and str(_held_prop().get("kind")) == "leaf_blower"):
		return {"text": _Strings.UI["prompt_climb_up"], "at": ladder.global_position + Vector3(0.0, 1.8, 0.0)}
	var ladder_top := _nearest_ladder_top()
	if ladder_top != null:
		return {"text": _Strings.UI["prompt_climb_down"], "at": (ladder_top.get("ladder_top") as Vector3) + Vector3(0.0, 0.8, 0.0)}
	var spot := _nearest_free_spot()
	if spot != null:
		return {"text": _Strings.UI["prompt_hide"], "at": spot.global_position + Vector3(0.0, 2.2, 0.0)}
	var hand := _nearest_hand_task()
	if not hand.is_empty():
		var key := "prompt_pick_litter" if hand["task"] == "pick_litter" else "prompt_pull_weed"
		return {"text": _Strings.UI[key], "at": (hand["at"] as Vector3) + Vector3(0.0, 0.6, 0.0)}
	var held := _held_prop()
	if held != null and bool(held.call("near_truck")):
		var held_kind := str(held.get("kind"))
		if held_kind == "leaf_bag":
			return {"text": _Strings.UI["prompt_toss_truck"], "at": held.global_position + Vector3(0.0, 0.8, 0.0)}
		if held_kind == "wheelbarrow" and int(held.get("stored_bags")) > 0:
			return {"text": _Strings.UI["prompt_dump_truck"], "at": held.global_position + Vector3(0.0, 1.0, 0.0)}
	if held != null and str(held.get("kind")) == "leaf_bag":
		var barrow := _nearest_kind("wheelbarrow", 2.4) as Node3D
		if barrow != null:
			return {"text": _Strings.UI["prompt_load_bag"], "at": barrow.global_position + Vector3(0.0, 1.4, 0.0)}
	if held != null:
		return {}
	var closest: Node3D = null
	var closest_distance := 2.4
	for node: Node in get_tree().get_nodes_in_group("props"):
		var prop := node as Node3D
		if prop == null or int(prop.get("held_by")) != 0:
			continue
		var distance := global_position.distance_to(prop.global_position)
		if distance < closest_distance:
			closest = prop
			closest_distance = distance
	if closest == null:
		return {}
	var prop_label := str(closest.get("label"))
	var text: String = _Strings.UI["prompt_pick_up"] % prop_label if prop_label != "" else _Strings.UI["prompt_pick_up_plain"]
	return {"text": text, "at": closest.global_position + Vector3(0.0, 1.2, 0.0)}


func _nearest_free_spot() -> Node3D:
	var closest: Node3D = null
	var closest_distance := Constants.HIDE_REACH
	for node: Node in get_tree().get_nodes_in_group("hide_spots"):
		var spot := node as Node3D
		if spot == null or int(spot.get("occupant")) != 0:
			continue
		var distance := spot.global_position.distance_to(global_position)
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


func _apply_look() -> void:
	body_yaw -= _look.x * MOUSE_SENSITIVITY
	head_pitch = clampf(head_pitch - _look.y * MOUSE_SENSITIVITY, -PITCH_LIMIT, PITCH_LIMIT)
	_look = Vector2.ZERO


func _simulate(delta: float) -> void:
	var crouching := Input.is_action_pressed("crouch")
	_apply_stance(crouching)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump") and not crouching:
		velocity.y = JUMP_VELOCITY
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := Vector3.ZERO
	if _crossing_drive:
		# The border camera looks toward the exit. W moves that way, A and D step across the lane.
		direction = Vector3(input_dir.x, 0.0, -input_dir.y)
		if direction.length() > 0.001:
			direction = direction.normalized()
	else:
		direction = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var speed := WALK_SPEED
	if crouching:
		speed = CROUCH_SPEED
	elif Input.is_action_pressed("sprint"):
		speed = SPRINT_SPEED
	speed *= carry_speed_scale()
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
	move_and_slide()
	_update_anim(crouching, direction)
	_stay_on_the_pad()
	_steps(delta)


## How far the throw is wound up, 0 to 1, or -1 when G isn't held. Past 1 is
## straining (ui/throw_meter.gd draws it).
func wind_up_share() -> float:
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
	var pressing := Input.is_action_pressed("drop") and held != null and _stun_left <= 0.0 and _hidden_spot == null
	if pressing:
		if _wind_up < 0.0:
			_wind_up = 0.0
			_next_strain = Constants.THROW_STRAIN_SECONDS
		_wind_up += delta
		straining = _wind_up >= Constants.THROW_STRAIN_SECONDS
		if straining:
			if _wind_up >= _next_strain:
				_next_strain = _wind_up + 1.3
				say_to_all("vo_strain")
		if _wind_up >= Constants.THROW_FAINT_SECONDS:
			_faint()
		return
	if _wind_up < 0.0:
		return
	var seconds := _wind_up
	_wind_up = -1.0
	straining = false
	var body := get_node_or_null("Visual/CartoonBody")
	if held == null:
		return
	if seconds < Constants.THROW_TAP_SECONDS:
		_release_held(false)
		return
	var share := clampf(seconds / Constants.THROW_CHARGE_SECONDS, 0.0, 1.0)
	var power := lerpf(Constants.THROW_POWER_MIN, Constants.THROW_POWER_MAX, share)
	held.call("request_throw", -global_transform.basis.z, power)
	say_to_all("vo_heave" if share > 0.7 else "vo_hup")
	if body != null and not bool(body.call("is_gesturing")):
		body.call("gesture", "startle")


## Held it up too long: the world spins, you drop it and go down for a moment.
func _faint() -> void:
	_wind_up = -1.0
	straining = false
	_release_held(false)
	_stun_left = Constants.FAINT_SECONDS
	_knocked = true
	say_to_all("vo_oof")


## A noise from this player that every peer hears from their head.
func say_to_all(sound_name: String) -> void:
	_rpc_say.rpc(sound_name)


@rpc("authority", "call_local", "unreliable")
func _rpc_say(sound_name: String) -> void:
	say(sound_name)


## Heavy things slow you down while you carry them (Constants.CARRY_SLOWDOWN_PER_KG).
func carry_speed_scale() -> float:
	var held := _held_prop()
	if held == null or not held.has_method("weight_kg"):
		return 1.0
	var kg := float(held.call("weight_kg"))
	if Constants.ROLLING_KINDS.has(str(held.get("kind"))):
		kg *= Constants.ROLLING_WEIGHT_SHARE
	return maxf(Constants.CARRY_SPEED_FLOOR, 1.0 - kg * Constants.CARRY_SLOWDOWN_PER_KG)


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
				body.call("dizzy", float(Constants.BONK_STUN_SECONDS["heavy"]))
	say("vo_oof" if tier != "light" else "vo_eh")
	if not is_multiplayer_authority() or _hidden_spot != null or _on_seat:
		return
	_stun_left = float(Constants.BONK_STUN_SECONDS.get(tier, 0.5))
	_knocked = tier == "heavy"
	velocity = push
	if _knocked and _held_prop() != null:
		_release_held(false)


## Stunned: sliding with the shove, no control, flat on your back if knocked.
func _step_stunned(delta: float) -> void:
	_stun_left = maxf(0.0, _stun_left - delta)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	var flat := Vector2(velocity.x, velocity.z).move_toward(Vector2.ZERO, (9.0 if is_on_floor() else 1.5) * delta)
	velocity.x = flat.x
	velocity.z = flat.y
	move_and_slide()
	anim_state = AnimState.KNOCKED if _knocked else (AnimState.AIR if not is_on_floor() else AnimState.IDLE)
	if _stun_left <= 0.0:
		_knocked = false


## A thrown prop can spike velocity. Cap it, and put the player back if they leave the pad.
func _stay_on_the_pad() -> void:
	var flat := Vector2(velocity.x, velocity.z)
	if flat.length() > SPRINT_SPEED:
		flat = flat.normalized() * SPRINT_SPEED
		velocity.x = flat.x
		velocity.z = flat.y
	if velocity.y > JUMP_VELOCITY:
		velocity.y = JUMP_VELOCITY
	var world := get_tree().get_first_node_in_group("world") as Node3D
	if world == null:
		return
	var zone := Net.player_zone(name.to_int())
	var pad := _pad_for_zone(world, zone)
	if pad == null:
		return
	if _crossing_bounded:
		global_position.x = clampf(global_position.x, _crossing_min.x, _crossing_max.x)
		global_position.z = clampf(global_position.z, _crossing_min.z, _crossing_max.z)
	var offset := global_position - pad.global_position
	var rect: Rect2 = Constants.PAD_RECTS.get(String(pad.name), Rect2(-20.0, -20.0, 40.0, 40.0))
	var past_edge := not rect.grow(1.0).has_point(Vector2(offset.x, offset.z))
	if not past_edge and global_position.y >= -2.0:
		return
	var at: Transform3D = world.call("get_spawn_transform", zone, &"", name.to_int())
	global_position = at.origin
	velocity = Vector3.ZERO


func is_throwing_back() -> bool:
	return _throwback_left > 0.0


## Comic toss back to the start of the lane. The owning player plays it immediately.
func play_throwback(to: Vector3) -> void:
	if _throwback_left > 0.0:
		return
	_throwback_from = global_position
	_throwback_to = to
	say("vo_oof")
	_throwback_left = Constants.BORDER_THROWBACK_SECONDS
	velocity = Vector3.ZERO


func set_crossing_view(active: bool) -> void:
	_crossing_drive = active
	if not active:
		_crossing_bounded = false
	if is_multiplayer_authority():
		%CameraRig.set_active(not active)


func set_crossing_bounds(enabled: bool, min_corner: Vector3, max_corner: Vector3) -> void:
	_crossing_bounded = enabled
	_crossing_min = min_corner
	_crossing_max = max_corner


func _step_throwback(delta: float) -> void:
	_throwback_left = maxf(_throwback_left - delta, 0.0)
	var t := 1.0 - clampf(_throwback_left / Constants.BORDER_THROWBACK_SECONDS, 0.0, 1.0)
	var pos := _throwback_from.lerp(_throwback_to, t)
	pos.y += sin(t * PI) * 2.2
	global_position = pos
	body_yaw += delta * 14.0
	velocity = Vector3.ZERO


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
	if limping and randf() < 0.25:
		say("vo_eh" if randf() < 0.5 else "vo_oof")
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play", _step_sound())


## What the ground underfoot sounds like: a crunch in leaves, a swish on the
## lawn, a scuff on pavement and porches.
func _step_sound() -> String:
	if global_position.y > 0.6:
		return "step_hard"
	var field := get_tree().get_first_node_in_group("leaf_field")
	if field != null and Net.player_zone(name.to_int()) == Net.Zone.LOT and int(field.call("sample_world", global_position)) >= Constants.STEP_LEAVES_DENSITY:
		return "step_leaves"
	var tasks := get_tree().get_first_node_in_group("job_tasks")
	if tasks != null and Net.player_zone(name.to_int()) == Net.Zone.LOT and bool(tasks.call("is_lawn", global_position)):
		return "step_grass"
	return "step_hard"


func _update_anim(crouching: bool, direction: Vector3) -> void:
	if not is_on_floor():
		anim_state = AnimState.AIR
	elif crouching:
		anim_state = AnimState.CROUCH
	elif direction.is_zero_approx():
		anim_state = AnimState.IDLE
	elif Input.is_action_pressed("sprint"):
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
	# Some jumps get a little "hup". anim_state and velocity replicate, so everyone hears it.
	if anim_state == AnimState.AIR and _last_anim != AnimState.AIR and velocity.y > 1.0 and randf() < HUP_CHANCE:
		say("vo_hup")
	_last_anim = anim_state


## Swap the gray-box capsule for a cartoon person (player/cartoon_body.gd). Looks
## come from the player's name, so a friend looks the same every session.
func _dress_up() -> void:
	if $Visual.has_node("CartoonBody"):
		return
	var body := _CartoonBody.new()
	body.name = "CartoonBody"
	var shown := Net.player_name(name.to_int())
	body.dress_from_seed(hash(shown) if shown != "" else name.to_int())
	$Visual.add_child(body)
	body.build(%Head, is_multiplayer_authority())
	var life := _CharacterLife.new()
	life.name = "Life"
	life.root = self
	life.body = body
	life.role = "player"
	body.add_child(life)
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


## A silly character noise (docs/ART.md, "Audio") from this player's head, in
## their own voice. Cosmetic and local: each peer plays it for itself.
func say(sound_name: String) -> void:
	if Net.is_automated():
		return
	var stream := load("res://assets/audio/sfx/%s.wav" % sound_name) as AudioStream
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
	%Head.add_child(voice)
	Net.attach_voice_output(name.to_int(), voice)
