extends Node3D

## Authority: host
## Density grid for one lot. The host's bytes are the only truth. Everything on top
## is told, never stepped (raking:1, docs/NETCODE.md "Leaf field"):
## - stroke_event: every stroke exactly once on every peer, in the frame its
##   density changes (the host's own apply, the raking client's own prediction,
##   everyone else on receipt of _rpc_stroke_event), empty strokes included.
## - _rpc_chunk_batch: one send tick's changed chunks in one reliable RPC, numbered.
## - the raking client's prediction ledger: its unconfirmed strokes replayed over
##   the host's bytes after every batch, so a late confirmation never snaps back.
## The density rules themselves (_stroke_cells, the windrow since rakefeel:field;
## _apply_collect and host_scatter's maths, 0.4.5's) are held by net/dev/leaf_golden.gd.
## OQ-004: cleaned_fraction() counts leaf units removed by collect, not leaves merely raked into a pile.

signal chunk_changed(chunk_index: int)
## One stroke, once per peer (keys in net/leaf_field/stroke_event.gd, contract C1).
signal stroke_event(ev: Dictionary)
## The whole field was replaced: hard (a new lot, a join) snaps, soft (a resync
## after an out-of-reach stroke or a refused bag) may be animated. Emitted before
## that frame's leaves_changed.
signal field_reset(hard: bool)
## Deferred, once per frame, for each chunk whose bytes on this peer really changed
## since the last time (host applies, predictions, recomposes, batches, snapshots).
signal leaves_changed(chunk_index: int)
## units is how much leaf density went into the bag, which sets its value.
signal bag_requested(at: Vector3, units: int)
## Why a bag didn't happen: "thin" (rake a pile first) or "no_bags" (the crew's
## out of lawn and contractor bags; Shops' supplies).
signal bag_refused(peer_id: int, reason: String)

const CHUNK_SIZE: int = 16
## A fresh lot starts thin enough that a raked pile can grow about four times
## denser (cells hold up to 255), so piling leaves up before bagging pays.
const INITIAL_DENSITY: int = 60
## OQ-004: a cell counts as cleaned once it is raked or bagged down to this density.
const CLEAN_DENSITY: int = 8
const REACH_METERS: float = 3.5
const SEND_INTERVAL: float = 0.1
const _Economy = preload("res://core/economy.gd")
const _ToolTiers = preload("res://core/tool_tiers.gd")
## Bag types, in the order they're used: contractor bags scoop wider
## (Constants.BIG_BAG_RADIUS_SCALE), then plain lawn bags. Shops supply ids.
const BAG_SUPPLIES: Array[String] = ["big_bags", "lawn_bags"]
## The stroke kinds a player's own request makes: their host echo is an ack, not news.
const OWN_KINDS: Array[String] = ["rake", "hand", "blower", "bag"]
const _StrokeEvent = preload("res://net/leaf_field/stroke_event.gd")

@export var cell_size: float = 0.5
@export var grid_width: int = 80
@export var grid_depth: int = 80
## Minimum corner of the grid in this node's local space. X and Z are the ground axes.
@export var grid_origin: Vector3 = Vector3(-20, 0.05, -20)

var _density := PackedByteArray()
var _versions := PackedInt32Array()
var _unit_scale: float = 1.0
var _starting_units: float = 0.0
var _removed_units: float = 0.0
var _dirty: Dictionary = {}
var _send_wait: float = 0.0
var _chunks_x: int = 0
var _chunks_z: int = 0
## Cells that start clean (under a house, on a path), not counted as raked.
var _clean_at_start: int = 0
## A field for checking rules only (net/dev/leaf_golden.gd, test references): set
## before it enters the tree; it joins no group and never talks to a peer.
var scratch: bool = false

# Host: the number of the last chunk batch sent (a stroke's ack_tick is the next one).
var _send_tick: int = 0
# Host: each running mower's mulch since the last batch, {key: {moved, at, radius}}.
var _mulch: Dictionary = {}
# Each raker's last stroke, {actor: [grid-local xz, 8-way step]}, for the drag
# (_stroke_drag): the host's for everyone (hired hands too), a client's for itself.
var _last_strokes: Dictionary = {}

# Client prediction ledger. _confirmed is the host's bytes as the batches left
# them; _pending this peer's strokes the host hasn't confirmed yet, in request
# order: {seq, op ("rake" | "collect"), args, ack_tick (-1 unknown), msec}.
# _density == _confirmed + _pending replayed, always.
var _confirmed := PackedByteArray()
var _pending: Array[Dictionary] = []
var _seq: int = 0
# Requests this peer sent without predicting them ({seq: msec}): their echo is news.
var _unpredicted: Dictionary = {}
var _had_snapshot: bool = false
# Client: the tick of the newest batch applied.
var _last_tick: int = 0
var _replaying: bool = false

# What leaves_changed last reported, and the chunks touched since.
var _flushed := PackedByteArray()
var _view_dirty: Dictionary = {}
var _flush_queued: bool = false

var _stats: Dictionary = {
	"pending_peak": 0, "recomposes": 0, "recompose_changes": 0, "timeouts": 0, "dropped_full": 0,
	"events_out": 0, "events_in": 0, "acks": 0, "mulch_events": 0, "batches_out": 0, "batches_in": 0,
	"batch_bytes_out": 0, "batch_chunks_out": 0, "resets_hard": 0, "resets_soft": 0, "snapshots_in": 0, "snapshot_hard": 0,
	"kept_on_resync": 0,
}


func _ready() -> void:
	# Mulch events ride the send tick (_flush_mulch), so it sets their rate.
	assert(SEND_INTERVAL >= Constants.LEAF_EVENT_MULCH_SECONDS)
	if not scratch:
		add_to_group("leaf_field")
	_chunks_x = int(ceil(float(grid_width) / float(CHUNK_SIZE)))
	_chunks_z = int(ceil(float(grid_depth) / float(CHUNK_SIZE)))
	_density.resize(grid_width * grid_depth)
	_density.fill(INITIAL_DENSITY)
	_confirmed = _density.duplicate()
	_flushed = _density.duplicate()
	_versions.resize(_chunks_x * _chunks_z)
	var total_density := grid_width * grid_depth * INITIAL_DENSITY
	_unit_scale = Balance.STARTING_LOT_LEAF_VOLUME / float(total_density)
	_starting_units = leaf_units()
	if scratch:
		return
	if Net.is_host():
		if not Net.player_joined.is_connected(_on_player_joined):
			Net.player_joined.connect(_on_player_joined)
	else:
		_rpc_request_snapshot.rpc_id(1)


