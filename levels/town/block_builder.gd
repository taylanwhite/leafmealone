extends RefCounted

## Authority: local, cosmetic. A whole street block in a neighborhood's style
## (levels/town/hood_styles.gd): the street (levels/town/street_builder.gd),
## parcels on both sides (levels/town/lot_builder.gd), the hood's set pieces
## (levels/town/set_pieces.gd), side hedges or fences between yards, the back
## boundary, street trees, parked cars, grass, and the season's block decor
## (levels/town/season_dressing.gd). Pure function of (hood, seed, season): every
## peer builds the same block from data it already has; nothing is networked,
## nothing collides, and nothing touches the gameplay rng.
##
##   BlockBuilder.build(parent, xform, "lakeside", seed, Seasons.current())
##   BlockBuilder.build_for_job(lot, hood, job_seed, {"house_rect": ...})
##
## BLOCK FRAME (the job lot's own space; levels/dressing/neighborhood.gd's
## layout, so Chefty's path, pedestrians and ambience cars stay valid): the
## street runs along x at z STREET (22.6..31.4) with sidewalks at SIDEWALK_NEAR
## and SIDEWALK_FAR, STREET_LENGTH long. Near-side parcels face +z with their
## street edge at z 20 (the job yard is the slot at x 0, between hedge rows at
## x +-21.2); far-side parcels are turned PI around z 56 (their street edge at
## z 36). Mansion Hill's far side stands on a 3 m terrace; Lakeside's lake lies
## behind the back boundary (z -24).
##
## opts:
##   job        the job yard (a Dictionary, see build_for_job): the slot at x 0 is
##              left empty, Chefty's lane is kept clear, and a far parcel in the
##              NICE BOYS van's way out is left a vacant lot
##   async      true (default): the street, the plan, the set pieces, each parcel
##              and the finish are BuildQueue steps (levels/build_queue.gd, one
##              parcel a frame at most: a job's block used to hold a joiner's
##              frame for seconds); false builds it all now
##   length     street length (default STREET_LENGTH)
##   grass      false: no grass (default true)
##   detail     parcels' detail ("full")
##   meta_target  a node that gets metas art_done, art_hash and hood_style when done
## The returned root (levels/town/parcel.gd, role "block") gets metas art_done
## (false until the last parcel), art_hash, hood_style, parcels (count),
## lamps (PackedVector3Array), back_boundary (kind), build_ms, and emits built.

const _LotBuilder = preload("res://levels/town/lot_builder.gd")
const _StreetBuilder = preload("res://levels/town/street_builder.gd")
const _SetPieces = preload("res://levels/town/set_pieces.gd")
const _HoodStyles = preload("res://levels/town/hood_styles.gd")
const _Parcel = preload("res://levels/town/parcel.gd")
const _Neighborhood = preload("res://levels/dressing/neighborhood.gd")
const _PropCatalog = preload("res://props/prop_catalog.gd")
const _PropBatch = preload("res://props/prop_batch.gd")
const _HouseKit = preload("res://props/house_kit.gd")
const _Trees = preload("res://props/trees.gd")
const _Grass = preload("res://props/grass.gd")
const _Surfaces = preload("res://props/surfaces.gd")
const _StreetLife = preload("res://levels/dressing/street_life.gd")
const _BuildQueue = preload("res://levels/build_queue.gd")

## The job yard's slot: x +-JOB_HALF between the hedge rows.
const JOB_HALF: float = 21.2
## The job yard's own mailbox, at the curb by the drive (yard space; the town's
## yards have theirs at the same spot, levels/town/town_dressing.gd).
const JOB_MAILBOX := Vector3(3.2, 0.0, 19.9)
## The job yard's front edge (lot z), where its drive meets the sidewalk.
const YARD_FRONT: float = 20.0
## The drive's apron across the sidewalk to the street, by the yard's drive surface.
const APRON: Dictionary = {"concrete": Color(0.66, 0.64, 0.6), "gravel": Color(0.6, 0.56, 0.5), "pavers": Color(0.66, 0.46, 0.36)}
## Far-side parcels' centers.
const FAR_Z: float = 56.0
## Signature groups a parcel can be made to carry (the top-up), by the kind that counts.
const TOPUP: Dictionary = {
	"junk_pile": "junk_pile", "porch_swing": "porch_swing", "pool_inground": "pool_inground", "trampoline": "trampoline",
	"violation_flag": "hoa_flag", "fountain": "fountain_tiered", "topiary_rake": "topiary_rake",
}


