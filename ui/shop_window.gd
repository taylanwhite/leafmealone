extends PanelContainer

## Authority: local. A shop's catalog window (docs/FEEL.md, "How characters deal
## with shops"; docs/GAME.md "Shops"; gap-specs shops chunk 4): the shop's name
## and brand, what its keeper just said, a tab per Catalog.SHOPS tab, and a
## scrolling grid of cards from core/catalog.gd, each with its picture
## (ui/icons.gd, or a color swatch until the catalog's icons are drawn), name,
## blurb, price and what you can do about it:
##   Tools     one card per tool with tier pips (●●○) and the next buy:
##             Buy $110, then Mk II $385, then Mk III $1100
##   Supplies  "%d left today", what the crew has, and x1 / x5 buttons
##   Workwear, Oddities  Buy, or Wear once owned (the closet comes with shops chunk 7)
##   Truck     Buy, or Put it on Chefty once the crew owns it
## A closed shop shows its shutter (CLOSED, Opens 7 AM) instead of the cards.
## Every button asks the host (Shops.request_buy); the answer comes back as
## Shops.result, shown as a toast ("Sold out", "Not enough cash", "Bought: ..."),
## and a confirmed buy emits `bought` so the shop's keeper reacts
## (ui/ui_root.gd). The register's ka-ching is audio/cue_hooks.gd's, on the same
## result; button clicks only click.

signal bought(item_id: StringName)

const _Strings = preload("res://ui/strings.gd")
const _Ranks = preload("res://core/ranks.gd")
const _Icons = preload("res://ui/icons.gd")
const _CartoonBody = preload("res://player/cartoon_body.gd")
const PAPER := Color(0.97, 0.93, 0.84)
const INK := Color(0.17, 0.14, 0.11)
const ORANGE := Color(0.93, 0.47, 0.13)
const CARD := Color(1.0, 0.98, 0.93)
const FOCUS := Color(0.2, 0.52, 0.85)
const SHUTTER := Color(0.36, 0.37, 0.4)
const GOOD := Color(0.25, 0.55, 0.3)
const BAD := Color(0.75, 0.2, 0.15)
const CARD_WIDTH: float = 196.0
const COLUMNS: int = 4
const GAP: int = 10
const SCROLL_HEIGHT: float = 330.0
const ICON_PX: float = 64.0
const BRAND_PX: float = 44.0
## How often an open window looks at the clock, so it shutters at closing time.
const CLOCK_CHECK_SECONDS: float = 0.5
## Card swatch colors, until the catalog's icons are drawn (icons:catalog).
const TOOL_COLORS: Dictionary = {
	"leaf_blower": Color(0.95, 0.55, 0.15), "lawn_mower": Color(0.2, 0.55, 0.3), "ladder": Color(0.75, 0.75, 0.72),
	"hose": Color(0.25, 0.6, 0.35), "pressure_washer": Color(0.95, 0.8, 0.2), "hedge_trimmer": Color(0.85, 0.25, 0.2),
	"paint_roller": Color(0.35, 0.55, 0.85),
}
const KIND_COLORS: Dictionary = {
	"upgrade": Color(0.85, 0.55, 0.25), "consumable": Color(0.72, 0.55, 0.34), "snack": Color(0.95, 0.75, 0.3),
	"cosmetic": Color(0.55, 0.45, 0.75), "truck_cosmetic": Color(0.75, 0.22, 0.15),
}
const SUPPLY_COLORS: Dictionary = {
	"lawn_bags": Color(0.72, 0.55, 0.34), "big_bags": Color(0.2, 0.2, 0.22), "gas": Color(0.84, 0.14, 0.1),
	"fertilizer": Color(0.36, 0.6, 0.3), "grass_seed": Color(0.92, 0.82, 0.42), "rock_salt": Color(0.75, 0.82, 0.92),
}
const HIVIS := Color(0.85, 1.0, 0.2)

## The shop and tab on show, and the item it was opened on ("" for none).
var shop_id: String = "homie_depot"
var tab: String = ""
var focus_item: String = ""

