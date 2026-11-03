extends Control

## Authority: local. Top-right of the screen: the season, the day and the clock
## with a sun (or the moon once quiet hours start), the crew's rank badge and
## title with an XP bar (pending XP drawn lighter, banked when you sleep), and a
## line for quiet hours, 2 AM or unread texts (with the phone's keycap). Reads
## net/day/day_clock.gd and Campaign. Icons: gap-specs/icons.json chunk E.

const _Strings = preload("res://ui/strings.gd")
const _Ranks = preload("res://core/ranks.gd")
const _Seasons = preload("res://core/seasons.gd")
const _Icons = preload("res://ui/icons.gd")
const _Look = preload("res://ui/catalog_look.gd")
const ORANGE := Color(0.93, 0.47, 0.13)
const BAR_WIDTH: float = 220.0
## Where the rank badge sits (left of the rank title and bar), and how big.
const BADGE_AT := Vector2(12, 26)
const BADGE_PX: float = 64.0
## The rank title, the XP bar and the XP line start this far in, right of the badge.
const COLUMN_X: float = 86.0
## The clock row's height; the season and sun icons are SIZE_HUD tall in it.
const CLOCK_ROW_HEIGHT: float = 28.0
const XP_ICON_PX: float = 16.0
## The note line's keycaps and icons, in pixels of height.
const NOTE_ICON_PX: float = 18.0
const NOTE_COLOR_QUIET := Color(0.75, 0.85, 1.0)
const NOTE_COLOR_CLOSED := Color(1.0, 0.7, 0.6)
const NOTE_COLOR_UNREAD := Color(1.0, 0.9, 0.6)

var _clock_label: Label
var _season_icon: TextureRect
var _time_icon: TextureRect
var _rank_block: Control
var _rank_badge: TextureRect
var _rank_label: Label
var _xp_label: Label
var _note: RichTextLabel
var _bar_back: ColorRect
var _bar_banked: ColorRect
var _bar_pending: ColorRect
## What the badge and the note show now, so they change only when it does.
var _shown_tier: int = -1
var _shown_note: String = ""


func _ready() -> void:
	# Anchored to the top-right corner; offsets are from that corner.
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -BAR_WIDTH - 110.0
	offset_right = -24.0
	offset_top = 14.0
	offset_bottom = 120.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# [season] Day 3 · Autumn  9:45 AM [sun], pushed to the right edge.
	var clock_row := HBoxContainer.new()
	clock_row.alignment = BoxContainer.ALIGNMENT_END
	clock_row.add_theme_constant_override("separation", 6)
	clock_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clock_row.position = Vector2.ZERO
	clock_row.size = Vector2(BAR_WIDTH + COLUMN_X, CLOCK_ROW_HEIGHT)
	add_child(clock_row)
	_season_icon = _icon(_Icons.SIZE_HUD)
	clock_row.add_child(_season_icon)
	_clock_label = _label(22, Color(1.0, 0.98, 0.92), clock_row)
	_clock_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_time_icon = _icon(_Icons.SIZE_HUD)
	clock_row.add_child(_time_icon)
	# The rank block (badge, title, XP) steps back while the phone is out: the phone
	# sits over it, and its Crew app shows the same rank bigger.
	_rank_block = Control.new()
	_rank_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rank_block)
	_rank_badge = _icon(BADGE_PX)
	_rank_badge.position = BADGE_AT
	_rank_badge.size = Vector2(BADGE_PX, BADGE_PX)
	_rank_block.add_child(_rank_badge)
	_rank_label = _label(17, Color(1.0, 0.82, 0.4), _rank_block)
	_rank_label.position = Vector2(COLUMN_X, 30)
	_bar_back = _rect(Color(0.0, 0.0, 0.0, 0.45), Vector2(COLUMN_X, 56), Vector2(BAR_WIDTH, 8))
	_bar_pending = _rect(Color(1.0, 0.85, 0.5, 0.65), Vector2(COLUMN_X, 56), Vector2(0, 8))
	_bar_banked = _rect(ORANGE, Vector2(COLUMN_X, 56), Vector2(0, 8))
	var xp_icon := _icon(XP_ICON_PX)
	_set_icon(xp_icon, "xp")
	xp_icon.position = Vector2(COLUMN_X, 67)
	xp_icon.size = Vector2(XP_ICON_PX, XP_ICON_PX)
	_rank_block.add_child(xp_icon)
	_xp_label = _label(13, Color(1.0, 1.0, 1.0, 0.8), _rank_block)
	_xp_label.position = Vector2(COLUMN_X + XP_ICON_PX + 4.0, 66)
	# Rich text, so the unread line can show the phone's keycap and the unread icon.
	_note = RichTextLabel.new()
	_note.bbcode_enabled = true
	_note.fit_content = true
	_note.scroll_active = false
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_note.position = Vector2(-34, 94)
	_note.custom_minimum_size = Vector2(BAR_WIDTH + 120, 0)
	_note.size = Vector2(BAR_WIDTH + 120, 0)
	_note.add_theme_font_size_override("normal_font_size", 14)
	_note.add_theme_color_override("font_shadow_color", Color.BLACK)
	_note.add_theme_constant_override("shadow_offset_x", 1)
	_note.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_note)


