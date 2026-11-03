extends Node

## Authority: host. --drive-test (with --town-map, and a client named Target
## joined, CI adds --sim-lag=120 to both) drives the drivable Chefty
## (net/components/chefty_drive.gd, driving chunk C1) through the real paths:
##   a. seats: Chefty on the TruckPad, the client asks for the driver's seat
##      (a scripted "enter" from _rpc_dev_script) and the host's player hops in
##      the bed; the host sees the client driving and itself in a bed seat.
##   b. 4 s of full throttle from the client: Chefty (the host's, the truth)
##      went at least 25 m along +X and reached at least 12 m/s.
##   c. 2 s of steering right: the heading turned at least 0.6 rad.
##   d. stopped with the brakes and the handbrake.
##   e. the client holds the horn for a second: the host saw it go on, then off.
##   f. the client gets out at a stop: off the seat, standing within 3.5 m of
##      Chefty, and in Zone.TOWN.
##   g. the host gets in to drive and the client rides in the bed (the client
##      draws Chefty through vehicle_view; CI gates its ride_wobble_m), then the
##      host floors it.
##   h. the client, then the host, bail out at speed: each exit is a bail, each
##      was thrown, and each landed at least 2 m from where they got out.
##   i. the client sits in the bed again and is caught (run director
##      note_capture, released at once): it's out of its seat.
##   j-l. the autopilot (driving chunk C2, _autopilot_steps): a real depart()
##      drive to a yard's curb, a hired hand chauffeuring and pulling over, and
##      a warped depart() home.
##   m-o. the chase camera never inside anything (driving chunk E2, _camera_steps):
##      swung past a post, a tree planted behind the truck, a wall backed into.
## The client's prediction (how far its predicted Chefty was from the host's
## after the same input, "drive".prediction_error_max_m), the riders both peers
## see, and the client's snapshot gaps are checked by CI from the probe reports.
## Each step prints a [DriveTest] line.

const _Vehicles = preload("res://props/vehicles.gd")
const _Trees = preload("res://props/trees.gd")
const _ViewBlockers = preload("res://props/view_blockers.gd")
## m-n: the chase camera's lens never moves farther than this in one frame (the
## recorder's cam_snap line, net/dev/recorder.gd CAM_SNAP_METERS).
const CAMERA_STEP_MAX: float = 1.2

static var result: Dictionary = {}

var _started: bool = false


func _process(_delta: float) -> void:
	if _started or not Net.is_host():
		return
	var world := get_tree().get_first_node_in_group("world")
	if world == null or get_tree().get_first_node_in_group("chefty") == null:
		return
	_started = true
	_run(world)


