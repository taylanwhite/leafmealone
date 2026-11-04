extends Node

## Authority: local, cosmetic (art chunk 9; docs/GAME.md "What each
## neighborhood sounds like, and the hours it keeps"). The porch light by every
## front door. levels/town/house_builder.gd puts one beside each full-detail
## house's door (add()); this node, under the DaySky (levels/day_sky.gd), turns
## them on house by house as dusk falls and off as people go to bed, except the
## ones left on all night. When a house's light comes on and goes off is a pure
## function of its seed (lit_at), so every peer sees the same street; nothing is
## sent.
##
## A light is one MeshInstance3D in group "porch_lights": a dark backplate and a
## glass lens in one mesh (vertex color red marks the lens) under a material of
## its own (one shared shader; its "level" is the light's), meta porch_seed. Low
## graphics pay for nothing but a look down the list every
## PORCH_LIGHT_CHECK_SECONDS and a few frames of warm-up when one changes.

## Cartoon-chunky, like the rest of the street.
const LENS_SIZE := Vector3(0.16, 0.24, 0.12)
const PLATE_SIZE := Vector3(0.22, 0.34, 0.04)
## The glow round a lit bulb (m across): what reads from across the street.
const GLOW_SIZE: float = 1.1

const SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform float level = 0.0;
uniform float energy = 2.4;
uniform vec4 lit : source_color = vec4(1.0, 0.78, 0.45, 1.0);
uniform vec4 glass : source_color = vec4(0.86, 0.82, 0.7, 1.0);
uniform vec4 plate : source_color = vec4(0.12, 0.11, 0.1, 1.0);

void fragment() {
	float lens = COLOR.r;
	ALBEDO = mix(plate.rgb, mix(glass.rgb, lit.rgb, level), lens);
	EMISSION = lit.rgb * energy * level * lens;
	ROUGHNESS = mix(0.6, 0.3, lens);
}
"""

const GLOW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform float level = 0.0;
uniform vec4 lit : source_color = vec4(1.0, 0.78, 0.45, 1.0);

void vertex() {
	// Always facing the camera.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float a = pow(max(0.0, 1.0 - d), 2.4);
	ALBEDO = lit.rgb * a * level * 1.3;
}
"""

static var _shader: Shader
static var _glow_shader: Shader
static var _mesh: ArrayMesh

## [WeakRef(material), seed, level now, WeakRef(glow material)] for every light found.
var _lights: Array = []
var _scan_left: float = 0.0
var _check_left: float = 0.0
## How many are lit now (tests, remote play).
var lit_count: int = 0


func _ready() -> void:
	add_to_group("porch_light_control")
	if DisplayServer.get_name() == "headless":
		set_process(false)


## Puts a porch light over the door of house (door_head: the middle of the top
## of the door, house space), lit by seed's hours. Returns it.
static func add(house: Node3D, door_head: Vector3, seed_value: int) -> MeshInstance3D:
	var view := MeshInstance3D.new()
	view.name = "PorchLight"
	view.mesh = _fixture()
	view.material_override = _material()
	view.set_meta("keep_material", true)
	view.set_meta("porch_seed", seed_value)
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.visibility_range_end = Constants.ART_MEDIUM_PROP_RANGE
	view.position = door_head + Constants.PORCH_LIGHT_OFFSET
	view.add_to_group("porch_lights")
	var glow := MeshInstance3D.new()
	glow.name = "Glow"
	var quad := QuadMesh.new()
	quad.size = Vector2(GLOW_SIZE, GLOW_SIZE)
	glow.mesh = quad
	glow.material_override = _glow_material()
	glow.set_meta("keep_material", true)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.visibility_range_end = Constants.ART_MEDIUM_PROP_RANGE
	glow.position = Vector3(0.0, -0.01, PLATE_SIZE.z + LENS_SIZE.z + 0.02)
	view.add_child(glow)
	house.add_child(view)
	return view


## Whether a light with this seed is on at hour (7 to 26): on from its dusk
## hour, off at its bedtime unless it's one left on all night.
static func lit_at(seed_value: int, hour: float) -> bool:
	var on := lerpf(Constants.PORCH_LIGHT_ON.x, Constants.PORCH_LIGHT_ON.y, _share(seed_value, "on"))
	var off := lerpf(Constants.PORCH_LIGHT_OFF.x, Constants.PORCH_LIGHT_OFF.y, _share(seed_value, "off"))
	var all_night := _share(seed_value, "all_night") < Constants.PORCH_LIGHT_ALL_NIGHT
	return hour >= on and (all_night or hour < off)


