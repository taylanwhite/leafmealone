extends RefCounted

## Authority: local, cosmetic. The store zone: Homie Depot on a street corner.
## A big-box building along the west edge with a tall orange entrance, sliding
## doors, and the sign; a parking lot with painted stalls, parked cars, light
## poles, a cart corral, and tree islands; a garden center whose shelves show
## the real stock (props/shelf_stock.gd); a checkout booth with a striped awning around
## the counter; Chefty's striped loading bay; and the roads out, including the
## one Chefty drives east on. Keeps clear of the counter (0, -8), the gate to
## the lot (0, -16), the spawns near (1, 6), and Chefty's pad at (10, 8).
## Solid pieces keep simple colliders so players can't walk through them.

const _LowPoly = preload("res://props/low_poly.gd")
const _Trees = preload("res://props/trees.gd")
const _YardModels = preload("res://props/yard_models.gd")
const _Neighborhood = preload("res://levels/dressing/neighborhood.gd")
const _MeshKit = preload("res://props/mesh_kit.gd")
## Where the checkout's register sits on the counter (m from its middle; the
## counter's top runs 1.7 m each way and 0.55 m front to back): on Marty's side,
## at his elbow, its screen to him. Set dressing.
const REGISTER_X: float = -0.6
const REGISTER_Z: float = -0.35
const _Stylized = preload("res://props/stylized.gd")
const _Grass = preload("res://props/grass.gd")
const _ShelfStock = preload("res://props/shelf_stock.gd")
const _BuildQueue = preload("res://levels/build_queue.gd")
const _StoreInterior = preload("res://levels/dressing/store_interior.gd")
const _PropBatch = preload("res://props/prop_batch.gd")
const _PropCatalog = preload("res://props/prop_catalog.gd")
const _StoreProps = preload("res://props/store_props.gd")
const _SeasonStock = preload("res://levels/dressing/store_season_stock.gd")
const _Strings = preload("res://ui/strings.gd")
const _P = preload("res://props/prop_parts.gd")
const WALL := Color(0.86, 0.8, 0.66)
const BLOCK := Color(0.66, 0.65, 0.62)
const FRAME := Color(0.72, 0.74, 0.76)
## The building, in StoreZone space: its front wall's x, its back's, the z it
## runs between, and the height of its walls; the cinder-block base's height.
const FRONT_X: float = -12.0
const BACK_X: float = -34.0
const SHELL_Z := Vector2(-19.0, 15.0)
const SHELL_HEIGHT: float = 8.0
const BLOCK_BASE_HEIGHT: float = 1.2
## The orange entrance block: its height, its side walls' thickness, and where
## its glass transom stops and the orange header starts.
const ENTRANCE_HEIGHT: float = 10.5
const ENTRANCE_WALL: float = 0.4
const TRANSOM_TOP: float = 4.4
## The bollards stand before the two sidelights, at this x.
const BOLLARD_X: float = -8.6
const BOLLARDS_Z: Array[float] = [-6.4, -5.2, 1.2, 2.4]
## The vehicle stop across the doorway: its middle this far out from the
## entrance's face (m), and its depth; far enough out that Chefty's bumper stops
## short of the glass.
const VEHICLE_STOP_OUT: float = 0.6
const VEHICLE_STOP_DEPTH: float = 0.8
## The pallets in the garden yard (Constants.STORE_LAYOUT "garden_yard"): kind,
## where, and the yaw.
const GARDEN_PALLETS: Array = [
	["mulch_pallet", Vector3(3.75, 0.0, -18.95), 0.0], ["mulch_pallet", Vector3(5.05, 0.0, -18.95), 0.04],
	["mulch_pallet", Vector3(6.35, 0.0, -18.95), -0.03], ["soil_pallet", Vector3(7.55, 0.0, -18.9), PI * 0.5],
	["mulch_pallet", Vector3(3.75, 0.0, -17.7), 0.03], ["soil_pallet", Vector3(5.05, 0.0, -17.7), -0.05],
]
const ROOF := Color(0.3, 0.32, 0.36)
const ORANGE := Color(0.95, 0.5, 0.15)
const DARK := Color(0.16, 0.17, 0.2)
const SHELF := Color(0.5, 0.36, 0.24)
const LINE := Color(0.95, 0.94, 0.88)
const STRIPE := Color(0.95, 0.8, 0.2)
## The parking lot's fixed pieces, in StoreZone space. Each one sits inside a
## "store" reservation in Constants.STORE_LAYOUT and clear of everyone else's
## (net/dev/townmap_test.gd checks it), so nothing new lands on them.
const PARKED_CARS: Array[Vector3] = [Vector3(-7.5, 0.0, 15.6), Vector3(-4.5, 0.0, 15.6), Vector3(-1.5, 0.0, 15.6)]
const LOT_LAMPS: Array[Vector3] = [Vector3(17.0, 0.0, 17.0), Vector3(17.0, 0.0, -17.0), Vector3(-9.0, 0.0, 17.0), Vector3(7.8, 0.0, 17.0)]
const TREE_ISLANDS: Array[Vector3] = [Vector3(18.5, 0.0, -18.5), Vector3(-10.0, 0.0, 18.5), Vector3(18.5, 0.0, 18.5)]
const CART_CORRAL_AT := Vector3(-7.5, 0.0, 10.0)
## Ground footprints (x, z) of those pieces, in meters.
const CAR_FOOTPRINT := Vector2(2.0, 4.5)
const LAMP_FOOTPRINT := Vector2(0.6, 0.6)
const TREE_ISLAND_SIZE: float = 3.0
const CART_CORRAL_FOOTPRINT := Vector2(1.4, 4.2)


