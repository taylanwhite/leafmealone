extends Node

## Authority: host (the sweep); every peer reports its own lot_art
## (net/dev/probe.gd). --art-test checks that every neighborhood looks like
## itself in the running game (gap-specs/art.json, art chunk 7), the in-game
## twin of tools/block_check.gd. Run as: host --start-zone=lot --job-seed=777
## --hood=lakeside --start-day=8 --legacy-map --art-test, a client joined after
## 3 s. Like --layout-test it frees and loads yards one after another
## (options job_seed, yard_size, hood, all_tasks; world._free_lot and
## _load_job_lot) and waits for each yard and its street block (lot meta
## art_done). It covers:
## - every hood at every size on SWEEP_SEED, and the yard plus block checks:
##   A1 the hood's style, never the fallback; A2 one of its archetypes;
##   A3 its signatures (hood_styles.gd "signature") under the lot;
##   A5 layout_test.gd's _check (no solid in a solid, nothing buried, beds off
##   the front walk); A6 the house contract (layout_test.gd's _check_house plus
##   the roof's full leaf count); A8 the draw-call proxy (GeometryInstance3Ds
##   under the Block and the yard's Dressing within ART_BLOCK_MAX_VISUALS and
##   ART_YARD_MAX_VISUALS; the most per hood are reported); A9 batching (at
##   least MIN_MULTIMESHES MultiMeshes per block, MIN_BATCHED_SHARE of simple
##   props drawn by one); A13 nothing but street surface in Chefty's lane
##   (Constants.ART_CHEFTY_LANE, the legacy lot's curb; critic C24)
## - A4 every hood's fingerprint (archetypes, fences, street, mailbox, ground)
##   differs from every other's
## - A7 budgets: every catalog prop, every archetype at the largest yard house,
##   every tree kind x crown x season near and far
## - A10 every hood's TWICE_SEED yard built twice: the same art and layout hash
## - A11 Maple Row's big yard in all four seasons (and Lakeside in winter): four
##   art hashes, Seasons.current() each time, winter's decor, bare trees and
##   frozen lake, spring's blossoms, autumn's pumpkins, A13 on the block and the
##   yard in every season (leafy crowns over the street), and the job house's own
##   decor (pumpkins on its steps and mums pots inside its beds, a wreath on its
##   door, a tulip bed per bed, a pool float and a pinwheel; never string lights)
## - A12 the words: every sign key a style or set piece names exists, and no
##   sign, boat name, aisle or label on a built block trips the guardrail
##   (net/dev/guardrail.gd) or the art wording rule (no "ice" at all: SNOW-B-GONE)
## Then it loads the configured yard again (the day's real season) and waits
## CLIENT_SETTLE_SECONDS, so CI can compare the host's lot_art with the client's.
## - A14 Homie Depot (art chunk 8): no solid of the store's dressing within
##   STORE_COUNTER_CLEAR of the counter, STORE_COT_CLEAR of a cot, STORE_SPAWN_CLEAR
##   of a spawn or STORE_PAD_CLEAR of Chefty's pad; every piece art added on the
##   lot (group store_art_solid) inside an "art" reservation of
##   Constants.STORE_LAYOUT, so none lands on a shop's or driving's; the lobby's
##   floor (STORE_LOBBY_POINT) open, and a box as wide as four players abreast
##   (STORE_CREW_WIDTH) swept from the lot through the doors down the lobby
##   without touching a thing; a ShelfSlot marker per tool, the lobby's stock
##   standing every tool in one, each slot's front open and inside the shop's
##   "lobby"; the sliding doors there.

const _HoodStyles = preload("res://levels/town/hood_styles.gd")
const _BlockBuilder = preload("res://levels/town/block_builder.gd")
const _HouseBuilder = preload("res://levels/town/house_builder.gd")
const _Archetypes = preload("res://levels/town/house_archetypes.gd")
const _PropCatalog = preload("res://props/prop_catalog.gd")
const _Trees = preload("res://props/trees.gd")
const _Strings = preload("res://ui/strings.gd")
const _LayoutTest = preload("res://net/dev/layout_test.gd")
const _Guardrail = preload("res://net/dev/guardrail.gd")

const SWEEP_SEED: int = 1000
const TWICE_SEED: int = 8919
const SEASON_HOOD: String = "maple_row"
## How long a yard and its block may take to build before the test gives up on it.
const BUILD_WAIT_FRAMES: int = 900
## After the last yard is built, how long the host waits before reporting, so a
## client has built the same yard and block too.
const CLIENT_SETTLE_SECONDS: float = 4.0
const MIN_MULTIMESHES: int = 3
const MIN_BATCHED_SHARE: float = 0.6
const LANE_LOW: float = 0.15
const LANE_HIGH: float = 3.0
## The art wording rule (docs/GAME.md): no "ice" anywhere in art text, any case
## (the guardrail itself only bans the acronym), and no agency initials.
const ART_WORDS: String = "(?i)\\b(ice|cbp|dhs|fbi|atf)\\b"
## Sign keys the set pieces and block builder use besides the styles' "signs".
const SET_PIECE_SIGNS: Array[String] = [
	"watch_maple", "hoa_gate", "hoa_rules", "hoa_violation", "dandelion_office", "dandelion_mail",
	"dandelion_speed", "hoa_slow", "mansion_private", "birchwood_pool", "birchwood_sod",
	"lakeside_no_wake", "mansion_lawn",
]

