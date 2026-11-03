extends Node

## Authority: host and client. --hands-test checks what your hands do (p1-hands,
## docs/GAME.md "What E does"; crew playtest 1). Run with --start-zone=lot
## --job-seed=777 --yard-size=1 --all-tools --start-hour=19 on the host and a
## joined client named Target, both with --hands-test.
##
## Host:
##   punch   a held left click on the yard with nobody in front never winds up a
##           punch (crew-04); with the Target in front it winds up, spins you out
##           once, and holding on doesn't wind up again.
##   board   at Chefty's pad with the Target beside you, E is Board, not Grab;
##           turned to look at them up close, it's Grab ("Grab", no name).
##   talk    by the homeowner with the wheelbarrow in reach, E is Talk; looking
##           at the wheelbarrow, it's Pick up.
##   hedge   by a hedge with a fresh bag in reach and no raid, E picks the bag up
##           (NB-07); in a raid, the hedge wins. The prompt is what E does.
##   fence   strokes pushed at the back fence never put leaves past it (NB-08);
##           without the fence line they would.
##   bag     a fresh bag sits at least BAG_SPAWN_AHEAD_MIN in front of the bagger,
##           on the ground, and grows from BAG_GROW_FROM to full size (crew-16).
##   barrow  a wheelbarrow knocked on its side rights itself (NB-14).
##   stars   your own dizzy stars are a small ring over your eye.
##   sleep   the Target lies down on a cot: the host draws it lying on that cot,
##           tag hidden; woken, it steps off the cot's foot (crew-06).
## Client: lying on its cot its own eye looks up from the pillow, low over the
## canvas. Each step prints a [HandsTest] line.

static var result: Dictionary = {}

const _Strings = preload("res://ui/strings.gd")
const _PropLooks = preload("res://props/prop_looks.gd")

var _started: bool = false
var _client_ready: bool = false
var _client_done: bool = false
var _ok: bool = true
var _steps: Dictionary = {}


@rpc("any_peer", "call_remote", "reliable")
func _rpc_ready() -> void:
	if Net.is_host():
		_client_ready = true


@rpc("any_peer", "call_remote", "reliable")
func _rpc_report(report: Dictionary) -> void:
	if Net.is_host():
		_steps["client"] = report
		_client_done = true


## Host -> client: you're done, finish.
@rpc("authority", "call_remote", "reliable")
func _rpc_finish() -> void:
	if not Net.is_host() and not bool(result.get("done", false)):
		result["done"] = true


func _process(_delta: float) -> void:
	if _started or _me() == null or get_tree().get_first_node_in_group("leaf_field") == null:
		return
	_started = true
	if Net.is_host():
		_run_host()
	else:
		_run_client()


# ---- host


func _run_host() -> void:
	var waited := 0.0
	while not _client_ready and waited < 25.0:
		await _seconds(0.25)
		waited += 0.25
	print("[HandsTest] client ready: %s (after %.1f s)" % [_client_ready, waited])
	if not _client_ready:
		_finish(false)
		return
	await _seconds(1.0)
	await _punch()
	await _talk()
	await _hedge()
	_fence()
	await _bag()
	await _barrow()
	_stars()
	await _board()
	await _sleep()
	# The client's own view of lying down.
	var waited_report := 0.0
	while not _client_done and waited_report < 8.0:
		await _seconds(0.25)
		waited_report += 0.25
	var client: Dictionary = _steps.get("client", {})
	_check("client: lying, its eye looks up from the pillow over the canvas; the mouse turns the head, not the body", bool(client.get("ok", false)), str(client))
	await _cot_press()
	# Last, since it drives off.
	await _board_press()
	_finish(_ok)