## Builds the block. See the top of this file.
static func build(parent: Node3D, xform: Transform3D, hood_id: String, block_seed: int, season: int, opts: Dictionary = {}) -> Node3D:
	var started := Time.get_ticks_usec()
	var look := _HoodStyles.style(hood_id)
	var hood := str(look["id"])
	var root: Node3D = _Parcel.new()
	root.name = "Block"
	root.transform = xform
	root.set("role", "block")
	root.set("hood", hood)
	root.set("seed_value", block_seed)
	root.set("season", season)
	root.set_meta("art_done", false)
	root.set_meta("hood_style", hood)
	parent.add_child(root)
	var is_job := opts.has("job")
	var length := float(opts.get("length", _Neighborhood.STREET_LENGTH))
	var terrace := hood == "mansion_hill"
	var state := {
		"root": root, "look": look, "hood": hood, "opts": opts, "is_job": is_job, "yard": opts.get("job", {}),
		"length": length, "lane": opts.get("keep_clear_lane", Constants.ART_CHEFTY_LANE if is_job else Rect2()),
		"batch": _PropBatch.new(root), "kit": _HouseKit.new(), "street_z": (_Neighborhood.STREET.x + _Neighborhood.STREET.y) * 0.5,
		"far_y": Constants.ART_TERRACE_HEIGHT if terrace else 0.0, "season": season, "seed": block_seed,
		# yard_hash: the job yard's own look decisions (levels/lots/lot_generator.gd).
		"digest": [hood, block_seed, season, length, is_job, int(opts.get("yard_hash", 0))],
		"grass": bool(opts.get("grass", true)), "started": started, "meta_target": opts.get("meta_target", null),
	}
	# Async (in the tree): each piece below, each parcel and the finish are
	# BuildQueue steps (levels/build_queue.gd), so a job's block never holds up
	# a frame for more than one of them. They run in this order either way, so
	# the block (and its art hash) is the same.
	var steps: Array[Callable] = [_build_street.bind(state), _build_plan.bind(state), _build_pieces.bind(state), _build_decor.bind(state)]
	state["async"] = bool(opts.get("async", true)) and root.is_inside_tree()
	if bool(state["async"]):
		for step: Callable in steps:
			_BuildQueue.later(root, _while_built(root, step), "block")
		_BuildQueue.later(root, _while_built(root, _build_async.bind(state)), "block")
	else:
		for step: Callable in steps:
			step.call()
		for index: int in (state["reqs"] as Array).size():
			_LotBuilder.build(root, (state["slots"][index] as Dictionary)["xform"], state["reqs"][index])
		_finish(state)
	return root


## A piece of a step: a BuildQueue step of its own when the block is built
## async (right after the step that hands it over), else now.
static func _part(state: Dictionary, fn: Callable) -> void:
	if bool(state.get("async", false)):
		_BuildQueue.later(state["root"], _while_built(state["root"], fn), "block part")
	else:
		fn.call()


## step, run only while root is still in the tree (a yard swapped out mid-build).
static func _while_built(root: Node3D, step: Callable) -> Callable:
	return func() -> void:
		if is_instance_valid(root) and root.is_inside_tree():
			step.call()


## 1. The street, and the job yard's frontage.
static func _build_street(state: Dictionary) -> void:
	var root: Node3D = state["root"]
	var look: Dictionary = state["look"]
	var length := float(state["length"])
	var street_z := float(state["street_z"])
	var street := _StreetBuilder.segment(root, Vector3(-length * 0.5, 0.0, street_z), Vector3(length * 0.5, 0.0, street_z), look,
		{"batch": state["batch"], "keep_clear_lane": state["lane"], "hood": state["hood"]})
	state["street"] = street
	var lamps: PackedVector3Array = street.get_meta("lamps")
	state["lamps"] = lamps
	root.set_meta("lamps", lamps)
	if bool(state["is_job"]):
		(state["digest"] as Array).append(_job_frontage(root, look, state["yard"], state["kit"], state["batch"]))


## 2. Plan every parcel (data only), then top up the hood's signatures.
static func _build_plan(state: Dictionary) -> void:
	var look: Dictionary = state["look"]
	var block_seed := int(state["seed"])
	var slots := _slots(look, float(state["length"]), bool(state["is_job"]), float(state["far_y"]), block_seed)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([block_seed, "block", state["hood"]])
	var reqs := _requests(slots, look, block_seed, int(state["season"]), str((state["opts"] as Dictionary).get("detail", "full")), bool(state["is_job"]), state["root"], state["batch"], state["kit"])
	var plans: Array = []
	state["slots"] = slots
	state["reqs"] = reqs
	state["plans"] = plans
	state["rng"] = rng
	# A parcel plan is 5-15 ms: one a part.
	for req: Dictionary in reqs:
		_part(state, func() -> void: plans.append(_LotBuilder.plan(req)))
	_part(state, func() -> void:
		_top_up(look, slots, reqs, plans, state["street"])
		_labels(slots, reqs, plans))


## 3. Set pieces, side boundaries, the back boundary, street trees and cars.
static func _build_pieces(state: Dictionary) -> void:
	var root: Node3D = state["root"]
	var look: Dictionary = state["look"]
	var length := float(state["length"])
	var block_seed := int(state["seed"])
	var batch: RefCounted = state["batch"]
	var far_y := float(state["far_y"])
	var pieces := _set_pieces(root, look, state["slots"], state["plans"], state["lamps"], length, int(state["season"]), block_seed, batch, far_y)
	(state["digest"] as Array).append(pieces)
	_part(state, func() -> void: _side_boundaries(root, look, state["slots"], length, bool(state["is_job"]), far_y))
	var back := str(look.get("back_boundary", "wood_fence"))
	root.set_meta("back_boundary", back)
	_part(state, func() -> void:
		_SetPieces.back_boundary(root, back, Constants.ART_BACK_BOUNDARY_Z, length, batch, block_seed)
		if bool(state["is_job"]):
			_street_life(root, look, state["lamps"], back, block_seed))
	_part(state, func() -> void:
		_street_trees(root, look, length, far_y, state["rng"], batch)
		_parked_cars(look, length, state["rng"], batch, state["lane"]))


