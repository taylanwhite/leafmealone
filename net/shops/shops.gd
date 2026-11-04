extends Node

## Authority: host. Every shop in town (docs/GAME.md "Shops"; docs/DECISIONS.md
## 2026-11-01, "Shops are one host node over a data catalog"). World/Shops is
## made on every peer in world._ready, next to Hires, so RPC paths match.
##
## The host owns every buy, every stock count, the crew's supplies (bags, gas,
## seasonal sacks), the players' looks, Chefty's paint, and snack buffs.
## Clients only ask (request_*); the host checks the request (_check_buy), takes
## the cash through Campaign's wallet API, applies it, saves, and sends a full
## snapshot to everyone (_rpc_state, call_local; the dictionaries are small and
## changes are rare) plus a result to the one who asked (_rpc_result).
##
## What the catalog sells is data in core/catalog.gd; every number is in
## core/constants.gd under "# ---- shops". Where each shop stands is
## Constants.SHOP_SITES, and _near_site is the one place that reads it for a
## buy, so the drivable town only has to move the data.
##
## Snacks (shops chunk 6): a snack's buff carries a server-time expiry, Turbo
## chains into the crash, the Snak-o-Matic's eat and sandwich rolls are the
## host's, and each player's last snack (snacks) rides in the snapshot so every
## peer plays the hand-over and the eating (player/snack_eater.gd).
##
## Cosmetics (shops chunk 7): a bought hat or shirt is worn at once, the closet
## and the shop's Wear swap them (request_equip), and Chefty's paint and decal
## are the crew's (request_apply_truck). Every peer draws the looks and the truck
## from the snapshot: player.gd rebuilds a body on looks_changed, and
## net/components/chefty_paint.gd repaints Chefty on truck_changed once it stands
## still.
##
## Deliveries (shops chunk 8): from Mulch Mule II the phone's Orders app buys
## Homie Depot's tools and supplies from anywhere (request_order) for the price
## plus Constants.DELIVERY_FEE and DELIVERY_FEE_SHARE. An order is due
## DELIVERY_HOURS of clock later (placed after closing: 9 AM the next day); the
## host lands it in _process: a honk from the van at the dock behind the lobby
## wall, then the order comes out of the hatch in that wall into the back room
## (_rpc_delivered): supplies as crates on the pallet (arrived_today, drawn by
## levels/dressing/delivery_pallet.gd), tools as themselves, real kit props
## (net/kit/kit.gd) lobbed in front of the cage. Never an unlock. Then a text.
## Pay a crewmate (request_give) moves PAY_CREWMATE_STEPS dollars between
## wallets; every peer hears of it (_rpc_gave, the gave signal) and
## player/cash_toss.gd flies the bill from the payer's hand to the payee.

signal changed
## Every peer: an order just landed in the back room (_rpc_delivered). crates:
## the crate item ids lobbed onto the pallet, in order; tools: how many tools come
## over the wall after them. The pallet plays the honk and the tosses from it.
signal delivered(crates: Array, tools: int)
## Every peer: one player paid another (host_give, _rpc_gave).
signal gave(from_peer: int, to_peer: int, amount: int)
signal looks_changed(peer_id: int)
signal truck_changed
## Local: the host's answer to this peer's request ("ok", "closed", "far",
## "locked", "sold_out", "owned", "needs", "short", "eaten", "season",
## "unknown", and "give_invalid" for a refused Pay a crewmate, whose item is
## "give"; "worn" and "applied" for a hat or shirt put on and a paint or decal
## put on Chefty, "not_owned" when it isn't yours to put on;
## ui/strings.gd SHOP_UI shop_result_<code>). amount is the dollars
## taken. The one confirmed-purchase hook for sound and keeper chatter. A
## phone order answers "ordered" (amount: what it cost, fees and all), or
## "full" with DELIVERY_MAX_OPEN orders already on the way.
signal result(code: String, item_id: String, amount: int)

const _Strings = preload("res://ui/strings.gd")
const _Seasons = preload("res://core/seasons.gd")
const _ToolTiers = preload("res://core/tool_tiers.gd")
const _KitRules = preload("res://core/kit_rules.gd")
## The save section's own version, for migrations (Campaign.SAVE_VERSION stays 1).
const SECTION_VERSION: int = 1
## The crew's supplies. Gas is gallons (a float); the rest are counts.
const SUPPLY_IDS: Array[String] = ["lawn_bags", "big_bags", "gas", "fertilizer", "grass_seed", "rock_salt"]
## Chefty's factory paint: always owned, so the crew can always go back.
const DEFAULT_PAINT: String = "paint_classic"
## How often the host checks for buffs running out (a poll, not tuning).
const BUFF_CHECK_SECONDS: float = 1.0

## {shop: {item: left today}}, for the items Constants.SHOP_DAILY_STOCK lists.
var stock: Dictionary = {}
## The day the stock was put out.
var stock_day: int = 0
## {supply id: amount}, the crew's (SUPPLY_IDS).
var supplies: Dictionary = {}
## Deliveries on the way: [{item, qty, arrive_day, arrive_minutes, by}] (shops chunk 8).
var orders: Array = []
## Delivered today, for the crates on the back-room pallet.
var arrived_today: Array = []
## {campaign key: {hat, shirt}} (Campaign.key_of), so a look follows the player
## between sessions like their cash does.
var looks: Dictionary = {}
## Chefty's look: {paint, decal}. Crew-wide.
var truck: Dictionary = {"paint": DEFAULT_PAINT, "decal": ""}
## Truck paint and decals the crew owns.
var crew_owned: Array = []
## {peer id: {buff id: server time it runs out}} (Constants.BUFFS). Not saved;
## they clear at sleep anyway.
var buffs: Dictionary = {}
## Rusty's mood today, his haggle results, and the used tools on his rack (shops chunk 5).
var rusty_mood: float = 1.0
var haggled: Dictionary = {}
var used_today: Array = []
## Unsold junk left at the store, respawned on load (shops chunk 5).
var junk_left: Array = []
## How much money the Snak-o-Matic has eaten, all time.
var vending_eaten: int = 0
## What the Snak-o-Matic ate today, in order (item ids): each one hangs stuck on
## its coil till the morning restock, on every peer (props/vending_machine.gd).
## Replicated, not saved (a host who reloads finds the coils turned free).
var vending_stuck: Array = []
## This peer holds the real state: the host from its _ready, a client once its
## first snapshot lands. Before that a client's fields are defaults, and anything
## that watches them for changes (the vending machine) must wait.
var synced: bool = false
## Local, true only while a client's first snapshot hands out its signals.
var first_snapshot: bool = false
## The last snack each player ate: {peer id: {item, buff, at}} (at is the server
## time it was handed over; buff is what it gave, so a sandwich's roll shows).
## Every peer plays the eating from it (player/snack_eater.gd), so a bite needs
## no RPC of its own. Not saved; cleared at sleep with the buffs.
var snacks: Dictionary = {}

var _rng := RandomNumberGenerator.new()
var _buff_wait: float = 0.0
var _order_wait: float = 0.0
var _broadcast_queued: bool = false
## Host: whether Rusty's was open (feature:salvage) when last looked, so his
## welcome text goes out once, the day the crew's rank opens it.
var _salvage_open: bool = false


func _ready() -> void:
	add_to_group("shops")
	Net.player_joined.connect(_on_player_joined)
	Net.player_left.connect(_on_player_left)
	if not Net.is_host():
		if multiplayer.multiplayer_peer != null:
			_rpc_request_state.rpc_id(1)
		return
	_rng.randomize()
	var clock := _clock()
	if clock != null:
		clock.connect("day_started", _on_day_started)
	_read_section(Campaign.save_section("shops"))
	if _unlimited_supplies():
		supplies = _supplies_from(Constants.TEST_STARTER_SUPPLIES)
	# A save from an earlier day (or none): today's shelves are put out fresh.
	if stock_day != _today():
		_restock(_today())
	synced = true
	Campaign.add_save_hook(_save_section)
	# Rusty's (shops chunk 5): his text when his yard opens, and last session's
	# unsold junk back by the TruckPad once the world is up.
	_salvage_open = Campaign.is_feature_on("salvage")
	Campaign.rank_changed.connect(_check_salvage_opened)
	if not junk_left.is_empty():
		_respawn_junk_left.call_deferred()
	# Clients ask for the state from their own _ready (the world may not be on
	# them yet), and late joiners get it on Net.player_joined.
	changed.emit()


