extends PanelContainer

## Authority: local. The Homie Depot shop window, styled like a store catalog
## (docs/FEEL.md, "How characters deal with shops"): a card per item with its
## price, what it does, and whether you own it or can afford it. Buying asks the
## host through Campaign.request_purchase(), which checks the price and credits.

signal bought(item_id: StringName)

const _Strings = preload("res://ui/strings.gd")
const PAPER := Color(0.97, 0.93, 0.84)
const INK := Color(0.17, 0.14, 0.11)
const ORANGE := Color(0.93, 0.47, 0.13)
const CARD := Color(1.0, 0.98, 0.93)
const CARD_WIDTH: float = 190.0
## Card swatch colors for tools, until each has a picture.
const TOOL_COLORS: Dictionary = {
	"leaf_blower": Color(0.95, 0.55, 0.15), "lawn_mower": Color(0.2, 0.55, 0.3), "ladder": Color(0.75, 0.75, 0.72),
	"hose": Color(0.25, 0.6, 0.35), "pressure_washer": Color(0.95, 0.8, 0.2), "hedge_trimmer": Color(0.85, 0.25, 0.2),
	"paint_roller": Color(0.35, 0.55, 0.85),
}

var _credits: Label
var _cards: GridContainer


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", _box(PAPER, 18, ORANGE, 6))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := _text(_Strings.UI["shop_title"], 34, ORANGE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_credits = _text("", 20, INK)
	header.add_child(_credits)
	column.add_child(_text(_Strings.UI["shop_subtitle"], 16, INK.lightened(0.3)))
	_cards = GridContainer.new()
	_cards.columns = 5
	_cards.add_theme_constant_override("h_separation", 12)
	_cards.add_theme_constant_override("v_separation", 12)
	column.add_child(_cards)
	var close := _button(_Strings.UI["shop_close"], INK)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(close_window)
	column.add_child(close)
	Campaign.credits_changed.connect(func(_peer_id: int, _amount: int) -> void: _refresh_if_open())
	Campaign.unlocks_changed.connect(_refresh_if_open)


func open() -> void:
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
		for task_id: String in Constants.TASK_TOOLS:
			if str(Constants.TASK_TOOLS[task_id]) == tool_id:
				unlocks.append(str(_Strings.UI["task_" + task_id]))
		var blurb := str(_Strings.UI["tool_blurb_" + tool_id])
		if not unlocks.is_empty():
			blurb += "\n" + _Strings.UI["shop_tool_unlocks"] % ", ".join(unlocks)
		items.append({
			"id": StringName(tool_id),
			"name": _Strings.UI["tool_" + tool_id],
			"blurb": blurb,
			"price": int(Constants.TOOL_PRICES[tool_id]),
			"color": TOOL_COLORS.get(tool_id, Color.GRAY),
		})
	items.append_array([
		{
			"id": Campaign.RAKE_UPGRADE,
			"name": _Strings.UI["shop_rake_name"],
			"blurb": _Strings.UI["shop_rake_blurb"] % Balance.TOOL_THROUGHPUT_GROWTH_MULTIPLIER,
			"price": Balance.BASELINE_TIER_1_TOOL_COST,
			"color": Color(0.85, 0.55, 0.25),
		},
		{
			"id": Campaign.WHEELBARROW_UPGRADE,
			"name": _Strings.UI["shop_barrow_name"],
			"blurb": _Strings.UI["shop_barrow_blurb"] % [Constants.WHEELBARROW_UPGRADED_BAG_CAPACITY, Constants.WHEELBARROW_BAG_CAPACITY],
			"price": Balance.BASELINE_TIER_1_TOOL_COST,
			"color": Color(0.55, 0.22, 0.18),
		},
	])
	return items


func _refresh_if_open() -> void:
	if visible:
		_refresh()


func _refresh() -> void:
	var wallet := Campaign.credits(Net.local_peer_id())
	_credits.text = _Strings.UI["shop_credits"] % wallet
	for child: Node in _cards.get_children():
		child.queue_free()
	for item: Dictionary in _items():
		_cards.add_child(_card(item, wallet))


func _card(item: Dictionary, wallet: int) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	card.add_theme_stylebox_override("panel", _box(CARD, 12, INK.lightened(0.6), 2))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	card.add_child(column)
	# A chunky swatch stands in for the item's picture until there is art for it.
	var swatch := ColorRect.new()
	swatch.color = item["color"]
	swatch.custom_minimum_size = Vector2(0, 10)
	column.add_child(swatch)
	column.add_child(_text(str(item["name"]), 18, INK))
	var blurb := _text(str(item["blurb"]), 13, INK.lightened(0.25))
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A fixed wrap width, or the label asks for a tall, narrow size first.
	blurb.custom_minimum_size = Vector2(CARD_WIDTH - 40.0, 0.0)
	column.add_child(blurb)
	column.add_child(_text(_Strings.UI["shop_price"] % int(item["price"]), 16, ORANGE.darkened(0.15)))
	var owned := Campaign.is_unlocked(item["id"])
	var affordable := wallet >= int(item["price"])
	var label: String = _Strings.UI["shop_owned"] if owned else (_Strings.UI["shop_buy"] if affordable else _Strings.UI["shop_short"])
	var buy := _button(label, ORANGE if affordable and not owned else INK.lightened(0.5))
	buy.disabled = owned or not affordable
	var item_id: StringName = item["id"]
	buy.pressed.connect(func() -> void:
		Campaign.request_purchase(item_id)
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
