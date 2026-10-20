extends Node

## Authority: host. The work a job asks for besides raking (Constants.TASK_TOOLS):
## spots for things you clean one at a time (windows, gutter sections, shaggy
## hedges, faded fence panels, litter, weeds) and grids for areas (the lawn to
## mow, the driveway to wash). Each spot and cell holds how much work is left,
## 0 to 100.
##
## The lot's generator defines the spots and grids the same way on every peer
## from the job's seed (define_spot, define_grid), then activate() turns on the
## tasks the homeowner asked for. After that the host owns the numbers: players
## send request_work() while using a tool, the host checks they hold the right
## tool and are close enough, applies it, and sends only what changed. A late
## joiner asks for a snapshot. Renderers listen to spot_changed and cell_changed.

signal spot_changed(index: int, amount: int)
signal cell_changed(grid: int, cell: int, amount: int)
signal tasks_changed

## Seconds of work each request stands for; tools send one this often.
const WORK_TICK: float = 0.15
const SEND_INTERVAL: float = 0.1

## Task ids the homeowner asked for, besides raking.
var active := PackedStringArray()
## Dollars the homeowner will bill for their water (the spigot). Replicated in whole dollars.
var water_fee: float = 0.0

var _spots: Array[Dictionary] = []
var _grids: Array[Dictionary] = []
var _start_total: Dictionary = {}
var _dirty_spots: Dictionary = {}
var _dirty_cells: Dictionary = {}
var _send_wait: float = 0.0
var _fx_wait: Dictionary = {}


func _ready() -> void:
	add_to_group("job_tasks")


## Every peer, same order: a spot of work for task at a world position. normal
## is the way the surface faces (for windows); radius is its size.
func define_spot(task: String, at: Vector3, normal: Vector3 = Vector3.UP, radius: float = 0.5) -> int:
	_spots.append({"task": task, "at": at, "normal": normal, "radius": radius, "amount": 0})
	return _spots.size() - 1


## Every peer, same order: a grid of cells for task over a rectangle on the
## ground, from corner (world, at its -x -z corner) across size meters. include
## (optional) says which cells are part of the work, given each cell's center.
func define_grid(task: String, corner: Vector3, size: Vector2, cell: float, include: Callable = Callable()) -> int:
	var width := maxi(1, int(ceil(size.x / cell)))
	var depth := maxi(1, int(ceil(size.y / cell)))
	var mask := PackedByteArray()
	mask.resize(width * depth)
	for z: int in depth:
		for x: int in width:
			var center := corner + Vector3((float(x) + 0.5) * cell, 0.0, (float(z) + 0.5) * cell)
			mask[x + z * width] = 1 if (not include.is_valid() or bool(include.call(center))) else 0
	var amounts := PackedByteArray()
	amounts.resize(width * depth)
	_grids.append({"task": task, "corner": corner, "cell": cell, "width": width, "depth": depth, "mask": mask, "amounts": amounts})
	return _grids.size() - 1


## Every peer: turn on the asked-for tasks. Their spots and cells start at 100
## (dirtiness can vary per spot, from the same seed everywhere).
func activate(tasks: PackedStringArray, seed_value: int) -> void:
	# A task this yard has nothing for (no beds, so no weeds) isn't asked for.
	active = PackedStringArray()
	for task: String in tasks:
		if task == "rake_leaves" or _has_work_for(task):
			active.append(task)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for spot: Dictionary in _spots:
		var on := active.has(str(spot["task"]))
		spot["amount"] = rng.randi_range(70, 100) if on else 0
	for grid: Dictionary in _grids:
		var on := active.has(str(grid["task"]))
		var amounts: PackedByteArray = grid["amounts"]
		var mask: PackedByteArray = grid["mask"]
		for index: int in amounts.size():
			amounts[index] = (rng.randi_range(80, 100) if on and mask[index] == 1 else 0)
		grid["amounts"] = amounts
	_start_total.clear()
	for task: String in active:
		_start_total[task] = _remaining(task)
	tasks_changed.emit()
	if not Net.is_host() and multiplayer.multiplayer_peer != null:
		_rpc_request_snapshot.rpc_id(1)


