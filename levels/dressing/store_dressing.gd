extends RefCounted

## Authority: local, cosmetic. The store zone: Homie Depot on a street corner.
## A big-box building along the west edge with a tall orange entrance, sliding
## doors, and the sign; a parking lot with painted stalls, parked cars, light
## poles, a cart corral, and tree islands; a garden center stocked with rakes,
## leaf bags, and wheelbarrows; a checkout booth with a striped awning around
## the counter; Chefty's striped loading bay; and the roads out, including the
## one Chefty drives east on. Keeps clear of the counter (0, -8), the gate to
## the lot (0, -16), the spawns near (1, 6), and Chefty's pad at (10, 8).
## Solid pieces keep simple colliders so players can't walk through them.

const _LowPoly = preload("res://props/low_poly.gd")
const _Trees = preload("res://props/trees.gd")
const _YardModels = preload("res://props/yard_models.gd")
const _Neighborhood = preload("res://levels/dressing/neighborhood.gd")
const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const WALL := Color(0.86, 0.8, 0.66)
const ROOF := Color(0.3, 0.32, 0.36)
const ORANGE := Color(0.95, 0.5, 0.15)
const DARK := Color(0.16, 0.17, 0.2)
const SHELF := Color(0.5, 0.36, 0.24)
const LINE := Color(0.95, 0.94, 0.88)
const STRIPE := Color(0.95, 0.8, 0.2)


