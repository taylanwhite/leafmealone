extends Node3D

## Authority: every peer builds the same yard from the job's seed. Called once
## by levels/lots/job_lot.gd. Each job lot is a different home: the house's
## size, stories, colors, and garage; how many trees and where (the leaves pile
## up thickest under them); hedges along the sides; picket fences; flower beds
## by the front; litter on the lawn; a shed, a wheelie bin, and a hedge to hide
## in; and the driveway. Fixed spots stay put: the driveway at x 0, the
## homeowner at the end of it by the street where Chefty parks, the tools beside it.
##
## It also lays out every piece of work this yard could need in
## net/work/job_tasks.gd (windows, gutter sections, shaggy hedges, fence panels,
## weeds, litter, the lawn, the driveway's stains) in the same order on every
## peer, and turns on the ones the homeowner asked for. levels/lots/task_looks.gd
## draws them. Everything solid here has a collider, so the crew paths around it.
##
## The yard looks like its neighborhood (levels/town/hood_styles.gd, by `hood`):
## the house is one of the hood's archetypes (levels/town/house_builder.gd, the
## same request the town's parcel builder makes, so it is the same house), and
## the fences, beds, trees, ground and drive follow the style. The roof, gutters,
## windows and spigot come from the house's HouseSpec. Look-only choices come
## from a second rng (_art, seeded hash([job_seed, "art"])); the gameplay rng's
## draws and their order are frozen, and so is everything that goes into _taken
## (the beds get a fixed strip in front of every house), so the hood never moves
## a tree, a hedge, the pool, a hiding spot or a piece of litter
## (--layout-test compares them across hoods). When the yard is
## done, the street block around it (levels/town/block_builder.gd) is built over
## the next few frames: neighbors, the street, set pieces, all cosmetic.

const _LowPoly = preload("res://props/low_poly.gd")
const _Trees = preload("res://props/trees.gd")
const _YardModels = preload("res://props/yard_models.gd")
const _Neighborhood = preload("res://levels/dressing/neighborhood.gd")
const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const _JobTasks = preload("res://net/work/job_tasks.gd")
const _TaskLooks = preload("res://levels/lots/task_looks.gd")
const _HideSpot = preload("res://props/hide_spot.tscn")
const _Doodles = preload("res://props/doodles.gd")
const _WaterSources = preload("res://net/work/water_sources.gd")
const _HouseBuilder = preload("res://levels/town/house_builder.gd")
const _HoodStyles = preload("res://levels/town/hood_styles.gd")
const _BlockBuilder = preload("res://levels/town/block_builder.gd")
const _HouseKit = preload("res://props/house_kit.gd")
const _PropCatalog = preload("res://props/prop_catalog.gd")
const _Surfaces = preload("res://props/surfaces.gd")
const _Parcel = preload("res://levels/town/parcel.gd")
const YARD_HALF: float = 20.0
const POOL_RADIUS: float = 2.3
const POOL_HEIGHT: float = 1.15
const PICKET := Color(0.93, 0.91, 0.86)
const CROWNS: Array[String] = ["orange", "red", "yellow", "rust", "turning"]
const BED_DIRT := Color(0.36, 0.25, 0.18)
const FLOWER_COLORS: Array[Color] = [Color(0.95, 0.35, 0.45), Color(0.98, 0.8, 0.25), Color(0.7, 0.45, 0.9), Color(0.98, 0.98, 0.95), Color(0.95, 0.55, 0.2)]
## Winter's beds: the same flowers, dried to straw and seed heads.
const WINTER_FLOWERS: Array[Color] = [Color(0.55, 0.42, 0.3), Color(0.62, 0.52, 0.36), Color(0.48, 0.4, 0.34), Color(0.7, 0.66, 0.58), Color(0.58, 0.44, 0.3)]
const GUTTER := Color(0.78, 0.78, 0.75)
const TIRE := Color(0.12, 0.12, 0.13)
const DRIVE := {"concrete": Color(0.62, 0.6, 0.57), "gravel": Color(0.6, 0.56, 0.5), "pavers": Color(0.66, 0.46, 0.36)}
## A bed's edging by the style's bed_edge: [color, surface].
const BED_EDGES: Dictionary = {
	"concrete": [Color(0.6, 0.58, 0.55), "concrete"], "brick": [Color(0.58, 0.32, 0.26), "brick"],
	"stone": [Color(0.66, 0.64, 0.6), "stone"], "timber": [Color(0.5, 0.36, 0.24), "planks"],
}
## The fence kinds the yard's paintable fence can be (hood_styles.gd "job_fence").
const FENCE_KINDS: Array[String] = ["picket", "weathered_picket", "vinyl", "split_rail", "privacy", "iron"]
## The fence's runs (from, to, the yard side), in this node's space: the back
## and both sides, open at the front. The leaf field stops raked leaves at them.
const FENCE_RUNS: Array = [
	[Vector3(-19.4, 0.0, -19.4), Vector3(19.4, 0.0, -19.4), Vector3.BACK],
	[Vector3(-19.4, 0.0, -18.4), Vector3(-19.4, 0.0, 14.0), Vector3.RIGHT],
	[Vector3(19.4, 0.0, -18.4), Vector3(19.4, 0.0, 14.0), Vector3.LEFT],
]

## The neighborhood the yard is in (net/town/neighborhoods.gd id; "" looks like
## maple_row). Set by job_lot before generate(), like mess.
var hood: String = ""

var _rng := RandomNumberGenerator.new()
## Look-only choices: never the gameplay rng (_rng), whose draws are frozen.
var _art := RandomNumberGenerator.new()
var _style: Dictionary = {}
var _job_seed: int = 0
## The house: its HouseSpec (house space), where it stands, and the request it was built from.
var _spec: Dictionary = {}
var _house_at := Vector3.ZERO
var _house_req: Dictionary = {}
## Lawn pieces, drive, beds, gutters and the pool's pad, batched into one kit.
var _kit: RefCounted
## Every look decision, for the lot's art hash.
var _art_notes: Array = []
## Lot-space rectangles (x and z) already used by something.
var _taken: Array[Rect2] = []
var _tasks: Node
var _looks: Node
var _trees: Array[Vector3] = []
var _house_rect := Rect2()
## Where a big yard's pool stands, or INF.
var _pool_at := Vector3.INF
## Where no lawn grows: beds, hedges, the shed and bins.
var _no_lawn: Array[Rect2] = []
var _layout_hash: int = 0
## The front walk (yard x and z; empty when the porch reaches the drive).
var _walk_rect := Rect2()
## The beds as drawn ([center, size, mums spot or null], yard space) and the yard's trees
## ([at, kind, crown]), for the house's season decor.
var _bed_boxes: Array = []
var _tree_looks: Array = []
## 0 small, 1 regular, 2 big.
var _size: int = 1
## Set by job_lot before generate(): how grown back the leaves are (net/town/town.gd).
var mess: float = 1.0


