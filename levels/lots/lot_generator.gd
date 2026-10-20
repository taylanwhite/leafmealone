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
const YARD_HALF: float = 20.0
const PICKET := Color(0.93, 0.91, 0.86)
const CROWNS: Array[String] = ["orange", "red", "yellow", "rust", "turning"]
const BED_DIRT := Color(0.36, 0.25, 0.18)
const FLOWER_COLORS: Array[Color] = [Color(0.95, 0.35, 0.45), Color(0.98, 0.8, 0.25), Color(0.7, 0.45, 0.9), Color(0.98, 0.98, 0.95), Color(0.95, 0.55, 0.2)]

var _rng := RandomNumberGenerator.new()
## Lot-space rectangles (x and z) already used by something.
var _taken: Array[Rect2] = []
var _tasks: Node
var _looks: Node
var _trees: Array[Vector3] = []
var _house_rect := Rect2()
## Where no lawn grows: beds, hedges, the shed and bins.
var _no_lawn: Array[Rect2] = []
var _layout_hash: int = 0


func generate(job_seed: int, tasks: PackedStringArray) -> void:
	_rng.seed = job_seed
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
	_trees_around()
	_hedges()
	_fences()
	_hide_spots(lot)
	_litter()
	_grids()
	_tasks.call("activate", tasks, job_seed)
	_looks.call("setup", _tasks)
	_shape_leaves(lot)
	if Net.is_host():
		_place_props(lot)
	lot.set_meta("layout_hash", _layout_hash)


## A hash of where everything went, so tests can check every peer built the same yard.
func layout_hash() -> int:
	return _layout_hash


func _note(value: Variant) -> void:
	_layout_hash = hash([_layout_hash, value])


# ---------------------------------------------------------------- the house

func _house() -> void:
	var width := _rng.randf_range(8.0, 12.5)
	var depth := _rng.randf_range(6.5, 9.0)
	var stories := 2 if _rng.randf() < 0.4 else 1
	var center_x := _rng.randf_range(-YARD_HALF + width * 0.5 + 2.5, YARD_HALF - width * 0.5 - 2.5)
	var center_z := -YARD_HALF + depth * 0.5 + _rng.randf_range(2.5, 6.0)
	var wall: Color = _Neighborhood.WALLS[_rng.randi() % _Neighborhood.WALLS.size()]
	var roof: Color = _Neighborhood.ROOFS[_rng.randi() % _Neighborhood.ROOFS.size()]
	var trim: Color = _Neighborhood.TRIMS[_rng.randi() % _Neighborhood.TRIMS.size()]
	var garage := _rng.randf() < 0.5
	var at := Vector3(center_x, 0.0, center_z)
	var house: Node3D = _Neighborhood.house(self, at, width, depth, stories, wall, roof, trim, garage)
	var height := 0.5 + 3.0 * float(stories)
	_solid_box(at + Vector3(0.0, height * 0.5, 0.0), Vector3(width, height, depth), "HouseBody")
	_house_rect = Rect2(center_x - width * 0.5 - 0.6, center_z - depth * 0.5 - 0.6, width + 1.2, depth + 3.6)
	_taken.append(_house_rect)
	_note([width, depth, stories, center_x, center_z, garage])
	# A note or two stuck to the front door.
	for index: int in _rng.randi_range(0, 2):
		_Doodles.place_paper(self, _Doodles.note(_rng.randi() % 50), at + Vector3(-0.15 + float(index) * 0.25, 1.9 - float(index) * 0.2, depth * 0.5 + 0.08), Vector3.BACK, Vector2(0.19, 0.19), _rng.randf_range(-0.3, 0.3))
	# Windows to wash.
	for entry: Array in house.get_meta("windows", []):
		var spot_at: Vector3 = at + (entry[0] as Vector3)
		var normal: Vector3 = entry[1]
		var index: int = _tasks.call("define_spot", "wash_windows", to_global(spot_at + normal * 0.04), normal, 0.7)
		_looks.call("add_window", index, to_global(spot_at + normal * 0.06), normal)
	# Gutters front and back, a section every two meters.
	var top := float(house.get_meta("roof_edge_y", height))
	for side: float in [1.0, -1.0]:
		var gutter_z := center_z + side * (depth * 0.5 + 0.6)
		_LowPoly.paint(_LowPoly.box(self, Vector3(width + 1.0, 0.14, 0.18), Vector3(center_x, top - 0.08, gutter_z), Color(0.78, 0.78, 0.75)), "metal")
		var sections := maxi(2, int(width / 2.0))
		for section: int in sections:
			var x := center_x - width * 0.5 + (float(section) + 0.5) * width / float(sections)
			var spot_at := Vector3(x, top, gutter_z)
			var index: int = _tasks.call("define_spot", "clean_gutters", to_global(spot_at), Vector3.UP, 1.0)
			_looks.call("add_gutter", index, to_global(spot_at))


