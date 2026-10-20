extends Node

## Authority: local, cosmetic. The part that makes a cartoon body feel alive
## (docs/FEEL.md): what it looks at, how it fidgets, how it reacts. It drives a
## player/cartoon_body.gd from things every peer already has (how the character
## turns and moves, its head pitch, the run event phase), so everyone sees the
## same kind of life with no extra network traffic. The small random choices
## differ per peer, which is fine for something nobody can compare.
##
## Players: eyes lead turns and glance at people nearby, idle fidgets, a wave
## for whoever walks up, a nervous look around when the crew is on the way, a
## startle when they arrive, arm-flailing panic while running from them, a
## stumble on hard turns at a sprint, and a cheer on payday.
## The crew: glances and an angry face while chasing. The clerk: glances,
## greetings, and fidgets.

const GLANCE_RANGE: float = 8.0
const GREET_DISTANCE: float = 4.5
## Someone must go this far away before walking up again gets another wave.
const GREET_RESET_DISTANCE: float = 8.0
const IDLE_AFTER_SECONDS: float = 3.5
const IDLE_GESTURES: Array[String] = ["look_around", "scratch", "stretch", "watch", "shuffle", "look_around", "scratch"]
## Eye lead past this (about 3 rad/s of turning) at a sprint for a moment can trip you up.
const HARD_TURN_LEAD: float = 0.9
const STUMBLE_COOLDOWN_SECONDS: float = 12.0
const SPRINT_SPEED: float = 6.5
## How strongly turning and looking up or down pull the eyes ahead.
const EYE_LEAD_GAIN: float = 0.3

## The character this brings to life: the node whose rotation is its facing.
var root: Node3D
## The cartoon body it drives.
var body: Node3D
## "player", "crew", or "clerk".
var role := "player"

var _rng := RandomNumberGenerator.new()
var _last_yaw: float = INF
var _last_pitch: float = INF
var _lead := Vector2.ZERO
var _still_for: float = 0.0
var _next_idle: float = 0.0
var _glance: Node3D
var _next_glance: float = 0.0
var _near: Dictionary = {}
var _stumble_cooldown: float = 0.0
var _hard_turn_for: float = 0.0
var _last_phase: int = 0


func _ready() -> void:
	_rng.randomize()
	_next_idle = _rng.randf_range(1.0, 4.0)
	if role == "player":
		Campaign.payout_ready.connect(func(_results: Array[Dictionary]) -> void:
			if is_instance_valid(body):
				body.call("gesture", "cheer")
		)


func _process(delta: float) -> void:
	if root == null or body == null or delta <= 0.0:
		return
	if not body.is_visible_in_tree():
		return
	var speed := float(body.call("speed"))
	_lead_eyes(delta)
	_pick_glance(delta)
	_aim(speed)
	body.set("squinting", speed > SPRINT_SPEED)
	_run_event(speed)
	_greet(speed)
	_idle(delta, speed)
	_stumble(delta, speed)


## The eyes get ahead of the head: turning left glances left, looking up glances up.
func _lead_eyes(delta: float) -> void:
	var yaw := root.global_rotation.y
	var pitch := float(root.get("head_pitch")) if "head_pitch" in root else 0.0
	var turn_rate := 0.0 if _last_yaw == INF else angle_difference(_last_yaw, yaw) / delta
	var pitch_rate := 0.0 if _last_pitch == INF else (pitch - _last_pitch) / delta
	_last_yaw = yaw
	_last_pitch = pitch
	var target := Vector2(clampf(-turn_rate * EYE_LEAD_GAIN, -1.0, 1.0), clampf(pitch_rate * EYE_LEAD_GAIN, -1.0, 1.0))
	_lead = _lead.lerp(target, clampf(delta * 10.0, 0.0, 1.0))
	body.set("eye_lead", _lead)


## Every couple of seconds, pick someone nearby to look at, or nobody.
func _pick_glance(delta: float) -> void:
	_next_glance -= delta
	if _next_glance > 0.0 and is_instance_valid(_glance):
		return
	_next_glance = _rng.randf_range(1.2, 3.5)
	_glance = null
	if _rng.randf() < 0.3:
		return
	# Bodies face -Z, but a root may not (the crew's is turned around), so use the body.
	var forward := -body.global_basis.z
	var best_score := 0.0
	for other: Node3D in _others():
		var to := other.global_position - root.global_position
		var distance := to.length()
		if distance > GLANCE_RANGE or distance < 0.3:
			continue
		var ahead := forward.dot(to / distance)
		if ahead < -0.2:
			continue
		var score := (1.0 + ahead) / distance * _rng.randf_range(0.6, 1.4)
		if score > best_score:
			best_score = score
			_glance = other


