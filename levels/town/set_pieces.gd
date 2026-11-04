extends RefCounted

## Authority: local, cosmetic. Each neighborhood's block-scale pieces
## (docs/GAME.md, "the neighborhood looks"): Lakeside's lake and docks, Mansion
## Hill's terrace, Oak Hollow's gatehouse and rules board, entrance signs,
## Dandelion Acres' park office and mailbox kiosks, Maple Row's watch sign, and
## the back boundary behind the yards. Built in block space (the lot's space for
## the job's block: the street runs along x at z 22.6..31.4, the yards' fronts
## at z +20). Each piece is a pure function of its arguments, joins group
## "art_signature:<id>" for the art test, and has no collision (the job yard's
## pad walls keep players in; the drivable town adds its own colliders).

const _PropCatalog = preload("res://props/prop_catalog.gd")
const _PropBatch = preload("res://props/prop_batch.gd")
const _MeshKit = preload("res://props/mesh_kit.gd")
const _HouseKit = preload("res://props/house_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const _P = preload("res://props/prop_parts.gd")
const _Water = preload("res://props/water_surface.gd")
const _Trees = preload("res://props/trees.gd")
const _HouseBuilder = preload("res://levels/town/house_builder.gd")
const _Parcel = preload("res://levels/town/parcel.gd")

const SAND := Color(0.86, 0.78, 0.58)
const STONE := Color(0.7, 0.68, 0.62)
const CINDER := Color(0.6, 0.6, 0.58)
const HOA_BEIGE := Color(0.86, 0.82, 0.74)
const PAINTED_OVER := Color(0.66, 0.66, 0.64)
const BOARD_GREEN := Color(0.16, 0.36, 0.22)
const BOARD_WOOD := Color(0.56, 0.4, 0.26)
const POST := Color(0.38, 0.3, 0.22)
## The lake's surface height (above the ground's -0.02 top, under the sand's).
const WATER_Y: float = 0.08
const SAND_TOP: float = 0.1


## A sign on posts: a board size (width x height) with a Strings.SIGNS key's
## words on its front (-Z, like every prop; turn it with yaw), its bottom
## clearance above the ground. look: "wood" (a hand-made board), "green" (a
## painted metal board), "beige" (Oak Hollow), "white".
static func sign_post(parent: Node3D, at: Vector3, yaw: float, key: String, size: Vector2 = Vector2(1.6, 0.9), clearance: float = 1.1, look: String = "wood", group: String = "") -> Node3D:
	var root := Node3D.new()
	root.name = "Sign_%s" % key.to_pascal_case()
	root.transform = Transform3D(Basis(Vector3.UP, yaw), at)
	parent.add_child(root)
	var board: Color = BOARD_WOOD
	var ink := Color(0.98, 0.96, 0.9)
	var post := POST
	match look:
		"green":
			board = BOARD_GREEN
			post = _P.DARK_STEEL
		"beige":
			board = HOA_BEIGE
			ink = Color(0.24, 0.2, 0.16)
			post = Color(0.95, 0.94, 0.9)
		"white":
			board = Color(0.95, 0.95, 0.93)
			ink = Color(0.2, 0.16, 0.14)
			post = _P.DARK_STEEL
	var kit := _MeshKit.new()
	var top := clearance + size.y
	for side: float in [-1.0, 1.0]:
		_P.post(kit, Vector3(side * size.x * 0.38, 0.0, 0.04), top + 0.1, 0.05, post, 6)
	_P.slab(kit, Vector3(0.0, clearance + size.y * 0.5, 0.0), Vector3(size.x, size.y, 0.06), board)
	_P.slab(kit, Vector3(0.0, top + 0.04, 0.0), Vector3(size.x + 0.1, 0.08, 0.1), board.darkened(0.25))
	_mesh(root, kit, "Board")
	_words(root, key, Vector3(0.0, clearance + size.y * 0.5, -0.035), size.x * 0.9, ink)
	if group != "":
		root.add_to_group("art_signature:%s" % group)
	return root


## Maple Row's NEIGHBORHOOD WATCH sign, bolted to a street lamp's pole at
## lamp_at, facing the way Chefty comes in (-x).
static func neighborhood_watch_sign(parent: Node3D, lamp_at: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "WatchSign"
	root.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), lamp_at)
	parent.add_child(root)
	var kit := _MeshKit.new()
	_P.slab(kit, Vector3(0.0, 2.55, 0.0), Vector3(0.62, 0.78, 0.04), Color(0.96, 0.96, 0.92))
	_P.slab(kit, Vector3(0.0, 2.88, -0.005), Vector3(0.6, 0.14, 0.04), Color(0.12, 0.2, 0.42))
	# An eye, watching.
	_P.ball(kit, Vector3(0.0, 2.36, -0.03), Vector3(0.12, 0.07, 0.02), Color(0.98, 0.98, 0.96), 0)
	_P.ball(kit, Vector3(0.0, 2.36, -0.045), Vector3(0.045, 0.045, 0.02), Color(0.1, 0.1, 0.12), 0)
	for y: float in [2.25, 2.85]:
		_P.slab(kit, Vector3(0.0, y, 0.06), Vector3(0.05, 0.05, 0.14), _P.DARK_STEEL)
	_mesh(root, kit, "Board")
	_words(root, "watch_maple", Vector3(0.0, 2.62, -0.025), 0.56, Color(0.12, 0.2, 0.42), 26, 0.0026)
	root.add_to_group("art_signature:watch_sign")
	return root


