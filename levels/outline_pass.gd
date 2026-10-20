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

const SHADER := """
shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform vec4 line_color : source_color;
uniform float relative_threshold;
uniform float min_threshold;

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
	float left = linear_depth(SCREEN_UV - vec2(pixel.x, 0.0), INV_PROJECTION_MATRIX);
	float right = linear_depth(SCREEN_UV + vec2(pixel.x, 0.0), INV_PROJECTION_MATRIX);
	float up = linear_depth(SCREEN_UV - vec2(0.0, pixel.y), INV_PROJECTION_MATRIX);
	float down = linear_depth(SCREEN_UV + vec2(0.0, pixel.y), INV_PROJECTION_MATRIX);
	// Only the far side of a jump draws, so lines sit on the outer edge of shapes.
	float jump = max(max(left - center, right - center), max(up - center, down - center));
	float threshold = max(min_threshold, center * relative_threshold);
	ALBEDO = line_color.rgb;
	ALPHA = step(threshold, jump) * line_color.a;
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
	material_override = material
	# Never culled: the vertex shader puts it over the whole screen for any camera.
	extra_cull_margin = 16384.0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# levels/shared_look.gd must leave this material alone.
	set_meta("keep_material", true)
