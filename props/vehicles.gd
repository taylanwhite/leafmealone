extends RefCounted

## Authority: local, cosmetic. Looks for the rides in net/components/ride.gd,
## built with props/mesh_kit.gd as soft, rounded toy vehicles. Both face -Z.
## Seats sit two across at bed height (y 1.0) from z -1.2 back, so riders are
## always visible: Chefty is a cab-over truck with an open bed, and the van has
## its right side cut away so the captured players can be counted at a glance
## (docs/ART.md). Chefty carries the Chefty logo (DEC-006). The van is the NICE
## BOYS' Courtesy Shuttle, designed (OQ-012 closed): its model, livery and motion
## live in props/nice_van.gd, which build_van() hands over to.

const _LowPoly = preload("res://props/low_poly.gd")
const _MeshKit = preload("res://props/mesh_kit.gd")
const _NiceVan = preload("res://props/nice_van.gd")
## The van's cream paint, its Courtesy Lavender band, and its amber dome.
const VAN_PAINT := _NiceVan.PAINT
const VAN_BAND := _NiceVan.BAND
const BEACON_AMBER := _NiceVan.BEACON_AMBER
const _Stylized = preload("res://props/stylized.gd")
const _YardModels = preload("res://props/yard_models.gd")
const _WaterSources = preload("res://net/work/water_sources.gd")
const GLASS := Color(0.17, 0.22, 0.28)
const TIRE := Color(0.11, 0.11, 0.12)
const CHROME := Color(0.86, 0.86, 0.84)
const TRIM := Color(0.92, 0.9, 0.86)
const GRILLE := Color(0.14, 0.14, 0.15)
const PAINT := {"roughness": 0.55, "specular": 0.25}

## Chefty's 8 seats in its own space (gap-specs/critic.md C21): the driver and
## shotgun on the cab's bench, then the bed two across, three deep. A seat is
## where the rider's feet go; the cab's are low because riders sit there
## (player/cartoon_body.gd sit()). The bed's first row clears the water tank.
const CHEFTY_SEATS: Array[Vector3] = [
	Vector3(-0.45, 0.62, -2.05), Vector3(0.45, 0.62, -2.05),
	Vector3(-0.5, 1.0, -0.05), Vector3(0.5, 1.0, -0.05),
	Vector3(-0.5, 1.0, 0.9), Vector3(0.5, 1.0, 0.9),
	Vector3(-0.5, 1.0, 1.85), Vector3(0.5, 1.0, 1.85),
]
## The cab seats (driver, shotgun); the rest are in the bed.
const CHEFTY_CAB_SEATS: int = 2
## Where the steering wheel's hub sits (driver's side), and how far it leans back.
const STEERING_WHEEL_AT := Vector3(-0.45, 1.52, -2.52)
const STEERING_WHEEL_TILT: float = -0.95
const STEERING_WHEEL_RADIUS: float = 0.19
## The doors and the tailgate, in Chefty's space, where you get in.
const CHEFTY_DRIVER_DOOR := Vector3(-1.6, 0.0, -2.0)
const CHEFTY_SHOTGUN_DOOR := Vector3(1.6, 0.0, -2.0)
const CHEFTY_TAILGATE := Vector3(0.0, 0.0, 3.4)

static var _cache: Dictionary = {}


