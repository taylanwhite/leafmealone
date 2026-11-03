extends SceneTree

## How raking feels, in numbers (rakefeel:field). Run headless:
##   godot --headless --path . --script res://tools/rake_pace.gd [-- --quick]
## Uses the leaf field's real rule code (a scratch LeafField: no peers, no view)
## on yards shaped like levels/lots/lot_generator.gd (the stand-in
## tools/leaf_look_check.gd uses: seeded trees, a house, a path) and reports:
## - pace: a scripted competent raker cleans the yard to the clean target. The
##   yard is cut into square blocks; each block is raked in lanes from both of its
##   edges in toward a pile row across its middle, at a walking pace, then the
##   rows are bagged. Lane spacing, block size and where to stop are searched per
##   rule, so each rule gets its best raker. Time is raking + walking + bagging
##   (BAG_SECONDS a bag) and, separately, hauling (HAUL_SECONDS a bag).
## - strokes: what one stroke moves on a fresh lawn, standing and walking.
## - windrow: a 6 m run down a fresh lawn: the density profile along the lane,
##   the berm's peak and where it rides relative to the tines.
## - pile: three runs into one spot: units within PILE_HIDE_RADIUS, is_pile_at.
## - symmetry: a 4 m run in each of the 8 directions: units moved and how far.
## Prints [RakePace] lines and a JSON summary; exits 0.

## Loaded on the first frame: the field names the Net autoload, which a --script
## run only registers after _initialize.
var _FieldScript: Script
var _started := false
const GRID: int = 80
const CELL: float = 0.5
const ORIGIN := Vector3(-20.0, 0.05, -20.0)
## The rake lands this far ahead of the player (equipment/rake.gd REACH).
const REACH: float = 1.5
## Walking between lanes, with the rake up.
const WALK_SPEED: float = 5.0
## One bag: the press, the scoop, the tie.
const BAG_SECONDS: float = 1.5
## Carrying one bag to Chefty (a wheelbarrow trip shared four ways, the walk back).
const HAUL_SECONDS: float = 4.0
const CLEAN_TARGET: float = 0.92
const MAX_PASSES: int = 3

var _quick := false
var _report: Dictionary = {}


func _process(_delta: float) -> bool:
	if _started:
		return true
	_started = true
	var path := "res://net/leaf_field/leaf_field.gd"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--field="):
			path = arg.substr(8)
	_FieldScript = load(path)
	_run()
	return true


func _run() -> void:
	_quick = OS.get_cmdline_user_args().has("--quick")
	var rule := "windrow" if _new_api(_field_for(_uniform(60))) else "legacy"
	print("[RakePace] rule: %s (RAKE_WIDTH %.2f, RAKE_STRENGTH %.1f, RAKE_STROKE_CELLS %d)" % [rule, _width(), Constants.RAKE_STRENGTH, Constants.RAKE_STROKE_CELLS])
	_report["rule"] = rule
	_strokes()
	_windrow()
	_pile()
	_symmetry()
	_pace()
	print("[RakePace] JSON %s" % JSON.stringify(_report))
	quit(0)


# ---- the field

func _field_for(density: PackedByteArray) -> Node3D:
	var field := _FieldScript.new() as Node3D
	field.set("scratch", true)
	root.add_child(field)
	field.set_process(false)
	field.set("_density", density.duplicate())
	return field


func _new_api(field: Node3D) -> bool:
	var yes := field.has_method("_stroke_drag")
	field.free()
	return yes


func _uniform(value: int) -> PackedByteArray:
	var density := PackedByteArray()
	density.resize(GRID * GRID)
	density.fill(value)
	return density


## lot_generator.gd's look, as tools/leaf_look_check.gd stands it in.
func _yard(seed_value: int, size: int) -> PackedByteArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var counts: Vector2i = Constants.YARD_TREES[size]
	var trees: Array[Vector2] = []
	for index: int in rng.randi_range(counts.x, counts.y):
		trees.append(Vector2(rng.randf_range(-16.5, 16.5), rng.randf_range(-16.5, 17.0)))
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
	return density


func _clean_at_start(density: PackedByteArray) -> int:
	var count := 0
	for byte: int in density:
		if byte <= 8:
			count += 1
	return count


