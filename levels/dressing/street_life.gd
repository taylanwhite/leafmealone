extends RefCounted

## Authority: local, cosmetic. The little things that make the block and the
## store feel lived in (props/doodles.gd): sidewalk chalk, spray-paint tags on
## fences and walls, sticky notes on doors and mailboxes, and posters on lamp
## posts. Positions follow the layouts in levels/dressing/neighborhood.gd,
## levels/lots/lot_01.tscn, and levels/dressing/store_dressing.gd. Seeded, so
## every peer sees the same street.

const _Doodles = preload("res://props/doodles.gd")
const CHALK_KINDS: Array[String] = ["smiley", "stick_figure", "sun", "house", "hearts"]


static func dress_lot(zone: Node3D) -> void:
	var root := _root(zone)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2210
	# Chalk on the sidewalk in front of the yard and down the block.
	_Doodles.place_on_ground(root, _Doodles.chalk("hopscotch", 1), Vector3(-9.0, 0.1, 21.3), Vector2(1.3, 2.6), PI * 0.5)
	var spots: Array[float] = [-15.0, 7.0, 13.0, -30.0, 34.0, -55.0, 61.0]
	for index: int in spots.size():
		_Doodles.place_on_ground(root, _Doodles.chalk(CHALK_KINDS[index % CHALK_KINDS.size()], index + 3), Vector3(spots[index], 0.1, 21.3 if index % 2 == 0 else 32.7), Vector2(1.8, 1.8), rng.randf_range(-0.4, 0.4))
	# Tags on the back fence, seen from the yard.
	for x: float in [-31.0, -9.5, 17.0, 46.0]:
		_Doodles.place_on_wall(root, _Doodles.graffiti(int(x) + 100), Vector3(x, 0.95, -23.96), Vector3.BACK, Vector2(4.2, 2.1))
	# A sticky note on the yard's mailbox. The house changes every job, so its
	# door notes come from levels/lots/lot_generator.gd.
	_Doodles.place_paper(root, _Doodles.note(14), Vector3(3.43, 1.27, 19.9), Vector3.RIGHT, Vector2(0.17, 0.17), 0.15)
	# Posters on the lamp posts along this side of the street.
	for x: float in range(-114, 127, 24):
		if rng.randf() < 0.6:
			_Doodles.place_paper(root, _Doodles.poster(int(x) + 300), Vector3(float(x), 2.1, 21.85), Vector3.FORWARD, Vector2(0.3, 0.41), rng.randf_range(-0.12, 0.12))


static func dress_store(zone: Node3D) -> void:
	var root := _root(zone)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1110
	# Tags on the store's long side wall facing the parking lot.
	_Doodles.place_on_wall(root, _Doodles.graffiti(7), Vector3(-19.0, 2.4, 15.03), Vector3.BACK, Vector2(4.4, 2.2))
	_Doodles.place_on_wall(root, _Doodles.graffiti(8), Vector3(-28.0, 1.9, 15.03), Vector3.BACK, Vector2(3.6, 1.8))
	# Chalk on the asphalt by the spawn, and a hopscotch on the front walk.
	_Doodles.place_on_ground(root, _Doodles.chalk("smiley", 21), Vector3(4.5, 0.01, 10.5), Vector2(1.8, 1.8), 0.2)
	_Doodles.place_on_ground(root, _Doodles.chalk("stick_figure", 22), Vector3(-4.0, 0.01, 3.0), Vector2(1.5, 1.5), -0.3)
	_Doodles.place_on_ground(root, _Doodles.chalk("hopscotch", 23), Vector3(-10.4, 0.13, 8.0), Vector2(0.9, 1.8), 0.0)
	# Notes stuck to the checkout counter, and posters on the parking lights.
	for index: int in 3:
		_Doodles.place_paper(root, _Doodles.note(30 + index), Vector3(-0.9 + float(index) * 0.35, 0.72 + rng.randf_range(-0.08, 0.08), -7.5), Vector3.BACK, Vector2(0.19, 0.19), rng.randf_range(-0.3, 0.3))
	for lamp: Vector3 in [Vector3(17.0, 0.0, 17.0), Vector3(17.0, 0.0, -17.0), Vector3(4.0, 0.0, 17.0)]:
		_Doodles.place_paper(root, _Doodles.poster(int(lamp.x + lamp.z) + 500), lamp + Vector3(0.0, 2.1, -0.1), Vector3.FORWARD, Vector2(0.3, 0.41), rng.randf_range(-0.12, 0.12))


static func _root(zone: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "StreetLife"
	zone.add_child(root)
	return root
