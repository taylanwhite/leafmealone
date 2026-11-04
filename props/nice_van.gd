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
##   VanLook/Motion    rolls the wheels, steers the front wheels and the steering
##                     wheel with the yaw rate, swings the air freshener, sways the
##                     body, flares the brake lights and pulses the dome, from how
##                     the VanLook itself moves. Whoever moves the van
##                     (net/run_events/shuttle.gd) just moves it.
##   The moving parts and markers (nice_boys:4, the Courtesy Shuttle), all riding
##   the Shell so they sway with the body:
##   Shell/SideDoor    three telescoping panels on the outside track: slide(open, at)
##   Shell/BackDoors   DoorL and DoorR on their hinges: swing(open, at)
##   Shell/SteeringWheel, Shell/Freshener (the daisy on its string), Shell/MirrorR
##                     (the door-side mirror's glint, shown by the shuttle)
##   Shell/Seats/Seat0..3      rider seats on the left bench, facing the open side,
##                             a shoulder apart (RIDER_SEAT_Z), front to back
##   Shell/CabinCam/Seat0..3   a rider's eyes from each seat, looking out
##   Shell/WindowFace/Seat0..3 where a knocking rider's face leans to
##   Shell/CrewSeats/Seat0..2  shotgun, then the back bench, facing forward
##   Shell/DriverSeat, Shell/FreshenerCam
##   VanLook/DoorStep (the ground outside the door), VanLook/RearStep (the bumper)
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

## The sliding door (nice_boys:4): three panels on the outside track, outermost
## first. Parked open they stack over the rear quarter, as cast:5 drew it; shut,
## they telescope forward over the whole open side, front to back.
const DOOR_PANEL_X: Array[float] = [1.265, 1.235, 1.205]
const DOOR_PANEL_CLOSED_Z: Array[float] = [-1.0, 0.6, 2.15]
const DOOR_PANEL_OPEN_Z: float = 2.2
const DOOR_PANEL_LENGTH: float = 1.7
## Each panel's window, sill to head (y).
const DOOR_WINDOW_Y := Vector2(1.86, 2.62)
## The water cooler's middle on the floor (x, z): the cabin's back-left corner,
## where the riders' bench meets the back bench (p1-van: the bench runs up to the
## cab now, so four riders sit a shoulder apart instead of head to head).
const COOLER_AT := Vector2(-0.82, 1.9)
## The riders' cab shot: the eye, and what it looks at (the daisy and the road).
## Leaning in between the front seats: the driver's and shotgun's heads at the
## edges, the daisy above the road in the middle (R2c van review: from up under
## the ceiling at (0.05, 2.78, -0.2), a full cab's two heads filled the lower half).
const FRESHENER_CAM := Vector3(0.0, 2.55, -1.25)
const FRESHENER_LOOK := Vector3(0.0, 2.5, -4.0)
## The open side's invisible wall (R2c van): a slab this thick and tall, its
## middle at x and y, over the doorway's span (Constants.VAN_DOORWAY_Z) and this
## much past each end, onto the door frame.
const DOORWAY_X: float = 1.16
const DOORWAY_Y: float = 1.6
const DOORWAY_THICK: float = 0.12
const DOORWAY_HEIGHT: float = 2.6
const DOORWAY_OVERLAP: float = 0.45
## The engine's sound comes from here, under the hood.
const ENGINE_AT := Vector3(0.0, 1.0, -2.6)
## The back doors' hinges (x) and how far they swing open (radians).
const BACK_HINGE_X: float = 1.05
const BACK_DOOR_OPEN: float = 1.9
## The rider seats along the left bench (z), facing the open side. p1-van: 0.7 m
## apart, all in front of the open doorway (the open door's panels stack over z
## 1.35 and on), so each rider steps straight in and out at their own seat and
## nobody passes in front of anyone's eyes; at 0.45 m apart (the old seats) two
## riders' heads (0.54 m across) touched, and the stage camera's near-body cut hid
## a neighbor whole ("vanishes into the seat", playtest r1).
const RIDER_SEAT_Z: Array[float] = [-1.2, -0.5, 0.2, 0.9]
## The open side between the B-pillar and the open door's stacked panels (z): where
## anyone can step through it.
const DOOR_OPENING_Z := Vector2(-1.75, 1.3)
## The back bench's two crew seats (x), facing forward, well behind the riders.
const CREW_BENCH_X: Array[float] = [0.1, 0.7]
## The riders' bench along the left wall: from just behind the cab's seats to the
## last rider (z).
const BENCH_Z := Vector2(-1.52, 1.22)
## The cab shot's dolly (p1-van, playtest nb1: a straight move from the seat to the
## cab went through the next rider's head). It leans out over the aisle at the
## rider's own seat first, turning to face the front, then glides up the aisle to
## FRESHENER_CAM: a cubic Bezier through these two handles (x, y; the first at the
## seat's z, the second at DOLLY_FRONT_Z).
const DOLLY_OUT := Vector2(0.45, 2.5)
const DOLLY_UP := Vector2(0.2, 2.56)
const DOLLY_FRONT_Z: float = -0.55
## The steering wheel's hub, and its tilt back toward the driver.
const WHEEL_HUB := Vector3(-0.5, 2.0, -2.06)
const WHEEL_UP := Vector3(0.0, 0.866, 0.5)

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
		_cache[key] = {
			"body": _body_mesh(paint), "glass": _glass_mesh(), "dome": _dome_mesh(), "wheel": _wheel_mesh(),
			"door_panel": _door_panel_mesh(paint), "door_panel_glass": _door_panel_glass_mesh(),
			"back_door": [_back_door_mesh(paint, -1.0), _back_door_mesh(paint, 1.0)], "back_door_glass": [_back_door_glass_mesh(-1.0), _back_door_glass_mesh(1.0)],
			"steering": _steering_mesh(), "freshener": _freshener_mesh(),
		}
	var meshes: Dictionary = _cache[key]
	var shell := Node3D.new()
	shell.name = "Shell"
	look.add_child(shell)
	var body := _Stylized.instance(meshes["body"], MATERIAL)
	body.name = "Body"
	shell.add_child(body)
	var glass_material := _glass_material()
	var glass := MeshInstance3D.new()
	glass.name = "Glass"
	glass.mesh = meshes["glass"]
	glass.material_override = glass_material
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glass.set_meta("keep_material", true)
	shell.add_child(glass)
	_moving_parts(shell, meshes, glass_material)
	_markers(look, shell)
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
	# The open side, kept shut to anyone walking (R2c van: through Annex B's
	# turnstile you walked straight into its aisle and stood there). Riders and
	# the crew get in and out on staged anchors, which go through it.
	var doorway := AnimatableBody3D.new()
	doorway.name = "Doorway"
	doorway.sync_to_physics = false
	var gap := CollisionShape3D.new()
	var gap_box := BoxShape3D.new()
	var span: Vector2 = Constants.VAN_DOORWAY_Z
	gap_box.size = Vector3(DOORWAY_THICK, DOORWAY_HEIGHT, span.y - span.x + DOORWAY_OVERLAP * 2.0)
	gap.shape = gap_box
	gap.position = Vector3(DOORWAY_X, DOORWAY_Y, (span.x + span.y) * 0.5)
	doorway.add_child(gap)
	look.add_child(doorway)
	var motion := Motion.new()
	motion.name = "Motion"
	motion.setup(look, lights)
	look.add_child(motion)
	return look


