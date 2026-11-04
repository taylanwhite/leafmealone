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
##
## Trips (driving chunk C2): depart() seats the party and the host's autopilot
## (vehicle_autopilot.gd) drives the roads to the yard's curb or the TruckPad,
## where everyone gets off into the zone like the legacy ride. With a hired hand
## aboard and the driver's seat empty, G in the cab lets the hand drive
## (request_chauffeur): the same autopilot, to the picked job or home, with the
## riders free to get out. Automated runs and --warp-rides skip the driving and
## follow the route at AUTOPILOT_TEST_WARP times cruise speed. The hands riding
## along are drawn in the free bed seats (and at the wheel) on every peer from
## the hires list and the seats, cosmetic only (cosmetic_riders()).
##
## The dash (p1-dash): no panel on screen. Every peer measures how fast Chefty
## really goes over the road (ground_speed(), _update_ground) and feeds the cab's
## instruments (props/chefty_dash.gd) with it, the odometer (the crew's meters,
## the host's saved and sent with _rpc_odometer) and the dents. Getting in at the
## driver's door, sliding over and bailing out go by ground speed too. Seated,
## seat_hint() is the prompt over the seat or hired hand you look at.

signal crashed(strength: float, at: Vector3)
signal parked(at: Vector3)
signal driver_changed(peer_id: int)

const _Vehicles = preload("res://props/vehicles.gd")
const _VehicleView = preload("res://net/components/vehicle_view.gd")
const _VehicleBody = preload("res://net/components/vehicle_body.gd")
const _MoneyPopup = preload("res://ui/money_popup.gd")
const _Strings = preload("res://ui/strings.gd")
const _Sfx = preload("res://audio/sfx.gd")
const _SoundBank = preload("res://audio/sound_bank.gd")
const _CartoonBody = preload("res://player/cartoon_body.gd")
const _BedLoad = preload("res://props/truck_bed_load.gd")
const _NearLabel = preload("res://ui/near_label.gd")
const _JunkBed = preload("res://net/components/junk_bed.gd")
const _CheftyPaint = preload("res://net/components/chefty_paint.gd")

const _CheftyCrash = preload("res://net/components/chefty_crash.gd")
## Chefty's bed, in its own space: bags that land in here are loaded (as ride.gd).
const BED := AABB(Vector3(-1.05, 0.9, -1.2), Vector3(2.1, 1.3, 3.85))
const COLOR := Color(0.75, 0.22, 0.15)
## Seat kinds for request_enter: the driver's seat, shotgun, the bed, or whichever
## door is nearest.
enum Kind { DRIVER = 0, SHOTGUN = 1, BED = 2, NEAREST = -1 }
## What the autopilot is doing: nothing, a depart() trip (the riders arrive in a
## zone at the end), or a hired hand chauffeuring (the riders stay put).
enum Trip { NONE = 0, DEPART = 1, CHAUFFEUR = 2 }
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
## The crew's paint and decal on the look now (shops chunk 7, apply_paint).
var _paint: Dictionary = {"color": COLOR, "decal": ""}
var _tick: int = 0
## Host: the driver's queued inputs [{seq, throttle, steer, flags}], the one
## held while none arrive, when the last one came, and the last seq used.
var _queue: Array[Dictionary] = []
var _held: Dictionary = {}
var _input_msec: int = 0
var _ack: int = 0
## Host: the driver's input the pose is after (what snapshots ack). Ahead of _ack
## while the host drove on the last input because the next ones were late (a
## hitch on either end) or lost: those ticks stood in for the inputs, which then
## move Chefty nothing more when they come (_host_input).
var _sim_seq: int = 0
## Host, for the probe: ticks driven on a stand-in, stand-ins the input made good
## later, and ticks past CHEFTY_STAND_IN_MAX_SECONDS that stood in for nothing.
var _stood_in: int = 0
var _made_good: int = 0
var _forgiven: int = 0
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
## The newest snapshot for the driver, reconciled on the next physics tick.
var _snap_waiting: Dictionary = {}
var _offset := Vector3.ZERO
var _yaw_offset: float = 0.0
var _last_ack: int = 0
var _prediction_error_max: float = 0.0
var _prediction_error_sum: float = 0.0
var _prediction_error_count: int = 0
## Snapshots that acked an input this peer hadn't predicted yet (see _reconcile).
var _acks_ahead: int = 0
var _corrections: int = 0
## Host, for drive_test: each peer's last time getting out, peer -> {at, bail}.
var _last_exits: Dictionary = {}
## This peer's own seated player's controls, set each tick by player/seated.gd.
var _local_input: Dictionary = {}
## Tests (_rpc_dev_script): scripted inputs that play through the normal path.
var _dev_steps: Array = []
var _dev_left: float = 0.0
var _dev_input: Dictionary = {}
## Non-drivers: the last drawn velocity, for the lean.
var _view_vel := Vector3.ZERO
var _view_state: Dictionary = {}
## The trip under way, on every peer (_rpc_autopilot): its Trip kind, the zone a
## depart() trip ends in, the hand at the wheel ("" with none aboard), and how
## many trips this peer has seen start (tests).
var _trip: int = Trip.NONE
var _trip_zone: int = 0
var _trip_label: String = ""
var _trips_seen: int = 0
## Tests: what this peer's own chauffeur_action() offered, each change to a
## non-empty one in order ("start", "stop"), so CI can check a client's G key
## offered what the host agreed to.
var _chauffeur_seen: Array[String] = []
var _chauffeur_last: String = ""
## Host: the autopilot driving the trip, whether it warps, where it parks (and
## facing which way, for a warp), and how long it has been going and may go.
var _auto: VehicleAutopilot = null
var _warp: bool = false
var _warp_forced: bool = false
var _trip_stop := Transform3D()
var _trip_clock: float = 0.0
var _trip_give_up: float = 0.0
var _quip_rng := RandomNumberGenerator.new()
## The chauffeur's quip over the cab, and how long it stays.
var _quip_label: Label3D
var _quip_left: float = 0.0
## The hands drawn riding along: what was built (to rebuild only on a change), the
## figures, and when each waves next.
var _hands_built: String = ""
var _hand_figures: Array[Node3D] = []
var _wave_rng := RandomNumberGenerator.new()
## Bags: this job's (unpaid; what the homeowner pays for) and paid ones still in
## the bed (driving chunk J's mulch; always 0 for now).
var _job_bags: int = 0
var _job_value: int = 0
var _spent_bags: int = 0
## Host: the last day Marty towed Chefty home (the save's towed_day).
var _towed_day: int = 0
var _was_moving: bool = false
## Host: coming home nose-first, the last stretch is a handbrake swing round to
## face the road (_swing_step): where it started, its heading then, and how far
## through it is (0..1, -1 when not swinging).
var _swing_from := Vector3.ZERO
var _swing_yaw: float = 0.0
var _swing_t: float = -1.0
## Every peer: the drawn heading last frame, and how fast it's turning, for the
## skid sound (a swing or a drift squeals on everyone's screen).
var _drawn_yaw: float = 0.0
var _drawn_yaw_rate: float = 0.0
## Sound, built when nothing better is attached (audio/vehicle_sound.gd, audio:7):
## the engine loop, and whether this plays the skid one-shot itself (and when next).
var _engine: AudioStreamPlayer3D
var _own_skid: bool = false
var _skid_left: float = 0.0
var _horn_player: AudioStreamPlayer3D
var _horn_held: float = 0.0
## The bags drawn in the bed (props/truck_bed_load.gd).
var _bed_load: Node3D
## The junk in the bed for Rusty's (net/components/junk_bed.gd).
var _junk_bed: Node3D
## The crash comedy (net/components/chefty_crash.gd, driving chunk C3).
var _crash: Node
## p1-dash: Chefty's ground velocity as this peer draws it (the host: the
## chassis, the truth), smoothed, and where it was last tick (INF before the
## first). What the needle shows and the seat rules go by (ground_speed()).
var _ground_vel := Vector3.ZERO
var _ground_last := Vector3.INF
## The crew's miles, in meters (the save's vehicle.odometer_m): the host's count,
## and on every other peer its own count of the drawn truck's travel, kept to the
## host's by _rpc_odometer. Host: the count it last sent.
var _odometer_m: float = 0.0
var _odometer_sent: float = 0.0
## Who sat where as _rpc_seats (or the join's _rpc_state) last said, for telling
## what changed.
var _seats_said := PackedInt32Array()


