extends Node3D

## Authority: host
## Density grid for one lot. The raking player may predict a stroke locally; the next host chunk replaces it.
## OQ-004: cleaned_fraction() counts leaf units removed by collect, not leaves merely raked into a pile.

signal chunk_changed(chunk_index: int)
signal stroke_visual(at: Vector3)
## units is how much leaf density went into the bag, which sets its value.
signal bag_requested(at: Vector3, units: int)
signal bag_refused(peer_id: int)

const CHUNK_SIZE: int = 16
## A fresh lot starts thin enough that a raked pile can grow about four times
## denser (cells hold up to 255), so piling leaves up before bagging pays.
const INITIAL_DENSITY: int = 60
## OQ-004: a cell counts as cleaned once it is raked or bagged down to this density.
const CLEAN_DENSITY: int = 8
const REACH_METERS: float = 3.5
const SEND_INTERVAL: float = 0.1

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


func _ready() -> void:
	add_to_group("leaf_field")
	_chunks_x = int(ceil(float(grid_width) / float(CHUNK_SIZE)))
	_chunks_z = int(ceil(float(grid_depth) / float(CHUNK_SIZE)))
	_density.resize(grid_width * grid_depth)
	_density.fill(INITIAL_DENSITY)
	_versions.resize(_chunks_x * _chunks_z)
	var total_density := grid_width * grid_depth * INITIAL_DENSITY
	_unit_scale = Balance.STARTING_LOT_LEAF_VOLUME / float(total_density)
	_starting_units = leaf_units()
	if Net.is_host():
		if not Net.player_joined.is_connected(_on_player_joined):
			Net.player_joined.connect(_on_player_joined)
	else:
		_rpc_request_snapshot.rpc_id(1)


func _process(delta: float) -> void:
	_send_wait += delta
	if _send_wait < SEND_INTERVAL or _dirty.is_empty():
		return
	_send_wait = 0.0
	for key: Variant in _dirty.keys():
		var chunk_index := int(key)
		# The chunk RPC is call_remote, so the host has to rebuild its own mesh here.
		if Net.is_host():
			_versions[chunk_index] += 1
			_rpc_chunk.rpc(chunk_index, _versions[chunk_index], _chunk_bytes(chunk_index))
		chunk_changed.emit(chunk_index)
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


## Move density from cells under the rake to the cells ahead of it.
func request_rake(origin: Vector3, direction: Vector3, width: float, strength: float) -> void:
	if not _inside_grid(origin):
		return
	if Net.is_host():
		_handle_rake(Net.local_peer_id(), origin, direction, width, strength)
	else:
		if _player_in_reach(Net.local_peer_id(), origin):
			_stroke(origin, direction, width, strength * Campaign.rake_multiplier(Net.local_peer_id()), width > Constants.HAND_RAKE_WIDTH)
		_rpc_request_rake.rpc_id(1, origin, direction, width, strength)


## Remove density around a point. This is what currently counts as cleaned.
func request_collect(origin: Vector3, radius: float) -> void:
	if not _inside_grid(origin):
		return
	if Net.is_host():
		_handle_collect(Net.local_peer_id(), origin, radius)
	else:
		if _player_in_reach(Net.local_peer_id(), origin):
			_apply_collect(origin, radius, false)
		_rpc_request_collect.rpc_id(1, origin, radius)


## Density at the cell under a world position. Smoke tests compare this on both peers.
func sample_world(world_position: Vector3) -> int:
	var cell := _cell_at(world_position)
	return density_at_cell(cell.x, cell.y)


func _on_player_joined(peer_id: int) -> void:
	if peer_id != Net.local_peer_id():
		_send_snapshot(peer_id)


func _handle_rake(peer_id: int, origin: Vector3, direction: Vector3, width: float, strength: float) -> void:
	if not _player_in_reach(peer_id, origin):
		_send_snapshot(peer_id)
		return
	# Full strength only with the job's one rake in hand. Bare hands barely move anything.
	var has_rake := holds_rake(peer_id)
	var max_strength := Constants.RAKE_STRENGTH if has_rake else Constants.HAND_RAKE_STRENGTH
	var max_width := Constants.RAKE_WIDTH if has_rake else Constants.HAND_RAKE_WIDTH
	var cells := Constants.RAKE_STROKE_CELLS if has_rake else 1
	# A leaf blower shoves leaves much farther than any rake.
	if holds_kind(peer_id, "leaf_blower"):
		max_strength = Constants.BLOWER_STRENGTH
		max_width = Constants.BLOWER_WIDTH
		cells = Constants.BLOWER_CELLS
	var moved := _stroke_cells(origin, direction, minf(width, max_width), minf(strength, max_strength) * Campaign.rake_multiplier(peer_id), cells)
	if moved <= 0:
		return
	Campaign.record_stat(peer_id, &"leaves_cleared", float(moved) * _unit_scale)
	_rpc_stroke.rpc(origin)


func _handle_collect(peer_id: int, origin: Vector3, radius: float) -> void:
	if not _player_in_reach(peer_id, origin):
		_send_snapshot(peer_id)
		return
	# Too few leaves here to fill a bag: rake a pile first. Nothing is taken.
	if _units_within(origin, minf(radius, Constants.BAG_RADIUS)) < int(Constants.MIN_BAG_CELLS * INITIAL_DENSITY):
		if peer_id == Net.local_peer_id():
			_on_bag_refused()
		else:
			# Undo the client's predicted bagging, then tell them why.
			_send_snapshot(peer_id)
			_rpc_bag_refused.rpc_id(peer_id)
		return
	var removed := _apply_collect(origin, minf(radius, Constants.BAG_RADIUS), true)
	if removed <= 0:
		return
	Campaign.record_stat(peer_id, &"leaves_cleared", float(removed) * _unit_scale)
	_rpc_stroke.rpc(origin)


