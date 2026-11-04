extends RefCounted

## Authority: the local peer, for its own character only. A bot's work on the lot,
## played with the same inputs a person presses: grab the rake when it is free,
## rake leaves into a pile and bag it, and carry loose bags to Chefty. Whoever has
## no rake and no bag to carry scoops at the leaves by hand now and then. Bots
## never talk to the homeowner, so a job ends only when a person says so.

## A rake run starts this far from the pile and ends at it.
const RUN_METERS: float = 5.0
## A stroke lands REACH (1.5 m) ahead and shoves leaves about 1.5 m further, so
## stop raking this far out to leave them on the pile, and bag from close in.
const STOP_RAKING_METERS: float = 3.0
const BAG_FROM_METERS: float = 1.5
## Rake this many runs into one pile from all sides, then bag it: a bigger pile
## makes a bag worth more. Then start a new pile somewhere else.
const RUNS_PER_PILE: int = 5
## With this many bags lying around, the raker puts the rake down and carries.
const LOOSE_BAGS_BEFORE_CARRYING: int = 3
const GRAB_FROM_METERS: float = 1.8
## A crew bot (share_rake) sets the rake down after each pile it bags and leaves
## it for this long, so a teammate (a person especially) gets a turn with it.
const RAKE_REST_SECONDS: float = 25.0
## A loose rake is left this long (s) to a person with empty hands within this
## far (m) of it, or nearer it than the bot, timed from when they came near
## (_mine_to_take).
const RAKE_DEFER_SECONDS: float = 20.0
const RAKE_DEFER_METERS: float = 15.0

## p2-kit: where a bot stands to take a rake off Chefty's rack (truck space, x
## to its side of the truck, z beside the cab's back), and how close is close enough (m).
const RACK_SIDE_X: float = 1.9
const RACK_SIDE_Z: float = -1.5
const TAKE_FROM_METERS: float = 0.9

## Walking at something for this long without getting 0.5 m closer is stuck (s).
const STUCK_SECONDS: float = 3.0
const STUCK_RUNS_BEFORE_NEW_PILE: int = 3
## Pile spots tried for the leafiest one, and run starts tried for one on leaves.
const PILE_TRIES: int = 8
const RUN_TRIES: int = 6
## How fast a crew bot turns (rad/s).
const CREW_TURN_RATE: float = 5.0
## hotbar:E: on this share of its walks to a run's start, a bot with the rake
## flicks the scroll wheel (slot_next) the way a bored hand does, then picks the
## rake back out of its pocket. Keeps the select RPC busy in the soaks, with
## --sim-lag too, and shows teammates the draw.
const FIDGET_CHANCE: float = 0.1
## A soak bot (not a crew bot) fidgets this often instead: a 45 s soak has only a
## handful of runs, and the point there is the select RPC under --sim-lag.
const SOAK_FIDGET_CHANCE: float = 0.4

## Set by a crew bot (net/dev/bot.gd --bot-crew): take turns with the rake, steer
## round things, give up on a spot it can't reach, and pick spots with leaves.
var share_rake: bool = false
var _field: Node
var _stuck_goal := Vector3.INF
var _stuck_best: float = INF
var _stuck_since: float = 0.0
var _stuck_runs: int = 0
## Whether this tick's steering means walking (a crew bot holds forward only
## then; a soak bot always walks). False while bagging, grabbing or tossing.
var wants_walk: bool = true
## How far (rad) the last _face this tick still had to turn (crew bots), so the
## bot can stop and turn before it walks (net/dev/bot.gd _crew_walk).
var turn_left: float = 0.0

