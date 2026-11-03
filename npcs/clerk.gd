extends Node3D

## Authority: local, cosmetic. The staff of Satellite Annex B (levels/annex/
## annex_b.gd builds them under AnnexSet/Staff): ClerkA..D behind the windows,
## the Head NICE BOY at his desk, the Greeter at the doors, the Janitor with his
## mop. Each is a CartoonBody in the NICE BOYS' uniform (the crew's look)
## driven by play(state, at, args): a pure function of the state and how
## long ago server time `at` was, so every peer shows the same moment (no
## spawner, nothing replicated). The host's "is he looking" never reads these
## bodies (R2 chunk 6 judges that from its own schedule), so drift can't change
## an outcome. Every state reads at 6 m: big arm shapes, a turned body, a head
## that shakes or slumps, a prop in the hand.
##
## States (gap-specs nice_boys C10): counter_idle, wave_up, take_form, stamp,
## hand_back, peer_form, head_shake_point (args.to), phone, telegraph_stretch
## (args.seconds), walk_to (args.to, args.face), on_break (args.to, args.face),
## hurry_back, asleep, wake, lunch_bite, lunch_turned, lean_toward (args.dir),
## turn_to_cabinet (args.twitch_at), twitch_turn_back, notice (args.at),
## add_carbon, volley (args.count), head_windup_slam, gasp_whistle,
## walk_hand_out (args.to), take_stamp_back (args.from), greeter_lead
## (args.reverse), greeter_offer, greeter_punch_card, janitor_mop,
## closing_rush; and idle (standing). args.bark (a ui/strings.gd CLERK_BARKS
## kind) says a line at `at`. Positions in args are global.

const _CartoonBody = preload("res://player/cartoon_body.gd")
const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const _Props = preload("res://props/office_props.gd")
const _Strings = preload("res://ui/strings.gd")
const _Bank = preload("res://audio/sound_bank.gd")
const _NiceSeal = preload("res://props/nice_seal.gd")
## The uniform's khaki shorts (npcs/crew_member.gd KHAKI).
const KHAKI := Color(0.8, 0.7, 0.52)

const STATES: Array[StringName] = [
	&"idle", &"counter_idle", &"wave_up", &"take_form", &"stamp", &"hand_back", &"peer_form",
	&"head_shake_point", &"phone", &"telegraph_stretch", &"walk_to", &"on_break",
	&"hurry_back", &"asleep", &"wake", &"lunch_bite", &"lunch_turned", &"lean_toward",
	&"turn_to_cabinet", &"twitch_turn_back", &"notice", &"add_carbon", &"volley",
	&"head_windup_slam", &"gasp_whistle", &"walk_hand_out", &"take_stamp_back",
	&"greeter_lead", &"greeter_offer", &"greeter_punch_card", &"janitor_mop", &"closing_rush",
]
## States in which a clerk or the Head NICE BOY sits (the rest stand or walk).
const SEATED: Array[StringName] = [
	&"counter_idle", &"wave_up", &"take_form", &"stamp", &"hand_back", &"peer_form",
	&"head_shake_point", &"phone", &"asleep", &"wake", &"lunch_bite", &"lunch_turned",
	&"lean_toward", &"turn_to_cabinet", &"twitch_turn_back", &"notice", &"add_carbon",
	&"volley", &"closing_rush",
]
## How far a seated body drops (CartoonBody: standing hips 0.82, seated 0.48).
const SIT_DROP: float = 0.34
const SIT_LEGS: float = 1.42
const SIT_SECONDS: float = 0.35
## Shoulder to hand, in meters (CartoonBody's arm).
const ARM_LENGTH: float = 0.52

## "clerk", "head", "greeter" or "janitor".
var role: String = "clerk"
## The set this one works in (for routes, windows, the big stamp).
var annex_set: Node3D = null
var state: StringName = &"idle"
var state_at: float = -1000.0
var args: Dictionary = {}
var body: Node3D
var _home_pos := Vector3.ZERO
var _home_yaw: float = 0.0
var _yaw: float = 0.0
var _sit: float = 1.0
## The way being walked: points in the parent's space, and where it started.
var _route := PackedVector3Array()
var _route_from := Vector3.ZERO
var _route_length: float = 0.0
var _arrive_yaw: float = INF
var _walk_delay: float = 0.0
var _snap_seat: bool = true
## Moments already sounded, by "<state_at>|<what>".
var _fired: Dictionary = {}
var _hand_props: Dictionary = {}
var _zs: Node3D
var _next_snore: float = 0.0
var _pending_bark: Dictionary = {}
var _rng := RandomNumberGenerator.new()
## Tools only (the studio's lineups): hold the pose this many seconds into the
## state instead of following the clock. Negative follows the clock.
var hold_t: float = -1.0


## A staff member named node_name in the role's look (index picks the face,
## npcs/crew_member.gd dress()).
static func make(node_name: String, staff_role: String, index: int) -> Node3D:
	var clerk: Node3D = (load("res://npcs/clerk.gd") as GDScript).new()
	clerk.name = node_name
	clerk.set("role", staff_role)
	clerk.call("_dress", index)
	return clerk