func _run(world: Node) -> void:
	if not bool(world.call("is_town_map")):
		_finish(false, ["not the connected town: run with --town-map"])
		return
	var chefty := get_tree().get_first_node_in_group("chefty")
	if not chefty.is_in_group("vehicles"):
		_finish(false, ["Chefty isn't the drivable one"])
		return
	var waited := 0.0
	while (Net.peer_ids().size() < 2 or _client_id() == 0 or _player(_client_id()) == null) and waited < 15.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	var client := _client_id()
	if client == 0 or _player(client) == null:
		_finish(false, ["no client joined"])
		return
	# Let the client's world, Chefty and player settle in.
	await get_tree().create_timer(1.5).timeout
	var problems: Array[String] = []
	var host := Net.local_peer_id()
	# a. Seats.
	chefty.call("dev_place", Constants.CHEFTY_PARK_SPOT, Constants.CHEFTY_PARK_YAW)
	await get_tree().create_timer(0.3).timeout
	var at: Transform3D = chefty.call("body_transform")
	var door := at * _Vehicles.CHEFTY_DRIVER_DOOR
	var gate := at * _Vehicles.CHEFTY_TAILGATE
	# A slow client (a window compiling shaders) may not have its Chefty yet, so
	# walk it to the door and ask again until it's in.
	waited = 0.0
	while (int(chefty.call("driver")) != client or int(chefty.call("seat_of", host)) < 2) and waited < 12.0:
		# A client dropped while it loaded (ENet times a peer out after about 5 s
		# without a word; seen with 40 Godots on the machine): say so and finish.
		if _player(client) == null:
			_finish(false, ["the client left before it drove"])
			return
		if int(chefty.call("driver")) != client:
			_player(client).call("send_teleport", Transform3D(Basis.IDENTITY, door + Vector3(0.0, 0.1, 0.0)))
		if int(chefty.call("seat_of", host)) < 0:
			_player(host).call("send_teleport", Transform3D(Basis.IDENTITY, gate + Vector3(0.0, 0.1, 0.0)))
		await get_tree().create_timer(0.8).timeout
		if int(chefty.call("seat_of", host)) < 0:
			chefty.call("request_enter", 2)
		if int(chefty.call("driver")) != client:
			chefty.call("dev_script", client, [{"do": "enter", "kind": 0}])
		await get_tree().create_timer(1.2).timeout
		waited += 2.0
	_verdict(int(chefty.call("driver")) == client and int(chefty.call("seat_of", host)) >= 2, "a. the client drives (%d), the host rides in bed seat %d" % [int(chefty.call("driver")), int(chefty.call("seat_of", host))], problems)
	if int(chefty.call("driver")) != client:
		_finish(false, problems)
		return
	await get_tree().create_timer(0.5).timeout
	# b. Full throttle along County Road 9.
	var start: Dictionary = chefty.call("sim_pose")
	var top := 0.0
	chefty.call("dev_script", client, [{"seconds": 4.0, "throttle": 1.0}])
	var clock := 0.0
	while clock < 4.5:
		await get_tree().physics_frame
		clock += get_physics_process_delta_time()
		top = maxf(top, float(chefty.call("speed")))
	var after: Dictionary = chefty.call("sim_pose")
	var moved := (after["pos"] as Vector3).x - (start["pos"] as Vector3).x
	_verdict(moved >= 25.0 and top >= 12.0, "b. full throttle: %.1f m along +X, top speed %.1f m/s" % [moved, top], problems)
	# c. Steer right.
	var yaw_before := float((chefty.call("sim_pose") as Dictionary)["yaw"])
	chefty.call("dev_script", client, [{"seconds": 2.0, "throttle": 0.3, "steer": 1.0}])
	await get_tree().create_timer(2.4).timeout
	var yaw_after := float((chefty.call("sim_pose") as Dictionary)["yaw"])
	var turned := absf(wrapf(yaw_after - yaw_before, -PI, PI))
	_verdict(turned >= 0.6, "c. steering right turned %.2f rad" % turned, problems)
	# d. Stop.
	chefty.call("dev_script", client, [{"seconds": 1.0, "throttle": -1.0}, {"seconds": 4.0, "handbrake": true}])
	waited = 0.0
	while float(chefty.call("speed")) > 0.3 and waited < 6.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	_verdict(float(chefty.call("speed")) <= 0.3, "d. stopped (%.2f m/s)" % float(chefty.call("speed")), problems)
	# e. The horn.
	var heard := (chefty.call("dev_report") as Dictionary)["horn_seen"] as Array
	var before_horn := heard.size()
	chefty.call("dev_script", client, [{"seconds": 1.0, "horn": true}, {"seconds": 0.2}])
	await get_tree().create_timer(1.8).timeout
	heard = (chefty.call("dev_report") as Dictionary)["horn_seen"] as Array
	var new_horn := heard.slice(before_horn)
	_verdict(new_horn.size() >= 2 and bool(new_horn[0]) and not bool(new_horn[new_horn.size() - 1]), "e. the host heard the horn: %s" % [new_horn], problems)
	# f. Out at a stop.
	chefty.call("dev_script", client, [{"do": "exit"}])
	waited = 0.0
	while int(chefty.call("seat_of", client)) >= 0 and waited < 3.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	await get_tree().create_timer(1.0).timeout
	var standing := _player(client)
	var gap := standing.global_position.distance_to(chefty.call("body_position")) if standing != null else INF
	var zone := Net.player_zone(client)
	_verdict(int(chefty.call("seat_of", client)) < 0 and gap <= 3.5 and zone == Net.Zone.TOWN, "f. out: seat %d, %.1f m from Chefty, zone %s" % [int(chefty.call("seat_of", client)), gap, Net.Zone.keys()[zone]], problems)
	# g. The other way round: the host drives and the client rides in the bed, so
	# the client draws Chefty through vehicle_view (100 ms behind) with a rider on
	# it (CI gates the client's ride_wobble_m).
	chefty.call("request_exit")
	await get_tree().create_timer(0.5).timeout
	chefty.call("dev_place", Constants.CHEFTY_PARK_SPOT, Constants.CHEFTY_PARK_YAW)
	await get_tree().create_timer(0.3).timeout
	at = chefty.call("body_transform")
	door = at * _Vehicles.CHEFTY_DRIVER_DOOR
	gate = at * _Vehicles.CHEFTY_TAILGATE
	waited = 0.0
	while (int(chefty.call("driver")) != host or int(chefty.call("seat_of", client)) < 2) and waited < 12.0:
		if int(chefty.call("driver")) != host:
			_player(host).call("send_teleport", Transform3D(Basis.IDENTITY, door + Vector3(0.0, 0.1, 0.0)))
		if int(chefty.call("seat_of", client)) < 0:
			_player(client).call("send_teleport", Transform3D(Basis.IDENTITY, gate + Vector3(0.0, 0.1, 0.0)))
		await get_tree().create_timer(0.8).timeout
		if int(chefty.call("driver")) != host:
			chefty.call("request_enter", 0)
		if int(chefty.call("seat_of", client)) < 0:
			chefty.call("dev_script", client, [{"do": "enter", "kind": 2}])
		await get_tree().create_timer(1.2).timeout
		waited += 2.0
	_verdict(int(chefty.call("driver")) == host and int(chefty.call("seat_of", client)) >= 2, "g. the host drives (%d), the client rides in bed seat %d" % [int(chefty.call("driver")), int(chefty.call("seat_of", client))], problems)
	if int(chefty.call("driver")) != host or int(chefty.call("seat_of", client)) < 2:
		_finish(false, problems)
		return
	await get_tree().create_timer(0.5).timeout
	chefty.call("dev_script", host, [{"seconds": 3.5, "throttle": 1.0}, {"seconds": 1.0, "throttle": -1.0}, {"seconds": 3.0, "handbrake": true}])
	await get_tree().create_timer(2.6).timeout
	# h. Both bail out at speed, the client first (its throw comes over the
	# network), then the host (its own, in the same call as the seat clearing):
	# each is thrown clear, not just set down by the door.
	var bail_speed := float(chefty.call("speed"))
	chefty.call("dev_script", client, [{"do": "exit"}])
	await get_tree().create_timer(0.3).timeout
	chefty.call("request_exit")
	var seen_thrown := {client: false, host: false}
	clock = 0.0
	while clock < 2.2:
		await get_tree().physics_frame
		clock += get_physics_process_delta_time()
		for peer_id: int in [client, host]:
			var bailed := _player(peer_id)
			if bailed != null and int(chefty.call("seat_of", peer_id)) < 0:
				seen_thrown[peer_id] = bool(seen_thrown[peer_id]) or bool(bailed.get("thrown"))
	for peer_id: int in [client, host]:
		var exit: Dictionary = chefty.call("dev_last_exit", peer_id)
		var bailed := _player(peer_id)
		# Where they came down, against where they got out: a bail flings you.
		var flew := 0.0
		if bailed != null and not exit.is_empty():
			var from: Vector3 = exit["at"]
			flew = Vector2(bailed.global_position.x - from.x, bailed.global_position.z - from.z).length()
		var who := "client" if peer_id == client else "host"
		_verdict(bool(exit.get("bail", false)) and bool(seen_thrown[peer_id]) and flew >= 2.0, "h. the %s bailed (Chefty at %.1f m/s): bail %s, thrown %s, landed %.1f m from the door" % [who, bail_speed, exit.get("bail", false), seen_thrown[peer_id], flew], problems)
	waited = 0.0
	while (chefty.call("dev_script_playing") or float(chefty.call("speed")) > 0.3) and waited < 6.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	# i. Caught sitting in the bed: the capture takes them out of the seat (else
	# they'd stay glued to Chefty while the van drives them off). Released again
	# at once, so no van leaves and the client stays in the town.
	at = chefty.call("body_transform")
	gate = at * _Vehicles.CHEFTY_TAILGATE
	waited = 0.0
	while int(chefty.call("seat_of", client)) < 0 and waited < 8.0:
		_player(client).call("send_teleport", Transform3D(Basis.IDENTITY, gate + Vector3(0.0, 0.1, 0.0)))
		await get_tree().create_timer(0.8).timeout
		chefty.call("dev_script", client, [{"do": "enter", "kind": 2}])
		await get_tree().create_timer(1.2).timeout
		waited += 2.0
	var seated_before := int(chefty.call("seat_of", client))
	var director := get_tree().get_first_node_in_group("run_director")
	if director != null:
		director.call("note_capture", client)
		director.call("release_peer", client)
	await get_tree().create_timer(0.5).timeout
	_verdict(director != null and seated_before >= 2 and int(chefty.call("seat_of", client)) < 0, "i. caught in bed seat %d: now in seat %d" % [seated_before, int(chefty.call("seat_of", client))], problems)
	await _autopilot_steps(world, chefty, host, problems)
	await _camera_steps(chefty, host, problems)
	# Give the client's report time to see the same seats and zone.
	await get_tree().create_timer(1.0).timeout
	_finish(problems.is_empty(), problems)


