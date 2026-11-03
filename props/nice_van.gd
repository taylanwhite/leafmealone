extends RefCounted

## Authority: local, cosmetic. The NICE BOYS' van, the "Courtesy Shuttle" (docs/GAME.md,
## "2026-11-02, the Courtesy Shuttle"; docs/ART.md, "The NICE BOYS"): a cream
## shuttle van with a Courtesy Lavender lower half, one amber dome on the roof (a
## dome, never a light bar), a big gray loudspeaker horn, whitewall tires, and Daisy
## Seals (props/nice_seal.gd) on the cab doors, the grille and the back. The left
## side reads THE NICE BOYS / "Courtesy Patrol · We Noticed.", the parked-open
## sliding door THE NICE BOYS, the back "HOW'S MY ENFORCING? FILL OUT FORM 9-B"
## (all from ui/strings.gd).
##
## Its right side behind the cab is open, the sliding door slid back, so the riders
## can be counted at a glance (docs/ART.md); the interior is furnished for that view:
## benches, a water cooler, grab loops, an Employee of the Month frame, and a cab
## with seats, a dash, a steering wheel, cupholders and a daisy air freshener.
## Glass is see-through. It faces -Z, its wheels touch y 0, and riders stand on its
## floor at y 1.0 (net/components/ride.gd seats).
##
##   NiceVan.build(parent, paint)   # a "VanLook" under parent; Vehicles.build_van calls it
##
## What build() makes, by node name:
##   VanLook/Shell     the body: mesh, glass, lights, dome; sways on the springs
##   VanLook/Livery    the lettering (Label3D), swayed with the Shell
##   VanLook/Wheels    WheelFL, WheelFR, WheelRL, WheelRR, which roll
##   VanLook/Solid     the five collision boxes riders and players bump into
##   VanLook/Motion    rolls the wheels, sways the body, flares the brake lights and
##                     pulses the dome, from how the VanLook itself moves. Whoever
##                     moves the van (ride.gd, net/run_events/van_arrival.gd) just
##                     moves it on physics ticks.
##
## The roads: arrival_curve() is how it pulls up to a curb, departure_curve() how it
## leaves with its riders. One ends exactly where and how the other starts, so the
## van that pulls up and the ride that leaves are the same van to the eye.

const _NiceSeal = preload("res://props/nice_seal.gd")
const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const _LowPoly = preload("res://props/low_poly.gd")
const _Strings = preload("res://ui/strings.gd")

## The cream body and the Courtesy Lavender lower half.
const PAINT := Color(0.94, 0.91, 0.82)
const BAND := _NiceSeal.LAVENDER
## A deeper lavender for the pinstripe, fender lips and grille.
const BAND_DEEP := Color(0.47, 0.39, 0.72)
const BEACON_AMBER := Color(1.0, 0.62, 0.12)
const LETTERING := Color(0.33, 0.24, 0.6)
const TIRE := Color(0.11, 0.11, 0.12)
const WHITEWALL := Color(0.95, 0.95, 0.92)
const CHROME := Color(0.86, 0.86, 0.84)
const RUBBER := Color(0.2, 0.2, 0.22)
const TRIM := Color(0.55, 0.55, 0.58)
const VINYL := Color(0.6, 0.52, 0.88)
const GLASS_TINT := Color(0.52, 0.66, 0.78, 0.32)
const MATERIAL := {"roughness": 0.55, "specular": 0.25}

## Wheels: centers (left side; the right mirrors), radius and width.
const WHEEL_X: float = 1.02
const WHEEL_Z: float = 2.1
const WHEEL_RADIUS: float = 0.46
const WHEEL_WIDTH: float = 0.36
## The cab's windshield line in the side profile (z, y): bottom at the hood, top at
## the roof. The cab doors follow it.
const SLANT_BOTTOM := Vector2(-2.47, 1.76)
const SLANT_TOP := Vector2(-2.03, 2.9)

## Which way it drives along the curb: heading -X in the street's far lane, so it
## arrives from +X and leaves toward the lot's van corridor (Constants.ART_VAN_ANGLE).
const STREET_DIR := Vector3(-1.0, 0.0, 0.0)

static var _cache: Dictionary = {}


