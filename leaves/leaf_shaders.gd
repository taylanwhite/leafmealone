extends RefCounted

## Authority: local, cosmetic. The leaf shaders (docs/ART.md "Leaves"), siblings
## of props/stylized.gd (the same sRGB clamp, wrapped lighting and season snow):
##
## - FLAKE: one leaf. Centre-to-rim colour, darker veins, age browning it, a
##   paler underside, light through it, snow on top in winter and a wet sheen,
##   loose leaves lifting their tips in the breeze. As a "hero" (resting on the
##   lawn) it rides the skin: the vertex adds the height map under its origin
##   and shears by the slope there, so a mound that grows carries its leaves
##   with no CPU work. As a "mover" (in flight, leaves/leaf_motion.gd) it draws
##   where it is.
## - LITTER: the skin. A flat grid lifted by the height map, painted with a
##   "dead leaves" pattern: overlapping leaf shapes in the cell's colours, each
##   leaf lying on whatever it overlaps, sparse and ragged where the leaves run
##   thin (the lawn shows through), dark gaps between them deep in a pile, a
##   darker rim at the base of a mound. It casts the leaves' shadows.
## - GRASS_PRESS: lines put into props/stylized.gd's shader by
##   leaves/grass_press.gd so grass under leaves lies flat.
##
## Shared inputs are global shader parameters (project.godot): leaf_height_map
## (FORMAT_RF, display height per field cell, meters), leaf_cover_map (RGBA8: R
## displayed density / 255, G the cell's look index / 255, B unused, A grass
## press) and leaf_rect (world x, z of the grid's corner, 1 / its size in x and
## z; all zero turns every leaf effect off). Height and cover are read with
## texelFetch and blended by hand, exactly as leaves/leaf_renderer.gd does on
## the CPU (surface_y), so a leaf handed from the CPU to the GPU lands where the
## skin is.

## The shared functions: the height map, read like the CPU reads it.
const COMMON := """
global uniform sampler2D leaf_height_map;
global uniform sampler2D leaf_cover_map;
global uniform vec4 leaf_rect;
global uniform float season_snow;

vec3 to_linear(vec3 c) {
	c = max(c, vec3(0.0));
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

float leaf_cell_h(ivec2 c) {
	ivec2 size = textureSize(leaf_height_map, 0);
	return texelFetch(leaf_height_map, clamp(c, ivec2(0), size - 1), 0).r;
}

// The grid position of a world point: integers at cell centres.
vec2 leaf_grid(vec2 xz) {
	return (xz - leaf_rect.xy) * leaf_rect.zw * vec2(textureSize(leaf_height_map, 0)) - 0.5;
}

// Height and its slope (per meter) at a world point, bilinear between cell centres.
vec3 leaf_height(vec2 xz) {
	if (leaf_rect.z <= 0.0) {
		return vec3(0.0);
	}
	vec2 g = leaf_grid(xz);
	vec2 i = floor(g);
	vec2 f = g - i;
	ivec2 c = ivec2(i);
	float a = leaf_cell_h(c);
	float b = leaf_cell_h(c + ivec2(1, 0));
	float d = leaf_cell_h(c + ivec2(0, 1));
	float e = leaf_cell_h(c + ivec2(1, 1));
	float h = mix(mix(a, b, f.x), mix(d, e, f.x), f.y);
	vec2 cells = vec2(textureSize(leaf_height_map, 0)) * leaf_rect.zw;
	float gx = ((b - a) * (1.0 - f.y) + (e - d) * f.y) * cells.x;
	float gz = ((d - a) * (1.0 - f.x) + (e - b) * f.x) * cells.y;
	return vec3(h, gx, gz);
}

vec4 leaf_cell_cover(ivec2 c) {
	ivec2 size = textureSize(leaf_cover_map, 0);
	return texelFetch(leaf_cover_map, clamp(c, ivec2(0), size - 1), 0);
}

// The cover map, bilinear, at a world point.
vec4 leaf_cover(vec2 xz) {
	vec2 g = (xz - leaf_rect.xy) * leaf_rect.zw * vec2(textureSize(leaf_cover_map, 0)) - 0.5;
	vec2 i = floor(g);
	vec2 f = g - i;
	ivec2 c = ivec2(i);
	return mix(mix(leaf_cell_cover(c), leaf_cell_cover(c + ivec2(1, 0)), f.x), mix(leaf_cell_cover(c + ivec2(0, 1)), leaf_cell_cover(c + ivec2(1, 1)), f.x), f.y);
}
"""