## Driving chunk C2: the autopilot, depart(), the chauffeur and warp mode.
##   j. depart([host], LOT) to Maple Row's first yard (the job site placed there
##      on the host; driving chunk D will place it from the lot's spawn data),
##      really driven: the host rides in a seat in TRANSIT, Chefty parks within
##      CHEFTY_ARRIVE_RADIUS of the curb point, the host gets off into LOT, the
##      homeowner's clock starts, and it took the time a drive takes.
##   k. a hired hand (Big Sal) rides in a bed seat; the client in shotgun lets
##      them drive (its own G, through _rpc_request_chauffeur): the autopilot
##      heads home with Big Sal drawn at the wheel, the client's G again pulls
##      over, F still slides the client over to the wheel, and the client gets
##      out on the street.
##   l. warp mode: depart([host], STORE) follows the route at warp speed, parks
##      on the TruckPad, lets the host off into STORE and frees the yard; Big Sal
##      is back in a bed seat.
func _autopilot_steps(world: Node, chefty: Node, host: int, problems: Array[String]) -> void:
	var house := TownMap.test_site_house()
	world.call("place_job_site", TownMap.yard_transform(house), house)
	var curb := TownMap.curb_point(house)
	if int(chefty.call("seat_of", host)) >= 0:
		chefty.call("request_exit")
		await get_tree().create_timer(0.5).timeout
	chefty.call("dev_place", Constants.CHEFTY_PARK_SPOT, Constants.CHEFTY_PARK_YAW)
	await get_tree().create_timer(0.5).timeout
	var clock_before := bool(Campaign.get("_job_clock_started"))
	chefty.call("depart", [host], Net.Zone.LOT)
	var riding := bool(chefty.call("is_riding")) and int(chefty.call("seat_of", host)) >= 0 and Net.player_zone(host) == Net.Zone.TRANSIT
	var top := 0.0
	var took := 0.0
	while bool(chefty.call("is_riding")) and took < 75.0:
		await get_tree().physics_frame
		took += get_physics_process_delta_time()
		top = maxf(top, float(chefty.call("speed")))
	var at: Vector3 = (chefty.call("sim_pose") as Dictionary)["pos"]
	var gap := Vector2(at.x - curb.x, at.z - curb.z).length()
	var clock_after := bool(Campaign.get("_job_clock_started"))
	_verdict(riding and not bool(chefty.call("is_riding")) and gap <= Constants.CHEFTY_ARRIVE_RADIUS and Net.player_zone(host) == Net.Zone.LOT and int(chefty.call("seat_of", host)) < 0 and not clock_before and clock_after and top >= 10.0 and took >= 15.0,
		"j. depart to house %d: rode %s, %.1f s at up to %.1f m/s, parked %.1f m from the curb, host zone %s, seat %d, job clock %s -> %s" % [house, riding, took, top, gap, Net.Zone.keys()[Net.player_zone(host)], int(chefty.call("seat_of", host)), clock_before, clock_after], problems)
	# k. The chauffeur.
	var hires := world.get_node_or_null("Hires")
	if hires == null:
		_verdict(false, "k. no Hires node", problems)
		return
	hires.call("dev_add_hand", "Big Sal")
	await get_tree().create_timer(0.5).timeout
	# The client takes shotgun and asks through its own G path (a scripted
	# "chauffeur", _rpc_request_chauffeur); CI checks the client's own
	# chauffeur_action offered "start" then "stop" (drive.chauffeur_seen).
	var client := _client_id()
	var waited := 0.0
	while int(chefty.call("seat_of", client)) != 1 and waited < 10.0:
		var door: Vector3 = (chefty.call("body_transform") as Transform3D) * _Vehicles.CHEFTY_SHOTGUN_DOOR
		_player(client).call("send_teleport", Transform3D(Basis.IDENTITY, door + Vector3(0.0, 0.1, 0.0)))
		await get_tree().create_timer(0.8).timeout
		chefty.call("dev_script", client, [{"do": "enter", "kind": 1}])
		await get_tree().create_timer(1.2).timeout
		waited += 2.0
	# Give the client a moment to see its seat and the hand aboard.
	await get_tree().create_timer(0.6).timeout
	var in_bed := _rides(chefty, "Big Sal", 2)
	var offered := str(chefty.call("chauffeur_action", client))
	var from: Vector3 = (chefty.call("sim_pose") as Dictionary)["pos"]
	chefty.call("dev_script", client, [{"do": "chauffeur"}])
	waited = 0.0
	while int((chefty.call("dev_report") as Dictionary)["trip"]) != 2 and waited < 3.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	var report: Dictionary = chefty.call("dev_report")
	var chauffeur := int(report["trip"]) == 2 and str(report["trip_label"]) == "Big Sal" and _rides(chefty, "Big Sal", 0) and not bool(chefty.call("is_riding"))
	# Far enough that the client gets out on the street, not in the yard's zone.
	var moved := 0.0
	waited = 0.0
	while moved < 40.0 and waited < 20.0 and bool(chefty.call("is_autopiloting")):
		await get_tree().create_timer(0.2).timeout
		waited += 0.2
		var now: Vector3 = (chefty.call("sim_pose") as Dictionary)["pos"]
		moved = Vector2(now.x - from.x, now.z - from.z).length()
	var stop_offered := str(chefty.call("chauffeur_action", client))
	chefty.call("dev_script", client, [{"do": "chauffeur"}])
	waited = 0.0
	while (float(chefty.call("speed")) > 0.3 or bool(chefty.call("is_autopiloting"))) and waited < 8.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	var pulled_over := not bool(chefty.call("is_autopiloting")) and float(chefty.call("speed")) <= 0.3 and int(chefty.call("seat_of", client)) == 1
	# F in shotgun still slides over with a hand aboard (G is the chauffeur's key).
	await get_tree().create_timer(0.3).timeout
	chefty.call("dev_script", client, [{"do": "swap"}])
	waited = 0.0
	while int(chefty.call("driver")) != client and waited < 3.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	var slid := int(chefty.call("driver")) == client
	# The client gets out where Chefty stopped, on the street (TOWN).
	chefty.call("dev_script", client, [{"do": "exit"}])
	waited = 0.0
	while int(chefty.call("seat_of", client)) >= 0 and waited < 3.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	var out := int(chefty.call("seat_of", client)) < 0 and Net.player_zone(client) == Net.Zone.TOWN
	_verdict(in_bed and offered == "start" and chauffeur and moved >= 10.0 and stop_offered == "stop" and pulled_over and slid and out,
		"k. the chauffeur: Big Sal in the bed %s, the client's G offers '%s', at the wheel %s, drove %.1f m, G then offers '%s', pulled over %s, F slid the client over %s, out on the street %s (%s)" % [in_bed, offered, chauffeur, moved, stop_offered, pulled_over, slid, out, Net.Zone.keys()[Net.player_zone(client)]], problems)
	# k2. The chauffeur fired mid-trip: nobody is named or drawn at the wheel any
	# more and Chefty pulls over. Big Sal is hired back for step l.
	# (The client again: the host is on the yard, fenced into LOT.)
	waited = 0.0
	while int(chefty.call("seat_of", client)) != 1 and waited < 8.0:
		var shotgun: Vector3 = (chefty.call("body_transform") as Transform3D) * _Vehicles.CHEFTY_SHOTGUN_DOOR
		_player(client).call("send_teleport", Transform3D(Basis.IDENTITY, shotgun + Vector3(0.0, 0.1, 0.0)))
		await get_tree().create_timer(0.8).timeout
		chefty.call("dev_script", client, [{"do": "enter", "kind": 1}])
		await get_tree().create_timer(1.2).timeout
		waited += 2.0
	chefty.call("dev_script", client, [{"do": "chauffeur"}])
	waited = 0.0
	while not bool(chefty.call("is_autopiloting")) and waited < 3.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	await get_tree().create_timer(0.5).timeout
	var started := bool(chefty.call("is_autopiloting")) and str(chefty.call("trip_label")) == "Big Sal" and _rides(chefty, "Big Sal", 0)
	hires.call("_handle_fire", "Big Sal")
	waited = 0.0
	while (bool(chefty.call("is_autopiloting")) or float(chefty.call("speed")) > 0.3) and waited < 6.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	var dropped := not bool(chefty.call("is_autopiloting")) and str(chefty.call("trip_label")) == "" and (chefty.call("cosmetic_riders") as Array).is_empty()
	chefty.call("dev_script", client, [{"do": "exit"}])
	waited = 0.0
	while int(chefty.call("seat_of", client)) >= 0 and waited < 3.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	var out_again := int(chefty.call("seat_of", client)) < 0 and Net.player_zone(client) == Net.Zone.TOWN
	_verdict(started and dropped and out_again, "k2. Big Sal fired mid-trip: was driving %s, Chefty pulled over with nobody at the wheel %s, the client out on the street %s" % [started, dropped, out_again], problems)
	hires.call("dev_add_hand", "Big Sal")
	await get_tree().create_timer(0.5).timeout
	# l. Warp home.
	chefty.call("dev_set_warp", true)
	chefty.call("depart", [host], Net.Zone.STORE)
	took = 0.0
	while bool(chefty.call("is_riding")) and took < 25.0:
		await get_tree().physics_frame
		took += get_physics_process_delta_time()
	chefty.call("dev_set_warp", false)
	at = (chefty.call("sim_pose") as Dictionary)["pos"]
	var home := Vector2(at.x - Constants.CHEFTY_PARK_SPOT.x, at.z - Constants.CHEFTY_PARK_SPOT.z).length()
	await get_tree().create_timer(0.5).timeout
	var slot := world.get_node_or_null("%LotSlot")
	var freed := slot != null and slot.get_child_count() == 0
	_verdict(not bool(chefty.call("is_riding")) and took < 20.0 and home <= 15.0 and Net.player_zone(Net.local_peer_id()) == Net.Zone.STORE and int(chefty.call("seat_of", host)) < 0 and freed and _rides(chefty, "Big Sal", 2),
		"l. warped home in %.1f s: %.1f m from the TruckPad, host zone %s, seat %d, yard freed %s, Big Sal back in the bed %s" % [took, home, Net.Zone.keys()[Net.player_zone(host)], int(chefty.call("seat_of", host)), freed, _rides(chefty, "Big Sal", 2)], problems)


