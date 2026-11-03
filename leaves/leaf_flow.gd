class_name LeafFlow
extends RefCounted

## Authority: local presentation, pure. Explains one frame's leaf-field changes
## as leaves going somewhere: which losses fed which gains, which leaves went into
## a bag or a mower, which came out of a burst bag, and which changes nothing
## explains (docs/DECISIONS.md 2026-11-02 "Leaf motion").
##
## solve(changes, hints, view, grid) -> {
##   transfers: [{src: Vector2i, dst: Vector2i, units: int, hint: int}],
##   sinks: [{src: Vector2i, units: int, to: Vector3, kind: String, hint: int}],
##   sources: [{dst: Vector2i, units: int, from: Vector3, kind: String, hint: int}],
##   drops: [{dst: Vector2i, units: int}],
##   fades: [{src: Vector2i, units: int}],
## }
## changes: flat (x, z, delta) triples (contract C3 targets_changed). hints: stroke
## events (contract C1 keys) that may explain them. view: the leaf view (only
## cell_center_world is used). grid: the field's size in cells.

## Kinds that push leaves along the stroke's 8-way step (leaf_field.gd _apply_rake).
const DIRECTIONAL: Array[String] = ["rake", "hand", "blower", "crew_rake", "plow"]
## Kinds whose losses go into something (a bag, a mower deck).
const SINKS: Array[String] = ["bag", "crew_bag", "mulch"]
## Kinds whose gains come out of something (a burst bag).
const SOURCES: Array[String] = ["scatter"]
## Kind of the sinks that slide off the edge of the yard.
const EDGE: String = "edge"


static func solve(changes: PackedInt32Array, hints: Array, view: Object, grid: Vector2i) -> Dictionary:
	var out := {"transfers": [], "sinks": [], "sources": [], "drops": [], "fades": []}
	var count := changes.size() / 3
	if count == 0:
		return out
	# Which hint explains each changed cell: the newest one whose reach covers it.
	var groups: Dictionary = {}
	for index: int in count:
		var cell := Vector2i(changes[index * 3], changes[index * 3 + 1])
		var delta := changes[index * 3 + 2]
		if delta == 0:
			continue
		var owner := _owner_hint(cell, hints, view)
		if not groups.has(owner):
			groups[owner] = []
		(groups[owner] as Array).append([cell, delta])
	var left_losses: Array = []
	var left_gains: Array = []
	for owner: int in groups:
		var cells: Array = groups[owner]
		if owner < 0:
			_split(cells, left_losses, left_gains, Vector3.ZERO, -1)
			continue
		var hint: Dictionary = hints[owner]
		var kind := str(hint.get("kind", ""))
		var dir := _flat_dir(hint)
		if DIRECTIONAL.has(kind):
			_transport(cells, _step_of(hint), dir, owner, grid, view, out, left_losses, left_gains)
		elif SINKS.has(kind):
			var to: Vector3 = hint.get("at", Vector3.ZERO)
			if kind != "mulch":
				to += Vector3(0.0, Constants.LEAF_BAG_MOUTH, 0.0)
			for entry: Array in cells:
				if int(entry[1]) < 0:
					(out["sinks"] as Array).append({"src": entry[0], "units": -int(entry[1]), "to": to, "kind": kind, "hint": owner})
				else:
					left_gains.append([entry[0], int(entry[1]), dir, owner])
		elif SOURCES.has(kind):
			var from: Vector3 = hint.get("at", Vector3.ZERO)
			for entry: Array in cells:
				if int(entry[1]) > 0:
					(out["sources"] as Array).append({"dst": entry[0], "units": int(entry[1]), "from": from, "kind": kind, "hint": owner})
				else:
					left_losses.append([entry[0], -int(entry[1]), dir, owner])
		else:
			_split(cells, left_losses, left_gains, dir, owner)
	_match(left_losses, left_gains, view, out)
	return out


## An integer avalanche hash of a cell and a salt, the same on every peer:
## non-negative, 31 bits.
static func hash(x: int, z: int, k: int) -> int:
	var value := (x * 73856093) ^ (z * 19349663) ^ (k * 83492791) ^ 0x2545F491
	value = ((value ^ (value >> 16)) * 0x45d9f3b) & 0xffffffff
	value = ((value ^ (value >> 16)) * 0x45d9f3b) & 0xffffffff
	value = value ^ (value >> 16)
	return value & 0x7fffffff


## Units moved by a solution's transfers (for tests and stats).
static func transfer_units(solution: Dictionary) -> int:
	var total := 0
	for transfer: Dictionary in solution["transfers"]:
		total += int(transfer["units"])
	return total


static func _owner_hint(cell: Vector2i, hints: Array, view: Object) -> int:
	var best := -1
	var center: Vector3 = view.call("cell_center_world", cell)
	for index: int in range(hints.size() - 1, -1, -1):
		var hint: Dictionary = hints[index]
		var at: Vector3 = hint.get("at", Vector3.ZERO)
		var reach := reach_of(hint)
		var dx := center.x - at.x
		var dz := center.z - at.z
		if dx * dx + dz * dz <= reach * reach:
			best = index
			break
	return best


## How far from its point a stroke event can have changed the field (m): its disc,
## the passes' advance, and a metre of cascade.
static func reach_of(hint: Dictionary) -> float:
	var width := float(hint.get("width", 1.0))
	var cells := int(hint.get("cells", 1))
	var kind := str(hint.get("kind", ""))
	if kind == "bag" or kind == "crew_bag" or kind == "mulch":
		return maxf(width, Constants.BAG_RADIUS * Constants.BIG_BAG_RADIUS_SCALE) + 0.5
	if kind == "scatter":
		return maxf(width, 1.0) + 0.75
	return width * 0.5 + float(cells) * 0.5 + 1.0


