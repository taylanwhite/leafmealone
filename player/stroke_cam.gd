extends Node

## Authority: local presentation. Under your own first-person camera
## (Visual/Head/FirstPerson; equipment/rake.gd adds it once you hold the rake):
## the camera nods down a touch as the tines bite, rolls with the drift and
## narrows the view a hair during the drive (equipment/rake_stroke.gd sample:
## cam_pitch, cam_roll, fov_kick). Additive: each tick it takes back what it added
## last tick, so the head's aim, which rake.gd and the tools read, never moves,
## and anyone else setting the camera's rotation or field of view (camera_rig.gd,
## a Settings change) is kept. Ticks with physics so interpolation smooths it.

## Whose swing to follow: the local player's peer id.
var actor: int = 0

var _applied := Vector3.ZERO
var _fov_applied: float = 0.0
var _fov_left: float = -1.0


func _physics_process(_delta: float) -> void:
	var camera := get_parent() as Camera3D
	if camera == null:
		return
	var shown := RakeStroke.display(actor) if _holding() else RakeStroke.idle()
	var want := Vector3(deg_to_rad(float(shown["cam_pitch"])), 0.0, deg_to_rad(float(shown["cam_roll"])))
	if not Constants.RAKE_CAM_ENABLED:
		want = Vector3.ZERO
	camera.rotation += want - _applied
	_applied = want
	var kick := float(shown["fov_kick"]) if Constants.RAKE_CAM_ENABLED else 0.0
	var base := camera.fov - _fov_applied
	# Someone set the field of view since last tick (a Settings change): that's the base now.
	if absf(camera.fov - _fov_left) > 0.001:
		base = camera.fov
	camera.fov = base + kick
	_fov_applied = kick
	_fov_left = camera.fov


func _holding() -> bool:
	var player := get_parent().get_parent().get_parent().get_parent() if get_parent() != null else null
	if player == null or not player.has_method("_held_prop"):
		return false
	var held: Node = player.call("_held_prop")
	return held != null and str(held.get("kind")) == "rake"


## How far the camera is turned and zoomed by the swing right now (for tests).
func offset() -> Dictionary:
	return {"rotation": _applied, "fov": _fov_applied}