var _brand_slot: HBoxContainer
var _title: Label
var _credits: Label
var _subtitle: Label
var _keeper_line: Label
var _tabs: HBoxContainer
var _info: Label
var _scroll: ScrollContainer
var _cards: GridContainer
var _empty: Label
var _shutter: PanelContainer
var _shutter_text: Label
var _toast: Label
var _toast_left: float = 0.0
var _clock_wait: float = 0.0
var _was_open: bool = true
var _shown_line: String = ""
var _focus_card: Control


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", _box(PAPER, 18, ORANGE, 6))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	column.add_child(header)
	_brand_slot = HBoxContainer.new()
	header.add_child(_brand_slot)
	_title = _text("", 32, ORANGE)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_title)
	_credits = _text("", 20, INK)
	var cash := _Icons.row("cash", _credits, 22.0)
	cash.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(cash)
	_subtitle = _text("", 15, INK.lightened(0.3))
	column.add_child(_subtitle)
	_keeper_line = _text("", 15, INK.lightened(0.15))
	_keeper_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_keeper_line.custom_minimum_size = Vector2(_grid_width(), 0.0)
	column.add_child(_keeper_line)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	column.add_child(_tabs)
	_info = _text("", 15, INK)
	column.add_child(_info)
	var body := Control.new()
	body.custom_minimum_size = Vector2(_grid_width() + 14.0, SCROLL_HEIGHT)
	column.add_child(body)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.add_child(_scroll)
	_cards = GridContainer.new()
	_cards.columns = COLUMNS
	_cards.add_theme_constant_override("h_separation", GAP)
	_cards.add_theme_constant_override("v_separation", GAP)
	_scroll.add_child(_cards)
	_empty = _text("", 18, INK.lightened(0.35))
	_empty.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	body.add_child(_empty)
	# The shutter comes down over the cards while the shop is closed.
	_shutter = PanelContainer.new()
	_shutter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shutter.add_theme_stylebox_override("panel", _shutter_box())
	body.add_child(_shutter)
	_shutter_text = _text("", 30, Color(0.97, 0.95, 0.9))
	_shutter_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shutter_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_shutter_text.add_theme_constant_override("outline_size", 8)
	_shutter_text.add_theme_color_override("font_outline_color", INK)
	_shutter.add_child(_shutter_text)
	var footer := HBoxContainer.new()
	column.add_child(footer)
	_toast = _text("", 17, INK)
	_toast.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toast.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer.add_child(_toast)
	var close := _button(_Strings.UI["shop_close"], INK)
	close.pressed.connect(close_window)
	footer.add_child(close)
	Campaign.credits_changed.connect(func(_peer_id: int, _amount: int) -> void: _refresh_if_open())
	Campaign.unlocks_changed.connect(_refresh_if_open)


## Opens a shop's window, on a tab (its first by default), with a card picked
## out when focus is a catalog id (a tool tier picks out its tool's card).
func open_shop(shop: String = "homie_depot", on_tab: String = "", focus: String = "") -> void:
	if not Catalog.SHOPS.has(shop):
		shop = "homie_depot"
	shop_id = shop
	focus_item = focus
	var tabs: Array = (Catalog.SHOPS[shop_id] as Dictionary)["tabs"]
	if on_tab == "" and focus != "":
		on_tab = str(Catalog.item(focus).get("tab", ""))
	tab = on_tab if tabs.has(on_tab) else str(tabs[0])
	open()


## Shows the window as it's set up (open_shop picks the shop). The catalog look
## is shared: ui/job_board_window.gd extends this script, builds its own
## content, and opens through here too, so the shop's own pieces are only
## touched when they were built (_scroll).
func open() -> void:
	if _scroll != null:
		# The world (and its Shops node) is made after the UI, so this hooks up on open.
		var shops := _shops()
		if shops != null:
			if not shops.is_connected("result", _on_shop_result):
				shops.connect("result", _on_shop_result)
			if not shops.is_connected("changed", _refresh_if_open):
				shops.connect("changed", _refresh_if_open)
		_toast_left = 0.0
		_toast.text = ""
		_shown_line = ""
		_build_header()
		_build_tabs()
	_refresh()
	visible = true
	# Centered by anchors, growing both ways from the middle of the screen, so its
	# size can settle after the cards are built without knocking it off screen.
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _scroll != null:
		_scroll_to_focus.call_deferred()


