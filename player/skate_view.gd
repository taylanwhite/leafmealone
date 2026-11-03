extends Node

## Authority: local, cosmetic, every peer. How the Gutter Shredder looks and
## sounds (driving chunk G1; player/skate.gd rides it): the board under the feet,
## the rider's stance (sideways on the deck, knees bent, arms out, leaning into a
## carve), the kick-push, the pop, flips and grabs, the board clattering off on a
## bail, sparks on a grind, the wheels turning, and the board's sounds. Read from
## the player's replicated on_board, skate_trick, wipeout, anim_state and velocity.
## On someone else's player those are read NetSmoother's delay late, so what you
## hear and see happen lines up with where their smoothed body is.
##
## It poses the CartoonBody after the body's own tick (process_physics_priority),
## through pose_part(), so cartoon_body.gd keeps no skate code (gap-specs/critic.md
## C20: driving G2 adds its flop there).

const _GearModels = preload("res://props/gear_models.gd")
const _Sfx = preload("res://audio/sfx.gd")
const _SoundBank = preload("res://audio/sound_bank.gd")
const _Skate = preload("res://player/skate.gd")

## The stance (radians, meters): the hips turned side-on so the right leg leads,
## the shoulders turned a little back toward the way you're going (still side-on:
## the balance arms point fore and aft, not out like a T; 0.8 back read square
## from behind in the 2026-11-03 recordings), legs spread along the board, knees
## bent. The head keeps looking where you're going.
const HIPS_YAW: float = 1.2
const TORSO_YAW: float = -0.35
const LEG_SPREAD: float = 0.3
const THIGH: float = 0.38
const ARM_OUT: float = 1.05
const ARM_FORWARD: float = 0.2
const TORSO_LEAN: float = 0.12
## Tucked (crouch on the ground), and in the air: thighs come up this far, and
## the board comes up with the feet. A grab tucks to GRAB_TUCK.
const TUCK_THIGH: float = 0.95
const AIR_THIGH: float = 0.8
const GRAB_TUCK: float = 1.25
## How the stance blends in and out, and the crouch with it (1/s).
const CROUCH_RATE: float = 9.0
## The kick-push: how long one kick takes (s), and how far the pushing leg swings out.
const PUSH_SECONDS: float = 0.36
const PUSH_SPREAD: float = 0.22
## A rider someone else sees: a speed gain this big (m/s) inside PUSH_SPOT_SECONDS is a kick.
const PUSH_SPOT_GAIN: float = 0.5
const PUSH_SPOT_SECONDS: float = 0.15
## Hopping on: the board drops from beside you (m), and you hop this high.
const MOUNT_FROM := Vector3(0.32, 0.55, 0.05)
const MOUNT_HOP: float = 0.14
## Stepping off: the board flicks up to your hand (m) and is gone.
const DISMOUNT_TO := Vector3(0.34, 0.85, 0.1)
## The board after a bail: how much it bounces, and how fast it tumbles (rad/s).
const FLY_BOUNCE: float = 0.35
const FLY_SPIN := Vector3(9.0, 4.0, 13.0)
## The loose board: the share of its speed it keeps off a wall, how fast it skids
## to a stop on the ground (m/s per s), how fast it rocks down flat (1/s), how long
## it lies there at most while you're down (s), and how long it takes to go in
## your pocket once you're up (s).
const FLY_WALL_KEEP: float = 0.4
const FLY_SKID: float = 6.0
const FLY_SETTLE_RATE: float = 9.0
const FLY_REST_MAX: float = 6.0
const POCKET_SECONDS: float = 0.3
## A flip caught on landing finishes this many times faster.
const FLIP_RUSH: float = 4.0
## The roll's sound under the board, and the sparks at its tail.
const SPARK_COLOR := Color(1.0, 0.78, 0.3)
const PUFF_COLOR := Color(0.85, 0.5, 0.18)

var player: CharacterBody3D

## The board's place under the feet (a child of Visual, so it turns with the body).
var _root: Node3D
var _board: Node3D
var _axles: Array[Node3D] = []
var _sparks: CPUParticles3D
var _puffs: CPUParticles3D
var _roll: AudioStreamPlayer3D
var _grind: AudioStreamPlayer3D
var _board_sound: Node

