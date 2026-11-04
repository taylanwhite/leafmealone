extends Node

## Authority: host and client. --yard-test checks the yard's edges and the people
## on it (fx-yard, docs/GAME.md "The yard's edges and the people on it"). Run in
## the connected town with --town-map --job-seed=777 --yard-size=1 --start-hour=10
## on the host and a joined client named Target 150 ms away, both with --yard-test.
##
## Host:
##   bin       inside Homie Depot, a teammate stands between you and the rake bin:
##             looking at the bin, E is the bin's ("[E] Look"), not "Grab"; the
##             client tries the same with the host in front of it (its half).
##   fence     the job yard's fence is solid: walking into the back fence stops
##             you at the pickets (not through them), a bag shoved at it stays in
##             the yard; the client walks into a side fence and stops too.
##   framed    talk to the homeowner looking well off to her side: she answers
##             from a spot in your view, or your view eases round onto her, so
##             she ends within HOMEOWNER_FRAME_OFF_CENTER of its middle, still
##             inside her stage radius; the client's talk too, on its own screen.
##   hedge     Chefty driven flat out at the town's hedgerow is caught by it: it
##             slows in the hedge's band, stops at the leaves and never crashes
##             (no dent, nothing thrown, on either peer); at an angle it's turned
##             away from the hedge.
##   barricade Chefty driven through a ROAD CLOSED barricade keeps most of its
##             speed and doesn't crash; on foot the client stops at it.
##             In its band (VehicleSim.town_edge stepped alone), a truck leaving
##             toward town or backing out nose in isn't steered at all.
##   catch_up  a teammate's drawn body after a gap in their updates (a stalled
##             peer's burst) glides back onto the stream instead of jumping.
##   bunched   a teammate's late update and the one bunched right behind it are
##             drawn at the players' pace cap, not as a leap.
## fx-w9 (W9's leftovers, docs/GAME.md "Fixes a player bumps into"):
##   shove     walking past a leaf bag lying beside your line leaves it be;
##             walking into one nudges it ahead no faster than PROP_SHOVE_SPEED_MAX.
##   hands_hop a hired hand riding Chefty's bed hops off at the yard: they stand
##             beside their own seat's rail, and wait out the hop before working.
##   down      knocked flat behind Chefty's tailgate: E does nothing and the bed
##             won't take you; on your feet again, it does.
##   fence_give Chefty floored into a fence (a run given to the fence give, with a
##             solid like the yard's): it bows and holds, no crash, no dent, the
##             nose within FENCE_GIVE_DEPTH of the pickets; the job yard's fence
##             is given to it too.
##   town_fence the town's own fences are solid to people (walking into one stops
##             you at it) and Chefty noses into one off the street without a crash.
## Each step prints a [YardTest] line; CI needs both peers' ok.

static var result: Dictionary = {}

const _Vehicles = preload("res://props/vehicles.gd")
const _Strings = preload("res://ui/strings.gd")
const _TownLine = preload("res://levels/town/town_line.gd")
const _LotGenerator = preload("res://levels/lots/lot_generator.gd")
const _NetSmoother = preload("res://net/components/net_smoother.gd")
const _FenceGive = preload("res://net/components/fence_give.gd")

var _started: bool = false
var _client_ready: bool = false
var _ok: bool = true
var _steps: Dictionary = {}
## Host: the client's answers to each of its halves, by name.
var _answers: Dictionary = {}


func _ready() -> void:
	result = {"ok": false, "steps": {}}


@rpc("any_peer", "call_remote", "reliable")
func _rpc_ready() -> void:
	if Net.is_host():
		_client_ready = true


## Client -> host: its half of a step.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_answer(step: String, report: Dictionary) -> void:
	if Net.is_host():
		_answers[step] = report


## Host -> client: do your half of a step.
@rpc("authority", "call_remote", "reliable")
func _rpc_do(step: String, args: Dictionary) -> void:
	if Net.is_host():
		return
	var report: Dictionary = {}
	match step:
		"bin":
			report = await _client_bin(args)
		"fence":
			report = await _client_fence(args)
		"framed":
			report = await _client_framed(args)
		"crashes":
			report = _crash_report()
		"barricade":
			report = await _client_barricade(args)
	_rpc_answer.rpc_id(1, step, report)


## Host -> client: done.
@rpc("authority", "call_remote", "reliable")
func _rpc_finish(ok: bool) -> void:
	if not Net.is_host():
		result["ok"] = ok
		result["done"] = true


func _process(_delta: float) -> void:
	if _started or _me() == null or get_tree().get_first_node_in_group("chefty") == null:
		return
	_started = true
	if Net.is_host():
		_run_host()
	else:
		await _seconds(1.5)
		_rpc_ready.rpc_id(1)
		# Safety net: the host finishes us; if it never does, stop anyway.
		await _seconds(170.0)
		result["done"] = true


# ---------------------------------------------------------------- host

func _run_host() -> void:
	var waited := 0.0
	while not _client_ready and waited < 30.0:
		await _seconds(0.25)
		waited += 0.25
	print("[YardTest] client ready: %s (after %.1f s)" % [_client_ready, waited])
	if not _client_ready or _other() == null:
		_finish(false)
		return
	await _seconds(1.0)
	await _catch_up()
	await _bunched()
	await _bin()
	await _fence()
	await _shove()
	await _hands_hop()
	await _down()
	await _fence_give()
	await _town_fence()
	await _framed()
	await _hedge()
	await _barricade()
	_finish(_ok)


## Asks the client for its half and waits for the answer ({} on a timeout).
func _ask(step: String, args: Dictionary, timeout: float) -> Dictionary:
	_answers.erase(step)
	_rpc_do.rpc_id(_other().name.to_int(), step, args)
	var waited := 0.0
	while not _answers.has(step) and waited < timeout:
		await _seconds(0.1)
		waited += 0.1
	return _answers.get(step, {})


