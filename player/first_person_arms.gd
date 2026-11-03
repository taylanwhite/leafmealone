extends Node3D

## Authority: local presentation. Your own arms in first person: two cartoon
## arms hanging under the camera that reach for whatever you hold, swing the
## rake, pump along as you walk, wind up over your shoulder for a throw (and
## tremble when you strain), go hand over hand up a ladder, flop when you're
## knocked out, and get dragged around by a hydrant hose. Taylan, 2026-10-21:
## the camera is first person and you should see your hands move (OQ-001).
##
## Built only for the local player's own body, as a child of their Head, so the
## arms pitch with the view. Each arm is two bones solved toward a hand target
## in head space (cheap two-bone IK), and only the first-person camera shows them.

const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const _PropLooks = preload("res://props/prop_looks.gd")

## Bone lengths, in meters.
## Short and stubby on purpose: a cartoon's arms, and less of them across the view.
const UPPER: float = 0.21
const FORE: float = 0.2
## Where the shoulders sit under the camera, in head space.
const SHOULDERS: Array[Vector3] = [Vector3(-0.16, -0.34, -0.02), Vector3(0.16, -0.34, -0.02)]
## Which way each elbow bends: out, down, and a little back.
const POLES: Array[Vector3] = [Vector3(-0.6, -0.8, 0.0), Vector3(0.6, -0.8, 0.0)]
## Hands at rest, in head space, and how far they swing while walking.
const REST: Array[Vector3] = [Vector3(-0.24, -0.28, -0.4), Vector3(0.24, -0.28, -0.4)]
const SWING: float = 0.1
## The grips each held thing gives the hands live in props/prop_looks.gd
## (TOOL_GRIPS, HOLDS, grip_points), shared with everyone's view of your body.
## How fast the hands chase a new target, per second.
const FOLLOW: float = 16.0
## A quick reach when you grab something, in seconds.
const REACH_SECONDS: float = 0.4
## The rake's grips in first person, moved up and ahead (head space, m).
const RAKE_FP_OFFSET := Constants.RAKE_FP_GRIP_OFFSET
## A lob's follow-through (Constants.FP_ARMS_FOLLOW_*): where the hands reach,
## [left, right], and the share of it spent getting there.
const FOLLOW_THROUGH: Array[Vector3] = [Constants.FP_ARMS_FOLLOW_REACH * Vector3(-1.0, 1.0, 1.0), Constants.FP_ARMS_FOLLOW_REACH]
const FOLLOW_PEAK := Constants.FP_ARMS_FOLLOW_PEAK
const BAG_ARM_STRETCH := Constants.FP_BAG_ARM_STRETCH
const _SnackGestures = preload("res://player/snack_gestures.gd")
## Eating in first person (shops chunk 6): where the right hand holds a snack in
## front of your mouth (low in the view), how far a bite brings it in, and how
## a sip lifts and brings in the cup (head space, m).
const FP_MOUTH := Vector3(0.07, -0.17, -0.3)
const FP_BITE := Vector3(-0.01, 0.02, 0.09)
const FP_SIP := Vector3(-0.03, 0.07, 0.1)
## Reaching for a snack being handed over: how far out along the line to it the
## hand goes (z, m from the eye), how far to its own side (x), the lowest it
## sits (y, so it's in view), and how far the arm may stretch to get there.
const FP_REACH := Vector3(0.06, -0.2, 0.5)
const FP_REACH_STRETCH: float = 1.2

var _player: CharacterBody3D
var _body: Node3D
var _camera: Camera3D
var _shoulders: Array[Node3D] = []
var _elbows: Array[Node3D] = []
var _hands: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _phase: float = 0.0
var _last_held: Node = null
var _reach_left: float = 0.0
var _reach_at := Vector3.ZERO
var _time: float = 0.0
## How far past their length the arms may reach this frame (1 = not at all).
var _stretch: float = 1.0
## The follow-through after a lob (Constants.FP_ARMS_FOLLOW_SECONDS): time
## left, where the hands let go, whether a wind-up was on last frame.
var _follow_left: float = 0.0
var _follow_from: Array = [Vector3.ZERO, Vector3.ZERO]
var _was_winding: bool = false
## A hand reaching out for a world point (taking a snack: player/snack_eater.gd
## sets these): which hand (0 left, 1 right), where, and how far, 0 to 1. Laid
## over everything else, as the body's own reach is (CartoonBody.reach_at).
var reach_side: int = 1
var reach_at := Vector3.INF
var reach_weight: float = 0.0


