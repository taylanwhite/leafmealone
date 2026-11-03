extends RefCounted

## Authority: local, cosmetic, the same on every peer (fixed seeds and TownMap
## only; solids() is data). Gutterford's outskirts (driving chunk E2, docs/GAME.md
## "Gutterford from the road"): what you drive past between Homie Depot, the
## square and the neighborhoods, so the open grass reads as farmland at the edge
## of a small town instead of a lawn with a road on it. Schedule I's town works
## because nothing between two places is empty; here that's:
##   - Fields both sides of County Road 9 and along Main Street: plowed furrows,
##     corn stubble, hay with round bales, a pumpkin patch (pumpkins in autumn
##     only), each one mesh.
##   - The Furrow family farm on the County Road: a red barn, a silo, a white
##     farmhouse, a gravel drive and a mailbox at the road.
##   - Split-rail fences along the County Road, a power line on wooden poles
##     beside it and up Main Street's west side, with wires.
##   - Trees in rows: a cypress windbreak, broadleaf lines along field edges,
##     and a line along the back fences between each pair of neighborhoods.
##   - Landmarks you can steer by: the GUTTERFORD water tower by the square, a
##     two-faced billboard on the County Road (TurfMasters™ one way, Homie Depot
##     the other), and the Municipal Leaf Depository off Main Street, a fenced
##     lot with a mountain of leaves in it ("Capacity: Exceeded Since 1987").
##
## Draw calls: one mesh per field and per landmark, fences, poles and bales in
## one PropBatch with Constants.OUTSKIRTS_PROP_CHUNK chunks, one wire mesh per
## power line, and the row trees (art's trees: each one draw call, near or far).
## The solids (poles, the barn, silo and farmhouse, the tower's legs, the
## billboard's posts, the leaf mountain, the row trees' trunks) are
## levels/town/town_colliders.gd's, from solids(). Fences, bales and fields
## don't collide, like the yards' own fences.

const _LowPoly = preload("res://props/low_poly.gd")
const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const _P = preload("res://props/prop_parts.gd")
const _PropCatalog = preload("res://props/prop_catalog.gd")
const _PropBatch = preload("res://props/prop_batch.gd")
const _Street = preload("res://props/street_props.gd")
const _Trees = preload("res://props/trees.gd")
const _HouseBuilder = preload("res://levels/town/house_builder.gd")
const _BuildQueue = preload("res://levels/build_queue.gd")
const _Strings = preload("res://ui/strings.gd")
const _Hoods = preload("res://net/town/neighborhoods.gd")

const SEED: int = 4417
const DIRT := Color(0.4, 0.29, 0.2)
const FURROW := Color(0.33, 0.23, 0.16)
const STUBBLE := Color(0.74, 0.64, 0.38)
const HAY := Color(0.8, 0.71, 0.42)
const BALE := Color(0.86, 0.74, 0.4)
const VINE := Color(0.3, 0.42, 0.2)
const PUMPKIN := Color(0.95, 0.5, 0.12)
const GRAVEL := Color(0.62, 0.58, 0.52)
const TOWER := Color(0.78, 0.8, 0.82)
const TOWER_TEXT := Color(0.18, 0.3, 0.5)
const LEAF_PILE: Array[Color] = [Color(0.88, 0.48, 0.16), Color(0.74, 0.3, 0.14), Color(0.9, 0.7, 0.24), Color(0.55, 0.33, 0.17)]
const BAG := Color(0.12, 0.13, 0.14)
## Fences come in whole runs this long (PropBatch groups by size).
const RUN: float = 6.0
## The County Road's half width, and how far out from its centerline the north
## fence, the south poles and the south fence stand.
const ROAD_HALF: float = 4.4
const FENCE_NORTH: float = 7.6
const POLES_SOUTH: float = 7.0
const FENCE_SOUTH: float = 8.8
## Main Street's west side: the power line's x.
const MAIN_POLES_X: float = 331.2

static var _rows: Array = []


# ---------------------------------------------------------------- the layout (data)

## County Road 9's centerline z at x (from Depot Road's junction to the square).
static func county_z(x: float) -> float:
	var a := TownMap.DEPOT_JUNCTION
	var b := TownMap.COUNTY_BEND
	if x >= b.x:
		return b.z
	return lerpf(a.z, b.z, clampf((x - a.x) / (b.x - a.x), 0.0, 1.0))


