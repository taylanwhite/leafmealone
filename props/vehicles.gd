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
	# The logos are named so dents can knock letters off them (set_dents).
	for side: float in [-1.0, 1.0]:
		var logo := _LowPoly.text_sign(look, "Chefty", Vector3(side * 1.17, 1.55, -1.95), 64, TRIM, side * PI * 0.5)
		logo.name = "LogoLeft" if side < 0.0 else "LogoRight"
	var tail := _LowPoly.text_sign(look, "Chefty", Vector3(0.0, 1.32, 2.68), 56, TRIM)
	tail.name = "LogoTail"
	_front_bumper(look)
	_lights(look, -2.97, 1.12, 2.66)
	if int(options.get("dents", 0)) > 0:
		set_dents(look, int(options.get("dents", 0)))
	return look


## The chrome front bumper, its own node hinged at its left end, so a dent can
## let its right end droop (set_dents).
static func _front_bumper(look: Node3D) -> void:
	if not _cache.has("front_bumper"):
		var kit := _MeshKit.new()
		kit.rbox(Vector3(BUMPER_HINGE_X_OFFSET, 0.0, 0.0), Vector3(1.2, 0.12, 0.12), CHROME, 4.0)
		_cache["front_bumper"] = kit.commit()
	var hinge := Node3D.new()
	hinge.name = "FrontBumper"
	hinge.position = Vector3(-BUMPER_HINGE_X_OFFSET, 0.74, -3.0)
	look.add_child(hinge)
	hinge.add_child(_Stylized.instance(_cache["front_bumper"], PAINT))


## Chefty's dents (0..Constants.CHEFTY_MAX_DENTS), on every peer from the host's
## count (driving chunk C3, docs/GAME.md "Crash comedy"): each dent knocks a
## letter off every logo (Chefty, Cheft, Chef, Che), the first lets the front
## bumper's right end droop and crumples the nose, the second loses the front
## right hubcap (chefty_drive.gd rolls one away), the third crumples a door. 0
## puts it all back (Marty's Body Shop).
static func set_dents(look: Node3D, dents: int) -> void:
	if look == null:
		return
	dents = clampi(dents, 0, Constants.CHEFTY_MAX_DENTS)
	for logo_name: String in ["LogoLeft", "LogoRight", "LogoTail"]:
		var logo := look.get_node_or_null(logo_name) as Label3D
		if logo != null:
			logo.text = "Chefty".left(6 - dents)
	var bumper := look.get_node_or_null("FrontBumper") as Node3D
	if bumper != null:
		bumper.rotation = Vector3(0.0, 0.0, -Constants.CHEFTY_DENT_BUMPER_DROOP[dents])
	var old := look.get_node_or_null("Dents")
	if old != null:
		old.free()
	if dents <= 0:
		return
	var key := "dents_%d" % dents
	if not _cache.has(key):
		_cache[key] = _dents_mesh(dents)
	var marks := _Stylized.instance(_cache[key], PAINT)
	marks.name = "Dents"
	look.add_child(marks)


## Where the front right wheel's hubcap was (Chefty's own space), its outward axis +X.
const HUBCAP_AT := Vector3(1.28, 0.46, -1.85)
const HUBCAP_RADIUS: float = 0.26
## The front bumper's hinge sits this far in from its left end's middle.
const BUMPER_HINGE_X_OFFSET: float = 1.15


