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
## Rusty's Salvage & Pawn (shops chunk 5) is a fenced gravel yard: his shack,
## a plank counter on two oil drums, the chalkboard with his mood today, the dial
## scale you heave junk onto (its needle swings to the weight, and Rusty has a
## word for whatever lands on it), the pallets his used tools sit on, tire
## stacks, and a double gate that swings shut when he's closed. Until their own
## chunk builds them, Dot works from a folding table in her parking stall (the
## Lunch Money truck is shops chunk 6). The Snak-o-Matic's machine is chunk 6 too.

const _LowPoly = preload("res://props/low_poly.gd")
const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const _ShopModels = preload("res://props/shop_models.gd")
const _Keeper = preload("res://npcs/store_clerk.gd")
const _Strings = preload("res://ui/strings.gd")
const _YardExtras = preload("res://props/yard_extras.gd")
const _ShelfStock = preload("res://props/shelf_stock.gd")
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
			build_site(zone, shop_id, site)


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
			_rustys_yard(root, site)
			_drum_counter(root, counter)
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


# ---------------------------------------------------------------- Rusty's yard

## Rusty's yard, in its zone's space (site is SHOP_SITES.rustys): area is the
## fenced gravel, scale and rack where the scale and the used-tool pallets stand.
## The gate is the west side's middle (RUSTYS_GATE_HALF either side of the
## area's middle), facing the store.
const RUSTYS_GATE_HALF: float = 2.5
const FENCE_HEIGHT: float = 1.8
const GRAVEL := Color(0.58, 0.55, 0.5)
const SHACK := Color(0.62, 0.6, 0.55)
const SHACK_ROOF := Color(0.5, 0.33, 0.24)
const CINDER := Color(0.6, 0.6, 0.58)


static func _rustys_yard(root: Node3D, site: Dictionary) -> void:
	var area: Rect2 = site["area"]
	var middle := area.get_center()
	var gravel := _LowPoly.box(root, Vector3(area.size.x, 0.025, area.size.y), Vector3(middle.x, 0.0125, middle.y), GRAVEL)
	_LowPoly.paint(gravel, "gravel")
	_rustys_fence(root, area)
	var gate := RustysGate.new()
	gate.name = "RustysGate"
	gate.yard = area
	gate.position = Vector3(area.position.x, 0.0, middle.y)
	root.add_child(gate)
	_rustys_shack(root, area)
	_mood_board(root, (site["counter"] as Vector3) + Vector3(-0.7, 0.0, -1.9))
	var dial := ScaleDial.new()
	dial.name = "ScaleDial"
	dial.position = site["scale"]
	# The dial faces the gate (west); the post stands on the keeper's side.
	dial.rotation.y = PI * 0.5
	root.add_child(dial)
	_used_rack(root, site["rack"] as Vector3)
	for at: Vector3 in [Vector3(area.position.x + 0.8, 0.0, area.end.y - 0.7), Vector3(area.end.x - 0.7, 0.0, area.end.y - 0.7), Vector3(area.position.x + 0.8, 0.0, area.position.y + 0.8)]:
		var stack := _ShopModels.node("tire_stack")
		stack.position = at
		stack.rotation.y = at.x
		root.add_child(stack)
		_solid(root, at + Vector3(0.0, 0.45, 0.0), Vector3(0.8, 0.9, 0.8))
	# His sign, on the fence, for the parking lot and for the store's side.
	var words := str(_Strings.SHOP_UI["rustys_yard_sign"])
	_sign_board(root, words, Vector3(middle.x + 1.2, 1.25, area.end.y + 0.06), 0.0)
	_sign_board(root, words, Vector3(area.position.x - 0.06, 1.25, area.position.y + 1.8), -PI * 0.5)
	_post_sign(root, "rustys", Vector3(area.position.x - 0.5, 0.0, middle.y + RUSTYS_GATE_HALF + 0.45), -PI * 0.5)


