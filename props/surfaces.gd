extends RefCounted

## Authority: local, cosmetic. Procedural surfaces for the lit look
## (docs/FEEL.md, "Look"): brick, siding, shingles, planks, asphalt, concrete,
## grass, bark, fabric, painted metal, dirt, and foliage, painted by one shader
## straight onto any mesh. No image files. Patterns are measured in meters in the
## mesh's own space, so a brick is brick-sized on anything, and every brick,
## board, and shingle varies a little so surfaces read as real, not flat.
##
## Tag a mesh with set_meta("surface", "brick") and levels/shared_look.gd
## paints it, using the mesh's own color as the base. Optional metas:
## "surface_params" (Vector4, what the pattern's params mean is listed below)
## and "surface_accent" (Color, the mortar, gap, or second color).
##
## params by pattern:
## - stone: x >= 0.5 for cut ashlar blocks instead of fieldstone.
## - pavers: x >= 0.5 for herringbone instead of running bond.
## - lawn_stripes: x = stripe contrast (0 means 0.12).
## - grass, lawn_stripes: z = a flower floor that stays all year (the season's
##   bloom is max(season_bloom, z)).
## - road: painted lines in local space (along = local x, across = local z, on
##   the top face). x = line style (ROAD_LINES), y = half the road's width
##   (0 means 4.4), z = dash length (0 means 3 m), w = dash period (0 means
##   twice the dash). Style 5 is an intersection patch: y is half the patch's
##   size and z the depth of the crosswalk bands along each edge.
##
## Painted per vertex: painted(pattern, params) is the material for a mesh
## that carries its colors itself (props/house_kit.gd): the vertex color is the
## base, CUSTOM0 the accent, and the vertex alpha scales the snow, so a house's
## every color in one pattern is one draw call. accent_for() is the accent a
## pattern would pick.
##
## Seasons: the shader globals season_snow and season_bloom (core/seasons.gd) lay
## snow on every upward face (roads, gravel, and asphalt only get slush) and dot
## lawns with flowers. Skin and tile_floor never get snow, and material()'s snow
## argument (mesh meta "surface_snow") turns it down or off for anything indoors.

const PATTERNS: Dictionary = {
	"plain": 0, "grass": 1, "asphalt": 2, "concrete": 3, "brick": 4, "siding": 5,
	"shingles": 6, "planks": 7, "bark": 8, "fabric": 9, "metal": 10, "dirt": 11,
	"foliage": 12, "skin": 13, "stucco": 14, "stone": 15, "roof_tiles": 16,
	"corrugated": 17, "shakes": 18, "board_batten": 19, "gravel": 20, "pavers": 21,
	"lawn_stripes": 22, "cinderblock": 23, "tile_floor": 24, "road": 25,
}

## Road line styles, the road pattern's params.x.
const ROAD_LINES: Dictionary = {
	"none": 0, "double_yellow": 1, "white_edges": 2, "double_yellow_edges": 3,
	"parking": 4, "crosswalk": 5, "single_yellow": 6,
}

const SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform int pattern = 0;
uniform vec4 base : source_color = vec4(0.6, 0.6, 0.6, 1.0);
uniform vec4 accent : source_color = vec4(0.3, 0.3, 0.3, 1.0);
uniform float roughness_value = 0.85;
// What each pattern does with these is listed in props/surfaces.gd.
uniform vec4 params = vec4(0.0);
// The season (core/seasons.gd): snow on upward faces, flowers on lawns.
global uniform float season_snow;
global uniform float season_bloom;
// How much of that snow this material takes (material()'s snow): 0 under a roof.
uniform float snow_cover = 1.0;
// Painted per vertex (painted(): props/house_kit.gd merges every color of one
// pattern into one mesh): the base color is the vertex color (sRGB), the accent
// is CUSTOM0 (sRGB), and the vertex alpha scales snow_cover (0 under a roof).
uniform bool painted = false;

varying vec3 local_position;
varying vec3 local_normal;
varying vec3 world_pos;
varying float world_up;
varying vec3 painted_accent;