func _has_work_for(task: String) -> bool:
	for entry: Dictionary in _spots:
		if str(entry["task"]) == task:
			return true
	for entry: Dictionary in _grids:
		if str(entry["task"]) == task and (entry["mask"] as PackedByteArray).has(1):
			return true
	return false


# ---------------------------------------------------------------- reading

## How much of task is done, 0 to 1. Tasks not asked for count as done.
func progress(task: String) -> float:
	var start := float(_start_total.get(task, 0))
	if start <= 0.0:
		return 1.0
	return clampf(1.0 - float(_remaining(task)) / start, 0.0, 1.0)


func spot_count() -> int:
	return _spots.size()


func spot(index: int) -> Dictionary:
	return _spots[index]


func grid_count() -> int:
	return _grids.size()


func grid(index: int) -> Dictionary:
	return _grids[index]


## The spot of task nearest to a point with work left, or -1.
func nearest_spot(task: String, near: Vector3, within: float = INF) -> int:
	var best := -1
	var best_distance := within
	for index: int in _spots.size():
		var entry := _spots[index]
		if str(entry["task"]) != task or int(entry["amount"]) <= 0:
			continue
		var distance := (entry["at"] as Vector3).distance_to(near)
		if distance < best_distance:
			best = index
			best_distance = distance
	return best


# ---------------------------------------------------------------- working

## The local player works at task: origin is where the work lands (or the eye,
## for spraying), direction is where they face. Call every WORK_TICK while working.
func request_work(task: String, origin: Vector3, direction: Vector3) -> void:
	if Net.is_host():
		_handle_work(Net.local_peer_id(), task, origin, direction)
	else:
		_rpc_request_work.rpc_id(1, task, origin, direction)


## Host only: work done by something the host moves itself, like a pushed mower.
func host_work(task: String, at: Vector3, radius: float, seconds: float, peer_id: int = 0) -> void:
	if not Net.is_host() or not active.has(task):
		return
	var done := _work_cells(task, at, radius, float(Constants.TASK_WORK_RATE.get(task, 50.0)) * seconds)
	if done > 0 and peer_id != 0:
		Campaign.record_stat(peer_id, &"objectives", float(done) / 100.0)
	if done > 0:
		_fx(task, at)


func _handle_work(peer_id: int, task: String, origin: Vector3, direction: Vector3) -> void:
	if not active.has(task):
		return
	var player := _player(peer_id)
	if player == null:
		return
	var reach := float(Constants.TASK_REACH.get(task, 2.0))
	if player.global_position.distance_to(origin) > reach + 2.5:
		return
	var tool := str(Constants.TASK_TOOLS.get(task, ""))
	# Gutters need you up a ladder, not a ladder in your hands. Scooping with a
	# leaf blower up there goes faster than by hand.
	var speedup := 1.0
	if task == "clean_gutters":
		if not bool(player.call("is_climbing")):
			return
		if _holds(peer_id, "leaf_blower"):
			speedup = Constants.GUTTER_BLOWER_SPEEDUP
	elif tool != "" and not _holds(peer_id, tool):
		return
	# Water: a hose has to be hooked up, a pressure washer has to have water in it.
	var hose: Node = null
	if task == "wash_windows":
		hose = _held(peer_id, "hose")
		if hose == null or str(hose.get("hose_source")) == "":
			return
		var source := str(hose.get("hose_source"))
		if source == "hydrant":
			speedup *= Constants.HYDRANT_CLEAN_SPEEDUP
		elif source == "spigot":
			add_water_fee(Constants.SPIGOT_FEE_PER_SECOND * WORK_TICK)
		hose.call("mark_spraying")
	elif task == "power_wash":
		var washer := _held(peer_id, "pressure_washer")
		if washer == null or float(washer.get("water")) <= 0.0:
			return
		washer.set("water", maxf(0.0, float(washer.get("water")) - Constants.WASHER_USE_PER_SECOND * WORK_TICK))
		washer.call("mark_spraying")
	# Tools work while held down, a tick at a time; bare-hands work is one press each.
	var amount := float(Constants.TASK_WORK_RATE.get(task, 50.0)) * (WORK_TICK if tool != "" else 1.0) * speedup
	var done := 0
	var hit := origin
	match task:
		"wash_windows":
			# The water flies in an arc at the source's pressure: only the windows
			# it actually passes through get clean.
			var speed := float(Constants.WATER_SPEED.get(str(hose.get("hose_source")), 10.0))
			var arc := water_arc(origin, direction.normalized() * speed)
			for index: int in _spots.size():
				var entry := _spots[index]
				if str(entry["task"]) != task or int(entry["amount"]) <= 0:
					continue
				if _arc_distance(arc, entry["at"]) > float(entry["radius"]):
					continue
				done += _work_spot(index, amount)
				hit = entry["at"]
		"power_wash", "mow_lawn":
			done = _work_cells(task, origin, 0.9, amount)
		_:
			# Up close: the nearest spot within reach of where you stand. Gutters
			# are overhead, so only the distance across the ground counts.
			var best := -1
			var best_distance := reach
			for index: int in _spots.size():
				var entry := _spots[index]
				if str(entry["task"]) != task or int(entry["amount"]) <= 0:
					continue
				var at: Vector3 = entry["at"]
				var distance := at.distance_to(origin)
				if task == "clean_gutters":
					distance = Vector2(at.x - origin.x, at.z - origin.z).length()
					if distance > Constants.LADDER_TOP_REACH or absf(at.y - origin.y) > 2.6:
						continue
				if distance < best_distance:
					best = index
					best_distance = distance
			if best >= 0:
				done = _work_spot(best, amount)
				hit = _spots[best]["at"]
	if done > 0:
		Campaign.record_stat(peer_id, &"objectives", float(done) / 100.0)
		_fx(task, hit)


