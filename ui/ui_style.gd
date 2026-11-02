extends RefCounted

## Local presentation. The shared UI kit for new windows: the Homie Depot
## catalog look of ui/shop_window.gd (paper card, ink text, orange accents) as
## static helpers, so every new window matches without copying private helpers.
## The older windows keep their own copies for now (critic.md gap 4 plans a
## global Theme built from this file). Static only; textures are drawn in code
## and cached.

const PAPER := Color(0.97, 0.93, 0.84)
const INK := Color(0.17, 0.14, 0.11)
const ORANGE := Color(0.93, 0.47, 0.13)
const CARD := Color(1.0, 0.98, 0.93)
## Inactive pills, quiet buttons and switch tracks that are off.
const SOFT := Color(0.585, 0.57, 0.555)
## Button text size, and how round a button's corners are.
const BUTTON_FONT: int = 18
const BUTTON_RADIUS: int = 10
## The switch drawn for check(): its size in pixels.
const SWITCH_SIZE := Vector2i(46, 26)
## The slider's grabber, a disk this many pixels across.
const GRABBER_SIZE: int = 22

static var _textures: Dictionary = {}


static func box(color: Color, radius: int, border: Color, border_width: int, margin := 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.border_color = border
	style.set_border_width_all(border_width)
	style.content_margin_left = margin + 4
	style.content_margin_right = margin + 4
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	return style


static func text(value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


## A solid button in color with white text.
static func button(value: String, color: Color) -> Button:
	var made := Button.new()
	made.text = value
	made.add_theme_font_size_override("font_size", BUTTON_FONT)
	paint_button(made, color)
	made.add_theme_color_override("font_color", Color.WHITE)
	made.add_theme_color_override("font_hover_color", Color.WHITE)
	made.add_theme_color_override("font_pressed_color", Color.WHITE)
	made.add_theme_color_override("font_focus_color", Color.WHITE)
	made.add_theme_color_override("font_disabled_color", Color(1.0, 1.0, 1.0, 0.7))
	return made


## Recolors a button made by button() or pill() (a pill that turns active).
static func paint_button(target: Button, color: Color) -> void:
	var edge := color.darkened(0.25)
	target.add_theme_stylebox_override("normal", box(color, BUTTON_RADIUS, edge, 0, 6))
	target.add_theme_stylebox_override("hover", box(color.lightened(0.12), BUTTON_RADIUS, edge, 0, 6))
	target.add_theme_stylebox_override("pressed", box(color.darkened(0.12), BUTTON_RADIUS, edge, 0, 6))
	target.add_theme_stylebox_override("hover_pressed", box(color.darkened(0.06), BUTTON_RADIUS, edge, 0, 6))
	target.add_theme_stylebox_override("disabled", box(color, BUTTON_RADIUS, edge, 0, 6))
	target.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), BUTTON_RADIUS, INK.lightened(0.2), 2, 6))


## A tab pill: orange when active, soft gray otherwise.
static func pill(value: String, active: bool) -> Button:
	var made := button(value, ORANGE if active else SOFT)
	made.add_theme_font_size_override("font_size", 17)
	set_pill(made, active)
	return made


static func set_pill(target: Button, active: bool) -> void:
	paint_button(target, ORANGE if active else SOFT)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var style := target.get_theme_stylebox(state) as StyleBoxFlat
		if style != null:
			style.set_corner_radius_all(16)
			style.content_margin_left = 18
			style.content_margin_right = 18


## A white card with ink text, for a key binding or a readout.
static func card_button(value: String) -> Button:
	var made := Button.new()
	made.text = value
	made.add_theme_font_size_override("font_size", 16)
	paint_card(made, false)
	return made


## A card button turns orange while it waits for a key.
static func paint_card(target: Button, listening: bool) -> void:
	var fill := ORANGE if listening else CARD
	var edge := ORANGE.darkened(0.2) if listening else INK.lightened(0.6)
	target.add_theme_stylebox_override("normal", box(fill, 8, edge, 2, 5))
	target.add_theme_stylebox_override("hover", box(fill.lightened(0.05) if listening else Color.WHITE, 8, ORANGE, 2, 5))
	target.add_theme_stylebox_override("pressed", box(fill.darkened(0.08), 8, ORANGE, 2, 5))
	target.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), 8, ORANGE.darkened(0.2), 2, 5))
	var ink := Color.WHITE if listening else INK
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		target.add_theme_color_override(state, ink)