func _cleaned(field: Node3D, start_clean: int) -> float:
	var density: PackedByteArray = field.get("_density")
	var clean := -start_clean
	for byte: int in density:
		if byte <= 8:
			clean += 1
	return float(clean) / float(GRID * GRID - start_clean)


func _total(field: Node3D) -> int:
	var total := 0
	for byte: int in (field.get("_density") as PackedByteArray):
		total += byte
	return total


# ---- a raker

## One raker's strokes on one field: the swing's bites in time order, the drag the
## field tracks between strokes (new rule) or nothing (legacy).
class Raker:
	var field: Node3D
	var t: float = 0.0
	var strokes: int = 0
	var moved: int = 0
	var swing_t: float = 0.0
	var next_bite: int = 0
	var bites: Array[float] = []
	var cycle: float = 0.6

	func _init(on: Node3D) -> void:
		field = on
		cycle = Constants.RAKE_STROKE_SECONDS * float(Constants.RAKE_SWING_STROKES)
		for share: float in Constants.RAKE_SWING_BITES:
			bites.append(share * cycle)

	## Lift the rake (between runs): the next press starts a new swing, and the
	## head was in the air, so nothing was dragged.
	func _width() -> float:
		for arg: String in OS.get_cmdline_user_args():
			if arg.begins_with("--width="):
				return float(arg.substr(8))
		return Constants.RAKE_WIDTH

	func lift() -> void:
		swing_t = 0.0
		next_bite = 0

	## Walk from a to b (player positions) at speed while holding the rake.
	func rake_walk(a: Vector3, b: Vector3, speed: float, dir: Vector3) -> void:
		var length := a.distance_to(b)
		var duration := length / maxf(speed, 0.001)
		var elapsed := 0.0
		while true:
			var to_bite := bites[next_bite] - swing_t
			if elapsed + to_bite > duration:
				swing_t += duration - elapsed
				t += duration - elapsed
				return
			elapsed += to_bite
			swing_t = bites[next_bite]
			t += to_bite
			var at := a.lerp(b, elapsed / duration) if duration > 0.0 else b
			stroke(at, dir, next_bite)
			next_bite += 1
			if next_bite >= bites.size():
				next_bite = 0
				# The rest of the swing (flick, swing back) before the next plant.
				var rest := cycle - swing_t
				swing_t = 0.0
				if elapsed + rest > duration:
					# Finishing the swing standing still is a pause, not travel.
					t += rest
					elapsed = duration
					return
				elapsed += rest
				t += rest

	## Stand and rake for this long.
	func rake_still(at: Vector3, seconds: float, dir: Vector3) -> void:
		var left := seconds
		while left > 0.0:
			var to_bite := bites[next_bite] - swing_t
			if to_bite > left:
				swing_t += left
				t += left
				return
			left -= to_bite
			t += to_bite
			swing_t = bites[next_bite]
			stroke(at, dir, next_bite)
			next_bite += 1
			if next_bite >= bites.size():
				next_bite = 0
				left -= cycle - swing_t
				t += cycle - swing_t
				swing_t = 0.0

	## One field stroke from a player standing at player_at, facing dir.
	func stroke(player_at: Vector3, dir: Vector3, bite: int) -> int:
		var origin := player_at + dir * 1.5 + Vector3(0.0, 0.2, 0.0)
		var got := 0
		if field.has_method("_stroke_drag"):
			var drag := float(field.call("_stroke_drag", 1, origin, dir))
			got = int(field.call("_stroke_cells", origin, dir, _width(), Constants.RAKE_STRENGTH, Constants.RAKE_STROKE_CELLS, drag, bite))
		else:
			got = int(field.call("_stroke_cells", origin, dir, _width(), Constants.RAKE_STRENGTH, Constants.RAKE_STROKE_CELLS))
		strokes += 1
		moved += got
		return got


# ---- reports

