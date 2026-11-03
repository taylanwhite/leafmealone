class_name LeafMotion
extends Node3D

## Authority: local presentation. Carries every leaf that changes cell from where
## it lay to where it lands, instead of letting it vanish in one cell and appear
## in another (the 0.4.5 "leaves just teleport" playtest note). Each frame the leaf
## view (contract C3: leaves/leaf_renderer.gd, or net/dev/leaf_view_stub.gd in
## tests) reports how the field changed; LeafFlow explains the change with the
## recent stroke events (contract C1); this node claims the units it will animate
## and spawns movers (leaves/leaf_movers.gd) that launch when the rake head sweeps
## past them (contract C4, group "rake_heads"), fly, flutter, skid and settle on
## the growing pile. Whatever it does not claim, the view morphs, so nothing ever
## pops. Also: leaves kicked up by running and diving (same flakes, same slots),
## chaff at each bite (leaves/leaf_chaff.gd), landing sounds through the
## "leaf_audio" group (contract C5). Never writes the field.
## Created by the view as "LeafMotion", a sibling of the field. Headless runs only
## with --leaf-motion-headless (the simulation, nothing drawn).

const _Chaff = preload("res://leaves/leaf_chaff.gd")
## Field kind strings to mover kinds.
const KINDS: Dictionary = {
	"rake": LeafMovers.K_RAKE, "hand": LeafMovers.K_HAND, "blower": LeafMovers.K_BLOWER,
	"crew_rake": LeafMovers.K_CREW, "plow": LeafMovers.K_PLOW, "bag": LeafMovers.K_BAG,
	"crew_bag": LeafMovers.K_BAG, "mulch": LeafMovers.K_MULCH, "scatter": LeafMovers.K_SCATTER,
	"edge": LeafMovers.K_EDGE,
}
## How many simulation times to keep for the averages.
const SIM_SAMPLES: int = 600

var _view: Node
var _field: Node3D
var _movers := LeafMovers.new()
var _hints: Array = []
var _clock: float = 0.0
var _cap: int = 900
var _range: float = 32.0
var _attached: bool = false
var _gpu: bool = true
var _chaff: Node3D
var _draws: Array[MultiMeshInstance3D] = []
var _sim_ms := PackedFloat32Array()
var _sim_next: int = 0
var _perf_scale: float = 1.0
var _sim_ema: float = 0.0
var _heads: Dictionary = {}
var _fars: Dictionary = {}
var _was_down: Dictionary = {}
var _players: Dictionary = {}
var _settle: Dictionary = {}
var _settle_until: float = -1.0
var _rng := RandomNumberGenerator.new()
var _grid := Vector2i(80, 80)
var _counts := {
	"batches": 0, "drops": 0, "fades": 0, "kicks": 0, "dives": 0, "morph_units": 0, "retargets": 0,
	"hard_resets": 0, "lod_skipped": 0, "resyncs_morphed": 0, "movers_peak": 0, "sinks": 0,
	"sources": 0, "transfers": 0, "corrections": 0, "predicted": 0, "edge": 0, "gusts": 0,
	"sink_redirects": 0, "fade_units": 0, "fade_units_hinted": 0,
}


## Whether leaf motion runs in this process: always with a window; headless only
## with --leaf-motion-headless (tests), and then nothing is drawn.
## display: DisplayServer.get_name(), or another name for tests.
static func allowed(args: PackedStringArray, display: String = "") -> bool:
	if display == "":
		display = DisplayServer.get_name()
	return display != "headless" or args.has("--leaf-motion-headless")


func _ready() -> void:
	add_to_group("leaf_motion")
	_rng.seed = 90210