## 4. Block decor data: curbs, the drives the snowbanks leave open, the inflatable's spot.
static func _build_decor(state: Dictionary) -> void:
	var root: Node3D = state["root"]
	var slots: Array = state["slots"]
	var plans: Array = state["plans"]
	var street: Node3D = state["street"]
	var street_z := float(state["street_z"])
	var gaps: Array = [Vector2(-2.8, 2.8)] if bool(state["is_job"]) else []
	for index: int in plans.size():
		var drive: Array = (plans[index] as Dictionary)["drive"]
		if drive.size() == 2:
			var at: Vector3 = (slots[index] as Dictionary)["xform"] * (drive[1] as Vector3)
			gaps.append(Vector2(at.x - 2.6, at.x + 2.6))
	# Snowbanks sit on the sidewalk side of each curb, out of the road (and Chefty's lane).
	var banks: Array = []
	for curb: Array in street.get_meta("curbs", []):
		var out := Vector3(0.0, 0.0, signf((curb[0] as Vector3).z - street_z) * 0.6)
		banks.append([(curb[0] as Vector3) + out, (curb[1] as Vector3) + out])
	var decor := {"curbs": banks, "gaps": gaps, "inflatable": _inflatable_spot(slots, plans, int(state["seed"]))}
	root.set("decor", decor)
	for plan: Dictionary in plans:
		(state["digest"] as Array).append(plan["hash"])

## The job's block, under the job lot (gap-specs/art.json, critic C24):
## neighbors, street, set pieces and back boundary from (hood, job_seed, season),
## built over a few frames after the yard. yard (lot space, all optional):
## house_rect (Rect2), pool_at (Vector3), driveway ([from, to]), clear (Rect2s
## grass keeps off: beds, hedges, the pool), drive_surface (the apron's). The
## block adds the yard's mailbox, the drive's apron across the sidewalk and the
## street life (levels/dressing/street_life.gd dress_block). opts.yard_hash (the
## yard's own art decisions) goes into the art hash. It also tints
## the lot zone's Surroundings ground to the hood's lawn. opts.town: the town is
## drawing the street and the neighbors, so only the yard-scope art is done here
## (the ground tint; the yard's own house, fences and beds are the lot
## generator's). The lot gets metas art_done, art_hash and hood_style.
static func build_for_job(lot: Node3D, hood_id: String, job_seed: int, yard: Dictionary, opts: Dictionary = {}) -> Node3D:
	var look := _HoodStyles.style(hood_id)
	tint_ground(lot, (look["ground"] as Dictionary).get("color", Color(0.4, 0.56, 0.24)))
	if bool(opts.get("town", false)):
		var holder := Node3D.new()
		holder.name = "Block"
		lot.add_child(holder)
		holder.set_meta("art_done", true)
		holder.set_meta("art_hash", hash([str(look["id"]), job_seed, "town", int(opts.get("yard_hash", 0))]))
		lot.set_meta("hood_style", str(look["id"]))
		lot.set_meta("art_hash", holder.get_meta("art_hash"))
		lot.set_meta("art_done", true)
		return holder
	var options := opts.duplicate()
	options["job"] = yard
	options["meta_target"] = lot
	lot.set_meta("art_done", false)
	lot.set_meta("hood_style", str(look["id"]))
	return build(lot, Transform3D.IDENTITY, hood_id, job_seed, Seasons.current(), options)


## Tints the lot zone's Surroundings ground (the land past the block) to color:
## walks up from node to the first ancestor with a "Surroundings" child.
static func tint_ground(node: Node, color: Color) -> void:
	var at := node
	for _step: int in 5:
		if at == null:
			return
		var around := at.get_node_or_null("Surroundings")
		if around != null:
			for child: Node in around.get_children():
				if child is MeshInstance3D and child.has_meta("surface"):
					var surface := str(child.get_meta("surface"))
					child.set_meta("surface_base", color)
					(child as MeshInstance3D).material_override = _Surfaces.material(surface, color)
					return
			return
		at = at.get_parent()


## Counts each art-test signature group under root (batched props by their
## prop_instances): {group: count}.
static func signature_counts(root: Node) -> Dictionary:
	var counts := {}
	var seen := {}
	for node: Node in [root] + root.find_children("*", "", true, false):
		for group: StringName in node.get_groups():
			var name := str(group)
			if not name.begins_with("art_signature:") or seen.has([node.get_instance_id(), name]):
				continue
			seen[[node.get_instance_id(), name]] = true
			var key := name.trim_prefix("art_signature:")
			counts[key] = int(counts.get(key, 0)) + int(node.get_meta("prop_instances", 1))
	return counts


# ---------------------------------------------------------------- planning

