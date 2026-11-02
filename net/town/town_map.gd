class_name TownMap
extends RefCounted

## Authority: data, the same on every peer. Gutterford's fixed layout
## (docs/GAME.md, "Gutterford"): Homie Depot at the origin, County Road 9 east to
## Main Street (x 340), and the six neighborhood streets branching east off Main
## Street, one per neighborhood in net/town/neighborhoods.gd order. Every house
## has a fixed slot on its street by its id: ids run hood by hood in HOODS order,
## so house 2 is always the third yard on Maple Row. Nothing here depends on the
## town's seed; changing a street, a spacing, or a hood's house count moves
## houses, so bump LAYOUT_VERSION when you do.
##
## Yard space (a job yard, a slot): x and z in -20..20, the house at the back,
## the front edge at z +20, the street's centerline at z +27, the driveway at
## x 0. Yards are never rotated: a yard slot's transform is always yaw 0, so
## the yard faces +Z and its street runs along x on its +Z side. The dressing
## houses across the street face back (yaw PI).
##
## The road graph is nodes (ids to world points) and straight edges between
## them [a, b, width, kind, sidewalks]; route() runs A* over it. Kinds: "lot"
## (the store's parking lot), "depot" (Depot Road), "county" (County Road 9),
## "main" (Main Street) and "street" (a neighborhood street).

const _Hoods = preload("res://net/town/neighborhoods.gd")

const LAYOUT_VERSION: int = 1
## Everything that collides: the ground box and every town collider sit inside it.
const TOWN_BOUNDS := AABB(Vector3(-150.0, -5.0, -520.0), Vector3(1050.0, 60.0, 1040.0))
## Main Street runs north (-Z) to south (+Z) at this x, between these z.
const MAIN_X: float = 340.0
const MAIN_Z := Vector2(-450.0, 450.0)
const MAIN_WIDTH: float = 10.0
## Neighborhood streets, County Road 9 and Depot Road (neighborhood.gd's road width).
const STREET_WIDTH: float = 8.8
## Curb (0.3) plus sidewalk (2.0) either side of a road that has sidewalks.
const SIDEWALK: float = 2.3
## Each neighborhood's street: its centerline z and the distance between yard
## slots along it, in HOODS order (Maple Row, Dandelion Acres, Birchwood Commons,
## Oak Hollow, Lakeside, Mansion Hill). Streets alternate north and south of the
## town square, so each one up the list is a little farther from the store.
const STREET_Z: Array[float] = [-110.0, 130.0, -250.0, 270.0, -390.0, 410.0]
const SLOT_SPACING: Array[float] = [44.0, 44.0, 46.0, 48.0, 50.0, 60.0]
## The first slot's near edge starts this far east of Main Street's centerline
## (the corner lot stays open), and each street runs this far past its last slot.
const FIRST_SLOT_X: float = 380.0
const STREET_TAIL: float = 20.0
const YARD_HALF: float = 20.0
## The street's centerline in yard space, and where Chefty parks at the curb
## (the near lane, a little past the driveway).
const YARD_STREET_Z: float = 27.0
const CURB_POINT := Vector3(7.0, 0.0, 24.6)
## The driveway in yard space (x, z), concrete.
const DRIVEWAY := Rect2(-2.1, 3.0, 4.2, 17.5)
## County Road 9 leaves the store's loading bay, crosses Depot Road (x 27) and
## runs east to the town square on Main Street.
const BAY := Vector3(16.0, 0.0, 8.3)
const DEPOT_X: float = 27.0
const DEPOT_Z := Vector2(-150.0, 150.0)
const DEPOT_JUNCTION := Vector3(27.0, 0.0, 8.6)
## Where the store's own road (levels/dressing/store_dressing.gd) ends and the
## town's part of County Road 9 begins.
const COUNTY_BEND := Vector3(300.0, 0.0, 15.2)
const SQUARE := Vector3(340.0, 0.0, 15.2)
## The lake behind Lakeside's yards (x, z), water.
const LAKE := Rect2(352.0, -505.0, 470.0, 63.0)
## The NICE BOYS Regional Field Office (Satellite Annex B), at the north end of
## Main Street on its west side, facing the street.
const FIELD_OFFICE := Vector3(316.0, 0.0, -436.0)
## Edges the store's dressing already draws (store_dressing.gd), by "a|b".
const STORE_DRAWN: Array[String] = ["bay|depot_jct", "depot_n|depot_jct", "depot_jct|depot_s", "depot_jct|cr9_bend"]

