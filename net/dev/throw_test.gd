extends Node

## Authority: host. --throw-test checks throwing with G the way a player does it,
## by holding the real input: a tap sets the item down, a short wind-up throws
## it a little way, a full wind-up throws it far, hands that are full can't grab
## a second thing, and holding on for too long strains and then faints you, and
## you drop it. In a windowed run it also saves a picture of the meter while
## straining (--screenshot dir). Each step prints a [ThrowTest] line.

static var result: Dictionary = {}

var _started: bool = false


func _process(_delta: float) -> void:
	if _started or not Net.is_host() or _own_player() == null or get_tree().get_first_node_in_group("job_lot") == null:
		return
	_started = true
	_run()


func _run() -> void:
	await get_tree().create_timer(1.5).timeout
	var me := _own_player()
	var gnome := _prop("gnome")
	var ok := true
	# A tap sets it down.
	await _grab(gnome)
	await _hold_g(0.08)
	var tapped := int(gnome.get("held_by")) == 0
	print("[ThrowTest] tap G: set down %s" % tapped)
	ok = ok and tapped
	# Hands full: a second grab does nothing.
	await _grab(gnome)
	var trash := _prop("trash")
	trash.global_position = me.global_position + Vector3(0.6, 0.3, 0.0)
	await _ticks(2)
	trash.call("request_grab")
	await _ticks(3)
	var one := int(trash.get("held_by")) == 0 and int(gnome.get("held_by")) == Net.local_peer_id()
	print("[ThrowTest] grab a second thing with full hands: refused %s" % one)
	ok = ok and one
	# A short wind-up and a full one: the full one goes farther.
	var short: float = await _throw_distance(gnome, 0.35)
	var full: float = await _throw_distance(gnome, 1.4)
	print("[ThrowTest] gnome thrown after 0.35 s: %.1f m, after 1.4 s: %.1f m" % [short, full])
	ok = ok and full > short * 1.5 and short > 0.5
	# Hold on too long: strain, then faint and drop it.
	await _grab(gnome)
	Input.action_press(&"drop")
	var strained := false
	var fainted := false
	var shot := false
	var waited := 0.0
	while waited < Constants.THROW_FAINT_SECONDS + 0.8:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
		strained = strained or bool(me.get("straining"))
		if not shot and waited > Constants.THROW_STRAIN_SECONDS + 0.8:
			shot = true
			_snapshot("throw_strain")
		if int(me.get("anim_state")) == 5:
			fainted = true
	Input.action_release(&"drop")
	var dropped := int(gnome.get("held_by")) == 0
	print("[ThrowTest] held G for %.0f s: strained %s, fainted %s, dropped it %s" % [Constants.THROW_FAINT_SECONDS, strained, fainted, dropped])
	ok = ok and strained and fainted and dropped
	result["ok"] = ok
	print("[ThrowTest] all ok: %s" % ok)


## Throw down the open driveway toward the street, and how far it got at most.
func _throw_distance(item: Node3D, hold: float) -> float:
	await get_tree().create_timer(Constants.FAINT_SECONDS).timeout
	var lot := get_tree().get_first_node_in_group("job_lot") as Node3D
	var me := _own_player()
	await get_tree().physics_frame
	me.call("apply_network_teleport", Transform3D(Basis.IDENTITY, lot.global_position + Vector3(0.0, 0.1, 12.5)))
	await _grab(item, PI)
	var start := me.global_position
	Input.action_press(&"drop")
	var waited := 0.0
	while waited < hold:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	Input.action_release(&"drop")
	var farthest := 0.0
	waited = 0.0
	while waited < 2.5:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
		farthest = maxf(farthest, Vector2(item.global_position.x - start.x, item.global_position.z - start.z).length())
	return farthest


func _grab(item: Node3D, yaw: float = 0.0) -> void:
	var me := _own_player()
	await get_tree().physics_frame
	me.set("body_yaw", yaw)
	me.rotation.y = yaw
	item.global_position = me.global_position + Vector3(0.0, 0.4, 0.0) + (-me.global_basis.z) * 0.8
	item.set("linear_velocity", Vector3.ZERO)
	await _ticks(3)
	item.call("request_grab")
	await _ticks(3)


func _hold_g(seconds: float) -> void:
	Input.action_press(&"drop")
	var waited := 0.0
	while waited < seconds:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	Input.action_release(&"drop")
	await _ticks(3)


func _snapshot(label: String) -> void:
	var dir := str(Net.dev_options().get("screenshot_dir"))
	if dir == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, label])


func _ticks(count: int) -> void:
	for _tick: int in count:
		await get_tree().physics_frame


func _own_player() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as Node3D
	return null


func _prop(kind: String) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) == kind and not node.is_queued_for_deletion():
			return node as Node3D
	return null
