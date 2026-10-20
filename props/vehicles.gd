extends RefCounted

## Authority: local, cosmetic. Looks for the rides in net/components/ride.gd,
## built with props/mesh_kit.gd as soft, rounded toy vehicles. Both face -Z.
## Seats sit two across at bed height (y 1.0) from z -1.2 back, so riders are
## always visible: Chefty is a cab-over truck with an open bed, and the van has
## its right side cut away so the captured players can be counted at a glance
## (docs/ART.md). Chefty carries the Chefty logo (DEC-006). The van is the
## fictional crew's and has no lettering or insignia until the crew is designed
## (OQ-012).

const _LowPoly = preload("res://props/low_poly.gd")
const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const GLASS := Color(0.17, 0.22, 0.28)
const TIRE := Color(0.11, 0.11, 0.12)
const CHROME := Color(0.86, 0.86, 0.84)
const TRIM := Color(0.92, 0.9, 0.86)
const GRILLE := Color(0.14, 0.14, 0.15)
const PAINT := {"roughness": 0.55, "specular": 0.25}

static var _cache: Dictionary = {}


## Chefty: a rounded cab-over cab up front and an open bed behind it.
static func build_truck(parent: Node3D, color: Color) -> Node3D:
	var look := _root(parent, "TruckLook")
	var key := "truck|%s" % color.to_html()
	if not _cache.has(key):
		_cache[key] = _truck_mesh(color)
	look.add_child(_Stylized.instance(_cache[key], PAINT))
	for side: float in [-1.0, 1.0]:
		_LowPoly.text_sign(look, "Chefty", Vector3(side * 1.17, 1.55, -1.95), 64, TRIM, side * PI * 0.5)
	_LowPoly.text_sign(look, "Chefty", Vector3(0.0, 1.32, 2.68), 56, TRIM)
	_lights(look, -2.97, 1.12, 2.66)
	return look


## The crew van: a long rounded body with a roof, a solid left side, and an
## open right side.
static func build_van(parent: Node3D, color: Color) -> Node3D:
	var look := _root(parent, "VanLook")
	var key := "van|%s" % color.to_html()
	if not _cache.has(key):
		_cache[key] = _van_mesh(color)
	look.add_child(_Stylized.instance(_cache[key], PAINT))
	_lights(look, -3.42, 1.2, 3.02)
	return look


static func _truck_mesh(color: Color) -> ArrayMesh:
	var kit := _MeshKit.new()
	var dark := color.darkened(0.25)
	# Frame and lower body; the bed floor sits at y 1.0 under the riders.
	kit.rbox(Vector3(0.0, 0.72, -0.1), Vector3(1.12, 0.3, 2.75), color, 6.0)
	kit.rbox(Vector3(0.0, 0.42, 0.0), Vector3(0.9, 0.14, 2.5), GRILLE, 6.0)
	# Cab-over cab with a short rounded nose.
	kit.rbox(Vector3(0.0, 1.72, -2.0), Vector3(1.12, 0.72, 0.74), color, 5.0)
	kit.rbox(Vector3(0.0, 1.12, -2.7), Vector3(1.1, 0.24, 0.22), color, 4.0)
	# Glass: windshield and side windows, set into the cab.
	kit.rbox(Vector3(0.0, 2.04, -2.68), Vector3(0.98, 0.32, 0.08), GLASS, 6.0, {"shade": false})
	for side: float in [-1.0, 1.0]:
		kit.rbox(Vector3(side * 1.1, 2.04, -1.95), Vector3(0.05, 0.3, 0.5), GLASS, 6.0, {"shade": false})
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


static func _van_mesh(color: Color) -> ArrayMesh:
	var kit := _MeshKit.new()
	var dark := color.darkened(0.3)
	kit.rbox(Vector3(0.0, 0.72, 0.0), Vector3(1.12, 0.3, 3.15), color, 6.0)
	kit.rbox(Vector3(0.0, 0.42, 0.0), Vector3(0.9, 0.14, 2.9), GRILLE, 6.0)
	kit.rbox(Vector3(0.0, 1.9, -2.55), Vector3(1.12, 0.9, 0.7), color, 5.0)
	kit.rbox(Vector3(0.0, 1.15, -3.2), Vector3(1.1, 0.26, 0.2), color, 4.0)
	kit.rbox(Vector3(0.0, 2.3, -3.2), Vector3(0.98, 0.35, 0.07), GLASS, 6.0, {"shade": false})
	kit.rbox(Vector3(0.0, 3.0, 0.5), Vector3(1.18, 0.09, 2.6), color, 6.0)
	kit.rbox(Vector3(-1.12, 1.95, 0.5), Vector3(0.07, 1.0, 2.6), color, 6.0)
	kit.rbox(Vector3(0.0, 1.95, 3.0), Vector3(1.12, 1.0, 0.07), color, 6.0)
	for z: float in [-1.85, 2.9]:
		kit.rbox(Vector3(1.12, 1.95, z), Vector3(0.08, 1.0, 0.08), dark, 4.0)
	# One amber stripe so it reads as a vehicle from far away, not as any agency's livery.
	kit.rbox(Vector3(-1.2, 1.6, 0.5), Vector3(0.015, 0.11, 2.5), Color(0.95, 0.62, 0.15), 6.0, {"shade": false})
	for side: float in [-1.0, 1.0]:
		kit.rbox(Vector3(side * 1.1, 2.3, -2.5), Vector3(0.05, 0.3, 0.45), GLASS, 6.0, {"shade": false})
		for z: float in [-2.1, 2.1]:
			kit.rbox(Vector3(side * 1.1, 0.95, z), Vector3(0.16, 0.2, 0.62), dark, 4.0)
			kit.wheel(Vector3(side * 1.08, 0.46, z), 0.46, 0.38, TIRE, CHROME.darkened(0.2))
	kit.rbox(Vector3(0.0, 1.15, -3.42), Vector3(0.62, 0.17, 0.03), GRILLE, 6.0, {"shade": false})
	kit.rbox(Vector3(0.0, 0.74, -3.45), Vector3(1.2, 0.12, 0.1), GRILLE, 4.0)
	kit.rbox(Vector3(0.0, 0.74, 3.15), Vector3(1.18, 0.11, 0.1), GRILLE, 4.0)
	return kit.commit()


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