## The fields: [rect (x, z), kind, rows run along x].
static func fields() -> Array:
	return [
		[Rect2(50.0, -96.0, 95.0, 90.0), "plowed", true],
		[Rect2(235.0, -105.0, 65.0, 99.0), "stubble", false],
		[Rect2(150.0, -230.0, 72.0, 92.0), "hay", true],
		[Rect2(240.0, -262.0, 75.0, 122.0), "plowed", false],
		[Rect2(55.0, 26.0, 82.0, 77.0), "hay", true],
		[Rect2(152.0, 26.0, 48.0, 40.0), "patch", true],
		[Rect2(215.0, 110.0, 90.0, 90.0), "plowed", true],
		[Rect2(235.0, 240.0, 80.0, 110.0), "stubble", false],
	]


## The Furrow farm: {barn, silo, house: [at, yaw]}, its drive (Rect2) and mailbox.
static func farm() -> Dictionary:
	return {
		"barn": [Vector3(178.0, 0.0, -48.0), PI],
		"silo": [Vector3(191.0, 0.0, -60.0), 0.0],
		"house": [Vector3(213.0, 0.0, -38.0), 0.0],
		"drive": Rect2(215.0, -31.0, 4.0, 31.0 + county_z(217.0) - ROAD_HALF),
		"mailbox": [Vector3(221.0, 0.0, county_z(221.0) - ROAD_HALF - 1.4), 0.0],
		"truck": [Vector3(196.0, 0.0, -36.0), 0.4],
	}


## The farmhouse's request (levels/town/house_builder.gd).
static func farmhouse_req() -> Dictionary:
	return {
		"archetype": "farmhouse", "width": 11.0, "depth": 8.0, "stories": 2, "seed": SEED,
		"wall": Color(0.93, 0.91, 0.86), "wall_surface": "siding", "roof": Color(0.36, 0.2, 0.17),
		"trim": Color(0.97, 0.96, 0.92), "door": Color(0.2, 0.32, 0.45), "detail": "full",
	}


static func water_tower() -> Vector3:
	return Vector3(262.0, 0.0, 62.0)


## The billboard by the County Road: [at, yaw]; its west face reads from the store.
static func billboard() -> Array:
	return [Vector3(145.0, 0.0, county_z(145.0) + 15.5), -PI * 0.5]


## The Municipal Leaf Depository's fenced lot (x, z), its gate on the west side.
static func depository() -> Rect2:
	return Rect2(400.0, 42.0, 70.0, 36.0)


## The power lines: each a list of pole bases, in order.
static func pole_lines() -> Array:
	var county := PackedVector3Array()
	var x := 52.0
	while x <= 300.0:
		county.append(Vector3(x, 0.0, county_z(x) + POLES_SOUTH))
		x += Constants.OUTSKIRTS_POLE_SPACING
	var north := PackedVector3Array()
	var z := -32.0
	while z >= -410.0:
		north.append(Vector3(MAIN_POLES_X, 0.0, z))
		z -= Constants.OUTSKIRTS_POLE_SPACING
	var south := PackedVector3Array()
	z = 34.0
	while z <= 440.0:
		south.append(Vector3(MAIN_POLES_X, 0.0, z))
		z += Constants.OUTSKIRTS_POLE_SPACING
	return [county, north, south]


