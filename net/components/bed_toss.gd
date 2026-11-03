extends RefCounted

## Authority: shared math, the same on every peer. Throwing things, and tossing
## leaf bags into Chefty's bed (docs/GAME.md "Tossing bags into Chefty"):
## where a throw leaves the hands and how fast, the flight it takes (the same
## steps Jolt takes, so the arc preview shows where it really lands), whether
## the bed catches it, and the light aim help that bends a near miss in.
##
## The host uses it in net_prop.gd _release and _try_load_bag, a throwing client
## in _predict_toss (its own bag flies at once, the same flight), and
## ui/toss_arc.gd to draw the dotted arc while you wind up. Both Cheftys (ride.gd and
## chefty_drive.gd) give their bed's space with bed_transform().

## Chefty's bed in its own space (ride.gd and chefty_drive.gd BED): the floor's
## top is at y 1.05, the walls' rails at 1.65.
const BED := AABB(Vector3(-1.05, 0.9, -1.2), Vector3(2.1, 1.3, 3.85))
## Where the aim help aims: the middle of the bed, a bag's height over the floor.
const BED_MIDDLE := Vector3(0.0, 1.3, 0.72)
## How far a tumbling leaf bag reaches out from its middle (its box,
## props/yard_prop.tscn, is 0.7 m; turned, its corners reach farther), so the
## flight bonks off the truck where the real bag would.
const BAG_HALF := Vector3(0.45, 0.35, 0.45)
## The truck's hull and cab in bed space, for where the preview arc stops when
## it would bonk off them: [center, half size].
const HULL: Array = [
	[Vector3(0.0, 0.85, -0.1), Vector3(1.2, 0.8, 2.85)],
	[Vector3(0.0, 1.75, -2.0), Vector3(1.2, 0.75, 0.78)],
]
## A drawn leaf bag (props/yard_models.gd) from its bottom, where its body's
## origin is: its middle, and how far it reaches each way from there, upright.
const LOOK_MIDDLE := Vector3(0.0, 0.4, 0.0)
const LOOK_HALF := Vector3(0.27, 0.42, 0.23)
## What a bag gliding into its spot goes over, never through (bed space; the
## truck's solid boxes, props/vehicles.gd build_truck): the side walls, the
## tailgate and the cab. [center, half size]
const WALLS: Array = [
	[Vector3(-1.1, 1.35, 0.72), Vector3(0.08, 0.3, 1.95)],
	[Vector3(1.1, 1.35, 0.72), Vector3(0.08, 0.3, 1.95)],
	[Vector3(0.0, 1.35, 2.66), Vector3(1.15, 0.3, 0.08)],
	[Vector3(0.0, 1.75, -2.0), Vector3(1.15, 0.75, 0.75)],
]
## How finely a settle's path is checked against the walls, how much deeper
## than at its ends it may brush one (m), and how much a bag on its way down may
## brush the wall its spot leans on (the edge spots in the load lean on a wall).
const SETTLE_SAMPLES: int = 64
const SETTLE_CUT_SLACK: float = 0.01
const SETTLE_LEAN_SLACK: float = 0.02

## What happened on this peer, for net/dev/probe.gd and the toss test. The host
## counts catches, refusals, long tosses and assists; every peer counts the
## catches and landings it was told about and how far a bag's drawn look was
## from its stack spot when it went (a pop).
static var stats: Dictionary = {
	"caught": 0, "refused": 0, "long": 0, "longest_m": 0.0, "assisted": 0, "hopped": 0,
	"catch_seen": 0, "land_seen": 0, "full_seen": 0, "reactions_seen": 0, "max_pop_m": 0.0, "stack": 0,
}


## Where a throw leaves the hands (world space): a leaf bag is lobbed from the
## chest, anything else flung from low in front.
static func release_point(kind: String, feet: Vector3, forward: Vector3) -> Vector3:
	var flat := Vector3(forward.x, 0.0, forward.z)
	flat = flat.normalized() if flat.length() > 0.001 else Vector3.FORWARD
	if kind == "leaf_bag":
		return feet + Vector3(0.0, Constants.BAG_TOSS_RELEASE_HEIGHT, 0.0) + flat * Constants.BAG_TOSS_RELEASE_FORWARD
	return feet + Vector3(0.0, 0.4, 0.0) + flat * 1.3


