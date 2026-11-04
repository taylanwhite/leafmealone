extends Node

## Authority: host. The crew's kit (docs/GAME.md "The crew's kit"; p2-kit).
## Taylan, 2026-11-03: "You gotta buy the equipment and load it up on the Chefty.
## Everyone spawns in with $50."
##
## Every rake and tool the crew owns is a thing in the world: a yard prop of a kit
## kind (Constants.KIT_KINDS, core/kit_rules.gd) lying somewhere, in someone's
## hands or pockets, or cargo in Chefty's bed (net/components/tool_bed.gd, which
## draws it on the rack over the cab). Who paid doesn't matter: it's crew kit.
## This node keeps nothing a prop already says; it only:
##   - makes a bought tool (host_deliver): a pocket tool into the buyer's hands
##     (at their feet with full pockets), a big one by the store's front door;
##   - sweeps up after a yard: kit left lying on a yard that goes away is "lost"
##     (host_yard_freed), and the next morning everything lost or left lying
##     out in town is by the front door, with a neighbor's text (_on_day_started);
##   - keeps the crew's summary on every peer (owned: {kind: tiers}), which job
##     offers, the shop and the shelves read (Campaign.crew_tool_tier);
##   - saves it all ("kit" section) and puts it back on load: what was in the
##     bed in the bed, everything else by the front door. A save from before
##     p2-kit turns each player's tool unlocks into tools by the door, plus a
##     rake for everyone (_migrate).
## World/Kit is made on every peer in world._ready, next to Shops, so RPC paths match.

signal changed

const _KitRules = preload("res://core/kit_rules.gd")
const _ToolTiers = preload("res://core/tool_tiers.gd")
const _Hotbar = preload("res://net/components/hotbar.gd")
const _Strings = preload("res://ui/strings.gd")
const BAG_SCENE: PackedScene = preload("res://props/yard_prop.tscn")
## The save section's own version (Campaign.SAVE_VERSION stays 1).
const SECTION_VERSION: int = 1
## How often the host looks over the kit for the summary (a poll, not tuning).
const SUMMARY_SECONDS: float = 0.5
## The colors a kit prop's box shows before its model (net_prop.gd color).
const RAKE_COLOR := Color(0.62, 0.45, 0.28)
const TOOL_COLOR := Color(0.8, 0.8, 0.8)

## Every peer: what the crew owns, anywhere: {kind: [tier, ...]} (best first).
var owned: Dictionary = {}
## Host: kit from a yard that went away, back by the door in the morning: [{kind, tier, fuel}].
var lost: Array = []
## Every peer: true once this peer has the host's summary.
var synced: bool = false

var _serial: int = 0
var _summary_wait: float = 0.0
## Host: the save section read at boot, put back once the world is up.
var _saved: Dictionary = {}
var _restored: bool = false


func _ready() -> void:
	add_to_group("kit")
	Net.player_joined.connect(_on_player_joined)
	if not Net.is_host():
		if multiplayer.multiplayer_peer != null:
			_rpc_request_state.rpc_id(1)
		return
	_saved = Campaign.save_section("kit")
	Campaign.add_save_hook(_save_section)
	var clock := get_tree().get_first_node_in_group("day_clock")
	if clock != null:
		clock.connect("day_started", _on_day_started)
	# Once Chefty, the store and the first yard are up (world._ready ends first).
	_restore.call_deferred()


func _exit_tree() -> void:
	Campaign.remove_save_hook(_save_section)


func _process(delta: float) -> void:
	if not Net.is_host() or not _restored:
		return
	_summary_wait += delta
	if _summary_wait < SUMMARY_SECONDS:
		return
	_summary_wait = 0.0
	var now := _summarize()
	if now != owned:
		owned = now
		_send_summary()


# ---------------------------------------------------------------- reading (every peer)

## The best tier of this kind the crew owns anywhere, or Catalog.TIER_NONE.
func best_tier(kind: String) -> int:
	var tiers: Array = _now().get(kind, [])
	return int(tiers[0]) if not tiers.is_empty() else Catalog.TIER_NONE


## How many of this kind the crew owns, anywhere.
func count_of(kind: String) -> int:
	return (_now().get(kind, []) as Array).size()


## The summary as this peer knows it: the host counts it fresh (a buy reads
## right away), a client has the host's last word.
func _now() -> Dictionary:
	return _summarize() if Net.is_host() and _restored and is_inside_tree() else owned


# ---------------------------------------------------------------- host

