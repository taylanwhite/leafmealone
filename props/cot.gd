extends Node3D

## Authority: local look; the host decides who sleeps (net/day/day_clock.gd).
## A folding cot in the crew's camp by Homie Depot's side wall: the manager
## lets the crew crash there, under a tarp, for a cut. Walk up and press E to lie
## down; once everyone is down, the day ends. The host can hold E while lying
## down to drag the whole crew to bed. Moving gets you up.

const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const _Strings = preload("res://ui/strings.gd")
const REACH: float = 1.6
const FRAME := Color(0.35, 0.37, 0.33)
const CANVAS := Color(0.42, 0.5, 0.34)
const PILLOW := Color(0.93, 0.9, 0.82)

## Which cot this is, 0 to 3: the n-th sleeper lies on the n-th cot.
var index: int = 0


func _ready() -> void:
	add_to_group("cots")
	add_to_group("prompt_sources")
	_build()


## Where a sleeper's body goes, on top of the canvas.
func bed_transform() -> Transform3D:
	return Transform3D(global_basis, global_position + Vector3(0.0, 0.45, 0.0))


func prompt() -> Dictionary:
	var clock := _clock()
	if clock == null or not _local_near():
		return {}
	var me := Net.local_peer_id()
	var lying := (clock.get("sleepers") as Array).size()
	var total := Net.peer_ids().size()
	if bool(clock.call("is_sleeping", me)):
		var key := "prompt_cot_host" if Net.is_host() else "prompt_cot_lying"
		return {"text": _Strings.UI[key] % [lying, total], "at": global_position + Vector3(0.0, 1.4, 0.0)}
	return {"text": _Strings.UI["prompt_cot"] % [lying, total], "at": global_position + Vector3(0.0, 1.2, 0.0)}


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or not _local_near():
		return
	var clock := _clock()
	if clock == null:
		return
	# Only the nearest cot answers, so one press is one lie-down.
	if _nearest_cot() != self:
		return
	if not bool(clock.call("is_sleeping", Net.local_peer_id())):
		clock.call("request_sleep", true, index)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var clock := _clock()
	if clock == null or _nearest_cot() != self:
		return
	# The host, lying down and holding E, puts everyone to bed.
	if Net.is_host() and bool(clock.call("is_sleeping", Net.local_peer_id())) and Input.is_action_pressed("interact"):
		clock.call("hold_force", delta)
	elif Net.is_host():
		clock.call("release_force")


func _clock() -> Node:
	return get_tree().get_first_node_in_group("day_clock")


func _local_body() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as Node3D
	return null


func _local_near() -> bool:
	if Net.player_zone(Net.local_peer_id()) != Net.Zone.STORE:
		return false
	var body := _local_body()
	if body == null:
		return false
	var flat := body.global_position - global_position
	flat.y = 0.0
	return flat.length() < REACH


func _nearest_cot() -> Node3D:
	var body := _local_body()
	if body == null:
		return null
	var best: Node3D = null
	var best_distance := INF
	for node: Node in get_tree().get_nodes_in_group("cots"):
		var cot := node as Node3D
		var distance := cot.global_position.distance_to(body.global_position)
		if distance < best_distance:
			best_distance = distance
			best = cot
	return best


## A folding cot: legs in an X at each end, a canvas bed, a lumpy pillow, and a
## rolled-up blanket at the foot. Long along x.
func _build() -> void:
	var kit := _MeshKit.new()
	for end: float in [-0.85, 0.85]:
		for side: float in [-1.0, 1.0]:
			kit.tube(PackedVector3Array([Vector3(end, 0.0, side * 0.32), Vector3(end, 0.38, -side * 0.32)]), PackedFloat32Array([0.022, 0.022]), FRAME, 6, {"jitter": 0.0})
	for side: float in [-0.33, 0.33]:
		kit.tube(PackedVector3Array([Vector3(-0.95, 0.38, side), Vector3(0.95, 0.38, side)]), PackedFloat32Array([0.025, 0.025]), FRAME, 6, {"jitter": 0.0})
	kit.rbox(Vector3(0.0, 0.39, 0.0), Vector3(0.92, 0.025, 0.33), CANVAS, 6.0)
	kit.blob(Vector3(-0.68, 0.47, 0.0), Vector3(0.17, 0.07, 0.25), PILLOW, {"seed": index + 3, "lumps": 0.15, "flat": false})
	kit.tube(PackedVector3Array([Vector3(0.7, 0.47, -0.28), Vector3(0.7, 0.47, 0.28)]), PackedFloat32Array([0.08, 0.08]), Color(0.7, 0.28, 0.22), 8, {"jitter": 0.0})
	var view := _Stylized.instance(kit.commit(), {"roughness": 0.9, "specular": 0.05})
	view.name = "Cot"
	add_child(view)


## The camp around the cots: a blue tarp on poles against the wall, a cooler,
## an alarm clock, and a sign. Called once by the world with the first cot's parent.
static func dress_camp(zone: Node3D, spots: Array[Vector3]) -> void:
	if spots.is_empty():
		return
	var kit := _MeshKit.new()
	var first := spots[0]
	var last := spots[spots.size() - 1]
	var middle := (first + last) * 0.5
	var length := absf(last.z - first.z) + 2.0
	# The tarp: tied to the store wall up high (Homie Depot's front is at x -12)
	# and sloping down to two poles out front, so it covers every cot.
	var wall_x := -11.95
	var pole_x := middle.x + 1.2
	var high := 2.8
	var low := 2.1
	var run := pole_x - wall_x
	var tilt := atan2(high - low, run)
	for z: float in [first.z - 0.9, last.z + 0.9]:
		kit.tube(PackedVector3Array([Vector3(pole_x, 0.0, z), Vector3(pole_x, low, z)]), PackedFloat32Array([0.04, 0.04]), FRAME, 6, {"jitter": 0.0})
	var span := Vector2(run, high - low).length()
	kit.rbox(Vector3((wall_x + pole_x) * 0.5, (high + low) * 0.5 + 0.02, middle.z), Vector3(span * 0.5, 0.02, length * 0.5), Color(0.2, 0.42, 0.72), 6.0, {"basis": Basis(Vector3.BACK, -tilt), "shade": false})
	# A batten along the wall where it's tied on.
	kit.rbox(Vector3(wall_x + 0.04, high, middle.z), Vector3(0.04, 0.05, length * 0.5), FRAME, 4.0)
	kit.rbox(Vector3(middle.x + 1.0, 0.22, last.z + 1.3), Vector3(0.32, 0.22, 0.22), Color(0.85, 0.25, 0.2), 5.0)
	kit.rbox(Vector3(middle.x + 1.0, 0.46, last.z + 1.3), Vector3(0.33, 0.03, 0.23), Color(0.95, 0.95, 0.92), 5.0)
	kit.blob(Vector3(middle.x - 1.2, 0.08, first.z - 1.1), Vector3(0.09, 0.08, 0.05), Color(0.9, 0.75, 0.2), {"flat": false, "lumps": 0.0})
	var view := _Stylized.instance(kit.commit(), {"roughness": 0.8, "specular": 0.1})
	view.name = "CrewCamp"
	zone.add_child(view)
	var sign := Label3D.new()
	sign.text = _Strings.UI["camp_sign"]
	sign.font_size = 40
	sign.pixel_size = 0.005
	sign.modulate = Color(1.0, 0.97, 0.88)
	sign.outline_size = 10
	sign.outline_modulate = Color(0.15, 0.15, 0.18)
	sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sign.position = Vector3(middle.x + 1.2, 2.5, middle.z)
	zone.add_child(sign)