## Shown state, read late on remotes: {on, anim, trick, wipe, speed, vy}.
var _history: Array[Dictionary] = []
var _shown: Dictionary = {}
var _was: Dictionary = {}
## 0 off ... 1 on: the hop on and the step off play along it.
var _mount: float = 0.0
var _crouch: float = 0.0
var _air_tuck: float = 0.0
var _flip_t: float = -1.0
var _flip_sign: float = 1.0
var _flip_rush: bool = false
## This air's tail clack has played.
var _popped: bool = false
var _push_t: float = -1.0
var _pushes_seen: int = 0
var _speed_window: Array[Vector2] = []
var _air_best: int = 0
var _lean: float = 0.0
var _last_yaw: float = 0.0
var _fly_t: float = -1.0
var _fly_velocity := Vector3.ZERO
var _fly_floor: float = 0.0
## The loose board going in your pocket: seconds since it started, -1 not yet.
var _pocket_t: float = -1.0
var _grab_on: bool = false
var _posed: bool = false
var _time: float = 0.0


func _ready() -> void:
	# After the body (0), the player (100) and the riding (105).
	process_physics_priority = 110
	call_deferred("_build")


func _build() -> void:
	if player == null or not is_instance_valid(player):
		return
	var visual := player.get_node_or_null("Visual") as Node3D
	if visual == null:
		return
	_root = Node3D.new()
	_root.name = "Board"
	visual.add_child(_root)
	_board = _GearModels.build_skateboard()
	_root.add_child(_board)
	for axle_name: String in ["AxleFront", "AxleBack"]:
		_axles.append(_board.get_node(axle_name) as Node3D)
	_root.visible = false
	_sparks = _particles(SPARK_COLOR, 0.025, 40, 0.35)
	_sparks.position = Vector3(0.0, 0.03, _GearModels.TRUCK_Z + 0.08)
	_board.add_child(_sparks)
	_puffs = _particles(PUFF_COLOR, 0.05, 14, 0.7)
	_puffs.position = Vector3(0.0, 0.05, 0.0)
	_board.add_child(_puffs)
	_attach_sound()
	_last_yaw = float(player.get("body_yaw"))


# ---------------------------------------------------------------- every tick

func _physics_process(delta: float) -> void:
	if _root == null or player == null or multiplayer.multiplayer_peer == null:
		return
	_time += delta
	_shown = _late_state()
	var on := bool(_shown["on"])
	var air := int(_shown["anim"]) == _Skate.ANIM_SKATE_AIR
	var trick := int(_shown["trick"])
	var wipe := bool(_shown["wipe"])
	var speed := float(_shown["speed"])
	_edges(on, air, trick, wipe, speed)
	_mount = move_toward(_mount, 1.0 if on else 0.0, delta / Constants.SKATE_MOUNT_SECONDS)
	var crouch_want := 0.0
	if on and not air and _tucking():
		crouch_want = 1.0
	_crouch = move_toward(_crouch, crouch_want, delta * CROUCH_RATE * 0.5)
	var tuck_want := 0.0
	if on and air:
		tuck_want = GRAB_TUCK / AIR_THIGH if trick == _Skate.TRICK_GRAB else 1.0
	_air_tuck = move_toward(_air_tuck, tuck_want, delta * CROUCH_RATE)
	_step_push(delta, on, air, speed)
	_step_flip(delta)
	_step_lean(delta, on and not air)
	_place_board(delta, on, air, trick, speed)
	_pose(on, air, trick)
	_step_fly(delta)
	_step_sound(on, air, trick, speed)
	_was = _shown


## What to show: this tick's values for your own player, NetSmoother's delay late
## for anyone else's (their body is drawn that far behind).
func _late_state() -> Dictionary:
	var now := {
		"on": bool(player.get("on_board")), "anim": int(player.get("anim_state")),
		"trick": int(player.get("skate_trick")), "wipe": bool(player.get("wipeout")),
		"speed": Vector2(player.velocity.x, player.velocity.z).length(), "vy": player.velocity.y,
		"pushes": int(player.skate().get("pushes")) if player.is_multiplayer_authority() and player.skate() != null else 0,
	}
	if player.is_multiplayer_authority():
		return now
	var clock := float(Time.get_ticks_usec()) / 1000000.0
	now["at"] = clock
	_history.append(now)
	var smoother := player.get_node_or_null("NetSmoother")
	var delay := float(smoother.get("delay_seconds")) if smoother != null else 0.1
	var shown: Dictionary = _history[0]
	while _history.size() > 1 and float(_history[1]["at"]) <= clock - delay:
		_history.pop_front()
		shown = _history[0]
	return shown


