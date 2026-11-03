extends Node3D

## Authority: local, cosmetic. A goofy low-poly cartoon person (docs/FEEL.md,
## "Look"): a big round head with big blinking eyes, a small body, and bouncy
## procedural motion. Used for players, the crew, and the store clerk.
##
## Put it under the node that moves on screen (a player's smoothed Visual), with
## its origin at the feet, facing -Z. Motion comes from how fast that node really
## moves, so it animates the same for local players, remote players, and NPCs.
## If the parent body has an anim_state like player.gd's, jumping and crouching
## show too. Call talk() to flap the mouth while a sound plays.

## Matches player.gd's AnimState: IDLE, WALK, SPRINT, CROUCH, AIR.
const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const _NiceSeal = preload("res://props/nice_seal.gd")
const STATE_CROUCH: int = 3
const STATE_AIR: int = 4
const STATE_KNOCKED: int = 5
## How far a knocked-down body tips back, in radians.
const FALL_ANGLE: float = 1.4
const SKIN_TONES: Array[Color] = [
	Color(0.98, 0.82, 0.68), Color(0.87, 0.67, 0.5), Color(0.72, 0.52, 0.36),
	Color(0.55, 0.37, 0.25), Color(0.4, 0.27, 0.18),
]
const SHIRTS: Array[Color] = [
	Color(0.92, 0.35, 0.2), Color(0.25, 0.55, 0.85), Color(0.95, 0.75, 0.2),
	Color(0.35, 0.7, 0.35), Color(0.65, 0.35, 0.75), Color(0.95, 0.5, 0.6),
	Color(0.2, 0.7, 0.7), Color(0.85, 0.85, 0.82),
]
const PANTS: Array[Color] = [Color(0.25, 0.3, 0.45), Color(0.35, 0.3, 0.25), Color(0.2, 0.2, 0.22), Color(0.45, 0.42, 0.35)]
const HAIR: Array[Color] = [Color(0.15, 0.1, 0.07), Color(0.45, 0.28, 0.12), Color(0.85, 0.7, 0.35), Color(0.6, 0.2, 0.1), Color(0.3, 0.3, 0.32)]
const EYE_WHITE := Color(0.97, 0.97, 0.95)
const PUPIL := Color(0.06, 0.05, 0.06)
## Stride length in radians of swing per meter walked.
const STRIDE: float = 2.4
## Render layer the head is drawn on, so a player's own first-person camera can skip it.
const HEAD_LAYER: int = 2

@export var skin := SKIN_TONES[0]
@export var shirt := SHIRTS[0]
@export var pants := PANTS[0]
@export var hair := HAIR[0]
## "cap", "hair", "visor" (a sun visor, hair poking out on top; the NICE BOYS), or "none".
@export var hat_style := "hair"
@export var hat_color := Color(0.2, 0.2, 0.22)
## Sunglasses over the eyes (the NICE BOYS wear them), in shades_style.
@export var shades := false
## "aviator": gold rims and dark teardrop lenses. "plain": two dark lenses.
@export var shades_style := "aviator"
## A uniform over the clothes (docs/GAME.md, "2026-11-01, the cast"): "" for none,
## "nice_boy" (polo collar, lanyard and ID card, Daisy Seal patch, fanny pack,
## knee socks, a clipboard in the left hand) or "nice_boy_lead" (the same, with a
## whistle on the lanyard and a megaphone in the right hand instead). Its parts are
## named MeshInstance3D nodes (OUTFIT_PARTS) so tests can find them.
@export var outfit := ""
## A fixed wide grin instead of the flat mouth. With the crew's angry brows, a
## furious smile.
@export var grin := false

var _head_root: Node3D
var _face: Node3D
var _own_head: bool = false
var _pupils: Array[Node3D] = []
var _face_yaw: float = 0.0
var _gesture: String = ""
var _gesture_time: float = 0.0
var _gesture_length: float = 0.0
var _brow_lift: float = 0.0
var _brow_tilt: float = 0.0
## The outfit's clipboard, tilted up to write on in the scribble gesture, and the
## lead's megaphone, kept level while pointing with it.
var _clipboard: Node3D
var _megaphone: Node3D
## Hands on a held thing (set_hold): [right, left] targets in the parent's space
## (a player's Visual), INF for a free hand; the last real one, to let go smoothly;
## and how far each arm has reached, 0 to 1.
var _hold_targets: Array[Vector3] = [Vector3.INF, Vector3.INF]
var _hold_last: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _hold_weight: Array[float] = [0.0, 0.0]

## Set by player/character_life.gd each frame. Where the eyes look, in world
## space, or INF to look straight ahead.
var look_at_point := Vector3.INF
## Extra glance in the turning direction, -1 to 1, so the eyes lead the head.
var eye_lead := Vector2.ZERO
## How far the face turns toward what it looks at, in radians, kept small.
var face_turn: float = 0.0
## "neutral", "raised", "worried", or "angry".
var mood := "neutral"
## True while sprinting: the eyes narrow.
var squinting := false
var _torso: Node3D
var _hips: Node3D
var _legs: Array[Node3D] = []
## Each leg's knee pivot (the shin and shoe hang from it) and its shoe.
var _shins: Array[Node3D] = []
var _shoes: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _eyes: Array[Node3D] = []
var _mouth: Node3D
var _brows: Array[Node3D] = []
var _phase: float = 0.0
var _last_position := Vector3.INF
var _speed: float = 0.0
var _blink_in: float = 2.0
var _blink_left: float = 0.0
var _talk_left: float = 0.0
var _squash: float = 0.0
var _was_air: bool = false
var _time: float = 0.0
var _head_base_y: float = 1.6
## 0 standing, 1 flat on the back after a heavy bonk. Read by player.gd for the head.
var fallen: float = 0.0
var _straining: bool = false
var _limping: bool = false
var _bandage: Node3D
## The mower got a foot: 1 a cut (bandaged shoe), 2 gone (a bandaged stump, hopping).
var foot_hurt: int = 0
var _foot_wrap: Node3D
var _stump: Node3D
var _head_stand_y: float = 1.6
var _stars: Node3D
var _stars_left: float = 0.0
## How far the hips and head drop when crouching, in meters.
const CROUCH_DROP: float = 0.3
## Sitting (sit(1), a Chefty cab seat): the hips this high over the seat's
## floor, the legs out in front this far (radians).
const SIT_HIPS: float = 0.48
const SIT_LEGS: float = 1.42
## 0 on your feet, 1 sitting, 2 riding standing up (a truck's bed: no walk cycle).
var _sit_pose: int = 0
## set_work_pose: what was asked (lean, twist, hip) and what's shown, and how fast
## it follows; the neck's height above the hips, for the head to ride the lean.
var _work_target := Vector3.ZERO
var _work := Vector3.ZERO
## set_work_pose's crouch (how far the hips sink, m), asked and shown; how far
## into the planted work stance the feet are (0 walking, 1 planted); the lean's
## last value and the head's lag behind it (secondary motion).
var _crouch_target: float = 0.0
var _crouch: float = 0.0
var _stance: float = 0.0
var _lean_last: float = 0.0
var _head_lag: float = 0.0
var _in_air: bool = false
## The stance's feet on the ground (world x, z; INF until planted), each foot's
## step (0 to 1 while it steps, -1 planted) and where the step left from, and the
## body's velocity across the ground (m/s) for where a step lands.
var _foot_spot: Array[Vector2] = [Vector2.INF, Vector2.INF]
var _foot_from: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var _foot_step: Array[float] = [-1.0, -1.0]
var _ground_vel := Vector2.ZERO
const WORK_SMOOTH_SECONDS: float = 0.015
## The head's height over the hips' pivot, which the lean swings it round.
const WORK_NECK: float = 0.72
## Hip to knee (the knee pivot) and the stance's shoe height above the feet.
const KNEE: float = Constants.BODY_THIGH
const SHOE_Y: float = 0.06
## Share of a player's look up and down that the visible head shows.
const HEAD_TILT_SHARE: float = 0.35
const GESTURE_SECONDS: Dictionary = {
	"wave": 1.4, "scratch": 1.6, "stretch": 2.2, "watch": 1.8, "shuffle": 1.2,
	"cheer": 1.8, "flail": 0.9, "startle": 0.8, "look_around": 2.4, "stumble": 0.9,
	"offer": 0.6, "windmill": 0.8, "punch": 0.45, "rake": 1.1,
	"point": 0.9, "scribble": 1.4,
}
## The named parts an outfit adds, by outfit (the test looks for every one).
const OUTFIT_PARTS: Dictionary = {
	"nice_boy": ["Socks", "Collar", "Lanyard", "Badge", "Insignia", "FannyPack", "VisorSeal", "Clipboard"],
	"nice_boy_lead": ["Socks", "Collar", "Lanyard", "Badge", "Insignia", "FannyPack", "VisorSeal", "Megaphone", "Whistle"],
}
const SOCK := Color(0.97, 0.97, 0.95)
const SNEAKER := Color(0.95, 0.95, 0.93)
const LANYARD := Color(0.86, 0.16, 0.16)
const GOLD := Color(0.88, 0.7, 0.28)
const LENS := Color(0.1, 0.12, 0.15)
const MEGAPHONE := Color(0.98, 0.5, 0.1)
const CLIPBOARD := Color(0.55, 0.36, 0.2)
const SILVER := Color(0.78, 0.8, 0.84)
const FANNY_PACK := Color(0.2, 0.62, 0.62)
## How much higher the brows sit over sunglasses, in meters.
const BROW_OVER_SHADES: float = 0.024
## The point gesture's arm, straight out ahead, in radians of x turn.
const POINT_ARM: float = 1.5
## The scribble gesture: the clipboard arm raised in front, and the board tilted
## back on top of that so the paper faces the writer.
const SCRIBBLE_BOARD_ARM: float = 1.1
const SCRIBBLE_BOARD_TILT: float = 1.1
## How far the pupils can travel inside the eye, in meters.
const PUPIL_RANGE := Vector2(0.026, 0.02)


