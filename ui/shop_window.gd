extends PanelContainer

## Authority: local. The Homie Depot shop window, styled like a store catalog
## (docs/FEEL.md, "How characters deal with shops"): a card per item with its
## icon on a shelf, its price, what it does, and whether you own it or can afford
## it. The sticker look (shelf, stamps, badges, hover and buy pop) is
## ui/catalog_look.gd's. Buying asks the host through Campaign.request_purchase(),
## which checks the price and credits.

signal bought(item_id: StringName)

const _Strings = preload("res://ui/strings.gd")
const _Ranks = preload("res://core/ranks.gd")
const _Icons = preload("res://ui/icons.gd")
const _Look = preload("res://ui/catalog_look.gd")
const PAPER := Color(0.97, 0.93, 0.84)
const INK := Color(0.17, 0.14, 0.11)
const ORANGE := Color(0.93, 0.47, 0.13)
const CARD := Color(1.0, 0.98, 0.93)
const CARD_WIDTH: float = 190.0
const CARD_MARGIN: int = 8
## Each tool's color: its card's shelf is tinted from it (ui/catalog_look.gd shelf()).
const TOOL_COLORS: Dictionary = {
	"leaf_blower": Color(0.95, 0.55, 0.15), "lawn_mower": Color(0.2, 0.55, 0.3), "ladder": Color(0.75, 0.75, 0.72),
	"hose": Color(0.25, 0.6, 0.35), "pressure_washer": Color(0.95, 0.8, 0.2), "hedge_trimmer": Color(0.85, 0.25, 0.2),
	"paint_roller": Color(0.35, 0.55, 0.85),
}

## How long after a confirmed buy a redrawn card still pops (_pop_bought).
const POP_REMEMBER_MSEC: int = 600

var _credits: Label
var _cards: GridContainer
var _pop_item: StringName = &""
var _pop_until_msec: int = 0


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", _box(PAPER, 18, ORANGE, 6))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	# One header line, so two rows of shelves fit 1280x720: the brand mark, the
	# name and what's sold, then the wallet and Close.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	column.add_child(header)
	var title := _text(_Strings.UI["shop_title"], 34, ORANGE)
	var brand := _Look.brand_title("brand_homie_depot", title)
	title.size_flags_horizontal = Control.SIZE_FILL
	var subtitle := _text(_Strings.UI["shop_subtitle"], 16, INK.lightened(0.3))
	subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	subtitle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brand.add_child(subtitle)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(brand)
	_credits = _text("", 20, INK)
	var wallet := _Look.wallet(_credits)
	wallet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(wallet)
	var close := _button(_Strings.UI["shop_close"], INK)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(close_window)
	header.add_child(close)
	_cards = GridContainer.new()
	_cards.columns = 5
	_cards.add_theme_constant_override("h_separation", 12)
	_cards.add_theme_constant_override("v_separation", 12)
	column.add_child(_cards)
	Campaign.credits_changed.connect(func(_peer_id: int, _amount: int) -> void: _refresh_if_open())
	Campaign.unlocks_changed.connect(_refresh_if_open)


func open() -> void:
	# The world (and its Shops node) is made after the UI, so this hooks up on open.
	var shops := _shops()
	if shops != null and not shops.is_connected("result", _on_shop_result):
		shops.connect("result", _on_shop_result)
	_refresh()
	visible = true
	# Centered by anchors, growing both ways from the middle of the screen, so its
	# size can settle after the cards are built without knocking it off screen.
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_window() -> void:
	visible = false
	if Net.current_state() == Net.State.IN_SESSION:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		close_window()
		get_viewport().set_input_as_handled()


## Everything the store sells: tools that unlock tasks, then upgrades. Prices
## and effects come from Balance and Constants.
func _items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for tool_id: String in Constants.TOOL_PRICES:
		var unlocks := PackedStringArray()
		var tasks := PackedStringArray()
		for task_id: String in Constants.TASK_TOOLS:
			if str(Constants.TASK_TOOLS[task_id]) == tool_id:
				unlocks.append(str(_Strings.UI["task_" + task_id]))
				tasks.append(task_id)
		# What it unlocks is a row of task badges under the blurb (_card), named on hover.
		items.append({
			"id": StringName(tool_id),
			"name": _Strings.UI["tool_" + tool_id],
			"blurb": str(_Strings.UI["tool_blurb_" + tool_id]),
			"unlocks": unlocks,
			"price": Campaign.price_of(StringName(tool_id)),
			"color": TOOL_COLORS.get(tool_id, Color.GRAY),
			"icon": _Icons.for_shop_item(StringName(tool_id)),
			"tasks": tasks,
		})
	items.append_array([
		{
			"id": Campaign.RAKE_UPGRADE,
			"name": _Strings.UI["shop_rake_name"],
			"blurb": _Strings.UI["shop_rake_blurb"] % Balance.TOOL_THROUGHPUT_GROWTH_MULTIPLIER,
			"price": Campaign.price_of(Campaign.RAKE_UPGRADE),
			"color": Color(0.85, 0.55, 0.25),
			"icon": _Icons.for_shop_item(Campaign.RAKE_UPGRADE),
		},
		{
			"id": Campaign.WHEELBARROW_UPGRADE,
			"name": _Strings.UI["shop_barrow_name"],
			"blurb": _Strings.UI["shop_barrow_blurb"] % [Constants.WHEELBARROW_UPGRADED_BAG_CAPACITY, Constants.WHEELBARROW_BAG_CAPACITY],
			"price": Campaign.price_of(Campaign.WHEELBARROW_UPGRADE),
			"color": Color(0.55, 0.22, 0.18),
			"icon": _Icons.for_shop_item(Campaign.WHEELBARROW_UPGRADE),
		},
	])
	return items


