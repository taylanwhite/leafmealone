extends Node3D

## Authority: host. The drivable Chefty in the connected town (World/Rides/Chefty,
## made in code on every peer by levels/world.gd; ride.gd stays the legacy one).
## docs/DECISIONS.md "Chefty is a host-simulated arcade vehicle", docs/NETCODE.md
## "Rides".
##
## The host simulates it with VehicleSim (net/components/vehicle_sim.gd) from
## the driver's input stream and sends a pose snapshot 30 times a second. The
## driver's own peer predicts: it runs the same sim on its own inputs right away,
## and on every snapshot puts the chassis where the host had it after the last
## input the host used (the ack), replays the inputs since, and fades the
## difference out of what it draws. Everyone else draws the snapshots 100 ms
## behind (vehicle_view.gd). Who sits where is the host's: 8 seats (the driver,
## shotgun, six in the bed), sent whole with _rpc_seats whenever it changes, and
## every peer seats every rider from it on physics ticks (player.gd), like the
## legacy ride. The ride contract (seat_of, seat_transform, depart, the bags, ...)
## is the same as ride.gd's, so the world, props, hires and UI don't care which
## Chefty they have.
##
## Nodes: Chassis (a CharacterBody3D on Constants.VEHICLE_LAYER, what the sim
## moves and what hits walls), Body (the rendered pose: TruckLook with the cab and
## the SteeringWheel, Seats x8, Label), View (vehicle_view.gd). Players never
## touch Chassis; they bump TruckLook's Solid on their own peer.

signal crashed(strength: float, at: Vector3)
signal parked(at: Vector3)
signal driver_changed(peer_id: int)

const _Vehicles = preload("res://props/vehicles.gd")
const _VehicleView = preload("res://net/components/vehicle_view.gd")
const _MoneyPopup = preload("res://ui/money_popup.gd")
const _Strings = preload("res://ui/strings.gd")
const _Sfx = preload("res://audio/sfx.gd")
const _SoundBank = preload("res://audio/sound_bank.gd")
## Chefty's bed, in its own space: bags that land in here are loaded (as ride.gd).
const BED := AABB(Vector3(-1.05, 0.9, -1.2), Vector3(2.1, 1.3, 3.85))
const COLOR := Color(0.75, 0.22, 0.15)
## Seat kinds for request_enter: the driver's seat, shotgun, the bed, or whichever
## door is nearest.
enum Kind { DRIVER = 0, SHOTGUN = 1, BED = 2, NEAREST = -1 }
const SEAT_DRIVER: int = 0
const SEAT_SHOTGUN: int = 1
## _rpc_input flags.
const FLAG_HANDBRAKE: int = 1
const FLAG_HORN: int = 2
## How many recent predicted positions the driver keeps (about 2 s of ticks).
const PREDICTION_HISTORY: int = 150

var _riders := PackedInt32Array()
var _chassis: CharacterBody3D
var _body: Node3D
var _look: Node3D
var _seats: Node3D
var _label: Label3D
var _view: Node
var _state: Dictionary = {}
var _params: Dictionary = {}
var _dents: int = 0
var _tick: int = 0
## Host: the driver's queued inputs [{seq, throttle, steer, flags}], the one
## held while none arrive, when the last one came, and the last seq used.
var _queue: Array[Dictionary] = []
var _held: Dictionary = {}
var _input_msec: int = 0
var _ack: int = 0
## The horn, as the host has it (every peer gets it with _rpc_horn), and the
## changes seen here, for the test.
var _horn: bool = false
var _horn_log: Array[bool] = []
## Host: the peers whose Chefty is ready for snapshots.
var _watchers: Dictionary = {}
## The driver's peer: its input counter, the inputs the host hasn't used yet,
## where it predicted Chefty after each, and the drawn pose's leftover error.
var _seq: int = 0
var _pending: Array[Dictionary] = []
var _predicted: Dictionary = {}
var _offset := Vector3.ZERO
var _yaw_offset: float = 0.0
var _last_ack: int = 0
var _prediction_error_max: float = 0.0
var _corrections: int = 0
## This peer's own seated player's controls, set each tick by player/seated.gd.
var _local_input: Dictionary = {}
## Tests (_rpc_dev_script): scripted inputs that play through the normal path.
var _dev_steps: Array = []
var _dev_left: float = 0.0
var _dev_input: Dictionary = {}
## Non-drivers: the last drawn velocity, for the lean.
var _view_vel := Vector3.ZERO
var _view_state: Dictionary = {}
## The legacy-style trip depart() makes until the autopilot exists (driving C2):
## {start, seconds, zone, riders}. Empty when not on one.
var _hop: Dictionary = {}
## Bags: this job's (unpaid; what the homeowner pays for) and paid ones still in
## the bed (driving chunk J's mulch; always 0 for now).
var _job_bags: int = 0
var _job_value: int = 0
var _spent_bags: int = 0
var _was_moving: bool = false
## Sound, built when nothing better is attached (audio/vehicle_sound.gd, audio:7).
var _engine: AudioStreamPlayer3D
var _skid: AudioStreamPlayer3D
var _horn_player: AudioStreamPlayer3D
var _horn_held: float = 0.0


func _ready() -> void:
	add_to_group("rides")
	add_to_group("chefty")
	add_to_group("vehicles")
	_riders.resize(Constants.CHEFTY_SEATS)
	_state = VehicleSim.new_state(Constants.CHEFTY_PARK_YAW)
	_view_state = VehicleSim.new_state(Constants.CHEFTY_PARK_YAW)
	_build()
	_place(Constants.CHEFTY_PARK_SPOT, Constants.CHEFTY_PARK_YAW)
	_refresh_params()
	_refresh_label()
	_refresh_role()
	if Net.is_host():
		if not Net.player_left.is_connected(_on_player_left):
			Net.player_left.connect(_on_player_left)
	elif multiplayer.multiplayer_peer != null:
		_rpc_request_state.rpc_id(1)


