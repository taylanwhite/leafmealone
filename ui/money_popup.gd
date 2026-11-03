extends Label3D

## Authority: local, cosmetic. A "+$9" that pops up, floats, and fades where money
## was made: a bag filled, bags loaded into the truck, the homeowner's cash taken.
## The cash icon (ui/icons.gd) spins to its left like a tossed coin (icons chunk F).

const _Strings = preload("res://ui/strings.gd")
const _Icons = preload("res://ui/icons.gd")
const RISE_METERS: float = 1.2
const LIFE_SECONDS: float = 1.6
const GREEN := Color(0.55, 1.0, 0.45)
const LABEL_PIXEL_SIZE: float = 0.0022

## The coin is a quad drawn the way a fixed-size billboard Label3D is (so it sits
## with the text at any distance), with its spin and its place beside the text
## done in the vertex shader from per-instance values. A Sprite3D can't do it: its
## offset only reaches the screen a frame after its scale, so a coin spinning by
## scale and held in place by offset/scale swung out and back every half turn.
const COIN_SHADER := """
shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, blend_mix, depth_draw_never;

uniform sampler2D coin : source_color, filter_linear_mipmap;
instance uniform float spin = 1.0;
instance uniform float alpha = 1.0;
instance uniform float shift = 0.0;

void vertex() {
	// A coin turning about its upright, beside the text, in the label's own units.
	VERTEX.x = VERTEX.x * spin + shift;
	// Billboard, keeping the popup's own pop scale, then fixed size on screen, as
	// BaseMaterial3D does for Label3D.
	float grow = length(MODEL_MATRIX[1].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX *= grow;
	if (PROJECTION_MATRIX[3][3] != 0.0) {
		float h = abs(1.0 / (2.0 * PROJECTION_MATRIX[1][1]));
		MODELVIEW_MATRIX[0] *= h * 2.0;
		MODELVIEW_MATRIX[1] *= h * 2.0;
		MODELVIEW_MATRIX[2] *= h * 2.0;
	} else {
		float sc = -(MODELVIEW_MATRIX)[3].z;
		MODELVIEW_MATRIX[0] *= sc;
		MODELVIEW_MATRIX[1] *= sc;
		MODELVIEW_MATRIX[2] *= sc;
	}
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec4 texel = texture(coin, UV);
	ALBEDO = texel.rgb;
	ALPHA = texel.a * alpha;
}
"""

static var _coin_shader: Shader

var _age: float = 0.0
var _start := Vector3.ZERO
var _coin: MeshInstance3D


## Pop "+$amount" at a world position, under the world node so it lives with the scene.
## ping false leaves out the coin, for money that makes its own sound (the
## homeowner's cash being snatched).
static func pop(tree: SceneTree, at: Vector3, amount: int, ping: bool = true) -> void:
	if amount <= 0:
		return
	# A coin's ping where the money was made (audio:5), heard by whoever is near.
	var sfx := tree.get_first_node_in_group("sfx") if ping else null
	if sfx != null:
		sfx.call("play_at", "coin", at)
	if Net.is_automated():
		return
	var world := tree.get_first_node_in_group("world") as Node3D
	if world == null:
		return
	var popup: Label3D = load("res://ui/money_popup.gd").new()
	popup.text = str(_Strings.UI["popup_cash"]) % amount
	world.add_child(popup)
	popup.global_position = at
	popup._start = at


func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	fixed_size = true
	pixel_size = LABEL_PIXEL_SIZE
	font_size = 34
	outline_size = 10
	modulate = GREEN
	outline_modulate = Color(0.05, 0.15, 0.05)
	no_depth_test = true
	render_priority = 12
	_add_coin()


## The coin: ICONS_COIN_PX of the label's pixels tall, just left of the text.
func _add_coin() -> void:
	var cash := _Icons.texture("cash")
	if cash == null:
		return
	if _coin_shader == null:
		_coin_shader = Shader.new()
		_coin_shader.code = COIN_SHADER
	var material := ShaderMaterial.new()
	material.shader = _coin_shader
	material.set_shader_parameter("coin", cash)
	material.render_priority = render_priority
	var quad := QuadMesh.new()
	var tall := Constants.ICONS_COIN_PX * LABEL_PIXEL_SIZE
	quad.size = Vector2(tall * float(cash.get_width()) / maxf(1.0, float(cash.get_height())), tall)
	_coin = MeshInstance3D.new()
	_coin.name = "Coin"
	_coin.mesh = quad
	_coin.material_override = material
	_coin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shown_font := font if font != null else ThemeDB.fallback_font
	var text_px := shown_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var shift := -(text_px * 0.5 + Constants.ICONS_COIN_GAP_PX) * LABEL_PIXEL_SIZE - quad.size.x * 0.5
	_coin.set_instance_shader_parameter("shift", shift)
	# The quad's bounds don't know the shader moves it: keep it from being culled.
	_coin.extra_cull_margin = absf(shift) + quad.size.x
	add_child(_coin)


func _process(delta: float) -> void:
	_age += delta
	var t := clampf(_age / LIFE_SECONDS, 0.0, 1.0)
	# Pops a little bigger first, then floats up and fades.
	var pop_scale := 1.0 + 0.4 * maxf(0.0, 1.0 - _age * 6.0)
	scale = Vector3.ONE * pop_scale
	global_position = _start + Vector3(0.0, RISE_METERS * (1.0 - pow(1.0 - t, 2.0)), 0.0)
	modulate.a = 1.0 - smoothstep(0.6, 1.0, t)
	outline_modulate.a = modulate.a
	if _coin != null:
		_coin.set_instance_shader_parameter("spin", coin_width(_age))
		_coin.set_instance_shader_parameter("alpha", modulate.a)
	if t >= 1.0:
		queue_free()


## How wide the coin looks this far into its spin (1 face on, never thinner than
## its rim).
static func coin_width(age: float) -> float:
	return maxf(absf(cos(age * Constants.ICONS_COIN_SPIN)), Constants.ICONS_COIN_EDGE_WIDTH)
