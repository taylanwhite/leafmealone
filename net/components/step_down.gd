extends RefCounted

## Authority: whoever calls it; pure geometry. Where riders land when they step
## off a vehicle (p1-arrive, docs/GAME.md "Stepping off Chefty"): each rider gets
## their own spot from their seat, never inside a solid and never on a spot
## another rider has, facing somewhere sensible but never into a solid or a lamp
## post at arm's length. Only the world's solids count (StaticBody3D), never
## loose props or people, which move and which peers can disagree about, so every
## peer that works out the same arrival gets the same answer. props: the drawn
## things with no collider (lamp posts, hydrants, mailboxes) as [global
## transform, local AABB] boxes, which the caller gathers (world.gd
## arrival_obstacles).


## Where each rider lands. truck: the vehicle's place, flat (basis a yaw, origin
## on the ground). own: each rider's own spot in the truck's space, in the order
## riders pick (seat order). Returns one world transform per entry of own,
## facing look_at (world space).
static func slots(space: PhysicsDirectSpaceState3D, truck: Transform3D, own: Array, look_at: Vector3, exclude: Array[RID] = [], props: Array = []) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var taken: Array[Vector3] = []
	for local: Variant in own:
		var choices: Array = [local]
		choices.append_array(Constants.CHEFTY_STEP_DOWN_SPARE)
		var chosen := Vector3.INF
		for choice: Variant in choices:
			var at := ground(space, truck * (choice as Vector3), exclude)
			if _near_any(at, taken) or not clear_at(space, at, exclude, props):
				continue
			chosen = at
			break
		if chosen == Vector3.INF:
			# Nothing's clear: the own spot, and room-to-stand eases them apart.
			chosen = ground(space, truck * (local as Vector3), exclude)
			print("[StepDown] no clear spot by the truck at %s (%d props): landing at %s" % [truck.origin, props.size(), chosen])
		taken.append(chosen)
		out.append(Transform3D(landing_facing(space, truck.origin, chosen, look_at, exclude, props), chosen))
	return out


## Facing look_at from at, but never more than STEP_DOWN_FACE_FROM_TRUCK off
## facing straight away from the truck (at truck_at): on the far side of it the
## house (or the store) is behind the truck, and you'd land staring at its cab
## or mirror (play, p1-arrive, at Homie Depot). Then off anything at arm's length.
static func landing_facing(space: PhysicsDirectSpaceState3D, truck_at: Vector3, at: Vector3, look_at: Vector3, exclude: Array[RID] = [], props: Array = []) -> Basis:
	var away := Vector2(at.x - truck_at.x, at.z - truck_at.z)
	var toward := look_at
	if away.length() > 0.01:
		var away_yaw := atan2(-away.x, -away.y)
		var to := look_at - at
		var look_yaw := atan2(-to.x, -to.z) if Vector2(to.x, to.z).length() > 0.01 else away_yaw
		var limit := Constants.STEP_DOWN_FACE_FROM_TRUCK
		var yaw := away_yaw + clampf(angle_difference(away_yaw, look_yaw), -limit, limit)
		toward = at + Basis(Vector3.UP, yaw) * Vector3.FORWARD * 10.0
	return facing(space, at, toward, exclude, props)


## The truck's place for slots(): its yaw (the way its nose points, -Z) and its
## position on the ground.
static func flat(xform: Transform3D) -> Transform3D:
	var forward := -xform.basis.z
	forward.y = 0.0
	var yaw := atan2(-forward.x, -forward.z) if forward.length() > 0.001 else 0.0
	return Transform3D(Basis(Vector3.UP, yaw), xform.origin)


## The ground under at (a curb, a lawn, the street), within a meter and a half
## up or down, or at itself when there's none.
static func ground(space: PhysicsDirectSpaceState3D, at: Vector3, exclude: Array[RID] = []) -> Vector3:
	if space == null:
		return at
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.5, at + Vector3.DOWN * 1.5, 1)
	query.exclude = exclude
	var hit := space.intersect_ray(query)
	if hit.is_empty() or not hit["collider"] is StaticBody3D:
		return at
	return Vector3(at.x, (hit["position"] as Vector3).y, at.z)