static var _nodes: Dictionary = {}
static var _edges: Array = []
static var _astar: AStar3D = null
static var _astar_ids: Dictionary = {}
static var _dressing: Array = []
static var _trees: Array = []


## Whether this world is the connected town.
static func enabled(tree: SceneTree) -> bool:
	if tree == null:
		return false
	var world := tree.get_first_node_in_group("world")
	return world != null and world.has_method("is_town_map") and bool(world.call("is_town_map"))


# ---------------------------------------------------------------- slots

static func house_count() -> int:
	var total := 0
	for hood: Dictionary in _Hoods.HOODS:
		total += int(hood["houses"])
	return total


## {hood_index, index} for a house id, or {} past the last house.
static func slot_of(house_id: int) -> Dictionary:
	if house_id < 0:
		return {}
	var first := 0
	for hood_index: int in _Hoods.HOODS.size():
		var houses := int(_Hoods.HOODS[hood_index]["houses"])
		if house_id < first + houses:
			return {"hood_index": hood_index, "index": house_id - first}
		first += houses
	return {}


## The first house id on a hood's street, or -1.
static func first_house_of(hood_index: int) -> int:
	if hood_index < 0 or hood_index >= _Hoods.HOODS.size():
		return -1
	var first := 0
	for index: int in hood_index:
		first += int(_Hoods.HOODS[index]["houses"])
	return first


static func hood_id_of(house_id: int) -> String:
	var slot := slot_of(house_id)
	return "" if slot.is_empty() else str(_Hoods.HOODS[int(slot["hood_index"])]["id"])


## The x of slot index on a hood's street (the yard's center).
static func slot_x(hood_index: int, index: int) -> float:
	return FIRST_SLOT_X + SLOT_SPACING[hood_index] * (float(index) + 0.5)


## Where a house's yard is: yaw 0, the yard's center at the origin, facing +Z
## onto its street. Identity for an unknown house.
static func yard_transform(house_id: int) -> Transform3D:
	var slot := slot_of(house_id)
	if slot.is_empty():
		return Transform3D.IDENTITY
	var hood_index := int(slot["hood_index"])
	return Transform3D(Basis.IDENTITY, Vector3(slot_x(hood_index, int(slot["index"])), 0.0, STREET_Z[hood_index] - YARD_STREET_Z))


## The yard's ground in world x and z.
static func yard_rect(house_id: int) -> Rect2:
	var at := yard_transform(house_id).origin
	return Rect2(at.x - YARD_HALF, at.z - YARD_HALF, YARD_HALF * 2.0, YARD_HALF * 2.0)


## Where Chefty parks for this house: the near lane, just past the driveway.
static func curb_point(house_id: int) -> Vector3:
	return yard_transform(house_id) * CURB_POINT


## The test yard for --job-seed and offers with no house: the first Maple Row slot.
static func test_site_house() -> int:
	return first_house_of(0)


