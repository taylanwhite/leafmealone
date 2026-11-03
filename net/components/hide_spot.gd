extends Node3D

## Authority: host decides who is inside, the exit side, suspicion and every
## inspection; every peer plays the cosmetics from the replicated results. A
## place to hide in during a run event (OQ-010; R2 chunk 3, docs/GAME.md "Hiding").
## The look (shed, bin, hedge, and its doors, lids, tells and stickers) is
## props/hide_spot.gd; the hider's dive, view and muffle is player/hide_view.gd.
##
## Searching is suspicion, not "seen means doomed": being seen going in, peeking
## or rustling where a NICE BOY can see the spot, recent use and being near the
## last sighting raise a spot's suspicion. A searching NICE BOY (the crew brain,
## R2 chunk 2) asks inspect_score(), walks to inspect_point(), calls
## host_inspect_begin(), pokes for Constants.HIDE_INSPECT_SECONDS, then
## host_inspect_resolve(): found (suspicion at HIDE_FOUND_AT or more, and the
## hider can be caught) lifts the hider out toward him into the gotcha; anything
## else is a near miss and a Courtesy Notice sticker on the spot. An unseen hider
## who stays still always gets the near miss.
##
## Clients ask with request_enter() and request_exit(); the host answers with
## _rpc_set_occupants (or a refusal to the asker), _rpc_exit_side, _rpc_inspect
## and _rpc_notice.

signal occupant_changed(peer_id: int)
signal occupants_changed(peers: Array)

## The four sides of the box in its own frame: 0 the front (-Z, where a shed's
## door is), 1 right (+X), 2 back (+Z), 3 left (-X).
const SIDES: Array[Vector3] = [Vector3(0.0, 0.0, -1.0), Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0), Vector3(-1.0, 0.0, 0.0)]
## What the exit sweep collides with: the world and props (the player's own mask).
const EXIT_MASK: int = 5
## Layout of the spots' insides (m): how far in from a side the body rests, and
## how far apart a shed's two places sit.
const INSIDE_DEPTH: float = 0.4
const PLACE_OFFSET: float = 0.45

## Totals for this process, read by net/dev/probe.gd and the soak report. Host only.
static var stats: Dictionary = {"entered": 0, "refused": 0, "pulled_out": 0, "inspected": 0, "near_misses": 0, "found": 0}

## What kind of spot this is ("shed", "bin", "hedge") and its box, set by the
## look (props/hide_spot.gd) before this script's _ready runs.
var spot_kind: String = "hedge"
var box_size := Vector3(1.6, 2.0, 1.6)
var capacity: int = 1
## The first peer hiding here, or 0 (older callers read this).
var occupant: int = 0
## Courtesy Notice stickers slapped on this spot today (every peer).
var notices: int = 0

## Peers inside, in arrival order, the side each came in by and the place each
## has (a shed's two; a newcomer gets the lowest free one) (every peer).
var _occupants: Array[int] = []
var _sides: Array[int] = []
var _slots: Array[int] = []
## Host only.
var _suspicion: float = 0.0
var _last_used_at: float = -1000.0
var _inspected_at: float = -1000.0
var _inspector: Node
var _inspect_began: float = -1.0
var _last_seen_hint := Vector3.INF
var _rustle_cool: Dictionary = {}
var _last_yaw: Dictionary = {}
## Host: each occupant's smoothed turn speed (rad/s), and who is being pulled
## out right now (peer -> true) so a climb-out can't race the reveal (R2b hide).
var _turn_speed: Dictionary = {}
var _pulling: Dictionary = {}
## Every peer: a bin's yard-facing side, once known (-1 not yet).
var _yard_side: int = -1


func _ready() -> void:
	add_to_group("hide_spots")
	Net.player_left.connect(_on_player_left)
	# A late joiner asks once its own copy of the lot exists, so the reply has somewhere to land.
	if not Net.is_host() and multiplayer.multiplayer_peer != null:
		_rpc_request_state.rpc_id(1)


## The lot can be unloaded with someone inside. Let them out locally on every peer.
func _exit_tree() -> void:
	var inside := _occupants.duplicate()
	_occupants.clear()
	_sides.clear()
	_slots.clear()
	occupant = 0
	for peer_id: int in inside:
		var body := _player(peer_id)
		if body != null and body.has_method("set_hidden_in"):
			body.call("set_hidden_in", null)


## The hide spot this peer is in, or null.
static func spot_of(tree: SceneTree, peer_id: int) -> Node3D:
	for node: Node in tree.get_nodes_in_group("hide_spots"):
		if node.has_method("is_inside") and bool(node.call("is_inside", peer_id)):
			return node as Node3D
	return null


