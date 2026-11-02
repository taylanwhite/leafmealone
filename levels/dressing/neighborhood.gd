extends RefCounted

## Authority: local, cosmetic. The street the job lot sits on, so the yard reads
## as one house on a real block instead of a pad in a field: a road along the
## front with curbs, sidewalks, and center lines, a driveway Chefty pulls into,
## neighbor houses on both sides and across the street with their own yards,
## fences, and trees, hedges between yards, street lamps, mailboxes, and a parked
## car. Built in the lot zone's space: the yard is x and z in -20..20, its front
## at z = +20. Seeded, so every peer sees the same block. Nothing here collides;
## the pad's walls (levels/world.gd) keep players in the yard.

const _LowPoly = preload("res://props/low_poly.gd")
const _Trees = preload("res://props/trees.gd")
const _YardModels = preload("res://props/yard_models.gd")
const _Grass = preload("res://props/grass.gd")
const _Surfaces = preload("res://props/surfaces.gd")
const _HouseBuilder = preload("res://levels/town/house_builder.gd")

## The street runs along x in front of the yard.
const SIDEWALK_NEAR := Vector2(20.3, 22.3)
const STREET := Vector2(22.6, 31.4)
const SIDEWALK_FAR := Vector2(31.7, 33.7)
const STREET_LENGTH: float = 260.0
const ASPHALT := Color(0.3, 0.3, 0.32)
const CONCRETE := Color(0.72, 0.7, 0.66)
## Center-line dashes, meters long, on a period of twice that (props/surfaces.gd "road").
const DASH: float = 3.0
const HEDGE := Color(0.24, 0.42, 0.22)
const PICKET := Color(0.92, 0.9, 0.84)
const WALLS: Array[Color] = [
	Color(0.86, 0.79, 0.62), Color(0.6, 0.71, 0.8), Color(0.82, 0.6, 0.5),
	Color(0.73, 0.8, 0.62), Color(0.9, 0.86, 0.78), Color(0.7, 0.62, 0.78),
]
const ROOFS: Array[Color] = [Color(0.36, 0.25, 0.22), Color(0.3, 0.32, 0.36), Color(0.45, 0.27, 0.2), Color(0.28, 0.3, 0.26)]
const TRIMS: Array[Color] = [Color(0.95, 0.94, 0.9), Color(0.25, 0.3, 0.28), Color(0.95, 0.94, 0.9)]
const CROWNS: Array[String] = ["orange", "red", "yellow", "rust", "turning"]


