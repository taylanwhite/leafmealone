extends Node3D

## Authority: local on every peer, cosmetic (driving chunk D; docs/GAME.md, "The
## job lives at the client's real house"). Built under a job yard in the
## connected town, at its curb point (TownMap.CURB_POINT, in the yard's space):
## - a chalk outline on the asphalt that says PARK HERE, where Chefty parks
##   (the homeowner drew it; they have opinions about where trucks go);
## - a tall leaf-orange beacon over it with "Barb's place" on top, so the yard can
##   be found from across town. It breathes a little, fades out as you get close
##   (SITE_BEACON_FADE), and fades away with the chalk once the homeowner has
##   paid (SITE_PAID_FADE_SECONDS).
## Nothing here is shared, and nothing is built headless.

const _Strings = preload("res://ui/strings.gd")
## The chalk box, Chefty-sized: its length along the street (x) and across it (z), m.
const BOX := Vector2(7.2, 3.1)
const LINE: float = 0.16
## Just over the street's asphalt (its top is at y 0.01), so it never z-fights.
const CHALK_Y: float = 0.035
const CHALK := Color(0.97, 0.96, 0.9, 0.82)
const BEACON := Color(1.0, 0.43, 0.05)
const LABEL_HEIGHT: float = 6.5

var _holder: Node3D
var _beam: MeshInstance3D
var _glow: StandardMaterial3D
var _label: Label3D
var _chalk: Node3D
var _chalk_material: StandardMaterial3D
var _chalk_words: Label3D
var _time: float = 0.0
## 1 until the job is paid, then down to 0 over SITE_PAID_FADE_SECONDS.
var _unpaid: float = 1.0


func _ready() -> void:
	position = TownMap.CURB_POINT
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_build_chalk()
	_build_beacon()


func _build_chalk() -> void:
	_chalk = Node3D.new()
	_chalk.name = "ParkHere"
	add_child(_chalk)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = CHALK
	_chalk_material = material
	# Four sides, a little uneven, like it was drawn by hand.
	var sides: Array = [
		[Vector3(0.0, CHALK_Y, -BOX.y * 0.5), Vector3(BOX.x, 0.01, LINE), 0.012],
		[Vector3(0.05, CHALK_Y, BOX.y * 0.5), Vector3(BOX.x + 0.1, 0.01, LINE * 0.9), -0.01],
		[Vector3(-BOX.x * 0.5, CHALK_Y, 0.0), Vector3(LINE, 0.01, BOX.y + 0.05), 0.02],
		[Vector3(BOX.x * 0.5 + 0.04, CHALK_Y, 0.02), Vector3(LINE * 1.1, 0.01, BOX.y - 0.05), -0.025],
	]
	for index: int in sides.size():
		var side: Array = sides[index]
		var line := MeshInstance3D.new()
		line.name = "Line%d" % index
		var mesh := BoxMesh.new()
		mesh.size = side[1]
		line.mesh = mesh
		line.position = side[0]
		line.rotation.y = float(side[2])
		line.material_override = material
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		line.set_meta("keep_material", true)
		_chalk.add_child(line)
	var words := Label3D.new()
	words.name = "Words"
	words.text = _Strings.UI["site_park_here"]
	words.font_size = 150
	words.pixel_size = 0.006
	words.outline_size = 0
	words.modulate = CHALK
	words.shaded = false
	words.double_sided = false
	words.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	words.position = Vector3(0.0, CHALK_Y + 0.01, 0.0)
	_chalk.add_child(words)
	_chalk_words = words


func _build_beacon() -> void:
	_glow = StandardMaterial3D.new()
	_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glow.disable_fog = true
	_glow.albedo_color = Color(BEACON, 0.4)
	_beam = MeshInstance3D.new()
	_beam.name = "Beacon"
	var column := CylinderMesh.new()
	column.top_radius = Constants.SITE_BEACON_RADIUS * 0.35
	column.bottom_radius = Constants.SITE_BEACON_RADIUS
	column.height = Constants.SITE_BEACON_HEIGHT
	column.radial_segments = 12
	column.rings = 1
	column.cap_top = false
	column.cap_bottom = false
	_beam.mesh = column
	_beam.material_override = _glow
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.position = Vector3(0.0, Constants.SITE_BEACON_HEIGHT * 0.5, 0.0)
	_beam.set_meta("keep_material", true)
	# The beacon lives in its own top-level holder: from across town it is drawn
	# closer in, scaled down by the same amount, so it looks the same but stays
	# inside the camera's reach (_place_beacon).
	_holder = Node3D.new()
	_holder.name = "BeaconHolder"
	_holder.top_level = true
	add_child(_holder)
	_holder.add_child(_beam)
	_label = Label3D.new()
	_label.name = "Whose"
	_label.text = _whose()
	_label.font_size = 44
	# A steady size on screen, near or far, so the name reads from across town.
	_label.fixed_size = true
	_label.pixel_size = 0.0011
	_label.outline_size = 12
	_label.modulate = Color(1.0, 0.86, 0.55)
	_label.outline_modulate = Color(0.25, 0.12, 0.03)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.top_level = true
	add_child(_label)