func occupants() -> Array:
	return _occupants.duplicate()


func is_inside(peer_id: int) -> bool:
	return _occupants.has(peer_id)


func has_room() -> bool:
	return _occupants.size() < capacity


## Which side peer came in by, or -1.
func side_of(peer_id: int) -> int:
	var index := _occupants.find(peer_id)
	return _sides[index] if index >= 0 and index < _sides.size() else -1


## Which of the spot's places peer has (a shed has two), or 0. It stays theirs
## while others come and go.
func slot_of(peer_id: int) -> int:
	var index := _occupants.find(peer_id)
	return _slots[index] if index >= 0 and index < _slots.size() else 0


## The place the next one in would get: the lowest one nobody has.
func free_slot() -> int:
	for slot: int in maxi(capacity, 1):
		if not _slots.has(slot):
			return slot
	return 0


# ---------------------------------------------------------------- geometry

## How far a point is from the box, flat (0 inside it). Reach is measured to
## the nearest edge, so a long hedge is as easy to get into at its end.
func reach_distance(at: Vector3) -> float:
	var local := global_transform.affine_inverse() * at
	var half := box_size * 0.5
	var nearest := Vector3(clampf(local.x, -half.x, half.x), 0.0, clampf(local.z, -half.z, half.z))
	return Vector2(local.x - nearest.x, local.z - nearest.z).length()


## The side someone at this point would come in by: the face they stand
## before (a shed only by its door).
func side_toward(at: Vector3) -> int:
	if spot_kind == "shed":
		return 0
	return _face_before(at)


## Whether someone here can get in: a shed only from before its door, so nobody
## steps in through a wall.
func can_enter_from(at: Vector3) -> bool:
	return spot_kind != "shed" or _face_before(at) == 0


## The face of the box this point stands before.
func _face_before(at: Vector3) -> int:
	var local := global_transform.affine_inverse() * at
	var half := box_size * 0.5
	var best := 0
	var best_score := -INF
	for side: int in SIDES.size():
		var direction: Vector3 = SIDES[side]
		var extent := absf(direction.x) * half.x + absf(direction.z) * half.z
		var score := (local.x * direction.x + local.z * direction.z) / maxf(extent, 0.1)
		if score > best_score:
			best_score = score
			best = side
	return best


## The outward direction of a side, in world space (flat).
func side_direction(side: int) -> Vector3:
	return (global_basis * SIDES[clampi(side, 0, 3)]).normalized()


## Where someone stands just outside a side (the start of a dive, the end of a
## climb-out), slot along the side for a shed's second place.
func entry_point(side: int, slot: int = 0) -> Vector3:
	var direction: Vector3 = SIDES[clampi(side, 0, 3)]
	var half := box_size * 0.5
	var extent := absf(direction.x) * half.x + absf(direction.z) * half.z
	var offset := _slot_offset(side, slot)
	if spot_kind == "shed":
		# Both of a shed's places step out on the latch side of the doorway, clear of
		# the door standing open on its hinge side (R2b hide).
		offset = Vector3(-direction.z, 0.0, direction.x) * (Constants.HIDE_SHED_EXIT_ALONG + Constants.HIDE_SHED_EXIT_SLOT_STEP * float(slot % 2))
	var local := direction * (extent + Constants.HIDE_EXIT_GAP + Constants.HIDE_EXIT_RADIUS) + offset
	return global_transform * Vector3(local.x, 0.05, local.z)


## Where the body rests while hidden: just inside the side it came in by.
func inside_point(side: int, slot: int = 0) -> Vector3:
	var direction: Vector3 = SIDES[clampi(side, 0, 3)]
	var half := box_size * 0.5
	var extent := absf(direction.x) * half.x + absf(direction.z) * half.z
	var local := direction * maxf(0.0, extent - INSIDE_DEPTH) + _slot_offset(side, slot)
	return global_transform * Vector3(local.x, 0.02, local.z)


## The eye while hidden: on the face of the side the hider came in by (just
## outside it, so no wall is ever in front of the lens), looking out. A bin's
## slit faces the yard whichever side you vaulted in from; a shed's eye is just
## inside the door at its knot holes, one each for its two places (R2b hide).
## Its -Z is the facing the view turns around.
func peek_transform(side: int, slot: int = 0) -> Transform3D:
	side = eye_side(side)
	var direction: Vector3 = SIDES[clampi(side, 0, 3)]
	var half := box_size * 0.5
	var extent := absf(direction.x) * half.x + absf(direction.z) * half.z
	var eye_y := _eye_height()
	var local := direction * (extent + 0.03) + _slot_offset(side, slot) + Vector3(0.0, eye_y, 0.0)
	if spot_kind == "shed":
		var across := _slot_offset(side, slot).normalized() * Constants.HIDE_SHED_EYE_SIDE if capacity > 1 else Vector3.ZERO
		local = direction * (extent - Constants.HIDE_SHED_EYE_IN) + across + Vector3(0.0, eye_y, 0.0)
	var facing := global_basis * direction
	var basis := Basis.looking_at(Vector3(facing.x, 0.0, facing.z).normalized(), Vector3.UP)
	return Transform3D(basis, global_transform * local)


