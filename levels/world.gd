extends Node3D

## Authority: host spawns players and the job lot. Geometry is the same on every peer.

const JOB_LOT: PackedScene = preload("res://levels/lots/lot_01.tscn")
const BAG_SCENE: PackedScene = preload("res://props/yard_prop.tscn")
const _PlayerDirector: Script = preload("res://net/player_director.gd")
const _Boarding: Script = preload("res://levels/boarding.gd")
const _SharedLook: Script = preload("res://levels/shared_look.gd")
const _StoreDressing = preload("res://levels/dressing/store_dressing.gd")
const _BorderDressing = preload("res://levels/dressing/border_dressing.gd")
const _Surroundings = preload("res://levels/dressing/surroundings.gd")
const _Neighborhood = preload("res://levels/dressing/neighborhood.gd")
const GRASS := Color(0.42, 0.52, 0.3)
const SAND := Color(0.78, 0.68, 0.5)
## Behind the store counter at (0, -8), facing the customers.
const CLERK_SPOT := Vector3(0.0, 0.0, -9.3)
## Gap between players who share a spawn marker, in meters.
const SPAWN_SPACING: float = 1.4
## Spawn slots to check for a free one before giving up and sharing.
const SPAWN_SLOTS_TO_TRY: int = 16

var _bag_serial: int = 0


func _ready() -> void:
	add_to_group("world")
	%RuntimeProps.add_to_group("runtime_props")
	# The sun is set up by levels/shared_look.gd.
	var director := preload("res://net/run_events/director.gd").new()
	director.name = "RunDirector"
	add_child(director)
	var crossing := preload("res://net/border_return.gd").new()
	crossing.name = "BorderReturn"
	add_child(crossing)
	_add_curb($StoreZone)
	_add_curb($LotZone)
	_add_curb($BorderZone)
	var sfx := preload("res://audio/sfx.gd").new()
	sfx.name = "Sfx"
	add_child(sfx)
	_dress()
	_SharedLook.call("apply", self)
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)
	if not Net.is_host():
		return
	_load_job_lot()
	for peer_id: int in Net.peer_ids():
		_spawn_peer(peer_id)
	Net.player_joined.connect(_on_player_joined)
	Net.player_left.connect(_on_player_left)


## Cosmetic set dressing for each zone, the scenery around them, and the shared
## outline. Local on every peer. The angles keep each ride's route clear of trees:
## Chefty leaves the store east, arrives at the lot from the west, and the van
## leaves the lot northwest and arrives at the border from the southeast.
func _dress() -> void:
	_StoreDressing.dress($StoreZone)
	_BorderDressing.dress($BorderZone)
	_Surroundings.dress($StoreZone, GRASS, 11, false, [0.0])
	_Surroundings.dress($LotZone, GRASS, 22, false, [PI * 0.75])
	_Neighborhood.dress($LotZone, 22)
	_Surroundings.dress($BorderZone, SAND, 33, false, [-PI * 0.25], "dirt")
	add_child(preload("res://levels/outline_pass.gd").new())
	# The clerk behind the counter. Local on every peer: nothing about it is shared.
	var clerk := preload("res://npcs/store_clerk.gd").new()
	clerk.name = "StoreClerk"
	$StoreZone.add_child(clerk)
	clerk.position = CLERK_SPOT


## An invisible wall around the pad, so a bump cannot walk or jump off it.
## Each zone's dressing shows the edge (fences, hedges, the street curb).
func _add_curb(zone: Node3D) -> void:
	var curb := StaticBody3D.new()
	curb.name = "Curb"
	zone.add_child(curb)
	var half := 20.0
	var thick := 0.8
	var height := 3.0
	var spans: Array[Dictionary] = [
		{"at": Vector3(0.0, height * 0.5, half), "size": Vector3(half * 2.0 + thick, height, thick)},
		{"at": Vector3(0.0, height * 0.5, -half), "size": Vector3(half * 2.0 + thick, height, thick)},
		{"at": Vector3(half, height * 0.5, 0.0), "size": Vector3(thick, height, half * 2.0)},
		{"at": Vector3(-half, height * 0.5, 0.0), "size": Vector3(thick, height, half * 2.0)},
	]
	for span: Dictionary in spans:
		var shape := BoxShape3D.new()
		shape.size = span["size"]
		var shape_node := CollisionShape3D.new()
		shape_node.shape = shape
		shape_node.position = span["at"]
		curb.add_child(shape_node)