# ---------------------------------------------------------------- edges: what just happened

func _edges(on: bool, air: bool, trick: int, wipe: bool, _speed: float) -> void:
	if _was.is_empty():
		return
	var was_on := bool(_was["on"])
	var was_air := int(_was["anim"]) == _Skate.ANIM_SKATE_AIR
	var was_trick := int(_was["trick"])
	if on and not was_on:
		_end_fly()
		_root.visible = true
	if not on and was_on and not wipe:
		_play("board_pop", -6.0)
	if wipe and not bool(_was["wipe"]):
		_launch_board()
		_play("wipeout")
	if on and air and not was_air:
		_air_best = trick
		_popped = false
	if on and air:
		_air_best = maxi(_air_best, trick)
		# A pop (an ollie, out of a grind) clacks the tail; rolling off the ramp doesn't.
		# Once per air, on whichever comes second on someone else's peer: the air
		# (anim_state, synced) or the ollie (skate_trick, sent on change).
		var popping := trick == _Skate.TRICK_OLLIE or (not was_air and float(_shown["vy"]) > Constants.SKATE_OLLIE_SPEED * 0.85)
		if not _popped and popping:
			_popped = true
			_play("board_pop")
	if trick != was_trick and (trick == _Skate.TRICK_KICKFLIP or trick == _Skate.TRICK_HEELFLIP):
		_flip_t = 0.0
		_flip_sign = 1.0 if trick == _Skate.TRICK_KICKFLIP else -1.0
	if on and not air and was_air:
		# A flip the feet caught just before the ground: its last bit goes round fast.
		_flip_rush = _flip_t >= 0.0
		_play("board_land")
		if _air_best >= _Skate.TRICK_KICKFLIP or trick == _Skate.TRICK_GRIND:
			_play("trick_ding")
		_air_best = 0
	# A grind ridden out to its end (not jumped out of): the ding too.
	if on and not air and was_trick == _Skate.TRICK_GRIND and trick != _Skate.TRICK_GRIND:
		_play("trick_ding")


func _tucking() -> bool:
	if player.is_multiplayer_authority():
		return Settings.is_held(&"crouch") or bool((player.skate().get("dev_input") as Dictionary).get("tuck", false))
	return false


# ---------------------------------------------------------------- the kick, the flip, the lean

func _step_push(delta: float, on: bool, air: bool, speed: float) -> void:
	if _push_t >= 0.0:
		_push_t += delta / PUSH_SECONDS
		if _push_t >= 1.0:
			_push_t = -1.0
	if not on or air:
		_speed_window.clear()
		return
	if player.is_multiplayer_authority():
		var pushes := int(_shown.get("pushes", 0))
		if pushes != _pushes_seen:
			_pushes_seen = pushes
			_push_t = 0.0
		return
	# Someone else's kick: a jump in their speed.
	_speed_window.append(Vector2(_time, speed))
	while _speed_window.size() > 1 and _speed_window[0].x < _time - PUSH_SPOT_SECONDS:
		_speed_window.pop_front()
	if _push_t < 0.0 and speed - _speed_window[0].y >= PUSH_SPOT_GAIN:
		_push_t = 0.0


func _step_flip(delta: float) -> void:
	if _flip_t < 0.0:
		return
	_flip_t += delta / Constants.SKATE_FLIP_SECONDS * (FLIP_RUSH if _flip_rush else 1.0)
	if _flip_t >= 1.0:
		_flip_t = -1.0
		_flip_rush = false


func _step_lean(delta: float, rolling: bool) -> void:
	var yaw := float(player.get("body_yaw"))
	var rate := angle_difference(_last_yaw, yaw) / maxf(delta, 0.0001)
	_last_yaw = yaw
	var want := clampf(rate * Constants.SKATE_LEAN_PER_TURN, -Constants.SKATE_LEAN_MAX, Constants.SKATE_LEAN_MAX) if rolling else 0.0
	_lean = lerpf(_lean, want, 1.0 - exp(-delta * Constants.SKATE_LEAN_RATE))


# ---------------------------------------------------------------- the board

