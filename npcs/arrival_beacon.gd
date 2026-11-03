extends Node3D

## Authority: local, cosmetic only. The Courtesy Flare: it marks where the NICE BOYS
## will arrive during the warning (docs/GAME.md, "2026-11-02, the Courtesy Shuttle";
## OQ-012 closed). ui/run_cues.gd places it and calls set_urgency() every frame.
##   - a pulsing amber column, which reads from across the lot (amber, never a real
##     agency's colors)
##   - "Seal": a 1.2 m Daisy Seal (props/nice_seal.gd) over the column, spinning
##     faster as the crew gets closer, and bobbing
##   - "Cones": a ring of orange-and-white traffic cones on the ground
##   - "Notices": courtesy notice slips fluttering down around the column, forever
##   - "Label": NICE BOYS INBOUND (ui/strings.gd beacon_label)
## When the crew arrives, dismiss() folds it away instead of it vanishing.

const _NiceSeal = preload("res://props/nice_seal.gd")
const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const _Strings = preload("res://ui/strings.gd")

const COLUMN_HEIGHT: float = 14.0
const COLOR := Color(1.0, 0.6, 0.12)
const SEAL_RADIUS: float = 1.2
## The seal floats over the column with its ribbon tails clear of it.
const SEAL_HEIGHT: float = COLUMN_HEIGHT + 1.9
const CONE_ORANGE := Color(1.0, 0.45, 0.08)
const NOTICE_PAPER := Color(0.98, 0.98, 0.96)

var _light: OmniLight3D
var _column: MeshInstance3D
var _material: StandardMaterial3D
var _seal: Node3D
var _cones: MeshInstance3D
var _notices: Node3D
var _label: Label3D
var _urgency: float = 0.0
var _time: float = 0.0
## Each notice: [phase offset 0..1, fall seconds, angle, distance from the column].
var _slips: Array = []
var _dismiss_left: float = -1.0


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
	_column.name = "Column"
	_column.mesh = mesh
	_column.material_override = _material
	_column.position.y = COLUMN_HEIGHT * 0.5
	_keep(_column)
	add_child(_column)
	_light = OmniLight3D.new()
	_light.light_color = COLOR
	_light.omni_range = 9.0
	_light.position.y = 1.5
	add_child(_light)
	_seal = Node3D.new()
	_seal.name = "Seal"
	_seal.position.y = SEAL_HEIGHT
	add_child(_seal)
	var seal_view := _NiceSeal.node(SEAL_RADIUS, Vector3.FORWARD)
	_keep(seal_view)
	_seal.add_child(seal_view)
	_cones = _Stylized.instance(_cones_mesh(), {"roughness": 0.6, "specular": 0.2})
	_cones.name = "Cones"
	_keep(_cones)
	add_child(_cones)
	_build_notices()
	_label = Label3D.new()
	_label.name = "Label"
	_label.text = str(_Strings.UI["beacon_label"])
	_label.font_size = 96
	_label.pixel_size = 0.012
	_label.outline_size = 18
	_label.modulate = Color(1.0, 0.93, 0.8)
	_label.outline_modulate = Color(0.33, 0.24, 0.6)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = SEAL_HEIGHT + SEAL_RADIUS * 1.6
	_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_label)


## 0 when the warning starts, 1 when the crew arrives.
func set_urgency(value: float) -> void:
	_urgency = clampf(value, 0.0, 1.0)


## The crew is here: fold the flare away over Constants.BEACON_DISMISS_SECONDS, then free it.
func dismiss() -> void:
	if _dismiss_left < 0.0:
		_dismiss_left = Constants.BEACON_DISMISS_SECONDS


## Runs the animation this many seconds ahead at once (the studio, to catch the
## notices mid-fall).
func advance(seconds: float) -> void:
	var step := 1.0 / 30.0
	var left := seconds
	while left > 0.0:
		_animate(minf(step, left))
		left -= step


func _process(delta: float) -> void:
	_animate(delta)