## Host: a player bought this (net/shops/shops.gd _apply). A pocket tool lands
## in their hands (drawn from a pocket, the hotbar's draw), or at their feet when
## their pockets or arms are full; a big one (the mower, the washer, the ladder)
## is waiting by the store's front door. A used one comes half full of gas, a
## new one full (Marty fills it). Returns the prop.
func host_deliver(peer_id: int, kind: String, tier: int) -> Node3D:
	if not Net.is_host() or not _KitRules.is_kit_kind(kind):
		return null
	var fuel := 50.0 if tier == Catalog.TIER_USED else 100.0
	var player := _player(peer_id)
	if _Hotbar.is_pocketable(kind) and player != null:
		var hotbar := get_tree().get_first_node_in_group("hotbar")
		var at := player.global_position + Vector3.UP * Constants.POCKET_FOLLOW_HEIGHT
		var prop := _make(kind, tier, fuel)
		var slot := _Hotbar.REFUSE
		if hotbar != null and _Hotbar.arms_item(get_tree(), peer_id) == null and _Hotbar.has_room(get_tree(), peer_id, kind):
			slot = int(hotbar.call("host_slot_for_pickup", peer_id, prop))
		if slot >= 0:
			# Straight into a pocket, then out into your hands: the draw.
			prop.set("pocket_slot", slot)
			prop.set("pocketed_by", peer_id)
			# Not solid from the start: it appears inside its owner.
			prop.call("_set_solid", false)
			_add(prop, at)
			hotbar.call("host_select_silently", peer_id, slot)
			hotbar.call("host_settle", peer_id)
			return prop
		# No room: it lands at your feet, in front of you.
		var ahead := -player.global_basis.z
		ahead.y = 0.0
		_add(prop, player.global_position + ahead.normalized() * 0.7 + Vector3.UP * 0.4)
		return prop
	var big := _make(kind, tier, fuel)
	_add(big, door_point(_door_index()))
	if multiplayer.multiplayer_peer == null:
		_rpc_thud(big.global_position)
	else:
		_rpc_thud.rpc(big.global_position)
	return big


## Host: make a kit prop at `at` (world space). For the bed's "take", the save's
## restore and dev kit.
func spawn_item(kind: String, tier: int, fuel: float, at: Transform3D) -> Node3D:
	if not Net.is_host():
		return null
	var prop := _make(kind, tier, fuel)
	_add(prop, at.origin)
	prop.global_transform = at
	return prop


## Host: the yard `lot` is going away (world._free_lot, a swap): every kit prop
## lying loose on it goes with it, to be found by the store's door in the
## morning. Pockets and Chefty's bed keep theirs.
func host_yard_freed(lot: Node3D) -> void:
	if not Net.is_host() or lot == null:
		return
	for node: Node in get_tree().get_nodes_in_group("props"):
		if not _KitRules.is_kit(node) or not bool(node.call("is_loose")):
			continue
		if not _at_yard(node as Node3D, lot):
			continue
		lost.append(_entry_of(node))
		node.queue_free()


## Host, dev and tests: one of every kit kind, a rake first (Campaign.dev_grant_all_tools).
func dev_add_all() -> void:
	var kinds: Array[String] = ["rake"]
	kinds.append_array(Catalog.TOOLS)
	_dev_add(kinds)


## Host: the door spot for the index-th thing waiting there, in the world.
func door_point(index: int) -> Vector3:
	var store := _store_zone()
	var local := Constants.KIT_DOOR_FIRST + Constants.KIT_DOOR_STEP * float(clampi(index, 0, Constants.KIT_DOOR_MAX - 1))
	if index >= Constants.KIT_DOOR_MAX:
		local += Vector3.UP * 0.3 * float(index - Constants.KIT_DOOR_MAX + 1)
	return store.to_global(local) if store != null else local


# ---------------------------------------------------------------- the morning

## Host: a new day. Everything the crew left out (lost with a yard, or lying
## loose anywhere but the store's lot) is by the front door, and one neighbor
## texts about it.
func _on_day_started(_day: int) -> void:
	if not Net.is_host() or not _restored:
		return
	var back: Array = lost.duplicate()
	lost.clear()
	for node: Node in get_tree().get_nodes_in_group("props"):
		if not _KitRules.is_kit(node) or not bool(node.call("is_loose")) or _at_store(node as Node3D):
			continue
		back.append(_entry_of(node))
		node.queue_free()
	if back.is_empty():
		return
	var names: Array = []
	for entry: Dictionary in back:
		_add(_make(str(entry["kind"]), int(entry["tier"]), float(entry["fuel"])), door_point(_door_index()))
		var named := _KitRules.sentence_name(str(entry["kind"]), int(entry["tier"]))
		if not names.has(named):
			names.append(named)
	var town := get_tree().get_first_node_in_group("town")
	if town != null:
		var pick := randi() % _Strings.KIT_FOUND_TEXTS.size()
		town.call("_text", str(_Strings.SHOP_UI["text_from_neighbor"]), "neighbor", _Strings.KIT_FOUND_TEXTS[pick] % _KitRules.sentence_list(names), -1)


