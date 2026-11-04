extends Node

## Authority: host. --skate-test (with --town-map, a client named Target joined)
## rides the Gutter Shredder (player/skate.gd, driving chunk G1) through the
## real paths, on the host's own player, its keys pressed through Skate.dev_input:
##   a. the board key does nothing without a board; with $100 granted, Homie
##      Depot sells the board ($60 off the wallet, the unlock on it).
##   b. on County Road 9 the board key gets you on, and board_state() (the
##      contract audio/board_sound.gd reads) says so; in c its speed is yours.
##   c. 3 s of pushing: 7 m/s or more; 2 s coasting: slower, still over 4.
##   d. an ollie: 0.4 m up or more, down again, one ollie counted.
##   e. an ollie with a kickflip, landed: a line worth 200 or more.
##   f. a 90 degree spin landed sideways: a wipeout, flat on your back (KNOCKED),
##      and back up within 3 s.
##   g. into a wall at 6 m/s: a wipeout.
##   h. off the street onto a lawn at 8 m/s: a lawn bail.
##   m. into a NICE BOY at 6 m/s (he's solid, like a wall): a bump, not a wall
##      bail, and his bonk adds HEAT_CREW_BONK (run before i; j-l are driving
##      G2's).
##   i. holding something heavy (a junk toilet), the board key won't get you on.
## driving G2:
##   j. on the board at Chefty's driver's door E is the door; seated, the board's away.
##   k. behind the tailgate E grabs on ("Hang on"); towed 5 s behind the autopilot
##      down County Road 9 within 3.1 m of tow_point() at Chefty's speed; E lets go.
##   l. Chefty crashing shakes the skitcher off: a wipeout whose flop tumbles past
##      1 rad, nothing below the ground, ending on its back.
## The client's view of the host (it saw the host on a board, a kickflip, a
## wipeout, a skitch and the flop: "skate_seen") is checked by CI from the probe
## reports.
## Each step prints a [SkateTest] line.

const _Skate = preload("res://player/skate.gd")
const _Strings = preload("res://ui/strings.gd")

static var result: Dictionary = {}

var _started: bool = false


func _process(_delta: float) -> void:
	if _started or not Net.is_host():
		return
	if get_tree().get_first_node_in_group("world") == null or _me() == null or get_tree().get_first_node_in_group("shops") == null:
		return
	_started = true
	_run()


