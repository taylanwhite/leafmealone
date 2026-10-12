extends Node3D

## Authority: host spawns players and the job lot. Geometry is the same on every peer.

const JOB_LOT: PackedScene = preload("res://levels/lots/lot_01.tscn")
const BAG_SCENE: PackedScene = preload("res://props/yard_prop.tscn")
const _PlayerDirector: Script = preload("res://net/player_director.gd")
const _Boarding: Script = preload("res://levels/boarding.gd")

var _bag_serial: int = 0


func _ready() -> void:
	add_to_group("world")
	%RuntimeProps.add_to_group("runtime_props")
	$Sun.rotation_degrees = Vector3(-50, 30, 0)
	var director := preload("res://net/run_events/director.gd").new()
	director.name = "RunDirector"
	add_child(director)
	if not Net.is_host():
		return
	_load_job_lot()
	for peer_id: int in Net.peer_ids():
		_spawn_peer(peer_id)
	Net.player_joined.connect(_on_player_joined)
	Net.player_left.connect(_on_player_left)


## World position used when the host teleports a player into a zone.
func get_spawn_transform(zone: Net.Zone, spawn_marker: StringName, peer_id: int) -> Transform3D:
	var points := _spawn_points(zone)
	if spawn_marker != &"" and points.has_node(String(spawn_marker)):
		return points.get_node(String(spawn_marker)).global_transform
	var markers := points.get_children()
	if markers.is_empty():
		return points.global_transform
	return (markers[posmod(peer_id, markers.size())] as Node3D).global_transform


func request_depart() -> void:
	if Net.is_host():
		_host_depart()
	else:
		_rpc_request_depart.rpc_id(1)


func request_finish() -> void:
	if Net.is_host():
		_host_finish()
	else:
		_rpc_request_finish.rpc_id(1)


## Host only. Called by the truck when the path is done.
func on_ride_arrived(destination: int) -> void:
	if destination == Net.Zone.STORE:
		_free_lot()


func _load_job_lot() -> void:
	if %LotSlot.get_child_count() > 0:
		return
	var lot := JOB_LOT.instantiate()
	lot.name = "Lot%d" % Campaign.current_lot_index()
	%LotSlot.add_child(lot, true)
	Campaign.mark_job_open()
	var field := lot.get_node_or_null("LeafField")
	if field != null and field.has_signal("bag_requested") and not field.bag_requested.is_connected(_spawn_bag):
		field.bag_requested.connect(_spawn_bag)


func _free_lot() -> void:
	for child: Node in %LotSlot.get_children():
		child.queue_free()


func _host_depart() -> void:
	var ride := get_node_or_null("Rides/Chefty")
	if ride == null or bool(ride.call("is_riding")):
		return
	var party: Array = _Boarding.call("choose_party", _players_near(%TruckPad.global_position))
	if party.is_empty():
		return
	_load_job_lot()
	ride.call("depart", party, Net.Zone.LOT)


func _host_finish() -> void:
	Campaign.finish_job()
	var ride := get_node_or_null("Rides/Chefty")
	if ride == null or bool(ride.call("is_riding")):
		return
	var party: Array = _Boarding.call("choose_party", Net.players_in_zone(Net.Zone.LOT))
	var riding: Array[int] = []
	for peer_id: Variant in party:
		riding.append(int(peer_id))
	for peer_id: int in Net.players_in_zone(Net.Zone.LOT):
		if not riding.has(peer_id):
			Net.move_player_to_zone(peer_id, Net.Zone.STORE)
	if riding.is_empty():
		_free_lot()
		return
	ride.call("depart", riding, Net.Zone.STORE)


func _players_near(point: Vector3) -> Array[int]:
	var ids: Array[int] = []
	for node: Node in get_tree().get_nodes_in_group("players"):
		if not node is Node3D:
			continue
		if (node as Node3D).global_position.distance_to(point) <= _Boarding.BOARD_RADIUS_METERS:
			ids.append(int(node.name))
	return ids


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_depart() -> void:
	if Net.is_host():
		_host_depart()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_finish() -> void:
	if Net.is_host():
		_host_finish()


func _on_player_joined(peer_id: int) -> void:
	_spawn_peer(peer_id)


func _on_player_left(peer_id: int) -> void:
	_PlayerDirector.despawn(%Players, peer_id)


func _spawn_bag(at: Vector3) -> void:
	_bag_serial += 1
	var bag := BAG_SCENE.instantiate()
	bag.name = "Bag%d" % _bag_serial
	bag.set("kind", "leaf_bag")
	bag.set("color", Color(0.72, 0.48, 0.18, 1))
	bag.set("label", "Leaf bag")
	%RuntimeProps.add_child(bag, true)
	bag.global_position = at + Vector3(0.0, 0.6, 0.0)


func _spawn_peer(peer_id: int) -> void:
	var zone := Net.player_zone(peer_id)
	_PlayerDirector.spawn(%Players, peer_id, get_spawn_transform(zone, &"", peer_id))


func _spawn_points(zone: Net.Zone) -> Node3D:
	match zone:
		Net.Zone.LOT:
			return %LotSpawnPoints
		Net.Zone.BORDER:
			return %BorderSpawnPoints
		_:
			return %StoreSpawnPoints
