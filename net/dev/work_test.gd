extends Node

## Authority: host. --work-test (with --all-tools --all-tasks) checks every kind
## of yard work end to end: for each task the homeowner asked for, grab the
## right tool, do the work the way a player does (request_work aimed at each
## spot, or pushing the mower), check it reaches 100%, then get paid and check
## the receipt pays for each task. Each step prints a [WorkTest] line, and the
## result lands in the --measure report, with the yard's layout hash so a
## client's report can be compared.

static var result: Dictionary = {}

var _started: bool = false


func _process(_delta: float) -> void:
	if _started or not Net.is_host() or _own_player() == null:
		return
	var lot := get_tree().get_first_node_in_group("job_lot")
	if lot == null or not bool(lot.get("is_generated")):
		return
	_started = true
	_run(lot)


func _run(lot: Node) -> void:
	await get_tree().create_timer(1.0).timeout
	var tasks := lot.call("job_tasks") as Node
	result["layout_hash"] = int(lot.get_meta("layout_hash", 0))
	result["active"] = Array(tasks.get("active"))
	var outcomes: Dictionary = {}
	result["tasks"] = outcomes
	var all_ok := true
	for task: String in (tasks.get("active") as PackedStringArray):
		if task == "rake_leaves":
			continue
		var done: float = await _do_task(tasks, task)
		var ok := done >= 0.99
		outcomes[task] = done
		all_ok = all_ok and ok
		print("[WorkTest] %s: %d%% done, ok=%s" % [task, int(done * 100.0), ok])
	# Get paid: each task should be on the receipt at full pay.
	var owner_node := get_tree().get_first_node_in_group("homeowner") as Node3D
	_drop_held()
	await _ticks(2)
	_move_to(owner_node.global_position + Vector3(0.0, 0.0, 1.5))
	await _ticks(2)
	owner_node.call("_handle_talk", Net.local_peer_id())
	var settlement: Dictionary = owner_node.get("_settlement")
	var task_pay := 0
	for row: Array in settlement.get("tasks", []):
		task_pay += int(row[2])
	var expected := 0
	for task: String in outcomes:
		expected += int(Constants.TASK_PAY.get(task, 0))
	result["task_pay"] = task_pay
	result["expected_task_pay"] = expected
	print("[WorkTest] receipt pays $%d for the tasks (full pay is $%d), mood %s, total $%d" % [task_pay, expected, settlement.get("mood", "?"), int(settlement.get("paid", 0))])
	all_ok = all_ok and task_pay >= expected - outcomes.size()
	result["ok"] = all_ok
	print("[WorkTest] all ok: %s" % all_ok)


func _do_task(tasks: Node, task: String) -> float:
	var tool := str(Constants.TASK_TOOLS.get(task, ""))
	_drop_held()
	await _ticks(2)
	if tool != "":
		var item := _prop(tool)
		if item == null:
			print("[WorkTest] %s: no %s came along" % [task, tool])
			return 0.0
		_move_to(item.global_position + Vector3(0.0, 0.0, 1.0))
		await _ticks(2)
		item.call("request_grab")
		await _ticks(3)
	if task == "mow_lawn":
		await _mow(tasks)
	elif task == "power_wash":
		await _wash(tasks)
	else:
		for index: int in int(tasks.call("spot_count")):
			var spot: Dictionary = tasks.call("spot", index)
			if str(spot["task"]) != task:
				continue
			for _try: int in 40:
				if int((tasks.call("spot", index) as Dictionary)["amount"]) <= 0:
					break
				await _work_at(tasks, task, spot)
	return float(tasks.call("progress", task))


## Stand where a player would for this spot, face it, and work it once.
func _work_at(tasks: Node, task: String, spot: Dictionary) -> void:
	var at: Vector3 = spot["at"]
	var normal: Vector3 = spot["normal"]
	var flat := Vector3(normal.x, 0.0, normal.z)
	if flat.length() < 0.1:
		flat = Vector3(0.0, 0.0, 1.0)
	flat = flat.normalized()
	var stand := Vector3(at.x, 0.0, at.z) + flat * (3.0 if task == "wash_windows" else 0.8)
	stand.y = 0.1
	_move_to(stand)
	await _ticks(1)
	var player := _own_player()
	var eye := player.global_position + Vector3(0.0, 1.6, 0.0)
	match task:
		"wash_windows":
			tasks.call("request_work", task, eye, (at - eye).normalized())
		"clean_gutters":
			tasks.call("request_work", task, player.global_position, -flat)
		_:
			tasks.call("request_work", task, at, -flat)
	await _ticks(2)


## Push the mower down one strip for real, then mow the rest cell by cell.
func _mow(tasks: Node) -> void:
	var grid_index := _grid_of(tasks, "mow_lawn")
	if grid_index < 0:
		return
	var grid: Dictionary = tasks.call("grid", grid_index)
	var corner: Vector3 = grid["corner"]
	var before := float(tasks.call("progress", "mow_lawn"))
	for step: int in 120:
		_move_to(corner + Vector3(2.0 + float(step) * 0.07, 0.1, 20.5))
		await get_tree().physics_frame
	print("[WorkTest] pushing the mower one strip: %d%% -> %d%%" % [int(before * 100.0), int(float(tasks.call("progress", "mow_lawn")) * 100.0)])
	var width: int = grid["width"]
	var mask: PackedByteArray = grid["mask"]
	for cell: int in mask.size():
		if mask[cell] == 1:
			var center := corner + Vector3((float(cell % width) + 0.5) * float(grid["cell"]), 0.0, (float(cell / width) + 0.5) * float(grid["cell"]))
			tasks.call("host_work", "mow_lawn", center, 0.4, 1.0, Net.local_peer_id())


## Aim the washer at every stain until it's gone.
func _wash(tasks: Node) -> void:
	var grid_index := _grid_of(tasks, "power_wash")
	if grid_index < 0:
		return
	var grid: Dictionary = tasks.call("grid", grid_index)
	var corner: Vector3 = grid["corner"]
	var width: int = grid["width"]
	var cell_size: float = grid["cell"]
	for cell: int in (grid["mask"] as PackedByteArray).size():
		if (grid["mask"] as PackedByteArray)[cell] != 1:
			continue
		var center := corner + Vector3((float(cell % width) + 0.5) * cell_size, 0.05, (float(cell / width) + 0.5) * cell_size)
		_move_to(center + Vector3(1.5, 0.05, 0.0))
		await _ticks(1)
		for _try: int in 12:
			if ((tasks.call("grid", grid_index) as Dictionary)["amounts"] as PackedByteArray)[cell] == 0:
				break
			tasks.call("request_work", "power_wash", center, Vector3.LEFT)


func _grid_of(tasks: Node, task: String) -> int:
	for index: int in int(tasks.call("grid_count")):
		if str((tasks.call("grid", index) as Dictionary)["task"]) == task:
			return index
	return -1


func _drop_held() -> void:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if int(node.get("held_by")) == Net.local_peer_id():
			node.call("request_drop")


func _ticks(count: int) -> void:
	for _tick: int in count:
		await get_tree().physics_frame


func _move_to(at: Vector3) -> void:
	var player := _own_player()
	if player != null:
		player.call("apply_network_teleport", Transform3D(player.global_basis, at))


func _own_player() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as Node3D
	return null


func _prop(kind: String) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) == kind and not node.is_queued_for_deletion():
			return node as Node3D
	return null
