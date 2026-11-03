extends Node3D

## Authority: local, cosmetic. The leaf bags riding in Chefty's bed, drawn from
## the bag count every peer already gets (ride.gd and chefty_drive.gd _rpc_bags),
## so a load you can see grows as the crew loads it (docs/GAME.md "Tossing bags
## into Chefty"). A child of the truck's Body, so it rides along.
##
## Bags fill fixed spots (slot()), from the cab back, in a heap that narrows as
## it rises. A tossed bag the bed caught holds its spot (hold_slot) while the bag
## itself glides into it and sits; the spot shows the moment that bag is gone,
## so the swap can't be seen. Bags that arrive any other way (a wheelbarrow
## dumped, a hired hand's) drop in from above, one after another. The bed's
## effects live here too: the thump, leaf puff and "+$" where a bag lands, and
## the pile giving and springing back when a full bed bats a bag out. No words:
## a full Chefty looks full.

const _YardModels = preload("res://props/yard_models.gd")
const _MoneyPopup = preload("res://ui/money_popup.gd")
const _BedToss = preload("res://net/components/bed_toss.gd")

## The heap's layers, bottom up (presentation): [columns' x, rows' z, height of
## the bags' bottoms]. The floor's top is at y 1.05. The first layer skips the
## two spots where the water tank stands (x < -0.2, z < -0.2).
const LAYERS: Array = [
	[[0.0, 0.62, -0.62], [-0.9, -0.28, 0.34, 0.96, 1.58, 2.2], 1.05],
	[[0.0, 0.62, -0.62], [-0.59, 0.03, 0.65, 1.27, 1.89], 1.68],
	[[0.31, -0.31], [-0.6, 0.0, 0.6, 1.2, 1.8], 2.3],
	[[0.31, -0.31], [-0.3, 0.3, 0.9, 1.5], 2.9],
]
## Past the last layer the heap keeps going two at a time, this much higher each.
const TOP_ROW: Array = [[0.0], [0.3, 1.2]]
## The middle of the bed along its length (z): the first spots fill out from here.
const MIDDLE_Z: float = 0.72
## A drawn leaf bag's height (props/yard_models.gd), and how far a bag sinks
## into the heap's edge before it bounces off (m).
const BAG_HEIGHT: float = 0.62
const PILE_GIVE: float = 0.3
const PILE_SIDE_REACH: float = 0.55
const LAYER_RISE: float = 0.6
## Above the tank a bag sits on its lid (the tank is 0.75 m tall).
const TANK_TOP: float = 1.8
const TANK_X: float = -0.2
const TANK_Z: float = -0.2
## How a dropped-in bag falls (s, m) and how long after the one before.
const DROP_SECONDS: float = 0.3
const DROP_HEIGHT: float = 1.4
const DROP_STAGGER: float = 0.08
const CLEAR_SECONDS: float = 0.22
## A held spot shows anyway after this long, if its bag never goes (s).
const HOLD_GIVE_UP_SECONDS: float = 3.0
## A full pile batting a bag out: how many of the top bags give, and how much.
const SPRING_BAGS: int = 5
const SPRING_SQUASH := Vector3(1.12, 0.78, 1.12)
const PUFF_COLORS: Array[Color] = [Color(0.9, 0.48, 0.15), Color(0.93, 0.72, 0.22), Color(0.75, 0.25, 0.14), Color(0.62, 0.4, 0.2)]

static var _slots: Array[Transform3D] = []

var _bags: Array[Node3D] = []
var _count: int = 0
var _synced: bool = false
## slot -> the time it was held, while its tossed bag is still on its way.
var _held: Dictionary = {}
## Dollars the next count changes bring that a tossed bag will pop itself when
## it lands (hold_slot); the rest pop here.
var _expected_value: int = 0


func _ready() -> void:
	name = "BedLoad"


## The bed-space transform of stack spot index: where a bag's bottom sits and
## how it leans. The same on every peer (a fixed layout and a fixed jitter).
static func slot(index: int) -> Transform3D:
	if _slots.is_empty():
		_build_slots()
	if index < _slots.size():
		return _slots[index]
	# Past the planned heap: keep piling two at a time.
	var extra := index - _slots.size()
	var layer := LAYERS.size() + extra / 2
	var y: float = float(LAYERS[LAYERS.size() - 1][2]) + LAYER_RISE * float(layer - LAYERS.size() + 1)
	var z: float = float((TOP_ROW[1] as Array)[extra % 2])
	return _jittered(Vector3(0.0, y, z), index)