## The pieces are BuildQueue steps (levels/build_queue.gd), in this order; with
## no queue they're all built right away.
static func dress(zone: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Dressing"
	zone.add_child(root)
	_BuildQueue.later(root, func() -> void: _building(root), "store building")
	_BuildQueue.later(root, func() -> void: _StoreInterior.dress(root, zone), "store lobby")
	_BuildQueue.later(root, func() -> void: _lot_extras(root), "store lot extras")
	_BuildQueue.later(root, func() -> void: _garden_center(root), "store garden")
	# Workwear on the entrance's wall, with a mirror, and Chefty's paint counter
	# (shops chunk 7, levels/dressing/wardrobe.gd).
	_BuildQueue.later(root, func() -> void: preload("res://levels/dressing/wardrobe.gd").build(root), "store wardrobe")
	_parking(root)
	_BuildQueue.later(root, func() -> void: _checkout(root, zone), "store checkout")
	_BuildQueue.later(root, func() -> void: _loading_bay(root, zone), "store bay")
	# No grass through the parking lot, the store, or the roads.
	_Grass.keep_clear(zone, Rect2(-20.5, -20.5, 41.0, 41.0))
	_Grass.keep_clear(zone, Rect2(-35.0, -20.0, 24.0, 36.0))
	_Grass.keep_clear(zone, Rect2(20.5, -165.0, 13.2, 330.0))
	_Grass.keep_clear(zone, Rect2(20.5, 3.0, 285.0, 17.0))
	# The cross street east of the lot, and the road Chefty leaves on toward the job.
	_BuildQueue.later(root, func() -> void:
		_Neighborhood.road(root, Vector3(27.0, 0.0, -160.0), Vector3(27.0, 0.0, 160.0))
		_Neighborhood.road(root, Vector3(32.0, 0.0, 8.6), Vector3(300.0, 0.0, 15.2), 8.8, false)
		_Neighborhood.road(root, Vector3(21.0, 0.0, 8.0), Vector3(22.6, 0.0, 8.0), 8.8, false), "store roads")
	_BuildQueue.later(root, func() -> void:
		for z: float in range(-140, 141, 28):
			_Neighborhood.lamp(root, Vector3(32.3, 0.0, float(z)), PI * 0.5), "store lamps")
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var crowns: Array[String] = ["orange", "red", "yellow", "rust"]
	for z: float in range(-130, 131, 18):
		if absf(float(z) - 10.0) < 12.0:
			continue
		var tall := rng.randf_range(6.5, 8.5)
		var crown := crowns[rng.randi() % crowns.size()]
		var turn := rng.randf() * TAU
		_BuildQueue.later(root, func() -> void: _Trees.spawn(root, Vector3(36.0, 0.0, float(z)), tall, "broadleaf", crown, int(z), false, turn), "store tree")


## A big box store: a shell of corrugated metal over a cinder-block base, a flat
## roof with a parapet, an orange band, display windows, and the tall orange
## entrance block with the name in big letters. The shell is solid boxes around
## the walk-in lobby (levels/dressing/store_interior.gd, art chunk 8): you walk
## through the entrance block's sliding doors (between two glass sidelights,
## under a glass transom and the canopy) into the room behind it.
static func _building(root: Node3D) -> void:
	var front := FRONT_X
	var room := _StoreInterior.ROOM
	# The shell, solid: the back of the store, the two wings either side of the
	# lobby, and the block over the lobby's ceiling.
	_shell(root, Rect2(BACK_X, SHELL_Z.x, room.position.x - BACK_X, SHELL_Z.y - SHELL_Z.x), 0.0)
	_shell(root, Rect2(room.position.x, SHELL_Z.x, front - room.position.x, room.position.y - SHELL_Z.x), 0.0)
	_shell(root, Rect2(room.position.x, room.end.y, front - room.position.x, SHELL_Z.y - room.end.y), 0.0)
	_shell(root, Rect2(room.position.x, room.position.y, front - room.position.x, room.size.y), _StoreInterior.CEILING + 0.2)
	var depth := front - BACK_X
	var center_x := (front + BACK_X) * 0.5
	var middle_z := (SHELL_Z.x + SHELL_Z.y) * 0.5
	var length := SHELL_Z.y - SHELL_Z.x
	var roof := _LowPoly.paint(_LowPoly.box(root, Vector3(depth + 0.4, 0.9, length + 0.4), Vector3(center_x, SHELL_HEIGHT + 0.4, middle_z), ROOF.lightened(0.15)), "concrete")
	# What the studio's store_lobby cutaway lifts off (tools/studio/studio.gd).
	roof.add_to_group("store_roof")
	_LowPoly.paint(_LowPoly.box(root, Vector3(0.25, 1.2, length), Vector3(front + 0.12, 6.6, middle_z), ORANGE), "metal")
	_entrance(root)
	# Display windows along the front, over the block base.
	for z: float in [-15.0, -11.0, 7.0, 11.0]:
		_LowPoly.window(root, 3.0, 2.0, Vector3(front + 0.08, 2.5, z), Color(0.85, 0.85, 0.82), PI * 0.5)
	# A low concrete walk along the front, either side of the entrance block,
	# and the apron in front of its doors.
	var walk := Color(0.72, 0.7, 0.66)
	for span: Vector2 in [Vector2(SHELL_Z.x, room.position.y), Vector2(room.end.y, SHELL_Z.y)]:
		_LowPoly.paint(_LowPoly.box(root, Vector3(3.0, 0.08, span.y - span.x), Vector3(front + 1.5, 0.0, (span.x + span.y) * 0.5), walk), "concrete")
	_LowPoly.paint(_LowPoly.box(root, Vector3(1.0, 0.08, room.size.y), Vector3(room.end.x + 0.5, 0.0, room.get_center().y), walk), "concrete")
	_carts(root, CART_CORRAL_AT)


## One solid block of the shell over rect (x, z), from y bottom to the roof:
## corrugated metal above a cinder-block base (just the metal when it starts up
## high), with one collider.
static func _shell(root: Node3D, rect: Rect2, bottom: float) -> void:
	var height := SHELL_HEIGHT - bottom
	var center := Vector3(rect.get_center().x, bottom + height * 0.5, rect.get_center().y)
	var body := StaticBody3D.new()
	body.name = "Shell"
	root.add_child(body)
	body.position = center
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(rect.size.x, height, rect.size.y)
	shape.shape = box
	body.add_child(shape)
	if bottom > 0.0:
		_LowPoly.paint(_LowPoly.box(body, box.size, Vector3.ZERO, WALL), "corrugated")
		body.add_to_group("store_roof")
		return
	var base := BLOCK_BASE_HEIGHT
	_LowPoly.paint(_LowPoly.box(body, Vector3(rect.size.x, height - base, rect.size.y), Vector3(0.0, base * 0.5, 0.0), WALL), "corrugated")
	# The block base stands a hair proud of the metal, all round.
	_LowPoly.paint(_LowPoly.box(body, Vector3(rect.size.x + 0.06, base, rect.size.y + 0.06), Vector3(0.0, base * 0.5 - height * 0.5, 0.0), BLOCK), "cinderblock")


## The entrance block juts out of the front, taller than the rest, all in
## orange: two side walls, the header over the doorway, the glass sidelights and
## transom around the doors (store_interior.gd's), the canopy over the apron on
## two posts, and the name.
static func _entrance(root: Node3D) -> void:
	var room := _StoreInterior.ROOM
	var front := FRONT_X
	var face := room.end.x
	var top := ENTRANCE_HEIGHT
	var door_half := Constants.ART_DOOR_WIDTH * 0.5
	var door_z := _StoreInterior.DOOR_Z
	var depth := face - front
	for z: float in [room.position.y + ENTRANCE_WALL * 0.5, room.end.y - ENTRANCE_WALL * 0.5]:
		_LowPoly.paint(_LowPoly.box(root, Vector3(depth, top, ENTRANCE_WALL), Vector3(front + depth * 0.5, top * 0.5, z), ORANGE, true), "metal")
	var header_from := TRANSOM_TOP
	_LowPoly.paint(_LowPoly.box(root, Vector3(0.25, top - header_from, room.size.y), Vector3(face - 0.125, (top + header_from) * 0.5, room.get_center().y), ORANGE), "metal")
	_LowPoly.paint(_LowPoly.box(root, Vector3(depth + 0.4, 0.5, room.size.y + 0.4), Vector3(front + depth * 0.5, top + 0.1, room.get_center().y), ORANGE.darkened(0.15)), "metal").add_to_group("store_roof")
	_LowPoly.text_sign(root, "HOMIE DEPOT", Vector3(face + 0.05, 7.6, room.get_center().y), 230, Color.WHITE, PI * 0.5)
	# The glass: a sidelight either side of the doors (solid), the transom over
	# them, framed in brushed metal.
	var inner := Vector2(room.position.y + ENTRANCE_WALL, room.end.y - ENTRANCE_WALL)
	var door_height := Constants.ART_DOOR_HEIGHT
	for span: Vector2 in [Vector2(inner.x, door_z - door_half), Vector2(door_z + door_half, inner.y)]:
		var width := span.y - span.x
		var middle := (span.x + span.y) * 0.5
		var pane := _LowPoly.box(root, Vector3(0.12, door_height, width), Vector3(face - 0.06, door_height * 0.5, middle), Color(0.55, 0.7, 0.82), true)
		_glass(pane)
		_LowPoly.paint(_LowPoly.box(root, Vector3(0.16, 0.12, width), Vector3(face - 0.06, 0.06, middle), FRAME), "metal")
	for z: float in [door_z - door_half - 0.06, door_z + door_half + 0.06]:
		_LowPoly.paint(_LowPoly.box(root, Vector3(0.18, door_height, 0.12), Vector3(face - 0.06, door_height * 0.5, z), FRAME), "metal")
	_LowPoly.paint(_LowPoly.box(root, Vector3(0.2, 0.14, inner.y - inner.x), Vector3(face - 0.06, door_height + 0.07, room.get_center().y), FRAME), "metal")
	_glass(_LowPoly.box(root, Vector3(0.06, header_from - door_height - 0.14, inner.y - inner.x), Vector3(face - 0.09, (header_from + door_height + 0.14) * 0.5, room.get_center().y), Color(0.55, 0.7, 0.82)))
	# The canopy over the apron, a light under it, and its two posts.
	var canopy := _LowPoly.paint(_LowPoly.box(root, Vector3(3.0, 0.3, 8.0), Vector3(face + 1.4, 4.4, door_z), ORANGE.lightened(0.05)), "metal") as GeometryInstance3D
	canopy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_LowPoly.glow(root, Vector3(1.6, 0.03, 4.0), Vector3(face + 1.3, 4.24, door_z), Color(1.0, 0.95, 0.85), 0.8)
	for z: float in [door_z - 3.7, door_z + 3.7]:
		_LowPoly.paint(_LowPoly.cylinder(root, 0.14, 4.4, Vector3(face + 2.6, 2.2, z), DARK, true, 10), "metal")
	# Yellow bollards before the sidelights (never before the doors).
	var batch := _PropBatch.new(root)
	for z: float in BOLLARDS_Z:
		var at := Vector3(BOLLARD_X, 0.0, z)
		batch.add("bollard", Transform3D(Basis.IDENTITY, at))
		_post_collider(root, at, 0.14, 1.0)
	batch.commit()
	# Chefty doesn't drive into the lobby: a stop across the doorway on the vehicle
	# layer only, so the crew walks through four abreast and the truck's nose meets
	# the doors (docs/DECISIONS.md "Homie Depot's lobby").
	var stop := StaticBody3D.new()
	stop.name = "VehicleStop"
	stop.collision_layer = Constants.VEHICLE_LAYER
	stop.collision_mask = 0
	root.add_child(stop)
	var band := Constants.ART_DOOR_VEHICLE_STOP_Y
	stop.position = Vector3(face + VEHICLE_STOP_OUT, (band.x + band.y) * 0.5, door_z)
	var stop_shape := CollisionShape3D.new()
	var stop_box := BoxShape3D.new()
	stop_box.size = Vector3(VEHICLE_STOP_DEPTH, band.y - band.x, Constants.ART_DOOR_WIDTH + 0.2)
	stop_shape.shape = stop_box
	stop.add_child(stop_shape)
	stop.add_to_group("store_art_solid")


static func _glass(pane: Node3D) -> void:
	var view := pane as MeshInstance3D
	if view == null:
		view = pane.get_node_or_null("MeshInstance3D") as MeshInstance3D
		if view == null:
			for child: Node in pane.get_children():
				if child is MeshInstance3D:
					view = child
	if view == null:
		return
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.62, 0.78, 0.86, 0.3)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.metallic = 0.3
	glass.roughness = 0.06
	glass.metallic_specular = 0.9
	view.material_override = glass
	view.set_meta("keep_material", true)
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## A round post's collider (no mesh) standing at at.
static func _post_collider(root: Node3D, at: Vector3, radius: float, height: float) -> void:
	var body := StaticBody3D.new()
	body.name = "Post"
	root.add_child(body)
	body.position = at + Vector3(0.0, height * 0.5, 0.0)
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = height
	shape.shape = cylinder
	body.add_child(shape)
	body.add_to_group("store_art_solid")


