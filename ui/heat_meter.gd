extends Control

## Authority: local. The crew's heat (net/run_events/heat.gd) as a bar under the
## cash and cleanup lines: green when quiet, red when the NICE BOYS are a sure
## thing, with a nudge when it crosses the warning marks.

const _Strings = preload("res://ui/strings.gd")
const WIDTH: float = 170.0
const HEIGHT: float = 12.0
const CAPTION_SECONDS: float = 4.0

var _fill: ColorRect
var _caption: Label
var _caption_left: float = 0.0
var _shown: float = 0.0
var _warned: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := Label.new()
	title.text = _Strings.UI["hud_heat"]
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_shadow_color", Color.BLACK)
	title.add_theme_constant_override("shadow_offset_x", 1)
	title.add_theme_constant_override("shadow_offset_y", 1)
	add_child(title)
	var back := ColorRect.new()
	back.color = Color(0.0, 0.0, 0.0, 0.45)
	back.position = Vector2(0, 20)
	back.size = Vector2(WIDTH, HEIGHT)
	add_child(back)
	_fill = ColorRect.new()
	_fill.position = Vector2(1, 21)
	_fill.size = Vector2(0, HEIGHT - 2)
	add_child(_fill)
	_caption = Label.new()
	_caption.position = Vector2(0, 34)
	_caption.add_theme_font_size_override("font_size", 13)
	_caption.add_theme_color_override("font_color", Color(1.0, 0.85, 0.6))
	_caption.add_theme_color_override("font_shadow_color", Color.BLACK)
	_caption.add_theme_constant_override("shadow_offset_x", 1)
	_caption.add_theme_constant_override("shadow_offset_y", 1)
	_caption.visible = false
	add_child(_caption)


func _process(delta: float) -> void:
	var heat := get_tree().get_first_node_in_group("heat")
	visible = heat != null and Net.current_state() == Net.State.IN_SESSION
	if not visible:
		return
	# Bottom left, clear of the job list and the hints.
	position = Vector2(16.0, get_viewport_rect().size.y - 118.0)
	var value := float(heat.get("heat"))
	_shown = lerpf(_shown, value, 1.0 - exp(-6.0 * delta))
	_fill.size.x = (WIDTH - 2.0) * _shown / 100.0
	var share := _shown / 100.0
	_fill.color = Color(0.3, 0.8, 0.3).lerp(Color(0.95, 0.75, 0.2), clampf(share * 2.0, 0.0, 1.0)).lerp(Color(0.9, 0.2, 0.15), clampf(share * 2.0 - 1.0, 0.0, 1.0))
	if share > 0.8:
		_fill.modulate.a = 0.7 + 0.3 * sin(Time.get_ticks_msec() / 1000.0 * 8.0)
	else:
		_fill.modulate.a = 1.0
	# A word when it crosses a warning mark on the way up.
	var level := -1
	for index: int in Constants.HEAT_WARN_AT.size():
		if value >= float(Constants.HEAT_WARN_AT[index]):
			level = index
	if level > _warned:
		_caption.text = _Strings.UI["heat_warn_%d" % level]
		_caption.visible = true
		_caption_left = CAPTION_SECONDS
	_warned = level
	if _caption_left > 0.0:
		_caption_left -= delta
		if _caption_left <= 0.0:
			_caption.visible = false
