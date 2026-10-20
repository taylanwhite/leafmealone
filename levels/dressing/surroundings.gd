extends RefCounted

## Authority: local, cosmetic. Ground to the horizon and a ring of trees and
## background houses around a zone, so the play pad doesn't float in the sky.
## Seeded, so every peer sees the same scenery. Nothing out here has collision.

const _LowPoly = preload("res://props/low_poly.gd")
const _Trees = preload("res://props/trees.gd")
const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const CLOUD_VARIANTS: int = 4

static var _cloud_meshes: Array[ArrayMesh] = []
const CROWNS: Array[String] = ["orange", "red", "yellow", "rust", "turning", "orange", "green"]
## Wide enough to reach the fog. Zones are 1000 m apart, so neighbors never overlap.
const GROUND_SIZE: float = 600.0
const PAD_HALF: float = 20.0
## Half-width of each ride corridor, in radians.
const CORRIDOR_HALF_ANGLE: float = 0.3


## clear_angles: directions (radians, atan2(z, x)) that rides drive out along, kept free of scenery.
static func dress(zone: Node3D, ground_color: Color, seed_value: int, with_houses: bool, clear_angles: Array[float] = [], ground_surface: String = "grass") -> void:
	var root := Node3D.new()
	root.name = "Surroundings"
	zone.add_child(root)
	# Level with the pad, a hair below, so the yard and the land around it are one ground.
	_LowPoly.paint(_LowPoly.box(root, Vector3(GROUND_SIZE, 0.2, GROUND_SIZE), Vector3(0, -0.12, 0), ground_color), ground_surface)
	# Solid, so a thrown item that sails over the yard's wall lands in the street.
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(GROUND_SIZE, 0.2, GROUND_SIZE)
	shape.shape = box
	shape.position.y = -0.12
	ground.add_child(shape)
	root.add_child(ground)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_clouds(root, rng)
	for index: int in 70:
		var angle := rng.randf() * TAU
		var distance := rng.randf_range(PAD_HALF + 6.0, 90.0)
		if _in_corridor(angle, clear_angles):
			continue
		var at := Vector3(cos(angle) * distance, -0.02, sin(angle) * distance)
		if rng.randf() < 0.3:
			_Trees.spawn(root, at, rng.randf_range(7.0, 11.0), "pine", "", index, false, rng.randf() * TAU)
		else:
			_Trees.spawn(root, at, rng.randf_range(5.5, 8.5), "broadleaf", CROWNS[rng.randi() % CROWNS.size()], index, false, rng.randf() * TAU)
	if not with_houses:
		return
	var walls: Array[Color] = [Color(0.85, 0.78, 0.62), Color(0.62, 0.72, 0.8), Color(0.82, 0.6, 0.5), Color(0.75, 0.8, 0.62)]
	for index: int in 10:
		var angle := float(index) / 10.0 * TAU + rng.randf_range(-0.2, 0.2)
		var distance := rng.randf_range(40.0, 60.0)
		if _in_corridor(angle, clear_angles):
			continue
		var at := Vector3(cos(angle) * distance, -0.02, sin(angle) * distance)
		_house(root, at, walls[index % walls.size()], -angle + PI * 0.5)


## Puffy low-poly clouds well out past the trees, high up, drifting nowhere.
static func _clouds(root: Node3D, rng: RandomNumberGenerator) -> void:
	if _cloud_meshes.is_empty():
		for variant: int in CLOUD_VARIANTS:
			_cloud_meshes.append(_cloud_mesh(variant))
	for index: int in 14:
		var angle := rng.randf() * TAU
		var distance := rng.randf_range(170.0, 320.0)
		var cloud := MeshInstance3D.new()
		cloud.name = "Cloud"
		cloud.mesh = _cloud_meshes[index % CLOUD_VARIANTS]
		cloud.material_override = _Stylized.cloud_material()
		cloud.set_meta("keep_material", true)
		cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(cloud)
		cloud.position = Vector3(cos(angle) * distance, rng.randf_range(55.0, 95.0), sin(angle) * distance)
		cloud.rotation.y = rng.randf() * TAU
		cloud.scale = Vector3.ONE * rng.randf_range(0.8, 1.5)


## A cloud: a row of white puffs, flat underneath, shaded a little gray below.
static func _cloud_mesh(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + variant
	var kit := _MeshKit.new()
	var puffs := rng.randi_range(4, 7)
	var length := float(puffs) * 7.0
	for index: int in puffs:
		var x := -length * 0.5 + (float(index) + 0.5) * length / float(puffs)
		var size := rng.randf_range(6.0, 10.0) * (1.0 - absf(x) / length * 0.8)
		kit.blob(Vector3(x, size * 0.35, rng.randf_range(-3.0, 3.0)), Vector3(size, size * 0.75, size * 0.85), Color(1.0, 0.99, 0.97), {"detail": 2, "lumps": 0.15, "flat": false, "jitter": 0.0, "seed": variant * 10 + index})
	kit.grade(0, -2.0, 10.0, 0.84, 1.0)
	return kit.commit()


static func _in_corridor(angle: float, clear_angles: Array[float]) -> bool:
	for clear: float in clear_angles:
		if absf(angle_difference(angle, clear)) < CORRIDOR_HALF_ANGLE:
			return true
	return false


static func _house(root: Node3D, at: Vector3, wall: Color, yaw: float) -> void:
	var house := Node3D.new()
	root.add_child(house)
	house.position = at
	house.rotation.y = yaw
	_LowPoly.paint(_LowPoly.box(house, Vector3(8.0, 4.0, 6.0), Vector3(0, 2.0, 0), wall), "siding")
	var roof := _LowPoly.roof(house, 6.8, 2.4, 8.8, Vector3(0, 5.2, 0), Color(0.36, 0.25, 0.22))
	roof.rotation.y = PI * 0.5
	_LowPoly.paint(roof, "shingles")
	_LowPoly.paint(_LowPoly.box(house, Vector3(1.0, 2.0, 0.08), Vector3(0, 1.0, 3.02), Color(0.3, 0.22, 0.18)), "planks")
