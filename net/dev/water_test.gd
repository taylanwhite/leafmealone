extends Node

## Authority: host. --water-test (with --all-tools --all-tasks) checks water:
## a hose hooked to Chefty snaps loose when you walk too far with it, a hose on
## the house spigot washes every window when aimed so the water's arc reaches it
## (and the homeowner bills for it), the pressure washer stops when its tank is
## dry and fills back up at a source, and (in a windowed run, holding on with
## the mouse captured) a hydrant-fed hose lifts and shoves you. Each step prints
## a [WaterTest] line; --screenshot saves the hydrant moment.

const _WaterSources = preload("res://net/work/water_sources.gd")
const _JobTasks = preload("res://net/work/job_tasks.gd")

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


func _run(lot: Node3D) -> void:
	await get_tree().create_timer(1.0).timeout
	var tasks := lot.call("job_tasks") as Node
	var me := _own_player()
	var hose := _prop("hose")
	var ok := true
	# 1. Hook up at Chefty, walk toward the house: it snaps.
	var tank := _WaterSources.find(get_tree(), "chefty")
	await _grab_at(hose, tank.global_position + Vector3(0.0, -0.6, 1.6))
	hose.call("request_hookup")
	await _ticks(3)
	var hooked := str(hose.get("hose_source")) == "chefty"
	var snapped_at := -1.0
	for step: int in 60:
		_move_to(tank.global_position + Vector3(0.0, -0.6, 1.6) + Vector3(0.0, 0.0, -0.6 * float(step)))
		await _ticks(2)
		if str(hose.get("hose_source")) == "":
			snapped_at = tank.global_position.distance_to(hose.global_position)
			break
	print("[WaterTest] hooked to Chefty %s, snapped loose at %.1f m (hose is %.0f m)" % [hooked, snapped_at, Constants.HOSE_LENGTH])
	ok = ok and hooked and snapped_at > 0.0
	# 2. Spigot: aim arcs at every window.
	var spigot := _WaterSources.find(get_tree(), "spigot")
	await _grab_at(hose, spigot.global_position + Vector3(0.0, -0.6, 0.0) + (spigot.global_position - Vector3(lot.global_position.x, 0, spigot.global_position.z)).normalized() * 0.0)
	_move_to(Vector3(spigot.global_position.x, 0.1, spigot.global_position.z) + _away_from_house(lot, spigot.global_position) * 1.0)
	await _ticks(2)
	hose.call("request_hookup")
	await _ticks(3)
	var on_spigot := str(hose.get("hose_source")) == "spigot"
	var speed := float(Constants.WATER_SPEED["spigot"])
	for index: int in int(tasks.call("spot_count")):
		var spot: Dictionary = tasks.call("spot", index)
		if str(spot["task"]) != "wash_windows":
			continue
		var target: Vector3 = spot["at"]
		var normal: Vector3 = spot["normal"]
		var stand := Vector3(target.x, 0.1, target.z) + Vector3(normal.x, 0.0, normal.z).normalized() * 4.0
		if stand.distance_to(spigot.global_position) > Constants.HOSE_LENGTH - 1.5:
			stand = spigot.global_position + (stand - spigot.global_position).normalized() * (Constants.HOSE_LENGTH - 1.5)
			stand.y = 0.1
		_move_to(stand)
		await _ticks(2)
		var eye := me.global_position + Vector3(0.0, 1.6, 0.0)
		var aim := _aim_at(eye, target, speed)
		for _try: int in 30:
			if int((tasks.call("spot", index) as Dictionary)["amount"]) <= 0:
				break
			tasks.call("request_work", "wash_windows", eye, aim)
			await _ticks(2)
	var windows := float(tasks.call("progress", "wash_windows"))
	var fee := float(tasks.get("water_fee"))
	print("[WaterTest] on the house spigot %s: windows %d%% clean by aiming the arc, water bill $%d" % [on_spigot, int(windows * 100.0), int(fee)])
	ok = ok and on_spigot and windows >= 0.99 and fee > 0.0
	# In a windowed run: pictures of aiming the hose low and high, from your own eyes.
	if DisplayServer.get_name() != "headless":
		me.set("head_pitch", -0.2)
		await _ticks(4)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		Input.action_press(&"primary")
		await get_tree().create_timer(0.8).timeout
		_snapshot("aim_low")
		me.set("head_pitch", 0.55)
		await get_tree().create_timer(0.8).timeout
		_snapshot("aim_high")
		Input.action_release(&"primary")
		me.set("head_pitch", 0.0)
	# 3. The washer runs dry, then refills.
	var washer := _prop("pressure_washer")
	_drop_held()
	await _ticks(2)
	await _grab_at(washer, lot.global_position + Vector3(1.5, 0.1, 10.0))
	washer.set("water", 2.0)
	var before := float(tasks.call("progress", "power_wash"))
	for _try: int in 30:
		tasks.call("request_work", "power_wash", lot.global_position + Vector3(0.0, 0.05, 10.0), Vector3.LEFT)
		await _ticks(1)
	var dry := float(washer.get("water")) <= 0.0
	var mid := float(tasks.call("progress", "power_wash"))
	for _try: int in 10:
		tasks.call("request_work", "power_wash", lot.global_position + Vector3(0.0, 0.05, 12.0), Vector3.LEFT)
		await _ticks(1)
	var stuck := is_equal_approx(float(tasks.call("progress", "power_wash")), mid)
	_move_to(Vector3(spigot.global_position.x, 0.1, spigot.global_position.z) + _away_from_house(lot, spigot.global_position) * 1.0)
	await _ticks(3)
	washer.call("request_hookup")
	await _ticks(3)
	var refilled := float(washer.get("water")) >= 99.0
	print("[WaterTest] washer ran dry %s (cleaned %d%% -> %d%%, then nothing more %s), refilled at the spigot %s" % [dry, int(before * 100.0), int(mid * 100.0), stuck, refilled])
	ok = ok and dry and stuck and refilled
	# 4. The hydrant (windowed only: it needs the mouse captured, like a player).
	if DisplayServer.get_name() != "headless":
		_drop_held()
		await _ticks(2)
		var hydrant := _WaterSources.find(get_tree(), "hydrant")
		await _grab_at(hose, Vector3(hydrant.global_position.x, 0.1, hydrant.global_position.z - 1.4))
		hose.call("request_hookup")
		await _ticks(3)
		me.set("body_yaw", PI)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		var start := me.global_position
		Input.action_press(&"primary")
		var highest := 0.0
		var shot := false
		var waited := 0.0
		_drop_held()
		await _ticks(1)
		await _grab_at(_prop("pressure_washer"), lot.global_position + Vector3(1.5, 0.1, 9.0))
		_prop("pressure_washer").set("water", 100.0)
		Input.action_press(&"primary")
		await get_tree().create_timer(0.8).timeout
		_snapshot("washer")
		Input.action_release(&"primary")
		_drop_held()
		await _ticks(2)
		await _grab_at(hose, Vector3(hydrant.global_position.x, 0.1, hydrant.global_position.z - 1.4))
		if str(hose.get("hose_source")) != "hydrant":
			hose.call("request_hookup")
		await _ticks(3)
		me.set("body_yaw", PI)
		Input.action_press(&"primary")
		while waited < 3.5:
			await get_tree().physics_frame
			waited += get_physics_process_delta_time()
			highest = maxf(highest, me.global_position.y)
			if not shot and waited > 2.0:
				shot = true
				_snapshot("hydrant")
		Input.action_release(&"primary")
		var moved := Vector2(me.global_position.x - start.x, me.global_position.z - start.z).length()
		print("[WaterTest] holding a hydrant hose: lifted to %.1f m, shoved %.1f m" % [highest, moved])
		ok = ok and highest > 0.8 and moved > 1.0
	result["ok"] = ok
	print("[WaterTest] all ok: %s" % ok)


