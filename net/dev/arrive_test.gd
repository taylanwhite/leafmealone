extends Node

## Authority: both peers run it (--arrive-test on host and client; p1-arrive,
## docs/GAME.md "Stepping off Chefty"). The host and the client ride Chefty to
## the job yard and back to Homie Depot together. Each arrival:
##   a. both riders were in the bed, on opposite rails, facing out (back to back);
##   b. each hops down to their own spot by the truck, at least
##      STEP_DOWN_SPACING apart, outside the bed, inside the zone, and on the
##      host's roster in it;
##   c. nothing pops: on its own peer a body never moves more than MAX_TICK_STEP
##      in a physics tick, and each peer's drawn view of the other never jumps
##      more than MAX_FRAME_JUMP in a frame, from the seat to the ground, and
##      never goes back the way it came (MAX_DRAWN_REGRESS: a rider drawn sliding
##      back up the road at seat height, their own truck trailing, then forward);
##   d. each faces where step_down.gd says (the house, the store's doors) and
##      never a solid within STEP_DOWN_FACE_CLEAR;
##   e. the peers agree on every rider's spot: each peer works out the whole
##      arrival (ride.gd arrival_spots) and checks the other rider landed on the
##      spot it has for them (each peer steps only its own rider down).
## Then room to stand: the host puts both of them on one spot at the store, and
## within PERSONAL_SPACE_WAIT they stand apart. Each step prints an [ArriveTest]
## line; CI needs both peers' ok.

const _StepDown = preload("res://net/components/step_down.gd")
const _PersonalSpace = preload("res://net/components/personal_space.gd")
const _Vehicles = preload("res://props/vehicles.gd")
## A physics tick's largest move for a body on its own peer (m): the hop moves
## about 0.15 m a tick at its fastest; the old teleport to the spawn was 20 m.
const MAX_TICK_STEP: float = 0.4
## A frame's largest jump of the other player as drawn here (m), over what the
## hop's top speed (m/s) covers in that frame.
const MAX_FRAME_JUMP: float = 0.2
const MAX_DRAWN_SPEED: float = 8.0
## How far the other player as drawn here may get from where they end up, past
## the closest they'd been (m): a hop only ever closes in.
const MAX_DRAWN_REGRESS: float = 0.15
## How far a rider may stand from the spot the other peer worked out for them (m).
const MAX_SPOT_DISAGREE: float = 0.15
## How long after arriving everyone has landed (s).
const SETTLE_SECONDS: float = 2.0
const PERSONAL_SPACE_WAIT: float = 2.5
## On the way to the yard the client's truck runs this far (s) behind the host's,
## as a client's clock that trails the host's does: it's still short of the curb
## when the host's arrives, so its rider is still seated while the host already
## draws them stepping down (the review's slide back up the road at seat height).
const CLIENT_TRAIL_SECONDS: float = 0.5

static var result: Dictionary = {}

var _started: bool = false
var _ok: bool = true
## Watching an arrival: the largest steps seen, and the last positions.
var _watching: bool = false
var _max_tick: float = 0.0
var _max_frame: float = 0.0
var _last_own := Vector3.INF
var _last_other := Vector3.INF
var _watch_msec: int = 0
var _max_frame_note: String = ""
var _trace: PackedStringArray = []
## The other player's drawn places (flat) while watching, for the regress check.
var _drawn_path: PackedVector2Array = []
## The own body's lowest height over the bed's rail or tailgate top while its
## feet were above the wall (m, negative: through it), for the review's clip.
var _wall_gap: float = INF
## The client: arrivals seen, by zone.
var _arrivals: int = 0
var _was_riding: bool = false


func _ready() -> void:
	result = {}
	# After every other node's frame (the smoothers'), so a frame's drawn pose is
	# read as it's drawn, not half-updated.
	process_priority = 1000