## The van under parent, as "VanLook" (an old one is replaced). paint is the body
## color (Vehicles.VAN_PAINT, cream); the band and trim are always the NICE BOYS'.
static func build(parent: Node3D, paint: Color = PAINT) -> Node3D:
	var old := parent.get_node_or_null("VanLook")
	if old != null:
		old.free()
	var look := Node3D.new()
	look.name = "VanLook"
	parent.add_child(look)
	var key := paint.to_html()
	if not _cache.has(key):
		_cache[key] = {"body": _body_mesh(paint), "glass": _glass_mesh(), "dome": _dome_mesh(), "wheel": _wheel_mesh()}
	var meshes: Dictionary = _cache[key]
	var shell := Node3D.new()
	shell.name = "Shell"
	look.add_child(shell)
	var body := _Stylized.instance(meshes["body"], MATERIAL)
	body.name = "Body"
	shell.add_child(body)
	var glass := MeshInstance3D.new()
	glass.name = "Glass"
	glass.mesh = meshes["glass"]
	glass.material_override = _glass_material()
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glass.set_meta("keep_material", true)
	shell.add_child(glass)
	var dome := MeshInstance3D.new()
	dome.name = "Dome"
	dome.mesh = meshes["dome"]
	dome.material_override = _glow_material(BEACON_AMBER, 2.0)
	dome.set_meta("keep_material", true)
	shell.add_child(dome)
	var dome_light := OmniLight3D.new()
	dome_light.name = "DomeLight"
	dome_light.light_color = BEACON_AMBER
	dome_light.omni_range = 7.0
	dome_light.light_energy = 0.8
	# A wash of amber on the street and the van, but no glare on its own windshield.
	dome_light.light_specular = 0.0
	dome_light.position = Vector3(0.0, 3.45, 0.3)
	shell.add_child(dome_light)
	# A warm cabin light, so the riders inside can be counted even in the van's shade.
	var cabin := OmniLight3D.new()
	cabin.name = "CabinLight"
	cabin.light_color = Color(1.0, 0.9, 0.72)
	cabin.omni_range = 3.4
	cabin.light_energy = 0.9
	cabin.light_specular = 0.0
	cabin.position = Vector3(0.0, 2.55, 0.0)
	shell.add_child(cabin)
	var lights := _lights(shell)
	_livery(look)
	var wheels := Node3D.new()
	wheels.name = "Wheels"
	look.add_child(wheels)
	for front: bool in [true, false]:
		for side: float in [-1.0, 1.0]:
			var wheel := MeshInstance3D.new()
			wheel.name = "Wheel%s%s" % ["F" if front else "R", "L" if side < 0.0 else "R"]
			wheel.mesh = meshes["wheel"]
			wheel.material_override = _Stylized.material(MATERIAL)
			wheel.set_meta("keep_material", true)
			wheel.position = Vector3(side * WHEEL_X, WHEEL_RADIUS, -WHEEL_Z if front else WHEEL_Z)
			# The mesh has its hub facing +X; the left wheels turn it to face out.
			if side < 0.0:
				wheel.rotation.y = PI
			wheels.add_child(wheel)
	# Solid: the same five boxes the van always had (riders and countability rely
	# on them; --cast-test step 11 counts them).
	_solid(look, [
		[Vector3(0.0, 0.65, 0.0), Vector3(2.3, 0.8, 6.4)],
		[Vector3(0.0, 1.9, -2.55), Vector3(2.3, 1.8, 1.4)],
		[Vector3(-1.12, 1.95, 0.5), Vector3(0.16, 2.0, 5.2)],
		[Vector3(0.0, 1.95, 3.0), Vector3(2.3, 2.0, 0.16)],
		[Vector3(0.0, 3.0, 0.5), Vector3(2.4, 0.2, 5.2)],
	])
	var motion := Motion.new()
	motion.name = "Motion"
	motion.setup(look, lights)
	look.add_child(motion)
	return look


## The curve a van leaving the curb at from drives to to: straight along the street
## first (Constants.VAN_LEAD_OUT), then bending away, lifted at the middle as the
## ride always was. Its start is where arrival_curve(from) ends, facing the same way.
static func departure_curve(from: Vector3, to: Vector3) -> Curve3D:
	var curve := Curve3D.new()
	var lead := from + STREET_DIR * Constants.VAN_LEAD_OUT
	curve.add_point(from)
	curve.add_point(lead, Vector3.ZERO, STREET_DIR * Constants.VAN_LEAD_OUT * 1.5)
	curve.add_point((from + to) * 0.5 + Vector3(0.0, 3.0, 0.0))
	curve.add_point(to)
	return curve


## The curve a van pulling up to park drives: down the street's far lane from
## Constants.VAN_ARRIVE_DISTANCE away, straight to park.
static func arrival_curve(park: Vector3) -> Curve3D:
	var curve := Curve3D.new()
	curve.add_point(park - STREET_DIR * Constants.VAN_ARRIVE_DISTANCE)
	curve.add_point(park)
	return curve


## The van's pose this far along a curve (0..1), the way a ride places its body.
static func pose(curve: Curve3D, along: float) -> Transform3D:
	return curve.sample_baked_with_rotation(clampf(along, 0.0, 1.0) * curve.get_baked_length(), true, true)


## How far along its departure curve (0..1) a leaving van is when share of a ride
## of duration seconds along a curve length meters long has passed. For the first
## Constants.VAN_PULL_SECONDS it pulls out from the curb like a van
## (Constants.VAN_PULL_ACCEL), so the people left on the lot watch it go; then it
## makes up the distance the ride's fixed time asks for, and slows to a stop at the
## end. Never backs up, never jumps.
static func depart_progress(share: float, duration: float, length: float) -> float:
	var u := clampf(share, 0.0, 1.0)
	if length <= 0.0 or duration <= 0.0:
		return u
	var t := u * duration
	var pull := minf(Constants.VAN_PULL_SECONDS, duration * 0.5)
	var accel := minf(Constants.VAN_PULL_ACCEL, length / maxf(pull * pull, 0.01))
	if t <= pull:
		return clampf(0.5 * accel * t * t / length, 0.0, 1.0)
	# The rest: a cubic from where the pull-out left it, at its speed, to the end at rest.
	var d0 := 0.5 * accel * pull * pull
	var span := duration - pull
	# On a short road, a gentler hand-off, so the cubic can't overshoot and come back.
	var v0 := minf(accel * pull, 3.0 * (length - d0) / span)
	var s := (t - pull) / span
	var s2 := s * s
	var s3 := s2 * s
	var d := (2.0 * s3 - 3.0 * s2 + 1.0) * d0 + (s3 - 2.0 * s2 + s) * span * v0 + (-2.0 * s3 + 3.0 * s2) * length
	return clampf(d / length, 0.0, 1.0)


## How far along its arrival curve a van pulling up is (0..1), t seconds after it
## started (Constants.VAN_ARRIVE_SECONDS in all): it cruises, then brakes evenly to
## a stop at the curb. 1 once parked.
static func arrive_progress(t: float) -> float:
	var total := Constants.VAN_ARRIVE_SECONDS
	if t <= 0.0:
		return 0.0
	if t >= total:
		return 1.0
	var cruise := total * Constants.VAN_ARRIVE_CRUISE_SHARE
	# Distance in units of the whole curve: cruising at v, then braking from v to 0.
	var v := 1.0 / (cruise + (total - cruise) * 0.5)
	if t <= cruise:
		return v * t
	var left := total - t
	return 1.0 - v * left * left / (2.0 * (total - cruise))


