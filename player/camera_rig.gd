extends Node3D

## Authority: local presentation. The player script does not read which camera is active.
## OQ-001: first person and over-the-shoulder stay swappable until the camera is decided.

@export var first_person: bool = true

var _active: bool = false


func _ready() -> void:
	_apply()


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


## Swap between the two cameras. Bound to toggle_camera by the player.
func toggle() -> void:
	first_person = not first_person
	_apply()


func _apply() -> void:
	%FirstPerson.current = _active and first_person
	%OverShoulder.current = _active and not first_person
