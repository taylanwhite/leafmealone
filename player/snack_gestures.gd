extends RefCounted

## Authority: local, cosmetic. The snack gestures (docs/GAME.md "Shops", Lunch
## Money and the Snak-o-Matic; gap shops chunk 6), registered with
## player/cartoon_body.gd's register_gesture on first use, so gesture("eat") and
## the rest play on any CartoonBody:
##   eat          the food comes up to the mouth and gets three bites (the
##                bites land at Constants.SNACK_EAT_BITES: the head nods into
##                each one; player/snack_eater.gd plays the munch and shrinks the
##                food on the same clock), then the hand goes back down
##   drink        the cup or can comes up, tips, the head goes back for the sip
##                (Constants.SNACK_DRINK_SIP), and comes down with a satisfied lean
##   belly_pat    full: two pats on the belly, chest out
##   turbo_shake  Turbo Juice kicking in: a full-body shudder, fists up
##   burp         queasy: the chest heaves, the head rocks back and forward
##
## Each pose_fn(body, t01, delta) poses body.pose_part(name) on top of the walk
## cycle: arms hang along -Y; a positive x turn swings an arm forward, a negative
## z turn brings the right arm in across the body (the left one mirrors).

const _CartoonBody = preload("res://player/cartoon_body.gd")

## Seconds each one lasts.
const SECONDS: Dictionary = {
	"eat": Constants.SNACK_EAT_SECONDS,
	"drink": Constants.SNACK_DRINK_SECONDS,
	"belly_pat": 1.1,
	"turbo_shake": 0.7,
	"burp": 0.8,
}
## The right arm with the food at the mouth: forward and in (rad), worked out
## from the cartoon body's shoulder (0.25 out, 0.46 over the hips) and its arm's
## length (0.55), so the hand ends just in front of the mouth.
const MOUTH_ARM := Vector2(2.2, -0.62)
## How long the hand takes to come up, and to go back down (s).
const RAISE_SECONDS: float = 0.42
const LOWER_SECONDS: float = 0.45

static var _done: bool = false


static func register() -> void:
	if _done:
		return
	_done = true
	for gesture_name: String in SECONDS:
		_CartoonBody.register_gesture(gesture_name, float(SECONDS[gesture_name]), _pose.bind(gesture_name))


static func _pose(body: Node3D, t: float, delta: float, gesture_name: String) -> void:
	match gesture_name:
		"eat":
			_pose_eat(body, t, delta)
		"drink":
			_pose_drink(body, t, delta)
		"belly_pat":
			_pose_belly_pat(body, t, delta)
		"turbo_shake":
			_pose_turbo_shake(body, t, delta)
		"burp":
			_pose_burp(body, t, delta)


## How far the hand is up at the mouth (0 down at the side, 1 at the mouth), s
## seconds into a gesture lasting length: up with a little overshoot, held, down.
## snack_eater.gd and the first-person arms read the same curve.
static func lift(s: float, length: float) -> float:
	var up := clampf(s / RAISE_SECONDS, 0.0, 1.0)
	var down := clampf((length - s) / LOWER_SECONDS, 0.0, 1.0)
	var rise := up * up * (3.0 - 2.0 * up) + 0.08 * sin(up * PI)
	return minf(rise, down * down * (3.0 - 2.0 * down))


## How far into a bite's nod the head is at s (0 none, 1 right into the food):
## a quick lean in that lands on the bite, and an easier way back.
static func bite_nod(s: float) -> float:
	var nod := 0.0
	for bite: float in Constants.SNACK_EAT_BITES:
		var into := s - (bite - 0.12)
		if into >= 0.0 and into < 0.12:
			nod = maxf(nod, into / 0.12)
		elif into >= 0.12 and into < 0.4:
			nod = maxf(nod, 1.0 - (into - 0.12) / 0.28)
	return nod


## How far the drink is tipped, 0 upright to 1 tipped to the lips.
static func sip_tip(s: float) -> float:
	var sip := Constants.SNACK_DRINK_SIP
	var into := clampf((s - sip.x + 0.15) / 0.2, 0.0, 1.0)
	var out := clampf((sip.y + 0.1 - s) / 0.2, 0.0, 1.0)
	return minf(into * into * (3.0 - 2.0 * into), out)


# ---- the poses

static func _part(body: Node3D, part: String) -> Node3D:
	return body.call("pose_part", part) as Node3D

static func _ease(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)