# ---------------------------------------------------------------- save

## The "kit" save section: every item and where it is ("bed", "pockets",
## "store", "yard", "town", "lost"). Only "bed" matters to a load (the rest go
## by the door); the others are there for whoever reads a save.
func _save_section() -> Dictionary:
	var items: Array = []
	var bed := _tool_bed()
	if bed != null:
		for entry: Dictionary in bed.get("tools") as Array:
			items.append({"kind": str(entry["kind"]), "tier": int(entry["tier"]), "fuel": snappedf(float(entry["fuel"]), 0.1), "at": "bed"})
	for node: Node in get_tree().get_nodes_in_group("props"):
		if not _KitRules.is_kit(node):
			continue
		var row := _entry_of(node)
		row["at"] = _where(node as Node3D)
		items.append(row)
	for entry: Dictionary in lost:
		var row := entry.duplicate()
		row["at"] = "lost"
		items.append(row)
	return {"kit": {"version": SECTION_VERSION, "items": items}}


## Host, once the world is up: last session's kit back (or an old save's
## unlocks turned into kit), then the dev kit.
func _restore() -> void:
	if _restored or not is_inside_tree():
		return
	var items: Array = []
	if _saved.has("items") and typeof(_saved["items"]) == TYPE_ARRAY:
		items = _saved["items"]
	elif Campaign.save_section("players").size() > 0 or not Campaign.save_section("crew").is_empty():
		items = _migrate()
	var bed := _tool_bed()
	var to_bed: Array = []
	var to_door: Array = []
	for item: Variant in items:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = item
		var kind := str(row.get("kind", ""))
		if not _KitRules.is_kit_kind(kind):
			continue
		var entry := {"kind": kind, "tier": clampi(int(row.get("tier", Catalog.TIER_STOCK)), Catalog.TIER_USED, Catalog.TIER_MK3), "fuel": clampf(float(row.get("fuel", 100.0)), 0.0, 100.0)}
		if str(row.get("at", "")) == "bed" and bed != null:
			to_bed.append(entry)
		else:
			to_door.append(entry)
	if bed != null and not to_bed.is_empty():
		# Whatever doesn't fit (a save from a bigger bed) waits by the door.
		to_door.append_array(bed.call("restore", to_bed) as Array)
	for entry: Dictionary in to_door:
		_add(_make(str(entry["kind"]), int(entry["tier"]), float(entry["fuel"])), door_point(_door_index()))
	_restored = true
	_seed_dev()
	owned = _summarize()
	_send_summary()


## A save from before p2-kit: each player's tools (their best tier of each, from
## their unlocks) become tools by the door, and everyone gets a rake (the Tune-Up
## and The Leafinator become the Mk II and Mk III). The tool unlocks leave the
## players' lists, so this happens once.
func _migrate() -> Array:
	var out := migrate_players(Campaign.save_section("players"))
	Campaign.call("forget_tool_unlocks")
	if not out.is_empty():
		print("[Kit] an old save's tools are by Homie Depot's door now: %d things" % out.size())
	return out


## The kit an old save's players bring ({save key: {unlocks}}, the "players"
## section): a rake each (Mk II with the Tune-Up, Mk III with The Leafinator),
## and each player's best tier of every tool they had. [{kind, tier, fuel}].
static func migrate_players(players: Dictionary) -> Array:
	var out: Array = []
	for key: Variant in players:
		var record: Variant = players[key]
		if typeof(record) != TYPE_DICTIONARY:
			continue
		var unlocks: Array = (record as Dictionary).get("unlocks", [])
		var rake := Catalog.TIER_STOCK
		if unlocks.has("rake_tier_2"):
			rake = Catalog.TIER_MK3
		elif unlocks.has("rake_tier_1"):
			rake = Catalog.TIER_MK2
		out.append({"kind": "rake", "tier": rake, "fuel": 100.0})
		for tool: String in Catalog.TOOLS:
			for tier: int in [Catalog.TIER_MK3, Catalog.TIER_MK2, Catalog.TIER_STOCK, Catalog.TIER_USED]:
				if unlocks.has(Catalog.tool_item(tool, tier)):
					out.append({"kind": tool, "tier": tier, "fuel": 100.0})
					break
	return out