## A neighborhood's entrance sign at at, its face toward -Z turned by yaw:
## kind "monument" (brick or stone wall), "arch" (Dandelion Acres' hand-made
## arch, 6.3 m between the posts), or "wooden" (a routed board on posts).
static func entrance_sign(parent: Node3D, at: Vector3, yaw: float, key: String, kind: String = "monument", color: Color = Color.WHITE) -> Node3D:
	var xform := Transform3D(Basis(Vector3.UP, yaw), at)
	var placed: Node3D
	match kind:
		"arch":
			placed = _PropCatalog.place(parent, "entrance_arch", xform, color, {"sign": key})
		"wooden":
			placed = sign_post(parent, at, yaw, key, Vector2(2.6, 1.2), 0.6, "wood")
		_:
			placed = _PropCatalog.place(parent, "monument_sign", xform, color, {"sign": key})
	placed.add_to_group("art_signature:entrance_sign")
	return placed


## Oak Hollow's gatehouse: the booth on the near side at at with its striped
## arm reaching across the road toward +z.
static func hoa_gatehouse(parent: Node3D, at: Vector3) -> Node3D:
	return _PropCatalog.place(parent, "gatehouse", Transform3D(Basis(Vector3.UP, -PI * 0.5), at), HOA_BEIGE, {"sign": "hoa_gate"})


## Oak Hollow's rules board, the one by the sidewalk everybody reads twice.
static func hoa_rules_board(parent: Node3D, at: Vector3, yaw: float) -> Node3D:
	var board := sign_post(parent, at, yaw, "hoa_rules", Vector2(2.2, 1.5), 0.7, "beige", "hoa_sign")
	return board


## Dandelion Acres' park office: a single-wide with an OFFICE sign in the yard
## (rent is due Friday) and a flag of a dandelion. Facing +Z from at, turned by yaw.
static func park_office(parent: Node3D, at: Vector3, yaw: float, seed_value: int) -> Node3D:
	var root := Node3D.new()
	root.name = "ParkOffice"
	root.transform = Transform3D(Basis(Vector3.UP, yaw), at)
	parent.add_child(root)
	_HouseBuilder.build(root, Vector3.ZERO, {
		"archetype": "single_wide", "width": 11.0, "depth": 6.5, "stories": 1, "seed": seed_value,
		"wall": Color(0.95, 0.88, 0.62), "wall_surface": "corrugated", "roof": Color(0.86, 0.86, 0.84), "roof_surface": "corrugated",
		"trim": Color(0.94, 0.94, 0.9), "door": Color(0.3, 0.42, 0.6), "accent": Color(0.3, 0.52, 0.66),
	})
	sign_post(root, Vector3(3.6, 0.0, 6.4), PI, "dandelion_office", Vector2(1.8, 1.0), 0.8, "white")
	root.add_to_group("art_signature:park_office")
	return root


