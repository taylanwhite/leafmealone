extends Node

## Authority: host. --job-test plays one job by itself so the whole loop can be
## checked without anyone at the keyboard: grab the one rake, rake a pile, bag it
## (and compare it to a bag from untouched leaves), deliver the bags to Chefty,
## talk to the homeowner, and take the cash. Each step prints a [JobTest] line,
## and the result lands in the --measure report.

static var result: Dictionary = {}

var _step: int = 0
var _wait: float = 3.0


func _process(delta: float) -> void:
	if not Net.is_host():
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = 0.4
	match _step:
		0:
			_grab_rake()
		1:
			_rake_pile()
		2:
			_bag_and_compare()
		3:
			_deliver()
		4:
			_talk()
		5:
			_take_cash()
		6:
			_check_paid()
		_:
			set_process(false)
			return
	_step += 1


func _grab_rake() -> void:
	var rake := _first_prop("rake")
	if rake == null:
		_fail("no rake on the lot")
		return
	_move_player_to(rake.global_position + Vector3(0.0, 0.0, 1.0))
	rake.call("request_grab")
	_wait = 0.6
	_note("grabbed the rake")


func _rake_pile() -> void:
	var field := _field()
	if field == null:
		_fail("no leaf field")
		return
	result["holds_rake"] = bool(field.call("holds_rake", Net.local_peer_id()))
	var lot := _lot_origin()
	# Rake a 6 m strip toward the pile spot, a stroke every half meter.
	for index: int in 12:
		var at := lot + Vector3(-9.0 + float(index) * 0.5, 0.2, -4.0)
		_move_player_to(at - Vector3(1.5, 0.0, 0.0))
		_face(Vector3(1.0, 0.0, 0.0))
		field.call("request_rake", at, Vector3(1.0, 0.0, 0.0), Constants.RAKE_WIDTH, Constants.RAKE_STRENGTH)
	_note("raked a pile, holding the rake: %s" % result["holds_rake"])


func _bag_and_compare() -> void:
	var field := _field()
	var lot := _lot_origin()
	var before := _bags()
	# A bag from the pile, and one from untouched leaves, for comparison.
	_move_player_to(lot + Vector3(-4.5, 0.0, -4.0))
	field.call("request_collect", lot + Vector3(-3.0, 0.2, -4.0), Constants.BAG_RADIUS)
	_move_player_to(lot + Vector3(6.0, 0.0, 6.0))
	field.call("request_collect", lot + Vector3(7.5, 0.2, 6.0), Constants.BAG_RADIUS)
	var values: Array = []
	for bag: Node in _bags():
		if not before.has(bag):
			values.append(int(bag.get("value")))
	result["bag_values"] = values
	# A thin spot (already raked away) refuses to bag.
	field.call("request_collect", lot + Vector3(-8.0, 0.2, -4.0), Constants.BAG_RADIUS)
	result["thin_spot_bags"] = _bags().size() - before.size() - values.size()
	_note("bag values %s (pile first, fresh leaves second), thin spot made %d bags" % [values, result["thin_spot_bags"]])


## The way a player does it: drop the rake, pick up each bag, walk it to Chefty,
## and press E to toss it in.
func _deliver() -> void:
	var chefty := get_tree().get_first_node_in_group("chefty")
	var rake := _first_prop("rake")
	if rake != null and int(rake.get("held_by")) == Net.local_peer_id():
		rake.call("request_drop")
	_delivered_expect = 0
	_pending_bags = _bags()
	for bag: Node in _pending_bags:
		_delivered_expect += int(bag.get("value"))
	_truck_at = chefty.call("body_position")
	_step_deliver_one()
	# Delivering takes a few ticks per bag. Talk to the homeowner after.
	_wait = 1.5


var _pending_bags: Array = []
var _delivered_expect: int = 0
var _truck_at := Vector3.ZERO


## A carried bag moves to your hands on the next physics tick, so each step waits
## a couple of ticks the way walking over would.
func _step_deliver_one() -> void:
	for bag: Node in _pending_bags:
		if not is_instance_valid(bag):
			continue
		_move_player_to((bag as Node3D).global_position + Vector3(0.0, 0.0, 1.0))
		await _ticks(2)
		bag.call("request_grab")
		await _ticks(2)
		if int(bag.get("held_by")) != Net.local_peer_id():
			_note("could not pick up a bag at %s" % (bag as Node3D).global_position)
		_move_player_to(_truck_at + Vector3(0.0, 0.0, 2.5))
		await _ticks(3)
		if is_instance_valid(bag):
			bag.call("request_load_truck")
		await _ticks(2)
	var chefty := get_tree().get_first_node_in_group("chefty")
	result["truck_value"] = int(chefty.call("bag_value"))
	result["tossed_ok"] = result["truck_value"] == _delivered_expect
	_note("carried bags worth $%d to Chefty and tossed them in, truck says $%d" % [_delivered_expect, result["truck_value"]])


func _talk() -> void:
	var owner_node := get_tree().get_first_node_in_group("homeowner") as Node3D
	if owner_node == null:
		_fail("no homeowner")
		return
	_move_player_to(owner_node.global_position + Vector3(0.0, 0.0, 1.5))
	result["credits_before"] = Campaign.credits(Net.local_peer_id())
	owner_node.call("_handle_talk", Net.local_peer_id())
	_wait = 3.2
	_note("talked to the homeowner")


func _take_cash() -> void:
	var owner_node := get_tree().get_first_node_in_group("homeowner")
	result["offered"] = int(owner_node.get("_amount"))
	owner_node.call("_handle_take", Net.local_peer_id())
	_wait = 1.0
	_note("took the cash: $%d" % result["offered"])


func _check_paid() -> void:
	result["credits_after"] = Campaign.credits(Net.local_peer_id())
	result["paid"] = int(result["credits_after"]) - int(result["credits_before"])
	result["ok"] = bool(result.get("holds_rake", false)) and bool(result.get("tossed_ok", false)) and int(result.get("offered", 0)) > 0 and int(result["paid"]) > 0
	_note("credits %d -> %d, ok=%s" % [result["credits_before"], result["credits_after"], result["ok"]])


func _ticks(count: int) -> void:
	for _tick: int in count:
		await get_tree().physics_frame


func _note(text: String) -> void:
	print("[JobTest] ", text)


func _fail(reason: String) -> void:
	result["ok"] = false
	result["error"] = reason
	_note("FAILED: " + reason)
	_step = 99


func _move_player_to(at: Vector3) -> void:
	var player := _own_player()
	if player != null:
		player.call("apply_network_teleport", Transform3D(player.global_basis, at))


func _face(direction: Vector3) -> void:
	var player := _own_player()
	if player != null:
		player.set("body_yaw", atan2(-direction.x, -direction.z))
		player.rotation.y = float(player.get("body_yaw"))


func _own_player() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as Node3D
	return null


func _first_prop(kind: String) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) == kind:
			return node as Node3D
	return null


func _bags() -> Array:
	return get_tree().get_nodes_in_group("props").filter(func(node: Node) -> bool: return str(node.get("kind")) == "leaf_bag")


func _field() -> Node:
	return get_tree().get_first_node_in_group("leaf_field")


func _lot_origin() -> Vector3:
	var lot := get_tree().get_first_node_in_group("world").get_node_or_null("LotZone") as Node3D
	return lot.global_position if lot != null else Vector3.ZERO