## Pick colors from a seed so each character looks different but stays the same every session.
func dress_from_seed(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	skin = SKIN_TONES[rng.randi() % SKIN_TONES.size()]
	shirt = SHIRTS[rng.randi() % SHIRTS.size()]
	pants = PANTS[rng.randi() % PANTS.size()]
	hair = HAIR[rng.randi() % HAIR.size()]
	hat_style = "cap" if rng.randf() < 0.35 else "hair"
	hat_color = SHIRTS[rng.randi() % SHIRTS.size()].darkened(0.2)


## Build the body. head_parent is where the head goes (a player's Head node, so
## looking up and down nods it), or null to give the body its own head.
## own_head is true only for the local player's own body: its head goes on
## HEAD_LAYER so that player's first-person camera can skip it. Everyone else's
## head stays on the normal layer, or that camera would skip theirs too.
func build(head_parent: Node3D = null, own_head: bool = false) -> void:
	_own_head = own_head
	_hips = _pivot(self, Vector3(0.0, 0.82, 0.0))
	_torso = _pivot(_hips, Vector3.ZERO)
	var shoe := Color(0.18, 0.14, 0.12) if outfit == "" else SNEAKER
	# Pelvis on the hips, the shirt's hem hanging over it from the torso.
	_kit_part(_hips, _blob_mesh(Vector3(0.0, -0.02, 0.0), Vector3(0.19, 0.13, 0.15), pants), Vector3.ZERO)
	_kit_part(_torso, _torso_mesh(shirt), Vector3.ZERO)
	for side: float in [-1.0, 1.0]:
		# The thigh hangs from the hip, the shin (and the shoe) from the knee, so the
		# knees can bend (docs/GAME.md, "Raking feel: the look").
		var leg := _pivot(_hips, Vector3(side * 0.1, 0.0, 0.0))
		var shin := _pivot(leg, Vector3(0.0, -KNEE, 0.0))
		shin.name = "Knee"
		var shoe_part: MeshInstance3D
		if outfit != "":
			# Shorts, bare shins and white knee socks.
			_kit_part(leg, _thigh_mesh(pants, skin), Vector3.ZERO).name = "Shorts"
			_kit_part(shin, _leg_mesh(skin, SOCK), Vector3.ZERO).name = "Socks"
			shoe_part = _kit_part(shin, _shoe_mesh(shoe, Color(0.7, 0.72, 0.74)), Vector3(0.0, KNEE - 0.76, -0.04))
		else:
			_kit_part(leg, _limb_mesh([Vector3(0.0, 0.0, 0.0), Vector3(0.0, -KNEE, 0.0)], [0.088, 0.078], pants), Vector3.ZERO)
			# The knee: a round joint the shin turns on, so a bent leg has no gap.
			_kit_part(shin, _knee_mesh([Vector3(0.0, 0.0, 0.0), Vector3(0.0, KNEE - 0.72, 0.0)], [0.078, 0.07], pants), Vector3.ZERO)
			shoe_part = _kit_part(shin, _shoe_mesh(shoe), Vector3(0.0, KNEE - 0.76, -0.04))
		_legs.append(leg)
		_shins.append(shin)
		_shoes.append(shoe_part)
		var arm := _pivot(_torso, Vector3(side * 0.25, 0.46, 0.0))
		arm.rotation.z = side * 0.12
		# Your own arms swing right through your first-person view during gestures,
		# so like your head they are hidden from your own camera.
		_on_head_layer(_kit_part(arm, _arm_mesh(side), Vector3.ZERO))
		_arms.append(arm)
	_head_root = head_parent if head_parent != null else _pivot(self, Vector3(0.0, 1.6, 0.0))
	_head_base_y = _head_root.position.y
	_head_stand_y = _head_base_y
	_build_head(_head_root)
	if outfit != "":
		_build_outfit()
	# Your own body, not just your head: looking down in first person, the torso
	# right under the camera filled the screen.
	if _own_head:
		for node: Node in find_children("*", "MeshInstance3D", true, false):
			_on_head_layer(node as Node3D)


## Paint or water all over: tint every part toward color by amount (0 clears it).
func set_coat(color: Color, amount: float) -> void:
	for node: Node in find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).set_instance_shader_parameter("tint", Color(color.r, color.g, color.b, amount))


## Play a gesture once, any key of GESTURE_SECONDS: "wave", "scratch", "stretch",
## "watch", "shuffle", "cheer", "flail", "startle", "look_around", "stumble",
## "point", "scribble" (writing on the outfit's clipboard), ... A new one replaces
## the current one.
func gesture(gesture_name: String) -> void:
	_gesture = gesture_name
	_gesture_time = 0.0
	_gesture_length = float(GESTURE_SECONDS.get(gesture_name, 1.5))
	_rest_props()


## Held props back in their resting grip (a gesture may have tilted them).
func _rest_props() -> void:
	if _clipboard != null:
		_clipboard.rotation = Vector3.ZERO
	if _megaphone != null:
		_megaphone.rotation = Vector3.ZERO


## Put the hands on something held: world-space targets [right, left] from
## props/prop_looks.gd grip_points, Vector3.INF for a hand that's free. Each arm
## swings round from its shoulder to point at its target, blended in and out over
## Constants.HOLD_BLEND_SECONDS, on top of walking and gestures; not while flat on
## the back. player.gd calls it every frame on every peer; NPCs never do. The
## targets are kept relative to the parent (the smoothed Visual), so they ride
## along between the frame they're set and the tick that aims the arms. A hold
## stretches or shortens the arm a little to land the hand (Constants.HOLD_ARM_*).
func set_hold(right: Vector3, left: Vector3) -> void:
	var into := _hold_frame().affine_inverse()
	_hold_targets[0] = into * right if right.is_finite() else Vector3.INF
	_hold_targets[1] = into * left if left.is_finite() else Vector3.INF


## Working a tool (the rake's swing, equipment/rake_stroke.gd): lean the torso by
## lean_x (negative is forward), twist it by twist_y, push the hips back by hip
## (m), and look down at the work. Smoothed over WORK_SMOOTH_SECONDS; call it every
## frame (zeros to stand up straight). The head rides along with the torso, except
## your own head while you look through it in first person (the camera nods on its
## own, player/stroke_cam.gd).
## crouch: how far the hips sink into the knees (m). While working and standing
## (slower than Constants.RAKE_STANCE_SPEED) the feet step into a planted stance,
## the left a half step ahead, and the knees take up the sink and the lunge.
func set_work_pose(lean_x: float, twist_y: float, hip: float, crouch: float = 0.0) -> void:
	_work_target = Vector3(lean_x, twist_y, hip)
	_crouch_target = crouch


## The current, smoothed work pose: (lean, twist, hip). For tests.
func work_pose() -> Vector3:
	return _work


## How far into the planted work stance the feet are (0 walking, 1 planted), and
## each knee's bend (rad, 0 straight). For tests.
func stance() -> float:
	return _stance


func knee_bend(index: int) -> float:
	if index < 0 or index >= _shins.size():
		return 0.0
	return absf(_shins[index].rotation.x)


## Where leg index's shoe is (world space), and whether that foot is planted in
## the work stance right now (not stepping). For tests.
func foot_position(index: int) -> Vector3:
	if index < 0 or index >= _shoes.size():
		return global_position
	return _shoes[index].global_position


func foot_planted(index: int) -> bool:
	return _stance >= 1.0 and index >= 0 and index < 2 and _foot_step[index] < 0.0 and _foot_spot[index].is_finite()


