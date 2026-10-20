extends Node

## Authority: host. --job-test plays whole jobs by itself so the loop can be
## checked without anyone at the keyboard. Each round: ride Chefty to the lot
## (unless the session started there), grab the one rake, rake a pile, bag it and
## compare it to a bag from untouched leaves, carry the bags to Chefty, talk to
## the homeowner, take the cash, and ride home. The second round checks that the
## next job starts fresh. Each step prints a [JobTest] line, and the result lands
## in the --measure report.

const ROUNDS: int = 2
const RIDE_TIMEOUT_SECONDS: float = 20.0

const _JobGoal = preload("res://ui/job_goal.gd")
const _Strings = preload("res://ui/strings.gd")

static var result: Dictionary = {}

var _started: bool = false


func _process(_delta: float) -> void:
	if _started or not Net.is_host() or _own_player() == null:
		return
	_started = true
	_run()


func _run() -> void:
	await _seconds(2.0)
	var rounds: Array = []
	result["rounds"] = rounds
	result["ok"] = false
	for round_index: int in ROUNDS:
		var round_result := {}
		rounds.append(round_result)
		_note("round %d" % (round_index + 1))
		var ok: bool = await _play_round(round_result)
		round_result["ok"] = ok
		if not ok:
			_note("FAILED round %d: %s" % [round_index + 1, round_result.get("error", "")])
			return
	result["ok"] = true
	_note("all %d rounds ok" % ROUNDS)
	var wrong: Array = []
	for round_result: Dictionary in rounds:
		wrong.append_array(round_result.get("wrong_goals", []))
	result["goals_ok"] = wrong.is_empty()
	if not wrong.is_empty():
		result["ok"] = false
		result["error"] = "goal line wrong: %s" % [wrong]
	_note("goal line right at every step: %s" % result["goals_ok"])


func _play_round(out: Dictionary) -> bool:
	if Net.player_zone(Net.local_peer_id()) == Net.Zone.STORE:
		if not await _ride_to_lot(out):
			return false
	if not _fresh_job(out):
		return false
	if not await _grab_rake(out):
		return false
	await _rake_pile(out)
	if not _bag_and_compare(out):
		return false
	if not await _deliver(out):
		return false
	if not await _get_paid(out):
		return false
	return await _ride_home(out)


func _ride_to_lot(out: Dictionary) -> bool:
	var pad := get_tree().get_first_node_in_group("world").get_node_or_null("StoreZone/TruckPad") as Node3D
	if pad == null:
		return _fail(out, "no truck pad at the store")
	_move_player_to(pad.global_position + Vector3(0.0, 0.5, 3.2))
	await _ticks(3)
	_expect_goal(out, "goal_board")
	get_tree().get_first_node_in_group("world").call("request_depart")
	if not await _until(func() -> bool: return Net.player_zone(Net.local_peer_id()) == Net.Zone.LOT, RIDE_TIMEOUT_SECONDS):
		return _fail(out, "Chefty never got to the lot")
	await _ticks(5)
	_note("rode Chefty to the lot")
	return true


## A new job: leaves untouched, an empty truck, a homeowner waiting, a free rake.
func _fresh_job(out: Dictionary) -> bool:
	var field := _field()
	var chefty := get_tree().get_first_node_in_group("chefty")
	var owner_node := get_tree().get_first_node_in_group("homeowner")
	var rake := _first_prop("rake")
	if field == null or owner_node == null or rake == null:
		return _fail(out, "the lot is missing its leaves, homeowner, or rake")
	out["start_clean"] = float(field.call("cleaned_fraction"))
	out["start_truck_value"] = int(chefty.call("bag_value"))
	var waiting := int(owner_node.get("_phase")) == 0
	var rake_free := int(rake.get("held_by")) == 0
	_note("fresh job: %.0f%% clean, truck $%d, homeowner waiting %s, rake free %s" % [float(out["start_clean"]) * 100.0, out["start_truck_value"], waiting, rake_free])
	if float(out["start_clean"]) > 0.01 or int(out["start_truck_value"]) != 0 or not waiting or not rake_free:
		return _fail(out, "the job did not start fresh")
	_expect_goal(out, "goal_grab_rake")
	return true