func attach(view: Node, field: Node) -> void:
	if _attached:
		return
	if not allowed(OS.get_cmdline_user_args()) or view == null or field == null:
		queue_free()
		return
	_view = view
	_field = field as Node3D
	_gpu = DisplayServer.get_name() != "headless"
	_grid = Vector2i(int(field.get("grid_width")), int(field.get("grid_depth")))
	var detail: Array = Constants.LEAF_DETAIL.get(_detail_preset(), Constants.LEAF_DETAIL["high"])
	_cap = int(detail[0])
	_range = float(detail[1])
	var meshes: Array[MultiMesh] = []
	if _gpu:
		for species: int in 3:
			var draw := MultiMeshInstance3D.new()
			draw.name = "Movers%d" % species
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.use_colors = true
			multi.use_custom_data = true
			multi.mesh = view.call("species_mesh", species)
			multi.instance_count = _cap
			multi.visible_instance_count = 0
			draw.multimesh = multi
			draw.material_override = view.call("flake_material", "mover")
			draw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			draw.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
			# Movers fly anywhere over the yard; don't let culling guess from stale instances.
			var ground: Vector3 = view.call("cell_center_world", Vector2i.ZERO)
			draw.custom_aabb = AABB(Vector3(ground.x - 4.0, ground.y - 2.0, ground.z - 4.0), Vector3(float(_grid.x) * 0.5 + 8.0, 8.0, float(_grid.y) * 0.5 + 8.0))
			# Movers are drawn in world space (the view's slots are world positions).
			draw.top_level = true
			add_child(draw)
			draw.global_transform = Transform3D.IDENTITY
			_draws.append(draw)
			meshes.append(multi)
		_chaff = _Chaff.new()
		_chaff.name = "Chaff"
		add_child(_chaff)
		var below: Vector3 = view.call("cell_center_world", _grid / 2)
		_chaff.call("build", below - Vector3(0.0, 1.5, 0.0))
	_movers.setup(_cap, view, meshes, _grid.x)
	view.connect("targets_changed", _on_targets_changed)
	if field.has_signal("stroke_event"):
		field.connect("stroke_event", add_hint)
	view.tree_exiting.connect(queue_free)
	_sim_ms.resize(SIM_SAMPLES)
	_attached = true


## A stroke event (contract C1) that explains the changes about to come: from the
## field's stroke_event, or synthetic ones from tests and tools.
func add_hint(ev: Dictionary) -> void:
	var hint := ev.duplicate()
	if not hint.has("dir"):
		hint["dir"] = Vector3.ZERO
	hint["_until"] = _clock + Constants.LEAF_HINT_SECONDS
	hint["_got"] = _clock
	_hints.append(hint)
	if _chaff != null:
		var head: Dictionary = _heads.get(int(hint.get("actor", 0)), {})
		_chaff.call("burst", hint, head, _view)


func _on_targets_changed(changes: PackedInt32Array, hard: bool) -> void:
	if not _attached:
		return
	if hard:
		_movers.clear(true)
		_counts["hard_resets"] = int(_counts["hard_resets"]) + 1
		return
	_prune_hints()
	# On the host a mower's mulch is told at the next send tick, after its leaves
	# already went (leaf_field.gd _flush_mulch): explain this batch with the mulch
	# not told yet, for this solve only (the real event explains nothing new later).
	var told := _hints.size()
	if _field.has_method("pending_mulch"):
		for ev: Dictionary in _field.call("pending_mulch"):
			var hint := ev.duplicate()
			hint["_until"] = _clock
			hint["_got"] = _clock
			_hints.append(hint)
	_explain(changes)
	if _hints.size() > told:
		_hints.resize(told)


func _explain(changes: PackedInt32Array) -> void:
	var cells := changes.size() / 3
	if cells == 0:
		return
	if cells > Constants.LEAF_FLOW_MAX_CELLS:
		_counts["resyncs_morphed"] = int(_counts["resyncs_morphed"]) + 1
		return
	var center := Vector3.ZERO
	for index: int in cells:
		center += view_center(Vector2i(changes[index * 3], changes[index * 3 + 1]))
	center /= float(cells)
	var share := 1.0
	var eye := _camera_point()
	if eye != Vector3.INF:
		var distance := Vector2(eye.x - center.x, eye.z - center.z).length()
		if distance > _range:
			_counts["lod_skipped"] = int(_counts["lod_skipped"]) + 1
			return
		if distance > Constants.LEAF_MOTION_NEAR:
			share = Constants.LEAF_MOTION_FAR_SHARE
	var hinted := _hinted(changes)
	if not hinted:
		# A resync nothing explains: a few flakes' worth animates, a big one morphs.
		var flakes := 0
		for index: int in cells:
			var cell := Vector2i(changes[index * 3], changes[index * 3 + 1])
			var now := int(_view.call("target_units", cell))
			flakes += absi(int(_view.call("hero_count", now)) - int(_view.call("hero_count", now - changes[index * 3 + 2])))
		if flakes > Constants.LEAF_RESYNC_ANIMATE_MAX:
			_counts["resyncs_morphed"] = int(_counts["resyncs_morphed"]) + 1
			return
	var solution := LeafFlow.solve(changes, _hints, _view, _grid)
	_counts["batches"] = int(_counts["batches"]) + 1
	_spawn(solution, share, hinted)