func _apply_work(delta: float) -> void:
	var follow := 1.0 - exp(-delta / WORK_SMOOTH_SECONDS)
	_work = _work.lerp(_work_target, follow)
	_crouch = lerpf(_crouch, _crouch_target, follow)
	var working := _work_target != Vector3.ZERO or _crouch_target > 0.0
	var plant := working and _speed < Constants.RAKE_STANCE_SPEED and _sit_pose == 0 and fallen <= 0.01 and not _in_air
	_stance = move_toward(_stance, 1.0 if plant else 0.0, delta / maxf(Constants.RAKE_STANCE_SECONDS, 0.001))
	if _work.length_squared() < 0.0000001 and not working and _stance <= 0.0:
		_work = Vector3.ZERO
		_crouch = 0.0
		_head_lag = 0.0
		_lean_last = 0.0
		_foot_spot = [Vector2.INF, Vector2.INF]
		_foot_step = [-1.0, -1.0]
		_hips.rotation.y = 0.0
		_hips.position.z = 0.0
		return
	_torso.rotation.x += _work.x
	# The hips turn a little against the shoulders.
	_hips.rotation.y = -Constants.WORK_HIP_COUNTER * _work.y
	_torso.rotation.y = _work.y * Constants.WORK_TWIST_SHARE
	_hips.position.z = _work.z
	if _stance > 0.0 and _legs.size() == 2 and _shins.size() == 2:
		# Planted: the hips sink and lunge, the feet stay put, the knees bend.
		var s := smoothstep(0.0, 1.0, _stance)
		_hips.position.y -= _crouch * s
		var feet := _stance_feet(delta)
		for index: int in 2:
			var angles := _leg_reach(index, feet[index])
			_legs[index].rotation.x = lerpf(_legs[index].rotation.x, angles.x, s)
			_shins[index].rotation.x = lerpf(_shins[index].rotation.x, angles.y, s)
			# Feet flat on the ground, whatever the leg does.
			_shoes[index].rotation.x = lerpf(0.0, -(angles.x + angles.y), s)
	else:
		_foot_spot = [Vector2.INF, Vector2.INF]
		_foot_step = [-1.0, -1.0]
	# Eyes on the tines.
	_face.rotation.x -= absf(_work.x) * Constants.WORK_FACE_TILT
	# The head lags the back a beat: it tips up as the shove throws the torso
	# down, and nods as the torso comes back up.
	if delta > 0.0:
		var lean_rate := (_work.x - _lean_last) / delta
		_lean_last = _work.x
		var want := clampf(-lean_rate * Constants.RAKE_HEAD_LAG, -Constants.RAKE_HEAD_LAG_MAX, Constants.RAKE_HEAD_LAG_MAX)
		_head_lag = lerpf(_head_lag, want, 1.0 - exp(-delta / Constants.RAKE_HEAD_LAG_SECONDS))
		_face.rotation.x += _head_lag


## The stance's two feet this tick, in body space. Each stays where it was put
## on the ground while the body shuffles over it (no skating); the one the body
## has carried furthest from its spot in the stance steps when it passes
## RAKE_STEP_DRIFT, one foot at a time, landing a little ahead of the motion.
func _stance_feet(delta: float) -> Array[Vector3]:
	var stance: Array[Vector2] = [Constants.RAKE_STANCE_FRONT, Constants.RAKE_STANCE_BACK]
	var homes: Array[Vector2] = []
	for index: int in 2:
		var home := global_transform * Vector3(stance[index].x, 0.0, stance[index].y)
		homes.append(Vector2(home.x, home.z))
		if not _foot_spot[index].is_finite() or _foot_spot[index].distance_to(homes[index]) > Constants.RAKE_STEP_LOST:
			_foot_spot[index] = homes[index]
			_foot_step[index] = -1.0
	if _foot_step[0] < 0.0 and _foot_step[1] < 0.0:
		var worst := 0 if _foot_spot[0].distance_to(homes[0]) >= _foot_spot[1].distance_to(homes[1]) else 1
		# Shuffling steps wait for the hips to come back out of the lunge, so the
		# back foot is free to step up in the next one.
		var go := _foot_spot[worst].distance_to(homes[worst]) > Constants.RAKE_STEP_DRIFT and absf(_work.z) < Constants.RAKE_STEP_LUNGE_MAX
		# A foot the leg can no longer reach (the lunge carried the hips past a
		# trailing foot) steps up now instead of dragging.
		for index: int in 2:
			if _foot_overreach(index) > Constants.RAKE_STEP_STRETCH:
				worst = index
				go = true
				break
		if go:
			_foot_step[worst] = 0.0
			_foot_from[worst] = _foot_spot[worst]
	var out: Array[Vector3] = []
	for index: int in 2:
		var lift := 0.0
		if _foot_step[index] >= 0.0:
			_foot_step[index] = minf(1.0, _foot_step[index] + delta / maxf(Constants.RAKE_STEP_SECONDS, 0.001))
			var land := homes[index] + _ground_vel * Constants.RAKE_STEP_LEAD
			_foot_spot[index] = _foot_from[index].lerp(land, smoothstep(0.0, 1.0, _foot_step[index]))
			lift = sin(PI * _foot_step[index]) * Constants.RAKE_STEP_LIFT
			if _foot_step[index] >= 1.0:
				_foot_step[index] = -1.0
		out.append(_foot_local(index) + Vector3(0.0, lift, 0.0))
	return out


## Leg index's planted spot in body space, at shoe height.
func _foot_local(index: int) -> Vector3:
	var local := to_local(Vector3(_foot_spot[index].x, global_position.y, _foot_spot[index].y))
	return Vector3(local.x, SHOE_Y, local.z)


## How far (m) leg index's planted spot is beyond what the leg reaches from the
## hip where it is now (negative: in reach).
func _foot_overreach(index: int) -> float:
	var d := _foot_local(index) - _hips.transform * _legs[index].position
	return Vector2(d.z, d.y).length() - (Constants.BODY_THIGH + Constants.BODY_SHIN)


## Thigh and shin angles (rotation.x of the leg and its knee) that put leg
## index's shoe at foot (body space), the knee bending forward; a foot out of
## reach gets a straight leg pointing at it.
func _leg_reach(index: int, foot: Vector3) -> Vector2:
	var leg := _legs[index]
	var hip := _hips.transform * leg.position
	var d := foot - hip
	var flat := Vector2(d.z, d.y)
	var thigh := Constants.BODY_THIGH
	var shin := Constants.BODY_SHIN
	var length := clampf(flat.length(), absf(thigh - shin) + 0.01, thigh + shin - 0.001)
	# The leg's -Y swings forward (toward -Z) for positive x turns.
	var aim := atan2(-flat.x, -flat.y)
	var at_hip := acos(clampf((thigh * thigh + length * length - shin * shin) / (2.0 * thigh * length), -1.0, 1.0))
	var at_knee := acos(clampf((thigh * thigh + shin * shin - length * length) / (2.0 * thigh * shin), -1.0, 1.0))
	# The hips may be turned (the counter-twist) and tipped: aim in their frame.
	var tilt := _hips.rotation.x
	return Vector2(aim + at_hip - tilt, -(PI - at_knee))


## The head follows the leaning torso (it isn't parented to it), unless it's your
## own head and you're looking through it.
func _apply_work_head() -> void:
	if _head_root == self:
		return
	# On the collar of the leaning torso, sunk with the hips into the knees.
	var sink := _crouch * smoothstep(0.0, 1.0, _stance)
	var offset := Vector3(0.0, WORK_NECK * (cos(_work.x) - 1.0) - sink, WORK_NECK * sin(_work.x) + _work.z)
	if _own_head:
		for child: Node in _head_root.get_children():
			if child is Camera3D and (child as Camera3D).current:
				offset = Vector3.ZERO
	if _head_root.get_parent() == self:
		# An NPC's own head pivot: its height is set every tick, its depth only here.
		_head_root.position.z = offset.z
		_head_root.position.y += offset.y
	else:
		# A player's Head: _apply_fall placed it this tick.
		_head_root.position += offset


## Where an arm hangs from, in world space: side 0 the right shoulder, 1 the left
## (the order of grip_points).
func shoulder_position(side: int) -> Vector3:
	if _arms.size() < 2:
		return global_position + Vector3(0.0, 1.28, 0.0)
	return _arms[1 - clampi(side, 0, 1)].global_position


## Which way an arm points from its shoulder toward its hand, in world space
## (side 0 right, 1 left). For tests.
func arm_direction(side: int) -> Vector3:
	if _arms.size() < 2:
		return Vector3.DOWN
	return -_arms[1 - clampi(side, 0, 1)].global_basis.y.normalized()


func _hold_frame() -> Transform3D:
	var parent := get_parent() as Node3D
	return parent.global_transform if parent != null else global_transform


## Aim each arm with a target at it (set_hold), blended with whatever the walk or
## a gesture did. The arm hangs along its pivot's -Y, so the pivot turns that axis
## onto the target; a target closer than the arm's length foreshortens the arm.
func _apply_hold(delta: float) -> void:
	var frame := _hold_frame()
	for side: int in 2:
		var arm := _arms[1 - side]
		var target := _hold_targets[side]
		if target.is_finite():
			_hold_last[side] = target
		var want := 1.0 if target.is_finite() and fallen <= 0.3 else 0.0
		_hold_weight[side] = move_toward(_hold_weight[side], want, delta / maxf(Constants.HOLD_BLEND_SECONDS, 0.001))
		if _hold_weight[side] <= 0.0:
			continue
		var parent := arm.get_parent() as Node3D
		var local := parent.global_transform.affine_inverse() * (frame * _hold_last[side]) - arm.position
		if local.length() < 0.01:
			continue
		var blend := smoothstep(0.0, 1.0, _hold_weight[side])
		arm.quaternion = arm.quaternion.slerp(Quaternion(Vector3.DOWN, local.normalized()), blend)
		var reach := clampf(local.length() / Constants.HOLD_ARM_REACH, Constants.HOLD_ARM_SHORTEST, Constants.HOLD_ARM_LONGEST)
		arm.scale = Vector3(1.0, lerpf(1.0, reach, blend), 1.0)


func is_gesturing() -> bool:
	return _gesture != ""


func current_gesture() -> String:
	return _gesture


## How fast the body is really moving across the ground, in m/s.
func speed() -> float:
	return _speed


## Flap the mouth for this long, and raise the brows a little.
func talk(seconds: float) -> void:
	_talk_left = maxf(_talk_left, seconds)


