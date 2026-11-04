extends Node3D

## Authority: local, cosmetic. The back room's delivery pallet (docs/GAME.md
## "Shops", deliveries; shops chunk 8). Today's delivered supplies stand on it as
## crates (Shops.arrived_today), two a layer, at most
## Constants.DELIVERY_CRATES_MAX; the morning restock clears it.
##
## The cage stands against the lobby's side wall, and in that wall behind it is
## a pass-through hatch with a roll-up shutter (built here). When an order lands
## (Shops.delivered, sent just before the snapshot that carries the crates) the
## delivery van honks from the loading dock behind the wall, the shutter rattles
## up, and someone inside shoves the crates out one by one: each comes out of the
## dark on a short arc, tipping flat as it drops, lands on the pallet with a thud
## and a squash, and springs back square. The tools in the same order come out
## after the crates, lobbed high over the cage onto the ground in front of it as
## real kit props the host throws (net/shops/shops.gd _toss_tool). Then the
## shutter rattles back down. A peer that joins later, or missed the honk, just
## finds the crates stacked. Every peer builds its own from replicated state,
## like the shelves, so it costs no traffic; each landed crate gets a simple box
## collider so nobody walks through the stack.
## Placed by levels/dressing/shop_sites.gd at SHOP_SITES.back_room's counter, in
## StoreZone's axes (the wall is toward -X).

const _ShopModels = preload("res://props/shop_models.gd")
const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
## A crate's box (props/shop_models.gd _crate: 0.6 by 0.5 by 0.6).
const CRATE_SIZE := Vector3(0.6, 0.5, 0.6)
## A tossed crate starts tipped back this much (radians) and comes down flat.
const TOSS_TIP: float = 0.5
## The hatch's colors: its frame and housing, the shutter's slats, the dark inside.
const STEEL := Color(0.32, 0.34, 0.37)
const SHUTTER := Color(0.66, 0.68, 0.7)
const HATCH_DARK := Color(0.05, 0.05, 0.06)
const FLAT := {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0}
## How much of its height the shutter keeps rolled up in the housing.
const SHUTTER_ROLLED: float = 0.06

var _shutter: Node3D
var _shutter_open: bool = false
var _shutter_tween: Tween

## The crates standing on the pallet, bottom layer first.
var _shown: Array[Node3D] = []
## Crates announced by a honk and still on their way (in the air or waiting their turn).
var _incoming: int = 0
var _shops: Node
## Landed crates this peer has drawn since it started (tests: a toss, not a pop).
var tossed: int = 0


func _ready() -> void:
	add_to_group("delivery_pallet")
	_build_hatch()
	_hook.call_deferred()


func _hook() -> void:
	if not is_inside_tree():
		return
	_shops = get_tree().get_first_node_in_group("shops")
	if _shops == null:
		# Shops comes up with the world; this is built a little after it, but in
		# case it isn't there yet, catch it when it is.
		get_tree().node_added.connect(_on_node_added)
		return
	_shops.connect("changed", _sync)
	_shops.connect("delivered", _on_delivered)
	_sync()


func _on_node_added(node: Node) -> void:
	if node.name == "Shops" and _shops == null:
		get_tree().node_added.disconnect(_on_node_added)
		_hook.call_deferred()


## How many crates stand on the pallet now (landed, not in the air).
func crate_count() -> int:
	return _shown.size()


## Where the index-th crate stands, in this node's space: two a layer.
static func crate_spot(index: int) -> Vector3:
	var side := -1.0 if index % 2 == 0 else 1.0
	var layer := index / 2
	return Vector3(side * Constants.DELIVERY_CRATE_SIDE, Constants.DELIVERY_PALLET_TOP + float(layer) * Constants.DELIVERY_CRATE_LAYER, 0.0)


## The crates the pallet should show: today's, up to what fits.
func _wanted() -> int:
	if _shops == null:
		return 0
	return mini((_shops.get("arrived_today") as Array).size(), Constants.DELIVERY_CRATES_MAX)


## Matches the stack to the state: crates nobody announced (a late join, a
## missed honk) are just there; the morning's empty pallet takes them away.
func _sync() -> void:
	var wanted := _wanted()
	while _shown.size() > wanted:
		var crate: Node3D = _shown.pop_back()
		crate.queue_free()
	if wanted == 0:
		_incoming = 0
	while _shown.size() + _incoming < wanted:
		_shown.append(_make_crate(_shown.size()))