## When the braking starts, seconds after the van starts pulling up.
static func brake_time() -> float:
	return Constants.VAN_ARRIVE_SECONDS * Constants.VAN_ARRIVE_CRUISE_SHARE


# ---------------------------------------------------------------- the body


static func _body_mesh(paint: Color) -> ArrayMesh:
	var kit := _MeshKit.new()
	var fine := {"detail": 2}
	# Underneath: the chassis between the wheels, and a dark belly.
	kit.rbox(Vector3(0.0, 0.7, -0.1), Vector3(0.85, 0.28, 3.2), BAND, 6.0)
	kit.rbox(Vector3(0.0, 0.42, 0.0), Vector3(0.8, 0.12, 2.9), RUBBER, 6.0, fine)
	for side: float in [-1.0, 1.0]:
		# Sills between the wheels, and the corners ahead of and behind them.
		kit.rbox(Vector3(side * 1.02, 0.72, 0.0), Vector3(0.12, 0.28, 1.45), BAND, 6.0, fine)
		kit.rbox(Vector3(side * 1.0, 0.8, -2.95), Vector3(0.14, 0.2, 0.32), BAND, 5.0, fine)
		kit.rbox(Vector3(side * 1.0, 0.8, 2.85), Vector3(0.14, 0.2, 0.25), BAND, 5.0, fine)
		# Fender lips over the wheels.
		for z: float in [-WHEEL_Z, WHEEL_Z]:
			kit.rbox(Vector3(side * 1.06, 1.0, z), Vector3(0.15, 0.07, 0.6), BAND_DEEP, 5.0, fine)
	# The floor riders stand on (top at y 1.01), with rubber ribs.
	kit.box(Vector3(0.0, 0.99, 0.55), Vector3(2.24, 0.04, 5.1), RUBBER)
	for index: int in 5:
		kit.box(Vector3(-0.8 + float(index) * 0.4, 1.013, 0.6), Vector3(0.05, 0.008, 4.8), RUBBER.lightened(0.12))
	_nose(kit, paint)
	_cab_sides(kit, paint)
	_left_wall(kit, paint)
	_back_wall(kit, paint)
	_right_side(kit, paint)
	_roof(kit, paint)
	_cab_inside(kit)
	_cabin_inside(kit)
	return kit.commit()


## The hood, grille, bumper and the hood's seal at the grille top.
static func _nose(kit: _MeshKit, paint: Color) -> void:
	kit.rbox(Vector3(0.0, 1.24, -2.88), Vector3(1.1, 0.27, 0.46), BAND, 6.0)
	kit.rbox(Vector3(0.0, 1.63, -2.87), Vector3(1.08, 0.13, 0.45), paint, 6.0)
	kit.rbox(Vector3(0.0, 1.1, -3.345), Vector3(0.52, 0.12, 0.02), BAND_DEEP.darkened(0.35), 6.0, {"detail": 2, "shade": false})
	for index: int in 3:
		kit.rbox(Vector3(0.0, 1.02 + float(index) * 0.08, -3.37), Vector3(0.48, 0.008, 0.008), CHROME, 4.0, {"detail": 1})
	_NiceSeal.add(kit, Vector3(0.0, 1.42, -3.352), 0.17, Vector3.FORWARD, 1)
	kit.rbox(Vector3(0.0, 0.76, -3.44), Vector3(1.14, 0.11, 0.09), TRIM, 5.0, {"detail": 2})


## The cab doors, each side: a panel shaped to the windshield's slant with a window
## hole, a door handle, a mirror, and a Daisy Seal on the door.
static func _cab_sides(kit: _MeshKit, paint: Color) -> void:
	var y_window := 2.0
	var y_top := 2.7
	var outer_2 := _slant_z(y_window)
	var outer_top := _slant_z(y_top)
	for side: float in [-1.0, 1.0]:
		var x0 := side * 1.05
		var x1 := side * 1.12
		_prism(kit, [Vector2(-2.47, 0.98), Vector2(-1.85, 0.98), Vector2(-1.85, 1.52), Vector2(-2.47, 1.52)], x0, x1, BAND)
		_prism(kit, [Vector2(-2.47, 1.52), Vector2(-1.85, 1.52), Vector2(-1.85, y_window), Vector2(outer_2, y_window), Vector2(SLANT_BOTTOM.x, SLANT_BOTTOM.y)], x0, x1, paint)
		# The A-pillar along the windshield, the B-pillar, and the header over the window.
		_prism(kit, [Vector2(outer_2, y_window), Vector2(outer_2 + 0.08, y_window), Vector2(SLANT_TOP.x + 0.08, SLANT_TOP.y), Vector2(SLANT_TOP.x, SLANT_TOP.y)], x0, x1, paint)
		_prism(kit, [Vector2(-1.95, y_window), Vector2(-1.85, y_window), Vector2(-1.85, SLANT_TOP.y), Vector2(-1.95, SLANT_TOP.y)], x0, x1, paint)
		_prism(kit, [Vector2(outer_top, y_top), Vector2(-1.95, y_top), Vector2(-1.95, SLANT_TOP.y), Vector2(SLANT_TOP.x, SLANT_TOP.y)], x0, x1, paint)
		kit.box(Vector3(side * 1.13, 1.92, -2.02), Vector3(0.02, 0.035, 0.13), CHROME)
		# A mirror on a stalk.
		kit.tube(PackedVector3Array([Vector3(side * 1.11, 2.08, -2.36), Vector3(side * 1.28, 2.12, -2.4)]), PackedFloat32Array([0.018, 0.018]), RUBBER, 6, {"jitter": 0.0})
		kit.rbox(Vector3(side * 1.32, 2.14, -2.4), Vector3(0.04, 0.12, 0.08), RUBBER, 4.0, {"detail": 1})
		# The cab door's Daisy Seal.
		_NiceSeal.add(kit, Vector3(side * 1.124, 1.56, -2.17), 0.24, Vector3(side, 0.0, 0.0), 1)
		# A rounded post where each cab door meets the body.
		kit.rbox(Vector3(side * 1.1, 1.27, -1.88), Vector3(0.08, 0.25, 0.06), BAND, 4.0, {"detail": 1})
		kit.rbox(Vector3(side * 1.1, 2.21, -1.88), Vector3(0.08, 0.7, 0.06), paint, 4.0, {"detail": 1})