func _punch() -> void:
	var me := _me()
	var other := _other()
	var lot := get_tree().get_first_node_in_group("job_lot") as Node3D
	# Nobody near: the Target well away behind.
	var spot := lot.to_global(Vector3(-6.0, 0.0, 6.0))
	_place(me, spot, 0.0, 0.0)
	_teleport(other, spot + Vector3(0.0, 0.0, 6.0), 0.0)
	await _seconds(0.8)
	var wound := false
	me.set("dev_primary", 1)
	var held := 0.0
	while held < Constants.PUNCH_DIZZY_SECONDS + 0.8:
		await get_tree().physics_frame
		held += get_physics_process_delta_time()
		wound = wound or bool(me.get("winding"))
	var stunned := float(me.get("_stun_left")) > 0.0
	me.set("dev_primary", 0)
	await _seconds(0.3)
	_check("punch: a held click with nobody in front never winds up (crew-04)", not wound and not stunned, "wound %s, stunned %s" % [wound, stunned])
	# The Target a step in front: a punch winds up and spins you out, once.
	_teleport(other, spot + Vector3(0.0, 0.0, -1.0), PI)
	await _seconds(0.8)
	me.set("dev_primary", 1)
	held = 0.0
	var spun_at := -1.0
	var rewound := false
	wound = false
	while held < Constants.PUNCH_DIZZY_SECONDS + Constants.FAINT_SECONDS * 0.8 + 2.0:
		await get_tree().physics_frame
		held += get_physics_process_delta_time()
		var winding := bool(me.get("winding"))
		if spun_at < 0.0:
			wound = wound or winding
			if float(me.get("_stun_left")) > 0.0:
				spun_at = held
		elif winding:
			rewound = true
	me.set("dev_primary", 0)
	_check("punch: with someone in front it winds up and spins you out once; holding on doesn't wind up again", wound and spun_at > 0.0 and not rewound, "wound %s, spun at %.2f, wound again %s" % [wound, spun_at, rewound])
	await _seconds(Constants.FAINT_SECONDS)


func _talk() -> void:
	var me := _me()
	var homeowner := get_tree().get_first_node_in_group("homeowner") as Node3D
	var barrow := _prop_of("wheelbarrow")
	if homeowner == null or barrow == null:
		_check("talk: a homeowner and a wheelbarrow on the yard", false, "homeowner %s, barrow %s" % [homeowner, barrow])
		return
	_teleport(_other(), homeowner.global_position + Vector3(8.0, 0.0, 8.0), 0.0)
	var facing := -homeowner.global_basis.z
	facing.y = 0.0
	facing = facing.normalized()
	var stand := homeowner.global_position + facing * 1.6
	_place(me, stand, _yaw_toward(stand, homeowner.global_position), 0.0)
	# The wheelbarrow in reach, off to the side.
	var side := facing.cross(Vector3.UP).normalized()
	_put(barrow, stand + side * 1.2)
	await _seconds(0.6)
	var choice: Dictionary = me.call("e_choice")
	var text := str((choice["hint"] as Dictionary).get("text", ""))
	_check("talk: by the homeowner with a wheelbarrow in reach, E is Talk", StringName(choice["do"]) == &"source" and text == _Strings.UI["prompt_talk"], "%s '%s'" % [choice["do"], text])
	_look_at(me, stand, barrow.global_position + Vector3(0.0, _PropLooks.VISUAL_HEIGHT, 0.0))
	await _seconds(0.2)
	choice = me.call("e_choice")
	_check("talk: looking at the wheelbarrow, E picks it up", StringName(choice["do"]) == &"pick_up" and choice["target"] == barrow, "%s %s" % [choice["do"], choice["target"]])


