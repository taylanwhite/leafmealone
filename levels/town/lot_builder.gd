extends RefCounted

## Authority: local, cosmetic (colliders() and skyline_boxes() are data). A house
## and its yard in a neighborhood's style (levels/town/hood_styles.gd), at any
## transform: the job's street block (levels/town/block_builder.gd) and the
## drivable town (driving's streamer, gap-specs/critic.md C24) both place
## parcels with it.
##
##   LotBuilder.build(parent, xform, {"hood": "maple_row", "seed": 1234, "size": 1})
##
## PARCEL FRAME: the origin is the center of the parcel's ground at y 0, the
## street edge is at +z = depth / 2 (+20 for the default 40 m: the job yard's
## own frame, so a town slot and its job yard line up), and the house faces +z.
## The parcel is frontage wide along x. Turn the parcel with xform, never the
## house inside it.
##
## req (every key optional):
##   hood       net/town/neighborhoods.gd id (unknown ids look like maple_row)
##   seed       the house's seed: for a town house, net/town/town.gd houses[i]
##              "seed", so the house matches its job yard (HouseBuilder.request_for)
##   size       0-2 (default: drawn from the hood's "sizes" by the seed)
##   season     0-3 (default Seasons.current())
##   frontage   meters along the street (default: the style's)
##   depth      meters from the street edge back (default Constants.ART_PARCEL_DEPTH)
##   detail     "full", "near" (no small props), or "far" (a far house, lawn, trees)
##   solid      true: simple colliders (StaticBody3D "Solids"), for a drivable town
##   batch      a props/prop_batch.gd to add repeated props to (its root must be
##              parent, or say where parent is with batch_xform); else its own
##   kit        a props/house_kit.gd to add the lawn, drive and walk to (kit_xform:
##              parent in the kit holder's space); else its own "Ground"
##   grass_root a Node3D whose props/grass.gd keep_clear rects get the house, drive,
##              walk and beds (grass_xform: parent in grass_root's space)
##   neighbor   false (default): a house someone can be hired at, drawn exactly as
##              its job yard's (HouseBuilder.request_for(..., false)), so a town
##              house and its job yard are the same house; true only for set
##              dressing nobody is ever hired at (the job block's neighbors), which
##              may be a neighbors-only archetype. Ignored (false) when job is true.
##   job        true: the job's own house (no string lights, no lawn clutter)
##   force      [kind, ...] props this parcel must have (the block's signature top-up)
##   uniform    {archetype, width, depth, stories}: overrides (Oak Hollow's sameness)
##   rebel      true: the hood's rebel door (Oak Hollow's one teal door)
##   vacant     true: no house, a FOR SALE sign (kept clear of the van's way out)
##   labels     how many of its violation flags show their words
##   house      the yard's house numbers (LotGenerator.house_spec), when known
##   name       the root's name (default "Parcel_<seed>")
##   house_node the House house_for(req) made ahead of time (taken in, not rebuilt)
##
## The returned root (script levels/town/parcel.gd, group "seasonal") has metas
## parcel_rect (Rect2, local), house_spec (Dictionary), house_at (Vector3),
## driveway ([from, to] local), mailbox (Vector3), door (Vector3, local),
## archetype (String), art_hash (int), and "decor" (what SeasonDressing reads).
## Every random choice comes from a RandomNumberGenerator seeded
## hash([seed, "parcel"]); nothing here calls the global randf.

const _HouseBuilder = preload("res://levels/town/house_builder.gd")
const _HoodStyles = preload("res://levels/town/hood_styles.gd")
const _Archetypes = preload("res://levels/town/house_archetypes.gd")
const _PropCatalog = preload("res://props/prop_catalog.gd")
const _PropBatch = preload("res://props/prop_batch.gd")
const _HouseKit = preload("res://props/house_kit.gd")
const _Trees = preload("res://props/trees.gd")
const _Grass = preload("res://props/grass.gd")
const _Hoods = preload("res://net/town/neighborhoods.gd")
const _Parcel = preload("res://levels/town/parcel.gd")

const CONCRETE := Color(0.7, 0.68, 0.64)
const PAVERS := Color(0.68, 0.46, 0.36)
const GRAVEL := Color(0.62, 0.58, 0.52)
const DIRT := Color(0.36, 0.25, 0.18)
const DRY := Color(0.62, 0.52, 0.32)
const MOBILE_HOMES: Array[String] = ["single_wide", "double_wide"]
## Front fences by the style's names (hood_styles.gd "fence_front").
const FENCE_RUNS: Dictionary = {
	"picket": "picket_fence_run", "weathered_picket": "weathered_picket_run", "chainlink": "chainlink_run",
	"split_rail": "split_rail_run", "vinyl": "vinyl_fence_run", "privacy": "privacy_fence_run", "iron": "iron_fence_run",
}
## Backyard features by the style's names (hood_styles.gd "backyard").
const BACKYARD: Dictionary = {
	"pool": "pool_inground", "trampoline": "trampoline", "swing_set": "swing_set", "garden_bed": "garden_bed_raised",
	"clothesline": "clothesline", "bbq_gas": "bbq_gas", "patio_set": "patio_set", "hot_tub": "hot_tub", "fire_pit": "fire_pit",
	"tennis_court": "tennis_court", "putting_green": "putting_green", "gazebo": "gazebo",
}
## Where a forced or styled prop goes: the porch, the backyard, else the front lawn.
const ON_PORCH: Array[String] = ["porch_swing", "rocking_chair"]
const IN_BACK: Array[String] = ["pool_inground", "trampoline", "swing_set", "garden_bed_raised", "clothesline", "bbq_gas", "bbq_kettle", "patio_set", "hot_tub", "fire_pit", "tennis_court", "putting_green", "gazebo", "playhouse", "compost_bin", "sandbox"]
const POOL_SIZE := Vector3(8.0, 0.0, 4.0)