## The houses across each street from the yards, dressing only: [{hood,
## hood_index, index, xform, seed}], the same x as the yard opposite, facing the
## street (yaw PI). Seeds come from the slot, never from the town's seed.
static func dressing_slots() -> Array:
	if not _dressing.is_empty():
		return _dressing
	for hood_index: int in _Hoods.HOODS.size():
		var hood_id := str(_Hoods.HOODS[hood_index]["id"])
		# The hood's most common yard size.
		var sizes: Array = _Hoods.HOODS[hood_index]["sizes"]
		var size := 0
		for pick: int in sizes.size():
			if float(sizes[pick]) > float(sizes[size]):
				size = pick
		for index: int in int(_Hoods.HOODS[hood_index]["houses"]):
			var at := Vector3(slot_x(hood_index, index), 0.0, STREET_Z[hood_index] + YARD_STREET_Z)
			_dressing.append({
				"hood": hood_id, "hood_index": hood_index, "index": index, "size": size,
				"xform": Transform3D(Basis(Vector3.UP, PI), at),
				"seed": absi(hash(["dressing", hood_id, index])) % 2147483646 + 1,
			})
	return _dressing


## A dressing slot's ground in world x and z.
static func dressing_rect(slot: Dictionary) -> Rect2:
	var at: Vector3 = (slot["xform"] as Transform3D).origin
	return Rect2(at.x - YARD_HALF, at.z - YARD_HALF, YARD_HALF * 2.0, YARD_HALF * 2.0)


# ---------------------------------------------------------------- the road graph

## id -> world point.
static func road_nodes() -> Dictionary:
	_build_graph()
	return _nodes


## [a, b, width, kind, sidewalks] for every straight piece of road.
static func road_edges() -> Array:
	_build_graph()
	return _edges


static func edge_from(edge: Array) -> Vector3:
	return road_nodes()[edge[0]]


static func edge_to(edge: Array) -> Vector3:
	return road_nodes()[edge[1]]


static func edge_key(edge: Array) -> String:
	return "%s|%s" % [edge[0], edge[1]]


## How far out from the centerline this road's surface reaches (asphalt, then
## curb and sidewalk if it has them).
static func edge_half_width(edge: Array, with_sidewalks: bool = true) -> float:
	return float(edge[2]) * 0.5 + (SIDEWALK if with_sidewalks and bool(edge[4]) else 0.0)


static func _build_graph() -> void:
	if not _nodes.is_empty():
		return
	_nodes = {
		"bay": BAY,
		"depot_jct": DEPOT_JUNCTION,
		"depot_n": Vector3(DEPOT_X, 0.0, DEPOT_Z.x),
		"depot_s": Vector3(DEPOT_X, 0.0, DEPOT_Z.y),
		"cr9_bend": COUNTY_BEND,
		"square": SQUARE,
		"main_n": Vector3(MAIN_X, 0.0, MAIN_Z.x),
		"main_s": Vector3(MAIN_X, 0.0, MAIN_Z.y),
	}
	_edges = [
		["bay", "depot_jct", STREET_WIDTH, "lot", false],
		["depot_n", "depot_jct", STREET_WIDTH, "depot", true],
		["depot_jct", "depot_s", STREET_WIDTH, "depot", true],
		["depot_jct", "cr9_bend", STREET_WIDTH, "county", false],
		["cr9_bend", "square", STREET_WIDTH, "county", false],
	]
	# Main Street, cut at every junction from north to south.
	var stops: Array = [["main_n", MAIN_Z.x], ["square", SQUARE.z], ["main_s", MAIN_Z.y]]
	for hood_index: int in _Hoods.HOODS.size():
		var hood_id := str(_Hoods.HOODS[hood_index]["id"])
		var junction := hood_id + "_jct"
		var street_end := hood_id + "_end"
		var z := STREET_Z[hood_index]
		_nodes[junction] = Vector3(MAIN_X, 0.0, z)
		_nodes[street_end] = Vector3(street_end_x(hood_index), 0.0, z)
		stops.append([junction, z])
		_edges.append([junction, street_end, STREET_WIDTH, "street", true])
	stops.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) < float(b[1]))
	for index: int in stops.size() - 1:
		_edges.append([stops[index][0], stops[index + 1][0], MAIN_WIDTH, "main", true])


