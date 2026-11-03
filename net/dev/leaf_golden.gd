extends RefCounted

## Authority: host. The leaf field's density rules, frozen (raking:1). A scratch
## LeafField (no renderer, no group, its own offline MultiplayerAPI so nothing it
## sends reaches a real peer, parked 1 km under the lot so no player is in reach of
## it) is shaped by a fixed multiplier and then put through 40 scripted ops that
## call the field's real rule code: rake strokes in all 8 directions, a lane of
## them into a pile, bare-hand strokes, blower strokes at tiers 1-3, hired-hand
## strokes at skill 0.3/0.7/1.0, bagging, a burst bag's scatter and the mower's
## mulch. Every op's result, the field's hash, leaf_units() and cleaned_fraction()
## must equal RECORDED. raking:1 recorded it from the unmodified 0.4.5 field;
## rakefeel:field (R1b) changed the stroke rule on purpose (the windrow: a stroke as
## wide as the head, a berm just ahead of the tines, the drag between strokes, no
## direction bias) and re-recorded it, adding ops 41-50 for the drag, the two bites,
## a wide tier head and a hired hand's full head. Anything that changes a rule on
## purpose (driving:C3's plow if it ever routes through _stroke_cells) regenerates
## RECORDED: empty RECORDED and run --rake-net-test; the host prints the new literal.
## Only arithmetic (no sin/exp) shapes the field, so CI's Linux run and a
## Windows run get the same bytes.

const _FieldScript: Script = preload("res://net/leaf_field/leaf_field.gd")
const _ToolTiers = preload("res://core/tool_tiers.gd")

## Recorded by rakefeel:field (R1b) from the windrow rule.
const RECORDED: Dictionary = {
	"hash": "0c18c8bcdd19e7220700ab8fa2084febb4a2077b156f57fdabb7ce64599e6d35",
	"leaf_units": 5199.291667,
	"cleaned": 0.04333119,
	"moved": [220, 186, 221, 148, 230, 159, 363, 159, 217, 247, 342, 423, 507, 591, 669, 755, 36, 36, 30, 383, 177, 166,
		230, 266, 364, 229, 265, 361, 2110, 2303, 441, 10751, 5733, 147, 74, 0, 1171, 1563, 114, 216, 114, 344, 371, 702,
		625, 1074, 210, 215, 558, 741],
	"params": "[[1.2, 72.0, 3], [1.0, 0.8, 1], [2.4, 45.0, 6], [2.76, 60.75, 6], [3.12, 81.0, 9], [1.2, 21.6, 3], [1.2, 50.4, 3], [1.2, 72.0, 3], [1.70526315789474, 131.22, 3]]",
}

## Runs the golden ops under parent (the host's test node) and frees everything
## again. Returns {ok, why, hash, leaf_units, cleaned, moved, params}.
static func run(parent: Node) -> Dictionary:
	var tree := parent.get_tree()
	var branch := Node3D.new()
	branch.name = "LeafGoldenScratch"
	parent.add_child(branch)
	branch.global_position = Vector3(0.0, -1000.0, 0.0)
	var api := MultiplayerAPI.create_default_interface()
	tree.set_multiplayer(api, branch.get_path())
	var field := _FieldScript.new() as Node3D
	# raking:1's scratch switch (no group, no peers, no RPCs); a no-op on 0.4.5.
	field.set("scratch", true)
	field.name = "Field"
	branch.add_child(field)
	if field.is_in_group("leaf_field"):
		field.remove_from_group("leaf_field")
	field.set_process(false)
	var report := _ops(field)
	tree.set_multiplayer(null, branch.get_path())
	branch.queue_free()
	report["ok"] = false
	if RECORDED.is_empty():
		report["why"] = "not recorded"
		print("[LeafGolden] RECORD: %s" % _literal(report))
		return report
	var problems: Array[String] = []
	if str(report["params"]) != str(RECORDED.get("params")):
		problems.append("tuning changed (stroke params %s, recorded %s): regenerate RECORDED on purpose" % [report["params"], RECORDED.get("params")])
	var moved: Array = report["moved"]
	var want: Array = RECORDED.get("moved")
	for index: int in mini(moved.size(), want.size()):
		if int(moved[index]) != int(want[index]):
			problems.append("op %d moved %d, recorded %d" % [index + 1, int(moved[index]), int(want[index])])
	if moved.size() != want.size():
		problems.append("%d ops, recorded %d" % [moved.size(), want.size()])
	if str(report["hash"]) != str(RECORDED.get("hash")):
		problems.append("density hash %s, recorded %s" % [report["hash"], RECORDED.get("hash")])
	if absf(float(report["leaf_units"]) - float(RECORDED.get("leaf_units"))) > 0.0001:
		problems.append("leaf_units %.6f, recorded %.6f" % [float(report["leaf_units"]), float(RECORDED.get("leaf_units"))])
	if absf(float(report["cleaned"]) - float(RECORDED.get("cleaned"))) > 0.000001:
		problems.append("cleaned_fraction %.8f, recorded %.8f" % [float(report["cleaned"]), float(RECORDED.get("cleaned"))])
	report["ok"] = problems.is_empty()
	report["why"] = "; ".join(problems)
	return report