func _work_spot(index: int, amount: float) -> int:
	var entry := _spots[index]
	var before := int(entry["amount"])
	var after := maxi(0, before - int(ceil(amount)))
	if after == before:
		return 0
	entry["amount"] = after
	_dirty_spots[index] = true
	spot_changed.emit(index, after)
	return before - after


func _work_cells(task: String, at: Vector3, radius: float, amount: float) -> int:
	var done := 0
	for grid_index: int in _grids.size():
		var entry := _grids[grid_index]
		if str(entry["task"]) != task:
			continue
		var cell: float = entry["cell"]
		var corner: Vector3 = entry["corner"]
		var width: int = entry["width"]
		var depth: int = entry["depth"]
		var amounts: PackedByteArray = entry["amounts"]
		var low := Vector2i(int(floor((at.x - radius - corner.x) / cell)), int(floor((at.z - radius - corner.z) / cell)))
		var high := Vector2i(int(floor((at.x + radius - corner.x) / cell)), int(floor((at.z + radius - corner.z) / cell)))
		for z: int in range(maxi(low.y, 0), mini(high.y, depth - 1) + 1):
			for x: int in range(maxi(low.x, 0), mini(high.x, width - 1) + 1):
				var index := x + z * width
				if amounts[index] == 0:
					continue
				var center := corner + Vector3((float(x) + 0.5) * cell, 0.0, (float(z) + 0.5) * cell)
				if Vector2(center.x - at.x, center.z - at.z).length() > radius + cell * 0.5:
					continue
				var before := int(amounts[index])
				var after := maxi(0, before - int(ceil(amount)))
				amounts[index] = after
				done += before - after
				if not _dirty_cells.has(grid_index):
					_dirty_cells[grid_index] = {}
				(_dirty_cells[grid_index] as Dictionary)[index] = true
				cell_changed.emit(grid_index, index, after)
		entry["amounts"] = amounts
	return done


## Points along a stream of water from origin at velocity, every 0.04 s, until it
## lands. The same arc the stream is drawn with.
static func water_arc(origin: Vector3, velocity: Vector3) -> PackedVector3Array:
	var points := PackedVector3Array()
	var at := origin
	var moving := velocity
	for _step: int in 60:
		points.append(at)
		moving += Vector3(0.0, -9.8, 0.0) * 0.04
		at += moving * 0.04
		if at.y < 0.0:
			points.append(at)
			break
	return points