func _ready() -> void:
	add_to_group("rides")
	add_to_group("chefty")
	add_to_group("vehicles")
	_riders.resize(Constants.CHEFTY_SEATS)
	_seats_said = _riders.duplicate()
	_quip_rng.randomize()
	_wave_rng.randomize()
	_state = VehicleSim.new_state(Constants.CHEFTY_PARK_YAW)
	_view_state = VehicleSim.new_state(Constants.CHEFTY_PARK_YAW)
	_build()
	_place(Constants.CHEFTY_PARK_SPOT, Constants.CHEFTY_PARK_YAW)
	_refresh_params()
	_refresh_label()
	_refresh_role()
	# perk:chefty_tuneup can arrive mid-session (the crew ranks up at day end):
	# every peer runs the same numbers again, so prediction keeps matching the host.
	if not Campaign.rank_changed.is_connected(_refresh_params):
		Campaign.rank_changed.connect(_refresh_params)
	if not Campaign.campaign_loaded.is_connected(_refresh_params):
		Campaign.campaign_loaded.connect(_refresh_params)
	if Net.is_host():
		if not Net.player_left.is_connected(_on_player_left):
			Net.player_left.connect(_on_player_left)
		_load_section()
		Campaign.add_save_hook(_save_section)
	elif multiplayer.multiplayer_peer != null:
		_rpc_request_state.rpc_id(1)


func _exit_tree() -> void:
	Campaign.remove_save_hook(_save_section)


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
	var body := _VehicleBody.new()
	body.vehicle = self
	_body = body
	_body.name = "Body"
	add_child(_body)
	_look = _Vehicles.build_truck(_body, {"color": COLOR, "interior": true})
	var solid := _look.get_node_or_null("Solid") as PhysicsBody3D
	if solid != null:
		_chassis.add_collision_exception_with(solid)
	# Its name and load shrink and fade up close (ui/near_label.gd).
	var label: Label3D = _NearLabel.new()
	label.name = "Label"
	label.font_size = 72
	label.outline_size = 12
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0.0, 3.4, 0.0)
	_body.add_child(label)
	_label = label
	_bed_load = _BedLoad.new()
	_body.add_child(_bed_load)
	_junk_bed = _JunkBed.new()
	_body.add_child(_junk_bed)
	# The chauffeur's quip, over the cab while it lasts.
	var quip := Label3D.new()
	quip.name = "Quip"
	quip.font_size = 48
	quip.outline_size = 10
	quip.width = 900.0
	quip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quip.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	quip.modulate = Color(1.0, 0.85, 0.55)
	quip.position = Vector3(0.0, 4.3, -1.6)
	quip.visible = false
	_body.add_child(quip)
	_quip_label = quip
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
	# The crew's paint job and decal (shops chunk 7).
	var paint := _CheftyPaint.new()
	paint.vehicle = self
	add_child(paint)

	# Crashes, spills, run-overs and the rest of what driving does (driving C3).
	_crash = _CheftyCrash.new()
	_crash.set("vehicle", self)
	add_child(_crash)
	_attach_sound()


## Chefty's paint and decal (shops chunk 7; chefty_paint.gd calls it only while
## it stands still, gap-specs critic C22): TruckLook is built again with them
## (the seats, the bed's load and the chassis stay), its Solid kept out of the
## chassis' way and the sim's.
func apply_paint(color: Color, decal: String) -> void:
	_paint = {"color": color, "decal": decal}
	if _body == null:
		return
	_look = _Vehicles.build_truck(_body, {"color": color, "decal": decal, "dents": _dents, "interior": true})
	var solid := _look.get_node_or_null("Solid") as PhysicsBody3D
	if solid != null and _chassis != null:
		_chassis.add_collision_exception_with(solid)
	_refresh_params()


## The sim's numbers: Chefty's, less its dents, plus the tune-up perk.
func _refresh_params() -> void:
	if _look == null:
		return
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
	_draw_body(VehicleSim.body_transform(at, _state))
	_body.reset_physics_interpolation()
	_chassis.reset_physics_interpolation()


## Every peer: where Body is drawn this tick, with a barrel roll's hop and turn on
## top while one plays (chefty_crash.gd tumble_offset; the chassis never flips).
func _draw_body(xform: Transform3D) -> void:
	_body.global_transform = xform * _crash.call("tumble_offset") if _crash != null else xform


# ---------------------------------------------------------------- the ride contract

## On a trip depart() started (the riders are along for it until it arrives).
func is_riding() -> bool:
	return _trip == Trip.DEPART


## The autopilot has the wheel: a depart() trip or a chauffeur.
func is_autopiloting() -> bool:
	return _trip != Trip.NONE


## The hired hand at the wheel ("" when nobody, or nobody's aboard). The name is
## the trip's (the host's pick when it started), and only counts while that hand
## is still aboard: one fired or gone home at payroll mid-trip isn't driving.
func trip_label() -> String:
	return _trip_label if not _wheel_hand().is_empty() else ""


## The hand drawn at the wheel: the trip's hand, while they're still aboard, else {}.
func _wheel_hand() -> Dictionary:
	if _trip == Trip.NONE or _trip_label == "" or driver() != 0:
		return {}
	for hand: Variant in hands_aboard():
		if hand is Dictionary and str((hand as Dictionary).get("name", "")) == _trip_label:
			return hand
	return {}


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


## How fast Chefty really goes over the road here (m/s): the drawn truck's
## travel, smoothed (the host's is the chassis's). Pinned against a wall with the
## gas down it's about 0, whatever the sim is pushing (p1-dash). The needle shows
## it, and getting in, sliding over and bailing out go by it.
func ground_speed() -> float:
	return Vector2(_ground_vel.x, _ground_vel.z).length()


## That travel as a velocity (m/s, flat): what a bail flings you with.
func ground_velocity() -> Vector3:
	return Vector3(_ground_vel.x, 0.0, _ground_vel.z)


## The odometer (miles): what Chefty had on it when the crew got it, plus the
## crew's own.
func odometer_miles() -> float:
	return Constants.CHEFTY_ODOMETER_START_MILES + _odometer_m / Constants.CHEFTY_METERS_PER_MILE


## Whether the engine's running: someone at the wheel, or a hired hand.
func engine_on() -> bool:
	return driver() != 0 or _trip != Trip.NONE


## What the dash in the cab shows now ({mph, odometer, check_engine}; {} without one).
func dash_reading() -> Dictionary:
	var dash := _dash()
	return dash.call("reading") if dash != null else {}


func _dash() -> Node:
	return _look.get_node_or_null("Dash") if _look != null else null


func yaw() -> float:
	if _body == null:
		return 0.0
	# From where its length points, not the Euler angles: a barrel roll turns it
	# about that axis (chefty_crash.gd), and past a quarter turn the Euler yaw flips
	# by half a turn.
	var length := _body.global_basis.z
	return atan2(length.x, length.z)


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


## Host only (chefty_crash.gd): count of this job's bags come off the top of the
## heap, each with its share of the bed's value (what flew out adds up to exactly
## what the bed lost) and the spot it was drawn in: [{value, xform}]. Every peer's
## heap loses those bags at once (they're the bags flying now).
func host_take_bags(count: int) -> Array:
	var out: Array = []
	if not Net.is_host():
		return out
	count = mini(count, _job_bags)
	if count <= 0:
		return out
	var top := _job_bags + _spent_bags
	var bags_left := _job_bags
	var value_left := _job_value
	for index: int in count:
		# Each bag's fair share of what's left, so the shares sum to the whole.
		var value := int(round(float(value_left) / float(bags_left)))
		value_left -= value
		bags_left -= 1
		out.append({"value": value, "xform": bed_slot(top - 1 - index)})
	_job_bags = bags_left
	_job_value = value_left
	_rpc_spill.rpc(_job_bags, _job_value, _spent_bags)
	return out


## The body you bump into (the bed, the cab; props/vehicles.gd's "Solid"): what
## bags and riders thrown out of the bed pass through on the way out.
func solid_body() -> PhysicsBody3D:
	return _look.get_node_or_null("Solid") as PhysicsBody3D if _look != null else null


## Chefty's dents (0..Constants.CHEFTY_MAX_DENTS), as this peer has them.
func dents() -> int:
	return _dents


## Every peer: Chefty now has this many dents: its top speed (the sim's params,
## the same on every peer so prediction keeps matching) and its looks.
func apply_dents(count: int) -> void:
	_dents = clampi(count, 0, Constants.CHEFTY_MAX_DENTS)
	_refresh_params()
	_Vehicles.set_dents(_look, _dents)