func _run() -> void:
	var world := get_tree().get_first_node_in_group("world")
	if not bool(world.call("is_town_map")):
		_finish(false, ["not the connected town: run with --town-map"])
		return
	var waited := 0.0
	while Net.peer_ids().size() < 2 and waited < 15.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	# Let the client's world and players settle in.
	await get_tree().create_timer(1.5).timeout
	var problems: Array[String] = []
	var me := _me()
	var host := Net.local_peer_id()
	var skate := me.call("skate") as Node
	# a. No board, no ride; then buy one.
	var nothing := not bool(skate.call("toggle")) and not bool(me.get("on_board"))
	Campaign.pay(host, 100)
	var cash := Campaign.credits(host)
	var counter: Vector3 = (Constants.SHOP_SITES["homie_depot"] as Dictionary)["counter"]
	var store := world.get_node("StoreZone") as Node3D
	_put(me, store.global_transform * (counter + Vector3(0.0, 0.0, 1.2)), PI)
	await _ticks(4)
	var shops := get_tree().get_first_node_in_group("shops")
	var code := str(shops.call("request_buy", "homie_depot", "skateboard", 1))
	await _ticks(2)
	var paid := cash - Campaign.credits(host)
	_verdict(nothing and code == "ok" and Campaign.is_unlocked(&"skateboard") and paid == Constants.SHOP_PRICES["skateboard"], "a. no board, no ride (%s); bought one: %s, paid $%d" % [nothing, code, paid], problems)
	if not Campaign.is_unlocked(&"skateboard"):
		_finish(false, problems)
		return
	# b. On County Road 9, heading east (+X).
	var road := TownMap.nearest_road_point(Vector3(70.0, 0.0, 10.0)) + Vector3(0.0, 0.05, 0.0)
	var along := (TownMap.COUNTY_BEND - TownMap.DEPOT_JUNCTION).normalized()
	_put(me, road, atan2(-along.x, -along.z))
	await _ticks(6)
	var surface := TownMap.surface_at(road)
	var mounted := bool(skate.call("toggle")) and bool(me.get("on_board"))
	await _ticks(3)
	# The contract audio/board_sound.gd reads (critic C13): {on_board, speed, on_ground, grinding}.
	var state: Dictionary = skate.call("board_state")
	var contract := bool(state.get("on_board")) and bool(state.get("on_ground")) and not bool(state.get("grinding")) and state.has("speed")
	_verdict(mounted and surface == &"asphalt" and contract, "b. on the board on County Road 9 (%s), board_state %s" % [surface, state], problems)
	if not mounted:
		_finish(false, problems)
		return
	# c. Push, then coast.
	skate.set("dev_input", {"push": true})
	await _seconds(3.0)
	var pushed := _speed(me)
	var heard := float((skate.call("board_state") as Dictionary).get("speed", 0.0))
	if absf(heard - pushed) > 0.05:
		problems.append("c. board_state speed %.2f, rolling %.2f" % [heard, pushed])
	skate.set("dev_input", {"push": false})
	await _seconds(2.0)
	var coasted := _speed(me)
	_verdict(pushed >= 7.0 and coasted < pushed and coasted > 4.0, "c. pushed to %.1f m/s, coasted down to %.1f" % [pushed, coasted], problems)
	# d. An ollie.
	var ground := me.global_position.y
	var ollies := int((skate.get("tricks") as Dictionary).get("ollie", 0))
	skate.set("dev_input", {"push": false, "jump": true})
	var peak := ground
	var clock := 0.0
	var left := false
	while clock < 1.6:
		await get_tree().physics_frame
		clock += get_physics_process_delta_time()
		peak = maxf(peak, me.global_position.y)
		left = left or not me.is_on_floor()
		if left and me.is_on_floor() and clock > 0.3:
			break
	await _ticks(2)
	var counted := int((skate.get("tricks") as Dictionary).get("ollie", 0)) - ollies
	_verdict(peak - ground >= 0.4 and me.is_on_floor() and counted == 1 and bool(me.get("on_board")), "d. ollie: %.2f m up, landed %s, ollies counted %d" % [peak - ground, me.is_on_floor(), counted], problems)
	# e. An ollie and a kickflip, landed (keep rolling: push back up to speed first).
	skate.set("dev_input", {"push": true})
	await _seconds(1.2)
	skate.set("dev_input", {"push": false, "jump": true})
	await _ticks(5)
	skate.set("dev_input", {"push": false, "kickflip": true})
	await _until_landed(me, 1.6)
	await _ticks(2)
	var line: Dictionary = skate.get("last_line")
	_verdict(bool(line.get("clean", false)) and int(line.get("score", 0)) >= 200 and bool(me.get("on_board")), "e. ollie + kickflip: %s" % [line], problems)
	# f. Spun a quarter turn and landed sideways: down you go, and back up.
	skate.set("dev_input", {"push": true})
	await _seconds(1.0)
	skate.set("dev_input", {"push": false, "jump": true})
	await _ticks(4)
	skate.set("dev_input", {"push": false, "steer": 1.0})
	await _seconds(PI * 0.5 / Constants.SKATE_SPIN_RATE)
	skate.set("dev_input", {"push": false})
	var fell := await _until_wipeout(me, 2.0)
	var knocked := false
	var up_after := -1.0
	clock = 0.0
	while clock < 3.5 and fell:
		await get_tree().physics_frame
		clock += get_physics_process_delta_time()
		knocked = knocked or int(me.get("anim_state")) == 5
		if not bool(me.get("wipeout")) and int(me.get("anim_state")) != 5:
			up_after = clock
			break
	_verdict(fell and knocked and up_after >= 0.0 and up_after <= 3.0 and int((skate.get("wipeouts") as Dictionary).get("landing", 0)) >= 1, "f. sideways landing: wipeout %s, knocked %s, up after %.2f s" % [fell, knocked, up_after], problems)
	# g. Into a wall at 6 m/s.
	var wall := _find_wall()
	var walled := false
	if wall.is_empty():
		problems.append("g. no wall to ride into")
		print("[SkateTest] g. no wall to ride into: false")
	else:
		var dir: Vector3 = wall["dir"]
		var start: Vector3 = (wall["hit"] as Vector3) - dir * 6.0
		await _ride_from(me, skate, Vector3(start.x, 0.05, start.z), dir, 6.0)
		walled = await _until_wipeout(me, 3.0)
		_verdict(walled and int((skate.get("wipeouts") as Dictionary).get("wall", 0)) >= 1, "g. into the wall at %s from %s: wipeout %s (%s)" % [wall["hit"], start, walled, skate.get("wipeouts")], problems)
		await _seconds(Constants.SKATE_WIPEOUT_SECONDS + 0.3)
	# h. Off the street onto a lawn at 8 m/s.
	var lawn := _lawn_run()
	var bailed := false
	if lawn.is_empty():
		problems.append("h. no clear run onto a lawn")
	else:
		await _ride_from(me, skate, lawn["from"], Vector3(0.0, 0.0, -1.0), 8.0)
		skate.set("dev_input", {"push": true})
		bailed = await _until_wipeout(me, 3.0)
		skate.set("dev_input", {})
		_verdict(bailed and int((skate.get("wipeouts") as Dictionary).get("lawn", 0)) >= 1, "h. onto the lawn at 8 m/s from %s: %s (%s)" % [lawn["from"], bailed, skate.get("wipeouts")], problems)
		await _seconds(Constants.SKATE_WIPEOUT_SECONDS + 0.3)
	# m. Into a NICE BOY at 6 m/s.
	await _into_nice_boy(me, skate, world, road, along, problems)
	# i. Something heavy in hand: no board.
	var heaviest := ""
	for type: String in Constants.JUNK_TYPES:
		if heaviest == "" or float((Constants.JUNK_TYPES[type] as Dictionary)["kg"]) > float((Constants.JUNK_TYPES[heaviest] as Dictionary)["kg"]):
			heaviest = type
	var at := Vector3(4.0, 0.1, 2.0)
	_put(me, at + Vector3(0.0, 0.0, 1.0), 0.0)
	var junk := world.call("spawn_junk", heaviest, at + Vector3(0.0, 0.3, 0.0), 10) as Node3D
	await _seconds(0.8)
	var held := false
	if junk != null:
		junk.call("request_grab")
		waited = 0.0
		while waited < 2.0 and int(junk.get("held_by")) != host:
			await get_tree().physics_frame
			waited += get_physics_process_delta_time()
		held = int(junk.get("held_by")) == host
	var kg := float(junk.call("weight_kg")) if junk != null else 0.0
	skate.call("toggle")
	await _ticks(3)
	var refused := not bool(me.get("on_board"))
	if junk != null:
		junk.call("request_drop")
	_verdict(held and kg > Constants.SKATE_MAX_CARRY_KG and refused, "i. holding a %.0f kg %s (%s): on the board %s" % [kg, heaviest, held, not refused], problems)
	await _seconds(0.5)
	# driving G2.
	var chefty := get_tree().get_first_node_in_group("chefty") as Node3D
	if chefty == null or not chefty.has_method("dev_drive_to"):
		problems.append("j-l. no drivable Chefty")
		_finish(false, problems)
		return
	await _into_chefty(me, skate, chefty, road, along, problems)
	await _skitch(me, skate, chefty, road, along, problems)
	await _flop(me, skate, chefty, problems)
	_finish(problems.is_empty(), problems)


