extends Node

## Authority: host. --gag-test checks the heat system and the gags built on it
## (docs/FUN.md): a running mower heats things up and, let go of, drives off on
## its own; heat cools when it's quiet; a thrown can knocks a set-up ladder down;
## a raked pile is thick enough to dive into and hides you from the NICE BOYS; a
## hot crew brings three of them and a thrown can stuns one; paint and water
## land on another player. Run with --start-zone=lot --all-tools --all-tasks and
## a joined client named Target for the paint and water part. Each step prints
## a [GagTest] line.

static var result: Dictionary = {}

const _Aim = preload("res://net/dev/water_test.gd")
const _WaterSources = preload("res://net/work/water_sources.gd")

var _started: bool = false


func _process(_delta: float) -> void:
	if _started or not Net.is_host() or _own_player() == null or get_tree().get_first_node_in_group("job_tasks") == null:
		return
	_started = true
	_run()


func _run() -> void:
	var waited := 0.0
	while Net.peer_ids().size() < 2 and waited < 6.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	await get_tree().create_timer(2.0).timeout
	var ok := true
	var heat := get_tree().get_first_node_in_group("heat")
	# 1. A running mower heats things up, then runs away when let go of.
	var mower := _prop("lawn_mower")
	var lot := get_tree().get_first_node_in_group("job_lot") as Node3D
	# Open ground along the yard's front, heading along it.
	_move_to(lot.global_position + Vector3(-15.0, 0.1, 8.0), -PI * 0.5)
	await _grab(mower)
	var pulls := 0
	while not bool(mower.get("spraying")) and pulls < 12:
		mower.call("request_start")
		pulls += 1
		await _ticks(3)
	var running := bool(mower.get("spraying"))
	await _seconds(3.0)
	var heat_after_mowing := float(heat.get("heat"))
	print("[GagTest] mower running %s for 3 s: heat %.1f" % [running, heat_after_mowing])
	ok = ok and running and heat_after_mowing > 3.0
	var dropped_at := mower.global_position
	_drop_held()
	await _seconds(1.2)
	var ran := mower.global_position.distance_to(dropped_at)
	var still_running := bool(mower.get("spraying"))
	print("[GagTest] let go of the running mower: it drove %.1f m on its own in 1.2 s, still running %s" % [ran, still_running])
	ok = ok and ran > 1.2 and still_running
	await _seconds(Constants.MOWER_RUNAWAY_SECONDS)
	var stalled := not bool(mower.get("spraying"))
	print("[GagTest] runaway mower stalled after %.0f s: %s" % [Constants.MOWER_RUNAWAY_SECONDS, stalled])
	ok = ok and stalled
	# 2. Quiet: heat cools.
	var before_cooling := float(heat.get("heat"))
	await _seconds(3.0)
	var cooled := float(heat.get("heat")) < before_cooling
	print("[GagTest] three quiet seconds: heat %.1f -> %.1f, cooled %s" % [before_cooling, float(heat.get("heat")), cooled])
	ok = ok and cooled
	# 3. A can knocks a set-up ladder down.
	var knocked: bool = await _ladder_check()
	print("[GagTest] trash thrown at a set-up ladder knocks it down: %s" % knocked)
	ok = ok and knocked
	# 5. Paint and water on the other player (before the raid takes them away).
	var target := _other_player()
	if target != null:
		var coated: bool = await _coat_check(target)
		ok = ok and coated
	else:
		print("[GagTest] no second player: skipped paint and water")
	# 6. Hot crew: three NICE BOYS, and a can stuns one.
	_drop_held()
	await _ticks(2)
	var back_in: bool = await _pile_check()
	ok = ok and back_in
	heat.call("add", 100.0, "test")
	var director := get_tree().get_first_node_in_group("run_director")
	director.call("force_event")
	await _seconds(Constants.RUN_WARNING_SECONDS + 1.5)
	var crew := get_tree().get_nodes_in_group("crew")
	print("[GagTest] at heat %.0f the raid brings %d NICE BOYS (expected %d)" % [float(heat.get("heat")), crew.size(), Constants.HEAT_MAX_CREW])
	ok = ok and crew.size() == Constants.HEAT_MAX_CREW
	var not_caught := not bool(director.call("is_captured", Net.local_peer_id()))
	print("[GagTest] still in the pile with them on the lot: not captured %s" % not_caught)
	ok = ok and not_caught
	_own_player().call("set_pile", false)
	await _ticks(3)
	var stunned: bool = await _stun_check(crew[0] as Node3D)
	print("[GagTest] trash thrown at a NICE BOY: stunned %s" % stunned)
	ok = ok and stunned
	result = {"ok": ok}
	print("[GagTest] all ok: %s" % ok)