## Host: Marty's Body Shop fixed every dent (net/shops/shops.gd, a "service").
func host_repair() -> void:
	if Net.is_host():
		_rpc_dents.rpc(0)


## Host (chefty_crash.gd): the sim's state as the host has it.
func sim_state() -> Dictionary:
	return _state


## Whether the horn is blowing (the host's say, every peer has it).
func horn_on() -> bool:
	return _horn


## Chefty's velocity as this peer draws it.
func drawn_velocity() -> Vector3:
	return _view_vel if _uses_view() else (_state["vel"] as Vector3)


## True when a point is inside Chefty's open bed.
func in_bed(point: Vector3) -> bool:
	if _body == null:
		return false
	return BED.has_point(_body.global_transform.affine_inverse() * point)


## The bed's space in the world (BED and the load's spots are in it).
func bed_transform() -> Transform3D:
	return body_transform()


## Where the bag in load spot index sits, in the world (props/truck_bed_load.gd).
func bed_slot(index: int) -> Transform3D:
	return bed_transform() * _BedLoad.slot(index)


## The bags drawn in the bed.
func bed_load() -> Node3D:
	return _bed_load


## Dollars' worth of this job's bags. What the homeowner pays for.
func bag_value() -> int:
	return _job_value


func bag_count() -> int:
	return _job_bags + _spent_bags


## Host: a piece of junk lying in the bed is loaded (junk_bed.gd). False when full.
func accept_junk(prop: Node3D) -> bool:
	return _junk_bed != null and bool(_junk_bed.call("accept", prop))


func junk_count() -> int:
	return int(_junk_bed.call("count")) if _junk_bed != null else 0


## Host: the junk hops out over the tailgate, one piece at a time (parked on
## Homie Depot's lot, gap-specs critic C22).
func unload_junk() -> void:
	if _junk_bed != null:
		_junk_bed.call("unload")


## Whether E at the tailgate may unload the junk now: Chefty is standing still.
func junk_unload_allowed() -> bool:
	return ground_speed() <= Constants.CHEFTY_PARK_SPEED


## Host only: the job is paid, so its bags come off the truck.
func clear_bags() -> void:
	if Net.is_host():
		_rpc_bags.rpc(0, 0, _spent_bags)


## Host: the job's paid (world.gd, driving chunk D keeps the yard and the truck).
func on_job_paid() -> void:
	clear_bags()


## Host, at bedtime (net/day/day_clock.gd): Chefty isn't on Homie Depot's lot, so
## Marty tows it back to the TruckPad. Anyone still sitting in it gets out where
## it was. True if it was towed (the day clock charges the fee and texts).
func host_tow_home() -> bool:
	if not Net.is_host() or Constants.STORE_AREA.has_point(Vector2(_chassis.global_position.x, _chassis.global_position.z)):
		return false
	if _trip != Trip.NONE:
		_end_trip()
	for peer_id: int in _riders.duplicate():
		if peer_id != 0:
			_handle_exit(peer_id)
	_riders.fill(0)
	_send_seats()
	_queue.clear()
	_held = {}
	dev_place(Constants.CHEFTY_PARK_SPOT, Constants.CHEFTY_PARK_YAW)
	_towed_day = _day()
	return true


## The day the clock is on (the save's towed_day), 0 without a clock.
func _day() -> int:
	var clock := get_tree().get_first_node_in_group("day_clock")
	return int(clock.get("day")) if clock != null else 0


## The save's "vehicle" section (gap-specs/critic.md, save keys): Chefty's dents,
## paid bags still in the bed (driving chunk J's mulch), the last day Marty
## towed it, and (p1-dash, additive) the meters the crew has driven it, the
## odometer's. Always parked on the TruckPad in the morning, so no position.
func _save_section() -> Dictionary:
	return {"vehicle": {"dents": _dents, "spent_bags": _spent_bags, "towed_day": _towed_day, "odometer_m": _odometer_m}}


func _load_section() -> void:
	var saved := Campaign.save_section("vehicle")
	_spent_bags = maxi(int(saved.get("spent_bags", 0)), 0)
	_towed_day = int(saved.get("towed_day", 0))
	_odometer_m = maxf(float(saved.get("odometer_m", 0.0)), 0.0)
	_odometer_sent = _odometer_m
	apply_dents(int(saved.get("dents", 0)))


## Host only. Seat these peers and take them to a zone: the autopilot drives the
## roads to the stop (the yard's curb, or the TruckPad), and there everyone in a
## seat gets off into the zone, like the legacy ride (their zone is TRANSIT on
## the way). A chauffeur under way gives up the wheel to the trip.
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
	for id: int in riding:
		Net.move_player_to_zone(id, Net.Zone.TRANSIT)
	_start_trip(Trip.DEPART, destination_zone, _stop_for(destination_zone))


## Ask the host to let a hired hand drive (or, while one is, to pull over). From
## a cab seat, with a hand aboard and nobody in the driver's seat.
func request_chauffeur() -> void:
	if Net.is_host():
		_handle_chauffeur(Net.local_peer_id())
	else:
		_rpc_request_chauffeur.rpc_id(1)


## What G does about the chauffeur for this peer: "start" (let a hand drive),
## "stop" (pull over), or "" (nothing). F always stays the seat swap. Every
## peer can ask.
func chauffeur_action(peer_id: int) -> String:
	var seat := seat_of(peer_id)
	if seat < 0 or seat >= _Vehicles.CHEFTY_CAB_SEATS:
		return ""
	if _trip == Trip.CHAUFFEUR:
		return "stop"
	if _trip != Trip.NONE or driver() != 0 or hands_aboard().is_empty() or _chauffeur_stop().is_empty():
		return ""
	return "start"


## The hired hands riding along (net/crew/hires.gd's list), less any off working
## a yard (or still walking back to the truck, each one climbs in on their own).
## Every peer: the list and the hands' bodies replicate.
func hands_aboard() -> Array:
	var hires := get_tree().get_first_node_in_group("hires")
	if hires == null:
		return []
	var out_working := {}
	for node: Node in get_tree().get_nodes_in_group("crew_hands"):
		if not node.is_queued_for_deletion():
			out_working[str(node.get("hand_name"))] = true
	var aboard: Array = []
	for hand: Variant in hires.get("hands") as Array:
		if hand is Dictionary and not out_working.has(str((hand as Dictionary).get("name", ""))):
			aboard.append(hand)
	return aboard


## Where the hands ride, drawn on every peer: [{seat, name, look}]. The trip's
## hand at the wheel while the autopilot drives with the driver's seat empty (the
## one the dash names, trip_label()), the rest in the free bed seats from the
## back row forward.
func cosmetic_riders() -> Array:
	var hands := hands_aboard().duplicate()
	var out: Array = []
	var next := 0
	var wheel := _wheel_hand()
	if not wheel.is_empty():
		out.append({"seat": SEAT_DRIVER, "name": str(wheel.get("name", "")), "look": int(wheel.get("look", 1))})
		hands.erase(wheel)
	for seat: int in range(Constants.CHEFTY_SEATS - 1, _Vehicles.CHEFTY_CAB_SEATS - 1, -1):
		if next >= hands.size():
			break
		if _riders[seat] != 0:
			continue
		out.append({"seat": seat, "name": str(hands[next].get("name", "")), "look": int(hands[next].get("look", 1))})
		next += 1
	return out


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
## {text, at, kind} or {}. Nothing while seated (seat_hint() is the seat's).
func prompt_for(player: Node3D) -> Dictionary:
	if player == null or seat_of(player.name.to_int()) >= 0 or is_riding():
		return {}
	var best := _entry_for(player.global_position, Kind.NEAREST)
	if best.is_empty():
		return {}
	var key := {Kind.DRIVER: "prompt_drive", Kind.SHOTGUN: "prompt_ride_shotgun", Kind.BED: "prompt_ride_bed"}.get(int(best["kind"]), "prompt_ride_bed") as String
	return {"text": _Strings.UI[key], "at": (best["at"] as Vector3) + Vector3(0.0, 1.7, 0.0), "kind": int(best["kind"])}