## How fast a throw leaves the hands. power is Constants.THROW_POWER_MIN to
## THROW_POWER_MAX (the wind-up). Every throw is the same shove, so the weight
## decides how far it goes; a leaf bag is a two-handed lob instead, high when
## soft and flatter when hard, a full bag a little shorter than an empty one.
static func launch_velocity(kind: String, kg: float, direction: Vector3, power: float) -> Vector3:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length() < 0.1:
		return Vector3.ZERO
	flat = flat.normalized()
	var strength := clampf(power, Constants.THROW_POWER_MIN, Constants.THROW_POWER_MAX)
	if kind == "leaf_bag":
		var share := inverse_lerp(Constants.THROW_POWER_MIN, Constants.THROW_POWER_MAX, strength)
		var light := float(Constants.ITEM_WEIGHT_KG.get("leaf_bag", 3.0))
		var heavy := clampf((kg - light) / maxf(Constants.LEAF_BAG_MAX_KG - light, 0.001), 0.0, 1.0)
		var along := lerpf(Constants.BAG_TOSS_SPEED_MIN, Constants.BAG_TOSS_SPEED_MAX, share) * lerpf(1.0, Constants.BAG_TOSS_HEAVY_SHARE, heavy)
		return flat * along + Vector3.UP * lift_for(along)
	var speed := clampf(Constants.THROW_IMPULSE / maxf(kg, 0.1), Constants.THROW_SPEED_MIN, Constants.THROW_SPEED_MAX) * strength
	return flat * speed + Vector3.UP * (1.5 + speed * 0.3)


## A bag's upward speed for its speed along the ground: a soft toss is a high lob.
static func lift_for(along: float) -> float:
	return Constants.BAG_TOSS_LIFT + Constants.BAG_TOSS_LIFT_PER_SPEED * along


## The power (THROW_POWER_MIN..MAX) a wind-up of this many seconds gives.
static func power_for_seconds(seconds: float) -> float:
	return lerpf(Constants.THROW_POWER_MIN, Constants.THROW_POWER_MAX, clampf(seconds / Constants.THROW_CHARGE_SECONDS, 0.0, 1.0))


## One physics tick of flight, as Jolt steps a free body: gravity, then the
## project's linear damping, then the move.
static func step(pos: Vector3, vel: Vector3, dt: float) -> Array:
	var damp := float(ProjectSettings.get_setting("physics/3d/default_linear_damp", 0.1))
	var next := vel + Vector3.DOWN * gravity() * dt
	next *= maxf(0.0, 1.0 - damp * dt)
	return [pos + next * dt, next]


static func gravity() -> float:
	return float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))


static func tick_seconds() -> float:
	return 1.0 / float(Engine.physics_ticks_per_second)


## The bed's space in the world, or Transform3D() without a Chefty.
static func bed_of(truck: Node) -> Transform3D:
	if truck == null or not truck.has_method("bed_transform"):
		return Transform3D()
	return truck.call("bed_transform")


## True when the bed catches a bag whose bottom is here, moving like this: inside
## the bed's box any time; over the open bed on its way down, up to Constants
## BED_CATCH_TOP_Y high; and a little past the side walls and the tailgate, only
## above the rails there (a bag that hits a wall bounces off it), on its way down
## or heading in over the rail (it would tumble in over it).
static func catches(truck: Node, pos: Vector3, vel: Vector3) -> bool:
	if truck == null or not truck.has_method("bed_transform"):
		return false
	var bed := bed_of(truck)
	return _catches_local(bed.affine_inverse() * pos, bed.basis.inverse() * vel)


