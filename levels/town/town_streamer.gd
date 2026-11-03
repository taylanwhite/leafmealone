extends Node3D

## Authority: local, cosmetic, on every peer in the connected town (driving
## chunk E). Draws Gutterford's houses: every yard slot (from its house's seed,
## the same house the job yard builds; net/town/town.gd sends the seeds to
## clients) and every house across the street (from its slot's seed), with art's
## parcel builder (levels/town/lot_builder.gd: the house, its yard, fences,
## trees and props in its neighborhood's style).
##
## STREAMING. The slots are cut into chunks of Constants.STREAM_SLOTS_PER_CHUNK
## along one side of one street. Every STREAM_TICK_SECONDS, from the camera (or
## set_focus_override for tests), each chunk picks a level by the distance to
## its nearest parcel: LOD 0 (LotBuilder "full": the house and yard down to the
## gnomes, as the job yard has them) under STREAM_LOD0_METERS, LOD 1 ("far": a far house, lawn and
## trees) under STREAM_LOD1_METERS, the SKYLINE (one merged box mesh per chunk,
## from LotBuilder.skyline_boxes) under STREAM_CULL_METERS, and nothing past
## that. A level only changes STREAM_HYSTERESIS_METERS past its line.
##
## NO POPS. A level is built off the tree under STREAM_BUILD_MS_PER_FRAME
## (nearest chunk first), each parcel over several steps (driving:E2: its plan,
## its new tree and prop meshes, its house, the rest, its leaves; stats
## "phase_ms" has the slowest of each), and added in one add_child.
## The level it replaces stays up until then (never a pop to empty), and the two
## cross-fade over STREAM_FADE_SECONDS (GeometryInstance3D.transparency). The
## level next to the shown one is kept, so turning back doesn't rebuild.
##
## WHAT THE TOWN SAYS (town.changed): a yard's leaves grow back with its mess
## (loose drifts and strays of single leaf cards on the front lawn), a
## TurfMasters™ sign stands on a poached lawn, and a homeowner whose request is
## open waits on the porch and waves when Chefty or a player comes by (LOD 0 only).
##
## Headless peers do the bookkeeping only (which level each chunk wants: stats),
## never building a mesh. The job site's slot is hidden while the job yard
## stands on it (set_slot_hidden, from world.place_job_site). Satellite Annex B
## (BorderZone) is never streamed: it is its own set, always there.

const _LotBuilder = preload("res://levels/town/lot_builder.gd")
const _Trees = preload("res://props/trees.gd")
const _PropCatalog = preload("res://props/prop_catalog.gd")
const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const _Hoods = preload("res://net/town/neighborhoods.gd")
const _CartoonBody = preload("res://player/cartoon_body.gd")
const _Strings = preload("res://ui/strings.gd")

const LOD_NEAR: int = 0
const LOD_FAR: int = 1
const LOD_SKYLINE: int = 2
const LOD_NONE: int = 3
const LOD_NAMES: Array[String] = ["Near", "Far", "Skyline", "None"]
## LotBuilder detail per parcel level.
const DETAIL: Array[String] = ["full", "far"]
## Fallen leaf colors on a messy lawn (the yard's own leaves are props/yard_models.gd
## LEAVES; these add a dry brown so a drift isn't one flat orange).
const LEAF_COLORS: Array[Color] = [Color(0.9, 0.48, 0.15), Color(0.93, 0.72, 0.22), Color(0.75, 0.25, 0.14), Color(0.58, 0.34, 0.16)]

## For probe and tests: chunks at each level (what each wants; headless peers
## only keep this), chunks wanting LOD 0 by neighborhood, builds made, the
## slowest build (ms), levels waiting to be built, swaps made, and fades running.
static var stats: Dictionary = {}

## [{id, hood_index, slots: [slot], center, want, shown, nodes: {level: Node3D}}]
## slot: {key, house_id (-1 across), xform, hood, seed, size, frontage, across, ready}
var _chunks: Array = []
## house_id -> [chunk index, slot index]
var _yard_slot: Dictionary = {}
var _hidden: Dictionary = {}
## house_id -> {mess, poached, waving}: what the town said last.
var _reflect: Dictionary = {}
var _draw: bool = true
var _wait: float = 0.0
## Where to measure distance from instead of the camera (tests), or INF.
var _focus_override := Vector3.INF
## The level being built: {chunk, level, holder, next (slot index), started}.
var _job: Dictionary = {}
## Cross-fades running: [{node, from, to, t, free_after}]
var _fades: Array = []
## Skyline boxes by slot key, computed once (LotBuilder.plan is not cheap).
var _boxes: Dictionary = {}
## When the last frame started (Time.get_ticks_usec), for stats max_frame_ms.
var _frame_at: int = 0
## Whether the last frame was sat out (BUILD_SKIP_FRAME_OVER_MS).
var _sat_out: bool = false


func _ready() -> void:
	name = "TownStreamer"
	add_to_group("town_streamer")
	_draw = DisplayServer.get_name() != "headless"
	stats = {"chunks_lod0": 0, "chunks_lod1": 0, "chunks_skyline": 0, "chunks_none": 0, "lod0_hoods": {}, "builds": 0, "max_build_ms": 0.0, "pending": 0, "swaps": 0, "fades": 0, "chunks": 0, "max_frame_ms": 0.0, "draw_calls": 0, "draw_calls_max": 0}
	_make_chunks()
	var town := get_tree().get_first_node_in_group("town")
	if town != null:
		town.connect("changed", _on_town_changed)
	_on_town_changed()
	_tick()