func _process(delta: float) -> void:
	var clock := get_tree().get_first_node_in_group("day_clock")
	visible = clock != null and Net.current_state() == Net.State.IN_SESSION
	if not visible:
		return
	var phone := get_tree().get_first_node_in_group("phone") as Control
	var under_phone := phone != null and phone.visible
	_rank_block.modulate.a = move_toward(_rank_block.modulate.a, 0.0 if under_phone else 1.0, delta / Constants.ICONS_HUD_FADE_SECONDS)
	var season := int(clock.call("season"))
	_clock_label.text = _Strings.UI["hud_clock"] % [int(clock.get("day")), _Seasons.name_of(season), str(clock.call("clock_text"))]
	_set_icon(_season_icon, _Icons.for_season(season))
	var closed := bool(clock.call("is_closed"))
	var quiet := bool(clock.call("is_quiet_hours"))
	_set_icon(_time_icon, "night" if closed or quiet else "day")
	var tier := Campaign.crew_tier()
	if tier != _shown_tier:
		_set_icon(_rank_badge, _Icons.for_rank(tier))
		# A rank-up in the middle of a session pops the badge (not the first fill).
		if _shown_tier >= 0:
			_Look.pop(_rank_badge)
		_shown_tier = tier
	_rank_label.text = _Strings.UI["hud_rank"] % _Ranks.title(tier)
	var need := float(_Ranks.xp_for_tier(tier))
	var into := float(_Ranks.xp_into_tier(Campaign.crew_xp()))
	var pending := float(Campaign.pending_xp())
	_bar_banked.size.x = BAR_WIDTH * clampf(into / need, 0.0, 1.0)
	_bar_pending.size.x = BAR_WIDTH * clampf((into + pending) / need, 0.0, 1.0)
	_xp_label.text = _Strings.UI["hud_xp"] % [int(into), int(need), int(pending)]
	var note := ""
	var color := NOTE_COLOR_QUIET
	if closed:
		note = _Strings.UI["hud_closed"]
		color = NOTE_COLOR_CLOSED
	elif quiet:
		note = _Strings.UI["hud_quiet_hours"] % int(round(float(clock.call("pay_bonus")) * 100.0))
	var unread := int(phone.call("unread")) if phone != null else 0
	if unread > 0:
		note = (_Strings.UI["hud_unread"] % unread) + ("\n" + note if note != "" else "")
		color = NOTE_COLOR_UNREAD
	_show_note(note, color)


## The note line, rebuilt only when its words or color change.
func _show_note(note: String, color: Color) -> void:
	var key := "%s|%s" % [note, color.to_html()]
	if key == _shown_note:
		return
	_shown_note = key
	_note.add_theme_color_override("default_color", color)
	_note.text = "[right]%s[/right]" % _Icons.rich(note, NOTE_ICON_PX) if note != "" else ""


## Points an icon at id, only when it changes (textures are cached by Icons).
func _set_icon(icon: TextureRect, id: String) -> void:
	if str(icon.get_meta("icon", "")) == id:
		return
	icon.texture = _Icons.texture(id)
	icon.set_meta("icon", id)


func _icon(px: float) -> TextureRect:
	var view := TextureRect.new()
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.custom_minimum_size = Vector2(px, px)
	view.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return view


func _label(size: int, color: Color, parent: Node = self) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _rect(color: Color, at: Vector2, size_of: Vector2) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.position = at
	rect.size = size_of
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rank_block.add_child(rect)
	return rect