## The left wall behind the cab: lavender below, cream above, one long window up front
## (the lettering takes the rest), side marker lights, and the rounded back corner.
static func _left_wall(kit: _MeshKit, paint: Color) -> void:
	var x := -1.12
	kit.box(Vector3(x, 1.27, 0.61), Vector3(0.14, 0.5, 4.92), BAND)
	kit.box(Vector3(x, 1.845, 0.61), Vector3(0.14, 0.65, 4.92), paint)
	kit.box(Vector3(x, 2.42, -1.7), Vector3(0.14, 0.5, 0.3), paint)
	kit.box(Vector3(x, 2.42, 1.41), Vector3(0.14, 0.5, 3.32), paint)
	kit.box(Vector3(x, 2.795, 0.61), Vector3(0.14, 0.25, 4.92), paint)
	# A deep lavender pinstripe along the top of the band.
	kit.box(Vector3(x - 0.071, 1.535, 0.61), Vector3(0.006, 0.03, 4.9), BAND_DEEP)
	# Rubber around the window.
	for edge: Array in [[Vector3(x - 0.071, 2.17, -0.9), Vector3(0.006, 0.025, 1.32)], [Vector3(x - 0.071, 2.67, -0.9), Vector3(0.006, 0.025, 1.32)], [Vector3(x - 0.071, 2.42, -1.55), Vector3(0.006, 0.52, 0.025)], [Vector3(x - 0.071, 2.42, -0.25), Vector3(0.006, 0.52, 0.025)]]:
		kit.box(edge[0], edge[1], RUBBER)
	# The back corner, rounded.
	kit.rbox(Vector3(-1.12, 1.27, 3.0), Vector3(0.085, 0.25, 0.085), BAND, 4.0, {"detail": 1})
	kit.rbox(Vector3(-1.12, 2.21, 3.0), Vector3(0.085, 0.7, 0.085), paint, 4.0, {"detail": 1})


## The back: two doors with windows, the seal on the band, handles, the bumper.
static func _back_wall(kit: _MeshKit, paint: Color) -> void:
	var z := 3.0
	kit.box(Vector3(0.0, 1.27, z), Vector3(2.38, 0.5, 0.14), BAND)
	kit.box(Vector3(0.0, 1.86, z), Vector3(2.38, 0.68, 0.14), paint)
	for x: float in [-1.07, 0.0, 1.07]:
		kit.box(Vector3(x, 2.45, z), Vector3(0.24 if x != 0.0 else 0.4, 0.5, 0.14), paint)
	kit.box(Vector3(0.0, 2.81, z), Vector3(2.38, 0.22, 0.14), paint)
	kit.box(Vector3(0.0, 1.535, z + 0.071), Vector3(2.36, 0.03, 0.006), BAND_DEEP)
	# The seam between the doors (broken where the lettering runs across), and
	# their handles.
	kit.box(Vector3(0.0, 1.36, z + 0.072), Vector3(0.014, 0.68, 0.006), RUBBER)
	kit.box(Vector3(0.0, 2.52, z + 0.072), Vector3(0.014, 0.8, 0.006), RUBBER)
	for side: float in [-1.0, 1.0]:
		kit.box(Vector3(side * 0.13, 1.72, z + 0.08), Vector3(0.12, 0.035, 0.02), CHROME)
	_NiceSeal.add(kit, Vector3(0.0, 1.29, z + 0.072), 0.2, Vector3.BACK, 1)
	kit.rbox(Vector3(0.0, 0.76, 3.16), Vector3(1.16, 0.11, 0.09), TRIM, 5.0, {"detail": 2})


## The open right side: posts at both ends, the door track, the running board with
## its yellow "watch your step" edge, and the sliding door parked open at the back.
static func _right_side(kit: _MeshKit, paint: Color) -> void:
	kit.rbox(Vector3(1.12, 1.27, 3.0), Vector3(0.085, 0.25, 0.085), BAND, 4.0, {"detail": 1})
	kit.rbox(Vector3(1.12, 2.21, 3.0), Vector3(0.085, 0.7, 0.085), paint, 4.0, {"detail": 1})
	kit.box(Vector3(1.14, 2.86, 0.6), Vector3(0.05, 0.04, 4.9), RUBBER)
	kit.box(Vector3(1.15, 0.93, -0.08), Vector3(0.2, 0.05, 3.5), TRIM)
	kit.box(Vector3(1.252, 0.945, -0.08), Vector3(0.006, 0.022, 3.5), Color(0.98, 0.82, 0.2))
	# The sliding door, slid back over the rear quarter, a hand's width out.
	var x := 1.235
	var z0 := 1.72
	var z1 := 3.06
	var mid := (z0 + z1) * 0.5
	kit.box(Vector3(x, 1.27, mid), Vector3(0.06, 0.5, z1 - z0), BAND)
	kit.box(Vector3(x, 1.835, mid), Vector3(0.06, 0.63, z1 - z0), paint)
	kit.box(Vector3(x, 2.385, z0 + 0.065), Vector3(0.06, 0.47, 0.13), paint)
	kit.box(Vector3(x, 2.385, z1 - 0.105), Vector3(0.06, 0.47, 0.21), paint)
	kit.box(Vector3(x, 2.74, mid), Vector3(0.06, 0.24, z1 - z0), paint)
	kit.box(Vector3(x + 0.031, 1.535, mid), Vector3(0.006, 0.03, z1 - z0 - 0.02), BAND_DEEP)
	kit.box(Vector3(x + 0.036, 1.86, z0 + 0.1), Vector3(0.02, 0.035, 0.12), CHROME)
	# The rollers it hangs from.
	kit.box(Vector3(1.19, 2.87, mid), Vector3(0.06, 0.03, z1 - z0), RUBBER)