## The connected town's parcel request for a slot, the same for its visuals
## (here) and its solids (levels/town/town_colliders.gd): a yard slot is drawn
## exactly as its job yard's house (neighbor false); a house across the street
## nobody is hired at may be a neighbors-only archetype.
static func parcel_request(hood: String, house_seed: int, size: int, hood_index: int, across: bool) -> Dictionary:
	return {
		"hood": hood, "seed": house_seed, "size": size,
		"frontage": TownMap.SLOT_SPACING[hood_index], "neighbor": across,
	}


## Hides (or shows again) a yard slot's house, for the job yard standing there.
func set_slot_hidden(house_id: int, on: bool) -> void:
	if on:
		_hidden[house_id] = true
	else:
		_hidden.erase(house_id)
	var at: Array = _yard_slot.get(house_id, [])
	if at.is_empty():
		return
	var chunk: Dictionary = _chunks[int(at[0])]
	for level: int in chunk["nodes"]:
		var node := chunk["nodes"][level] as Node3D
		if level == LOD_SKYLINE:
			_rebuild_skyline(int(at[0]))
		elif node != null:
			var parcel := node.get_node_or_null(str((chunk["slots"][int(at[1])] as Dictionary)["key"])) as Node3D
			if parcel != null:
				parcel.visible = not on


func is_slot_hidden(house_id: int) -> bool:
	return _hidden.has(house_id)


func hidden_slots() -> Array:
	var out: Array = _hidden.keys()
	out.sort()
	return out


## Tests: measure distance from pos instead of the camera; Vector3.INF clears it.
## The next look happens right away.
func set_focus_override(pos: Vector3) -> void:
	_focus_override = pos
	_tick()


## Screenshots (net/dev/capture.gd's Town tour): everything a camera at `at`
## should see, built now, fades done. at = Vector3.INF goes back to the camera.
## A long frame on purpose; never in play.
func settle_now(at: Vector3) -> void:
	_focus_override = at
	if not _draw:
		_tick()
		return
	for _round: int in _chunks.size() * 4:
		_tick()
		if _job.is_empty():
			break
		while not _job.is_empty():
			if _build_step():
				_finish_job()
	for fade: Dictionary in _fades:
		fade["t"] = 1.0
	_step_fades(0.0)


## Tests: the level a chunk wants, by any of its yard houses.
func level_of_house(house_id: int) -> int:
	var at: Array = _yard_slot.get(house_id, [])
	return int((_chunks[int(at[0])] as Dictionary)["want"]) if not at.is_empty() else LOD_NONE


func _process(delta: float) -> void:
	_wait -= delta
	if _wait <= 0.0:
		_wait = Constants.STREAM_TICK_SECONDS
		_tick()
		if _draw:
			var calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			stats["draw_calls"] = calls
			stats["draw_calls_max"] = maxi(int(stats.get("draw_calls_max", 0)), calls)
	if _draw:
		# The whole frame's length (wall clock) while a level is being built
		# (docs/DECISIONS.md perf numbers).
		var now := Time.get_ticks_usec()
		var long := _frame_at > 0 and now - _frame_at > int(Constants.BUILD_SKIP_FRAME_OVER_MS * 1000.0)
		if not _job.is_empty() and _frame_at > 0:
			stats["max_frame_ms"] = maxf(float(stats.get("max_frame_ms", 0.0)), float(now - _frame_at) / 1000.0)
		_frame_at = now
		# A frame that was already long (a yard arriving, a body spawning) gets no
		# build step on top, never two frames running (driving:E2).
		if long and not _sat_out:
			_sat_out = true
		else:
			_sat_out = false
			_build_some()
		_step_fades(delta)


func _exit_tree() -> void:
	if _draw and int(stats.get("builds", 0)) > 0:
		print("[Streamer] %d builds, slowest %.1f ms; longest frame while building %.1f ms; %d swaps; draw calls up to %d; slowest by step %s" % [int(stats["builds"]), float(stats["max_build_ms"]), float(stats.get("max_frame_ms", 0.0)), int(stats["swaps"]), int(stats.get("draw_calls_max", 0)), stats.get("phase_ms", {})])


# ---------------------------------------------------------------- chunks

