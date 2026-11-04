extends RefCounted

## Authority: local, cosmetic. The little things that make the block and the
## store feel lived in (props/doodles.gd): sidewalk chalk, spray-paint tags on
## fences and walls, sticky notes on doors and mailboxes, and posters on lamp
## posts. The job's block (levels/town/block_builder.gd) calls dress_block with
## what it built; the store's follow levels/dressing/store_dressing.gd. Seeded,
## so every peer sees the same street.

const _Doodles = preload("res://props/doodles.gd")
const _BuildQueue = preload("res://levels/build_queue.gd")
## Loaded when the store is dressed, not preloaded: the block builder uses this
## file, and tools/mesh_check.gd (a --script run, where autoloads are not yet
## names) compiles it; preloading the store pulled in its shelves, which name
## Campaign, and printed a compile error on every mesh check.
const STORE_DRESSING: String = "res://levels/dressing/store_dressing.gd"
const CHALK_KINDS: Array[String] = ["smiley", "stick_figure", "sun", "house", "hearts"]
## Along the block's near sidewalk, where chalk drawings go (x, lot space); the
## hopscotch is in front of the yard's tools at x -9.
const CHALK_SPOTS: Array[float] = [-15.0, 7.0, 13.0, -30.0, 34.0, -55.0, 61.0]
## Lamp posts by kind (props/street_props.gd): [post radius at poster height, poster height].
const LAMP_POSTS: Dictionary = {
	"cobra": [0.1, 1.6], "acorn": [0.075, 1.6], "lantern": [0.065, 1.6], "post_lantern": [0.085, 1.55],
}
## The yard's mailbox by kind (props/street_props.gd, turned to face the street):
## [half width of the box, height of its middle], for the sticky note on its side.
const MAILBOX_SIDES: Dictionary = {
	"mailbox_post": [0.125, 1.15], "mailbox_brick": [0.29, 0.78], "mailbox_fancy": [0.145, 1.2],
	"mailbox_lighthouse": [0.24, 0.55],
}
## Posters hang at reading height (m), since cast:7 gave them words.
const STORE_POSTER_HEIGHT: float = 1.6
## The store lot's first poster seed (props/doodles.gd POSTERS: the depot's flyer first).
const STORE_POSTER_SEED: int = 2
## The checkout counter's sticky notes start at this seed (Doodles.NOTES: Gerald's
## return, the HOA, the side-of-the-fence complaint). Dale's rake note is Rusty's
## door's alone.
const COUNTER_NOTE_SEED: int = 34
## The connected town's lamp posters (dress_town_lamps): the poster's height up the
## post (m) and its size (m).
const TOWN_POSTER_HEIGHT: float = 1.6
## The town lamp's post radius (levels/dressing/neighborhood.gd _lamp).
const TOWN_POST_RADIUS: float = 0.09
const POSTER_SIZE := Vector2(0.3, 0.41)
## A sticky note on a mailbox or a shack door (m), and one on a counter or a
## front door (levels/lots/lot_generator.gd); net/dev/cast_test.gd checks the
## words fit both.
const NOTE_SIZE := Vector2(0.17, 0.17)
const NOTE_SIZE_LARGE := Vector2(0.19, 0.19)
## Rusty's yard (levels/dressing/shop_sites.gd): his door's note (Dale has his rake)
## and his fence's poster (Gerald is missing, at a pawn shop).
const RUSTYS_NOTE_SEED: int = 3
const RUSTYS_POSTER_SEED: int = 0