## The garden center corner: three shelving units, stocked with what Homie
## Depot really sells today (props/shelf_stock.gd: each item stands in its
## slot with a price tag, supplies run out box by box, and your rank's locked
## items wait under a tarp). Its slots are shelf_stock's SHELF_SLOTS, on these units.
static func _garden_center(root: Node3D) -> void:
	for row: int in 3:
		_shelf(root, Vector3(10.0 + float(row) * 3.0, 0.0, -13.0))
	var stock := _ShelfStock.new()
	stock.name = "ShelfStock"
	stock.set("shop_id", "homie_depot")
	root.add_child(stock)


## A wooden shelving unit, solid, with three levels.
static func _shelf(root: Node3D, at: Vector3) -> void:
	var unit := StaticBody3D.new()
	root.add_child(unit)
	unit.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 2.4, 5.0)
	shape.shape = box
	shape.position.y = 1.2
	unit.add_child(shape)
	for x: float in [-0.45, 0.45]:
		for z: float in [-2.45, 0.0, 2.45]:
			_LowPoly.paint(_LowPoly.box(unit, Vector3(0.08, 2.4, 0.08), Vector3(x, 1.2, z), ORANGE.darkened(0.2)), "metal")
	for level: int in 3:
		_LowPoly.paint(_LowPoly.box(unit, Vector3(1.0, 0.06, 5.0), Vector3(0.0, 0.1 + float(level) * 0.8, 0.0), SHELF), "planks")