func _grab_rake(out: Dictionary) -> bool:
	var rake := _first_prop("rake")
	_move_player_to(rake.global_position + Vector3(0.0, 0.0, 1.0))
	await _ticks(2)
	rake.call("request_grab")
	await _ticks(2)
	out["holds_rake"] = bool(_field().call("holds_rake", Net.local_peer_id()))
	if not bool(out["holds_rake"]):
		return _fail(out, "could not grab the rake")
	_expect_goal(out, "goal_rake")
	return true


func _rake_pile(out: Dictionary) -> void:
	var field := _field()
	var lot := _lot_origin()
	# Rake a 6 m strip toward the pile spot, a stroke every half meter.
	for index: int in 12:
		var at := lot + Vector3(-9.0 + float(index) * 0.5, 0.2, -4.0)
		_move_player_to(at - Vector3(1.5, 0.0, 0.0))
		_face(Vector3(1.0, 0.0, 0.0))
		field.call("request_rake", at, Vector3(1.0, 0.0, 0.0), Constants.RAKE_WIDTH, Constants.RAKE_STRENGTH)
	await _ticks(2)
	_note("raked a pile")
	out["raked"] = true


func _bag_and_compare(out: Dictionary) -> bool:
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
	out["bag_values"] = values
	# A thin spot (already raked away) refuses to bag.
	field.call("request_collect", lot + Vector3(-8.0, 0.2, -4.0), Constants.BAG_RADIUS)
	out["thin_spot_bags"] = _bags().size() - before.size() - values.size()
	_note("bag values %s (pile first, fresh leaves second), thin spot made %d bags" % [values, out["thin_spot_bags"]])
	if values.size() != 2 or int(values[0]) <= int(values[1]) or int(out["thin_spot_bags"]) != 0:
		return _fail(out, "the pile bag should be worth more than a fresh one, and a thin spot should not bag")
	return true


## The way a player does it: drop the rake, pick up each bag, walk it to Chefty,
## and press E to toss it in. A carried bag reaches your hands a tick later, so
## each step waits a couple of ticks the way walking over would.
func _deliver(out: Dictionary) -> bool:
	var chefty := get_tree().get_first_node_in_group("chefty")
	var rake := _first_prop("rake")
	if rake != null and int(rake.get("held_by")) == Net.local_peer_id():
		rake.call("request_drop")
	await _ticks(2)
	_expect_goal(out, "goal_carry_loose")
	var expected := 0
	var bags := _bags()
	for bag: Node in bags:
		expected += int(bag.get("value"))
	var truck_at: Vector3 = chefty.call("body_position")
	for bag: Node in bags:
		if not is_instance_valid(bag):
			continue
		_move_player_to((bag as Node3D).global_position + Vector3(0.0, 0.0, 1.0))
		await _ticks(2)
		bag.call("request_grab")
		await _ticks(2)
		if int(bag.get("held_by")) != Net.local_peer_id():
			_note("could not pick up a bag at %s" % (bag as Node3D).global_position)
		_expect_goal(out, "goal_carry_held")
		_move_player_to(truck_at + Vector3(0.0, 0.0, 2.5))
		await _ticks(3)
		if is_instance_valid(bag):
			bag.call("request_load_truck")
		await _ticks(2)
	out["truck_value"] = int(chefty.call("bag_value"))
	_note("carried bags worth $%d to Chefty and tossed them in, truck says $%d" % [expected, out["truck_value"]])
	if int(out["truck_value"]) != expected:
		return _fail(out, "the truck did not take every bag")
	_expect_goal(out, "goal_rake_or_talk")
	return true


