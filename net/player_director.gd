extends RefCounted

## Authority: host. The world calls this to spawn and despawn one player node per peer.
## Spawned nodes are named with the peer id so authority can be derived from the name.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")


static func spawn(players_root: Node, peer_id: int, at: Transform3D) -> void:
	if players_root.get_node_or_null(str(peer_id)) != null:
		return
	var player := PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	# Players live under a node at the origin, so the marker's global origin is the local position.
	player.position = at.origin
	player.set("body_yaw", at.basis.get_euler().y)
	players_root.add_child(player, true)
	# The spawn position only reaches the owner through a host-ordered teleport.
	player.call_deferred("send_teleport", at)


static func despawn(players_root: Node, peer_id: int) -> void:
	var player := players_root.get_node_or_null(str(peer_id))
	if player != null:
		player.queue_free()