## The side a hider in by `side` looks out of: a bin's slit faces the yard (the
## side most toward the job lot's middle, the same on every peer); every other
## spot looks out the way you came in.
func eye_side(side: int) -> int:
	if spot_kind != "bin":
		return side
	if _yard_side < 0:
		var lot := get_tree().get_first_node_in_group("job_lot") as Node3D if is_inside_tree() else null
		if lot == null:
			return side
		var toward := lot.global_position - global_position
		toward.y = 0.0
		if toward.length() < 0.1:
			return side
		var best := -INF
		for each: int in SIDES.size():
			var score := side_direction(each).dot(toward.normalized())
			if score > best:
				best = score
				_yard_side = each
	return _yard_side


## The spot's own peek anchor for that side and slot: a Node3D at
## peek_transform (made on first use), for the hider's camera shot.
func peek_anchor(side: int = -1, slot: int = 0) -> Node3D:
	var use_side := side if side >= 0 else 0
	var anchor_name := "PeekAnchor" if use_side == 0 and slot == 0 else "PeekAnchor_%d_%d" % [use_side, slot]
	var anchor := get_node_or_null(anchor_name) as Node3D
	if anchor == null:
		anchor = Marker3D.new()
		anchor.name = anchor_name
		add_child(anchor)
	anchor.global_transform = peek_transform(use_side, slot)
	return anchor


## Where a NICE BOY stands to poke this spot: before its front, or before the
## side the first hider came in by.
func inspect_point() -> Vector3:
	var side := eye_side(_sides[0] if not _sides.is_empty() else 0)
	var direction: Vector3 = SIDES[clampi(side, 0, 3)]
	var half := box_size * 0.5
	var extent := absf(direction.x) * half.x + absf(direction.z) * half.z
	# Within arm's reach of the face (R2c hide: from 1.2 m out he stood in the
	# picket fence and never touched the hider).
	var local := direction * (extent + Constants.HIDE_INSPECT_REACH)
	return global_transform * Vector3(local.x, 0.05, local.z)


func top_point() -> Vector3:
	return global_transform * Vector3(0.0, box_size.y * 0.85, 0.0)


func _eye_height() -> float:
	match spot_kind:
		"shed":
			# At the knot holes, a hand under the top of the door (props/hide_spot.gd
			# draws them there): any higher looks into the lintel.
			return shed_knot_height(box_size.y)
		"bin":
			return box_size.y - 0.12
		_:
			return box_size.y - 0.2


## A shed this tall: its door's height (m), and the knot holes in it (m, the
## hider's eye) a hand under the door's top. Shared with props/hide_spot.gd's model.
static func shed_door_height(height: float) -> float:
	return height * Constants.HIDE_SHED_WALL_SHARE - Constants.HIDE_SHED_DOOR_HEADROOM


static func shed_knot_height(height: float) -> float:
	return shed_door_height(height) - Constants.HIDE_SHED_KNOT_DROP


func _slot_offset(side: int, slot: int) -> Vector3:
	if capacity <= 1:
		return Vector3.ZERO
	var direction: Vector3 = SIDES[clampi(side, 0, 3)]
	var along := Vector3(-direction.z, 0.0, direction.x)
	return along * (PLACE_OFFSET if slot % 2 == 1 else -PLACE_OFFSET)


# ---------------------------------------------------------------- requests

func request_enter() -> void:
	if Net.is_host():
		_handle_enter(Net.local_peer_id())
	else:
		_rpc_request_enter.rpc_id(1)


## side_hint: the side the hider's camera faces (side_toward of a point ahead),
## -1 for any. The host sweeps for room and picks the nearest clear one.
func request_exit(side_hint: int = -1) -> void:
	if Net.is_host():
		_handle_exit(Net.local_peer_id(), side_hint)
	else:
		_rpc_request_exit_toward.rpc_id(1, side_hint)