func _place_board(delta: float, on: bool, air: bool, trick: int, speed: float) -> void:
	if _fly_t >= 0.0:
		return
	var showing := _mount > 0.0 and bool(player.call("is_body_drawn"))
	_root.visible = showing
	if not showing:
		return
	var m := smoothstep(0.0, 1.0, _mount)
	var lift := _board_lift(air)
	if on:
		# Hopping on: it drops from beside you to the ground, turning flat.
		_root.position = MOUNT_FROM.lerp(Vector3(0.0, lift, 0.0), m)
		_root.rotation = Vector3(0.0, 0.0, lerpf(1.2, 0.0, m))
		_root.scale = Vector3.ONE
	else:
		# Stepping off: the tail goes down, the nose flicks up into your hand.
		_root.position = DISMOUNT_TO.lerp(Vector3(0.0, lift, 0.0), m)
		_root.rotation = Vector3(lerpf(1.3, 0.0, m), 0.0, 0.0)
		_root.scale = Vector3.ONE * lerpf(0.2, 1.0, m)
	var pose := Basis.IDENTITY
	if _flip_t >= 0.0:
		pose = Basis(Vector3.BACK, _flip_sign * TAU * smoothstep(0.0, 1.0, _flip_t))
	pose = Basis(Vector3.BACK, -_lean * 0.35) * pose
	if trick == _Skate.TRICK_GRIND and not air:
		_root.position.y += Constants.SKATE_CURB_TOP
	_board.basis = pose
	# The wheels turn with the ground going by.
	if not air:
		for axle: Node3D in _axles:
			axle.rotation.x -= speed / _GearModels.WHEEL_RADIUS * delta
	var grinding := on and trick == _Skate.TRICK_GRIND and not air
	_sparks.emitting = grinding and speed > 1.0
	_puffs.emitting = grinding and speed > 1.0


## How far the board rides up with the feet: in the air they tuck up under you.
func _board_lift(air: bool) -> float:
	if not air:
		return 0.0
	var stance := _reach(THIGH)
	var tucked := _reach(lerpf(THIGH, AIR_THIGH, _air_tuck))
	return maxf(0.0, stance - tucked)


## A bail: the board leaves on its own, tumbling along the way you were going,
## bounces off the ground and anything solid, skids, and settles where it stops.
## It lies there while you're down and goes in your pocket once you're up
## (shrinks, with the hotbar's pocket sound), so it never just vanishes.
## Its floor is the real ground under it, found each tick (_ground_under), not the
## rider's height: a bail in the air (off the ramp, into Rusty's fence) drops the
## board all the way down instead of leaving it lying on nothing.
func _launch_board() -> void:
	if _root == null:
		return
	var at := _root.global_transform
	_root.top_level = true
	_root.global_transform = at
	_root.visible = bool(player.call("is_body_drawn"))
	var flat := Vector3(player.velocity.x, 0.0, player.velocity.z)
	_fly_velocity = flat * Constants.SKATE_BOARD_FLY_SHARE + Vector3.UP * Constants.SKATE_BOARD_FLY_UP
	_fly_floor = _ground_under(at.origin, player.global_position.y)
	_fly_t = 0.0
	_pocket_t = -1.0
	_flip_t = -1.0


## The ground straight under the loose board: the first solid thing (layer 1)
## below it that isn't someone (a NICE BOY's or a hired hand's capsule is layer 1
## too: the board doesn't lie on a head). fallback when there's nothing.
func _ground_under(at: Vector3, fallback: float) -> float:
	var space := _root.get_world_3d().direct_space_state
	var skip: Array[RID] = [player.get_rid()]
	for _try: int in 4:
		var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * Constants.SKATE_BOARD_GROUND_ABOVE, at + Vector3.DOWN * Constants.SKATE_BOARD_GROUND_BELOW, 1, skip)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return fallback
		if hit["collider"] is CharacterBody3D:
			skip.append(hit["rid"])
			continue
		return (hit["position"] as Vector3).y
	return fallback


