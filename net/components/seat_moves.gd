extends RefCounted

## Authority: whoever draws it; pure geometry and timing, cosmetic. How a body
## gets into, out of and between the seats of a truck (fx-chefty, docs/GAME.md
## "Getting in and out of Chefty"): every peer works the same move out from the
## same few numbers when the seats change, and draws it on its own clock, the
## way the legacy ride's climbs are drawn (net/components/ride.gd). Nothing here
## is sent or decides anything.
##
## A move is a list of legs in the truck's own space (its body's: y 0 is the
## ground under its wheels, -Z its nose), played one after another:
##   walk   on the ground from a to b (a step or two to the door or the rail);
##   in     a hop up into a seat: the step off a seat (player.gd step_down_point)
##          played backward, so the knees bend on the ground first, the body
##          rises over the rail (or onto the cab's sill and slides in sitting),
##          and the knees take the landing in the seat;
##   out    the step off a seat, forward (a hired hand leaving the bed for the wheel);
##   slide  seat to seat inside the truck: along the bench sitting, or a little
##          hop across the bed.
## sample() says where the body is, which way it faces, and what it's doing.

const _Vehicles = preload("res://props/vehicles.gd")
const _StepDown = preload("res://net/components/step_down.gd")
## The cartoon poses (player/cartoon_body.gd sit()): on your feet, sitting, riding standing.
const POSE_STAND: int = 0
const POSE_SIT: int = 1
const POSE_BED: int = 2

## player.gd, for its step-off curve (loaded when first needed: player.gd's own
## preloads reach back to the components).
static var _player_script: GDScript = null


static func _hop_point(seat: Vector3, ground: Vector3, k: float, path: Vector4, timing: PackedFloat32Array) -> Vector3:
	if _player_script == null:
		_player_script = load("res://player/player.gd") as GDScript
	return _player_script.call("step_down_point", seat, ground, k, path, timing)


static func _hop_timing(seat_y: float, ground_y: float, path: Vector4) -> PackedFloat32Array:
	if _player_script == null:
		_player_script = load("res://player/player.gd") as GDScript
	return _player_script.call("hop_timing", seat_y, ground_y, path)


## Climbing in from where someone stands (from, truck space; yaw their facing in
## the truck's space) to a seat: a few steps to the door (a cab seat) or to just
## outside the rail (the bed), then the hop in.
static func board(from: Vector3, yaw: float, seat: Vector3, seat_yaw: float, cab: bool, door: Vector3) -> Dictionary:
	var ground_y := from.y
	var stand := Vector3(door.x, ground_y, door.z) if cab else _beside_seat(from, seat)
	var legs: Array = []
	_walk_round(legs, from, stand)
	legs.append(_in_leg(seat, stand, cab))
	return _finish(legs, yaw, seat_yaw)


## From one seat to another (a slide over, a swap, a shuffle down the bed, or a
## hired hand going from the bed to the wheel). Same part of the truck: a slide.
## Bed to cab or back: out over the rail (or the door), round on the ground, and in.
static func shift(from_seat: Vector3, from_cab: bool, from_yaw: float, to_seat: Vector3, to_cab: bool, to_yaw: float, door: Vector3) -> Dictionary:
	var legs: Array = []
	if from_cab == to_cab:
		var seconds := Constants.CHEFTY_SEAT_SLIDE_SECONDS * clampf(from_seat.distance_to(to_seat) / Constants.CHEFTY_SEAT_SLIDE_SPAN, 0.6, 1.6)
		legs.append({"kind": "slide", "a": from_seat, "b": to_seat, "s": seconds, "cab": from_cab})
		return _finish(legs, from_yaw, to_yaw)
	# Over the rail on the bed seat's own side (straight across the bed it's a
	# leap over the far rail), and round the front of the cab when the door is
	# on the other side.
	var at_door := Vector3(door.x, 0.0, door.z)
	if from_cab:
		legs.append(_out_leg(from_seat, at_door, true))
		var rail := Vector3(_side_of(to_seat.x) * Constants.CHEFTY_CLIMB_RAIL_OUT, 0.0, to_seat.z)
		_walk_round(legs, at_door, rail)
		legs.append(_in_leg(to_seat, rail, false))
	else:
		var rail := Vector3(_side_of(from_seat.x) * Constants.CHEFTY_CLIMB_RAIL_OUT, 0.0, from_seat.z)
		legs.append(_out_leg(from_seat, rail, false))
		_walk_round(legs, rail, at_door)
		legs.append(_in_leg(to_seat, at_door, true))
	return _finish(legs, from_yaw, to_yaw)