static func _build_slots() -> void:
	for layer: Array in LAYERS:
		# From the middle of the bed out, where tosses come down (the aim help aims
		# there), so a caught bag drops nearly straight into its spot.
		var rows: Array = (layer[1] as Array).duplicate()
		rows.sort_custom(func(a: float, b: float) -> bool: return absf(a - MIDDLE_Z) < absf(b - MIDDLE_Z))
		var columns: Array = (layer[0] as Array).duplicate()
		columns.sort_custom(func(a: float, b: float) -> bool: return absf(a) < absf(b))
		for z: float in rows:
			for x: float in columns:
				var y: float = layer[2]
				if x < TANK_X and z < TANK_Z:
					if is_equal_approx(y, float(LAYERS[0][2])):
						continue
					y = maxf(y, TANK_TOP)
				_slots.append(_jittered(Vector3(x, y, z), _slots.size()))


## A spot turned and tipped a little, the same for the same spot everywhere, so
## the heap looks tossed in, not stacked by a machine.
static func _jittered(at: Vector3, index: int) -> Transform3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 + index * 104729
	var basis := Basis(Vector3.UP, rng.randf_range(-0.6, 0.6))
	basis = basis * Basis(Vector3.RIGHT, rng.randf_range(-0.12, 0.12)) * Basis(Vector3.BACK, rng.randf_range(-0.12, 0.12))
	return Transform3D(basis.orthonormalized(), at + Vector3(rng.randf_range(-0.05, 0.05), 0.0, rng.randf_range(-0.05, 0.05)))


## How high the heap of count bags reaches, in the bed's space (the top of its
## highest bag), or the floor with none.
static func pile_top(count: int) -> float:
	var top := float(LAYERS[0][2])
	for index: int in mini(count, 200):
		top = maxf(top, slot(index).origin.y + BAG_HEIGHT)
	return top


## True when a bag whose bottom is here (bed space) is in the heap of count bags:
## over the bed, below its top, with half a bag's give at the sides.
static func in_pile(local: Vector3, count: int) -> bool:
	if count <= 0:
		return false
	# A bag's middle this far past the bed's walls already has its side on the heap.
	var reach := PILE_SIDE_REACH
	return absf(local.x) <= 1.05 + reach and local.z >= -1.2 - reach and local.z <= 2.65 + reach and local.y <= pile_top(count) - PILE_GIVE and local.y >= 1.0


## How many bags are drawn (the replicated count).
func shown_count() -> int:
	return _count


## The bed's count changed (every peer). New bags drop in, unless a tossed bag
## holds the spot; bags paid for go away. The first count (joining, a fresh
## truck) just shows.
func set_count(count: int) -> void:
	count = maxi(count, 0)
	while _bags.size() < count:
		var bag := _YardModels.node("leaf_bag") as Node3D
		bag.name = "Bag%d" % _bags.size()
		add_child(bag)
		bag.transform = slot(_bags.size())
		bag.visible = false
		_bags.append(bag)
	var dropped := 0
	for index: int in range(_count, count):
		var bag := _bags[index]
		bag.transform = slot(index)
		bag.scale = Vector3.ONE
		if _held.has(index):
			bag.visible = false
		elif not _synced:
			bag.visible = true
		else:
			_drop_in(bag, index, float(dropped) * DROP_STAGGER)
			dropped += 1
	for index: int in range(count, _count):
		_clear_out(_bags[index], float(index - count) * 0.03)
	_count = count
	_synced = true
	_BedToss.stats["stack"] = count


## A late joiner's snapshot of the load: shown as it is, nothing drops in.
func sync_count(count: int) -> void:
	_synced = false
	set_count(count)


## A tossed bag the bed caught is on its way into spot index: keep the spot
## empty until that bag is gone (its own look sits there meanwhile), and leave
## its dollars for it to pop when it lands.
func hold_slot(index: int, bag: Node, amount: int) -> void:
	_held[index] = Time.get_ticks_msec()
	_expected_value += maxi(amount, 0)
	if index < _bags.size():
		_bags[index].visible = false
	var release := _release_slot.bind(index, bag)
	if bag != null and not bag.tree_exiting.is_connected(release):
		bag.tree_exiting.connect(release, CONNECT_ONE_SHOT)


## A client's guess that its toss went in was wrong (net_prop.gd
## _abort_provisional): the spot shows whatever the count says again.
func unhold_slot(index: int, bag: Node) -> void:
	var release := _release_slot.bind(index, bag)
	if bag != null and bag.tree_exiting.is_connected(release):
		bag.tree_exiting.disconnect(release)
	if bag != null and "value" in bag:
		_expected_value = maxi(_expected_value - int(bag.get("value")), 0)
	_held.erase(index)
	if index < _count and index < _bags.size():
		_bags[index].visible = true