## The right arm up to the mouth by share up (0..1).
static func _pose_arm_to_mouth(body: Node3D, up: float) -> void:
	var right := _part(body, "arm_r")
	if right != null:
		right.rotation.x = lerpf(right.rotation.x, MOUTH_ARM.x, up)
		right.rotation.z = lerpf(right.rotation.z, MOUTH_ARM.y, up)

static func _pose_eat(body: Node3D, t: float, _delta: float) -> void:
	var length := float(SECONDS["eat"])
	var s := t * length
	var up := lift(s, length)
	_pose_arm_to_mouth(body, up)
	var nod := bite_nod(s) * up
	var face := _part(body, "face")
	if face != null:
		face.rotation.x -= 0.2 * nod
	var torso := _part(body, "torso")
	if torso != null:
		torso.rotation.x -= 0.06 * nod
	# The other hand comes up a little under it, in case of crumbs.
	var left := _part(body, "arm_l")
	if left != null:
		left.rotation.x = lerpf(left.rotation.x, 0.7, up * 0.8)
		left.rotation.z = lerpf(left.rotation.z, 0.3, up * 0.8)

static func _pose_drink(body: Node3D, t: float, _delta: float) -> void:
	var length := float(SECONDS["drink"])
	var s := t * length
	var up := lift(s, length)
	var tip := sip_tip(s)
	var right := _part(body, "arm_r")
	if right != null:
		# Tipping it up lifts the elbow: the arm swings higher through the sip.
		right.rotation.x = lerpf(right.rotation.x, MOUTH_ARM.x + 0.3 * tip, up)
		right.rotation.z = lerpf(right.rotation.z, MOUTH_ARM.y, up)
	var face := _part(body, "face")
	if face != null:
		face.rotation.x += 0.38 * tip
	var torso := _part(body, "torso")
	if torso != null:
		torso.rotation.x += 0.1 * tip
	# After the sip: "ahh", shoulders drop, a little lean back.
	var after := clampf((s - Constants.SNACK_DRINK_SIP.y) / 0.5, 0.0, 1.0)
	if torso != null and after > 0.0:
		torso.rotation.x += 0.08 * sin(after * PI)

static func _pose_belly_pat(body: Node3D, t: float, _delta: float) -> void:
	var fade := clampf(minf(t * 5.0, (1.0 - t) * 5.0), 0.0, 1.0)
	var pat := absf(sin(clampf((t - 0.15) / 0.75, 0.0, 1.0) * PI * 2.0))
	for index: int in 2:
		var arm := _part(body, "arm_r" if index == 0 else "arm_l")
		if arm != null:
			arm.rotation.x = lerpf(arm.rotation.x, 0.75 + 0.2 * pat, fade)
			arm.rotation.z = lerpf(arm.rotation.z, (-0.55 if index == 0 else 0.55), fade)
	var torso := _part(body, "torso")
	if torso != null:
		torso.rotation.x = lerpf(torso.rotation.x, 0.14, fade)

static func _pose_turbo_shake(body: Node3D, t: float, _delta: float) -> void:
	var fade := clampf(minf(t * 8.0, (1.0 - t) * 4.0), 0.0, 1.0)
	var buzz := sin(t * 95.0)
	var torso := _part(body, "torso")
	if torso != null:
		torso.rotation.z += 0.07 * buzz * fade
	var face := _part(body, "face")
	if face != null:
		face.rotation.y += 0.12 * buzz * fade
	for index: int in 2:
		var arm := _part(body, "arm_r" if index == 0 else "arm_l")
		if arm != null:
			# Fists up by the shoulders: "LET'S GO".
			arm.rotation.x = lerpf(arm.rotation.x, 1.2, fade)
			arm.rotation.z = lerpf(arm.rotation.z, (0.9 if index == 0 else -0.9) + 0.1 * buzz, fade)

static func _pose_burp(body: Node3D, t: float, _delta: float) -> void:
	var heave := sin(clampf(t / 0.45, 0.0, 1.0) * PI)
	var settle := clampf((t - 0.45) / 0.55, 0.0, 1.0)
	var torso := _part(body, "torso")
	if torso != null:
		torso.rotation.x += 0.16 * heave - 0.08 * sin(settle * PI)
		torso.scale.z *= 1.0 + 0.08 * heave
	var face := _part(body, "face")
	if face != null:
		face.rotation.x += 0.22 * heave - 0.12 * sin(settle * PI)
	var right := _part(body, "arm_r")
	if right != null:
		# A fist to the chest after it.
		var fist := sin(settle * PI)
		right.rotation.x = lerpf(right.rotation.x, 1.0, fist)
		right.rotation.z = lerpf(right.rotation.z, -0.7, fist)