## Dev sessions: the kit a test or a try-out starts with. Never for a player's
## own session (all three are dev flags, net/command_line.gd).
##   --start-zone=lot: a rake lies where the yard's own rake used to (the tests
##     that work a yard find it there, as they always did), and with --all-tools
##     one of every tool laid out by the truck, as the job's tools used to be.
##   otherwise --all-tools: a rake and one of every tool in Chefty's bed.
##   --starter-kit=N: N rakes in Chefty's bed (N 0 skips the yard's rake too).
## Only what the crew is short of is made, so a dev save doesn't pile up kit.
func _seed_dev() -> void:
	var options := Net.dev_options()
	if not bool(options.call("is_dev_session")):
		return
	var all_tools := bool(options.get("all_tools"))
	var rakes := int(options.get("starter_kit"))
	var on_lot := str(options.get("start_zone")) == "lot"
	if on_lot and rakes < 0:
		rakes = 1
	if rakes < 0:
		rakes = 0
	var lot := _lot()
	if on_lot and lot != null:
		for index: int in maxi(rakes - _count_now("rake"), 0):
			var at := lot.global_transform * (Constants.KIT_DEV_RAKE_AT + Constants.KIT_DEV_RAKE_STEP * float(index))
			_add(_make("rake", Catalog.TIER_STOCK, 100.0), at)
		if all_tools:
			var index := 0
			for tool: String in Catalog.TOOLS:
				if _count_now(tool) == 0:
					# Rows of three by the truck (the old job tools' layout).
					_add(_make(tool, Catalog.TIER_STOCK, 100.0), lot.global_position + Vector3(-5.5 - float(index % 3) * 1.4, 0.6, 13.5 + float(index / 3) * 1.6))
				index += 1
		return
	var kinds: Array[String] = []
	for _index: int in maxi(rakes - _count_now("rake"), 0):
		kinds.append("rake")
	if all_tools:
		if not kinds.has("rake"):
			kinds.append("rake")
		kinds.append_array(Catalog.TOOLS)
	_dev_add(kinds)


## Host: these kinds, the ones the crew is short of, into Chefty's bed (by the
## door when the bed's full or there's no Chefty).
func _dev_add(kinds: Array[String]) -> void:
	var bed := _tool_bed()
	var counts: Dictionary = {}
	var wanted: Array = []
	for kind: String in kinds:
		counts[kind] = int(counts.get(kind, 0)) + 1
	for kind: String in counts:
		for _index: int in maxi(int(counts[kind]) - _count_now(kind), 0):
			wanted.append({"kind": kind, "tier": Catalog.TIER_STOCK, "fuel": 100.0})
	var spill: Array = wanted
	if bed != null:
		spill = bed.call("restore", wanted)
	for entry: Dictionary in spill:
		_add(_make(str(entry["kind"]), int(entry["tier"]), float(entry["fuel"])), door_point(_door_index()))


# ---------------------------------------------------------------- the summary

## Host: {kind: [tiers, best first]} for everything the crew owns.
func _summarize() -> Dictionary:
	var tiers: Dictionary = {}
	var add := func(kind: String, tier: int) -> void:
		if not tiers.has(kind):
			tiers[kind] = []
		(tiers[kind] as Array).append(tier)
	for node: Node in get_tree().get_nodes_in_group("props"):
		if _KitRules.is_kit(node):
			add.call(str(node.get("kind")), int(node.get("tier")))
	var bed := _tool_bed()
	if bed != null:
		for entry: Dictionary in bed.get("tools") as Array:
			add.call(str(entry["kind"]), int(entry["tier"]))
	for entry: Dictionary in lost:
		add.call(str(entry["kind"]), int(entry["tier"]))
	for kind: Variant in tiers:
		var list: Array = tiers[kind]
		list.sort()
		list.reverse()
	return tiers


## How many of a kind exist right now (host, before the summary catches up).
func _count_now(kind: String) -> int:
	return (_summarize().get(kind, []) as Array).size()


func _send_summary() -> void:
	if multiplayer.multiplayer_peer == null:
		_rpc_summary(owned)
		return
	_rpc_summary.rpc(owned)


func _on_player_joined(peer_id: int) -> void:
	if Net.is_host() and peer_id != Net.local_peer_id() and multiplayer.multiplayer_peer != null:
		_rpc_summary.rpc_id(peer_id, owned)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_state() -> void:
	if Net.is_host():
		_rpc_summary.rpc_id(multiplayer.get_remote_sender_id(), owned)