## Every parcel slot: {side, x, frontage, xform, id, vacant, office}.
static func _slots(look: Dictionary, length: float, is_job: bool, far_y: float, block_seed: int) -> Array:
	var frontage := float(look["frontage"])
	var slots: Array = []
	var half := length * 0.5
	if not is_job:
		slots.append({"side": "near", "x": 0.0, "frontage": JOB_HALF * 2.0, "id": "near_0"})
	for side: float in [-1.0, 1.0]:
		var x := JOB_HALF + frontage * 0.5
		var index := 1
		while x <= half:
			slots.append({"side": "near", "x": side * x, "frontage": frontage, "id": "near_%d" % (index * int(side))})
			x += frontage
			index += 1
	var k := 0
	while (float(k) + 0.5) * frontage <= half:
		for side: float in [-1.0, 1.0]:
			var x := side * (float(k) + 0.5) * frontage
			slots.append({"side": "far", "x": x, "frontage": frontage, "id": "far_%d" % (k * 2 + (0 if side < 0.0 else 1))})
		k += 1
	for slot: Dictionary in slots:
		if slot["side"] == "near":
			slot["xform"] = Transform3D(Basis.IDENTITY, Vector3(float(slot["x"]), 0.0, 0.0))
		else:
			slot["xform"] = Transform3D(Basis(Vector3.UP, PI), Vector3(float(slot["x"]), far_y, FAR_Z))
		slot["vacant"] = false
		slot["office"] = false
	# Dandelion Acres' park office takes the far slot nearest the entrance.
	if (look["set_pieces"] as Array).has("park_office"):
		var first: Dictionary = {}
		for slot: Dictionary in slots:
			if slot["side"] == "far" and (first.is_empty() or float(slot["x"]) < float(first["x"])):
				first = slot
		if not first.is_empty():
			first["office"] = true
	# The NICE BOYS van leaves the lot along PI * 0.75: no house in its way.
	if is_job:
		var way := Vector2(cos(Constants.ART_VAN_ANGLE), sin(Constants.ART_VAN_ANGLE))
		for slot: Dictionary in slots:
			if slot["side"] != "far":
				continue
			# Where its house would stand: a far yard's house sits about 13 m behind its center.
			var center := Vector2(float(slot["x"]), FAR_Z + 13.0)
			var across := absf(way.x * center.y - way.y * center.x)
			if center.dot(way) > 0.0 and across < Constants.ART_VAN_CORRIDOR_HALF:
				slot["vacant"] = true
	return slots


## The LotBuilder req for every slot (offices get none: an empty plan).
static func _requests(slots: Array, look: Dictionary, block_seed: int, season: int, detail: String, is_job: bool, root: Node3D, batch: RefCounted, kit: RefCounted) -> Array:
	var reqs: Array = []
	var hood := str(look["id"])
	var uniformity := float(look.get("uniformity", 0.0))
	var template: Dictionary = {}
	# Oak Hollow's one rebel door, on a house that is really there.
	var rebel := -1
	if look.has("rebel_door"):
		var houses: Array = []
		for index: int in slots.size():
			if not bool((slots[index] as Dictionary)["vacant"]) and not bool((slots[index] as Dictionary)["office"]):
				houses.append(index)
		if not houses.is_empty():
			rebel = houses[posmod(hash([block_seed, "rebel"]), houses.size())]
	# Oak Hollow's flamingo goes in the far yard nearest the job.
	var flamingo := -1
	if (look["set_pieces"] as Array).has("rebel_flamingo"):
		var best := INF
		for index: int in slots.size():
			var slot: Dictionary = slots[index]
			if slot["side"] == "far" and not bool(slot["vacant"]) and absf(float(slot["x"])) < best:
				best = absf(float(slot["x"]))
				flamingo = index
	for index: int in slots.size():
		var slot: Dictionary = slots[index]
		var req := {
			"hood": hood, "seed": hash([block_seed, "neighbor", slot["id"]]), "season": season,
			"frontage": slot["frontage"], "detail": detail, "batch": batch, "kit": kit, "grass_root": root,
			"vacant": bool(slot["vacant"]) or bool(slot["office"]), "rebel": index == rebel, "force": [],
			# Set dressing nobody is hired at: neighbors-only archetypes allowed.
			"neighbor": true,
			"name": "Parcel_%s" % str(slot["id"]).replace("-", "m"),
		}
		if index == flamingo:
			(req["force"] as Array).append("rebel_flamingo")
		if not bool(req["vacant"]):
			var pick := RandomNumberGenerator.new()
			pick.seed = hash([block_seed, "uniform", slot["id"]])
			if template.is_empty():
				var first := _LotBuilder.plan(req)
				var house: Dictionary = first["house_req"]
				template = {"archetype": house["archetype"], "width": house["width"], "depth": house["depth"], "stories": house["stories"]}
			elif pick.randf() < uniformity:
				req["uniform"] = template
		reqs.append(req)
	return reqs


## Adds forced props to parcels until every prop-based signature group of the
## hood reaches its minimum (a hood's look never depends on luck).
static func _top_up(look: Dictionary, slots: Array, reqs: Array, plans: Array, street: Node3D) -> void:
	var counts := {}
	for plan: Dictionary in plans:
		for group: String in plan["signature"]:
			counts[group] = int(counts.get(group, 0)) + int((plan["signature"] as Dictionary)[group])
	var order: Array = range(slots.size())
	order.sort_custom(func(a: int, b: int) -> bool: return absf(float(slots[a]["x"])) < absf(float(slots[b]["x"])))
	var wanted: Dictionary = look.get("signature", {})
	for name: String in wanted:
		var group := name.trim_prefix("art_signature:")
		if not TOPUP.has(group):
			continue
		var need := int(wanted[name]) - int(counts.get(group, 0))
		for index: int in order:
			if need <= 0:
				break
			var req: Dictionary = reqs[index]
			if bool(req["vacant"]):
				continue
			var before := int(((plans[index] as Dictionary)["signature"] as Dictionary).get(group, 0))
			(req["force"] as Array).append(TOPUP[group])
			var again := _LotBuilder.plan(req)
			var after := int((again["signature"] as Dictionary).get(group, 0))
			if after > before:
				plans[index] = again
				need -= after - before
			else:
				(req["force"] as Array).pop_back()


