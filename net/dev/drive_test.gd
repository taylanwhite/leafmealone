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
## The client's prediction (how far its predicted Chefty was from the host's
## after the same input, "drive".prediction_error_max_m), the riders both peers
## see, and the client's snapshot gaps are checked by CI from the probe reports.
## Each step prints a [DriveTest] line.

const _Vehicles = preload("res://props/vehicles.gd")

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
	if OS.get_environment("DRIVE_TEST_C3_ONLY") == "1":
		await _crash_steps(world, get_tree().get_first_node_in_group("chefty"), host, problems)
		_finish(problems.is_empty(), problems)
		return
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
	await _crash_steps(world, chefty, host, problems)
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


## Driving chunk C3, the crash comedy (the spec's drive_test steps h to j):
##   m. the host drives 10 bags ($200) and the client (in the bed) into the side
##      of a parked car at about 14 m/s: a crash every peer saw, at least 3 bags
##      out of the bed as real leaf bags whose values and the bed's add up to
##      $200 again, a dent, and the client thrown out of its seat.
##   m2. with the Chefty Net, the same crash spills half as many, and the second
##      dent; Marty's Body Shop (Shops.host_buy chefty_repair at the counter)
##      takes $25 a dent and every dent out.
##   n. the client stands on County Road 9; the host drives at it: the client
##      was Chefty'd (its own report, CI), and the host saw it.
##   o. in the job yard: driving through the leaves plows them, parking on the
##      lawn for CHEFTY_LAWN_PARK_SECONDS makes the homeowner yell and costs a
##      mood step, the horn there adds heat and gets a "Yes, I SEE you.", and a
##      mailbox Chefty flattens adds HEAT_MAILBOX.
func _crash_steps(world: Node, chefty: Node, host: int, problems: Array[String]) -> void:
	var client := _client_id()
	var hires := world.get_node_or_null("Hires")
	if hires != null:
		hires.call("_handle_fire", "Big Sal")
	# m. A parked car, side on, with room on the street side to run up.
	var target := _car_target()
	if target.is_empty():
		_verdict(false, "m. no parked car with a clear run-up", problems)
		return
	var run_from: Vector3 = target["from"]
	var run_yaw := float(target["yaw"])
	var first := await _crash_into(chefty, host, client, run_from, run_yaw, 10, 200)
	var seen: Dictionary = first["report"]
	_verdict(int(seen["crashes_seen"]) >= 1 and int(first["spilled"]) >= 3 and int(first["props"]) == int(first["spilled"]) and int(first["props_value"]) + int(first["bed_value"]) == 200 and int(seen["dents"]) >= 1 and bool(first["thrown"]) and int(chefty.call("seat_of", client)) < 0,
		"m. crash at %.1f m/s: crashes %d, %d bags out (%d leaf bags worth $%d, the bed keeps $%d of $200), dents %d, the client thrown %s, seat %d" % [float(first["impact"]), int(seen["crashes_seen"]), int(first["spilled"]), int(first["props"]), int(first["props_value"]), int(first["bed_value"]), int(seen["dents"]), first["thrown"], int(chefty.call("seat_of", client))], problems)
	_clear_spills()
	# m2. The Chefty Net halves the spill; the second dent; Marty's Body Shop.
	var shops := get_tree().get_first_node_in_group("shops")
	if shops != null and not (shops.get("crew_owned") as Array).has("chefty_net"):
		(shops.get("crew_owned") as Array).append("chefty_net")
	var second := await _crash_into(chefty, host, client, run_from, run_yaw, 10, 200)
	_clear_spills()
	# What this crash would have spilled with no net, halved.
	var bare := maxi(1, int(floor((float(second["impact"]) - Constants.CHEFTY_CRASH_MIN_SPEED) * Constants.CHEFTY_SPILL_PER_MPS + 0.5)))
	var net_halves := float(second["impact"]) > 0.0 and int(second["spilled"]) == int(floor(float(bare) * Constants.CHEFTY_NET_SPILL_SHARE))
	var dents_now := int(chefty.call("dents"))
	if int(chefty.call("seat_of", host)) >= 0:
		chefty.call("request_exit")
		await get_tree().create_timer(0.4).timeout
	Net.move_player_to_zone(host, Net.Zone.STORE)
	await get_tree().create_timer(0.6).timeout
	var counter: Vector3 = (Constants.SHOP_SITES["homie_depot"] as Dictionary)["counter"]
	var store := world.get_node("StoreZone") as Node3D
	_player(host).global_position = store.to_global(counter + Vector3(0.0, 0.1, 1.8))
	await get_tree().physics_frame
	await get_tree().physics_frame
	Campaign.pay(host, Constants.SHOP_PRICES["chefty_repair"] * Constants.CHEFTY_MAX_DENTS)
	var cash_before := Campaign.credits(host)
	var code := str(shops.call("host_buy", host, "homie_depot", "chefty_repair", dents_now)) if shops != null else "no shops"
	var paid := cash_before - Campaign.credits(host)
	await get_tree().create_timer(0.5).timeout
	_verdict(net_halves and dents_now >= 2 and code == "ok" and paid == Catalog.price("chefty_repair") * dents_now and int(chefty.call("dents")) == 0,
		"m2. with the Net %d bags out (%d without it), dents %d; the body shop said %s, took $%d, dents now %d" % [int(second["spilled"]), bare, dents_now, code, paid, int(chefty.call("dents"))], problems)
	# n. Chefty'd: the client in the road, the host driving at it.
	var road := Vector3(70.0, 0.0, TownMap.nearest_road_point(Vector3(70.0, 0.0, 15.0)).z)
	await _take_wheel(chefty, host, road, -PI * 0.5)
	_player(client).call("send_teleport", Transform3D(Basis.IDENTITY, road + Vector3(20.0, 0.1, 0.0)))
	await get_tree().create_timer(1.2).timeout
	var ran_before := int((chefty.call("dev_report") as Dictionary)["runovers_seen"])
	chefty.call("dev_script", host, [{"seconds": 2.6, "throttle": 1.0}, {"seconds": 2.0, "throttle": -1.0}])
	await get_tree().create_timer(4.8).timeout
	var ran := int((chefty.call("dev_report") as Dictionary)["runovers_seen"]) - ran_before
	print("[DriveTest]   road %s: driver %d, Chefty now %s, client at %s" % [road, int(chefty.call("driver")), (chefty.call("dev_report") as Dictionary)["pos"], _player(client).global_position])
	_verdict(ran >= 1, "n. the host ran the client over: %d run-overs seen" % ran, problems)
	# o. The job yard: plow, lawn, horn, mailbox.
	var house := TownMap.test_site_house()
	world.call("place_job_site", TownMap.yard_transform(house), house)
	world.call("_load_job_lot")
	var waited := 0.0
	while get_tree().get_first_node_in_group("homeowner") == null and waited < 6.0:
		await get_tree().create_timer(0.2).timeout
		waited += 0.2
	var homeowner := get_tree().get_first_node_in_group("homeowner")
	var lot := (world.get_node("LotZone") as Node3D).global_transform
	await _take_wheel(chefty, host, lot * Vector3(-17.0, 0.0, 8.0), -PI * 0.5)
	var plowed_before := int((chefty.call("dev_report") as Dictionary)["plowed"])
	chefty.call("dev_script", host, [{"seconds": 1.6, "throttle": 0.6}, {"seconds": 1.5, "throttle": -1.0}])
	await get_tree().create_timer(3.4).timeout
	var plowed := int((chefty.call("dev_report") as Dictionary)["plowed"]) - plowed_before
	var grumbles_before := int(homeowner.get("grumbles")) if homeowner != null else 0
	chefty.call("dev_place", lot * Vector3(-10.0, 0.0, 10.0), -PI * 0.5)
	await get_tree().create_timer(Constants.CHEFTY_LAWN_PARK_SECONDS + 1.0).timeout
	var grumbles := int(homeowner.get("grumbles")) - grumbles_before if homeowner != null else 0
	var stepped := str(homeowner.call("grumbled", "happy", grumbles)) if homeowner != null else ""
	var heat := get_tree().get_first_node_in_group("heat")
	var heat_before := float(heat.get("heat")) if heat != null else 0.0
	chefty.call("dev_script", host, [{"seconds": 1.2, "horn": true}, {"seconds": 0.2}])
	await get_tree().create_timer(1.6).timeout
	var horn_heat := (float(heat.get("heat")) if heat != null else 0.0) - heat_before
	var yells: Array = homeowner.get("yells_seen") if homeowner != null else []
	_verdict(homeowner != null and plowed > 0 and grumbles == 1 and stepped == "fine" and yells.has("lawn_park") and yells.has("horn") and horn_heat > 0.15,
		"o. the yard: plowed %d, lawn parking cost %d mood step (happy -> %s), yells %s, the horn added %.2f heat" % [plowed, grumbles, stepped, yells, horn_heat], problems)
	# The mailbox: along the curb of the next yard up the street, at 9 m/s.
	var next_house := house + 1
	var mailbox: Vector3 = TownMap.yard_transform(next_house) * preload("res://levels/town/town_dressing.gd").MAILBOX_AT
	await _take_wheel(chefty, host, mailbox + Vector3(-14.0, 0.0, 0.0), -PI * 0.5)
	var hit_before := int((chefty.call("dev_report") as Dictionary)["mailboxes_hit"])
	heat_before = float(heat.get("heat")) if heat != null else 0.0
	chefty.call("dev_script", host, [{"seconds": 2.4, "throttle": 0.8}, {"seconds": 1.5, "throttle": -1.0}])
	await get_tree().create_timer(4.2).timeout
	var hit := int((chefty.call("dev_report") as Dictionary)["mailboxes_hit"]) - hit_before
	var box_heat := (float(heat.get("heat")) if heat != null else 0.0) - heat_before
	_verdict(hit >= 1 and box_heat >= Constants.HEAT_MAILBOX - 0.5, "o2. flattened %d mailbox (+%.1f heat)" % [hit, box_heat], problems)
	if int(chefty.call("seat_of", host)) >= 0:
		chefty.call("request_exit")
	await get_tree().create_timer(0.5).timeout