## A14: how far (m) the store dressing's solids keep from the counter, a cot, a
## spawn and Chefty's pad; a point on the lobby's floor; and the walk-in sweep:
## a box this wide (four players abreast) from STORE_SWEEP_FROM to STORE_SWEEP_TO.
const STORE_COUNTER_CLEAR: float = 2.5
const STORE_COT_CLEAR: float = 1.2
const STORE_SPAWN_CLEAR: float = 1.5
const STORE_PAD_CLEAR: float = 4.0
const STORE_LOBBY_POINT := Vector3(-16.0, 0.5, -2.0)
const STORE_CREW_WIDTH: float = 4.4
const STORE_SWEEP_FROM := Vector3(-6.0, 1.0, -2.0)
const STORE_SWEEP_TO := Vector3(-16.8, 1.0, -2.0)

static var result: Dictionary = {}

var _started: bool = false
var _layout: Node
var _words := RegEx.new()
## The most GeometryInstance3Ds any build had under its Block and its Dressing: [count, which].
var _most := {"block": [0, ""], "yard": [0, ""]}


func _process(_delta: float) -> void:
	if _started or not Net.is_host() or get_tree().get_first_node_in_group("job_lot") == null:
		return
	_started = true
	_words.compile(ART_WORDS)
	_layout = _LayoutTest.new()
	_run()


func _exit_tree() -> void:
	if _layout != null:
		_layout.free()
		_layout = null


func _run() -> void:
	var world := get_tree().get_first_node_in_group("world")
	var options := Net.dev_options()
	var had := {
		"hood": str(options.get("hood")), "job_seed": int(options.get("job_seed")),
		"yard_size": int(options.get("yard_size")), "all_tasks": bool(options.get("all_tasks")),
	}
	var problems: Array[String] = []
	var hoods := {}
	var yards := 0
	var started := Time.get_ticks_msec()
	# What needs no yard: budgets and words, and Homie Depot.
	problems.append_array(_budgets())
	problems.append_array(_strings())
	problems.append_array(_store(world))
	# Every hood at every size.
	for hood: String in _HoodStyles.ids():
		hoods[hood] = {"archetypes": {}, "fences": {}, "street": "", "mailbox": {}, "ground": {}, "max_visuals_block": 0, "max_visuals_yard": 0, "signatures": {}, "build_ms": 0.0}
		for size: int in 3:
			var label := "%s size %d seed %d" % [hood, size, SWEEP_SEED]
			var lot := await _load(world, hood, SWEEP_SEED, size)
			yards += 1
			problems.append_array(_check_yard(lot, hood, label, hoods[hood]))
	problems.append_array(_distinct(hoods))
	# Determinism: the same hood, seed and season twice.
	for hood: String in _HoodStyles.ids():
		var first := await _load(world, hood, TWICE_SEED, 1)
		var hashes := _hashes(first)
		var second := await _load(world, hood, TWICE_SEED, 1)
		yards += 2
		if hashes.is_empty() or hashes != _hashes(second):
			problems.append("A10 %s seed %d: built twice, hashes %s then %s" % [hood, TWICE_SEED, hashes, _hashes(second)])
	# The seasons.
	var seasons := await _seasons(world)
	problems.append_array(seasons[0])
	yards += int(seasons[1])
	# Back to the day's own look and the configured yard, for the client comparison.
	var clock := get_tree().get_first_node_in_group("day_clock")
	Seasons.apply_look(int(clock.get("day")) if clock != null else 1)
	for key: String in had:
		options.set(key, had[key])
	var final := await _load_configured(world)
	# A8 over every build, the seasons' decor included.
	if int(_most["block"][0]) > Constants.ART_BLOCK_MAX_VISUALS:
		problems.append("A8 %s: the block has %d visuals (budget %d)" % [_most["block"][1], _most["block"][0], Constants.ART_BLOCK_MAX_VISUALS])
	if int(_most["yard"][0]) > Constants.ART_YARD_MAX_VISUALS:
		problems.append("A8 %s: the yard has %d visuals (budget %d)" % [_most["yard"][1], _most["yard"][0], Constants.ART_YARD_MAX_VISUALS])
	var lot_art := int(final.get_meta("art_hash", 0)) if final != null else 0
	if lot_art == 0:
		problems.append("the configured yard never finished its art")
	for line: String in problems:
		print("[ArtTest] %s" % line)
	var report := {}
	for hood: String in hoods:
		var entry: Dictionary = hoods[hood]
		report[hood] = {
			"archetypes": PackedStringArray(entry["archetypes"].keys()), "fences": PackedStringArray(entry["fences"].keys()),
			"street": entry["street"], "max_visuals_block": entry["max_visuals_block"],
			"max_visuals_yard": entry["max_visuals_yard"], "signatures": entry["signatures"],
			"build_ms": snappedf(float(entry["build_ms"]), 1.0),
		}
		print("[ArtTest] %-17s archetypes %s, block visuals up to %d, yard visuals up to %d, block built in up to %.0f ms" % [hood, ",".join(report[hood]["archetypes"]), entry["max_visuals_block"], entry["max_visuals_yard"], float(entry["build_ms"])])
	print("[ArtTest] the most visuals of any build: block %d (%s, budget %d), yard %d (%s, budget %d)" % [_most["block"][0], _most["block"][1], Constants.ART_BLOCK_MAX_VISUALS, _most["yard"][0], _most["yard"][1], Constants.ART_YARD_MAX_VISUALS])
	await get_tree().create_timer(CLIENT_SETTLE_SECONDS).timeout
	var ok := problems.is_empty()
	result = {"ok": ok, "yards": yards, "hoods": report, "most_visuals": _most.duplicate(true), "problems": problems.slice(0, 40), "problem_count": problems.size(), "lot_art": lot_art, "seconds": float(Time.get_ticks_msec() - started) / 1000.0, "error": "" if ok else problems[0], "done": true}
	print("[ArtTest] %d yards in %.0f s, %d problems, all ok: %s" % [yards, result["seconds"], problems.size(), ok])


