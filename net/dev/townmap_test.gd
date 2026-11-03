extends Node

## Authority: host. --townmap-test (with --town-map) checks Gutterford's layout
## (net/town/town_map.gd, driving chunk B): every yard slot is its own ground,
## clear of every road and of the houses across the street; every curb point is
## on a road; a route from Homie Depot's pad reaches every house's curb along
## the roads; the ground is what it looks like (asphalt, concrete, grass,
## water); Homie Depot's STORE_LAYOUT reservations never overlap and cover the
## shops' sites; TownColliders has one house per yard slot; a yard generated
## from a house's seed and hood builds that house (its HouseBody is the walls
## art's HouseBuilder gives it); and the job site hides its slot
## and gives it back. A joined client named Target must build the same town
## ("town_site" in the probe report: layout, colliders, site). Each step prints
## a [TownmapTest] line. Chunk D adds the site and zone steps, chunk E the
## spread-out build and the streaming steps.

const _HouseBuilder = preload("res://levels/town/house_builder.gd")
const _Hoods = preload("res://net/town/neighborhoods.gd")
const _StoreDressing = preload("res://levels/dressing/store_dressing.gd")
const _JobBoard = preload("res://levels/job_board.gd")
const _Surroundings = preload("res://levels/dressing/surroundings.gd")
const _BuildQueue = preload("res://levels/build_queue.gd")
const _Streamer = preload("res://levels/town/town_streamer.gd")
## No single step of the world's build may take longer than this (ms, headless):
## steps are one tree, one body, one parcel's solids. A stall is a frame, and a
## frame past ENet's patience drops a joining player (driving chunk E).
const BUILD_STEP_MAX_MS: float = 400.0
## The job board's posts stand 2.5 m apart (levels/job_board.gd _build_board).
const JOB_BOARD_FOOTPRINT := Vector2(2.7, 0.4)
## Which STORE_LAYOUT reservations hold each shop's counter and buy area.
const SHOP_RESERVATIONS: Dictionary = {
	"homie_depot": ["checkout", "garden_center"],
	"rustys": ["rustys"],
	"lunch_money": ["lunch_money"],
	"snak_o_matic": ["snak_o_matic"],
	"back_room": ["back_room"],
}
## The yard whose house the parity step generates: the third on Maple Row.
const PARITY_HOUSE: int = 2
## The house whose request the job-site steps pick (driving chunk D), then the next.
const SITE_HOUSE: int = 2

static var result: Dictionary = {}

var _started: bool = false


func _process(_delta: float) -> void:
	if _started or not Net.is_host():
		return
	var world := get_tree().get_first_node_in_group("world")
	var town := get_tree().get_first_node_in_group("town")
	if world == null or town == null or (town.get("houses") as Array).is_empty():
		return
	_started = true
	_run(world, town)


func _run(world: Node, town: Node) -> void:
	if not bool(world.call("is_town_map")):
		_finish(false, ["not the connected town: run with --town-map"])
		return
	var waited := 0.0
	while Net.peer_ids().size() < 2 and waited < 8.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	var problems: Array[String] = []
	_check_slots(problems)
	_check_roads(problems)
	_check_surfaces(problems)
	_check_store(problems)
	# The connected town loads the picked job's yard on its own (driving chunk D):
	# clear it (once the client has it, so nothing it asks of it goes astray), so
	# every slot has its house and the parity step builds the yard it asks for.
	await get_tree().create_timer(3.0).timeout
	world.call("_free_lot")
	await get_tree().physics_frame
	# The town's solids and dressing are built over its first frames (levels/build_queue.gd).
	await _check_build(problems)
	_check_colliders(world, problems)
	await _check_streaming(world, problems)
	await _check_parity(world, town, problems)
	_check_site(world, problems)
	await _check_job_at_house(world, town, problems)
	# Give the client time to have the town's seeds and its colliders before it reports.
	await get_tree().create_timer(1.5).timeout
	_finish(problems.is_empty(), problems)


func _verdict(ok: bool, line: String, problems: Array[String]) -> void:
	print("[TownmapTest] %s: %s" % [line, ok])
	if not ok:
		problems.append(line)


