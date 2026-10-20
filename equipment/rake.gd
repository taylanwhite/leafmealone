extends Node

## Authority: owning peer sends the request. The leaf field decides what changes.
## Primary rakes. Secondary bags leaves, which is what currently counts as cleaned.

## Strength, width, and bag radius live in Constants (RAKE_*, HAND_RAKE_*, BAG_RADIUS),
## because the host checks them too. TODO(balance): move them into the workbook.
const REACH: float = 1.5
## Hand raking: a stroke at most this often, so flailing doesn't turn into a fast rake.
const HAND_STROKE_SECONDS: float = 0.35

var _hand_wait: float = 0.0
var _rake_wait: float = 0.0
var _work_wait: float = 0.0
var _spray: CPUParticles3D
var _hooked_field: Node


func _physics_process(delta: float) -> void:
	var player := get_parent() as CharacterBody3D
	if player == null or multiplayer.multiplayer_peer == null:
		return
	if not player.is_multiplayer_authority():
		return
	_hook_refusal()
	_hand_wait = maxf(0.0, _hand_wait - delta)
	_rake_wait = maxf(0.0, _rake_wait - delta)
	_work_wait = maxf(0.0, _work_wait - delta)
	var held: Node = player.call("_held_prop")
	var has_rake := held != null and str(held.get("kind")) == "rake"
	var held_kind := str(held.get("kind")) if held != null else ""
	_set_spray(player, held_kind if Input.is_action_pressed("primary") else "")
	# Up a ladder: left click works the gutters, by hand or with the leaf blower.
	if bool(player.call("is_climbing")):
		if Input.is_action_pressed("primary") and _work_wait <= 0.0:
			_work_wait = 0.15
			var tasks := get_tree().get_first_node_in_group("job_tasks")
			if tasks != null:
				tasks.call("request_work", "clean_gutters", player.global_position + Vector3(0.0, 1.5, 0.0) - player.global_basis.z * 0.4, -player.global_basis.z)
			var body := player.get_node_or_null("Visual/CartoonBody")
			if body != null and held_kind == "" and not bool(body.call("is_gesturing")):
				body.call("gesture", "scratch")
		return
	# A ladder in hand: left click sets it up against the house.
	if held_kind == "ladder":
		if Input.is_action_just_pressed("primary"):
			held.call("request_place_ladder")
		return
	# A tool: left click uses it. G throws anything (player.gd).
	if Constants.TOOL_PRICES.has(held_kind):
		if Input.is_action_pressed("primary"):
			_use_tool(player, held_kind)
		return
	if held != null and not has_rake:
		return
	if Input.is_action_pressed("primary"):
		if has_rake:
			# A stroke on a rhythm, not every tick: each one shoves leaves well forward.
			if _rake_wait <= 0.0:
				_rake_wait = Constants.RAKE_STROKE_SECONDS
				_stroke(player, false, Constants.RAKE_STRENGTH, Constants.RAKE_WIDTH)
		elif _hand_wait <= 0.0:
			_hand_wait = HAND_STROKE_SECONDS
			_hand_rake(player)
	elif Input.is_action_just_pressed("secondary"):
		_stroke(player, true, 0.0, 0.0)


## Using a tool: the leaf blower puffs leaves along like a super rake; the rest
## send their work to the job's tasks (net/work/job_tasks.gd), aimed where you look.
func _use_tool(player: CharacterBody3D, tool_kind: String) -> void:
	if tool_kind == "leaf_blower":
		if _rake_wait <= 0.0:
			_rake_wait = Constants.BLOWER_PUFF_SECONDS
			_stroke(player, false, Constants.BLOWER_STRENGTH, Constants.BLOWER_WIDTH)
		return
	if tool_kind == "lawn_mower" or _work_wait > 0.0:
		# The mower mows by being pushed around.
		return
	_work_wait = 0.15
	var tasks := get_tree().get_first_node_in_group("job_tasks")
	if tasks == null:
		return
	var task := ""
	for task_id: String in Constants.TASK_TOOLS:
		if str(Constants.TASK_TOOLS[task_id]) == tool_kind:
			task = task_id
	if task == "":
		return
	var head := player.get_node_or_null("Visual/Head") as Node3D
	var eye := head.global_position if head != null else player.global_position + Vector3(0.0, 1.6, 0.0)
	var look := -head.global_basis.z if head != null else -player.global_basis.z
	var forward := -player.global_basis.z
	var origin := player.global_position
	match task:
		"wash_windows":
			if str(_held_prop(player).get("hose_source")) == "":
				return
			origin = eye
			look = hose_aim(player, look)
		"power_wash":
			# Where the look meets the ground, within reach.
			var reach := float(Constants.TASK_REACH["power_wash"])
			var distance := reach * 0.6
			if look.y < -0.05:
				distance = clampf((eye.y - 0.05) / -look.y, 0.6, reach)
			origin = eye + look * distance
			origin.y = player.global_position.y + 0.05
		"clean_gutters":
			origin = player.global_position
		"trim_hedges":
			origin = player.global_position + forward * 0.9 + Vector3(0.0, 1.2, 0.0)
		"paint_fence":
			origin = player.global_position + forward * 0.9 + Vector3(0.0, 0.5, 0.0)
	if task == "power_wash" and float(_held_prop(player).get("water")) <= 0.0:
		return
	tasks.call("request_work", task, origin, look)