## Which way to throw water from eye at speed so its arc passes through target
## (the lower of the two angles), as a direction.
static func aim_at(eye: Vector3, target: Vector3, speed: float) -> Vector3:
	var flat := Vector3(target.x - eye.x, 0.0, target.z - eye.z)
	var x := flat.length()
	var y := target.y - eye.y
	var g := 9.8
	var inside := speed * speed * speed * speed - g * (g * x * x + 2.0 * y * speed * speed)
	var angle := atan2(y, x) if inside < 0.0 else atan((speed * speed - sqrt(inside)) / (g * x))
	return (flat.normalized() * cos(angle) + Vector3.UP * sin(angle)).normalized()


func _aim_at(eye: Vector3, target: Vector3, speed: float) -> Vector3:
	var flat := Vector3(target.x - eye.x, 0.0, target.z - eye.z)
	var x := flat.length()
	var y := target.y - eye.y
	var g := 9.8
	var inside := speed * speed * speed * speed - g * (g * x * x + 2.0 * y * speed * speed)
	var angle := atan2(y, x) if inside < 0.0 else atan((speed * speed - sqrt(inside)) / (g * x))
	return (flat.normalized() * cos(angle) + Vector3.UP * sin(angle)).normalized()


func _away_from_house(lot: Node3D, at: Vector3) -> Vector3:
	var tasks := lot.call("job_tasks") as Node
	for index: int in int(tasks.call("spot_count")):
		var spot: Dictionary = tasks.call("spot", index)
		if str(spot["task"]) == "wash_windows" and (spot["at"] as Vector3).distance_to(at) < 6.0 and absf((spot["normal"] as Vector3).x) > 0.5:
			return Vector3((spot["normal"] as Vector3).x, 0.0, 0.0)
	return Vector3(signf(at.x - lot.global_position.x), 0.0, 0.0)


func _grab_at(item: Node3D, stand: Vector3) -> void:
	_drop_held()
	await _ticks(2)
	_move_to(stand)
	await _ticks(1)
	item.global_position = _own_player().global_position + Vector3(0.0, 0.4, 0.6)
	item.set("linear_velocity", Vector3.ZERO)
	await _ticks(2)
	item.call("request_grab")
	await _ticks(3)


func _snapshot(label: String) -> void:
	var dir := str(Net.dev_options().get("screenshot_dir"))
	if dir == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, label])


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