var _rng: RandomNumberGenerator
var _rake_rest_until: float = -1.0
## The loose rake last weighed up, and since when (bot seconds) a person has had
## a claim on it (-1: nobody now).
var _loose_rake: Node3D
var _loose_since: float = 0.0
var _set_rake_down: bool = false
var _pile := Vector3.INF
var _run_start := Vector3.ZERO
var _runs_on_pile: int = 0
var _raking_in: bool = false
var _bag_next: bool = false
## This walk to a run's start flicks to the next pocket on the way (FIDGET_CHANCE).
var _fidget: bool = false
## Fidgets and rake runs so far (each bot prints them on exit).
var fidgets: int = 0
var runs: int = 0
var _hand_raking: bool = false
var _next_hand_choice: float = 0.0
var _press_wait: float = 0.0
var _release_next: StringName = &""
var _elapsed: float = 0.0
## Since when (bot seconds) this bot has been on the lot (-1: it isn't), and
## whether it has said it's going for the current loose rake (for the logs:
## playtest_tools_test reads the line).
var _on_lot_since: float = -1.0
var _told_taking: bool = false
## The person whose claim on the loose rake is running (0: none).
var _claimant: int = 0


func _init(rng: RandomNumberGenerator) -> void:
	_rng = rng


## Steers for this tick. Returns false when there is no work here, so the bot
## wanders instead.
func step(player: Node3D, delta: float) -> bool:
	_elapsed += delta
	wants_walk = true
	# Picked up since: the next time it's set down, the wait starts over.
	if _loose_rake != null and (not is_instance_valid(_loose_rake) or not bool(_loose_rake.call("is_loose"))):
		_loose_rake = null
	_press_wait = maxf(0.0, _press_wait - delta)
	if _release_next != &"":
		_send(_release_next, false)
		_release_next = &""
	var tree := player.get_tree()
	var field := tree.get_first_node_in_group("leaf_field")
	if field == null or Net.player_zone(Net.local_peer_id()) != Net.Zone.LOT:
		_on_lot_since = -1.0
		stop()
		return false
	if _on_lot_since < 0.0:
		_on_lot_since = _elapsed
	# Raking walks slowly so the strokes overlap; everything else walks.
	Input.action_release(&"sprint")
	Input.action_release(&"crouch")
	var held: Node = player.call("_held_prop")
	var held_kind := "" if held == null else str(held.get("kind"))
	match held_kind:
		"rake":
			return _rake(player, field, tree)
		"leaf_bag":
			return _carry_to_truck(player, held, tree)
		"":
			return _find_work(player, tree)
		_:
			# Another pocket's tool came up (a fidget, or a dive that drew the wrong
			# slot back): back to the rake in its pocket. Otherwise it's not
			# something bots work with: put it down.
			var rake_slot := _pocket_of(player, "rake")
			if rake_slot >= 0:
				wants_walk = false
				_tap(StringName("slot_%d" % (rake_slot + 1)))
				return true
			stop()
			_tap(&"drop")
			return false


## Lets go of anything the job is holding down, for a chase or leaving the lot.
func stop() -> void:
	Input.action_release(&"primary")
	Input.action_release(&"crouch")
	_raking_in = false
	_bag_next = false
	_hand_raking = false