# ---------------------------------------------------------------- loading

## Frees the yard and loads hood's seed_value at size with every task; waits
## for the yard, its street block (lot meta art_done) and its colliders.
func _load(world: Node, hood: String, seed_value: int, size: int) -> Node3D:
	var options := Net.dev_options()
	options.set("hood", hood)
	options.set("job_seed", seed_value)
	options.set("yard_size", size)
	options.set("all_tasks", true)
	return await _reload(world)


## The yard the run was started with (its --hood, --job-seed and --yard-size).
func _load_configured(world: Node) -> Node3D:
	return await _reload(world)


func _reload(world: Node) -> Node3D:
	world.call("_free_lot")
	await get_tree().physics_frame
	await get_tree().physics_frame
	world.call("_load_job_lot")
	var lot := get_tree().get_first_node_in_group("job_lot") as Node3D
	var waited := 0
	while waited < BUILD_WAIT_FRAMES and (lot == null or not bool(lot.get("is_generated")) or not bool(lot.get_meta("art_done", false))):
		await get_tree().process_frame
		lot = get_tree().get_first_node_in_group("job_lot") as Node3D
		waited += 1
	# Colliders register on the next physics step.
	await get_tree().physics_frame
	await get_tree().physics_frame
	# The most visuals any build had (seasons included), for setting the budgets.
	if lot != null and lot.get_node_or_null("Block") != null and lot.get_node_or_null("Dressing") != null:
		var label := "%s size %d seed %d %s" % [lot.get("hood"), int(lot.get("yard_size")), int(lot.get("job_seed")), Seasons.IDS[Seasons.current()]]
		var block := lot.get_node("Block").find_children("*", "GeometryInstance3D", true, false).size()
		var yard := lot.get_node("Dressing").find_children("*", "GeometryInstance3D", true, false).size()
		if block > int(_most["block"][0]):
			_most["block"] = [block, label]
		if yard > int(_most["yard"][0]):
			_most["yard"] = [yard, label]
	return lot


func _hashes(lot: Node3D) -> Array:
	if lot == null or not bool(lot.get_meta("art_done", false)):
		return []
	return [int(lot.get_meta("art_hash", 0)), int(lot.get_meta("layout_hash", 0)), int(lot.get_meta("yard_art_hash", 0))]


# ---------------------------------------------------------------- one yard

