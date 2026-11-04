extends RefCounted

## Authority: none; pure data every peer builds the same way (fx-w9, docs/GAME.md
## "Fences give"). A fence is something Chefty noses into, not a wall it crashes
## on: the town line's hedge has done that since fx-yard (VehicleSim.town_edge);
## this is the same for the job yard's picket fence (levels/lots/lot_generator.gd)
## and the town's own fences in front of and between the yards
## (levels/town/town_colliders.gd, from levels/town/lot_builder.gd fence_lines).
##
## Each fence run is a line on the ground. The vehicle sim (VehicleSim.step, with
## params "fence_give") holds the truck's speed into a line it's pressing against
## under what stops it within FENCE_GIVE_DEPTH past the pickets, drags its slide
## along them, and pushes it gently back out once it's in deep: the fence bows
## and holds. It's a pure function of where the chassis is, so the driver's
## replay matches the host. People and thrown things still stop at the fence's
## own solid (the yard's FenceBody on layer 1, which the chassis is kept out of;
## the town's on PAD_WALL_LAYER, people only). chefty_crash.gd draws the bow (the
## yard's panels lean), the creak and the shake, each peer from its drawn truck.

## The lines are bucketed in square cells this wide (m).
const CELL: float = 16.0

## id -> {a: Vector2, b: Vector2, owner: Object, panels: Array[Node3D]}.
static var _lines: Dictionary = {}
## Vector2i cell -> Array[int] of line ids.
static var _grid: Dictionary = {}
static var _next_id: int = 1
## Bodies a chassis must not meet as walls (the yard's FenceBody), and a count
## that goes up whenever that list changes.
static var _bodies: Array = []
static var revision: int = 0


## A fence run from a to b (world, the ground under it). owner keeps it: freed
## (or a CollisionShape3D turned off, a town slot while it's the job site) and the
## line no longer counts. panels: the drawn panels that lean when it's pushed.
static func add(a: Vector3, b: Vector3, owner: Object, panels: Array = []) -> int:
	var id := _next_id
	_next_id += 1
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	_lines[id] = {"a": a2, "b": b2, "owner": owner, "panels": panels}
	for cell: Vector2i in _cells_along(a2, b2):
		if not _grid.has(cell):
			_grid[cell] = []
		(_grid[cell] as Array).append(id)
	return id


## The fence body a chassis is kept out of (it meets the give instead).
static func add_body(body: PhysicsBody3D) -> void:
	if body != null and not _bodies.has(body):
		_bodies.append(body)
		revision += 1


## Every line (and body) this owner added goes.
static func remove_owner(owner: Object) -> void:
	for id: Variant in _lines.keys():
		if (_lines[id] as Dictionary)["owner"] == owner:
			_remove(int(id))
	if _bodies.has(owner):
		_bodies.erase(owner)
		revision += 1


static func _remove(id: int) -> void:
	var line: Dictionary = _lines.get(id, {})
	if line.is_empty():
		return
	for cell: Vector2i in _cells_along(line["a"], line["b"]):
		if _grid.has(cell):
			(_grid[cell] as Array).erase(id)
	_lines.erase(id)


## Keeps chassis from meeting the registered fence bodies as walls.
static func except_bodies(chassis: PhysicsBody3D) -> void:
	if int(chassis.get_meta(&"fence_rev", -1)) == revision:
		return
	chassis.set_meta(&"fence_rev", revision)
	for body: Variant in _bodies.duplicate():
		if is_instance_valid(body):
			chassis.add_collision_exception_with(body as PhysicsBody3D)
		else:
			_bodies.erase(body)


static func line_count() -> int:
	return _lines.size()


