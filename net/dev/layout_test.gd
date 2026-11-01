extends Node

## Authority: host. --layout-test builds many yards in a row (every size, many
## seeds, the first houses of the town) and checks each one for the things that
## look broken in screenshots: solid pieces inside each other (a hedge through
## the house, a shed in the pool, a tree trunk in a wall), props and the rake
## starting inside something or off the yard, and work spots (weeds, litter,
## windows, gutters) buried inside a solid where nobody can reach them. Prints
## one [LayoutTest] line per problem and a summary. Run with --start-zone=lot.

const SEEDS_PER_SIZE: int = 12
## Overlaps smaller than this, in meters of penetration, are touching, not clipping.
const TOLERANCE: float = 0.06
## Solids allowed to touch: the floor holds everything up, the curb rings the yard.
const IGNORED: Array[String] = ["Floor", "Curb"]

static var result: Dictionary = {}

var _started: bool = false


func _process(_delta: float) -> void:
	if _started or not Net.is_host() or get_tree().get_first_node_in_group("job_lot") == null:
		return
	_started = true
	_run()


func _run() -> void:
	var world := get_tree().get_first_node_in_group("world")
	var options := Net.dev_options()
	var problems: Array[String] = []
	var yards := 0
	var seeds: Array[int] = []
	for index: int in SEEDS_PER_SIZE:
		seeds.append(1000 + index * 7919)
	for size: int in 3:
		for seed_value: int in seeds:
			options.set("job_seed", seed_value)
			options.set("yard_size", size)
			options.set("all_tasks", true)
			world.call("_free_lot")
			await get_tree().physics_frame
			await get_tree().physics_frame
			world.call("_load_job_lot")
			var lot := get_tree().get_first_node_in_group("job_lot") as Node3D
			var waited := 0
			while (lot == null or not bool(lot.get("is_generated"))) and waited < 60:
				await get_tree().physics_frame
				lot = get_tree().get_first_node_in_group("job_lot") as Node3D
				waited += 1
			# Colliders register on the next physics step.
			await get_tree().physics_frame
			await get_tree().physics_frame
			var found := _check(lot, "size %d seed %d" % [size, seed_value])
			problems.append_array(found)
			yards += 1
	for line: String in problems:
		print("[LayoutTest] %s" % line)
	var ok := problems.is_empty()
	result = {"ok": ok, "yards": yards, "problems": problems.size(), "done": true}
	print("[LayoutTest] %d yards checked, %d problems, all ok: %s" % [yards, problems.size(), ok])


func _check(lot: Node3D, label: String) -> Array[String]:
	var out: Array[String] = []
	if lot == null:
		out.append("%s: the yard never loaded" % label)
		return out
	var space := lot.get_world_3d().direct_space_state
	var solids := _solids(lot)
	# Solid against solid: their bounds overlap by more than a touch on every axis.
	# The yard's solids are boxes and upright cylinders, so bounds are close enough.
	var bounds: Array[AABB] = []
	for shape: CollisionShape3D in solids:
		bounds.append(shape.global_transform * shape.shape.get_debug_mesh().get_aabb())
	for index: int in solids.size():
		for other_index: int in range(index + 1, solids.size()):
			if solids[index].get_parent() == solids[other_index].get_parent():
				continue
			# The roof sits on the house: one building, built to touch.
			if _same_structure(solids[index].get_parent(), solids[other_index].get_parent()):
				continue
			var overlap := bounds[index].intersection(bounds[other_index])
			if overlap.size.x > TOLERANCE and overlap.size.y > TOLERANCE and overlap.size.z > TOLERANCE:
				out.append("%s: %s overlaps %s by %.2f x %.2f m" % [label, _describe(solids[index].get_parent()), _describe(solids[other_index].get_parent()), overlap.size.x, overlap.size.z])
	# Props and the rake start on the yard, outside every solid.
	for prop_name: String in ["TrashCan", "Wheelbarrow", "Gnome", "Rake"]:
		var prop := lot.get_node_or_null(prop_name) as Node3D
		if prop == null:
			continue
		var local := lot.to_local(prop.global_position)
		if absf(local.x) > 19.5 or absf(local.z) > 19.5:
			out.append("%s: %s starts off the yard at %s" % [label, prop_name, local])
		if _inside_solid(space, lot, prop.global_position + Vector3(0.0, 0.2, 0.0)):
			out.append("%s: %s starts inside %s at %s" % [label, prop_name, _what_is_at(space, lot, prop.global_position + Vector3(0.0, 0.2, 0.0)), local])
	# Work spots on the ground can be reached: not inside a solid.
	var tasks := lot.get_node_or_null("JobTasks")
	if tasks != null:
		for index: int in int(tasks.call("spot_count")):
			var spot: Dictionary = tasks.call("spot", index)
			var task := str(spot["task"])
			if not task in ["pull_weeds", "pick_litter"]:
				continue
			var at: Vector3 = spot["at"]
			if _inside_solid(space, lot, at + Vector3(0.0, 0.15, 0.0)):
				out.append("%s: a %s spot is inside %s at %s" % [label, task, _what_is_at(space, lot, at + Vector3(0.0, 0.15, 0.0)), lot.to_local(at)])
	return out


func _solids(lot: Node3D) -> Array[CollisionShape3D]:
	var out: Array[CollisionShape3D] = []
	for node: Node in lot.find_children("*", "CollisionShape3D", true, false):
		var shape := node as CollisionShape3D
		if shape.disabled or shape.shape == null:
			continue
		var body := shape.get_parent()
		if not body is StaticBody3D or _ignored(body):
			continue
		out.append(shape)
	return out


func _inside_solid(space: PhysicsDirectSpaceState3D, lot: Node3D, point: Vector3) -> bool:
	var query := PhysicsPointQueryParameters3D.new()
	query.position = point
	query.collide_with_bodies = true
	for hit: Dictionary in space.intersect_point(query, 8):
		var other := hit.get("collider") as Node
		if other != null and other is StaticBody3D and lot.is_ancestor_of(other) and not _ignored(other):
			return true
	return false


const HOUSE_PARTS: Array[String] = ["HouseBody", "Roof"]


func _same_structure(a: Node, b: Node) -> bool:
	return HOUSE_PARTS.has(String(a.name)) and HOUSE_PARTS.has(String(b.name))


## What a point is inside of, for the report.
func _what_is_at(space: PhysicsDirectSpaceState3D, lot: Node3D, point: Vector3) -> String:
	var query := PhysicsPointQueryParameters3D.new()
	query.position = point
	query.collide_with_bodies = true
	for hit: Dictionary in space.intersect_point(query, 8):
		var other := hit.get("collider") as Node
		if other != null and other is StaticBody3D and lot.is_ancestor_of(other) and not _ignored(other):
			return _describe(other)
	return "?"


func _ignored(node: Node) -> bool:
	for name_part: String in IGNORED:
		if String(node.name).begins_with(name_part):
			return true
	return false


func _describe(node: Node) -> String:
	var parent := node.get_parent()
	return "%s (in %s)" % [node.name, parent.name if parent != null else "?"]
