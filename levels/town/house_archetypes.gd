extends RefCounted

## Authority: local, cosmetic. Every house archetype the town builds
## (docs/GAME.md, "2026-11-01, the neighborhood looks"), one function each,
## called by levels/town/house_builder.gd with a HouseKit and a normalized req.
## Each one builds facing +Z around the footprint's ground center and fills
## the HouseSpec (house_builder.gd lists the keys and the footprint contract).
## The main climbable roof of every job archetype is a gable along x; only the
## neighbors-only archetypes (NEIGHBOR_ONLY) break that rule.

const ALL: PackedStringArray = [
	"classic", "bungalow", "cottage", "foursquare", "single_wide", "double_wide",
	"colonial_new", "split_level", "hoa_standard", "lake_cabin", "lake_house",
	"a_frame", "estate", "modern_glass", "farmhouse",
]
## Never a job house: their roofs are not a climbable gable along x.
const NEIGHBOR_ONLY: PackedStringArray = ["a_frame", "modern_glass"]
## Main roof rise as a share of the roofed block's depth.
const RISE: Dictionary = {
	"classic": 0.38, "bungalow": 0.34, "cottage": 0.55, "foursquare": 0.3, "single_wide": 0.1,
	"double_wide": 0.12, "colonial_new": 0.36, "split_level": 0.32, "hoa_standard": 0.4,
	"lake_cabin": 0.6, "lake_house": 0.45, "estate": 0.42, "farmhouse": 0.5,
}
## Roof slab thickness, meters.
const SLAB: float = 0.16
const FOUNDATION := Color(0.55, 0.53, 0.5)
const STOOP := Color(0.62, 0.6, 0.57)
const BRICK := Color(0.58, 0.32, 0.26)
const PLYWOOD := Color(0.7, 0.58, 0.4)
const LATTICE := Color(0.92, 0.91, 0.86)
const CINDER := Color(0.62, 0.62, 0.6)
const STEEL := Color(0.62, 0.64, 0.66)
const BOXWOOD := Color(0.24, 0.42, 0.22)
const DECK := Color(0.6, 0.45, 0.32)
const MULLION := Color(0.14, 0.15, 0.16)
const FLOWERS: Array[Color] = [Color(0.92, 0.3, 0.32), Color(0.98, 0.84, 0.3), Color(0.86, 0.5, 0.8), Color(0.96, 0.96, 0.92)]


## Builds r["archetype"] into kit and returns its HouseSpec.
static func build(kit: RefCounted, r: Dictionary) -> Dictionary:
	var spec := {
		"archetype": r["archetype"], "stories": int(r["stories"]), "width": float(r["width"]), "depth": float(r["depth"]),
		"windows": [], "gutters": [], "eaves": [], "solids": [], "roof_solids": [], "roof_blockers": [], "roof": {}, "roof_edge_y": 0.0,
		"porch_depth": 0.0, "door": Vector3(0.0, 1.6, float(r["depth"]) * 0.5), "spigot": [],
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(r["seed"]), "house", str(r["archetype"])])
	match str(r["archetype"]):
		"bungalow":
			_bungalow(kit, r, spec, rng)
		"cottage":
			_cottage(kit, r, spec, rng)
		"foursquare":
			_foursquare(kit, r, spec, rng)
		"single_wide":
			_single_wide(kit, r, spec, rng)
		"double_wide":
			_double_wide(kit, r, spec, rng)
		"colonial_new":
			_colonial_new(kit, r, spec, rng)
		"split_level":
			_split_level(kit, r, spec, rng)
		"hoa_standard":
			_hoa_standard(kit, r, spec, rng)
		"lake_cabin":
			_lake_cabin(kit, r, spec, rng)
		"lake_house":
			_lake_house(kit, r, spec, rng)
		"a_frame":
			_a_frame(kit, r, spec, rng)
		"estate":
			_estate(kit, r, spec, rng)
		"modern_glass":
			_modern_glass(kit, r, spec, rng)
		"farmhouse":
			_farmhouse(kit, r, spec, rng)
		_:
			_classic(kit, r, spec)
	_clear_lines(spec)
	return spec


## The far version of a built house: its solids as boxes, its main roof, and
## two windows (about a hundred triangles).
static func far(kit: RefCounted, r: Dictionary, spec: Dictionary) -> void:
	for solid: Array in spec["solids"]:
		kit.call("box", solid[1], solid[0], r["wall"], r["wall_surface"])
	var roof: Dictionary = spec["roof"]
	var center: Vector3 = roof.get("center", Vector3.ZERO)
	var rise := float(roof.get("rise", 0.0))
	match str(roof.get("kind", "")):
		"gable_x":
			kit.call("prism", Vector3(float(roof["half_run"]) * 2.0, rise, float(roof["width"])), center + Vector3(0.0, rise * 0.5, 0.0), r["roof"], r["roof_surface"], Basis(Vector3.UP, PI * 0.5))
		"a_frame":
			kit.call("prism", Vector3(float(roof["half_run"]) * 2.0, rise, float(roof["width"])), center + Vector3(0.0, rise * 0.5, 0.0), r["roof"], r["roof_surface"])
		_:
			kit.call("box", Vector3(float(roof.get("width", 1.0)), 0.25, float(roof.get("half_run", 0.5)) * 2.0), center + Vector3(0.0, 0.12, 0.0), r["roof"], "plain")
	var shown := 0
	for entry: Array in spec["windows"]:
		if shown >= 2:
			break
		var normal: Vector3 = entry[1]
		if normal.z < 0.5:
			continue
		var size: Vector2 = entry[2]
		kit.call("window", size.x, size.y, entry[0], r["trim"], 0.0, {"far": true})
		shown += 1


# ---------------------------------------------------------------- shared parts

## A gable roof over a block of walls w long (along the ridge) and d deep, its
## eaves at top: two slabs, the gable-end walls under them, a ridge cap, and
## fascia boards. along "x" (the default) or "z" (a front-facing gable). Returns
## {half_run, rise, top}. main = true makes it the house's climbable roof in spec;
## blocker = true records its bounding box in spec "roof_blockers" (a
## cross-gable or hood that reaches the main roof or its eaves).
static func _gable(kit: RefCounted, spec: Dictionary, o: Dictionary) -> Dictionary:
	var w := float(o["w"])
	var d := float(o["d"])
	var top := float(o["top"])
	var rise := float(o["rise"])
	var ox := float(o.get("ox", 0.5))
	var oz := float(o.get("oz", 0.6))
	var roof: Color = o["roof"]
	var roof_surface := str(o["roof_surface"])
	var wall: Color = o["wall"]
	var gable_surface := str(o.get("gable_surface", o["wall_surface"]))
	var place := Transform3D(Basis(Vector3.UP, 0.0 if str(o.get("along", "x")) == "x" else PI * 0.5), Vector3(float(o["cx"]), 0.0, float(o["cz"])))
	var saved: Transform3D = kit.get("frame")
	kit.set("frame", saved * place)
	var half_run := d * 0.5 + oz
	var length := w + ox * 2.0
	var slope := atan2(rise, half_run)
	for side: float in [1.0, -1.0]:
		_slab(kit, Vector3(0.0, top + rise, 0.0), Vector3(0.0, top, side * half_run), length, roof, roof_surface)
		if o.has("fascia"):
			kit.call("box", Vector3(length, 0.2, 0.05), Vector3(0.0, top - 0.1, side * (half_run + 0.025)), o["fascia"], "planks")
	# The gable-end walls: a prism just under the slabs, so the eaves have a soffit.
	var under := SLAB / cos(slope)
	var gable_rise := rise - under
	if gable_rise > 0.05:
		var gable_half := gable_rise * half_run / rise
		kit.call("prism", Vector3(gable_half * 2.0, gable_rise, w), Vector3(0.0, top + gable_rise * 0.5, 0.0), wall, gable_surface, Basis(Vector3.UP, PI * 0.5), {"snow": 0.0})
	if bool(o.get("ridge_cap", true)):
		kit.call("box", Vector3(length + 0.04, 0.12, 0.3), Vector3(0.0, top + rise + 0.02, 0.0), roof.darkened(0.18), roof_surface)
	kit.set("frame", saved)
	if bool(o.get("blocker", false)):
		# Its bounding box, fascia and ridge cap included, as a roof blocker.
		var low := top - 0.22
		var high := top + rise + 0.14
		var half := Vector3(length * 0.5 + 0.02, (high - low) * 0.5, half_run + SLAB * sin(slope) + 0.05)
		if str(o.get("along", "x")) != "x":
			half = Vector3(half.z, half.y, half.x)
		_blocker(spec, place * Vector3(0.0, (low + high) * 0.5, 0.0), half * 2.0)
	var eave_x := length * 0.5
	for side: float in ([1.0, -1.0] if bool(o.get("eaves", o.get("main", false))) else []):
		(spec["eaves"] as Array).append([place * Vector3(-eave_x, top, side * half_run), place * Vector3(eave_x, top, side * half_run)])
	if bool(o.get("main", false)):
		spec["roof"] = {"kind": "gable_x", "center": place * Vector3(0.0, top, 0.0), "width": length, "half_run": half_run, "rise": rise, "top": top}
		spec["roof_edge_y"] = top
		for side: float in [1.0, -1.0]:
			var z := side * (half_run + 0.09)
			(spec["gutters"] as Array).append([place * Vector3(-eave_x, top - 0.08, z), place * Vector3(eave_x, top - 0.08, z), Vector3(0.0, 0.0, side)])
	return {"half_run": half_run, "rise": rise, "top": top}


## A flat slab whose top surface runs from the line through high (its middle) to
## the line through low, width across: roofs, awnings, porch roofs.
static func _slab(kit: RefCounted, high: Vector3, low: Vector3, width: float, color: Color, surface: String, thickness: float = SLAB, style: Dictionary = {}) -> void:
	var run := low - high
	var flat := Vector3(run.x, 0.0, run.z).normalized()
	var across := Vector3.UP.cross(flat).normalized()
	var along := run.normalized()
	var up := along.cross(across)
	kit.call("box", Vector3(width, thickness, run.length() + 0.02), (high + low) * 0.5 - up * thickness * 0.5, color, surface, Basis(across, up, along), style)


## A window on a wall, recorded as washable unless wash is false. yaw turns it
## from facing +Z (PI/2 faces +X).
static func _window(kit: RefCounted, spec: Dictionary, at: Vector3, yaw: float, size: Vector2, frame: Color, wash: bool = true, style: Dictionary = {}) -> void:
	kit.call("window", size.x, size.y, at, frame, yaw, style)
	if wash:
		var normal := Vector3(snappedf(sin(yaw), 0.0001), 0.0, snappedf(cos(yaw), 0.0001))
		(spec["windows"] as Array).append([at, normal, size])


## Shutters either side of a window facing +Z (or yaw).
static func _shutters(kit: RefCounted, at: Vector3, yaw: float, size: Vector2, color: Color) -> void:
	var basis := Basis(Vector3.UP, yaw)
	for side: float in [-1.0, 1.0]:
		kit.call("box", Vector3(0.36, size.y + 0.15, 0.06), at + basis * Vector3(side * (size.x * 0.5 + 0.27), 0.0, 0.03), color, "planks", basis)


## A keystone and lintel over a window facing +Z.
static func _keystone(kit: RefCounted, at: Vector3, size: Vector2, color: Color) -> void:
	kit.call("box", Vector3(size.x + 0.4, 0.16, 0.08), at + Vector3(0.0, size.y * 0.5 + 0.17, 0.04), color, "stone", Basis.IDENTITY, {"params": Vector4(1, 0, 0, 0)})
	kit.call("box", Vector3(0.28, 0.38, 0.12), at + Vector3(0.0, size.y * 0.5 + 0.22, 0.06), color.lightened(0.06), "stone", Basis.IDENTITY, {"params": Vector4(1, 0, 0, 0)})


