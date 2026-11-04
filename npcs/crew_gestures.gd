extends Node

## Authority: local, cosmetic. The NICE BOYS' catch poses (R2 chunk 2; docs/GAME.md
## "The NICE BOYS encounter (R2)"), layered over player/cartoon_body.gd's own walk
## and gestures. One of these sits under each NICE BOY's CartoonBody and runs right
## after it every physics tick (a child ticks after its parent), so whatever the
## body did this tick, the pose wins where it says so, blended in and out.
##
## Poses, by name (POSES): speedwalk (a gait overlay: stiff, elbow-pumping),
## lunge_windup, lunge, collar_grab, grin_hold, cite_scribble (loops), tear_page,
## slap_sticker, arm_link and escort_hum (the escort, loops), hop_out, hop_in,
## whiff_sprawl, investigate_peer, wave_off, driver_wheel, sit_bench, haul_reach
## and haul_up (the haul-up of someone knocked flat).
##
## crew_member.gd picks the pose from its replicated mode on every peer. When
## player/cartoon_body.gd has chunk 1's register_gesture, register_all() also puts
## the one-shot poses in its registry (so the studio and other chunks can play them
## by name); the crew itself always plays them through this node.

const POSES: Dictionary = {
	# name: [seconds (0 = held until changed), loops]
	"speedwalk": [0.0, true],
	"lunge_windup": [0.0, false],
	"lunge": [0.0, false],
	"collar_grab": [0.0, false],
	"grin_hold": [0.0, false],
	"cite_scribble": [0.0, true],
	"tear_page": [0.45, false],
	"slap_sticker": [0.4, false],
	"arm_link": [0.0, true],
	"escort_hum": [0.0, true],
	"hop_out": [0.0, false],
	"hop_in": [0.0, false],
	"whiff_sprawl": [0.0, false],
	"investigate_peer": [0.0, true],
	"wave_off": [1.2, false],
	"driver_wheel": [0.0, true],
	"sit_bench": [0.0, true],
	# R2b: the landing look-round and the spotted double take (crew_member.gd).
	"land_look": [0.9, false],
	"spot_take": [0.85, false],
	# R2c: a rescue's bonk lands on him (encounter.gd _rpc_freed): knocked back a
	# step, arms flung up, the clipboard flying, a woozy wobble with stars.
	"bonked": [1.5, false],
	# P1 catch (audit crew-13): someone knocked flat isn't pounced on. He bends over
	# them reaching for the collar (held through the steps over), then heaves them up
	# off the grass (a shot at the thaw, encounter.gd _play_gotcha).
	"haul_reach": [0.0, false],
	"haul_up": [0.6, false],
}
## Blend in and out, in seconds.
const BLEND_SECONDS: float = 0.12
## The haul-up's squat over someone on the ground: the hips this far down (m) and
## the back bent over this far (rad, forward), deep enough for the hand to reach
## a collar on the grass (the head rides the bend, _follow_head).
const HAUL_SQUAT: float = 0.32
const HAUL_BEND: float = -1.0
const _CartoonBody = preload("res://player/cartoon_body.gd")

var _body: Node3D
var _pose: String = ""
var _start: float = 0.0
var _length: float = 0.0
var _weight: float = 0.0
var _fading: String = ""
var _fade_start: float = 0.0
var _fade_length: float = 0.0
var _time: float = 0.0
## A one-shot that plays over the held pose (tear_page, slap_sticker, wave_off).
var _shot: String = ""
var _shot_time: float = 0.0
var _shot_hard: bool = false
## The haul-up (P1 catch): the body (a player's CartoonBody) whose collar his
## grabbing hand goes to in haul_reach and haul_up (net/run_events/encounter.gd).
var reach_body: Node3D
## The speed-walk gait, on top of whatever else (0..1, by how fast he goes).
var gait: float = 0.0


func _ready() -> void:
	_body = get_parent() as Node3D


## Hold this pose from now (for length seconds, 0 = until another), blending from
## the last one. "" lets go. t0 lets a late peer start partway in.
func hold(pose_name: String, length: float = 0.0, t0: float = 0.0) -> void:
	if pose_name == _pose:
		return
	_fading = _pose
	_fade_start = _start
	_fade_length = _length
	_pose = pose_name
	_start = _time - maxf(0.0, t0)
	_length = length
	_weight = 0.0 if _fading == "" else _weight