func _handle_enter(peer_id: int) -> void:
	var body := _player(peer_id)
	var reason := _refusal(peer_id, body)
	if reason != "":
		stats["refused"] = int(stats["refused"]) + 1
		_refuse(peer_id, reason)
		return
	var side := side_toward(body.global_position)
	var seen := _seen_by_crew(body.global_position + Vector3(0.0, 1.2, 0.0), peer_id)
	if seen:
		_suspicion = maxf(_suspicion, Constants.SUSPICION_SEEN_ENTERING)
	_last_used_at = Net.server_time()
	stats["entered"] = int(stats["entered"]) + 1
	var peers := _occupants.duplicate()
	var sides := _sides.duplicate()
	var slots := _slots.duplicate()
	peers.append(peer_id)
	sides.append(side)
	slots.append(free_slot())
	_rpc_set_occupants.rpc(peers, sides, slots, Net.server_time())


## Why peer can't get in now, or "".
func _refusal(peer_id: int, body: Node3D) -> String:
	if body == null:
		return "gone"
	if spot_of(get_tree(), peer_id) != null:
		return "inside"
	if not has_room():
		return "full"
	if reach_distance(body.global_position) > Constants.HIDE_REACH_EDGE + Constants.HIDE_REACH_SLACK:
		return "far"
	# A shed's door: the asker checked can_enter_from; the host, a moment behind,
	# only turns away someone round the back half.
	if spot_kind == "shed" and (global_transform.affine_inverse() * body.global_position).z > 0.0:
		return "door"
	var director := get_tree().get_first_node_in_group("run_director")
	if director != null and bool(director.call("is_captured", peer_id)):
		return "caught"
	if body.has_method("is_staged") and bool(body.call("is_staged")):
		return "staged"
	return ""


func _refuse(peer_id: int, reason: String) -> void:
	if peer_id == Net.local_peer_id():
		_on_refused(reason)
	else:
		_rpc_refuse.rpc_id(peer_id, reason)


func _on_refused(reason: String) -> void:
	var me := _player(Net.local_peer_id())
	if me != null and me.has_method("on_hide_refused"):
		me.call("on_hide_refused", self, reason)


func _handle_exit(peer_id: int, side_hint: int) -> void:
	# Found: his hands are already on you.
	if not _occupants.has(peer_id) or _pulling.has(peer_id):
		return
	var side := host_exit_side(peer_id, side_hint)
	_rpc_exit_side.rpc(peer_id, side, Net.server_time())


## Host: the side peer leaves by: the one it faces if there's room to stand
## there, else the next clear one by angle, else the one it came in by. A shed
## only lets you out of its door.
func host_exit_side(peer_id: int, side_hint: int) -> int:
	if spot_kind == "shed":
		return 0
	var came_in := side_of(peer_id)
	var order: Array[int] = []
	var first := side_hint if side_hint >= 0 else maxi(came_in, 0)
	for step: int in [0, 1, 3, 2]:
		order.append((first + step) % 4)
	for side: int in order:
		if _exit_clear(side, slot_of(peer_id)):
			return side
	return maxi(came_in, 0)


## Room for a standing body just outside that side, with floor under it and
## nothing between it and the box.
func _exit_clear(side: int, slot: int) -> bool:
	var space := get_world_3d().direct_space_state
	var at := entry_point(side, slot)
	var capsule := CapsuleShape3D.new()
	capsule.radius = Constants.HIDE_EXIT_RADIUS
	capsule.height = Constants.HIDE_EXIT_HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3(0.0, Constants.HIDE_EXIT_HEIGHT * 0.5 + 0.08, 0.0))
	query.collision_mask = EXIT_MASK
	query.exclude = _own_rids()
	if not space.intersect_shape(query, 1).is_empty():
		return false
	var down := PhysicsRayQueryParameters3D.create(at + Vector3(0.0, 0.6, 0.0), at + Vector3(0.0, -1.0, 0.0), 1)
	down.exclude = _own_rids()
	return not space.intersect_ray(down).is_empty()


func _own_rids() -> Array[RID]:
	var rids: Array[RID] = []
	for node: Node in find_children("*", "CollisionObject3D", true, false):
		rids.append((node as CollisionObject3D).get_rid())
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node is CollisionObject3D:
			rids.append((node as CollisionObject3D).get_rid())
	return rids


# ---------------------------------------------------------------- suspicion and inspection

## Host: how suspicious this spot looks, 0 to 1.
func suspicion() -> float:
	var recent := Constants.SUSPICION_RECENT_USE if Net.server_time() - _last_used_at < Constants.SUSPICION_RECENT_SECONDS else 0.0
	return clampf(_suspicion + recent, 0.0, 1.0)