func _make_chunks() -> void:
	var per := maxi(1, Constants.STREAM_SLOTS_PER_CHUNK)
	var across_by_hood: Dictionary = {}
	for slot: Dictionary in TownMap.dressing_slots():
		var hood_index := int(slot["hood_index"])
		if not across_by_hood.has(hood_index):
			across_by_hood[hood_index] = []
		(across_by_hood[hood_index] as Array).append(slot)
	for hood_index: int in _Hoods.HOODS.size():
		var hood := str(_Hoods.HOODS[hood_index]["id"])
		var first := TownMap.first_house_of(hood_index)
		var count := int(_Hoods.HOODS[hood_index]["houses"])
		var yards: Array = []
		for house_id: int in range(first, first + count):
			yards.append({
				"key": "Yard%d" % house_id, "house_id": house_id, "xform": TownMap.yard_transform(house_id),
				"hood": hood, "hood_index": hood_index, "seed": 0, "size": 1, "across": false, "ready": false,
			})
		var across: Array = []
		for slot: Dictionary in across_by_hood.get(hood_index, []):
			across.append({
				"key": "Across%d_%d" % [hood_index, int(slot["index"])], "house_id": -1, "xform": slot["xform"],
				"hood": hood, "hood_index": hood_index, "seed": int(slot["seed"]), "size": int(slot["size"]), "across": true, "ready": true,
			})
		for side: Array in [yards, across]:
			for start: int in range(0, side.size(), per):
				var members: Array = side.slice(start, mini(start + per, side.size()))
				var center := Vector3.ZERO
				for member: Dictionary in members:
					center += (member["xform"] as Transform3D).origin
				center /= float(members.size())
				var index := _chunks.size()
				_chunks.append({
					"id": "%s_%s_%d" % [hood, "across" if bool(members[0]["across"]) else "yards", start / per],
					"hood": hood, "slots": members, "center": center, "want": LOD_NONE, "shown": LOD_NONE, "nodes": {},
				})
				for member_index: int in members.size():
					var member: Dictionary = members[member_index]
					if int(member["house_id"]) >= 0:
						_yard_slot[int(member["house_id"])] = [index, member_index]
	stats["chunks"] = _chunks.size()


## The yard slots' seeds (and what the town says about each), when the town's
## state arrives or changes.
func _on_town_changed() -> void:
	var town := get_tree().get_first_node_in_group("town")
	if town == null:
		return
	var houses: Array = town.get("houses")
	if houses.size() < TownMap.house_count():
		return
	var requests: Array = town.get("requests")
	for house_id: int in TownMap.house_count():
		var entry: Dictionary = houses[house_id]
		var at: Array = _yard_slot.get(house_id, [])
		if at.is_empty():
			continue
		var chunk_index := int(at[0])
		var slot: Dictionary = (_chunks[chunk_index] as Dictionary)["slots"][int(at[1])]
		var house_seed := int(entry.get("seed", 0))
		var size := int(entry.get("size", 1))
		if not bool(slot["ready"]) or house_seed != int(slot["seed"]) or size != int(slot["size"]):
			slot["seed"] = house_seed
			slot["size"] = size
			slot["ready"] = true
			_boxes.erase(slot["key"])
			_drop_levels(chunk_index)
		var said := {
			"mess": snappedf(float(town.call("mess", house_id)), 0.1),
			"poached": bool(entry.get("poached", false)),
			"waving": requests.has(house_id),
		}
		if said != _reflect.get(house_id, {}):
			_reflect[house_id] = said
			_reflect_in(chunk_index, int(at[1]))


## Every built level of a chunk goes (its houses changed).
func _drop_levels(chunk_index: int) -> void:
	var chunk: Dictionary = _chunks[chunk_index]
	for level: int in (chunk["nodes"] as Dictionary).keys():
		var node := chunk["nodes"][level] as Node3D
		if node != null:
			node.queue_free()
	(chunk["nodes"] as Dictionary).clear()
	chunk["shown"] = LOD_NONE
	if not _job.is_empty() and int(_job["chunk"]) == chunk_index:
		_drop_job()


func _chunk_ready(chunk: Dictionary) -> bool:
	for slot: Dictionary in chunk["slots"]:
		if not bool(slot["ready"]):
			return false
	return true


## Where distance is measured from: the override, else the camera, else nowhere.
func _focus() -> Vector3:
	if _focus_override != Vector3.INF:
		return _focus_override
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	return camera.global_position if camera != null else Vector3.INF


## Distance from at to the chunk's nearest parcel (its ground, 20 m from its middle).
func _distance(chunk: Dictionary, at: Vector3) -> float:
	var best := INF
	for slot: Dictionary in chunk["slots"]:
		var origin := (slot["xform"] as Transform3D).origin
		best = minf(best, maxf(Vector2(origin.x - at.x, origin.z - at.z).length() - TownMap.YARD_HALF, 0.0))
	return best


## Each chunk's level from the focus, with hysteresis, and the stats.
func _tick() -> void:
	var at := _focus()
	var lines: Array[float] = [Constants.STREAM_LOD0_METERS, Constants.STREAM_LOD1_METERS, Constants.STREAM_CULL_METERS]
	var margin := Constants.STREAM_HYSTERESIS_METERS
	var counts: Array[int] = [0, 0, 0, 0]
	var hoods := {}
	for chunk: Dictionary in _chunks:
		var want := LOD_NONE
		if at != Vector3.INF:
			var distance := _distance(chunk, at)
			want = LOD_NONE
			for level: int in lines.size():
				if distance < lines[level]:
					want = level
					break
			# Hysteresis: keep the current level until the distance is margin past its line.
			var current := int(chunk["want"])
			if want != current and current != LOD_NONE and current < lines.size():
				var inner := lines[current - 1] if current > 0 else -INF
				if distance < lines[current] + margin and distance > inner - margin:
					want = current
		chunk["want"] = want
		counts[want] += 1
		if want == LOD_NEAR:
			hoods[chunk["hood"]] = int(hoods.get(chunk["hood"], 0)) + 1
	stats["chunks_lod0"] = counts[0]
	stats["chunks_lod1"] = counts[1]
	stats["chunks_skyline"] = counts[2]
	stats["chunks_none"] = counts[3]
	stats["lod0_hoods"] = hoods
	if _draw:
		_settle(at)