## Play a short one over the held pose. hard: it starts fully in (from the held
## pose's own last frame, the haul-up's heave out of its reach) and is the whole
## pose until it blends out into whatever is held then.
func shot(pose_name: String, hard: bool = false) -> void:
	_shot = pose_name
	_shot_time = 0.0
	_shot_hard = hard
	if hard and _pose == "haul_reach":
		# Out of the reach, into the hand on your shoulder under it (crew_member's
		# GOTCHA, which may reach this peer after the heave has started).
		hold("collar_grab")


func current() -> String:
	return _pose


## Puts the one-shot poses in CartoonBody's registry when chunk 1's
## register_gesture exists (has_method guard: it is a static on the script).
static var _registered: bool = false


static func register_all() -> void:
	if _registered:
		return
	_registered = true
	var body_script: Script = load("res://player/cartoon_body.gd")
	if body_script == null or not ("register_gesture" in body_script.get_script_method_list().map(func(m: Dictionary) -> String: return str(m["name"]))):
		return
	for pose_name: String in POSES:
		var seconds := float((POSES[pose_name] as Array)[0])
		var captured := pose_name
		body_script.call("register_gesture", pose_name, seconds if seconds > 0.0 else 1.0,
			func(body: Node3D, t01: float, _delta: float) -> void: _apply(_parts(body), captured, t01 * maxf(seconds, 1.0), t01, 1.0, 0.0))


func _physics_process(delta: float) -> void:
	if _body == null:
		return
	# A hit-stop (chunk 1's set_anim_speed) holds the pose too.
	if _body.has_method("anim_speed"):
		var scale_by := float(_body.call("anim_speed"))
		if scale_by <= 0.0:
			return
		delta *= scale_by
	_time += delta
	var parts := _parts(_body)
	if parts.is_empty():
		return
	var phase := float(_body.get("_phase"))
	# Where the body left the lean and the hips this tick, for the head (_follow_head).
	var lean_from := (parts["torso"] as Node3D).rotation.x
	var hips_from := (parts["hips"] as Node3D).position.y
	# The few pivots the body never resets itself are written absolutely from these.
	var extras: Dictionary = {}
	# A hard one-shot (the haul-up's heave) is the whole pose while it's fully in.
	var shot_whole := _shot != "" and _shot_hard and _shot_time + delta < float((POSES.get(_shot, [0.5, false]) as Array)[0]) - 0.08
	if gait > 0.01 and _pose == "" and not shot_whole:
		_apply(parts, "speedwalk", _time, 0.0, gait, phase, extras)
	if shot_whole:
		_fading = ""
	elif _fading != "":
		var fade_t := _time - _fade_start
		var out := clampf(1.0 - (_time - _start) / BLEND_SECONDS, 0.0, 1.0)
		if out <= 0.0:
			_fading = ""
		else:
			_apply(parts, _fading, fade_t, _t01(fade_t, _fade_length), out, phase, extras)
	if _pose != "":
		var t := _time - _start
		var weight := clampf(t / BLEND_SECONDS, 0.0, 1.0)
		if _length > 0.0:
			weight = minf(weight, clampf((_length - t) / BLEND_SECONDS, 0.0, 1.0))
			if t >= _length:
				_pose = ""
		_weight = weight
		if _pose != "" and not shot_whole:
			_apply(parts, _pose, t, _t01(t, _length), weight, phase, extras)
	if _shot != "":
		_shot_time += delta
		var length := float((POSES.get(_shot, [0.5, false]) as Array)[0])
		var weight := clampf(minf(_shot_time, length - _shot_time) / 0.08, 0.0, 1.0)
		if _shot_hard:
			weight = clampf((length - _shot_time) / 0.08, 0.0, 1.0)
		_apply(parts, _shot, _shot_time, _t01(_shot_time, length), weight, 0.0, extras)
		if _shot_time >= length:
			_shot = ""
			_shot_hard = false
	(parts["torso"] as Node3D).rotation.y = float(extras.get("torso_y", 0.0))
	(parts["hips"] as Node3D).rotation.z = float(extras.get("hips_z", 0.0))
	if parts["face"] != null:
		(parts["face"] as Node3D).rotation.z = float(extras.get("face_z", 0.0))
		if extras.has("face_y"):
			(parts["face"] as Node3D).rotation.y += float(extras["face_y"])
	_squat_legs(float(extras.get("squat", 0.0)))
	_reach(parts, float(extras.get("reach", 0.0)))
	_follow_head(parts, lean_from, hips_from)