## A flower box under a window facing +Z: the planter and a row of blooms.
static func _flower_box(kit: RefCounted, at: Vector3, width: float, color: Color, rng: RandomNumberGenerator) -> void:
	kit.call("box", Vector3(width + 0.1, 0.26, 0.3), at + Vector3(0.0, 0.0, 0.17), color, "planks")
	kit.call("box", Vector3(width, 0.12, 0.22), at + Vector3(0.0, 0.18, 0.17), BOXWOOD, "foliage")
	var bloom: Color = FLOWERS[rng.randi() % FLOWERS.size()]
	for index: int in 3:
		kit.call("box", Vector3(0.16, 0.1, 0.12), at + Vector3((float(index) - 1.0) * width * 0.32, 0.27, 0.19), bloom, "plain")


## A front door facing +Z with its frame, its bottom at y0 on the wall at z.
static func _door(kit: RefCounted, spec: Dictionary, x: float, y0: float, z: float, color: Color, trim: Color, width: float = 1.1, height: float = 2.2) -> void:
	kit.call("box", Vector3(width, height, 0.08), Vector3(x, y0 + height * 0.5, z + 0.03), color, "planks")
	kit.call("box", Vector3(width + 0.3, 0.14, 0.1), Vector3(x, y0 + height + 0.08, z + 0.05), trim, "planks")
	for side: float in [-1.0, 1.0]:
		kit.call("box", Vector3(0.1, height, 0.1), Vector3(x + side * (width * 0.5 + 0.05), y0 + height * 0.5, z + 0.05), trim, "planks")
	kit.call("box", Vector3(0.07, 0.07, 0.07), Vector3(x + width * 0.36, y0 + height * 0.45, z + 0.1), Color(0.82, 0.68, 0.3), "metal")
	spec["door"] = Vector3(x, y0 + height * 0.5, z + 0.07)


## count steps down from a porch top at y_top, starting at z0 and stepping
## forward by each. Returns the z of the last step's front.
static func _steps(kit: RefCounted, x: float, z0: float, y_top: float, width: float, each: float, count: int, color: Color, surface: String = "concrete") -> float:
	for index: int in count:
		var height := y_top * float(count - index) / float(count + 1)
		kit.call("box", Vector3(width, height, each), Vector3(x, height * 0.5, z0 + each * (float(index) + 0.5)), color, surface)
	return z0 + each * float(count)


## A porch rail from a to b (level), height tall, with balusters every spacing (0: none).
static func _rail(kit: RefCounted, a: Vector3, b: Vector3, height: float, color: Color, spacing: float = 0.0) -> void:
	var run := b - a
	var length := Vector3(run.x, 0.0, run.z).length()
	if length < 0.2:
		return
	var basis := Basis(Vector3.UP, atan2(-run.z, run.x))
	var middle := (a + b) * 0.5
	kit.call("box", Vector3(length, 0.08, 0.1), middle + Vector3(0.0, height, 0.0), color, "planks", basis)
	kit.call("box", Vector3(length, 0.06, 0.06), middle + Vector3(0.0, 0.12, 0.0), color, "planks", basis)
	if spacing <= 0.0:
		return
	var count := int(length / spacing)
	for index: int in range(1, count):
		var t := float(index) / float(count)
		kit.call("box", Vector3(0.045, height - 0.12, 0.045), a.lerp(b, t) + Vector3(0.0, 0.12 + (height - 0.12) * 0.5, 0.0), color, "planks", basis)


## A balustrade from a to b: a plinth, round balusters, and a stone top rail.
static func _balustrade(kit: RefCounted, a: Vector3, b: Vector3, color: Color) -> void:
	var run := b - a
	var length := Vector3(run.x, 0.0, run.z).length()
	if length < 0.4:
		return
	var basis := Basis(Vector3.UP, atan2(-run.z, run.x))
	var middle := (a + b) * 0.5
	var ashlar := {"params": Vector4(1, 0, 0, 0)}
	kit.call("box", Vector3(length, 0.14, 0.3), middle + Vector3(0.0, 0.07, 0.0), color, "stone", basis, ashlar)
	kit.call("box", Vector3(length + 0.1, 0.12, 0.32), middle + Vector3(0.0, 0.72, 0.0), color, "stone", basis, ashlar)
	var count := int(length / 0.34)
	for index: int in range(1, count):
		var at := a.lerp(b, float(index) / float(count))
		kit.call("cylinder", 0.07, 0.52, at + Vector3(0.0, 0.4, 0.0), color.lightened(0.04), "stone", 6, {"top_radius": 0.05})


## A round column standing on a plinth at base, with a capital.
static func _column(kit: RefCounted, base: Vector3, height: float, radius: float, color: Color) -> void:
	kit.call("box", Vector3(radius * 2.6, 0.22, radius * 2.6), base + Vector3(0.0, 0.11, 0.0), color, "stone")
	kit.call("cylinder", radius, height - 0.42, base + Vector3(0.0, 0.22 + (height - 0.42) * 0.5, 0.0), color, "stucco", 12, {"top_radius": radius * 0.86})
	kit.call("box", Vector3(radius * 2.5, 0.2, radius * 2.5), base + Vector3(0.0, height - 0.1, 0.0), color, "stone")


## A chimney from y0 up to y1, with a cap, recorded as a roof blocker.
static func _chimney(kit: RefCounted, spec: Dictionary, x: float, z: float, size: Vector2, y0: float, y1: float, color: Color, surface: String) -> void:
	kit.call("box", Vector3(size.x, y1 - y0, size.y), Vector3(x, (y0 + y1) * 0.5, z), color, surface)
	kit.call("box", Vector3(size.x + 0.14, 0.14, size.y + 0.14), Vector3(x, y1 + 0.07, z), color.darkened(0.25), "concrete")
	_blocker(spec, Vector3(x, (y0 + y1 + 0.14) * 0.5, z), Vector3(size.x + 0.14, y1 + 0.14 - y0, size.y + 0.14))


## Something that stands on the main roof or across its eaves (a dormer, a
## cross-gable, a door hood, a pediment, a chimney), as a box [center, size], so
## the lot skips roof spots and adds colliders there, and gutters and eaves
## split around it (_clear_lines).
static func _blocker(spec: Dictionary, center: Vector3, size: Vector3) -> void:
	(spec["roof_blockers"] as Array).append([center, size])


## Splits every gutter and eave around the solids and roof blockers it would
## run through (a cottage's bay, a garage's cross-gable, a door hood, a
## pediment, a wing's eave running into the core's wall), so a lot never hangs
## a gutter, a clean-gutters spot, or a string light inside a wall or a roof.
static func _clear_lines(spec: Dictionary) -> void:
	var boxes: Array[AABB] = []
	for entry: Array in (spec["solids"] as Array) + (spec["roof_blockers"] as Array):
		var size: Vector3 = entry[1]
		boxes.append(AABB((entry[0] as Vector3) - size * 0.5, size).grow(Constants.ART_HOUSE_LINE_CLEARANCE))
	for key: String in ["gutters", "eaves"]:
		var kept: Array = []
		for line: Array in spec[key]:
			var a: Vector3 = line[0]
			var b: Vector3 = line[1]
			for span: Vector2 in _free_spans(a, b, boxes):
				var from := a.lerp(b, span.x)
				var to := a.lerp(b, span.y)
				if from.distance_to(to) < Constants.ART_HOUSE_MIN_LINE:
					continue
				var piece := line.duplicate()
				piece[0] = from
				piece[1] = to
				kept.append(piece)
		spec[key] = kept


## The parts (t from 0 to 1) of the segment a..b outside every box.
static func _free_spans(a: Vector3, b: Vector3, boxes: Array[AABB]) -> Array[Vector2]:
	var spans: Array[Vector2] = [Vector2(0.0, 1.0)]
	for box: AABB in boxes:
		var hit := _segment_span(a, b, box)
		if hit.x >= hit.y:
			continue
		var next: Array[Vector2] = []
		for span: Vector2 in spans:
			if hit.y <= span.x or hit.x >= span.y:
				next.append(span)
				continue
			if hit.x > span.x:
				next.append(Vector2(span.x, hit.x))
			if hit.y < span.y:
				next.append(Vector2(hit.y, span.y))
		spans = next
	return spans


## The part (t0, t1) of the segment a..b inside box; t0 >= t1 when it misses.
static func _segment_span(a: Vector3, b: Vector3, box: AABB) -> Vector2:
	var t0 := 0.0
	var t1 := 1.0
	var run := b - a
	for axis: int in 3:
		var low := box.position[axis]
		var high := box.end[axis]
		if absf(run[axis]) < 1e-6:
			if a[axis] <= low or a[axis] >= high:
				return Vector2(1.0, 0.0)
			continue
		var ta := (low - a[axis]) / run[axis]
		var tb := (high - a[axis]) / run[axis]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	return Vector2(t0, t1)


## Walls of a block from y0 to y1, and its solid (from the ground).
static func _walls(kit: RefCounted, spec: Dictionary, cx: float, cz: float, w: float, d: float, y0: float, y1: float, color: Color, surface: String, style: Dictionary = {}) -> void:
	kit.call("box", Vector3(w, y1 - y0, d), Vector3(cx, (y0 + y1) * 0.5, cz), color, surface, Basis.IDENTITY, style)
	(spec["solids"] as Array).append([Vector3(cx, y1 * 0.5, cz), Vector3(w, y1, d)])


static func _foundation(kit: RefCounted, cx: float, cz: float, w: float, d: float, height: float, color: Color = FOUNDATION) -> void:
	kit.call("box", Vector3(w + 0.3, height, d + 0.3), Vector3(cx, height * 0.5, cz), color, "concrete")


## A dormer on the front slope of a gable g ({half_run, rise, top}) centered at
## x, with a window (not washable: it is up on the roof).
static func _dormer(kit: RefCounted, spec: Dictionary, r: Dictionary, x: float, cz: float, g: Dictionary, width: float) -> void:
	var half_run := float(g["half_run"])
	var rise := float(g["rise"])
	var top := float(g["top"])
	# Its front halfway down the slope; its peak meets the main roof just short of the ridge.
	var front := cz + half_run * 0.5
	var at_slope := top + rise * 0.5
	var y0 := at_slope - 0.25
	var y1 := top + rise * 0.85
	var back := cz + half_run * 0.05
	kit.call("box", Vector3(width, y1 - y0, front - back), Vector3(x, (y0 + y1) * 0.5, (front + back) * 0.5), r["wall"], r["wall_surface"])
	_gable(kit, spec, {"cx": x, "cz": (front + back) * 0.5, "w": front - back, "d": width, "top": y1, "rise": rise * 0.1, "ox": 0.2, "oz": 0.15, "along": "z", "ridge_cap": false,
		"roof": r["roof"], "roof_surface": r["roof_surface"], "wall": r["wall"], "wall_surface": r["wall_surface"]})
	# The whole dormer, its little gable and overhangs included.
	var peak := y1 + rise * 0.1 + 0.05
	_blocker(spec, Vector3(x, (y0 + peak) * 0.5, (front + back) * 0.5), Vector3(width + 0.34, peak - y0, front - back + 0.44))
	var high := minf(0.85, y1 - at_slope - 0.3)
	if high > 0.3:
		_window(kit, spec, Vector3(x, (at_slope + y1) * 0.5, front + 0.02), 0.0, Vector2(minf(1.0, width - 0.7), high), r["trim"], false, {"sill": false})


