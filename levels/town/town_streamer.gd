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
## its nearest parcel: LOD 0 (LotBuilder "near": the full house and yard, no
## small clutter) under STREAM_LOD0_METERS, LOD 1 ("far": a far house, lawn and
## trees) under STREAM_LOD1_METERS, the SKYLINE (one merged box mesh per chunk,
## from LotBuilder.skyline_boxes) under STREAM_CULL_METERS, and nothing past
## that. A level only changes STREAM_HYSTERESIS_METERS past its line.
##
## NO POPS. A level is built off the tree, one parcel a frame under
## STREAM_BUILD_MS_PER_FRAME (nearest chunk first), and added in one add_child.
## The level it replaces stays up until then (never a pop to empty), and the two
## cross-fade over STREAM_FADE_SECONDS (GeometryInstance3D.transparency). The
## level next to the shown one is kept, so turning back doesn't rebuild.
##
## WHAT THE TOWN SAYS (town.changed): a yard's leaves grow back with its mess
## (flat leaf drifts on the front lawn), a TurfMasters™ sign stands on a poached
## lawn, and a homeowner whose request is open waits on the porch and waves at
## passing trucks (LOD 0 only).
##
## Headless peers do the bookkeeping only (which level each chunk wants: stats),
## never building a mesh. The job site's slot is hidden while the job yard
## stands on it (set_slot_hidden, from world.place_job_site). Satellite Annex B
## (BorderZone) is never streamed: it is its own set, always there.

const _LotBuilder = preload("res://levels/town/lot_builder.gd")
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
const DETAIL: Array[String] = ["near", "far"]
## Leaf drift colors on a messy lawn.
const LEAF_COLORS: Array[Color] = [Color(0.86, 0.42, 0.13), Color(0.74, 0.22, 0.12), Color(0.9, 0.68, 0.2), Color(0.6, 0.33, 0.15)]
## How many drifts a fully grown-back lawn has.
const LEAF_DRIFTS: int = 14
## A waiting homeowner waves this often (s), give or take.
const WAVE_EVERY: float = 4.5

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
		if not _job.is_empty() and _frame_at > 0:
			stats["max_frame_ms"] = maxf(float(stats.get("max_frame_ms", 0.0)), float(now - _frame_at) / 1000.0)
		_frame_at = now
		_build_some()
		_step_fades(delta)


func _exit_tree() -> void:
	if _draw and int(stats.get("builds", 0)) > 0:
		print("[Streamer] %d builds, slowest %.1f ms; longest frame while building %.1f ms; %d swaps; draw calls up to %d" % [int(stats["builds"]), float(stats["max_build_ms"]), float(stats.get("max_frame_ms", 0.0)), int(stats["swaps"]), int(stats.get("draw_calls_max", 0))])


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
		(_job["holder"] as Node3D).free()
		_job = {}


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
		(_job["holder"] as Node3D).free()
		_job = {}
	if best >= 0:
		_start(best, int((_chunks[best] as Dictionary)["want"]))


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
		var done := _build_step()
		var spent := float(Time.get_ticks_usec() - step_started) / 1000.0
		stats["builds"] = int(stats["builds"]) + 1
		stats["max_build_ms"] = maxf(float(stats["max_build_ms"]), spent)
		if done:
			_finish_job()
		if Time.get_ticks_usec() - started >= budget:
			break


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
	var parcel := _LotBuilder.build(holder, slot["xform"], req)
	parcel.visible = not _hidden.has(int(slot["house_id"]))
	# The leaves and the sign now; a waiting homeowner once the level is in the
	# tree (_finish_job), since a body builds itself there.
	if int(slot["house_id"]) >= 0:
		_leaves_into(parcel, int(slot["house_id"]), int(slot["seed"]))
		if level == LOD_NEAR:
			var said: Dictionary = _reflect.get(int(slot["house_id"]), {})
			_replace(parcel, "RivalSign", _rival_sign(int(slot["seed"])) if bool(said.get("poached", false)) else null)
	_job["next"] = next + 1
	return next + 1 >= slots.size()


