extends RefCounted

## Authority: local, cosmetic. Streets in a neighborhood's style
## (levels/town/hood_styles.gd "street"): the road (asphalt with its lines
## painted by the surface shader, or a gravel lane), curbs, sidewalks or a
## shoulder, a grass strip, street lamps or wooden power poles with their wires,
## storm drains, and speed bumps where the style has them. For the job's block
## (levels/town/block_builder.gd) and the drivable town (driving's streamer,
## gap-specs/critic.md C24).
##
##   StreetBuilder.segment(parent, from, to, style, {"batch": batch})
##   StreetBuilder.intersection(parent, center, style, 4)
##
## A segment runs along its local x from from to to; local +z and -z are its
## two sides. The road, curbs and sidewalks join group "street_surface" (the art
## test's Chefty-lane check ignores them). Lamps' lenses join "street_lamps"
## (props/prop_catalog.gd place()). Nothing collides.
##
## opts:
##   batch (PropBatch): repeated props go in here, in its root's space (parent's
##     space unless batch_xform says where parent sits in it); without one the
##     segment commits its own
##   width (road width, default 8.8), half_band (curb plus sidewalk band beyond
##     the road on each side, default 2.3 + the 0.3 curb: the job street's layout)
##   keep_clear_lane (Rect2, parent x and z): no props in it (the job's block
##     passes Chefty's lane, Constants.ART_CHEFTY_LANE)
##   speed_bumps_from_x (parent x): speed bumps only past this (default
##     Constants.ART_SPEED_BUMP_FROM_X); the style decides whether there are any
##   hood (net/town/neighborhoods.gd id): street names on the sign post
##   lamps (false: none, for a segment whose sides are dressed elsewhere)
## Metas on the returned root: "lamps" (PackedVector3Array, parent space: each
## lamp's base), "poles" (the same for power poles), "length", "curbs"
## ([[from, to]] parent space), "width".

const _LowPoly = preload("res://props/low_poly.gd")
const _Surfaces = preload("res://props/surfaces.gd")
const _HouseKit = preload("res://props/house_kit.gd")
const _PropCatalog = preload("res://props/prop_catalog.gd")
const _PropBatch = preload("res://props/prop_batch.gd")
const _Street = preload("res://props/street_props.gd")
const _Stylized = preload("res://props/stylized.gd")

const ASPHALT := Color(0.3, 0.3, 0.32)
const CONCRETE := Color(0.72, 0.7, 0.66)
const GRANITE := Color(0.62, 0.62, 0.64)
const PAVERS := Color(0.68, 0.44, 0.34)
const GRAVEL := Color(0.62, 0.58, 0.52)
const ROAD_WIDTH: float = 8.8
const CURB: float = 0.3
const SIDEWALK: float = 2.0
## Between the curb and the sidewalk, when the style has a grass strip.
const GRASS_STRIP: float = 0.8
const DASH: float = 3.0


