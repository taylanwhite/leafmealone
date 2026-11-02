extends RefCounted

## Authority: local, cosmetic. Shorthand shapes for the prop builders
## (props/street_props.gd, yard_extras.gd, estate_props.gd, season_props.gd), on top
## of props/mesh_kit.gd: posts, bars, slabs, soft boxes, balls, discs, rings,
## cheap wheels, and sagging lines. Everything is low detail on purpose: a prop
## stays under Constants.ART_PROP_MAX_TRIANGLES (2000), and a soft box at detail 1
## is 80 triangles where MeshKit's default (detail 3) is 1280.
## Colors are sRGB; alpha is set by the shape (sway: 0 rooted, 1 sways fully).

const _MeshKit = preload("res://props/mesh_kit.gd")

const STEEL := Color(0.62, 0.64, 0.66)
const DARK_STEEL := Color(0.3, 0.31, 0.33)
const TIRE := Color(0.11, 0.11, 0.12)
const CHROME := Color(0.86, 0.86, 0.84)
const GLASS := Color(0.2, 0.27, 0.34)
const WOOD := Color(0.6, 0.44, 0.29)
const OLD_WOOD := Color(0.55, 0.5, 0.43)
const STONE := Color(0.66, 0.64, 0.6)
const BRICK := Color(0.6, 0.32, 0.26)
const WHITE := Color(0.94, 0.94, 0.91)
const BLACK := Color(0.08, 0.08, 0.09)
const LEAF := Color(0.24, 0.46, 0.22)
const SOIL := Color(0.3, 0.22, 0.16)
const WATER := Color(0.36, 0.66, 0.82)
const SNOW := Color(0.94, 0.96, 1.0)
const STRAW := Color(0.86, 0.72, 0.38)


## color unless it is the "use the default" white every catalog call starts with.
static func tint(color: Color, fallback: Color) -> Color:
	return fallback if color.is_equal_approx(Color.WHITE) else color


## size unless it is the "use the default" Vector3.ONE; a zero or negative axis
## takes the default's.
static func dims(size: Vector3, fallback: Vector3) -> Vector3:
	if size.is_equal_approx(Vector3.ONE):
		return fallback
	return Vector3(size.x if size.x > 0.0 else fallback.x, size.y if size.y > 0.0 else fallback.y, size.z if size.z > 0.0 else fallback.z)


## A hard-edged box (12 triangles).
static func slab(kit: _MeshKit, center: Vector3, size: Vector3, color: Color, basis: Basis = Basis.IDENTITY, sway: float = 0.0) -> void:
	kit.box(center, size, color, basis, sway)


## A box with rounded edges (size is the full size). detail 1 is 80 triangles,
## 2 is 320.
static func soft(kit: _MeshKit, center: Vector3, size: Vector3, color: Color, roundness: float = 5.0, detail: int = 1, basis: Basis = Basis.IDENTITY, sway: float = 0.0) -> void:
	kit.rbox(center, size * 0.5, color, roundness, {"detail": detail, "basis": basis, "sway": sway})


## A straight round bar from a to b, capped at both ends.
static func bar(kit: _MeshKit, a: Vector3, b: Vector3, radius: float, color: Color, sides: int = 6, sway_a: float = 0.0, sway_b: float = 0.0) -> void:
	if a.distance_to(b) < 0.001:
		return
	kit.tube(PackedVector3Array([a, b]), PackedFloat32Array([radius, radius]), color, sides, {"jitter": 0.0, "cap": true, "cap_start": true, "sway_from": sway_a, "sway_to": sway_b})


## An upright post of height standing on base.
static func post(kit: _MeshKit, base: Vector3, height: float, radius: float, color: Color, sides: int = 6) -> void:
	bar(kit, base, base + Vector3(0.0, height, 0.0), radius, color, sides)


## A tapered upright: radius at the bottom, top_radius at the top.
static func taper(kit: _MeshKit, base: Vector3, height: float, radius: float, top_radius: float, color: Color, sides: int = 8) -> void:
	kit.tube(PackedVector3Array([base, base + Vector3(0.0, height, 0.0)]), PackedFloat32Array([radius, top_radius]), color, sides, {"jitter": 0.0, "cap": true, "cap_start": true})


