extends Node

## Authority: host. --layout-test builds many yards in a row (every size, many
## seeds, the first houses of the town) and checks each one for the things that
## look broken in screenshots: solid pieces inside each other (a hedge through
## the house, a shed in the pool, a tree trunk in a wall), props and the rake
## starting inside something or off the yard, and work spots (weeds, litter,
## windows, gutters) buried inside a solid where nobody can reach them, and
## flower beds lying across the front walk or each other. Prints
## one [LayoutTest] line per problem and a summary. Run with --start-zone=lot.
##
## Then every neighborhood (--hood's sweep, levels/town/hood_styles.gd) at
## every size on HOOD_SEEDS, with the same checks plus the house contract (art
## chunk 6): the yard took the hood's style and one of its archetypes, the
## HouseBody's boxes stay inside the house's rectangle, roof leaves, gutters and
## windows are out in the open (never inside a wall, a dormer or a chimney),
## gutters run along both eaves, the roof has at least
## Constants.ART_YARD_ROOF_SPOTS_MIN leaves to clear, the spigot is on a wall,
## the yard's dressing stays within Constants.ART_YARD_MAX_VISUALS, and every
## hood's yard for one seed and size has the same trees, hiding spots, hedges,
## pool, litter and weed count (the hood is only a look).

const _HoodStyles = preload("res://levels/town/hood_styles.gd")
const SEEDS_PER_SIZE: int = 12
const HOOD_SEEDS: Array[int] = [1000, 8919]
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
			var lot := await _load(world, seed_value, size)
			var found := _check(lot, "size %d seed %d" % [size, seed_value])
			problems.append_array(found)
			yards += 1
	# Every neighborhood's yards: the same checks, and the house contract.
	var had_hood := str(options.get("hood"))
	var most_visuals := {}
	# The first hood's gameplay layout per size and seed: every other hood must match it.
	var layouts := {}
	for hood: String in _HoodStyles.ids():
		options.set("hood", hood)
		for size: int in 3:
			for seed_value: int in HOOD_SEEDS:
				var lot := await _load(world, seed_value, size)
				var label := "%s size %d seed %d" % [hood, size, seed_value]
				problems.append_array(_check(lot, label))
				problems.append_array(_check_house(lot, hood, label))
				if lot != null:
					var key := "%d/%d" % [size, seed_value]
					var layout := _gameplay_layout(lot)
					if not layouts.has(key):
						layouts[key] = [hood, layout]
					elif layouts[key][1] != layout:
						problems.append("%s: the gameplay layout differs from %s's (trees, hiding spots, litter, hedges, pool or weeds moved with the hood)" % [label, layouts[key][0]])
					var visuals := lot.get_node("Dressing").find_children("*", "GeometryInstance3D", true, false).size()
					most_visuals[hood] = maxi(int(most_visuals.get(hood, 0)), visuals)
					if visuals > Constants.ART_YARD_MAX_VISUALS:
						problems.append("%s: the yard's dressing has %d visuals (budget %d)" % [label, visuals, Constants.ART_YARD_MAX_VISUALS])
				yards += 1
	options.set("hood", had_hood)
	for line: String in problems:
		print("[LayoutTest] %s" % line)
	var ok := problems.is_empty()
	result = {"ok": ok, "yards": yards, "problems": problems.size(), "yard_visuals": most_visuals, "done": true}
	print("[LayoutTest] most visuals in a yard's dressing, by hood: %s" % most_visuals)
	print("[LayoutTest] %d yards checked, %d problems, all ok: %s" % [yards, problems.size(), ok])


## What the hood must never move (lot_generator.gd keeps the gameplay rng and
## its taken areas frozen): the trees, hiding spots, hedges, pool and litter,
## and how many weeds there are to pull.
func _gameplay_layout(lot: Node3D) -> Array:
	var trees: Array = lot.get_node("Dressing").get("_trees")
	var hides := []
	for child: Node in lot.get_children():
		if str(child.name) in ["Shed", "BigBin", "Hedge"]:
			hides.append([str(child.name), (child as Node3D).position.snapped(Vector3.ONE * 0.01)])
	var spots := []
	var weeds := 0
	var tasks := lot.get_node_or_null("JobTasks")
	if tasks != null:
		for index: int in int(tasks.call("spot_count")):
			var spot: Dictionary = tasks.call("spot", index)
			var task := str(spot["task"])
			if task in ["pick_litter", "trim_hedges", "skim_pool"]:
				spots.append([task, (spot["at"] as Vector3).snapped(Vector3.ONE * 0.01)])
			elif task == "pull_weeds":
				weeds += 1
	return [trees.duplicate(), hides, spots, weeds]


## Frees the yard and loads seed_value's at size, with every task; waits for
## it to be built and its colliders registered.
func _load(world: Node, seed_value: int, size: int) -> Node3D:
	var options := Net.dev_options()
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
	return lot