func _dress(index: int) -> void:
	body = _CartoonBody.new()
	body.name = "CartoonBody"
	# The crew's look (npcs/crew_member.gd dress()), kept here so the office
	# never loads the crew's networked script: Courtesy Lavender polos, khaki
	# shorts, sun visors, gold aviators, the grin; the Head NICE BOY's megaphone.
	body.set("shirt", _NiceSeal.LAVENDER)
	body.set("pants", KHAKI)
	body.set("skin", _CartoonBody.SKIN_TONES[absi(hash("Annex%d" % index)) % _CartoonBody.SKIN_TONES.size()])
	body.set("hair", _CartoonBody.HAIR[absi(hash("annex_hair%d" % index)) % _CartoonBody.HAIR.size()])
	body.set("hat_style", "visor")
	body.set("hat_color", _NiceSeal.LAVENDER)
	body.set("shades", true)
	body.set("shades_style", "aviator")
	body.set("grin", true)
	body.set("outfit", "nice_boy_lead" if role == "head" else "nice_boy")
	add_child(body)
	# Bodies face -Z; the staff's +Z is forward, as the crew's is.
	body.rotation.y = PI
	body.call("build")
	_rng.seed = hash(node_name_for_seed(index))
	_build_props()
	# Pose after the body animates each tick (it resets the arms every tick).
	process_physics_priority = 10


func node_name_for_seed(index: int) -> String:
	return "%s:%d" % [role, index]


## Where this one belongs (its seat, its post) in the parent's space.
func set_home(at: Vector3, yaw: float) -> void:
	_home_pos = at
	_home_yaw = yaw
	_yaw = yaw
	position = at
	rotation.y = yaw


## Show state from server time at on (see the list above). The same call on
## every peer shows the same pose at the same moment.
func play(next: StringName, at: float, play_args: Dictionary = {}) -> void:
	if not STATES.has(next):
		push_warning("[Clerk] %s has no state %s" % [name, next])
		return
	state = next
	state_at = at
	args = play_args
	_route = PackedVector3Array()
	_arrive_yaw = INF
	match next:
		&"walk_to", &"on_break", &"walk_hand_out":
			_walk(_target(args.get("to", null)), args.get("face", null))
		&"hurry_back":
			_walk(_home_pos, _home_yaw)
		&"greeter_lead":
			_walk_path("GreeterPath", bool(args.get("reverse", false)))
		&"janitor_mop":
			_walk_path("JanitorPath", false)
		&"take_stamp_back":
			_walk(_target(args.get("to", null)), _home_yaw)
	if args.has("bark"):
		_pending_bark = {"kind": str(args["bark"]), "at": at}
	if next == &"asleep":
		_next_snore = at + 0.5
	# A state that began long ago (a late joiner, the set's first pose) is
	# already sat in or stood up from: no slow sit on arrival.
	_snap_seat = _Props.now() - at > SIT_SECONDS
	set_physics_process(true)


## Says a line of kind (ui/strings.gd CLERK_BARKS) now: the caption stack shows
## it as a subtitle (it honors the captions setting), the mouth moves, the
## babble plays from here. index picks the line; -1 picks one from the moment,
## the same on every peer.
func bark(kind: String, index: int = -1) -> String:
	var pool: Array = _Strings.CLERK_BARKS.get(kind, [])
	if pool.is_empty():
		return ""
	var pick := index if index >= 0 else absi(hash("%s|%s|%.2f" % [name, kind, state_at])) % pool.size()
	var line := str(pool[pick % pool.size()])
	body.call("talk", minf(Constants.CLERK_BARK_SECONDS, 0.25 + float(line.length()) * 0.04))
	_play_sfx("babble", global_position + Vector3.UP * 1.4)
	var captions := get_tree().get_first_node_in_group("caption_stack") if is_inside_tree() else null
	if captions != null and captions.has_method("push"):
		captions.call("push", &"subtitle", line, Constants.CLERK_BARK_SECONDS)
	return line


## A global point or node from args, in the parent's space; home without one.
func _target(value: Variant) -> Vector3:
	var parent := get_parent() as Node3D
	if value is Vector3:
		return parent.to_local(value) if parent != null else value
	if value is Node3D:
		return parent.to_local((value as Node3D).global_position) if parent != null else (value as Node3D).position
	return _home_pos


## Walk from where this one stands to `to` (parent space), the set's route
## through the staff door when the counter wall is in the way.
func _walk(to: Vector3, face: Variant) -> void:
	_route_from = position
	_walk_delay = SIT_SECONDS if _sit > 0.5 else 0.0
	var points := PackedVector3Array([to])
	if annex_set != null and annex_set.has_method("route") and get_parent() != null:
		var from_set := annex_set.to_local((get_parent() as Node3D).to_global(position))
		var to_set := annex_set.to_local((get_parent() as Node3D).to_global(to))
		points = PackedVector3Array()
		for point: Vector3 in annex_set.call("route", from_set, to_set) as PackedVector3Array:
			points.append((get_parent() as Node3D).to_local(annex_set.to_global(point)))
	_route = points
	_route_length = _length(_route_from, _route)
	if face is float or face is int:
		_arrive_yaw = float(face)
	elif face is Vector3:
		var toward: Vector3 = (get_parent() as Node3D).to_local(face) - to if get_parent() != null else face - to
		_arrive_yaw = atan2(toward.x, toward.z)


