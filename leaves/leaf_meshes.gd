class_name LeafMeshes
extends RefCounted

## Authority: local, cosmetic. The three fallen-leaf shapes, built in code and
## cached: a maple (five pointed lobes, the front one longest, sinuses cut to
## about 0.45 of the lobe), an oak (four rounded lobes a side, 1.6:1) and an oval
## (serrated, pointed tip; a birch leaf, a willow leaf drawn narrow, a spring
## petal drawn small). Each is a unit leaf, 1.0 long from base to tip along -Z,
## centred on the origin, scaled per instance by Constants.LEAF_SIZE.
##
## Shape: a fan from the hub where the veins meet, V-folded along the midrib
## (each half rises 0.13 rad), the tips curled up (Constants.LEAF_CURL times r
## squared) and a bent four-triangle stem off the base. Normals are bent toward
## up (face + 0.8 up) so a carpet of them shades like a soft surface instead of
## glittering. Masks the flake shader reads (leaves/leaf_shaders.gd):
## - UV.x: rim factor, 0 at the hub, 1 at the edge (centre-to-rim colour)
## - UV.y: species * 2 + flex (flex 0 at the stem, 1 at the tips: what the
##   breeze lifts)
## - UV2: the point in the leaf's own plane (x, z) from the hub, for the veins
## - COLOR: white (the instance colour multiplies it)

const MAPLE: int = 0
const OAK: int = 1
const OVAL: int = 2
const SPECIES: int = 3
## How far each half folds up from the midrib (radians).
const FOLD: float = 0.13
## The stem: length and width in unit-leaf lengths.
const STEM_LENGTH: float = 0.22
const STEM_WIDTH: float = 0.022

static var _meshes: Array = [null, null, null]
static var _triangles: Array[int] = [0, 0, 0]


## The unit leaf of a species (MAPLE, OAK, OVAL).
static func mesh(species: int) -> ArrayMesh:
	var index := clampi(species, 0, SPECIES - 1)
	if _meshes[index] == null:
		_meshes[index] = _build(index)
	return _meshes[index]


## Triangles in a species' leaf.
static func triangles(species: int) -> int:
	mesh(species)
	return _triangles[clampi(species, 0, SPECIES - 1)]


## The outline as polar points around the hub: [[angle, radius]], the angle
## measured from -Z (the tip) toward +X, all the way round. And the hub.
static func _outline(species: int) -> Dictionary:
	var points: Array = []
	match species:
		MAPLE:
			# Five lobes radiating from the hub near the base.
			var lobes: Array = [[-1.9, 0.34], [-0.98, 0.5], [0.0, 0.62], [0.98, 0.5], [1.9, 0.34]]
			for index: int in lobes.size():
				var angle: float = lobes[index][0]
				var reach: float = lobes[index][1]
				if index == 0:
					# The base: from the back notch round to the first lobe.
					points.append([-PI + 0.001, 0.07])
					points.append([-2.65, 0.16])
				# Broad lobes: shoulders well out, a tooth each side of the point
				# on the three big ones.
				var toothed := absf(angle) < 1.2
				points.append([angle - 0.3, reach * 0.66])
				points.append([angle - 0.17, reach * 0.86])
				if toothed:
					points.append([angle - 0.08, reach * 0.8])
				points.append([angle, reach])
				if toothed:
					points.append([angle + 0.08, reach * 0.8])
				points.append([angle + 0.17, reach * 0.86])
				points.append([angle + 0.3, reach * 0.66])
				if index < lobes.size() - 1:
					# The sinus between this lobe and the next.
					var next: Array = lobes[index + 1]
					points.append([(angle + float(next[0])) * 0.5, minf(reach, float(next[1])) * 0.48])
			points.append([2.65, 0.16])
			return {"points": points, "hub": Vector2(0.0, 0.18)}
		OAK:
			# An oblong outline with four rounded lobes a side and a rounded tip.
			var count := 40
			for index: int in count:
				var angle := -PI + TAU * (float(index) + 0.5) / float(count)
				var s := sin(angle)
				var c := cos(angle)
				var ellipse := 1.0 / sqrt(pow(s / 0.31, 2.0) + pow(c / 0.5, 2.0))
				# Lobes: a rounded tip lobe, then rounded bumps down each side.
				var along := clampf(absf(angle) / (PI - 0.35), 0.0, 1.0)
				var lobe := pow(absf(cos(along * 4.0 * PI)), 0.6)
				var radius := ellipse * (0.72 + 0.28 * lobe)
				if absf(angle) > PI - 0.35:
					radius = ellipse * 0.35
				points.append([angle, radius])
			return {"points": points, "hub": Vector2(0.0, 0.0)}
	# OVAL: pointed tip, rounded base, serrated sides.
	var teeth := 30
	for index: int in teeth:
		var angle := -PI + TAU * (float(index) + 0.5) / float(teeth)
		var s := sin(angle)
		var c := cos(angle)
		var ellipse := 1.0 / sqrt(pow(s / 0.27, 2.0) + pow(c / 0.5, 2.0))
		# A drawn-out tip.
		var tip := 1.0 + 0.22 * pow(maxf(c, 0.0), 6.0)
		var serration := 1.0 if index % 2 == 0 else 0.93
		points.append([angle, ellipse * tip * serration])
	return {"points": points, "hub": Vector2(0.0, 0.0)}


