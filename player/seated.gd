extends RefCounted

## Authority: the owning peer. A player in a drivable vehicle's seat (Chefty in
## the connected town, net/components/chefty_drive.gd), kept out of player.gd so
## its hooks there stay a few lines. Seated, a player never walks: every peer
## puts them on their seat each physics tick (player.gd _seat_on_ride). Their
## own peer turns the head (mouse), drives if they're in the driver's seat
## (W/S, A/D, Space handbrake, H or left click horn), and handles E (get out),
## F (swap seats) and the camera key (chase camera or first person).

const _VehicleCamera = preload("res://player/vehicle_camera.gd")
const _Vehicles = preload("res://props/vehicles.gd")
## player.gd's AnimState.IDLE, and its PITCH_LIMIT.
const ANIM_IDLE: int = 0
const PITCH_LIMIT: float = 1.2


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
	player.set("anim_state", ANIM_IDLE)
	var look: Vector2 = player.get("_look")
	player.set("_look", Vector2.ZERO)
	var turn := Settings.look_scale()
	var seat_look := clampf(float(player.get("seat_look")) - look.x * turn.x, -Constants.CHEFTY_SEAT_LOOK_YAW, Constants.CHEFTY_SEAT_LOOK_YAW)
	player.set("seat_look", seat_look)
	player.set("head_pitch", clampf(float(player.get("head_pitch")) - look.y * turn.y, -PITCH_LIMIT, PITCH_LIMIT))
	player.set("body_yaw", float(vehicle.call("yaw")) + seat_look)
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
		# In the cab with a hired hand aboard and nobody at the wheel, F lets the
		# hand drive (and F again pulls over); otherwise it swaps seats.
		if vehicle.has_method("chauffeur_action") and str(vehicle.call("chauffeur_action", player.name.to_int())) != "":
			vehicle.call("request_chauffeur")
		else:
			vehicle.call("request_swap")
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
		if camera != null:
			camera.queue_free()
			camera.name = "VehicleCameraGone"
		var head := player.get_node_or_null("Visual/Head") as Node3D
		if head != null:
			head.rotation.y = 0.0
		player.set("seat_look", 0.0)
		player.remove_meta("vehicle_chase")
		var rig := player.get_node_or_null("CameraRig")
		if rig != null:
			rig.call("set_active", true)
		return
	if camera == null:
		camera = _VehicleCamera.new()
		camera.name = "VehicleCamera"
		camera.set("player", player)
		player.add_child(camera)
	camera.set("vehicle", vehicle)
	player.set_meta("vehicle_chase", seat == 0)
	_apply_camera(player, vehicle)


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
