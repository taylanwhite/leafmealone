extends RefCounted

## Authority: local, cosmetic, with simple colliders. Every shop's spot in town
## (docs/GAME.md "Shops"; gap-specs shops chunk 4): reads Constants.SHOP_SITES,
## the one source of where shops stand, and builds each site in its zone with
## build_site(), which the drivable town can call wherever a shop ends up. Each
## site gets its keeper (npcs/store_clerk.gd, at the site's keeper spot) and an
## hours sign that keeps itself current: OPEN 7 AM - 9 PM, CLOSED · Opens ...,
## GONE FISHIN' on Rusty's day off, or COMING SOON with the rank that opens it.
## The back room gets the delivery pallet's base (the crates are shops chunk 8).
##
## Until their own chunks build them, Rusty works from a plank counter on two
## oil drums (his fenced yard, shack and scale are shops chunk 5) and Dot from a
## folding table in her parking stall (the Lunch Money truck is shops chunk 6).
## The Snak-o-Matic's machine is chunk 6 too.

const _LowPoly = preload("res://props/low_poly.gd")
const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const _ShopModels = preload("res://props/shop_models.gd")
const _Keeper = preload("res://npcs/store_clerk.gd")
const _Strings = preload("res://ui/strings.gd")
const _BuildQueue = preload("res://levels/build_queue.gd")
const BOARD := Color(0.17, 0.22, 0.2)
const FRAME := Color(0.55, 0.38, 0.22)
const ORANGE := Color(0.95, 0.5, 0.15)
const DARK := Color(0.16, 0.17, 0.2)
const RUST := Color(0.55, 0.27, 0.14)
const DRUM := Color(0.28, 0.42, 0.36)
const PLANK := Color(0.6, 0.45, 0.3)
const TABLE := Color(0.92, 0.92, 0.9)
const CAGE := Color(0.7, 0.72, 0.74)


## Builds every site in Constants.SHOP_SITES into its zone of the world.
static func dress(world: Node3D) -> void:
	for shop_id: String in Constants.SHOP_SITES:
		var site: Dictionary = Constants.SHOP_SITES[shop_id]
		var zone := world.get_node_or_null(str(site.get("zone", ""))) as Node3D
		if zone != null:
			# One site a BuildQueue step (levels/build_queue.gd): a keeper is a whole body.
			_BuildQueue.later(zone, func() -> void: build_site(zone, shop_id, site), "shop site")


