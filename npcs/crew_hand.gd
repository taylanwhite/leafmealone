extends CharacterBody3D

## Authority: host. A hired hand (docs/SPINE.md, "Hiring"; net/crew/hires.gd):
## rides along on the job and does the dull part. It finds a thick patch of
## leaves, rakes it into a pile a few strokes at a time, bags the pile, carries
## the bag to Chefty, and goes again. Slower than a player, and never funny on
## purpose: the players keep the chaos jobs. Clients only see the replicated body
## and its action ("rake", "carry", "idle") for the arms.

const _CartoonBody = preload("res://player/cartoon_body.gd")
const _CharacterLife = preload("res://player/character_life.gd")
const _LotNav = preload("res://npcs/lot_nav.gd")
const _YardModels = preload("res://props/yard_models.gd")

## BOARD: the job's paid, so they walk back to Chefty and climb in (driving chunk D).
enum State { FIND, WALK, RAKE, BAG, HAUL, REST, BOARD }

const HAND_BAG_AT := Vector3(0.0, 0.55, 0.4)
## The step after the pile (m) glides over the swing's way back, from this phase on.
const STEP_AFTER_PILE: float = 0.18
const GLIDE_FROM: float = 0.7
## How fast a hand turns to face the way it rakes (rad/s).
const TURN_SPEED: float = Constants.HIRE_TURN_SPEED

## Replicated: the name over their head, how they look, what their arms are doing.
var hand_name: String = ""
var look_seed: int = 0
var action: String = "idle"
## Host: 0.5 to 1, how good they are (rake strength and walking speed).
var skill: float = 0.7

var _state: int = State.FIND
var _target := Vector3.ZERO
var _rake_dir := Vector3.FORWARD
var _strokes: int = 0
var _carrying_units: int = 0
var _state_time: float = 0.0
var _gravity: float = 9.8
var _rng := RandomNumberGenerator.new()
var _built: bool = false
## Host: what's left of the step after the pile, glided over the swing's way back.
var _glide_left: float = 0.0
var _events_field: Node
var _rake_shown: bool = false
## Every peer: this hand's last STROKE_LOG_KEEP strokes as this peer saw them
## ({phase, msec}), and how many it has seen in all, for tests.
var stroke_log: Array = []
var stroke_count: int = 0
const STROKE_LOG_KEEP: int = 32

## Host: emitted on each of this hand's strokes (the bite), for tests.
signal raked(origin: Vector3)


func _ready() -> void:
	set_multiplayer_authority(1)
	add_to_group("crew_hands")
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	if Net.is_host():
		_rng.seed = hash([look_seed, hand_name])
		_LotNav.ensure(_lot_zone())


## This hand in stroke events: Constants.RAKE_ACTOR_HAND_BASE + N for "HandN".
func actor() -> int:
	return Constants.RAKE_ACTOR_HAND_BASE + name.to_int()


func _process(_delta: float) -> void:
	# Spawn-synced properties land before _ready on clients; build the look once they have.
	if not _built and hand_name != "":
		_built = true
		_dress_up()
	_hook_events()
	var body := get_node_or_null("Visual/CartoonBody")
	var rake := get_node_or_null("Visual/HandRake") as Node3D
	var holding := action != "carry"
	if rake != null:
		rake.visible = holding
	var bag := get_node_or_null("Visual/HandBag") as Node3D
	if bag != null:
		bag.visible = action == "carry"
	if body == null:
		return
	# Hands on the rake's grips, leaning into the swing (props/rake_motion.gd).
	var pose := rake.get_node_or_null("Pose") as Node3D if rake != null else null
	if holding and pose != null:
		var grips := RakeMotion.grips_of(pose)
		body.call("set_hold", grips[0], grips[1])
		var shown := RakeStroke.display(actor())
		body.call("set_work_pose", float(shown["lean"]), float(shown["twist"]), float(shown["hip"]))
	else:
		body.call("set_hold", Vector3.INF, Vector3.INF)
		body.call("set_work_pose", 0.0, 0.0, 0.0)


