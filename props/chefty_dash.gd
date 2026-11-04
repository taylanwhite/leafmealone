extends Node3D

## Authority: local, cosmetic. Chefty's instruments (p1-dash; docs/GAME.md
## "Chefty's dash"): the gauge pod on the dash in front of the driver, built in
## code like everything else. Every instrument shows something true, or isn't
## there:
## - the speedometer: a cream dial to 50 MPH, its needle sweeping with Chefty's
##   real ground speed (how fast it actually goes over the road, not how hard
##   the sim pushes it into a wall), on a damped spring so it eases and settles
##   like a real needle against its stop pin;
## - the odometer in the dial's window: five white-on-black mile drums and a
##   black-on-white tenths drum that roll like real ones (the tenths turn all the
##   time, a higher drum only turns over while every drum below it rolls from 9
##   to 0). The miles are the crew's, kept in the save (chefty_drive.gd);
## - the check-engine lamp: lit while Chefty has a dent (driving C3), blinking at
##   the most it can take, dark again after Marty's Body Shop. The lamps light for
##   a moment when someone takes the wheel, the way a real dash checks its bulbs.
## Chefty burns no fuel, so there's no fuel gauge.
##
## The node sits on the face of the pod (FACE_AT, tilted back by FACE_TILT toward
## the driver's eye); its own space has the dial in the XY plane facing +Z. The
## odometer's drums are behind the dial's window: the dial hides their digits
## above and below it by depth, the way the face plate of a real one does.
## chefty_drive.gd feeds it with set_reading() every physics tick; the needle and
## the drums move every frame. Everything here is out of sight (and out of the
## draw) past Constants.CHEFTY_DASH_VISIBLE_M.

## The dial's center in Chefty's space (straight ahead of the driver, over the
## top of the steering wheel), and how far it leans back toward the driver's eye.
const FACE_AT := Vector3(-0.45, 1.665, -2.68)
const FACE_TILT: float = -0.33
## The dial (m): its radius, the chrome bezel round it, and the pod behind it.
const DIAL_RADIUS: float = 0.085
const BEZEL: float = 0.007
## Where the needle points at 0 and at the top of the dial, from straight up
## (radians, clockwise positive); the dial's numbers every 10 MPH, ticks every 5.
const SWEEP_FROM: float = -2.0944
const SWEEP_TO: float = 2.0944
const NUMBER_STEP: int = 10
const TICK_STEP: int = 5
## The odometer's window (its center under the hub, m) and its drums.
const ODO_CENTER := Vector2(0.0, -0.043)
const ODO_DIGIT := Vector2(0.0112, 0.0152)
const ODO_PLACES: int = 6
## The check-engine lamp, right of the dial (its center, m).
const LAMP_AT := Vector2(0.128, -0.018)
const LAMP_RADIUS: float = 0.024

const DIAL_CREAM := Color(0.96, 0.93, 0.83)
const INK := Color(0.1, 0.09, 0.09)
const NEEDLE_RED := Color(0.93, 0.27, 0.1)
const POD := Color(0.13, 0.12, 0.12)
const CHROME := Color(0.86, 0.86, 0.84)
const DRUM_BLACK := Color(0.07, 0.07, 0.08)
const DRUM_WHITE := Color(0.95, 0.94, 0.9)
const LAMP_OFF := Color(0.13, 0.085, 0.035)
const LAMP_ON := Color(1.0, 0.64, 0.12)

static var _cache: Dictionary = {}

## The reading chefty_drive.gd last gave: ground speed (m/s), odometer (miles),
## dents, and whether the engine's on (someone, or a hired hand, at the wheel).
var _speed: float = 0.0
var _miles: float = 0.0
var _dents: int = 0
var _powered: bool = false
## The needle: where it points (share of the dial, 0 at the stop pin) and how fast it moves.
var _needle_at: float = 0.0
var _needle_vel: float = 0.0
## Seconds left of the bulb check, and the clock the blink runs on.
var _bulb_check: float = 0.0
var _blink_clock: float = 0.0
var _lamp_lit: bool = false
## The odometer shown (miles) and the digit each drum shows now.
var _shown_miles: float = -1.0
var _drum_digits: PackedInt32Array = PackedInt32Array()