func _animate(delta: float) -> void:
	_time += delta
	var rate := lerpf(3.0, 10.0, _urgency)
	var pulse := 0.5 + 0.5 * sin(_time * rate)
	var fold := 1.0
	if _dismiss_left >= 0.0:
		_dismiss_left -= delta
		fold = clampf(_dismiss_left / maxf(Constants.BEACON_DISMISS_SECONDS, 0.01), 0.0, 1.0)
		if _dismiss_left <= 0.0:
			queue_free()
			return
	var eased := fold * fold * (3.0 - 2.0 * fold)
	_light.light_energy = lerpf(0.5, 3.0, pulse) * (0.6 + _urgency) * eased
	_material.albedo_color = Color(COLOR, lerpf(0.15, 0.55, pulse) * eased)
	# The column narrows to a thread as it folds away.
	_column.scale = Vector3(eased, 1.0, eased)
	if _seal != null:
		_seal.rotation.y = wrapf(_seal.rotation.y + lerpf(Constants.BEACON_SPIN_MIN, Constants.BEACON_SPIN_MAX, _urgency) * delta, -PI, PI)
		_seal.position.y = SEAL_HEIGHT + sin(_time * 1.7) * 0.25
		# A little pop up before it shrinks away.
		var pop := 1.0 + 0.25 * sin(PI * (1.0 - fold)) if fold < 1.0 else 1.0
		_seal.scale = Vector3.ONE * maxf(eased * pop, 0.001)
	if _cones != null:
		# The cones sink into the ground.
		_cones.scale = Vector3(1.0, maxf(eased, 0.001), 1.0)
	if _label != null:
		_label.modulate.a = eased
		_label.outline_modulate.a = eased
	_flutter(eased)


## Each slip falls from Constants.BEACON_NOTICE_HEIGHT, swinging side to side and
## turning as paper does, grows in at the top and shrinks as it lands, and starts
## again.
func _flutter(fold: float) -> void:
	if _notices == null:
		return
	for index: int in _slips.size():
		var slip: Array = _slips[index]
		var view := _notices.get_child(index) as Node3D
		var fall: float = slip[1]
		var p := fposmod(_time / fall + float(slip[0]), 1.0)
		var angle: float = float(slip[2]) + p * 1.3
		var reach: float = slip[3]
		var swing := sin(_time * 2.6 + float(index) * 1.7) * 0.45
		view.position = Vector3(cos(angle) * reach + swing * sin(angle), Constants.BEACON_NOTICE_HEIGHT * (1.0 - p) + 0.02, sin(angle) * reach - swing * cos(angle))
		view.rotation = Vector3(sin(_time * 3.1 + float(index)) * 0.6, _time * 1.4 + float(index), cos(_time * 2.3 + float(index) * 0.7) * 0.5)
		var grow := clampf(minf(p / 0.05, (1.0 - p) / 0.08), 0.0, 1.0)
		view.scale = Vector3.ONE * maxf(grow * fold, 0.001)


func _build_notices() -> void:
	_notices = Node3D.new()
	_notices.name = "Notices"
	add_child(_notices)
	var kit := _MeshKit.new()
	# Big enough to read as paper from across the lot.
	kit.box(Vector3.ZERO, Vector3(0.34, 0.005, 0.46), NOTICE_PAPER)
	# A lavender header band and three lines of fine print, both faces.
	for face: float in [-1.0, 1.0]:
		kit.box(Vector3(0.0, face * 0.0035, -0.17), Vector3(0.34, 0.002, 0.09), _NiceSeal.LAVENDER)
		for line: int in 3:
			kit.box(Vector3(-0.03, face * 0.0035, -0.04 + float(line) * 0.08), Vector3(0.22, 0.002, 0.02), Color(0.55, 0.55, 0.6))
	var mesh := kit.commit()
	var material := {"roughness": 0.8, "specular": 0.1}
	var rng := RandomNumberGenerator.new()
	rng.seed = 9171
	for index: int in Constants.BEACON_NOTICES:
		var view := _Stylized.instance(mesh, material)
		view.name = "Notice%d" % index
		_keep(view)
		_notices.add_child(view)
		var fall := rng.randf_range(Constants.BEACON_NOTICE_FALL.x, Constants.BEACON_NOTICE_FALL.y)
		_slips.append([float(index) / float(Constants.BEACON_NOTICES), fall, TAU * float(index) / float(Constants.BEACON_NOTICES), rng.randf_range(1.3, 2.6)])
	_flutter(1.0)


## Six traffic cones in a ring on the ground, each on a black square foot with a
## white reflective band.
func _cones_mesh() -> ArrayMesh:
	var kit := _MeshKit.new()
	var flat := {"lumps": 0.0}
	for index: int in 6:
		var angle := TAU * float(index) / 6.0 + PI / 6.0
		var at := Vector3(cos(angle), 0.0, sin(angle)) * Constants.BEACON_CONE_RING
		kit.box(at + Vector3(0.0, 0.02, 0.0), Vector3(0.36, 0.04, 0.36), Color(0.12, 0.12, 0.13), Basis(Vector3.UP, angle))
		kit.cone(at + Vector3(0.0, 0.04, 0.0), 0.15, 0.55, CONE_ORANGE, 12, flat)
		kit.cone(at + Vector3(0.0, 0.25, 0.0), 0.1, 0.12, Color(0.97, 0.97, 0.95), 12, {"lumps": 0.0, "top_radius": 0.067})
	return kit.commit()


func _keep(view: GeometryInstance3D) -> void:
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.set_meta("keep_material", true)
