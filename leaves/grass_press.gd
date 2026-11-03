extends RefCounted

## Authority: local, cosmetic. Grass that lies flat under leaves: props/
## stylized.gd's material with leaves/leaf_shaders.gd GRASS_PRESS_SNIPPET put
## at the top of its vertex(), so each tuft is squashed by the leaf cover under
## its root (the cover map's A, which the leaf view eases: grass springs back up
## behind the rake). Off where there is no leaf field (leaf_rect zero) and
## outside it. stylized.gd itself is untouched; cached per options like it.

const _Stylized = preload("res://props/stylized.gd")
const _LeafShaders = preload("res://leaves/leaf_shaders.gd")

static var _shaders: Dictionary = {}
static var _cache: Dictionary = {}


## The grass material for these props/stylized.gd options, pressed by leaves.
## Falls back to the plain stylized material when the project has no leaf
## cover global (an older project file).
static func material(options: Dictionary = {}) -> ShaderMaterial:
	if not ProjectSettings.has_setting("shader_globals/leaf_cover_map"):
		return _Stylized.material(options)
	var key := str(options)
	if _cache.has(key):
		return _cache[key]
	var plain := _Stylized.material(options)
	var two_sided := bool(options.get("double_sided", false))
	if not _shaders.has(two_sided):
		var code: String = _Stylized.SHADER
		if two_sided:
			code = code.replace("cull_back", "cull_disabled")
		code = code.replace("varying float world_up;", "varying float world_up;\n" + _LeafShaders.GRASS_PRESS_GLOBALS)
		code = code.replace("void vertex() {", "void vertex() {\n" + _LeafShaders.GRASS_PRESS_SNIPPET)
		var shader := Shader.new()
		shader.code = code
		_shaders[two_sided] = shader
	var made := ShaderMaterial.new()
	made.shader = _shaders[two_sided]
	for parameter: String in ["wind", "roughness_value", "specular_value", "translucency", "snow_cover", "seasonal"]:
		made.set_shader_parameter(parameter, plain.get_shader_parameter(parameter))
	made.set_shader_parameter("leaf_press_max", Constants.LEAF_GRASS_PRESS_MAX)
	_cache[key] = made
	return made
