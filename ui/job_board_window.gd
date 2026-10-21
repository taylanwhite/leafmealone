extends "res://ui/shop_window.gd"

## Authority: local. The job board up close, styled like the shop's catalog: a
## card per offer with the yard, every job the homeowner wants done (and which
## tool it needs if the crew doesn't have it), and what the jobs pay. Picking
## one asks the host through levels/job_board.gd.

const CARD_WIDE: float = 250.0

var _board_cards: HBoxContainer
var _rating: Label


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", _box(PAPER, 18, ORANGE, 6))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	add_child(column)
	column.add_child(_text(_Strings.UI["board_window_title"], 34, ORANGE))
	column.add_child(_text(_Strings.UI["board_window_subtitle"], 16, INK.lightened(0.3)))
	_rating = _text("", 18, ORANGE.darkened(0.15))
	column.add_child(_rating)
	_board_cards = HBoxContainer.new()
	_board_cards.add_theme_constant_override("separation", 14)
	column.add_child(_board_cards)
	var close := _button(_Strings.UI["board_close"], INK)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(close_window)
	column.add_child(close)


func open() -> void:
	var board := _board()
	if board != null and not board.is_connected("offers_changed", _refresh_if_open):
		board.connect("offers_changed", _refresh_if_open)
	super.open()


func _board() -> Node:
	return get_tree().get_first_node_in_group("job_board")


func _refresh() -> void:
	for child: Node in _board_cards.get_children():
		child.queue_free()
	var count := Campaign.rating_count()
	_rating.text = _Strings.UI["board_rating"] % [_Strings.stars(Campaign.rating()), count] if count > 0 else _Strings.UI["board_rating_none"]
	var board := _board()
	if board == null:
		return
	var offers: Array = board.get("offers")
	var world := get_tree().get_first_node_in_group("world")
	var locked := world != null and bool(world.call("job_locked"))
	for index: int in offers.size():
		_board_cards.add_child(_offer_card(offers[index], index, index == int(board.get("chosen")), locked))


func _offer_card(offer: Dictionary, index: int, picked: bool, locked: bool) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_WIDE, 0)
	card.add_theme_stylebox_override("panel", _box(CARD, 12, ORANGE if picked else INK.lightened(0.6), 4 if picked else 2))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	card.add_child(column)
	column.add_child(_text(_Strings.UI["board_house"] % int(offer["house"]), 22, INK))
	column.add_child(_text(_Strings.UI["board_size_%d" % int(offer.get("size", 1))], 15, INK.lightened(0.3)))
	var owned := Campaign.crew_tools()
	for task: String in (offer["tasks"] as PackedStringArray):
		var line := str(_Strings.UI["task_" + task])
		var tool := str(Constants.TASK_TOOLS.get(task, ""))
		if tool != "" and not owned.has(tool):
			line = _Strings.UI["task_needs"] % [line, str(_Strings.UI["tool_" + tool]).to_lower()]
		var label := _text("•  " + line, 14, INK.lightened(0.15))
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(CARD_WIDE - 40.0, 0.0)
		column.add_child(label)
	var pay: int = load("res://levels/job_board.gd").task_pay(offer)
	column.add_child(_text(_Strings.UI["board_pay"] % pay, 18, ORANGE.darkened(0.15)))
	var label: String = _Strings.UI["board_taken"] if picked else (_Strings.UI["board_locked"] if locked else _Strings.UI["board_take"])
	var take := _button(label, ORANGE if not picked and not locked else INK.lightened(0.5))
	take.disabled = picked or locked
	take.pressed.connect(func() -> void:
		var board := _board()
		if board != null:
			board.call("request_choose", index)
	)
	column.add_child(take)
	return card