func _release_slot(index: int, bag: Node) -> void:
	if not _held.has(index):
		return
	_held.erase(index)
	# How far from its spot the bag was last drawn (net_prop.gd _step_settle keeps
	# it; it's leaving the tree now, so it can't be asked where it is): a pop if far.
	if is_instance_valid(bag) and "settle_gap_m" in bag:
		var stats: Dictionary = _BedToss.stats
		stats["max_pop_m"] = maxf(float(stats["max_pop_m"]), float(bag.get("settle_gap_m")))
	if index < _count and index < _bags.size():
		_bags[index].transform = slot(index)
		_bags[index].visible = true


## The truck's job value went up by amount (every peer): a "+$" over the bed,
## less what a tossed bag on its way will pop itself.
func on_value_added(amount: int) -> void:
	if amount <= 0:
		return
	var own := mini(amount, _expected_value)
	_expected_value -= own
	if amount - own > 0:
		_MoneyPopup.pop(get_tree(), global_transform * Vector3(0.0, 2.4, 0.7), amount - own)


## A tossed bag just landed in its spot (every peer): a thump, a puff of leaves
## and its dollars, small and quick.
func land_fx(at: Vector3, amount: int) -> void:
	_puff(at + Vector3(0.0, 0.5, 0.0))
	if amount > 0:
		_MoneyPopup.pop(get_tree(), at + Vector3(0.0, 1.1, 0.0), amount)
	_play("bed_thump", at)


## A full bed batted a bag out (every peer): the top of the pile gives under it
## and springs back, with a floomp and a few leaves.
func refuse_fx(at: Vector3) -> void:
	_puff(at)
	_play("bag", at)
	for index: int in range(maxi(_count - SPRING_BAGS, 0), _count):
		if index < _bags.size() and _bags[index].visible:
			_spring(_bags[index], float(_count - 1 - index) * 0.03)


func _play(id: String, at: Vector3) -> void:
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play_at", id, at)


func _process(_delta: float) -> void:
	# A held spot whose bag never went (it was lost on the way): show it anyway.
	if not _held.is_empty():
		var now := Time.get_ticks_msec()
		for index: int in _held.keys():
			if now - int(_held[index]) > int(HOLD_GIVE_UP_SECONDS * 1000.0):
				_held.erase(index)
				if index < _count and index < _bags.size():
					_bags[index].visible = true


func _drop_in(bag: Node3D, index: int, delay: float) -> void:
	var rest := slot(index)
	bag.visible = false
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_callback(func() -> void:
		bag.transform = rest.translated(Vector3(0.0, DROP_HEIGHT, 0.0))
		bag.visible = true)
	tween.tween_property(bag, "position", rest.origin, DROP_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		_puff(global_transform * (rest.origin + Vector3(0.0, 0.5, 0.0)))
		_squash(bag)
		_play("bed_thump", global_transform * rest.origin))


func _clear_out(bag: Node3D, delay: float) -> void:
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_property(bag, "scale", Vector3(0.01, 0.01, 0.01), CLEAR_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		bag.visible = false
		bag.scale = Vector3.ONE)


## Squashes a landed bag flat and lets it spring back (its bottom stays put).
static func _squash(bag: Node3D) -> void:
	var rest := Vector3.ONE
	var tween := bag.create_tween()
	bag.scale = rest * Vector3(1.16, 0.8, 1.16)
	tween.tween_property(bag, "scale", rest, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Squash a tossed bag's own look where it lands (net_prop.gd _land).
static func squash(look: Node3D) -> void:
	if look != null:
		_squash(look)


## A bag in the pile pressed down by one bouncing off it, and springing back
## past where it was before it settles.
static func _spring(bag: Node3D, delay: float) -> void:
	var tween := bag.create_tween()
	tween.tween_interval(delay)
	tween.tween_property(bag, "scale", SPRING_SQUASH, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(bag, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## A little burst of leaves where a bag lands.
func _puff(at: Vector3) -> void:
	var world := get_tree().get_first_node_in_group("world") as Node3D
	if world == null:
		world = get_tree().current_scene as Node3D
	if world == null:
		return
	var particles := CPUParticles3D.new()
	particles.name = "LeafPuff"
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.amount = 16
	particles.lifetime = 0.9
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.09, 0.06)
	particles.mesh = mesh
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particles.material_override = material
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	ramp.colors = PackedColorArray(PUFF_COLORS)
	particles.color_initial_ramp = ramp
	particles.direction = Vector3.UP
	particles.spread = 70.0
	particles.initial_velocity_min = 1.2
	particles.initial_velocity_max = 2.6
	particles.gravity = Vector3(0.0, -3.5, 0.0)
	particles.damping_min = 1.0
	particles.damping_max = 2.0
	particles.angular_velocity_min = -360.0
	particles.angular_velocity_max = 360.0
	particles.particle_flag_rotate_y = true
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.25
	world.add_child(particles)
	particles.global_position = at
	particles.emitting = true
	get_tree().create_timer(1.4).timeout.connect(particles.queue_free)
