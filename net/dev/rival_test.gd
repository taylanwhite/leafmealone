extends Node

## Authority: host. --rival-test checks the seasons (core/seasons.gd) and the
## rival, TurfMasters™ (net/town/town.gd): days map to seasons, winter pays more
## and has fewer leaves; a poached client stops texting; a neighbor's yard on
## their street has the rival's sign in it; pulling the sign up pays XP and wins
## the client back. Run with --rank=17 (Mulch Mule III, when they arrive).
## Each step prints a [RivalTest] line.

const _Seasons = preload("res://core/seasons.gd")

static var result: Dictionary = {}

var _started: bool = false


func _process(_delta: float) -> void:
	if _started or not Net.is_host() or _town() == null or _board() == null:
		return
	if (_board().get("offers") as Array).is_empty():
		return
	_started = true
	_run()


func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	var town := _town()
	var clock := get_tree().get_first_node_in_group("day_clock")
	var world := get_tree().get_first_node_in_group("world")
	var ok := true
	# Seasons from the day number.
	var map_ok := _Seasons.of_day(1) == 0 and _Seasons.of_day(Constants.SEASON_DAYS + 1) == 1 and _Seasons.of_day(Constants.SEASON_DAYS * 2 + 1) == 2 and _Seasons.of_day(Constants.SEASON_DAYS * 3 + 1) == 3 and _Seasons.of_day(Constants.SEASON_DAYS * 4 + 1) == 0 and _Seasons.year_of(Constants.SEASON_DAYS * 4 + 1) == 2
	print("[RivalTest] days map to autumn, winter, spring, summer, then a new year: %s" % map_ok)
	ok = ok and map_ok
	var rival_on := Campaign.is_feature_on("rival")
	print("[RivalTest] TurfMasters™ are in town at this rank: %s" % rival_on)
	ok = ok and rival_on
	# A Maple Row client is poached.
	var requests: Array = town.get("requests")
	var victim := int(requests[0])
	var hood := str(town.call("house", victim)["hood"])
	town.call("dev_poach", victim)
	await get_tree().create_timer(0.3).timeout
	var gone := bool(town.call("house", victim)["poached"]) and not (town.get("requests") as Array).has(victim) and int(town.call("poached_in", hood)) == 1
	print("[RivalTest] %s went to TurfMasters™ and stopped texting: %s" % [town.call("owner_name", victim), gone])
	ok = ok and gone
	# A neighbor's job: their yard has the rival's sign in it.
	var offers: Array = _board().get("offers")
	var neighbor := -1
	for index: int in offers.size():
		if str((offers[index] as Dictionary).get("hood", "")) == hood and int((offers[index] as Dictionary)["house_id"]) != victim:
			neighbor = index
	var has_signs := neighbor >= 0 and int((offers[neighbor] as Dictionary).get("signs", 0)) == 1
	print("[RivalTest] a neighbor's job on the same street carries 1 sign: %s" % has_signs)
	ok = ok and has_signs
	_board().call("request_choose", neighbor)
	await get_tree().create_timer(0.3).timeout
	world.call("_load_job_lot")
	await get_tree().create_timer(1.0).timeout
	var signs := get_tree().get_nodes_in_group("turf_signs")
	var planted := signs.size() == 1 and str((signs[0] as Node).get("kind")) == "turf_sign"
	print("[RivalTest] the sign is in the yard: %s" % planted)
	ok = ok and planted
	# Someone pulls it up.
	var xp_before := Campaign.pending_xp()
	if planted:
		(signs[0] as Node).set("held_by", Net.local_peer_id())
	await get_tree().create_timer(0.5).timeout
	var back := not bool(town.call("house", victim)["poached"]) and (town.get("requests") as Array).has(victim) and Campaign.pending_xp() > xp_before
	print("[RivalTest] pulling the sign won %s back, with XP: %s" % [town.call("owner_name", victim), back])
	ok = ok and back
	# Winter: more pay, fewer leaves.
	clock.set("day", Constants.SEASON_DAYS + 1)
	town.set("_day", Constants.SEASON_DAYS + 1)
	var bonus := float(clock.call("pay_bonus"))
	var cold := absf(bonus - float(_Seasons.PAY_BONUS[1])) < 0.001
	var fresh := -1
	for entry: Variant in (town.get("houses") as Array):
		if bool((entry as Dictionary).get("known", false)) and int((entry as Dictionary).get("last_day", -1)) < 0:
			fresh = int((entry as Dictionary)["id"])
	var winter_mess := float((town.call("offer_for", fresh) as Dictionary).get("mess", 1.0))
	var thin := absf(winter_mess - float(_Seasons.LEAVES[1])) < 0.001
	print("[RivalTest] winter pays +%d%% and a never-done yard is %.0f%% full: %s" % [int(bonus * 100.0), winter_mess * 100.0, cold and thin])
	ok = ok and cold and thin
	result = {"ok": ok}
	print("[RivalTest] all ok: %s" % ok)


func _town() -> Node:
	return get_tree().get_first_node_in_group("town")


func _board() -> Node:
	return get_tree().get_first_node_in_group("job_board")