func _process(delta: float) -> void:
	if not Net.is_host():
		_expire_predictions()
	_send_wait += delta
	if _send_wait < SEND_INTERVAL or _dirty.is_empty():
		return
	_send_wait = 0.0
	var indices := PackedByteArray()
	var versions := PackedInt32Array()
	var data := PackedByteArray()
	var host := Net.is_host()
	for key: Variant in _dirty.keys():
		var chunk_index := int(key)
		if host:
			_versions[chunk_index] += 1
			indices.append(chunk_index)
			versions.append(_versions[chunk_index])
			data.append_array(_chunk_bytes(chunk_index))
	# One RPC per send tick, so a stroke's chunks never arrive split; every stroke
	# event of this tick went out before it on the same reliable channel.
	if host:
		# The mulch since the last batch is told now, with this batch's tick, so
		# its event always goes out ahead of the bytes it describes.
		_flush_mulch()
		_send_tick += 1
		if not scratch:
			var compressed := data.size() > Constants.LEAF_BATCH_COMPRESS_BYTES
			var payload := data.compress(FileAccess.COMPRESSION_DEFLATE) if compressed else data
			_rpc_chunk_batch.rpc(_send_tick, indices, versions, payload, compressed)
			_stats["batches_out"] = int(_stats["batches_out"]) + 1
			_stats["batch_bytes_out"] = int(_stats["batch_bytes_out"]) + payload.size() + indices.size() * 5 + 9
			_stats["batch_chunks_out"] = int(_stats["batch_chunks_out"]) + indices.size()
	# The batch RPC is call_remote, so the host rebuilds its own meshes here; a
	# client's are its predictions and recomposes.
	for key: Variant in _dirty.keys():
		chunk_changed.emit(int(key))
	_dirty.clear()


## How many leaf units are still on the field.
func leaf_units() -> float:
	var total := 0
	for byte: int in _density:
		total += byte
	return float(total) * _unit_scale


func clean_density() -> int:
	return CLEAN_DENSITY


## OQ-004: share of cells raked or bagged down to CLEAN_DENSITY. Pushing leaves into a pile clears the cells you raked.
func cleaned_fraction() -> float:
	var total := grid_width * grid_depth - _clean_at_start
	if total <= 0:
		return 0.0
	var clean := -_clean_at_start
	for byte: int in _density:
		if byte <= CLEAN_DENSITY:
			clean += 1
	return clampf(float(clean) / float(total), 0.0, 1.0)


## Every peer, right after the lot is generated, the same way from the job's seed:
## how thick the leaves start at each spot. multiplier(world position) scales
## INITIAL_DENSITY there: thicker under trees, none under the house. The host's
## field is the truth from then on, as always.
func shape_initial(multiplier: Callable) -> void:
	var scale := Vector3(cell_size, 0.0, cell_size)
	_clean_at_start = 0
	for z: int in grid_depth:
		for x: int in grid_width:
			var local := grid_origin + Vector3((float(x) + 0.5) * scale.x, 0.0, (float(z) + 0.5) * scale.z)
			var value := clampi(int(round(float(INITIAL_DENSITY) * float(multiplier.call(global_transform * local)))), 0, 255)
			_density[x + z * grid_width] = value
			if value <= CLEAN_DENSITY:
				_clean_at_start += 1
	_starting_units = leaf_units()
	for chunk_index: int in chunk_count():
		chunk_changed.emit(chunk_index)
	# A new lot: whatever this peer predicted belonged to the last one.
	_confirmed = _density.duplicate()
	_pending.clear()
	_unpredicted.clear()
	_mulch.clear()
	_last_strokes.clear()
	_reset_view(true)


func chunk_count() -> int:
	return _chunks_x * _chunks_z


## Density 0-255 at a cell. Out of range is 0.
func density_at_cell(x: int, z: int) -> int:
	if x < 0 or z < 0 or x >= grid_width or z >= grid_depth:
		return 0
	return int(_density[x + z * grid_width])


## Local-space center of a cell, with density in the Z component's spare... use a Vector3 of (local_x, density, local_z).
func chunk_cells(chunk_index: int) -> Array[Vector3]:
	var cells: Array[Vector3] = []
	var origin := _chunk_origin(chunk_index)
	for dz: int in CHUNK_SIZE:
		for dx: int in CHUNK_SIZE:
			var x := origin.x + dx
			var z := origin.y + dz
			var density := density_at_cell(x, z)
			if density <= 0:
				continue
			var center := _cell_center(x, z)
			cells.append(Vector3(center.x, float(density), center.y))
	return cells


## Move density from cells under the rake to the cells ahead of it. bite (0 the
## plant bite, 1 mid-drive) and tempo (the swing's seconds) only ride along on the
## stroke event. Returns the density moved: the host's real number, or this
## client's prediction (0 when it couldn't predict; the host's echo then tells).
func request_rake(origin: Vector3, direction: Vector3, width: float, strength: float, bite: int = 0, tempo: float = 0.0) -> int:
	if not _inside_grid(origin):
		return 0
	var me := Net.local_peer_id()
	if Net.is_host():
		return _handle_rake(me, origin, direction, width, strength, 0, bite, tempo)
	var seq := _next_seq()
	var moved := 0
	# Every request this peer sends counts for the drag, as the host counts every one it gets.
	var drag := _stroke_drag(me, origin, direction)
	if _player_in_reach(me, origin):
		# The host's own numbers for this tool, so the confirmation matches.
		var params := _stroke_params(me, width, strength)
		var rule_bite := bite if str(params["kind"]) == "rake" else -1
		moved = _stroke_cells(origin, direction, float(params["width"]), float(params["strength"]), int(params["cells"]), drag, rule_bite)
		_push_pending(seq, "rake", [origin, direction, float(params["width"]), float(params["strength"]), int(params["cells"]), drag, rule_bite])
		_emit_stroke(str(params["kind"]), me, origin, direction, float(params["width"]), int(params["cells"]), moved, seq, bite, tempo)
	else:
		_unpredicted[seq] = Time.get_ticks_msec()
	_rpc_request_rake.rpc_id(1, origin, direction, width, strength, seq, bite, tempo)
	return moved


## Remove density around a point. This is what currently counts as cleaned.
## Returns what was bagged (on a client, what it predicts; 0 when it didn't).
func request_collect(origin: Vector3, radius: float) -> int:
	if not _inside_grid(origin):
		return 0
	var me := Net.local_peer_id()
	if Net.is_host():
		return _handle_collect(me, origin, radius, 0)
	var seq := _next_seq()
	var removed := 0
	# No bags left (as far as this peer has heard), or too thin to fill one: the
	# host will refuse it, so there's nothing to predict.
	var supply_id := bag_type()
	if _player_in_reach(me, origin) and supply_id != "":
		var scoop := bag_radius(supply_id, minf(radius, Constants.BAG_RADIUS))
		if _units_within(origin, scoop) >= int(Constants.MIN_BAG_CELLS * INITIAL_DENSITY):
			removed = _apply_collect(origin, scoop, false)
			_push_pending(seq, "collect", [origin, scoop])
			if removed > 0:
				_emit_stroke("bag", me, origin, Vector3.ZERO, scoop * 2.0, 0, removed, seq)
	if removed <= 0:
		_unpredicted[seq] = Time.get_ticks_msec()
	_rpc_request_collect.rpc_id(1, origin, radius, seq)
	return removed


## Which bag the next pile goes in: "big_bags" while the crew has contractor
## bags, else "lawn_bags", or "" when it's out of both. Any peer (supplies
## replicate); a scene with no Shops node never runs out.
func bag_type() -> String:
	var shops := get_tree().get_first_node_in_group("shops")
	if shops == null:
		return "lawn_bags"
	for supply_id: String in BAG_SUPPLIES:
		if float(shops.call("supply", supply_id)) >= 1.0:
			return supply_id
	return ""


## How wide a bag of this type scoops.
static func bag_radius(supply_id: String, radius: float) -> float:
	return radius * (Constants.BIG_BAG_RADIUS_SCALE if supply_id == "big_bags" else 1.0)


