extends Node

## Authority: local presentation. Under your own first-person camera
## (Visual/Head/FirstPerson; equipment/rake.gd adds it once you hold the rake):
## the camera nods down a touch as the tines bite, rolls with the drift and
## narrows the view a hair during the drive (equipment/rake_stroke.gd sample:
## cam_pitch, cam_roll, fov_kick). Your eyes go with your body's lunge and sink
## into the knees (sample hip and crouch, a share of each), and while the rake
## works the view settles a few degrees further down onto the tines
## (Constants.RAKE_FP_LOOK_DEG), easing back once you stop. Additive: each tick
## it takes back what it added last tick, so the head's aim, which rake.gd and
## the tools read, never moves, and anyone else setting the camera's rotation,
## position or field of view (camera_rig.gd, a Settings change) is kept. Ticks
## with physics so interpolation smooths it.

## Whose swing to follow: the local player's peer id.
var actor: int = 0

var _applied := Vector3.ZERO
var _moved := Vector3.ZERO
var _pos_left := Vector3.INF
var _fov_applied: float = 0.0
var _fov_left: float = -1.0
## 0..1: how far the work look-down is eased in.
var _working: float = 0.0


func _physics_process(delta: float) -> void:
	var camera := get_parent() as Camera3D
	if camera == null:
		return
	var holding := _holding()
	var shown := RakeStroke.display(actor) if holding else RakeStroke.idle()
	var swinging := holding and RakeStroke.is_moving(actor)
	var ease := 1.0 - exp(-delta / maxf(Constants.RAKE_FP_LOOK_SECONDS, 0.001))
	_working = lerpf(_working, 1.0 if swinging else 0.0, ease)
	var look_down := deg_to_rad(Constants.RAKE_FP_LOOK_DEG) * smoothstep(0.0, 1.0, _working)
	var want := Vector3(deg_to_rad(float(shown["cam_pitch"])) - look_down, 0.0, deg_to_rad(float(shown["cam_roll"])))
	# The lunge (hip is + back) and the sink, in the head's own frame: forward is -Z.
	var crouch_rest := Constants.RAKE_CROUCH_IDLE
	var sink := maxf(float(shown.get("crouch", crouch_rest)) - crouch_rest, 0.0) * Constants.RAKE_FP_CROUCH_SHARE
	var lunge := -float(shown.get("hip", 0.0)) * Constants.RAKE_FP_LUNGE_SHARE
	var move := Vector3(0.0, -sink, -lunge) if holding else Vector3.ZERO
	if not Constants.RAKE_CAM_ENABLED:
		want = Vector3.ZERO
		move = Vector3.ZERO
	camera.rotation += want - _applied
	_applied = want
	# player.gd sets the camera's height every tick (down in a pile): whatever was
	# set since last tick is the base now, else take back what was added.
	# Axis by axis: it only ever sets the height.
	var base_at := camera.position - _moved
	for axis: int in 3:
		if _pos_left.is_finite() and absf(camera.position[axis] - _pos_left[axis]) > 0.0001:
			base_at[axis] = camera.position[axis]
	camera.position = base_at + move
	_moved = move
	_pos_left = camera.position
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


## How far the camera is turned, moved and zoomed by the swing right now (for tests).
func offset() -> Dictionary:
	return {"rotation": _applied, "position": _moved, "fov": _fov_applied}