## Where a hood's street ends, past its last slot.
static func street_end_x(hood_index: int) -> float:
	return FIRST_SLOT_X + SLOT_SPACING[hood_index] * float(_Hoods.HOODS[hood_index]["houses"]) + STREET_TAIL


static func _closest_on(edge: Array, pos: Vector3) -> Vector3:
	var a := edge_from(edge)
	var b := edge_to(edge)
	var point := Geometry3D.get_closest_point_to_segment(Vector3(pos.x, 0.0, pos.z), a, b)
	point.y = 0.0
	return point


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## The index of the road edge nearest pos (by centerline).
static func nearest_edge(pos: Vector3) -> int:
	var best := -1
	var best_distance := INF
	var edges := road_edges()
	for index: int in edges.size():
		var distance := _flat_distance(pos, _closest_on(edges[index], pos))
		if distance < best_distance:
			best_distance = distance
			best = index
	return best


## The nearest point on any road's centerline, at y 0.
static func nearest_road_point(pos: Vector3) -> Vector3:
	var index := nearest_edge(pos)
	return Vector3.ZERO if index < 0 else _closest_on(road_edges()[index], pos)


## How far pos is from the nearest road's centerline.
static func distance_to_road(pos: Vector3) -> float:
	return _flat_distance(pos, nearest_road_point(pos))


static func _graph() -> AStar3D:
	if _astar != null:
		return _astar
	_astar = AStar3D.new()
	var nodes := road_nodes()
	var next := 0
	for id: Variant in nodes.keys():
		_astar_ids[id] = next
		_astar.add_point(next, nodes[id])
		next += 1
	for edge: Array in road_edges():
		_astar.connect_points(int(_astar_ids[edge[0]]), int(_astar_ids[edge[1]]))
	return _astar


static func _path_length(points: PackedVector3Array) -> float:
	var total := 0.0
	for index: int in range(1, points.size()):
		total += points[index - 1].distance_to(points[index])
	return total