## A marker of a built VanLook by name ("Seats/Seat0", "DoorStep", ...): the
## Shell's first (seats, cameras, faces), then the VanLook's own (the ground steps).
static func marker(look: Node3D, path: String) -> Node3D:
	if look == null:
		return null
	var on_shell := look.get_node_or_null("Shell/" + path) as Node3D
	return on_shell if on_shell != null else look.get_node_or_null(path) as Node3D


## The riders' cab shot's dolly, in the Shell's space, u from 0 (the seat's eye,
## seat_cam) to 1 (the cab shot, FRESHENER_CAM): out over the aisle at the seat
## first, then up the aisle to the front (DOLLY_OUT, DOLLY_UP). It turns to face
## the front over the first half, while it's leaning out, so it never looks along
## the bench at the riders' faces as it goes.
static func dolly_pose(seat_cam: Transform3D, u: float) -> Transform3D:
	var k := clampf(u, 0.0, 1.0)
	var front := Transform3D(Basis.looking_at(FRESHENER_LOOK - FRESHENER_CAM, Vector3.UP), FRESHENER_CAM)
	var z := seat_cam.origin.z
	var a := seat_cam.origin
	var b := Vector3(DOLLY_OUT.x, DOLLY_OUT.y, z)
	var c := Vector3(DOLLY_UP.x, DOLLY_UP.y, minf(DOLLY_FRONT_Z, z))
	var d := FRESHENER_CAM
	var m := 1.0 - k
	var at := a * (m * m * m) + b * (3.0 * m * m * k) + c * (3.0 * m * k * k) + d * (k * k * k)
	var turn := smoothstep(0.0, 0.6, k)
	var basis := seat_cam.basis.orthonormalized().slerp(front.basis.orthonormalized(), turn)
	return Transform3D(basis, at)