static func _side_windows(kit: RefCounted, spec: Dictionary, half_x: float, cx: float, z: float, y: float, size: Vector2, trim: Color, sides: Array = [-1.0, 1.0]) -> void:
	for side: float in sides:
		_window(kit, spec, Vector3(cx + side * (half_x + 0.02), y, z), side * PI * 0.5, size, trim)


static func _back_windows(kit: RefCounted, spec: Dictionary, xs: Array, z: float, y: float, size: Vector2, trim: Color) -> void:
	for x: float in xs:
		_window(kit, spec, Vector3(x, y, z - 0.02), PI, size, trim)


static func _spigot(spec: Dictionary, x: float, z: float, side: float) -> void:
	spec["spigot"] = [Vector3(x + side * 0.02, 0.6, z), Vector3(side, 0.0, 0.0)]


# ---------------------------------------------------------------- archetypes

## Today's house (levels/dressing/neighborhood.gd house() before the kit),
## shape for shape: a box on a foundation, a solid shingled gable, a porch roof
## on posts, windows with shutters, a brick chimney, and maybe a garage.
static func _classic(kit: RefCounted, r: Dictionary, spec: Dictionary) -> void:
	var width := float(r["width"])
	var depth := float(r["depth"])
	var stories := int(r["stories"])
	var wall: Color = r["wall"]
	var roof: Color = r["roof"]
	var trim: Color = r["trim"]
	var story := 3.0
	var height := story * float(stories)
	var front := depth * 0.5
	kit.call("box", Vector3(width + 0.3, 0.5, depth + 0.3), Vector3(0.0, 0.25, 0.0), FOUNDATION, "concrete")
	kit.call("box", Vector3(width, height, depth), Vector3(0.0, 0.5 + height * 0.5, 0.0), wall, r["wall_surface"])
	var top := 0.5 + height
	for corner: float in [-1.0, 1.0]:
		kit.call("box", Vector3(0.22, height, 0.22), Vector3(corner * width * 0.5, 0.5 + height * 0.5, front), trim, "planks")
	kit.call("prism", Vector3(depth + 1.4, depth * 0.38, width + 1.0), Vector3(0.0, top + depth * 0.19, 0.0), roof, r["roof_surface"], Basis(Vector3.UP, PI * 0.5))
	kit.call("box", Vector3(width + 1.0, 0.2, 0.14), Vector3(0.0, top - 0.02, front + 0.68), trim, "planks")
	kit.call("box", Vector3(0.9, depth * 0.38 + 1.4, 0.9), Vector3(width * 0.28, top + depth * 0.19 + 0.3, -depth * 0.12), BRICK, "brick")
	_blocker(spec, Vector3(width * 0.28, top + depth * 0.19 + 0.3, -depth * 0.12), Vector3(0.9, depth * 0.38 + 1.4, 0.9))
	kit.call("box", Vector3(1.1, 2.2, 0.08), Vector3(0.0, 1.6, front + 0.03), r["door"], "planks")
	kit.call("box", Vector3(1.4, 0.14, 0.1), Vector3(0.0, 2.78, front + 0.05), trim, "planks")
	kit.call("box", Vector3(3.4, 0.14, 2.0), Vector3(0.0, 3.1, front + 1.0), roof, "shingles")
	for side: float in [-1.0, 1.0]:
		kit.call("box", Vector3(0.16, 2.6, 0.16), Vector3(side * 1.5, 1.8, front + 1.85), trim, "planks")
	kit.call("box", Vector3(3.2, 0.5, 2.0), Vector3(0.0, 0.25, front + 1.0), STOOP, "concrete", Basis.IDENTITY, {"snow": 0.0})
	kit.call("box", Vector3(1.6, 0.25, 0.6), Vector3(0.0, 0.12, front + 2.3), STOOP, "concrete")
	for floor_index: int in stories:
		var y := 0.5 + story * float(floor_index) + 1.65
		var xs: Array[float] = [-width * 0.3, width * 0.3]
		if floor_index > 0:
			xs.append(0.0)
		for x: float in xs:
			if bool(r["garage"]) and floor_index == 0 and x > 0.0:
				continue
			_window(kit, spec, Vector3(x, y, front + 0.02), 0.0, Vector2(1.3, 1.25), trim)
			for side: float in [-1.0, 1.0]:
				kit.call("box", Vector3(0.36, 1.4, 0.06), Vector3(x + side * 0.92, y, front + 0.05), roof.lightened(0.15), "planks")
		for side: float in [-1.0, 1.0]:
			_window(kit, spec, Vector3(side * (width * 0.5 + 0.02), y, 0.0), side * PI * 0.5, Vector2(1.1, 1.1), trim)
	if bool(r["garage"]):
		var door_x := width * 0.3
		kit.call("box", Vector3(2.8, 2.3, 0.1), Vector3(door_x, 1.65, front + 0.04), trim.darkened(0.04), "siding")
		kit.call("box", Vector3(3.1, 0.14, 0.12), Vector3(door_x, 2.88, front + 0.06), trim, "planks")
	var half_run := (depth + 1.4) * 0.5
	spec["roof"] = {"kind": "gable_x", "center": Vector3(0.0, top, 0.0), "width": width + 1.0, "half_run": half_run, "rise": depth * 0.38, "top": top}
	spec["roof_edge_y"] = top
	for side: float in [1.0, -1.0]:
		var z := side * (depth * 0.5 + 0.6)
		(spec["gutters"] as Array).append([Vector3(-(width + 1.0) * 0.5, top - 0.08, z), Vector3((width + 1.0) * 0.5, top - 0.08, z), Vector3(0.0, 0.0, side)])
		(spec["eaves"] as Array).append([Vector3(-(width + 1.0) * 0.5, top, side * half_run), Vector3((width + 1.0) * 0.5, top, side * half_run)])
	spec["solids"] = [[Vector3(0.0, top * 0.5, 0.0), Vector3(width, top, depth)]]
	spec["porch_depth"] = 2.6
	spec["door"] = Vector3(0.0, 1.6, front + 0.07)
	_spigot(spec, width * 0.5, -depth * 0.25, 1.0)


## Maple Row: one story, a full-width porch under its own roof, tapered
## columns on brick piers, a dormer on the front slope, a brick chimney.
static func _bungalow(kit: RefCounted, r: Dictionary, spec: Dictionary, rng: RandomNumberGenerator) -> void:
	var w := float(r["width"])
	var d := float(r["depth"])
	var front := d * 0.5
	var base := 0.6
	var top := base + 3.0
	var trim: Color = r["trim"]
	spec["stories"] = 1
	_foundation(kit, 0.0, 0.0, w, d, base)
	_walls(kit, spec, 0.0, 0.0, w, d, base, top, r["wall"], r["wall_surface"])
	var g := _gable(kit, spec, {"cx": 0.0, "cz": 0.0, "w": w, "d": d, "top": top, "rise": d * RISE["bungalow"], "main": true, "fascia": trim,
		"roof": r["roof"], "roof_surface": r["roof_surface"], "wall": r["wall"], "wall_surface": r["wall_surface"]})
	_dormer(kit, spec, r, 0.0, 0.0, g, clampf(w * 0.3, 2.0, 2.8))
	# The porch: deck, steps, a low roof tucked under the eave, piers and columns.
	var porch := 1.9
	kit.call("box", Vector3(w - 0.2, base - 0.08, porch), Vector3(0.0, (base - 0.08) * 0.5, front + porch * 0.5), STOOP, "concrete", Basis.IDENTITY, {"snow": 0.0})
	kit.call("box", Vector3(w - 0.2, 0.08, porch), Vector3(0.0, base - 0.04, front + porch * 0.5), DECK, "planks", Basis.IDENTITY, {"snow": 0.0})
	var reach := _steps(kit, 0.0, front + porch, base, 1.8, 0.3, 2, STOOP)
	var roof_high := top - 0.3
	var roof_low := top - 0.85
	var roof_out := front + 2.15
	_slab(kit, Vector3(0.0, roof_high, front), Vector3(0.0, roof_low, roof_out), w + 0.5, r["roof"], r["roof_surface"], 0.12)
	var post_z := front + porch - 0.35
	var at_post := roof_high + (roof_low - roof_high) * (post_z - front) / (roof_out - front) - 0.14
	var xs: Array[float] = [-(w * 0.5 - 0.45), -1.25, 1.25, w * 0.5 - 0.45]
	for x: float in xs:
		kit.call("box", Vector3(0.55, 0.9, 0.55), Vector3(x, base + 0.45, post_z), r["accent"], "brick")
		var column := at_post - (base + 0.9)
		kit.call("cylinder", 0.21, column, Vector3(x, base + 0.9 + column * 0.5, post_z), trim, "planks", 4, {"top_radius": 0.14, "turn": PI * 0.25})
	for pair: Array in [[xs[0], xs[1]], [xs[2], xs[3]]]:
		_rail(kit, Vector3(float(pair[0]) + 0.3, base, post_z), Vector3(float(pair[1]) - 0.3, base, post_z), 0.85, trim, 0.4)
	_door(kit, spec, 0.0, base, front, r["door"], trim)
	for x: float in [-w * 0.3, w * 0.3]:
		_window(kit, spec, Vector3(x, base + 1.6, front + 0.02), 0.0, Vector2(1.5, 1.3), trim)
	_side_windows(kit, spec, w * 0.5, 0.0, -d * 0.1, base + 1.6, Vector2(1.1, 1.1), trim)
	_back_windows(kit, spec, [-w * 0.25, w * 0.25], -front, base + 1.6, Vector2(1.2, 1.1), trim)
	var chimney_x := w * 0.3 * (1.0 if rng.randf() < 0.5 else -1.0)
	_chimney(kit, spec, chimney_x, -d * 0.15, Vector2(0.8, 0.8), top - 0.2, top + g["rise"] + 0.8, BRICK, "brick")
	spec["porch_depth"] = reach - front
	_spigot(spec, w * 0.5, -d * 0.3, 1.0)


