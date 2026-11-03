extends RefCounted

## Dev tool, local only. The studio's "leaves" subject (raking:2, docs/ART.md
## "Leaves"): a real LeafField and its leaf view on a yard shaped like
## levels/lots/lot_generator.gd _shape_leaves (an even cover, heaped under two
## trees: a red maple and a yellow birch), drawn with the game's renderer.
##
##   Godot --path . res://tools/studio/studio.tscn -- --subject=leaves --kind=carpet --out=build/r1/leaves/carpet.png
##
## --kind:
## - carpet (default): knee height, first person, top-down from 9 m, wide from the truck
## - pile: a raked pile (density 255) beside the drift under the red maple, at
##   eye level, a ground-level profile, from above and close
## - raked: a lane raked through the carpet, from first person and above
## - species: the three leaves up close, face up, face down and mid-tumble
## - gpu: also prints the largest gap between the CPU's surface_y and the
##   height the shaders read, over 400 points ([LeafStudio] gpu ...)
## --season=N picks the season (the studio sets it before building), --sun=noon|low|dusk
## the time of day, --strokes=N how many rake strokes build the pile.

const _Trees = preload("res://props/trees.gd")
const _LeafShaders = preload("res://leaves/leaf_shaders.gd")
const RED_TREE := Vector3(-7.0, 0.0, -5.0)
const BIRCH := Vector3(8.0, 0.0, -8.0)


static func build(root: Node3D, options: Dictionary) -> void:
	var kind := str(options.get("kind", "carpet"))
	if kind == "species":
		_species(root)
		_sun(root, str(options.get("sun", "noon")))
		return
	_Trees.spawn(root, RED_TREE, 8.0, "broadleaf", "red", 0)
	_Trees.spawn(root, BIRCH, 7.5, "birch", "yellow", 1)
	var field := Node3D.new()
	field.name = "LeafField"
	field.set_script(load("res://net/leaf_field/leaf_field.gd"))
	field.set_meta("leaf_sources", [
		{"at": Vector2(RED_TREE.x, RED_TREE.z), "crown": "red", "kind": "broadleaf", "variant": 0},
		{"at": Vector2(BIRCH.x, BIRCH.z), "crown": "yellow", "kind": "birch", "variant": 1},
		{"at": Vector2(-12.0, 12.0), "crown": "orange", "kind": "broadleaf", "variant": 1},
	])
	var view := Node3D.new()
	view.name = "LeafRenderer"
	view.set_script(load("res://leaves/leaf_renderer.gd"))
	field.add_child(view)
	root.add_child(field)
	var trees: Array[Vector3] = [RED_TREE, BIRCH, Vector3(-12.0, 0.0, 12.0)]
	var spread := 5.5
	field.call("shape_initial", func(world: Vector3) -> float:
		var amount := 0.6 * float(Constants.YARD_LEAVES[1])
		for tree: Vector3 in trees:
			var distance := Vector2(world.x - tree.x, world.z - tree.z).length()
			amount += Constants.YARD_TREE_LEAVES * exp(-distance * distance / (2.0 * spread * spread))
		# A swept walk, as the yard's driveway is.
		if absf(world.x - 2.5) < 1.0 and world.z > 6.0:
			return 0.0
		# Fewer leaves out of autumn, as the game's yards (Seasons.LEAVES).
		return clampf(amount, 0.0, Constants.YARD_LEAF_CAP) * Seasons.LEAVES[Seasons.current()])
	match kind:
		"pile":
			_rake_pile(field, int(options.get("strokes", "18")))
			root.set_meta("views", [
				{"from": Vector3(1.0, 1.7, 8.5), "at": Vector3(1.0, 0.25, -2.0), "fov": 55.0},
				{"from": Vector3(1.5, 0.12, 9.0), "at": Vector3(1.5, 0.3, -3.0), "fov": 45.0},
				{"from": Vector3(1.0, 9.0, 4.0), "at": Vector3(1.0, 0.0, -2.0), "fov": 55.0},
				{"from": Vector3(5.6, 1.0, 2.6), "at": Vector3(4.6, 0.35, 0.0), "fov": 50.0},
			])
		"raked":
			_rake_lane(field)
			root.set_meta("views", [
				{"from": Vector3(0.0, 1.6, 6.5), "at": Vector3(0.0, 0.0, 1.0), "fov": 70.0},
				{"from": Vector3(0.0, 8.0, 5.0), "at": Vector3(0.0, 0.0, -1.0), "fov": 50.0},
				{"from": Vector3(2.2, 0.45, 3.5), "at": Vector3(0.0, 0.05, 0.5), "fov": 50.0},
				{"from": Vector3(0.4, 1.6, -7.5), "at": Vector3(0.0, 0.2, -4.0), "fov": 70.0},
			])
		_:
			root.set_meta("views", [
				{"from": Vector3(1.4, 0.45, 3.4), "at": Vector3(0.0, 0.05, 0.4), "fov": 50.0},
				{"from": Vector3(0.0, 1.6, 4.0), "at": Vector3(0.0, 0.0, -0.5), "fov": 70.0},
				{"from": Vector3(0.0, 9.0, 0.01), "at": Vector3(0.0, 0.0, 0.0), "fov": 50.0},
				{"from": Vector3(16.0, 3.2, 24.0), "at": Vector3(0.0, 0.0, -2.0), "fov": 60.0},
			])
	_sun(root, str(options.get("sun", "noon")))
	if kind == "gpu":
		var check := _GpuCheck.new()
		check.view = view
		root.add_child(check)


