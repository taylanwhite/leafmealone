extends RefCounted

## Authority: local, cosmetic. Builds one house of any archetype
## (levels/town/house_archetypes.gd) with HouseKit (props/house_kit.gd), facing
## +Z with its origin at the ground center of its footprint, and describes it in
## HouseSpec metas so a lot can hang gameplay on it (roof, gutters, windows,
## spigot) without knowing the archetype. Pure function of req: the same req
## builds the same house on every peer. Nothing here collides; callers turn
## "solids" into colliders.
##
## req (every key optional):
##   archetype  house_archetypes.ALL id (default "classic")
##   width, depth  the footprint the main body fills, in meters
##   stories    1 or 2 (archetypes that are always one or two stories ignore it)
##   wall, wall_surface, roof, roof_surface, trim, door, accent  colors and surfaces
##   garage     bool, for archetypes where it is optional
##   seed       int: small per-house choices (which side the chimney is on, ...)
##   detail     "full" or "far" (a box, a prism, and two windows per house)
##
## HouseSpec metas on the returned root "House" (house-root space):
##   archetype, stories, width, depth
##   windows      [[pos, normal, Vector2 size], ...] washable windows, on the wall surface
##   roof         {kind ("gable_x" for every job archetype), center (x, eave y, z of
##                the ridge's middle), width (the roof's length along x), half_run
##                (ridge to eave, horizontally), rise, top (eave y)}
##   roof_edge_y  the main roof's eave height
##   gutters      [[from, to, outward normal], ...] the main roof's front and back
##                eaves, split around any solid or roof blocker they would run
##                through (a cottage's bay, a garage's cross-gable, a door hood),
##                so one eave may be several pieces
##   solids       [[center, size], ...] boxes a lot turns into one HouseBody
##   roof_solids  [[center, size], ...] lower roofs (estate wings) as boxes
##   roof_blockers [[center, size], ...] what stands on the climbable roof or
##                across its eaves (dormers, cross-gables, door hoods, pediments,
##                chimneys) as boxes: no roof spots inside them, and colliders
##   porch_depth  how far porch and steps reach past the facade (m)
##   door         the front door's center, on the facade
##   spigot       [pos, normal] on a real side wall, for a hose
##   eaves        [[from, to], ...] eave lines, for string lights (split like gutters)
##   footprint    Rect2 (x, z) of everything built
##   triangles, draw_calls
## and "house_spec", all of the above as one Dictionary.
##
## FOOTPRINT CONTRACT (checked by check() and tools/mesh_check.gd): everything
## stays within x in +-(width/2 + Constants.ART_HOUSE_SIDE_REACH) and z in
## [-depth/2 - ART_HOUSE_BACK_REACH, depth/2 + ART_HOUSE_FRONT_REACH], and the
## main climbable roof of every job archetype is a gable along x, so the lot
## generator's roof, gutter, and window logic stays valid.

const _HouseKit = preload("res://props/house_kit.gd")
const _Archetypes = preload("res://levels/town/house_archetypes.gd")
const _HoodStyles = preload("res://levels/town/hood_styles.gd")
const _PorchLights = preload("res://levels/porch_lights.gd")
## The yard generator, loaded when first needed (it preloads half the game).
const LOT_GENERATOR := "res://levels/lots/lot_generator.gd"

## spec_for's results, by req: a block plans each parcel more than once.
static var _specs: Dictionary = {}
const _SPEC_CACHE_SIZE: int = 256


## The req for the house a yard with this seed and size gets in hood
## (gap-specs/critic.md C25). The job yard (levels/lots/lot_generator.gd) and the
## parcel builder (levels/town/lot_builder.gd) both call it, so the house you
## work at is the house you drive past. spec is the yard's numbers from
## LotGenerator.house_spec (width, depth, stories, center_x, center_z, wall, roof,
## trim, garage), drawn from the yard's own rng; left empty, they come from
## LotGenerator.spec_for_seed(house_seed, size). Every look choice (archetype,
## door, accent) comes from a separate rng seeded hash([house_seed, "art"]), so
## the yard's rng draws are never touched; the yard's wall, roof and trim draws
## pick the hood's palette entries. neighbor: may also be a neighbors-only
## archetype (an A-frame, a glass cube). The req carries "at" (the yard-space
## ground center from center_x and center_z) and "hood" besides HouseBuilder's keys.
static func request_for(hood: String, house_seed: int, size: int, spec: Dictionary = {}, neighbor: bool = false) -> Dictionary:
	var numbers := spec
	if numbers.is_empty():
		numbers = load(LOT_GENERATOR).call("spec_for_seed", house_seed, clampi(size, 0, 2))
	var look := _HoodStyles.style(hood)
	var art := RandomNumberGenerator.new()
	art.seed = hash([house_seed, "art"])
	var stories := clampi(int(numbers.get("stories", 1)), 1, 2)
	var weights := _HoodStyles.neighbor_archetype_weights(str(look["id"]), stories) if neighbor else _HoodStyles.archetype_weights(str(look["id"]), stories)
	var archetype := str(_HoodStyles.pick(art, weights))
	var walls: Array = look["walls"]
	var roofs: Array = look["roofs"]
	var trims: Array = look["trims"]
	var wall: Array = walls[_palette_index(numbers.get("wall", Color.WHITE), walls.size())]
	var roof: Array = roofs[_palette_index(numbers.get("roof", Color.WHITE), roofs.size())]
	var trim: Color = trims[_palette_index(numbers.get("trim", Color.WHITE), trims.size())]
	var doors: Array = look["doors"]
	var accents: Array = look["accents"]
	var door: Color = doors[art.randi() % doors.size()]
	var accent: Color = accents[art.randi() % accents.size()]
	return {
		"archetype": archetype, "width": float(numbers.get("width", 10.0)), "depth": float(numbers.get("depth", 8.0)),
		"stories": stories, "wall": wall[0], "wall_surface": wall[1], "roof": roof[0], "roof_surface": roof[1],
		"trim": trim, "door": door, "accent": accent, "garage": bool(numbers.get("garage", false)),
		"seed": house_seed, "detail": "full", "hood": str(look["id"]),
		"at": Vector3(float(numbers.get("center_x", 0.0)), 0.0, float(numbers.get("center_z", 0.0))),
	}