func _strokes() -> void:
	var out := {}
	for speed: float in [0.0, 2.5, 5.0]:
		var field := _field_for(_uniform(60))
		var raker := Raker.new(field)
		var start := Vector3(-12.0, 0.0, 0.0)
		if speed <= 0.0:
			raker.rake_still(start, 3.0, Vector3.RIGHT)
		else:
			raker.rake_walk(start, start + Vector3(12.0, 0.0, 0.0), speed, Vector3.RIGHT)
		var per_stroke := float(raker.moved) / maxf(1.0, float(raker.strokes))
		var per_second := float(raker.moved) / maxf(0.001, raker.t)
		out["%.1f" % speed] = {"strokes": raker.strokes, "per_stroke": snappedf(per_stroke, 0.1), "per_second": snappedf(per_second, 1.0), "seconds": snappedf(raker.t, 0.01)}
		print("[RakePace] strokes at %.1f m/s: %d strokes in %.2f s, %.0f units a stroke, %.0f a second" % [speed, raker.strokes, raker.t, per_stroke, per_second])
		field.free()
	_report["strokes"] = out
	# Bare hands and the blower, walking a 12 m strip at 2.5 m/s: how much of a
	# 1.5 m strip they leave clean, and how far they shift the leaves.
	var tools := {}
	for tool: Array in [["hand", Constants.HAND_RAKE_WIDTH, Constants.HAND_RAKE_STRENGTH, 1, 0.35],
			["blower", Constants.BLOWER_WIDTH, Constants.BLOWER_STRENGTH, Constants.BLOWER_CELLS, Constants.BLOWER_PUFF_SECONDS]]:
		var field := _field_for(_uniform(60))
		var t := 0.0
		var moved := 0
		var strokes := 0
		var x := -12.0
		while x < 0.0:
			var origin := Vector3(x + 1.5, 0.25, 0.25)
			var drag := 0.0
			if field.has_method("_stroke_drag"):
				drag = float(field.call("_stroke_drag", 7, origin, Vector3.RIGHT))
				moved += int(field.call("_stroke_cells", origin, Vector3.RIGHT, float(tool[1]), float(tool[2]), int(tool[3]), drag, -1))
			else:
				moved += int(field.call("_stroke_cells", origin, Vector3.RIGHT, float(tool[1]), float(tool[2]), int(tool[3])))
			strokes += 1
			t += float(tool[4])
			x += 2.5 * float(tool[4])
		var clean := 0
		for cx: int in range(20, 40):
			for cz: int in range(39, 42):
				if int(field.call("density_at_cell", cx, cz)) <= 8:
					clean += 1
		tools[tool[0]] = {"per_second": int(float(moved) / t), "per_stroke": int(float(moved) / float(strokes)), "strip_clean": snappedf(float(clean) / 60.0, 0.01)}
		print("[RakePace] %s: %d units a stroke, %d a second, %.0f%% of its strip clean" % [tool[0], int(float(moved) / float(strokes)), int(float(moved) / t), 100.0 * float(clean) / 60.0])
		field.free()
	_report["tools"] = tools
	# A hired hand's pile (npcs/crew_hand.gd): HIRE_STROKES_PER_PILE strokes 0.9 m
	# ahead, a HIRE_STEP_AFTER_STROKE glide after each (0.18 m on the legacy field),
	# then a bag 2.4 m ahead.
	var crew := {}
	for skill: float in [0.5, 1.0]:
		var field := _field_for(_uniform(60))
		var pos := Vector3(0.0, 0.0, 0.25)
		for index: int in Constants.HIRE_STROKES_PER_PILE:
			var origin := pos + Vector3.RIGHT * 0.9
			if field.has_method("_stroke_drag"):
				var drag := float(field.call("_stroke_drag", 1001, origin, Vector3.RIGHT))
				field.call("_stroke_cells", origin, Vector3.RIGHT, Constants.RAKE_WIDTH, Constants.RAKE_STRENGTH * skill, Constants.RAKE_STROKE_CELLS, drag)
			else:
				field.call("_stroke_cells", origin, Vector3.RIGHT, _width(), Constants.RAKE_STRENGTH * skill, Constants.RAKE_STROKE_CELLS)
			pos += Vector3.RIGHT * (Constants.HIRE_STEP_AFTER_STROKE if field.has_method("_stroke_drag") else 0.18)
		var bagged := int(field.call("_apply_collect", pos + Vector3.RIGHT * 2.4, Constants.BAG_RADIUS, false))
		crew["%.1f" % skill] = bagged
		print("[RakePace] hired hand at skill %.1f: a pile bags %d units" % [skill, bagged])
		field.free()
	_report["crew"] = crew