## Builds the parcel req describes under parent at xform. Returns its root.
static func build(parent: Node3D, xform: Transform3D, req: Dictionary) -> Node3D:
	var p := plan(req)
	var r: Dictionary = p["req"]
	var look := _HoodStyles.style(str(r["hood"]))
	var root: Node3D = _Parcel.new()
	root.name = str(r.get("name", "Parcel_%d" % posmod(int(r["seed"]), 1000000)))
	root.transform = xform
	root.set("role", "parcel")
	root.set("hood", str(r["hood"]))
	root.set("seed_value", int(r["seed"]))
	root.set("season", int(r["season"]))
	root.set("decor", p["decor"])
	root.set("lights", not bool(r["job"]))
	var detail := str(r["detail"])
	root.set("detail", detail)
	# Not dressed yet: a season turn before dress() below only moves root.season.
	parent.add_child(root)
	# Repeated props into the shared batch (in its root's space) or our own.
	var batch: RefCounted = r.get("batch", null)
	var to_batch := Transform3D.IDENTITY
	if batch == null:
		batch = _PropBatch.new(root)
	else:
		to_batch = r.get("batch_xform", Transform3D.IDENTITY) * xform
	var kit: RefCounted = r.get("kit", null)
	var own_kit := kit == null
	var to_kit := Transform3D.IDENTITY
	if own_kit:
		kit = _HouseKit.new()
	else:
		to_kit = r.get("kit_xform", Transform3D.IDENTITY) * xform
	var house: Node3D = null
	if not bool(r["vacant"]):
		var house_req: Dictionary = (p["house_req"] as Dictionary).duplicate()
		house_req["detail"] = "far" if detail == "far" else "full"
		var given: Node3D = r.get("house_node", null)
		if given != null and is_instance_valid(given):
			# Built ahead by house_for (a streamer spreading one parcel over frames).
			if given.get_parent() != null:
				given.get_parent().remove_child(given)
			root.add_child(given)
			given.position = p["house_at"]
			house = given
		else:
			house = _HouseBuilder.build(root, p["house_at"], house_req)
		house.add_to_group("art_signature:house_%s" % str(house_req["archetype"]))
		if MOBILE_HOMES.has(str(house_req["archetype"])):
			house.add_to_group("art_signature:mobile_home")
	_ground(kit, to_kit, p, look)
	if own_kit:
		var ground: Node3D = kit.call("commit", root, "Ground")
		ground.add_to_group("street_surface")
	for entry: Dictionary in p["props"]:
		var size: Vector3 = entry.get("size", Vector3.ONE)
		if detail != "full" and size == Vector3.ONE and float(_PropCatalog.mesh(entry["kind"]).get_meta("height", 1.0)) < Constants.ART_SMALL_PROP_HEIGHT:
			continue
		if detail == "far" and not bool(entry.get("big", false)):
			continue
		if bool(entry.get("complex", false)):
			var opts: Dictionary = (entry.get("opts", {}) as Dictionary).duplicate()
			opts["size"] = size
			opts["season"] = int(r["season"])
			_PropCatalog.place(root, entry["kind"], entry["xform"], entry.get("color", Color.WHITE), opts)
		else:
			batch.call("add", entry["kind"], to_batch * (entry["xform"] as Transform3D), entry.get("color", Color.WHITE), size)
	for tree: Array in p["trees"]:
		_Trees.spawn(root, tree[0], float(tree[3]), str(tree[1]), str(tree[2]), int(tree[4]), false, float(tree[5]))
	if bool(r["solid"]):
		_solids(root, p)
	# The season decor, once (a far parcel gets none; parcel.gd knows).
	root.call("dress")
	var grass_root: Node3D = r.get("grass_root", null)
	if grass_root != null:
		var to_grass: Transform3D = r.get("grass_xform", Transform3D.IDENTITY) * xform
		for clear: Array in p["clear"]:
			_Grass.keep_clear_box(grass_root, to_grass * Transform3D(Basis.IDENTITY, clear[0]), clear[1])
	if r.get("batch", null) == null:
		batch.call("commit")
	root.set_meta("parcel_rect", p["rect"])
	root.set_meta("house_spec", p["house_spec"])
	root.set_meta("house_at", p["house_at"])
	root.set_meta("driveway", p["drive"])
	root.set_meta("mailbox", p["mailbox"])
	root.set_meta("door", p["door"])
	root.set_meta("archetype", str((p["house_req"] as Dictionary).get("archetype", "")) if not bool(r["vacant"]) else "")
	root.set_meta("art_hash", int(p["hash"]))
	root.set_meta("signature", p["signature"])
	return root


## The house build() would make for req, made now and not in any tree (null for a
## vacant parcel), for build()'s house_node: the drivable town's streamer builds
## the house in one frame and the rest of the parcel in the next (driving:E2).
static func house_for(req: Dictionary) -> Node3D:
	var p := plan(req)
	var r: Dictionary = p["req"]
	if bool(r["vacant"]):
		return null
	var house_req: Dictionary = (p["house_req"] as Dictionary).duplicate()
	house_req["detail"] = "far" if str(r["detail"]) == "far" else "full"
	var holder := Node3D.new()
	var house := _HouseBuilder.build(holder, p["house_at"], house_req)
	holder.remove_child(house)
	holder.free()
	return house


