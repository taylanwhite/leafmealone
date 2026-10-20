extends RefCounted

## Authority: local, cosmetic. Procedural surfaces for the lit look
## (docs/FEEL.md, "Look"): brick, siding, shingles, planks, asphalt, concrete,
## grass, bark, fabric, painted metal, dirt, and foliage, painted by one shader
## straight onto any mesh. No image files. Patterns are measured in meters in the
## mesh's own space, so a brick is brick-sized on anything, and every brick,
## board, and shingle varies a little so surfaces read as real, not flat.
##
## Tag a mesh with set_meta("surface", "brick") and levels/shared_look.gd
## paints it, using the mesh's own color as the base.

const PATTERNS: Dictionary = {
	"plain": 0, "grass": 1, "asphalt": 2, "concrete": 3, "brick": 4, "siding": 5,
	"shingles": 6, "planks": 7, "bark": 8, "fabric": 9, "metal": 10, "dirt": 11,
	"foliage": 12, "skin": 13,
}

const SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform int pattern = 0;
uniform vec4 base : source_color = vec4(0.6, 0.6, 0.6, 1.0);
uniform vec4 accent : source_color = vec4(0.3, 0.3, 0.3, 1.0);
uniform float roughness_value = 0.85;

varying vec3 local_position;
varying vec3 local_normal;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float amplitude = 0.5;
	for (int octave = 0; octave < 4; octave++) {
		total += noise(p) * amplitude;
		p *= 2.03;
		amplitude *= 0.5;
	}
	return total;
}

// Walls use a vertical plane (x or z across, y up). Floors and roofs use x and z.
vec2 plane_uv(out bool is_floor) {
	vec3 n = abs(local_normal);
	is_floor = n.y > max(n.x, n.z);
	if (is_floor) {
		return local_position.xz;
	}
	return vec2(n.x > n.z ? local_position.z : local_position.x, local_position.y);
}

vec3 shade(vec3 color, float amount) {
	return color * (1.0 + amount);
}