func view_center(cell: Vector2i) -> Vector3:
	return _view.call("cell_center_world", cell)


func _hinted(changes: PackedInt32Array) -> bool:
	if _hints.is_empty():
		return false
	var cells := changes.size() / 3
	for index: int in mini(cells, 8):
		var at := view_center(Vector2i(changes[index * 3], changes[index * 3 + 1]))
		for hint: Dictionary in _hints:
			var point: Vector3 = hint.get("at", Vector3.ZERO)
			var reach := LeafFlow.reach_of(hint)
			if Vector2(at.x - point.x, at.z - point.z).length() <= reach:
				return true
	return false


## Claims what the solution animates and creates the movers for it.
func _spawn(solution: Dictionary, share: float, hinted: bool) -> void:
	for fade: Dictionary in solution["fades"]:
		# Left unclaimed: the view morphs it out. Counted, since an observer sees
		# these leaves shrink away instead of fly (the test asserts on hinted ones).
		_counts["fades"] = int(_counts["fades"]) + 1
		_counts["fade_units"] = int(_counts["fade_units"]) + int(fade["units"])
		if hinted:
			_counts["fade_units_hinted"] = int(_counts["fade_units_hinted"]) + int(fade["units"])
	var total := 0
	for key: String in ["transfers", "sinks", "sources", "drops"]:
		for item: Dictionary in solution[key]:
			total += int(item["units"])
	if total <= 0:
		return
	var wanted := clampi(int(ceil(float(total) / float(Constants.LEAF_MOVER_UNITS))), 4, Constants.LEAF_MOVERS_PER_BATCH_MAX)
	wanted = maxi(1, int(round(float(wanted) * share * _perf_scale)))
	var per := maxi(Constants.LEAF_MOVER_UNITS, int(ceil(float(total) / float(wanted))))
	var need := 0
	for key: String in ["transfers", "sinks", "sources", "drops"]:
		for item: Dictionary in solution[key]:
			need += maxi(1, int(round(float(item["units"]) / float(per))))
	if need > _movers.free_count():
		_rush_oldest(need - _movers.free_count())
	# Movers still on their way into a cell that is now losing leaves are sent on
	# instead of taking more off the cell (a cascade across two batches).
	var inbound: Dictionary = {}
	var kinds := _movers.kind
	var dsts := _movers.dst
	var states := _movers.state
	for i: int in _movers.alive:
		var state := states[i]
		if kinds[i] == LeafMovers.K_KICK or dsts[i] < 0 or not (state == LeafMovers.WAIT or state == LeafMovers.FLY or state == LeafMovers.SLIDE or state == LeafMovers.RIDE):
			continue
		if not inbound.has(dsts[i]):
			inbound[dsts[i]] = []
		(inbound[dsts[i]] as Array).append(i)
	for transfer: Dictionary in solution["transfers"]:
		var src: Vector2i = transfer["src"]
		var dst: Vector2i = transfer["dst"]
		var left := _redirect_inbound(inbound, src, int(transfer["units"]), dst, -1, Vector3.INF)
		if left <= 0:
			continue
		var hint := _hint_of(int(transfer["hint"]))
		var kind_id := int(KINDS.get(str(hint.get("kind", "")), LeafMovers.K_CORRECTION)) if not hint.is_empty() else LeafMovers.K_CORRECTION
		_counts["transfers"] = int(_counts["transfers"]) + 1
		if kind_id == LeafMovers.K_CORRECTION:
			_counts["corrections"] = int(_counts["corrections"]) + 1
		elif bool(hint.get("local", false)):
			_counts["predicted"] = int(_counts["predicted"]) + 1
		_emit_movers(kind_id, hint, src, dst, left, per, Vector3.INF)
	for sink: Dictionary in solution["sinks"]:
		var hint := _hint_of(int(sink["hint"]))
		var kind_id := int(KINDS.get(str(sink["kind"]), LeafMovers.K_BAG))
		if kind_id == LeafMovers.K_EDGE:
			_counts["edge"] = int(_counts["edge"]) + 1
		else:
			_counts["sinks"] = int(_counts["sinks"]) + 1
		# Leaves still flying into a cell the bag (or deck, or edge) just emptied go
		# into it from the air; only what the cell shows is launched from it.
		var left := _redirect_inbound(inbound, sink["src"], int(sink["units"]), Vector2i(-1, -1), kind_id, sink["to"])
		if left > 0:
			_emit_movers(kind_id, hint, sink["src"], Vector2i(-1, -1), left, per, sink["to"])
	for source: Dictionary in solution["sources"]:
		_counts["sources"] = int(_counts["sources"]) + 1
		_emit_movers(LeafMovers.K_SCATTER, _hint_of(int(source["hint"])), Vector2i(-1, -1), source["dst"], int(source["units"]), per, source["from"])
	for drop: Dictionary in solution["drops"]:
		_counts["drops"] = int(_counts["drops"]) + 1
		_emit_movers(LeafMovers.K_DROP, {}, Vector2i(-1, -1), drop["dst"], int(drop["units"]), per, Vector3.INF)
	_counts["movers_peak"] = maxi(int(_counts["movers_peak"]), _movers.alive_count())