func _build() -> void:
	_chassis = CharacterBody3D.new()
	_chassis.name = "Chassis"
	_chassis.collision_layer = Constants.VEHICLE_LAYER
	_chassis.collision_mask = 1 | Constants.VEHICLE_LAYER
	_chassis.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	_chassis.wall_min_slide_angle = 0.0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Constants.CHEFTY_CHASSIS_SIZE
	shape.shape = box
	shape.position = Constants.CHEFTY_CHASSIS_CENTER
	_chassis.add_child(shape)
	add_child(_chassis)
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	_look = _Vehicles.build_truck(_body, {"color": COLOR, "interior": true})
	var solid := _look.get_node_or_null("Solid") as PhysicsBody3D
	if solid != null:
		_chassis.add_collision_exception_with(solid)
	var label := Label3D.new()
	label.name = "Label"
	label.font_size = 72
	label.outline_size = 12
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0.0, 3.4, 0.0)
	_body.add_child(label)
	_label = label
	_seats = Node3D.new()
	_seats.name = "Seats"
	_body.add_child(_seats)
	for index: int in Constants.CHEFTY_SEATS:
		var seat := Marker3D.new()
		seat.name = "Seat%d" % index
		seat.position = _Vehicles.CHEFTY_SEATS[index]
		_seats.add_child(seat)
	_view = _VehicleView.new()
	_view.name = "View"
	_view.set("vehicle", self)
	add_child(_view)
	_attach_sound()


## The sim's numbers: Chefty's, less its dents, plus the tune-up perk.
func _refresh_params() -> void:
	_params = VehicleSim.chefty_params(_dents, Campaign.has_perk("chefty_tuneup"))
	var solid := _look.get_node_or_null("Solid") as CollisionObject3D if _look != null else null
	_params["exclude"] = [solid.get_rid()] if solid != null else []


func _place(at: Vector3, yaw: float) -> void:
	_chassis.global_position = at
	_chassis.global_rotation = Vector3(0.0, yaw, 0.0)
	_state["yaw"] = yaw
	_state["vel"] = Vector3.ZERO
	_state["yaw_rate"] = 0.0
	_state["vy"] = 0.0
	_offset = Vector3.ZERO
	_yaw_offset = 0.0
	_body.global_transform = VehicleSim.body_transform(at, _state)
	_body.reset_physics_interpolation()
	_chassis.reset_physics_interpolation()


# ---------------------------------------------------------------- the ride contract

## On a trip depart() started (until the autopilot, a hop; driving C2).
func is_riding() -> bool:
	return not _hop.is_empty()


func seat_of(peer_id: int) -> int:
	if peer_id <= 0:
		return -1
	for index: int in _riders.size():
		if _riders[index] == peer_id:
			return index
	return -1


func seat_transform(index: int) -> Transform3D:
	if _seats == null or _seats.get_child_count() == 0:
		return global_transform
	return (_seats.get_child(clampi(index, 0, _seats.get_child_count() - 1)) as Node3D).global_transform


func seat_count() -> int:
	return Constants.CHEFTY_SEATS


## Whether a seat is in the cab (the riders there sit, player/cartoon_body.gd sit()).
func is_cab_seat(index: int) -> bool:
	return index >= 0 and index < _Vehicles.CHEFTY_CAB_SEATS


func occupied_count() -> int:
	var count := 0
	for peer_id: int in _riders:
		if peer_id != 0:
			count += 1
	return count


## The peers in the seats, in seat order, 0 for an empty seat.
func riders() -> PackedInt32Array:
	return _riders.duplicate()


## The driver's peer id, or 0.
func driver() -> int:
	return _riders[SEAT_DRIVER] if _riders.size() > 0 else 0


## Host: take this peer out of their seat (they left, or got captured).
func drop_rider(peer_id: int) -> void:
	if not Net.is_host():
		return
	var seat := seat_of(peer_id)
	if seat < 0:
		return
	_riders[seat] = 0
	_send_seats()


func body_position() -> Vector3:
	return _body.global_position if _body != null else global_position


## The rendered Chefty's pose (what you see, and what riders sit on).
func body_transform() -> Transform3D:
	return _body.global_transform if _body != null else global_transform


## Chefty's speed in m/s as this peer has it.
func speed() -> float:
	var vel: Vector3 = _view_vel if _uses_view() else _state["vel"]
	return Vector2(vel.x, vel.z).length()


func is_moving() -> bool:
	return speed() > Constants.CHEFTY_PARK_SPEED


func yaw() -> float:
	return _body.global_rotation.y if _body != null else 0.0


## Where a skateboarder hangs on behind (driving G2): behind the tailgate.
func tow_point() -> Transform3D:
	return body_transform() * Transform3D(Basis.IDENTITY, _Vehicles.CHEFTY_TAILGATE + Vector3(0.0, 0.0, 0.6))


## Host only. Load bags worth value dollars in all; returns how many fit.
func accept_bags(count: int, value: int = 0) -> int:
	if not Net.is_host() or count <= 0:
		return 0
	var room := Constants.TRUCK_BAG_CAPACITY - _job_bags - _spent_bags
	var taken := mini(count, maxi(room, 0))
	if taken <= 0:
		_refresh_label()
		return 0
	_job_bags += taken
	_job_value += int(round(float(value) * float(taken) / float(count)))
	_rpc_bags.rpc(_job_bags, _job_value, _spent_bags)
	return taken