## For each chunk: show the wanted level if it's built, start building it if
## not (nearest first, one at a time), and let go of levels two steps away.
func _settle(at: Vector3) -> void:
	var waiting := 0
	var best := -1
	var best_distance := INF
	for index: int in _chunks.size():
		var chunk: Dictionary = _chunks[index]
		var want := int(chunk["want"])
		var nodes: Dictionary = chunk["nodes"]
		if want == LOD_NONE:
			if int(chunk["shown"]) != LOD_NONE:
				_swap(index, LOD_NONE)
		elif nodes.has(want):
			if int(chunk["shown"]) != want:
				_swap(index, want)
		elif _chunk_ready(chunk):
			waiting += 1
			var distance := _distance(chunk, at) if at != Vector3.INF else 0.0
			if distance < best_distance:
				best_distance = distance
				best = index
		# Levels two or more steps from the wanted one aren't kept.
		for level: int in nodes.keys():
			if absi(level - want) >= 2 and level != int(chunk["shown"]):
				(nodes[level] as Node3D).queue_free()
				nodes.erase(level)
	stats["pending"] = waiting
	# The job in hand goes on unless a nearer chunk now waits and it's for a level nobody wants.
	if not _job.is_empty():
		var chunk: Dictionary = _chunks[int(_job["chunk"])]
		if int(chunk["want"]) == int(_job["level"]):
			return
		_drop_job()
	if best >= 0:
		_start(best, int((_chunks[best] as Dictionary)["want"]))


## Lets go of the level being built, and the house built ahead for it.
func _drop_job() -> void:
	if _job.is_empty():
		return
	(_job["holder"] as Node3D).free()
	var house: Variant = _job.get("house", null)
	if house != null and is_instance_valid(house) and not (house as Node).is_inside_tree():
		(house as Node).free()
	_job = {}


## Starts building a chunk's level off the tree.
func _start(chunk_index: int, level: int) -> void:
	var holder := Node3D.new()
	holder.name = LOD_NAMES[level]
	_job = {"chunk": chunk_index, "level": level, "holder": holder, "next": 0}


## One parcel (or the skyline) a frame, inside the budget; the finished level
## goes into the tree in one add_child.
func _build_some() -> void:
	var started := Time.get_ticks_usec()
	var budget := int(Constants.STREAM_BUILD_MS_PER_FRAME * 1000.0)
	while not _job.is_empty():
		var step_started := Time.get_ticks_usec()
		var label := _step_label()
		var done := _build_step()
		var spent := float(Time.get_ticks_usec() - step_started) / 1000.0
		stats["builds"] = int(stats["builds"]) + 1
		stats["max_build_ms"] = maxf(float(stats["max_build_ms"]), spent)
		# The slowest step of each kind (driving:E2: LOD 0 "full" is spread over them).
		var by_phase: Dictionary = stats.get("phase_ms", {})
		by_phase[label] = maxf(float(by_phase.get(label, 0.0)), snappedf(spent, 0.1))
		stats["phase_ms"] = by_phase
		if done:
			_finish_job()
		if Time.get_ticks_usec() - started >= budget:
			break


## What the next _build_step will do, for stats: "skyline", or the level's
## initial and the parcel's phase ("near plan", "far parcel", "near dress", ...).
func _step_label() -> String:
	var level := int(_job["level"])
	if level == LOD_SKYLINE:
		return "skyline"
	var phase := str(_job.get("phase", "plan"))
	if phase == "parcel" and _job.has("dress"):
		phase = "dress"
	return "%s %s" % [LOD_NAMES[level].to_lower(), phase]


