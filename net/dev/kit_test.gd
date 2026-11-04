extends Node

## Authority: both peers run it (--kit-test on the host and the client; p2-kit,
## docs/GAME.md "The crew's kit"). A crew of two on Day 1, the client 150 ms
## away, plays the kit's whole loop as players would:
##   a. wallet: both start with Constants.STARTING_CASH;
##   b. buy: each walks to the rake bin inside Homie Depot's doors and buys a
##      rake: the price comes off their own cash and the rake lands in their
##      hands, a stock rake, the crew's kit (Kit.count_of), on both peers;
##   c. load: beside Chefty, E with the rake in hand says "Load", and the rake
##      goes onto the rack over the cab: the prop is gone and the bed draws it,
##      on both peers (a blower with a low tank rides along too);
##   d. ride: both ride to the yard; leaving the store tops the blower's tank
##      up out of the crew's gas;
##   e. take: looking at a rake on the rack, E says "Take" and the rake comes
##      into your hands; a stroke with it rakes like a rake (a stock rake's
##      strength, the leaves move);
##   f. the host leaves its rake on the lawn; the client keeps its own in its
##      pockets; both ride home: the client's rake came home with it, the
##      host's is gone with the yard but still the crew's;
##   g. sleep: in the morning the host's rake is by the store's front door and
##      a neighbor texts that it was found;
##   h. the save has the kit (where each thing is), and an old save's tool
##      unlocks turn into kit (Kit.migrate_players);
##   i. a take refused in its hand-off beat (arms filled) goes back aboard,
##      and a second take while one is on its way is refused.
## Each step prints a [KitTest] line; CI needs both peers' ok.

const _KitRules = preload("res://core/kit_rules.gd")
const _Kit = preload("res://net/kit/kit.gd")
const _Strings = preload("res://ui/strings.gd")
const WAIT_SECONDS: float = 6.0
const RIDE_SECONDS: float = 20.0
## The blower that rides along, and how full its tank is before the top-up.
const BLOWER_FUEL: float = 20.0

static var result: Dictionary = {}

var _started: bool = false
var _ok: bool = true


func _ready() -> void:
	result = {"ok": false, "steps": {}}


func _process(_delta: float) -> void:
	if _started or _own_player() == null or _kit() == null or _bed() == null:
		return
	if Net.peer_ids().size() < 2 or _other_player() == null:
		return
	if not bool(_kit().get("synced")) and not Net.is_host():
		return
	_started = true
	if Net.is_host():
		_run_host()
	else:
		_run_client()


# ---------------------------------------------------------------- host