## Host: use up one bag of this type from the crew's supply. True when it was there.
func _take_bag(supply_id: String) -> bool:
	var shops := get_tree().get_first_node_in_group("shops")
	if shops == null:
		return true
	return bool(shops.call("consume", supply_id, 1.0))


## Host: a hired hand's rake stroke (npcs/crew_hand.gd). A real rake, at the
## hand's skill; nobody's contribution stats (hands are paid wages instead).
## actor names the hand on its stroke events (Constants.RAKE_ACTOR_HAND_BASE + N
## for "HandN", raking:4); 0 when the caller doesn't say.
func host_hand_rake(origin: Vector3, direction: Vector3, skill: float, actor: int = 0) -> int:
	if not Net.is_host() or not _inside_grid(origin):
		return 0
	# A hand's swing bites once: a whole drive, dragged since its last one.
	var drag := _stroke_drag(actor if actor != 0 else -1, origin, direction)
	var moved := _stroke_cells(origin, direction, Constants.RAKE_WIDTH, Constants.RAKE_STRENGTH * clampf(skill, 0.3, 1.0), Constants.RAKE_STROKE_CELLS, drag)
	# Every stroke is told, an empty one too: the hand's swing and scrape still happen.
	_emit_stroke("crew_rake", actor, origin, direction, Constants.RAKE_WIDTH, Constants.RAKE_STROKE_CELLS, moved)
	if moved > 0:
		var flat := Vector3(direction.x, 0.0, direction.z).normalized()
		_turn_out(origin + flat * cell_size * 2.0, Constants.PILE_HIDE_RADIUS + 1.2)
	return moved


## Host: a hired hand bags the pile here and carries it off (no bag prop: the
## hand takes it straight to Chefty). Returns the units bagged, 0 if too thin.
func host_hand_collect(origin: Vector3, actor: int = 0) -> int:
	if not Net.is_host() or not _inside_grid(origin):
		return 0
	# Hands bag with the crew's bags too: contractor bags first, none when it's out.
	var supply_id := bag_type()
	if supply_id == "":
		return 0
	var radius := bag_radius(supply_id, Constants.BAG_RADIUS)
	if _units_within(origin, radius) < int(Constants.MIN_BAG_CELLS * INITIAL_DENSITY):
		return 0
	if not _take_bag(supply_id):
		return 0
	var removed := _apply_collect(origin, radius, false)
	# R2:3 a hand bagging the pile someone's hiding in turns them out.
	_turn_out(origin, radius + Constants.PILE_HIDE_RADIUS)
	_removed_units += float(removed) * _unit_scale
	if removed > 0:
		_emit_stroke("crew_bag", actor, origin, Vector3.ZERO, radius * 2.0, 0, removed)
	return removed


## Leaf units within radius of a world position (what a pile is made of).
func units_within_world(world_position: Vector3, radius: float) -> int:
	return _units_within(world_position, radius)


## True when the leaves here are thick enough to dive into (Constants.PILE_HIDE_UNITS).
func is_pile_at(world_position: Vector3) -> bool:
	return _inside_grid(world_position) and _units_within(world_position, Constants.PILE_HIDE_RADIUS) >= Constants.PILE_HIDE_UNITS


## The local player dives into the pile they stand on. The host checks it's a
## pile, notes whether a NICE BOY watched, and tells them they're in.
func request_pile_hide() -> void:
	if Net.is_host():
		_handle_pile_hide(Net.local_peer_id())
	else:
		_rpc_request_pile_hide.rpc_id(1)


func _handle_pile_hide(peer_id: int) -> void:
	var player := _player_node(peer_id)
	if player == null or not is_pile_at(player.global_position):
		return
	var seen := false
	for crew: Node in get_tree().get_nodes_in_group("crew"):
		if bool(crew.call("can_see_peer", peer_id)):
			seen = true
	player.set_meta("pile_seen", seen)
	_tell_pile(peer_id, true)


## Host: a rake stroke or a mower through a pile turns out whoever's in it.
func _turn_out(origin: Vector3, radius: float) -> void:
	for node: Node in get_tree().get_nodes_in_group("players"):
		var player := node as Node3D
		if player != null and bool(player.get("in_pile")) and player.global_position.distance_to(origin) <= radius:
			_tell_pile(player.name.to_int(), false)


func _tell_pile(peer_id: int, hidden: bool) -> void:
	if peer_id == Net.local_peer_id():
		_player_node(peer_id).call("set_pile", hidden)
	else:
		_player_node(peer_id).rpc_id(peer_id, "_rpc_pile", hidden)