## Builds the next piece of the job. True when the level is complete.
func _build_step() -> bool:
	var chunk: Dictionary = _chunks[int(_job["chunk"])]
	var level := int(_job["level"])
	var holder: Node3D = _job["holder"]
	var slots: Array = chunk["slots"]
	var next := int(_job["next"])
	if level == LOD_SKYLINE:
		# The boxes cost a parcel plan each: one slot a step, then the mesh.
		if next < slots.size():
			_slot_boxes(slots[next])
			_job["next"] = next + 1
			return false
		_fill_skyline(holder, chunk)
		return true
	var slot: Dictionary = slots[next]
	var req := parcel_request(str(slot["hood"]), int(slot["seed"]), int(slot["size"]), int(slot["hood_index"]), bool(slot["across"]))
	req["detail"] = DETAIL[level]
	req["name"] = str(slot["key"])
	# One parcel over several steps (driving:E2), so no frame pays for a whole
	# one: its plan (the house's numbers, cold the first time), the tree meshes and
	# prop meshes it will use that aren't built yet, its house, the rest of it
	# (from the same plan), then its leaves.
	var phase := str(_job.get("phase", "plan"))
	if phase == "plan":
		_job["plan"] = _LotBuilder.plan(req)
		_job["tree"] = 0
		_job["phase"] = "trees"
		return false
	if phase == "trees":
		# One tree mesh a step (near, then far): a cold one is the whole cost of
		# its step, and warm ones are cache hits, so _build_some's budget decides
		# how many go in a frame.
		var trees: Array = (_job["plan"] as Dictionary)["trees"]
		var index := int(_job["tree"])
		if index < trees.size() * 2:
			var tree: Array = trees[int(index / 2.0)]
			_Trees.mesh_for(str(tree[1]), str(tree[2]), int(tree[4]), -1, index % 2 == 1)
			index += 1
		_job["tree"] = index
		if index >= trees.size() * 2:
			_job["phase"] = "props"
			_job["prop"] = 0
		return false
	if phase == "props":
		# The catalog meshes the parcel's props will use, built ahead (cached),
		# within the budget: cold, they're most of a full parcel's cost.
		var props: Array = (_job["plan"] as Dictionary)["props"]
		var prop_started := Time.get_ticks_usec()
		var at := int(_job["prop"])
		while at < props.size():
			var entry: Dictionary = props[at]
			if not bool(entry.get("complex", false)):
				_PropCatalog.mesh(entry["kind"], entry.get("color", Color.WHITE), entry.get("size", Vector3.ONE))
			at += 1
			if Time.get_ticks_usec() - prop_started > int(Constants.STREAM_BUILD_MS_PER_FRAME * 1000.0):
				break
		_job["prop"] = at
		if at >= props.size():
			_job["phase"] = "house"
		return false
	if phase == "house":
		req["plan"] = _job["plan"]
		_job["house"] = _LotBuilder.house_for(req)
		_job["phase"] = "parcel"
		return false
	if _job.has("dress"):
		# A yard's own step after its parcel's: the leaves and the sign (a
		# waiting homeowner once the level is in the tree, _finish_job, since a
		# body builds itself there). Its own step so one frame never pays for both.
		var dressed: Node3D = _job["dress"]
		_job.erase("dress")
		_leaves_into(dressed, int(slot["house_id"]), int(slot["seed"]), level == LOD_FAR)
		if level == LOD_NEAR:
			var said: Dictionary = _reflect.get(int(slot["house_id"]), {})
			_replace(dressed, "RivalSign", _rival_sign(int(slot["seed"])) if bool(said.get("poached", false)) else null)
		_job["next"] = next + 1
		_job["phase"] = "plan"
		return next + 1 >= slots.size()
	var house: Variant = _job.get("house", null)
	if house != null and is_instance_valid(house):
		req["house_node"] = house
	if _job.has("plan"):
		req["plan"] = _job["plan"]
	_job.erase("house")
	_job.erase("plan")
	var parcel := _LotBuilder.build(holder, slot["xform"], req)
	# Read again when the level goes in (_finish_job): the job site may come or go
	# while the rest of the chunk builds.
	parcel.visible = not _hidden.has(int(slot["house_id"]))
	if int(slot["house_id"]) >= 0:
		_job["dress"] = parcel
		return false
	_job["next"] = next + 1
	_job["phase"] = "plan"
	return next + 1 >= slots.size()


func _finish_job() -> Node3D:
	var chunk_index := int(_job["chunk"])
	var level := int(_job["level"])
	var holder: Node3D = _job["holder"]
	_job = {}
	var chunk: Dictionary = _chunks[chunk_index]
	var nodes: Dictionary = chunk["nodes"]
	if nodes.has(level):
		(nodes[level] as Node3D).queue_free()
	nodes[level] = holder
	holder.visible = false
	# set_slot_hidden only reaches levels in nodes: a job site placed or cleared
	# while this one was off the tree is caught here.
	if level != LOD_SKYLINE:
		for slot: Dictionary in chunk["slots"]:
			var parcel := holder.get_node_or_null(str(slot["key"])) as Node3D
			if parcel != null:
				parcel.visible = not _hidden.has(int(slot["house_id"]))
	add_child(holder)
	if level == LOD_NEAR:
		for slot_index: int in (chunk["slots"] as Array).size():
			var slot: Dictionary = chunk["slots"][slot_index]
			if bool((_reflect.get(int(slot["house_id"]), {}) as Dictionary).get("waving", false)):
				_reflect_in(chunk_index, slot_index)
	if int(chunk["want"]) == level:
		_swap(chunk_index, level)
	return holder


## Tests (headless too): builds a yard house's chunk at level now, step by step
## as the frames would, calling between() after the first parcel is built (to
## land a change mid-build), and returns the finished level's node.
func build_level_now(house_id: int, level: int, between: Callable = Callable()) -> Node3D:
	var at: Array = _yard_slot.get(house_id, [])
	if at.is_empty() or level > LOD_SKYLINE or not _chunk_ready(_chunks[int(at[0])]):
		return null
	_drop_job()
	_start(int(at[0]), level)
	var first := true
	while not _job.is_empty():
		var done := _build_step()
		if first and between.is_valid():
			between.call()
		first = false
		if done:
			return _finish_job()
	return null


## Tests: the houses in a yard house's chunk, in slot order.
func chunk_houses(house_id: int) -> Array:
	var at: Array = _yard_slot.get(house_id, [])
	var out: Array = []
	if not at.is_empty():
		for slot: Dictionary in (_chunks[int(at[0])] as Dictionary)["slots"]:
			out.append(int(slot["house_id"]))
	return out


## Tests: lets a yard house's chunk's built levels go.
func drop_levels_of(house_id: int) -> void:
	var at: Array = _yard_slot.get(house_id, [])
	if not at.is_empty():
		_drop_levels(int(at[0]))


## Shows level instead of what the chunk shows now, cross-faded.
func _swap(chunk_index: int, level: int) -> void:
	var chunk: Dictionary = _chunks[chunk_index]
	var nodes: Dictionary = chunk["nodes"]
	var old := int(chunk["shown"])
	if old == level:
		return
	chunk["shown"] = level
	stats["swaps"] = int(stats["swaps"]) + 1
	if nodes.has(old):
		_fade(nodes[old], 0.0, 1.0, true)
	if nodes.has(level):
		var node := nodes[level] as Node3D
		node.visible = true
		_fade(node, 1.0, 0.0, false)


