extends Node

## Authority: host. --townmap-test (with --town-map) checks Gutterford's layout
## (net/town/town_map.gd, driving chunk B): every yard slot is its own ground,
## clear of every road and of the houses across the street; every curb point is
## on a road; a route from Homie Depot's pad reaches every house's curb along
## the roads; the ground is what it looks like (asphalt, concrete, grass,
## water); Homie Depot's STORE_LAYOUT reservations never overlap and cover the
## shops' sites; TownColliders has one house per yard slot, and that house is
## the job yard's own (a yard generated from the house's seed puts its
## HouseBody where the town's collider is); and the job site hides its slot
## and gives it back. A joined client named Target must build the same town
## ("town_site" in the probe report: layout, colliders, site). Each step prints
## a [TownmapTest] line. Chunks D and E add the site/zone and streaming steps.

const _Fallback = preload("res://levels/town/fallback_house.gd")
const _Hoods = preload("res://net/town/neighborhoods.gd")
const _StoreDressing = preload("res://levels/dressing/store_dressing.gd")
const _JobBoard = preload("res://levels/job_board.gd")
const _Surroundings = preload("res://levels/dressing/surroundings.gd")
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
	_check_colliders(world, problems)
	await _check_parity(world, town, problems)
	_check_site(world, problems)
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


## The house the town shows at a slot is the house the job yard builds there:
## generate that house's yard and compare its HouseBody with the slot's collider.
func _check_parity(world: Node, town: Node, problems: Array[String]) -> void:
	var entry: Dictionary = town.call("house", PARITY_HOUSE)
	var options := Net.dev_options()
	var had_seed := int(options.get("job_seed"))
	var had_size := int(options.get("yard_size"))
	options.set("job_seed", int(entry["seed"]))
	options.set("yard_size", int(entry["size"]))
	world.call("_load_job_lot")
	var lot := get_tree().get_first_node_in_group("job_lot") as Node3D
	var waited := 0
	while (lot == null or not bool(lot.get("is_generated"))) and waited < 120:
		await get_tree().physics_frame
		lot = get_tree().get_first_node_in_group("job_lot") as Node3D
		waited += 1
	var body := lot.get_node_or_null("Dressing/HouseBody") as Node3D if lot != null else null
	var expected: Array = _Fallback.colliders(TownMap.hood_id_of(PARITY_HOUSE), int(entry["seed"]), int(entry["size"]))[0]
	var same := false
	if body != null:
		var shape := body.get_child(0) as CollisionShape3D
		var size: Vector3 = (shape.shape as BoxShape3D).size
		var at := lot.to_local(body.global_position)
		same = at.is_equal_approx(expected[0]) and size.is_equal_approx(expected[1])
	_verdict(same, "house %d's yard builds the house the town shows (%s)" % [PARITY_HOUSE, expected], problems)
	# Let the client finish loading the yard (and asking after it) before it goes.
	await get_tree().create_timer(2.0).timeout
	world.call("_free_lot")
	options.set("job_seed", had_seed)
	options.set("yard_size", had_size)
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
	# Put the site back where this world keeps it until driving chunk D.
	world.call("place_job_site", home, -1)
	var restored := int(colliders.call("house_shapes_enabled")) == TownMap.house_count() and (streamer.call("hidden_slots") as Array).is_empty()
	_verdict(placed and hidden and moved and restored, "the job site hides its slot (placed %s, hidden %s, handed on %s, restored %s)" % [placed, hidden, moved, restored], problems)


func _finish(ok: bool, problems: Array) -> void:
	result = {"ok": ok, "problems": problems, "done": true}
	print("[TownmapTest] all ok: %s" % ok)
