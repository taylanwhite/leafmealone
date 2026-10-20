extends CharacterBody3D

## Authority: host. Clients display the replicated body.
## Placeholder name until the crew is designed. OQ-010 counterplay v0:
## - It chases whoever it can see. Sprinting outruns it.
## - Out of sight, it goes to where it last saw someone, searches around there
##   for Constants.CREW_SEARCH_SECONDS, then patrols the lot.
## - It ignores players inside a hide spot, unless it watched them get in, in
##   which case it walks over and pulls them out.

const _SPEED_UP := Vector3(0.0, 1.4, 0.0)
const _HideSpot = preload("res://net/components/hide_spot.gd")
const _CartoonBody = preload("res://player/cartoon_body.gd")
## Close enough to a search or patrol point to pick the next one, in meters.
const WAYPOINT_REACHED: float = 1.5
## Patrol points stay this far inside the lot's edge.
const PATROL_HALF_EXTENT: float = 17.0

var _gravity: float = 9.8
var _last_seen := Vector3.ZERO
var _has_seen: bool = false
var _target_peer: int = 0
var _search_left: float = 0.0
var _waypoint := Vector3.INF
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	set_multiplayer_authority(1)
	add_to_group("crew")
	_dress_up()
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	if Net.is_host():
		_rng.randomize()
		_bake_navmesh()


## Placeholder look until the crew is designed (OQ-012): a cartoon person in plain
## dark work clothes, a cap, and dark glasses. No lettering, logo, or insignia.
func _dress_up() -> void:
	var visual := get_node_or_null("Visual") as Node3D
	if visual == null or visual.has_node("CartoonBody"):
		return
	var body := _CartoonBody.new()
	body.name = "CartoonBody"
	body.shirt = Color(0.22, 0.25, 0.32)
	body.pants = Color(0.17, 0.18, 0.2)
	body.skin = _CartoonBody.SKIN_TONES[absi(hash(name)) % _CartoonBody.SKIN_TONES.size()]
	body.hat_style = "cap"
	body.hat_color = Color(0.15, 0.16, 0.19)
	body.shades = true
	visual.add_child(body)
	# The crew turns its +Z toward where it walks (see _steer), and bodies face -Z.
	body.rotation.y = PI
	body.build()
	var capsule := visual.get_node_or_null("Body") as Node3D
	if capsule != null:
		capsule.visible = false


## Host only: whether this crew member has a clear view of that player now.
func can_see_peer(peer_id: int) -> bool:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id) and node is Node3D:
			return _can_see(node as Node3D)
	return false


func _physics_process(delta: float) -> void:
	if not Net.is_host():
		return
	var goal := global_position
	var target := _visible_target()
	if target != null:
		goal = target.global_position
		_last_seen = goal
		_has_seen = true
		_target_peer = int(target.name)
		_search_left = Constants.CREW_SEARCH_SECONDS
		_waypoint = Vector3.INF
		if global_position.distance_to(target.global_position) <= Constants.CAPTURE_RADIUS:
			_capture(_target_peer)
	else:
		goal = _goal_without_target(delta)
	_steer(goal, delta)


func _goal_without_target(delta: float) -> Vector3:
	# Watched them hide: go open it.
	var spot: Node3D = _HideSpot.spot_of(get_tree(), _target_peer) if _target_peer != 0 else null
	if spot != null and bool(spot.call("was_seen_entering")):
		if _flat_distance(spot.global_position) <= Constants.CAPTURE_RADIUS + Constants.HIDE_REACH * 0.5:
			var peer_id := int(spot.call("pull_out"))
			_capture(peer_id)
			_target_peer = 0
		return spot.global_position
	if _has_seen and _search_left > 0.0:
		_search_left -= delta
		if _waypoint == Vector3.INF:
			_waypoint = _last_seen
		elif _flat_distance(_waypoint) <= WAYPOINT_REACHED:
			_waypoint = _last_seen + _random_flat(Constants.CREW_SEARCH_RADIUS)
		return _waypoint
	if _waypoint == Vector3.INF or _flat_distance(_waypoint) <= WAYPOINT_REACHED or _has_seen:
		_has_seen = false
		_waypoint = _lot_center() + _random_flat(PATROL_HALF_EXTENT)
	return _waypoint


func _capture(peer_id: int) -> void:
	if peer_id == 0:
		return
	var director := get_tree().get_first_node_in_group("run_director")
	if director != null:
		director.call("note_capture", peer_id)


func _random_flat(radius: float) -> Vector3:
	return Vector3(_rng.randf_range(-radius, radius), 0.0, _rng.randf_range(-radius, radius))


func _flat_distance(point: Vector3) -> float:
	return Vector2(point.x - global_position.x, point.z - global_position.z).length()


func _lot_center() -> Vector3:
	var lot := _lot_zone()
	return lot.global_position if lot != null else global_position


func _lot_zone() -> Node3D:
	return get_tree().get_first_node_in_group("world").get_node_or_null("LotZone") as Node3D


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
		if body.has_method("is_hidden") and bool(body.call("is_hidden")):
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


## Bake a fresh navigation mesh from the lot's static colliders, so the crew paths
## around the house, fences, cover, and hide spots of whichever lot is loaded.
func _bake_navmesh() -> void:
	var lot := _lot_zone()
	if lot == null:
		return
	var old := lot.get_node_or_null("CrewNav")
	if old != null:
		old.queue_free()
	var mesh := NavigationMesh.new()
	# Whole voxels, so the bake doesn't round them. Cell size matches the default navigation map.
	mesh.cell_size = 0.25
	mesh.cell_height = 0.25
	mesh.agent_radius = 0.5
	mesh.agent_height = 1.75
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	var source := NavigationMeshSourceGeometryData3D.new()
	# Geometry is gathered relative to the lot zone, so the region sits at the lot zone too.
	NavigationServer3D.parse_source_geometry_data(mesh, source, lot)
	NavigationServer3D.bake_from_source_geometry_data(mesh, source)
	var region := NavigationRegion3D.new()
	region.name = "CrewNav"
	region.add_to_group("lot_nav")
	region.navigation_mesh = mesh
	lot.add_child(region)