## Movers still on their way into src (inbound: cell index -> movers) carry up to
## units of src's loss on instead of the cell launching leaves it does not show yet:
## on to dst, or (dst (-1, -1)) into the sink sink_kind at point. A mover bigger than
## what is left splits, its twin still landing in src; with no free mover to split
## into it is left alone and the rest goes the usual way. Returns the units left.
func _redirect_inbound(inbound: Dictionary, src: Vector2i, units: int, dst: Vector2i, sink_kind: int, point: Vector3) -> int:
	var left := units
	var coming: Array = inbound.get(src.x + src.y * _grid.x, [])
	var at := coming.size() - 1
	while left > 0 and at >= 0:
		var mover := int(coming[at])
		var mover_units := int(_movers.units[mover])
		at -= 1
		var take := mini(mover_units, left)
		if take < mover_units and _movers.free_count() <= 0:
			continue
		coming.remove_at(at + 1)
		if take < mover_units:
			# Part of it goes on; a twin keeps the rest coming here (and stays in the
			# list for a later loss from this cell).
			var rest := _movers.split(mover, mover_units - take, _clock)
			if rest < 0:
				coming.insert(at + 1, mover)
				continue
			coming.append(rest)
		_view.call("claim", src, -take)
		if dst.x >= 0:
			_view.call("claim", dst, take)
			_movers.retarget(mover, dst.x + dst.y * _grid.x, _aim_for(dst, mover))
		else:
			_movers.to_sink(mover, sink_kind, point)
			_counts["sink_redirects"] = int(_counts["sink_redirects"]) + 1
		left -= take
		_counts["retargets"] = int(_counts["retargets"]) + 1
	return left


## Claims units going from src to dst (either may be (-1, -1): a point instead)
## and splits them over movers; with no room left they stay unclaimed (morphed).
func _emit_movers(kind_id: int, hint: Dictionary, src: Vector2i, dst: Vector2i, total: int, per: int, point: Vector3) -> void:
	var count := mini(maxi(1, int(round(float(total) / float(per)))), _movers.free_count())
	if count <= 0:
		_counts["morph_units"] = int(_counts["morph_units"]) + total
		return
	var has_src := src.x >= 0
	var has_dst := dst.x >= 0
	if has_src:
		_view.call("claim", src, -total)
	if has_dst:
		_view.call("claim", dst, total)
	var stroke := LeafFlow._flat_dir(hint) if not hint.is_empty() else Vector3.ZERO
	var who := int(hint.get("actor", 0))
	var base := total / count
	var extra := total - base * count
	for part: int in count:
		var carried := base + (extra if part == count - 1 else 0)
		if carried <= 0:
			continue
		var from := Vector3.ZERO
		if has_src:
			from = _source_point(src, part)
		elif kind_id == LeafMovers.K_SCATTER:
			var spawn := Constants.LEAF_SCATTER_SPAWN
			from = point + Vector3(_rng.randf_range(-spawn.x, spawn.x), _rng.randf_range(spawn.y, spawn.z), _rng.randf_range(-spawn.x, spawn.x))
		else:
			var center := view_center(dst)
			var spread := Constants.LEAF_DROP_SPREAD
			from = Vector3(center.x + _rng.randf_range(-spread, spread), 0.0, center.z + _rng.randf_range(-spread, spread))
			from.y = float(_view.call("surface_y", Vector2(from.x, from.z))) + Constants.LEAF_DROP_HEIGHT
		var to := point
		if has_dst:
			to = _aim_for(dst, part)
		var timing := _schedule(kind_id, hint, from)
		var mover := _movers.add(kind_id, carried, src.x + src.y * _grid.x if has_src else -1, dst.x + dst.y * _grid.x if has_dst else -1, from, to, stroke, who, int(timing[0]), float(timing[1]), _clock)
		if mover < 0:
			# Cannot happen (count was capped by free slots); keep the books right anyway.
			if has_src:
				_view.call("claim", src, carried)
			if has_dst:
				_view.call("claim", dst, -carried)