func _exit_tree() -> void:
	Campaign.remove_save_hook(_save_section)


func _process(delta: float) -> void:
	if not Net.is_host():
		return
	if not orders.is_empty():
		_order_wait += delta
		if _order_wait >= Constants.DELIVERY_CHECK_SECONDS:
			_order_wait = 0.0
			_land_due_orders()
	if buffs.is_empty():
		return
	_buff_wait += delta
	if _buff_wait < BUFF_CHECK_SECONDS:
		return
	_buff_wait = 0.0
	if _expire_buffs(Net.server_time()):
		_broadcast()


# ---------------------------------------------------------------- reading (every peer)

## Whether the crew's rank has opened this shop (Catalog.shop_gate).
func is_unlocked(shop: String) -> bool:
	return Catalog.SHOPS.has(shop) and Campaign.has_unlock(Catalog.shop_gate(shop))


## Whether the shop is open right now, by the day clock.
func is_open(shop: String) -> bool:
	var clock := _clock()
	if clock == null:
		return Constants.SHOP_HOURS.has(shop)
	return open_at(shop, float(clock.call("hour")), int(clock.get("day")))


## Whether a shop is open at this clock hour (7 to 26) on this day: its
## Constants.SHOP_HOURS, and Rusty goes fishing every RUSTYS_CLOSED_EVERY days.
static func open_at(shop: String, hour: float, day: int) -> bool:
	if not Constants.SHOP_HOURS.has(shop):
		return false
	if _fishing(shop, day):
		return false
	var hours: Vector2 = Constants.SHOP_HOURS[shop]
	return hour >= hours.x and hour < hours.y


## When a closed shop opens next, for "Closed. Opens %s": "9 AM", or
## "tomorrow, 7 AM" once it has closed for the night (or Rusty is fishing), or
## "the day after tomorrow, 9 AM" on the evening before Rusty's fishing day.
func opens_text(shop: String) -> String:
	var clock := _clock()
	var hours: Vector2 = Constants.SHOP_HOURS.get(shop, Vector2.ZERO)
	var hour := float(clock.call("hour")) if clock != null else hours.x
	var day := int(clock.get("day")) if clock != null else 1
	return opens_text_at(shop, hour, day)


## opens_text for a clock hour on a day ("" for a shop that never opens).
static func opens_text_at(shop: String, hour: float, day: int) -> String:
	if not Constants.SHOP_HOURS.has(shop):
		return ""
	var hours: Vector2 = Constants.SHOP_HOURS[shop]
	var face := hour_text(hours.x)
	if hour < hours.x and not _fishing(shop, day):
		return face
	# The next day it isn't fishing; a week of fishing every day never opens.
	var next := day + 1
	while _fishing(shop, next):
		next += 1
		if next - day > maxi(Constants.RUSTYS_CLOSED_EVERY, 1):
			return ""
	if next == day + 1:
		return str(_Strings.SHOP_UI["shop_opens_tomorrow"]) % face
	return str(_Strings.SHOP_UI["shop_opens_day_after"]) % face


## "7 AM", "9 PM" for a clock hour (26 is 2 AM).
static func hour_text(hour: float) -> String:
	var hours := int(floor(hour)) % 24
	var face := hours % 12
	if face == 0:
		face = 12
	return str(_Strings.SHOP_UI["shop_hour_am" if hours < 12 else "shop_hour_pm"]) % face


## How much of an item the shop has left today, or -1 when it never runs out.
func stock_left(shop: String, item: String) -> int:
	var shelf: Dictionary = stock.get(shop, {})
	if not shelf.has(item):
		return -1
	return int(shelf[item])


## How much of a crew supply there is (SUPPLY_IDS): bags and sacks as counts, gas in gallons.
func supply(id: String) -> float:
	return float(supplies.get(id, 0))


## The product of this effect ("speed", "carry", "strain", "stroke") over a
## player's buffs that haven't run out. 1.0 with none. The same on every peer:
## expiries are server times.
func buff(peer_id: int, effect: String) -> float:
	var multiplier := 1.0
	var now := Net.server_time()
	var mine: Dictionary = buffs.get(peer_id, {})
	for buff_id: Variant in mine:
		if float(mine[buff_id]) > now:
			multiplier *= float((Constants.BUFFS.get(str(buff_id), {}) as Dictionary).get(effect, 1.0))
	return multiplier


func has_buff(peer_id: int, buff_id: String) -> bool:
	var mine: Dictionary = buffs.get(peer_id, {})
	return mine.has(buff_id) and float(mine[buff_id]) > Net.server_time()


## A player's buffs still running, as {buff id: seconds left}, soonest last.
func buffs_left(peer_id: int) -> Dictionary:
	var out := {}
	var now := Net.server_time()
	var mine: Dictionary = buffs.get(peer_id, {})
	for buff_id: Variant in mine:
		var left := float(mine[buff_id]) - now
		if left > 0.0:
			out[str(buff_id)] = left
	return out


## The last snack this player ate ({item, buff, at}), or {} for none today.
func snack_of(peer_id: int) -> Dictionary:
	return snacks.get(peer_id, {}) as Dictionary


## A player's hat and shirt item ids ("" for their own from dress_from_seed).
func look_of(peer_id: int) -> Dictionary:
	var look: Dictionary = looks.get(Campaign.key_of(peer_id), {})
	return {"hat": str(look.get("hat", "")), "shirt": str(look.get("shirt", ""))}


## Chefty's paint as a color, and its decal id ("" for none).
func truck_look() -> Dictionary:
	var paint := str(truck.get("paint", DEFAULT_PAINT))
	return {
		"color": Constants.CHEFTY_PAINTS.get(paint, Constants.CHEFTY_PAINTS[DEFAULT_PAINT]),
		"decal": str(truck.get("decal", "")),
	}


## How many dents Chefty has (what Marty's Body Shop charges for), 0 with no
## drivable Chefty. Every peer has it (chefty_drive.gd's crash and dent RPCs).
func chefty_dents() -> int:
	var chefty := get_tree().get_first_node_in_group("chefty") if is_inside_tree() else null
	return int(chefty.call("dents")) if chefty != null and chefty.has_method("dents") else 0


## Whether this player (or the crew, for truck paint) already owns an item.
func owns(peer_id: int, item: String) -> bool:
	var entry := Catalog.item(item)
	var kind := str(entry.get("kind", ""))
	if kind == "truck_cosmetic":
		return item == DEFAULT_PAINT or crew_owned.has(item)
	# Chefty's gear is the crew's, like its paint (driving chunk C3).
	if kind == "truck_gear":
		return crew_owned.has(item)
	# p2-kit: a tool is a thing you can always buy another of (the crew's kit,
	# net/kit/kit.gd), never "owned".
	if Catalog.is_kit(item):
		return false
	if Catalog.is_owned_kind(item):
		return Campaign.peer_has_unlock(peer_id, StringName(item))
	return false


# ---------------------------------------------------------------- requests (any peer)

## The local player buys qty of an item at a shop. On the host this is decided
## at once and the result code returned; on a client it returns "" and the
## answer comes back as the result signal.
func request_buy(shop: String, item: String, qty: int = 1) -> String:
	if Net.is_host():
		return host_buy(Net.local_peer_id(), shop, item, qty)
	_rpc_request_buy.rpc_id(1, shop, item, qty)
	return ""


## The local player puts on a hat or shirt they own (slot "hat" or "shirt"), or
## takes it off back to their own (item ""): the shop window's Wear and the
## phone's Closet (shops chunk 7). Anywhere, any time. The host answers "worn",
## "not_owned" or "unknown"; the result signal brings it on a client.
func request_equip(slot: String, item: String) -> String:
	if Net.is_host():
		return host_equip(Net.local_peer_id(), slot, item)
	_rpc_request_equip.rpc_id(1, slot, item)
	return ""