var _needle: Node3D
var _lamp_material: StandardMaterial3D
## Per drum: [the digit rolling out (up), the digit rolling in (from below)].
var _drums: Array = []


func _init() -> void:
	name = "Dash"
	position = FACE_AT
	rotation = Vector3(FACE_TILT, 0.0, 0.0)
	_build()


## The truck's reading for this tick (chefty_drive.gd _update_dash).
func set_reading(ground_speed: float, miles: float, dents: int, powered: bool) -> void:
	_speed = maxf(ground_speed, 0.0)
	if powered and not _powered:
		_bulb_check = Constants.CHEFTY_DASH_BULB_CHECK_SECONDS
	_powered = powered
	_dents = dents
	_miles = maxf(miles, 0.0)


## What the dash shows right now, for tests and the playtest recorder: the
## needle (MPH), the odometer (miles), and whether the check-engine lamp is lit.
func reading() -> Dictionary:
	return {
		"mph": _needle_at * Constants.CHEFTY_DASH_MAX_MPH,
		"odometer": _shown_miles,
		"check_engine": _lamp_lit,
	}


## The needle's angle (radians from straight up, clockwise) for a share of the dial.
static func needle_angle(share: float) -> float:
	return lerpf(SWEEP_FROM, SWEEP_TO, share)


func _process(delta: float) -> void:
	_step(delta)


func _step(delta: float) -> void:
	if delta <= 0.0:
		return
	# The needle: a damped spring toward the speed, resting on its stop pin at 0
	# and never past the one at the top.
	var want := clampf(_speed * Constants.CHEFTY_DASH_MPH_PER_MPS / Constants.CHEFTY_DASH_MAX_MPH, 0.0, Constants.CHEFTY_DASH_NEEDLE_PEG)
	var force := (want - _needle_at) * Constants.CHEFTY_DASH_NEEDLE_STIFFNESS - _needle_vel * Constants.CHEFTY_DASH_NEEDLE_DAMPING
	_needle_vel += force * delta
	_needle_at += _needle_vel * delta
	if _needle_at < 0.0:
		_needle_at = 0.0
		_needle_vel = maxf(_needle_vel, 0.0)
	elif _needle_at > Constants.CHEFTY_DASH_NEEDLE_PEG:
		_needle_at = Constants.CHEFTY_DASH_NEEDLE_PEG
		_needle_vel = minf(_needle_vel, 0.0)
	if _needle != null:
		_needle.rotation = Vector3(0.0, 0.0, -needle_angle(_needle_at))
	# The lamp: the bulb check, then the dents (blinking at the most).
	_bulb_check = maxf(_bulb_check - delta, 0.0)
	_blink_clock = fmod(_blink_clock + delta, 1000.0)
	var lit := false
	if _powered:
		if _bulb_check > 0.0:
			lit = true
		elif _dents >= Constants.CHEFTY_MAX_DENTS:
			lit = fmod(_blink_clock * Constants.CHEFTY_DASH_CEL_BLINK_HZ, 1.0) < 0.5
		else:
			lit = _dents > 0
	if lit != _lamp_lit:
		_lamp_lit = lit
		if _lamp_material != null:
			_lamp_material.albedo_color = LAMP_ON if lit else LAMP_OFF
	# (Not is_equal_approx: at 186,000 miles its tolerance is over a mile.)
	if absf(_miles - _shown_miles) > 0.00001:
		_roll(_miles)