## The boxes a drivable town gives this parcel colliders, parcel space:
## [[center, size], ...]. The house's walls (HouseSpec solids), its roofs as
## boxes, and each tree's trunk.
static func colliders(req: Dictionary) -> Array:
	var p := plan(req)
	var out: Array = []
	if not bool((p["req"] as Dictionary)["vacant"]):
		var at: Vector3 = p["house_at"]
		var spec: Dictionary = p["house_spec"]
		for solid: Array in (spec.get("solids", []) as Array) + (spec.get("roof_solids", []) as Array):
			out.append([at + (solid[0] as Vector3), solid[1]])
		var roof: Dictionary = spec.get("roof", {})
		if roof.has("center"):
			var rise := float(roof.get("rise", 0.0))
			out.append([at + (roof["center"] as Vector3) + Vector3(0.0, rise * 0.5, 0.0), Vector3(float(roof.get("width", 1.0)), rise, float(roof.get("half_run", 0.5)) * 2.0)])
	for tree: Array in p["trees"]:
		out.append([(tree[0] as Vector3) + Vector3(0.0, 1.5, 0.0), Vector3(0.5, 3.0, 0.5)])
	return out


## Far boxes for a merged skyline, parcel space: [[center, size, color], ...]:
## the house's walls in its wall color and its main roof in its roof color.
static func skyline_boxes(req: Dictionary) -> Array:
	var p := plan(req)
	if bool((p["req"] as Dictionary)["vacant"]):
		return []
	var at: Vector3 = p["house_at"]
	var spec: Dictionary = p["house_spec"]
	var house_req: Dictionary = p["house_req"]
	var out: Array = []
	for solid: Array in spec.get("solids", []):
		out.append([at + (solid[0] as Vector3), solid[1], house_req["wall"]])
	var roof: Dictionary = spec.get("roof", {})
	if roof.has("center"):
		var rise := float(roof.get("rise", 0.0))
		out.append([at + (roof["center"] as Vector3) + Vector3(0.0, rise * 0.5, 0.0), Vector3(float(roof.get("width", 1.0)), rise, float(roof.get("half_run", 0.5)) * 2.0), house_req["roof"]])
	return out


## req with every key filled in (the batch, kit and grass root pass through).
static func normalized(req: Dictionary) -> Dictionary:
	var r := req.duplicate()
	var look := _HoodStyles.style(str(r.get("hood", _HoodStyles.FALLBACK)))
	r["hood"] = str(look["id"])
	r["seed"] = int(r.get("seed", 0))
	if not r.has("size"):
		var sizes: Array = _Hoods.get_hood(str(look["id"])).get("sizes", [0.3, 0.5, 0.2])
		var pick := RandomNumberGenerator.new()
		pick.seed = hash([int(r["seed"]), "size"])
		r["size"] = int(_HoodStyles.pick(pick, [[0, sizes[0]], [1, sizes[1]], [2, sizes[2]]]))
	r["size"] = clampi(int(r["size"]), 0, 2)
	r["season"] = posmod(int(r.get("season", Seasons.current())), 4)
	r["frontage"] = float(r.get("frontage", look["frontage"]))
	r["depth"] = float(r.get("depth", Constants.ART_PARCEL_DEPTH))
	r["detail"] = str(r.get("detail", "full"))
	r["solid"] = bool(r.get("solid", false))
	r["job"] = bool(r.get("job", false))
	# A job house is never a neighbors-only archetype, whatever the caller says:
	# it has to be the same house as its job yard (HouseBuilder.request_for).
	r["neighbor"] = bool(r.get("neighbor", false)) and not bool(r["job"])
	r["force"] = r.get("force", [])
	r["uniform"] = r.get("uniform", {})
	r["rebel"] = bool(r.get("rebel", false))
	r["vacant"] = bool(r.get("vacant", false))
	r["labels"] = int(r.get("labels", 0))
	r["house"] = r.get("house", {})
	return r


