extends RefCounted

## Dev tool, headless: checks the neighborhood builders (levels/town/: house
## requests, parcels, streets, blocks, set pieces, season dressing) the way the
## art test (art chunk 7) will, without a game running. Run by tools/mesh_check.gd
## (a CI step). For every neighborhood it builds the job's block (the slot at
## x 0 left for the yard) and checks:
## - determinism: the same hood and seed build the same art hash twice
## - signatures: every group in the style's "signature" reaches its minimum
## - the draw-call proxy: GeometryInstance3Ds under the block within
##   Constants.ART_BLOCK_MAX_VISUALS (the counts are printed)
## - Chefty's lane: nothing but the street surface inside Constants.ART_CHEFTY_LANE
##   between 0.15 m and 3 m up (MultiMesh instances one by one)
## - every house inside its parcel, every parcel's colliders and skyline boxes
## - HouseBuilder.request_for only picks archetypes the hood builds
## - every sign key a style names exists in Strings.SIGNS
## and for Maple Row in all four seasons (and Lakeside in winter): four different
## hashes, winter's decor, bare trees and frozen lake, spring's blossoms, autumn's pumpkins.

const _BlockBuilder = preload("res://levels/town/block_builder.gd")
const _LotBuilder = preload("res://levels/town/lot_builder.gd")
const _HouseBuilder = preload("res://levels/town/house_builder.gd")
const _HoodStyles = preload("res://levels/town/hood_styles.gd")
const _PropCatalog = preload("res://props/prop_catalog.gd")
const _Strings = preload("res://ui/strings.gd")

const SEED: int = 8919
const LANE_LOW: float = 0.15
const LANE_HIGH: float = 3.0


static func run() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var holder := Node3D.new()
	holder.name = "BlockCheck"
	tree.root.add_child(holder)
	var ok := _check_requests()
	ok = _check_signs() and ok
	Seasons.apply_look(Seasons.first_day_of(0))
	for hood: String in _HoodStyles.ids():
		ok = _check_hood(holder, hood) and ok
	ok = _check_seasons(holder) and ok
	Seasons.apply_look(Seasons.first_day_of(0))
	holder.queue_free()
	return ok


## request_for: job houses only from the hood's job archetypes, neighbors may
## also be its neighbors-only ones; the same seed always asks for the same house.
static func _check_requests() -> bool:
	var problems := PackedStringArray()
	for hood: String in _HoodStyles.ids():
		for index: int in 24:
			var house_seed := 1000 + index * 37
			var size := index % 3
			var job := _HouseBuilder.request_for(hood, house_seed, size)
			var stories := int(job["stories"])
			if not _HoodStyles.archetypes_for(hood, stories).has(str(job["archetype"])):
				problems.append("%s seed %d: job archetype %s" % [hood, house_seed, job["archetype"]])
			if str(job) != str(_HouseBuilder.request_for(hood, house_seed, size)):
				problems.append("%s seed %d: request_for differs on a second call" % [hood, house_seed])
			var neighbor := _HouseBuilder.request_for(hood, house_seed, size, {}, true)
			var allowed: Array = []
			for entry: Array in _HoodStyles.neighbor_archetype_weights(hood, stories):
				allowed.append(str(entry[0]))
			if not allowed.has(str(neighbor["archetype"])):
				problems.append("%s seed %d: neighbor archetype %s" % [hood, house_seed, neighbor["archetype"]])
	return _report("requests", problems, "%d hoods x 24 seeds" % _HoodStyles.ids().size())


static func _check_signs() -> bool:
	var problems := PackedStringArray()
	for hood: String in _HoodStyles.ids():
		for key: Variant in _HoodStyles.style(hood)["signs"]:
			if not _Strings.SIGNS.has(str(key)):
				problems.append("%s: no Strings.SIGNS[%s]" % [hood, key])
	for key: String in ["dandelion_mail", "birchwood_sod", "for_sale", "hoa_violation"]:
		if not _Strings.SIGNS.has(key):
			problems.append("no Strings.SIGNS[%s]" % key)
	return _report("signs", problems, "every style's sign keys")