static func dress(zone: Node3D, seed_value: int) -> void:
	var root := Node3D.new()
	root.name = "Neighborhood"
	zone.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_street(root)
	_driveway(root)
	# No grass through the street, the yard's driveway, or the yard's house.
	_Grass.keep_clear(zone, Rect2(-STREET_LENGTH * 0.5, SIDEWALK_NEAR.x - 0.1, STREET_LENGTH, SIDEWALK_FAR.y - SIDEWALK_NEAR.x + 0.2))
	_Grass.keep_clear(zone, Rect2(-2.2, 4.0, 4.4, 16.5))
	_Grass.keep_clear(zone, Rect2(-12.6, -9.6, 9.2, 7.2))
	# Neighbors on this side of the street, past the hedges.
	for side: float in [-1.0, 1.0]:
		_neighbor(root, rng, Vector3(side * 44.0, 0.0, 0.0), 0.0)
		_neighbor(root, rng, Vector3(side * 88.0, 0.0, 0.0), 0.0)
		_hedge_row(root, Vector3(side * 21.2, 0.0, -1.0), 40.0)
	# And across the street, facing back.
	for x: float in [-66.0, -22.0, 22.0, 66.0]:
		_neighbor(root, rng, Vector3(x, 0.0, 56.0), PI)
	# A back fence line behind the yards.
	for x: float in range(-110, 111, 4):
		_fence_panel(root, Vector3(float(x), 0.0, -24.0))
	for index: int in 10:
		var x := -100.0 + float(index) * 22.0 + rng.randf_range(-4.0, 4.0)
		var crown: String = CROWNS[rng.randi() % CROWNS.size()]
		_Trees.spawn(root, Vector3(x, 0.0, -30.0 - rng.randf_range(0.0, 8.0)), rng.randf_range(7.5, 10.0), "broadleaf" if rng.randf() < 0.7 else "pine", crown, index, false, rng.randf() * TAU)
	# Street trees and lamps along the far sidewalk, lamps on this side too.
	for x: float in range(-120, 121, 24):
		_lamp(root, Vector3(float(x) + 6.0, 0.0, SIDEWALK_NEAR.y - 0.35), PI)
		_lamp(root, Vector3(float(x) - 6.0, 0.0, SIDEWALK_FAR.x + 0.35), 0.0)
	for x: float in range(-110, 111, 24):
		if absf(float(x)) < 8.0:
			continue
		_Trees.spawn(root, Vector3(float(x), 0.0, SIDEWALK_FAR.y + 1.6), rng.randf_range(6.5, 8.5), "broadleaf", CROWNS[rng.randi() % CROWNS.size()], int(x) + 40, false, rng.randf() * TAU)
	_parked_car(root, Vector3(-34.0, 0.0, STREET.y - 1.4), Color(0.25, 0.45, 0.62))
	_parked_car(root, Vector3(47.0, 0.0, STREET.y - 1.4), Color(0.85, 0.82, 0.74))
	_mailbox(root, Vector3(3.2, 0.0, SIDEWALK_NEAR.x - 0.4), Color(0.25, 0.3, 0.42))


static func _street(root: Node3D) -> void:
	var center := (STREET.x + STREET.y) * 0.5
	var width := STREET.y - STREET.x
	# Asphalt with a dashed double center line, painted by the road surface.
	var street := _LowPoly.box(root, Vector3(STREET_LENGTH, 0.1, width), Vector3(0.0, -0.04, center), ASPHALT)
	street.name = "Street"
	_LowPoly.paint(street, "road", _Surfaces.road_params("double_yellow", width * 0.5, DASH))
	for span: Vector2 in [SIDEWALK_NEAR, SIDEWALK_FAR]:
		_LowPoly.paint(_LowPoly.box(root, Vector3(STREET_LENGTH, 0.16, span.y - span.x), Vector3(0.0, 0.02, (span.x + span.y) * 0.5), CONCRETE), "concrete")
	# Curbs: a lip between each sidewalk and the road.
	for z: float in [SIDEWALK_NEAR.y + 0.15, SIDEWALK_FAR.x - 0.15]:
		_LowPoly.paint(_LowPoly.box(root, Vector3(STREET_LENGTH, 0.2, 0.3), Vector3(0.0, 0.0, z), CONCRETE.darkened(0.08)), "concrete")


## The yard's driveway, from the street to where Chefty parks.
static func _driveway(root: Node3D) -> void:
	_LowPoly.paint(_LowPoly.box(root, Vector3(4.2, 0.06, 2.6), Vector3(0.0, 0.03, SIDEWALK_NEAR.x + 1.0), CONCRETE.darkened(0.05)), "concrete")