func close_window() -> void:
	visible = false
	var ui := get_parent()
	if ui != null and ui.has_method("recapture_mouse"):
		ui.call("recapture_mouse")
	elif Net.current_state() == Net.State.IN_SESSION:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Switches the open window to another of its shop's tabs.
func show_tab(next_tab: String) -> void:
	tab = next_tab
	focus_item = ""
	for button: Node in _tabs.get_children():
		(button as Button).set_pressed_no_signal(str(button.get_meta("tab")) == tab)
	_scroll.scroll_vertical = 0
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		close_window()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible or _scroll == null:
		return
	if _toast_left > 0.0:
		_toast_left = maxf(0.0, _toast_left - delta)
		_toast.modulate.a = clampf(_toast_left / 0.4, 0.0, 1.0)
	_clock_wait += delta
	if _clock_wait >= CLOCK_CHECK_SECONDS:
		_clock_wait = 0.0
		if _is_open() != _was_open:
			_refresh()
		_update_keeper_line()


# ---------------------------------------------------------------- what's on the tab

## The cards on the tab on show, in order: one per tool on the tools tab (its
## next tier), else one per catalog item. Each is {id, tool?, owned_tier?, maxed?}.
func _items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if tab == "tools":
		var me := Net.local_peer_id()
		for tool: String in Catalog.TOOLS:
			var owned := Campaign.tool_tier(me, tool)
			var maxed := owned >= Catalog.TIER_MK3
			out.append({"id": Catalog.tool_item(tool, next_tier(owned)), "tool": tool, "owned_tier": owned, "maxed": maxed})
		return out
	if tab == "sell":
		# Rusty's scale (shops chunk 5).
		return out
	for id: String in Catalog.items_for(shop_id, tab):
		out.append({"id": id})
	return out


## The tier a tool card offers next, from the tier you own (-1 none, 0 used,
## 1 stock, 2 Mk II, 3 Mk III): a stock one, then Mk II (a used one skips to
## it), then Mk III, which stays on the card once owned.
static func next_tier(owned: int) -> int:
	if owned < Catalog.TIER_USED:
		return Catalog.TIER_STOCK
	return mini(maxi(owned + 1, Catalog.TIER_MK2), Catalog.TIER_MK3)


# ---------------------------------------------------------------- building

func _build_header() -> void:
	for child: Node in _brand_slot.get_children():
		_brand_slot.remove_child(child)
		child.queue_free()
	_brand_slot.add_child(_Icons.rect("brand_" + shop_id, BRAND_PX))
	_title.text = str(_Strings.SHOP_UI.get("shop_title_" + shop_id, shop_id))
	var hours: Vector2 = Constants.SHOP_HOURS.get(shop_id, Vector2.ZERO)
	var shops_script := preload("res://net/shops/shops.gd")
	var hours_text := str(_Strings.SHOP_UI["shop_hours_always"]) if hours.y - hours.x >= 24.0 \
		else str(_Strings.SHOP_UI["shop_hours"]) % [shops_script.hour_text(hours.x), shops_script.hour_text(hours.y)]
	_subtitle.text = "%s  ·  %s" % [str(_Strings.SHOP_UI.get("shop_subtitle_" + shop_id, "")), hours_text]
	_keeper_line.text = ""
	_keeper_line.visible = false
	_update_keeper_line()


func _build_tabs() -> void:
	for child: Node in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	var group := ButtonGroup.new()
	for tab_id: Variant in (Catalog.SHOPS[shop_id] as Dictionary)["tabs"]:
		var button := _small_button(str(_Strings.SHOP_UI.get("shop_tab_" + str(tab_id), tab_id)), ORANGE)
		button.toggle_mode = true
		button.button_group = group
		button.set_meta("tab", str(tab_id))
		button.set_pressed_no_signal(str(tab_id) == tab)
		button.add_theme_stylebox_override("normal", _tight(INK.lightened(0.55), 10, INK.lightened(0.4), 0))
		button.add_theme_stylebox_override("pressed", _tight(ORANGE, 10, ORANGE.darkened(0.25), 0))
		button.add_theme_stylebox_override("hover_pressed", _tight(ORANGE.lightened(0.1), 10, ORANGE.darkened(0.25), 0))
		var target := str(tab_id)
		button.pressed.connect(func() -> void: show_tab(target))
		_tabs.add_child(button)


