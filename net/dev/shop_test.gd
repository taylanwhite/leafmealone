extends Node

## Authority: host. --shop-test checks the Shops node (net/shops/shops.gd):
## the catalog's data is whole; a Mk II buy takes exactly its price and the
## crew brings the better tool; locked, owned, far, sold-out and closed buys
## are refused with cash untouched; the morning restocks the shelves, clears
## buffs, and Marty tops up a crew out of bags; Rusty's fishing days; paying a
## crewmate; a bought hat is worn; and the "shops" save section round-trips.
## Run with --start-zone=lot --all-tools --rank=22 --start-hour=10 and a Target
## client that also has --shop-test (tools/ci_local.ps1 "shop", port 7814). The
## client half (_run_client) buys a hat and pays the host through the real
## client path (_rpc_request_buy, _rpc_request_give, _rpc_result) and reports
## its own shop_test; the host's "client_buy" step sees it land. CI also
## compares the host's "shops" report with the client's, which proves the state
## replicates. Later shop chunks add steps (bags, gas, tiers, junk, snacks,
## looks, deliveries). Each step prints a [ShopTest] line.

const _Shops = preload("res://net/shops/shops.gd")
const _Strings = preload("res://ui/strings.gd")
const _Ranks = preload("res://core/ranks.gd")
## What the client buys, so the host can tell its buy from its own.
const CLIENT_HAT: String = "hat_beanie"
## The host's starting cash for the client: the hat, the gift, and change.
const CLIENT_CASH: int = 500
## How long either side waits for the other (the client's buy, a result).
const WAIT_SECONDS: float = 20.0

static var result: Dictionary = {}

var _started: bool = false
var _steps: Dictionary = {}
## The client's results from the host, in order: [code, item, amount].
var _results: Array = []


func _process(_delta: float) -> void:
	if _started or _shops() == null:
		return
	if not Net.is_host():
		_started = true
		_run_client()
		return
	if get_tree().get_first_node_in_group("leaf_field") == null:
		return
	_started = true
	_run()


