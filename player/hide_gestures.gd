extends RefCounted

## Authority: local, cosmetic. The hiding gestures (R2 chunk 3), registered with
## player/cartoon_body.gd's register_gesture (R2 chunk 1) on first use, so
## gesture("hedge_dive") and the rest play on any CartoonBody: the hider's dive,
## vault, step, cannonball and burst out, and a NICE BOY's poke, lid peer, shed
## knock, pile pat, shrug and the "Upsy-daisy!" lift. Callers check has_gesture
## and fall back to an older gesture when one is missing.
##
## Each pose_fn(body, t01, delta) poses the parts body.pose_part(name) returns on
## top of the walk cycle: arms hang along -Y; a positive x turn swings an arm
## forward, a positive z turn lifts the right arm out sideways (the left one
## mirrors with negative z).

const _CartoonBody = preload("res://player/cartoon_body.gd")

## Seconds each one lasts: the length of the move or poke it plays over.
const SECONDS: Dictionary = {
	"hedge_dive": Constants.HIDE_ENTER_SECONDS, "bin_vault": Constants.HIDE_ENTER_SECONDS,
	"shed_step": Constants.HIDE_ENTER_SECONDS, "pile_cannonball": Constants.HIDE_ENTER_SECONDS,
	"burst_out": Constants.HIDE_EXIT_SECONDS + Constants.HIDE_EXIT_GESTURE_TAIL, "upsy_daisy_victim": Constants.HIDE_PULL_SECONDS + Constants.HIDE_PULL_GESTURE_TAIL,
	"inspect_poke": Constants.HIDE_INSPECT_SECONDS, "lid_peer": Constants.HIDE_INSPECT_SECONDS,
	"shed_knock": Constants.HIDE_INSPECT_SECONDS, "pile_pat": Constants.HIDE_INSPECT_SECONDS,
	"shrug_notice": Constants.HIDE_SHRUG_SECONDS, "upsy_daisy": Constants.HIDE_UPSY_DAISY_SECONDS,
}

static var _done: bool = false


static func register() -> void:
	if _done:
		return
	_done = true
	for gesture_name: String in SECONDS:
		_CartoonBody.register_gesture(gesture_name, float(SECONDS[gesture_name]), _pose.bind(gesture_name))


## One entry point for every pose here: the registry calls (body, t01, delta)
## with the gesture's name bound on the end.
static func _pose(body: Node3D, t: float, delta: float, gesture_name: String) -> void:
	match gesture_name:
		"hedge_dive":
			_HideGesturePoses.hedge_dive(body, t, delta)
		"bin_vault":
			_HideGesturePoses.bin_vault(body, t, delta)
		"shed_step":
			_HideGesturePoses.shed_step(body, t, delta)
		"pile_cannonball":
			_HideGesturePoses.pile_cannonball(body, t, delta)
		"burst_out":
			_HideGesturePoses.burst_out(body, t, delta)
		"upsy_daisy_victim":
			_HideGesturePoses.upsy_daisy_victim(body, t, delta)
		"inspect_poke":
			_HideGesturePoses.inspect_poke(body, t, delta)
		"lid_peer":
			_HideGesturePoses.lid_peer(body, t, delta)
		"shed_knock":
			_HideGesturePoses.shed_knock(body, t, delta)
		"pile_pat":
			_HideGesturePoses.pile_pat(body, t, delta)
		"shrug_notice":
			_HideGesturePoses.shrug_notice(body, t, delta)
		"upsy_daisy":
			_HideGesturePoses.upsy_daisy(body, t, delta)


