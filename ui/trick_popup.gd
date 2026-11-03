extends Control

## Authority: local. The Gutter Shredder's trick line (driving chunk G1;
## player/skate.gd calls show_line on your own landings and bails): centered near
## the top, it pops in big, settles, holds, and fades. "KICKFLIP + 360 ×2 = 800"
## in warm paper; a bail's line in red. Bragging only: nothing else reads it.

const _UiStyle = preload("res://ui/ui_style.gd")
const GOOD := Color(1.0, 0.86, 0.42)
const BAD := Color(1.0, 0.42, 0.32)
const FONT_SIZE: int = 34
## Where its top sits (px): below the FPS readout at the top center
## and clear of the day HUD and rank badge on the right (gap-specs/critic.md: the trick popup at y 80).
const TOP_Y: float = 80.0
## The pop: starts this much bigger and settles over POP_SECONDS; fades over the last FADE_SECONDS.
const POP_SCALE: float = 1.45
const POP_SECONDS: float = 0.18
const FADE_SECONDS: float = 0.45

var _label: Label
var _age: float = -1.0
var _life: float = 0.0


func _ready() -> void:
	add_to_group("trick_popup")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = _UiStyle.text("", FONT_SIZE, GOOD)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_constant_override("outline_size", 10)
	_label.add_theme_color_override("font_outline_color", Color(0.12, 0.08, 0.05))
	add_child(_label)
	visible = false


## Show a line: good for a landed trick, false for a bail.
func show_line(text: String, good: bool) -> void:
	_label.text = text
	_label.add_theme_color_override("font_color", GOOD if good else BAD)
	_label.reset_size()
	_age = 0.0
	_life = Constants.SKATE_POPUP_SECONDS
	visible = true
	_place(POP_SCALE)


## What's showing now ("" when nothing), for tests and the recorder.
func showing() -> String:
	return _label.text if visible else ""


func _process(delta: float) -> void:
	if _age < 0.0:
		return
	_age += delta
	if _age >= _life:
		_age = -1.0
		visible = false
		return
	var pop := clampf(_age / POP_SECONDS, 0.0, 1.0)
	# Overshoots a touch on the way down to size, like a stamp.
	var grow := lerpf(POP_SCALE, 1.0, 1.0 - pow(1.0 - pop, 3.0)) - 0.06 * sin(PI * pop)
	_place(grow)
	modulate.a = 1.0 - smoothstep(_life - FADE_SECONDS, _life, _age)


func _place(grow: float) -> void:
	var screen := get_viewport_rect().size
	var size_now := _label.get_combined_minimum_size()
	_label.pivot_offset = size_now * 0.5
	_label.scale = Vector2.ONE * grow
	_label.position = Vector2(screen.x * 0.5 - size_now.x * 0.5, TOP_Y)
