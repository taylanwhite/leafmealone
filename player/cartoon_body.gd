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
## "cap", "hair", or "none".
@export var hat_style := "hair"
@export var hat_color := Color(0.2, 0.2, 0.22)
## Dark glasses over the eyes, for the crew's placeholder look.
@export var shades := false

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
## Share of a player's look up and down that the visible head shows.
const HEAD_TILT_SHARE: float = 0.35
const GESTURE_SECONDS: Dictionary = {
	"wave": 1.4, "scratch": 1.6, "stretch": 2.2, "watch": 1.8, "shuffle": 1.2,
	"cheer": 1.8, "flail": 0.9, "startle": 0.8, "look_around": 2.4, "stumble": 0.9,
	"offer": 0.6,
}
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
	var shoe := Color(0.18, 0.14, 0.12)
	# Pelvis on the hips, the shirt's hem hanging over it from the torso.
	_kit_part(_hips, _blob_mesh(Vector3(0.0, -0.02, 0.0), Vector3(0.19, 0.13, 0.15), pants), Vector3.ZERO)
	_kit_part(_torso, _torso_mesh(shirt), Vector3.ZERO)
	for side: float in [-1.0, 1.0]:
		var leg := _pivot(_hips, Vector3(side * 0.1, 0.0, 0.0))
		_kit_part(leg, _limb_mesh([Vector3(0.0, 0.0, 0.0), Vector3(0.0, -0.36, 0.0), Vector3(0.0, -0.72, 0.0)], [0.088, 0.078, 0.07], pants), Vector3.ZERO)
		_kit_part(leg, _shoe_mesh(shoe), Vector3(0.0, -0.76, -0.04))
		_legs.append(leg)
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
	# Your own body, not just your head: looking down in first person, the torso
	# right under the camera filled the screen.
	if _own_head:
		for node: Node in find_children("*", "MeshInstance3D", true, false):
			_on_head_layer(node as Node3D)