## Yards are their own ground: not on each other, not on a road, not on the
## houses across the street.
func _check_slots(problems: Array[String]) -> void:
	var count := TownMap.house_count()
	var expected := 0
	for hood: Dictionary in _Hoods.HOODS:
		expected += int(hood["houses"])
	_verdict(count == expected and count == 47, "%d yard slots for %d houses" % [count, expected], problems)
	var overlaps := 0
	var yards: Array[Rect2] = []
	for house_id: int in count:
		yards.append(TownMap.yard_rect(house_id))
	for index: int in yards.size():
		for other: int in range(index + 1, yards.size()):
			if yards[index].intersects(yards[other]):
				overlaps += 1
	var on_roads := 0
	for yard: Rect2 in yards:
		if _rect_on_road(yard):
			on_roads += 1
	_verdict(overlaps == 0 and on_roads == 0, "yards apart (%d overlaps) and off the roads (%d on one)" % [overlaps, on_roads], problems)
	var across_bad := 0
	for slot: Dictionary in TownMap.dressing_slots():
		var rect := TownMap.dressing_rect(slot)
		if _rect_on_road(rect) or yards.any(func(yard: Rect2) -> bool: return yard.intersects(rect)):
			across_bad += 1
	_verdict(across_bad == 0, "%d houses across the street, %d on a yard or road" % [TownMap.dressing_slots().size(), across_bad], problems)
	var inside := 0
	for yard: Rect2 in yards:
		var bounds := TownMap.TOWN_BOUNDS
		if Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z).encloses(yard):
			inside += 1
	_verdict(inside == count, "every yard inside the town's bounds (%d of %d)" % [inside, count], problems)
	_verdict(TownMap.slot_of(2).get("index", -1) == 2 and TownMap.yard_transform(2).basis.is_equal_approx(Basis.IDENTITY), "house 2 is the third yard on Maple Row, facing +Z", problems)


## Whether a rect (x, z) touches any road's asphalt or sidewalk. Roads are
## sampled every meter along their centerline against the rect grown by their
## half width.
func _rect_on_road(rect: Rect2) -> bool:
	for edge: Array in TownMap.road_edges():
		var a := TownMap.edge_from(edge)
		var b := TownMap.edge_to(edge)
		var grown := rect.grow(TownMap.edge_half_width(edge) - 0.01)
		var steps := maxi(1, int(a.distance_to(b)))
		for step: int in steps + 1:
			var at := a.lerp(b, float(step) / float(steps))
			if grown.has_point(Vector2(at.x, at.z)):
				return true
	return false


## Curbs are on the road, and every house can be driven to from the store.
func _check_roads(problems: Array[String]) -> void:
	var far_curbs := 0
	for house_id: int in TownMap.house_count():
		var curb := TownMap.curb_point(house_id)
		if TownMap.distance_to_road(curb) > 6.0 or TownMap.surface_at(curb) != &"asphalt":
			far_curbs += 1
	_verdict(far_curbs == 0, "every curb point on a road (%d off)" % far_curbs, problems)
	var pad := Vector3(10.0, 0.0, 8.0)
	var bad_routes := 0
	var longest := 0.0
	for house_id: int in TownMap.house_count():
		var curb := TownMap.curb_point(house_id)
		var path := TownMap.route(pad, curb)
		if path.size() < 2 or path[0].distance_to(pad) > 10.0 or path[path.size() - 1].distance_to(curb) > 6.0:
			bad_routes += 1
			continue
		# Every leg runs along a road: its middle is on one.
		var length := 0.0
		for index: int in range(1, path.size()):
			length += path[index - 1].distance_to(path[index])
			if TownMap.distance_to_road((path[index - 1] + path[index]) * 0.5) > 0.5:
				bad_routes += 1
				break
		longest = maxf(longest, length)
	_verdict(bad_routes == 0, "a road route from the store to every curb (%d bad, longest %.0f m)" % [bad_routes, longest], problems)
	var nodes := TownMap.road_nodes()
	var dangling := 0
	for edge: Array in TownMap.road_edges():
		if not nodes.has(edge[0]) or not nodes.has(edge[1]):
			dangling += 1
	_verdict(dangling == 0 and TownMap.curb_segments().size() > 0, "%d roads, %d curbs, %d broken" % [TownMap.road_edges().size(), TownMap.curb_segments().size(), dangling], problems)


