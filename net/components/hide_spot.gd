extends Node3D

## Authority: host decides who is inside. A place a player can hide in during a
## run event (OQ-010, counterplay v0). The crew ignores a hidden player, unless a
## crew member could see them going in, in which case it walks over and pulls
## them out. Clients ask with request_enter() and request_exit().
## The scene in props/hide_spot.tscn gives it a body and a label.

signal occupant_changed(peer_id: int)

## Totals for this process, read by net/dev/probe.gd. Host only.
static var stats: Dictionary = {"entered": 0, "pulled_out": 0}

## Peer hiding here, or 0.
var occupant: int = 0
var _seen_entering: bool = false


func _ready() -> void:
	add_to_group("hide_spots")
	Net.player_left.connect(_on_player_left)
	# A late joiner asks once its own copy of the lot exists, so the reply has somewhere to land.
	if not Net.is_host() and multiplayer.multiplayer_peer != null:
		_rpc_request_state.rpc_id(1)


## The lot can be unloaded with someone inside. Let them out locally on every peer.
func _exit_tree() -> void:
	if occupant == 0:
		return
	var body := _player(occupant)
	occupant = 0
	if body != null and body.has_method("set_hidden_in"):
		body.call("set_hidden_in", null)


## The hide spot this peer is in, or null.
static func spot_of(tree: SceneTree, peer_id: int) -> Node3D:
	for node: Node in tree.get_nodes_in_group("hide_spots"):
		if int(node.get("occupant")) == peer_id:
			return node as Node3D
	return null


func request_enter() -> void:
	if Net.is_host():
		_handle_enter(Net.local_peer_id())
	else:
		_rpc_request_enter.rpc_id(1)


func request_exit() -> void:
	if Net.is_host():
		_handle_exit(Net.local_peer_id())
	else:
		_rpc_request_exit.rpc_id(1)


## Host only: true when a crew member could see this player get in.
func was_seen_entering() -> bool:
	return _seen_entering


## Host only: a crew member opens the spot and takes whoever is inside.
func pull_out() -> int:
	var peer_id := occupant
	if peer_id != 0:
		stats["pulled_out"] = int(stats["pulled_out"]) + 1
		_rpc_set_occupant.rpc(0)
	return peer_id


## Where a player stands after leaving: in front of the spot.
func exit_position() -> Vector3:
	return global_position + global_basis.z * 1.4 + Vector3(0.0, 0.1, 0.0)


func _handle_enter(peer_id: int) -> void:
	if occupant != 0 or spot_of(get_tree(), peer_id) != null:
		return
	var body := _player(peer_id)
	if body == null or body.global_position.distance_to(global_position) > Constants.HIDE_REACH + 0.6:
		return
	var director := get_tree().get_first_node_in_group("run_director")
	if director != null and bool(director.call("is_captured", peer_id)):
		return
	_seen_entering = false
	for crew: Node in get_tree().get_nodes_in_group("crew"):
		if bool(crew.call("can_see_peer", peer_id)):
			_seen_entering = true
	stats["entered"] = int(stats["entered"]) + 1
	_rpc_set_occupant.rpc(peer_id)


func _handle_exit(peer_id: int) -> void:
	if occupant == peer_id:
		_rpc_set_occupant.rpc(0)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_enter() -> void:
	if Net.is_host():
		_handle_enter(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_exit() -> void:
	if Net.is_host():
		_handle_exit(multiplayer.get_remote_sender_id())


@rpc("authority", "call_local", "reliable")
func _rpc_set_occupant(peer_id: int) -> void:
	var previous := occupant
	occupant = peer_id
	if previous != 0:
		var leaving := _player(previous)
		if leaving != null and leaving.has_method("set_hidden_in"):
			leaving.call("set_hidden_in", null)
	if peer_id != 0:
		var entering := _player(peer_id)
		if entering != null and entering.has_method("set_hidden_in"):
			entering.call("set_hidden_in", self)
	occupant_changed.emit(peer_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_state() -> void:
	if Net.is_host() and occupant != 0:
		_rpc_set_occupant.rpc_id(multiplayer.get_remote_sender_id(), occupant)


func _on_player_left(peer_id: int) -> void:
	if Net.is_host() and occupant == peer_id:
		_rpc_set_occupant.rpc(0)


func _player(peer_id: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node as Node3D
	return null