## World position used when the host teleports a player into a zone.
func get_spawn_transform(zone: Net.Zone, spawn_marker: StringName, peer_id: int) -> Transform3D:
	var points := _spawn_points(zone)
	if spawn_marker != &"" and points.has_node(String(spawn_marker)):
		return points.get_node(String(spawn_marker)).global_transform
	var markers := points.get_children()
	if markers.is_empty():
		return points.global_transform
	# The first slot nobody is standing on, so nobody spawns inside someone else.
	# Peer ids are random, so a slot by id or by sorted order can collide.
	for slot: int in SPAWN_SLOTS_TO_TRY:
		var candidate := _slot_transform(markers, slot)
		if not _someone_near(candidate.origin, peer_id):
			return candidate
	return _slot_transform(markers, posmod(peer_id, markers.size()))


## Slot 0 is the first marker, then the next, then rows behind the markers.
func _slot_transform(markers: Array[Node], slot: int) -> Transform3D:
	var marker := (markers[slot % markers.size()] as Node3D).global_transform
	var row := floori(float(slot) / markers.size())
	marker.origin += marker.basis.z * SPAWN_SPACING * float(row)
	return marker


func _someone_near(point: Vector3, except_peer: int) -> bool:
	for node: Node in get_tree().get_nodes_in_group("players"):
		var body := node as Node3D
		if body == null or body.name == str(except_peer):
			continue
		if Vector2(body.global_position.x - point.x, body.global_position.z - point.z).length() < SPAWN_SPACING * 0.8:
			return true
	return false


func request_depart() -> void:
	if Net.is_host():
		_host_depart()
	else:
		_rpc_request_depart.rpc_id(1)


## Host only: the homeowner was paid. Settle the job and drive everyone home.
func finish_with_pay(paid: int, details: Dictionary = {}) -> void:
	if Net.is_host():
		_host_finish(float(paid), details)


func request_finish() -> void:
	if Net.is_host():
		_host_finish()
	else:
		_rpc_request_finish.rpc_id(1)


## Host only. Called by the truck when the path is done.
func on_ride_arrived(destination: int) -> void:
	if destination == Net.Zone.STORE:
		_free_lot()
	elif destination == Net.Zone.BORDER:
		var crossing := get_node_or_null("BorderReturn")
		var director := get_node_or_null("RunDirector")
		if crossing != null and director != null:
			crossing.call("begin", director.call("cohort_roster"), int(director.call("hazard_seed")))


func _load_job_lot() -> void:
	if %LotSlot.get_child_count() > 0:
		return
	var lot := JOB_LOT.instantiate()
	lot.name = "Lot%d" % Campaign.current_lot_index()
	%LotSlot.add_child(lot, true)
	Campaign.mark_job_open()
	var telemetry := get_tree().get_first_node_in_group("telemetry")
	if telemetry != null:
		telemetry.call("mark_job_start")
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


## Host only. paid is the homeowner's cash; without it, Campaign falls back to cleanup.
func _host_finish(paid: float = -1.0, details: Dictionary = {}) -> void:
	Campaign.finish_job(paid, details)
	var chefty := get_node_or_null("Rides/Chefty")
	if chefty != null:
		chefty.call("clear_bags")
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


func _on_node_added(node: Node) -> void:
	_SharedLook.call("restyle", node)


func _play_sfx(sound_name: String) -> void:
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play", sound_name)


func _on_player_joined(peer_id: int) -> void:
	_spawn_peer(peer_id)


func _on_player_left(peer_id: int) -> void:
	_PlayerDirector.despawn(%Players, peer_id)


func _spawn_bag(at: Vector3, units: int) -> void:
	_bag_serial += 1
	var bag := BAG_SCENE.instantiate()
	bag.name = "Bag%d" % _bag_serial
	bag.set("kind", "leaf_bag")
	bag.set("color", Color(0.72, 0.48, 0.18, 1))
	bag.set("label", "Leaf bag")
	var field := get_tree().get_first_node_in_group("leaf_field")
	bag.set("value", int(field.call("dollars_for", units)) if field != null else 0)
	_play_sfx("bag")
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
