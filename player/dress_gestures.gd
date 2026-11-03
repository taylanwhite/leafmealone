extends RefCounted

## Authority: local, cosmetic. Putting on something new (docs/GAME.md
## "Cosmetics"; gap-specs shops chunk 7), registered with player/cartoon_body.gd's
## register_gesture on first use. CartoonBody.rebuild plays one on every peer when
## a player's look changes:
##   hat_on     both hands come up to the head as the new hat drops (they meet
##              it as it lands, Constants.HAT_DROP_DELAY + HAT_DROP_SECONDS in),
##              give it a tug down with a little nod, and go back down
##   shirt_tug  the hands find the hem, tug the new shirt down twice with the
##              shoulders coming up, then brush it flat on the way back down
## Arms hang along -Y; a positive x turn swings an arm forward and up, a negative
## z turn brings the right arm in across the body (the left mirrors).

const _CartoonBody = preload("res://player/cartoon_body.gd")

const SECONDS: Dictionary = {
	"hat_on": Constants.HAT_ON_SECONDS,
	"shirt_tug": Constants.SHIRT_TUG_SECONDS,
}
## Both arms up beside the head, hands on the hat's brim over the ears (rad:
## forward-up, in; the arm is one piece, so it goes nearly straight up and a
## little out. W8: 2.75 forward and 0.38 in put both hands over the eyes).
const HAT_ARMS := Vector2(0.3, -2.8)
## The hands at the shirt's hem, and up on the chest for the brush (rad).
const HEM_ARMS := Vector2(0.42, 0.34)
const CHEST_ARMS := Vector2(1.05, 0.5)

static var _done: bool = false


static func register() -> void:
	if _done:
		return
	_done = true
	for gesture_name: String in SECONDS:
		_CartoonBody.register_gesture(gesture_name, float(SECONDS[gesture_name]), _pose.bind(gesture_name))


static func _pose(body: Node3D, t: float, _delta: float, gesture_name: String) -> void:
	var length := float(SECONDS[gesture_name])
	var s := t * length
	match gesture_name:
		"hat_on":
			_pose_hat_on(body, s, length)
		"shirt_tug":
			_pose_shirt_tug(body, s, length)


static func _ease(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _arms(body: Node3D, at: Vector2, amount: float) -> void:
	for side: int in 2:
		var arm := body.call("pose_part", "arm_r" if side == 1 else "arm_l") as Node3D
		if arm == null:
			continue
		var mirror := 1.0 if side == 1 else -1.0
		arm.rotation.x = lerpf(arm.rotation.x, at.x, amount)
		arm.rotation.z = lerpf(arm.rotation.z, -at.y * mirror, amount)


## How far into its pose a gesture is s seconds in (0 at rest, 1 there): the
## body's arms and your first-person ones (player/first_person_arms.gd) both
## follow it, so you and your crew see the same beat.
static func fp_amount(gesture_name: String, s: float) -> float:
	var length := float(SECONDS.get(gesture_name, 0.0))
	if gesture_name == "hat_on":
		var lands := Constants.HAT_DROP_DELAY + Constants.HAT_DROP_SECONDS
		return minf(_ease(s / maxf(lands, 0.01)), _ease((length - s) / maxf(length - lands - 0.2, 0.01)))
	if gesture_name == "shirt_tug":
		return minf(_ease(s / 0.18), _ease((length - s) / 0.22))
	return 0.0


## The tug in it (0..1): the hat pulled down once it lands, the hem twice.
static func fp_tug(gesture_name: String, s: float) -> float:
	if gesture_name == "hat_on":
		var lands := Constants.HAT_DROP_DELAY + Constants.HAT_DROP_SECONDS
		return sin((s - lands) / 0.2 * PI) if s > lands and s < lands + 0.2 else 0.0
	if gesture_name == "shirt_tug":
		return absf(sin((s - 0.18) / 0.28 * TAU)) if s > 0.18 and s < 0.46 else 0.0
	return 0.0


## The hands reach the brim just as the hat lands, tug, and drop.
static func _pose_hat_on(body: Node3D, s: float, _length: float) -> void:
	var amount := fp_amount("hat_on", s)
	# The tug: the hands pull the hat down a touch after it lands.
	var tug := fp_tug("hat_on", s)
	_arms(body, HAT_ARMS - Vector2(0.18 * tug, 0.0), amount)
	var face := body.call("pose_part", "face") as Node3D
	if face != null:
		# Chin down as the hands come up to it; a nod into the tug.
		face.rotation.x -= 0.12 * amount + 0.14 * tug
	var hips := body.call("pose_part", "hips") as Node3D
	if hips != null:
		hips.position.y -= 0.025 * tug


static func _pose_shirt_tug(body: Node3D, s: float, length: float) -> void:
	var to_hem := _ease(s / 0.18)
	var back := _ease((length - s) / 0.22)
	var tugs := fp_tug("shirt_tug", s)
	# The brush: from the hem up the chest and away.
	var brush := _ease((s - 0.46) / 0.16) if s > 0.46 else 0.0
	var at := HEM_ARMS.lerp(CHEST_ARMS, brush) - Vector2(0.14 * tugs, 0.0)
	_arms(body, at, minf(to_hem, back))
	var torso := body.call("pose_part", "torso") as Node3D
	if torso != null:
		# Shoulders up and chest out as each tug pulls the hem down.
		torso.rotation.x += 0.08 * tugs
	var face := body.call("pose_part", "face") as Node3D
	if face != null:
		# Looking down at the new shirt.
		face.rotation.x -= 0.32 * minf(to_hem, back)