## The haul-up's squat over someone on the ground, 0 to 1, t seconds into it (it
## starts as his walk over ends): down by the time the hand lands (CATCH_DOWN_BEND).
static func _haul_bend(t: float) -> float:
	return smoothstep(0.0, maxf(Constants.CATCH_DOWN_BEND, 0.05), t)


## Squatting (the haul-up): the feet planted under him on the grass, the knees taking
## up the drop of the hips (CartoonBody's own leg reach), by `share` (0 to 1).
func _squat_legs(share: float) -> void:
	if share <= 0.0 or not _body.has_method("_leg_reach"):
		return
	var legs: Array = _body.get("_legs")
	var shins: Array = _body.get("_shins")
	var shoes: Array = _body.get("_shoes")
	if legs.size() < 2 or shins.size() < 2 or shoes.size() < 2:
		return
	for index: int in 2:
		var leg := legs[index] as Node3D
		# Feet a little wide, the left a half step ahead (its -Z is forward).
		var foot := Vector3(leg.position.x * 1.5, 0.06, -0.12 if index == 0 else 0.1)
		var angles: Vector2 = _body.call("_leg_reach", index, foot)
		leg.rotation.x = lerpf(leg.rotation.x, angles.x, share)
		leg.rotation.z = lerpf(leg.rotation.z, 0.0, share)
		(shins[index] as Node3D).rotation.x = lerpf((shins[index] as Node3D).rotation.x, angles.y, share)
		(shoes[index] as Node3D).rotation.x = lerpf((shoes[index] as Node3D).rotation.x, -(angles.x + angles.y), share)


## The haul-up's grabbing hand on reach_body's collar, by `share`: the right arm
## swung round from the shoulder onto it (CartoonBody._aim_arm), wherever that body
## is drawn: lying on the grass, then coming up with it.
func _reach(parts: Dictionary, share: float) -> void:
	if share <= 0.0 or reach_body == null or not is_instance_valid(reach_body) or not _body.has_method("_aim_arm"):
		return
	var torso := reach_body.call("pose_part", "torso") as Node3D if reach_body.has_method("pose_part") else null
	if torso == null:
		return
	# The shirt's collar, at the front of the chest (a body faces its -Z).
	var collar := torso.global_transform * Vector3(0.0, 0.4, -0.1)
	_body.call("_aim_arm", parts["right"], collar, smoothstep(0.0, 1.0, share))


## The head isn't on the torso (CartoonBody: its own pivot, moved only with the
## body's work lean). A pose that bends the torso or drops the hips takes it along:
## round the hips by the change in lean, down by the change in hips, so the neck
## never shows a gap (audit crew-13 review: his head floated above his collar in a
## bend). Only an NPC's own head pivot; a player's Head is the camera's.
func _follow_head(parts: Dictionary, lean_from: float, hips_from: float) -> void:
	var head := parts.get("head") as Node3D
	if head == null or head.get_parent() != _body:
		return
	var lean_to := (parts["torso"] as Node3D).rotation.x
	var neck := float(_CartoonBody.WORK_NECK)
	var drop := (parts["hips"] as Node3D).position.y - hips_from
	if is_equal_approx(lean_to, lean_from) and is_zero_approx(drop):
		return
	head.position.y += neck * (cos(lean_to) - cos(lean_from)) + drop
	head.position.z += neck * (sin(lean_to) - sin(lean_from))


static func _t01(t: float, length: float) -> float:
	return clampf(t / length, 0.0, 1.0) if length > 0.0 else 0.0


