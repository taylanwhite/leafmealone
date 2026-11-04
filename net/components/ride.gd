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

## p1-depart, the honk-and-wait (docs/GAME.md "Leaving together"): Chefty parked
## with the crew climbing in, honking, until _leave_at (server time). The host
## decides who sits and when it goes (levels/world.gd _tick_boarding); every
## peer knows the riders and seats from the RPCs and draws the same climbs.
## _riders may hold 0 for a seat left empty, so nobody's seat moves when someone
## hops out.
var _boarding: bool = false
var _leave_at: float = 0.0
## Climbing in: peer -> [from (world), at (server time)].
var _climbs: Dictionary = {}
## Hopping out over the tailgate: seat -> [peer, at (server time)].
var _exits: Dictionary = {}
var _last_call_played: bool = false
## Every peer: when it goes, on this peer's own game clock (_local_now).
var _local_leave: float = 0.0
## Local: the hold on E to leave now, armed once E was let go after sitting.
var _hold: float = 0.0
var _hold_armed: bool = false
var _asked_to_go: bool = false
## Local: jump was down last frame (a fresh press hops you out).
var _jump_held: bool = false
## Host: a boarder hopped out (world.gd keeps them from being sat right back down).
signal hopped_out(peer_id: int)


func _ready() -> void:
	_build()
	# Chefty's riders, which player.gd seats every frame.
	add_to_group("rides")
	if name == "Chefty":
		add_to_group("chefty")
		# "Hold E: hit the road" while you sit in the bed waiting (p1-depart).
		add_to_group("prompt_sources")
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
	if not Net.is_host() or _riding or _seated(peer_ids).is_empty():
		return
	_rpc_depart.rpc(Net.server_time(), peer_ids, destination_zone, RIDE_DURATION_SECONDS)
	for peer_id: int in _seated(peer_ids):
		Net.move_player_to_zone(peer_id, Net.Zone.TRANSIT)


func is_riding() -> bool:
	return _riding


## The peers in a riders list, without the empty seats.
static func _seated(riders: Array) -> Array[int]:
	var out: Array[int] = []
	for entry: Variant in riders:
		if int(entry) != 0:
			out.append(int(entry))
	return out


## The seat this peer rides in right now, or -1. Every peer knows the riders
## from the departure message, so every peer can place every rider. While the
## honk-and-wait runs the boarders have seats too, and someone hopping out over
## the tailgate has seat_count() + their old seat until they land.
func seat_of(peer_id: int) -> int:
	if _riding or _boarding:
		for index: int in _riders.size():
			if int(_riders[index]) == peer_id:
				return index
	for seat: Variant in _exits:
		var exit: Array = _exits[seat]
		if int(exit[0]) == peer_id and _local_now() - float(exit[1]) < float(exit[2]):
			return seat_count() + int(seat)
	return -1


# ---------------------------------------------------------------- p1-depart: the honk-and-wait

## Host: Chefty honks and waits for the crew, then goes to destination_zone at
## the latest after wait seconds (levels/world.gd decides who sits and when).
func open_boarding(destination_zone: int, wait: float) -> void:
	if not Net.is_host() or _riding or _boarding:
		return
	_rpc_boarding.rpc(destination_zone, Net.server_time() + wait, wait)


func is_boarding() -> bool:
	return _boarding


## Where the waiting truck is going (a Net.Zone).
func boarding_destination() -> int:
	return _destination


## Server time the waiting truck goes on its own.
func leave_at() -> float:
	return _leave_at


## Whether anyone aboard is still in mid-hop into the bed (on this peer's clock;
## the host waits for it before it pulls away).
func climbing() -> bool:
	for peer_id: Variant in _climbs:
		var climb: Array = _climbs[peer_id]
		if _riders.has(peer_id) and _local_now() - float(climb[1]) < float(climb[2]):
			return true
	return false


## Who's sitting in the bed now (not the empty seats).
func boarders() -> Array[int]:
	return _seated(_riders) if _boarding else ([] as Array[int])


## Host: peer_id climbs in from where they stand (from). False when there's no
## window, they're already in, or the bed is full.
func board(peer_id: int, from: Vector3) -> bool:
	if not Net.is_host() or not _boarding or _riders.has(peer_id):
		return false
	var seat := _free_seat()
	if seat < 0:
		return false
	_rpc_boarded.rpc(peer_id, seat, from)
	return true


