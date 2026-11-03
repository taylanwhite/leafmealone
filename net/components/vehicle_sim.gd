class_name VehicleSim
extends RefCounted

## Authority: none; a pure step function. The arcade vehicle model the host runs
## for Chefty (and later the NICE BOYS' van), that the driver's own peer replays to
## predict, and that the autopilot drives (docs/DECISIONS.md, "Chefty is a
## host-simulated arcade vehicle"). Nothing here is a physics body with wheels:
## the chassis is a CharacterBody3D box held off the ground, four rays find the
## road under the hubs, and move_and_slide only ever meets walls. So the same
## inputs from the same state give the same result on the host and the driver,
## which is what makes replaying them work.
##
## Vehicles face -Z in their own space, like every model in props/vehicles.gd. yaw
## is the heading: 0 faces -Z, +PI/2 faces -X.
##
## state (the caller keeps it between steps):
##   yaw       heading in radians
##   vel       horizontal world velocity (y is 0)
##   yaw_rate  turn rate in rad/s
##   vy        vertical speed (falling off a ramp)
##   air       no wheel touched ground last step
##   pitch, roll    the ground's tilt under the wheels (visual)
##   lean_pitch, lean_roll   how the body leans with the throttle and the turn (visual)
##   slip      sideways speed, m/s (the skid sound)
##   steer     the wheel's position, -1..1 (the steering wheel)
##   skip      {instance_id: msec} soft things the chassis ignores until then
## input: throttle -1..1 (negative brakes, then reverses), steer -1..1 (positive
## is right), handbrake bool, brake bool (nobody driving: stop).

## A chassis this far (m) under the ground it should stand on is sunk, and is
## stood back up on it, found by a ray from this far over its wheels (m).
const SUNK_MARGIN: float = 0.3
const SUNK_LOOK_UP: float = 2.2


## The params dictionary for Chefty with this many dents and the tune-up perk.
static func chefty_params(dents: int, tuneup: bool) -> Dictionary:
	var top := Constants.CHEFTY_TOP_SPEED * (1.0 - Constants.CHEFTY_DENT_SPEED_SHARE * float(clampi(dents, 0, Constants.CHEFTY_MAX_DENTS)))
	if tuneup:
		top *= Constants.CHEFTY_TUNEUP_SHARE
	return {
		"top_speed": top,
		"reverse_speed": Constants.CHEFTY_REVERSE_SPEED,
		"accel": Constants.CHEFTY_ACCEL,
		"brake": Constants.CHEFTY_BRAKE,
		"coast_drag": Constants.CHEFTY_COAST_DRAG,
		"air_drag": Constants.CHEFTY_AIR_DRAG,
		"handbrake_decel": Constants.CHEFTY_HANDBRAKE_DECEL,
		"steer_rate": Constants.CHEFTY_STEER_RATE,
		"steer_full_at": Constants.CHEFTY_STEER_FULL_AT,
		"steer_high_share": Constants.CHEFTY_STEER_HIGH_SPEED_SHARE,
		"yaw_response": Constants.CHEFTY_YAW_RESPONSE,
		"drift_steer_share": Constants.CHEFTY_DRIFT_STEER_SHARE,
		"grip": Constants.CHEFTY_GRIP,
		"drift_grip": Constants.CHEFTY_DRIFT_GRIP,
		"ride_height": Constants.CHEFTY_RIDE_HEIGHT,
		"ray": Constants.CHEFTY_SUSPENSION_RAY,
		"suspension_rate": Constants.CHEFTY_SUSPENSION_RATE,
		"gravity": Constants.CHEFTY_GRAVITY,
		"wheels": Constants.CHEFTY_WHEELS,
	}


## A fresh state at rest, facing yaw.
static func new_state(yaw: float) -> Dictionary:
	return {
		"yaw": yaw, "vel": Vector3.ZERO, "yaw_rate": 0.0, "vy": 0.0, "air": false,
		"pitch": 0.0, "roll": 0.0, "lean_pitch": 0.0, "lean_roll": 0.0, "slip": 0.0, "steer": 0.0,
		"skip": {},
	}