## The local player puts a paint or decal the crew owns on Chefty (item ""
## peels the decal off). Chefty takes it the next time it stands still
## (net/components/chefty_paint.gd). Answers "applied", "not_owned" or "unknown".
func request_apply_truck(item: String) -> String:
	if Net.is_host():
		return host_apply_truck(Net.local_peer_id(), item)
	_rpc_request_apply_truck.rpc_id(1, item)
	return ""


## The local player hands a crewmate cash (the phone's "Pay a crewmate";
## amount is one of Constants.PAY_CREWMATE_STEPS). Returns the code on the host.
func request_give(to_peer: int, amount: int) -> String:
	if Net.is_host():
		return host_give(Net.local_peer_id(), to_peer, amount)
	_rpc_request_give.rpc_id(1, to_peer, amount)
	return ""


## The local player orders qty of a Homie Depot tool or supply by phone (shops
## chunk 8). Returns the code on the host ("ordered" or a refusal); on a client
## "" and the answer comes as the result signal.
func request_order(item: String, qty: int = 1) -> String:
	if Net.is_host():
		return host_order(Net.local_peer_id(), item, qty)
	_rpc_request_order.rpc_id(1, item, qty)
	return ""


# ---------------------------------------------------------------- host

## Host: a player buys. Checks, charges, applies, saves, tells everyone, and
## answers the buyer. Returns the result code.
func host_buy(peer_id: int, shop: String, item: String, qty: int) -> String:
	if not Net.is_host():
		return ""
	var code := _check_buy(peer_id, shop, item, qty)
	var amount := 0
	if code == "":
		var price := Catalog.price(item) * qty
		if not Campaign.charge(peer_id, price):
			code = "short"
		else:
			amount = price
			code = _apply(peer_id, shop, item, qty)
			# Money the machine ate dispensed nothing, so the shelf keeps it.
			if code == "ok":
				_take_stock(shop, item, qty)
			Campaign.save_now()
			_broadcast()
	_send_result(peer_id, code, item, amount)
	return code


## Host: a player puts on (or takes off) a hat or shirt. Returns the result code.
func host_equip(peer_id: int, slot: String, item: String) -> String:
	if not Net.is_host():
		return ""
	var code := "worn"
	var entry := Catalog.item(item)
	if slot != "hat" and slot != "shirt":
		code = "unknown"
	elif item != "" and (str(entry.get("kind", "")) != "cosmetic" or str(entry.get("slot", "")) != slot):
		code = "unknown"
	elif item != "" and not owns(peer_id, item):
		code = "not_owned"
	elif str(look_of(peer_id).get(slot, "")) != item:
		_wear(peer_id, slot, item)
		Campaign.save_now()
		_broadcast()
	_send_result(peer_id, code, item, 0)
	return code


## Host: Chefty gets a paint or decal the crew owns ("" peels the decal off).
func host_apply_truck(peer_id: int, item: String) -> String:
	if not Net.is_host():
		return ""
	var code := "applied"
	var entry := Catalog.item(item)
	var slot := str(entry.get("slot", "decal" if item == "" else ""))
	if item != "" and str(entry.get("kind", "")) != "truck_cosmetic":
		code = "unknown"
	elif item != "" and not owns(peer_id, item):
		code = "not_owned"
	elif str(truck.get(slot, "")) != item:
		truck[slot] = item
		truck_changed.emit()
		Campaign.save_now()
		_broadcast()
	_send_result(peer_id, code, item, 0)
	return code


## Host: one player pays another. Returns the result code.
func host_give(from_peer: int, to_peer: int, amount: int) -> String:
	if not Net.is_host():
		return ""
	var code := "ok"
	if from_peer == to_peer or not Net.peer_ids().has(to_peer) or not Constants.PAY_CREWMATE_STEPS.has(amount):
		code = "give_invalid"
	elif not Campaign.charge(from_peer, amount):
		code = "short"
	else:
		Campaign.pay(to_peer, amount)
		Campaign.save_now()
	_send_result(from_peer, code, "give", amount if code == "ok" else 0)
	if code == "ok":
		# Everyone sees the bill change hands (player/cash_toss.gd).
		if multiplayer.multiplayer_peer == null:
			_rpc_gave(from_peer, to_peer, amount)
		else:
			_rpc_gave.rpc(from_peer, to_peer, amount)
	return code


# ---------------------------------------------------------------- deliveries (shops chunk 8)

## Whether the phone sells this: Homie Depot's tools (each a thing for the
## crew's kit) and its supplies. Never an upgrade, a look or anything owned.
static func orderable(item: String) -> bool:
	var entry := Catalog.item(item)
	if str(entry.get("shop", "")) != "homie_depot" or Catalog.price(item) < 0:
		return false
	return Catalog.is_kit(item) or str(entry.get("kind", "")) == "consumable"


## What qty of an item costs delivered: the price, the flat fee, and the share.
static func order_price(item: String, qty: int = 1) -> int:
	var goods := Catalog.price(item) * maxi(qty, 1)
	return goods + Constants.DELIVERY_FEE + roundi(float(goods) * Constants.DELIVERY_FEE_SHARE)


## When an order placed at this clock hour on this day lands: [day, clock
## minutes] (minutes from midnight, so 9 AM is 540). Homie Depot open: in
## DELIVERY_HOURS; closed: DELIVERY_AFTER_HOURS_ARRIVE, today if it hasn't
## opened yet, else tomorrow.
static func arrival_at(hour: float, day: int) -> Array:
	var hours: Vector2 = Constants.SHOP_HOURS["homie_depot"]
	var morning := Constants.DELIVERY_AFTER_HOURS_ARRIVE * 60.0
	if open_at("homie_depot", hour, day):
		# On the quarter hour, like the clock on the HUD says it.
		var due := (hour + Constants.DELIVERY_HOURS) * 60.0
		return [day, ceilf(due / Constants.DELIVERY_ROUND_MINUTES - 0.001) * Constants.DELIVERY_ROUND_MINUTES]
	if hour < hours.x:
		return [day, morning]
	return [day + 1, morning]


## Whether an order is due at this clock hour on this day.
static func order_due(order: Dictionary, hour: float, day: int) -> bool:
	var arrive_day := int(order.get("arrive_day", 0))
	return day > arrive_day or (day == arrive_day and hour * 60.0 >= float(order.get("arrive_minutes", 0.0)) - 0.001)


## "2:30 PM", or "tomorrow, 9 AM", for an order's arrival as seen on `today`.
static func arrival_text(order: Dictionary, today: int) -> String:
	var minutes := int(round(float(order.get("arrive_minutes", 0.0))))
	var hours := (minutes / 60) % 24
	var face := hours % 12
	if face == 0:
		face = 12
	var mins := minutes % 60
	var text := str(_Strings.SHOP_UI["deliveries_time_am" if hours < 12 else "deliveries_time_pm"]) % [face, mins]
	if int(order.get("arrive_day", today)) > today:
		return str(_Strings.SHOP_UI["shop_opens_tomorrow"]) % text
	return text


## Why this player can't order this now ("" when they can, cash aside). The
## phone greys a row out with it; the host checks it again (host_order).
func order_blocker(peer_id: int, item: String, qty: int = 1) -> String:
	if not Campaign.is_feature_on("deliveries"):
		return "locked"
	if not orderable(item):
		return "unknown"
	if qty < 1 or qty > Constants.SHOP_MAX_QTY or (Catalog.is_kit(item) and qty != 1):
		return "unknown"
	var clock := _clock()
	if clock != null and not Catalog.is_in_season(item, int(clock.call("season"))):
		return "season"
	if not Campaign.is_for_sale(StringName(item)):
		return "locked"
	var left := stock_left("homie_depot", item)
	if left >= 0 and left < qty:
		return "sold_out"
	if orders.size() >= Constants.DELIVERY_MAX_OPEN:
		return "full"
	if peer_id > 0 and Campaign.credits(peer_id) < order_price(item, qty):
		return "short"
	return ""