## The pivots a pose turns: CartoonBody's pose_part (chunk 1) when it has it, else
## its own fields by the names _animate_gesture uses.
static func _parts(body: Node3D) -> Dictionary:
	if body == null:
		return {}
	if body.has_method("pose_part"):
		if body.call("pose_part", "arm_r") == null:
			return {}
		return {
			"right": body.call("pose_part", "arm_r"), "left": body.call("pose_part", "arm_l"),
			"leg_l": body.call("pose_part", "leg_l"), "leg_r": body.call("pose_part", "leg_r"),
			"torso": body.call("pose_part", "torso"), "hips": body.call("pose_part", "hips"),
			"face": body.call("pose_part", "face"), "head": body.call("pose_part", "head"), "clipboard": body.call("pose_part", "clipboard"),
			"megaphone": body.call("pose_part", "megaphone"),
		}
	var arms: Array = body.get("_arms") if "_arms" in body else []
	var legs: Array = body.get("_legs") if "_legs" in body else []
	if arms.size() < 2 or legs.size() < 2:
		return {}
	return {
		"right": arms[1], "left": arms[0], "leg_l": legs[0], "leg_r": legs[1],
		"torso": body.get("_torso"), "hips": body.get("_hips"), "face": body.get("_face"), "head": body.get("_head_root"),
		"clipboard": body.get("_clipboard"), "megaphone": body.get("_megaphone"),
	}