## Which way a heading faces, on the ground.
static func forward_of(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


static func right_of(yaw: float) -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))


## Signed speed along the heading (negative reversing).
static func forward_speed(state: Dictionary) -> float:
	return (state["vel"] as Vector3).dot(forward_of(float(state["yaw"])))


## One step: moves chassis and updates state. Returns {impact (m/s lost into
## something solid), impact_normal, hits: [{collider, normal, soft}]}.
static func step(chassis: CharacterBody3D, state: Dictionary, input: Dictionary, params: Dictionary, dt: float) -> Dictionary:
	var throttle := clampf(float(input.get("throttle", 0.0)), -1.0, 1.0)
	var steer := clampf(float(input.get("steer", 0.0)), -1.0, 1.0)
	var handbrake := bool(input.get("handbrake", false))
	var brake := bool(input.get("brake", false))
	var top := float(params["top_speed"])
	var yaw := float(state["yaw"])
	var vel: Vector3 = state["vel"]
	var air := bool(state["air"])
	state["steer"] = move_toward(float(state["steer"]), steer, dt * Constants.CHEFTY_STEER_SPEED)
	# Turn first, with the speed the wheels had: the heading swings and the
	# velocity has to follow it through the tires' grip.
	var speed_before := vel.dot(forward_of(yaw))
	var yaw_rate := float(state["yaw_rate"])
	if not air:
		var ramp := clampf(absf(speed_before) / float(params["steer_full_at"]), 0.0, 1.0)
		var high := lerpf(1.0, float(params["steer_high_share"]), clampf(absf(speed_before) / maxf(top, 0.1), 0.0, 1.0))
		var want := -float(state["steer"]) * float(params["steer_rate"]) * ramp * high * signf(speed_before)
		if handbrake:
			want *= float(params["drift_steer_share"])
		yaw_rate = move_toward(yaw_rate, want, float(params["yaw_response"]) * dt)
	else:
		yaw_rate = move_toward(yaw_rate, 0.0, dt)
	yaw = wrapf(yaw + yaw_rate * dt, -PI, PI)
	var forward := forward_of(yaw)
	var right := right_of(yaw)
	var along := vel.dot(forward)
	var side := vel.dot(right)
	var accel_along := 0.0
	if not air:
		var before := along
		if brake:
			along = move_toward(along, 0.0, float(params["brake"]) * dt)
		elif throttle > 0.01:
			if along < -Constants.CHEFTY_REVERSE_SWITCH_SPEED:
				along = move_toward(along, 0.0, float(params["brake"]) * throttle * dt)
			elif along < top:
				along = minf(along + float(params["accel"]) * throttle * dt, top)
			else:
				along = move_toward(along, top, float(params["coast_drag"]) * dt)
		elif throttle < -0.01:
			if along > Constants.CHEFTY_REVERSE_SWITCH_SPEED:
				along = move_toward(along, 0.0, float(params["brake"]) * -throttle * dt)
			else:
				along = maxf(along - float(params["accel"]) * -throttle * dt, -float(params["reverse_speed"]))
		else:
			along = move_toward(along, 0.0, float(params["coast_drag"]) * dt)
		along -= signf(along) * float(params["air_drag"]) * along * along * dt
		if handbrake:
			along = move_toward(along, 0.0, float(params["handbrake_decel"]) * dt)
		side *= exp(-float(params["drift_grip"] if handbrake else params["grip"]) * dt)
		accel_along = (along - before) / maxf(dt, 0.0001)
	state["slip"] = absf(side)
	vel = forward * along + right * side
	# Lean back on the gas, nose down on the brakes, out of the turn.
	var lean_max := Constants.CHEFTY_LEAN_MAX
	var lateral := yaw_rate * along
	state["lean_pitch"] = lerpf(float(state["lean_pitch"]), clampf(accel_along * Constants.CHEFTY_LEAN_PITCH, -lean_max, lean_max), clampf(dt * Constants.CHEFTY_LEAN_PITCH_RATE, 0.0, 1.0))
	state["lean_roll"] = lerpf(float(state["lean_roll"]), clampf(-lateral * Constants.CHEFTY_LEAN_ROLL, -lean_max, lean_max), clampf(dt * Constants.CHEFTY_LEAN_ROLL_RATE, 0.0, 1.0))
	# Slide along walls; soft things (props, people) only slow it a little.
	var before_slide := vel
	_expire_skips(chassis, state)
	chassis.velocity = Vector3(vel.x, 0.0, vel.z)
	chassis.global_rotation = Vector3(0.0, yaw, 0.0)
	var from := chassis.global_position
	chassis.move_and_slide()
	# The slide only moves it across the ground; the suspension below says how high
	# it rides. Pushed out of a parked car, the slide's recovery could shove it half
	# a meter into the road (driving C3: the drawn truck sank, then popped back up).
	chassis.global_position.y = from.y
	var after := Vector3(chassis.velocity.x, 0.0, chassis.velocity.z)
	# A floating CharacterBody keeps its velocity through a wall it can't pass;
	# what it really managed is how far it got (driving C3: hitting a parked car
	# head on stops the truck and counts as a crash, instead of grinding round it).
	if chassis.get_slide_collision_count() > 0 and dt > 0.0:
		var moved := chassis.global_position - from
		var managed := Vector3(moved.x, 0.0, moved.z) / dt
		if managed.length() < after.length():
			after = managed
	var hits: Array = []
	var impact := 0.0
	var impact_normal := Vector3.ZERO
	var soft_hit := false
	for index: int in chassis.get_slide_collision_count():
		var collision := chassis.get_slide_collision(index)
		var collider := collision.get_collider()
		var normal := collision.get_normal()
		normal.y = 0.0
		var soft := collider is RigidBody3D or collider is CharacterBody3D
		hits.append({"collider": collider, "normal": normal, "soft": soft})
		if soft and collider is PhysicsBody3D:
			soft_hit = true
			chassis.add_collision_exception_with(collider as PhysicsBody3D)
			(state["skip"] as Dictionary)[(collider as Object).get_instance_id()] = Time.get_ticks_msec() + int(Constants.CHEFTY_SOFT_HIT_SECONDS * 1000.0)
			continue
		if normal.length() > 0.01:
			var lost := maxf(0.0, -before_slide.dot(normal.normalized())) - maxf(0.0, -after.dot(normal.normalized()))
			if lost > impact:
				impact = lost
				impact_normal = normal.normalized()
	if soft_hit and impact <= 0.0:
		after = before_slide * Constants.CHEFTY_SOFT_HIT_KEEP
	state["vel"] = after
	state["yaw"] = yaw
	state["yaw_rate"] = yaw_rate
	_suspend(chassis, state, params, dt)
	return {"impact": impact, "impact_normal": impact_normal, "hits": hits}


