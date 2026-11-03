extends CanvasLayer

## Authority: local, cosmetic only. Warning and foreshadow cues for each run
## event phase. Everything is timed from the phase's server-time start, so every
## peer on the lot hears the radio and sees the flare at the same moment without
## extra network traffic. Only players on the lot get them. OQ-009, OQ-010: the
## cues are one replaceable presenter.
##
## R2 (docs/GAME.md, "The NICE BOYS encounter"): no countdown digits and no
## "they're here, run" line. The radio crackle, the flare at the curb where the
## van will park, the horn and the van pulling up are the warning; the arrival is
## the van itself. The radio line goes through the caption stack
## (ui/caption_stack.gd) and follows the player's caption settings. "All clear"
## only plays when nobody was taken.

const _Strings = preload("res://ui/strings.gd")
const _BeaconScript = preload("res://npcs/arrival_beacon.gd")
const _QuipPlayer = preload("res://ui/quip_player.gd")
## The cue caption's font size at the normal caption size (the stack sizes it by
## Settings.caption_scale(); kept here for the tests that compare sizes).
const CAPTION_FONT_SIZE: int = 22
const CAPTION_SECONDS: float = 3.5
const WARNING_TINT := Color(1.0, 0.62, 0.12)
const CHASE_TINT := Color(0.95, 0.22, 0.16)
const CLEAR_TINT := Color(0.35, 0.85, 0.45)
## The edge vignette's strongest pulse (presentation): a tint at the edges of
## your eyes, not a red screen.
const VIGNETTE_PEAK: float = 0.12
## R2b: only the rim of the screen (a rounded rectangle from inner out to the
## edge, the corners deepest); the middle of the view is never tinted, so the
## CHASE flash is a pulse at the edges, not a pink screen.
const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(1.0);
uniform float strength = 0.0;
uniform float inner = 0.7;
void fragment() {
	vec2 q = abs(UV - vec2(0.5)) * 2.0;
	float d = pow(pow(q.x, 4.0) + pow(q.y, 4.0), 0.25);
	float edge = smoothstep(inner, 1.12, d);
	COLOR = vec4(tint.rgb, edge * edge * strength);
}
"""

## Cue moments for this process, read by net/dev/probe.gd: phase, and how late
## after the phase's server-time start this peer showed it, in milliseconds.
static var log: Array[Dictionary] = []

var _vignette: ColorRect
var _material: ShaderMaterial
var _seen_started: float = -1.0
var _seen_phase: int = 0
var _flash: float = 0.0
var _beacon: Node3D
## The director's cohort_id when the NICE BOYS arrived (-1 before any raid):
## it moves only when they take somebody, on every peer.
var _raid_cohort_id: int = -1
## The caption stack line the radio is on (0 = none).
var _caption_id: int = 0


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
	_material.set_shader_parameter("inner", Constants.R2B_HUD_VIGNETTE_INNER)
	add_child(_vignette)


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
	_flash = maxf(0.0, _flash - delta * 1.6)
	if not on_lot:
		_set_strength(0.0)
		_clear_beacon()
		return
	match phase:
		1:
			_warning_frame(float(director.call("arrival_time")))
		2, 3:
			_material.set_shader_parameter("tint", CHASE_TINT)
			_set_strength(VIGNETTE_PEAK * (0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.006)) + _flash * 0.18)
		_:
			_set_strength(_flash * 0.3)


func _enter_phase(director: Node, phase: int, previous: int, started: float) -> void:
	log.append({"phase": phase, "late_ms": (Net.server_time() - started) * 1000.0})
	match phase:
		1:
			_play("warning")
			_play("radio")
			_show_caption(cue_line("radio", started))
			_clear_beacon()
			_beacon = _BeaconScript.new()
			_beacon.name = "ArrivalBeacon"
			get_tree().get_first_node_in_group("world").add_child(_beacon)
			# The flare goes up where the van will really park.
			_beacon.global_position = director.call("van_park_point")
			# Just ahead of its nose, not under its body (R2c van).
			var shuttle := get_tree().get_first_node_in_group("nice_shuttle")
			if shuttle != null and shuttle.has_method("flare_point"):
				_beacon.global_position = shuttle.call("flare_point")
		2:
			_raid_cohort_id = _cohort_id_of(director)
			_clear_beacon()
			_play("arrive")
			_flash = 1.0
		3:
			pass
		_:
			_clear_beacon()
			if (previous == 2 or previous == 3) and _nobody_taken(director, _raid_cohort_id):
				_play("clear")
				_show_caption(cue_line("clear", started))
				_material.set_shader_parameter("tint", CLEAR_TINT)
				_flash = 1.0


## Nobody caught in the raid that just ended: the cohort id (one more per catch,
## on every peer) hasn't moved since they arrived. Not the cohort's size: a
## teammate still at the Annex from an earlier raid is in it. Not the director's
## last_raid_caught(): that count is the host's alone, and a client would hear
## "All clear" after every raid (R2 integration).
static func _nobody_taken(director: Node, cohort_at_arrival: int) -> bool:
	if cohort_at_arrival < 0:
		return false
	return _cohort_id_of(director) == cohort_at_arrival


static func _cohort_id_of(director: Node) -> int:
	return int(director.call("cohort_id")) if director.has_method("cohort_id") else 0


func _warning_frame(arrival: float) -> void:
	var left := arrival - Net.server_time()
	var progress := clampf(1.0 - left / Constants.RUN_WARNING_SECONDS, 0.0, 1.0)
	# The pulse speeds up and deepens as the crew gets closer.
	var rate := lerpf(2.0, 9.0, progress)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * rate)
	_material.set_shader_parameter("tint", WARNING_TINT)
	_set_strength(VIGNETTE_PEAK * (0.35 + 0.65 * progress) * pulse)
	if _beacon != null:
		_beacon.call("set_urgency", progress)


## The caption for a cue (Strings.CUE_LINES), picked from the phase's server-time
## start, which every peer has, so they all show the same line.
static func cue_line(kind: String, started: float) -> String:
	return _Strings.pick_seeded(_Strings.CUE_LINES.get(kind, []), int(started * 1000.0))


## A radio line on the caption stack (captions off: it isn't shown).
func _show_caption(text: String) -> void:
	var stack := get_tree().get_first_node_in_group("caption_stack")
	if stack == null:
		return
	if _caption_id != 0:
		stack.call("drop", _caption_id)
	_caption_id = int(stack.call("push", &"radio", text, CAPTION_SECONDS, 1))


func _set_strength(value: float) -> void:
	# R2b: once the moment has you (caught, held, in the van) the chase pulse is
	# over for you; it eases out with the yard HUD.
	var ui := get_parent()
	if ui != null and ui.has_method("yard_hud_alpha"):
		value *= float(ui.call("yard_hud_alpha"))
	_material.set_shader_parameter("strength", clampf(value, 0.0, 1.0))
	_vignette.visible = value > 0.001


func _play(sound_name: String) -> void:
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play", sound_name)


## The beacon folds itself away (npcs/arrival_beacon.gd dismiss) rather than vanishing.
func _clear_beacon() -> void:
	if is_instance_valid(_beacon):
		if _beacon.has_method("dismiss"):
			_beacon.call("dismiss")
		else:
			_beacon.queue_free()
	_beacon = null
