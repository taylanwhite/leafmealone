extends CanvasLayer

## Authority: local, cosmetic (owner-local: other peers never see yours). The
## iris (R2 contract C5, group "iris"): the screen closes down to a Daisy Seal
## rosette (props/nice_seal.gd's scalloped edge and petals, drawn by a shader),
## sweeps shut like a door, or fades, and opens again. Anything that has to cut
## the camera or move a player across the map does it while this is closed, so a
## cut is never seen. Times are server times, so a beat sent ahead plays on time.
##
##   iris.close(at, seconds := IRIS_CLOSE, shape := &"seal")   # &"seal", &"door", &"fade"
##   iris.open(at, seconds := IRIS_OPEN)
##   iris.is_closed() / closed_since()
##
## It stays shut at least Constants.IRIS_HOLD_MIN, so a quick open never
## flickers. Above the HUD, below the pause buttons and Settings (it drops under
## them while they're up). Sound never pauses across it: only iris_swish plays.

const _NiceSeal = preload("res://props/nice_seal.gd")
const SHAPES: Array[StringName] = [&"seal", &"door", &"fade"]
## Draw order: over the HUD (UIRoot is layer 1), under the run cues' vignette (5);
## under everything while a menu is up.
const LAYER_OVER_HUD: int = 4
const LAYER_UNDER_MENUS: int = 0
const SHADER := """
shader_type canvas_item;
uniform float amount = 0.0;
uniform int shape = 0;
uniform vec2 aspect = vec2(1.7778, 1.0);
uniform vec4 fill : source_color = vec4(0.5, 0.4, 0.84, 1.0);
uniform vec4 ring : source_color = vec4(0.98, 0.98, 0.95, 1.0);
uniform vec4 petal : source_color = vec4(0.98, 0.98, 0.95, 1.0);
uniform vec4 middle : source_color = vec4(0.98, 0.82, 0.25, 1.0);
uniform vec4 door : source_color = vec4(0.36, 0.25, 0.17, 1.0);

float scallop(float angle) {
	return 0.8 + 0.2 * sqrt(abs(cos(angle * 6.0)));
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * aspect;
	float a = clamp(amount, 0.0, 1.0);
	if (shape == 2) {
		COLOR = vec4(fill.rgb * 0.35, a);
	} else if (shape == 1) {
		// A door swinging shut from the right: its edge sweeps left, darker near the hinge.
		float edge = 1.0 - a * 1.02;
		float inside = step(edge, UV.x);
		float shade = mix(0.75, 1.0, smoothstep(edge, 1.0, UV.x));
		vec3 c = door.rgb * shade;
		float lip = smoothstep(edge, edge + 0.012, UV.x) * (1.0 - smoothstep(edge + 0.012, edge + 0.02, UV.x));
		c = mix(c, door.rgb * 0.45, lip);
		// Two inset panels and a brass knob that ride in with the door's leading edge.
		float dx = UV.x - edge;
		vec2 q = vec2(dx * aspect.x, UV.y);
		float panel_top = step(0.18, q.x) * step(q.x, 0.82) * step(0.1, q.y) * step(q.y, 0.44);
		float panel_low = step(0.18, q.x) * step(q.x, 0.82) * step(0.56, q.y) * step(q.y, 0.9);
		c = mix(c, c * 0.82, max(panel_top, panel_low));
		float knob = 1.0 - smoothstep(0.022, 0.028, length(q - vec2(0.09, 0.52)));
		c = mix(c, vec3(0.85, 0.68, 0.3), knob);
		COLOR = vec4(c, inside);
	} else {
		// The hole: a scalloped rosette shrinking to nothing; the rest is the seal's lavender.
		float r = length(p);
		float ang = atan(p.y, p.x);
		float hole = (1.0 - a) * 1.25 * scallop(ang);
		float covered = smoothstep(hole - 0.004, hole + 0.004, r);
		vec3 c = fill.rgb;
		// The white stitched ring just outside the hole.
		float band = smoothstep(hole + 0.006, hole + 0.012, r) * (1.0 - smoothstep(hole + 0.022, hole + 0.03, r));
		c = mix(c, ring.rgb, band * step(0.02, hole));
		// Shut: a little daisy in the middle, petals and a yellow center.
		float shut = smoothstep(0.92, 1.0, a);
		float pr = 0.16 * shut;
		if (pr > 0.001) {
			float k = ang - 1.5707963;
			float petals = abs(cos(k * 3.0));
			float flower = step(r, pr * (0.35 + 0.65 * petals));
			c = mix(c, petal.rgb, flower);
			c = mix(c, middle.rgb, step(r, pr * 0.3));
		}
		COLOR = vec4(c, covered);
	}
}
"""