func _check_surfaces(problems: Array[String]) -> void:
	var county := (TownMap.COUNTY_BEND + TownMap.DEPOT_JUNCTION) * 0.5
	var yard := TownMap.yard_transform(PARITY_HOUSE).origin
	var lake := Vector3(TownMap.LAKE.get_center().x, 0.0, TownMap.LAKE.get_center().y)
	var maple_z := TownMap.STREET_Z[0]
	var sidewalk := Vector3(TownMap.slot_x(0, 3), 0.0, maple_z - TownMap.STREET_WIDTH * 0.5 - 1.3)
	var driveway := TownMap.yard_transform(PARITY_HOUSE) * Vector3(0.0, 0.0, 12.0)
	var seen := [TownMap.surface_at(county), TownMap.surface_at(yard), TownMap.surface_at(lake), TownMap.surface_at(sidewalk), TownMap.surface_at(driveway)]
	var ok := seen == [&"asphalt", &"grass", &"water", &"concrete", &"concrete"]
	_verdict(ok, "ground: County Road %s, a yard %s, the lake %s, a sidewalk %s, a driveway %s" % seen, problems)
	var regions := [TownMap.region_of(Vector3(0.0, 0.0, 0.0)), TownMap.region_of(yard), TownMap.region_of(Vector3(150.0, 0.0, 200.0))]
	_verdict(regions == ["store", "maple_row", "country"], "regions: %s" % [regions], problems)
	var respawn := TownMap.respawn_point(yard + Vector3(0.0, -30.0, 0.0))
	_verdict(TownMap.surface_at(respawn) == &"concrete", "a fall in a yard respawns on the sidewalk (%s)" % respawn, problems)


## Homie Depot's reservations: no two overlap, and each shop's counter and buy
## area are inside its own.
func _check_store(problems: Array[String]) -> void:
	var layout: Dictionary = Constants.STORE_LAYOUT
	var names: Array = layout.keys()
	var clashes: Array[String] = []
	for index: int in names.size():
		for other: int in range(index + 1, names.size()):
			var a: Rect2 = layout[names[index]]["rect"]
			var b: Rect2 = layout[names[other]]["rect"]
			if a.intersects(b):
				clashes.append("%s/%s" % [names[index], names[other]])
	var placed_outside := 0
	for entry_name: Variant in names:
		var entry: Dictionary = layout[entry_name]
		if entry.has("at"):
			var at: Vector3 = entry["at"]
			if not (entry["rect"] as Rect2).has_point(Vector2(at.x, at.z)):
				placed_outside += 1
	_verdict(clashes.is_empty() and placed_outside == 0, "%d store reservations, overlapping: %s, placed outside their rect: %d" % [names.size(), clashes, placed_outside], problems)
	var uncovered: Array[String] = []
	for shop: Variant in Constants.SHOP_SITES:
		var site: Dictionary = Constants.SHOP_SITES[shop]
		var rects: Array[Rect2] = []
		for key: Variant in SHOP_RESERVATIONS.get(shop, []):
			rects.append(layout[key]["rect"])
		if site.has("counter"):
			var counter: Vector3 = site["counter"]
			if not rects.any(func(rect: Rect2) -> bool: return rect.has_point(Vector2(counter.x, counter.z))):
				uncovered.append("%s counter" % shop)
		if site.has("area"):
			var area: Rect2 = site["area"]
			if not rects.any(func(rect: Rect2) -> bool: return rect.grow(0.01).encloses(area)):
				uncovered.append("%s area" % shop)
	_verdict(uncovered.is_empty(), "every shop's counter and area reserved (missing: %s)" % [uncovered], problems)
	# The pieces already standing on the lot: each inside a "store" reservation
	# and clear of every other owner's, so a new piece can't land on one.
	var misplaced: Array[String] = []
	for fixture: Array in _store_fixtures():
		var footprint: Rect2 = fixture[1]
		var held := false
		for entry_name: Variant in names:
			var entry: Dictionary = layout[entry_name]
			var rect: Rect2 = entry["rect"]
			if str(entry["owner"]) == "store":
				held = held or rect.grow(0.01).encloses(footprint)
			elif rect.intersects(footprint):
				misplaced.append("%s on %s" % [fixture[0], entry_name])
		if not held:
			misplaced.append("%s unreserved" % fixture[0])
	_verdict(misplaced.is_empty(), "the lot's fixed pieces reserved and clear (%s)" % [misplaced], problems)