const vec3 LINE_YELLOW = vec3(0.85, 0.57, 0.07);
const vec3 LINE_WHITE = vec3(0.8, 0.8, 0.78);
const vec3 SNOW_WHITE = vec3(0.93, 0.95, 0.99);

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

// Cells around scattered points: x = distance to the nearest, y = to the second
// nearest (y - x is small along the seams), z = a hash naming the nearest cell.
vec3 voronoi(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	float id = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = vec2(hash(cell + g), hash(cell + g + 17.31)) * 0.8 + 0.1;
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < f1) {
				f2 = f1;
				f1 = d;
				id = hash(cell + g + 3.7);
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return vec3(sqrt(f1), sqrt(f2), id);
}

// Herringbone of 2x1 bricks in brick-width units: x = a hash naming the brick,
// y = the distance to its nearest edge.
vec2 herringbone(vec2 p) {
	vec2 c = floor(p);
	float d = c.x - c.y;
	float strip = floor((d + 2.0) / 4.0);
	float e = d - 4.0 * strip;
	vec2 lo;
	vec2 size;
	if (e >= 0.0) {
		lo = vec2(c.y + 4.0 * strip, c.y);
		size = vec2(2.0, 1.0);
	} else if (e > -1.5) {
		lo = vec2(c.x, c.y);
		size = vec2(1.0, 2.0);
	} else {
		lo = vec2(c.x, c.y - 1.0);
		size = vec2(1.0, 2.0);
	}
	vec2 q = p - lo;
	float edge = min(min(q.x, size.x - q.x), min(q.y, size.y - q.y));
	return vec2(hash(lo * 1.37 + size * 7.0), edge);
}

// 1 inside a painted stripe of this width around center, softened by aa
// (about a pixel, from fwidth taken outside any per-pixel branch).
float band(float x, float center, float width, float aa) {
	return 1.0 - smoothstep(width * 0.5 - aa, width * 0.5 + aa, abs(x - center));
}

vec3 asphalt_color(vec2 uv, float grain, vec3 base_rgb, vec3 accent_rgb) {
	vec3 color = mix(base_rgb, vec3(0.17, 0.17, 0.19), 0.68);
	color = shade(color, (hash(floor(uv * 40.0)) - 0.5) * 0.25 + (grain - 0.5) * 0.2);
	float field = fbm(uv * 0.9) + (noise(uv * 9.0) - 0.5) * 0.08;
	float worn = smoothstep(0.62, 0.72, noise(uv * 0.18 + 7.3));
	float crack = 1.0 - smoothstep(0.0, 0.01, abs(field - 0.5));
	return mix(color, accent_rgb, crack * worn);
}

