extends RefCounted

## Authority: host. What the windrow rule promises (rakefeel:field, docs/GAME.md
## "Raking: the windrow"), checked on scratch fields with the field's real rule
## code, in --rake-net-test next to the golden (net/dev/leaf_golden.gd, which pins
## the exact bytes; this pins the behaviour, so a retune that keeps it passes):
## - symmetry: one stroke each of the 8 ways moves the same and carries as far
##   (0.4.5's in-place cascade carried leaves twice as far toward +X/+Z as back);
## - width: a stroke touches nothing farther from its line than half the head plus
##   RAKE_FIELD_EDGE (and half a cell), and clears the head's own width;
## - windrow: a run walked down a fresh lawn at the swing's rhythm leaves the lane
##   behind clean and pushes a berm that grows every metre and rides just ahead
##   of the tines, holding nearly all of what the run crossed;
## - pile: runs from three sides into one spot make a pile you can dive into
##   (is_pile_at), and one stroke can't haul a lane (at most cap per lane);
## - a full head: a 16 m run's berm stops growing (diminishing returns);
## - bare hands barely move anything next to the rake;
## - the drag: forward only, none after a turn, a side-step or a step back.
## Returns {ok, why, numbers}.

const _FieldScript: Script = preload("res://net/leaf_field/leaf_field.gd")
const REACH: float = 1.5
const LAWN: int = 60


static func run(parent: Node) -> Dictionary:
	var tree := parent.get_tree()
	var branch := Node3D.new()
	branch.name = "RakeRulesScratch"
	parent.add_child(branch)
	branch.global_position = Vector3(0.0, -1000.0, 0.0)
	var api := MultiplayerAPI.create_default_interface()
	tree.set_multiplayer(api, branch.get_path())
	var problems: Array[String] = []
	var numbers := {}
	_symmetry(branch, problems, numbers)
	_width(branch, problems, numbers)
	_windrow(branch, problems, numbers)
	_pile(branch, problems, numbers)
	_full_head(branch, problems, numbers)
	_hands(branch, problems, numbers)
	_drag(branch, problems, numbers)
	tree.set_multiplayer(null, branch.get_path())
	branch.queue_free()
	return {"ok": problems.is_empty(), "why": "; ".join(problems), "numbers": numbers}


static func _field(branch: Node3D, fill: int = LAWN) -> Node3D:
	var field := _FieldScript.new() as Node3D
	field.set("scratch", true)
	branch.add_child(field)
	field.set_process(false)
	var density: PackedByteArray = field.get("_density")
	density.fill(fill)
	field.set("_density", density)
	return field


static func _at(field: Node3D, local: Vector3) -> Vector3:
	return field.to_global(Vector3(local.x, 0.25, local.z))


static func _cell_center(field: Node3D, x: int, z: int) -> Vector2:
	var origin: Vector3 = field.get("grid_origin")
	return Vector2(origin.x + (float(x) + 0.5) * 0.5, origin.z + (float(z) + 0.5) * 0.5)


## Sum over cells of (density - lawn) x position along dir, / units that left.
static func _carry(field: Node3D, dir: Vector3) -> float:
	var density: PackedByteArray = field.get("_density")
	var moment := 0.0
	var lost := 0
	for z: int in 80:
		for x: int in 80:
			var d := int(density[x + z * 80])
			if d == LAWN:
				continue
			var c := _cell_center(field, x, z)
			moment += float(d - LAWN) * (c.x * dir.x + c.y * dir.z)
			if d < LAWN:
				lost += LAWN - d
	return moment / maxf(1.0, float(lost))