## Painted stalls, parked cars, light poles, and tree islands at the corners.
static func _parking(root: Node3D) -> void:
	for index: int in 7:
		var x := -9.0 + float(index) * 3.0
		_LowPoly.box(root, Vector3(0.12, 0.02, 5.0), Vector3(x, 0.01, 15.5), LINE)
	_LowPoly.box(root, Vector3(18.0, 0.02, 0.12), Vector3(0.0, 0.01, 13.0), LINE)
	var cars: Array[Color] = [Color(0.3, 0.42, 0.62), Color(0.85, 0.82, 0.74), Color(0.55, 0.15, 0.15)]
	# The east stalls stay empty: Lunch Money parks there (Constants.SHOP_SITES).
	for index: int in PARKED_CARS.size():
		_BuildQueue.later(root, func() -> void:
			var car := _YardModels.node("car", cars[index % cars.size()], Vector3.ONE, {"roughness": 0.5, "specular": 0.3})
			root.add_child(car)
			car.position = PARKED_CARS[index], "store car")
	_BuildQueue.later(root, func() -> void:
		for corner: Vector3 in LOT_LAMPS:
			_Neighborhood.lamp(root, corner, PI * 0.5 if corner.x > 0.0 else -PI * 0.5), "store lot lamps")
	# Tree islands: a curbed planter with a tree and mulch.
	for at: Vector3 in TREE_ISLANDS:
		_BuildQueue.later(root, func() -> void:
			_LowPoly.paint(_LowPoly.box(root, Vector3(3.0, 0.25, 3.0), at + Vector3(0.0, 0.12, 0.0), Color(0.7, 0.68, 0.64)), "concrete")
			_LowPoly.paint(_LowPoly.box(root, Vector3(2.6, 0.28, 2.6), at + Vector3(0.0, 0.14, 0.0), Color(0.36, 0.24, 0.17)), "dirt")
			_Trees.spawn(root, at + Vector3(0.0, 0.25, 0.0), 6.5, "broadleaf", "orange", int(at.x + at.z), false, at.x), "store tree island")