## Turns the parts toward pose_name by weight w. t is seconds into it, t01 its
## share (held poses: 0), phase the walk cycle.
static func _apply(parts: Dictionary, pose_name: String, t: float, t01: float, w: float, phase: float, extras: Dictionary = {}) -> void:
	var right: Node3D = parts["right"]
	var left: Node3D = parts["left"]
	var leg_l: Node3D = parts["leg_l"]
	var leg_r: Node3D = parts["leg_r"]
	var torso: Node3D = parts["torso"]
	var hips: Node3D = parts["hips"]
	var face: Node3D = parts["face"]
	var clipboard: Node3D = parts["clipboard"]
	if w <= 0.0:
		return
	match pose_name:
		"speedwalk":
			# Elbows pumping, arms bent and swinging hard, the torso bolt upright and
			# the hips wagging: a speed-walker who means business.
			var swing := sin(phase)
			right.rotation.x = lerpf(right.rotation.x, 0.55 + 0.75 * swing, w)
			left.rotation.x = lerpf(left.rotation.x, 0.55 - 0.75 * swing, w)
			right.rotation.z = lerpf(right.rotation.z, 0.28, w)
			left.rotation.z = lerpf(left.rotation.z, -0.28, w)
			torso.rotation.x = lerpf(torso.rotation.x, 0.04, w)
			extras["torso_y"] = float(extras.get("torso_y", 0.0)) + 0.16 * swing * w
			extras["hips_z"] = float(extras.get("hips_z", 0.0)) + 0.06 * sin(phase * 2.0) * w
		"lunge_windup":
			# Knees bent, weight back, clipboard raised like a net, the grabbing hand
			# drawn back: the "Ah-ah-ah!" crouch. It sinks all the way in over the
			# first third of the wind-up (R2b: deep enough to read from first person
			# at 2.6 m, so there's time to sidestep), with a quiver of effort.
			# From the front it reads as a goalkeeper about to pounce: low, feet
			# wide, both arms out wide and forward, hands open.
			var sink := smoothstep(0.0, 0.14, t)
			var quiver := 0.05 * sin(t * 42.0) * sink
			hips.position.y -= 0.16 * w * sink
			torso.rotation.x = lerpf(torso.rotation.x, -0.22 + quiver * 0.5, w)
			leg_l.rotation.x = lerpf(leg_l.rotation.x, 0.25, w)
			leg_r.rotation.x = lerpf(leg_r.rotation.x, -0.15, w)
			leg_l.rotation.z = lerpf(leg_l.rotation.z, -0.28 * sink, w)
			leg_r.rotation.z = lerpf(leg_r.rotation.z, 0.28 * sink, w)
			left.rotation.x = lerpf(left.rotation.x, 0.55, w)
			left.rotation.z = lerpf(left.rotation.z, -1.15 - quiver, w)
			right.rotation.x = lerpf(right.rotation.x, 0.55, w)
			right.rotation.z = lerpf(right.rotation.z, 1.15 + quiver, w)
			if face != null:
				face.rotation.x -= 0.12 * w
		"lunge":
			# All in: lean forward, the grabbing arm straight out, legs split. Not so
			# far that his face ends up in yours (R2b: he stops at arm's length).
			hips.position.y -= 0.08 * w
			torso.rotation.x = lerpf(torso.rotation.x, -0.3, w)
			right.rotation.x = lerpf(right.rotation.x, 1.65, w)
			right.rotation.z = lerpf(right.rotation.z, 0.05, w)
			left.rotation.x = lerpf(left.rotation.x, -0.9, w)
			left.rotation.z = lerpf(left.rotation.z, -0.4, w)
			leg_l.rotation.x = lerpf(leg_l.rotation.x, 0.75, w)
			leg_r.rotation.x = lerpf(leg_r.rotation.x, -0.7, w)
		"haul_reach":
			# Held once his walk over ends (crew_member.gd), squatting down over
			# someone on the ground: knees bent, back bent well over (the head rides
			# it, _follow_head), the grabbing hand down on their collar (_reach) and
			# the clipboard hand out on his knee for balance, eyes on them.
			var bend := _haul_bend(t)
			hips.position.y -= HAUL_SQUAT * bend * w
			torso.rotation.x = lerpf(torso.rotation.x, HAUL_BEND * bend, w)
			right.rotation.x = lerpf(right.rotation.x, 0.6 * bend, w)
			left.rotation.x = lerpf(left.rotation.x, 0.75 * bend, w)
			left.rotation.z = lerpf(left.rotation.z, -0.35 * bend, w)
			if face != null:
				face.rotation.x += 0.3 * w * bend
			extras["squat"] = maxf(float(extras.get("squat", 0.0)), bend * w)
			extras["reach"] = maxf(float(extras.get("reach", 0.0)), smoothstep(0.3, 0.95, t / maxf(Constants.CATCH_DOWN_BEND, 0.05)) * w)
		"haul_up":
			# The heave: up out of the squat with the weight of you, leaning back on
			# it at the top, the hand on your collar the whole way up (_reach), then
			# letting go into the hand on your shoulder (collar_grab) as he stands tall.
			var heave := smoothstep(0.0, 0.8, t01)
			var lean_back := sin(clampf((t01 - 0.35) / 0.65, 0.0, 1.0) * PI)
			hips.position.y -= HAUL_SQUAT * (1.0 - heave) * w
			torso.rotation.x = lerpf(torso.rotation.x, lerpf(HAUL_BEND, 0.06, heave) + 0.18 * lean_back, w)
			right.rotation.x = lerpf(right.rotation.x, lerpf(0.6, 1.3, heave), w)
			left.rotation.x = lerpf(left.rotation.x, lerpf(0.75, 0.95, heave), w)
			left.rotation.z = lerpf(left.rotation.z, lerpf(-0.35, 0.42, heave), w)
			if face != null:
				face.rotation.x += lerpf(0.3, -0.06, heave) * w
			extras["squat"] = maxf(float(extras.get("squat", 0.0)), (1.0 - heave) * w)
			extras["reach"] = maxf(float(extras.get("reach", 0.0)), (1.0 - smoothstep(0.7, 1.0, t01)) * w)
		"collar_grab", "grin_hold":
			# The hand on your shoulder, the clipboard tucked at his chest, standing
			# tall. grin_hold adds a pleased little head tilt and a bob of breath.
			var breathe := 0.02 * sin(t * 2.4)
			right.rotation.x = lerpf(right.rotation.x, 1.3, w)
			right.rotation.z = lerpf(right.rotation.z, -0.2, w)
			left.rotation.x = lerpf(left.rotation.x, 0.95, w)
			left.rotation.z = lerpf(left.rotation.z, 0.42, w)
			torso.rotation.x = lerpf(torso.rotation.x, 0.06 + breathe, w)
			if pose_name == "grin_hold" and face != null:
				extras["face_z"] = float(extras.get("face_z", 0.0)) + 0.09 * w
				face.rotation.x += 0.06 * w
		"cite_scribble":
			# Writing you up: the board up and tilted to the face, the pencil going.
			left.rotation.x = lerpf(left.rotation.x, 1.1, w)
			left.rotation.z = lerpf(left.rotation.z, 0.5, w)
			right.rotation.x = lerpf(right.rotation.x, 0.95 + 0.08 * sin(t * 31.0), w)
			right.rotation.z = lerpf(right.rotation.z, -0.55 + 0.06 * sin(t * 23.0), w)
			torso.rotation.x = lerpf(torso.rotation.x, 0.05, w)
			if face != null:
				face.rotation.x -= 0.25 * w
			if clipboard != null:
				clipboard.rotation.x = 1.1 * w
		"tear_page":
			# Rrrip: the pencil hand yanks up and out.
			var yank := sin(clampf(t01 * 1.4, 0.0, 1.0) * PI * 0.5)
			right.rotation.x = lerpf(right.rotation.x, 1.0 - 0.7 * yank, w)
			right.rotation.z = lerpf(right.rotation.z, 1.3 * yank, w)
		"slap_sticker":
			# Out and flat onto your chest, a quick pat.
			var pat := sin(clampf(t01 * 2.0, 0.0, 1.0) * PI)
			right.rotation.x = lerpf(right.rotation.x, 1.45 * pat, w)
			right.rotation.z = lerpf(right.rotation.z, -0.1, w)
		"arm_link":
			# Arm hooked through yours on his right, the other swinging jauntily, a
			# spring in his step.
			right.rotation.x = lerpf(right.rotation.x, 0.35, w)
			right.rotation.z = lerpf(right.rotation.z, 0.62, w)
			left.rotation.x = lerpf(left.rotation.x, 0.9 * sin(phase), w)
			hips.position.y += absf(sin(phase)) * 0.05 * w
		"escort_hum":
			right.rotation.x = lerpf(right.rotation.x, 0.35, w)
			right.rotation.z = lerpf(right.rotation.z, 0.62, w)
			left.rotation.x = lerpf(left.rotation.x, 0.9 * sin(phase), w)
			hips.position.y += absf(sin(phase)) * 0.05 * w
			extras["face_z"] = float(extras.get("face_z", 0.0)) + 0.1 * sin(t * 3.0) * w
		"hop_out", "hop_in":
			# Stooped steps to the sill, then crouch, spring, tuck, land with a knee
			# bounce (hop_in: the hop up first, then the steps to the seat). u runs the hop.
			var walk_share := 0.45
			var u := (t01 - walk_share) / (1.0 - walk_share) if pose_name == "hop_out" else t01 / (1.0 - walk_share)
			var crouch := 0.0
			var air := 0.0
			if u < 0.0 or u > 1.0:
				# Stepping along inside the van, head ducked under the roof.
				torso.rotation.x = lerpf(torso.rotation.x, -0.35, w)
				hips.position.y -= 0.06 * w
				u = clampf(u, 0.0, 1.0)
				w *= 0.0
			elif u < 0.2:
				crouch = u / 0.2
			elif u < 0.8:
				air = sin((u - 0.2) / 0.6 * PI)
			else:
				crouch = sin((u - 0.8) / 0.2 * PI) * 1.2
			hips.position.y -= 0.14 * crouch * w
			torso.rotation.x = lerpf(torso.rotation.x, -0.2 * crouch, w)
			leg_l.rotation.x = lerpf(leg_l.rotation.x, 0.5 * crouch + 0.6 * air, w)
			leg_r.rotation.x = lerpf(leg_r.rotation.x, 0.3 * crouch - 0.3 * air, w)
			right.rotation.z = lerpf(right.rotation.z, 0.2 + 1.3 * air, w)
			left.rotation.z = lerpf(left.rotation.z, -0.2 - 1.3 * air, w)
			right.rotation.x = lerpf(right.rotation.x, -0.4 * crouch, w)
			left.rotation.x = lerpf(left.rotation.x, -0.4 * crouch, w)
		"whiff_sprawl":
			# Grabbed air: pitched forward, arms windmilling, one leg kicked back,
			# then hauling himself upright.
			var down := sin(clampf(t / 0.9, 0.0, 1.0) * PI)
			hips.position.y -= 0.22 * down * w
			torso.rotation.x = lerpf(torso.rotation.x, -1.0 * down, w)
			right.rotation.x = lerpf(right.rotation.x, 2.2 * sin(t * 15.0), w)
			left.rotation.x = lerpf(left.rotation.x, -2.2 * sin(t * 15.0), w)
			leg_r.rotation.x = lerpf(leg_r.rotation.x, -0.9 * down, w)
		"investigate_peer":
			# Bent over something on the lawn, hands on knees, nose first.
			hips.position.y -= 0.06 * w
			torso.rotation.x = lerpf(torso.rotation.x, -0.75, w)
			right.rotation.x = lerpf(right.rotation.x, 0.65, w)
			left.rotation.x = lerpf(left.rotation.x, 0.65, w)
			if face != null:
				face.rotation.x += 0.35 * w
				face.rotation.y += 0.25 * sin(t * 1.6) * w
		"wave_off":
			right.rotation.z = lerpf(right.rotation.z, 2.5 + 0.35 * sin(t * 13.0), w)
		"driver_wheel":
			# Both hands on the wheel, a little steering wiggle.
			right.rotation.x = lerpf(right.rotation.x, 1.15, w)
			left.rotation.x = lerpf(left.rotation.x, 1.15, w)
			right.rotation.z = lerpf(right.rotation.z, -0.18 + 0.05 * sin(t * 1.3), w)
			left.rotation.z = lerpf(left.rotation.z, 0.18 + 0.05 * sin(t * 1.3), w)
		"sit_bench":
			# Hands on the knees, sitting up straight, ready for duty.
			right.rotation.x = lerpf(right.rotation.x, 0.8, w)
			left.rotation.x = lerpf(left.rotation.x, 0.8, w)
		"land_look":
			# Down from the van: a tug at the visor's brim, then the head turns left,
			# right, and back to front. t01 runs over the whole look.
			var tug := sin(clampf(t01 / 0.35, 0.0, 1.0) * PI)
			right.rotation.x = lerpf(right.rotation.x, 2.6 * tug, w)
			right.rotation.z = lerpf(right.rotation.z, -0.3 * tug, w)
			var look := clampf((t01 - 0.25) / 0.75, 0.0, 1.0)
			extras["face_y"] = 0.75 * sin(look * TAU) * w
		"bonked":
			# Hit: snapped back, arms flung up and out (0-0.18 s); then a stagger back
			# on wobbly legs, arms windmilling for balance (to 0.9 s); then a woozy
			# sway, head lolling round, a hand up to the visor (to 1.5 s).
			var hit := sin(clampf(t / 0.18, 0.0, 1.0) * PI * 0.5)
			var stagger := clampf((t - 0.12) / 0.78, 0.0, 1.0)
			var woozy := clampf((t - 0.8) / 0.7, 0.0, 1.0)
			var reel := hit * (1.0 - 0.6 * stagger)
			torso.rotation.x = lerpf(torso.rotation.x, 0.5 * reel - 0.15 * woozy, w)
			hips.position.y -= (0.1 * reel + 0.05 * sin(stagger * PI)) * w
			var mill := sin(t * 15.0) * (1.0 - woozy)
			right.rotation.z = lerpf(right.rotation.z, 2.3 * reel + 1.3 * mill * stagger + 0.4 * woozy, w)
			left.rotation.z = lerpf(left.rotation.z, -2.3 * reel + 1.3 * mill * stagger - 0.3 * woozy, w)
			right.rotation.x = lerpf(right.rotation.x, -0.5 * reel + 2.4 * woozy, w)
			left.rotation.x = lerpf(left.rotation.x, -0.5 * reel + 0.4 * mill, w)
			# Stepping back: the legs split and swap under him.
			var step := sin(stagger * PI * 3.0) * (1.0 - woozy)
			leg_l.rotation.x = lerpf(leg_l.rotation.x, -0.55 * step - 0.2 * reel, w)
			leg_r.rotation.x = lerpf(leg_r.rotation.x, 0.45 * step + 0.15 * reel, w)
			extras["hips_z"] = float(extras.get("hips_z", 0.0)) + 0.12 * sin(t * 9.0) * stagger * w
			extras["face_z"] = float(extras.get("face_z", 0.0)) + 0.3 * sin(t * 7.0) * maxf(stagger, woozy) * w
			extras["face_y"] = float(extras.get("face_y", 0.0)) + 0.35 * cos(t * 7.0) * woozy * w
			if clipboard != null:
				clipboard.rotation.x = lerpf(clipboard.rotation.x, -2.0 * reel, w)
		"spot_take":
			# The double take: a hop of surprise (0-0.15 s), then the arm shoots out
			# at you, straight and level, leaning in behind it.
			var hop := sin(clampf(t / 0.15, 0.0, 1.0) * PI)
			var out := smoothstep(0.08, 0.2, t)
			hips.position.y += 0.08 * hop * w
			torso.rotation.x = lerpf(torso.rotation.x, 0.2 * hop - 0.12 * out, w)
			right.rotation.x = lerpf(right.rotation.x, 1.55 * out, w)
			right.rotation.z = lerpf(right.rotation.z, 0.04, w)
			left.rotation.z = lerpf(left.rotation.z, -0.5 * hop - 0.15, w)
			if parts["megaphone"] != null:
				(parts["megaphone"] as Node3D).rotation.x = -right.rotation.x * w
