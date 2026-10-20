extends RigidBody3D

const _PropLooks = preload("res://props/prop_looks.gd")

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

var _airborne: bool = false

const GRAB_REACH: float = 2.4
const PUSH_REACH: float = 1.1


func _enter_tree() -> void:
	add_to_group("props")


func _ready() -> void:
	_apply_color()
	_refresh_label()
	if multiplayer.multiplayer_peer != null and not Net.is_host():
		freeze = true


func _physics_process(_delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	# A carried prop must not stay solid. Moving a colliding body into the player launches them.
	_set_solid(held_by == 0)
	_refresh_label()
	if kind == "rake":
		var holder := _player(held_by) if held_by != 0 else null
		var raking := held_by == Net.local_peer_id() and Input.is_action_pressed("primary")
		_PropLooks.pose_rake(self, holder, raking)
	if Net.is_host():
		_host_step()
	elif held_by == Net.local_peer_id():
		var player := _player(held_by)
		if player != null:
			%Visual.global_position = _hold_position(player)


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


func request_throw(direction: Vector3) -> void:
	if Net.is_host():
		_handle_release(Net.local_peer_id(), direction)
	else:
		_rpc_request_throw.rpc_id(1, direction)


func _host_step() -> void:
	if held_by != 0:
		var player := _player(held_by)
		if player == null:
			held_by = 0
			_set_solid(true)
			return
		global_position = _hold_position(player)
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		return
	for node: Node in get_tree().get_nodes_in_group("players"):
		if not node is CharacterBody3D:
			continue
		var player := node as CharacterBody3D
		var offset := global_position - player.global_position
		if offset.length() > PUSH_REACH or player.velocity.length() < 0.8:
			continue
		apply_central_impulse(player.velocity * mass * 0.15)
	if _airborne and linear_velocity.length() < 0.35:
		_airborne = false
	_try_load_bag()
	_try_unload_wheelbarrow()


func _handle_grab(peer_id: int) -> void:
	if held_by != 0:
		return
	var player := _player(peer_id)
	if player == null or player.global_position.distance_to(global_position) > GRAB_REACH:
		return
	held_by = peer_id
	_airborne = false
	_set_solid(false)


func _handle_release(peer_id: int, direction: Vector3) -> void:
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
	apply_central_impulse(flat.normalized() * mass * 4.0 + Vector3.UP * mass)
	_airborne = true


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


func _try_load_bag() -> void:
	if kind != "leaf_bag" or held_by != 0:
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
	if kind == "rake":
		return player.global_position + Vector3(0.0, 0.75, 0.0) + (-player.global_transform.basis.z) * 0.9
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
func _rpc_request_throw(direction: Vector3) -> void:
	if Net.is_host():
		_handle_release(multiplayer.get_remote_sender_id(), direction)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_load() -> void:
	if Net.is_host():
		_load_held(multiplayer.get_remote_sender_id())