## The checkout booth around the counter: a striped awning on posts and a
## register, so the counter reads as the place you pay.
static func _checkout(root: Node3D, zone: Node3D) -> void:
	var counter := zone.get_node_or_null("Counter") as Node3D
	var at := counter.position if counter != null else Vector3(0.0, 0.55, -8.0)
	var base := Vector3(at.x, 0.0, at.z)
	if counter != null:
		var mesh := counter.get_node_or_null("Mesh") as MeshInstance3D
		if mesh != null:
			mesh.visible = false
	var kit := _MeshKit.new()
	kit.rbox(base + Vector3(0.0, 0.55, 0.0), Vector3(1.6, 0.55, 0.45), Color(0.62, 0.44, 0.28), 8.0)
	kit.rbox(base + Vector3(0.0, 1.12, 0.0), Vector3(1.7, 0.04, 0.55), Color(0.85, 0.82, 0.76), 6.0)
	kit.rbox(base + Vector3(0.0, 0.55, 0.47), Vector3(1.55, 0.4, 0.02), ORANGE, 8.0)
	# The register at Marty's elbow on the back edge (p1-ui, NB-M1): not between
	# him and the customer, and not at the counter's end either, where it sat
	# in the near corner of a customer's view, cut by the frame's edge.
	kit.rbox(base + Vector3(REGISTER_X, 1.3, REGISTER_Z), Vector3(0.22, 0.14, 0.18), DARK, 4.0)
	kit.rbox(base + Vector3(REGISTER_X, 1.5, REGISTER_Z - 0.13), Vector3(0.18, 0.12, 0.02), Color(0.3, 0.6, 0.5), 4.0, {"shade": false})
	for x: float in [-2.0, 2.0]:
		for z: float in [-1.2, 1.2]:
			kit.tube(PackedVector3Array([base + Vector3(x, 0.0, z), base + Vector3(x, 2.9, z)]), PackedFloat32Array([0.06, 0.06]), DARK, 8, {"jitter": 0.0})
	# The awning: alternating orange and white stripes, sloping toward the front.
	for stripe: int in 8:
		var x := -2.1 + 0.6 * float(stripe) + 0.3 - 0.3
		var color := ORANGE if stripe % 2 == 0 else Color(0.97, 0.96, 0.92)
		kit.rbox(base + Vector3(x + 0.3, 3.0, 0.0), Vector3(0.3, 0.05, 1.45), color, 6.0, {"basis": Basis(Vector3.RIGHT, -0.12)})
	var view := _Stylized.instance(kit.commit(), {"roughness": 0.7, "specular": 0.2})
	view.name = "CheckoutBooth"
	root.add_child(view)