## Set the ladder up at a gutter, then throw the trash can at it.
func _ladder_check() -> bool:
	var tasks := get_tree().get_first_node_in_group("job_tasks")
	var ladder := _prop("ladder")
	var trash := _prop("trash")
	if ladder == null or trash == null:
		return false
	for index: int in int(tasks.call("spot_count")):
		var spot: Dictionary = tasks.call("spot", index)
		if str(spot["task"]) != "clean_gutters":
			continue
		var at: Vector3 = spot["at"]
		var out: Vector3 = spot["normal"]
		var stand := Vector3(at.x, 0.1, at.z) + out * 1.6
		_move_to(stand, atan2(out.x, out.z))
		await _grab(ladder)
		ladder.call("request_place_ladder")
		await _ticks(4)
		if not bool(ladder.call("is_set_up")):
			print("[GagTest] couldn't set the ladder up at %s" % at)
			continue
		# Stand off to the side, level with the ladder's lower rungs, and throw
		# along the wall through it.
		var side := out.cross(Vector3.UP).normalized()
		var rung: Vector3 = ladder.global_position.lerp(ladder.get("ladder_top"), 0.2)
		var from := Vector3(rung.x, 0.1, rung.z) + side * 1.6
		_move_to(from, atan2(-side.x, -side.z))
		await _grab(trash)
		trash.call("request_throw", -side, 1.2)
		var waited := 0.0
		var closest := INF
		var top: Vector3 = ladder.get("ladder_top")
		while waited < 2.0 and bool(ladder.call("is_set_up")):
			await get_tree().physics_frame
			waited += get_physics_process_delta_time()
			var foot := ladder.global_position
			var along := clampf((trash.global_position - foot).dot(top - foot) / maxf((top - foot).length_squared(), 0.01), 0.0, 1.0)
			closest = minf(closest, trash.global_position.distance_to(foot.lerp(top, along)))
		print("[GagTest] the can's closest pass to the ladder: %.2f m" % closest)
		return not bool(ladder.call("is_set_up"))
	return false


## Rake a strip into a pile, dive in, and climb out again when raked.
func _pile_check() -> bool:
	var field := get_tree().get_first_node_in_group("leaf_field")
	var lot := get_tree().get_first_node_in_group("job_lot") as Node3D
	_drop_held()
	await _ticks(2)
	var rake := _prop("rake")
	# A strip of untouched leaves, so the pile is as thick as a real one.
	var strip := Vector3.INF
	for z: float in [-6.0, -10.0, 2.0, 6.0, -14.0, 10.0]:
		for x: float in [-15.0, -9.0, 3.0, 9.0]:
			var fine := true
			for step: int in 14:
				if int(field.call("sample_world", lot.global_position + Vector3(x + float(step) * 0.5, 0.2, z))) < 36:
					fine = false
			if fine:
				strip = lot.global_position + Vector3(x, 0.1, z)
				break
		if strip != Vector3.INF:
			break
	if strip == Vector3.INF:
		print("[GagTest] no untouched strip to rake")
		return false
	_move_to(strip - Vector3(1.5, 0.0, 0.0), -PI * 0.5)
	await _grab(rake)
	for index: int in 14:
		var at := strip + Vector3(float(index) * 0.5, 0.1, 0.0)
		_move_to(at - Vector3(1.5, 0.0, 0.0), -PI * 0.5)
		field.call("request_rake", at, Vector3(1.0, 0.0, 0.0), Constants.RAKE_WIDTH, Constants.RAKE_STRENGTH)
		await _ticks(1)
	await _ticks(2)
	_drop_held()
	await _ticks(2)
	var pile := Vector3.INF
	var most := 0
	for ahead: float in [5.5, 6.0, 6.5, 7.0, 7.5, 8.0, 8.5, 9.0]:
		var at := strip + Vector3(ahead, 0.0, 0.0)
		var units := int(field.call("units_within_world", at, Constants.PILE_HIDE_RADIUS))
		if units > most:
			most = units
			pile = at
	var fresh := int(field.call("units_within_world", strip + Vector3(0.0, 0.0, 6.0), Constants.PILE_HIDE_RADIUS))
	print("[GagTest] raked a pile of %d leaf units (fresh ground has %d, a pile needs %d)" % [most, fresh, Constants.PILE_HIDE_UNITS])
	if pile == Vector3.INF or not bool(field.call("is_pile_at", pile)):
		return false
	var me := _own_player()
	_move_to(Vector3(pile.x, 0.1, pile.z), 0.0)
	await _ticks(2)
	field.call("request_pile_hide")
	await _ticks(4)
	var hidden := bool(me.get("in_pile")) and bool(me.call("is_hidden"))
	if not hidden:
		print("[GagTest] (dive refused: standing at %s, pile at %s, pile there %s, in_pile %s, held %s)" % [me.global_position, pile, bool(field.call("is_pile_at", me.global_position)), bool(me.get("in_pile")), _held_kind()])
	print("[GagTest] dived into the pile: hidden %s" % hidden)
	return hidden


