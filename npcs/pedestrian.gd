extends Node3D

## Authority: local, cosmetic, but the same on every peer. Someone out for a walk
## on the sidewalk: a cartoon person strolling back and forth along a route.
## Where they are is a pure function of their seed and Net.server_time(), so every
## peer sees them in the same spot with no network traffic (docs/NETCODE.md).
## They glance at people and fidget like everyone else (player/character_life.gd).
##
## Bonkable: the host spots a thrown item reaching them (net/components/net_prop.gd)
## and tells every peer, which calls on_bonked here. They get shoved, flinch,
## stumble, or go flat, then get up angry and walk back to their route. Who they
## are, what they say, and any jokes about them are design decisions; they only
## make the shared goofy noises.

const _CartoonBody = preload("res://player/cartoon_body.gd")
const _CharacterLife = preload("res://player/character_life.gd")
## Matches player.gd's AnimState: IDLE, WALK, KNOCKED.
const STATE_WALK: int = 1
const STATE_KNOCKED: int = 5
const ANGRY_SECONDS: float = 2.0

## Read by player/cartoon_body.gd (its parent's parent): knocked flat or not.
var anim_state: int = STATE_WALK
## Run over by a mower: 1 cut, 2 the foot came off. They heal after a while.
var foot_hurt: int = 0
var _heal_left: float = 0.0
var route_from := Vector3.ZERO
var route_to := Vector3.ZERO
var speed: float = 1.3
var phase: float = 0.0
var seed_value: int = 0

var _body: Node3D
var _voice: AudioStreamPlayer3D
## Knocked off the route: where they are, how fast they're sliding, and how long
## until they're up and over it. Then they walk back to the route.
var _free: bool = false
var _free_at := Vector3.ZERO
var _slide := Vector3.ZERO
var _down_left: float = 0.0
var _angry_left: float = 0.0


func _ready() -> void:
	add_to_group("bonkable")
	var visual := Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	_body = _CartoonBody.new()
	_body.name = "CartoonBody"
	_body.call("dress_from_seed", seed_value)
	visual.add_child(_body)
	_body.call("build")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	visual.scale = Vector3.ONE * rng.randf_range(0.88, 1.08)
	var life := _CharacterLife.new()
	life.name = "Life"
	life.root = self
	life.body = _body
	life.role = "clerk"
	_body.add_child(life)
	_voice = AudioStreamPlayer3D.new()
	_voice.position.y = 1.6
	_voice.unit_size = 5.0
	add_child(_voice)
	_place(0.0)
	reset_physics_interpolation()


## Every peer moves them the same way on physics ticks.
func _physics_process(delta: float) -> void:
	_place(delta)


## A mower got their foot. Called on every peer.
func hurt_foot(level: int, heading: Vector3) -> void:
	if level >= 2 and foot_hurt < 2:
		var lot := get_tree().get_first_node_in_group("job_lot")
		load("res://props/lost_foot.gd").launch(lot if lot != null else get_parent(), global_position, heading, Color(0.18, 0.14, 0.12), _body.get("skin"))
	foot_hurt = maxi(foot_hurt, level)
	_heal_left = 90.0
	on_bonked(heading * 2.0, "medium")
	_say("vo_yelp")


## Bonked by a thrown item. Called on every peer.
func on_bonked(push: Vector3, tier: String) -> void:
	match tier:
		"light":
			_body.call("gesture", "startle")
			_angry_left = ANGRY_SECONDS * 0.6
		"medium":
			_body.call("gesture", "stumble")
			_angry_left = ANGRY_SECONDS
		_:
			_down_left = float(Constants.BONK_STUN_SECONDS["heavy"])
			_body.call("dizzy", _down_left)
			_angry_left = ANGRY_SECONDS
	if not _free:
		_free = true
		_free_at = position
	_slide = Vector3(push.x, 0.0, push.z)
	_say("vo_oof" if tier != "light" else "vo_eh")


func _place(delta: float) -> void:
	if foot_hurt > 0:
		_heal_left -= delta
		if _heal_left <= 0.0:
			foot_hurt = 0
	var length := maxf(route_from.distance_to(route_to), 0.1)
	# Hurt feet slow them down, so they drift behind their route and catch up later.
	var walked := fposmod(Net.server_time() * speed + phase, length * 2.0)
	var along := walked if walked < length else length * 2.0 - walked
	var heading := (route_to - route_from).normalized() * (1.0 if walked < length else -1.0)
	var on_route := route_from + (route_to - route_from) * (along / length)
	_down_left = maxf(0.0, _down_left - delta)
	_angry_left = maxf(0.0, _angry_left - delta)
	anim_state = STATE_KNOCKED if _down_left > 0.0 else STATE_WALK
	_body.set("mood", "angry" if _angry_left > 0.0 else "neutral")
	if not _free:
		position = on_route
		_face(heading)
		return
	_free_at += _slide * delta
	_slide = _slide.move_toward(Vector3.ZERO, 9.0 * delta)
	if _down_left <= 0.0 and _angry_left > 0.0:
		# Up, and shaking it off, fists flying.
		if not bool(_body.call("is_gesturing")):
			_body.call("gesture", "flail")
	elif _down_left <= 0.0 and _slide.length() < 0.2:
		# Walk back to where the route has got to, a bit brisker than usual.
		var back := on_route - _free_at
		back.y = 0.0
		if back.length() < 0.15:
			_free = false
		else:
			_free_at += back.normalized() * minf(back.length(), speed * 1.6 * delta)
			_face(back)
	position = _free_at


func _face(direction: Vector3) -> void:
	if Vector2(direction.x, direction.z).length() > 0.01:
		rotation.y = atan2(-direction.x, -direction.z)


func _say(sound_name: String) -> void:
	if Net.is_automated():
		return
	var stream := load("res://assets/audio/sfx/%s.wav" % sound_name) as AudioStream
	if stream == null:
		return
	_voice.stream = stream
	_voice.pitch_scale = 0.85 + float(seed_value % 7) * 0.06
	_voice.play()
