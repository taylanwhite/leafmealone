extends Node

## Authority: host. --hire-test checks hired hands (net/crew/hires.gd,
## npcs/crew_hand.gd): hiring takes the signing fee and fills a slot; on the
## yard the hand rakes a pile, bags it, and loads it into Chefty by itself; a
## client sees the hand; at bedtime the crew pays the wage; letting the hand go
## frees the slot. Run with --start-zone=lot --rank=22 (Hedge Hog III, where
## hiring opens) and a Target client. Each step prints a [HireTest] line.

const WORK_SECONDS: float = 40.0

static var result: Dictionary = {}

var _started: bool = false


func _process(_delta: float) -> void:
	if _started or not Net.is_host() or _hires() == null or get_tree().get_first_node_in_group("leaf_field") == null:
		return
	_started = true
	_run()


func _run() -> void:
	var hires := _hires()
	var me := Net.local_peer_id()
	var waited := 0.0
	while Net.peer_ids().size() < 2 and waited < 8.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	await get_tree().create_timer(1.0).timeout
	var ok := true
	var open := int(hires.call("slots")) >= 1 and bool(hires.call("can_hire"))
	print("[HireTest] hiring is open at this rank (%d slot): %s" % [int(hires.call("slots")), open])
	ok = ok and open
	Campaign.call("_add_credits", me, 1000)
	var before := Campaign.credits(me)
	hires.call("request_hire")
	await get_tree().create_timer(0.3).timeout
	var hands: Array = hires.get("hands")
	var hired := hands.size() == 1 and Campaign.credits(me) == before - Constants.HIRE_SIGNING_FEE
	print("[HireTest] hired %s for $%d: %s" % [(hands[0] as Dictionary).get("name", "?") if not hands.is_empty() else "nobody", before - Campaign.credits(me), hired])
	ok = ok and hired
	hires.call("request_hire")
	await get_tree().create_timer(0.3).timeout
	var capped := (hires.get("hands") as Array).size() == 1
	print("[HireTest] a second hire is refused with one slot: %s" % capped)
	ok = ok and capped
	# The hand hops off Chefty and works the yard.
	var truck := get_tree().get_first_node_in_group("chefty")
	var bags_before := int(truck.call("bag_count"))
	hires.call("spawn_on_lot")
	await get_tree().create_timer(1.0).timeout
	var spawned := get_tree().get_nodes_in_group("crew_hands").size() == 1
	print("[HireTest] the hand is on the yard: %s" % spawned)
	ok = ok and spawned
	var worked := 0.0
	while worked < WORK_SECONDS and int(truck.call("bag_count")) <= bags_before:
		await get_tree().create_timer(1.0).timeout
		worked += 1.0
	var loaded := int(truck.call("bag_count")) > bags_before
	print("[HireTest] the hand raked, bagged, and loaded a bag into Chefty in %.0f s (%d bags, $%d): %s" % [worked, int(truck.call("bag_count")), int(truck.call("bag_value")), loaded])
	ok = ok and loaded
	# Bedtime: everyone back at the store, and payday.
	for peer_id: int in Net.peer_ids():
		Net.move_player_to_zone(peer_id, Net.Zone.STORE)
	await get_tree().create_timer(0.5).timeout
	var summaries: Array = []
	var clock := get_tree().get_first_node_in_group("day_clock")
	clock.connect("day_ended", func(summary: Dictionary) -> void: summaries.append(summary))
	var cash_before := 0
	for peer_id: int in Net.peer_ids():
		cash_before += Campaign.credits(peer_id)
	clock.call("force_sleep")
	await get_tree().create_timer(0.5).timeout
	var cash_after := 0
	for peer_id: int in Net.peer_ids():
		cash_after += Campaign.credits(peer_id)
	var wages: Dictionary = (summaries[0] as Dictionary).get("wages", {}) if not summaries.is_empty() else {}
	var paid := cash_before - cash_after == Constants.HIRE_DAILY_WAGE and int(wages.get("wages", 0)) == Constants.HIRE_DAILY_WAGE
	print("[HireTest] payday: the crew paid $%d in wages: %s" % [cash_before - cash_after, paid])
	ok = ok and paid
	var name_of := str((hires.get("hands") as Array)[0]["name"]) if not (hires.get("hands") as Array).is_empty() else ""
	hires.call("request_fire", name_of)
	await get_tree().create_timer(0.3).timeout
	var freed := (hires.get("hands") as Array).is_empty() and bool(hires.call("can_hire"))
	print("[HireTest] let %s go, the slot is free: %s" % [name_of, freed])
	ok = ok and freed
	await get_tree().create_timer(1.0).timeout
	result = {"ok": ok}
	print("[HireTest] all ok: %s" % ok)


func _hires() -> Node:
	return get_tree().get_first_node_in_group("hires")