## Hands out Constants.ART_VIOLATION_LABELS NOTICE OF VIOLATION signs to the
## block's plain violation flags, nearest the job first (the rest stay batched).
## Labels only swap how a flag is drawn, never where it stands, so the replan
## keeps every parcel's layout.
static func _labels(slots: Array, reqs: Array, plans: Array) -> void:
	var left := Constants.ART_VIOLATION_LABELS
	var order: Array = range(slots.size())
	order.sort_custom(func(a: int, b: int) -> bool: return absf(float(slots[a]["x"])) < absf(float(slots[b]["x"])))
	for index: int in order:
		if left <= 0:
			return
		var plain := 0
		for entry: Dictionary in (plans[index] as Dictionary)["props"]:
			if str(entry["kind"]) == "hoa_flag" and not (entry.get("opts", {}) as Dictionary).has("sign"):
				plain += 1
		if plain == 0:
			continue
		var req: Dictionary = reqs[index]
		req["labels"] = mini(left, plain)
		plans[index] = _LotBuilder.plan(req)
		left -= int(req["labels"])


# ---------------------------------------------------------------- the block's pieces

## The job yard's frontage: its mailbox at the curb in the hood's kind
## (Dandelion Acres' residents share kiosks, but the client still gets a post
## for its sticky note) and the drive's apron across the sidewalk. Returns what
## it decided, for the art hash.
static func _job_frontage(root: Node3D, look: Dictionary, yard: Dictionary, kit: RefCounted, batch: RefCounted) -> Array:
	var kind := str(look.get("mailbox", "mailbox_post"))
	if kind == "mailbox_cluster" or not _PropCatalog.has(kind):
		kind = "mailbox_post"
	var place := Transform3D(Basis(Vector3.UP, PI), JOB_MAILBOX)
	if _PropCatalog.is_simple(kind):
		batch.call("add", kind, place)
	else:
		_PropCatalog.place(root, kind, place)
	root.set_meta("job_mailbox", kind)
	var surface := str(yard.get("drive_surface", "concrete"))
	if not APRON.has(surface):
		surface = "concrete"
	var walk := str((look.get("street", {}) as Dictionary).get("sidewalk", "none")) != "none"
	var from_z := YARD_FRONT
	var to_z := _Neighborhood.STREET.x
	# Over the sidewalk and the curb where there is one, flush with the shoulder where there isn't.
	var top := 0.105 if walk else 0.03
	kit.call("box", Vector3(4.2, top + 0.005, to_z - from_z + 0.02), Vector3(0.0, (top - 0.005) * 0.5, (from_z + to_z) * 0.5), APRON[surface], surface)
	return ["frontage", kind, surface]


## Posters, chalk, tags and the yard mailbox's note (levels/dressing/street_life.gd).
static func _street_life(root: Node3D, look: Dictionary, lamps: PackedVector3Array, back: String, block_seed: int) -> void:
	var street: Dictionary = look.get("street", {})
	var strip := bool(street.get("grass_strip", false))
	var walk_width := _StreetBuilder.SIDEWALK - (_StreetBuilder.GRASS_STRIP if strip else 0.0)
	var street_z := (_Neighborhood.STREET.x + _Neighborhood.STREET.y) * 0.5
	var outer := _StreetBuilder.ROAD_WIDTH * 0.5 + _StreetBuilder.CURB
	var offset := outer + _StreetBuilder.SIDEWALK - walk_width * 0.5
	var opts := {
		"lamp": str(street.get("lamp", "none")), "street_z": street_z, "boundary_z": Constants.ART_BACK_BOUNDARY_Z,
		"mailbox": str(root.get_meta("job_mailbox", "")), "mailbox_at": JOB_MAILBOX,
	}
	if str(street.get("sidewalk", "none")) != "none":
		opts["walk_z"] = street_z - offset
		opts["far_walk_z"] = street_z + offset
		opts["walk_width"] = walk_width
	_StreetLife.dress_block(root, lamps, back, bool(look.get("chalk", false)), block_seed, opts)