## [name, footprint (x, z)] for every fixed piece the store dressing and the job
## board put on Homie Depot's lot.
func _store_fixtures() -> Array:
	var fixtures: Array = []
	var add := func(label: String, at: Vector3, size: Vector2) -> void:
		fixtures.append([label, Rect2(Vector2(at.x, at.z) - size * 0.5, size)])
	for at: Vector3 in _StoreDressing.PARKED_CARS:
		add.call("car %s" % at, at, _StoreDressing.CAR_FOOTPRINT)
	for at: Vector3 in _StoreDressing.LOT_LAMPS:
		add.call("lamp %s" % at, at, _StoreDressing.LAMP_FOOTPRINT)
	for at: Vector3 in _StoreDressing.TREE_ISLANDS:
		add.call("tree island %s" % at, at, Vector2.ONE * _StoreDressing.TREE_ISLAND_SIZE)
	add.call("cart corral", _StoreDressing.CART_CORRAL_AT, _StoreDressing.CART_CORRAL_FOOTPRINT)
	add.call("job board", _JobBoard.BOARD_AT, JOB_BOARD_FOOTPRINT)
	return fixtures


func _check_colliders(world: Node, problems: Array[String]) -> void:
	var colliders := world.get_node_or_null("TownColliders")
	if colliders == null:
		_verdict(false, "TownColliders built", problems)
		return
	var enabled := int(colliders.call("house_shapes_enabled"))
	_verdict(enabled == TownMap.house_count(), "TownColliders: %d shapes, one house per yard slot (%d)" % [int(colliders.call("shape_count")), enabled], problems)
	colliders.call("set_slot_enabled", PARITY_HOUSE, false)
	var off := int(colliders.call("house_shapes_enabled"))
	colliders.call("set_slot_enabled", PARITY_HOUSE, true)
	var back := int(colliders.call("house_shapes_enabled"))
	_verdict(off == enabled - 1 and back == enabled, "a slot's house turns off and on (%d, then %d)" % [off, back], problems)
	var space := (world as Node3D).get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(Vector3(200.0, 5.0, 200.0), Vector3(200.0, -5.0, 200.0), 1)
	var hit := space.intersect_ray(query)
	_verdict(not hit.is_empty() and absf(float((hit["position"] as Vector3).y) + 0.02) < 0.05, "the town's ground is solid out in the country (%s)" % hit.get("position", "nothing"), problems)
	# The town's grass and the border's sand share a height, so they must not overlap.
	var ground := world.get_node_or_null("TownDressing/Ground") as VisualInstance3D
	var border := world.get_node_or_null("BorderZone") as Node3D
	if ground != null and border != null:
		var reach := (ground.global_transform * ground.get_aabb()).end.z
		var sand := border.global_position.z - _Surroundings.GROUND_SIZE * 0.5
		_verdict(reach <= sand + 0.01, "the town's grass stops at the border's sand (z %.1f, sand from %.1f)" % [reach, sand], problems)
	else:
		_verdict(false, "the town's ground and the border zone exist", problems)


## Driving chunk E: the world's build is spread over frames (levels/build_queue.gd):
## it finishes, and no step of it took a frame on its own past BUILD_STEP_MAX_MS.
## The join's own longest frame is the CI check's (probe "join_stall_ms").
func _check_build(problems: Array[String]) -> void:
	var waited := 0.0
	while not _BuildQueue.is_drained(get_tree()) and waited < 20.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	var stats: Dictionary = _BuildQueue.stats
	_verdict(_BuildQueue.is_drained(get_tree()) and float(stats["max_step_ms"]) < BUILD_STEP_MAX_MS, "the world built in %d steps over %d frames, the longest step %.0f ms (%s), most in one frame %.0f ms (want under %.0f)" % [int(stats["steps"]), int(stats["frames"]), float(stats["max_step_ms"]), stats["max_step"], float(stats["max_frame_ms"]), BUILD_STEP_MAX_MS], problems)