## Play a gesture once: "wave", "scratch", "stretch", "watch", "shuffle",
## "cheer", "flail", "startle", "look_around", or "stumble". A new one replaces
## the current one.
func gesture(gesture_name: String) -> void:
	_gesture = gesture_name
	_gesture_time = 0.0
	_gesture_length = float(GESTURE_SECONDS.get(gesture_name, 1.5))


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
	_on_head_layer(_kit_part(_mouth, _blob_mesh(Vector3.ZERO, Vector3(0.048, 0.013, 0.012), Color(0.32, 0.1, 0.1), false), Vector3.ZERO))
	if shades:
		var glasses := _MeshKit.new()
		for side: float in [-1.0, 1.0]:
			glasses.blob(Vector3(side * 0.095, 0.06, -0.255), Vector3(0.075, 0.05, 0.015), PUPIL, {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0, "shade": false})
		glasses.box(Vector3(0.0, 0.07, -0.258), Vector3(0.06, 0.015, 0.012), PUPIL)
		_on_head_layer(_kit_part(face, glasses.commit(), Vector3.ZERO, {"roughness": 0.15, "specular": 0.8}))
	match hat_style:
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
	_last_position = now
	var state := int(get_parent().get_parent().get("anim_state")) if get_parent() != null and get_parent().get_parent() != null and "anim_state" in get_parent().get_parent() else 0
	var in_air := state == STATE_AIR
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
	var walk := clampf(_speed / 5.0, 0.0, 1.4)
	var swing := sin(_phase) * 0.65 * walk
	_legs[0].rotation.x = swing
	_legs[1].rotation.x = -swing
	if foot_hurt >= 2:
		# Hopping: the footless leg tucked up behind, a bounce on every hop.
		_legs[0].rotation.x = 0.9
		_legs[1].rotation.x = swing * 0.3
	elif _limping:
		# The hurt leg stays stiff and swings out; the hips lurch onto the good one.
		_legs[0].rotation.x = swing * 0.2
		_legs[0].rotation.z = -0.12
		swing *= 1.2
	_arms[0].rotation.x = -swing * 0.9
	_arms[1].rotation.x = swing * 0.9
	var bounce := absf(sin(_phase)) * 0.06 * walk
	if foot_hurt >= 2:
		bounce = absf(sin(_phase * 1.5)) * 0.2 * walk
	elif _limping:
		bounce = maxf(0.0, sin(_phase)) * 0.11 * walk
	var breathe := sin(_time * 2.2) * 0.012 * (1.0 - walk)
	var drop := CROUCH_DROP if crouching else 0.0
	_hips.position.y = 0.82 + bounce - drop - _squash * 0.08
	# The head rides with the body, and a player's camera with it.
	_head_stand_y = lerpf(_head_stand_y, _head_base_y - drop + bounce * 0.6 - _squash * 0.06, clampf(delta * 12.0, 0.0, 1.0))
	_head_root.position.y = _head_stand_y
	_torso.rotation.x = -0.12 * walk
	_torso.scale = Vector3(1.0 + _squash * 0.15, 1.0 + breathe - _squash * 0.12, 1.0 + _squash * 0.15)
	for index: int in _legs.size():
		if crouching:
			_legs[index].rotation.x = -0.9
		if in_air:
			_legs[index].rotation.x = 0.5 if index == 0 else -0.25
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
	_animate_gesture(delta)
	_animate_face(delta)
	_apply_fall(delta)


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
	if _legs.is_empty():
		return
	var shoe := _legs[0].get_child(1) as Node3D if _legs[0].get_child_count() > 1 else null
	if shoe != null:
		shoe.visible = foot_hurt < 2
	if foot_hurt == 1 and _foot_wrap == null:
		var kit := _MeshKit.new()
		kit.blob(Vector3(0.0, -0.74, -0.04), Vector3(0.1, 0.09, 0.17), Color(0.97, 0.96, 0.93), {"detail": 2, "lumps": 0.15, "lump_scale": 4.0, "outward": true, "flat": false, "jitter": 0.0})
		kit.blob(Vector3(0.0, -0.66, -0.12), Vector3(0.03, 0.03, 0.01), Color(0.85, 0.2, 0.2), {"detail": 1, "lumps": 0.0, "flat": false, "jitter": 0.0, "shade": false})
		_foot_wrap = _kit_part(_legs[0], kit.commit(), Vector3.ZERO)
		_on_head_layer(_foot_wrap)
	if foot_hurt >= 2 and _stump == null:
		var kit := _MeshKit.new()
		kit.blob(Vector3(0.0, -0.72, 0.0), Vector3(0.085, 0.07, 0.085), Color(0.97, 0.96, 0.93), {"detail": 2, "lumps": 0.15, "lump_scale": 4.0, "outward": true, "flat": false, "jitter": 0.0})
		_stump = _kit_part(_legs[0], kit.commit(), Vector3.ZERO)
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
		_bandage = _kit_part(_legs[0], kit.commit(), Vector3.ZERO)
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
		_brows[index].position.y = 0.16 + _brow_lift
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
			left.rotation.x = lerpf(left.rotation.x, -1.3, fade)
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
			left.rotation.x = lerpf(left.rotation.x, -1.35, fade)
			right.rotation.x = lerpf(right.rotation.x, -1.35, fade)
			left.rotation.z = lerpf(left.rotation.z, -0.2, fade)
			right.rotation.z = lerpf(right.rotation.z, 0.2, fade)
		"stumble":
			_torso.rotation.x = lerpf(_torso.rotation.x, -0.6, fade)
			left.rotation.x = -2.0 * sin(t * 16.0)
			right.rotation.x = 2.0 * sin(t * 16.0)
	if t >= _gesture_length:
		if _gesture == "look_around":
			face_turn = 0.0
		_gesture = ""


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
func _shoe_mesh(color: Color) -> ArrayMesh:
	var kit := _MeshKit.new()
	kit.blob(Vector3(0.0, 0.0, -0.03), Vector3(0.075, 0.055, 0.14), color, {"detail": 2, "lumps": 0.0, "flat": false, "jitter": 0.0})
	kit.blob(Vector3(0.0, -0.035, -0.03), Vector3(0.077, 0.018, 0.142), Color(0.82, 0.78, 0.7), {"detail": 2, "lumps": 0.0, "flat": false, "jitter": 0.0, "shade": false})
	return kit.commit()


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