static func dress(zone: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Dressing"
	zone.add_child(root)
	_building(root)
	_garden_center(root)
	_parking(root)
	_checkout(root, zone)
	_loading_bay(root, zone)
	# The cross street east of the lot, and the road Chefty leaves on toward the job.
	_Neighborhood.road(root, Vector3(27.0, 0.0, -160.0), Vector3(27.0, 0.0, 160.0))
	_Neighborhood.road(root, Vector3(32.0, 0.0, 8.6), Vector3(300.0, 0.0, 15.2), 8.8, false)
	_Neighborhood.road(root, Vector3(21.0, 0.0, 8.0), Vector3(22.6, 0.0, 8.0), 8.8, false)
	for z: float in range(-140, 141, 28):
		_Neighborhood.lamp(root, Vector3(32.3, 0.0, float(z)), PI * 0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var crowns: Array[String] = ["orange", "red", "yellow", "rust"]
	for z: float in range(-130, 131, 18):
		if absf(float(z) - 10.0) < 12.0:
			continue
		_Trees.spawn(root, Vector3(36.0, 0.0, float(z)), rng.randf_range(6.5, 8.5), "broadleaf", crowns[rng.randi() % crowns.size()], int(z), false, rng.randf() * TAU)


## A big box store: walls, a flat roof with a parapet, an orange band, a tall
## orange entrance with sliding doors, windows, and the name in big letters.
static func _building(root: Node3D) -> void:
	var front := -12.0
	var depth := 22.0
	var center_x := front - depth * 0.5
	# The part inside the pad is solid; the rest is out of reach anyway.
	_LowPoly.paint(_LowPoly.box(root, Vector3(depth, 8.0, 34.0), Vector3(center_x, 4.0, -2.0), WALL, true), "concrete")
	_LowPoly.paint(_LowPoly.box(root, Vector3(depth + 0.4, 0.9, 34.4), Vector3(center_x, 8.4, -2.0), ROOF.lightened(0.15)), "concrete")
	_LowPoly.paint(_LowPoly.box(root, Vector3(0.25, 1.2, 34.0), Vector3(front + 0.1, 6.6, -2.0), ORANGE), "metal")
	# Wall panel seams every few meters.
	for z: float in range(-18, 15, 4):
		_LowPoly.box(root, Vector3(0.06, 8.0, 0.08), Vector3(front + 0.04, 4.0, float(z)), WALL.darkened(0.12))
	# The entrance block juts out, taller than the rest, all in orange.
	var entrance := Vector3(front + 1.0, 0.0, -2.0)
	_LowPoly.paint(_LowPoly.box(root, Vector3(2.0, 10.5, 10.0), entrance + Vector3(0.0, 5.25, 0.0), ORANGE, true), "metal")
	_LowPoly.paint(_LowPoly.box(root, Vector3(2.4, 0.5, 10.4), entrance + Vector3(0.0, 10.6, 0.0), ORANGE.darkened(0.15)), "metal")
	_LowPoly.text_sign(root, "HOMIE DEPOT", entrance + Vector3(1.05, 7.6, 0.0), 230, Color.WHITE, PI * 0.5)
	_LowPoly.box(root, Vector3(0.12, 4.0, 6.0), entrance + Vector3(1.0, 2.0, 0.0), DARK)
	for z: float in [-1.4, 1.4]:
		_LowPoly.window(root, 2.5, 3.4, entrance + Vector3(1.07, 1.8, z), DARK, PI * 0.5)
	_LowPoly.paint(_LowPoly.box(root, Vector3(3.0, 0.3, 8.0), entrance + Vector3(2.4, 4.4, 0.0), ORANGE.lightened(0.05)), "metal")
	for z: float in [-3.7, 3.7]:
		_LowPoly.paint(_LowPoly.cylinder(root, 0.14, 4.4, entrance + Vector3(3.6, 2.2, z), DARK, false, 10), "metal")
	# Display windows along the front.
	for z: float in [-15.0, -11.0, 7.0, 11.0]:
		_LowPoly.window(root, 3.0, 2.0, Vector3(front + 0.03, 2.2, z), Color(0.85, 0.85, 0.82), PI * 0.5)
	# A low concrete walk along the front.
	_LowPoly.paint(_LowPoly.box(root, Vector3(3.0, 0.15, 34.0), Vector3(front + 1.5, 0.05, -2.0), Color(0.72, 0.7, 0.66)), "concrete")
	_carts(root, Vector3(-7.5, 0.0, 10.0))


## The garden center corner: shelves stocked with the gear you buy here.
static func _garden_center(root: Node3D) -> void:
	for row: int in 3:
		var at := Vector3(10.0 + float(row) * 3.0, 0.0, -13.0)
		_shelf(root, at)
		for level: int in 3:
			var y := 0.12 + float(level) * 0.8
			for slot: int in 4:
				var spot := at + Vector3(0.0, y, -1.8 + float(slot) * 1.2)
				match (row + level + slot) % 3:
					0:
						for index: int in 2:
							var bag := _YardModels.node("leaf_bag")
							root.add_child(bag)
							bag.position = spot + Vector3(0.0, 0.0, -0.22 + float(index) * 0.44)
							bag.scale = Vector3.ONE * 0.75
							bag.rotation.y = float(slot + index)
					1:
						for index: int in 3:
							var rake := _YardModels.node("rake")
							root.add_child(rake)
							rake.position = spot + Vector3(-0.2, 0.0, -0.3 + float(index) * 0.3)
							rake.rotation = Vector3(0.0, PI * 0.5, 0.12)
							rake.scale = Vector3.ONE * 0.45
					_:
						var barrow := _YardModels.node("wheelbarrow", [ORANGE, Color(0.25, 0.5, 0.3), Color(0.3, 0.45, 0.7)][(row + slot) % 3])
						root.add_child(barrow)
						barrow.position = spot
						barrow.scale = Vector3.ONE * 0.6
						barrow.rotation.y = PI * 0.5


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
	for index: int in [0, 2, 5]:
		var car := _YardModels.node("car", cars[index % cars.size()], Vector3.ONE, {"roughness": 0.5, "specular": 0.3})
		root.add_child(car)
		car.position = Vector3(-7.5 + float(index) * 3.0, 0.0, 15.6)
	for corner: Vector3 in [Vector3(17, 0, 17), Vector3(17, 0, -17), Vector3(-9, 0, 17), Vector3(4, 0, 17)]:
		_Neighborhood.lamp(root, corner, PI * 0.5 if corner.x > 0.0 else -PI * 0.5)
	# Tree islands: a curbed planter with a tree and mulch.
	for at: Vector3 in [Vector3(18.5, 0.0, -3.0), Vector3(-10.0, 0.0, 18.5), Vector3(18.5, 0.0, 18.5)]:
		_LowPoly.paint(_LowPoly.box(root, Vector3(3.0, 0.25, 3.0), at + Vector3(0.0, 0.12, 0.0), Color(0.7, 0.68, 0.64)), "concrete")
		_LowPoly.paint(_LowPoly.box(root, Vector3(2.6, 0.28, 2.6), at + Vector3(0.0, 0.14, 0.0), Color(0.36, 0.24, 0.17)), "dirt")
		_Trees.spawn(root, at + Vector3(0.0, 0.25, 0.0), 6.5, "broadleaf", "orange", int(at.x + at.z), false, at.x)


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
	kit.rbox(base + Vector3(0.9, 1.3, 0.05), Vector3(0.22, 0.14, 0.18), DARK, 4.0)
	kit.rbox(base + Vector3(0.9, 1.5, -0.08), Vector3(0.18, 0.12, 0.02), Color(0.3, 0.6, 0.5), 4.0, {"shade": false})
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


## A cart corral by the parking lot: a rail frame and a few nested carts.
static func _carts(root: Node3D, at: Vector3) -> void:
	for side: float in [-1.0, 1.0]:
		_LowPoly.paint(_LowPoly.box(root, Vector3(0.08, 0.08, 4.0), at + Vector3(side * 0.6, 0.9, 0), Color(0.85, 0.85, 0.82)), "metal")
		for z: float in [-2.0, 2.0]:
			_LowPoly.paint(_LowPoly.box(root, Vector3(0.08, 0.9, 0.08), at + Vector3(side * 0.6, 0.45, z), Color(0.85, 0.85, 0.82)), "metal")
	for index: int in 3:
		_cart(root, at + Vector3(0, 0, -1.2 + index * 0.7))


static func _cart(root: Node3D, at: Vector3) -> void:
	var red := Color(0.85, 0.3, 0.15)
	var wire := Color(0.8, 0.8, 0.78)
	_LowPoly.paint(_LowPoly.box(root, Vector3(0.6, 0.45, 0.9), at + Vector3(0, 0.75, 0), wire), "metal")
	_LowPoly.paint(_LowPoly.box(root, Vector3(0.62, 0.06, 0.06), at + Vector3(0, 1.05, 0.5), red), "metal")
	for x: float in [-0.25, 0.25]:
		for z: float in [-0.35, 0.35]:
			_LowPoly.paint(_LowPoly.cylinder(root, 0.06, 0.04, at + Vector3(x, 0.07, z), Color(0.12, 0.12, 0.13)), "metal")
