extends Node

## Authority: host. --skate-test (with --town-map, a client named Target joined)
## rides the Gutter Shredder (player/skate.gd, driving chunk G1) through the
## real paths, on the host's own player, its keys pressed through Skate.dev_input:
##   a. the board key does nothing without a board; with $100 granted, Homie
##      Depot sells the board ($60 off the wallet, the unlock on it).
##   b. on County Road 9 the board key gets you on.
##   c. 3 s of pushing: 7 m/s or more; 2 s coasting: slower, still over 4.
##   d. an ollie: 0.4 m up or more, down again, one ollie counted.
##   e. an ollie with a kickflip, landed: a line worth 200 or more.
##   f. a 90 degree spin landed sideways: a wipeout, flat on your back (KNOCKED),
##      and back up within 3 s.
##   g. into a wall at 6 m/s: a wipeout.
##   h. off the street onto a lawn at 8 m/s: a lawn bail.
##   i. holding something heavy (a junk toilet), the board key won't get you on.
## The client's view of the host (it saw the host on a board, a kickflip, a
## wipeout: "skate_seen") is checked by CI from the probe reports.
## Each step prints a [SkateTest] line.

const _Skate = preload("res://player/skate.gd")

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
	_verdict(mounted and surface == &"asphalt", "b. on the board on County Road 9 (%s)" % surface, problems)
	if not mounted:
		_finish(false, problems)
		return
	# c. Push, then coast.
	skate.set("dev_input", {"push": true})
	await _seconds(3.0)
	var pushed := _speed(me)
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
	_finish(problems.is_empty(), problems)


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
