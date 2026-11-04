extends RefCounted

## Authority: local, cosmetic, the same on every peer (fixed seeds and TownMap
## only; solids() is data, built by levels/town/town_colliders.gd). The Gutterford
## town line (docs/GAME.md "The edge of town"): where the town stops, so driving
## off across the fields ends at something that belongs there instead of grass
## to the horizon (crew playtest 1, lagduo-8).
##   - A farm hedgerow all the way round Constants.TOWN_LINE_RECT: a thick lumpy
##     hedge with field trees standing out of it, a split-rail fence along its
##     inside, and a solid wall whose inside face stands just in front of the
##     fence, so Chefty and anyone on foot stop at the rails like at any hedge
##     (never through them). The wall breaks at each farm gate, which is solid
##     itself, and a bush each side closes the hedge on the gate's posts.
##   - Out past each Depot Road barricade, the outskirts' Depot Road farms
##     (levels/town/outskirts.gd fields() and row_trees(): plowed, stubble and
##     hay either side of the track, a windbreak across), so the view past a
##     closure is farmland running into the haze, not empty grass.
##   - Every paved road that runs out toward it (Depot Road both ways, Main Street
##     both ways) ends at a ROAD CLOSED barricade: sawhorses, barrels, an amber
##     lamp and a sign with the town's excuse, then a gravel track on to a shut
##     farm gate in the hedge, and on out of sight beyond it.
##   - Past the hedge, low wooded hills all round, which the haze takes, so the
##     ground's edge is never seen from inside.
## Draw calls: one mesh per Constants.TOWN_LINE_SEGMENT of hedge, one per hill
## stretch, the fence in a few PropBatch chunks, one mesh and a few labels per
## closure.

const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const _P = preload("res://props/prop_parts.gd")
const _PropBatch = preload("res://props/prop_batch.gd")
const _LowPoly = preload("res://props/low_poly.gd")
const _BuildQueue = preload("res://levels/build_queue.gd")
const _Strings = preload("res://ui/strings.gd")

const SEED: int = 6151
const HEDGE: Array[Color] = [Color(0.27, 0.38, 0.19), Color(0.33, 0.42, 0.2), Color(0.24, 0.33, 0.17), Color(0.4, 0.42, 0.2)]
const CROWNS: Array[Color] = [Color(0.86, 0.46, 0.14), Color(0.72, 0.26, 0.13), Color(0.88, 0.68, 0.22), Color(0.36, 0.46, 0.22), Color(0.6, 0.36, 0.16)]
const BARK := Color(0.33, 0.25, 0.18)
const HILL: Array[Color] = [Color(0.25, 0.34, 0.22), Color(0.3, 0.37, 0.22), Color(0.22, 0.3, 0.24)]
const GRAVEL := Color(0.5, 0.46, 0.4)
const ORANGE := Color(0.95, 0.45, 0.1)
const WHITE := Color(0.95, 0.94, 0.9)
const GATE := Color(0.78, 0.72, 0.6)
const AMBER := Color(1.0, 0.62, 0.15)
## Fence runs this long (PropBatch groups by size), standing this far inside the
## line: a hand behind the wall's inside face, so nothing reaches the rails (a
## bumper sticks out past Chefty's collision shape a little).
const RUN: float = 6.0
const FENCE_IN: float = Constants.TOWN_LINE_WALL_INSIDE - 0.4
## A gate's posts stand this far out from its bars' ends; the wall stops at
## the posts and the gate's own solid fills the gap.
const POST_OUT: float = 0.2
## The bushes that close the hedge on each gate post: their reach along the line.
const GATE_BUSH: float = 2.6


# ---------------------------------------------------------------- the layout (data)

## The four sides as [from, to] in (x, z), clockwise from the north-west corner.
static func sides() -> Array:
	var rect := Constants.TOWN_LINE_RECT
	var nw := rect.position
	var ne := Vector2(rect.end.x, rect.position.y)
	var se := rect.end
	var sw := Vector2(rect.position.x, rect.end.y)
	return [[nw, ne], [ne, se], [se, sw], [sw, nw]]


