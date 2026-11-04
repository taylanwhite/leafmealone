extends RefCounted

## Authority: the owning peer. A player in a drivable vehicle's seat (Chefty in
## the connected town, net/components/chefty_drive.gd), kept out of player.gd so
## its hooks there stay a few lines. Seated, a player never walks: every peer
## puts them on their seat each physics tick (player.gd _seat_on_ride). Their
## own peer turns the head (mouse), drives if they're in the driver's seat
## (W/S, A/D, Space handbrake, H or left click horn), and handles E (get out),
## F (swap seats), G (let a hired hand drive, or pull over) and the camera key
## (chase camera or first person).

const _VehicleCamera = preload("res://player/vehicle_camera.gd")
const _Vehicles = preload("res://props/vehicles.gd")
const _CameraBlend = preload("res://player/camera_blend.gd")
## player.gd's AnimState.IDLE, and its PITCH_LIMIT.
const ANIM_IDLE: int = 0
const PITCH_LIMIT: float = 1.2
## A climb's anim (net/components/seat_moves.gd) as player.gd's AnimState: WALK,
## CROUCH, AIR.
const CLIMB_ANIMS: Dictionary = {"walk": 1, "crouch": 3, "air": 4}


## The vehicle this player sits in, or null (a legacy ride isn't one).
static func vehicle_of(player: Node) -> Node:
	var ride: Node = player.call("seat_ride")
	return ride if ride != null and is_instance_valid(ride) and ride.is_in_group("vehicles") else null


static func is_driving(player: Node) -> bool:
	var vehicle := vehicle_of(player)
	return vehicle != null and int(vehicle.call("driver")) == player.name.to_int()


## Owner, every physics tick while seated: look around, and drive if driving.
static func step(player: CharacterBody3D, _delta: float) -> void:
	var vehicle := vehicle_of(player)
	if vehicle == null:
		return
	player.velocity = Vector3.ZERO
	# Climbing in (fx-chefty): the steps to the door, the knees, the hop, for everyone.
	var climbing := str(vehicle.call("climb_anim", player.name.to_int())) if vehicle.has_method("climb_anim") else ""
	player.set("anim_state", CLIMB_ANIMS.get(climbing, ANIM_IDLE))
	var look: Vector2 = player.get("_look")
	player.set("_look", Vector2.ZERO)
	var turn := Settings.look_scale()
	var seat_look := clampf(float(player.get("seat_look")) - look.x * turn.x, -Constants.CHEFTY_SEAT_LOOK_YAW, Constants.CHEFTY_SEAT_LOOK_YAW)
	player.set("seat_look", seat_look)
	player.set("head_pitch", clampf(float(player.get("head_pitch")) - look.y * turn.y, -PITCH_LIMIT, PITCH_LIMIT))
	# The seat's own facing (a bed rider looks out over the side, p1-arrive), then the head's turn.
	var seat_facing := float(vehicle.call("seat_yaw", int(player.call("seat_slot")))) if vehicle.has_method("seat_yaw") else 0.0
	player.set("body_yaw", float(vehicle.call("yaw")) + seat_facing + seat_look)
	var head := player.get_node_or_null("Visual/Head") as Node3D
	if head != null:
		head.rotation.y = seat_look
	if int(vehicle.call("driver")) != player.name.to_int():
		return
	var playing := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var input := {
		"throttle": Input.get_axis("move_back", "move_forward") if playing else 0.0,
		"steer": Input.get_axis("move_left", "move_right") if playing else 0.0,
		"handbrake": playing and Input.is_action_pressed("jump"),
		"horn": playing and (Input.is_action_pressed("honk") or Input.is_action_pressed("primary")),
	}
	vehicle.call("local_drive_input", input)


## Owner: the seat's keys. True when the event was the seat's to handle.
static func handle_input(player: Node, event: InputEvent) -> bool:
	var vehicle := vehicle_of(player)
	if vehicle == null:
		return false
	if event.is_action_pressed("interact"):
		vehicle.call("request_exit")
		return true
	if event.is_action_pressed("take"):
		vehicle.call("request_swap")
		return true
	if event.is_action_pressed("drop"):
		# The chauffeur has its own key (G), so F can still slide you over: in the
		# cab with a hired hand aboard and nobody at the wheel, G lets the hand
		# drive, and G again pulls over.
		if vehicle.has_method("chauffeur_action") and str(vehicle.call("chauffeur_action", player.name.to_int())) != "":
			vehicle.call("request_chauffeur")
		return true
	if event.is_action_pressed("toggle_camera"):
		var chase := not bool(player.get_meta("vehicle_chase", false))
		player.set_meta("vehicle_chase", chase)
		_apply_camera(player, vehicle)
		return true
	# Left click and Space are the horn and the handbrake here, never a punch or a jump.
	return event.is_action_pressed("primary") or event.is_action_pressed("secondary") or event.is_action_pressed("jump") or event.is_action_pressed("drop")