## Host: peer_id hops back out over the tailgate.
func unboard(peer_id: int) -> void:
	if not Net.is_host() or not _boarding or not _riders.has(peer_id):
		return
	_rpc_unboarded.rpc(peer_id, true)
	hopped_out.emit(peer_id)


## Host: peer_id left the game mid-wait: their seat just empties (levels/world.gd).
func drop_boarder(peer_id: int) -> void:
	if Net.is_host() and _boarding and _riders.has(peer_id):
		_rpc_unboarded.rpc(peer_id, false)


## Host: the trip's off: everyone aboard hops back out, and the window closes.
func cancel_boarding() -> void:
	close_boarding()


## Host: the window closes with nobody going. Whoever's still aboard hops back
## out over the tailgate first (closed with someone seated, say at 2 AM, they
## stayed glued to the seat with E and jump dead: review of p1-depart).
func close_boarding() -> void:
	if not Net.is_host() or not _boarding:
		return
	for peer_id: int in boarders():
		_rpc_unboarded.rpc(peer_id, true)
	_rpc_boarding_closed.rpc()


## Whether Chefty is parked at Homie Depot (the store end of the road) rather
## than out at the yard.
func parked_at_store() -> bool:
	return not _riding and _parked_along < 0.5


## Host: the window's over; go with whoever's aboard (their seats as they sat).
func leave_now() -> void:
	if not Net.is_host() or not _boarding:
		return
	if boarders().is_empty():
		close_boarding()
		return
	depart(_riders.duplicate(), _destination)


func _free_seat() -> int:
	for seat: int in seat_count():
		var leaving := _exits.has(seat) and _local_now() - float((_exits[seat] as Array)[1]) < float((_exits[seat] as Array)[2])
		if (seat >= _riders.size() or int(_riders[seat]) == 0) and not leaving:
			return seat
	return -1


## This peer's game clock (s): the climbs, hops and the last call run on it,
## cosmetic and local, so a client's clock estimate never stalls them.
static func _local_now() -> float:
	return float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)


## Where someone climbing (in or out) is this moment: an eased hop from a to b.
static func _hop(a: Vector3, b: Vector3, t: float) -> Vector3:
	var eased := t * t * (3.0 - 2.0 * t)
	return a.lerp(b, eased) + Vector3.UP * Constants.CHEFTY_BOARD_CLIMB_HOP * 4.0 * t * (1.0 - t)


## Where a boarder hopping out of seat lands: behind the tailgate, their side.
func _step_down_spot(seat: int) -> Vector3:
	var x := -0.5 + float(seat % 2)
	return bed_transform() * Vector3(x, 0.0, Constants.CHEFTY_BOARD_STEP_DOWN_Z)


func _process(delta: float) -> void:
	if not _boarding:
		_hold = 0.0
		_hold_armed = false
		_asked_to_go = false
		_jump_held = Input.is_action_pressed("jump")
		return
	var now := _local_now()
	# The last call: one more honk just before it goes (every peer on its own
	# game clock from when it heard the first: a client's server-time estimate
	# can trail the host's by most of a second on a busy machine).
	if not _last_call_played and now >= _local_leave - Constants.CHEFTY_BOARD_LAST_CALL_SECONDS and now < _local_leave:
		_last_call_played = true
		_honk()
	var me := Net.local_peer_id()
	var jump := Input.is_action_pressed("jump")
	var jumped := jump and not _jump_held
	_jump_held = jump
	if not _riders.has(me) or Net.is_automated():
		_hold = 0.0
		_hold_armed = false
		return
	if jumped:
		_ask(false)
		return
	# Holding E leaves now; the press that sat you down doesn't count.
	if not Input.is_action_pressed("interact"):
		_hold_armed = true
		_hold = 0.0
	elif _hold_armed and not _asked_to_go:
		_hold += delta
		if _hold >= Constants.CHEFTY_BOARD_HOLD_SECONDS:
			_asked_to_go = true
			_ask(true)


## Local: go now (go) or let me out.
func _ask(go: bool) -> void:
	if Net.is_host():
		_handle_ask(Net.local_peer_id(), go)
	else:
		_rpc_request_board_choice.rpc_id(1, go)