## Chefty's loading bay: yellow hatching where the truck waits, in place of the
## old brown pad.
static func _loading_bay(root: Node3D, zone: Node3D) -> void:
	var pad := zone.get_node_or_null("TruckPad") as MeshInstance3D
	if pad == null:
		return
	pad.visible = false
	var center := Vector3(pad.position.x, 0.0, pad.position.z)
	for side: float in [-1.0, 1.0]:
		_LowPoly.box(root, Vector3(0.15, 0.02, 7.0), center + Vector3(side * 1.9, 0.015, 0.0), STRIPE)
		_LowPoly.box(root, Vector3(3.95, 0.02, 0.15), center + Vector3(0.0, 0.015, side * 3.5), STRIPE)
	for index: int in 5:
		var stripe := _LowPoly.box(root, Vector3(0.18, 0.02, 3.4), center + Vector3(-1.2 + float(index) * 0.6, 0.016, -1.6), STRIPE)
		stripe.rotation.y = 0.6


## Art chunk 8's pieces on the lot, each where Constants.STORE_LAYOUT reserves
## it ("art" entries): the roadside pylon sign, the propane cage, the mulch and
## soil pallets beside the garden center, a second cart corral, and the
## season's stock along the store front (levels/dressing/store_season_stock.gd).
static func _lot_extras(root: Node3D) -> void:
	var layout: Dictionary = Constants.STORE_LAYOUT
	_pylon(root, layout["pylon"]["at"], float(layout["pylon"]["yaw"]))
	_propane_cage(root, layout["propane_cage"]["at"], float(layout["propane_cage"]["yaw"]))
	var batch := _PropBatch.new(root)
	for pallet: Array in GARDEN_PALLETS:
		var at: Vector3 = pallet[1]
		var turn := Basis(Vector3.UP, float(pallet[2]))
		batch.add(str(pallet[0]), Transform3D(turn, at))
		var footprint := turn * Vector3(_StoreProps.PALLET.x, 0.0, _StoreProps.PALLET.z)
		_box_collider(root, "Pallet", at + Vector3(0.0, 0.3, 0.0), Vector3(absf(footprint.x), 0.6, absf(footprint.z)))
	batch.commit()
	_post_sign(root, str(_Strings.SIGNS["mulch"]), Vector3(6.9, 0.0, -17.45), 0.0)
	var corral: Dictionary = layout["cart_corral_east"]
	var corral_root := Node3D.new()
	corral_root.name = "CartCorralEast"
	root.add_child(corral_root)
	corral_root.position = corral["at"]
	corral_root.rotation.y = float(corral["yaw"])
	_carts(corral_root, Vector3.ZERO, true)
	var stock: Node3D = _SeasonStock.new()
	stock.name = "SeasonStock"
	stock.set("area", layout["seasonal_display"]["rect"])
	root.add_child(stock)