func _bin() -> void:
	var bin := get_tree().get_first_node_in_group("rake_bin") as Node3D
	if bin == null:
		_check("bin: Homie Depot has its rake bin", false, "no rake_bin")
		return
	var spots := _bin_spots(bin)
	var me := _me()
	# The client between you and the bin, facing it, browsing.
	_teleport(_other(), spots["mate"], float(spots["yaw"]))
	_place_looking(me, spots["me"], spots["look"])
	await _seconds(1.0)
	_place_looking(me, spots["me"], spots["look"])
	await _ticks(2)
	var choice: Dictionary = me.call("e_choice")
	var says := str((choice["hint"] as Dictionary).get("text", ""))
	var mate_near := _flat(_other().global_position, me.global_position) < Constants.E_GRAB_REACH
	_check("bin: a teammate in front of the rake bin, looking at the bin: E is the bin's, not Grab", mate_near and StringName(choice["do"]) == &"source" and choice["target"] == bin and says == str(_Strings.SHOP_UI["prompt_look_at"]),
		"teammate %.2f m away, E would %s '%s'" % [_flat(_other().global_position, me.global_position), choice["do"], says])
	# Swapped: the host browses, the client looks past it at the bin.
	_place(me, spots["mate"], float(spots["yaw"]))
	await _seconds(0.6)
	var answer := await _ask("bin", {"at": spots["me"], "look": spots["look"]}, 10.0)
	_check("bin: the client, the host in front of the bin: its E is the bin's too", bool(answer.get("ok", false)), str(answer))


## Where the bin test stands: the browsing teammate right in front of the bin,
## the one pressing E behind them, and the bin's middle to look at.
func _bin_spots(bin: Node3D) -> Dictionary:
	var front: Vector3 = bin.call("slot_front", 0)
	var slot: Dictionary = (bin.get("slots") as Array)[0]
	var middle := bin.to_global((slot["at"] as Vector3) + Vector3(0.0, (slot["size"] as Vector3).y * 0.5, 0.0))
	var out := Vector3(front.x - middle.x, 0.0, front.z - middle.z).normalized()
	var mate := Vector3(front.x, bin.global_position.y + 0.05, front.z) + out * 0.15
	var me := mate + out * 0.85
	return {"mate": mate, "me": me, "look": middle, "yaw": atan2(out.x, out.z)}


func _fence() -> void:
	var lot := await _job_lot()
	if lot == null:
		_check("fence: the job yard is there", false, "no job_lot")
		return
	var body := lot.find_child("FenceBody", true, false) as StaticBody3D
	var me := _me()
	# Into the back fence, from 2.6 m inside it, at a walk.
	var yaw := lot.global_rotation.y
	var start := lot.to_global(Vector3(3.0, 0.1, _LotGenerator.FENCE_RUNS[0][0].z + 2.6))
	_teleport(_other(), lot.to_global(Vector3(-8.0, 0.1, 6.0)), yaw)
	_place(me, start, yaw)
	await _seconds(0.5)
	Input.action_press("move_forward")
	await _seconds(2.2)
	Input.action_release("move_forward")
	await _ticks(3)
	var local := lot.to_local(me.global_position)
	var fence_z := float(_LotGenerator.FENCE_RUNS[0][0].z)
	var walked_up := local.z < fence_z + 0.8
	var stopped := local.z > fence_z + Constants.YARD_FENCE_SOLID_THICK * 0.5
	_check("fence: walking into the back fence stops you at the pickets, not through them", body != null and walked_up and stopped,
		"fence body %s, ended %.2f m from the fence line (yard side positive)" % [body != null, local.z - fence_z])
	# A bag shoved hard at it from 1.5 m stays in the yard.
	var world := get_tree().get_first_node_in_group("world")
	world.call("_spawn_bag", lot.to_global(Vector3(-3.0, 0.6, fence_z + 1.5)), 0)
	await _seconds(0.4)
	var bag := _nearest_bag(lot.to_global(Vector3(-3.0, 0.6, fence_z + 1.5)))
	if bag != null:
		(bag as RigidBody3D).linear_velocity = lot.global_basis * Vector3(0.0, 1.0, -7.0)
		await _seconds(1.6)
		var bag_z := lot.to_local(bag.global_position).z
		_check("fence: a bag shoved at the back fence stays in the yard", bag_z > fence_z, "the bag ended %.2f m from the fence line" % (bag_z - fence_z))
		bag.queue_free()
	else:
		_check("fence: a bag shoved at the back fence stays in the yard", false, "no bag spawned")
	# The client walks into the left fence, over 150 ms of lag.
	var side_x := float(_LotGenerator.FENCE_RUNS[1][0].x)
	var answer := await _ask("fence", {"start": lot.to_global(Vector3(side_x + 2.4, 0.1, -4.0)), "yaw": yaw + PI * 0.5, "lot": lot.global_transform, "fence_x": side_x}, 12.0)
	_check("fence: the client walks into the side fence and stops at it", bool(answer.get("ok", false)), str(answer))


## fx-w9: a walker only nudges what's in front of their feet, at a walk's share.
func _shove() -> void:
	var lot := await _job_lot()
	if lot == null:
		_check("shove: the job yard is there", false, "no job_lot")
		return
	var me := _me()
	var world := get_tree().get_first_node_in_group("world")
	var yaw := lot.global_rotation.y
	var ahead := -lot.global_basis.z
	var side := lot.global_basis.x
	_teleport(_other(), lot.to_global(Vector3(-8.0, 0.1, 6.0)), yaw)
	# A bag 0.7 m to the side of the line you sprint along.
	var start := lot.to_global(Vector3(6.0, 0.1, 4.0))
	var beside_at := start + ahead * 2.5 + side * 0.75 + Vector3.UP * 0.5
	world.call("_spawn_bag", beside_at, 0)
	await _seconds(1.2)
	var beside := _nearest_bag(beside_at)
	if beside == null:
		_check("shove: a bag on the lawn", false, "no bag spawned")
		return
	var rest := beside.global_position
	_place(me, start, yaw)
	await _seconds(0.3)
	Input.action_press("sprint")
	Input.action_press("move_forward")
	await _seconds(1.4)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	await _seconds(0.8)
	var passed := _flat(beside.global_position, rest)
	_check("shove: sprinting past a bag lying beside your line leaves it where it lay", passed < 0.15, "it moved %.2f m (the old shove kicked anything within 1.1 m)" % passed)
	# Straight into it: it's nudged along ahead, never faster than the cap.
	var behind := beside.global_position - ahead * 1.6
	_place(me, Vector3(behind.x, start.y, behind.z), yaw)
	await _seconds(0.4)
	var from := beside.global_position
	var fastest := 0.0
	Input.action_press("move_forward")
	for _tick: int in 60:
		await get_tree().physics_frame
		var vel := (beside as RigidBody3D).linear_velocity
		fastest = maxf(fastest, Vector2(vel.x, vel.z).length())
	Input.action_release("move_forward")
	await _seconds(0.6)
	var pushed := (beside.global_position - from).dot(ahead)
	_check("shove: walking into a bag nudges it ahead at most at PROP_SHOVE_SPEED_MAX", pushed > 0.2 and fastest <= Constants.PROP_SHOVE_SPEED_MAX + 0.4,
		"pushed %.2f m ahead, fastest %.2f m/s (cap %.1f)" % [pushed, fastest, Constants.PROP_SHOVE_SPEED_MAX])
	beside.queue_free()


