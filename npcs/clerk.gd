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
	&"head_pleased",
]
## States in which a clerk or the Head NICE BOY sits (the rest stand or walk).
const SEATED: Array[StringName] = [
	&"counter_idle", &"wave_up", &"take_form", &"stamp", &"hand_back", &"peer_form",
	&"head_shake_point", &"phone", &"asleep", &"wake", &"lunch_bite", &"lunch_turned",
	&"lean_toward", &"turn_to_cabinet", &"twitch_turn_back", &"notice", &"add_carbon",
	&"volley", &"closing_rush", &"head_pleased",
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
## The eased head turn, and the sidestep round a person in the way (R2b).
var _face_turn: float = 0.0
var _avoid := Vector3.ZERO
## The wide solid ball at head height (off while at his seat or desk).
var _head_shape: CollisionShape3D
## Walking round someone: the side he steps to (1 or -1), 0 when nobody's near.
var _side: int = 0
## R2c annex: where the body stands before any stand-off (the route's point, or
## where he stopped); position is this plus _avoid.
var _base := Vector3.ZERO
## Walking home first because the state wants him at his seat or post.
var _homing: bool = false
## A walk's speed fitted to arrive in time (m/s), or negative for the state's own.
var _speed_override: float = -1.0
var _sheet_on: bool = false
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
	# At his desk the Head NICE BOY's hands are for the big stamp: the raid's
	# megaphone stays in the van (R2c annex: it blocked his face at the slam).
	var megaphone := body.get("_megaphone") as Node3D
	if megaphone != null:
		megaphone.visible = false
	add_to_group("annex_staff")
	# Solid to players (R2c annex: you walked into a NICE BOY's head): a capsule on
	# the pad-wall layer, which people mask and thrown things and rays don't.
	var solid := AnimatableBody3D.new()
	solid.name = "Solid"
	solid.sync_to_physics = false
	solid.collision_layer = Constants.PAD_WALL_LAYER
	solid.collision_mask = 0
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = Constants.CLERK_SOLID_RADIUS
	capsule.height = Constants.CLERK_SOLID_HEIGHT
	shape.shape = capsule
	shape.position = Vector3(0.0, Constants.CLERK_SOLID_HEIGHT * 0.5, 0.0)
	solid.add_child(shape)
	# And wider at the head (review: walking into him, his face still filled the
	# view from 0.4 m): a camera stops CLERK_SOLID_HEAD_RADIUS off his face.
	# Off at a seat or desk (a visitor at the Head NICE BOY's desk stands closer).
	_head_shape = CollisionShape3D.new()
	var head_ball := SphereShape3D.new()
	head_ball.radius = Constants.CLERK_SOLID_HEAD_RADIUS
	_head_shape.shape = head_ball
	_head_shape.position = Vector3(0.0, Constants.CLERK_SOLID_HEAD_Y, 0.0)
	solid.add_child(_head_shape)
	add_child(solid)
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
	_base = at
	_avoid = Vector3.ZERO
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
	_homing = false
	_speed_override = -1.0
	match next:
		&"walk_to", &"on_break", &"walk_hand_out":
			_walk(_target(args.get("to", null)), args.get("face", null))
			# A break's walk out arrives part way into it (R2c: at the plain walk
			# he was still on his way when his window reopened).
			if args.has("arrive_in"):
				_fit_speed(float(args["arrive_in"]))
		&"hurry_back":
			_walk(_home_pos, _home_yaw)
			# Seated by the end of RETURN, whatever the way back (R2c: the lamp lit
			# over an empty stool while he was still walking).
			if args.has("seconds"):
				_fit_speed(float(args["seconds"]) - SIT_SECONDS - 0.1)
		&"greeter_lead":
			_walk_path("GreeterPath", bool(args.get("reverse", false)))
		&"janitor_mop":
			_walk_path("JanitorPath", false)
		&"take_stamp_back":
			_walk(_target(args.get("to", null)), _home_yaw)
		&"greeter_offer":
			# A step aside to hand the clipboard over face to face (R2b).
			if args.has("to"):
				_walk(_target(args["to"]), args.get("face", null))
	# A state that wants him at his seat (or the Head NICE BOY at his desk) while
	# he's somewhere else walks him there first (R2c: the desk approval played at
	# the water cooler, an OPEN window's clerk stood frozen in mid-walk).
	if _route.is_empty() and _wants_home(next) and Vector2(_base.x - _home_pos.x, _base.z - _home_pos.z).length() > 0.15:
		_walk(_home_pos, _home_yaw)
		_homing = true
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


## States that want a clerk on his stool, or the Head NICE BOY at his desk.
func _wants_home(next: StringName) -> bool:
	if role != "clerk" and role != "head":
		return false
	return SEATED.has(next) or next == &"head_windup_slam" or next == &"telegraph_stretch"


## How far a seated body drops: a clerk's tall stool, the Head NICE BOY's chair.
func _sit_drop() -> float:
	return Constants.CLERK_STOOL_DROP if role == "clerk" else SIT_DROP


## A walk just started gets the speed that covers it in `seconds` (after
## standing up), between a plain walk and a rush.
func _fit_speed(seconds: float) -> void:
	var avail := seconds - _walk_delay
	if avail > 0.05 and _route_length > 0.01:
		_speed_override = clampf(_route_length / avail, Constants.CLERK_WALK_SPEED, Constants.CLERK_RUSH_MAX)


## Walk from where this one stands to `to` (parent space), the set's route
## through the staff door when the counter wall is in the way.
func _walk(to: Vector3, face: Variant) -> void:
	_route_from = _base
	_walk_delay = SIT_SECONDS if _sit > 0.5 else 0.0
	var points := PackedVector3Array([to])
	if annex_set != null and annex_set.has_method("route") and get_parent() != null:
		var from_set := annex_set.to_local((get_parent() as Node3D).to_global(_base))
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
	_route_from = _base
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
	_stand_off(delta)
	_seat(delta)
	_pose(t, delta)
	# The head turns ease, whatever the state asked for (R2b: a one-frame snap
	# sideways between a stamp and the next state).
	var want := float(body.get("face_turn"))
	_face_turn = want if hold_t >= 0.0 else lerpf(_face_turn, want, 1.0 - exp(-delta * Constants.CLERK_FACE_EASE))
	body.set("face_turn", _face_turn)


## Staff step round people (R2b) and each other (R2c annex): anyone standing or
## walking (not seated) within CLERK_STAND_OFF of a player eases sideways out of
## their way, and two standing staff within CLERK_STAFF_GAP ease apart, each half
## the way (R2c: the Head NICE BOY stood fused with a clerk at the cooler). Back
## onto their line once clear. Their capsule (Solid) stops a player walking in.
## Cosmetic: the host never reads these bodies.
func _stand_off(delta: float) -> void:
	var push := Vector3.ZERO
	var parent := get_parent() as Node3D
	if _sit < 0.5 and is_inside_tree() and parent != null:
		var me := parent.to_global(_base)
		# Round people, never through them (review: walking into the Greeter, or
		# him walking into you, the push flipped sides as you crossed his line and
		# he jumped half a metre through you). Walking, he steps aside, square to
		# his way, to the side he started on; standing, he keeps to the side he's
		# already stepped to.
		var last := _route[_route.size() - 1] if not _route.is_empty() else _base
		var walking := not _route.is_empty() and Vector2(_base.x - last.x, _base.z - last.z).length() > 0.05
		var lateral := parent.global_basis * Vector3(cos(_yaw), 0.0, -sin(_yaw))
		var held_side := parent.global_basis * _avoid
		var near := false
		for node: Node in get_tree().get_nodes_in_group("players"):
			var person := node as Node3D
			if person == null or not person.is_visible_in_tree():
				continue
			var away := me - person.global_position
			away.y = 0.0
			var d := away.length()
			if d >= Constants.CLERK_STAND_OFF:
				continue
			near = true
			var amount := Constants.CLERK_STAND_OFF - d
			if walking:
				if _side == 0:
					_side = 1 if lateral.dot(away) >= 0.0 else -1
				push += lateral * float(_side) * amount
				continue
			var dir := away / d if d > 0.01 else (held_side.normalized() if held_side.length() > 0.01 else lateral)
			if held_side.length() > 0.1 and dir.dot(held_side) < 0.0:
				var keep := held_side.normalized()
				dir -= keep * 2.0 * dir.dot(keep)
			push += dir * amount
		if not near:
			_side = 0
		for node: Node in get_tree().get_nodes_in_group("annex_staff"):
			var other := node as Node3D
			if other == self or other == null or float(other.get("_sit")) >= 0.5 or not other.is_visible_in_tree():
				continue
			var away := me - other.global_position
			away.y = 0.0
			var d := away.length()
			if d < Constants.CLERK_STAFF_GAP:
				# Exactly on top of each other: part by name, the same on every peer.
				var dir := away / d if d > 0.01 else Vector3.RIGHT * (1.0 if str(name) < str(other.name) else -1.0)
				push += dir * (Constants.CLERK_STAFF_GAP - d) * 0.5
		push = parent.global_basis.inverse() * push
	_avoid = _avoid.lerp(Vector3(push.x, 0.0, push.z), 1.0 - exp(-delta * Constants.CLERK_STAND_OFF_EASE))
	position = _base + _avoid
	if _head_shape != null:
		var off := not (role == "greeter" or role == "janitor" or _base.distance_to(_home_pos) > 0.6)
		if _head_shape.disabled != off:
			_head_shape.set_deferred(&"disabled", off)


# ---------------------------------------------------------------- moving

func _locomote(t: float, delta: float) -> void:
	var walking := not _route.is_empty()
	if walking:
		var speed := Constants.CLERK_HURRY_SPEED if state == &"hurry_back" else Constants.CLERK_WALK_SPEED
		if state == &"janitor_mop":
			speed = Constants.CLERK_WALK_SPEED * 0.45
		if _homing:
			speed = Constants.CLERK_HOME_SPEED
		if _speed_override > 0.0:
			speed = _speed_override
		# Ease into the walk and stand up first (the stool), then go.
		var travelled := maxf(0.0, t - _walk_delay) * speed
		travelled = minf(travelled, _route_length)
		var at: Array = _along(travelled)
		_base = Vector3((at[0] as Vector3).x, _home_pos.y, (at[0] as Vector3).z)
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
			_route_from = _base
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
				var toward: Vector3 = (get_parent() as Node3D).to_local(at) - _base
				return atan2(toward.x, toward.z)
	if _base.distance_to(_home_pos) < 0.3:
		return _home_yaw
	return _yaw


func _dir_arg() -> Vector3:
	var dir: Variant = args.get("dir", Vector3.ZERO)
	if dir is Vector3:
		return (dir as Vector3).normalized() if (dir as Vector3).length() > 0.01 else Vector3.ZERO
	return Vector3.ZERO


## Sitting down and standing up take SIT_SECONDS, never a frame.
func _seat(delta: float) -> void:
	# Arrived (a walk home's route stays on the list) counts as there (R2c: a clerk
	# back from his break used to stay standing until the next state).
	var walking := not _route.is_empty() and not _route_done()
	var want := 1.0 if SEATED.has(state) and not walking and _base.distance_to(_home_pos) < 0.08 and (role == "clerk" or role == "head") else 0.0
	if state == &"telegraph_stretch":
		want = 0.0
	_sit = want if _snap_seat else move_toward(_sit, want, delta / SIT_SECONDS)
	_snap_seat = false
	var k := smoothstep(0.0, 1.0, _sit)
	var hips := body.get("_hips") as Node3D
	var head := body.get("_head_root") as Node3D
	var legs: Array = body.get("_legs")
	hips.position.y -= _sit_drop() * k
	head.position.y -= _sit_drop() * k
	for leg: Node3D in legs:
		leg.rotation.x = lerpf(leg.rotation.x, SIT_LEGS, k)


# ---------------------------------------------------------------- posing

func _arm(side: int) -> Node3D:
	# side 0 right, 1 left (CartoonBody keeps [left, right]).
	var arms: Array = body.get("_arms")
	return arms[1 - side] as Node3D


## Swing an arm (0 right, 1 left) to point its hand at a world point.
func _aim(side: int, target: Vector3, weight: float, max_reach: float = 1.08) -> void:
	var arm := _arm(side)
	var parent := arm.get_parent() as Node3D
	var local := parent.global_transform.affine_inverse() * target - arm.position
	if local.length() < 0.01:
		return
	var k := clampf(weight, 0.0, 1.0)
	arm.quaternion = arm.quaternion.slerp(Quaternion(Vector3.DOWN, local.normalized()), k)
	# The arm has no elbow: a near target shortens it so the hand lands there.
	var reach := clampf(local.length() / ARM_LENGTH, 0.62, max_reach)
	arm.scale = Vector3(1.0, lerpf(1.0, reach, k), 1.0)


## How much the body's gesture named gesture_name has the arms, 0 to 1: up over
## its first CLERK_GESTURE_BLEND seconds, down over its last.
func _gesture_blend(gesture_name: String) -> float:
	if not bool(body.call("is_gesturing")) or str(body.call("current_gesture")) != gesture_name:
		return 0.0
	var at := float(body.get("_gesture_time"))
	var length := float(body.get("_gesture_length"))
	var blend := Constants.CLERK_GESTURE_BLEND
	return smoothstep(0.0, blend, at) * smoothstep(0.0, blend, length - at)


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
	var head_y := 1.6 - _sit_drop() * sat
	body.position = Vector3.ZERO
	var clipboard := body.get("_clipboard") as Node3D
	if clipboard != null:
		# The clipboard never leaves the left hand (nothing pops); the janitor has a mop instead.
		clipboard.visible = role != "janitor"
	if role == "head" and _sheet_on and state != &"head_windup_slam":
		_sheet_on = false
		var big := _big_stamp()
		if big != null:
			big.call("set_sheet", false, false)
	if _homing and not _route_done():
		# On his way back to his seat: just walking, the state's pose once there.
		return
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
			# Then the body's scribble (head down, the board tipped up to the face),
			# written here at the desk: the board held up off the desktop in the
			# left hand, the pencil hand scratching at it. The hands ease from the
			# slide into it and back out as the gesture starts and ends.
			var write := _gesture_blend("scribble")
			var board := _ahead(-0.1, 0.93, 0.46)
			var pencil := _ahead(0.02 + 0.03 * sin(t * 31.0), 0.97 + 0.02 * sin(t * 23.0), 0.44)
			_aim(0, _ahead(0.08, 1.02, 0.5 + slide * 0.6).lerp(pencil, write), fade)
			_aim(1, _ahead(-0.08, 1.02, 0.5 + slide * 0.6).lerp(board, write), fade)
			_show_prop("paper", t < 0.6)
			if t > 1.0 and t < 1.05 and not body.call("is_gesturing"):
				body.call("gesture", "scribble")
		&"volley", &"closing_rush":
			# His hand rides the window's stamp through every slam (R2b: he sat
			# still while the box changed); the body pumps with it, the free hand
			# feeds the form.
			var stamp := _window_node("Stamp")
			var rise := 0.0
			if stamp != null:
				rise = clampf((stamp.position.y - (_Props.STAMP_SPOT.y + 0.026)) / 0.24, -0.1, 1.5)
				_aim(0, stamp.global_position + Vector3.UP * 0.14, clampf(t / 0.15, 0.0, 1.0))
			else:
				var beat := fmod(t, Constants.CLERK_VOLLEY_GAP) / Constants.CLERK_VOLLEY_GAP
				rise = 1.0 - absf(beat * 2.0 - 1.0)
				_aim(0, _ahead(0.25, 0.95 + rise * 0.35, 0.45), 1.0)
			_aim(1, _ahead(-0.08, 0.9, 0.5), 0.8)
			torso.rotation.x += 0.12 * rise - 0.05
			(body.get("_hips") as Node3D).position.y += 0.03 * rise
			body.set("mood", "raised" if state == &"volley" else "worried")
			if state == &"closing_rush" and t > 2.4:
				body.set("face_turn", sin(t * 5.0) * 0.4)
		&"head_windup_slam":
			_approve_pose(t, fade, torso, face)
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
		&"head_pleased":
			# P1 catch (audit r2): APPROVED, slammed. He sits back in his chair, hands
			# laced behind his head, chin up, a slow satisfied nod at his own work.
			var settle := smoothstep(0.0, 0.5, t)
			torso.rotation.x += 0.16 * settle
			face.rotation.x -= (0.1 + 0.04 * sin(t * 3.2)) * settle
			_aim(0, _ahead(0.14, head_y + 0.02, -0.12), settle * fade)
			_aim(1, _ahead(-0.14, head_y + 0.02, -0.12), settle * fade)
			body.set("mood", "raised")
			body.set("face_turn", 0.15 * sin(t * 0.8) * settle)
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
			# Holds the clipboard out as he arrives beside you; it leaves his hands
			# on the frame it starts up into yours (Constants.ANNEX_FORM_HANDOFF_AT).
			var handoff := Constants.ANNEX_FORM_HANDOFF_AT
			var reach := ease_reach(t, maxf(handoff - 0.35, 0.0), 0.35, handoff + 0.5)
			_aim(0, _ahead(0.12, 1.15, 0.3 + reach * 0.4), maxf(fade, reach))
			_aim(1, _ahead(-0.12, 1.15, 0.3 + reach * 0.4), maxf(fade, reach))
			# Gone from his hands on the frame yours takes it from there (R2c annex).
			_show_prop("form", t < handoff)
			body.set("mood", "raised")
			if t > handoff + 0.1 and t < handoff + 0.6:
				body.set("face_turn", 0.0)
		&"greeter_punch_card":
			var squeeze := clampf(sin(clampf((t - 0.3) / 0.25, 0.0, 1.0) * PI), 0.0, 1.0)
			_aim(0, _ahead(0.05, 1.2, 0.35 - squeeze * 0.04), fade)
			_aim(1, _ahead(-0.05, 1.2, 0.38), fade)
			_show_prop("punch", true)
			if t >= 0.42 and _once("punch"):
				_play_sfx("punch_card", global_position + Vector3.UP * 1.2)
		&"janitor_mop":
			_mop(t, true)


func _big_stamp() -> Node3D:
	return annex_set.get_node_or_null("HeadDesk/BigStamp") as Node3D if annex_set != null else null


## The Head NICE BOY approves a form (R2c annex: the stamp used to rise and slam
## by itself at an empty desk). He stands and steps to his desk's edge, reads the
## form held up, lays it on the pad and takes the big stamp's knob in both hands,
## raises it over the desk, holds his breath, slams it down on the form (the
## KA-CHUNK is the stamp's own cue, on this same frame), holds it there, lets go.
## The stamp goes where his hands put it, every frame; the sheet on the pad is
## the form he laid down, APPROVED, NICELY on it after the slam.
func _approve_pose(t: float, fade: float, torso: Node3D, face: Node3D) -> void:
	var read := float(args.get("read", 0.0))
	var lift := Constants.ANNEX_BIG_STAMP_LIFT_SECONDS
	var hesitate := Constants.ANNEX_BIG_STAMP_HESITATE
	var hit := read + lift + hesitate + Constants.ANNEX_BIG_STAMP_SLAM_SECONDS
	var release := hit + Constants.ANNEX_HEAD_SLAM_HOLD
	# The step to the desk and, once he's let go, back.
	var step := smoothstep(0.0, 0.4, t) * (1.0 - smoothstep(release + 0.2, release + 0.6, t))
	body.position = Vector3(0.0, 0.0, Constants.ANNEX_HEAD_DESK_STEP * step)
	var stamp := _big_stamp()
	var home := _base.distance_to(_home_pos) < 0.3
	var lay := read * Constants.ANNEX_HEAD_LAY_AT
	if t < lay or stamp == null or not home:
		# Reading it, held up, a squint.
		torso.rotation.x -= 0.2 * fade
		face.rotation.x -= 0.15 * fade
		body.set("squinting", t > 0.25)
		_aim(0, _ahead(0.1, 1.15, 0.42 + 0.3 * step), fade)
		_aim(1, _ahead(-0.1, 1.15, 0.42 + 0.3 * step), fade)
		_show_prop("paper", true)
		if t > lay * 0.6:
			body.set("face_turn", 0.18 * sin(t * 6.0))
		return
	var desk := stamp.get_parent() as Node3D
	var rest := desk.to_global(stamp.call("rest") as Vector3)
	var toward := global_position - rest
	toward.y = 0.0
	toward = toward.normalized() if toward.length() > 0.01 else Vector3.ZERO
	# Up over his right shoulder, block at his brow: his face (the grin, then the
	# held breath) stays clear of it from the visitor spot.
	var right := global_basis * Vector3(-1.0, 0.0, 0.0)
	var top := rest + toward * Constants.ANNEX_HEAD_RAISE_BACK + right * Constants.ANNEX_HEAD_RAISE_SIDE + Vector3.UP * Constants.ANNEX_HEAD_RAISE
	var at := rest
	var since := t - read
	if since >= 0.0 and since < lift:
		at = rest.lerp(top, 1.0 - pow(1.0 - since / lift, 2.0))
	elif since >= lift and since < lift + hesitate:
		# The held breath: up there, trembling with it.
		at = top + Vector3(0.012 * sin(t * 47.0), 0.01 * sin(t * 31.0), 0.0)
		body.set("mood", "angry")
		body.set("face_turn", 0.12 * sin(t * 18.0))
	elif t >= read + lift + hesitate and t < hit:
		var k := (t - read - lift - hesitate) / Constants.ANNEX_BIG_STAMP_SLAM_SECONDS
		at = top.lerp(rest, k * k)
	elif t >= hit:
		# The squash on contact, settling.
		var settle := t - hit
		at = rest + Vector3.UP * (-0.008 * exp(-settle * 18.0) * cos(settle * 40.0))
	# Puppeted only while the stamp is his to slam (a slam set going at the raise).
	if since >= -0.05 and t < release + 0.05:
		stamp.global_position = at
	_sheet_on = t < release + 0.5
	stamp.call("set_sheet", _sheet_on, t >= hit)
	# Both hands on the block's ends (a big stamp is two-handed) from the lay down
	# to the release, then back to his sides.
	var block := at + Vector3.UP * 0.03
	var grip := smoothstep(lay, read, t) * (1.0 - smoothstep(release, release + 0.25, t))
	var side := right * 0.09
	# A cartoon's arms stretch to keep hold of it up there.
	_aim(0, block + side, grip, Constants.ANNEX_HEAD_ARM_STRETCH)
	_aim(1, block - side, grip, Constants.ANNEX_HEAD_ARM_STRETCH)
	# Leaning over the desk to reach it, up with it, and his weight into the slam.
	var low := clampf(1.0 - (at.y - rest.y) / Constants.ANNEX_HEAD_RAISE, 0.0, 1.0)
	var lunge := 1.0 - smoothstep(0.0, 0.25, absf(t - hit)) if t > read + lift + hesitate - 0.05 else 0.0
	torso.rotation.x -= (0.3 * low + 0.2 * lunge) * grip
	face.rotation.x += 0.15 * grip


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
	return _route.is_empty() or _base.distance_to(_route[_route.size() - 1]) < 0.02


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


## A thing in his hand by name ("form", "paper", ...), shown or not: where the
## Greeter's clipboard is when it leaves his hands for yours.
func held_prop(prop_name: String) -> Node3D:
	return _hand_props.get(prop_name) as Node3D


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