func _build_head(root: Node3D) -> void:
	var face := Node3D.new()
	face.name = "CartoonHead"
	root.add_child(face)
	_face = face
	var head := _MeshKit.new()
	head.blob(Vector3(0.0, 0.02, 0.0), Vector3(0.265, 0.27, 0.255), skin, {"detail": 3, "lumps": 0.0, "flat": false, "jitter": 0.0})
	# Ears, a small nose, and a little blush on the cheeks.
	for side: float in [-1.0, 1.0]:
		head.blob(Vector3(side * 0.258, 0.0, 0.0), Vector3(0.035, 0.055, 0.03), skin.darkened(0.05), {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0})
		head.blob(Vector3(side * 0.15, -0.06, -0.205), Vector3(0.05, 0.03, 0.02), skin.lerp(Color(0.95, 0.45, 0.45), 0.35), {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0, "shade": false})
	head.blob(Vector3(0.0, -0.025, -0.262), Vector3(0.035, 0.03, 0.025), skin.darkened(0.06), {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0})
	_on_head_layer(_kit_part(face, head.commit(), Vector3.ZERO, {"roughness": 0.7, "specular": 0.2}))
	for side: float in [-1.0, 1.0]:
		# Eyes sit flush in the face: flattened, so a profile never shows bug eyes.
		var eye := _pivot(face, Vector3(side * 0.095, 0.06, -0.228))
		_on_head_layer(_kit_part(eye, _blob_mesh(Vector3.ZERO, Vector3(0.068, 0.082, 0.03), EYE_WHITE, false), Vector3.ZERO, {"roughness": 0.25, "specular": 0.5}))
		var pupil := _kit_part(eye, _blob_mesh(Vector3.ZERO, Vector3(0.033, 0.04, 0.012), PUPIL, false), Vector3(side * -0.008, -0.005, -0.024), {"roughness": 0.2, "specular": 0.6})
		_on_head_layer(pupil)
		_pupils.append(pupil)
		_eyes.append(eye)
		var brow := _pivot(face, Vector3(side * 0.1, 0.16, -0.222))
		_on_head_layer(_kit_part(brow, _blob_mesh(Vector3.ZERO, Vector3(0.05, 0.013, 0.012), hair.darkened(0.3), false), Vector3.ZERO))
		brow.rotation.z = side * -0.12
		_brows.append(brow)
	_mouth = _pivot(face, Vector3(0.0, -0.115, -0.238))
	if grin:
		_on_head_layer(_kit_part(_mouth, _grin_mesh(), Vector3.ZERO))
	else:
		_on_head_layer(_kit_part(_mouth, _blob_mesh(Vector3.ZERO, Vector3(0.048, 0.013, 0.012), Color(0.32, 0.1, 0.1), false), Vector3.ZERO))
	if shades and shades_style == "aviator":
		_on_head_layer(_kit_part(face, _aviator_mesh(), Vector3.ZERO, {"roughness": 0.2, "specular": 0.8}))
	elif shades:
		var glasses := _MeshKit.new()
		for side: float in [-1.0, 1.0]:
			glasses.blob(Vector3(side * 0.095, 0.06, -0.255), Vector3(0.075, 0.05, 0.015), PUPIL, {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0, "shade": false})
		glasses.box(Vector3(0.0, 0.07, -0.258), Vector3(0.06, 0.015, 0.012), PUPIL)
		_on_head_layer(_kit_part(face, glasses.commit(), Vector3.ZERO, {"roughness": 0.15, "specular": 0.8}))
	match hat_style:
		"visor":
			_on_head_layer(_kit_part(face, _visor_mesh(), Vector3.ZERO))
		# Caps and hair sit clear of the head everywhere they cover it, and their
		# lumps only push outward, so the scalp never pokes through.
		"cap":
			var cap := _MeshKit.new()
			cap.blob(Vector3(0.0, 0.1, 0.01), Vector3(0.285, 0.21, 0.285), hat_color, {"detail": 2, "lumps": 0.0, "flat": false, "jitter": 0.0})
			cap.blob(Vector3(0.0, 0.07, -0.29), Vector3(0.17, 0.018, 0.12), hat_color.darkened(0.1), {"detail": 2, "lumps": 0.0, "flat": false, "jitter": 0.0})
			cap.blob(Vector3(0.0, 0.31, 0.01), Vector3(0.03, 0.015, 0.03), hat_color.darkened(0.15), {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0})
			# Hair peeking out at the back and sides.
			cap.blob(Vector3(0.0, -0.02, 0.12), Vector3(0.25, 0.12, 0.17), hair, {"detail": 2, "lumps": 0.15, "lump_scale": 3.0, "outward": true, "flat": false, "jitter": 0.0})
			_on_head_layer(_kit_part(face, cap.commit(), Vector3.ZERO))
		"hair":
			var mop := _MeshKit.new()
			mop.blob(Vector3(0.0, 0.14, 0.06), Vector3(0.28, 0.19, 0.27), hair, {"detail": 3, "lumps": 0.16, "lump_scale": 2.6, "outward": true, "flat": false, "jitter": 0.0, "seed": int(hair.r * 100.0)})
			# A fringe of tufts over the forehead, above the brows.
			for tuft: int in 3:
				mop.blob(Vector3((float(tuft) - 1.0) * 0.1, 0.235, -0.17), Vector3(0.075, 0.05, 0.065), hair, {"detail": 2, "lumps": 0.0, "flat": false, "jitter": 0.0})
			_on_head_layer(_kit_part(face, mop.commit(), Vector3.ZERO))


## Animates on physics ticks: the head carries a player's camera, and physics
## interpolation smooths everything that moves on ticks together.
func _physics_process(delta: float) -> void:
	if _hips == null:
		return
	_time += delta
	var now := global_position
	if _last_position != Vector3.INF and delta > 0.0:
		var moved := Vector2(now.x - _last_position.x, now.z - _last_position.z).length()
		# Teleports and rides would read as sprinting at hundreds of m/s. Ignore those.
		if moved / delta < 20.0:
			_speed = lerpf(_speed, moved / delta, clampf(delta * 10.0, 0.0, 1.0))
			_phase += moved * STRIDE
			var vel := Vector2(now.x - _last_position.x, now.z - _last_position.z) / delta
			_ground_vel = _ground_vel.lerp(vel, clampf(delta * 10.0, 0.0, 1.0))
	_last_position = now
	var state := int(get_parent().get_parent().get("anim_state")) if get_parent() != null and get_parent().get_parent() != null and "anim_state" in get_parent().get_parent() else 0
	var in_air := state == STATE_AIR
	_in_air = in_air
	var crouching := state == STATE_CROUCH
	var knocked := state == STATE_KNOCKED
	var owner_node := get_parent().get_parent() if get_parent() != null else null
	_straining = bool(owner_node.get("straining")) if owner_node != null and "straining" in owner_node else false
	_limping = bool(owner_node.get("limping")) if owner_node != null and "limping" in owner_node else false
	if owner_node != null and "foot_hurt" in owner_node:
		foot_hurt = int(owner_node.get("foot_hurt"))
	if foot_hurt == 1:
		_limping = true
	# Every peer sees stars when someone goes down, bonked or fainted.
	if knocked and fallen <= 0.0:
		dizzy(float(Constants.BONK_STUN_SECONDS["heavy"]))
	# Topple fast, get up a little slower.
	fallen = move_toward(fallen, 1.0 if knocked else 0.0, delta * (5.0 if knocked else 2.5))
	if _was_air and not in_air:
		_squash = 1.0
	_was_air = in_air
	_squash = maxf(0.0, _squash - delta * 5.0)
	# Riding along isn't walking, however fast the truck goes.
	if _sit_pose != 0:
		_speed = 0.0
	var walk := clampf(_speed / 5.0, 0.0, 1.4)
	var swing := sin(_phase) * 0.65 * walk
	_legs[0].rotation.x = swing
	_legs[1].rotation.x = -swing
	# Each knee flexes as its leg swings through, the foot clearing the ground.
	for index: int in _shins.size():
		var through := cos(_phase + PI * float(index))
		_shins[index].rotation.x = -Constants.BODY_WALK_KNEE * walk * maxf(through, 0.0)
		_shoes[index].rotation.x = 0.0
	if foot_hurt >= 2:
		# Hopping: the footless leg tucked up behind, a bounce on every hop.
		_legs[0].rotation.x = Constants.BODY_HOP_THIGH
		_shins[0].rotation.x = Constants.BODY_HOP_SHIN
		_legs[1].rotation.x = swing * 0.3
	elif _limping:
		# The hurt leg stays stiff and swings out; the hips lurch onto the good one.
		_legs[0].rotation.x = swing * 0.2
		_legs[0].rotation.z = -0.12
		swing *= 1.2
	# A hold (_apply_hold) last tick may have turned and foreshortened the arms.
	for arm: Node3D in _arms:
		arm.rotation.y = 0.0
		arm.scale = Vector3.ONE
	_arms[0].rotation.x = -swing * 0.9
	_arms[1].rotation.x = swing * 0.9
	var bounce := absf(sin(_phase)) * 0.06 * walk
	if foot_hurt >= 2:
		bounce = absf(sin(_phase * 1.5)) * 0.2 * walk
	elif _limping:
		bounce = maxf(0.0, sin(_phase)) * 0.11 * walk
	var breathe := sin(_time * 2.2) * 0.012 * (1.0 - walk)
	var drop := CROUCH_DROP if crouching else 0.0
	if _sit_pose == 1:
		drop = 0.82 - SIT_HIPS
	_hips.position.y = 0.82 + bounce - drop - _squash * 0.08
	# The head rides with the body, and a player's camera with it.
	_head_stand_y = lerpf(_head_stand_y, _head_base_y - drop + bounce * 0.6 - _squash * 0.06, clampf(delta * 12.0, 0.0, 1.0))
	_head_root.position.y = _head_stand_y
	_torso.rotation.x = -0.12 * walk
	_torso.scale = Vector3(1.0 + _squash * 0.15, 1.0 + breathe - _squash * 0.12, 1.0 + _squash * 0.15)
	for index: int in _legs.size():
		if crouching:
			# Squatting on bent knees, the feet under the hips.
			var squat := _leg_reach(index, Vector3(_legs[index].position.x * 1.2, SHOE_Y, 0.06 - 0.12 * float(index)))
			_legs[index].rotation.x = squat.x
			_shins[index].rotation.x = squat.y
			_shoes[index].rotation.x = -(squat.x + squat.y)
		if in_air:
			_legs[index].rotation.x = 0.5 if index == 0 else -0.25
			_shins[index].rotation.x = Constants.BODY_JUMP_SHINS.x if index == 0 else Constants.BODY_JUMP_SHINS.y
		if _sit_pose == 1:
			_legs[index].rotation.x = SIT_LEGS
	for index: int in _arms.size():
		var side := -1.0 if index == 0 else 1.0
		# Flailing up when airborne, the way cartoon people jump.
		_arms[index].rotation.z = side * (2.4 if in_air else 0.12 + 0.05 * sin(_time * 1.7 + index))
	# A player's Head node tilts fully with where they look, for the camera. A real
	# head tips much less, so the visible head only follows part of it.
	_face.rotation.x = -_head_root.rotation.x * (1.0 - HEAD_TILT_SHARE)
	_face_yaw = lerpf(_face_yaw, face_turn, clampf(delta * 6.0, 0.0, 1.0))
	_face.rotation.y = _face_yaw
	# Lean into turns a little: the body tips toward where the eyes lead.
	var lean := -eye_lead.x * 0.08 * walk
	if _limping:
		lean += 0.14 * walk * (0.5 + 0.5 * sin(_phase))
	_torso.rotation.z = lerpf(_torso.rotation.z, lean, clampf(delta * 8.0, 0.0, 1.0))
	_show_bandage()
	_show_foot()
	_apply_work(delta)
	_animate_gesture(delta)
	_apply_hold(delta)
	_animate_face(delta)
	_apply_fall(delta)
	_apply_work_head()