## j. On the board at Chefty's driver's door, E is the door, not the board: in
## the seat, the board's away (on_board false); out again, still away.
func _into_chefty(me: CharacterBody3D, skate: Node, chefty: Node3D, road: Vector3, along: Vector3, problems: Array[String]) -> void:
	chefty.call("dev_place", road + along * 30.0, atan2(along.x, along.z) + PI)
	await _ticks(4)
	var door: Vector3 = (chefty.call("body_transform") as Transform3D) * Vector3(-1.9, 0.05, -2.0)
	await _ride_from(me, skate, door, along, 0.0)
	await _ticks(3)
	var choice := StringName((me.call("e_choice") as Dictionary)["do"])
	var boarded := bool(me.get("on_board"))
	chefty.call("request_enter", 0)
	var seated := false
	var clock := 0.0
	while clock < 2.0 and not seated:
		await get_tree().physics_frame
		clock += get_physics_process_delta_time()
		seated = bool(me.call("in_vehicle"))
	await _ticks(3)
	var stowed := not bool(me.get("on_board"))
	chefty.call("request_exit")
	await _seconds(1.5)
	_verdict(boarded and choice == &"seat" and seated and stowed and not bool(me.get("on_board")), "j. on the board at the door: E %s, in the seat %s, board away %s" % [choice, seated, stowed], problems)


