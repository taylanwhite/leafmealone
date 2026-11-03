extends SceneTree

## Checks the leaf look (raking:2; leaves/, docs/ART.md "Leaves"). Run headless:
##   godot --headless --path . --script res://tools/leaf_look_check.gd
## - each leaf species within its triangle budget (Constants.LEAF_MESH_MAX_TRIS),
##   its normals bent (not all straight up) and its masks present
## - no stripes: over a uniform carpet, a slot's offset and yaw don't correlate
##   with the same slot one to eight cells along either axis
## - no leaf colour near the old olive that read as dead grass; all four
##   seasons build
## - the mound: monotonic, about 0.015 m at density 60 and 0.77 m at 255; the
##   hero leaf counts; a hero leaf drawn exactly on the skin (slot_world vs
##   surface_y); the view's ease (morph) lands on the field and claims hold
## - budgets on yards shaped like levels/lots/lot_generator.gd (seeds 777 and
##   1000, every yard size): hero leaves near a camera, skin triangles, visible
##   triangles and draw calls; and how long rebuilding the densest chunk takes
## Prints [LeafCheck] lines; exits 1 on any failure.

const _Renderer = preload("res://leaves/leaf_renderer.gd")
const OLD_OLIVE := Color(0.55, 0.58, 0.22)
const GRID: int = 80
const CELL: float = 0.5
const ORIGIN := Vector3(-20.0, 0.05, -20.0)

var _failed := false
var _field: Node3D
var _view: Node3D
var _frames: int = 0
var _stage: int = 0
var _claimed: int = 0


## A stand-in leaf field: the grid and the calls the view makes, no networking.
class FakeField extends Node3D:
	signal chunk_changed(chunk_index: int)
	var grid_width: int = 80
	var grid_depth: int = 80
	var cell_size: float = 0.5
	var grid_origin := Vector3(-20.0, 0.05, -20.0)
	var density := PackedByteArray()

	func _init() -> void:
		density.resize(grid_width * grid_depth)

	func density_at_cell(x: int, z: int) -> int:
		if x < 0 or z < 0 or x >= grid_width or z >= grid_depth:
			return 0
		return density[x + z * grid_width]

	func clean_density() -> int:
		return 8

	func chunk_count() -> int:
		return 25

	func refresh_all() -> void:
		for index: int in 25:
			chunk_changed.emit(index)


func _initialize() -> void:
	_check_meshes()
	_check_stripes()
	_check_palettes()
	_check_heights()
	_field = FakeField.new()
	_field.name = "LeafField"
	(_field as FakeField).density = _shape(777, 1)
	_view = _Renderer.new()
	_view.name = "LeafRenderer"
	_view.set("keep_state_headless", true)
	_field.add_child(_view)
	root.add_child(_field)


func _process(_delta: float) -> bool:
	_frames += 1
	match _stage:
		0:
			# The view sets up on its first frame and snaps to the field (a hard reset).
			if _frames >= 3:
				_check_surface()
				_check_budgets()
				_check_morph_start()
				_stage = 1
				_frames = 0
		1:
			if _frames >= 90:
				_check_morph_end()
				_stage = 2
		2:
			print("[LeafCheck] %s" % ("FAIL" if _failed else "PASS"))
			quit(1 if _failed else 0)
			return true
	return false


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("[LeafCheck] FAIL %s" % what)
	else:
		print("[LeafCheck]   ok %s" % what)


