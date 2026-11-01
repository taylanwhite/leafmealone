extends Node

## Authority: host. --town-test checks the persistent town (docs/SPINE.md): a
## new town has every neighborhood's houses with three Maple Row clients who all
## text on day one; the job board offers their requests; picking one loads that
## house's yard; a paid job moves the client's relationship, clears the request,
## and pays new-client XP; a happy client refers a neighbor; the next morning a
## yard done yesterday hasn't grown back enough to ask again; and rank opens the
## next neighborhood with a first client in it. A joined client named Target
## should see the same town ("town" in the probe report). Each step prints a
## [TownTest] line.

const _Hoods = preload("res://net/town/neighborhoods.gd")
const _Ranks = preload("res://core/ranks.gd")

static var result: Dictionary = {}

var _started: bool = false


func _process(_delta: float) -> void:
	if _started or not Net.is_host() or _town() == null or _board() == null or _own_player() == null:
		return
	if (_board().get("offers") as Array).is_empty():
		return
	_started = true
	_run()


func _run() -> void:
	var town := _town()
	var board := _board()
	var waited := 0.0
	while Net.peer_ids().size() < 2 and waited < 8.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	await get_tree().create_timer(1.5).timeout
	var ok := true
	var expected_houses := 0
	for hood: Dictionary in _Hoods.HOODS:
		expected_houses += int(hood["houses"])
	var houses: Array = town.get("houses")
	var known: Array = town.call("known_houses")
	var all_maple := true
	for entry: Variant in known:
		all_maple = all_maple and str((entry as Dictionary)["hood"]) == "maple_row"
	var made := houses.size() == expected_houses and known.size() == Constants.TOWN_STARTING_CLIENTS and all_maple
	print("[TownTest] %d houses (expected %d), %d known clients, all in Maple Row %s: %s" % [houses.size(), expected_houses, known.size(), all_maple, made])
	ok = ok and made
	var offers: Array = board.get("offers")
	var requests: Array = town.get("requests")
	var offered := offers.size() == Constants.TOWN_STARTING_CLIENTS and requests.size() == offers.size() and (offers[0] as Dictionary).has("client")
	print("[TownTest] day one: %d requests on the board, from %s: %s" % [offers.size(), (offers[0] as Dictionary).get("client", "?"), offered])
	ok = ok and offered
	# Pick the second request: that house's yard loads.
	board.call("request_choose", 1)
	await get_tree().create_timer(0.3).timeout
	# What Chefty setting off does: the picked house's yard loads.
	get_tree().get_first_node_in_group("world").call("_load_job_lot")
	await get_tree().create_timer(1.5).timeout
	var pick: Dictionary = board.call("current")
	var house_id := int(pick.get("house_id", -1))
	var lot := get_tree().get_first_node_in_group("job_lot")
	var loaded := lot != null and int(lot.get("job_seed")) == int(town.call("house", house_id)["seed"]) and absf(float(lot.get("mess")) - 1.0) < 0.001
	print("[TownTest] picked %s at %s: their yard loaded, full of leaves: %s" % [pick.get("client", "?"), town.call("address", house_id), loaded])
	ok = ok and loaded
	var working := int(town.get("current_house")) == house_id
	print("[TownTest] the town knows the crew is at that house: %s" % working)
	ok = ok and working
	# A great job.
	var xp_before := Campaign.pending_xp()
	Campaign.finish_job(120.0, {"mood": "thrilled", "tasks": []})
	await get_tree().create_timer(0.3).timeout
	var after: Dictionary = town.call("house", house_id)
	var expected_rel := Constants.TOWN_START_RELATIONSHIP + 2.0 * Constants.TOWN_RELATIONSHIP_PER_STAR + 2.0
	var paid := int(after.get("jobs", 0)) == 1 and int(after.get("last_day", -1)) == 1 and absf(float(after.get("relationship", 0.0)) - expected_rel) < 0.01 and not (town.get("requests") as Array).has(house_id)
	print("[TownTest] after a 5-star job: %d jobs, relationship %.0f (expected %.0f), request cleared: %s" % [int(after.get("jobs", 0)), float(after.get("relationship", 0.0)), expected_rel, paid])
	ok = ok and paid
	var new_client_xp := Campaign.pending_xp() - xp_before >= Constants.XP_NEW_CLIENT
	print("[TownTest] new-client XP paid (%d pending): %s" % [Campaign.pending_xp(), new_client_xp])
	ok = ok and new_client_xp
	# Make them a fan: the next good job there gets a referral.
	var known_before := (town.call("known_houses") as Array).size()
	after["relationship"] = 70.0
	town.call("start_job", house_id)
	Campaign.mark_job_open()
	Campaign.finish_job(120.0, {"mood": "thrilled", "tasks": []})
	await get_tree().create_timer(0.3).timeout
	var texts: Array = town.get("texts")
	var referral := (town.call("known_houses") as Array).size() == known_before + 1 and str((texts[texts.size() - 1] as Dictionary).get("kind", "")) == "request" and _has_kind(texts, "referral")
	print("[TownTest] a happy client referred a neighbor (%d clients now): %s" % [(town.call("known_houses") as Array).size(), referral])
	ok = ok and referral
	# Next morning: the yard done today hasn't grown back enough to ask.
	var clock := get_tree().get_first_node_in_group("day_clock")
	clock.call("force_sleep")
	await get_tree().create_timer(0.5).timeout
	var regrow := absf(float(town.call("mess", house_id)) - Constants.TOWN_REGROW_PER_DAY) < 0.001 and not (town.get("requests") as Array).has(house_id)
	print("[TownTest] day %d: the yard done yesterday is %.0f%% grown back and its owner waits: %s" % [int(clock.get("day")), float(town.call("mess", house_id)) * 100.0, regrow])
	ok = ok and regrow
	var morning := not (town.get("requests") as Array).is_empty()
	print("[TownTest] other clients texted this morning (%d requests): %s" % [(town.get("requests") as Array).size(), morning])
	ok = ok and morning
	# Rank opens Dandelion Acres; the next morning someone there is a client.
	var locked := not bool(town.call("is_hood_open", "dandelion_acres"))
	Campaign.add_xp(_xp_to(_Ranks.tier_of("hood:dandelion_acres")), "test")
	clock.call("force_sleep")
	await get_tree().create_timer(0.5).timeout
	var opened := bool(town.call("is_hood_open", "dandelion_acres")) and _known_in(town, "dandelion_acres") > 0
	print("[TownTest] Dandelion Acres was locked %s, opened at %s with %d client: %s" % [locked, _Ranks.title(Campaign.crew_tier()), _known_in(town, "dandelion_acres"), locked and opened])
	ok = ok and locked and opened
	await get_tree().create_timer(1.0).timeout
	result = {"ok": ok}
	print("[TownTest] all ok: %s" % ok)


## XP from what's banked to the start of this tier.
func _xp_to(tier: int) -> int:
	var total := 0
	for index: int in tier:
		total += _Ranks.xp_for_tier(index)
	return maxi(0, total - Campaign.crew_xp() - Campaign.pending_xp())


func _known_in(town: Node, hood_id: String) -> int:
	var count := 0
	for entry: Variant in (town.call("known_houses") as Array):
		if str((entry as Dictionary)["hood"]) == hood_id:
			count += 1
	return count


func _has_kind(texts: Array, kind: String) -> bool:
	for entry: Variant in texts:
		if str((entry as Dictionary).get("kind", "")) == kind:
			return true
	return false


func _town() -> Node:
	return get_tree().get_first_node_in_group("town")


func _board() -> Node:
	return get_tree().get_first_node_in_group("job_board")


func _own_player() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as Node3D
	return null
