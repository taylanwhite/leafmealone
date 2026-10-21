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
## Where the hands go on each aimed tool, in its Look space: [right, left].
const GRIPS: Dictionary = {
	"hose": [Vector3(0.0, -0.09, 0.06), Vector3(-0.05, -0.02, -0.12)],
	"leaf_blower": [Vector3(0.0, 0.29, 0.07), Vector3(-0.06, 0.1, -0.28)],
	"hedge_trimmer": [Vector3(0.0, 0.2, 0.09), Vector3(-0.05, 0.12, -0.06)],
	"paint_roller": [Vector3(0.0, 0.0, 0.16), Vector3(-0.09, -0.05, 0.02)],
}
## How fast the hands chase a new target, per second.
const FOLLOW: float = 16.0
## A quick reach when you grab something, in seconds.
const REACH_SECONDS: float = 0.4

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


## Where each hand wants to be, in head space, for what the player is doing now.
func _targets(delta: float) -> Dictionary:
	var hands: Array[Vector3] = [REST[0], REST[1]]
	var snap := false
	var held := _player.call("_held_prop") as Node
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	_phase += speed * delta * 2.4
	# Grabbing something: a quick reach toward it, then the hands settle on it.
	if held != _last_held:
		if held != null:
			_reach_left = REACH_SECONDS
			_reach_at = to_local((held as Node3D).global_position)
		_last_held = held
	_reach_left = maxf(0.0, _reach_left - delta)
	var gesture := str(_body.call("current_gesture")) if _body != null else ""
	var anim: int = _player.get("anim_state")
	var wind_up := float(_player.get("_wind_up"))
	if anim == 5:
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
	elif wind_up >= 0.0 and held != null:
		# Wound up: the hands stay on the thing, hitch it up, and shake more the
		# longer you hold it, until you strain and it's a full tremble.
		var t := clampf(wind_up / Constants.THROW_CHARGE_SECONDS, 0.0, 1.0)
		var strain := 1.0 if bool(_player.get("straining")) else 0.0
		var shake := Vector3(sin(_time * 37.0), cos(_time * 41.0), sin(_time * 29.0)) * (0.004 + 0.012 * t + 0.03 * strain)
		_on_item(held, hands)
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
	# A mower cord pull yanks the right hand back, whatever else is going on.
	if gesture == "startle" and held != null and str(held.get("kind")) == "lawn_mower":
		var t := clampf(float(_body.get("_gesture_time")) / 0.5, 0.0, 1.0)
		hands[1] = Vector3(0.15, -0.35, -0.5).lerp(Vector3(0.4, -0.05, 0.05), sin(t * PI))
		snap = false
	return {"hands": hands, "snap": snap}


## Hands on whatever's held. Returns true when they should follow it exactly.
func _on_item(held: Node, hands: Array[Vector3]) -> bool:
	var kind := str(held.get("kind"))
	var prop := held as Node3D
	var right := _player.global_basis.x
	match kind:
		"rake":
			# Both hands down toward the handle, riding its stroke (the rake itself
			# is held low and ahead, farther than these arms reach).
			var raking := Input.is_action_pressed("primary") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			var phase := fmod(Time.get_ticks_msec() / 1000.0, Constants.RAKE_STROKE_SECONDS) / Constants.RAKE_STROKE_SECONDS
			var sweep := (0.1 - 0.2 * phase) if raking else 0.0
			hands[1] = Vector3(0.2, -0.26, -0.36 + sweep)
			hands[0] = Vector3(-0.04, -0.3, -0.42 + sweep * 1.3)
			return true
		"hose", "leaf_blower", "hedge_trimmer", "paint_roller":
			var look := prop.get_node_or_null("Visual/Look") as Node3D
			if look != null and _PropLooks.HANDHELD.has(kind) and not (kind == "hose" and str(held.get("hose_source")) == ""):
				# Where each model's grips are (props/yard_models.gd, drawn at 0.7 scale).
				var grips: Array = GRIPS[kind]
				hands[1] = to_local(look.global_transform * (grips[0] as Vector3))
				hands[0] = to_local(look.global_transform * (grips[1] as Vector3))
				return true
			# A hose that isn't hooked up is just carried.
			hands[1] = to_local(prop.global_position + right * 0.18)
			hands[0] = to_local(prop.global_position - right * 0.18)
			return true
		"pressure_washer":
			var wand := prop.get_node_or_null("Wand") as Node3D
			if wand != null and wand.visible:
				hands[1] = to_local(wand.global_transform * Vector3(0.0, -0.11, 0.1))
				hands[0] = to_local(wand.global_transform * Vector3(-0.03, -0.02, -0.3))
				return true
		"lawn_mower":
			# Pushing: both hands out on the bar, rocking with each step.
			var rock := sin(_phase) * 0.03
			hands[1] = Vector3(0.2, -0.3 + rock, -0.42)
			hands[0] = Vector3(-0.2, -0.3 - rock, -0.42)
			return false
		"ladder":
			# Up on the right shoulder, held by one hand; the other swings.
			hands[1] = Vector3(0.3, -0.12, -0.08)
			hands[0] = REST[0] + Vector3(0.0, 0.0, sin(_phase) * SWING * 0.5)
			return false
		"wheelbarrow":
			hands[1] = Vector3(0.24, -0.34, -0.36)
			hands[0] = Vector3(-0.24, -0.34, -0.36)
			return false
	# Anything else is carried out in front, arms up and open around it.
	var bob := sin(_phase) * 0.02
	hands[1] = Vector3(0.26, -0.2 + bob, -0.4)
	hands[0] = Vector3(-0.26, -0.2 - bob, -0.4)
	return false


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
