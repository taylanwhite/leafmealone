extends Node3D

## Authority: host decides; every peer builds. The root of a job lot. The host
## picks the job's seed and the tasks the homeowner wants before spawning it,
## and both reach every peer with the spawn (JobSync), so each one generates the
## same yard (levels/lots/lot_generator.gd) and turns on the same work
## (net/work/job_tasks.gd). Late joiners get them the same way.

signal generated

## Seeds the whole yard: the house, trees, hedges, fences, beds, litter, leaves.
@export var job_seed: int = 0
## Task ids the homeowner asked for (Constants.TASK_TOOLS), raking included.
@export var tasks := PackedStringArray()
## 0 small, 1 regular, 2 big (levels/job_board.gd).
@export var yard_size: int = 1
## How grown back the yard is since the crew last did it (net/town/town.gd):
## 1 is a full yard of leaves, less after a recent job.
@export var mess: float = 1.0
## The neighborhood the house is in (net/town/neighborhoods.gd): the yard, its
## house and its street block are built in that hood's style.
@export var hood: String = ""
## The connected town (driving chunk D): where the yard stands (its town house's
## slot, TownMap.yard_transform) and that house's id, -1 in the legacy world.
## The host places the job site before it adds the lot; every client places it
## from these, before generating.
@export var site := Transform3D()
@export var house_id: int = -1
## Where the job is (the connected town): STAGE_WAITING for the crew, STAGE_ARRIVED
## (the homeowner's clock runs, the pick is locked), STAGE_PAID (the next job can
## be taken from right here). Host-set, replicated on change and with the spawn,
## so every peer and a late joiner read the same lock (world.job_locked), beacon
## and goal line.
@export var stage: int = STAGE_WAITING

const STAGE_WAITING: int = 0
const STAGE_ARRIVED: int = 1
const STAGE_PAID: int = 2

var is_generated: bool = false
var _placed_house: int = -1


func _ready() -> void:
	add_to_group("job_lot")
	# The host placed the site before adding the lot: it's this yard's from now.
	if Net.is_host():
		_placed_house = house_id
	# Spawn state normally lands before _ready; wait a few frames in case it doesn't.
	var waited := 0
	while job_seed == 0 and waited < 30:
		await get_tree().process_frame
		waited += 1
	if job_seed == 0:
		job_seed = 1
	var world := get_tree().get_first_node_in_group("world")
	var town := world != null and world.has_method("is_town_map") and bool(world.call("is_town_map"))
	if town:
		if not Net.is_host() and is_inside_tree():
			world.call("place_job_site", site, house_id)
			_placed_house = house_id
		# The chalk PARK HERE box at the curb, and the beacon over it.
		var marker := preload("res://levels/lots/site_marker.gd").new()
		marker.name = "SiteMarker"
		add_child(marker)
	$Dressing.set("mess", mess)
	# The yard and its block look like their neighborhood (levels/town/hood_styles.gd).
	$Dressing.set("hood", hood)
	$Dressing.call("generate", job_seed, tasks, yard_size)
	is_generated = true
	generated.emit()


## Every peer: the yard is going, so its town slot shows its own house again.
func _exit_tree() -> void:
	if _placed_house < 0:
		return
	var world := get_tree().get_first_node_in_group("world") if is_inside_tree() else null
	if world != null and world.has_method("release_job_site"):
		world.call("release_job_site", _placed_house)
	_placed_house = -1


## Every peer: the homeowner has paid for this yard (stage, replicated).
func is_paid() -> bool:
	return stage == STAGE_PAID


## The job's extra work (net/work/job_tasks.gd), or null until generated.
func job_tasks() -> Node:
	return get_node_or_null("JobTasks")
