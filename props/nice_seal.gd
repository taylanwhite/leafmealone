extends RefCounted

## Authority: local, cosmetic. The NICE BOYS' insignia, the Daisy Seal (docs/GAME.md,
## "2026-11-01, the cast"; docs/ART.md, "The NICE BOYS"): a six-petal white daisy
## with a yellow center and a little smile, on a scalloped lavender rosette with
## two ribbon tails. It reads as a "Certified Nice" sticker. It is never a shield,
## a star or a badge.
##
## Everything that shows the NICE BOYS uses this one seal: the chest patch and the
## visor (player/cartoon_body.gd), the van, the arrival beacon, posters and notices.
##
##   NiceSeal.add(kit, center, radius, facing)   # draws into an existing MeshKit
##   NiceSeal.node(radius, facing)               # a ready MeshInstance3D
##
## The seal is flat: stacked layers a hair apart, each facing `facing`, so it can
## sit on a surface like a sticker. `center` is where its back layer sits; nudge it
## a millimeter off the surface it is stuck to.

const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")

## Courtesy Lavender: the NICE BOYS' polos, visors and van band.
const LAVENDER := Color(0.74, 0.70, 0.93)
## The rosette is a deeper lavender, so the seal still reads on a lavender polo.
const ROSETTE := Color(0.5, 0.4, 0.84)
const RIBBON := Color(0.42, 0.33, 0.74)
const PETAL := Color(0.98, 0.98, 0.95)
const CENTER := Color(0.98, 0.82, 0.25)
const INK := Color(0.14, 0.09, 0.12)
## Scallops around the rosette's edge.
const SCALLOPS: int = 12
## Layer spacing: this share of the radius, kept between these, in meters.
const LAYER_SHARE: float = 0.02
const LAYER_MIN: float = 0.0012
const LAYER_MAX: float = 0.02


## Draws the seal into kit, centered at center, radius meters across the rosette
## (the ribbon tails hang a little below), its face toward facing. facing can be
## any direction; straight up or down puts the seal's top toward -Z. detail 0 is
## for small seals (about 100 triangles), 1 for big ones. two_sided draws the face
## on the back too, for a seal that hangs in the air.
static func add(kit: _MeshKit, center: Vector3, radius: float, facing: Vector3, detail: int = 0, two_sided: bool = false) -> void:
	var basis := _basis(facing)
	var layer := clampf(radius * LAYER_SHARE, LAYER_MIN, LAYER_MAX) / maxf(radius, 0.001)
	_face(kit, center, radius, basis, detail, layer)
	if two_sided:
		# The back: the same face mirrored through the seal's plane.
		var back := Basis(-basis.x, basis.y, -basis.z)
		_face(kit, center, radius, back, detail, layer)


## A MeshInstance3D of the seal, two-sided, drawn with the stylized material and
## kept out of the shared look. Its origin is the seal's center.
static func node(radius: float, facing: Vector3 = Vector3.FORWARD) -> MeshInstance3D:
	var kit := _MeshKit.new()
	add(kit, Vector3.ZERO, radius, facing, 0 if radius < 0.15 else 1, true)
	var view := _Stylized.instance(kit.commit(), {"roughness": 0.6, "specular": 0.25})
	view.name = "NiceSeal"
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.set_meta("keep_material", true)
	return view


## Right, up and face for a seal facing that way: a right-handed basis whose z is
## facing, so the seal's local +x is the viewer's right.
static func _basis(facing: Vector3) -> Basis:
	var z := facing.normalized() if facing.length() > 0.001 else Vector3.FORWARD
	var up := Vector3.UP if absf(z.y) < 0.95 else Vector3.FORWARD
	var x := up.cross(z).normalized()
	var y := z.cross(x).normalized()
	return Basis(x, y, z)


