extends RefCounted

## Authority: local, cosmetic (colliders() is data). A stand-in for art's
## per-neighborhood house and yard builders (gap-specs/driving.json
## contracts_needed, art's LotBuilder later): a town slot's house and front yard,
## built from the same numbers the job yard's house is
## (LotGenerator.house_spec), so a client's house looks like the yard you work
## at. Deterministic for (hood, seed, size) on every peer; visuals only, no
## colliders, no networked nodes.
##
## Yard space: x and z in -20..20 facing +Z, the driveway at x -2.1..2.1 running
## to the front, nothing past z +20.3 where the sidewalk starts.
##
## LOD: 0 is the full house (neighborhood.gd house()) with real trees; 1 is one
## merged mesh (shell, gable roof, door, windows, chimney, driveway, walk, and
## blob trees; see add_to_kit, which the streamer uses to merge many slots);
## 2 is skyline_boxes() for a far impostor.

const _LotGenerator = preload("res://levels/lots/lot_generator.gd")
const _Neighborhood = preload("res://levels/dressing/neighborhood.gd")
const _LowPoly = preload("res://props/low_poly.gd")
const _Trees = preload("res://props/trees.gd")
const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")

const STORY: float = 3.0
const GABLE_STEPS: int = 4
const FOUNDATION: float = 0.5
const CONCRETE := Color(0.7, 0.68, 0.64)
const WINDOW := Color(0.2, 0.26, 0.32)
const BRICK := Color(0.58, 0.32, 0.26)
const TRUNK := Color(0.36, 0.25, 0.18)
const CROWNS: Array[Color] = [Color(0.88, 0.45, 0.15), Color(0.78, 0.22, 0.14), Color(0.92, 0.72, 0.22), Color(0.66, 0.34, 0.16), Color(0.6, 0.55, 0.22)]
const CROWN_NAMES: Array[String] = ["orange", "red", "yellow", "rust", "turning"]
## The LOD 1 mesh's look (props/stylized.gd): snow on top in winter, crowns sway a little.
const MATERIAL: Dictionary = {"roughness": 0.9, "snow": 1.0, "wind": 0.05}


## The house this slot shows: options.spec when given (the job yard's own),
## else the one a yard with this seed and size gets.
static func spec_of(house_seed: int, size: int, options: Dictionary = {}) -> Dictionary:
	if options.has("spec"):
		return options["spec"]
	return _LotGenerator.spec_for_seed(house_seed, size)


static func house_height(spec: Dictionary) -> float:
	return FOUNDATION + STORY * float(spec["stories"])


## The front yard's trees, in yard space: [[at, height, crown]]. From the seed,
## clear of the house, the driveway and the front walk.
static func yard_trees(house_seed: int, size: int, spec: Dictionary) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([house_seed, "town_trees"])
	var out: Array = []
	var house_front := float(spec["center_z"]) + float(spec["depth"]) * 0.5 + 3.0
	var count := rng.randi_range(1, 2) + (1 if size == 2 else 0)
	for index: int in count:
		var side := -1.0 if index % 2 == 0 else 1.0
		var at := Vector3(side * rng.randf_range(8.0, 15.5), 0.0, rng.randf_range(maxf(house_front, 6.0), 15.5))
		out.append([at, rng.randf_range(6.5, 9.0), rng.randi() % CROWNS.size()])
	return out


## The slot's solids, in yard space: [[center, size]] boxes. The house (the
## same box as the job yard's HouseBody) and each tree's trunk.
static func colliders(_hood_id: String, house_seed: int, size: int, options: Dictionary = {}) -> Array:
	var spec := spec_of(house_seed, size, options)
	var height := house_height(spec)
	var out: Array = [[Vector3(float(spec["center_x"]), height * 0.5, float(spec["center_z"])), Vector3(float(spec["width"]), height, float(spec["depth"]))]]
	for tree: Array in yard_trees(house_seed, size, spec):
		out.append([(tree[0] as Vector3) + Vector3(0.0, 1.5, 0.0), Vector3(0.5, 3.0, 0.5)])
	return out


