extends Node3D

## Authority: local, cosmetic. A shop's physical stock (docs/GAME.md "Shops",
## physical stock; gap-specs shops chunk 4): what's on sale stands on the
## shelves as itself, with a price tag. Every peer builds its own from state it
## already has (Shops' replicated stock, Campaign's unlocks), so it costs no
## traffic, like the shopkeepers.
##   A tool shows the next one you can buy (a stock blower, then the Mk II with
##   its chrome stripe, then the Mk III in black and gold) and its price, or
##   OWNED once you have the Mk III.
##   A supply shows one box per unit left today, up to Constants.SHELF_MAX_UNITS,
##   so the shelf visibly empties, and SOLD OUT when it's gone.
##   Anything your crew's rank can't buy yet sits under a blue tarp with "Rank: ...".
## Walk up to a slot and it prompts "Look at ..."; E opens the shop's catalog on
## that item. A shelving unit's levels share one spot in front of it, so tilt
## your head to pick the level (the one your pitch points at most nearly). The garden center's shelves are levels/dressing/store_dressing.gd's;
## the slots are SHELF_SLOTS below unless the builder passes its own.
## Rusty's used-tool pallets (levels/dressing/shop_sites.gd, shops chunk 5) are
## a used_rack: one slot per tool he can have out, each showing that day's
## used tool (Shops.used_today) in its rust and tape, or nothing once it's sold.

const _YardModels = preload("res://props/yard_models.gd")
const _ShopModels = preload("res://props/shop_models.gd")
const _Strings = preload("res://ui/strings.gd")
const _Ranks = preload("res://core/ranks.gd")
## The garden center's slots, in the store zone's space: three shelving units
## (x 10, 13 and 16, levels 0.13, 0.93 and 1.73 m up), two slots a level, top
## level first. Each is {at: the slot's floor center, size: Vector3(depth across
## the shelf, height, width along it), face: the way customers see it (the yaw
## a -Z model turns to face them)}. Catalog order fills them.
const SHELF_SLOTS: Array[Dictionary] = [
	{"at": Vector3(10.0, 1.73, -1.25 - 13.0), "size": Vector3(0.9, 0.6, 2.3), "face": PI * 0.5},
	{"at": Vector3(10.0, 1.73, 1.25 - 13.0), "size": Vector3(0.9, 0.6, 2.3), "face": PI * 0.5},
	{"at": Vector3(10.0, 0.93, -1.25 - 13.0), "size": Vector3(0.9, 0.7, 2.3), "face": PI * 0.5},
	{"at": Vector3(10.0, 0.93, 1.25 - 13.0), "size": Vector3(0.9, 0.7, 2.3), "face": PI * 0.5},
	{"at": Vector3(10.0, 0.13, -1.25 - 13.0), "size": Vector3(0.9, 0.7, 2.3), "face": PI * 0.5},
	{"at": Vector3(10.0, 0.13, 1.25 - 13.0), "size": Vector3(0.9, 0.7, 2.3), "face": PI * 0.5},
	{"at": Vector3(13.0, 1.73, -1.25 - 13.0), "size": Vector3(0.9, 0.6, 2.3), "face": PI * 0.5},
	{"at": Vector3(13.0, 1.73, 1.25 - 13.0), "size": Vector3(0.9, 0.6, 2.3), "face": PI * 0.5},
	{"at": Vector3(13.0, 0.93, -1.25 - 13.0), "size": Vector3(0.9, 0.7, 2.3), "face": PI * 0.5},
	{"at": Vector3(13.0, 0.93, 1.25 - 13.0), "size": Vector3(0.9, 0.7, 2.3), "face": PI * 0.5},
	{"at": Vector3(13.0, 0.13, -1.25 - 13.0), "size": Vector3(0.9, 0.7, 2.3), "face": PI * 0.5},
	{"at": Vector3(13.0, 0.13, 1.25 - 13.0), "size": Vector3(0.9, 0.7, 2.3), "face": PI * 0.5},
	{"at": Vector3(16.0, 1.73, -1.25 - 13.0), "size": Vector3(0.9, 0.6, 2.3), "face": PI * 0.5},
	{"at": Vector3(16.0, 1.73, 1.25 - 13.0), "size": Vector3(0.9, 0.6, 2.3), "face": PI * 0.5},
	{"at": Vector3(16.0, 0.93, -1.25 - 13.0), "size": Vector3(0.9, 0.7, 2.3), "face": PI * 0.5},
	{"at": Vector3(16.0, 0.93, 1.25 - 13.0), "size": Vector3(0.9, 0.7, 2.3), "face": PI * 0.5},
	{"at": Vector3(16.0, 0.13, -1.25 - 13.0), "size": Vector3(0.9, 0.7, 2.3), "face": PI * 0.5},
	{"at": Vector3(16.0, 0.13, 1.25 - 13.0), "size": Vector3(0.9, 0.7, 2.3), "face": PI * 0.5},
]
## The catalog tabs that stand on Homie Depot's garden shelves (workwear goes on
## the hat rack and the truck's paint on the swatch counter, shops chunk 7).
const SHELF_TABS: Array[String] = ["tools", "upgrades", "supplies"]
## How much of a slot a model may fill.
const FILL: float = 0.85
const TAG_PIXEL: float = 0.0035
const TAG_PRICE := Color(1.0, 0.97, 0.9)
const TAG_EDGE := Color(0.93, 0.47, 0.13)
const TAG_OWNED := Color(0.35, 0.75, 0.4)
const TAG_SOLD_OUT := Color(0.85, 0.2, 0.15)
const TAG_LOCKED := Color(0.4, 0.42, 0.46)

