extends RigidBody3D

const _PropLooks = preload("res://props/prop_looks.gd")
const _MoneyPopup = preload("res://ui/money_popup.gd")
const _WaterSources = preload("res://net/work/water_sources.gd")

## Authority: host
## Clients freeze the body and display the replicated transform. The carrier's own client
## draws the visual at the hand until the host releases it.

@export var color: Color = Color(0.55, 0.42, 0.28, 1):
	set(value):
		color = value
		_apply_color()
## Words shown above the box until it has a real model.
@export var label: String = "":
	set(value):
		label = value
		_refresh_label()
## leaf_bag, wheelbarrow, rake, trash, or gnome. Replicated so a thrown bag knows what it hit.
@export var kind: String = "":
	set(value):
		kind = value
		_refresh_label()
## Bags sitting in a wheelbarrow. The bags themselves are freed. Replicated.
@export var stored_bags: int = 0:
	set(value):
		stored_bags = value
		_refresh_label()
## Peer id holding this prop, or 0. Replicated.
@export var held_by: int = 0
## A leaf bag's worth in dollars, set by the host from the leaves that went in. Replicated.
@export var value: int = 0:
	set(new_value):
		value = new_value
		_refresh_label()
## Dollars' worth of the bags sitting in a wheelbarrow. Replicated.
@export var stored_value: int = 0:
	set(new_value):
		stored_value = new_value
		_refresh_label()

## A hose's water: the kind of source it's hooked up to ("chefty", "spigot",
## "hydrant"), or "" when it isn't. Replicated.
@export var hose_source: String = ""
## True while water is coming out of this hose or pressure washer. Replicated.
@export var spraying: bool = false
## A pressure washer's tank, 0 to 100. Replicated.
@export var water: float = 100.0
## A ladder set up against the house: where its top rests (world space), or zero
## when it isn't set up. Its position is its foot. Replicated.
@export var ladder_top := Vector3.ZERO

var _airborne: bool = false
var _spray_left: float = 0.0
## A snapped hose's loose end whipping from where it was hooked up: from, how far along, who it hit.
var _whip_from := Vector3.ZERO
var _whip_t: float = -1.0
var _whipped: Array[Node] = []
## Who threw this, and when, so a throw can't bonk its own thrower right away.
var _thrower: int = 0
var _thrown_at: float = 0.0
## Everyone this throw already hit, so one throw bonks each person once.
var _bonked: Array[Node] = []

const GRAB_REACH: float = 2.4
const PUSH_REACH: float = 1.1


func _enter_tree() -> void:
	add_to_group("props")
	# After players (100): a held tool follows its holder's head on the same tick.
	process_physics_priority = 110


func _ready() -> void:
	_apply_color()
	_refresh_label()
	# A fresh bag pops its worth where it was filled.
	if kind == "leaf_bag" and value > 0:
		_MoneyPopup.pop(get_tree(), global_position + Vector3(0.0, 1.0, 0.0), value)
	if multiplayer.multiplayer_peer != null and not Net.is_host():
		freeze = true


