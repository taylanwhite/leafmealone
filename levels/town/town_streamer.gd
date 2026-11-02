extends Node3D

## Authority: local, cosmetic, on every peer in the connected town. Draws the
## town's houses: every yard slot (from its house's seed, the same house the job
## yard builds; net/town/town.gd sends the seeds to clients) and every house
## across the street (from its slot's seed). Driving chunk B's version builds
## everything once at LOD 1 (levels/town/fallback_house.gd add_to_kit): one
## merged mesh per yard slot, and one per street for the houses across from
## them. Chunk E turns this into the streamer (chunks by distance, LOD 0/1/
## skyline, a per-frame build budget) behind the same API.
##
## Headless peers do the bookkeeping only (stats), never building a mesh.
## The job site's slot is hidden while the job yard stands on it
## (set_slot_hidden, from world.place_job_site).

const _Fallback = preload("res://levels/town/fallback_house.gd")
const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const _Hoods = preload("res://net/town/neighborhoods.gd")

## For probe and tests: chunks built at each LOD, builds made, the slowest build.
static var stats: Dictionary = {"chunks_lod0": 0, "chunks_lod1": 0, "builds": 0, "max_build_ms": 0.0}

## house_id -> the yard slot's node (only when drawing).
var _yards: Dictionary = {}
var _hidden: Dictionary = {}
var _built_from: int = 0
var _across_chunks: int = 0
var _draw: bool = true
## Where chunk E will measure distance from instead of the camera (tests), or INF.
var _focus_override := Vector3.INF


func _ready() -> void:
	name = "TownStreamer"
	add_to_group("town_streamer")
	_draw = DisplayServer.get_name() != "headless"
	stats = {"chunks_lod0": 0, "chunks_lod1": 0, "builds": 0, "max_build_ms": 0.0}
	_build_across()
	var town := get_tree().get_first_node_in_group("town")
	if town != null:
		town.connect("changed", _refresh_yards)
	_refresh_yards()


## Hides (or shows again) a yard slot's house, for the job yard standing there.
func set_slot_hidden(house_id: int, on: bool) -> void:
	if on:
		_hidden[house_id] = true
	else:
		_hidden.erase(house_id)
	var node := _yards.get(house_id) as Node3D
	if node != null:
		node.visible = not on


func is_slot_hidden(house_id: int) -> bool:
	return _hidden.has(house_id)


func hidden_slots() -> Array:
	var out: Array = _hidden.keys()
	out.sort()
	return out


## Tests: measure distance from pos instead of the camera; Vector3.INF clears it.
## Nothing streams yet in this version (driving chunk E).
func set_focus_override(pos: Vector3) -> void:
	_focus_override = pos


## The houses across every street: one merged mesh per street.
func _build_across() -> void:
	var by_hood: Dictionary = {}
	for slot: Dictionary in TownMap.dressing_slots():
		var hood_index := int(slot["hood_index"])
		if not by_hood.has(hood_index):
			by_hood[hood_index] = []
		(by_hood[hood_index] as Array).append(slot)
	for hood_index: Variant in by_hood:
		var started := Time.get_ticks_usec()
		_across_chunks += 1
		stats["chunks_lod1"] = int(stats["chunks_lod1"]) + 1
		if not _draw:
			continue
		var kit := _MeshKit.new()
		for slot: Dictionary in by_hood[hood_index]:
			var spec: Dictionary = _Fallback.spec_of(int(slot["seed"]), int(slot["size"]))
			_Fallback.add_to_kit(kit, slot["xform"], int(slot["seed"]), int(slot["size"]), spec)
		var mesh := kit.commit()
		if mesh != null:
			var view := _Stylized.instance(mesh, _Fallback.MATERIAL)
			view.name = "Across_%s" % str(_Hoods.HOODS[int(hood_index)]["id"])
			add_child(view)
		_note_build(started)


## The yard slots, once the town's seeds are here (and again only if they change).
func _refresh_yards() -> void:
	var town := get_tree().get_first_node_in_group("town")
	if town == null:
		return
	var houses: Array = town.get("houses")
	if houses.size() < TownMap.house_count():
		return
	var key_parts: Array = []
	for house_id: int in TownMap.house_count():
		var entry: Dictionary = houses[house_id]
		key_parts.append([int(entry.get("seed", 0)), int(entry.get("size", 1))])
	var key := hash(key_parts)
	if key == _built_from:
		return
	_built_from = key
	for node: Variant in _yards.values():
		remove_child(node as Node)
		(node as Node).queue_free()
	_yards.clear()
	stats["chunks_lod1"] = _across_chunks
	for house_id: int in TownMap.house_count():
		var started := Time.get_ticks_usec()
		var entry: Dictionary = houses[house_id]
		stats["chunks_lod1"] = int(stats["chunks_lod1"]) + 1
		if not _draw:
			continue
		var node := _Fallback.build(self, TownMap.yard_transform(house_id), TownMap.hood_id_of(house_id), int(entry.get("seed", 0)), int(entry.get("size", 1)), 1)
		node.name = "Yard%d" % house_id
		node.visible = not _hidden.has(house_id)
		_yards[house_id] = node
		_note_build(started)


func _note_build(started_usec: int) -> void:
	var spent := float(Time.get_ticks_usec() - started_usec) / 1000.0
	stats["builds"] = int(stats["builds"]) + 1
	stats["max_build_ms"] = maxf(float(stats["max_build_ms"]), spent)