func setup(player: CharacterBody3D, body: Node3D, camera: Camera3D) -> void:
	_player = player
	_body = body
	_camera = camera
	var shirt: Color = body.get("shirt")
	var skin: Color = body.get("skin")
	for side: int in 2:
		var shoulder := Node3D.new()
		shoulder.name = "Shoulder%d" % side
		shoulder.position = SHOULDERS[side]
		add_child(shoulder)
		var upper := _part(_upper_mesh(shirt))
		shoulder.add_child(upper)
		var elbow := Node3D.new()
		elbow.name = "Elbow"
		elbow.position = Vector3(0.0, 0.0, -UPPER)
		shoulder.add_child(elbow)
		var fore := _part(_fore_mesh(skin, 1.0 if side == 1 else -1.0))
		elbow.add_child(fore)
		_shoulders.append(shoulder)
		_elbows.append(elbow)
		_hands[side] = REST[side]
	_solve()


## Where a hand is now, in head space (0 left, 1 right): what a held snack
## follows (player/snack_eater.gd).
func hand_point(side: int) -> Vector3:
	return _hands[clampi(side, 0, 1)]


## The hand a snack is in (player/snack_gestures.gd side_of: the body's meta).
func _snack_side() -> int:
	return int(_body.get_meta("snack_side", 1)) if _body != null else 1


func _part(mesh: Mesh) -> MeshInstance3D:
	var view := _Stylized.instance(mesh, {"roughness": 0.85, "specular": 0.15})
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return view


## The upper arm: a shirt sleeve along -Z, a shoulder at its root.
func _upper_mesh(shirt: Color) -> ArrayMesh:
	var kit := _MeshKit.new()
	kit.blob(Vector3.ZERO, Vector3.ONE * 0.042, shirt, {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0})
	kit.tube(PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0, -UPPER * 0.5), Vector3(0, 0, -UPPER)]), PackedFloat32Array([0.04, 0.037, 0.034]), shirt, 10, {"jitter": 0.0})
	return kit.commit()


## The forearm along -Z, ending in a big cartoon hand with a thumb.
func _fore_mesh(skin: Color, side: float) -> ArrayMesh:
	var kit := _MeshKit.new()
	kit.blob(Vector3.ZERO, Vector3.ONE * 0.034, skin, {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0})
	kit.tube(PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0, -FORE * 0.6), Vector3(0, 0, -FORE + 0.04)]), PackedFloat32Array([0.032, 0.029, 0.026]), skin, 10, {"jitter": 0.0})
	kit.blob(Vector3(0.0, 0.0, -FORE - 0.005), Vector3(0.04, 0.03, 0.055), skin, {"detail": 2, "lumps": 0.0, "flat": false, "jitter": 0.0})
	kit.blob(Vector3(side * -0.035, 0.01, -FORE + 0.01), Vector3(0.016, 0.014, 0.027), skin, {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0})
	return kit.commit()


func _process(delta: float) -> void:
	if _player == null or _camera == null:
		return
	visible = _camera.current
	if not visible:
		return
	_time += delta
	var targets := _targets(delta)
	var snap: bool = targets["snap"]
	for side: int in 2:
		var want: Vector3 = targets["hands"][side]
		_hands[side] = want if snap else _hands[side].lerp(want, 1.0 - exp(-FOLLOW * delta))
	_solve()
	# A snack in hand (player/snack_eater.gd sets where it sits from the hand):
	# moved here, after the hand, so it never trails it by a frame.
	var snack := get_node_or_null("SnackFP") as Node3D
	if snack != null and snack.has_meta("from_hand"):
		var from_hand: Transform3D = snack.get_meta("from_hand")
		snack.transform = Transform3D(from_hand.basis, _hands[_snack_side()] + from_hand.origin)