const FLAKE_SHADER := """
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx, cull_disabled, world_vertex_coords;
//DEFINES
//COMMON

uniform float translucency = 0.45;
// Winter's wet sheen, 0..1 (the leaf view sets it by season).
uniform float wet = 0.0;
// How far a loose leaf's tips lift in a gust, in meters.
uniform float loose_lift = 0.025;

varying vec4 rim_color;
varying vec2 masks;
varying vec2 plane;
varying float species;
varying float world_up;

float gust(float t, vec2 at) {
	float slow = max(sin(t * 1.3 + at.x * 0.21 + at.y * 0.17), 0.0);
	return slow * slow * (0.55 + 0.45 * sin(t * 9.0 + at.x * 3.1 - at.y * 2.3));
}

void vertex() {
	rim_color = INSTANCE_CUSTOM;
	masks = vec2(UV.x, mod(UV.y, 2.0));
	species = floor(UV.y * 0.5);
	plane = UV2;
	vec3 origin = MODEL_MATRIX[3].xyz;
#ifdef HERO
	vec3 ground = leaf_height(origin.xz);
	VERTEX.y += ground.x + dot(VERTEX.xz - origin.xz, ground.yz);
	NORMAL = normalize(vec3(NORMAL.x - ground.y * NORMAL.y, NORMAL.y, NORMAL.z - ground.z * NORMAL.y));
#endif
	if (INSTANCE_CUSTOM.a > 0.6) {
		VERTEX.y += masks.y * loose_lift * (INSTANCE_CUSTOM.a - 0.6) * 2.5 * gust(TIME, origin.xz);
	}
	world_up = NORMAL.y;
}

float vein_mask() {
	vec2 p = plane;
	float midrib = 1.0 - smoothstep(0.006, 0.02, abs(p.x));
	float veins = 0.0;
	if (species < 0.5) {
		// Maple: veins radiate from the hub out along the lobes.
		vec2 d = p;
		float r = length(d);
		float a = atan(d.x, -d.y);
		for (int l = 0; l < 5; l++) {
			float lobe = (float(l) - 2.0) * 0.95;
			float off = abs(sin(a - lobe)) * r;
			veins = max(veins, (1.0 - smoothstep(0.005, 0.018, off)) * step(0.0, cos(a - lobe)));
		}
		midrib = 0.0;
	} else {
		// Oak and oval: side veins off the midrib, sweeping toward the tip.
		float side = fract((p.y + abs(p.x) * 1.1) * 6.0);
		veins = (1.0 - smoothstep(0.0, 0.09, abs(side - 0.5) * 2.0 - 0.82)) * step(0.03, abs(p.x));
		veins *= 1.0 - smoothstep(0.18, 0.3, abs(p.x));
	}
	return max(midrib, veins) * (1.0 - smoothstep(0.85, 1.0, masks.x));
}

void fragment() {
	vec3 centre = to_linear(COLOR.rgb);
	vec3 rim = to_linear(rim_color.rgb);
	float age = clamp(COLOR.a, 0.0, 1.0);
	vec3 base = mix(centre, rim, pow(clamp(masks.x, 0.0, 1.0), 2.2));
	base *= 1.0 - 0.18 * vein_mask();
	// Age dries a leaf toward brown and darkens it.
	base = mix(base, to_linear(vec3(0.52, 0.34, 0.19)), age * 0.75) * (1.0 - 0.3 * age);
	// The underside is paler (it flickers past in flight).
	if (!FRONT_FACING) {
		base = mix(base, to_linear(vec3(0.86, 0.74, 0.52)), 0.28);
	}
	// Snow dusts some leaves' tops (by where they lie), never every leaf.
	vec3 at = MODEL_MATRIX[3].xyz;
	float dust = smoothstep(0.45, 0.8, fract(sin(dot(floor(at.xz * 2.0), vec2(12.9898, 78.233))) * 43758.5453));
	float snow = season_snow * smoothstep(0.5, 0.85, world_up) * (FRONT_FACING ? 1.0 : 0.0) * dust * (1.0 - smoothstep(0.55, 1.0, masks.x) * 0.6);
	base = mix(base, vec3(0.86, 0.89, 0.95), snow * 0.8);
	ALBEDO = base;
	ROUGHNESS = mix(0.85, 0.5, wet);
	SPECULAR = mix(0.12, 0.35, wet);
	BACKLIGHT = base * translucency;
}
"""