func generate(job_seed: int, tasks: PackedStringArray, yard_size: int = 1) -> void:
	_rng.seed = job_seed
	_job_seed = job_seed
	_art.seed = hash([job_seed, "art"])
	_style = _HoodStyles.style(hood)
	_kit = _HouseKit.new()
	_size = clampi(yard_size, 0, 2)
	_note(["size", _size])
	var lot := get_parent() as Node3D
	# What's fixed: the driveway and truck, the homeowner, the tools' spot.
	_taken.append(Rect2(-2.8, 3.0, 5.6, 17.5))
	_taken.append(Rect2(2.0, 16.5, 3.2, 3.5))
	_taken.append(Rect2(-9.8, 12.0, 6.0, 7.0))
	_tasks = _JobTasks.new()
	_tasks.name = "JobTasks"
	lot.add_child(_tasks)
	_looks = _TaskLooks.new()
	_looks.name = "TaskLooks"
	add_child(_looks)
	_house()
	_driveway()
	_beds()
	if _size == 2:
		_pool()
	_trees_around()
	_hedges()
	_fences()
	_hide_spots(lot)
	_water(lot)
	_pool_lounge()
	_litter()
	_grids()
	_tasks.call("activate", tasks, job_seed)
	_looks.call("setup", _tasks)
	_shape_leaves(lot)
	if Net.is_host():
		_place_props(lot)
	lot.set_meta("layout_hash", _layout_hash)
	var yard_look: Node3D = _kit.call("commit", self, "YardLook")
	yard_look.set_meta("art", "yard")
	_paint_ground(lot)
	_season_decor()
	var art_hash := hash(_art_notes)
	lot.set_meta("hood_style", str(_style["id"]))
	lot.set_meta("archetype", str(_spec.get("archetype", "")))
	lot.set_meta("yard_art_hash", art_hash)
	_start_block(lot, art_hash)


## A hash of where everything went, so tests can check every peer built the same yard.
func layout_hash() -> int:
	return _layout_hash


func _note(value: Variant) -> void:
	_layout_hash = hash([_layout_hash, value])


# ---------------------------------------------------------------- the house

## The house's numbers, drawn first from a yard's rng right after it is seeded
## with the house's seed. The job yard (_house) and the town's view of the same
## house (levels/town/fallback_house.gd, and art's HouseBuilder.request_for
## later) both use it, so the house you drive past is the house you work at.
## The draws and their order are fixed: changing them changes every yard
## (work_test and layout_test check the layout hash). Yard space: x and z in
## -20..20, the front at +Z.
static func house_spec(rng: RandomNumberGenerator, size: int) -> Dictionary:
	var widths: Vector2 = Constants.YARD_HOUSE_WIDTH[clampi(size, 0, 2)]
	var width := rng.randf_range(widths.x, widths.y)
	var depth := rng.randf_range(6.5, 9.0) + (1.0 if size == 2 else 0.0)
	# Small yards have bungalows, big yards two stories.
	var stories := 2 if rng.randf() < 0.4 else 1
	# (Was `stories = _size`, which gave small yards a zero-story house: a roof
	# sitting on its foundation. --layout-test caught it.)
	if size == 0:
		stories = 1
	elif size == 2:
		stories = 2
	var center_x := rng.randf_range(-YARD_HALF + width * 0.5 + 2.5, YARD_HALF - width * 0.5 - 2.5)
	var center_z := -YARD_HALF + depth * 0.5 + rng.randf_range(2.5, 6.0)
	var wall: Color = _Neighborhood.WALLS[rng.randi() % _Neighborhood.WALLS.size()]
	var roof: Color = _Neighborhood.ROOFS[rng.randi() % _Neighborhood.ROOFS.size()]
	var trim: Color = _Neighborhood.TRIMS[rng.randi() % _Neighborhood.TRIMS.size()]
	var garage := rng.randf() < 0.5
	return {
		"width": width, "depth": depth, "stories": stories, "center_x": center_x, "center_z": center_z,
		"wall": wall, "roof": roof, "trim": trim, "garage": garage,
	}