## Chain-link all round (props/yard_extras.gd's run), with the gate's gap in
## the west side, and colliders along every run.
static func _rustys_fence(root: Node3D, area: Rect2) -> void:
	var middle := area.get_center()
	var runs: Array = [
		[Vector2(area.position.x, area.position.y), Vector2(area.end.x, area.position.y)],
		[Vector2(area.end.x, area.position.y), Vector2(area.end.x, area.end.y)],
		[Vector2(area.end.x, area.end.y), Vector2(area.position.x, area.end.y)],
		[Vector2(area.position.x, area.end.y), Vector2(area.position.x, middle.y + RUSTYS_GATE_HALF)],
		[Vector2(area.position.x, middle.y - RUSTYS_GATE_HALF), Vector2(area.position.x, area.position.y)],
	]
	for run: Array in runs:
		var a: Vector2 = run[0]
		var b: Vector2 = run[1]
		var length := a.distance_to(b)
		var kit := _MeshKit.new()
		_YardExtras.build("chainlink_run", kit, Color.WHITE, Vector3(length, FENCE_HEIGHT, 0.0))
		var view := _Stylized.instance(kit.commit(), {"roughness": 0.5, "specular": 0.4})
		var mid := (a + b) * 0.5
		view.position = Vector3(mid.x, 0.0, mid.y)
		view.rotation.y = -atan2(b.y - a.y, b.x - a.x)
		root.add_child(view)
		var along := b - a
		var size := Vector3(absf(along.x) + 0.1, FENCE_HEIGHT, absf(along.y) + 0.1)
		_solid(root, Vector3(mid.x, FENCE_HEIGHT * 0.5, mid.y), size)


## Rusty's corrugated shack behind his counter: a lean-to roof, a door, a
## window with a hand-lettered card, solid.
static func _rustys_shack(root: Node3D, area: Rect2) -> void:
	var from := Vector2(16.9, area.position.y + 0.35)
	var to := Vector2(area.end.x - 0.25, -2.6)
	var size := Vector3(to.x - from.x, 2.4, to.y - from.y)
	var middle := Vector3((from.x + to.x) * 0.5, 0.0, (from.y + to.y) * 0.5)
	var walls := _LowPoly.box(root, size, middle + Vector3(0.0, size.y * 0.5, 0.0), SHACK)
	_LowPoly.paint(walls, "corrugated", Vector4.ZERO, Color(0, 0, 0, 0), 0.0)
	# The lean-to roof, high at the front (west), overhanging.
	var roof := _LowPoly.box(root, Vector3(size.x + 0.5, 0.08, size.z + 0.4), middle + Vector3(-0.1, size.y + 0.18, 0.0), SHACK_ROOF)
	roof.rotation.z = -0.12
	_LowPoly.paint(roof, "corrugated")
	var front := middle.x - size.x * 0.5
	var door := _LowPoly.box(root, Vector3(0.06, 1.95, 0.9), Vector3(front - 0.03, 0.98, middle.z + size.z * 0.28), Color(0.36, 0.3, 0.26))
	_LowPoly.paint(door, "planks")
	_LowPoly.window(root, 0.9, 0.6, Vector3(front - 0.01, 1.55, middle.z - size.z * 0.22), Color(0.45, 0.38, 0.3), -PI * 0.5)
	_solid(root, middle + Vector3(0.0, size.y * 0.5, 0.0), size)


## The chalkboard on an A-frame by the counter: today's mood (MoodBoard).
static func _mood_board(root: Node3D, at: Vector3) -> void:
	var holder := Node3D.new()
	holder.position = at
	# Turned to the customers coming in through the gate.
	holder.rotation.y = -0.9
	root.add_child(holder)
	var kit := _MeshKit.new()
	for lean: float in [-1.0, 1.0]:
		kit.rbox(Vector3(0.0, 0.55, lean * 0.13), Vector3(0.38, 0.5, 0.02), FRAME, 6.0, {"detail": 1, "basis": Basis(Vector3.RIGHT, lean * 0.24)})
		kit.rbox(Vector3(0.0, 0.58, lean * 0.135 + lean * 0.012), Vector3(0.33, 0.42, 0.012), BOARD, 6.0, {"detail": 1, "basis": Basis(Vector3.RIGHT, lean * 0.24)})
	holder.add_child(_Stylized.instance(kit.commit(), {"roughness": 0.85, "specular": 0.1}))
	var board := MoodBoard.new()
	board.name = "MoodBoard"
	board.position = Vector3(0.0, 0.62, 0.17)
	board.rotation.x = -0.24
	board.pixel_size = 0.0024
	holder.add_child(board)