func _refresh_if_open() -> void:
	if visible:
		_refresh()


func _refresh() -> void:
	var me := Net.local_peer_id()
	var wallet := Campaign.credits(me)
	_credits.text = _Strings.UI["shop_credits"] % wallet
	var shops := _shops()
	var open := _is_open()
	_was_open = open
	_info.text = _info_line(shops)
	_info.visible = _info.text != ""
	var keep_scroll := _scroll.scroll_vertical
	for child: Node in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()
	_focus_card = null
	var items := _items()
	for data: Dictionary in items:
		var card := _card(data, wallet, shops, open)
		_cards.add_child(card)
		if focus_item != "" and _is_focus(data):
			_focus_card = card
	_empty.text = str(_Strings.SHOP_UI["shop_scale_empty"] if tab == "sell" else _Strings.SHOP_UI["shop_tab_empty"])
	_empty.visible = items.is_empty() and open
	_shutter.visible = not open or not _unlocked()
	_scroll.visible = not _shutter.visible
	if not _unlocked():
		_shutter_text.text = str(_Strings.SHOP_UI["shop_rank_tag"]) % _Ranks.title(_Ranks.tier_of(Catalog.shop_gate(shop_id)))
	elif not open:
		var opens := str(shops.call("opens_text", shop_id)) if shops != null else ""
		_shutter_text.text = str(_Strings.SHOP_UI["shop_closed_shutter"]) % opens
	_scroll.set_deferred("scroll_vertical", keep_scroll)


## The line over the cards: what the crew has, on a supplies tab.
func _info_line(shops: Node) -> String:
	if shops == null:
		return ""
	var supplies := false
	for id: String in Catalog.items_for(shop_id, tab):
		supplies = supplies or str(Catalog.item(id).get("kind", "")) == "consumable"
	if not supplies:
		return ""
	var bags := float(shops.call("supply", "lawn_bags")) + float(shops.call("supply", "big_bags"))
	return str(_Strings.SHOP_UI["shop_crew_has"]) % [int(bags), int(floor(float(shops.call("supply", "gas"))))]


func _card(data: Dictionary, wallet: int, shops: Node, open: bool) -> Control:
	var id := str(data["id"])
	var entry := Catalog.item(id)
	var kind := str(entry.get("kind", ""))
	var focused := focus_item != "" and _is_focus(data)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	card.add_theme_stylebox_override("panel", _tight(CARD, 12, FOCUS if focused else INK.lightened(0.6), 4 if focused else 2))
	card.set_meta("item", id)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	card.add_child(column)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	column.add_child(top)
	top.add_child(_picture(id, entry, data))
	if data.has("tool"):
		var pips := VBoxContainer.new()
		pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pips.add_child(_text(_pips(int(data["owned_tier"])), 22, ORANGE.darkened(0.1)))
		if int(data["owned_tier"]) == Catalog.TIER_USED:
			pips.add_child(_text(str(_Strings.SHOP_UI["shop_tier_used"]), 13, INK.lightened(0.35)))
		top.add_child(pips)
	var name_label := _text(_Strings.shop_item_name(id), 18, INK)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(CARD_WIDTH - 36.0, 0.0)
	column.add_child(name_label)
	var blurb := _text(_blurb(id, data), 13, INK.lightened(0.25))
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A fixed wrap width, or the label asks for a tall, narrow size first.
	blurb.custom_minimum_size = Vector2(CARD_WIDTH - 36.0, 0.0)
	column.add_child(blurb)
	if kind == "consumable" and shops != null:
		var left := int(shops.call("stock_left", shop_id, id))
		if left >= 0:
			column.add_child(_text(str(_Strings.SHOP_UI["shop_sold_out"]) if left == 0 else str(_Strings.SHOP_UI["shop_stock_left"]) % left, 13, BAD if left == 0 else GOOD))
	var price := Catalog.price(id)
	column.add_child(_text(str(_Strings.SHOP_UI["shop_free"]) if price == 0 else str(_Strings.SHOP_UI["shop_price_tag"]) % price, 16, ORANGE.darkened(0.15)))
	var why := _blocker(id, 1, wallet, shops, open, data)
	if why != "":
		var reason := _text(why, 13, BAD)
		reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reason.custom_minimum_size = Vector2(CARD_WIDTH - 36.0, 0.0)
		column.add_child(reason)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	column.add_child(buttons)
	for action: Dictionary in _actions(id, data, wallet, shops, open, why):
		var button := _small_button(str(action["text"]), ORANGE if bool(action["enabled"]) else INK.lightened(0.5))
		button.disabled = not bool(action["enabled"])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.set_meta("action", str(action["do"]))
		button.set_meta("qty", int(action.get("qty", 1)))
		var what := str(action["do"])
		var qty := int(action.get("qty", 1))
		button.pressed.connect(func() -> void: _press(what, id, qty))
		buttons.add_child(button)
	return card