## Turns the drums to show these miles: the tenths drum all the time, each one
## above it only while every drum below it is rolling over from 9.
func _roll(miles: float) -> void:
	_shown_miles = miles
	var tenths := fposmod(miles * 10.0, pow(10.0, float(ODO_PLACES)))
	var whole := int(floor(tenths))
	var turning := tenths - float(whole)
	for place: int in ODO_PLACES:
		# Drum 0 is the tenths (rightmost); drum k counts 10^k tenths.
		var step := int(pow(10.0, float(place)))
		var digit := floori(float(whole) / float(step)) % 10
		var roll := turning if place == 0 or whole % step == step - 1 else 0.0
		_set_drum(place, digit, roll)


func _set_drum(place: int, digit: int, roll: float) -> void:
	if place >= _drums.size():
		return
	var pair: Array = _drums[place]
	var out_label := pair[0] as MeshInstance3D
	var in_label := pair[1] as MeshInstance3D
	if _drum_digits[place] != digit:
		_drum_digits[place] = digit
		out_label.mesh = _text_mesh(str(digit), ODO_DIGIT.y * 0.82)
		in_label.mesh = _text_mesh(str((digit + 1) % 10), ODO_DIGIT.y * 0.82)
	var center := _drum_center(place)
	out_label.position = Vector3(center.x, center.y + roll * ODO_DIGIT.y * 1.25, -0.004)
	in_label.position = Vector3(center.x, center.y - (1.0 - roll) * ODO_DIGIT.y * 1.25, -0.004)


## A drum's window center (dash space), drum 0 the rightmost (tenths).
static func _drum_center(place: int) -> Vector2:
	var left := ODO_CENTER.x - ODO_DIGIT.x * float(ODO_PLACES) * 0.5
	var column := ODO_PLACES - 1 - place
	return Vector2(left + ODO_DIGIT.x * (float(column) + 0.5), ODO_CENTER.y)


# ---------------------------------------------------------------- building

func _build() -> void:
	if not _cache.has("pod"):
		_cache["pod"] = _pod_mesh()
		_cache["face"] = _face_mesh()
		_cache["needle"] = _needle_mesh()
		_cache["drums"] = _drum_mesh()
		_cache["lamp"] = _lamp_mesh()
	# The pod and the bezel take the light like the rest of the truck.
	var pod := preload("res://props/stylized.gd").instance(_cache["pod"], {"roughness": 0.45, "specular": 0.4})
	pod.name = "Pod"
	_quiet(pod)
	add_child(pod)
	# The dial, its numbers and the needle are printed: they read the same in the
	# cab's shade as in the sun.
	var face := _flat(_cache["face"], "Face")
	add_child(face)
	add_child(_flat(_cache["drums"], "Drums"))
	_needle = Node3D.new()
	_needle.name = "Needle"
	_needle.position = Vector3(0.0, 0.0, 0.004)
	add_child(_needle)
	_needle.add_child(_flat(_cache["needle"], "NeedleMesh"))
	_needle.rotation = Vector3(0.0, 0.0, -needle_angle(0.0))
	for mph: int in range(0, int(Constants.CHEFTY_DASH_MAX_MPH) + 1, NUMBER_STEP):
		var share := float(mph) / Constants.CHEFTY_DASH_MAX_MPH
		var angle := needle_angle(share)
		var at := Vector2(sin(angle), cos(angle)) * DIAL_RADIUS * 0.6
		add_child(_text(str(mph), Vector3(at.x, at.y, 0.001), 0.0175, INK, "Mph%d" % mph))
	add_child(_text("MPH", Vector3(0.0, 0.026, 0.001), 0.0105, INK, "MphWord"))
	_drum_digits.resize(ODO_PLACES)
	_drum_digits.fill(-1)
	for place: int in ODO_PLACES:
		var ink := INK if place == 0 else DRUM_WHITE
		_drums.append([
			_text("0", Vector3.ZERO, ODO_DIGIT.y * 0.82, ink, "Drum%dOut" % place),
			_text("1", Vector3.ZERO, ODO_DIGIT.y * 0.82, ink, "Drum%dIn" % place),
		])
		for digit: MeshInstance3D in _drums[place]:
			add_child(digit)
	var lamp_face := MeshInstance3D.new()
	lamp_face.name = "CheckEngine"
	lamp_face.mesh = _cache["lamp"]
	_lamp_material = StandardMaterial3D.new()
	_lamp_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# The lens's gray and the engine's white, tinted by the lamp's state.
	_lamp_material.vertex_color_use_as_albedo = true
	_lamp_material.vertex_color_is_srgb = true
	_lamp_material.albedo_color = LAMP_OFF
	lamp_face.material_override = _lamp_material
	lamp_face.set_meta("keep_material", true)
	lamp_face.position = Vector3(LAMP_AT.x, LAMP_AT.y, 0.0015)
	_quiet(lamp_face)
	add_child(lamp_face)
	_roll(0.0)