## A tube through points with one radius (wire, hose, chain, rope).
static func path(kit: _MeshKit, points: PackedVector3Array, radius: float, color: Color, sides: int = 4, sway_from: float = 0.0, sway_to: float = 0.0) -> void:
	if points.size() < 2:
		return
	var radii := PackedFloat32Array()
	for _point: Vector3 in points:
		radii.append(radius)
	kit.tube(points, radii, color, sides, {"jitter": 0.0, "cap": true, "sway_from": sway_from, "sway_to": sway_to})


## A smooth ball (or ellipsoid with radii). detail 0 is 20 triangles, 1 is 80, 2 is 320.
static func ball(kit: _MeshKit, center: Vector3, radii: Vector3, color: Color, detail: int = 1, sway: float = 0.0) -> void:
	kit.blob(center, radii, color, {"detail": detail, "lumps": 0.0, "flat": false, "jitter": 0.0, "sway": sway})


## A lumpy ball: foliage, rocks, snow, laundry piles.
static func lump(kit: _MeshKit, center: Vector3, radii: Vector3, color: Color, seed_value: int, detail: int = 1, lumps: float = 0.22, sway: float = 0.0) -> void:
	kit.blob(center, radii, color, {"detail": detail, "lumps": lumps, "lump_scale": 2.2, "flat": true, "soft": 0.6, "jitter": 0.04, "seed": seed_value, "sway": sway, "outward": true})


## A flat round slab lying level, center at its middle.
static func disc(kit: _MeshKit, center: Vector3, radius: float, thickness: float, color: Color, sides: int = 12) -> void:
	bar(kit, center - Vector3(0.0, thickness * 0.5, 0.0), center + Vector3(0.0, thickness * 0.5, 0.0), radius, color, sides)


## A cone standing on base (top_radius > 0 makes a frustum).
static func cone(kit: _MeshKit, base: Vector3, radius: float, height: float, color: Color, sides: int = 8, top_radius: float = 0.0, sway: float = 0.0) -> void:
	kit.cone(base, radius, height, color, sides, {"lumps": 0.0, "top_radius": top_radius, "sway": sway})


## A ring (torus) around center, lying in the plane basis puts its local x and z
## in: radius to the middle of the tube, thickness the tube's radius.
static func ring(kit: _MeshKit, center: Vector3, radius: float, thickness: float, color: Color, sides: int = 12, tube_sides: int = 5, basis: Basis = Basis.IDENTITY) -> void:
	var points := PackedVector3Array()
	var radii := PackedFloat32Array()
	for step: int in sides + 1:
		var angle := TAU * float(step) / float(sides)
		points.append(center + basis * Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))
		radii.append(thickness)
	kit.tube(points, radii, color, tube_sides, {"jitter": 0.0, "cap": false})


## A cheap wheel lying along x at center: a tire and a hub (about 70 triangles).
static func wheel(kit: _MeshKit, center: Vector3, radius: float, width: float, tire: Color = TIRE, hub: Color = CHROME) -> void:
	var half := Vector3(width * 0.5, 0.0, 0.0)
	bar(kit, center - half, center + half, radius, tire, 10)
	bar(kit, center - half * 1.08, center + half * 1.08, radius * 0.55, hub, 8)


## Points along a line from a to b that sags by sag in the middle.
static func sag(a: Vector3, b: Vector3, amount: float, steps: int = 6) -> PackedVector3Array:
	var points := PackedVector3Array()
	for step: int in steps + 1:
		var t := float(step) / float(steps)
		points.append(a.lerp(b, t) - Vector3(0.0, amount * 4.0 * t * (1.0 - t), 0.0))
	return points