## When a new waiting leaf goes: [rule, time]. See LeafMovers' launch rules.
func _schedule(kind_id: int, hint: Dictionary, from: Vector3) -> Array:
	var soon := _clock + _rng.randf_range(0.0, 0.08)
	if hint.is_empty():
		return [LeafMovers.R_SCHEDULED, soon]
	if not bool(hint.get("local", false)) and Net.server_time() - float(hint.get("t", Net.server_time())) > Constants.LEAF_LATE_EVENT:
		return [LeafMovers.R_SCHEDULED, soon]
	match kind_id:
		LeafMovers.K_BAG:
			return [LeafMovers.R_SCHEDULED, _clock + _rng.randf_range(0.0, Constants.LEAF_BAG_STAGGER)]
		LeafMovers.K_MULCH, LeafMovers.K_SCATTER, LeafMovers.K_EDGE, LeafMovers.K_DROP, LeafMovers.K_CORRECTION:
			return [LeafMovers.R_SCHEDULED, _clock + _rng.randf_range(0.0, 0.05)]
	var at: Vector3 = hint.get("at", from)
	var stroke := LeafFlow._flat_dir(hint)
	var who := int(hint.get("actor", 0))
	if _heads.has(who) and bool((_heads[who] as Dictionary)["down"]):
		var head: Dictionary = _heads[who]
		var rel := from - (head["mid"] as Vector3)
		var ahead := rel.dot(head["fwd"] as Vector3)
		if ahead <= 0.0:
			# Behind the tines already (bite B's near leaves, an observer's late batch):
			# swept up over a moment, so the litter thins rather than blinks out, and
			# they slide along the lawn into the windrow while the tines still drive
			# (rakefeel:look) instead of hopping off on their own.
			return [LeafMovers.R_SCHEDULED, _clock + _rng.randf_range(0.0, Constants.RAKE_SWEEP_STAGGER)]
		var side := absf(rel.dot(head["right"] as Vector3))
		var rule := LeafMovers.R_TINE if side <= float(head["half"]) + Constants.LEAF_HEAD_SIDE else LeafMovers.R_BESIDE
		return [rule, _clock + Constants.LEAF_MOVER_WAIT_MAX]
	# No head to read (blower, a crew hand without a posed rake, a far raker): a
	# pressure wave from the back of the stroke forward.
	var along := (from - at).dot(stroke)
	var wave := clampf((along + 1.6) / Constants.LEAF_SWEEP_SPEED, 0.0, 0.3)
	return [LeafMovers.R_SCHEDULED, _clock + wave + _rng.randf_range(0.0, 0.05)]


## Where in a source cell a leaf starts from (its top flake, roughly; launch asks the view).
func _source_point(cell: Vector2i, salt: int) -> Vector3:
	var center := view_center(cell)
	var hash := LeafFlow.hash(cell.x, cell.y, salt + 31)
	center.x += (float(hash & 255) / 255.0 - 0.5) * 0.4
	center.z += (float((hash >> 8) & 255) / 255.0 - 0.5) * 0.4
	center.y = float(_view.call("surface_y", Vector2(center.x, center.z)))
	return center


## Where a leaf aims for in its destination cell before it knows its slot.
func _aim_for(cell: Vector2i, salt: int) -> Vector3:
	var center := view_center(cell)
	var hash := LeafFlow.hash(cell.x, cell.y, salt + 977)
	center.x += (float(hash & 255) / 255.0 - 0.5) * 0.4
	center.z += (float((hash >> 8) & 255) / 255.0 - 0.5) * 0.4
	center.y = float(_view.call("surface_y", Vector2(center.x, center.z)))
	return center


func _hint_of(index: int) -> Dictionary:
	if index < 0 or index >= _hints.size():
		return {}
	return _hints[index]