static func _check_hood(holder: Node3D, hood: String) -> bool:
	var problems := PackedStringArray()
	var started := Time.get_ticks_msec()
	var block := _BlockBuilder.build(holder, Transform3D.IDENTITY, hood, SEED, 0, {"job": {}, "async": false})
	var spent := Time.get_ticks_msec() - started
	var again := _BlockBuilder.build(holder, Transform3D.IDENTITY, hood, SEED, 0, {"job": {}, "async": false, "grass": false})
	if not bool(block.get_meta("art_done", false)):
		problems.append("art_done never set")
	if int(block.get_meta("art_hash", 0)) == 0 or int(block.get_meta("art_hash", 0)) != int(again.get_meta("art_hash", -1)):
		problems.append("art hash %d then %d" % [int(block.get_meta("art_hash", 0)), int(again.get_meta("art_hash", -1))])
	var counts := _BlockBuilder.signature_counts(block)
	var wanted: Dictionary = _HoodStyles.style(hood)["signature"]
	for name: String in wanted:
		var group := name.trim_prefix("art_signature:")
		if int(counts.get(group, 0)) < int(wanted[name]):
			problems.append("signature %s: %d of %d" % [group, int(counts.get(group, 0)), int(wanted[name])])
	var visuals := block.find_children("*", "GeometryInstance3D", true, false).size()
	if visuals > Constants.ART_BLOCK_MAX_VISUALS:
		problems.append("%d visuals (budget %d)" % [visuals, Constants.ART_BLOCK_MAX_VISUALS])
	problems.append_array(_lane(block))
	var parcels := 0
	for node: Node in block.find_children("Parcel*", "Node3D", false, false):
		parcels += 1
		problems.append_array(_parcel(node as Node3D))
	_free(holder, again)
	_free(holder, block)
	return _report("block %-17s" % hood, problems, "%d parcels, %d visuals, built in %d ms, signatures %s" % [parcels, visuals, spent, _short(counts)])


## Every house inside its parcel; a parcel's colliders and skyline match its house.
static func _parcel(parcel: Node3D) -> PackedStringArray:
	var problems := PackedStringArray()
	var rect: Rect2 = parcel.get_meta("parcel_rect", Rect2())
	var spec: Dictionary = parcel.get_meta("house_spec", {})
	if spec.is_empty():
		return problems
	var at: Vector3 = parcel.get_meta("house_at", Vector3.ZERO)
	var footprint: Rect2 = spec.get("footprint", Rect2())
	var placed := Rect2(at.x + footprint.position.x, at.z + footprint.position.y, footprint.size.x, footprint.size.y)
	if not rect.grow(0.1).encloses(placed):
		problems.append("%s: house %s leaves the parcel %s" % [parcel.name, placed, rect])
	if parcel.get_node_or_null("House") == null:
		problems.append("%s: no House" % parcel.name)
	return problems


