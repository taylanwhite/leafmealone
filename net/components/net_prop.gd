extends RigidBody3D

## Authority: host
## Clients freeze the body and display the replicated transform. The carrier's own client
## draws the visual at the hand until the host releases it.

@export var color: Color = Color(0.55, 0.42, 0.28, 1)
## Peer id holding this prop, or 0. Replicated.
@export var held_by: int = 0

const GRAB_REACH: float = 2.4
const PUSH_REACH: float = 1.1


func _enter_tree() -> void:
	add_to_group("props")


func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	%Visual.material_override = material
	if multiplayer.multiplayer_peer != null and not Net.is_host():
		freeze = true


func _physics_process(_delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	# A carried prop must not stay solid. Moving a colliding body into the player launches them.
	_set_solid(held_by == 0)
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


func _handle_grab(peer_id: int) -> void:
	if held_by != 0:
		return
	var player := _player(peer_id)
	if player == null or player.global_position.distance_to(global_position) > GRAB_REACH:
		return
	held_by = peer_id
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


func _hold_position(player: CharacterBody3D) -> Vector3:
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