## Host: a player orders by phone. Checks, charges, takes it off Homie Depot's
## shelf (it's the same stock), books the van, saves, tells everyone, answers.
func host_order(peer_id: int, item: String, qty: int) -> String:
	if not Net.is_host():
		return ""
	var code := order_blocker(-1, item, qty)
	var amount := 0
	if code == "":
		var price := order_price(item, qty)
		if not Campaign.charge(peer_id, price):
			code = "short"
		else:
			amount = price
			code = "ordered"
			_take_stock("homie_depot", item, qty)
			var clock := _clock()
			var hour := float(clock.call("hour")) if clock != null else float(Constants.SHOP_HOURS["homie_depot"].x)
			var due := arrival_at(hour, _today())
			orders.append({"item": item, "qty": qty, "arrive_day": int(due[0]), "arrive_minutes": float(due[1]), "by": Campaign.key_of(peer_id)})
			Campaign.save_now()
			_broadcast()
	_send_result(peer_id, code, item, amount)
	return code


## Host: every order that's due lands now, all in one drop.
func _land_due_orders() -> void:
	var clock := _clock()
	if clock == null:
		return
	var hour := float(clock.call("hour"))
	var day := int(clock.get("day"))
	var due: Array = []
	var waiting: Array = []
	for order: Variant in orders:
		if typeof(order) == TYPE_DICTIONARY and order_due(order, hour, day):
			due.append(order)
		elif typeof(order) == TYPE_DICTIONARY:
			waiting.append(order)
	if due.is_empty():
		return
	orders = waiting
	host_land(due)


## Host: these orders land in the back room. Supplies go into the crew's supply
## at once and onto the pallet as crates; tools come out of the hatch one by one
## as kit props, after the crates (the same schedule delivery_pallet.gd plays). A
## text says what came. Also dev: an order landed by hand.
func host_land(due: Array) -> void:
	if not Net.is_host() or due.is_empty():
		return
	var crates: Array = []
	var tools: Array = []
	var names: Array = []
	for order: Dictionary in due:
		var item := str(order.get("item", ""))
		var qty := maxi(int(order.get("qty", 1)), 1)
		var entry := Catalog.item(item)
		if entry.is_empty():
			continue
		if Catalog.is_kit(item):
			for _unit: int in qty:
				tools.append({"kind": str(entry["tool"]), "tier": int(entry["tier"])})
			names.append(_KitRules.sentence_name(str(entry["tool"]), int(entry["tier"])))
		else:
			var supply_id := str(entry.get("supply", ""))
			add_supply(supply_id, float(Constants.SUPPLY_PER_ITEM.get(item, 0)) * float(qty))
			for _unit: int in mini(qty, Constants.DELIVERY_CRATES_PER_ORDER):
				crates.append(item)
			var named := _Strings.shop_item_name(item)
			# Mid-sentence: "2 × gas can", like the kit's "rake".
			if named.length() > 1 and named.substr(1, 1) == named.substr(1, 1).to_lower():
				named = named.substr(0, 1).to_lower() + named.substr(1)
			names.append(str(_Strings.SHOP_UI["deliveries_qty"]) % [qty, named] if qty > 1 else named)
	# The crates the pallet has room for (the rest are "in the back").
	var room := maxi(Constants.DELIVERY_CRATES_MAX - arrived_today.size(), 0)
	var shown := crates.slice(0, room)
	arrived_today.append_array(crates)
	# The honk and the tosses first, then the snapshot: every peer hears of the
	# new crates before it sees them, so it lobs them in instead of popping them.
	if multiplayer.multiplayer_peer == null:
		_rpc_delivered(shown, tools.size())
	else:
		_rpc_delivered.rpc(shown, tools.size())
	# Each tool gets its own spot, worked out now: the one before it is still in the air when it goes.
	var first_spot := _delivery_kit_index()
	for index: int in tools.size():
		var tool: Dictionary = tools[index]
		var delay := Constants.DELIVERY_TOSS_DELAY + float(shown.size() + index) * Constants.DELIVERY_TOSS_GAP
		get_tree().create_timer(delay).timeout.connect(_toss_tool.bind(str(tool["kind"]), int(tool["tier"]), first_spot + index))
	var town := get_tree().get_first_node_in_group("town")
	if town != null and not names.is_empty():
		town.call("_text", str(_Strings.SHOP_UI["text_from_deliveries"]), "delivery", str(_Strings.SHOP_UI["text_delivery"]) % _KitRules.sentence_list(names), -1)
	Campaign.save_now()
	_broadcast()


## Host: one ordered tool comes out of the back room's hatch, lobbed high over
## the cage onto the next free spot in front of it: a real kit prop thrown on an
## arc (net/kit/kit.gd), turning a little as it flies.
func _toss_tool(kind: String, tier: int, spot: int) -> void:
	var kit := get_tree().get_first_node_in_group("kit") if is_inside_tree() else null
	if kit == null or not Net.is_host():
		return
	var land := delivery_kit_point(spot)
	var from := delivery_point(Constants.DELIVERY_HATCH + Vector3(Constants.DELIVERY_TOOL_START_OUT, 0.0, 0.0))
	var fuel := Constants.KIT_USED_FUEL if tier == Catalog.TIER_USED else Constants.KIT_NEW_FUEL
	# As it lies on the ground (a kit prop's rest pose), so it comes through the
	# hatch flat and lands flat.
	var prop := kit.call("spawn_item", kind, tier, fuel, Transform3D(Basis(), from)) as RigidBody3D
	if prop == null:
		return
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * prop.gravity_scale
	var seconds := Constants.DELIVERY_TOOL_FLIGHT
	prop.linear_velocity = (land - from) / seconds + Vector3.UP * 0.5 * gravity * seconds
	# A lazy turn about up as it flies; tumbling end over end, a rake could land
	# on its head and stand there.
	prop.angular_velocity = Vector3(0.0, Constants.DELIVERY_TOOL_SPIN, 0.0)
	# The order left the list when it landed: the tool is in the save from now on.
	Campaign.save_now()


## A point given from the back room's pallet (StoreZone's axes), in the world.
func delivery_point(offset: Vector3) -> Vector3:
	var site: Dictionary = Constants.SHOP_SITES.get("back_room", {})
	var zone := _site_zone(site)
	var local := (site.get("counter", Vector3.ZERO) as Vector3) + offset
	return zone.to_global(local) if zone != null else local


## The world point the index-th delivered tool lands on (DELIVERY_KIT_*).
func delivery_kit_point(index: int) -> Vector3:
	var site: Dictionary = Constants.SHOP_SITES.get("back_room", {})
	var zone := _site_zone(site)
	var local := (site.get("counter", Vector3.ZERO) as Vector3) + Constants.DELIVERY_KIT_FIRST + Constants.DELIVERY_KIT_STEP * float(clampi(index, 0, Constants.DELIVERY_KIT_MAX - 1))
	if index >= Constants.DELIVERY_KIT_MAX:
		local += Vector3.UP * Constants.DELIVERY_KIT_STACK_STEP * float(index - Constants.DELIVERY_KIT_MAX + 1)
	return zone.to_global(local) if zone != null else local


## The next free spot in front of the cage: one past the kit already lying there.
func _delivery_kit_index() -> int:
	var used := 0
	var first := delivery_kit_point(0)
	var last := delivery_kit_point(Constants.DELIVERY_KIT_MAX - 1)
	for node: Node in get_tree().get_nodes_in_group("props"):
		if not _KitRules.is_kit(node) or not bool(node.call("is_loose")) or node.is_queued_for_deletion():
			continue
		var at := (node as Node3D).global_position
		# Near the line of spots (a tool lies across it, long side along x).
		var along := Geometry3D.get_closest_point_to_segment(at, first, last)
		if Vector2(at.x - along.x, at.z - along.z).length() < 1.0:
			used += 1
	return used

# ---------------------------------------------------------------- Rusty's (shops chunk 5)

## Where Rusty's scale stands, in the world (its platform's middle, on the ground).
func scale_point() -> Vector3:
	var site: Dictionary = Constants.SHOP_SITES.get("rustys", {})
	var zone := _site_zone(site)
	if zone == null or not site.has("scale"):
		return Vector3.INF
	return zone.to_global(site["scale"] as Vector3)