## Every peer: the rake posed from this hand's swing, after the swing moved on.
func _pose_rake() -> void:
	var visual := get_node_or_null("Visual") as Node3D
	var pose := get_node_or_null("Visual/HandRake/Pose") as Node3D
	if visual == null or pose == null or action == "carry":
		_rake_shown = false
		RakeMotion.unpublish(pose)
		return
	RakeMotion.pose_frame(pose, hand_frame(visual), RakeStroke.display(actor()), actor(), 0.0, RakeMotion.shoulders_of(visual.get_node_or_null("CartoonBody")))
	if not _rake_shown:
		# Back in hand after hauling a bag: no streak from where it was last drawn.
		pose.reset_physics_interpolation()
		_rake_shown = true


## Remembers a stroke for tests, keeping only the last STROKE_LOG_KEEP.
func _log_stroke() -> void:
	stroke_count += 1
	stroke_log.append({"phase": RakeStroke.phase_of(actor()), "msec": Time.get_ticks_msec()})
	if stroke_log.size() > STROKE_LOG_KEEP:
		stroke_log.pop_front()


## A hand's body frame for posing (feet, -Z ahead): their Visual faces +Z.
static func hand_frame(visual: Node3D) -> Transform3D:
	var ahead := visual.global_basis.z
	ahead = Vector3(ahead.x, 0.0, ahead.z)
	if ahead.length() < 0.001:
		ahead = Vector3.FORWARD
	return Transform3D(Basis.looking_at(ahead.normalized(), Vector3.UP), visual.global_position)


## Clients: this hand's swing is replayed from its stroke events (the host runs it).
func _hook_events() -> void:
	if Net.is_host():
		return
	var field := get_tree().get_first_node_in_group("leaf_field")
	if field == null or field == _events_field:
		return
	_events_field = field
	if field.has_signal("stroke_event"):
		field.connect("stroke_event", func(ev: Dictionary) -> void:
			if str(ev.get("kind", "")) == "crew_rake" and int(ev.get("actor", 0)) == actor():
				_remote_stroke(ev)
		)


func _remote_stroke(ev: Dictionary) -> void:
	RakeStroke.on_event(actor(), ev)
	_log_stroke()


func _dress_up() -> void:
	var visual := get_node("Visual") as Node3D
	var body := _CartoonBody.new()
	body.name = "CartoonBody"
	body.dress_from_seed(look_seed)
	# Work clothes: crew orange shirt, so you can tell your hands from passersby.
	body.shirt = Color(0.93, 0.5, 0.18)
	body.hat_style = "cap"
	body.hat_color = Color(0.2, 0.32, 0.22)
	visual.add_child(body)
	body.rotation.y = PI
	body.build()
	var life := _CharacterLife.new()
	life.name = "Life"
	life.root = self
	life.body = body
	life.role = "crew"
	body.add_child(life)
	add_hand_rake(visual)
	add_hand_bag(visual).visible = false
	var label := get_node_or_null("Visual/Label") as Label3D
	if label != null:
		label.text = hand_name
		label.modulate = Color(1.0, 0.85, 0.55)


## The hired hand's own rake, under their Visual (which faces +Z here; the body is
## turned to match): a Pose posed by their swing (props/rake_motion.gd), standing
## ready until then. Also used by the studio (tools/studio, "gestures").
static func add_hand_rake(visual: Node3D) -> Node3D:
	var rake := Node3D.new()
	rake.name = "HandRake"
	visual.add_child(rake)
	var pose := Node3D.new()
	pose.name = "Pose"
	rake.add_child(pose)
	RakeMotion.dress(pose, 0)
	if visual.is_inside_tree():
		RakeMotion.pose_frame(pose, hand_frame(visual), RakeStroke.idle(), 0)
		pose.reset_physics_interpolation()
	return rake


## The bag a hired hand hauls to Chefty, hugged in front of them (it used to
## float behind their back: the Visual faces +Z here).
static func add_hand_bag(visual: Node3D) -> Node3D:
	var bag := _YardModels.node("leaf_bag")
	bag.name = "HandBag"
	visual.add_child(bag)
	bag.position = HAND_BAG_AT
	bag.scale = Vector3.ONE * 0.7
	return bag


