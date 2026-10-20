extends RefCounted

## Authority: the local peer, for its own character only. A bot's work on the lot,
## played with the same inputs a person presses: grab the rake when it is free,
## rake leaves into a pile and bag it, and carry loose bags to Chefty. Whoever has
## no rake and no bag to carry scoops at the leaves by hand now and then. Bots
## never talk to the homeowner, so a job ends only when a person says so.

## A rake run starts this far from the pile and ends at it.
const RUN_METERS: float = 5.0
## A stroke lands REACH (1.5 m) ahead and shoves leaves about 1.5 m further, so
## stop raking this far out to leave them on the pile, and bag from close in.
const STOP_RAKING_METERS: float = 3.0
const BAG_FROM_METERS: float = 1.5
## Rake this many runs into one pile from all sides, then bag it: a bigger pile
## makes a bag worth more. Then start a new pile somewhere else.
const RUNS_PER_PILE: int = 5
## With this many bags lying around, the raker puts the rake down and carries.
const LOOSE_BAGS_BEFORE_CARRYING: int = 3
const GRAB_FROM_METERS: float = 1.8

var _rng: RandomNumberGenerator
var _pile := Vector3.INF
var _run_start := Vector3.ZERO
var _runs_on_pile: int = 0
var _raking_in: bool = false
var _bag_next: bool = false
var _hand_raking: bool = false
var _next_hand_choice: float = 0.0
var _press_wait: float = 0.0
var _release_next: StringName = &""
var _elapsed: float = 0.0


func _init(rng: RandomNumberGenerator) -> void:
	_rng = rng


## Steers for this tick. Returns false when there is no work here, so the bot
## wanders instead.
func step(player: Node3D, delta: float) -> bool:
	_elapsed += delta
	_press_wait = maxf(0.0, _press_wait - delta)
	if _release_next != &"":
		_send(_release_next, false)
		_release_next = &""
	var tree := player.get_tree()
	var field := tree.get_first_node_in_group("leaf_field")
	if field == null or Net.player_zone(Net.local_peer_id()) != Net.Zone.LOT:
		stop()
		return false
	# Raking walks slowly so the strokes overlap; everything else walks.
	Input.action_release(&"sprint")
	Input.action_release(&"crouch")
	var held: Node = player.call("_held_prop")
	var held_kind := "" if held == null else str(held.get("kind"))
	match held_kind:
		"rake":
			return _rake(player, field, tree)
		"leaf_bag":
			return _carry_to_truck(player, held, tree)
		"":
			return _find_work(player, tree)
		_:
			# Not something bots work with. Put it down.
			stop()
			_tap(&"drop")
			return false


## Lets go of anything the job is holding down, for a chase or leaving the lot.
func stop() -> void:
	Input.action_release(&"primary")
	Input.action_release(&"crouch")
	_raking_in = false
	_bag_next = false
	_hand_raking = false


func _rake(player: Node3D, field: Node, tree: SceneTree) -> bool:
	_hand_raking = false
	if _loose_bags(tree).size() >= LOOSE_BAGS_BEFORE_CARRYING:
		stop()
		_tap(&"drop")
		return false
	if _bag_next:
		Input.action_release(&"primary")
		_face(player, _pile)
		if _press_wait > 0.0 or _release_next != &"" or _flat_distance(player.global_position, _pile) > BAG_FROM_METERS:
			return true
		_bag_next = false
		_tap(&"secondary")
		_pile = Vector3.INF
		return true
	if _pile == Vector3.INF:
		_pile = _random_spot(field)
		_runs_on_pile = 0
		_new_run(player)
	if not _raking_in:
		Input.action_release(&"primary")
		_face(player, _run_start)
		if _flat_distance(player.global_position, _run_start) < 1.0:
			_raking_in = true
		return true
	_face(player, _pile)
	Input.action_press(&"primary")
	Input.action_press(&"crouch")
	if _flat_distance(player.global_position, _pile) <= STOP_RAKING_METERS:
		Input.action_release(&"primary")
		_runs_on_pile += 1
		if _runs_on_pile >= RUNS_PER_PILE:
			_bag_next = true
		else:
			_new_run(player)
	return true