## Whether a piece of junk lies on Rusty's scale: loose, its base over the
## platform (within JUNK_SCALE_HALF of the middle along both of the platform's
## sides) and resting on it (at least its top, not on the gravel beside it, and
## not flying over it). Every peer can tell from the replicated positions.
func on_scale(prop: Node) -> bool:
	var junk := prop as Node3D
	if junk == null or str(junk.get("kind")) != "junk" or junk.is_queued_for_deletion():
		return false
	if junk.has_method("is_loose") and not bool(junk.call("is_loose")):
		return false
	var middle := scale_point()
	if not middle.is_finite():
		return false
	# In the store's own space (the platform is square, so the dial's turn doesn't matter).
	var zone := _site_zone(Constants.SHOP_SITES["rustys"])
	var local := zone.global_basis.inverse() * (junk.global_position - middle)
	return absf(local.x) <= Constants.JUNK_SCALE_HALF and absf(local.z) <= Constants.JUNK_SCALE_HALF \
		and local.y >= Constants.JUNK_SCALE_TOP - Constants.JUNK_SCALE_TOP_SLACK and local.y <= Constants.JUNK_ON_SCALE_HEIGHT


## Every piece of junk on Rusty's scale, nearest the middle first.
func junk_on_scale() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if not is_inside_tree():
		return out
	for node: Node in get_tree().get_nodes_in_group("props"):
		if on_scale(node):
			out.append(node as Node3D)
	var middle := scale_point()
	out.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.global_position.distance_to(middle) < b.global_position.distance_to(middle))
	return out


## What Rusty offers for a piece of junk today: its base value times his mood,
## times what a haggle did to it.
func appraise(prop: Node) -> int:
	if prop == null or str(prop.get("kind")) != "junk":
		return 0
	return maxi(roundi(float(prop.get("value")) * rusty_mood * float(haggled.get(str(prop.name), 1.0))), 1)


## Whether this piece was haggled over already (one try each; the answer sticks).
func was_haggled(prop: Node) -> bool:
	return prop != null and haggled.has(str(prop.name))


## What a haggle did to this piece's price for good (1.0: never haggled over).
## It goes with the piece through Chefty's bed and the save (junk_bed.gd,
## junk_left), so neither a ride nor a night wipes it.
func haggle_of(prop: Node) -> float:
	return float(haggled.get(str(prop.name), 1.0)) if prop != null else 1.0


## Host: a piece of junk came back as a new prop (out of Chefty's bed, or from
## the save) carrying a haggle's result: it keeps it under its new name.
func host_keep_haggle(prop: Node, factor: float) -> void:
	if not Net.is_host() or prop == null or is_equal_approx(factor, 1.0):
		return
	haggled[str(prop.name)] = factor
	_broadcast()


## Host: a piece of junk is leaving the world as a prop (into Chefty's bed): its
## haggle goes with it, returned here (1.0 if none).
func host_take_haggle(prop: Node) -> float:
	if not Net.is_host() or prop == null or not haggled.has(str(prop.name)):
		return 1.0
	var factor := float(haggled[str(prop.name)])
	haggled.erase(str(prop.name))
	_broadcast()
	return factor


## The catalog-style id a piece of junk sells as ("junk_toilet"), the jackpot
## flamingo as "junk_flamingo_vintage": Strings.SHOP_UI names it.
static func junk_item(prop: Node) -> String:
	var type := str(prop.get("label"))
	if type == "flamingo" and int(prop.get("value")) >= int(Constants.JUNK_JACKPOT["value"]):
		return "junk_flamingo_vintage"
	return "junk_" + type


## The local player sells a piece of junk on Rusty's scale (haggle false), or
## haggles over it first (true: once per piece, it sticks). Returns the result
## code on the host; on a client "" and the answer comes as the result signal:
## "sold" (amount: what you got), "haggle_won" / "haggle_lost" (amount: the new
## offer), or a refusal ("closed", "far", "locked", "off_scale", "haggled", "unknown").
func request_sell(prop_path: NodePath, haggle: bool = false) -> String:
	if Net.is_host():
		return host_sell(Net.local_peer_id(), prop_path, haggle)
	_rpc_request_sell.rpc_id(1, prop_path, haggle)
	return ""


## Host: a player sells (or haggles over) a piece of junk on Rusty's scale.
func host_sell(peer_id: int, prop_path: NodePath, haggle: bool) -> String:
	if not Net.is_host():
		return ""
	var prop := get_node_or_null(prop_path)
	var item := junk_item(prop) if prop != null and str(prop.get("kind")) == "junk" else "junk"
	var code := ""
	var amount := 0
	if not is_unlocked("rustys"):
		code = "locked"
	elif not is_open("rustys"):
		code = "closed"
	elif not _near_site(peer_id, "rustys"):
		code = "far"
	elif prop == null or str(prop.get("kind")) != "junk" or prop.is_queued_for_deletion():
		code = "unknown"
	elif not on_scale(prop):
		code = "off_scale"
	elif haggle:
		if was_haggled(prop):
			code = "haggled"
		else:
			var won := _rng.randf() < Constants.HAGGLE_WIN_CHANCE
			haggled[str(prop.name)] = 1.0 + Constants.HAGGLE_WIN if won else 1.0 - Constants.HAGGLE_LOSE
			code = "haggle_won" if won else "haggle_lost"
			amount = appraise(prop)
			_broadcast()
	else:
		amount = appraise(prop)
		Campaign.pay(peer_id, amount)
		haggled.erase(str(prop.name))
		prop.queue_free()
		code = "sold"
		Campaign.save_now()
		_broadcast()
	_send_result(peer_id, code, item, amount)
	return code


## Host: the crew's rank just opened Rusty's: he texts (once; a save that has it
## open already never hears it again).
func _check_salvage_opened() -> void:
	if not Net.is_host():
		return
	var open := Campaign.is_feature_on("salvage")
	if open and not _salvage_open:
		var town := get_tree().get_first_node_in_group("town")
		if town != null:
			town.call("_text", str(_Strings.SHOP_UI["text_from_rusty"]), "rusty", str(_Strings.SHOP_UI["text_rusty_welcome"]), -1)
	_salvage_open = open


## Host, saving: the junk nobody sold ([{type, value, bed?, haggle?}]): what's
## in Chefty's bed ("bed": true), then what lies on the store's lot, at most
## Constants.JUNK_LEFT_MAX of those (the junk_drop grid's spots). A haggle's
## result rides along. The yards' own junk goes with the yard.
func _unsold_junk() -> Array:
	var out: Array = []
	if not is_inside_tree():
		return junk_left
	var chefty := get_tree().get_first_node_in_group("chefty")
	var bed := chefty.get_node_or_null("Body/JunkBed") if chefty != null else null
	if bed != null:
		for entry: Dictionary in bed.get("junk") as Array:
			var saved := {"type": str(entry["type"]), "value": int(entry["value"]), "bed": true}
			if not is_equal_approx(float(entry.get("haggle", 1.0)), 1.0):
				saved["haggle"] = float(entry["haggle"])
			out.append(saved)
	var on_lot := 0
	for node: Node in get_tree().get_nodes_in_group("junk"):
		if node.is_queued_for_deletion() or node.is_in_group("job_tools") or on_lot >= Constants.JUNK_LEFT_MAX:
			continue
		var at := (node as Node3D).global_position
		if Constants.STORE_AREA.has_point(Vector2(at.x, at.z)):
			var saved := {"type": str(node.get("label")), "value": int(node.get("value"))}
			if was_haggled(node):
				saved["haggle"] = haggle_of(node)
			out.append(saved)
			on_lot += 1
	return out