## Where each hand wants to be, in head space, for what the player is doing now.
func _targets(delta: float) -> Dictionary:
	_stretch = 1.0
	var hands: Array[Vector3] = [REST[0], REST[1]]
	var snap := false
	var held := _player.call("_held_prop") as Node
	# A leaf bag already flying from your hands (a client draws its own toss
	# before the host hears of it) is out of them.
	if held != null and str(held.get("kind")) == "leaf_bag" and held.has_method("fp_carried") and not bool(held.call("fp_carried")):
		held = null
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	_phase += speed * delta * 2.4
	# Grabbing something: a quick reach toward it, then the hands settle on it.
	if held != _last_held:
		if held != null:
			_reach_left = REACH_SECONDS
			_reach_at = to_local((held as Node3D).global_position)
		elif _last_held != null and is_instance_valid(_last_held) and str(_last_held.get("kind")) == "leaf_bag" and _was_winding:
			# Lobbed: both hands carry on up and out after it, then come back down.
			_follow_left = Constants.FP_ARMS_FOLLOW_SECONDS
			_follow_from = [_hands[0], _hands[1]]
		_last_held = held
	_reach_left = maxf(0.0, _reach_left - delta)
	_follow_left = maxf(0.0, _follow_left - delta)
	_was_winding = float(_player.get("_wind_up")) >= Constants.THROW_TAP_SECONDS
	var gesture := str(_body.call("current_gesture")) if _body != null else ""
	var anim: int = _player.get("anim_state")
	var wind_up := float(_player.get("_wind_up"))
	var swing_left := float(_player.get("_swing_left"))
	var punch_wind := float(_player.get("_punch_wind"))
	var wheel: Array = _player.call("wheel_grips") if _player.has_method("wheel_grips") else []
	if not wheel.is_empty() and (wheel[0] as Vector3).is_finite():
		# Driving Chefty: both hands on the wheel, turning with it (grips are [right, left]).
		hands[1] = to_local(wheel[0])
		hands[0] = to_local(wheel[1])
		snap = true
	elif int(_player.get("carried_by")) != 0 or bool(_player.get("thrown")):
		# Carried or flying: kicking and flailing.
		for side: int in 2:
			hands[side] = REST[side] + Vector3(sin(_time * 16.0 + float(side) * 3.0) * 0.12, 0.2 + cos(_time * 13.0 + float(side)) * 0.12, -0.05)
	elif swing_left > 0.0:
		# The punch: the right fist shoots out and comes back.
		var t := 1.0 - swing_left / 0.45
		hands[1] = Vector3(0.22, -0.2, -0.3).lerp(Vector3(0.08, -0.12, -0.6), sin(clampf(t / 0.6, 0.0, 1.0) * PI))
		hands[0] = Vector3(-0.26, -0.28, -0.34)
		snap = true
	elif punch_wind >= 0.0:
		# Winding up: the right arm windmills, faster the longer you hold.
		_phase += delta * (6.0 + punch_wind * 10.0)
		hands[1] = Vector3(0.3 + 0.1 * cos(_phase), -0.1 + 0.22 * sin(_phase), -0.3 + 0.08 * cos(_phase))
		hands[0] = Vector3(-0.28, -0.3, -0.36)
		snap = true
	elif int(_player.get("carrying")) != 0:
		# Someone in your arms: both hands out wide, hanging on.
		var bob := sin(_phase) * 0.02
		hands[1] = Vector3(0.34, -0.14 + bob, -0.42)
		hands[0] = Vector3(-0.34, -0.14 - bob, -0.42)
	elif anim == 5:
		# Knocked flat: arms flung up and wobbling.
		for side: int in 2:
			hands[side] = Vector3(signf(float(side) - 0.5) * 0.38, 0.25 + 0.05 * sin(_time * 3.0 + float(side)), -0.3)
	elif float(_player.get("_stun_left")) > 0.0:
		for side: int in 2:
			hands[side] = REST[side] + Vector3(sin(_time * 11.0 + float(side) * 2.0) * 0.06, 0.1 + cos(_time * 9.0) * 0.05, 0.0)
	elif _player.get("_ladder") != null:
		# Hand over hand up the rungs.
		for side: int in 2:
			hands[side] = Vector3(signf(float(side) - 0.5) * 0.22, 0.08 + 0.16 * sin(_time * 5.0 + float(side) * PI), -0.42)
	elif _follow_left > 0.0 and held == null:
		# The follow-through of a lob: from where they let go, up and out in front
		# (anticipation done, this is the release), then back down to your sides.
		var t := 1.0 - _follow_left / Constants.FP_ARMS_FOLLOW_SECONDS
		for side: int in 2:
			var peak := FOLLOW_THROUGH[side]
			if t < FOLLOW_PEAK:
				var rise := t / FOLLOW_PEAK
				hands[side] = (_follow_from[side] as Vector3).lerp(peak, 1.0 - (1.0 - rise) * (1.0 - rise))
			else:
				hands[side] = peak.lerp(REST[side], smoothstep(0.0, 1.0, (t - FOLLOW_PEAK) / (1.0 - FOLLOW_PEAK)))
		snap = true
	elif wind_up >= 0.0 and held != null:
		# Wound up: the hands stay on the thing, hitch it up, and shake more the
		# longer you hold it, until you strain and it's a full tremble. A leaf bag
		# dips and trembles itself (props/carry_view.gd), and the hands stay on it.
		var t := clampf(wind_up / Constants.THROW_CHARGE_SECONDS, 0.0, 1.0)
		var strain := 1.0 if bool(_player.get("straining")) else 0.0
		var shake := Vector3(sin(_time * 37.0), cos(_time * 41.0), sin(_time * 29.0)) * (0.004 + 0.012 * t + 0.03 * strain)
		_on_item(held, hands)
		if str(held.get("kind")) != "leaf_bag":
			for side: int in 2:
				hands[side] += Vector3(0.0, 0.08 * t, 0.06 * t) + shake
		snap = true
	elif held != null:
		snap = _on_item(held, hands)
	elif _reach_left > 0.0:
		var t := _reach_left / REACH_SECONDS
		hands[1] = REST[1].lerp(_reach_at, sin(t * PI))
	elif gesture == "scratch" or gesture == "shuffle":
		# Bare-hands work: reach down in front and tug.
		var dip := sin(fmod(_time * 6.0, PI))
		hands[1] = Vector3(0.2, -0.48 - 0.12 * dip, -0.55)
		hands[0] = Vector3(-0.26, -0.55, -0.35)
	elif gesture == "wave":
		hands[1] = Vector3(0.36, 0.12 + 0.06 * sin(_time * 12.0), -0.28)
	elif gesture == "cheer":
		for side: int in 2:
			hands[side] = Vector3(signf(float(side) - 0.5) * 0.3, 0.28 + 0.05 * sin(_time * 8.0 + float(side)), -0.3)
	elif gesture == "flail" or gesture == "stumble":
		for side: int in 2:
			hands[side] = REST[side] + Vector3(sin(_time * 14.0 + float(side) * 3.0) * 0.15, 0.25 + cos(_time * 12.0 + float(side)) * 0.12, 0.0)
	else:
		# Walking: the arms pump, opposite each other; sprinting pumps harder.
		var swing := SWING * (1.5 if anim == 2 else 1.0) * clampf(speed / 2.0, 0.0, 1.0)
		for side: int in 2:
			var along := sin(_phase + float(side) * PI)
			hands[side] = REST[side] + Vector3(0.0, 0.03 * absf(along), along * swing)
	# A snack (player/snack_eater.gd): the hand it's in (the right, or the left
	# when the right holds something one-handed) brings it up into view and to
	# your mouth, on the same clock as everyone's view of your body. From wherever
	# that hand was (on a rake's handle, say), so it never jumps off it.
	var side := _snack_side()
	if gesture == "eat" or gesture == "drink":
		var s := float(_body.get("_gesture_time"))
		var length := float(_SnackGestures.SECONDS[gesture])
		var up := _SnackGestures.lift(s, length)
		var at_mouth := FP_MOUTH
		if gesture == "eat":
			at_mouth += FP_BITE * _SnackGestures.bite_nod(s)
		else:
			at_mouth += FP_SIP * _SnackGestures.sip_tip(s)
		if side == 0:
			at_mouth.x = -at_mouth.x
		hands[side] = hands[side].lerp(at_mouth, up)
		snap = true
	# Reaching out to take it: the hand comes up from low in the view, out along
	# your line of sight toward the point (so you see it go to meet the food),
	# the arm stretched a little to get there.
	if reach_weight > 0.0 and reach_at.is_finite():
		var toward := to_local(reach_at)
		var out := toward.normalized() * minf(toward.length(), FP_REACH.z)
		out.x += FP_REACH.x * (1.0 if reach_side == 1 else -1.0)
		out.y = maxf(out.y, FP_REACH.y)
		var w := smoothstep(0.0, 1.0, clampf(reach_weight, 0.0, 1.0))
		hands[reach_side] = hands[reach_side].lerp(out, w)
		_stretch = maxf(_stretch, FP_REACH_STRETCH)
		snap = true
	# A mower cord pull yanks the right hand back, whatever else is going on.
	if gesture == "startle" and held != null and str(held.get("kind")) == "lawn_mower":
		var t := clampf(float(_body.get("_gesture_time")) / 0.5, 0.0, 1.0)
		hands[1] = Vector3(0.15, -0.35, -0.5).lerp(Vector3(0.4, -0.05, 0.05), sin(t * PI))
		snap = false
	return {"hands": hands, "snap": snap}