## One shop's site, in zone's space (site is its Constants.SHOP_SITES entry).
static func build_site(zone: Node3D, shop_id: String, site: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "ShopSite_" + shop_id
	zone.add_child(root)
	var counter: Vector3 = site.get("counter", Vector3.ZERO)
	match shop_id:
		"homie_depot":
			# Hung from the checkout awning's front edge, facing the customers.
			_hanging_sign(root, shop_id, counter + Vector3(0.0, 2.45, 1.25), 0.0)
		"rustys":
			_drum_counter(root, counter)
			_post_sign(root, shop_id, counter + Vector3(-0.4, 0.0, -1.6), -PI * 0.5)
		"lunch_money":
			var keeper_at: Vector3 = site.get("keeper", counter)
			_folding_table(root, (keeper_at + counter) * 0.5)
			_post_sign(root, shop_id, counter + Vector3(0.5, 0.0, 1.7), PI * 0.5)
		"back_room":
			_pallet_base(root, counter)
	var shop: Dictionary = Catalog.SHOPS.get(shop_id, {})
	if str(shop.get("keeper", "")) != "" and site.has("keeper"):
		var keeper := _Keeper.new()
		keeper.set("shop_id", shop_id)
		# Marty keeps his old node name; tests and the cast find him by it too.
		keeper.name = "StoreClerk" if shop_id == "homie_depot" else "Keeper_" + shop_id
		zone.add_child(keeper)
		keeper.position = site["keeper"]


## The hours sign's words for a shop right now (every peer works them out from
## the clock and the crew's rank, so the sign needs no network).
static func sign_text(shop_id: String, shops: Node, clock: Node) -> String:
	return HoursSign.text_for(shop_id, shops, clock)


## A sign board hung on two chains, its words on the side facing yaw.
static func _hanging_sign(root: Node3D, shop_id: String, at: Vector3, yaw: float) -> void:
	var holder := Node3D.new()
	holder.position = at
	holder.rotation.y = yaw
	root.add_child(holder)
	var kit := _MeshKit.new()
	kit.rbox(Vector3.ZERO, Vector3(0.85, 0.24, 0.025), BOARD, 6.0, {"detail": 1})
	kit.rbox(Vector3(0.0, 0.0, -0.005), Vector3(0.9, 0.28, 0.02), ORANGE, 6.0, {"detail": 1})
	for x: float in [-0.7, 0.7]:
		kit.tube(PackedVector3Array([Vector3(x, 0.26, 0.0), Vector3(x, 0.52, 0.0)]), PackedFloat32Array([0.01, 0.01]), DARK, 5, {"jitter": 0.0})
	holder.add_child(_Stylized.instance(kit.commit(), {"roughness": 0.8, "specular": 0.1}))
	_add_label(holder, shop_id, Vector3(0.0, 0.0, 0.035), 0.0032)


## A chalkboard on a post, its words on the side facing yaw.
static func _post_sign(root: Node3D, shop_id: String, at: Vector3, yaw: float) -> void:
	var holder := Node3D.new()
	holder.position = at
	holder.rotation.y = yaw
	root.add_child(holder)
	var kit := _MeshKit.new()
	kit.tube(PackedVector3Array([Vector3(0.0, 0.0, -0.04), Vector3(0.0, 1.9, -0.04)]), PackedFloat32Array([0.04, 0.035]), FRAME.darkened(0.2), 6, {"jitter": 0.0, "cap_start": true})
	kit.rbox(Vector3(0.0, 1.45, 0.0), Vector3(0.55, 0.32, 0.025), BOARD, 6.0, {"detail": 1})
	kit.rbox(Vector3(0.0, 1.45, -0.006), Vector3(0.6, 0.37, 0.02), FRAME, 6.0, {"detail": 1})
	holder.add_child(_Stylized.instance(kit.commit(), {"roughness": 0.85, "specular": 0.1}))
	_add_label(holder, shop_id, Vector3(0.0, 1.45, 0.035), 0.0026)
	_solid(holder, Vector3(0.0, 0.95, -0.04), Vector3(0.12, 1.9, 0.12))


static func _add_label(holder: Node3D, shop_id: String, at: Vector3, pixel: float) -> void:
	var label := HoursSign.new()
	label.name = "HoursSign"
	label.shop_id = shop_id
	label.position = at
	label.pixel_size = pixel
	holder.add_child(label)


## Rusty's stopgap counter: a long plank across two oil drums, solid.
static func _drum_counter(root: Node3D, at: Vector3) -> void:
	var kit := _MeshKit.new()
	for z: float in [-0.65, 0.65]:
		kit.tube(PackedVector3Array([at + Vector3(0.0, 0.0, z), at + Vector3(0.0, 0.92, z)]), PackedFloat32Array([0.3, 0.3]), DRUM, 12, {"jitter": 0.0, "cap_start": true})
		for y: float in [0.3, 0.62]:
			kit.tube(PackedVector3Array([at + Vector3(0.0, y - 0.02, z), at + Vector3(0.0, y + 0.02, z)]), PackedFloat32Array([0.31, 0.31]), DRUM.darkened(0.25), 12, {"jitter": 0.0, "cap": false})
		kit.blob(at + Vector3(0.31, 0.5, z), Vector3(0.012, 0.12, 0.14), RUST, {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0})
	kit.rbox(at + Vector3(0.0, 0.97, 0.0), Vector3(0.32, 0.04, 1.15), PLANK, 3.0, {"detail": 1})
	root.add_child(_Stylized.instance(kit.commit(), {"roughness": 0.85, "specular": 0.15}))
	_solid(root, at + Vector3(0.0, 0.5, 0.0), Vector3(0.66, 1.0, 2.3))


## Dot's stopgap: a white folding table with a striped cloth, solid.
static func _folding_table(root: Node3D, at: Vector3) -> void:
	var kit := _MeshKit.new()
	kit.rbox(at + Vector3(0.0, 0.76, 0.0), Vector3(0.32, 0.025, 0.75), TABLE, 3.0, {"detail": 1})
	for stripe: int in 5:
		kit.rbox(at + Vector3(-0.33, 0.66, -0.6 + float(stripe) * 0.3), Vector3(0.006, 0.1, 0.075), ORANGE if stripe % 2 == 0 else Color(0.98, 0.85, 0.3), 2.0, {"detail": 1})
	for x: float in [-0.26, 0.26]:
		for z: float in [-0.65, 0.65]:
			kit.tube(PackedVector3Array([at + Vector3(x, 0.0, z), at + Vector3(x * 0.8, 0.74, z)]), PackedFloat32Array([0.018, 0.018]), CAGE, 5, {"jitter": 0.0})
	root.add_child(_Stylized.instance(kit.commit(), {"roughness": 0.7, "specular": 0.2}))
	_solid(root, at + Vector3(0.0, 0.4, 0.0), Vector3(0.66, 0.8, 1.5))


## The back room's delivery spot: a pallet in a wire cage against the store's
## side wall, and the stenciled sign over it. Low enough to step around, so
## only the cage's posts are solid.
static func _pallet_base(root: Node3D, at: Vector3) -> void:
	var pallet := _ShopModels.node("pallet")
	pallet.position = at
	root.add_child(pallet)
	var kit := _MeshKit.new()
	var corners: Array[Vector3] = [Vector3(-0.8, 0.0, -0.75), Vector3(0.8, 0.0, -0.75), Vector3(0.8, 0.0, 0.75), Vector3(-0.8, 0.0, 0.75)]
	for corner: Vector3 in corners:
		kit.tube(PackedVector3Array([at + corner, at + corner + Vector3(0.0, 1.6, 0.0)]), PackedFloat32Array([0.025, 0.025]), CAGE, 5, {"jitter": 0.0, "cap_start": true})
	# Top rails all round, and one along the back and sides at knee height (the front is open).
	for index: int in corners.size():
		var a := corners[index]
		var b := corners[(index + 1) % corners.size()]
		kit.tube(PackedVector3Array([at + a + Vector3(0.0, 1.6, 0.0), at + b + Vector3(0.0, 1.6, 0.0)]), PackedFloat32Array([0.015, 0.015]), CAGE, 4, {"jitter": 0.0})
		if index != 1:
			kit.tube(PackedVector3Array([at + a + Vector3(0.0, 0.5, 0.0), at + b + Vector3(0.0, 0.5, 0.0)]), PackedFloat32Array([0.012, 0.012]), CAGE, 4, {"jitter": 0.0})
	root.add_child(_Stylized.instance(kit.commit(), {"roughness": 0.6, "specular": 0.35}))
	for corner: Vector3 in corners:
		_solid(root, at + corner + Vector3(0.0, 0.8, 0.0), Vector3(0.08, 1.6, 0.08))
	var words := _LowPoly.text_sign(root, str(_Strings.SHOP_UI["back_room_sign"]), at + Vector3(-1.38, 2.1, 0.0), 64, Color(0.95, 0.94, 0.9), PI * 0.5)
	words.outline_size = 10


## An invisible box collider (the meshes above are kit meshes with none).
static func _solid(parent: Node3D, center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = center
	parent.add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)


## An hours sign's words: a Label3D that rewrites itself once a second from the
## clock and the crew's rank (sign_text).
class HoursSign extends Label3D:
	const REFRESH_SECONDS: float = 1.0
	var shop_id: String = ""
	var _wait: float = 0.0

	func _ready() -> void:
		font_size = 64
		outline_size = 10
		modulate = Color(0.97, 0.96, 0.9)
		outline_modulate = Color(0.08, 0.08, 0.09)
		horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		double_sided = false
		_refresh()

	func _process(delta: float) -> void:
		_wait += delta
		if _wait >= REFRESH_SECONDS:
			_wait = 0.0
			_refresh()

	func _refresh() -> void:
		var tree := get_tree()
		text = text_for(shop_id, tree.get_first_node_in_group("shops"), tree.get_first_node_in_group("day_clock"))

	static func text_for(shop: String, shops: Node, clock: Node) -> String:
		var strings := preload("res://ui/strings.gd")
		var title := str(strings.SHOP_UI.get("shop_title_" + shop, shop)).to_upper()
		var hours: Vector2 = Constants.SHOP_HOURS.get(shop, Vector2.ZERO)
		if shops != null and not bool(shops.call("is_unlocked", shop)):
			var ranks := preload("res://core/ranks.gd")
			return str(strings.SHOP_UI["shop_sign_locked"]) % [title, ranks.title(ranks.tier_of(Catalog.shop_gate(shop)))]
		if hours.y - hours.x >= 24.0:
			return str(strings.SHOP_UI["shop_sign_always"]) % title
		var shops_script := preload("res://net/shops/shops.gd")
		var day := int(clock.get("day")) if clock != null else 1
		var hour := float(clock.call("hour")) if clock != null else hours.x
		if shops_script.open_at(shop, hour, day):
			return str(strings.SHOP_UI["shop_sign_open"]) % [title, shops_script.hour_text(hours.x), shops_script.hour_text(hours.y)]
		if shops_script._fishing(shop, day):
			return str(strings.SHOP_UI["gone_fishin"])
		return str(strings.SHOP_UI["shop_sign_closed"]) % [title, shops_script.opens_text_at(shop, hour, day)]