func _process(delta: float) -> void:
	if _watching:
		var other := _other_visual()
		if other != null:
			var at := other.global_position
			if Time.get_ticks_msec() - _watch_msec < 400:
				_trace.append("%d:%s|%s|%.2f" % [Time.get_ticks_msec() - _watch_msec, at.snapped(Vector3.ONE * 0.01), _other_player().global_position.snapped(Vector3.ONE * 0.01), float(_other_player().get("body_yaw"))])
			# A jump past what the hop's own speed covers in this frame (a slow frame on
			# a busy machine moves it further) is a pop.
			var beyond := at.distance_to(_last_other) - MAX_DRAWN_SPEED * delta if _last_other != Vector3.INF else 0.0
			if _last_other != Vector3.INF and beyond > _max_frame:
				_max_frame = beyond
				_max_frame_note = "at %.2f s, %s to %s" % [float(Time.get_ticks_msec() - _watch_msec) / 1000.0, _last_other, at]
			_last_other = at
			_drawn_path.append(Vector2(at.x, at.z))
	if _started or _own_player() == null or _ride() == null:
		return
	if Net.peer_ids().size() < 2 or _other_player() == null:
		return
	_started = true
	if Net.is_host():
		_run_host()
	else:
		_run_client()


func _physics_process(_delta: float) -> void:
	if not _watching:
		return
	var me := _own_player()
	if me == null:
		return
	if _last_own != Vector3.INF:
		_max_tick = maxf(_max_tick, me.global_position.distance_to(_last_own))
	_last_own = me.global_position
	# Over the bed's walls, the feet are over their top (the hop goes over the
	# rail and the tailgate, never through them).
	var body := _ride().get_node_or_null("Body") as Node3D
	if body != null:
		var local := body.global_transform.affine_inverse() * me.global_position
		var flat := Vector2(local.x, local.z)
		if _Vehicles.CHEFTY_BED_OUTER.has_point(flat) and not _Vehicles.CHEFTY_BED_INNER.has_point(flat):
			_wall_gap = minf(_wall_gap, local.y - _Vehicles.CHEFTY_BED_WALL_TOP)


func _run_host() -> void:
	# The client's world, its yard and its own test node come up.
	await get_tree().create_timer(3.0).timeout
	var client := _other_player().name.to_int()
	await _ride_and_check([1, client], Net.Zone.LOT, "the yard")
	await get_tree().create_timer(1.0).timeout
	await _ride_and_check([1, client], Net.Zone.STORE, "Homie Depot")
	# The client judges its own landing first (it sees the arrival a little later).
	await get_tree().create_timer(1.5).timeout
	await _personal_space(client)
	_finish()


func _run_client() -> void:
	# The host drives the test; this side judges its own body and its view of the host.
	var waited := 0.0
	while _arrivals < 2 and waited < 50.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
		var riding := int(_ride().call("seat_of", Net.local_peer_id())) >= 0
		if riding and not _was_riding:
			await get_tree().physics_frame
			_check_seats("client")
			if _arrivals == 0:
				_ride().set("_start_time", float(_ride().get("_start_time")) + CLIENT_TRAIL_SECONDS)
		if _was_riding and not riding:
			_arrivals += 1
			_begin_watch()
			await get_tree().create_timer(SETTLE_SECONDS).timeout
			_end_watch("client, arrival %d" % _arrivals)
			_check_own_landing("client, arrival %d" % _arrivals, Net.Zone.LOT if _arrivals == 1 else Net.Zone.STORE)
			_check_agree("client, arrival %d" % _arrivals)
		_was_riding = riding
	if _arrivals < 2:
		_verdict(false, "client saw %d of 2 arrivals" % _arrivals)
	# The host judges room to stand; the client's run ends with the host's.
	_finish()