static func _ops(field: Node3D) -> Dictionary:
	field.call("shape_initial", func(world: Vector3) -> float: return _multiplier(field.to_local(world)))
	var moved: Array[int] = []
	var params: Array = []
	var rake := [Constants.RAKE_WIDTH, Constants.RAKE_STRENGTH, Constants.RAKE_STROKE_CELLS]
	var hand := [Constants.HAND_RAKE_WIDTH, Constants.HAND_RAKE_STRENGTH, 1]
	params.append(rake)
	params.append(hand)
	# 1-8: a rake stroke in each of the 8 directions.
	var dirs: Array[Vector3] = [Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1), Vector3(-1, 0, 1),
		Vector3(-1, 0, 0), Vector3(-1, 0, -1), Vector3(0, 0, -1), Vector3(1, 0, -1)]
	for index: int in dirs.size():
		moved.append(_stroke(field, Vector3(-12.0 + 3.0 * float(index), 0.0, 2.0), dirs[index], rake))
	# 9-16: a lane toward +X, into a pile.
	for index: int in 8:
		moved.append(_stroke(field, Vector3(-14.0 + 0.5 * float(index), 0.0, 8.0), Vector3.RIGHT, rake))
	# 17-19: bare hands.
	for dir: Vector3 in [Vector3.RIGHT, Vector3.FORWARD, Vector3(1, 0, -1)]:
		moved.append(_stroke(field, Vector3(10.0, 0.0, -4.0), dir, hand))
	# 20-22: the leaf blower at tiers 1-3, exactly as _handle_rake clamps it.
	for tier: int in [1, 2, 3]:
		var scale := _ToolTiers.speed(tier)
		var blower := [minf(Constants.BLOWER_WIDTH * _ToolTiers.reach(tier), Constants.BLOWER_WIDTH * _ToolTiers.reach(tier)),
			minf(Constants.BLOWER_STRENGTH * scale, Constants.BLOWER_STRENGTH * scale), _ToolTiers.blower_cells(tier)]
		params.append(blower)
		moved.append(_stroke(field, Vector3(-7.0 + float(tier), 0.0, -6.0), Vector3.BACK, blower))
	# 23-25: a hired hand at skill 0.3, 0.7 and 1.0 (host_hand_rake's numbers).
	for index: int in 3:
		var skill: float = [0.3, 0.7, 1.0][index]
		var crew := [Constants.RAKE_WIDTH, Constants.RAKE_STRENGTH * clampf(skill, 0.3, 1.0), Constants.RAKE_STROKE_CELLS]
		params.append(crew)
		moved.append(_stroke(field, Vector3(12.0 - 0.5 * float(index), 0.0, 10.0), Vector3.LEFT, crew))
	# 26-28: toward -Z (0.4.5's in-place cascade carried leaves half as far this way).
	for index: int in 3:
		moved.append(_stroke(field, Vector3(5.0, 0.0, 14.0 - 0.5 * float(index)), Vector3.FORWARD, rake))
	# 29-31: bagging: the lane's pile, a contractor bag's wider scoop, a thin spot.
	moved.append(int(field.call("_apply_collect", _at(field, Vector3(-9.0, 0.0, 8.0)), Constants.BAG_RADIUS, false)))
	moved.append(int(field.call("_apply_collect", _at(field, Vector3(5.0, 0.0, 11.0)), Constants.BAG_RADIUS * Constants.BIG_BAG_RADIUS_SCALE, false)))
	moved.append(int(field.call("_apply_collect", _at(field, Vector3(15.0, 0.0, -15.0)), 1.0, false)))
	# 32-33: burst bags scatter back onto the lawn (the units actually added).
	for scatter: Array in [[Vector3(0.0, 0.0, -3.0), 40], [Vector3(-15.0, 0.0, 15.0), 12]]:
		var before := _total(field)
		field.call("host_scatter", _at(field, scatter[0] as Vector3), 1.8, int(scatter[1]))
		moved.append(_total(field) - before)
	# 34-36: the mower mulches.
	for index: int in 3:
		moved.append(int(field.call("host_mulch", _at(field, Vector3(13.0 + 0.3 * float(index), 0.0, -11.0)), 0.6)))
	# 37-38: diagonal strokes over the scattered leaves.
	moved.append(_stroke(field, Vector3(-1.0, 0.0, -4.0), Vector3(1, 0, 1), rake))
	moved.append(_stroke(field, Vector3(-0.5, 0.0, -3.5), Vector3(1, 0, 1), rake))
	# 39-40: off both X edges of the grid.
	moved.append(_stroke(field, Vector3(19.2, 0.0, 0.0), Vector3.RIGHT, rake))
	moved.append(_stroke(field, Vector3(-19.5, 0.0, 5.0), Vector3.LEFT, rake))
	# 41-46: a walked run toward -X, the swing's two bites, dragged between strokes
	# (_stroke_drag: 0.45 m between a swing's bites, 1.05 m to the next swing's plant).
	var walk := Vector3(16.0, 0.0, 16.0)
	for index: int in 6:
		var at := _at(field, walk)
		var drag := float(field.call("_stroke_drag", 1, at, Vector3.LEFT))
		moved.append(_stroke(field, walk, Vector3.LEFT, rake, drag, index % 2))
		walk += Vector3.LEFT * (0.45 if index % 2 == 0 else 1.05)
	# 47: The Leafinator's wider head.
	var wide := [Constants.RAKE_WIDTH * Constants.RAKE_HEAD_WIDTHS[2] / Constants.RAKE_HEAD_WIDTHS[0], Constants.RAKE_STRENGTH * Balance.TOOL_THROUGHPUT_GROWTH_MULTIPLIER * Balance.TOOL_THROUGHPUT_GROWTH_MULTIPLIER, Constants.RAKE_STROKE_CELLS]
	params.append(wide)
	moved.append(_stroke(field, Vector3(0.0, 0.0, 17.0), Vector3(1, 0, -1), wide))
	# 48-50: a weak hired hand walking a run toward +Z until its head is full.
	var hand_at := Vector3(-16.0, 0.0, -18.0)
	var weak := [Constants.RAKE_WIDTH, Constants.RAKE_STRENGTH * 0.3, Constants.RAKE_STROKE_CELLS]
	for index: int in 3:
		var drag := float(field.call("_stroke_drag", 1001, _at(field, hand_at), Vector3.BACK))
		moved.append(_stroke(field, hand_at, Vector3.BACK, weak, drag))
		hand_at += Vector3.BACK * 1.4
	var density: PackedByteArray = field.get("_density")
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(density)
	return {
		"hash": hashing.finish().hex_encode(),
		"leaf_units": float(field.call("leaf_units")),
		"cleaned": float(field.call("cleaned_fraction")),
		"moved": moved,
		"params": str(params),
	}


