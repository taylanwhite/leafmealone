extends RefCounted

## Authority: local, cosmetic. Set dressing for the Border Return zone: lane
## dividers, low barriers down both sides, a striped arch over the exit end, and
## scrub and rocks outside the course. The lanes run from z -14 to +14 between
## x -8 and +8 (border/lane_layout.gd), and hazards live inside them, so nothing
## here goes inside that box. Generic road-works look, no real border iconography.

const _LowPoly = preload("res://props/low_poly.gd")
const LINE := Color(0.95, 0.94, 0.88)
const BARRIER := Color(0.92, 0.55, 0.15)
const POST := Color(0.9, 0.9, 0.86)
const ROCK := Color(0.6, 0.52, 0.42)
const SCRUB := Color(0.5, 0.55, 0.3)


static func dress(zone: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Dressing"
	zone.add_child(root)
	# Dashed dividers between the four lanes.
	for x: float in [-4.0, 0.0, 4.0]:
		for z: float in range(-13, 14, 3):
			_LowPoly.box(root, Vector3(0.15, 0.02, 1.5), Vector3(x, 0.012, z), LINE)
	# Striped barriers down both sides of the course.
	for side: float in [-1.0, 1.0]:
		for index: int in 10:
			var z := -13.5 + float(index) * 3.0
			var color := BARRIER if index % 2 == 0 else POST
			_LowPoly.box(root, Vector3(0.4, 0.9, 2.8), Vector3(side * 9.0, 0.45, z), color)
	# The exit arch at the far end.
	for side: float in [-1.0, 1.0]:
		_LowPoly.box(root, Vector3(0.8, 5.0, 0.8), Vector3(side * 9.0, 2.5, 15.5), POST)
	for index: int in 9:
		var color := BARRIER if index % 2 == 0 else POST
		_LowPoly.box(root, Vector3(2.0, 0.8, 0.8), Vector3(-8.0 + float(index) * 2.0, 5.4, 15.5), color)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for index: int in 24:
		var side := -1.0 if index % 2 == 0 else 1.0
		var at := Vector3(side * rng.randf_range(11.0, 19.0), 0.0, rng.randf_range(-18.0, 18.0))
		if rng.randf() < 0.5:
			var size := rng.randf_range(0.5, 1.4)
			_LowPoly.ball(root, size, at + Vector3(0, size * 0.4, 0), ROCK)
		else:
			_LowPoly.ball(root, 0.7, at + Vector3(0, 0.5, 0), SCRUB)