static func slider(min_value: float, max_value: float, step: float) -> HSlider:
	var made := HSlider.new()
	made.min_value = min_value
	made.max_value = max_value
	made.step = step
	made.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	made.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var track := box(CARD, 5, INK.lightened(0.55), 2, 0)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	made.add_theme_stylebox_override("slider", track)
	var filled := box(ORANGE, 5, ORANGE.darkened(0.2), 2, 0)
	filled.content_margin_top = 4
	filled.content_margin_bottom = 4
	made.add_theme_stylebox_override("grabber_area", filled)
	made.add_theme_stylebox_override("grabber_area_highlight", filled)
	made.add_theme_icon_override("grabber", _disk(ORANGE, INK.lightened(0.1)))
	made.add_theme_icon_override("grabber_highlight", _disk(ORANGE.lightened(0.15), INK))
	made.add_theme_icon_override("grabber_disabled", _disk(SOFT, INK.lightened(0.3)))
	return made


## An on/off switch, drawn in the catalog colors so it reads on paper.
static func check() -> CheckButton:
	var made := CheckButton.new()
	made.focus_mode = Control.FOCUS_ALL
	made.add_theme_icon_override("checked", _switch(true))
	made.add_theme_icon_override("unchecked", _switch(false))
	made.add_theme_icon_override("checked_disabled", _switch(true))
	made.add_theme_icon_override("unchecked_disabled", _switch(false))
	made.add_theme_icon_override("checked_mirrored", _switch(true))
	made.add_theme_icon_override("unchecked_mirrored", _switch(false))
	var empty := StyleBoxEmpty.new()
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		made.add_theme_stylebox_override(state, empty)
	made.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return made


## A drop-down of items (texts), ink on a white card.
static func choice(items: PackedStringArray) -> OptionButton:
	var made := OptionButton.new()
	for item: String in items:
		made.add_item(item)
	made.add_theme_font_size_override("font_size", 16)
	made.add_theme_stylebox_override("normal", box(CARD, 8, INK.lightened(0.6), 2, 6))
	made.add_theme_stylebox_override("hover", box(Color.WHITE, 8, ORANGE, 2, 6))
	made.add_theme_stylebox_override("pressed", box(Color.WHITE, 8, ORANGE, 2, 6))
	made.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), 8, ORANGE.darkened(0.2), 2, 6))
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		made.add_theme_color_override(state, INK)
	# The drop arrow takes the font color, or it is white on white.
	made.add_theme_constant_override("modulate_arrow", 1)
	made.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return made


## A filled circle with a thin rim, as a grabber.
static func _disk(fill: Color, rim: Color) -> Texture2D:
	var key := "disk %s %s" % [fill.to_html(), rim.to_html()]
	if _textures.has(key):
		return _textures[key]
	var size := GRABBER_SIZE
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	var radius := size * 0.5 - 1.0
	for y: int in size:
		for x: int in size:
			var distance := (Vector2(x, y) + Vector2(0.5, 0.5)).distance_to(center)
			var inside := clampf(radius - distance + 0.5, 0.0, 1.0)
			var color := rim if distance > radius - 2.0 else fill
			color.a *= inside
			image.set_pixel(x, y, color)
	var texture := ImageTexture.create_from_image(image)
	_textures[key] = texture
	return texture


## A rounded track with a knob: orange with the knob right when on, soft gray left when off.
static func _switch(on: bool) -> Texture2D:
	var key := "switch %s" % on
	if _textures.has(key):
		return _textures[key]
	var size := SWITCH_SIZE
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	var half := size.y * 0.5
	var track := ORANGE if on else SOFT
	var knob_center := Vector2(size.x - half if on else half, half)
	for y: int in size.y:
		for x: int in size.x:
			var point := Vector2(x, y) + Vector2(0.5, 0.5)
			# Distance to the capsule's spine, from half to size.x - half at mid height.
			var spine := Vector2(clampf(point.x, half, size.x - half), half)
			var track_alpha := clampf(half - point.distance_to(spine) + 0.5, 0.0, 1.0)
			var knob_alpha := clampf(half - 3.0 - point.distance_to(knob_center) + 0.5, 0.0, 1.0)
			var color := track
			color.a = track_alpha
			if knob_alpha > 0.0:
				color = color.lerp(Color.WHITE, knob_alpha)
				color.a = maxf(track_alpha, knob_alpha)
			image.set_pixel(x, y, color)
	var texture := ImageTexture.create_from_image(image)
	_textures[key] = texture
	return texture