## Host, on load: last session's unsold junk back. What was in Chefty's bed goes
## back in it (junk_bed.gd restore); the rest lies in a grid in STORE_LAYOUT's
## "junk_drop" by the TruckPad, at most JUNK_LEFT_MAX pieces, haggles kept.
func _respawn_junk_left() -> void:
	var world := get_tree().get_first_node_in_group("world")
	var zone := world.get_node_or_null("StoreZone") as Node3D if world != null else null
	if zone == null or not world.has_method("spawn_junk"):
		return
	var chefty := get_tree().get_first_node_in_group("chefty")
	var bed := chefty.get_node_or_null("Body/JunkBed") if chefty != null else null
	var to_bed: Array = []
	var to_lot: Array = []
	for item: Variant in junk_left:
		if typeof(item) != TYPE_DICTIONARY or not Constants.JUNK_TYPES.has(str((item as Dictionary).get("type", ""))):
			continue
		var entry: Dictionary = item
		if bool(entry.get("bed", false)) and bed != null and to_bed.size() < Constants.TRUCK_JUNK_CAPACITY:
			to_bed.append(entry)
		else:
			to_lot.append(entry)
	if bed != null and not to_bed.is_empty():
		bed.call("restore", to_bed)
	for index: int in mini(to_lot.size(), Constants.JUNK_LEFT_MAX):
		var entry: Dictionary = to_lot[index]
		var spot := junk_drop_spot(index)
		var junk := world.call("spawn_junk", str(entry["type"]), zone.to_global(spot), int(entry.get("value", -1))) as Node
		host_keep_haggle(junk, float(entry.get("haggle", 1.0)))
	junk_left = []


## Where the index-th piece of last session's lot junk lies, in StoreZone space:
## a grid inside STORE_LAYOUT's "junk_drop" (Constants.JUNK_LEFT_*).
static func junk_drop_spot(index: int) -> Vector3:
	var column := index % Constants.JUNK_LEFT_COLUMNS
	var row := index / Constants.JUNK_LEFT_COLUMNS
	return Constants.JUNK_LEFT_FIRST + Vector3(float(column) * Constants.JUNK_LEFT_STEP.x, 0.0, float(row) * Constants.JUNK_LEFT_STEP.y)


## Host: take from a crew supply. False (and nothing taken) when there isn't enough.
func consume(id: String, amount: float) -> bool:
	if not Net.is_host() or not supplies.has(id) or amount < 0.0 or supply(id) < amount:
		return false
	_set_supply(id, supply(id) - amount)
	_queue_broadcast()
	return true


## Host: add to a crew supply.
func add_supply(id: String, amount: float) -> void:
	if not Net.is_host() or not SUPPLY_IDS.has(id) or amount <= 0.0:
		return
	_set_supply(id, supply(id) + amount)
	_queue_broadcast()


## Host, dev and tests: set a supply outright.
func dev_set_supply(id: String, amount: float) -> void:
	if not Net.is_host() or not SUPPLY_IDS.has(id):
		return
	_set_supply(id, maxf(amount, 0.0))
	_broadcast()


## Host: whether this player stands close enough to buy at this shop: in the
## store (or the connected town's streets), and within SHOP_REACH plus the lag
## slack of the shop's counter, or inside its area (its shelves or yard). Uses
## the host's copy of the player's position.
func _near_site(peer_id: int, shop: String) -> bool:
	var zone := Net.player_zone(peer_id)
	if zone != Net.Zone.STORE and zone != Net.Zone.TOWN:
		return false
	var site: Dictionary = Constants.SHOP_SITES.get(shop, {})
	var body := _player_body(peer_id)
	var zone_node := _site_zone(site)
	if site.is_empty() or body == null or zone_node == null:
		return false
	var local := zone_node.to_local(body.global_position)
	var spot := Vector2(local.x, local.z)
	var reach := Constants.SHOP_REACH + Constants.SHOP_REACH_SLACK
	if site.has("counter"):
		var counter: Vector3 = site["counter"]
		if spot.distance_to(Vector2(counter.x, counter.z)) <= reach:
			return true
	# More places you can buy at: Homie Depot's hat rack, shirt cubby and paint
	# counter (shops chunk 7).
	for at: Variant in site.get("spots", []):
		var point: Vector3 = at
		if spot.distance_to(Vector2(point.x, point.z)) <= reach:
			return true
	if site.has("area"):
		var area: Rect2 = site["area"]
		if area.grow(Constants.SHOP_REACH_SLACK).has_point(spot):
			return true
	# Homie Depot's walk-in lobby, where its tool endcaps stand (art chunk 8).
	if site.has("lobby"):
		var lobby: Rect2 = site["lobby"]
		if lobby.grow(Constants.SHOP_REACH_SLACK).has_point(spot):
			return true
	return false


## Host: why a buy can't happen, or "" when it can (the order is the
## validation order in gap-specs/shops.json; cash is checked last, by charge).
func _check_buy(peer_id: int, shop: String, item: String, qty: int) -> String:
	if not Catalog.SHOPS.has(shop):
		return "unknown"
	if not is_unlocked(shop):
		return "locked"
	if not is_open(shop):
		return "closed"
	if not _near_site(peer_id, shop):
		return "far"
	var entry := Catalog.item(item)
	if entry.is_empty() or str(entry.get("shop", "")) != shop or Catalog.price(item) < 0:
		return "unknown"
	var kind := str(entry.get("kind", ""))
	var only_one := Catalog.is_owned_kind(item) or kind == "snack" or Catalog.is_kit(item)
	if qty < 1 or qty > Constants.SHOP_MAX_QTY or (only_one and qty != 1):
		return "unknown"
	var clock := _clock()
	if clock != null and not Catalog.is_in_season(item, int(clock.call("season"))):
		return "season"
	var left := stock_left(shop, item)
	if left >= 0 and left < qty:
		return "sold_out"
	# Rusty's rack only has today's used tools, one of each.
	if kind == "used_tool" and not used_today.has(str(entry.get("tool", ""))):
		return "sold_out"
	if not Campaign.is_for_sale(StringName(item)):
		return "locked"
	if owns(peer_id, item):
		return "owned"
	# Marty's Body Shop fixes every dent at once, priced per dent (driving chunk C3).
	if kind == "service":
		var dents := chefty_dents()
		if dents <= 0:
			return "no_dents"
		if qty != dents:
			return "unknown"
	var needs: Array = entry.get("needs", [])
	if not Catalog.is_kit(item) and not needs.is_empty() and not needs.any(func(need: Variant) -> bool: return owns(peer_id, str(need))):
		return "needs"
	return ""


## Host: the buy is paid for; hand it over. Returns the result code.
func _apply(peer_id: int, shop: String, item: String, qty: int) -> String:
	var entry := Catalog.item(item)
	var kind := str(entry.get("kind", ""))
	# The Snak-o-Matic keeps the money now and then. That's the whole joke.
	if shop == "snak_o_matic" and _rng.randf() < Constants.VENDING_EAT_CHANCE:
		vending_eaten += 1
		vending_stuck.append(item)
		return "eaten"
	if Catalog.is_kit(item):
		# p2-kit: buying makes a thing (net/kit/kit.gd): in your hands, or by the
		# front door for the big ones. The crew's, whoever paid.
		var kit := get_tree().get_first_node_in_group("kit")
		if kit != null:
			kit.call("host_deliver", peer_id, str(entry["tool"]), int(entry["tier"]))
	match kind:
		"tool", "tier":
			pass
		"upgrade":
			Campaign.grant_unlock(peer_id, item)
		"used_tool":
			# Off its pallet: an empty spot ("") where it stood, so the rest of the
			# day's tools stay on their own pallets.
			var at := used_today.find(str(entry.get("tool", "")))
			if at >= 0:
				used_today[at] = ""
		"gear":
			# Yours: the skateboard rides home in your wallet, not as a job tool.
			Campaign.grant_unlock(peer_id, item)
		"cosmetic":
			Campaign.grant_unlock(peer_id, item)
			# Bought means worn: you walk out in the new hat.
			_wear(peer_id, str(entry.get("slot", "hat")), item)
		"truck_cosmetic":
			if not crew_owned.has(item):
				crew_owned.append(item)
			truck[str(entry.get("slot", "paint"))] = item
			truck_changed.emit()
		"truck_gear":
			if not crew_owned.has(item):
				crew_owned.append(item)
		"service":
			var chefty := get_tree().get_first_node_in_group("chefty")
			if chefty != null and chefty.has_method("host_repair"):
				chefty.call("host_repair")
		"consumable":
			var per := float(Constants.SUPPLY_PER_ITEM.get(item, 0))
			_set_supply(str(entry.get("supply", "")), supply(str(entry.get("supply", ""))) + per * float(qty))
		"snack":
			var given := _give_buff(peer_id, str(entry.get("buff", "")))
			snacks[peer_id] = {"item": item, "buff": given, "at": Net.server_time()}
	return "ok"