func _hedge() -> void:
	var me := _me()
	var spot: Node3D = null
	for node: Node in get_tree().get_nodes_in_group("hide_spots"):
		if str(node.get("spot_kind")) == "hedge" and bool(node.call("has_room")):
			spot = node as Node3D
			break
	if spot == null:
		_check("hedge: the yard has a hedge", false, "")
		return
	var stand: Vector3 = spot.call("entry_point", 0, 0)
	_place(me, stand, _yaw_toward(stand, spot.global_position), -0.25)
	await _seconds(0.3)
	var world := get_tree().get_first_node_in_group("world")
	var ahead := -me.global_basis.z
	ahead.y = 0.0
	world.call("_spawn_bag", me.global_position + ahead.normalized() * 0.4 + me.global_basis.x * 0.5, 0)
	await _seconds(0.6)
	var bag := _nearest_bag(me.global_position)
	var choice: Dictionary = me.call("e_choice")
	var hint: Dictionary = me.call("interaction_hint")
	_check("hedge: no raid, a bag in reach by the hedge: E picks up the bag, and that's the prompt (NB-07)", bag != null and StringName(choice["do"]) == &"pick_up" and choice["target"] == bag and str(hint.get("text", "")) == _Strings.UI["prompt_pick_up_plain"], "%s %s '%s'" % [choice["do"], choice["target"], hint.get("text", "")])
	# A real press, through _input: the bag comes up, and you're not in the hedge.
	if bag != null:
		await _press_e()
		await _seconds(0.3)
		var held := int(bag.get("held_by")) == 1
		var dove := me.get("_hidden_spot") != null or bool(me.call("_hide_moving"))
		_check("hedge: pressing E by the hedge picks the bag up and doesn't dive in", held and not dove, "held_by %d, dove %s" % [int(bag.get("held_by")), dove])
		if held:
			bag.call("request_drop")
			await _seconds(0.3)
	var director := get_tree().get_first_node_in_group("run_director")
	director.call("_rpc_phase", 1, Net.server_time(), "")
	await _seconds(0.1)
	choice = me.call("e_choice")
	_check("hedge: in a raid, the hedge comes first", StringName(choice["do"]) == &"hide", str(choice["do"]))
	director.call("dev_reset")
	if bag != null:
		bag.queue_free()
	await _seconds(0.3)


func _fence() -> void:
	var field := get_tree().get_first_node_in_group("leaf_field") as Node3D
	var lot := get_tree().get_first_node_in_group("job_lot") as Node3D
	var lines: Array = field.get_meta("fence_lines", [])
	if lines.is_empty():
		_check("fence: the yard tells the field its fence", false, "")
		return
	var before := _density_past_fence(field, lot)
	var snapshot := _density_copy(field)
	var pushed := _push_at_fence(field, lot)
	var after := _density_past_fence(field, lot)
	# The same strokes with no fence, from the same leaves: they would cross it.
	_density_restore(field, snapshot)
	field.set_meta("fence_lines", [])
	_push_at_fence(field, lot)
	var unfenced := _density_past_fence(field, lot)
	_density_restore(field, snapshot)
	field.set_meta("fence_lines", lines)
	_check("fence: leaves raked into the back fence bank up on the yard side (NB-08)", pushed > 0 and after <= before and unfenced > before, "moved %d, past the fence %d -> %d (unfenced %d)" % [pushed, before, after, unfenced])


func _bag() -> void:
	var me := _me()
	var field := get_tree().get_first_node_in_group("leaf_field")
	var world := get_tree().get_first_node_in_group("world")
	var lot := get_tree().get_first_node_in_group("job_lot") as Node3D
	var stand := lot.to_global(Vector3(-6.0, 0.0, 6.0))
	_place(me, stand, 0.0, -0.3)
	await _seconds(0.3)
	var ahead := -me.global_basis.z
	ahead.y = 0.0
	# A pile right under the bagger's nose.
	world.call("_spawn_bag_for", field, me.global_position + ahead.normalized() * 0.5 + Vector3(0.0, 0.2, 0.0), int(Constants.MIN_BAG_CELLS * 80.0))
	await get_tree().process_frame
	var bag := _nearest_bag(me.global_position)
	if bag == null:
		_check("bag: a fresh bag", false, "")
		return
	var flat := Vector2(bag.global_position.x - me.global_position.x, bag.global_position.z - me.global_position.z)
	var look := bag.get_node_or_null("Visual/Look") as Node3D
	var small := look != null and look.scale.x < 0.8
	var low := bag.global_position.y < me.global_position.y + 0.3
	var in_front := flat.normalized().dot(Vector2(ahead.x, ahead.z).normalized()) > 0.7
	await _seconds(Constants.BAG_GROW_SECONDS + 0.2)
	var full := look != null and is_equal_approx(look.scale.x, 1.0)
	_check("bag: it sits a step ahead on the ground, and grows from the pile (crew-16)", flat.length() >= Constants.BAG_SPAWN_AHEAD_MIN - 0.05 and low and in_front and small and full, "%.2f m ahead, low %s, in front %s, small %s, full %s" % [flat.length(), low, in_front, small, full])
	bag.queue_free()
	# Two on one pile: the Target just past it, closer to it than the bagger.
	# The bag still goes a step in front of whoever bagged it, not at their feet.
	var pile := me.global_position + ahead.normalized() * 1.5 + Vector3(0.0, 0.2, 0.0)
	_teleport(_other(), Vector3(pile.x, me.global_position.y, pile.z) + ahead.normalized() * 0.6, 0.0)
	await _seconds(0.8)
	world.call("_spawn_bag_for", field, pile, int(Constants.MIN_BAG_CELLS * 80.0), 1)
	await get_tree().process_frame
	var shared := _nearest_bag(pile)
	if shared == null:
		_check("bag: a fresh bag with a teammate at the pile", false, "")
		return
	var out := Vector2(shared.global_position.x - me.global_position.x, shared.global_position.z - me.global_position.z)
	_check("bag: with a teammate nearer the pile, it still lands a step in front of the bagger", out.length() >= Constants.BAG_SPAWN_AHEAD_MIN - 0.05 and out.normalized().dot(Vector2(ahead.x, ahead.z).normalized()) > 0.7, "%.2f m ahead of the bagger, Target %.2f m from the pile" % [out.length(), Vector2(_other().global_position.x - pile.x, _other().global_position.z - pile.z).length()])
	shared.queue_free()


