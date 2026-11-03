extends Node3D

## Authority: local, cosmetic. The season's stock out front of Homie Depot (art
## chunk 8; docs/GAME.md "Homie Depot, inside and out"), on the walk north of
## the doors (Constants.STORE_LAYOUT "seasonal_display"): hay bales stacked with
## pumpkins, mums and a scarecrow in autumn; a netted holiday-tree lot and
## pallets of SNOW-B-GONE in winter; flower flats, soil and mulch in spring;
## kiddie pools leaning on the wall, a pool float and the grills in summer.
## In group "seasonal": core/seasons.gd calls apply_season on every peer the
## morning a season turns, and it swaps its stock (pieces and their colliders)
## for the new season's. Nothing here is networked.

const _PropCatalog = preload("res://props/prop_catalog.gd")
const _LowPoly = preload("res://props/low_poly.gd")
const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const _Strings = preload("res://ui/strings.gd")

## Each season's pieces, in StoreZone space: [kind, at, yaw, scale, collider
## size (Vector3.ZERO for none; centered over at, on the ground)]. Every piece
## and collider stays inside STORE_LAYOUT "seasonal_display" (x -12..-9.2,
## z 6.4..12.8); net/dev/art_test.gd A14 checks the colliders.
const STOCK: Array = [
	# Autumn: a hay-bale stack with pumpkins on it and in front, mums, a scarecrow.
	[
		["hay_bale", Vector3(-11.25, 0.0, 7.05), PI * 0.5, 1.0, Vector3(0.6, 1.0, 1.1)],
		["hay_bale", Vector3(-11.25, 0.0, 8.15), PI * 0.5, 1.0, Vector3(0.6, 1.0, 1.1)],
		["hay_bale", Vector3(-11.25, 0.0, 9.25), PI * 0.5, 1.0, Vector3(0.6, 1.0, 1.1)],
		["hay_bale", Vector3(-11.25, 0.5, 7.6), PI * 0.5, 1.0, Vector3.ZERO],
		["hay_bale", Vector3(-11.25, 0.5, 8.7), PI * 0.5 + 0.05, 1.0, Vector3.ZERO],
		["pumpkin_big", Vector3(-11.2, 1.0, 7.5), 0.4, 1.0, Vector3.ZERO],
		["pumpkin", Vector3(-11.3, 1.0, 8.4), 1.1, 1.0, Vector3.ZERO],
		["pumpkin_small", Vector3(-11.15, 1.0, 9.0), 2.0, 1.0, Vector3.ZERO],
		["pumpkin", Vector3(-11.2, 0.5, 9.5), 0.2, 1.0, Vector3.ZERO],
		["pumpkin_big", Vector3(-10.35, 0.0, 7.3), 2.5, 1.0, Vector3(0.6, 0.6, 0.6)],
		["pumpkin", Vector3(-10.4, 0.0, 8.2), 0.9, 1.0, Vector3(0.45, 0.45, 0.45)],
		["pumpkin_small", Vector3(-9.85, 0.0, 7.85), 1.7, 1.0, Vector3.ZERO],
		["pumpkin", Vector3(-10.25, 0.0, 9.15), 3.0, 1.0, Vector3(0.45, 0.45, 0.45)],
		["mums_pot", Vector3(-10.0, 0.0, 10.4), 0.0, 1.0, Vector3(0.5, 0.6, 0.5)],
		["mums_pot", Vector3(-10.0, 0.0, 11.1), 0.7, 1.0, Vector3(0.5, 0.6, 0.5)],
		["mums_pot", Vector3(-10.6, 0.0, 10.75), 1.4, 1.0, Vector3(0.5, 0.6, 0.5)],
		["scarecrow", Vector3(-11.3, 0.0, 11.9), -PI * 0.5, 1.0, Vector3(0.3, 2.0, 0.3)],
	],
	# Winter: the netted holiday-tree lot and two pallets of SNOW-B-GONE.
	[
		["holiday_tree_lot", Vector3(-10.57, 0.0, 8.6), PI * 0.5, 0.85, Vector3(2.66, 1.0, 3.95)],
		["salt_pallet", Vector3(-11.1, 0.0, 11.9), 0.03, 1.0, Vector3(1.2, 0.8, 1.0)],
		["salt_pallet", Vector3(-9.85, 0.0, 11.9), -0.04, 1.0, Vector3(1.2, 0.8, 1.0)],
	],
	# Spring: flower flats, a pallet of soil and one of mulch.
	[
		["flower_flats", Vector3(-11.05, 0.0, 7.6), -PI * 0.5, 1.0, Vector3(0.85, 1.2, 2.05)],
		["flower_flats", Vector3(-11.05, 0.0, 9.9), -PI * 0.5, 1.0, Vector3(0.85, 1.2, 2.05)],
		["soil_pallet", Vector3(-11.1, 0.0, 11.9), 0.0, 1.0, Vector3(1.2, 0.6, 1.0)],
		["mulch_pallet", Vector3(-9.85, 0.0, 11.9), 0.05, 1.0, Vector3(1.2, 0.6, 1.0)],
	],
	# Summer: kiddie pools leaning on the wall, gas grills, a beach umbrella.
	[
		["kiddie_pool", Vector3(-11.55, 0.0, 7.7), 0.0, 1.0, Vector3.ZERO],
		["kiddie_pool", Vector3(-11.1, 0.0, 8.6), 0.0, 1.0, Vector3(1.3, 1.9, 3.9)],
		["pool_float", Vector3(-9.95, 0.0, 7.5), 0.5, 1.0, Vector3.ZERO],
		["bbq_gas", Vector3(-10.1, 0.0, 11.6), -PI * 0.5, 1.0, Vector3(0.6, 1.1, 1.7)],
		["bbq_kettle", Vector3(-11.25, 0.0, 11.9), 0.3, 1.0, Vector3(0.6, 1.0, 0.6)],
	],
]
## How far a kiddie pool leans back against the wall from standing upright (rad).
const POOL_LEAN: float = 0.22

