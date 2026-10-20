extends Node3D

## Authority: host for who sits and when the ride starts.
## The truck's place on the path is a pure function of the shared clock, so it is not replicated per frame.

# TODO(balance): add the truck ride duration to the workbook.
const RIDE_DURATION_SECONDS: float = 8.0
## Where Chefty parks at the lot: the curb in front of the yard (world space; the lot zone is at x 1000).
const LOT_PARK := Vector3(1007.0, 0.0, 24.6)
## Chefty's bed, in its own space: bags that land in here are loaded.
const BED := AABB(Vector3(-1.05, 0.9, -1.2), Vector3(2.1, 1.3, 3.85))
const _Vehicles = preload("res://props/vehicles.gd")
const _MoneyPopup = preload("res://ui/money_popup.gd")

var _riding: bool = false
var _start_time: float = 0.0
var _duration: float = RIDE_DURATION_SECONDS
var _destination: int = 0
var _riders: Array = []
var _bags: int = 0
var _bag_value: int = 0
var _path: Path3D
var _body: Node3D
var _seats: Node3D
var _label: Label3D
var _vehicle_name: String = "Chefty"
var _vehicle_color: Color = Color(0.75, 0.22, 0.15)
## Chefty drives its one road both ways: true while it runs lot to store.
var _reverse: bool = false
## Where along the road it is parked between rides: 0 at the store, 1 at the lot.
var _parked_along: float = 0.0


func _ready() -> void:
	_build()
	# Chefty and the van both carry riders, which player.gd seats every frame.
	add_to_group("rides")
	if name == "Chefty":
		add_to_group("chefty")
		_refresh_label()
		# A session started on the lot (--start-zone=lot) finds Chefty parked there.
		if Net.is_host() and Net.start_zone() == Net.Zone.LOT:
			_parked_along = 1.0
	_place(_parked_along)
	if not Net.is_host() and multiplayer.multiplayer_peer != null and is_in_group("chefty"):
		_rpc_request_state.rpc_id(1)


## Moves on physics ticks, so physics interpolation smooths the vehicle and its
## riders together.
func _physics_process(_delta: float) -> void:
	if not _riding:
		return
	var duration := maxf(_duration, 0.1)
	var along := clampf((Net.server_time() - _start_time) / duration, 0.0, 1.0)
	_place(1.0 - along if _reverse else along)
	if Net.is_host() and along >= 1.0:
		_arrive()


## Host only. Seat these peers and drive to a zone.
func depart(peer_ids: Array, destination_zone: int) -> void:
	if not Net.is_host() or _riding or peer_ids.is_empty():
		return
	_rpc_depart.rpc(Net.server_time(), peer_ids, destination_zone, RIDE_DURATION_SECONDS)
	for peer_id: Variant in peer_ids:
		Net.move_player_to_zone(int(peer_id), Net.Zone.TRANSIT)


func is_riding() -> bool:
	return _riding


## The seat this peer rides in right now, or -1. Every peer knows the riders
## from the departure message, so every peer can place every rider.
func seat_of(peer_id: int) -> int:
	if not _riding:
		return -1
	for index: int in _riders.size():
		if int(_riders[index]) == peer_id:
			return index
	return -1


func bag_count() -> int:
	return _bags


func occupied_count() -> int:
	return _riders.size()


func drop_rider(peer_id: int) -> void:
	var kept: Array = []
	for entry: Variant in _riders:
		if int(entry) != peer_id:
			kept.append(int(entry))
	_riders = kept
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id) and node.has_method("clear_riding"):
			node.call("clear_riding")
	_refresh_label()


func body_position() -> Vector3:
	if _body == null:
		return global_position
	return _body.global_position


## Host only. Pulls bags off a thrown wheelbarrow, up to the truck's cap.
## Host only. Load bags worth value dollars in all; returns how many fit.
func accept_bags(count: int, value: int = 0) -> int:
	if not Net.is_host() or count <= 0:
		return 0
	var room := Constants.TRUCK_BAG_CAPACITY - _bags
	var taken := mini(count, maxi(room, 0))
	if taken <= 0:
		_refresh_label()
		return 0
	_bags += taken
	_bag_value += int(round(float(value) * float(taken) / float(count)))
	_rpc_bags.rpc(_bags, _bag_value)
	return taken


## True when a point is inside Chefty's open bed.
func in_bed(point: Vector3) -> bool:
	if _body == null or not is_in_group("chefty"):
		return false
	return BED.has_point(_body.global_transform.affine_inverse() * point)


## Dollars' worth of bags loaded this job. What the homeowner pays for.
func bag_value() -> int:
	return _bag_value


## Host only: the job is paid, so the truck's load is emptied.
func clear_bags() -> void:
	if Net.is_host():
		_rpc_bags.rpc(0, 0)


## Called on every peer before the van departs. Chefty builds itself in _ready.
func setup_as_van(from_point: Vector3, to_point: Vector3) -> void:
	add_to_group("vans")
	_vehicle_name = "Van"
	_vehicle_color = Color(0.16, 0.17, 0.2)
	if _body != null:
		var truck := _body.get_node_or_null("TruckLook")
		if truck != null:
			truck.free()
		_Vehicles.build_van(_body, _vehicle_color)
		if _label != null:
			_label.position.y = 3.9
	var curve := Curve3D.new()
	curve.add_point(from_point)
	curve.add_point((from_point + to_point) * 0.5 + Vector3(0.0, 3.0, 0.0))
	curve.add_point(to_point)
	_path.curve = curve
	while _seats != null and _seats.get_child_count() < Constants.MAX_PLAYERS:
		var seat := Marker3D.new()
		seat.name = "Seat%d" % _seats.get_child_count()
		var index := _seats.get_child_count()
		seat.position = Vector3(-0.5 + float(index % 2), 1.0, -1.2 + float(index / 2))
		_seats.add_child(seat)
	_place(0.0)
	_refresh_label()