## A 6 m run down a fresh lawn at crouch pace, then the lane's profile.
func _windrow() -> void:
	var field := _field_for(_uniform(60))
	var raker := Raker.new(field)
	var start := Vector3(-10.0, 0.0, 0.25)
	var stop := start + Vector3(6.0, 0.0, 0.0)
	var profile: Array = []
	var peaks: Array = []
	# Snapshots after each metre: where's the berm, how big.
	for metre: int in 6:
		raker.rake_walk(start + Vector3(float(metre), 0.0, 0.0), start + Vector3(float(metre + 1), 0.0, 0.0), 2.5, Vector3.RIGHT)
		var tines := start.x + float(metre + 1) + REACH
		var best := 0
		var best_x := 0.0
		var lane_sum := 0
		for x: int in GRID:
			var wx := ORIGIN.x + (float(x) + 0.5) * CELL
			var d := int(field.call("density_at_cell", x, 40))
			if d > best:
				best = d
				best_x = wx
			if wx > tines - 0.5 and wx < tines + 2.0:
				lane_sum += d + int(field.call("density_at_cell", x, 39)) + int(field.call("density_at_cell", x, 41))
		peaks.append({"after_m": metre + 1, "peak": best, "peak_ahead_of_tines": snappedf(best_x - tines, 0.01), "berm_units": lane_sum})
	for x: int in GRID:
		var wx := ORIGIN.x + (float(x) + 0.5) * CELL
		if wx >= start.x - 1.0 and wx <= stop.x + 5.0:
			profile.append([snappedf(wx - (stop.x + REACH), 0.01), int(field.call("density_at_cell", x, 39)), int(field.call("density_at_cell", x, 40)), int(field.call("density_at_cell", x, 41)), int(field.call("density_at_cell", x, 42))])
	var across: Array = []
	for z: int in range(34, 47):
		var row := 0
		for x: int in GRID:
			row += int(field.call("density_at_cell", x, z))
		across.append(row)
	print("[RakePace] windrow: berm after each metre %s" % str(peaks))
	print("[RakePace] windrow: lane profile (m from tines, rows z39..42) %s" % str(profile))
	print("[RakePace] windrow: units per row across the lane z34..46 %s" % str(across))
	_report["windrow"] = {"peaks": peaks, "profile": profile, "across": across}
	field.free()


## Three runs into one spot (from -X, +X, -Z), then is it a pile?
func _pile() -> void:
	var field := _field_for(_uniform(60))
	var raker := Raker.new(field)
	var spot := Vector3(0.0, 0.0, 0.0)
	var runs: Array = []
	var stop_at := 0.75
	for dir: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD, Vector3(1, 0, 1).normalized(), Vector3(-1, 0, -1).normalized()]:
		raker.lift()
		var player_end := spot - dir * (REACH + stop_at)
		var player_start := player_end - dir * 5.0
		raker.rake_walk(player_start, player_end, 2.5, dir)
		raker.rake_still(player_end, 0.6, dir)
		var units := int(field.call("units_within_world", spot, Constants.PILE_HIDE_RADIUS))
		var best := _best_pile(field, spot, 2.0)
		runs.append({"dir": _dir_name(dir), "units_at_spot": units, "best_units": best[1], "best_at": [snappedf(best[0].x, 0.1), snappedf(best[0].z, 0.1)], "is_pile": bool(field.call("is_pile_at", best[0]))})
	print("[RakePace] pile: after each run into (0,0) %s (a pile is %d)" % [str(runs), Constants.PILE_HIDE_UNITS])
	_report["pile"] = runs
	field.free()


func _best_pile(field: Node3D, around: Vector3, reach: float) -> Array:
	var best := around
	var most := -1
	var steps := int(reach / 0.25)
	for dz: int in range(-steps, steps + 1):
		for dx: int in range(-steps, steps + 1):
			var at := around + Vector3(float(dx) * 0.25, 0.0, float(dz) * 0.25)
			var units := int(field.call("units_within_world", at, Constants.PILE_HIDE_RADIUS))
			if units > most:
				most = units
				best = at
	return [best, most]


