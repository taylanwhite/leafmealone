extends CanvasLayer

## Authority: local, cosmetic only. Warning and foreshadow cues for each run
## event phase. Everything is timed from the phase's server-time start, so every
## peer on the lot hears the radio, sees the countdown, and gets the arrival at
## the same moment without extra network traffic. Only players on the lot get
## them. OQ-009, OQ-010: the cues are one replaceable presenter.

const _Strings = preload("res://ui/strings.gd")
const _BeaconScript = preload("res://npcs/arrival_beacon.gd")
## Seconds before arrival that the countdown shows and ticks.
const COUNTDOWN_SECONDS: int = 5
const CAPTION_SECONDS: float = 3.5
const WARNING_TINT := Color(1.0, 0.62, 0.12)
const CHASE_TINT := Color(0.95, 0.22, 0.16)
const CLEAR_TINT := Color(0.35, 0.85, 0.45)
const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(1.0);
uniform float strength = 0.0;
void fragment() {
	float edge = smoothstep(0.35, 0.8, length(UV - vec2(0.5)) * 1.45);
	COLOR = vec4(tint.rgb, edge * strength);
}
"""

## Cue moments for this process, read by net/dev/probe.gd: phase, and how late
## after the phase's server-time start this peer showed it, in milliseconds.
static var log: Array[Dictionary] = []

var _vignette: ColorRect
var _material: ShaderMaterial
var _caption: Label
var _countdown: Label
var _seen_started: float = -1.0
var _seen_phase: int = 0
var _caption_left: float = 0.0
var _flash: float = 0.0
var _last_tick: int = -1
var _beacon: Node3D


func _ready() -> void:
	layer = 5
	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = VIGNETTE_SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	_vignette.material = _material
	add_child(_vignette)
	_caption = _label(28, Control.PRESET_CENTER_TOP, 90.0)
	_countdown = _label(96, Control.PRESET_CENTER, -140.0)


func _label(size: int, preset: Control.LayoutPreset, offset_y: float) -> Label:
	var label := Label.new()
	label.set_anchors_and_offsets_preset(preset)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.position.y += offset_y
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 10)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func _process(delta: float) -> void:
	var director := get_tree().get_first_node_in_group("run_director")
	var on_lot := Net.player_zone(Net.local_peer_id()) == Net.Zone.LOT
	if director == null or Net.current_state() != Net.State.IN_SESSION:
		_set_strength(0.0)
		return
	var phase := int(director.call("phase"))
	var started := float(director.call("phase_started_at"))
	if started != _seen_started or phase != _seen_phase:
		var previous := _seen_phase
		_seen_started = started
		_seen_phase = phase
		# Quiet to quiet is just the first frame, not a cue.
		if on_lot and not (phase == 0 and previous == 0):
			_enter_phase(director, phase, previous, started)
	_caption_left = maxf(0.0, _caption_left - delta)
	_caption.visible = _caption_left > 0.0
	_flash = maxf(0.0, _flash - delta * 1.6)
	if not on_lot:
		_countdown.visible = false
		_set_strength(0.0)
		_clear_beacon()
		return
	match phase:
		1:
			_warning_frame(float(director.call("arrival_time")))
		2:
			_countdown.visible = false
			_material.set_shader_parameter("tint", CHASE_TINT)
			_set_strength(0.1 + 0.06 * sin(Time.get_ticks_msec() * 0.006) + _flash * 0.5)
		_:
			_countdown.visible = false
			_set_strength(_flash * 0.35)


func _enter_phase(director: Node, phase: int, previous: int, started: float) -> void:
	log.append({"phase": phase, "late_ms": (Net.server_time() - started) * 1000.0})
	match phase:
		1:
			_play("warning")
			_play("radio")
			_show_caption(_Strings.UI["cue_radio"])
			_last_tick = -1
			_clear_beacon()
			_beacon = _BeaconScript.new()
			_beacon.name = "ArrivalBeacon"
			get_tree().get_first_node_in_group("world").add_child(_beacon)
			_beacon.global_position = director.call("crew_arrival_point")
		2:
			_clear_beacon()
			_play("arrive")
			_show_caption(_Strings.UI["cue_arrived"])
			_flash = 1.0
		_:
			_clear_beacon()
			if previous == 2:
				_play("clear")
				_show_caption(_Strings.UI["cue_clear"])
				_material.set_shader_parameter("tint", CLEAR_TINT)
				_flash = 1.0


func _warning_frame(arrival: float) -> void:
	var left := arrival - Net.server_time()
	var progress := clampf(1.0 - left / Constants.RUN_WARNING_SECONDS, 0.0, 1.0)
	# The pulse speeds up and deepens as the crew gets closer.
	var rate := lerpf(2.0, 9.0, progress)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * rate)
	_material.set_shader_parameter("tint", WARNING_TINT)
	_set_strength((0.12 + 0.38 * progress) * pulse)
	var whole := int(ceil(left))
	_countdown.visible = whole >= 1 and whole <= COUNTDOWN_SECONDS
	if _countdown.visible:
		_countdown.text = _Strings.UI["cue_countdown"] % whole
		if whole != _last_tick:
			_last_tick = whole
			_play("tick")
	if _beacon != null:
		_beacon.call("set_urgency", progress)


func _show_caption(text: String) -> void:
	_caption.text = text
	_caption_left = CAPTION_SECONDS


func _set_strength(value: float) -> void:
	_material.set_shader_parameter("strength", clampf(value, 0.0, 1.0))
	_vignette.visible = value > 0.001


func _play(sound_name: String) -> void:
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play", sound_name)


func _clear_beacon() -> void:
	if is_instance_valid(_beacon):
		_beacon.queue_free()
	_beacon = null
