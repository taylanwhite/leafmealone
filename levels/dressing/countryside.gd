extends RefCounted

## Authority: local, cosmetic. The country between Homie Depot and the town's
## streets, so Chefty's ride passes something: the road it drives on, grass,
## trees in the season's colors, fence lines, farms (a farmhouse, a red barn and
## a silo, hay in the yard that turns to snow piles in winter, a mailbox and now
## and then an egg stand at the road; art chunk 8), and a power line on poles. Built once in
## world space along Chefty's route (net/components/ride.gd: the store at x 0,
## the yards at x 1000). Seeded, so every peer sees the same drive. Nothing here
## collides. The grass sits a little below the zones' own ground, so the two
## never fight where they overlap.

const _LowPoly = preload("res://props/low_poly.gd")
const _Trees = preload("res://props/trees.gd")
const _Surfaces = preload("res://props/surfaces.gd")
const _BuildQueue = preload("res://levels/build_queue.gd")
const _HouseBuilder = preload("res://levels/town/house_builder.gd")
const _PropCatalog = preload("res://props/prop_catalog.gd")
const _PropBatch = preload("res://props/prop_batch.gd")
const _StreetProps = preload("res://props/street_props.gd")
const _Stylized = preload("res://props/stylized.gd")
const _MeshKit = preload("res://props/mesh_kit.gd")
const _SeasonSet = preload("res://levels/dressing/season_set.gd")
const _Strings = preload("res://ui/strings.gd")
const ASPHALT := Color(0.3, 0.3, 0.32)
## The center line's dashes: longer and further apart than a town street's.
const DASH: float = 4.0
const DASH_PERIOD: float = 12.0
const GRASS := Color(0.42, 0.52, 0.3)
const FENCE := Color(0.55, 0.42, 0.3)
const CROWNS: Array[String] = ["orange", "red", "yellow", "rust", "turning"]
## Farmhouse paint: white, cream, barn red, pale yellow, sage; and roofs.
const FARM_WALLS: Array[Color] = [Color(0.95, 0.94, 0.9), Color(0.9, 0.86, 0.74), Color(0.62, 0.2, 0.16), Color(0.93, 0.86, 0.58), Color(0.66, 0.72, 0.6)]
const FARM_ROOFS: Array[Color] = [Color(0.36, 0.38, 0.4), Color(0.5, 0.2, 0.16), Color(0.3, 0.32, 0.28)]
## The stretch of Chefty's route with no zone around it, as road points (x, z).
const ROUTE: Array[Vector2] = [Vector2(290.0, 14.9), Vector2(500.0, 20.0), Vector2(880.0, 24.0)]


