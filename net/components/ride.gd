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
const _Strings = preload("res://ui/strings.gd")
const _BedLoad = preload("res://props/truck_bed_load.gd")
const _NearLabel = preload("res://ui/near_label.gd")
const _JunkBed = preload("res://net/components/junk_bed.gd")
const _CheftyPaint = preload("res://net/components/chefty_paint.gd")
const _StepDown = preload("res://net/components/step_down.gd")

var _riding: bool = false
## The bags drawn in the bed (props/truck_bed_load.gd), Chefty only.
var _bed_load: Node3D
## The junk in the bed for Rusty's (net/components/junk_bed.gd), Chefty only.
var _junk_bed: Node3D
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
var _vehicle_color: Color = Color(0.75, 0.22, 0.15)
## Chefty drives its one road both ways: true while it runs lot to store.
var _reverse: bool = false
## Where along the road it is parked between rides: 0 at the store, 1 at the lot.
var _parked_along: float = 0.0
## How far through this trip it was last drawn (0 to 1, eased), and a client's
## drive to the curb after the host's arrival: from where, how far (0 to 1; -1
## when not), over how long (s).
var _eased_now: float = 1.0
var _catchup_from: float = 0.0
var _catchup_t: float = -1.0
var _catchup_seconds: float = 0.5
## The last arrival's riders, in seat order (arrival_spots, the tests).
var _landed_riders: Array = []


func _ready() -> void:
	_build()
	# Chefty's riders, which player.gd seats every frame.
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
func _physics_process(delta: float) -> void:
	if _catchup_t >= 0.0:
		_step_catchup(delta)
		return
	if not _riding:
		return
	var duration := maxf(_duration, 0.1)
	var along := clampf((Net.server_time() - _start_time) / duration, 0.0, 1.0)
	# Chefty's legacy ride pulls away and pulls in (p1-arrive): at an even pace it
	# hit the curb at 125 m/s, so a client's clock a few ms off, or a rider's
	# replicated pose one update old, put that rider metres from where they got
	# off: every screen saw a pop as the riders stepped down. (The NICE BOYS' van
	# is net/run_events/shuttle.gd now, nice_boys:4.)
	var eased := smoothstep(0.0, 1.0, along)
	_eased_now = eased
	_place(1.0 - eased if _reverse else eased)
	if Net.is_host() and along >= 1.0:
		_arrive()


## A client whose truck was still short of the curb when the host said it had
## arrived (its clock trails the host's; a loaded machine's, by most of a second:
## 50 m in play, and the rider's hop became a 50 m teleport) drives the rest of
## the way first, easing into the curb, and only then lets its riders off.
func _step_catchup(delta: float) -> void:
	_catchup_t = minf(_catchup_t + delta / maxf(_catchup_seconds, 0.01), 1.0)
	var eased := lerpf(_catchup_from, 1.0, smoothstep(0.0, 1.0, _catchup_t))
	_eased_now = eased
	_place(1.0 - eased if _reverse else eased)
	if _catchup_t >= 1.0:
		_catchup_t = -1.0
		_land()


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


## The bed's space in the world (BED and the load's spots are in it).
func bed_transform() -> Transform3D:
	return _body.global_transform if _body != null else global_transform


## Where the bag in load spot index sits, in the world (props/truck_bed_load.gd).
func bed_slot(index: int) -> Transform3D:
	return bed_transform() * _BedLoad.slot(index)


## The bags drawn in the bed, or null (the van).
func bed_load() -> Node3D:
	return _bed_load


## Dollars' worth of bags loaded this job. What the homeowner pays for.
func bag_value() -> int:
	return _bag_value


## Host: a piece of junk lying in the bed is loaded (junk_bed.gd). False when full.
func accept_junk(prop: Node3D) -> bool:
	return _junk_bed != null and bool(_junk_bed.call("accept", prop))


func junk_count() -> int:
	return int(_junk_bed.call("count")) if _junk_bed != null else 0


## Host: the junk hops out over the tailgate, one piece at a time (at the store).
func unload_junk() -> void:
	if _junk_bed != null:
		_junk_bed.call("unload")