func _rake(player: Node3D, field: Node, tree: SceneTree) -> bool:
	_hand_raking = false
	if _loose_bags(tree).size() >= LOOSE_BAGS_BEFORE_CARRYING:
		stop()
		_tap(&"drop")
		return false
	if _set_rake_down:
		# The pile's bagged: put the rake down where it is for someone else.
		wants_walk = false
		Input.action_release(&"primary")
		if _press_wait <= 0.0 and _release_next == &"":
			_set_rake_down = false
			_rake_rest_until = _elapsed + RAKE_REST_SECONDS
			_tap(&"drop")
		return true
	if _bag_next:
		Input.action_release(&"primary")
		_face(player, _pile)
		var close := _flat_distance(player.global_position, _pile) <= BAG_FROM_METERS
		wants_walk = not close
		if _press_wait > 0.0 or _release_next != &"" or not close:
			return true
		_bag_next = false
		_tap(&"secondary")
		_pile = Vector3.INF
		# A turn for a person with no rake of their own; with everyone holding one
		# (p2-kit: the crew buys a rake each), it keeps its own, so it's in its
		# hands to put back on the rack when Chefty honks home (hotbar:E: two
		# rested rakes lay out on the lawn at the honk, play\rec_honk6_1p).
		# Only while the rakeless outnumber the rakes already lying free on the yard
		# (hotbar:E review, rec_lagbots2_3p: bots kept shedding rakes beside a free
		# one until three lay loose and nobody raked).
		_set_rake_down = share_rake and _rakeless_people(player, tree) > _spare_rakes(player, tree)
		return true
	if _pile == Vector3.INF:
		_pile = _random_spot(field)
		_runs_on_pile = 0
		_stuck_runs = 0
		_new_run(player)
	if not _raking_in:
		Input.action_release(&"primary")
		if _fidget and _press_wait <= 0.0 and _release_next == &"":
			# The scroll wheel, idly, on the way: whatever's next comes up (or bare
			# hands); _find_work or the other-tool branch above draws the rake back.
			_fidget = false
			fidgets += 1
			_tap(&"slot_next")
		_face(player, _steer(player, _run_start))
		if _flat_distance(player.global_position, _run_start) < 1.0:
			_raking_in = true
		elif _stuck(player, _run_start):
			# A wall, a fence or the house in the way: come at the pile from elsewhere,
			# and after a few tries, rake somewhere else.
			_stuck_runs += 1
			if _stuck_runs >= STUCK_RUNS_BEFORE_NEW_PILE:
				_pile = Vector3.INF
			else:
				_new_run(player)
		return true
	_face(player, _pile)
	Input.action_press(&"primary")
	Input.action_press(&"crouch")
	var stuck_raking := _stuck(player, _pile)
	if stuck_raking or _flat_distance(player.global_position, _pile) <= STOP_RAKING_METERS:
		Input.action_release(&"primary")
		_runs_on_pile += 1
		if _runs_on_pile >= RUNS_PER_PILE:
			_bag_next = true
		else:
			_new_run(player)
	return true


func _carry_to_truck(player: Node3D, held: Node, tree: SceneTree) -> bool:
	stop()
	var truck := tree.get_first_node_in_group("chefty")
	# The drivable Chefty (the connected town) may be driving off with no trip.
	if truck == null or bool(truck.call("is_riding")) or (truck.has_method("is_moving") and bool(truck.call("is_moving"))):
		return false
	_face(player, _steer(player, truck.call("body_position")))
	if bool(held.call("near_truck")):
		wants_walk = false
		_press_e(player, func() -> void: held.call("request_load_truck"))
	return true


func _find_work(player: Node3D, tree: SceneTree) -> bool:
	_raking_in = false
	_bag_next = false
	# Something of ours in a pocket (a dive into a hedge pockets what you hold):
	# take it back out, or the crew's only rake sits in a bot's pocket all day
	# (tools:crew, "Press [1] for the rake" on a bot that thought its hands were empty).
	# Every bot does this (hotbar:E): a soak bot's fidget leaves the rake there too.
	var pocket := _pocketed_work(player)
	if pocket >= 0:
		wants_walk = false
		_tap(StringName("slot_%d" % (pocket + 1)))
		return true
	var target: Node3D = _nearest(player, _loose_bags(tree))
	if target == null and _elapsed >= _rake_rest_until:
		var rake := _free_rake(tree)
		if rake != null and _mine_to_take(player, rake):
			target = rake
	# p2-kit: no rake lying free, but one on Chefty's rack: take it off the rack,
	# once every person on the yard without a rake has had theirs (people first).
	if target == null and _elapsed >= _rake_rest_until and share_rake and _bed_rake_is_mine(player, tree):
		var bed := _tool_bed(tree)
		var side := _rack_side(player, tree)
		Input.action_release(&"primary")
		_hand_raking = false
		if _flat_distance(player.global_position, side) <= TAKE_FROM_METERS:
			wants_walk = false
			_face(player, bed.global_position)
			if _press_wait <= 0.0 and _release_next == &"":
				_press_wait = 1.0
				var index := _bed_rake_index(bed)
				if index >= 0:
					bed.call("request_take", index)
		else:
			_face(player, _steer(player, side))
		return true
	if target != null:
		_hand_raking = false
		Input.action_release(&"primary")
		if _flat_distance(player.global_position, target.global_position) <= GRAB_FROM_METERS:
			wants_walk = false
			_press_e(player, func() -> void: target.call("request_grab"), target)
		else:
			_face(player, _steer(player, target.global_position))
		return true
	# Nothing to carry and someone else has the rake: scoop by hand, sometimes.
	if _elapsed >= _next_hand_choice:
		_next_hand_choice = _elapsed + _rng.randf_range(2.0, 5.0)
		_hand_raking = _rng.randf() < 0.35
	if _hand_raking:
		Input.action_press(&"primary")
	else:
		Input.action_release(&"primary")
	return false