## The rays under the hubs set the ride height and the tilt; with no ground the
## chassis falls (a ramp gives air).
static func _suspend(chassis: CharacterBody3D, state: Dictionary, params: Dictionary, dt: float) -> void:
	var space := chassis.get_world_3d().direct_space_state if chassis.is_inside_tree() else null
	var origin := chassis.global_position
	var basis := Basis(Vector3.UP, float(state["yaw"]))
	var ride := float(params["ride_height"])
	var reach := float(params["ray"])
	var heights: Array[float] = []
	var exclude: Array[RID] = [chassis.get_rid()]
	for rid: RID in params.get("exclude", []):
		exclude.append(rid)
	var found := 0
	var ground_sum := 0.0
	for wheel: Vector2 in params["wheels"]:
		var hub := origin + basis * Vector3(wheel.x, ride, wheel.y)
		var height := NAN
		if space != null:
			var query := PhysicsRayQueryParameters3D.create(hub + Vector3.UP * 0.6, hub + Vector3.DOWN * reach, 1)
			query.exclude = exclude
			query.hit_back_faces = false
			var hit := space.intersect_ray(query)
			if not hit.is_empty() and (hit["normal"] as Vector3).y > 0.5 and not hit["collider"] is RigidBody3D and not hit["collider"] is CharacterBody3D:
				height = (hit["position"] as Vector3).y
				found += 1
				ground_sum += height
		heights.append(height)
	var vy := float(state["vy"])
	if found == 0 and space != null:
		# Pushed down into the ground (a crash's shove out of a car can do it): the
		# rays start under the surface and miss it. Look from well above, and stand
		# back up on what's there if it's over us.
		var query := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * (ride + SUNK_LOOK_UP), origin + Vector3.DOWN * 0.2, 1)
		query.exclude = exclude
		query.hit_back_faces = false
		var hit := space.intersect_ray(query)
		if not hit.is_empty() and (hit["normal"] as Vector3).y > 0.5 and (hit["position"] as Vector3).y > origin.y + SUNK_MARGIN \
				and not hit["collider"] is RigidBody3D and not hit["collider"] is CharacterBody3D:
			origin.y = (hit["position"] as Vector3).y
			vy = 0.0
			found = -1
	if found == 0:
		state["air"] = true
		vy -= float(params["gravity"]) * dt
		origin.y += vy * dt
		# Never through the floor of the world.
		origin.y = maxf(origin.y, -5.0)
	elif found < 0:
		state["air"] = false
	else:
		var ground := ground_sum / float(found)
		if origin.y > ground + Constants.CHEFTY_LAND_GAP and vy <= Constants.CHEFTY_LAND_RISE_SPEED:
			# Coming down: fall onto it.
			state["air"] = true
			vy -= float(params["gravity"]) * dt
			origin.y = maxf(origin.y + vy * dt, ground)
			if origin.y <= ground:
				vy = 0.0
				state["air"] = false
		else:
			state["air"] = false
			# The springs: up onto a ramp or a curb quickly, a little bounce.
			var rise := (ground - origin.y) * clampf(float(params["suspension_rate"]) * dt, 0.0, 1.0)
			vy = rise / maxf(dt, 0.0001) if rise > 0.0 else 0.0
			origin.y += rise
		# Tilt from the wheels that found ground (front vs back, left vs right).
		var front := _mean([heights[0], heights[1]])
		var back := _mean([heights[2], heights[3]])
		var left := _mean([heights[0], heights[2]])
		var right := _mean([heights[1], heights[3]])
		var wheels: Array = params["wheels"]
		var base := absf((wheels[2] as Vector2).y - (wheels[0] as Vector2).y)
		var track := absf((wheels[1] as Vector2).x - (wheels[0] as Vector2).x)
		state["pitch"] = atan2(front - back, base) if not is_nan(front) and not is_nan(back) else 0.0
		state["roll"] = atan2(right - left, track) if not is_nan(left) and not is_nan(right) else 0.0
	state["vy"] = vy
	chassis.global_position = origin


