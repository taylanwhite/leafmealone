extends "res://ui/shop_window.gd"

## Authority: local. The job board up close, styled like the shop's catalog: a
## card per offer with the yard (and its neighborhood's pin), every job the
## homeowner wants done as a task badge (and the tool it needs, locked, if the
## crew doesn't have it), and what the jobs pay. The crew rating is a row of
## stars. Picking one asks the host through levels/job_board.gd.

## Its own names for these, not the parent's: shops chunk 4 rewrites
## ui/shop_window.gd and may declare _Icons/_Look there, and a subclass can't
## redeclare a parent's constant.
const _BoardIcons = preload("res://ui/icons.gd")
const _BoardLook = preload("res://ui/catalog_look.gd")
const CARD_WIDE: float = 250.0
## The neighborhood pin beside a client card's address.
const HOOD_PIN_PX: float = 20.0

var _board_cards: HBoxContainer
## The crew rating: a lead label, five star icons and the job count, rebuilt on refresh.
var _rating: HBoxContainer


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", _box(PAPER, 18, ORANGE, 6))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	add_child(column)
	# x1:text: no subtitle explaining the board; the cards' pay lines say it.
	column.add_child(_text(_Strings.UI["board_window_title"], 34, ORANGE))
	_rating = HBoxContainer.new()
	_rating.add_theme_constant_override("separation", 6)
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
	_show_rating(Campaign.rating(), Campaign.rating_count())
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
	if offer.has("client"):
		# A town client (net/town/town.gd): who, where, and how they feel about you.
		column.add_child(_text(str(offer["client"]), 20, INK))
		var where := _text("%d %s · %s" % [int(offer["house"]), str(offer.get("street", "")), str(offer.get("hood_name", ""))], 14, INK.lightened(0.3))
		where.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		where.custom_minimum_size = Vector2(CARD_WIDE - 40.0 - HOOD_PIN_PX - 6.0, 0.0)
		column.add_child(_BoardIcons.row(_BoardIcons.for_hood(str(offer.get("hood", ""))), where, HOOD_PIN_PX))
	else:
		column.add_child(_text(_Strings.UI["board_house"] % int(offer["house"]), 22, INK))
	column.add_child(_text(_Strings.UI["board_size_%d" % int(offer.get("size", 1))], 15, INK.lightened(0.3)))
	var owned := Campaign.crew_tools()
	for task: String in (offer["tasks"] as PackedStringArray):
		var line := str(_Strings.UI["task_" + task])
		var tool := str(Constants.TASK_TOOLS.get(task, ""))
		var missing := tool != "" and not owned.has(tool)
		if missing:
			line = _Strings.UI["task_needs"] % [line, str(_Strings.UI["tool_" + tool]).to_lower()]
		var label := _text(line, 14, INK.lightened(0.15))
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# The badge and, for a missing tool, its icon and lock take this much of the row.
		var icons_wide := _BoardIcons.SIZE_ROW + 6.0 + ((_BoardLook.MISSING_TOOL_PX + 6.0) * 2.0 if missing else 0.0)
		label.custom_minimum_size = Vector2(CARD_WIDE - 40.0 - icons_wide, 0.0)
		column.add_child(_BoardLook.task_line(task, label, tool if missing else ""))
	var pay: int = load("res://levels/job_board.gd").task_pay(offer)
	column.add_child(_BoardLook.price_row(_text(_Strings.UI["board_pay"] % pay, 18, ORANGE.darkened(0.15))))
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

## The crew rating as star icons (ui/job_board_window.gd): the lead, the stars,
## then the count; no reviews yet keeps the old one-line text.
func _show_rating(rating: float, count: int) -> void:
	for child: Node in _rating.get_children():
		child.queue_free()
	var color := ORANGE.darkened(0.15)
	if count <= 0:
		_rating.add_child(_text(_Strings.UI["board_rating_none"], 18, color))
		return
	_rating.add_child(_text(_Strings.ICON_UI["board_rating_lead"], 18, color))
	_rating.add_child(_BoardLook.stars(rating))
	_rating.add_child(_text(_Strings.ICON_UI["board_rating_jobs"] % count, 18, color))