## The roof, the amber dome's base, and the loudspeaker horn on the front edge.
static func _roof(kit: _MeshKit, paint: Color) -> void:
	kit.rbox(Vector3(0.0, 3.0, 0.55), Vector3(1.2, 0.09, 2.6), paint, 6.0)
	kit.rbox(Vector3(0.0, 3.1, 0.3), Vector3(0.3, 0.035, 0.3), RUBBER, 2.5, {"detail": 2})
	# The loudspeaker: a bracket, a flaring gray horn pointing ahead, a dark mouth.
	var at := Vector3(-0.45, 3.27, 0.0)
	kit.box(Vector3(at.x, 3.15, -1.62), Vector3(0.06, 0.12, 0.08), TRIM.darkened(0.2))
	kit.tube(PackedVector3Array([Vector3(at.x, at.y, -1.32), Vector3(at.x, at.y, -1.5), Vector3(at.x, at.y, -1.72), Vector3(at.x, at.y, -1.9), Vector3(at.x, at.y, -1.96)]),
		PackedFloat32Array([0.055, 0.06, 0.1, 0.18, 0.2]), Color(0.66, 0.67, 0.7), 12, {"jitter": 0.0, "cap": true, "cap_start": true})
	kit.tube(PackedVector3Array([Vector3(at.x, at.y, -1.955), Vector3(at.x, at.y, -1.965)]), PackedFloat32Array([0.16, 0.16]), RUBBER, 12, {"jitter": 0.0})
	# The ceiling inside, a little under the roof.
	kit.box(Vector3(0.0, 2.88, 0.6), Vector3(2.1, 0.02, 4.9), Color(0.86, 0.84, 0.88))


## Through the windshield and the open side: two seats, a dash, a steering wheel, a
## console with two cupholders, a mirror and a daisy air freshener.
static func _cab_inside(kit: _MeshKit) -> void:
	kit.box(Vector3(0.0, 1.86, -2.24), Vector3(2.08, 0.14, 0.24), Color(0.32, 0.29, 0.4))
	for x: float in [-0.5, 0.5]:
		kit.box(Vector3(x, 1.38, -1.98), Vector3(0.6, 0.14, 0.42), VINYL)
		kit.box(Vector3(x, 1.2, -1.98), Vector3(0.5, 0.26, 0.36), RUBBER)
		kit.box(Vector3(x, 1.86, -1.79), Vector3(0.6, 0.8, 0.1), VINYL, Basis(Vector3.RIGHT, 0.1))
		kit.box(Vector3(x, 2.36, -1.75), Vector3(0.36, 0.2, 0.09), VINYL.darkened(0.15))
	# The steering wheel, leaned back toward the driver, on its column.
	var hub := Vector3(-0.5, 2.0, -2.06)
	var up := Vector3(0.0, 0.866, 0.5)
	var ring := PackedVector3Array()
	var radii := PackedFloat32Array()
	for index: int in 17:
		var angle := TAU * float(index) / 16.0
		ring.append(hub + (Vector3.RIGHT * cos(angle) + up * sin(angle)) * 0.17)
		radii.append(0.018)
	kit.tube(ring, radii, RUBBER, 6, {"jitter": 0.0, "cap": false})
	kit.tube(PackedVector3Array([hub, hub + Vector3(0.0, -0.08, -0.16)]), PackedFloat32Array([0.025, 0.03]), RUBBER, 6, {"jitter": 0.0})
	# The console between the seats: two cupholders (they mention them; docs/GAME.md).
	kit.box(Vector3(0.0, 1.3, -2.02), Vector3(0.3, 0.6, 0.4), RUBBER.lightened(0.1))
	for z: float in [-2.1, -1.94]:
		kit.tube(PackedVector3Array([Vector3(0.0, 1.6, z), Vector3(0.0, 1.62, z)]), PackedFloat32Array([0.05, 0.05]), Color(0.12, 0.12, 0.13), 8, {"jitter": 0.0})
	# The mirror, and a daisy air freshener hanging from it, facing out the front.
	kit.box(Vector3(0.0, 2.76, -2.04), Vector3(0.3, 0.07, 0.03), RUBBER)
	kit.tube(PackedVector3Array([Vector3(0.0, 2.72, -2.05), Vector3(0.0, 2.6, -2.05)]), PackedFloat32Array([0.004, 0.004]), Color(0.95, 0.95, 0.95), 4, {"jitter": 0.0})
	_NiceSeal.add(kit, Vector3(0.0, 2.55, -2.05), 0.05, Vector3.FORWARD, 0, true)