func _fade(node: Node3D, from: float, to: float, hide_after: bool) -> void:
	for fade: Dictionary in _fades:
		if fade["node"] == node:
			_fades.erase(fade)
			break
	_set_transparency(node, from)
	_fades.append({"node": node, "from": from, "to": to, "t": 0.0, "hide": hide_after})
	stats["fades"] = int(stats["fades"]) + 1


func _step_fades(delta: float) -> void:
	for index: int in range(_fades.size() - 1, -1, -1):
		var fade: Dictionary = _fades[index]
		var node: Variant = fade["node"]
		if not is_instance_valid(node):
			_fades.remove_at(index)
			continue
		fade["t"] = minf(float(fade["t"]) + delta / maxf(Constants.STREAM_FADE_SECONDS, 0.01), 1.0)
		var share := smoothstep(0.0, 1.0, float(fade["t"]))
		_set_transparency(node, lerpf(float(fade["from"]), float(fade["to"]), share))
		if float(fade["t"]) >= 1.0:
			if bool(fade["hide"]):
				(node as Node3D).visible = false
				_set_transparency(node, 0.0)
			_fades.remove_at(index)


static func _set_transparency(node: Node, value: float) -> void:
	var geometry := node as GeometryInstance3D
	if geometry != null:
		geometry.transparency = value
	for child: Node in node.get_children():
		_set_transparency(child, value)


# ---------------------------------------------------------------- the skyline

func _slot_boxes(slot: Dictionary) -> Array:
	var key := str(slot["key"])
	if not _boxes.has(key):
		_boxes[key] = _LotBuilder.skyline_boxes(parcel_request(str(slot["hood"]), int(slot["seed"]), int(slot["size"]), int(slot["hood_index"]), bool(slot["across"])))
	return _boxes[key]


## The chunk's skyline: every (shown) slot's house boxes in one mesh.
func _fill_skyline(holder: Node3D, chunk: Dictionary) -> void:
	for child: Node in holder.get_children():
		holder.remove_child(child)
		child.queue_free()
	var kit := _MeshKit.new()
	var any := false
	for slot: Dictionary in chunk["slots"]:
		if _hidden.has(int(slot["house_id"])):
			continue
		var xform: Transform3D = slot["xform"]
		for box: Array in _slot_boxes(slot):
			kit.call("box", xform * (box[0] as Vector3), box[1], box[2], xform.basis)
			any = true
	if not any:
		return
	var view := _Stylized.instance(kit.commit(), {"roughness": 0.9, "snow": 1.0})
	view.name = "Boxes"
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(view)


func _rebuild_skyline(chunk_index: int) -> void:
	var chunk: Dictionary = _chunks[chunk_index]
	var node := (chunk["nodes"] as Dictionary).get(LOD_SKYLINE, null) as Node3D
	if node != null:
		_fill_skyline(node, chunk)
		if int(chunk["shown"]) != LOD_SKYLINE:
			node.visible = false


# ---------------------------------------------------------------- what the town says

## A yard's reflection changed: redo it on the built parcels that show it.
func _reflect_in(chunk_index: int, slot_index: int) -> void:
	var chunk: Dictionary = _chunks[chunk_index]
	var slot: Dictionary = chunk["slots"][slot_index]
	for level: int in [LOD_NEAR, LOD_FAR]:
		var node := (chunk["nodes"] as Dictionary).get(level, null) as Node3D
		var parcel := node.get_node_or_null(str(slot["key"])) as Node3D if node != null else null
		if parcel == null:
			continue
		if level == LOD_NEAR:
			_reflect_into(parcel, int(slot["house_id"]), int(slot["seed"]))
		else:
			_leaves_into(parcel, int(slot["house_id"]), int(slot["seed"]), true)


func _reflect_into(parcel: Node3D, house_id: int, house_seed: int) -> void:
	_leaves_into(parcel, house_id, house_seed, false)
	var said: Dictionary = _reflect.get(house_id, {})
	_replace(parcel, "RivalSign", _rival_sign(house_seed) if bool(said.get("poached", false)) else null)
	_replace(parcel, "Waiting", _waiting_owner(parcel, house_seed) if bool(said.get("waving", false)) else null)


func _leaves_into(parcel: Node3D, house_id: int, house_seed: int, far: bool) -> void:
	var said: Dictionary = _reflect.get(house_id, {})
	_replace(parcel, "Leaves", _leaf_drifts(parcel, float(said.get("mess", 0.0)), house_seed, far))


static func _replace(parcel: Node3D, child_name: String, made: Node3D) -> void:
	var old := parcel.get_node_or_null(child_name)
	if old != null:
		parcel.remove_child(old)
		old.queue_free()
	if made != null:
		made.name = child_name
		parcel.add_child(made)