func _walk_path(path_name: String, reverse: bool) -> void:
	var path := annex_set.get_node_or_null(path_name) as Path3D if annex_set != null else null
	_route_from = position
	_walk_delay = SIT_SECONDS if _sit > 0.5 else 0.0
	_route = PackedVector3Array()
	if path == null or path.curve == null:
		return
	var count := path.curve.point_count
	for step: int in count:
		var index := count - 1 - step if reverse else step
		_route.append((get_parent() as Node3D).to_local(path.to_global(path.curve.get_point_position(index))))
	_route_length = _length(_route_from, _route)


func _length(from: Vector3, points: PackedVector3Array) -> float:
	var total := 0.0
	var last := from
	for point: Vector3 in points:
		total += Vector2(point.x - last.x, point.z - last.z).length()
		last = point
	return total


## Where along the route this far in, and which way it heads there.
func _along(distance: float) -> Array:
	var last := _route_from
	var left := distance
	for point: Vector3 in _route:
		var leg := Vector2(point.x - last.x, point.z - last.z).length()
		if left <= leg and leg > 0.001:
			var k := left / leg
			return [last.lerp(point, k), atan2(point.x - last.x, point.z - last.z), false]
		left -= leg
		last = point
	var heading := _yaw
	if _route.size() >= 1:
		var before := _route_from if _route.size() == 1 else _route[_route.size() - 2]
		var tail := _route[_route.size() - 1] - before
		if Vector2(tail.x, tail.z).length() > 0.01:
			heading = atan2(tail.x, tail.z)
	return [last, heading, true]


func _physics_process(delta: float) -> void:
	if body == null:
		return
	var t := _Props.now() - state_at if hold_t < 0.0 else hold_t
	if not _pending_bark.is_empty() and _Props.now() >= float(_pending_bark["at"]):
		var kind := str(_pending_bark["kind"])
		_pending_bark = {}
		if _Props.now() - state_at <= 1.0:
			bark(kind)
	_locomote(t, delta)
	_seat(delta)
	_pose(t, delta)


# ---------------------------------------------------------------- moving

func _locomote(t: float, delta: float) -> void:
	var walking := not _route.is_empty()
	if walking:
		var speed := Constants.CLERK_HURRY_SPEED if state == &"hurry_back" else Constants.CLERK_WALK_SPEED
		if state == &"janitor_mop":
			speed = Constants.CLERK_WALK_SPEED * 0.45
		# Ease into the walk and stand up first (the stool), then go.
		var travelled := maxf(0.0, t - _walk_delay) * speed
		travelled = minf(travelled, _route_length)
		var at: Array = _along(travelled)
		position = Vector3((at[0] as Vector3).x, _home_pos.y, (at[0] as Vector3).z)
		var arrived: bool = at[2]
		var want: float = at[1]
		if arrived and _arrive_yaw != INF:
			want = _arrive_yaw
		_yaw = rotate_toward(_yaw, want, Constants.CLERK_TURN_RATE * delta)
		if arrived and state == &"hurry_back":
			_yaw = rotate_toward(_yaw, _home_yaw, Constants.CLERK_TURN_RATE * delta)
		if arrived and state == &"janitor_mop" and _route_length > 0.5:
			# Round again, the other way: he mops the same floor forever.
			var back := PackedVector3Array()
			for index: int in range(_route.size() - 2, -1, -1):
				back.append(_route[index])
			back.append(_route_from)
			_route_from = position
			_route = back
			_walk_delay = 0.0
			state_at = _Props.now()
	else:
		_yaw = rotate_toward(_yaw, _turn_target(t), Constants.CLERK_TURN_RATE * delta)
	rotation.y = _yaw


## Which way to face while not walking: home, turned for the phone or the
## cabinet, round for lunch, toward whatever is leaned at.
func _turn_target(t: float) -> float:
	match state:
		&"phone":
			return _home_yaw + 0.95
		&"lunch_turned":
			return _home_yaw + PI * 0.92
		&"turn_to_cabinet":
			var twitch_at := float(args.get("twitch_at", 1.2))
			# A head twitch back toward the counter: the body hesitates too.
			var flinch := 0.35 if t > twitch_at and t < twitch_at + 0.35 else 0.0
			return _home_yaw + PI * 0.8 - flinch
		&"lean_toward":
			var dir := _dir_arg()
			if dir != Vector3.ZERO:
				var local := (get_parent() as Node3D).global_basis.inverse() * dir if get_parent() != null else dir
				return _home_yaw + clampf(angle_difference(_home_yaw, atan2(local.x, local.z)), -0.25, 0.25)
		&"notice", &"walk_hand_out", &"take_stamp_back":
			var at: Variant = args.get("at", args.get("from", null))
			if at is Vector3:
				var toward: Vector3 = (get_parent() as Node3D).to_local(at) - position
				return atan2(toward.x, toward.z)
	if position.distance_to(_home_pos) < 0.3:
		return _home_yaw
	return _yaw