func _run() -> void:
	var waited := 0.0
	while Net.peer_ids().size() < 2 and waited < 10.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	await get_tree().create_timer(1.0).timeout
	if Net.peer_ids().size() < 2:
		_finish("the Target client never joined")
		return
	var shops := _shops()
	var me := Net.local_peer_id()
	var mate := -1
	for peer_id: int in Net.peer_ids():
		if peer_id != me:
			mate = peer_id
	_step("catalog", _check_catalog())
	# The client gets cash for its own buy (_run_client), before anyone is at the store.
	Campaign.pay(mate, CLIENT_CASH)
	var mate_cash := Campaign.credits(mate)
	var host_cash := Campaign.credits(me)
	# Everyone back at the store; the host walks up to Homie Depot's counter.
	for peer_id: int in Net.peer_ids():
		Net.move_player_to_zone(peer_id, Net.Zone.STORE)
	await get_tree().create_timer(0.6).timeout
	await _stand_at("homie_depot")

	# client_buy: the client walks to the counter, buys a hat and pays the host
	# $20 through the RPCs; here the host sees the hat on it and the cash move.
	var gift: int = Constants.PAY_CREWMATE_STEPS[0]
	var hat_price := Catalog.price(CLIENT_HAT)
	var client_wait := 0.0
	while client_wait < WAIT_SECONDS and not (str((shops.call("look_of", mate) as Dictionary).get("hat", "")) == CLIENT_HAT and Campaign.credits(me) - host_cash >= gift):
		await get_tree().create_timer(0.25).timeout
		client_wait += 0.25
	var mate_hat := str((shops.call("look_of", mate) as Dictionary).get("hat", ""))
	var mate_paid := mate_cash - Campaign.credits(mate)
	var host_got := Campaign.credits(me) - host_cash
	_step("client_buy", mate_hat == CLIENT_HAT and Campaign.peer_has_unlock(mate, StringName(CLIENT_HAT)) and mate_paid == hat_price + gift and host_got == gift,
		"client wears %s, paid $%d (hat $%d + $%d gift), host got $%d, after %.1f s" % [mate_hat, mate_paid, hat_price, gift, host_got, client_wait])

	# buy_tier: a Mk II for exactly its price, and the crew brings it.
	Campaign.pay(me, 9000)
	var cash := Campaign.credits(me)
	var code := str(shops.call("request_buy", "homie_depot", "leaf_blower_mk2", 1))
	var paid := cash - Campaign.credits(me)
	_step("buy_tier", code == "ok" and paid == Catalog.price("leaf_blower_mk2") \
		and Campaign.peer_has_unlock(me, &"leaf_blower_mk2") and Campaign.crew_tool_tier("leaf_blower") == Catalog.TIER_MK2,
		"code %s, paid $%d, crew blower tier %d" % [code, paid, Campaign.crew_tool_tier("leaf_blower")])
	cash = Campaign.credits(me)
	var mk3 := str(shops.call("request_buy", "homie_depot", "leaf_blower_mk3", 1))
	var roller := str(shops.call("request_buy", "homie_depot", "paint_roller_mk3", 1))
	var again := str(shops.call("request_buy", "homie_depot", "leaf_blower", 1))
	var elsewhere := str(shops.call("request_buy", "homie_depot", "hot_dog", 1))
	_step("refusals", mk3 == "locked" and roller == "locked" and again == "owned" and elsewhere == "unknown" and Campaign.credits(me) == cash,
		"Mk III %s, roller Mk III %s, a stock blower over a Mk II %s, a hot dog at Homie Depot %s" % [mk3, roller, again, elsewhere])

	# far: twelve-ish meters from every shop.
	var far_spot := Vector3(-2.0, 0.0, 6.0)
	var clear := true
	for shop: String in Catalog.SHOPS:
		var counter: Vector3 = (Constants.SHOP_SITES[shop] as Dictionary)["counter"]
		clear = clear and Vector2(far_spot.x - counter.x, far_spot.z - counter.z).length() > Constants.SHOP_REACH + Constants.SHOP_REACH_SLACK + 3.0
	await _stand_local(far_spot)
	var far := str(shops.call("request_buy", "homie_depot", "lawn_bags", 1))
	_step("far", clear and far == "far" and Campaign.credits(me) == cash, "code %s" % far)

	# stock: the day's twelve rolls, then sold out.
	await _stand_at("homie_depot")
	var bags := float(shops.call("supply", "lawn_bags"))
	var daily := int((Constants.SHOP_DAILY_STOCK["homie_depot"] as Dictionary)["lawn_bags"])
	var all := str(shops.call("request_buy", "homie_depot", "lawn_bags", daily))
	var added := float(shops.call("supply", "lawn_bags")) - bags
	var left := int(shops.call("stock_left", "homie_depot", "lawn_bags"))
	cash = Campaign.credits(me)
	var more := str(shops.call("request_buy", "homie_depot", "lawn_bags", 1))
	_step("stock", all == "ok" and is_equal_approx(added, float(daily * int(Constants.SUPPLY_PER_ITEM["lawn_bags"]))) and left == 0 \
		and more == "sold_out" and Campaign.credits(me) == cash,
		"bought %d rolls (%s, +%d bags, %d left), then %s" % [daily, all, int(added), left, more])

	# day_rollover: fresh shelves, no buffs, Marty's bags for a crew that ran out.
	var clock := get_tree().get_first_node_in_group("day_clock")
	var town := get_tree().get_first_node_in_group("town")
	var day_before := int(shops.get("stock_day"))
	var bags_before := float(shops.call("supply", "lawn_bags"))
	var big_before := float(shops.call("supply", "big_bags"))
	shops.call("dev_set_supply", "lawn_bags", 2)
	shops.call("dev_set_supply", "big_bags", 0)
	(shops.get("buffs") as Dictionary)[me] = {"full": Net.server_time() + 600.0}
	var texts_before := (town.get("texts") as Array).size() if town != null else 0
	clock.call("force_sleep")
	await get_tree().create_timer(0.6).timeout
	var texts: Array = town.get("texts") if town != null else []
	var marty := texts.size() > texts_before and str((texts[texts.size() - 1] as Dictionary).get("text", "")) == str(_Strings.SHOP_UI["text_emergency_bags"])
	var restocked := JSON.stringify(shops.get("stock"), "", true) == JSON.stringify(Constants.SHOP_DAILY_STOCK, "", true)
	var topped := is_equal_approx(float(shops.call("supply", "lawn_bags")), float(Constants.EMERGENCY_BAGS))
	_step("day_rollover", restocked and int(shops.get("stock_day")) == day_before + 1 and int(clock.get("day")) == day_before + 1 \
		and (shops.get("buffs") as Dictionary).is_empty() and topped and marty,
		"day %d, restocked %s, buffs %s, bags %d, Marty texted %s" % [int(shops.get("stock_day")), restocked, str(shops.get("buffs")), int(shops.call("supply", "lawn_bags")), marty])
	shops.call("dev_set_supply", "lawn_bags", bags_before)
	shops.call("dev_set_supply", "big_bags", big_before)

	# hours: Homie Depot closes at 9 PM; Rusty goes fishing every seventh day.
	clock.call("set_hour_for_tests", 22.0)
	await get_tree().create_timer(0.2).timeout
	cash = Campaign.credits(me)
	var closed := str(shops.call("request_buy", "homie_depot", "lawn_bags", 1))
	var shut := not bool(shops.call("is_open", "homie_depot")) and bool(shops.call("is_open", "snak_o_matic"))
	var opens := str(shops.call("opens_text", "homie_depot"))
	var rules: bool = _Shops.open_at("homie_depot", 7.0, 2) and not _Shops.open_at("homie_depot", 21.0, 2) \
		and _Shops.open_at("snak_o_matic", 25.5, 2) and not _Shops.open_at("rustys", 12.0, Constants.RUSTYS_CLOSED_EVERY) \
		and _Shops.open_at("rustys", 12.0, Constants.RUSTYS_CLOSED_EVERY + 1) and not _Shops.open_at("rustys", 18.5, 3) \
		and _Shops.hour_text(21.0) == "9 PM" and _Shops.hour_text(7.0) == "7 AM" and _Shops.hour_text(24.5) == "12 AM" \
		and _fishing_texts()
	clock.call("set_hour_for_tests", 12.0)
	await get_tree().create_timer(0.2).timeout
	var reopened := bool(shops.call("is_open", "homie_depot"))
	_step("hours", closed == "closed" and shut and Campaign.credits(me) == cash and rules and reopened and opens == "tomorrow, 7 AM",
		"at 10 PM: %s (opens %s); open again at noon %s; the open_at rules %s" % [closed, opens, reopened, rules])

	# give: exactly $20 to the crewmate; odd amounts and yourself are refused.
	var mine := Campaign.credits(me)
	var theirs := Campaign.credits(mate)
	var gave := str(shops.call("request_give", mate, Constants.PAY_CREWMATE_STEPS[0]))
	var moved := mine - Campaign.credits(me) == Constants.PAY_CREWMATE_STEPS[0] and Campaign.credits(mate) - theirs == Constants.PAY_CREWMATE_STEPS[0]
	var odd := str(shops.call("request_give", mate, 37))
	var selfish := str(shops.call("request_give", me, Constants.PAY_CREWMATE_STEPS[0]))
	_step("give", gave == "ok" and moved and odd == "give_invalid" and selfish == "give_invalid" and Campaign.credits(mate) - theirs == Constants.PAY_CREWMATE_STEPS[0],
		"gave $%d: %s; $37: %s; to yourself: %s" % [Constants.PAY_CREWMATE_STEPS[0], gave, odd, selfish])

	# wear: a bought hat goes straight on.
	var hat := str(shops.call("request_buy", "homie_depot", "hat_bucket", 1))
	var worn := str((shops.call("look_of", me) as Dictionary).get("hat", ""))
	_step("wear", hat == "ok" and worn == "hat_bucket" and Campaign.peer_has_unlock(me, &"hat_bucket"), "%s, wearing %s" % [hat, worn])

	# save: the section is written, and reads back into the same state.
	Campaign.save_now()
	_step("save", _check_save(shops, me))
	# Let the last snapshot reach the client before the reports.
	await get_tree().create_timer(1.0).timeout
	_finish("")