func _run_host() -> void:
	# The client's world, its pockets and its own test node come up.
	await _seconds(3.0)
	var me := Net.local_peer_id()
	var mate := _other_player().name.to_int()
	_step("a wallet", Campaign.credits(me) == Constants.STARTING_CASH and Campaign.credits(mate) == Constants.STARTING_CASH and _kit_count("rake") == 0,
		"host $%d, client $%d, rakes %d" % [Campaign.credits(me), Campaign.credits(mate), _kit_count("rake")])
	# b. buy
	var bought := await _buy_rake()
	var mine := _held_rake(me)
	var price := Catalog.price("rake")
	_step("b buy", bought and mine != null and int(mine.get("tier")) == Catalog.TIER_STOCK and Campaign.credits(me) == Constants.STARTING_CASH - price,
		"bought %s, in hand %s, $%d left" % [bought, mine != null, Campaign.credits(me)])
	# c. load: "[E] Load" by the bed, and onto the rack.
	_move_to_bed_side(Vector3(1.9, 0.0, -0.4))
	await _ticks(4)
	var choice: Dictionary = _own_player().call("e_choice")
	var says := str((choice["hint"] as Dictionary).get("text", ""))
	mine.call("request_load_truck")
	# By path: a lambda can't hold on to a node that gets freed.
	var mine_path := mine.get_path()
	var loaded := await _until(func() -> bool: return _bed_count("rake") >= 1 and get_node_or_null(mine_path) == null, WAIT_SECONDS)
	_step("c load", StringName(choice["do"]) == &"load_truck" and says == str(_Strings.SHOP_UI["prompt_load_kit"]) and loaded,
		"E would %s ('%s'), on the rack %s" % [choice["do"], says, loaded])
	# The client buys its own (its half: it shops once the host's is aboard), off its own cash.
	var client_bought := await _until(func() -> bool: return Campaign.credits(mate) == Constants.STARTING_CASH - price and _kit_count("rake") == 2, 20.0)
	_step("b2 client buy", client_bought, "client $%d, crew rakes %d" % [Campaign.credits(mate), _kit_count("rake")])
	var client_loaded := await _until(func() -> bool: return _bed_count("rake") == 2 and _held_rake(mate) == null, 20.0)
	_step("c2 client load", client_loaded, "rakes aboard %d" % _bed_count("rake"))
	# A blower with a low tank rides along (bought or not: the top-up's the thing here).
	_bed().call("restore", [{"kind": "leaf_blower", "tier": Catalog.TIER_STOCK, "fuel": BLOWER_FUEL}])
	var shops := get_tree().get_first_node_in_group("shops")
	var gas_before := float(shops.call("supply", "gas"))
	# d. ride to the yard together.
	var arrived := await _ride([me, mate], Net.Zone.LOT)
	var blower := _bed_entry("leaf_blower")
	var gas_used := gas_before - float(shops.call("supply", "gas"))
	var topped := not blower.is_empty() and is_equal_approx(float(blower["fuel"]), 100.0) and absf(gas_used - (100.0 - BLOWER_FUEL) / 100.0 * Constants.GAS_PER_TANK) < 0.01
	_step("d ride", arrived and _bed_count("rake") == 2 and topped, "at the yard %s, rakes aboard %d, blower %.0f%% (gas used %.2f gal)" % [arrived, _bed_count("rake"), float(blower.get("fuel", -1.0)), gas_used])
	# e. take one off the rack, the way a player looks at it and presses E.
	_move_to_bed_side(Vector3(1.9, 0.0, -0.8))
	await _ticks(3)
	var aimed := await _aim_at_bed("rake")
	var take: Dictionary = _own_player().call("e_choice")
	var take_says := str((take["hint"] as Dictionary).get("text", ""))
	if StringName(take["do"]) == &"take_kit":
		_bed().call("request_take", int((take["target"] as Dictionary)["index"]))
	var took := await _until(func() -> bool: return _held_rake(me) != null, WAIT_SECONDS)
	_step("e take", aimed and StringName(take["do"]) == &"take_kit" and take_says == str(_Strings.SHOP_UI["prompt_take_kit"]) and took and _bed_count("rake") == 1,
		"aimed %s, E would %s ('%s'), in hand %s, rakes aboard %d" % [aimed, take["do"], take_says, took, _bed_count("rake")])
	var raked := await _rake_a_lane()
	_step("e2 rake", raked, "the leaves moved")
	var client_took := await _until(func() -> bool: return _carried_rake(mate) != null and _bed_count("rake") == 0, 20.0)
	_step("e3 client take", client_took, "client carries one %s, rakes aboard %d" % [client_took, _bed_count("rake")])
	# f. the host leaves its rake on the lawn; both ride home.
	mine = _held_rake(me)
	if mine != null:
		_own_player().call("apply_network_teleport", Transform3D(_own_player().global_basis, _lot_origin() + Vector3(-6.0, 0.2, 4.0)))
		await _ticks(3)
		mine.call("request_drop")
	await _until(func() -> bool: return mine != null and bool(mine.call("is_loose")), WAIT_SECONDS)
	var home := await _ride([me, mate], Net.Zone.STORE)
	await _seconds(1.0)
	var kit := _kit()
	var lost := (kit.get("lost") as Array).size()
	var client_home := _carried_rake(mate) != null
	await _until(func() -> bool: return _kit_count("rake") == 2, WAIT_SECONDS)
	_step("f home", home and lost == 1 and client_home and _kit_count("rake") == 2 and not is_instance_valid(mine),
		"home %s, left at the yard %d, the client's came home %s, crew rakes %d" % [home, lost, client_home, _kit_count("rake")])
	# g. sleep: in the morning it's by the door, and a neighbor texts.
	var town := get_tree().get_first_node_in_group("town")
	var texts_before := (town.get("texts") as Array).size() if town != null else 0
	get_tree().get_first_node_in_group("day_clock").call("force_sleep")
	var at_door := await _until(func() -> bool: return _door_rake() != null, WAIT_SECONDS)
	var text := _new_text(texts_before)
	_step("g morning", at_door and (kit.get("lost") as Array).is_empty() and text != "" and text.contains("rake"),
		"by the door %s, text '%s'" % [at_door, text])
	# h. the save, and an old save's tools.
	Campaign.save_now()
	var saved := _saved_kit()
	var places := {}
	for item: Variant in saved:
		var key := "%s@%s" % [str((item as Dictionary).get("kind")), str((item as Dictionary).get("at"))]
		places[key] = int(places.get(key, 0)) + 1
	_step("h save", int(places.get("rake@store", 0)) == 1 and int(places.get("rake@pockets", 0)) == 1 and int(places.get("leaf_blower@bed", 0)) == 1, "saved %s" % str(places))
	var old := _Kit.migrate_players({
		"name:A": {"credits": 10, "unlocks": ["rake_tier_1", "leaf_blower", "leaf_blower_mk2", "hat_beanie"]},
		"name:B": {"credits": 5, "unlocks": ["lawn_mower_used"]},
	})
	var kinds := old.map(func(item: Variant) -> String: return "%s:%d" % [str((item as Dictionary)["kind"]), int((item as Dictionary)["tier"])])
	kinds.sort()
	_step("h2 old save", kinds == ["lawn_mower:0", "leaf_blower:2", "rake:1", "rake:2"], "an old save's two players bring %s" % str(kinds))
	# The neighbor's text names a proper-named tool without a second article.
	var leafinator := _KitRules.sentence_name("rake", Catalog.TIER_MK3)
	_step("h3 names", leafinator == "Leafinator" and _KitRules.sentence_name("rake", Catalog.TIER_STOCK) == "rake", "Mk III '%s'" % leafinator)
	# Wait for the client's verdict on what it saw (it counts the crew's rakes).
	await _seconds(2.5)
	# i. a take whose hand-off is refused goes back aboard (no loose ghost), and
	# a second take while one is on its way is refused; j. hose or load by the tap.
	await _refused_take()
	_finish()