void vertex() {
	local_position = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	bool is_floor;
	vec2 uv = plane_uv(is_floor);
	vec3 color = base.rgb;
	float rough = roughness_value;
	float grain = fbm(uv * 3.0);
	if (pattern == 1) {
		// Grass: two greens in soft patches, with fine blade speckle.
		float patches = fbm(uv * 0.35);
		color = mix(base.rgb, accent.rgb, smoothstep(0.35, 0.65, patches));
		color = shade(color, (noise(uv * 18.0) - 0.5) * 0.18);
	} else if (pattern == 2) {
		// Asphalt: dark and speckled, with short jagged cracks only in worn patches.
		color = mix(base.rgb, vec3(0.17, 0.17, 0.19), 0.68);
		color = shade(color, (hash(floor(uv * 40.0)) - 0.5) * 0.25 + (grain - 0.5) * 0.2);
		float field = fbm(uv * 0.9) + (noise(uv * 9.0) - 0.5) * 0.08;
		float worn = smoothstep(0.62, 0.72, noise(uv * 0.18 + 7.3));
		float crack = 1.0 - smoothstep(0.0, 0.01, abs(field - 0.5));
		color = mix(color, accent.rgb, crack * worn);
	} else if (pattern == 3) {
		// Concrete: blotchy, with slab seams every two meters.
		color = shade(base.rgb, (grain - 0.5) * 0.25);
		vec2 seam = abs(fract(uv / 2.0) - 0.5);
		color = mix(accent.rgb, color, smoothstep(0.485, 0.47, max(seam.x, seam.y)));
	} else if (pattern == 4) {
		// Brick: offset rows, mortar lines, each brick a slightly different red.
		vec2 size = vec2(0.42, 0.16);
		float row = floor(uv.y / size.y);
		vec2 cell = vec2(uv.x / size.x + mod(row, 2.0) * 0.5, uv.y / size.y);
		vec2 inside = fract(cell);
		float brick = hash(floor(cell));
		color = shade(base.rgb, (brick - 0.5) * 0.3 + (grain - 0.5) * 0.15);
		float mortar = step(inside.x, 0.05) + step(inside.y, 0.12);
		color = mix(color, accent.rgb, clamp(mortar, 0.0, 1.0));
	} else if (pattern == 5) {
		// Siding: horizontal boards with a shadow under each lip.
		float board = fract(uv.y / 0.22);
		color = shade(base.rgb, (hash(vec2(floor(uv.y / 0.22), 3.0)) - 0.5) * 0.08 + (noise(uv * vec2(1.5, 30.0)) - 0.5) * 0.06);
		color *= mix(0.78, 1.0, smoothstep(0.0, 0.18, board));
	} else if (pattern == 6) {
		// Shingles: staggered tabs, darker at each tab's lower edge.
		vec2 size = vec2(0.36, 0.24);
		float row = floor(uv.y / size.y);
		vec2 cell = vec2(uv.x / size.x + mod(row, 2.0) * 0.5, uv.y / size.y);
		vec2 inside = fract(cell);
		color = shade(base.rgb, (hash(floor(cell)) - 0.5) * 0.35);
		color *= mix(0.7, 1.0, smoothstep(0.0, 0.25, inside.y));
		color = mix(color, accent.rgb, step(inside.x, 0.04) * 0.6);
	} else if (pattern == 7) {
		// Planks: boards with gaps and wood grain running along them.
		float across = is_floor ? uv.x : uv.x;
		float plank = floor(across / 0.18);
		float along = is_floor ? uv.y : uv.y;
		float streak = noise(vec2(across * 40.0, along * 1.5 + plank * 7.0));
		color = shade(base.rgb, (hash(vec2(plank, 1.0)) - 0.5) * 0.25 + (streak - 0.5) * 0.25);
		color = mix(accent.rgb, color, smoothstep(0.0, 0.07, fract(across / 0.18)));
	} else if (pattern == 8) {
		// Bark: deep vertical furrows.
		float angle = atan(local_position.z, local_position.x) * 3.0;
		float furrow = noise(vec2(angle * 2.5, local_position.y * 2.0));
		color = shade(base.rgb, (furrow - 0.5) * 0.6);
		rough = 1.0;
	} else if (pattern == 9) {
		// Fabric: a soft weave and a little fuzz.
		float weave = sin(local_position.x * 260.0) * sin(local_position.y * 260.0);
		color = shade(base.rgb, weave * 0.04 + (noise(local_position.xy * 12.0) - 0.5) * 0.08);
		rough = 0.95;
	} else if (pattern == 10) {
		// Painted metal: smooth, with grime gathering low down.
		float grime = 1.0 - smoothstep(-0.4, 0.8, local_position.y);
		color = shade(base.rgb, (grain - 0.5) * 0.08 - grime * 0.18);
		rough = 0.45;
	} else if (pattern == 11) {
		// Dirt and sand: pebbly speckle in soft patches.
		color = mix(base.rgb, accent.rgb, smoothstep(0.3, 0.75, fbm(uv * 0.5)));
		color = shade(color, (hash(floor(uv * 30.0)) - 0.5) * 0.2);
	} else if (pattern == 12) {
		// Foliage: clumps of light and dark leaves.
		float clumps = fbm(local_position.xy * 4.0 + local_position.z * 3.0);
		color = shade(base.rgb, (clumps - 0.5) * 0.5);
		rough = 0.95;
	} else if (pattern == 13) {
		// Skin: smooth, with the faintest warmth variation.
		color = shade(base.rgb, (noise(local_position.xy * 6.0) - 0.5) * 0.04);
		rough = 0.7;
	} else {
		// Everything else: a painterly variation so no surface is perfectly flat.
		color = shade(base.rgb, (grain - 0.5) * 0.12);
	}
	ALBEDO = color;
	ROUGHNESS = rough;
	SPECULAR = 0.25;
}
"""

static var _shader: Shader
static var _cache: Dictionary = {}


## A material painting pattern in color. accent is the mortar, gaps, or second
## color; left out, it is a darker shade of color. Shared between meshes.
static func material(pattern: String, color: Color, accent := Color(0, 0, 0, 0)) -> ShaderMaterial:
	var second := accent if accent.a > 0.0 else _default_accent(pattern, color)
	var key := "%s|%s|%s" % [pattern, color.to_html(), second.to_html()]
	if _cache.has(key):
		return _cache[key]
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var made := ShaderMaterial.new()
	made.shader = _shader
	made.set_shader_parameter("pattern", int(PATTERNS.get(pattern, 0)))
	made.set_shader_parameter("base", color)
	made.set_shader_parameter("accent", second)
	_cache[key] = made
	return made


static func _default_accent(pattern: String, color: Color) -> Color:
	match pattern:
		"brick":
			return Color(0.78, 0.75, 0.7)
		"grass":
			return color.lightened(0.12).lerp(Color(0.6, 0.62, 0.25), 0.25)
		"asphalt":
			return color.darkened(0.45)
		"dirt":
			return color.darkened(0.15)
		_:
			return color.darkened(0.3)