func _prune_hints() -> void:
	var kept: Array = []
	for hint: Dictionary in _hints:
		if float(hint["_until"]) >= _clock:
			kept.append(hint)
	_hints = kept


## The pool is full: the oldest airborne leaves land quickly to make room.
func _rush_oldest(count: int) -> void:
	var flying: Array = []
	var ages := _movers.age
	var states := _movers.state
	for i: int in _movers.alive:
		if states[i] == LeafMovers.FLY or states[i] == LeafMovers.SLIDE:
			flying.append(i)
	flying.sort_custom(func(a: int, b: int) -> bool: return ages[a] > ages[b])
	for index: int in mini(count, flying.size()):
		_movers.rush(int(flying[index]))


func _physics_process(delta: float) -> void:
	if not _attached:
		return
	var started := Time.get_ticks_usec()
	_clock += delta
	_read_heads(delta)
	if Constants.LEAF_WORLD_RAYS_PER_TICK > 0:
		_movers.space = get_world_3d().direct_space_state
		_movers.rays_per_tick = Constants.LEAF_WORLD_RAYS_PER_TICK
	_kicks(delta)
	_movers.step(delta, _clock, _heads, _fars)
	_settle_sounds()
	_counts["movers_peak"] = maxi(int(_counts["movers_peak"]), _movers.alive_count())
	var ms := float(Time.get_ticks_usec() - started) / 1000.0
	_sim_ms[_sim_next % SIM_SAMPLES] = ms
	_sim_next += 1
	# Over budget on this machine (on average): later batches get fewer, heavier movers.
	if _movers.alive_count() > 0:
		_sim_ema = lerpf(_sim_ema, ms, 0.05)
		_perf_scale = clampf(_perf_scale * (0.98 if _sim_ema > Constants.LEAF_MOTION_MS else 1.01), 0.3, 1.0)


## The posed rakes this frame (contract C4), and when each one finished its drive.
func _read_heads(delta: float = 0.0) -> void:
	var last := _heads.duplicate()
	_heads.clear()
	for node: Node in get_tree().get_nodes_in_group("rake_heads"):
		if not node.has_meta("actor") or not node.has_meta("head_a"):
			continue
		var who := int(node.get_meta("actor"))
		var a: Vector3 = node.get_meta("head_a")
		var b: Vector3 = node.get_meta("head_b", a)
		var fwd: Vector3 = node.get_meta("drive_dir", Vector3.FORWARD)
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
		var right := (b - a)
		right.y = 0.0
		right = right.normalized() if right.length() > 0.01 else fwd.cross(Vector3.UP)
		var down := bool(node.get_meta("down", false)) and float(node.get_meta("phase", -1.0)) >= 0.0
		var mid := (a + b) * 0.5
		# Two poses for one actor (a stowed rake and a swinging one): the lowered one wins.
		if _heads.has(who) and bool((_heads[who] as Dictionary)["down"]) and not down:
			continue
		# How fast the head moves (the windrow it shoves carries on with it).
		var vel := Vector3.ZERO
		if last.has(who) and delta > 0.0:
			var before: Dictionary = last[who]
			var moved := mid - (before["mid"] as Vector3)
			# Rakes are posed per frame, this runs per tick: a tick with no new pose
			# keeps the speed it had.
			vel = before.get("vel", Vector3.ZERO) if moved.length() < 0.00001 else moved / delta
			if vel.length() > 20.0:
				vel = Vector3.ZERO
		_heads[who] = {"mid": mid, "fwd": fwd, "right": right, "half": float(node.get_meta("half_width", a.distance_to(b) * 0.5)), "down": down, "vel": vel}
		if bool(_was_down.get(who, false)) and not down:
			_fars[who] = {"mid": mid, "fwd": fwd, "t": _clock}
		_was_down[who] = down