func _step_fly(delta: float) -> void:
	if _fly_t < 0.0:
		return
	_fly_t += delta
	var at := _root.global_position
	_fly_floor = _ground_under(at, _fly_floor)
	# Tumbling for SKATE_BOARD_FLY_SECONDS, and still falling after that while it's
	# above the ground (a high bail), for at most SKATE_BOARD_FALL_MAX more.
	var falling := at.y > _fly_floor + 0.02 and _fly_t < Constants.SKATE_BOARD_FLY_SECONDS + Constants.SKATE_BOARD_FALL_MAX
	if _fly_t < Constants.SKATE_BOARD_FLY_SECONDS or falling:
		_fly_velocity.y -= Constants.SKATE_BOARD_FLY_GRAVITY * delta
		var to := at + _fly_velocity * delta
		# Off a wall or a fence: back the way it came, slower, with a clack.
		var hit := _root.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.08, to + Vector3.UP * 0.08, 1, [player.get_rid()]))
		if not hit.is_empty() and (hit["normal"] as Vector3).y < 0.6:
			var normal: Vector3 = hit["normal"]
			_fly_velocity = _fly_velocity.bounce(Vector3(normal.x, 0.0, normal.z).normalized()) * FLY_WALL_KEEP
			to = at
			_play_at("board_land", at, -2.0)
		if to.y < _fly_floor and _fly_velocity.y < 0.0:
			to.y = _fly_floor
			if absf(_fly_velocity.y) > Constants.SKATE_BOARD_CLACK_SPEED:
				_play_at("board_land", to, -4.0)
			_fly_velocity.y = -_fly_velocity.y * FLY_BOUNCE
			_fly_velocity.x *= Constants.SKATE_BOARD_BOUNCE_KEEP
			_fly_velocity.z *= Constants.SKATE_BOARD_BOUNCE_KEEP
		if to.y <= _fly_floor + 0.01:
			# Skidding on its side or its wheels.
			var skid := Vector2(_fly_velocity.x, _fly_velocity.z)
			skid = skid.move_toward(Vector2.ZERO, FLY_SKID * delta)
			_fly_velocity.x = skid.x
			_fly_velocity.z = skid.y
		_root.global_position = to
		var spin := FLY_SPIN * clampf(1.0 - _fly_t / Constants.SKATE_BOARD_FLY_SECONDS, 0.0, 1.0)
		_root.rotate_object_local(Vector3.RIGHT, spin.x * delta)
		_root.rotate_object_local(Vector3.UP, spin.y * delta)
		_root.rotate_object_local(Vector3.BACK, spin.z * delta)
		return
	# Settled: it rocks down flat, wheels up or wheels down, whichever it's nearer.
	var size := _root.scale.x
	var basis := _root.global_basis.orthonormalized()
	var up := Vector3.UP if basis.y.y >= 0.0 else Vector3.DOWN
	var along := basis.z - up * basis.z.dot(up)
	if along.length() < 0.01:
		along = basis.x.cross(up)
	var flat_basis := Basis.looking_at(-along.normalized(), up)
	var ease := 1.0 - exp(-delta * FLY_SETTLE_RATE)
	_root.global_basis = basis.slerp(flat_basis, ease).scaled(Vector3.ONE * size)
	# Lying on its grip tape, the deck is on the ground and the wheels in the air.
	var rest_y := _fly_floor + (Constants.SKATE_DECK_HEIGHT if up == Vector3.DOWN else 0.0)
	_root.global_position = Vector3(at.x, lerpf(at.y, rest_y, ease), at.z)
	var down_long := _fly_t > Constants.SKATE_BOARD_FLY_SECONDS + FLY_REST_MAX
	if _pocket_t < 0.0 and (not bool(_shown.get("wipe", false)) or down_long):
		_pocket_t = 0.0
		_play_at("pocket", _root.global_position, -6.0)
	if _pocket_t >= 0.0:
		_pocket_t += delta
		var left := 1.0 - smoothstep(0.0, 1.0, _pocket_t / POCKET_SECONDS)
		_root.scale = Vector3.ONE * maxf(left, 0.001)
		if _pocket_t >= POCKET_SECONDS:
			_end_fly()
			_root.visible = false
			_mount = 0.0


func _end_fly() -> void:
	if _fly_t < 0.0 and not _root.top_level:
		return
	_fly_t = -1.0
	_pocket_t = -1.0
	_root.top_level = false
	_root.transform = Transform3D.IDENTITY


# ---------------------------------------------------------------- the rider