## Owner: E by a door or the tailgate gets in. True when it asked for a seat.
static func try_enter(player: Node3D) -> bool:
	for vehicle: Node in player.get_tree().get_nodes_in_group("vehicles"):
		if not vehicle.has_method("prompt_for"):
			continue
		var hint: Dictionary = vehicle.call("prompt_for", player)
		if not hint.is_empty():
			vehicle.call("request_enter", int(hint["kind"]))
			return true
	return false


## The getting-in prompt for the interaction prompt, or {}.
static func hint(player: Node3D) -> Dictionary:
	for vehicle: Node in player.get_tree().get_nodes_in_group("vehicles"):
		if not vehicle.has_method("prompt_for"):
			continue
		var found: Dictionary = vehicle.call("prompt_for", player)
		if not found.is_empty():
			return found
	return {}


## Owner: sat down, moved seats, or got out. The driver gets the chase camera,
## riders their own eyes; getting out gives the normal cameras back.
static func on_seat_changed(player: Node3D, seated: bool, seat: int) -> void:
	var vehicle := vehicle_of(player) if seated else null
	var camera := player.get_node_or_null("VehicleCamera") as Camera3D
	if vehicle == null:
		var chasing := camera != null and camera.current
		if camera != null:
			camera.name = "VehicleCameraGone"
			if not chasing:
				camera.queue_free()
		var head := player.get_node_or_null("Visual/Head") as Node3D
		if head != null:
			head.rotation.y = 0.0
		player.set("seat_look", 0.0)
		player.remove_meta("vehicle_chase")
		var rig := player.get_node_or_null("CameraRig")
		if rig != null:
			rig.call("set_active", true)
		# Out from behind the chase camera (fx-chefty): the view comes down to your
		# eyes as you hop out, never a cut. The chase camera goes when it's done.
		if chasing:
			var eyes: Camera3D = rig.call("current_base_camera") if rig != null else player.get_node_or_null("Visual/Head/FirstPerson") as Camera3D
			if eyes != null and eyes.current:
				_CameraBlend.start(player, camera, eyes, Constants.CHEFTY_EXIT_CAMERA_SECONDS, true, _swing_point(camera.get("vehicle") as Node, eyes.global_position))
			else:
				camera.queue_free()
		return
	var entering := camera == null
	if camera == null:
		camera = _VehicleCamera.new()
		camera.name = "VehicleCamera"
		camera.set("player", player)
		player.add_child(camera)
	camera.set("vehicle", vehicle)
	player.set_meta("vehicle_chase", seat == 0)
	var was := player.get_viewport().get_camera_3d() if player.is_inside_tree() else null
	_apply_camera(player, vehicle)
	# Into the driver's seat: the view swings out from your eyes to the chase
	# camera while you climb in (fx-chefty), never a cut.
	if entering and was != null and was != camera and camera.current and player.is_ancestor_of(was):
		_CameraBlend.start(player, was, camera, Constants.CHEFTY_ENTER_CAMERA_SECONDS, false, _swing_point(vehicle, was.global_position))


## Where the view swings out through between your eyes and the chase camera
## (world): up and out beside the truck on the side you're on, so the lens goes
## round the bed and the cab, never through them. INF without a truck.
static func _swing_point(vehicle: Node, eye: Vector3) -> Vector3:
	if vehicle == null or not is_instance_valid(vehicle) or not vehicle.has_method("body_transform"):
		return Vector3.INF
	var body: Transform3D = vehicle.call("body_transform")
	var side := -1.0 if (body.affine_inverse() * eye).x < 0.0 else 1.0
	return body * Vector3(side * Constants.CHEFTY_CAMERA_SWING_OUT.x, Constants.CHEFTY_CAMERA_SWING_OUT.y, Constants.CHEFTY_CAMERA_SWING_OUT.z)


static func _apply_camera(player: Node, _vehicle: Node) -> void:
	var camera := player.get_node_or_null("VehicleCamera") as Camera3D
	var eyes := player.get_node_or_null("Visual/Head/FirstPerson") as Camera3D
	if camera == null or eyes == null:
		return
	if bool(player.get_meta("vehicle_chase", false)):
		camera.call("snap")
		camera.make_current()
	else:
		eyes.make_current()


## The cartoon pose for a seat: 1 sitting (the cab), 2 standing still (the bed),
## 0 not in a vehicle seat.
static func pose_for(player: Node) -> int:
	var vehicle := vehicle_of(player)
	if vehicle == null:
		return 0
	# Still climbing in (fx-chefty): on your feet to the door, sitting once over the sill.
	if vehicle.has_method("climb_pose"):
		var climbing := int(vehicle.call("climb_pose", player.name.to_int()))
		if climbing >= 0:
			return climbing
	return 1 if bool(vehicle.call("is_cab_seat", int(player.call("seat_slot")))) else 2


## The driver's hands on the wheel, world space [right, left], or [] when not driving.
static func wheel_grips(player: Node) -> Array:
	if not is_driving(player):
		return []
	var vehicle := vehicle_of(player)
	var look := vehicle.get_node_or_null("Body/TruckLook") as Node3D
	if look == null:
		return []
	return _Vehicles.wheel_grips(look)
