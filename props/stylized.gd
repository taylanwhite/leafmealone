extends RefCounted

## Authority: local, cosmetic. The material for meshes built by props/mesh_kit.gd:
## color from the mesh's vertex colors (authored in sRGB), soft wrapped
## lighting like painted toys, and wind that moves each vertex by its color's
## alpha, so tree crowns and grass sway while trunks stay put. One material per
## setting, shared. levels/shared_look.gd leaves it alone (keep_material).

const SHADER := """
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx, cull_back;

uniform float wind = 0.0;
uniform float roughness_value = 0.92;
uniform float specular_value = 0.12;
uniform float translucency = 0.0;

varying float sway;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void vertex() {
	sway = COLOR.a;
	if (wind > 0.0 && COLOR.a > 0.0) {
		vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float phase = dot(NODE_POSITION_WORLD.xz, vec2(0.37, 0.21));
		// A slow lean, plus a quick small flutter that differs across the crown.
		vec3 lean = vec3(sin(TIME * 1.1 + phase), 0.0, cos(TIME * 0.9 + phase * 1.3)) * 0.55;
		vec3 flutter = vec3(
			sin(TIME * 3.9 + world.x * 2.1 + world.z * 1.3),
			sin(TIME * 3.1 + world.z * 2.4) * 0.4,
			cos(TIME * 3.5 + world.y * 1.8 + world.x * 0.7)) * 0.22;
		vec3 push = (lean + flutter) * wind * COLOR.a;
		VERTEX += inverse(mat3(MODEL_MATRIX)) * push;
	}
}

void fragment() {
	ALBEDO = to_linear(COLOR.rgb);
	ROUGHNESS = roughness_value;
	SPECULAR = specular_value;
	// Light through thin leaves on the shadow side.
	BACKLIGHT = ALBEDO * translucency * sway;
}
"""

## Clouds: their vertex colors are the whole look (shading baked in), with no
## lighting and no fog, so they stay crisp far out past the haze.
const CLOUD_SHADER := """
shader_type spatial;
render_mode unshaded, fog_disabled, cull_back, shadows_disabled;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void fragment() {
	ALBEDO = to_linear(COLOR.rgb);
}
"""

static var _shader: Shader
static var _cloud_material: ShaderMaterial
static var _cache: Dictionary = {}


## options: wind (meters of sway at alpha 1), roughness, specular, translucency.
static func material(options: Dictionary = {}) -> ShaderMaterial:
	var key := str(options)
	if _cache.has(key):
		return _cache[key]
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var made := ShaderMaterial.new()
	made.shader = _shader
	made.set_shader_parameter("wind", float(options.get("wind", 0.0)))
	made.set_shader_parameter("roughness_value", float(options.get("roughness", 0.92)))
	made.set_shader_parameter("specular_value", float(options.get("specular", 0.12)))
	made.set_shader_parameter("translucency", float(options.get("translucency", 0.0)))
	_cache[key] = made
	return made


static func cloud_material() -> ShaderMaterial:
	if _cloud_material == null:
		var shader := Shader.new()
		shader.code = CLOUD_SHADER
		_cloud_material = ShaderMaterial.new()
		_cloud_material.shader = shader
	return _cloud_material


## A MeshInstance3D for mesh with this material, kept out of the shared look.
static func instance(mesh: Mesh, options: Dictionary = {}) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material(options)
	node.set_meta("keep_material", true)
	return node