## Host: whether it's worth a look from `from`, given where someone was last
## seen (Vector3.INF if nowhere): suspicion + HIDE_INSPECT_BASE - meters /
## HIDE_INSPECT_METERS_PER_POINT, plus a little near the last sighting. Below 0
## means skip (just inspected, or being poked).
func inspect_score(from: Vector3, last_seen: Vector3) -> float:
	_drop_stale_inspector()
	if Net.server_time() - _inspected_at < Constants.HIDE_INSPECT_COOLDOWN or _inspector != null:
		return -1.0
	_last_seen_hint = last_seen
	return suspicion() + _near_bonus(last_seen) + Constants.HIDE_INSPECT_BASE - from.distance_to(global_position) / Constants.HIDE_INSPECT_METERS_PER_POINT


## A poke nobody resolved (the NICE BOY was bonked, stunned or sent home) stops
## holding the spot once it's well overdue or he's gone.
func _drop_stale_inspector() -> void:
	if _inspector == null:
		return
	if not is_instance_valid(_inspector) or Net.server_time() - _inspect_began > Constants.HIDE_INSPECT_SECONDS + Constants.HIDE_INSPECT_STALE_SLACK:
		_inspector = null


## The bark kinds a NICE BOY uses on this spot (ui/strings.gd CREW_BARKS): his
## line as he walks over to it and after a near miss name what it is (R2b hide).
func inspect_bark() -> String:
	return "inspect_" + spot_kind


func near_miss_bark() -> String:
	return "near_miss_" + spot_kind


## Host only, for older callers: whether it looks bad enough to be opened.
func was_seen_entering() -> bool:
	return not _occupants.is_empty() and suspicion() >= Constants.HIDE_FOUND_AT


func _near_bonus(last_seen: Vector3) -> float:
	if not last_seen.is_finite():
		return 0.0
	return Constants.SUSPICION_NEAR_LAST_SEEN if Vector2(last_seen.x - global_position.x, last_seen.z - global_position.z).length() <= Constants.SUSPICION_NEAR_METERS else 0.0


## Host: a NICE BOY at the inspect point starts poking. Everyone sees the
## telegraph and the poke (_rpc_inspect).
func host_inspect_begin(crew: Node) -> void:
	if not Net.is_host() or crew == null:
		return
	_inspector = crew
	_inspect_began = Net.server_time()
	stats["inspected"] = int(stats["inspected"]) + 1
	_rpc_inspect.rpc(_crew_index(crew), Net.server_time(), &"begin", 0)


## Host: the poke stopped short (he was bonked, stunned or sent home): no
## outcome, no sticker; the spot can be looked at again.
func host_inspect_cancel(crew: Node) -> void:
	if not Net.is_host() or _inspector == null:
		return
	if crew != null and is_instance_valid(_inspector) and crew != _inspector:
		return
	var who: Node = _inspector if is_instance_valid(_inspector) else null
	_inspector = null
	_rpc_inspect.rpc(_crew_index(who), Net.server_time(), &"cancel", 0)


## Host: the poke is over. {outcome: &"found" | &"near_miss", peer}. Found lifts
## the first hider out toward the NICE BOY; the caller hands them to the gotcha
## (without the R2 Encounter, the director takes them at once).
func host_inspect_resolve(crew: Node) -> Dictionary:
	if not Net.is_host():
		return {"outcome": &"near_miss", "peer": 0}
	_inspector = null
	_inspected_at = Net.server_time()
	var total := clampf(suspicion() + _near_bonus(_last_seen_hint), 0.0, 1.0)
	var target := 0
	for peer_id: int in _occupants:
		if _can_capture(peer_id):
			target = peer_id
			break
	if target != 0 and total >= Constants.HIDE_FOUND_AT:
		stats["found"] = int(stats["found"]) + 1
		_rpc_inspect.rpc(_crew_index(crew), Net.server_time(), &"found", target)
		_pull(target, crew)
		_suspicion = 0.0
		return {"outcome": &"found", "peer": target}
	stats["near_misses"] = int(stats["near_misses"]) + 1
	_rpc_inspect.rpc(_crew_index(crew), Net.server_time(), &"near_miss", 0)
	_rpc_notice.rpc(mini(notices + 1, Constants.HIDE_NOTICE_MAX))
	# He looked and saw nothing: it looks a little less suspicious now.
	_suspicion *= 0.5
	return {"outcome": &"near_miss", "peer": 0}


## Host only, for the older crew: open the spot and take whoever can be taken.
## Respects immunity (director.can_capture). Returns the peer, or 0.
func pull_out() -> int:
	for peer_id: int in _occupants:
		if _can_capture(peer_id):
			_pull(peer_id, _nearest_crew())
			return peer_id
	return 0


