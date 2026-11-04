extends Node

## --lens-test (P1 lens, docs/GAME.md "Nobody's face at the lens"; port 7841, the
## host plus a Target client, both with --lens-test). The near-lens net in the
## running game, over the network:
##   solid       the homeowner has a body: a capsule and a head ball on the
##               pad-wall layer, and walking straight into her never puts your
##               camera inside her head or chest.
##   keep        she then stands off: at least HOMEOWNER_KEEP_METERS * HOMEOWNER_KEEP_TRIGGER from
##               you, or as far as her patch of yard lets her.
##   view        answering a talk, she walks (no teleport) to the middle of the
##               talker's view, about HOMEOWNER_FACE_METERS away.
##   price       the cash's price floats over her head, small, not over her chest.
##   dolly       a camera dollied through her head at 6 m/s: she's gone before the
##               lens gets there (no frame inside LENS_FADE_GONE_METERS shows her),
##               fades in steps no faster than the crossing allows, and comes
##               back once it's past.
##   cut         a camera cut into her head lands faded at once; cut away, solid.
##   remote      (each peer) the other player walks into your face: their body
##               fades out (shown inside the gone distance no longer than a fade
##               takes), and back in no faster than LENS_FADE_IN_SECONDS when they
##               step away; your own body never fades.
## Each step prints a [LensTest] line. The client reports its half by RPC.

const _Body = preload("res://player/cartoon_body.gd")
const START_WAIT_SECONDS: float = 45.0
const PEER_WAIT_SECONDS: float = 25.0
const HOLD_SECONDS: float = 1.5
const DOLLY_SPEED: float = 6.0
## How far in front of the other's eyes a walker puts its feet (m): heads overlap.
const WALK_IN_METERS: float = 0.2
const STEPS_HOST: Array[String] = ["solid", "keep", "view", "price", "dolly", "cut", "remote", "own", "client"]

static var result: Dictionary = {}

var _started: bool = false
var _steps: Dictionary = {}
## The other player's body being watched, and each frame's {dt, clear, fade, cam}.
var _watch: Node3D
var _samples: Array[Dictionary] = []
var _watching: bool = false
var _own_max: float = 0.0
## RPC flags.
var _walk_asked: bool = false
var _peer_walked: bool = false
var _host_walked: bool = false
var _client_done: bool = false
var _client_ok: bool = false
var _client_detail: String = ""


func _ready() -> void:
	result = {"done": false, "ok": false, "steps": {}}
	# After every body, so a frame's fade is read after it was worked out.
	process_priority = 2000


func _process(delta: float) -> void:
	if not _started and _ready_to_start():
		_started = true
		if Net.is_host():
			_run_host()
		else:
			_run_client()
	if _watching:
		_sample(delta)
	var own := _body_of(_me())
	if own != null:
		_own_max = maxf(_own_max, float(own.get("lens_fade")))


func _ready_to_start() -> bool:
	if get_tree().get_first_node_in_group("world") == null or _me() == null:
		return false
	if get_tree().get_first_node_in_group("job_lot") == null:
		return false
	return _other() != null and _body_of(_other()) != null


# ---------------------------------------------------------------- host

func _run_host() -> void:
	_note("started: host %s, client %s" % [Net.local_peer_id(), _other().name])
	await _ticks(30)
	await _homeowner_checks()
	# Remote: the client walks into the host's face.
	var client_id := int(str(_other().name))
	_start_watch(_body_of(_other()))
	_rpc_walk_in.rpc_id(client_id)
	if not await _until(func() -> bool: return _peer_walked, PEER_WAIT_SECONDS):
		_step("remote", false, "the client never walked in")
	else:
		await _wait(Constants.LENS_FADE_IN_SECONDS + 0.6)
		var verdict := _judge_watch("client")
		_step("remote", bool(verdict[0]), str(verdict[1]))
	_watching = false
	# Now the host walks into the client's face.
	await _walk_into(_other())
	_rpc_host_walked.rpc_id(client_id)
	if not await _until(func() -> bool: return _client_done, PEER_WAIT_SECONDS):
		_step("client", false, "no report from the client")
	else:
		_step("client", _client_ok, _client_detail)
	_step("own", _own_max <= 0.0, "own body's lens fade peaked at %.2f" % _own_max)
	_finish()