## fx-w9: a hired hand riding in Chefty's bed hops off at the yard over their own
## rail (chefty_drive.gd draws the hop from the seat; hires.gd stands them there).
func _hands_hop() -> void:
	var chefty := get_tree().get_first_node_in_group("chefty")
	var hires := get_tree().get_first_node_in_group("hires")
	var lot := await _job_lot()
	if chefty == null or hires == null or lot == null or not chefty.has_method("hand_landing"):
		_check("hands_hop: Chefty, the hires and the yard", false, "missing")
		return
	var house := TownMap.test_site_house()
	var curb := TownMap.yard_transform(house) * Vector3(TownMap.CURB_POINT.x, 0.0, TownMap.YARD_STREET_Z + 2.2)
	chefty.call("dev_place", curb, -PI * 0.5)
	hires.call("dev_add_hand", "Gravy")
	await _seconds(0.6)
	var seat := -1
	for entry: Dictionary in chefty.call("cosmetic_riders"):
		if str(entry["name"]) == "Gravy":
			seat = int(entry["seat"])
	var landing: Dictionary = chefty.call("hand_landing", maxi(seat, 1))
	hires.call("spawn_on_lot")
	await _ticks(2)
	var hand: Node3D = null
	for node: Node in get_tree().get_nodes_in_group("crew_hands"):
		if str(node.get("hand_name")) == "Gravy":
			hand = node as Node3D
	if hand == null or seat < 0:
		_check("hands_hop: the hand rode in a bed seat and is on the yard", false, "seat %d, hand %s" % [seat, hand])
		hires.call("_handle_fire", "Gravy")
		return
	var off := _flat(hand.global_position, landing["at"] as Vector3)
	var at := hand.global_position
	var hop := float(hand.get("hop_seconds"))
	await _seconds(hop * 0.85)
	var still := _flat(hand.global_position, at)
	await _seconds(hop * 0.15 + Constants.HIRE_HOP_LAND_BEAT + 2.6)
	var went := _flat(hand.global_position, at)
	# Off to work (crew_hand.gd State: 5 is REST, what the hop holds them in).
	var working := int(hand.get("_state")) != 5 or went > 0.3
	_check("hands_hop: a hand in the bed lands beside their own seat's rail, waits out the hop, then works", off < 0.4 and hop > 0.5 and still < 0.1 and working,
		"seat %d, landed %.2f m from the rail spot, hop %.2f s, moved %.2f m during it, then state %d and %.2f m" % [seat, off, hop, still, int(hand.get("_state")), went])
	hires.call("despawn")
	hires.call("_handle_fire", "Gravy")
	await _seconds(0.3)


## fx-w9: flat on your back behind the tailgate, the bed won't take you.
func _down() -> void:
	var chefty := get_tree().get_first_node_in_group("chefty")
	var me := _me()
	if chefty == null or not chefty.has_method("request_enter"):
		_check("down: the drivable Chefty", false, "none")
		return
	chefty.call("dev_place", Constants.CHEFTY_PARK_SPOT, Constants.CHEFTY_PARK_YAW)
	await _seconds(0.4)
	var at: Transform3D = chefty.call("body_transform")
	var behind := at * (_Vehicles.CHEFTY_TAILGATE + Vector3(0.0, 0.0, 0.9))
	_place(me, Vector3(behind.x, behind.y + 0.1, behind.z), atan2(at.basis.z.x, at.basis.z.z))
	await _seconds(0.5)
	me.call("_apply_bonk", Vector3.ZERO, "heavy")
	var flat := await _until(func() -> bool: return bool(me.call("is_down")), 1.5)
	var choice: Dictionary = me.call("e_choice")
	chefty.call("request_enter", 2)
	await _seconds(0.4)
	var refused := int(chefty.call("seat_of", Net.local_peer_id())) < 0
	await _until(func() -> bool: return not bool(me.call("is_down")), float(Constants.BONK_STUN_SECONDS["heavy"]) + 2.0)
	await _seconds(0.4)
	_place(me, Vector3(behind.x, behind.y + 0.1, behind.z), atan2(at.basis.z.x, at.basis.z.z))
	await _seconds(0.3)
	chefty.call("request_enter", 2)
	var took := await _until(func() -> bool: return int(chefty.call("seat_of", Net.local_peer_id())) >= 0, 2.0)
	_check("down: knocked flat behind the tailgate, E does nothing and the bed won't take you; up again, it does", flat and StringName(choice["do"]) == &"down" and refused and took,
		"knocked down %s, E would %s, refused %s, in once up %s" % [flat, choice["do"], refused, took])
	if took:
		chefty.call("request_exit")
		await _seconds(1.6)


## fx-w9: Chefty into a fence: it bows and holds. A run given to the fence give
## out on the farm track (a solid like the yard's, which the chassis is kept out
## of), driven at flat out; and the job yard's own fence is given to it.
func _fence_give() -> void:
	var chefty := get_tree().get_first_node_in_group("chefty")
	var lot := await _job_lot()
	var yard_lines := 0
	if lot != null:
		# A truck's footprint just inside each of the back and side fences.
		for corner: Vector3 in [Vector3(0.0, 0.0, -15.8), Vector3(-18.0, 0.0, 0.0), Vector3(18.0, 0.0, 0.0)]:
			if not _FenceGive.contact(lot.to_global(corner), lot.global_rotation.y).is_empty():
				yard_lines += 1
	if not await _drive(chefty):
		_check("fence_give: at Chefty's wheel", false, "couldn't get in")
		return
	var crash := chefty.get_node("Crash")
	var before: Dictionary = crash.call("report")
	var face_z := Constants.TOWN_LINE_RECT.position.y + Constants.TOWN_LINE_WALL_INSIDE
	var x := TownMap.DEPOT_X - 24.0
	# Clear of the hedge's band (its face + TOWN_EDGE_BAND), on the hedge test's own ground.
	var fence_z := face_z + 14.0
	var holder := StaticBody3D.new()
	holder.name = "YardTestFence"
	holder.collision_layer = 1
	add_child(holder)
	var box := BoxShape3D.new()
	box.size = Vector3(12.0, 1.0, Constants.YARD_FENCE_SOLID_THICK)
	var shape := CollisionShape3D.new()
	shape.shape = box
	holder.add_child(shape)
	holder.global_position = Vector3(x, 0.5, fence_z)
	_FenceGive.add_body(holder)
	_FenceGive.add(Vector3(x - 6.0, 0.0, fence_z), Vector3(x + 6.0, 0.0, fence_z), holder)
	await _ticks(2)
	var run := await _run_at(chefty, Vector3(x, 0.5, fence_z + 26.0 + Constants.CHEFTY_HALF_LENGTH), 0.0, 4.5)
	var after: Dictionary = crash.call("report")
	var nose := (run["pos"] as Vector3).z - Constants.CHEFTY_HALF_LENGTH - fence_z
	var crashed := int(after["crashes_seen"]) - int(before["crashes_seen"])
	_check("fence_give: flat out into a fence, it bows and holds: no crash, no dent, the nose at the pickets", float(run["top"]) > 12.0 and float(run["end_speed"]) < 1.5 and nose > -(Constants.FENCE_GIVE_DEPTH + 0.25) and nose < 0.8 and crashed == 0 and int(chefty.call("dents")) == 0 and yard_lines >= 3,
		"top %.1f m/s, ended at %.1f m/s, the nose %.2f m from the pickets (yard side +), crashes %d, dents %d; the job yard's back and side fences given to it: %d of 3" % [float(run["top"]), float(run["end_speed"]), nose, crashed, int(chefty.call("dents")), yard_lines])
	_FenceGive.remove_owner(holder)
	holder.queue_free()
	chefty.call("request_exit")
	await _seconds(1.2)


