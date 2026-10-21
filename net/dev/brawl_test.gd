extends Node

## Authority: host. --brawl-test, with a joined client named Target standing
## still: a punch shoves them, a whiff hits nobody, a whack with the trash can
## knocks them flat, grabbing them carries them along, setting them down puts
## them in front of you, and a throw sends them flying. Each step prints a
## [BrawlTest] line.

static var result: Dictionary = {}

var _started: bool = false


func _process(_delta: float) -> void:
	if _started or not Net.is_host() or _own_player() == null or get_tree().get_first_node_in_group("job_tasks") == null:
		return
	_started = true
	_run()


func _run() -> void:
	var waited := 0.0
	while _other_player() == null and waited < 10.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	await get_tree().create_timer(2.0).timeout
	var target := _other_player()
	if target == null:
		print("[BrawlTest] no second player joined")
		result = {"ok": false}
		return
	var brawl := get_tree().get_first_node_in_group("brawl")
	var me := _own_player()
	var lot := get_tree().get_first_node_in_group("job_lot") as Node3D
	var ok := true
	# Face +X with them 1.2 m ahead.
	var stand := lot.global_position + Vector3(2.0, 0.1, 10.0)
	await _place(stand, stand + Vector3(1.2, 0.0, 0.0), target)
	var from := target.global_position
	brawl.call("request_punch", "medium")
	var moved: float = await _moved(target, from, 1.2)
	print("[BrawlTest] medium punch: they were shoved %.2f m" % moved)
	ok = ok and moved > 0.4
	# Nobody in front: a whiff, nothing happens to them.
	await _place(stand, stand + Vector3(-3.0, 0.0, 0.0), target)
	from = target.global_position
	brawl.call("request_punch", "heavy")
	moved = await _moved(target, from, 0.8)
	print("[BrawlTest] heavy punch at nobody: they moved %.2f m" % moved)
	ok = ok and moved < 0.2
	# A whack with the trash can: heavy.
	await _place(stand, stand + Vector3(1.2, 0.0, 0.0), target)
	var trash := _prop("trash")
	await _grab(trash)
	from = target.global_position
	brawl.call("request_whack")
	moved = await _moved(target, from, 1.5)
	print("[BrawlTest] whacked with the trash can (%s): they went %.2f m" % [str(trash.call("weight_tier")), moved])
	ok = ok and moved > 0.8
	_drop_held()
	await _seconds(2.8)
	# Grab and carry.
	await _place(stand, stand + Vector3(1.0, 0.0, 0.0), target)
	brawl.call("request_grab_player", target.name.to_int())
	await _ticks(12)
	var carrying := int(me.get("carrying")) == target.name.to_int() and int(target.get("carried_by")) == Net.local_peer_id()
	print("[BrawlTest] grabbed them: carrying %s" % carrying)
	ok = ok and carrying
	_move_to(stand + Vector3(0.0, 0.0, -4.0), -PI * 0.5)
	await _ticks(20)
	var along := target.global_position.distance_to(me.global_position)
	print("[BrawlTest] walked 4 m with them: they're %.2f m from me" % along)
	ok = ok and along < 1.6
	brawl.call("request_release_player", "drop")
	await _ticks(10)
	var set_down := int(me.get("carrying")) == 0 and int(target.get("carried_by")) == 0 and target.global_position.distance_to(me.global_position) < 2.5
	print("[BrawlTest] set them down: %s" % set_down)
	ok = ok and set_down
	# Grab again and throw.
	await _ticks(10)
	await _place(stand, stand + Vector3(1.0, 0.0, 0.0), target)
	brawl.call("request_grab_player", target.name.to_int())
	await _ticks(12)
	from = me.global_position
	brawl.call("request_release_player", "throw", Vector3(1.0, 0.0, 0.0), 1.4)
	var flew := false
	var far := 0.0
	var elapsed := 0.0
	while elapsed < 2.5:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		flew = flew or bool(target.get("thrown"))
		far = maxf(far, target.global_position.distance_to(from))
	print("[BrawlTest] threw them: flew %s, landed %.1f m away" % [flew, far])
	ok = ok and flew and far > 2.5
	result = {"ok": ok}
	print("[BrawlTest] all ok: %s" % ok)


## Me at stand facing +X, them at there (host-to-owner teleport).
func _place(stand: Vector3, there: Vector3, target: Node3D) -> void:
	_move_to(stand, -PI * 0.5)
	target.call("send_teleport", Transform3D(Basis(Vector3.UP, PI * 0.5), there))
	await _ticks(8)


func _moved(target: Node3D, from: Vector3, seconds: float) -> float:
	var most := 0.0
	var elapsed := 0.0
	while elapsed < seconds:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		most = maxf(most, Vector2(target.global_position.x - from.x, target.global_position.z - from.z).length())
	return most


func _grab(item: Node3D) -> void:
	var me := _own_player()
	await get_tree().physics_frame
	item.global_position = me.global_position + Vector3(0.0, 0.4, 0.0) + (-me.global_basis.z) * 0.6
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
