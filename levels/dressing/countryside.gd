extends RefCounted

## Authority: local, cosmetic. The country between Homie Depot and the town's
## streets, so Chefty's ride passes something: the road it drives on, grass,
## trees in the season's colors, fence lines, and the odd house. Built once in
## world space along Chefty's route (net/components/ride.gd: the store at x 0,
## the yards at x 1000). Seeded, so every peer sees the same drive. Nothing here
## collides. The grass sits a little below the zones' own ground, so the two
## never fight where they overlap.

const _LowPoly = preload("res://props/low_poly.gd")
const _Trees = preload("res://props/trees.gd")
const _Neighborhood = preload("res://levels/dressing/neighborhood.gd")
const ASPHALT := Color(0.3, 0.3, 0.32)
const LINE_YELLOW := Color(0.93, 0.78, 0.3)
const GRASS := Color(0.42, 0.52, 0.3)
const FENCE := Color(0.55, 0.42, 0.3)
const CROWNS: Array[String] = ["orange", "red", "yellow", "rust", "turning"]
## The stretch of Chefty's route with no zone around it, as road points (x, z).
const ROUTE: Array[Vector2] = [Vector2(290.0, 14.9), Vector2(500.0, 20.0), Vector2(880.0, 24.0)]


static func dress(world: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Countryside"
	world.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1101
	# Grass under the whole stretch, below the zones' ground.
	_LowPoly.paint(_LowPoly.box(root, Vector3(700.0, 0.1, 260.0), Vector3(585.0, -0.16, 20.0), GRASS), "grass")
	for index: int in ROUTE.size() - 1:
		_road(root, ROUTE[index], ROUTE[index + 1])
	# Trees, fences, and houses on both sides of the road.
	var x := ROUTE[0].x + 10.0
	while x < ROUTE[ROUTE.size() - 1].x - 10.0:
		var road_z := _road_z(x)
		for side: float in [-1.0, 1.0]:
			if rng.randf() < 0.8:
				var off := rng.randf_range(10.0, 34.0)
				var kind := "pine" if rng.randf() < 0.25 else "broadleaf"
				_Trees.spawn(root, Vector3(x + rng.randf_range(-6.0, 6.0), 0.0, road_z + side * off), rng.randf_range(6.5, 9.5), kind, CROWNS[rng.randi() % CROWNS.size()], rng.randi() % 4, false, rng.randf() * TAU)
		x += rng.randf_range(14.0, 22.0)
	# Fence lines along a few fields.
	for field: int in 6:
		var start := rng.randf_range(ROUTE[0].x + 20.0, ROUTE[ROUTE.size() - 1].x - 80.0)
		var side := -1.0 if field % 2 == 0 else 1.0
		var length := rng.randf_range(40.0, 70.0)
		var z := _road_z(start) + side * rng.randf_range(8.0, 9.0)
		for post: int in int(length / 4.0):
			var at := Vector3(start + float(post) * 4.0, 0.0, z)
			_LowPoly.box(root, Vector3(0.14, 1.1, 0.14), at + Vector3(0.0, 0.55, 0.0), FENCE)
			_LowPoly.box(root, Vector3(4.0, 0.1, 0.06), at + Vector3(2.0, 0.85, 0.0), FENCE)
			_LowPoly.box(root, Vector3(4.0, 0.1, 0.06), at + Vector3(2.0, 0.45, 0.0), FENCE)
	# A farmhouse now and then, set back from the road and facing it.
	var house_x := ROUTE[0].x + 60.0
	while house_x < ROUTE[ROUTE.size() - 1].x - 60.0:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var at := Vector3(house_x, 0.0, _road_z(house_x) + side * rng.randf_range(42.0, 55.0))
		var holder := Node3D.new()
		holder.name = "Farmhouse"
		root.add_child(holder)
		holder.position = at
		holder.rotation.y = 0.0 if side < 0.0 else PI
		_Neighborhood.house(holder, Vector3.ZERO, rng.randf_range(9.0, 12.0), rng.randf_range(7.0, 9.0), 1 + int(rng.randf() < 0.4), _Neighborhood.WALLS[rng.randi() % _Neighborhood.WALLS.size()], _Neighborhood.ROOFS[rng.randi() % _Neighborhood.ROOFS.size()], _Neighborhood.TRIMS[rng.randi() % _Neighborhood.TRIMS.size()], rng.randf() < 0.5)
		house_x += rng.randf_range(110.0, 170.0)


## The road's z at x along the route.
static func _road_z(x: float) -> float:
	for index: int in ROUTE.size() - 1:
		var a := ROUTE[index]
		var b := ROUTE[index + 1]
		if x >= a.x and x <= b.x:
			return lerpf(a.y, b.y, (x - a.x) / (b.x - a.x))
	return ROUTE[ROUTE.size() - 1].y


## Asphalt and a dashed center line, with fewer dashes than a town street.
static func _road(root: Node3D, from: Vector2, to: Vector2) -> void:
	var holder := Node3D.new()
	holder.name = "CountryRoad"
	root.add_child(holder)
	var flat := Vector2(to.x - from.x, to.y - from.y)
	var length := flat.length()
	holder.position = Vector3((from.x + to.x) * 0.5, 0.0, (from.y + to.y) * 0.5)
	holder.rotation.y = atan2(-flat.y, flat.x)
	_LowPoly.paint(_LowPoly.box(holder, Vector3(length + 2.0, 0.1, 8.0), Vector3(0.0, -0.06, 0.0), ASPHALT), "asphalt")
	var x := -length * 0.5
	while x < length * 0.5 - 4.0:
		_LowPoly.box(holder, Vector3(4.0, 0.02, 0.14), Vector3(x + 2.0, 0.0, 0.0), LINE_YELLOW)
		x += 12.0