static func _symmetry(branch: Node3D, problems: Array[String], numbers: Dictionary) -> void:
	var dirs: Array[Vector3] = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1),
		Vector3(1, 0, 1), Vector3(-1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, -1)]
	var moved: Array[int] = []
	var carries: Array[float] = []
	for raw: Vector3 in dirs:
		var dir := raw.normalized()
		var field := _field(branch)
		moved.append(int(field.call("_stroke_cells", _at(field, Vector3.ZERO), dir, Constants.RAKE_WIDTH, Constants.RAKE_STRENGTH, Constants.RAKE_STROKE_CELLS, 0.0, -1)))
		carries.append(_carry(field, dir))
		field.free()
	numbers["symmetry_moved"] = moved
	numbers["symmetry_carry"] = carries.map(func(c: float) -> float: return snappedf(c, 0.01))
	for group: Array in [[0, 1, 2, 3], [4, 5, 6, 7]]:
		for index: int in group:
			if moved[index] != moved[group[0]] or absf(carries[index] - carries[group[0]]) > 0.01:
				problems.append("symmetry: direction %s moved %d (carry %.2f m), %s moved %d (%.2f m)" % [dirs[index], moved[index], carries[index], dirs[group[0]], moved[group[0]], carries[group[0]]])
	if moved[0] <= 0 or absf(carries[0] - carries[4]) > 0.2 * carries[0]:
		problems.append("symmetry: axis carry %.2f m vs diagonal %.2f m" % [carries[0], carries[4]])


static func _width(branch: Node3D, problems: Array[String], numbers: Dictionary) -> void:
	var field := _field(branch)
	var here := Vector2(0.25, 0.25)
	field.call("_stroke_cells", _at(field, Vector3(here.x, 0.0, here.y)), Vector3.RIGHT, Constants.RAKE_WIDTH, Constants.RAKE_STRENGTH, Constants.RAKE_STROKE_CELLS, 0.0, -1)
	var limit := Constants.RAKE_WIDTH * 0.5 + Constants.RAKE_FIELD_EDGE + 0.25
	var widest := 0.0
	var cleared_rows := {}
	for z: int in 80:
		for x: int in 80:
			var d := int(field.call("density_at_cell", x, z))
			if d == LAWN:
				continue
			var across := absf(_cell_center(field, x, z).y - here.y)
			widest = maxf(widest, across)
			if d <= int(field.get("CLEAN_DENSITY")):
				cleared_rows[z] = true
	numbers["width_touched_m"] = snappedf(widest * 2.0 + 0.5, 0.01)
	numbers["width_cleared_rows"] = cleared_rows.size()
	if widest > limit:
		problems.append("width: a %.2f m head touched a cell %.2f m off its line (limit %.2f)" % [Constants.RAKE_WIDTH, widest, limit])
	if float(cleared_rows.size()) * 0.5 < Constants.RAKE_WIDTH * 0.9:
		problems.append("width: a %.2f m head cleared only %d rows" % [Constants.RAKE_WIDTH, cleared_rows.size()])
	field.free()


## The raker's swing in time: bites at RAKE_SWING_BITES of each swing, walking at
## speed, the drag tracked by the field. Returns the strokes' moved, in order.
static func _walk(field: Node3D, from: Vector3, to: Vector3, speed: float, actor: int = 1) -> Array[int]:
	var cycle := Constants.RAKE_STROKE_SECONDS * float(Constants.RAKE_SWING_STROKES)
	var dir := (to - from).normalized()
	var duration := from.distance_to(to) / speed
	var moved: Array[int] = []
	var swing := 0
	while true:
		var done := false
		for bite: int in Constants.RAKE_SWING_BITES.size():
			var t := (float(swing) + Constants.RAKE_SWING_BITES[bite]) * cycle
			if t > duration:
				done = true
				break
			var player := from.lerp(to, t / duration)
			var origin := _at(field, player + dir * REACH)
			var drag := float(field.call("_stroke_drag", actor, origin, dir))
			moved.append(int(field.call("_stroke_cells", origin, dir, Constants.RAKE_WIDTH, Constants.RAKE_STRENGTH, Constants.RAKE_STROKE_CELLS, drag, bite)))
		if done:
			break
		swing += 1
	return moved


## Units in the lane band (|z| <= 1 m) between two x positions.
static func _band(field: Node3D, x_from: float, x_to: float, z: float = 0.25) -> int:
	var total := 0
	for cz: int in 80:
		for cx: int in 80:
			var c := _cell_center(field, cx, cz)
			if c.x >= x_from and c.x <= x_to and absf(c.y - z) <= 1.0:
				total += int(field.call("density_at_cell", cx, cz))
	return total