func _pose(on: bool, air: bool, trick: int) -> void:
	var body := player.get_node_or_null("Visual/CartoonBody") as Node3D
	if body == null or body.call("pose_part", "hips") == null:
		return
	var m := smoothstep(0.0, 1.0, _mount) if _fly_t < 0.0 else 0.0
	if m <= 0.0 or not on and _mount <= 0.0:
		if _posed:
			_posed = false
			body.position.y = 0.0
			body.rotation.z = 0.0
			(body.call("pose_part", "torso") as Node3D).rotation.y = 0.0
			_set_grab(body, false)
		return
	_posed = true
	var hips := body.call("pose_part", "hips") as Node3D
	var torso := body.call("pose_part", "torso") as Node3D
	var legs: Array[Node3D] = [body.call("pose_part", "leg_l") as Node3D, body.call("pose_part", "leg_r") as Node3D]
	var arms: Array[Node3D] = [body.call("pose_part", "arm_l") as Node3D, body.call("pose_part", "arm_r") as Node3D]
	# Hopping on: a little hop as the board lands under you.
	var hop := sin(PI * clampf(_mount, 0.0, 1.0)) * MOUNT_HOP if on and _mount < 1.0 else 0.0
	body.position.y = Constants.SKATE_DECK_HEIGHT * m + hop
	body.rotation.z = _lean * m
	# Legs: both feet on the deck; the back one kicks the ground while pushing.
	var thigh := THIGH
	if air:
		thigh = lerpf(THIGH, AIR_THIGH, _air_tuck)
	elif _crouch > 0.0:
		thigh = lerpf(THIGH, TUCK_THIGH, _crouch)
	# On the ground the hips sink as the knees bend; in the air they stay put and
	# the tucked feet (and the board, _board_lift) come up instead.
	var hip_y := 0.06 + _reach(THIGH if air else thigh)
	var kick := sin(PI * _push_t) if _push_t >= 0.0 else 0.0
	var hips_y := lerpf(hips.position.y, hip_y - kick * 0.05, m)
	hips.position.y = hips_y
	hips.rotation.y = lerpf(hips.rotation.y, HIPS_YAW, m)
	for index: int in 2:
		var leg := legs[index]
		var knee := leg.get_node_or_null("Knee") as Node3D
		var side := -1.0 if index == 0 else 1.0
		var leg_thigh := thigh
		var spread := LEG_SPREAD
		var reach := _reach(thigh)
		if index == 0 and kick > 0.0:
			# The back foot drops off the deck to the ground beside it and shoves.
			leg_thigh = lerpf(thigh, 0.12, kick)
			spread = LEG_SPREAD + PUSH_SPREAD * kick
			reach = _reach(thigh) + kick * (Constants.SKATE_DECK_HEIGHT + 0.05)
		leg.rotation.x = lerpf(leg.rotation.x, leg_thigh, m)
		leg.rotation.z = lerpf(leg.rotation.z, side * spread, m)
		if knee != null:
			knee.rotation.x = lerpf(knee.rotation.x, _shin_for(leg_thigh, reach / cos(spread)), m)
	# Torso: shoulders back round toward the way you're going, a little bent.
	torso.rotation.y = lerpf(0.0, TORSO_YAW, m)
	torso.rotation.x = lerpf(torso.rotation.x, -TORSO_LEAN - 0.25 * _crouch - 0.2 * _air_tuck, m)
	# Arms out for balance, wobbling; up and wide in the air. Hands on something
	# held (a leaf bag) stay on it.
	var holding := bool(player.call("holding_prop"))
	for index: int in 2:
		if holding:
			break
		var arm := arms[index]
		var side := -1.0 if index == 0 else 1.0
		var wobble := sin(_time * 3.1 + float(index) * 1.7) * 0.08
		var out := ARM_OUT + 0.5 * _air_tuck + wobble
		arm.rotation.z = lerpf(arm.rotation.z, side * out, m)
		arm.rotation.x = lerpf(arm.rotation.x, ARM_FORWARD, m)
	_set_grab(body, on and air and trick == _Skate.TRICK_GRAB)
	# Your head (and your camera) rides the deck too, smooth, with no walk bob.
	var head := player.get_node_or_null("Visual/Head") as Node3D
	if head != null:
		var base := float(body.get("_head_base_y"))
		var sink := 0.82 - hips_y
		head.position.y = lerpf(head.position.y, base + Constants.SKATE_DECK_HEIGHT + hop - sink * 0.9, m)


## The grab: the leading hand reaches down to the deck's toe-side edge.
func _set_grab(body: Node3D, on: bool) -> void:
	if on == _grab_on and not on:
		return
	_grab_on = on
	var reach_at: Array = body.get("reach_at")
	var weight: Array = body.get("reach_weight")
	if on:
		reach_at[0] = _board.global_transform * Vector3(0.0, Constants.SKATE_DECK_HEIGHT, -0.05) + _root.global_basis.x * -0.11
		weight[0] = 1.0
	else:
		weight[0] = 0.0
		reach_at[0] = Vector3.INF
	body.set("reach_at", reach_at)
	body.set("reach_weight", weight)


