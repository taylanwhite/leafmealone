extends PanelContainer

## Authority: local. The payout receipt after a job: what the bags were worth,
## how the homeowner felt and what that did to the pay, what was paid, and each
## player's share. Styled like the store catalog (ui/shop_window.gd).

const _Strings = preload("res://ui/strings.gd")
const PAPER := Color(0.97, 0.93, 0.84)
const INK := Color(0.17, 0.14, 0.11)
const ORANGE := Color(0.93, 0.47, 0.13)
const GREEN := Color(0.2, 0.55, 0.25)
const RED := Color(0.75, 0.2, 0.15)

var _rows: VBoxContainer


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(420, 0)
	add_theme_stylebox_override("panel", _box(PAPER, 18, ORANGE, 6))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	column.add_child(_text(_Strings.UI["receipt_title"], 32, ORANGE))
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	column.add_child(_rows)
	var close := Button.new()
	close.text = _Strings.UI["receipt_close"]
	close.add_theme_font_size_override("font_size", 18)
	close.add_theme_stylebox_override("normal", _box(ORANGE, 10, ORANGE.darkened(0.25), 0))
	close.add_theme_stylebox_override("hover", _box(ORANGE.lightened(0.12), 10, ORANGE.darkened(0.25), 0))
	close.add_theme_stylebox_override("pressed", _box(ORANGE.darkened(0.12), 10, ORANGE.darkened(0.25), 0))
	close.add_theme_color_override("font_color", Color.WHITE)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(close_window)
	column.add_child(close)


func show_payout(results: Array[Dictionary], settlement: Dictionary) -> void:
	for child: Node in _rows.get_children():
		child.queue_free()
	if settlement.has("bags_value"):
		_line(_Strings.UI["receipt_bags"], "$%d" % int(settlement["bags_value"]), INK)
		for row: Array in settlement.get("tasks", []):
			_line(_Strings.UI["receipt_task"] % [_Strings.UI["task_" + str(row[0])], int(row[1])], "$%d" % int(row[2]), INK)
		var multiplier := float(settlement.get("multiplier", 1.0))
		var mood: String = _Strings.MOOD_NAMES.get(str(settlement.get("mood", "")), str(settlement.get("mood", "")))
		var change := int(round((multiplier - 1.0) * 100.0))
		var change_text := "+%d%%" % change if change > 0 else ("%d%%" % change if change < 0 else "±0%")
		_line(_Strings.UI["receipt_mood"] % mood, change_text, GREEN if change > 0 else (RED if change < 0 else INK))
		if int(settlement.get("water_fee", 0)) > 0:
			_line(_Strings.UI["receipt_water"], "-$%d" % int(settlement["water_fee"]), RED)
		_line(_Strings.UI["receipt_paid"], "$%d" % int(settlement.get("paid", 0)), ORANGE.darkened(0.1), 22)
	else:
		_line(_Strings.UI["receipt_no_homeowner"], "", INK)
	_rows.add_child(HSeparator.new())
	_rows.add_child(_text(_Strings.UI["receipt_split"], 16, INK.lightened(0.3)))
	for row: Dictionary in results:
		_line(str(row["name"]), "$%d" % int(row["credits"]), INK)
	visible = true
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_window() -> void:
	visible = false
	if Net.current_state() == Net.State.IN_SESSION:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _line(left: String, right: String, color: Color, size: int = 18) -> void:
	var row := HBoxContainer.new()
	var name_label := _text(left, size, INK)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	row.add_child(_text(right, size, color))
	_rows.add_child(row)


func _text(value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _box(color: Color, radius: int, border: Color, border_width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.border_color = border
	box.set_border_width_all(border_width)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 14
	box.content_margin_bottom = 14
	return box