func _physics_process(_delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	# A carried prop must not stay solid. Moving a colliding body into the player launches them.
	_set_solid(held_by == 0)
	if Net.is_host() and ladder_top != Vector3.ZERO:
		freeze = true
	_refresh_label()
	if kind == "rake":
		var holder := _player(held_by) if held_by != 0 else null
		var raking := held_by == Net.local_peer_id() and Input.is_action_pressed("primary")
		_PropLooks.pose_rake(self, holder, raking)
	elif kind == "ladder" and ladder_top != Vector3.ZERO:
		_PropLooks.pose_ladder_up(self, ladder_top)
	elif Constants.TOOL_PRICES.has(kind):
		_PropLooks.pose_tool(self, _player(held_by) if held_by != 0 else null)
	if Net.is_host():
		_host_step()
	elif held_by == Net.local_peer_id():
		var player := _player(held_by)
		if player != null:
			%Visual.global_position = _hold_position(player)


## What this weighs in kg (Constants.ITEM_WEIGHT_KG). A bag gets heavier with
## its leaves and a wheelbarrow with its bags. Every peer can work it out from
## the replicated kind, value, and stored bags, so the holder's slowdown matches.
func weight_kg() -> float:
	var base := float(Constants.ITEM_WEIGHT_KG.get(kind, 6.0))
	if kind == "leaf_bag":
		return minf(base + float(value) * Constants.LEAF_BAG_KG_PER_DOLLAR, Constants.LEAF_BAG_MAX_KG)
	if kind == "wheelbarrow":
		return base + float(stored_bags) * Constants.WHEELBARROW_KG_PER_BAG
	return base


## "light", "medium", or "heavy", by weight (Constants.BONK_TIER_KG).
func weight_tier() -> String:
	var kg := weight_kg()
	if kg <= float(Constants.BONK_TIER_KG["light"]):
		return "light"
	if kg <= float(Constants.BONK_TIER_KG["medium"]):
		return "medium"
	return "heavy"


## The holder sets the ladder up against the nearest gutter, if one is close.
func request_place_ladder() -> void:
	if Net.is_host():
		_place_ladder(Net.local_peer_id())
	else:
		_rpc_request_place_ladder.rpc_id(1)


func is_set_up() -> bool:
	return ladder_top != Vector3.ZERO


func _place_ladder(peer_id: int) -> void:
	if kind != "ladder" or held_by != peer_id:
		return
	var player := _player(peer_id)
	var tasks := get_tree().get_first_node_in_group("job_tasks")
	if player == null or tasks == null:
		return
	# The gutter section closest to where they stand.
	var best := -1
	var best_distance := Constants.LADDER_SET_REACH
	for index: int in int(tasks.call("spot_count")):
		var spot: Dictionary = tasks.call("spot", index)
		if str(spot["task"]) != "clean_gutters":
			continue
		var at: Vector3 = spot["at"]
		var distance := Vector2(at.x - player.global_position.x, at.z - player.global_position.z).length()
		if distance < best_distance:
			best = index
			best_distance = distance
	if best < 0:
		return
	var gutter: Dictionary = tasks.call("spot", best)
	var top: Vector3 = (gutter["at"] as Vector3) - Vector3(0.0, 0.15, 0.0)
	var out: Vector3 = gutter["normal"]
	held_by = 0
	_set_solid(true)
	freeze = true
	var foot := Vector3(top.x, player.global_position.y, top.z) + out * (0.28 * top.y + 0.3)
	global_position = foot
	rotation = Vector3.ZERO
	ladder_top = top


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_place_ladder() -> void:
	if Net.is_host():
		_place_ladder(multiplayer.get_remote_sender_id())


## E by a water source: a hose hooks up there (or unhooks if it already is),
## a pressure washer fills its tank.
func request_hookup() -> void:
	if Net.is_host():
		_hookup(Net.local_peer_id())
	else:
		_rpc_request_hookup.rpc_id(1)


func _hookup(peer_id: int) -> void:
	if held_by != peer_id or (kind != "hose" and kind != "pressure_washer"):
		return
	var holder := _player(peer_id)
	if holder == null:
		return
	var source := _WaterSources.nearest(get_tree(), holder.global_position, Constants.WATER_REACH)
	if source == null:
		return
	var source_kind := str(source.get_meta("kind"))
	if kind == "hose":
		if hose_source == source_kind:
			hose_source = ""
			return
		hose_source = source_kind
	else:
		water = 100.0
	if source_kind == "spigot":
		var tasks := get_tree().get_first_node_in_group("job_tasks")
		if tasks != null:
			tasks.call("add_water_fee", float(Constants.SPIGOT_HOOKUP_FEE))


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_hookup() -> void:
	if Net.is_host():
		_hookup(multiplayer.get_remote_sender_id())


## Host: water came out just now (net/work/job_tasks.gd says so on each spray).
func mark_spraying() -> void:
	_spray_left = 0.3
	if not spraying:
		spraying = true


## Host: a hooked-up hose stretched past its length comes loose and its end whips
## back across the yard; anyone it passes is knocked out.
func _step_hose(delta: float) -> void:
	_spray_left -= delta
	if spraying and _spray_left <= 0.0:
		spraying = false
	if _whip_t >= 0.0:
		_whip_t += delta / Constants.HOSE_WHIP_SECONDS
		var t := clampf(_whip_t, 0.0, 1.0)
		# The loose end flies from the source toward the nozzle, bowing out sideways.
		var across := (global_position - _whip_from).cross(Vector3.UP).normalized()
		var tip := _whip_from.lerp(global_position, t * t) + across * sin(t * PI) * 3.0 + Vector3.UP * sin(t * PI) * 1.2
		for node: Node in get_tree().get_nodes_in_group("players"):
			var person := node as Node3D
			if person == null or _whipped.has(person) or person.name == str(held_by):
				continue
			if (person.global_position + Vector3(0.0, 1.0, 0.0)).distance_to(tip) < Constants.HOSE_WHIP_RADIUS:
				_whipped.append(person)
				_rpc_bonk_fx.rpc(get_path_to(person), "heavy", (tip - _whip_from).normalized() * 6.0 + Vector3.UP * 2.0)
		if _whip_t >= 1.0:
			_whip_t = -1.0
	if kind != "hose" or hose_source == "":
		return
	var source := _WaterSources.find(get_tree(), hose_source)
	if source == null:
		hose_source = ""
		return
	if source.global_position.distance_to(global_position) > Constants.HOSE_LENGTH:
		_whip_from = source.global_position
		_whip_t = 0.0
		_whipped.clear()
		hose_source = ""
		_rpc_hose_snap.rpc(_whip_from)
		# The one holding it gets yanked too.
		var holder := _player(held_by) if held_by != 0 else null
		if holder != null:
			_rpc_bonk_fx.rpc(get_path_to(holder), "light", (_whip_from - holder.global_position).normalized() * 3.0)


## Everyone sees the hose snap loose (props/hose_rope.gd whips it) and hears it.
@rpc("authority", "call_local", "reliable")
func _rpc_hose_snap(from: Vector3) -> void:
	var rope := get_node_or_null("HoseRope")
	if rope != null:
		rope.call("snap", from)
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play", "bonk")


func request_grab() -> void:
	if Net.is_host():
		_handle_grab(Net.local_peer_id())
	else:
		_rpc_request_grab.rpc_id(1)


func request_drop() -> void:
	if Net.is_host():
		_handle_release(Net.local_peer_id(), Vector3.ZERO)
	else:
		_rpc_request_drop.rpc_id(1)


## power is how hard: Constants.THROW_POWER_MIN to THROW_POWER_MAX, 1 for a normal throw.
func request_throw(direction: Vector3, power: float = 1.0) -> void:
	if Net.is_host():
		_handle_release(Net.local_peer_id(), direction, power)
	else:
		_rpc_request_throw.rpc_id(1, direction, power)


func _host_step() -> void:
	if kind == "hose" or kind == "pressure_washer":
		_step_hose(get_physics_process_delta_time())
	var kg := weight_kg()
	if not is_equal_approx(mass, kg):
		mass = kg
	if held_by != 0:
		var player := _player(held_by)
		if player == null:
			held_by = 0
			_set_solid(true)
			return
		var was := global_position
		global_position = _hold_position(player)
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		# A mower being pushed mows whatever it rolls over.
		if kind == "lawn_mower" and Vector2(global_position.x - was.x, global_position.z - was.z).length() > 0.01:
			var tasks := get_tree().get_first_node_in_group("job_tasks")
			if tasks != null:
				tasks.call("host_work", "mow_lawn", global_position, 0.75, get_physics_process_delta_time(), held_by)
		return
	for node: Node in get_tree().get_nodes_in_group("players"):
		if not node is CharacterBody3D:
			continue
		var player := node as CharacterBody3D
		var offset := global_position - player.global_position
		if offset.length() > PUSH_REACH or player.velocity.length() < 0.8:
			continue
		apply_central_impulse(player.velocity * mass * 0.15)
	if _airborne:
		_check_bonks()
	_come_back_in()
	if _airborne and linear_velocity.length() < 0.35:
		_airborne = false
	_try_load_bag()
	_try_unload_wheelbarrow()


func _handle_grab(peer_id: int) -> void:
	if held_by != 0:
		return
	# One thing at a time: hands full means no grabbing.
	for node: Node in get_tree().get_nodes_in_group("props"):
		if int(node.get("held_by")) == peer_id:
			return
	var player := _player(peer_id)
	if player == null or player.global_position.distance_to(global_position) > GRAB_REACH:
		return
	held_by = peer_id
	_airborne = false
	# Taking a set-up ladder down: anyone on it falls.
	if ladder_top != Vector3.ZERO:
		ladder_top = Vector3.ZERO
	_set_solid(false)


func _handle_release(peer_id: int, direction: Vector3, power: float = 1.0) -> void:
	if held_by != peer_id:
		return
	var player := _player(peer_id)
	held_by = 0
	if player != null:
		var forward := -player.global_transform.basis.z
		forward.y = 0.0
		if forward.length() > 0.001:
			forward = forward.normalized()
		global_position = player.global_position + Vector3(0.0, 0.4, 0.0) + forward * 1.3
	_set_solid(true)
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length() < 0.1:
		return
	# Every throw is the same shove, so the weight decides how far it goes.
	var strength := clampf(power, Constants.THROW_POWER_MIN, Constants.THROW_POWER_MAX)
	var speed := clampf(Constants.THROW_IMPULSE / weight_kg(), Constants.THROW_SPEED_MIN, Constants.THROW_SPEED_MAX) * strength
	linear_velocity = flat.normalized() * speed + Vector3.UP * (1.5 + speed * 0.3)
	angular_velocity = Vector3(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0), randf_range(-4.0, 4.0)) * (6.0 / weight_kg())
	_airborne = true
	_thrower = peer_id
	_thrown_at = Net.server_time()
	_bonked.clear()
	_rpc_throw_fx.rpc()


