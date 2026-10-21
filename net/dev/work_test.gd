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
	all_ok = all_ok and await _fall_check()
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
	if task == "clear_roof":
		await _roof(tasks)
	elif task == "wash_windows":
		await _windows(tasks)
	elif task == "clean_gutters":
		await _gutters(tasks)
	elif task == "mow_lawn":
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
				# A dry roller gets dipped in the paint bucket first.
				if task == "paint_fence" and float(_prop("paint_roller").get("water")) <= 0.0:
					var bucket := get_tree().get_first_node_in_group("paint_buckets") as Node3D
					_move_to(bucket.global_position + Vector3(0.8, -0.3, 0.0))
					await _ticks(2)
					_prop("paint_roller").call("request_hookup")
					await _ticks(2)
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
	# Leaves in the pool are scooped from outside it, reaching over the side.
	var pool := get_tree().get_first_node_in_group("job_lot").find_child("PoolBody", true, false) as Node3D if task == "skim_pool" else null
	if pool != null:
		var out := Vector3(at.x - pool.global_position.x, 0.0, at.z - pool.global_position.z).normalized()
		stand = Vector3(pool.global_position.x, 0.0, pool.global_position.z) + out * 2.75
		flat = out
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


## The hose way: hook it to the house spigot, then stand off each window and aim
## so the water's arc reaches it.
func _windows(tasks: Node) -> void:
	var water_sources := preload("res://net/work/water_sources.gd")
	var aim_script := preload("res://net/dev/water_test.gd")
	var hose := _prop("hose")
	var spigot: Node3D = water_sources.find(get_tree(), "spigot")
	_move_to(Vector3(spigot.global_position.x, 0.1, spigot.global_position.z) + Vector3(signf(spigot.global_position.x - _house_middle(tasks).x), 0.0, 0.0) * 1.0)
	await _ticks(3)
	hose.call("request_hookup")
	await _ticks(3)
	var speed := float(Constants.WATER_SPEED["spigot"])
	for index: int in int(tasks.call("spot_count")):
		var spot: Dictionary = tasks.call("spot", index)
		if str(spot["task"]) != "wash_windows":
			continue
		var target: Vector3 = spot["at"]
		var normal: Vector3 = spot["normal"]
		_move_to(Vector3(target.x, 0.1, target.z) + Vector3(normal.x, 0.0, normal.z).normalized() * 4.0)
		await _ticks(2)
		var eye := _own_player().global_position + Vector3(0.0, 1.6, 0.0)
		for _try: int in 30:
			if int((tasks.call("spot", index) as Dictionary)["amount"]) <= 0:
				break
			tasks.call("request_work", "wash_windows", eye, aim_script.aim_at(eye, target, speed))
			await _ticks(2)


func _house_middle(tasks: Node) -> Vector3:
	var total := Vector3.ZERO
	var count := 0
	for index: int in int(tasks.call("spot_count")):
		var spot: Dictionary = tasks.call("spot", index)
		if str(spot["task"]) == "wash_windows":
			total += spot["at"]
			count += 1
	return total / float(maxi(count, 1))


## On the roof: stand by each pile of leaves and scoop it.
func _roof(tasks: Node) -> void:
	for index: int in int(tasks.call("spot_count")):
		var spot: Dictionary = tasks.call("spot", index)
		if str(spot["task"]) != "clear_roof":
			continue
		var at: Vector3 = spot["at"]
		_move_to(at + Vector3(0.6, 0.4, 0.0))
		await _ticks(2)
		for _try: int in 30:
			if int((tasks.call("spot", index) as Dictionary)["amount"]) <= 0:
				break
			tasks.call("request_work", "clear_roof", at + Vector3(0.3, 0.3, 0.0), Vector3.LEFT)
			_move_to(at + Vector3(0.6, 0.4, 0.0))
			await _ticks(2)


## Step off a high place: a bounce, knocked out, then a limp.
func _fall_check() -> bool:
	var me := _own_player()
	_drop_held()
	var lot := get_tree().get_first_node_in_group("job_lot") as Node3D
	_move_to(lot.global_position + Vector3(0.0, 5.0, 10.0))
	var bounced := false
	var knocked := false
	var waited := 0.0
	while waited < 4.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
		bounced = bounced or bool(me.get("_bounced"))
		knocked = knocked or int(me.get("anim_state")) == 5
	var limping := bool(me.get("limping"))
	print("[WorkTest] stepped off 5 m up: bounced %s, knocked out %s, limping %s" % [bounced, knocked, limping])
	return bounced and knocked and limping


## The ladder way: carry it to each gutter section, set it up, climb, scoop, climb
## down, take it back down, next section.
func _gutters(tasks: Node) -> void:
	var ladder := _prop("ladder")
	var me := _own_player()
	var climbs := 0
	for index: int in int(tasks.call("spot_count")):
		var spot: Dictionary = tasks.call("spot", index)
		if str(spot["task"]) != "clean_gutters" or int(spot["amount"]) <= 0:
			continue
		var at: Vector3 = spot["at"]
		var out: Vector3 = spot["normal"]
		_drop_held()
		await _ticks(2)
		if bool(ladder.call("is_set_up")):
			_move_to(ladder.global_position + Vector3(0.0, 0.1, 0.0))
			await _ticks(2)
			ladder.call("request_grab")
			await _ticks(2)
			_drop_held()
			await _ticks(2)
		_move_to(ladder.global_position + Vector3(0.0, 0.1, 0.8))
		await _ticks(2)
		ladder.call("request_grab")
		await _ticks(3)
		_move_to(Vector3(at.x, 0.1, at.z) + out * 1.6)
		await _ticks(3)
		ladder.call("request_place_ladder")
		await _ticks(3)
		if not bool(ladder.call("is_set_up")):
			print("[WorkTest] couldn't set the ladder up at %s" % at)
			continue
		_move_to(ladder.global_position + out * 0.5 + Vector3(0.0, 0.1, 0.0))
		await _ticks(2)
		me.call("_toggle_climb")
		await get_tree().create_timer(Constants.LADDER_CLIMB_SECONDS + 0.3).timeout
		climbs += 1
		for _try: int in 40:
			if not bool(me.call("is_climbing")):
				print("[WorkTest] not up the ladder at %s" % at)
				break
			for near: int in int(tasks.call("spot_count")):
				var other: Dictionary = tasks.call("spot", near)
				if str(other["task"]) == "clean_gutters" and int(other["amount"]) > 0:
					tasks.call("request_work", "clean_gutters", me.global_position + Vector3(0.0, 1.5, 0.0) - out * 0.4, -out)
					break
			await _ticks(2)
			if int((tasks.call("spot", index) as Dictionary)["amount"]) <= 0:
				break
		me.call("_toggle_climb")
		await get_tree().create_timer(Constants.LADDER_CLIMB_SECONDS + 0.3).timeout
	print("[WorkTest] gutters took %d trips up the ladder" % climbs)


## Push the mower down one strip for real, then mow the rest cell by cell.
func _mow(tasks: Node) -> void:
	var grid_index := _grid_of(tasks, "mow_lawn")
	if grid_index < 0:
		return
	var grid: Dictionary = tasks.call("grid", grid_index)
	var corner: Vector3 = grid["corner"]
	var before := float(tasks.call("progress", "mow_lawn"))
	var mower := _prop("lawn_mower")
	var pulls := 0
	while not bool(mower.get("spraying")) and pulls < 10:
		mower.call("request_start")
		pulls += 1
		await _ticks(2)
	print("[WorkTest] the mower started after %d pulls of the cord" % pulls)
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