func _get_paid(out: Dictionary) -> bool:
	var owner_node := get_tree().get_first_node_in_group("homeowner") as Node3D
	_move_player_to(owner_node.global_position + Vector3(0.0, 0.0, 1.5))
	await _ticks(2)
	out["credits_before"] = Campaign.credits(Net.local_peer_id())
	owner_node.call("_handle_talk", Net.local_peer_id())
	_note("talked to the homeowner")
	# Phase 2 is OFFERING: the reaction plays, then the cash comes out.
	if not await _until(func() -> bool: return int(owner_node.get("_phase")) == 2, 6.0):
		return _fail(out, "the homeowner never held out the cash")
	_expect_goal(out, "goal_take_cash")
	out["offered"] = int(owner_node.get("_amount"))
	owner_node.call("_handle_take", Net.local_peer_id())
	await _ticks(3)
	out["credits_after"] = Campaign.credits(Net.local_peer_id())
	out["paid"] = int(out["credits_after"]) - int(out["credits_before"])
	out["settlement"] = Campaign.last_settlement()
	_note("took the cash: $%d, credits %d -> %d" % [out["offered"], out["credits_before"], out["credits_after"]])
	if int(out["offered"]) <= 0 or int(out["paid"]) != int(out["offered"]):
		return _fail(out, "the cash taken did not land in credits")
	return true


func _ride_home(out: Dictionary) -> bool:
	if not await _until(func() -> bool: return Net.player_zone(Net.local_peer_id()) == Net.Zone.STORE, RIDE_TIMEOUT_SECONDS):
		return _fail(out, "never got back to the store")
	await _ticks(5)
	var chefty := get_tree().get_first_node_in_group("chefty") as Node
	var pad := get_tree().get_first_node_in_group("world").get_node_or_null("StoreZone/TruckPad") as Node3D
	var truck_at: Vector3 = chefty.call("body_position")
	out["truck_home_distance"] = Vector2(truck_at.x - pad.global_position.x, truck_at.z - pad.global_position.z).length()
	out["lot_cleared"] = _field() == null
	_note("rode home: Chefty %.1f m from the pad, lot cleared %s" % [out["truck_home_distance"], out["lot_cleared"]])
	if float(out["truck_home_distance"]) > 15.0 or not bool(out["lot_cleared"]):
		return _fail(out, "Chefty or the lot did not come home right")
	return true


## The HUD goal line (ui/job_goal.gd) should say this right now.
func _expect_goal(out: Dictionary, key: String) -> void:
	var shown := _JobGoal.goal(get_tree(), Net.local_peer_id())
	var prefix := str(_Strings.UI[key]).split("%")[0]
	if not shown.begins_with(prefix):
		var wrong: Array = out.get("wrong_goals", [])
		wrong.append("%s showed \"%s\"" % [key, shown])
		out["wrong_goals"] = wrong
		_note("goal line should be %s but says \"%s\"" % [key, shown])


func _fail(out: Dictionary, reason: String) -> bool:
	out["error"] = reason
	result["error"] = reason
	return false


func _seconds(duration: float) -> void:
	await get_tree().create_timer(duration).timeout


func _ticks(count: int) -> void:
	for _tick: int in count:
		await get_tree().physics_frame


## Waits until the check passes, up to a limit. True if it passed.
func _until(check: Callable, limit_seconds: float) -> bool:
	var waited := 0.0
	while waited < limit_seconds:
		if bool(check.call()):
			return true
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	return bool(check.call())


func _note(text: String) -> void:
	print("[JobTest] ", text)


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
		if str(node.get("kind")) == kind and not node.is_queued_for_deletion():
			return node as Node3D
	return null


func _bags() -> Array:
	return get_tree().get_nodes_in_group("props").filter(func(node: Node) -> bool: return str(node.get("kind")) == "leaf_bag" and not node.is_queued_for_deletion())


func _field() -> Node:
	for node: Node in get_tree().get_nodes_in_group("leaf_field"):
		if not node.is_queued_for_deletion():
			return node
	return null


func _lot_origin() -> Vector3:
	var lot := get_tree().get_first_node_in_group("world").get_node_or_null("LotZone") as Node3D
	return lot.global_position if lot != null else Vector3.ZERO