func _dir_arg() -> Vector3:
	var dir: Variant = args.get("dir", Vector3.ZERO)
	if dir is Vector3:
		return (dir as Vector3).normalized() if (dir as Vector3).length() > 0.01 else Vector3.ZERO
	return Vector3.ZERO


## Sitting down and standing up take SIT_SECONDS, never a frame.
func _seat(delta: float) -> void:
	var want := 1.0 if SEATED.has(state) and _route.is_empty() and position.distance_to(_home_pos) < 0.08 and (role == "clerk" or role == "head") else 0.0
	if state == &"telegraph_stretch":
		want = 0.0
	if not _route.is_empty():
		want = 0.0
	_sit = want if _snap_seat else move_toward(_sit, want, delta / SIT_SECONDS)
	_snap_seat = false
	var k := smoothstep(0.0, 1.0, _sit)
	var hips := body.get("_hips") as Node3D
	var head := body.get("_head_root") as Node3D
	var legs: Array = body.get("_legs")
	hips.position.y -= SIT_DROP * k
	head.position.y -= SIT_DROP * k
	for leg: Node3D in legs:
		leg.rotation.x = lerpf(leg.rotation.x, SIT_LEGS, k)


# ---------------------------------------------------------------- posing

func _arm(side: int) -> Node3D:
	# side 0 right, 1 left (CartoonBody keeps [left, right]).
	var arms: Array = body.get("_arms")
	return arms[1 - side] as Node3D


## Swing an arm (0 right, 1 left) to point its hand at a world point.
func _aim(side: int, target: Vector3, weight: float) -> void:
	var arm := _arm(side)
	var parent := arm.get_parent() as Node3D
	var local := parent.global_transform.affine_inverse() * target - arm.position
	if local.length() < 0.01:
		return
	var k := clampf(weight, 0.0, 1.0)
	arm.quaternion = arm.quaternion.slerp(Quaternion(Vector3.DOWN, local.normalized()), k)
	# The arm has no elbow: a near target shortens it so the hand lands there.
	var reach := clampf(local.length() / ARM_LENGTH, 0.62, 1.08)
	arm.scale = Vector3(1.0, lerpf(1.0, reach, k), 1.0)


## A point in front of this one: right (+), up, forward (+), in world space.
func _ahead(right: float, up: float, forward: float) -> Vector3:
	return global_transform * Vector3(-right, up, forward)


func _face_node() -> Node3D:
	return body.get("_face") as Node3D


