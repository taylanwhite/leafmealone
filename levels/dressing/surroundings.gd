extends RefCounted

## Authority: local, cosmetic. Ground to the horizon and a ring of trees and
## background houses around a zone, so the play pad doesn't float in the sky.
## Seeded, so every peer sees the same scenery. Nothing out here has collision.

const _LowPoly = preload("res://props/low_poly.gd")
const _Trees = preload("res://props/trees.gd")
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
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
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