## k. Skitching: on the board behind Chefty's tailgate, E (the "skitch" choice,
## its prompt "Hang on") grabs on; the autopilot drives off for real down County
## Road 9 and for 5 s at speed the board rides within 3.1 m of chefty.tow_point()
## at Chefty's speed (within 1.5 m/s); E lets go and you roll on, on the board.
## The client sees the skitch (skate_seen, CI).
func _skitch(me: CharacterBody3D, skate: Node, chefty: Node3D, road: Vector3, along: Vector3, problems: Array[String]) -> void:
	var yaw := atan2(along.x, along.z) + PI
	chefty.call("dev_place", road + along * 10.0, yaw)
	await _ticks(4)
	var spot := _Skate.hold_spot(chefty, 1.0)
	await _ride_from(me, skate, Vector3(spot.x, road.y, spot.z) + along * -0.4, along, 0.0)
	await _ticks(4)
	var choice: Dictionary = me.call("e_choice")
	var hint: Dictionary = choice["hint"]
	var grabbed := StringName(choice["do"]) == &"skitch" and bool(skate.call("grab_on")) and bool(me.get("skitch"))
	if not grabbed:
		_verdict(false, "k. no grab at the tailgate: %s" % [choice], problems)
		return
	chefty.call("dev_drive_to", Transform3D(Basis(Vector3.UP, yaw), road + along * 200.0))
	var clock := 0.0
	var towed := 0.0
	var worst_gap := 0.0
	var worst_speed := 0.0
	var top := 0.0
	while clock < 20.0 and towed < 5.0 and bool(me.get("skitch")):
		await get_tree().physics_frame
		var delta := get_physics_process_delta_time()
		clock += delta
		var truck_speed := float(chefty.call("speed"))
		if truck_speed < 4.0:
			continue
		towed += delta
		top = maxf(top, truck_speed)
		var tow: Vector3 = (chefty.call("tow_point") as Transform3D).origin
		worst_gap = maxf(worst_gap, Vector2(me.global_position.x - tow.x, me.global_position.z - tow.z).length())
		worst_speed = maxf(worst_speed, absf(_speed(me) - truck_speed))
	var held := bool(me.get("skitch"))
	var mid := StringName((me.call("e_choice") as Dictionary)["do"])
	skate.call("let_go", "hands")
	await _ticks(10)
	var rolled := bool(me.get("on_board")) and not bool(me.get("skitch")) and _speed(me) > 4.0
	chefty.call("dev_end_trip")
	await _seconds(2.5)
	_verdict(held and towed >= 5.0 and worst_gap <= 3.1 and worst_speed <= 1.5 and mid == &"let_go" and rolled and str(hint.get("text", "")) == str(_Strings.UI["prompt_skitch"]),
		"k. skitched %.1f s at up to %.1f m/s: worst gap to the tow point %.2f m, speed off by %.2f m/s, E then %s, rolled on %s (%.1f m/s), left %s" % [towed, top, worst_gap, worst_speed, mid, rolled, _speed(me), skate.get("last_let_go")], problems)
	await _seconds(1.0)


## l. Hanging on when Chefty crashes shakes you off: a wipeout, and the body's
## flop tumbles past 1 rad (CartoonBody.flop_max_angle, the cosmetic hook), never
## below the ground (its hips, head and feet), and lands on its back like a knock.
func _flop(me: CharacterBody3D, skate: Node, chefty: Node3D, problems: Array[String]) -> void:
	var body := me.get_node_or_null("Visual/CartoonBody")
	if body == null:
		_verdict(false, "l. no CartoonBody to flop", problems)
		return
	chefty.call("dev_place", (chefty.call("body_transform") as Transform3D).origin, float(chefty.call("yaw")))
	await _ticks(3)
	var spot := _Skate.hold_spot(chefty, -1.0)
	if bool(me.get("on_board")):
		skate.call("dismount", false)
	_put(me, Vector3(spot.x, me.global_position.y, spot.z), float(chefty.call("yaw")))
	await _ticks(3)
	skate.call("toggle")
	await _ticks(3)
	var grabbed := bool(skate.call("grab_on"))
	await _ticks(3)
	var flops_before := int(body.get("flops"))
	chefty.emit_signal("crashed", 6.0, (chefty.call("body_transform") as Transform3D).origin)
	var fell := await _until_wipeout(me, 1.0)
	var lowest := INF
	var clock := 0.0
	var angle := 0.0
	while clock < Constants.FLOP_TUMBLE_SECONDS + 0.2:
		await get_tree().physics_frame
		clock += get_physics_process_delta_time()
		angle = maxf(angle, float(body.get("flop_angle")))
		var floor_y := me.global_position.y
		for part: String in ["hips", "head"]:
			var node := body.call("pose_part", part) as Node3D
			if node != null:
				lowest = minf(lowest, node.global_position.y - floor_y)
	var flat := absf(float(body.get("fallen")) - 1.0) < 0.01 and not bool(body.call("is_flopping"))
	_verdict(grabbed and fell and int(body.get("flops")) == flops_before + 1 and angle > 1.0 and lowest > -0.05 and flat and int((skate.get("wipeouts") as Dictionary).get("skitch_crash", 0)) >= 1,
		"l. a crash shook the skitcher off (grabbed %s, wipeout %s): flopped %d, tumbled to %.2f rad, lowest part %.2f m off the ground, on its back %s" % [grabbed, fell, int(body.get("flops")) - flops_before, angle, lowest, flat], problems)
	await _seconds(Constants.SKATE_WIPEOUT_SECONDS + 0.3)