## A drivable route along the roads: from the road point nearest from, through
## the junctions, to the road point nearest to. Empty only if the graph is.
static func route(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var start_edge := nearest_edge(from)
	var end_edge := nearest_edge(to)
	if start_edge < 0 or end_edge < 0:
		return out
	var edges := road_edges()
	var start := _closest_on(edges[start_edge], from)
	var finish := _closest_on(edges[end_edge], to)
	if start_edge == end_edge:
		out.append(start)
		if finish.distance_to(start) > 0.01:
			out.append(finish)
		return out
	var graph := _graph()
	var best := PackedVector3Array()
	var best_length := INF
	for leave: int in [0, 1]:
		for arrive: int in [0, 1]:
			var leave_id := int(_astar_ids[edges[start_edge][leave]])
			var arrive_id := int(_astar_ids[edges[end_edge][arrive]])
			var middle := graph.get_point_path(leave_id, arrive_id)
			if middle.is_empty():
				continue
			var candidate := PackedVector3Array([start])
			candidate.append_array(middle)
			candidate.append(finish)
			var length := _path_length(candidate)
			if length < best_length:
				best_length = length
				best = candidate
	# Drop points that repeat (a route that starts or ends on a junction).
	for point: Vector3 in best:
		if out.is_empty() or out[out.size() - 1].distance_to(point) > 0.01:
			out.append(point)
	return out


## The curbs along every road with sidewalks, [from, to] pairs at y 0 (for
## skateboard grinds). Each runs the edge's full length.
static func curb_segments() -> Array:
	var out: Array = []
	for edge: Array in road_edges():
		if not bool(edge[4]):
			continue
		var a := edge_from(edge)
		var b := edge_to(edge)
		var side := (b - a).normalized().cross(Vector3.UP)
		var offset := float(edge[2]) * 0.5 + 0.15
		for sign_value: float in [-1.0, 1.0]:
			out.append([a + side * offset * sign_value, b + side * offset * sign_value])
	return out


# ---------------------------------------------------------------- what's where

## What the ground is made of here: water (the lake), asphalt (a road or the
## store's lot), concrete (a sidewalk, a driveway, the store's walk), or grass.
static func surface_at(pos: Vector3) -> StringName:
	if LAKE.has_point(Vector2(pos.x, pos.z)):
		return &"water"
	var on_sidewalk := false
	for edge: Array in road_edges():
		var distance := _flat_distance(pos, _closest_on(edge, pos))
		if distance <= float(edge[2]) * 0.5:
			return &"asphalt"
		if bool(edge[4]) and distance <= edge_half_width(edge):
			on_sidewalk = true
	if on_sidewalk:
		return &"concrete"
	var flat := Vector2(pos.x, pos.z)
	if Constants.STORE_AREA.has_point(flat):
		# The store building's front walk is concrete; the lot is asphalt.
		return &"concrete" if pos.x < -9.0 else &"asphalt"
	var house_id := yard_at(pos)
	if house_id >= 0:
		var local := yard_transform(house_id).affine_inverse() * pos
		if DRIVEWAY.has_point(Vector2(local.x, local.z)):
			return &"concrete"
	return &"grass"


## The house whose yard pos stands in, or -1.
static func yard_at(pos: Vector3) -> int:
	for hood_index: int in _Hoods.HOODS.size():
		var yard_z := STREET_Z[hood_index] - YARD_STREET_Z
		if absf(pos.z - yard_z) > YARD_HALF:
			continue
		var spacing := SLOT_SPACING[hood_index]
		var index := floori((pos.x - FIRST_SLOT_X) / spacing)
		if index < 0 or index >= int(_Hoods.HOODS[hood_index]["houses"]):
			return -1
		if absf(pos.x - slot_x(hood_index, index)) > YARD_HALF:
			return -1
		return first_house_of(hood_index) + index
	return -1


## Which part of town pos is in: a neighborhood's id (its street, its yards, the
## houses across from them), "store" (Homie Depot's lot), or "country".
static func region_of(pos: Vector3) -> String:
	if Constants.STORE_AREA.has_point(Vector2(pos.x, pos.z)):
		return "store"
	for hood_index: int in _Hoods.HOODS.size():
		var z := STREET_Z[hood_index]
		if pos.x > MAIN_X + MAIN_WIDTH * 0.5 and pos.x < street_end_x(hood_index) + YARD_HALF and absf(pos.z - z) <= YARD_STREET_Z + YARD_HALF + 3.0:
			return str(_Hoods.HOODS[hood_index]["id"])
	# The lake is Lakeside's back yard.
	if LAKE.has_point(Vector2(pos.x, pos.z)):
		return "lakeside"
	return "country"


## A safe place to put someone who fell out of the world near pos: the store's
## spawn in the store's lot, else the sidewalk (or road edge) nearest them.
static func respawn_point(pos: Vector3) -> Vector3:
	if Constants.STORE_AREA.has_point(Vector2(pos.x, pos.z)):
		return Vector3(0.0, 0.1, 6.0)
	var index := nearest_edge(pos)
	if index < 0:
		return Vector3(0.0, 0.1, 6.0)
	var edge: Array = road_edges()[index]
	var on_road := _closest_on(edge, pos)
	var across := Vector3(pos.x - on_road.x, 0.0, pos.z - on_road.z)
	if across.length() < 0.01:
		across = (edge_to(edge) - edge_from(edge)).normalized().cross(Vector3.UP)
	var out := float(edge[2]) * 0.5 + (1.3 if bool(edge[4]) else 0.8)
	var spot := on_road + across.normalized() * out
	return Vector3(spot.x, 0.1, spot.z)


# ---------------------------------------------------------------- street furniture

## Street lamps: [[at, yaw]], alternating sides every Constants.TOWN_LAMP_SPACING
## along every town road with sidewalks (the store's own roads have theirs). The
## lamp's arm reaches out over the road.
static func lamp_spots() -> Array:
	var out: Array = []
	for edge: Array in road_edges():
		if not bool(edge[4]) or STORE_DRAWN.has(edge_key(edge)):
			continue
		var a := edge_from(edge)
		var b := edge_to(edge)
		var along := (b - a).normalized()
		var side := along.cross(Vector3.UP)
		var length := a.distance_to(b)
		var count := int(length / Constants.TOWN_LAMP_SPACING)
		for step: int in count:
			# Clear of the junctions at either end.
			var distance := (float(step) + 0.5) * length / float(maxi(count, 1))
			if distance < 12.0 or distance > length - 12.0:
				continue
			var sign_value := 1.0 if step % 2 == 0 else -1.0
			var at := a + along * distance + side * sign_value * (float(edge[2]) * 0.5 + 0.65)
			# The arm points back across the road: the lamp's +Z faces the centerline.
			var facing := -side * sign_value
			out.append([at, atan2(facing.x, facing.z)])
	return out


## Parked cars along the curbs: [[at, yaw, color_index]]. A few per street, on
## the far side from the yards, clear of the slots' driveways opposite.
static func car_spots() -> Array:
	var out: Array = []
	for hood_index: int in _Hoods.HOODS.size():
		var z := STREET_Z[hood_index] + STREET_WIDTH * 0.5 - 1.3
		var houses := int(_Hoods.HOODS[hood_index]["houses"])
		for index: int in range(1, houses, 3):
			# Between two dressing driveways.
			var x := slot_x(hood_index, index) + SLOT_SPACING[hood_index] * 0.5
			out.append([Vector3(x, 0.0, z), PI * 0.5, (hood_index + index) % 3])
	return out


## The landmarks, by name: {at, yaw} (yaw turns the piece's +Z toward where it
## faces). Visuals in levels/town/town_dressing.gd, solids in set_piece_solids().
static func landmarks() -> Dictionary:
	var oak := STREET_Z[_Hoods.index_of("oak_hollow")]
	var mansion := STREET_Z[_Hoods.index_of("mansion_hill")]
	return {
		# On the town square's plaza, read by everyone driving in from Homie Depot.
		"welcome_sign": {"at": Vector3(325.0, 0.0, 1.0), "yaw": -PI * 0.5},
		# The Founder's Rake: the town's statue, a rake six meters tall on a plinth.
		"founders_rake": {"at": Vector3(318.0, 0.0, -6.0), "yaw": -PI * 0.5},
		"plaza": {"at": Vector3(321.0, 0.0, -4.0), "yaw": 0.0},
		"field_office": {"at": FIELD_OFFICE, "yaw": PI * 0.5},
		# Arches over each street's mouth, just past Main Street's sidewalk.
		"hoa_arch": {"at": Vector3(MAIN_X + 14.0, 0.0, oak), "yaw": PI * 0.5},
		"mansion_gate": {"at": Vector3(MAIN_X + 14.0, 0.0, mansion), "yaw": PI * 0.5},
	}


## Half the distance between an arch's two pillars, across its street.
static func arch_half_span() -> float:
	return STREET_WIDTH * 0.5 + SIDEWALK + 0.7


## Solid boxes for the landmarks: [[center, size, yaw]] in world space.
static func set_piece_solids() -> Array:
	var marks := landmarks()
	var out: Array = []
	var office: Dictionary = marks["field_office"]
	out.append([(office["at"] as Vector3) + Vector3(0.0, 2.6, 0.0), Vector3(14.0, 5.2, 10.0), float(office["yaw"])])
	var rake: Dictionary = marks["founders_rake"]
	out.append([(rake["at"] as Vector3) + Vector3(0.0, 0.6, 0.0), Vector3(2.4, 1.2, 2.4), 0.0])
	var sign_at: Vector3 = marks["welcome_sign"]["at"]
	for side: float in [-1.0, 1.0]:
		out.append([sign_at + Vector3(0.0, 1.2, side * 3.4), Vector3(0.3, 2.4, 0.3), 0.0])
	for arch: String in ["hoa_arch", "mansion_gate"]:
		var at: Vector3 = marks[arch]["at"]
		for side: float in [-1.0, 1.0]:
			out.append([at + Vector3(0.0, 3.0, side * arch_half_span()), Vector3(1.0, 6.0, 1.0), 0.0])
	return out


## Lakeside's docks, one behind every second Lakeside yard: [[from, to]] at
## y 0, from the shore out over the water.
static func docks() -> Array:
	var out: Array = []
	var hood := _Hoods.index_of("lakeside")
	for index: int in range(0, int(_Hoods.HOODS[hood]["houses"]), 2):
		var x := slot_x(hood, index) + 8.0
		out.append([Vector3(x, 0.0, LAKE.end.y), Vector3(x, 0.0, LAKE.end.y - 14.0)])
	return out


## Trees out on the open land: [[at, height, kind, crown]]. Seeded by the layout
## only, clear of every road, slot, the store's lot, the lake and the landmarks.
static func country_trees() -> Array:
	if not _trees.is_empty():
		return _trees
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["gutterford_trees", LAYOUT_VERSION])
	var crowns: Array[String] = ["orange", "red", "yellow", "rust", "turning"]
	var out: Array = _trees
	# Also clear of the legacy ride's straight line east (net/components/ride.gd),
	# which Chefty still drives until it is drivable (driving chunk C1).
	var keep_out: Array[Rect2] = [Constants.STORE_AREA.grow(14.0), LAKE.grow(4.0), Rect2(MAIN_X, 4.0, TOWN_BOUNDS.end.x - MAIN_X, 32.0)]
	for house_id: int in house_count():
		keep_out.append(yard_rect(house_id).grow(3.0))
	for slot: Dictionary in dressing_slots():
		keep_out.append(dressing_rect(slot).grow(3.0))
	for mark: Dictionary in landmarks().values():
		var at: Vector3 = mark["at"]
		keep_out.append(Rect2(at.x - 14.0, at.z - 14.0, 28.0, 28.0))
	var attempts := 0
	while out.size() < Constants.TOWN_COUNTRY_TREES and attempts < Constants.TOWN_COUNTRY_TREES * 30:
		attempts += 1
		var at := Vector3(rng.randf_range(TOWN_BOUNDS.position.x + 10.0, TOWN_BOUNDS.end.x - 10.0), 0.0, rng.randf_range(TOWN_BOUNDS.position.z + 10.0, TOWN_BOUNDS.end.z - 10.0))
		var flat := Vector2(at.x, at.z)
		if keep_out.any(func(rect: Rect2) -> bool: return rect.has_point(flat)):
			continue
		if distance_to_road(at) < 14.0:
			continue
		var crowded := false
		for other: Array in out:
			if (other[0] as Vector3).distance_to(at) < 9.0:
				crowded = true
				break
		if crowded:
			continue
		var kind := "pine" if rng.randf() < 0.3 else "broadleaf"
		out.append([at, rng.randf_range(7.0, 11.0), kind, crowns[rng.randi() % crowns.size()]])
	return out


## A hash of the whole layout (slots, roads, furniture), for tests that check
## every peer built the same town.
static func layout_hash() -> int:
	var parts: Array = [LAYOUT_VERSION, house_count()]
	for house_id: int in house_count():
		parts.append(yard_transform(house_id).origin)
	for slot: Dictionary in dressing_slots():
		parts.append([(slot["xform"] as Transform3D).origin, slot["seed"]])
	for edge: Array in road_edges():
		parts.append([edge_from(edge), edge_to(edge), edge[2], edge[3], edge[4]])
	parts.append(lamp_spots().size())
	parts.append(car_spots().size())
	return hash(parts)