static func _neighbor(root: Node3D, rng: RandomNumberGenerator, at: Vector3, yaw: float) -> void:
	var lot := Node3D.new()
	lot.name = "NeighborLot"
	root.add_child(lot)
	lot.position = at
	lot.rotation.y = yaw
	var wall: Color = WALLS[rng.randi() % WALLS.size()]
	var roof: Color = ROOFS[rng.randi() % ROOFS.size()]
	var trim: Color = TRIMS[rng.randi() % TRIMS.size()]
	var width := rng.randf_range(9.0, 12.0)
	var depth := rng.randf_range(7.0, 9.0)
	var stories := 2 if rng.randf() < 0.45 else 1
	var house_at := Vector3(rng.randf_range(-3.0, 3.0), 0.0, -6.0)
	house(lot, house_at, width, depth, stories, wall, roof, trim, rng.randi() % 2 == 0)
	# Their own front walk, driveway, mailbox, and a tree or two dropping leaves.
	var drive_x := width * 0.5 + 1.5
	var zone := root.get_parent() as Node3D
	var place := root.transform * lot.transform
	_Grass.keep_clear_box(zone, place * Transform3D(Basis.IDENTITY, house_at), Vector3(width + 1.0, 1.0, depth + 5.0))
	_Grass.keep_clear_box(zone, place * Transform3D(Basis.IDENTITY, Vector3(drive_x, 0.0, 10.0)), Vector3(3.8, 1.0, 20.2))
	_Grass.keep_clear_box(zone, place * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 12.0)), Vector3(1.6, 1.0, 15.2))
	_LowPoly.paint(_LowPoly.box(lot, Vector3(3.6, 0.05, 20.0), Vector3(drive_x, 0.025, 10.0), CONCRETE.darkened(0.06)), "concrete")
	_LowPoly.paint(_LowPoly.box(lot, Vector3(1.4, 0.05, 15.0), Vector3(0.0, 0.025, 12.0), CONCRETE), "concrete")
	_mailbox(lot, Vector3(drive_x + 2.4, 0.0, 19.6), Color(0.2, 0.2, 0.22) if rng.randf() < 0.5 else Color(0.6, 0.15, 0.12))
	var trees := rng.randi_range(1, 2)
	for index: int in trees:
		var spot := Vector3(rng.randf_range(-12.0, -5.0) if index == 0 else rng.randf_range(7.0, 12.0), 0.0, rng.randf_range(6.0, 14.0))
		_Trees.spawn(lot, spot, rng.randf_range(6.5, 9.0), "broadleaf", CROWNS[rng.randi() % CROWNS.size()], rng.randi() % 4, false, rng.randf() * TAU)
	# Leaves already piling up on their lawn too.
	for index: int in 3:
		_leaf_patch(lot, rng, Vector3(rng.randf_range(-12.0, 12.0), 0.0, rng.randf_range(4.0, 16.0)))


## A suburban house facing +Z, its front door at the middle of the front wall:
## the "classic" archetype (levels/town/house_archetypes.gd), the same shapes
## and colors this function always built, now batched by HouseKit into about a
## dozen meshes. Siding walls, a shingled gable roof with overhangs, framed
## windows with shutters, a porch with posts, steps, a chimney, and optionally a
## garage. Metas as before ("windows" [[pos, normal, size]], "roof_edge_y") plus
## the full HouseSpec (levels/town/house_builder.gd).
static func house(parent: Node3D, at: Vector3, width: float, depth: float, stories: int, wall: Color, roof: Color, trim: Color, garage: bool) -> Node3D:
	return _HouseBuilder.build(parent, at, {
		"archetype": "classic", "width": width, "depth": depth, "stories": stories,
		"wall": wall, "roof": roof, "trim": trim, "garage": garage,
	})


static func _hedge_row(root: Node3D, at: Vector3, length: float) -> void:
	var hedge := _YardModels.node("hedge", HEDGE, Vector3(1.4, 1.5, length))
	root.add_child(hedge)
	hedge.position = at


static func _fence_panel(root: Node3D, at: Vector3) -> void:
	var fence := _YardModels.node("fence", Color(0.62, 0.5, 0.38), Vector3(4.0, 1.7, 0.2))
	root.add_child(fence)
	fence.position = at