## Maple Row: a steep roof, a cross-gabled bay with a big window, a brick
## chimney up one gable end, flower boxes, and a little hood over the door.
static func _cottage(kit: RefCounted, r: Dictionary, spec: Dictionary, rng: RandomNumberGenerator) -> void:
	var w := float(r["width"])
	var d := float(r["depth"])
	var stories := int(r["stories"])
	var front := d * 0.5
	var base := 0.5
	var story := 2.8
	var top := base + story * float(stories)
	var trim: Color = r["trim"]
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var bay_w := clampf(w * 0.38, 2.6, 4.0)
	var bay_x := side * (w * 0.5 - bay_w * 0.5 - 0.4)
	var bay_out := 1.2
	_foundation(kit, 0.0, 0.0, w, d, base)
	_foundation(kit, bay_x, front + bay_out * 0.5, bay_w, bay_out, base)
	_walls(kit, spec, 0.0, 0.0, w, d, base, top, r["wall"], r["wall_surface"])
	_walls(kit, spec, bay_x, front + bay_out * 0.5, bay_w, bay_out, base, top, r["wall"], r["wall_surface"])
	var g := _gable(kit, spec, {"cx": 0.0, "cz": 0.0, "w": w, "d": d, "top": top, "rise": d * RISE["cottage"], "main": true, "fascia": trim,
		"roof": r["roof"], "roof_surface": r["roof_surface"], "wall": r["wall"], "wall_surface": r["wall_surface"]})
	var bay_len := front + bay_out
	_gable(kit, spec, {"cx": bay_x, "cz": bay_len * 0.5, "w": bay_len, "d": bay_w, "top": top, "rise": minf(bay_w * 0.7, float(g["rise"]) * 0.85), "ox": 0.3, "oz": 0.3, "along": "z", "blocker": true,
		"roof": r["roof"], "roof_surface": r["roof_surface"], "wall": r["wall"], "wall_surface": r["wall_surface"]})
	# The bay's big window (and one above it on two stories), with a flower box.
	var bay_win := Vector2(minf(bay_w - 0.9, 2.0), 1.4)
	var bay_front := front + bay_out
	_window(kit, spec, Vector3(bay_x, base + 1.55, bay_front + 0.02), 0.0, bay_win, trim)
	_flower_box(kit, Vector3(bay_x, base + 1.55 - bay_win.y * 0.5 - 0.3, bay_front), bay_win.x, trim.darkened(0.15), rng)
	if stories > 1:
		_window(kit, spec, Vector3(bay_x, base + story + 1.4, bay_front + 0.02), 0.0, Vector2(1.1, 1.1), trim)
	# The door beside the bay, under a little gabled hood, on a stoop.
	var door_x := side * (w * 0.5 - bay_w - 1.4)
	_door(kit, spec, door_x, base, front, r["door"], trim, 1.0, 2.1)
	_gable(kit, spec, {"cx": door_x, "cz": front + 0.4, "w": 0.8, "d": 1.5, "top": base + 2.5, "rise": 0.5, "ox": 0.05, "oz": 0.1, "along": "z", "blocker": true,
		"roof": r["roof"], "roof_surface": r["roof_surface"], "wall": trim, "wall_surface": "planks"})
	kit.call("box", Vector3(1.8, base, 1.2), Vector3(door_x, base * 0.5, front + 0.6), STOOP, "concrete", Basis.IDENTITY, {"snow": 0.0})
	var reach := _steps(kit, door_x, front + 1.2, base, 1.4, 0.4, 1, STOOP)
	# The other front window, with its own flower box, and the windows above.
	var other_x := -side * (w * 0.5 - 1.2)
	_window(kit, spec, Vector3(other_x, base + 1.55, front + 0.02), 0.0, Vector2(1.2, 1.2), trim)
	_flower_box(kit, Vector3(other_x, base + 1.55 - 0.9, front), 1.2, trim.darkened(0.15), rng)
	_shutters(kit, Vector3(other_x, base + 1.55, front + 0.02), 0.0, Vector2(1.2, 1.2), r["accent"].darkened(0.1))
	if stories > 1:
		_window(kit, spec, Vector3(other_x, base + story + 1.4, front + 0.02), 0.0, Vector2(1.1, 1.1), trim)
	# A brick chimney up the far gable end.
	_chimney(kit, spec, -side * (w * 0.5 + 0.08), -d * 0.1, Vector2(0.8, 1.2), 0.0, top + float(g["rise"]) * 0.9, BRICK, "brick")
	for floor_index: int in stories:
		var y := base + story * float(floor_index) + 1.5
		_side_windows(kit, spec, w * 0.5, 0.0, d * 0.28, y, Vector2(1.0, 1.0), trim, [side])
		_side_windows(kit, spec, w * 0.5, 0.0, d * 0.3, y, Vector2(0.9, 1.0), trim, [-side])
		_back_windows(kit, spec, [-w * 0.25, w * 0.25], -front, y, Vector2(1.1, 1.0), trim)
	spec["porch_depth"] = maxf(reach - front, bay_out + 0.3)
	_spigot(spec, side * w * 0.5, -d * 0.25, side)


## Maple Row two-story: a brick ground floor, siding above, a low gable with a
## dormer, and a full porch on square columns.
static func _foursquare(kit: RefCounted, r: Dictionary, spec: Dictionary, rng: RandomNumberGenerator) -> void:
	var w := float(r["width"])
	var d := float(r["depth"])
	var front := d * 0.5
	var base := 0.6
	var story := 3.0
	var top := base + story * 2.0
	var trim: Color = r["trim"]
	spec["stories"] = 2
	_foundation(kit, 0.0, 0.0, w, d, base)
	kit.call("box", Vector3(w, story, d), Vector3(0.0, base + story * 0.5, 0.0), r["accent"], "brick")
	kit.call("box", Vector3(w, story, d), Vector3(0.0, base + story * 1.5, 0.0), r["wall"], r["wall_surface"])
	kit.call("box", Vector3(w + 0.08, 0.2, d + 0.08), Vector3(0.0, base + story, 0.0), trim, "planks")
	(spec["solids"] as Array).append([Vector3(0.0, top * 0.5, 0.0), Vector3(w, top, d)])
	var g := _gable(kit, spec, {"cx": 0.0, "cz": 0.0, "w": w, "d": d, "top": top, "rise": d * RISE["foursquare"], "main": true, "fascia": trim,
		"roof": r["roof"], "roof_surface": r["roof_surface"], "wall": r["wall"], "wall_surface": r["wall_surface"]})
	_dormer(kit, spec, r, 0.0, 0.0, g, clampf(w * 0.28, 2.0, 2.8))
	var porch := 2.0
	kit.call("box", Vector3(w, base - 0.08, porch), Vector3(0.0, (base - 0.08) * 0.5, front + porch * 0.5), STOOP, "concrete", Basis.IDENTITY, {"snow": 0.0})
	kit.call("box", Vector3(w, 0.08, porch), Vector3(0.0, base - 0.04, front + porch * 0.5), DECK, "planks", Basis.IDENTITY, {"snow": 0.0})
	var reach := _steps(kit, 0.0, front + porch, base, 2.0, 0.3, 2, STOOP)
	var roof_high := base + story - 0.05
	var roof_low := roof_high - 0.35
	_slab(kit, Vector3(0.0, roof_high, front), Vector3(0.0, roof_low, front + 2.2), w + 0.3, r["roof"], r["roof_surface"], 0.12)
	var post_z := front + porch - 0.2
	var post_h := roof_low + 0.3 - base - 0.14
	var xs: Array[float] = [-(w * 0.5 - 0.25), -1.2, 1.2, w * 0.5 - 0.25]
	for x: float in xs:
		kit.call("box", Vector3(0.3, post_h, 0.3), Vector3(x, base + post_h * 0.5, post_z), trim, "planks")
	for pair: Array in [[xs[0], xs[1]], [xs[2], xs[3]]]:
		_rail(kit, Vector3(float(pair[0]) + 0.2, base, post_z), Vector3(float(pair[1]) - 0.2, base, post_z), 0.85, trim, 0.4)
	_door(kit, spec, 0.0, base, front, r["door"], trim)
	for x: float in [-w * 0.28, w * 0.28]:
		_window(kit, spec, Vector3(x, base + 1.6, front + 0.02), 0.0, Vector2(1.3, 1.5), trim)
	var upper: Array = [-w * 0.3, 0.0, w * 0.3] if w >= 10.0 else [-w * 0.25, w * 0.25]
	for x: float in upper:
		_window(kit, spec, Vector3(x, base + story + 1.5, front + 0.02), 0.0, Vector2(1.2, 1.3), trim)
	for floor_index: int in 2:
		var y := base + story * float(floor_index) + 1.55
		_side_windows(kit, spec, w * 0.5, 0.0, 0.0, y, Vector2(1.1, 1.2), trim)
		_back_windows(kit, spec, [-w * 0.25, w * 0.25], -front, y, Vector2(1.1, 1.2), trim)
	_chimney(kit, spec, w * 0.25 * (1.0 if rng.randf() < 0.5 else -1.0), -d * 0.2, Vector2(0.8, 0.8), top - 0.2, top + float(g["rise"]) + 0.7, BRICK, "brick")
	spec["porch_depth"] = reach - front
	_spigot(spec, -w * 0.5, -d * 0.3, -1.0)


## Dandelion Acres: a single-wide on cinder blocks, lattice skirt front and
## back, corrugated walls with a contrast stripe, a shallow metal roof, a
## plywood deck under a metal awning, a window AC, and the hitch still on.
static func _single_wide(kit: RefCounted, r: Dictionary, spec: Dictionary, rng: RandomNumberGenerator) -> void:
	var w := float(r["width"])
	var d := float(r["depth"])
	var front := d * 0.5
	var body_d := minf(4.4, d)
	var body_z := front - body_d * 0.5
	var floor_y := 0.8
	var top := floor_y + 2.45
	var trim: Color = r["trim"]
	spec["stories"] = 1
	# Up on blocks: piers, the steel frame, and lattice along the long sides.
	var piers := maxi(2, int(w / 2.2))
	for index: int in piers:
		var x := -w * 0.5 + 0.5 + (w - 1.0) * float(index) / float(piers - 1)
		for row: float in [-1.0, 1.0]:
			kit.call("box", Vector3(0.4, floor_y - 0.1, 0.4), Vector3(x, (floor_y - 0.1) * 0.5, body_z + row * (body_d * 0.5 - 0.7)), CINDER, "cinderblock")
	kit.call("box", Vector3(w - 0.3, 0.14, body_d - 0.6), Vector3(0.0, floor_y - 0.07, body_z), STEEL.darkened(0.4), "metal")
	for row: float in [-1.0, 1.0]:
		kit.call("box", Vector3(w - 0.1, floor_y - 0.05, 0.04), Vector3(0.0, (floor_y - 0.05) * 0.5, body_z + row * (body_d * 0.5 - 0.1)), LATTICE, "planks")
	_walls(kit, spec, 0.0, body_z, w, body_d, floor_y, top, r["wall"], r["wall_surface"])
	kit.call("box", Vector3(w + 0.04, 0.34, body_d + 0.04), Vector3(0.0, floor_y + 0.55, body_z), r["accent"], r["wall_surface"])
	_gable(kit, spec, {"cx": 0.0, "cz": body_z, "w": w, "d": body_d, "top": top, "rise": body_d * RISE["single_wide"], "ox": 0.25, "oz": 0.3, "main": true, "ridge_cap": false,
		"roof": r["roof"], "roof_surface": r["roof_surface"], "wall": r["wall"], "wall_surface": r["wall_surface"]})
	# The door, a plywood deck on blocks, steps, and an awning on two posts.
	var door_x := w * 0.25 * (1.0 if rng.randf() < 0.5 else -1.0)
	_door(kit, spec, door_x, floor_y, front, r["door"], trim, 0.9, 2.0)
	kit.call("box", Vector3(3.0, 0.1, 2.0), Vector3(door_x, floor_y - 0.05, front + 1.0), PLYWOOD, "planks", Basis.IDENTITY, {"snow": 0.0})
	for corner: Vector2 in [Vector2(-1.3, 0.3), Vector2(1.3, 0.3), Vector2(-1.3, 1.8), Vector2(1.3, 1.8)]:
		kit.call("box", Vector3(0.3, floor_y - 0.1, 0.3), Vector3(door_x + corner.x, (floor_y - 0.1) * 0.5, front + corner.y), CINDER, "cinderblock")
	var reach := _steps(kit, door_x, front + 2.0, floor_y, 1.0, 0.25, 2, PLYWOOD, "planks")
	_slab(kit, Vector3(door_x, top - 0.2, front), Vector3(door_x, top - 0.5, front + 2.25), 3.4, r["roof"], "corrugated", 0.05)
	for x: float in [door_x - 1.55, door_x + 1.55]:
		kit.call("cylinder", 0.04, top - 0.5 - floor_y, Vector3(x, floor_y + (top - 0.5 - floor_y) * 0.5, front + 2.1), STEEL, "metal", 6)
	# Front windows, skipping the door, the first with an AC unit hanging out of it.
	var size := Vector2(1.0, 0.85)
	var window_y := floor_y + 1.45
	var with_ac := false
	for t: float in [-0.4, -0.12, 0.14, 0.4]:
		var x := w * t
		if absf(x - door_x) < 1.4:
			continue
		_window(kit, spec, Vector3(x, window_y, front + 0.02), 0.0, size, trim)
		if not with_ac:
			with_ac = true
			kit.call("box", Vector3(0.66, 0.42, 0.5), Vector3(x, window_y - 0.2, front + 0.25), Color(0.86, 0.86, 0.82), "metal")
			kit.call("box", Vector3(0.5, 0.26, 0.02), Vector3(x, window_y - 0.2, front + 0.51), STEEL.darkened(0.3), "corrugated")
	_side_windows(kit, spec, w * 0.5, 0.0, body_z, window_y, Vector2(0.8, 0.8), trim)
	_back_windows(kit, spec, [-w * 0.25, w * 0.25], body_z - body_d * 0.5, window_y, size, trim)
	# The hitch, a V of steel and a jack, at the left end.
	for turn: float in [-0.35, 0.35]:
		kit.call("box", Vector3(0.08, 0.08, 0.8), Vector3(-w * 0.5 - 0.18, 0.55, body_z + turn * 0.7), STEEL.darkened(0.3), "metal", Basis(Vector3.UP, PI * 0.5 + turn * 0.9))
	kit.call("cylinder", 0.05, 0.55, Vector3(-w * 0.5 - 0.45, 0.28, body_z), STEEL, "metal", 6)
	spec["porch_depth"] = reach - front
	_spigot(spec, w * 0.5, body_z - 0.8, 1.0)