func _check_meshes() -> void:
	for species: int in LeafMeshes.SPECIES:
		var mesh := LeafMeshes.mesh(species)
		var triangles := LeafMeshes.triangles(species)
		_expect(triangles <= Constants.LEAF_MESH_MAX_TRIS[species], "species %d: %d triangles (budget %d)" % [species, triangles, Constants.LEAF_MESH_MAX_TRIS[species]])
		var arrays := mesh.surface_get_arrays(0)
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var bent := 0
		for normal: Vector3 in normals:
			if normal.y < 0.999:
				bent += 1
		_expect(bent > normals.size() / 2, "species %d: normals bent (%d of %d)" % [species, bent, normals.size()])
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var uv2s: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
		var rim_low := INF
		var rim_high := -INF
		var flex_high := 0.0
		var wrong_code := 0
		for uv: Vector2 in uvs:
			rim_low = minf(rim_low, uv.x)
			rim_high = maxf(rim_high, uv.x)
			flex_high = maxf(flex_high, fmod(uv.y, 2.0))
			if int(floor(uv.y * 0.5)) != species:
				wrong_code += 1
		_expect(wrong_code == 0, "species %d: species code in UV.y" % species)
		_expect(rim_low <= 0.01 and rim_high >= 0.99 and flex_high > 0.8 and uv2s.size() == uvs.size(), "species %d: rim, flex and plane masks" % species)
		var low := INF
		var high := -INF
		for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			low = minf(low, vertex.z)
			high = maxf(high, vertex.z)
		_expect(high - low > 0.95 and high - low < 1.4, "species %d: unit length (%.2f with the stem)" % [species, high - low])


## A uniform carpet must not show the old renderer's corduroy: no correlation
## between a cell's slot and the same slot a few cells along.
func _check_stripes() -> void:
	var size := 40
	var worst := 0.0
	for k: int in 3:
		for property: String in ["x", "yaw"]:
			var values := PackedFloat32Array()
			values.resize(size * size)
			for z: int in size:
				for x: int in size:
					var spot := LeafPalette.slot(x, z, k)
					values[x + z * size] = (spot["offset"] as Vector2).x if property == "x" else cos(float(spot["yaw"]))
			for shift: int in range(1, 9):
				for axis: int in 2:
					worst = maxf(worst, absf(_correlation(values, size, shift, axis)))
	_expect(worst < 0.1, "no stripes: worst lattice autocorrelation %.3f" % worst)


func _correlation(values: PackedFloat32Array, size: int, shift: int, axis: int) -> float:
	var a := PackedFloat32Array()
	var b := PackedFloat32Array()
	for z: int in size:
		for x: int in size:
			var x2 := x + (shift if axis == 0 else 0)
			var z2 := z + (shift if axis == 1 else 0)
			if x2 >= size or z2 >= size:
				continue
			a.append(values[x + z * size])
			b.append(values[x2 + z2 * size])
	var mean_a := 0.0
	var mean_b := 0.0
	for index: int in a.size():
		mean_a += a[index]
		mean_b += b[index]
	mean_a /= float(a.size())
	mean_b /= float(b.size())
	var top := 0.0
	var var_a := 0.0
	var var_b := 0.0
	for index: int in a.size():
		top += (a[index] - mean_a) * (b[index] - mean_b)
		var_a += (a[index] - mean_a) * (a[index] - mean_a)
		var_b += (b[index] - mean_b) * (b[index] - mean_b)
	return top / sqrt(maxf(var_a * var_b, 1e-12))


func _check_palettes() -> void:
	var olive := _lab(OLD_OLIVE)
	var closest := INF
	var where := ""
	for crown: String in Constants.LEAF_PALETTES:
		for color: Color in Constants.LEAF_PALETTES[crown]:
			for value: float in [0.88, 1.0, 1.10]:
				var shade := Color(color.r * value, color.g * value, color.b * value)
				var distance := _lab(shade).distance_to(olive)
				if distance < closest:
					closest = distance
					where = crown
	_expect(closest >= 12.0, "no olive: nearest palette colour (%s) is dE %.1f from the old olive" % [where, closest])
	var looks: Array = LeafPalette.cell_looks([{"at": Vector2(-5, -5), "crown": "red", "kind": "broadleaf", "variant": 0}, {"at": Vector2(6, 4), "crown": "yellow", "kind": "birch", "variant": 1}, {"at": Vector2(0, 9), "crown": "", "kind": "pine", "variant": 0}], GRID, GRID, Vector2(ORIGIN.x + 0.25, ORIGIN.z + 0.25), CELL)["looks"]
	_expect(looks.size() == 2, "a pine drops nothing (%d looks from three trees)" % looks.size())
	for season: int in 4:
		var count := 0
		for k: int in 64:
			var leaf := LeafPalette.flake(looks, [0, 1], k % 2, season, k, 3, k % 8)
			if leaf.has("centre") and float(leaf["age"]) >= 0.0 and float(leaf["age"]) <= 1.0:
				count += 1
		var litter := LeafPalette.litter(looks, season)
		_expect(count == 64 and litter.size() == looks.size(), "season %d builds (%d leaves, %d skin looks)" % [season, count, litter.size()])