## The job's street block: posters on the near side's lamp posts, sidewalk chalk
## where the style has a sidewalk and chalk, spray-paint tags on a wood fence or
## cinderblock back wall (an HOA wall has none: its tags were painted over, in
## gray rectangles, by levels/town/set_pieces.gd), and a sticky note on the
## yard's mailbox. root is the block (lot space). opts (from the block):
##   lamp (the style's lamp kind), street_z (the road's middle), walk_z and
##   walk_width (the near sidewalk's middle and width, far_walk_z the far one's),
##   mailbox (the yard mailbox's kind) and mailbox_at, boundary_z (the back boundary)
## Each piece is a BuildQueue step (levels/build_queue.gd): a doodle draws its
## texture, and a block's worth took 170 ms in one frame.
static func dress_block(root: Node3D, lamps: PackedVector3Array, back_boundary: String, chalk: bool, seed_value: int, opts: Dictionary = {}) -> Node3D:
	var holder := _root(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "street_life"])
	var street_z := float(opts.get("street_z", 27.0))
	# Posters on the lamp posts along the yard's side of the street, on the yard's side of the post.
	# The block's seed picks where in Doodles.POSTERS its posts start, and each
	# poster down the street is the next one, so neighbors never repeat (seeding
	# from the lamp's x gave every post the same poster: the lamp spacings are
	# multiples of the poster count).
	var post: Array = LAMP_POSTS.get(str(opts.get("lamp", "")), [])
	var next_poster := posmod(hash([seed_value, "street_posters"]), _Doodles.POSTERS.size())
	if not post.is_empty():
		for lamp: Vector3 in lamps:
			if lamp.z > street_z:
				continue
			if rng.randf() < 0.6:
				var tilt := rng.randf_range(-0.12, 0.12)
				var poster_seed := next_poster
				next_poster += 1
				_BuildQueue.later(holder, func() -> void: _Doodles.place_poster(holder, poster_seed, lamp + Vector3(0.0, float(post[1]), -float(post[0]) - 0.012), Vector3.FORWARD, POSTER_SIZE, tilt), "street life")
	# Chalk on the sidewalks: a hopscotch in front of the yard, more down the block.
	if chalk and opts.has("walk_z"):
		var walk_z := float(opts["walk_z"])
		var far_z := float(opts.get("far_walk_z", walk_z))
		var across := minf(float(opts.get("walk_width", 2.0)) * 0.9, 1.8)
		_BuildQueue.later(holder, func() -> void: _Doodles.place_on_ground(holder, _Doodles.chalk("hopscotch", 1), Vector3(-9.0, 0.1, walk_z), Vector2(minf(1.3, across), 2.6), PI * 0.5), "street life")
		for index: int in CHALK_SPOTS.size():
			var z := walk_z if index % 2 == 0 else far_z
			var turn := rng.randf_range(-0.4, 0.4)
			_BuildQueue.later(holder, func() -> void: _Doodles.place_on_ground(holder, _Doodles.chalk(CHALK_KINDS[index % CHALK_KINDS.size()], index + 3), Vector3(CHALK_SPOTS[index], 0.1, z), Vector2(across, across), turn), "street life")
	# Tags on the back fence or wall, seen from the yard.
	var back_z := float(opts.get("boundary_z", Constants.ART_BACK_BOUNDARY_Z))
	match back_boundary:
		"wood_fence":
			# Between the privacy fence's rails, on its boards.
			for x: float in [-31.0, -9.5, 17.0, 46.0]:
				_BuildQueue.later(holder, func() -> void: _Doodles.place_on_wall(holder, _Doodles.graffiti(int(x) + 100), Vector3(x, 0.9, back_z + 0.02), Vector3.BACK, Vector2(2.2, 1.1)), "street life")
		"cinderblock":
			for x: float in [-31.0, -9.5, 17.0, 46.0, -58.0]:
				_BuildQueue.later(holder, func() -> void: _Doodles.place_on_wall(holder, _Doodles.graffiti(int(x) + 100), Vector3(x, 0.95, back_z + 0.16), Vector3.BACK, Vector2(4.2, 1.7)), "street life")
	# A sticky note on the yard's mailbox. The house changes every job, so its
	# door notes come from levels/lots/lot_generator.gd.
	var side: Array = MAILBOX_SIDES.get(str(opts.get("mailbox", "")), [])
	if not side.is_empty():
		var at: Vector3 = opts.get("mailbox_at", Vector3(3.2, 0.0, 19.9))
		var note_seed := posmod(hash([seed_value, "mailbox_note"]), 1 << 16)
		_BuildQueue.later(holder, func() -> void: _Doodles.place_note(holder, note_seed, at + Vector3(float(side[0]) + 0.01, float(side[1]), 0.0), Vector3.RIGHT, NOTE_SIZE, 0.15), "street life")
	return holder