## The hider comes out toward the NICE BOY (every peer sees the lift). The spot
## comes open around his face first (_rpc_inspect found, HIDE_FOUND_REVEAL), then
## they're pulled out onto their feet beside him, never left on top of the spot;
## the landing rides on the player as meta "hide_pulled_to" ([where, server time
## they're down]) so the gotcha stands them there (net/run_events/encounter.gd).
func _pull(peer_id: int, crew: Node) -> void:
	stats["pulled_out"] = int(stats["pulled_out"]) + 1
	var landing := found_landing(peer_id, crew as Node3D)
	_pulling[peer_id] = true
	var body := _player(peer_id)
	if body != null:
		body.set_meta(&"hide_pulled_to", [landing, Net.server_time() + Constants.HIDE_FOUND_REVEAL + Constants.HIDE_PULL_SECONDS])
	get_tree().create_timer(Constants.HIDE_FOUND_REVEAL).timeout.connect(func() -> void:
		if not is_instance_valid(self) or not is_inside_tree():
			return
		_pulling.erase(peer_id)
		if _occupants.has(peer_id):
			_rpc_pull.rpc(peer_id, landing, Net.server_time()))
	# Without the R2 Encounter there's no gotcha to hand them to: the director takes them.
	if get_tree().get_first_node_in_group("nice_encounter") == null:
		var director := get_tree().get_first_node_in_group("run_director")
		if director != null:
			get_tree().create_timer(Constants.HIDE_FOUND_REVEAL + Constants.HIDE_PULL_SECONDS).timeout.connect(func() -> void:
				if is_instance_valid(director):
					director.call("note_capture", peer_id))


## Where a found hider is set down: on the ground just out from the face he
## looked in at, a step to one side of him (whichever side has room), so the two
## of them stand apart for the gotcha. A shed's is off the hinge side of its door.
func found_landing(peer_id: int, crew: Node3D) -> Vector3:
	var side := eye_side(maxi(side_of(peer_id), 0))
	var direction: Vector3 = SIDES[side]
	var half := box_size * 0.5
	var extent := absf(direction.x) * half.x + absf(direction.z) * half.z
	var along := Vector3(-direction.z, 0.0, direction.x)
	var out := direction * (extent + Constants.HIDE_FOUND_LAND_OUT)
	var options: Array[Vector3] = []
	if spot_kind == "shed":
		# The door swings out on its left hinge (-X): land on the latch side.
		options = [out + Vector3(Constants.HIDE_FOUND_LAND_SIDE * Constants.HIDE_FOUND_LAND_ALONG_SHED, 0.0, 0.0)]
	else:
		var first := 1.0
		if crew != null:
			var local_crew := global_transform.affine_inverse() * crew.global_position
			first = -1.0 if (local_crew - out).dot(along) > 0.0 else 1.0
		options = [out + along * first * Constants.HIDE_FOUND_LAND_SIDE, out - along * first * Constants.HIDE_FOUND_LAND_SIDE, out]
	for local: Vector3 in options:
		var at := global_transform * Vector3(local.x, 0.05, local.z)
		if not is_inside_tree() or _room_at(at):
			return at
	return global_transform * Vector3(options[0].x, 0.05, options[0].z)


## Room for a standing body at `at`, ignoring the spot itself and the players.
func _room_at(at: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = Constants.HIDE_EXIT_RADIUS * 0.85
	capsule.height = Constants.HIDE_EXIT_HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3(0.0, Constants.HIDE_EXIT_HEIGHT * 0.5 + 0.08, 0.0))
	query.collision_mask = EXIT_MASK
	query.exclude = _own_rids()
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _can_capture(peer_id: int) -> bool:
	var director := get_tree().get_first_node_in_group("run_director")
	return director == null or bool(director.call("can_capture", peer_id))


