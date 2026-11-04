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

const _Overheads = preload("res://ui/overheads.gd")

var max_screen: float = Constants.CHEFTY_LABEL_MAX_SCREEN
var gone_m: float = Constants.CHEFTY_LABEL_GONE_M
var full_m: float = Constants.CHEFTY_LABEL_FULL_M
## p1-ui: its own fade now (distance and the yard HUD's), and the share of it
## ui/overheads.gd lets show (a world sign: off a screen edge, off the HUD, out of
## a nearer name's way, gone during a stage shot). Drawn at their product.
var own_alpha: float = 1.0
var screen_alpha: float = 1.0:
	set(value):
		screen_alpha = value
		transparency = 1.0 - own_alpha * screen_alpha
## Its own pixel size; it draws smaller by drawing smaller pixels (a billboard
## doesn't take its node's scale).
var _base_pixel: float = 0.0


func _ready() -> void:
	_base_pixel = pixel_size
	add_to_group(_Overheads.SIGNS)
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
	# R2c: it's HUD hung in the world, so it eases out with the yard HUD while the
	# moment has you (Chefty's "0/50 bags" used to float through the Courtesy
	# Shuttle's window during the ride).
	own_alpha = smoothstep(gone_m, full_m, away) * _Overheads.yard_alpha(get_tree())
	transparency = 1.0 - own_alpha * screen_alpha
	var size := 1.0
	if camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		var view_height := 2.0 * away * tan(deg_to_rad(camera.fov) * 0.5)
		var line := float(font_size) * _base_pixel
		size = clampf(max_screen * view_height / maxf(line, 0.001), Constants.CHEFTY_LABEL_MIN_SCALE, 1.0)
	# Only when it really changes: a new pixel size rebuilds the text's mesh.
	if absf(pixel_size - _base_pixel * size) > _base_pixel * 0.01:
		pixel_size = _base_pixel * size
	return size