func _player_node(peer_id: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node as Node3D
	return null


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_pile_hide() -> void:
	if Net.is_host():
		_handle_pile_hide(multiplayer.get_remote_sender_id())


## Density at the cell under a world position. Smoke tests compare this on both peers.
func sample_world(world_position: Vector3) -> int:
	var cell := _cell_at(world_position)
	return density_at_cell(cell.x, cell.y)


func _on_player_joined(peer_id: int) -> void:
	if peer_id != Net.local_peer_id():
		_send_snapshot(peer_id, true)


## Host: what a stroke by this peer really does with the width and strength it
## asked for, from the tool in its hands; the raking client predicts with the very
## same function, so a confirmation matches its prediction. {kind ("rake" | "hand"
## | "blower"), width, strength, cells, blower (the prop or null)}. Changes nothing.
func _stroke_params(peer_id: int, width: float, strength: float) -> Dictionary:
	# Full strength only with the job's one rake in hand. Bare hands barely move anything.
	var has_rake := holds_rake(peer_id)
	var kind := "rake" if has_rake else "hand"
	var max_strength := Constants.RAKE_STRENGTH if has_rake else Constants.HAND_RAKE_STRENGTH
	var max_width := Constants.RAKE_WIDTH if has_rake else Constants.HAND_RAKE_WIDTH
	var cells := Constants.RAKE_STROKE_CELLS if has_rake else 1
	# The field strokes as wide as the head you see: a better rake's head is wider.
	var head := rake_head_scale(peer_id) if has_rake else 1.0
	max_width *= head
	width = minf(width, Constants.RAKE_WIDTH) * head if has_rake else width
	# A leaf blower shoves leaves much farther than any rake; a better one harder
	# and wider, the Mk III farther still (core/tool_tiers.gd). An empty one is a
	# very loud-looking pair of bare hands.
	var blower := held_prop(peer_id, "leaf_blower")
	if blower != null and _ToolTiers.has_fuel(blower):
		var tier := _ToolTiers.tier_of(blower)
		var tool_scale := _ToolTiers.speed(tier)
		kind = "blower"
		max_strength = Constants.BLOWER_STRENGTH * tool_scale
		max_width = Constants.BLOWER_WIDTH * _ToolTiers.reach(tier)
		cells = _ToolTiers.blower_cells(tier)
		strength *= tool_scale
		width *= _ToolTiers.reach(tier)
	else:
		blower = null
	return {
		"kind": kind,
		"width": minf(width, max_width),
		"strength": minf(strength, max_strength) * Campaign.rake_multiplier(peer_id),
		"cells": cells,
		"blower": blower,
	}


## How much wider than the starter's this peer's rake head is
## (Constants.RAKE_HEAD_WIDTHS: the Tune-Up's, The Leafinator's), from their
## unlocks, which every peer has (props/prop_looks.gd rake_tier draws the same head).
static func rake_head_scale(peer_id: int) -> float:
	var widths := Constants.RAKE_HEAD_WIDTHS
	var tier := 0
	if Campaign.peer_has_unlock(peer_id, &"rake_tier_2"):
		tier = 2
	elif Campaign.peer_has_unlock(peer_id, &"rake_tier_1"):
		tier = 1
	tier = clampi(tier, 0, widths.size() - 1)
	return widths[tier] / widths[0]


func _handle_rake(peer_id: int, origin: Vector3, direction: Vector3, width: float, strength: float, seq: int = 0, bite: int = 0, tempo: float = 0.0) -> int:
	# Every request counts for the drag, refused ones too (the client counts every one it sends).
	var drag := _stroke_drag(peer_id, origin, direction)
	if not _player_in_reach(peer_id, origin):
		_send_snapshot(peer_id, false, seq)
		return 0
	var params := _stroke_params(peer_id, width, strength)
	var blower: Node = params["blower"]
	if blower != null:
		blower.call("mark_spraying")
	# Only a rake's own bites are part-drives; hands and the blower always push a whole one.
	var rule_bite := bite if str(params["kind"]) == "rake" else -1
	var moved := _stroke_cells(origin, direction, float(params["width"]), float(params["strength"]), int(params["cells"]), drag, rule_bite)
	# Every accepted stroke is told, an empty one too (a swing and a scrape on bare grass).
	_emit_stroke(str(params["kind"]), peer_id, origin, direction, float(params["width"]), int(params["cells"]), moved, seq, bite, tempo)
	if moved <= 0:
		return 0
	Campaign.record_stat(peer_id, &"leaves_cleared", float(moved) * _unit_scale)
	# Raking through a pile someone's hiding in turns them out.
	var flat := Vector3(direction.x, 0.0, direction.z).normalized()
	_turn_out(origin + flat * cell_size * 2.0, Constants.PILE_HIDE_RADIUS + 1.2)
	return moved


func _handle_collect(peer_id: int, origin: Vector3, radius: float, seq: int = 0) -> int:
	if not _player_in_reach(peer_id, origin):
		_send_snapshot(peer_id, false, seq)
		return 0
	# Every pile takes a bag from the crew's supply: contractor bags first (they
	# scoop wider), then lawn bags. Out of both, nothing is bagged.
	var supply_id := bag_type()
	if supply_id == "":
		_refuse_bag(peer_id, "no_bags", seq)
		return 0
	var scoop := bag_radius(supply_id, minf(radius, Constants.BAG_RADIUS))
	# Too few leaves here to fill a bag: rake a pile first. Nothing is taken.
	if _units_within(origin, scoop) < int(Constants.MIN_BAG_CELLS * INITIAL_DENSITY):
		_refuse_bag(peer_id, "thin", seq)
		return 0
	if not _take_bag(supply_id):
		_refuse_bag(peer_id, "no_bags", seq)
		return 0
	var removed := _apply_collect(origin, scoop, true)
	if removed <= 0:
		return 0
	# R2:3 bagging the pile someone's hiding in turns them out.
	_turn_out(origin, scoop + Constants.PILE_HIDE_RADIUS)
	Campaign.record_stat(peer_id, &"leaves_cleared", float(removed) * _unit_scale)
	_emit_stroke("bag", peer_id, origin, Vector3.ZERO, scoop * 2.0, 0, removed, seq)
	return removed


func _apply_collect(origin: Vector3, radius: float, count_removed: bool) -> int:
	var center := _cell_at(origin)
	var radius_cells := int(ceil(radius / cell_size)) + 1
	var removed := 0
	for dz: int in range(-radius_cells, radius_cells + 1):
		for dx: int in range(-radius_cells, radius_cells + 1):
			var cell := Vector2i(center.x + dx, center.y + dz)
			if _cell_center(cell.x, cell.y).distance_to(Vector2(_local_xz(origin).x, _local_xz(origin).y)) > radius:
				continue
			var amount := density_at_cell(cell.x, cell.y)
			if amount <= 0:
				continue
			_add_density(cell.x, cell.y, -amount)
			removed += amount
	if count_removed:
		_removed_units += float(removed) * _unit_scale
		if removed >= INITIAL_DENSITY:
			bag_requested.emit(origin, removed)
	return removed


## A bag's worth in dollars for this much leaf density: its share of what
## clearing the whole lot pays (Balance.CREDITS_PER_1_PERCENT_LOT_CLEANUP).
func dollars_for(units: int) -> int:
	var lot_density := float(grid_width * grid_depth * INITIAL_DENSITY)
	var whole_lot := float(Balance.CREDITS_PER_1_PERCENT_LOT_CLEANUP) * 100.0
	# The crew's bag perks (core/ranks.gd).
	var perks := 0
	for perk: String in ["bag_bonus", "bag_bonus_2", "bag_bonus_3"]:
		if Campaign.has_perk(perk):
			perks += 1
	var bonus := _Economy.bag_bonus(perks)
	return maxi(1, int(round(float(units) / lot_density * whole_lot * bonus)))


## One stroke, the windrow rule (rakefeel:field; docs/GAME.md "Raking: the
## windrow"). The stroke runs along its 8-way grid step; every cell is on one lane
## parallel to it. In each lane, the cells the tine line crossed (from RAKE_FIELD_BACK
## + drag behind the origin up to this bite's front, across width plus a soft
## RAKE_FIELD_EDGE) give up what they hold but a residue, front first, until the
## head holds strength x RAKE_FIELD_LOAD per 0.5 m of lane (a full head glides over
## the rest), and the lane's load lands in a berm of RAKE_FIELD_BERM shares in the cells just
## ahead of the tines (cells - RAKE_STROKE_CELLS further for the blower's throw); a
## full cell passes the rest on. Lanes never share a cell and each is read before
## it is written, so the rule is the same in every direction and in any order.
## drag: how far the head was dragged since this raker's last stroke
## (_stroke_drag). bite: 0 the plant, 1 mid-drive (RAKE_FIELD_BITE_FRONT); -1 a
## whole drive. Returns the density that moved (leaves pushed off the grid count).
func _stroke_cells(origin: Vector3, direction: Vector3, width: float, strength: float, cells: int, drag: float = 0.0, bite: int = -1) -> int:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length() < 0.001:
		return 0
	flat = flat.normalized()
	var step := _step_of(flat)
	var lane_dir := Vector2(step).normalized()
	var side := Vector2(-lane_dir.y, lane_dir.x)
	var fronts := Constants.RAKE_FIELD_BITE_FRONT
	var front := fronts[clampi(bite, 0, fronts.size() - 1)] if bite >= 0 else fronts[fronts.size() - 1]
	var back := Constants.RAKE_FIELD_BACK + clampf(drag, 0.0, Constants.RAKE_FIELD_DRAG_MAX)
	var half := width * 0.5
	var edge := Constants.RAKE_FIELD_EDGE
	var reach_side := half + edge
	# One lane every cell along an axis, every half diagonal along a diagonal: the
	# load is per metre of head either way.
	var lane_share := 0.70710678 if step.x != 0 and step.y != 0 else 1.0
	var cap := maxi(1, int(strength * Constants.RAKE_FIELD_LOAD * lane_share))
	var throw_cells := maxi(0, int(round(float(cells - Constants.RAKE_STROKE_CELLS) / Vector2(step).length())))
	# The berm passes on as far in metres every way (6 cells along an axis, 4 along a
	# diagonal), so no carry outruns LEAF_FLOW_MAX_DIST on a diagonal.
	var berm_reach := maxi(Constants.RAKE_FIELD_BERM.size(), int(round(float(Constants.RAKE_FIELD_BERM_REACH) / Vector2(step).length())))
	var here := _local_xz(origin)
	# The cells the tine line crossed, by lane.
	var corners: Array[Vector2] = [here - lane_dir * back - side * reach_side, here - lane_dir * back + side * reach_side,
		here + lane_dir * front - side * reach_side, here + lane_dir * front + side * reach_side]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for corner: Vector2 in corners:
		lo = Vector2(minf(lo.x, corner.x), minf(lo.y, corner.y))
		hi = Vector2(maxf(hi.x, corner.x), maxf(hi.y, corner.y))
	var cell_lo := Vector2i(int(floor((lo.x - grid_origin.x) / cell_size)), int(floor((lo.y - grid_origin.z) / cell_size)))
	var cell_hi := Vector2i(int(floor((hi.x - grid_origin.x) / cell_size)), int(floor((hi.y - grid_origin.z) / cell_size)))
	var lanes: Dictionary = {}
	for z: int in range(maxi(cell_lo.y, 0), mini(cell_hi.y, grid_depth - 1) + 1):
		for x: int in range(maxi(cell_lo.x, 0), mini(cell_hi.x, grid_width - 1) + 1):
			var rel := _cell_center(x, z) - here
			var along := rel.dot(lane_dir)
			if along < -back or along > front:
				continue
			var across := absf(rel.dot(side))
			if across > reach_side:
				continue
			var grip := 1.0 if across <= half else (reach_side - across) / edge
			var held := int(_density[x + z * grid_width])
			# The ends of the head catch only part of the lawn's litter. A heap they
			# push whole over the inner part of the edge (so the head's own berm never
			# leaves a trail) and less and less past it, so a pile beside your lane
			# mostly stays where it is.
			var litter := mini(held, INITIAL_DENSITY)
			var heap_grip := minf(1.0, grip * Constants.RAKE_FIELD_HEAP_GRIP)
			var offer := int(float(litter - _residue(litter)) * grip) + int(float(held - litter) * heap_grip)
			var key := step.x * z - step.y * x
			if not lanes.has(key):
				lanes[key] = []
			(lanes[key] as Array).append([x, z, step.x * x + step.y * z, offer])
	var moved := 0
	var keys: Array = lanes.keys()
	keys.sort()
	for key: Variant in keys:
		moved += _push_lane(lanes[key], step, cap, throw_cells, berm_reach)
	return moved


## One lane of a stroke: [x, z, position along the step, offer] for each crossed cell.
func _push_lane(crossed: Array, step: Vector2i, cap: int, throw_cells: int, berm_reach: int) -> int:
	var gathered := 0
	var front_cell := Vector2i(-1, -1)
	var front_at := -INF
	for entry: Array in crossed:
		gathered += int(entry[3])
		if float(entry[2]) > front_at:
			front_at = float(entry[2])
			front_cell = Vector2i(int(entry[0]), int(entry[1]))
	if gathered <= 0:
		return 0
	# The head fills from the front: the berm it's already pushing first, then the
	# litter behind, until it holds cap. A full head glides over the rest, so a
	# windrow stops growing (diminishing returns) instead of one run hauling a lane.
	var order := range(crossed.size())
	order.sort_custom(func(a: int, b: int) -> bool: return float(crossed[a][2]) > float(crossed[b][2]))
	var takes: Array[int] = []
	takes.resize(crossed.size())
	var load := 0
	for index: int in order:
		var take := mini(int(crossed[index][3]), cap - load)
		takes[index] = take
		load += take
	if load <= 0:
		return 0
	# The berm, just ahead of the tine line.
	var shares := Constants.RAKE_FIELD_BERM
	var parts: Array[int] = []
	var placed := 0
	for share: float in shares:
		var part := int(float(load) * share)
		parts.append(part)
		placed += part
	parts[0] += load - placed
	var carry := 0
	var landed := 0
	for index: int in berm_reach:
		var want := carry + (parts[index] if index < parts.size() else 0)
		if want <= 0:
			break
		var cell := front_cell + step * (1 + throw_cells + index)
		var put := want
		if cell.x >= 0 and cell.y >= 0 and cell.x < grid_width and cell.y < grid_depth:
			put = mini(want, 255 - int(_density[cell.x + cell.y * grid_width]))
			if put > 0:
				_add_density(cell.x, cell.y, put)
		# Off the grid the leaves leave the lot, as they always have.
		landed += put
		carry = want - put
	# What didn't fit ahead stays at the tine line: the frontmost crossed cells keep it.
	var kept := carry
	for index: int in order:
		var take := takes[index]
		var back_in := mini(kept, take)
		kept -= back_in
		if take - back_in > 0:
			_add_density(int(crossed[index][0]), int(crossed[index][1]), -(take - back_in))
	return landed


## What the tines leave in a cell they cross.
static func _residue(held: int) -> int:
	return mini(int(float(held) * Constants.RAKE_FIELD_RESIDUE_SHARE), Constants.RAKE_FIELD_RESIDUE_MAX)


## A direction's 8-way grid step (stroke_event's step_of: +Z when flat).
static func _step_of(flat: Vector3) -> Vector2i:
	var step := Vector2i(int(round(flat.x)), int(round(flat.z)))
	return step if step != Vector2i.ZERO else Vector2i(0, 1)


## How far this raker's head was dragged over the ground since their last stroke,
## along this one, and remember this one. Both the host (for every request it gets)
## and the raking client (for every request it sends, predicted or not) call it in
## the same order with the same origins, so their drags agree. 0 for a first
## stroke, a turn, a step back, a side-step past RAKE_FIELD_DRAG_SIDESTEP, or more
## than RAKE_FIELD_DRAG_MAX forward (the raker walked or ran on with the head up:
## a pause to bag, or a sprint, never sweeps ground the head didn't touch).
func _stroke_drag(actor: int, origin: Vector3, direction: Vector3) -> float:
	var flat := Vector3(direction.x, 0.0, direction.z)
	var here := _local_xz(origin)
	var step := _step_of(flat.normalized()) if flat.length() > 0.001 else Vector2i.ZERO
	var last: Variant = _last_strokes.get(actor)
	_last_strokes[actor] = [here, step]
	if last == null or step == Vector2i.ZERO or (last as Array)[1] != step:
		return 0.0
	var lane_dir := Vector2(step).normalized()
	var moved := here - ((last as Array)[0] as Vector2)
	if absf(moved.dot(Vector2(-lane_dir.y, lane_dir.x))) > Constants.RAKE_FIELD_DRAG_SIDESTEP:
		return 0.0
	var along := moved.dot(lane_dir)
	if along > Constants.RAKE_FIELD_DRAG_MAX:
		return 0.0
	return maxf(along, 0.0)


## Host: a running mower shreds the leaves under it. They're gone, but nobody
## bagged them, so they earn nothing. Returns how much went.
func host_mulch(at: Vector3, radius: float) -> int:
	if not Net.is_host() or not _inside_grid(at):
		return 0
	var removed := _apply_collect(at, radius, false)
	if removed > 0:
		# Mulch runs every physics tick: it's told once per send tick per mower,
		# summed, at the last spot, just ahead of the batch that carries it
		# (_flush_mulch, from _process).
		var key := _mower_key(at)
		var acc: Dictionary = _mulch.get(key, {"moved": 0})
		acc["moved"] = int(acc["moved"]) + removed
		acc["at"] = at
		acc["radius"] = radius
		_mulch[key] = acc
	_turn_out(at, radius + 0.8)
	return removed


## Host: a burst bag's leaves fall back onto the lawn around at.
func host_scatter(at: Vector3, radius: float, dollars: int) -> void:
	if not Net.is_host():
		return
	var lot_density := float(grid_width * grid_depth * INITIAL_DENSITY)
	var whole_lot := float(Balance.CREDITS_PER_1_PERCENT_LOT_CLEANUP) * 100.0
	var units := int(float(dollars) * lot_density / maxf(whole_lot, 1.0))
	var center := _cell_at(at)
	var radius_cells := int(ceil(radius / cell_size))
	var cells: Array[Vector2i] = []
	for dz: int in range(-radius_cells, radius_cells + 1):
		for dx: int in range(-radius_cells, radius_cells + 1):
			if Vector2(dx, dz).length() <= float(radius_cells):
				cells.append(Vector2i(center.x + dx, center.y + dz))
	if cells.is_empty():
		return
	var each := maxi(1, units / cells.size())
	var added := 0
	for cell: Vector2i in cells:
		# What actually lands (a full or off-grid cell takes less), for the event only.
		if cell.x >= 0 and cell.y >= 0 and cell.x < grid_width and cell.y < grid_depth:
			added += mini(each, 255 - density_at_cell(cell.x, cell.y))
		_add_density(cell.x, cell.y, each)
	_emit_stroke("scatter", 0, at, Vector3.ZERO, radius * 2.0, 0, added)


## Host: true while this peer carries a prop of this kind.
func holds_kind(peer_id: int, held_kind: String) -> bool:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) == held_kind and int(node.get("held_by")) == peer_id:
			return true
	return false