## A 4 m run in each of the 8 directions on a fresh lawn: moved, and how far the
## moved leaves travelled (the shift of the field's centre of mass along the run).
func _symmetry() -> void:
	var out: Array = []
	var dirs: Array[Vector3] = [Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1), Vector3(-1, 0, 1),
		Vector3(-1, 0, 0), Vector3(-1, 0, -1), Vector3(0, 0, -1), Vector3(1, 0, -1)]
	var carries: Array[float] = []
	for dir_raw: Vector3 in dirs:
		var dir := dir_raw.normalized()
		var field := _field_for(_uniform(60))
		var before := _moment(field, dir)
		var raker := Raker.new(field)
		var player_start := -dir * 4.0
		raker.rake_walk(player_start, Vector3.ZERO, 2.5, dir)
		var after := _moment(field, dir)
		# Units x metres of travel / the units that moved = the mean carry.
		var shifted := after - before
		var carry := shifted / maxf(1.0, float(_units_changed(field)))
		carries.append(carry)
		out.append({"dir": _dir_name(dir), "moved": raker.moved, "carry_m": snappedf(carry, 0.01), "total": _total(field)})
		field.free()
	var lo := 1e9
	var hi := 0.0
	for c: float in carries:
		lo = minf(lo, c)
		hi = maxf(hi, c)
	print("[RakePace] symmetry: runs %s, carry max/min %.2f" % [str(out), hi / maxf(lo, 0.001)])
	# One stroke each way, standing (R1's OQ-R1-2: +X carried ~3 m, -X ~1.5 m).
	var singles: Array = []
	var single_carries: Array[float] = []
	for dir_raw: Vector3 in dirs:
		var dir := dir_raw.normalized()
		var field := _field_for(_uniform(60))
		var before := _moment(field, dir)
		var origin := Vector3(0.0, 0.25, 0.0)
		var got := 0
		if field.has_method("_stroke_drag"):
			got = int(field.call("_stroke_cells", origin, dir, _width(), Constants.RAKE_STRENGTH, Constants.RAKE_STROKE_CELLS, 0.0, -1))
		else:
			got = int(field.call("_stroke_cells", origin, dir, _width(), Constants.RAKE_STRENGTH, Constants.RAKE_STROKE_CELLS))
		var carry := (_moment(field, dir) - before) / maxf(1.0, float(_units_changed(field)))
		# How far ahead the farthest leaf landed (R1 measured 3 m one way, 1.5 m the other).
		var reach := 0.0
		var density: PackedByteArray = field.get("_density")
		for z: int in GRID:
			for x: int in GRID:
				if int(density[x + z * GRID]) > 60:
					var at := Vector3(ORIGIN.x + (float(x) + 0.5) * CELL, 0.0, ORIGIN.z + (float(z) + 0.5) * CELL)
					reach = maxf(reach, at.dot(dir))
		single_carries.append(reach)
		singles.append({"dir": _dir_name(dir), "moved": got, "carry_m": snappedf(carry, 0.01), "reach_m": snappedf(reach, 0.01)})
		field.free()
	var lo1 := 1e9
	var hi1 := 0.0
	for c: float in single_carries:
		lo1 = minf(lo1, c)
		hi1 = maxf(hi1, c)
	print("[RakePace] symmetry: single strokes %s, carry max/min %.2f" % [str(singles), hi1 / maxf(lo1, 0.001)])
	_report["symmetry"] = {"runs": out, "carry_ratio": snappedf(hi / maxf(lo, 0.001), 0.01), "singles": singles, "single_ratio": snappedf(hi1 / maxf(lo1, 0.001), 0.01)}


## Sum of density x position along dir.
func _moment(field: Node3D, dir: Vector3) -> float:
	var total := 0.0
	var density: PackedByteArray = field.get("_density")
	for z: int in GRID:
		for x: int in GRID:
			var d := int(density[x + z * GRID])
			if d == 60:
				continue
			var at := Vector3(ORIGIN.x + (float(x) + 0.5) * CELL, 0.0, ORIGIN.z + (float(z) + 0.5) * CELL)
			total += float(d - 60) * at.dot(dir)
	return total