## The sliding door and the back doors (Door nodes that animate themselves from
## the shared clock), the steering wheel, the air freshener and the mirror glint.
static func _moving_parts(shell: Node3D, meshes: Dictionary, glass_material: Material) -> void:
	var side := SideDoor.new()
	side.name = "SideDoor"
	shell.add_child(side)
	for index: int in DOOR_PANEL_X.size():
		var panel := _Stylized.instance(meshes["door_panel"], MATERIAL)
		panel.name = "Panel%d" % index
		panel.position = Vector3(DOOR_PANEL_X[index], 0.0, DOOR_PANEL_OPEN_Z)
		side.add_child(panel)
		var pane := MeshInstance3D.new()
		pane.name = "Glass"
		pane.mesh = meshes["door_panel_glass"]
		pane.material_override = glass_material
		pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pane.set_meta("keep_material", true)
		panel.add_child(pane)
	# The handle and THE NICE BOYS ride the outermost panel, the one that travels.
	var front := side.get_node("Panel0") as Node3D
	var handle := _LowPoly.box(front, Vector3(0.02, 0.035, 0.12), Vector3(0.026, 1.86, -DOOR_PANEL_LENGTH * 0.5 + 0.12), CHROME)
	handle.name = "Handle"
	_letter(_LowPoly.text_sign(front, str(_Strings.UI["van_side"]), Vector3(0.018, (1.52 + DOOR_WINDOW_Y.x) * 0.5, 0.19), 30, LETTERING, PI * 0.5))
	side.setup(DOOR_PANEL_OPEN_Z, DOOR_PANEL_CLOSED_Z)
	var back := BackDoors.new()
	back.name = "BackDoors"
	shell.add_child(back)
	for index: int in 2:
		var hinge_side := -1.0 if index == 0 else 1.0
		var door := Node3D.new()
		door.name = "DoorL" if index == 0 else "DoorR"
		door.position = Vector3(hinge_side * BACK_HINGE_X, 0.0, 3.0)
		back.add_child(door)
		var leaf := _Stylized.instance((meshes["back_door"] as Array)[index], MATERIAL)
		leaf.name = "Leaf"
		door.add_child(leaf)
		var pane := MeshInstance3D.new()
		pane.name = "Glass"
		pane.mesh = (meshes["back_door_glass"] as Array)[index]
		pane.material_override = glass_material
		pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pane.set_meta("keep_material", true)
		door.add_child(pane)
	# "HOW'S MY ENFORCING?" on the right-hand door, wrapped to its width.
	var rear := _LowPoly.text_sign(back.get_node("DoorR"), str(_Strings.UI["van_rear"]), Vector3(-0.53, 1.92, 0.077), 24, LETTERING)
	rear.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rear.width = 200.0
	_letter(rear)
	var steering := Node3D.new()
	steering.name = "SteeringWheel"
	steering.transform = Transform3D(Basis(Vector3.RIGHT, WHEEL_UP, Vector3.RIGHT.cross(WHEEL_UP).normalized()), WHEEL_HUB)
	shell.add_child(steering)
	var wheel_mesh := _Stylized.instance(meshes["steering"], MATERIAL)
	wheel_mesh.name = "Ring"
	steering.add_child(wheel_mesh)
	var freshener := Node3D.new()
	freshener.name = "Freshener"
	freshener.position = Vector3(0.0, 2.72, -2.05)
	shell.add_child(freshener)
	var daisy := _Stylized.instance(meshes["freshener"], MATERIAL)
	daisy.name = "Daisy"
	freshener.add_child(daisy)
	# The door-side mirror's glint (the driver's check; the shuttle shows it).
	var glint := _LowPoly.glow(shell, Vector3(0.05, 0.1, 0.01), Vector3(1.32, 2.14, -2.355), Color(1.0, 1.0, 0.92), 6.0) as Node3D
	glint.name = "MirrorR"
	glint.visible = false


## Where everyone sits and stands, as Marker3Ds (see the header).
static func _markers(look: Node3D, shell: Node3D) -> void:
	var facing_side := Basis(Vector3.UP, -PI * 0.5)
	var seats := Node3D.new()
	seats.name = "Seats"
	shell.add_child(seats)
	var cams := Node3D.new()
	cams.name = "CabinCam"
	shell.add_child(cams)
	var faces := Node3D.new()
	faces.name = "WindowFace"
	shell.add_child(faces)
	for index: int in RIDER_SEAT_Z.size():
		var z := RIDER_SEAT_Z[index]
		_marker(seats, "Seat%d" % index, Transform3D(facing_side, Vector3(-0.78, 1.01, z)))
		# Eye height when sat, looking out the open side and a touch down.
		_marker(cams, "Seat%d" % index, Transform3D(facing_side * Basis(Vector3.RIGHT, -0.08), Vector3(-0.7, 2.3, z)))
		_marker(faces, "Seat%d" % index, Transform3D(facing_side, Vector3(-0.3, 1.01, z)))
	var crew := Node3D.new()
	crew.name = "CrewSeats"
	shell.add_child(crew)
	# Shotgun in the cab, then two on the back bench facing forward.
	_marker(crew, "Seat0", Transform3D(Basis.IDENTITY, Vector3(0.5, 1.0, -1.92)))
	_marker(crew, "Seat1", Transform3D(Basis.IDENTITY, Vector3(CREW_BENCH_X[0], 1.01, 2.56)))
	_marker(crew, "Seat2", Transform3D(Basis.IDENTITY, Vector3(CREW_BENCH_X[1], 1.01, 2.56)))
	_marker(shell, "DriverSeat", Transform3D(Basis.IDENTITY, Vector3(-0.5, 1.0, -1.92)))
	# The cab from just behind the front seats, between the headrests: the driver
	# at the wheel on the left, the daisy swinging in the middle, the road ahead
	# through the windshield (R2b van: from over the passenger seat it sat inside
	# the head of whoever rode shotgun).
	var at := FRESHENER_CAM
	_marker(shell, "FreshenerCam", Transform3D(Basis.looking_at(FRESHENER_LOOK - at, Vector3.UP), at))
	_marker(look, "DoorStep", Transform3D(facing_side.rotated(Vector3.UP, PI), Vector3(1.75, 0.0, 0.3)))
	_marker(look, "RearStep", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.87, 3.24)))