func _barrow() -> void:
	var barrow := _prop_of("wheelbarrow")
	if barrow == null:
		return
	var lot := get_tree().get_first_node_in_group("job_lot") as Node3D
	_put(barrow, lot.to_global(Vector3(-9.0, 0.3, 4.0)))
	barrow.global_rotation = Vector3(0.0, 0.4, 1.45)
	await _seconds(2.5)
	var tilt := barrow.global_basis.y.angle_to(Vector3.UP)
	_check("barrow: a wheelbarrow knocked on its side rights itself (NB-14)", tilt < 0.15, "tilt %.2f rad" % tilt)


func _stars() -> void:
	var body := _me().get_node_or_null("Visual/CartoonBody")
	body.call("dizzy", 1.0)
	var stars := body.get_node_or_null("DizzyStars") as Node3D
	_check("stars: your own are a small ring over your eye", stars != null and absf(stars.scale.x - Constants.STARS_OWN_SCALE) < 0.01, str(stars.scale if stars != null else null))


func _board() -> void:
	var me := _me()
	var other := _other()
	Net.move_player_to_zone(1, Net.Zone.STORE)
	Net.move_player_to_zone(other.name.to_int(), Net.Zone.STORE)
	await _seconds(1.5)
	var post: Node3D = null
	for node: Node in get_tree().get_nodes_in_group("prompt_sources"):
		if str(node.get("action_name")) == "depart":
			post = node as Node3D
	if post == null:
		_check("board: Chefty's pad", false, "")
		return
	var stand := Vector3(post.global_position.x, me.global_position.y, post.global_position.z)
	_place(me, stand, 0.0, 0.0)
	# A teammate right beside you, the way you both wait at the tailgate.
	_teleport(other, stand + Vector3(0.85, 0.0, 0.0), 0.0)
	await _seconds(0.8)
	var choice: Dictionary = me.call("e_choice")
	var text := str((choice["hint"] as Dictionary).get("text", ""))
	_check("board: at Chefty's pad with a teammate beside you, E is Board", StringName(choice["do"]) == &"source" and text == _Strings.UI["prompt_board"], "%s '%s'" % [choice["do"], text])
	_look_at(me, stand, other.global_position + Vector3(0.0, 1.2, 0.0))
	await _seconds(0.2)
	choice = me.call("e_choice")
	text = str((choice["hint"] as Dictionary).get("text", ""))
	_check("board: looking right at them up close, E is Grab, with no name on it", StringName(choice["do"]) == &"grab_player" and text == _Strings.UI["prompt_grab"], "%s '%s'" % [choice["do"], text])


