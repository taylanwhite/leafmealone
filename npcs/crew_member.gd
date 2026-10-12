extends CharacterBody3D

## Authority: host. Clients display the replicated body.
## Placeholder name until the crew is designed. OQ-010: a blocked view makes them search the last place they looked.

const _SPEED_UP := Vector3(0.0, 1.4, 0.0)

var _gravity: float = 9.8
var _last_seen := Vector3.ZERO
var _has_seen: bool = false


func _ready() -> void:
	set_multiplayer_authority(1)
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	if Net.is_host():
		_ensure_navmesh()


func _physics_process(delta: float) -> void:
	if not Net.is_host():
		return
	var goal := global_position
	var target := _visible_target()
	if target != null:
		goal = target.global_position
		_last_seen = goal
		_has_seen = true
		if global_position.distance_to(target.global_position) <= Constants.CAPTURE_RADIUS:
			var director := get_tree().get_first_node_in_group("run_director")
			if director != null:
				director.call("note_capture", int(target.name))
	elif _has_seen:
		goal = _last_seen
	_steer(goal, delta)


func _visible_target() -> Node3D:
	var director := get_tree().get_first_node_in_group("run_director")
	var closest: Node3D = null
	var closest_distance := INF
	for node: Node in get_tree().get_nodes_in_group("players"):
		if not node is Node3D:
			continue
		var body := node as Node3D
		var peer_id := int(body.name)
		if director != null and not bool(director.call("can_capture", peer_id)):
			continue
		if director == null and Net.player_zone(peer_id) != Net.Zone.LOT:
			continue
		if not _can_see(body):
			continue
		var distance := global_position.distance_to(body.global_position)
		if distance < closest_distance:
			closest = body
			closest_distance = distance
	return closest


func _can_see(body: Node3D) -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(global_position + _SPEED_UP, body.global_position + Vector3(0.0, 1.0, 0.0), 3)
	query.exclude = [self]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return true
	var collider := hit.collider as Node
	return collider != null and (collider == body or collider.is_in_group("players"))


func _steer(goal: Vector3, delta: float) -> void:
	var next := goal
	var agent := get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if agent != null:
		agent.target_position = goal
		var path := agent.get_current_navigation_path()
		if not path.is_empty():
			next = agent.get_next_path_position()
	var flat := Vector3(next.x - global_position.x, 0.0, next.z - global_position.z)
	if flat.length() > 0.75:
		var step := flat.normalized() * Constants.CREW_SPEED
		velocity.x = step.x
		velocity.z = step.z
		rotation.y = atan2(flat.x, flat.z)
	else:
		velocity.x = move_toward(velocity.x, 0.0, Constants.CREW_SPEED)
		velocity.z = move_toward(velocity.z, 0.0, Constants.CREW_SPEED)
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= _gravity * delta
	move_and_slide()


func _ensure_navmesh() -> void:
	if get_tree().get_first_node_in_group("lot_nav") != null:
		return
	var mesh := NavigationMesh.new()
	mesh.agent_radius = 0.45
	mesh.agent_height = 1.8
	mesh.cell_size = 0.3
	var source := NavigationMeshSourceGeometryData3D.new()
	var faces := PackedVector3Array([
		Vector3(980.0, 0.0, -20.0), Vector3(1020.0, 0.0, -20.0), Vector3(1020.0, 0.0, 20.0),
		Vector3(980.0, 0.0, -20.0), Vector3(1020.0, 0.0, 20.0), Vector3(980.0, 0.0, 20.0),
	])
	source.add_faces(faces, Transform3D.IDENTITY)
	NavigationServer3D.bake_from_source_geometry_data(mesh, source)
	var region := NavigationRegion3D.new()
	region.name = "LotNav"
	region.add_to_group("lot_nav")
	region.navigation_mesh = mesh
	get_parent().add_child(region)