func _ride_and_check(riders: Array, zone: int, label: String) -> void:
	var ride := _ride()
	ride.call("depart", riders, zone)
	await get_tree().create_timer(0.5).timeout
	_check_seats("host")
	while bool(ride.call("is_riding")):
		await get_tree().physics_frame
	_begin_watch()
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	_end_watch("host, to %s" % label)
	_check_own_landing("host, to %s" % label, zone)
	_check_agree("host, to %s" % label)
	# Both stand on their own spots, by the truck.
	var me := _own_player()
	var other := _other_player()
	var apart := _flat(me.global_position, other.global_position)
	var truck: Vector3 = ride.call("body_position")
	var near := _flat(me.global_position, truck) < 5.0 and _flat(other.global_position, truck) < 5.0
	var out_of_bed := not bool(ride.call("in_bed", me.global_position + Vector3.UP * 0.5)) and not bool(ride.call("in_bed", other.global_position + Vector3.UP * 0.5))
	var zoned := Net.player_zone(1) == zone and Net.player_zone(other.name.to_int()) == zone
	_verdict(apart >= Constants.STEP_DOWN_SPACING * 0.9 and near and out_of_bed and zoned, "%s: riders %.2f m apart, by the truck %s, out of the bed %s, in the zone %s" % [label, apart, near, out_of_bed, zoned])


## While seated: on opposite rails, facing out, back to back.
func _check_seats(who: String) -> void:
	var ride := _ride()
	var mine := int(ride.call("seat_of", Net.local_peer_id()))
	if mine < 0:
		_verdict(false, "%s: not seated" % who)
		return
	var seat: Transform3D = ride.call("seat_transform", mine)
	var truck: Transform3D = (ride.get_node("Body") as Node3D).global_transform
	var local := truck.affine_inverse() * seat.origin
	var out := (truck.basis.inverse() * (-seat.basis.z)).normalized()
	var facing_out := signf(out.x) == signf(local.x) and absf(out.x) > 0.9
	_verdict(facing_out and absf(local.x) > 0.4, "%s seated: seat %d at x %.2f facing out %s" % [who, mine, local.x, facing_out])


## This peer's own body after landing: where step_down.gd would face it, and
## never into a solid within arm's length.
func _check_own_landing(who: String, zone: int) -> void:
	var me := _own_player()
	var world := get_tree().get_first_node_in_group("world")
	var look: Vector3 = world.call("arrival_look_point", zone)
	var space := me.get_world_3d().direct_space_state
	var props_near: Array = world.call("arrival_obstacles", zone, (_ride().call("body_position") as Vector3), Constants.STEP_DOWN_PROP_REACH)
	var expected := _StepDown.landing_facing(space, _ride().call("body_position"), me.global_position, look, [], props_near)
	var yaw := float(me.get("body_yaw"))
	var off := absf(angle_difference(yaw, expected.get_euler().y))
	var ahead := Basis(Vector3.UP, yaw) * Vector3.FORWARD * Constants.STEP_DOWN_FACE_CLEAR
	var query := PhysicsRayQueryParameters3D.create(me.global_position + Vector3.UP * 1.5, me.global_position + Vector3.UP * 1.5 + ahead, 1)
	var hit := space.intersect_ray(query)
	var blocked := not hit.is_empty() and hit["collider"] is StaticBody3D
	var stood := not bool(me.call("is_stepping_down")) and me.is_on_floor()
	# No drawn prop (a lamp post, a hydrant: no collider) at arm's length.
	var props: Array = world.call("arrival_obstacles", zone, me.global_position, Constants.STEP_DOWN_PROP_REACH)
	var nearest := _StepDown.prop_distance(me.global_position, props)
	var roomy := nearest >= Constants.STEP_DOWN_POST_ROOM * 0.9
	var in_view := not _StepDown.view_clear(null, me.global_position, yaw, [], props)
	_verdict(off < 0.35 and not blocked and not in_view and stood and roomy, "%s: facing %.2f rad off the planned look, view blocked %s (a prop %s), landed %s, nearest of %d props %.1f m" % [who, off, blocked, in_view, stood, props.size(), nearest])