## True when a point is inside Chefty's open bed.
func in_bed(point: Vector3) -> bool:
	if _body == null:
		return false
	return BED.has_point(_body.global_transform.affine_inverse() * point)


## Dollars' worth of this job's bags. What the homeowner pays for.
func bag_value() -> int:
	return _job_value


func bag_count() -> int:
	return _job_bags + _spent_bags


## Host only: the job is paid, so its bags come off the truck.
func clear_bags() -> void:
	if Net.is_host():
		_rpc_bags.rpc(0, 0, _spent_bags)


## Host: the job's paid (world.gd, driving chunk D keeps the yard and the truck).
func on_job_paid() -> void:
	clear_bags()


## Host only. Seat these peers and take them to a zone. Until the autopilot
## (driving C2) it's a hop: they sit for CHEFTY_HOP_SECONDS, then Chefty parks at
## the stop (the yard's curb or the TruckPad) and they arrive like the legacy ride.
func depart(peer_ids: Array, destination_zone: int) -> void:
	if not Net.is_host() or is_riding() or peer_ids.is_empty():
		return
	for peer_id: Variant in peer_ids:
		var id := int(peer_id)
		if seat_of(id) >= 0:
			continue
		var free := _free_seat(range(SEAT_SHOTGUN, Constants.CHEFTY_SEATS))
		if free < 0:
			free = _free_seat([SEAT_DRIVER])
		if free < 0:
			break
		_riders[free] = id
		_stow(id)
	var riding: Array[int] = []
	for id: int in _riders:
		if id != 0:
			riding.append(id)
	_send_seats()
	_rpc_hop.rpc(Net.server_time(), Constants.CHEFTY_HOP_SECONDS, destination_zone)
	for id: int in riding:
		Net.move_player_to_zone(id, Net.Zone.TRANSIT)


# ---------------------------------------------------------------- getting in and out

## Ask the host for a seat (kind is a Kind).
func request_enter(kind: int) -> void:
	if Net.is_host():
		_handle_enter(Net.local_peer_id(), kind)
	else:
		_rpc_request_enter.rpc_id(1, kind)


func request_exit() -> void:
	if Net.is_host():
		_handle_exit(Net.local_peer_id())
	else:
		_rpc_request_exit.rpc_id(1)


## F in a seat: the driver and shotgun trade places (or slide over), a bed rider
## moves to the next free bed seat.
func request_swap() -> void:
	if Net.is_host():
		_handle_swap(Net.local_peer_id())
	else:
		_rpc_request_swap.rpc_id(1)


## This peer's seated player's controls for this tick (player/seated.gd):
## {throttle, steer, handbrake, horn}. Only the driver's are used.
func local_drive_input(input: Dictionary) -> void:
	_local_input = input


## What E would do near Chefty for this player, for the interaction prompt:
## {text, at, kind} or {}. Nothing while seated (the drive HUD shows the keys).
func prompt_for(player: Node3D) -> Dictionary:
	if player == null or seat_of(player.name.to_int()) >= 0 or is_riding():
		return {}
	var best := _entry_for(player.global_position, Kind.NEAREST)
	if best.is_empty():
		return {}
	var key := {Kind.DRIVER: "prompt_drive", Kind.SHOTGUN: "prompt_ride_shotgun", Kind.BED: "prompt_ride_bed"}.get(int(best["kind"]), "prompt_ride_bed") as String
	return {"text": _Strings.UI[key], "at": (best["at"] as Vector3) + Vector3(0.0, 1.7, 0.0), "kind": int(best["kind"])}


## The nearest way in for someone standing at from, of this kind (or the nearest
## of any kind with a free seat): {kind, at}, or {} with none in reach.
func _entry_for(from: Vector3, kind: int) -> Dictionary:
	var entries: Array = [
		[Kind.DRIVER, _Vehicles.CHEFTY_DRIVER_DOOR],
		[Kind.SHOTGUN, _Vehicles.CHEFTY_SHOTGUN_DOOR],
		[Kind.BED, _Vehicles.CHEFTY_TAILGATE],
	]
	var best: Dictionary = {}
	var best_distance := Constants.CHEFTY_ENTER_RADIUS
	for entry: Array in entries:
		var entry_kind := int(entry[0])
		if kind != Kind.NEAREST and entry_kind != kind:
			continue
		if _seat_for_kind(entry_kind) < 0:
			continue
		var at := body_transform() * (entry[1] as Vector3)
		var distance := Vector2(at.x - from.x, at.z - from.z).length()
		if distance <= best_distance:
			best_distance = distance
			best = {"kind": entry_kind, "at": at}
	return best


## The free seat a kind of entry gets, or -1 (the driver's only while slow).
func _seat_for_kind(kind: int) -> int:
	match kind:
		Kind.DRIVER:
			if speed() >= Constants.CHEFTY_ENTER_MAX_SPEED:
				return -1
			return _free_seat([SEAT_DRIVER])
		Kind.SHOTGUN:
			return _free_seat([SEAT_SHOTGUN])
		_:
			return _free_seat(range(_Vehicles.CHEFTY_CAB_SEATS, Constants.CHEFTY_SEATS))


func _free_seat(indices: Array) -> int:
	for index: Variant in indices:
		if _riders[int(index)] == 0:
			return int(index)
	return -1


func _handle_enter(peer_id: int, kind: int) -> void:
	if seat_of(peer_id) >= 0 or is_riding():
		return
	var player := _player(peer_id)
	if player == null or not _may_board(player, peer_id):
		return
	var entry := _entry_for(player.global_position, kind)
	if entry.is_empty():
		return
	var seat := _seat_for_kind(int(entry["kind"]))
	if seat < 0:
		return
	_riders[seat] = peer_id
	_stow(peer_id)
	_send_seats()


