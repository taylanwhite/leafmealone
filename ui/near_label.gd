extends Label3D

## Authority: local, cosmetic. A floating label over something big (Chefty's
## name and load, ride.gd and chefty_drive.gd) that reads from across the yard
## but never fills your view up close: within the distance where it would stand
## taller than Constants.CHEFTY_LABEL_MAX_SCREEN of the view per line it shrinks
## to stay that size, and it fades out as you come within
## Constants.CHEFTY_LABEL_FULL_M to CHEFTY_LABEL_GONE_M of it (up close the
## heap in the bed and the floating dollars tell the load). It measures from
## whichever camera is drawing, and only changes its own scale and transparency,
## so whoever owns it can still show, hide and move it.

## How small it may get (a share of its own size), so it never vanishes into a dot
## before the fade takes it.
const MIN_SCALE: float = 0.2

var max_screen: float = Constants.CHEFTY_LABEL_MAX_SCREEN
var gone_m: float = Constants.CHEFTY_LABEL_GONE_M
var full_m: float = Constants.CHEFTY_LABEL_FULL_M
## Its own pixel size; it draws smaller by drawing smaller pixels (a billboard
## doesn't take its node's scale).
var _base_pixel: float = 0.0


func _ready() -> void:
	_base_pixel = pixel_size
	# Its size follows the camera, which moves on physics ticks too.
	process_physics_priority = 1000


func _physics_process(_delta: float) -> void:
	fit(get_viewport().get_camera_3d())


## Size and fade for this camera; returns the share of its own size it took.
func fit(camera: Camera3D) -> float:
	if camera == null or not is_inside_tree():
		return 1.0
	if _base_pixel <= 0.0:
		_base_pixel = pixel_size
	var away := camera.global_position.distance_to(global_position)
	transparency = 1.0 - smoothstep(gone_m, full_m, away)
	var size := 1.0
	if camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		var view_height := 2.0 * away * tan(deg_to_rad(camera.fov) * 0.5)
		var line := float(font_size) * _base_pixel
		size = clampf(max_screen * view_height / maxf(line, 0.001), MIN_SCALE, 1.0)
	# Only when it really changes: a new pixel size rebuilds the text's mesh.
	if absf(pixel_size - _base_pixel * size) > _base_pixel * 0.01:
		pixel_size = _base_pixel * size
	return size