## Seated, the prompt for what a key does to whatever you're looking at with
## your own eyes (not the chase camera), for the interaction prompt (p1-dash: no
## key list on screen; docs/GAME.md "Chefty's dash"): {text, at, key, source} or {}.
## Everything is across the cab: a seated head turns CHEFTY_SEAT_LOOK_YAW at
## most, never round to the bed behind it.
## - The empty driver's seat, from shotgun with a hired hand riding along: G
##   gives the hand the wheel ("You drive"), next to F "Slide over" while Chefty's
##   slow enough to move over.
## - The hand at the wheel: G "Pull over".
## - The other cab seat, while Chefty's slow enough to move over: F "Slide over"
##   to it when it's empty, "Swap seats" when someone's in it.
## E (out, the way you got in; a bail at speed) and the bed's F shuffle say nothing.
func seat_hint(player: Node3D) -> Dictionary:
	var peer_id := player.name.to_int()
	var seat := seat_of(peer_id)
	var eyes := player.get_node_or_null("Visual/Head/FirstPerson") as Camera3D
	if seat < 0 or not is_cab_seat(seat) or eyes == null or not eyes.current:
		return {}
	var view := eyes.global_transform
	var up := body_transform().basis.y
	var chauffeur := chauffeur_action(peer_id)
	var other := SEAT_SHOTGUN if seat == SEAT_DRIVER else SEAT_DRIVER
	var target := seat_transform(other).origin + up * _seat_head_up(other)
	if not _looked_at(view, target):
		return {}
	var source := "chefty_seat_%d" % other
	if chauffeur == "stop":
		if _wheel_hand().is_empty() or other != SEAT_DRIVER:
			return {}
		return {"text": _Strings.UI["prompt_chauffeur_stop"], "at": target + up * 0.4, "key": "drop", "source": source}
	var slow := _trip == Trip.NONE and ground_speed() < Constants.CHEFTY_SEAT_SWAP_MAX_SPEED
	# Over an empty seat the prompt sits where a head would; over a teammate, above it.
	var at := target + up * (0.0 if _riders[other] == 0 else 0.3)
	if chauffeur == "start":
		# chauffeur_action only says "start" in shotgun with the wheel empty.
		var give: String = _Strings.UI["prompt_chauffeur"]
		if not slow:
			return {"text": give, "at": at, "key": "drop", "source": source}
		var both: String = _Strings.UI["prompt_pair"] % [_Strings.UI["prompt_slide_over"], _Strings.UI["prompt_format"] % ["drop", give]]
		return {"text": both, "at": at, "key": "take", "source": source}
	if not slow:
		return {}
	var key := "prompt_slide_over" if _riders[other] == 0 else "prompt_swap_seat"
	return {"text": _Strings.UI[key], "at": at, "key": "take", "source": source}


## How high over a seat's marker a head is: sitting in the cab, standing in the bed.
func _seat_head_up(seat: int) -> float:
	return Constants.CHEFTY_SEAT_PROMPT_UP.x if is_cab_seat(seat) else Constants.CHEFTY_SEAT_PROMPT_UP.y


static func _looked_at(view: Transform3D, target: Vector3) -> bool:
	var toward := target - view.origin
	var reach := toward.length()
	if reach > Constants.CHEFTY_SEAT_PROMPT_REACH or reach < 0.05:
		return false
	return (-view.basis.z).normalized().angle_to(toward / reach) < Constants.CHEFTY_SEAT_PROMPT_CONE


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
			# The autopilot (or the hand it's drawn as) has the wheel.
			if ground_speed() >= Constants.CHEFTY_ENTER_MAX_SPEED or _trip != Trip.NONE:
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
	# What the truck is really doing over the road: pinned against a wall with
	# the gas down is standing still, not a bail (p1-dash).
	var moving := ground_velocity()
	_riders[seat] = 0
	_send_seats()
	if player == null:
		return
	var spot := _exit_spot(seat)
	var facing := yaw()
	player.call("send_teleport", Transform3D(Basis(Vector3.UP, facing), spot))
	var bail := Vector2(moving.x, moving.z).length() > Constants.CHEFTY_EXIT_MAX_SPEED
	if bail:
		host_eject(peer_id, moving * Constants.CHEFTY_BAIL_SHARE + Vector3.UP * Constants.CHEFTY_BAIL_UP)
	_last_exits[peer_id] = {"at": spot, "bail": bail}
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
	# Its own run-over check would see them still standing on their seat (the
	# host's copy of them, until their flight comes back) and bonk them off it.
	_crash.call("host_spare", player)
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
	var lift := 0.1
	var candidates: Array[Vector3] = [
		flat * Vector3(side * Constants.CHEFTY_EXIT_SIDE, lift, z),
		flat * Vector3(-side * Constants.CHEFTY_EXIT_SIDE, lift, z),
		flat * Vector3(0.0, lift, Constants.CHEFTY_EXIT_BEHIND),
		flat * Constants.CHEFTY_EXIT_ROOF,
	]
	for candidate: Vector3 in candidates:
		if _clear_at(candidate):
			return candidate
	return candidates[0]


func _clear_at(at: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = Constants.CHEFTY_EXIT_CAPSULE.x
	capsule.height = Constants.CHEFTY_EXIT_CAPSULE.y
	query.shape = capsule
	# Its bottom just clear of the ground.
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3(0.0, capsule.height * 0.5 + 0.15, 0.0))
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
		# Nobody slides behind the wheel while a hand is driving.
		if ground_speed() >= Constants.CHEFTY_SEAT_SWAP_MAX_SPEED or _trip != Trip.NONE:
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


func _handle_chauffeur(peer_id: int) -> void:
	var seat := seat_of(peer_id)
	if seat < 0 or seat >= _Vehicles.CHEFTY_CAB_SEATS:
		return
	if _trip == Trip.CHAUFFEUR:
		# Pull over: the autopilot lets go, and with nobody driving Chefty brakes.
		_end_trip()
		return
	if chauffeur_action(peer_id) != "start":
		return
	var stop := _chauffeur_stop()
	_start_trip(Trip.CHAUFFEUR, int(stop["zone"]), stop["at"])


## Where a chauffeur heads: the picked job's curb while a yard is loaded and
## Chefty isn't parked at it, else home to the TruckPad, else nowhere ({}):
## {zone, at}.
func _chauffeur_stop() -> Dictionary:
	var here := _chassis.global_position
	var world := get_tree().get_first_node_in_group("world")
	var slot := world.get_node_or_null("%LotSlot") if world != null else null
	if slot != null and slot.get_child_count() > 0:
		var lot := _stop_for(Net.Zone.LOT)
		if _flat_distance(here, lot.origin) > Constants.CHEFTY_ARRIVE_RADIUS:
			return {"zone": Net.Zone.LOT, "at": lot}
	var home := _stop_for(Net.Zone.STORE)
	if _flat_distance(here, home.origin) > Constants.CHEFTY_ARRIVE_RADIUS:
		return {"zone": Net.Zone.STORE, "at": home}
	return {}


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


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
	_step_dev_script(delta)
	_crash.call("physics", delta)
	if Net.is_host():
		_host_step(delta)
	elif driver() == Net.local_peer_id() and driver() != 0 and _trip == Trip.NONE:
		if not _snap_waiting.is_empty():
			var snap := _snap_waiting
			_snap_waiting = {}
			_reconcile(snap["pos"], float(snap["yaw"]), snap["vel"], float(snap["yaw_rate"]), int(snap["ack"]))
		_predict_step(delta)
	_update_presentation(delta)


## Host: this tick's inputs (usually one; two when the driver's queue runs long),
## the sim, and a snapshot every other tick.
func _host_step(delta: float) -> void:
	if _auto != null:
		_autopilot_step(delta)
	else:
		# Two steps catch a client driver's long queue up; never for the host's own
		# drive or nobody's (a queue is only ever a client driver's).
		var remote := driver() != 0 and driver() != Net.local_peer_id()
		var steps := 2 if remote and _queue.size() > Constants.CHEFTY_INPUT_QUEUE_CATCHUP else 1
		for _step: int in steps:
			var input := _host_input()
			# A barrel roll jams the horn on for a while (chefty_crash.gd).
			_set_horn(bool(input.get("horn", false)) or bool(_crash.call("horn_stuck")))
			if driver() == Net.local_peer_id():
				_local_horn(bool(input.get("horn", false)))
			_host_sim(input, delta)
	_crash.call("host_every_tick", delta, _auto != null and (_warp or _swing_t >= 0.0))
	_draw_body(VehicleSim.body_transform(_chassis.global_position, _state))
	_tick += 1
	var every := maxi(1, int(round(float(Engine.physics_ticks_per_second) / float(Constants.CHEFTY_SNAP_HZ))))
	if _tick % every == 0:
		# Only to peers whose Chefty exists (it asked for the state from _ready):
		# an unreliable snapshot can outrun the world's spawn to a joining peer.
		for peer_id: int in _watchers.keys():
			if Net.peer_ids().has(peer_id):
				_rpc_snap.rpc_id(peer_id, Net.server_time(), _chassis.global_position, float(_state["yaw"]), _state["vel"], float(_state["yaw_rate"]), float(_state["steer"]), _sim_seq)
	_note_parking()


