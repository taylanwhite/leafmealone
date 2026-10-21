extends Node

## Authority: host. Players roughing each other up (Taylan, 2026-10-21): a
## wound-up punch, a whack with whatever's in hand, grabbing a friend, carrying
## them around, and throwing them. Clients ask; the host checks reach and who's
## where, then tells everyone what landed (the hit RPC) and tells the two owners
## involved what they're now doing (carrying, carried, thrown), following the
## host-to-owner pattern: each player's replicated flags are set by its owner.

const _Strings = preload("res://ui/strings.gd")

var _flight_hits: Dictionary = {}


func _ready() -> void:
	add_to_group("brawl")


# ---------------------------------------------------------------- asks

## Swing at whoever's in front, with a punch wound up to this tier.
func request_punch(tier: String) -> void:
	if Net.is_host():
		_handle_punch(Net.local_peer_id(), tier, false)
	else:
		_rpc_request_punch.rpc_id(1, tier)


## Swing whatever's held at whoever's in front; it hits as hard as it's heavy.
func request_whack() -> void:
	if Net.is_host():
		_handle_punch(Net.local_peer_id(), "", true)
	else:
		_rpc_request_whack.rpc_id(1)


func request_grab_player(target_id: int) -> void:
	if Net.is_host():
		_handle_grab(Net.local_peer_id(), target_id)
	else:
		_rpc_request_grab.rpc_id(1, target_id)


## mode is "drop" (set them down) or "throw" (direction and power like an item throw).
func request_release_player(mode: String, direction: Vector3 = Vector3.ZERO, power: float = 1.0) -> void:
	if Net.is_host():
		_handle_release(Net.local_peer_id(), mode, direction, power)
	else:
		_rpc_request_release.rpc_id(1, mode, direction, power)


## The one being carried wriggled enough to get loose.
func request_break_free() -> void:
	if Net.is_host():
		_handle_break_free(Net.local_peer_id())
	else:
		_rpc_request_break_free.rpc_id(1)


# ---------------------------------------------------------------- host

func _handle_punch(peer_id: int, tier: String, whack: bool) -> void:
	var puncher := _player(peer_id)
	if puncher == null or bool(puncher.call("is_hidden")) or int(puncher.get("carried_by")) != 0:
		return
	var held := _held_by(peer_id)
	var sound := "whoosh"
	if whack:
		# Tools are for working, and the rake is for raking; anything else is a club.
		if held == null or Constants.TOOL_PRICES.has(str(held.get("kind"))) or str(held.get("kind")) == "rake":
			return
		tier = str(held.call("weight_tier"))
	elif held != null:
		return
	var reach := Constants.WHACK_REACH if whack else Constants.PUNCH_REACH
	var target := _in_front(puncher, reach, peer_id)
	if target == null:
		_rpc_hit.rpc(puncher.get_path(), NodePath(), Vector3.ZERO, tier, sound)
		return
	var forward := -puncher.global_basis.z
	forward.y = 0.0
	var push := forward.normalized() * float(Constants.PUNCH_PUSH.get(tier, 3.0)) + Vector3.UP * (1.2 if tier != "heavy" else 2.5)
	sound = "thud" if tier == "heavy" else "bonk"
	_rpc_hit.rpc(puncher.get_path(), target.get_path(), push, tier, sound)
	_heat_for(target, tier)


func _handle_grab(peer_id: int, target_id: int) -> void:
	var grabber := _player(peer_id)
	var target := _player(target_id)
	if grabber == null or target == null or peer_id == target_id:
		return
	if _held_by(peer_id) != null or int(grabber.get("carrying")) != 0 or int(grabber.get("carried_by")) != 0:
		return
	if bool(target.call("is_hidden")) or int(target.get("carried_by")) != 0 or int(target.get("carrying")) != 0 or bool(target.get("thrown")):
		return
	if target.global_position.distance_to(grabber.global_position) > Constants.GRAB_PLAYER_REACH + 0.6:
		return
	_tell_carry(peer_id, target_id, 0)
	_tell_carry(target_id, 0, peer_id)
	_rpc_hit.rpc(grabber.get_path(), NodePath(), Vector3.ZERO, "grab", "vo_hup")


func _handle_release(peer_id: int, mode: String, direction: Vector3, power: float) -> void:
	var carrier := _player(peer_id)
	if carrier == null:
		return
	var target_id := int(carrier.get("carrying"))
	var target := _player(target_id)
	if target_id == 0 or target == null:
		return
	_tell_carry(peer_id, 0, 0)
	if mode == "throw":
		var flat := Vector3(direction.x, 0.0, direction.z)
		if flat.length() < 0.1:
			flat = -carrier.global_basis.z
		var strength := clampf(power, Constants.THROW_POWER_MIN, Constants.THROW_POWER_MAX)
		var velocity := flat.normalized() * Constants.PLAYER_THROW_SPEED * strength + Vector3.UP * Constants.PLAYER_THROW_LIFT
		_tell_thrown(target_id, velocity, peer_id)
		_rpc_hit.rpc(carrier.get_path(), NodePath(), Vector3.ZERO, "throw", "whoosh")
	else:
		_tell_carry(target_id, 0, 0)


func _handle_break_free(peer_id: int) -> void:
	var carried := _player(peer_id)
	if carried == null:
		return
	var carrier_id := int(carried.get("carried_by"))
	if carrier_id == 0:
		return
	_tell_carry(carrier_id, 0, 0)
	_tell_carry(peer_id, 0, 0)
	var carrier := _player(carrier_id)
	if carrier != null:
		# Wriggling free knocks the carrier back a step.
		_rpc_hit.rpc(carried.get_path(), carrier.get_path(), (carrier.global_basis.z).normalized() * 2.0 + Vector3.UP, "light", "bonk")