## Out of shadows, and out of sight past the dash's range.
static func _quiet(node: GeometryInstance3D) -> void:
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = Constants.CHEFTY_DASH_VISIBLE_M
	node.visibility_range_end_margin = 1.0
	node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


## A printed part: its vertex colors as they are, no lighting.
static func _flat(mesh: Mesh, node_name: String) -> MeshInstance3D:
	var view := MeshInstance3D.new()
	view.name = node_name
	view.mesh = mesh
	if not _cache.has("print"):
		var printed := StandardMaterial3D.new()
		printed.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		printed.vertex_color_use_as_albedo = true
		printed.vertex_color_is_srgb = true
		_cache["print"] = printed
	view.material_override = _cache["print"]
	# levels/shared_look.gd would swap it for a lit one and lose the print.
	view.set_meta("keep_material", true)
	_quiet(view)
	return view


## A printed word or digit on the dial, height tall (m): a flat TextMesh, made
## once per text and size. (Not Label3D: a moving truck full of them redrew their
## text every frame, and the drive test's client fell seconds behind.)
static func _text(text: String, at: Vector3, height: float, color: Color, node_name: String) -> MeshInstance3D:
	var view := MeshInstance3D.new()
	view.name = node_name
	view.mesh = _text_mesh(text, height)
	var key := "ink|" + color.to_html()
	if not _cache.has(key):
		var ink := StandardMaterial3D.new()
		ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ink.albedo_color = color
		_cache[key] = ink
	view.material_override = _cache[key]
	view.set_meta("keep_material", true)
	view.position = at
	_quiet(view)
	return view


static func _text_mesh(text: String, height: float) -> Mesh:
	var key := "text|%s|%.4f" % [text, height]
	if not _cache.has(key):
		var mesh := TextMesh.new()
		mesh.text = text
		# Coarse curves: it's a few millimeters on a dial (64 px and fine curves
		# cost ten times as much to build, for nothing anyone sees).
		mesh.font_size = 32
		mesh.pixel_size = height / 32.0
		mesh.depth = 0.0
		mesh.curve_step = 1.0
		mesh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mesh.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_cache[key] = mesh
	return _cache[key]

## The pod the dial sits in (behind the face, far enough back that the drums fit
## in front of it), its chrome bezel, and a little visor over the top.
static func _pod_mesh() -> ArrayMesh:
	var kit := preload("res://props/mesh_kit.gd").new()
	var lamp_reach := LAMP_AT.x + LAMP_RADIUS + 0.02
	var left := -DIAL_RADIUS - 0.022
	var mid := (left + lamp_reach) * 0.5
	var half_x := (lamp_reach - left) * 0.5
	kit.rbox(Vector3(mid, 0.0, -0.05), Vector3(half_x, DIAL_RADIUS + 0.018, 0.034), POD, 6.0)
	kit.rbox(Vector3(mid, DIAL_RADIUS + 0.024, -0.012), Vector3(half_x + 0.006, 0.008, 0.05), POD, 5.0)
	# The bezel, a chrome ring round the dial.
	var ring := PackedVector3Array()
	var radii := PackedFloat32Array()
	for index: int in 33:
		var angle := TAU * float(index) / 32.0
		ring.append(Vector3(cos(angle), sin(angle), 0.0) * (DIAL_RADIUS + BEZEL * 0.5))
		radii.append(BEZEL)
	kit.tube(ring, radii, CHROME, 8, {"jitter": 0.0, "cap": false, "wobble": 0.0})
	# The lamp's chrome rim.
	var rim := PackedVector3Array()
	var rim_radii := PackedFloat32Array()
	for index: int in 17:
		var angle := TAU * float(index) / 16.0
		rim.append(Vector3(LAMP_AT.x + cos(angle) * (LAMP_RADIUS + 0.003), LAMP_AT.y + sin(angle) * (LAMP_RADIUS + 0.003), 0.0))
		rim_radii.append(0.004)
	kit.tube(rim, rim_radii, CHROME, 6, {"jitter": 0.0, "cap": false, "wobble": 0.0})
	return kit.commit()