// sRGB to linear, clamped first: pow() of a negative is NaN, and glow smears a
// NaN pixel into a white flare (props/stylized.gd has the same guard).
vec3 to_linear(vec3 c) {
	c = clamp(c, vec3(0.0), vec3(1.0));
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void vertex() {
	local_position = VERTEX;
	local_normal = NORMAL;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_up = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
	painted_accent = CUSTOM0.rgb;
}

void fragment() {
	bool is_floor;
	vec2 uv = plane_uv(is_floor);
	// The two colors and the snow this pixel takes: uniforms, or per vertex when painted.
	vec3 base_rgb = painted ? to_linear(COLOR.rgb) : base.rgb;
	vec3 accent_rgb = painted ? to_linear(painted_accent) : accent.rgb;
	float cover = painted ? snow_cover * clamp(COLOR.a, 0.0, 1.0) : snow_cover;
	vec3 color = base_rgb;
	float rough = roughness_value;
	float spec = 0.25;
	float grain = fbm(uv * 3.0);
	// Pixel widths for painted lines, taken here where every pixel runs the same code.
	float aa_x = max(fwidth(local_position.x), 0.002);
	float aa_z = max(fwidth(local_position.z), 0.002);
	if (pattern == 1 || pattern == 22) {
		// Grass: two greens in soft patches, with fine blade speckle.
		float patches = fbm(uv * 0.35);
		color = mix(base_rgb, accent_rgb, smoothstep(0.35, 0.65, patches));
		color = shade(color, (noise(uv * 18.0) - 0.5) * 0.18);
		if (pattern == 22) {
			// Lawn stripes: mowed bands running along local x, light then dark.
			float contrast = params.x > 0.0 ? params.x : 0.12;
			float stripe = smoothstep(-0.2, 0.2, sin(uv.y * 3.14159 / 1.1));
			color *= 1.0 + (stripe - 0.5) * contrast * 2.0;
		}
		// Flowers: sparse dots, more in spring; some lawns keep a floor of them.
		float bloom = max(season_bloom, params.z);
		if (bloom > 0.0 && is_floor) {
			vec2 cell = floor(uv * 6.0);
			vec2 inside = fract(uv * 6.0);
			float pick = hash(cell);
			vec2 center = vec2(hash(cell + 5.1), hash(cell + 9.7)) * 0.5 + 0.25;
			float petal = 1.0 - smoothstep(0.17, 0.23, length(inside - center));
			float shown = step(1.0 - bloom * 0.35, pick) * petal;
			float kind = hash(cell + 2.3);
			vec3 flower = kind < 0.45 + params.z * 0.5 ? vec3(0.9, 0.7, 0.05) : (kind < 0.85 ? vec3(0.88, 0.88, 0.84) : vec3(0.9, 0.45, 0.6));
			color = mix(color, flower, shown);
		}
	} else if (pattern == 2) {
		// Asphalt: dark and speckled, with short jagged cracks only in worn patches.
		color = asphalt_color(uv, grain, base_rgb, accent_rgb);
	} else if (pattern == 25) {
		// Road: asphalt with painted lines, worn a little, on the top face only.
		color = asphalt_color(uv, grain, base_rgb, accent_rgb);
		if (is_floor && local_normal.y > 0.0) {
			float along = local_position.x;
			float across = local_position.z;
			int style = int(params.x + 0.5);
			float half_w = params.y > 0.0 ? params.y : 4.4;
			float dash = params.z > 0.0 ? params.z : 3.0;
			float period = params.w > 0.0 ? params.w : dash * 2.0;
			float dashed = step(mod(along, period), dash);
			float yellow = 0.0;
			float white = 0.0;
			if (style == 1 || style == 3) {
				yellow = (band(across, -0.12, 0.1, aa_z) + band(across, 0.12, 0.1, aa_z)) * dashed;
			}
			if (style == 6) {
				yellow = band(across, 0.0, 0.14, aa_z) * dashed;
			}
			if (style == 2 || style == 3) {
				white = band(abs(across), half_w - 0.3, 0.12, aa_z);
			}
			if (style == 4) {
				// Parking stalls every 3 m, 5 m deep from each edge, and the line where they end.
				float to_line = abs(mod(along + 1.5, 3.0) - 1.5);
				float in_stall = step(half_w - 5.0, abs(across)) * step(abs(across), half_w - 0.15);
				white = band(to_line, 0.0, 0.1, aa_x) * in_stall;
				if (half_w > 5.5) {
					white = max(white, band(abs(across), half_w - 5.0, 0.1, aa_z));
				}
			}
			if (style == 5) {
				// Intersection: zebra bars in a band just inside each edge, none in the corners.
				float depth = dash;
				float near_x = step(half_w - depth, abs(along)) * step(abs(along), half_w - 0.3) * step(abs(across), half_w - depth);
				float near_z = step(half_w - depth, abs(across)) * step(abs(across), half_w - 0.3) * step(abs(along), half_w - depth);
				white = near_x * step(fract(across / 1.0), 0.5) + near_z * step(fract(along / 1.0), 0.5);
			}
			float wear = 0.82 + 0.18 * noise(uv * 2.5);
			color = mix(color, LINE_YELLOW * wear, clamp(yellow, 0.0, 1.0) * 0.95);
			color = mix(color, LINE_WHITE * wear, clamp(white, 0.0, 1.0) * 0.92);
		}
	} else if (pattern == 3) {
		// Concrete: blotchy, with slab seams every two meters.
		color = shade(base_rgb, (grain - 0.5) * 0.25);
		vec2 seam = abs(fract(uv / 2.0) - 0.5);
		color = mix(accent_rgb, color, smoothstep(0.485, 0.47, max(seam.x, seam.y)));
	} else if (pattern == 4) {
		// Brick: offset rows, mortar lines, each brick a slightly different red.
		vec2 size = vec2(0.42, 0.16);
		float row = floor(uv.y / size.y);
		vec2 cell = vec2(uv.x / size.x + mod(row, 2.0) * 0.5, uv.y / size.y);
		vec2 inside = fract(cell);
		float brick = hash(floor(cell));
		color = shade(base_rgb, (brick - 0.5) * 0.3 + (grain - 0.5) * 0.15);
		float mortar = step(inside.x, 0.05) + step(inside.y, 0.12);
		color = mix(color, accent_rgb, clamp(mortar, 0.0, 1.0));
	} else if (pattern == 5) {
		// Siding: horizontal boards with a shadow under each lip.
		float board = fract(uv.y / 0.22);
		color = shade(base_rgb, (hash(vec2(floor(uv.y / 0.22), 3.0)) - 0.5) * 0.08 + (noise(uv * vec2(1.5, 30.0)) - 0.5) * 0.06);
		color *= mix(0.78, 1.0, smoothstep(0.0, 0.18, board));
	} else if (pattern == 6) {
		// Shingles: staggered tabs, darker at each tab's lower edge.
		vec2 size = vec2(0.36, 0.24);
		float row = floor(uv.y / size.y);
		vec2 cell = vec2(uv.x / size.x + mod(row, 2.0) * 0.5, uv.y / size.y);
		vec2 inside = fract(cell);
		color = shade(base_rgb, (hash(floor(cell)) - 0.5) * 0.35);
		color *= mix(0.7, 1.0, smoothstep(0.0, 0.25, inside.y));
		color = mix(color, accent_rgb, step(inside.x, 0.04) * 0.6);
	} else if (pattern == 7) {
		// Planks: boards with gaps and wood grain running along them.
		float across = is_floor ? uv.x : uv.x;
		float plank = floor(across / 0.18);
		float along = is_floor ? uv.y : uv.y;
		float streak = noise(vec2(across * 40.0, along * 1.5 + plank * 7.0));
		color = shade(base_rgb, (hash(vec2(plank, 1.0)) - 0.5) * 0.25 + (streak - 0.5) * 0.25);
		color = mix(accent_rgb, color, smoothstep(0.0, 0.07, fract(across / 0.18)));
	} else if (pattern == 8) {
		// Bark: deep vertical furrows.
		float angle = atan(local_position.z, local_position.x) * 3.0;
		float furrow = noise(vec2(angle * 2.5, local_position.y * 2.0));
		color = shade(base_rgb, (furrow - 0.5) * 0.6);
		rough = 1.0;
	} else if (pattern == 9) {
		// Fabric: a soft weave and a little fuzz.
		float weave = sin(local_position.x * 260.0) * sin(local_position.y * 260.0);
		color = shade(base_rgb, weave * 0.04 + (noise(local_position.xy * 12.0) - 0.5) * 0.08);
		rough = 0.95;
	} else if (pattern == 10) {
		// Painted metal: smooth, with grime gathering low down.
		float grime = 1.0 - smoothstep(-0.4, 0.8, local_position.y);
		color = shade(base_rgb, (grain - 0.5) * 0.08 - grime * 0.18);
		rough = 0.45;
	} else if (pattern == 11) {
		// Dirt and sand: pebbly speckle in soft patches.
		color = mix(base_rgb, accent_rgb, smoothstep(0.3, 0.75, fbm(uv * 0.5)));
		color = shade(color, (hash(floor(uv * 30.0)) - 0.5) * 0.2);
	} else if (pattern == 12) {
		// Foliage: clumps of light and dark leaves.
		float clumps = fbm(local_position.xy * 4.0 + local_position.z * 3.0);
		color = shade(base_rgb, (clumps - 0.5) * 0.5);
		rough = 0.95;
	} else if (pattern == 13) {
		// Skin: smooth, with the faintest warmth variation.
		color = shade(base_rgb, (noise(local_position.xy * 6.0) - 0.5) * 0.04);
		rough = 0.7;
	} else if (pattern == 14) {
		// Stucco: trowel swirls and a fine sandy grit.
		float trowel = fbm(uv * 1.3 + vec2(fbm(uv * 0.6)));
		color = shade(base_rgb, (trowel - 0.5) * 0.2 + (hash(floor(uv * 90.0)) - 0.5) * 0.07);
		rough = 0.95;
	} else if (pattern == 15) {
		// Stone: rounded fieldstone set in mortar, or cut ashlar blocks (params.x).
		if (params.x >= 0.5) {
			float row = floor(uv.y / 0.32);
			float cut = uv.x / 0.55 + hash(vec2(row, 4.2)) * 3.0;
			vec2 inside = vec2(fract(cut), fract(uv.y / 0.32));
			float stone = hash(vec2(floor(cut), row));
			color = shade(mix(base_rgb, base_rgb * vec3(1.08, 1.0, 0.9), stone), (stone - 0.5) * 0.3 + (grain - 0.5) * 0.2);
			float joint = step(inside.x, 0.03) + step(inside.y, 0.06);
			color = mix(color, accent_rgb, clamp(joint, 0.0, 1.0));
		} else {
			vec3 cells = voronoi(uv * vec2(2.0, 2.8));
			float seam = cells.y - cells.x;
			color = mix(base_rgb, base_rgb * vec3(1.1, 1.0, 0.86), hash(vec2(cells.z, 1.3)));
			color = shade(color, (cells.z - 0.5) * 0.35 + (grain - 0.5) * 0.25);
			color *= mix(0.78, 1.0, smoothstep(0.0, 0.3, seam));
			color = mix(color, accent_rgb, 1.0 - smoothstep(0.05, 0.1, seam));
		}
		rough = 0.95;
	} else if (pattern == 16) {
		// Clay barrel tiles: straight columns of half-round tiles, each row lapping the next.
		float row = floor(uv.y / 0.34);
		float column = floor(uv.x / 0.26);
		float barrel = sin(fract(uv.x / 0.26) * 3.14159);
		color = shade(base_rgb, (hash(vec2(column, row)) - 0.5) * 0.22 + (grain - 0.5) * 0.1);
		color *= 0.62 + 0.38 * barrel;
		color *= mix(0.75, 1.0, smoothstep(0.0, 0.15, fract(uv.y / 0.34)));
		rough = 0.7;
	} else if (pattern == 17) {
		// Corrugated metal: ribs, with rust running down in streaks.
		float rib = sin(uv.x * 6.28318 / 0.13);
		color = shade(base_rgb, rib * 0.12 + (grain - 0.5) * 0.1);
		float streak = smoothstep(0.55, 0.8, noise(vec2(uv.x * 2.5, uv.y * 0.25)));
		color = mix(color, accent_rgb, streak * 0.35);
		rough = 0.55;
		spec = 0.4;
	} else if (pattern == 18) {
		// Cedar shakes: staggered rows of uneven shingles, each a different brown.
		float row = floor(uv.y / 0.22);
		float x = uv.x / 0.2 + hash(vec2(row, 9.1)) * 5.0;
		x += (noise(vec2(x * 0.7, row * 3.1)) - 0.5) * 0.9;
		vec2 inside = vec2(fract(x), fract(uv.y / 0.22));
		float tone = hash(vec2(floor(x), row));
		color = shade(base_rgb, (tone - 0.5) * 0.35 + (noise(vec2(uv.x * 30.0, uv.y * 2.0)) - 0.5) * 0.15);
		color *= mix(0.68, 1.0, smoothstep(0.0, 0.22, inside.y));
		color = mix(color, accent_rgb, step(inside.x, 0.05) * 0.7);
		rough = 0.95;
	} else if (pattern == 19) {
		// Board and batten: wide vertical boards, a raised batten over every seam.
		float d = fract(uv.x / 0.4);
		float batten = step(d, 0.14);
		color = shade(base_rgb, (noise(vec2(uv.x * 25.0, uv.y * 1.2)) - 0.5) * 0.1 + (hash(vec2(floor(uv.x / 0.4), 2.0)) - 0.5) * 0.06);
		color *= 1.0 + batten * 0.06;
		color *= mix(1.0, 0.72, smoothstep(0.14, 0.17, d) * (1.0 - smoothstep(0.17, 0.24, d)));
		color *= mix(0.85, 1.0, smoothstep(0.0, 0.02, d));
		rough = 0.9;
	} else if (pattern == 20) {
		// Gravel: packed pebbles in a few tones, dark between them.
		vec3 cells = voronoi(uv * 20.0);
		color = mix(base_rgb, accent_rgb, step(0.62, cells.z) * 0.6);
		color = shade(color, (cells.z - 0.5) * 0.4 + (fbm(uv * 0.5) - 0.5) * 0.2);
		color *= mix(0.6, 1.0, smoothstep(0.0, 0.15, cells.y - cells.x));
		rough = 1.0;
	} else if (pattern == 21) {
		// Brick pavers: running bond, or herringbone (params.x), with sand in the joints.
		float tone;
		float edge;
		if (params.x >= 0.5) {
			vec2 laid = herringbone(uv / 0.12);
			tone = laid.x;
			edge = laid.y * 0.12;
		} else {
			float row = floor(uv.y / 0.12);
			vec2 cell = vec2(uv.x / 0.24 + mod(row, 2.0) * 0.5, uv.y / 0.12);
			vec2 inside = fract(cell);
			tone = hash(floor(cell));
			edge = min(min(inside.x, 1.0 - inside.x) * 0.24, min(inside.y, 1.0 - inside.y) * 0.12);
		}
		color = shade(base_rgb, (tone - 0.5) * 0.25 + (grain - 0.5) * 0.12);
		color = mix(color, accent_rgb, 1.0 - smoothstep(0.004, 0.009, edge));
		rough = 0.9;
	} else if (pattern == 23) {
		// Cinder block: big gray blocks in running bond, pitted, with mortar lines.
		float row = floor(uv.y / 0.2);
		vec2 cell = vec2(uv.x / 0.4 + mod(row, 2.0) * 0.5, uv.y / 0.2);
		vec2 inside = fract(cell);
		color = shade(base_rgb, (hash(floor(cell)) - 0.5) * 0.12 + (hash(floor(uv * 60.0)) - 0.5) * 0.12 + (grain - 0.5) * 0.1);
		float mortar = step(inside.x, 0.025) + step(inside.y, 0.05);
		color = mix(color, accent_rgb, clamp(mortar, 0.0, 1.0));
		rough = 1.0;
	} else if (pattern == 24) {
		// Polished tile floor: big squares, thin grout, and a shine.
		vec2 inside = fract(uv / 0.6);
		color = shade(base_rgb, (hash(floor(uv / 0.6)) - 0.5) * 0.06 + (fbm(uv * 2.0) - 0.5) * 0.06);
		float grout = step(min(inside.x, inside.y), 0.012) + step(0.988, max(inside.x, inside.y));
		color = mix(color, accent_rgb, clamp(grout, 0.0, 1.0));
		rough = 0.22;
		spec = 0.5;
	} else {
		// Everything else: a painterly variation so no surface is perfectly flat.
		color = shade(base_rgb, (grain - 0.5) * 0.12);
	}
	// Snow settles on whatever faces up, in soft drifts; roads and gravel only get slush.
	// Skin (13) and tile_floor (24, always indoors) never get any.
	if (season_snow > 0.0 && cover > 0.0 && pattern != 13 && pattern != 24) {
		float drift = fbm(world_pos.xz * 0.35) + (noise(world_pos.xz * 3.0) - 0.5) * 0.12 + season_snow * 0.25;
		float snow = cover * season_snow * smoothstep(0.45, 0.8, world_up) * smoothstep(0.32, 0.5, drift);
		if (pattern == 2 || pattern == 25 || pattern == 20) {
			snow *= 0.2;
			color *= 1.0 - cover * season_snow * 0.08;
		}
		color = mix(color, SNOW_WHITE * (0.9 + 0.1 * fbm(world_pos.xz * 1.7)), snow);
		rough = mix(rough, 0.6, snow);
		spec = mix(spec, 0.3, snow);
	}
	ALBEDO = color;
	ROUGHNESS = rough;
	SPECULAR = spec;
}
"""

static var _shader: Shader
static var _cache: Dictionary = {}


## A material painting pattern in color. accent is the mortar, gaps, or second
## color; left out, it is a darker shade of color. params tune the pattern (see
## the top of this file). snow (0-1) is how much of the season's snow it takes:
## 0 for anything under a roof (store and garage floors, porches), and tile_floor
## never takes any. Shared between meshes with the same settings.
static func material(pattern: String, color: Color, accent := Color(0, 0, 0, 0), params := Vector4.ZERO, snow: float = 1.0) -> ShaderMaterial:
	var second := accent if accent.a > 0.0 else _default_accent(pattern, color)
	snow = clampf(snow, 0.0, 1.0)
	var key := "%s|%s|%s|%s|%s" % [pattern, color.to_html(), second.to_html(), params, snow]
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
	made.set_shader_parameter("params", params)
	made.set_shader_parameter("snow_cover", snow)
	_cache[key] = made
	return made


## The material for a mesh painted per vertex (props/house_kit.gd): the vertex
## color is the base (sRGB), CUSTOM0 the accent (sRGB, see accent_for), and the
## vertex alpha how much snow that face takes. One material per pattern and
## params, so a whole house of colors in one pattern is one draw call.
static func painted(pattern: String, params := Vector4.ZERO) -> ShaderMaterial:
	var key := "painted|%s|%s" % [pattern, params]
	if _cache.has(key):
		return _cache[key]
	var made := material(pattern, Color.WHITE, Color.BLACK, params, 1.0).duplicate() as ShaderMaterial
	made.set_shader_parameter("painted", true)
	_cache[key] = made
	return made


## The accent a pattern uses with color: accent itself when given (alpha > 0),
## else the pattern's default (the same one material() picks).
static func accent_for(pattern: String, color: Color, accent := Color(0, 0, 0, 0)) -> Color:
	return accent if accent.a > 0.0 else _default_accent(pattern, color)


## Road params (the "road" pattern): a line style from ROAD_LINES, half the
## road's width, the dash length, and the dash period (0: twice the dash).
static func road_params(style: String, half_width: float = 4.4, dash: float = 3.0, period: float = 0.0) -> Vector4:
	return Vector4(float(ROAD_LINES.get(style, 0)), half_width, dash, period)


static func _default_accent(pattern: String, color: Color) -> Color:
	match pattern:
		"brick", "cinderblock":
			return Color(0.78, 0.75, 0.7)
		"grass", "lawn_stripes":
			return color.lightened(0.07).lerp(Color(0.62, 0.6, 0.3), 0.2)
		"asphalt", "road":
			return color.darkened(0.45)
		"dirt":
			return color.darkened(0.15)
		"stone":
			return Color(0.7, 0.68, 0.64)
		"pavers":
			return Color(0.74, 0.68, 0.56)
		"gravel":
			return color.lightened(0.18).lerp(Color(0.6, 0.52, 0.42), 0.4)
		"corrugated":
			return color.darkened(0.2).lerp(Color(0.55, 0.32, 0.18), 0.6)
		"tile_floor":
			return color.darkened(0.25)
		"stucco":
			return color.darkened(0.12)
		_:
			return color.darkened(0.3)
