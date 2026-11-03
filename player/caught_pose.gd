extends Node

## Authority: local, cosmetic (every peer runs its own, from the catch's RPCs).
## R2b: how a caught player's body takes it (docs/GAME.md "The catch, staged
## (R2b)"; R2c: "the caught body acts"). net/run_events/encounter.gd adds one
## under the caught player's CartoonBody on every peer at the gotcha and lets it
## go at the van door or when they're freed. It runs right after the body each
## physics tick (a child ticks after its parent), so it wins where it says so,
## blended in and out; the face and the eyes are set every frame, after the
## body's own CharacterLife has picked where to look.
##   held      never one pose (R2c: the audit saw one stiff arms-forward pose for
##             the whole 2.5 s two-shot): hands half up, palms out, shoulders up,
##             a tremble you can see from 3 m, and every second or so a squirm
##             (a twist against his grip, an arm yanked back, a knee up, a dip),
##             between which the eyes and face go to him, now and then to the
##             camera ("are you seeing this?"). react() is his bark landing: a
##             recoil, a blink, brows up. flinch() jerks it (the grab, the
##             sticker: a look down at your own chest), wriggle() is each jump
##             during the cite (a bigger squirm).
##   escorted  your arm hooked through his on your left, leaning back from the
##             stroll, dragging a step now and then, looking back over your
##             shoulder at the yard.
## A hit-stop (CartoonBody.set_anim_speed 0) holds it still with the body.
## Every beat is timed from this node's own clock, so peers drift a little, but
## nothing in it is game state.

const BLEND_SECONDS: float = 0.15
const FLINCH_SECONDS: float = 0.34
const TWIST_SECONDS: float = 0.55
const REACT_SECONDS: float = 0.6
## How far the shoulders come up (m).
const SHRUG: float = 0.045
## How much of the turn to him the face makes (the eyes make all of it).
const FACE_AT_CAPTOR: float = 0.35

var _body: Node3D
var _mode: StringName = &"held"
var _weight: float = 0.0
var _target: float = 1.0
var _time: float = 0.0
var _flinch_t: float = 10.0
var _flinch_down: bool = false
var _twist_t: float = 10.0
var _twist_big: float = 1.0
var _react_t: float = 10.0
var _leaving: bool = false
## The arms' pivots at rest (the shrug moves them), restored on the way out.
var _arm_rest: Array[Vector3] = []
## Who has hold of you (his head is what you look at) and where the two-shot
## films from (a glance to it now and then), INF when nobody films.
var captor: Node3D
var camera_point := Vector3.INF
## The squirms: when the next one starts, how long each lasts, which way it
## twists, and how many have gone (every third one looks to the camera).
var _next_squirm: float = 0.45
var _squirm_t: float = 10.0
var _squirm_side: float = 1.0
var _squirms: int = 0
var _rng := RandomNumberGenerator.new()
var _at_captor: bool = false


func _ready() -> void:
	_body = get_parent() as Node3D
	# Varied per body, not per frame: two caught players don't squirm in step.
	_rng.seed = hash(str(get_path()))


## The jolt: the grab landing, a bonk. down: the sticker slapped on your chest
## (you look down at it).
func flinch(down: bool = false) -> void:
	_flinch_t = 0.0
	_flinch_down = down


## A twist against his grip (a wriggle during the cite): a big squirm now.
func wriggle() -> void:
	_twist_t = 0.0
	_twist_big = 1.0
	_squirm_side = -_squirm_side


## His bark lands: recoil from the megaphone, blink, brows up.
func react() -> void:
	_react_t = 0.0


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


## Where to look this frame, after the body's own CharacterLife chose (it runs
## first: it is the older child).
func _process(_delta: float) -> void:
	if _body == null or _weight <= 0.01 or not _body.is_visible_in_tree():
		return
	var look := _look_point()
	if not look.is_finite():
		return
	_body.set("look_at_point", look)
	var to := look - _body.global_position
	var local := _body.global_basis.inverse() * to
	var angle := clampf(atan2(-local.x, -local.z), -1.0, 1.0)
	# At him it's a side-eye (the stage cheat keeps your face to the camera);
	# anything else gets the whole face.
	_body.set("face_turn", angle * _weight * (FACE_AT_CAPTOR if _at_captor else 1.0))