## Something thrown hit them (net/components/net_prop.gd): they flinch and keep working.
func on_bonked(_push: Vector3, _tier: String) -> void:
	var body := get_node_or_null("Visual/CartoonBody")
	if body != null:
		body.call("gesture", "startle")


func _physics_process(delta: float) -> void:
	if not Net.is_host():
		RakeStroke.remote_step(actor(), delta)
		_pose_rake()
		return
	_physics_host(delta)
	# Not raking: let a swing in progress finish, then stand ready.
	if _state != State.RAKE:
		RakeStroke.crew_step(actor(), delta, _cycle(), false)
	_pose_rake()


func _cycle() -> float:
	return Constants.HIRE_STROKE_SECONDS / maxf(skill, 0.3)


func _physics_host(delta: float) -> void:
	_state_time += delta
	match _state:
		State.FIND:
			_find_work()
		State.WALK:
			if _steer_to(_target, delta) or _state_time > 12.0:
				_begin(State.RAKE)
		State.RAKE:
			_rake(delta)
		State.BAG:
			_bag()
		State.HAUL:
			var truck := _truck_point()
			if _steer_to(truck, delta) or _state_time > 20.0:
				_deliver()
		State.REST:
			_stop(delta)
			if _state_time > 2.0:
				_begin(State.FIND)
		State.BOARD:
			# At the truck (or given up walking): climb in. Chefty draws them in a
			# bed seat from the moment they're gone (chefty_drive.gd cosmetic_riders).
			if _steer_to(_truck_point(), delta) or _state_time > Constants.HIRE_BOARD_SECONDS:
				queue_free()


## Host: the job's done: walk back to Chefty and get in.
func board() -> void:
	if _state != State.BOARD:
		_begin(State.BOARD)


func _begin(state: int) -> void:
	_state = state
	_state_time = 0.0
	match state:
		State.RAKE:
			action = "rake"
			_strokes = 0
		State.HAUL:
			action = "carry"
		_:
			action = "idle"


## The thickest patch of leaves nobody else is working: a few random spots, the
## best one wins. Then rake toward the driveway side, where the bags go.
func _find_work() -> void:
	var field := get_tree().get_first_node_in_group("leaf_field")
	var lot := get_tree().get_first_node_in_group("job_lot") as Node3D
	if field == null or lot == null:
		_begin(State.REST)
		return
	var best := Vector3.INF
	var best_units := 0
	for attempt: int in 14:
		var spot := lot.to_global(Vector3(_rng.randf_range(-17.0, 17.0), 0.05, _rng.randf_range(-17.0, 17.0)))
		if _someone_near(spot, 4.0):
			continue
		var units := int(field.call("units_within_world", spot, 2.0))
		if units > best_units:
			best_units = units
			best = spot
	if best == Vector3.INF or best_units < int(Constants.MIN_BAG_CELLS * 60):
		# The yard's about done: wait by the truck.
		_target = _truck_point()
		_begin(State.REST)
		return
	_target = best
	var toward_street := lot.to_global(Vector3(0.0, 0.0, 18.0)) - best
	toward_street.y = 0.0
	_rake_dir = toward_street.normalized() if toward_street.length() > 0.1 else Vector3.BACK
	_begin(State.WALK)