## Trees in rows: [[at, height, kind, crown]], seeded. Worked out once.
static func row_trees() -> Array:
	if not _rows.is_empty():
		return _rows
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([SEED, "rows"])
	var out: Array = []
	# The windbreak north of the first field and the farm.
	_row(out, rng, Vector3(55.0, 0.0, -114.0), Vector3(228.0, 0.0, -114.0), 9.0, "cypress", ["green"], Vector2(9.0, 11.0))
	_row(out, rng, Vector3(229.0, 0.0, -136.0), Vector3(229.0, 0.0, -262.0), 12.0, "broadleaf", ["orange", "yellow"], Vector2(8.0, 10.5))
	_row(out, rng, Vector3(60.0, 0.0, 118.0), Vector3(205.0, 0.0, 118.0), 12.0, "broadleaf", ["red", "rust", "orange"], Vector2(7.5, 10.0))
	_row(out, rng, Vector3(226.0, 0.0, 238.0), Vector3(226.0, 0.0, 352.0), 11.0, "pine", ["green"], Vector2(9.0, 12.0))
	# Along the back fences between each pair of neighborhoods: [hood a, hood b].
	for pair: Array in [[0, 2], [1, 3], [2, 4], [3, 5]]:
		var a := int(pair[0])
		var b := int(pair[1])
		# Halfway between the back edges of the two streets' lots: yards always
		# stand on the street's -z side, the houses across on its +z side.
		var reach := TownMap.YARD_STREET_Z + TownMap.YARD_HALF
		var back_a := TownMap.STREET_Z[a] - reach if TownMap.STREET_Z[a] < 0.0 else TownMap.STREET_Z[a] + reach
		var back_b := TownMap.STREET_Z[b] + reach if TownMap.STREET_Z[b] < 0.0 else TownMap.STREET_Z[b] - reach
		var za := (back_a + back_b) * 0.5
		var end_x := minf(TownMap.street_end_x(a), TownMap.street_end_x(b)) - 6.0
		var crowns: Array = ["orange", "red", "yellow", "rust", "turning"]
		_row(out, rng, Vector3(TownMap.FIRST_SLOT_X + 12.0, 0.0, za), Vector3(end_x, 0.0, za), Constants.OUTSKIRTS_BACK_ROW_SPACING, "broadleaf", crowns, Vector2(8.0, 11.0))
	# Not on top of a country tree.
	var country := TownMap.country_trees()
	for tree: Array in out:
		var clear := true
		for other: Array in country:
			if (other[0] as Vector3).distance_to(tree[0]) < 6.0:
				clear = false
				break
		if clear:
			_rows.append(tree)
	return _rows


static func _row(out: Array, rng: RandomNumberGenerator, from: Vector3, to: Vector3, spacing: float, kind: String, crowns: Array, heights: Vector2) -> void:
	var length := from.distance_to(to)
	var count := maxi(1, int(length / spacing))
	var along := (to - from) / float(count)
	var across := along.normalized().cross(Vector3.UP)
	for index: int in count + 1:
		var at := from + along * float(index) + along * rng.randf_range(-0.12, 0.12) + across * rng.randf_range(-0.8, 0.8)
		out.append([at, rng.randf_range(heights.x, heights.y), kind, str(crowns[rng.randi() % crowns.size()])])


## Everything here that collides: [["box", center, size, yaw] or ["cylinder",
## center, Vector2(radius, height), 0.0]], world space. part picks a piece (the
## colliders build one part a step): "poles", "farm" (a house plan, cold the
## first time), "landmarks", "trees"; "" is all of them.
static func solids(part: String = "") -> Array:
	var out: Array = []
	if part == "" or part == "poles":
		_pole_solids(out)
	if part == "" or part == "farm":
		_farm_solids(out)
	if part == "" or part == "landmarks":
		_landmark_solids(out)
	if part == "" or part == "trees":
		for tree: Array in row_trees():
			out.append(["cylinder", (tree[0] as Vector3) + Vector3(0.0, 1.5, 0.0), Vector2(0.35, 3.0), 0.0])
	return out


static func _pole_solids(out: Array) -> void:
	for line: PackedVector3Array in pole_lines():
		for base: Vector3 in line:
			out.append(["cylinder", base + Vector3(0.0, 4.6, 0.0), Vector2(0.16, 9.2), 0.0])


static func _farm_solids(out: Array) -> void:
	var place := farm()
	var barn: Array = place["barn"]
	out.append(["box", (barn[0] as Vector3) + Vector3(0.0, 4.1, 0.0), Vector3(9.0, 8.2, 12.0), float(barn[1])])
	var silo: Array = place["silo"]
	out.append(["cylinder", (silo[0] as Vector3) + Vector3(0.0, 6.5, 0.0), Vector2(2.2, 13.0), 0.0])
	var house: Array = place["house"]
	var spec := _HouseBuilder.spec_for(farmhouse_req())
	var turn := Basis(Vector3.UP, float(house[1]))
	for solid: Array in spec.get("solids", []):
		out.append(["box", (house[0] as Vector3) + turn * (solid[0] as Vector3), solid[1], float(house[1])])


static func _landmark_solids(out: Array) -> void:
	var tower := water_tower()
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		out.append(["cylinder", tower + Vector3(corner.x * 3.4, 2.0, corner.y * 3.4), Vector2(0.35, 4.0), 0.0])
	var board: Array = billboard()
	var board_turn := Basis(Vector3.UP, float(board[1]))
	for side: float in [-1.0, 1.0]:
		out.append(["cylinder", (board[0] as Vector3) + board_turn * Vector3(side * 3.6, 2.5, 0.0), Vector2(0.2, 5.0), 0.0])
	var lot := depository()
	out.append(["box", Vector3(lot.get_center().x + 6.0, 1.6, lot.get_center().y), Vector3(26.0, 3.2, 18.0), 0.0])