## catches() in the bed's own space.
static func _catches_local(local: Vector3, heading: Vector3) -> bool:
	if BED.has_point(local):
		return true
	if local.y > Constants.BED_CATCH_TOP_Y or local.y < BED.position.y:
		return false
	var inside_x := absf(local.x) <= BED.end.x
	var inside_z := local.z >= BED.position.z and local.z <= BED.end.z
	if inside_x and inside_z:
		return heading.y <= 0.0
	var margin := Constants.BED_CATCH_SIDE_MARGIN
	if absf(local.x) > BED.end.x + margin or local.z < BED.position.z or local.z > BED.end.z + margin:
		return false
	if local.y < Constants.BED_CATCH_RAIL_Y:
		return false
	var inward := (not inside_x and signf(local.x) * heading.x < 0.0) or (local.z > BED.end.z and heading.z < 0.0)
	return heading.y <= 0.0 or inward


## True when a bag tossed from right by the bed (its middle within
## Constants.BED_CLOSE_REACH past a side wall or the tailgate, thrown toward it)
## would only bonk the wall from there (no lob from that close clears the rail):
## it goes in with a little hop instead
## (net_prop.gd), the way you'd heave it over the side.
static func close_toss(truck: Node, pos: Vector3, vel: Vector3, ground_y: float) -> bool:
	if truck == null or not truck.has_method("bed_transform"):
		return false
	var bed := bed_of(truck)
	var local := bed.affine_inverse() * pos
	var heading := bed.basis.inverse() * vel
	var reach := Constants.BED_CLOSE_REACH
	var past_side := absf(local.x) - BED.end.x
	var past_tail := local.z - BED.end.z
	var by_side := past_side > 0.0 and past_side <= reach and local.z >= BED.position.z and local.z <= BED.end.z and signf(local.x) * heading.x < 0.0
	var by_tail := past_tail > 0.0 and past_tail <= reach and absf(local.x) <= BED.end.x and heading.z < 0.0
	if not by_side and not by_tail:
		return false
	# Only a toss that would bonk the side: one thrown clean over the truck misses.
	var path := flight(pos, vel, ground_y, truck)
	return not bool(path["caught"]) and bool(path["hull"])


## True when a bag whose bottom is here would be touching the truck's hull or
## cab (the whole bag, BAG_HALF each way of its middle, not just its bottom), so
## the flight would bonk off it. A flight checks catches() first, so this only
## stops one that hasn't cleared the rail.
static func hits_hull(truck: Node, pos: Vector3) -> bool:
	if truck == null or not truck.has_method("bed_transform"):
		return false
	return _hull_local(bed_of(truck).affine_inverse() * pos)


## hits_hull() in the bed's own space.
static func _hull_local(local: Vector3) -> bool:
	var middle := local + Vector3(0.0, BAG_HALF.y, 0.0)
	for box: Array in HULL:
		var offset: Vector3 = (middle - (box[0] as Vector3)).abs()
		var half: Vector3 = (box[1] as Vector3) + BAG_HALF
		if offset.x <= half.x and offset.y <= half.y and offset.z <= half.z:
			return true
	return false


## The flight from here at this speed until it lands (its bottom back down to
## ground_y), the bed catches it, it would bonk off the truck, or max_seconds
## pass. {points: a dot every Constants.TOSS_ARC_STEP_SECONDS, end, end_vel,
## caught, hull}. first_dot (s) puts the first dot that far in, not at the start
## (the preview slides its dots along the arc with it). Worked out in the bed's
## space (the same steps as step(), turned into it once), since the aim help and
## the preview run many of these a frame.
static func flight(pos: Vector3, vel: Vector3, ground_y: float, truck: Node = null, max_seconds: float = -1.0, first_dot: float = -1.0) -> Dictionary:
	var dt := tick_seconds()
	var limit := max_seconds if max_seconds > 0.0 else Constants.TOSS_ARC_MAX_SECONDS
	var points := PackedVector3Array([pos]) if first_dot < 0.0 else PackedVector3Array()
	var since_dot := 0.0 if first_dot < 0.0 else Constants.TOSS_ARC_STEP_SECONDS - first_dot
	var has_truck := truck != null and truck.has_method("bed_transform")
	var bed := bed_of(truck) if has_truck else Transform3D()
	var back := bed.affine_inverse()
	var at := back * pos
	var v := back.basis * vel
	var fall := back.basis * (Vector3.DOWN * gravity() * dt)
	var keep := maxf(0.0, 1.0 - float(ProjectSettings.get_setting("physics/3d/default_linear_damp", 0.1)) * dt)
	# World height of a bed-space point: this row of the bed's transform.
	var up_row := Vector3(bed.basis.x.y, bed.basis.y.y, bed.basis.z.y)
	var t := 0.0
	var caught := false
	var hull := false
	while t < limit:
		v = (v + fall) * keep
		at += v * dt
		t += dt
		since_dot += dt
		if since_dot >= Constants.TOSS_ARC_STEP_SECONDS:
			since_dot = 0.0
			points.append(bed * at)
		if has_truck and _catches_local(at, v):
			caught = true
			break
		if has_truck and _hull_local(at):
			hull = true
			break
		if up_row.dot(v) < 0.0 and up_row.dot(at) + bed.origin.y <= ground_y:
			break
	var end := bed * at
	if first_dot < 0.0:
		points.append(end)
	return {"points": points, "end": end, "end_vel": bed.basis * v, "caught": caught, "hull": hull, "seconds": t}