## Host: a rake goes on the rack and a washer on the bed floor; E on the rake,
## E on the washer straight after (refused: one take at a time), then the host's
## arms fill with a ladder in the hand-off's beat, so the rake's hand-off is
## refused: both stay aboard and no rake lies loose by the truck.
func _refused_take() -> void:
	var me := Net.local_peer_id()
	_bed().call("restore", [{"kind": "rake", "tier": Catalog.TIER_STOCK, "fuel": 100.0}, {"kind": "pressure_washer", "tier": Catalog.TIER_STOCK, "fuel": 100.0}])
	var rakes := _bed_count("rake")
	_move_to_bed_side(Vector3(1.9, 0.0, -0.4))
	await _ticks(3)
	_bed().call("request_take", _bed_index("rake"))
	_bed().call("request_take", _bed_index("pressure_washer"))
	# The rake left the rack for its hand-off; the washer's take was refused.
	var mid := _bed_count("rake") == rakes - 1 and _bed_count("pressure_washer") == 1
	var ladder := _kit().call("spawn_item", "ladder", Catalog.TIER_STOCK, 100.0, Transform3D(Basis.IDENTITY, _own_player().global_position + Vector3(0.6, 0.5, 0.0))) as Node3D
	ladder.call("_handle_grab", me, false)
	await _seconds(Constants.KIT_TAKE_HANDOFF_SECONDS + 0.5)
	var loose := 0
	var truck_at := (_bed() as Node3D).global_position
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) == "rake" and not node.is_queued_for_deletion() and bool(node.call("is_loose")) and (node as Node3D).global_position.distance_to(truck_at) < 6.0:
			loose += 1
	_step("i refused take", mid and _bed_count("rake") == rakes and _bed_count("pressure_washer") == 1 and loose == 0 and int(ladder.get("held_by")) == me,
		"mid-take %s, rakes aboard %d of %d, washer aboard %d, loose by the truck %d, ladder held %s" % [mid, _bed_count("rake"), rakes, _bed_count("pressure_washer"), loose, int(ladder.get("held_by")) == me])
	# j. by Chefty's water tap with the washer: looking at the bed, E loads it;
	# looking at the tap, E refills it.
	ladder.call("request_load_truck")
	await _until(func() -> bool: return _bed_count("ladder") == 1, WAIT_SECONDS)
	# The loaded prop is freed at the frame's end; till then it's still in your arms.
	await _ticks(3)
	_bed().call("request_take", _bed_index("pressure_washer"))
	var washer_held := await _until(func() -> bool: return _held_kind(me) == "pressure_washer", WAIT_SECONDS)
	var tap: Node3D = null
	for node: Node in get_tree().get_nodes_in_group("water_sources"):
		if node.has_meta("kind") and str(node.get_meta("kind")) == "chefty":
			tap = node as Node3D
	if tap == null or not washer_held:
		_step("j tap or load", false, "tap %s, washer in hand %s (holding '%s', ladders aboard %d)" % [tap != null, washer_held, _held_kind(me), _bed_count("ladder")])
		return
	var middle := (_bed() as Node3D).global_transform * Vector3(0.0, 1.2, 0.7)
	var away := Vector3(tap.global_position.x - middle.x, 0.0, tap.global_position.z - middle.z).normalized()
	var stand := tap.global_position + away * 1.4
	_own_player().call("apply_network_teleport", Transform3D(_own_player().global_basis, Vector3(stand.x, _own_player().global_position.y + 0.1, stand.z)))
	await _ticks(4)
	await _aim_at(_bed().call("load_point") as Vector3)
	var at_bed := StringName((_own_player().call("e_choice") as Dictionary)["do"])
	await _aim_at(tap.global_position)
	var at_tap := StringName((_own_player().call("e_choice") as Dictionary)["do"])
	_step("j tap or load", at_bed == &"load_truck" and at_tap == &"water", "looking at the bed E would %s, at the tap %s" % [at_bed, at_tap])


