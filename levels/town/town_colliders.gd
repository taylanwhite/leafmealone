extends Node3D

## Authority: every peer builds the same colliders (net/town/town_map.gd is pure
## data), at world _ready in the connected town. They are global and never
## streamed: the host simulates every vehicle and player wherever they are, and
## each player's own peer moves them, so all of them need the whole town solid.
## Visuals never collide; these boxes stand in for them.
##
## One StaticBody3D "TownStatic" on layer 1: the ground over TownMap.TOWN_BOUNDS
## (its top at y -0.02, a hair under the lot's floor), each yard slot's house and
## tree trunks, each dressing house across the street, street lamps, parked
## cars, the landmarks, the country trees, the lake's low wall, and Marty's
## pallet ramp at Homie Depot. Curbs have no collider: vehicles ride over them.
##
## A yard slot's house comes from the house's seed (the job yard's
## LotGenerator.house_spec), which clients learn with the town's state
## (net/town/town.gd); until then those shapes wait, disabled. While a slot is
## the job site its shapes are off, since the job yard brings its own HouseBody
## (set_slot_enabled).

const _Fallback = preload("res://levels/town/fallback_house.gd")
const GROUND_THICKNESS: float = 0.2
const LAMP_RADIUS: float = 0.15
const LAMP_HEIGHT: float = 5.2
const TRUNK_RADIUS: float = 0.35
const TRUNK_HEIGHT: float = 3.0
const CAR_SIZE := Vector3(1.9, 1.5, 4.3)
const LAKE_WALL_HEIGHT: float = 0.5
## Marty's ramp: how long it runs, how high it gets, and how wide it is.
const RAMP_SIZE := Vector3(3.2, 0.8, 2.4)

var _body: StaticBody3D
## house_id -> Array[CollisionShape3D]; the first is the house.
var _slots: Dictionary = {}
## Yard slots that are the job site right now.
var _off: Dictionary = {}
## What the yard shapes were last built from: a hash of every house's seed and size.
var _built_from: int = 0
var _serial: int = 0


func _ready() -> void:
	name = "TownColliders"
	add_to_group("town_colliders")
	_body = StaticBody3D.new()
	_body.name = "TownStatic"
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)
	var bounds := TownMap.TOWN_BOUNDS
	_add_box("Ground", Vector3(bounds.get_center().x, -0.02 - GROUND_THICKNESS * 0.5, bounds.get_center().z), Vector3(bounds.size.x, GROUND_THICKNESS, bounds.size.z))
	for slot: Dictionary in TownMap.dressing_slots():
		var xform: Transform3D = slot["xform"]
		for solid: Array in _Fallback.colliders(str(slot["hood"]), int(slot["seed"]), int(slot["size"])):
			_add_box("Dressing", xform * (solid[0] as Vector3), solid[1], xform.basis)
	for lamp: Array in TownMap.lamp_spots():
		_add_cylinder("Lamp", (lamp[0] as Vector3) + Vector3(0.0, LAMP_HEIGHT * 0.5, 0.0), LAMP_RADIUS, LAMP_HEIGHT)
	for car: Array in TownMap.car_spots():
		_add_box("Car", (car[0] as Vector3) + Vector3(0.0, CAR_SIZE.y * 0.5, 0.0), CAR_SIZE, Basis(Vector3.UP, float(car[1])))
	for tree: Array in TownMap.country_trees():
		_add_cylinder("Tree", (tree[0] as Vector3) + Vector3(0.0, TRUNK_HEIGHT * 0.5, 0.0), TRUNK_RADIUS, TRUNK_HEIGHT)
	for solid: Array in TownMap.set_piece_solids():
		_add_box("Landmark", solid[0], solid[1], Basis(Vector3.UP, float(solid[2])))
	_lake_wall()
	_ramp()
	for house_id: int in TownMap.house_count():
		_slots[house_id] = []
	var town := get_tree().get_first_node_in_group("town")
	if town != null:
		town.connect("changed", _refresh_yards)
	_refresh_yards()


## The job site's slot (house_id) loses its colliders while on is false.
func set_slot_enabled(house_id: int, on: bool) -> void:
	if on:
		_off.erase(house_id)
	else:
		_off[house_id] = true
	for shape: CollisionShape3D in _slots.get(house_id, []):
		shape.disabled = not on


func is_slot_enabled(house_id: int) -> bool:
	var shapes: Array = _slots.get(house_id, [])
	return not shapes.is_empty() and not (shapes[0] as CollisionShape3D).disabled


## How many yard slots have their house collider on.
func house_shapes_enabled() -> int:
	var count := 0
	for house_id: int in _slots:
		if is_slot_enabled(house_id):
			count += 1
	return count


