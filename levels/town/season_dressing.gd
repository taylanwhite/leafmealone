extends RefCounted

## Authority: local, cosmetic. What each season puts out in the yards and along
## a block (docs/GAME.md, "the seasons' looks"), rebuilt by levels/town/parcel.gd
## when the season turns:
## - autumn (the home season): pumpkins on the porch steps, potted mums, a hay
##   bale or a scarecrow now and then, and leaves piling up on the lawn
## - winter: string lights along the eaves (never on the job house: a future
##   hang-lights task owns those), a wreath on the door, a snowman, snow piled at
##   the drive; snowbanks along the curbs and the block's one sagging inflatable
## - spring: tulip beds and petals under the blossom trees
## - summer: a sprinkler, a pool float, a beach umbrella, sometimes a lemonade stand
## The hood's decor style shades it: "approved" (Oak Hollow: the same warm-white
## lights and the same wreath on every door), "homemade" (mismatched lights, a
## dead bulb or two, lights on half the eaves), "pro" (Mansion Hill: big bulbs on
## every eave), "dock" (Lakeside: lights on the docks too), "classic".
##
## Everything goes under a "SeasonDecor" child and into groups "season_decor" and
## "art_signature:season_<id>" (Seasons.IDS). Pure function of the decor data,
## the style, the season, and the seed: every peer decorates the same.
##
## A parcel's decor dict (levels/town/lot_builder.gd plan()["decor"]), parcel space:
##   house_at, spec (the HouseSpec, house space), beds [[center, size]], trees
##   [[at, kind, crown]], drive [from, to], walk [from, to], pools [at], yard
##   [Rect2 free lawn spots], job (bool)

const _PropCatalog = preload("res://props/prop_catalog.gd")
const _PropBatch = preload("res://props/prop_batch.gd")
const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const _Trees = preload("res://props/trees.gd")

const LEAVES: Array[Color] = [Color(0.88, 0.45, 0.15), Color(0.9, 0.7, 0.2), Color(0.72, 0.25, 0.14)]
const PETALS := Color(0.98, 0.8, 0.86)
## Lights per decor style (props/prop_catalog.gd string_lights "lights").
const LIGHTS: Dictionary = {"approved": "approved", "homemade": "homemade", "pro": "pro", "dock": "classic", "classic": "classic"}


## Decorates a parcel for season under a new "SeasonDecor" child and returns it.
## include_lights false keeps string lights off (the job house).
static func decorate(parcel: Node3D, spec: Dictionary, style: Dictionary, season: int, seed_value: int, include_lights: bool = true) -> Node3D:
	var root := _holder(parcel, season)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "decor", season])
	var batch := _PropBatch.new(root, 64.0)
	var decor := str(style.get("decor", "classic"))
	var house_at: Vector3 = spec.get("house_at", Vector3.ZERO)
	var house: Dictionary = spec.get("spec", {})
	var door: Vector3 = house_at + (house.get("door", Vector3(0.0, 1.6, 4.0)) as Vector3)
	var porch := float(house.get("porch_depth", 0.0))
	var step := Vector3(door.x, 0.0, door.z + maxf(porch, 0.4) + 0.4)
	var yard: Array = spec.get("yard", [])
	var job := bool(spec.get("job", false))
	match season:
		0:
			# Pumpkins either side of the steps, mums by the walk.
			for side: float in [-1.0, 1.0]:
				var kind: String = ["pumpkin_small", "pumpkin", "pumpkin_big"][rng.randi() % 3]
				batch.add(kind, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), step + Vector3(side * 0.9, 0.0, -0.2)))
			if rng.randf() < 0.6:
				batch.add("pumpkin_small", Transform3D(Basis.IDENTITY, step + Vector3(1.25, 0.0, 0.3)))
			for bed: Array in spec.get("beds", []):
				batch.add("mums_pot", Transform3D(Basis.IDENTITY, (bed[0] as Vector3) + Vector3(0.0, 0.0, 0.9)))
			if not job and not yard.is_empty() and rng.randf() < 0.3:
				var spot := _spot(yard, rng)
				batch.add("hay_bale" if rng.randf() < 0.7 else "scarecrow", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), spot))
			if not job:
				_leaves(root, yard, rng)
		1:
			if include_lights and not job:
				var eaves: Array = house.get("eaves", [])
				var kind: String = LIGHTS.get(decor, "classic")
				for index: int in eaves.size():
					# Homemade decorating gets about half the eaves done.
					if decor == "homemade" and rng.randf() < 0.5:
						continue
					var line: Array = eaves[index]
					_lights(root, house_at + (line[0] as Vector3), house_at + (line[1] as Vector3), kind, seed_value + index)
			# The same wreath on every door (Oak Hollow approves exactly one).
			var wreath := Color.WHITE if decor == "approved" or rng.randf() < 0.6 else Color(0.62, 0.16, 0.14)
			batch.add("wreath", Transform3D(Basis.IDENTITY, door + Vector3(0.0, 0.75, 0.06)), wreath)
			if not job and not yard.is_empty() and rng.randf() < 0.55:
				batch.add("snowman", Transform3D(Basis(Vector3.UP, PI + rng.randf_range(-0.5, 0.5)), _spot(yard, rng)))
			var drive: Array = spec.get("drive", [])
			if drive.size() == 2:
				var end: Vector3 = drive[1]
				for side: float in [-1.0, 1.0]:
					batch.add("snow_pile", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), end + Vector3(side * 2.4, 0.0, -1.5 - rng.randf() * 2.0)))
			if not job and rng.randf() < 0.35:
				batch.add("sled", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), step + Vector3(-1.6, 0.0, 0.8)))
		2:
			for bed: Array in spec.get("beds", []):
				var size: Vector3 = bed[1]
				batch.add("tulip_bed", Transform3D(Basis.IDENTITY, bed[0]), Color.WHITE, Vector3(maxf(size.x - 0.2, 0.6), 0.0, maxf(size.z - 0.2, 0.4)))
			for tree: Array in spec.get("trees", []):
				var form: Array = _Trees.seasonal_form(str(tree[1]), str(tree[2]), season)
				if str(form[1]).begins_with("blossom"):
					batch.add("petal_scatter", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), tree[0]))
		3:
			if not job and not yard.is_empty():
				batch.add("sprinkler", Transform3D(Basis.IDENTITY, _spot(yard, rng)))
				if rng.randf() < 0.4:
					batch.add("beach_umbrella", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), _spot(yard, rng)))
			for pool: Vector3 in spec.get("pools", []):
				batch.add("pool_float", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), pool + Vector3(1.2, 0.08, 0.4)))
			var walk: Array = spec.get("walk", [])
			if not job and walk.size() == 2 and rng.randf() < 0.12:
				var curb: Vector3 = walk[1]
				_place(root, "lemonade_stand", Transform3D(Basis(Vector3.UP, PI), curb + Vector3(2.4, 0.0, -1.4)), season)
	batch.commit()
	_tag(root, season)
	return root