## Running through deep leaves and diving into piles: the same flakes hop up and
## come back to their own slots.
func _kicks(delta: float) -> void:
	var eye := _camera_point()
	var room := _movers.alive_count() < int(float(_movers.limit) * Constants.LEAF_KICK_POOL_SHARE)
	for node: Node in get_tree().get_nodes_in_group("players"):
		var body := node as Node3D
		if body == null:
			continue
		var at := body.global_position
		var key := str(node.name)
		var record: Dictionary = _players.get(key, {"at": at, "pile": false, "budget": 0.0, "sound": -1.0, "heard": 0})
		var velocity := (at - (record["at"] as Vector3)) / maxf(delta, 0.0001)
		record["at"] = at
		var pile := bool(node.get("in_pile"))
		var near := eye == Vector3.INF or at.distance_to(eye) <= Constants.LEAF_KICK_RANGE
		if pile and not bool(record["pile"]) and near and room:
			var thrown := 0
			for _try: int in Constants.LEAF_DIVE_LEAVES * 2:
				if thrown >= Constants.LEAF_DIVE_LEAVES:
					break
				var reach := Constants.LEAF_DIVE_RADIUS
				var spot := at + Vector3(_rng.randf_range(-reach, reach), 0.0, _rng.randf_range(-reach, reach))
				if _kick_at(spot, velocity * 0.2 + Vector3(0.0, 1.0, 0.0), 1):
					thrown += 1
			if thrown > 0:
				_counts["dives"] = int(_counts["dives"]) + 1
				_kick_sound(record, at, thrown)
		record["pile"] = pile
		var speed := Vector2(velocity.x, velocity.z).length()
		if near and room and not pile and speed > Constants.LEAF_KICK_SPEED and speed < Constants.LEAF_KICK_SPEED_MAX:
			record["budget"] = float(record["budget"]) + float(Constants.LEAF_KICK_PER_SEC) * delta
			var thrown := 0
			while float(record["budget"]) >= 1.0:
				record["budget"] = float(record["budget"]) - 1.0
				var ahead := Vector3(velocity.x, 0.0, velocity.z).normalized() * 0.25
				if _kick_at(at + ahead + Vector3(_rng.randf_range(-0.3, 0.3), 0.0, _rng.randf_range(-0.3, 0.3)), velocity, 0):
					thrown += 1
			if thrown > 0:
				_kick_sound(record, at, thrown)
		else:
			record["budget"] = 0.0
		_players[key] = record


## Kicks one flake near a point if the leaves there are deep. True when one flew.
func _kick_at(spot: Vector3, push: Vector3, salt: int) -> bool:
	if _movers.free_count() <= 0:
		return false
	var cell: Vector2i = _view.call("cell_of", spot)
	if cell.x < 0 or cell.y < 0 or cell.x >= _grid.x or cell.y >= _grid.y:
		return false
	var units := int(_view.call("displayed_units", cell))
	if units < Constants.LEAF_KICK_DENSITY:
		return false
	var heroes := int(_view.call("hero_count", units))
	var taken := _kicked_slots(cell)
	for offset: int in heroes:
		var k := heroes - 1 - ((offset + salt) % heroes)
		if taken.has(k):
			continue
		if _movers.add_kick(cell, k, push, _clock) >= 0:
			_counts["kicks"] = int(_counts["kicks"]) + 1
			return true
		return false
	return false


func _kicked_slots(cell: Vector2i) -> Dictionary:
	var out: Dictionary = {}
	var index := cell.x + cell.y * _grid.x
	var kinds := _movers.kind
	var srcs := _movers.src
	var slots := _movers.slot
	for i: int in _movers.alive:
		if kinds[i] == LeafMovers.K_KICK and srcs[i] == index:
			out[slots[i]] = true
	return out


func _kick_sound(record: Dictionary, at: Vector3, count: int) -> void:
	if _clock - float(record["sound"]) < 1.0 / Constants.LEAF_KICK_SOUNDS_PER_SEC:
		return
	record["sound"] = _clock
	get_tree().call_group("leaf_audio", "on_kick", at, count)


## Landings heard in bins (contract C5): where, how many, onto a pile or not.
func _settle_sounds() -> void:
	for landing: Array in _movers.landings:
		var at: Vector3 = landing[0]
		var key := Vector2i(int(floor(at.x / Constants.LEAF_SETTLE_AREA)), int(floor(at.z / Constants.LEAF_SETTLE_AREA)))
		if _settle.is_empty():
			_settle_until = _clock + Constants.LEAF_SETTLE_WINDOW
		var bin: Array = _settle.get(key, [Vector3.ZERO, 0, false])
		bin[0] = (bin[0] as Vector3) + at
		bin[1] = int(bin[1]) + 1
		var cell := Vector2i(int(landing[1]) % _grid.x, int(landing[1]) / _grid.x)
		if int(_view.call("displayed_units", cell)) >= Constants.LEAF_PILE_WHUMP_DENSITY:
			bin[2] = true
		_settle[key] = bin
	if _settle.is_empty() or _clock < _settle_until:
		return
	for key: Vector2i in _settle:
		var bin: Array = _settle[key]
		get_tree().call_group("leaf_audio", "on_settled", (bin[0] as Vector3) / float(bin[1]), int(bin[1]), bool(bin[2]))
	_settle.clear()


