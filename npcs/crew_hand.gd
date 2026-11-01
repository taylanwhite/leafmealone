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

enum State { FIND, WALK, RAKE, BAG, HAUL, REST }

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
var _stroke_wait: float = 0.0
var _carrying_units: int = 0
var _state_time: float = 0.0
var _gravity: float = 9.8
var _rng := RandomNumberGenerator.new()
var _built: bool = false


func _ready() -> void:
	set_multiplayer_authority(1)
	add_to_group("crew_hands")
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	if Net.is_host():
		_rng.seed = hash([look_seed, hand_name])
		_LotNav.ensure(_lot_zone())


func _process(_delta: float) -> void:
	# Spawn-synced properties land before _ready on clients; build the look once they have.
	if not _built and hand_name != "":
		_built = true
		_dress_up()
	var body := get_node_or_null("Visual/CartoonBody")
	if body != null and action == "rake" and not bool(body.call("is_gesturing")):
		body.call("gesture", "rake")
	var rake := get_node_or_null("Visual/HandRake") as Node3D
	if rake != null:
		rake.visible = action != "carry"
	var bag := get_node_or_null("Visual/HandBag") as Node3D
	if bag != null:
		bag.visible = action == "carry"


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
	var rake := _YardModels.node("rake")
	rake.name = "HandRake"
	visual.add_child(rake)
	rake.position = Vector3(0.35, 0.15, -0.45)
	rake.rotation = Vector3(-0.5, 0.0, 0.1)
	rake.scale = Vector3.ONE * 0.8
	var bag := _YardModels.node("leaf_bag")
	bag.name = "HandBag"
	visual.add_child(bag)
	bag.position = Vector3(0.0, 0.55, -0.45)
	bag.scale = Vector3.ONE * 0.7
	bag.visible = false
	var label := get_node_or_null("Visual/Label") as Label3D
	if label != null:
		label.text = hand_name
		label.modulate = Color(1.0, 0.85, 0.55)


## Something thrown hit them (net/components/net_prop.gd): they flinch and keep working.
func on_bonked(_push: Vector3, _tier: String) -> void:
	var body := get_node_or_null("Visual/CartoonBody")
	if body != null:
		body.call("gesture", "startle")


func _physics_process(delta: float) -> void:
	if not Net.is_host():
		return
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


## A stroke every so often, inching forward behind the pile.
func _rake(delta: float) -> void:
	_stop(delta)
	rotation.y = atan2(_rake_dir.x, _rake_dir.z)
	_stroke_wait -= delta
	if _stroke_wait > 0.0:
		return
	_stroke_wait = Constants.HIRE_STROKE_SECONDS / maxf(skill, 0.3)
	var field := get_tree().get_first_node_in_group("leaf_field")
	if field == null:
		_begin(State.FIND)
		return
	var origin := global_position + _rake_dir * 0.9
	field.call("host_hand_rake", origin, _rake_dir, skill)
	_strokes += 1
	# Step after the pile.
	global_position += _rake_dir * 0.18
	if _strokes >= Constants.HIRE_STROKES_PER_PILE:
		_begin(State.BAG)


func _bag() -> void:
	var field := get_tree().get_first_node_in_group("leaf_field")
	if field == null:
		_begin(State.FIND)
		return
	var pile := global_position + _rake_dir * (0.9 + 0.5 * 3.0)
	var units := int(field.call("host_hand_collect", pile))
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