## When Rusty's opens, around his fishing day: the evening before it skips a
## day, the morning of it and the evening of a plain day say tomorrow, and a
## plain morning says the hour.
func _fishing_texts() -> bool:
	var fishing := Constants.RUSTYS_CLOSED_EVERY
	var face := _Shops.hour_text((Constants.SHOP_HOURS["rustys"] as Vector2).x)
	var cases := {
		"evening before fishing": [_Shops.opens_text_at("rustys", 19.0, fishing - 1), str(_Strings.SHOP_UI["shop_opens_day_after"]) % face],
		"fishing morning": [_Shops.opens_text_at("rustys", 8.0, fishing), str(_Strings.SHOP_UI["shop_opens_tomorrow"]) % face],
		"plain evening": [_Shops.opens_text_at("rustys", 19.0, fishing + 1), str(_Strings.SHOP_UI["shop_opens_tomorrow"]) % face],
		"plain morning": [_Shops.opens_text_at("rustys", 8.0, fishing + 1), face],
	}
	var ok := true
	for name: String in cases:
		var pair: Array = cases[name]
		if pair[0] != pair[1]:
			ok = false
			print("[ShopTest]   Rusty's %s says %s, not %s" % [name, pair[0], pair[1]])
	return ok


## The client half: once the host has sent it to the store with cash, it walks
## to Homie Depot's counter, buys CLIENT_HAT, tries an odd gift, and pays the
## host $20, all through Shops' requests, and checks each answer that comes back.
func _run_client() -> void:
	var shops := _shops()
	var me := Net.local_peer_id()
	var hat_price := Catalog.price(CLIENT_HAT)
	var gift: int = Constants.PAY_CREWMATE_STEPS[0]
	shops.connect("result", func(code: String, item: String, amount: int) -> void: _results.append([code, item, amount]))
	var waited := 0.0
	while waited < WAIT_SECONDS and not (Net.player_zone(me) == Net.Zone.STORE and Campaign.credits(me) >= hat_price + gift and bool(shops.call("is_open", "homie_depot"))):
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	if Net.player_zone(me) != Net.Zone.STORE or Campaign.credits(me) < hat_price + gift:
		_finish("the client was never sent to the store with cash")
		return
	# Let the host's teleport land, then stand at the counter and let the host see it.
	await get_tree().create_timer(0.6).timeout
	await _stand_at("homie_depot")
	await get_tree().create_timer(0.5).timeout

	var cash := Campaign.credits(me)
	var asked := str(shops.call("request_buy", "homie_depot", CLIENT_HAT, 1))
	await _await_results(1)
	waited = 0.0
	while waited < 3.0 and (cash - Campaign.credits(me) != hat_price or str((shops.call("look_of", me) as Dictionary).get("hat", "")) != CLIENT_HAT):
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	var answer: Array = _results[0] if _results.size() > 0 else []
	var worn := str((shops.call("look_of", me) as Dictionary).get("hat", ""))
	_step("client_buy", asked == "" and answer == ["ok", CLIENT_HAT, hat_price] and cash - Campaign.credits(me) == hat_price and worn == CLIENT_HAT,
		"asked %s, answer %s, paid $%d, wearing %s" % [asked, str(answer), cash - Campaign.credits(me), worn])

	# An odd amount is refused with its own code; then $20 goes to the host.
	shops.call("request_give", 1, gift + 17)
	await _await_results(2)
	cash = Campaign.credits(me)
	shops.call("request_give", 1, gift)
	await _await_results(3)
	waited = 0.0
	while waited < 3.0 and cash - Campaign.credits(me) != gift:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	var odd: Array = _results[1] if _results.size() > 1 else []
	var gave: Array = _results[2] if _results.size() > 2 else []
	_step("client_give", odd == ["give_invalid", "give", 0] and gave == ["ok", "give", gift] and cash - Campaign.credits(me) == gift,
		"odd gift %s, $%d gift %s, paid $%d" % [str(odd), gift, str(gave), cash - Campaign.credits(me)])
	_finish("")