## Which shop's stock this is.
var shop_id: String = "homie_depot"
## The catalog tabs it shows, and the slots they fill (set before adding it).
var tabs: Array[String] = SHELF_TABS.duplicate()
var slots: Array[Dictionary] = SHELF_SLOTS.duplicate(true)
## Rusty's rack: the slots show today's used tools, in order, whatever they are.
var used_rack: bool = false
## The slot ids a used rack fills: "used_slot_<n>".
const USED_SLOT: String = "used_slot_"

## One per slot used: {item: the slot's catalog id (the tool's, for a tool), tab,
## slot index, node: the slot's Node3D, state: the last state drawn}.
var _entries: Array[Dictionary] = []


func _ready() -> void:
	add_to_group("prompt_sources")
	# Rusty's rack is its own group: "shelf_stock" is Homie Depot's garden shelves.
	add_to_group("rusty_rack" if used_rack else "shelf_stock")
	var index := 0
	for tab: String in tabs:
		for id: String in _slot_items(tab):
			if index >= slots.size():
				push_warning("[ShelfStock] %s has more items than slots" % shop_id)
				break
			var holder := Node3D.new()
			holder.name = "Slot_" + id
			add_child(holder)
			_entries.append({"item": id, "tab": tab, "slot": index, "node": holder, "state": {}})
			index += 1
	Campaign.unlocks_changed.connect(refresh)
	Campaign.rank_changed.connect(refresh)
	var shops := _shops()
	if shops != null:
		shops.connect("changed", refresh)
	refresh()


## The ids one slot each: every tool once (its tiers are the same slot), then
## the tab's items in catalog order.
func _slot_items(tab: String) -> PackedStringArray:
	if used_rack:
		var out := PackedStringArray()
		for index: int in slots.size():
			out.append(USED_SLOT + str(index))
		return out
	if tab == "tools":
		return PackedStringArray(Catalog.TOOLS)
	return Catalog.items_for(shop_id, tab)


## Redraws the slots whose state changed (cheap to call often: Shops sends a
## snapshot whenever a bag is used).
func refresh() -> void:
	for entry: Dictionary in _entries:
		var state := slot_state(str(entry["item"]))
		if state == entry["state"]:
			continue
		entry["state"] = state
		_draw_slot(entry, state)


