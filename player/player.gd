extends CharacterBody3D

## Authority: owning peer for movement, look, and the values replicated below.
## Remote peers display those values. NetSmoother only moves the visual on remotes.

enum AnimState { IDLE, WALK, SPRINT, CROUCH, AIR }

# TODO(balance): add movement speeds to the workbook.
const WALK_SPEED: float = 5.0
const SPRINT_SPEED: float = 8.0
const CROUCH_SPEED: float = 2.5
const JUMP_VELOCITY: float = 4.5
const MOUSE_SENSITIVITY: float = 0.003
const STAND_HEIGHT: float = 1.8
const CROUCH_HEIGHT: float = 1.1
const PITCH_LIMIT: float = 1.2

## Yaw of the body in radians. Replicated.
@export var body_yaw: float = 0.0
## Pitch of the head in radians. Replicated.
@export var head_pitch: float = 0.0
## Coarse pose shared with other peers. Replicated.
@export var anim_state: AnimState = AnimState.IDLE
## Equipped tool id. Empty until tools exist. Replicated.
@export var equipment_id: String = ""

var _look := Vector2.ZERO
var _ride: Node3D
var _seat_index: int = -1
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _enter_tree() -> void:
	add_to_group("players")
	var peer_id := name.to_int()
	if peer_id <= 0:
		return
	# The synchronizer has to share this peer's authority or the client cannot publish its pose.
	set_multiplayer_authority(peer_id, true)


func _ready() -> void:
	%Collision.shape = %Collision.shape.duplicate()
	%CameraRig.set_active(is_multiplayer_authority())
	%Nameplate.visible = not is_multiplayer_authority()
	_refresh_name()
	if not Net.player_joined.is_connected(_on_player_joined):
		Net.player_joined.connect(_on_player_joined)
	if not Net.player_zone_changed.is_connected(_on_zone_changed):
		Net.player_zone_changed.connect(_on_zone_changed)
	_apply_presentation()


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event.is_action_pressed("toggle_camera"):
		%CameraRig.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and _grab_nearby():
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("drop"):
		_release_held(false)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_look += motion.relative


func _physics_process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if is_multiplayer_authority():
		_apply_look()
		if _ride != null and _seat_index >= 0 and _ride.has_method("seat_transform"):
			var seat: Transform3D = _ride.call("seat_transform", _seat_index)
			global_position = seat.origin
		else:
			_simulate(delta)
	_apply_presentation()


## Follow a seat until the ride arrives. Movement stays off; looking still works.
func set_riding(ride: Node3D, seat_index: int) -> void:
	_ride = ride
	_seat_index = seat_index
	velocity = Vector3.ZERO


func clear_riding() -> void:
	_ride = null
	_seat_index = -1


func _on_zone_changed(peer_id: int, zone: Net.Zone) -> void:
	if peer_id == name.to_int() and zone != Net.Zone.TRANSIT:
		clear_riding()


## Host-ordered teleport. Runs on the owning peer only.
func apply_network_teleport(at: Transform3D) -> void:
	global_position = at.origin
	velocity = Vector3.ZERO
	body_yaw = at.basis.get_euler().y
	_apply_presentation()


func _grab_nearby() -> bool:
	var closest: Node = null
	var closest_distance := 2.4
	for node: Node in get_tree().get_nodes_in_group("props"):
		if not node is Node3D:
			continue
		var distance := global_position.distance_to((node as Node3D).global_position)
		if distance < closest_distance:
			closest = node
			closest_distance = distance
	if closest == null:
		return false
	closest.call("request_grab")
	return true


func _release_held(throw_it: bool) -> void:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if int(node.get("held_by")) != name.to_int():
			continue
		if throw_it:
			node.call("request_throw", -global_transform.basis.z)
		else:
			node.call("request_drop")
		return


func holding_prop() -> bool:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if int(node.get("held_by")) == name.to_int():
			return true
	return false


func _apply_look() -> void:
	body_yaw -= _look.x * MOUSE_SENSITIVITY
	head_pitch = clampf(head_pitch - _look.y * MOUSE_SENSITIVITY, -PITCH_LIMIT, PITCH_LIMIT)
	_look = Vector2.ZERO


func _simulate(delta: float) -> void:
	var crouching := Input.is_action_pressed("crouch")
	_apply_stance(crouching)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump") and not crouching:
		velocity.y = JUMP_VELOCITY
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var speed := WALK_SPEED
	if crouching:
		speed = CROUCH_SPEED
	elif Input.is_action_pressed("sprint"):
		speed = SPRINT_SPEED
	if direction.is_zero_approx():
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)
	else:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	move_and_slide()
	_update_anim(crouching, direction)


func _update_anim(crouching: bool, direction: Vector3) -> void:
	if not is_on_floor():
		anim_state = AnimState.AIR
	elif crouching:
		anim_state = AnimState.CROUCH
	elif direction.is_zero_approx():
		anim_state = AnimState.IDLE
	elif Input.is_action_pressed("sprint"):
		anim_state = AnimState.SPRINT
	else:
		anim_state = AnimState.WALK


func _apply_stance(crouching: bool) -> void:
	var shape := %Collision.shape as CapsuleShape3D
	var height := CROUCH_HEIGHT if crouching else STAND_HEIGHT
	shape.height = height
	%Collision.position.y = height * 0.5
	%BodyMesh.scale.y = height / STAND_HEIGHT
	%BodyMesh.position.y = height * 0.5


func _apply_presentation() -> void:
	rotation.y = body_yaw
	%Head.rotation.x = head_pitch


func _refresh_name() -> void:
	var shown := Net.player_name(name.to_int())
	if shown != "":
		%Nameplate.text = shown


func _on_player_joined(peer_id: int) -> void:
	if peer_id == name.to_int():
		_refresh_name()