## The dial: a cream disc with the odometer's window cut out of it, the ticks,
## and a dark ring at the window's edge.
static func _face_mesh() -> ArrayMesh:
	var kit := preload("res://props/mesh_kit.gd").new()
	var circle := PackedVector2Array()
	for index: int in 48:
		var angle := TAU * float(index) / 48.0
		circle.append(Vector2(cos(angle), sin(angle)) * (DIAL_RADIUS + 0.001))
	var window := _window_rect()
	var far := DIAL_RADIUS * 2.0
	# The disc less the window: above it, below it, and either side of it.
	var bands: Array[Rect2] = [
		Rect2(-far, window.end.y, far * 2.0, far),
		Rect2(-far, -far, far * 2.0, window.position.y + far),
		Rect2(-far, window.position.y, window.position.x + far, window.size.y),
		Rect2(window.end.x, window.position.y, far, window.size.y),
	]
	for band: Rect2 in bands:
		var rect := PackedVector2Array([band.position, Vector2(band.end.x, band.position.y), band.end, Vector2(band.position.x, band.end.y)])
		for piece: PackedVector2Array in Geometry2D.intersect_polygons(circle, rect):
			_fan(kit, piece, 0.0, DIAL_CREAM)
	# The window's dark surround.
	var edge := 0.0016
	for strip: Rect2 in [
		Rect2(window.position.x - edge, window.end.y, window.size.x + edge * 2.0, edge),
		Rect2(window.position.x - edge, window.position.y - edge, window.size.x + edge * 2.0, edge),
		Rect2(window.position.x - edge, window.position.y, edge, window.size.y),
		Rect2(window.end.x, window.position.y, edge, window.size.y),
	]:
		_quad(kit, strip, 0.0004, INK)
	# The ticks: long at the numbers, short between.
	for mph: int in range(0, int(Constants.CHEFTY_DASH_MAX_MPH) + 1, TICK_STEP):
		var angle := needle_angle(float(mph) / Constants.CHEFTY_DASH_MAX_MPH)
		var major := mph % NUMBER_STEP == 0
		var length := 0.0135 if major else 0.008
		var width := 0.0034 if major else 0.002
		var out := Vector2(sin(angle), cos(angle))
		var across := Vector2(out.y, -out.x) * width * 0.5
		var a := out * (DIAL_RADIUS - 0.004)
		var b := out * (DIAL_RADIUS - 0.004 - length)
		_poly(kit, PackedVector2Array([a - across, a + across, b + across, b - across]), 0.0004, INK)
	return kit.commit()


## The needle (pointing up its +Y), red to its tip, with a black hub cap over it.
static func _needle_mesh() -> ArrayMesh:
	var kit := preload("res://props/mesh_kit.gd").new()
	var tip := DIAL_RADIUS - 0.006
	_poly(kit, PackedVector2Array([Vector2(-0.0026, -0.014), Vector2(0.0026, -0.014), Vector2(0.0009, tip), Vector2(-0.0009, tip)]), 0.0, NEEDLE_RED)
	var hub := PackedVector2Array()
	for index: int in 16:
		var angle := TAU * float(index) / 16.0
		hub.append(Vector2(cos(angle), sin(angle)) * 0.0085)
	_fan(kit, hub, 0.0008, INK)
	return kit.commit()


