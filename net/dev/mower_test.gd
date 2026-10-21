extends Node

## Authority: host. --mower-test (with --all-tools --all-tasks, and a second
## player joined who stands still) runs things over with a running mower and
## checks each: leaves get mulched (no money), litter gets flung elsewhere, a
## hooked-up hose gets cut (billed), a leaf bag bursts back into leaves, the
## gnome stalls the mower (billed), the other player's foot gets cut and then
## comes off (medical bills, seen on their peer), a passerby's foot gets hurt,
## and the receipt lists the bills. Each step prints a [MowerTest] line.

static var result: Dictionary = {}

var _started: bool = false


func _process(_delta: float) -> void:
	if _started or not Net.is_host() or _own_player() == null or _target() == null:
		return
	var lot := get_tree().get_first_node_in_group("job_lot")
	if lot == null or not bool(lot.get("is_generated")):
		return
	_started = true
	_run(lot)


func _run(lot: Node3D) -> void:
	await get_tree().create_timer(2.0).timeout
	var tasks := lot.call("job_tasks") as Node
	var field := get_tree().get_first_node_in_group("leaf_field")
	var mower := _prop("lawn_mower")
	var ok := true
	# Grab it and pull the cord until it runs.
	await _stand(lot.global_position + Vector3(6.0, 0.1, 6.0), 0.0)
	mower.global_position = _own_player().global_position + Vector3(0.0, 0.3, -0.8)
	await _ticks(2)
	mower.call("request_grab")
	await _ticks(3)
	await _start(mower)
	# Leaves: mulched, no money.
	var units_before := float(field.call("leaf_units"))
	await _drive(lot.global_position + Vector3(-10.0, 0.1, -2.0), Vector3.RIGHT, 4.0)
	var mulched := float(field.call("leaf_units")) < units_before
	var chefty := get_tree().get_first_node_in_group("chefty")
	print("[MowerTest] leaves mulched %s, truck still $%d" % [mulched, int(chefty.call("bag_value"))])
	ok = ok and mulched and int(chefty.call("bag_value")) == 0
	# Litter: flung somewhere else.
	var litter := -1
	for index: int in int(tasks.call("spot_count")):
		if str((tasks.call("spot", index) as Dictionary)["task"]) == "pick_litter":
			litter = index
			break
	if litter >= 0:
		var was: Vector3 = (tasks.call("spot", litter) as Dictionary)["at"]
		await _drive(was - Vector3(1.6, 0.0, 0.0), Vector3.RIGHT, 2.5)
		var now: Vector3 = (tasks.call("spot", litter) as Dictionary)["at"]
		print("[MowerTest] litter flung %.1f m" % was.distance_to(now))
		ok = ok and was.distance_to(now) > 2.0
	# Hose: hooked to the spigot, lying across the lawn; drive across it.
	var hose := _prop("hose")
	var spigot := get_tree().get_nodes_in_group("water_sources").filter(func(node: Node) -> bool: return str(node.get_meta("kind")) == "spigot")[0] as Node3D
	hose.global_position = spigot.global_position + Vector3(0.0, -0.5, 8.0)
	hose.set("linear_velocity", Vector3.ZERO)
	hose.set("hose_source", "spigot")
	await _ticks(3)
	var middle := (spigot.global_position + hose.global_position) * 0.5
	await _drive(Vector3(middle.x - 2.0, 0.1, middle.z), Vector3.RIGHT, 4.0)
	var cut := str(hose.get("hose_source")) == "" and int((tasks.get("bills") as Dictionary).get("hose", 0)) > 0
	print("[MowerTest] hose cut and billed %s" % cut)
	ok = ok and cut
	# A leaf bag: bursts back into leaves.
	var bag_spot := lot.global_position + Vector3(10.0, 0.2, -10.0)
	var bags_before := _count("leaf_bag")
	_drop_hold_and_run(mower, bag_spot)
	await _ticks(2)
	# Stand by the leaves to rake them into a pile and bag it, like a player.
	for index: int in 14:
		var stroke_at := bag_spot - Vector3(4.0 - float(index) * 0.3, 0.0, 0.0)
		_move_to(stroke_at - Vector3(1.5, 0.1, 0.0))
		field.call("request_rake", stroke_at, Vector3.RIGHT, Constants.RAKE_WIDTH, Constants.RAKE_STRENGTH)
	_move_to(bag_spot - Vector3(1.5, 0.1, 0.0))
	await _ticks(1)
	field.call("request_collect", bag_spot, Constants.BAG_RADIUS)
	await _ticks(3)
	var made := _count("leaf_bag") > bags_before
	_move_to(lot.global_position + Vector3(6.0, 0.1, 6.0))
	await _grab_back(mower)
	await _start(mower)
	await _drive(bag_spot - Vector3(2.0, 0.0, 0.0), Vector3.RIGHT, 3.0)
	var burst := _count("leaf_bag") == bags_before
	print("[MowerTest] made a bag %s, mowed it and it burst %s" % [made, burst])
	ok = ok and made and burst
	# The gnome: grinds, flies, stalls the mower, billed.
	var gnome := _prop("gnome")
	var gnome_at := lot.global_position + Vector3(-6.0, 0.25, 4.0)
	gnome.global_position = gnome_at
	gnome.set("linear_velocity", Vector3.ZERO)
	await _ticks(3)
	await _drive(gnome_at - Vector3(2.0, 0.0, 0.0), Vector3.RIGHT, 3.0)
	var stalled := not bool(mower.get("spraying"))
	var gnome_billed := int((tasks.get("bills") as Dictionary).get("gnome", 0)) > 0
	print("[MowerTest] hit the gnome: mower stalled %s, billed %s" % [stalled, gnome_billed])
	ok = ok and stalled and gnome_billed
	# The other player's foot, twice: a cut, then it comes off.
	var target := _target()
	var levels: Array[int] = []
	for pass_index: int in 2:
		await _start(mower)
		await _drive(target.global_position - Vector3(2.2, 0.0, 0.0), Vector3.RIGHT, 3.5)
		# The other player's foot replicates from their machine: give it a moment.
		var before := levels[-1] if not levels.is_empty() else 0
		for _tenth: int in 30:
			await get_tree().create_timer(0.1).timeout
			if int(target.get("foot_hurt")) > before:
				break
		levels.append(int(target.get("foot_hurt")))
		await get_tree().create_timer(3.6).timeout
	print("[MowerTest] the other player's foot: after one pass %d, after two %d" % [levels[0], levels[1]])
	# In a windowed run, look at them (and the foot on the lawn).
	if DisplayServer.get_name() != "headless":
		var me := _own_player()
		var away := (me.global_position - target.global_position)
		away.y = 0.0
		_move_to(target.global_position + away.normalized() * 2.6 + Vector3(0.0, 0.1, 0.0))
		var toward := target.global_position - me.global_position
		me.set("body_yaw", atan2(-toward.x, -toward.z))
		me.set("head_pitch", -0.35)
		await get_tree().create_timer(0.5).timeout
		var dir := str(Net.dev_options().get("screenshot_dir"))
		if dir != "":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/foot_off.png" % dir)
	ok = ok and levels[0] >= 1 and levels[1] == 2
	# A passerby's foot.
	var walker: Node3D = null
	for node: Node in get_tree().get_nodes_in_group("bonkable"):
		var person := node as Node3D
		if person != null and absf(person.global_position.x - lot.global_position.x) < 30.0 and absf(person.global_position.z - lot.global_position.z - 21.4) < 1.0:
			walker = person
			break
	if walker != null:
		await _start(mower)
		for _chase: int in 120:
			_move_to(walker.global_position - (-_own_player().global_basis.z) * 1.1 + Vector3(0.0, 0.1, 0.0))
			await get_tree().physics_frame
			if int(walker.get("foot_hurt")) > 0:
				break
		print("[MowerTest] a passerby's foot hurt %s" % (int(walker.get("foot_hurt")) > 0))
		ok = ok and int(walker.get("foot_hurt")) > 0
	var bills: Dictionary = tasks.get("bills")
	print("[MowerTest] the bill: %s" % bills)
	ok = ok and int(bills.get("medical", 0)) >= Constants.BILL_FOOT_CUT + Constants.BILL_FOOT_OFF
	result["ok"] = ok
	print("[MowerTest] all ok: %s" % ok)