## A two-faced flat quad (seen from both sides), for flags, laundry, and thin
## sign faces: width by height standing on bottom_center, facing -Z (and +Z),
## turned by basis. The bottom corners carry sway_bottom and the top corners
## sway_top; hinge (0-1) scales the sway of the left edge (0 = pinned, for a flag
## on a pole).
static func card(kit: _MeshKit, bottom_center: Vector3, width: float, height: float, color: Color, basis: Basis = Basis.IDENTITY, sway_bottom: float = 0.0, sway_top: float = 0.0, hinge: float = 1.0) -> void:
	var half := width * 0.5
	var corners: Array[Vector3] = [
		bottom_center + basis * Vector3(-half, 0.0, 0.0), bottom_center + basis * Vector3(half, 0.0, 0.0),
		bottom_center + basis * Vector3(half, height, 0.0), bottom_center + basis * Vector3(-half, height, 0.0),
	]
	var sways: Array[float] = [sway_bottom * hinge, sway_bottom, sway_top, sway_top * hinge]
	var front := (basis * Vector3.FORWARD).normalized()
	var back_shade := 0.88
	# Clockwise seen from the front (-Z), then the same quad wound the other way.
	for tri: Array in [[0, 2, 3], [0, 1, 2]]:
		for corner: int in tri:
			kit._add(corners[corner], front, _alpha(color, sways[corner]))
	for tri: Array in [[0, 3, 2], [0, 2, 1]]:
		for corner: int in tri:
			kit._add(corners[corner], -front, Color(color.r * back_shade, color.g * back_shade, color.b * back_shade, sways[corner]))


## One flat convex face (3+ points in order around it), facing away from
## inside, flat-shaded. For hand-built hulls and roofs.
static func poly(kit: _MeshKit, points: Array, inside: Vector3, color: Color, sway: float = 0.0) -> void:
	var middle := Vector3.ZERO
	for point: Vector3 in points:
		middle += point
	middle /= float(points.size())
	var tinted := _alpha(color, sway)
	for index: int in range(1, points.size() - 1):
		var a: Vector3 = points[0]
		var b: Vector3 = points[index]
		var c: Vector3 = points[index + 1]
		# Godot's front face is clockwise: its normal is (c - a) x (b - a).
		var normal := (c - a).cross(b - a)
		if normal.length_squared() < 1e-12:
			continue
		if normal.dot(middle - inside) < 0.0:
			var swap := b
			b = c
			c = swap
			normal = -normal
		kit.triangle(a, b, c, normal.normalized(), tinted)

## A small two-sided leaf or petal: a diamond facing normal (like MeshKit's
## leaf_card, but its back faces carry the back normal, so both sides light).
static func leaf(kit: _MeshKit, at: Vector3, normal: Vector3, size: float, color: Color, sway: float = 0.0, spin: float = 0.0) -> void:
	var facing := normal.normalized()
	var across := facing.cross(Vector3.UP if absf(facing.y) < 0.95 else Vector3.RIGHT).normalized().rotated(facing, spin)
	var along := facing.cross(across).normalized()
	var tip := at + along * size
	var tail := at - along * size * 0.6
	var left := at - across * size * 0.45
	var right := at + across * size * 0.45
	var front := _alpha(color, sway)
	var back := Color(color.r * 0.9, color.g * 0.9, color.b * 0.9, sway)
	for tri: Array in [[tail, left, tip], [tail, tip, right]]:
		var a: Vector3 = tri[0]
		var b: Vector3 = tri[1]
		var c: Vector3 = tri[2]
		var n := (c - a).cross(b - a)
		if n.dot(facing) < 0.0:
			var swap := b
			b = c
			c = swap
		kit._add(a, facing, front)
		kit._add(b, facing, front)
		kit._add(c, facing, front)
		kit._add(a, -facing, back)
		kit._add(c, -facing, back)
		kit._add(b, -facing, back)

static func _alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)

## A slight random shade of color, from rng (for planks, stones, boards).
static func vary(color: Color, rng: RandomNumberGenerator, amount: float = 0.08) -> Color:
	var scale := 1.0 + rng.randf_range(-amount, amount)
	return Color(clampf(color.r * scale, 0.0, 1.0), clampf(color.g * scale, 0.0, 1.0), clampf(color.b * scale, 0.0, 1.0), color.a)