func _aim(speed: float) -> void:
	if not is_instance_valid(_glance) or not _glance.is_inside_tree() or _glance.global_position.distance_to(root.global_position) > GLANCE_RANGE:
		_glance = null
	if _glance == null:
		body.set("look_at_point", Vector3.INF)
		if body.call("current_gesture") != "look_around":
			body.set("face_turn", 0.0)
		return
	var head := _glance.global_position + Vector3(0.0, 1.55, 0.0)
	body.set("look_at_point", head)
	if body.call("current_gesture") == "look_around":
		return
	# Turn the face partway toward them, only when not running.
	var to := head - root.global_position
	var local := body.global_basis.inverse() * to
	var angle := atan2(-local.x, -local.z)
	body.set("face_turn", clampf(angle, -0.7, 0.7) * 0.6 if speed < 2.5 else 0.0)


func _run_event(speed: float) -> void:
	var director := get_tree().get_first_node_in_group("run_director")
	var phase := int(director.call("phase")) if director != null else 0
	var on_lot := role != "player" or Net.player_zone(root.name.to_int()) == Net.Zone.LOT
	match role:
		"crew":
			body.set("mood", "angry")
		_:
			body.set("mood", "worried" if phase != 0 and on_lot else "neutral")
	if phase != _last_phase and role == "player" and on_lot:
		if phase == 1:
			body.call("gesture", "look_around")
		elif phase == 2:
			body.call("gesture", "startle")
	_last_phase = phase
	# Running from the crew: arms over the head.
	if role == "player" and phase == 2 and on_lot and speed > SPRINT_SPEED * 0.8:
		var current := str(body.call("current_gesture"))
		if current == "" or current == "flail":
			body.call("gesture", "flail")


## A wave for whoever walks up, once until they go away again.
func _greet(speed: float) -> void:
	if role == "crew":
		return
	for other: Node3D in _others():
		var key := other.get_instance_id()
		var distance := other.global_position.distance_to(root.global_position)
		var was_near := bool(_near.get(key, true))
		if distance <= GREET_DISTANCE and not was_near:
			_near[key] = true
			if speed < 2.0 and not bool(body.call("is_gesturing")) and _rng.randf() < 0.65:
				_glance = other
				_next_glance = 2.5
				body.call("gesture", "wave")
		elif distance >= GREET_RESET_DISTANCE:
			_near[key] = false


func _idle(delta: float, speed: float) -> void:
	if speed > 0.3 or bool(body.call("is_gesturing")):
		_still_for = 0.0
		return
	_still_for += delta
	_next_idle -= delta
	if _still_for >= IDLE_AFTER_SECONDS and _next_idle <= 0.0:
		_next_idle = _rng.randf_range(3.0, 8.0)
		body.call("gesture", IDLE_GESTURES[_rng.randi() % IDLE_GESTURES.size()])


## Cornering too hard at a sprint now and then trips you up, with an oof.
func _stumble(delta: float, speed: float) -> void:
	_stumble_cooldown = maxf(0.0, _stumble_cooldown - delta)
	if role != "player" or speed < SPRINT_SPEED or absf(_lead.x) < HARD_TURN_LEAD:
		_hard_turn_for = 0.0
		return
	_hard_turn_for += delta
	if _hard_turn_for > 0.25 and _stumble_cooldown <= 0.0:
		_stumble_cooldown = STUMBLE_COOLDOWN_SECONDS
		if _rng.randf() < 0.4:
			body.call("gesture", "stumble")
			if root.has_method("say"):
				root.call("say", "vo_oof")


func _others() -> Array[Node3D]:
	var found: Array[Node3D] = []
	for group: String in ["players", "crew", "store_clerk"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var other := node as Node3D
			if other != null and other != root and _shown(other):
				found.append(other)
	return found


## Hidden players keep their node visible and hide only their Visual.
func _shown(other: Node3D) -> bool:
	var visual := other.get_node_or_null("Visual") as Node3D
	return visual.is_visible_in_tree() if visual != null else other.is_visible_in_tree()