## Light, fair aim help for a leaf bag tossed at Chefty (docs/GAME.md): a throw
## the bed would catch anyway is left alone; a near miss (aimed within
## BED_ASSIST_WINDOW times Constants.BED_ASSIST_MAX_YAW of the bed's middle) is
## given the smallest nudge that puts it in: turned toward the middle by at most
## BED_ASSIST_MAX_YAW and thrown up to BED_ASSIST_MAX_SPEED_SHARE softer or
## harder (a harder lob also goes higher, so a toss that would clip the rail
## clears it). Help that can't put it in changes nothing. Only the launch
## changes, so the flight stays one smooth arc. Returns the velocity to throw with.
static func assist(truck: Node, pos: Vector3, vel: Vector3, ground_y: float) -> Vector3:
	if truck == null or not truck.has_method("bed_transform"):
		return vel
	var flat := Vector3(vel.x, 0.0, vel.z)
	var along := flat.length()
	if along < 0.1:
		return vel
	if bool(flight(pos, vel, ground_y, truck)["caught"]):
		return vel
	var target: Vector3 = bed_of(truck) * BED_MIDDLE
	var to_target := Vector3(target.x - pos.x, 0.0, target.z - pos.z)
	if to_target.length() < 0.3:
		return vel
	var turn := flat.signed_angle_to(to_target, Vector3.UP)
	if absf(turn) > Constants.BED_ASSIST_MAX_YAW * Constants.BED_ASSIST_WINDOW:
		return vel
	var extra_lift := vel.y - lift_for(along)
	var yaw_cap := clampf(turn, -Constants.BED_ASSIST_MAX_YAW, Constants.BED_ASSIST_MAX_YAW)
	var best := vel
	var best_cost := INF
	# The nudges, smallest first by how much they change: a quarter of the speed
	# cap at a time, half the turn at a time.
	for turn_step: int in 3:
		for speed_step: int in [0, 1, -1, 2, -2, 3, -3, 4, -4]:
			var cost := absf(float(speed_step)) / 4.0 + float(turn_step) / 2.0
			if cost >= best_cost or (turn_step == 0 and speed_step == 0):
				continue
			var speed := along * (1.0 + Constants.BED_ASSIST_MAX_SPEED_SHARE * float(speed_step) / 4.0)
			var heading := flat.normalized().rotated(Vector3.UP, yaw_cap * float(turn_step) / 2.0)
			var tried := heading * speed + Vector3.UP * (lift_for(speed) + extra_lift)
			if bool(flight(pos, tried, ground_y, truck)["caught"]):
				best = tried
				best_cost = cost
	return best