## The dents' marks, cumulative: a crumpled nose; the bare hub where the
## hubcap was; a caved-in shotgun door.
static func _dents_mesh(dents: int) -> ArrayMesh:
	var kit := _MeshKit.new()
	var crease := Color(0.75, 0.22, 0.15).darkened(0.45)
	# The nose, pushed in at the right headlight: dark folds in the paint.
	kit.blob(Vector3(0.62, 1.1, -2.93), Vector3(0.22, 0.12, 0.04), crease, {"detail": 1, "lumps": 0.45, "seed": 3, "flat": false})
	kit.blob(Vector3(0.4, 1.22, -2.92), Vector3(0.12, 0.06, 0.03), crease.darkened(0.2), {"detail": 1, "lumps": 0.5, "seed": 5, "flat": false})
	if dents >= 2:
		# The hubcap's gone: a dull steel hub and its lug nuts.
		kit.tube(PackedVector3Array([HUBCAP_AT - Vector3(0.012, 0.0, 0.0), HUBCAP_AT + Vector3(0.012, 0.0, 0.0)]), PackedFloat32Array([HUBCAP_RADIUS, HUBCAP_RADIUS]), Color(0.27, 0.27, 0.29), 14, {"jitter": 0.0, "cap": true, "cap_start": true})
		for nut: int in 5:
			var angle := TAU * float(nut) / 5.0
			kit.blob(HUBCAP_AT + Vector3(0.02, sin(angle) * 0.1, cos(angle) * 0.1), Vector3(0.018, 0.022, 0.022), Color(0.6, 0.6, 0.62), {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0})
	if dents >= 3:
		# The shotgun door, caved in.
		kit.blob(Vector3(1.13, 1.32, -1.95), Vector3(0.03, 0.2, 0.3), crease, {"detail": 1, "lumps": 0.5, "seed": 9, "flat": false})
		kit.blob(Vector3(1.12, 1.18, -1.72), Vector3(0.025, 0.08, 0.14), crease.darkened(0.2), {"detail": 1, "lumps": 0.5, "seed": 11, "flat": false})
	return kit.commit()


## The hubcap that rolls off (chefty_drive.gd): a chrome disc, its axis along X.
static func hubcap_mesh() -> ArrayMesh:
	if not _cache.has("hubcap"):
		var kit := _MeshKit.new()
		kit.tube(PackedVector3Array([Vector3(-0.025, 0.0, 0.0), Vector3(0.0, 0.0, 0.0), Vector3(0.025, 0.0, 0.0)]), PackedFloat32Array([HUBCAP_RADIUS, HUBCAP_RADIUS, HUBCAP_RADIUS * 0.6]), CHROME, 16, {"jitter": 0.0, "cap": true, "cap_start": true})
		kit.tube(PackedVector3Array([Vector3(0.02, 0.0, 0.0), Vector3(0.035, 0.0, 0.0)]), PackedFloat32Array([HUBCAP_RADIUS * 0.25, HUBCAP_RADIUS * 0.2]), CHROME.darkened(0.3), 10, {"jitter": 0.0, "cap": true, "cap_start": true})
		_cache["hubcap"] = kit.commit()
	return _cache["hubcap"]


## Chefty's chrome, for the pieces chefty_drive.gd draws on its own.
static func stylized(mesh: Mesh) -> MeshInstance3D:
	return _Stylized.instance(mesh, PAINT)


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
	# (The front bumper is its own node: _front_bumper.)
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


# ---- Lunch Money (shops chunk 6): Dot's food truck

## The food truck's box: mustard yellow with a red skirt, the awning's stripes,
## its stainless counter, and the kitchen's steel inside.
const FOOD_BOX := Color(0.98, 0.76, 0.24)
const FOOD_SKIRT := Color(0.8, 0.2, 0.14)
const FOOD_STRIPE := Color(0.96, 0.95, 0.9)
const FOOD_STEEL := Color(0.66, 0.68, 0.7)
## The serving hatch on the box's +X side, in the truck's own space: z from x to
## y, and up from FOOD_HATCH_Y.x to FOOD_HATCH_Y.y. The awning hangs from its top.
const FOOD_HATCH_Z := Vector2(-0.75, 0.85)
const FOOD_HATCH_Y := Vector2(1.18, 2.3)
## The box's outside: half its width, its floor and roof, its front and back.
const FOOD_BOX_HALF_X: float = 1.15
const FOOD_BOX_Y := Vector2(0.85, 2.85)
const FOOD_BOX_Z := Vector2(-1.28, 2.15)