static func segment(parent: Node3D, from: Vector3, to: Vector3, style: Dictionary, opts: Dictionary = {}) -> Node3D:
	var street: Dictionary = style.get("street", {})
	var root := Node3D.new()
	root.name = "Street"
	parent.add_child(root)
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var length := flat.length()
	root.position = (from + to) * 0.5
	root.rotation.y = atan2(-flat.z, flat.x)
	var place := root.transform
	var width := float(opts.get("width", ROAD_WIDTH))
	var surface := str(street.get("surface", "road"))
	var curb := str(street.get("curb", "concrete"))
	var sidewalk := str(street.get("sidewalk", "concrete"))
	var strip := bool(street.get("grass_strip", false))
	var kit := _HouseKit.new()
	# The road itself. Lines: a stub too short for one dash gets none.
	var lines := str(street.get("lines", "none")) if length >= DASH * 2.0 else "none"
	if surface == "gravel":
		kit.call("box", Vector3(length, 0.1, width), Vector3(0.0, -0.04, 0.0), GRAVEL, "gravel")
	else:
		kit.call("box", Vector3(length, 0.1, width), Vector3(0.0, -0.04, 0.0), ASPHALT, "road", Basis.IDENTITY, {"params": _Surfaces.road_params(lines, width * 0.5, DASH)})
	var curbs: Array = []
	for side: float in [-1.0, 1.0]:
		var edge := side * width * 0.5
		if curb != "none":
			var tone := GRANITE if curb == "granite" else CONCRETE.darkened(0.08)
			kit.call("box", Vector3(length, 0.2, CURB), Vector3(0.0, 0.0, edge + side * CURB * 0.5), tone, "stone" if curb == "granite" else "concrete", Basis.IDENTITY, {"params": Vector4(1, 0, 0, 0)} if curb == "granite" else {})
			curbs.append([place * Vector3(-length * 0.5, 0.0, edge + side * CURB * 0.5), place * Vector3(length * 0.5, 0.0, edge + side * CURB * 0.5)])
		var outer := edge + side * CURB
		if sidewalk != "none":
			var walk_width := SIDEWALK - (GRASS_STRIP if strip else 0.0)
			var walk_center := outer + side * (SIDEWALK - walk_width * 0.5)
			if sidewalk == "pavers":
				kit.call("box", Vector3(length, 0.16, walk_width), Vector3(0.0, 0.02, walk_center), PAVERS, "pavers")
			else:
				kit.call("box", Vector3(length, 0.16, walk_width), Vector3(0.0, 0.02, walk_center), CONCRETE, "concrete")
		elif surface == "gravel":
			# No curb, no sidewalk: the gravel spills onto a dirt shoulder.
			kit.call("box", Vector3(length, 0.06, 1.0), Vector3(0.0, -0.02, edge + side * 0.5), GRAVEL.darkened(0.12), "dirt")
	var road: Node3D = kit.call("commit", root, "Road")
	road.add_to_group("street_surface")
	for view: Node in road.get_children():
		view.add_to_group("street_surface")
	var batch: RefCounted = opts.get("batch", null)
	var own := batch == null
	var to_batch: Transform3D = opts.get("batch_xform", Transform3D.IDENTITY)
	if own:
		batch = _PropBatch.new(root)
		to_batch = place.affine_inverse()
	var lane: Rect2 = opts.get("keep_clear_lane", Rect2())
	var lamps := PackedVector3Array()
	var poles := PackedVector3Array()
	var lamp := str(street.get("lamp", "none"))
	var spacing := maxf(float(street.get("lamp_spacing", 24.0)), 6.0)
	var with_poles := bool(street.get("poles", false))
	var band := CURB + SIDEWALK if sidewalk != "none" else 1.2
	# Lamps both sides, staggered; poles both sides, in step, wires between them.
	for side: float in [-1.0, 1.0]:
		var count := int(length / spacing)
		var offset := spacing * (0.25 if side > 0.0 else 0.75)
		var line: Array[Vector3] = []
		for index: int in count:
			var x := -length * 0.5 + offset + float(index) * spacing
			if with_poles:
				# Back from the road far enough that the crossarm clears the lane.
				var at := Vector3(x, 0.0, side * (width * 0.5 + (1.9 if sidewalk == "none" else band - 0.3)))
				var world := place * at
				if _in_lane(lane, world, 0.6):
					continue
				batch.call("add", "power_pole", to_batch * (place * Transform3D(Basis(Vector3.UP, PI * 0.5), at)))
				poles.append(world)
				line.append(world)
			elif lamp != "none" and bool(opts.get("lamps", true)):
				# Lamps stand at the sidewalk's back (or in the grass strip), the arm toward the road.
				var reach := width * 0.5 + CURB + (GRASS_STRIP * 0.5 if strip else SIDEWALK - 0.3)
				if lamp == "cobra":
					reach = width * 0.5 + band - 0.25
				var at := Vector3(x, 0.0, side * reach)
				var world := place * at
				if _in_lane(lane, world, 1.6):
					continue
				var yaw := PI if side < 0.0 else 0.0
				_PropCatalog.place(root, "lamp_%s" % lamp, Transform3D(Basis(Vector3.UP, yaw), at))
				lamps.append(world)
		if with_poles and line.size() >= 2:
			var spans: Array = []
			for index: int in line.size() - 1:
				spans.append([root.transform.affine_inverse() * line[index], root.transform.affine_inverse() * line[index + 1]])
			var wires := _Street.wire_mesh(spans, _Street.WIRE_HEIGHT, 0.7)
			if wires != null:
				var view := _Stylized.instance(wires, _PropCatalog.options("wire_span"))
				view.name = "Wires%d" % int(side)
				view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				root.add_child(view)
	# Storm drains in the gutter now and then.
	if curb != "none":
		for index: int in int(length / 40.0):
			var x := -length * 0.5 + 20.0 + float(index) * 40.0
			for side: float in [-1.0, 1.0]:
				var at := Vector3(x, 0.0, side * (width * 0.5 - 0.35))
				batch.call("add", "storm_drain", to_batch * (place * Transform3D(Basis(Vector3.UP, 0.0 if side > 0.0 else PI), at)))
	# Speed bumps across the road, only where Chefty never drives.
	if bool(street.get("speed_bumps", false)):
		var from_x := float(opts.get("speed_bumps_from_x", Constants.ART_SPEED_BUMP_FROM_X))
		var placed := 0
		for x: float in [-length * 0.5 + 18.0, 0.0, length * 0.5 - 18.0, length * 0.25, -length * 0.25]:
			var world := place * Vector3(x, 0.0, 0.0)
			if world.x <= from_x or placed >= 2:
				continue
			batch.call("add", "speed_bump", to_batch * (place * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x, 0.0, 0.0))), Color.WHITE, Vector3(width - 0.2, 0.1, 0.9))
			placed += 1
	if own:
		batch.call("commit")
	root.set_meta("lamps", lamps)
	root.set_meta("poles", poles)
	root.set_meta("length", length)
	root.set_meta("curbs", curbs)
	root.set_meta("width", width)
	return root