const LITTER_SHADER := """
shader_type spatial;
// Plain lambert (not wrapped like props): a pile's shaded side reads as a shape.
render_mode diffuse_lambert, specular_schlick_ggx, cull_back;
//COMMON

const int LOOKS = 16;
// Per look (G of the cover map): colours and age range for the season.
uniform vec4 look_centre[LOOKS];
uniform vec4 look_rim[LOOKS];
uniform vec4 look_alt_centre[LOOKS];
uniform vec4 look_alt_rim[LOOKS];
uniform int look_count = 1;
uniform float tile = 0.11;
uniform float skin_clean = 10.0;
uniform float skin_full = 70.0;
uniform float stray_share = 0.12;
uniform float dry_share = 0.15;
uniform float look_jitter = 1.6;
uniform float wet = 0.0;

varying vec3 world_pos;
varying float cavity;
varying float height_here;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_pos = w;
	cavity = 1.0;
	height_here = 0.0;
	if (leaf_rect.z > 0.0) {
		vec3 here = leaf_height(w.xz);
		VERTEX.y += here.x;
		NORMAL = normalize(vec3(-here.y, 1.0, -here.z));
		float e = 0.9;
		float wide = 0.25 * (leaf_height(w.xz + vec2(e, 0.0)).x + leaf_height(w.xz - vec2(e, 0.0)).x + leaf_height(w.xz + vec2(0.0, e)).x + leaf_height(w.xz - vec2(0.0, e)).x);
		// Darker where the skin dips below its surroundings: the base of a mound.
		cavity = mix(0.7, 1.0, smoothstep(-0.07, 0.01, here.x - wide));
		height_here = here.x;
		world_pos.y += here.x;
	}
}

uint hash1(uint x) {
	x ^= x >> 16u;
	x *= 0x7feb352du;
	x ^= x >> 15u;
	x *= 0x846ca68bu;
	x ^= x >> 16u;
	return x;
}

// Four floats in [0, 1] for a tile cell and a leaf in it.
vec4 rand4(vec2 cell, uint n) {
	ivec2 i = ivec2(cell) + ivec2(32768);
	uint s = hash1((uint(i.x) * 73856093u) ^ (uint(i.y) * 19349663u) ^ (n * 83492791u));
	uint t = hash1(s ^ 0x9e3779b9u);
	return vec4(float(s & 65535u), float(s >> 16u), float(t & 65535u), float(t >> 16u)) / 65535.0;
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = p - i;
	f = f * f * (3.0 - 2.0 * f);
	float a = rand4(i, 91u).x;
	float b = rand4(i + vec2(1.0, 0.0), 91u).x;
	float c = rand4(i + vec2(0.0, 1.0), 91u).x;
	float d = rand4(i + vec2(1.0, 1.0), 91u).x;
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// A leaf's half width at a point along it (y in -1 base .. 1 tip): a pointed oval.
float leaf_half_width(float y) {
	float t = clamp(y, -1.0, 1.0);
	return sqrt(max(1.0 - t * t, 0.0)) * (1.0 - 0.3 * max(t, 0.0)) * (1.0 + 0.15 * min(t, 0.0));
}

float maple_lobe(float a, float centre, float reach) {
	float c = max(cos((a - centre) * 1.7), 0.0);
	return reach * (0.42 + 0.58 * c * c * c);
}

// Whether a point of a leaf's own space (y along it, -1 base .. 1 tip, x
// across, in half lengths) is on the leaf, by species (0 maple, 1 oak, 2
// oval): its rim factor (0 middle .. 1 edge), or -1 off it.
float leaf_shape(vec2 q, float width, int species) {
	if (species == 0) {
		// Five lobes from a hub low on the leaf; the front one longest.
		vec2 h = vec2(q.x, q.y + 0.2);
		float r = length(h);
		float a = atan(h.x, h.y);
		float aa = abs(a);
		float reach = max(maple_lobe(a, 0.0, 1.0), max(maple_lobe(aa, 1.0, 0.8), maple_lobe(aa, 1.95, 0.5)));
		if (r > reach) {
			return -1.0;
		}
		return r / reach;
	}
	float y = q.y;
	if (abs(y) > 1.0) {
		return -1.0;
	}
	float w = leaf_half_width(y) * width;
	if (species == 1) {
		// Oak: rounded lobes down each side.
		w *= 0.74 + 0.26 * abs(cos(y * 7.0));
	}
	float ax = abs(q.x);
	if (ax > w) {
		return -1.0;
	}
	return max(ax / max(w, 0.0001), abs(y) * 0.85);
}

int look_at(vec2 world, ivec2 size) {
	vec2 g = (world - leaf_rect.xy) * leaf_rect.zw * vec2(size);
	return clamp(int(leaf_cell_cover(ivec2(floor(g))).g * 255.0 + 0.5), 0, look_count - 1);
}

vec3 look_color(int l) {
	vec3 c = mix(to_linear(look_centre[l].rgb), to_linear(look_rim[l].rgb), 0.5);
	return mix(c, to_linear(vec3(0.52, 0.34, 0.19)), (look_centre[l].a + look_rim[l].a) * 0.5 * 0.75) * 0.9;
}

void fragment() {
	if (leaf_rect.z <= 0.0) {
		discard;
	}
	vec2 xz = world_pos.xz;
	vec4 cover = leaf_cover(xz);
	float dens = cover.r * 255.0;
	float broad = value_noise(xz / 1.5);
	vec2 p = xz / tile;
	float footprint = length(fwidth(p));
	float detail = 1.0 - smoothstep(0.35, 0.9, footprint);
	// No leaves near: bare lawn. Up close the skin's edge is made of whole
	// leaves (each lives or not by the density under its middle), so it is as
	// ragged as they are; far off a wandering line.
	if (dens < 0.5 || (detail <= 0.5 && dens < skin_clean + 14.0 * broad)) {
		discard;
	}
	ivec2 size = textureSize(leaf_cover_map, 0);
	vec2 cell_m = 1.0 / (leaf_rect.zw * vec2(size));
	float best = -1.0;
	float shade_order = -1.0;
	float rim_f = 0.0;
	float along = 0.0;
	float across = 1.0;
	vec4 pick = vec4(0.0);
	vec4 pick_t = vec4(0.0);
	int pick_look = 0;
	int pick_species = 2;
	// Where a leaf lying on top throws its shadow, in tiles.
	vec2 shadow = vec2(0.13, 0.1);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 cell = floor(p) + vec2(float(i), float(j));
			for (uint n = 0u; n < 3u; n++) {
				vec4 r = rand4(cell, n);
				vec2 centre = cell + r.xy;
				vec2 g = (centre * tile - leaf_rect.xy) * leaf_rect.zw * vec2(size);
				float here = leaf_cell_cover(ivec2(floor(g))).r * 255.0;
				float coverage = smoothstep(skin_clean, skin_full, here);
				if (r.z >= coverage) {
					continue;
				}
				vec4 s = rand4(cell, n + 17u);
				vec4 t = rand4(cell, n + 41u);
				// Each leaf takes the colour of a cell near it: tree colours blend
				// leaf by leaf instead of cell by cell.
				int l = look_at(centre * tile + (t.xy * 2.0 - 1.0) * cell_m * look_jitter, size);
				int species = int(look_alt_rim[l].a + 0.5);
				float angle = r.w * 6.2831853;
				float half_len = mix(0.6, 0.95, s.x) * (species == 0 ? 0.92 : 1.0);
				float width = mix(0.45, 0.68, s.y);
				mat2 turn = mat2(vec2(cos(angle), -sin(angle)), vec2(sin(angle), cos(angle)));
				vec2 q = turn * (p - centre) / half_len;
				vec2 q_shadow = turn * (p - shadow - centre) / half_len;
				float order = s.w;
				if (order > shade_order && leaf_shape(q_shadow, width, species) >= 0.0) {
					shade_order = order;
				}
				if (order <= best) {
					continue;
				}
				float on = leaf_shape(q, width, species);
				if (on < 0.0) {
					continue;
				}
				best = order;
				pick = s;
				pick_t = t;
				rim_f = on;
				along = q.y;
				across = abs(q.x) / max(leaf_half_width(q.y) * width, 0.0001);
				pick_look = l;
				pick_species = species;
			}
		}
	}
	// Far away, the cells' colours blended between cell centres (no leaf shapes to alias, no squares).
	vec2 fg = (xz - leaf_rect.xy) * leaf_rect.zw * vec2(size) - 0.5;
	vec2 fi = floor(fg);
	vec2 ff = fg - fi;
	ivec2 fc = ivec2(fi);
	vec3 far_color = mix(
		mix(look_color(clamp(int(leaf_cell_cover(fc).g * 255.0 + 0.5), 0, look_count - 1)), look_color(clamp(int(leaf_cell_cover(fc + ivec2(1, 0)).g * 255.0 + 0.5), 0, look_count - 1)), ff.x),
		mix(look_color(clamp(int(leaf_cell_cover(fc + ivec2(0, 1)).g * 255.0 + 0.5), 0, look_count - 1)), look_color(clamp(int(leaf_cell_cover(fc + ivec2(1, 1)).g * 255.0 + 0.5), 0, look_count - 1)), ff.x), ff.y);
	vec3 leaf;
	// Far away there are no leaf shapes to leave gaps between, so the lawn
	// shows through as often as it would close up: a share of the skin,
	// picked by a smooth noise, is let through (no band where detail ends).
	float far_gap = dens < skin_full + 10.0 ? exp(-2.6 * smoothstep(skin_clean, skin_full, dens)) : 0.0;
	if (detail <= 0.5 && value_noise(xz * 3.3) < far_gap) {
		discard;
	}
	if (best < 0.0) {
		// A gap: the lawn shows through thin leaves; deep in a pile, darker leaves below.
		if (dens < skin_full + 10.0 && detail > 0.5) {
			discard;
		}
		leaf = far_color * mix(0.45, 0.85, 1.0 - detail);
	} else {
		int l = pick_look;
		// Strays from elsewhere in the yard, and summer's odd yellow.
		if (pick.z < stray_share) {
			l = int(floor(fract(pick.z * 37.0) * float(look_count)));
		}
		bool alt = pick_t.z < look_alt_centre[l].a;
		vec3 c = to_linear(alt ? look_alt_centre[l].rgb : look_centre[l].rgb);
		vec3 rim = to_linear(alt ? look_alt_rim[l].rgb : look_rim[l].rgb);
		float age = mix(look_centre[l].a, look_rim[l].a, pick_t.w);
		if (fract(pick.y * 17.0) < dry_share) {
			age = max(age, 0.6);
		}
		leaf = mix(c, rim, pow(clamp(rim_f, 0.0, 1.0), 1.5));
		leaf *= mix(0.8, 1.12, fract(pick.x * 23.0));
		// The midrib, and the leaf's edge a little darker than its face.
		if (pick_species != 0) {
			leaf *= 1.0 - 0.16 * (1.0 - smoothstep(0.05, 0.12, across)) * step(along, 0.9);
		}
		leaf *= 1.0 - 0.15 * smoothstep(0.82, 0.98, rim_f);
		leaf = mix(leaf, to_linear(vec3(0.52, 0.34, 0.19)), age * 0.75) * (1.0 - 0.3 * age);
		// Leaves lying under others are a little darker, and in their shadow.
		leaf *= mix(0.82, 1.04, pick.w);
		if (shade_order > best) {
			leaf *= 0.6;
		}
		leaf = mix(far_color, leaf, detail);
	}	leaf *= 0.92 + 0.16 * broad;
	leaf *= cavity;
	leaf *= 1.0 + 0.06 * smoothstep(0.25, 0.35, height_here);
	float up = clamp((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y, 0.0, 1.0);
	// A dusting, not a blanket: snow lies in drifts across the leaves, and on piles' tops.
	float drift = smoothstep(0.35, 0.75, value_noise(xz * 1.7) * 0.7 + value_noise(xz * 6.0) * 0.3 + 0.25 * smoothstep(0.1, 0.4, height_here));
	float snow = season_snow * smoothstep(0.5, 0.85, up) * drift;
	leaf = mix(leaf, vec3(0.86, 0.89, 0.95), snow * 0.85);
	ALBEDO = leaf;
	ROUGHNESS = mix(0.88, 0.5, wet);
	SPECULAR = mix(0.1, 0.32, wet);
	BACKLIGHT = leaf * 0.12;
}
"""