## How long a bag the bed caught takes into its spot (s): Constants
## BED_SETTLE_SECONDS_PER_M along the way settle_plan() takes it (over the rail,
## if it has to go over), within BED_SETTLE_MIN_SECONDS..MAX. from and to are its
## body in the bed's space. The host sends it with the catch, so every peer's
## glide ends together.
static func settle_seconds(from: Transform3D, to: Transform3D) -> float:
	var turn_from := from.basis.orthonormalized()
	var turn_to := to.basis.orthonormalized()
	var points := _over_points(Transform3D(turn_from, from.origin) * LOOK_MIDDLE, Transform3D(turn_to, to.origin) * LOOK_MIDDLE, _settle_reach(turn_from, turn_to), look_reach(turn_to), 0.0)
	var length := 0.0
	for index: int in range(1, points.size()):
		length += (points[index] as Vector3).distance_to(points[index - 1])
	return clampf(length * Constants.BED_SETTLE_SECONDS_PER_M, Constants.BED_SETTLE_MIN_SECONDS, Constants.BED_SETTLE_MAX_SECONDS)


## The way a bag the bed caught goes into its spot, in the bed's space: from its
## body at `from` moving at `moving`, to `to`, over `seconds`. It glides straight
## in when that clears the truck; otherwise it goes up, over the rail (or the
## cab) and down into its spot, never cutting into the truck deeper than it was
## at either end (cut_depth). Its middle follows the path (smooth: position and
## speed both continuous) while it turns from from's lean to to's (over a
## wall, done turning by the time it's over it, so it comes down the way it will
## sit). settle_at() reads it. {keys: [[middle, velocity, time]...], from, to
## (Basis), turned (s), seconds}.
static func settle_plan(from: Transform3D, moving: Vector3, to: Transform3D, seconds: float) -> Dictionary:
	var turn_from := from.basis.orthonormalized()
	var turn_to := to.basis.orthonormalized()
	var plan := {"from": turn_from, "to": turn_to, "seconds": maxf(seconds, 0.05), "turned": maxf(seconds, 0.05), "keys": []}
	var start := Transform3D(turn_from, from.origin) * LOOK_MIDDLE
	var end := Transform3D(turn_to, to.origin) * LOOK_MIDDLE
	var land := Vector3.DOWN * Constants.BED_SETTLE_LAND_SPEED
	var allowed := maxf(cut_depth(start, look_reach(turn_from)), cut_depth(end, look_reach(turn_to))) + SETTLE_CUT_SLACK
	# Straight in, carrying on as it was moving (or half as fast), when that clears.
	for share: float in [1.0, 0.5]:
		plan["keys"] = _timed([start, end], moving * share, land, float(plan["seconds"]))
		if settle_cut(plan) <= allowed:
			return plan
	# Over the top: up first if it's beside the truck (its sideways speed would
	# only push it into the wall), then over, then down into its spot.
	var reach := _settle_reach(turn_from, turn_to)
	for raise: float in [0.0, 0.15, 0.4]:
		var points := _over_points(start, end, reach, look_reach(turn_to), raise)
		var lift := moving
		if points.size() > 2 and _under_walls(start, reach) and start.y < (points[1] as Vector3).y:
			lift = Vector3(0.0, maxf(moving.y, 0.0), 0.0)
		plan["keys"] = _timed(points, lift, land, float(plan["seconds"]))
		var keys: Array = plan["keys"]
		plan["turned"] = maxf(float(keys[maxi(keys.size() - 2, 1)][2]), 0.05)
		if settle_cut(plan) <= allowed:
			return plan
	return plan


## The body's transform (bed space) age seconds into a settle_plan().
static func settle_at(plan: Dictionary, age: float) -> Transform3D:
	var seconds := float(plan["seconds"])
	var t := clampf(age / seconds, 0.0, 1.0)
	var at := t * seconds
	var turn := (plan["from"] as Basis).slerp(plan["to"] as Basis, smoothstep(0.0, 1.0, clampf(at / float(plan["turned"]), 0.0, 1.0)))
	var keys: Array = plan["keys"]
	var middle: Vector3 = keys[keys.size() - 1][0]
	for index: int in range(1, keys.size()):
		var a: Array = keys[index - 1]
		var b: Array = keys[index]
		if at <= float(b[2]) or index == keys.size() - 1:
			var span := maxf(float(b[2]) - float(a[2]), 0.0001)
			middle = _hermite(a[0], a[1], b[0], b[1], span, clampf((at - float(a[2])) / span, 0.0, 1.0))
			break
	return Transform3D(turn, middle - turn * LOOK_MIDDLE)