## Dandelion Acres, bigger: a double-wide on a lattice skirt with a stripe, a
## shallow gable, a corrugated carport on posts, a small deck at the door.
static func _double_wide(kit: RefCounted, r: Dictionary, spec: Dictionary, rng: RandomNumberGenerator) -> void:
	var w := float(r["width"])
	var d := float(r["depth"])
	var front := d * 0.5
	var body_d := minf(7.0, d)
	var body_z := front - body_d * 0.5
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var port_w := clampf(w * 0.3, 2.8, 3.6)
	var body_w := w - port_w
	var body_x := -side * port_w * 0.5
	var floor_y := 0.7
	var top := floor_y + 2.5
	var trim: Color = r["trim"]
	spec["stories"] = 1
	kit.call("box", Vector3(body_w - 0.06, floor_y, body_d - 0.06), Vector3(body_x, floor_y * 0.5, body_z), LATTICE, "planks")
	_walls(kit, spec, body_x, body_z, body_w, body_d, floor_y, top, r["wall"], r["wall_surface"])
	kit.call("box", Vector3(body_w + 0.04, 0.3, body_d + 0.04), Vector3(body_x, floor_y + 0.5, body_z), r["accent"], r["wall_surface"])
	_gable(kit, spec, {"cx": body_x, "cz": body_z, "w": body_w, "d": body_d, "top": top, "rise": body_d * RISE["double_wide"], "ox": 0.3, "oz": 0.4, "main": true,
		"roof": r["roof"], "roof_surface": r["roof_surface"], "wall": r["wall"], "wall_surface": r["wall_surface"]})
	# The carport: a pad, four posts, and a corrugated roof off the side wall.
	var inner := side * (w * 0.5 - port_w)
	var port_x := side * (w * 0.5 - port_w * 0.5)
	kit.call("box", Vector3(port_w, 0.04, body_d + 0.2), Vector3(port_x, 0.02, body_z), STOOP, "concrete", Basis.IDENTITY, {"snow": 0.0})
	_slab(kit, Vector3(inner, 2.75, body_z), Vector3(side * (w * 0.5 + 0.1), 2.6, body_z), body_d + 0.4, r["roof"], "corrugated", 0.06)
	for z: float in [body_z - body_d * 0.5 + 0.15, body_z + body_d * 0.5 - 0.15]:
		kit.call("cylinder", 0.06, 2.6, Vector3(side * (w * 0.5 - 0.12), 1.3, z), STEEL, "metal", 6)
	# The door, its deck and steps, and a little awning.
	var door_x := body_x - side * body_w * 0.2
	_door(kit, spec, door_x, floor_y, front, r["door"], trim, 0.95, 2.05)
	kit.call("box", Vector3(2.6, 0.1, 1.6), Vector3(door_x, floor_y - 0.05, front + 0.8), PLYWOOD, "planks")
	var reach := _steps(kit, door_x, front + 1.6, floor_y, 1.0, 0.25, 2, PLYWOOD, "planks")
	_slab(kit, Vector3(door_x, top - 0.25, front), Vector3(door_x, top - 0.45, front + 1.0), 2.0, r["roof"], "corrugated", 0.05)
	var size := Vector2(1.2, 1.0)
	var window_y := floor_y + 1.45
	for t: float in [-0.36, 0.0, 0.36]:
		var x := body_x + body_w * t
		if absf(x - door_x) < 1.4:
			continue
		_window(kit, spec, Vector3(x, window_y, front + 0.02), 0.0, size, trim)
	_side_windows(kit, spec, body_w * 0.5, body_x, body_z, window_y, Vector2(1.0, 0.9), trim)
	_back_windows(kit, spec, [body_x - body_w * 0.3, body_x, body_x + body_w * 0.3], body_z - body_d * 0.5, window_y, size, trim)
	spec["porch_depth"] = reach - front
	_spigot(spec, body_x - side * body_w * 0.5, body_z - body_d * 0.25, -side)


## Birchwood Commons: a new-build colonial (or a one-story ranch version), a
## garage bump-out with a stone front and a paneled double door under its own
## front gable, stone wainscot, and a portico on two columns.
static func _colonial_new(kit: RefCounted, r: Dictionary, spec: Dictionary, rng: RandomNumberGenerator) -> void:
	var w := float(r["width"])
	var d := float(r["depth"])
	var stories := int(r["stories"])
	var front := d * 0.5
	var base := 0.4
	var story := 2.9
	var top := base + story * float(stories)
	var trim: Color = r["trim"]
	var stone: Color = r["accent"]
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var garage_w := clampf(w * 0.4, 3.4, 6.0)
	var main_w := w - garage_w
	var garage_x := side * (w * 0.5 - garage_w * 0.5)
	var main_x := -side * (w * 0.5 - main_w * 0.5)
	_foundation(kit, main_x, 0.0, main_w, d, base)
	_walls(kit, spec, main_x, 0.0, main_w, d, base, top, r["wall"], r["wall_surface"])
	# The garage, stepped forward of the house.
	var bump := 1.2
	var garage_top := 3.0
	var garage_z := bump
	var garage_front := front + bump
	_walls(kit, spec, garage_x, garage_z, garage_w, d, 0.1, garage_top, r["wall"], r["wall_surface"])
	kit.call("box", Vector3(garage_w + 0.04, garage_top, 0.06), Vector3(garage_x, garage_top * 0.5, garage_front + 0.03), stone, "stone")
	var door_w := minf(garage_w - 0.9, 5.0)
	kit.call("box", Vector3(door_w, 2.3, 0.08), Vector3(garage_x, 1.2, garage_front + 0.09), trim, "siding")
	for t: float in [-0.25, 0.0, 0.25]:
		kit.call("box", Vector3(0.04, 2.3, 0.02), Vector3(garage_x + door_w * t, 1.2, garage_front + 0.14), trim.darkened(0.12), "plain")
	kit.call("box", Vector3(door_w + 0.3, 0.14, 0.1), Vector3(garage_x, 2.42, garage_front + 0.1), trim, "planks")
	_gable(kit, spec, {"cx": garage_x, "cz": garage_z, "w": d, "d": garage_w, "top": garage_top, "rise": garage_w * 0.35, "ox": 0.35, "oz": 0.3, "along": "z", "fascia": trim, "blocker": true,
		"roof": r["roof"], "roof_surface": r["roof_surface"], "wall": r["wall"], "wall_surface": r["wall_surface"]})
	_gable(kit, spec, {"cx": main_x, "cz": 0.0, "w": main_w, "d": d, "top": top, "rise": d * RISE["colonial_new"], "ox": 0.4, "oz": 0.6, "main": true, "fascia": trim,
		"roof": r["roof"], "roof_surface": r["roof_surface"], "wall": r["wall"], "wall_surface": r["wall_surface"]})
	# Stone wainscot, the door, and its portico.
	kit.call("box", Vector3(main_w + 0.04, 1.0, 0.06), Vector3(main_x, base + 0.5, front + 0.03), stone, "stone")
	var door_x := main_x
	_door(kit, spec, door_x, base, front, r["door"], trim, 1.0, 2.3)
	kit.call("box", Vector3(2.6, base, 1.6), Vector3(door_x, base * 0.5, front + 0.8), STOOP, "concrete", Basis.IDENTITY, {"snow": 0.0})
	var reach := _steps(kit, door_x, front + 1.6, base, 1.8, 0.4, 1, STOOP)
	for x: float in [door_x - 1.05, door_x + 1.05]:
		kit.call("cylinder", 0.14, 2.7, Vector3(x, base + 1.35, front + 1.4), trim, "stucco", 12)
	kit.call("box", Vector3(2.6, 0.25, 1.7), Vector3(door_x, base + 2.82, front + 0.85), trim, "planks")
	kit.call("prism", Vector3(2.9, 0.7, 1.8), Vector3(door_x, base + 2.95 + 0.35, front + 0.9), r["roof"], r["roof_surface"])
	# The portico reaches the eave of a one-story main roof.
	_blocker(spec, Vector3(door_x, base + 2.69 + 0.48, front + 0.9), Vector3(2.9, 0.96, 1.8))
	# Windows: either side of the portico, a row upstairs, and around.
	var shutter: Color = r["door"].darkened(0.15)
	for t: float in [-0.32, 0.32]:
		var x := main_x + main_w * t
		if absf(x - door_x) < 1.9:
			continue
		_window(kit, spec, Vector3(x, base + 1.6, front + 0.02), 0.0, Vector2(1.2, 1.5), trim)
		_shutters(kit, Vector3(x, base + 1.6, front + 0.02), 0.0, Vector2(1.2, 1.5), shutter)
	if stories > 1:
		for t: float in ([-0.32, 0.0, 0.32] if main_w >= 6.0 else [-0.25, 0.25]):
			var at := Vector3(main_x + main_w * t, base + story + 1.5, front + 0.02)
			_window(kit, spec, at, 0.0, Vector2(1.1, 1.3), trim)
			_shutters(kit, at, 0.0, Vector2(1.1, 1.3), shutter)
	for floor_index: int in stories:
		var y := base + story * float(floor_index) + 1.55
		_side_windows(kit, spec, main_w * 0.5, main_x, 0.0, y, Vector2(1.1, 1.2), trim, [-side])
		_back_windows(kit, spec, [main_x - main_w * 0.25, main_x + main_w * 0.25], -front, y, Vector2(1.1, 1.2), trim)
	_side_windows(kit, spec, garage_w * 0.5, garage_x, garage_z - 1.0, 1.6, Vector2(0.9, 0.8), trim, [side])
	spec["porch_depth"] = maxf(reach - front, bump + 0.35)
	_spigot(spec, -side * w * 0.5, -d * 0.25, -side)


