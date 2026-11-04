extends MeshInstance3D

## Authority: local, cosmetic. The shared look's outline (docs/ART.md, "Unifying
## the look"): a full-screen pass that draws a dark line wherever depth jumps, on
## top of the lit surfaces from levels/shared_look.gd. It works with
## whichever camera is current, because the quad is placed in clip space by its
## vertex shader rather than in the world.

const LINE_COLOR := Color(0.1, 0.09, 0.11, 0.6)
## Depth jump that draws a line, as a share of the distance to the pixel.
const RELATIVE_THRESHOLD: float = 0.06
## Smallest depth jump that draws a line close up, in meters.
const MIN_THRESHOLD: float = 0.35
## Lines fade out with the haze (levels/shared_look.gd's fog), between these
## distances (m): a hill or a tree line far off in the haze has no ink edge.
const FADE_FROM: float = 80.0
const FADE_TO: float = 220.0

const SHADER := """
shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform vec4 line_color : source_color;
uniform float relative_threshold;
uniform float min_threshold;
uniform float fade_from;
uniform float fade_to;
// Line width in pixels (levels/graphics_quality.gd: the Outlines setting).
uniform float line_width = 1.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float linear_depth(vec2 uv, mat4 inv_projection) {
	float depth = texture(depth_texture, uv).r;
	vec4 view = inv_projection * vec4(uv * 2.0 - 1.0, depth, 1.0);
	return -view.z / view.w;
}

void fragment() {
	vec2 pixel = 1.0 / VIEWPORT_SIZE;
	float center = linear_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	// Every pixel from 1 out to the line width, not just the one at the width:
	// a wide line has to be one band hugging the edge, or a gap a pixel wide
	// (between cart wires, behind a rail) draws two ghost lines 3 px off it.
	float steps = max(ceil(line_width), 1.0);
	// Only the far side of a jump draws, so lines sit on the outer edge of shapes.
	float jump = 0.0;
	for (int i = 1; i <= 4; i++) {
		if (float(i) > steps) {
			break;
		}
		vec2 offset = pixel * float(i);
		float left = linear_depth(SCREEN_UV - vec2(offset.x, 0.0), INV_PROJECTION_MATRIX);
		float right = linear_depth(SCREEN_UV + vec2(offset.x, 0.0), INV_PROJECTION_MATRIX);
		float up = linear_depth(SCREEN_UV - vec2(0.0, offset.y), INV_PROJECTION_MATRIX);
		float down = linear_depth(SCREEN_UV + vec2(0.0, offset.y), INV_PROJECTION_MATRIX);
		jump = max(jump, max(max(left - center, right - center), max(up - center, down - center)));
	}
	float threshold = max(min_threshold, center * relative_threshold);
	ALBEDO = line_color.rgb;
	ALPHA = step(threshold, jump) * line_color.a * (1.0 - smoothstep(fade_from, fade_to, center));
}
"""


func _ready() -> void:
	name = "OutlinePass"
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	quad.flip_faces = true
	mesh = quad
	var shader := Shader.new()
	shader.code = SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("line_color", LINE_COLOR)
	material.set_shader_parameter("relative_threshold", RELATIVE_THRESHOLD)
	material.set_shader_parameter("min_threshold", MIN_THRESHOLD)
	material.set_shader_parameter("fade_from", FADE_FROM)
	material.set_shader_parameter("fade_to", FADE_TO)
	material_override = material
	# Never culled: the vertex shader puts it over the whole screen for any camera.
	extra_cull_margin = 16384.0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# levels/shared_look.gd must leave this material alone.
	set_meta("keep_material", true)
	set_width(preload("res://levels/graphics_quality.gd").outline_width())


## The line's width in pixels (the Outlines setting, Constants.OUTLINE_WIDTHS);
## 0 turns the pass off.
func set_width(width: float) -> void:
	visible = width > 0.0
	var material := material_override as ShaderMaterial
	if material != null:
		material.set_shader_parameter("line_width", maxf(width, 0.0))