func _new_run(player: Node3D) -> void:
	var angle := _rng.randf_range(0.0, TAU)
	_run_start = _pile + Vector3(cos(angle), 0.0, sin(angle)) * RUN_METERS
	if share_rake and _field != null:
		# A run over leaves, not across the path or out of the house's wall.
		var best := -1
		for _try: int in RUN_TRIES:
			var start := _pile + Vector3(cos(angle), 0.0, sin(angle)) * RUN_METERS
			var leafy := _leaves_at(start) + _leaves_at((start + _pile) * 0.5)
			if leafy > best:
				best = leafy
				_run_start = start
			angle = _rng.randf_range(0.0, TAU)
	_raking_in = _flat_distance(player.global_position, _run_start) < 1.0
	runs += 1
	_fidget = not _raking_in and _rng.randf() < (FIDGET_CHANCE if share_rake else SOAK_FIDGET_CHANCE)
	_stuck_goal = Vector3.INF


## Crew bots: whether this loose rake is ours to go for. A person (anyone not
## named Bot<N>) with empty hands has first claim: while one is nearer the rake
## than this bot, or within RAKE_DEFER_METERS of it, it's theirs for
## RAKE_DEFER_SECONDS, timed from when such a person came near it (not from when
## the bot first looked: the tool-row rake is loose from the moment the crew
## arrives, and its time ran out while the people were still walking over from
## Chefty). After that, or with nobody like that about, the nearest bot's.
## (tools:crew: Bot1 set the rake down for its 25 s rest and Bot2, with no rest of
## its own, had it before the host standing next to it could press E; then Bot1
## ran 20 m for one Bot2 dropped to carry bags, past the host walking up to it.
## The host never raked all job.)
func _mine_to_take(player: Node3D, rake: Node3D) -> bool:
	if not share_rake:
		return true
	if _loose_rake != rake:
		_loose_rake = rake
		_loose_since = -1.0
		_claimant = 0
		_told_taking = false
	var mine := _flat_distance(player.global_position, rake.global_position)
	var person_claims := false
	var claimant_about := false
	var bot_nearer := false
	var nearest_person := INF
	for node: Node in player.get_tree().get_nodes_in_group("players"):
		var other := node as Node3D
		var peer_id := int(str(node.name))
		if other == null or other == player or Net.player_zone(peer_id) != Net.Zone.LOT or Net.is_watcher(peer_id) or Net.player_name(peer_id) == "Observer":
			continue
		var theirs := _flat_distance(other.global_position, rake.global_position)
		if not Net.player_name(peer_id).begins_with("Bot"):
			var free_hands := other.has_method("_held_prop") and other.call("_held_prop") == null
			nearest_person = minf(nearest_person, theirs)
			if free_hands and (theirs <= RAKE_DEFER_METERS or theirs < mine):
				person_claims = true
				if _claimant == 0:
					_claimant = peer_id
			claimant_about = claimant_about or (peer_id == _claimant and free_hands)
		elif theirs < mine:
			bot_nearer = true
	# A claim, once made, runs its time while that person is still on the yard with
	# empty hands, wherever the rake has got to since (fx-net: a bot scooping
	# leaves by hand beside a rake it was leaving to the host kicked it 7 m along
	# the lawn, out of the host's 15 m, and then took it, 13 s in).
	if not person_claims and claimant_about:
		person_claims = true
	# _loose_since here: since when a person has had a claim on this rake (-1: none now).
	if not person_claims:
		_loose_since = -1.0
		_claimant = 0
	elif _loose_since < 0.0:
		_loose_since = _elapsed
	if person_claims and _elapsed - _loose_since < RAKE_DEFER_SECONDS:
		return false
	# Another bot nearer goes for it.
	if not bot_nearer and not _told_taking:
		_told_taking = true
		print("[BotJob] going for the loose rake %.1f s after arriving; a person's claim %s; the nearest person %.1f m from it, me %.1f m" % [_elapsed - _on_lot_since, "ran %.1f s" % (_elapsed - _loose_since) if person_claims else "none now", nearest_person, mine])
	return not bot_nearer