## The block's own decor (winter: snowbanks along the curbs and the one sagging
## inflatable snowman) under a new "SeasonDecor" child of block. decor:
##   curbs [[from, to]] (block space, the curb lines), inflatable (Vector3 or null),
##   gaps [Vector2(x_from, x_to)] where no snowbank goes (driveways, the job's drive)
static func block_decor(block: Node3D, season: int, decor: Dictionary) -> Node3D:
	var root := _holder(block, season)
	if season == 1:
		var batch := _PropBatch.new(root)
		var gaps: Array = decor.get("gaps", [])
		for curb: Array in decor.get("curbs", []):
			var from: Vector3 = curb[0]
			var to: Vector3 = curb[1]
			var length := from.distance_to(to)
			var pieces := maxi(1, ceili(length / 6.0))
			var each := length / float(pieces)
			for index: int in pieces:
				var center := from.lerp(to, (float(index) + 0.5) / float(pieces))
				var blocked := false
				for gap: Vector2 in gaps:
					if center.x + each * 0.5 > gap.x and center.x - each * 0.5 < gap.y:
						blocked = true
				if blocked:
					continue
				var yaw := atan2(-(to - from).z, (to - from).x)
				batch.add("snowbank_run", Transform3D(Basis(Vector3.UP, yaw), center), Color.WHITE, Vector3(snappedf(each, 0.1), 0.45, 0.7))
		var inflatable: Variant = decor.get("inflatable", null)
		if inflatable is Vector3:
			batch.add("snowman_inflatable", Transform3D(Basis(Vector3.UP, PI + 0.3), inflatable))
		batch.commit()
	_tag(root, season)
	return root


## A string-light run from a to b (an eave line), hanging from it.
static func _lights(root: Node3D, a: Vector3, b: Vector3, kind: String, seed_value: int) -> void:
	var length := a.distance_to(b)
	if length < 1.0:
		return
	var along := (b - a) / length
	var basis := Basis(along, Vector3.UP, along.cross(Vector3.UP).normalized())
	_place(root, "string_lights", Transform3D(basis.orthonormalized(), (a + b) * 0.5), 1, {"size": Vector3(snappedf(length, 0.1), 0.0, 0.0), "lights": kind, "seed": seed_value})


static func _place(root: Node3D, kind: String, xform: Transform3D, season: int, opts: Dictionary = {}) -> Node3D:
	var options := opts.duplicate()
	options["season"] = season
	return _PropCatalog.place(root, kind, xform, Color.WHITE, options)


## Fallen leaves on the lawn: a few patches of flat flakes, one mesh.
static func _leaves(root: Node3D, yard: Array, rng: RandomNumberGenerator) -> void:
	var kit := _MeshKit.new()
	for _patch: int in Constants.ART_NEIGHBOR_LEAF_PATCHES:
		var center := _spot(yard, rng)
		for _flake: int in 14:
			var at := center + Vector3(rng.randf_range(-1.5, 1.5), 0.02, rng.randf_range(-1.5, 1.5))
			kit.box(at, Vector3(0.22, 0.02, 0.16), LEAVES[rng.randi() % LEAVES.size()], Basis(Vector3.UP, rng.randf() * TAU))
	var mesh := kit.commit()
	if mesh == null:
		return
	var view := _Stylized.instance(mesh, {"roughness": 0.9})
	view.name = "Leaves"
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.visibility_range_end = Constants.ART_SMALL_PROP_RANGE
	root.add_child(view)


## A free spot on the lawn: inside one of the yard rects.
static func _spot(yard: Array, rng: RandomNumberGenerator) -> Vector3:
	if yard.is_empty():
		return Vector3.ZERO
	var rect: Rect2 = yard[rng.randi() % yard.size()]
	return Vector3(rect.position.x + rng.randf() * rect.size.x, 0.0, rect.position.y + rng.randf() * rect.size.y)


static func _holder(parent: Node3D, _season: int) -> Node3D:
	var root := Node3D.new()
	root.name = "SeasonDecor"
	parent.add_child(root)
	return root


## Every decor node joins season_decor and its season's signature group.
static func _tag(root: Node3D, season: int) -> void:
	var group := "art_signature:season_%s" % Seasons.IDS[posmod(season, 4)]
	root.add_to_group("season_decor")
	for node: Node in root.find_children("*", "Node3D", true, false):
		if node is GeometryInstance3D or node.has_meta("prop_kind"):
			node.add_to_group("season_decor")
			node.add_to_group(group)