## What shows through the window behind the digits: black drums for the miles,
## a white one for the tenths, with thin dark gaps between them. Tall enough that
## nothing behind them shows at any angle the cab allows.
static func _drum_mesh() -> ArrayMesh:
	var kit := preload("res://props/mesh_kit.gd").new()
	for place: int in ODO_PLACES:
		var center := _drum_center(place)
		var rect := Rect2(center.x - ODO_DIGIT.x * 0.45, center.y - ODO_DIGIT.y * 1.6, ODO_DIGIT.x * 0.9, ODO_DIGIT.y * 3.2)
		_quad(kit, rect, -0.0055, DRUM_WHITE if place == 0 else DRUM_BLACK)
	var whole := _window_rect().grow(0.004)
	_quad(kit, Rect2(whole.position.x, whole.position.y - 0.02, whole.size.x, whole.size.y + 0.04), -0.006, DRUM_BLACK.darkened(0.5))
	return kit.commit()


## The check-engine lamp's lens: an engine's outline (block, head, intake,
## exhaust tab, fan stub) on a round lens; the material lights it.
static func _lamp_mesh() -> ArrayMesh:
	var kit := preload("res://props/mesh_kit.gd").new()
	var lens := PackedVector2Array()
	for index: int in 20:
		var angle := TAU * float(index) / 20.0
		lens.append(Vector2(cos(angle), sin(angle)) * LAMP_RADIUS)
	_fan(kit, lens, -0.0004, Color(0.16, 0.16, 0.16))
	var w := Color.WHITE
	# The block, its valve cover and the cap on top.
	_quad(kit, Rect2(-0.011, -0.008, 0.02, 0.012), 0.0, w)
	_quad(kit, Rect2(-0.008, 0.004, 0.014, 0.003), 0.0, w)
	_quad(kit, Rect2(-0.003, 0.007, 0.004, 0.003), 0.0, w)
	_quad(kit, Rect2(-0.007, 0.0095, 0.012, 0.0025), 0.0, w)
	# The fan on its stub (left), the exhaust stepping out (right).
	_quad(kit, Rect2(-0.014, -0.004, 0.0035, 0.004), 0.0, w)
	_quad(kit, Rect2(-0.0175, -0.008, 0.0035, 0.012), 0.0, w)
	_quad(kit, Rect2(0.0085, -0.003, 0.005, 0.004), 0.0, w)
	_quad(kit, Rect2(0.013, -0.007, 0.0035, 0.011), 0.0, w)
	return kit.commit()


static func _window_rect() -> Rect2:
	var size := Vector2(ODO_DIGIT.x * float(ODO_PLACES), ODO_DIGIT.y * 1.08)
	return Rect2(ODO_CENTER - size * 0.5, size)


static func _quad(kit: RefCounted, rect: Rect2, z: float, color: Color) -> void:
	_poly(kit, PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]), z, color)


## A convex polygon in the dial's plane at depth z, facing +Z.
static func _poly(kit: RefCounted, points: PackedVector2Array, z: float, color: Color) -> void:
	_fan(kit, points, z, color)


static func _fan(kit: RefCounted, points: PackedVector2Array, z: float, color: Color) -> void:
	if points.size() < 3:
		return
	var normal := Vector3.BACK
	var a := Vector3(points[0].x, points[0].y, z)
	for index: int in range(1, points.size() - 1):
		var b := Vector3(points[index].x, points[index].y, z)
		var c := Vector3(points[index + 1].x, points[index + 1].y, z)
		# Clockwise as seen from +Z (Godot's front face).
		if (b - a).cross(c - a).z > 0.0:
			kit.call("triangle", a, c, b, normal, color)
		else:
			kit.call("triangle", a, b, c, normal, color)