## Driving chunk E: the streamer picks each chunk's level by distance. At the
## store nothing in town is near; on Mansion Hill its own chunks are LOD 0 and
## nobody else's (headless: the bookkeeping only, so no build is slow).
func _check_streaming(world: Node, problems: Array[String]) -> void:
	var streamer := world.get_node_or_null("TownStreamer")
	if streamer == null:
		_verdict(false, "TownStreamer built", problems)
		return
	var stats: Dictionary = _Streamer.stats
	streamer.call("set_focus_override", Vector3(10.0, 1.7, 8.0))
	var at_store := int(stats["chunks_lod0"])
	var hood := _Hoods.index_of("mansion_hill")
	var hill := Vector3(TownMap.slot_x(hood, 3), 1.7, TownMap.STREET_Z[hood])
	streamer.call("set_focus_override", hill)
	var waited := 0.0
	while int((stats["lod0_hoods"] as Dictionary).get("mansion_hill", 0)) < 1 and waited < 3.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	var hoods: Dictionary = stats["lod0_hoods"]
	var mansion := int(hoods.get("mansion_hill", 0))
	# Every yard whose chunk is LOD 0 has a parcel near; Maple Row, 500 m off, is out.
	var wrong := 0
	for house_id: int in TownMap.house_count():
		var level := int(streamer.call("level_of_house", house_id))
		var yard := TownMap.yard_transform(house_id).origin
		var away := Vector2(yard.x - hill.x, yard.z - hill.z).length()
		if level == 0 and away > Constants.STREAM_LOD0_METERS + Constants.STREAM_HYSTERESIS_METERS + TownMap.YARD_HALF + float(TownMap.SLOT_SPACING[hood]) * Constants.STREAM_SLOTS_PER_CHUNK:
			wrong += 1
		if TownMap.hood_id_of(house_id) == "maple_row" and level != 3:
			wrong += 1
	var far := int(stats["chunks_skyline"]) + int(stats["chunks_none"])
	var ok := at_store <= 4 and mansion >= 1 and wrong == 0 and far > 0
	_verdict(ok, "streaming: %d chunks LOD 0 at the store; on Mansion Hill %d of its own (%.1f s), LOD 0 by hood %s, %d yards at the wrong level, %d chunks far or out, of %d chunks" % [at_store, mansion, waited, hoods, wrong, far, int(stats["chunks"])], problems)
	streamer.call("set_focus_override", Vector3.INF)
	_check_stream_build(streamer, problems)


## The streamer's build path, which a headless peer never takes on its own: a
## chunk's LOD 0 and LOD 1 levels have a parcel per slot; a job site placed
## (or cleared) while the level is still being built is honored when it goes in
## (the race the driving:E review found); a grown-back lawn has its leaves (flat
## leaf cards, never a solid lump), a poached one its sign, a waiting homeowner
## stands on the porch and waves only when someone comes by.
func _check_stream_build(streamer: Node, problems: Array[String]) -> void:
	# A chunk of three on Maple Row whose slots nobody has hidden.
	var houses: Array = []
	for house_id: int in TownMap.house_count():
		var candidate: Array = streamer.call("chunk_houses", house_id)
		if candidate.size() >= 2 and candidate.all(func(other: int) -> bool: return not bool(streamer.call("is_slot_hidden", other))):
			houses = candidate
			break
	if houses.is_empty():
		_verdict(false, "stream build: a chunk with two open slots", problems)
		return
	var first := int(houses[0])
	var key := "Yard%d" % first
	var started := Time.get_ticks_usec()
	# Hidden while the chunk's later parcels are still being built.
	var near: Node3D = streamer.call("build_level_now", first, 0, func() -> void: streamer.call("set_slot_hidden", first, true))
	var near_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var parcels := 0
	for house_id: int in houses:
		if near != null and near.get_node_or_null("Yard%d" % house_id) != null:
			parcels += 1
	var hid_mid := near != null and near.get_node_or_null(key) != null and not (near.get_node(key) as Node3D).visible
	# Shown again while LOD 1 is being built (built hidden, so this is the other way round).
	var far: Node3D = streamer.call("build_level_now", first, 1, func() -> void: streamer.call("set_slot_hidden", first, false))
	var shown_mid := far != null and far.get_node_or_null(key) != null and (far.get_node(key) as Node3D).visible
	var near_shown := near != null and is_instance_valid(near) and (near.get_node(key) as Node3D).visible
	_verdict(near != null and parcels == houses.size() and hid_mid and shown_mid and near_shown, "stream build: LOD 0 of houses %s has %d/%d parcels (%.0f ms); hidden mid-build stays hidden %s, shown mid-build is shown %s (LOD 0 too %s)" % [houses, parcels, houses.size(), near_ms, hid_mid, shown_mid, near_shown], problems)
	# What the town says, on that LOD 0 parcel.
	var parcel := near.get_node_or_null(key) as Node3D if near != null and is_instance_valid(near) else null
	if parcel == null:
		_verdict(false, "stream build: the LOD 0 parcel to dress", problems)
		return
	var leaves_at := Time.get_ticks_usec()
	var leaves: Node3D = _Streamer._leaf_drifts(parcel, 1.0, 1234)
	var leaves_ms := float(Time.get_ticks_usec() - leaves_at) / 1000.0
	var far_leaves: Node3D = _Streamer._leaf_drifts(parcel, 1.0, 1234, true)
	var none: Node3D = _Streamer._leaf_drifts(parcel, 0.0, 1234)
	var flat := false
	var cards := 0
	var far_cards := 0
	if leaves is MeshInstance3D and far_leaves is MeshInstance3D:
		var mesh := (leaves as MeshInstance3D).mesh
		var box := mesh.get_aabb()
		cards = mesh.surface_get_array_len(0) if mesh.get_surface_count() > 0 else 0
		far_cards = (far_leaves as MeshInstance3D).mesh.surface_get_array_len(0)
		# Lying on the lawn: nothing a truck could visibly drive through.
		flat = box.size.y < 0.25 and box.position.y > -0.05
	var sign_node: Node3D = _Streamer._rival_sign(1234)
	var waiting: Node3D = _Streamer._waiting_owner(parcel, 1234)
	parcel.add_child(waiting)
	var alone := _Streamer.someone_passing(waiting)
	# ...and does wave at a player coming up the street.
	var passer := get_tree().get_first_node_in_group("players") as Node3D
	var seen := false
	if passer != null:
		waiting.global_position = passer.global_position + Vector3(Constants.STREAM_WAVE_METERS * 0.5, 0.0, 0.0)
		seen = _Streamer.someone_passing(waiting)
	waiting.queue_free()
	_verdict(flat and cards > 0 and far_cards > 0 and far_cards < cards and none == null and sign_node != null and not alone and seen, "stream build: a grown-back lawn's leaves lie flat %s (%d vertices near in %.1f ms, %d far), a clean lawn has none %s, the sign %s, the homeowner waits without waving at nobody %s and sees a player come by %s" % [flat, cards, leaves_ms, far_cards, none == null, sign_node != null, not alone, seen], problems)
	if leaves != null:
		leaves.free()
	if far_leaves != null:
		far_leaves.free()
	if sign_node != null:
		sign_node.free()
	streamer.call("drop_levels_of", first)