## fx-w9: the town's own fences: solid to people, and Chefty noses into one.
func _town_fence() -> void:
	var colliders := get_tree().get_first_node_in_group("town_colliders")
	var me := _me()
	var chefty := get_tree().get_first_node_in_group("chefty")
	var foot := colliders.get_node_or_null("TownLineFoot") as Node3D if colliders != null else null
	if foot == null:
		_check("town_fence: the town's colliders", false, "none")
		return
	await _until(func() -> bool: return _town_fence_shapes(foot).size() > 20, 20.0)
	var shapes := _town_fence_shapes(foot)
	var space := me.get_world_3d().direct_space_state
	var picked: Dictionary = {}
	for shape: CollisionShape3D in shapes:
		if (shape.shape as BoxShape3D).size.x < 3.0 or shape.disabled:
			continue
		var mid := shape.global_position
		mid.y = 0.0
		var normal := shape.global_basis.z
		normal.y = 0.0
		normal = normal.normalized()
		for sign: float in [1.0, -1.0]:
			var out := normal * sign
			var far := mid + out * 13.0
			var ray := PhysicsRayQueryParameters3D.create(far + Vector3.UP * 0.9, mid + Vector3.UP * 0.9 + out * 0.3, 1 | Constants.VEHICLE_LAYER)
			var floor := PhysicsRayQueryParameters3D.create(far + Vector3.UP * 2.0, far + Vector3.DOWN * 1.0, 1)
			if space.intersect_ray(ray).is_empty() and not space.intersect_ray(floor).is_empty():
				picked = {"mid": mid, "out": out}
				break
		if not picked.is_empty():
			break
	if picked.is_empty():
		_check("town_fence: a town fence with open street in front of it", false, "%d fence shapes, none clear" % shapes.size())
		return
	var mid: Vector3 = picked["mid"]
	var out: Vector3 = picked["out"]
	# On foot, from 2.4 m out, at a walk.
	var start := mid + out * 2.4 + Vector3.UP * 0.1
	_place(me, start, atan2(out.x, out.z))
	await _seconds(0.5)
	Input.action_press("move_forward")
	await _seconds(1.8)
	Input.action_release("move_forward")
	await _ticks(3)
	var from_line := (me.global_position - mid).dot(out)
	var stopped := from_line > Constants.YARD_FENCE_SOLID_THICK * 0.5 and from_line < 0.8
	# Chefty, off the street, at it.
	var crash := chefty.get_node("Crash")
	var before: Dictionary = crash.call("report")
	var nosed := false
	var detail := "couldn't get in"
	if await _drive(chefty):
		var run := await _run_at(chefty, mid + out * 13.0 + Vector3.UP * 0.5, atan2(out.x, out.z), 3.0)
		var after: Dictionary = crash.call("report")
		var nose := ((run["pos"] as Vector3) - mid).dot(out) - Constants.CHEFTY_HALF_LENGTH
		var crashed := int(after["crashes_seen"]) - int(before["crashes_seen"])
		nosed = crashed == 0 and nose > -(Constants.FENCE_GIVE_DEPTH + 0.3) and nose < 1.0 and float(run["end_speed"]) < 1.5
		detail = "top %.1f m/s, the nose %.2f m from the pickets, crashes %d" % [float(run["top"]), nose, crashed]
		chefty.call("request_exit")
		await _seconds(1.2)
	_check("town_fence: walking into a town fence stops you at it; Chefty noses into one off the street, no crash", stopped and nosed,
		"%d fence runs; on foot stopped %.2f m off it; %s" % [shapes.size(), from_line, detail])


func _town_fence_shapes(foot: Node) -> Array[CollisionShape3D]:
	var out: Array[CollisionShape3D] = []
	for child: Node in foot.get_children():
		if child is CollisionShape3D and str(child.name).begins_with("Fence") and (child as CollisionShape3D).shape is BoxShape3D:
			out.append(child as CollisionShape3D)
	return out


