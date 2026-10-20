extends RefCounted

## Authority: local, cosmetic. Trees for the neighborhood, built in code with
## props/mesh_kit.gd and drawn with props/stylized.gd. A broadleaf tree is a
## flared, leaning trunk that splits into bent limbs, each ending in clumps of
## autumn leaves, with the crown darkened toward its middle so it reads as deep.
## A pine is a thin trunk inside drooping tiers. Crowns sway in the wind.
## Meshes are cached per kind and variant, so a street of trees costs a handful.
## Art rules: docs/ART.md. 1 unit = 1 meter, Y up, origin at the base.

const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")

## Every tree is built this tall and scaled to the height asked for.
const BUILD_HEIGHT: float = 7.0
const VARIANTS: int = 4
const BARK := Color(0.33, 0.24, 0.18)
const PINE_GREEN := Color(0.2, 0.42, 0.26)
## Autumn crowns: the main color and the one its clumps drift toward.
const CROWNS: Dictionary = {
	"orange": [Color(0.92, 0.5, 0.16), Color(0.95, 0.66, 0.24)],
	"red": [Color(0.78, 0.22, 0.14), Color(0.9, 0.4, 0.18)],
	"yellow": [Color(0.93, 0.73, 0.24), Color(0.86, 0.8, 0.33)],
	"rust": [Color(0.66, 0.3, 0.14), Color(0.84, 0.46, 0.18)],
	"turning": [Color(0.55, 0.6, 0.24), Color(0.93, 0.58, 0.2)],
	"green": [Color(0.33, 0.53, 0.22), Color(0.45, 0.6, 0.25)],
}
const WIND: Dictionary = {"wind": 0.09, "translucency": 0.35}

static var _cache: Dictionary = {}