## A delivery landed: the honk from the dock, the shutter up, each crate out
## through the hatch, the shutter down once the last thing (a tool, maybe) is out.
func _on_delivered(crates: Array, tools: int) -> void:
	_sfx("delivery_honk", to_global(Constants.DELIVERY_HONK_FROM), Constants.DELIVERY_HONK_DB)
	var tree := get_tree()
	tree.create_timer(Constants.DELIVERY_SHUTTER_DELAY).timeout.connect(_roll_shutter.bind(true))
	var thrown := 0
	for index: int in crates.size():
		var slot := _shown.size() + _incoming
		if slot >= Constants.DELIVERY_CRATES_MAX:
			break
		_incoming += 1
		thrown += 1
		var delay := Constants.DELIVERY_TOSS_DELAY + float(index) * Constants.DELIVERY_TOSS_GAP
		tree.create_timer(delay).timeout.connect(_toss.bind(slot))
	# The host throws the tools right after the crates it sent (all of them,
	# even ones the pallet has no room to show).
	var last := Constants.DELIVERY_TOSS_DELAY + float(maxi(crates.size() + tools - 1, 0)) * Constants.DELIVERY_TOSS_GAP
	var flight := Constants.DELIVERY_TOOL_FLIGHT if tools > 0 else Constants.DELIVERY_TOSS_SECONDS
	if thrown == 0 and tools == 0:
		flight = 0.0
	tree.create_timer(last + flight + Constants.DELIVERY_SHUTTER_HOLD).timeout.connect(_roll_shutter.bind(false))


## One crate out of the hatch onto its spot: it starts back in the dark, comes
## out on a ballistic arc (gravity's), tipping flat as it drops, then lands.
func _toss(slot: int) -> void:
	if not is_inside_tree():
		return
	var land := crate_spot(slot)
	# The crate's base, centered in the hatch (it's 0.5 tall), back inside it.
	var from := Constants.DELIVERY_HATCH + Vector3(-Constants.DELIVERY_CRATE_START_BACK, -CRATE_SIZE.y * 0.5, 0.0)
	var crate := _crate_model(slot)
	crate.position = from
	add_child(crate)
	var seconds := Constants.DELIVERY_TOSS_SECONDS
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var start_velocity := (land - from) / seconds + Vector3.UP * 0.5 * gravity * seconds
	var yaw := crate.rotation.y
	var flight := create_tween()
	flight.tween_method(func(t: float) -> void:
		if not is_instance_valid(crate):
			return
		var time := t * seconds
		crate.position = from + start_velocity * time + Vector3.DOWN * 0.5 * gravity * time * time
		# Leaning back toward the wall as it leaves, flat by the time it lands.
		crate.rotation = Vector3(0.0, yaw, TOSS_TIP * (1.0 - t))
	, 0.0, 1.0, seconds)
	flight.tween_callback(_landed.bind(crate, slot))


## A crate touched down: thud, squash, spring back, and it's part of the stack.
func _landed(crate: Node3D, slot: int) -> void:
	_incoming = maxi(_incoming - 1, 0)
	if not is_instance_valid(crate):
		return
	# The morning (or a reload) cleared the pallet while it flew.
	if slot >= _wanted():
		crate.queue_free()
		return
	crate.position = crate_spot(slot)
	crate.rotation = Vector3(0.0, crate.rotation.y, 0.0)
	_sfx("crate_thud", crate.global_position, Constants.DELIVERY_THUD_DB)
	# The model squashes from its base (its origin), so it stays on what it landed on.
	var look := crate.get_node("Look") as Node3D
	var squash := Constants.DELIVERY_CRATE_SQUASH
	look.scale = Vector3(1.0 + (1.0 - squash) * 0.5, squash, 1.0 + (1.0 - squash) * 0.5)
	var settle := create_tween()
	settle.tween_property(look, "scale", Vector3.ONE, Constants.DELIVERY_CRATE_SETTLE).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_add_solid(crate)
	_shown.append(crate)
	tossed += 1