## The hood's set pieces (hood_styles.gd "set_pieces"), plus its entrance sign.
## Returns what they decided, for the art hash.
static func _set_pieces(root: Node3D, look: Dictionary, slots: Array, plans: Array, lamps: PackedVector3Array, length: float, season: int, block_seed: int, batch: RefCounted, far_y: float) -> Array:
	var hood := str(look["id"])
	var ids: Array = look.get("set_pieces", [])
	var half := length * 0.5
	var entrance := Vector3(-half + 4.0, 0.0, _Neighborhood.SIDEWALK_FAR.y + 1.4)
	var near_walk := (_Neighborhood.SIDEWALK_NEAR.x + _Neighborhood.SIDEWALK_NEAR.y) * 0.5
	var far_walk := (_Neighborhood.SIDEWALK_FAR.x + _Neighborhood.SIDEWALK_FAR.y) * 0.5
	var done: Array = []
	match hood:
		"maple_row":
			_SetPieces.entrance_sign(root, entrance, 0.0, "maple_entrance", "wooden")
		"dandelion_acres":
			_SetPieces.entrance_sign(root, entrance + Vector3(-3.0, 0.0, 1.2), 0.0, "dandelion_entrance", "arch")
			_PropCatalog.place(root, "speed_sign", Transform3D(Basis.IDENTITY, Vector3(-half + 12.0, 0.0, far_walk)), Color.WHITE, {"sign": "dandelion_speed"})
		"birchwood_commons":
			_SetPieces.entrance_sign(root, entrance, 0.0, "birchwood_entrance", "monument", Color(0.62, 0.36, 0.28))
		"oak_hollow":
			_SetPieces.entrance_sign(root, entrance, 0.0, "hoa_entrance", "monument", Color(0.84, 0.8, 0.72)).add_to_group("art_signature:hoa_sign")
			_PropCatalog.place(root, "speed_sign", Transform3D(Basis.IDENTITY, Vector3(40.0, 0.0, far_walk)), Color.WHITE, {"sign": "hoa_slow"})
		"lakeside":
			_SetPieces.entrance_sign(root, entrance, 0.0, "lakeside_entrance", "wooden")
		"mansion_hill":
			_SetPieces.entrance_sign(root, entrance + Vector3(-6.0, 0.0, 0.0), 0.0, "mansion_gate", "monument", Color(0.78, 0.74, 0.66))
			_PropCatalog.place(root, "speed_sign", Transform3D(Basis(Vector3.UP, PI), Vector3(34.0, 0.0, near_walk - 0.7)), Color.WHITE, {"sign": "mansion_private"})
	for id: String in ids:
		match id:
			"neighborhood_watch_sign":
				# On the first near-side lamp up the street from the job, the way Chefty comes in.
				var best := Vector3.INF
				for lamp: Vector3 in lamps:
					if lamp.z < 27.0 and lamp.x < -20.0 and (best == Vector3.INF or lamp.x > best.x):
						best = lamp
				if best == Vector3.INF and not lamps.is_empty():
					best = lamps[0]
				if best != Vector3.INF:
					_SetPieces.neighborhood_watch_sign(root, best)
					done.append(["watch", best.snapped(Vector3.ONE * 0.01)])
			"park_office":
				# The office and its mailbox kiosks share the far slot nearest the entrance.
				for index: int in slots.size():
					var slot: Dictionary = slots[index]
					if bool(slot["office"]):
						var x := float(slot["x"])
						_SetPieces.park_office(root, Vector3(x, 0.0, FAR_Z - 10.0), PI, hash([block_seed, "office"]))
						_SetPieces.cluster_mailboxes(root, Vector3(x + float(slot["frontage"]) * 0.5 - 3.0, 0.0, _Neighborhood.SIDEWALK_FAR.y + 1.4), 0.0, batch)
						done.append(["office", x])
			"cluster_mailboxes", "monument_sign", "summit_sign", "lakeside_sign", "entrance_arch", "power_poles", "estate_gates", "topiary_rake", "docks", "rebel_flamingo":
				pass
			"pool_sign":
				# By the first backyard pool on the block, and the new sod's own sign out front.
				for index: int in plans.size():
					var pools: Array = (plans[index] as Dictionary)["pools"]
					if pools.is_empty():
						continue
					var place: Transform3D = (slots[index] as Dictionary)["xform"]
					var at := place * ((pools[0] as Vector3) + Vector3(5.6, 0.0, 0.0))
					_SetPieces.sign_post(root, at, place.basis.get_euler().y + PI * 0.5, "birchwood_pool", Vector2(1.2, 0.7), 0.9, "white", "pool_sign")
					done.append(["pool_sign", at.snapped(Vector3.ONE * 0.01)])
					break
				_SetPieces.sign_post(root, Vector3(JOB_HALF + 4.0, 0.0, 18.4), PI, "birchwood_sod", Vector2(1.4, 0.8), 0.5, "white")
			"hoa_gatehouse":
				_SetPieces.hoa_gatehouse(root, Vector3(half - 16.0, 0.0, near_walk - 0.5))
			"hoa_rules_board":
				_SetPieces.hoa_rules_board(root, Vector3(-30.0, 0.0, near_walk - 0.6), PI)
			"lake":
				_SetPieces.lake(root, length + 80.0, Constants.ART_LAKE_SHORE_Z, Constants.ART_LAKE_LENGTH, season, block_seed)
				_SetPieces.sign_post(root, Vector3(12.0, _SetPieces.SAND_TOP, Constants.ART_LAKE_SHORE_Z + 1.6), 0.0, "lakeside_no_wake", Vector2(1.4, 0.8), 0.6, "white")
				var xs: Array = [0.0]
				for slot: Dictionary in slots:
					if slot["side"] == "near" and absf(float(slot["x"])) > 1.0:
						xs.append(float(slot["x"]))
				xs.sort()
				_SetPieces.docks_for(root, xs, Constants.ART_LAKE_SHORE_Z, block_seed, batch)
				done.append(["docks", xs.size()])
			"terrace":
				var stairs: Array = []
				for index: int in slots.size():
					var slot: Dictionary = slots[index]
					if slot["side"] != "far":
						continue
					var drive: Array = (plans[index] as Dictionary)["drive"]
					var local := Vector3(-4.6, 0.0, 0.0) if drive.size() != 2 else (drive[1] as Vector3) + Vector3(-4.6, 0.0, 0.0)
					stairs.append(((slot["xform"] as Transform3D) * local).x)
				_SetPieces.terrace(root, _Neighborhood.SIDEWALK_FAR.y + 0.3, FAR_Z + 24.0, far_y, length, stairs, batch)
				_SetPieces.sign_post(root, Vector3(18.0, 0.0, _Neighborhood.SIDEWALK_FAR.y - 0.5), 0.0, "mansion_lawn", Vector2(1.3, 0.7), 0.4, "white")
				done.append(["terrace", stairs.size()])
	return done