## The poses, one static function per gesture.
class _HideGesturePoses:
	static func _part(body: Node3D, part: String) -> Node3D:
		return body.call("pose_part", part) as Node3D

	static func _ease(t: float) -> float:
		return t * t * (3.0 - 2.0 * t)

	## In and out of a pose over the gesture: up fast, down at the end.
	static func _fade(t: float) -> float:
		return clampf(minf(t * 6.0, (1.0 - t) * 6.0), 0.0, 1.0)

	## A dive over a hedge: a quick crouch, then both arms thrown forward over the
	## head, leaning into it, legs piked up under you to clear the top.
	static func hedge_dive(body: Node3D, t: float, _delta: float) -> void:
		var crouch := clampf(1.0 - t / 0.2, 0.0, 1.0)
		var reach := _ease(clampf((t - 0.08) / 0.3, 0.0, 1.0))
		var tuck := sin(clampf((t - 0.12) / 0.75, 0.0, 1.0) * PI)
		var fade := _fade(t)
		for side: String in ["arm_r", "arm_l"]:
			var arm := _part(body, side)
			if arm != null:
				arm.rotation.x = lerpf(arm.rotation.x, lerpf(0.3, 2.7, reach), fade)
				arm.rotation.z = lerpf(arm.rotation.z, (0.15 if side == "arm_r" else -0.15), fade)
		var torso := _part(body, "torso")
		if torso != null:
			torso.rotation.x = lerpf(torso.rotation.x, -0.3 * crouch - 0.55 * reach, fade)
		var hips := _part(body, "hips")
		if hips != null:
			hips.position.y -= 0.16 * crouch * fade
		for side: String in ["leg_r", "leg_l"]:
			var leg := _part(body, side)
			if leg != null:
				leg.rotation.x = lerpf(leg.rotation.x, 1.35 * tuck - 0.4 * crouch, fade)

	## Vault into a bin: both hands on the rim, legs swung up and over.
	static func bin_vault(body: Node3D, t: float, _delta: float) -> void:
		var fade := _fade(t)
		var swing := sin(clampf(t / 0.8, 0.0, 1.0) * PI)
		for side: String in ["arm_r", "arm_l"]:
			var arm := _part(body, side)
			if arm != null:
				arm.rotation.x = lerpf(arm.rotation.x, 1.1, fade)
		for side: String in ["leg_r", "leg_l"]:
			var leg := _part(body, side)
			if leg != null:
				leg.rotation.x = lerpf(leg.rotation.x, 1.4 * swing, fade)
		var torso := _part(body, "torso")
		if torso != null:
			torso.rotation.x = lerpf(torso.rotation.x, -0.4 * swing, fade)

	## Into the shed: a quick hunched tiptoe, arms tucked.
	static func shed_step(body: Node3D, t: float, _delta: float) -> void:
		var fade := _fade(t)
		var torso := _part(body, "torso")
		if torso != null:
			torso.rotation.x = lerpf(torso.rotation.x, -0.35, fade)
		for side: String in ["arm_r", "arm_l"]:
			var arm := _part(body, side)
			if arm != null:
				arm.rotation.x = lerpf(arm.rotation.x, 0.7, fade)
		for index: int in 2:
			var leg := _part(body, "leg_r" if index == 0 else "leg_l")
			if leg != null:
				leg.rotation.x = lerpf(leg.rotation.x, 0.5 * sin(t * 30.0 + float(index) * PI), fade)

	## Cannonball: knees hugged to the chest, in the air.
	static func pile_cannonball(body: Node3D, t: float, _delta: float) -> void:
		var tuck := _ease(clampf((t - 0.1) / 0.3, 0.0, 1.0)) * _fade(t)
		for side: String in ["leg_r", "leg_l"]:
			var leg := _part(body, side)
			if leg != null:
				leg.rotation.x = lerpf(leg.rotation.x, 1.9, tuck)
		for side: String in ["arm_r", "arm_l"]:
			var arm := _part(body, side)
			if arm != null:
				arm.rotation.x = lerpf(arm.rotation.x, 1.2, tuck)
		var torso := _part(body, "torso")
		if torso != null:
			torso.rotation.x = lerpf(torso.rotation.x, -0.5, tuck)

	## Bursting out (R2b hide): a quick tuck, then both arms flung straight up in
	## a "ta-da!" for the whole hop (up in two frames, never passing through a
	## T), knees up; on landing they flop down past the sides and settle. The
	## gesture runs BURST_SECONDS, longer than the climb-out, so the follow-through
	## plays on your feet.
	static func burst_out(body: Node3D, t: float, _delta: float) -> void:
		var seconds := float(SECONDS["burst_out"])
		var s := t * seconds
		var climb := Constants.HIDE_EXIT_SECONDS
		var tuck := 1.0 - _ease(clampf(s / 0.06, 0.0, 1.0))
		var fling := _ease(clampf((s - 0.02) / 0.07, 0.0, 1.0))
		# Down from just after landing, overshooting a little past the hips.
		var drop := clampf((s - climb - 0.05) / 0.3, 0.0, 1.0)
		var flop := _ease(drop) + 0.18 * sin(drop * PI) * (1.0 - drop)
		var arm_z := lerpf(-0.15 * tuck + 2.95 * fling, 0.12, clampf(flop, 0.0, 1.2))
		var wiggle := 0.12 * sin(s * 31.0) * fling * (1.0 - drop)
		var fade := clampf(minf(s / 0.03, (seconds - s) / 0.12), 0.0, 1.0)
		var right := _part(body, "arm_r")
		var left := _part(body, "arm_l")
		if right != null:
			right.rotation.z = lerpf(right.rotation.z, arm_z + wiggle, fade)
			right.rotation.x = lerpf(right.rotation.x, 0.25 * fling * (1.0 - drop), fade)
		if left != null:
			left.rotation.z = lerpf(left.rotation.z, -arm_z + wiggle, fade)
			left.rotation.x = lerpf(left.rotation.x, 0.25 * fling * (1.0 - drop), fade)
		var hop := sin(clampf(s / climb, 0.0, 1.0) * PI)
		for index: int in 2:
			var leg := _part(body, "leg_r" if index == 0 else "leg_l")
			if leg != null:
				leg.rotation.x = lerpf(leg.rotation.x, (1.1 if index == 0 else 0.6) * hop, fade)
		var torso := _part(body, "torso")
		if torso != null:
			# A little stretch back at the top of it.
			torso.rotation.x = lerpf(torso.rotation.x, 0.12 * fling * (1.0 - drop) - 0.2 * tuck, fade)

	## Lifted out by the collar: legs kicking, arms up.
	static func upsy_daisy_victim(body: Node3D, t: float, _delta: float) -> void:
		var fade := _fade(t)
		for index: int in 2:
			var leg := _part(body, "leg_r" if index == 0 else "leg_l")
			if leg != null:
				leg.rotation.x = 0.7 * sin(t * 28.0 + float(index) * PI) * fade
		var right := _part(body, "arm_r")
		var left := _part(body, "arm_l")
		if right != null:
			right.rotation.z = lerpf(right.rotation.z, 2.0, fade)
		if left != null:
			left.rotation.z = lerpf(left.rotation.z, -2.0, fade)

	## A NICE BOY parts the hedge with his clipboard: lean in, the board arm
	## pushing forward and back twice, the other hand cupped to the brim.
	static func inspect_poke(body: Node3D, t: float, _delta: float) -> void:
		var fade := _fade(t)
		var push := 0.5 + 0.5 * sin(t * TAU * 2.0 - PI * 0.5)
		var board := _part(body, "arm_l")
		if board != null:
			board.rotation.x = lerpf(board.rotation.x, 0.9 + 0.6 * push, fade)
		var right := _part(body, "arm_r")
		if right != null:
			right.rotation.x = lerpf(right.rotation.x, 2.4, fade)
			right.rotation.z = lerpf(right.rotation.z, 0.6, fade)
		var torso := _part(body, "torso")
		if torso != null:
			torso.rotation.x = lerpf(torso.rotation.x, -0.35 - 0.15 * push, fade)

	## Lifting a bin lid a crack and peering in: one hand up under the lid, bent
	## right over, still.
	static func lid_peer(body: Node3D, t: float, _delta: float) -> void:
		var fade := _fade(t)
		var right := _part(body, "arm_r")
		if right != null:
			right.rotation.x = lerpf(right.rotation.x, 1.9, fade)
		var torso := _part(body, "torso")
		if torso != null:
			torso.rotation.x = lerpf(torso.rotation.x, -0.55, fade)
		var face := _part(body, "face")
		if face != null:
			face.rotation.x -= 0.2 * fade

	## Knock, knock, knock on the shed: the right fist rapping, head tilted to listen.
	static func shed_knock(body: Node3D, t: float, _delta: float) -> void:
		var fade := _fade(t)
		var right := _part(body, "arm_r")
		if right != null:
			var rap := absf(sin(clampf((t * 2.0 - 0.25) / 0.9, 0.0, 1.0) * PI * 3.0))
			right.rotation.x = lerpf(right.rotation.x, 1.3 + 0.35 * rap, fade)
			right.rotation.z = lerpf(right.rotation.z, 0.25, fade)
		var face := _part(body, "face")
		if face != null:
			face.rotation.z += 0.2 * fade

	## Patting the pile: crouched, both hands flat, patting in turn.
	static func pile_pat(body: Node3D, t: float, _delta: float) -> void:
		var fade := _fade(t)
		var hips := _part(body, "hips")
		if hips != null:
			hips.position.y -= 0.3 * fade
		var torso := _part(body, "torso")
		if torso != null:
			torso.rotation.x = lerpf(torso.rotation.x, -0.7, fade)
		for index: int in 2:
			var arm := _part(body, "arm_r" if index == 0 else "arm_l")
			if arm != null:
				arm.rotation.x = lerpf(arm.rotation.x, 1.2 + 0.3 * absf(sin(t * 18.0 + float(index) * PI * 0.5)), fade)
		for side: String in ["leg_r", "leg_l"]:
			var leg := _part(body, side)
			if leg != null:
				leg.rotation.x = lerpf(leg.rotation.x, -0.9, fade)

	## Nothing there: palms up, shoulders up, a little head shake.
	static func shrug_notice(body: Node3D, t: float, _delta: float) -> void:
		var fade := _fade(t)
		var right := _part(body, "arm_r")
		var left := _part(body, "arm_l")
		if right != null:
			right.rotation.z = lerpf(right.rotation.z, 0.9, fade)
			right.rotation.x = lerpf(right.rotation.x, 0.6, fade)
		if left != null:
			left.rotation.z = lerpf(left.rotation.z, -0.9, fade)
			left.rotation.x = lerpf(left.rotation.x, 0.6, fade)
		var face := _part(body, "face")
		if face != null:
			face.rotation.y += 0.25 * sin(t * 18.0) * fade

	## Found you: both arms reach forward and haul up.
	static func upsy_daisy(body: Node3D, t: float, _delta: float) -> void:
		var fade := _fade(t)
		var haul := _ease(clampf((t - 0.2) / 0.5, 0.0, 1.0))
		for side: String in ["arm_r", "arm_l"]:
			var arm := _part(body, side)
			if arm != null:
				arm.rotation.x = lerpf(arm.rotation.x, lerpf(1.3, 2.3, haul), fade)
		var torso := _part(body, "torso")
		if torso != null:
			torso.rotation.x = lerpf(torso.rotation.x, lerpf(-0.45, 0.1, haul), fade)