## One face of the seal. Local units are the radius; local z is out of the face.
static func _face(kit: _MeshKit, center: Vector3, radius: float, basis: Basis, detail: int, layer: float) -> void:
	var to_world := func(local: Vector3) -> Vector3: return center + basis * (local * radius)
	var normal := basis.z
	var ring := 24 if detail <= 0 else 48
	var petal_steps := 8 if detail <= 0 else 12
	# Ribbon tails, behind everything, hanging down from under the rosette.
	for side: float in [-1.0, 1.0]:
		var top := Vector2(side * 0.12, -0.55)
		var tip := Vector2(side * 0.42, -1.28)
		var along := (tip - top).normalized()
		var across := Vector2(-along.y, along.x) * 0.15
		var points := [top - across, top + across, tip + across, tip - along * 0.16, tip - across]
		var flat: Array[Vector3] = []
		for point: Vector2 in points:
			flat.append(to_world.call(Vector3(point.x, point.y, 0.0)))
		var color := RIBBON
		_poly(kit, [flat[0], flat[1], flat[3]], normal, color)
		_poly(kit, [flat[1], flat[2], flat[3]], normal, color)
		_poly(kit, [flat[0], flat[3], flat[4]], normal, color)
	# The scalloped rosette.
	var rim: Array[Vector3] = []
	for step: int in ring:
		var angle := TAU * float(step) / float(ring)
		var reach := 0.8 + 0.2 * sqrt(absf(cos(angle * float(SCALLOPS) * 0.5)))
		rim.append(Vector3(cos(angle) * reach, sin(angle) * reach, layer))
	_fan(kit, to_world.call(Vector3(0.0, 0.0, layer)), rim, to_world, normal, ROSETTE)
	# A white stitched ring on the big seals.
	if detail > 0:
		for step: int in ring:
			var a := TAU * float(step) / float(ring)
			var b := TAU * float(step + 1) / float(ring)
			var z := layer * 1.5
			var inner_a := Vector3(cos(a) * 0.68, sin(a) * 0.68, z)
			var inner_b := Vector3(cos(b) * 0.68, sin(b) * 0.68, z)
			var outer_a := Vector3(cos(a) * 0.73, sin(a) * 0.73, z)
			var outer_b := Vector3(cos(b) * 0.73, sin(b) * 0.73, z)
			_quad(kit, to_world, inner_a, outer_a, outer_b, inner_b, normal, PETAL)
	# Six petals, one straight up.
	for petal: int in 6:
		var angle := PI * 0.5 + TAU * float(petal) / 6.0
		var out := Vector2(cos(angle), sin(angle))
		var side := Vector2(-out.y, out.x)
		var middle := out * 0.36
		var edge: Array[Vector3] = []
		for step: int in petal_steps:
			var t := TAU * float(step) / float(petal_steps)
			var at := middle + out * cos(t) * 0.27 + side * sin(t) * 0.14
			edge.append(Vector3(at.x, at.y, layer * 2.0))
		_fan(kit, to_world.call(Vector3(middle.x, middle.y, layer * 2.0)), edge, to_world, normal, PETAL)
	# The yellow center.
	var disc: Array[Vector3] = []
	for step: int in petal_steps:
		var t := TAU * float(step) / float(petal_steps)
		disc.append(Vector3(cos(t) * 0.2, sin(t) * 0.2, layer * 3.0))
	_fan(kit, to_world.call(Vector3(0.0, 0.0, layer * 3.0)), disc, to_world, normal, CENTER)
	# Its little smile and two dot eyes.
	var smile := 4
	for step: int in smile:
		var a := deg_to_rad(205.0 + 130.0 * float(step) / float(smile))
		var b := deg_to_rad(205.0 + 130.0 * float(step + 1) / float(smile))
		var z := layer * 4.0
		var inner_a := Vector3(cos(a) * 0.09, sin(a) * 0.09 + 0.02, z)
		var inner_b := Vector3(cos(b) * 0.09, sin(b) * 0.09 + 0.02, z)
		var outer_a := Vector3(cos(a) * 0.125, sin(a) * 0.125 + 0.02, z)
		var outer_b := Vector3(cos(b) * 0.125, sin(b) * 0.125 + 0.02, z)
		_quad(kit, to_world, inner_a, outer_a, outer_b, inner_b, normal, INK)
	for side: float in [-1.0, 1.0]:
		var z := layer * 4.0
		var eye := Vector3(side * 0.065, 0.06, z)
		var half := 0.025
		_quad(kit, to_world, eye + Vector3(-half, -half, 0.0), eye + Vector3(-half, half, 0.0), eye + Vector3(half, half, 0.0), eye + Vector3(half, -half, 0.0), normal, INK)


## A fan from middle round the edge points (local units), counterclockwise in the
## seal's plane, so clockwise seen from the front.
static func _fan(kit: _MeshKit, middle: Vector3, edge: Array[Vector3], to_world: Callable, normal: Vector3, color: Color) -> void:
	for step: int in edge.size():
		var a: Vector3 = to_world.call(edge[step])
		var b: Vector3 = to_world.call(edge[(step + 1) % edge.size()])
		_poly(kit, [middle, b, a], normal, color)


## A quad a, b, c, d in local units, counterclockwise in the seal's plane.
static func _quad(kit: _MeshKit, to_world: Callable, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color) -> void:
	var wa: Vector3 = to_world.call(a)
	var wb: Vector3 = to_world.call(b)
	var wc: Vector3 = to_world.call(c)
	var wd: Vector3 = to_world.call(d)
	_poly(kit, [wa, wb, wc], normal, color)
	_poly(kit, [wa, wc, wd], normal, color)


## A world-space triangle whose corners may wind either way: it is turned to face
## normal (clockwise seen from that side).
static func _poly(kit: _MeshKit, corners: Array, normal: Vector3, color: Color) -> void:
	var a: Vector3 = corners[0]
	var b: Vector3 = corners[1]
	var c: Vector3 = corners[2]
	# Clockwise from the front means (c - a) x (b - a) points along the normal.
	if (c - a).cross(b - a).dot(normal) >= 0.0:
		kit.triangle(a, b, c, normal, color)
	else:
		kit.triangle(a, c, b, normal, color)