@rpc("authority", "call_local", "reliable")
func _rpc_summary(summary: Dictionary) -> void:
	owned = summary.duplicate(true)
	synced = true
	changed.emit()
	# The shelves and the shop window read the kit (what the crew has).
	Campaign.unlocks_changed.emit()


## Every peer: a big tool just rolled out by the front door.
@rpc("authority", "call_local", "reliable")
func _rpc_thud(at: Vector3) -> void:
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play_at", "thud", at, Constants.JUNK_LAND_DB)


# ---------------------------------------------------------------- helpers

func _make(kind: String, tier: int, fuel: float) -> RigidBody3D:
	var prop := BAG_SCENE.instantiate() as RigidBody3D
	_serial += 1
	var props := _props_root()
	while props != null and props.has_node("Kit%d" % _serial):
		_serial += 1
	prop.name = "Kit%d" % _serial
	prop.set("kind", kind)
	prop.set("tier", tier)
	prop.set("fuel", fuel)
	prop.set("label", _ToolTiers.tool_name(kind, tier) if kind != "rake" else _rake_label(tier))
	prop.set("color", RAKE_COLOR if kind == "rake" else TOOL_COLOR)
	return prop


func _rake_label(tier: int) -> String:
	if tier == Catalog.TIER_STOCK:
		return _Strings.item_name("rake")
	return _Strings.shop_item_name(Catalog.tool_item("rake", tier))


func _add(prop: Node3D, at: Vector3) -> void:
	var props := _props_root()
	if props == null:
		prop.free()
		return
	props.add_child(prop, true)
	prop.global_position = at


func _entry_of(node: Node) -> Dictionary:
	return {"kind": str(node.get("kind")), "tier": int(node.get("tier")), "fuel": snappedf(float(node.get("fuel")), 0.1)}


## Where a kit prop is, for the save: in someone's hands or pockets, at the
## store, on the job's yard, or out in town.
func _where(node: Node3D) -> String:
	if int(node.get("held_by")) != 0 or int(node.get("pocketed_by")) != 0:
		return "pockets"
	if _at_store(node):
		return "store"
	var lot := _lot()
	if lot != null and _at_yard(node, lot):
		return "yard"
	return "town"


## Whether a prop lies at Homie Depot: its zone in the legacy world, its lot in town.
func _at_store(node: Node3D) -> bool:
	var store := _store_zone()
	if store == null:
		return false
	var local := store.to_local(node.global_position)
	if TownMap.enabled(get_tree()):
		return Constants.STORE_AREA.has_point(Vector2(local.x, local.z))
	var rect: Rect2 = Constants.PAD_RECTS.get("StoreZone", Rect2(-20.0, -20.0, 40.0, 40.0))
	return rect.grow(Constants.KIT_STORE_SLACK).has_point(Vector2(local.x, local.z)) and absf(local.y) < 50.0


## Whether a prop lies on (or by) this yard: within PROP_LEASH_METERS of its site.
func _at_yard(node: Node3D, lot: Node3D) -> bool:
	var center := (lot.get_parent() as Node3D).global_position if lot.get_parent() is Node3D else lot.global_position
	return Vector2(node.global_position.x - center.x, node.global_position.z - center.z).length() <= Constants.PROP_LEASH_METERS


## The next free spot by the door: one past the kit already waiting there.
func _door_index() -> int:
	var store := _store_zone()
	if store == null:
		return 0
	var used := 0
	for node: Node in get_tree().get_nodes_in_group("props"):
		if not _KitRules.is_kit(node) or not bool(node.call("is_loose")):
			continue
		var local := store.to_local((node as Node3D).global_position)
		var rect: Rect2 = Constants.STORE_LAYOUT["kit_door"]["rect"]
		if rect.grow(0.5).has_point(Vector2(local.x, local.z)):
			used += 1
	return used


func _tool_bed() -> Node:
	var chefty := get_tree().get_first_node_in_group("chefty")
	return chefty.get_node_or_null("Body/ToolBed") if chefty != null else null


func _store_zone() -> Node3D:
	var world := get_tree().get_first_node_in_group("world")
	return world.get_node_or_null("StoreZone") as Node3D if world != null else null


func _lot() -> Node3D:
	var world := get_tree().get_first_node_in_group("world")
	var slot := world.get_node_or_null("LotZone/LotSlot") if world != null else null
	if slot == null or slot.get_child_count() == 0:
		return null
	return slot.get_child(0) as Node3D


func _props_root() -> Node:
	return get_tree().get_first_node_in_group("runtime_props")


func _player(peer_id: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node as Node3D
	return null