## m. A NICE BOY standing on County Road 9 (stunned, so he stays put; out of the
## "nice_crew" group, so the director doesn't tidy him away), ridden into at 9 m/s.
## He's solid (layer 1, like a wall), but it's a bump: a "bump" wipeout, not a
## "wall" one, and his light bonk brings the crew's heat (HEAT_CREW_BONK). Three
## runs, each starting a third of a tick's travel further back, so at least two
## of them reach his capsule on the tick that hits it rather than stopping inside
## SKATE_BONK_RADIUS a tick early (the run-up the review found a wall bail on).
func _into_nice_boy(me: CharacterBody3D, skate: Node, world: Node, road: Vector3, along: Vector3, problems: Array[String]) -> void:
	var heat := get_tree().get_first_node_in_group("heat")
	var crew := (load("res://npcs/crew_member.tscn") as PackedScene).instantiate() as CharacterBody3D
	crew.name = "SkateTestCrew"
	var npcs := world.get_node_or_null("Npcs")
	(npcs if npcs != null else world).add_child(crew, true)
	crew.remove_from_group("nice_crew")
	var speed := 9.0
	var step := speed / float(Engine.physics_ticks_per_second)
	for run: int in 3:
		crew.global_position = road + along * 8.0
		crew.velocity = Vector3.ZERO
		crew.set("_stun_left", 60.0)
		await _seconds(0.4)
		var heat_before := float(heat.get("heat")) if heat != null else 0.0
		var walls_before := int((skate.get("wipeouts") as Dictionary).get("wall", 0))
		var bumps_before := int((skate.get("wipeouts") as Dictionary).get("bump", 0))
		await _ride_from(me, skate, road + along * (2.5 - step * float(run) / 3.0), along, speed)
		var fell := await _until_wipeout(me, 2.5)
		await _ticks(3)
		var rise := (float(heat.get("heat")) if heat != null else 0.0) - heat_before
		var bumps := int((skate.get("wipeouts") as Dictionary).get("bump", 0)) - bumps_before
		var walls := int((skate.get("wipeouts") as Dictionary).get("wall", 0)) - walls_before
		_verdict(fell and bumps == 1 and walls == 0 and rise >= Constants.HEAT_CREW_BONK - 0.5, "m. into a NICE BOY at %.0f m/s (run %d): wipeout %s, bumps %d, walls %d, heat +%.1f" % [speed, run + 1, fell, bumps, walls, rise], problems)
		if heat != null:
			heat.set("heat", heat_before)
		await _seconds(Constants.SKATE_WIPEOUT_SECONDS + 0.3)
	crew.queue_free()


## Teleport the host's player onto its feet at, facing yaw.
func _put(me: Node3D, at: Vector3, yaw: float) -> void:
	me.call("apply_network_teleport", Transform3D(Basis(Vector3.UP, yaw), at))


## On the board at from, rolling along dir at speed (no pushing).
func _ride_from(me: CharacterBody3D, skate: Node, from: Vector3, dir: Vector3, speed: float) -> void:
	if bool(me.get("on_board")):
		skate.call("dismount", false)
	_put(me, from, atan2(-dir.x, -dir.z))
	await _ticks(3)
	if not bool(me.get("on_board")):
		skate.call("toggle")
	skate.set("dev_input", {"push": false})
	me.velocity = Vector3(dir.x, 0.0, dir.z).normalized() * speed
	await _ticks(1)