## Half the absolute change: the units that left their cell.
func _units_changed(field: Node3D) -> int:
	var lost := 0
	for byte: int in (field.get("_density") as PackedByteArray):
		if byte < 60:
			lost += 60 - byte
	return lost


func _dir_name(dir: Vector3) -> String:
	var parts := ""
	if dir.x > 0.1:
		parts += "+x"
	elif dir.x < -0.1:
		parts += "-x"
	if dir.z > 0.1:
		parts += "+z"
	elif dir.z < -0.1:
		parts += "-z"
	return parts


# ---- pace

func _pace() -> void:
	var seeds: Array = [777, 1000, 4242]
	var speeds: Array = [2.5, 5.0]
	var spacings: Array = [1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 3.5]
	var blocks: Array = [3, 4, 5, 6]
	var stops: Array = [0.5, 1.0, 1.5, 2.5]
	if _quick:
		seeds = [777, 1000]
		spacings = [1.25, 1.5, 2.0, 3.0]
		blocks = [4, 5]
		stops = [0.5, 1.5]
	# --seeds=1,2 --speeds=2.5 --spacings=1.5,2 --blocks=4 --stops=1 pick by hand.
	for arg: String in OS.get_cmdline_user_args():
		for key: String in ["seeds", "speeds", "spacings", "blocks", "stops"]:
			if arg.begins_with("--%s=" % key):
				var values: Array = []
				for part: String in arg.substr(key.length() + 3).split(","):
					values.append(int(part) if key == "seeds" or key == "blocks" else float(part))
				match key:
					"seeds": seeds = values
					"speeds": speeds = values
					"spacings": spacings = values
					"blocks": blocks = values
					"stops": stops = values
	var out := {}
	for speed: float in speeds:
		var times: Array[float] = []
		var hauls: Array[float] = []
		var best_runs: Array = []
		for seed_value: int in seeds:
			var yard := _yard(seed_value, 1)
			for orient: int in 2:
				var best := {}
				for spacing: float in spacings:
					for block_count: int in blocks:
						for stop_at: float in stops:
							for bag_step: float in [2.0, 2.8]:
								var run := _clean_lot(yard, orient, speed, spacing, block_count, stop_at, bag_step)
								if best.is_empty() or _score(run) < _score(best):
									best = run
				times.append(float(best["seconds"]))
				hauls.append(float(best["seconds"]) + float(best["bags"]) * HAUL_SECONDS)
				best_runs.append(best)
				print("[RakePace] pace %.1f m/s seed %d %s: %s" % [speed, seed_value, "x lanes" if orient == 0 else "z lanes", str(best)])
		var mean := 0.0
		var mean_haul := 0.0
		for index: int in times.size():
			mean += times[index] / float(times.size())
			mean_haul += hauls[index] / float(hauls.size())
		print("[RakePace] pace %.1f m/s: mean %.1f s to %.0f%% clean (%.1f s with hauling)" % [speed, mean, CLEAN_TARGET * 100.0, mean_haul])
		out["%.1f" % speed] = {"mean_seconds": snappedf(mean, 0.1), "mean_with_haul": snappedf(mean_haul, 0.1), "runs": best_runs}
	_report["pace"] = out


## Unfinished runs rank behind every finished one.
func _score(run: Dictionary) -> float:
	return float(run["seconds"]) + float(run["bags"]) * HAUL_SECONDS + (0.0 if bool(run["done"]) else 100000.0 * (1.0 - float(run["cleaned"])))