func _pose(t: float, _delta: float) -> void:
	var fade := clampf(t / 0.2, 0.0, 1.0)
	var torso := body.get("_torso") as Node3D
	var face := _face_node()
	var eyes: Array = body.get("_eyes")
	body.set("squinting", false)
	body.set("mood", "neutral")
	body.set("face_turn", 0.0)
	torso.rotation.y = 0.0
	(body.get("_hips") as Node3D).position.x = 0.0
	_show_prop("", false)
	if _zs != null:
		_zs.visible = false
	var sat := smoothstep(0.0, 1.0, _sit)
	var head_y := 1.6 - SIT_DROP * sat
	var clipboard := body.get("_clipboard") as Node3D
	if clipboard != null:
		# The clipboard never leaves the left hand (nothing pops); the janitor has a mop instead.
		clipboard.visible = role != "janitor"
	match state:
		&"idle":
			body.set("face_turn", sin(t * 0.35) * 0.35 * clampf(sin(t * 0.13) * 3.0, 0.0, 1.0))
			if role == "janitor":
				_mop(t, false)
		&"counter_idle":
			# Typing: both hands on the desk, a key at a time; a look up now and then.
			var typing := 0.5 + 0.5 * sin(t * 0.3)
			_aim(0, _ahead(0.12 + 0.02 * sin(t * 19.0), 0.8 + 0.015 * absf(sin(t * 23.0)), 0.42), typing * fade)
			_aim(1, _ahead(-0.12, 0.8 + 0.015 * absf(sin(t * 17.0 + 1.0)), 0.42), typing * fade)
			body.set("face_turn", sin(t * 0.45) * 0.3)
			face.rotation.x -= 0.18 * typing
		&"wave_up":
			_aim(0, _ahead(0.35, head_y + 0.55 + 0.12 * sin(t * 12.0), 0.25), fade)
			body.set("mood", "raised")
		&"take_form":
			var reach := ease_reach(t, 0.0, 0.35, 0.8)
			_aim(0, _ahead(0.05, 1.05, 0.55 + reach * 0.75), fade)
			_show_prop("paper", t > 0.35)
		&"stamp":
			# The window's stamp moves; the hand rides on it, so he is holding it.
			_aim(1, _ahead(-0.05, 0.86, 0.5), fade)
			var stamp := _window_node("Stamp")
			if stamp != null:
				_aim(0, stamp.global_position + Vector3.UP * 0.14, fade)
		&"hand_back":
			var reach := ease_reach(t, 0.0, 0.3, 0.7)
			_aim(0, _ahead(0.05, 1.05, 0.55 + reach * 0.75), fade)
			_show_prop("paper", t < 0.35)
		&"peer_form":
			torso.rotation.x -= 0.35 * fade
			face.rotation.x -= 0.25 * fade
			body.set("squinting", true)
			_aim(0, _ahead(0.1, 1.0, 0.45), fade)
			_aim(1, _ahead(-0.1, 1.0, 0.45), fade)
			_show_prop("paper", true)
		&"head_shake_point":
			var shake_end := 0.9
			if t < shake_end:
				# No, no, no: the whole head, and the shoulders a little against it.
				var shake := sin(t * TAU * Constants.CLERK_SHAKE_HZ) * (1.0 - t / shake_end * 0.35)
				face.rotation.y = shake * 0.75
				torso.rotation.y = -shake * 0.12
				body.set("mood", "worried")
			else:
				var to: Variant = args.get("to", null)
				var point := to as Vector3 if to is Vector3 else _ahead(1.5, head_y, 1.0)
				_aim(0, point, clampf((t - shake_end) / 0.18, 0.0, 1.0))
				var local := global_transform.affine_inverse() * point
				body.set("face_turn", clampf(atan2(local.x, local.z), -0.9, 0.9))
		&"phone":
			_aim(0, _ahead(0.27, head_y - 0.02, 0.02), fade)
			_show_prop("phone", true)
			# One finger up: just a moment.
			var finger := _arm(1)
			finger.rotation.z = lerpf(finger.rotation.z, -2.35, fade)
			finger.rotation.x = lerpf(finger.rotation.x, 0.5, fade)
			if fmod(t, 2.6) < 1.4:
				body.call("talk", 0.1)
			body.set("face_turn", 0.0)
		&"telegraph_stretch":
			var seconds := float(args.get("seconds", 0.8))
			var k := clampf(t / maxf(seconds, 0.1), 0.0, 1.0)
			var up := sin(minf(k * 1.4, 1.0) * PI * 0.5)
			_aim(0, _ahead(0.3, 1.6 + 0.85 * up, 0.05), up)
			_aim(1, _ahead(-0.3, 1.6 + 0.85 * up, 0.05), up)
			torso.rotation.x += 0.12 * up
			if k > 0.25 and k < 0.9:
				(body.get("_mouth") as Node3D).scale = Vector3(0.8, 5.0, 1.0)
				for eye: Node3D in eyes:
					eye.scale.y = 0.2
		&"walk_to", &"hurry_back":
			if state == &"hurry_back":
				# Elbows pumping, a stiff speed-walk.
				var pump := sin(t * 14.0)
				_arm(0).rotation.x = 0.9 * pump
				_arm(1).rotation.x = -0.9 * pump
				torso.rotation.x -= 0.15
				body.set("mood", "worried")
		&"on_break":
			if _route_done():
				# A coffee, sipped slowly, back to the room.
				var sip := clampf(sin(t * 0.9) * 2.0 - 0.8, 0.0, 1.0)
				_aim(0, _ahead(0.12, 1.15 + sip * 0.4, 0.28 - sip * 0.12), 0.9)
				_show_prop("mug", true)
				face.rotation.x += 0.25 * sip
		&"asleep":
			# Slumped: chin on chest, head lolled a little to one side.
			face.rotation.x -= 0.5
			face.rotation.z += 0.18
			for eye: Node3D in eyes:
				eye.scale.y = 0.08
			torso.rotation.x -= 0.18 + 0.03 * sin(t * 1.4)
			_aim(0, _ahead(0.15, 0.82, 0.38), 0.9)
			_aim(1, _ahead(-0.15, 0.82, 0.38), 0.9)
			_snore(t)
		&"wake":
			if t < 0.45:
				var jolt := sin(t / 0.45 * PI)
				_arm(0).rotation.z += 1.4 * jolt
				_arm(1).rotation.z -= 1.4 * jolt
				(body.get("_hips") as Node3D).position.y += 0.08 * jolt
				for eye: Node3D in eyes:
					eye.scale.y = 1.35
			elif t < 1.4:
				body.set("face_turn", sin((t - 0.45) * 7.0) * 0.6)
			elif t < 2.2:
				_aim(0, _ahead(0.06, head_y + 0.05, 0.12), clampf((t - 1.4) / 0.2, 0.0, 1.0))
				for eye: Node3D in eyes:
					eye.scale.y = 0.3
		&"lunch_bite":
			var bite := clampf(sin(t * TAU / 1.6) * 2.0, 0.0, 1.0)
			_aim(0, _ahead(0.05, head_y - 0.1 + bite * 0.1, 0.25 - bite * 0.12), 0.9)
			_show_prop("sandwich", true)
			if bite < 0.5:
				body.call("talk", 0.08)
		&"lunch_turned":
			_aim(0, _ahead(0.08, head_y - 0.25, 0.25), 0.8)
			_show_prop("sandwich", true)
			if fmod(t, 0.5) < 0.25:
				body.call("talk", 0.06)
		&"lean_toward":
			var dir := _dir_arg()
			var local := global_basis.inverse() * dir if dir != Vector3.ZERO else Vector3.ZERO
			var side := signf(-local.x) if absf(local.x) > 0.01 else 1.0
			# Craning over toward the commotion: the whole upper body tips that way.
			torso.rotation.z = -side * 0.5 * fade
			torso.rotation.x -= 0.1 * fade
			(body.get("_hips") as Node3D).position.x = -side * 0.08 * fade
			body.set("face_turn", -side * 0.55)
			body.set("mood", "raised")
		&"turn_to_cabinet":
			var cabinet := _window_node("Cabinet")
			var drawer := cabinet.global_position + Vector3.UP * 0.75 if cabinet != null else _ahead(0.3, 0.8, 0.6)
			_aim(0, drawer + Vector3(0.0, 0.05 * sin(t * 9.0), 0.0), clampf(t / 0.4, 0.0, 1.0))
			var twitch_at := float(args.get("twitch_at", 1.2))
			if t > twitch_at and t < twitch_at + 0.35:
				body.set("face_turn", -1.0)
		&"twitch_turn_back":
			body.set("mood", "raised")
		&"notice":
			if t < 0.4:
				(body.get("_hips") as Node3D).position.y += 0.06 * sin(t / 0.4 * PI)
			body.set("mood", "raised")
			_aim(0, _ahead(0.2, head_y + 0.2, 0.5), clampf((t - 0.2) / 0.2, 0.0, 1.0) * 0.7)
		&"add_carbon":
			var slide := ease_reach(t, 0.0, 0.4, 1.0)
			_aim(0, _ahead(0.08, 1.02, 0.5 + slide * 0.6), fade)
			_aim(1, _ahead(-0.08, 1.02, 0.5 + slide * 0.6), fade)
			_show_prop("paper", t < 0.6)
			if t > 1.0 and t < 1.05 and not body.call("is_gesturing"):
				body.call("gesture", "scribble")
		&"volley", &"closing_rush":
			var gap := Constants.CLERK_VOLLEY_GAP * (0.7 if state == &"closing_rush" else 1.0)
			var beat := fmod(t, gap) / gap
			var up := 1.0 - absf(beat * 2.0 - 1.0)
			_aim(0, _ahead(0.25, 0.95 + up * 0.35, 0.45), 1.0)
			_aim(1, _ahead(-0.05, 0.88, 0.5), 0.8)
			body.set("mood", "raised")
			if state == &"closing_rush" and t > 2.4:
				body.set("face_turn", sin(t * 5.0) * 0.4)
		&"head_windup_slam":
			var stamp := annex_set.get_node_or_null("HeadDesk/BigStamp") as Node3D if annex_set != null else null
			var held := stamp.global_position + Vector3.UP * 0.32 if stamp != null else _ahead(0.0, 1.9, 0.4)
			_aim(0, held + global_basis * Vector3(-0.05, 0.0, 0.0), 1.0)
			_aim(1, held + global_basis * Vector3(0.05, 0.0, 0.0), 1.0)
			face.rotation.x += 0.2
			if t > 0.25 and t < 0.25 + Constants.ANNEX_BIG_STAMP_HESITATE:
				body.set("mood", "angry")
				body.set("face_turn", 0.12 * sin(t * 18.0))
		&"gasp_whistle":
			if t < 0.4:
				var gasp := sin(t / 0.4 * PI)
				(body.get("_hips") as Node3D).position.y += 0.1 * gasp
				_arm(0).rotation.z += 1.2 * gasp
				_arm(1).rotation.z -= 1.2 * gasp
				for eye: Node3D in eyes:
					eye.scale.y = 1.4
				(body.get("_mouth") as Node3D).scale = Vector3(0.6, 5.0, 1.0)
			else:
				_aim(1, _ahead(0.0, head_y - 0.08, 0.15), clampf((t - 0.4) / 0.15, 0.0, 1.0))
				body.set("mood", "angry")
			if t >= 0.45 and _once("whistle"):
				var whistle_id := "whistle"
				if _Bank.has(whistle_id):
					_play_sfx(whistle_id, global_position + Vector3.UP * 1.5)
		&"walk_hand_out":
			_aim(0, _ahead(0.15, 1.0, 0.7), 0.9)
			body.set("mood", "angry")
		&"take_stamp_back":
			var from: Variant = args.get("from", null)
			if from is Vector3 and t < 0.8:
				_aim(0, from as Vector3 + Vector3.UP * 1.05, 0.9)
				_aim(1, from as Vector3 + Vector3.UP * 1.05, 0.9)
			else:
				_aim(0, _ahead(0.08, 1.05, 0.38), 0.9)
				_aim(1, _ahead(-0.08, 1.05, 0.38), 0.9)
		&"greeter_lead":
			if not _route_done():
				# Leading the way, looking back over his shoulder and beckoning.
				var look_back := clampf(sin(t * 1.3) * 3.0, 0.0, 1.0)
				body.set("face_turn", 1.4 * look_back)
				var beckon := _arm(1)
				beckon.rotation.x = lerpf(beckon.rotation.x, 0.6 + 0.5 * sin(t * 9.0), look_back)
				beckon.rotation.z = lerpf(beckon.rotation.z, -0.9, look_back)
			else:
				_aim(0, _ahead(0.6, 1.2, 0.6), clampf((t - _route_length / Constants.CLERK_WALK_SPEED) / 0.3, 0.0, 1.0) * 0.8)
		&"greeter_offer":
			var reach := ease_reach(t, 0.0, 0.35, 1.6)
			_aim(0, _ahead(0.12, 1.15, 0.3 + reach * 0.35), fade)
			_aim(1, _ahead(-0.12, 1.15, 0.3 + reach * 0.35), fade)
			_show_prop("form", t < 1.0)
			body.set("mood", "raised")
		&"greeter_punch_card":
			var squeeze := clampf(sin(clampf((t - 0.3) / 0.25, 0.0, 1.0) * PI), 0.0, 1.0)
			_aim(0, _ahead(0.05, 1.2, 0.35 - squeeze * 0.04), fade)
			_aim(1, _ahead(-0.05, 1.2, 0.38), fade)
			_show_prop("punch", true)
			if t >= 0.42 and _once("punch"):
				_play_sfx("punch_card", global_position + Vector3.UP * 1.2)
		&"janitor_mop":
			_mop(t, true)


