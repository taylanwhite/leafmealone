extends Node3D

## Authority: local, cosmetic only. Foreshadows where the crew will arrive
## during the warning: a tall column of light with a pulsing glow that reads
## from across the lot. Placeholder visual until the crew's look is designed
## (OQ-012). Deliberately amber, not any real agency's colors.

const COLUMN_HEIGHT: float = 14.0
const COLOR := Color(1.0, 0.6, 0.12)

var _light: OmniLight3D
var _column: MeshInstance3D
var _material: StandardMaterial3D
var _urgency: float = 0.0


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = Color(COLOR, 0.35)
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.6
	mesh.bottom_radius = 0.9
	mesh.height = COLUMN_HEIGHT
	_column = MeshInstance3D.new()
	_column.mesh = mesh
	_column.material_override = _material
	_column.position.y = COLUMN_HEIGHT * 0.5
	_column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Keep the shared look from restyling it (levels/shared_look.gd).
	_column.set_meta("keep_material", true)
	add_child(_column)
	_light = OmniLight3D.new()
	_light.light_color = COLOR
	_light.omni_range = 9.0
	_light.position.y = 1.5
	add_child(_light)


## 0 when the warning starts, 1 when the crew arrives.
func set_urgency(value: float) -> void:
	_urgency = clampf(value, 0.0, 1.0)


func _process(_delta: float) -> void:
	var rate := lerpf(3.0, 10.0, _urgency)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * rate)
	_light.light_energy = lerpf(0.5, 3.0, pulse) * (0.6 + _urgency)
	_material.albedo_color = Color(COLOR, lerpf(0.15, 0.55, pulse))
