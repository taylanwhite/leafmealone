extends Node3D

## Authority: local, cosmetic, but the same on every peer. Someone out for a walk
## on the sidewalk: a cartoon person strolling back and forth along a route.
## Where they are is a pure function of their seed and Net.server_time(), so every
## peer sees them in the same spot with no network traffic (docs/NETCODE.md).
## They glance at people and fidget like everyone else (player/character_life.gd).
## They keep hours (art:9, out_at): home by late evening, back out in the
## morning, leaving and coming back only where this peer's camera can't see it.
## On the way they step round players and the camera (_dodge, local to each
## peer), so nobody walks through you or into your lens.
##
## Bonkable: the host spots a thrown item reaching them (net/components/net_prop.gd)
## and tells every peer, which calls on_bonked here. They get shoved, flinch,
## stumble, or go flat, then get up angry and walk back to their route. Who they
## are, what they say, and any jokes about them are design decisions; they only
## make the shared goofy noises.

const _CartoonBody = preload("res://player/cartoon_body.gd")
const _CharacterLife = preload("res://player/character_life.gd")
## Matches player.gd's AnimState: IDLE, WALK, KNOCKED.
const STATE_IDLE: int = 0
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
## Stopped short of a NICE van's door, watching (Shuttle.keep_clear); _free_at
## holds where they stand, and they catch up on their route once it's gone.
var _held: bool = false
## art:9: out for their walk at this hour (out_at), or home; they only leave or
## come back where nobody's camera sees it. And how far (m) they've stepped off
## their route (across it) to get round a player or the camera, and how fast.
var _out: bool = true
var _hours_check: float = 0.0
var _offset: float = 0.0
var _offset_speed: float = 0.0


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
	_voice.bus = preload("res://audio/sound_bank.gd").bus("vo_yelp")
	add_child(_voice)
	# Built at night, they're at home already.
	var clock := get_tree().get_first_node_in_group("day_clock")
	_out = out_at(seed_value, float(clock.call("hour")) if clock != null else Constants.DAY_SKY_ART_HOUR)
	visible = _out
	if not _out:
		remove_from_group("bonkable")
	_place(0.0)
	reset_physics_interpolation()


## Every peer moves them the same way on physics ticks.
func _physics_process(delta: float) -> void:
	_hours_check -= delta
	if _hours_check <= 0.0:
		_hours_check = Constants.PEDESTRIAN_HOURS_CHECK_SECONDS
		_keep_hours()
	if not _out:
		return
	_place(delta)


## Whether the walker with this seed is out at hour (7 to 26; pure, for tests):
## out from the morning until their own evening hour, so nobody is out at 2 AM.
static func out_at(seed_number: int, hour: float) -> bool:
	var home := lerpf(Constants.PEDESTRIAN_HOME_HOURS.x, Constants.PEDESTRIAN_HOME_HOURS.y, float(posmod(hash([seed_number, "home"]), 1000)) / 1000.0)
	return hour < home


## Out or home by the clock, changing only while no camera here can see it
## happen (they never pop in or out in front of you).
func _keep_hours() -> void:
	var clock := get_tree().get_first_node_in_group("day_clock")
	var want := out_at(seed_value, float(clock.call("hour")) if clock != null else Constants.DAY_SKY_ART_HOUR)
	if want == _out:
		return
	# Going home: where they stand. Coming out: where today's walk has them now
	# (a hidden walker still stands where they went home, maybe far from it).
	var at := _world(_route_at(Net.server_time())) if want else global_position
	if not _unseen_at(at):
		return
	_out = want
	visible = want
	if want:
		add_to_group("bonkable")
		_free = false
		_held = false
		_offset = 0.0
		_offset_speed = 0.0
		_place(0.0)
		reset_physics_interpolation()
	else:
		remove_from_group("bonkable")


## No camera here sees someone standing at (world space).
func _unseen_at(at: Vector3) -> bool:
	var viewport := get_viewport()
	var camera := viewport.get_camera_3d() if viewport != null else null
	if camera == null:
		return true
	var middle := at + Vector3(0.0, 1.0, 0.0)
	return camera.global_position.distance_to(middle) > Constants.PEDESTRIAN_UNSEEN_DISTANCE or not camera.is_position_in_frustum(middle)


## How far across the route (m, along across) to be, given the players and the
## camera near on_route: stepping aside for whoever is in the way ahead, holding
## that while passing them, drifting back once clear. Moves _offset.
func _dodge(on_route: Vector3, heading: Vector3, across: Vector3, delta: float) -> void:
	var nearest := INF
	var target := 0.0
	var hold := false
	var urgent := false
	for obstacle: Array in _obstacles():
		var rel := _local(obstacle[0] as Vector3) - on_route
		rel.y = 0.0
		var ahead := rel.dot(heading)
		if ahead < -0.9 or ahead > Constants.PEDESTRIAN_LOOK_AHEAD:
			continue
		var clear := float(obstacle[1])
		var side := rel.dot(across)
		var gap := side - _offset
		if absf(gap) < clear:
			if absf(ahead) < nearest:
				nearest = absf(ahead)
				# Round whichever side is nearer: away from where they stand.
				target = side - clear if gap > 0.0 else side + clear
				urgent = Vector2(ahead, gap).length() < clear
		elif absf(gap) < clear + Constants.PEDESTRIAN_HOLD_BAND:
			hold = true
	var speed := Constants.PEDESTRIAN_RETURN_SPEED
	if nearest < INF:
		speed = Constants.PEDESTRIAN_SIDESTEP_SPEED * (Constants.PEDESTRIAN_URGENT_SIDESTEP if urgent else 1.0)
	elif hold:
		target = _offset
	target = clampf(target, -Constants.PEDESTRIAN_SIDESTEP_MAX, Constants.PEDESTRIAN_SIDESTEP_MAX)
	var before := _offset
	_offset = move_toward(_offset, target, speed * delta)
	_offset_speed = (_offset - before) / maxf(delta, 0.001)