func _homeowner_checks() -> void:
	var ho := get_tree().get_first_node_in_group("homeowner") as Node3D
	if ho == null:
		for step: String in ["solid", "keep", "view", "price", "dolly", "cut"]:
			_step(step, false, "no homeowner on the yard")
		return
	var body := ho.get_node_or_null("CartoonBody") as Node3D
	var me := _me()
	# ---- solid
	var solid := ho.get_node_or_null("Solid") as CollisionObject3D
	var solid_ok := solid is AnimatableBody3D and solid.collision_layer == Constants.PAD_WALL_LAYER
	var query := PhysicsPointQueryParameters3D.new()
	query.position = ho.global_position + Vector3(0.0, 1.0, 0.0)
	query.collision_mask = Constants.PAD_WALL_LAYER
	var hits := ho.get_world_3d().direct_space_state.intersect_point(query, 4)
	var hit_her := false
	for hit: Dictionary in hits:
		hit_her = hit_her or hit["collider"] == solid
	var front := -ho.global_basis.z
	front.y = 0.0
	front = front.normalized() if front.length() > 0.01 else Vector3.FORWARD
	var start := ho.global_position + front * 2.6
	_move_me(Vector3(start.x, me.global_position.y + 0.05, start.z), -front)
	await _ticks(10)
	var min_clear := INF
	var closest := INF
	var walked := 0.0
	Input.action_press("move_forward")
	while walked < 2.5:
		await get_tree().process_frame
		walked += get_process_delta_time()
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			min_clear = minf(min_clear, float(body.call("lens_clearance", cam.global_position)))
		closest = minf(closest, _flat(ho.global_position, me.global_position))
	Input.action_release("move_forward")
	_step("solid", solid_ok and hit_her and min_clear > 0.0 and closest < 2.0,
		"solid %s on layer %d, hit %s; walking in got to %.2f m, the lens never closer than %.2f m to her" % [solid_ok, solid.collision_layer if solid != null else -1, hit_her, closest, min_clear])
	# ---- keep
	await _wait(2.0)
	var away := _flat(ho.global_position, me.global_position)
	var off_home := float(Vector2(ho.position.x - (ho.get("_home") as Vector3).x, ho.position.z - (ho.get("_home") as Vector3).z).length())
	_step("keep", away >= Constants.HOMEOWNER_KEEP_METERS * Constants.HOMEOWNER_KEEP_TRIGGER - 0.1 or off_home >= Constants.HOMEOWNER_STAGE_RADIUS - 0.1,
		"stood off to %.2f m (%.2f m from where she waits)" % [away, off_home])
	# ---- view: off out of her way, let her go home, then come back to talk.
	_move_me(ho.global_position + front * 8.0 + Vector3(0.0, 0.05, 0.0), -front)
	await _until(func() -> bool: return float(ho.call("walk_speed")) <= 0.0 and Vector2(ho.position.x - (ho.get("_home") as Vector3).x, ho.position.z - (ho.get("_home") as Vector3).z).length() < 0.1, 8.0)
	await _wait(0.5)
	var home := ho.global_position
	var stand := home + front * 2.0
	var toward := -front
	var looks := Vector3.ZERO
	for turn: float in [1.2, -1.2, 0.9, -0.9]:
		var look := toward.rotated(Vector3.UP, turn)
		var spot := stand + look * Constants.HOMEOWNER_FACE_METERS
		var ray := PhysicsRayQueryParameters3D.create(home + Vector3(0.0, 1.0, 0.0), spot + Vector3(0.0, 1.0, 0.0) + (spot - home).normalized() * 0.5, 1 | Constants.VEHICLE_LAYER)
		if ho.get_world_3d().direct_space_state.intersect_ray(ray).is_empty() and Vector2(spot.x - home.x, spot.z - home.z).length() < Constants.HOMEOWNER_STAGE_RADIUS - 0.1:
			looks = look
			break
	if looks == Vector3.ZERO:
		_step("view", false, "no clear spot in front of the talker on this yard to test with")
	else:
		_move_me(Vector3(stand.x, me.global_position.y + 0.05, stand.z), looks)
		await _ticks(5)
		var off_before := _view_angle(me, ho)
		ho.call("_rpc_react", "fine", 0, 10, "")
		var fastest := 0.0
		var last := ho.global_position
		var moved := false
		var waited := 0.0
		while waited < 4.0:
			await get_tree().physics_frame
			waited += get_physics_process_delta_time()
			var step_m := _flat(ho.global_position, last)
			fastest = maxf(fastest, step_m / maxf(get_physics_process_delta_time(), 0.001))
			moved = moved or step_m > 0.0
			last = ho.global_position
			if moved and float(ho.call("walk_speed")) <= 0.0:
				break
		var angle := _view_angle(me, ho)
		var dist := _flat(ho.global_position, me.global_position)
		_step("view", moved and angle < 25.0 and dist > 1.3 and dist < 2.3 and fastest <= Constants.HOMEOWNER_WALK_SPEED * 1.15,
			"she was %.0f deg off the talker's view; walked to %.0f deg off at %.2f m, never faster than %.2f m/s" % [off_before, angle, dist, fastest])
	# ---- price
	ho.call("_offer", 10)
	await _ticks(3)
	var price := ho.get_node_or_null("Price") as Label3D
	var head_top := (body.call("pose_part", "face") as Node3D).global_position.y + Constants.LENS_HEAD_RADIUS - 0.05
	var glyph := float(price.font_size) * price.pixel_size if price != null else INF
	_step("price", price != null and price.visible and price.get_parent() == ho and price.global_position.y >= head_top and glyph <= 0.16,
		"price %s over her head by %.2f m, %.3f m tall" % [price != null and price.visible, (price.global_position.y - head_top) if price != null else -1.0, glyph])
	# Back to waiting (this was the host's copy only).
	ho.set("_phase", 0)
	(ho.get_node("Cash") as Node3D).visible = false
	if price != null:
		price.visible = false
	# ---- dolly and cut, on a camera of the test's own.
	_move_me(ho.global_position + front * 8.0 + Vector3(0.0, 0.05, 0.0), -front)
	await _wait(0.5)
	await _until(func() -> bool: return float(ho.call("walk_speed")) <= 0.0 and Vector2(ho.position.x - (ho.get("_home") as Vector3).x, ho.position.z - (ho.get("_home") as Vector3).z).length() < 0.1, 8.0)
	await _wait(0.3)
	await _dolly(ho, body, front)


