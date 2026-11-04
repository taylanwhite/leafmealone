extends RefCounted

## Authority: local, cosmetic. The job street's layout (the lot zone's space:
## the yard is x and z in -20..20, its front at z = +20, the street along x in
## front of it), the old palettes, and the shared pieces older dressing still
## uses: the classic house, a plain road, a street lamp. The job's street block
## itself (neighbors, street, set pieces, street life) is built per job yard in
## its neighborhood's style by levels/town/block_builder.gd; Chefty's path,
## pedestrians and ambience cars keep to the layout below.

const _LowPoly = preload("res://props/low_poly.gd")
const _Surfaces = preload("res://props/surfaces.gd")
const _HouseBuilder = preload("res://levels/town/house_builder.gd")

## The street runs along x in front of the yard.
const SIDEWALK_NEAR := Vector2(20.3, 22.3)
const STREET := Vector2(22.6, 31.4)
const SIDEWALK_FAR := Vector2(31.7, 33.7)
const STREET_LENGTH: float = 260.0
## A street lamp's pole height and the radius of its base (m; _lamp).
const LAMP_HEIGHT: float = 5.2
const LAMP_BASE_RADIUS: float = 0.16
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


## A suburban house facing +Z, its front door at the middle of the front wall:
## the "classic" archetype (levels/town/house_archetypes.gd), the same shapes
## and colors this function always built, now batched by HouseKit into about a
## dozen meshes (shingle courses now run along the eaves, the porch stoop takes
## no snow, and mullions are painted like the frames: docs/DECISIONS.md). Siding walls, a shingled gable roof with overhangs, framed
## windows with shutters, a porch with posts, steps, a chimney, and optionally a
## garage. Metas as before ("windows" [[pos, normal, size]], "roof_edge_y") plus
## the full HouseSpec (levels/town/house_builder.gd).
static func house(parent: Node3D, at: Vector3, width: float, depth: float, stories: int, wall: Color, roof: Color, trim: Color, garage: bool) -> Node3D:
	return _HouseBuilder.build(parent, at, {
		"archetype": "classic", "width": width, "depth": depth, "stories": stories,
		"wall": wall, "roof": roof, "trim": trim, "garage": garage,
	})


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
	_LowPoly.paint(_LowPoly.cylinder(lamp, 0.09, LAMP_HEIGHT, Vector3(0.0, LAMP_HEIGHT * 0.5, 0.0), pole, false, 8), "metal")
	_LowPoly.paint(_LowPoly.cylinder(lamp, LAMP_BASE_RADIUS, 0.5, Vector3(0.0, 0.25, 0.0), pole, false, 8), "metal")
	_LowPoly.paint(_LowPoly.box(lamp, Vector3(0.1, 0.1, 1.3), Vector3(0.0, 5.15, 0.6), pole), "metal")
	_LowPoly.paint(_LowPoly.box(lamp, Vector3(0.42, 0.18, 0.62), Vector3(0.0, 5.08, 1.25), pole), "metal")
	_LowPoly.glow(lamp, Vector3(0.34, 0.04, 0.52), Vector3(0.0, 4.98, 1.25), Color(1.0, 0.9, 0.7), 0.6)