## A tree under parent at at. kind is "broadleaf" or "pine"; crown is a key of
## CROWNS (ignored for pines). variant picks one of a few shapes. solid adds a
## trunk collider.
static func spawn(parent: Node3D, at: Vector3, height: float, kind: String = "broadleaf", crown: String = "orange", variant: int = 0, solid: bool = false, yaw: float = 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Tree"
	parent.add_child(root)
	root.position = at
	root.rotation.y = yaw
	var scale := height / BUILD_HEIGHT
	root.scale = Vector3.ONE * scale
	var mesh := mesh_for(kind, crown, variant)
	var view := _Stylized.instance(mesh, WIND)
	view.name = "Look"
	root.add_child(view)
	if solid:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.radius = 0.35
		cylinder.height = 3.0
		shape.shape = cylinder
		shape.position.y = 1.5
		body.add_child(shape)
		root.add_child(body)
	return root


static func mesh_for(kind: String, crown: String, variant: int) -> ArrayMesh:
	var key := "%s|%s|%d" % [kind, crown, variant % VARIANTS]
	if not _cache.has(key):
		var seed_value := hash(key)
		_cache[key] = _pine(seed_value) if kind == "pine" else _broadleaf(seed_value, crown)
	return _cache[key]


static func _broadleaf(seed_value: int, crown: String) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var kit := _MeshKit.new()
	var height := BUILD_HEIGHT
	var colors: Array = CROWNS.get(crown, CROWNS["orange"])
	var trunk_height := height * rng.randf_range(0.3, 0.36)
	var base_radius := height * 0.05
	var lean := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized() * rng.randf_range(0.1, 0.35)
	var trunk := PackedVector3Array()
	var radii := PackedFloat32Array()
	for step: int in 5:
		var t := float(step) / 4.0
		trunk.append(Vector3(0.0, t * trunk_height, 0.0) + lean * t * t * trunk_height * 0.5)
		radii.append(lerpf(base_radius * 1.1, base_radius * 0.7, t))
	kit.tube(trunk, radii, BARK, 9, {"seed": seed_value, "flare": 0.45, "cap": false})
	var top := trunk[trunk.size() - 1]
	var crown_center := top + Vector3(0.0, (height - trunk_height) * 0.4, 0.0)
	var crown_radii := Vector3(height * 0.4, (height - trunk_height) * 0.5, height * 0.4)
	# Limbs fan out from the top of the trunk, each splitting once or twice.
	var tips: Array[Vector3] = []
	var limbs := rng.randi_range(4, 6)
	var turn := rng.randf_range(0.0, TAU)
	for limb: int in limbs:
		var angle := turn + TAU * float(limb) / float(limbs) + rng.randf_range(-0.35, 0.35)
		var rise := rng.randf_range(0.45, 0.9)
		var direction := Vector3(cos(angle), rise, sin(angle)).normalized()
		var start := top - Vector3(0.0, rng.randf_range(0.0, trunk_height * 0.3), 0.0)
		_limb(kit, rng, start, direction, height * rng.randf_range(0.28, 0.34), base_radius * 0.55, 1, tips)
	# A central leader keeps the crown from looking hollow on top.
	_limb(kit, rng, top, Vector3(rng.randf_range(-0.15, 0.15), 1.0, rng.randf_range(-0.15, 0.15)).normalized(), height * 0.24, base_radius * 0.5, 1, tips)
	# Leaf clumps: one on each limb tip, and a few big ones filling the middle.
	var clump := height * 0.18
	var index := 0
	var crown_start := kit.vertex_count()
	var leaf_options := {"detail": 2, "lumps": 0.38, "lump_scale": 0.9, "sway": 1.0, "jitter": 0.015, "soft": 0.8}
	var clumps: Array = []
	for tip: Vector3 in tips:
		index += 1
		var color := _crown_color(rng, colors, (tip.y - top.y) / maxf(crown_radii.y * 2.0, 0.1))
		var size := Vector3.ONE * clump * rng.randf_range(0.8, 1.2)
		size.y *= rng.randf_range(0.7, 0.85)
		leaf_options["seed"] = seed_value + index
		kit.blob(tip + Vector3(0.0, clump * 0.2, 0.0), size, color, leaf_options)
		clumps.append([tip + Vector3(0.0, clump * 0.2, 0.0), size, color])
	for filler: int in 3:
		var angle := TAU * float(filler) / 3.0 + rng.randf_range(-0.4, 0.4)
		var offset := Vector3(cos(angle) * 0.35, rng.randf_range(-0.2, 0.3), sin(angle) * 0.35) * crown_radii
		if filler == 0:
			offset = Vector3(0.0, crown_radii.y * 0.35, 0.0)
		var color := _crown_color(rng, colors, 0.5 + offset.y / maxf(crown_radii.y, 0.1) * 0.5)
		var size := Vector3(clump * 1.6, clump * 1.2, clump * 1.6) * rng.randf_range(0.9, 1.1)
		leaf_options["seed"] = seed_value + 100 + filler
		leaf_options["sway"] = 0.7
		kit.blob(crown_center + offset, size, color, leaf_options)
		clumps.append([crown_center + offset, size, color])
	# Loose leaves over every clump's surface break up the silhouette.
	for entry: Array in clumps:
		var at: Vector3 = entry[0]
		var size: Vector3 = entry[1]
		var color: Color = entry[2]
		for card: int in 40:
			var direction := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.4, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
			var spot := at + direction * size * rng.randf_range(1.0, 1.1)
			var tint := color.lerp(colors[1], rng.randf_range(0.0, 0.3))
			# Cards lie along the surface, tipped outward, lit like the clump under them.
			var facing := (direction + Vector3(0.0, 0.6, 0.0)).normalized()
			kit.leaf_card(spot, facing, clump * rng.randf_range(0.16, 0.24), tint, 1.0, rng.randf_range(0.0, TAU))
	var crown_bottom := crown_center.y - crown_radii.y * 1.1
	var crown_top := crown_center.y + crown_radii.y * 1.2
	kit.grade(crown_start, crown_bottom, crown_top, 0.62, 1.12)
	kit.occlude(crown_center, crown_radii * 1.2, 0.3)
	return kit.commit()


## A bent limb from start toward direction, which splits depth more times.
## Every final tip is added to tips, where leaf clumps go.
static func _limb(kit: RefCounted, rng: RandomNumberGenerator, start: Vector3, direction: Vector3, length: float, radius: float, depth: int, tips: Array[Vector3]) -> void:
	var points := PackedVector3Array()
	var radii := PackedFloat32Array()
	var heading := direction
	var at := start
	for step: int in 4:
		points.append(at)
		radii.append(lerpf(radius, radius * 0.6, float(step) / 3.0))
		# Limbs curve upward toward the light, with a little wander.
		heading = (heading + Vector3(rng.randf_range(-0.2, 0.2), 0.22, rng.randf_range(-0.2, 0.2))).normalized()
		at += heading * length / 3.0
	kit.call("tube", points, radii, BARK, 6, {"seed": rng.randi(), "sway_from": 0.0, "sway_to": 0.35, "cap": true})
	var end := points[points.size() - 1]
	if depth <= 0:
		tips.append(end)
		return
	var children := 2 if rng.randf() < 0.75 else 3
	for child: int in children:
		var side := heading.cross(Vector3.UP)
		if side.length() < 0.1:
			side = Vector3.RIGHT
		side = side.normalized().rotated(heading, rng.randf_range(0.0, TAU))
		var spread := rng.randf_range(0.35, 0.7)
		var next := (heading * cos(spread) + side * sin(spread)).normalized()
		_limb(kit, rng, end, next, length * rng.randf_range(0.6, 0.75), radius * 0.62, depth - 1, tips)


static func _crown_color(rng: RandomNumberGenerator, colors: Array, height_share: float) -> Color:
	var main: Color = colors[0]
	var other: Color = colors[1]
	var color := main.lerp(other, clampf(rng.randf_range(0.0, 0.45) + (height_share - 0.3) * 0.5, 0.0, 1.0))
	# Higher clumps catch more sun.
	return color.lightened(clampf(height_share, 0.0, 1.0) * 0.08)


static func _pine(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var kit := _MeshKit.new()
	var height := BUILD_HEIGHT * rng.randf_range(0.95, 1.1)
	var trunk := PackedVector3Array([Vector3.ZERO, Vector3(0.0, height * 0.5, 0.0), Vector3(0.0, height * 0.95, 0.0)])
	kit.tube(trunk, PackedFloat32Array([0.24, 0.15, 0.05]), BARK.darkened(0.1), 7, {"seed": seed_value, "flare": 0.3})
	var tiers := rng.randi_range(6, 7)
	var bottom := height * 0.16
	for tier: int in tiers:
		var t := float(tier) / float(tiers - 1)
		var base_y := lerpf(bottom, height * 0.8, t)
		var radius := lerpf(height * 0.3, height * 0.08, t) * rng.randf_range(0.92, 1.08)
		var tall := lerpf(height * 0.32, height * 0.24, t)
		var color := PINE_GREEN.lightened(t * 0.12 + rng.randf_range(-0.03, 0.03))
		kit.cone(Vector3(0.0, base_y, 0.0), radius, tall, color, 9, {"seed": seed_value + tier, "sway": lerpf(0.5, 1.0, t), "droop": radius * 0.22, "lumps": 0.14})
	kit.occlude(Vector3(0.0, height * 0.45, 0.0), Vector3(height * 0.3, height * 0.55, height * 0.3), 0.2)
	return kit.commit()