func _apply_rake(origin: Vector3, direction: Vector3, width: float, strength: float) -> int:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length() < 0.001:
		return 0
	flat = flat.normalized()
	var step := Vector2i(int(round(flat.x)), int(round(flat.z)))
	if step == Vector2i.ZERO:
		step = Vector2i(0, 1)
	var center := _cell_at(origin)
	var radius_cells := int(ceil((width * 0.5) / cell_size)) + 1
	var moved := 0
	var take := int(clamp(strength, 1.0, 255.0))
	for dz: int in range(-radius_cells, radius_cells + 1):
		for dx: int in range(-radius_cells, radius_cells + 1):
			var source := Vector2i(center.x + dx, center.y + dz)
			if _cell_center(source.x, source.y).distance_to(Vector2(_local_xz(origin).x, _local_xz(origin).y)) > width * 0.5:
				continue
			var amount := mini(density_at_cell(source.x, source.y), take)
			if amount <= 0:
				continue
			var dest := source + step
			if density_at_cell(dest.x, dest.y) >= 255:
				continue
			var room := 255 - density_at_cell(dest.x, dest.y)
			var shifted := mini(amount, room)
			_add_density(source.x, source.y, -shifted)
			if dest.x >= 0 and dest.y >= 0 and dest.x < grid_width and dest.y < grid_depth:
				_add_density(dest.x, dest.y, shifted)
			moved += shifted
	return moved


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
	return maxi(1, int(round(float(units) / lot_density * whole_lot)))


## One rake stroke: the leaves are shoved several cells forward, building a pile
## ahead of the rake. Bare hands only manage one cell.
func _stroke(origin: Vector3, direction: Vector3, width: float, strength: float, with_rake: bool) -> int:
	return _stroke_cells(origin, direction, width, strength, Constants.RAKE_STROKE_CELLS if with_rake else 1)


func _stroke_cells(origin: Vector3, direction: Vector3, width: float, strength: float, cells: int) -> int:
	var flat := Vector3(direction.x, 0.0, direction.z).normalized()
	var moved := 0
	for step: int in cells:
		moved += _apply_rake(origin + flat * cell_size * float(step), direction, width, strength)
	return moved


## Host: true while this peer carries a prop of this kind.
func holds_kind(peer_id: int, held_kind: String) -> bool:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) == held_kind and int(node.get("held_by")) == peer_id:
			return true
	return false


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


## The bagging player hears that there wasn't enough here.
@rpc("authority", "call_remote", "reliable")
func _rpc_bag_refused() -> void:
	_on_bag_refused()


func _on_bag_refused() -> void:
	bag_refused.emit(Net.local_peer_id())


func _add_density(x: int, z: int, delta: int) -> void:
	if x < 0 or z < 0 or x >= grid_width or z >= grid_depth:
		return
	var index := x + z * grid_width
	var next := clampi(int(_density[index]) + delta, 0, 255)
	_density[index] = next
	_dirty[_chunk_index(x, z)] = true


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


func _apply_chunk_bytes(chunk_index: int, version: int, bytes: PackedByteArray) -> void:
	if chunk_index < 0 or chunk_index >= _versions.size():
		return
	if version < _versions[chunk_index]:
		return
	_versions[chunk_index] = version
	var origin := _chunk_origin(chunk_index)
	var read := 0
	for dz: int in CHUNK_SIZE:
		for dx: int in CHUNK_SIZE:
			var x := origin.x + dx
			var z := origin.y + dz
			if read < bytes.size():
				_set_density_raw(x, z, int(bytes[read]))
			read += 1
	chunk_changed.emit(chunk_index)


func _set_density_raw(x: int, z: int, value: int) -> void:
	if x < 0 or z < 0 or x >= grid_width or z >= grid_depth:
		return
	_density[x + z * grid_width] = clampi(value, 0, 255)


func _send_snapshot(peer_id: int) -> void:
	# The host already has the true field; it never resyncs itself.
	if peer_id == Net.local_peer_id():
		return
	var compressed := _density.compress(FileAccess.COMPRESSION_DEFLATE)
	_rpc_snapshot.rpc_id(peer_id, compressed, _versions.duplicate(), _removed_units)


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
func _rpc_request_rake(origin: Vector3, direction: Vector3, width: float, strength: float) -> void:
	if not Net.is_host():
		return
	_handle_rake(multiplayer.get_remote_sender_id(), origin, direction, width, strength)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_collect(origin: Vector3, radius: float) -> void:
	if not Net.is_host():
		return
	_handle_collect(multiplayer.get_remote_sender_id(), origin, radius)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_snapshot() -> void:
	if not Net.is_host():
		return
	_send_snapshot(multiplayer.get_remote_sender_id())


@rpc("authority", "call_remote", "reliable")
func _rpc_chunk(chunk_index: int, version: int, bytes: PackedByteArray) -> void:
	_apply_chunk_bytes(chunk_index, version, bytes)


@rpc("authority", "call_remote", "reliable")
func _rpc_snapshot(compressed: PackedByteArray, versions: PackedInt32Array, removed_units: float) -> void:
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
	_density = raw
	_versions = versions
	_removed_units = removed_units
	for chunk_index: int in chunk_count():
		chunk_changed.emit(chunk_index)


@rpc("authority", "call_remote", "reliable")
func _rpc_stroke(at: Vector3) -> void:
	stroke_visual.emit(at)