## Two pallets on cinder blocks where today's used tools sit with their tags
## (props/shelf_stock.gd for Rusty's Used tab; one slot per tool on his rack).
static func _used_rack(root: Node3D, at: Vector3) -> void:
	var slots: Array[Dictionary] = []
	for index: int in Constants.USED_TOOLS_PER_DAY.y:
		var z := at.z + (float(index) - float(Constants.USED_TOOLS_PER_DAY.y - 1) * 0.5) * 2.2
		var slot_at := Vector3(at.x, 0.42, z)
		for block: float in [-0.75, 0.0, 0.75]:
			for side: float in [-0.4, 0.4]:
				var cinder := _LowPoly.box(root, Vector3(0.38, 0.28, 0.18), Vector3(at.x + side, 0.14, z + block), CINDER)
				_LowPoly.paint(cinder, "cinderblock")
		for half: float in [-0.52, 0.52]:
			var pallet := _ShopModels.node("pallet")
			pallet.position = Vector3(at.x, 0.28, z + half)
			pallet.rotation.y = PI * 0.5
			pallet.scale = Vector3(0.84, 1.0, 0.84)
			root.add_child(pallet)
		_solid(root, Vector3(at.x, 0.21, z), Vector3(1.0, 0.42, 2.1))
		slots.append({"at": slot_at, "size": Vector3(1.0, 1.2, 2.0), "face": PI * 0.5})
	var stock := _ShelfStock.new()
	stock.name = "RustysRack"
	stock.set("shop_id", "rustys")
	var tabs: Array[String] = ["used"]
	stock.set("tabs", tabs)
	stock.set("slots", slots)
	stock.set("used_rack", true)
	root.add_child(stock)


## A painted plank sign with words on it, facing yaw (+Z at 0).
static func _sign_board(root: Node3D, words: String, at: Vector3, yaw: float) -> void:
	var holder := Node3D.new()
	holder.position = at
	holder.rotation.y = yaw
	root.add_child(holder)
	var plank := _LowPoly.box(holder, Vector3(2.6, 0.8, 0.04), Vector3.ZERO, Color(0.86, 0.82, 0.7))
	_LowPoly.paint(plank, "planks")
	var label := _LowPoly.text_sign(holder, words, Vector3(0.0, 0.0, 0.03), 72, Color(0.62, 0.18, 0.12))
	label.pixel_size = 0.0042
	label.outline_size = 0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## Rusty's counter: a long plank across two oil drums, solid.
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


## Rusty's chalkboard: his mood today in chalk (Shops.rusty_mood against
## Constants.RUSTY_MOOD_BANDS), rewritten when it changes. Local, from replicated state.
class MoodBoard extends Label3D:
	const REFRESH_SECONDS: float = 1.0
	var _wait: float = REFRESH_SECONDS

	func _ready() -> void:
		font_size = 64
		outline_size = 0
		modulate = Color(0.95, 0.95, 0.9)
		horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		width = 260.0
		autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		double_sided = false

	func _process(delta: float) -> void:
		_wait += delta
		if _wait < REFRESH_SECONDS:
			return
		_wait = 0.0
		var shops := get_tree().get_first_node_in_group("shops")
		var mood := float(shops.get("rusty_mood")) if shops != null else 1.0
		text = str(preload("res://ui/strings.gd").SHOP_UI["rusty_mood_%d" % band(mood)])

	## 0 grumpy, 1 so-so, 2 paying good.
	static func band(mood: float) -> int:
		var bands: Array[float] = Constants.RUSTY_MOOD_BANDS
		if mood < bands[0]:
			return 0
		return 1 if mood < bands[1] else 2