## In a seat: 1 sitting (Chefty's cab: hips down, legs out front), 2 riding
## standing (the bed: still, no walk cycle), 0 back on your feet. player.gd calls
## it every frame on every peer, from the riders the vehicle replicates.
func sit(pose: int = 1) -> void:
	_sit_pose = pose


## Lying on the back, limbs splayed, head and all, and stars circling while dizzy.
func _apply_fall(delta: float) -> void:
	var angle := fallen * FALL_ANGLE
	rotation.x = angle
	if _head_root != self and _head_root.get_parent() != self:
		_head_root.position = Vector3(0.0, _head_stand_y * cos(angle), _head_stand_y * sin(angle))
	if fallen > 0.01:
		for index: int in _legs.size():
			_legs[index].rotation.x = lerpf(_legs[index].rotation.x, -0.3 + 0.15 * float(index), fallen)
			_legs[index].rotation.z = lerpf(0.0, (-0.3 if index == 0 else 0.3), fallen)
			_shins[index].rotation.x = lerpf(_shins[index].rotation.x, Constants.BODY_FALLEN_SHIN, fallen)
			_shoes[index].rotation.x = lerpf(_shoes[index].rotation.x, 0.0, fallen)
		for index: int in _arms.size():
			_arms[index].rotation.z = lerpf(_arms[index].rotation.z, (-1.6 if index == 0 else 1.6) + 0.2 * sin(_time * 9.0 + index), fallen)
	else:
		for index: int in _legs.size():
			_legs[index].rotation.z = -0.12 if _limping and index == 0 else 0.0
	if _stars != null:
		_stars_left -= delta
		_stars.visible = _stars_left > 0.0
		if _stars.visible:
			_stars.rotation.y += delta * 6.0
			var top := _head_root.global_position if _head_root != null else global_position + Vector3.UP * 1.6
			_stars.global_position = top + Vector3(0.0, 0.42, 0.0)


## A mower's work: a cut foot gets a fat bandage over the shoe; a lost foot leaves
## a round bandaged stump where the shoe was.
func _show_foot() -> void:
	if _legs.is_empty() or _shins.is_empty():
		return
	var shoe := _shoes[0] if not _shoes.is_empty() else null
	if shoe != null:
		shoe.visible = foot_hurt < 2
	if foot_hurt == 1 and _foot_wrap == null:
		var kit := _MeshKit.new()
		kit.blob(Vector3(0.0, -0.74, -0.04), Vector3(0.1, 0.09, 0.17), Color(0.97, 0.96, 0.93), {"detail": 2, "lumps": 0.15, "lump_scale": 4.0, "outward": true, "flat": false, "jitter": 0.0})
		kit.blob(Vector3(0.0, -0.66, -0.12), Vector3(0.03, 0.03, 0.01), Color(0.85, 0.2, 0.2), {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0, "shade": false})
		_foot_wrap = _kit_part(_shins[0], kit.commit(), Vector3(0.0, KNEE, 0.0))
		_on_head_layer(_foot_wrap)
	if foot_hurt >= 2 and _stump == null:
		var kit := _MeshKit.new()
		kit.blob(Vector3(0.0, -0.72, 0.0), Vector3(0.085, 0.07, 0.085), Color(0.97, 0.96, 0.93), {"detail": 2, "lumps": 0.15, "lump_scale": 4.0, "outward": true, "flat": false, "jitter": 0.0})
		_stump = _kit_part(_shins[0], kit.commit(), Vector3(0.0, KNEE, 0.0))
		_on_head_layer(_stump)
	if _foot_wrap != null:
		_foot_wrap.visible = foot_hurt == 1
	if _stump != null:
		_stump.visible = foot_hurt >= 2


## A white bandage wrapped round the hurt leg while limping.
func _show_bandage() -> void:
	if not _limping:
		if _bandage != null:
			_bandage.visible = false
		return
	if _bandage == null:
		var kit := _MeshKit.new()
		for wrap: int in 4:
			kit.tube(PackedVector3Array([Vector3(0, -0.28 - float(wrap) * 0.07, 0), Vector3(0, -0.33 - float(wrap) * 0.07, 0.01)]), PackedFloat32Array([0.098, 0.098]), Color(0.96, 0.95, 0.92), 10, {"jitter": 0.0, "cap": false})
		# Around the shin, just under the knee.
		_bandage = _kit_part(_shins[0], kit.commit(), Vector3(0.0, KNEE - 0.08, 0.0))
		_on_head_layer(_bandage)
	_bandage.visible = true
	if mood == "neutral":
		mood = "worried"


## Stars circle this character's head for a while.
func dizzy(seconds: float) -> void:
	if _stars == null:
		_stars = Node3D.new()
		_stars.name = "DizzyStars"
		add_child(_stars)
		_stars.top_level = true
		var kit := _MeshKit.new()
		for index: int in 4:
			var angle := TAU * float(index) / 4.0
			var at := Vector3(cos(angle) * 0.3, 0.03 * float(index % 2), sin(angle) * 0.3)
			# A five-pointed star from two flattened cones would do; a squashed lumpy ball reads fine small.
			kit.blob(at, Vector3(0.07, 0.07, 0.025), Color(1.0, 0.85, 0.25), {"detail": 1, "lumps": 0.6, "lump_scale": 5.0, "outward": true, "flat": true, "jitter": 0.0, "shade": false, "seed": index})
		var view := _Stylized.instance(kit.commit(), {"roughness": 0.4, "specular": 0.4})
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_stars.add_child(view)
	_stars_left = seconds


func _animate_face(delta: float) -> void:
	_blink_in -= delta
	if _blink_in <= 0.0:
		_blink_left = 0.12
		_blink_in = randf_range(1.8, 4.5)
	_blink_left = maxf(0.0, _blink_left - delta)
	var eye_open := 0.12 if _blink_left > 0.0 else (0.6 if squinting else 1.0)
	if _straining:
		eye_open = 0.25
	if _gesture == "stretch" and _gesture_time > 0.4:
		eye_open = 0.15
	if _gesture == "startle":
		eye_open = 1.3
	for eye: Node3D in _eyes:
		eye.scale.y = lerpf(eye.scale.y, eye_open, clampf(delta * 25.0, 0.0, 1.0))
	_aim_pupils(delta)
	_talk_left = maxf(0.0, _talk_left - delta)
	var open := 0.0
	if _talk_left > 0.0:
		open = absf(sin(_time * 24.0))
	_mouth.scale = Vector3(1.0 - open * 0.3, 1.0 + open * 3.5, 1.0)
	var lift := 0.0
	var tilt := 0.0
	match mood:
		"raised":
			lift = 0.035
		"worried":
			lift = 0.015
			tilt = 0.35
		"angry":
			lift = -0.01
			tilt = -0.4
	if _talk_left > 0.0:
		lift += 0.02
	if _gesture == "startle" or _gesture == "wave":
		lift = 0.045
	_brow_lift = lerpf(_brow_lift, lift, clampf(delta * 10.0, 0.0, 1.0))
	_brow_tilt = lerpf(_brow_tilt, tilt, clampf(delta * 10.0, 0.0, 1.0))
	for index: int in _brows.size():
		var side := -1.0 if index == 0 else 1.0
		# Over sunglasses the brows sit a little higher, so they still show.
		_brows[index].position.y = 0.16 + _brow_lift + (BROW_OVER_SHADES if shades else 0.0)
		# Worried brows lift toward the middle, angry ones dip toward it.
		_brows[index].rotation.z = side * (-0.12 + _brow_tilt)
		if _straining:
			_brows[index].rotation.z = side * 0.35
			_brows[index].position.y = 0.13
	if _straining:
		# Teeth gritted, face red and trembling.
		_mouth.scale = Vector3(1.4, 0.6, 1.0)
		_face.position = Vector3(randf_range(-0.008, 0.008), randf_range(-0.006, 0.006), 0.0)
	elif _face != null and _face.position != Vector3.ZERO:
		_face.position = Vector3.ZERO
	if _gesture == "stretch" and _gesture_time > 0.4 and _gesture_time < 1.8:
		_mouth.scale = Vector3(0.8, 6.0, 1.0)
	elif _gesture == "startle":
		_mouth.scale = Vector3(0.6, 5.0, 1.0)