## Every collider's place and size, hashed, so tests can check each peer built
## the same solid town. Only enabled shapes count.
func layout_hash() -> int:
	var parts: Array = []
	for child: Node in _body.get_children():
		var shape := child as CollisionShape3D
		if shape == null or shape.disabled:
			continue
		var at := shape.position.snappedf(0.01)
		var size := Vector3.ZERO
		if shape.shape is BoxShape3D:
			size = (shape.shape as BoxShape3D).size.snappedf(0.01)
		elif shape.shape is CylinderShape3D:
			size = Vector3((shape.shape as CylinderShape3D).radius, (shape.shape as CylinderShape3D).height, 0.0).snappedf(0.01)
		parts.append(hash([String(child.name).get_slice("_", 0), at, size]))
	# Order-free: peers may build the yard slots at different moments.
	parts.sort()
	return hash(parts)


func shape_count() -> int:
	return _body.get_child_count()


## The yard slots' houses, from the town's seeds, once they're known.
func _refresh_yards() -> void:
	var town := get_tree().get_first_node_in_group("town")
	if town == null:
		return
	var houses: Array = town.get("houses")
	if houses.size() < TownMap.house_count():
		return
	var key_parts: Array = []
	for house_id: int in TownMap.house_count():
		var entry: Dictionary = houses[house_id]
		key_parts.append([int(entry.get("seed", 0)), int(entry.get("size", 1))])
	var key := hash(key_parts)
	if key == _built_from:
		return
	_built_from = key
	for house_id: int in TownMap.house_count():
		for shape: CollisionShape3D in _slots[house_id]:
			_body.remove_child(shape)
			shape.queue_free()
		var shapes: Array = []
		var entry: Dictionary = houses[house_id]
		var xform := TownMap.yard_transform(house_id)
		for solid: Array in _Fallback.colliders(TownMap.hood_id_of(house_id), int(entry.get("seed", 0)), int(entry.get("size", 1))):
			var shape := _add_box("Yard%d" % house_id, xform * (solid[0] as Vector3), solid[1], xform.basis)
			shape.disabled = _off.has(house_id)
			shapes.append(shape)
		_slots[house_id] = shapes


func _add_box(label: String, center: Vector3, size: Vector3, basis: Basis = Basis.IDENTITY) -> CollisionShape3D:
	var box := BoxShape3D.new()
	box.size = size
	var shape := CollisionShape3D.new()
	_serial += 1
	shape.name = "%s_%d" % [label, _serial]
	shape.shape = box
	shape.transform = Transform3D(basis, center)
	_body.add_child(shape)
	return shape


func _add_cylinder(label: String, center: Vector3, radius: float, height: float) -> CollisionShape3D:
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = height
	var shape := CollisionShape3D.new()
	_serial += 1
	shape.name = "%s_%d" % [label, _serial]
	shape.shape = cylinder
	shape.position = center
	_body.add_child(shape)
	return shape


## A knee-high bulkhead around the lake, so nothing drives into it.
func _lake_wall() -> void:
	var lake := TownMap.LAKE
	var middle := lake.get_center()
	var y := LAKE_WALL_HEIGHT * 0.5
	_add_box("Lake", Vector3(middle.x, y, lake.position.y), Vector3(lake.size.x, LAKE_WALL_HEIGHT, 0.4))
	_add_box("Lake", Vector3(middle.x, y, lake.end.y), Vector3(lake.size.x, LAKE_WALL_HEIGHT, 0.4))
	_add_box("Lake", Vector3(lake.position.x, y, middle.y), Vector3(0.4, LAKE_WALL_HEIGHT, lake.size.y))
	_add_box("Lake", Vector3(lake.end.x, y, middle.y), Vector3(0.4, LAKE_WALL_HEIGHT, lake.size.y))


## Marty's nephew's pallet ramp in the parking lot (Constants.STORE_LAYOUT):
## a slope up along its +X and a solid block under the high end.
func _ramp() -> void:
	var entry: Dictionary = Constants.STORE_LAYOUT["marty_ramp"]
	var store := Transform3D.IDENTITY
	var zone := get_parent().get_node_or_null("StoreZone") as Node3D if get_parent() != null else null
	if zone != null:
		store = zone.transform
	var place := store * Transform3D(Basis(Vector3.UP, float(entry["yaw"])), entry["at"])
	for solid: Array in ramp_solids():
		_add_box("Ramp", place * (solid[0] as Vector3), solid[1], place.basis * (solid[2] as Basis))


## The ramp's boxes in its own space: [[center, size, basis]].
static func ramp_solids() -> Array:
	var slope := atan2(RAMP_SIZE.y, RAMP_SIZE.x)
	var length := Vector2(RAMP_SIZE.x, RAMP_SIZE.y).length()
	var thick := 0.16
	return [
		[Vector3(0.0, RAMP_SIZE.y * 0.5 - thick * 0.5 / cos(slope), 0.0), Vector3(length, thick, RAMP_SIZE.z), Basis(Vector3.BACK, slope)],
		[Vector3(RAMP_SIZE.x * 0.375, RAMP_SIZE.y * 0.35, 0.0), Vector3(RAMP_SIZE.x * 0.25, RAMP_SIZE.y * 0.7, RAMP_SIZE.z), Basis.IDENTITY],
	]
