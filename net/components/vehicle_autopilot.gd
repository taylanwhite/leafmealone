class_name VehicleAutopilot
extends RefCounted

## Authority: host. Makes driving inputs for a vehicle with nobody at the wheel
## (docs/DECISIONS.md, "The autopilot"): Chefty on a depart() trip, a hired hand
## chauffeuring the crew, and later the NICE BOYS' van (driving chunk F). It
## only ever produces {throttle, steer, handbrake} for VehicleSim.step, so the
## pose replicates through the vehicle's normal snapshots and nothing about it is
## networked.
##
## Driving is pure pursuit: aim at the point AUTOPILOT_LOOKAHEAD ahead along the
## route, cruise at AUTOPILOT_CRUISE, slow to AUTOPILOT_CORNER_SPEED for sharp
## corners (braking at AUTOPILOT_BRAKE_DECEL ahead of them), and brake to a stop
## at stop_at. A target behind the nose (a U-turn, a truck parked facing the wrong
## way) or a truck that hasn't moved for AUTOPILOT_STUCK_SECONDS backs up with
## the wheel turned toward the target, then goes on.
##
## Warp mode (Net.is_automated(), or --warp-rides) skips the driving: the caller
## moves the chassis along the route itself at AUTOPILOT_TEST_WARP times cruise
## speed (warp_step), so job, board, hire and smoke tests keep their timing.

## The route (y 0) and the cumulative distance to each of its points.
var route := PackedVector3Array()
var stop_at := Vector3.ZERO
var _lengths := PackedFloat64Array()
## How far along the route the vehicle has got (only ever grows).
var _along: float = 0.0
## Backing up: how long it still will, and how long it has been stuck.
var _reverse_left: float = 0.0
var _stuck: float = 0.0
## How long it has been stopped near, but not at, the stop.
var _settle: float = 0.0
var done: bool = false


## Whether depart() and the chauffeur skip the driving: automated runs (the smoke
## test) and --warp-rides.
static func wants_warp() -> bool:
	return Net.is_automated() or bool(Net.dev_options().get("warp_rides"))


## The way to drive from from to to along Gutterford's roads (TownMap.route):
## from here onto the nearest road, junction to junction, and off the road into
## to's lane, lined up AUTOPILOT_LANE_LEAD before it, so the truck pulls in
## straight instead of swerving across the centerline at the end.
static func plan(from: Vector3, to: Vector3) -> PackedVector3Array:
	var flat_from := Vector3(from.x, 0.0, from.z)
	var flat_to := Vector3(to.x, 0.0, to.z)
	var out := PackedVector3Array([flat_from])
	for point: Vector3 in TownMap.route(flat_from, flat_to):
		# A road point right beside the truck is a sideways jog, not a way to go.
		if out[out.size() - 1].distance_to(point) > Constants.AUTOPILOT_MIN_STEP:
			out.append(point)
	if out.size() >= 2 and out[out.size() - 1].distance_to(flat_to) > Constants.AUTOPILOT_MIN_STEP:
		var last := out[out.size() - 1]
		var prev := out[out.size() - 2]
		var leg := last.distance_to(prev)
		var dir := (last - prev).normalized()
		var lead := minf(Constants.AUTOPILOT_LANE_LEAD, leg * Constants.AUTOPILOT_LEAD_SHARE)
		out[out.size() - 1] = flat_to - dir * lead
	if out[out.size() - 1].distance_to(flat_to) > 0.01:
		out.append(flat_to)
	return out


func start(points: PackedVector3Array, stop: Vector3) -> void:
	route = PackedVector3Array()
	for point: Vector3 in points:
		route.append(Vector3(point.x, 0.0, point.z))
	stop_at = Vector3(stop.x, 0.0, stop.z)
	if route.is_empty() or route[route.size() - 1].distance_to(stop_at) > 0.01:
		route.append(stop_at)
	_lengths = PackedFloat64Array([0.0])
	for index: int in range(1, route.size()):
		_lengths.append(_lengths[index - 1] + route[index - 1].distance_to(route[index]))
	_along = 0.0
	_reverse_left = 0.0
	_stuck = 0.0
	_settle = 0.0
	done = false


func length() -> float:
	return _lengths[_lengths.size() - 1] if not _lengths.is_empty() else 0.0