## What a slot shows for the local player: {item: the catalog id on show (the
## next tier for a tool), tier, units (boxes on the shelf), tag (its price tag's
## text), look (price | owned | sold_out | locked | season)}.
func slot_state(item: String) -> Dictionary:
	var me := Net.local_peer_id()
	var shown := item
	var tier := Catalog.TIER_STOCK
	if item.begins_with(USED_SLOT):
		# Rusty's rack: the day's n-th used tool, or an empty pallet (one sold
		# today is "" in its place, so the others never move pallets).
		var shops_node := _shops()
		var rack: Array = shops_node.get("used_today") if shops_node != null else []
		var index := int(item.trim_prefix(USED_SLOT))
		if index >= rack.size() or str(rack[index]) == "":
			return {"item": "", "tier": Catalog.TIER_USED, "units": 0, "tag": "", "look": "empty"}
		shown = Catalog.tool_item(str(rack[index]), Catalog.TIER_USED)
		tier = Catalog.TIER_USED
	elif Catalog.TOOLS.has(item):
		var owned := Campaign.tool_tier(me, item)
		tier = Catalog.TIER_STOCK if owned < Catalog.TIER_STOCK and owned != Catalog.TIER_USED else mini(maxi(owned + 1, Catalog.TIER_MK2), Catalog.TIER_MK3)
		shown = Catalog.tool_item(item, tier)
		if owned >= Catalog.TIER_MK3:
			return {"item": shown, "tier": tier, "units": 1, "tag": str(_Strings.SHOP_UI["shop_owned_tag"]), "look": "owned"}
	var entry := Catalog.item(shown)
	var shops := _shops()
	var units := 1
	if str(entry.get("kind", "")) == "consumable":
		var left := int(shops.call("stock_left", shop_id, shown)) if shops != null else Constants.SHELF_MAX_UNITS
		units = Constants.SHELF_MAX_UNITS if left < 0 else mini(left, Constants.SHELF_MAX_UNITS)
	if not Campaign.is_for_sale(StringName(shown)):
		var rank := _Ranks.title(_Ranks.tier_of(Catalog.gate_of(shown)))
		return {"item": shown, "tier": tier, "units": units, "tag": str(_Strings.SHOP_UI["shop_rank_tag"]) % rank, "look": "locked"}
	if shops != null and bool(shops.call("owns", me, shown)):
		return {"item": shown, "tier": tier, "units": units, "tag": str(_Strings.SHOP_UI["shop_owned_tag"]), "look": "owned"}
	var clock := get_tree().get_first_node_in_group("day_clock") if is_inside_tree() else null
	if clock != null and not Catalog.is_in_season(shown, int(clock.call("season"))):
		return {"item": shown, "tier": tier, "units": 0, "tag": str(_Strings.SHOP_UI["shop_out_of_season"]), "look": "season"}
	if units <= 0:
		return {"item": shown, "tier": tier, "units": 0, "tag": str(_Strings.SHOP_UI["shop_sold_out"]), "look": "sold_out"}
	return {"item": shown, "tier": tier, "units": units, "tag": str(_Strings.SHOP_UI["shop_price_tag"]) % Catalog.price(shown), "look": "price"}


## {catalog id: boxes on the shelf} for every slot: the same on every peer
## (it's the replicated stock), so the probe can compare a client's shelves.
func units_by_item() -> Dictionary:
	var out := {}
	for entry: Dictionary in _entries:
		out[str(entry["item"])] = int((entry["state"] as Dictionary).get("units", 0))
	return out


## The slot index an item stands in (a tool's tiers share its tool's), or -1.
func slot_of(item: String) -> int:
	var tool := str(Catalog.item(item).get("tool", ""))
	for entry: Dictionary in _entries:
		if str((entry["state"] as Dictionary).get("item", "")) == item and str(entry["item"]).begins_with(USED_SLOT):
			return int(entry["slot"])
		if str(entry["item"]) == item or (tool != "" and str(entry["item"]) == tool):
			return int(entry["slot"])
	return -1


## The point in front of a slot a customer stands at, in world space.
func slot_front(index: int) -> Vector3:
	var slot: Dictionary = slots[index]
	var size: Vector3 = slot["size"]
	var out := _facing(float(slot["face"]))
	return to_global((slot["at"] as Vector3) + out * (size.x * 0.5 + 0.4))


