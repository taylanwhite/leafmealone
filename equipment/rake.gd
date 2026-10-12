extends Node

## Authority: owning peer sends the request. The leaf field decides what changes.
## Primary rakes. Secondary bags leaves, which is what currently counts as cleaned.

# TODO(balance): add rake width, strength, reach, and bag radius to the workbook.
const RAKE_WIDTH: float = 1.6
const RAKE_STRENGTH: float = 70.0
const BAG_RADIUS: float = 1.1
const REACH: float = 1.5


func _physics_process(_delta: float) -> void:
	var player := get_parent() as CharacterBody3D
	if player == null or multiplayer.multiplayer_peer == null:
		return
	if not player.is_multiplayer_authority():
		return
	if player.has_method("holding_prop") and bool(player.call("holding_prop")):
		if Input.is_action_just_pressed("primary"):
			player.call("_release_held", true)
		return
	if Input.is_action_pressed("primary"):
		_stroke(player, false)
	elif Input.is_action_just_pressed("secondary"):
		_stroke(player, true)


func _stroke(player: CharacterBody3D, bag: bool) -> void:
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
		field.call("request_collect", origin, BAG_RADIUS)
	else:
		field.call("request_rake", origin, forward, RAKE_WIDTH, RAKE_STRENGTH)
	_burst(origin)


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


func player_parent() -> Node:
	return get_parent()