func _sleep() -> void:
	var other := _other()
	var clock := get_tree().get_first_node_in_group("day_clock")
	var peer := other.name.to_int()
	var cot: Node3D = null
	for node: Node in get_tree().get_nodes_in_group("cots"):
		if int(node.get("index")) == 1:
			cot = node as Node3D
	if cot == null or not bool(clock.call("can_sleep_now")):
		_check("sleep: a cot, after dark", false, "cot %s, can sleep %s" % [cot, clock.call("can_sleep_now")])
		return
	_teleport(other, cot.global_position + cot.global_basis.x * 1.6 + Vector3(0.0, 0.05, 0.0), 0.0)
	await _seconds(0.8)
	clock.call("_handle_sleep", peer, true, 1)
	await _seconds(Constants.SLEEP_CLIMB_SECONDS + 1.0)
	var body := other.get_node_or_null("Visual/CartoonBody")
	var spot: Transform3D = other.call("sleep_spot", cot)
	var lying := float(body.get("lie"))
	var on_cot := other.global_position.distance_to(spot.origin) < 0.15
	var tag_gone := _tag_hidden(other)
	var face_up := (body as Node3D).rotation.x > 1.3
	_check("sleep: the host draws the Target lying on its cot, tag hidden (crew-06)", lying > 0.95 and on_cot and tag_gone and face_up, "lie %.2f, %.2f m off the spot, tag gone %s, tipped %.2f" % [lying, other.global_position.distance_to(spot.origin), tag_gone, (body as Node3D).rotation.x])
	# The client checks its own view and turns its head on the pillow: the body
	# stays on the cot's line for the host (it used to swing off the cot).
	var spot_yaw := spot.basis.get_euler().y
	var worst := 0.0
	var sampled := 0.0
	while sampled < 2.0:
		await get_tree().physics_frame
		sampled += get_physics_process_delta_time()
		worst = maxf(worst, absf(angle_difference(spot_yaw, other.rotation.y)))
	var still_on := other.global_position.distance_to(spot.origin) < 0.15
	_check("sleep: the Target turning its head keeps its body on the cot's line", worst < 0.05 and still_on, "body off the cot's line by up to %.3f rad, on the spot %s" % [worst, still_on])
	clock.call("_handle_sleep", peer, false)
	await _seconds(Constants.SLEEP_CLIMB_SECONDS * 0.8 + 1.0)
	var off := other.global_position
	var foot := spot.origin
	var stepped := Vector2(off.x - foot.x, off.z - foot.z).length() > Constants.SLEEP_GET_UP_SIDE * 0.7 and absf(off.y - cot.global_position.y) < 0.2
	_check("sleep: woken, the Target steps down off the cot's foot and stands", stepped and float(body.get("lie")) < 0.05, "at %s (foot %s), lie %.2f" % [off, foot, float(body.get("lie"))])


## A real E between two cots, nearer the one that isn't first to answer: the
## first cot passes (it isn't the nearest), the press falls through to the
## nearest, and you lie down on it.
func _cot_press() -> void:
	var me := _me()
	var clock := get_tree().get_first_node_in_group("day_clock")
	var first: Node3D = null
	for node: Node in get_tree().get_nodes_in_group("prompt_sources"):
		if node.is_in_group("cots"):
			first = node as Node3D
			break
	var near: Node3D = null
	for node: Node in get_tree().get_nodes_in_group("cots"):
		var cot := node as Node3D
		if cot != first and first != null and cot.global_position.distance_to(first.global_position) < 2.9 and (near == null or cot.global_position.distance_to(first.global_position) < near.global_position.distance_to(first.global_position)):
			near = cot
	if first == null or near == null:
		_check("cot press: two cots side by side", false, "first %s, near %s" % [first, near])
		return
	_teleport(_other(), near.global_position + Vector3(6.0, 0.0, 6.0), 0.0)
	var stand := near.global_position.lerp(first.global_position, 0.47)
	stand.y = me.global_position.y
	_place(me, stand, _yaw_toward(stand, near.global_position), 0.0)
	await _seconds(0.6)
	var choice: Dictionary = me.call("e_choice")
	await _press_e()
	await _seconds(0.4)
	var lying := bool(clock.call("is_sleeping", 1))
	var on := int(clock.call("cot_of", 1)) == int(near.get("index"))
	_check("cot press: E between two cots lies you down on the nearer one, even when the other answers first", lying and on, "E chose %s (%s), asleep %s, cot %d (nearest %d)" % [choice["do"], choice["target"], lying, int(clock.call("cot_of", 1)), int(near.get("index"))])
	clock.call("_handle_sleep", 1, false)
	await _seconds(Constants.SLEEP_CLIMB_SECONDS + 0.6)