static func _mean(values: Array) -> float:
	var total := 0.0
	var count := 0
	for value: float in values:
		if not is_nan(value):
			total += value
			count += 1
	return total / float(count) if count > 0 else NAN


## Soft things the chassis went through come back into play after a moment.
static func _expire_skips(chassis: CharacterBody3D, state: Dictionary) -> void:
	var skip: Dictionary = state["skip"]
	if skip.is_empty():
		return
	var now := Time.get_ticks_msec()
	for id: Variant in skip.keys():
		if int(skip[id]) > now:
			continue
		skip.erase(id)
		var body := instance_from_id(int(id)) as PhysicsBody3D
		if body != null and is_instance_valid(body):
			chassis.remove_collision_exception_with(body)


## The rendered pose for a chassis position and state: heading, then the ground's
## tilt plus the lean. (Basis.from_euler is YXZ: yaw, then pitch, then roll.)
static func body_transform(at: Vector3, state: Dictionary) -> Transform3D:
	var pitch := float(state.get("pitch", 0.0)) + float(state.get("lean_pitch", 0.0))
	var roll := float(state.get("roll", 0.0)) + float(state.get("lean_roll", 0.0))
	return Transform3D(Basis.from_euler(Vector3(pitch, float(state["yaw"]), roll)), at)