## Walk up to a NICE BOY and bean them with the trash can.
func _stun_check(crew: Node3D) -> bool:
	var trash := _prop("trash")
	var me := _own_player()
	# Stand off at the yard's open front; they come running, and the can meets them.
	var lot := get_tree().get_first_node_in_group("job_lot") as Node3D
	var stand := lot.global_position + Vector3(0.0, 0.1, 12.0)
	_move_to(stand, 0.0)
	await _grab(trash)
	# Point blank, as they lunge: the can and the NICE BOY meet on the next tick.
	var toward := Vector3(0.0, 0.0, -1.0)
	crew.global_position = stand + toward * 1.6
	crew.set("_stun_left", 0.0)
	trash.global_position = me.global_position + Vector3(0.0, 0.9, 0.0) + toward * 0.6
	var held := int(trash.get("held_by")) == Net.local_peer_id()
	trash.call("request_throw", toward, 1.3)
	var waited := 0.0
	var closest := INF
	while waited < 1.5:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
		closest = minf(closest, trash.global_position.distance_to(crew.global_position + Vector3(0.0, 0.95, 0.0)))
		if float(crew.get("_stun_left")) > 0.0:
			return true
	print("[GagTest] (held the can %s; its closest pass to the NICE BOY was %.2f m)" % [held, closest])
	return false


## Paint the other player, then hose them off.
func _coat_check(target: Node3D) -> bool:
	var tasks := get_tree().get_first_node_in_group("job_tasks")
	var me := _own_player()
	var lot := get_tree().get_first_node_in_group("job_lot") as Node3D
	# Near the street, so the hose reaches from Chefty's tank.
	var stand := lot.global_position + Vector3(6.0, 0.1, 14.0)
	_move_to(stand, -PI * 0.5)
	target.call("send_teleport", Transform3D(Basis.IDENTITY, stand + Vector3(1.0, 0.0, 0.0)))
	await _grab(_prop("paint_roller"))
	var painted := false
	for _try: int in 20:
		tasks.call("request_work", "paint_fence", me.global_position + Vector3(0.9, 0.5, 0.0), Vector3(1.0, 0.0, 0.0))
		await _ticks(3)
		if int(target.get("coat")) == 1:
			painted = true
			break
	print("[GagTest] painted the other player: %s" % painted)
	_drop_held()
	# One coat at a time: the next can't land for a moment.
	await _seconds(1.6)
	var hose := _prop("hose")
	var chefty: Node3D = _WaterSources.find(get_tree(), "chefty")
	_move_to(Vector3(chefty.global_position.x, 0.1, chefty.global_position.z) + Vector3(0.0, 0.0, -1.2), 0.0)
	await _grab(hose)
	hose.call("request_hookup")
	await _ticks(3)
	var hooked := str(hose.get("hose_source")) == "chefty"
	var from := target.global_position + Vector3(0.0, 0.1, -4.0)
	_move_to(from, 0.0)
	await _ticks(2)
	var soaked := false
	for _try: int in 40:
		if _try % 8 == 0:
			target.call("send_teleport", Transform3D(Basis.IDENTITY, stand + Vector3(1.0, 0.0, 0.0)))
			await _ticks(3)
		var eye := me.global_position + Vector3(0.0, 1.6, 0.0)
		var aim: Vector3 = _Aim.aim_at(eye, target.global_position + Vector3(0.0, 0.9, 0.0), float(Constants.WATER_SPEED["chefty"]))
		tasks.call("request_work", "wash_windows", eye, aim)
		await _ticks(3)
		if int(target.get("coat")) == 2:
			soaked = true
			break
	print("[GagTest] hosed the other player (hooked to Chefty %s): soaked %s" % [hooked, soaked])
	return painted and soaked


func _held_kind() -> String:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if int(node.get("held_by")) == Net.local_peer_id():
			return str(node.get("kind"))
	return ""


func _grab(item: Node3D) -> void:
	var me := _own_player()
	await get_tree().physics_frame
	item.global_position = me.global_position + Vector3(0.0, 0.4, 0.0) + (-me.global_basis.z) * 0.8
	item.set("linear_velocity", Vector3.ZERO)
	await _ticks(2)
	item.call("request_grab")
	await _ticks(3)


func _drop_held() -> void:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if int(node.get("held_by")) == Net.local_peer_id():
			node.call("request_drop")


func _move_to(at: Vector3, yaw: float) -> void:
	var me := _own_player()
	me.call("apply_network_teleport", Transform3D(Basis(Vector3.UP, yaw), at))
	me.set("body_yaw", yaw)


func _seconds(count: float) -> void:
	await get_tree().create_timer(count).timeout


func _ticks(count: int) -> void:
	for _tick: int in count:
		await get_tree().physics_frame


func _own_player() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as Node3D
	return null


func _other_player() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name != str(Net.local_peer_id()):
			return node as Node3D
	return null


func _prop(kind: String) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) == kind and not node.is_queued_for_deletion():
			return node as Node3D
	return null