## "Look at ..." while the local player stands by a slot.
func prompt() -> Dictionary:
	var entry := _nearest_entry()
	if entry.is_empty():
		return {}
	var state: Dictionary = entry["state"]
	var name_text := _Strings.shop_item_name(str(state.get("item", entry["item"])))
	var slot: Dictionary = slots[int(entry["slot"])]
	return {"text": str(_Strings.SHOP_UI["prompt_look_at"]) % name_text, "at": to_global((slot["at"] as Vector3) + Vector3(0.0, (slot["size"] as Vector3).y + 0.35, 0.0))}


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	var entry := _nearest_entry()
	if entry.is_empty():
		return
	var ui := get_tree().get_first_node_in_group("game_ui")
	if ui == null or bool(ui.call("any_window_open")):
		return
	ui.call("open_shop", shop_id, str(entry["tab"]), str((entry["state"] as Dictionary).get("item", entry["item"])))
	get_viewport().set_input_as_handled()


## The slot the local player is looking at: the nearest stack of slots on the
## ground (a shelving unit's levels share one spot in front of it), then the
## level in that stack the head's pitch points at most nearly.
func _nearest_entry() -> Dictionary:
	var local := _local_player()
	if local == null:
		return {}
	var nearest := Constants.SHELF_LOOK_REACH
	var distances: Array[float] = []
	for entry: Dictionary in _entries:
		if str((entry["state"] as Dictionary).get("look", "")) == "empty":
			distances.append(INF)
			continue
		var front := slot_front(int(entry["slot"]))
		var distance := Vector2(front.x - local.global_position.x, front.z - local.global_position.z).length()
		distances.append(distance)
		nearest = minf(nearest, distance)
	var best: Dictionary = {}
	var best_miss := INF
	var pitch := float(local.get("head_pitch")) if "head_pitch" in local else 0.0
	for index: int in _entries.size():
		if distances[index] >= Constants.SHELF_LOOK_REACH or distances[index] > nearest + Constants.SHELF_STACK_TOLERANCE:
			continue
		var miss := absf(pitch_to(int(_entries[index]["slot"])) - pitch)
		if miss < best_miss:
			best = _entries[index]
			best_miss = miss
	return best


## The head pitch (radians, up is positive, as Player.head_pitch) at which the
## local player looks straight at a slot's middle.
func pitch_to(index: int) -> float:
	var local := _local_player()
	if local == null:
		return 0.0
	var slot: Dictionary = slots[index]
	var middle := to_global((slot["at"] as Vector3) + Vector3(0.0, (slot["size"] as Vector3).y * 0.5, 0.0))
	var head := local.get_node_or_null("%Head") as Node3D
	var eye := head.global_position if head != null else local.global_position + Vector3.UP * Constants.SHELF_EYE_HEIGHT
	var across := Vector2(middle.x - eye.x, middle.z - eye.z).length()
	return atan2(middle.y - eye.y, maxf(across, 0.01))


# ---------------------------------------------------------------- drawing

func _draw_slot(entry: Dictionary, state: Dictionary) -> void:
	var holder: Node3D = entry["node"]
	for child: Node in holder.get_children():
		child.queue_free()
	var slot: Dictionary = slots[int(entry["slot"])]
	var size: Vector3 = slot["size"]
	var face := float(slot["face"])
	holder.position = slot["at"]
	holder.rotation.y = face - PI * 0.5
	# In the holder's space the customer is at -X and the shelf runs along Z.
	var look := str(state["look"])
	if look == "empty":
		# An empty pallet on Rusty's rack: nothing on it, no tag.
		return
	if look == "locked":
		var tarp := _ShopModels.node("tarp")
		tarp.scale = Vector3(size.x * FILL, size.y * 0.7, size.z * 0.55)
		holder.add_child(tarp)
	else:
		var item := str(state["item"])
		var units := int(state["units"])
		if str(Catalog.item(item).get("kind", "")) == "consumable":
			_draw_units(holder, item, units, size)
		elif units > 0:
			_draw_one(holder, item, int(state["tier"]), size)
	var tag := Label3D.new()
	tag.name = "Tag"
	tag.text = str(state["tag"])
	tag.font_size = 40
	tag.pixel_size = TAG_PIXEL
	tag.outline_size = 12
	tag.modulate = TAG_PRICE
	tag.outline_modulate = {"owned": TAG_OWNED, "sold_out": TAG_SOLD_OUT, "locked": TAG_LOCKED, "season": TAG_LOCKED}.get(look, TAG_EDGE)
	# No wider than its slot (the lobby's endcaps are narrow): a long tag wraps.
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag.width = size.z / TAG_PIXEL
	# On the shelf's front lip, facing the aisle.
	tag.position = Vector3(-size.x * 0.5 - 0.07, -0.04, 0.0)
	tag.rotation.y = -PI * 0.5
	holder.add_child(tag)