## fx-w9: off a bed seat onto the ground beside the truck (a hired hand at the
## yard): the step off the seat, over the rail, the knees taking the landing.
static func alight(seat: Vector3, seat_yaw: float, ground: Vector3, yaw_to: float) -> Dictionary:
	return _finish([_out_leg(seat, ground, false)], seat_yaw, yaw_to)


static func _side_of(x: float) -> float:
	return -1.0 if x < 0.0 else 1.0


## On foot from a to b beside the truck: straight along one side, or round the
## front of the cab from one side to the other.
static func _walk_round(legs: Array, a: Vector3, b: Vector3) -> void:
	var half := Constants.CHEFTY_CLIMB_SIDE_X
	var a_side := absf(a.x) > half
	var b_side := absf(b.x) > half
	if a_side == b_side and (not a_side or signf(a.x) == signf(b.x)):
		# Along one side, or from the front to the front (the back to the back).
		_add_walk(legs, a, b)
		return
	if a_side and b_side:
		# Side to side: round the nose or the tailgate, whichever's nearer.
		var end_z := Constants.CHEFTY_CLIMB_ROUND_FRONT_Z if a.z + b.z < 0.0 else Constants.CHEFTY_CLIMB_ROUND_BACK_Z
		var corner_a := Vector3(a.x, a.y, end_z)
		var corner_b := Vector3(b.x, b.y, end_z)
		_add_walk(legs, a, corner_a)
		_add_walk(legs, corner_a, corner_b)
		_add_walk(legs, corner_b, b)
		return
	# From the front or the back round the corner to a side, or back again.
	var corner := Vector3(b.x, a.y, a.z) if b_side else Vector3(a.x, a.y, b.z)
	_add_walk(legs, a, corner)
	_add_walk(legs, corner, b)


## How long a move takes (s).
static func seconds(move: Dictionary) -> float:
	return float(move.get("seconds", 0.0))


## Where the move has the body t seconds in: {pos (truck space), yaw (truck
## space), pose (POSE_*), anim ("idle", "walk", "crouch", "air"), done}.
static func sample(move: Dictionary, t: float) -> Dictionary:
	var legs: Array = move.get("legs", [])
	var total := seconds(move)
	var yaw_to := float(move.get("yaw_to", 0.0))
	# Which way the body faces, turned smoothly leg by leg (a turn never happens in
	# a frame): walking, it turns to the way it goes over CHEFTY_CLIMB_TURN_SECONDS;
	# over a hop or a slide, it turns to the seat's way.
	var facing := float(move.get("yaw_from", 0.0))
	var left := t
	for index: int in legs.size():
		var leg: Dictionary = legs[index]
		var s := float(leg["s"])
		var last := index == legs.size() - 1
		var into := left if last else minf(left, s)
		var aim := yaw_to
		var turn := smoothstep(0.0, 1.0, clampf(into / maxf(s, 0.001), 0.0, 1.0))
		if str(leg["kind"]) == "walk":
			var dir := (leg["b"] as Vector3) - (leg["a"] as Vector3)
			# A step or two is taken sideways, the head kept where it looked; a
			# longer walk round the truck faces the way it goes.
			aim = atan2(-dir.x, -dir.z) if Vector2(dir.x, dir.z).length() > Constants.CHEFTY_CLIMB_FACE_WALK_MIN else facing
			turn = smoothstep(0.0, 1.0, clampf(into / maxf(minf(Constants.CHEFTY_CLIMB_TURN_SECONDS, s), 0.001), 0.0, 1.0))
		var yaw := lerp_angle(facing, aim, turn)
		if left > s and not last:
			left -= s
			facing = yaw
			continue
		var out := _leg_point(leg, clampf(left / maxf(s, 0.001), 0.0, 1.0))
		out["yaw"] = yaw
		out["done"] = t >= total
		return out
	return {"pos": Vector3.ZERO, "yaw": yaw_to, "pose": POSE_STAND, "anim": "idle", "done": true}


# ---------------------------------------------------------------- legs

