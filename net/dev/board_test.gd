extends Node

## Authority: host. --board-test checks the job board at Homie Depot: offers go
## up, picking one sticks, buying a tool keeps the same yards and the pick,
## Chefty drives to the picked yard with its work, nobody can change the pick
## once the job is set, and back at the store new offers go up. A joined client's
## probe report ("board") should match the host's at the end. Each step prints a
## [BoardTest] line.

## Long enough for a picked yard to swap in (levels/world.gd LOT_SWAP_SECONDS) and settle.
const LOT_WAIT: float = 3.0

static var result: Dictionary = {}

var _started: bool = false


func _process(_delta: float) -> void:
	if _started or not Net.is_host() or _own_player() == null or _board() == null:
		return
	if (_board().get("offers") as Array).is_empty():
		return
	_started = true
	_run()


func _run() -> void:
	var board := _board()
	var world := get_tree().get_first_node_in_group("world")
	# Give a client a moment to join, so it sees every step.
	var waited := 0.0
	while Net.peer_ids().size() < 2 and waited < 6.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	# As long as a player takes to walk up to the board, so the client's yard is settled.
	await get_tree().create_timer(4.0).timeout
	var ok := true
	var offers: Array = (board.get("offers") as Array).duplicate(true)
	var up := offers.size() == Constants.JOB_BOARD_OFFERS
	print("[BoardTest] offers up: %d, ok=%s" % [offers.size(), up])
	ok = ok and up
	board.call("request_choose", 2)
	await get_tree().create_timer(0.3).timeout
	var picked := int(board.get("chosen")) == 2
	print("[BoardTest] picked the third offer: %s" % picked)
	ok = ok and picked
	# Buying tools re-reads the offers: same yards, same pick.
	Campaign.dev_grant_all_tools(Net.local_peer_id())
	await get_tree().create_timer(0.5).timeout
	var reread: Array = board.get("offers")
	var same := int(board.get("chosen")) == 2
	for index: int in offers.size():
		same = same and int(reread[index]["seed"]) == int(offers[index]["seed"])
	print("[BoardTest] after buying tools: same yards and pick %s" % same)
	ok = ok and same
	var expected: Dictionary = (board.call("current") as Dictionary).duplicate(true)
	# Everyone at the truck, and off to the picked yard.
	for node: Node in get_tree().get_nodes_in_group("players"):
		var pad := world.get_node("%TruckPad") as Node3D
		(node as Node3D).global_position = pad.global_position + Vector3(randf_range(-1.0, 1.0), 0.2, randf_range(-1.0, 1.0))
	await get_tree().create_timer(0.3).timeout
	await get_tree().create_timer(LOT_WAIT).timeout
	world.call("_host_depart")
	await get_tree().create_timer(0.5).timeout
	var lot := get_tree().get_first_node_in_group("job_lot")
	var went := lot != null and int(lot.get("job_seed")) == int(expected["seed"]) and (lot.get("tasks") as PackedStringArray) == (expected["tasks"] as PackedStringArray)
	print("[BoardTest] Chefty drives to the picked yard with its work: %s" % went)
	ok = ok and went
	board.call("request_choose", 0)
	await get_tree().create_timer(0.3).timeout
	var held := int(board.get("chosen")) == 2
	print("[BoardTest] can't change the pick once the job is set: %s" % held)
	ok = ok and held
	# Back at the store, new offers.
	world.call("_free_lot")
	await get_tree().create_timer(0.5).timeout
	var fresh: Array = board.get("offers")
	var new_ones := fresh.size() == Constants.JOB_BOARD_OFFERS and int(fresh[0]["seed"]) != int(offers[0]["seed"]) and int(board.get("chosen")) == 0
	print("[BoardTest] new offers once the job is over: %s" % new_ones)
	ok = ok and new_ones
	result = {"ok": ok}
	print("[BoardTest] all ok: %s" % ok)


func _board() -> Node:
	return get_tree().get_first_node_in_group("job_board")


func _own_player() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as Node3D
	return null
