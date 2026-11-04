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
## The job house (decor "job", levels/lots/lot_generator.gd) gets the porch and
## bed decor only, never anything on the lawn where the work is: pumpkins, a
## mums pot set into the back of each bed (beside no weed), a wreath and snow piles along the shoveled drive, tulips, a pool float
## in the middle of the pool and a pinwheel in a bed. No string lights.
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
##   house_at, spec (the HouseSpec, house space), beds [[center, size]] (a job
##   bed adds its mums pot's spot or null: [center, size, mums]), trees
##   [[at, kind, crown]], drive [from, to], walk [from, to], pools [at], yard
##   [Rect2 free lawn spots], job (bool)

const _PropCatalog = preload("res://props/prop_catalog.gd")
const _PropBatch = preload("res://props/prop_batch.gd")
const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const _Trees = preload("res://props/trees.gd")
const _LeafShaders = preload("res://leaves/leaf_shaders.gd")

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
				if not job:
					batch.add("mums_pot", Transform3D(Basis.IDENTITY, (bed[0] as Vector3) + Vector3(0.0, 0.0, 0.9)))
				elif bed.size() > 2 and bed[2] is Vector3:
					# The job's pot stands in the bed, at the back by the porch, its
					# base set into the soil: never on the lawn, the edging or a weed.
					batch.add("mums_pot", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), (bed[2] as Vector3) + Vector3(0.0, (bed[1] as Vector3).y * 0.5, 0.0)))
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
			if job and drive.size() == 2:
				# The job's drive was shoveled the long way: piles along its edges,
				# short of the curb, where the homeowner waits and Chefty parks.
				var from: Vector3 = drive[0]
				for at: Vector3 in Constants.ART_JOB_SNOW_PILES:
					# Long side along the drive, the smaller heap toward it.
					var yaw := -signf(at.x) * PI * 0.5 + rng.randf_range(-0.2, 0.2)
					batch.add("snow_pile", Transform3D(Basis(Vector3.UP, yaw), from + at))
			elif drive.size() == 2:
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
				# Running in the morning (art:9, props/sprinkler_jet.gd), each lawn in its
				# own time; Oak Hollow's lawns have the HOA's, and only that one.
				var lawn := _spot(yard, rng)
				if not Constants.SPRINKLER_HOODS.has(str(style.get("id", ""))):
					# Its own beat: a hashed share of the head's loop (the jet is loaded,
					# not preloaded: it names Net, which a --script run has no autoload for).
					var loop := float(load(_PropCatalog.SPRINKLER_JET).call("loop_seconds"))
					var beat := float(posmod(hash([seed_value, "sprinkler"]), 10000)) / 10000.0
					_place(root, "sprinkler", Transform3D(Basis(Vector3.UP, float(posmod(seed_value, 628)) * 0.01), lawn), season,
						{"running": "summer", "phase": beat * loop})
				if rng.randf() < 0.4:
					batch.add("beach_umbrella", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), _spot(yard, rng)))
			for pool: Vector3 in spec.get("pools", []):
				# The job's pool float bobs in the middle, clear of the leaves to skim.
				var float_at := pool if job else pool + Vector3(1.2, 0.08, 0.4)
				batch.add("pool_float", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), float_at))
			if job:
				# A pinwheel stuck in a bed by the walk.
				var beds: Array = spec.get("beds", [])
				if not beds.is_empty():
					var bed: Array = beds[rng.randi() % beds.size()]
					var size: Vector3 = bed[1]
					var toward := signf(door.x - (bed[0] as Vector3).x)
					batch.add("pinwheel", Transform3D(Basis(Vector3.UP, rng.randf_range(-0.4, 0.4)), (bed[0] as Vector3) + Vector3(toward * (size.x * 0.5 - 0.2), 0.0, -size.z * 0.5 + 0.2)))
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


## Fallen leaves on the lawn: a few patches of the job yard's own curled leaves
## (LeafMeshes, LeafPalette, the flake material), so a neighbour's lawn matches
## the one you rake. One MultiMesh for the parcel.
static func _leaves(root: Node3D, yard: Array, rng: RandomNumberGenerator) -> void:
	# No free lawn: no leaves (never a pile at the parcel origin, under the house).
	if yard.is_empty():
		return
	var crowns: Array[String] = ["orange", "red", "yellow", "rust"]
	var looks: Array = []
	for crown: String in crowns:
		looks.append({"crown": crown, "species": LeafPalette.MAPLE if looks.size() % 2 == 0 else LeafPalette.OAK, "width": 1.0})
	var mix: Array = [0, 1, 2, 3]
	var floats := PackedFloat32Array()
	var salt := rng.randi() & 0xffff
	for patch: int in Constants.ART_NEIGHBOR_LEAF_PATCHES:
		var center := _spot(yard, rng)
		var look := rng.randi() % looks.size()
		for flake: int in Constants.LEAF_NEIGHBOR_PATCH_LEAVES:
			# Thick in the middle of the patch, thinning out to a ragged edge.
			var reach := Constants.LEAF_NEIGHBOR_PATCH_REACH * sqrt(rng.randf())
			var angle := rng.randf() * TAU
			var at := center + Vector3(cos(angle) * reach, 0.012 + 0.003 * float(flake % 4), sin(angle) * reach)
			var leaf := LeafPalette.flake(looks, mix, look, 0, salt + patch, flake, 0)
			var length := lerpf(Constants.LEAF_SIZE.x, Constants.LEAF_SIZE.y, rng.randf())
			var lean := Constants.LEAF_NEIGHBOR_TILT
			var tilt := Vector3(rng.randf_range(-lean, lean), rng.randf() * TAU, rng.randf_range(-lean, lean))
			var basis := Basis.from_euler(tilt) * Basis.from_scale(Vector3(length * float(leaf["width"]), length, length))
			var centre: Color = leaf["centre"]
			var rim: Color = leaf["rim"]
			floats.append_array([
				basis.x.x, basis.y.x, basis.z.x, at.x,
				basis.x.y, basis.y.y, basis.z.y, at.y,
				basis.x.z, basis.y.z, basis.z.z, at.z,
				centre.r, centre.g, centre.b, float(leaf["age"]),
				rim.r, rim.g, rim.b, float(leaf["loose"]),
			])
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.use_custom_data = true
	multi.mesh = LeafMeshes.mesh(LeafPalette.MAPLE)
	multi.instance_count = floats.size() / 20
	multi.buffer = floats
	var view := MultiMeshInstance3D.new()
	view.name = "Leaves"
	view.multimesh = multi
	view.material_override = _LeafShaders.flake_material("mover")
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
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