## The hatch in the wall behind the cage: a steel frame, the dark inside, the
## shutter's housing over it, and the corrugated shutter, hung from its top edge
## so it rolls up into the housing by shrinking toward it.
func _build_hatch() -> void:
	var hatch := Node3D.new()
	hatch.name = "Hatch"
	hatch.position = Constants.DELIVERY_HATCH
	add_child(hatch)
	var width := Constants.DELIVERY_HATCH_SIZE.x
	var height := Constants.DELIVERY_HATCH_SIZE.y
	var kit := _MeshKit.new()
	# The dark inside, just off the wall's face; the frame stands proud of it.
	kit.call("box", Vector3.ZERO, Vector3(0.01, height, width), HATCH_DARK)
	for side: float in [-1.0, 1.0]:
		kit.call("rbox", Vector3(0.02, 0.0, side * (width * 0.5 + 0.03)), Vector3(0.03, height * 0.5 + 0.06, 0.03), STEEL, 8.0, FLAT)
	kit.call("rbox", Vector3(0.02, -height * 0.5 - 0.03, 0.0), Vector3(0.04, 0.03, width * 0.5 + 0.06), STEEL.darkened(0.2), 8.0, FLAT)
	# The housing the shutter rolls up into.
	kit.call("rbox", Vector3(0.05, height * 0.5 + 0.1, 0.0), Vector3(0.07, 0.09, width * 0.5 + 0.08), STEEL, 8.0, FLAT)
	hatch.add_child(_Stylized.instance(kit.commit(), {"roughness": 0.55, "specular": 0.3}))
	_shutter = Node3D.new()
	_shutter.name = "Shutter"
	_shutter.position = Vector3(0.0, height * 0.5, 0.0)
	hatch.add_child(_shutter)
	var slats := _MeshKit.new()
	var count := 8
	for index: int in count:
		var y := -(float(index) + 0.5) * height / float(count)
		slats.call("box", Vector3(0.0, y, 0.0), Vector3(0.024, height / float(count) * 0.92, width), SHUTTER.darkened(float(index % 2) * 0.08))
	slats.call("box", Vector3(0.012, -height + 0.025, 0.0), Vector3(0.032, 0.05, width), STEEL.darkened(0.3))
	_shutter.add_child(_Stylized.instance(slats.commit(), {"roughness": 0.5, "specular": 0.35}))


## The shutter rolls up (open) or back down, with its rattle.
func _roll_shutter(open: bool) -> void:
	if not is_inside_tree() or _shutter == null:
		return
	if open == _shutter_open:
		return
	_shutter_open = open
	_sfx("shutter_roll", global_transform * Constants.DELIVERY_HATCH, 0.0)
	if _shutter_tween != null and _shutter_tween.is_valid():
		_shutter_tween.kill()
	_shutter_tween = create_tween()
	var shut := Vector3.ONE
	var rolled := Vector3(1.0, SHUTTER_ROLLED, 1.0)
	_shutter_tween.tween_property(_shutter, "scale", rolled if open else shut, Constants.DELIVERY_SHUTTER_SECONDS) \
		.set_trans(Tween.TRANS_LINEAR)


## Whether the hatch is open now (tests, the recorder).
func shutter_open() -> bool:
	return _shutter_open


## A crate standing in its spot from the start (no toss).
func _make_crate(slot: int) -> Node3D:
	var crate := _crate_model(slot)
	crate.position = crate_spot(slot)
	add_child(crate)
	_add_solid(crate)
	return crate


## The crate model, turned a little off square (the same turn for a slot on every peer).
func _crate_model(slot: int) -> Node3D:
	var crate := Node3D.new()
	crate.name = "Crate%d" % slot
	var look := _ShopModels.node("crate")
	look.name = "Look"
	crate.add_child(look)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["delivery_crate", slot])
	crate.rotation.y = rng.randf_range(-Constants.DELIVERY_CRATE_YAW, Constants.DELIVERY_CRATE_YAW)
	return crate


## A box collider for a crate in the stack, so nobody walks through it.
func _add_solid(crate: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "Solid"
	body.position = Vector3(0.0, CRATE_SIZE.y * 0.5, 0.0)
	crate.add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = CRATE_SIZE
	shape.shape = box
	body.add_child(shape)


func _sfx(id: String, at: Vector3, db: float) -> void:
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play_at", id, at, db)