## Dandelion Acres' cluster mailboxes: a little concrete pad with two kiosks and
## the mail's own sign, at at, the doors facing -Z turned by yaw.
static func cluster_mailboxes(parent: Node3D, at: Vector3, yaw: float, batch: RefCounted) -> Node3D:
	var root := Node3D.new()
	root.name = "ClusterMailboxes"
	root.transform = Transform3D(Basis(Vector3.UP, yaw), at)
	parent.add_child(root)
	var kit := _HouseKit.new()
	kit.call("box", Vector3(4.2, 0.12, 2.0), Vector3(0.0, 0.06, 0.0), Color(0.7, 0.68, 0.64), "concrete")
	kit.call("commit", root, "Pad")
	for x: float in [-1.0, 1.0]:
		batch.call("add", "mailbox_cluster", root.transform * Transform3D(Basis.IDENTITY, Vector3(x, 0.12, 0.0)))
	sign_post(root, Vector3(2.6, 0.0, 0.4), 0.0, "dandelion_mail", Vector2(1.2, 0.7), 0.9, "white")
	root.add_to_group("art_signature:cluster_mailboxes")
	return root


## Lakeside's lake behind the yards: the water from shore_z out to shore_z -
## length across width (block x), a sand strip up to the back fence, pines along
## the far shore in the haze, frozen with a fishing shanty in winter (the root is
## a levels/town/parcel.gd "lake", so it turns with the season).
static func lake(parent: Node3D, width: float, shore_z: float, length: float, season: int, seed_value: int) -> Node3D:
	var root: Node3D = _Parcel.new()
	root.name = "Lake"
	root.set("role", "lake")
	root.set("seed_value", seed_value)
	parent.add_child(root)
	var water := _Water.plane(Vector2(width, length), _Water.lake_kind(season), 48)
	water.name = "Water"
	water.position = Vector3(0.0, WATER_Y, shore_z - length * 0.5)
	root.add_child(water)
	var kit := _HouseKit.new()
	var sand_from := Constants.ART_BACK_BOUNDARY_Z - 0.4
	var sand_to := shore_z - 0.6
	kit.call("box", Vector3(width, 0.2, sand_from - sand_to), Vector3(0.0, SAND_TOP - 0.1, (sand_from + sand_to) * 0.5), SAND, "dirt", Basis.IDENTITY, {"accent": SAND.darkened(0.12)})
	kit.call("commit", root, "Beach")
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "far_shore"])
	var far_z := shore_z - length
	var x := -width * 0.5 + 6.0
	var index := 0
	while x < width * 0.5 - 6.0:
		_Trees.spawn(root, Vector3(x, 0.0, far_z - rng.randf_range(3.0, 14.0)), rng.randf_range(10.0, 15.0), "pine", "", index, false, rng.randf() * TAU)
		x += rng.randf_range(9.0, 16.0)
		index += 1
	root.set("decor", {"shanty": Vector3(rng.randf_range(-30.0, 30.0), WATER_Y - 0.05, shore_z - rng.randf_range(35.0, 55.0))})
	root.set("season", -1)
	root.call("apply_season", season)
	root.add_to_group("art_signature:lake")
	# It freezes over in winter (parcel.gd), and then neither laps nor has a loon.
	shore(root, Vector3(-width * 0.5, WATER_Y, shore_z), Vector3(width * 0.5, WATER_Y, shore_z), Vector3.FORWARD).set_meta("ambient_freezes", true)
	return root


