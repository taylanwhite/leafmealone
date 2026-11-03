extends Node3D

## Authority: local presentation. The player script does not read which camera is active.
## OQ-001: first person and over-the-shoulder stay swappable until the camera is decided.
## R2: CameraRig/StageCam (player/stage_cam.gd) takes the view for staged shots;
## while it has it, the toggle only changes which camera it hands back to.

@export var first_person: bool = true

var _active: bool = false


func _ready() -> void:
	_apply()
	if not Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.connect(_on_setting_changed)


## Aimed on physics ticks like everything it follows, so physics interpolation
## smooths the camera and the player together.
func _physics_process(_delta: float) -> void:
	if not _active or first_person:
		return
	%OverShoulder.look_at(%LookTarget.global_position, Vector3.UP)


## Turn this rig on only for the peer that owns the player.
func set_active(active: bool) -> void:
	_active = active
	_apply()


## Whether this rig has the view at all (off on other peers' players, and while
## something else has it: the Border Return camera, set_crossing_view).
func is_active() -> bool:
	return _active


## Swap between the two cameras. Bound to toggle_camera by the player.
func toggle() -> void:
	first_person = not first_person
	_apply()


## The camera this rig shows when no stage shot has the view: FirstPerson or
## OverShoulder, by the toggle.
func current_base_camera() -> Camera3D:
	return (%FirstPerson if first_person else %OverShoulder) as Camera3D


func _stage_live() -> bool:
	var stage := get_node_or_null("StageCam")
	return stage != null and bool(stage.call("is_live"))


func _apply() -> void:
	# A stage shot keeps the view; it hands back to the base camera when it ends.
	if not _stage_live():
		# Current is handed over in one call, never through a frame with none.
		var want := current_base_camera()
		var other := (%OverShoulder if first_person else %FirstPerson) as Camera3D
		if _active:
			want.make_current()
		else:
			want.current = false
			other.current = false
	else:
		# The shot keeps playing, but only shows while the rig has the view: it
		# never takes it back from whatever was given it (the crossing camera).
		var stage := get_node("StageCam") as Camera3D
		if _active and not stage.current:
			stage.make_current()
		elif not _active:
			stage.current = false
	# Field of view is this machine's setting (core/settings.gd), for both views.
	%FirstPerson.fov = Settings.fov()
	%OverShoulder.fov = Settings.fov()


func _on_setting_changed(section: StringName, key: StringName, _value: Variant) -> void:
	if section == &"controls" and key == &"fov":
		_apply()
