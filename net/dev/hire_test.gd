extends Node

const _KitRules = preload("res://core/kit_rules.gd")

## Authority: host. --hire-test checks hired hands (net/crew/hires.gd,
## npcs/crew_hand.gd): hiring takes the signing fee and fills a slot; on the
## yard the hand rakes a pile, bags it, and loads it into Chefty by itself; a
## client sees the hand; at bedtime the crew pays the wage; letting the hand go
## frees the slot. Then it checks Campaign's wallet API and the counter's rules
## (_check_wallet). Run with --start-zone=lot --rank=22 (Hedge Hog III, where
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
	# The signing fee and three days of wages, whatever balance:E makes them.
	Campaign.pay(me, Constants.HIRE_SIGNING_FEE + Constants.HIRE_DAILY_WAGE * 3)
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
	# The counter's buys go through the Shops node, which wants you at the counter.
	await _stand_at_counter()
	ok = _check_wallet(me) and ok
	await get_tree().create_timer(1.0).timeout
	result = {"ok": ok, "done": true}
	print("[HireTest] all ok: %s" % ok)


## The shops:1 wallet API and the old counter's rules (net/campaign.gd charge,
## _handle_purchase, tool_tier; core/catalog.gd price). All host-side and
## synchronous. Runs last so the bought rake and tools can't change the steps above.
func _check_wallet(me: int) -> bool:
	var ok := true
	Campaign.pay(me, 5000)
	var cash := Campaign.credits(me)
	var short := not Campaign.charge(me, cash + 1) and Campaign.credits(me) == cash
	var negative := not Campaign.charge(me, -5) and Campaign.credits(me) == cash
	print("[HireTest] charge refuses a short player and a negative amount, wallet untouched: %s" % (short and negative))
	ok = ok and short and negative
	Campaign.request_purchase(&"lawn_bags")
	var no_consumable := Campaign.credits(me) == cash and not Campaign.peer_has_unlock(me, &"lawn_bags")
	print("[HireTest] the counter won't sell a consumable as an unlock: %s" % no_consumable)
	ok = ok and no_consumable
	# p2-kit: The Leafinator is a rake you buy (no tune-up first), made in your
	# hands; its tier is the rake's, and it rakes at the workbook's growth twice.
	var shops := get_tree().get_first_node_in_group("shops")
	var code := str(shops.call("request_buy", "homie_depot", "rake_tier_2", 1))
	var paid := cash - Campaign.credits(me)
	var growth := Balance.TOOL_THROUGHPUT_GROWTH_MULTIPLIER
	var held := _KitRules.held_rake(get_tree(), me)
	var rake := code == "ok" and held != null and int(held.get("tier")) == Catalog.TIER_MK3 \
		and paid == Campaign.price_of(&"rake_tier_2") and not Campaign.peer_has_unlock(me, &"rake_tier_2") \
		and is_equal_approx(Campaign.rake_multiplier(me), growth * growth)
	print("[HireTest] bought The Leafinator (%s) for $%d, in hand %s, rake x%.2f: %s" % [code, paid, held != null, Campaign.rake_multiplier(me), rake])
	ok = ok and rake
	var none := Campaign.tool_tier(me, "leaf_blower") == Catalog.TIER_NONE
	get_tree().get_first_node_in_group("kit").call("host_deliver", me, "leaf_blower", Catalog.TIER_USED)
	var used := none and Campaign.tool_tier(me, "leaf_blower") == Catalog.TIER_USED \
		and Campaign.crew_tool_tier("leaf_blower") >= Catalog.TIER_USED \
		and Campaign.crew_tools().has("leaf_blower")
	print("[HireTest] a used leaf blower is tier %d and the crew owns it: %s" % [Campaign.tool_tier(me, "leaf_blower"), used])
	ok = ok and used
	var blower := float(Constants.TOOL_PRICES["leaf_blower"])
	var prices := Catalog.price("leaf_blower_mk2") == roundi(blower * Constants.TOOL_TIER_PRICE[Catalog.TIER_MK2]) \
		and Catalog.price("leaf_blower_used") == roundi(blower * Constants.TOOL_TIER_PRICE[Catalog.TIER_USED]) \
		and Catalog.price("vend_sandwich") == roundi(float(Constants.SHOP_PRICES["vend_sandwich"]) * Constants.VENDING_PRICE_SCALE) \
		and Catalog.price("no_such_item") == -1
	print("[HireTest] catalog prices apply the tier and vending markups: %s" % prices)
	ok = ok and prices
	return ok


## The host stands across Homie Depot's counter (Constants.SHOP_SITES).
func _stand_at_counter() -> void:
	var world := get_tree().get_first_node_in_group("world")
	var zone := world.get_node_or_null("StoreZone") as Node3D if world != null else null
	var counter: Vector3 = (Constants.SHOP_SITES["homie_depot"] as Dictionary)["counter"]
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()) and zone != null:
			(node as Node3D).global_position = zone.to_global(counter + Vector3(0.0, 0.1, 1.8))
	await get_tree().physics_frame
	await get_tree().physics_frame


func _hires() -> Node:
	return get_tree().get_first_node_in_group("hires")