## How far below the hip a foot is with the thigh forward by thigh (rad), the knee
## bent back to keep the shin near upright.
func _reach(thigh: float) -> float:
	var shin := _shin_for(thigh, -1.0)
	return Constants.BODY_THIGH * cos(thigh) + Constants.BODY_SHIN * cos(thigh + shin)


## The knee's bend (negative, rad) that puts the foot reach meters below the hip
## with the thigh at thigh; reach < 0: the shin hangs straight down.
func _shin_for(thigh: float, reach: float) -> float:
	if reach < 0.0:
		return -thigh * 1.85
	var shin_cos := clampf((reach - Constants.BODY_THIGH * cos(thigh)) / Constants.BODY_SHIN, -1.0, 1.0)
	return -(thigh + acos(shin_cos))


# ---------------------------------------------------------------- sound

## audio/board_sound.gd when it exists (audio chunk 7; it reads the riding's
## board_state(), critic C13), else the roll and grind loops here. Nothing headless.
func _attach_sound() -> void:
	if Net.is_automated() or DisplayServer.get_name() == "headless":
		return
	if ResourceLoader.exists("res://audio/board_sound.gd"):
		_board_sound = load("res://audio/board_sound.gd").new()
		_board_sound.name = "BoardSound"
		var riding: Node = player.skate()
		if "state_source" in _board_sound and riding != null:
			_board_sound.set("state_source", Callable(riding, "board_state"))
		if riding != null:
			riding.add_child(_board_sound)
		return
	_roll = _loop("board_roll_loop", "Roll")
	_grind = _loop("board_grind_loop", "Grind")


func _loop(id: String, node_name: String) -> AudioStreamPlayer3D:
	var sound := AudioStreamPlayer3D.new()
	sound.name = node_name
	sound.stream = _Sfx.looped(id)
	sound.bus = _SoundBank.bus(id)
	sound.unit_size = Constants.SFX_UNIT_SIZE
	sound.max_distance = Constants.SKATE_SOUND_MAX_DISTANCE
	sound.volume_db = -80.0
	_root.add_child(sound)
	return sound


func _step_sound(on: bool, air: bool, trick: int, speed: float) -> void:
	if _roll == null:
		return
	var rolling := on and not air and speed > 0.3 and trick != _Skate.TRICK_GRIND and _fly_t < 0.0
	var share := clampf(speed / Constants.SKATE_MAX_PUSH_SPEED, 0.0, 1.0)
	if rolling:
		if not _roll.playing:
			_roll.play()
		_roll.volume_db = lerpf(Constants.SKATE_ROLL_DB.x, Constants.SKATE_ROLL_DB.y, share)
		_roll.pitch_scale = lerpf(Constants.SKATE_ROLL_PITCH.x, Constants.SKATE_ROLL_PITCH.y, share)
	elif _roll.playing:
		_roll.stop()
	var grinding := on and not air and trick == _Skate.TRICK_GRIND
	if grinding:
		if not _grind.playing:
			_grind.play()
		_grind.volume_db = lerpf(Constants.SKATE_GRIND_DB.x, Constants.SKATE_GRIND_DB.y, share)
	elif _grind.playing:
		_grind.stop()


func _play(id: String, db := 0.0) -> void:
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null and _root != null:
		sfx.call("play_on", id, _root, db)


func _play_at(id: String, at: Vector3, db := 0.0) -> void:
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play_at", id, at, db)


func _particles(color: Color, size: float, amount: int, life: float) -> CPUParticles3D:
	var bits := CPUParticles3D.new()
	bits.emitting = false
	bits.amount = amount
	bits.lifetime = life
	bits.local_coords = false
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = color
	quad.material = material
	bits.mesh = quad
	bits.direction = Vector3(0.0, 1.0, 1.0)
	bits.spread = 50.0
	bits.initial_velocity_min = 0.8
	bits.initial_velocity_max = 2.2
	bits.gravity = Vector3(0.0, -6.0, 0.0)
	bits.scale_amount_min = 0.6
	bits.scale_amount_max = 1.2
	return bits