## Push the mower from start along heading for this far, at a walk.
func _drive(start: Vector3, heading: Vector3, distance: float) -> void:
	var me := _own_player()
	me.set("body_yaw", atan2(-heading.x, -heading.z))
	me.rotation.y = float(me.get("body_yaw"))
	var steps := int(distance / 0.07)
	for step: int in steps:
		_move_to(start + heading * (float(step) * 0.07))
		await get_tree().physics_frame


func _start(mower: Node) -> void:
	for _pull: int in 12:
		if bool(mower.get("spraying")):
			return
		mower.call("request_start")
		await _ticks(2)


func _restart(mower: Node) -> void:
	await _start(mower)


func _drop_hold_and_run(mower: Node, _at: Vector3) -> void:
	mower.call("request_drop")


func _grab_back(mower: Node3D) -> void:
	await _ticks(2)
	mower.global_position = _own_player().global_position + Vector3(0.0, 0.3, -0.8)
	await _ticks(2)
	mower.call("request_grab")
	await _ticks(3)


func _stand(at: Vector3, yaw: float) -> void:
	await get_tree().physics_frame
	_move_to(at)
	_own_player().set("body_yaw", yaw)


func _count(kind: String) -> int:
	return get_tree().get_nodes_in_group("props").filter(func(node: Node) -> bool: return str(node.get("kind")) == kind and not node.is_queued_for_deletion()).size()


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


func _target() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name != str(Net.local_peer_id()):
			return node as Node3D
	return null


func _prop(kind: String) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) == kind and not node.is_queued_for_deletion():
			return node as Node3D
	return null