## Point the pupils at look_at_point, plus the turn lead, inside the eye.
func _aim_pupils(delta: float) -> void:
	var aim := eye_lead
	if _gesture == "watch":
		# Down and to the left, at the wrist.
		aim = Vector2(-0.7, -0.9)
	elif look_at_point != Vector3.INF and _face != null:
		var local := _face.global_transform.affine_inverse() * look_at_point
		# The face looks down -Z. Left-right and up-down as a share of the distance ahead.
		var ahead := maxf(0.3, -local.z)
		aim += Vector2(clampf(local.x / ahead, -1.0, 1.0), clampf((local.y - 0.06) / ahead, -1.0, 1.0))
	aim = aim.limit_length(1.0)
	for index: int in _pupils.size():
		var side := -1.0 if index == 0 else 1.0
		var rest := Vector3(side * -0.008, -0.005, -0.04)
		var target := rest + Vector3(aim.x * PUPIL_RANGE.x, aim.y * PUPIL_RANGE.y, 0.0)
		_pupils[index].position = _pupils[index].position.lerp(target, clampf(delta * 18.0, 0.0, 1.0))


## Gestures layer over walking: they mostly move the arms, sometimes the face.
func _animate_gesture(delta: float) -> void:
	if _gesture == "":
		return
	_gesture_time += delta
	var t := _gesture_time
	var fade := clampf(minf(t * 5.0, (_gesture_length - t) * 5.0), 0.0, 1.0)
	var right := _arms[1]
	var left := _arms[0]
	match _gesture:
		"wave":
			right.rotation.z = lerpf(right.rotation.z, 2.6 + 0.35 * sin(t * 14.0), fade)
		"scratch":
			right.rotation.z = lerpf(right.rotation.z, 2.3, fade)
			right.rotation.x = lerpf(right.rotation.x, -0.6 + 0.15 * sin(t * 20.0), fade)
			_face.rotation.z = 0.12 * fade
		"stretch":
			left.rotation.z = lerpf(left.rotation.z, -2.9, fade)
			right.rotation.z = lerpf(right.rotation.z, 2.9, fade)
			_torso.scale.y += 0.05 * fade
		"watch":
			# The left wrist up in front of the chest. A positive x turn swings a
			# hanging arm forward (-Z); negative swung these arms out behind.
			left.rotation.x = lerpf(left.rotation.x, 1.3, fade)
			left.rotation.z = lerpf(left.rotation.z, 0.6, fade)
			_face.rotation.x -= 0.35 * fade
		"shuffle":
			_legs[0].rotation.x = 0.25 * sin(t * 12.0) * fade
			_legs[1].rotation.x = -0.25 * sin(t * 12.0) * fade
		"cheer":
			left.rotation.z = lerpf(left.rotation.z, -2.7 - 0.3 * sin(t * 12.0), fade)
			right.rotation.z = lerpf(right.rotation.z, 2.7 + 0.3 * sin(t * 12.0), fade)
			_hips.position.y += absf(sin(t * 7.0)) * 0.12 * fade
		"flail":
			left.rotation.z = -2.2 - 0.6 * sin(t * 22.0)
			right.rotation.z = 2.2 + 0.6 * sin(t * 22.0 + 1.3)
		"startle":
			left.rotation.z = lerpf(left.rotation.z, -1.6, fade)
			right.rotation.z = lerpf(right.rotation.z, 1.6, fade)
			_hips.position.y += 0.12 * sin(clampf(t / 0.35, 0.0, 1.0) * PI)
		"look_around":
			face_turn = sin(t * 2.6) * 0.6
		"offer":
			# Both hands out, holding something for you to take.
			left.rotation.x = lerpf(left.rotation.x, 1.35, fade)
			right.rotation.x = lerpf(right.rotation.x, 1.35, fade)
			left.rotation.z = lerpf(left.rotation.z, -0.2, fade)
			right.rotation.z = lerpf(right.rotation.z, 0.2, fade)
		"windmill":
			# Winding up: the right arm goes round and round.
			right.rotation.x = -t * 16.0
			right.rotation.z = 0.5
			_torso.rotation.y = 0.2 * sin(t * 16.0)
		"punch":
			# The right fist straight out ahead, the right shoulder turned into it.
			var swing := sin(clampf(t / 0.3, 0.0, 1.0) * PI)
			right.rotation.x = 1.7 * swing
			right.rotation.z = 0.15
			_torso.rotation.y = 0.4 * swing
		"rake":
			# Both hands low on a handle, pulling toward the body: a hired hand at work.
			var pull := sin(t * 5.7)
			# Reaching out ahead (positive x) and pulling back, bent over the work
			# (a negative torso x leans forward, as walking does).
			left.rotation.x = lerpf(left.rotation.x, 0.9 + 0.45 * pull, fade)
			right.rotation.x = lerpf(right.rotation.x, 0.75 + 0.45 * pull, fade)
			left.rotation.z = lerpf(left.rotation.z, -0.25, fade)
			right.rotation.z = lerpf(right.rotation.z, 0.25, fade)
			_torso.rotation.x = lerpf(_torso.rotation.x, -0.18 - 0.08 * pull, fade)
		"stumble":
			_torso.rotation.x = lerpf(_torso.rotation.x, -0.6, fade)
			left.rotation.x = -2.0 * sin(t * 16.0)
			right.rotation.x = 2.0 * sin(t * 16.0)
		"point":
			# The right arm straight out ahead at whoever it means. A positive x
			# turn swings a hanging arm forward (-Z). The lead's megaphone stays
			# level, aimed where he points.
			right.rotation.x = lerpf(right.rotation.x, POINT_ARM, fade)
			right.rotation.z = lerpf(right.rotation.z, 0.04, fade)
			if _megaphone != null:
				_megaphone.rotation.x = -right.rotation.x * fade
		"scribble":
			# Writing a citation: the clipboard up in front, tilted toward the face,
			# the pencil hand scratching away at it.
			left.rotation.x = lerpf(left.rotation.x, SCRIBBLE_BOARD_ARM, fade)
			left.rotation.z = lerpf(left.rotation.z, 0.5, fade)
			right.rotation.x = lerpf(right.rotation.x, 0.95 + 0.07 * sin(t * 31.0), fade)
			right.rotation.z = lerpf(right.rotation.z, -0.55 + 0.05 * sin(t * 23.0), fade)
			_face.rotation.x -= 0.25 * fade
			if _clipboard != null:
				_clipboard.rotation.x = SCRIBBLE_BOARD_TILT * fade
	if t >= _gesture_length:
		if _gesture == "look_around":
			face_turn = 0.0
		_gesture = ""
		_rest_props()


func _on_head_layer(node: Node3D) -> void:
	var mesh := node as MeshInstance3D
	if mesh != null and _own_head:
		mesh.layers = 1 << (HEAD_LAYER - 1)


func _pivot(parent: Node3D, at: Vector3) -> Node3D:
	var node := Node3D.new()
	parent.add_child(node)
	node.position = at
	return node


## A smooth body part drawn with the stylized material, kept out of the shared look.
func _kit_part(parent: Node3D, mesh: Mesh, at: Vector3, options: Dictionary = {}) -> MeshInstance3D:
	var view := _Stylized.instance(mesh, options if not options.is_empty() else {"roughness": 0.85, "specular": 0.15})
	parent.add_child(view)
	view.position = at
	return view


func _blob_mesh(center: Vector3, size: Vector3, color: Color, shade: bool = true) -> ArrayMesh:
	var kit := _MeshKit.new()
	kit.blob(center, size, color, {"detail": 2, "lumps": 0.0, "flat": false, "jitter": 0.0, "shade": shade})
	return kit.commit()


func _limb_mesh(points: Array, radii: Array, color: Color) -> ArrayMesh:
	var kit := _MeshKit.new()
	kit.tube(PackedVector3Array(points), PackedFloat32Array(radii), color, 10, {"jitter": 0.0})
	kit.blob(points[0], Vector3.ONE * float(radii[0]), color, {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0})
	return kit.commit()