func _framed() -> void:
	var ho := get_tree().get_first_node_in_group("homeowner") as Node3D
	if ho == null:
		_check("framed: a homeowner on the yard", false, "none")
		return
	var me := _me()
	_teleport(_other(), ho.global_position + Vector3(9.0, 0.1, 9.0), 0.0)
	# Let her settle back home first.
	_place(me, ho.global_position + Vector3(0.0, 0.1, 9.0), 0.0)
	await _until(func() -> bool: return float(ho.call("walk_speed")) <= 0.0, 6.0)
	await _seconds(0.6)
	for case: Array in [["host", 0.85], ["host wide", 1.45]]:
		var home := ho.global_position
		var stand := _talk_spot(ho, 2.5)
		if not stand.is_finite():
			_check("framed: %s: a clear spot to talk from" % case[0], false, "none round her")
			continue
		var toward := atan2(-(home.x - stand.x), -(home.z - stand.z))
		# Looking well off to her side (the prompt is by reach, not by look).
		_place(me, stand, toward + float(case[1]))
		me.set("head_pitch", 0.0)
		await _ticks(4)
		var eased_before := int(ho.get("frames_eased"))
		var off_before := _view_off(me, ho)
		ho.call("_ask", true)
		await _seconds(0.3)
		await _until(func() -> bool: return float(ho.call("walk_speed")) <= 0.0, 6.0)
		await _seconds(Constants.P1_COUNTER_FRAME_SECONDS + 0.4)
		var off_after := _view_off(me, ho)
		var home_off := Vector2(ho.position.x - (ho.get("_home") as Vector3).x, ho.position.z - (ho.get("_home") as Vector3).z).length()
		_check("framed: %s: talking while looking off to her side, she ends in the middle of the view" % case[0], off_after <= rad_to_deg(Constants.HOMEOWNER_FRAME_OFF_CENTER) + 3.0 and home_off <= Constants.HOMEOWNER_STAGE_RADIUS + 0.05,
			"%.0f deg off before, %.0f deg after (view eased %d), %.2f m from where she waits" % [off_before, off_after, int(ho.get("frames_eased")) - eased_before, home_off])
		# Back to waiting for the next talk, and out of her way.
		ho.set("_phase", 0)
		_place(me, home + Vector3(0.0, 0.1, 9.0), 0.0)
		await _until(func() -> bool: return float(ho.call("walk_speed")) <= 0.0 and float(Vector2(ho.position.x - (ho.get("_home") as Vector3).x, ho.position.z - (ho.get("_home") as Vector3).z).length()) < 0.2, 8.0)
		await _seconds(0.5)
	# The client's own talk, on its own screen.
	var client_stand := _talk_spot(ho, 2.5)
	var answer := await _ask("framed", {"stand": client_stand, "home": ho.global_position, "turn": 1.2}, 16.0)
	_check("framed: the client talks looking off to her side; on its screen she ends in the middle", bool(answer.get("ok", false)), str(answer))
	ho.set("_phase", 0)


## A spot this far from her, clear of solids between, on the side away from the house.
func _talk_spot(ho: Node3D, away: float) -> Vector3:
	var space := ho.get_world_3d().direct_space_state
	var front := -ho.global_basis.z
	front.y = 0.0
	front = front.normalized() if front.length() > 0.01 else Vector3.BACK
	for turn: float in [0.0, 0.6, -0.6, 1.2, -1.2, PI]:
		var dir := front.rotated(Vector3.UP, turn)
		var spot := ho.global_position + dir * away
		var ray := PhysicsRayQueryParameters3D.create(ho.global_position + Vector3.UP, spot + Vector3.UP + dir * 2.5, 1 | Constants.VEHICLE_LAYER)
		if space.intersect_ray(ray).is_empty():
			return spot + Vector3.UP * 0.1
	return Vector3.INF


## The hedge's own steering, stepped as the sim steps it (VehicleSim.town_edge is
## pure): in its band at the east hedge, nose in at an angle it turns the nose
## away; driving off toward town, or backing out nose in, it doesn't steer at all
## (it used to swing a leaving truck round to run along the hedge).
func _hedge_leaving() -> void:
	var face_x := Constants.TOWN_LINE_RECT.end.x - Constants.TOWN_LINE_WALL_INSIDE
	var start := Vector3(face_x - 5.0, 0.5, 0.0)
	var cases := {
		"leaving at 45 deg": [PI * 0.25, 7.0],
		"leaving straight": [PI * 0.5, 7.0],
		"leaving at 27 deg off": [1.10, 7.0],
		"backing out nose in": [-PI * 0.5 + 0.4, -4.0],
	}
	var drift: Array[String] = []
	var still := true
	for label: String in cases:
		var yaw := float(cases[label][0])
		var pose := _edge_steps(start, yaw, float(cases[label][1]), 1.5)
		var turned := absf(wrapf(float(pose["yaw"]) - yaw, -PI, PI))
		drift.append("%s %.3f rad" % [label, turned])
		still = still and turned < 0.02
	var nose_in := -PI * 0.5 + 0.5
	var into := _edge_steps(start + Vector3(-3.0, 0.0, 0.0), nose_in, 7.0, 0.6)
	var into_before := VehicleSim.forward_of(nose_in).dot(Vector3.RIGHT)
	var into_after := VehicleSim.forward_of(float(into["yaw"])).dot(Vector3.RIGHT)
	_check("hedge_leaving: in the hedge's band, leaving or backing out isn't steered; nose in, it's turned away", still and into_after < into_before - 0.05,
		"%s; nose in %.2f -> %.2f" % [", ".join(drift), into_before, into_after])


## VehicleSim.town_edge alone at 60 Hz for seconds: the truck at pos heading yaw,
## moving at `along` m/s along its nose (negative: backing). {pos, yaw}.
func _edge_steps(pos: Vector3, yaw: float, along: float, seconds: float) -> Dictionary:
	var dt := 1.0 / 60.0
	var vel := VehicleSim.forward_of(yaw) * along
	for tick: int in int(seconds / dt):
		var edge := VehicleSim.town_edge(pos, yaw, vel, dt)
		vel = edge[0]
		yaw = wrapf(yaw + float(edge[1]), -PI, PI)
		# The driver holds their line: the speed kept along the (new) nose.
		vel = VehicleSim.forward_of(yaw) * vel.dot(VehicleSim.forward_of(yaw))
		pos += vel * dt
	return {"pos": pos, "yaw": yaw}


func _hedge() -> void:
	_hedge_leaving()
	var chefty := get_tree().get_first_node_in_group("chefty")
	if not await _drive(chefty):
		_check("hedge: at Chefty's wheel", false, "couldn't get in")
		return
	var crash := chefty.get_node("Crash")
	var before: Dictionary = crash.call("report")
	var client_before := await _ask("crashes", {}, 6.0)
	var face_z := Constants.TOWN_LINE_RECT.position.y + Constants.TOWN_LINE_WALL_INSIDE
	# Head on at the north hedge, up the Depot Road farm track, flat out.
	# West of the farm track: the hedge itself, not its gate.
	var x := TownMap.DEPOT_X - 24.0
	var start := Vector3(x, 0.5, face_z + 32.0)
	var run := await _run_at(chefty, start, 0.0, 5.5)
	var after: Dictionary = crash.call("report")
	var pos := run["pos"] as Vector3
	var gap := pos.z - Constants.CHEFTY_HALF_LENGTH - face_z
	var crashed := int(after["crashes_seen"]) - int(before["crashes_seen"])
	_check("hedge: flat out at the hedgerow, Chefty is caught in the leaves and stops, no crash", float(run["top"]) > 12.0 and float(run["end_speed"]) < 1.5 and gap > -0.3 and gap < 1.5 and crashed == 0 and int(chefty.call("dents")) == 0,
		"top %.1f m/s, ended at %.1f m/s, its nose %.2f m short of the hedge's face, crashes %d, dents %d" % [float(run["top"]), float(run["end_speed"]), gap, crashed, int(chefty.call("dents"))])
	# At an angle: turned away along the hedge.
	var heading := -0.55
	var angled := await _run_at(chefty, Vector3(x - 30.0, 0.5, face_z + 30.0), heading, 5.5)
	var normal := Vector3.FORWARD
	var into_before := VehicleSim.forward_of(heading).dot(normal)
	var into_after := VehicleSim.forward_of(float(angled["yaw"])).dot(normal)
	after = crash.call("report")
	crashed = int(after["crashes_seen"]) - int(before["crashes_seen"])
	_check("hedge: at an angle, the hedge turns it away and it still doesn't crash", into_after < into_before - 0.1 and crashed == 0,
		"nose into the hedge %.2f before, %.2f after, crashes %d" % [into_before, into_after, crashed])
	var client_after := await _ask("crashes", {}, 6.0)
	_check("hedge: the client saw no crash either", not client_before.is_empty() and not client_after.is_empty() and int(client_after.get("crashes_seen", -1)) == int(client_before.get("crashes_seen", -2)),
		"client crashes %s -> %s" % [client_before.get("crashes_seen", "?"), client_after.get("crashes_seen", "?")])