static func _flat_dir(hint: Dictionary) -> Vector3:
	var dir: Vector3 = hint.get("dir", Vector3.ZERO)
	dir.y = 0.0
	return dir.normalized() if dir.length() > 0.001 else Vector3.ZERO


## The field's own 8-way step for a stroke (leaf_field.gd _apply_rake).
static func _step_of(hint: Dictionary) -> Vector2i:
	if hint.has("step"):
		var given: Vector2i = hint["step"]
		if given != Vector2i.ZERO:
			return given
	var flat := _flat_dir(hint)
	var step := Vector2i(int(round(flat.x)), int(round(flat.z)))
	return step if step != Vector2i.ZERO else Vector2i(0, 1)


static func _split(cells: Array, losses: Array, gains: Array, dir: Vector3, owner: int) -> void:
	for entry: Array in cells:
		var delta := int(entry[1])
		if delta < 0:
			losses.append([entry[0], -delta, dir, owner])
		elif delta > 0:
			gains.append([entry[0], delta, dir, owner])


## Monotone transport along the stroke's step: cells on one line parallel to the
## step, walked back to front; each gain is fed from the earliest losses behind it
## (the k-th unit lost goes to the k-th unit gained, as _apply_rake's cascade does).
static func _transport(cells: Array, step: Vector2i, dir: Vector3, owner: int, grid: Vector2i, view: Object, out: Dictionary, left_losses: Array, left_gains: Array) -> void:
	var lines: Dictionary = {}
	for entry: Array in cells:
		var cell: Vector2i = entry[0]
		var key := cell.x * step.y - cell.y * step.x
		if not lines.has(key):
			lines[key] = []
		(lines[key] as Array).append(entry)
	for key: int in lines:
		var line: Array = lines[key]
		line.sort_custom(func(a: Array, b: Array) -> bool:
			var ca: Vector2i = a[0]
			var cb: Vector2i = b[0]
			return ca.x * step.x + ca.y * step.y < cb.x * step.x + cb.y * step.y)
		var stock: Array = []
		for entry: Array in line:
			var cell: Vector2i = entry[0]
			var delta := int(entry[1])
			if delta < 0:
				stock.append([cell, -delta])
				continue
			var want := delta
			while want > 0 and not stock.is_empty():
				var head: Array = stock[0]
				var take := mini(want, int(head[1]))
				(out["transfers"] as Array).append({"src": head[0], "dst": cell, "units": take, "hint": owner})
				want -= take
				head[1] = int(head[1]) - take
				if int(head[1]) <= 0:
					stock.pop_front()
			if want > 0:
				left_gains.append([cell, want, dir, owner])
		if stock.is_empty():
			continue
		# Losses with nothing ahead to land in: pushed off the yard's edge, or left
		# for the nearest-gain pass.
		var front: Vector2i = (line[line.size() - 1] as Array)[0]
		var beyond := front + step
		var off_edge := beyond.x < 0 or beyond.y < 0 or beyond.x >= grid.x or beyond.y >= grid.y
		for rest: Array in stock:
			if off_edge:
				var from: Vector3 = view.call("cell_center_world", rest[0])
				(out["sinks"] as Array).append({"src": rest[0], "units": int(rest[1]), "to": from + dir * 1.2, "kind": EDGE, "hint": owner})
			else:
				left_losses.append([rest[0], int(rest[1]), dir, owner])


## Greedy nearest matching of what is left: cheapest pairs first, where cost is the
## distance less half of how far the gain lies along the stroke.
static func _match(losses: Array, gains: Array, view: Object, out: Dictionary) -> void:
	if not losses.is_empty() and not gains.is_empty():
		var pairs: Array = []
		var gain_at: Array[Vector3] = []
		for gain: Array in gains:
			gain_at.append(view.call("cell_center_world", gain[0]))
		for li: int in losses.size():
			var loss: Array = losses[li]
			var from: Vector3 = view.call("cell_center_world", loss[0])
			var dir: Vector3 = loss[2]
			for gi: int in gains.size():
				var offset := gain_at[gi] - from
				offset.y = 0.0
				var dist := offset.length()
				if dist > Constants.LEAF_FLOW_MAX_DIST:
					continue
				var along_dir: Vector3 = dir if dir != Vector3.ZERO else gains[gi][2]
				pairs.append([dist - 0.5 * offset.dot(along_dir), li, gi])
		pairs.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		for pair: Array in pairs:
			var loss: Array = losses[int(pair[1])]
			var gain: Array = gains[int(pair[2])]
			var take := mini(int(loss[1]), int(gain[1]))
			if take <= 0:
				continue
			var owner := int(loss[3]) if int(loss[3]) >= 0 else int(gain[3])
			(out["transfers"] as Array).append({"src": loss[0], "dst": gain[0], "units": take, "hint": owner})
			loss[1] = int(loss[1]) - take
			gain[1] = int(gain[1]) - take
	for loss: Array in losses:
		if int(loss[1]) > 0:
			(out["fades"] as Array).append({"src": loss[0], "units": int(loss[1])})
	for gain: Array in gains:
		if int(gain[1]) > 0:
			(out["drops"] as Array).append({"dst": gain[0], "units": int(gain[1])})
