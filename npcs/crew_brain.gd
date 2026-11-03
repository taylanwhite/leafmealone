extends RefCounted

## Authority: host only. A NICE BOY's decisions (R2 chunk 2; docs/GAME.md "The NICE
## BOYS encounter (R2)"): one per crew member, ticked by npcs/crew_member.gd in the
## modes it owns (PATROL, NOISE, SPOT, CHASE, INVESTIGATE, SEARCH, INSPECT). It
## returns where to walk, how fast and what to look at, and switches the crew's
## replicated mode; the catch itself is net/run_events/encounter.gd's.
##
##   - Senses: crew.can_see_peer (a 110 degree cone out to 26 m, 3 m all round,
##     line of sight to the chest) or crew.hears_tool (a running tool within 16 m).
##   - The first CREW_NOISE_SEEK_SECONDS of a chase, unspotted crew head for where
##     the loudest player's noise was; then they patrol near lot players, each in
##     his own sector of the yard.
##   - Spotted: SPOT (he freezes, snaps round, whistles, points, barks), then CHASE.
##   - In the chase, close and in front: Encounter.host_windup, the lunge.
##   - Lost: SEARCH around the last sighting; hide spots that can be inspected
##     (chunk 3's inspect_score) are, the most suspicious first; without those, a
##     spot he watched someone get into is opened (pull_out), gated by can_capture.

## crew_member.gd's Mode values (that script preloads this one).
const PATROL: int = 0
const NOISE: int = 1
const SPOT: int = 2
const CHASE: int = 3
const INVESTIGATE: int = 4
const SEARCH: int = 5
const INSPECT: int = 6


var _rng: RandomNumberGenerator
var _target: int = 0
var _last_seen := Vector3.INF
var _last_seen_at: float = -1000.0
var _waypoint := Vector3.INF
var _repick_at: float = 0.0
var _search_until: float = 0.0
var _spot_until: float = 0.0
var _investigate_until: float = -1.0
## The mode_at of the investigation _investigate_until belongs to.
var _investigate_for: float = -1.0
## The inspection under way: {"node", "point", "phase": "walk" | "poke", "until"}.
var _inspect: Dictionary = {}
var _inspected: Array = []
var _constants: Dictionary = {}


func _init(rng: RandomNumberGenerator) -> void:
	_rng = rng
	_constants = load("res://core/constants.gd").get_script_constant_map()


## Another chunk's tuning number if it has landed, else the default.
func _k(key: String, fallback: Variant) -> Variant:
	return _constants.get(key, fallback)


func target_peer() -> int:
	return _target


func last_seen() -> Vector3:
	return _last_seen