## The pocket (0-based) holding a rake or a leaf bag of ours, or -1. hotbar.gd is
## loaded here, not preloaded as a constant: with the preload every peer of the
## event soak (host and bots, all running this script) crashed with an access
## violation on quit, after writing its report; without it, none did.
func _pocketed_work(player: Node3D) -> int:
	var slots: Array = load("res://net/components/hotbar.gd").slots_of(player.get_tree(), Net.local_peer_id())
	for index: int in slots.size():
		var slot: Array = slots[index]
		if not slot.is_empty() and slot[0] != null and str((slot[0] as Node).get("kind")) in ["rake", "leaf_bag"]:
			return index
	return -1


## How many people (not bots, not the observer) on the yard have no rake in hand
## or pocket.
func _rakeless_people(player: Node3D, tree: SceneTree) -> int:
	var count := 0
	for node: Node in tree.get_nodes_in_group("players"):
		var peer_id := int(str(node.name))
		if node == player or Net.player_zone(peer_id) != Net.Zone.LOT or Net.is_watcher(peer_id):
			continue
		var who := Net.player_name(peer_id)
		if who.begins_with("Bot") or who == "Observer":
			continue
		var carries := false
		for prop: Node in tree.get_nodes_in_group("props"):
			if str(prop.get("kind")) == "rake" and (int(prop.get("held_by")) == peer_id or int(prop.get("pocketed_by")) == peer_id):
				carries = true
				break
		if not carries:
			count += 1
	return count


## A rake lying free this close (m) to a bot counts as one on its yard.
const YARD_RAKE_METERS: float = 40.0


## How many rakes lie free (is_loose, not in the air) on this bot's yard: one is
## there for a rakeless person already.
func _spare_rakes(player: Node3D, tree: SceneTree) -> int:
	var count := 0
	for node: Node in tree.get_nodes_in_group("props"):
		var prop := node as Node3D
		if prop == null or str(prop.get("kind")) != "rake" or not bool(prop.call("is_loose")) or bool(prop.call("is_flying")):
			continue
		if _flat_distance(player.global_position, prop.global_position) <= YARD_RAKE_METERS:
			count += 1
	return count


## The pocket (0-based) holding this kind of ours, or -1 (player/pockets.gd).
func _pocket_of(player: Node3D, kind: String) -> int:
	var pockets := player.get_node_or_null("Pockets")
	return int(pockets.call("slot_of_kind", kind)) if pockets != null and pockets.has_method("slot_of_kind") else -1


func _leaves_at(point: Vector3) -> int:
	return int(_field.call("sample_world", point)) if _field != null and _field.has_method("sample_world") else 0


## Crew bots: true once walking at goal has got no closer for STUCK_SECONDS.
func _stuck(player: Node3D, goal: Vector3) -> bool:
	if not share_rake:
		return false
	var left := _flat_distance(player.global_position, goal)
	if goal != _stuck_goal or left < _stuck_best - 0.5:
		_stuck_goal = goal
		_stuck_best = left
		_stuck_since = _elapsed
		return false
	if _elapsed - _stuck_since < STUCK_SECONDS:
		return false
	_stuck_goal = Vector3.INF
	return true