## Everything a parcel will hold, decided without making a node: the house req
## and where it stands, the drive, walk, beds, fences, props, trees, what grass
## keeps clear of, what the season decorates, the art-test signature counts, and
## the art hash. A pure function of req.
static func plan(req: Dictionary) -> Dictionary:
	var r := normalized(req)
	var look := _HoodStyles.style(str(r["hood"]))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(r["seed"]), "parcel"])
	var frontage := float(r["frontage"])
	var depth := float(r["depth"])
	var half_w := frontage * 0.5
	var half_d := depth * 0.5
	var p := {
		"req": r, "rect": Rect2(-half_w, -half_d, frontage, depth), "props": [], "trees": [], "beds": [],
		"pools": [], "clear": [], "taken": [], "signature": {}, "house_req": {}, "house_spec": {},
		"house_at": Vector3.ZERO, "drive": [], "walk": [], "mailbox": Vector3.INF, "door": Vector3.ZERO,
	}
	var street: Dictionary = look["street"]
	var paved := "pavers" if str(street.get("sidewalk", "")) == "pavers" else "concrete"
	var drive_surface := "gravel" if str(street.get("surface", "road")) == "gravel" else paved
	var wide := frontage >= 40.0
	var house_front := -half_d + 4.0
	var house_back := -half_d + 2.0
	var drive_side := 1.0
	var drive_x := 0.0
	var spec: Dictionary = {}
	if bool(r["vacant"]):
		p["drive"] = []
		p["walk"] = []
	else:
		var house_req := _HouseBuilder.request_for(str(r["hood"]), int(r["seed"]), int(r["size"]), r["house"], bool(r["neighbor"]))
		var uniform: Dictionary = r["uniform"]
		for key: String in ["archetype", "width", "depth", "stories"]:
			if uniform.has(key):
				house_req[key] = uniform[key]
		if bool(r["rebel"]) and look.has("rebel_door"):
			house_req["door"] = look["rebel_door"]
		var at: Vector3 = house_req.get("at", Vector3.ZERO)
		var width := float(house_req["width"])
		var house_depth := float(house_req["depth"])
		var reach := Constants.ART_HOUSE_SIDE_REACH
		if wide:
			# The job yard's layout (levels/lots/lot_generator.gd): the drive at x 0
			# from z 3 to the street, the house where the yard's numbers put it.
			drive_x = 0.0
			drive_side = 1.0 if at.x < 0.0 else -1.0
			at.x = clampf(at.x, -half_w + width * 0.5 + reach + 1.0, half_w - width * 0.5 - reach - 1.0)
		else:
			# A narrow lot: the house hugs one side, the drive runs up the other.
			drive_side = 1.0 if posmod(int(r["seed"]), 2) == 0 else -1.0
			at.x = -drive_side * (half_w - width * 0.5 - reach - 0.6)
			drive_x = at.x + drive_side * (width * 0.5 + reach + 0.4 + 1.8)
			drive_x = clampf(drive_x, -half_w + 2.0, half_w - 2.0)
		at.z = clampf(at.z, -half_d + house_depth * 0.5 + Constants.ART_HOUSE_BACK_REACH + 1.0, half_d - house_depth * 0.5 - Constants.ART_HOUSE_FRONT_REACH - 6.0)
		house_req["at"] = at
		spec = _HouseBuilder.spec_for(house_req)
		p["house_req"] = house_req
		p["house_spec"] = spec
		p["house_at"] = at
		var footprint: Rect2 = spec.get("footprint", Rect2(-width * 0.5, -house_depth * 0.5, width, house_depth))
		var house_rect := Rect2(at.x + footprint.position.x, at.z + footprint.position.y, footprint.size.x, footprint.size.y)
		(p["taken"] as Array).append(house_rect.grow(0.6))
		p["clear"].append([Vector3(house_rect.get_center().x, 0.0, house_rect.get_center().y), Vector3(house_rect.size.x + 0.6, 1.0, house_rect.size.y + 0.6)])
		var door: Vector3 = at + (spec.get("door", Vector3(0.0, 1.6, house_depth * 0.5)) as Vector3)
		p["door"] = door
		house_front = at.z + house_depth * 0.5 + float(spec.get("porch_depth", 0.0))
		house_back = at.z - house_depth * 0.5 - Constants.ART_HOUSE_BACK_REACH
		# The drive: up beside the house on a narrow lot, from z 3 on a wide one.
		var drive_width := 4.2 if wide else 3.6
		var drive_from := 3.0 if wide else at.z - house_depth * 0.5 + 1.0
		p["drive"] = [Vector3(drive_x, 0.0, drive_from), Vector3(drive_x, 0.0, half_d)]
		p["drive_width"] = drive_width
		(p["taken"] as Array).append(Rect2(drive_x - drive_width * 0.5 - 0.3, drive_from, drive_width + 0.6, half_d - drive_from))
		p["clear"].append([Vector3(drive_x, 0.0, (drive_from + half_d) * 0.5), Vector3(drive_width + 0.2, 1.0, half_d - drive_from)])
		p["drive_surface"] = drive_surface
		# The front walk from the porch: to the drive on a wide lot, the street on a narrow one.
		var walk_to := 3.0 if wide else half_d
		if house_front + 0.3 < walk_to:
			p["walk"] = [Vector3(door.x, 0.0, house_front), Vector3(door.x, 0.0, walk_to)]
			(p["taken"] as Array).append(Rect2(door.x - 0.9, house_front, 1.8, walk_to - house_front))
			p["clear"].append([Vector3(door.x, 0.0, (house_front + walk_to) * 0.5), Vector3(1.5, 1.0, walk_to - house_front)])
		else:
			p["walk"] = []
		p["walk_surface"] = paved
		# The mailbox at the curb (Dandelion Acres shares a kiosk instead).
		var mailbox_kind := str(look.get("mailbox", "mailbox_post"))
		var mailbox := Vector3(3.2, 0.0, half_d - 0.4) if wide else Vector3(drive_x + drive_side * 2.4, 0.0, half_d - 0.4)
		p["mailbox"] = mailbox
		if mailbox_kind != "mailbox_cluster":
			_prop(p, mailbox_kind, Transform3D(Basis(Vector3.UP, PI), mailbox))
		# Flower beds flanking the walk, in front of the porch.
		_beds(p, rng, look, door.x, house_front, house_rect)
	var front_lawn := Rect2(-half_w + 1.2, house_front + 1.2, frontage - 2.4, maxf(half_d - 2.0 - (house_front + 1.2), 0.0))
	var back_lawn := Rect2(-half_w + 1.2, -half_d + 1.2, frontage - 2.4, maxf(house_back - 1.2 - (-half_d + 1.2), 0.0))
	var side_lawn := Rect2(-half_w + 1.2, -half_d + 1.2, frontage - 2.4, depth - 3.2)
	if bool(r["vacant"]):
		_prop(p, "for_sale_sign", Transform3D(Basis(Vector3.UP, PI), Vector3(rng.randf_range(-3.0, 3.0), 0.0, half_d - 2.2)), Color.WHITE, Vector3.ONE, true)
		if rng.randf() < 0.5:
			_scatter(p, rng, "tire_stack", front_lawn, Color.WHITE)
		front_lawn = side_lawn
	else:
		_front_fence(p, rng, look, half_w, half_d, drive_x)
		# Forced props first (the block's signature top-up), then the style's own.
		for kind: Variant in r["force"]:
			_styled(p, rng, str(kind), spec, front_lawn, back_lawn, side_lawn, look, true)
		if not bool(r["job"]):
			for entry: Array in look.get("yard_props", []):
				if rng.randf() < float(entry[1]):
					for _index: int in rng.randi_range(1, int(entry[2])):
						_styled(p, rng, str(entry[0]), spec, front_lawn, back_lawn, side_lawn, look, false)
			var backyard: Dictionary = look.get("backyard", {})
			for key: String in backyard:
				if rng.randf() < float(backyard[key]) and BACKYARD.has(key):
					_styled(p, rng, BACKYARD[key], spec, front_lawn, back_lawn, side_lawn, look, false)
			_cars_and_bins(p, rng, look, drive_x, drive_side, half_d, wide)
	_trees(p, rng, look, front_lawn, back_lawn, half_w, half_d, drive_side)
	# What the season dresses: lawns free of everything above.
	# front: the free front lawn alone (the block's inflatable snowman), or absent.
	var yard: Array = []
	var front_free := Rect2()
	for rect: Rect2 in [front_lawn, back_lawn]:
		if rect.size.x > 2.0 and rect.size.y > 2.0:
			var free := _free_rect(p, rect)
			if free.size.x >= 2.0 and free.size.y >= 2.0:
				yard.append(free)
				if rect == front_lawn:
					front_free = free
	p["decor"] = {
		"house_at": p["house_at"], "spec": p["house_spec"], "beds": p["beds"], "trees": _decor_trees(p),
		"drive": p["drive"], "walk": p["walk"], "pools": p["pools"], "yard": yard, "job": bool(r["job"]),
	}
	if front_free.has_area():
		p["decor"]["front"] = front_free
	p["hash"] = _hash(p)
	return p