static func _marker(parent: Node3D, marker_name: String, xform: Transform3D) -> void:
	var node := Marker3D.new()
	node.name = marker_name
	node.transform = xform
	parent.add_child(node)


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


## The back around its two doors (Shell/BackDoors, _back_door_mesh): the corner
## posts that carry the taillights, the header over the doors, and the bumper the
## straggler hops onto.
static func _back_wall(kit: _MeshKit, paint: Color) -> void:
	var z := 3.0
	for side: float in [-1.0, 1.0]:
		kit.box(Vector3(side * 1.12, 1.27, z), Vector3(0.14, 0.5, 0.14), BAND)
		kit.box(Vector3(side * 1.12, 2.21, z), Vector3(0.14, 1.38, 0.14), paint)
		kit.box(Vector3(side * 1.12, 1.535, z + 0.071), Vector3(0.12, 0.03, 0.006), BAND_DEEP)
	kit.box(Vector3(0.0, 2.9, z), Vector3(2.38, 0.06, 0.14), paint)
	# The door frame's floor sill, so the open back shows a floor, not a gap.
	kit.box(Vector3(0.0, 1.0, z), Vector3(2.1, 0.04, 0.16), TRIM)
	kit.rbox(Vector3(0.0, 0.76, 3.16), Vector3(1.16, 0.11, 0.09), TRIM, 5.0, {"detail": 2})


## One back door, hung on its hinge: side -1 the left (hinge at -BACK_HINGE_X,
## the door reaching to the middle), 1 the right. In the hinge's own space, so
## swinging is a turn about y. The left one carries the Daisy Seal on its band.
static func _back_door_mesh(paint: Color, side: float) -> ArrayMesh:
	var kit := _MeshKit.new()
	var w := BACK_HINGE_X
	# The door's middle, from the hinge toward the van's middle.
	var mid := -side * w * 0.5
	kit.box(Vector3(mid, 1.27, 0.0), Vector3(w, 0.5, 0.14), BAND)
	kit.box(Vector3(mid, 1.86, 0.0), Vector3(w, 0.68, 0.14), paint)
	# Round the window: the hinge-side strip, the middle strip, the header.
	kit.box(Vector3(-side * 0.05, 2.45, 0.0), Vector3(0.1, 0.5, 0.14), paint)
	kit.box(Vector3(-side * (w - 0.1), 2.45, 0.0), Vector3(0.2, 0.5, 0.14), paint)
	kit.box(Vector3(mid, 2.79, 0.0), Vector3(w, 0.18, 0.14), paint)
	kit.box(Vector3(mid, 1.535, 0.071), Vector3(w - 0.02, 0.03, 0.006), BAND_DEEP)
	# The seam where they meet (rubber on the right door's edge) and the handle.
	if side > 0.0:
		kit.box(Vector3(-w + 0.007, 1.94, 0.072), Vector3(0.014, 1.84, 0.006), RUBBER)
	kit.box(Vector3(-side * (w - 0.13), 1.72, 0.08), Vector3(0.12, 0.035, 0.02), CHROME)
	if side < 0.0:
		_NiceSeal.add(kit, Vector3(mid, 1.29, 0.072), 0.2, Vector3.BACK, 1)
	return kit.commit()


static func _back_door_glass_mesh(side: float) -> ArrayMesh:
	var kit := _MeshKit.new()
	kit.box(Vector3(-side * 0.475, 2.45, 0.0), Vector3(0.75, 0.5, 0.04), Color.WHITE)
	return kit.commit()


## One sliding door panel, centered on its own origin (z), its outer face at
## +x: the lavender band, a window, the pinstripe.
static func _door_panel_mesh(paint: Color) -> ArrayMesh:
	var kit := _MeshKit.new()
	var length := DOOR_PANEL_LENGTH
	var t := 0.03
	# A tall window (R2b van: a seated rider's whole ride is the view through these,
	# and a slot at eye height showed a strip of street over a cream wall).
	var sill := DOOR_WINDOW_Y.x
	var head := DOOR_WINDOW_Y.y
	kit.box(Vector3(0.0, 1.27, 0.0), Vector3(t, 0.5, length), BAND)
	kit.box(Vector3(0.0, (1.52 + sill) * 0.5, 0.0), Vector3(t, sill - 1.52, length), paint)
	for side: float in [-1.0, 1.0]:
		kit.box(Vector3(0.0, (sill + head) * 0.5, side * (length * 0.5 - 0.1)), Vector3(t, head - sill, 0.2), paint)
	kit.box(Vector3(0.0, (head + 2.86) * 0.5, 0.0), Vector3(t, 2.86 - head, length), paint)
	# Rubber round the window.
	for y: float in [sill, head]:
		kit.box(Vector3(t * 0.5 + 0.003, y, 0.0), Vector3(0.006, 0.025, length - 0.4), RUBBER)
	kit.box(Vector3(t * 0.5 + 0.003, 1.535, 0.0), Vector3(0.006, 0.03, length - 0.02), BAND_DEEP)
	# Rubber round its edges, so three stacked panels read as three.
	for side: float in [-1.0, 1.0]:
		kit.box(Vector3(t * 0.5 + 0.003, 1.94, side * (length * 0.5 - 0.006)), Vector3(0.006, 1.84, 0.012), RUBBER)
	return kit.commit()