static func dress_store(zone: Node3D) -> void:
	var root := _root(zone)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1110
	# Tags on the store's long side wall facing the parking lot.
	_BuildQueue.later(root, func() -> void: _Doodles.place_on_wall(root, _Doodles.graffiti(7), Vector3(-19.0, 2.4, 15.03), Vector3.BACK, Vector2(4.4, 2.2)), "street life")
	_BuildQueue.later(root, func() -> void: _Doodles.place_on_wall(root, _Doodles.graffiti(8), Vector3(-28.0, 1.9, 15.03), Vector3.BACK, Vector2(3.6, 1.8)), "street life")
	# Chalk on the asphalt by the spawn, and a hopscotch on the front walk.
	_BuildQueue.later(root, func() -> void: _Doodles.place_on_ground(root, _Doodles.chalk("smiley", 21), Vector3(4.5, 0.01, 10.5), Vector2(1.8, 1.8), 0.2), "street life")
	_BuildQueue.later(root, func() -> void: _Doodles.place_on_ground(root, _Doodles.chalk("stick_figure", 22), Vector3(-4.0, 0.01, 3.0), Vector2(1.5, 1.5), -0.3), "street life")
	_BuildQueue.later(root, func() -> void: _Doodles.place_on_ground(root, _Doodles.chalk("hopscotch", 23), Vector3(-10.4, 0.13, 8.0), Vector2(0.9, 1.8), 0.0), "street life")
	# Notes stuck to the checkout counter, and posters on the parking lights.
	for index: int in 3:
		_BuildQueue.later(root, func() -> void: _Doodles.place_note(root, COUNTER_NOTE_SEED + index,Vector3(-0.9 + float(index) * 0.35, 0.72 + rng.randf_range(-0.08, 0.08), -7.5), Vector3.BACK, NOTE_SIZE_LARGE, rng.randf_range(-0.3, 0.3)), "street life")
	# The lot's posters: Homie Depot's own flyer, a yard sale, and TurfMasters™
	# advertising in Marty's parking lot (Doodles.POSTERS from STORE_POSTER_SEED).
	var posters := 0
	for lamp: Vector3 in (load(STORE_DRESSING) as Script).get_script_constant_map()["LOT_LAMPS"]:
		if lamp.x < 0.0:
			continue
		var poster_seed := STORE_POSTER_SEED + posters
		posters += 1
		_BuildQueue.later(root, func() -> void: _Doodles.place_poster(root, poster_seed, lamp + Vector3(0.0, STORE_POSTER_HEIGHT, -0.1), Vector3.FORWARD, POSTER_SIZE, rng.randf_range(-0.12, 0.12)), "street life")


## The connected town's street lamps (net/town/town_map.gd lamp_spots, [at, yaw],
## their arm's +Z toward the road): a poster on one in four (Constants.WORDS_TOWN_POSTER_SHARE,
## seeded), three in four downtown (within WORDS_DOWNTOWN_M of downtown, the
## square), on the sidewalk side of the post
## at walking eye height. One BuildQueue step: the papers are cached by kind.
static func dress_town_lamps(root: Node3D, spots: Array, seed_value: int, downtown: Vector3) -> Node3D:
	var holder := _root(root)
	holder.name = "LampPosters"
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "lamp_posters"])
	var picks: Array = []
	for spot: Array in spots:
		var near := (spot[0] as Vector3).distance_to(downtown) < Constants.WORDS_DOWNTOWN_M
		if rng.randf() >= (Constants.WORDS_DOWNTOWN_POSTER_SHARE if near else Constants.WORDS_TOWN_POSTER_SHARE):
			continue
		picks.append([spot[0], float(spot[1]), rng.randi(), rng.randf_range(-0.12, 0.12)])
	_BuildQueue.later(holder, func() -> void:
		for pick: Array in picks:
			var turn := Basis(Vector3.UP, float(pick[1]))
			var out := turn * Vector3.FORWARD
			var at: Vector3 = (pick[0] as Vector3) + Vector3(0.0, TOWN_POSTER_HEIGHT, 0.0) + out * (TOWN_POST_RADIUS + 0.012)
			# The paper fades with its lamp (town_dressing._fade only reaches the
			# Lamps holder), a little sooner since it's small; its words keep
			# their own, shorter fade (Doodles.ink).
			_fade_paper(_Doodles.place_poster(holder, int(pick[2]), at, out, POSTER_SIZE, float(pick[3])), Constants.TOWN_SMALL_VISIBLE_METERS), "town lamp posters")
	return holder


## Sets a fade distance on a card's paper, back and seal, but not its ink.
static func _fade_paper(node: Node, meters: float) -> void:
	var geometry := node as GeometryInstance3D
	if geometry != null and not geometry is Label3D:
		geometry.visibility_range_end = meters
		geometry.visibility_range_end_margin = meters * 0.05
	for child: Node in node.get_children():
		_fade_paper(child, meters)


## Rusty's yard: a note on his shack's door (door_at: the door's face, facing
## door_normal) and a poster zip-tied to his fence by the gate (fence_at, facing
## fence_normal), in the shop site's space.
static func dress_rustys(root: Node3D, door_at: Vector3, door_normal: Vector3, fence_at: Vector3, fence_normal: Vector3) -> void:
	_BuildQueue.later(root, func() -> void:
		_Doodles.place_note(root, RUSTYS_NOTE_SEED, door_at, door_normal, NOTE_SIZE, -0.18)
		_Doodles.place_poster(root, RUSTYS_POSTER_SEED, fence_at, fence_normal, POSTER_SIZE, 0.05), "rustys street life")


static func _root(zone: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "StreetLife"
	zone.add_child(root)
	return root
