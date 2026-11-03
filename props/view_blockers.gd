extends RefCounted

## Authority: local, cosmetic (driving chunk E2). What a camera must not sit
## inside but nothing collides with: tree crowns. A crown has no collider (Chefty
## and everyone walk under it, leaves and rakes pass through it), so it can't be
## on a physics layer every ray in the game would hit; instead each tree
## (props/tree_node.gd) adds its crown here as an upright ellipsoid in world
## space when it enters the tree and takes it out when it leaves. Chefty's chase
## camera (player/vehicle_camera.gd) sweeps its boom against these as well as the
## world's colliders, and fades a crown its lens ends up inside anyway.
##
## A flat grid of Constants.VIEW_BLOCKER_CELL meters cells keeps a query to the
## few crowns near the boom. A crown whose owner is hidden (a parcel under the
## job yard, a LOD level faded out) never blocks.

## Vector2i cell -> Array of entries; entry: {owner, center, radii}.
static var _cells: Dictionary = {}
## owner instance id -> [entry, Array[Vector2i] cells]
static var _by_owner: Dictionary = {}


## Adds (or moves) owner's crown: an ellipsoid at center (world) with radii.
static func add(owner: Node3D, center: Vector3, radii: Vector3) -> void:
	remove(owner)
	var entry := {"owner": owner, "center": center, "radii": radii}
	var cells: Array[Vector2i] = []
	var size := Constants.VIEW_BLOCKER_CELL
	var low := Vector2i(floori((center.x - radii.x) / size), floori((center.z - radii.z) / size))
	var high := Vector2i(floori((center.x + radii.x) / size), floori((center.z + radii.z) / size))
	for x: int in range(low.x, high.x + 1):
		for z: int in range(low.y, high.y + 1):
			var cell := Vector2i(x, z)
			if not _cells.has(cell):
				_cells[cell] = []
			(_cells[cell] as Array).append(entry)
			cells.append(cell)
	_by_owner[owner.get_instance_id()] = [entry, cells]


static func remove(owner: Object) -> void:
	var id := owner.get_instance_id()
	var held: Array = _by_owner.get(id, [])
	if held.is_empty():
		return
	_by_owner.erase(id)
	for cell: Vector2i in held[1]:
		var list: Array = _cells.get(cell, [])
		list.erase(held[0])
		if list.is_empty():
			_cells.erase(cell)


static func count() -> int:
	return _by_owner.size()


## The crowns (entries) whose cells touch the flat box around a and b, grown by pad.
static func _near(a: Vector3, b: Vector3, pad: float) -> Array:
	var size := Constants.VIEW_BLOCKER_CELL
	var low := Vector2i(floori((minf(a.x, b.x) - pad) / size), floori((minf(a.z, b.z) - pad) / size))
	var high := Vector2i(floori((maxf(a.x, b.x) + pad) / size), floori((maxf(a.z, b.z) + pad) / size))
	var out: Array = []
	var seen := {}
	for x: int in range(low.x, high.x + 1):
		for z: int in range(low.y, high.y + 1):
			for entry: Dictionary in _cells.get(Vector2i(x, z), []):
				var owner: Variant = entry["owner"]
				if not is_instance_valid(owner):
					continue
				var id := (owner as Object).get_instance_id()
				if seen.has(id):
					continue
				seen[id] = true
				if (owner as Node3D).is_visible_in_tree():
					out.append(entry)
	return out


## How far along from -> to (0..1) a sphere of radius pad first touches a crown;
## 1.0 when it touches none. Crowns that already hold from are left out: pulling
## in can't get out of them (the camera fades those instead, inside()).
static func sweep(from: Vector3, to: Vector3, pad: float) -> float:
	var best := 1.0
	for entry: Dictionary in _near(from, to, pad):
		var radii: Vector3 = (entry["radii"] as Vector3) + Vector3.ONE * pad
		var center: Vector3 = entry["center"]
		# In the ellipsoid's unit-sphere space the sweep is a ray against a sphere.
		var start := (from - center) / radii
		if start.length_squared() <= 1.0:
			continue
		var along := (to - from) / radii
		var a := along.length_squared()
		if a < 0.000001:
			continue
		var b := 2.0 * start.dot(along)
		var c := start.length_squared() - 1.0
		var disc := b * b - 4.0 * a * c
		if disc < 0.0:
			continue
		var t := (-b - sqrt(disc)) / (2.0 * a)
		if t >= 0.0 and t < best:
			best = t
	return best


## The crowns point is inside (grown by pad): [[owner, depth]], depth 0 at the
## grown edge to 1 at the middle.
static func inside(point: Vector3, pad: float) -> Array:
	var out: Array = []
	for entry: Dictionary in _near(point, point, pad):
		var radii: Vector3 = (entry["radii"] as Vector3) + Vector3.ONE * pad
		var local := (point - (entry["center"] as Vector3)) / radii
		var reach := local.length()
		if reach < 1.0:
			out.append([entry["owner"], 1.0 - reach])
	return out
