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
##   gutters      [[from, to, outward normal], ...] the main roof's front and back eaves
##   solids       [[center, size], ...] boxes a lot turns into one HouseBody
##   roof_solids  [[center, size], ...] lower roofs (estate wings) as boxes
##   porch_depth  how far porch and steps reach past the facade (m)
##   door         the front door's center, on the facade
##   spigot       [pos, normal] on a real side wall, for a hose
##   eaves        [[from, to], ...] eave lines, for string lights
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
	for key: String in ["archetype", "windows", "roof", "roof_edge_y", "gutters", "solids", "roof_solids", "porch_depth", "door", "spigot", "eaves", "footprint"]:
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
		if (spec["gutters"] as Array).size() < 2:
			problems.append("%s: gutters on %d eaves" % [label, (spec["gutters"] as Array).size()])
		if (spec["windows"] as Array).is_empty():
			problems.append("%s: no windows to wash" % label)
		if float(roof.get("rise", 0.0)) <= 0.0 or float(roof.get("half_run", 0.0)) <= 0.0:
			problems.append("%s: flat main roof" % label)
	var spigot: Array = spec["spigot"]
	if spigot.size() != 2:
		problems.append("%s: no spigot" % label)
	if int(spec["triangles"]) > Constants.ART_HOUSE_MAX_TRIANGLES:
		problems.append("%s: %d triangles (budget %d)" % [label, int(spec["triangles"]), Constants.ART_HOUSE_MAX_TRIANGLES])
	return problems
