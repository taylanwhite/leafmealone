extends RefCounted

## Authority: none (pure queries). R2b: the one way the stage asks "is anything in
## the way?": a sphere swept through the world (mask 1) and the vehicles
## (Constants.VEHICLE_LAYER), past people and loose things. StageCam keeps its eye
## clear with it, the two-shot picks its side with it and the escort finds its way
## round a hedge to the van door with it (docs/DECISIONS.md "R2b: the stage sweep").
## People (players, the crew) and loose props are never obstacles here: a camera
## about someone looks past them, and the pair walks past them.

const _Trees = preload("res://props/trees.gd")

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


## fx-net: the upright things a camera can't see through and the physics can't
## see at all (street lamps and scenery trees have no collider): [[base, radius]]
## for each within `within` m (flat) of `near`. A street lamp is found by its
## lens (group "street_lamps", props/prop_catalog.gd), whose parent stands at the
## post's foot; a tree by group "seasonal" (props/trees.gd), its trunk a share of
## its height, an evergreen's skirt its whole low spread.
static func posts(tree: SceneTree, near: Vector3, within: float) -> Array:
	var out: Array = []
	if tree == null:
		return out
	for lens: Node in tree.get_nodes_in_group(&"street_lamps"):
		var post := lens.get_parent() as Node3D
		if post == null or not post.is_inside_tree():
			continue
		if _flat(post.global_position, near) <= within:
			out.append([post.global_position, Constants.STAGE_LAMP_POST_RADIUS])
	for node: Node in tree.get_nodes_in_group(&"seasonal"):
		var plant := node as Node3D
		if plant == null or not "kind" in plant or not plant.is_visible_in_tree():
			continue
		if _flat(plant.global_position, near) > within:
			continue
		var height := plant.global_basis.get_scale().x * _Trees.BUILD_HEIGHT
		var share := Constants.VAN_TREE_SPREAD.x if _Trees.EVERGREEN.has(str(plant.get("kind"))) else Constants.STAGE_TRUNK_SHARE
		out.append([plant.global_position, height * share])
	return out


## Whether a sight line from -> to passes every one of posts() by its radius
## plus margin (flat: they all stand taller than a face).
static func posts_clear(found: Array, from: Vector3, to: Vector3, margin: float) -> bool:
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	for post: Array in found:
		var at := post[0] as Vector3
		var point := Vector2(at.x, at.z)
		if Geometry2D.get_closest_point_to_segment(point, a, b).distance_to(point) < float(post[1]) + margin:
			return false
	return true


## Whether no post of posts() stands within `clear` m (flat, past its radius) of `eye`.
static func lens_clear(found: Array, eye: Vector3, clear: float) -> bool:
	for post: Array in found:
		if _flat(post[0] as Vector3, eye) - float(post[1]) < clear:
			return false
	return true


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