## Whether a person fits standing at at: no solid in the way, and no drawn prop
## standing within STEP_DOWN_POST_ROOM.
static func clear_at(space: PhysicsDirectSpaceState3D, at: Vector3, exclude: Array[RID] = [], props: Array = []) -> bool:
	if prop_distance(at, props) < Constants.STEP_DOWN_POST_ROOM:
		return false
	if space == null:
		return true
	var capsule := CapsuleShape3D.new()
	capsule.radius = Constants.STEP_DOWN_CAPSULE.x
	capsule.height = Constants.STEP_DOWN_CAPSULE.y
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	# Its bottom just clear of the ground it stands on.
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3(0.0, capsule.height * 0.5 + 0.12, 0.0))
	query.collision_mask = 1
	query.exclude = exclude
	for hit: Dictionary in space.intersect_shape(query, 8):
		if hit.get("collider") is StaticBody3D:
			return false
	return true


## Facing look_at from at, turned off anything (a solid, a lamp post) closer than
## STEP_DOWN_FACE_CLEAR in the middle of the view (STEP_DOWN_FACE_CONE either side).
static func facing(space: PhysicsDirectSpaceState3D, at: Vector3, look_at: Vector3, exclude: Array[RID] = [], props: Array = []) -> Basis:
	var to := look_at - at
	to.y = 0.0
	var yaw := atan2(-to.x, -to.z) if to.length() > 0.01 else 0.0
	if view_clear(space, at, yaw, exclude, props):
		return Basis(Vector3.UP, yaw)
	for turn: float in Constants.STEP_DOWN_FACE_TURNS:
		if view_clear(space, at, yaw + turn, exclude, props):
			return Basis(Vector3.UP, yaw + turn)
	return Basis(Vector3.UP, yaw)


## Whether the middle of the view from at, facing yaw, is clear to arm's length.
static func view_clear(space: PhysicsDirectSpaceState3D, at: Vector3, yaw: float, exclude: Array[RID] = [], props: Array = []) -> bool:
	var cone := Constants.STEP_DOWN_FACE_CONE
	# A drawn prop up to the knees or higher anywhere in the cone, to arm's length.
	for turn: float in [0.0, -cone * 0.5, cone * 0.5, -cone, cone]:
		var dir := Basis(Vector3.UP, yaw + turn) * Vector3.FORWARD
		var step := 0.3
		while step <= Constants.STEP_DOWN_FACE_CLEAR:
			if prop_distance(at + dir * step, props, at.y + 0.5) < 0.12:
				return false
			step += 0.3
	if space == null:
		return true
	var eye := at + Vector3.UP * 1.5
	for turn: float in [0.0, -cone, cone]:
		var ahead := Basis(Vector3.UP, yaw + turn) * Vector3.FORWARD * Constants.STEP_DOWN_FACE_CLEAR
		# Low and high: a hedge's top and a pole both count.
		for lift: float in [0.0, -0.8]:
			var from := eye + Vector3.UP * lift
			var query := PhysicsRayQueryParameters3D.create(from, from + ahead, 1)
			query.exclude = exclude
			var hit := space.intersect_ray(query)
			if not hit.is_empty() and hit["collider"] is StaticBody3D:
				return false
	return true


## How far (m, flat) at is from the nearest drawn prop that stands taller than
## STEP_DOWN_PROP_MIN_HEIGHT over the ground (or whose top is above min_top),
## INF with none. A box with a scaled transform is measured in its own space.
static func prop_distance(at: Vector3, props: Array, min_top: float = -INF) -> float:
	var nearest := INF
	for entry: Variant in props:
		var xform: Transform3D = entry[0]
		var box: AABB = entry[1]
		var top := (xform * (box.position + Vector3(0.0, box.size.y, 0.0))).y
		if top - at.y < Constants.STEP_DOWN_PROP_MIN_HEIGHT or top < min_top:
			continue
		var local := xform.affine_inverse() * at
		var dx := maxf(maxf(box.position.x - local.x, local.x - box.end.x), 0.0)
		var dz := maxf(maxf(box.position.z - local.z, local.z - box.end.z), 0.0)
		nearest = minf(nearest, Vector2(dx, dz).length() * xform.basis.get_scale().x)
	return nearest


static func _near_any(at: Vector3, taken: Array[Vector3]) -> bool:
	for other: Vector3 in taken:
		if Vector2(at.x - other.x, at.z - other.z).length() < Constants.STEP_DOWN_SPACING:
			return true
	return false