## Host only. A flying item that reaches a person bonks them: everyone sees and
## hears it, and a player is shoved and stunned by how heavy and fast it was.
func _check_bonks() -> void:
	var speed := linear_velocity.length()
	if speed < Constants.BONK_MIN_SPEED:
		return
	var targets: Array[Node] = get_tree().get_nodes_in_group("players")
	targets.append_array(get_tree().get_nodes_in_group("bonkable"))
	for node: Node in targets:
		var target := node as Node3D
		if target == null or _bonked.has(target) or not target.is_inside_tree():
			continue
		if target.name == str(_thrower) and Net.server_time() - _thrown_at < 0.5:
			continue
		var center := target.global_position + Vector3(0.0, 0.95, 0.0)
		var offset := center - global_position
		if absf(offset.y) > 1.2 or Vector2(offset.x, offset.z).length() > 0.85:
			continue
		_bonked.append(target)
		var flat := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
		var shove_speed := minf(weight_kg() * speed * Constants.BONK_SHOVE_PER_MOMENTUM, Constants.BONK_SHOVE_MAX)
		var push := (flat.normalized() if flat.length() > 0.1 else Vector3.FORWARD) * shove_speed + Vector3.UP * shove_speed * 0.35
		_rpc_bonk_fx.rpc(get_path_to(target), weight_tier(), push)
		# It bounces off them.
		linear_velocity = -linear_velocity * 0.25 + Vector3.UP * 1.5