## Chefty: a rounded cab-over cab up front and an open bed behind it. opts
## (critic C21, one signature for every truck): color, decal (shops' livery, ""
## for none), dents (0..3, driving C3), interior (an open cab with a bench, a dash
## and a SteeringWheel node, for the drivable Chefty). A plain Color still works.
## Every option is in the cache key.
static func build_truck(parent: Node3D, opts: Variant = {}) -> Node3D:
	var options: Dictionary = {"color": opts} if opts is Color else (opts as Dictionary if opts is Dictionary else {})
	var color: Color = options.get("color", Color(0.75, 0.22, 0.15))
	var interior := bool(options.get("interior", false))
	var look := _root(parent, "TruckLook")
	var key := "truck|%s|%s|%d|%s" % [color.to_html(), str(options.get("decal", "")), int(options.get("dents", 0)), interior]
	if not _cache.has(key):
		_cache[key] = _truck_mesh(color, interior)
	look.add_child(_Stylized.instance(_cache[key], PAINT))
	if interior:
		_steering_wheel(look)
	# Solid: you bump into it, and thrown bags land in the bed.
	_solid(look, [
		[Vector3(0.0, 0.65, -0.1), Vector3(2.3, 0.8, 5.6)],
		[Vector3(0.0, 1.75, -2.0), Vector3(2.3, 1.5, 1.5)],
		[Vector3(-1.1, 1.35, 0.72), Vector3(0.16, 0.6, 3.9)],
		[Vector3(1.1, 1.35, 0.72), Vector3(0.16, 0.6, 3.9)],
		[Vector3(0.0, 1.35, 2.66), Vector3(2.3, 0.6, 0.16)],
	])
	# A water tank strapped in the bed, by the cab: free water for the hose.
	var tank := _YardModels.node("water_tank", Color.WHITE, Vector3.ONE, {"roughness": 0.5, "specular": 0.3})
	look.add_child(tank)
	tank.position = Vector3(-0.55, 1.05, -0.75)
	_WaterSources.make(look, "chefty", Vector3(-0.55, 1.2, -0.3))
	for side: float in [-1.0, 1.0]:
		_LowPoly.text_sign(look, "Chefty", Vector3(side * 1.17, 1.55, -1.95), 64, TRIM, side * PI * 0.5)
	_LowPoly.text_sign(look, "Chefty", Vector3(0.0, 1.32, 2.68), 56, TRIM)
	_lights(look, -2.97, 1.12, 2.66)
	return look


## The NICE BOYS' van, the Courtesy Shuttle (props/nice_van.gd): a "VanLook" with
## its livery, rolling wheels, the five collision boxes, and an open right side.
## color is the body paint (VAN_PAINT); the lavender band is always theirs.
static func build_van(parent: Node3D, color: Color = VAN_PAINT) -> Node3D:
	return _NiceVan.build(parent, color)


