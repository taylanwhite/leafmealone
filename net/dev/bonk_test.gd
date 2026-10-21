extends Node

## Authority: host. --bonk-test throws a light, a medium, and a heavy item at
## another player and checks what happened to them on their own peer, as seen
## through replication: a light hit barely moves them, a medium one shoves them,
## and a heavy one knocks them flat (anim_state KNOCKED). Run the target as a
## client with --measure and no --bot, so it stands still. Each throw prints a
## [BonkTest] line, and the result lands in the --measure report.

## What to throw, lightest first, and what each should do.
const THROWS: Array = [["rake", "light"], ["gnome", "medium"], ["trash", "heavy"]]

static var result: Dictionary = {}

var _started: bool = false


func _process(_delta: float) -> void:
	if _started or not Net.is_host() or _target() == null or _own_player() == null or _field() == null:
		return
	_started = true
	_run()


func _run() -> void:
	await get_tree().create_timer(2.0).timeout
	var throws: Array = []
	result["throws"] = throws
	var all_ok := true
	for entry: Array in THROWS:
		var kind: String = entry[0]
		var expected: String = entry[1]
		var outcome: Dictionary = await _throw_at_target(kind)
		outcome["expected"] = expected
		var ok := bool(outcome.get("thrown", false)) and str(outcome.get("tier", "")) == expected
		if expected == "heavy":
			ok = ok and bool(outcome.get("knocked", false))
		elif expected == "medium":
			ok = ok and float(outcome.get("moved", 0.0)) > 0.4 and not bool(outcome.get("knocked", false))
		else:
			ok = ok and not bool(outcome.get("knocked", false))
		outcome["ok"] = ok
		all_ok = all_ok and ok
		throws.append(outcome)
		print("[BonkTest] %s (%.1f kg, %s): target moved %.2f m, knocked %s, ok=%s" % [kind, float(outcome.get("kg", 0.0)), outcome.get("tier", "?"), float(outcome.get("moved", 0.0)), outcome.get("knocked", false), ok])
		# Let them get up before the next one.
		await get_tree().create_timer(3.0).timeout
	# Leading a walker is timing: a slow machine gets a couple more tries.
	var walker_hit := false
	for _attempt: int in 3:
		walker_hit = await _throw_at_pedestrian()
		if walker_hit:
			break
		await get_tree().create_timer(1.0).timeout
	result["pedestrian_hit"] = walker_hit
	print("[BonkTest] rake at a pedestrian on the sidewalk: knocked off their route %s" % walker_hit)
	all_ok = all_ok and walker_hit
	result["ok"] = all_ok
	print("[BonkTest] all ok: %s" % all_ok)


func _throw_at_target(kind: String) -> Dictionary:
	var outcome := {"kind": kind}
	var item := _prop(kind)
	var target := _target()
	var me := _own_player()
	if item == null or target == null or me == null:
		outcome["error"] = "missing item or players"
		return outcome
	outcome["kg"] = float(item.call("weight_kg"))
	outcome["tier"] = str(item.call("weight_tier"))
	# Stand 2.6 m from the target, facing them, with the item at our feet.
	var spot := target.global_position + Vector3(0.0, 0.0, 2.6)
	# Moves happen on a physics tick, like everything that moves in the game.
	await get_tree().physics_frame
	me.call("apply_network_teleport", Transform3D(Basis.IDENTITY, spot))
	me.set("body_yaw", 0.0)
	me.rotation.y = 0.0
	item.global_position = spot + Vector3(0.0, 0.4, -0.8)
	item.set("linear_velocity", Vector3.ZERO)
	await _ticks(3)
	item.call("request_grab")
	await _ticks(3)
	if int(item.get("held_by")) != Net.local_peer_id():
		outcome["error"] = "could not pick it up"
		return outcome
	var start := target.global_position
	item.call("request_throw", Vector3(0.0, 0.0, -1.0))
	outcome["thrown"] = true
	var knocked := false
	var moved := 0.0
	var waited := 0.0
	while waited < 2.5:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
		knocked = knocked or int(target.get("anim_state")) == 5
		moved = maxf(moved, Vector2(target.global_position.x - start.x, target.global_position.z - start.z).length())
	outcome["knocked"] = knocked
	outcome["moved"] = moved
	return outcome


## Throws the rake over the yard's wall at someone walking past on the sidewalk.
func _throw_at_pedestrian() -> bool:
	var item := _prop("rake")
	var me := _own_player()
	var walker: Node3D = null
	for node: Node in get_tree().get_nodes_in_group("bonkable"):
		var candidate := node as Node3D
		if candidate != null and candidate.global_position.distance_to(me.global_position) < 200.0 and not bool(candidate.get("_free")):
			walker = candidate
			break
	if item == null or walker == null:
		return false
	await get_tree().physics_frame
	# Lead them a little: they keep walking while it flies.
	var ahead := walker.global_position + (-walker.global_basis.z) * 0.25
	var spot := ahead - Vector3(0.0, 0.0, 2.2) if walker.global_position.z > me.global_position.z else ahead + Vector3(0.0, 0.0, 2.2)
	spot.y = walker.global_position.y
	me.call("apply_network_teleport", Transform3D(Basis.IDENTITY, spot))
	var toward := Vector3(0.0, 0.0, signf(ahead.z - spot.z))
	me.set("body_yaw", atan2(-toward.x, -toward.z))
	me.rotation.y = float(me.get("body_yaw"))
	item.global_position = spot + Vector3(0.0, 0.4, 0.0) + toward * 0.6
	item.set("linear_velocity", Vector3.ZERO)
	await _ticks(3)
	item.call("request_grab")
	await _ticks(3)
	if int(item.get("held_by")) != Net.local_peer_id():
		return false
	item.call("request_throw", toward)
	var waited := 0.0
	while waited < 1.5:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
		if bool(walker.get("_free")):
			return true
	return false


func _ticks(count: int) -> void:
	for _tick: int in count:
		await get_tree().physics_frame


func _own_player() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as Node3D
	return null


func _target() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name != str(Net.local_peer_id()) and Net.player_zone(node.name.to_int()) == Net.player_zone(Net.local_peer_id()):
			return node as Node3D
	return null


func _prop(kind: String) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) == kind and not node.is_queued_for_deletion():
			return node as Node3D
	return null


func _field() -> Node:
	return get_tree().get_first_node_in_group("leaf_field")