static func _stroke(field: Node3D, local: Vector3, dir: Vector3, params: Array, drag: float = 0.0, bite: int = -1) -> int:
	return int(field.call("_stroke_cells", _at(field, local), dir.normalized(), float(params[0]), float(params[1]), int(params[2]), drag, bite))


static func _at(field: Node3D, local: Vector3) -> Vector3:
	return field.to_global(Vector3(local.x, 0.25, local.z))


static func _total(field: Node3D) -> int:
	var total := 0
	for byte: int in (field.get("_density") as PackedByteArray):
		total += byte
	return total


## A yard shaped from arithmetic only: thin lawn (0.6) with a ripple, two trees'
## drifts, and a house footprint with no leaves.
static func _multiplier(local: Vector3) -> float:
	if local.x > -4.0 and local.x < 4.0 and local.z > -14.0 and local.z < -8.0:
		return 0.0
	var value := 0.6 + 0.004 * float(int(local.x * 7.0 + local.z * 3.0) % 9)
	value += 1.8 * _bump(local, Vector2(6.0, 5.0), 4.0)
	value += 1.2 * _bump(local, Vector2(-9.0, -2.0), 5.0)
	return value


static func _bump(local: Vector3, center: Vector2, radius: float) -> float:
	var dx := local.x - center.x
	var dz := local.z - center.y
	var t := 1.0 - (dx * dx + dz * dz) / (radius * radius)
	return t * t if t > 0.0 else 0.0


static func _literal(report: Dictionary) -> String:
	return "{\"hash\": \"%s\", \"leaf_units\": %.6f, \"cleaned\": %.8f, \"moved\": %s, \"params\": \"%s\"}" % [
		report["hash"], float(report["leaf_units"]), float(report["cleaned"]), str(report["moved"]), str(report["params"]).replace("\"", "\\\"")]