static func _cells_along(a: Vector2, b: Vector2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var low := Vector2i(floori(minf(a.x, b.x) / CELL), floori(minf(a.y, b.y) / CELL))
	var high := Vector2i(floori(maxf(a.x, b.x) / CELL), floori(maxf(a.y, b.y) / CELL))
	for x: int in range(low.x, high.x + 1):
		for y: int in range(low.y, high.y + 1):
			out.append(Vector2i(x, y))
	return out


static func _alive(line: Dictionary) -> bool:
	var owner: Variant = line["owner"]
	if owner == null or not is_instance_valid(owner):
		return false
	if owner is CollisionShape3D and (owner as CollisionShape3D).disabled:
		return false
	return true


## Where the truck's footprint at pos (heading yaw) meets a fence: {clear (m from
## the pickets to the footprint's nearest point on the truck's side; under 0 it's
## pressing in that far), normal (flat, from the fence toward the truck), at (the
## contact point, world), id}. {} with no fence within FENCE_GIVE_BAND.
static func contact(pos: Vector3, yaw: float) -> Dictionary:
	if _lines.is_empty():
		return {}
	var basis := Basis(Vector3.UP, yaw)
	var probes: Array[Vector2] = []
	var hw := Constants.CHEFTY_HALF_WIDTH
	var hl := Constants.CHEFTY_HALF_LENGTH
	for local: Vector3 in [Vector3(-hw, 0.0, -hl), Vector3(hw, 0.0, -hl), Vector3(-hw, 0.0, hl), Vector3(hw, 0.0, hl), Vector3(0.0, 0.0, -hl), Vector3(0.0, 0.0, hl), Vector3(-hw, 0.0, 0.0), Vector3(hw, 0.0, 0.0)]:
		var at := pos + basis * local
		probes.append(Vector2(at.x, at.z))
	var center := Vector2(pos.x, pos.z)
	var seen := {}
	var best := {}
	var best_clear := Constants.FENCE_GIVE_BAND
	var reach := hl + Constants.FENCE_GIVE_BAND
	for cell: Vector2i in _cells_along(center - Vector2(reach, reach), center + Vector2(reach, reach)):
		for id: int in _grid.get(cell, []):
			if seen.has(id):
				continue
			seen[id] = true
			var line: Dictionary = _lines[id]
			if not _alive(line):
				continue
			var a: Vector2 = line["a"]
			var b: Vector2 = line["b"]
			var span := a.distance_to(b)
			if span < 0.05:
				continue
			var along := (b - a) / span
			var normal := Vector2(-along.y, along.x)
			var side := (center - a).dot(normal)
			# The truck's middle must be clearly on one side (a truck straddling a
			# run's end, or parked across a line it never pressed, is left alone).
			if absf(side) < Constants.FENCE_GIVE_MIDDLE_CLEAR:
				continue
			if side < 0.0:
				normal = -normal
			var line_best := {}
			var line_clear := best_clear
			var crossed := false
			for probe: Vector2 in probes:
				var t := (probe - a).dot(along)
				if t < -Constants.FENCE_GIVE_END_SLACK or t > span + Constants.FENCE_GIVE_END_SLACK:
					continue
				var clear := (probe - a).dot(normal)
				# Already well through it (put there: a teleport, a crash's shove): the
				# give never lets a truck get that deep, so this run doesn't hold it,
				# or it would never drive off again.
				if clear < -(Constants.FENCE_GIVE_DEPTH + Constants.FENCE_GIVE_CROSSED):
					crossed = true
					break
				if clear < line_clear:
					line_clear = clear
					var on := a + along * clampf(t, 0.0, span)
					line_best = {"clear": clear, "normal": Vector3(normal.x, 0.0, normal.y), "at": Vector3(on.x, pos.y, on.y), "id": id}
			if not crossed and not line_best.is_empty():
				best_clear = line_clear
				best = line_best
	return best


## The drawn panels of a line (lot_generator's FencePanel holders), [] for none.
static func panels_of(id: int) -> Array:
	return (_lines.get(id, {}) as Dictionary).get("panels", [])


## One step of the give: the truck's velocity after the fence has its say.
static func give(pos: Vector3, yaw: float, vel: Vector3, dt: float) -> Vector3:
	var hit := contact(pos, yaw)
	if hit.is_empty():
		return vel
	var normal: Vector3 = hit["normal"]
	var clear := float(hit["clear"])
	var left := clear + Constants.FENCE_GIVE_DEPTH
	var allow := sqrt(2.0 * Constants.FENCE_GIVE_DECEL * maxf(left, 0.0))
	# Bowed in deep, the fence springs it back out a little.
	var deep := clampf(-clear / Constants.FENCE_GIVE_DEPTH, 0.0, 1.0)
	allow -= Constants.FENCE_GIVE_PUSH_BACK * deep
	var into := -vel.dot(normal)
	if into > allow:
		vel += normal * (into - allow)
	if clear < Constants.FENCE_GIVE_TOUCH:
		var sliding := vel - normal * vel.dot(normal)
		vel -= sliding * (1.0 - exp(-Constants.FENCE_GIVE_SIDE_DRAG * dt))
	return vel