func _handle_ask(peer_id: int, go: bool) -> void:
	if not _boarding or not _riders.has(peer_id):
		return
	if not go:
		unboard(peer_id)
		return
	var world := get_tree().get_first_node_in_group("world")
	if world != null and world.has_method("boarding_go_now"):
		world.call("boarding_go_now")
	else:
		leave_now()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_board_choice(go: bool) -> void:
	if Net.is_host():
		_handle_ask(multiplayer.get_remote_sender_id(), go)


## While you sit in the bed waiting: hold E to go now. Anchored just ahead of
## your own view, so it's there wherever you look.
func prompt() -> Dictionary:
	if not _boarding or not _riders.has(Net.local_peer_id()) or _asked_to_go:
		return {}
	var camera := get_viewport().get_camera_3d()
	var ahead := bed_transform() * Vector3(0.0, 2.2, 0.0)
	if camera != null:
		ahead = camera.global_position - camera.global_basis.z * 2.5 - camera.global_basis.y * 0.6
	return {"text": _Strings.UI["prompt_go_now"], "plain": true, "at": ahead}


## Every peer: honks this Chefty made for the honk-and-wait (for --depart-test).
var honks: int = 0


func _honk() -> void:
	honks += 1
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null and _body != null:
		sfx.call("play_on", "truck_horn", _body)


@rpc("authority", "call_local", "reliable")
func _rpc_boarding(destination_zone: int, leave_at_time: float, wait: float) -> void:
	_boarding = true
	_destination = destination_zone
	_leave_at = leave_at_time
	_local_leave = _local_now() + wait
	_riders = []
	_climbs.clear()
	_exits.clear()
	_last_call_played = false
	_asked_to_go = false
	# The honk is the whole announcement: Chefty's going, get in.
	_honk()


@rpc("authority", "call_local", "reliable")
func _rpc_boarded(peer_id: int, seat: int, from: Vector3) -> void:
	if not _boarding:
		return
	while _riders.size() <= seat:
		_riders.append(0)
	_riders[seat] = peer_id
	_exits.erase(seat)
	# The hop starts where this peer draws them now (the host's copy of a
	# client lags its own by the ping: from there the climb began with a jump
	# back on the climber's screen, play: rec_dep_1p frame 212, 0.73 m).
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			var visual := node.get_node_or_null("Visual") as Node3D
			var here := visual.global_position if visual != null else (node as Node3D).global_position
			if here.distance_to(from) <= Constants.CHEFTY_BOARD_CLIMB_FROM_MAX:
				from = here
	_climbs.erase(peer_id)
	if from.distance_to(seat_transform(seat).origin) <= Constants.CHEFTY_BOARD_CLIMB_FROM_MAX:
		# On this peer's own game clock, from when it hears of it: timed by the
		# host's clock a client's hop stood still, then started late, by as much
		# as its server-time estimate trailed (play: rec_dep2_fr frames 236-258).
		# Farther off, the hop takes longer (no 13 m/s leap from the pad's edge:
		# rec_dep3_1p frame 240).
		var reach := from.distance_to(seat_transform(seat).origin)
		_climbs[peer_id] = [from, _local_now(), Constants.CHEFTY_BOARD_CLIMB_SECONDS * maxf(1.0, reach / Constants.CHEFTY_BOARD_CLIMB_REACH)]
	else:
		_climbs.erase(peer_id)
	if peer_id == Net.local_peer_id():
		_hold_armed = false
		_hold = 0.0
		_seat_local_player()
	# The thump is the landing in the bed, at the end of the hop.
	if _climbs.has(peer_id):
		_sound_later("bed_thump", float((_climbs[peer_id] as Array)[2]), Callable(), true)


