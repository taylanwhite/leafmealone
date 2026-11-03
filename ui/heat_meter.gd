extends Control

## Authority: local. The crew's heat (net/run_events/heat.gd) as a bar under the
## cash and cleanup lines: green when quiet, red when the NICE BOYS are a sure
## thing, with a nudge when it crosses the warning marks.

const _Strings = preload("res://ui/strings.gd")
const _Icons = preload("res://ui/icons.gd")
const WIDTH: float = 170.0
const HEIGHT: float = 12.0
const CAPTION_SECONDS: float = 4.0
## The siren in front of the title (icons chunk E), and where the bar starts under it.
const SIREN_PX: float = 20.0
const BAR_Y: float = 24.0

var _fill: ColorRect
var _siren: Control
var _caption: Label
var _caption_left: float = 0.0
var _shown: float = 0.0
var _warned: int = -1
## Whether _warned has had a first reading (heat already high on joining doesn't whoop).
var _read: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := Label.new()
	title.text = _Strings.UI["hud_heat"]
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_shadow_color", Color.BLACK)
	title.add_theme_constant_override("shadow_offset_x", 1)
	title.add_theme_constant_override("shadow_offset_y", 1)
	var row := _Icons.row("heat", title, SIREN_PX)
	add_child(row)
	_siren = row.get_child(0) as Control
	var back := ColorRect.new()
	back.color = Color(0.0, 0.0, 0.0, 0.45)
	back.position = Vector2(0, BAR_Y)
	back.size = Vector2(WIDTH, HEIGHT)
	add_child(back)
	_fill = ColorRect.new()
	_fill.position = Vector2(1, BAR_Y + 1.0)
	_fill.size = Vector2(0, HEIGHT - 2)
	add_child(_fill)
	_caption = Label.new()
	_caption.position = Vector2(0, BAR_Y + HEIGHT + 2.0)
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
	var phase := Time.get_ticks_msec() / 1000.0 * Constants.ICONS_SIREN_SPEED
	if share > Constants.ICONS_SIREN_FROM:
		_fill.modulate.a = 0.7 + 0.3 * sin(phase)
	else:
		_fill.modulate.a = 1.0
	# The siren rocks on its center in time with the bar's pulse, easing in past the
	# mark and settling back as the heat drops, never snapping.
	var rock := clampf((share - Constants.ICONS_SIREN_FROM) / Constants.ICONS_SIREN_RAMP, 0.0, 1.0)
	_siren.pivot_offset = _siren.size * 0.5
	_siren.rotation = sin(phase) * Constants.ICONS_SIREN_ROCK_RAD * rock
	# A word when it crosses a warning mark on the way up.
	var level := -1
	for index: int in Constants.HEAT_WARN_AT.size():
		if value >= float(Constants.HEAT_WARN_AT[index]):
			level = index
	if level > _warned:
		_caption.text = _Strings.UI["heat_warn_%d" % level]
		_caption.visible = true
		_caption_left = CAPTION_SECONDS
		# A little cartoon siren, this player's own (audio:5).
		var sfx := get_tree().get_first_node_in_group("sfx") if _read else null
		if sfx != null:
			sfx.call("play", "heat_whoop")
	_warned = level
	_read = true
	if _caption_left > 0.0:
		_caption_left -= delta
		if _caption_left <= 0.0:
			_caption.visible = false