## Rake strokes toward +X along three lanes, into a pile ahead (as gag_test does).
static func _rake_pile(field: Node3D, strokes: int) -> void:
	for lane: float in [-1.0, 0.0, 1.0]:
		for stroke: int in strokes:
			var at := Vector3(-5.0 + float(stroke) * 0.5, 0.2, lane)
			field.call("_stroke_cells", at, Vector3.RIGHT, Constants.RAKE_WIDTH, Constants.RAKE_STRENGTH, Constants.RAKE_STROKE_CELLS)


## A lane raked toward -Z, as a player walking backward through the carpet leaves it.
static func _rake_lane(field: Node3D) -> void:
	for stroke: int in 16:
		var at := Vector3(0.0, 0.2, 5.0 - float(stroke) * 0.5)
		field.call("_stroke_cells", at, Vector3.FORWARD, Constants.RAKE_WIDTH, Constants.RAKE_STRENGTH, Constants.RAKE_STROKE_CELLS)


## The time of day: the studio's shared look sets the sun after the subject is
## built, so a small helper turns it a frame later.
static func _sun(root: Node3D, when: String) -> void:
	if when == "noon":
		return
	var helper := _Sun.new()
	helper.when = when
	root.add_child(helper)


## The three leaves, big: face up, face down, mid-tumble.
static func _species(root: Node3D) -> void:
	var floats := PackedFloat32Array()
	var looks: Array = [{"crown": "red", "species": 0, "width": 1.0}, {"crown": "orange", "species": 1, "width": 1.0}, {"crown": "yellow", "species": 2, "width": 1.0}]
	var counts: Array[int] = [0, 0, 0]
	var buffers: Array = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
	for row: int in 3:
		for species: int in 3:
			var leaf := LeafPalette.flake(looks, [0, 1, 2], species, Seasons.current(), 3, 7, species + row * 5)
			var basis := Basis.IDENTITY
			match row:
				1:
					basis = Basis(Vector3.FORWARD, PI)
				2:
					basis = Basis.from_euler(Vector3(0.9, 0.6, 0.5))
			basis = basis * Basis.from_scale(Vector3.ONE * 0.9)
			var at := Vector3(float(species) - 1.0, 0.25 + float(row) * 0.0, float(row) * 1.1 - 1.1)
			var centre: Color = leaf["centre"]
			var rim: Color = leaf["rim"]
			var into: PackedFloat32Array = buffers[species]
			into.append_array([
				basis.x.x, basis.y.x, basis.z.x, at.x,
				basis.x.y, basis.y.y, basis.z.y, at.y,
				basis.x.z, basis.y.z, basis.z.z, at.z,
				centre.r, centre.g, centre.b, float(leaf["age"]),
				rim.r, rim.g, rim.b, 0.0,
			])
			buffers[species] = into
			counts[species] += 1
	for species: int in 3:
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.use_custom_data = true
		multi.mesh = LeafMeshes.mesh(species)
		multi.instance_count = counts[species]
		multi.buffer = buffers[species]
		var view := MultiMeshInstance3D.new()
		view.multimesh = multi
		view.material_override = _LeafShaders.flake_material("mover")
		root.add_child(view)
	floats.clear()
	root.set_meta("views", [
		{"from": Vector3(0.0, 2.2, 1.6), "at": Vector3(0.0, 0.2, -0.2), "fov": 50.0},
		{"from": Vector3(0.0, 0.9, 2.4), "at": Vector3(0.0, 0.25, -0.4), "fov": 45.0},
		{"from": Vector3(0.0, 3.2, 0.01), "at": Vector3(0.0, 0.0, 0.0), "fov": 45.0},
		{"from": Vector3(-0.6, 0.6, 0.6), "at": Vector3(-1.0, 0.25, -1.1), "fov": 40.0},
	])