# ---------------------------------------------------------------- pieces of a plan

static func _prop(p: Dictionary, kind: String, xform: Transform3D, color: Color = Color.WHITE, size: Vector3 = Vector3.ONE, complex: bool = false, opts: Dictionary = {}) -> void:
	var entry := {"kind": kind, "xform": xform, "color": color, "size": size, "complex": complex or not _PropCatalog.is_simple(kind), "opts": opts}
	var box: AABB = _PropCatalog.mesh(kind, color, size).get_meta("aabb", AABB())
	entry["big"] = maxf(box.size.x, box.size.z) >= Constants.ART_LARGE_PROP_SIZE or box.size.y > 2.5
	(p["props"] as Array).append(entry)
	if _PropCatalog.SIGNATURE.has(kind):
		var group := str(_PropCatalog.SIGNATURE[kind])
		(p["signature"] as Dictionary)[group] = int((p["signature"] as Dictionary).get(group, 0)) + 1


## A prop of kind where the style puts it: the porch, the backyard, or the front
## lawn, on a free spot. Returns false when there was no room.
static func _styled(p: Dictionary, rng: RandomNumberGenerator, kind: String, spec: Dictionary, front: Rect2, back: Rect2, side: Rect2, look: Dictionary, forced: bool) -> bool:
	var r: Dictionary = p["req"]
	if ON_PORCH.has(kind):
		var porch := float(spec.get("porch_depth", 0.0))
		if porch < 1.4:
			return false
		var door: Vector3 = p["door"]
		var floor_y := maxf(door.y - 1.1, 0.0)
		var house_at: Vector3 = p["house_at"]
		var front_z := house_at.z + float(spec.get("depth", 8.0)) * 0.5
		var x := door.x + (1.7 if rng.randf() < 0.5 else -1.7)
		_prop(p, kind, Transform3D(Basis(Vector3.UP, PI), Vector3(x, floor_y, front_z + porch * 0.5)))
		return true
	var opts := {}
	var color := Color.WHITE
	var size := Vector3.ONE
	match kind:
		"pool_inground":
			size = POOL_SIZE
		"hoa_flag":
			if int(r["labels"]) > 0:
				r["labels"] = int(r["labels"]) - 1
				opts["sign"] = "hoa_violation"
		"rebel_flamingo":
			return _rebel_flamingo(p, rng, front)
	var region := back if IN_BACK.has(kind) and back.size.y > 3.0 else front
	if region.size.y < 1.0:
		region = side
	var spot := _spot(p, rng, kind, region, color, size)
	if spot == Vector3.INF:
		return false
	var yaw := PI + rng.randf_range(-0.6, 0.6) if region == front else rng.randf() * TAU
	if kind == "pool_inground":
		yaw = 0.0
		(p["pools"] as Array).append(spot)
	_prop(p, kind, Transform3D(Basis(Vector3.UP, yaw), spot), color, size, not opts.is_empty(), opts)
	return true