## The deepest a settle_plan() cuts into the truck anywhere along it (m).
static func settle_cut(plan: Dictionary) -> float:
	var deepest := 0.0
	for index: int in SETTLE_SAMPLES + 1:
		var body := settle_at(plan, float(plan["seconds"]) * float(index) / float(SETTLE_SAMPLES))
		deepest = maxf(deepest, cut_depth(body * LOOK_MIDDLE, look_reach(body.basis)))
	return deepest


## How far a drawn bag turned like this reaches from its middle along each of
## the bed's axes.
static func look_reach(turn: Basis) -> Vector3:
	return Vector3(
		absf(turn.x.x) * LOOK_HALF.x + absf(turn.y.x) * LOOK_HALF.y + absf(turn.z.x) * LOOK_HALF.z,
		absf(turn.x.y) * LOOK_HALF.x + absf(turn.y.y) * LOOK_HALF.y + absf(turn.z.y) * LOOK_HALF.z,
		absf(turn.x.z) * LOOK_HALF.x + absf(turn.y.z) * LOOK_HALF.y + absf(turn.z.z) * LOOK_HALF.z)


## How deep a drawn bag with its middle here (bed space), reaching this far,
## cuts into the truck's walls or cab: the least it would have to move to come
## clear of the deepest one (m), 0 when it's clear.
static func cut_depth(middle: Vector3, reach: Vector3) -> float:
	var deepest := 0.0
	for wall: Array in WALLS:
		var gap: Vector3 = (wall[1] as Vector3) + reach - (middle - (wall[0] as Vector3)).abs()
		if gap.x > 0.0 and gap.y > 0.0 and gap.z > 0.0:
			deepest = maxf(deepest, minf(gap.x, minf(gap.y, gap.z)))
	return deepest


## The most a bag reaches from its middle while it turns from one lean to the other.
static func _settle_reach(turn_from: Basis, turn_to: Basis) -> Vector3:
	var reach := Vector3.ZERO
	for index: int in 9:
		var turn := turn_from.slerp(turn_to, float(index) / 8.0)
		var here := look_reach(turn)
		reach = Vector3(maxf(reach.x, here.x), maxf(reach.y, here.y), maxf(reach.z, here.z))
	return reach


## True when a bag's middle here, reaching this far, is over a wall or the cab
## (seen from above).
static func _under_walls(middle: Vector3, reach: Vector3) -> bool:
	for wall: Array in WALLS:
		var c: Vector3 = wall[0]
		var h: Vector3 = wall[1]
		if absf(middle.x - c.x) < h.x + reach.x and absf(middle.z - c.z) < h.z + reach.z:
			return true
	return false


## The points a settle goes through (bed space, the bag's middle): start and
## end, plus, when the way between them passes over a wall or the cab, where it
## first comes over one and where it's last over one, high enough there (raise
## higher still) that the bag clears it.
static func _over_points(start: Vector3, end: Vector3, reach: Vector3, end_reach: Vector3, raise: float) -> Array:
	var first := -1
	var last := -1
	var top := -INF
	# A spot by a wall or the cab has its bag leaning on it a little: brushing it
	# that much on the way down is no reason to go up over it.
	var leaning: Array[float] = []
	for wall: Array in WALLS:
		var gap: Vector3 = (wall[1] as Vector3) + end_reach - (end - (wall[0] as Vector3)).abs()
		leaning.append(maxf(minf(gap.x, minf(gap.y, gap.z)), 0.0) + SETTLE_LEAN_SLACK)
	for index: int in SETTLE_SAMPLES + 1:
		var here := start.lerp(end, float(index) / float(SETTLE_SAMPLES))
		for wall_index: int in WALLS.size():
			var c: Vector3 = WALLS[wall_index][0]
			var h: Vector3 = WALLS[wall_index][1]
			if minf(h.x + reach.x - absf(here.x - c.x), h.z + reach.z - absf(here.z - c.z)) > leaning[wall_index]:
				top = maxf(top, c.y + h.y)
				if first < 0:
					first = index
				last = index
	if first < 0:
		return [start, end]
	var over := top + reach.y + Constants.BED_SETTLE_CLEARANCE + raise
	var points: Array = [start]
	var up_at := start.lerp(end, float(first) / float(SETTLE_SAMPLES))
	if start.y < over:
		points.append(Vector3(up_at.x, over, up_at.z))
	var down_at := start.lerp(end, float(last) / float(SETTLE_SAMPLES))
	if last > first or start.y >= over:
		points.append(Vector3(down_at.x, maxf(over, minf(start.y, over + 0.5)), down_at.z))
	points.append(end)
	return points