## A straight road from one point to another on the ground: asphalt with a
## dashed double center line painted on (one mesh), and optionally curbs and
## sidewalks on both sides.
static func road(root: Node3D, from: Vector3, to: Vector3, width: float = 8.8, sidewalks: bool = true) -> void:
	var holder := Node3D.new()
	holder.name = "Road"
	root.add_child(holder)
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var length := flat.length()
	holder.position = (from + to) * 0.5
	holder.rotation.y = atan2(-flat.z, flat.x)
	# The center line is painted by the road surface; a stub too short for one dash gets none.
	var lines := "double_yellow" if length >= DASH * 2.0 else "none"
	_LowPoly.paint(_LowPoly.box(holder, Vector3(length, 0.1, width), Vector3(0.0, -0.04, 0.0), ASPHALT), "road", _Surfaces.road_params(lines, width * 0.5, DASH))
	if not sidewalks:
		return
	for side: float in [-1.0, 1.0]:
		_LowPoly.paint(_LowPoly.box(holder, Vector3(length, 0.2, 0.3), Vector3(0.0, 0.0, side * (width * 0.5 + 0.15)), CONCRETE.darkened(0.08)), "concrete")
		_LowPoly.paint(_LowPoly.box(holder, Vector3(length, 0.16, 2.0), Vector3(0.0, 0.02, side * (width * 0.5 + 1.3)), CONCRETE), "concrete")


static func lamp(root: Node3D, at: Vector3, yaw: float) -> void:
	_lamp(root, at, yaw)


static func _lamp(root: Node3D, at: Vector3, yaw: float) -> void:
	var lamp := Node3D.new()
	lamp.name = "StreetLamp"
	root.add_child(lamp)
	lamp.position = at
	lamp.rotation.y = yaw
	var pole := Color(0.22, 0.24, 0.26)
	_LowPoly.paint(_LowPoly.cylinder(lamp, 0.09, 5.2, Vector3(0.0, 2.6, 0.0), pole, false, 8), "metal")
	_LowPoly.paint(_LowPoly.cylinder(lamp, 0.16, 0.5, Vector3(0.0, 0.25, 0.0), pole, false, 8), "metal")
	_LowPoly.paint(_LowPoly.box(lamp, Vector3(0.1, 0.1, 1.3), Vector3(0.0, 5.15, 0.6), pole), "metal")
	_LowPoly.paint(_LowPoly.box(lamp, Vector3(0.42, 0.18, 0.62), Vector3(0.0, 5.08, 1.25), pole), "metal")
	_LowPoly.glow(lamp, Vector3(0.34, 0.04, 0.52), Vector3(0.0, 4.98, 1.25), Color(1.0, 0.9, 0.7), 0.6)


static func _mailbox(root: Node3D, at: Vector3, color: Color) -> void:
	_LowPoly.paint(_LowPoly.box(root, Vector3(0.12, 1.1, 0.12), at + Vector3(0.0, 0.55, 0.0), Color(0.45, 0.33, 0.22)), "planks")
	_LowPoly.paint(_LowPoly.box(root, Vector3(0.42, 0.34, 0.66), at + Vector3(0.0, 1.25, 0.0), color), "metal")
	_LowPoly.box(root, Vector3(0.04, 0.22, 0.1), at + Vector3(0.23, 1.38, -0.12), Color(0.85, 0.2, 0.15))


static func _parked_car(root: Node3D, at: Vector3, color: Color) -> void:
	var car := _YardModels.node("car", color, Vector3.ONE, {"roughness": 0.5, "specular": 0.3})
	root.add_child(car)
	car.position = at
	car.rotation.y = PI * 0.5


## Fallen leaves on a neighbor's lawn: flat orange flakes, cosmetic.
static func _leaf_patch(root: Node3D, rng: RandomNumberGenerator, at: Vector3) -> void:
	for index: int in 14:
		var flake := _LowPoly.box(root, Vector3(0.22, 0.02, 0.16), at + Vector3(rng.randf_range(-1.5, 1.5), 0.02, rng.randf_range(-1.5, 1.5)), [Color(0.88, 0.45, 0.15), Color(0.9, 0.7, 0.2), Color(0.72, 0.25, 0.14)][rng.randi() % 3])
		flake.rotation.y = rng.randf() * TAU