## The back, seen through the open side: a bench along the left wall and one across
## the back, a water cooler, grab rails with loops, a ceiling light, and the Employee
## of the Month on the wall.
static func _cabin_inside(kit: _MeshKit) -> void:
	kit.box(Vector3(-0.82, 1.45, 1.4), Vector3(0.42, 0.12, 1.8), VINYL)
	kit.box(Vector3(-0.82, 1.22, 1.4), Vector3(0.36, 0.38, 1.7), RUBBER)
	kit.box(Vector3(-1.0, 1.86, 1.4), Vector3(0.08, 0.62, 1.8), VINYL.darkened(0.08))
	kit.box(Vector3(0.22, 1.45, 2.62), Vector3(1.66, 0.12, 0.42), VINYL)
	kit.box(Vector3(0.22, 1.22, 2.62), Vector3(1.6, 0.38, 0.36), RUBBER)
	kit.box(Vector3(0.22, 1.86, 2.88), Vector3(1.66, 0.62, 0.08), VINYL.darkened(0.08))
	# The water cooler: a white stand, a blue jug, a red and a blue tap.
	kit.box(Vector3(0.72, 1.46, 1.35), Vector3(0.34, 0.9, 0.34), Color(0.95, 0.95, 0.96))
	kit.rbox(Vector3(0.72, 2.13, 1.35), Vector3(0.15, 0.22, 0.15), Color(0.45, 0.7, 0.95), 3.0, {"detail": 2})
	kit.box(Vector3(0.62, 1.78, 1.35), Vector3(0.03, 0.04, 0.04), Color(0.85, 0.2, 0.2))
	kit.box(Vector3(0.62, 1.78, 1.25), Vector3(0.03, 0.04, 0.04), Color(0.2, 0.4, 0.9))
	# Grab rails along both sides of the ceiling, with lavender loops.
	for x: float in [-0.92, 0.92]:
		kit.tube(PackedVector3Array([Vector3(x, 2.79, -1.7), Vector3(x, 2.79, 2.7)]), PackedFloat32Array([0.018, 0.018]), CHROME, 6, {"jitter": 0.0})
		# Between the riders' rows (z -1.2 and -0.2), not in their faces.
		for z: float in [-0.7, 0.3, 1.3]:
			kit.tube(PackedVector3Array([Vector3(x, 2.79, z - 0.04), Vector3(x, 2.6, z - 0.07), Vector3(x, 2.53, z), Vector3(x, 2.6, z + 0.07), Vector3(x, 2.79, z + 0.04)]),
				PackedFloat32Array([0.014, 0.014, 0.014, 0.014, 0.014]), VINYL.darkened(0.2), 5, {"jitter": 0.0, "cap": false})
	# Employee of the Month: a white frame, a lavender card, a Daisy Seal.
	kit.box(Vector3(-1.04, 2.42, 0.9), Vector3(0.02, 0.44, 0.36), Color(0.97, 0.97, 0.95))
	kit.box(Vector3(-1.032, 2.42, 0.9), Vector3(0.01, 0.36, 0.28), BAND)
	_NiceSeal.add(kit, Vector3(-1.026, 2.45, 0.9), 0.1, Vector3.RIGHT)


## Every window as one see-through mesh: the windshield, both cab doors, the left
## side, the two back doors and the sliding door.
static func _glass_mesh() -> ArrayMesh:
	var kit := _MeshKit.new()
	var tilt := atan2(SLANT_TOP.x - SLANT_BOTTOM.x, SLANT_TOP.y - SLANT_BOTTOM.y)
	var center := (SLANT_BOTTOM + SLANT_TOP) * 0.5
	var length := SLANT_BOTTOM.distance_to(SLANT_TOP)
	kit.box(Vector3(0.0, center.y, center.x), Vector3(2.1, length, 0.03), Color.WHITE, Basis(Vector3.RIGHT, tilt))
	for side: float in [-1.0, 1.0]:
		var inner_2 := _slant_z(2.0) + 0.08
		var inner_top := _slant_z(2.7) + 0.08
		_prism(kit, [Vector2(inner_2, 2.0), Vector2(-1.95, 2.0), Vector2(-1.95, 2.7), Vector2(inner_top, 2.7)], side * 1.07, side * 1.1, Color.WHITE)
	kit.box(Vector3(-1.12, 2.42, -0.9), Vector3(0.04, 0.5, 1.3), Color.WHITE)
	for x: float in [-0.575, 0.575]:
		kit.box(Vector3(x, 2.45, 3.0), Vector3(0.75, 0.5, 0.04), Color.WHITE)
	kit.box(Vector3(1.235, 2.385, 2.27), Vector3(0.025, 0.47, 1.0), Color.WHITE)
	return kit.commit()


## The amber dome on the roof: a dome, never a bar.
static func _dome_mesh() -> ArrayMesh:
	var kit := _MeshKit.new()
	kit.rbox(Vector3(0.0, 3.1, 0.3), Vector3(0.24, 0.2, 0.24), Color.WHITE, 2.0, {"detail": 2, "shade": false})
	return kit.commit()