## The roads that run out toward the line and are closed: {key, end (the paved
## road's last point), out (unit, toward the line), half (half the road and its
## sidewalks), gate (where the track meets the hedge)}.
static func closures() -> Array:
	var rect := Constants.TOWN_LINE_RECT
	var depot_half := TownMap.STREET_WIDTH * 0.5 + TownMap.SIDEWALK
	var main_half := TownMap.MAIN_WIDTH * 0.5 + TownMap.SIDEWALK
	var out: Array = []
	for entry: Array in [
		["depot_n", Vector3(TownMap.DEPOT_X, 0.0, -Constants.TOWN_LINE_DEPOT_ASPHALT_END), -1.0, depot_half],
		["depot_s", Vector3(TownMap.DEPOT_X, 0.0, Constants.TOWN_LINE_DEPOT_ASPHALT_END), 1.0, depot_half],
		["main_n", Vector3(TownMap.MAIN_X, 0.0, TownMap.MAIN_Z.x), -1.0, main_half],
		["main_s", Vector3(TownMap.MAIN_X, 0.0, TownMap.MAIN_Z.y), 1.0, main_half],
	]:
		var end: Vector3 = entry[1]
		var sign := float(entry[2])
		var line_z := rect.position.y if sign < 0.0 else rect.end.y
		out.append({"key": str(entry[0]), "end": end, "out": Vector3(0.0, 0.0, sign), "half": float(entry[3]), "gate": Vector3(end.x, 0.0, line_z)})
	return out


## Where a closure's barricade stands (its middle at the ground).
static func barricade_at(closure: Dictionary) -> Vector3:
	return (closure["end"] as Vector3) + (closure["out"] as Vector3) * Constants.TOWN_LINE_BARRICADE_OUT


## Everything here that collides for everyone, world space: [["box", center,
## size, yaw]]. The hedge's walls (overlapping at the corners, their inside face
## at the fence, broken at each gate) and each shut gate. Chefty never reaches
## them at speed: the hedge's band catches it first (VehicleSim.town_edge,
## fx-yard). The barricades are foot_solids().
static func solids() -> Array:
	var out: Array = []
	var high := Constants.TOWN_LINE_WALL_HEIGHT
	var deep := Constants.TOWN_LINE_WALL_DEPTH
	var center := Constants.TOWN_LINE_RECT.get_center()
	var gate_reach := Constants.TOWN_LINE_GATE_HALF + POST_OUT
	for side: Array in sides():
		var a: Vector2 = side[0]
		var b: Vector2 = side[1]
		var along := (b - a).normalized()
		var along_x := absf(along.x) > absf(along.y)
		var inward := Vector2(-along.y, along.x)
		if inward.dot(center - (a + b) * 0.5) < 0.0:
			inward = -inward
		# The wall's middle stands off the line toward town by this much.
		var shift := inward * (Constants.TOWN_LINE_WALL_INSIDE - deep * 0.5)
		# The stretches between gates, as distances along a to b (past each corner by deep).
		var cuts: Array[float] = [-deep]
		for closure: Dictionary in closures():
			var gate: Vector3 = closure["gate"]
			var flat := Vector2(gate.x, gate.z)
			var s := (flat - a).dot(along)
			if absf((flat - a).dot(inward)) < 0.5 and s > 0.0 and s < a.distance_to(b):
				cuts.append(s - gate_reach)
				cuts.append(s + gate_reach)
		cuts.sort()
		cuts.append(a.distance_to(b) + deep)
		for index: int in range(0, cuts.size(), 2):
			var from := cuts[index]
			var to := cuts[index + 1]
			var middle := a + along * ((from + to) * 0.5) + shift
			var size := Vector3(to - from, high, deep) if along_x else Vector3(deep, high, to - from)
			out.append(["box", Vector3(middle.x, high * 0.5, middle.y), size, 0.0])
	for closure: Dictionary in closures():
		var gate: Vector3 = closure["gate"]
		out.append(["box", gate + Vector3(0.0, 0.9, 0.0), Vector3(gate_reach * 2.0, 1.8, 0.4), 0.0])
	return out