## Declarations put after props/stylized.gd's varyings.
const GRASS_PRESS_GLOBALS := """
global uniform sampler2D leaf_cover_map;
global uniform vec4 leaf_rect;
uniform float leaf_press_max = 0.8;
"""

## The first lines of the grass vertex(): grass under leaves lies flat (cover A).
const GRASS_PRESS_SNIPPET := """
	if (leaf_rect.z > 0.0) {
		vec3 leaf_root = MODEL_MATRIX[3].xyz;
		vec2 leaf_uv = (leaf_root.xz - leaf_rect.xy) * leaf_rect.zw;
		if (leaf_uv.x >= 0.0 && leaf_uv.y >= 0.0 && leaf_uv.x <= 1.0 && leaf_uv.y <= 1.0) {
			ivec2 leaf_size = textureSize(leaf_cover_map, 0);
			vec2 leaf_g = leaf_uv * vec2(leaf_size) - 0.5;
			vec2 leaf_i = floor(leaf_g);
			vec2 leaf_f = leaf_g - leaf_i;
			ivec2 leaf_c = ivec2(leaf_i);
			float leaf_a = texelFetch(leaf_cover_map, clamp(leaf_c, ivec2(0), leaf_size - 1), 0).a;
			float leaf_b = texelFetch(leaf_cover_map, clamp(leaf_c + ivec2(1, 0), ivec2(0), leaf_size - 1), 0).a;
			float leaf_d = texelFetch(leaf_cover_map, clamp(leaf_c + ivec2(0, 1), ivec2(0), leaf_size - 1), 0).a;
			float leaf_e = texelFetch(leaf_cover_map, clamp(leaf_c + ivec2(1, 1), ivec2(0), leaf_size - 1), 0).a;
			float leaf_press = mix(mix(leaf_a, leaf_b, leaf_f.x), mix(leaf_d, leaf_e, leaf_f.x), leaf_f.y);
			VERTEX.y *= 1.0 - leaf_press_max * leaf_press;
		}
	}
"""