## The prop of this kind this peer has in hand, or null.
func held_prop(peer_id: int, held_kind: String) -> Node:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) == held_kind and int(node.get("held_by")) == peer_id:
			return node
	return null


## Host: the tool this peer carries ran just now, so everyone hears it.
func _mark_running(peer_id: int, held_kind: String) -> void:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) == held_kind and int(node.get("held_by")) == peer_id:
			node.call("mark_spraying")


## Host: true while this peer carries the job's rake.
func holds_rake(peer_id: int) -> bool:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) == "rake" and int(node.get("held_by")) == peer_id:
			return true
	return false


## Leaf density within radius of a point, without taking any.
func _units_within(origin: Vector3, radius: float) -> int:
	var center := _cell_at(origin)
	var radius_cells := int(ceil(radius / cell_size)) + 1
	var total := 0
	var here := _local_xz(origin)
	for dz: int in range(-radius_cells, radius_cells + 1):
		for dx: int in range(-radius_cells, radius_cells + 1):
			var cell := Vector2i(center.x + dx, center.y + dz)
			if _cell_center(cell.x, cell.y).distance_to(Vector2(here.x, here.y)) <= radius:
				total += density_at_cell(cell.x, cell.y)
	return total


## Host: no bag for this peer, and why ("thin", "no_bags"). A client's
## predicted bagging (request seq) is undone first.
func _refuse_bag(peer_id: int, reason: String, seq: int = -1) -> void:
	if peer_id == Net.local_peer_id():
		_on_bag_refused(reason)
	else:
		_send_snapshot(peer_id, false, seq)
		_rpc_bag_refused.rpc_id(peer_id, reason)