## fx-yard: the closed roads' barricades, solid to people only (Constants.
## PAD_WALL_LAYER; Chefty drives through them and they tip): [[key, center, size,
## yaw]], one per sawhorse (as wide as its share of the road, so the row has no
## gap to squeeze through) and one per barrel. The key names the drawn piece
## (_closure), which turns its own off while it lies knocked over.
static func foot_solids() -> Array:
	var out: Array = []
	for closure: Dictionary in closures():
		var horses := sawhorses(closure)
		var share := float(closure["half"]) * 2.0 / float(horses.size())
		for index: int in horses.size():
			var horse: Dictionary = horses[index]
			out.append([piece_key(closure, "horse", index), (horse["at"] as Vector3) + Vector3(0.0, 0.6, 0.0), Vector3(share + 0.5, 1.2, 0.8), float(horse["yaw"])])
		var spots := barrels(closure)
		for index: int in spots.size():
			out.append([piece_key(closure, "barrel", index), spots[index] + Vector3(0.0, 0.5, 0.0), Vector3(0.7, 1.0, 0.7), 0.0])
	return out


## The name a barricade piece goes by in foot_solids() and the drawing.
static func piece_key(closure: Dictionary, kind: String, index: int) -> String:
	return "%s_%s%d" % [closure["key"], kind, index]


## The barricade's own frame, world space: +X across the road, +Z back toward
## town (it faces in), at the middle of the road at the ground.
static func barricade_frame(closure: Dictionary) -> Transform3D:
	var out: Vector3 = closure["out"]
	return Transform3D(Basis(Vector3.UP, 0.0 if out.z < 0.0 else PI), barricade_at(closure))


## A closed road's sawhorses across it, a little ragged: [{at (world, the
## feet's middle at the ground), yaw, width}]. The same on every peer.
static func sawhorses(closure: Dictionary) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([SEED, str(closure["key"]), "sawhorses"])
	var frame := barricade_frame(closure)
	var half := float(closure["half"])
	var width := half * 2.0
	var count := maxi(3, int(width / 3.4))
	var out: Array = []
	for index: int in count:
		var x := -half + width * (float(index) + 0.5) / float(count) + rng.randf_range(-0.2, 0.2)
		var turn := rng.randf_range(-0.08, 0.08)
		var foot := Vector3(x, 0.0, rng.randf_range(-0.15, 0.15))
		out.append({"at": frame * foot, "yaw": frame.basis.get_euler().y + turn, "width": minf(2.6, width / float(count) - 0.3)})
	return out


## Where a closure's two barrels stand (world, at the ground), each side of its
## sawhorses, a little toward town.
static func barrels(closure: Dictionary) -> Array[Vector3]:
	var at := barricade_at(closure)
	var out_dir: Vector3 = closure["out"]
	var across := Vector3(1.0, 0.0, 0.0)
	var half := float(closure["half"])
	var spots: Array[Vector3] = []
	for side: float in [-1.0, 1.0]:
		spots.append(at + across * side * (half + 0.8) - out_dir * 0.3)
	return spots


## Whether a point (x, z) is inside the line with this much room to spare.
static func inside(point: Vector2, margin: float = 0.0) -> bool:
	return Constants.TOWN_LINE_RECT.grow(-margin).has_point(point)


# ---------------------------------------------------------------- building (visuals)