## Nothing but street surface in Chefty's lane between LANE_LOW and LANE_HIGH.
static func _lane(block: Node3D) -> PackedStringArray:
	var problems := PackedStringArray()
	var lane := Constants.ART_CHEFTY_LANE
	var to_block := block.global_transform.affine_inverse()
	for node: Node in block.find_children("*", "GeometryInstance3D", true, false):
		if node.is_in_group("street_surface") or node is Label3D:
			continue
		var view := node as GeometryInstance3D
		var place := to_block * view.global_transform
		var boxes: Array[AABB] = []
		if view is MultiMeshInstance3D:
			var multi := (view as MultiMeshInstance3D).multimesh
			if multi == null or multi.mesh == null:
				continue
			var box: AABB = multi.mesh.get_meta("aabb", multi.mesh.get_aabb())
			# The dummy renderer forgets instance transforms; PropBatch keeps a copy.
			var xforms: Array = view.get_meta("instance_xforms", [])
			if xforms.is_empty():
				for index: int in multi.instance_count:
					xforms.append(multi.get_instance_transform(index))
			for xform: Transform3D in xforms:
				boxes.append(place * xform * box)
		elif view is MeshInstance3D and (view as MeshInstance3D).mesh != null:
			boxes.append(place * (view as MeshInstance3D).mesh.get_aabb())
		for box: AABB in boxes:
			var flat := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
			if flat.intersects(lane) and box.position.y < LANE_HIGH and box.end.y > LANE_LOW:
				problems.append("in Chefty's lane: %s (%s)" % [block.get_path_to(view), box])
				break
		if problems.size() >= 6:
			break
	return problems


static func _check_seasons(holder: Node3D) -> bool:
	var problems := PackedStringArray()
	var hashes := {}
	for season: int in 4:
		Seasons.apply_look(Seasons.first_day_of(season))
		if Seasons.current() != season:
			problems.append("Seasons.current() %d, want %d" % [Seasons.current(), season])
		var block := _BlockBuilder.build(holder, Transform3D.IDENTITY, "maple_row", 1000, season, {"job": {}, "async": false, "grass": false})
		hashes[int(block.get_meta("art_hash", 0))] = true
		# Each season's decor (winter's snowbanks along the curbs) keeps out of Chefty's lane too.
		problems.append_array(_lane(block))
		var counts := _BlockBuilder.signature_counts(block)
		var forms := {}
		var crowns := {}
		for tree: Node in block.find_children("Tree*", "Node3D", true, false):
			forms[str(tree.get_meta("form", ""))] = true
			crowns[str(tree.get_meta("crown", ""))] = true
		match season:
			0:
				if int(counts.get("pumpkin", 0)) < 1:
					problems.append("autumn: no pumpkins")
			1:
				if int(counts.get("season_winter", 0)) < 3:
					problems.append("winter: %d season_winter nodes" % int(counts.get("season_winter", 0)))
				if not forms.has("bare"):
					problems.append("winter: no bare tree (%s)" % ",".join(PackedStringArray(forms.keys())))
			2:
				if not crowns.has("blossom_pink") and not crowns.has("blossom_white"):
					problems.append("spring: no blossom (%s)" % ",".join(PackedStringArray(crowns.keys())))
		_free(holder, block)
	if hashes.size() != 4:
		problems.append("4 seasons gave %d art hashes" % hashes.size())
	# The lake freezes in winter.
	Seasons.apply_look(Seasons.first_day_of(1))
	var lake_block := _BlockBuilder.build(holder, Transform3D.IDENTITY, "lakeside", 1000, 1, {"job": {}, "async": false, "grass": false})
	var water := lake_block.get_node_or_null("Lake/Water")
	if water == null or str(water.get_meta("water_kind", "")) != "frozen":
		problems.append("lakeside winter: lake water %s" % (water.get_meta("water_kind", "") if water != null else "missing"))
	_free(holder, lake_block)
	return _report("seasons", problems, "maple_row x 4 seasons, lakeside in winter")


static func _free(holder: Node3D, node: Node) -> void:
	holder.remove_child(node)
	node.free()


static func _short(counts: Dictionary) -> String:
	var parts := PackedStringArray()
	for key: String in counts:
		if not key.begins_with("house_") and not key.begins_with("season_"):
			parts.append("%s %d" % [key, int(counts[key])])
	return ", ".join(parts)


static func _report(label: String, problems: PackedStringArray, summary: String) -> bool:
	var ok := problems.is_empty()
	print("[BlockCheck] %s %s  %s" % [label, "ok  " if ok else "FAIL", summary])
	for problem: String in problems.slice(0, 10):
		print("[BlockCheck]   %s" % problem)
	return ok