## Birchwood Commons: two offset boxes, the higher one over the garage with
## the main gable, the lower one raised half a story with a picture window.
static func _split_level(kit: RefCounted, r: Dictionary, spec: Dictionary, rng: RandomNumberGenerator) -> void:
	var w := float(r["width"])
	var d := float(r["depth"])
	var front := d * 0.5
	var trim: Color = r["trim"]
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var high_w := clampf(w * 0.55, 4.0, w - 3.0)
	var low_w := w - high_w
	var high_x := side * (w * 0.5 - high_w * 0.5)
	var low_x := -side * (w * 0.5 - low_w * 0.5)
	spec["stories"] = 2
	# The high side: a garage below, rooms above, set back a little.
	var high_d := d - 0.6
	var high_z := -0.3
	var high_front := front - 0.6
	var high_top := 0.2 + 5.4
	_foundation(kit, high_x, high_z, high_w, high_d, 0.2)
	_walls(kit, spec, high_x, high_z, high_w, high_d, 0.2, high_top, r["wall"], r["wall_surface"])
	kit.call("box", Vector3(high_w + 0.04, 2.6, 0.06), Vector3(high_x, 0.2 + 1.3, high_front + 0.03), r["accent"], "stone")
	var door_w := minf(high_w - 0.8, 4.8)
	kit.call("box", Vector3(door_w, 2.2, 0.08), Vector3(high_x, 1.25, high_front + 0.09), trim, "siding")
	kit.call("box", Vector3(door_w + 0.3, 0.14, 0.1), Vector3(high_x, 2.42, high_front + 0.1), trim, "planks")
	_gable(kit, spec, {"cx": high_x, "cz": high_z, "w": high_w, "d": high_d, "top": high_top, "rise": high_d * RISE["split_level"], "ox": 0.4, "oz": 0.6, "main": true, "fascia": trim,
		"roof": r["roof"], "roof_surface": r["roof_surface"], "wall": r["wall"], "wall_surface": r["wall_surface"]})
	for t: float in [-0.25, 0.25]:
		_window(kit, spec, Vector3(high_x + high_w * t, 0.2 + 2.6 + 1.4, high_front + 0.02), 0.0, Vector2(1.2, 1.2), trim)
	# The low side, half a story up.
	var low_base := 0.9
	var low_top := low_base + 2.8
	_foundation(kit, low_x, 0.0, low_w, d, low_base)
	_walls(kit, spec, low_x, 0.0, low_w, d, low_base, low_top, r["wall"], r["wall_surface"])
	_gable(kit, spec, {"cx": low_x, "cz": 0.0, "w": low_w, "d": d, "top": low_top, "rise": d * 0.24, "ox": 0.4, "oz": 0.6, "fascia": trim,
		"roof": r["roof"], "roof_surface": r["roof_surface"], "wall": r["wall"], "wall_surface": r["wall_surface"]})
	var door_x := low_x + side * (low_w * 0.5 - 0.75)
	_door(kit, spec, door_x, low_base, front, r["door"], trim, 0.95, 2.1)
	kit.call("box", Vector3(1.6, low_base, 1.2), Vector3(door_x, low_base * 0.5, front + 0.6), STOOP, "concrete", Basis.IDENTITY, {"snow": 0.0})
	var reach := _steps(kit, door_x, front + 1.2, low_base, 1.3, 0.3, 3, STOOP)
	var picture := maxf(1.0, minf(low_w - 2.2, 2.4))
	_window(kit, spec, Vector3(low_x - side * 0.6, low_base + 1.5, front + 0.02), 0.0, Vector2(picture, 1.4), trim)
	_side_windows(kit, spec, low_w * 0.5, low_x, 0.0, low_base + 1.5, Vector2(1.1, 1.1), trim, [-side])
	for y: float in [1.5, 0.2 + 2.6 + 1.4]:
		_side_windows(kit, spec, high_w * 0.5, high_x, high_z, y, Vector2(1.0, 1.0), trim, [side])
	_back_windows(kit, spec, [low_x], -front, low_base + 1.5, Vector2(1.2, 1.1), trim)
	_back_windows(kit, spec, [high_x], -front, 0.2 + 2.6 + 1.4, Vector2(1.2, 1.1), trim)
	spec["porch_depth"] = reach - front
	_spigot(spec, -side * w * 0.5, -d * 0.25, -side)


## Oak Hollow's one approved model: garage on the left, the door with
## sidelights under a little gable, shutters on every front window, and two
## approved urns. Every Oak Hollow house is this, in an Approved Beige.
static func _hoa_standard(kit: RefCounted, r: Dictionary, spec: Dictionary, _rng: RandomNumberGenerator) -> void:
	var w := float(r["width"])
	var d := float(r["depth"])
	var stories := int(r["stories"])
	var front := d * 0.5
	var base := 0.4
	var story := 2.9
	var top := base + story * float(stories)
	var trim: Color = r["trim"]
	var shutter: Color = r["door"].darkened(0.1)
	_foundation(kit, 0.0, 0.0, w, d, base)
	_walls(kit, spec, 0.0, 0.0, w, d, base, top, r["wall"], r["wall_surface"])
	_gable(kit, spec, {"cx": 0.0, "cz": 0.0, "w": w, "d": d, "top": top, "rise": d * RISE["hoa_standard"], "ox": 0.45, "oz": 0.6, "main": true, "fascia": trim,
		"roof": r["roof"], "roof_surface": r["roof_surface"], "wall": r["wall"], "wall_surface": r["wall_surface"]})
	# The garage, always on the left.
	var garage_x := -w * 0.5 + 1.9
	kit.call("box", Vector3(3.0, 2.35, 0.08), Vector3(garage_x, 1.22, front + 0.19), trim, "siding")
	kit.call("box", Vector3(3.3, 0.14, 0.1), Vector3(garage_x, 2.46, front + 0.2), trim, "planks")
	# The door with sidelights, its hood, the stoop, and the urns.
	var door_x := w * 0.12
	_door(kit, spec, door_x, base, front, r["door"], trim, 1.0, 2.3)
	for side: float in [-1.0, 1.0]:
		kit.call("box", Vector3(0.3, 2.1, 0.04), Vector3(door_x + side * 0.78, base + 1.15, front + 0.03), Color.WHITE, "glass")
		kit.call("box", Vector3(0.08, 2.3, 0.1), Vector3(door_x + side * 0.97, base + 1.15, front + 0.05), trim, "planks")
	_gable(kit, spec, {"cx": door_x, "cz": front + 0.5, "w": 1.0, "d": 2.5, "top": base + 2.75, "rise": 0.5, "ox": 0.05, "oz": 0.1, "along": "z", "fascia": trim, "blocker": true,
		"roof": r["roof"], "roof_surface": r["roof_surface"], "wall": trim, "wall_surface": "planks"})
	kit.call("box", Vector3(2.6, base, 1.3), Vector3(door_x, base * 0.5, front + 0.65), STOOP, "concrete", Basis.IDENTITY, {"snow": 0.0})
	var reach := _steps(kit, door_x, front + 1.3, base, 1.8, 0.4, 1, STOOP)
	for side: float in [-1.0, 1.0]:
		var urn := Vector3(door_x + side * 1.05, base, front + 0.95)
		kit.call("cylinder", 0.22, 0.5, urn + Vector3(0.0, 0.25, 0.0), Color(0.8, 0.77, 0.7), "stone", 10, {"top_radius": 0.32, "params": Vector4(1, 0, 0, 0)})
		kit.call("cylinder", 0.3, 0.42, urn + Vector3(0.0, 0.7, 0.0), BOXWOOD, "foliage", 8, {"top_radius": 0.16})
	# Shuttered windows: one by the door downstairs, a row of three up.
	var size := Vector2(1.2, 1.4)
	var by_door := w * 0.5 - 1.4
	if by_door - door_x > 1.6:
		_window(kit, spec, Vector3(by_door, base + 1.6, front + 0.02), 0.0, size, trim)
		_shutters(kit, Vector3(by_door, base + 1.6, front + 0.02), 0.0, size, shutter)
	if stories > 1:
		for t: float in [-0.3, 0.0, 0.3]:
			var at := Vector3(w * t, base + story + 1.5, front + 0.02)
			_window(kit, spec, at, 0.0, size, trim)
			_shutters(kit, at, 0.0, size, shutter)
	for floor_index: int in stories:
		var y := base + story * float(floor_index) + 1.55
		_side_windows(kit, spec, w * 0.5, 0.0, 0.0, y, Vector2(1.1, 1.2), trim)
		_back_windows(kit, spec, [-w * 0.25, w * 0.25], -front, y, Vector2(1.1, 1.2), trim)
	spec["porch_depth"] = reach - front
	_spigot(spec, w * 0.5, -d * 0.25, 1.0)


## Lakeside: board-and-batten walls, a steep metal roof, a stone chimney up
## one gable end, and an open deck across the front with a railing.
static func _lake_cabin(kit: RefCounted, r: Dictionary, spec: Dictionary, rng: RandomNumberGenerator) -> void:
	var w := float(r["width"])
	var d := float(r["depth"])
	var stories := int(r["stories"])
	var front := d * 0.5
	var base := 0.6
	var story := 2.9
	var top := base + story * float(stories)
	var trim: Color = r["trim"]
	var stone: Color = r["accent"]
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	_foundation(kit, 0.0, 0.0, w, d, base, stone)
	_walls(kit, spec, 0.0, 0.0, w, d, base, top, r["wall"], r["wall_surface"])
	var g := _gable(kit, spec, {"cx": 0.0, "cz": 0.0, "w": w, "d": d, "top": top, "rise": d * RISE["lake_cabin"], "main": true,
		"roof": r["roof"], "roof_surface": r["roof_surface"], "wall": r["wall"], "wall_surface": r["wall_surface"]})
	_chimney(kit, spec, side * (w * 0.5 + 0.08), -d * 0.12, Vector2(0.8, 1.3), 0.0, top + float(g["rise"]) * 0.85, stone, "stone")
	# The deck: boards on posts, a rail with balusters, steps in the middle.
	var deck := 2.0
	kit.call("box", Vector3(w, 0.12, deck), Vector3(0.0, base - 0.06, front + deck * 0.5), DECK, "planks")
	for x: float in [-w * 0.5 + 0.1, 0.0, w * 0.5 - 0.1]:
		kit.call("box", Vector3(0.16, base - 0.12, 0.16), Vector3(x, (base - 0.12) * 0.5, front + deck - 0.1), DECK.darkened(0.2), "planks")
	var rail_z := front + deck - 0.06
	_rail(kit, Vector3(-w * 0.5 + 0.05, base, rail_z), Vector3(-0.9, base, rail_z), 0.9, DECK.darkened(0.1), 0.45)
	_rail(kit, Vector3(0.9, base, rail_z), Vector3(w * 0.5 - 0.05, base, rail_z), 0.9, DECK.darkened(0.1), 0.45)
	for x: float in [-w * 0.5 + 0.05, w * 0.5 - 0.05]:
		_rail(kit, Vector3(x, base, front + 0.05), Vector3(x, base, rail_z), 0.9, DECK.darkened(0.1), 0.45)
	var reach := _steps(kit, 0.0, front + deck, base, 1.6, 0.28, 2, DECK, "planks")
	_door(kit, spec, 0.0, base, front, r["door"], trim)
	for floor_index: int in stories:
		var y := base + story * float(floor_index) + 1.55
		var size := Vector2(1.6, 1.5) if floor_index == 0 else Vector2(1.2, 1.2)
		for x: float in [-w * 0.28, w * 0.28]:
			_window(kit, spec, Vector3(x, y, front + 0.02), 0.0, size, trim)
		_side_windows(kit, spec, w * 0.5, 0.0, d * 0.25, y, Vector2(1.0, 1.0), trim, [-side])
		# Big windows on the back: the lake is back there.
		_back_windows(kit, spec, [-w * 0.24, w * 0.24], -front, y, Vector2(2.0, 1.6), trim)
	spec["porch_depth"] = reach - front
	_spigot(spec, -side * w * 0.5, -d * 0.25, -side)