## Host: one step of the sim on these controls, then the crash rules on what it
## hit (chefty_crash.gd host_after_step).
func _host_sim(input: Dictionary, delta: float) -> void:
	var pre_vel: Vector3 = _state["vel"]
	var result := VehicleSim.step(_chassis, _state, input, _params, delta)
	_crash.call("host_after_step", result, pre_vel, input, delta)


## Host: the driver's next input. The host's own seated player drives directly; a
## client's come queued; with none for CHEFTY_INPUT_TIMEOUT, or nobody driving,
## Chefty brakes.
##
## Every tick of a client's drive stands for one of its inputs, in order
## (_sim_seq), so the pose a snapshot acks is the one the driver predicted after
## that input. When the next input is late (a long frame on either peer sends a
## burst after a gap) or lost, the host drives on the last one and that tick
## stands in for it; when it does come it only becomes the held input. Without
## this, a 0.15 s hitch ran ten ticks the driver never had and its truck was
## yanked 2 to 4 m forward (docs/DECISIONS.md, "Flaky gameplay tests").
func _host_input() -> Dictionary:
	var who := driver()
	if who == 0:
		return {"brake": true}
	if who == Net.local_peer_id():
		return _input_from_local()
	# The first input of a stint (or after a gap longer than any queue) starts
	# the count where the driver's is.
	if not _queue.is_empty() and (_held.is_empty() or int(_queue[0]["seq"]) - _sim_seq > Constants.CHEFTY_INPUT_QUEUE_MAX):
		_sim_seq = int(_queue[0]["seq"]) - 1
	# Inputs the host already drove on while they were on their way.
	while not _queue.is_empty() and int(_queue[0]["seq"]) <= _sim_seq:
		_take_input(_queue.pop_front())
		_made_good += 1
	if not _queue.is_empty() and int(_queue[0]["seq"]) == _sim_seq + 1:
		_take_input(_queue.pop_front())
		_sim_seq += 1
		return _held
	if _held.is_empty() or Time.get_ticks_msec() - _input_msec > int(Constants.CHEFTY_INPUT_TIMEOUT * 1000.0):
		# The link has stalled: Chefty brakes on the host's own say-so, and the
		# ticks stood in so far stand for nothing.
		_sim_seq = _ack
		return {"brake": true}
	# Late (nothing queued) or lost (the queue starts past it): drive on the last
	# input in its place, up to CHEFTY_STAND_IN_MAX_SECONDS ahead of the inputs.
	if not _queue.is_empty() or _sim_seq - _ack < int(round(Constants.CHEFTY_STAND_IN_MAX_SECONDS * Engine.physics_ticks_per_second)):
		_sim_seq += 1
		_stood_in += 1
	else:
		_forgiven += 1
	return _held


## Host: a client's input arrived at its turn (or after its stand-in drove).
func _take_input(next: Dictionary) -> void:
	_ack = int(next["seq"])
	_held = _unpack(next)
	_input_msec = Time.get_ticks_msec()


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
	# Where this input was first predicted to put Chefty. Replays on later
	# snapshots never rewrite it, so the error measured against the host's pose
	# after the same input is the whole round trip's, not the last two ticks'.
	_predicted[_seq] = _chassis.global_position
	_predicted.erase(_seq - PREDICTION_HISTORY)
	# The drawn pose carries what's left of the last correction, fading out.
	var fade := pow(0.5, delta / Constants.CHEFTY_CORRECTION_HALF_LIFE)
	_offset *= fade
	_yaw_offset *= fade
	var drawn := _state.duplicate()
	drawn["yaw"] = float(_state["yaw"]) + _yaw_offset
	_draw_body(VehicleSim.body_transform(_chassis.global_position + _offset, drawn))


## The driver's peer, on a snapshot: back to where the host had Chefty after the
## input it acked, the inputs since replayed, and the jump faded out of the view.
func _reconcile(pos: Vector3, yaw_now: float, vel: Vector3, yaw_rate: float, ack: int) -> void:
	if ack > _last_ack and _predicted.has(ack):
		var error := (_predicted[ack] as Vector3).distance_to(pos)
		_prediction_error_max = maxf(_prediction_error_max, error)
		_prediction_error_sum += error
		_prediction_error_count += 1
	elif ack > _seq:
		# The host's pose is after an input this peer hasn't sent yet: its frames ran
		# so long it lost physics ticks (past Godot's catch-up limit) and fell behind
		# real time, while the host stood in for it. Nothing here to compare it with.
		_acks_ahead += 1
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
	_view_state["lean_pitch"] = lerpf(float(_view_state["lean_pitch"]), clampf(accel.dot(forward) * Constants.CHEFTY_LEAN_PITCH, -lean, lean), clampf(dt * Constants.CHEFTY_LEAN_PITCH_RATE, 0.0, 1.0))
	_view_state["lean_roll"] = lerpf(float(_view_state["lean_roll"]), clampf(-turn * vel.dot(forward) * Constants.CHEFTY_LEAN_ROLL, -lean, lean), clampf(dt * Constants.CHEFTY_LEAN_ROLL_RATE, 0.0, 1.0))
	_draw_body(VehicleSim.body_transform(pos, _view_state))
	if snapped:
		_body.reset_physics_interpolation()


func _uses_view() -> bool:
	return not Net.is_host() and (driver() != Net.local_peer_id() or driver() == 0 or _trip != Trip.NONE)


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
		_snap_waiting = {}


## Host: Chefty came to a stop (it's parked) or set off. Parked by the job's
## yard is the crew arriving there (arrival detection: the homeowner's clock
## starts, the hands hop off), however it got there.
func _note_parking() -> void:
	var moving := speed() > Constants.CHEFTY_PARK_SPEED
	if _was_moving and not moving:
		parked.emit(_chassis.global_position)
		_check_arrival(_chassis.global_position)
		# Parked at the store: the junk in the bed is for Rusty's.
		if Constants.STORE_AREA.has_point(Vector2(_chassis.global_position.x, _chassis.global_position.z)):
			unload_junk()
	_was_moving = moving


## Host: parked within CHEFTY_ARRIVE_RADIUS of the loaded yard's curb point.
func _check_arrival(at: Vector3) -> void:
	var world := get_tree().get_first_node_in_group("world")
	if world == null or not world.has_method("on_crew_arrived"):
		return
	var slot := world.get_node_or_null("%LotSlot")
	if slot == null or slot.get_child_count() == 0:
		return
	if _flat_distance(at, _stop_for(Net.Zone.LOT).origin) <= Constants.CHEFTY_ARRIVE_RADIUS:
		world.call("on_crew_arrived")


## Where a trip to a zone parks: at the yard's curb facing along its street (the
## job site, wherever LotZone stands), or on the TruckPad nose to the road.
func _stop_for(zone: int) -> Transform3D:
	var world := get_tree().get_first_node_in_group("world")
	if zone == Net.Zone.LOT and world != null:
		var lot_zone := world.get_node_or_null("LotZone") as Node3D
		if lot_zone != null:
			return Transform3D(Basis(Vector3.UP, -PI * 0.5), lot_zone.global_transform * TownMap.CURB_POINT)
	return Transform3D(Basis(Vector3.UP, Constants.CHEFTY_PARK_YAW), Constants.CHEFTY_PARK_SPOT)


# ---------------------------------------------------------------- the autopilot

## Host: the autopilot takes the wheel for a trip to stop (a Transform3D, its
## heading used when a warp parks there).
func _start_trip(kind: int, zone: int, stop: Transform3D) -> void:
	_auto = VehicleAutopilot.new()
	_auto.start(VehicleAutopilot.plan(_chassis.global_position, stop.origin), stop.origin)
	_warp = _warp_forced or VehicleAutopilot.wants_warp()
	_swing_t = -1.0
	_trip_stop = stop
	_trip_clock = 0.0
	_trip_give_up = _auto.length() / Constants.AUTOPILOT_GIVE_UP_SPEED + Constants.AUTOPILOT_GIVE_UP_EXTRA
	var hands := hands_aboard()
	var label := str(hands[0].get("name", "")) if not hands.is_empty() and driver() == 0 else ""
	var quip := -1
	if kind == Trip.CHAUFFEUR and label != "":
		quip = _quip_rng.randi() % _Strings.CHAUFFEUR_QUIPS.size()
	_rpc_autopilot.rpc(kind, zone, label, quip)