## Rusty's dial scale (props/shop_models.gd dial_scale): the needle swings to the
## weight of the junk lying on the platform (Shops.on_scale, every peer from the
## replicated props), springy, overshooting and settling, and when a new piece
## lands Rusty has a word for it (Strings.JUNK_LINES), if he's there.
class ScaleDial extends Node3D:
	const _Models = preload("res://props/shop_models.gd")
	var _needle: Node3D
	var _angle: float = 0.0
	var _speed: float = 0.0
	## The pieces on the scale last frame, by name, so a new one gets a word.
	var _seen: Dictionary = {}
	## Total weight on it now (kg), for tests and the probe.
	var kg: float = 0.0

	func _ready() -> void:
		add_child(_Models.node("dial_scale"))
		var pivot := Node3D.new()
		pivot.name = "Needle"
		pivot.position = _Models.DIAL_AT + Vector3(0.0, 0.0, -0.042)
		add_child(pivot)
		pivot.add_child(_Models.node("dial_needle"))
		_needle = pivot
		_angle = -_Models.DIAL_SWEEP
		_needle.rotation.z = _angle
		var brand := Label3D.new()
		brand.text = str(preload("res://ui/strings.gd").SHOP_UI["rustys_scale_brand"])
		brand.font_size = 28
		brand.pixel_size = 0.002
		brand.outline_size = 0
		brand.modulate = Color(0.2, 0.18, 0.16)
		brand.double_sided = false
		brand.rotation.y = PI
		brand.position = _Models.DIAL_AT + Vector3(0.0, -0.1, -0.04)
		add_child(brand)
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.24, 0.12, 1.24)
		shape.shape = box
		shape.position = Vector3(0.0, 0.06, -0.02)
		body.add_child(shape)
		var post := CollisionShape3D.new()
		var post_box := BoxShape3D.new()
		post_box.size = Vector3(0.7, 1.7, 0.2)
		post.shape = post_box
		post.position = Vector3(0.0, 0.85, _Models.DIAL_AT.z + 0.02)
		body.add_child(post)
		add_child(body)

	func _physics_process(delta: float) -> void:
		var shops := get_tree().get_first_node_in_group("shops")
		var total := 0.0
		var now: Dictionary = {}
		if shops != null:
			for prop: Node3D in shops.call("junk_on_scale"):
				total += float(prop.call("weight_kg")) if prop.has_method("weight_kg") else 0.0
				now[str(prop.name)] = prop
		kg = total
		for key: Variant in now:
			if not _seen.has(key):
				_remark(now[key] as Node3D, shops)
		_seen = now
		# A spring toward the reading: it overshoots and wobbles in, like a real dial.
		var target := lerpf(-_Models.DIAL_SWEEP, _Models.DIAL_SWEEP, clampf(total / Constants.RUSTY_SCALE_FULL_KG, 0.0, 1.0))
		_speed += ((target - _angle) * Constants.RUSTY_SCALE_STIFFNESS - _speed * Constants.RUSTY_SCALE_DAMPING) * delta
		_angle += _speed * delta
		_needle.rotation.z = _angle

	## The needle's angle now (radians from straight up), for tests.
	func needle_angle() -> float:
		return _angle

	func _remark(prop: Node3D, shops: Node) -> void:
		var item := str(shops.call("junk_item", prop)) if shops != null else "junk_" + str(prop.get("label"))
		var pool: Array = preload("res://ui/strings.gd").JUNK_LINES.get(item.trim_prefix("junk_"), [])
		if pool.is_empty():
			return
		for keeper: Node in get_tree().get_nodes_in_group("shopkeepers"):
			if str(keeper.get("shop_id")) == "rustys" and bool(keeper.call("is_present")) and not bool(keeper.call("is_thinking")):
				# The same line on every peer for the same piece.
				keeper.call("say", str(pool[absi(hash(str(prop.name))) % pool.size()]))