func _arc_distance(arc: PackedVector3Array, point: Vector3) -> float:
	var best := INF
	for index: int in arc.size() - 1:
		var a := arc[index]
		var b := arc[index + 1]
		var along := clampf((point - a).dot(b - a) / maxf((b - a).length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, point.distance_to(a.lerp(b, along)))
	return best


## Host: run up the homeowner's water bill.
func add_water_fee(dollars: float) -> void:
	if not Net.is_host():
		return
	var before := int(water_fee)
	water_fee += dollars
	if int(water_fee) != before:
		_rpc_fee.rpc(int(water_fee))


@rpc("authority", "call_remote", "reliable")
func _rpc_fee(dollars: int) -> void:
	water_fee = float(dollars)


func _held(peer_id: int, kind: String) -> Node:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) == kind and int(node.get("held_by")) == peer_id:
			return node
	return null


func _remaining(task: String) -> int:
	var total := 0
	for entry: Dictionary in _spots:
		if str(entry["task"]) == task:
			total += int(entry["amount"])
	for entry: Dictionary in _grids:
		if str(entry["task"]) == task:
			for value: int in (entry["amounts"] as PackedByteArray):
				total += value
	return total


func _holds(peer_id: int, kind: String) -> bool:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) == kind and int(node.get("held_by")) == peer_id:
			return true
	return false


func _player(peer_id: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node as Node3D
	return null


# ---------------------------------------------------------------- replication

func _process(delta: float) -> void:
	if not Net.is_host() or multiplayer.multiplayer_peer == null:
		return
	_send_wait -= delta
	if _send_wait > 0.0:
		return
	_send_wait = SEND_INTERVAL
	if not _dirty_spots.is_empty():
		var indices := PackedInt32Array()
		var values := PackedByteArray()
		for index: int in _dirty_spots:
			indices.append(index)
			values.append(int(_spots[index]["amount"]))
		_dirty_spots.clear()
		_rpc_spots.rpc(indices, values)
	for grid_index: int in _dirty_cells:
		var cells := PackedInt32Array()
		var values := PackedByteArray()
		var amounts: PackedByteArray = _grids[grid_index]["amounts"]
		for index: int in (_dirty_cells[grid_index] as Dictionary):
			cells.append(index)
			values.append(amounts[index])
		_rpc_cells.rpc(grid_index, cells, values)
	_dirty_cells.clear()


## Everyone sees work happen: a splash, clippings, gunk, or paint where it landed.
func _fx(task: String, at: Vector3) -> void:
	var now := Time.get_ticks_msec()
	if int(_fx_wait.get(task, 0)) > now:
		return
	_fx_wait[task] = now + 120
	_rpc_fx.rpc(task, at)


@rpc("authority", "call_local", "unreliable")
func _rpc_fx(task: String, at: Vector3) -> void:
	var looks := get_tree().get_first_node_in_group("task_looks")
	if looks != null and looks.has_method("work_fx"):
		looks.call("work_fx", task, at)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_work(task: String, origin: Vector3, direction: Vector3) -> void:
	if Net.is_host():
		_handle_work(multiplayer.get_remote_sender_id(), task, origin, direction)


@rpc("authority", "call_remote", "reliable")
func _rpc_spots(indices: PackedInt32Array, values: PackedByteArray) -> void:
	for slot: int in indices.size():
		var index := indices[slot]
		if index < 0 or index >= _spots.size():
			continue
		_spots[index]["amount"] = values[slot]
		spot_changed.emit(index, values[slot])


@rpc("authority", "call_remote", "reliable")
func _rpc_cells(grid_index: int, cells: PackedInt32Array, values: PackedByteArray) -> void:
	if grid_index < 0 or grid_index >= _grids.size():
		return
	var amounts: PackedByteArray = _grids[grid_index]["amounts"]
	for slot: int in cells.size():
		if cells[slot] >= 0 and cells[slot] < amounts.size():
			amounts[cells[slot]] = values[slot]
			cell_changed.emit(grid_index, cells[slot], values[slot])
	_grids[grid_index]["amounts"] = amounts


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_snapshot() -> void:
	if not Net.is_host():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var indices := PackedInt32Array()
	var values := PackedByteArray()
	for index: int in _spots.size():
		indices.append(index)
		values.append(int(_spots[index]["amount"]))
	_rpc_spots.rpc_id(peer_id, indices, values)
	for grid_index: int in _grids.size():
		var amounts: PackedByteArray = _grids[grid_index]["amounts"]
		var cells := PackedInt32Array()
		for index: int in amounts.size():
			cells.append(index)
		_rpc_cells.rpc_id(peer_id, grid_index, cells, amounts)