## True the first time it's asked for this moment (one sound per state change).
func _once(what: String) -> bool:
	var key := "%.3f|%s" % [state_at, what]
	if _fired.has(key):
		return false
	if _fired.size() > 32:
		_fired.clear()
	_fired[key] = true
	return true


func _route_done() -> bool:
	return _route.is_empty() or position.distance_to(_route[_route.size() - 1]) < 0.02


## 0 -> 1 over (rise_at, rise_at + rise), back to 0 by back_at.
static func ease_reach(t: float, rise_at: float, rise: float, back_at: float) -> float:
	if t < rise_at:
		return 0.0
	if t < rise_at + rise:
		return sin((t - rise_at) / rise * PI * 0.5)
	if t < back_at:
		return 1.0
	return maxf(0.0, 1.0 - (t - back_at) / 0.25)


func _window_node(child: String) -> Node3D:
	if annex_set == null or not str(name).begins_with("Clerk"):
		return null
	return annex_set.get_node_or_null("Windows/%s/%s" % [str(name).trim_prefix("Clerk"), child]) as Node3D


## The mop swept side to side ahead of him, both hands on the handle.
func _mop(t: float, working: bool) -> void:
	_show_prop("mop", true)
	var sweep := sin(t * (3.2 if working else 0.6)) * (0.45 if working else 0.05)
	var torso := body.get("_torso") as Node3D
	torso.rotation.y = sweep * 0.5
	torso.rotation.x -= 0.15 if working else 0.0
	_aim(0, _ahead(0.15 + sweep * 0.5, 1.0, 0.35), 1.0)
	_aim(1, _ahead(0.05 + sweep * 0.5, 1.25, 0.25), 1.0)
	var mop := _hand_props.get("mop") as Node3D
	if mop != null:
		mop.rotation = Vector3(0.6 + 0.1 * sweep, 0.0, sweep)