## Lakeside two-story: a metal roof, a glass cross-gable to the street and
## big glass on the lake side, and a deck that wraps the front and one side.
static func _lake_house(kit: RefCounted, r: Dictionary, spec: Dictionary, rng: RandomNumberGenerator) -> void:
	var w := float(r["width"])
	var d := float(r["depth"])
	var front := d * 0.5
	var base := 0.6
	var story := 3.0
	var top := base + story * 2.0
	var trim: Color = r["trim"]
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var main_w := w - 1.8
	var main_x := -side * 0.9
	spec["stories"] = 2
	_foundation(kit, main_x, 0.0, main_w, d, base, r["accent"])
	_walls(kit, spec, main_x, 0.0, main_w, d, base, top, r["wall"], r["wall_surface"])
	var g := _gable(kit, spec, {"cx": main_x, "cz": 0.0, "w": main_w, "d": d, "top": top, "rise": d * RISE["lake_house"], "main": true,
		"roof": r["roof"], "roof_surface": r["roof_surface"], "wall": r["wall"], "wall_surface": r["wall_surface"]})
	# The glass cross-gable, a little proud of the front.
	var glass_w := clampf(main_w * 0.38, 3.0, 4.6)
	var glass_x := main_x
	var proud := 0.6
	_walls(kit, spec, glass_x, front + proud * 0.5, glass_w, proud, base, top, r["wall"], r["wall_surface"])
	_gable(kit, spec, {"cx": glass_x, "cz": (front + proud) * 0.5, "w": front + proud, "d": glass_w, "top": top, "rise": minf(glass_w * 0.75, float(g["rise"]) * 0.9), "ox": 0.4, "oz": 0.3, "along": "z", "blocker": true,
		"gable_surface": "glass", "roof": r["roof"], "roof_surface": r["roof_surface"], "wall": r["wall"], "wall_surface": r["wall_surface"]})
	var glass_front := front + proud
	kit.call("box", Vector3(glass_w - 0.5, story * 2.0 - 0.6, 0.04), Vector3(glass_x, base + story, glass_front + 0.02), Color.WHITE, "glass")
	for t: float in [-0.5, -0.17, 0.17, 0.5]:
		kit.call("box", Vector3(0.08, story * 2.0 - 0.6, 0.08), Vector3(glass_x + (glass_w - 0.5) * t, base + story, glass_front + 0.05), MULLION, "metal")
	kit.call("box", Vector3(glass_w - 0.5, 0.1, 0.1), Vector3(glass_x, base + story, glass_front + 0.06), MULLION, "metal")
	(spec["windows"] as Array).append([Vector3(glass_x, base + 1.4, glass_front + 0.04), Vector3.BACK, Vector2(glass_w - 0.5, 2.2)])
	# The wraparound deck, its rail, and steps at the far end.
	var deck := 2.2
	kit.call("box", Vector3(w, 0.12, deck), Vector3(0.0, base - 0.06, front + deck * 0.5), DECK, "planks")
	var side_in := main_x + side * main_w * 0.5
	var side_out := side * (w * 0.5 + 0.4)
	kit.call("box", Vector3(absf(side_out - side_in), 0.12, d - 0.5), Vector3((side_in + side_out) * 0.5, base - 0.06, 0.25), DECK, "planks")
	var steps_x := -side * (w * 0.5 - 1.0)
	var rail_z := front + deck - 0.06
	var rail := DECK.darkened(0.1)
	_rail(kit, Vector3(-side * (w * 0.5 - 0.05), base, rail_z), Vector3(steps_x + side * 0.75, base, rail_z), 0.95, rail, 0.5)
	_rail(kit, Vector3(steps_x + side * 0.75, base, rail_z), Vector3(side_out - side * 0.05, base, rail_z), 0.95, rail, 0.5)
	_rail(kit, Vector3(side_out - side * 0.05, base, rail_z), Vector3(side_out - side * 0.05, base, -d * 0.5 + 0.55), 0.95, rail, 0.5)
	for corner: Vector2 in [Vector2(-side * (w * 0.5 - 0.1), rail_z), Vector2(side_out - side * 0.1, rail_z), Vector2(side_out - side * 0.1, -d * 0.5 + 0.6)]:
		kit.call("box", Vector3(0.16, base - 0.12, 0.16), Vector3(corner.x, (base - 0.12) * 0.5, corner.y), rail.darkened(0.2), "planks")
	var reach := _steps(kit, steps_x, front + deck, base, 1.3, 0.2, 2, DECK, "planks")
	# The door beside the glass, or in it when there is no room.
	var door_x := glass_x + side * (glass_w * 0.5 + 0.9)
	if absf(door_x - main_x) + 0.6 > main_w * 0.5:
		_door(kit, spec, glass_x, base, glass_front, MULLION, trim, 1.0, 2.2)
	else:
		_door(kit, spec, door_x, base, front, r["door"], trim)
	var upper_y := base + story + 1.5
	for x: float in [main_x - (glass_w * 0.5 + (main_w * 0.5 - glass_w * 0.5) * 0.5), main_x + (glass_w * 0.5 + (main_w * 0.5 - glass_w * 0.5) * 0.5)]:
		if main_w * 0.5 - glass_w * 0.5 > 1.4:
			_window(kit, spec, Vector3(x, upper_y, front + 0.02), 0.0, Vector2(1.1, 1.2), trim)
	for floor_index: int in 2:
		var y := base + story * float(floor_index) + 1.55
		_side_windows(kit, spec, main_w * 0.5, main_x, 0.0, y, Vector2(1.2, 1.2), trim)
		_back_windows(kit, spec, [main_x - main_w * 0.25, main_x + main_w * 0.25], -front, y, Vector2(2.2, 2.0), trim)
	spec["porch_depth"] = reach - front
	_spigot(spec, main_x - side * main_w * 0.5, -d * 0.25, -side)


## Lakeside neighbors only: a roof down to the ground, glass in both gables,
## a deck out front.
static func _a_frame(kit: RefCounted, r: Dictionary, spec: Dictionary, _rng: RandomNumberGenerator) -> void:
	var w := float(r["width"])
	var d := float(r["depth"])
	var front := d * 0.5
	var frame_w := minf(w, 9.0)
	var base := 0.5
	var floor_y := base + 0.3
	var height := frame_w * 0.95
	var trim: Color = r["trim"]
	_foundation(kit, 0.0, 0.0, frame_w - 0.4, d, floor_y, r["accent"])
	_gable(kit, spec, {"cx": 0.0, "cz": 0.0, "w": d, "d": frame_w, "top": floor_y, "rise": height, "ox": 0.55, "oz": 0.25, "along": "z",
		"gable_surface": "glass", "roof": r["roof"], "roof_surface": r["roof_surface"], "wall": r["wall"], "wall_surface": r["wall_surface"]})
	kit.call("box", Vector3(0.1, height * 0.85, 0.1), Vector3(0.0, floor_y + height * 0.42, front + 0.05), MULLION, "metal")
	for level: float in [2.6, 5.2]:
		if level < height - 0.8:
			kit.call("box", Vector3(frame_w * (1.0 - level / height) - 0.3, 0.1, 0.1), Vector3(0.0, floor_y + level, front + 0.05), MULLION, "metal")
	kit.call("box", Vector3(frame_w * 0.8, 0.12, 2.0), Vector3(0.0, floor_y - 0.06, front + 1.0), DECK, "planks")
	var reach := _steps(kit, 0.0, front + 2.0, floor_y, 1.4, 0.25, 2, DECK, "planks")
	_door(kit, spec, 0.0, floor_y, front, MULLION, trim, 1.0, 2.2)
	(spec["windows"] as Array).append([Vector3(0.0, floor_y + 1.4, front + 0.02), Vector3.BACK, Vector2(frame_w * 0.6, 2.4)])
	spec["roof"] = {"kind": "a_frame", "center": Vector3(0.0, floor_y, 0.0), "width": d + 1.1, "half_run": frame_w * 0.5 + 0.25, "rise": height, "top": floor_y}
	spec["roof_edge_y"] = floor_y
	spec["solids"] = [[Vector3(0.0, (floor_y + height * 0.6) * 0.5, 0.0), Vector3(frame_w * 0.6, floor_y + height * 0.6, d)]]
	spec["porch_depth"] = reach - front
	spec["spigot"] = [Vector3(frame_w * 0.3, 0.5, front + 0.02), Vector3.BACK]