func _take_stock(shop: String, item: String, qty: int) -> void:
	var shelf: Dictionary = stock.get(shop, {})
	if shelf.has(item):
		shelf[item] = maxi(int(shelf[item]) - qty, 0)


func _wear(peer_id: int, slot: String, item: String) -> void:
	var key := Campaign.key_of(peer_id)
	var look: Dictionary = {"hat": "", "shirt": ""}
	look.merge(looks.get(key, {}) as Dictionary, true)
	look[slot] = item
	looks[key] = look
	looks_changed.emit(peer_id)


## Host: a snack's buff starts now ("sandwich" rolls full or queasy). Turbo
## replaces a crash still running. Returns the buff given ("" for none).
func _give_buff(peer_id: int, buff_id: String) -> String:
	if buff_id == "sandwich":
		buff_id = "queasy" if _rng.randf() < Constants.VENDING_QUEASY_CHANCE else "full"
	if not Constants.BUFFS.has(buff_id):
		return ""
	var mine: Dictionary = (buffs.get(peer_id, {}) as Dictionary).duplicate()
	var then := str((Constants.BUFFS[buff_id] as Dictionary).get("then", ""))
	mine.erase(then)
	mine[buff_id] = Net.server_time() + float((Constants.BUFFS[buff_id] as Dictionary)["seconds"])
	buffs[peer_id] = mine
	return buff_id


## Host, dev and tests: a player's buffs (and last snack) gone at once.
func dev_clear_buffs(peer_id: int) -> void:
	if not Net.is_host():
		return
	buffs.erase(peer_id)
	snacks.erase(peer_id)
	_broadcast()


## Host: drop buffs that ran out, starting the one each chains into (turbo,
## then the crash). True when anything changed.
func _expire_buffs(now: float) -> bool:
	var any := false
	for peer_id: Variant in buffs.keys():
		var mine: Dictionary = (buffs[peer_id] as Dictionary).duplicate()
		for buff_id: Variant in mine.keys():
			var ends := float(mine[buff_id])
			if ends > now:
				continue
			mine.erase(buff_id)
			any = true
			var then := str((Constants.BUFFS.get(str(buff_id), {}) as Dictionary).get("then", ""))
			if Constants.BUFFS.has(then):
				var then_ends := ends + float((Constants.BUFFS[then] as Dictionary)["seconds"])
				if then_ends > now:
					mine[then] = then_ends
		if mine.is_empty():
			buffs.erase(peer_id)
		else:
			buffs[peer_id] = mine
	return any


## Host: a new morning. Fresh shelves, buffs gone, and Marty finds a few bags
## for a crew that ran out, so nobody is ever stuck without one.
func _on_day_started(day: int) -> void:
	if not Net.is_host():
		return
	_restock(day)
	buffs.clear()
	snacks.clear()
	var bags := supply("lawn_bags") + supply("big_bags")
	if bags < float(Constants.EMERGENCY_BAGS):
		_set_supply("lawn_bags", supply("lawn_bags") + float(Constants.EMERGENCY_BAGS) - bags)
		var town := get_tree().get_first_node_in_group("town")
		if town != null:
			town.call("_text", str(_Strings.SHOP_UI["text_from_marty"]), "shop", str(_Strings.SHOP_UI["text_emergency_bags"]), -1)
	Campaign.save_now()
	_broadcast()


func _restock(day: int) -> void:
	stock = Constants.SHOP_DAILY_STOCK.duplicate(true)
	stock_day = day
	arrived_today.clear()
	vending_stuck.clear()
	# A haggle sticks to its piece for good (the morning doesn't wipe it); only
	# the pieces that are gone are forgotten.
	_forget_gone_haggles()
	_roll_rusty(day)


## Host: drop the haggles of junk that isn't in the world any more.
func _forget_gone_haggles() -> void:
	if haggled.is_empty() or not is_inside_tree():
		return
	var here: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group("junk"):
		here[str(node.name)] = true
	for key: Variant in haggled.keys():
		if not here.has(str(key)):
			haggled.erase(key)


## Host: Rusty's mood today (Constants.RUSTY_MOOD, his chalkboard says it) and
## the used tools on his rack (USED_TOOLS_PER_DAY of the tools the crew's rank
## sells), from the town's seed and the day, so a day replays the same.
func _roll_rusty(day: int) -> void:
	var rng := RandomNumberGenerator.new()
	var town := get_tree().get_first_node_in_group("town") if is_inside_tree() else null
	rng.seed = hash([int(town.get("town_seed")) if town != null else 0, day, "rusty"])
	rusty_mood = snappedf(rng.randf_range(Constants.RUSTY_MOOD.x, Constants.RUSTY_MOOD.y), 0.01)
	var candidates: Array[String] = []
	# p2-kit: a used rake, whenever he has one (the rake's sold from the start).
	for tool: String in Catalog.kit_tools():
		if Campaign.is_for_sale(StringName(Catalog.tool_item(tool, Catalog.TIER_USED))):
			candidates.append(tool)
	used_today = []
	var count := mini(rng.randi_range(Constants.USED_TOOLS_PER_DAY.x, Constants.USED_TOOLS_PER_DAY.y), candidates.size())
	for _pick: int in count:
		used_today.append(candidates.pop_at(rng.randi() % candidates.size()))


func _set_supply(id: String, amount: float) -> void:
	if not SUPPLY_IDS.has(id):
		return
	supplies[id] = _supply_value(id, amount)


## Gas is gallons (a float); everything else is a whole count.
static func _supply_value(id: String, amount: Variant) -> Variant:
	if id == "gas":
		return float(amount)
	return int(round(float(amount)))


static func _supplies_from(source: Dictionary) -> Dictionary:
	var out := {}
	for id: String in SUPPLY_IDS:
		out[id] = _supply_value(id, source.get(id, 0))
	return out


## Timed test runs never run out of bags or gas, so the old tests and soaks
## don't change; --shop-test runs on the real starter supplies.
func _unlimited_supplies() -> bool:
	var options := Net.dev_options()
	var timed := float(options.get("run_seconds")) > 0.0 or Net.is_automated()
	return timed and not bool(options.get("shop_test"))


static func _fishing(shop: String, day: int) -> bool:
	return shop == "rustys" and Constants.RUSTYS_CLOSED_EVERY > 0 and day % Constants.RUSTYS_CLOSED_EVERY == 0


func _send_result(peer_id: int, code: String, item: String, amount: int) -> void:
	if peer_id == Net.local_peer_id():
		result.emit(code, item, amount)
	elif multiplayer.multiplayer_peer != null:
		_rpc_result.rpc_id(peer_id, code, item, amount)


# ---------------------------------------------------------------- save

## The "shops" save section (gap-specs/critic.md, "Save keys").
func _save_section() -> Dictionary:
	return {"shops": {
		"version": SECTION_VERSION,
		"stock_day": stock_day,
		"stock": stock,
		"supplies": supplies_to_save(),
		"orders": orders,
		"looks": looks,
		"truck": truck,
		"crew_owned": crew_owned,
		"rusty_mood": rusty_mood,
		"used_today": used_today,
		"junk_left": _unsold_junk(),
		"vending_eaten": vending_eaten,
	}}


## The supplies as the save writes them. Chefty filled the job tools' tanks and
## the gas can out of the supply, and what's left in them only comes back after
## the job (world._return_job_gas), so the save counts it as the crew's already:
## a host who quits mid-job or on the ride home loses none of it (job tools
## aren't saved, so it can't be counted twice).
func supplies_to_save() -> Dictionary:
	var out := supplies.duplicate()
	if out.has("gas") and is_inside_tree():
		out["gas"] = _supply_value("gas", float(out["gas"]) + _ToolTiers.gas_out(get_tree().get_nodes_in_group("job_tools")))
	return out