## A real E at Chefty's pad with the Target right beside you: Chefty heads out,
## and nobody gets picked up (the W8 crew session's Board/Grab mix-up).
func _board_press() -> void:
	var me := _me()
	var other := _other()
	var post: Node3D = null
	for node: Node in get_tree().get_nodes_in_group("prompt_sources"):
		if str(node.get("action_name")) == "depart":
			post = node as Node3D
	var chefty := get_tree().get_first_node_in_group("world").get_node_or_null("Rides/Chefty")
	if post == null or chefty == null:
		_check("board press: Chefty and its pad", false, "")
		return
	var stand := Vector3(post.global_position.x, me.global_position.y, post.global_position.z)
	_place(me, stand, 0.0, 0.0)
	_teleport(other, stand + Vector3(0.85, 0.0, 0.0), 0.0)
	await _seconds(0.8)
	await _press_e()
	var waited := 0.0
	while waited < 1.5 and not bool(chefty.call("is_riding")):
		await _seconds(0.1)
		waited += 0.1
	var riding := bool(chefty.call("is_riding"))
	var grabbed := int(me.get("carrying")) != 0 or int(other.get("carried_by")) != 0
	_check("board press: E at the pad with a teammate beside you boards Chefty, nobody grabbed", riding and not grabbed, "riding %s, grabbed %s" % [riding, grabbed])


## E, pressed and let go through the input pipeline like a player's key.
func _press_e() -> void:
	var down := InputEventAction.new()
	down.action = &"interact"
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var up := InputEventAction.new()
	up.action = &"interact"
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().physics_frame


func _finish(ok: bool) -> void:
	result["ok"] = ok
	result["steps"] = _steps
	print("[HandsTest] all ok: %s" % ok)
	_rpc_finish.rpc()
	result["done"] = true


func _check(step: String, passed: bool, detail: String) -> void:
	_ok = _ok and passed
	_steps[step] = passed
	print("[HandsTest] %s %s (%s)" % ["ok  " if passed else "FAIL", step, detail])


# ---- client


func _run_client() -> void:
	await _seconds(1.0)
	_rpc_ready.rpc_id(1)
	var me := _me()
	var clock: Node = null
	var ok := false
	var detail := "never lay down"
	var waited := 0.0
	while waited < 100.0 and not bool(result.get("done", false)):
		await _seconds(0.1)
		waited += 0.1
		clock = get_tree().get_first_node_in_group("day_clock")
		if clock == null or not bool(clock.call("is_sleeping", Net.local_peer_id())):
			continue
		await _seconds(Constants.SLEEP_CLIMB_SECONDS + 0.6)
		var head := me.get_node_or_null("Visual/Head") as Node3D
		var cot_y := me.global_position.y
		var eye_low := head != null and head.global_position.y < cot_y + 0.6
		var looks_up := head != null and (-head.global_basis.z).y > 0.8
		ok = eye_low and looks_up
		detail = "eye %.2f m over the canvas, look %s" % [head.global_position.y - cot_y if head != null else -1.0, -head.global_basis.z if head != null else Vector3.ZERO]
		# The mouse turns the head on the pillow, not the body on the cot.
		if head != null:
			var cot: Node3D = me.call("_my_cot", clock)
			var spot_yaw := (me.call("sleep_spot", cot) as Transform3D).basis.get_euler().y if cot != null else float(me.get("body_yaw"))
			var before := -head.global_basis.z
			var turning := 0.0
			while turning < 0.8:
				me.set("_look", Vector2(-40.0, 0.0))
				await get_tree().physics_frame
				turning += get_physics_process_delta_time()
			await _seconds(0.2)
			var after := -head.global_basis.z
			var body_off := absf(angle_difference(spot_yaw, float(me.get("body_yaw"))))
			var turned := before.angle_to(after)
			var still_up := after.y > 0.5
			ok = ok and body_off < 0.01 and turned > 0.4 and still_up
			detail += "; turned the head %.2f rad (look %s), body off the cot's line %.3f" % [turned, after, body_off]
		break
	print("[HandsTest] client: %s (%s)" % [ok, detail])
	result["ok"] = ok
	_rpc_report.rpc_id(1, {"ok": ok, "detail": detail})
	var left := 30.0
	while left > 0.0 and not bool(result.get("done", false)):
		await _seconds(0.25)
		left -= 0.25
	result["done"] = true


