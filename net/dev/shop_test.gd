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
## replicates. On the yard first: bags get used up (and run out), gas burns and
## the gas can refills a tank, and the tier tables do what they say (shops chunk
## 3); then the client runs out of bags and refuels the mower through the RPCs
## (client_yard, _run_client_yard), and the save keeps the gas still in the job
## tools. Shops chunk 4 adds the shop you can see: the garden shelves' stock and
## tags (shelves), the catalog window buying at the counter (window), the
## keepers and hours signs at 10 PM and noon (keepers), and the ladder's reach
## per tier (in tier_math); the probe's shelf_units proves the client's shelves
## match. Shops chunk 5 adds Rusty's: his day (mood and rack), junk landing in
## Chefty's bed and hopping out at the tailgate (junk_bed), selling off his scale
## (sell: the needle reads the weight, the offer is the value times his mood),
## a haggle that sticks (haggle), and the client selling and buying a used tool
## off his rack through the RPCs (used_buy, the client's client_rusty). The
## review round adds: yard junk per hood (yard_junk), junk beside the platform
## isn't on the scale (scale_edge), a haggle surviving Chefty's bed and the
## morning (haggle_sticks), E heaving junk into the bed without beaning you
## (heave), Rusty's welcome text (welcome), the rack's other pallets staying put
## (in used_buy), the client's copy of the bed (in client_rusty), and junk_left
## saved and laid back out, bed and lot (junk_left). Shops chunk 6 adds the
## Snak-o-Matic at 10 PM (vending), Lunch Money at noon with every snack's
## effect and look (snack), and the client's own machine buy through the RPC
## (client_snack). Later shop chunks add steps (looks, deliveries). Each step
## prints a [ShopTest] line.

const _Shops = preload("res://net/shops/shops.gd")
const _Strings = preload("res://ui/strings.gd")
const _Ranks = preload("res://core/ranks.gd")
const _ToolTiers = preload("res://core/tool_tiers.gd")
const _Heat = preload("res://net/run_events/heat.gd")
const _ShopModels = preload("res://props/shop_models.gd")
const _JunkBed = preload("res://net/components/junk_bed.gd")
const _Hats = preload("res://player/hats.gd")
## What the client buys, so the host can tell its buy from its own.
const CLIENT_HAT: String = "hat_beanie"
## And what it buys at the Snak-o-Matic (shops chunk 6).
const CLIENT_SNACK: String = "vend_turbo"
## The host's starting cash for the client: the hat, the gift, and change.
const CLIENT_CASH: int = 500
## How long either side waits for the other (the client's buy, a result).
const WAIT_SECONDS: float = 20.0
## How long the client waits to be sent to the store: the host checks bags, gas
## and tiers on the yard first.
const CLIENT_WAIT_SECONDS: float = 45.0
## How long a gas tool with a nearly empty tank gets to run dry (it has 2 s of gas).
const RUN_DRY_SECONDS: float = 4.0
## The mower's tank (out of 100) the client fills up from the gas can.
const CLIENT_REFUEL_FROM: float = 50.0
## How long the client waits for one answer on the yard (a refusal, a fill).
const CLIENT_ANSWER_SECONDS: float = 4.0
## How long the client waits for the host's Rusty's cue after its own buys.
const CLIENT_RUSTY_WAIT_SECONDS: float = 70.0
## How long junk gets to land, settle, load or hop out (s).
const JUNK_SETTLE_SECONDS: float = 5.0
## How far from its predicted landing an unloaded piece may come to rest (m):
## it bounces and tumbles a little.
const JUNK_LAND_TOLERANCE: float = 1.2
## yard_junk: the made-up job seed a Dandelion Acres yard's junk is rolled from.
const YARD_JUNK_SEED: int = 424242

static var result: Dictionary = {}