## The house contract on a hood's yard (levels/lots/lot_generator.gd, art chunk 6).
func _check_house(lot: Node3D, hood: String, label: String) -> Array[String]:
	var out: Array[String] = []
	if lot == null:
		return out
	if str(lot.get_meta("hood_style", "")) != hood:
		out.append("%s: the yard's style is %s" % [label, lot.get_meta("hood_style", "?")])
	var house := lot.get_node_or_null("Dressing/House") as Node3D
	var body := lot.get_node_or_null("Dressing/HouseBody") as Node3D
	if house == null or body == null:
		out.append("%s: no House or HouseBody" % label)
		return out
	var spec: Dictionary = house.get_meta("house_spec", {})
	var archetype := str(spec.get("archetype", ""))
	if not _HoodStyles.archetypes_for(hood, int(spec.get("stories", 1))).has(archetype):
		out.append("%s: archetype %s is not one of the hood's" % [label, archetype])
	if str(lot.get_meta("archetype", "")) != archetype:
		out.append("%s: lot meta archetype %s, house %s" % [label, lot.get_meta("archetype", ""), archetype])
	var dressing := lot.get_node("Dressing") as Node3D
	var at := dressing.to_local(house.global_position)
	var width := float(spec.get("width", 0.0))
	var depth := float(spec.get("depth", 0.0))
	var rect := Rect2(at.x - width * 0.5 - 0.6, at.z - depth * 0.5 - 0.6, width + 1.2, depth + 3.6).grow(0.1)
	var boxes: Array[AABB] = []
	for shape: Node in body.get_children():
		var box := (shape as CollisionShape3D).shape as BoxShape3D
		var center := dressing.to_local((shape as Node3D).global_position)
		var aabb := AABB(center - box.size * 0.5, box.size)
		boxes.append(aabb)
		if not rect.encloses(Rect2(aabb.position.x, aabb.position.z, aabb.size.x, aabb.size.z)):
			out.append("%s: a HouseBody box %s leaves the house's rectangle %s" % [label, aabb, rect])
	if boxes.is_empty():
		out.append("%s: HouseBody has no shapes" % label)
	# Roof leaves, gutters and windows are out in the open; gutters on both eaves.
	var space := lot.get_world_3d().direct_space_state
	var tasks := lot.get_node_or_null("JobTasks")
	var eaves := {"front": 0, "back": 0}
	var roof_spots := 0
	if tasks != null:
		for index: int in int(tasks.call("spot_count")):
			var spot: Dictionary = tasks.call("spot", index)
			var task := str(spot["task"])
			if not task in ["clear_roof", "clean_gutters", "wash_windows"]:
				continue
			var point: Vector3 = spot["at"]
			if task == "clear_roof":
				roof_spots += 1
			if task == "clean_gutters":
				eaves["front" if (spot["normal"] as Vector3).z > 0.0 else "back"] += 1
			if _inside_solid(space, lot, point):
				out.append("%s: a %s spot is inside %s at %s" % [label, task, _what_is_at(space, lot, point), lot.to_local(point)])
	var size := clampi(int(lot.get("yard_size")), 0, 2)
	if roof_spots < Constants.ART_YARD_ROOF_SPOTS_MIN[size]:
		out.append("%s: only %d roof leaves (at least %d)" % [label, roof_spots, Constants.ART_YARD_ROOF_SPOTS_MIN[size]])
	if int(eaves["front"]) == 0 or int(eaves["back"]) == 0:
		out.append("%s: gutters front %d, back %d" % [label, eaves["front"], eaves["back"]])
	# The spigot hangs on a wall: within 0.3 m of a HouseBody box.
	var spigot: Array = spec.get("spigot", [])
	if spigot.size() == 2:
		var point: Vector3 = at + (spigot[0] as Vector3)
		var nearest := INF
		for box: AABB in boxes:
			var inside := point.clamp(box.position, box.end)
			nearest = minf(nearest, inside.distance_to(point))
		if nearest > 0.3:
			out.append("%s: the spigot is %.2f m from the house" % [label, nearest])
	else:
		out.append("%s: the house has no spigot" % label)
	return out


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
	# Flower beds keep off the front walk and off each other (lot_generator.gd
	# metas front_walk and bed_rects, yard space).
	var dressing := lot.get_node_or_null("Dressing")
	if dressing != null:
		var walk: Rect2 = dressing.get_meta("front_walk", Rect2())
		var beds: Array = dressing.get_meta("bed_rects", [])
		for index: int in beds.size():
			var bed: Rect2 = beds[index]
			if walk.has_area() and bed.intersects(walk):
				out.append("%s: a flower bed %s lies across the front walk %s" % [label, bed, walk])
			for other_index: int in range(index + 1, beds.size()):
				if bed.intersects(beds[other_index] as Rect2):
					out.append("%s: two flower beds overlap (%s, %s)" % [label, bed, beds[other_index]])
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