## One tick: {"goal": Vector3, "speed": float, "face": Vector3 or INF}.
func tick(crew: Node3D, _delta: float) -> Dictionary:
	var now := Net.server_time()
	var tree := crew.get_tree()
	var director := tree.get_first_node_in_group("run_director")
	var encounter := tree.get_first_node_in_group("nice_encounter")
	var mode := int(crew.get("mode"))
	var seen := _sense(crew, director)
	if not seen.is_empty():
		crew.set("last_contact_at", now)
		_target = int(seen["peer"])
		_last_seen = (seen["body"] as Node3D).global_position
		_last_seen_at = now
		if director != null and director.has_method("note_spotted"):
			director.call("note_spotted", _target)
		if mode != SPOT and mode != CHASE:
			_inspect = {}
			crew.call("host_set_mode", SPOT, _target, _last_seen)
			_spot_until = now + Constants.CREW_SPOT_FREEZE
			crew.call("bark", "spot")
			mode = SPOT
	match mode:
		SPOT:
			if now >= _spot_until:
				crew.call("host_set_mode", CHASE, _target)
				crew.call("bark", "chase")
			return _stand(crew, _last_seen)
		CHASE:
			if seen.is_empty() and now - _last_seen_at > Constants.CREW_LOST_AFTER:
				crew.call("host_set_mode", SEARCH, _target, _last_seen)
				crew.call("bark", "lost")
				_search_until = now + Constants.CREW_SEARCH_SECONDS
				_waypoint = Vector3.INF
				_inspected.clear()
				return _stand(crew, _last_seen)
			if not seen.is_empty() and bool(seen["sight"]) and encounter != null:
				var body := seen["body"] as Node3D
				var offset := body.global_position - crew.global_position
				var flat := Vector3(offset.x, 0.0, offset.z)
				var facing: Vector3 = crew.call("facing")
				if flat.length() <= Constants.CREW_LUNGE_RANGE and absf(offset.y) < 1.4 and rad_to_deg(facing.angle_to(flat.normalized())) <= Constants.CREW_LUNGE_CONE_DEG * 0.5:
					if bool(encounter.call("host_windup", crew, _target, false)):
						return _stand(crew, body.global_position)
			crew.call("bark", "chase")
			return {"goal": _last_seen, "speed": Constants.CREW_SPEED_CHASE, "face": Vector3.INF}
		SEARCH, INSPECT:
			var inspecting := _step_inspect(crew, encounter, now)
			if not inspecting.is_empty():
				return inspecting
			var opening := _open_seen_spot(crew, director, encounter)
			if not opening.is_empty():
				return opening
			if now >= _search_until:
				crew.call("host_set_mode", PATROL)
				_waypoint = Vector3.INF
				return _stand(crew, Vector3.INF)
			if _waypoint == Vector3.INF or _flat(crew, _waypoint) <= Constants.CREW_WAYPOINT_REACHED:
				_waypoint = _last_seen + _random_flat(Constants.CREW_SEARCH_RADIUS) if _last_seen.is_finite() else crew.global_position + _random_flat(Constants.CREW_SEARCH_RADIUS)
				if _rng.randf() < Constants.CREW_SEARCH_BARK_CHANCE:
					crew.call("bark", "search")
			return {"goal": _waypoint, "speed": Constants.CREW_SPEED_SEARCH, "face": Vector3.INF}
		INVESTIGATE:
			var at: Vector3 = crew.get("mode_arg")
			# A fresh investigation (each starts a new mode_at: a re-target mid-way,
			# or one after another was cut short by a sighting) walks over again.
			var started := float(crew.get("mode_at"))
			if started != _investigate_for:
				_investigate_for = started
				_investigate_until = -1.0
			if _flat(crew, at) > 1.1 and _investigate_until < 0.0:
				return {"goal": at, "speed": Constants.CREW_SPEED_SEARCH, "face": at}
			if _investigate_until < 0.0:
				_investigate_until = now + Constants.CREW_INVESTIGATE_SECONDS
			if now >= _investigate_until:
				_investigate_until = -1.0
				crew.call("host_set_mode", SEARCH if _last_seen.is_finite() and now - _last_seen_at < Constants.CREW_SEARCH_MEMORY else PATROL, _target, _last_seen)
				_search_until = now + Constants.CREW_SEARCH_SECONDS * 0.5
			return _stand(crew, at)
	# PATROL and NOISE.
	var opened := _open_seen_spot(crew, director, encounter)
	if not opened.is_empty():
		return opened
	var heard := _noise_lead(crew, director)
	if heard.is_finite():
		if mode != NOISE:
			crew.call("host_set_mode", NOISE, 0, heard)
		return {"goal": heard, "speed": Constants.CREW_SPEED_SEARCH, "face": Vector3.INF}
	if mode != PATROL:
		crew.call("host_set_mode", PATROL)
	if _waypoint == Vector3.INF or _flat(crew, _waypoint) <= Constants.CREW_WAYPOINT_REACHED or now >= _repick_at:
		_waypoint = _patrol_point(crew, director)
		_repick_at = now + Constants.CREW_PATROL_REPICK
	return {"goal": _waypoint, "speed": Constants.CREW_SPEED_PATROL, "face": Vector3.INF}


func _stand(crew: Node3D, face: Vector3) -> Dictionary:
	return {"goal": crew.global_position, "speed": 0.0, "face": face}