## Queues the line's pieces on root's BuildQueue (each a step).
static func dress(root: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "TownLine"
	root.add_child(holder)
	var gaps: Array[Vector2] = []
	for closure: Dictionary in closures():
		var gate: Vector3 = closure["gate"]
		gaps.append(Vector2(gate.x, gate.z))
	var index := 0
	for side: Array in sides():
		var a: Vector2 = side[0]
		var b: Vector2 = side[1]
		var count := maxi(1, ceili(a.distance_to(b) / Constants.TOWN_LINE_SEGMENT))
		for piece: int in count:
			var from := a.lerp(b, float(piece) / float(count))
			var to := a.lerp(b, float(piece + 1) / float(count))
			var serial := index
			index += 1
			_BuildQueue.later(holder, func() -> void: _hedge(holder, from, to, gaps, serial), "town line hedge")
	_BuildQueue.later(holder, func() -> void: _fence(holder, gaps), "town line fence")
	var hills := Node3D.new()
	hills.name = "Hills"
	holder.add_child(hills)
	for side: int in 4:
		_BuildQueue.later(holder, func() -> void: _hills(hills, side), "town line hills")
	for closure: Dictionary in closures():
		_BuildQueue.later(holder, func() -> void: _closure(holder, closure), "town line closure")


static func _view(parent: Node3D, kit: RefCounted, node_name: String, shadow: bool, options: Dictionary = {}) -> MeshInstance3D:
	var mesh: ArrayMesh = kit.call("commit")
	if mesh == null:
		return null
	var merged := {"roughness": 0.95, "snow": 1.0}
	merged.merge(options, true)
	var view := _Stylized.instance(mesh, merged)
	view.name = node_name
	view.visibility_range_end = Constants.TOWN_LINE_VISIBLE_METERS
	if not shadow:
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(view)
	return view


## One stretch of hedgerow from a to b (x, z): overlapping lumps of hedge, a
## field tree every few, and a gap at each closure's gate.
static func _hedge(parent: Node3D, a: Vector2, b: Vector2, gaps: Array[Vector2], serial: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([SEED, "hedge", serial])
	var kit := _MeshKit.new()
	var length := a.distance_to(b)
	var along := (b - a).normalized()
	var across := Vector2(-along.y, along.x)
	var along_x := absf(along.x) > absf(along.y)
	var step := Constants.TOWN_LINE_HEDGE_STEP
	var count := maxi(1, int(length / step))
	for index: int in count + 1:
		var spot := a + along * (float(index) * length / float(count)) + across * rng.randf_range(-0.5, 0.5)
		# Clear of the gate and the bushes either side of it (the closure's own).
		if gaps.any(func(gap: Vector2) -> bool: return gap.distance_to(spot) < Constants.TOWN_LINE_GATE_HALF + 2.0):
			continue
		var reach := rng.randf_range(2.3, 3.1)
		var high := rng.randf_range(1.9, 2.6)
		var deep := rng.randf_range(1.5, 2.0)
		var size := Vector3(reach, high, deep) if along_x else Vector3(deep, high, reach)
		var color := HEDGE[rng.randi() % HEDGE.size()]
		kit.blob(Vector3(spot.x, high * 0.8, spot.y), size, color, {"seed": rng.randi(), "lumps": 0.35, "outward": true, "sway": 0.4, "jitter": 0.08})
		# A field tree stands out of the hedge now and then.
		if rng.randf() < Constants.TOWN_LINE_TREE_SHARE:
			var trunk_high := rng.randf_range(4.5, 6.5)
			var base := Vector3(spot.x, 0.0, spot.y)
			_P.taper(kit, base, trunk_high, 0.32, 0.2, BARK, 6)
			var crown := rng.randf_range(3.2, 4.6)
			var crown_color := CROWNS[rng.randi() % CROWNS.size()]
			kit.blob(base + Vector3(0.0, trunk_high + crown * 0.45, 0.0), Vector3(crown, crown * 0.85, crown), crown_color, {"seed": rng.randi(), "lumps": 0.3, "sway": 0.5})
			kit.blob(base + Vector3(rng.randf_range(-1.5, 1.5), trunk_high + crown * 0.1, rng.randf_range(-1.5, 1.5)), Vector3(crown * 0.6, crown * 0.5, crown * 0.6), crown_color.darkened(0.1), {"seed": rng.randi(), "lumps": 0.3, "sway": 0.5})
	_view(parent, kit, "Hedge%d" % serial, true)


## A split-rail fence along the hedge's inside, open where the tracks go through.
static func _fence(parent: Node3D, gaps: Array[Vector2]) -> void:
	var holder := Node3D.new()
	holder.name = "Fence"
	parent.add_child(holder)
	var batch := _PropBatch.new(holder, Constants.OUTSKIRTS_PROP_CHUNK)
	var rect := Constants.TOWN_LINE_RECT.grow(-FENCE_IN)
	for side: Array in [[rect.position, Vector2(rect.end.x, rect.position.y)], [Vector2(rect.end.x, rect.position.y), rect.end], [rect.end, Vector2(rect.position.x, rect.end.y)], [Vector2(rect.position.x, rect.end.y), rect.position]]:
		var a: Vector2 = side[0]
		var b: Vector2 = side[1]
		var pieces := int(a.distance_to(b) / RUN)
		var length := a.distance_to(b) / float(pieces)
		var yaw := atan2(-(b.y - a.y), b.x - a.x)
		for index: int in pieces:
			var spot := a.lerp(b, (float(index) + 0.5) / float(pieces))
			if gaps.any(func(gap: Vector2) -> bool: return absf(gap.x - spot.x) < Constants.TOWN_LINE_GATE_HALF + RUN * 0.5 and absf(gap.y - spot.y) < FENCE_IN + RUN):
				continue
			batch.call("add", "split_rail_run", Transform3D(Basis(Vector3.UP, yaw), Vector3(spot.x, 0.0, spot.y)), Color.WHITE, Vector3(length, 0.0, 0.0))
	batch.call("commit")


## Low wooded hills out past one side of the hedge (index into sides()): the
## haze takes them, so the horizon rolls instead of ending in a line.
static func _hills(holder: Node3D, index: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([SEED, "hills", index])
	var rect := Constants.TOWN_LINE_RECT
	var band := Constants.TOWN_LINE_HILLS_OUT
	var side: Array = sides()[index]
	var a: Vector2 = side[0]
	var b: Vector2 = side[1]
	var along := (b - a).normalized()
	# Outward is away from the town's middle.
	var outward := Vector2(along.y, -along.x)
	if outward.dot((a + b) * 0.5 - rect.get_center()) < 0.0:
		outward = -outward
	var kit := _MeshKit.new()
	var length := a.distance_to(b) + band.y * 2.0
	var start := a - along * band.y
	var s := 0.0
	while s < length:
		var out := rng.randf_range(band.x, band.y)
		var spot := start + along * s + outward * out
		var reach := rng.randf_range(38.0, 70.0)
		var high := rng.randf_range(12.0, 30.0)
		kit.blob(Vector3(spot.x, -high * 0.25, spot.y), Vector3(reach, high, reach * rng.randf_range(0.6, 0.9)), HILL[rng.randi() % HILL.size()], {"seed": rng.randi(), "detail": 2, "lumps": 0.18, "soft": 0.6})
		s += Constants.TOWN_LINE_HILL_SPACING * rng.randf_range(0.7, 1.2)
	var view := _view(holder, kit, "Hills%d" % index, false)
	if view != null:
		view.visibility_range_end = 0.0


## A closed road: a gravel track on from the asphalt's end, out through a shut
## farm gate in the hedge and on out of sight; at the asphalt's end a row of
## sawhorses, a barrel each side, an amber lamp and the town's sign.
static func _closure(parent: Node3D, closure: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "Closed_%s" % str(closure["key"])
	parent.add_child(root)
	var end: Vector3 = closure["end"]
	var out: Vector3 = closure["out"]
	var gate: Vector3 = closure["gate"]
	var half := float(closure["half"])
	# The barricade's frame: +X across the road, +Z back toward town (it faces in).
	root.position = barricade_at(closure)
	root.rotation.y = 0.0 if out.z < 0.0 else PI
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([SEED, str(closure["key"])])
	var track := _MeshKit.new()
	var far := Constants.TOWN_LINE_TRACK_PAST
	var to_gate := gate.distance_to(end)
	# Gravel from the barricade out past the gate (in this frame, -Z is outward).
	var track_length := to_gate - Constants.TOWN_LINE_BARRICADE_OUT + far
	track.box(Vector3(0.0, -0.01, -track_length * 0.5), Vector3(Constants.TOWN_LINE_TRACK_WIDTH, 0.06, track_length), GRAVEL)
	# Two worn ruts.
	for side: float in [-1.0, 1.0]:
		track.box(Vector3(side * 0.9, 0.0, -track_length * 0.5), Vector3(0.5, 0.06, track_length), GRAVEL.darkened(0.15))
	_view(root, track, "Track", false, {"snow": 1.0})
	var kit := _MeshKit.new()
	# fx-yard: the sawhorses and barrels are each a piece of their own, so Chefty
	# can knock them over (net/components/chefty_crash.gd, "town_knockables"),
	# each with its people-only solid (foot_solids()) turned off while it lies.
	var horses := sawhorses(closure)
	for index: int in horses.size():
		var horse: Dictionary = horses[index]
		var piece := _knockable(root, "Sawhorse%d" % index, "sawhorse", piece_key(closure, "horse", index), horse["at"], float(horse["yaw"]), float(horse["width"]) * 0.5)
		var horse_kit := _MeshKit.new()
		_sawhorse(horse_kit, Vector3.ZERO, Basis.IDENTITY, float(horse["width"]))
		_view(piece, horse_kit, "Look", true)
		# The amber lamp sits on the first one's board (its top at 1.14 m) and
		# goes over with it.
		if index == 0:
			var lamp := _LowPoly.glow(piece, Vector3(0.22, 0.22, 0.22), Vector3(0.0, 1.25, 0.0), AMBER, 1.8)
			lamp.name = "Lamp"
			(lamp as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var spots := barrels(closure)
	for index: int in spots.size():
		var piece := _knockable(root, "Barrel%d" % index, "barrel", piece_key(closure, "barrel", index), spots[index], 0.0, 0.0)
		var barrel_kit := _MeshKit.new()
		_barrel(barrel_kit, Vector3.ZERO)
		_view(piece, barrel_kit, "Look", true)
	# The sign on a stand, just off the middle, its legs behind the board: a
	# piece of its own, so a truck through the barricade takes it too (fx-yard).
	var sign_x := -half * 0.35
	var sign_piece := _knockable(root, "Sign", "sign", "", root.global_transform * Vector3(sign_x, 0.0, 0.0), root.global_rotation.y, 1.05)
	var sign_kit := _MeshKit.new()
	for leg: float in [-1.0, 1.0]:
		_P.bar(sign_kit, Vector3(leg * 0.75, 0.0, -0.3), Vector3(leg * 0.75, 2.25, -0.01), 0.045, Color(0.35, 0.36, 0.37), 5)
	_P.slab(sign_kit, Vector3(0.0, 1.75, 0.08), Vector3(2.0, 1.15, 0.05), WHITE)
	_P.slab(sign_kit, Vector3(0.0, 1.75, 0.06), Vector3(2.1, 1.25, 0.03), ORANGE)
	_view(sign_piece, sign_kit, "Look", true)
	# The farm gate in the hedge: two posts and five bars, shut across the track,
	# and a bush each side so the hedge closes on the posts.
	var gate_z := -(to_gate - Constants.TOWN_LINE_BARRICADE_OUT)
	var gate_half := Constants.TOWN_LINE_GATE_HALF
	for side: float in [-1.0, 1.0]:
		_P.post(kit, Vector3(side * (gate_half + POST_OUT), 0.0, gate_z), 1.7, 0.16, BARK, 6)
		var high := rng.randf_range(2.1, 2.5)
		var bush_at := Vector3(side * (gate_half + POST_OUT + GATE_BUSH * 0.5 - 0.1), high * 0.8, gate_z)
		kit.blob(bush_at, Vector3(GATE_BUSH, high, rng.randf_range(1.7, 2.0)), HEDGE[rng.randi() % HEDGE.size()], {"seed": rng.randi(), "lumps": 0.3, "outward": true, "sway": 0.4, "jitter": 0.06})
	for bar: int in 5:
		var y := 0.35 + float(bar) * 0.27
		_P.slab(kit, Vector3(0.0, y, gate_z), Vector3(gate_half * 2.0, 0.12, 0.06), GATE.darkened(float(bar % 2) * 0.06))
	var brace := Vector3(gate_half * 2.0, 1.08, 0.0)
	_P.slab(kit, Vector3(0.0, 0.89, gate_z + 0.05), Vector3(brace.length(), 0.12, 0.05), GATE.darkened(0.1), Basis(Vector3.BACK, atan2(brace.y, brace.x)))
	for side: float in [-1.0, 1.0]:
		_P.slab(kit, Vector3(side * (gate_half - 0.1), 0.89, gate_z + 0.04), Vector3(0.12, 1.25, 0.06), GATE.darkened(0.08))
	_view(root, kit, "Barricade", true)
	var title := _LowPoly.text_sign(sign_piece, _Strings.TOWN_SIGNS["road_closed"], Vector3(0.0, 2.0, 0.12), 50, Color(0.12, 0.1, 0.08))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.outline_size = 0
	var line := _LowPoly.text_sign(sign_piece, _Strings.TOWN_SIGNS["road_closed_" + str(closure["key"])], Vector3(0.0, 1.52, 0.12), 19, Color(0.12, 0.1, 0.08))
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.outline_size = 0


## One barricade piece Chefty can knock over: a node at world `at`, turned to
## yaw, in "town_knockables" (kind, its people-only solid's key, and how far its
## ends reach past its middle across the road, m, for the knock's footprint).
static func _knockable(parent: Node3D, node_name: String, kind: String, key: String, at: Vector3, yaw: float, reach: float) -> Node3D:
	var piece := Node3D.new()
	piece.name = node_name
	parent.add_child(piece)
	piece.global_transform = Transform3D(Basis(Vector3.UP, yaw), at)
	piece.set_meta("kind", kind)
	if key != "":
		piece.set_meta("foot_key", key)
	piece.set_meta("knock_reach", reach)
	piece.add_to_group("town_knockables")
	return piece


## A sawhorse at at (its feet at the ground), turned by turn: A-frame legs each
## end and a striped board across the top.
static func _sawhorse(kit: RefCounted, at: Vector3, turn: Basis, width: float) -> void:
	var half := width * 0.5
	for end: float in [-1.0, 1.0]:
		var top := at + turn * Vector3(end * (half - 0.15), 1.0, 0.0)
		for lean: float in [-1.0, 1.0]:
			_P.bar(kit, at + turn * Vector3(end * (half - 0.05), 0.0, lean * 0.38), top, 0.04, WHITE.darkened(0.1), 4)
	var stripes := 6
	for index: int in stripes:
		var x := -half + width * (float(index) + 0.5) / float(stripes)
		_P.slab(kit, at + turn * Vector3(x, 1.02, 0.0), Vector3(width / float(stripes) + 0.005, 0.24, 0.06), ORANGE if index % 2 == 0 else WHITE, turn)
	_P.slab(kit, at + turn * Vector3(0.0, 0.55, 0.0), Vector3(width - 0.3, 0.16, 0.05), ORANGE, turn)


## An orange traffic barrel with white bands.
static func _barrel(kit: RefCounted, at: Vector3) -> void:
	_P.taper(kit, at, 1.0, 0.33, 0.28, ORANGE, 10)
	for y: float in [0.35, 0.68]:
		_P.taper(kit, at + Vector3(0.0, y, 0.0), 0.12, 0.335 - y * 0.05, 0.33 - y * 0.05, WHITE, 10)
	_P.disc(kit, at + Vector3(0.0, 0.02, 0.0), 0.42, 0.06, Color(0.15, 0.15, 0.16), 10)