## One wheel, hub facing +X: a tire, a whitewall, a chrome hubcap with five lug nuts
## (so it can be seen turning), and a lavender center cap. Centered on its axle.
static func _wheel_mesh() -> ArrayMesh:
	var kit := _MeshKit.new()
	var r := WHEEL_RADIUS
	var h := WHEEL_WIDTH * 0.5
	kit.tube(PackedVector3Array([Vector3(-h, 0, 0), Vector3(-h * 0.7, 0, 0), Vector3(h * 0.7, 0, 0), Vector3(h, 0, 0)]),
		PackedFloat32Array([r * 0.84, r, r, r * 0.84]), TIRE, 16, {"jitter": 0.0, "cap": true, "cap_start": true})
	kit.tube(PackedVector3Array([Vector3(-h * 1.01, 0, 0), Vector3(h * 1.01, 0, 0)]), PackedFloat32Array([r * 0.72, r * 0.72]), WHITEWALL, 16, {"jitter": 0.0, "cap": true, "cap_start": true})
	kit.tube(PackedVector3Array([Vector3(-h * 1.03, 0, 0), Vector3(h * 1.03, 0, 0)]), PackedFloat32Array([r * 0.5, r * 0.5]), CHROME, 14, {"jitter": 0.0, "cap": true, "cap_start": true})
	kit.tube(PackedVector3Array([Vector3(h * 1.03, 0, 0), Vector3(h * 1.12, 0, 0)]), PackedFloat32Array([r * 0.2, r * 0.17]), BAND, 10, {"jitter": 0.0, "cap": true})
	for index: int in 5:
		var angle := TAU * float(index) / 5.0
		kit.box(Vector3(h * 1.05, sin(angle) * r * 0.33, cos(angle) * r * 0.33), Vector3(0.03, 0.045, 0.045), RUBBER)
	return kit.commit()


## Where the outer windshield line is at height y (side profile).
static func _slant_z(y: float) -> float:
	var t := (y - SLANT_BOTTOM.y) / (SLANT_TOP.y - SLANT_BOTTOM.y)
	return lerpf(SLANT_BOTTOM.x, SLANT_TOP.x, t)


## A convex side-profile shape, points (z, y) in order, extruded from x0 to x1:
## both faces and every edge, faceted.
static func _prism(kit: _MeshKit, points: Array, x0: float, x1: float, color: Color) -> void:
	var low := minf(x0, x1)
	var high := maxf(x0, x1)
	var count := points.size()
	var middle := Vector2.ZERO
	for point: Vector2 in points:
		middle += point
	middle /= float(count)
	for index: int in count:
		var a: Vector2 = points[index]
		var b: Vector2 = points[(index + 1) % count]
		# The faces at both ends, as fans from the middle.
		_tri(kit, Vector3(low, middle.y, middle.x), Vector3(low, a.y, a.x), Vector3(low, b.y, b.x), Vector3.LEFT, color)
		_tri(kit, Vector3(high, middle.y, middle.x), Vector3(high, a.y, a.x), Vector3(high, b.y, b.x), Vector3.RIGHT, color)
		# The edge between a and b, facing away from the middle.
		var along := b - a
		var out := Vector2(-along.y, along.x).normalized()
		if out.dot((a + b) * 0.5 - middle) < 0.0:
			out = -out
		var normal := Vector3(0.0, out.y, out.x)
		var shade := color.lightened(0.05) if normal.y > 0.5 else (color.darkened(0.3) if normal.y < -0.5 else color)
		_tri(kit, Vector3(low, a.y, a.x), Vector3(high, a.y, a.x), Vector3(high, b.y, b.x), normal, shade)
		_tri(kit, Vector3(low, a.y, a.x), Vector3(high, b.y, b.x), Vector3(low, b.y, b.x), normal, shade)


## A triangle facing normal, whichever way its corners wind.
static func _tri(kit: _MeshKit, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color) -> void:
	if (c - a).cross(b - a).dot(normal) >= 0.0:
		kit.triangle(a, b, c, normal, color)
	else:
		kit.triangle(a, c, b, normal, color)


# ---------------------------------------------------------------- lights and lettering


## Headlights, turn signals, taillights, side markers and the cabin's ceiling light.
## Returns the taillights' materials, which flare when the van brakes.
static func _lights(shell: Node3D) -> Array[StandardMaterial3D]:
	var tails: Array[StandardMaterial3D] = []
	for side: float in [-1.0, 1.0]:
		_LowPoly.glow(shell, Vector3(0.3, 0.16, 0.03), Vector3(side * 0.78, 1.38, -3.355), Color(1.0, 0.95, 0.78), 2.5)
		_LowPoly.glow(shell, Vector3(0.14, 0.07, 0.03), Vector3(side * 0.9, 1.15, -3.322), BEACON_AMBER, 1.5)
		var tail := _LowPoly.glow(shell, Vector3(0.14, 0.48, 0.03), Vector3(side * 1.0, 1.95, 3.085), Color(0.9, 0.12, 0.08), Constants.VAN_TAIL_GLOW) as MeshInstance3D
		tails.append(tail.material_override as StandardMaterial3D)
		_LowPoly.glow(shell, Vector3(0.12, 0.08, 0.03), Vector3(side * 0.62, 0.82, 3.255), Color(1.0, 0.97, 0.9), 0.8)
	for z: float in [-1.6, 2.85]:
		_LowPoly.glow(shell, Vector3(0.012, 0.06, 0.12), Vector3(-1.197, 1.3, z), BEACON_AMBER, 1.5)
	_LowPoly.glow(shell, Vector3(0.5, 0.025, 0.24), Vector3(0.0, 2.865, 0.4), Color(1.0, 0.93, 0.78), 1.4)
	return tails


## The lettering (VanLook/Livery), all from ui/strings.gd: THE NICE BOYS and the
## motto on the left, a smaller THE NICE BOYS on the sliding door, and the back's
## "HOW'S MY ENFORCING?" wrapped onto two lines.
static func _livery(look: Node3D) -> void:
	var livery := Node3D.new()
	livery.name = "Livery"
	look.add_child(livery)
	var side := str(_Strings.UI["van_side"])
	_letter(_LowPoly.text_sign(livery, side, Vector3(-1.2, 2.33, 1.55), 72, LETTERING, -PI * 0.5))
	_letter(_LowPoly.text_sign(livery, str(_Strings.UI["van_motto"]), Vector3(-1.2, 1.86, 1.55), 30, LETTERING, -PI * 0.5))
	_letter(_LowPoly.text_sign(livery, side, Vector3(1.268, 2.0, 2.39), 30, LETTERING, PI * 0.5))
	var rear := _LowPoly.text_sign(livery, str(_Strings.UI["van_rear"]), Vector3(0.0, 1.92, 3.077), 26, LETTERING)
	rear.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rear.width = 330.0
	_letter(rear)