class _Sun extends Node:
	var when := "low"
	var _frames := 0

	func _process(_delta: float) -> void:
		_frames += 1
		if _frames != 1:
			return
		var sun := get_tree().current_scene.get_node_or_null("Sun") as DirectionalLight3D
		if sun == null:
			return
		match when:
			"low":
				sun.rotation_degrees = Vector3(-14.0, -60.0, 0.0)
				sun.light_color = Color(1.0, 0.78, 0.55)
			"dusk":
				sun.rotation_degrees = Vector3(-6.0, -95.0, 0.0)
				sun.light_color = Color(1.0, 0.62, 0.4)
				sun.light_energy = 0.9
			"high":
				sun.rotation_degrees = Vector3(-70.0, -30.0, 0.0)


## Compares the CPU's surface_y with the shaders' height map: a top-down
## orthographic camera over a flat quad whose shader writes leaf_height().
class _GpuCheck extends Node3D:
	var view: Node3D
	var _viewport: SubViewport
	var _frames := 0
	const PIXELS := 20
	const SPAN := 18.0

	func _ready() -> void:
		_viewport = SubViewport.new()
		_viewport.size = Vector2i(PIXELS, PIXELS)
		_viewport.own_world_3d = true
		_viewport.use_hdr_2d = true
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(_viewport)
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = SPAN
		_viewport.add_child(camera)
		camera.look_at_from_position(Vector3(0.0, 20.0, 0.0), Vector3.ZERO, Vector3.FORWARD)
		camera.current = true
		var quad := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(SPAN * 2.0, SPAN * 2.0)
		quad.mesh = plane
		var shader := Shader.new()
		shader.code = "shader_type spatial;\nrender_mode unshaded, fog_disabled;\n" + _LeafShaders.COMMON.replace("vec3 to_linear", "vec3 unused_to_linear") + """
varying vec3 world;
void vertex() { world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() { ALBEDO = vec3(leaf_height(world.xz).x, 0.0, 0.0); }
"""
		var material := ShaderMaterial.new()
		material.shader = shader
		quad.material_override = material
		_viewport.add_child(quad)

	func _process(_delta: float) -> void:
		_frames += 1
		if _frames != 4:
			return
		var image := _viewport.get_texture().get_image()
		var worst := 0.0
		var samples := 0
		var ground := float(view.call("ground_y"))
		for py: int in PIXELS:
			for px: int in PIXELS:
				# The camera looks down -Y with up -Z: image x is +X, image y is +Z.
				var x := (float(px) + 0.5) / float(PIXELS) * SPAN - SPAN * 0.5
				var z := (float(py) + 0.5) / float(PIXELS) * SPAN - SPAN * 0.5
				var gpu := image.get_pixel(px, py).r
				var cpu := float(view.call("surface_y", Vector2(x, z))) - ground
				worst = maxf(worst, absf(gpu - cpu))
				samples += 1
		print("[LeafStudio] gpu %d points, max |CPU surface_y - GPU height| = %.2f mm (%s)" % [samples, worst * 1000.0, "PASS" if worst <= 0.002 else "FAIL"])