## Shirt from the hips to the shoulders: a hem that hangs over the pants and a
## collar. The arms' own shoulder balls round off the shoulders. Squashed front to back like a real chest.
func _torso_mesh(color: Color) -> ArrayMesh:
	var kit := _MeshKit.new()
	var points := PackedVector3Array([Vector3(0, -0.06, 0), Vector3(0, 0.08, 0), Vector3(0, 0.3, 0), Vector3(0, 0.46, 0), Vector3(0, 0.55, 0)])
	var radii := PackedFloat32Array([0.205, 0.2, 0.205, 0.19, 0.11])
	kit.tube(points, radii, color, 14, {"jitter": 0.0})
	kit.tube(PackedVector3Array([Vector3(0, 0.5, 0), Vector3(0, 0.58, 0)]), PackedFloat32Array([0.12, 0.1]), color.darkened(0.12), 12, {"jitter": 0.0})
	var mesh := kit.commit()
	return _squashed(mesh, Vector3(1.0, 1.0, 0.8))


## Sleeve, forearm, and a mitten hand with a thumb, hanging from the shoulder.
func _arm_mesh(side: float) -> ArrayMesh:
	var kit := _MeshKit.new()
	kit.blob(Vector3.ZERO, Vector3.ONE * 0.07, shirt, {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0})
	kit.tube(PackedVector3Array([Vector3(0, 0, 0), Vector3(0, -0.15, 0), Vector3(0, -0.27, 0)]), PackedFloat32Array([0.068, 0.065, 0.066]), shirt, 10, {"jitter": 0.0, "cap": false})
	kit.tube(PackedVector3Array([Vector3(0, -0.25, 0), Vector3(0, -0.45, 0)]), PackedFloat32Array([0.05, 0.045]), skin, 10, {"jitter": 0.0})
	kit.blob(Vector3(0.0, -0.52, 0.0), Vector3(0.05, 0.068, 0.04), skin, {"detail": 2, "lumps": 0.0, "flat": false, "jitter": 0.0})
	kit.blob(Vector3(side * -0.035, -0.49, -0.025), Vector3(0.02, 0.035, 0.02), skin, {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0})
	return kit.commit()


## A rounded shoe with a lighter sole, toes pointing forward (-Z).
func _shoe_mesh(color: Color, sole := Color(0.82, 0.78, 0.7)) -> ArrayMesh:
	var kit := _MeshKit.new()
	kit.blob(Vector3(0.0, 0.0, -0.03), Vector3(0.075, 0.055, 0.14), color, {"detail": 2, "lumps": 0.0, "flat": false, "jitter": 0.0})
	kit.blob(Vector3(0.0, -0.035, -0.03), Vector3(0.077, 0.018, 0.142), sole, {"detail": 2, "lumps": 0.0, "flat": false, "jitter": 0.0, "shade": false})
	return kit.commit()


# ---------------------------------------------------------------- the NICE BOYS
# Outfit parts (docs/ART.md, "The NICE BOYS"). The body is already over the
# character triangle budget, so everything here is blob detail 0 or 1, boxes, and
# tubes of 8 sides or fewer, never rbox (net/dev/cast_test.gd counts the extra).
# The exceptions match the body part they cover, so it can't poke through between
# facets (docs/DECISIONS.md, the NICE BOYS' look): the shorts, socks and stripe
# match the plain leg's 10, the collar and visor band the 12-sided shirt collar
# and the head, the megaphone 10 so the bell reads round. They cost 48 triangles
# (62 on the head NICE BOY) more than 8 sides would.

const _SMOOTH: Dictionary = {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0}


## The thigh under shorts: the shorts from the hip, bare skin down to the knee.
func _thigh_mesh(shorts: Color, shin: Color) -> ArrayMesh:
	var kit := _MeshKit.new()
	kit.blob(Vector3.ZERO, Vector3.ONE * 0.093, shorts, _SMOOTH)
	kit.tube(PackedVector3Array([Vector3(0, 0, 0), Vector3(0, -0.3, 0)]), PackedFloat32Array([0.096, 0.093]), shorts, 10, {"jitter": 0.0})
	kit.tube(PackedVector3Array([Vector3(0, -0.28, 0), Vector3(0, -KNEE, 0)]), PackedFloat32Array([0.058, 0.057]), shin, 8, {"jitter": 0.0, "cap": false})
	return kit.commit()


## From the knee (the origin) down: a round bare knee, the shin, and a white knee
## sock with a lavender stripe to the ankle.
func _leg_mesh(shin: Color, sock: Color) -> ArrayMesh:
	var kit := _MeshKit.new()
	var k := KNEE
	kit.blob(Vector3.ZERO, Vector3.ONE * 0.058, shin, {"detail": 0, "lumps": 0.0, "flat": false, "jitter": 0.0})
	kit.tube(PackedVector3Array([Vector3(0, 0, 0), Vector3(0, k - 0.51, 0)]), PackedFloat32Array([0.057, 0.055]), shin, 8, {"jitter": 0.0, "cap": false})
	kit.tube(PackedVector3Array([Vector3(0, k - 0.49, 0), Vector3(0, k - 0.74, 0)]), PackedFloat32Array([0.061, 0.064]), sock, 10, {"jitter": 0.0})
	kit.tube(PackedVector3Array([Vector3(0, k - 0.515, 0), Vector3(0, k - 0.54, 0)]), PackedFloat32Array([0.0635, 0.0635]), _NiceSeal.ROSETTE, 10, {"jitter": 0.0, "cap": false})
	return kit.commit()


## A plain shin hanging from a round knee.
func _knee_mesh(points: Array, radii: Array, color: Color) -> ArrayMesh:
	var kit := _MeshKit.new()
	kit.tube(PackedVector3Array(points), PackedFloat32Array(radii), color, 10, {"jitter": 0.0})
	kit.blob(points[0], Vector3.ONE * (float(radii[0]) + 0.004), color, {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0})
	return kit.commit()


## Gold-rimmed aviators: dark lenses, a top bar, and arms back to the ears.
func _aviator_mesh() -> ArrayMesh:
	var kit := _MeshKit.new()
	var thin := {"jitter": 0.0, "cap": false}
	for side: float in [-1.0, 1.0]:
		var middle := Vector3(side * 0.1, 0.07, -0.272)
		# Teardrop: a flat top, the bottom sagging lowest toward the outside.
		var rim := PackedVector3Array()
		for step: int in 15:
			var angle := TAU * float(step) / 14.0
			var s := sin(angle)
			var height := 0.062 * pow(s, 0.6) if s >= 0.0 else -0.1 * pow(-s, 0.85)
			var width := 0.082 + (0.012 * -s if cos(angle) * side > 0.0 and s < 0.0 else 0.0)
			rim.append(middle + Vector3(cos(angle) * width - side * 0.012 * minf(s, 0.0), height, -0.004))
		kit.tube(rim, PackedFloat32Array([0.0055]), GOLD, 4, thin)
		kit.blob(middle + Vector3(0.0, 0.005, 0.0), Vector3(0.08, 0.06, 0.01), LENS, {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0, "shade": false})
		kit.blob(middle + Vector3(side * 0.008, -0.035, 0.001), Vector3(0.074, 0.064, 0.009), LENS, {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0, "shade": false})
		kit.tube(PackedVector3Array([Vector3(side * 0.18, 0.12, -0.27), Vector3(side * 0.218, 0.115, -0.17), Vector3(side * 0.25, 0.1, -0.08), Vector3(side * 0.266, 0.09, 0.01)]), PackedFloat32Array([0.006]), GOLD, 4, thin)
	# The double bridge: a straight top bar right across, and a small arch between.
	kit.tube(PackedVector3Array([Vector3(-0.18, 0.13, -0.274), Vector3(0.0, 0.134, -0.286), Vector3(0.18, 0.13, -0.274)]), PackedFloat32Array([0.0065]), GOLD, 4, thin)
	kit.tube(PackedVector3Array([Vector3(-0.025, 0.1, -0.283), Vector3(0.0, 0.108, -0.287), Vector3(0.025, 0.1, -0.283)]), PackedFloat32Array([0.0055]), GOLD, 4, thin)
	return kit.commit()


## A wide fixed grin, curled up at the corners, with a row of teeth. In the mouth
## pivot's space; it follows the face's curve.
func _grin_mesh() -> ArrayMesh:
	var kit := _MeshKit.new()
	var lip := PackedVector3Array()
	var teeth := PackedVector3Array()
	for step: int in 9:
		var u := float(step) / 8.0 * 2.0 - 1.0
		var x := u * 0.075
		# The face's surface here, in the mouth pivot's space (it sits at z -0.238).
		var surface := -0.221 * sqrt(maxf(0.0, 1.0 - pow(x / 0.229, 2.0))) + 0.238
		lip.append(Vector3(x, 0.03 * u * u - 0.006, surface - 0.012))
		if absf(u) <= 0.75:
			teeth.append(Vector3(x * 0.95, 0.03 * u * u + 0.004, surface - 0.016))
	kit.tube(lip, PackedFloat32Array([0.013]), Color(0.3, 0.08, 0.1), 6, {"jitter": 0.0})
	kit.tube(teeth, PackedFloat32Array([0.0075]), Color(0.98, 0.97, 0.94), 5, {"jitter": 0.0})
	return kit.commit()