static func _door_panel_glass_mesh() -> ArrayMesh:
	var kit := _MeshKit.new()
	kit.box(Vector3(0.0, (DOOR_WINDOW_Y.x + DOOR_WINDOW_Y.y) * 0.5, 0.0), Vector3(0.022, DOOR_WINDOW_Y.y - DOOR_WINDOW_Y.x, DOOR_PANEL_LENGTH - 0.4), Color.WHITE)
	return kit.commit()


## The steering wheel in its own space (the ring in x-y, the column down -z), with
## a crossbar and a horn button so it can be seen turning.
static func _steering_mesh() -> ArrayMesh:
	var kit := _MeshKit.new()
	var ring := PackedVector3Array()
	var radii := PackedFloat32Array()
	for index: int in 17:
		var angle := TAU * float(index) / 16.0
		ring.append(Vector3(cos(angle), sin(angle), 0.0) * 0.17)
		radii.append(0.018)
	kit.tube(ring, radii, RUBBER, 6, {"jitter": 0.0, "cap": false})
	kit.tube(PackedVector3Array([Vector3(-0.16, 0.0, 0.0), Vector3(0.16, 0.0, 0.0)]), PackedFloat32Array([0.012, 0.012]), RUBBER.lightened(0.15), 5, {"jitter": 0.0})
	kit.tube(PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(0.0, -0.16, 0.0)]), PackedFloat32Array([0.012, 0.012]), RUBBER.lightened(0.15), 5, {"jitter": 0.0})
	kit.tube(PackedVector3Array([Vector3(0.0, 0.0, 0.01), Vector3(0.0, 0.0, 0.03)]), PackedFloat32Array([0.04, 0.04]), BAND, 8, {"jitter": 0.0, "cap": true})
	# The column into the dash.
	kit.tube(PackedVector3Array([Vector3(0.0, 0.0, -0.01), Vector3(0.0, 0.0, -0.18)]), PackedFloat32Array([0.025, 0.03]), RUBBER, 6, {"jitter": 0.0})
	return kit.commit()


## The daisy air freshener on its string, hanging from its pivot (the mirror).
static func _freshener_mesh() -> ArrayMesh:
	var kit := _MeshKit.new()
	kit.tube(PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(0.0, -0.12, 0.0)]), PackedFloat32Array([0.004, 0.004]), Color(0.95, 0.95, 0.95), 4, {"jitter": 0.0})
	_NiceSeal.add(kit, Vector3(0.0, -0.17, 0.0), 0.05, Vector3.FORWARD, 0, true)
	return kit.commit()


## The open right side: posts at both ends, the door track, the running board with
## its yellow "watch your step" edge, and the rail the sliding door (Shell/SideDoor,
## _door_panel_mesh) runs along, the whole length of the opening.
static func _right_side(kit: _MeshKit, paint: Color) -> void:
	kit.rbox(Vector3(1.12, 1.27, 3.0), Vector3(0.085, 0.25, 0.085), BAND, 4.0, {"detail": 1})
	kit.rbox(Vector3(1.12, 2.21, 3.0), Vector3(0.085, 0.7, 0.085), paint, 4.0, {"detail": 1})
	kit.box(Vector3(1.14, 2.86, 0.6), Vector3(0.05, 0.04, 4.9), RUBBER)
	kit.box(Vector3(1.15, 0.93, -0.08), Vector3(0.2, 0.05, 3.5), TRIM)
	kit.box(Vector3(1.252, 0.945, -0.08), Vector3(0.006, 0.022, 3.5), Color(0.98, 0.82, 0.2))
	# The rail the door's rollers hang from.
	kit.box(Vector3(1.24, 2.89, 0.58), Vector3(0.09, 0.03, 4.9), RUBBER)


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
	# The steering wheel turns (Shell/SteeringWheel, _steering_mesh).
	# The console between the seats: two cupholders (they mention them; docs/GAME.md).
	kit.box(Vector3(0.0, 1.3, -2.02), Vector3(0.3, 0.6, 0.4), RUBBER.lightened(0.1))
	for z: float in [-2.1, -1.94]:
		kit.tube(PackedVector3Array([Vector3(0.0, 1.6, z), Vector3(0.0, 1.62, z)]), PackedFloat32Array([0.05, 0.05]), Color(0.12, 0.12, 0.13), 8, {"jitter": 0.0})
	# The mirror; the daisy air freshener swings from it (Shell/Freshener).
	kit.box(Vector3(0.0, 2.76, -2.04), Vector3(0.3, 0.07, 0.03), RUBBER)
	# Its glass, facing the cab, so from behind it reads as a mirror, not a black bar.
	kit.box(Vector3(0.0, 2.76, -2.024), Vector3(0.27, 0.05, 0.004), Color(0.72, 0.8, 0.86))