## Whether E at the tailgate may unload the junk now: parked, not on the road.
func junk_unload_allowed() -> bool:
	return not _riding


## Host only: the job is paid, so the truck's load is emptied.
func clear_bags() -> void:
	if Net.is_host():
		_rpc_bags.rpc(0, 0)


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
	# Every peer steps its own rider down from the seat list it still has
	# (_rpc_arrived), so the list is cleared there, not before.
	_rpc_arrived.rpc()
	if not Net.is_host():
		return
	# Into the zone where they stand: each rider hops down to their own spot by
	# the truck (_step_riders_down), never a spawn marker (crew-01: every rider
	# landed on the same one, inside each other).
	for peer_id: Variant in riders:
		Net.move_player_to_zone(int(peer_id), destination as Net.Zone, &"", false)
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
	# Chefty's name and load shrink and fade up close (ui/near_label.gd).
	var label: Label3D = _NearLabel.new() if name == "Chefty" else Label3D.new()
	label.name = "Label"
	label.text = "Chefty"
	label.font_size = 72
	label.outline_size = 12
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0.0, 3.4, 0.0)
	_body.add_child(label)
	_label = label
	if name == "Chefty":
		_bed_load = _BedLoad.new()
		_body.add_child(_bed_load)
		_junk_bed = _JunkBed.new()
		_body.add_child(_junk_bed)
		# The crew's paint job and decal (shops chunk 7).
		var paint := _CheftyPaint.new()
		paint.vehicle = self
		add_child(paint)
	var seats := Node3D.new()
	seats.name = "Seats"
	_body.add_child(seats)
	_seats = seats
	# On the bed's rails, facing out over the side (Constants.CHEFTY_RIDE_SEATS):
	# two riders stand back to back, not shoulder to shoulder in each other's view.
	for index: int in Balance.EXPECTED_TRAVELING_PARTY_SIZE:
		var seat := Marker3D.new()
		seat.name = "Seat%d" % index
		var place := index % Constants.CHEFTY_RIDE_SEATS.size()
		seat.position = Constants.CHEFTY_RIDE_SEATS[place]
		seat.rotation.y = Constants.CHEFTY_RIDE_SEAT_YAWS[place]
		seats.add_child(seat)
	_place(0.0)


## Chefty's paint and decal (shops chunk 7; chefty_paint.gd calls it only while
## it's parked): the look is built again; the seats, the bed's load and the
## label stay.
func apply_paint(color: Color, decal: String) -> void:
	_vehicle_color = color
	if _body != null:
		_Vehicles.build_truck(_body, {"color": color, "decal": decal})


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
	# Still driving the last trip's last meters here: that trip's riders get off first.
	if _catchup_t >= 0.0:
		_land()
	_eased_now = 0.0
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
		# It pulls away with the body, so riders hear it and the curb hears it go.
		sfx.call("play_on", "truck", _body if _body != null else self)


func _refresh_label() -> void:
	if _label == null:
		return
	_label.text = _Strings.UI["ride_chefty_label"] % [_bags, Constants.TRUCK_BAG_CAPACITY, _bag_value]
	if _bed_load != null:
		_bed_load.call("set_count", _bags)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_state() -> void:
	if Net.is_host():
		_rpc_parked.rpc_id(multiplayer.get_remote_sender_id(), _parked_along, _bags, _bag_value)
		if _junk_bed != null:
			_junk_bed.call("send_to", multiplayer.get_remote_sender_id())


## A late joiner learns where Chefty is parked and what it is carrying.
@rpc("authority", "call_remote", "reliable")
func _rpc_parked(along: float, count: int, value: int) -> void:
	_parked_along = along
	_bags = count
	_bag_value = value
	if _bed_load != null:
		_bed_load.call("sync_count", count)
	if not _riding:
		_place(along)
		if _body != null:
			_body.reset_physics_interpolation()
	_refresh_label()