## Host, every tick of a trip: the autopilot's controls through the sim (or the
## warp along the route), a trip that has gone on far too long warped the rest
## of the way, and the arrival.
func _autopilot_step(delta: float) -> void:
	# The chauffeur was fired (or went home at payroll) mid-trip: nobody's driving,
	# so Chefty pulls over rather than carry on by itself.
	if _trip == Trip.CHAUFFEUR and trip_label() == "":
		_end_trip()
		return
	_trip_clock += delta
	_set_horn(bool(_crash.call("horn_stuck")))
	if not _warp and _trip_clock > _trip_give_up:
		push_warning("Chefty's autopilot gave up driving after %.0f s; warping the rest" % _trip_clock)
		_auto.start(VehicleAutopilot.plan(_chassis.global_position, _trip_stop.origin), _trip_stop.origin)
		_warp = true
	if _swing_t >= 0.0:
		if _swing_step(delta):
			_arrive()
		return
	if _warp:
		_warp_step(delta)
	else:
		_host_sim(_auto.next_input(_state, _chassis.global_position, delta), delta)
		if _wants_swing():
			_swing_from = _chassis.global_position
			_swing_yaw = float(_state["yaw"])
			_swing_t = 0.0
			return
	if _auto.done:
		_arrive()


## Host: driving home to the TruckPad, the route comes in off County Road 9 nose
## first, facing the store. The last few meters are a handbrake swing instead,
## round to face the road, so Chefty is parked ready to go (Big Sal's signature
## move). Only for the TruckPad: a yard's curb is parked along the street
## whichever way you came.
func _wants_swing() -> bool:
	if _trip_zone != Net.Zone.STORE or _auto == null or _auto.remaining() > Constants.CHEFTY_HOME_SWING_METERS:
		return false
	var off := wrapf(_trip_stop.basis.get_euler().y - float(_state["yaw"]), -PI, PI)
	return absf(off) > Constants.CHEFTY_HOME_SWING_MIN_ANGLE


## Host: one tick of the swing: sliding onto the stop while the tail comes round
## (out to the side by CHEFTY_HOME_SWING_BULGE), the heading turning the short way
## to the stop's. True once it's parked there. It moves the chassis like a warp,
## so the pose goes out in the snapshots and riders stay in their seats.
func _swing_step(delta: float) -> bool:
	_swing_t = minf(_swing_t + delta / Constants.CHEFTY_HOME_SWING_SECONDS, 1.0)
	var target := _trip_stop.origin
	var turn := wrapf(_trip_stop.basis.get_euler().y - _swing_yaw, -PI, PI)
	var travel := Vector3(target.x - _swing_from.x, 0.0, target.z - _swing_from.z)
	var side := travel.normalized().cross(Vector3.UP) * signf(turn) if travel.length() > 0.01 else Vector3.ZERO
	var slide := smoothstep(0.0, 1.0, _swing_t)
	var spin := smoothstep(0.08, 0.85, _swing_t)
	var at := _swing_from.lerp(target, slide) + side * Constants.CHEFTY_HOME_SWING_BULGE * sin(PI * _swing_t)
	at.y = target.y
	var before := _chassis.global_position
	var heading := _swing_yaw + turn * spin
	_chassis.global_position = at
	_chassis.global_rotation = Vector3(0.0, heading, 0.0)
	_state["vel"] = (at - before) / maxf(delta, 0.0001)
	_state["yaw_rate"] = wrapf(heading - float(_state["yaw"]), -PI, PI) / maxf(delta, 0.0001)
	_state["yaw"] = heading
	_state["vy"] = 0.0
	_state["air"] = false
	# Sideways the whole way round: the skid.
	_state["slip"] = Constants.CHEFTY_SKID_SLIP * 2.0 if _swing_t < 0.9 else 0.0
	if _swing_t < 1.0:
		return false
	_swing_t = -1.0
	_state["slip"] = 0.0
	_place(target, _trip_stop.basis.get_euler().y)
	return true


## Warp mode: the chassis follows the route at AUTOPILOT_TEST_WARP times cruise,
## facing along it, and parks exactly on the stop.
func _warp_step(delta: float) -> void:
	var pace := Constants.AUTOPILOT_TEST_WARP * Constants.AUTOPILOT_CRUISE
	var step := _auto.warp_step(pace * delta)
	var dir: Vector3 = step["dir"]
	if bool(step["done"]):
		_place(_trip_stop.origin, _trip_stop.basis.get_euler().y)
		return
	var heading := float(_state["yaw"])
	if dir.length() > 0.01:
		heading = lerp_angle(heading, VehicleAutopilot.yaw_of(dir), clampf(delta * Constants.AUTOPILOT_WARP_TURN_RATE, 0.0, 1.0))
	var at: Vector3 = step["pos"]
	_chassis.global_position = Vector3(at.x, _trip_stop.origin.y, at.z)
	_chassis.global_rotation = Vector3(0.0, heading, 0.0)
	_state["yaw"] = heading
	_state["vel"] = dir * pace
	_state["yaw_rate"] = 0.0
	_state["vy"] = 0.0
	_state["air"] = false


## Host: the trip's over. A depart() trip lets everyone off into its zone (a
## teleport, like the legacy ride) and tells the world; a chauffeur just parks,
## and its riders' zones follow where Chefty stopped.
func _arrive() -> void:
	var kind := _trip
	var zone := _trip_zone
	_end_trip()
	if kind == Trip.DEPART:
		var riders_now: Array[int] = []
		for id: int in _riders:
			if id != 0:
				riders_now.append(id)
		_riders.fill(0)
		_send_seats()
		for id: int in riders_now:
			Net.move_player_to_zone(id, zone as Net.Zone)
		var world := get_tree().get_first_node_in_group("world")
		if world != null and world.has_method("on_ride_arrived"):
			world.call("on_ride_arrived", zone)
	else:
		for id: int in _riders:
			if id != 0:
				_note_zone(id, _chassis.global_position)


## Host: the autopilot lets go (arrived, or the chauffeur pulled over).
func _end_trip() -> void:
	_auto = null
	_warp = false
	_swing_t = -1.0
	_rpc_autopilot.rpc(Trip.NONE, 0, "", -1)


## The steering wheel, the label, the sounds.
func _update_presentation(delta: float) -> void:
	var steer := float(_state.get("steer", 0.0))
	if driver() == Net.local_peer_id() and driver() != 0 and _trip == Trip.NONE:
		steer = float(_input_from_local().get("steer", 0.0))
	_Vehicles.set_steering(_look, steer)
	if _body != null and delta > 0.0:
		var heading := _body.global_rotation.y
		_drawn_yaw_rate = lerpf(_drawn_yaw_rate, wrapf(heading - _drawn_yaw, -PI, PI) / delta, clampf(delta * Constants.CHEFTY_SKID_YAW_SMOOTHING, 0.0, 1.0))
		_drawn_yaw = heading
	_update_ground(delta)
	var dash := _dash()
	if dash != null:
		dash.call("set_reading", ground_speed(), odometer_miles(), _dents, engine_on())
	_update_sound(delta)
	if _quip_label != null:
		_quip_left = maxf(_quip_left - delta, 0.0)
		_quip_label.visible = _quip_left > 0.0
	_update_hands(delta)
	var offered := chauffeur_action(Net.local_peer_id()) if seat_of(Net.local_peer_id()) >= 0 else ""
	if offered != _chauffeur_last:
		_chauffeur_last = offered
		if offered != "":
			_chauffeur_seen.append(offered)


## Every peer, each physics tick: how far Chefty really went over the road since
## the last one (the host's chassis, the truth; elsewhere the truck as drawn),
## smoothed into the ground velocity, and onto the odometer. A jump faster than
## any drive (placed, towed home) is neither. The host tells everyone its count
## every CHEFTY_ODOMETER_SYNC_M.
func _update_ground(delta: float) -> void:
	if delta <= 0.0 or _body == null:
		return
	var here := _chassis.global_position if Net.is_host() else _body.global_position
	here.y = 0.0
	var raw := Vector3.ZERO
	if _ground_last != Vector3.INF:
		var moved := here - _ground_last
		if moved.length() / delta < Constants.CHEFTY_GROUND_TELEPORT_MPS:
			raw = moved / delta
			_odometer_m += moved.length()
		else:
			raw = _ground_vel
	_ground_last = here
	_ground_vel = _ground_vel.lerp(raw, 1.0 - exp(-Constants.CHEFTY_GROUND_SPEED_RATE * delta))
	if Net.is_host() and _odometer_m - _odometer_sent >= Constants.CHEFTY_ODOMETER_SYNC_M:
		_odometer_sent = _odometer_m
		_rpc_odometer.rpc(_odometer_m)