static func _windrow(branch: Node3D, problems: Array[String], numbers: Dictionary) -> void:
	var field := _field(branch)
	var start := Vector3(-12.0, 0.0, 0.25)
	var berms: Array[int] = []
	var tines := 0.0
	for metre: int in 6:
		_walk(field, start + Vector3(float(metre), 0.0, 0.0), start + Vector3(float(metre + 1), 0.0, 0.0), 2.5)
		tines = start.x + float(metre + 1) + REACH + Constants.RAKE_FIELD_BITE_FRONT[1]
		berms.append(_band(field, tines - 0.5, tines + 2.0))
	numbers["windrow_berm_by_metre"] = berms
	for index: int in range(1, berms.size()):
		if berms[index] <= berms[index - 1]:
			problems.append("windrow: the berm didn't grow from metre %d to %d (%s)" % [index, index + 1, berms])
			break
	# The peak rides just ahead of the tines, and it's a heap.
	var peak := 0
	var peak_x := 0.0
	for cx: int in 80:
		var d := int(field.call("density_at_cell", cx, 40))
		if d > peak:
			peak = d
			peak_x = _cell_center(field, cx, 40).x
	numbers["windrow_peak"] = peak
	numbers["windrow_peak_ahead_m"] = snappedf(peak_x - tines, 0.01)
	if peak < 200 or peak_x - tines < -0.5 or peak_x - tines > 1.5:
		problems.append("windrow: peak %d at %.2f m from the tine line (want >= 200, -0.5..1.5 m)" % [peak, peak_x - tines])
	# Behind the tines the lane is clean.
	var dirty := 0
	for cx: int in 80:
		var c := _cell_center(field, cx, 40)
		if c.x > start.x + REACH + 0.5 and c.x < tines - 1.0:
			for cz: int in [39, 40, 41]:
				if int(field.call("density_at_cell", cx, cz)) > int(field.get("CLEAN_DENSITY")):
					dirty += 1
	numbers["windrow_dirty_behind"] = dirty
	if dirty > 0:
		problems.append("windrow: %d cells left dirty behind the tines" % dirty)
	# Nearly everything the run crossed is in the berm (conserved, not erased).
	var total := 0
	for byte: int in (field.get("_density") as PackedByteArray):
		total += byte
	numbers["windrow_conserved"] = total == 80 * 80 * LAWN
	if total != 80 * 80 * LAWN:
		problems.append("windrow: the field holds %d units, it started with %d" % [total, 80 * 80 * LAWN])
	field.free()


static func _pile(branch: Node3D, problems: Array[String], numbers: Dictionary) -> void:
	var field := _field(branch)
	var spot := Vector3(0.0, 0.0, 0.0)
	var piles: Array = []
	for dir: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK]:
		var end := spot - dir * (REACH + 0.75)
		_walk(field, end - dir * 5.0, end, 2.5, 3)
		var best := 0
		for dz: int in range(-8, 9):
			for dx: int in range(-8, 9):
				best = maxi(best, int(field.call("units_within_world", _at(field, Vector3(float(dx) * 0.25, 0.0, float(dz) * 0.25)), Constants.PILE_HIDE_RADIUS)))
		piles.append(best)
	numbers["pile_units_by_run"] = piles
	if int(piles[2]) < Constants.PILE_HIDE_UNITS or int(piles[2]) <= int(piles[0]):
		problems.append("pile: three runs into one spot made %s units (a pile is %d)" % [piles, Constants.PILE_HIDE_UNITS])
	field.free()
	# One stroke dragged through a deep drift moves at most the head's cap per lane.
	var deep := _field(branch)
	var bytes: PackedByteArray = deep.get("_density")
	for z: int in range(36, 45):
		for x: int in range(32, 41):
			bytes[x + z * 80] = 255
	deep.set("_density", bytes)
	var one := int(deep.call("_stroke_cells", _at(deep, Vector3(0.25, 0.0, 0.25)), Vector3.RIGHT, Constants.RAKE_WIDTH, Constants.RAKE_STRENGTH, Constants.RAKE_STROKE_CELLS, Constants.RAKE_FIELD_DRAG_MAX, -1))
	var lanes := int(ceil((Constants.RAKE_WIDTH + 2.0 * Constants.RAKE_FIELD_EDGE) / 0.5)) + 1
	var cap := int(Constants.RAKE_STRENGTH * Constants.RAKE_FIELD_LOAD) * lanes
	numbers["deep_stroke_moved"] = one
	if one > cap or one < int(Constants.RAKE_STRENGTH * Constants.RAKE_FIELD_LOAD):
		problems.append("pile: one stroke through a deep drift moved %d (at most %d, at least one lane's cap)" % [one, cap])
	deep.free()


