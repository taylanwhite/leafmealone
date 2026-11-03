extends Node

## --rake-net-test (raking:1). Skeleton: the golden density rules on the host.

const _Golden = preload("res://net/dev/leaf_golden.gd")

static var result: Dictionary = {}

var _started: bool = false


func _process(_delta: float) -> void:
	if _started or not Net.is_host():
		return
	var lot := get_tree().get_first_node_in_group("job_lot")
	if lot == null or not bool(lot.get("is_generated")) or get_tree().get_first_node_in_group("leaf_field") == null:
		return
	_started = true
	var golden := _Golden.run(self)
	print("[RakeNetTest] golden: %s (%s)" % [golden["ok"], golden.get("why", "")])
	result["golden"] = golden
	result["ok"] = bool(golden["ok"])
	result["done"] = true