## Driving chunk E2: Chefty's chase camera (player/vehicle_camera.gd) never sits
## inside anything. The host at the wheel, Chefty parked on the County Road with
## Big Sal in the bed (a person: never pushes the lens in):
##   m. the boom swings round (the seat's look, eased like a hand on a mouse)
##      past a pillar standing in its way: it pulls in before the pillar and
##      never goes through it or into it, never moves more than CAMERA_STEP_MAX
##      in a frame, never cuts, and eases back out once it's gone. Then past a
##      lamp post in the same spot: thin, it passes between, the boom stays out.
##   n. the boom swings the other way into a tree's crown (a crown has no
##      collider; props/view_blockers.gd): it pulls in in front of it, the lens
##      never in it, no cut; the tree goes and the boom eases back out.
##   o. a wall gets between the truck and the lens at once (backed into): one
##      cut, and the lens is in front of the wall.
func _camera_steps(chefty: Node, host: int, problems: Array[String]) -> void:
	var me := _player(host)
	if int(chefty.call("seat_of", host)) >= 0:
		chefty.call("request_exit")
		await get_tree().create_timer(0.5).timeout
	var spot := Vector3(110.0, 0.0, 0.0)
	spot.z = lerpf(TownMap.DEPOT_JUNCTION.z, TownMap.COUNTY_BEND.z, (spot.x - TownMap.DEPOT_JUNCTION.x) / (TownMap.COUNTY_BEND.x - TownMap.DEPOT_JUNCTION.x))
	var yaw := -PI * 0.5
	chefty.call("dev_place", spot, yaw)
	await get_tree().create_timer(0.3).timeout
	var waited := 0.0
	while int(chefty.call("driver")) != host and waited < 6.0:
		var door: Vector3 = (chefty.call("body_transform") as Transform3D) * _Vehicles.CHEFTY_DRIVER_DOOR
		me.call("send_teleport", Transform3D(Basis.IDENTITY, door + Vector3(0.0, 0.1, 0.0)))
		await get_tree().create_timer(0.5).timeout
		chefty.call("request_enter", 0)
		await get_tree().create_timer(0.5).timeout
		waited += 1.0
	var camera := me.get_node_or_null("VehicleCamera") as Camera3D if me != null else null
	if int(chefty.call("driver")) != host or camera == null:
		_verdict(false, "m. the host at the wheel with the chase camera (driver %d, camera %s)" % [int(chefty.call("driver")), camera != null], problems)
		return
	# Let it settle behind the truck.
	await get_tree().create_timer(1.0).timeout
	var holder := Node3D.new()
	holder.name = "CameraTestProps"
	get_tree().get_first_node_in_group("world").add_child(holder)
	var body: Transform3D = chefty.call("body_transform")
	var pivot := body.origin + Vector3.UP * Constants.CHEFTY_CAMERA_PIVOT_UP
	var full := float((camera.get("last") as Dictionary)["length"])
	var cuts_before := int(camera.get("cuts"))
	# m. A pillar (as wide as a house's corner), where the boom points once the
	# look has turned 0.8 rad: it pulls in before it and never goes through.
	# Then a lamp post in the same spot: thin, it just passes between.
	var swing := yaw + 0.8
	var post_at := pivot + Vector3(sin(swing), 0.0, cos(swing)) * 4.5
	post_at.y = 0.0
	var pillar_shape := BoxShape3D.new()
	pillar_shape.size = Vector3(1.4, 6.0, 1.4)
	for thin: bool in [false, true]:
		var post: StaticBody3D
		var half := 0.7
		if thin:
			var cylinder := CylinderShape3D.new()
			cylinder.radius = 0.15
			cylinder.height = 6.0
			post = _test_solid(holder, cylinder, post_at + Vector3(0.0, 3.0, 0.0))
			half = 0.15
		else:
			post = _test_solid(holder, pillar_shape, post_at + Vector3(0.0, 3.0, 0.0))
			post.rotation.y = swing
		var track := {"max_step": 0.0, "through": false, "inside": false, "last": camera.global_position, "min_boom": INF}
		await _swing(me, camera, 0.0, 1.6, 1.5, track, func(lens: Vector3) -> void:
			var flat := _flat_segment_distance(Vector2(post_at.x, post_at.z), Vector2(pivot.x, pivot.z), Vector2(lens.x, lens.z))
			if flat < half * 0.9 and lens.y < 6.0:
				track["through"] = true
			if Vector2(lens.x - post_at.x, lens.z - post_at.z).length() < half + 0.05:
				track["inside"] = true)
		await _swing(me, camera, 1.6, 1.6, 1.0, track, Callable())
		var pulled := float(track["min_boom"])
		post.queue_free()
		await _swing(me, camera, 1.6, 0.0, 1.5, track, Callable())
		await get_tree().create_timer(2.5).timeout
		var back := float((camera.get("last") as Dictionary)["boom"])
		var shape_ok := pulled > full - 0.5 if thin else (pulled < full - 1.5 and not bool(track["through"]))
		_verdict(shape_ok and not bool(track["inside"]) and float(track["max_step"]) < CAMERA_STEP_MAX and int(camera.get("cuts")) == cuts_before and back > full * 0.9,
			"m. the boom swung past a %s: pulled in to %.1f of %.1f m, through it %s, into it %s, biggest step %.2f m, cuts %d, eased back out to %.1f m" % ["lamp post (passes between)" if thin else "pillar", pulled, full, track["through"], track["inside"], float(track["max_step"]), int(camera.get("cuts")) - cuts_before, back], problems)
	# n. A tree on the other side, the boom swung round into its crown.
	var other := yaw - 0.8
	var tree_at := pivot - Vector3.UP * pivot.y + Vector3(sin(other), 0.0, cos(other)) * 6.0
	var tree := _Trees.spawn(holder, tree_at, 7.0, "broadleaf", "orange", 0, false, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var track := {"max_step": 0.0, "last": camera.global_position, "min_boom": INF, "in_crown": 0}
	await _swing(me, camera, 0.0, -1.6, 1.5, track, func(lens: Vector3) -> void:
		if not _ViewBlockers.inside(lens, 0.0).is_empty():
			track["in_crown"] = int(track["in_crown"]) + 1)
	await _swing(me, camera, -1.6, -1.6, 1.0, track, Callable())
	var registered := _ViewBlockers.inside(tree_at + Vector3.UP * 5.0, 0.0).size() > 0
	var crown_boom := float(track["min_boom"])
	tree.queue_free()
	await _swing(me, camera, -1.6, 0.0, 1.5, track, Callable())
	await get_tree().create_timer(2.5).timeout
	var after_tree := float((camera.get("last") as Dictionary)["boom"])
	_verdict(registered and crown_boom < full - 1.5 and int(track["in_crown"]) == 0 and float(track["max_step"]) < CAMERA_STEP_MAX and int(camera.get("cuts")) == cuts_before and after_tree > full * 0.9,
		"n. the boom swung into a tree (its crown registered %s): pulled in to %.1f m, frames in the crown %d, biggest step %.2f m, cuts %d, back out to %.1f m" % [registered, crown_boom, int(track["in_crown"]), float(track["max_step"]), int(camera.get("cuts")) - cuts_before, after_tree], problems)
	# o. A wall between the truck and the lens, all at once.
	var behind := Vector3(sin(yaw), 0.0, cos(yaw))
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(8.0, 8.0, 0.4)
	var wall := _test_solid(holder, wall_shape, pivot - Vector3.UP * pivot.y + behind * 4.0 + Vector3.UP * 4.0)
	wall.rotation.y = yaw
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var lens := camera.global_position
	var lens_out := Vector2(lens.x - pivot.x, lens.z - pivot.z).length()
	var cut := int(camera.get("cuts")) - cuts_before
	_verdict(cut == 1 and lens_out < 4.0 - 0.2, "o. a wall backed into: %d cut, the lens %.1f m out (the wall at 4.0 m)" % [cut, lens_out], problems)
	holder.queue_free()
	chefty.call("request_exit")
	await get_tree().create_timer(0.5).timeout


## Turns the host's seat look from one angle to another over seconds, a frame at
## a time, calling check(lens) each frame and keeping track of the biggest
## frame-to-frame step of the lens and the shortest boom.
func _swing(me: Node, camera: Camera3D, from: float, to: float, seconds: float, track: Dictionary, check: Callable) -> void:
	var clock := 0.0
	while clock < seconds:
		await get_tree().physics_frame
		clock += get_physics_process_delta_time()
		me.set("seat_look", lerpf(from, to, smoothstep(0.0, 1.0, clock / seconds)))
		var lens := camera.global_position
		track["max_step"] = maxf(float(track["max_step"]), lens.distance_to(track["last"]))
		track["last"] = lens
		track["min_boom"] = minf(float(track["min_boom"]), float((camera.get("last") as Dictionary)["boom"]))
		if check.is_valid():
			check.call(lens)


func _test_solid(holder: Node3D, shape: Shape3D, at: Vector3) -> StaticBody3D:
	var solid := StaticBody3D.new()
	solid.collision_layer = 1
	var collision := CollisionShape3D.new()
	collision.shape = shape
	solid.add_child(collision)
	holder.add_child(solid)
	solid.global_position = at
	return solid


static func _flat_segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var along := b - a
	var t := clampf((point - a).dot(along) / maxf(along.length_squared(), 0.0001), 0.0, 1.0)
	return point.distance_to(a + along * t)


## Whether a hand is drawn riding in Chefty: at the wheel (seat 0) or, with
## min_seat 2, in any bed seat.
func _rides(chefty: Node, hand: String, min_seat: int) -> bool:
	for entry: Dictionary in chefty.call("cosmetic_riders"):
		var seat := int(entry["seat"])
		if str(entry["name"]) == hand and (seat == min_seat if min_seat == 0 else seat >= min_seat):
			return true
	return false


func _client_id() -> int:
	for peer_id: int in Net.peer_ids():
		if peer_id != Net.local_peer_id():
			return peer_id
	return 0


func _player(peer_id: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node as Node3D
	return null


func _verdict(ok: bool, line: String, problems: Array[String]) -> void:
	print("[DriveTest] %s: %s" % [line, ok])
	if not ok:
		problems.append(line)


func _finish(ok: bool, problems: Array) -> void:
	result = {"ok": ok, "problems": problems, "done": true}
	print("[DriveTest] done: ok=%s %s" % [ok, problems])
