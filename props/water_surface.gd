extends RefCounted

## Authority: local, cosmetic. Water that looks like water, in four kinds, each
## one shared ShaderMaterial:
## - "pool": bright turquoise with drifting caustic bands (in-ground pools, hot
##   tubs, fountain basins).
## - "lake": deep blue-green, gentle waves moving the vertices (give the plane
##   some subdivisions), a fresnel fade toward the sky's horizon color.
## - "fountain": a falling sheet that scrolls down a ribbon (sheet() builds one).
## - "frozen": opaque white-blue ice with crack lines; the lake in winter
##   (lake_kind(season)). No sign anywhere says the word, per docs/GAME.md.
## Everything animates from TIME on each peer; nothing feeds back into play.
## Meshes using these set meta keep_material so levels/shared_look.gd leaves
## them alone.

const POOL_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

uniform vec4 shallow : source_color = vec4(0.42, 0.86, 0.9, 1.0);
uniform vec4 deep : source_color = vec4(0.12, 0.55, 0.72, 1.0);
uniform vec4 sky : source_color = vec4(0.78, 0.9, 0.96, 1.0);

varying vec3 world_pos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float n = noise(p * 1.6 + vec2(TIME * 0.31, TIME * 0.17)) + noise(p * 2.2 - vec2(TIME * 0.21, -TIME * 0.27));
	float bands = 1.0 - smoothstep(0.0, 0.11, abs(n - 1.0));
	float depth = noise(p * 0.35) * 0.6;
	vec3 color = mix(shallow.rgb, deep.rgb, depth) + vec3(bands * 0.22);
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(color, sky.rgb, fresnel * 0.55);
	ROUGHNESS = 0.06;
	SPECULAR = 0.7;
}
"""

const LAKE_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

uniform vec4 shallow : source_color = vec4(0.2, 0.42, 0.44, 1.0);
uniform vec4 deep : source_color = vec4(0.08, 0.24, 0.3, 1.0);
uniform vec4 horizon : source_color = vec4(0.72, 0.82, 0.88, 1.0);
uniform float wave_height = 0.05;

varying vec3 world_pos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float wave = sin(world.x * 0.35 + TIME * 0.8) * 0.6 + sin(world.z * 0.5 + TIME * 0.55) * 0.4;
	VERTEX.y += wave * wave_height;
	world_pos = world;
}

void fragment() {
	vec2 p = world_pos.xz;
	// Ripples tilt the normal a little, so the sun glints move.
	float e = 0.15;
	float h0 = noise(p * 0.9 + TIME * 0.12);
	float hx = noise((p + vec2(e, 0.0)) * 0.9 + TIME * 0.12);
	float hz = noise((p + vec2(0.0, e)) * 0.9 + TIME * 0.12);
	vec3 ripple = normalize(vec3((h0 - hx) * 1.4, 1.0, (h0 - hz) * 1.4));
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(ripple, 0.0)).xyz, 0.3));
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 color = mix(deep.rgb, shallow.rgb, noise(p * 0.08) * 0.7);
	ALBEDO = mix(color, horizon.rgb, fresnel * 0.5);
	ROUGHNESS = 0.18;
	SPECULAR = 0.45;
}
"""

const FOUNTAIN_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

uniform vec4 water : source_color = vec4(0.82, 0.94, 1.0, 1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	// UV.x runs around the sheet, UV.y down it; the streaks fall.
	float streak = noise(vec2(UV.x * 26.0, UV.y * 3.0 - TIME * 2.4));
	float foam = smoothstep(0.75, 1.0, UV.y);
	ALBEDO = mix(water.rgb, vec3(1.0), streak * 0.35 + foam * 0.4);
	ALPHA = clamp(0.32 + streak * 0.4 + foam * 0.3, 0.0, 0.92);
	ROUGHNESS = 0.1;
	SPECULAR = 0.6;
}
"""

const FROZEN_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

uniform vec4 ice : source_color = vec4(0.84, 0.9, 0.96, 1.0);
uniform vec4 crack : source_color = vec4(0.56, 0.68, 0.78, 1.0);

varying vec3 world_pos;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz * 0.35;
	vec2 cell = floor(p);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 point = o + hash2(cell + o);
			float d = length(point - fract(p));
			if (d < f1) { f2 = f1; f1 = d; } else if (d < f2) { f2 = d; }
		}
	}
	float line = 1.0 - smoothstep(0.0, 0.035, f2 - f1);
	vec3 color = mix(ice.rgb, crack.rgb, line * 0.7);
	color = mix(color, vec3(0.96, 0.97, 1.0), smoothstep(0.3, 0.9, hash2(cell).x) * 0.3);
	ALBEDO = color;
	ROUGHNESS = 0.3;
	SPECULAR = 0.5;
}
"""

const KINDS: Array[String] = ["pool", "lake", "fountain", "frozen"]

static var _cache: Dictionary = {}


## The shared material for kind (one of KINDS; anything else is "pool").
static func material(kind: String) -> ShaderMaterial:
	if not KINDS.has(kind):
		kind = "pool"
	if _cache.has(kind):
		return _cache[kind]
	var shader := Shader.new()
	match kind:
		"lake":
			shader.code = LAKE_SHADER
		"fountain":
			shader.code = FOUNTAIN_SHADER
		"frozen":
			shader.code = FROZEN_SHADER
		_:
			shader.code = POOL_SHADER
	var made := ShaderMaterial.new()
	made.shader = shader
	_cache[kind] = made
	return made


## The lake's kind for a season (core/seasons.gd): frozen in winter.
static func lake_kind(season: int) -> String:
	return "frozen" if season == 1 else "lake"


## A flat water surface size.x by size.y, centered on its node, with the kind's
## material. subdivide splits it for the lake's waves.
static func plane(size: Vector2, kind: String, subdivide: int = 0) -> MeshInstance3D:
	var mesh := PlaneMesh.new()
	mesh.size = size
	mesh.subdivide_width = subdivide
	mesh.subdivide_depth = subdivide
	return _view(mesh, kind)


## A round water surface (a fountain basin, a hot tub's round cousin).
static func disc(radius: float, kind: String, sides: int = 16) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.02
	mesh.radial_segments = sides
	mesh.rings = 1
	mesh.cap_bottom = false
	return _view(mesh, kind)


## A falling sheet of water: an open ring from radius top_radius at height
## top_y down to bottom_radius at bottom_y, with UVs (x around, y down) for the
## "fountain" material.
static func sheet(top_radius: float, top_y: float, bottom_radius: float, bottom_y: float, sides: int = 16) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var rows := 4
	for step: int in sides:
		for row: int in rows:
			var corners: Array = []
			for corner: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var angle := TAU * float(step + corner.x) / float(sides)
				var t := float(row + corner.y) / float(rows)
				# The sheet bows outward as it falls.
				var radius := lerpf(top_radius, bottom_radius, t) + sin(t * PI) * 0.06
				var y := lerpf(top_y, bottom_y, t * t)
				corners.append([Vector3(cos(angle) * radius, y, sin(angle) * radius), Vector3(cos(angle), 0.2, sin(angle)).normalized(), Vector2(float(step + corner.x) / float(sides), t)])
			for entry: Array in corners:
				vertices.append(entry[0])
				normals.append(entry[1])
				uvs.append(entry[2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## A MeshInstance3D drawing mesh with kind's water.
static func view(mesh: Mesh, kind: String) -> MeshInstance3D:
	return _view(mesh, kind)


static func _view(mesh: Mesh, kind: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material(kind)
	node.set_meta("keep_material", true)
	node.set_meta("water", kind)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node