## The buttons a card gets: [{text, enabled, do: buy | equip | apply | none, qty}].
func _actions(id: String, data: Dictionary, wallet: int, shops: Node, open: bool, why: String) -> Array[Dictionary]:
	var entry := Catalog.item(id)
	var kind := str(entry.get("kind", ""))
	var me := Net.local_peer_id()
	var price := Catalog.price(id)
	if data.has("tool"):
		if bool(data["maxed"]):
			return [{"text": _Strings.UI["shop_owned"], "enabled": false, "do": "none"}]
		var tier := int(Catalog.item(id).get("tier", 1))
		return [{"text": str(_Strings.SHOP_UI["shop_next_tier"]) % [str(_Strings.SHOP_UI["shop_tier_buy_%d" % tier]), price], "enabled": why == "", "do": "buy", "qty": 1}]
	var owned := shops != null and bool(shops.call("owns", me, id))
	if owned and kind == "cosmetic":
		var slot := str(entry.get("slot", "hat"))
		var wearing := shops != null and str((shops.call("look_of", me) as Dictionary).get(slot, "")) == id
		if wearing:
			return [{"text": _Strings.SHOP_UI["shop_wearing"], "enabled": false, "do": "none"}]
		if shops.has_method("request_equip"):
			return [{"text": _Strings.SHOP_UI["shop_wear"], "enabled": true, "do": "equip"}]
		return [{"text": _Strings.UI["shop_owned"], "enabled": false, "do": "none"}]
	if owned and kind == "truck_cosmetic":
		var slot := str(entry.get("slot", "paint"))
		if str((shops.get("truck") as Dictionary).get(slot, "")) == id:
			return [{"text": _Strings.SHOP_UI["shop_applied"], "enabled": false, "do": "none"}]
		if shops.has_method("request_apply_truck"):
			return [{"text": _Strings.SHOP_UI["shop_apply"], "enabled": true, "do": "apply"}]
		return [{"text": _Strings.SHOP_UI["shop_owned_crew"], "enabled": false, "do": "none"}]
	if owned:
		return [{"text": _Strings.UI["shop_owned"], "enabled": false, "do": "none"}]
	if kind == "consumable":
		var out: Array[Dictionary] = []
		for qty: int in Constants.SHOP_QTY_STEPS:
			out.append({"text": str(_Strings.SHOP_UI["shop_buy_qty"]) % qty, "enabled": _blocker(id, qty, wallet, shops, open, data) == "", "do": "buy", "qty": qty})
		return out
	return [{"text": _Strings.UI["shop_buy"], "enabled": why == "", "do": "buy", "qty": 1}]


