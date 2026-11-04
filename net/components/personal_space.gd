extends Node

## Authority: host. Room to stand (p1-arrive, docs/GAME.md "Stepping off
## Chefty"). Players don't collide with each other (layer 2 never masks 2), so
## anything that puts two bodies on one spot (a spawn, waking up, a teleport, a
## friend walking into you and stopping) left one person's camera inside the
## other's head. The host looks at every pair of players on foot; a pair closer
## than PERSONAL_SPACE_RADIUS for longer than PERSONAL_SPACE_AFTER is eased
## apart, each owner sliding a little (player.gd send_nudge, nudge), so walking
## through someone never shoves them, but standing in them does.
##
## Only bodies on their own feet are moved: never anyone seated, staged, hidden,
## asleep, carried or carrying someone (whose bodies overlap on purpose), thrown,
## up a ladder or on the board, and never the playtest observer.

## For the tests: how many nudges went out, and the pairs pushed apart.
static var stats: Dictionary = {"nudges": 0, "pairs": 0}

## Pair key -> seconds they've been too close.
var _close: Dictionary = {}
var _wait: float = 0.0


static func reset_stats() -> void:
	stats = {"nudges": 0, "pairs": 0}


func _ready() -> void:
	add_to_group("personal_space")


func _physics_process(delta: float) -> void:
	if not Net.is_host() or multiplayer.multiplayer_peer == null:
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = Constants.PERSONAL_SPACE_TICK
	var bodies: Array[Node3D] = []
	for node: Node in get_tree().get_nodes_in_group("players"):
		var body := node as Node3D
		if body != null and body.is_inside_tree() and not Net.is_watcher(body.name.to_int()):
			bodies.append(body)
	var seen := {}
	for a: int in bodies.size():
		for b: int in range(a + 1, bodies.size()):
			_check_pair(bodies[a], bodies[b], seen)
	for key: Variant in _close.keys():
		if not seen.has(key):
			_close.erase(key)


func _check_pair(a: Node3D, b: Node3D, seen: Dictionary) -> void:
	var flat := Vector2(b.global_position.x - a.global_position.x, b.global_position.z - a.global_position.z)
	var apart := flat.length()
	if apart >= Constants.PERSONAL_SPACE_RADIUS or absf(b.global_position.y - a.global_position.y) > 1.2:
		return
	var free_a := on_foot(a)
	var free_b := on_foot(b)
	if not free_a and not free_b:
		return
	var key := "%s:%s" % [a.name, b.name]
	seen[key] = true
	var was := float(_close.get(key, 0.0))
	_close[key] = was + Constants.PERSONAL_SPACE_TICK
	if was + Constants.PERSONAL_SPACE_TICK < Constants.PERSONAL_SPACE_AFTER:
		return
	if was < Constants.PERSONAL_SPACE_AFTER:
		stats["pairs"] = int(stats["pairs"]) + 1
	# Exactly on top of each other: apart along a direction both peers' ids pick.
	var away := flat.normalized() if apart > 0.01 else Vector2.from_angle(float(hash(key) % 628) * 0.01)
	# Harder the deeper in, never less than half.
	var speed := Constants.PERSONAL_SPACE_SPEED * clampf(1.5 - apart / Constants.PERSONAL_SPACE_RADIUS, 0.5, 1.0)
	# One of them can't move (seated, asleep): the other just takes longer.
	if free_a:
		_nudge(a, -away * speed)
	if free_b:
		_nudge(b, away * speed)


func _nudge(body: Node3D, push: Vector2) -> void:
	if body.has_method("send_nudge"):
		body.call("send_nudge", Vector3(push.x, 0.0, push.y))
		stats["nudges"] = int(stats["nudges"]) + 1


## Whether this player stands on their own feet (the host's view of them).
static func on_foot(body: Node) -> bool:
	if body.has_method("seat_ride") and body.call("seat_ride") != null:
		return false
	if body.get("_ride") != null:
		return false
	for check: String in ["is_staged", "is_hidden", "is_sleeping", "is_climbing"]:
		if body.has_method(check) and bool(body.call(check)):
			return false
	if int(body.get("carried_by")) != 0 or int(body.get("carrying")) != 0 or bool(body.get("thrown")):
		return false
	if bool(body.get("in_pile")) or bool(body.get("on_board")):
		return false
	return true
