extends RefCounted

## Authority: local, cosmetic. Builds organic low-poly meshes in code: lumpy
## blobs, tapered bent tubes, cones, and boxes, all merged into one ArrayMesh
## with per-vertex color. Shading that a hand painter would bake in (darker
## underneath, lighter on top, occlusion in the middle of a clump) goes into the
## vertex colors, so one mesh is one draw call and still reads as modeled.
## Draw the result with props/stylized.gd.
##
## Usage:
##   var kit := MeshKit.new()
##   kit.blob(Vector3(0, 2, 0), Vector3.ONE, Color.ORANGE, {"seed": 4})
##   var mesh := kit.commit()
##
## Vertex color alpha is how much a vertex sways in the wind (0 = rooted).
## Art rules: docs/ART.md. 1 unit = 1 meter, Y up, models face -Z.

const _ICO_T: float = 1.618034

static var _ico_cache: Dictionary = {}

var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _noise := FastNoiseLite.new()


func _init() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0


## A lumpy ball. size is the radius on each axis. Options:
##   seed (int), detail (0-3 subdivisions, default 1), lumps (0-1, default 0.25),
##   lump_scale (default 1.4), flat (bool, default true: faceted),
##   soft (0-1, default 0: how far a faceted normal bends toward the smooth one),
##   outward (bool: lumps only push out, never in, so nothing under shows through),
##   shade (bool, default true: darker under, lighter on top), sway (0-1),
##   jitter (0-1, per-face color variation, default 0.06)
func blob(center: Vector3, size: Vector3, color: Color, options: Dictionary = {}) -> void:
	var detail := int(options.get("detail", 1))
	var lumps := float(options.get("lumps", 0.25))
	var lump_scale := float(options.get("lump_scale", 1.4))
	var flat := bool(options.get("flat", true))
	var soft := float(options.get("soft", 0.0))
	var outward := bool(options.get("outward", false))
	var shade := bool(options.get("shade", true))
	var sway := float(options.get("sway", 0.0))
	var jitter := float(options.get("jitter", 0.06))
	_noise.seed = int(options.get("seed", 0))
	var sphere: Array = _icosphere(detail)
	var points: PackedVector3Array = sphere[0]
	var triangles: PackedInt32Array = sphere[1]
	var moved := PackedVector3Array()
	moved.resize(points.size())
	for index: int in points.size():
		var direction := points[index]
		var bump := _noise.get_noise_3dv(direction * lump_scale)
		bump = (bump * 0.5 + 0.5 if outward else bump) * lumps
		moved[index] = center + direction * size * (1.0 + bump)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(options.get("seed", 0)) * 7919 + 13
	# Smooth normals from the lumpy surface itself, so bumps shade like bumps.
	var smooth_normals := PackedVector3Array()
	smooth_normals.resize(moved.size())
	for tri: int in range(0, triangles.size(), 3):
		var face := (moved[triangles[tri + 1]] - moved[triangles[tri]]).cross(moved[triangles[tri + 2]] - moved[triangles[tri]])
		for corner: int in 3:
			smooth_normals[triangles[tri + corner]] += face
	for tri: int in range(0, triangles.size(), 3):
		var a := moved[triangles[tri]]
		var b := moved[triangles[tri + 1]]
		var c := moved[triangles[tri + 2]]
		var face_normal := (b - a).cross(c - a).normalized()
		var face_color := _vary(color, rng, jitter)
		for corner: int in 3:
			var at := moved[triangles[tri + corner]]
			var smooth := smooth_normals[triangles[tri + corner]].normalized()
			var normal := face_normal.lerp(smooth, soft).normalized() if flat else smooth
			var tint := face_color
			if shade:
				# Darker underneath, a touch brighter on top: baked sky light.
				var up := ((at - center) / maxf(size.y, 0.001)).y
				tint = _scaled(tint, lerpf(0.62, 1.1, clampf(up * 0.5 + 0.5, 0.0, 1.0)))
			tint.a = sway
			_add(at, normal, tint)