## Why this can't be bought right now, or "" when it can: the first refusal in
## the host's own order (net/shops/shops.gd _check_buy: closed, season, sold
## out, rank, needs; cash last, as the charge), so the card says what the host
## would answer. Owned things have their own buttons instead, so they're
## skipped before any of it.
func _blocker(id: String, qty: int, wallet: int, shops: Node, open: bool, data: Dictionary) -> String:
	if data.get("maxed", false):
		return ""
	var me := Net.local_peer_id()
	if shops != null and bool(shops.call("owns", me, id)):
		return ""
	if not open:
		return str(_Strings.SHOP_UI["shop_result_closed"])
	var clock := get_tree().get_first_node_in_group("day_clock") if is_inside_tree() else null
	if clock != null and not Catalog.is_in_season(id, int(clock.call("season"))):
		return str(_Strings.SHOP_UI["shop_out_of_season"])
	if shops != null:
		var left := int(shops.call("stock_left", shop_id, id))
		if left >= 0 and left < qty:
			return str(_Strings.SHOP_UI["shop_sold_out"]) if left == 0 or qty == 1 else str(_Strings.SHOP_UI["shop_stock_left"]) % left
	if not Campaign.is_for_sale(StringName(id)):
		return _Strings.UI["shop_needs_rank"] % _Ranks.title(_Ranks.tier_of(Catalog.gate_of(id)))
	var needs: Array = Catalog.item(id).get("needs", [])
	if shops != null and not needs.is_empty() and not needs.any(func(need: Variant) -> bool: return bool(shops.call("owns", me, str(need)))):
		return str(_Strings.SHOP_UI["shop_result_needs"])
	if wallet < Catalog.price(id) * qty:
		return _Strings.UI["shop_short"]
	return ""


func _press(what: String, id: String, qty: int) -> void:
	var shops := _shops()
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play", "ui_pop")
	if shops == null:
		# No Shops (a test scene): the old wallet path.
		Campaign.request_purchase(StringName(id))
		bought.emit(StringName(id))
		return
	match what:
		"buy":
			shops.call("request_buy", shop_id, id, qty)
		"equip":
			shops.call("request_equip", str(Catalog.item(id).get("slot", "hat")), id)
		"apply":
			shops.call("request_apply_truck", id)


## The host's answer to this player's request: a toast, the keeper's reaction
## to a real sale, and fresh cards.
func _on_shop_result(code: String, item_id: String, _amount: int) -> void:
	if not visible or item_id == "give":
		return
	var line := str(_Strings.SHOP_UI.get("shop_result_" + code, code))
	if code == "ok":
		line = line % _Strings.shop_item_name(item_id)
		bought.emit(StringName(item_id))
	show_toast(line, code == "ok")
	_refresh()


func show_toast(line: String, good: bool) -> void:
	_toast.text = line
	_toast.add_theme_color_override("font_color", GOOD if good else BAD)
	_toast.modulate.a = 1.0
	_toast_left = Constants.SHOP_TOAST_SECONDS


## The text of the toast on show ("" once it's gone), for tests.
func toast_text() -> String:
	return _toast.text if _toast_left > 0.0 else ""


# ---------------------------------------------------------------- pieces

## The card's picture: its icon (ui/icons.gd for_shop_item), tinted for shirts
## and paint, or a color swatch while the catalog has no icon for it yet.
func _picture(id: String, entry: Dictionary, data: Dictionary) -> Control:
	var icon_id := _Icons.for_shop_item(StringName(id))
	var tint := _tint(id, entry)
	if icon_id != "" and _Icons.has(icon_id):
		var view := _Icons.rect(icon_id, ICON_PX)
		if icon_id == "shirt" or icon_id == "paint_swatch":
			view.modulate = tint
		return view
	var swatch := PanelContainer.new()
	swatch.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
	swatch.add_theme_stylebox_override("panel", _tight(TOOL_COLORS.get(str(data.get("tool", "")), tint) as Color, 10, INK.lightened(0.5), 2))
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return swatch


func _tint(id: String, entry: Dictionary) -> Color:
	match str(entry.get("slot", "")):
		"shirt":
			var which: Variant = entry.get("shirt", 0)
			if str(which) == "hivis":
				return HIVIS
			return _CartoonBody.SHIRTS[clampi(int(which), 0, _CartoonBody.SHIRTS.size() - 1)]
		"paint":
			return Constants.CHEFTY_PAINTS.get(id, KIND_COLORS["truck_cosmetic"])
	if entry.has("tool"):
		return TOOL_COLORS.get(str(entry["tool"]), Color.GRAY)
	if entry.has("supply"):
		return SUPPLY_COLORS.get(str(entry["supply"]), KIND_COLORS["consumable"])
	return KIND_COLORS.get(str(entry.get("kind", "")), Color.GRAY)