## Who he can see (or hear) now, the nearest first: {"peer", "body", "sight"} or {}.
func _sense(crew: Node3D, director: Node) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	for node: Node in crew.get_tree().get_nodes_in_group("players"):
		var body := node as Node3D
		if body == null:
			continue
		var peer_id := int(body.name)
		if director != null and not bool(director.call("can_capture", peer_id)):
			continue
		if director == null and Net.player_zone(peer_id) != Net.Zone.LOT:
			continue
		# Hidden is for the inspections, unless he watched them dive into a pile.
		if body.has_method("is_hidden") and bool(body.call("is_hidden")) and not (bool(body.get("in_pile")) and bool(body.get_meta("pile_seen", false))):
			continue
		var sight := bool(crew.call("can_see_peer", peer_id))
		if not sight and not bool(crew.call("hears_tool", peer_id)):
			continue
		var distance := crew.global_position.distance_to(body.global_position) - (0.0 if sight else Constants.CREW_HEARD_PENALTY)
		if distance < best_distance:
			best_distance = distance
			best = {"peer": peer_id, "body": body, "sight": sight}
	return best


## The first CREW_NOISE_SEEK_SECONDS of a chase: where the loudest player's noise
## was (net/run_events/heat.gd), or INF.
func _noise_lead(_crew: Node3D, director: Node) -> Vector3:
	if director == null or not director.has_method("loudest_peer"):
		return Vector3.INF
	if Net.server_time() - float(director.call("phase_started_at")) > Constants.CREW_NOISE_SEEK_SECONDS:
		return Vector3.INF
	var heat := _crew_tree(_crew).get_first_node_in_group("heat")
	var loud := int(director.call("loudest_peer"))
	if heat == null or loud == 0 or not heat.has_method("noise_point"):
		return Vector3.INF
	return heat.call("noise_point", loud)


func _crew_tree(crew: Node) -> SceneTree:
	return crew.get_tree()


## A patrol point near a lot player he could plausibly notice (seen or noisy), on
## his own side of the yard; with nobody to go on, a point in his sector.
func _patrol_point(crew: Node3D, director: Node) -> Vector3:
	var lot := _lot_center(crew)
	var sector: Vector3 = Constants.CREW_PATROL_SECTORS[posmod(int(crew.call("crew_index")) - 1, Constants.CREW_PATROL_SECTORS.size())]
	var candidates: Array[Vector3] = []
	var heat := crew.get_tree().get_first_node_in_group("heat")
	for node: Node in crew.get_tree().get_nodes_in_group("players"):
		var body := node as Node3D
		var peer_id := int(body.name) if body != null else 0
		if body == null or (director != null and not bool(director.call("can_capture", peer_id))):
			continue
		var noisy := heat != null and heat.has_method("noise_point") and (heat.call("noise_point", peer_id) as Vector3).is_finite()
		if noisy or bool(crew.call("sees_point", body.global_position + Vector3.UP * 1.2)):
			candidates.append(body.global_position)
	if not candidates.is_empty():
		var near := candidates[_rng.randi_range(0, candidates.size() - 1)]
		var lean := (lot + sector - near)
		lean.y = 0.0
		var bias := lean.normalized() * Constants.CREW_PATROL_RADIUS * 0.5 if lean.length() > 0.1 else Vector3.ZERO
		return near + bias + _random_flat(Constants.CREW_PATROL_RADIUS * 0.6)
	var point := lot + sector + _random_flat(Constants.CREW_PATROL_SECTOR_SPREAD)
	point.x = clampf(point.x, lot.x - Constants.CREW_PATROL_HALF_EXTENT, lot.x + Constants.CREW_PATROL_HALF_EXTENT)
	point.z = clampf(point.z, lot.z - Constants.CREW_PATROL_HALF_EXTENT, lot.z + Constants.CREW_PATROL_HALF_EXTENT)
	return point


