extends RefCounted

## Authority: local, cosmetic, built once at world _ready in the connected town,
## the same on every peer (everything comes from net/town/town_map.gd or a fixed
## seed). Gutterford's ground and roads, the town square with the welcome sign
## and the Founder's Rake, street signs, the HOA arch, Mansion Hill's gate, the
## lake and its docks, the NICE BOYS Field Office, street lamps, mailboxes and
## curbside bins, parked cars, country trees, clouds, and people out walking.
## Also Homie Depot's town-only extras from Constants.STORE_LAYOUT: Marty's
## pallet ramp and the "NO NICENESS" sign. Nothing here collides; the matching
## solids are levels/town/town_colliders.gd. The houses are the streamer's
## (levels/town/town_streamer.gd).
##
## Small things stop drawing past Constants.TOWN_LAMP_VISIBLE_METERS (lamps) and
## TOWN_SMALL_VISIBLE_METERS (mailboxes, bins, flags). Mailboxes and bins are in
## group "town_knockables" (meta kind, house_id) for Chefty to knock over later
## (driving chunk C3).

const _Neighborhood = preload("res://levels/dressing/neighborhood.gd")
const _Surroundings = preload("res://levels/dressing/surroundings.gd")
const _LowPoly = preload("res://props/low_poly.gd")
const _Trees = preload("res://props/trees.gd")
const _YardModels = preload("res://props/yard_models.gd")
const _Surfaces = preload("res://props/surfaces.gd")
const _Pedestrians = preload("res://npcs/pedestrians.gd")
const _Hoods = preload("res://net/town/neighborhoods.gd")
const _Strings = preload("res://ui/strings.gd")
const _Colliders = preload("res://levels/town/town_colliders.gd")
const _BuildQueue = preload("res://levels/build_queue.gd")
const _StreetBuilder = preload("res://levels/town/street_builder.gd")
const _HoodStyles = preload("res://levels/town/hood_styles.gd")
const _PropBatch = preload("res://props/prop_batch.gd")
const _Outskirts = preload("res://levels/town/outskirts.gd")
const _TownLine = preload("res://levels/town/town_line.gd")

const GRASS := Color(0.42, 0.52, 0.3)
const ASPHALT := Color(0.3, 0.3, 0.32)
const CONCRETE := Color(0.72, 0.7, 0.66)
const WOOD := Color(0.55, 0.4, 0.27)
const PALLET := Color(0.7, 0.56, 0.38)
const STONE := Color(0.66, 0.64, 0.6)
const WATER := Color(0.28, 0.5, 0.62)
## Courtesy Lavender, the NICE BOYS' color (no insignia, no real agency).
const LAVENDER := Color(0.72, 0.66, 0.86)
const SIGN_GREEN := Color(0.16, 0.42, 0.26)
const CAR_COLORS: Array[Color] = [Color(0.3, 0.42, 0.62), Color(0.85, 0.82, 0.74), Color(0.55, 0.15, 0.15)]
## Seeds for the pieces that use one, so every peer builds the same town.
const SEED: int = 9091
## Where each yard's mailbox and curbside bin stand, in yard space.
const MAILBOX_AT := Vector3(3.2, 0.0, 19.9)
const BIN_AT := Vector3(-3.4, 0.0, 19.7)