func _held_prop(player: CharacterBody3D) -> Node:
	return player.call("_held_prop")


## Where the water goes: where you look, except a hydrant's hose has a mind of
## its own and thrashes around.
static func hose_aim(player: Node3D, look: Vector3) -> Vector3:
	var held: Node = player.call("_held_prop")
	if held == null or str(held.get("hose_source")) != "hydrant":
		return look
	var t := Time.get_ticks_msec() / 1000.0
	var thrash := look.rotated(Vector3.UP, sin(t * 2.1) * 0.7 + sin(t * 5.3) * 0.15)
	return thrash.rotated(thrash.cross(Vector3.UP).normalized(), sin(t * 1.6) * 0.35).normalized()


## The holder sees their own hose or washer spraying; everyone else sees the
## host's splashes where the water lands.
func _set_spray(player: CharacterBody3D, tool_kind: String) -> void:
	# The hose and the washer draw their own water (props/water_stream.gd); only the blower puffs here.
	var spraying := tool_kind == "leaf_blower"
	if not spraying:
		if _spray != null:
			_spray.emitting = false
		return
	if _spray == null:
		_spray = CPUParticles3D.new()
		_spray.amount = 60
		_spray.lifetime = 0.5
		var mesh := SphereMesh.new()
		mesh.radius = 0.035
		mesh.height = 0.07
		_spray.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.7, 0.85, 1.0, 0.7)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_spray.material_override = material
		_spray.spread = 6.0
		_spray.gravity = Vector3(0.0, -6.0, 0.0)
		_spray.local_coords = false
		player_parent().add_child(_spray)
	var head := player.get_node_or_null("Visual/Head") as Node3D
	var look := -head.global_basis.z if head != null else -player.global_basis.z
	_spray.global_position = player.global_position + Vector3(0.0, 1.0, 0.0) + (-player.global_basis.z) * 0.8 + player.global_basis.x * 0.25
	_spray.direction = look
	var speed := 9.0 if tool_kind == "hose" else (14.0 if tool_kind == "pressure_washer" else 6.0)
	_spray.initial_velocity_min = speed * 0.8
	_spray.initial_velocity_max = speed
	(_spray.material_override as StandardMaterial3D).albedo_color = Color(0.85, 0.75, 0.55, 0.0) if tool_kind == "leaf_blower" else Color(0.7, 0.85, 1.0, 0.7)
	_spray.emitting = true


## No rake: scoop at the leaves with your hands. It barely does anything, and
## it looks it.
func _hand_rake(player: CharacterBody3D) -> void:
	_stroke(player, false, Constants.HAND_RAKE_STRENGTH, Constants.HAND_RAKE_WIDTH)
	var body := player.get_node_or_null("Visual/CartoonBody")
	if body != null and not bool(body.call("is_gesturing")):
		body.call("gesture", "flail")
	if randf() < 0.25:
		player.call("say", ["vo_hup", "vo_huh", "vo_eh"][randi() % 3])


func _stroke(player: CharacterBody3D, bag: bool, strength: float, width: float) -> void:
	var forward := -player.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.001:
		return
	forward = forward.normalized()
	var origin := player.global_position + forward * REACH + Vector3(0.0, 0.2, 0.0)
	var field := _field_near(origin)
	if field == null:
		return
	if bag:
		field.call("request_collect", origin, Constants.BAG_RADIUS)
	else:
		field.call("request_rake", origin, forward, width, strength)
		_play_sfx("rake")
	_burst(origin, forward, width > Constants.HAND_RAKE_WIDTH)


## A refused bag (too few leaves) gets a puzzled "eh?" from you.
## Each job loads a new lot and leaf field, so hook whichever one is current.
func _hook_refusal() -> void:
	var field := _field_near(Vector3.ZERO)
	if field == null or field == _hooked_field or not field.has_signal("bag_refused"):
		return
	_hooked_field = field
	field.connect("bag_refused", func(peer_id: int) -> void:
		var player := get_parent()
		if player != null and peer_id == player.name.to_int():
			player.call("say", "vo_eh")
	)


func _field_near(_origin: Vector3) -> Node:
	var fields := get_tree().get_nodes_in_group("leaf_field")
	if fields.is_empty():
		return null
	return fields[0] as Node


## Leaves thrown up and forward the way you raked, more with the rake than by hand.
func _burst(at: Vector3, forward: Vector3 = Vector3.UP, with_rake: bool = true) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.18, 0.08, 0.12)
	var material := StandardMaterial3D.new()
	material.albedo_color = [Color(0.85, 0.42, 0.17), Color(0.89, 0.71, 0.23), Color(0.64, 0.23, 0.14)][randi() % 3]
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 18 if with_rake else 5
	particles.lifetime = 0.45
	particles.mesh = mesh
	particles.material_override = material
	particles.direction = (forward + Vector3(0.0, 1.2, 0.0)).normalized()
	particles.spread = 35.0
	particles.initial_velocity_min = 1.5
	particles.initial_velocity_max = 3.5 if with_rake else 2.0
	particles.gravity = Vector3(0, -5.0, 0)
	particles.emitting = true
	player_parent().add_child(particles)
	particles.global_position = at
	get_tree().create_timer(0.8).timeout.connect(particles.queue_free)


func _play_sfx(sound_name: String) -> void:
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play", sound_name)


func player_parent() -> Node:
	return get_parent()