## The house a town slot stands for is the house the job yard builds there:
## generate that house's yard (in its neighborhood) and compare its HouseBody
## with the walls art's HouseBuilder gives that house (request_for, the same
## request the town's parcels make: gap-specs/critic.md C25). The town draws and
## collides its slots with art's LotBuilder from the same request (driving chunk E).
func _check_parity(world: Node, town: Node, problems: Array[String]) -> void:
	var entry: Dictionary = town.call("house", PARITY_HOUSE)
	var hood := TownMap.hood_id_of(PARITY_HOUSE)
	var options := Net.dev_options()
	var had_seed := int(options.get("job_seed"))
	var had_size := int(options.get("yard_size"))
	var had_hood := str(options.get("hood"))
	options.set("job_seed", int(entry["seed"]))
	options.set("yard_size", int(entry["size"]))
	options.set("hood", hood)
	world.call("_load_job_lot")
	var lot := get_tree().get_first_node_in_group("job_lot") as Node3D
	var waited := 0
	while (lot == null or not bool(lot.get("is_generated"))) and waited < 120:
		await get_tree().physics_frame
		lot = get_tree().get_first_node_in_group("job_lot") as Node3D
		waited += 1
	var body := lot.get_node_or_null("Dressing/HouseBody") as Node3D if lot != null else null
	var request := _HouseBuilder.request_for(hood, int(entry["seed"]), int(entry["size"]))
	var walls: Array = _HouseBuilder.spec_for(request).get("solids", [])
	var house_at: Vector3 = request["at"]
	var same := body != null and not walls.is_empty() and body.get_child_count() == walls.size()
	if same:
		for index: int in walls.size():
			var shape := body.get_child(index) as CollisionShape3D
			var size: Vector3 = (shape.shape as BoxShape3D).size
			var at := lot.to_local(shape.global_position)
			same = same and at.is_equal_approx(house_at + (walls[index][0] as Vector3)) and size.is_equal_approx(walls[index][1])
	_verdict(same, "house %d's yard builds its %s house (%s, %d walls at %s)" % [PARITY_HOUSE, hood, request["archetype"], walls.size(), house_at], problems)
	# Let the client finish loading the yard (and asking after it) before it goes.
	await get_tree().create_timer(2.0).timeout
	world.call("_free_lot")
	options.set("job_seed", had_seed)
	options.set("yard_size", had_size)
	options.set("hood", had_hood)
	await get_tree().physics_frame