static func _share(seed_value: int, what: String) -> float:
	return float(posmod(hash([seed_value, "porch", what]), 10000)) / 10000.0


func _process(delta: float) -> void:
	_scan_left -= delta
	if _scan_left <= 0.0:
		_scan_left = Constants.DAY_SKY_SCAN_SECONDS
		_scan()
	_check_left -= delta
	var check := _check_left <= 0.0
	if check:
		_check_left = Constants.PORCH_LIGHT_CHECK_SECONDS
	var warming := false
	var hour := _hour()
	var lit := 0
	for index: int in range(_lights.size() - 1, -1, -1):
		var entry: Array = _lights[index]
		var level := float(entry[2])
		# A steady light is only looked at on a check; one warming up every frame.
		if not check and (level <= 0.0 or level >= 1.0):
			lit += 1 if level > 0.5 else 0
			continue
		var material := (entry[0] as WeakRef).get_ref() as ShaderMaterial
		if material == null:
			_lights.remove_at(index)
			continue
		var target := 1.0 if lit_at(int(entry[1]), hour) else 0.0
		if level != target:
			level = move_toward(level, target, delta / Constants.PORCH_LIGHT_WARM_SECONDS)
			entry[2] = level
			material.set_shader_parameter("level", level)
			var glow := (entry[3] as WeakRef).get_ref() as ShaderMaterial if entry[3] != null else null
			if glow != null:
				glow.set_shader_parameter("level", level)
			warming = warming or level != target
		lit += 1 if level > 0.5 else 0
	lit_count = lit
	if warming:
		_check_left = 0.0


func _scan() -> void:
	var known := {}
	for entry: Array in _lights:
		var material: Object = (entry[0] as WeakRef).get_ref()
		if material != null:
			known[material.get_instance_id()] = true
	var hour := _hour()
	for node: Node in get_tree().get_nodes_in_group("porch_lights"):
		var view := node as MeshInstance3D
		if view == null:
			continue
		var material := view.material_override as ShaderMaterial
		if material == null or known.has(material.get_instance_id()):
			continue
		# Found already in the hour's state: a street streaming in shows its
		# lights as they are, without every one flicking on at once.
		var level := 1.0 if lit_at(int(view.get_meta("porch_seed", 0)), hour) else 0.0
		material.set_shader_parameter("level", level)
		var glow_view := view.get_node_or_null("Glow") as MeshInstance3D
		var glow := glow_view.material_override as ShaderMaterial if glow_view != null else null
		if glow != null:
			glow.set_shader_parameter("level", level)
		_lights.append([weakref(material), int(view.get_meta("porch_seed", 0)), level, weakref(glow) if glow != null else null])


func _hour() -> float:
	var clock := get_tree().get_first_node_in_group("day_clock")
	return float(clock.call("hour")) if clock != null else Constants.DAY_SKY_ART_HOUR


## A glow's own material: the shared shader at its own level, off.
static func _glow_material() -> ShaderMaterial:
	if _glow_shader == null:
		_glow_shader = Shader.new()
		_glow_shader.code = GLOW_SHADER
	var made := ShaderMaterial.new()
	made.shader = _glow_shader
	made.set_shader_parameter("lit", Constants.PORCH_LIGHT_COLOR)
	return made


## A light's own material: the shared shader at its own level, off.
static func _material() -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var made := ShaderMaterial.new()
	made.shader = _shader
	made.set_shader_parameter("energy", Constants.PORCH_LIGHT_ENERGY)
	made.set_shader_parameter("lit", Constants.PORCH_LIGHT_COLOR)
	return made


## The fixture, one surface: the backplate (vertex color black) and the lens in
## front of it (red). Built once.
static func _fixture() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for part: Array in [[PLATE_SIZE, Vector3(0.0, 0.0, PLATE_SIZE.z * 0.5), Color.BLACK], [LENS_SIZE, Vector3(0.0, -0.01, PLATE_SIZE.z + LENS_SIZE.z * 0.5), Color.RED]]:
		var box := BoxMesh.new()
		box.size = part[0]
		var arrays := box.get_mesh_arrays()
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var faces: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var order: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for index: int in order:
			vertices.append(points[index] + (part[1] as Vector3))
			normals.append(faces[index])
			colors.append(part[2] as Color)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _mesh