## Hedges or fences between the yards (the style's fence_side) at every parcel
## edge, on both sides of the street. Lakeside's long hedges run from the
## street all the way to the shore.
static func _side_boundaries(root: Node3D, look: Dictionary, slots: Array, length: float, is_job: bool, far_y: float) -> void:
	var kind := str(look.get("fence_side", "hedge"))
	if kind == "none":
		return
	var frontage := float(look["frontage"])
	var half := length * 0.5
	var edges: Array = []
	var x := JOB_HALF
	while x <= half + 0.1:
		edges.append(["near", x])
		edges.append(["near", -x])
		x += frontage
	var k := 0
	while float(k) * frontage <= half:
		edges.append(["far", float(k) * frontage])
		if k > 0:
			edges.append(["far", -float(k) * frontage])
		k += 1
	var batch := _PropBatch.new(root)
	for edge: Array in edges:
		var near: bool = edge[0] == "near"
		var ex := float(edge[1])
		var front := 19.4 if near else FAR_Z - 19.4
		var back := -20.0 if near else FAR_Z + 20.0
		if near and kind == "long_hedge":
			back = Constants.ART_LAKE_SHORE_Z
		var y := 0.0 if near else far_y
		var z_from := minf(front, back)
		var z_to := maxf(front, back)
		var run := z_to - z_from
		var middle := Vector3(ex, y, (z_from + z_to) * 0.5)
		match kind:
			"hedge", "long_hedge":
				var tall := 2.4 if kind == "long_hedge" else 1.5
				batch.add("hedge", Transform3D(Basis.IDENTITY, middle), Color(0.24, 0.42, 0.22), Vector3(1.4, tall, run))
			"boxwood":
				var pieces := maxi(1, int(run / 3.0))
				for index: int in pieces:
					batch.add("boxwood", Transform3D(Basis.IDENTITY, Vector3(ex, y, z_from + (float(index) + 0.5) * run / float(pieces))), Color.WHITE, Vector3(0.9, 0.9, 2.6))
			"privacy", "chainlink":
				var fence := "privacy_fence_run" if kind == "privacy" else "chainlink_run"
				var pieces := maxi(1, ceili(run / 6.0))
				var each := run / float(pieces)
				for index: int in pieces:
					batch.add(fence, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(ex, y, z_from + each * (float(index) + 0.5))), Color.WHITE, Vector3(snappedf(each, 0.1), 1.8 if kind == "privacy" else 1.2, 0.0))
	batch.commit()
	for view: MultiMeshInstance3D in batch.views():
		view.add_to_group("art_signature:%s" % kind)


## Trees along the far sidewalk (the style's street trees), young and staked
## where the style's trees are short (Birchwood Commons).
static func _street_trees(root: Node3D, look: Dictionary, length: float, far_y: float, rng: RandomNumberGenerator, batch: RefCounted) -> void:
	var trees: Dictionary = look.get("trees", {})
	if not bool(trees.get("street_trees", false)):
		return
	var heights: Vector2 = trees.get("height", Vector2(7.0, 9.0))
	var identical := bool(trees.get("identical", false))
	var z := _Neighborhood.SIDEWALK_FAR.y + 1.3
	var x := -length * 0.5 + Constants.ART_STREET_TREE_SPACING * 0.5
	var index := 0
	while x < length * 0.5:
		var kind := str(_HoodStyles.pick(rng, trees.get("kinds", [["broadleaf", 1]])))
		var crown := str(_HoodStyles.pick(rng, trees.get("crowns", [["orange", 1]])))
		var height := heights.x if identical else rng.randf_range(heights.x, heights.y) * 0.85
		var at := Vector3(x, far_y, z)
		_Trees.spawn(root, at, height, kind, crown, 0 if identical else index, false, 0.0 if identical else rng.randf() * TAU)
		if heights.y < 7.0:
			batch.add("staked_sapling_stakes", Transform3D(Basis.IDENTITY, at))
		x += Constants.ART_STREET_TREE_SPACING
		index += 1


## A few cars parked along the street: the far lane anywhere, the near lane only
## past where Chefty parks, never in its lane.
static func _parked_cars(look: Dictionary, length: float, rng: RandomNumberGenerator, batch: RefCounted, lane: Rect2) -> void:
	var colors: Array = look.get("car_colors", [Color(0.5, 0.5, 0.52)])
	var placed: Array[float] = []
	for index: int in Constants.ART_STREET_CARS:
		var near := index == 0
		var z := _Neighborhood.STREET.x + 1.3 if near else _Neighborhood.STREET.y - 1.3
		var from := Constants.ART_NEAR_PARKING_FROM_X + 4.0 if near else -length * 0.5 + 12.0
		var x := 0.0
		var found := false
		for _try: int in 12:
			x = rng.randf_range(from, length * 0.5 - 12.0)
			var clear := true
			for other: float in placed:
				if absf(other - x) < 9.0:
					clear = false
			if clear and not (lane.size != Vector2.ZERO and lane.grow(2.6).has_point(Vector2(x, z))):
				found = true
				break
		if not found:
			continue
		placed.append(x)
		var kind := str(_HoodStyles.pick(rng, look.get("cars", [["car_sedan", 1]])))
		# Facing the way traffic runs in its lane.
		var yaw := -PI * 0.5 if near else PI * 0.5
		batch.add(kind, Transform3D(Basis(Vector3.UP, yaw), Vector3(x, 0.0, z)), colors[rng.randi() % colors.size()])


