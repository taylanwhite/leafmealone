extends Control

## Authority: local. Top-right of the screen: the day and the clock, the crew's
## rank with an XP bar (pending XP drawn lighter, banked when you sleep), and a
## line for quiet hours or 2 AM. Reads net/day/day_clock.gd and Campaign.

const _Strings = preload("res://ui/strings.gd")
const _Ranks = preload("res://core/ranks.gd")
const _Seasons = preload("res://core/seasons.gd")
const ORANGE := Color(0.93, 0.47, 0.13)
const BAR_WIDTH: float = 220.0

var _clock_label: Label
var _rank_label: Label
var _xp_label: Label
var _note: Label
var _bar_back: ColorRect
var _bar_banked: ColorRect
var _bar_pending: ColorRect


func _ready() -> void:
	# Anchored to the top-right corner; offsets are from that corner.
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -BAR_WIDTH - 110.0
	offset_right = -24.0
	offset_top = 14.0
	offset_bottom = 120.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock_label = _label(22, Color(1.0, 0.98, 0.92))
	_clock_label.position = Vector2(0, 0)
	_clock_label.custom_minimum_size = Vector2(BAR_WIDTH + 86.0, 0)
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_rank_label = _label(17, Color(1.0, 0.82, 0.4))
	_rank_label.position = Vector2(86, 30)
	_bar_back = _rect(Color(0.0, 0.0, 0.0, 0.45), Vector2(86, 56), Vector2(BAR_WIDTH, 8))
	_bar_pending = _rect(Color(1.0, 0.85, 0.5, 0.65), Vector2(86, 56), Vector2(0, 8))
	_bar_banked = _rect(ORANGE, Vector2(86, 56), Vector2(0, 8))
	_xp_label = _label(13, Color(1.0, 1.0, 1.0, 0.8))
	_xp_label.position = Vector2(86, 66)
	_note = _label(14, Color(0.75, 0.85, 1.0))
	_note.position = Vector2(-34, 86)
	_note.custom_minimum_size = Vector2(BAR_WIDTH + 120, 0)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _process(_delta: float) -> void:
	var clock := get_tree().get_first_node_in_group("day_clock")
	visible = clock != null and Net.current_state() == Net.State.IN_SESSION
	if not visible:
		return
	_clock_label.text = _Strings.UI["hud_clock"] % [int(clock.get("day")), _Seasons.name_of(int(clock.call("season"))), str(clock.call("clock_text"))]
	var tier := Campaign.crew_tier()
	_rank_label.text = _Strings.UI["hud_rank"] % _Ranks.title(tier)
	var need := float(_Ranks.xp_for_tier(tier))
	var into := float(_Ranks.xp_into_tier(Campaign.crew_xp()))
	var pending := float(Campaign.pending_xp())
	_bar_banked.size.x = BAR_WIDTH * clampf(into / need, 0.0, 1.0)
	_bar_pending.size.x = BAR_WIDTH * clampf((into + pending) / need, 0.0, 1.0)
	_xp_label.text = _Strings.UI["hud_xp"] % [int(into), int(need), int(pending)]
	if bool(clock.call("is_closed")):
		_note.text = _Strings.UI["hud_closed"]
		_note.modulate = Color(1.0, 0.7, 0.6)
	elif bool(clock.call("is_quiet_hours")):
		_note.text = _Strings.UI["hud_quiet_hours"] % int(round(float(clock.call("pay_bonus")) * 100.0))
		_note.modulate = Color(0.75, 0.85, 1.0)
	else:
		_note.text = ""
	var phone := get_tree().get_first_node_in_group("phone")
	var unread := int(phone.call("unread")) if phone != null else 0
	if unread > 0:
		_note.text = (_Strings.UI["hud_unread"] % unread) + ("\n" + _note.text if _note.text != "" else "")
		_note.modulate = Color(1.0, 0.9, 0.6)


func _label(size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func _rect(color: Color, at: Vector2, size_of: Vector2) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.position = at
	rect.size = size_of
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	return rect