## Mansion Hill: a tall central block whose gable is the climbable roof, a
## two-story portico of four columns under a pediment, lower wings with hip
## roofs, keystone windows, quoins, and a stone terrace with a balustrade.
static func _estate(kit: RefCounted, r: Dictionary, spec: Dictionary, _rng: RandomNumberGenerator) -> void:
	var w := float(r["width"])
	var d := float(r["depth"])
	var front := d * 0.5
	var base := 0.8
	var story := 3.4
	var top := base + story * 2.0
	var trim: Color = r["trim"]
	var stone: Color = r["accent"]
	var ashlar := {"params": Vector4(1, 0, 0, 0)}
	var core_w := clampf(w * 0.5, 5.0, w - 3.0)
	var wing_w := (w - core_w) * 0.5
	spec["stories"] = 2
	_foundation(kit, 0.0, 0.0, core_w, d, base, stone)
	_walls(kit, spec, 0.0, 0.0, core_w, d, base, top, r["wall"], r["wall_surface"])
	var g := _gable(kit, spec, {"cx": 0.0, "cz": 0.0, "w": core_w, "d": d, "top": top, "rise": d * RISE["estate"], "main": true, "fascia": trim,
		"roof": r["roof"], "roof_surface": r["roof_surface"], "wall": r["wall"], "wall_surface": r["wall_surface"]})
	for x: float in [-core_w * 0.28, core_w * 0.28]:
		_dormer(kit, spec, r, x, 0.0, g, 1.7)
	for x: float in [-(core_w * 0.5 - 0.6), core_w * 0.5 - 0.6]:
		_chimney(kit, spec, x, 0.0, Vector2(0.9, 0.9), top + float(g["rise"]) * 0.5, top + float(g["rise"]) + 1.0, r["wall"], r["wall_surface"])
	# Quoins up the core's front corners.
	for corner: float in [-1.0, 1.0]:
		for index: int in 18:
			var long := index % 2 == 0
			kit.call("box", Vector3(0.5 if long else 0.32, 0.34, 0.06), Vector3(corner * (core_w * 0.5 - (0.25 if long else 0.16)), base + 0.2 + float(index) * 0.36, front + 0.03), stone, "stone", Basis.IDENTITY, ashlar)
	# The wings, set back, with hip roofs.
	var wing_d := d * 0.8
	var wing_z := -d * 0.5 + wing_d * 0.5
	var wing_top := base + 4.0
	var wing_front := wing_z + wing_d * 0.5
	for side: float in [-1.0, 1.0]:
		var wing_x := side * (core_w * 0.5 + wing_w * 0.5)
		_foundation(kit, wing_x, wing_z, wing_w, wing_d, base, stone)
		_walls(kit, spec, wing_x, wing_z, wing_w, wing_d, base, wing_top, r["wall"], r["wall_surface"])
		var hip_rise := minf(wing_w, wing_d) * 0.35
		kit.call("hip", Vector3(wing_w + 0.5, 0.0, wing_d + 0.5), Vector3(wing_x, wing_top, wing_z), hip_rise, r["roof"], r["roof_surface"])
		kit.call("box", Vector3(wing_w + 0.5, 0.18, wing_d + 0.5), Vector3(wing_x, wing_top - 0.09, wing_z), trim, "stucco", Basis.IDENTITY, {"snow": 0.0})
		(spec["roof_solids"] as Array).append([Vector3(wing_x, wing_top + hip_rise * 0.2, wing_z), Vector3(wing_w, hip_rise * 0.4, wing_d)])
		(spec["eaves"] as Array).append([Vector3(wing_x - wing_w * 0.5 - 0.25, wing_top, wing_front + 0.25), Vector3(wing_x + wing_w * 0.5 + 0.25, wing_top, wing_front + 0.25)])
		var tall := Vector2(1.1, 2.1)
		var count := 2 if wing_w >= 3.2 else 1
		for index: int in count:
			var x := wing_x + (0.0 if count == 1 else (float(index) - 0.5) * wing_w * 0.5)
			var at := Vector3(x, base + 1.7, wing_front + 0.02)
			_window(kit, spec, at, 0.0, tall, trim)
			_keystone(kit, at, tall, stone)
		_side_windows(kit, spec, wing_w * 0.5, wing_x, wing_z, base + 1.7, tall, trim, [side])
		_back_windows(kit, spec, [wing_x], -front, base + 1.7, tall, trim)
	# The terrace, its balustrade, and wide steps.
	var terrace_w := core_w + 1.0
	kit.call("box", Vector3(terrace_w, base, 2.0), Vector3(0.0, base * 0.5, front + 1.0), stone, "stone", Basis.IDENTITY, ashlar)
	var reach := _steps(kit, 0.0, front + 2.0, base, 3.0, 0.2, 3, stone, "stone")
	var edge := front + 1.88
	_balustrade(kit, Vector3(-terrace_w * 0.5 + 0.15, base, edge), Vector3(-1.65, base, edge), stone.lightened(0.05))
	_balustrade(kit, Vector3(1.65, base, edge), Vector3(terrace_w * 0.5 - 0.15, base, edge), stone.lightened(0.05))
	# The portico: four columns, an entablature, and a pediment buried in the roof.
	var spacing := minf(1.5, (core_w - 1.4) / 3.0)
	for index: int in 4:
		_column(kit, Vector3((float(index) - 1.5) * spacing, base, front + 1.55), story * 2.0 - 0.8, 0.26, trim)
	# Just past the outer capitals, so even a narrow core keeps some front eave
	# (and gutter) either side of the pediment.
	var span := spacing * 3.0 + 0.8
	kit.call("box", Vector3(span, 0.6, 1.9), Vector3(0.0, top - 0.8 + 0.3, front + 0.95), trim, "stucco")
	kit.call("box", Vector3(span + 0.3, 0.12, 2.1), Vector3(0.0, top - 0.14, front + 1.0), stone, "stone", Basis.IDENTITY, ashlar)
	_blocker(spec, Vector3(0.0, top - 0.8 + 0.36, front + 1.0), Vector3(span + 0.3, 0.72, 2.1))
	_gable(kit, spec, {"cx": 0.0, "cz": front + 0.3, "w": 3.6, "d": span, "top": top - 0.08, "rise": 1.3, "ox": 0.12, "oz": 0.1, "along": "z", "fascia": stone, "blocker": true,
		"roof": r["roof"], "roof_surface": r["roof_surface"], "wall": trim, "wall_surface": "stucco"})
	# The door: double, tall, with a fanlight; keystone windows around it.
	_door(kit, spec, 0.0, base, front, r["door"], trim, 1.6, 3.0)
	kit.call("box", Vector3(1.6, 0.55, 0.04), Vector3(0.0, base + 3.45, front + 0.03), Color.WHITE, "glass")
	var size := Vector2(1.2, 2.0)
	for floor_index: int in 2:
		var y := base + story * float(floor_index) + 1.75
		var xs: Array = [-core_w * 0.33, core_w * 0.33]
		if floor_index == 1:
			xs.append(0.0)
		for x: float in xs:
			var at := Vector3(x, y, front + 0.02)
			_window(kit, spec, at, 0.0, size, trim)
			_keystone(kit, at, size, stone)
		_back_windows(kit, spec, [-core_w * 0.25, core_w * 0.25], -front, y, size, trim)
	spec["porch_depth"] = reach - front
	_spigot(spec, -w * 0.5, wing_z, -1.0)


## Mansion Hill neighbors only: flat-roofed cubes, one cantilevered over the
## other, walls of glass, a wood panel, a pivot door.
static func _modern_glass(kit: RefCounted, r: Dictionary, spec: Dictionary, rng: RandomNumberGenerator) -> void:
	var w := float(r["width"])
	var d := float(r["depth"])
	var front := d * 0.5
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var white := Color(0.95, 0.95, 0.93)
	var wood := Color(0.6, 0.42, 0.28)
	spec["stories"] = 2
	_walls(kit, spec, 0.0, 0.0, w, d, 0.15, 3.4, white, "stucco")
	kit.call("box", Vector3(w + 1.0, 0.25, d + 0.6), Vector3(0.0, 3.4 + 0.125, 0.0), MULLION.lightened(0.15), "concrete")
	var upper_w := w * 0.65
	var upper_d := d * 0.8
	var upper_x := side * (w - upper_w) * 0.5
	var upper_z := front - upper_d * 0.5 + 0.0
	_walls(kit, spec, upper_x, upper_z, upper_w, upper_d, 3.65, 6.6, white, "stucco")
	kit.call("box", Vector3(upper_w + 1.0, 0.25, upper_d + 0.6), Vector3(upper_x, 6.6 + 0.125, upper_z), MULLION.lightened(0.15), "concrete")
	var lower_glass := w * 0.55
	var glass_x := -side * (w * 0.5 - lower_glass * 0.5 - 0.3)
	kit.call("box", Vector3(lower_glass, 2.6, 0.04), Vector3(glass_x, 1.6, front + 0.02), Color.WHITE, "glass")
	kit.call("box", Vector3(upper_w - 0.6, 2.2, 0.04), Vector3(upper_x, 5.1, upper_z + upper_d * 0.5 + 0.02), Color.WHITE, "glass")
	for t: float in [-0.25, 0.25]:
		kit.call("box", Vector3(0.06, 2.6, 0.06), Vector3(glass_x + lower_glass * t, 1.6, front + 0.05), MULLION, "metal")
		kit.call("box", Vector3(0.06, 2.2, 0.06), Vector3(upper_x + (upper_w - 0.6) * t, 5.1, upper_z + upper_d * 0.5 + 0.05), MULLION, "metal")
	var panel_x := side * (w * 0.5 - w * 0.14)
	kit.call("box", Vector3(w * 0.26, 3.1, 0.06), Vector3(panel_x, 1.75, front + 0.03), wood, "planks")
	_door(kit, spec, panel_x - side * (w * 0.13 + 0.8), 0.15, front, wood.darkened(0.2), MULLION, 1.2, 2.6)
	(spec["windows"] as Array).append([Vector3(glass_x, 1.6, front + 0.04), Vector3.BACK, Vector2(lower_glass, 2.6)])
	spec["roof"] = {"kind": "flat", "center": Vector3(0.0, 3.4, 0.0), "width": w + 1.0, "half_run": d * 0.5 + 0.3, "rise": 0.0, "top": 3.4}
	spec["roof_edge_y"] = 3.4
	spec["eaves"] = [[Vector3(-w * 0.5 - 0.5, 3.4, front + 0.3), Vector3(w * 0.5 + 0.5, 3.4, front + 0.3)]]
	spec["porch_depth"] = 0.3
	_spigot(spec, -side * w * 0.5, -d * 0.25, -side)


## The countryside: white siding, a steep roof, a dormer on two stories, and a
## porch that wraps the front and one side.
static func _farmhouse(kit: RefCounted, r: Dictionary, spec: Dictionary, rng: RandomNumberGenerator) -> void:
	var w := float(r["width"])
	var d := float(r["depth"])
	var stories := int(r["stories"])
	var front := d * 0.5
	var base := 0.6
	var story := 3.0
	var top := base + story * float(stories)
	var trim: Color = r["trim"]
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var main_w := w - 2.0
	var main_x := -side * 1.0
	_foundation(kit, main_x, 0.0, main_w, d, base)
	_walls(kit, spec, main_x, 0.0, main_w, d, base, top, r["wall"], r["wall_surface"])
	var g := _gable(kit, spec, {"cx": main_x, "cz": 0.0, "w": main_w, "d": d, "top": top, "rise": d * RISE["farmhouse"], "ox": 0.45, "main": true, "fascia": trim,
		"roof": r["roof"], "roof_surface": r["roof_surface"], "wall": r["wall"], "wall_surface": r["wall_surface"]})
	if stories > 1:
		_dormer(kit, spec, r, main_x, 0.0, g, clampf(main_w * 0.3, 2.0, 2.8))
	# The wraparound porch: decks, its roof, posts, rails.
	var porch := 2.2
	var porch_top := base + story - 0.25
	var porch_low := porch_top - 0.5
	kit.call("box", Vector3(w, base, porch), Vector3(0.0, base * 0.5, front + porch * 0.5), DECK, "planks", Basis.IDENTITY, {"snow": 0.0})
	var side_in := main_x + side * main_w * 0.5
	var side_out := side * (w * 0.5 + 0.1)
	kit.call("box", Vector3(absf(side_out - side_in), base, d - 0.6), Vector3((side_in + side_out) * 0.5, base * 0.5, 0.3), DECK, "planks", Basis.IDENTITY, {"snow": 0.0})
	_slab(kit, Vector3(0.0, porch_top, front), Vector3(0.0, porch_low, front + porch + 0.1), w + 0.2, r["roof"], r["roof_surface"], 0.12)
	_slab(kit, Vector3(side_in, porch_top, 0.3), Vector3(side * (w * 0.5 + 0.25), porch_low, 0.3), d - 0.6, r["roof"], r["roof_surface"], 0.12)
	var post_h := porch_low - base - 0.06
	var post_z := front + porch - 0.15
	var posts := maxi(3, int(w / 2.4) + 1)
	for index: int in posts:
		var x := -w * 0.5 + 0.15 + (w - 0.3) * float(index) / float(posts - 1)
		kit.call("box", Vector3(0.18, post_h, 0.18), Vector3(x, base + post_h * 0.5, post_z), trim, "planks")
	for z: float in [-d * 0.5 + 0.75, 0.0]:
		kit.call("box", Vector3(0.18, post_h, 0.18), Vector3(side * (w * 0.5 - 0.05), base + post_h * 0.5, z), trim, "planks")
	_rail(kit, Vector3(-w * 0.5 + 0.15, base, post_z), Vector3(-0.85, base, post_z), 0.85, trim, 0.4)
	_rail(kit, Vector3(0.85, base, post_z), Vector3(w * 0.5 - 0.15, base, post_z), 0.85, trim, 0.4)
	_rail(kit, Vector3(side * (w * 0.5 - 0.05), base, -d * 0.5 + 0.75), Vector3(side * (w * 0.5 - 0.05), base, post_z), 0.85, trim, 0.4)
	var reach := _steps(kit, 0.0, front + porch, base, 1.6, 0.2, 2, DECK, "planks")
	_door(kit, spec, main_x, base, front, r["door"], trim)
	var size := Vector2(1.1, 1.7)
	for floor_index: int in stories:
		var y := base + story * float(floor_index) + 1.65
		for t: float in [-0.3, 0.3]:
			_window(kit, spec, Vector3(main_x + main_w * t, y, front + 0.02), 0.0, size, trim)
		_side_windows(kit, spec, main_w * 0.5, main_x, 0.0, y, size, trim)
		_back_windows(kit, spec, [main_x - main_w * 0.25, main_x + main_w * 0.25], -front, y, size, trim)
	_chimney(kit, spec, main_x - side * (main_w * 0.5 - 0.7), -d * 0.1, Vector2(0.8, 0.8), top - 0.2, top + float(g["rise"]) + 0.6, BRICK, "brick")
	spec["porch_depth"] = reach - front
	_spigot(spec, main_x - side * main_w * 0.5, -d * 0.25, -side)