## Keys [[point, velocity, time]...] for a smooth path through points over
## seconds, each stretch taking its share by length: leaving at start_vel,
## arriving at end_vel, and through the points between at the speed that carries
## on from the one before to the one after, held back where that would carry it
## past either (so it never swings out over a wall it was meant to clear).
static func _timed(points: Array, start_vel: Vector3, end_vel: Vector3, seconds: float) -> Array:
	var lengths: Array[float] = [0.0]
	for index: int in range(1, points.size()):
		lengths.append(lengths[index - 1] + maxf((points[index] as Vector3).distance_to(points[index - 1]), 0.001))
	var total := lengths[lengths.size() - 1]
	var times: Array[float] = []
	for index: int in points.size():
		times.append(seconds * lengths[index] / total)
	var keys: Array = []
	var last := points.size() - 1
	for index: int in points.size():
		var vel := start_vel if index == 0 else end_vel
		if last < 2:
			keys.append([points[index], vel, times[index]])
			continue
		# Over a wall: the speed through each point (and leaving and landing too)
		# is held back so no stretch swings past where it's headed.
		var into := ((points[index] as Vector3) - (points[index - 1] as Vector3)) / maxf(times[index] - times[index - 1], 0.001) if index > 0 else Vector3.INF
		var out := ((points[index + 1] as Vector3) - (points[index] as Vector3)) / maxf(times[index + 1] - times[index], 0.001) if index < last else Vector3.INF
		if index > 0 and index < last:
			vel = ((points[index + 1] as Vector3) - (points[index - 1] as Vector3)) / maxf(times[index + 1] - times[index - 1], 0.001)
		keys.append([points[index], _held_back(vel, into, out), times[index]])
	return keys


## A speed through a point no faster than three times the stretch into it's or
## out of it's (INF: no stretch that side), across (x and z together) and up and
## down on their own, and none at all where the path turns back there.
static func _held_back(vel: Vector3, into: Vector3, out: Vector3) -> Vector3:
	var flat := Vector2(vel.x, vel.z)
	var cap := INF
	for side: Vector3 in [into, out]:
		if not side.is_finite():
			continue
		var side_flat := Vector2(side.x, side.z)
		if flat.dot(side_flat) <= 0.0:
			flat = Vector2.ZERO
		cap = minf(cap, 3.0 * side_flat.length())
	if flat.length() > cap:
		flat = flat.normalized() * cap
	var rise := vel.y
	for side: Vector3 in [into, out]:
		if not side.is_finite():
			continue
		if rise * side.y <= 0.0:
			rise = 0.0
		rise = signf(rise) * minf(absf(rise), 3.0 * absf(side.y))
	return Vector3(flat.x, rise, flat.y)


## One stretch of cubic Hermite from p0 moving at v0 to p1 arriving at v1, over
## seconds, at t in 0..1. A fast throw's speed would loop the curve, so each
## pull is capped to the stretch's length.
static func _hermite(p0: Vector3, v0: Vector3, p1: Vector3, v1: Vector3, seconds: float, t: float) -> Vector3:
	var span := p0.distance_to(p1)
	var m0 := v0 * seconds
	if m0.length() > span * 1.5:
		m0 = m0.normalized() * span * 1.5
	var m1 := v1 * seconds
	if m1.length() > span * 1.5:
		m1 = m1.normalized() * span * 1.5
	var t2 := t * t
	var t3 := t2 * t
	return p0 * (2.0 * t3 - 3.0 * t2 + 1.0) + m0 * (t3 - 2.0 * t2 + t) + p1 * (-2.0 * t3 + 3.0 * t2) + m1 * (t3 - t2)