func _personal_space(client: int) -> void:
	_PersonalSpace.reset_stats()
	var me := _own_player()
	var other := _other_player()
	var spot := Transform3D(Basis.IDENTITY, (get_tree().get_first_node_in_group("world").get_node("%TruckPad") as Node3D).global_position + Vector3(-6.0, 0.1, -6.0))
	me.call("apply_network_teleport", spot)
	other.call("send_teleport", spot)
	var waited := 0.0
	var apart := 0.0
	while waited < PERSONAL_SPACE_WAIT:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
		apart = _flat(me.global_position, other.global_position)
	_verdict(apart >= Constants.PERSONAL_SPACE_RADIUS * 0.85 and int(_PersonalSpace.stats["nudges"]) > 0, "room to stand: put on one spot, %.2f m apart %.1f s later (%d nudges, peer %d)" % [apart, PERSONAL_SPACE_WAIT, int(_PersonalSpace.stats["nudges"]), client])


func _begin_watch() -> void:
	_watching = true
	_watch_msec = Time.get_ticks_msec()
	_max_frame_note = ""
	_trace = []
	_drawn_path = PackedVector2Array()
	_wall_gap = INF
	_max_tick = 0.0
	_max_frame = 0.0
	_last_own = Vector3.INF
	_last_other = Vector3.INF


func _end_watch(who: String) -> void:
	_watching = false
	# Back the way it came: further from where it ends up than it had already been.
	var regress := 0.0
	if not _drawn_path.is_empty():
		var end := _drawn_path[_drawn_path.size() - 1]
		var closest := INF
		for at: Vector2 in _drawn_path:
			var left := at.distance_to(end)
			if closest != INF:
				regress = maxf(regress, left - closest)
			closest = minf(closest, left)
	if _max_frame > MAX_FRAME_JUMP or regress > MAX_DRAWN_REGRESS:
		print("[ArriveTest] trace: %s" % " ".join(_trace))
	var over_wall := _wall_gap == INF or _wall_gap >= 0.0
	_verdict(_max_tick <= MAX_TICK_STEP and _max_frame <= MAX_FRAME_JUMP and regress <= MAX_DRAWN_REGRESS and over_wall, "%s: own body's largest tick step %.2f m, the other's largest drawn jump %.2f m past a hop's speed (%s), drawn going back %.2f m, feet over the bed's wall by %.2f m" % [who, _max_tick, _max_frame, _max_frame_note, regress, _wall_gap])


## Every rider stands on the spot this peer works out for them: the peers agree.
func _check_agree(who: String) -> void:
	var ride := _ride()
	var riders: Array = ride.call("landed_riders")
	var spots: Array = ride.call("arrival_spots", riders)
	var worst := 0.0
	var notes: PackedStringArray = []
	for index: int in riders.size():
		var rider := _player_by_id(int(riders[index]))
		if rider == null or index >= spots.size():
			worst = INF
			continue
		var off := _flat(rider.global_position, (spots[index] as Transform3D).origin)
		worst = maxf(worst, off)
		notes.append("%d %.2f m" % [int(riders[index]), off])
	_verdict(riders.size() >= 2 and worst <= MAX_SPOT_DISAGREE, "%s: every rider on the spot this peer has for them (%s)" % [who, ", ".join(notes)])


func _verdict(ok: bool, line: String) -> void:
	_ok = _ok and ok
	print("[ArriveTest] %s: %s" % [line, "ok" if ok else "FAIL"])


func _finish() -> void:
	result = {"ok": _ok, "done": true}
	print("[ArriveTest] all ok: %s" % _ok)


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _ride() -> Node:
	var world := get_tree().get_first_node_in_group("world")
	return world.get_node_or_null("Rides/Chefty") if world != null else null


func _own_player() -> CharacterBody3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as CharacterBody3D
	return null


func _other_player() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name != str(Net.local_peer_id()):
			return node as Node3D
	return null


func _player_by_id(peer_id: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node as Node3D
	return null


func _other_visual() -> Node3D:
	var other := _other_player()
	return other.get_node_or_null("Visual") as Node3D if other != null else null