## The hands riding along, drawn from cosmetic_riders() (rebuilt only when who
## sits where changes; nothing is drawn headless), each waving now and then.
func _update_hands(delta: float) -> void:
	var riding := cosmetic_riders()
	var built := str(riding)
	if built != _hands_built:
		_hands_built = built
		for figure: Node3D in _hand_figures:
			if is_instance_valid(figure):
				figure.queue_free()
		_hand_figures.clear()
		if DisplayServer.get_name() != "headless" and _seats != null:
			for entry: Dictionary in riding:
				_hand_figures.append(_build_hand(entry))
	for figure: Node3D in _hand_figures:
		if not is_instance_valid(figure) or int(figure.get_meta("seat", 0)) == SEAT_DRIVER:
			continue
		var wait := float(figure.get_meta("wave_in", 0.0)) - delta
		if wait <= 0.0:
			var body := figure.get_node_or_null("CartoonBody")
			if body != null:
				body.call("gesture", "wave")
			wait = _wave_rng.randf_range(Constants.CHEFTY_HAND_WAVE_SECONDS.x, Constants.CHEFTY_HAND_WAVE_SECONDS.y)
		figure.set_meta("wave_in", wait)


## One hand in a seat: a crew-orange cartoon body (like npcs/crew_hand.gd's),
## sitting in the cab or standing in the bed, with their name over them.
func _build_hand(entry: Dictionary) -> Node3D:
	var seat := int(entry["seat"])
	var holder := Node3D.new()
	holder.name = "HandRider%d" % seat
	holder.set_meta("seat", seat)
	holder.set_meta("wave_in", _wave_rng.randf_range(Constants.CHEFTY_HAND_FIRST_WAVE, Constants.CHEFTY_HAND_WAVE_SECONDS.x))
	_seats.get_child(seat).add_child(holder)
	var body := _CartoonBody.new()
	body.name = "CartoonBody"
	body.dress_from_seed(int(entry["look"]))
	body.shirt = Color(0.93, 0.5, 0.18)
	body.hat_style = "cap"
	body.hat_color = Color(0.2, 0.32, 0.22)
	holder.add_child(body)
	body.build()
	body.sit(1 if is_cab_seat(seat) else 2)
	var tag := Label3D.new()
	tag.name = "Name"
	tag.text = str(entry["name"])
	tag.font_size = 40
	tag.outline_size = 8
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = Color(1.0, 0.85, 0.55)
	tag.position = Vector3(0.0, 2.2, 0.0)
	holder.add_child(tag)
	return holder


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
			"chauffeur":
				request_chauffeur()
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
	var report := {
		"riders": riders_list,
		"driver": driver(),
		"prediction_error_max_m": _prediction_error_max,
		"prediction_error_mean_m": _prediction_error_sum / maxf(float(_prediction_error_count), 1.0),
		"prediction_samples": _prediction_error_count,
		"acks_ahead": _acks_ahead,
		"corrections": _corrections,
		"stood_in": _stood_in,
		"made_good": _made_good,
		"forgiven": _forgiven,
		"horn_seen": _horn_log.duplicate(),
		"dents": _dents,
		"bag_count": bag_count(),
		"speed": speed(),
		"ground_speed": ground_speed(),
		"odometer_m": _odometer_m,
		"dash": dash_reading(),
		"pos": [at.x, at.y, at.z],
		"yaw": float(_state["yaw"]),
		"trip": _trip,
		"trip_label": trip_label(),
		"trips_seen": _trips_seen,
		"chauffeur_seen": _chauffeur_seen.duplicate(),
		"cosmetic": _cosmetic_report(),
		"job_value": _job_value,
	}
	# The crash comedy's counts (chefty_crash.gd report: crashes_seen, runovers_me, ...).
	report.merge(_crash.call("report") as Dictionary)
	return report


## The hands riding along as [seat, name] pairs, for CI's host-equals-client check.
func _cosmetic_report() -> Array:
	var out: Array = []
	for entry: Dictionary in cosmetic_riders():
		out.append([int(entry["seat"]), str(entry["name"])])
	return out


## Host, tests: make every trip warp (true) or follow the --warp-rides and
## automated-run default (false).
func dev_set_warp(on: bool) -> void:
	_warp_forced = on


## Host, tests: how far the current trip has left to go along its route (m),
## or -1 with no trip.
func dev_trip_left() -> float:
	return _auto.remaining() if _auto != null else -1.0


## Host, tests: this peer's last exit {at, bail}, or {}.
func dev_last_exit(peer_id: int) -> Dictionary:
	return (_last_exits.get(peer_id, {}) as Dictionary).duplicate()


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


## Host, scenarios: sit this peer in this seat (free, or theirs already), wherever
## they stand. True when they're in it.
func dev_seat(peer_id: int, seat: int) -> bool:
	if not Net.is_host() or seat < 0 or seat >= _riders.size() or is_riding():
		return false
	if seat_of(peer_id) == seat:
		return true
	if _riders[seat] != 0 or seat_of(peer_id) >= 0:
		return false
	_riders[seat] = peer_id
	_stow(peer_id)
	_send_seats()
	return true


# ---------------------------------------------------------------- sound

## Audio's contract (gap-specs/critic.md C13): audio/vehicle_sound.gd reads this.
## {on, throttle (-1..1), speed (m/s), skidding}.
func engine_state() -> Dictionary:
	var input := _input_from_local() if driver() == Net.local_peer_id() else _held
	var throttle := float(input.get("throttle", 0.0)) if driver() != 0 else 0.0
	if _trip != Trip.NONE:
		# The autopilot's pedal isn't sent; the engine works as hard as it's going.
		throttle = clampf(speed() / Constants.AUTOPILOT_CRUISE, 0.0, 1.0)
	return {
		"on": driver() != 0 or is_moving() or _trip != Trip.NONE,
		"throttle": throttle,
		"speed": speed(),
		# The sim's slide where it runs (the host, the driver), and on everyone's
		# screen a truck turning faster than any grip allows (a drift, the swing home).
		"skidding": float(_state.get("slip", 0.0)) > Constants.CHEFTY_SKID_SLIP or (absf(_drawn_yaw_rate) > Constants.CHEFTY_SKID_YAW_RATE and speed() > Constants.CHEFTY_PARK_SPEED),
	}


## The engine and skid: audio/vehicle_sound.gd when it exists (audio chunk 7),
## else a plain engine loop pitched by speed and the skid one-shot. Nothing
## headless. vehicle_sound sits under Body, so it moves with the drawn truck, and
## reads parent.engine_state() (critic C13): Body (vehicle_body.gd) hands that
## through to here. Its state_source Callable is set too, before it's in the tree.
func _attach_sound() -> void:
	if Net.is_automated() or DisplayServer.get_name() == "headless":
		return
	if ResourceLoader.exists("res://audio/vehicle_sound.gd"):
		var vehicle_sound: Node = load("res://audio/vehicle_sound.gd").new()
		vehicle_sound.name = "VehicleSound"
		if "state_source" in vehicle_sound:
			vehicle_sound.set("state_source", engine_state)
		_body.add_child(vehicle_sound)
	else:
		_engine = _sound_loop("engine_idle", "Engine")
		_own_skid = true
	_horn_player = _sound_loop("horn_loop", "Horn")