func _held_kind(peer_id: int) -> String:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if int(node.get("held_by")) == peer_id and not node.is_queued_for_deletion():
			return str(node.get("kind"))
	return ""


func _aim_at(point: Vector3) -> void:
	var player := _own_player()
	for _try: int in 3:
		var head := player.get_node_or_null("Visual/Head") as Node3D
		var eye := head.global_position if head != null else player.global_position + Vector3.UP * 1.6
		var to := point - eye
		player.set("body_yaw", atan2(-to.x, -to.z))
		player.rotation.y = float(player.get("body_yaw"))
		player.set("head_pitch", atan2(to.y, Vector2(to.x, to.z).length()))
		await _ticks(1)


func _bed_index(kind: String) -> int:
	var tools: Array = _bed().get("tools")
	for index: int in tools.size():
		if str((tools[index] as Dictionary)["kind"]) == kind:
			return index
	return -1


## Host: to the rake bin's front, and buy one.
func _buy_rake() -> bool:
	var bin := _rake_bin()
	if bin == null:
		return false
	var front: Vector3 = bin.call("slot_front", 0)
	_own_player().call("apply_network_teleport", Transform3D(_own_player().global_basis, front + Vector3.UP * 0.1))
	await _ticks(3)
	var shops := get_tree().get_first_node_in_group("shops")
	shops.call("request_buy", "homie_depot", "rake", 1)
	return await _until(func() -> bool: return _held_rake(Net.local_peer_id()) != null, WAIT_SECONDS)


func _ride(riders: Array, zone: int) -> bool:
	var ride := get_tree().get_first_node_in_group("chefty")
	ride.call("depart", riders, zone)
	await _seconds(0.5)
	var waited := 0.0
	while bool(ride.call("is_riding")) and waited < RIDE_SECONDS:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	await _seconds(1.5)
	return Net.player_zone(Net.local_peer_id()) == zone


## Host: three strokes with the rake in hand; true when the leaves where they
## landed thinned, at a stock rake's strength.
func _rake_a_lane() -> bool:
	var field := get_tree().get_first_node_in_group("leaf_field")
	if field == null:
		return false
	var me := Net.local_peer_id()
	var params: Dictionary = field.call("_stroke_params", me, Constants.RAKE_WIDTH, Constants.RAKE_STRENGTH)
	var start := _lot_origin() + Vector3(-6.0, 0.2, -2.0)
	var before := int(field.call("sample_world", start + Vector3(0.5, 0.0, 0.0)))
	for index: int in 3:
		var at := start + Vector3(float(index) * 0.5, 0.0, 0.0)
		_own_player().call("apply_network_teleport", Transform3D(_own_player().global_basis, at - Vector3(1.5, 0.0, 0.0)))
		_own_player().set("body_yaw", atan2(-1.0, 0.0))
		field.call("request_rake", at, Vector3(1.0, 0.0, 0.0), Constants.RAKE_WIDTH, Constants.RAKE_STRENGTH)
		await _ticks(2)
	var after := int(field.call("sample_world", start + Vector3(0.5, 0.0, 0.0)))
	print("[KitTest] stroke %s at strength %.2f; leaves %d -> %d" % [params["kind"], float(params["strength"]), before, after])
	return str(params["kind"]) == "rake" and is_equal_approx(float(params["strength"]), Constants.RAKE_STRENGTH) and after < before