## A camera through her head at DOLLY_SPEED, then cuts in and out.
func _dolly(ho: Node3D, body: Node3D, front: Vector3) -> void:
	var before := get_viewport().get_camera_3d()
	var cam := Camera3D.new()
	cam.name = "LensTestCam"
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	get_tree().root.add_child(cam)
	var face := (body.call("pose_part", "face") as Node3D).global_position + Vector3(0.0, Constants.LENS_HEAD_CENTER_Y, 0.0)
	var from := face + front * 3.0
	var to := face - front * 3.0
	cam.global_position = from
	cam.current = true
	await _frames(3)
	var travelled := 0.0
	var shown := 0
	var inside := 0
	var worst_step := 0.0
	var last_fade := float(body.get("lens_fade"))
	var peak := 0.0
	var span := from.distance_to(to)
	var body_dt := -1.0
	while travelled < span:
		# The fade read now was worked out against where the camera is now.
		var clear := float(body.call("lens_clearance", cam.global_position))
		var fade := float(body.get("lens_fade"))
		var dt := get_process_delta_time()
		if clear < Constants.LENS_FADE_GONE_METERS:
			inside += 1
			if fade < 0.9:
				shown += 1
		# That fade moved over the last frame, at the last frame's delta.
		if body_dt > 0.0:
			# Out may go as fast as the camera crosses the band (cartoon_body.gd _lens_net).
			var rate := maxf(1.0 / Constants.LENS_FADE_OUT_SECONDS, 1.5 * DOLLY_SPEED / (Constants.LENS_FADE_START_METERS - Constants.LENS_FADE_GONE_METERS)) if fade > last_fade else 1.0 / Constants.LENS_FADE_IN_SECONDS
			worst_step = maxf(worst_step, absf(fade - last_fade) / maxf(body_dt * rate, 0.0001))
		last_fade = fade
		body_dt = dt
		peak = maxf(peak, fade)
		var step_m := minf(DOLLY_SPEED * maxf(dt, 0.001), 0.2)
		travelled += step_m
		# Along the line through where her head is now (she breathes and turns).
		face = (body.call("pose_part", "face") as Node3D).global_position + Vector3(0.0, Constants.LENS_HEAD_CENTER_Y, 0.0)
		cam.global_position = face + front * (3.0 - minf(travelled, span))
		await get_tree().process_frame
	await _wait(Constants.LENS_FADE_IN_SECONDS + 0.3)
	var after := float(body.get("lens_fade"))
	_step("dolly", inside > 0 and shown == 0 and peak >= 0.99 and worst_step <= 1.15 and after <= 0.0,
		"%d frames inside, %d of them showing her; peak fade %.2f; fastest step %.2f of the allowed; %.2f once past" % [inside, shown, peak, worst_step, after])
	# ---- cut: straight into her head, and out.
	face = (body.call("pose_part", "face") as Node3D).global_position + Vector3(0.0, Constants.LENS_HEAD_CENTER_Y, 0.0)
	cam.global_position = face
	await _frames(2)
	var cut_in := float(body.get("lens_fade"))
	cam.global_position = face + front * 6.0
	await _frames(2)
	var cut_out := float(body.get("lens_fade"))
	_step("cut", cut_in >= 0.99 and cut_out <= 0.0, "cut in: %.2f, cut out: %.2f" % [cut_in, cut_out])
	cam.current = false
	cam.queue_free()
	if before != null and is_instance_valid(before):
		before.current = true


