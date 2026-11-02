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
	# Give the client's report time to see the same seats and zone.
	await get_tree().create_timer(1.0).timeout
	_finish(problems.is_empty(), problems)


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