## A run twice a normal one: the head fills, and the berm stops growing.
static func _full_head(branch: Node3D, problems: Array[String], numbers: Dictionary) -> void:
	var field := _field(branch)
	var start := Vector3(-18.0, 0.0, 0.25)
	_walk(field, start, start + Vector3(8.0, 0.0, 0.0), 2.5)
	var tines := start.x + 8.0 + REACH + Constants.RAKE_FIELD_BITE_FRONT[1]
	var at_8 := _band(field, tines - 0.75, tines + 2.0)
	_walk(field, start + Vector3(8.0, 0.0, 0.0), start + Vector3(16.0, 0.0, 0.0), 2.5)
	tines += 8.0
	var at_16 := _band(field, tines - 0.75, tines + 2.0)
	numbers["full_head_berm_8m_16m"] = [at_8, at_16]
	if float(at_16) > float(at_8) * 1.6:
		problems.append("full head: the berm kept growing, %d units after 8 m and %d after 16 m" % [at_8, at_16])
	field.free()


static func _hands(branch: Node3D, problems: Array[String], numbers: Dictionary) -> void:
	var out := {}
	for tool: Array in [["rake", Constants.RAKE_WIDTH, Constants.RAKE_STRENGTH, Constants.RAKE_STROKE_CELLS, 0.3],
			["hand", Constants.HAND_RAKE_WIDTH, Constants.HAND_RAKE_STRENGTH, 1, 0.35]]:
		var field := _field(branch)
		var moved := 0
		var x := -12.0
		while x < 0.0:
			var origin := _at(field, Vector3(x + REACH, 0.0, 0.25))
			var drag := float(field.call("_stroke_drag", 5, origin, Vector3.RIGHT))
			moved += int(field.call("_stroke_cells", origin, Vector3.RIGHT, float(tool[1]), float(tool[2]), int(tool[3]), drag, -1))
			x += 2.5 * float(tool[4])
		out[tool[0]] = moved
		field.free()
	numbers["hands_vs_rake"] = out
	if float(out["hand"]) > 0.08 * float(out["rake"]):
		problems.append("hands: bare hands moved %d where the rake moved %d" % [out["hand"], out["rake"]])


static func _drag(branch: Node3D, problems: Array[String], numbers: Dictionary) -> void:
	var field := _field(branch)
	var got: Array[float] = []
	got.append(float(field.call("_stroke_drag", 9, _at(field, Vector3(0.0, 0.0, 0.0)), Vector3.RIGHT)))
	got.append(float(field.call("_stroke_drag", 9, _at(field, Vector3(1.0, 0.0, 0.0)), Vector3.RIGHT)))
	got.append(float(field.call("_stroke_drag", 9, _at(field, Vector3(10.0, 0.0, 0.0)), Vector3.RIGHT)))
	got.append(float(field.call("_stroke_drag", 9, _at(field, Vector3(9.0, 0.0, 0.0)), Vector3.RIGHT)))
	got.append(float(field.call("_stroke_drag", 9, _at(field, Vector3(9.5, 0.0, 2.0)), Vector3.RIGHT)))
	got.append(float(field.call("_stroke_drag", 9, _at(field, Vector3(10.0, 0.0, 2.0)), Vector3.FORWARD)))
	got.append(float(field.call("_stroke_drag", 10, _at(field, Vector3(10.5, 0.0, 2.0)), Vector3.RIGHT)))
	var want: Array[float] = [0.0, 1.0, Constants.RAKE_FIELD_DRAG_MAX, 0.0, 0.0, 0.0, 0.0]
	numbers["drag"] = got
	for index: int in want.size():
		if absf(got[index] - want[index]) > 0.001:
			problems.append("drag: step %d gave %.2f m, want %.2f (first, forward, capped, back, side-step, turn, another raker)" % [index + 1, got[index], want[index]])
			break
	field.free()