## Oak Hollow's one pink flamingo, surrounded by three NOTICE OF VIOLATION flags.
static func _rebel_flamingo(p: Dictionary, rng: RandomNumberGenerator, front: Rect2) -> bool:
	var spot := _spot(p, rng, "kiddie_pool", front, Color.WHITE, Vector3.ONE)
	if spot == Vector3.INF:
		return false
	_prop(p, "flamingo", Transform3D(Basis(Vector3.UP, PI + 0.3), spot))
	for index: int in 3:
		var angle := TAU * float(index) / 3.0 + 0.4
		_prop(p, "hoa_flag", Transform3D(Basis(Vector3.UP, PI + angle * 0.2), spot + Vector3(cos(angle), 0.0, sin(angle)) * 0.7), Color.WHITE, Vector3.ONE, true, {"sign": "hoa_violation"})
	return true


## A free spot for kind inside region, or Vector3.INF. Marks it taken.
static func _spot(p: Dictionary, rng: RandomNumberGenerator, kind: String, region: Rect2, color: Color, size: Vector3) -> Vector3:
	var box: AABB = _PropCatalog.mesh(kind, color, size).get_meta("aabb", AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE))
	var radius := maxf(box.size.x, box.size.z) * 0.5 + 0.3
	var inner := region.grow(-radius)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return Vector3.INF
	for _try: int in Constants.ART_PARCEL_SPOT_TRIES:
		var at := Vector2(inner.position.x + rng.randf() * inner.size.x, inner.position.y + rng.randf() * inner.size.y)
		var rect := Rect2(at - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
		var free := true
		for taken: Rect2 in p["taken"]:
			if taken.intersects(rect):
				free = false
				break
		if free:
			(p["taken"] as Array).append(rect)
			return Vector3(at.x, 0.0, at.y)
	return Vector3.INF


## One more of kind somewhere in region (no rotation preference).
static func _scatter(p: Dictionary, rng: RandomNumberGenerator, kind: String, region: Rect2, color: Color) -> void:
	var spot := _spot(p, rng, kind, region, color, Vector3.ONE)
	if spot != Vector3.INF:
		_prop(p, kind, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), spot), color)


## Flower beds either side of the walk, just past the porch, edged in the
## style's bed edge (tire planters for Dandelion Acres).
static func _beds(p: Dictionary, rng: RandomNumberGenerator, look: Dictionary, walk_x: float, front: float, house_rect: Rect2) -> void:
	for side: float in [-1.0, 1.0]:
		if rng.randf() < 0.25:
			continue
		var length := rng.randf_range(2.4, 3.6)
		var x := walk_x + side * (1.1 + length * 0.5)
		if x - length * 0.5 < house_rect.position.x or x + length * 0.5 > house_rect.end.x:
			continue
		var center := Vector3(x, 0.0, front + 0.1 + 0.6)
		var size := Vector3(length, 0.12, 1.2)
		(p["beds"] as Array).append([center, size])
		(p["taken"] as Array).append(Rect2(x - length * 0.5, front + 0.1, length, 1.2))
		p["clear"].append([center, size + Vector3(0.2, 0.0, 0.2)])
		if str(look.get("bed_edge", "")) == "tire":
			# The tire planters stand just past the bed, on the lawn: keep them clear too.
			(p["taken"] as Array).append(Rect2(x - length * 0.5, front + 1.3, length, 1.0))
			for index: int in maxi(1, int(length / 1.1)):
				_prop(p, "tire_planter", Transform3D(Basis.IDENTITY, center + Vector3(-length * 0.5 + 0.55 + float(index) * 1.1, 0.0, 0.85)))


## The front fence along the street edge, open at the drive and the walk. Iron
## gets stone pillars and a gate across the drive, lions if the style has them.
static func _front_fence(p: Dictionary, rng: RandomNumberGenerator, look: Dictionary, half_w: float, half_d: float, drive_x: float) -> void:
	var kind := str(_HoodStyles.pick(rng, look.get("fence_front", [])))
	if not FENCE_RUNS.has(kind):
		return
	var run: String = FENCE_RUNS[kind]
	var z := half_d - 0.6
	var drive_gap := 2.05 if kind == "iron" else float(p.get("drive_width", 4.2)) * 0.5 + 0.3
	var gaps: Array[Vector2] = [Vector2(drive_x - drive_gap, drive_x + drive_gap)]
	var walk: Array = p["walk"]
	if walk.size() == 2 and (walk[1] as Vector3).z >= half_d - 0.1:
		var walk_x := (walk[1] as Vector3).x
		gaps.append(Vector2(walk_x - 0.9, walk_x + 0.9))
	gaps.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var spans: Array[Vector2] = []
	var from := -half_w + 0.4
	for gap: Vector2 in gaps:
		if gap.x - from > 0.6:
			spans.append(Vector2(from, gap.x))
		from = maxf(from, gap.y)
	if half_w - 0.4 - from > 0.6:
		spans.append(Vector2(from, half_w - 0.4))
	for span: Vector2 in spans:
		var length := span.y - span.x
		var pieces := maxi(1, ceili(length / 6.0))
		var each := length / float(pieces)
		for index: int in pieces:
			var x := span.x + each * (float(index) + 0.5)
			_prop(p, run, Transform3D(Basis.IDENTITY, Vector3(x, 0.0, z)), Color.WHITE, Vector3(snappedf(each, 0.1), 0.0, 0.0))
	if kind == "iron":
		for side: float in [-1.0, 1.0]:
			_prop(p, "gate_pillar", Transform3D(Basis.IDENTITY, Vector3(drive_x + side * 2.05, 0.0, z)))
			if rng.randf() < 0.6:
				_prop(p, "lion_statue", Transform3D(Basis(Vector3.UP, PI), Vector3(drive_x + side * 2.9, 0.0, z - 1.2)))
				(p["taken"] as Array).append(Rect2(drive_x + side * 2.9 - 0.7, z - 1.9, 1.4, 1.4))
		_prop(p, "iron_gate", Transform3D(Basis.IDENTITY, Vector3(drive_x, 0.0, z)))
	(p["taken"] as Array).append(Rect2(-half_w, z - 0.5, half_w * 2.0, 1.0))


