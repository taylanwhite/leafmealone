extends RefCounted

## Dev tool, local only. The studio's "hide" subject (R2b hide; docs/GAME.md
## "Hiding"): the hiding poses frozen at moments, so a pose can be judged without
## playing the game.
##
##   Godot --path . res://tools/studio/studio.tscn -- --subject=hide --out=build/art/hide.png
##
## --part=poses (default): a row of players climbing out (burst_out at three
##   moments) and being pulled out (upsy_daisy_victim), then NICE BOYS peering
##   into each kind of spot and grabbing (props/hide_spot.gd peer_pose).
## --part=shell: the leafy inside of a hedge (player/hide_view.gd) seen from
##   the hider's eye, looking out, and turned 60 degrees.

const _CartoonBody = preload("res://player/cartoon_body.gd")
const _HideGestures = preload("res://player/hide_gestures.gd")
const _HideSpotLook = preload("res://props/hide_spot.gd")
const _HideView = preload("res://player/hide_view.gd")


static func build(root: Node3D, options: Dictionary) -> void:
	_HideGestures.register()
	match str(options.get("part", "poses")):
		"shell":
			_shell(root, str(options.get("kind", "hedge")))
		_:
			_poses(root)


static func _poses(root: Node3D) -> void:
	# name, gesture, share of the way through it.
	var lineup: Array = [["burst_out", 0.06], ["burst_out", 0.12], ["burst_out", 0.4], ["burst_out", 0.68], ["burst_out", 0.85], ["upsy_daisy_victim", 0.5]]
	for index: int in lineup.size():
		var body: Node3D = _CartoonBody.new()
		body.call("dress_from_seed", 3 + index * 5)
		root.add_child(body)
		body.position = Vector3(float(index) * 1.25 - 3.5, 0.0, 0.0)
		body.call("build")
		_hold(body, str(lineup[index][0]), float(lineup[index][1]))
	# NICE BOYS: peering into a hedge, a bin, a shed, a pile; the found grab; the haul.
	var crew: Array = [["hedge", 1.0, 0.0, 0.0], ["bin", 1.0, 0.0, 0.0], ["shed", 1.0, 0.0, 0.0], ["pile", 1.0, 0.0, 0.0], ["hedge", 1.0, 1.0, 0.0], ["hedge", 0.0, 1.0, 0.7]]
	for index: int in crew.size():
		var body: Node3D = _CartoonBody.new()
		preload("res://npcs/crew_member.gd").dress(body, 2)
		root.add_child(body)
		body.position = Vector3(float(index) * 1.4 - 3.5, 0.0, -8.0)
		# In profile, facing +X, so the lean reads.
		body.rotation.y = -PI * 0.5
		body.call("build")
		for _step: int in 3:
			body.call("_physics_process", 1.0 / 60.0)
		var entry: Array = crew[index]
		_HideSpotLook.peer_pose(body, str(entry[0]), float(entry[1]), float(entry[2]), float(entry[3]), 0.0)
		body.set_physics_process(false)
	# The players from the front (they face -Z: the camera is ahead of them), the
	# NICE BOYS in profile and from where a hider would see them.
	root.set_meta("views", [
		{"from": Vector3(-1.0, 1.4, -5.0), "at": Vector3(-1.0, 1.0, 0.0), "fov": 50.0},
		{"from": Vector3(0.0, 1.2, -2.0), "at": Vector3(0.0, 1.0, -8.0), "fov": 55.0},
		{"from": Vector3(-1.5, 1.3, -2.0), "at": Vector3(-3.0, 1.0, 0.0), "fov": 35.0},
		{"from": Vector3(1.0, 1.3, -8.0), "at": Vector3(-3.5, 1.2, -8.0), "fov": 40.0},
	])


## Runs a body's animation to share t of the gesture, then freezes it there.
static func _hold(body: Node3D, gesture_name: String, t: float) -> void:
	body.call("gesture", gesture_name)
	var seconds := float(_HideGestures.SECONDS.get(gesture_name, 1.0))
	var steps := maxi(1, int(round(seconds * t * 60.0)))
	for _step: int in steps:
		body.call("_physics_process", 1.0 / 60.0)
	body.set_physics_process(false)


## The inside of a spot from the hider's eye: the shell around a marker at 1.4 m
## looking down -Z, and the yard beyond.
static func _shell(root: Node3D, kind: String) -> void:
	var eye := Transform3D(Basis.IDENTITY, Vector3(0.0, 1.4, 0.0))
	var shell := _HideView.make_shell(kind)
	if shell != null:
		root.add_child(shell)
		shell.global_transform = eye
	# Something out in the yard to look at.
	var body: Node3D = _CartoonBody.new()
	preload("res://npcs/crew_member.gd").dress(body, 2)
	root.add_child(body)
	# He stands HIDE_INSPECT_STAND out from the face, facing the eye.
	body.position = Vector3(0.0, 0.0, -0.03 - Constants.HIDE_INSPECT_STAND)
	body.rotation.y = PI
	body.call("build")
	for _step: int in 3:
		body.call("_physics_process", 1.0 / 60.0)
	_HideSpotLook.peer_pose(body, kind, 1.0, 0.0, 0.0, 0.0)
	body.set_physics_process(false)
	var ahead := eye.origin + Vector3(0.0, 0.0, -1.0)
	var turned := eye.origin + Vector3(-sin(1.05), 0.0, -cos(1.05))
	root.set_meta("views", [
		{"from": eye.origin, "at": ahead, "fov": 75.0},
		{"from": eye.origin, "at": turned, "fov": 75.0},
		{"from": eye.origin, "at": eye.origin + Vector3(-1.0, 0.0, 0.2), "fov": 75.0},
		{"from": Vector3(2.0, 2.2, 1.5), "at": Vector3(0.0, 1.2, -0.4), "fov": 45.0},
	])