var _started: bool = false
var _steps: Dictionary = {}
## The client's results from the host, in order: [code, item, amount].
var _results: Array = []
## Client: the host's cue for the yard half (_rpc_client_yard).
var _yard_cue: Dictionary = {}
## Client: the host's cue for Rusty's (_rpc_client_rusty): the used tool to buy
## and the junk on the scale to sell.
var _rusty_cue: Dictionary = {}


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
	_check_yard_junk()
	# On the yard, before the store: bags get used up, gas burns, tiers do their math.
	await _check_bags(shops)
	await _check_gas(shops)
	await _check_tier_math()
	await _check_client_yard(shops, mate)
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
	var eaten_before := int(shops.get("vending_eaten"))
	# The client also buys a warm Turbo Juice at the Snak-o-Matic (shops chunk 6):
	# it lands as its snack, or the machine keeps the money.
	var client_snacked := func() -> bool: return not (shops.call("snack_of", mate) as Dictionary).is_empty() or int(shops.get("vending_eaten")) > eaten_before
	while client_wait < WAIT_SECONDS and not (str((shops.call("look_of", mate) as Dictionary).get("hat", "")) == CLIENT_HAT and Campaign.credits(me) - host_cash >= gift and client_snacked.call()):
		await get_tree().create_timer(0.25).timeout
		client_wait += 0.25
	# Every peer plays a snack from the snapshot: here, the host's copy of the
	# client's body has to drink it too (or, if the machine kept the money, the
	# host's machine has its can stuck on a coil).
	var seen_here := false
	if not (shops.call("snack_of", mate) as Dictionary).is_empty():
		seen_here = await _ate(_player_node(mate), "drink", 4.0)
	elif int(shops.get("vending_eaten")) > eaten_before:
		var machine := get_tree().get_first_node_in_group("vending_machines")
		seen_here = machine != null and machine.get("_stuck") != null
	_step("client_snack", client_snacked.call() and seen_here, "the client's vend_turbo landed as %s, the machine ate %d, the host saw it %s" % [str(shops.call("snack_of", mate)), int(shops.get("vending_eaten")) - eaten_before, seen_here])
	# Its cash for the snack, so the hat-and-gift sum below still adds up.
	mate_cash -= Catalog.price(CLIENT_SNACK)
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

	# shelves and window (shops chunk 4): the garden shelves show today's stock,
	# and the catalog window, opened on an item, buys it at the counter.
	_step("shelves", await _check_shelves(shops))
	await _stand_at("homie_depot")
	await _check_window(shops, me)

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
	var keepers_late: Array[String] = await _check_keepers(shops, 22.0)
	var closed_free := Campaign.credits(me) == cash
	# vending (shops chunk 6): the Snak-o-Matic sells at 10 PM, when the rest is shut.
	_step("vending", await _check_vending(shops, me))
	clock.call("set_hour_for_tests", 12.0)
	await get_tree().create_timer(0.2).timeout
	var keepers_noon: Array[String] = await _check_keepers(shops, 12.0)
	# snack (shops chunk 6): Lunch Money at noon; what each snack does, and how it shows.
	_step("snack", await _check_snack(shops, me))
	var keeper_problems := keepers_late + keepers_noon
	for problem: String in keeper_problems:
		print("[ShopTest]   %s" % problem)
	_step("keepers", keeper_problems.is_empty(), "%d problems at 10 PM and noon" % keeper_problems.size())
	var reopened := bool(shops.call("is_open", "homie_depot"))
	_step("hours", closed == "closed" and shut and closed_free and rules and reopened and opens == "tomorrow, 7 AM",
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
	# Cosmetics (shops chunk 7): the hats themselves, a look going on a body in
	# place, the closet's swaps, and Chefty's paint and decal.
	await _stand_at("homie_depot")
	_step("hats", _check_hats())
	_step("cosmetics", await _check_cosmetics(shops, me, mate))
	_step("truck", await _check_truck(shops, me))

	# Rusty's (shops chunk 5).
	await _check_rustys(shops, me, mate)

	# save: the section is written, and reads back into the same state.
	Campaign.save_now()
	_step("save", _check_save(shops, me))
	await _check_junk_left(shops)
	# A stand-in truck, after everything the client waits on (it adds ~2.4 s).
	_step("paint_pull_away", await _check_paint_pull_away())
	# Let the last snapshot reach the client before the reports.
	await get_tree().create_timer(1.0).timeout
	_finish("")


## hats (shops chunk 7): every hat item names a style player/hats.gd builds,
## each one stays under its triangle budget, and none comes down in front of the
## eyes (R2b: the old cap's brim cut across them).
func _check_hats() -> bool:
	var problems: Array[String] = []
	for id: String in Catalog.ITEMS:
		var entry: Dictionary = Catalog.ITEMS[id]
		if str(entry.get("slot", "")) == "hat" and not _Hats.has_style(str(entry.get("style", ""))):
			problems.append("%s wears an unknown style %s" % [id, str(entry.get("style", ""))])
	for style: String in _Hats.STYLES:
		var count := _Hats.triangles(style)
		var lowest := _Hats.lowest_over_eyes(style)
		if count > _Hats.MAX_TRIANGLES:
			problems.append("%s costs %d triangles" % [style, count])
		if lowest <= _Hats.EYE_TOP:
			problems.append("%s comes down to %.3f in front of the eyes" % [style, lowest])
		print("[ShopTest]   hat %s: %d triangles, lowest over the eyes %.3f" % [style, count, lowest])
	for problem: String in problems:
		print("[ShopTest]   %s" % problem)
	return problems.is_empty()


## cosmetics (shops chunk 7): the host's bought bucket hat is on its body, the
## client's beanie on the client's body here; a shirt dye and the hi-vis vest go
## on the same body in place (same node, same arm pivots), every hat part on
## the own-head layer (never at the first-person lens); the closet takes the
## hat off and puts it back; a hat you don't own is refused.
func _check_cosmetics(shops: Node, me: int, mate: int) -> bool:
	var ok := true
	await get_tree().create_timer(0.3).timeout
	var body := _player_node(me).get_node_or_null("Visual/CartoonBody") if _player_node(me) != null else null
	var mate_body := _player_node(mate).get_node_or_null("Visual/CartoonBody") if _player_node(mate) != null else null
	if body == null or mate_body == null:
		print("[ShopTest]   no bodies (host %s, client %s)" % [body != null, mate_body != null])
		return false
	var bucket := str(body.get("hat_style")) == "bucket"
	var beanie := str(mate_body.get("hat_style")) == "beanie"
	var arm_before := body.call("pose_part", "arm_r") as Node3D
	var shirt := str(shops.call("request_buy", "homie_depot", "shirt_3", 1))
	await get_tree().create_timer(0.2).timeout
	var dyed := (body.get("shirt") as Color).is_equal_approx(Constants.SHIRT_DYES[3]) and str((shops.call("look_of", me) as Dictionary).get("shirt", "")) == "shirt_3"
	var same_body: bool = _player_node(me).get_node_or_null("Visual/CartoonBody") == body and (body.call("pose_part", "arm_r") as Node3D) == arm_before
	var vest := str(shops.call("request_buy", "homie_depot", "shirt_hivis", 1))
	await get_tree().create_timer(0.2).timeout
	var vested := str(body.get("vest")) == "hivis" and body.find_child("Vest", true, false) != null
	# Off to the hat your name gives you, then back on (the closet's Wear).
	var off := str(shops.call("request_equip", "hat", ""))
	await get_tree().create_timer(0.1).timeout
	var bare := str(body.get("hat_style")) in ["cap", "hair"] and str((shops.call("look_of", me) as Dictionary).get("hat", "")) == ""
	var not_mine := str(shops.call("request_equip", "hat", "hat_cowboy"))
	var on := str(shops.call("request_equip", "hat", "hat_bucket"))
	await get_tree().create_timer(0.1).timeout
	var back := str(body.get("hat_style")) == "bucket"
	# It drops on, then sits: nothing left mid-air.
	var waited := 0.0
	while waited < 2.0 and bool(body.call("dressing")):
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	# The hat is on the head, which is the player's Head node, not under the body.
	var hat := _player_node(me).find_child("Hat", true, false) as Node3D
	var head_bit := 1 << (preload("res://player/cartoon_body.gd").HEAD_LAYER - 1)
	var on_head_layer := hat != null
	if hat != null:
		for node: Node in hat.find_children("*", "MeshInstance3D", true, false):
			on_head_layer = on_head_layer and (node as MeshInstance3D).layers == head_bit
	var sat := hat != null and hat.transform.is_equal_approx(_Hats.build("bucket", Color.BLACK)["at"])
	ok = bucket and beanie and shirt == "ok" and dyed and same_body and vest == "ok" and vested and off == "worn" and bare \
		and not_mine == "not_owned" and on == "worn" and back and on_head_layer and sat
	print("[ShopTest] cosmetics: %s (bucket on the host %s, beanie on the client %s; shirt %s dyed %s same body %s; vest %s on %s; off %s bare %s; cowboy %s; back on %s %s; on the own-head layer %s, sat %s)" % [ok, bucket, beanie, shirt, dyed, same_body, vest, vested, off, bare, not_mine, on, back, on_head_layer, sat])
	return ok


## truck (shops chunk 7): Mint paint bought goes on Chefty (with the show, as
## it's standing still), googly eyes too, with their pupils; the factory red and
## no decal go back on from the counter; paint the crew doesn't own is refused.
## It ends mint with googly eyes, for the client's report to match.
func _check_truck(shops: Node, me: int) -> bool:
	var chefty := get_tree().get_first_node_in_group("chefty")
	var paint := chefty.get_node_or_null("Paint") if chefty != null else null
	if paint == null:
		print("[ShopTest]   no Chefty paint (%s)" % [chefty != null])
		return false
	var shows := int(paint.get("repaints"))
	var mint := str(shops.call("request_buy", "homie_depot", "paint_mint", 1))
	var mint_on := await _truck_shows(paint, Constants.CHEFTY_PAINTS["paint_mint"], "")
	var googly := str(shops.call("request_buy", "homie_depot", "decal_googly", 1))
	var googly_on := await _truck_shows(paint, Constants.CHEFTY_PAINTS["paint_mint"], "decal_googly")
	var look := chefty.get_node_or_null("Body/TruckLook")
	var pupils := look != null and look.get_node_or_null("GooglyEye0/Pupil") != null and look.get_node_or_null("GooglyEye1/Pupil") != null and look.get_node_or_null("Decal") != null
	var red := str(shops.call("request_apply_truck", "paint_classic"))
	var peel := str(shops.call("request_apply_truck", ""))
	var plain := await _truck_shows(paint, Constants.CHEFTY_PAINTS["paint_classic"], "")
	look = chefty.get_node_or_null("Body/TruckLook")
	var no_decal := look != null and look.get_node_or_null("Decal") == null and look.get_node_or_null("GooglyEye0") == null
	var gold := str(shops.call("request_apply_truck", "paint_gold"))
	var again := str(shops.call("request_apply_truck", "paint_mint"))
	var eyes := str(shops.call("request_apply_truck", "decal_googly"))
	var last := await _truck_shows(paint, Constants.CHEFTY_PAINTS["paint_mint"], "decal_googly")
	var played := int(paint.get("repaints")) - shows
	var ok := mint == "ok" and mint_on and googly == "ok" and googly_on and pupils and red == "applied" and peel == "applied" \
		and plain and no_decal and gold == "not_owned" and again == "applied" and eyes == "applied" and last and played >= 3 \
		and (shops.get("crew_owned") as Array).has("paint_mint")
	print("[ShopTest] truck: %s (mint %s on %s; googly %s on %s, pupils %s; red %s, peeled %s, plain %s no decal %s; gold %s; mint and eyes again %s %s %s; %d repaints shown)" % [ok, mint, mint_on, googly, googly_on, pupils, red, peel, plain, no_decal, gold, again, eyes, last, played])
	return ok


## paint_pull_away (critic C22, W8 review): a truck that drives off inside the
## paint cloud, before the swap, keeps its old paint (the cloud is left behind),
## and the show plays again once it parks. On a stand-in truck, so the real
## Chefty's look stays what the client's report expects.
func _check_paint_pull_away() -> bool:
	var stand_in_script := GDScript.new()
	stand_in_script.source_code = "extends Node3D\nvar moving := false\nvar applied := 0\nfunc is_moving() -> bool:\n\treturn moving\nfunc apply_paint(_color: Color, _decal: String) -> void:\n\tapplied += 1\n"
	stand_in_script.reload()
	var truck := Node3D.new()
	truck.set_script(stand_in_script)
	var body := Node3D.new()
	body.name = "Body"
	truck.add_child(body)
	var paint: Node = preload("res://net/components/chefty_paint.gd").new()
	paint.set("vehicle", truck)
	paint.set("shown", {"color": Constants.CHEFTY_PAINTS["paint_classic"], "decal": ""})
	paint.set("_wanted", {"color": Constants.CHEFTY_PAINTS["paint_mint"], "decal": ""})
	truck.add_child(paint)
	add_child(truck)
	await get_tree().create_timer(0.1).timeout
	var started := int(paint.get("repaints")) == 1
	# Pulls away at once, inside the cloud.
	truck.set("moving", true)
	await get_tree().create_timer(Constants.REPAINT_SECONDS + 0.4).timeout
	var kept := int(truck.get("applied")) == 0 and not bool(paint.call("is_settled"))
	var no_new_show := int(paint.get("repaints")) == 1
	# Parks: sprayed again, and it goes on this time.
	truck.set("moving", false)
	await get_tree().create_timer(Constants.REPAINT_SWAP_AT + 0.3).timeout
	var sprayed := int(paint.get("repaints")) == 2 and int(truck.get("applied")) == 1
	truck.queue_free()
	var ok := started and kept and no_new_show and sprayed
	print("[ShopTest] paint_pull_away: %s (show started %s; driving off kept the old paint %s, no show on the road %s; parked and sprayed %s)" % [ok, started, kept, no_new_show, sprayed])
	return ok


## Waits (up to 4 s) for Chefty to show this paint and decal, settled.
func _truck_shows(paint: Node, color: Color, decal: String) -> bool:
	var waited := 0.0
	while waited < 4.0:
		var shown: Dictionary = paint.get("shown")
		if bool(paint.call("is_settled")) and not shown.is_empty() and (shown["color"] as Color).is_equal_approx(color) and str(shown["decal"]) == decal:
			return true
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	return false


## bags: every pile bagged takes one bag from the crew's supply; out of bags,
## nothing is bagged and the leaves stay put ("no_bags"); a contractor bag goes
## first and scoops wider.
func _check_bags(shops: Node) -> void:
	var field := get_tree().get_first_node_in_group("leaf_field")
	var spots := _leafy_spots(field, 3)
	if spots.size() < 3:
		_step("bags", false, "found only %d leafy spots on the yard" % spots.size())
		return
	var lawn_before := float(shops.call("supply", "lawn_bags"))
	var big_before := float(shops.call("supply", "big_bags"))
	var reasons: Array[String] = []
	var heard := func(_peer_id: int, reason: String) -> void: reasons.append(reason)
	field.connect("bag_refused", heard)
	shops.call("dev_set_supply", "big_bags", 0)
	shops.call("dev_set_supply", "lawn_bags", 2)
	# One bag: a bag prop, and the supply goes 2 to 1.
	var bags := _count_kind("leaf_bag")
	await _stand_world(spots[0] - Vector3(1.5, 0.0, 0.0))
	field.call("request_collect", spots[0], Constants.BAG_RADIUS)
	await _ticks(3)
	var made := _count_kind("leaf_bag") == bags + 1
	var used := is_equal_approx(float(shops.call("supply", "lawn_bags")), 1.0)
	# None left: no bag, the leaves untouched, and why.
	shops.call("dev_set_supply", "lawn_bags", 0)
	await _stand_world(spots[1] - Vector3(1.5, 0.0, 0.0))
	var units := int(field.call("units_within_world", spots[1], Constants.BAG_RADIUS))
	field.call("request_collect", spots[1], Constants.BAG_RADIUS)
	await _ticks(3)
	var refused := _count_kind("leaf_bag") == bags + 1 and int(field.call("units_within_world", spots[1], Constants.BAG_RADIUS)) == units and reasons.has("no_bags")
	var hint := str((_me().call("interaction_hint") as Dictionary).get("text", ""))
	# A contractor bag goes first, even with lawn bags left, and clears a wider circle.
	shops.call("dev_set_supply", "big_bags", 1)
	shops.call("dev_set_supply", "lawn_bags", 5)
	var wide := Constants.BAG_RADIUS * Constants.BIG_BAG_RADIUS_SCALE
	await _stand_world(spots[2] - Vector3(1.5, 0.0, 0.0))
	field.call("request_collect", spots[2], Constants.BAG_RADIUS)
	await _ticks(3)
	var big := _count_kind("leaf_bag") == bags + 2 and is_equal_approx(float(shops.call("supply", "big_bags")), 0.0) \
		and is_equal_approx(float(shops.call("supply", "lawn_bags")), 5.0) and int(field.call("units_within_world", spots[2], wide - 0.3)) == 0
	field.disconnect("bag_refused", heard)
	shops.call("dev_set_supply", "lawn_bags", lawn_before)
	shops.call("dev_set_supply", "big_bags", big_before)
	_step("bags", made and used and refused and big and hint == str(_Strings.SHOP_UI["hud_out_of_bags"]),
		"bagged %s (supply 2 -> 1 %s); out of bags refused %s (%s, %d units stay), hint \"%s\"; contractor bag first and wider %s" % [made, used, refused, str(reasons), units, hint, big])


## gas: Chefty filled each gas tool's tank and sent the rest along in the gas
## can; a tank burns while it runs, sputters dry, won't start empty, and the
## gas can fills it back up.
func _check_gas(shops: Node) -> void:
	var mower := _job_prop("lawn_mower")
	var can := _job_prop("gas_can")
	if mower == null or can == null:
		_step("gas", false, "no mower (%s) or gas can (%s) came along" % [mower != null, can != null])
		return
	var gas_tools := 0
	for node: Node in get_tree().get_nodes_in_group("props"):
		if not node.is_queued_for_deletion() and _ToolTiers.is_gas_tool(str(node.get("kind"))):
			gas_tools += 1
	var in_can := _ToolTiers.can_gallons(can)
	var spent := float(Constants.STARTER_SUPPLIES["gas"]) - float(shops.call("supply", "gas"))
	var loaded := is_equal_approx(float(mower.get("fuel")), 100.0) and int(mower.get("tier")) == Catalog.TIER_STOCK \
		and is_equal_approx(spent, Constants.GAS_PER_TANK * float(gas_tools) + in_can) and in_can > 0.0
	# Grab the mower, leave it a splash of gas, and start it.
	await _stand_world(mower.global_position + Vector3(0.0, 0.1, 1.2))
	mower.call("request_grab")
	await _ticks(3)
	mower.set("fuel", 1.0)
	for _pull: int in 12:
		if bool(mower.get("spraying")):
			break
		mower.call("request_start")
		await _ticks(2)
	var started := bool(mower.get("spraying"))
	var waited := 0.0
	while waited < RUN_DRY_SECONDS and bool(mower.get("spraying")):
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	var dry := not bool(mower.get("spraying")) and float(mower.get("fuel")) <= 0.0
	# Empty, it won't start, however hard you pull.
	for _pull: int in 4:
		mower.call("request_start")
		await _ticks(2)
	var dead := not bool(mower.get("spraying")) and _ToolTiers.has_fuel(mower) == false
	# Put it down, pick up the gas can, and fill it up.
	mower.call("request_drop")
	await _ticks(3)
	can.call("request_grab")
	await _ticks(4)
	var holding := int(can.get("held_by")) == Net.local_peer_id()
	# The out-of-gas notice from the dead mower has the prompt for a moment first.
	await get_tree().create_timer(Constants.SUPPLY_NOTICE_SECONDS + 0.2).timeout
	var prompt := str((_me().call("interaction_hint") as Dictionary).get("text", ""))
	var target: Variant = can.call("refuel_target")
	can.call("request_refuel")
	await _ticks(2)
	var full := is_equal_approx(float(mower.get("fuel")), 100.0)
	var poured := in_can - _ToolTiers.can_gallons(can)
	can.call("request_drop")
	await _ticks(3)
	_step("gas", loaded and started and dry and dead and holding and target == mower and full and is_equal_approx(poured, Constants.GAS_PER_TANK) \
		and prompt == str(_Strings.SHOP_UI["prompt_refuel"]) % 0,
		"tanks full and %.1f gal in the can (%.1f spent for %d gas tools) %s; started %s, ran dry in %.1f s %s, dead %s; held the can %s, prompt \"%s\", filled %s, poured %.2f gal" % [in_can, spent, gas_tools, loaded, started, waited, dry, dead, holding, prompt, full, poured])


## client_yard: a client runs out of bags and refuels through the real RPCs
## (_rpc_request_collect answered by _rpc_bag_refused "no_bags", and
## _rpc_request_refuel). The host empties the bags and half the mower's tank,
## tells the client where (_rpc_client_yard), and sees nothing bagged, the
## leaves untouched, and the tank filled from the gas can the client holds.
func _check_client_yard(shops: Node, mate: int) -> void:
	var field := get_tree().get_first_node_in_group("leaf_field")
	var mower := _job_prop("lawn_mower")
	var can := _job_prop("gas_can")
	var spots := _leafy_spots(field, 1)
	if mower == null or can == null or spots.is_empty():
		_step("client_yard", false, "no mower (%s), gas can (%s) or leafy spot (%d)" % [mower != null, can != null, spots.size()])
		return
	if Net.player_zone(mate) != Net.Zone.LOT:
		Net.move_player_to_zone(mate, Net.Zone.LOT)
		await get_tree().create_timer(0.6).timeout
	var lawn_before := float(shops.call("supply", "lawn_bags"))
	var big_before := float(shops.call("supply", "big_bags"))
	shops.call("dev_set_supply", "lawn_bags", 0)
	shops.call("dev_set_supply", "big_bags", 0)
	mower.set("fuel", CLIENT_REFUEL_FROM)
	var in_can := _ToolTiers.can_gallons(can)
	var need := (100.0 - CLIENT_REFUEL_FROM) / 100.0 * Constants.GAS_PER_TANK
	var bags := _count_kind("leaf_bag")
	var units := int(field.call("units_within_world", spots[0], Constants.BAG_RADIUS))
	_rpc_client_yard.rpc_id(mate, spots[0], mower.get_path(), can.get_path())
	var waited := 0.0
	var held := false
	while waited < WAIT_SECONDS and not (held and is_equal_approx(float(mower.get("fuel")), 100.0) and int(can.get("held_by")) == 0):
		held = held or int(can.get("held_by")) == mate
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	var full := is_equal_approx(float(mower.get("fuel")), 100.0)
	var poured := in_can - _ToolTiers.can_gallons(can)
	var untouched := _count_kind("leaf_bag") == bags and int(field.call("units_within_world", spots[0], Constants.BAG_RADIUS)) == units \
		and is_equal_approx(float(shops.call("supply", "lawn_bags")), 0.0) and is_equal_approx(float(shops.call("supply", "big_bags")), 0.0)
	shops.call("dev_set_supply", "lawn_bags", lawn_before)
	shops.call("dev_set_supply", "big_bags", big_before)
	_step("client_yard", in_can >= need and untouched and held and full and is_equal_approx(poured, need),
		"no bag and %d units stay %s; the client held the can %s, tank %.0f%% (poured %.2f of %.2f gal), after %.1f s" % [units, untouched, held, float(mower.get("fuel")), poured, need, waited])


## The host's cue for the client's yard half (_run_client_yard): where to bag,
## and the half-empty mower and the gas can to fill it from.
@rpc("authority", "call_remote", "reliable")
func _rpc_client_yard(spot: Vector3, mower_path: NodePath, can_path: NodePath) -> void:
	_yard_cue = {"spot": spot, "mower": mower_path, "can": can_path}


## tier_math: what each tier does, from the tables (core/tool_tiers.gd,
## Heat.noise_for); and a tier set on a tool reaches its look on this peer
## (and, through the shops report's tools, the client's copy).
func _check_tier_math() -> void:
	var problems: Array[String] = []
	if not is_equal_approx(_Heat.noise_for("leaf_blower", Catalog.TIER_MK2), float(Constants.HEAT_NOISE_PER_SECOND["leaf_blower"]) * 0.7):
		problems.append("a Mk II blower's noise is %.3f" % _Heat.noise_for("leaf_blower", Catalog.TIER_MK2))
	for kind: String in Constants.HEAT_NOISE_PER_SECOND:
		if not (_Heat.noise_for(kind, 0) > _Heat.noise_for(kind, 1) and _Heat.noise_for(kind, 1) > _Heat.noise_for(kind, 2) and _Heat.noise_for(kind, 2) > _Heat.noise_for(kind, 3)):
			problems.append("%s isn't quieter at every tier" % kind)
	if not (_ToolTiers.start_chance(0, 0) < _ToolTiers.start_chance(1, 0) and _ToolTiers.start_chance(1, 0) < _ToolTiers.start_chance(2, 0)) or not is_equal_approx(_ToolTiers.start_chance(3, 0), 1.0):
		problems.append("pull-start chances %s" % str([_ToolTiers.start_chance(0, 0), _ToolTiers.start_chance(1, 0), _ToolTiers.start_chance(2, 0), _ToolTiers.start_chance(3, 0)]))
	if not is_equal_approx(_ToolTiers.hose_length(3), float(Constants.MK3_PERKS["hose"])) or not is_equal_approx(_ToolTiers.hose_length(2), Constants.HOSE_LENGTH * Constants.TOOL_TIER_REACH[2]):
		problems.append("hose lengths %.1f, %.1f" % [_ToolTiers.hose_length(2), _ToolTiers.hose_length(3)])
	if not is_equal_approx(_ToolTiers.washer_use(3), Constants.WASHER_USE_PER_SECOND / float(Constants.MK3_PERKS["pressure_washer"])) or _ToolTiers.trimmer_spots(3) != 2 or _ToolTiers.trimmer_spots(2) != 1:
		problems.append("washer use %.2f, trimmer spots %d" % [_ToolTiers.washer_use(3), _ToolTiers.trimmer_spots(3)])
	if not (_ToolTiers.burn_per_second("leaf_blower", 0) > _ToolTiers.burn_per_second("leaf_blower", 1) and _ToolTiers.burn_per_second("leaf_blower", 1) > _ToolTiers.burn_per_second("leaf_blower", 3)):
		problems.append("fuel use doesn't drop with the tier")
	if _ToolTiers.tool_name("leaf_blower", Catalog.TIER_MK2) != str(_Strings.SHOP_UI["item_leaf_blower_mk2"]) or _ToolTiers.tool_name("hose", Catalog.TIER_STOCK) != _Strings.item_name("hose"):
		problems.append("tool names %s, %s" % [_ToolTiers.tool_name("leaf_blower", 2), _ToolTiers.tool_name("hose", 1)])
	# The yard's blower becomes a Mk II: its look rebuilds with the trim.
	var blower := _job_prop("leaf_blower")
	if blower == null:
		problems.append("no blower came along")
	else:
		blower.set("tier", Catalog.TIER_MK2)
		await _ticks(2)
		var look := blower.get_node_or_null("Visual/Look")
		if look == null or int(look.get_meta("tier", 1)) != Catalog.TIER_MK2:
			problems.append("the blower's look didn't take its tier")
	# The ladder's reach at the gutters goes with its tier (shops chunk 4), read
	# from whichever ladder is set up by the worker (job_tasks.ladder_tier_near).
	for tier: int in range(Catalog.TIER_USED, Catalog.TIER_MK3 + 1):
		if not is_equal_approx(_ToolTiers.ladder_reach(tier), Constants.LADDER_TOP_REACH * Constants.TOOL_TIER_REACH[tier]):
			problems.append("a tier %d ladder reaches %.2f m" % [tier, _ToolTiers.ladder_reach(tier)])
	if not (_ToolTiers.ladder_reach(Catalog.TIER_MK3) > _ToolTiers.ladder_reach(Catalog.TIER_STOCK)):
		problems.append("a Mk III ladder doesn't reach farther")
	var tasks := get_tree().get_first_node_in_group("job_tasks")
	if tasks == null:
		problems.append("no job tasks")
	else:
		var me := _me()
		var near := me.global_position if me != null else Vector3.ZERO
		var none := int(tasks.call("ladder_tier_near", near))
		# A stand-in set-up Mk III ladder, in and out of the props group within this
		# one frame, so nothing else ever sees it.
		var stand_in := FakeLadder.new()
		stand_in.ladder_top = near + Vector3(0.4, 2.0, 0.0)
		add_child(stand_in)
		stand_in.add_to_group("props")
		var found := int(tasks.call("ladder_tier_near", near))
		stand_in.remove_from_group("props")
		remove_child(stand_in)
		stand_in.free()
		if none != Catalog.TIER_STOCK or found != Catalog.TIER_MK3:
			problems.append("the ladder near the worker is tier %d with none set up, %d with a Mk III up" % [none, found])
	for problem: String in problems:
		print("[ShopTest]   %s" % problem)
	_step("tier_math", problems.is_empty(), "%d problems" % problems.size())


## shelves: the garden center's shelves (props/shelf_stock.gd) show today's
## stock: the day's lawn bags just sold out, a box per gas can left, the next
## tier of each tool with its price, or a tarp and the rank for one the crew's
## rank hasn't opened; and walking up to a slot prompts "Look at ...".
func _check_shelves(shops: Node) -> bool:
	var shelf := get_tree().get_first_node_in_group("shelf_stock")
	if shelf == null:
		print("[ShopTest]   no shelf stock in the store")
		return false
	shelf.call("refresh")
	var problems: Array[String] = []
	var bags: Dictionary = shelf.call("slot_state", "lawn_bags")
	if str(bags.get("look")) != "sold_out" or int(bags.get("units", -1)) != 0 or str(bags.get("tag")) != str(_Strings.SHOP_UI["shop_sold_out"]):
		problems.append("sold-out lawn bags show %s" % str(bags))
	var gas: Dictionary = shelf.call("slot_state", "gas_can")
	var gas_left := int(shops.call("stock_left", "homie_depot", "gas_can"))
	if int(gas.get("units", -1)) != mini(gas_left, Constants.SHELF_MAX_UNITS) or str(gas.get("tag")) != str(_Strings.SHOP_UI["shop_price_tag"]) % Catalog.price("gas_can"):
		problems.append("gas cans (%d left) show %s" % [gas_left, str(gas)])
	if _drawn_units(shelf, "gas_can") != int(gas.get("units", -1)):
		problems.append("the gas can slot draws %d boxes for %d" % [_drawn_units(shelf, "gas_can"), int(gas.get("units", -1))])
	# The host owns a Mk II blower (buy_tier): the Mk III is next, and rank 22 is short of it.
	var blower: Dictionary = shelf.call("slot_state", "leaf_blower")
	var rank := _Ranks.title(_Ranks.tier_of(Catalog.gate_of("leaf_blower_mk3")))
	if str(blower.get("item")) != "leaf_blower_mk3" or str(blower.get("look")) != "locked" or str(blower.get("tag")) != str(_Strings.SHOP_UI["shop_rank_tag"]) % rank:
		problems.append("the blower slot shows %s" % str(blower))
	var trimmer: Dictionary = shelf.call("slot_state", "hedge_trimmer")
	if str(trimmer.get("item")) != "hedge_trimmer_mk2" or str(trimmer.get("tag")) != str(_Strings.SHOP_UI["shop_price_tag"]) % Catalog.price("hedge_trimmer_mk2"):
		problems.append("the trimmer slot shows %s" % str(trimmer))
	# Walking up to a slot on each level (a unit's levels share one spot in
	# front of it; the head's pitch picks the level): the gas cans up top, the
	# ladder in the middle and the lawn bags at the bottom.
	var me := _me()
	for item: String in ["gas_can", "ladder", "lawn_bags"]:
		var slot := int(shelf.call("slot_of", item))
		var front: Vector3 = shelf.call("slot_front", slot)
		await _stand_world(Vector3(front.x, 0.0, front.z))
		if me != null:
			me.set("head_pitch", float(shelf.call("pitch_to", slot)))
		var prompt := str((shelf.call("prompt") as Dictionary).get("text", ""))
		var shown := str((shelf.call("slot_state", item) as Dictionary).get("item", item))
		if prompt != str(_Strings.SHOP_UI["prompt_look_at"]) % _Strings.shop_item_name(shown):
			problems.append("looking at the %s prompts \"%s\"" % [item, prompt])
	if me != null:
		me.set("head_pitch", 0.0)
	for problem: String in problems:
		print("[ShopTest]   %s" % problem)
	return problems.is_empty()


## How many boxes a shelf slot really draws.
func _drawn_units(shelf: Node, item: String) -> int:
	var holder := shelf.get_node_or_null("Slot_" + item)
	if holder == null:
		return -1
	var count := 0
	for child: Node in holder.get_children():
		if child is MeshInstance3D and not child.is_queued_for_deletion():
			count += 1
	return count


## window: the shop window (ui/shop_window.gd), opened on the gas can as the
## shelf does, lands on the Supplies tab with that card picked out; its x1
## button buys one through Shops at the counter (cash, supply, stock and the
## shelf all move, and the toast says so); the Tools tab is one card per tool
## with the next tier, the locked Mk III's button off.
func _check_window(shops: Node, me: int) -> void:
	var ui := get_tree().get_first_node_in_group("game_ui")
	var window := ui.get_node_or_null("ShopWindow") if ui != null else null
	if window == null:
		_step("window", false, "no ShopWindow")
		return
	var problems: Array[String] = []
	ui.call("open_shop", "homie_depot", "", "gas_can")
	await _ticks(2)
	var tabs: Array = (Catalog.SHOPS["homie_depot"] as Dictionary)["tabs"]
	if not window.visible or str(window.get("tab")) != "supplies" or (window.get("_tabs") as Node).get_child_count() != tabs.size():
		problems.append("opened on the gas can: visible %s, tab %s, %d tabs" % [window.visible, window.get("tab"), (window.get("_tabs") as Node).get_child_count()])
	var cards := window.get("_cards") as Node
	if cards.get_child_count() != (window.call("_items") as Array).size():
		problems.append("%d cards for %d items" % [cards.get_child_count(), (window.call("_items") as Array).size()])
	var focus := window.get("_focus_card") as Node
	if focus == null or str(focus.get_meta("item", "")) != "gas_can":
		problems.append("the gas can isn't picked out")
	var buy := _card_button(cards, "gas_can", 1)
	var cash := Campaign.credits(me)
	var gas := float(shops.call("supply", "gas"))
	var left := int(shops.call("stock_left", "homie_depot", "gas_can"))
	if buy == null or buy.disabled:
		problems.append("no x1 button on the gas can's card")
	else:
		buy.emit_signal("pressed")
		await _ticks(2)
		var shelf := get_tree().get_first_node_in_group("shelf_stock")
		var units := int((shelf.call("slot_state", "gas_can") as Dictionary).get("units", -1)) if shelf != null else -1
		var toast := str(window.call("toast_text"))
		if cash - Campaign.credits(me) != Catalog.price("gas_can") or not is_equal_approx(float(shops.call("supply", "gas")) - gas, float(Constants.SUPPLY_PER_ITEM["gas_can"])) \
			or int(shops.call("stock_left", "homie_depot", "gas_can")) != left - 1 or units != mini(left - 1, Constants.SHELF_MAX_UNITS) \
			or toast != str(_Strings.SHOP_UI["shop_result_ok"]) % _Strings.shop_item_name("gas_can"):
			problems.append("the x1 gas can: paid $%d, gas +%.1f, %d left of %d, shelf %d boxes, toast \"%s\"" % [cash - Campaign.credits(me), float(shops.call("supply", "gas")) - gas, int(shops.call("stock_left", "homie_depot", "gas_can")), left, units, toast])
	window.call("show_tab", "tools")
	await _ticks(1)
	var items: Array = window.call("_items")
	if cards.get_child_count() != Catalog.TOOLS.size() or items.size() != Catalog.TOOLS.size() or str((items[0] as Dictionary).get("id")) != "leaf_blower_mk3":
		problems.append("the tools tab: %d cards, first %s" % [cards.get_child_count(), str((items[0] as Dictionary).get("id")) if not items.is_empty() else "-"])
	var locked := _card_button(cards, "leaf_blower_mk3", 1)
	if locked == null or not locked.disabled:
		problems.append("the locked Mk III blower can be clicked")
	window.call("close_window")
	for problem: String in problems:
		print("[ShopTest]   %s" % problem)
	_step("window", problems.is_empty(), "%d problems" % problems.size())


## A card's buy button for qty, from the window's grid.
func _card_button(cards: Node, item: String, qty: int) -> Button:
	for card: Node in cards.get_children():
		if card.is_queued_for_deletion() or str(card.get_meta("item", "")) != item:
			continue
		for node: Node in card.find_children("*", "Button", true, false):
			if str(node.get_meta("action", "")) == "buy" and int(node.get_meta("qty", 0)) == qty:
				return node as Button
	return null


## vending (shops chunk 6), at 10 PM with Homie Depot shut: the gas-station-
## adjacent sandwich at the Snak-o-Matic is charged once, at the marked-up
## vending price, and either lands (its stock drops, a front snack falls in the
## machine, the buyer is full or queasy and their body eats it: three bites,
## then a belly pat or a burp) or the machine keeps the money (vending_eaten up,
## stock and buffs untouched, a snack stuck on its coil, its screen says thanks).
func _check_vending(shops: Node, me: int) -> bool:
	var problems: Array[String] = []
	await _stand_at("snak_o_matic")
	var machine := get_tree().get_first_node_in_group("vending_machines")
	if machine == null:
		print("[ShopTest]   no Snak-o-Matic in the store")
		return false
	var cash := Campaign.credits(me)
	var eaten := int(shops.get("vending_eaten"))
	var left := int(shops.call("stock_left", "snak_o_matic", "vend_sandwich"))
	var price := Catalog.price("vend_sandwich")
	var code := str(shops.call("request_buy", "snak_o_matic", "vend_sandwich", 1))
	var paid := cash - Campaign.credits(me)
	if paid != price or price <= int(Constants.SHOP_PRICES["vend_sandwich"]):
		problems.append("paid $%d of the vending price $%d (base $%d)" % [paid, price, int(Constants.SHOP_PRICES["vend_sandwich"])])
	await get_tree().create_timer(1.0).timeout
	var shelf_count := int(machine.call("front_count"))
	var stocked := 0
	for item: Variant in (shops.get("stock") as Dictionary).get("snak_o_matic", {}):
		stocked += int((shops.get("stock") as Dictionary)["snak_o_matic"][item])
	if code == "ok":
		var snack: Dictionary = shops.call("snack_of", me)
		var buff := str(snack.get("buff", ""))
		if str(snack.get("item", "")) != "vend_sandwich" or not (buff == "full" or buff == "queasy") or not bool(shops.call("has_buff", me, buff)):
			problems.append("the sandwich landed as %s" % str(snack))
		if int(shops.call("stock_left", "snak_o_matic", "vend_sandwich")) != left - 1 or int(shops.get("vending_eaten")) != eaten:
			problems.append("stock %d -> %d, eaten %d -> %d" % [left, int(shops.call("stock_left", "snak_o_matic", "vend_sandwich")), eaten, int(shops.get("vending_eaten"))])
		# One front snack a unit in stock, less what's stuck on a coil today.
		var stuck := (shops.get("vending_stuck") as Array).size()
		if shelf_count != stocked - stuck:
			problems.append("the machine shows %d snacks for %d in stock (%d stuck)" % [shelf_count, stocked, stuck])
		if not await _ate(_me(), "eat", 4.0):
			problems.append("the body never ate it")
		var after := "gesture belly_pat" if buff == "full" else "burp"
		var eater := _me().get_node_or_null("Visual/CartoonBody/SnackEater")
		var waited := 0.0
		while waited < 4.0 and eater != null and not (eater.get("log_lines") as Array).has(after):
			await get_tree().create_timer(0.1).timeout
			waited += 0.1
		var lines: Array = eater.get("log_lines") if eater != null else []
		if lines.count("munch") != Constants.SNACK_EAT_BITES.size() or not lines.has(after):
			problems.append("eating went %s" % str(lines))
	elif code == "eaten":
		if int(shops.get("vending_eaten")) != eaten + 1 or int(shops.call("stock_left", "snak_o_matic", "vend_sandwich")) != left or bool(shops.call("has_buff", me, "full")) or bool(shops.call("has_buff", me, "queasy")):
			problems.append("eaten, but eaten %d -> %d, stock %d" % [eaten, int(shops.get("vending_eaten")), int(shops.call("stock_left", "snak_o_matic", "vend_sandwich"))])
		if str(machine.get("last_trigger")) != "eaten" or machine.get("_stuck") == null:
			problems.append("the machine's screen says %s (%s), stuck %s" % [machine.get("last_line"), machine.get("last_trigger"), machine.get("_stuck") != null])
	else:
		problems.append("the Snak-o-Matic said %s at 10 PM" % code)
	print("[ShopTest]   vending: %s, paid $%d" % [code, paid])
	for problem: String in problems:
		print("[ShopTest]   %s" % problem)
	shops.call("dev_clear_buffs", me)
	return problems.is_empty()


## snack (shops chunk 6), at noon at Lunch Money: Turbo Juice gives the turbo
## buff with a future expiry: legs x1.2 and the rake's swing x0.8 (RakeStroke,
## the one tempo hook), its icon on the HUD, and the body drinks it and
## shudders; when it runs out it chains into the crash (legs x0.75), which
## yawns as it hits. A hot dog is full (heavy things slow you half as much),
## eaten in three bites and a belly pat; burnt coffee holds a strain 1.6x as long.
func _check_snack(shops: Node, me: int) -> bool:
	var problems: Array[String] = []
	await _stand_at("lunch_money")
	var body := _me()
	var cash := Campaign.credits(me)
	var code := str(shops.call("request_buy", "lunch_money", "turbo_juice", 1))
	var mine: Dictionary = (shops.get("buffs") as Dictionary).get(me, {})
	var ends := float(mine.get("turbo", 0.0))
	var base := Constants.RAKE_STROKE_SECONDS * float(Constants.RAKE_SWING_STROKES)
	if code != "ok" or ends < Net.server_time() + float(Constants.BUFFS["turbo"]["seconds"]) - 5.0:
		problems.append("turbo juice: %s, turbo runs out at %.1f (now %.1f)" % [code, ends, Net.server_time()])
	if not is_equal_approx(float(shops.call("buff", me, "speed")), 1.2) or not is_equal_approx(float(body.call("snack_buff", "speed")), 1.2) \
		or not is_equal_approx(RakeStroke.cycle_seconds(me), base * 0.8):
		problems.append("turbo: speed x%.2f (legs x%.2f), a swing %.3f s of %.3f" % [float(shops.call("buff", me, "speed")), float(body.call("snack_buff", "speed")), RakeStroke.cycle_seconds(me), base])
	await _ticks(2)
	var ui := get_tree().get_first_node_in_group("game_ui")
	var row := ui.get_node_or_null("HudRows/BuffRow") if ui != null else null
	# The row redraws on process frames: on a loaded machine two physics ticks
	# can pass inside one of them, so give it a few frames (W8: it read []).
	for _frame: int in 10:
		if row == null or (row.get("shown") as Array).has("turbo"):
			break
		await get_tree().process_frame
	if row == null or not (row.get("shown") as Array).has("turbo"):
		problems.append("the HUD shows %s" % (str(row.get("shown")) if row != null else "no buff row"))
	if not await _ate(body, "drink", 4.0):
		problems.append("the turbo juice was never drunk")
	var eater := body.get_node_or_null("Visual/CartoonBody/SnackEater")
	var waited := 0.0
	while waited < 4.0 and eater != null and not (eater.get("log_lines") as Array).has("gesture turbo_shake"):
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	if eater == null or not (eater.get("log_lines") as Array).has("slurp") or not (eater.get("log_lines") as Array).has("gesture turbo_shake"):
		problems.append("drinking went %s" % (str(eater.get("log_lines")) if eater != null else "no eater"))
	# The turbo runs out (as the host's clock would see it then): the crash follows on.
	shops.call("_expire_buffs", ends + 0.5)
	mine = (shops.get("buffs") as Dictionary).get(me, {})
	if mine.has("turbo") or not is_equal_approx(float(mine.get("crash", 0.0)), ends + float(Constants.BUFFS["crash"]["seconds"])) \
		or not is_equal_approx(float(shops.call("buff", me, "speed")), 0.75):
		problems.append("after turbo: %s, speed x%.2f" % [str(mine), float(shops.call("buff", me, "speed"))])
	# A crash that hits now yawns.
	(shops.get("buffs") as Dictionary)[me] = {"crash": Net.server_time() + float(Constants.BUFFS["crash"]["seconds"])}
	shops.call("_broadcast")
	waited = 0.0
	while waited < 2.0 and not (eater.get("log_lines") as Array).has("yawn"):
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	if not (eater.get("log_lines") as Array).has("yawn"):
		problems.append("the crash never yawned")
	shops.call("dev_clear_buffs", me)
	# A hot dog: full; three bites and a pat on the belly.
	code = str(shops.call("request_buy", "lunch_money", "hot_dog", 1))
	if code != "ok" or not is_equal_approx(float(body.call("snack_buff", "carry")), 0.5):
		problems.append("hot dog: %s, carry x%.2f" % [code, float(body.call("snack_buff", "carry"))])
	waited = 0.0
	var before := (eater.get("log_lines") as Array).count("munch")
	while waited < 5.0 and not ((eater.get("log_lines") as Array).count("munch") >= before + Constants.SNACK_EAT_BITES.size() and (eater.get("log_lines") as Array).has("gesture belly_pat")):
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	if (eater.get("log_lines") as Array).count("munch") < before + Constants.SNACK_EAT_BITES.size() or not (eater.get("log_lines") as Array).has("gesture belly_pat"):
		problems.append("the hot dog went %s" % str(eater.get("log_lines")))
	# Burnt coffee: hold on longer.
	code = str(shops.call("request_buy", "lunch_money", "coffee", 1))
	if code != "ok" or not is_equal_approx(float(body.call("snack_buff", "strain")), float(Constants.BUFFS["coffee"]["strain"])):
		problems.append("coffee: %s, strain x%.2f" % [code, float(body.call("snack_buff", "strain"))])
	var spent := cash - Campaign.credits(me)
	var prices := Catalog.price("turbo_juice") + Catalog.price("hot_dog") + Catalog.price("coffee")
	if spent != prices:
		problems.append("paid $%d for $%d of snacks" % [spent, prices])
	for problem: String in problems:
		print("[ShopTest]   %s" % problem)
	# Clean: the reports compare buffs, and these would run out on their own clock.
	await get_tree().create_timer(0.3).timeout
	shops.call("dev_clear_buffs", me)
	# Back at Homie Depot's counter, where the steps after this one buy.
	await _stand_at("homie_depot")
	return problems.is_empty()


## keepers at an hour (shops chunk 4): each shop's keeper (npcs/store_clerk.gd)
## is behind the counter exactly while their shop is open, except Marty, who
## never leaves; at Homie Depot's counter the prompt is "Shop" while it's open
## and "Closed. Opens ..." after, still with its key since Marty's there to
## answer E (only an absent keeper's closed prompt is plain); the window shows its shutter when
## closed; and the hours sign says the same. Returns the problems found.
func _check_keepers(shops: Node, hour: float) -> Array[String]:
	var problems: Array[String] = []
	var clock := get_tree().get_first_node_in_group("day_clock")
	var day := int(clock.get("day"))
	var keepers := {}
	for node: Node in get_tree().get_nodes_in_group("shopkeepers"):
		keepers[str(node.get("shop_id"))] = node
	for shop: String in Catalog.SHOPS:
		var keeper_id := str((Catalog.SHOPS[shop] as Dictionary).get("keeper", ""))
		if keeper_id == "":
			continue
		if not keepers.has(shop):
			problems.append("%s has no keeper" % shop)
			continue
		var keeper: Node3D = keepers[shop]
		var open := _Shops.open_at(shop, hour, day)
		var there := open or shop == "homie_depot"
		await _ticks(1)
		if bool(keeper.call("is_present")) != there or keeper.visible != there or str(keeper.get("keeper")) != keeper_id:
			problems.append("at %d:00 %s (open %s) is there %s, visible %s" % [int(hour), keeper_id, open, keeper.call("is_present"), keeper.visible])
	await _stand_at("homie_depot")
	var marty: Node = keepers.get("homie_depot")
	var open := _Shops.open_at("homie_depot", hour, day)
	if marty != null:
		var prompt: Dictionary = marty.call("prompt")
		var want := str(_Strings.UI["prompt_shop"]) if open else str(_Strings.SHOP_UI["prompt_shop_closed"]) % str(shops.call("opens_text", "homie_depot"))
		# Marty is always there, so E always does something: never a plain notice.
		if str(prompt.get("text", "")) != want or bool(prompt.get("plain", false)):
			problems.append("at %d:00 Marty's counter prompts %s" % [int(hour), str(prompt)])
	var ui := get_tree().get_first_node_in_group("game_ui")
	var window := ui.get_node_or_null("ShopWindow") if ui != null else null
	if window != null:
		ui.call("open_shop", "homie_depot")
		await _ticks(2)
		var shutter := window.get("_shutter") as Control
		if shutter == null or shutter.visible == open:
			problems.append("at %d:00 the window's shutter is %s" % [int(hour), "down" if shutter != null and shutter.visible else "up"])
		window.call("close_window")
	var site := get_tree().get_first_node_in_group("world").get_node_or_null("StoreZone/ShopSite_homie_depot")
	var signs: Array[Node] = site.find_children("HoursSign", "", true, false) if site != null else []
	if signs.is_empty():
		problems.append("Homie Depot has no hours sign")
	else:
		signs[0].call("_refresh")
		var title := str(_Strings.SHOP_UI["shop_title_homie_depot"]).to_upper()
		var hours: Vector2 = Constants.SHOP_HOURS["homie_depot"]
		var want := str(_Strings.SHOP_UI["shop_sign_open"]) % [title, _Shops.hour_text(hours.x), _Shops.hour_text(hours.y)] if open \
			else str(_Strings.SHOP_UI["shop_sign_closed"]) % [title, str(shops.call("opens_text", "homie_depot"))]
		if str(signs[0].get("text")) != want:
			problems.append("at %d:00 the sign says %s" % [int(hour), str(signs[0].get("text")).replace("\n", " / ")])
	return problems


## A stand-in for a set-up ladder prop (tier_math): the three things
## job_tasks.ladder_tier_near reads.
class FakeLadder extends Node:
	var kind: String = "ladder"
	var tier: int = Catalog.TIER_MK3
	var ladder_top := Vector3.ZERO


## Up to count spots on the yard thick enough with leaves to bag (with a
## contractor bag's wider scoop to spare), at least 5 m apart.
func _leafy_spots(field: Node, count: int) -> Array[Vector3]:
	var lot := get_tree().get_first_node_in_group("world").get_node("LotZone") as Node3D
	var need := int(Constants.MIN_BAG_CELLS * float(field.get("INITIAL_DENSITY"))) * 2
	var found: Array[Vector3] = []
	for z: float in [6.0, -6.0, 10.0, -10.0, 2.0, -2.0, 14.0, -14.0]:
		for x: float in [-14.0, 14.0, -9.0, 9.0, -4.0, 4.0]:
			var spot := lot.global_position + Vector3(x, 0.2, z)
			if int(field.call("units_within_world", spot, Constants.BAG_RADIUS)) < need:
				continue
			if found.any(func(other: Vector3) -> bool: return other.distance_to(spot) < 5.0):
				continue
			found.append(spot)
			if found.size() >= count:
				return found
	return found


func _count_kind(kind: String) -> int:
	return get_tree().get_nodes_in_group("props").filter(func(node: Node) -> bool: return str(node.get("kind")) == kind and not node.is_queued_for_deletion()).size()


func _job_prop(kind: String) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("job_tools"):
		if str(node.get("kind")) == kind and not node.is_queued_for_deletion():
			return node as Node3D
	return null


## The host stands here, in world space.
func _stand_world(at: Vector3) -> void:
	var me := _me()
	if me == null:
		return
	me.global_position = at + Vector3(0.0, 0.1, 0.0)
	if me is CharacterBody3D:
		(me as CharacterBody3D).velocity = Vector3.ZERO
	await _ticks(2)


func _ticks(count: int) -> void:
	for _tick: int in count:
		await get_tree().physics_frame


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
	await _run_client_yard()
	var waited := 0.0
	while waited < CLIENT_WAIT_SECONDS and not (Net.player_zone(me) == Net.Zone.STORE and Campaign.credits(me) >= hat_price + gift and bool(shops.call("is_open", "homie_depot"))):
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	if Net.player_zone(me) != Net.Zone.STORE or Campaign.credits(me) < hat_price + gift:
		_finish("the client was never sent to the store with cash")
		return
	# Let the host's teleport land, then stand at the counter and let the host see it.
	await get_tree().create_timer(0.6).timeout
	await _stand_at("homie_depot")
	await get_tree().create_timer(0.5).timeout
	# Before anyone paints it (the host's truck step comes later): this peer's
	# Chefty already shows the look it joined to, quietly, so the first paint job
	# gets its cloud here too (W8: the first snapshot never said truck_changed
	# for a factory-red truck, and the observer's Chefty swapped in one frame).
	var chefty := get_tree().get_first_node_in_group("chefty")
	var paint := chefty.get_node_or_null("Paint") if chefty != null else null
	var joined_look: Dictionary = paint.get("shown") if paint != null else {}
	_step("client_truck_look", paint != null and not joined_look.is_empty() and int(paint.get("repaints")) == 0, "shows %s, %d repaints" % [str(joined_look), int(paint.get("repaints")) if paint != null else -1])

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
	# The snack first: the host waits for it with client_buy, while Rusty's cue
	# only comes once the host has done Rusty's own steps (W7 integration).
	_step("client_snack", await _run_client_snack(shops, me))
	await _run_client_rusty(shops, me)
	_step("client_equip", await _run_client_equip(shops, me))
	_finish("")


## The client's closet (shops chunk 7): it takes its beanie off and puts it back
## on through _rpc_request_equip; each answer is "worn", and its own body here
## shows the hat it should.
func _run_client_equip(shops: Node, me: int) -> bool:
	var before := _results.size()
	var asked := str(shops.call("request_equip", "hat", ""))
	await _await_results(before + 1)
	var waited := 0.0
	var body := _player_node(me).get_node_or_null("Visual/CartoonBody") if _player_node(me) != null else null
	while waited < 2.0 and body != null and str(body.get("hat_style")) == "beanie":
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	var bare := body != null and str(body.get("hat_style")) != "beanie"
	shops.call("request_equip", "hat", CLIENT_HAT)
	await _await_results(before + 2)
	waited = 0.0
	while waited < 2.0 and body != null and str(body.get("hat_style")) != "beanie":
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	var off: Array = _results[before] if _results.size() > before else []
	var on: Array = _results[before + 1] if _results.size() > before + 1 else []
	var back := body != null and str(body.get("hat_style")) == "beanie"
	# The host's truck step is done by now: this peer's Chefty sprayed its new
	# look on with the show too (W8: a client that never learned the first look
	# swapped the next one in a frame), and ends mint with googly eyes.
	var paint := get_tree().get_first_node_in_group("chefty").get_node_or_null("Paint") if get_tree().get_first_node_in_group("chefty") != null else null
	var sprayed := paint != null and int(paint.get("repaints")) >= 1
	var shown: Dictionary = paint.get("shown") if paint != null else {}
	var mint := not shown.is_empty() and (shown["color"] as Color).is_equal_approx(Constants.CHEFTY_PAINTS["paint_mint"]) and str(shown["decal"]) == "decal_googly"
	print("[ShopTest] client_equip: off %s %s bare %s, on %s back %s; Chefty here sprayed %s (%d repaints), mint with googly eyes %s" % [asked, str(off), bare, str(on), back, sprayed, int(paint.get("repaints")) if paint != null else -1, mint])
	return asked == "" and off.size() > 0 and str(off[0]) == "worn" and bare and on.size() > 0 and str(on[0]) == "worn" and back and sprayed and mint


## The client's snack (shops chunk 6): at the Snak-o-Matic it buys a warm Turbo
## Juice through _rpc_request_buy. The machine either sells it (the turbo buff
## comes back in the snapshot, this player's legs and rake both take it, and
## its body drinks it) or keeps the money ("eaten": charged, no buff, a snack
## stuck on its coil). Either way it's charged exactly the vending price once.
func _run_client_snack(shops: Node, me: int) -> bool:
	await _stand_at("snak_o_matic")
	await get_tree().create_timer(0.5).timeout
	var cash := Campaign.credits(me)
	var before := _results.size()
	shops.call("request_buy", "snak_o_matic", CLIENT_SNACK, 1)
	await _await_results(before + 1)
	var answer: Array = _results[before] if _results.size() > before else []
	var code := str(answer[0]) if answer.size() > 0 else ""
	var waited := 0.0
	var price := Catalog.price(CLIENT_SNACK)
	while waited < 3.0 and cash - Campaign.credits(me) != price:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	var paid := cash - Campaign.credits(me)
	var ok := false
	var detail := ""
	if code == "ok":
		waited = 0.0
		while waited < 3.0 and not is_equal_approx(float(shops.call("buff", me, "speed")), 1.2):
			await get_tree().create_timer(0.1).timeout
			waited += 0.1
		var body := _me()
		var legs := float(body.call("snack_buff", "speed")) if body != null else 0.0
		var base := Constants.RAKE_STROKE_SECONDS * float(Constants.RAKE_SWING_STROKES)
		var swing := RakeStroke.cycle_seconds(me)
		var drank := await _ate(body, "drink", 4.0)
		ok = is_equal_approx(legs, 1.2) and is_equal_approx(swing, base * 0.8) and drank
		detail = "turbo: legs x%.2f, a swing %.2f s of %.2f, drank it %s" % [legs, swing, base, drank]
	elif code == "eaten":
		ok = is_equal_approx(float(shops.call("buff", me, "speed")), 1.0)
		detail = "the machine kept it, no buff %s" % ok
	print("[ShopTest]   client snack: %s, paid $%d of $%d, %s" % [code, paid, price, detail])
	return ok and paid == price and answer.size() == 3 and int(answer[2]) == price


## Whether this player's body plays the snack gesture (player/snack_eater.gd's
## log) within seconds.
func _ate(body: Node, gesture_name: String, seconds: float) -> bool:
	var eater := body.get_node_or_null("Visual/CartoonBody/SnackEater") if body != null else null
	if eater == null:
		return false
	var waited := 0.0
	while waited < seconds:
		if (eater.get("log_lines") as Array).has("gesture " + gesture_name):
			return true
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	return false


## The client's yard half (the host's client_yard step): out of bags, its bag
## request comes back refused ("no_bags") and the leaves stay; holding the gas
## can by the half-empty mower, its refuel request fills the tank.
func _run_client_yard() -> void:
	var waited := 0.0
	while _yard_cue.is_empty() and waited < CLIENT_WAIT_SECONDS:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	if _yard_cue.is_empty():
		_step("client_yard", false, "the host never sent the yard cue")
		return
	var field := get_tree().get_first_node_in_group("leaf_field")
	var mower := get_node_or_null(_yard_cue["mower"] as NodePath) as Node3D
	var can := get_node_or_null(_yard_cue["can"] as NodePath) as Node3D
	if field == null or mower == null or can == null:
		_step("client_yard", false, "no leaf field (%s), mower (%s) or gas can (%s) here" % [field != null, mower != null, can != null])
		return
	var spot: Vector3 = _yard_cue["spot"]
	# The host's emptied supply and half tank arrive just ahead of the cue.
	waited = 0.0
	while waited < CLIENT_ANSWER_SECONDS and (str(field.call("bag_type")) != "" or float(mower.get("fuel")) >= 100.0):
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	var reasons: Array[String] = []
	var heard := func(_peer_id: int, reason: String) -> void: reasons.append(reason)
	field.connect("bag_refused", heard)
	# Stand by the pile long enough for the host's copy of this player to be there too.
	await _stand_world(spot - Vector3(1.5, 0.0, 0.0))
	await get_tree().create_timer(0.6).timeout
	var units := int(field.call("units_within_world", spot, Constants.BAG_RADIUS))
	field.call("request_collect", spot, Constants.BAG_RADIUS)
	waited = 0.0
	while waited < CLIENT_ANSWER_SECONDS and reasons.is_empty():
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	# The host's snapshot of the cells follows the refusal.
	await get_tree().create_timer(0.3).timeout
	var stayed := int(field.call("units_within_world", spot, Constants.BAG_RADIUS)) == units
	field.disconnect("bag_refused", heard)
	# Pick up the gas can by the mower and fill it up.
	await _stand_world(mower.global_position + Vector3(0.0, 0.1, 1.2))
	await get_tree().create_timer(0.6).timeout
	can.call("request_grab")
	waited = 0.0
	while waited < CLIENT_ANSWER_SECONDS and int(can.get("held_by")) != Net.local_peer_id():
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	var holding := int(can.get("held_by")) == Net.local_peer_id()
	var target: Variant = can.call("refuel_target")
	can.call("request_refuel")
	waited = 0.0
	while waited < CLIENT_ANSWER_SECONDS and float(mower.get("fuel")) < 100.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	var full := is_equal_approx(float(mower.get("fuel")), 100.0)
	can.call("request_drop")
	waited = 0.0
	while waited < CLIENT_ANSWER_SECONDS and int(can.get("held_by")) != 0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	var dropped := int(can.get("held_by")) == 0
	_step("client_yard", reasons.size() == 1 and reasons[0] == "no_bags" and stayed and holding and target == mower and full and dropped,
		"refused %s, %d units stay %s; held the can %s, it aims at the mower %s, tank full %s, put down %s" % [str(reasons), units, stayed, holding, target == mower, full, dropped])


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
	# The gas still in the job tools' tanks and the can is saved as the crew's
	# (Shops.supplies_to_save): the yard is still loaded, so there is some.
	var out_there := _ToolTiers.gas_out(get_tree().get_nodes_in_group("job_tools"))
	var expected: Dictionary = shops.call("supplies_to_save")
	var supplies_same := true
	for id: String in _Shops.SUPPLY_IDS:
		supplies_same = supplies_same and absf(float((copy.get("supplies") as Dictionary).get(id, -1.0)) - float(expected.get(id, -2.0))) < 0.01
	var gas_kept := out_there > 0.0 and absf(float((copy.get("supplies") as Dictionary).get("gas", 0.0)) - float(shops.call("supply", "gas")) - out_there) < 0.01
	var same := supplies_same and gas_kept \
		and JSON.stringify(copy.get("stock"), "", true) == JSON.stringify(shops.get("stock"), "", true) \
		and JSON.stringify(copy.get("looks"), "", true) == JSON.stringify(shops.get("looks"), "", true) \
		and int(copy.get("stock_day")) == int(shops.get("stock_day"))
	copy.free()
	var keys := true
	for field: String in ["version", "stock_day", "stock", "supplies", "orders", "looks", "truck", "crew_owned", "rusty_mood", "used_today", "junk_left", "vending_eaten"]:
		keys = keys and section.has(field)
	var saved_look: Variant = (section.get("looks", {}) as Dictionary).get(key, {})
	var hat := str((saved_look as Dictionary).get("hat", "")) if typeof(saved_look) == TYPE_DICTIONARY else ""
	print("[ShopTest]   every key %s, reads back the same %s (supplies %s, the %.2f gal out on the job saved %s), hat %s, Mk II saved %s" % [keys, same, supplies_same, out_there, gas_kept, hat, unlocks.has("leaf_blower_mk2")])
	return keys and same and hat == "hat_bucket" and unlocks.has("leaf_blower_mk2")


## junk_left: the save keeps the junk nobody sold (shops chunk 5): the flamingo
## still in Chefty's bed ("bed": true) and the haggled grill on the lot (with its
## haggle). Loaded back (_respawn_junk_left, as Shops does on a load), the
## flamingo is in the bed again and the grill lies on the first spot of the
## "junk_drop" grid, its haggle kept.
func _check_junk_left(shops: Node) -> void:
	var file := FileAccess.open(str(Campaign.call("_save_path")), FileAccess.READ)
	var data: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if file != null:
		file.close()
	var saved: Array = ((data as Dictionary).get("shops", {}) as Dictionary).get("junk_left", []) if typeof(data) == TYPE_DICTIONARY else []
	var in_bed := saved.filter(func(entry: Dictionary) -> bool: return bool(entry.get("bed", false)) and str(entry.get("type", "")) == "flamingo")
	var on_lot := saved.filter(func(entry: Dictionary) -> bool: return not bool(entry.get("bed", false)) and str(entry.get("type", "")) == "grill")
	var factor := float((on_lot[0] as Dictionary).get("haggle", 1.0)) if not on_lot.is_empty() else -1.0
	# Load it back: the bed emptied and the lot's junk gone first, as a fresh session has them.
	var chefty := get_tree().get_first_node_in_group("chefty")
	var junk_bed := chefty.get_node_or_null("Body/JunkBed")
	junk_bed.set("junk", [])
	junk_bed.call("_send")
	for node: Node in get_tree().get_nodes_in_group("junk"):
		if not node.is_in_group("job_tools"):
			node.queue_free()
	await _ticks(2)
	shops.set("junk_left", saved.duplicate(true))
	shops.call("_respawn_junk_left")
	await get_tree().create_timer(0.8).timeout
	var world := get_tree().get_first_node_in_group("world")
	var spot := (world.get_node("StoreZone") as Node3D).to_global(_Shops.junk_drop_spot(0))
	var grill := _nearest_junk(spot, 0.8)
	var grill_kept := grill != null and str(grill.get("label")) == "grill" and is_equal_approx(float(shops.call("haggle_of", grill)), factor)
	var bed_back := int(chefty.call("junk_count")) == in_bed.size() and junk_bed.get_child_count() == in_bed.size()
	_step("junk_left", in_bed.size() == 1 and on_lot.size() == 1 and not is_equal_approx(factor, 1.0) and grill_kept and bed_back,
		"saved %s; back: Chefty's bed %d, the grill at the junk_drop grid %s (x%.2f)" % [str(saved), int(chefty.call("junk_count")), grill_kept, factor])


## Yard junk (shops chunk 5): this yard has as many pieces as its hood's
## Constants.JUNK_PER_HOOD roll from the offer's seed says, each a real junk
## type lying on the front lawn band, clear of each other.
func _check_yard_junk() -> void:
	var world := get_tree().get_first_node_in_group("world")
	var slot := world.get_node_or_null("%LotSlot") if world != null else null
	var lot := slot.get_child(slot.get_child_count() - 1) as Node3D if slot != null and slot.get_child_count() > 0 else null
	if lot == null or not lot.has_meta("offer"):
		_step("yard_junk", false, "no job lot")
		return
	var offer: Dictionary = lot.get_meta("offer")
	var range_of: Vector2i = Constants.JUNK_PER_HOOD.get(str(lot.get("hood")), Constants.JUNK_PER_HOOD[""])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(offer.get("seed", 0)), "junk"])
	var want := rng.randi_range(range_of.x, range_of.y)
	var pieces: Array[Node3D] = []
	for node: Node in get_tree().get_nodes_in_group("junk"):
		if node.is_in_group("job_tools"):
			pieces.append(node as Node3D)
	var placed_ok := true
	for index: int in pieces.size():
		var local := pieces[index].global_position - lot.global_position
		placed_ok = placed_ok and Constants.JUNK_TYPES.has(str(pieces[index].get("label"))) \
			and absf(local.x) <= Constants.JUNK_LAWN_ACROSS.y + 1.0 and local.z >= Constants.JUNK_LAWN_ALONG.x - 1.0 and local.z <= Constants.JUNK_LAWN_ALONG.y + 1.0
	# And a Dandelion Acres yard (the most junk) from a fixed seed, laid out the same way.
	var hood_was: Variant = lot.get("hood")
	lot.set("hood", "dandelion_acres")
	var acres_range: Vector2i = Constants.JUNK_PER_HOOD["dandelion_acres"]
	rng.seed = hash([YARD_JUNK_SEED, "junk"])
	var acres_want := rng.randi_range(acres_range.x, acres_range.y)
	var before: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group("junk"):
		before[node] = true
	world.call("_spawn_junk", lot, {"seed": YARD_JUNK_SEED})
	lot.set("hood", hood_was)
	var acres: Array[Node3D] = []
	for node: Node in get_tree().get_nodes_in_group("junk"):
		if not before.has(node):
			acres.append(node as Node3D)
	var apart := true
	for index: int in acres.size():
		var local := acres[index].global_position - lot.global_position
		placed_ok = placed_ok and absf(local.x) >= Constants.JUNK_LAWN_ACROSS.x - 0.01 and absf(local.x) <= Constants.JUNK_LAWN_ACROSS.y + 0.01 \
			and local.z >= Constants.JUNK_LAWN_ALONG.x - 0.01 and local.z <= Constants.JUNK_LAWN_ALONG.y + 0.01 and acres[index].is_in_group("job_tools")
		for other: int in index:
			var gap := acres[index].global_position - acres[other].global_position
			apart = apart and Vector2(gap.x, gap.z).length() >= Constants.JUNK_SPACING - 0.01
	for node: Node3D in acres:
		node.queue_free()
	_step("yard_junk", pieces.size() == want and acres.size() == acres_want and acres_want >= acres_range.x and placed_ok and apart,
		"this yard (hood %s): %d pieces (the seed says %d, range %s); Dandelion Acres seed %d: %d (want %d, range %s), on the lawn band %s, apart %s" % [str(hood_was), pieces.size(), want, str(range_of), YARD_JUNK_SEED, acres.size(), acres_want, str(acres_range), placed_ok, apart])


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
	return _player_node(Net.local_peer_id())