## hops false: they left the game, the seat just empties.
@rpc("authority", "call_local", "reliable")
func _rpc_unboarded(peer_id: int, hops: bool) -> void:
	var seat := _riders.find(peer_id)
	if seat < 0:
		return
	# Out from wherever they are now (still climbing in, they turn round mid-hop).
	var from := seat_transform(seat).origin
	_riders[seat] = 0
	_climbs.erase(peer_id)
	if not hops:
		return
	# The front seats are farther from the tailgate: a longer hop, not a faster one.
	var hop := Constants.CHEFTY_BOARD_CLIMB_SECONDS * maxf(1.0, from.distance_to(_step_down_spot(seat)) / Constants.CHEFTY_BOARD_CLIMB_REACH)
	_exits[seat] = [peer_id, _local_now(), hop, from]
	if peer_id == Net.local_peer_id():
		_asked_to_go = false
		for node: Node in get_tree().get_nodes_in_group("players"):
			if node.name == str(peer_id) and node.has_method("clear_riding"):
				node.call("clear_riding")
	# Feet on the ground at the end of the hop, behind the tailgate.
	_sound_later("hop_land", hop, _step_down_spot.bind(seat), false)


## A sound after delay seconds: on the truck (on_truck), or at where() then.
func _sound_later(id: String, delay: float, where: Callable, on_truck: bool) -> void:
	get_tree().create_timer(delay, false, true).timeout.connect(func() -> void:
		var sfx := get_tree().get_first_node_in_group("sfx") if is_inside_tree() else null
		if sfx == null:
			return
		if on_truck and _body != null:
			sfx.call("play_on", id, _body)
		elif where.is_valid():
			sfx.call("play_at", id, where.call())
	)


@rpc("authority", "call_remote", "reliable")
func _rpc_boarding_state(destination_zone: int, leave_at_time: float, left: float, riders: Array) -> void:
	_boarding = true
	_destination = destination_zone
	_leave_at = leave_at_time
	_local_leave = _local_now() + left
	_riders = riders
	_last_call_played = left <= Constants.CHEFTY_BOARD_LAST_CALL_SECONDS


@rpc("authority", "call_local", "reliable")
func _rpc_boarding_closed() -> void:
	_boarding = false
	_riders = []
	_climbs.clear()
	# Nobody stays seated in a truck that isn't going (close_boarding hops them
	# out first; this catches a seat whose hop-out never arrived).
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.has_method("clear_riding") and node.get("_ride") == self:
			node.call("clear_riding")


func bag_count() -> int:
	return _bags


func occupied_count() -> int:
	return _seated(_riders).size()


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
	var count := _seats.get_child_count()
	# Hopping out of seat (index - count), over the tailgate (seat_of).
	if index >= count:
		var from_seat := index - count
		var seat_xf := (_seats.get_child(clampi(from_seat, 0, count - 1)) as Node3D).global_transform
		var exit: Array = _exits.get(from_seat, [0, -1000.0, 1.0, seat_xf.origin])
		var t := clampf((_local_now() - float(exit[1])) / float(exit[2]), 0.0, 1.0)
		return Transform3D(seat_xf.basis, _hop(exit[3] as Vector3, _step_down_spot(from_seat), t))
	var seat := _seats.get_child(clampi(index, 0, count - 1)) as Node3D
	var xf := seat.global_transform
	# Climbing in from where they stood (the honk-and-wait).
	var peer_id := int(_riders[index]) if index < _riders.size() else 0
	if _climbs.has(peer_id):
		var climb: Array = _climbs[peer_id]
		var t := (_local_now() - float(climb[1])) / float(climb[2])
		if t < 1.0:
			return Transform3D(xf.basis, _hop(climb[0] as Vector3, xf.origin, clampf(t, 0.0, 1.0)))
	return xf


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
	# landed on the same one, inside each other). Empty seats (0) are skipped.
	for peer_id: int in _seated(riders):
		Net.move_player_to_zone(peer_id, destination as Net.Zone, &"", false)
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
		# Integration (P1): p1-arrive's outward-facing rail seats win over
		# p1-depart's two-by-two spread; back to back on opposite rails also
		# keeps a waiting crew from standing nose to nose (rec_dep3_fr 252-261).
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
	# The honk-and-wait is over: the boarders keep their seats (and a climb
	# still finishing finishes on the move).
	_boarding = false
	_exits.clear()
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
		# Joined mid honk-and-wait: who's sitting where (no honk, no climbs).
		if _boarding:
			_rpc_boarding_state.rpc_id(multiplayer.get_remote_sender_id(), _destination, _leave_at, _leave_at - Net.server_time(), _riders)
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
	_climbs.clear()
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