## Chunk 3's inspections (hide spots and piles with inspect_score): pick the most
## suspicious, telegraph, walk over, poke for HIDE_INSPECT_SECONDS, then found (the
## gotcha, no lunge) or a near miss. {} when there's nothing to inspect.
func _step_inspect(crew: Node3D, encounter: Node, now: float) -> Dictionary:
	if _inspect.is_empty():
		if _inspected.size() >= int(_k("HIDE_INSPECT_PER_SEARCH", 2)):
			return {}
		var best: Node = null
		var best_score := float(_k("HIDE_INSPECT_THRESHOLD", 0.0))
		var candidates: Array[Node] = crew.get_tree().get_nodes_in_group("hide_spots")
		for node: Node in crew.get_tree().get_nodes_in_group("players"):
			if bool(node.get("in_pile")):
				candidates.append(node)
		for node: Node in candidates:
			if _inspected.has(node) or not node.has_method("inspect_score"):
				continue
			var score := float(node.call("inspect_score", crew.global_position, _last_seen))
			if score > best_score:
				best_score = score
				best = node
		if best == null:
			return {}
		_inspected.append(best)
		var point: Vector3 = best.call("inspect_point") if best.has_method("inspect_point") else (best as Node3D).global_position
		_inspect = {"node": best, "point": point, "phase": "walk", "until": 0.0}
		crew.call("host_set_mode", INSPECT, 0, point)
		# The line names what he's about to poke (R2b hide).
		crew.call("bark", str(best.call("inspect_bark")) if best.has_method("inspect_bark") else "inspect", true)
	var node: Node = _inspect["node"]
	if not is_instance_valid(node):
		_inspect = {}
		return {}
	var point: Vector3 = _inspect["point"]
	if str(_inspect["phase"]) == "walk":
		if _flat(crew, point) > 0.9:
			return {"goal": point, "speed": Constants.CREW_SPEED_SEARCH, "face": point}
		_inspect["phase"] = "poke"
		_inspect["until"] = now + float(_k("HIDE_INSPECT_SECONDS", 2.0))
		crew.set("last_contact_at", now)
		if node.has_method("host_inspect_begin"):
			node.call("host_inspect_begin", crew)
	if now < float(_inspect["until"]):
		return _stand(crew, (node as Node3D).global_position if node is Node3D else point)
	var outcome: Dictionary = node.call("host_inspect_resolve", crew) if node.has_method("host_inspect_resolve") else {}
	_inspect = {}
	crew.call("host_set_mode", SEARCH, _target, _last_seen)
	if StringName(outcome.get("outcome", &"")) == &"found" and encounter != null:
		encounter.call("host_windup", crew, int(outcome.get("peer", 0)), true)
	else:
		crew.call("bark", str(node.call("near_miss_bark")) if node.has_method("near_miss_bark") else "near_miss", true)
	return _stand(crew, point)


## Without chunk 3's inspections: a spot he watched someone get into is opened,
## if they can still be caught (the found-hider gotcha, no lunge). {} otherwise.
func _open_seen_spot(crew: Node3D, director: Node, encounter: Node) -> Dictionary:
	if encounter == null:
		return {}
	for node: Node in crew.get_tree().get_nodes_in_group("hide_spots"):
		if node.has_method("inspect_score") or not node.has_method("was_seen_entering"):
			continue
		var occupant := int(node.get("occupant"))
		if occupant == 0 or not bool(node.call("was_seen_entering")):
			continue
		if director != null and not bool(director.call("can_capture", occupant)):
			continue
		var spot := node as Node3D
		if _flat(crew, spot.global_position) > Constants.HIDE_REACH + 1.0:
			return {"goal": spot.global_position, "speed": Constants.CREW_SPEED_CHASE, "face": spot.global_position}
		var peer_id := int(node.call("pull_out"))
		if peer_id != 0:
			encounter.call("host_windup", crew, peer_id, true)
		return _stand(crew, spot.global_position)
	return {}


func _lot_center(crew: Node3D) -> Vector3:
	var world := crew.get_tree().get_first_node_in_group("world")
	var lot := world.get_node_or_null("LotZone") as Node3D if world != null else null
	return lot.global_position if lot != null else crew.global_position


func _random_flat(radius: float) -> Vector3:
	return Vector3(_rng.randf_range(-radius, radius), 0.0, _rng.randf_range(-radius, radius))


func _flat(crew: Node3D, point: Vector3) -> float:
	return Vector2(point.x - crew.global_position.x, point.z - crew.global_position.z).length()
