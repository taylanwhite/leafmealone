extends RefCounted

## Authority: local, cosmetic. Grass: tufts of bent blades scattered over a
## zone's lawns, drawn as instanced meshes in chunks so only nearby ones cost
## anything, and swaying in the wind (props/stylized.gd, by vertex alpha: tips
## move, roots don't). Dressing code marks what must stay clear (roads, walks,
## driveways, buildings) with keep_clear(), and plant() skips those. Seeded, so
## every peer grows the same lawn.

const _Stylized = preload("res://props/stylized.gd")
const CHUNK: float = 14.0
const BASE := Color(0.24, 0.38, 0.16)
const TIP := Color(0.5, 0.66, 0.28)

static var _tuft: ArrayMesh
static var _short_tuft: ArrayMesh


## Mark a rectangle (zone space, x and z) where no grass grows.
static func keep_clear(zone: Node3D, rect: Rect2) -> void:
	var rects: Array = zone.get_meta("no_grass", [])
	rects.append(rect)
	zone.set_meta("no_grass", rects)


## Mark the ground under a node's footprint, given its size and transform in zone space.
static func keep_clear_box(zone: Node3D, xform: Transform3D, size: Vector3) -> void:
	var half := size * 0.5
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for corner: Vector3 in [Vector3(-half.x, 0, -half.z), Vector3(half.x, 0, -half.z), Vector3(-half.x, 0, half.z), Vector3(half.x, 0, half.z)]:
		var at := xform * corner
		low = Vector2(minf(low.x, at.x), minf(low.y, at.z))
		high = Vector2(maxf(high.x, at.x), maxf(high.y, at.z))
	keep_clear(zone, Rect2(low, high - low))


## Grow grass over the square of half_size around the zone's middle, every
## spacing meters on average, skipping cleared rectangles. yard_half: inside this
## square (the play pad) the tufts are short and sparse, so leaves stay the star.
static func plant(zone: Node3D, half_size: float, spacing: float, seed_value: int, yard_half: float = 0.0) -> void:
	if _tuft == null:
		_tuft = _tuft_mesh(0.42, 7)
		_short_tuft = _tuft_mesh(0.18, 5)
	var rects: Array = zone.get_meta("no_grass", [])
	var root := Node3D.new()
	root.name = "Grass"
	zone.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var chunks := int(ceil(half_size * 2.0 / CHUNK))
	var material := _Stylized.material({"wind": 0.06, "roughness": 1.0, "specular": 0.05, "translucency": 0.25, "double_sided": true})
	for chunk_x: int in chunks:
		for chunk_z: int in chunks:
			var corner := Vector2(-half_size + float(chunk_x) * CHUNK, -half_size + float(chunk_z) * CHUNK)
			var tall: Array[Transform3D] = []
			var short: Array[Transform3D] = []
			var tall_colors: Array[Color] = []
			var short_colors: Array[Color] = []
			var count := int(CHUNK * CHUNK / (spacing * spacing))
			for _index: int in count:
				var at := corner + Vector2(rng.randf() * CHUNK, rng.randf() * CHUNK)
				if _cleared(rects, at):
					continue
				var in_yard := absf(at.x) < yard_half and absf(at.y) < yard_half
				if in_yard and rng.randf() < 0.6:
					continue
				var scale := rng.randf_range(0.7, 1.3)
				var xform := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(scale, scale * rng.randf_range(0.8, 1.25), scale)), Vector3(at.x, 0.0, at.y))
				var tint := Color.WHITE.lerp(Color(1.08, 0.98, 0.75), rng.randf() * 0.6)
				if in_yard:
					short.append(xform)
					short_colors.append(tint)
				else:
					tall.append(xform)
					tall_colors.append(tint)
			_add_chunk(root, _tuft, tall, tall_colors, material)
			_add_chunk(root, _short_tuft, short, short_colors, material)


static func _cleared(rects: Array, at: Vector2) -> bool:
	for rect: Rect2 in rects:
		if rect.has_point(at):
			return true
	return false


static func _add_chunk(root: Node3D, mesh: Mesh, spots: Array[Transform3D], colors: Array[Color], material: Material) -> void:
	if spots.is_empty():
		return
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = mesh
	multi.instance_count = spots.size()
	for index: int in spots.size():
		multi.set_instance_transform(index, spots[index])
		multi.set_instance_color(index, colors[index])
	var view := MultiMeshInstance3D.new()
	view.multimesh = multi
	view.material_override = material
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Grass only matters up close; past this it's the ground's own color.
	view.visibility_range_end = 45.0
	view.visibility_range_end_margin = 8.0
	view.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	root.add_child(view)


## A tuft: blades fanning out from one root, each bent a little, dark at the root
## and sunny at the tip, the tips free to sway.
static func _tuft_mesh(height: float, blades: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = blades * 31 + int(height * 100.0)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for blade: int in blades:
		var angle := TAU * float(blade) / float(blades) + rng.randf_range(-0.4, 0.4)
		var lean := Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(0.04, 0.12)
		var side := Vector3(-sin(angle), 0.0, cos(angle)) * 0.03
		var root := Vector3(cos(angle), 0.0, sin(angle)) * 0.03
		var tall := height * rng.randf_range(0.7, 1.1)
		var mid := root + Vector3(0.0, tall * 0.55, 0.0) + lean * 0.4
		var tip := root + Vector3(0.0, tall, 0.0) + lean
		var normal := Vector3(cos(angle), 0.6, sin(angle)).normalized()
		var base := BASE
		base.a = 0.0
		var middle := BASE.lerp(TIP, 0.55)
		middle.a = 0.45
		var top := TIP
		top.a = 1.0
		# Two quads up to a point: root, middle, tip.
		var quad := [root - side, root + side, mid + side * 0.7, mid - side * 0.7]
		var quad_colors := [base, base, middle, middle]
		for corner: int in [0, 1, 2, 0, 2, 3]:
			vertices.append(quad[corner])
			normals.append(normal)
			colors.append(quad_colors[corner])
		for point: Array in [[mid - side * 0.7, middle], [mid + side * 0.7, middle], [tip, top]]:
			vertices.append(point[0])
			normals.append(normal)
			colors.append(point[1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