func _barricade() -> void:
	var chefty := get_tree().get_first_node_in_group("chefty")
	var crash := chefty.get_node("Crash")
	var before: Dictionary = crash.call("report")
	var closure: Dictionary = {}
	for entry: Dictionary in _TownLine.closures():
		if str(entry["key"]) == "depot_n":
			closure = entry
	var at := _TownLine.barricade_at(closure)
	# Up to speed 40 m short of it, then through.
	var speeds: Array[float] = []
	var run := await _run_at(chefty, at + Vector3(0.0, 0.5, 40.0), 0.0, 4.5, func(pose: Dictionary) -> void:
		var z := (pose["pos"] as Vector3).z
		if z > at.z + 6.0 and z < at.z + 9.0:
			speeds.append(float(pose["speed"]))
		elif z < at.z - 6.0 and z > at.z - 9.0:
			speeds.append(-float(pose["speed"])))
	var going_in := 0.0
	var coming_out := 0.0
	for speed: float in speeds:
		if speed > 0.0:
			going_in = speed
		elif coming_out == 0.0:
			coming_out = -speed
	var after: Dictionary = crash.call("report")
	var crashed := int(after["crashes_seen"]) - int(before["crashes_seen"])
	var through := (run["pos"] as Vector3).z < at.z - 6.0
	_check("barricade: Chefty drives through a ROAD CLOSED barricade, keeps most of its speed, no crash", through and crashed == 0 and going_in > 8.0 and coming_out > going_in * 0.65,
		"through %s, %.1f m/s going in, %.1f m/s coming out, crashes %d" % [through, going_in, coming_out, crashed])
	chefty.call("request_exit")
	await _seconds(0.6)
	var answer := await _ask("barricade", {"start": at + Vector3(0.0, 0.1, 3.2), "yaw": 0.0, "line_z": at.z}, 12.0)
	_check("barricade: on foot, the client stops at the sawhorses", bool(answer.get("ok", false)), str(answer))


## Into Chefty's driver's seat (the connected town's drivable Chefty).
func _drive(chefty: Node) -> bool:
	if chefty == null or not chefty.has_method("request_enter"):
		return false
	chefty.call("dev_place", Constants.CHEFTY_PARK_SPOT, Constants.CHEFTY_PARK_YAW)
	await _seconds(0.3)
	var me := _me()
	for attempt: int in 4:
		if int(chefty.call("driver")) == Net.local_peer_id():
			return true
		var at: Transform3D = chefty.call("body_transform")
		me.call("apply_network_teleport", Transform3D(Basis.IDENTITY, at * _Vehicles.CHEFTY_DRIVER_DOOR + Vector3(0.0, 0.1, 0.0)))
		await _ticks(3)
		chefty.call("request_enter", 0)
		await _seconds(0.5)
	return int(chefty.call("driver")) == Net.local_peer_id()


## Chefty placed at `at` facing yaw, then flat out for seconds: {top, end_speed,
## pos, yaw}; watch (if valid) sees every tick's {pos, speed}.
func _run_at(chefty: Node, at: Vector3, yaw: float, seconds: float, watch: Callable = Callable()) -> Dictionary:
	chefty.call("dev_place", at, yaw)
	await _seconds(0.6)
	chefty.call("dev_script", Net.local_peer_id(), [{"throttle": 1.0, "seconds": seconds}, {"throttle": 0.0, "seconds": 0.05}])
	var top := 0.0
	var waited := 0.0
	while waited < seconds:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
		var pose: Dictionary = chefty.call("sim_pose")
		var speed := Vector2((pose["vel"] as Vector3).x, (pose["vel"] as Vector3).z).length()
		top = maxf(top, speed)
		if watch.is_valid():
			watch.call({"pos": pose["pos"], "speed": speed})
	var end: Dictionary = chefty.call("sim_pose")
	var end_speed := Vector2((end["vel"] as Vector3).x, (end["vel"] as Vector3).z).length()
	await _seconds(0.3)
	return {"top": top, "end_speed": end_speed, "pos": end["pos"], "yaw": float(end["yaw"])}


## The smoother on a stand-in teammate: walking at 3.5 m/s, its updates stop for
## 0.35 s and come back where it really is. Without the catch-up the drawn body
## jumps; with it, it never moves faster than the catch-up allows, and catches up.
func _catch_up() -> void:
	var before: Dictionary = await _catch_up_run(false)
	var after: Dictionary = await _catch_up_run(true)
	# The cap rides the stream's own speed, which jitters with when updates land:
	# a third over it is still a run, and a jump is several times it.
	var allowed := (float(after["stream"]) * Constants.SMOOTHER_CATCH_UP_SPEED_SHARE + Constants.SMOOTHER_CATCH_UP_SPEED_MIN) * 1.35
	# Drawn without the cap the body no longer jumps in one frame either: fx-net's
	# smoother glides from where it was drawn over delay_seconds. That glide is
	# still faster than a run; the cap must hold it below it (W9 integration).
	_check("catch_up: after a 0.35 s gap a teammate's body glides back onto the stream, never jumping", float(after["jump"]) > 0.8 and float(before["fastest"]) > float(after["fastest"]) * 1.2 and float(after["fastest"]) <= allowed and float(after["behind"]) < 3.5 * 0.1 + 0.3,
		"the stream jumped %.2f m; drawn as it came the body went %.1f m/s, caught up never faster than %.1f m/s (allowed %.1f), ended %.2f m behind" % [float(after["jump"]), float(before["fastest"]), float(after["fastest"]), allowed, float(after["behind"])])