## One model, scaled to fit the slot and turned to face the aisle (long things
## lie along the shelf).
func _draw_one(holder: Node3D, item: String, tier: int, size: Vector3) -> void:
	var view := _model(item, tier)
	if view == null:
		return
	var box := view.get_aabb()
	var along := box.size.z > box.size.x * 1.3
	# Facing the aisle (-X here) turns a -Z model a quarter turn; a long one lies along Z.
	view.rotation.y = 0.0 if along else PI * 0.5
	var across := box.size.x if along else box.size.z
	var lengthwise := box.size.z if along else box.size.x
	var fit := minf(minf(size.x * FILL / maxf(across, 0.01), size.z * FILL / maxf(lengthwise, 0.01)), size.y * FILL / maxf(box.size.y, 0.01))
	fit = minf(fit, 1.0)
	view.scale = Vector3.ONE * fit
	# Sit it on the shelf, centered.
	var center := box.get_center()
	var offset := Vector3(center.x, 0.0, center.z)
	if not along:
		offset = Vector3(center.z, 0.0, -center.x)
	view.position = Vector3(-offset.x * fit, -box.position.y * fit + 0.005, -offset.z * fit)
	holder.add_child(view)


## One box per unit left, in two rows along the shelf: the front row fills
## first, so the shelf empties from the back.
func _draw_units(holder: Node3D, item: String, units: int, size: Vector3) -> void:
	if units <= 0:
		return
	var per_row := maxi(1, int(ceil(float(Constants.SHELF_MAX_UNITS) / 2.0)))
	var cell := Vector2(size.x * FILL / 2.0, size.z * FILL / float(per_row))
	for index: int in units:
		var view := _model(item, Catalog.TIER_STOCK)
		if view == null:
			return
		var box := view.get_aabb()
		# Turned to face the aisle, its depth runs across the shelf (x here).
		var fit := minf(minf(cell.x * 0.9 / maxf(box.size.z, 0.01), cell.y * 0.9 / maxf(box.size.x, 0.01)), size.y * FILL / maxf(box.size.y, 0.01))
		fit = minf(fit, 1.0)
		view.scale = Vector3.ONE * fit
		view.rotation.y = PI * 0.5
		var row := index / per_row
		var column := index % per_row
		var in_row := mini(units - row * per_row, per_row)
		view.position = Vector3(
			(-0.5 if row == 0 else 0.5) * cell.x,
			-box.position.y * fit + 0.005,
			(float(column) - float(in_row - 1) * 0.5) * cell.y)
		holder.add_child(view)


## The mesh for a catalog item: its yard model (tools at their tier) or one of
## the shop models.
func _model(item: String, tier: int) -> MeshInstance3D:
	var model := str(Catalog.item(item).get("model", ""))
	if model == "":
		return null
	if _ShopModels.has(model):
		return _ShopModels.node(model)
	if model == "rake" or model == "wheelbarrow" or Catalog.TOOLS.has(model):
		return _YardModels.node(model, Color(0.95, 0.5, 0.15) if model == "wheelbarrow" else Color.WHITE, Vector3.ONE, {}, tier)
	return null


func _facing(face: float) -> Vector3:
	# A -Z model turned by face looks along this.
	return Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, face)


func _shops() -> Node:
	return get_tree().get_first_node_in_group("shops") if is_inside_tree() else null


func _local_player() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as Node3D
	return null