## A wall in Homie Depot's lot, square on to a run of hard ground: {hit, dir}.
func _find_wall() -> Dictionary:
	var space := (get_tree().get_first_node_in_group("world") as Node3D).get_world_3d().direct_space_state
	for z: float in [0.0, -3.0, 3.0, 6.0, -6.0, 9.0]:
		for dir: Vector3 in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD]:
			var from := Vector3(2.0, 0.9, z)
			var query := PhysicsRayQueryParameters3D.create(from, from + dir * 30.0, 1)
			var hit := space.intersect_ray(query)
			if hit.is_empty() or not hit["collider"] is StaticBody3D:
				continue
			var normal: Vector3 = hit["normal"]
			var point: Vector3 = hit["position"]
			if normal.dot(-dir) < 0.9 or from.distance_to(point) < 7.0:
				continue
			var clear := true
			for step: int in range(1, 7):
				var on := point - dir * float(step)
				var ground := TownMap.surface_at(on)
				if ground == &"grass" or ground == &"water":
					clear = false
			# Nothing in the way on the run up (a car, a lamp).
			var low := PhysicsRayQueryParameters3D.create(point - dir * 6.5 + Vector3(0.0, -0.5, 0.0), point - dir * 0.3 + Vector3(0.0, -0.5, 0.0), 1)
			var blocked := space.intersect_ray(low)
			if clear and (blocked.is_empty() or (blocked["position"] as Vector3).distance_to(point) < 0.6):
				return {"hit": Vector3(point.x, 0.0, point.z), "dir": dir}
	return {}


## From the street onto a Maple Row lawn, heading -Z, with nothing in the way: {from}.
func _lawn_run() -> Dictionary:
	var house := TownMap.test_site_house()
	var yard := TownMap.yard_transform(house)
	var space := (get_tree().get_first_node_in_group("world") as Node3D).get_world_3d().direct_space_state
	for x: float in [-12.0, -8.0, 12.0, 15.0, -15.0]:
		var from := yard * Vector3(x, 0.05, 32.0)
		var into := yard * Vector3(x, 0.05, 12.0)
		if TownMap.surface_at(into) != &"grass" or TownMap.surface_at(from) == &"grass":
			continue
		var query := PhysicsRayQueryParameters3D.create(from + Vector3(0.0, 0.6, 0.0), into + Vector3(0.0, 0.6, 0.0), 1)
		if space.intersect_ray(query).is_empty():
			return {"from": from}
	return {}


func _until_landed(me: CharacterBody3D, limit: float) -> void:
	var clock := 0.0
	var left := false
	while clock < limit:
		await get_tree().physics_frame
		clock += get_physics_process_delta_time()
		left = left or not me.is_on_floor()
		if left and me.is_on_floor() and clock > 0.2:
			return


func _until_wipeout(me: Node, limit: float) -> bool:
	var clock := 0.0
	while clock < limit:
		if bool(me.get("wipeout")):
			return true
		await get_tree().physics_frame
		clock += get_physics_process_delta_time()
	return bool(me.get("wipeout"))


func _speed(me: CharacterBody3D) -> float:
	return Vector2(me.velocity.x, me.velocity.z).length()


func _seconds(seconds: float) -> void:
	var clock := 0.0
	while clock < seconds:
		await get_tree().physics_frame
		clock += get_physics_process_delta_time()


func _ticks(count: int) -> void:
	for index: int in count:
		await get_tree().physics_frame


func _me() -> CharacterBody3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as CharacterBody3D
	return null


func _verdict(ok: bool, line: String, problems: Array[String]) -> void:
	print("[SkateTest] %s: %s" % [line, ok])
	if not ok:
		problems.append(line)


func _finish(ok: bool, problems: Array) -> void:
	var skate := _me().call("skate") as Node if _me() != null else null
	result = {"ok": ok, "problems": problems, "done": true}
	if skate != null:
		result["tricks"] = (skate.get("tricks") as Dictionary).duplicate()
		result["wipeouts"] = (skate.get("wipeouts") as Dictionary).duplicate()
		result["best_score"] = int(skate.get("best_score"))
	print("[SkateTest] done: ok=%s %s" % [ok, problems])