var _rect: ColorRect
var _material: ShaderMaterial
var _shape: StringName = &"seal"
## The close in progress: when it starts and how long it takes. INF = open.
var _close_at: float = INF
var _close_seconds: float = 0.35
## The open after it, INF while none is due.
var _open_at: float = INF
var _open_seconds: float = 0.35
var _swished_close: bool = true
var _swished_open: bool = true

## For the probe and stage_test: every close and open this process played.
static var log: Array[Dictionary] = []


func _ready() -> void:
	add_to_group("iris")
	layer = LAYER_OVER_HUD
	_rect = ColorRect.new()
	_rect.name = "Mask"
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("fill", _NiceSeal.ROSETTE)
	_material.set_shader_parameter("ring", _NiceSeal.PETAL)
	_material.set_shader_parameter("petal", _NiceSeal.PETAL)
	_material.set_shader_parameter("middle", _NiceSeal.CENTER)
	_rect.material = _material
	_rect.visible = false
	add_child(_rect)


## Start closing at server time `at` over `seconds`, in a shape.
func close(at: float, seconds: float = Constants.IRIS_CLOSE, shape: StringName = &"seal") -> void:
	_shape = shape if SHAPES.has(shape) else &"seal"
	# Closing while part shut carries on from where it is, not from wide open.
	var now := Net.server_time()
	var shown := amount_at(now)
	_close_seconds = maxf(0.01, seconds)
	_close_at = at - shown * _close_seconds if shown > 0.0 and at <= now else at
	_open_at = INF
	_swished_close = false
	log.append({"op": "close", "at": at, "seconds": seconds, "shape": String(_shape)})


## Start opening at server time `at` (never sooner than IRIS_HOLD_MIN after it shut).
func open(at: float, seconds: float = Constants.IRIS_OPEN) -> void:
	if _close_at == INF:
		return
	_open_seconds = maxf(0.01, seconds)
	_open_at = maxf(at, _close_at + _close_seconds + Constants.IRIS_HOLD_MIN)
	_swished_open = false
	log.append({"op": "open", "at": _open_at, "seconds": seconds})


## Let go of a close that's no longer wanted (R2b: freed mid-boarding): one
## that hasn't started yet is dropped and never shows; one under way or shut
## opens again, as open() would.
func release(at: float, seconds: float = Constants.IRIS_OPEN) -> void:
	if _close_at == INF:
		return
	if _open_at == INF and Net.server_time() < _close_at:
		_close_at = INF
		_swished_close = true
		log.append({"op": "release", "at": at})
		return
	open(at, seconds)


## Fully shut right now.
func is_closed() -> bool:
	return amount_at(Net.server_time()) >= 1.0


## The server time it finished closing, or INF while it isn't shut.
func closed_since() -> float:
	return _close_at + _close_seconds if is_closed() else INF


## How shut it is at a server time, 0 open to 1 closed.
func amount_at(now: float) -> float:
	if _close_at == INF or now < _close_at:
		return 0.0
	var shut := clampf((now - _close_at) / _close_seconds, 0.0, 1.0)
	if _open_at != INF and now >= _open_at:
		var opened := clampf((now - _open_at) / _open_seconds, 0.0, 1.0)
		return shut * (1.0 - opened)
	return shut


func _process(_delta: float) -> void:
	var now := Net.server_time()
	var shown := amount_at(now)
	if not _swished_close and now >= _close_at:
		_swished_close = true
		_swish(_close_at)
	if not _swished_open and _open_at != INF and now >= _open_at:
		_swished_open = true
		_swish(_open_at)
	if _open_at != INF and now >= _open_at + _open_seconds:
		# All the way open again: forget it.
		_close_at = INF
		_open_at = INF
	_rect.visible = shown > 0.0
	if _rect.visible:
		var view := get_viewport().get_visible_rect().size
		_material.set_shader_parameter("aspect", Vector2(view.x / maxf(1.0, view.y), 1.0))
		_material.set_shader_parameter("amount", _ease(shown))
		_material.set_shader_parameter("shape", SHAPES.find(_shape))
	var ui := get_tree().get_first_node_in_group("game_ui")
	var menu_up := ui != null and (bool(ui.call("pause_open")) or bool(ui.call("any_window_open")))
	layer = LAYER_UNDER_MENUS if menu_up else LAYER_OVER_HUD


## Ease in and out, so it gathers speed and settles shut.
func _ease(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


func _swish(at: float) -> void:
	if Net.server_time() - at > Constants.BEAT_SKIP:
		return
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play", "iris_swish")