## "Barb's place": the homeowner's first name, from the town's houses.
func _whose() -> String:
	var lot := get_parent()
	var house_id := int(lot.get("house_id")) if lot != null else -1
	var town := get_tree().get_first_node_in_group("town")
	var full := str(town.call("owner_name", house_id)) if town != null and house_id >= 0 else ""
	var first := full.get_slice(" ", 0) if full != "" else _Strings.UI["homeowner_name"]
	return _Strings.UI["site_beacon"] % first


func _process(delta: float) -> void:
	_time += delta
	if _label != null and _label.text.begins_with(_Strings.UI["homeowner_name"]):
		# The town's houses reached this peer after the yard did.
		_label.text = _whose()
	# The yard's replicated stage (a late joiner has it), or the paid phase.
	var paid := get_parent().has_method("is_paid") and bool(get_parent().call("is_paid"))
	var homeowner := get_parent().get_node_or_null("Homeowner")
	if homeowner != null:
		paid = paid or int(homeowner.get("_phase")) == 3
	if paid and _unpaid > 0.0:
		_unpaid = maxf(0.0, _unpaid - delta / maxf(Constants.SITE_PAID_FADE_SECONDS, 0.01))
		var chalk := CHALK
		chalk.a *= _unpaid
		_chalk_material.albedo_color = chalk
		_chalk_words.modulate = chalk
		_chalk.visible = _unpaid > 0.0
	var me := _local_body()
	var distance := INF
	if me != null:
		distance = Vector2(me.global_position.x - global_position.x, me.global_position.z - global_position.z).length()
	var fade := Constants.SITE_BEACON_FADE
	var share := _unpaid * clampf((distance - fade.x) / maxf(fade.y - fade.x, 0.01), 0.0, 1.0)
	var pulse := 1.0 - Constants.SITE_BEACON_PULSE * (0.5 + 0.5 * sin(_time * TAU * Constants.SITE_BEACON_PULSE_HZ))
	_glow.albedo_color = Color(BEACON, 0.75 * share * pulse)
	_beam.visible = share > 0.01
	_label.visible = share > 0.01
	_label.modulate.a = share
	_label.outline_modulate.a = share
	if share > 0.01:
		_place_beacon()


## Where the beacon is drawn: right over the curb, or (farther than the camera can
## see, SITE_BEACON_DRAW_METERS) pulled in along the line from the camera and
## shrunk by the same share, which looks exactly the same from there. Far away it
## also gets fatter, so it never thins to nothing.
func _place_beacon() -> void:
	var at := global_position
	var camera := get_viewport().get_camera_3d()
	var scale_by := 1.0
	var width := 1.0
	if camera != null:
		var eye := camera.global_position
		var distance := eye.distance_to(at)
		if distance > Constants.SITE_BEACON_DRAW_METERS:
			scale_by = Constants.SITE_BEACON_DRAW_METERS / distance
			at = eye + (at - eye) * scale_by
		width = maxf(1.0, distance / Constants.SITE_BEACON_WIDEN_FROM)
	_holder.global_transform = Transform3D(Basis.from_scale(Vector3(width, 1.0, width) * scale_by), at)
	var top := at + Vector3.UP * LABEL_HEIGHT * scale_by
	# The name keeps one size on screen and is drawn over everything, so it can sit
	# well inside the fog along the same line of sight and still read.
	if camera != null:
		var eye := camera.global_position
		var reach := eye.distance_to(top)
		if reach > Constants.SITE_BEACON_LABEL_METERS:
			top = eye + (top - eye) * (Constants.SITE_BEACON_LABEL_METERS / reach)
	_label.global_position = top


## This peer's own player (seated, they're carried along with the truck).
func _local_body() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as Node3D
	return null