## Crew bots: straight at the point when the way is clear at knee height, else the
## nearest clear heading either side (the house's corner, the hedge, a tree).
func _steer(player: Node3D, point: Vector3) -> Vector3:
	if not share_rake:
		return point
	var from := player.global_position + Vector3(0.0, 0.45, 0.0)
	var flat := Vector3(point.x - from.x, 0.0, point.z - from.z)
	var reach := minf(flat.length(), 2.5)
	if reach < 0.3:
		return point
	var space := player.get_world_3d().direct_space_state
	var dir := flat.normalized()
	for turn: float in [0.0, 0.5, -0.5, 1.0, -1.0, 1.5, -1.5, 2.2, -2.2]:
		var heading := dir.rotated(Vector3.UP, turn)
		var query := PhysicsRayQueryParameters3D.create(from, from + heading * reach, 1)
		query.exclude = [(player as CollisionObject3D).get_rid()]
		if space.intersect_ray(query).is_empty():
			return player.global_position + heading * 2.0
	return point


## A pile spot well inside the leaf field, so every run starts on leaves (a crew
## bot takes the leafiest of a few).
func _random_spot(field: Node) -> Vector3:
	_field = field
	if not share_rake:
		return _any_spot(field)
	var best := _any_spot(field)
	var most := _leaves_at(best)
	for _try: int in PILE_TRIES - 1:
		var spot := _any_spot(field)
		var leafy := _leaves_at(spot)
		if leafy > most:
			most = leafy
			best = spot
	return best


func _any_spot(field: Node) -> Vector3:
	var origin: Vector3 = field.get("grid_origin")
	var cell := float(field.get("cell_size"))
	var width := float(int(field.get("grid_width"))) * cell
	var depth := float(int(field.get("grid_depth"))) * cell
	var margin := RUN_METERS + 1.0
	var local := origin + Vector3(
		_rng.randf_range(margin, maxf(margin, width - margin)),
		0.0,
		_rng.randf_range(margin, maxf(margin, depth - margin)))
	return (field as Node3D).global_transform * local


func _loose_bags(tree: SceneTree) -> Array:
	var bags: Array = []
	for node: Node in tree.get_nodes_in_group("props"):
		if str(node.get("kind")) == "leaf_bag" and bool(node.call("is_loose")):
			bags.append(node)
	return bags


## p2-kit: whether a rake on Chefty's rack is this bot's to take: more rakes
## aboard than the people on the yard who have none (a person walking up to
## the rack gets theirs first), and no other bot nearer the truck.
func _bed_rake_is_mine(player: Node3D, tree: SceneTree) -> bool:
	var bed := _tool_bed(tree)
	if bed == null or int(bed.call("count_of", "rake")) <= 0:
		return false
	var truck := tree.get_first_node_in_group("chefty")
	if truck != null and (bool(truck.call("is_riding")) or (truck.has_method("is_moving") and bool(truck.call("is_moving")))):
		return false
	var rakeless_people := 0
	var mine := _flat_distance(player.global_position, bed.global_position)
	for node: Node in tree.get_nodes_in_group("players"):
		var other := node as Node3D
		var peer_id := int(str(node.name))
		if other == null or other == player or Net.player_zone(peer_id) != Net.Zone.LOT or Net.is_watcher(peer_id) or Net.player_name(peer_id) == "Observer":
			continue
		var carries := false
		for prop: Node in tree.get_nodes_in_group("props"):
			if str(prop.get("kind")) == "rake" and (int(prop.get("held_by")) == peer_id or int(prop.get("pocketed_by")) == peer_id):
				carries = true
				break
		if carries:
			continue
		if not Net.player_name(peer_id).begins_with("Bot"):
			rakeless_people += 1
		elif _flat_distance(other.global_position, bed.global_position) < mine:
			return false
	return int(bed.call("count_of", "rake")) > rakeless_people