static var _flake_shaders: Dictionary = {}
static var _litter_shader: Shader
static var _flake_materials: Dictionary = {}


## The flake shader, "hero" (rides the height map) or "mover".
static func flake_shader(mode: String) -> Shader:
	var key := "hero" if mode == "hero" else "mover"
	if not _flake_shaders.has(key):
		var shader := Shader.new()
		shader.code = FLAKE_SHADER.replace("//COMMON", COMMON).replace("//DEFINES", "#define HERO" if key == "hero" else "")
		_flake_shaders[key] = shader
	return _flake_shaders[key]


## The one flake material per mode, shared by every leaf (and by
## levels/town/season_dressing.gd's neighbour yards, as "mover").
static func flake_material(mode: String) -> ShaderMaterial:
	var key := "hero" if mode == "hero" else "mover"
	if not _flake_materials.has(key):
		var made := ShaderMaterial.new()
		made.shader = flake_shader(key)
		made.set_shader_parameter("translucency", Constants.LEAF_TRANSLUCENCY)
		_flake_materials[key] = made
	return _flake_materials[key]


## A litter material (one per leaf view: its looks are its yard's).
static func litter_material() -> ShaderMaterial:
	if _litter_shader == null:
		_litter_shader = Shader.new()
		_litter_shader.code = LITTER_SHADER.replace("//COMMON", COMMON)
	var made := ShaderMaterial.new()
	made.shader = _litter_shader
	made.set_shader_parameter("tile", Constants.LEAF_TILE)
	made.set_shader_parameter("skin_clean", float(Constants.LEAF_SKIN_CLEAN))
	made.set_shader_parameter("skin_full", float(Constants.LEAF_SKIN_FULL))
	made.set_shader_parameter("stray_share", Constants.LEAF_STRAY_SHARE)
	made.set_shader_parameter("dry_share", Constants.LEAF_DRY_SHARE)
	made.set_shader_parameter("look_jitter", Constants.LEAF_LOOK_JITTER_CELLS)
	return made


## Winter's wet sheen on every leaf material (0..1).
static func set_wet(amount: float) -> void:
	for key: String in ["hero", "mover"]:
		flake_material(key).set_shader_parameter("wet", amount)