## CIE Lab of an sRGB colour (D65).
func _lab(color: Color) -> Vector3:
	var linear := Vector3(_to_linear(color.r), _to_linear(color.g), _to_linear(color.b))
	var x := (0.4124 * linear.x + 0.3576 * linear.y + 0.1805 * linear.z) / 0.95047
	var y := 0.2126 * linear.x + 0.7152 * linear.y + 0.0722 * linear.z
	var z := (0.0193 * linear.x + 0.1192 * linear.y + 0.9505 * linear.z) / 1.08883
	var fx := _lab_f(x)
	var fy := _lab_f(y)
	var fz := _lab_f(z)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


func _lab_f(t: float) -> float:
	return pow(t, 1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0


func _to_linear(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)


func _check_heights() -> void:
	var last := -1.0
	var monotonic := true
	for density: int in 256:
		var height := float(_Renderer.mound_height(float(density)))
		if height < last:
			monotonic = false
		last = height
	_expect(monotonic, "mound height rises with density")
	var h60 := float(_Renderer.mound_height(60.0))
	var h150 := float(_Renderer.mound_height(150.0))
	var h255 := float(_Renderer.mound_height(255.0))
	_expect(absf(h60 - 0.015) < 0.002, "H(60) = %.3f m (about 0.015)" % h60)
	_expect(h150 > 0.2 and h150 < 0.32, "H(150) = %.3f m (a drift under a tree)" % h150)
	_expect(absf(h255 - 0.765) < 0.02, "H(255) = %.3f m (a raked pile)" % h255)
	# None at the clean line, one on a fresh lawn, more in a drift, the most on a full pile.
	var table := {8: 0, 9: 1, 60: 1, 150: 3, 255: Constants.LEAF_HERO_MAX}
	for units: int in table:
		_expect(int(_Renderer.hero_count(units)) == int(table[units]), "hero_count(%d) = %d (%d)" % [units, int(_Renderer.hero_count(units)), int(table[units])])


## Hero leaves lie exactly on the skin: slot_world's origin is surface_y plus the slot's lift.
func _check_surface() -> void:
	var worst := 0.0
	var checked := 0
	for c: int in range(0, GRID * GRID, 37):
		var cell := Vector2i(c % GRID, c / GRID)
		for k: int in [0, 3, Constants.LEAF_HERO_MAX - 1]:
			var xform: Transform3D = _view.call("slot_world", cell, k)
			var surface := float(_view.call("surface_y", Vector2(xform.origin.x, xform.origin.z)))
			var lift := Constants.LEAF_HERO_LIFT.x + Constants.LEAF_HERO_LIFT.y * float(k)
			worst = maxf(worst, absf(xform.origin.y - surface - lift))
			checked += 1
	_expect(worst < 0.0001, "slot_world on the skin: %d slots, worst %.6f m" % [checked, worst])
	var stats: Dictionary = _view.call("stats")
	_expect(int(stats.get("instant", -1)) == 0, "a hard reset pops nothing (instant %d)" % int(stats.get("instant", -1)))


## Yards like the lot generator makes: counts against the leaf budgets. Hero
## leaves draw per block (Constants.LEAF_HERO_BLOCK_CHUNKS) and species; a block
## draws while its middle is within the hero range of the camera.
func _check_budgets() -> void:
	var litter_triangles := 25 * int(LeafLitter.grid(Vector2(8.0, 8.0)).get_meta("triangles", 0))
	_expect(litter_triangles == 51200, "skin triangles %d (51,200)" % litter_triangles)
	var cameras: Array[Vector3] = [Vector3(0.0, 1.6, 0.0), Vector3(-17.0, 1.6, -17.0), Vector3(0.0, 1.6, 22.0)]
	var per := Constants.LEAF_HERO_BLOCK_CHUNKS * 16
	var blocks := int(ceil(float(GRID) / float(per)))
	for seed_value: int in [777, 1000]:
		for size: int in 3:
			var yard := _yard(seed_value, size)
			var density: PackedByteArray = yard["density"]
			var made := LeafPalette.cell_looks(yard["sources"], GRID, GRID, Vector2(ORIGIN.x + 0.25, ORIGIN.z + 0.25), CELL)
			var cell_look: PackedByteArray = made["cells"]
			# Heroes per block and species, as the view lays them.
			var counts: Array = []
			for _block: int in blocks * blocks:
				counts.append([0, 0, 0])
			for z: int in GRID:
				for x: int in GRID:
					var heroes := int(_Renderer.hero_count(density[x + z * GRID]))
					var block := int(x / per) + int(z / per) * blocks
					for k: int in heroes:
						var jx := clampi(x + int(round((LeafPalette.unit(x, z, k, 50) * 2.0 - 1.0) * 1.6)), 0, GRID - 1)
						var jz := clampi(z + int(round((LeafPalette.unit(x, z, k, 51) * 2.0 - 1.0) * 1.6)), 0, GRID - 1)
						var leaf := LeafPalette.flake(made["looks"], made["mix"], cell_look[jx + jz * GRID], 0, x, z, k)
						counts[block][int(leaf["species"])] += 1
			var worst_heroes := 0
			var worst_triangles := 0
			var worst_draws := 0
			for camera: Vector3 in cameras:
				var heroes := 0
				var triangles := litter_triangles
				var draws := 25
				for block: int in blocks * blocks:
					var span := float(per) * CELL
					var centre := Vector3(ORIGIN.x + (float(block % blocks) + 0.5) * span, 0.0, ORIGIN.z + (float(block / blocks) + 0.5) * span)
					if centre.distance_to(camera) > Constants.LEAF_HERO_RANGE + span * 0.5:
						continue
					for species: int in 3:
						var count := int(counts[block][species])
						heroes += count
						triangles += count * LeafMeshes.triangles(species)
						draws += 1 if count > 0 else 0
				worst_heroes = maxi(worst_heroes, heroes)
				worst_triangles = maxi(worst_triangles, triangles)
				worst_draws = maxi(worst_draws, draws)
			# The budgets are a medium yard's; a big yard (more trees, more leaves) gets LEAF_BIG_YARD_BUDGET times them.
			var scale := Constants.LEAF_BIG_YARD_BUDGET if size >= 2 else 1.0
			_expect(worst_heroes <= int(Constants.LEAF_MAX_HEROES_NEAR * scale), "seed %d size %d: %d hero leaves near a camera (budget %d)" % [seed_value, size, worst_heroes, int(Constants.LEAF_MAX_HEROES_NEAR * scale)])
			_expect(worst_triangles <= int(Constants.LEAF_MAX_TRIS_VISIBLE * scale), "seed %d size %d: %d leaf triangles drawn (budget %d)" % [seed_value, size, worst_triangles, int(Constants.LEAF_MAX_TRIS_VISIBLE * scale)])
			_expect(worst_draws <= Constants.LEAF_MAX_DRAWS, "seed %d size %d: %d leaf draws (budget %d)" % [seed_value, size, worst_draws, Constants.LEAF_MAX_DRAWS])	# The densest chunk, rebuilt from cached slices.
	var densest := 0
	var most := -1
	var field_density: PackedByteArray = (_field as FakeField).density
	for chunk: int in 25:
		var total := 0
		for dz: int in 16:
			for dx: int in 16:
				total += field_density[(chunk % 5) * 16 + dx + ((chunk / 5) * 16 + dz) * GRID]
		if total > most:
			most = total
			densest = chunk
	_view.call("_rebuild_chunk", densest)
	var started := Time.get_ticks_usec()
	for _round: int in 10:
		_view.call("_rebuild_chunk", densest)
	var each := float(Time.get_ticks_usec() - started) / 10000.0
	print("[LeafCheck] densest chunk rebuild from cached slices: %.3f ms" % each)
	_expect(each <= 3.0, "densest chunk rebuild %.3f ms (<= 3 ms)" % each)


## A raked lane: the field changes; with no listener every unit eases in.
func _check_morph_start() -> void:
	var fake := _field as FakeField
	for z: int in range(30, 34):
		for x: int in range(20, 40):
			fake.density[x + z * GRID] = 0
		for x: int in range(40, 44):
			fake.density[x + z * GRID] = 230
	# A listener claims part of one cell's change; it must still add up.
	_view.connect("targets_changed", func(changes: PackedInt32Array, hard: bool) -> void:
		if hard:
			return
		for index: int in range(0, changes.size(), 3):
			if changes[index] == 41 and changes[index + 1] == 31:
				_view.call("claim", Vector2i(41, 31), changes[index + 2])
				_claimed = changes[index + 2]
	)
	# Only the chunks that changed (a refresh of every chunk at once is a reset).
	for chunk: int in [6, 7, 11, 12]:
		fake.chunk_changed.emit(chunk)


func _check_morph_end() -> void:
	var fake := _field as FakeField
	var claimed_cell := Vector2i(41, 31)
	# The listener delivers what it claimed: launch nothing, land it all.
	var reservation: Dictionary = _view.call("reserve_landing", claimed_cell, _claimed)
	_view.call("land", claimed_cell, _claimed, int(reservation.get("slot", -1)))
	var mismatched := 0
	for z: int in range(28, 36):
		for x: int in range(18, 46):
			var cell := Vector2i(x, z)
			if int(_view.call("displayed_units", cell)) != fake.density[x + z * GRID]:
				mismatched += 1
	var stats: Dictionary = _view.call("stats")
	_expect(mismatched == 0, "the ease lands on the field (%d cells off)" % mismatched)
	_expect(int(stats.get("fading", -1)) == 0 and int(stats.get("morphing", -1)) == 0, "nothing still fading or easing after 1.5 s")
	_expect(_claimed > 0, "a listener claimed a change (%d units)" % _claimed)


## Density like levels/lots/lot_generator.gd _shape_leaves: an even cover per
## yard size, heaped under the yard's trees, capped; a house with none.
func _shape(seed_value: int, size: int) -> PackedByteArray:
	return _yard(seed_value, size)["density"]


## {density, sources}: the yard's trees are broadleaves (maple and oak) and a
## birch, so all three species fall.
func _yard(seed_value: int, size: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var counts: Vector2i = Constants.YARD_TREES[size]
	var trees: Array[Vector2] = []
	var sources: Array = []
	var crowns: Array[String] = ["red", "orange", "yellow", "rust"]
	for index: int in rng.randi_range(counts.x, counts.y):
		var at := Vector2(rng.randf_range(-16.5, 16.5), rng.randf_range(-16.5, 17.0))
		trees.append(at)
		sources.append({"at": at, "crown": crowns[index % crowns.size()], "kind": "birch" if index % 3 == 2 else "broadleaf", "variant": index})
	var spread := rng.randf_range(Constants.YARD_TREE_SPREAD.x, Constants.YARD_TREE_SPREAD.y)
	var base := rng.randf_range(Constants.YARD_LEAF_BASE.x, Constants.YARD_LEAF_BASE.y) * float(Constants.YARD_LEAVES[size])
	var house := Rect2(-6.0, -12.0, 12.0, 9.0)
	var density := PackedByteArray()
	density.resize(GRID * GRID)
	for z: int in GRID:
		for x: int in GRID:
			var at := Vector2(ORIGIN.x + (float(x) + 0.5) * CELL, ORIGIN.z + (float(z) + 0.5) * CELL)
			var amount := base
			for tree: Vector2 in trees:
				amount += Constants.YARD_TREE_LEAVES * exp(-at.distance_squared_to(tree) / (2.0 * spread * spread))
			if house.has_point(at) or (absf(at.x) < 3.0 and at.y > 3.0):
				amount = 0.0
			density[x + z * GRID] = clampi(int(round(60.0 * clampf(amount, 0.0, Constants.YARD_LEAF_CAP))), 0, 255)
	return {"density": density, "sources": sources}