func _driveway() -> void:
	# From the street to the porch: Chefty pulls up it, and its stains get washed.
	_LowPoly.paint(_LowPoly.box(self, Vector3(4.2, 0.03, 17.0), Vector3(0.0, 0.015, 11.5), Color(0.62, 0.6, 0.57)), "concrete")
	var walk_to := _house_rect.end.y - 3.0
	if walk_to < 3.0:
		var walk_x := _house_rect.get_center().x
		_LowPoly.paint(_LowPoly.box(self, Vector3(1.3, 0.03, 3.0 - walk_to), Vector3(walk_x, 0.015, (walk_to + 3.0) * 0.5), Color(0.66, 0.64, 0.6)), "concrete")


## Flower beds along the front of the house, either side of the front walk,
## with weeds coming up among the flowers.
func _beds() -> void:
	var front := _house_rect.end.y - 3.0 + 0.1
	var walk_x := _house_rect.get_center().x
	for side: float in [-1.0, 1.0]:
		if _rng.randf() < 0.25:
			continue
		var length := _rng.randf_range(2.4, 3.6)
		var x := walk_x + side * (1.1 + length * 0.5)
		var rect := Rect2(x - length * 0.5, front, length, 1.3)
		if rect.position.x < _house_rect.position.x or rect.end.x > _house_rect.end.x:
			continue
		_no_lawn.append(rect)
		var center := Vector3(rect.get_center().x, 0.0, rect.get_center().y)
		_LowPoly.paint(_LowPoly.box(self, Vector3(length, 0.12, 1.3), center + Vector3(0.0, 0.06, 0.0), BED_DIRT), "dirt")
		_LowPoly.paint(_LowPoly.box(self, Vector3(length + 0.2, 0.18, 0.12), center + Vector3(0.0, 0.09, 0.7), Color(0.6, 0.58, 0.55)), "concrete")
		var kit := _MeshKit.new()
		for flower: int in int(length * 2.0):
			var spot := center + Vector3(-length * 0.5 + 0.3 + float(flower) * 0.5, 0.0, _rng.randf_range(-0.35, 0.35))
			kit.tube(PackedVector3Array([spot, spot + Vector3(0.0, 0.32, 0.0)]), PackedFloat32Array([0.015, 0.012]), Color(0.3, 0.55, 0.25), 4, {"jitter": 0.0, "sway_to": 0.6})
			kit.blob(spot + Vector3(0.0, 0.36, 0.0), Vector3(0.09, 0.06, 0.09), FLOWER_COLORS[_rng.randi() % FLOWER_COLORS.size()], {"detail": 1, "lumps": 0.3, "flat": true, "jitter": 0.05, "sway": 0.8, "seed": flower})
		add_child(_Stylized.instance(kit.commit(), {"wind": 0.04, "roughness": 0.9}))
		for weed: int in _rng.randi_range(3, 5):
			var spot := center + Vector3(_rng.randf_range(-length * 0.45, length * 0.45), 0.12, _rng.randf_range(-0.45, 0.45))
			var index: int = _tasks.call("define_spot", "pull_weeds", to_global(spot), Vector3.UP, 0.3)
			_looks.call("add_weed", index, to_global(spot))
		_note(["bed", rect])


# ---------------------------------------------------------------- the yard