## A car on the drive (maybe), the bins out by the curb (maybe).
static func _cars_and_bins(p: Dictionary, rng: RandomNumberGenerator, look: Dictionary, drive_x: float, drive_side: float, half_d: float, wide: bool) -> void:
	if (p["drive"] as Array).size() == 2 and rng.randf() < 0.75:
		var kind := str(_HoodStyles.pick(rng, look.get("cars", [["car_sedan", 1]])))
		var colors: Array = look.get("car_colors", [Color(0.5, 0.5, 0.52)])
		var color: Color = colors[rng.randi() % colors.size()]
		var z := half_d - 5.0 if wide else lerpf(((p["drive"] as Array)[0] as Vector3).z, half_d, 0.55)
		_prop(p, kind, Transform3D(Basis(Vector3.UP, rng.randf_range(-0.05, 0.05)), Vector3(drive_x, 0.0, z)), color)
	if rng.randf() < float(look.get("bins", 0.0)):
		var x := drive_x - drive_side * (float(p.get("drive_width", 4.2)) * 0.5 + 0.7)
		if wide:
			x = drive_x + 2.9
		for index: int in 2:
			_prop(p, "wheelie_bin", Transform3D(Basis(Vector3.UP, PI + rng.randf_range(-0.2, 0.2)), Vector3(x + float(index) * 0.75 * (-1.0 if wide else -drive_side), 0.0, half_d - 1.1)), [Color(0.2, 0.42, 0.24), Color(0.25, 0.28, 0.32)][index])


## The parcel's trees from the style: kinds, crowns and heights, in the front
## or back lawn. Oak Hollow's are identical: one tree, the same spot, height,
## kind and crown in every yard.
static func _trees(p: Dictionary, rng: RandomNumberGenerator, look: Dictionary, front: Rect2, back: Rect2, half_w: float, half_d: float, drive_side: float) -> void:
	var trees: Dictionary = look.get("trees", {})
	var heights: Vector2 = trees.get("height", Vector2(7.0, 9.0))
	var per: Vector2i = trees.get("per_parcel", Vector2i(1, 2))
	if bool((p["req"] as Dictionary)["job"]):
		return
	if bool(trees.get("identical", false)):
		var kind := str(((trees["kinds"] as Array)[0] as Array)[0])
		var crown := str(((trees["crowns"] as Array)[0] as Array)[0])
		var at := Vector3(-drive_side * half_w * 0.45, 0.0, half_d - 7.0)
		(p["trees"] as Array).append([at, kind, crown, heights.x, 1, 0.0])
		(p["taken"] as Array).append(Rect2(at.x - 1.6, at.z - 1.6, 3.2, 3.2))
		return
	for _index: int in rng.randi_range(per.x, per.y):
		var kind := str(_HoodStyles.pick(rng, trees.get("kinds", [["broadleaf", 1]])))
		var crown := str(_HoodStyles.pick(rng, trees.get("crowns", [["orange", 1]])))
		var height := rng.randf_range(heights.x, heights.y)
		var region := front if rng.randf() < 0.6 or back.size.y < 4.0 else back
		var spot := _tree_spot(p, rng, region)
		if spot == Vector3.INF:
			continue
		(p["trees"] as Array).append([spot, kind, crown, height, rng.randi() % 4, rng.randf() * TAU])


static func _tree_spot(p: Dictionary, rng: RandomNumberGenerator, region: Rect2) -> Vector3:
	var inner := region.grow(-1.8)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return Vector3.INF
	for _try: int in Constants.ART_PARCEL_SPOT_TRIES:
		var at := Vector2(inner.position.x + rng.randf() * inner.size.x, inner.position.y + rng.randf() * inner.size.y)
		var rect := Rect2(at - Vector2(1.6, 1.6), Vector2(3.2, 3.2))
		var free := true
		for taken: Rect2 in p["taken"]:
			if taken.intersects(rect):
				free = false
				break
		for tree: Array in p["trees"]:
			if Vector2((tree[0] as Vector3).x, (tree[0] as Vector3).z).distance_to(at) < 5.5:
				free = false
		if free:
			(p["taken"] as Array).append(rect)
			return Vector3(at.x, 0.0, at.y)
	return Vector3.INF


## The biggest piece of rect that nothing stands on (a cheap shrink: rows of
## rect's height cut where something was placed), for seasonal clutter.
static func _free_rect(p: Dictionary, rect: Rect2) -> Rect2:
	var best := rect
	for taken: Rect2 in p["taken"]:
		if not best.intersects(taken):
			continue
		# Keep the bigger side of best around taken, along x.
		var left := Rect2(best.position, Vector2(maxf(taken.position.x - best.position.x, 0.0), best.size.y))
		var right := Rect2(Vector2(taken.end.x, best.position.y), Vector2(maxf(best.end.x - taken.end.x, 0.0), best.size.y))
		best = left if left.get_area() >= right.get_area() else right
		if best.size.x < 2.0:
			# Too little lawn left: no clutter here at all (an empty Rect2 callers
			# skip), never the whole lawn with the drive and props on it.
			return Rect2()
	return best