## The back, seen through the open side: a bench along the left wall and one across
## the back, a water cooler, grab rails with loops, a ceiling light, and the Employee
## of the Month on the wall.
static func _cabin_inside(kit: _MeshKit) -> void:
	var bench_mid := (BENCH_Z.x + BENCH_Z.y) * 0.5
	var bench_long := BENCH_Z.y - BENCH_Z.x
	kit.box(Vector3(-0.82, 1.45, bench_mid), Vector3(0.42, 0.12, bench_long), VINYL)
	kit.box(Vector3(-0.82, 1.22, bench_mid), Vector3(0.36, 0.38, bench_long - 0.1), RUBBER)
	kit.box(Vector3(-1.0, 1.86, bench_mid), Vector3(0.08, 0.62, bench_long), VINYL.darkened(0.08))
	kit.box(Vector3(0.22, 1.45, 2.62), Vector3(1.66, 0.12, 0.42), VINYL)
	kit.box(Vector3(0.22, 1.22, 2.62), Vector3(1.6, 0.38, 0.36), RUBBER)
	kit.box(Vector3(0.22, 1.86, 2.88), Vector3(1.66, 0.62, 0.08), VINYL.darkened(0.08))
	_cooler(kit)
	# Grab rails along both sides of the ceiling, with lavender loops.
	for x: float in [-0.92, 0.92]:
		kit.tube(PackedVector3Array([Vector3(x, 2.79, -1.7), Vector3(x, 2.79, 2.7)]), PackedFloat32Array([0.018, 0.018]), CHROME, 6, {"jitter": 0.0})
		# Between the riders' seats, not over their faces.
		for index: int in RIDER_SEAT_Z.size() - 1:
			var z := (RIDER_SEAT_Z[index] + RIDER_SEAT_Z[index + 1]) * 0.5
			kit.tube(PackedVector3Array([Vector3(x, 2.79, z - 0.04), Vector3(x, 2.6, z - 0.07), Vector3(x, 2.53, z), Vector3(x, 2.6, z + 0.07), Vector3(x, 2.79, z + 0.04)]),
				PackedFloat32Array([0.014, 0.014, 0.014, 0.014, 0.014]), VINYL.darkened(0.2), 5, {"jitter": 0.0, "cap": false})
	# Employee of the Month: a white frame, a lavender card, a Daisy Seal.
	kit.box(Vector3(-1.04, 2.42, 0.9), Vector3(0.02, 0.44, 0.36), Color(0.97, 0.97, 0.95))
	kit.box(Vector3(-1.032, 2.42, 0.9), Vector3(0.01, 0.36, 0.28), BAND)
	_NiceSeal.add(kit, Vector3(-1.026, 2.45, 0.9), 0.1, Vector3.RIGHT)


## The water cooler, in the front corner against the left wall where the riders'
## bench starts (R2b van: it stood mid-cabin, a white block with a blue jug dead
## center in every rider's view): a stand with a recessed drip panel, two taps and
## a tray, an upside-down jug on top, and a paper-cup tube on the wall.
static func _cooler(kit: _MeshKit) -> void:
	var x := COOLER_AT.x
	var z := COOLER_AT.y
	var body := Color(0.9, 0.89, 0.86)
	kit.rbox(Vector3(x, 1.4, z), Vector3(0.15, 0.39, 0.15), body, 3.0, {"detail": 1})
	kit.box(Vector3(x + 0.152, 1.56, z), Vector3(0.01, 0.24, 0.2), body.darkened(0.25))
	kit.box(Vector3(x + 0.165, 1.46, z), Vector3(0.05, 0.02, 0.2), RUBBER)
	kit.box(Vector3(x + 0.165, 1.63, z - 0.05), Vector3(0.03, 0.035, 0.035), Color(0.85, 0.2, 0.2))
	kit.box(Vector3(x + 0.165, 1.63, z + 0.05), Vector3(0.03, 0.035, 0.035), Color(0.2, 0.4, 0.9))
	kit.tube(PackedVector3Array([Vector3(x, 1.79, z), Vector3(x, 1.85, z), Vector3(x, 1.93, z), Vector3(x, 2.17, z), Vector3(x, 2.22, z)]),
		PackedFloat32Array([0.035, 0.035, 0.12, 0.12, 0.09]), Color(0.55, 0.78, 0.95), 10, {"jitter": 0.0, "cap": true, "cap_start": true})
	kit.tube(PackedVector3Array([Vector3(-1.02, 1.86, z + 0.3), Vector3(-1.02, 2.14, z + 0.3)]), PackedFloat32Array([0.035, 0.035]), Color(0.97, 0.97, 0.95), 8, {"jitter": 0.0, "cap": true, "cap_start": true})
	kit.tube(PackedVector3Array([Vector3(-1.02, 2.1, z + 0.3), Vector3(-1.02, 2.14, z + 0.3)]), PackedFloat32Array([0.038, 0.038]), BAND, 8, {"jitter": 0.0, "cap": true})