func _carry_to_truck(player: Node3D, held: Node, tree: SceneTree) -> bool:
	stop()
	var truck := tree.get_first_node_in_group("chefty")
	if truck == null or bool(truck.call("is_riding")):
		return false
	_face(player, truck.call("body_position"))
	if bool(held.call("near_truck")):
		_tap(&"interact")
	return true


func _find_work(player: Node3D, tree: SceneTree) -> bool:
	_raking_in = false
	_bag_next = false
	var target: Node3D = _nearest(player, _loose_bags(tree))
	if target == null:
		var rake := _free_rake(tree)
		if rake != null:
			target = rake
	if target != null:
		_hand_raking = false
		Input.action_release(&"primary")
		_face(player, target.global_position)
		if _flat_distance(player.global_position, target.global_position) <= GRAB_FROM_METERS:
			_tap(&"interact")
		return true
	# Nothing to carry and someone else has the rake: scoop by hand, sometimes.
	if _elapsed >= _next_hand_choice:
		_next_hand_choice = _elapsed + _rng.randf_range(2.0, 5.0)
		_hand_raking = _rng.randf() < 0.35
	if _hand_raking:
		Input.action_press(&"primary")
	else:
		Input.action_release(&"primary")
	return false


func _new_run(player: Node3D) -> void:
	var angle := _rng.randf_range(0.0, TAU)
	_run_start = _pile + Vector3(cos(angle), 0.0, sin(angle)) * RUN_METERS
	_raking_in = _flat_distance(player.global_position, _run_start) < 1.0


## A pile spot well inside the leaf field, so every run starts on leaves.
func _random_spot(field: Node) -> Vector3:
	var origin: Vector3 = field.get("grid_origin")
	var cell := float(field.get("cell_size"))
	var width := float(int(field.get("grid_width"))) * cell
	var depth := float(int(field.get("grid_depth"))) * cell
	var margin := RUN_METERS + 1.0
	var local := origin + Vector3(
		_rng.randf_range(margin, maxf(margin, width - margin)),
		0.0,
		_rng.randf_range(margin, maxf(margin, depth - margin)))
	return (field as Node3D).global_transform * local


func _loose_bags(tree: SceneTree) -> Array:
	var bags: Array = []
	for node: Node in tree.get_nodes_in_group("props"):
		if str(node.get("kind")) == "leaf_bag" and int(node.get("held_by")) == 0:
			bags.append(node)
	return bags


func _free_rake(tree: SceneTree) -> Node3D:
	for node: Node in tree.get_nodes_in_group("props"):
		if str(node.get("kind")) == "rake" and int(node.get("held_by")) == 0:
			return node as Node3D
	return null


func _nearest(player: Node3D, nodes: Array) -> Node3D:
	var closest: Node3D = null
	var closest_distance := INF
	for node: Variant in nodes:
		var spot := node as Node3D
		if spot == null:
			continue
		var distance := _flat_distance(player.global_position, spot.global_position)
		if distance < closest_distance:
			closest = spot
			closest_distance = distance
	return closest


## Turn so move_forward heads toward the point. Forward is -Z, rotated by body_yaw.
func _face(player: Node3D, point: Vector3) -> void:
	var away := point - player.global_position
	if Vector2(away.x, away.z).length() < 0.01:
		return
	player.set("body_yaw", atan2(-away.x, -away.z))


## A quick press, released next tick, sent as input events so both
## _unhandled_input and is_action_just_pressed see it. At most one a second.
func _tap(action: StringName) -> void:
	if _press_wait > 0.0 or _release_next != &"":
		return
	_press_wait = 1.0
	_send(action, true)
	_release_next = action


func _send(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