## One raker cleans the yard: passes of lanes into block pile rows, then bagging.
func _clean_lot(yard: PackedByteArray, orient: int, speed: float, spacing: float, block_count: int, stop_at: float, bag_step: float = 2.0) -> Dictionary:
	var field := _field_for(yard)
	var start_clean := _clean_at_start(yard)
	var raker := Raker.new(field)
	var u := Vector3.RIGHT if orient == 0 else Vector3.BACK
	var v := Vector3.BACK if orient == 0 else Vector3.RIGHT
	var block := 40.0 / float(block_count)
	var walk := 0.0
	var bags := 0
	var bagged := 0
	var cleaned := 0.0
	var passes := 0
	var done := false
	for pass_index: int in MAX_PASSES:
		passes += 1
		var shift := spacing * 0.5 * float(pass_index % 2)
		var cross := -20.0 + spacing * 0.5 + shift
		while cross < 20.0:
			for b: int in block_count:
				var lo := -20.0 + block * float(b)
				var mid := lo + block * 0.5
				var hi := lo + block
				# From the low edge in, then from the high edge in. The rake's
				# tines start at the edge; the player stops stop_at short of the row.
				for side: float in [1.0, -1.0]:
					var dir := u * side
					var edge := lo if side > 0.0 else hi
					var start_origin := edge + side * 0.25
					var end_origin := mid - side * stop_at
					if (end_origin - start_origin) * side <= 0.0:
						continue
					# Start a step back, so the first bite (0.12 s in) plants on the edge.
					var a := u * (start_origin - side * (REACH + 0.35)) + v * cross
					var b2 := u * (end_origin - side * REACH) + v * cross
					raker.lift()
					raker.rake_walk(a, b2, speed, dir)
					raker.rake_still(b2, 0.6, dir)
					# Then walk round to the next start (the far edge, or the next block).
					walk += block * 0.5 + 1.0
			cross += spacing
		# Bag every block's row.
		for b: int in block_count:
			var mid := -20.0 + block * (float(b) + 0.5)
			var along := -20.0 + 0.8
			while along < 20.0:
				walk += bag_step
				for attempt: int in 3:
					var spot := _bag_spot(field, u * mid + v * along, u)
					if int(field.call("_units_within", spot, Constants.BAG_RADIUS)) < int(Constants.MIN_BAG_CELLS * 60):
						break
					bagged += int(field.call("_apply_collect", spot, Constants.BAG_RADIUS, false))
					bags += 1
				along += bag_step
		cleaned = _cleaned(field, start_clean)
		if OS.get_cmdline_user_args().has("--map"):
			_print_map(field, "after pass %d (%.3f clean)" % [passes, cleaned])
		if cleaned >= CLEAN_TARGET:
			done = true
			break
	var seconds := raker.t + walk / WALK_SPEED + float(bags) * BAG_SECONDS
	var result := {
		"spacing": spacing, "blocks": block_count, "stop": stop_at, "bag_step": bag_step, "passes": passes, "done": done,
		"cleaned": snappedf(cleaned, 0.001), "seconds": snappedf(seconds, 0.1), "rake_s": snappedf(raker.t, 0.1),
		"bags": bags, "units_per_bag": int(float(bagged) / maxf(1.0, float(bags))), "strokes": raker.strokes,
		"per_stroke": int(float(raker.moved) / maxf(1.0, float(raker.strokes))),
	}
	field.free()
	return result


## The densest spot near a row, the way equipment/rake.gd _pile_spot looks.
func _bag_spot(field: Node3D, around: Vector3, u: Vector3) -> Vector3:
	var best := around
	var most := -1
	for step: int in range(-4, 5):
		var at := around + u * (float(step) * 0.4) + Vector3(0.0, 0.2, 0.0)
		var units := int(field.call("_units_within", at, Constants.BAG_RADIUS))
		if units > most:
			most = units
			best = at
	return best


## --map: the field as text, one character a cell (blank is clean).
func _print_map(field: Node3D, title: String) -> void:
	print("[RakePace] map %s" % title)
	var density: PackedByteArray = field.get("_density")
	for z: int in GRID:
		var line := ""
		for x: int in GRID:
			var d := int(density[x + z * GRID])
			line += " " if d <= 8 else ("." if d <= 30 else (":" if d <= 60 else ("o" if d <= 150 else ("O" if d < 255 else "#"))))
		print("[RakePace] |%s|" % line)

## --width=3.2 rakes with another width (the legacy field's 0.4.7 numbers).
static func _width() -> float:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--width="):
			return float(arg.substr(8))
	return Constants.RAKE_WIDTH