## Homie Depot's roadside pylon: two steel legs and a tall orange cabinet with
## the name and the slogan on both faces (Strings.SIGNS "store_pylon"), facing
## along yaw so drivers on the cross street read it both ways.
static func _pylon(root: Node3D, at: Vector3, yaw: float) -> void:
	var holder := Node3D.new()
	holder.name = "Pylon"
	root.add_child(holder)
	holder.position = at
	holder.rotation.y = yaw
	var kit := _MeshKit.new()
	var steel := Color(0.36, 0.38, 0.42)
	for x: float in [-0.75, 0.75]:
		kit.box(Vector3(x, 3.4, 0.0), Vector3(0.28, 6.8, 0.28), steel)
	kit.box(Vector3(0.0, 0.25, 0.0), Vector3(1.9, 0.5, 0.5), Color(0.66, 0.65, 0.62))
	kit.rbox(Vector3(0.0, 8.2, 0.0), Vector3(1.9, 1.5, 0.3), ORANGE, 10.0, {"detail": 1})
	kit.box(Vector3(0.0, 6.35, 0.0), Vector3(3.6, 0.7, 0.5), Color(0.97, 0.96, 0.92))
	kit.box(Vector3(0.0, 9.85, 0.0), Vector3(3.9, 0.12, 0.66), ORANGE.darkened(0.2))
	var view := _Stylized.instance(kit.commit(), {"roughness": 0.6, "specular": 0.25})
	holder.add_child(view)
	_box_collider(holder, "PylonBase", Vector3(0.0, 0.5, 0.0), Vector3(1.9, 1.0, 0.5))
	var lines := str(_Strings.SIGNS["store_pylon"]).split("\n", false, 1)
	for side: float in [-1.0, 1.0]:
		var title := _LowPoly.text_sign(holder, lines[0], Vector3(0.0, 8.35, side * 0.31), 150, Color.WHITE, 0.0 if side > 0.0 else PI)
		title.pixel_size = 0.009
		title.outline_size = 18
		if lines.size() > 1:
			var tagline := _LowPoly.text_sign(holder, lines[1], Vector3(0.0, 6.35, side * 0.26), 56, Color(0.2, 0.2, 0.22), 0.0 if side > 0.0 else PI)
			tagline.pixel_size = 0.0045
			tagline.outline_size = 0
			tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			tagline.width = 3.4 / tagline.pixel_size


## The propane exchange cage against the store wall, facing the lot, with its
## red header's words (Strings.SIGNS "propane").
static func _propane_cage(root: Node3D, at: Vector3, yaw: float) -> void:
	var holder := Node3D.new()
	holder.name = "PropaneCage"
	root.add_child(holder)
	holder.position = at
	holder.rotation.y = yaw
	holder.add_child(_PropCatalog.node("propane_cage"))
	_box_collider(holder, "Cage", Vector3(0.0, 0.95, 0.0), Vector3(1.95, 1.9, 0.95))
	var words := _LowPoly.text_sign(holder, str(_Strings.SIGNS["propane"]), Vector3(0.0, 1.9, -0.48), 40, Color.WHITE, PI)
	words.pixel_size = 0.0034
	words.outline_size = 0
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.width = 1.35 / words.pixel_size


## A chalkboard sign on a post, its words facing yaw (0 reads from +Z).
static func _post_sign(root: Node3D, words: String, at: Vector3, yaw: float) -> void:
	var holder := Node3D.new()
	holder.name = "PostSign"
	root.add_child(holder)
	holder.position = at
	holder.rotation.y = yaw
	var kit := _MeshKit.new()
	kit.box(Vector3(0.0, 0.6, -0.03), Vector3(0.07, 1.2, 0.07), Color(0.45, 0.33, 0.22))
	kit.box(Vector3(0.0, 1.1, 0.0), Vector3(0.62, 0.48, 0.03), Color(0.16, 0.2, 0.18))
	kit.box(Vector3(0.0, 1.1, -0.006), Vector3(0.68, 0.54, 0.02), Color(0.55, 0.4, 0.26))
	holder.add_child(_Stylized.instance(kit.commit(), {"roughness": 0.85, "specular": 0.1}))
	var label := _LowPoly.text_sign(holder, words, Vector3(0.0, 1.1, 0.02), 32, Color(0.95, 0.94, 0.88), 0.0)
	label.pixel_size = 0.0032
	label.outline_size = 0
	_post_collider(holder, Vector3.ZERO, 0.06, 1.2)


