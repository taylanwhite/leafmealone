extends RefCounted

## Snaps mesh colors to the shared palette and turns shading off.
## The store, the lot, and the border all go through this so the boxes read as one game.

const _Palette: Script = preload("res://assets/materials/palette.gd")
## Fog fades the scenery out between these distances, in meters.
const FOG_BEGIN: float = 90.0
const FOG_END: float = 240.0


static func apply(root: Node) -> void:
	_environment(root)
	_visit(root)


static func restyle(node: Node) -> void:
	if node is MeshInstance3D:
		_flatten(node as MeshInstance3D)


static func _environment(root: Node) -> void:
	var world_environment := root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_environment == null or world_environment.environment == null:
		return
	var environment := world_environment.environment
	environment.background_color = _Palette.SKY
	environment.ambient_light_color = _Palette.SKY
	environment.ambient_light_energy = 0.9
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.06
	environment.adjustment_saturation = 1.12
	# Distance fades into the sky, so the scenery's ground edge never shows as a line.
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = _Palette.SKY
	environment.fog_density = 1.0
	environment.fog_depth_begin = FOG_BEGIN
	environment.fog_depth_end = FOG_END
	environment.fog_sky_affect = 0.0


static func _visit(node: Node) -> void:
	if node is MeshInstance3D:
		_flatten(node as MeshInstance3D)
	for child: Node in node.get_children():
		_visit(child)


static func _flatten(mesh: MeshInstance3D) -> void:
	# Effects that animate their own material (glows, beacons) opt out.
	if mesh.has_meta("keep_material"):
		return
	var source := mesh.material_override as StandardMaterial3D
	if source == null:
		source = mesh.get_active_material(0) as StandardMaterial3D
	if source == null:
		return
	var flat := source.duplicate() as StandardMaterial3D
	flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	flat.albedo_color = _Palette.nearest(source.albedo_color)
	mesh.material_override = flat
