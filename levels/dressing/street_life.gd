extends RefCounted

## Authority: local, cosmetic. The little things that make the block and the
## store feel lived in (props/doodles.gd): sidewalk chalk, spray-paint tags on
## fences and walls, sticky notes on doors and mailboxes, and posters on lamp
## posts. The job's block (levels/town/block_builder.gd) calls dress_block with
## what it built; the store's follow levels/dressing/store_dressing.gd. Seeded,
## so every peer sees the same street.

const _Doodles = preload("res://props/doodles.gd")
const _StoreDressing = preload("res://levels/dressing/store_dressing.gd")
const CHALK_KINDS: Array[String] = ["smiley", "stick_figure", "sun", "house", "hearts"]
## Along the block's near sidewalk, where chalk drawings go (x, lot space); the
## hopscotch is in front of the yard's tools at x -9.
const CHALK_SPOTS: Array[float] = [-15.0, 7.0, 13.0, -30.0, 34.0, -55.0, 61.0]
## Lamp posts by kind (props/street_props.gd): [post radius at poster height, poster height].
const LAMP_POSTS: Dictionary = {
	"cobra": [0.1, 2.1], "acorn": [0.075, 2.0], "lantern": [0.065, 2.0], "post_lantern": [0.085, 1.6],
}
## The yard's mailbox by kind (props/street_props.gd, turned to face the street):
## [half width of the box, height of its middle], for the sticky note on its side.
const MAILBOX_SIDES: Dictionary = {
	"mailbox_post": [0.125, 1.15], "mailbox_brick": [0.29, 0.78], "mailbox_fancy": [0.145, 1.2],
	"mailbox_lighthouse": [0.24, 0.55],
}


## The job's street block: posters on the near side's lamp posts, sidewalk chalk
## where the style has a sidewalk and chalk, spray-paint tags on a wood fence or
## cinderblock back wall (an HOA wall has none: its tags were painted over, in
## gray rectangles, by levels/town/set_pieces.gd), and a sticky note on the
## yard's mailbox. root is the block (lot space). opts (from the block):
##   lamp (the style's lamp kind), street_z (the road's middle), walk_z and
##   walk_width (the near sidewalk's middle and width, far_walk_z the far one's),
##   mailbox (the yard mailbox's kind) and mailbox_at, boundary_z (the back boundary)
static func dress_block(root: Node3D, lamps: PackedVector3Array, back_boundary: String, chalk: bool, seed_value: int, opts: Dictionary = {}) -> Node3D:
	var holder := _root(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "street_life"])
	var street_z := float(opts.get("street_z", 27.0))
	# Posters on the lamp posts along the yard's side of the street, on the yard's side of the post.
	var post: Array = LAMP_POSTS.get(str(opts.get("lamp", "")), [])
	if not post.is_empty():
		for lamp: Vector3 in lamps:
			if lamp.z > street_z:
				continue
			if rng.randf() < 0.6:
				_Doodles.place_paper(holder, _Doodles.poster(int(lamp.x) + 300), lamp + Vector3(0.0, float(post[1]), -float(post[0]) - 0.012), Vector3.FORWARD, Vector2(0.3, 0.41), rng.randf_range(-0.12, 0.12))
	# Chalk on the sidewalks: a hopscotch in front of the yard, more down the block.
	if chalk and opts.has("walk_z"):
		var walk_z := float(opts["walk_z"])
		var far_z := float(opts.get("far_walk_z", walk_z))
		var across := minf(float(opts.get("walk_width", 2.0)) * 0.9, 1.8)
		_Doodles.place_on_ground(holder, _Doodles.chalk("hopscotch", 1), Vector3(-9.0, 0.1, walk_z), Vector2(minf(1.3, across), 2.6), PI * 0.5)
		for index: int in CHALK_SPOTS.size():
			var z := walk_z if index % 2 == 0 else far_z
			_Doodles.place_on_ground(holder, _Doodles.chalk(CHALK_KINDS[index % CHALK_KINDS.size()], index + 3), Vector3(CHALK_SPOTS[index], 0.1, z), Vector2(across, across), rng.randf_range(-0.4, 0.4))
	# Tags on the back fence or wall, seen from the yard.
	var back_z := float(opts.get("boundary_z", Constants.ART_BACK_BOUNDARY_Z))
	match back_boundary:
		"wood_fence":
			# Between the privacy fence's rails, on its boards.
			for x: float in [-31.0, -9.5, 17.0, 46.0]:
				_Doodles.place_on_wall(holder, _Doodles.graffiti(int(x) + 100), Vector3(x, 0.9, back_z + 0.02), Vector3.BACK, Vector2(2.2, 1.1))
		"cinderblock":
			for x: float in [-31.0, -9.5, 17.0, 46.0, -58.0]:
				_Doodles.place_on_wall(holder, _Doodles.graffiti(int(x) + 100), Vector3(x, 0.95, back_z + 0.16), Vector3.BACK, Vector2(4.2, 1.7))
	# A sticky note on the yard's mailbox. The house changes every job, so its
	# door notes come from levels/lots/lot_generator.gd.
	var side: Array = MAILBOX_SIDES.get(str(opts.get("mailbox", "")), [])
	if not side.is_empty():
		var at: Vector3 = opts.get("mailbox_at", Vector3(3.2, 0.0, 19.9))
		_Doodles.place_paper(holder, _Doodles.note(14), at + Vector3(float(side[0]) + 0.01, float(side[1]), 0.0), Vector3.RIGHT, Vector2(0.17, 0.17), 0.15)
	return holder


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
	for lamp: Vector3 in _StoreDressing.LOT_LAMPS:
		if lamp.x < 0.0:
			continue
		_Doodles.place_paper(root, _Doodles.poster(int(lamp.x + lamp.z) + 500), lamp + Vector3(0.0, 2.1, -0.1), Vector3.FORWARD, Vector2(0.3, 0.41), rng.randf_range(-0.12, 0.12))


static func _root(zone: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "StreetLife"
	zone.add_child(root)
	return root