func _trees_around() -> void:
	var count := _rng.randi_range(2, 5)
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
		var kind := "pine" if _rng.randf() < 0.15 else "broadleaf"
		_Trees.spawn(self, at, _rng.randf_range(7.0, 9.5), kind, CROWNS[_rng.randi() % CROWNS.size()], _rng.randi() % 4, true, _rng.randf() * TAU)
		_note(["tree", at])


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


## Picket fences along the back and sides, in panels the paint task can refresh.
func _fences() -> void:
	var runs: Array = [
		[Vector3(-19.4, 0.0, -19.4), Vector3(19.4, 0.0, -19.4), Vector3.BACK],
		[Vector3(-19.4, 0.0, -18.4), Vector3(-19.4, 0.0, 14.0), Vector3.RIGHT],
		[Vector3(19.4, 0.0, -18.4), Vector3(19.4, 0.0, 14.0), Vector3.LEFT],
	]
	for run: Array in runs:
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
			var pickets := int(a.distance_to(b) / 0.3)
			for picket: int in pickets:
				var at := a.lerp(b, (float(picket) + 0.5) / float(pickets))
				_LowPoly.paint(_LowPoly.box(holder, Vector3(0.12, 0.9, 0.06) if inward.z != 0.0 else Vector3(0.06, 0.9, 0.12), at + Vector3(0.0, 0.45, 0.0), PICKET), "planks")
			var middle := (a + b) * 0.5
			_LowPoly.box(holder, Vector3(a.distance_to(b), 0.08, 0.06) if inward.z != 0.0 else Vector3(0.06, 0.08, a.distance_to(b)), middle + Vector3(0.0, 0.55, 0.0) - inward * 0.04, PICKET)
			var index: int = _tasks.call("define_spot", "paint_fence", to_global(middle + Vector3(0.0, 0.5, 0.0) + inward * 0.1), inward, 1.2)
			_looks.call("add_fence_panel", index, holder)


func _hide_spots(lot: Node3D) -> void:
	var spots: Array = [
		["Shed", Vector3(2.4, 2.4, 2.0), Color(0.5, 0.4, 0.3), "Shed", "planks"],
		["BigBin", Vector3(1.4, 1.3, 1.0), Color(0.25, 0.3, 0.32), "Big bin", "metal"],
		["Hedge", Vector3(3.0, 1.6, 1.2), Color(0.2, 0.42, 0.22), "Hedge", "foliage"],
	]
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


## Cans, wrappers, and bottles dropped on the lawn.
func _litter() -> void:
	for piece: int in _rng.randi_range(6, 11):
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
	var house := _house_rect
	var no_lawn := _no_lawn.duplicate()
	var lawn: int = _tasks.call("define_grid", "mow_lawn", to_global(Vector3(-YARD_HALF, 0.0, -YARD_HALF)), Vector2(YARD_HALF * 2.0, YARD_HALF * 2.0), 1.0, func(center: Vector3) -> bool:
		var local := lot_global.to_local(center)
		var at := Vector2(local.x, local.z)
		if Rect2(house.position, Vector2(house.size.x, house.size.y - 3.0)).grow(-0.3).has_point(at) or Rect2(-2.2, 3.0, 4.4, 17.5).has_point(at):
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
	var house := _house_rect
	var spread := _rng.randf_range(4.5, 6.5)
	var base := _rng.randf_range(0.45, 0.75)
	field.call("shape_initial", func(world: Vector3) -> float:
		var local := lot.to_local(world)
		if Rect2(house.position, Vector2(house.size.x, house.size.y - 3.0)).grow(-0.4).has_point(Vector2(local.x, local.z)):
			return 0.0
		var amount := base
		for tree: Vector3 in trees:
			var distance := Vector2(world.x - tree.x, world.z - tree.z).length()
			amount += 1.6 * exp(-distance * distance / (2.0 * spread * spread))
		# The driveway is swept: leaves on it would only make washing it a chore.
		if absf(local.x) < 2.3 and local.z > 3.0:
			return 0.0
		return clampf(amount, 0.0, 2.6)
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
