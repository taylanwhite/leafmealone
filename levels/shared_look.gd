extends RefCounted

## The shared look for the store, the lot, and the border (docs/FEEL.md, "Look"):
## lit low-poly in a warm late-afternoon autumn light. Surfaces keep the colors
## they were built with and get real shading, soft shadows, sky light, ambient
## occlusion, a little glow, and warm haze in the distance. The outline pass in
## levels/outline_pass.gd draws on top. Meshes that animate their own material
## (glows, beacons) opt out with set_meta("keep_material", true).

const _Palette: Script = preload("res://assets/materials/palette.gd")
const _Surfaces = preload("res://props/surfaces.gd")
## Surfaces for meshes built in scene files, found by the name of the node they sit
## under. Code-built meshes say what they are with set_meta("surface", ...).
const SURFACE_BY_NAME: Dictionary = {
	"House": "siding", "Fence": "planks", "Counter": "planks", "Car": "metal",
	"HedgeRow": "foliage", "Curb": "concrete", "TruckPad": "concrete", "Pad": "concrete",
}
## Floors depend on which zone they belong to.
const FLOOR_BY_ZONE: Dictionary = {"StoreZone": "asphalt", "LotZone": "grass", "BorderZone": "dirt"}
## Fog fades the scenery out between these distances, in meters.
const FOG_BEGIN: float = 90.0
const FOG_END: float = 260.0
const SKY_TOP := Color(0.33, 0.55, 0.82)
const SKY_HORIZON := Color(0.96, 0.82, 0.64)
const SUN_COLOR := Color(1.0, 0.87, 0.7)
## Late afternoon: low and from the side, so shapes get long soft shadows.
const SUN_ROTATION_DEGREES := Vector3(-32.0, -38.0, 0.0)
const SUN_ENERGY: float = 1.35


static func apply(root: Node) -> void:
	_environment(root)
	_sun(root)
	_visit(root)


static func restyle(node: Node) -> void:
	if node is MeshInstance3D:
		_shade(node as MeshInstance3D)


static func _environment(root: Node) -> void:
	var world_environment := root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_environment == null or world_environment.environment == null:
		return
	var environment := world_environment.environment
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = SKY_TOP
	sky_material.sky_horizon_color = SKY_HORIZON
	# Below the horizon the sky matches the haze, so the ground fades into it without a band.
	sky_material.ground_horizon_color = SKY_HORIZON
	sky_material.ground_bottom_color = SKY_HORIZON.darkened(0.08)
	sky_material.ground_curve = 0.5
	sky_material.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.75
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.05
	environment.ssao_enabled = true
	environment.ssao_radius = 1.2
	environment.ssao_intensity = 1.6
	environment.glow_enabled = true
	environment.glow_intensity = 0.35
	environment.glow_bloom = 0.04
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.05
	environment.adjustment_saturation = 1.15
	# Distance fades into a warm haze, so the scenery's ground edge never shows as a line.
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = SKY_HORIZON
	environment.fog_density = 1.0
	environment.fog_depth_begin = FOG_BEGIN
	environment.fog_depth_end = FOG_END
	environment.fog_sky_affect = 0.0


static func _sun(root: Node) -> void:
	var sun := root.get_node_or_null("Sun") as DirectionalLight3D
	if sun == null:
		return
	sun.rotation_degrees = SUN_ROTATION_DEGREES
	sun.light_color = SUN_COLOR
	sun.light_energy = SUN_ENERGY
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 90.0


static func _visit(node: Node) -> void:
	if node is MeshInstance3D:
		_shade(node as MeshInstance3D)
	for child: Node in node.get_children():
		_visit(child)


## Paint every plain mesh with a procedural surface (props/surfaces.gd), lit and
## matte like painted toys. Its own color is the base. Safe to call again after a
## mesh is tagged: the first color it had is remembered.
static func _shade(mesh: MeshInstance3D) -> void:
	if mesh.has_meta("keep_material"):
		return
	var base: Color
	if mesh.has_meta("surface_base"):
		base = mesh.get_meta("surface_base")
	else:
		var source := mesh.material_override as StandardMaterial3D
		if source == null:
			source = mesh.get_active_material(0) as StandardMaterial3D
		if source == null:
			return
		base = source.albedo_color
		mesh.set_meta("surface_base", base)
	var surface := str(mesh.get_meta("surface", _surface_by_name(mesh)))
	mesh.material_override = _Surfaces.material(surface, base)


static func _surface_by_name(mesh: MeshInstance3D) -> String:
	var node: Node = mesh
	for _level: int in 3:
		node = node.get_parent()
		if node == null:
			break
		if node.name == "Floor":
			var zone: Node = node.get_parent()
			while zone != null and not FLOOR_BY_ZONE.has(String(zone.name)):
				zone = zone.get_parent()
			# A lot scene's own floor sits in LotZone too, a few levels down.
			return FLOOR_BY_ZONE.get(String(zone.name), "concrete") if zone != null else "concrete"
		if SURFACE_BY_NAME.has(String(node.name)):
			return SURFACE_BY_NAME[String(node.name)]
	return "plain"
