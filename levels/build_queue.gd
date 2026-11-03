extends Node

## Authority: local, on every peer. Spreads cosmetic building over frames so no
## build stalls a frame (driving chunk E, docs/DECISIONS.md "Builds are spread
## over frames"): the world's dressing, Satellite Annex B, the store, the town's
## pieces and their people are steps here instead of one long _ready. Every
## frame it runs steps until Constants.BUILD_MS_PER_FRAME is spent (at least one
## a frame), so a 2-5 s world build becomes a few hundred short frames and a
## joining peer keeps answering ENet the whole time.
##
## Builders stay plain functions: they hand work over with
##   BuildQueue.later(node, func() -> void: ...)
## which queues the step when node's tree has an open queue, and runs it right
## now otherwise (the studio, tools and tests that build things by hand get
## everything at once, as before). A step queued from inside a running step runs
## right after it (depth first), so things build in the order they always did.
##
## flush() runs every waiting step now, for whatever needs the whole world
## before it can go on (BuildQueue.finish(tree)). Nothing networked waits on a
## step: steps build visuals, local walkers and set dressing only.

signal drained

const GROUP := &"build_queue"

## Per-peer stats for the probe and tests: steps run, frames spent, the longest
## step (ms) and its label, and the most time spent building in one frame (ms).
static var stats: Dictionary = {}

## Waiting steps, [Callable, label]; _head is the next to run.
var _steps: Array = []
var _head: int = 0
## Where a step queued while another runs goes: right after that one's children.
var _insert_at: int = -1
## How many "soon" steps wait at the front (they keep their own order).
var _firsts: int = 0
var _open: bool = true
## The frame this queue was made in (the world's arrival on a joiner): no step
## runs in it, so that frame never pays for a step on top of the world itself
## (driving:E2's join frame).
var _born_frame: int = -1


func _ready() -> void:
	name = "BuildQueue"
	add_to_group(GROUP)
	# Before anything else in the frame: the steps' time is taken first, and the
	# rest of the frame (players, physics, the network) still fits after.
	process_priority = -100
	_born_frame = Engine.get_process_frames()
	stats = {"steps": 0, "frames": 0, "max_step_ms": 0.0, "max_step": "", "max_frame_ms": 0.0, "pending": 0, "flushed": 0}


## Queues fn on node's tree's open queue, or runs it now when there is none.
## node is what fn builds into: if it has left the tree (or been freed) by the
## time the step comes up, the step is skipped. label names the step in stats
## (the slowest one is reported).
static func later(node: Node, fn: Callable, label: String = "") -> void:
	var queue := _of(node)
	if queue == null:
		fn.call()
		return
	queue.add(fn, label, node)


## Like later, but ahead of everything already waiting: for what play needs
## first (the town's solids, which a joiner's own movement and its Chefty
## prediction collide with).
static func soon(node: Node, fn: Callable, label: String = "") -> void:
	var queue := _of(node)
	if queue == null:
		fn.call()
		return
	queue.add(fn, label, node, true)


## Runs every step still waiting in tree's queue, now. For code that needs the
## whole world built before it goes on.
static func finish(tree: SceneTree) -> void:
	if tree == null:
		return
	for queue: Node in tree.get_nodes_in_group(GROUP):
		queue.call("flush")


## Whether tree's queue has nothing left (true with no queue).
static func is_drained(tree: SceneTree) -> bool:
	if tree == null:
		return true
	for queue: Node in tree.get_nodes_in_group(GROUP):
		if not bool(queue.call("is_idle")):
			return false
	return true


## Before a join (net/net.gd join_enet): builds what the world's first frame
## would otherwise build from nothing, so it isn't in that frame. Chefty's truck
## mesh (both maps' looks: the legacy ride's and the drivable one's cab) is the
## biggest piece, 150-200 ms; props/vehicles.gd keeps it.
static func prewarm() -> void:
	var holder := Node3D.new()
	for interior: bool in [false, true]:
		preload("res://props/vehicles.gd").build_truck(holder, {"color": Color(0.75, 0.22, 0.15), "interior": interior})
	holder.free()


static func _of(node: Node) -> Node:
	if node == null or not node.is_inside_tree():
		return null
	var queue := node.get_tree().get_first_node_in_group(GROUP)
	if queue == null or not bool(queue.get("_open")):
		return null
	return queue


func add(fn: Callable, label: String = "", node: Node = null, first: bool = false) -> void:
	var step := [fn, label, node, node != null, first and _insert_at < 0]
	if _insert_at >= 0:
		_steps.insert(_insert_at, step)
		_insert_at += 1
	elif first:
		# Ahead of the waiting steps, after any queued "first" before it.
		_steps.insert(_head + _firsts, step)
		_firsts += 1
	else:
		_steps.append(step)
	stats["pending"] = _steps.size() - _head


func is_idle() -> bool:
	return _head >= _steps.size()


## Every waiting step, now.
func flush() -> void:
	if is_idle():
		return
	stats["flushed"] = int(stats["flushed"]) + (_steps.size() - _head)
	while not is_idle():
		_run_next()
	_done()


func _process(_delta: float) -> void:
	if is_idle() or Engine.get_process_frames() == _born_frame:
		return
	var started := Time.get_ticks_usec()
	var budget := int(Constants.BUILD_MS_PER_FRAME * 1000.0)
	while not is_idle():
		_run_next()
		if Time.get_ticks_usec() - started >= budget:
			break
	stats["frames"] = int(stats["frames"]) + 1
	stats["max_frame_ms"] = maxf(float(stats["max_frame_ms"]), float(Time.get_ticks_usec() - started) / 1000.0)
	if is_idle():
		_done()


func _run_next() -> void:
	var step: Array = _steps[_head]
	_head += 1
	if bool(step[4]):
		_firsts = maxi(_firsts - 1, 0)
	_insert_at = _head
	var started := Time.get_ticks_usec()
	var fn: Callable = step[0]
	# A step whose node went away (a yard swapped out mid-build) is skipped.
	var node: Variant = step[2]
	if fn.is_valid() and (not bool(step[3]) or (is_instance_valid(node) and (node as Node).is_inside_tree())):
		fn.call()
	_insert_at = -1
	var spent := float(Time.get_ticks_usec() - started) / 1000.0
	stats["steps"] = int(stats["steps"]) + 1
	if spent > float(stats["max_step_ms"]):
		stats["max_step_ms"] = spent
		stats["max_step"] = str(step[1])
	stats["pending"] = _steps.size() - _head


func _done() -> void:
	_steps.clear()
	_head = 0
	_firsts = 0
	stats["pending"] = 0
	drained.emit()