## The reserved rect this stands in (StoreZone x, z), set by store_dressing.gd.
var area: Rect2 = Rect2()
var season: int = -1


func _ready() -> void:
	add_to_group("seasonal")
	apply_season(Seasons.current())


## Every peer, the morning a season turns (core/seasons.gd): this season's stock.
func apply_season(next: int) -> void:
	next = posmod(next, 4)
	if next == season and get_node_or_null("Stock") != null:
		return
	season = next
	var old := get_node_or_null("Stock")
	if old != null:
		remove_child(old)
		old.queue_free()
	var stock := Node3D.new()
	stock.name = "Stock"
	add_child(stock)
	for piece: Array in STOCK[season]:
		_place(stock, piece)
	if season == 1:
		_salt_sign(stock, Vector3(-10.5, 0.0, 11.25))


## The pieces' colliders' footprints (x, z) in StoreZone space, for the art test.
func collider_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for piece: Array in STOCK[maxi(season, 0)]:
		var size: Vector3 = piece[4]
		if size == Vector3.ZERO:
			continue
		var at: Vector3 = piece[1]
		out.append(Rect2(at.x - size.x * 0.5, at.z - size.z * 0.5, size.x, size.z))
	return out


func _place(stock: Node3D, piece: Array) -> void:
	var kind := str(piece[0])
	var at: Vector3 = piece[1]
	var view := _PropCatalog.node(kind)
	stock.add_child(view)
	view.position = at
	view.rotation.y = float(piece[2])
	view.scale = Vector3.ONE * float(piece[3])
	if kind == "kiddie_pool":
		# Stood on its rim against the store wall, leaning back a little.
		view.rotation = Vector3(0.0, 0.0, -(PI * 0.5 - POOL_LEAN))
		view.position = at + Vector3(0.0, 0.95, 0.0)
	var size: Vector3 = piece[4]
	if size == Vector3.ZERO:
		return
	var body := StaticBody3D.new()
	body.name = "Solid"
	stock.add_child(body)
	body.position = Vector3(at.x, size.y * 0.5, at.z)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.add_to_group("store_art_solid")


## The SNOW-B-GONE sign on a stake between the tree lot and the salt.
func _salt_sign(stock: Node3D, at: Vector3) -> void:
	var holder := Node3D.new()
	holder.name = "SaltSign"
	stock.add_child(holder)
	holder.position = at
	holder.rotation.y = PI * 0.5
	var kit := _MeshKit.new()
	kit.box(Vector3(0.0, 0.55, -0.02), Vector3(0.05, 1.1, 0.05), Color(0.45, 0.33, 0.22))
	kit.box(Vector3(0.0, 1.05, 0.0), Vector3(0.8, 0.42, 0.03), Color(0.2, 0.42, 0.78))
	holder.add_child(_Stylized.instance(kit.commit(), {"roughness": 0.7, "specular": 0.15, "snow": 1.0}))
	var words := _LowPoly.text_sign(holder, str(_Strings.SIGNS["salt"]), Vector3(0.0, 1.05, 0.02), 36, Color.WHITE, 0.0)
	words.pixel_size = 0.0034
	words.outline_size = 0