## Hands on whatever's held, on the same grips everyone else sees your body hold
## (props/prop_looks.gd grip_points). Returns true when they should follow it exactly.
func _on_item(held: Node, hands: Array[Vector3]) -> bool:
	var kind := str(held.get("kind"))
	var grips := _PropLooks.grip_points(held as Node3D, _player)
	var gripped := false
	# grip_points is [right, left]; these arms are [left, right].
	for side: int in 2:
		if grips[side].is_finite():
			hands[1 - side] = to_local(grips[side])
			gripped = true
	if not gripped:
		# Nothing to hold on to (a rake not posed yet): arms up and open around it.
		var bob := sin(_phase) * 0.02
		hands[1] = Vector3(0.26, -0.2 + bob, -0.4)
		hands[0] = Vector3(-0.26, -0.2 - bob, -0.4)
		return false
	# A free hand (the sign, the ladder) swings along as you walk.
	for side: int in 2:
		if not grips[side].is_finite():
			hands[1 - side] = REST[1 - side] + Vector3(0.0, 0.0, sin(_phase + float(side) * PI) * SWING * 0.5)
	if kind == "rake":
		# The rake's grips (props/rake_motion.gd: in first person both hands at the
		# handle's top, aimed past your right shoulder), a hair up so the mitts sit on
		# the handle rather than inside it; the arms stretch to keep hold in the drive.
		for side: int in 2:
			hands[side] += RAKE_FP_OFFSET
		_stretch = Constants.RAKE_FP_ARM_STRETCH
		return true
	if kind == "leaf_bag":
		_stretch = BAG_ARM_STRETCH
		return true
	# Pushed and shouldered things rock with each step, and the hands follow
	# them smoothly instead of exactly.
	if kind in ["lawn_mower", "wheelbarrow", "ladder"]:
		var rock := sin(_phase) * 0.03
		hands[1] += Vector3(0.0, rock, 0.0)
		hands[0] += Vector3(0.0, -rock, 0.0)
		return false
	return true