## A box collider (no mesh) under parent, in its space.
static func _box_collider(parent: Node3D, name: String, center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = name
	parent.add_child(body)
	body.position = center
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.add_to_group("store_art_solid")


## A cart corral by the parking lot: round rails on posts and a row of carts
## parked in it, handles toward the open end (+Z). One mesh a corral. art_piece:
## its rails join store_art_solid (a corral art added in its own reservation;
## the west one is the store's own, docs/DECISIONS.md).
static func _carts(root: Node3D, at: Vector3, art_piece: bool = false) -> void:
	var kit := _MeshKit.new()
	var rail := Color(0.85, 0.85, 0.82)
	for side: float in [-1.0, 1.0]:
		for y: float in [0.5, 0.9]:
			kit.tube(PackedVector3Array([at + Vector3(side * 0.6, y, -2.0), at + Vector3(side * 0.6, y, 2.0)]), PackedFloat32Array([0.035, 0.035]), rail, 8, {"jitter": 0.0})
		for z: float in [-2.0, 0.0, 2.0]:
			kit.tube(PackedVector3Array([at + Vector3(side * 0.6, 0.0, z), at + Vector3(side * 0.6, 0.94, z)]), PackedFloat32Array([0.045, 0.045]), rail, 8, {"jitter": 0.0})
	# The closed end, toward the store.
	kit.tube(PackedVector3Array([at + Vector3(-0.6, 0.9, -2.0), at + Vector3(0.6, 0.9, -2.0)]), PackedFloat32Array([0.035, 0.035]), rail, 8, {"jitter": 0.0})
	for index: int in CART_COUNT:
		_cart(kit, at + Vector3(0.0, 0.0, -1.45 + float(index) * CART_SPACING))
	var view := _Stylized.instance(kit.commit(), {"roughness": 0.45, "specular": 0.5})
	view.name = "CartCorral"
	root.add_child(view)
	# The rails and the closed end are solid (the carts sit inside them).
	var body := StaticBody3D.new()
	body.name = "CartCorralRails"
	root.add_child(body)
	body.position = at
	for piece: Array in [[Vector3(-0.6, 0.47, 0.0), Vector3(0.1, 0.94, 4.1)], [Vector3(0.6, 0.47, 0.0), Vector3(0.1, 0.94, 4.1)], [Vector3(0.0, 0.47, -2.0), Vector3(1.3, 0.94, 0.1)]]:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = piece[1]
		shape.shape = box
		shape.position = piece[0]
		body.add_child(shape)
	if art_piece:
		body.add_to_group("store_art_solid")


## How many carts a corral holds, and how far apart they park (m; a cart is 0.9 long).
const CART_COUNT: int = 3
const CART_SPACING: float = 0.98


## A shopping cart standing on its four casters at at, its handle to +Z: a wire
## basket (a floor, open sides with rails), a bottom rack, the legs down to the
## casters, and Homie Depot's orange handle.
static func _cart(kit: _MeshKit, at: Vector3) -> void:
	var handle := ORANGE
	var wire := Color(0.78, 0.79, 0.78)
	var frame := Color(0.6, 0.62, 0.64)
	var tire := Color(0.12, 0.12, 0.13)
	var half := Vector3(0.27, 0.0, 0.43)
	var floor_y := 0.55
	var top_y := 0.98
	# The basket: its floor and four sides, each a frame of rails with a few wires.
	kit.box(at + Vector3(0.0, floor_y, 0.0), Vector3(half.x * 2.0, 0.02, half.z * 2.0), wire)
	for y: float in [floor_y + 0.14, floor_y + 0.28, top_y]:
		for side: float in [-1.0, 1.0]:
			kit.box(at + Vector3(side * half.x, y, 0.0), Vector3(0.02, 0.02, half.z * 2.0), wire)
			kit.box(at + Vector3(0.0, y, side * half.z), Vector3(half.x * 2.0, 0.02, 0.02), wire)
	for side: float in [-1.0, 1.0]:
		for step: int in 5:
			var z := -half.z + 0.06 + float(step) * (half.z * 2.0 - 0.12) / 4.0
			kit.box(at + Vector3(side * half.x, (floor_y + top_y) * 0.5, z), Vector3(0.015, top_y - floor_y, 0.015), wire)
		for step: int in 3:
			var x := -half.x + 0.09 + float(step) * (half.x * 2.0 - 0.18) / 2.0
			kit.box(at + Vector3(x, (floor_y + top_y) * 0.5, side * half.z), Vector3(0.015, top_y - floor_y, 0.015), wire)
	# The handle on two short posts at the back.
	for side: float in [-1.0, 1.0]:
		kit.box(at + Vector3(side * (half.x - 0.02), top_y + 0.06, half.z + 0.06), Vector3(0.025, 0.14, 0.025), frame)
	kit.box(at + Vector3(0.0, top_y + 0.13, half.z + 0.08), Vector3(half.x * 2.0 + 0.04, 0.05, 0.05), handle)
	# The legs, the bottom rack, and the casters (wheels standing, along x).
	for side: float in [-1.0, 1.0]:
		for end: float in [-1.0, 1.0]:
			kit.box(at + Vector3(side * (half.x - 0.04), (0.12 + floor_y) * 0.5, end * (half.z - 0.06)), Vector3(0.03, floor_y - 0.12, 0.03), frame)
			_P.wheel(kit, at + Vector3(side * (half.x - 0.04), 0.06, end * (half.z - 0.06)), 0.06, 0.03, tire, frame)
	kit.box(at + Vector3(0.0, 0.16, 0.0), Vector3(half.x * 2.0 - 0.06, 0.02, half.z * 2.0 - 0.1), wire)