## The HouseSpec build() would return for req, without making any node (for
## planning a parcel, colliders, and skylines). Cached.
static func spec_for(req: Dictionary) -> Dictionary:
	var r := normalized(req)
	r.erase("at")
	r.erase("hood")
	r["detail"] = "full"
	var key := str(r)
	if _specs.has(key):
		return (_specs[key] as Dictionary).duplicate(true)
	var kit: RefCounted = _HouseKit.new()
	var spec := _Archetypes.build(kit, r)
	var bounds: AABB = kit.call("bounds")
	spec["footprint"] = Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z)
	spec["height"] = bounds.end.y
	spec["triangles"] = int(kit.call("triangle_count"))
	if _specs.size() >= _SPEC_CACHE_SIZE:
		_specs.clear()
	_specs[key] = spec
	return spec.duplicate(true)


## A yard color's place in a palette of count entries: the same color always
## lands on the same entry, on every peer.
static func _palette_index(color: Color, count: int) -> int:
	return posmod(hash(color.to_html(false)), maxi(count, 1))


static func build(parent: Node3D, at: Vector3, req: Dictionary) -> Node3D:
	var r := normalized(req)
	var root := Node3D.new()
	root.name = "House"
	parent.add_child(root)
	root.position = at
	var kit: RefCounted = _HouseKit.new()
	var spec := _Archetypes.build(kit, r)
	var full_bounds: AABB = kit.call("bounds")
	if str(r["detail"]) == "far":
		kit = _HouseKit.new()
		_Archetypes.far(kit, r, spec)
	var look: Node3D = kit.call("commit", root, "Look")
	spec["footprint"] = Rect2(full_bounds.position.x, full_bounds.position.z, full_bounds.size.x, full_bounds.size.z)
	spec["height"] = full_bounds.end.y
	spec["triangles"] = int(look.get_meta("triangles", 0))
	spec["draw_calls"] = int(look.get_meta("draw_calls", 0))
	for key: String in spec:
		root.set_meta(key, spec[key])
	root.set_meta("house_spec", spec)
	# Its porch light, lit at dusk (levels/porch_lights.gd), and the porch the
	# neighborhood's own sounds come from (audio/ambience.gd: a wind chime, a
	# screen door, someone whistling).
	root.add_to_group("porches")
	if str(r["detail"]) == "full" and spec.has("door"):
		var door_size: Vector2 = spec.get("door_size", Vector2(1.1, 2.2))
		_PorchLights.add(root, (spec["door"] as Vector3) + Vector3(0.0, door_size.y * 0.5, 0.0), int(r["seed"]))
	return root


## req with every key filled in.
static func normalized(req: Dictionary) -> Dictionary:
	var r := req.duplicate()
	r["archetype"] = str(r.get("archetype", "classic"))
	if not _Archetypes.ALL.has(r["archetype"]):
		push_warning("[HouseBuilder] no archetype %s, building classic" % r["archetype"])
		r["archetype"] = "classic"
	r["width"] = float(r.get("width", 10.0))
	r["depth"] = float(r.get("depth", 8.0))
	r["stories"] = clampi(int(r.get("stories", 1)), 1, 2)
	var wall: Color = r.get("wall", Color(0.86, 0.79, 0.62))
	r["wall"] = wall
	r["wall_surface"] = str(r.get("wall_surface", "siding"))
	r["roof"] = r.get("roof", Color(0.36, 0.25, 0.22))
	r["roof_surface"] = str(r.get("roof_surface", "shingles"))
	r["trim"] = r.get("trim", Color(0.95, 0.94, 0.9))
	# Today's door rule (levels/dressing/neighborhood.gd): red on darker walls, blue on pale.
	r["door"] = r.get("door", Color(0.5, 0.18, 0.15) if wall.r < 0.8 else Color(0.2, 0.32, 0.45))
	r["accent"] = r.get("accent", Color(0.58, 0.32, 0.26))
	r["garage"] = bool(r.get("garage", false))
	r["seed"] = int(r.get("seed", 0))
	r["detail"] = str(r.get("detail", "full"))
	return r