@rpc("authority", "call_local", "reliable")
func _rpc_arrived() -> void:
	# Still short of the curb here: drive the rest first (_step_catchup).
	var left := (1.0 - _eased_now) * (_path.curve.get_baked_length() if _path != null and _path.curve != null else 0.0)
	if not Net.is_host() and _riding and _catchup_t < 0.0 and left > Constants.CHEFTY_RIDE_CATCHUP_MIN_METERS:
		_catchup_from = _eased_now
		_catchup_t = 0.0
		_catchup_seconds = clampf(left / Constants.CHEFTY_RIDE_CATCHUP_SPEED, Constants.CHEFTY_RIDE_CATCHUP_SECONDS.x, Constants.CHEFTY_RIDE_CATCHUP_SECONDS.y)
		return
	_land()


## Every peer: the truck's parked at the end of the trip, and its riders get off.
func _land() -> void:
	_catchup_t = -1.0
	_riding = false
	_parked_along = 0.0 if _reverse else 1.0
	_eased_now = 1.0
	# A client's last tick can fall just short of the end (its clock estimate
	# trails the host's), and a dev scenario that skips the ride moves only the
	# host's start time (net/dev/scenarios.gd): park where the trip ends either way.
	_place(_parked_along)
	if _body != null:
		_body.reset_physics_interpolation()
	var riders: Array = _riders.duplicate()
	_riders.clear()
	# Only this ride's riders get off: anyone seated elsewhere (the Shuttle, the
	# drivable Chefty) stays put.
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.has_method("clear_riding") and node.get("_ride") == self:
			node.call("clear_riding")
	_step_riders_down(riders)
	_refresh_label()


## Every peer, on arrival: each rider's landing spot from their seat (bed left,
## bed right, the tailgate, the cab), worked out the same way everywhere
## (net/components/step_down.gd), and this peer's own rider hops down to theirs.
## Everyone else sees that hop through the synchronizer.
func _step_riders_down(riders: Array) -> void:
	_landed_riders = riders.duplicate()
	var local_id := Net.local_peer_id()
	var mine := riders.find(local_id)
	if mine < 0 or _body == null:
		return
	var spots := arrival_spots(riders)
	var seat := seat_transform(mine).origin
	# Over the rail or the tailgate, never through it (step_down.gd hop_path).
	var path := _StepDown.hop_path(_body.global_transform, seat, spots[mine].origin, false)
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(local_id) and node.has_method("step_down_to"):
			# One after another, by seat, so two hops never cross in the air.
			node.call("step_down_to", spots[mine], float(mine) * Constants.STEP_DOWN_STAGGER, path)


## Every peer: where each of riders (in seat order) lands by the truck where it's
## parked, worked out from this peer's own world (step_down.gd slots). Each peer
## steps only its own rider down, so the peers have to agree on all of them, or
## two riders could take one spot; --arrive-test checks they do.
func arrival_spots(riders: Array) -> Array[Transform3D]:
	if _body == null:
		return []
	var own: Array = []
	for index: int in riders.size():
		own.append(Constants.CHEFTY_STEP_DOWN_SLOTS[index % Constants.CHEFTY_STEP_DOWN_SLOTS.size()])
	var world := get_tree().get_first_node_in_group("world")
	var look_at := _body.global_position + (-_body.global_basis.z) * Constants.STEP_DOWN_LOOK_AHEAD
	var props: Array = []
	if world != null and world.has_method("arrival_look_point"):
		look_at = world.call("arrival_look_point", _destination)
		props = world.call("arrival_obstacles", _destination, _body.global_position, Constants.STEP_DOWN_PROP_REACH)
	return _StepDown.slots(_body.get_world_3d().direct_space_state, _StepDown.flat(_body.global_transform), own, look_at, [], props)


## The riders of the last arrival, in seat order (for the tests).
func landed_riders() -> Array:
	return _landed_riders.duplicate()


@rpc("authority", "call_local", "reliable")
func _rpc_bags(count: int, value: int) -> void:
	if value > _bag_value and _bed_load != null:
		_bed_load.call("on_value_added", value - _bag_value)
	elif value > _bag_value and _body != null:
		_MoneyPopup.pop(get_tree(), _body.global_position + Vector3(0.0, 3.0, 0.0), value - _bag_value)
	_bags = count
	_bag_value = value
	_refresh_label()