# ---------------------------------------------------------------- client

func _run_client() -> void:
	await _seconds(2.0)
	var me := Net.local_peer_id()
	var wallet := await _until(func() -> bool: return Campaign.credits(me) == Constants.STARTING_CASH, WAIT_SECONDS)
	_step("a wallet (client)", wallet, "$%d" % Campaign.credits(me))
	# Wait until the host has bought and loaded its own, then shop.
	await _until(func() -> bool: return _bed_count("rake") >= 1, 30.0)
	var bought := await _buy_rake()
	await _until(func() -> bool: return _kit_count("rake") == 2, WAIT_SECONDS)
	_step("b buy (client)", bought and Campaign.credits(me) == Constants.STARTING_CASH - Catalog.price("rake") and _kit_count("rake") == 2,
		"in hand %s, $%d, crew rakes %d here" % [bought, Campaign.credits(me), _kit_count("rake")])
	_move_to_bed_side(Vector3(-1.9, 0.0, -0.4))
	await _ticks(6)
	var choice: Dictionary = _own_player().call("e_choice")
	var held := _held_rake(me)
	if held != null and StringName(choice["do"]) == &"load_truck":
		held.call("request_load_truck")
	var loaded := await _until(func() -> bool: return _bed_count("rake") == 2 and _held_rake(me) == null, WAIT_SECONDS)
	var drawn := _bed().get_node_or_null("Load")
	_step("c load (client)", loaded and drawn != null and drawn.get_child_count() >= 2, "E would %s, rakes drawn aboard %d" % [choice["do"], drawn.get_child_count() if drawn != null else -1])
	# d/e: at the yard, once the host took its rake, take the other the same way.
	var at_yard := await _until(func() -> bool: return Net.player_zone(me) == Net.Zone.LOT and not bool(get_tree().get_first_node_in_group("chefty").call("is_riding")), 40.0)
	await _until(func() -> bool: return _bed_count("rake") == 1, 30.0)
	await _seconds(1.0)
	_move_to_bed_side(Vector3(-1.9, 0.0, -0.8))
	await _ticks(4)
	var aimed := await _aim_at_bed("rake")
	var take: Dictionary = _own_player().call("e_choice")
	if StringName(take["do"]) == &"take_kit":
		_bed().call("request_take", int((take["target"] as Dictionary)["index"]))
	var took := await _until(func() -> bool: return _held_rake(me) != null, WAIT_SECONDS)
	_step("e take (client)", at_yard and aimed and StringName(take["do"]) == &"take_kit" and took, "at the yard %s, aimed %s, E would %s, in hand %s" % [at_yard, aimed, take["do"], took])
	# f: home with it.
	var home := await _until(func() -> bool: return Net.player_zone(me) == Net.Zone.STORE and not bool(get_tree().get_first_node_in_group("chefty").call("is_riding")), 60.0)
	await _seconds(1.0)
	_step("f home (client)", home and _carried_rake(me) != null, "home %s, the rake came too %s" % [home, _carried_rake(me) != null])
	# g: the morning's rake by the door and the neighbor's text, here too.
	var town := get_tree().get_first_node_in_group("town")
	var texts_before := (town.get("texts") as Array).size() if town != null else 0
	var at_door := await _until(func() -> bool: return _door_rake() != null, 30.0)
	await _seconds(0.5)
	var text := _new_text(texts_before)
	_step("g morning (client)", at_door and text.contains("rake") and _kit_count("rake") == 2, "by the door %s, text '%s', crew rakes %d" % [at_door, text, _kit_count("rake")])
	_finish()


# ---------------------------------------------------------------- shared

## Turns the local player's view onto the first tool of this kind on the rack;
## true once the bed says that's the one looked at.
func _aim_at_bed(kind: String) -> bool:
	var bed := _bed()
	var player := _own_player()
	var target := -1
	for index: int in (bed.get("tools") as Array).size():
		if str(((bed.get("tools") as Array)[index] as Dictionary)["kind"]) == kind:
			target = index
			break
	if target < 0:
		return false
	var at: Vector3 = bed.call("_world_middle", (bed.get("tools") as Array)[target])
	for _try: int in 30:
		var head := player.get_node_or_null("Visual/Head") as Node3D
		var eye := head.global_position if head != null else player.global_position + Vector3.UP * 1.6
		var to := at - eye
		player.set("body_yaw", atan2(-to.x, -to.z))
		player.rotation.y = float(player.get("body_yaw"))
		player.set("head_pitch", atan2(to.y, Vector2(to.x, to.z).length()))
		await _ticks(1)
		var seen: Dictionary = bed.call("looked_at", player)
		if not seen.is_empty() and int(seen["index"]) == target:
			return true
	return false