## A sun visor: a band round the head, a brim out front, hair poking out over the
## top and at the back. In the head's space.
func _visor_mesh() -> ArrayMesh:
	var kit := _MeshKit.new()
	# The scalp under the band, and short hair at the back and sides.
	kit.blob(Vector3(0.0, 0.15, 0.035), Vector3(0.226, 0.18, 0.226), hair, _SMOOTH)
	kit.blob(Vector3(0.0, 0.0, 0.12), Vector3(0.24, 0.14, 0.16), hair, {"detail": 1, "lumps": 0.12, "lump_scale": 3.0, "outward": true, "flat": false, "jitter": 0.0})
	# Tufts sticking up out of the open top.
	for tuft: int in 5:
		var angle := TAU * float(tuft) / 5.0 + 0.4
		var at := Vector3(cos(angle) * 0.1, 0.3 + 0.02 * float(tuft % 2), sin(angle) * 0.1 + 0.02)
		kit.blob(at, Vector3(0.085, 0.075, 0.085), hair, {"detail": 1, "lumps": 0.35, "lump_scale": 3.5, "outward": true, "flat": false, "jitter": 0.0, "seed": tuft})
	kit.blob(Vector3(0.0, 0.33, 0.02), Vector3(0.08, 0.07, 0.08), hair, {"detail": 1, "lumps": 0.35, "lump_scale": 3.5, "outward": true, "flat": false, "jitter": 0.0, "seed": 9})
	kit.tube(PackedVector3Array([Vector3(0, 0.2, 0), Vector3(0, 0.285, 0)]), PackedFloat32Array([0.232, 0.2]), hat_color, 12, {"jitter": 0.0, "cap": false})
	kit.blob(Vector3(0.0, 0.214, -0.318), Vector3(0.18, 0.016, 0.135), hat_color.darkened(0.08), _SMOOTH)
	return kit.commit()


## The NICE BOYS' uniform over the clothes. Every part is a named MeshInstance3D
## (OUTFIT_PARTS); the torso parts ride the torso, so they lean and breathe with it.
func _build_outfit() -> void:
	var lead := outfit == "nice_boy_lead"
	# A white polo collar, squashed front to back like the chest.
	var collar := _MeshKit.new()
	collar.tube(PackedVector3Array([Vector3(0, 0.47, 0), Vector3(0, 0.55, 0)]), PackedFloat32Array([0.188, 0.13]), SOCK, 12, {"jitter": 0.0, "cap": false})
	_kit_part(_torso, _squashed(collar.commit(), Vector3(1.0, 1.0, 0.82)), Vector3.ZERO).name = "Collar"
	# The lanyard: a red V from the collar down to the ID card, and the polo's flaps.
	var cord := _MeshKit.new()
	for side: float in [-1.0, 1.0]:
		cord.tube(PackedVector3Array([Vector3(side * 0.075, 0.49, -0.14), Vector3(side * 0.045, 0.42, -0.165), Vector3(side * 0.012, 0.335, -0.176)]), PackedFloat32Array([0.0075]), LANYARD, 4, {"jitter": 0.0})
		cord.box(Vector3(side * 0.04, 0.455, -0.163), Vector3(0.065, 0.045, 0.008), SOCK, Basis(Vector3.BACK, side * 0.5) * Basis(Vector3.RIGHT, -0.25))
	_kit_part(_torso, cord.commit(), Vector3.ZERO).name = "Lanyard"
	# The ID card: a lavender header, a photo, a name line.
	var card := _MeshKit.new()
	card.box(Vector3(0.0, 0.28, -0.171), Vector3(0.075, 0.095, 0.006), SOCK)
	card.box(Vector3(0.0, 0.315, -0.1745), Vector3(0.075, 0.02, 0.002), _NiceSeal.ROSETTE)
	card.box(Vector3(-0.016, 0.278, -0.1745), Vector3(0.028, 0.034, 0.002), Color(0.45, 0.55, 0.68))
	card.box(Vector3(0.017, 0.284, -0.1745), Vector3(0.026, 0.006, 0.002), _NiceSeal.INK)
	card.box(Vector3(0.017, 0.271, -0.1745), Vector3(0.026, 0.006, 0.002), _NiceSeal.INK)
	_kit_part(_torso, card.commit(), Vector3.ZERO).name = "Badge"
	# The Daisy Seal patch on the left breast, tilted to sit on the curve of the chest.
	var patch := _MeshKit.new()
	_NiceSeal.add(patch, Vector3(-0.103, 0.405, -0.138), 0.045, Vector3(-0.43, 0.0, -0.9))
	_kit_part(_torso, patch.commit(), Vector3.ZERO, {"roughness": 0.7, "specular": 0.2}).name = "Insignia"
	# The fanny pack on a strap round the hips, outside the shirt's hem.
	var pack := _MeshKit.new()
	var strap := PackedVector3Array()
	for step: int in 13:
		var angle := TAU * float(step) / 12.0
		strap.append(Vector3(cos(angle) * 0.224, -0.035, sin(angle) * 0.192))
	pack.tube(strap, PackedFloat32Array([0.013]), FANNY_PACK.darkened(0.45), 4, {"jitter": 0.0, "cap": false})
	pack.blob(Vector3(0.0, -0.04, -0.205), Vector3(0.105, 0.055, 0.04), FANNY_PACK, _SMOOTH)
	pack.box(Vector3(0.0, -0.025, -0.244), Vector3(0.12, 0.006, 0.004), SILVER)
	_kit_part(_hips, pack.commit(), Vector3.ZERO).name = "FannyPack"
	# Another seal on the front of the visor's band, above the brim.
	if hat_style == "visor" and _face != null:
		var badge := _MeshKit.new()
		_NiceSeal.add(badge, Vector3(0.0, 0.257, -0.214), 0.024, Vector3(0.0, 0.37, -1.0))
		var visor_seal := _kit_part(_face, badge.commit(), Vector3.ZERO, {"roughness": 0.7, "specular": 0.2})
		visor_seal.name = "VisorSeal"
		_on_head_layer(visor_seal)
	if lead:
		# A whistle on the lanyard, and a megaphone in the right hand.
		var whistle := _MeshKit.new()
		whistle.tube(PackedVector3Array([Vector3(0.05, 0.318, -0.18), Vector3(0.085, 0.312, -0.181)]), PackedFloat32Array([0.011, 0.009]), SILVER, 6, {"jitter": 0.0, "cap_start": true})
		whistle.blob(Vector3(0.052, 0.31, -0.18), Vector3(0.016, 0.016, 0.014), SILVER, {"detail": 0, "lumps": 0.0, "flat": false, "jitter": 0.0})
		_kit_part(_torso, whistle.commit(), Vector3.ZERO, {"roughness": 0.25, "specular": 0.7}).name = "Whistle"
		var horn := _MeshKit.new()
		var axis := 0.075
		horn.tube(PackedVector3Array([Vector3(0, axis, 0.08), Vector3(0, axis, -0.2)]), PackedFloat32Array([0.028, 0.1]), MEGAPHONE, 10, {"jitter": 0.0, "cap": false})
		horn.tube(PackedVector3Array([Vector3(0, axis, -0.15), Vector3(0, axis, -0.18)]), PackedFloat32Array([0.0845, 0.0955]), SOCK, 10, {"jitter": 0.0, "cap": false})
		horn.tube(PackedVector3Array([Vector3(0, axis, -0.19), Vector3(0, axis, -0.197)]), PackedFloat32Array([0.094, 0.095]), MEGAPHONE.darkened(0.3), 10, {"jitter": 0.0})
		horn.tube(PackedVector3Array([Vector3(0, axis, -0.196), Vector3(0, axis, -0.199)]), PackedFloat32Array([0.045, 0.045]), Color(0.18, 0.16, 0.16), 8, {"jitter": 0.0})
		horn.tube(PackedVector3Array([Vector3(0, axis, 0.13), Vector3(0, axis, 0.075)]), PackedFloat32Array([0.02, 0.026]), Color(0.18, 0.16, 0.16), 6, {"jitter": 0.0, "cap_start": true, "cap": false})
		horn.box(Vector3(0.0, 0.025, -0.01), Vector3(0.028, 0.075, 0.035), Color(0.18, 0.16, 0.16))
		_megaphone = _kit_part(_arms[1], horn.commit(), Vector3(0.0, -0.52, -0.01))
		_megaphone.name = "Megaphone"
		_on_head_layer(_megaphone)
	else:
		# A clipboard hanging from the left hand, paper facing out.
		var board := _MeshKit.new()
		board.box(Vector3(0.0, -0.1, 0.0), Vector3(0.18, 0.25, 0.012), CLIPBOARD)
		board.box(Vector3(0.0, -0.115, -0.0075), Vector3(0.16, 0.2, 0.003), SOCK)
		for line: int in 4:
			board.box(Vector3(-0.01 + float(line % 2) * 0.012, -0.065 - float(line) * 0.03, -0.0095), Vector3(0.1, 0.006, 0.0015), Color(0.4, 0.42, 0.55))
		board.box(Vector3(-0.055, -0.188, -0.0095), Vector3(0.02, 0.02, 0.0015), LANYARD)
		board.box(Vector3(0.0, 0.012, -0.009), Vector3(0.075, 0.032, 0.014), SILVER)
		_clipboard = _kit_part(_arms[0], board.commit(), Vector3(-0.02, -0.5, -0.052))
		_clipboard.name = "Clipboard"
		_on_head_layer(_clipboard)


func _squashed(mesh: ArrayMesh, scale_by: Vector3) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for index: int in vertices.size():
		vertices[index] = vertices[index] * scale_by
		normals[index] = (normals[index] / scale_by).normalized()
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var squashed := ArrayMesh.new()
	squashed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return squashed