## Two-bone IK in head space: aim the upper arm at an elbow that bends toward
## the arm's pole, then the forearm at the hand.
func _solve() -> void:
	for side: int in 2:
		var shoulder := _shoulders[side]
		var elbow := _elbows[side]
		var start := SHOULDERS[side]
		var target := _hands[side]
		# Never behind the camera's near plane, or the hand pops in and out.
		target.z = minf(target.z, -0.12)
		# Holding the rake out at the end of a shove: the arm reaches further (the
		# whole arm slides out from below the view, a cartoon's stretch).
		var reach := UPPER + FORE - 0.02
		var excess := (target - start).length() - reach
		if _stretch > 1.0 and excess > 0.0:
			start += (target - start).normalized() * minf(excess, reach * (_stretch - 1.0))
		shoulder.position = start
		var to_hand := target - start
		var length := clampf(to_hand.length(), 0.08, UPPER + FORE - 0.02)
		var along := to_hand.normalized() if to_hand.length() > 0.001 else Vector3.FORWARD
		var cos_a := clampf((UPPER * UPPER + length * length - FORE * FORE) / (2.0 * UPPER * length), -1.0, 1.0)
		var angle := acos(cos_a)
		var pole: Vector3 = POLES[side]
		var perp := pole - along * pole.dot(along)
		if perp.length() < 0.01:
			perp = Vector3.DOWN
		perp = perp.normalized()
		var elbow_at := start + along * (UPPER * cos(angle)) + perp * (UPPER * sin(angle))
		shoulder.basis = _looking(elbow_at - start)
		var hand_at := start + along * length
		var fore_dir := shoulder.basis.inverse() * (hand_at - elbow_at)
		elbow.basis = _looking(fore_dir)


static func _looking(direction: Vector3) -> Basis:
	if direction.length() < 0.001:
		return Basis.IDENTITY
	var up := Vector3.UP
	if absf(direction.normalized().dot(up)) > 0.98:
		up = Vector3.BACK
	return Basis.looking_at(direction, up)