## Host only. Something thrown into the street or a neighbor's yard comes back
## into the pad once it settles, so the job's one rake can't be lost.
func _come_back_in() -> void:
	var zone_name := _zone_name()
	var zone := _zone_center()
	var local := global_position - zone
	var rect: Rect2 = Constants.PAD_RECTS.get(zone_name, Rect2(-20.0, -20.0, 40.0, 40.0))
	var outside := not rect.grow(0.3).has_point(Vector2(local.x, local.z))
	if global_position.y < -5.0 or (outside and linear_velocity.length() < 0.5):
		var inner := rect.grow(-1.5)
		var back := Vector3(clampf(local.x, inner.position.x, inner.end.x), 1.2, clampf(local.z, inner.position.y, inner.end.y))
		global_position = zone + back
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		_airborne = false


## Which zone node this prop is nearest.
func _zone_name() -> String:
	var world := get_tree().get_first_node_in_group("world")
	var best := "LotZone"
	var best_distance := INF
	if world == null:
		return best
	for zone_name: String in ["StoreZone", "LotZone", "BorderZone"]:
		var zone := world.get_node_or_null(zone_name) as Node3D
		if zone != null and zone.global_position.distance_to(global_position) < best_distance:
			best_distance = zone.global_position.distance_to(global_position)
			best = zone_name
	return best