func _await_results(count: int) -> void:
	var waited := 0.0
	while _results.size() < count and waited < 5.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1


func _check_catalog() -> bool:
	var strings := _Strings
	var problems: Array[String] = []
	for id: String in Catalog.ITEMS:
		var entry: Dictionary = Catalog.ITEMS[id]
		var shop := str(entry.get("shop", ""))
		if not strings.SHOP_UI.has("item_" + id) or not strings.SHOP_UI.has("item_blurb_" + id):
			problems.append("%s has no name or blurb" % id)
		if Catalog.price(id) < 0:
			problems.append("%s has no price" % id)
		if not Catalog.SHOPS.has(shop) or not ((Catalog.SHOPS[shop] as Dictionary)["tabs"] as Array).has(str(entry.get("tab", ""))):
			problems.append("%s is in an unknown shop or tab" % id)
		var tier := _Ranks.tier_of(Catalog.gate_of(id))
		if tier < 0 or tier > 39:
			problems.append("%s opens at tier %d" % [id, tier])
	for shop: String in Catalog.SHOPS:
		if not Constants.SHOP_SITES.has(shop) or not Constants.SHOP_HOURS.has(shop) or not Constants.SHOP_DAILY_STOCK.has(shop):
			problems.append("%s has no site, hours, or stock table" % shop)
		if not strings.SHOP_UI.has("shop_title_" + shop):
			problems.append("%s has no title" % shop)
	for shop: String in Constants.SHOP_DAILY_STOCK:
		for item: String in (Constants.SHOP_DAILY_STOCK[shop] as Dictionary):
			if str(Catalog.item(item).get("shop", "")) != shop:
				problems.append("%s stocks %s, which it doesn't sell" % [shop, item])
	for problem: String in problems:
		print("[ShopTest]   %s" % problem)
	print("[ShopTest] %d catalog items, %d problems" % [Catalog.ITEMS.size(), problems.size()])
	return problems.is_empty()