## Not captured, carried, carrying someone, hiding, asleep, or flying.
func _may_board(player: Node3D, peer_id: int) -> bool:
	var director := get_tree().get_first_node_in_group("run_director")
	if director != null and bool(director.call("is_captured", peer_id)):
		return false
	if int(player.get("carried_by")) != 0 or int(player.get("carrying")) != 0 or bool(player.get("thrown")):
		return false
	if bool(player.call("is_hidden")) or bool(player.call("is_sleeping")):
		return false
	var zone := Net.player_zone(peer_id)
	return zone != Net.Zone.BORDER and zone != Net.Zone.TRANSIT


## Hands away for the ride (critic C23): a pocket item back in its pocket, a big
## one set down.
func _stow(peer_id: int) -> void:
	var hotbar := get_tree().get_first_node_in_group("hotbar")
	if hotbar != null and hotbar.has_method("host_stow_hands"):
		hotbar.call("host_stow_hands", peer_id)


func _handle_exit(peer_id: int) -> void:
	var seat := seat_of(peer_id)
	if seat < 0 or is_riding():
		return
	var player := _player(peer_id)
	var moving: Vector3 = _state["vel"]
	_riders[seat] = 0
	_send_seats()
	if player == null:
		return
	var spot := _exit_spot(seat)
	var facing := yaw()
	player.call("send_teleport", Transform3D(Basis(Vector3.UP, facing), spot))
	if Vector2(moving.x, moving.z).length() > Constants.CHEFTY_EXIT_MAX_SPEED:
		host_eject(peer_id, moving * Constants.CHEFTY_BAIL_SHARE + Vector3.UP * 3.0)
	_note_zone(peer_id, spot)


## Host: fling a peer out (a bail, later a crash): they fly with velocity and land
## the way a thrown player does (player.gd set_thrown).
func host_eject(peer_id: int, velocity: Vector3) -> void:
	if not Net.is_host():
		return
	if seat_of(peer_id) >= 0:
		_riders[seat_of(peer_id)] = 0
		_send_seats()
	var player := _player(peer_id)
	if player == null:
		return
	if peer_id == Net.local_peer_id():
		player.call("set_thrown", velocity, 0)
	else:
		player.rpc_id(peer_id, &"_rpc_thrown", velocity, 0)


## In the connected town zones follow where people are (driving chunk D's
## ZoneTracker does it for everyone; until then, getting out of Chefty does).
func _note_zone(peer_id: int, at: Vector3) -> void:
	var world := get_tree().get_first_node_in_group("world")
	if world == null or not bool(world.call("is_town_map")):
		return
	var zone := Net.Zone.TOWN
	if Constants.STORE_AREA.has_point(Vector2(at.x, at.z)):
		zone = Net.Zone.STORE
	else:
		var lot_zone := world.get_node_or_null("LotZone") as Node3D
		var slot := world.get_node_or_null("%LotSlot")
		if lot_zone != null and slot != null and slot.get_child_count() > 0:
			var local := lot_zone.global_transform.affine_inverse() * at
			var rect: Rect2 = Constants.PAD_RECTS.get("LotZone", Rect2(-20.0, -20.0, 40.0, 40.0))
			if rect.has_point(Vector2(local.x, local.z)):
				zone = Net.Zone.LOT
	if Net.player_zone(peer_id) != zone:
		Net.set_player_zone(peer_id, zone)


## A clear spot to stand by the seat's door (or the bed's side), else the other
## side, else behind the tailgate, else on the roof.
func _exit_spot(seat: int) -> Vector3:
	var side := -1.0 if (seat == SEAT_DRIVER or (seat >= _Vehicles.CHEFTY_CAB_SEATS and _Vehicles.CHEFTY_SEATS[seat].x < 0.0)) else 1.0
	var z := _Vehicles.CHEFTY_SEATS[seat].z
	var flat := Transform3D(Basis(Vector3.UP, yaw()), Vector3(body_position().x, _chassis.global_position.y, body_position().z))
	var candidates: Array[Vector3] = [
		flat * Vector3(side * 1.9, 0.1, z),
		flat * Vector3(-side * 1.9, 0.1, z),
		flat * Vector3(0.0, 0.1, 3.6),
		flat * Vector3(0.0, 2.6, -2.0),
	]
	for candidate: Vector3 in candidates:
		if _clear_at(candidate):
			return candidate
	return candidates[0]


func _clear_at(at: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.6
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3(0.0, 0.95, 0.0))
	query.collision_mask = 1
	var exclude: Array[RID] = [_chassis.get_rid()]
	for rid: RID in _params.get("exclude", []):
		exclude.append(rid)
	query.exclude = exclude
	return space.intersect_shape(query, 1).is_empty()


func _handle_swap(peer_id: int) -> void:
	var seat := seat_of(peer_id)
	if seat < 0 or is_riding():
		return
	if seat < _Vehicles.CHEFTY_CAB_SEATS:
		if speed() >= Constants.CHEFTY_SEAT_SWAP_MAX_SPEED:
			return
		var other := SEAT_SHOTGUN if seat == SEAT_DRIVER else SEAT_DRIVER
		_riders[seat] = _riders[other]
		_riders[other] = peer_id
	else:
		var next := -1
		for step: int in range(1, Constants.CHEFTY_SEATS - _Vehicles.CHEFTY_CAB_SEATS):
			var candidate := _Vehicles.CHEFTY_CAB_SEATS + (seat - _Vehicles.CHEFTY_CAB_SEATS + step) % (Constants.CHEFTY_SEATS - _Vehicles.CHEFTY_CAB_SEATS)
			if _riders[candidate] == 0:
				next = candidate
				break
		if next < 0:
			return
		_riders[seat] = 0
		_riders[next] = peer_id
	_send_seats()


