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

var is_generated: bool = false


func _ready() -> void:
	add_to_group("job_lot")
	# Spawn state normally lands before _ready; wait a few frames in case it doesn't.
	var waited := 0
	while job_seed == 0 and waited < 30:
		await get_tree().process_frame
		waited += 1
	if job_seed == 0:
		job_seed = 1
	$Dressing.call("generate", job_seed, tasks)
	is_generated = true
	generated.emit()


## The job's extra work (net/work/job_tasks.gd), or null until generated.
func job_tasks() -> Node:
	return get_node_or_null("JobTasks")