func _snore(t: float) -> void:
	if _zs != null:
		_zs.visible = true
		for index: int in _zs.get_child_count():
			var z := _zs.get_child(index) as Node3D
			var k := fmod(t * 0.45 + float(index) / 3.0, 1.0)
			z.position = Vector3(0.12 + k * 0.18, 0.35 + k * 0.45, 0.05)
			z.scale = Vector3.ONE * (0.4 + k * 0.8) * (1.0 - smoothstep(0.75, 1.0, k))
	if _Props.now() >= _next_snore:
		_next_snore = _Props.now() + Constants.CLERK_SNORE_EVERY
		_play_sfx("clerk_snore", global_position + Vector3.UP * 1.2)


# ---------------------------------------------------------------- props

## The small things in hand, all hidden until a state shows one.
func _build_props() -> void:
	var right := _arm(0)
	var left := _arm(1)
	_hand_props["phone"] = _prop(right, "Phone", func(kit: RefCounted) -> void:
		kit.call("box", Vector3(0.0, 0.0, 0.0), Vector3(0.05, 0.2, 0.06), Color(0.2, 0.2, 0.22))
		kit.call("box", Vector3(0.0, 0.1, -0.03), Vector3(0.06, 0.05, 0.05), Color(0.2, 0.2, 0.22))
		kit.call("box", Vector3(0.0, -0.1, -0.03), Vector3(0.06, 0.05, 0.05), Color(0.2, 0.2, 0.22)))
	_hand_props["mug"] = _prop(right, "Mug", func(kit: RefCounted) -> void:
		kit.call("tube", PackedVector3Array([Vector3(0.0, -0.04, -0.05), Vector3(0.0, 0.05, -0.05)]), PackedFloat32Array([0.04, 0.042]), Color(0.95, 0.94, 0.9), 10, {"jitter": 0.0})
		kit.call("box", Vector3(0.0, 0.048, -0.05), Vector3(0.06, 0.004, 0.06), Color(0.3, 0.18, 0.1)))
	_hand_props["sandwich"] = _prop(right, "Sandwich", func(kit: RefCounted) -> void:
		kit.call("box", Vector3(0.0, 0.0, -0.06), Vector3(0.12, 0.025, 0.1), Color(0.92, 0.8, 0.55))
		kit.call("box", Vector3(0.0, 0.02, -0.06), Vector3(0.13, 0.015, 0.11), Color(0.4, 0.7, 0.3))
		kit.call("box", Vector3(0.0, 0.04, -0.06), Vector3(0.12, 0.025, 0.1), Color(0.92, 0.8, 0.55)))
	_hand_props["paper"] = _prop(right, "Paper", func(kit: RefCounted) -> void:
		kit.call("box", Vector3(0.0, -0.02, -0.08), Vector3(0.2, 0.004, 0.26), Color(0.97, 0.96, 0.92)))
	_hand_props["paper_left"] = _prop(left, "PaperLeft", func(kit: RefCounted) -> void:
		kit.call("box", Vector3(0.0, -0.02, -0.08), Vector3(0.2, 0.004, 0.26), Color(0.97, 0.96, 0.92)))
	_hand_props["form"] = _prop(right, "Form", func(kit: RefCounted) -> void:
		kit.call("box", Vector3(0.0, 0.0, -0.1), Vector3(0.22, 0.3, 0.012), Color(0.55, 0.36, 0.2))
		kit.call("box", Vector3(0.0, -0.01, -0.093), Vector3(0.19, 0.24, 0.004), Color(0.97, 0.96, 0.92)))
	_hand_props["punch"] = _prop(right, "Punch", func(kit: RefCounted) -> void:
		kit.call("box", Vector3(0.0, 0.0, -0.05), Vector3(0.06, 0.05, 0.12), Color(0.2, 0.3, 0.6))
		kit.call("box", Vector3(0.0, 0.04, -0.07), Vector3(0.05, 0.02, 0.1), Color(0.75, 0.78, 0.82)))
	_hand_props["mop"] = _prop(right, "Mop", func(kit: RefCounted) -> void:
		kit.call("tube", PackedVector3Array([Vector3(0.0, 0.25, 0.0), Vector3(0.0, -1.1, 0.0)]), PackedFloat32Array([0.018, 0.018]), Color(0.75, 0.6, 0.35), 6, {"jitter": 0.0})
		kit.call("blob", Vector3(0.0, -1.18, 0.0), Vector3(0.16, 0.08, 0.12), Color(0.85, 0.85, 0.8), {"detail": 1, "lumps": 0.6, "seed": 5}))
	# Z's for the sleeper: three little zigzags of three bars each.
	_zs = Node3D.new()
	_zs.name = "Zs"
	(body.get("_head_root") as Node3D).add_child(_zs)
	for index: int in 3:
		var kit := _MeshKit.new()
		kit.box(Vector3(0.0, 0.05, 0.0), Vector3(0.1, 0.018, 0.012), Color(0.95, 0.95, 1.0))
		kit.box(Vector3(0.0, -0.05, 0.0), Vector3(0.1, 0.018, 0.012), Color(0.95, 0.95, 1.0))
		kit.box(Vector3(0.0, 0.0, 0.0), Vector3(0.13, 0.016, 0.012), Color(0.95, 0.95, 1.0), Basis(Vector3.BACK, 0.75))
		var view := _Stylized.instance(kit.commit(), {"roughness": 0.4})
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var holder := Node3D.new()
		holder.add_child(view)
		holder.rotation.y = PI
		_zs.add_child(holder)
	_zs.visible = false


func _prop(arm: Node3D, prop_name: String, shape: Callable) -> Node3D:
	var kit := _MeshKit.new()
	shape.call(kit)
	var view := _Stylized.instance(kit.commit(), {"roughness": 0.7})
	view.name = prop_name
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arm.add_child(view)
	view.position = Vector3(0.0, -0.53, -0.02)
	view.visible = false
	return view


func _show_prop(prop_name: String, on: bool) -> void:
	if prop_name == "":
		for key: String in _hand_props:
			(_hand_props[key] as Node3D).visible = false
		return
	var prop := _hand_props.get(prop_name) as Node3D
	if prop != null:
		prop.visible = on


## A positional one-shot from the sfx group, while anyone can hear it.
func _play_sfx(id: String, at: Vector3) -> void:
	if not is_inside_tree() or not is_visible_in_tree():
		return
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play_at", id, at)