static func _truck_mesh(color: Color, interior: bool = false) -> ArrayMesh:
	var kit := _MeshKit.new()
	var dark := color.darkened(0.25)
	# Frame and lower body; the bed floor sits at y 1.0 under the riders.
	kit.rbox(Vector3(0.0, 0.72, -0.1), Vector3(1.12, 0.3, 2.75), color, 6.0)
	kit.rbox(Vector3(0.0, 0.42, 0.0), Vector3(0.9, 0.14, 2.5), GRILLE, 6.0)
	if interior:
		_open_cab(kit, color, dark)
	else:
		# Cab-over cab with a short rounded nose.
		kit.rbox(Vector3(0.0, 1.72, -2.0), Vector3(1.12, 0.72, 0.74), color, 5.0)
		# Glass: windshield and side windows, set into the cab.
		kit.rbox(Vector3(0.0, 2.04, -2.68), Vector3(0.98, 0.32, 0.08), GLASS, 6.0, {"shade": false})
		for side: float in [-1.0, 1.0]:
			kit.rbox(Vector3(side * 1.1, 2.04, -1.95), Vector3(0.05, 0.3, 0.5), GLASS, 6.0, {"shade": false})
	kit.rbox(Vector3(0.0, 1.12, -2.7), Vector3(1.1, 0.24, 0.22), color, 4.0)
	for side: float in [-1.0, 1.0]:
		# A door handle.
		kit.rbox(Vector3(side * 1.13, 1.62, -1.62), Vector3(0.025, 0.03, 0.09), CHROME, 4.0)
		# Mirrors on stalks.
		kit.rbox(Vector3(side * 1.28, 2.0, -2.45), Vector3(0.18, 0.025, 0.025), GRILLE, 4.0)
		kit.rbox(Vector3(side * 1.44, 2.0, -2.4), Vector3(0.05, 0.16, 0.1), GRILLE, 4.0)
		# Bed walls with a rolled top rail.
		kit.rbox(Vector3(side * 1.08, 1.28, 0.72), Vector3(0.07, 0.3, 1.98), color, 6.0)
		kit.rbox(Vector3(side * 1.08, 1.6, 0.72), Vector3(0.09, 0.04, 2.0), dark, 4.0)
		# Wheel arches and wheels.
		for z: float in [-1.85, 1.85]:
			kit.rbox(Vector3(side * 1.1, 0.95, z), Vector3(0.16, 0.2, 0.62), dark, 4.0)
			kit.wheel(Vector3(side * 1.08, 0.46, z), 0.46, 0.38, TIRE, CHROME)
	# The bed floor: dark planks the riders stand on.
	for index: int in 5:
		kit.rbox(Vector3(-0.8 + float(index) * 0.4, 1.035, 0.72), Vector3(0.19, 0.02, 1.95), Color(0.42, 0.3, 0.22), 8.0)
	kit.rbox(Vector3(0.0, 1.28, 2.66), Vector3(1.12, 0.3, 0.07), color, 6.0)
	kit.rbox(Vector3(0.0, 1.6, 2.66), Vector3(1.14, 0.04, 0.09), dark, 4.0)
	kit.rbox(Vector3(0.0, 1.32, -1.24), Vector3(1.1, 0.3, 0.06), dark, 6.0)
	# Grille and chrome bumpers.
	kit.rbox(Vector3(0.0, 1.12, -2.93), Vector3(0.62, 0.17, 0.03), GRILLE, 6.0, {"shade": false})
	for index: int in 3:
		kit.rbox(Vector3(0.0, 1.02 + float(index) * 0.1, -2.96), Vector3(0.58, 0.012, 0.012), CHROME, 4.0)
	kit.rbox(Vector3(0.0, 0.74, -3.0), Vector3(1.2, 0.12, 0.12), CHROME, 4.0)
	kit.rbox(Vector3(0.0, 0.74, 2.78), Vector3(1.18, 0.11, 0.1), CHROME, 4.0)
	# A roof light bar, just for the silhouette.
	kit.rbox(Vector3(0.0, 2.47, -2.0), Vector3(0.5, 0.05, 0.14), dark, 4.0)
	return kit.commit()


## The drivable Chefty's cab: open windows (no glass, so you can see who's
## driving), a roof on four pillars, door panels, a dash and a bench seat. The
## cab spans the old closed cab's box (y 1.0 to 2.44, z -2.74 to -1.26).
static func _open_cab(kit: RefCounted, color: Color, dark: Color) -> void:
	var seat := Color(0.55, 0.36, 0.22)
	# The back wall behind the bench, the roof, and the four pillars.
	kit.call("rbox", Vector3(0.0, 1.72, -1.31), Vector3(1.12, 0.72, 0.05), color, 5.0)
	kit.call("rbox", Vector3(0.0, 2.38, -2.0), Vector3(1.14, 0.07, 0.76), color, 5.0)
	for side: float in [-1.0, 1.0]:
		kit.call("rbox", Vector3(side * 1.06, 1.98, -2.66), Vector3(0.06, 0.36, 0.06), color, 4.0)
		kit.call("rbox", Vector3(side * 1.06, 1.98, -1.36), Vector3(0.06, 0.36, 0.06), color, 4.0)
		# The door panels up to the window line.
		kit.call("rbox", Vector3(side * 1.08, 1.3, -2.0), Vector3(0.05, 0.3, 0.7), color, 5.0)
		# A little rear window in the back wall's upper corners.
		kit.call("rbox", Vector3(side * 0.55, 2.0, -1.255), Vector3(0.32, 0.16, 0.012), GLASS, 6.0, {"shade": false})
	# The dash, with a glovebox line and two round gauges.
	kit.call("rbox", Vector3(0.0, 1.42, -2.58), Vector3(1.04, 0.18, 0.12), dark, 5.0)
	kit.call("rbox", Vector3(0.45, 1.36, -2.455), Vector3(0.22, 0.06, 0.008), GRILLE, 4.0, {"shade": false})
	for x: float in [-0.56, -0.34]:
		kit.call("rbox", Vector3(x, 1.52, -2.455), Vector3(0.06, 0.06, 0.008), TRIM, 6.0, {"shade": false})
	# The bench: a cushion and a back.
	kit.call("rbox", Vector3(0.0, 1.12, -1.78), Vector3(0.95, 0.1, 0.3), seat, 6.0)
	kit.call("rbox", Vector3(0.0, 1.48, -1.44), Vector3(0.95, 0.3, 0.08), seat, 6.0)
	# The column the wheel sits on.
	kit.call("rbox", STEERING_WHEEL_AT + Vector3(0.0, -0.1, -0.1), Vector3(0.035, 0.035, 0.14), GRILLE, 4.0)