func _blurb(id: String, data: Dictionary) -> String:
	if bool(data.get("maxed", false)):
		return str(_Strings.SHOP_UI["shop_tier_maxed"])
	var blurb := _Strings.shop_item_blurb(id)
	# A stock tool says which jobs it opens up.
	if Catalog.item(id).get("kind", "") == "tool":
		var unlocks := PackedStringArray()
		for task_id: String in Constants.TASK_TOOLS:
			if str(Constants.TASK_TOOLS[task_id]) == id:
				unlocks.append(str(_Strings.UI["task_" + task_id]))
		if not unlocks.is_empty():
			blurb += "\n" + _Strings.UI["shop_tool_unlocks"] % ", ".join(unlocks)
	return blurb


## ●●○: the stock, Mk II and Mk III pips, filled up to the tier owned.
func _pips(owned: int) -> String:
	var out := ""
	for tier: int in range(Catalog.TIER_STOCK, Catalog.TIER_MK3 + 1):
		out += str(_Strings.SHOP_UI["shop_pip_on" if owned >= tier else "shop_pip_off"])
	return out


func _is_focus(data: Dictionary) -> bool:
	if str(data["id"]) == focus_item:
		return true
	return data.has("tool") and str(Catalog.item(focus_item).get("tool", "")) == str(data["tool"])


func _scroll_to_focus() -> void:
	if _focus_card != null and is_instance_valid(_focus_card):
		_scroll.ensure_control_visible(_focus_card)


## What this shop's keeper is saying, under the title (only a line still in
## its caption, so an old one doesn't greet you when the window opens).
func _update_keeper_line() -> void:
	for keeper: Node in get_tree().get_nodes_in_group("shopkeepers"):
		if str(keeper.get("shop_id")) != shop_id:
			continue
		var line := str(keeper.call("current_line")) if keeper.has_method("current_line") else ""
		if line != "" and line != _shown_line:
			_shown_line = line
			_keeper_line.text = str(_Strings.SHOP_UI["shop_keeper_says"]) % [str(_Strings.SHOP_UI.get("keeper_" + str(keeper.get("keeper")), "")), line]
			_keeper_line.visible = true
		return


func _is_open() -> bool:
	var shops := _shops()
	return shops == null or bool(shops.call("is_open", shop_id))


func _unlocked() -> bool:
	var shops := _shops()
	return shops == null or bool(shops.call("is_unlocked", shop_id))


func _shops() -> Node:
	return get_tree().get_first_node_in_group("shops") if is_inside_tree() else null


func _grid_width() -> float:
	return CARD_WIDTH * float(COLUMNS) + float(GAP * (COLUMNS - 1))


func _text(value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


## The catalog look's button (ui/job_board_window.gd uses it too).
func _button(value: String, color: Color) -> Button:
	var button := Button.new()
	button.text = value
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_stylebox_override("normal", _box(color, 10, color.darkened(0.25), 0))
	button.add_theme_stylebox_override("hover", _box(color.lightened(0.12), 10, color.darkened(0.25), 0))
	button.add_theme_stylebox_override("pressed", _box(color.darkened(0.12), 10, color.darkened(0.25), 0))
	button.add_theme_stylebox_override("disabled", _box(color, 10, color.darkened(0.25), 0))
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(1.0, 1.0, 1.0, 0.7))
	return button


## A card's or tab's smaller button, with tighter padding so four cards fit a row.
func _small_button(value: String, color: Color) -> Button:
	var button := _button(value, color)
	button.add_theme_font_size_override("font_size", 16)
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var box := (button.get_theme_stylebox(state) as StyleBoxFlat)
		_tighten(box)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	return button


## The catalog look's rounded panel (ui/job_board_window.gd uses it too).
func _box(color: Color, radius: int, border: Color, border_width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.border_color = border
	box.set_border_width_all(border_width)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	return box


## _box with the tighter padding of a card in a four-wide grid.
func _tight(color: Color, radius: int, border: Color, border_width: int) -> StyleBoxFlat:
	return _tighten(_box(color, radius, border, border_width))


func _tighten(box: StyleBoxFlat) -> StyleBoxFlat:
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 7
	box.content_margin_bottom = 7
	return box


## The roll-down shutter: steel gray with darker slats.
func _shutter_box() -> StyleBoxFlat:
	var box := _tight(SHUTTER, 12, SHUTTER.darkened(0.35), 4)
	box.shadow_color = Color(0.0, 0.0, 0.0, 0.25)
	box.shadow_size = 6
	return box
