extends Node3D

## Authority: host spawns players and the test lot. Geometry is the same on every peer.
## M1 always loads the test lot so the lot zone is a place you can stand.

const TEST_LOT: PackedScene = preload("res://levels/lots/lot_test.tscn")
const BAG_SCENE: PackedScene = preload("res://props/yard_prop.tscn")
const _PlayerDirector: Script = preload("res://net/player_director.gd")

var _bag_serial: int = 0


func _ready() -> void:
	add_to_group("world")
	%RuntimeProps.add_to_group("runtime_props")
	$Sun.rotation_degrees = Vector3(-50, 30, 0)
	if not Net.is_host():
		return
	_load_test_lot()
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


func _load_test_lot() -> void:
	if %LotSlot.get_child_count() > 0:
		return
	var lot := TEST_LOT.instantiate()
	lot.name = "LotTest"
	%LotSlot.add_child(lot, true)
	var field := lot.get_node_or_null("LeafField")
	if field != null and field.has_signal("bag_requested"):
		field.bag_requested.connect(_spawn_bag)


func _on_player_joined(peer_id: int) -> void:
	_spawn_peer(peer_id)


func _on_player_left(peer_id: int) -> void:
	_PlayerDirector.despawn(%Players, peer_id)


func _spawn_bag(at: Vector3) -> void:
	_bag_serial += 1
	var bag := BAG_SCENE.instantiate()
	bag.name = "Bag%d" % _bag_serial
	bag.set("color", Color(0.42, 0.52, 0.24, 1))
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