## The steering wheel, its own node so it turns with the driver's steering
## (chefty_drive.gd): a pivot leaned back toward the driver; spin it about its Z.
static func _steering_wheel(look: Node3D) -> void:
	var key := "steering_wheel"
	if not _cache.has(key):
		var kit := _MeshKit.new()
		var ring := PackedVector3Array()
		var radii := PackedFloat32Array()
		for index: int in 17:
			var angle := TAU * float(index) / 16.0
			ring.append(Vector3(cos(angle), sin(angle), 0.0) * STEERING_WHEEL_RADIUS)
			radii.append(0.022)
		kit.tube(ring, radii, GRILLE, 6, {"jitter": 0.0, "cap": false})
		# Three spokes and a hub, so you can see it turn.
		for spoke: int in 3:
			var angle := PI * 0.5 + TAU * float(spoke) / 3.0
			kit.tube(PackedVector3Array([Vector3.ZERO, Vector3(cos(angle), sin(angle), 0.0) * STEERING_WHEEL_RADIUS]), PackedFloat32Array([0.016, 0.014]), CHROME, 5, {"jitter": 0.0})
		kit.rbox(Vector3.ZERO, Vector3(0.045, 0.045, 0.025), Color(0.85, 0.2, 0.15), 6.0)
		_cache[key] = kit.commit()
	var pivot := Node3D.new()
	pivot.name = "SteeringWheel"
	pivot.position = STEERING_WHEEL_AT
	pivot.rotation = Vector3(STEERING_WHEEL_TILT, 0.0, 0.0)
	look.add_child(pivot)
	pivot.add_child(_Stylized.instance(_cache[key], PAINT))


## Turn a truck's steering wheel to steer (-1 full left .. 1 full right).
static func set_steering(look: Node3D, steer: float) -> void:
	var wheel := look.get_node_or_null("SteeringWheel") as Node3D if look != null else null
	if wheel != null:
		wheel.rotation = Vector3(STEERING_WHEEL_TILT, 0.0, -steer * Constants.CHEFTY_WHEEL_TURN)


## Where the driver's hands go on the wheel (world space): [right, left].
static func wheel_grips(look: Node3D) -> Array[Vector3]:
	var wheel := look.get_node_or_null("SteeringWheel") as Node3D if look != null else null
	if wheel == null:
		return [Vector3.INF, Vector3.INF]
	var r := STEERING_WHEEL_RADIUS
	return [wheel.global_transform * Vector3(r * 0.94, r * 0.3, 0.0), wheel.global_transform * Vector3(-r * 0.94, r * 0.3, 0.0)]


## Collision boxes ([center, size] each) that move with the vehicle.
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


static func _root(parent: Node3D, look_name: String) -> Node3D:
	var old := parent.get_node_or_null(look_name)
	if old != null:
		old.free()
	var look := Node3D.new()
	look.name = look_name
	parent.add_child(look)
	return look


## Headlights glow warm at the front (front_z), taillights red at the back.
static func _lights(look: Node3D, front_z: float, height: float, back_z: float) -> void:
	for side: float in [-1.0, 1.0]:
		_LowPoly.glow(look, Vector3(0.3, 0.2, 0.05), Vector3(side * 0.85, height, front_z), Color(1.0, 0.95, 0.75), 2.5)
		_LowPoly.glow(look, Vector3(0.18, 0.26, 0.05), Vector3(side * 0.95, 1.2, back_z + 0.08), Color(0.9, 0.12, 0.08), 1.5)