## A crossing of arms streets at center: a square patch with crosswalk bars
## (the road pattern's style 5) and a stop sign at each corner that has a road
## coming in. A minimal version for the drivable town.
static func intersection(parent: Node3D, center: Vector3, style: Dictionary, arms: int = 4, opts: Dictionary = {}) -> Node3D:
	var street: Dictionary = style.get("street", {})
	var width := float(opts.get("width", ROAD_WIDTH))
	var root := Node3D.new()
	root.name = "Intersection"
	root.position = center
	parent.add_child(root)
	var kit := _HouseKit.new()
	if str(street.get("surface", "road")) == "gravel":
		kit.call("box", Vector3(width, 0.1, width), Vector3(0.0, -0.039, 0.0), GRAVEL, "gravel")
	else:
		kit.call("box", Vector3(width, 0.1, width), Vector3(0.0, -0.039, 0.0), ASPHALT, "road", Basis.IDENTITY, {"params": _Surfaces.road_params("crosswalk", width * 0.5, 2.2)})
	var road: Node3D = kit.call("commit", root, "Road")
	road.add_to_group("street_surface")
	for view: Node in road.get_children():
		view.add_to_group("street_surface")
	var corner := width * 0.5 + CURB + 0.6
	var yaw := 0.0
	for index: int in clampi(arms, 0, 4):
		var at := Basis(Vector3.UP, yaw) * Vector3(corner, 0.0, corner)
		_PropCatalog.place(root, "stop_sign", Transform3D(Basis(Vector3.UP, yaw + PI * 0.25), at))
		yaw += PI * 0.5
	if opts.has("hood"):
		_PropCatalog.place(root, "street_sign_post", Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(-corner, 0.0, corner)), Color.WHITE, {"hood": str(opts["hood"])})
	return root


static func _in_lane(lane: Rect2, world: Vector3, margin: float) -> bool:
	return lane.size != Vector2.ZERO and lane.grow(margin).has_point(Vector2(world.x, world.z))