## The middle of whichever zone this prop is nearest: the store, the lot, or the border.
func _zone_center() -> Vector3:
	var world := get_tree().get_first_node_in_group("world")
	var best := Vector3.ZERO
	var best_distance := INF
	if world == null:
		return best
	for zone_name: String in ["StoreZone", "LotZone", "BorderZone"]:
		var zone := world.get_node_or_null(zone_name) as Node3D
		if zone == null:
			continue
		var distance := zone.global_position.distance_to(global_position)
		if distance < best_distance:
			best_distance = distance
			best = zone.global_position
	return best


## Everyone plays the throw's whoosh.
@rpc("authority", "call_local", "reliable")
func _rpc_throw_fx() -> void:
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play", "whoosh")


## Everyone sees and hears a bonk; the person hit reacts (player.gd on_bonked,
## or a pedestrian's bonk). target is relative to this prop, the same on every peer.
@rpc("authority", "call_local", "reliable")
func _rpc_bonk_fx(target: NodePath, tier: String, push: Vector3) -> void:
	var node := get_node_or_null(target)
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play", "thud" if tier == "heavy" else "bonk")
		if tier == "heavy":
			sfx.call("play", "dizzy")
	if node != null and node.has_method("on_bonked"):
		node.call("on_bonked", push, tier)


func _player(peer_id: int) -> CharacterBody3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id) and node is CharacterBody3D:
			return node as CharacterBody3D
	return null


func _set_solid(solid: bool) -> void:
	collision_layer = 1 if solid else 0
	collision_mask = 1 if solid else 0
	if Net.is_host():
		freeze = not solid
	else:
		freeze = true


## Host only. Drop the prop if this peer is still holding it.
func force_release() -> void:
	if Net.is_host() and held_by != 0:
		_handle_release(held_by, Vector3.ZERO)


## Press E while holding a leaf bag next to this wheelbarrow.
func request_load_held() -> void:
	if kind != "wheelbarrow":
		return
	if Net.is_host():
		_load_held(Net.local_peer_id())
	else:
		_rpc_request_load.rpc_id(1)


## The holder presses E by Chefty: a bag is tossed in, a wheelbarrow dumped.
func request_load_truck() -> void:
	if Net.is_host():
		_load_truck(Net.local_peer_id())
	else:
		_rpc_request_load_truck.rpc_id(1)


## True when this prop, held, is close enough to Chefty to load it.
func near_truck() -> bool:
	var truck := get_tree().get_first_node_in_group("chefty")
	if truck == null:
		return false
	var at: Vector3 = truck.call("body_position")
	# Measure from the holder: a carried prop catches up to their hands a tick late.
	var holder := _player(held_by) if held_by != 0 else null
	var from := holder.global_position if holder != null else global_position
	return Vector2(from.x - at.x, from.z - at.z).length() <= Constants.TRUCK_UNLOAD_RADIUS + 1.0


func _load_truck(peer_id: int) -> void:
	if held_by != peer_id or not near_truck():
		return
	var truck := get_tree().get_first_node_in_group("chefty")
	if kind == "leaf_bag":
		if int(truck.call("accept_bags", 1, value)) > 0:
			queue_free()
	elif kind == "wheelbarrow" and stored_bags > 0:
		var taken := int(truck.call("accept_bags", stored_bags, stored_value))
		if taken > 0:
			var moved_value := int(round(float(stored_value) * float(taken) / float(stored_bags)))
			stored_bags -= taken
			stored_value = maxi(0, stored_value - moved_value)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_load_truck() -> void:
	if Net.is_host():
		_load_truck(multiplayer.get_remote_sender_id())


func _try_load_bag() -> void:
	if kind != "leaf_bag" or held_by != 0:
		return
	# Tossed into Chefty's bed: it's loaded.
	var truck := get_tree().get_first_node_in_group("chefty")
	if truck != null and bool(truck.call("in_bed", global_position)):
		if int(truck.call("accept_bags", 1, value)) > 0:
			queue_free()
			return
	var closest: Node = null
	var closest_distance := Constants.BAG_LOAD_RADIUS
	for node: Node in get_tree().get_nodes_in_group("props"):
		if node == self or str(node.get("kind")) != "wheelbarrow":
			continue
		var distance := global_position.distance_to((node as Node3D).global_position)
		if distance < closest_distance:
			closest = node
			closest_distance = distance
	if closest == null or not bool(closest.call("receive_bag", value)):
		return
	queue_free()