## Lunch Money (docs/GAME.md "Shops"): a converted Chefty, cab-over and all, 4.3 m
## nose to tail, facing -Z, with a box on the back whose +X side opens into a
## serving hatch under a striped awning. A giant hot dog rides on the roof. The
## Chefty logo stays on the grille and the doors (DEC-006: every truck is a
## Chefty), "LUNCH MONEY" is painted on both sides, and the menu board by the
## hatch lists the real prices (Catalog.price). The awning is its own node,
## "Hatch", hinged at the hatch's top: rotation.z 0 is shut over the hatch,
## Constants.FOOD_TRUCK_HATCH_OPEN is propped open (levels/dressing/shop_sites.gd
## swings it with the opening hours). Solid as one box; the awning isn't.
static func build_food_truck(parent: Node3D) -> Node3D:
	var look := _root(parent, "FoodTruckLook")
	var key := "food_truck"
	if not _cache.has(key):
		_cache[key] = _food_truck_mesh()
	look.add_child(_Stylized.instance(_cache[key], PAINT))
	# The awning, shut by default.
	var hatch := Node3D.new()
	hatch.name = "Hatch"
	hatch.position = Vector3(FOOD_BOX_HALF_X + 0.02, FOOD_HATCH_Y.y, (FOOD_HATCH_Z.x + FOOD_HATCH_Z.y) * 0.5)
	look.add_child(hatch)
	if not _cache.has("food_truck_awning"):
		_cache["food_truck_awning"] = _awning_mesh()
	hatch.add_child(_Stylized.instance(_cache["food_truck_awning"], {"roughness": 0.9, "specular": 0.1}))
	# The giant hot dog on the roof, on two little posts.
	if not _cache.has("food_truck_dog"):
		var kit := _MeshKit.new()
		preload("res://props/shop_models.gd").build_into(kit, "hot_dog")
		_cache["food_truck_dog"] = kit.commit()
	var dog := _Stylized.instance(_cache["food_truck_dog"], {"roughness": 0.6, "specular": 0.3})
	dog.name = "RoofDog"
	dog.scale = Vector3.ONE * 8.5
	dog.position = Vector3(0.0, FOOD_BOX_Y.y + 0.38, 0.5)
	look.add_child(dog)
	# Words: LUNCH MONEY on both sides, Chefty on the doors and the grille.
	var painted := str(preload("res://ui/strings.gd").SHOP_UI["sign_lunch_money"])
	_LowPoly.text_sign(look, painted, Vector3(FOOD_BOX_HALF_X + 0.03, 2.58, 0.45), 44, FOOD_SKIRT, PI * 0.5)
	_LowPoly.text_sign(look, painted, Vector3(-FOOD_BOX_HALF_X - 0.03, 1.95, 0.45), 84, FOOD_SKIRT, -PI * 0.5)
	for side: float in [-1.0, 1.0]:
		_LowPoly.text_sign(look, "Chefty", Vector3(side * 1.115, 1.55, -1.7), 40, TRIM, side * PI * 0.5)
	_LowPoly.text_sign(look, "Chefty", Vector3(0.0, 1.32, -2.14), 30, TRIM, PI)
	_menu_board(look)
	_lights(look, -2.13, 1.05, 2.1)
	_solid(look, [
		[Vector3(0.0, 1.6, (FOOD_BOX_Z.x + FOOD_BOX_Z.y) * 0.5), Vector3(FOOD_BOX_HALF_X * 2.0, 2.5, FOOD_BOX_Z.y - FOOD_BOX_Z.x)],
		[Vector3(0.0, 1.45, -1.7), Vector3(2.24, 1.9, 0.82)],
	])
	return look