## The leaves a yard has grown back (net/town/town.gd mess), lying on its front
## lawn clear of the drive and the walk: loose drifts of single leaf cards, thick
## in the middle and thinning out (where the wind left them against nothing in
## particular), and strays strewn between. Never a solid: Chefty and the camera
## pass through leaves, so they have to look like leaves. LOD 1 (far) lays a
## share of them, bigger, so a lawn 200 m off still reads orange without
## shimmering. Seeded by the house, so every peer drops them in the same places.
static func _leaf_drifts(parcel: Node3D, mess: float, house_seed: int, far: bool = false) -> Node3D:
	var share := clampf(mess, 0.0, 1.0)
	var drifts := roundi(share * float(Constants.STREAM_LEAF_DRIFTS_MAX))
	var strays := roundi(share * float(Constants.STREAM_LEAF_STRAYS))
	var per_drift := Constants.STREAM_LEAVES_PER_DRIFT
	var scale := 1.0
	if far:
		per_drift = maxi(1, roundi(float(per_drift) * Constants.STREAM_LEAF_FAR_SHARE))
		strays = roundi(float(strays) * Constants.STREAM_LEAF_FAR_SHARE)
		scale = Constants.STREAM_LEAF_FAR_SCALE
	if drifts + strays <= 0:
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([house_seed, "town_leaves"])
	var front := 6.0
	var house_at: Variant = parcel.get_meta("house_at", null)
	var spec: Dictionary = parcel.get_meta("house_spec", {})
	if house_at is Vector3 and spec.has("depth"):
		front = (house_at as Vector3).z + float(spec["depth"]) * 0.5 + 1.5
	var half := Constants.STREAM_LEAF_LAWN_HALF_WIDTH
	var curb := Constants.STREAM_LEAF_LAWN_FRONT_Z
	var clear := Constants.STREAM_LEAF_CLEAR_X
	var near_z := clampf(front, 0.0, curb - 1.0)
	var kit := _MeshKit.new()
	var placed := 0
	for _try: int in drifts * 4:
		if placed >= drifts:
			break
		var middle := Vector2(rng.randf_range(-half, half), rng.randf_range(near_z, curb))
		if absf(middle.x) < clear + 0.5:
			continue
		placed += 1
		var radius := rng.randf_range(Constants.STREAM_LEAF_DRIFT_RADIUS.x, Constants.STREAM_LEAF_DRIFT_RADIUS.y)
		var squash := rng.randf_range(0.45, 1.0)
		var turn := rng.randf() * TAU
		_leaf_bed(kit, rng, middle, radius, squash, turn)
		for _leaf: int in per_drift:
			# Most on the bed, the rest past its edge so the edge breaks up.
			var out := pow(rng.randf(), 0.7) * 1.2
			var angle := rng.randf() * TAU
			var spot := middle + Vector2(cos(angle) * out * radius, sin(angle) * out * radius * squash).rotated(turn)
			if absf(spot.x) < clear or spot.y > curb or spot.y < near_z - 0.5:
				continue
			var lift := Constants.STREAM_LEAF_HEAP_METERS * maxf(1.0 - out, 0.0)
			_leaf_card(kit, rng, Vector3(spot.x, Constants.STREAM_LEAF_BED_Y + 0.012 + lift + 0.015 * rng.randf(), spot.y), scale)
	for _stray: int in strays:
		var spot := Vector2(rng.randf_range(-half, half), rng.randf_range(near_z - 1.0, curb))
		if absf(spot.x) < clear:
			continue
		_leaf_card(kit, rng, Vector3(spot.x, Constants.STREAM_LEAF_BED_Y, spot.y), scale)
	var mesh := kit.commit()
	if mesh == null:
		return null
	var view := _Stylized.instance(mesh, {"roughness": 1.0})
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return view


## A drift's bed: a paper-thin mat of leaf colors with a ragged edge and a low
## rise in the middle, so the drift reads as many leaves (its cards on top give
## the leaf shapes) instead of a lawn with a few specks.
static func _leaf_bed(kit: Object, rng: RandomNumberGenerator, middle: Vector2, radius: float, squash: float, turn: float) -> void:
	var sides := Constants.STREAM_LEAF_BED_SIDES
	var rim: Array[Vector3] = []
	var inner: Array[Vector3] = []
	var heap := Constants.STREAM_LEAF_HEAP_METERS
	for side: int in sides:
		var angle := TAU * (float(side) + rng.randf_range(-0.3, 0.3)) / float(sides)
		var reach := radius * rng.randf_range(0.65, 1.1)
		var flat := middle + Vector2(cos(angle) * reach, sin(angle) * reach * squash).rotated(turn)
		rim.append(Vector3(flat.x, Constants.STREAM_LEAF_BED_Y, flat.y))
		var half := middle + (flat - middle) * rng.randf_range(0.4, 0.6)
		inner.append(Vector3(half.x, Constants.STREAM_LEAF_BED_Y + heap * 0.6, half.y))
	var top := Vector3(middle.x, Constants.STREAM_LEAF_BED_Y + heap, middle.y)
	# One deep under-layer tone per bed, barely varied, so its facets never read
	# as shards up close; the cards on top bring the bright leaf colors.
	var base := LEAF_COLORS[rng.randi() % LEAF_COLORS.size()].lerp(LEAF_COLORS[3], 0.35).darkened(Constants.STREAM_LEAF_BED_SHADE)
	for side: int in sides:
		var next := (side + 1) % sides
		_bed_facet(kit, rng, base, top, inner[side], inner[next])
		_bed_facet(kit, rng, base, inner[side], rim[side], rim[next])
		_bed_facet(kit, rng, base, inner[side], rim[next], inner[next])