func _check_yard(lot: Node3D, hood: String, label: String, seen: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if lot == null or not bool(lot.get_meta("art_done", false)):
		out.append("%s: the yard or its block never finished" % label)
		return out
	var look := _HoodStyles.style(hood)
	# A1, A2 and most of A6 are layout_test's house contract; A5 its yard checks.
	if bool(look["fallback"]):
		out.append("A1 %s: %s has no style of its own" % [label, hood])
	for line: String in _layout.call("_check_house", lot, hood, label):
		out.append("A1/A2/A6 %s" % line)
	for line: String in _layout.call("_check", lot, label):
		out.append("A5 %s" % line)
	out.append_array(_roof_count(lot, label))
	var block := lot.get_node_or_null("Block") as Node3D
	var dressing := lot.get_node_or_null("Dressing") as Node3D
	if block == null or dressing == null:
		out.append("%s: no Block or Dressing" % label)
		return out
	# A3 signatures, under the whole lot (the yard's house counts too).
	var counts := _BlockBuilder.signature_counts(lot)
	var wanted: Dictionary = look.get("signature", {})
	for name: String in wanted:
		var group := name.trim_prefix("art_signature:")
		var have := int(counts.get(group, 0))
		seen["signatures"][group] = maxi(int(seen["signatures"].get(group, 0)), have)
		if have < int(wanted[name]):
			out.append("A3 %s: signature %s %d of %d" % [label, group, have, int(wanted[name])])
	# A8 the draw-call proxy.
	var block_visuals := block.find_children("*", "GeometryInstance3D", true, false).size()
	var yard_visuals := dressing.find_children("*", "GeometryInstance3D", true, false).size()
	seen["max_visuals_block"] = maxi(int(seen["max_visuals_block"]), block_visuals)
	seen["max_visuals_yard"] = maxi(int(seen["max_visuals_yard"]), yard_visuals)
	seen["build_ms"] = maxf(float(seen["build_ms"]), float(block.get_meta("build_ms", 0.0)))
	if block_visuals > Constants.ART_BLOCK_MAX_VISUALS:
		out.append("A8 %s: the block has %d visuals (budget %d)" % [label, block_visuals, Constants.ART_BLOCK_MAX_VISUALS])
	if yard_visuals > Constants.ART_YARD_MAX_VISUALS:
		out.append("A8 %s: the yard has %d visuals (budget %d)" % [label, yard_visuals, Constants.ART_YARD_MAX_VISUALS])
	# A9 batching.
	out.append_array(_batching(lot, block, label))
	# A13 Chefty's lane.
	out.append_array(_lane(lot, block, label))
	out.append_array(_lane(lot, dressing, label))
	# The job house's own decor, and the words on everything built.
	out.append_array(_job_decor(dressing, Seasons.current(), label))
	out.append_array(_labels(lot, label))
	# The fingerprint (A4).
	seen["archetypes"][str(lot.get_meta("archetype", ""))] = true
	seen["fences"][str((look.get("job_fence", {}) as Dictionary).get("kind", ""))] = true
	seen["fences"][str(look.get("fence_side", ""))] = true
	if dressing.find_children("FencePanel*", "Node3D", false, false).is_empty():
		out.append("A4 %s: the yard has no fence panels" % label)
	var street: Dictionary = look.get("street", {})
	seen["street"] = "%s/%s" % [street.get("surface", ""), street.get("lines", "")]
	if not _has_street(block):
		out.append("A4 %s: the block has no street surface" % label)
	seen["mailbox"][str(block.get_meta("job_mailbox", ""))] = true
	var ground := lot.get_node_or_null("Floor/Mesh")
	if ground != null:
		seen["ground"][(ground.get_meta("surface_base", Color.BLACK) as Color).to_html()] = true
	return out


## A6: the roof has its whole grid of leaves, 2 rows x max(2, int(width / 2.2))
## columns x 2 slopes (a spot a dormer takes slides elsewhere on the roof).
func _roof_count(lot: Node3D, label: String) -> Array[String]:
	var out: Array[String] = []
	var house := lot.get_node_or_null("Dressing/House") as Node3D
	var tasks := lot.get_node_or_null("JobTasks")
	if house == null or tasks == null:
		return out
	var spec: Dictionary = house.get_meta("house_spec", {})
	var want := 4 * maxi(2, int(float(spec.get("width", 0.0)) / 2.2))
	var have := 0
	for index: int in int(tasks.call("spot_count")):
		if str((tasks.call("spot", index) as Dictionary)["task"]) == "clear_roof":
			have += 1
	if have != want:
		out.append("A6 %s: %d roof leaves, want %d" % [label, have, want])
	return out


## A9: the block draws its props through MultiMeshes.
func _batching(lot: Node3D, block: Node3D, label: String) -> Array[String]:
	var out: Array[String] = []
	var multis := block.find_children("*", "MultiMeshInstance3D", true, false)
	if multis.size() < MIN_MULTIMESHES:
		out.append("A9 %s: %d MultiMeshes in the block (at least %d)" % [label, multis.size(), MIN_MULTIMESHES])
	var batched := 0
	var single := 0
	for node: Node in lot.find_children("*", "GeometryInstance3D", true, false):
		if not node.has_meta("prop_kind") or not _PropCatalog.is_simple(str(node.get_meta("prop_kind"))):
			continue
		if node is MultiMeshInstance3D:
			batched += int(node.get_meta("prop_instances", 1))
		elif node is MeshInstance3D:
			single += 1
	var share := float(batched) / float(maxi(batched + single, 1))
	if share < MIN_BATCHED_SHARE:
		out.append("A9 %s: %d of %d simple props batched (%.0f%%, want %.0f%%)" % [label, batched, batched + single, share * 100.0, MIN_BATCHED_SHARE * 100.0])
	return out


## A13: nothing but the street surface (group street_surface) and words inside
## Chefty's lane between LANE_LOW and LANE_HIGH, in the lot's space.
func _lane(lot: Node3D, root: Node3D, label: String) -> Array[String]:
	var out: Array[String] = []
	var lane := Constants.ART_CHEFTY_LANE
	var to_lot := lot.global_transform.affine_inverse()
	for node: Node in root.find_children("*", "GeometryInstance3D", true, false):
		if node.is_in_group("street_surface") or node is Label3D:
			continue
		var view := node as GeometryInstance3D
		var place := to_lot * view.global_transform
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
				# A tree's box is coarse (it runs from its roots to its crown's top,
				# and a leafy crown over the street is fine above the truck): a tree's
				# mesh only counts when a vertex of it is in the lane, low. Anything
				# else counts by its box (a rail or fence run crossing the lane with
				# every vertex outside it still blocks Chefty).
				var low := box.position.y
				if _is_tree(view):
					low = _lowest_in_lane(view as MeshInstance3D, place, lane)
				if is_inf(low):
					continue
				out.append("A13 %s: in Chefty's lane: %s (%s, %.2f m up)" % [label, lot.get_path_to(view), box, low])
				break
		if out.size() >= 4:
			break
	return out


## Whether view is a tree's near or far mesh ("Look"/"LookFar" under a
## props/tree_node.gd, which carries metas form and crown; props/trees.gd spawn).
func _is_tree(view: GeometryInstance3D) -> bool:
	if not view is MeshInstance3D or (view as MeshInstance3D).mesh == null:
		return false
	var parent := view.get_parent()
	return parent != null and parent.has_meta("form") and parent.has_meta("crown") and (view.name == "Look" or view.name == "LookFar")


## The height of the lowest vertex of view's mesh inside lane between LANE_LOW
## and LANE_HIGH (place: the view's transform in the lot), or INF when none is.
func _lowest_in_lane(view: MeshInstance3D, place: Transform3D, lane: Rect2) -> float:
	var lowest := INF
	var mesh := view.mesh
	for surface: int in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array:
			var at := place * vertex
			if at.y > LANE_LOW and at.y < LANE_HIGH and lane.has_point(Vector2(at.x, at.z)):
				lowest = minf(lowest, at.y)
	return lowest


## The job house's season decor (levels/lots/lot_generator.gd _season_decor):
## there, in its season, only on the porch, beds and drive, never string lights.
func _job_decor(dressing: Node3D, season: int, label: String) -> Array[String]:
	var out: Array[String] = []
	var holder := dressing.get_node_or_null("JobDecor")
	if holder == null or holder.get_node_or_null("SeasonDecor") == null:
		out.append("%s: the job house has no season decor" % label)
		return out
	if int(holder.get("season")) != season:
		out.append("%s: the job house is decorated for season %d, the look is %d" % [label, int(holder.get("season")), season])
	if not holder.find_children("*", "StaticBody3D", true, false).is_empty():
		out.append("%s: the job house's decor has a collider" % label)
	var kinds := {}
	for node: Node in holder.find_children("*", "", true, false):
		if node.has_meta("prop_kind"):
			kinds[str(node.get_meta("prop_kind"))] = int(kinds.get(str(node.get_meta("prop_kind")), 0)) + int(node.get_meta("prop_instances", 1))
	if kinds.has("string_lights"):
		out.append("%s: string lights on the job house (a future hang-lights task owns those)" % label)
	var beds: Array = dressing.get_meta("bed_rects", [])
	var pool: Variant = dressing.get("_pool_at")
	var has_pool: bool = pool is Vector3 and pool != Vector3.INF
	match season:
		0:
			if int(kinds.get("pumpkin", 0)) + int(kinds.get("pumpkin_small", 0)) + int(kinds.get("pumpkin_big", 0)) < 2:
				out.append("%s: autumn, but no pumpkins on the job house's steps (%s)" % [label, kinds])
			# Each mums pot stands inside a bed, clear of its edges (the tires, the
			# edging and the mowed lawn are all outside).
			var pots := _instances(dressing, holder, "mums_pot")
			if pots.size() > beds.size():
				out.append("%s: %d mums pots for %d beds" % [label, pots.size(), beds.size()])
			for at: Vector3 in pots:
				var inside := false
				for bed: Rect2 in beds:
					if bed.grow(-0.25).has_point(Vector2(at.x, at.z)):
						inside = true
				if not inside:
					out.append("%s: a mums pot at %s is not inside a bed (%s)" % [label, at, beds])
		1:
			if not kinds.has("wreath"):
				out.append("%s: winter, but no wreath on the job house's door (%s)" % [label, kinds])
		2:
			if int(kinds.get("tulip_bed", 0)) != beds.size():
				out.append("%s: spring, %d tulip beds for %d beds (%s)" % [label, int(kinds.get("tulip_bed", 0)), beds.size(), kinds])
		3:
			if int(kinds.get("pool_float", 0)) != (1 if has_pool else 0):
				out.append("%s: summer, %d pool floats, pool %s (%s)" % [label, int(kinds.get("pool_float", 0)), has_pool, kinds])
			if int(kinds.get("pinwheel", 0)) != (0 if beds.is_empty() else 1):
				out.append("%s: summer, %d pinwheels for %d beds (%s)" % [label, int(kinds.get("pinwheel", 0)), beds.size(), kinds])
	for kind: String in ["snowman", "sled", "hay_bale", "scarecrow", "sprinkler", "beach_umbrella", "lemonade_stand"]:
		if kinds.has(kind):
			out.append("%s: a %s on the job yard's lawn, where the work is" % [label, kind])
	return out


## Where every prop of kind under holder stands, in dressing's space (batched
## instances through their instance_xforms, single props by their own place).
func _instances(dressing: Node3D, holder: Node, kind: String) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var to_dressing := dressing.global_transform.affine_inverse()
	for node: Node in holder.find_children("*", "Node3D", true, false):
		if str(node.get_meta("prop_kind", "")) != kind:
			continue
		var place := to_dressing * (node as Node3D).global_transform
		if node is MultiMeshInstance3D:
			for xform: Transform3D in node.get_meta("instance_xforms", []):
				out.append(place * xform.origin)
		else:
			out.append(place.origin)
	return out


## A12 at run time: every label on the built block and yard has words, and
## none trips the guardrail or the art wording rule.
func _labels(lot: Node3D, label: String) -> Array[String]:
	var out: Array[String] = []
	for node: Node in lot.find_children("*", "Label3D", true, false):
		var text := (node as Label3D).text
		if text.strip_edges().is_empty():
			continue
		for hit: String in _Guardrail.check(text):
			out.append("A12 %s: %s on %s" % [label, hit, lot.get_path_to(node)])
		if _words.search(text) != null:
			out.append("A12 %s: '%s' on %s breaks the art wording rule" % [label, text.replace("\n", " "), lot.get_path_to(node)])
	return out


func _has_street(block: Node3D) -> bool:
	for node: Node in block.find_children("*", "", true, false):
		if node.is_in_group("street_surface") and node is GeometryInstance3D:
			return true
	return false


# ---------------------------------------------------------------- across hoods

## A4: no two hoods share a fingerprint.
func _distinct(hoods: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var prints := {}
	for hood: String in hoods:
		var entry: Dictionary = hoods[hood]
		var parts: Array = []
		for key: String in ["archetypes", "fences", "mailbox", "ground"]:
			var keys: Array = (entry[key] as Dictionary).keys()
			keys.sort()
			parts.append(keys)
		parts.append(entry["street"])
		prints[hood] = str(parts)
	var ids: Array = prints.keys()
	for a: int in ids.size():
		for b: int in range(a + 1, ids.size()):
			if prints[ids[a]] == prints[ids[b]]:
				out.append("A4 %s and %s look the same: %s" % [ids[a], ids[b], prints[ids[a]]])
	return out


## A11: Maple Row in every season, then Lakeside in winter. Returns [problems, yards].
func _seasons(world: Node) -> Array:
	var out: Array[String] = []
	var hashes := {}
	var yards := 0
	for season: int in 4:
		Seasons.apply_look(Seasons.first_day_of(season))
		if Seasons.current() != season:
			out.append("A11 Seasons.current() %d, want %d" % [Seasons.current(), season])
		# The big yard: it has the pool the summer float rides on.
		var lot := await _load(world, SEASON_HOOD, SWEEP_SEED, 2)
		yards += 1
		var label := "%s %s" % [SEASON_HOOD, Seasons.IDS[season]]
		if lot == null or not bool(lot.get_meta("art_done", false)):
			out.append("A11 %s: never finished" % label)
			continue
		hashes[int(lot.get_meta("art_hash", 0))] = true
		var counts := _BlockBuilder.signature_counts(lot)
		var forms := {}
		var crowns := {}
		for tree: Node in lot.find_children("Tree*", "Node3D", true, false):
			forms[str(tree.get_meta("form", ""))] = true
			crowns[str(tree.get_meta("crown", ""))] = true
		match season:
			0:
				if int(counts.get("pumpkin", 0)) < 1:
					out.append("A11 %s: no pumpkins" % label)
			1:
				if int(counts.get("season_winter", 0)) < 3:
					out.append("A11 %s: %d season_winter nodes" % [label, int(counts.get("season_winter", 0))])
				if not forms.has("bare"):
					out.append("A11 %s: no bare tree (%s)" % [label, ",".join(PackedStringArray(forms.keys()))])
			2:
				if not crowns.has("blossom_pink") and not crowns.has("blossom_white"):
					out.append("A11 %s: no blossoms (%s)" % [label, ",".join(PackedStringArray(crowns.keys()))])
		out.append_array(_job_decor(lot.get_node("Dressing") as Node3D, season, "A11 " + label))
		# The leafy seasons' crowns too (CI's main sweep runs in winter).
		out.append_array(_lane(lot, lot.get_node("Block") as Node3D, label))
		out.append_array(_lane(lot, lot.get_node("Dressing") as Node3D, label))
	if hashes.size() != 4:
		out.append("A11 four seasons gave %d art hashes" % hashes.size())
	Seasons.apply_look(Seasons.first_day_of(1))
	var lake := await _load(world, "lakeside", SWEEP_SEED, 1)
	yards += 1
	var water := lake.get_node_or_null("Block/Lake/Water") if lake != null else null
	if water == null or str(water.get_meta("water_kind", "")) != "frozen":
		out.append("A11 lakeside winter: the lake is %s" % (water.get_meta("water_kind", "") if water != null else "missing"))
	return [out, yards]


# ---------------------------------------------------------------- tables

## A14: Homie Depot's dressing (levels/dressing/store_dressing.gd and
## store_interior.gd, art chunk 8). See the header.
func _store(world: Node) -> Array[String]:
	var out: Array[String] = []
	var zone := world.get_node_or_null("StoreZone") as Node3D
	var dressing := zone.get_node_or_null("Dressing") as Node3D if zone != null else null
	if dressing == null:
		return ["A14 no StoreZone/Dressing"]
	var to_zone := zone.global_transform.affine_inverse()
	var keep_from: Array = [[Constants.SHOP_SITES["homie_depot"]["counter"], STORE_COUNTER_CLEAR, "the counter"]]
	for spot: Vector3 in Constants.COT_SPOTS:
		keep_from.append([spot, STORE_COT_CLEAR, "a cot"])
	var spawns := zone.get_node_or_null("StoreSpawnPoints")
	if spawns != null:
		for spawn: Node in spawns.get_children():
			keep_from.append([(spawn as Node3D).position, STORE_SPAWN_CLEAR, "a spawn"])
	var pad := zone.get_node_or_null("TruckPad") as Node3D
	if pad != null:
		keep_from.append([pad.position, STORE_PAD_CLEAR, "Chefty's pad"])
	var solids := 0
	for shape: Node in dressing.find_children("*", "CollisionShape3D", true, false):
		if not (shape.get_parent() is StaticBody3D):
			continue
		var footprint := _footprint(shape as CollisionShape3D, to_zone)
		if footprint.size == Vector2.ZERO:
			continue
		solids += 1
		for keep: Array in keep_from:
			var at: Vector3 = keep[0]
			var spot := Vector2(at.x, at.z)
			var nearest := Vector2(clampf(spot.x, footprint.position.x, footprint.end.x), clampf(spot.y, footprint.position.y, footprint.end.y))
			if nearest.distance_to(spot) < float(keep[1]):
				out.append("A14 %s is %.2f m from %s (needs %.1f)" % [dressing.get_path_to(shape.get_parent()), nearest.distance_to(spot), keep[2], float(keep[1])])
	# Art's pieces stand in art's reservations, so they never land on anyone else's.
	var art_rects: Array[Rect2] = []
	for key: Variant in Constants.STORE_LAYOUT:
		var entry: Dictionary = Constants.STORE_LAYOUT[key]
		if str(entry["owner"]) == "art":
			art_rects.append((entry["rect"] as Rect2).grow(0.05))
	var pieces := 0
	for body: Node in get_tree().get_nodes_in_group("store_art_solid"):
		if not dressing.is_ancestor_of(body):
			continue
		for shape: Node in body.get_children():
			if not (shape is CollisionShape3D):
				continue
			pieces += 1
			var footprint := _footprint(shape as CollisionShape3D, to_zone)
			if not art_rects.any(func(rect: Rect2) -> bool: return rect.encloses(footprint)):
				out.append("A14 %s (%s) is outside art's reservations" % [dressing.get_path_to(body), footprint])
	if pieces < 20:
		out.append("A14 only %d art pieces on the lot" % pieces)
	# The lobby: open floor, and four abreast walk in from the lot without a bump.
	var space := zone.get_world_3d().direct_space_state
	var probe := PhysicsPointQueryParameters3D.new()
	probe.position = zone.global_transform * STORE_LOBBY_POINT
	probe.collide_with_areas = false
	if not space.intersect_point(probe, 4).is_empty():
		out.append("A14 the lobby floor at %s is inside a solid" % STORE_LOBBY_POINT)
	var crew := BoxShape3D.new()
	crew.size = Vector3(0.4, 1.6, STORE_CREW_WIDTH)
	var sweep := PhysicsShapeQueryParameters3D.new()
	sweep.shape = crew
	sweep.collide_with_areas = false
	var steps := int(ceil(STORE_SWEEP_FROM.distance_to(STORE_SWEEP_TO) / 0.3))
	for step: int in steps + 1:
		var at := STORE_SWEEP_FROM.lerp(STORE_SWEEP_TO, float(step) / float(steps))
		sweep.transform = zone.global_transform * Transform3D(Basis.IDENTITY, at)
		var hits := space.intersect_shape(sweep, 4)
		if not hits.is_empty():
			var hit := hits[0]["collider"] as Node
			out.append("A14 four abreast walking in bump %s at x %.1f" % [hit.get_path() if hit != null else "?", at.x])
			break
	# The endcaps: a ShelfSlot per tool, the lobby stock standing each tool in one,
	# each slot's front open and in the shop's lobby (where Shops sells).
	var markers := get_tree().get_nodes_in_group("shop_shelf_slot")
	if markers.size() != Catalog.TOOLS.size():
		out.append("A14 %d ShelfSlot markers for %d tools" % [markers.size(), Catalog.TOOLS.size()])
	var stock := get_tree().get_first_node_in_group("lobby_stock")
	if stock == null or stock.is_in_group("shelf_stock"):
		out.append("A14 no lobby stock of its own")
	else:
		var lobby: Rect2 = Constants.SHOP_SITES["homie_depot"]["lobby"]
		for tool: String in Catalog.TOOLS:
			var slot := int(stock.call("slot_of", tool))
			if slot < 0:
				out.append("A14 the lobby endcaps have no %s" % tool)
				continue
			var front := to_zone * (stock.call("slot_front", slot) as Vector3)
			probe.position = zone.global_transform * Vector3(front.x, 0.5, front.z)
			if not lobby.has_point(Vector2(front.x, front.z)) or not space.intersect_point(probe, 4).is_empty():
				out.append("A14 the %s endcap's front %s is blocked or outside the lobby" % [tool, front])
	if get_tree().get_first_node_in_group("store_doors") == null:
		out.append("A14 no sliding doors")
	print("[ArtTest] A14 Homie Depot: %d solids, %d art pieces, %d ShelfSlots, %d problems" % [solids, pieces, markers.size(), out.size()])
	return out


## A collision shape's ground footprint (x, z) in the zone's space, or an empty
## rect for a shape it can't size.
func _footprint(shape: CollisionShape3D, to_zone: Transform3D) -> Rect2:
	var half := Vector3.ZERO
	if shape.shape is BoxShape3D:
		half = (shape.shape as BoxShape3D).size * 0.5
	elif shape.shape is CylinderShape3D:
		var cylinder := shape.shape as CylinderShape3D
		half = Vector3(cylinder.radius, cylinder.height * 0.5, cylinder.radius)
	else:
		return Rect2()
	var place := to_zone * shape.global_transform
	var box := AABB(place * Vector3(-half.x, -half.y, -half.z), Vector3.ZERO)
	for corner: int in 8:
		box = box.expand(place * Vector3(half.x * (1.0 if corner & 1 else -1.0), half.y * (1.0 if corner & 2 else -1.0), half.z * (1.0 if corner & 4 else -1.0)))
	return Rect2(box.position.x, box.position.z, box.size.x, box.size.z)


## A7: the triangle budgets, from the 'triangles' metas (counted at build time,
## so headless works).
func _budgets() -> Array[String]:
	var out: Array[String] = []
	for kind: String in _PropCatalog.kinds():
		var triangles := int(_PropCatalog.mesh(kind).get_meta("triangles", -1))
		if triangles <= 0 or triangles > Constants.ART_PROP_MAX_TRIANGLES:
			out.append("A7 prop %s: %d triangles (budget %d)" % [kind, triangles, Constants.ART_PROP_MAX_TRIANGLES])
	var holder := Node3D.new()
	var widths: Array = Constants.YARD_HOUSE_WIDTH
	var largest := (widths[widths.size() - 1] as Vector2).y
	for archetype: String in _Archetypes.ALL:
		for stories: int in [1, 2]:
			var house := _HouseBuilder.build(holder, Vector3.ZERO, {"archetype": archetype, "width": largest, "depth": 10.0, "stories": stories, "seed": 7, "detail": "full", "garage": true})
			var triangles := int(house.get_meta("triangles", -1))
			if triangles <= 0 or triangles > Constants.ART_HOUSE_MAX_TRIANGLES:
				out.append("A7 house %s, %d stories, %.1f m: %d triangles (budget %d)" % [archetype, stories, largest, triangles, Constants.ART_HOUSE_MAX_TRIANGLES])
			holder.remove_child(house)
			house.free()
	holder.free()
	for kind: String in _Trees.KINDS:
		for crown: String in (_Trees.CROWNS as Dictionary).keys():
			for season: int in 4:
				var near := int(_Trees.mesh_for(kind, crown, 0, season).get_meta("triangles", -1))
				var far := int(_Trees.mesh_for(kind, crown, 0, season, true).get_meta("triangles", -1))
				if near <= 0 or near > Constants.ART_TREE_MAX_TRIANGLES:
					out.append("A7 tree %s %s %s: %d triangles near (budget %d)" % [kind, crown, Seasons.IDS[season], near, Constants.ART_TREE_MAX_TRIANGLES])
				if far <= 0 or far > Constants.ART_TREE_FAR_MAX_TRIANGLES:
					out.append("A7 tree %s %s %s: %d triangles far (budget %d)" % [kind, crown, Seasons.IDS[season], far, Constants.ART_TREE_FAR_MAX_TRIANGLES])
	return out


## A12: every sign key exists; no sign, boat name or aisle trips the guardrail
## or the art wording rule.
func _strings() -> Array[String]:
	var out: Array[String] = []
	var keys: Array[String] = SET_PIECE_SIGNS.duplicate()
	for hood: String in _HoodStyles.ids():
		for key: Variant in _HoodStyles.style(hood).get("signs", []):
			keys.append(str(key))
	for key: String in keys:
		if not _Strings.SIGNS.has(key) or str(_Strings.SIGNS[key]).strip_edges().is_empty():
			out.append("A12 no words for Strings.SIGNS[%s]" % key)
	var texts := {}
	for key: Variant in _Strings.SIGNS:
		texts["SIGNS.%s" % key] = str(_Strings.SIGNS[key])
	for index: int in _Strings.BOAT_NAMES.size():
		texts["BOAT_NAMES[%d]" % index] = _Strings.BOAT_NAMES[index]
	for path: String in texts:
		var text: String = texts[path]
		for hit: String in _Guardrail.check(text):
			out.append("A12 %s: %s" % [path, hit])
		if _words.search(text) != null:
			out.append("A12 %s ('%s') breaks the art wording rule" % [path, text.replace("\n", " ")])
	return out