## Painted-on lettering: no dark outline, a pale one so it reads on cream.
static func _letter(label: Label3D) -> void:
	label.outline_size = maxi(2, label.font_size / 12)
	label.outline_modulate = Color(1.0, 1.0, 1.0, 0.85)
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _glass_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = GLASS_TINT
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Soft enough that the sun glints off it without blowing out into a white blob.
	material.roughness = 0.35
	material.metallic_specular = 0.45
	return material


static func _glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material


## Collision boxes ([center, size] each) that move with the van.
static func _solid(look: Node3D, boxes: Array) -> void:
	var body := AnimatableBody3D.new()
	body.name = "Solid"
	body.sync_to_physics = false
	for entry: Array in boxes:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = entry[1]
		shape.shape = box
		shape.position = entry[0]
		body.add_child(shape)
	look.add_child(body)


## Rolls the wheels by how far the van went, sways the Shell (and Livery) on its
## springs when it speeds up, brakes or turns, flares the taillights when it
## brakes, and pulses the amber dome. Reads only the VanLook's own motion, so it
## works the same under a ride, the arrival, or the studio.
class Motion extends Node:
	var _look: Node3D
	var _shell: Node3D
	var _livery: Node3D
	var _wheels: Array[Node3D] = []
	var _tails: Array[StandardMaterial3D] = []
	var _dome: StandardMaterial3D
	var _dome_light: OmniLight3D
	var _last: Transform3D
	var _has_last: bool = false
	var _speed: float = 0.0
	var _pitch: float = 0.0
	var _pitch_speed: float = 0.0
	var _roll: float = 0.0
	var _roll_speed: float = 0.0
	var _braking: float = 0.0
	## Speed now (m/s along its nose) and the last acceleration; read by tests.
	var speed: float = 0.0
	var accel: float = 0.0

	func setup(look: Node3D, tails: Array[StandardMaterial3D]) -> void:
		_look = look
		_shell = look.get_node("Shell")
		_livery = look.get_node("Livery")
		for wheel: Node in look.get_node("Wheels").get_children():
			_wheels.append(wheel as Node3D)
		_tails = tails
		_dome = (_shell.get_node("Dome") as MeshInstance3D).material_override as StandardMaterial3D
		_dome_light = _shell.get_node("DomeLight") as OmniLight3D

	## Forget the last pose (after a teleport), so nothing spins or lurches.
	func settle() -> void:
		_has_last = false
		_speed = 0.0

	func _physics_process(delta: float) -> void:
		if _look == null or delta <= 0.0:
			return
		var now := _look.global_transform
		if not _has_last:
			_last = now
			_has_last = true
			return
		var moved := now.origin - _last.origin
		var forward := -now.basis.z.normalized()
		var along := moved.dot(forward)
		var turned := _last.basis.z.normalized().signed_angle_to(now.basis.z.normalized(), Vector3.UP)
		_last = now
		# A jump this big is a teleport (the ride placing a van at the curb): skip it.
		if moved.length() > Constants.VAN_TELEPORT_METERS:
			_speed = 0.0
			return
		var new_speed := along / delta
		accel = (new_speed - _speed) / delta
		_speed = new_speed
		speed = new_speed
		for wheel: Node3D in _wheels:
			# The left wheels are turned around, so they spin the other way round.
			var sign_x := 1.0 if wheel.position.x > 0.0 else -1.0
			wheel.rotation.x = wrapf(wheel.rotation.x - sign_x * along / WHEEL_RADIUS, -PI, PI)
		# The body leans against the change in speed: nose down braking, up pulling
		# away; and out of a turn. A spring brings it back, past level once.
		var pitch_goal := clampf(accel * Constants.VAN_SWAY_PER_ACCEL, -Constants.VAN_SWAY_MAX, Constants.VAN_SWAY_MAX)
		var lateral := _speed * turned / delta
		var roll_goal := clampf(-lateral * Constants.VAN_SWAY_PER_ACCEL, -Constants.VAN_SWAY_MAX, Constants.VAN_SWAY_MAX)
		_pitch_speed += (Constants.VAN_SWAY_STIFFNESS * (pitch_goal - _pitch) - Constants.VAN_SWAY_DAMPING * _pitch_speed) * delta
		_pitch += _pitch_speed * delta
		_roll_speed += (Constants.VAN_SWAY_STIFFNESS * (roll_goal - _roll) - Constants.VAN_SWAY_DAMPING * _roll_speed) * delta
		_roll += _roll_speed * delta
		var sway := Transform3D(Basis.from_euler(Vector3(_pitch, 0.0, _roll)), Vector3.ZERO)
		_shell.transform = sway
		_livery.transform = sway
		_braking = 1.0 if accel < -Constants.VAN_BRAKE_LIGHT_ACCEL and _speed > 0.3 else maxf(0.0, _braking - delta * 4.0)

	func _process(_delta: float) -> void:
		if _dome == null:
			return
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * TAU * Constants.VAN_DOME_PULSE_HZ)
		_dome.emission_energy_multiplier = lerpf(0.9, 3.2, pulse)
		_dome_light.light_energy = lerpf(0.3, 1.4, pulse)
		for tail: StandardMaterial3D in _tails:
			tail.emission_energy_multiplier = lerpf(Constants.VAN_TAIL_GLOW, Constants.VAN_BRAKE_GLOW, _braking)