## Host: suspicion from what the hiders do where a NICE BOY could see it.
func _physics_process(delta: float) -> void:
	if not Net.is_host():
		return
	_suspicion = maxf(0.0, _suspicion - Constants.SUSPICION_DECAY_PER_S * delta)
	if _occupants.is_empty():
		_last_yaw.clear()
		return
	var watched := _seen_by_crew(top_point(), 0)
	# Settling in after the dive turns the body round once: that's no rustle.
	var settling := Net.server_time() - _last_used_at < Constants.HIDE_SETTLE_SECONDS
	for peer_id: int in _occupants:
		var body := _player(peer_id)
		if body == null:
			continue
		var yaw := float(body.get("body_yaw"))
		var step := absf(angle_difference(float(_last_yaw.get(peer_id, yaw)), yaw)) / maxf(delta, 0.001)
		# Smoothed like the shiver everyone sees (props/hide_spot.gd): a client's
		# yaw arrives in network steps, which aren't a jerk of the head.
		var rate := lerpf(float(_turn_speed.get(peer_id, 0.0)), step, 1.0 - exp(-delta / Constants.HIDE_TREMBLE_SMOOTH))
		_turn_speed[peer_id] = rate if not settling else 0.0
		_last_yaw[peer_id] = yaw
		_rustle_cool[peer_id] = maxf(0.0, float(_rustle_cool.get(peer_id, 0.0)) - delta)
		if not watched or settling:
			continue
		if bool(body.get("peeking")):
			_suspicion = minf(1.0, _suspicion + Constants.SUSPICION_PEEK_PER_S * delta)
		if spot_kind == "hedge" and rate > Constants.HIDE_TREMBLE_TURN_RATE and float(_rustle_cool[peer_id]) <= 0.0:
			_rustle_cool[peer_id] = Constants.HIDE_TREMBLE_SECONDS
			_suspicion = minf(1.0, _suspicion + Constants.SUSPICION_RUSTLE)


## Host: whether any NICE BOY within SUSPICION_CONE_METERS could see this point
## (the crew's own sees_point when it has one: chunk 2's cone; otherwise a
## facing cone and a clear line, ignoring the spot itself). peer_id > 0 also
## accepts the crew's can_see_peer for that player.
func _seen_by_crew(point: Vector3, peer_id: int) -> bool:
	for crew: Node in _crew_nodes():
		var body := crew as Node3D
		if body == null or body.global_position.distance_to(point) > Constants.SUSPICION_CONE_METERS:
			continue
		if crew.has_method("sees_point") and bool(crew.call("sees_point", point)):
			return true
		# Chunk 2's sees_point counts the spot itself as in the way of its own top
		# (the line ends on its surface), so a peek in plain view never raised
		# suspicion: the cone and a line that ignores the spot decide that (R2
		# integration).
		if not _facing(body, point):
			continue
		# A player going in is seen past everything, the spot too; the spot's own
		# top (a peek, a rustle) only past everything else.
		if peer_id > 0:
			if crew.has_method("can_see_peer") and bool(crew.call("can_see_peer", peer_id)):
				return true
		elif _clear_line(body.global_position + Vector3(0.0, 1.4, 0.0), point, body):
			return true
	return false


## The NICE BOY faces +Z (crew_member.gd turns its +Z toward where it walks).
func _facing(crew: Node3D, point: Vector3) -> bool:
	var forward := crew.global_basis.z
	forward.y = 0.0
	var to := point - crew.global_position
	to.y = 0.0
	if to.length() < 1.0:
		return true
	return rad_to_deg(forward.normalized().angle_to(to.normalized())) <= Constants.SUSPICION_CONE_HALF_DEG


