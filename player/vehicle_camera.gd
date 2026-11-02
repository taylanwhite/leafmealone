extends Camera3D

## Authority: local presentation. The chase camera behind a vehicle you sit in
## (player/seated.gd adds it under your own player; the camera key swaps it with
## your own eyes). It follows the vehicle's rendered body on physics ticks, so
## physics interpolation smooths it with the truck: Constants.CHEFTY_CAMERA_BACK
## behind and CHEFTY_CAMERA_UP over it, looking a little ahead by speed, the field
## of view widening with speed. The mouse swings it round (the seat's look).

var vehicle: Node3D
var player: Node3D
var _placed: bool = false


func _ready() -> void:
	# After the vehicle (0), its view (50) and the players (100) have moved.
	process_physics_priority = 120
	fov = Constants.CHEFTY_CAMERA_FOV.x


## Jump straight to the spot behind the vehicle (no swing in from wherever).
func snap() -> void:
	_placed = false


func _physics_process(delta: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	var body: Transform3D = vehicle.call("body_transform")
	var look := float(player.get("seat_look")) if player != null else 0.0
	var heading := float(vehicle.call("yaw")) + look
	var behind := Vector3(sin(heading), 0.0, cos(heading))
	var speed := float(vehicle.call("speed"))
	var forward := Vector3(-sin(heading), 0.0, -cos(heading))
	var focus := body.origin + Vector3(0.0, 1.6, 0.0) + forward * speed * Constants.CHEFTY_CAMERA_LEAD
	var want := body.origin + behind * Constants.CHEFTY_CAMERA_BACK + Vector3.UP * Constants.CHEFTY_CAMERA_UP
	if not _placed:
		global_position = want
		reset_physics_interpolation()
		_placed = true
	else:
		global_position = global_position.lerp(want, 1.0 - exp(-Constants.CHEFTY_CAMERA_FOLLOW * delta))
	if global_position.distance_to(focus) > 0.1:
		look_at(focus, Vector3.UP)
	var share := clampf(speed / Constants.CHEFTY_TOP_SPEED, 0.0, 1.0)
	fov = lerpf(Constants.CHEFTY_CAMERA_FOV.x, Constants.CHEFTY_CAMERA_FOV.y, share)