func _refresh_if_open() -> void:
	if visible:
		_refresh()


## The host's answer to this player's buy: the clerk only chatters over a real
## sale; a refusal (closed, too far) redraws the cards so they show why.
## The toast for a refusal comes with the shop UI (shops chunk 4).
func _on_shop_result(code: String, item_id: String, _amount: int) -> void:
	if not visible or item_id == "give":
		return
	if code == "ok":
		_pop_bought(StringName(item_id))
		bought.emit(StringName(item_id))
	else:
		_refresh()


## The bought item's icon squash-pops (ui/catalog_look.gd pop()). The sale also
## redraws the cards (credits and unlocks change) in either order, so the pop is
## remembered for a moment and played again on the redrawn card.
func _pop_bought(item_id: StringName) -> void:
	_pop_item = item_id
	_pop_until_msec = Time.get_ticks_msec() + POP_REMEMBER_MSEC
	_pop_card.call_deferred()


func _pop_card() -> void:
	if _cards == null:
		return
	for card: Node in _cards.get_children():
		if card.is_queued_for_deletion() or card.get_meta("item_id", &"") != _pop_item:
			continue
		var shelf := card.get_meta("shelf", null) as Control
		if shelf != null:
			_Look.pop(shelf.get_meta("shelf_icon", null) as Control)


func _shops() -> Node:
	return get_tree().get_first_node_in_group("shops") if is_inside_tree() else null


func _refresh() -> void:
	var wallet := Campaign.credits(Net.local_peer_id())
	_credits.text = _Strings.UI["cash_amount"] % wallet
	for child: Node in _cards.get_children():
		child.queue_free()
	for item: Dictionary in _items():
		_cards.add_child(_card(item, wallet))
	if Time.get_ticks_msec() < _pop_until_msec:
		_pop_card.call_deferred()


func _card(item: Dictionary, wallet: int) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	var card_box := _box(CARD, 12, INK.lightened(0.6), 2)
	# Tighter than a window's margins: two rows of cards must fit 1280x720.
	card_box.content_margin_left = CARD_MARGIN
	card_box.content_margin_right = CARD_MARGIN
	card_box.content_margin_top = CARD_MARGIN
	card_box.content_margin_bottom = CARD_MARGIN
	card.add_theme_stylebox_override("panel", card_box)
	card.set_meta("item_id", item["id"])
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	card.add_child(column)
	var owned := Campaign.is_unlocked(item["id"])
	var affordable := wallet >= int(item["price"])
	# The crew's rank gates what Homie Depot will sell them (core/ranks.gd).
	var for_sale := Campaign.is_for_sale(item["id"])
	# The item's icon on a shelf tinted its color, its price tag stuck on the corner:
	# OWNED gets a check, a rank lock a lock.
	var tag := _Look.price_tag(_text(_Strings.UI["shop_price"] % int(item["price"]), 15, ORANGE.darkened(0.15)))
	var shelf := _Look.shelf(str(item.get("icon", "")), item["color"], owned, not for_sale, tag)
	card.set_meta("shelf", shelf)
	column.add_child(shelf)
	_Look.hover(card, shelf)
	column.add_child(_text(str(item["name"]), 18, INK))
	var blurb := _text(str(item["blurb"]), 13, INK.lightened(0.25))
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A fixed wrap width, or the label asks for a tall, narrow size first.
	blurb.custom_minimum_size = Vector2(CARD_WIDTH - 2.0 * CARD_MARGIN - 4.0, 0.0)
	column.add_child(blurb)
	var tasks: PackedStringArray = item.get("tasks", PackedStringArray())
	if not tasks.is_empty():
		var lead := _text((_Strings.UI["shop_tool_unlocks"] % "").strip_edges(), 13, INK.lightened(0.25))
		column.add_child(_Look.task_badges(tasks, item.get("unlocks", PackedStringArray()), lead))
	# The button sits at the card's foot, so buttons line up across a row.
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)
	var label: String = _Strings.UI["shop_owned"] if owned else (_Strings.UI["shop_buy"] if affordable else _Strings.UI["shop_short"])
	if not owned and not for_sale:
		label = _Strings.UI["shop_needs_rank"] % _Ranks.title(_Ranks.tier_of(Catalog.gate_of(String(item["id"]))))
	# After hours the host refuses the buy (net/shops/shops.gd), so the card says so.
	var shops := _shops()
	var closed := shops != null and not bool(shops.call("is_open", "homie_depot"))
	if not owned and closed:
		label = _Strings.SHOP_UI["shop_result_closed"]
	var buy := _button(label, ORANGE if affordable and not owned and for_sale and not closed else INK.lightened(0.5))
	buy.disabled = owned or not affordable or not for_sale or closed
	var item_id: StringName = item["id"]
	buy.pressed.connect(func() -> void:
		Campaign.request_purchase(item_id)
		# With Shops in the world, `bought` waits for the host's "ok" (_on_shop_result).
		if _shops() == null:
			_pop_bought(item_id)
			bought.emit(item_id)
	)
	column.add_child(buy)
	return card


func _text(value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


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