func _tool_bed(tree: SceneTree) -> Node3D:
	var truck := tree.get_first_node_in_group("chefty")
	return truck.call("tool_bed") as Node3D if truck != null and truck.has_method("tool_bed") else null


## The first rake on the rack (its index in the bed's list), or -1.
func _bed_rake_index(bed: Node) -> int:
	var tools: Array = bed.get("tools")
	for index: int in tools.size():
		if str((tools[index] as Dictionary)["kind"]) == "rake":
			return index
	return -1


## Where a bot stands to reach the rack: beside the cab, on its own side of the truck.
func _rack_side(player: Node3D, tree: SceneTree) -> Vector3:
	var truck := tree.get_first_node_in_group("chefty")
	var bed: Transform3D = truck.call("bed_transform")
	var local := bed.affine_inverse() * player.global_position
	return bed * Vector3(RACK_SIDE_X * (1.0 if local.x >= 0.0 else -1.0), 0.0, RACK_SIDE_Z)


func _free_rake(tree: SceneTree) -> Node3D:
	for node: Node in tree.get_nodes_in_group("props"):
		if str(node.get("kind")) == "rake" and bool(node.call("is_loose")):
			return node as Node3D
	return null


func _nearest(player: Node3D, nodes: Array) -> Node3D:
	var closest: Node3D = null
	var closest_distance := INF
	for node: Variant in nodes:
		var spot := node as Node3D
		if spot == null:
			continue
		var distance := _flat_distance(player.global_position, spot.global_position)
		if distance < closest_distance:
			closest = spot
			closest_distance = distance
	return closest


## Turn so move_forward heads toward the point. Forward is -Z, rotated by body_yaw.
func _face(player: Node3D, point: Vector3) -> void:
	var away := point - player.global_position
	if Vector2(away.x, away.z).length() < 0.01:
		return
	var want := atan2(-away.x, -away.z)
	if share_rake:
		# A crew bot turns like a hand on a mouse, not in one tick: a snap turn
		# made everyone else's screen draw it lurching 0.6 m out and back.
		var have := float(player.get("body_yaw"))
		var step := CREW_TURN_RATE * player.get_physics_process_delta_time()
		turn_left = wrapf(want - have, -PI, PI)
		want = have + clampf(turn_left, -step, step)
	player.set("body_yaw", want)


## E, meaning what the bot means by it (picking up its target, loading Chefty).
## E does the first thing it can (player.gd): with a teammate in front it picks
## them up, next to a hedge or on a deep pile it dives in. A crew bot that would
## set one of those off turns away from the teammate first, as a person would;
## a hiding spot or a pile it can't turn away from, so it does the thing itself
## (tools:crew: a bot pressing E for the rake at the host's feet carried the
## host off instead, and one by the hedge spent a raid-free morning diving in).
func _press_e(player: Node3D, meant: Callable, target: Node = null) -> void:
	if not share_rake:
		_tap(&"interact")
		return
	var mate: Node3D = player.call("_grabbable_player") if player.has_method("_grabbable_player") else null
	if mate != null:
		var away := player.global_position * 2.0 - mate.global_position
		_face(player, away)
		return
	var dives := player.has_method("_nearest_free_spot") and player.call("_nearest_free_spot") != null
	dives = dives or (player.has_method("_on_pile") and bool(player.call("_on_pile")))
	# E picks up whatever's best in reach (player.gd _best_pickup): by the tool row
	# that was the gas can beside the rake, picked up and dropped again and again.
	var other: bool = target != null and player.has_method("_best_pickup") and player.call("_best_pickup") != target
	if not dives and not other:
		_tap(&"interact")
		return
	if _press_wait > 0.0 or _release_next != &"":
		return
	_press_wait = 1.0
	meant.call()


## A quick press, released next tick, sent as input events so both
## _unhandled_input and is_action_just_pressed see it. At most one a second.
func _tap(action: StringName) -> void:
	if _press_wait > 0.0 or _release_next != &"":
		return
	_press_wait = 1.0
	_send(action, true)
	_release_next = action


func _send(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