static func _food_truck_mesh() -> ArrayMesh:
	var kit := _MeshKit.new()
	var red := Color(0.75, 0.22, 0.15)
	var dark := red.darkened(0.25)
	var hx := FOOD_BOX_HALF_X
	var wall := 0.05
	# Frame under it all.
	kit.rbox(Vector3(0.0, 0.62, 0.42), Vector3(1.02, 0.18, 1.85), GRILLE, 6.0, {"detail": 1})
	# The Chefty cab up front (red, as it left the factory).
	kit.rbox(Vector3(0.0, 1.5, -1.7), Vector3(1.1, 0.78, 0.42), red, 6.0, {"detail": 2})
	kit.rbox(Vector3(0.0, 1.98, -2.1), Vector3(0.94, 0.28, 0.04), GLASS, 6.0, {"detail": 1, "shade": false})
	for side: float in [-1.0, 1.0]:
		kit.rbox(Vector3(side * 1.1, 1.98, -1.8), Vector3(0.04, 0.26, 0.26), GLASS, 6.0, {"detail": 1, "shade": false})
		kit.rbox(Vector3(side * 1.13, 1.4, -1.5), Vector3(0.025, 0.03, 0.09), CHROME, 4.0, {"detail": 1})
		kit.rbox(Vector3(side * 1.28, 1.95, -2.0), Vector3(0.16, 0.025, 0.025), GRILLE, 4.0, {"detail": 1})
		kit.rbox(Vector3(side * 1.42, 1.95, -1.96), Vector3(0.05, 0.15, 0.1), GRILLE, 4.0, {"detail": 1})
		for z: float in [-1.55, 1.45]:
			kit.rbox(Vector3(side * 1.08, 0.92, z), Vector3(0.12, 0.18, 0.55), dark, 4.0, {"detail": 1})
			kit.wheel(Vector3(side * 1.04, 0.42, z), 0.42, 0.34, TIRE, CHROME)
	kit.rbox(Vector3(0.0, 1.05, -2.11), Vector3(0.58, 0.16, 0.03), GRILLE, 6.0, {"detail": 1, "shade": false})
	for index: int in 3:
		kit.rbox(Vector3(0.0, 0.95 + float(index) * 0.1, -2.14), Vector3(0.54, 0.012, 0.012), CHROME, 4.0, {"detail": 1})
	kit.rbox(Vector3(0.0, 0.66, -2.16), Vector3(1.14, 0.1, 0.08), CHROME, 4.0, {"detail": 1})
	kit.rbox(Vector3(0.0, 0.66, FOOD_BOX_Z.y + 0.06), Vector3(1.12, 0.09, 0.07), CHROME, 4.0, {"detail": 1})
	# The box: floor, roof, front and back, the -X wall, and the +X wall around the hatch.
	var box_y := (FOOD_BOX_Y.x + FOOD_BOX_Y.y) * 0.5
	var box_hy := (FOOD_BOX_Y.y - FOOD_BOX_Y.x) * 0.5
	var box_z := (FOOD_BOX_Z.x + FOOD_BOX_Z.y) * 0.5
	var box_hz := (FOOD_BOX_Z.y - FOOD_BOX_Z.x) * 0.5
	kit.rbox(Vector3(0.0, FOOD_BOX_Y.y - wall, box_z), Vector3(hx + 0.02, wall + 0.02, box_hz + 0.02), FOOD_BOX.lightened(0.1), 8.0, {"detail": 1})
	kit.rbox(Vector3(0.0, FOOD_BOX_Y.x + wall, box_z), Vector3(hx, wall, box_hz), FOOD_SKIRT, 8.0, {"detail": 1})
	for z: float in [FOOD_BOX_Z.x + wall, FOOD_BOX_Z.y - wall]:
		kit.rbox(Vector3(0.0, box_y, z), Vector3(hx, box_hy, wall), FOOD_BOX, 10.0, {"detail": 1})
	kit.rbox(Vector3(-hx + wall, box_y, box_z), Vector3(wall, box_hy, box_hz), FOOD_BOX, 10.0, {"detail": 1})
	var hz0 := FOOD_HATCH_Z.x
	var hz1 := FOOD_HATCH_Z.y
	# Under and over the hatch, and either side of it (they overlap a little at the seams).
	kit.rbox(Vector3(hx - wall, (FOOD_BOX_Y.x + FOOD_HATCH_Y.x) * 0.5, box_z), Vector3(wall, (FOOD_HATCH_Y.x - FOOD_BOX_Y.x) * 0.5 + 0.01, box_hz), FOOD_BOX, 10.0, {"detail": 1})
	kit.rbox(Vector3(hx - wall, (FOOD_HATCH_Y.y + FOOD_BOX_Y.y) * 0.5, box_z), Vector3(wall, (FOOD_BOX_Y.y - FOOD_HATCH_Y.y) * 0.5 + 0.01, box_hz), FOOD_BOX, 10.0, {"detail": 1})
	kit.rbox(Vector3(hx - wall, box_y, (FOOD_BOX_Z.x + hz0) * 0.5), Vector3(wall, box_hy, (hz0 - FOOD_BOX_Z.x) * 0.5 + 0.01), FOOD_BOX, 10.0, {"detail": 1})
	kit.rbox(Vector3(hx - wall, box_y, (hz1 + FOOD_BOX_Z.y) * 0.5), Vector3(wall, box_hy, (FOOD_BOX_Z.y - hz1) * 0.5 + 0.01), FOOD_BOX, 10.0, {"detail": 1})
	# A red skirt along the bottom of the box, both sides.
	for side: float in [-1.0, 1.0]:
		kit.rbox(Vector3(side * (hx + 0.005), FOOD_BOX_Y.x + 0.14, box_z), Vector3(0.012, 0.12, box_hz), FOOD_SKIRT, 6.0, {"detail": 1})
	# The stainless counter under the hatch, on two little brackets.
	kit.rbox(Vector3(hx + 0.12, FOOD_HATCH_Y.x + 0.02, (hz0 + hz1) * 0.5), Vector3(0.15, 0.022, (hz1 - hz0) * 0.5 + 0.02), FOOD_STEEL, 6.0, {"detail": 1})
	for z: float in [hz0 + 0.15, hz1 - 0.15]:
		kit.rbox(Vector3(hx + 0.07, FOOD_HATCH_Y.x - 0.08, z), Vector3(0.07, 0.07, 0.015), FOOD_STEEL.darkened(0.2), 4.0, {"detail": 1})
	# The kitchen inside: steel on the back wall, a griddle, a coffee urn, cups on a shelf.
	kit.rbox(Vector3(-hx + 0.12, 1.75, box_z), Vector3(0.012, 0.85, box_hz - 0.08), FOOD_STEEL, 8.0, {"detail": 1})
	kit.rbox(Vector3(-hx + 0.4, 1.12, 0.05), Vector3(0.28, 0.2, 0.9), FOOD_STEEL.darkened(0.15), 8.0, {"detail": 1})
	kit.rbox(Vector3(-hx + 0.4, 1.34, -0.3), Vector3(0.24, 0.02, 0.4), Color(0.12, 0.12, 0.13), 8.0, {"detail": 1})
	kit.tube(PackedVector3Array([Vector3(-hx + 0.4, 1.32, 0.55), Vector3(-hx + 0.4, 1.7, 0.55)]), PackedFloat32Array([0.12, 0.11]), FOOD_STEEL.lightened(0.15), 12, {"jitter": 0.0, "cap": true, "cap_start": true})
	kit.rbox(Vector3(-hx + 0.2, 2.15, 0.05), Vector3(0.1, 0.015, 0.8), FOOD_STEEL, 6.0, {"detail": 1})
	for index: int in 6:
		kit.tube(PackedVector3Array([Vector3(-hx + 0.2, 2.165, -0.6 + float(index) * 0.24), Vector3(-hx + 0.2, 2.27, -0.6 + float(index) * 0.24)]), PackedFloat32Array([0.03, 0.038]), Color(0.96, 0.95, 0.92), 8, {"jitter": 0.0, "cap": true, "cap_start": true})
	# A string of bulbs along the hatch's top edge, outside.
	for index: int in 8:
		var z := lerpf(hz0 + 0.05, hz1 - 0.05, float(index) / 7.0)
		kit.blob(Vector3(hx + 0.05, FOOD_HATCH_Y.y + 0.06, z), Vector3(0.025, 0.03, 0.025), Color(1.0, 0.93, 0.6), {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0, "shade": false})
	# The hot dog's two posts on the roof.
	for z: float in [0.1, 0.9]:
		kit.tube(PackedVector3Array([Vector3(0.0, FOOD_BOX_Y.y, z), Vector3(0.0, FOOD_BOX_Y.y + 0.3, z)]), PackedFloat32Array([0.035, 0.03]), FOOD_STEEL, 6, {"jitter": 0.0})
	return kit.commit()