## A tube through points, radius tapering through radii (one per point), with
## sides around. Smooth-shaded, capped at the end. Options:
##   seed, sway_from / sway_to (alpha at the first and last point), jitter,
##   cap (bool, default true), flare (extra radius at the very base, 0-1)
func tube(points: PackedVector3Array, radii: PackedFloat32Array, color: Color, sides: int = 7, options: Dictionary = {}) -> void:
	if points.size() < 2:
		return
	var sway_from := float(options.get("sway_from", 0.0))
	var sway_to := float(options.get("sway_to", 0.0))
	var jitter := float(options.get("jitter", 0.04))
	var flare := float(options.get("flare", 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(options.get("seed", 0))
	var rings: Array[PackedVector3Array] = []
	var ring_normals: Array[PackedVector3Array] = []
	var side := Vector3.RIGHT
	for index: int in points.size():
		var forward: Vector3
		if index == 0:
			forward = points[1] - points[0]
		elif index == points.size() - 1:
			forward = points[index] - points[index - 1]
		else:
			forward = points[index + 1] - points[index - 1]
		forward = forward.normalized()
		# Carry the side vector along so the tube never twists.
		side = (side - forward * side.dot(forward))
		if side.length() < 0.01:
			side = forward.cross(Vector3.FORWARD if absf(forward.y) > 0.9 else Vector3.UP)
		side = side.normalized()
		var other := forward.cross(side).normalized()
		var radius := radii[mini(index, radii.size() - 1)]
		var ring := PackedVector3Array()
		var normals := PackedVector3Array()
		for step: int in sides:
			var angle := TAU * float(step) / float(sides)
			var outward := side * cos(angle) + other * sin(angle)
			var wobble := 1.0 + rng.randf_range(-0.06, 0.06)
			if index == 0 and flare > 0.0:
				# Root flare: lumpy, wider at the very bottom.
				wobble += flare * (0.6 + 0.4 * absf(sin(angle * 2.5 + float(rng.randi() % 7))))
			ring.append(points[index] + outward * radius * wobble)
			normals.append(outward)
		rings.append(ring)
		ring_normals.append(normals)
	for index: int in points.size() - 1:
		var t0 := float(index) / float(points.size() - 1)
		var t1 := float(index + 1) / float(points.size() - 1)
		var c0 := _vary(color, rng, jitter)
		var c1 := _vary(color, rng, jitter)
		c0.a = lerpf(sway_from, sway_to, t0)
		c1.a = lerpf(sway_from, sway_to, t1)
		for step: int in sides:
			var next := (step + 1) % sides
			var a := rings[index][step]
			var b := rings[index][next]
			var c := rings[index + 1][next]
			var d := rings[index + 1][step]
			_add(a, ring_normals[index][step], c0)
			_add(c, ring_normals[index + 1][next], c1)
			_add(b, ring_normals[index][next], c0)
			_add(a, ring_normals[index][step], c0)
			_add(d, ring_normals[index + 1][step], c1)
			_add(c, ring_normals[index + 1][next], c1)
	if bool(options.get("cap", true)):
		var last := rings.size() - 1
		var tip := points[last]
		var tip_normal := (points[last] - points[last - 1]).normalized()
		var cap_color := _scaled(color, 1.05)
		cap_color.a = sway_to
		for step: int in sides:
			var next := (step + 1) % sides
			_add(rings[last][step], tip_normal, cap_color)
			_add(rings[last][next], tip_normal, cap_color)
			_add(tip, tip_normal, cap_color)


## A cone or tapered cylinder, base at base, pointing up by height. Faceted.
## Options: seed, sway (alpha at the top), droop (how far the rim sags), lumps.
func cone(base: Vector3, radius: float, height: float, color: Color, sides: int = 8, options: Dictionary = {}) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(options.get("seed", 0))
	var sway := float(options.get("sway", 0.0))
	var droop := float(options.get("droop", 0.0))
	var lumps := float(options.get("lumps", 0.12))
	var top_radius := float(options.get("top_radius", 0.0))
	var top := base + Vector3(0.0, height, 0.0)
	var rim := PackedVector3Array()
	var top_ring := PackedVector3Array()
	var turn := rng.randf_range(0.0, TAU)
	for step: int in sides:
		var angle := turn + TAU * float(step) / float(sides)
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var r := radius * (1.0 + rng.randf_range(-lumps, lumps))
		# Every other rim point hangs lower, like drooping branch tips.
		var sag := droop * (1.0 if step % 2 == 0 else 0.35)
		rim.append(base + out * r - Vector3(0.0, sag, 0.0))
		top_ring.append(top + out * top_radius)
	for step: int in sides:
		var next := (step + 1) % sides
		var a := rim[step]
		var b := rim[next]
		var c := top_ring[next] if top_radius > 0.0 else top
		var d := top_ring[step] if top_radius > 0.0 else top
		# Outward and up by the slope, so the light wraps around the cone.
		var out := ((a + b) * 0.5 - base)
		out.y = 0.0
		var normal := (out.normalized() * height + Vector3.UP * (radius - top_radius)).normalized()
		var face := _vary(color, rng, 0.05)
		var low := _scaled(face, 0.8)
		low.a = sway * 0.6
		var high := _scaled(face, 1.08)
		high.a = sway
		_add(a, normal, low)
		_add(b, normal, low)
		_add(d, normal, high)
		if top_radius > 0.0:
			_add(b, normal, low)
			_add(c, normal, high)
			_add(d, normal, high)
	# Underside, so it reads from below.
	var under := _scaled(color, 0.7)
	under.a = sway * 0.6
	var middle := base + Vector3(0.0, -droop * 0.3, 0.0)
	for step: int in sides:
		var next := (step + 1) % sides
		_add(rim[step], Vector3.DOWN, under)
		_add(middle, Vector3.DOWN, under)
		_add(rim[next], Vector3.DOWN, under)


## A box with optional bevel-free faces, faceted, centered at center.
func box(center: Vector3, size: Vector3, color: Color, basis: Basis = Basis.IDENTITY, sway: float = 0.0) -> void:
	var half := size * 0.5
	var faces := [
		[Vector3.RIGHT, Vector3.UP, Vector3.BACK],
		[Vector3.LEFT, Vector3.UP, Vector3.FORWARD],
		[Vector3.UP, Vector3.BACK, Vector3.RIGHT],
		[Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT],
		[Vector3.BACK, Vector3.UP, Vector3.LEFT],
		[Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
	]
	for face: Array in faces:
		var normal: Vector3 = face[0]
		var up: Vector3 = face[1]
		var across: Vector3 = face[2]
		var mid := normal * half
		var u := up * half
		var v := across * half
		var corners := [mid - u - v, mid - u + v, mid + u + v, mid + u - v]
		var tint := _scaled(color, 1.06 if normal == Vector3.UP else (0.7 if normal == Vector3.DOWN else 1.0))
		tint.a = sway
		var world_normal := (basis * normal).normalized()
		var order := [0, 2, 1, 0, 3, 2]
		for corner: int in order:
			_add(center + basis * (corners[corner] as Vector3), world_normal, tint)


## Darken every vertex by how deep inside the shape it sits, measured from
## center with the given radii: fake ambient occlusion for clumps like a tree crown.
func occlude(center: Vector3, radii: Vector3, strength: float = 0.35) -> void:
	for index: int in _vertices.size():
		var local := (_vertices[index] - center) / radii
		var depth := clampf(1.0 - local.length(), 0.0, 1.0)
		var dim := 1.0 - depth * strength
		var color := _colors[index]
		_colors[index] = Color(color.r * dim, color.g * dim, color.b * dim, color.a)


## A small leaf: a diamond facing normal, seen from both sides. For fluffy
## silhouettes, scatter these over a clump's surface.
func leaf_card(at: Vector3, normal: Vector3, size: float, color: Color, sway: float, spin: float = 0.0) -> void:
	var facing := normal.normalized()
	var across := facing.cross(Vector3.UP if absf(facing.y) < 0.95 else Vector3.RIGHT).normalized()
	across = across.rotated(facing, spin)
	var along := facing.cross(across).normalized()
	var tip := at + along * size
	var tail := at - along * size * 0.6
	var left := at - across * size * 0.45
	var right := at + across * size * 0.45
	var tint := color
	tint.a = sway
	var back := _scaled(color, 0.92)
	back.a = sway
	_add(tail, facing, tint)
	_add(left, facing, tint)
	_add(tip, facing, tint)
	_add(tail, facing, tint)
	_add(tip, facing, tint)
	_add(right, facing, tint)
	_add(tail, facing, back)
	_add(tip, facing, back)
	_add(left, facing, back)
	_add(tail, facing, back)
	_add(right, facing, back)
	_add(tip, facing, back)


## Grade vertices from index on: darker at bottom_y, lighter at top_y. For a
## whole crown, so it has one big lit top and shaded underside.
func grade(from_index: int, bottom_y: float, top_y: float, low: float, high: float) -> void:
	for index: int in range(from_index, _vertices.size()):
		var t := clampf((_vertices[index].y - bottom_y) / maxf(top_y - bottom_y, 0.001), 0.0, 1.0)
		var amount := lerpf(low, high, t * t * (3.0 - 2.0 * t))
		var color := _colors[index]
		_colors[index] = Color(color.r * amount, color.g * amount, color.b * amount, color.a)


func vertex_count() -> int:
	return _vertices.size()


## The finished mesh, or null if nothing was added.
func commit() -> ArrayMesh:
	if _vertices.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# Triangles wind clockwise seen from outside, which is Godot's front face.
func _add(at: Vector3, normal: Vector3, color: Color) -> void:
	_vertices.append(at)
	_normals.append(normal)
	_colors.append(color)


func _vary(color: Color, rng: RandomNumberGenerator, amount: float) -> Color:
	if amount <= 0.0:
		return color
	var varied := Color.from_hsv(
		fposmod(color.h + rng.randf_range(-amount, amount) * 0.25, 1.0),
		clampf(color.s + rng.randf_range(-amount, amount), 0.0, 1.0),
		clampf(color.v * (1.0 + rng.randf_range(-amount, amount) * 1.5), 0.0, 1.0))
	varied.a = color.a
	return varied


func _scaled(color: Color, amount: float) -> Color:
	return Color(color.r * amount, color.g * amount, color.b * amount, color.a)


## Unit icosphere points and triangles, subdivided detail times. Cached.
static func _icosphere(detail: int) -> Array:
	if _ico_cache.has(detail):
		return _ico_cache[detail]
	var t := _ICO_T
	var points: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	]
	for index: int in points.size():
		points[index] = points[index].normalized()
	var triangles := PackedInt32Array([
		0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11,
		1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9,
		4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1,
	])
	for _level: int in detail:
		var midpoints: Dictionary = {}
		var finer := PackedInt32Array()
		for tri: int in range(0, triangles.size(), 3):
			var a := triangles[tri]
			var b := triangles[tri + 1]
			var c := triangles[tri + 2]
			var ab := _midpoint(points, midpoints, a, b)
			var bc := _midpoint(points, midpoints, b, c)
			var ca := _midpoint(points, midpoints, c, a)
			finer.append_array([a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca])
		triangles = finer
	# Flip to clockwise winding for Godot's front faces.
	for tri: int in range(0, triangles.size(), 3):
		var swap := triangles[tri + 1]
		triangles[tri + 1] = triangles[tri + 2]
		triangles[tri + 2] = swap
	var result := [PackedVector3Array(points), triangles]
	_ico_cache[detail] = result
	return result


static func _midpoint(points: Array[Vector3], midpoints: Dictionary, a: int, b: int) -> int:
	var key := Vector2i(mini(a, b), maxi(a, b))
	if midpoints.has(key):
		return midpoints[key]
	points.append(((points[a] + points[b]) * 0.5).normalized())
	midpoints[key] = points.size() - 1
	return points.size() - 1