## Every fixed window as one see-through mesh: the windshield, both cab doors and
## the left side (the doors carry their own panes).
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
		# The turn signals: the shuttle blinks the door side's pulling out.
		_LowPoly.glow(shell, Vector3(0.14, 0.07, 0.03), Vector3(side * 0.9, 1.15, -3.322), BEACON_AMBER, 1.5).name = "BlinkerL" if side < 0.0 else "BlinkerR"
		# On the corner posts, so they stay put when the back doors swing.
		var tail := _LowPoly.glow(shell, Vector3(0.11, 0.48, 0.03), Vector3(side * 1.12, 1.95, 3.085), Color(0.9, 0.12, 0.08), Constants.VAN_TAIL_GLOW) as MeshInstance3D
		tails.append(tail.material_override as StandardMaterial3D)
		_LowPoly.glow(shell, Vector3(0.12, 0.08, 0.03), Vector3(side * 0.62, 0.82, 3.255), Color(1.0, 0.97, 0.9), 0.8)
	for z: float in [-1.6, 2.85]:
		_LowPoly.glow(shell, Vector3(0.012, 0.06, 0.12), Vector3(-1.197, 1.3, z), BEACON_AMBER, 1.5)
	_LowPoly.glow(shell, Vector3(0.5, 0.025, 0.24), Vector3(0.0, 2.865, 0.4), Color(1.0, 0.93, 0.78), 1.4)
	return tails


## The lettering (VanLook/Livery), all from ui/strings.gd: THE NICE BOYS and the
## motto on the left. The smaller THE NICE BOYS rides the sliding door and the
## back's "HOW'S MY ENFORCING?" the right back door (_moving_parts), so they go
## where the doors go.
static func _livery(look: Node3D) -> void:
	var livery := Node3D.new()
	livery.name = "Livery"
	look.add_child(livery)
	var side := str(_Strings.UI["van_side"])
	_letter(_LowPoly.text_sign(livery, side, Vector3(-1.2, 2.33, 1.55), 72, LETTERING, -PI * 0.5))
	_letter(_LowPoly.text_sign(livery, str(_Strings.UI["van_motto"]), Vector3(-1.2, 1.86, 1.55), 30, LETTERING, -PI * 0.5))


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
	var _front: Array[Node3D] = []
	var _front_base: Array[float] = []
	var _steering: Node3D
	var _steering_base: Basis
	var _freshener: Node3D
	var _steer: float = 0.0
	var _swing := Vector2.ZERO
	var _swing_speed := Vector2.ZERO
	## The front wheels' steer now (radians, + is left); read by tests.
	var steer: float = 0.0
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
	## Chasing (driving:F, the Courtesy Shuttle sets it): the dome pulses fast and
	## bright and throws its light far, the lights in a fleeing truck's mirror.
	var urgent: bool = false
	var _dome_range: float = -1.0

	func setup(look: Node3D, tails: Array[StandardMaterial3D]) -> void:
		_look = look
		_shell = look.get_node("Shell")
		_livery = look.get_node("Livery")
		for wheel: Node in look.get_node("Wheels").get_children():
			_wheels.append(wheel as Node3D)
			if str(wheel.name).begins_with("WheelF"):
				_front.append(wheel as Node3D)
				_front_base.append((wheel as Node3D).rotation.y)
		_steering = _shell.get_node_or_null("SteeringWheel") as Node3D
		if _steering != null:
			_steering_base = _steering.transform.basis
		_freshener = _shell.get_node_or_null("Freshener") as Node3D
		_tails = tails
		_dome = (_shell.get_node("Dome") as MeshInstance3D).material_override as StandardMaterial3D
		_dome_light = _shell.get_node("DomeLight") as OmniLight3D

	## Forget the last pose (after a teleport), so nothing spins or lurches.
	func settle() -> void:
		_has_last = false
		_speed = 0.0

	## A pothole: the body kicks up and rocks, the air freshener jumps.
	func bump(strength: float = 1.0) -> void:
		_pitch_speed += Constants.VAN_BUMP_KICK * strength
		_roll_speed -= Constants.VAN_BUMP_KICK * 0.4 * strength
		_swing_speed += Vector2(Constants.VAN_BUMP_KICK * 6.0, Constants.VAN_BUMP_KICK * 3.0) * strength

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
		# The front wheels steer into the turn it's making (a bicycle model: the
		# yaw rate over the speed, times the wheelbase), and the wheel in the cab
		# turns with them; eased, so a corner never flicks them.
		var yaw_rate := turned / delta
		var goal := 0.0
		if absf(_speed) > 0.5:
			goal = clampf(atan(2.0 * WHEEL_Z * yaw_rate / absf(_speed)), -Constants.VAN_STEER_MAX, Constants.VAN_STEER_MAX)
		_steer = lerpf(_steer, goal, clampf(delta * Constants.VAN_STEER_RATE, 0.0, 1.0))
		steer = _steer
		for index: int in _front.size():
			_front[index].rotation.y = _front_base[index] + _steer
		if _steering != null:
			_steering.transform.basis = _steering_base * Basis(Vector3.BACK, -_steer * Constants.VAN_STEERING_RATIO)
		# The air freshener swings against the van's pull: fore and aft when it
		# speeds up or brakes, sideways in a turn.
		if _freshener != null:
			var push := Vector2(accel, -lateral) * Constants.VAN_FRESHENER_PUSH
			_swing_speed += (-Constants.VAN_FRESHENER_STIFFNESS * _swing - Constants.VAN_FRESHENER_DAMPING * _swing_speed - push) * delta
			_swing += _swing_speed * delta
			_swing = _swing.limit_length(0.9)
			_freshener.rotation = Vector3(_swing.x, 0.0, _swing.y)

	func _process(_delta: float) -> void:
		if _dome == null:
			return
		var hz := Constants.VAN_DOME_CHASE_HZ if urgent else Constants.VAN_DOME_PULSE_HZ
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * TAU * hz)
		var boost := Constants.VAN_DOME_CHASE_ENERGY if urgent else 1.0
		_dome.emission_energy_multiplier = lerpf(0.9, 3.2 * boost, pulse)
		_dome_light.light_energy = lerpf(0.3, 1.4 * boost, pulse)
		if _dome_range < 0.0:
			_dome_range = _dome_light.omni_range
		_dome_light.omni_range = Constants.VAN_DOME_CHASE_RANGE if urgent else _dome_range
		for tail: StandardMaterial3D in _tails:
			tail.emission_energy_multiplier = lerpf(Constants.VAN_TAIL_GLOW, Constants.VAN_BRAKE_GLOW, _braking)