## Who a walker steps round: every player's middle, and this peer's camera.
func _obstacles() -> Array:
	var out: Array = []
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node is Node3D:
			out.append([(node as Node3D).global_position, Constants.PEDESTRIAN_CLEAR_PLAYER])
	var viewport := get_viewport()
	var camera := viewport.get_camera_3d() if viewport != null else null
	if camera != null:
		out.append([camera.global_position, Constants.PEDESTRIAN_CLEAR_CAMERA])
	return out


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
		_offset = 0.0
		_offset_speed = 0.0
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
	var heading := (route_to - route_from).normalized() * (1.0 if walked < length else -1.0)
	var on_route := _route_at(Net.server_time())
	_down_left = maxf(0.0, _down_left - delta)
	_angry_left = maxf(0.0, _angry_left - delta)
	anim_state = STATE_KNOCKED if _down_left > 0.0 else STATE_WALK
	_body.set("mood", "angry" if _angry_left > 0.0 else "neutral")
	# A NICE van at the curb: they stop short of its door and watch the people
	# stepping down, then catch up on their walk once it's gone (p1-van review).
	var keep := _keep_clear()
	if _held:
		var watching := _keep_near(_world(_free_at), keep)
		if not watching.is_empty():
			anim_state = STATE_IDLE
			position = _free_at
			_face(_local(watching[0] as Vector3) - _free_at)
			return
		_held = false
	if _down_left <= 0.0 and _slide.length() < 0.2 and not keep.is_empty():
		var next := on_route
		if _free:
			var back := on_route - _free_at
			back.y = 0.0
			next = _free_at + back.normalized() * minf(back.length(), speed * 1.6 * delta) if back.length() > 0.001 else _free_at
		if _keep_inside(_world(next), keep) and not _keep_inside(global_position, keep):
			_held = true
			if not _free:
				# Off the route where they stand (sidestep and all); the walk back
				# rejoins the plain route, so the sidestep ends here, not in a jump later.
				_free = true
				_free_at = position
				_offset = 0.0
				_offset_speed = 0.0
			anim_state = STATE_IDLE
			position = _free_at
			return
	if not _free:
		# Round anyone in the way (art:9): never through a player or into the lens.
		var axis := (route_to - route_from).normalized()
		var across := Vector3(-axis.z, 0.0, axis.x)
		if delta > 0.0:
			_dodge(on_route, heading, across, delta)
		position = on_route + across * _offset
		_face(heading * speed + across * _offset_speed)
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


## Where their route has them at a server time (parent space).
func _route_at(time: float) -> Vector3:
	var length := maxf(route_from.distance_to(route_to), 0.1)
	var walked := fposmod(time * speed + phase, length * 2.0)
	var along := walked if walked < length else length * 2.0 - walked
	return route_from + (route_to - route_from) * (along / length)


## Where they'll be (world space) every step seconds from server time from_t to
## to_t, for a van planning where its riders step down (net/run_events/shuttle.gd):
## along their route, stopping short of a van's door as _place does (with the
## sidewalk kept clear as it is now), or where they stand while off their route.
func passing_points(from_t: float, to_t: float, step: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	if _free or _held:
		out.append(global_position)
		return out
	var keep := _keep_clear()
	var at := global_position
	var held := false
	var t := Net.server_time()
	while t <= to_t + 0.001:
		if not held:
			var next := _world(_route_at(t))
			if _keep_inside(next, keep) and not _keep_inside(at, keep):
				held = true
			else:
				at = next
		if t >= from_t - 0.001:
			out.append(at)
		t += maxf(step, 0.05)
	return out


## The sidewalk kept clear around NICE vans now ([where, radius] pairs, world).
func _keep_clear() -> Array:
	var shuttle := get_tree().get_first_node_in_group("nice_shuttle") if is_inside_tree() else null
	return shuttle.call("keep_clear", Net.server_time()) as Array if shuttle != null and shuttle.has_method("keep_clear") else []


static func _keep_inside(at: Vector3, keep: Array) -> bool:
	for zone: Array in keep:
		var center := zone[0] as Vector3
		if Vector2(at.x - center.x, at.z - center.z).length() < float(zone[1]):
			return true
	return false


## The zone a passer-by stopped at the edge of, while it's still there.
static func _keep_near(at: Vector3, keep: Array) -> Array:
	for zone: Array in keep:
		var center := zone[0] as Vector3
		if Vector2(at.x - center.x, at.z - center.z).length() < float(zone[1]) + 0.5:
			return zone
	return []


func _world(local: Vector3) -> Vector3:
	var parent := get_parent() as Node3D
	return parent.global_transform * local if parent != null and parent.is_inside_tree() else local


func _local(world: Vector3) -> Vector3:
	var parent := get_parent() as Node3D
	return parent.global_transform.affine_inverse() * world if parent != null and parent.is_inside_tree() else world


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