## The block's one inflatable snowman: in a front yard near the job, block space.
static func _inflatable_spot(slots: Array, plans: Array, block_seed: int) -> Variant:
	var candidates: Array = []
	for index: int in plans.size():
		# The free front lawn only (LotBuilder's decor "front": clear of the drive,
		# the car on it and every placed prop).
		var decor: Dictionary = (plans[index] as Dictionary).get("decor", {})
		if bool(((plans[index] as Dictionary)["req"] as Dictionary)["vacant"]) or not decor.has("front"):
			continue
		candidates.append(index)
	if candidates.is_empty():
		return null
	var index: int = candidates[posmod(hash([block_seed, "inflatable"]), candidates.size())]
	var rect: Rect2 = ((plans[index] as Dictionary)["decor"] as Dictionary)["front"]
	return (slots[index] as Dictionary)["xform"] * Vector3(rect.get_center().x, 0.0, rect.get_center().y)


# ---------------------------------------------------------------- building

## The parcels, one BuildQueue step each, then the finish (levels/build_queue.gd).
static func _build_async(state: Dictionary) -> void:
	var root: Node3D = state["root"]
	var reqs: Array = state["reqs"]
	var slots: Array = state["slots"]
	for index: int in reqs.size():
		_BuildQueue.later(root, _while_built(root, func() -> void:
			# A season that turned mid-build (parcel.gd moved root.season): the rest
			# are built for it, and the ones already built turned with it.
			(reqs[index] as Dictionary)["season"] = int(root.get("season"))
			_LotBuilder.build(root, (slots[index] as Dictionary)["xform"], reqs[index])), "block parcel")
	_BuildQueue.later(root, _while_built(root, _finish.bind(state)), "block finish")


## After the last parcel: grass, the batched props and the ground, the block's
## season decor, and the metas.
static func _finish(state: Dictionary) -> void:
	var root: Node3D = state["root"]
	var look: Dictionary = state["look"]
	var batch: RefCounted = state["batch"]
	var length := float(state["length"])
	# root.season: the requested one, or the one a mid-build season turn moved it to.
	var season := int(root.get("season"))
	if bool(state["grass"]):
		_grass(root, look, state["yard"], bool(state["is_job"]), length, season, int(state["seed"]))
	batch.call("commit")
	var ground: Node3D = (state["kit"] as RefCounted).call("commit", root, "Ground")
	ground.add_to_group("street_surface")
	for view: Node in ground.get_children():
		view.add_to_group("street_surface")
	# The block's season decor, once (levels/town/parcel.gd).
	root.call("dress")
	var digest: Array = state["digest"]
	digest.append(batch.call("hash"))
	var art_hash := hash(digest)
	var spent := float(Time.get_ticks_usec() - int(state["started"])) / 1000.0
	root.set_meta("art_hash", art_hash)
	root.set_meta("parcels", (state["reqs"] as Array).size())
	root.set_meta("build_ms", spent)
	root.set_meta("art_done", true)
	var target: Node = state.get("meta_target", null)
	if target != null and is_instance_valid(target):
		target.set_meta("art_hash", art_hash)
		target.set_meta("hood_style", str(look["id"]))
		target.set_meta("art_done", true)
	print("[Art] block built in %.0f ms (%s, %d parcels)" % [spent, look["id"], (state["reqs"] as Array).size()])
	root.emit_signal("built")


## Grass across the block's lawns, clear of the street, the parcels' houses,
## drives and walks (LotBuilder marked those), the job yard's house, the lake
## and the terrace. Short where the style mows (lawn stripes), sparser in winter.
static func _grass(root: Node3D, look: Dictionary, yard: Dictionary, is_job: bool, length: float, season: int, block_seed: int) -> void:
	_Grass.keep_clear(root, Rect2(-length, _Neighborhood.SIDEWALK_NEAR.x - 0.1, length * 2.0, _Neighborhood.SIDEWALK_FAR.y - _Neighborhood.SIDEWALK_NEAR.x + 0.2))
	if str(look["id"]) == "mansion_hill":
		_Grass.keep_clear(root, Rect2(-length, _Neighborhood.SIDEWALK_FAR.y, length * 2.0, 100.0))
	if (look.get("set_pieces", []) as Array).has("lake"):
		_Grass.keep_clear(root, Rect2(-length, -400.0, length * 2.0, 400.0 + Constants.ART_BACK_BOUNDARY_Z + 0.3))
	if is_job:
		_Grass.keep_clear(root, Rect2(-2.2, 4.0, 4.4, 16.5))
		var house: Variant = yard.get("house_rect", null)
		if house is Rect2:
			_Grass.keep_clear(root, house)
		# The yard's beds, hedges, pool and the like (the lot generator's no-lawn rects).
		for rect: Variant in yard.get("clear", []):
			if rect is Rect2:
				_Grass.keep_clear(root, rect)
	var ground: Dictionary = look.get("ground", {})
	var dirt := float(ground.get("dirt", 0.0))
	var options := {
		"short": str(ground.get("surface", "grass")) == "lawn_stripes",
		"tint": Color.WHITE.lerp(Color(1.12, 1.02, 0.7), clampf(dirt, 0.0, 1.0)),
		"spacing_scale": Constants.ART_GRASS_WINTER_SPACING_SCALE if season == 1 else 1.0,
	}
	_Grass.plant(root, Constants.ART_BLOCK_GRASS_HALF, Constants.ART_BLOCK_GRASS_SPACING, block_seed, Constants.PAD_HALF if is_job else 0.0, options)