## The lake's edge as a sound source (art:9, audio/ambience.gd): the water
## lapping along the line from a to b (parent space) wherever along it is
## nearest you, and the loon out over the water, toward out.
static func shore(parent: Node3D, a: Vector3, b: Vector3, out: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = "Shore"
	parent.add_child(node)
	node.add_to_group("ambient_emitters")
	node.set_meta("ambient", "lake_lap_loop")
	node.set_meta("ambient_line", PackedVector3Array([a, b]))
	node.set_meta("ambient_out", out)
	return node


## A dock behind each yard at xs (block x), from the shore out over the lake,
## boats tied up at some (always at least min_boats), buoys, a swim platform,
## and a kayak rack on the sand.
static func docks_for(parent: Node3D, xs: Array, shore_z: float, seed_value: int, batch: RefCounted, min_boats: int = 2) -> Node3D:
	var root := Node3D.new()
	root.name = "Docks"
	parent.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "docks"])
	var boats := 0
	for index: int in xs.size():
		var x := float(xs[index]) + rng.randf_range(-3.0, 3.0)
		var length := rng.randf_range(8.0, 12.0)
		batch.call("add", "dock", Transform3D(Basis.IDENTITY, Vector3(x, 0.0, shore_z + 0.6)), Color.WHITE, Vector3(2.0, 0.0, length))
		var wants_boat := boats < min_boats and xs.size() - index <= min_boats - boats
		if wants_boat or rng.randf() < 0.55:
			var kind := "boat_motor" if rng.randf() < 0.5 else "boat_row"
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			var at := Vector3(x + side * 2.3, WATER_Y - 0.32, shore_z - length * 0.55)
			_PropCatalog.place(root, kind, Transform3D(Basis(Vector3.UP, rng.randf_range(-0.15, 0.15)), at), Color.WHITE, {"seed": hash([seed_value, index])})
			boats += 1
		if rng.randf() < 0.4:
			batch.call("add", "kayak_rack", Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x + 3.6, SAND_TOP, shore_z + 3.5)))
		if rng.randf() < 0.5:
			batch.call("add", "buoy", Transform3D(Basis.IDENTITY, Vector3(x + rng.randf_range(-8.0, 8.0), WATER_Y - 0.17, shore_z - length - rng.randf_range(6.0, 18.0))))
	if not xs.is_empty():
		batch.call("add", "swim_platform", Transform3D(Basis.IDENTITY, Vector3(float(xs[0]) + 9.0, WATER_Y - 0.07, shore_z - 22.0)))
	root.add_to_group("art_signature:docks")
	return root


## Mansion Hill's far side up on a terrace: a stone retaining wall along x at
## from_z (its face toward -Z, the street), the raised lawn behind it to to_z,
## height tall, with stairs up at each x in stairs (2.4 m wide). Visual only.
static func terrace(parent: Node3D, from_z: float, to_z: float, height: float, length: float, stairs: Array, batch: RefCounted) -> Node3D:
	var root := Node3D.new()
	root.name = "Terrace"
	parent.add_child(root)
	var half := length * 0.5
	var stair_depth := 4.0
	var gap := 2.4
	var cuts: Array[float] = []
	for x: Variant in stairs:
		if absf(float(x)) < half - gap:
			cuts.append(float(x))
	cuts.sort()
	var kit := _HouseKit.new()
	var top := height - 0.03
	var lawn := Color(0.27, 0.5, 0.24)
	# The raised lawn: behind the stairs full length, in front of them between the cuts.
	kit.call("box", Vector3(length, top, to_z - from_z - stair_depth), Vector3(0.0, top * 0.5, (from_z + stair_depth + to_z) * 0.5), lawn, "grass")
	var edges: Array[float] = [-half]
	for x: float in cuts:
		edges.append(x - gap * 0.5)
		edges.append(x + gap * 0.5)
	edges.append(half)
	for index: int in range(0, edges.size(), 2):
		var a := edges[index]
		var b := edges[index + 1]
		if b - a < 0.1:
			continue
		kit.call("box", Vector3(b - a, top, stair_depth - 0.45), Vector3((a + b) * 0.5, top * 0.5, from_z + 0.45 + (stair_depth - 0.45) * 0.5), lawn, "grass")
		# The wall face in pieces of at most 8 m (props/estate_props.gd retaining_wall_run).
		var pieces := maxi(1, ceili((b - a) / 8.0))
		var each := (b - a) / float(pieces)
		for piece: int in pieces:
			batch.call("add", "retaining_wall_run", Transform3D(Basis.IDENTITY, Vector3(a + each * (float(piece) + 0.5), 0.0, from_z)), STONE, Vector3(snappedf(each, 0.1), height, 0.0))
	var steps := 10
	for x: float in cuts:
		for step: int in steps:
			var rise := height * float(step + 1) / float(steps)
			var z0 := from_z + stair_depth * float(step) / float(steps)
			kit.call("box", Vector3(gap, rise, stair_depth / float(steps) + 0.02), Vector3(x, rise * 0.5, z0 + stair_depth / float(steps) * 0.5), STONE.lightened(0.05), "stone", Basis.IDENTITY, {"params": Vector4(1, 0, 0, 0)})
		for side: float in [-1.0, 1.0]:
			kit.call("box", Vector3(0.3, height + 0.5, stair_depth), Vector3(x + side * (gap * 0.5 + 0.15), (height + 0.5) * 0.5, from_z + stair_depth * 0.5), STONE, "stone")
	# End walls.
	for side: float in [-1.0, 1.0]:
		kit.call("box", Vector3(0.5, height + 0.1, to_z - from_z), Vector3(side * (half + 0.25), (height + 0.1) * 0.5, (from_z + to_z) * 0.5), STONE, "stone")
	kit.call("commit", root, "Ground")
	root.set_meta("stairs", PackedFloat32Array(cuts))
	root.add_to_group("art_signature:terrace")
	return root