## The job site takes a slot: its house and colliders go; moving on gives them back.
func _check_site(world: Node, problems: Array[String]) -> void:
	var colliders := world.get_node_or_null("TownColliders")
	var streamer := world.get_node_or_null("TownStreamer")
	var lot_zone := world.get_node("LotZone") as Node3D
	var home := lot_zone.global_transform
	world.call("place_job_site", TownMap.yard_transform(PARITY_HOUSE), PARITY_HOUSE)
	var placed := lot_zone.global_position.is_equal_approx(TownMap.yard_transform(PARITY_HOUSE).origin)
	var hidden := not bool(colliders.call("is_slot_enabled", PARITY_HOUSE)) and bool(streamer.call("is_slot_hidden", PARITY_HOUSE))
	world.call("place_job_site", TownMap.yard_transform(PARITY_HOUSE + 1), PARITY_HOUSE + 1)
	var moved := bool(colliders.call("is_slot_enabled", PARITY_HOUSE)) and not bool(streamer.call("is_slot_hidden", PARITY_HOUSE)) and not bool(colliders.call("is_slot_enabled", PARITY_HOUSE + 1))
	# Back where it was, with no house hidden (no yard is loaded).
	world.call("place_job_site", home, -1)
	var restored := int(colliders.call("house_shapes_enabled")) == TownMap.house_count() and (streamer.call("hidden_slots") as Array).is_empty()
	_verdict(placed and hidden and moved and restored, "the job site hides its slot (placed %s, hidden %s, handed on %s, restored %s)" % [placed, hidden, moved, restored], problems)