## A teammate's pace (the players' cap, NetSmoother.paced standing in for being
## in "players"): walking at 3.5 m/s, a busy peer's update comes late and nearly
## where the last one was, the next lands right behind it where they really are
## (fx-yard rec_bin_1p 0.83 s, Bot2's 0.65 m pop). No gap long enough to count as
## a hitch, so only the pace cap can hold it. Drawn as it came the body leaps
## across that pair; paced it never goes faster than the cap allows.
func _bunched() -> void:
	var before: Dictionary = await _bunched_run(false)
	var after: Dictionary = await _bunched_run(true)
	var allowed := (3.5 * Constants.SMOOTHER_CATCH_UP_SPEED_SHARE + Constants.SMOOTHER_CATCH_UP_SPEED_MIN) * 1.35
	# fx-net's SMOOTHER_MIN_SPACING already spaces a bunched pair, so drawn without
	# the cap it no longer leaps far past a run; the cap still holds it lower, and
	# under what a run allows (W9 integration).
	_check("bunched: a teammate's late-then-bunched updates are drawn at their pace, not as a leap", int(after["bursts"]) >= 3 and float(before["fastest"]) > float(after["fastest"]) and float(after["fastest"]) <= allowed and float(after["behind"]) < 3.5 * 0.1 + 0.3,
		"%d bursts; drawn as they came the body went %.1f m/s, paced never faster than %.1f m/s (allowed %.1f), ended %.2f m behind" % [int(after["bursts"]), float(before["fastest"]), float(after["fastest"]), allowed, float(after["behind"])])


func _bunched_run(on: bool) -> Dictionary:
	var body := CharacterBody3D.new()
	body.name = "YardTestPaced"
	add_child(body)
	body.set_multiplayer_authority(_other().name.to_int())
	var visual := Node3D.new()
	visual.name = "Visual"
	body.add_child(visual)
	var smoother := _NetSmoother.new()
	smoother.visual_path = NodePath("../Visual")
	smoother.catch_up_on = on
	smoother.paced = true
	body.add_child(smoother)
	var speed := 3.5
	var fastest := 0.0
	var clock := 0.0
	var last_sent := 0.0
	var next_busy := 0.6
	# 0 sending at 30 Hz, 1 waiting on a busy peer, 2 the late one is in.
	var phase := 0
	var late_tick := 0
	var bursts := 0
	var span_from := Vector3.INF
	var span_at := 0.0
	while clock < 2.8:
		await get_tree().process_frame
		var now := clock
		if not span_from.is_finite():
			span_from = visual.global_position
			span_at = now
		elif now - span_at >= 1.0 / 60.0:
			fastest = maxf(fastest, visual.global_position.distance_to(span_from) / (now - span_at))
			span_from = visual.global_position
			span_at = now
		clock += get_process_delta_time()
		var send := Vector3.INF
		match phase:
			0:
				if clock - last_sent >= 1.0 / 30.0:
					send = Vector3(0.0, 0.0, -speed * clock)
					last_sent = clock
					if clock >= next_busy:
						phase = 1
			1:
				# Under delay_seconds since the last one: not a hitch.
				if clock - last_sent >= 0.085:
					send = Vector3(0.0, 0.0, -speed * (last_sent + 0.01))
					late_tick = Engine.get_physics_frames()
					phase = 2
			2:
				# Once the smoother's tick has taken the late one in.
				if Engine.get_physics_frames() > late_tick:
					send = Vector3(0.0, 0.0, -speed * clock)
					last_sent = clock
					next_busy = clock + 0.5
					bursts += 1
					phase = 0
		if send.is_finite():
			body.velocity = Vector3(0.0, 0.0, -speed)
			body.position = send
	var out := {"fastest": fastest, "bursts": bursts, "behind": visual.global_position.distance_to(Vector3(0.0, 0.0, -speed * clock))}
	body.queue_free()
	await _ticks(2)
	return out


func _catch_up_run(on: bool) -> Dictionary:
	# A CharacterBody: the smoother reads its velocity, as it does a player's.
	var body := CharacterBody3D.new()
	body.name = "YardTestMate"
	add_child(body)
	# Somebody else's body (the smoother leaves its own authority's alone).
	body.set_multiplayer_authority(_other().name.to_int())
	var visual := Node3D.new()
	visual.name = "Visual"
	body.add_child(visual)
	var smoother := _NetSmoother.new()
	smoother.visual_path = NodePath("../Visual")
	smoother.catch_up_on = on
	body.add_child(smoother)
	var speed := 3.5
	var fastest := 0.0
	var jump := 0.0
	var resumed := false
	var clock := 0.0
	var at := Vector3.ZERO
	var stalled_from := 1.0
	var stall := 0.35
	# The drawn body's speed over spans of a 60 Hz frame or more, on the frames'
	# own clock (what the catch-up caps): a headless run's sub-millisecond frames
	# would make a centimetre's rounding look like a sprint.
	var span_from := Vector3.INF
	var span_at := 0.0
	while clock < 2.6:
		await get_tree().process_frame
		# What the last frame drew (the visual is the body's child: read it before
		# the body moves under it).
		var now := clock
		if not span_from.is_finite():
			span_from = visual.global_position
			span_at = now
		elif now - span_at >= 1.0 / 60.0:
			fastest = maxf(fastest, visual.global_position.distance_to(span_from) / (now - span_at))
			span_from = visual.global_position
			span_at = now
		var dt := get_process_delta_time()
		clock += dt
		at = Vector3(0.0, 0.0, -speed * clock)
		# Updates every 1/30 s, none for the stall.
		var in_stall := clock > stalled_from and clock < stalled_from + stall
		if not in_stall and int(clock * 30.0) != int((clock - dt) * 30.0):
			var before := body.position
			body.velocity = Vector3(0.0, 0.0, -speed)
			body.position = at
			if clock >= stalled_from + stall and not resumed:
				resumed = true
				jump = before.distance_to(at)
	var out := {"jump": jump, "fastest": fastest, "behind": visual.global_position.distance_to(at), "stream": maxf(speed, jump / maxf(stall - _NetSmoother.STOP_AFTER_SECONDS, 0.05))}
	body.queue_free()
	await _ticks(2)
	return out


# ---------------------------------------------------------------- client halves