## Rusty's double gate: two chain-link leaves that stand open (swung out to the
## lot) while he's open and swing shut when he closes, solid only shut. On his
## day off the GONE FISHIN' board hangs on them. Local, from the clock and the
## replicated players: while anyone is still in the yard (or in the gateway) he
## holds it open, so nobody is fenced in overnight, and a shut gate swings open
## for someone who turns up inside.
class RustysGate extends Node3D:
	const _Kit = preload("res://props/mesh_kit.gd")
	const _Look = preload("res://props/stylized.gd")
	const _Extras = preload("res://props/yard_extras.gd")
	const _Shops = preload("res://net/shops/shops.gd")
	const HALF: float = 2.5
	const CHECK_SECONDS: float = 0.5
	var _leaves: Array[Node3D] = []
	var _shut: float = 0.0
	var _want_shut: float = 0.0
	var _wait: float = CHECK_SECONDS
	var _board: Node3D
	var _solid: CollisionShape3D
	## The fenced yard, in the parent's (the site's) space.
	var yard: Rect2 = Rect2()

	func _ready() -> void:
		for side: float in [-1.0, 1.0]:
			# Hinged at the gap's ends; a leaf runs from its hinge toward the middle.
			var hinge := Node3D.new()
			hinge.position = Vector3(0.0, 0.0, side * HALF)
			add_child(hinge)
			var kit := _Kit.new()
			_Extras.build("chainlink_run", kit, Color.WHITE, Vector3(HALF - 0.05, 1.7, 0.0))
			var leaf := _Look.instance(kit.commit(), {"roughness": 0.5, "specular": 0.4})
			# The run lies along x; turned to run along -side z from the hinge.
			leaf.rotation.y = side * PI * 0.5
			leaf.position = Vector3(0.0, 0.0, -side * (HALF - 0.05) * 0.5)
			hinge.add_child(leaf)
			_leaves.append(hinge)
		var body := StaticBody3D.new()
		_solid = CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.12, 1.7, HALF * 2.0)
		_solid.shape = box
		_solid.position = Vector3(0.0, 0.85, 0.0)
		body.add_child(_solid)
		add_child(body)
		_board = Node3D.new()
		_board.position = Vector3(-0.08, 1.15, 0.0)
		add_child(_board)
		var plank := preload("res://props/low_poly.gd").box(_board, Vector3(0.04, 0.62, 1.5), Vector3.ZERO, Color(0.9, 0.88, 0.8))
		preload("res://props/low_poly.gd").paint(plank, "planks")
		var words := preload("res://props/low_poly.gd").text_sign(_board, str(preload("res://ui/strings.gd").SHOP_UI["gone_fishin"]), Vector3(-0.03, 0.0, 0.0), 64, Color(0.15, 0.3, 0.6), -PI * 0.5)
		words.pixel_size = 0.0036
		words.outline_size = 0
		words.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_check()
		_shut = _want_shut
		_pose()

	func _process(delta: float) -> void:
		_wait += delta
		if _wait >= CHECK_SECONDS:
			_wait = 0.0
			_check()
		if not is_equal_approx(_shut, _want_shut):
			_shut = move_toward(_shut, _want_shut, delta / Constants.RUSTY_GATE_SWING_SECONDS)
			_pose()

	## Whether the gate is shut now (0 open .. 1 shut), for tests.
	func shut_amount() -> float:
		return _shut

	func _check() -> void:
		var tree := get_tree()
		var shops := tree.get_first_node_in_group("shops")
		var clock := tree.get_first_node_in_group("day_clock")
		var open := shops == null or (bool(shops.call("is_unlocked", "rustys")) and bool(shops.call("is_open", "rustys")))
		_want_shut = 0.0 if open or someone_inside() else 1.0
		var day := int(clock.get("day")) if clock != null else 1
		_board.visible = shops != null and bool(shops.call("is_unlocked", "rustys")) and _Shops._fishing("rustys", day)

	## Whether a player stands in the yard, or within RUSTY_GATE_HOLD_MARGIN of
	## it (the gateway, where the leaves swing).
	func someone_inside() -> bool:
		var site := get_parent() as Node3D
		if site == null or yard.size == Vector2.ZERO:
			return false
		var around := yard.grow(Constants.RUSTY_GATE_HOLD_MARGIN)
		for node: Node in get_tree().get_nodes_in_group("players"):
			var body := node as Node3D
			if body == null or not body.is_visible_in_tree():
				continue
			var local := site.to_local(body.global_position)
			if around.has_point(Vector2(local.x, local.z)):
				return true
		return false

	func _pose() -> void:
		# Eased: the leaves slow into the latch and the stop.
		var eased := smoothstep(0.0, 1.0, _shut)
		for index: int in _leaves.size():
			var side := -1.0 if index == 0 else 1.0
			# Open is swung out to the lot (-x), a quarter turn; shut is across the gap.
			_leaves[index].rotation.y = side * (1.0 - eased) * PI * 0.5
		_solid.disabled = _shut < 0.95
		_board.visible = _board.visible and _shut > 0.95