## A parked car to crash into, rear-ended in its own lane: the run-up spot
## CRASH_RUN_UP meters back up the street, and the heading that faces it. {}
## with none clear.
func _car_target() -> Dictionary:
	for car: Array in TownMap.car_spots():
		var at: Vector3 = car[0]
		var along := Basis(Vector3.UP, float(car[1])).z
		for flip: float in [1.0, -1.0]:
			var from := at + along * flip * (CRASH_RUN_UP + Constants.CHEFTY_HALF_LENGTH + 2.2)
			if TownMap.surface_at(from) != &"asphalt" or TownMap.surface_at(at + along * flip * 6.0) != &"asphalt":
				continue
			var toward := (at - from)
			return {"from": Vector3(from.x, 0.0, from.z), "yaw": atan2(-toward.x, -toward.z)}
	return {}


## The run-up to a crash (m): about 14 m/s at the hit.
const CRASH_RUN_UP: float = 15.0


## Host at the wheel, the client in the bed, bags worth value in it, Chefty at
## from facing yaw; full throttle into whatever's ahead. Returns what happened:
## {impact, spilled, props, props_value, bed_value, thrown, report}.
func _crash_into(chefty: Node, host: int, client: int, from: Vector3, yaw: float, bags: int, value: int) -> Dictionary:
	await _take_wheel(chefty, host, from, yaw)
	var waited := 0.0
	while int(chefty.call("seat_of", client)) < 2 and waited < 10.0:
		var gate: Vector3 = (chefty.call("body_transform") as Transform3D) * _Vehicles.CHEFTY_TAILGATE
		_player(client).call("send_teleport", Transform3D(Basis.IDENTITY, gate + Vector3(0.0, 0.1, 0.0)))
		await get_tree().create_timer(0.8).timeout
		chefty.call("dev_script", client, [{"do": "enter", "kind": 2}])
		await get_tree().create_timer(1.2).timeout
		waited += 2.0
	chefty.call("clear_bags")
	await get_tree().create_timer(0.2).timeout
	chefty.call("accept_bags", bags, value)
	await get_tree().create_timer(0.4).timeout
	var bags_before := int(chefty.call("bag_count"))
	var crashes_before := int((chefty.call("dev_report") as Dictionary)["crashes_seen"])
	chefty.call("dev_script", host, [{"seconds": 3.5, "throttle": 1.0}, {"seconds": 1.0, "throttle": -1.0}])
	var thrown := false
	var clock := 0.0
	var top := 0.0
	while clock < 4.0:
		await get_tree().physics_frame
		clock += get_physics_process_delta_time()
		top = maxf(top, float(chefty.call("speed")))
		var rider := _player(client)
		if rider != null and int(chefty.call("seat_of", client)) < 0:
			thrown = thrown or bool(rider.get("thrown"))
	var report: Dictionary = chefty.call("dev_report")
	var crash: Dictionary = report.get("last_crash", {})
	print("[DriveTest]   run from %s yaw %.2f: driver %d, top %.1f m/s, now at %s" % [from, yaw, int(chefty.call("driver")), top, report["pos"]])
	var props := 0
	var props_value := 0
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) == "leaf_bag" and node.name.begins_with("Spill"):
			props += 1
			props_value += int(node.get("value"))
	return {
		"impact": float(crash.get("impact", 0.0)) if int(report["crashes_seen"]) > crashes_before else 0.0,
		"spilled": bags_before - int(chefty.call("bag_count")),
		"props": props, "props_value": props_value, "bed_value": int(chefty.call("bag_value")),
		"thrown": thrown, "report": report,
	}


## Spilled bags from a crash step go away before the next.
func _clear_spills() -> void:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if node.name.begins_with("Spill"):
			node.queue_free()
	await get_tree().process_frame


## The host in the driver's seat with Chefty stopped at `at` facing yaw.
func _take_wheel(chefty: Node, host: int, at: Vector3, yaw: float) -> void:
	chefty.call("dev_place", at, yaw)
	await get_tree().create_timer(0.3).timeout
	var waited := 0.0
	while int(chefty.call("driver")) != host and waited < 6.0:
		if int(chefty.call("seat_of", host)) >= 0:
			chefty.call("request_exit")
			await get_tree().create_timer(0.3).timeout
		var door: Vector3 = (chefty.call("body_transform") as Transform3D) * _Vehicles.CHEFTY_DRIVER_DOOR
		_player(host).call("send_teleport", Transform3D(Basis.IDENTITY, door + Vector3(0.0, 0.1, 0.0)))
		await get_tree().create_timer(0.3).timeout
		chefty.call("request_enter", 0)
		await get_tree().create_timer(0.4).timeout
		waited += 1.0
	chefty.call("dev_place", at, yaw)
	await get_tree().create_timer(0.3).timeout


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