## His face, the camera for a moment after every third squirm, your own chest
## while the sticker lands, the yard behind you on the walk.
func _look_point() -> Vector3:
	_at_captor = false
	if _flinch_down and _flinch_t < FLINCH_SECONDS + 0.5:
		return _body.global_position + _body.global_basis * Vector3(0.0, 0.6, -0.5)
	if _mode == &"escorted":
		if fmod(_time, 2.6) > 1.9:
			# A look back over your shoulder at the yard you were working.
			return _body.global_position + _body.global_basis * Vector3(1.6, 1.4, 2.0)
	elif camera_point.is_finite() and _squirms % 3 == 2 and _squirm_t > 0.25 and _squirm_t < 1.05:
		return camera_point
	if captor != null and is_instance_valid(captor) and captor.is_inside_tree():
		_at_captor = true
		return captor.global_position + Vector3(0.0, 1.55, 0.0)
	return Vector3.INF


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
	var leg_l := _body.call("pose_part", "leg_l") as Node3D
	var leg_r := _body.call("pose_part", "leg_r") as Node3D
	if left == null or right == null or torso == null or hips == null:
		return
	if _arm_rest.is_empty():
		_arm_rest = [left.position, right.position]
	_time += delta
	_flinch_t += delta
	_twist_t += delta
	_react_t += delta
	_squirm_t += delta
	_weight = move_toward(_weight, _target, delta / BLEND_SECONDS)
	var w := _weight
	_body.set("mood", "worried")
	var shrug := 0.0
	if _mode == &"held":
		shrug = _held(delta, w, left, right, torso, hips, leg_l, leg_r)
	else:
		shrug = _escorted(w, left, right, torso, hips)
	if _flinch_t < FLINCH_SECONDS:
		var jolt := sin(_flinch_t / FLINCH_SECONDS * PI) * w
		hips.position.y -= 0.08 * jolt
		torso.rotation.x += (0.32 if _flinch_down else 0.2) * jolt
		left.rotation.x += 0.55 * jolt
		right.rotation.x += 0.55 * jolt
		left.rotation.z -= 0.25 * jolt
		right.rotation.z += 0.25 * jolt
		shrug += 0.04 * jolt
	if _react_t < REACT_SECONDS:
		# Leaning away from the megaphone, eyes squeezed for a moment.
		var recoil := sin(clampf(_react_t / REACT_SECONDS, 0.0, 1.0) * PI) * w
		torso.rotation.x -= 0.22 * recoil
		hips.position.y -= 0.03 * recoil
		shrug += 0.03 * recoil
		if _react_t < 0.05:
			_body.call("gesture", "startle")
	left.position = _arm_rest[0] + Vector3.UP * shrug
	right.position = _arm_rest[1] + Vector3.UP * shrug
	if _twist_t < TWIST_SECONDS:
		# A wriggle (a jump press): a big shake against his grip, three twists.
		var fade := 1.0 - _twist_t / TWIST_SECONDS
		torso.rotation.y = 0.5 * _twist_big * sin(_twist_t * 22.0) * fade * w
		hips.position.y -= 0.05 * absf(sin(_twist_t * 11.0)) * fade * w
	if _leaving and _weight <= 0.0:
		left.position = _arm_rest[0]
		right.position = _arm_rest[1]
		torso.rotation.y = 0.0
		torso.rotation.z = 0.0
		queue_free()


## Held: half-raised hands, a visible tremble, and a squirm every second or so.
## Returns the shrug (m).
func _held(_delta: float, w: float, left: Node3D, right: Node3D, torso: Node3D, hips: Node3D, leg_l: Node3D, leg_r: Node3D) -> float:
	if _time >= _next_squirm and _squirm_t > 0.6:
		_squirm_t = 0.0
		_squirms += 1
		_squirm_side = -_squirm_side if _rng.randf() < 0.7 else _squirm_side
		_next_squirm = _time + _rng.randf_range(0.85, 1.35)
	# Breathing fast, a tremble that reads at the two-shot's 3 m.
	var tremble := 0.09 * sin(_time * 17.0) + 0.04 * sin(_time * 29.0)
	var pant := 0.5 + 0.5 * sin(_time * 7.5)
	# The squirm: 0 -> 1 -> 0 over 0.6 s, eased, with a little overshoot back.
	var s := 0.0
	if _squirm_t < 0.6:
		var u := _squirm_t / 0.6
		s = sin(u * PI) * (1.0 - 0.3 * u)
	var side := _squirm_side
	# Hands half up, palms out ("whoa, whoa"); on a squirm one arm yanks back
	# against his grip, the other flaps out.
	var yank_l := s if side > 0.0 else 0.0
	var yank_r := s if side < 0.0 else 0.0
	left.rotation.x = lerpf(left.rotation.x, 0.95 + tremble - 1.1 * yank_l + 0.35 * yank_r, w)
	left.rotation.z = lerpf(left.rotation.z, -0.55 - 0.5 * yank_l - 0.25 * yank_r, w)
	right.rotation.x = lerpf(right.rotation.x, 0.95 - tremble - 1.1 * yank_r + 0.35 * yank_l, w)
	right.rotation.z = lerpf(right.rotation.z, 0.55 + 0.5 * yank_r + 0.25 * yank_l, w)
	# Leaning back from him, twisting away on the squirm, the hips swinging.
	torso.rotation.x = lerpf(torso.rotation.x, 0.12 + 0.03 * pant, w)
	torso.rotation.y = lerpf(torso.rotation.y, 0.45 * side * s, w)
	torso.rotation.z = lerpf(torso.rotation.z, -0.14 * side * s, w)
	hips.position.y -= (0.03 + 0.06 * s) * w
	# A knee comes up on the squirm (a little kick), the other leg braced.
	if leg_l != null and leg_r != null:
		var kick := leg_l if side > 0.0 else leg_r
		var brace := leg_r if side > 0.0 else leg_l
		kick.rotation.x = lerpf(kick.rotation.x, 0.55 * s, w)
		brace.rotation.x = lerpf(brace.rotation.x, -0.12 * s, w)
	return (SHRUG + 0.012 * pant) * w


## Escorted: arm hooked through his, leaning back, a reluctant drag every so often.
func _escorted(w: float, left: Node3D, right: Node3D, torso: Node3D, _hips: Node3D) -> float:
	var drag := maxf(0.0, sin(_time * 2.4)) * 0.5
	left.rotation.x = lerpf(left.rotation.x, 0.3, w)
	left.rotation.z = lerpf(left.rotation.z, -0.5, w)
	right.rotation.x = lerpf(right.rotation.x, 0.15 * sin(_time * 5.0) - 0.2 * drag, w)
	right.rotation.z = lerpf(right.rotation.z, 0.2 + 0.15 * drag, w)
	torso.rotation.x = lerpf(torso.rotation.x, 0.14 + 0.1 * drag, w)
	torso.rotation.z = lerpf(torso.rotation.z, 0.06 * sin(_time * 2.4), w)
	if _twist_t >= TWIST_SECONDS:
		torso.rotation.y = lerpf(torso.rotation.y, 0.0, w)
	return SHRUG * 0.4 * w