## The house a yard with this seed and size gets, without building the yard.
static func spec_for_seed(seed_value: int, size: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return house_spec(rng, clampi(size, 0, 2))


func _house() -> void:
	var spec := house_spec(_rng, _size)
	var width: float = spec["width"]
	var depth: float = spec["depth"]
	var stories: int = spec["stories"]
	var center_x: float = spec["center_x"]
	var center_z: float = spec["center_z"]
	var garage: bool = spec["garage"]
	var at := Vector3(center_x, 0.0, center_z)
	# The hood's version of this house: the request the town's parcel builder
	# makes for the same seed and size (HouseBuilder.request_for, critic C25),
	# its archetype, door and accent from the art rng, its colors from the
	# yard's own palette draws above.
	_house_req = _HouseBuilder.request_for(str(_style["id"]), _job_seed, _size, spec)
	_house_at = at
	var house: Node3D = _HouseBuilder.build(self, at, _house_req)
	_spec = _HouseBuilder.spec_of(house)
	# One body, a box per HouseSpec solid (walls; the roof's are under Roof).
	var body := StaticBody3D.new()
	body.name = "HouseBody"
	add_child(body)
	body.position = at
	for solid: Array in _spec.get("solids", []):
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = solid[1]
		shape.shape = box
		shape.position = solid[0]
		body.add_child(shape)
	# The footprint contract keeps every archetype in here (house_builder.gd).
	_house_rect = Rect2(center_x - width * 0.5 - 0.6, center_z - depth * 0.5 - 0.6, width + 1.2, depth + 3.6)
	_taken.append(_house_rect)
	var archetype := str(_spec.get("archetype", "classic"))
	_note([width, depth, stories, center_x, center_z, garage, archetype])
	_art_notes.append([str(_style["id"]), archetype, (_house_req["wall"] as Color).to_html(), (_house_req["roof"] as Color).to_html(), (_house_req["door"] as Color).to_html()])
	# A note or two stuck to the front door.
	var door: Vector3 = at + (_spec.get("door", Vector3(0.0, 1.6, depth * 0.5 + 0.07)) as Vector3)
	for index: int in _rng.randi_range(0, 2):
		_Doodles.place_paper(self, _Doodles.note(_rng.randi() % 50), door + Vector3(-0.15 + float(index) * 0.25, 0.3 - float(index) * 0.2, 0.02), Vector3.BACK, Vector2(0.19, 0.19), _rng.randf_range(-0.3, 0.3))
	# Windows to wash.
	for entry: Array in _spec.get("windows", []):
		var spot_at: Vector3 = at + (entry[0] as Vector3)
		var normal: Vector3 = entry[1]
		var size: Vector2 = entry[2] if entry.size() > 2 else Vector2.ZERO
		var index: int = _tasks.call("define_spot", "wash_windows", to_global(spot_at + normal * 0.04), normal, 0.7)
		_looks.call("add_window", index, to_global(spot_at + normal * 0.06), normal, size)
	_roof(_spec.get("roof", {}))
	_gutters()


## The roof you can climb onto from a ladder: two slopes up to the ridge of the
## house's main gable (HouseSpec "roof", always a gable along x for a job
## house), anything standing on it (dormers, chimneys, cross-gables: HouseSpec
## "roof_blockers") and lower roofs (estate wings: "roof_solids") as boxes, and
## leaves lying on it for the clear-the-roof task, never inside a blocker.
func _roof(roof: Dictionary) -> void:
	var center: Vector3 = _house_at + (roof.get("center", Vector3(0.0, 3.5, 0.0)) as Vector3)
	var top := center.y
	var rise := float(roof.get("rise", 3.0))
	var half_run := float(roof.get("half_run", 4.0))
	var width := float(roof.get("width", 10.0))
	var slope := atan2(rise, half_run)
	var length := Vector2(half_run, rise).length()
	var body := StaticBody3D.new()
	body.name = "Roof"
	add_child(body)
	var blockers: Array[AABB] = []
	for entry: Array in (_spec.get("roof_blockers", []) as Array) + (_spec.get("roof_solids", []) as Array):
		var size: Vector3 = entry[1]
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		shape.position = _house_at + (entry[0] as Vector3)
		body.add_child(shape)
		blockers.append(AABB(shape.position - size * 0.5, size).grow(0.35))
	# The leaves cover the part of the slope over the walls (the eaves overhang
	# the gable ends by half a meter each side).
	var span := maxf(width - 1.0, 2.0)
	# How many spots, and the gameplay rng's jitter draws, come from the yard's own
	# house width (as on the old box house), never from the archetype's roof, so
	# the hood never changes how many draws there are.
	var columns := maxi(2, int((_house_rect.size.x - 1.2) / 2.2))
	var gap := Constants.ART_YARD_ROOF_SPOT_GAP
	var free := func(spot: Vector3, taken: Array[Vector3]) -> bool:
		if blockers.any(func(blocker: AABB) -> bool: return blocker.has_point(spot)):
			return false
		return not taken.any(func(other: Vector3) -> bool: return other.distance_to(spot) < gap)
	var on_slope := func(x: float, row: float, side: float) -> Vector3:
		return Vector3(x, top + rise * row + 0.05, center.z + side * half_run * (1.0 - row))
	var front_spots: Array[Vector3] = []
	var back_spots: Array[Vector3] = []
	var slopes := {1.0: front_spots, -1.0: back_spots}
	for side: float in [1.0, -1.0]:
		var normal := Vector3(0.0, cos(slope), side * sin(slope))
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(width, 0.3, length)
		shape.shape = box
		shape.transform = Transform3D(Basis(Vector3.RIGHT, side * slope), Vector3(center.x, top + rise * 0.5, center.z + side * half_run * 0.5) - normal * 0.15)
		body.add_child(shape)
		var spots: Array[Vector3] = slopes[side]
		for row: float in [0.3, 0.7]:
			for column: int in columns:
				# Drawn even when the spot is blocked: the gameplay rng's draws never change.
				var x := center.x - span * 0.5 + (float(column) + 0.5) * span / float(columns) + _rng.randf_range(-0.4, 0.4)
				var spot: Vector3 = on_slope.call(x, row, side)
				if free.call(spot, spots):
					spots.append(spot)
	# Spots a dormer, a chimney or a narrow roof took slide to whatever free roof
	# is left (middle rows first, from the middle out): first on their own
	# slope, then, for a slope that is all dormers (an estate's front), on the
	# other one, so every house's roof is about as much work as the old box's.
	var steps := maxi(1, int(span / 0.5))
	var fill := func(side: float, wanted: int) -> void:
		var spots: Array[Vector3] = slopes[side]
		for row: float in [0.5, 0.3, 0.7, 0.15, 0.85]:
			for step: int in steps + 1:
				if spots.size() >= wanted:
					return
				var offset := float(ceili(float(step) * 0.5)) * span / float(steps) * (1.0 if step % 2 == 1 else -1.0)
				var spot: Vector3 = on_slope.call(center.x + offset, row, side)
				if absf(offset) <= span * 0.5 and free.call(spot, spots):
					spots.append(spot)
	for side: float in [1.0, -1.0]:
		fill.call(side, columns * 2)
	for side: float in [1.0, -1.0]:
		var other: Array[Vector3] = slopes[-side]
		fill.call(side, columns * 4 - other.size())
	for side: float in [1.0, -1.0]:
		var normal := Vector3(0.0, cos(slope), side * sin(slope))
		for spot: Vector3 in slopes[side]:
			var index: int = _tasks.call("define_spot", "clear_roof", to_global(spot), normal, 1.0)
			_looks.call("add_roof_leaves", index, to_global(spot), normal)


## Gutters on the main roof's front and back eaves (HouseSpec "gutters", split
## around anything that crosses an eave), a section to clean every two meters.
func _gutters() -> void:
	var pieces: Array = _spec.get("gutters", [])
	var per_side := {}
	for piece: Array in pieces:
		var key := signf((piece[2] as Vector3).z)
		per_side[key] = int(per_side.get(key, 0)) + 1
	for piece: Array in pieces:
		var from: Vector3 = _house_at + (piece[0] as Vector3)
		var to: Vector3 = _house_at + (piece[1] as Vector3)
		# The normal points out from the wall, which way a ladder leans out.
		var normal: Vector3 = piece[2]
		var run := to - from
		var along := Vector3(run.x, 0.0, run.z).normalized()
		_kit.call("box", Vector3(run.length(), 0.14, 0.18), (from + to) * 0.5, GUTTER, "metal", Basis(along, Vector3.UP, along.cross(Vector3.UP)))
		var least := 2 if int(per_side.get(signf(normal.z), 1)) == 1 else 1
		var sections := maxi(least, int(run.length() / 2.0))
		for section: int in sections:
			var spot_at := from.lerp(to, (float(section) + 0.5) / float(sections)) + Vector3(0.0, 0.08, 0.0)
			var index: int = _tasks.call("define_spot", "clean_gutters", to_global(spot_at), normal, 1.0)
			_looks.call("add_gutter", index, to_global(spot_at))


## How deep the porch and steps reach past the facade, and where the front walk starts.
func _porch_front() -> float:
	var depth := float(_spec.get("depth", _house_rect.size.y - 3.6))
	return _house_at.z + depth * 0.5 + float(_spec.get("porch_depth", 2.6))


## The house with its porch and steps (yard x and z): no lawn grows and no
## leaves fall in here (a porch deck would hide them).
func _built_rect() -> Rect2:
	return Rect2(_house_rect.position, Vector2(_house_rect.size.x, maxf(_porch_front(), _house_rect.end.y - 3.0) - _house_rect.position.y))


## The front door's x, where the walk and the beds line up.
func _door_x() -> float:
	return _house_at.x + float((_spec.get("door", Vector3.ZERO) as Vector3).x)


func _driveway() -> void:
	# From the street to the porch: Chefty pulls up it, and its stains get washed.
	# Concrete, or the hood's gravel or pavers.
	var surface := _drive_surface()
	_kit.call("box", Vector3(4.2, 0.03, 17.0), Vector3(0.0, 0.015, 11.5), DRIVE[surface], surface)
	var walk_from := _porch_front()
	if walk_from < 3.0:
		_kit.call("box", Vector3(Constants.ART_YARD_WALK_WIDTH, 0.03, 3.0 - walk_from), Vector3(_door_x(), 0.015, (walk_from + 3.0) * 0.5), (DRIVE[surface] as Color).lightened(0.04), surface)
		_walk_rect = Rect2(_door_x() - Constants.ART_YARD_WALK_WIDTH * 0.5, walk_from, Constants.ART_YARD_WALK_WIDTH, 3.0 - walk_from)
	set_meta("front_walk", _walk_rect)
	_art_notes.append(["drive", surface])


## The drive's surface from the street's style: gravel lanes get a gravel drive,
## paver sidewalks paver drives, everyone else concrete.
func _drive_surface() -> String:
	var street: Dictionary = _style.get("street", {})
	if str(street.get("surface", "road")) == "gravel":
		return "gravel"
	if str(street.get("sidewalk", "")) == "pavers":
		return "pavers"
	return "concrete"


## Flower beds in front of the porch, either side of the front walk, edged in
## the hood's way (brick, stone, timber, a row of old tires), with weeds coming
## up among the flowers.
##
## Whether each bed is there, how long it is, and its flowers and weeds are the
## gameplay rng's draws in their old order and count, decided against the
## house's middle as on the old box house, so the hood never changes them (nor
## how often a yard has weeds to pull). Only where they stand is the hood's:
## either side of the walk to its door (_bed_xs). A strip in front of every house
## (Constants.ART_YARD_BED_STRIP) is kept clear for them whatever the porch, so
## nothing placed later moves with the hood either.
func _beds() -> void:
	var middle := _house_rect.get_center().x
	var beds: Array = []
	for side: float in [-1.0, 1.0]:
		if _rng.randf() < 0.25:
			continue
		var length := _rng.randf_range(2.4, 3.6)
		var x := middle + side * (1.1 + length * 0.5)
		if x - length * 0.5 < _house_rect.position.x or x + length * 0.5 > _house_rect.end.x:
			continue
		var blooms: Array = []
		for flower: int in int(length * 2.0):
			blooms.append([_rng.randf_range(-0.35, 0.35), _rng.randi()])
		var weeds: Array[Vector2] = []
		for weed: int in _rng.randi_range(3, 5):
			weeds.append(Vector2(_rng.randf_range(-length * 0.45, length * 0.45), _rng.randf_range(-0.45, 0.45)))
		beds.append([side, length, blooms, weeds])
	_taken.append(Rect2(_house_rect.position.x, _house_rect.end.y, _house_rect.size.x, Constants.ART_YARD_BED_STRIP))
	var xs := _bed_xs(beds)
	var front := _porch_front() + 0.1
	var edge := str(_style.get("bed_edge", "concrete"))
	var flowers := WINTER_FLOWERS if Seasons.current() == 1 else FLOWER_COLORS
	var bed_rects: Array[Rect2] = []
	for bed_index: int in beds.size():
		var bed: Array = beds[bed_index]
		var x: float = (xs[bed_index] as Vector2).x
		# A bed squeezed in beside a corner door's walk is drawn shorter: the same
		# flowers and weeds, closer together.
		var squeeze: float = (xs[bed_index] as Vector2).y
		var length: float = float(bed[1]) * squeeze
		var rect := Rect2(x - length * 0.5, front, length, 1.3)
		bed_rects.append(rect)
		var weed_spots: Array[Vector2] = []
		for weed: Vector2 in bed[3]:
			weed_spots.append(rect.get_center() + Vector2(weed.x * squeeze, weed.y))
		_bed_boxes.append([Vector3(rect.get_center().x, 0.0, rect.get_center().y), Vector3(length, 0.12, 1.3), _mums_spot(rect, weed_spots)])
		# Tires stick out past the bed's front edge.
		var reach := Rect2(rect.position, rect.size + Vector2(0.0, 0.45 if edge == "tire" else 0.0))
		_no_lawn.append(reach)
		var center := Vector3(rect.get_center().x, 0.0, rect.get_center().y)
		_kit.call("box", Vector3(length, 0.12, 1.3), center + Vector3(0.0, 0.06, 0.0), BED_DIRT, "dirt")
		if edge == "tire":
			# Old tires along the front, half sunk, painted once upon a time.
			var tires := maxi(2, int(length / 0.62))
			for tire: int in tires:
				var tire_x := center.x - length * 0.5 + 0.3 + float(tire) * (length - 0.6) / float(tires - 1)
				_kit.call("cylinder", 0.3, 0.16, Vector3(tire_x, 0.07, center.z + 0.72), TIRE, "plain", 10)
				_kit.call("cylinder", 0.17, 0.17, Vector3(tire_x, 0.075, center.z + 0.72), BED_DIRT.darkened(0.2), "dirt", 8)
		else:
			var look: Array = BED_EDGES.get(edge, BED_EDGES["concrete"])
			_kit.call("box", Vector3(length + 0.2, 0.18, 0.12), center + Vector3(0.0, 0.09, 0.7), look[0], look[1])
		var kit := _MeshKit.new()
		var blooms: Array = bed[2]
		for flower: int in blooms.size():
			var spot := center + Vector3(-length * 0.5 + (0.3 + float(flower) * 0.5) * squeeze, 0.0, float(blooms[flower][0]))
			kit.tube(PackedVector3Array([spot, spot + Vector3(0.0, 0.32, 0.0)]), PackedFloat32Array([0.015, 0.012]), Color(0.3, 0.55, 0.25), 4, {"jitter": 0.0, "sway_to": 0.6})
			kit.blob(spot + Vector3(0.0, 0.36, 0.0), Vector3(0.09, 0.06, 0.09), flowers[int(blooms[flower][1]) % flowers.size()], {"detail": 1, "lumps": 0.3, "flat": true, "jitter": 0.05, "sway": 0.8, "seed": flower})
		add_child(_Stylized.instance(kit.commit(), {"wind": 0.04, "roughness": 0.9}))
		for weed: Vector2 in bed[3]:
			var spot := center + Vector3(weed.x * squeeze, 0.12, weed.y)
			var index: int = _tasks.call("define_spot", "pull_weeds", to_global(spot), Vector3.UP, 0.3)
			_looks.call("add_weed", index, to_global(spot))
		_note(["bed", rect])
	set_meta("bed_rects", bed_rects)
	_art_notes.append(["beds", edge])


## Where the job house's autumn mums pot stands in bed rect (yard space, front
## edge toward the street): at the back by the porch, the walk's end first, then
## the far end, then the middle, wherever it is ART_JOB_MUMS_WEED_CLEAR from every
## weed (so it never hides one from the street), or null. Inside the bed, it is
## clear of the edging and the tires, and no grass grows through it. Look only.
func _mums_spot(rect: Rect2, weeds: Array[Vector2]) -> Variant:
	var inset := Constants.ART_JOB_MUMS_INSET
	if rect.size.x < inset * 2.0 or rect.size.y < inset * 2.0:
		return null
	var toward := 1.0 if _door_x() >= rect.get_center().x else -1.0
	var reach := rect.size.x * 0.5 - inset
	var z := rect.position.y + inset
	for x: float in [rect.get_center().x + toward * reach, rect.get_center().x - toward * reach, rect.get_center().x]:
		var clear := true
		for weed: Vector2 in weeds:
			if weed.distance_to(Vector2(x, z)) < Constants.ART_JOB_MUMS_WEED_CLEAR:
				clear = false
		if clear:
			return Vector3(x, 0.0, z)
	return null


## Where each bed ([side, length, ...]) stands along the house front, as
## Vector2(center x, squeeze): either side of the walk to the door, or, when the
## door sits too near a corner for a bed on that side, past its sibling on the
## roomy side. Failing that (a door so near a corner that the pair fits on
## neither side), they are packed beside the walk on whatever room there is,
## drawn shorter (squeeze < 1). A bed never leaves the house's width and never
## touches the front walk: its inner edge stays Constants.ART_YARD_BED_FROM_WALK from the walk's
## middle. (The old last resort slid the pair round the house's middle and left
## the walk where it was, so about 1 yard in 30 had a bed across its walk.)
func _bed_xs(beds: Array) -> Array[Vector2]:
	var door := _door_x()
	var low := _house_rect.position.x
	var high := _house_rect.end.x
	var xs: Array[Vector2] = []
	var misfits: Array[int] = []
	# How far along each side of the walk is already used.
	var used := {-1.0: Constants.ART_YARD_BED_FROM_WALK, 1.0: Constants.ART_YARD_BED_FROM_WALK}
	for index: int in beds.size():
		var side: float = beds[index][0]
		var length: float = beds[index][1]
		var x := door + side * (Constants.ART_YARD_BED_FROM_WALK + length * 0.5)
		xs.append(Vector2(x, 1.0))
		if x - length * 0.5 < low or x + length * 0.5 > high:
			misfits.append(index)
		else:
			used[side] = Constants.ART_YARD_BED_FROM_WALK + length + Constants.ART_YARD_BED_GAP
	for index: int in misfits:
		var side: float = -float(beds[index][0])
		var length: float = beds[index][1]
		var x := door + side * (float(used[side]) + length * 0.5)
		if x - length * 0.5 >= low and x + length * 0.5 <= high:
			xs[index] = Vector2(x, 1.0)
			used[side] = float(used[side]) + length + Constants.ART_YARD_BED_GAP
			continue
		return _packed_beds(beds, door, low, high)
	return xs


## The last resort of _bed_xs: each bed on its own side of the walk, shortened
## to the room there, or, when one side has too little room for a bed, both on
## the other side, shortened together to fit.
func _packed_beds(beds: Array, door: float, low: float, high: float) -> Array[Vector2]:
	var room := {-1.0: maxf(door - Constants.ART_YARD_BED_FROM_WALK - low, 0.0), 1.0: maxf(high - door - Constants.ART_YARD_BED_FROM_WALK, 0.0)}
	var roomy := -1.0 if float(room[-1.0]) > float(room[1.0]) else 1.0
	var out: Array[Vector2] = []
	var own_sides := true
	for bed: Array in beds:
		if float(room[float(bed[0])]) < Constants.ART_YARD_BED_MIN_LENGTH:
			own_sides = false
	if own_sides:
		for bed: Array in beds:
			var side := float(bed[0])
			var squeeze := minf(1.0, float(room[side]) / float(bed[1]))
			out.append(Vector2(door + side * (Constants.ART_YARD_BED_FROM_WALK + float(bed[1]) * squeeze * 0.5), squeeze))
		return out
	var total := 0.0
	for bed: Array in beds:
		total += float(bed[1])
	var gaps := Constants.ART_YARD_BED_GAP * float(beds.size() - 1)
	var squeeze := clampf((float(room[roomy]) - gaps) / total, 0.1, 1.0)
	var along := Constants.ART_YARD_BED_FROM_WALK
	for bed: Array in beds:
		var length := float(bed[1]) * squeeze
		out.append(Vector2(door + roomy * (along + length * 0.5), squeeze))
		along += length + Constants.ART_YARD_BED_GAP
	return out


# ---------------------------------------------------------------- the yard

func _trees_around() -> void:
	var counts: Vector2i = Constants.YARD_TREES[_size]
	var count := _rng.randi_range(counts.x, counts.y)
	var attempts := 0
	while _trees.size() < count and attempts < 60:
		attempts += 1
		var at := Vector3(_rng.randf_range(-16.5, 16.5), 0.0, _rng.randf_range(-16.5, 17.0))
		var rect := Rect2(at.x - 1.6, at.z - 1.6, 3.2, 3.2)
		if _overlaps(rect, 1.0):
			continue
		var crowded := false
		for other: Vector3 in _trees:
			if other.distance_to(at) < 6.5:
				crowded = true
		if crowded:
			continue
		_trees.append(at)
		_taken.append(rect)
		# The gameplay rng's draws, as always (kind, height, crown, variant, turn);
		# what kind of tree and crown it is, and how tall, is the hood's (_art).
		var _old_kind := _rng.randf()
		var height := _rng.randf_range(7.0, 9.5)
		var _old_crown := _rng.randi()
		var variant := _rng.randi() % 4
		var yaw := _rng.randf() * TAU
		var trees: Dictionary = _style.get("trees", {})
		var kind := str(_HoodStyles.pick(_art, trees.get("kinds", [["broadleaf", 1]])))
		var crown := str(_HoodStyles.pick(_art, trees.get("crowns", [["orange", 1]])))
		var heights: Vector2 = trees.get("height", Vector2(7.0, 9.5))
		# The yard's own trees stay big enough to bury a lawn (a staked sapling drops nothing).
		var tall := maxf(lerpf(heights.x, heights.y, (height - 7.0) / 2.5), Constants.ART_YARD_TREE_MIN_HEIGHT)
		_Trees.spawn(self, at, tall, kind, crown, variant, true, yaw)
		_tree_looks.append([at, kind, crown])
		_art_notes.append([kind, crown, snappedf(tall, 0.01)])
		_note(["tree", at])


## A big yard's above-ground pool: round, waist high, with leaves floating on it
## to scoop out by hand (reach over the side with E).
func _pool() -> void:
	for _attempt: int in 40:
		var at := Vector3(_rng.randf_range(-15.0, 15.0), 0.0, _rng.randf_range(-12.0, 14.0))
		var rect := Rect2(at.x - POOL_RADIUS - 0.4, at.z - POOL_RADIUS - 0.4, POOL_RADIUS * 2.0 + 0.8, POOL_RADIUS * 2.0 + 0.8)
		if _overlaps(rect, 1.2):
			continue
		_pool_at = at
		_taken.append(rect)
		_no_lawn.append(rect)
		_note(["pool", at])
		# A concrete pad under it (decoration: no collider).
		var pad := POOL_RADIUS * 2.0 + 0.7
		_kit.call("box", Vector3(pad, 0.04, pad), at + Vector3(0.0, 0.02, 0.0), DRIVE["concrete"], "concrete")
		_looks.call("add_pool", to_global(at), POOL_RADIUS, POOL_HEIGHT)
		var body := StaticBody3D.new()
		body.name = "PoolBody"
		var shape := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.radius = POOL_RADIUS + 0.08
		cylinder.height = POOL_HEIGHT
		shape.shape = cylinder
		body.add_child(shape)
		add_child(body)
		body.position = at + Vector3(0.0, POOL_HEIGHT * 0.5, 0.0)
		# Clumps of leaves floating on the water.
		for clump: int in _rng.randi_range(5, 8):
			var angle := _rng.randf() * TAU
			# Not out in the very middle: someone reaching over the side has to get to it.
			var reach := 0.9 + sqrt(_rng.randf()) * (POOL_RADIUS - 1.3)
			var spot := at + Vector3(cos(angle) * reach, POOL_HEIGHT - 0.12, sin(angle) * reach)
			var index: int = _tasks.call("define_spot", "skim_pool", to_global(spot), Vector3.UP, 0.5)
			_looks.call("add_pool_leaves", index, to_global(spot), _rng.randi())
		return


## Hedges down one or both sides, shaggy where they need trimming.
func _hedges() -> void:
	for side: float in [-1.0, 1.0]:
		if _rng.randf() < 0.35:
			continue
		var length := _rng.randf_range(6.0, 12.0)
		var z := _rng.randf_range(-15.0, 15.0 - length)
		var x := side * 17.9
		var rect := Rect2(x - 0.8, z, 1.6, length)
		if _overlaps(rect, 0.3):
			continue
		_taken.append(rect)
		_no_lawn.append(rect)
		var center := Vector3(x, 0.0, z + length * 0.5)
		var hedge := _YardModels.node("hedge", Color(0.24, 0.42, 0.22), Vector3(1.3, 1.5, length))
		add_child(hedge)
		hedge.position = center
		_solid_box(center + Vector3(0.0, 0.75, 0.0), Vector3(1.3, 1.5, length), "Hedge%d" % int(side))
		for section: int in int(length / 1.5):
			var spot := Vector3(x, 1.55, z + 0.75 + float(section) * 1.5)
			var index: int = _tasks.call("define_spot", "trim_hedges", to_global(spot), Vector3.UP, 0.8)
			_looks.call("add_shaggy", index, to_global(spot))
		_note(["hedge", rect])


## The hood's fence along the back and sides (hood_styles.gd "job_fence":
## pickets, weathered pickets, white vinyl, split rails, a privacy fence, or
## iron), in panels the paint task can refresh: one mesh per panel, repainted
## from the style's faded color to its fresh one (rusty to glossy black, for iron).
func _fences() -> void:
	var look: Dictionary = _style.get("job_fence", {})
	var kind := str(look.get("kind", "picket"))
	if not FENCE_KINDS.has(kind):
		kind = "picket"
	var fresh: Color = look.get("fresh", _TaskLooks.FRESH_PAINT)
	var faded: Color = look.get("faded", _TaskLooks.FADED_PAINT)
	var surface := str(look.get("surface", "planks"))
	_art_notes.append(["fence", kind, fresh.to_html(), faded.to_html(), surface])
	for run: Array in FENCE_RUNS:
		var from: Vector3 = run[0]
		var to: Vector3 = run[1]
		var inward: Vector3 = run[2]
		var length := from.distance_to(to)
		var panels := int(length / 2.4)
		for panel: int in panels:
			var a := from.lerp(to, float(panel) / float(panels))
			var b := from.lerp(to, float(panel + 1) / float(panels))
			var holder := Node3D.new()
			holder.name = "FencePanel"
			add_child(holder)
			# One color per panel and no per-vertex paint: the paint task swaps its material.
			var kit: RefCounted = _HouseKit.new()
			kit.set("paint_per_vertex", false)
			_fence_panel(kit, a, b, inward, kind, faded, surface)
			kit.call("commit", holder, "Look")
			var middle := (a + b) * 0.5
			var index: int = _tasks.call("define_spot", "paint_fence", to_global(middle + Vector3(0.0, 0.5, 0.0) + inward * 0.1), inward, 1.2)
			_looks.call("add_fence_panel", index, holder, fresh, faded, surface)


## One fence panel from a to b (the yard side is inward), in one color, into kit.
func _fence_panel(kit: RefCounted, a: Vector3, b: Vector3, inward: Vector3, kind: String, color: Color, surface: String) -> void:
	var length := a.distance_to(b)
	var along := (b - a).normalized()
	var turn := Basis(along, Vector3.UP, along.cross(Vector3.UP))
	var middle := (a + b) * 0.5
	# Panel space: x along the fence, y up, z across (the yard is at -z or +z).
	var place := func(local: Vector3) -> Vector3: return middle + turn * local
	var back := -signf(turn.z.dot(inward)) if turn.z.dot(inward) != 0.0 else -1.0
	match kind:
		"picket", "weathered_picket":
			var weathered := kind == "weathered_picket"
			var pickets := int(length / 0.3)
			# A missing one every few (weathered), never two in a row.
			var skip := -1
			if weathered:
				skip = _art.randi_range(0, pickets + 3)
			for picket: int in pickets:
				if picket == skip:
					continue
				var x := -length * 0.5 + (float(picket) + 0.5) * length / float(pickets)
				var tall := 0.85 - (_art.randf_range(0.0, 0.12) if weathered else 0.0)
				var lean := Basis(Vector3.BACK, _art.randf_range(-0.06, 0.06)) if weathered else Basis.IDENTITY
				kit.call("box", Vector3(0.1, tall, 0.04), place.call(Vector3(x, tall * 0.5, 0.0)), color, surface, turn * lean)
				kit.call("prism", Vector3(0.1, 0.07, 0.04), place.call(Vector3(x, tall + 0.035, 0.0)), color, surface, turn * lean)
			for y: float in [0.25, 0.62]:
				kit.call("box", Vector3(length, 0.07, 0.04), place.call(Vector3(0.0, y, back * 0.04)), color, surface, turn)
		"vinyl":
			for side: float in [-1.0, 1.0]:
				kit.call("box", Vector3(0.12, 1.15, 0.12), place.call(Vector3(side * (length * 0.5 - 0.06), 0.575, 0.0)), color, surface, turn)
				kit.call("prism", Vector3(0.14, 0.06, 0.14), place.call(Vector3(side * (length * 0.5 - 0.06), 1.18, 0.0)), color, surface, turn)
			for y: float in [0.12, 0.98]:
				kit.call("box", Vector3(length - 0.24, 0.09, 0.06), place.call(Vector3(0.0, y, 0.0)), color, surface, turn)
			var slats := int((length - 0.24) / 0.16)
			for slat: int in slats:
				var x := -(length - 0.24) * 0.5 + (float(slat) + 0.5) * (length - 0.24) / float(slats)
				kit.call("box", Vector3(0.12, 0.82, 0.03), place.call(Vector3(x, 0.55, 0.0)), color, surface, turn)
		"split_rail":
			for side: float in [-1.0, 1.0]:
				kit.call("box", Vector3(0.16, 1.05, 0.16), place.call(Vector3(side * (length * 0.5 - 0.08), 0.525, 0.0)), color, surface, turn)
			for y: float in [0.42, 0.82]:
				var sag := _art.randf_range(-0.04, 0.02)
				kit.call("box", Vector3(length - 0.1, 0.12, 0.1), place.call(Vector3(0.0, y + sag, 0.0)), color, surface, turn * Basis(Vector3.BACK, _art.randf_range(-0.02, 0.02)))
		"privacy":
			var boards := int(length / 0.15)
			for board: int in boards:
				var x := -length * 0.5 + (float(board) + 0.5) * length / float(boards)
				kit.call("box", Vector3(0.14, 1.6, 0.025), place.call(Vector3(x, 0.8, 0.0)), color, surface, turn)
			for y: float in [0.3, 1.3]:
				kit.call("box", Vector3(length, 0.09, 0.04), place.call(Vector3(0.0, y, back * 0.035)), color, surface, turn)
		"iron":
			for side: float in [-1.0, 1.0]:
				kit.call("box", Vector3(0.09, 1.3, 0.09), place.call(Vector3(side * (length * 0.5 - 0.045), 0.65, 0.0)), color, surface, turn)
				kit.call("cylinder", 0.07, 0.06, place.call(Vector3(side * (length * 0.5 - 0.045), 1.33, 0.0)), color, surface, 6)
			for y: float in [0.1, 1.0]:
				kit.call("box", Vector3(length - 0.09, 0.04, 0.04), place.call(Vector3(0.0, y, 0.0)), color, surface, turn)
			var bars := int(length / 0.13)
			for bar: int in bars:
				var x := -length * 0.5 + (float(bar) + 0.5) * length / float(bars)
				kit.call("box", Vector3(0.022, 1.08, 0.022), place.call(Vector3(x, 0.6, 0.0)), color, surface, turn)
				kit.call("prism", Vector3(0.06, 0.1, 0.03), place.call(Vector3(x, 1.19, 0.0)), color, surface, turn)


func _hide_spots(lot: Node3D) -> void:
	# The hood's shed (a rusty one in Dandelion Acres, a painted pool house on Mansion Hill).
	var shed: Color = _style.get("shed", Color(0.5, 0.4, 0.3))
	var spots: Array = [
		["Shed", Vector3(2.4, 2.4, 2.0), shed, "Shed", "planks"],
		["BigBin", Vector3(1.4, 1.3, 1.0), Color(0.25, 0.3, 0.32), "Big bin", "metal"],
		["Hedge", Vector3(3.0, 1.6, 1.2), Color(0.2, 0.42, 0.22), "Hedge", "foliage"],
	]
	_art_notes.append(["shed", shed.to_html()])
	for entry: Array in spots:
		var size: Vector3 = entry[1]
		var placed := false
		for _attempt: int in 40:
			var at := Vector3(_rng.randf_range(-17.0, 17.0), 0.0, _rng.randf_range(-17.5, 17.0))
			var rect := Rect2(at.x - size.x * 0.5, at.z - size.z * 0.5, size.x, size.z)
			if _overlaps(rect, 1.2):
				continue
			_taken.append(rect)
			_no_lawn.append(rect)
			var spot := _HideSpot.instantiate()
			spot.name = entry[0]
			spot.set("size", size)
			spot.set("color", entry[2])
			spot.set("label", entry[3])
			spot.set("surface", entry[4])
			spot.position = at
			lot.add_child(spot)
			_note([entry[0], at])
			placed = true
			break
		if not placed:
			push_warning("[Lot] no room for %s" % entry[0])


## The house's spigot on a side wall, and a fire hydrant on the sidewalk out front.
func _water(lot: Node3D) -> void:
	# Drawn as always; the house's own spigot (HouseSpec "spigot") says which wall now.
	var side := -1.0 if _rng.randf() < 0.5 else 1.0
	var normal := Vector3(side, 0.0, 0.0)
	var wall_x := (_house_rect.position.x + 0.6) if side < 0.0 else (_house_rect.end.x - 0.6)
	var house_depth := _house_rect.size.y - 3.6
	var spigot_at := Vector3(wall_x + side * 0.05, 0.7, _house_rect.position.y + 0.6 + house_depth * 0.7)
	var on_house: Array = _spec.get("spigot", [])
	if on_house.size() == 2:
		normal = on_house[1]
		spigot_at = _house_at + (on_house[0] as Vector3) + normal * 0.03 + Vector3(0.0, 0.1, 0.0)
	var spigot := _YardModels.node("spigot", Color.WHITE, Vector3.ONE, {"roughness": 0.35, "specular": 0.6})
	add_child(spigot)
	spigot.position = spigot_at
	# The model's spout points -Z: turn it out from the wall.
	spigot.rotation.y = atan2(-normal.x, -normal.z)
	_WaterSources.make(lot, "spigot", spigot_at + normal * 0.18 + Vector3(0.0, -0.08, 0.0))
	var hydrant_x := _rng.randf_range(6.0, 15.0) * (-1.0 if _rng.randf() < 0.5 else 1.0)
	var hydrant_at := Vector3(hydrant_x, 0.1, 21.0)
	var hydrant := _YardModels.node("hydrant", Color.WHITE, Vector3.ONE, {"roughness": 0.5, "specular": 0.3})
	add_child(hydrant)
	hydrant.position = hydrant_at
	_solid_box(hydrant_at + Vector3(0.0, 0.4, 0.0), Vector3(0.4, 0.8, 0.4), "Hydrant")
	_WaterSources.make(lot, "hydrant", hydrant_at + Vector3(0.0, 0.42, -0.22))
	_note(["water", spigot_at, hydrant_at])
	# A paint bucket by the tools, for dipping the roller.
	var bucket_at := Vector3(-9.3, 0.0, 18.4)
	var bucket := _YardModels.node("paint_bucket", Color.WHITE, Vector3.ONE, {"roughness": 0.5, "specular": 0.3})
	add_child(bucket)
	bucket.position = bucket_at
	var marker := Node3D.new()
	marker.name = "PaintBucket"
	marker.add_to_group("paint_buckets")
	add_child(marker)
	marker.position = bucket_at + Vector3(0.0, 0.4, 0.0)


## Two loungers by a big yard's pool, where there's room (decoration: no
## collider). Lawn and litter keep off them. Every hood gets them in the same
## places (their own rng, from the job seed alone, and a _taken the hood never
## changes), so the litter scattered after them never moves with the hood.
func _pool_lounge() -> void:
	if _pool_at == Vector3.INF:
		return
	var lounge := RandomNumberGenerator.new()
	lounge.seed = hash([_job_seed, "lounge"])
	var placed := 0
	for _attempt: int in 12:
		if placed >= 2:
			break
		var angle := lounge.randf() * TAU
		var reach := POOL_RADIUS + 1.8
		var at := _pool_at + Vector3(cos(angle) * reach, 0.0, sin(angle) * reach)
		var rect := Rect2(at.x - 1.1, at.z - 1.1, 2.2, 2.2)
		if _overlaps(rect, 0.2):
			continue
		_taken.append(rect)
		_no_lawn.append(rect)
		var lounger := _PropCatalog.node("pool_lounger")
		lounger.name = "PoolLounger%d" % placed
		add_child(lounger)
		lounger.position = at
		# Feet toward the water.
		lounger.rotation.y = atan2(at.x - _pool_at.x, at.z - _pool_at.z)
		_art_notes.append(["lounger", at.snapped(Vector3.ONE * 0.01)])
		placed += 1


## Cans, wrappers, and bottles dropped on the lawn.
func _litter() -> void:
	var counts: Vector2i = Constants.YARD_LITTER[_size]
	for piece: int in _rng.randi_range(counts.x, counts.y):
		for _attempt: int in 20:
			var at := Vector3(_rng.randf_range(-18.0, 18.0), 0.05, _rng.randf_range(-18.0, 18.5))
			if _overlaps(Rect2(at.x - 0.3, at.z - 0.3, 0.6, 0.6), 0.0):
				continue
			var index: int = _tasks.call("define_spot", "pick_litter", to_global(at), Vector3.UP, 0.4)
			_looks.call("add_litter", index, to_global(at), _rng.randi())
			break


## The lawn to mow (everywhere grass grows) and the driveway's oil stains.
func _grids() -> void:
	var lot_global := get_parent() as Node3D
	var house := _built_rect()
	var no_lawn := _no_lawn.duplicate()
	# No grass to mow on the front walk either (it grew through the paving).
	var walk := _walk_rect.grow(0.15) if _walk_rect.has_area() else Rect2()
	var lawn: int = _tasks.call("define_grid", "mow_lawn", to_global(Vector3(-YARD_HALF, 0.0, -YARD_HALF)), Vector2(YARD_HALF * 2.0, YARD_HALF * 2.0), 1.0, func(center: Vector3) -> bool:
		var local := lot_global.to_local(center)
		var at := Vector2(local.x, local.z)
		if house.grow(-0.3).has_point(at) or Rect2(-2.2, 3.0, 4.4, 17.5).has_point(at) or walk.has_point(at):
			return false
		for rect: Rect2 in no_lawn:
			if rect.has_point(at):
				return false
		return true
	)
	_looks.call("add_lawn", lawn)
	var noise := FastNoiseLite.new()
	noise.seed = _rng.randi()
	noise.frequency = 0.6
	var stains: int = _tasks.call("define_grid", "power_wash", to_global(Vector3(-2.1, 0.0, 4.0)), Vector2(4.2, 15.5), 0.5, func(center: Vector3) -> bool:
		return noise.get_noise_2d(center.x, center.z) > 0.1
	)
	_looks.call("add_stains", stains)


## Leaves pile up thickest under the trees and thin out between them; none fall
## inside the house, and the driveway gets a light dusting.
func _shape_leaves(lot: Node3D) -> void:
	var field := lot.get_node_or_null("LeafField")
	if field == null:
		return
	var trees: Array[Vector3] = []
	for tree: Vector3 in _trees:
		trees.append(to_global(tree))
	var house := _built_rect()
	var spread := _rng.randf_range(Constants.YARD_TREE_SPREAD.x, Constants.YARD_TREE_SPREAD.y)
	var base := _rng.randf_range(Constants.YARD_LEAF_BASE.x, Constants.YARD_LEAF_BASE.y) * float(Constants.YARD_LEAVES[_size])
	# A yard done recently has had less time to fill back up.
	var grown := clampf(mess, 0.0, 1.5)
	# What falls where (leaves/leaf_renderer.gd colours each cell by the trees
	# over it): the yard's own trees, in the field's space. Every peer, from the seed.
	var sources: Array = []
	for child: Node in get_children():
		var tree := child as Node3D
		if tree == null or not _trees.has(tree.position) or tree.get("crown") == null:
			continue
		var at: Vector3 = (field as Node3D).to_local(to_global(tree.position))
		sources.append({"at": Vector2(at.x, at.z), "crown": str(tree.get("crown")), "kind": str(tree.get("kind")), "variant": int(tree.get("variant"))})
	field.set_meta("leaf_sources", sources)
	# The fence along the back and sides (_fences): raked leaves bank up against
	# it instead of being pushed through it (NB-08), in the field's space.
	var fence_lines: Array = []
	for run: Array in FENCE_RUNS:
		# Each run reaches back a metre past its start, so the corners close.
		var from: Vector3 = run[0]
		var to: Vector3 = run[1]
		var a: Vector3 = (field as Node3D).to_local(to_global(from - (to - from).normalized()))
		var b: Vector3 = (field as Node3D).to_local(to_global(to))
		fence_lines.append([Vector2(a.x, a.z), Vector2(b.x, b.z)])
	field.set_meta("fence_lines", fence_lines)
	field.call("shape_initial", func(world: Vector3) -> float:
		var local := lot.to_local(world)
		if house.grow(-0.4).has_point(Vector2(local.x, local.z)):
			return 0.0
		var amount := base
		for tree: Vector3 in trees:
			var distance := Vector2(world.x - tree.x, world.z - tree.z).length()
			amount += Constants.YARD_TREE_LEAVES * exp(-distance * distance / (2.0 * spread * spread))
		# None under the pool.
		if _pool_at != Vector3.INF and Vector2(local.x - _pool_at.x, local.z - _pool_at.z).length() < POOL_RADIUS + 0.2:
			return 0.0
		# The driveway is swept: leaves on it would only make washing it a chore.
		# Nor do they bury the tools laid out beside it, or the rake.
		if absf(local.x) < 3.0 and local.z > 3.0:
			return 0.0
		if Rect2(-10.0, 12.0, 6.5, 7.0).has_point(Vector2(local.x, local.z)):
			return 0.0
		return clampf(amount * grown, 0.0, Constants.YARD_LEAF_CAP)
	)


## Host only: the yard props start somewhere new each job.
func _place_props(lot: Node3D) -> void:
	for prop_name: String in ["TrashCan", "Wheelbarrow", "Gnome"]:
		var prop := lot.get_node_or_null(prop_name) as Node3D
		if prop == null:
			continue
		for _attempt: int in 30:
			var at := Vector3(_rng.randf_range(-16.0, 16.0), 0.25, _rng.randf_range(-16.0, 16.0))
			if _overlaps(Rect2(at.x - 0.6, at.z - 0.6, 1.2, 1.2), 0.5):
				continue
			_taken.append(Rect2(at.x - 0.6, at.z - 0.6, 1.2, 1.2))
			prop.position = at
			break


# ---------------------------------------------------------------- the hood's look

## The yard's ground in the hood's lawn color (the grass pattern, never mowed
## stripes, so the mowing task's own stripes stay readable), with the hood's
## all-year flowers (Dandelion Acres' dandelions) and dry patches.
func _paint_ground(lot: Node3D) -> void:
	var view := lot.get_node_or_null("Floor/Mesh") as MeshInstance3D
	if view == null:
		return
	var ground: Dictionary = _style.get("ground", {})
	var color: Color = ground.get("color", Color(0.42, 0.478, 0.271))
	var params := Vector4(0.0, 0.0, float(ground.get("flowers", 0.0)), 0.0)
	var dirt := clampf(float(ground.get("dirt", 0.0)), 0.0, 1.0)
	var accent := color.lerp(Color(0.62, 0.52, 0.32), dirt) if dirt > 0.0 else Color(0, 0, 0, 0)
	view.set_meta("surface", "grass")
	view.set_meta("surface_base", color)
	view.set_meta("surface_params", params)
	view.set_meta("surface_accent", accent)
	view.material_override = _Surfaces.material("grass", color, accent, params)
	_art_notes.append(["ground", color.to_html()])


## The house's own season decor, like its neighbors' (levels/town/season_dressing.gd,
## job: porch, beds, door and drive only, nothing on the lawn where the work is,
## and no string lights: a future hang-lights task owns those). Its root is a
## levels/town/parcel.gd in group "seasonal", so it redecorates itself the
## morning a season turns. Look only: no colliders, nothing a task uses.
func _season_decor() -> void:
	var holder: Node3D = _Parcel.new()
	holder.name = "JobDecor"
	holder.set("role", "parcel")
	holder.set("hood", str(_style["id"]))
	holder.set("seed_value", hash([_job_seed, "job_decor"]))
	holder.set("season", Seasons.current())
	holder.set("lights", false)
	var walk: Array = []
	if _walk_rect.has_area():
		walk = [Vector3(_walk_rect.get_center().x, 0.0, _walk_rect.position.y), Vector3(_walk_rect.get_center().x, 0.0, _walk_rect.end.y)]
	var pools: Array = []
	if _pool_at != Vector3.INF:
		# The above-ground pool's float rides on its water (task_looks.gd add_pool).
		pools.append(_pool_at + Vector3(0.0, POOL_HEIGHT - 0.23, 0.0))
	holder.set("decor", {
		"house_at": _house_at, "spec": _spec, "beds": _bed_boxes, "trees": _tree_looks,
		"drive": [Vector3(0.0, 0.0, 3.0), Vector3(0.0, 0.0, YARD_HALF)], "walk": walk, "pools": pools,
		"yard": [], "job": true,
	})
	add_child(holder)
	holder.call("dress")


## The street block around the yard (levels/town/block_builder.gd), built over
## the next few frames: neighbors, the street, set pieces, the back boundary,
## grass, and the yard's mailbox. In the connected town the town draws the
## street and the neighbors, so only the yard-scope art is done (critic C24).
func _start_block(lot: Node3D, yard_hash: int) -> void:
	var town := false
	if is_inside_tree():
		var world := get_tree().get_first_node_in_group("world")
		town = world != null and world.has_method("is_town_map") and bool(world.call("is_town_map"))
	var yard := {
		"house_rect": _house_rect, "pool_at": _pool_at, "driveway": [Vector3(0.0, 0.0, 3.0), Vector3(0.0, 0.0, YARD_HALF)],
		"clear": _no_lawn.duplicate(), "drive_surface": _drive_surface(),
	}
	_BlockBuilder.build_for_job(lot, hood, _job_seed, yard, {"town": town, "yard_hash": yard_hash})


# ---------------------------------------------------------------- helpers

func _overlaps(rect: Rect2, margin: float) -> bool:
	if rect.position.x < -YARD_HALF + 0.5 or rect.end.x > YARD_HALF - 0.5 or rect.position.y < -YARD_HALF + 0.5 or rect.end.y > YARD_HALF - 0.5:
		return true
	var grown := rect.grow(margin)
	for other: Rect2 in _taken:
		if grown.intersects(other):
			return true
	return false


func _solid_box(center: Vector3, size: Vector3, body_name: String) -> void:
	var body := StaticBody3D.new()
	body.name = body_name
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.position = center
