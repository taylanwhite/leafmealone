extends Node

## Authority: local, cosmetic (every peer runs its own, from the catch's RPCs).
## R2b: how a caught player's body takes it (docs/GAME.md "The catch, staged
## (R2b)"). net/run_events/encounter.gd adds one under the caught player's
## CartoonBody on every peer at the gotcha and lets it go at the van door or when
## they're freed. It runs right after the body each physics tick (a child ticks
## after its parent), so it wins where it says so, blended in and out:
##   held      shoulders up, both hands half raised ("whoa, whoa"), a small
##             tremble, leaning back from him; flinch() jerks it (the grab, a
##             bonk), wriggle() twists the shoulders (each jump during the cite)
##   escorted  your arm hooked through his on your left, leaning back from the
##             stroll, the other arm hanging
## A hit-stop (CartoonBody.set_anim_speed 0) holds it still with the body.

const BLEND_SECONDS: float = 0.15
const FLINCH_SECONDS: float = 0.3
const TWIST_SECONDS: float = 0.45
## How far the shoulders come up (m).
const SHRUG: float = 0.035

var _body: Node3D
var _mode: StringName = &"held"
var _weight: float = 0.0
var _target: float = 1.0
var _time: float = 0.0
var _flinch_t: float = 10.0
var _twist_t: float = 10.0
var _leaving: bool = false
## The arms' pivots at rest (the shrug moves them), restored on the way out.
var _arm_rest: Array[Vector3] = []


func _ready() -> void:
	_body = get_parent() as Node3D


## The jolt: the grab landing, a bonk.
func flinch() -> void:
	_flinch_t = 0.0


## A twist against his grip (a wriggle during the cite).
func wriggle() -> void:
	_twist_t = 0.0


func set_mode(mode: StringName) -> void:
	_mode = mode


func mode() -> StringName:
	return _mode


## Ease out and go.
func release() -> void:
	_target = 0.0
	_leaving = true


func _exit_tree() -> void:
	if _body == null or _arm_rest.is_empty() or not _body.has_method("pose_part"):
		return
	var left := _body.call("pose_part", "arm_l") as Node3D
	var right := _body.call("pose_part", "arm_r") as Node3D
	if left != null and right != null:
		left.position = _arm_rest[0]
		right.position = _arm_rest[1]


func _physics_process(delta: float) -> void:
	if _body == null or not _body.has_method("pose_part"):
		return
	if _body.has_method("anim_speed"):
		var scale_by := float(_body.call("anim_speed"))
		if scale_by <= 0.0:
			return
		delta *= scale_by
	var left := _body.call("pose_part", "arm_l") as Node3D
	var right := _body.call("pose_part", "arm_r") as Node3D
	var torso := _body.call("pose_part", "torso") as Node3D
	var hips := _body.call("pose_part", "hips") as Node3D
	if left == null or right == null or torso == null or hips == null:
		return
	if _arm_rest.is_empty():
		_arm_rest = [left.position, right.position]
	_time += delta
	_flinch_t += delta
	_twist_t += delta
	_weight = move_toward(_weight, _target, delta / BLEND_SECONDS)
	var w := _weight
	if _mode == &"held":
		var tremble := 0.035 * sin(_time * 19.0)
		left.rotation.x = lerpf(left.rotation.x, 1.2 + tremble, w)
		left.rotation.z = lerpf(left.rotation.z, -0.62, w)
		right.rotation.x = lerpf(right.rotation.x, 1.2 - tremble, w)
		right.rotation.z = lerpf(right.rotation.z, 0.62, w)
		torso.rotation.x = lerpf(torso.rotation.x, 0.1, w)
		hips.position.y -= 0.03 * w
	else:
		# His arm is on your left: yours hooks out to it; the right hangs, limp.
		left.rotation.x = lerpf(left.rotation.x, 0.3, w)
		left.rotation.z = lerpf(left.rotation.z, -0.5, w)
		right.rotation.x = lerpf(right.rotation.x, 0.1 * sin(_time * 5.0), w)
		torso.rotation.x = lerpf(torso.rotation.x, 0.14, w)
	var shrug := SHRUG * w if _mode == &"held" else SHRUG * 0.4 * w
	if _flinch_t < FLINCH_SECONDS:
		var jolt := sin(_flinch_t / FLINCH_SECONDS * PI) * w
		hips.position.y -= 0.06 * jolt
		torso.rotation.x += 0.16 * jolt
		left.rotation.x += 0.45 * jolt
		right.rotation.x += 0.45 * jolt
		shrug += 0.03 * jolt
	left.position = _arm_rest[0] + Vector3.UP * shrug
	right.position = _arm_rest[1] + Vector3.UP * shrug
	if _twist_t < TWIST_SECONDS:
		torso.rotation.y = 0.32 * sin(_twist_t * 26.0) * (1.0 - _twist_t / TWIST_SECONDS) * w
	elif _twist_t < TWIST_SECONDS + 0.1:
		torso.rotation.y = 0.0
	if _leaving and _weight <= 0.0:
		left.position = _arm_rest[0]
		right.position = _arm_rest[1]
		queue_free()