## A swing every HIRE_STROKE_SECONDS / skill, one stroke at its bite
## (Constants.RAKE_CREW_BITES), inching forward behind the pile on the way back.
func _rake(delta: float) -> void:
	# Turn to face the pile's way (not an instant about-face), then start swinging.
	var facing := atan2(_rake_dir.x, _rake_dir.z)
	rotation.y = rotate_toward(rotation.y, facing, TURN_SPEED * delta)
	var cycle := _cycle()
	var turned := absf(angle_difference(rotation.y, facing)) < 0.15
	var working := _strokes < Constants.HIRE_STROKES_PER_PILE and (turned or RakeStroke.phase_of(actor()) >= 0.0)
	if RakeStroke.crew_step(actor(), delta, cycle, working):
		var field := get_tree().get_first_node_in_group("leaf_field")
		if field == null:
			_begin(State.FIND)
			return
		var origin := global_position + _rake_dir * 0.9
		if field.has_signal("stroke_event"):
			field.call("host_hand_rake", origin, _rake_dir, skill, actor())
		else:
			field.call("host_hand_rake", origin, _rake_dir, skill)
		_strokes += 1
		_glide_left = STEP_AFTER_PILE
		_log_stroke()
		raked.emit(origin)
	# The step after the pile, glided over the swing's way back (never a jump).
	var phase := RakeStroke.phase_of(actor())
	if _glide_left > 0.0 and (phase >= GLIDE_FROM or phase < 0.0):
		var step := minf(_glide_left, STEP_AFTER_PILE * (delta / cycle) / (1.0 - GLIDE_FROM))
		_glide_left -= step
		velocity.x = _rake_dir.x * step / maxf(delta, 0.0001)
		velocity.z = _rake_dir.z * step / maxf(delta, 0.0001)
		_fall(delta)
		move_and_slide()
	else:
		_stop(delta)
	# The last swing finished and its step taken: bag the pile.
	if _strokes >= Constants.HIRE_STROKES_PER_PILE and phase < 0.0 and _glide_left <= 0.0:
		_begin(State.BAG)


func _bag() -> void:
	var field := get_tree().get_first_node_in_group("leaf_field")
	if field == null:
		_begin(State.FIND)
		return
	var pile := global_position + _rake_dir * (0.9 + 0.5 * 3.0)
	var units := int(field.call("host_hand_collect", pile, actor())) if field.has_signal("stroke_event") else int(field.call("host_hand_collect", pile))
	if units <= 0:
		_begin(State.FIND)
		return
	_carrying_units = units
	_begin(State.HAUL)


func _deliver() -> void:
	var truck := get_tree().get_first_node_in_group("chefty")
	var field := get_tree().get_first_node_in_group("leaf_field")
	if truck != null and field != null and _carrying_units > 0:
		var value := int(field.call("dollars_for", _carrying_units))
		truck.call("accept_bags", 1, value)
		var hires := get_tree().get_first_node_in_group("hires")
		if hires != null:
			hires.call("note_bag", hand_name, value)
	_carrying_units = 0
	_begin(State.REST)


func _truck_point() -> Vector3:
	var truck := get_tree().get_first_node_in_group("chefty")
	var lot := get_tree().get_first_node_in_group("job_lot") as Node3D
	if truck == null:
		return lot.to_global(Vector3(2.0, 0.0, 17.0)) if lot != null else global_position
	# The curb side of the bed: inside the yard's pad, next to the truck.
	var at: Vector3 = truck.call("body_position")
	return Vector3(at.x, global_position.y, at.z - 2.4)


func _someone_near(spot: Vector3, radius: float) -> bool:
	for group: String in ["crew_hands", "players"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			if node == self:
				continue
			var other := node as Node3D
			if other != null and Vector2(other.global_position.x - spot.x, other.global_position.z - spot.z).length() < radius:
				return true
	return false


## Walk toward a point along the yard's navmesh. True once there.
func _steer_to(goal: Vector3, delta: float) -> bool:
	var flat_goal := Vector2(goal.x - global_position.x, goal.z - global_position.z)
	if flat_goal.length() < 0.9:
		_stop(delta)
		return true
	var next := goal
	var agent := get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if agent != null:
		agent.target_position = goal
		if not agent.get_current_navigation_path().is_empty():
			next = agent.get_next_path_position()
	var flat := Vector3(next.x - global_position.x, 0.0, next.z - global_position.z)
	if flat.length() > 0.05:
		var step := flat.normalized() * Constants.HIRE_SPEED * (0.7 + 0.3 * skill)
		velocity.x = step.x
		velocity.z = step.z
		rotation.y = atan2(flat.x, flat.z)
	_fall(delta)
	move_and_slide()
	return false


func _stop(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_fall(delta)
	move_and_slide()


func _fall(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= _gravity * delta


func _lot_zone() -> Node3D:
	var world := get_tree().get_first_node_in_group("world")
	return world.get_node_or_null("LotZone") as Node3D if world != null else null