## The awning, hinged at its top edge (the node's origin), hanging down over
## the hatch when shut: red and white stripes on the outside, a scalloped
## valance at the bottom edge.
static func _awning_mesh() -> ArrayMesh:
	var kit := _MeshKit.new()
	var length := FOOD_HATCH_Y.y - FOOD_HATCH_Y.x + 0.06
	var half_z := (FOOD_HATCH_Z.y - FOOD_HATCH_Z.x) * 0.5 + 0.08
	var stripes := 7
	for index: int in stripes:
		var z := -half_z + (float(index) + 0.5) * (half_z * 2.0 / float(stripes))
		kit.rbox(Vector3(0.02, -length * 0.5, z), Vector3(0.018, length * 0.5, half_z / float(stripes) + 0.002), FOOD_SKIRT if index % 2 == 0 else FOOD_STRIPE, 8.0, {"detail": 1})
	for index: int in stripes * 2:
		var z := -half_z + (float(index) + 0.5) * (half_z * 2.0 / float(stripes * 2))
		kit.blob(Vector3(0.03, -length - 0.02, z), Vector3(0.012, 0.05, half_z / float(stripes * 2)), FOOD_SKIRT if (index / 2) % 2 == 0 else FOOD_STRIPE, {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0})
	return kit.commit()


