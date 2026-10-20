extends Node

## Authority: owning peer sends the request. The leaf field decides what changes.
## Primary rakes. Secondary bags leaves, which is what currently counts as cleaned.

## Strength, width, and bag radius live in Constants (RAKE_*, HAND_RAKE_*, BAG_RADIUS),
## because the host checks them too. TODO(balance): move them into the workbook.
const REACH: float = 1.5
## Hand raking: a stroke at most this often, so flailing doesn't turn into a fast rake.
const HAND_STROKE_SECONDS: float = 0.35

var _hand_wait: float = 0.0
var _hooked_field: Node


func _physics_process(delta: float) -> void:
	var player := get_parent() as CharacterBody3D
	if player == null or multiplayer.multiplayer_peer == null:
		return
	if not player.is_multiplayer_authority():
		return
	_hook_refusal()
	_hand_wait = maxf(0.0, _hand_wait - delta)
	var held: Node = player.call("_held_prop")
	var has_rake := held != null and str(held.get("kind")) == "rake"
	# Holding anything but the rake: left click throws it, as before.
	if held != null and not has_rake:
		if Input.is_action_just_pressed("primary"):
			player.call("_release_held", true)
		return
	if Input.is_action_pressed("primary"):
		if has_rake:
			_stroke(player, false, Constants.RAKE_STRENGTH, Constants.RAKE_WIDTH)
		elif _hand_wait <= 0.0:
			_hand_wait = HAND_STROKE_SECONDS
			_hand_rake(player)
	elif Input.is_action_just_pressed("secondary"):
		_stroke(player, true, 0.0, 0.0)


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
	_burst(origin)


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


func _burst(at: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.18, 0.08, 0.12)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.75, 0.42, 0.16)
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 8
	particles.lifetime = 0.45
	particles.mesh = mesh
	particles.material_override = material
	particles.direction = Vector3.UP
	particles.spread = 50.0
	particles.initial_velocity_min = 1.0
	particles.initial_velocity_max = 2.2
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