func _clear_line(from: Vector3, to: Vector3, crew: Node3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	var rids := _own_rids()
	if crew is CollisionObject3D:
		rids.append((crew as CollisionObject3D).get_rid())
	query.exclude = rids
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _crew_nodes() -> Array[Node]:
	var found: Array[Node] = []
	for group: String in ["nice_crew", "crew"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			if not found.has(node):
				found.append(node)
	return found


func _crew_index(crew: Node) -> int:
	if crew == null:
		return 0
	if crew.has_method("crew_index"):
		return int(crew.call("crew_index"))
	return str(crew.name).trim_prefix("Crew").to_int()


func _crew_by_index(index: int) -> Node3D:
	for crew: Node in _crew_nodes():
		if _crew_index(crew) == index:
			return crew as Node3D
	return null


func _nearest_crew() -> Node:
	var best: Node = null
	var best_distance := INF
	for crew: Node in _crew_nodes():
		var distance := (crew as Node3D).global_position.distance_to(global_position)
		if distance < best_distance:
			best_distance = distance
			best = crew
	return best


# ---------------------------------------------------------------- RPCs

@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_enter() -> void:
	if Net.is_host():
		_handle_enter(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_exit() -> void:
	if Net.is_host():
		_handle_exit(multiplayer.get_remote_sender_id(), -1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_exit_toward(side_hint: int) -> void:
	if Net.is_host():
		_handle_exit(multiplayer.get_remote_sender_id(), clampi(side_hint, -1, 3))


## To the asker only: no room, too far, or not now. Their dive bonks off.
@rpc("authority", "call_remote", "reliable")
func _rpc_refuse(reason: String) -> void:
	_on_refused(reason)


## Who is inside, by which side and in which place, from the host's server time at.
@rpc("authority", "call_local", "reliable")
func _rpc_set_occupants(peers: Array, entry_sides: Array, slots: Array, at: float) -> void:
	var before := _occupants.duplicate()
	_occupants.clear()
	_sides.clear()
	_slots.clear()
	for index: int in peers.size():
		_occupants.append(int(peers[index]))
		_sides.append(int(entry_sides[index]) if index < entry_sides.size() else 0)
		_slots.append(int(slots[index]) if index < slots.size() else index)
	occupant = _occupants[0] if not _occupants.is_empty() else 0
	for peer_id: int in before:
		if not _occupants.has(peer_id):
			var leaving := _player(peer_id)
			if leaving != null and leaving.has_method("set_hidden_in"):
				leaving.call("set_hidden_in", null)
			# Gone without climbing out (a disconnect): the look lets go of them too.
			_on_exited(peer_id, -1, at)
	for peer_id: int in _occupants:
		if not before.has(peer_id):
			var entering := _player(peer_id)
			if entering != null and entering.has_method("set_hidden_in"):
				entering.call("set_hidden_in", self, side_of(peer_id), at)
			_on_entered(peer_id, side_of(peer_id), at)
	occupant_changed.emit(occupant)
	occupants_changed.emit(occupants())


## peer leaves by side, from server time at: every peer sees them burst out there.
@rpc("authority", "call_local", "reliable")
func _rpc_exit_side(peer_id: int, side: int, at: float) -> void:
	var index := _occupants.find(peer_id)
	if index < 0:
		return
	var slot := slot_of(peer_id)
	_forget(index)
	occupant = _occupants[0] if not _occupants.is_empty() else 0
	var body := _player(peer_id)
	if body != null and body.has_method("set_hidden_in"):
		body.call("set_hidden_in", null, -1, at, entry_point(side, slot))
	_on_exited(peer_id, side, at)
	occupant_changed.emit(occupant)
	occupants_changed.emit(occupants())


## Found: peer is lifted out toward to, from server time at.
@rpc("authority", "call_local", "reliable")
func _rpc_pull(peer_id: int, to: Vector3, at: float) -> void:
	var index := _occupants.find(peer_id)
	if index < 0:
		return
	_forget(index)
	occupant = _occupants[0] if not _occupants.is_empty() else 0
	var body := _player(peer_id)
	if body != null and body.has_method("set_hidden_in"):
		body.call("set_hidden_in", null, -1, at, to, true)
	_on_exited(peer_id, -1, at)
	occupant_changed.emit(occupant)
	occupants_changed.emit(occupants())


func _forget(index: int) -> void:
	_occupants.remove_at(index)
	if index < _sides.size():
		_sides.remove_at(index)
	if index < _slots.size():
		_slots.remove_at(index)


## A NICE BOY's poke: phase &"begin", &"near_miss", &"found" or &"cancel", from
## server time at. peer_id: who he found (found only; 0 otherwise), so a second
## occupant of a shed isn't caught by someone else's find.
@rpc("authority", "call_local", "reliable")
func _rpc_inspect(crew_index: int, at: float, phase: StringName, peer_id: int) -> void:
	_on_inspect(_crew_by_index(crew_index), phase, at, peer_id)


@rpc("authority", "call_local", "reliable")
func _rpc_notice(count: int) -> void:
	var before := notices
	notices = count
	_on_notices(before, count)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_state() -> void:
	if not Net.is_host():
		return
	var asker := multiplayer.get_remote_sender_id()
	if not _occupants.is_empty():
		# Old news by now: at is long past, so they're simply inside.
		_rpc_set_occupants.rpc_id(asker, _occupants, _sides, _slots, Net.server_time() - 10.0)
	if notices > 0:
		_rpc_notice.rpc_id(asker, notices)


func _on_player_left(peer_id: int) -> void:
	if not Net.is_host() or not _occupants.has(peer_id):
		return
	var peers := _occupants.duplicate()
	var sides := _sides.duplicate()
	var slots := _slots.duplicate()
	var index := peers.find(peer_id)
	peers.remove_at(index)
	sides.remove_at(index)
	slots.remove_at(index)
	_rpc_set_occupants.rpc(peers, sides, slots, Net.server_time())


# ---------------------------------------------------------------- the look's hooks
# props/hide_spot.gd overrides these with doors, lids, leaves and stickers.

func _on_entered(_peer_id: int, _side: int, _at: float) -> void:
	pass


func _on_exited(_peer_id: int, _side: int, _at: float) -> void:
	pass


func _on_inspect(_crew: Node3D, _phase: StringName, _at: float, _peer_id: int = 0) -> void:
	pass


func _on_notices(_before: int, _count: int) -> void:
	pass


func _player(peer_id: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node as Node3D
	return null