## A thrown player who flies into someone takes them down too.
func _physics_process(_delta: float) -> void:
	if not Net.is_host():
		return
	for node: Node in get_tree().get_nodes_in_group("players"):
		var flyer := node as CharacterBody3D
		if flyer == null:
			continue
		var key := flyer.name
		if not bool(flyer.get("thrown")):
			_flight_hits.erase(key)
			continue
		var hit: Array = _flight_hits.get(key, [])
		var speed := Vector3(flyer.velocity.x, 0.0, flyer.velocity.z)
		if speed.length() < 2.0:
			continue
		var people: Array[Node] = get_tree().get_nodes_in_group("players")
		people.append_array(get_tree().get_nodes_in_group("bonkable"))
		for other_node: Node in people:
			var other := other_node as Node3D
			if other == null or other == flyer or hit.has(other) or not other.is_inside_tree():
				continue
			if other.is_in_group("players") and bool(other.call("is_hidden")):
				continue
			var offset := other.global_position - flyer.global_position
			if absf(offset.y) > 1.2 or Vector2(offset.x, offset.z).length() > Constants.THROWN_HIT_RADIUS:
				continue
			hit.append(other)
			_flight_hits[key] = hit
			var push := speed.normalized() * 5.0 + Vector3.UP * 2.5
			_rpc_hit.rpc(flyer.get_path(), other.get_path(), push, "heavy", "thud")
			_heat_for(other, "heavy")


# ---------------------------------------------------------------- helpers

func _tell_carry(peer_id: int, carrying: int, carried_by: int) -> void:
	var player := _player(peer_id)
	if player == null:
		return
	if peer_id == Net.local_peer_id():
		player.call("set_carry_state", carrying, carried_by)
	else:
		player.rpc_id(peer_id, "_rpc_carry", carrying, carried_by)


func _tell_thrown(peer_id: int, velocity: Vector3, thrower: int) -> void:
	var player := _player(peer_id)
	if player == null:
		return
	if peer_id == Net.local_peer_id():
		player.call("set_thrown", velocity, thrower)
	else:
		player.rpc_id(peer_id, "_rpc_thrown", velocity, thrower)


## The nearest person (another player, a passerby, a NICE BOY) within reach and
## roughly in front of this player, or null.
func _in_front(player: Node3D, reach: float, peer_id: int) -> Node3D:
	var forward := -player.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var people: Array[Node] = get_tree().get_nodes_in_group("players")
	people.append_array(get_tree().get_nodes_in_group("bonkable"))
	var best: Node3D = null
	var best_distance := reach
	for node: Node in people:
		var person := node as Node3D
		if person == null or person == player or not person.is_inside_tree() or person.name == str(peer_id):
			continue
		if person.is_in_group("players") and bool(person.call("is_hidden")):
			continue
		var offset := person.global_position - player.global_position
		if absf(offset.y) > 1.5:
			continue
		var flat := Vector3(offset.x, 0.0, offset.z)
		var distance := flat.length()
		if distance > best_distance or (distance > 0.3 and flat.normalized().dot(forward) < 0.5):
			continue
		best = person
		best_distance = distance
	return best


func _heat_for(target: Node3D, tier: String) -> void:
	var heat := get_tree().get_first_node_in_group("heat")
	if heat == null or target.is_in_group("players"):
		return
	if target.is_in_group("crew"):
		heat.call("add", Constants.HEAT_CREW_BONK, "crew_punch")
	else:
		heat.call("add", float(Constants.HEAT_PEDESTRIAN_BONK.get(tier, 4.0)), "pedestrian_punch")


func _player(peer_id: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node as Node3D
	return null


func _held_by(peer_id: int) -> Node:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if int(node.get("held_by")) == peer_id:
			return node
	return null


# ---------------------------------------------------------------- every peer

## What everyone sees and hears: the swing (or grab, or throw) on the one doing
## it, and the hit on whoever it landed on.
@rpc("authority", "call_local", "reliable")
func _rpc_hit(puncher_path: NodePath, target_path: NodePath, push: Vector3, tier: String, sound: String) -> void:
	var puncher := get_node_or_null(puncher_path)
	if puncher != null:
		var body := puncher.get_node_or_null("Visual/CartoonBody")
		if body != null:
			body.call("gesture", "punch" if tier != "grab" and tier != "throw" else "startle")
		if puncher.has_method("note_swing"):
			puncher.call("note_swing", tier)
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		if sound.begins_with("vo_"):
			if puncher != null and puncher.has_method("say"):
				puncher.call("say", sound)
		else:
			sfx.call("play", sound)
		if tier == "heavy" and target_path != NodePath():
			sfx.call("play", "dizzy")
	var target := get_node_or_null(target_path)
	if target != null and target.has_method("on_bonked"):
		target.call("on_bonked", push, tier)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_punch(tier: String) -> void:
	if Net.is_host():
		_handle_punch(multiplayer.get_remote_sender_id(), tier, false)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_whack() -> void:
	if Net.is_host():
		_handle_punch(multiplayer.get_remote_sender_id(), "", true)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_grab(target_id: int) -> void:
	if Net.is_host():
		_handle_grab(multiplayer.get_remote_sender_id(), target_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_release(mode: String, direction: Vector3, power: float) -> void:
	if Net.is_host():
		_handle_release(multiplayer.get_remote_sender_id(), mode, direction, power)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_break_free() -> void:
	if Net.is_host():
		_handle_break_free(multiplayer.get_remote_sender_id())