func _check_save(shops: Node, me: int) -> bool:
	var path := str(Campaign.call("_save_path"))
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("[ShopTest]   no save at %s" % path)
		return false
	var data: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(data) != TYPE_DICTIONARY or typeof((data as Dictionary).get("shops")) != TYPE_DICTIONARY:
		print("[ShopTest]   the save has no shops section")
		return false
	var section: Dictionary = data["shops"]
	var key := Campaign.key_of(me)
	var players: Dictionary = data.get("players", {})
	var unlocks: Array = (players.get(key, {}) as Dictionary).get("unlocks", [])
	# Read it into a fresh Shops, off the tree, and compare.
	var copy: Node = shops.get_script().new()
	copy.call("_read_section", section)
	var same := JSON.stringify(copy.get("supplies"), "", true) == JSON.stringify(shops.get("supplies"), "", true) \
		and JSON.stringify(copy.get("stock"), "", true) == JSON.stringify(shops.get("stock"), "", true) \
		and JSON.stringify(copy.get("looks"), "", true) == JSON.stringify(shops.get("looks"), "", true) \
		and int(copy.get("stock_day")) == int(shops.get("stock_day"))
	copy.free()
	var keys := true
	for field: String in ["version", "stock_day", "stock", "supplies", "orders", "looks", "truck", "crew_owned", "rusty_mood", "used_today", "junk_left", "vending_eaten"]:
		keys = keys and section.has(field)
	var saved_look: Variant = (section.get("looks", {}) as Dictionary).get(key, {})
	var hat := str((saved_look as Dictionary).get("hat", "")) if typeof(saved_look) == TYPE_DICTIONARY else ""
	print("[ShopTest]   every key %s, reads back the same %s, hat %s, Mk II saved %s" % [keys, same, hat, unlocks.has("leaf_blower_mk2")])
	return keys and same and hat == "hat_bucket" and unlocks.has("leaf_blower_mk2")


## The host stands at a shop's counter, on the customer's side.
func _stand_at(shop: String) -> void:
	var counter: Vector3 = (Constants.SHOP_SITES[shop] as Dictionary)["counter"]
	await _stand_local(counter + Vector3(0.0, 0.0, 1.8))


## The host stands at this point of the store zone.
func _stand_local(at: Vector3) -> void:
	var world := get_tree().get_first_node_in_group("world")
	var zone := world.get_node("StoreZone") as Node3D
	var me := _me()
	if me == null or zone == null:
		return
	me.global_position = zone.to_global(at + Vector3(0.0, 0.1, 0.0))
	if me is CharacterBody3D:
		(me as CharacterBody3D).velocity = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame


func _step(step: String, ok: bool, detail: String = "") -> void:
	_steps[step] = ok
	print("[ShopTest] %s: %s%s" % [step, ok, "" if detail == "" else " (%s)" % detail])


func _finish(error: String) -> void:
	var ok := error == "" and not _steps.is_empty() and not _steps.values().has(false)
	result = {"ok": ok, "done": true, "steps": _steps.duplicate()}
	if error != "":
		result["error"] = error
		print("[ShopTest] error: %s" % error)
	print("[ShopTest] all ok: %s" % ok)


func _shops() -> Node:
	return get_tree().get_first_node_in_group("shops")


func _me() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as Node3D
	return null