static func _build(species: int) -> ArrayMesh:
	var outline := _outline(species)
	var points: Array = outline["points"]
	var hub: Vector2 = outline["hub"]
	# Plane positions (x, z), the tip toward -Z.
	var flat: Array[Vector2] = []
	var max_radius := 0.0
	for point: Array in points:
		var angle: float = point[0]
		var radius: float = point[1]
		flat.append(hub + Vector2(sin(angle), -cos(angle)) * radius)
		max_radius = maxf(max_radius, radius)
	# Unit length along Z, centred on the origin.
	var low := INF
	var high := -INF
	for at: Vector2 in flat:
		low = minf(low, at.y)
		high = maxf(high, at.y)
	var scale := 1.0 / maxf(high - low, 0.001)
	var shift := Vector2(0.0, -(low + high) * 0.5)
	for index: int in flat.size():
		flat[index] = (flat[index] + shift) * scale
	hub = (hub + shift) * scale
	max_radius *= scale
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()
	var code := float(species) * 2.0
	# The hub, then the rim.
	vertices.append(_lift(hub, hub, max_radius))
	uvs.append(Vector2(0.0, code + 0.35))
	uv2s.append(Vector2.ZERO)
	for at: Vector2 in flat:
		vertices.append(_lift(at, hub, max_radius))
		var reach := clampf(at.distance_to(hub) / max_radius, 0.0, 1.0)
		uvs.append(Vector2(1.0, code + clampf(0.35 + reach, 0.0, 1.0)))
		uv2s.append(at - hub)
	var rim := flat.size()
	for index: int in rim:
		indices.append_array([0, 1 + index, 1 + (index + 1) % rim])
	# The stem: two bent quads off the base, from the rim point nearest the back.
	var base := 0
	for index: int in rim:
		if flat[index].y > flat[base].y:
			base = index
	var start := Vector3(flat[base].x, 0.0, flat[base].y)
	start.y = vertices[1 + base].y
	var mid := start + Vector3(0.03, 0.025, STEM_LENGTH * 0.5)
	var end := start + Vector3(0.08, 0.06, STEM_LENGTH)
	var first := vertices.size()
	for along: Vector3 in [start + Vector3(0.0, 0.0, -0.03), mid, end]:
		for side: float in [-1.0, 1.0]:
			vertices.append(along + Vector3(side * STEM_WIDTH * 0.5, 0.0, 0.0))
			uvs.append(Vector2(0.3, code))
			uv2s.append(Vector2(0.0, 0.5))
	for segment: int in 2:
		var a := first + segment * 2
		# Clockwise seen from above: the top is the front face.
		indices.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
	# Normals: each face's, averaged per vertex, then bent toward up.
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for index: int in range(0, indices.size(), 3):
		var a := vertices[indices[index]]
		var b := vertices[indices[index + 1]]
		var c := vertices[indices[index + 2]]
		var face := (b - a).cross(c - a)
		if face.y < 0.0:
			face = -face
		for corner: int in 3:
			normals[indices[index + corner]] += face
	for index: int in normals.size():
		var face := normals[index].normalized() if normals[index].length() > 0.0 else Vector3.UP
		normals[index] = (face + Vector3.UP * 0.8).normalized()
	var colors := PackedColorArray()
	colors.resize(vertices.size())
	colors.fill(Color.WHITE)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	var made := ArrayMesh.new()
	made.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_triangles[species] = indices.size() / 3
	made.set_meta("triangles", indices.size() / 3)
	return made


## A point of the leaf's plane, folded and curled.
static func _lift(at: Vector2, hub: Vector2, max_radius: float) -> Vector3:
	var reach := at.distance_to(hub) / maxf(max_radius, 0.001)
	var fold := absf(at.x) * tan(FOLD)
	var curl := Constants.LEAF_CURL * reach * reach
	return Vector3(at.x, fold + curl, at.y)