static func dress(world: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Countryside"
	world.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1101
	# Grass under the whole stretch, below the zones' ground.
	_LowPoly.paint(_LowPoly.box(root, Vector3(700.0, 0.1, 260.0), Vector3(585.0, -0.16, 20.0), GRASS), "grass")
	for index: int in ROUTE.size() - 1:
		_road(root, ROUTE[index], ROUTE[index + 1])
	# Trees, fences, and houses on both sides of the road.
	var x := ROUTE[0].x + 10.0
	while x < ROUTE[ROUTE.size() - 1].x - 10.0:
		var road_z := _road_z(x)
		for side: float in [-1.0, 1.0]:
			if rng.randf() < 0.8:
				var off := rng.randf_range(10.0, 34.0)
				var kind := "pine" if rng.randf() < 0.25 else "broadleaf"
				var at := Vector3(x + rng.randf_range(-6.0, 6.0), 0.0, road_z + side * off)
				var tall := rng.randf_range(6.5, 9.5)
				var crown: String = CROWNS[rng.randi() % CROWNS.size()]
				var variant := rng.randi() % 4
				var turn := rng.randf() * TAU
				_BuildQueue.later(root, func() -> void: _Trees.spawn(root, at, tall, kind, crown, variant, false, turn), "country tree")
		x += rng.randf_range(14.0, 22.0)
	# Fence lines along a few fields.
	for field: int in 6:
		var start := rng.randf_range(ROUTE[0].x + 20.0, ROUTE[ROUTE.size() - 1].x - 80.0)
		var side := -1.0 if field % 2 == 0 else 1.0
		var length := rng.randf_range(40.0, 70.0)
		var z := _road_z(start) + side * rng.randf_range(8.0, 9.0)
		for post: int in int(length / 4.0):
			var at := Vector3(start + float(post) * 4.0, 0.0, z)
			_LowPoly.box(root, Vector3(0.14, 1.1, 0.14), at + Vector3(0.0, 0.55, 0.0), FENCE)
			_LowPoly.box(root, Vector3(4.0, 0.1, 0.06), at + Vector3(2.0, 0.85, 0.0), FENCE)
			_LowPoly.box(root, Vector3(4.0, 0.1, 0.06), at + Vector3(2.0, 0.45, 0.0), FENCE)
	# A farm now and then, set back from the road and facing it: the farmhouse,
	# a red barn and a silo behind it, hay out in the yard (season-aware), and a
	# mailbox at the road.
	var house_x := ROUTE[0].x + 60.0
	var farm := 0
	while house_x < ROUTE[ROUTE.size() - 1].x - 60.0:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var off := rng.randf_range(42.0, 55.0)
		var at := Vector3(house_x, 0.0, _road_z(house_x) + side * off)
		var holder := Node3D.new()
		holder.name = "Farm"
		root.add_child(holder)
		holder.position = at
		holder.rotation.y = 0.0 if side < 0.0 else PI
		var req := {
			"archetype": "farmhouse", "width": rng.randf_range(10.0, 12.5), "depth": rng.randf_range(7.5, 9.0),
			"stories": 1 + int(rng.randf() < 0.6), "wall": FARM_WALLS[rng.randi() % FARM_WALLS.size()],
			"wall_surface": "board_batten" if rng.randf() < 0.5 else "siding", "roof": FARM_ROOFS[rng.randi() % FARM_ROOFS.size()],
			"roof_surface": "corrugated" if rng.randf() < 0.5 else "shingles", "trim": Color(0.95, 0.94, 0.9), "seed": 1101 + farm,
		}
		var barn_side := -1.0 if rng.randf() < 0.5 else 1.0
		var stand_sign := "farm_stand" if farm % 2 == 0 else "farm_hay"
		_BuildQueue.later(root, func() -> void: _farm(holder, req, off, barn_side, stand_sign), "farm")
		house_x += rng.randf_range(110.0, 170.0)
		farm += 1
	# A power line along the north side of the road, in long merged runs.
	_BuildQueue.later(root, func() -> void: _power_line(root), "country power line")


## One farm in its holder's frame (house at the origin facing +Z, the road off
## metres ahead): the farmhouse (levels/town/house_builder.gd "farmhouse"), the
## barn and silo to barn_side behind it, hay bales in the yard that turn to snow
## piles in winter (levels/dressing/season_set.gd), the mailbox at the road and
## a roadside stand beside it with its sign (Strings.SIGNS stand_sign).
static func _farm(holder: Node3D, req: Dictionary, off: float, barn_side: float, stand_sign: String) -> void:
	_HouseBuilder.build(holder, Vector3.ZERO, req)
	var wide := float(req["width"])
	var barn_x := barn_side * (wide * 0.5 + 12.0)
	var barn := _PropCatalog.node("barn")
	holder.add_child(barn)
	barn.position = Vector3(barn_x, 0.0, -6.0)
	barn.rotation.y = PI
	var silo := _PropCatalog.node("silo")
	holder.add_child(silo)
	silo.position = Vector3(barn_x + barn_side * 7.5, 0.0, -9.0)
	var hay := _SeasonSet.new()
	hay.name = "Hay"
	var yard := Vector3(barn_x * 0.55, 0.0, 9.0)
	hay.set("pieces", [
		[["hay_bale", yard, 0.3, 1.0], ["hay_bale", yard + Vector3(1.2, 0.0, 0.4), -0.2, 1.0], ["hay_bale", yard + Vector3(0.6, 0.5, 0.2), 0.1, 1.0], ["pumpkin", yard + Vector3(-1.0, 0.0, 1.0), 0.5, 1.0], ["scarecrow", yard + Vector3(-3.0, 0.0, 3.0), 0.0, 1.0]],
		[["snow_pile", yard, 0.3, 1.2], ["snow_pile", yard + Vector3(1.6, 0.0, 0.6), 1.4, 1.0]],
		[],
		[["hay_bale", yard, 0.3, 1.0], ["hay_bale", yard + Vector3(1.2, 0.0, 0.4), -0.2, 1.0]],
	])
	holder.add_child(hay)
	# The mailbox at the road's edge, beside the drive, its door to the road.
	var road_edge := off - 5.5
	var mailbox := _PropCatalog.node("mailbox_post")
	holder.add_child(mailbox)
	mailbox.position = Vector3(wide * 0.5 + 1.5, 0.0, road_edge)
	mailbox.rotation.y = PI
	_stand(holder, Vector3(wide * 0.5 + 3.4, 0.0, road_edge - 0.6), stand_sign)


## A roadside stand: a crate on a post with its hand-painted sign, facing the road.
static func _stand(holder: Node3D, at: Vector3, sign_key: String) -> void:
	var stand := Node3D.new()
	stand.name = "EggStand"
	holder.add_child(stand)
	stand.position = at
	stand.rotation.y = PI
	var kit := _MeshKit.new()
	kit.box(Vector3(0.0, 0.45, 0.0), Vector3(0.9, 0.9, 0.5), FENCE)
	kit.box(Vector3(0.0, 0.92, 0.0), Vector3(0.96, 0.04, 0.56), FENCE.darkened(0.15))
	kit.box(Vector3(0.0, 1.0, 0.0), Vector3(0.5, 0.12, 0.3), Color(0.82, 0.7, 0.5))
	kit.box(Vector3(0.0, 1.25, 0.24), Vector3(0.05, 0.9, 0.05), FENCE.darkened(0.2))
	kit.box(Vector3(0.0, 1.55, 0.22), Vector3(0.8, 0.5, 0.03), Color(0.96, 0.94, 0.88))
	stand.add_child(_Stylized.instance(kit.commit(), {"roughness": 0.85, "specular": 0.1}))
	var words := _LowPoly.text_sign(stand, str(_Strings.SIGNS[sign_key]), Vector3(0.0, 1.55, 0.2), 32, Color(0.2, 0.18, 0.16), PI)
	words.pixel_size = 0.0028
	words.outline_size = 0


## Wooden power poles along the north (+Z) side of the route every
## ART_COUNTRY_POLE_SPACING, their crossarms across the road, and the wires
## between them merged into one mesh per ART_COUNTRY_WIRE_RUN of road.
static func _power_line(root: Node3D) -> void:
	var batch := _PropBatch.new(root)
	var run: Array = []
	var run_start := ROUTE[0].x
	var last := Vector3.INF
	var x := ROUTE[0].x + 12.0
	var runs := 0
	while x < ROUTE[ROUTE.size() - 1].x - 8.0:
		var ahead := Vector2(x + 1.0, _road_z(x + 1.0)) - Vector2(x, _road_z(x))
		var yaw := atan2(-ahead.y, ahead.x) + PI * 0.5
		var at := Vector3(x, 0.0, _road_z(x) + Constants.ART_COUNTRY_POLE_OFFSET)
		batch.add("power_pole", Transform3D(Basis(Vector3.UP, yaw), at))
		if last != Vector3.INF:
			run.append([last, at])
		last = at
		if x - run_start >= Constants.ART_COUNTRY_WIRE_RUN:
			_wires(root, run, runs)
			runs += 1
			run = []
			run_start = x
		x += Constants.ART_COUNTRY_POLE_SPACING
	_wires(root, run, runs)
	batch.commit()


static func _wires(root: Node3D, spans: Array, index: int) -> void:
	if spans.is_empty():
		return
	var mesh := _StreetProps.wire_mesh(spans, _StreetProps.WIRE_HEIGHT, 0.9)
	if mesh == null:
		return
	var view := _Stylized.instance(mesh, _PropCatalog.options("wire_span"))
	view.name = "Wires%d" % index
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(view)

## The road's z at x along the route.
static func _road_z(x: float) -> float:
	for index: int in ROUTE.size() - 1:
		var a := ROUTE[index]
		var b := ROUTE[index + 1]
		if x >= a.x and x <= b.x:
			return lerpf(a.y, b.y, (x - a.x) / (b.x - a.x))
	return ROUTE[ROUTE.size() - 1].y


## Asphalt and a dashed center line, with fewer dashes than a town street.
static func _road(root: Node3D, from: Vector2, to: Vector2) -> void:
	var holder := Node3D.new()
	holder.name = "CountryRoad"
	root.add_child(holder)
	var flat := Vector2(to.x - from.x, to.y - from.y)
	var length := flat.length()
	holder.position = Vector3((from.x + to.x) * 0.5, 0.0, (from.y + to.y) * 0.5)
	holder.rotation.y = atan2(-flat.y, flat.x)
	# One mesh: the road surface paints the single dashed line (props/surfaces.gd "road").
	_LowPoly.paint(_LowPoly.box(holder, Vector3(length + 2.0, 0.1, 8.0), Vector3(0.0, -0.06, 0.0), ASPHALT), "road", _Surfaces.road_params("single_yellow", 4.0, DASH, DASH_PERIOD))