## Driving chunk D: the job lives at the client's real house.
##   d1. A request from house SITE_HOUSE, picked on the board: its yard loads at
##       that house's slot (LotZone there, the slot's dressing house hidden and
##       its collider off, exactly one HouseBody: the yard's own).
##   d2. Walking into the yard is LOT and the crew has arrived (the homeowner's
##       clock), which locks the pick; paid with the host still in it, the yard
##       stays and the pick is open again (chaining from the truck). CI checks a
##       client reads the same lock ("town_site" job_locked and job_stage).
##   d3. The host goes more than SITE_FREE_DISTANCE away: the paid yard goes and
##       the slot's house is back.
##   d4. The next job (house SITE_HOUSE + 1) loads at its own house. Its yard,
##       the street and the store are LOT, TOWN and STORE on the host (CI checks
##       the client heard the same, "host_zones"), and leaves raked off it there
##       are gone on the client too (CI: the client's lot_work). It stays loaded,
##       so CI compares both peers' town_site and lot_layout.
func _check_job_at_house(world: Node, town: Node, problems: Array[String]) -> void:
	var board := get_tree().get_first_node_in_group("job_board")
	var colliders := world.get_node_or_null("TownColliders")
	var streamer := world.get_node_or_null("TownStreamer")
	var lot_zone := world.get_node("LotZone") as Node3D
	var host := Net.local_peer_id()
	var lot := await _pick(world, town, board, SITE_HOUSE)
	if lot == null:
		_verdict(false, "d1. house %d's request picked: no yard loaded" % SITE_HOUSE, problems)
		return
	var site := TownMap.yard_transform(SITE_HOUSE)
	var placed := lot_zone.global_position.distance_to(site.origin) < 0.01 and int(lot.get("house_id")) == SITE_HOUSE and int(world.call("job_site_house")) == SITE_HOUSE
	var hidden := not bool(colliders.call("is_slot_enabled", SITE_HOUSE)) and bool(streamer.call("is_slot_hidden", SITE_HOUSE))
	var bodies := lot.find_children("HouseBody", "", true, false).size()
	_verdict(placed and hidden and bodies == 1, "d1. house %d's yard loads at its slot %s (placed %s, slot hidden %s, %d HouseBody)" % [SITE_HOUSE, site.origin, placed, hidden, bodies], problems)
	_teleport(host, site * Vector3(0.0, 0.3, 5.0))
	await get_tree().create_timer(0.6).timeout
	var arrived := Net.player_zone(host) == Net.Zone.LOT and bool(Campaign.get("_job_clock_started")) and lot.has_meta("crew_arrived")
	# Arrived and unpaid: the pick is locked, from the yard's replicated stage.
	var locked := int(lot.get("stage")) == 1 and bool(world.call("job_locked"))
	world.call("finish_with_pay", 40)
	await get_tree().create_timer(1.2).timeout
	var kept := is_instance_valid(lot) and lot.is_inside_tree() and not Campaign.is_job_open()
	# Paid with the host still standing in it: the next job can be taken from here.
	var chainable := kept and int(lot.get("stage")) == 2 and Net.player_zone(host) == Net.Zone.LOT and not bool(world.call("job_locked"))
	_verdict(arrived and locked and kept and chainable, "d2. in the yard: zone %s, crew arrived %s, locked %s; paid with the host in it, the yard stays %s and the next job can be taken %s" % [Net.Zone.keys()[Net.player_zone(host)], arrived, locked, kept, chainable], problems)
	_teleport(host, Vector3(site.origin.x + Constants.SITE_FREE_DISTANCE + 20.0, 0.3, TownMap.STREET_Z[0] + TownMap.STREET_WIDTH * 0.5 + 1.2))
	var waited := 0.0
	while is_instance_valid(lot) and lot.is_inside_tree() and waited < 4.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	await get_tree().physics_frame
	var freed := not (is_instance_valid(lot) and lot.is_inside_tree())
	var shown := bool(colliders.call("is_slot_enabled", SITE_HOUSE)) and not bool(streamer.call("is_slot_hidden", SITE_HOUSE))
	_verdict(freed and shown and Net.player_zone(host) == Net.Zone.TOWN, "d3. %.0f m away the paid yard goes (%s after %.1f s), its house is back %s, host in %s" % [Constants.SITE_FREE_DISTANCE + 20.0, freed, waited, shown, Net.Zone.keys()[Net.player_zone(host)]], problems)
	var next_house := SITE_HOUSE + 1
	lot = await _pick(world, town, board, next_house)
	if lot == null:
		_verdict(false, "d4. house %d's request picked: no yard loaded" % next_house, problems)
		return
	site = TownMap.yard_transform(next_house)
	var seen: Array[String] = []
	for spot: Vector3 in [site * Vector3(-3.0, 0.3, 4.0), site * Vector3(0.0, 0.3, 33.6), Vector3(2.0, 0.3, 4.0)]:
		_teleport(host, spot)
		await get_tree().create_timer(0.6).timeout
		seen.append(Net.Zone.keys()[Net.player_zone(host)])
	var field := lot.get_node_or_null("LeafField")
	if field != null:
		for offset: Vector3 in [Vector3(-6.0, 0.0, 6.0), Vector3(6.0, 0.0, 6.0), Vector3(0.0, 0.0, -2.0)]:
			field.call("host_mulch", site * offset, 3.0)
	await get_tree().create_timer(0.5).timeout
	var cleaned := float(field.call("cleaned_fraction")) if field != null else 0.0
	var at_house := lot_zone.global_position.distance_to(site.origin) < 0.01 and int(world.call("job_site_house")) == next_house
	_verdict(at_house and seen == ["LOT", "TOWN", "STORE"] and cleaned > 0.0, "d4. house %d's yard at its slot %s; yard, street, store: %s; leaves cleared %.3f" % [next_house, at_house, seen, cleaned], problems)


## Host: a request from this house, picked on the board; waits for its yard.
## The yard (generated), or null.
func _pick(world: Node, town: Node, board: Node, house: int) -> Node:
	town.call("dev_request", house)
	await get_tree().create_timer(0.3).timeout
	var offers: Array = board.get("offers")
	var index := -1
	for at: int in offers.size():
		if int((offers[at] as Dictionary).get("house_id", -1)) == house:
			index = at
	if index < 0:
		return null
	board.call("request_choose", index)
	var waited := 0.0
	while waited < 6.0:
		var lot := get_tree().get_first_node_in_group("job_lot")
		if lot != null and lot.is_inside_tree() and int(lot.get("house_id")) == house and bool(lot.get("is_generated")) and int(world.call("job_site_house")) == house:
			return lot
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	return null


func _teleport(peer_id: int, at: Vector3) -> void:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			node.call("send_teleport", Transform3D(Basis.IDENTITY, at))


func _finish(ok: bool, problems: Array) -> void:
	result = {"ok": ok, "problems": problems, "done": true}
	print("[TownmapTest] all ok: %s" % ok)