# ---------------------------------------------------------------- client

func _run_client() -> void:
	_note("started: client %s" % Net.local_peer_id())
	if not await _until(func() -> bool: return _walk_asked, START_WAIT_SECONDS + PEER_WAIT_SECONDS):
		_client_finish(false, "the host never asked for the walk-in")
		return
	await _walk_into(_other())
	_rpc_walked.rpc_id(1)
	_start_watch(_body_of(_other()))
	if not await _until(func() -> bool: return _host_walked, PEER_WAIT_SECONDS):
		_client_finish(false, "the host never walked in")
		return
	await _wait(Constants.LENS_FADE_IN_SECONDS + 0.6)
	_watching = false
	var verdict := _judge_watch("host")
	var ok := bool(verdict[0]) and _own_max <= 0.0
	_client_finish(ok, "%s; own body peaked at %.2f" % [verdict[1], _own_max])


func _client_finish(ok: bool, detail: String) -> void:
	_note("client: %s %s" % ["ok" if ok else "FAIL", detail])
	result["ok"] = ok
	result["detail"] = detail
	result["done"] = true
	_rpc_client_report.rpc_id(1, ok, detail)


@rpc("authority", "call_remote", "reliable")
func _rpc_walk_in() -> void:
	_walk_asked = true


@rpc("authority", "call_remote", "reliable")
func _rpc_host_walked() -> void:
	_host_walked = true


@rpc("any_peer", "call_remote", "reliable")
func _rpc_walked() -> void:
	_peer_walked = true


@rpc("any_peer", "call_remote", "reliable")
func _rpc_client_report(ok: bool, detail: String) -> void:
	_client_done = true
	_client_ok = ok
	_client_detail = detail


# ---------------------------------------------------------------- both

## Walk (teleport) right into the other player's face, hold, and step back
## where we were.
func _walk_into(other: Node3D) -> void:
	var me := _me()
	var was := me.global_position
	var yaw := float(other.get("body_yaw"))
	var ahead := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var spot := other.global_position + ahead * WALK_IN_METERS
	_move_me(Vector3(spot.x, other.global_position.y + 0.05, spot.z), -ahead)
	await _wait(HOLD_SECONDS)
	# Back where we were, or well clear of them if that was close.
	var out := was - other.global_position
	out.y = 0.0
	var back := was
	if out.length() < 4.0:
		var dir := out.normalized() if out.length() > 0.1 else ahead.rotated(Vector3.UP, 1.0)
		back = other.global_position + dir * 4.5
	_move_me(back + Vector3(0.0, 0.05, 0.0), ahead)
	await _ticks(3)