static func _bed_facet(kit: Object, rng: RandomNumberGenerator, base: Color, a: Vector3, b: Vector3, c: Vector3) -> void:
	var shade := rng.randf_range(-0.05, 0.05)
	var color := base.lightened(shade) if shade > 0.0 else base.darkened(-shade)
	# Godot's front face is clockwise seen from above: the cross points down.
	if (b - a).cross(c - a).y > 0.0:
		kit.call("triangle", a, c, b, Vector3.UP, color)
	else:
		kit.call("triangle", a, b, c, Vector3.UP, color)


## One fallen leaf lying nearly flat, a little tipped, in a shade of autumn.
static func _leaf_card(kit: Object, rng: RandomNumberGenerator, at: Vector3, scale: float) -> void:
	var tip := Vector3(rng.randf_range(-0.3, 0.3), 1.0, rng.randf_range(-0.3, 0.3))
	var color := LEAF_COLORS[rng.randi() % LEAF_COLORS.size()]
	var shade := rng.randf_range(-0.12, 0.1)
	color = color.lightened(shade) if shade > 0.0 else color.darkened(-shade)
	var size := rng.randf_range(Constants.STREAM_LEAF_SIZE.x, Constants.STREAM_LEAF_SIZE.y) * scale
	kit.call("leaf_card", at, tip, size, color, 0.0, rng.randf() * TAU)


## TurfMasters™' lawn sign on a yard they poached: a wire stake and a glossy
## green panel, by the curb where every passing truck reads it.
static func _rival_sign(house_seed: int) -> Node3D:
	var root := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([house_seed, "rival_sign"])
	var side := Constants.STREAM_SIGN_SIDE_METERS
	root.position = Vector3(rng.randf_range(side.x, side.y) * (1.0 if rng.randf() < 0.5 else -1.0), 0.0, Constants.STREAM_SIGN_Z)
	root.rotation.y = rng.randf_range(-Constants.STREAM_SIGN_TURN, Constants.STREAM_SIGN_TURN)
	var kit := _MeshKit.new()
	for x: float in [-0.22, 0.22]:
		kit.tube(PackedVector3Array([Vector3(x, 0.0, 0.0), Vector3(x, 0.55, 0.0)]), PackedFloat32Array([0.012, 0.012]), Color(0.55, 0.56, 0.58), 5, {"jitter": 0.0})
	kit.rbox(Vector3(0.0, 0.72, 0.0), Vector3(0.32, 0.2, 0.015), Color(0.1, 0.55, 0.28), 8.0, {"shade": false})
	kit.rbox(Vector3(0.0, 0.72, 0.0), Vector3(0.335, 0.215, 0.012), Color(0.97, 0.97, 0.94), 8.0, {"shade": false})
	root.add_child(_Stylized.instance(kit.commit(), {"roughness": 0.35, "specular": 0.45}))
	var label := Label3D.new()
	label.text = _Strings.UI["rival_sign_text"]
	label.font_size = 28
	label.pixel_size = 0.003
	label.double_sided = false
	label.modulate = Color(1.0, 1.0, 0.95)
	label.outline_size = 0
	label.position = Vector3(0.0, 0.72, 0.03)
	label.visibility_range_end = Constants.TOWN_SMALL_VISIBLE_METERS
	root.add_child(label)
	return root


## The homeowner out on the porch, waiting for a crew (their request is open):
## they wave when Chefty or a player comes by (within STREAM_WAVE_METERS), not
## at an empty street.
static func _waiting_owner(parcel: Node3D, house_seed: int) -> Node3D:
	var root := Node3D.new()
	var door: Variant = parcel.get_meta("door", null)
	var at := (door as Vector3) if door is Vector3 else Vector3(0.0, 0.0, 6.0)
	root.position = Vector3(at.x + 1.1, at.y, at.z + 0.9)
	var body: Node3D = _CartoonBody.new()
	body.name = "CartoonBody"
	body.call("dress_from_seed", house_seed)
	root.add_child(body)
	body.call("build")
	var cooldown := Constants.STREAM_WAVE_COOLDOWN_SECONDS + float(posmod(house_seed, 7)) / 6.0 * Constants.STREAM_WAVE_JITTER_SECONDS
	# A Dictionary, since a lambda's captured locals are copies.
	var state := {"wait": 0.0}
	var timer := Timer.new()
	timer.wait_time = Constants.STREAM_WAVE_LOOK_SECONDS
	timer.autostart = true
	timer.timeout.connect(func() -> void:
		state["wait"] = maxf(float(state["wait"]) - Constants.STREAM_WAVE_LOOK_SECONDS, 0.0)
		if float(state["wait"]) > 0.0 or not is_instance_valid(body) or not body.is_visible_in_tree():
			return
		if someone_passing(root):
			body.call("gesture", "wave")
			state["wait"] = cooldown)
	root.add_child(timer)
	return root


## Chefty or a player within STREAM_WAVE_METERS of node (flat distance).
static func someone_passing(node: Node3D) -> bool:
	if not node.is_inside_tree():
		return false
	var here := node.global_position
	for group: String in ["chefty", "players"]:
		for other: Node in node.get_tree().get_nodes_in_group(group):
			var spot := other as Node3D
			if spot != null and Vector2(spot.global_position.x - here.x, spot.global_position.z - here.z).length() < Constants.STREAM_WAVE_METERS:
				return true
	return false