## Host only. Returns true when the bag fits. bag_value is that bag's dollars.
func receive_bag(bag_value: int = 0) -> bool:
	if kind != "wheelbarrow" or stored_bags >= Campaign.wheelbarrow_capacity():
		return false
	stored_bags += 1
	stored_value += bag_value
	return true


func _try_unload_wheelbarrow() -> void:
	if kind != "wheelbarrow" or held_by != 0 or stored_bags <= 0 or not _airborne:
		return
	var truck := get_tree().get_first_node_in_group("chefty")
	if truck == null:
		return
	var truck_at: Vector3 = truck.call("body_position")
	if global_position.distance_to(truck_at) > Constants.TRUCK_UNLOAD_RADIUS:
		return
	# If only some bags fit, the truck takes that share of the value.
	var taken := int(truck.call("accept_bags", stored_bags, stored_value))
	if taken > 0:
		var moved_value := int(round(float(stored_value) * float(taken) / float(stored_bags)))
		stored_bags -= taken
		stored_value = maxi(0, stored_value - moved_value)
	_airborne = false


func _load_held(peer_id: int) -> void:
	if kind != "wheelbarrow" or stored_bags >= Campaign.wheelbarrow_capacity():
		return
	var player := _player(peer_id)
	if player == null or player.global_position.distance_to(global_position) > GRAB_REACH:
		return
	for node: Node in get_tree().get_nodes_in_group("props"):
		if node == self or str(node.get("kind")) != "leaf_bag":
			continue
		if int(node.get("held_by")) != peer_id:
			continue
		stored_bags += 1
		stored_value += int(node.get("value"))
		node.queue_free()
		return


func _apply_color() -> void:
	if not is_node_ready():
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	%Visual.material_override = material


func _refresh_label() -> void:
	if not is_node_ready():
		return
	# Real shapes from props/prop_looks.gd. The prompt names things, so only the
	# wheelbarrow keeps a floating count.
	_PropLooks.dress(self, kind, color)
	# Bags show what they're worth, so a fat bag from a big pile reads as a prize.
	%Label.visible = kind == "wheelbarrow" or (kind == "leaf_bag" and value > 0)
	if kind == "wheelbarrow":
		var capacity := Campaign.wheelbarrow_capacity()
		var full := " full" if stored_bags >= capacity else ""
		%Label.text = "%d/%d%s  $%d" % [stored_bags, capacity, full, stored_value]
		_PropLooks.show_bags(self, stored_bags)
	elif kind == "leaf_bag":
		%Label.text = "$%d" % value
	else:
		%Label.text = label if label != "" else name


func _hold_position(player: CharacterBody3D) -> Vector3:
	# The rake is held low and close, tines on the leaves. Everything else at chest height.
	var forward := -player.global_transform.basis.z
	var right := player.global_transform.basis.x
	match kind:
		"lawn_mower":
			# Pushed along the ground in front.
			return player.global_position + forward * 1.15
		"pressure_washer":
			# Rolled along at your side while you hold its wand.
			return player.global_position + right * 0.85 + forward * 0.2
		"ladder":
			# On the shoulder.
			return player.global_position + Vector3(0.0, 1.45, 0.0) + right * 0.3
		"leaf_blower", "hedge_trimmer", "hose", "paint_roller":
			return player.global_position + Vector3(0.0, 0.8, 0.0) + forward * 0.55 + right * 0.25
	if kind == "rake":
		# A little to the right, so the handle doesn't split a first-person view in half.
		return player.global_position + Vector3(0.0, 0.75, 0.0) + (-player.global_transform.basis.z) * 0.9 + player.global_transform.basis.x * 0.35
	return player.global_position + Vector3(0.0, 1.2, 0.0) + (-player.global_transform.basis.z) * 1.15


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_grab() -> void:
	if Net.is_host():
		_handle_grab(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_drop() -> void:
	if Net.is_host():
		_handle_release(multiplayer.get_remote_sender_id(), Vector3.ZERO)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_throw(direction: Vector3, power: float) -> void:
	if Net.is_host():
		_handle_release(multiplayer.get_remote_sender_id(), direction, power)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_load() -> void:
	if Net.is_host():
		_load_held(multiplayer.get_remote_sender_id())