# ---------------------------------------------------------------- building (visuals)

## Queues the outskirts' pieces on root's BuildQueue (each a step).
static func dress(root: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "Outskirts"
	root.add_child(holder)
	for index: int in fields().size():
		var entry: Array = fields()[index]
		_BuildQueue.later(holder, func() -> void: _field(holder, entry[0], str(entry[1]), bool(entry[2]), index), "outskirts field")
	_BuildQueue.later(holder, func() -> void: _farm(holder), "outskirts farm")
	_BuildQueue.later(holder, func() -> void: _farmhouse(holder), "outskirts farmhouse")
	_BuildQueue.later(holder, func() -> void: _fences_and_poles(holder), "outskirts fences")
	_BuildQueue.later(holder, func() -> void: _water_tower(holder), "outskirts water tower")
	_BuildQueue.later(holder, func() -> void: _billboard(holder), "outskirts billboard")
	_BuildQueue.later(holder, func() -> void: _depository(holder), "outskirts depository")
	var trees_holder := Node3D.new()
	trees_holder.name = "RowTrees"
	holder.add_child(trees_holder)
	# Working out the rows is a step too; each few trees are one more.
	_BuildQueue.later(trees_holder, func() -> void:
		var trees := row_trees()
		for first: int in range(0, trees.size(), 3):
			_BuildQueue.later(trees_holder, func() -> void:
				for index: int in range(first, mini(first + 3, trees.size())):
					var tree: Array = trees[index]
					_Trees.spawn(trees_holder, tree[0], float(tree[1]), str(tree[2]), str(tree[3]), index % 4, false, float(index) * 2.3), "outskirts trees"), "outskirts rows")


static func _mesh(parent: Node3D, kit: RefCounted, node_name: String, shadow: bool = true) -> MeshInstance3D:
	var mesh: ArrayMesh = kit.call("commit")
	if mesh == null:
		return null
	var view := _Stylized.instance(mesh, {"roughness": 0.95, "snow": 1.0})
	view.name = node_name
	if not shadow:
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(view)
	return view


## One field: its ground a hair over the grass, its rows, and what grows in them.
static func _field(parent: Node3D, rect: Rect2, kind: String, along_x: bool, index: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([SEED, "field", index])
	var flat := _MeshKit.new()
	var middle := rect.get_center()
	var base: Color = {"plowed": DIRT, "stubble": STUBBLE.darkened(0.15), "hay": HAY.darkened(0.08), "patch": DIRT}[kind]
	flat.box(Vector3(middle.x, -0.005, middle.y), Vector3(rect.size.x, 0.05, rect.size.y), base)
	var long := rect.size.x if along_x else rect.size.y
	var wide := rect.size.y if along_x else rect.size.x
	var spacing := Constants.OUTSKIRTS_FURROW_SPACING if kind != "hay" else Constants.OUTSKIRTS_FURROW_SPACING * 2.5
	var rows := int(wide / spacing)
	var tone: Color = {"plowed": FURROW, "stubble": STUBBLE, "hay": HAY, "patch": FURROW}[kind]
	for row: int in rows:
		var offset := -wide * 0.5 + spacing * (float(row) + 0.5)
		var at := Vector3(middle.x, 0.04, middle.y + offset) if along_x else Vector3(middle.x + offset, 0.04, middle.y)
		var size := Vector3(long - 1.0, 0.09, spacing * 0.42) if along_x else Vector3(spacing * 0.42, 0.09, long - 1.0)
		flat.box(at, size, tone.lightened(rng.randf_range(-0.04, 0.06)))
	_mesh(parent, flat, "Field%d" % index, false)
	var standing := _MeshKit.new()
	var country := TownMap.country_trees()
	match kind:
		"stubble":
			# Cut stalks along every other row, a few hand-widths high.
			for row: int in range(0, rows, 2):
				var offset := -wide * 0.5 + spacing * (float(row) + 0.5)
				var step := 0.0
				while step < long - 2.0:
					step += rng.randf_range(1.6, 3.2)
					var along := -long * 0.5 + step
					var at := Vector3(middle.x + along, 0.0, middle.y + offset) if along_x else Vector3(middle.x + offset, 0.0, middle.y + along)
					var high := rng.randf_range(0.22, 0.45)
					standing.box(at + Vector3(0.0, high * 0.5, 0.0), Vector3(0.07, high, 0.07), STUBBLE.lightened(rng.randf_range(-0.05, 0.1)), Basis(Vector3.FORWARD, rng.randf_range(-0.3, 0.3)))
		"hay":
			# Round bales lying where the baler dropped them.
			for _bale: int in Constants.OUTSKIRTS_BALES_PER_FIELD:
				var at := Vector3(rng.randf_range(rect.position.x + 3.0, rect.end.x - 3.0), 0.0, rng.randf_range(rect.position.y + 3.0, rect.end.y - 3.0))
				if country.any(func(tree: Array) -> bool: return (tree[0] as Vector3).distance_to(at) < 4.0):
					continue
				var turn := rng.randf() * PI
				var axis := Vector3(cos(turn), 0.0, -sin(turn)) * 0.65
				standing.tube(PackedVector3Array([at + Vector3(0.0, 0.75, 0.0) - axis, at + Vector3(0.0, 0.75, 0.0) + axis]), PackedFloat32Array([0.75, 0.75]), BALE.lightened(rng.randf_range(-0.06, 0.05)), 12, {"jitter": 0.02, "cap": true})
		"patch":
			for _vine: int in 70:
				var at := Vector3(rng.randf_range(rect.position.x + 1.0, rect.end.x - 1.0), 0.05, rng.randf_range(rect.position.y + 1.0, rect.end.y - 1.0))
				standing.blob(at, Vector3(rng.randf_range(0.6, 1.1), 0.18, rng.randf_range(0.6, 1.1)), VINE.lightened(rng.randf_range(-0.05, 0.08)), {"detail": 1, "lumps": 0.3, "seed": rng.randi()})
			# Pumpkins only while it's pumpkin season.
			if Seasons.current() == 0:
				for _pumpkin: int in 46:
					var at := Vector3(rng.randf_range(rect.position.x + 1.0, rect.end.x - 1.0), 0.0, rng.randf_range(rect.position.y + 1.0, rect.end.y - 1.0))
					var size := rng.randf_range(0.28, 0.5)
					standing.blob(at + Vector3(0.0, size * 0.75, 0.0), Vector3(size * 2.0, size * 1.5, size * 2.0), PUMPKIN.lightened(rng.randf_range(-0.08, 0.06)), {"detail": 1, "lumps": 0.12, "seed": rng.randi()})
			# The scarecrow keeps an eye on it.
			var crow := _PropCatalog.node("scarecrow")
			crow.position = Vector3(middle.x + 4.0, 0.0, middle.y - 3.0)
			crow.rotation.y = PI * 0.15
			parent.add_child(crow)
	_mesh(parent, standing, "Field%dCrop" % index)


static func _farm(parent: Node3D) -> void:
	var place := farm()
	var holder := Node3D.new()
	holder.name = "FurrowFarm"
	parent.add_child(holder)
	for key: String in ["barn", "silo"]:
		var spot: Array = place[key]
		var view := _PropCatalog.node(key)
		view.position = spot[0]
		view.rotation.y = float(spot[1])
		holder.add_child(view)
	var drive: Rect2 = place["drive"]
	var kit := _MeshKit.new()
	kit.box(Vector3(drive.get_center().x, -0.005, drive.get_center().y), Vector3(drive.size.x, 0.05, drive.size.y), GRAVEL)
	# The yard between barn and house: packed dirt.
	kit.box(Vector3(195.0, -0.01, -40.0), Vector3(30.0, 0.04, 22.0), DIRT.lightened(0.12))
	_mesh(holder, kit, "Drive", false)
	var mailbox: Array = place["mailbox"]
	var box := _PropCatalog.node("mailbox_post")
	box.position = mailbox[0]
	box.rotation.y = float(mailbox[1])
	holder.add_child(box)
	var truck: Array = place["truck"]
	var pickup := _PropCatalog.node("car_pickup", Color(0.36, 0.42, 0.33))
	pickup.position = truck[0]
	pickup.rotation.y = float(truck[1])
	holder.add_child(pickup)
	# A hand-painted sign at the drive.
	var sign_root := Node3D.new()
	holder.add_child(sign_root)
	sign_root.position = Vector3(212.0, 0.0, county_z(212.0) - ROAD_HALF - 2.2)
	var wood := _MeshKit.new()
	for side: float in [-1.0, 1.0]:
		_P.post(wood, Vector3(side * 1.1, 0.0, 0.0), 1.9, 0.07, _P.WOOD, 6)
	_P.slab(wood, Vector3(0.0, 1.45, 0.0), Vector3(2.8, 0.9, 0.08), Color(0.94, 0.9, 0.8))
	_mesh(sign_root, wood, "Board")
	_text(sign_root, _Strings.TOWN_SIGNS["farm_sign"], Vector3(0.0, 1.45, 0.05), 22, Color(0.55, 0.16, 0.12))


static func _farmhouse(parent: Node3D) -> void:
	var house: Array = farm()["house"]
	var root := Node3D.new()
	root.name = "Farmhouse"
	parent.add_child(root)
	root.rotation.y = float(house[1])
	root.position = house[0]
	_HouseBuilder.build(root, Vector3.ZERO, farmhouse_req())


static func _fences_and_poles(parent: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "FencesAndPoles"
	parent.add_child(holder)
	var batch := _PropBatch.new(holder, Constants.OUTSKIRTS_PROP_CHUNK)
	var gap: Rect2 = farm()["drive"]
	for side: float in [-1.0, 1.0]:
		var out := -FENCE_NORTH if side < 0.0 else FENCE_SOUTH
		var x := 48.0
		while x + RUN <= 298.0:
			var middle := x + RUN * 0.5
			x += RUN
			if side < 0.0 and middle > gap.position.x - 4.0 and middle < gap.end.x + 4.0:
				continue
			var a := Vector3(middle - RUN * 0.5, 0.0, county_z(middle - RUN * 0.5) + out)
			var b := Vector3(middle + RUN * 0.5, 0.0, county_z(middle + RUN * 0.5) + out)
			var yaw := atan2(-(b.z - a.z), b.x - a.x)
			batch.call("add", "split_rail_run", Transform3D(Basis(Vector3.UP, yaw), (a + b) * 0.5), Color.WHITE, Vector3(RUN, 0.0, 0.0))
	var wires := Node3D.new()
	wires.name = "Wires"
	holder.add_child(wires)
	for line: PackedVector3Array in pole_lines():
		var spans: Array = []
		for index: int in line.size():
			var here := line[index]
			var toward := (line[mini(index + 1, line.size() - 1)] - line[maxi(index - 1, 0)])
			toward.y = 0.0
			var across := toward.normalized().cross(Vector3.UP)
			batch.call("add", "power_pole", Transform3D(Basis(Vector3.UP, atan2(-across.z, across.x)), here))
			if index > 0:
				spans.append([line[index - 1], here])
		var mesh := _Street.wire_mesh(spans, _Street.WIRE_HEIGHT, 0.9)
		if mesh != null:
			var view := _Stylized.instance(mesh, _PropCatalog.options("wire_span"))
			view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			wires.add_child(view)
	batch.call("commit")


## GUTTERFORD on a water tower by the square: four legs, braces, a fat tank, a
## catwalk and a pointed cap, the name painted where the County Road sees it.
static func _water_tower(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "WaterTower"
	parent.add_child(root)
	root.position = water_tower()
	var kit := _MeshKit.new()
	var legs: Array[Vector3] = []
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var foot := Vector3(corner.x * 3.4, 0.0, corner.y * 3.4)
		var head := Vector3(corner.x * 2.4, 17.2, corner.y * 2.4)
		_P.bar(kit, foot, head, 0.22, TOWER.darkened(0.12), 8)
		legs.append(foot)
	for level: float in [5.0, 11.0]:
		for index: int in 4:
			var a := legs[index].lerp(Vector3(legs[index].x * 0.7, 17.2, legs[index].z * 0.7), level / 17.2)
			var b := legs[(index + 1) % 4].lerp(Vector3(legs[(index + 1) % 4].x * 0.7, 17.2, legs[(index + 1) % 4].z * 0.7), level / 17.2)
			_P.bar(kit, a, b, 0.07, TOWER.darkened(0.2), 5)
	_P.post(kit, Vector3(0.0, 0.0, 0.0), 17.5, 0.3, TOWER.darkened(0.25), 8)
	_P.post(kit, Vector3(0.0, 17.0, 0.0), 6.0, 5.0, TOWER, 20)
	_P.ring(kit, Vector3(0.0, 17.1, 0.0), 5.6, 0.08, TOWER.darkened(0.3), 20, 4)
	_P.ring(kit, Vector3(0.0, 18.1, 0.0), 5.6, 0.05, TOWER.darkened(0.3), 20, 4)
	_P.disc(kit, Vector3(0.0, 17.05, 0.0), 5.6, 0.1, TOWER.darkened(0.35), 20)
	_P.cone(kit, Vector3(0.0, 23.0, 0.0), 5.2, 2.6, TOWER.darkened(0.06), 20)
	_P.ball(kit, Vector3(0.0, 25.7, 0.0), Vector3(0.35, 0.35, 0.35), TOWER.darkened(0.3), 1)
	_mesh(root, kit, "Tower")
	# Painted on the tank, read from the store (west) and from the County Road (north).
	for yaw: float in [-PI * 0.5, PI]:
		var face := Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, 5.05)
		var label := _text(root, _Strings.TOWN_SIGNS["water_tower"], face + Vector3(0.0, 20.2, 0.0), 140, TOWER_TEXT, yaw)
		label.outline_size = 0
		label.pixel_size = 0.008


## The billboard on its two posts: TurfMasters™ to the store side (read driving
## into town), Homie Depot on the back (read driving out to it).
static func _billboard(parent: Node3D) -> void:
	var place: Array = billboard()
	var root := Node3D.new()
	root.name = "Billboard"
	parent.add_child(root)
	root.position = place[0]
	root.rotation.y = float(place[1])
	var kit := _MeshKit.new()
	for side: float in [-1.0, 1.0]:
		_P.post(kit, Vector3(side * 3.6, 0.0, 0.0), 5.4, 0.18, _P.WOOD.darkened(0.2), 6)
		_P.bar(kit, Vector3(side * 3.6, 1.6, 0.0), Vector3(side * 3.6 - side * 1.4, 4.4, 0.0), 0.06, _P.WOOD.darkened(0.25), 4)
	_P.slab(kit, Vector3(0.0, 6.4, 0.0), Vector3(10.0, 3.6, 0.25), Color(0.95, 0.95, 0.92))
	_P.slab(kit, Vector3(0.0, 6.4, 0.14), Vector3(9.6, 3.2, 0.04), Color(0.1, 0.52, 0.28))
	_P.slab(kit, Vector3(0.0, 6.4, -0.14), Vector3(9.6, 3.2, 0.04), Color(0.95, 0.5, 0.12))
	_P.slab(kit, Vector3(0.0, 4.55, 0.4), Vector3(10.0, 0.08, 0.7), _P.DARK_STEEL)
	_mesh(root, kit, "Board")
	_text(root, _Strings.TOWN_SIGNS["billboard_turf_title"], Vector3(0.0, 7.1, 0.18), 200, Color(0.98, 0.98, 0.94))
	_text(root, _Strings.TOWN_SIGNS["billboard_turf_line"], Vector3(0.0, 5.6, 0.18), 70, Color(0.98, 0.98, 0.94))
	_text(root, _Strings.TOWN_SIGNS["billboard_depot_title"], Vector3(0.0, 7.1, -0.18), 200, Color(0.14, 0.12, 0.1), PI)
	_text(root, _Strings.TOWN_SIGNS["billboard_depot_line"], Vector3(0.0, 5.6, -0.18), 70, Color(0.14, 0.12, 0.1), PI)


## The Gutterford Municipal Leaf Depository: where the town's leaves go, and
## stay. A chain-link lot off Main Street with a mountain of leaves in it, bags
## stacked against the fence, a gravel drive in from the street, and its sign.
static func _depository(parent: Node3D) -> void:
	var lot := depository()
	var root := Node3D.new()
	root.name = "LeafDepository"
	parent.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([SEED, "depository"])
	var ground := _MeshKit.new()
	ground.box(Vector3(lot.get_center().x, -0.005, lot.get_center().y), Vector3(lot.size.x, 0.05, lot.size.y), GRAVEL.darkened(0.08))
	var main_east := TownMap.MAIN_X + TownMap.MAIN_WIDTH * 0.5 + TownMap.SIDEWALK
	ground.box(Vector3((main_east + lot.position.x) * 0.5, -0.005, lot.get_center().y), Vector3(lot.position.x - main_east, 0.05, 6.0), GRAVEL)
	_mesh(root, ground, "Ground", false)
	# The mountain: overlapping heaps, the big one in the middle, drifts at its feet.
	var pile := _MeshKit.new()
	var middle := Vector3(lot.get_center().x + 6.0, 0.0, lot.get_center().y)
	for heap: int in 9:
		var at := middle + Vector3(rng.randf_range(-11.0, 11.0), 0.0, rng.randf_range(-6.0, 6.0))
		var reach := rng.randf_range(4.5, 8.0) if heap > 0 else 11.0
		var high := rng.randf_range(2.5, 4.5) if heap > 0 else 7.0
		if heap == 0:
			at = middle
		pile.blob(at, Vector3(reach * 2.0, high * 2.0, reach * 1.6), LEAF_PILE[rng.randi() % LEAF_PILE.size()], {"detail": 2, "lumps": 0.35, "seed": rng.randi(), "flat": true})
	for _leaf: int in 260:
		var angle := rng.randf() * TAU
		var out := rng.randf_range(10.0, 16.0)
		var at := middle + Vector3(cos(angle) * out * 1.3, 0.05, sin(angle) * out * 0.75)
		if not lot.grow(-1.0).has_point(Vector2(at.x, at.z)):
			continue
		_P.leaf(pile, at, Vector3(rng.randf_range(-0.3, 0.3), 1.0, rng.randf_range(-0.3, 0.3)).normalized(), rng.randf_range(0.18, 0.3), LEAF_PILE[rng.randi() % LEAF_PILE.size()], 0.0, rng.randf() * TAU)
	# Bags, stacked by the gate where people gave up.
	for bag: int in 26:
		var row := bag % 7
		var layer := bag / 7
		var at := Vector3(lot.position.x + 4.0 + float(row) * 0.85 + rng.randf_range(-0.1, 0.1), 0.42 + float(layer) * 0.6, lot.end.y - 2.4 + rng.randf_range(-0.2, 0.2))
		pile.blob(at, Vector3(0.8, 0.85, 0.7), BAG.lightened(rng.randf_range(0.0, 0.06)), {"detail": 1, "lumps": 0.2, "seed": rng.randi()})
	_mesh(root, pile, "Mountain")
	var batch := _PropBatch.new(root, Constants.OUTSKIRTS_PROP_CHUNK)
	# Chain-link all round, the gate on the Main Street side left open.
	var gate_z := lot.get_center().y
	for edge: Array in [[lot.position, Vector2(lot.end.x, lot.position.y)], [Vector2(lot.end.x, lot.position.y), lot.end], [lot.end, Vector2(lot.position.x, lot.end.y)], [Vector2(lot.position.x, lot.end.y), lot.position]]:
		var a: Vector2 = edge[0]
		var b: Vector2 = edge[1]
		var length := a.distance_to(b)
		var pieces := int(round(length / RUN))
		for index: int in pieces:
			var t := (float(index) + 0.5) / float(pieces)
			var spot := a.lerp(b, t)
			if absf(spot.x - lot.position.x) < 0.1 and absf(spot.y - gate_z) < 4.0:
				continue
			var yaw := atan2(-(b.y - a.y), b.x - a.x)
			batch.call("add", "chainlink_run", Transform3D(Basis(Vector3.UP, yaw), Vector3(spot.x, 0.0, spot.y)), Color.WHITE, Vector3(length / float(pieces), 0.0, 0.0))
	batch.call("commit")
	# The sign on the fence by the gate, facing Main Street.
	var sign_root := Node3D.new()
	root.add_child(sign_root)
	sign_root.position = Vector3(lot.position.x - 0.3, 0.0, gate_z + 7.0)
	sign_root.rotation.y = -PI * 0.5
	var board := _MeshKit.new()
	for side: float in [-1.0, 1.0]:
		_P.post(board, Vector3(side * 2.2, 0.0, 0.0), 3.2, 0.06, _P.DARK_STEEL, 6)
	_P.slab(board, Vector3(0.0, 2.3, 0.0), Vector3(4.8, 1.6, 0.06), Color(0.95, 0.95, 0.93))
	_mesh(sign_root, board, "Board")
	_text(sign_root, _Strings.TOWN_SIGNS["depository_sign"], Vector3(0.0, 2.4, 0.04), 30, Color(0.16, 0.3, 0.22))


static func _text(parent: Node3D, text: String, at: Vector3, font_size: int, color: Color, yaw: float = 0.0) -> Label3D:
	var label := _LowPoly.text_sign(parent, text, at, font_size, color, yaw)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label