func _move_to_bed_side(local: Vector3) -> void:
	var chefty := get_tree().get_first_node_in_group("chefty")
	var at := (chefty.call("bed_transform") as Transform3D) * local
	_own_player().call("apply_network_teleport", Transform3D(_own_player().global_basis, Vector3(at.x, at.y + 0.1, at.z)))


func _rake_bin() -> Node:
	return get_tree().get_first_node_in_group("rake_bin")


## A rake in this peer's hands, or null.
func _held_rake(peer_id: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) == "rake" and int(node.get("held_by")) == peer_id and not node.is_queued_for_deletion():
			return node as Node3D
	return null


## A rake in this peer's hands or pockets, or null.
func _carried_rake(peer_id: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) == "rake" and (int(node.get("held_by")) == peer_id or int(node.get("pocketed_by")) == peer_id) and not node.is_queued_for_deletion():
			return node as Node3D
	return null


## A loose rake lying in STORE_LAYOUT's "kit_door", or null.
func _door_rake() -> Node3D:
	var world := get_tree().get_first_node_in_group("world")
	var store := world.get_node_or_null("StoreZone") as Node3D if world != null else null
	if store == null:
		return null
	var rect: Rect2 = Constants.STORE_LAYOUT["kit_door"]["rect"]
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) != "rake" or not bool(node.call("is_loose")):
			continue
		var local := store.to_local((node as Node3D).global_position)
		if rect.grow(0.6).has_point(Vector2(local.x, local.z)):
			return node as Node3D
	return null


## The newest text from the neighbor since there were `before` texts, or "".
func _new_text(before: int) -> String:
	var town := get_tree().get_first_node_in_group("town")
	if town == null:
		return ""
	var texts: Array = town.get("texts")
	for index: int in range(texts.size() - 1, mini(before, texts.size()) - 1, -1):
		var entry: Dictionary = texts[index]
		if str(entry.get("from", "")) == str(_Strings.SHOP_UI["text_from_neighbor"]):
			return str(entry.get("text", ""))
	return ""


func _saved_kit() -> Array:
	var file := FileAccess.open(Campaign.save_path(), FileAccess.READ)
	if file == null:
		return []
	var data: Variant = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return []
	return ((data as Dictionary).get("kit", {}) as Dictionary).get("items", [])


func _bed_entry(kind: String) -> Dictionary:
	for entry: Dictionary in _bed().get("tools") as Array:
		if str(entry["kind"]) == kind:
			return entry
	return {}


func _bed_count(kind: String) -> int:
	return int(_bed().call("count_of", kind)) if _bed() != null else 0


func _kit_count(kind: String) -> int:
	return int(_kit().call("count_of", kind)) if _kit() != null else 0


func _bed() -> Node:
	var chefty := get_tree().get_first_node_in_group("chefty")
	return chefty.call("tool_bed") as Node if chefty != null and chefty.has_method("tool_bed") else null


func _kit() -> Node:
	return get_tree().get_first_node_in_group("kit")


func _lot_origin() -> Vector3:
	var world := get_tree().get_first_node_in_group("world")
	var zone := world.get_node_or_null("LotZone") as Node3D if world != null else null
	return zone.global_position if zone != null else Vector3.ZERO


func _step(label: String, passed: bool, detail: String) -> void:
	print("[KitTest] %s: %s (%s)" % [label, passed, detail])
	(result["steps"] as Dictionary)[label] = passed
	_ok = _ok and passed


func _finish() -> void:
	result["ok"] = _ok
	result["done"] = true
	print("[KitTest] all ok: %s" % _ok)


func _until(check: Callable, limit_seconds: float) -> bool:
	var waited := 0.0
	while waited < limit_seconds:
		if bool(check.call()):
			return true
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	return bool(check.call())


func _seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _ticks(count: int) -> void:
	for _tick: int in count:
		await get_tree().physics_frame


func _own_player() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as Node3D
	return null


func _other_player() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name != str(Net.local_peer_id()) and node.name.to_int() > 0:
			return node as Node3D
	return null