static func dress(world: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "TownDressing"
	world.add_child(root)
	# Each piece is a BuildQueue step (levels/build_queue.gd), the ground first.
	_ground(root, world)
	_BuildQueue.later(root, func() -> void: _roads(root), "town roads")
	_BuildQueue.later(root, func() -> void: _square(root), "town square")
	_BuildQueue.later(root, func() -> void:
		_street_signs(root)
		_hoa_arch(root)
		_mansion_gate(root), "town signs")
	_BuildQueue.later(root, func() -> void: _lake(root), "town lake")
	_BuildQueue.later(root, func() -> void: _field_office(root), "town field office")
	_BuildQueue.later(root, func() -> void: _lamps(root), "town lamps")
	_BuildQueue.later(root, func() -> void: _curbside(root), "town curbside")
	_BuildQueue.later(root, func() -> void: _cars(root), "town cars")
	_country_trees(root)
	# The farmland, landmarks and tree rows between it all (driving:E2).
	_Outskirts.dress(root)
	# The hedgerow round the town, the closed roads and the hills past it (p1-world).
	_TownLine.dress(root)
	_BuildQueue.later(root, func() -> void: _store_extras(root, world.get_node_or_null("StoreZone") as Node3D), "town store extras")
	_walkers(root)
	for at: Vector3 in [Vector3(0.0, 0.0, 0.0), Vector3(560.0, 0.0, -250.0), Vector3(560.0, 0.0, 250.0)]:
		var sky := Node3D.new()
		sky.name = "Sky"
		root.add_child(sky)
		sky.position = at
		_BuildQueue.later(root, func() -> void: _Surroundings.clouds(sky, SEED + int(at.x + at.z)), "town clouds")
	return root


## Grass to the horizon under the whole town, a hair below the lot's floor. Its
## +Z edge stops where the border's own ground begins (both tops sit at y -0.02,
## so an overlap would z-fight grass against sand).
static func _ground(root: Node3D, world: Node3D) -> void:
	var bounds := TownMap.TOWN_BOUNDS
	var margin := Constants.TOWN_GROUND_MARGIN
	var start := Vector2(bounds.position.x - margin, bounds.position.z - margin)
	var end := Vector2(bounds.end.x + margin, bounds.end.z + margin)
	var border := world.get_node_or_null("BorderZone") as Node3D
	if border != null and border.position.z > bounds.end.z:
		end.y = minf(end.y, border.position.z - _Surroundings.GROUND_SIZE * 0.5)
	var size := end - start
	var center := (start + end) * 0.5
	var ground := _LowPoly.box(root, Vector3(size.x, 0.2, size.y), Vector3(center.x, -0.12, center.y), GRASS)
	ground.name = "Ground"
	_LowPoly.paint(ground, "grass")


## Every town road (the store's own are drawn by store_dressing.gd): Main Street
## cut at its junctions, the street mouths, County Road 9's last stretch.
static func _roads(root: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "Roads"
	root.add_child(holder)
	# The streets' storm drains, a few big chunks for the whole town.
	var batch := _PropBatch.new(holder, Constants.TOWN_STREET_PROP_CHUNK)
	var nodes := TownMap.road_nodes()
	# How far a road stops short of each junction, so crossings don't stack.
	var trims := {}
	for edge: Array in TownMap.road_edges():
		if str(edge[3]) == "main":
			continue
		for end: int in [0, 1]:
			var id: String = edge[end]
			if id.ends_with("_jct") or id == "square":
				trims[id] = maxf(float(trims.get(id, 0.0)), TownMap.edge_half_width(edge))
	for edge: Array in TownMap.road_edges():
		if TownMap.STORE_DRAWN.has(TownMap.edge_key(edge)):
			continue
		var a: Vector3 = nodes[edge[0]]
		var b: Vector3 = nodes[edge[1]]
		var along := (b - a).normalized()
		var main := str(edge[3]) == "main"
		var cut_a := float(trims.get(edge[0], 0.0)) if main else (TownMap.MAIN_WIDTH * 0.5 + TownMap.SIDEWALK if str(edge[0]).ends_with("_jct") else 0.0)
		var cut_b := float(trims.get(edge[1], 0.0)) if main else (TownMap.MAIN_WIDTH * 0.5 + TownMap.SIDEWALK if str(edge[1]) == "square" else 0.0)
		if str(edge[3]) == "street":
			_street(holder, str(edge[0]).trim_suffix("_jct"), a + along * cut_a, b - along * cut_b, batch)
		else:
			_Neighborhood.road(holder, a + along * cut_a, b - along * cut_b, float(edge[2]), bool(edge[4]))
	batch.call("commit")
	# The crossings: plain asphalt, and the sidewalk carried on across the side
	# opposite the road that joins.
	for id: Variant in trims:
		var at: Vector3 = nodes[id]
		var half := float(trims[id])
		var patch := _LowPoly.box(holder, Vector3(TownMap.MAIN_WIDTH, 0.1, half * 2.0), at + Vector3(0.0, -0.04, 0.0), ASPHALT)
		_LowPoly.paint(patch, "road", _Surfaces.road_params("none", TownMap.MAIN_WIDTH * 0.5, 3.0))
		var far_side := -1.0 if id != "square" else 1.0
		var walk_x := at.x + far_side * (TownMap.MAIN_WIDTH * 0.5 + 1.3)
		_LowPoly.paint(_LowPoly.box(holder, Vector3(2.0, 0.16, half * 2.0), Vector3(walk_x, 0.02, at.z), CONCRETE), "concrete")
		_LowPoly.paint(_LowPoly.box(holder, Vector3(0.3, 0.2, half * 2.0), Vector3(at.x + far_side * (TownMap.MAIN_WIDTH * 0.5 + 0.15), 0.0, at.z), CONCRETE.darkened(0.08)), "concrete")
	# Each neighborhood street ends in a curb.
	for hood_index: int in _Hoods.HOODS.size():
		var end_x := TownMap.street_end_x(hood_index)
		_LowPoly.paint(_LowPoly.box(holder, Vector3(0.3, 0.2, TownMap.STREET_WIDTH + TownMap.SIDEWALK * 2.0), Vector3(end_x + 0.15, 0.0, TownMap.STREET_Z[hood_index]), CONCRETE.darkened(0.08)), "concrete")


## A neighborhood's street in its own style (levels/town/street_builder.gd,
## driving:E2): its curbs (Mansion Hill's granite), its sidewalks (pavers on Oak
## Hollow and Mansion Hill), a grass strip where the style has one, its lane
## lines, storm drains. Held to the town's contract wherever the style differs,
## since the town's solids, footsteps and curb grinds are laid out from TownMap:
## always asphalt, always a curb and a sidewalk both sides (concrete where the
## style has none), no lamps (TownMap.lamp_spots has the town's, with colliders),
## no power poles and no speed bumps (neither has a solid here).
static func _street(holder: Node3D, hood: String, from: Vector3, to: Vector3, batch: RefCounted) -> void:
	var look: Dictionary = _HoodStyles.style(hood).duplicate()
	var street: Dictionary = (look.get("street", {}) as Dictionary).duplicate()
	street["surface"] = "road"
	if str(street.get("curb", "none")) == "none":
		street["curb"] = "concrete"
	if str(street.get("sidewalk", "none")) == "none":
		street["sidewalk"] = "concrete"
	look["street"] = street
	_StreetBuilder.segment(holder, from, to, look, {
		"batch": batch, "width": TownMap.STREET_WIDTH, "lamps": false, "poles": false,
		"speed_bumps_from_x": INF, "hood": hood,
	})


## The town square: a plaza by the County Road junction with the welcome sign
## and the Founder's Rake.
static func _square(root: Node3D) -> void:
	var marks := TownMap.landmarks()
	var plaza := _piece(root, "Plaza", marks["plaza"])
	_LowPoly.paint(_LowPoly.box(plaza, Vector3(22.0, 0.12, 22.0), Vector3(0.0, 0.03, 0.0), CONCRETE.lightened(0.04)), "pavers")
	# Corner trees, none between the welcome sign and the road in from the west.
	for corner: Vector3 in [Vector3(-9.0, 0.0, -9.0), Vector3(9.0, 0.0, -9.0), Vector3(9.0, 0.0, 9.0)]:
		_Trees.spawn(plaza, corner, 7.5, "broadleaf", "orange", int(corner.x), false, corner.z)
	# The welcome sign: two posts and a board, read from the County Road.
	var sign_root := _piece(root, "WelcomeSign", marks["welcome_sign"])
	for side: float in [-1.0, 1.0]:
		_LowPoly.paint(_LowPoly.box(sign_root, Vector3(0.3, 2.4, 0.3), Vector3(side * 3.4, 1.2, 0.0), WOOD), "planks")
	_LowPoly.paint(_LowPoly.box(sign_root, Vector3(7.4, 2.2, 0.2), Vector3(0.0, 2.5, 0.0), SIGN_GREEN), "planks")
	_LowPoly.paint(_LowPoly.box(sign_root, Vector3(7.7, 0.16, 0.3), Vector3(0.0, 3.66, 0.0), WOOD), "planks")
	_sign_text(sign_root, _Strings.TOWN_SIGNS["welcome_title"], Vector3(0.0, 3.0, 0.12), 150, Color(0.98, 0.94, 0.8))
	_sign_text(sign_root, _Strings.TOWN_SIGNS["welcome_sign"], Vector3(0.0, 2.25, 0.12), 80, Color(0.98, 0.94, 0.8))
	_sign_text(sign_root, _Strings.TOWN_SIGNS["welcome_fine_print"], Vector3(0.0, 1.62, 0.12), 26, Color(0.9, 0.9, 0.82))
	# The Founder's Rake: a stone plinth, and a rake six meters tall.
	var statue := _piece(root, "FoundersRake", marks["founders_rake"])
	_LowPoly.paint(_LowPoly.box(statue, Vector3(2.4, 1.2, 2.4), Vector3(0.0, 0.6, 0.0), STONE), "stone")
	var bronze := Color(0.55, 0.42, 0.25)
	_LowPoly.paint(_LowPoly.cylinder(statue, 0.12, 5.2, Vector3(0.0, 3.8, 0.0), bronze, false, 8), "metal")
	_LowPoly.paint(_LowPoly.box(statue, Vector3(1.9, 0.18, 0.2), Vector3(0.0, 6.45, 0.0), bronze), "metal")
	for tine: int in 9:
		_LowPoly.paint(_LowPoly.box(statue, Vector3(0.06, 0.5, 0.08), Vector3(-0.85 + float(tine) * 0.2125, 6.75, 0.0), bronze), "metal")
	_sign_text(statue, _Strings.TOWN_SIGNS["founders_rake"], Vector3(0.0, 0.62, 1.22), 30, Color(0.2, 0.18, 0.14))


## A green street sign at each corner of Main Street, and the County Road's.
static func _street_signs(root: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "StreetSigns"
	root.add_child(holder)
	for hood_index: int in _Hoods.HOODS.size():
		var z := TownMap.STREET_Z[hood_index]
		var label := str(_Hoods.HOODS[hood_index]["name"]).to_upper()
		_street_sign(holder, Vector3(TownMap.MAIN_X + TownMap.MAIN_WIDTH * 0.5 + 1.6, 0.0, z - TownMap.STREET_WIDTH * 0.5 - 1.6), label, _Strings.TOWN_SIGNS["main_street"])
	_street_sign(holder, Vector3(TownMap.MAIN_X - TownMap.MAIN_WIDTH * 0.5 - 1.6, 0.0, TownMap.SQUARE.z + TownMap.STREET_WIDTH * 0.5 + 1.6), _Strings.TOWN_SIGNS["county_road"], _Strings.TOWN_SIGNS["main_street"])
	_street_sign(holder, Vector3(TownMap.DEPOT_X + TownMap.STREET_WIDTH * 0.5 + 1.6, 0.0, TownMap.DEPOT_JUNCTION.z + TownMap.STREET_WIDTH * 0.5 + 1.6), _Strings.TOWN_SIGNS["county_road"], _Strings.TOWN_SIGNS["depot_road"])


## A post with two blades: one along x (read from Main Street) and one along z.
static func _street_sign(root: Node3D, at: Vector3, along_x: String, along_z: String) -> void:
	var post := Node3D.new()
	post.name = "StreetSign"
	root.add_child(post)
	post.position = at
	_LowPoly.paint(_LowPoly.cylinder(post, 0.05, 3.0, Vector3(0.0, 1.5, 0.0), Color(0.3, 0.32, 0.34), false, 6), "metal")
	_LowPoly.box(post, Vector3(0.05, 0.3, 1.6), Vector3(0.0, 2.85, 0.0), SIGN_GREEN)
	_LowPoly.box(post, Vector3(1.6, 0.3, 0.05), Vector3(0.0, 2.5, 0.0), SIGN_GREEN)
	var first := _sign_text(post, along_x, Vector3(0.04, 2.85, 0.0), 22, Color.WHITE, PI * 0.5)
	first.double_sided = true
	var second := _sign_text(post, along_z, Vector3(0.0, 2.5, 0.04), 22, Color.WHITE)
	second.double_sided = true
	_fade(post, Constants.TOWN_SMALL_VISIBLE_METERS)


## Oak Hollow's arch over its street mouth, and VIOLATION flags on its lawns.
static func _hoa_arch(root: Node3D) -> void:
	var arch := _piece(root, "HoaArch", TownMap.landmarks()["hoa_arch"])
	var span := TownMap.arch_half_span()
	var white := Color(0.93, 0.92, 0.88)
	for side: float in [-1.0, 1.0]:
		_LowPoly.paint(_LowPoly.box(arch, Vector3(1.0, 6.0, 1.0), Vector3(side * span, 3.0, 0.0), white), "stucco")
		_LowPoly.paint(_LowPoly.box(arch, Vector3(1.3, 0.4, 1.3), Vector3(side * span, 6.2, 0.0), white.darkened(0.1)), "stucco")
	_LowPoly.paint(_LowPoly.box(arch, Vector3(span * 2.0 + 1.0, 1.2, 0.5), Vector3(0.0, 6.6, 0.0), white), "stucco")
	# Read by drivers turning in off Main Street, on the arch's west (-Z) face.
	_sign_text(arch, _Strings.TOWN_SIGNS["hoa_arch"], Vector3(0.0, 6.6, -0.27), 64, Color(0.2, 0.3, 0.24), PI)
	var hood := _Hoods.index_of("oak_hollow")
	var flags := Node3D.new()
	flags.name = "ViolationFlags"
	root.add_child(flags)
	for house_id: int in range(TownMap.first_house_of(hood), TownMap.first_house_of(hood) + int(_Hoods.HOODS[hood]["houses"])):
		for spot: Vector3 in [Vector3(-12.0, 0.0, 17.0), Vector3(13.0, 0.0, 15.0)]:
			var flag := Node3D.new()
			flag.name = "Flag"
			flags.add_child(flag)
			flag.position = TownMap.yard_transform(house_id) * spot
			_LowPoly.box(flag, Vector3(0.03, 0.9, 0.03), Vector3(0.0, 0.45, 0.0), Color(0.85, 0.85, 0.85))
			_LowPoly.box(flag, Vector3(0.36, 0.22, 0.02), Vector3(0.18, 0.78, 0.0), Color(0.86, 0.16, 0.12))
			var text := _sign_text(flag, _Strings.TOWN_SIGNS["hoa_flag"], Vector3(0.18, 0.78, 0.02), 14, Color.WHITE)
			text.double_sided = true
			_fade(flag, Constants.TOWN_SMALL_VISIBLE_METERS)


## Mansion Hill's gate: stone pillars with lamps, the iron gates swung open.
static func _mansion_gate(root: Node3D) -> void:
	var gate := _piece(root, "MansionGate", TownMap.landmarks()["mansion_gate"])
	var span := TownMap.arch_half_span()
	var iron := Color(0.15, 0.15, 0.17)
	for side: float in [-1.0, 1.0]:
		_LowPoly.paint(_LowPoly.box(gate, Vector3(1.4, 4.2, 1.4), Vector3(side * span, 2.1, 0.0), STONE), "stone")
		_LowPoly.glow(gate, Vector3(0.5, 0.6, 0.5), Vector3(side * span, 4.6, 0.0), Color(1.0, 0.9, 0.7), 0.8)
		# Each gate leaf swung back along the sidewalk.
		var leaf := Node3D.new()
		gate.add_child(leaf)
		leaf.position = Vector3(side * (span - 0.7), 0.0, 0.0)
		leaf.rotation.y = side * PI * 0.5
		for bar: int in 9:
			_LowPoly.box(leaf, Vector3(0.05, 2.6, 0.05), Vector3(-side * (0.3 + float(bar) * 0.4), 1.3, 0.0), iron)
		_LowPoly.box(leaf, Vector3(3.6, 0.08, 0.06), Vector3(-side * 1.9, 2.5, 0.0), iron)
	_sign_text(gate, _Strings.TOWN_SIGNS["mansion_gate"], Vector3(-span, 3.2, -0.72), 34, Color(0.95, 0.88, 0.6), PI)


## Lake Gutterford behind Lakeside's yards, with a dock behind every second one.
static func _lake(root: Node3D) -> void:
	var lake := TownMap.LAKE
	var holder := Node3D.new()
	holder.name = "Lake"
	root.add_child(holder)
	var water := _LowPoly.box(holder, Vector3(lake.size.x, 0.1, lake.size.y), Vector3(lake.get_center().x, 0.0, lake.get_center().y), WATER)
	water.name = "Water"
	_LowPoly.paint(_LowPoly.box(holder, Vector3(lake.size.x + 0.6, 0.5, 0.4), Vector3(lake.get_center().x, 0.25, lake.end.y), STONE), "stone")
	# The water lapping at that edge and the loon out on it (art:9, audio/ambience.gd).
	preload("res://levels/town/set_pieces.gd").shore(holder, Vector3(lake.position.x, 0.05, lake.end.y - 0.3), Vector3(lake.end.x, 0.05, lake.end.y - 0.3), Vector3.FORWARD)
	for dock: Array in TownMap.docks():
		var from: Vector3 = dock[0]
		var to: Vector3 = dock[1]
		var length := from.distance_to(to)
		var middle := (from + to) * 0.5
		_LowPoly.paint(_LowPoly.box(holder, Vector3(2.2, 0.14, length), middle + Vector3(0.0, 0.42, 0.0), WOOD), "planks")
		for post: int in 4:
			var at := from.lerp(to, float(post) / 3.0)
			for side: float in [-1.0, 1.0]:
				_LowPoly.paint(_LowPoly.cylinder(holder, 0.1, 1.0, at + Vector3(side * 1.0, 0.2, 0.0), WOOD.darkened(0.2), false, 6), "bark")
	var sign_root := Node3D.new()
	holder.add_child(sign_root)
	sign_root.position = Vector3(lake.position.x + 6.0, 0.0, lake.end.y + 2.0)
	_LowPoly.paint(_LowPoly.box(sign_root, Vector3(0.15, 1.6, 0.15), Vector3(0.0, 0.8, 0.0), WOOD), "planks")
	_LowPoly.paint(_LowPoly.box(sign_root, Vector3(2.4, 0.9, 0.1), Vector3(0.0, 1.7, 0.0), Color(0.9, 0.88, 0.8)), "planks")
	_sign_text(sign_root, _Strings.TOWN_SIGNS["lake_sign"], Vector3(0.0, 1.7, 0.06), 20, Color(0.15, 0.2, 0.3))


## The NICE BOYS Regional Field Office (Satellite Annex B): a lavender box of a
## building with a banner, a form by the door, and a flag with nothing on it.
static func _field_office(root: Node3D) -> void:
	var office := _piece(root, "FieldOffice", TownMap.landmarks()["field_office"])
	# Matches the solid in TownMap.set_piece_solids: 14 wide, 5.2 tall, 10 deep.
	_LowPoly.paint(_LowPoly.box(office, Vector3(14.0, 5.2, 10.0), Vector3(0.0, 2.6, 0.0), LAVENDER), "stucco")
	_LowPoly.paint(_LowPoly.box(office, Vector3(14.4, 0.4, 10.4), Vector3(0.0, 5.4, 0.0), LAVENDER.darkened(0.25)), "concrete")
	_LowPoly.box(office, Vector3(1.4, 2.4, 0.08), Vector3(0.0, 1.2, 5.02), Color(0.3, 0.28, 0.4))
	for x: float in [-4.5, -2.4, 2.4, 4.5]:
		_LowPoly.window(office, 1.4, 1.1, Vector3(x, 2.2, 5.02), Color(0.92, 0.92, 0.95))
	_LowPoly.paint(_LowPoly.box(office, Vector3(9.0, 1.0, 0.06), Vector3(0.0, 4.3, 5.06), Color(0.98, 0.97, 0.94)), "fabric")
	_sign_text(office, _Strings.TOWN_SIGNS["field_office_banner"], Vector3(0.0, 4.3, 5.1), 70, Color(0.36, 0.24, 0.55))
	_LowPoly.box(office, Vector3(3.4, 1.4, 0.06), Vector3(-4.0, 3.4, 5.04), Color(0.95, 0.95, 0.97))
	_sign_text(office, _Strings.TOWN_SIGNS["field_office_sign"], Vector3(-4.0, 3.4, 5.08), 26, Color(0.36, 0.24, 0.55))
	_LowPoly.box(office, Vector3(0.9, 0.6, 0.04), Vector3(1.3, 1.5, 5.04), Color(0.98, 0.98, 0.96))
	_sign_text(office, _Strings.TOWN_SIGNS["field_office_form"], Vector3(1.3, 1.5, 5.07), 10, Color(0.2, 0.2, 0.24))
	_LowPoly.paint(_LowPoly.box(office, Vector3(6.0, 0.12, 4.0), Vector3(0.0, 0.03, 7.2), CONCRETE), "concrete")
	_LowPoly.paint(_LowPoly.cylinder(office, 0.06, 7.0, Vector3(5.5, 3.5, 7.5), Color(0.8, 0.8, 0.82), false, 6), "metal")
	_LowPoly.paint(_LowPoly.box(office, Vector3(1.6, 1.0, 0.03), Vector3(6.3, 6.4, 7.5), LAVENDER), "fabric")


static func _lamps(root: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "Lamps"
	root.add_child(holder)
	for lamp: Array in TownMap.lamp_spots():
		_Neighborhood.lamp(holder, lamp[0], float(lamp[1]))
	_fade(holder, Constants.TOWN_LAMP_VISIBLE_METERS)
	# Posters on some of them (cast:7, levels/dressing/street_life.gd); their words
	# keep their own fade.
	preload("res://levels/dressing/street_life.gd").dress_town_lamps(root, TownMap.lamp_spots(), SEED, TownMap.SQUARE)


## A mailbox at every yard and every house across the street, and a wheelie
## bin out at the curb in front of every second yard.
static func _curbside(root: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "Curbside"
	root.add_child(holder)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var places: Array = []
	for house_id: int in TownMap.house_count():
		places.append([TownMap.yard_transform(house_id), house_id])
	for slot: Dictionary in TownMap.dressing_slots():
		places.append([slot["xform"], -1])
	for index: int in places.size():
		var xform: Transform3D = places[index][0]
		var house_id: int = places[index][1]
		var mailbox := Node3D.new()
		mailbox.name = "Mailbox%d" % index
		holder.add_child(mailbox)
		mailbox.transform = xform * Transform3D(Basis.IDENTITY, MAILBOX_AT)
		mailbox.add_to_group("town_knockables")
		mailbox.set_meta("kind", "mailbox")
		mailbox.set_meta("house_id", house_id)
		var color := Color(0.2, 0.2, 0.22) if rng.randf() < 0.5 else Color(0.6, 0.15, 0.12)
		_LowPoly.paint(_LowPoly.box(mailbox, Vector3(0.12, 1.1, 0.12), Vector3(0.0, 0.55, 0.0), Color(0.45, 0.33, 0.22)), "planks")
		_LowPoly.paint(_LowPoly.box(mailbox, Vector3(0.42, 0.34, 0.66), Vector3(0.0, 1.25, 0.0), color), "metal")
		_LowPoly.box(mailbox, Vector3(0.04, 0.22, 0.1), Vector3(0.23, 1.38, -0.12), Color(0.85, 0.2, 0.15))
		_fade(mailbox, Constants.TOWN_SMALL_VISIBLE_METERS)
		if index % 2 != 0:
			continue
		var bin := Node3D.new()
		bin.name = "Bin%d" % index
		holder.add_child(bin)
		bin.transform = xform * Transform3D(Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)), BIN_AT)
		bin.add_to_group("town_knockables")
		bin.set_meta("kind", "trash_can")
		bin.set_meta("house_id", house_id)
		var body := Color(0.2, 0.38, 0.24) if rng.randf() < 0.6 else Color(0.25, 0.27, 0.3)
		_LowPoly.paint(_LowPoly.box(bin, Vector3(0.6, 1.0, 0.7), Vector3(0.0, 0.52, 0.0), body), "metal")
		_LowPoly.paint(_LowPoly.box(bin, Vector3(0.66, 0.08, 0.76), Vector3(0.0, 1.06, 0.0), body.darkened(0.15)), "metal")
		_fade(bin, Constants.TOWN_SMALL_VISIBLE_METERS)


static func _cars(root: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "ParkedCars"
	root.add_child(holder)
	for car: Array in TownMap.car_spots():
		var model := _YardModels.node("car", CAR_COLORS[int(car[2]) % CAR_COLORS.size()], Vector3.ONE, {"roughness": 0.5, "specular": 0.3})
		holder.add_child(model)
		model.position = car[0]
		model.rotation.y = float(car[1])


static func _country_trees(root: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "CountryTrees"
	root.add_child(holder)
	var trees := TownMap.country_trees()
	# A few trees a BuildQueue step.
	for first: int in range(0, trees.size(), 3):
		_BuildQueue.later(holder, func() -> void:
			for index: int in range(first, mini(first + 3, trees.size())):
				var tree: Array = trees[index]
				_Trees.spawn(holder, tree[0], float(tree[1]), str(tree[2]), str(tree[3]), index % 4, false, float(index) * 1.7), "town country trees")


## Homie Depot's town-only pieces, placed by Constants.STORE_LAYOUT in the
## store's space: Marty's pallet ramp (its solid is TownColliders') and the sign
## at the lot's entrance.
static func _store_extras(root: Node3D, store: Node3D) -> void:
	var store_xform := store.global_transform if store != null and store.is_inside_tree() else Transform3D.IDENTITY
	var holder := Node3D.new()
	holder.name = "StoreExtras"
	root.add_child(holder)
	var ramp_entry: Dictionary = Constants.STORE_LAYOUT["marty_ramp"]
	var ramp := Node3D.new()
	ramp.name = "MartysRamp"
	holder.add_child(ramp)
	ramp.transform = store_xform * Transform3D(Basis(Vector3.UP, float(ramp_entry["yaw"])), ramp_entry["at"])
	var size: Vector3 = _Colliders.RAMP_SIZE
	var solids: Array = _Colliders.ramp_solids()
	var slab: Array = solids[0]
	var top := _LowPoly.box(ramp, slab[1], slab[0], Color(0.78, 0.66, 0.46))
	top.basis = slab[2]
	_LowPoly.paint(top, "planks")
	# Pallets stacked under the high end, the low end resting on the asphalt.
	for layer: int in 3:
		var height := 0.14
		var length := size.x * (0.75 - float(layer) * 0.2)
		_LowPoly.paint(_LowPoly.box(ramp, Vector3(length, height, size.z - 0.1), Vector3(size.x * 0.5 - length * 0.5, height * 0.5 + float(layer) * height * 1.6, 0.0), PALLET), "planks")
	var sign_root := Node3D.new()
	ramp.add_child(sign_root)
	sign_root.position = Vector3(-size.x * 0.5 - 0.6, 0.0, size.z * 0.5 + 0.3)
	sign_root.rotation.y = -PI * 0.5
	_LowPoly.paint(_LowPoly.box(sign_root, Vector3(0.08, 1.0, 0.08), Vector3(0.0, 0.5, 0.0), WOOD), "planks")
	_LowPoly.box(sign_root, Vector3(1.0, 0.5, 0.04), Vector3(0.0, 1.1, 0.0), Color(0.95, 0.92, 0.85))
	_sign_text(sign_root, _Strings.TOWN_SIGNS["ramp_sign"], Vector3(0.0, 1.1, 0.03), 9, Color(0.2, 0.18, 0.15))
	var sign_entry: Dictionary = Constants.STORE_LAYOUT["depot_safe_sign"]
	var safe := Node3D.new()
	safe.name = "NoNicenessSign"
	holder.add_child(safe)
	safe.transform = store_xform * Transform3D(Basis(Vector3.UP, float(sign_entry["yaw"])), sign_entry["at"])
	for side: float in [-1.0, 1.0]:
		_LowPoly.paint(_LowPoly.cylinder(safe, 0.05, 2.2, Vector3(side * 0.6, 1.1, 0.0), Color(0.3, 0.32, 0.34), false, 6), "metal")
	_LowPoly.box(safe, Vector3(1.5, 0.8, 0.05), Vector3(0.0, 1.9, 0.0), Color(0.95, 0.5, 0.15))
	_sign_text(safe, _Strings.TOWN_SIGNS["depot_safe_sign"], Vector3(0.0, 1.9, 0.04), 18, Color.WHITE)


## People walking each neighborhood street's sidewalks and Main Street's. One
## holder per street, so every walker's node path is the same on every peer.
static func _walkers(root: Node3D) -> void:
	for hood_index: int in _Hoods.HOODS.size():
		var z := TownMap.STREET_Z[hood_index]
		var from_x := TownMap.MAIN_X + TownMap.MAIN_WIDTH * 0.5 + TownMap.SIDEWALK + 2.0
		var to_x := TownMap.street_end_x(hood_index) - 2.0
		var offset := TownMap.STREET_WIDTH * 0.5 + 1.3
		var street := Node3D.new()
		street.name = "Walkers_%s" % str(_Hoods.HOODS[hood_index]["id"])
		root.add_child(street)
		_Pedestrians.populate(street, [
			[Vector3(from_x, 0.1, z - offset), Vector3(to_x, 0.1, z - offset)],
			[Vector3(from_x, 0.1, z + offset), Vector3(to_x, 0.1, z + offset)],
		], Constants.TOWN_PEDESTRIANS_PER_STREET, SEED + hood_index)
	var main := Node3D.new()
	main.name = "Walkers_main_street"
	root.add_child(main)
	var side := TownMap.MAIN_WIDTH * 0.5 + 1.3
	_Pedestrians.populate(main, [
		[Vector3(TownMap.MAIN_X - side, 0.1, -380.0), Vector3(TownMap.MAIN_X - side, 0.1, 380.0)],
		[Vector3(TownMap.MAIN_X + side, 0.1, -380.0), Vector3(TownMap.MAIN_X + side, 0.1, 380.0)],
	], Constants.TOWN_PEDESTRIANS_PER_STREET + 1, SEED + 77)


# ---------------------------------------------------------------- helpers

## A holder at a landmark's place, turned the way it faces.
static func _piece(root: Node3D, piece_name: String, mark: Dictionary) -> Node3D:
	var piece := Node3D.new()
	piece.name = piece_name
	root.add_child(piece)
	piece.position = mark["at"]
	piece.rotation.y = float(mark["yaw"])
	return piece


static func _sign_text(parent: Node3D, text: String, at: Vector3, font_size: int, color: Color, yaw: float = 0.0) -> Label3D:
	var label := _LowPoly.text_sign(parent, text, at, font_size, color, yaw)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


## Every mesh and label under node stops drawing past meters.
static func _fade(node: Node, meters: float) -> void:
	var geometry := node as GeometryInstance3D
	if geometry != null:
		geometry.visibility_range_end = meters
		geometry.visibility_range_end_margin = meters * 0.05
	for child: Node in node.get_children():
		_fade(child, meters)
