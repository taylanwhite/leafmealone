extends RefCounted

## Authority: none (pure queries). R2b: the one way the stage asks "is anything in
## the way?": a sphere swept through the world (mask 1) and the vehicles
## (Constants.VEHICLE_LAYER), past people and loose things. StageCam keeps its eye
## clear with it, the two-shot picks its side with it and the escort finds its way
## round a hedge to the van door with it (docs/DECISIONS.md "R2b: the stage sweep").
## People (players, the crew) and loose props are never obstacles here: a camera
## about someone looks past them, and the pair walks past them.

const MASK: int = 1 | Constants.VEHICLE_LAYER


## Bodies a sweep goes through: every player, NICE BOY and loose prop.
static func passable(tree: SceneTree) -> Array[RID]:
	var out: Array[RID] = []
	if tree == null:
		return out
	for group: StringName in [&"players", &"crew", &"props"]:
		for node: Node in tree.get_nodes_in_group(group):
			if node is CollisionObject3D:
				out.append((node as CollisionObject3D).get_rid())
	return out


## How far along from -> to (0..1) a sphere of this radius gets before it touches
## something solid. 1 = clear all the way.
static func reach(world: World3D, from: Vector3, to: Vector3, radius: float, exclude: Array[RID]) -> float:
	if world == null or from.distance_to(to) < 0.001:
		return 1.0
	var space := world.direct_space_state
	if space == null:
		return 1.0
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, from)
	query.motion = to - from
	query.collision_mask = MASK
	query.exclude = exclude
	query.collide_with_areas = false
	# Already inside something at the start: nothing to pull toward.
	if not space.intersect_shape(query, 1).is_empty():
		return 1.0
	var result := space.cast_motion(query)
	if result.is_empty():
		return 1.0
	return clampf(float(result[0]), 0.0, 1.0)


## Whether a sphere of this radius at `at` overlaps something solid.
static func inside(world: World3D, at: Vector3, radius: float, exclude: Array[RID]) -> bool:
	if world == null or world.direct_space_state == null:
		return false
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, at)
	query.collision_mask = MASK
	query.exclude = exclude
	return not world.direct_space_state.intersect_shape(query, 1).is_empty()


## Whether a sphere passes from -> to without touching anything solid.
static func clear(world: World3D, from: Vector3, to: Vector3, radius: float, exclude: Array[RID]) -> bool:
	return reach(world, from, to, radius, exclude) >= 0.999