func _player_node(peer_id: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node as Node3D
	return null


# ---------------------------------------------------------------- Rusty's (shops chunk 5)

## Rusty's, at noon: his day (rusty_day), a toilet landing in Chefty's bed and
## hopping back out at the tailgate (junk_bed), onto his scale and sold (sell),
## a flamingo haggled over (haggle), and the client selling a boombox and buying
## a used tool off his rack through the RPCs (used_buy).
func _check_rustys(shops: Node, me: int, mate: int) -> void:
	var clock := get_tree().get_first_node_in_group("day_clock")
	if _Shops._fishing("rustys", int(clock.get("day"))):
		clock.call("force_sleep")
		await get_tree().create_timer(0.6).timeout
		clock.call("set_hour_for_tests", 12.0)
		await get_tree().create_timer(0.2).timeout
	var world := get_tree().get_first_node_in_group("world")
	var chefty := get_tree().get_first_node_in_group("chefty")
	# rusty_day: his mood in range, today's rack, open, and the gate stands open.
	var mood := float(shops.get("rusty_mood"))
	var rack: Array = (shops.get("used_today") as Array).duplicate()
	var gate := world.get_node_or_null("StoreZone/ShopSite_rustys/RustysGate")
	await get_tree().create_timer(Constants.RUSTY_GATE_SWING_SECONDS + 0.6).timeout
	var day_ok := mood >= Constants.RUSTY_MOOD.x and mood <= Constants.RUSTY_MOOD.y and rack.size() >= Constants.USED_TOOLS_PER_DAY.x \
		and rack.size() <= Constants.USED_TOOLS_PER_DAY.y and bool(shops.call("is_open", "rustys")) and bool(shops.call("is_unlocked", "rustys")) \
		and gate != null and float(gate.call("shut_amount")) < 0.05
	_step("rusty_day", day_ok, "mood %.2f, rack %s, open %s, gate shut %.2f" % [mood, str(rack), shops.call("is_open", "rustys"), float(gate.call("shut_amount")) if gate != null else -1.0])

	# junk_bed: dropped into Chefty's bed it lands, settles and is loaded where it
	# lies (the prop goes, its model stays); unloaded, it hops out over the tailgate.
	var bed: Transform3D = chefty.call("bed_transform")
	var toilet := world.call("spawn_junk", "toilet", bed * Vector3(0.3, 1.6, 0.9), 30) as Node3D
	var toilet_name := str(toilet.name) if toilet != null else ""
	await _wait_until(func() -> bool: return int(chefty.call("junk_count")) == 1, JUNK_SETTLE_SECONDS)
	await _ticks(2)
	var junk_bed := chefty.get_node_or_null("Body/JunkBed")
	var loaded := int(chefty.call("junk_count")) == 1 and not is_instance_valid(toilet) and junk_bed != null and junk_bed.get_child_count() == 1
	var drawn_at := (junk_bed.get_child(0) as Node3D).global_position if loaded else Vector3.INF
	# Where it should land: straight back past the tailgate (and over to the side
	# away from anyone standing there, junk_bed.gd _landing_side), from where it lay.
	var lay: Transform3D = ((junk_bed.get("junk") as Array)[0] as Dictionary)["at"] if loaded else Transform3D.IDENTITY
	var side := float(junk_bed.call("_landing_side")) if junk_bed != null else 0.0
	var landing := bed * Vector3(lay.origin.x * (1.0 + Constants.JUNK_UNLOAD_SPREAD) + side, 0.0, Constants.JUNK_UNLOAD_LAND_Z + (_JunkBed.TAILGATE_Z - lay.origin.z) * Constants.JUNK_UNLOAD_FRONT_SHARE)
	chefty.call("unload_junk")
	# (Lambdas capture by value: the found prop goes in an array.)
	var found: Array = [null]
	await _wait_until(func() -> bool:
		found[0] = _nearest_junk(landing, JUNK_LAND_TOLERANCE * 2.0)
		return int(chefty.call("junk_count")) == 0 and found[0] != null and (found[0] as RigidBody3D).linear_velocity.length() < 0.3, JUNK_SETTLE_SECONDS)
	var out_prop := found[0] as Node3D
	var land_off := Vector2(out_prop.global_position.x - landing.x, out_prop.global_position.z - landing.z).length() if out_prop != null else INF
	var landed := out_prop != null and out_prop.global_position.y < bed.origin.y + 0.5 and land_off <= JUNK_LAND_TOLERANCE and int(chefty.call("junk_count")) == 0 and junk_bed.get_child_count() == 0
	_step("junk_bed", toilet_name != "" and loaded and landed,
		"loaded %s (drawn at %s), unloaded and landed %s at %s, %.2f m from where it should (side %.1f)" % [loaded, str(drawn_at), landed, str(out_prop.global_position) if out_prop != null else "-", land_off, side])

	# sell: on the scale the needle reads its weight and Rusty offers its value
	# times his mood; Take it pays exactly that and the toilet goes.
	await _stand_at("rustys")
	var middle: Vector3 = shops.call("scale_point")
	var dial := world.get_node_or_null("StoreZone/ShopSite_rustys/ScaleDial")
	var sold_ok := false
	var detail := "no toilet came out"
	if out_prop != null:
		_put(out_prop, middle + Vector3(0.0, 0.15, 0.0))
		await get_tree().create_timer(1.6).timeout
		var on := bool(shops.call("on_scale", out_prop))
		var offer := int(shops.call("appraise", out_prop))
		var weighed := float(dial.get("kg")) if dial != null else -1.0
		var needle := float(dial.call("needle_angle")) if dial != null else -9.0
		var want_needle := lerpf(-_ShopModels.DIAL_SWEEP, _ShopModels.DIAL_SWEEP, 28.0 / Constants.RUSTY_SCALE_FULL_KG)
		var cash := Campaign.credits(me)
		var code := str(shops.call("request_sell", out_prop.get_path(), false))
		await _ticks(2)
		sold_ok = on and offer == roundi(30.0 * mood) and is_equal_approx(weighed, 28.0) and absf(needle - want_needle) < 0.12 \
			and code == "sold" and Campaign.credits(me) - cash == offer and not is_instance_valid(out_prop)
		detail = "on the scale %s, %.1f kg, needle %.2f (want %.2f), offer $%d (want $%d), %s, paid $%d" % [on, weighed, needle, want_needle, offer, roundi(30.0 * mood), code, Campaign.credits(me) - cash]
	_step("sell", sold_ok, detail)

	# scale_edge: junk on the gravel beside the platform isn't on the scale (the
	# platform is 1.24 m square); on the platform's edge it is.
	# (Along z: the dial's post stands on its east side.)
	var tire_edge := world.call("spawn_junk", "tire", middle + Vector3(0.0, 0.03, 1.1), 9) as Node3D
	await get_tree().create_timer(0.8).timeout
	var beside := bool(shops.call("on_scale", tire_edge))
	_put(tire_edge, middle + Vector3(0.0, Constants.JUNK_SCALE_TOP + 0.02, 0.5))
	await get_tree().create_timer(0.8).timeout
	var on_edge := bool(shops.call("on_scale", tire_edge))
	tire_edge.queue_free()
	await _ticks(2)
	_step("scale_edge", not beside and on_edge, "1.05 m out on the gravel: on the scale %s; on the platform's edge: %s" % [beside, on_edge])

	# haggle: once a piece; it moves the offer up 30% or down 25% for good, and
	# the sale pays the new price. Junk off the scale isn't bought.
	var bird := world.call("spawn_junk", "flamingo", middle + Vector3(0.0, 0.1, 0.0), 8) as Node3D
	await get_tree().create_timer(1.0).timeout
	var haggle := str(shops.call("request_sell", bird.get_path(), true))
	var factor := float((shops.get("haggled") as Dictionary).get(str(bird.name), 1.0))
	var offer_after := int(shops.call("appraise", bird))
	var again := str(shops.call("request_sell", bird.get_path(), true))
	var cash_before := Campaign.credits(me)
	var sold := str(shops.call("request_sell", bird.get_path(), false))
	var tire := world.call("spawn_junk", "tire", middle + Vector3(-4.0, 0.05, 0.0), 9) as Node3D
	await get_tree().create_timer(0.5).timeout
	var off := str(shops.call("request_sell", tire.get_path(), false))
	tire.queue_free()
	var right_factor := (haggle == "haggle_won" and is_equal_approx(factor, 1.0 + Constants.HAGGLE_WIN)) or (haggle == "haggle_lost" and is_equal_approx(factor, 1.0 - Constants.HAGGLE_LOSE))
	_step("haggle", right_factor and offer_after == maxi(roundi(8.0 * mood * factor), 1) and again == "haggled" and sold == "sold" \
		and Campaign.credits(me) - cash_before == offer_after and off == "off_scale",
		"%s (x%.2f, offer $%d), again %s, sold %s for $%d, a tire off the scale %s" % [haggle, factor, offer_after, again, sold, Campaign.credits(me) - cash_before, off])

	# haggle_sticks: a haggle's result stays with its piece for good: through
	# Chefty's bed (in as one prop, out as another) and the morning's restock.
	var grill := world.call("spawn_junk", "grill", middle + Vector3(0.0, 0.1, 0.0), 30) as Node3D
	await get_tree().create_timer(1.0).timeout
	var grill_haggle := str(shops.call("request_sell", grill.get_path(), true))
	var grill_factor := float(shops.call("haggle_of", grill))
	var taken := bool(chefty.call("accept_junk", grill))
	var bed_factor := float(((junk_bed.get("junk") as Array).back() as Dictionary).get("haggle", 1.0)) if taken else -1.0
	shops.call("_forget_gone_haggles")
	await _ticks(2)
	chefty.call("unload_junk")
	await _wait_until(func() -> bool: return int(chefty.call("junk_count")) == 0, JUNK_SETTLE_SECONDS)
	await get_tree().create_timer(0.3).timeout
	var grill_back: Node3D = null
	for node: Node in get_tree().get_nodes_in_group("junk"):
		if str(node.get("label")) == "grill" and not node.is_queued_for_deletion():
			grill_back = node as Node3D
	var kept := grill_back != null and is_equal_approx(float(shops.call("haggle_of", grill_back)), grill_factor) and bool(shops.call("was_haggled", grill_back))
	_step("haggle_sticks", grill_haggle.begins_with("haggle_") and taken and is_equal_approx(bed_factor, grill_factor) and kept,
		"%s (x%.2f), in the bed x%.2f, back out as %s x%.2f" % [grill_haggle, grill_factor, bed_factor, str(grill_back.name) if grill_back != null else "-", float(shops.call("haggle_of", grill_back)) if grill_back != null else -1.0])
	# The grill waits on Rusty's gravel (Chefty is parked at the yard in this
	# test), unsold, for the save (junk_left).
	if grill_back != null:
		_put(grill_back, middle + Vector3(-3.0, 0.05, 0.0))

	# heave: E by Chefty with junk in your arms heaves it into the bed (player.gd
	# _load_truck), where it lands and is loaded.
	var me_body := _me() as CharacterBody3D
	var heave_ok := false
	var heave_detail := "no player"
	if me_body != null:
		# Chefty waits at the yard in this test: over there, by its tailgate.
		Net.move_player_to_zone(me, Net.Zone.LOT)
		await _wait_until(func() -> bool: return Net.player_zone(me) == Net.Zone.LOT, WAIT_SECONDS)
		await get_tree().create_timer(0.5).timeout
		var behind := bed * Vector3(0.0, 0.0, _JunkBed.TAILGATE_Z + 1.2)
		me_body.global_position = Vector3(behind.x, bed.origin.y + 0.1, behind.z)
		me_body.velocity = Vector3.ZERO
		await _ticks(3)
		var flamingo := world.call("spawn_junk", "flamingo", me_body.global_position + Vector3(0.0, 0.05, 0.0) - me_body.global_basis.z * 0.6, 6) as Node3D
		await _ticks(3)
		flamingo.call("_handle_grab", me)
		await _ticks(3)
		var held := int(flamingo.get("held_by")) == me
		var in_hands := me_body.call("_held_prop") as Node
		print("[ShopTest]   heave: in hands %s (%s), near the truck %s, me at %s, the bed at %s" % [str(in_hands.name) if in_hands != null else "-", str(in_hands.get("kind")) if in_hands != null else "-", flamingo.call("near_truck"), str(me_body.global_position), str(bed.origin)])
		var heaved := bool(me_body.call("_load_truck"))
		await _ticks(4)
		# It leaves their hands inside their reach: it must not bean them.
		var stunned := float(me_body.get("_stun_left")) > 0.0
		await _wait_until(func() -> bool: return int(chefty.call("junk_count")) == 1, JUNK_SETTLE_SECONDS)
		heave_ok = held and heaved and int(chefty.call("junk_count")) == 1 and not stunned
		heave_detail = "held %s, heaved %s, in the bed %d, the heaver stunned %s" % [held, heaved, int(chefty.call("junk_count")), stunned]
	_step("heave", heave_ok, heave_detail)
	Net.move_player_to_zone(me, Net.Zone.STORE)
	await _wait_until(func() -> bool: return Net.player_zone(me) == Net.Zone.STORE, WAIT_SECONDS)
	await get_tree().create_timer(0.5).timeout
	await _stand_at("rustys")

	# welcome: the day the crew's rank opens Rusty's, he texts, once.
	var town := get_tree().get_first_node_in_group("town")
	var before_texts := (town.get("texts") as Array).size() if town != null else -1
	shops.set("_salvage_open", false)
	shops.call("_check_salvage_opened")
	shops.call("_check_salvage_opened")
	var new_texts: Array = (town.get("texts") as Array).slice(before_texts) if town != null else []
	var from_rusty := new_texts.filter(func(text: Dictionary) -> bool: return str(text.get("text", "")) == str(_Strings.SHOP_UI["text_rusty_welcome"]))
	_step("welcome", from_rusty.size() == 1, "%d new texts, %d from Rusty" % [new_texts.size(), from_rusty.size()])

	# used_buy: the host owns every tool (--all-tools), so Rusty's used one is
	# "owned"; the client, with no tools, sells a boombox off the scale and buys
	# it off his rack through the RPCs; that pallet empties and the rest of the
	# day's tools stay on their own pallets (here and there). The client also
	# checks its copy of Chefty's bed (the flamingo heaved in above).
	var used_item := Catalog.tool_item(str(rack[0]), Catalog.TIER_USED) if not rack.is_empty() else ""
	var mine := str(shops.call("request_buy", "rustys", used_item, 1)) if used_item != "" else "-"
	var box := world.call("spawn_junk", "boombox", middle + Vector3(0.0, 0.1, 0.0), 20) as Node3D
	await get_tree().create_timer(1.0).timeout
	var box_offer := int(shops.call("appraise", box))
	Campaign.pay(mate, Catalog.price(used_item) + 50)
	var mate_cash := Campaign.credits(mate)
	_rpc_client_rusty.rpc_id(mate, used_item, box.get_path(), int(chefty.call("junk_count")))
	# By path: a lambda can't hold on to a node that gets freed.
	var box_path := box.get_path()
	await _wait_until(func() -> bool: return Campaign.peer_has_unlock(mate, StringName(used_item)) and get_node_or_null(box_path) == null, WAIT_SECONDS)
	var bought := Campaign.peer_has_unlock(mate, StringName(used_item)) and not (shops.get("used_today") as Array).has(str(rack[0]))
	var net_cash := Campaign.credits(mate) - mate_cash
	var rack_stand := get_tree().get_first_node_in_group("rusty_rack")
	var sold_slot: Dictionary = rack_stand.call("slot_state", "used_slot_0") if rack_stand != null else {}
	# The next pallet still shows its own tool (it doesn't slide over to the empty one).
	var next_slot: Dictionary = rack_stand.call("slot_state", "used_slot_1") if rack_stand != null and rack.size() > 1 else {}
	var others_stay := rack.size() < 2 or str(next_slot.get("item", "")) == Catalog.tool_item(str(rack[1]), Catalog.TIER_USED)
	_step("used_buy", used_item != "" and mine == "owned" and bought and not is_instance_valid(box) and net_cash == box_offer - Catalog.price(used_item) \
		and Campaign.tool_tier(mate, str(rack[0])) == Catalog.TIER_USED and sold_slot.get("look", "") == "empty" and others_stay,
		"the host's %s: %s; the client bought it %s, net $%d (sold the boombox for $%d, paid $%d), its tier %d, its pallet %s, the next pallet %s (rack %s)" % [used_item, mine, bought, net_cash, box_offer, Catalog.price(used_item), Campaign.tool_tier(mate, str(rack[0])) if not rack.is_empty() else -2, sold_slot.get("look", "?"), next_slot.get("item", "-"), str(shops.get("used_today"))])


## The host's cue for the client's Rusty's half: sell what's on the scale, then
## buy this used tool off the rack.
@rpc("authority", "call_remote", "reliable")
func _rpc_client_rusty(item: String, junk_path: NodePath, bed_count: int) -> void:
	_rusty_cue = {"item": item, "junk": junk_path, "bed": bed_count}


## The client at Rusty's: walks up to his counter, sells the boombox on the scale
## (_rpc_request_sell answered "sold") and buys the used tool (_rpc_request_buy
## answered "ok"), through the real client path.
func _run_client_rusty(shops: Node, me: int) -> void:
	var waited := 0.0
	while _rusty_cue.is_empty() and waited < CLIENT_RUSTY_WAIT_SECONDS:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	if _rusty_cue.is_empty():
		_step("client_rusty", false, "the host never sent Rusty's cue")
		return
	await _stand_at("rustys")
	await get_tree().create_timer(0.6).timeout
	var junk := get_node_or_null(_rusty_cue["junk"] as NodePath)
	var offer := int(shops.call("appraise", junk)) if junk != null else -1
	var count := _results.size()
	var asked := str(shops.call("request_sell", _rusty_cue["junk"] as NodePath, false))
	await _await_results(count + 1)
	var sale: Array = _results[count] if _results.size() > count else []
	var item := str(_rusty_cue["item"])
	shops.call("request_buy", "rustys", item, 1)
	await _await_results(count + 2)
	var buy: Array = _results[count + 1] if _results.size() > count + 1 else []
	await _wait_until(func() -> bool: return Campaign.peer_has_unlock(me, StringName(item)), 3.0)
	# Chefty's bed here holds what the host's does (JunkBed._rpc_junk), drawn.
	var chefty := get_tree().get_first_node_in_group("chefty")
	var junk_bed := chefty.get_node_or_null("Body/JunkBed") if chefty != null else null
	var here := (junk_bed.get("junk") as Array).size() if junk_bed != null else -1
	var drawn := junk_bed.get_child_count() if junk_bed != null else -1
	var bed_same := here == int(_rusty_cue.get("bed", -2)) and drawn == here
	_step("client_rusty", asked == "" and sale == ["sold", "junk_boombox", offer] and buy == ["ok", item, Catalog.price(item)] and Campaign.peer_has_unlock(me, StringName(item)) and bed_same,
		"sold %s (offer $%d), bought %s, Chefty's bed here %d (%d drawn), the host's %d" % [str(sale), offer, str(buy), here, drawn, int(_rusty_cue.get("bed", -2))])


## The junk prop nearest a point, within reach, or null.
func _nearest_junk(at: Vector3, reach: float) -> Node3D:
	var best: Node3D = null
	for node: Node in get_tree().get_nodes_in_group("junk"):
		if node.is_queued_for_deletion():
			continue
		var distance := (node as Node3D).global_position.distance_to(at)
		if distance < reach:
			reach = distance
			best = node as Node3D
	return best


## Host: put a prop down here, still.
func _put(prop: Node3D, at: Vector3) -> void:
	prop.global_position = at
	if prop is RigidBody3D:
		(prop as RigidBody3D).linear_velocity = Vector3.ZERO
		(prop as RigidBody3D).angular_velocity = Vector3.ZERO


## Wait until check says so, or seconds pass.
func _wait_until(check: Callable, seconds: float) -> void:
	var waited := 0.0
	while waited < seconds and not bool(check.call()):
		await get_tree().create_timer(0.1).timeout
		waited += 0.1