## The boundary behind the yards along x at z, length long: "wood_fence"
## (privacy boards), "cinderblock" (a gray block wall), "stone_wall",
## "hoa_wall" (Approved Beige stucco with gray painted-over rectangles where
## the tags used to be), or "iron". Its yard side faces +z.
static func back_boundary(parent: Node3D, kind: String, z: float, length: float, batch: RefCounted, seed_value: int) -> Node3D:
	var root := Node3D.new()
	root.name = "BackBoundary"
	parent.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "back", kind])
	match kind:
		"wood_fence", "iron":
			var run := "privacy_fence_run" if kind == "wood_fence" else "iron_fence_run"
			var pieces := maxi(1, ceili(length / 6.0))
			var each := length / float(pieces)
			for index: int in pieces:
				batch.call("add", run, Transform3D(Basis.IDENTITY, Vector3(-length * 0.5 + each * (float(index) + 0.5), 0.0, z)), Color.WHITE, Vector3(snappedf(each, 0.1), 1.8 if kind == "wood_fence" else 1.6, 0.0))
		_:
			var kit := _HouseKit.new()
			var height := 1.9
			var surface := "cinderblock"
			var color := CINDER
			match kind:
				"stone_wall":
					height = 1.6
					surface = "stone"
					color = STONE
				"hoa_wall":
					height = 2.1
					surface = "stucco"
					color = HOA_BEIGE
			var pieces := maxi(1, ceili(length / 20.0))
			var each := length / float(pieces)
			for index: int in pieces:
				var x := -length * 0.5 + each * (float(index) + 0.5)
				kit.call("box", Vector3(each, height, 0.3), Vector3(x, height * 0.5, z), color, surface)
			kit.call("box", Vector3(length + 0.1, 0.1, 0.42), Vector3(0.0, height + 0.05, z), color.lightened(0.08), "concrete")
			var piers := int(length / 6.0)
			for index: int in piers + 1:
				var x := -length * 0.5 + float(index) * length / float(piers)
				kit.call("box", Vector3(0.45, height + 0.2, 0.45), Vector3(x, (height + 0.2) * 0.5, z), color.darkened(0.05), surface)
			if kind == "hoa_wall":
				# Where the tags were: gray rectangles that almost match. Almost.
				for index: int in int(length / 9.0):
					var x := -length * 0.5 + 4.0 + float(index) * 9.0 + rng.randf_range(-2.0, 2.0)
					var size := Vector3(rng.randf_range(1.2, 2.6), rng.randf_range(0.5, 1.1), 0.02)
					kit.call("box", size, Vector3(x, rng.randf_range(0.5, 1.3), z + 0.16), PAINTED_OVER.lerp(HOA_BEIGE, rng.randf_range(0.0, 0.35)), "plain")
			kit.call("commit", root, "Wall")
	root.set_meta("kind", kind)
	root.add_to_group("art_signature:back_%s" % kind)
	return root


static func _mesh(root: Node3D, kit: _MeshKit, node_name: String) -> MeshInstance3D:
	var mesh := kit.commit()
	var view := _Stylized.instance(mesh, {"roughness": 0.85, "specular": 0.15, "snow": 1.0, "seasonal": false})
	view.name = node_name
	root.add_child(view)
	return view


static func _words(root: Node3D, key: String, at: Vector3, width: float, color: Color, font: int = 40, pixel: float = 0.0034) -> Label3D:
	return _PropCatalog.label(root, _PropCatalog.sign_text(key), {"at": at, "yaw": PI, "font": font, "pixel": pixel, "color": color, "width": width, "outline": 0})