static func _leg_point(leg: Dictionary, k: float) -> Dictionary:
	match str(leg["kind"]):
		"walk":
			return {"pos": (leg["a"] as Vector3).lerp(leg["b"] as Vector3, k), "pose": POSE_STAND, "anim": "walk"}
		"slide":
			var a: Vector3 = leg["a"]
			var b: Vector3 = leg["b"]
			var eased := smoothstep(0.0, 1.0, k)
			var at := a.lerp(b, eased)
			if not bool(leg["cab"]):
				at.y += Constants.CHEFTY_SEAT_SHUFFLE_HOP * 4.0 * eased * (1.0 - eased)
			return {"pos": at, "pose": POSE_SIT if bool(leg["cab"]) else POSE_BED, "anim": "idle" if bool(leg["cab"]) or k <= 0.1 or k >= 0.9 else "air"}
		"in":
			# The step off, played backward.
			return _hop_state(leg, 1.0 - k)
		"out":
			return _hop_state(leg, k)
	return {"pos": Vector3.ZERO, "pose": POSE_STAND, "anim": "idle"}


## Where a step off the seat (k 0 on the seat .. 1 on the ground) has the body,
## and its pose: sitting while still inside the cab's door, the bed's riding
## stance while the feet are still on the seat, else on your feet; the knees
## bent at either end, flying between.
static func _hop_state(leg: Dictionary, k: float) -> Dictionary:
	var seat: Vector3 = leg["seat"]
	var ground: Vector3 = leg["ground"]
	var path: Vector4 = leg["path"]
	var timing: PackedFloat32Array = leg["timing"]
	var at := _hop_point(seat, ground, k, path, timing)
	var crouch := timing[0]
	var land := timing[1]
	var cab := bool(leg["cab"])
	var seated_pose := POSE_SIT if cab else POSE_BED
	if k <= crouch:
		return {"pos": at, "pose": seated_pose, "anim": "idle" if cab else "crouch"}
	if k >= land:
		var crouching := k < land + (1.0 - land) * Constants.STEP_DOWN_LAND_CROUCH
		return {"pos": at, "pose": POSE_STAND, "anim": "crouch" if crouching else "idle"}
	var u := (k - crouch) / maxf(land - crouch, 0.001)
	if cab:
		return {"pos": at, "pose": POSE_SIT if u < path.w else POSE_STAND, "anim": "idle"}
	return {"pos": at, "pose": POSE_STAND, "anim": "air"}


static func _in_leg(seat: Vector3, ground: Vector3, cab: bool) -> Dictionary:
	var leg := _out_leg(seat, ground, cab)
	leg["kind"] = "in"
	return leg


static func _out_leg(seat: Vector3, ground: Vector3, cab: bool) -> Dictionary:
	var path := _StepDown.hop_path(Transform3D.IDENTITY, seat, ground, cab)
	var timing := _hop_timing(seat.y, ground.y, path)
	return {"kind": "out", "seat": seat, "ground": ground, "path": path, "timing": timing, "s": timing[2], "cab": cab}


static func _add_walk(legs: Array, a: Vector3, b: Vector3) -> void:
	var span := Vector2(b.x - a.x, b.z - a.z).length()
	if span < Constants.CHEFTY_CLIMB_WALK_MIN:
		return
	legs.append({"kind": "walk", "a": a, "b": b, "s": span / Constants.CHEFTY_CLIMB_WALK_SPEED})


## Where you hop into a bed seat from: just outside the rail on the seat's own
## side, level with it (straight across the bed it'd be a leap over the far
## rail), or behind the tailgate for the back row when you're behind the truck.
static func _beside_seat(from: Vector3, seat: Vector3) -> Vector3:
	var rect := _Vehicles.CHEFTY_BED_OUTER.grow(Constants.CHEFTY_CLIMB_RAIL_GAP)
	if from.z > rect.end.y and seat.z > Constants.CHEFTY_CLIMB_TAILGATE_ROW_Z:
		return Vector3(seat.x, from.y, rect.end.y)
	var x := rect.position.x if seat.x < 0.0 else rect.end.x
	return Vector3(x, from.y, seat.z)


static func _finish(legs: Array, yaw_from: float, yaw_to: float) -> Dictionary:
	var total := 0.0
	for leg: Dictionary in legs:
		total += float(leg["s"])
	return {"legs": legs, "seconds": total, "yaw_from": yaw_from, "yaw_to": yaw_to}