static func _decor_trees(p: Dictionary) -> Array:
	var out: Array = []
	for tree: Array in p["trees"]:
		out.append([tree[0], tree[1], tree[2]])
	return out


## The lawn, drive, walk and beds, painted per vertex into one kit.
static func _ground(kit: RefCounted, to_kit: Transform3D, p: Dictionary, look: Dictionary) -> void:
	var saved: Transform3D = kit.get("frame")
	kit.set("frame", to_kit)
	var rect: Rect2 = p["rect"]
	var ground: Dictionary = look.get("ground", {})
	var color: Color = ground.get("color", Color(0.38, 0.55, 0.24))
	var surface := str(ground.get("surface", "grass"))
	var params := Vector4(float(ground.get("stripe", 0.0)), 0.0, float(ground.get("flowers", 0.0)), 0.0)
	var dirt := float(ground.get("dirt", 0.0))
	var lawn_style := {"params": params}
	if dirt > 0.0:
		lawn_style["accent"] = color.lerp(DRY, clampf(dirt, 0.0, 1.0))
	var top := Constants.ART_LAWN_TOP
	kit.call("box", Vector3(rect.size.x, 0.04, rect.size.y), Vector3(rect.get_center().x, top - 0.02, rect.get_center().y), color, surface, Basis.IDENTITY, lawn_style)
	var drive: Array = p["drive"]
	if drive.size() == 2:
		var a: Vector3 = drive[0]
		var b: Vector3 = drive[1]
		var surface_name := str(p.get("drive_surface", "concrete"))
		var tone: Color = {"gravel": GRAVEL, "pavers": PAVERS}.get(surface_name, CONCRETE)
		kit.call("box", Vector3(float(p.get("drive_width", 4.2)), 0.05, b.z - a.z), Vector3(a.x, Constants.ART_DRIVE_TOP - 0.025, (a.z + b.z) * 0.5), tone, surface_name)
	var walk: Array = p["walk"]
	if walk.size() == 2:
		var a: Vector3 = walk[0]
		var b: Vector3 = walk[1]
		var surface_name := str(p.get("walk_surface", "concrete"))
		kit.call("box", Vector3(1.3, 0.04, b.z - a.z), Vector3(a.x, Constants.ART_WALK_TOP - 0.02, (a.z + b.z) * 0.5), PAVERS if surface_name == "pavers" else CONCRETE.lightened(0.04), surface_name)
	var edge := str(look.get("bed_edge", "concrete"))
	for bed: Array in p["beds"]:
		var center: Vector3 = bed[0]
		var size: Vector3 = bed[1]
		kit.call("box", size, center + Vector3(0.0, size.y * 0.5, 0.0), DIRT, "dirt")
		if edge == "tire":
			continue
		var edging: Color = {"brick": Color(0.58, 0.32, 0.26), "stone": Color(0.66, 0.64, 0.6), "timber": Color(0.5, 0.36, 0.24)}.get(edge, Color(0.62, 0.6, 0.57))
		var edging_surface: String = {"brick": "brick", "stone": "stone", "timber": "planks"}.get(edge, "concrete")
		kit.call("box", Vector3(size.x + 0.2, 0.18, 0.12), center + Vector3(0.0, 0.09, size.z * 0.5 + 0.06), edging, edging_surface)
		for side: float in [-1.0, 1.0]:
			kit.call("box", Vector3(0.12, 0.18, size.z), center + Vector3(side * (size.x * 0.5 + 0.04), 0.09, 0.0), edging, edging_surface)
	kit.set("frame", saved)


## Colliders for a drivable town: one StaticBody3D "Solids", a box each.
static func _solids(root: Node3D, p: Dictionary) -> void:
	var body := StaticBody3D.new()
	body.name = "Solids"
	root.add_child(body)
	for entry: Array in colliders(p["req"]):
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = entry[1]
		shape.shape = box
		shape.position = entry[0]
		body.add_child(shape)


## The art hash: every look decision, snapped to a centimeter, in order.
static func _hash(p: Dictionary) -> int:
	var r: Dictionary = p["req"]
	var parts: Array = [r["hood"], r["seed"], r["size"], r["season"], r["detail"], r["frontage"], r["vacant"]]
	var house_req: Dictionary = p["house_req"]
	if not house_req.is_empty():
		parts.append([house_req["archetype"], snappedf(float(house_req["width"]), 0.01), snappedf(float(house_req["depth"]), 0.01), house_req["stories"], (house_req["wall"] as Color).to_html(), (house_req["door"] as Color).to_html(), (p["house_at"] as Vector3).snapped(Vector3.ONE * 0.01)])
	for entry: Dictionary in p["props"]:
		parts.append([entry["kind"], (entry["xform"] as Transform3D).origin.snapped(Vector3.ONE * 0.01), (entry["color"] as Color).to_html()])
	for tree: Array in p["trees"]:
		parts.append([(tree[0] as Vector3).snapped(Vector3.ONE * 0.01), tree[1], tree[2]])
	return hash(parts)