func _start_watch(body: Node3D) -> void:
	_watch = body
	_samples.clear()
	_watching = true


func _sample(delta: float) -> void:
	if _watch == null or not is_instance_valid(_watch):
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var at := cam.get_global_transform_interpolated().origin if cam.is_physics_interpolated_and_enabled() else cam.global_position
	_samples.append({"dt": delta, "clear": float(_watch.call("lens_clearance", at)), "fade": float(_watch.get("lens_fade")), "cam": cam.get_instance_id(), "at": at})


## [ok, detail] for the other player's body walking into this camera and out.
func _judge_watch(who: String) -> Array:
	var inside := 0
	var shown_time := 0.0
	var peak := 0.0
	var worst := 0.0
	var last: Dictionary = {}
	for sample: Dictionary in _samples:
		var fade := float(sample["fade"])
		peak = maxf(peak, fade)
		if float(sample["clear"]) < Constants.LENS_FADE_GONE_METERS:
			inside += 1
			if fade < 0.9:
				shown_time += float(sample["dt"])
		if not last.is_empty() and int(last["cam"]) == int(sample["cam"]) and (last["at"] as Vector3).distance_to(sample["at"] as Vector3) <= Constants.LENS_CUT_METERS:
			# Coming back in is never faster than LENS_FADE_IN_SECONDS (going out may be
			# as fast as a body pops into your face).
			if fade < float(last["fade"]):
				var allowed := float(sample["dt"]) / Constants.LENS_FADE_IN_SECONDS
				worst = maxf(worst, (float(last["fade"]) - fade) / maxf(allowed, 0.0001))
		last = sample
	var after := float(_samples[-1]["fade"]) if not _samples.is_empty() else -1.0
	var ok := inside > 0 and peak >= 0.99 and shown_time <= Constants.LENS_FADE_OUT_SECONDS + 0.1 and worst <= 1.15 and after <= 0.0
	return [ok, "%s's body: %d frames inside the lens, shown %.3f s of them; peak fade %.2f; fastest step %.2f of the allowed; %.2f after leaving" % [who, inside, shown_time, peak, worst, after]]


func _view_angle(me: Node3D, ho: Node3D) -> float:
	var yaw := float(me.get("body_yaw"))
	var ahead := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var to := ho.global_position - me.global_position
	to.y = 0.0
	return rad_to_deg(ahead.angle_to(to.normalized())) if to.length() > 0.01 else 0.0


func _move_me(at: Vector3, facing: Vector3) -> void:
	var me := _me()
	if me == null:
		return
	var yaw := atan2(-facing.x, -facing.z)
	me.call("apply_network_teleport", Transform3D(Basis(Vector3.UP, yaw), at))


func _me() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as Node3D
	return null


func _other() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name != str(Net.local_peer_id()) and str(node.name).is_valid_int() and not Net.is_watcher(int(str(node.name))):
			return node as Node3D
	return null


func _body_of(player: Node3D) -> Node3D:
	return player.get_node_or_null("Visual/CartoonBody") as Node3D if player != null else null


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _step(step_name: String, ok: bool, detail: String) -> void:
	_steps[step_name] = {"ok": ok, "detail": detail}
	(result["steps"] as Dictionary)[step_name] = ok
	_note("%s %s: %s" % [step_name, "ok" if ok else "FAIL", detail])


func _finish() -> void:
	var ok := true
	for step: String in STEPS_HOST:
		ok = ok and _steps.has(step) and bool((_steps[step] as Dictionary)["ok"])
	result["ok"] = ok
	result["detail"] = _steps.duplicate(true)
	result["done"] = true
	_note("done: %s" % ("ok" if ok else "FAIL"))


func _note(text: String) -> void:
	print("[LensTest] ", text)


func _ticks(count: int) -> void:
	for _tick: int in count:
		await get_tree().physics_frame


func _frames(count: int) -> void:
	for _frame: int in count:
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _until(check: Callable, limit_seconds: float) -> bool:
	var waited := 0.0
	while waited < limit_seconds:
		if bool(check.call()):
			return true
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	return bool(check.call())