func _send_seats() -> void:
	_rpc_seats.rpc(_riders, driver())


func _on_player_left(peer_id: int) -> void:
	_watchers.erase(peer_id)
	drop_rider(peer_id)


func _player(peer_id: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node as Node3D
	return null


# ---------------------------------------------------------------- simulation

func _physics_process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if not _hop.is_empty():
		_step_hop()
		return
	_step_dev_script(delta)
	if Net.is_host():
		_host_step(delta)
	elif driver() == Net.local_peer_id() and driver() != 0:
		_predict_step(delta)
	_update_presentation(delta)


## Host: this tick's inputs (usually one; two when the driver's queue runs long),
## the sim, and a snapshot every other tick.
func _host_step(delta: float) -> void:
	var steps := 2 if _queue.size() > Constants.CHEFTY_INPUT_QUEUE_CATCHUP else 1
	for _step: int in steps:
		var input := _host_input()
		_set_horn(bool(input.get("horn", false)))
		if driver() == Net.local_peer_id():
			_local_horn(bool(input.get("horn", false)))
		VehicleSim.step(_chassis, _state, input, _params, delta)
	_body.global_transform = VehicleSim.body_transform(_chassis.global_position, _state)
	_tick += 1
	var every := maxi(1, int(round(float(Engine.physics_ticks_per_second) / float(Constants.CHEFTY_SNAP_HZ))))
	if _tick % every == 0:
		# Only to peers whose Chefty exists (it asked for the state from _ready):
		# an unreliable snapshot can outrun the world's spawn to a joining peer.
		for peer_id: int in _watchers.keys():
			if Net.peer_ids().has(peer_id):
				_rpc_snap.rpc_id(peer_id, Net.server_time(), _chassis.global_position, float(_state["yaw"]), _state["vel"], float(_state["yaw_rate"]), float(_state["steer"]), _ack)
	_note_parking()


## Host: the driver's next input. The host's own seated player drives directly; a
## client's come queued; with none for CHEFTY_INPUT_TIMEOUT, or nobody driving,
## Chefty brakes.
func _host_input() -> Dictionary:
	var who := driver()
	if who == 0:
		return {"brake": true}
	if who == Net.local_peer_id():
		return _input_from_local()
	if not _queue.is_empty():
		var next: Dictionary = _queue.pop_front()
		_ack = int(next["seq"])
		_held = _unpack(next)
		_input_msec = Time.get_ticks_msec()
		return _held
	if _held.is_empty() or Time.get_ticks_msec() - _input_msec > int(Constants.CHEFTY_INPUT_TIMEOUT * 1000.0):
		return {"brake": true}
	return _held


## The local seated player's controls, or a test's script while one plays.
func _input_from_local() -> Dictionary:
	if not _dev_steps.is_empty() or _dev_left > 0.0:
		return _dev_input
	return _local_input


static func _unpack(packed: Dictionary) -> Dictionary:
	var flags := int(packed["flags"])
	return {"throttle": float(packed["throttle"]), "steer": float(packed["steer"]), "handbrake": flags & FLAG_HANDBRAKE != 0, "horn": flags & FLAG_HORN != 0}


## The driver's peer: send this tick's input and move on it right away.
func _predict_step(delta: float) -> void:
	_seq += 1
	var input := _input_from_local()
	var flags := (FLAG_HANDBRAKE if bool(input.get("handbrake", false)) else 0) | (FLAG_HORN if bool(input.get("horn", false)) else 0)
	_rpc_input.rpc_id(1, _seq, float(input.get("throttle", 0.0)), float(input.get("steer", 0.0)), flags)
	# The horn plays the moment you press it; the host's _rpc_horn follows.
	_local_horn(bool(input.get("horn", false)))
	_pending.append({"seq": _seq, "input": input})
	while _pending.size() > PREDICTION_HISTORY:
		_pending.pop_front()
	VehicleSim.step(_chassis, _state, input, _params, delta)
	_predicted[_seq] = _chassis.global_position
	_predicted.erase(_seq - PREDICTION_HISTORY)
	# The drawn pose carries what's left of the last correction, fading out.
	var fade := pow(0.5, delta / Constants.CHEFTY_CORRECTION_HALF_LIFE)
	_offset *= fade
	_yaw_offset *= fade
	var drawn := _state.duplicate()
	drawn["yaw"] = float(_state["yaw"]) + _yaw_offset
	_body.global_transform = VehicleSim.body_transform(_chassis.global_position + _offset, drawn)


## The driver's peer, on a snapshot: back to where the host had Chefty after the
## input it acked, the inputs since replayed, and the jump faded out of the view.
func _reconcile(pos: Vector3, yaw_now: float, vel: Vector3, yaw_rate: float, ack: int) -> void:
	if ack > _last_ack and _predicted.has(ack):
		_prediction_error_max = maxf(_prediction_error_max, (_predicted[ack] as Vector3).distance_to(pos))
	_last_ack = maxi(_last_ack, ack)
	while not _pending.is_empty() and int(_pending[0]["seq"]) <= ack:
		_pending.pop_front()
	var before := _chassis.global_position
	var before_yaw := float(_state["yaw"])
	_chassis.global_position = pos
	_state["yaw"] = yaw_now
	_state["vel"] = vel
	_state["yaw_rate"] = yaw_rate
	var dt := get_physics_process_delta_time()
	for entry: Dictionary in _pending:
		VehicleSim.step(_chassis, _state, entry["input"], _params, dt)
		_predicted[int(entry["seq"])] = _chassis.global_position
	var jump := before - _chassis.global_position
	if jump.length() > 0.05:
		_corrections += 1
		_VehicleView.stats["corrections"] = int(_VehicleView.stats["corrections"]) + 1
		_VehicleView.stats["max_correction_m"] = maxf(float(_VehicleView.stats["max_correction_m"]), jump.length())
	var carried := _offset + jump
	if carried.length() > Constants.CHEFTY_SNAP_ERROR:
		_offset = Vector3.ZERO
		_yaw_offset = 0.0
		_VehicleView.stats["snaps"] = int(_VehicleView.stats["snaps"]) + 1
		_body.reset_physics_interpolation()
	else:
		_offset = carried
		_yaw_offset = wrapf(_yaw_offset + before_yaw - float(_state["yaw"]), -PI, PI)


## Everyone but the host and the driver: the view places the body (priority 50).
func apply_view_pose(pos: Vector3, yaw_now: float, vel: Vector3, snapped: bool) -> void:
	var dt := maxf(get_physics_process_delta_time(), 0.0001)
	var forward := VehicleSim.forward_of(yaw_now)
	var accel := (vel - _view_vel) / dt
	var turn := wrapf(yaw_now - float(_view_state["yaw"]), -PI, PI) / dt
	_view_vel = vel
	_view_state["yaw"] = yaw_now
	var lean := Constants.CHEFTY_LEAN_MAX
	_view_state["lean_pitch"] = lerpf(float(_view_state["lean_pitch"]), clampf(accel.dot(forward) * Constants.CHEFTY_LEAN_PITCH, -lean, lean), clampf(dt * 8.0, 0.0, 1.0))
	_view_state["lean_roll"] = lerpf(float(_view_state["lean_roll"]), clampf(-turn * vel.dot(forward) * Constants.CHEFTY_LEAN_ROLL, -lean, lean), clampf(dt * 6.0, 0.0, 1.0))
	_body.global_transform = VehicleSim.body_transform(pos, _view_state)
	if snapped:
		_body.reset_physics_interpolation()


func _uses_view() -> bool:
	return not Net.is_host() and (driver() != Net.local_peer_id() or driver() == 0)


## Who draws this peer's Chefty: the host its own sim, the driver its prediction,
## everyone else the view.
func _refresh_role() -> void:
	if _view == null:
		return
	var viewing := _uses_view()
	if bool(_view.get("active")) == viewing:
		return
	_view.set("active", viewing)
	if not viewing and not Net.is_host():
		# Just became the driver: start predicting from the newest snapshot, and
		# fade from where Chefty was drawn.
		var latest: Dictionary = _view.call("latest")
		if not latest.is_empty():
			_chassis.global_position = latest["pos"]
			_state["yaw"] = float(latest["yaw"])
			_state["vel"] = latest["vel"]
		_offset = _body.global_position - _chassis.global_position
		_yaw_offset = wrapf(_body.global_rotation.y - float(_state["yaw"]), -PI, PI)
		_pending.clear()
		_predicted.clear()


## Host: Chefty came to a stop (it's parked) or set off.
func _note_parking() -> void:
	var moving := speed() > Constants.CHEFTY_PARK_SPEED
	if _was_moving and not moving:
		parked.emit(_chassis.global_position)
	_was_moving = moving


## The legacy-style trip (until the autopilot): sit, then park at the stop.
func _step_hop() -> void:
	if not Net.is_host():
		return
	if Net.server_time() - float(_hop["start"]) < float(_hop["seconds"]):
		return
	var zone := int(_hop["zone"])
	var stop := _hop_stop(zone)
	var riders_now: Array[int] = []
	for id: int in _riders:
		if id != 0:
			riders_now.append(id)
	_rpc_hop_arrived.rpc(stop.origin, stop.basis.get_euler().y)
	for id: int in riders_now:
		Net.move_player_to_zone(id, zone as Net.Zone)
	var world := get_tree().get_first_node_in_group("world")
	if world != null and world.has_method("on_ride_arrived"):
		world.call("on_ride_arrived", zone)


## Where a hop parks: at the yard's curb facing along its street, or on the TruckPad.
func _hop_stop(zone: int) -> Transform3D:
	var world := get_tree().get_first_node_in_group("world")
	if zone == Net.Zone.LOT and world != null:
		var lot_zone := world.get_node_or_null("LotZone") as Node3D
		if lot_zone != null:
			return Transform3D(Basis(Vector3.UP, -PI * 0.5), lot_zone.global_transform * TownMap.CURB_POINT)
	return Transform3D(Basis(Vector3.UP, Constants.CHEFTY_PARK_YAW), Constants.CHEFTY_PARK_SPOT)


## The steering wheel, the label, the sounds.
func _update_presentation(delta: float) -> void:
	var steer := float(_state.get("steer", 0.0))
	if driver() == Net.local_peer_id() and driver() != 0:
		steer = float(_input_from_local().get("steer", 0.0))
	_Vehicles.set_steering(_look, steer)
	_update_sound(delta)


# ---------------------------------------------------------------- tests

## Host: play scripted controls on the driver's peer (drive_test). Steps are
## {seconds, throttle, steer, handbrake, horn} held for seconds, or {do:
## "enter", kind} / {do: "exit"} / {do: "swap"} done at once.
func dev_script(peer_id: int, steps: Array) -> void:
	if not Net.is_host():
		return
	if peer_id == Net.local_peer_id():
		_start_dev_script(steps)
	else:
		_rpc_dev_script.rpc_id(peer_id, steps)


@rpc("authority", "call_remote", "reliable")
func _rpc_dev_script(steps: Array) -> void:
	if float(Net.dev_options().get("run_seconds")) <= 0.0:
		return
	_start_dev_script(steps)


func _start_dev_script(steps: Array) -> void:
	_dev_steps = steps.duplicate(true)
	_dev_left = 0.0
	_dev_input = {}


func _step_dev_script(delta: float) -> void:
	if _dev_left > 0.0:
		_dev_left -= delta
		if _dev_left > 0.0:
			return
		_dev_input = {}
	while not _dev_steps.is_empty():
		var step: Dictionary = _dev_steps.pop_front()
		match str(step.get("do", "")):
			"enter":
				request_enter(int(step.get("kind", Kind.NEAREST)))
				continue
			"exit":
				request_exit()
				continue
			"swap":
				request_swap()
				continue
		_dev_input = {"throttle": float(step.get("throttle", 0.0)), "steer": float(step.get("steer", 0.0)), "handbrake": bool(step.get("handbrake", false)), "horn": bool(step.get("horn", false))}
		_dev_left = float(step.get("seconds", 0.0))
		return


## Whether a test script is still playing here.
func dev_script_playing() -> bool:
	return not _dev_steps.is_empty() or _dev_left > 0.0


## For the probe (net/dev/probe.gd "drive") and drive_test, as this peer sees it.
func dev_report() -> Dictionary:
	var riders_list: Array = []
	for id: int in _riders:
		riders_list.append(id)
	var at := _chassis.global_position
	return {
		"riders": riders_list,
		"driver": driver(),
		"prediction_error_max_m": _prediction_error_max,
		"corrections": _corrections,
		"horn_seen": _horn_log.duplicate(),
		"crashes_seen": 0,
		"dents": _dents,
		"bag_count": bag_count(),
		"speed": speed(),
		"pos": [at.x, at.y, at.z],
		"yaw": float(_state["yaw"]),
	}


## The chassis's pose as the sim has it here (host: the truth; the driver: the
## prediction): {pos, yaw, vel}.
func sim_pose() -> Dictionary:
	return {"pos": _chassis.global_position, "yaw": float(_state["yaw"]), "vel": _state["vel"]}


## Host, tests: put Chefty somewhere, stopped.
func dev_place(at: Vector3, yaw_now: float) -> void:
	if not Net.is_host():
		return
	_place(at, yaw_now)
	_rpc_placed.rpc(at, yaw_now)


# ---------------------------------------------------------------- sound

## Audio's contract (gap-specs/critic.md C13): audio/vehicle_sound.gd reads this.
## {on, throttle (-1..1), speed (m/s), skidding}.
func engine_state() -> Dictionary:
	var input := _input_from_local() if driver() == Net.local_peer_id() else _held
	return {
		"on": driver() != 0 or is_moving(),
		"throttle": float(input.get("throttle", 0.0)) if driver() != 0 else 0.0,
		"speed": speed(),
		"skidding": float(_state.get("slip", 0.0)) > Constants.CHEFTY_SKID_SLIP,
	}


## The engine and skid: audio/vehicle_sound.gd when it exists (audio chunk 7),
## else a plain engine loop pitched by speed and a skid loop. Nothing headless.
func _attach_sound() -> void:
	if Net.is_automated() or DisplayServer.get_name() == "headless":
		return
	if ResourceLoader.exists("res://audio/vehicle_sound.gd"):
		var vehicle_sound: Node = load("res://audio/vehicle_sound.gd").new()
		vehicle_sound.name = "VehicleSound"
		_body.add_child(vehicle_sound)
		# It reads engine_state() from its parent.
		vehicle_sound.set_meta("state_source", self)
	else:
		_engine = _sound_loop("engine_idle", "Engine")
		_skid = _sound_loop("skid", "Skid")
	_horn_player = _sound_loop("horn_loop", "Horn")


func _sound_loop(id: String, node_name: String) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = node_name
	player.stream = _Sfx.looped(id)
	player.bus = _SoundBank.bus(id)
	player.unit_size = 8.0
	player.max_distance = 70.0
	player.volume_db = -40.0
	player.position = Vector3(0.0, 1.0, -2.2)
	_body.add_child(player)
	return player


func _update_sound(delta: float) -> void:
	if _engine != null and _engine.stream != null:
		var state := engine_state()
		var share := clampf(float(state["speed"]) / Constants.CHEFTY_TOP_SPEED, 0.0, 1.0)
		if bool(state["on"]):
			if not _engine.playing:
				_engine.play()
			_engine.pitch_scale = lerpf(Constants.CHEFTY_ENGINE_PITCH.x, Constants.CHEFTY_ENGINE_PITCH.y, share) + absf(float(state["throttle"])) * 0.08
			_engine.volume_db = lerpf(-14.0, -4.0, share)
		elif _engine.playing:
			_engine.stop()
		if _skid != null and _skid.stream != null:
			var skidding := bool(state["skidding"]) and share > 0.2
			if skidding and not _skid.playing:
				_skid.play()
			elif not skidding and _skid.playing:
				_skid.stop()
			_skid.volume_db = -6.0
	if _horn_player != null and _horn_player.stream != null:
		var honking := _horn or (driver() == Net.local_peer_id() and driver() != 0 and bool(_input_from_local().get("horn", false)))
		_horn_held = _horn_held + delta if honking else 0.0
		var loop := _horn_held > Constants.CHEFTY_HORN_LOOP_AFTER
		if loop and not _horn_player.playing:
			_horn_player.volume_db = -2.0
			_horn_player.play()
		elif not loop and _horn_player.playing:
			_horn_player.stop()


var _local_honking: bool = false


## The driver hears their own horn the moment they press it.
func _local_horn(on: bool) -> void:
	if on and not _local_honking:
		_play_on("truck_horn")
	_local_honking = on


## Host: the driver's horn, to everyone.
func _set_horn(on: bool) -> void:
	if on == _horn:
		return
	_rpc_horn.rpc(on)


func _play_on(id: String) -> void:
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play_on", id, _body)


func _refresh_label() -> void:
	if _label == null:
		return
	var full := _Strings.UI["ride_chefty_full"] if bag_count() >= Constants.TRUCK_BAG_CAPACITY else ""
	_label.text = _Strings.UI["ride_chefty_label"] % [bag_count(), Constants.TRUCK_BAG_CAPACITY, _job_value, full]


# ---------------------------------------------------------------- RPCs

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _rpc_input(seq: int, throttle: float, steer: float, flags: int) -> void:
	if not Net.is_host() or multiplayer.get_remote_sender_id() != driver():
		return
	if seq <= _ack or (not _queue.is_empty() and seq <= int(_queue[_queue.size() - 1]["seq"])):
		return
	_queue.append({"seq": seq, "throttle": clampf(throttle, -1.0, 1.0), "steer": clampf(steer, -1.0, 1.0), "flags": flags})
	# A stalled link must not let the queue grow without end.
	while _queue.size() > 30:
		_queue.pop_front()


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _rpc_snap(t: float, pos: Vector3, yaw_now: float, vel: Vector3, yaw_rate: float, steer: float, ack: int) -> void:
	_view.call("add_snap", t, pos, yaw_now, vel)
	_state["steer"] = steer
	if driver() == Net.local_peer_id() and driver() != 0:
		_reconcile(pos, yaw_now, vel, yaw_rate, ack)
	else:
		_chassis.global_position = pos
		_chassis.global_rotation = Vector3(0.0, yaw_now, 0.0)
		_state["yaw"] = yaw_now
		_state["vel"] = vel
		_state["yaw_rate"] = yaw_rate


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_enter(kind: int) -> void:
	if Net.is_host():
		_handle_enter(multiplayer.get_remote_sender_id(), kind)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_exit() -> void:
	if Net.is_host():
		_handle_exit(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_swap() -> void:
	if Net.is_host():
		_handle_swap(multiplayer.get_remote_sender_id())


@rpc("authority", "call_local", "reliable")
func _rpc_seats(seated: PackedInt32Array, driver_id: int) -> void:
	var before := _riders.duplicate()
	var before_driver := driver()
	_riders = seated.duplicate()
	_riders.resize(Constants.CHEFTY_SEATS)
	if Net.is_host() and driver_id != before_driver:
		# A new driver starts a fresh input stream.
		_queue.clear()
		_held = {}
		_ack = 0
	# The driver's peer keeps counting its inputs up across seats, so nothing
	# still on the way from an earlier stint is taken for a new one.
	if driver_id != before_driver:
		driver_changed.emit(driver_id)
	_refresh_role()
	# Someone got in or out of the cab: the door.
	for index: int in _Vehicles.CHEFTY_CAB_SEATS:
		if before[index] != _riders[index]:
			_play_on("door_slam")
			break


@rpc("authority", "call_local", "reliable")
func _rpc_horn(on: bool) -> void:
	_horn = on
	_horn_log.append(on)
	# The driver already heard it start.
	if on and not (driver() == Net.local_peer_id() and driver() != 0):
		_play_on("truck_horn")


@rpc("authority", "call_local", "reliable")
func _rpc_bags(job_bags: int, job_value: int, spent_bags: int) -> void:
	if job_value > _job_value and _body != null:
		_MoneyPopup.pop(get_tree(), _body.global_position + Vector3(0.0, 3.0, 0.0), job_value - _job_value)
	_job_bags = job_bags
	_job_value = job_value
	_spent_bags = spent_bags
	_refresh_label()


@rpc("authority", "call_local", "reliable")
func _rpc_hop(start: float, seconds: float, zone: int) -> void:
	_hop = {"start": start, "seconds": seconds, "zone": zone}
	_play_on("truck_horn")


@rpc("authority", "call_local", "reliable")
func _rpc_hop_arrived(at: Vector3, yaw_now: float) -> void:
	_hop = {}
	_riders.fill(0)
	_place(at, yaw_now)
	_view.call("clear")
	_refresh_role()
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.has_method("clear_riding"):
			node.call("clear_riding")


@rpc("authority", "call_remote", "reliable")
func _rpc_placed(at: Vector3, yaw_now: float) -> void:
	_place(at, yaw_now)
	_view.call("clear")


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_state() -> void:
	if not Net.is_host():
		return
	_watchers[multiplayer.get_remote_sender_id()] = true
	var hop_left := -1.0
	if not _hop.is_empty():
		hop_left = float(_hop["seconds"]) - (Net.server_time() - float(_hop["start"]))
	_rpc_state.rpc_id(multiplayer.get_remote_sender_id(), _riders, driver(), _job_bags, _job_value, _spent_bags, _dents, _horn, hop_left, int(_hop.get("zone", 0)), _chassis.global_position, float(_state["yaw"]))


## A late joiner learns who sits where, what's in the bed, and where Chefty is.
@rpc("authority", "call_remote", "reliable")
func _rpc_state(seated: PackedInt32Array, _driver_id: int, job_bags: int, job_value: int, spent_bags: int, dents: int, horn: bool, hop_left: float, hop_zone: int, at: Vector3, yaw_now: float) -> void:
	_riders = seated.duplicate()
	_riders.resize(Constants.CHEFTY_SEATS)
	_job_bags = job_bags
	_job_value = job_value
	_spent_bags = spent_bags
	_dents = dents
	_horn = horn
	if hop_left >= 0.0:
		_hop = {"start": Net.server_time(), "seconds": hop_left, "zone": hop_zone}
	_place(at, yaw_now)
	_refresh_params()
	_refresh_role()
	_refresh_label()