## The menu by the hatch: a chalkboard on the box with today's prices on it.
static func _menu_board(look: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "MenuBoard"
	holder.position = Vector3(FOOD_BOX_HALF_X + 0.02, 1.78, (FOOD_HATCH_Z.y + FOOD_BOX_Z.y) * 0.5)
	holder.rotation.y = PI * 0.5
	look.add_child(holder)
	var kit := _MeshKit.new()
	kit.rbox(Vector3(0.0, 0.0, 0.0), Vector3(0.5, 0.42, 0.015), Color(0.15, 0.19, 0.17), 8.0, {"detail": 1, "shade": false})
	kit.rbox(Vector3(0.0, 0.0, -0.008), Vector3(0.54, 0.46, 0.012), Color(0.55, 0.38, 0.22), 8.0, {"detail": 1})
	holder.add_child(_Stylized.instance(kit.commit(), {"roughness": 0.9, "specular": 0.05}))
	var strings := preload("res://ui/strings.gd")
	var lines := PackedStringArray()
	for item: String in Catalog.items_for("lunch_money", "menu"):
		if str(Catalog.item(item).get("kind", "")) == "snack":
			lines.append(str(strings.SHOP_UI["menu_line"]) % [strings.shop_item_name(item).to_upper(), Catalog.price(item)])
	var words := _LowPoly.text_sign(holder, "\n".join(lines), Vector3(0.0, 0.02, 0.02), 30, Color(0.96, 0.95, 0.88))
	words.name = "Menu"
	words.outline_size = 0
	words.pixel_size = 0.0055
	words.line_spacing = 6.0