## Fills the state from a saved section (empty for a new or older save), with
## every value retyped (JSON reads numbers as floats) and defaults for what's missing.
func _read_section(saved: Dictionary) -> void:
	supplies = _supplies_from(Constants.STARTER_SUPPLIES)
	var saved_supplies: Dictionary = saved.get("supplies", {}) if typeof(saved.get("supplies")) == TYPE_DICTIONARY else {}
	for id: String in SUPPLY_IDS:
		if saved_supplies.has(id):
			supplies[id] = _supply_value(id, saved_supplies[id])
	stock_day = int(saved.get("stock_day", 0))
	stock = Constants.SHOP_DAILY_STOCK.duplicate(true)
	var saved_stock: Dictionary = saved.get("stock", {}) if typeof(saved.get("stock")) == TYPE_DICTIONARY else {}
	for shop: String in stock:
		var shelf: Dictionary = stock[shop]
		var saved_shelf: Dictionary = saved_stock.get(shop, {}) if typeof(saved_stock.get(shop)) == TYPE_DICTIONARY else {}
		for item: String in shelf:
			if saved_shelf.has(item):
				shelf[item] = maxi(int(saved_shelf[item]), 0)
	# Orders still on the way (shops chunk 8), retyped: JSON brings ints back as floats.
	orders = []
	for order: Variant in (saved.get("orders", []) as Array if typeof(saved.get("orders")) == TYPE_ARRAY else []):
		if typeof(order) != TYPE_DICTIONARY or not orderable(str((order as Dictionary).get("item", ""))):
			continue
		orders.append({
			"item": str(order["item"]), "qty": maxi(int((order as Dictionary).get("qty", 1)), 1),
			"arrive_day": int((order as Dictionary).get("arrive_day", 0)), "arrive_minutes": float((order as Dictionary).get("arrive_minutes", 0.0)),
			"by": str((order as Dictionary).get("by", "")),
		})
	looks = {}
	if typeof(saved.get("looks")) == TYPE_DICTIONARY:
		for key: Variant in (saved["looks"] as Dictionary):
			var look: Variant = saved["looks"][key]
			if typeof(look) == TYPE_DICTIONARY:
				looks[str(key)] = {"hat": str((look as Dictionary).get("hat", "")), "shirt": str((look as Dictionary).get("shirt", ""))}
	truck = {"paint": DEFAULT_PAINT, "decal": ""}
	if typeof(saved.get("truck")) == TYPE_DICTIONARY:
		truck["paint"] = str((saved["truck"] as Dictionary).get("paint", DEFAULT_PAINT))
		truck["decal"] = str((saved["truck"] as Dictionary).get("decal", ""))
	crew_owned = []
	for id: Variant in (saved.get("crew_owned", []) as Array if typeof(saved.get("crew_owned")) == TYPE_ARRAY else []):
		crew_owned.append(str(id))
	rusty_mood = float(saved.get("rusty_mood", 1.0))
	used_today = []
	for id: Variant in (saved.get("used_today", []) as Array if typeof(saved.get("used_today")) == TYPE_ARRAY else []):
		used_today.append(str(id))
	junk_left = (saved.get("junk_left", []) as Array).duplicate(true) if typeof(saved.get("junk_left")) == TYPE_ARRAY else []
	vending_eaten = int(saved.get("vending_eaten", 0))


# ---------------------------------------------------------------- replication

func _broadcast() -> void:
	_broadcast_queued = false
	if multiplayer.multiplayer_peer == null:
		changed.emit()
		return
	_rpc_state.rpc(stock, supplies, orders, looks, truck, crew_owned, buffs, _extra())


## Many small changes in one frame (bags being used) go out as one snapshot.
func _queue_broadcast() -> void:
	if _broadcast_queued:
		return
	_broadcast_queued = true
	_broadcast.call_deferred()


func _extra() -> Dictionary:
	return {
		"rusty_mood": rusty_mood,
		"haggled": haggled,
		"used_today": used_today,
		"arrived_today": arrived_today,
		"stock_day": stock_day,
		"vending_eaten": vending_eaten,
		"vending_stuck": vending_stuck,
		"snacks": snacks,
	}


func _on_player_joined(peer_id: int) -> void:
	if Net.is_host() and peer_id != Net.local_peer_id():
		_rpc_state.rpc_id(peer_id, stock, supplies, orders, looks, truck, crew_owned, buffs, _extra())


func _on_player_left(peer_id: int) -> void:
	if Net.is_host() and (buffs.has(peer_id) or snacks.has(peer_id)):
		buffs.erase(peer_id)
		snacks.erase(peer_id)
		_broadcast()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_state() -> void:
	if Net.is_host():
		_rpc_state.rpc_id(multiplayer.get_remote_sender_id(), stock, supplies, orders, looks, truck, crew_owned, buffs, _extra())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_buy(shop: String, item: String, qty: int) -> void:
	if Net.is_host():
		host_buy(multiplayer.get_remote_sender_id(), shop, item, qty)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_sell(prop_path: NodePath, haggle: bool) -> void:
	if Net.is_host():
		host_sell(multiplayer.get_remote_sender_id(), prop_path, haggle)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_equip(slot: String, item: String) -> void:
	if Net.is_host():
		host_equip(multiplayer.get_remote_sender_id(), slot, item)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_apply_truck(item: String) -> void:
	if Net.is_host():
		host_apply_truck(multiplayer.get_remote_sender_id(), item)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_give(to_peer: int, amount: int) -> void:
	if Net.is_host():
		host_give(multiplayer.get_remote_sender_id(), to_peer, amount)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_order(item: String, qty: int) -> void:
	if Net.is_host():
		host_order(multiplayer.get_remote_sender_id(), item, qty)


## Every peer: an order landed (host_land). Sent before the snapshot that
## carries the crates, so the pallet lobs them in rather than drawing them.
@rpc("authority", "call_local", "reliable")
func _rpc_delivered(crates: Array, tools: int) -> void:
	delivered.emit(crates, tools)


## Every peer: a crewmate paid another (host_give).
@rpc("authority", "call_local", "reliable")
func _rpc_gave(from_peer: int, to_peer: int, amount: int) -> void:
	gave.emit(from_peer, to_peer, amount)


@rpc("authority", "call_local", "reliable")
func _rpc_state(all_stock: Dictionary, all_supplies: Dictionary, all_orders: Array, all_looks: Dictionary, look_of_truck: Dictionary, owned: Array, all_buffs: Dictionary, extra: Dictionary) -> void:
	if Net.is_host():
		# The host's state is the source; it only tells its own UI.
		changed.emit()
		return
	var old_looks := looks
	var old_truck := truck
	stock = all_stock
	supplies = all_supplies
	orders = all_orders
	looks = all_looks
	truck = look_of_truck
	crew_owned = owned
	buffs = all_buffs
	rusty_mood = float(extra.get("rusty_mood", 1.0))
	haggled = extra.get("haggled", {})
	used_today = extra.get("used_today", [])
	arrived_today = extra.get("arrived_today", [])
	stock_day = int(extra.get("stock_day", 0))
	vending_eaten = int(extra.get("vending_eaten", 0))
	vending_stuck = extra.get("vending_stuck", [])
	snacks = extra.get("snacks", {})
	# A joiner's first snapshot puts everyone's look on without the show
	# (player.gd _on_looks_changed reads this while the signal runs).
	first_snapshot = not synced
	synced = true
	for peer_id: int in Net.peer_ids():
		var key := Campaign.key_of(peer_id)
		if JSON.stringify(old_looks.get(key, {})) != JSON.stringify(looks.get(key, {})):
			looks_changed.emit(peer_id)
	if JSON.stringify(old_truck) != JSON.stringify(truck):
		truck_changed.emit()
	first_snapshot = false
	changed.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_result(code: String, item: String, amount: int) -> void:
	result.emit(code, item, amount)


# ---------------------------------------------------------------- helpers

func _clock() -> Node:
	return get_tree().get_first_node_in_group("day_clock")


func _today() -> int:
	var clock := _clock()
	return int(clock.get("day")) if clock != null else 1


func _site_zone(site: Dictionary) -> Node3D:
	var world := get_tree().get_first_node_in_group("world")
	if world == null or not site.has("zone"):
		return null
	return world.get_node_or_null(str(site["zone"])) as Node3D


func _player_body(peer_id: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node as Node3D
	return null