## The HouseSpec of a built house.
static func spec_of(house: Node3D) -> Dictionary:
	return house.get_meta("house_spec", {})


## What breaks the footprint contract, as readable lines (empty when it holds).
static func check(house: Node3D) -> PackedStringArray:
	var problems := PackedStringArray()
	var spec := spec_of(house)
	var label := "%s %.1fx%.1f %d-story" % [spec.get("archetype", "?"), float(spec.get("width", 0.0)), float(spec.get("depth", 0.0)), int(spec.get("stories", 0))]
	for key: String in ["archetype", "windows", "roof", "roof_edge_y", "gutters", "solids", "roof_solids", "roof_blockers", "porch_depth", "door", "spigot", "eaves", "footprint"]:
		if not spec.has(key):
			problems.append("%s: no %s" % [label, key])
	if not problems.is_empty():
		return problems
	var half_w := float(spec["width"]) * 0.5
	var half_d := float(spec["depth"]) * 0.5
	var allowed := Rect2(-half_w - Constants.ART_HOUSE_SIDE_REACH, -half_d - Constants.ART_HOUSE_BACK_REACH,
		half_w * 2.0 + Constants.ART_HOUSE_SIDE_REACH * 2.0, half_d * 2.0 + Constants.ART_HOUSE_BACK_REACH + Constants.ART_HOUSE_FRONT_REACH).grow(0.01)
	var footprint: Rect2 = spec["footprint"]
	if not allowed.encloses(footprint):
		problems.append("%s: footprint %s leaves %s" % [label, footprint, allowed])
	for solid: Array in spec["solids"]:
		var center: Vector3 = solid[0]
		var size: Vector3 = solid[1]
		var flat := Rect2(center.x - size.x * 0.5, center.z - size.z * 0.5, size.x, size.z)
		if not allowed.encloses(flat):
			problems.append("%s: solid %s leaves the footprint" % [label, flat])
	if float(spec["porch_depth"]) > Constants.ART_HOUSE_FRONT_REACH + 0.01:
		problems.append("%s: porch reaches %.2f m" % [label, float(spec["porch_depth"])])
	var roof: Dictionary = spec["roof"]
	if not _Archetypes.NEIGHBOR_ONLY.has(str(spec["archetype"])):
		if str(roof.get("kind", "")) != "gable_x":
			problems.append("%s: main roof is %s, not gable_x" % [label, roof.get("kind", "")])
		var facing := {"front": false, "back": false}
		for gutter: Array in spec["gutters"]:
			var outward: Vector3 = gutter[2]
			if outward.z > 0.5:
				facing["front"] = true
			elif outward.z < -0.5:
				facing["back"] = true
		if not (facing["front"] and facing["back"]):
			problems.append("%s: gutters not on both eaves (%d pieces)" % [label, (spec["gutters"] as Array).size()])
		if (spec["windows"] as Array).is_empty():
			problems.append("%s: no windows to wash" % label)
		if float(roof.get("rise", 0.0)) <= 0.0 or float(roof.get("half_run", 0.0)) <= 0.0:
			problems.append("%s: flat main roof" % label)
	# Gutters and eaves keep clear of every wall and roof blocker.
	var boxes: Array[AABB] = []
	for entry: Array in (spec["solids"] as Array) + (spec["roof_blockers"] as Array):
		var size: Vector3 = entry[1]
		boxes.append(AABB((entry[0] as Vector3) - size * 0.5, size).grow(-0.005))
	for key: String in ["gutters", "eaves"]:
		for line: Array in spec[key]:
			var a: Vector3 = line[0]
			var b: Vector3 = line[1]
			var steps := maxi(1, ceili(a.distance_to(b) / 0.2))
			for index: int in steps + 1:
				var point := a.lerp(b, float(index) / float(steps))
				var inside := boxes.filter(func(box: AABB) -> bool: return box.has_point(point))
				if not inside.is_empty():
					problems.append("%s: %s point %s inside %s" % [label, key.trim_suffix("s"), point, inside[0]])
					break
	var spigot: Array = spec["spigot"]
	if spigot.size() != 2:
		problems.append("%s: no spigot" % label)
	if int(spec["triangles"]) > Constants.ART_HOUSE_MAX_TRIANGLES:
		problems.append("%s: %d triangles (budget %d)" % [label, int(spec["triangles"]), Constants.ART_HOUSE_MAX_TRIANGLES])
	return problems