# ---- helpers


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


func _place(me: Node3D, at: Vector3, yaw: float, pitch: float) -> void:
	me.call("apply_network_teleport", Transform3D(Basis(Vector3.UP, yaw), at))
	me.set("body_yaw", yaw)
	me.set("head_pitch", pitch)


## Stand at a spot and look straight at a point (from about where the eye is).
func _look_at(me: Node3D, at: Vector3, point: Vector3) -> void:
	var eye := at + Vector3(0.0, 1.6, 0.0)
	var flat := Vector2(point.x - eye.x, point.z - eye.z).length()
	_place(me, at, _yaw_toward(at, point), atan2(point.y - eye.y, flat))


## Whether the overhead tags hide this player's name tag (ui/overheads.gd).
func _tag_hidden(player: Node) -> bool:
	for node: Node in get_tree().root.find_children("*", "Node", true, false):
		var script := node.get_script() as Script
		if script == null or script.resource_path != "res://ui/overheads.gd":
			continue
		for entry: Dictionary in node.call("_tags"):
			if entry["owner"] == player:
				return bool(entry["hide"])
	return false


func _teleport(player: Node3D, at: Vector3, yaw: float) -> void:
	if player != null:
		player.call("send_teleport", Transform3D(Basis(Vector3.UP, yaw), at))


func _put(prop: Node3D, at: Vector3) -> void:
	var body := prop as RigidBody3D
	prop.global_position = at
	prop.global_rotation = Vector3.ZERO
	if body != null:
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO


func _yaw_toward(from: Vector3, to: Vector3) -> float:
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	return atan2(-flat.x, -flat.z)


func _prop_of(kind: String) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) == kind and bool(node.call("is_loose")):
			return node as Node3D
	return null


func _nearest_bag(near: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance := 4.0
	for node: Node in get_tree().get_nodes_in_group("props"):
		var prop := node as Node3D
		if prop == null or str(prop.get("kind")) != "leaf_bag" or prop.is_queued_for_deletion():
			continue
		var distance := prop.global_position.distance_to(near)
		if distance < best_distance:
			best_distance = distance
			best = prop
	return best


## Strokes from 3 m inside the back fence toward it, across its middle: the
## density they moved.
func _push_at_fence(field: Node3D, lot: Node3D) -> int:
	var moved := 0
	for row: int in 6:
		for lane: int in 5:
			var origin := lot.to_global(Vector3(-4.0 + float(lane) * 2.0, 0.2, -16.0 - float(row) * 0.5))
			var toward := lot.to_global(Vector3(-4.0 + float(lane) * 2.0, 0.2, -25.0)) - origin
			moved += int(field.call("_stroke_cells", origin, toward, 1.4, Constants.RAKE_STRENGTH, Constants.RAKE_STROKE_CELLS))
	return moved


## Leaves in the strip behind the back fence (lot z under -19.4), across the
## stretch _push_at_fence rakes.
func _density_past_fence(field: Node3D, lot: Node3D) -> int:
	var total := 0
	var width := int(field.get("grid_width"))
	var depth := int(field.get("grid_depth"))
	for z: int in depth:
		for x: int in width:
			var center: Vector2 = field.call("_cell_center", x, z)
			var world := field.to_global(Vector3(center.x, 0.0, center.y))
			var local := lot.to_local(world)
			if local.z < -19.45 and absf(local.x) < 7.0:
				total += int(field.call("density_at_cell", x, z))
	return total


func _density_copy(field: Node) -> PackedByteArray:
	return (field.get("_density") as PackedByteArray).duplicate()


func _density_restore(field: Node, bytes: PackedByteArray) -> void:
	field.set("_density", bytes.duplicate())


func _seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