## The bagging player hears why there's no bag.
@rpc("authority", "call_remote", "reliable")
func _rpc_bag_refused(reason: String) -> void:
	_on_bag_refused(reason)


func _on_bag_refused(reason: String) -> void:
	bag_refused.emit(Net.local_peer_id(), reason)


func _add_density(x: int, z: int, delta: int) -> void:
	if x < 0 or z < 0 or x >= grid_width or z >= grid_depth:
		return
	var index := x + z * grid_width
	var next := clampi(int(_density[index]) + delta, 0, 255)
	_density[index] = next
	# A ledger replay's changes are found by comparing afterwards (_recompose).
	if _replaying:
		return
	var chunk_index := _chunk_index(x, z)
	_dirty[chunk_index] = true
	_view_dirty[chunk_index] = true
	_queue_flush()


func _chunk_bytes(chunk_index: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(CHUNK_SIZE * CHUNK_SIZE)
	var origin := _chunk_origin(chunk_index)
	var write := 0
	for dz: int in CHUNK_SIZE:
		for dx: int in CHUNK_SIZE:
			bytes[write] = density_at_cell(origin.x + dx, origin.y + dz)
			write += 1
	return bytes


## Client: one chunk of a host batch into the confirmed bytes (not the view: the
## ledger recomposes that). False when the version is older than what this peer has.
func _confirm_chunk_bytes(chunk_index: int, version: int, bytes: PackedByteArray, offset: int) -> bool:
	if chunk_index < 0 or chunk_index >= _versions.size():
		return false
	if version < _versions[chunk_index]:
		return false
	_versions[chunk_index] = version
	var origin := _chunk_origin(chunk_index)
	var read := offset
	for dz: int in CHUNK_SIZE:
		for dx: int in CHUNK_SIZE:
			var x := origin.x + dx
			var z := origin.y + dz
			if read < bytes.size() and x < grid_width and z < grid_depth:
				_confirmed[x + z * grid_width] = bytes[read]
			read += 1
	return true


## hard: a join or a new lot (everything snaps); otherwise a resync (an
## out-of-reach stroke, a refused bag) that the view may animate. upto_seq: the
## refused request's seq on a resync (the client keeps its later predictions),
## -1 to drop them all.
func _send_snapshot(peer_id: int, hard: bool = false, upto_seq: int = -1) -> void:
	# The host already has the true field; it never resyncs itself.
	if peer_id == Net.local_peer_id() or scratch:
		return
	var compressed := _density.compress(FileAccess.COMPRESSION_DEFLATE)
	_rpc_snapshot.rpc_id(peer_id, compressed, _versions.duplicate(), _removed_units, _send_tick, hard, -1 if hard else upto_seq)


# ---- stroke events

## The one place a stroke is told (contract C1). On the host: emitted here and
## sent to every client in the same frame as the density change, ahead of the
## batch that carries it (ack_tick = that batch's tick, -1 when nothing changed).
## On a predicting client: emitted here as its own (local), and nothing is sent;
## the host's echo is only an ack. driving:C3's host_plow calls this with "plow".
func _emit_stroke(kind: String, actor: int, at: Vector3, dir: Vector3, width: float, cells: int, moved: int, seq: int = 0, bite: int = 0, tempo: float = 0.0) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	# Undirected kinds (bags, mulch, scatter) say +Z, which is what the wire gives back.
	flat = flat.normalized() if flat.length() > 0.001 else Vector3.BACK
	var host := Net.is_host()
	var ev := {
		"kind": kind,
		"actor": actor,
		"seq": seq,
		"bite": bite,
		"at": at,
		"dir": flat,
		"step": _StrokeEvent.step_of(flat),
		"width": width,
		"cells": cells,
		"moved": moved,
		"tempo": tempo,
		"t": Net.server_time(),
		"ack_tick": (_send_tick + 1 if moved > 0 else -1) if host else -1,
		"local": actor == Net.local_peer_id() if host else true,
	}
	if host:
		if kind == "mulch":
			_stats["mulch_events"] = int(_stats["mulch_events"]) + 1
		if not scratch:
			_stats["events_out"] = int(_stats["events_out"]) + 1
			_rpc_stroke_event.rpc(_StrokeEvent.pack(ev))
	stroke_event.emit(ev)


## Client: a stroke the host applied. This peer's own is an ack for its ledger
## (its predicted event already played); anyone else's is news.
@rpc("authority", "call_remote", "reliable")
func _rpc_stroke_event(packed: PackedByteArray) -> void:
	if Net.is_host():
		return
	var ev := _StrokeEvent.unpack(packed)
	if ev.is_empty():
		return
	_stats["events_in"] = int(_stats["events_in"]) + 1
	var me := Net.local_peer_id()
	if int(ev["actor"]) == me and OWN_KINDS.has(str(ev["kind"])):
		var seq := int(ev["seq"])
		var ack := int(ev["ack_tick"])
		for index: int in _pending.size():
			if int(_pending[index]["seq"]) == seq:
				_stats["acks"] = int(_stats["acks"]) + 1
				_pending[index]["ack_tick"] = ack
				# Nothing will change (or the batch is already here): the prediction is done.
				if ack < 0 or ack <= _last_tick:
					_pending.remove_at(index)
					_recompose()
				break
		if _unpredicted.has(seq):
			# Not predicted here (out of reach as this peer saw it, a thin bag): this is
			# the first this peer hears of its own stroke.
			_unpredicted.erase(seq)
			ev["local"] = true
			stroke_event.emit(ev)
	else:
		stroke_event.emit(ev)


## Host, at a send tick, before _send_tick counts it: every mower's mulch since the
## last batch, one event each, whose ack_tick (_send_tick + 1) is the batch about
## to go. All of that mulch is dirty in that batch, so no mulch reaches a client
## ahead of its event, and none is left untold when the mower stops. The send
## tick (SEND_INTERVAL, never shorter than LEAF_EVENT_MULCH_SECONDS) bounds the rate.
func _flush_mulch() -> void:
	for key: Variant in _mulch.keys():
		var acc: Dictionary = _mulch[key]
		if int(acc["moved"]) > 0:
			_emit_stroke("mulch", 0, acc["at"], Vector3.ZERO, float(acc["radius"]) * 2.0, 0, int(acc["moved"]))
	_mulch.clear()


## Host, local presentation only: the mulch applied since the last send tick that
## _flush_mulch has not told yet, as the stroke events it will become (contract C1
## keys, local). The leaves are already gone from this peer's field (leaves_changed
## fired in the frame they went), so the leaf motion layer reads these to fly them
## into the deck now instead of fading them while it waits for the event. Clients
## get the event ahead of the batch and never need this. Empty off the host.
func pending_mulch() -> Array:
	var out: Array = []
	if not Net.is_host():
		return out
	for key: Variant in _mulch.keys():
		var acc: Dictionary = _mulch[key]
		if int(acc["moved"]) <= 0:
			continue
		out.append({
			"kind": "mulch", "actor": 0, "seq": 0, "bite": 0, "at": acc["at"], "dir": Vector3.BACK,
			"step": Vector2i(0, 1), "width": float(acc["radius"]) * 2.0, "cells": 0,
			"moved": int(acc["moved"]), "tempo": 0.0, "t": Net.server_time(), "ack_tick": -1, "local": true,
		})
	return out


## Which mower is mulching here (the lawn mower prop at this spot), so two mowers
## keep their own tallies.
func _mower_key(at: Vector3) -> int:
	for node: Node in get_tree().get_nodes_in_group("props"):
		var prop := node as Node3D
		if prop != null and str(prop.get("kind")) == "lawn_mower" and prop.global_position.distance_to(at) < 1.0:
			return prop.get_instance_id()
	return 0


# ---- prediction ledger (client)

func _next_seq() -> int:
	_seq = (_seq + 1) & 0xFFFF
	return _seq


func _push_pending(seq: int, op: String, args: Array) -> void:
	_pending.append({"seq": seq, "op": op, "args": args, "ack_tick": -1, "msec": Time.get_ticks_msec()})
	_stats["pending_peak"] = maxi(int(_stats["pending_peak"]), _pending.size())
	if _pending.size() > Constants.LEAF_PREDICT_MAX:
		_pending.pop_front()
		_stats["dropped_full"] = int(_stats["dropped_full"]) + 1
		_recompose()


## Client: predictions the host never confirmed in time are let go.
func _expire_predictions() -> void:
	var now := Time.get_ticks_msec()
	var limit := int(Constants.LEAF_PREDICT_TIMEOUT * 1000.0)
	var expired := false
	while not _pending.is_empty() and now - int(_pending[0]["msec"]) > limit:
		_pending.pop_front()
		_stats["timeouts"] = int(_stats["timeouts"]) + 1
		expired = true
	if expired:
		_recompose()
	for seq: Variant in _unpredicted.keys():
		if now - int(_unpredicted[seq]) > limit:
			_unpredicted.erase(seq)


## Client: the field this peer shows is the host's confirmed bytes with its own
## unconfirmed strokes replayed on top, in order, with the very same rule code
## (a stroke's cascade can cross chunks, so the whole field, never a region).
## Only chunks whose bytes come out different are marked; a confirmation that
## matches the prediction changes nothing.
func _recompose() -> void:
	_stats["recomposes"] = int(_stats["recomposes"]) + 1
	var before := _density
	_density = _confirmed.duplicate()
	_replay_pending()
	if before == _density:
		return
	_stats["recompose_changes"] = int(_stats["recompose_changes"]) + 1
	for chunk_index: int in _changed_chunks(before, _density):
		_view_dirty[chunk_index] = true
		chunk_changed.emit(chunk_index)
	_queue_flush()


## The pending strokes, in order, onto _density (which starts as _confirmed).
func _replay_pending() -> void:
	_replaying = true
	for op: Dictionary in _pending:
		var args: Array = op["args"]
		if str(op["op"]) == "rake":
			_stroke_cells(args[0], args[1], float(args[2]), float(args[3]), int(args[4]), float(args[5]), int(args[6]))
		else:
			_apply_collect(args[0], float(args[1]), false)
	_replaying = false


## The chunks in which two whole-field byte arrays differ.
func _changed_chunks(a: PackedByteArray, b: PackedByteArray) -> Array[int]:
	var changed: Array[int] = []
	if a.size() != b.size():
		for chunk_index: int in chunk_count():
			changed.append(chunk_index)
		return changed
	var seen := {}
	for z: int in grid_depth:
		var row := z * grid_width
		if a.slice(row, row + grid_width) == b.slice(row, row + grid_width):
			continue
		for cx: int in _chunks_x:
			var start := row + cx * CHUNK_SIZE
			var end := mini(start + CHUNK_SIZE, row + grid_width)
			if a.slice(start, end) != b.slice(start, end):
				seen[cx + int(z / CHUNK_SIZE) * _chunks_x] = true
	for key: Variant in seen.keys():
		changed.append(int(key))
	changed.sort()
	return changed


# ---- what this peer shows

func _queue_flush() -> void:
	if _flush_queued:
		return
	_flush_queued = true
	_flush_view.call_deferred()


## Once a frame: leaves_changed for every chunk whose bytes really changed since
## the last flush (a stroke and its matching confirmation report once).
func _flush_view() -> void:
	_flush_queued = false
	if _view_dirty.is_empty():
		return
	var chunks: Array = _view_dirty.keys()
	_view_dirty.clear()
	chunks.sort()
	for key: Variant in chunks:
		var chunk_index := int(key)
		var origin := _chunk_origin(chunk_index)
		var differs := false
		for dz: int in CHUNK_SIZE:
			var z := origin.y + dz
			if z >= grid_depth:
				break
			var start := z * grid_width + origin.x
			var end := mini(start + CHUNK_SIZE, z * grid_width + grid_width)
			if _density.slice(start, end) != _flushed.slice(start, end):
				differs = true
				for index: int in range(start, end):
					_flushed[index] = _density[index]
		if differs:
			leaves_changed.emit(chunk_index)


## The whole field was replaced on this peer: tell it, then let the flush report
## the chunks that differ.
func _reset_view(hard: bool) -> void:
	_stats["resets_hard" if hard else "resets_soft"] = int(_stats["resets_hard" if hard else "resets_soft"]) + 1
	field_reset.emit(hard)
	for chunk_index: int in chunk_count():
		_view_dirty[chunk_index] = true
	_queue_flush()


## The field's event, batch and ledger counters (probe "leaf_ledger", --rake-net-test).
func ledger_stats() -> Dictionary:
	var stats := _stats.duplicate()
	stats["pending"] = _pending.size()
	stats["send_tick"] = _send_tick
	stats["last_tick"] = _last_tick
	return stats


## This peer's unconfirmed predicted strokes.
func pending_count() -> int:
	return _pending.size()


## SHA-256 of the bytes this peer shows (tests compare peers with it).
func density_hash() -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(_density)
	return hashing.finish().hex_encode()


func _player_in_reach(peer_id: int, origin: Vector3) -> bool:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name != str(peer_id) or not node is Node3D:
			continue
		return (node as Node3D).global_position.distance_to(origin) <= REACH_METERS
	return false


func _inside_grid(world_position: Vector3) -> bool:
	var cell := _cell_at(world_position)
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_width and cell.y < grid_depth


func _cell_at(world_position: Vector3) -> Vector2i:
	var local := _local_xz(world_position)
	var rel_x := local.x - grid_origin.x
	var rel_z := local.y - grid_origin.z
	return Vector2i(int(floor(rel_x / cell_size)), int(floor(rel_z / cell_size)))


func _cell_center(x: int, z: int) -> Vector2:
	return Vector2(grid_origin.x + (float(x) + 0.5) * cell_size, grid_origin.z + (float(z) + 0.5) * cell_size)


func _local_xz(world_position: Vector3) -> Vector2:
	var local: Vector3 = global_transform.affine_inverse() * world_position
	return Vector2(local.x, local.z)


func _chunk_index(x: int, z: int) -> int:
	return int(x / CHUNK_SIZE) + int(z / CHUNK_SIZE) * _chunks_x


func _chunk_origin(chunk_index: int) -> Vector2i:
	return Vector2i((chunk_index % _chunks_x) * CHUNK_SIZE, int(chunk_index / _chunks_x) * CHUNK_SIZE)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_rake(origin: Vector3, direction: Vector3, width: float, strength: float, seq: int, bite: int, tempo: float) -> void:
	if not Net.is_host():
		return
	_handle_rake(multiplayer.get_remote_sender_id(), origin, direction, width, strength, seq, bite, tempo)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_collect(origin: Vector3, radius: float, seq: int) -> void:
	if not Net.is_host():
		return
	_handle_collect(multiplayer.get_remote_sender_id(), origin, radius, seq)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_snapshot() -> void:
	if not Net.is_host():
		return
	_send_snapshot(multiplayer.get_remote_sender_id(), true)


## Client: one send tick's changed chunks (indices, versions and 256 bytes each,
## deflated when big). They land in the confirmed bytes; every prediction they
## confirm (ack_tick <= tick) is done, and the rest are replayed over them.
@rpc("authority", "call_remote", "reliable")
func _rpc_chunk_batch(tick: int, indices: PackedByteArray, versions: PackedInt32Array, data: PackedByteArray, compressed: bool) -> void:
	if Net.is_host():
		return
	var size := indices.size() * CHUNK_SIZE * CHUNK_SIZE
	var raw := data.decompress(size, FileAccess.COMPRESSION_DEFLATE) if compressed else data
	if raw.size() != size or versions.size() != indices.size():
		push_warning("[LeafField] chunk batch %d: %d bytes for %d chunks" % [tick, raw.size(), indices.size()])
		return
	_stats["batches_in"] = int(_stats["batches_in"]) + 1
	for index: int in indices.size():
		_confirm_chunk_bytes(int(indices[index]), versions[index], raw, index * CHUNK_SIZE * CHUNK_SIZE)
	_last_tick = maxi(_last_tick, tick)
	var kept: Array[Dictionary] = []
	for op: Dictionary in _pending:
		var ack := int(op["ack_tick"])
		if ack < 0 or ack > tick:
			kept.append(op)
	_pending = kept
	_recompose()


## Client: the host's whole field (on arrival, a new lot, or a resync). tick is the
## host's last batch tick. upto_seq is the request a resync answers: the host had
## applied everything this peer sent up to it, so those predictions go, and the
## later ones (still on their way to the host) are replayed over the new bytes.
## -1 (a hard snapshot) drops every prediction.
@rpc("authority", "call_remote", "reliable")
func _rpc_snapshot(compressed: PackedByteArray, versions: PackedInt32Array, removed_units: float, tick: int, hard: bool, upto_seq: int) -> void:
	var raw := compressed.decompress(grid_width * grid_depth, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != _density.size():
		push_warning("[LeafField] snapshot size %d did not match %d" % [raw.size(), _density.size()])
		return
	var local_version := 0
	var remote_version := 0
	for version: int in _versions:
		local_version = maxi(local_version, version)
	for version: int in versions:
		remote_version = maxi(remote_version, version)
	if remote_version < local_version:
		return
	_stats["snapshots_in"] = int(_stats["snapshots_in"]) + 1
	# The first field this peer shows always snaps in, whatever the reason.
	var reset_hard := hard or not _had_snapshot
	if reset_hard:
		_stats["snapshot_hard"] = int(_stats["snapshot_hard"]) + 1
	_had_snapshot = true
	_confirmed = raw
	_versions = versions
	_removed_units = removed_units
	_last_tick = maxi(_last_tick, tick)
	if upto_seq < 0:
		_pending.clear()
		_density = raw.duplicate()
	else:
		var kept: Array[Dictionary] = []
		for op: Dictionary in _pending:
			if not _seq_at_or_before(int(op["seq"]), upto_seq):
				kept.append(op)
		_pending = kept
		for seq: Variant in _unpredicted.keys():
			if _seq_at_or_before(int(seq), upto_seq):
				_unpredicted.erase(seq)
		_stats["kept_on_resync"] = int(_stats["kept_on_resync"]) + kept.size()
		# _recompose marks only what differs; the snapshot's chunks are all told below.
		_density = _confirmed.duplicate()
		_replay_pending()
	for chunk_index: int in chunk_count():
		chunk_changed.emit(chunk_index)
	_reset_view(reset_hard)


## u16 sequence order, wrap aware: a is b or was sent before it.
static func _seq_at_or_before(a: int, b: int) -> bool:
	return ((b - a) & 0xFFFF) < 0x8000