func _client_bin(args: Dictionary) -> Dictionary:
	var me := _me()
	_place_looking(me, args["at"], args["look"])
	await _seconds(0.8)
	# The host's own move in front of the bin comes 150 ms late.
	await _until(func() -> bool: return _other() != null and _flat(_other().global_position, me.global_position) < Constants.E_GRAB_REACH, 3.0)
	_place_looking(me, args["at"], args["look"])
	await _ticks(2)
	var choice: Dictionary = me.call("e_choice")
	var bin := get_tree().get_first_node_in_group("rake_bin")
	var says := str((choice["hint"] as Dictionary).get("text", ""))
	var mate := _other()
	var near := mate != null and _flat(mate.global_position, me.global_position) < Constants.E_GRAB_REACH
	return {"ok": near and StringName(choice["do"]) == &"source" and choice["target"] == bin, "do": str(choice["do"]), "says": says, "host_near": near, "host_at": mate.global_position if mate != null else Vector3.INF, "me_at": me.global_position}


func _client_fence(args: Dictionary) -> Dictionary:
	var me := _me()
	_place(me, args["start"], float(args["yaw"]))
	await _seconds(0.6)
	Input.action_press("move_forward")
	await _seconds(2.0)
	Input.action_release("move_forward")
	await _ticks(3)
	var lot: Transform3D = args["lot"]
	var local := lot.affine_inverse() * me.global_position
	var from_fence := local.x - float(args["fence_x"])
	return {"ok": from_fence > Constants.YARD_FENCE_SOLID_THICK * 0.5 and from_fence < 0.8, "from_fence": snappedf(from_fence, 0.01)}


func _client_framed(args: Dictionary) -> Dictionary:
	var me := _me()
	var ho := get_tree().get_first_node_in_group("homeowner") as Node3D
	var stand: Vector3 = args["stand"]
	var home: Vector3 = args["home"]
	if ho == null or not stand.is_finite():
		return {"ok": false, "why": "no homeowner or spot"}
	var toward := atan2(-(home.x - stand.x), -(home.z - stand.z))
	_place(me, stand, toward + float(args["turn"]))
	me.set("head_pitch", 0.0)
	await _seconds(0.5)
	var off_before := _view_off(me, ho)
	ho.call("_ask", true)
	await _seconds(1.0)
	await _until(func() -> bool: return float(ho.call("walk_speed")) <= 0.0, 6.0)
	await _seconds(Constants.P1_COUNTER_FRAME_SECONDS + 0.5)
	var off_after := _view_off(me, ho)
	return {"ok": off_after <= rad_to_deg(Constants.HOMEOWNER_FRAME_OFF_CENTER) + 3.0, "off_before": snappedf(off_before, 1.0), "off_after": snappedf(off_after, 1.0), "eased": int(ho.get("frames_eased"))}


func _client_barricade(args: Dictionary) -> Dictionary:
	var me := _me()
	_place(me, args["start"], float(args["yaw"]))
	await _seconds(0.6)
	Input.action_press("move_forward")
	await _seconds(1.8)
	Input.action_release("move_forward")
	await _ticks(3)
	var short := me.global_position.z - float(args["line_z"])
	return {"ok": short > 0.3 and short < 1.6, "short_of_the_row": snappedf(short, 0.01)}


func _crash_report() -> Dictionary:
	var chefty := get_tree().get_first_node_in_group("chefty")
	var crash := chefty.get_node_or_null("Crash") if chefty != null else null
	return crash.call("report") if crash != null else {}


# ---------------------------------------------------------------- helpers

func _job_lot() -> Node3D:
	var lot := get_tree().get_first_node_in_group("job_lot") as Node3D
	if lot != null:
		return lot
	var world := get_tree().get_first_node_in_group("world")
	var house := TownMap.test_site_house()
	world.call("place_job_site", TownMap.yard_transform(house), house)
	world.call("_load_job_lot")
	await _until(func() -> bool: return get_tree().get_first_node_in_group("homeowner") != null and get_tree().get_first_node_in_group("job_lot") != null, 15.0)
	await _seconds(1.0)
	return get_tree().get_first_node_in_group("job_lot") as Node3D


## How far (degrees) her face is off the middle of this player's view.
func _view_off(me: Node3D, ho: Node3D) -> float:
	var head := me.get_node_or_null("Visual/Head") as Node3D
	var eye := head.global_position if head != null else me.global_position + Vector3.UP * 1.6
	var aim := -(head.global_basis.z if head != null else me.global_basis.z)
	var face := ho.global_position + Vector3.UP * Constants.HOMEOWNER_FRAME_FACE_Y
	return rad_to_deg(aim.angle_to(face - eye))


func _finish(ok: bool) -> void:
	result["ok"] = ok
	result["steps"] = _steps
	print("[YardTest] all ok: %s" % ok)
	_rpc_finish.rpc(ok)
	result["done"] = true


func _check(step: String, passed: bool, detail: String) -> void:
	_ok = _ok and passed
	_steps[step] = passed
	print("[YardTest] %s %s (%s)" % ["ok  " if passed else "FAIL", step, detail])


func _me() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as Node3D
	return null


func _other() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name != str(Net.local_peer_id()) and not Net.is_watcher(node.name.to_int()):
			return node as Node3D
	return null


func _place(me: Node3D, at: Vector3, yaw: float) -> void:
	me.call("apply_network_teleport", Transform3D(Basis(Vector3.UP, yaw), at))
	me.set("body_yaw", yaw)


func _place_looking(me: Node3D, at: Vector3, point: Vector3) -> void:
	var eye := at + Vector3(0.0, 1.6, 0.0)
	var head := me.get_node_or_null("Visual/Head") as Node3D
	if head != null:
		eye = at + Vector3(0.0, head.global_position.y - me.global_position.y, 0.0)
	var flat := Vector2(point.x - eye.x, point.z - eye.z).length()
	_place(me, at, atan2(-(point.x - at.x), -(point.z - at.z)))
	me.set("head_pitch", atan2(point.y - eye.y, flat))


func _teleport(player: Node3D, at: Vector3, yaw: float) -> void:
	if player != null:
		player.call("send_teleport", Transform3D(Basis(Vector3.UP, yaw), at))


func _nearest_bag(near: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance := 3.0
	for node: Node in get_tree().get_nodes_in_group("props"):
		var prop := node as Node3D
		if prop == null or str(prop.get("kind")) != "leaf_bag" or prop.is_queued_for_deletion():
			continue
		var distance := prop.global_position.distance_to(near)
		if distance < best_distance:
			best_distance = distance
			best = prop
	return best


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _until(test: Callable, timeout: float) -> bool:
	var waited := 0.0
	while waited < timeout:
		if bool(test.call()):
			return true
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	return bool(test.call())


func _ticks(count: int) -> void:
	for _tick: int in count:
		await get_tree().physics_frame


func _seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