func seat_count() -> int:
	if _seats == null:
		return 0
	return _seats.get_child_count()


func seat_transform(index: int) -> Transform3D:
	if _seats == null or _seats.get_child_count() == 0:
		return global_transform
	var seat := _seats.get_child(clampi(index, 0, _seats.get_child_count() - 1)) as Node3D
	return seat.global_transform


func _arrive() -> void:
	_riding = false
	_parked_along = 0.0 if _reverse else 1.0
	var riders: Array = _riders.duplicate()
	var destination := _destination
	_riders.clear()
	_rpc_arrived.rpc()
	if not Net.is_host():
		return
	for peer_id: Variant in riders:
		Net.move_player_to_zone(int(peer_id), destination as Net.Zone)
	var world := get_tree().get_first_node_in_group("world")
	if world != null and world.has_method("on_ride_arrived"):
		world.call("on_ride_arrived", destination)


func _place(along: float) -> void:
	if _path == null or _path.curve == null or _body == null:
		return
	var length := _path.curve.get_baked_length()
	var on_path := _path.curve.sample_baked_with_rotation(along * length, true, true)
	# Driving back along the same road it faces the way it's going, not backward.
	if _reverse:
		on_path.basis = on_path.basis.rotated(on_path.basis.y.normalized(), PI)
	_body.global_transform = _path.global_transform * on_path


func _build() -> void:
	_path = Path3D.new()
	_path.name = "Path"
	# Out of the store lot, then down the lot's street (levels/dressing/neighborhood.gd)
	# to park at the curb in the near lane, in front of the yard: the driveway
	# stays clear for work (Taylan, 2026-10-20).
	var curve := Curve3D.new()
	# The path runs along the ground: the truck's wheels touch down at its body's origin.
	curve.add_point(Vector3(10.0, 0.0, 8.0))
	curve.add_point(Vector3(500.0, 0.0, 20.0))
	curve.add_point(Vector3(930.0, 0.0, LOT_PARK.z))
	curve.add_point(LOT_PARK)
	_path.curve = curve
	add_child(_path)
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	# The look lives in props/vehicles.gd. Riders sit where they can be seen.
	_Vehicles.build_truck(_body, _vehicle_color)
	var label := Label3D.new()
	label.name = "Label"
	label.text = "Chefty"
	label.font_size = 72
	label.outline_size = 12
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0.0, 3.4, 0.0)
	_body.add_child(label)
	_label = label
	var seats := Node3D.new()
	seats.name = "Seats"
	_body.add_child(seats)
	_seats = seats
	for index: int in Balance.EXPECTED_TRAVELING_PARTY_SIZE:
		var seat := Marker3D.new()
		seat.name = "Seat%d" % index
		seat.position = Vector3(-0.5 + float(index % 2), 1.0, -1.2 + float(index / 2))
		seats.add_child(seat)
	_place(0.0)


func _seat_local_player() -> void:
	var local_id := Net.local_peer_id()
	for index: int in _riders.size():
		if int(_riders[index]) != local_id:
			continue
		for node: Node in get_tree().get_nodes_in_group("players"):
			if node.name == str(local_id) and node.has_method("set_riding"):
				node.call("set_riding", self, index)


@rpc("authority", "call_local", "reliable")
func _rpc_depart(start_time: float, riders: Array, destination_zone: int, duration: float) -> void:
	_start_time = start_time
	_duration = duration
	_destination = destination_zone
	_reverse = is_in_group("chefty") and destination_zone == Net.Zone.STORE
	_riders = riders
	_riding = true
	if _body != null:
		_body.reset_physics_interpolation()
	_seat_local_player()
	_refresh_label()
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play", "van" if is_in_group("vans") else "truck")


func _refresh_label() -> void:
	if _label == null:
		return
	if is_in_group("vans"):
		var lines: PackedStringArray = PackedStringArray(["Van"])
		for peer_id: Variant in _riders:
			var shown := Net.player_name(int(peer_id))
			lines.append(shown if shown != "" else "Player %d" % int(peer_id))
		_label.text = "\n".join(lines)
		return
	var full := " full" if _bags >= Constants.TRUCK_BAG_CAPACITY else ""
	_label.text = "Chefty\n%d/%d bags  $%d%s" % [_bags, Constants.TRUCK_BAG_CAPACITY, _bag_value, full]


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_state() -> void:
	if Net.is_host():
		_rpc_parked.rpc_id(multiplayer.get_remote_sender_id(), _parked_along, _bags, _bag_value)


## A late joiner learns where Chefty is parked and what it is carrying.
@rpc("authority", "call_remote", "reliable")
func _rpc_parked(along: float, count: int, value: int) -> void:
	_parked_along = along
	_bags = count
	_bag_value = value
	if not _riding:
		_place(along)
		if _body != null:
			_body.reset_physics_interpolation()
	_refresh_label()


@rpc("authority", "call_local", "reliable")
func _rpc_arrived() -> void:
	_riding = false
	_parked_along = 0.0 if _reverse else 1.0
	_riders.clear()
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.has_method("clear_riding"):
			node.call("clear_riding")
	_refresh_label()


@rpc("authority", "call_local", "reliable")
func _rpc_bags(count: int, value: int) -> void:
	if value > _bag_value and _body != null:
		_MoneyPopup.pop(get_tree(), _body.global_position + Vector3(0.0, 3.0, 0.0), value - _bag_value)
	_bags = count
	_bag_value = value
	_refresh_label()