## W13 weather: a gust lifts loose flakes in an area and drops them back where they lay.
func spawn_gust(area: Rect2, dir: Vector3, strength: float) -> void:
	if not _attached:
		return
	_counts["gusts"] = int(_counts["gusts"]) + 1
	var tries := int(clampf(strength * Constants.LEAF_GUST_TRIES.x, 1.0, Constants.LEAF_GUST_TRIES.y))
	for _try: int in tries:
		if _movers.alive_count() >= int(float(_movers.limit) * Constants.LEAF_KICK_POOL_SHARE):
			return
		var spot := Vector3(area.position.x + _rng.randf() * area.size.x, 0.0, area.position.y + _rng.randf() * area.size.y)
		var cell: Vector2i = _view.call("cell_of", spot)
		if cell.x < 0 or cell.y < 0 or cell.x >= _grid.x or cell.y >= _grid.y:
			continue
		var heroes := int(_view.call("hero_count", int(_view.call("displayed_units", cell))))
		if heroes <= 0:
			continue
		var k := heroes - 1
		if not _kicked_slots(cell).has(k):
			_movers.add_kick(cell, k, dir * strength * 3.0, _clock)


func _camera_point() -> Vector3:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	return camera.global_position if camera != null else Vector3.INF


func _detail_preset() -> String:
	var settings := get_node_or_null("/root/Settings")
	if settings != null and settings.has_method("get_value"):
		var preset := str(settings.call("get_value", "video", "preset"))
		if Constants.LEAF_DETAIL.has(preset):
			return preset
	return "high"


func clock() -> float:
	return _clock


## Units each cell will still receive less what waiting leaves will take out
## (cell index -> units), for tests: it equals the view's pending claims.
func ledger() -> Dictionary:
	return _movers.ledger()


func kick_count() -> int:
	return _movers.kick_count()


## Tests: run as if the pool were this small (a lower video preset's cap); 0 resets.
func set_pool_limit(count: int) -> void:
	_movers.limit = _cap if count <= 0 else mini(count, _cap)


func set_trace(on: bool) -> void:
	_movers.trace = on
	_movers.finished.clear()
	_movers.tine_launches.clear()


## {finished: [{kind, start, end, dir, age, rule, dst, units}], tine_launches: [{t, at, actor}]}
func trace() -> Dictionary:
	return {"finished": _movers.finished.duplicate(), "tine_launches": _movers.tine_launches.duplicate()}


func stats() -> Dictionary:
	var samples: Array[float] = []
	for index: int in mini(_sim_next, SIM_SAMPLES):
		samples.append(_sim_ms[index])
	samples.sort()
	var average := 0.0
	for sample: float in samples:
		average += sample
	average = average / float(samples.size()) if not samples.is_empty() else 0.0
	var p99 := samples[int(float(samples.size() - 1) * 0.99)] if not samples.is_empty() else 0.0
	var out := _counts.duplicate()
	out.merge({
		"movers_alive": _movers.alive_count(),
		"waiting": _movers.count_state(LeafMovers.WAIT),
		"parked": _movers.count_state(LeafMovers.PARK),
		"airborne_kicks": _movers.kick_count(),
		"launched": _movers.launched,
		"rode": _movers.rode,
		"riding": _movers.count_state(LeafMovers.RIDE),
		"landed": _movers.landed,
		"sunk": _movers.sinks_done,
		"snaps": _movers.snaps,
		"pops": _movers.pops,
		"max_step": _movers.max_step,
		"max_snap": _movers.max_snap,
		"max_handoff": _movers.max_handoff,
		"max_age": _movers.max_age,
		"kick_handovers": _movers.handovers,
		"kicks_faded": _movers.kicks_faded,
		"overdrawn": _movers.overdrawn,
		"rays": _movers.rays,
		"ray_hits": _movers.ray_hits,
		"sim_ms_avg": average,
		"sim_ms_p99": p99,
		"perf_scale": _perf_scale,
		"cap": _cap,
		"pool_limit": _movers.limit,
		"range": _range,
	})
	return out