## Far boxes for a merged skyline: [[center, size, color]] in yard space.
static func skyline_boxes(_hood_id: String, house_seed: int, size: int, options: Dictionary = {}) -> Array:
	var spec := spec_of(house_seed, size, options)
	var height := house_height(spec)
	var center := Vector3(float(spec["center_x"]), 0.0, float(spec["center_z"]))
	return [
		[center + Vector3(0.0, height * 0.5, 0.0), Vector3(float(spec["width"]), height, float(spec["depth"])), spec["wall"]],
		[center + Vector3(0.0, height + float(spec["depth"]) * 0.19, 0.0), Vector3(float(spec["width"]) + 1.0, float(spec["depth"]) * 0.38, float(spec["depth"]) + 1.0), spec["roof"]],
	]


## Builds one slot under parent at xform. Returns the slot's root.
static func build(parent: Node3D, xform: Transform3D, hood_id: String, house_seed: int, size: int, lod: int, options: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "Slot_%s_%d" % [hood_id, house_seed % 100000]
	var spec := spec_of(house_seed, size, options)
	if lod <= 0:
		root.transform = xform
		_full(root, house_seed, size, spec)
	else:
		var kit := _MeshKit.new()
		add_to_kit(kit, xform, house_seed, size, spec)
		var mesh := kit.commit()
		if mesh != null:
			root.add_child(_Stylized.instance(mesh, MATERIAL))
	parent.add_child(root)
	return root


## LOD 0: the job yard's own house builder, the yard's concrete, and real trees.
static func _full(root: Node3D, house_seed: int, size: int, spec: Dictionary) -> void:
	var at := Vector3(float(spec["center_x"]), 0.0, float(spec["center_z"]))
	_Neighborhood.house(root, at, float(spec["width"]), float(spec["depth"]), int(spec["stories"]), spec["wall"], spec["roof"], spec["trim"], bool(spec["garage"]))
	_LowPoly.paint(_LowPoly.box(root, Vector3(4.2, 0.03, 17.0), Vector3(0.0, 0.015, 11.5), CONCRETE), "concrete")
	var walk_from := at.z + float(spec["depth"]) * 0.5 + 2.6
	if walk_from < 20.0:
		_LowPoly.paint(_LowPoly.box(root, Vector3(1.3, 0.03, 20.0 - walk_from), Vector3(at.x, 0.015, (walk_from + 20.0) * 0.5), CONCRETE.lightened(0.05)), "concrete")
	for tree: Array in yard_trees(house_seed, size, spec):
		_Trees.spawn(root, tree[0], float(tree[1]), "broadleaf", CROWN_NAMES[int(tree[2])], int(tree[2]), false, float(tree[1]))


## LOD 1 into a shared kit, in world space through xform: the house shell with
## its roof, door, windows and chimney, the driveway and front walk, and blob
## trees. Everything is boxes and blobs, one draw call for the whole kit.
static func add_to_kit(kit: RefCounted, xform: Transform3D, house_seed: int, size: int, spec: Dictionary) -> void:
	var width := float(spec["width"])
	var depth := float(spec["depth"])
	var stories := int(spec["stories"])
	var wall: Color = spec["wall"]
	var roof: Color = spec["roof"]
	var trim: Color = spec["trim"]
	var center := Vector3(float(spec["center_x"]), 0.0, float(spec["center_z"]))
	var height := STORY * float(stories)
	var top := FOUNDATION + height
	var front := center.z + depth * 0.5
	_box(kit, xform, center + Vector3(0.0, FOUNDATION * 0.5, 0.0), Vector3(width + 0.3, FOUNDATION, depth + 0.3), Color(0.55, 0.53, 0.5))
	_box(kit, xform, center + Vector3(0.0, FOUNDATION + height * 0.5, 0.0), Vector3(width, height, depth), wall)
	# The gable along x, as two slabs like the job yard's climbable roof.
	var rise := depth * 0.38
	var half_run := (depth + 1.4) * 0.5
	var slope := atan2(rise, half_run)
	var length := Vector2(half_run, rise).length()
	for side: float in [1.0, -1.0]:
		var normal := Vector3(0.0, cos(slope), side * sin(slope))
		var slab_at := center + Vector3(0.0, top + rise * 0.5, side * half_run * 0.5) - normal * 0.12
		_box(kit, xform, slab_at, Vector3(width + 1.0, 0.24, length), roof, Basis(Vector3.RIGHT, side * slope))
	# Gable ends under the slabs: a stepped wedge, each step's top corner kept
	# under the roof line so nothing pokes through the shingles.
	for step: int in GABLE_STEPS - 1:
		var share := 1.0 - (float(step) + 1.0) / float(GABLE_STEPS)
		_box(kit, xform, center + Vector3(0.0, top + rise * (float(step) + 0.5) / float(GABLE_STEPS), 0.0), Vector3(width - 0.05, rise / float(GABLE_STEPS), depth * share), wall)
	_box(kit, xform, center + Vector3(width * 0.28, top + rise * 0.5 + 0.3, -depth * 0.12), Vector3(0.9, rise + 1.4, 0.9), BRICK)
	# The door, a porch slab, windows on every floor, and the garage door.
	var garage := bool(spec["garage"])
	_box(kit, xform, center + Vector3(0.0, 1.6, depth * 0.5 + 0.03), Vector3(1.1, 2.2, 0.08), Color(0.5, 0.18, 0.15) if wall.r < 0.8 else Color(0.2, 0.32, 0.45))
	_box(kit, xform, center + Vector3(0.0, 0.25, depth * 0.5 + 1.0), Vector3(3.2, 0.5, 2.0), Color(0.62, 0.6, 0.57))
	_box(kit, xform, center + Vector3(0.0, 3.1, depth * 0.5 + 1.0), Vector3(3.4, 0.14, 2.0), roof)
	for floor_index: int in stories:
		var y := FOUNDATION + STORY * float(floor_index) + 1.65
		var xs: Array[float] = [-width * 0.3, width * 0.3]
		if floor_index > 0:
			xs.append(0.0)
		for x: float in xs:
			if garage and floor_index == 0 and x > 0.0:
				continue
			_box(kit, xform, Vector3(center.x + x, y, front + 0.04), Vector3(1.3, 1.25, 0.06), WINDOW)
			_box(kit, xform, Vector3(center.x + x, y - 0.68, front + 0.06), Vector3(1.45, 0.1, 0.1), trim)
	if garage:
		_box(kit, xform, Vector3(center.x + width * 0.3, 1.65, front + 0.04), Vector3(2.8, 2.3, 0.1), trim.darkened(0.04))
	# The yard's concrete.
	_box(kit, xform, Vector3(0.0, 0.015, 11.5), Vector3(4.2, 0.03, 17.0), CONCRETE)
	var walk_from := front + 2.6
	if walk_from < 20.0:
		_box(kit, xform, Vector3(center.x, 0.015, (walk_from + 20.0) * 0.5), Vector3(1.3, 0.03, 20.0 - walk_from), CONCRETE.lightened(0.05))
	for tree: Array in yard_trees(house_seed, size, spec):
		var at: Vector3 = tree[0]
		var tall := float(tree[1])
		_box(kit, xform, at + Vector3(0.0, tall * 0.25, 0.0), Vector3(0.45, tall * 0.5, 0.45), TRUNK)
		var crown: Color = CROWNS[int(tree[2])]
		kit.call("blob", xform * (at + Vector3(0.0, tall * 0.68, 0.0)), Vector3(tall * 0.33, tall * 0.3, tall * 0.33), crown, {"detail": 1, "lumps": 0.3, "seed": house_seed % 997 + int(tree[2]), "sway": 0.3})


static func _box(kit: RefCounted, xform: Transform3D, center: Vector3, size: Vector3, color: Color, basis: Basis = Basis.IDENTITY) -> void:
	kit.call("box", xform * center, size, color, xform.basis * basis)