## The sliding door: three panels that telescope along the outside track.
## slide(open, at) eases them over Constants.VAN_DOOR_SLIDE from wherever they
## are, starting at server time at, so every peer's door moves together; the
## outermost panel travels farthest, the innermost hardly at all.
class SideDoor extends Node3D:
	var _open_z: float = 0.0
	var _closed_z: Array[float] = []
	var _from: float = 1.0
	var _to: float = 1.0
	var _at: float = -1000.0
	## 1 fully open, 0 shut, as drawn now.
	var openness: float = 1.0

	func setup(open_z: float, closed_z: Array[float]) -> void:
		_open_z = open_z
		_closed_z = closed_z
		_apply(1.0)

	## Start sliding open (true) or shut at server time at.
	func slide(open: bool, at: float) -> void:
		_from = openness
		_to = 1.0 if open else 0.0
		_at = at

	## Open or shut right now, no motion (a van built mid-trip).
	func set_open_now(open: bool) -> void:
		_from = 1.0 if open else 0.0
		_to = _from
		_apply(_from)

	func target_open() -> bool:
		return _to > 0.5

	func _process(_delta: float) -> void:
		if is_equal_approx(openness, _to) and Net.server_time() >= _at:
			return
		var u := clampf((Net.server_time() - _at) / maxf(Constants.VAN_DOOR_SLIDE, 0.01), 0.0, 1.0)
		_apply(lerpf(_from, _to, u * u * (3.0 - 2.0 * u)))

	func _apply(value: float) -> void:
		openness = value
		for index: int in _closed_z.size():
			var panel := get_node_or_null("Panel%d" % index) as Node3D
			if panel != null:
				panel.position.z = lerpf(_closed_z[index], _open_z, value)


## The back doors on their hinges: swing(open, at) turns both out over
## Constants.VAN_BACK_DOOR_SWING, the left one a touch behind the right.
class BackDoors extends Node3D:
	var _from: float = 0.0
	var _to: float = 0.0
	var _at: float = -1000.0
	## 1 swung wide, 0 shut.
	var openness: float = 0.0

	func swing(open: bool, at: float) -> void:
		_from = openness
		_to = 1.0 if open else 0.0
		_at = at

	func set_open_now(open: bool) -> void:
		_from = 1.0 if open else 0.0
		_to = _from
		_apply(_from, _from)

	func _process(_delta: float) -> void:
		if is_equal_approx(openness, _to) and Net.server_time() >= _at + 0.2:
			return
		var seconds := maxf(Constants.VAN_BACK_DOOR_SWING, 0.01)
		var right := clampf((Net.server_time() - _at) / seconds, 0.0, 1.0)
		var left := clampf((Net.server_time() - _at - 0.12) / seconds, 0.0, 1.0)
		_apply(lerpf(_from, _to, _ease(left)), lerpf(_from, _to, _ease(right)))

	## Swinging out, a little past and back, like a door let go of.
	static func _ease(u: float) -> float:
		return 1.0 - pow(1.0 - u, 3.0) + 0.08 * sin(u * PI) * (1.0 - u)

	func _apply(left: float, right: float) -> void:
		openness = right
		var door_l := get_node_or_null("DoorL") as Node3D
		var door_r := get_node_or_null("DoorR") as Node3D
		if door_l != null:
			door_l.rotation.y = -left * BACK_DOOR_OPEN
		if door_r != null:
			door_r.rotation.y = right * BACK_DOOR_OPEN