func remaining() -> float:
	return maxf(length() - _along, 0.0)


## The route's point at a distance along it (clamped to its ends).
func point_at(distance: float) -> Vector3:
	if route.size() == 1:
		return route[0]
	var at := clampf(distance, 0.0, length())
	for index: int in range(1, route.size()):
		if at <= _lengths[index] or index == route.size() - 1:
			var span := _lengths[index] - _lengths[index - 1]
			var share := 0.0 if span <= 0.0001 else (at - _lengths[index - 1]) / span
			return route[index - 1].lerp(route[index], clampf(share, 0.0, 1.0))
	return route[route.size() - 1]


## The way the route runs at a distance along it.
func direction_at(distance: float) -> Vector3:
	if route.size() < 2:
		return Vector3.ZERO
	var at := clampf(distance, 0.0, length())
	for index: int in range(1, route.size()):
		if (at < _lengths[index] or index == route.size() - 1) and route[index].distance_to(route[index - 1]) > 0.0001:
			return (route[index] - route[index - 1]).normalized()
	return (route[route.size() - 1] - route[route.size() - 2]).normalized()


## The heading (VehicleSim's yaw) that faces along a direction on the ground.
static func yaw_of(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


## The nearest point on the route to pos, as a distance along it, looking only a
## little behind and a stretch ahead of where the vehicle already got (so a route
## that passes the same corner twice can't jump).
func _project(pos: Vector3) -> float:
	var flat := Vector3(pos.x, 0.0, pos.z)
	var best := _along
	var best_distance := INF
	for index: int in range(1, route.size()):
		if _lengths[index] < _along - Constants.AUTOPILOT_LOOKAHEAD or _lengths[index - 1] > _along + Constants.AUTOPILOT_PROJECT_AHEAD:
			continue
		var a := route[index - 1]
		var b := route[index]
		var closest := Geometry3D.get_closest_point_to_segment(flat, a, b)
		var distance := closest.distance_to(flat)
		if distance < best_distance:
			best_distance = distance
			best = _lengths[index - 1] + a.distance_to(closest)
	return best


## Warp mode: move along by distance; {pos, dir, done}.
func warp_step(distance: float) -> Dictionary:
	_along = minf(_along + distance, length())
	done = _along >= length() - 0.001
	return {"pos": point_at(_along), "dir": direction_at(_along), "done": done}


## This tick's controls for a vehicle at pos in state (VehicleSim's).
func next_input(state: Dictionary, pos: Vector3, dt: float) -> Dictionary:
	if done or route.is_empty():
		return {"brake": true}
	_along = maxf(_along, _project(pos))
	var speed := VehicleSim.forward_speed(state)
	var forward := VehicleSim.forward_of(float(state["yaw"]))
	var flat := Vector3(pos.x, 0.0, pos.z)
	var to_stop := flat.distance_to(stop_at)
	var left := remaining()
	var stopped := absf(speed) < Constants.CHEFTY_PARK_SPEED
	# There: stopped on the spot, or stopped close enough for long enough.
	if to_stop <= Constants.AUTOPILOT_STOP_RADIUS and stopped:
		done = true
		return {"brake": true}
	if stopped and to_stop <= Constants.AUTOPILOT_SETTLE_RADIUS:
		_settle += dt
		if _settle >= Constants.AUTOPILOT_SETTLE_SECONDS:
			done = true
			return {"brake": true}
	else:
		_settle = 0.0
	var target := point_at(_along + Constants.AUTOPILOT_LOOKAHEAD) if left > Constants.AUTOPILOT_LOOKAHEAD else stop_at
	var aim := target - flat
	aim.y = 0.0
	var angle := 0.0
	if aim.length() > 0.05:
		aim = aim.normalized()
		angle = atan2(forward.cross(aim).y, forward.dot(aim))
	# Backing up: the wheel turned so the nose swings toward the target (in
	# reverse, steering right turns the nose left).
	if _reverse_left > 0.0:
		_reverse_left -= dt
		if absf(angle) < Constants.AUTOPILOT_REVERSE_EXIT:
			_reverse_left = 0.0
		else:
			return {"throttle": -Constants.AUTOPILOT_REVERSE_THROTTLE, "steer": 1.0 if angle >= 0.0 else -1.0}
	if absf(angle) > Constants.AUTOPILOT_REVERSE_ANGLE and to_stop > Constants.AUTOPILOT_SETTLE_RADIUS and absf(speed) < Constants.AUTOPILOT_TURN_SPEED:
		_reverse_left = Constants.AUTOPILOT_REVERSE_SECONDS
		_stuck = 0.0
		return {"throttle": -Constants.AUTOPILOT_REVERSE_THROTTLE, "steer": 1.0 if angle >= 0.0 else -1.0}
	var want := _wanted_speed(left, to_stop, angle)
	# Pushing and going nowhere (a post, a parked car): back off and try again.
	if want > Constants.AUTOPILOT_STUCK_SPEED * Constants.AUTOPILOT_STUCK_WANT_FACTOR and absf(speed) < Constants.AUTOPILOT_STUCK_SPEED:
		_stuck += dt
		if _stuck >= Constants.AUTOPILOT_STUCK_SECONDS:
			_stuck = 0.0
			_reverse_left = Constants.AUTOPILOT_REVERSE_SECONDS
	else:
		_stuck = 0.0
	var steer := clampf(-angle * Constants.AUTOPILOT_STEER_GAIN, -1.0, 1.0)
	if want <= 0.0:
		return {"brake": true, "steer": steer}
	var gap := want - speed
	if gap >= 0.0:
		return {"throttle": clampf(gap / Constants.AUTOPILOT_THROTTLE_BAND, Constants.AUTOPILOT_MIN_THROTTLE, 1.0), "steer": steer}
	if -gap < Constants.AUTOPILOT_COAST_BAND:
		return {"throttle": 0.0, "steer": steer}
	# Too fast: the brakes, as hard as the overspeed calls for. Never a negative
	# throttle near standstill, which would back up instead.
	if speed > Constants.CHEFTY_REVERSE_SWITCH_SPEED + Constants.AUTOPILOT_BRAKE_MARGIN:
		return {"throttle": -clampf(-gap / Constants.AUTOPILOT_THROTTLE_BAND, Constants.AUTOPILOT_MIN_THROTTLE, 1.0), "steer": steer}
	return {"brake": true, "steer": steer}


## How fast to go here: cruise, slower ahead of a sharp corner and down to a stop
## at the end (each reached at AUTOPILOT_BRAKE_DECEL), slow while the nose points
## well off the route, and never slower than a creep until the stop.
func _wanted_speed(left: float, to_stop: float, angle: float) -> float:
	var decel := Constants.AUTOPILOT_BRAKE_DECEL
	var want := Constants.AUTOPILOT_CRUISE
	want = minf(want, sqrt(2.0 * decel * maxf(minf(left, to_stop + Constants.AUTOPILOT_LANE_LEAD) - Constants.AUTOPILOT_STOP_RADIUS * Constants.AUTOPILOT_STOP_AIM_SHARE, 0.0)))
	var scan := Constants.AUTOPILOT_CORNER_SCAN
	for index: int in range(1, route.size() - 1):
		var at := _lengths[index]
		if at < _along - Constants.AUTOPILOT_CORNER_BEHIND or at > _along + scan:
			continue
		var into := route[index] - route[index - 1]
		var out := route[index + 1] - route[index]
		if into.length() < 0.01 or out.length() < 0.01:
			continue
		var turn := into.normalized().angle_to(out.normalized())
		if turn < Constants.AUTOPILOT_CORNER_ANGLE:
			continue
		var ahead := maxf(at - _along - Constants.AUTOPILOT_CORNER_EARLY, 0.0)
		want = minf(want, sqrt(Constants.AUTOPILOT_CORNER_SPEED * Constants.AUTOPILOT_CORNER_SPEED + 2.0 * decel * ahead))
	if absf(angle) > Constants.AUTOPILOT_TURN_ANGLE:
		# Close to the stop and pointing away: rolled past it. Stop and call it parked
		# rather than circle the spot.
		if to_stop <= Constants.AUTOPILOT_SETTLE_RADIUS:
			return 0.0
		want = minf(want, Constants.AUTOPILOT_TURN_SPEED)
	if to_stop > Constants.AUTOPILOT_STOP_RADIUS:
		want = maxf(want, Constants.AUTOPILOT_CREEP_SPEED)
	else:
		want = 0.0
	return want