func _finish_job() -> void:
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
	add_child(holder)
	if level == LOD_NEAR:
		for slot_index: int in (chunk["slots"] as Array).size():
			var slot: Dictionary = chunk["slots"][slot_index]
			if bool((_reflect.get(int(slot["house_id"]), {}) as Dictionary).get("waving", false)):
				_reflect_in(chunk_index, slot_index)
	if int(chunk["want"]) == level:
		_swap(chunk_index, level)


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
			_leaves_into(parcel, int(slot["house_id"]), int(slot["seed"]))


func _reflect_into(parcel: Node3D, house_id: int, house_seed: int) -> void:
	_leaves_into(parcel, house_id, house_seed)
	var said: Dictionary = _reflect.get(house_id, {})
	_replace(parcel, "RivalSign", _rival_sign(house_seed) if bool(said.get("poached", false)) else null)
	_replace(parcel, "Waiting", _waiting_owner(parcel, house_seed) if bool(said.get("waving", false)) else null)


func _leaves_into(parcel: Node3D, house_id: int, house_seed: int) -> void:
	var said: Dictionary = _reflect.get(house_id, {})
	_replace(parcel, "Leaves", _leaf_drifts(parcel, float(said.get("mess", 0.0)), house_seed))


static func _replace(parcel: Node3D, child_name: String, made: Node3D) -> void:
	var old := parcel.get_node_or_null(child_name)
	if old != null:
		parcel.remove_child(old)
		old.queue_free()
	if made != null:
		made.name = child_name
		parcel.add_child(made)


## Flat drifts of fallen leaves over the front lawn, as many as the yard has
## grown back (net/town/town.gd mess), clear of the drive and the walk. Seeded
## by the house, so every peer drops them in the same places.
static func _leaf_drifts(parcel: Node3D, mess: float, house_seed: int) -> Node3D:
	var count := roundi(clampf(mess, 0.0, 1.0) * float(LEAF_DRIFTS))
	if count <= 0:
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([house_seed, "town_leaves"])
	var front := 6.0
	var house_at: Variant = parcel.get_meta("house_at", null)
	var spec: Dictionary = parcel.get_meta("house_spec", {})
	if house_at is Vector3 and spec.has("depth"):
		front = (house_at as Vector3).z + float(spec["depth"]) * 0.5 + 1.5
	var kit := _MeshKit.new()
	var placed := 0
	for _try: int in count * 4:
		if placed >= count:
			break
		var at := Vector3(rng.randf_range(-17.0, 17.0), 0.02, rng.randf_range(clampf(front, 0.0, 17.0), 18.5))
		# Off the drive and the front walk.
		if absf(at.x) < 3.0:
			continue
		var size := rng.randf_range(0.9, 2.2)
		kit.blob(at, Vector3(size, 0.07, size * rng.randf_range(0.6, 1.0)), LEAF_COLORS[rng.randi() % LEAF_COLORS.size()], {"detail": 1, "lumps": 0.5, "flat": true, "seed": house_seed % 997 + placed})
		placed += 1
	if placed == 0:
		return null
	var view := _Stylized.instance(kit.commit(), {"roughness": 1.0})
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return view


## TurfMasters™' lawn sign on a yard they poached: a wire stake and a glossy
## green panel, by the curb where every passing truck reads it.
static func _rival_sign(house_seed: int) -> Node3D:
	var root := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([house_seed, "rival_sign"])
	root.position = Vector3(rng.randf_range(6.0, 12.0) * (1.0 if rng.randf() < 0.5 else -1.0), 0.0, 18.2)
	root.rotation.y = rng.randf_range(-0.25, 0.25)
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
## they wave at whoever drives by.
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
	var timer := Timer.new()
	timer.wait_time = WAVE_EVERY + float(house_seed % 7) * 0.3
	timer.autostart = true
	timer.timeout.connect(func() -> void:
		if is_instance_valid(body) and body.is_visible_in_tree():
			body.call("gesture", "wave"))
	root.add_child(timer)
	return root