func _sound_loop(id: String, node_name: String) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = node_name
	player.stream = _Sfx.looped(id)
	player.bus = _SoundBank.bus(id)
	player.unit_size = Constants.SFX_UNIT_SIZE
	player.max_distance = Constants.CHEFTY_SOUND_MAX_DISTANCE
	player.volume_db = -80.0
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
			_engine.pitch_scale = lerpf(Constants.CHEFTY_ENGINE_PITCH.x, Constants.CHEFTY_ENGINE_PITCH.y, share) + absf(float(state["throttle"])) * Constants.CHEFTY_ENGINE_THROTTLE_PITCH
			_engine.volume_db = lerpf(Constants.CHEFTY_ENGINE_DB.x, Constants.CHEFTY_ENGINE_DB.y, share)
		elif _engine.playing:
			_engine.stop()
	if _own_skid:
		# The skid one-shot when a slide starts, and again while it lasts.
		var state := engine_state()
		var share := clampf(float(state["speed"]) / Constants.CHEFTY_TOP_SPEED, 0.0, 1.0)
		if bool(state["skidding"]) and share > Constants.CHEFTY_SKID_MIN_SPEED_SHARE:
			_skid_left -= delta
			if _skid_left <= 0.0:
				_play_on("skid")
				_skid_left = Constants.CHEFTY_SKID_REPEAT
		else:
			_skid_left = 0.0
	if _horn_player != null and _horn_player.stream != null:
		var honking := _horn or (driver() == Net.local_peer_id() and driver() != 0 and bool(_input_from_local().get("horn", false)))
		_horn_held = _horn_held + delta if honking else 0.0
		var loop := _horn_held > Constants.CHEFTY_HORN_LOOP_AFTER
		if loop and not _horn_player.playing:
			_horn_player.volume_db = Constants.CHEFTY_HORN_LOOP_DB
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
	_label.text = _Strings.UI["ride_chefty_label"] % [bag_count(), Constants.TRUCK_BAG_CAPACITY]
	if _bed_load != null:
		_bed_load.call("set_count", bag_count())


# ---------------------------------------------------------------- RPCs

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _rpc_input(seq: int, throttle: float, steer: float, flags: int) -> void:
	if not Net.is_host() or multiplayer.get_remote_sender_id() != driver():
		return
	if seq <= _ack or (not _queue.is_empty() and seq <= int(_queue[_queue.size() - 1]["seq"])):
		return
	_queue.append({"seq": seq, "throttle": clampf(throttle, -1.0, 1.0), "steer": clampf(steer, -1.0, 1.0), "flags": flags})
	# A stalled link must not let the queue grow without end.
	while _queue.size() > Constants.CHEFTY_INPUT_QUEUE_MAX:
		_queue.pop_front()


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _rpc_snap(t: float, pos: Vector3, yaw_now: float, vel: Vector3, yaw_rate: float, steer: float, ack: int) -> void:
	_view.call("add_snap", t, pos, yaw_now, vel)
	_state["steer"] = steer
	if driver() == Net.local_peer_id() and driver() != 0:
		# Reconciled on the next physics tick, not here: the replay steps through
		# move_and_slide, which only moves by the physics step inside a physics
		# frame (out here it'd use the render frame's delta and fall behind).
		if _snap_waiting.is_empty() or ack >= int(_snap_waiting["ack"]):
			_snap_waiting = {"pos": pos, "yaw": yaw_now, "vel": vel, "yaw_rate": yaw_rate, "ack": ack}
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
	# Against the seats this last said, not _riders: on the host _riders already
	# holds the change (it's sent from there), so a driver leaving never cleared
	# their queued inputs, and the host never heard the door (p1-dash: with a
	# backlog left over, the host's own drive ran two sim steps a tick, Chefty at
	# twice the speed its needle and sim said).
	var before := _seats_said.duplicate()
	var before_driver := _seats_said[SEAT_DRIVER] if _seats_said.size() > 0 else 0
	_riders = seated.duplicate()
	_seats_said = _riders.duplicate()
	_riders.resize(Constants.CHEFTY_SEATS)
	if Net.is_host() and driver_id != before_driver:
		# A new driver starts a fresh input stream.
		_queue.clear()
		_held = {}
		_ack = 0
		_sim_seq = 0
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
	if job_value > _job_value and _bed_load != null:
		_bed_load.call("on_value_added", job_value - _job_value)
	elif job_value > _job_value and _body != null:
		_MoneyPopup.pop(get_tree(), _body.global_position + Vector3(0.0, 3.0, 0.0), job_value - _job_value)
	_job_bags = job_bags
	_job_value = job_value
	_spent_bags = spent_bags
	_refresh_label()


## Bags flew out of the bed (chefty_crash.gd host_spill): the new counts. The
## heap loses its top bags at once (they're the bags in the air now), with a
## pomf-pomf.
@rpc("authority", "call_local", "reliable")
func _rpc_spill(job_bags: int, job_value: int, spent_bags: int) -> void:
	_job_bags = job_bags
	_job_value = job_value
	_spent_bags = spent_bags
	if _bed_load != null and _bed_load.has_method("spill_to"):
		_bed_load.call("spill_to", bag_count())
	if _label != null:
		_label.text = _Strings.UI["ride_chefty_label"] % [bag_count(), Constants.TRUCK_BAG_CAPACITY]
	_crash.call("note_spill", bed_transform() * Vector3(0.0, 1.8, 0.7))


## Chefty's dents changed outside a crash (Marty's Body Shop: 0): every peer.
@rpc("authority", "call_local", "reliable")
func _rpc_dents(count: int) -> void:
	var had := _dents
	apply_dents(count)
	# The dents pop out under Marty's nephew's mallet.
	if count < had:
		_play_on("bonk")


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_chauffeur() -> void:
	if Net.is_host():
		_handle_chauffeur(multiplayer.get_remote_sender_id())


## The autopilot took the wheel (kind a Trip) or let go (Trip.NONE): who's drawn
## driving, and the chauffeur's quip (an index into Strings.CHAUFFEUR_QUIPS, the
## host's pick, or -1). Cosmetic and for is_riding(); the pose comes in snapshots.
@rpc("authority", "call_local", "reliable")
func _rpc_autopilot(kind: int, zone: int, label: String, quip: int) -> void:
	_trip = kind
	_trip_zone = zone
	_trip_label = label if kind != Trip.NONE else ""
	if kind != Trip.NONE:
		_trips_seen += 1
		_play_on("truck_horn")
	if quip >= 0 and label != "" and not _Strings.CHAUFFEUR_QUIPS.is_empty():
		_quip_label.text = _Strings.CHAUFFEUR_QUIPS[quip % _Strings.CHAUFFEUR_QUIPS.size()] % [label, label]
		_quip_left = Constants.CHAUFFEUR_QUIP_SECONDS
	_refresh_role()


@rpc("authority", "call_remote", "reliable")
func _rpc_placed(at: Vector3, yaw_now: float) -> void:
	_place(at, yaw_now)
	_view.call("clear")


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_state() -> void:
	if not Net.is_host():
		return
	_watchers[multiplayer.get_remote_sender_id()] = true
	_rpc_state.rpc_id(multiplayer.get_remote_sender_id(), _riders, driver(), _job_bags, _job_value, _spent_bags, _dents, _horn, _trip, _trip_zone, _trip_label, _chassis.global_position, float(_state["yaw"]))
	if _junk_bed != null:
		_junk_bed.call("send_to", multiplayer.get_remote_sender_id())
	_rpc_odometer.rpc_id(multiplayer.get_remote_sender_id(), _odometer_m)


## The host's odometer (meters the crew has driven), every CHEFTY_ODOMETER_SYNC_M
## and to a joiner. This peer's own count of the drawn truck's travel runs a hair
## behind the host's (it draws 100 ms back), so it takes the host's when that's
## ahead, and the host's outright when the two have drifted apart.
@rpc("authority", "call_remote", "reliable")
func _rpc_odometer(meters: float) -> void:
	if absf(_odometer_m - meters) > Constants.CHEFTY_ODOMETER_RESYNC_M:
		_odometer_m = meters
	else:
		_odometer_m = maxf(_odometer_m, meters)


## A late joiner learns who sits where, what's in the bed, whether the autopilot
## is driving, and where Chefty is.
@rpc("authority", "call_remote", "reliable")
func _rpc_state(seated: PackedInt32Array, _driver_id: int, job_bags: int, job_value: int, spent_bags: int, dents: int, horn: bool, trip: int, trip_zone: int, trip_label: String, at: Vector3, yaw_now: float) -> void:
	_riders = seated.duplicate()
	_riders.resize(Constants.CHEFTY_SEATS)
	_seats_said = _riders.duplicate()
	_job_bags = job_bags
	_job_value = job_value
	_spent_bags = spent_bags
	if _bed_load != null:
		_bed_load.call("sync_count", job_bags + spent_bags)
	_horn = horn
	_trip = trip
	_trip_zone = trip_zone
	_trip_label = trip_label
	_place(at, yaw_now)
	apply_dents(dents)
	_refresh_role()
	_refresh_label()
