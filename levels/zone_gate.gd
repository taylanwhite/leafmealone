extends Area3D

## Authority: the overlapping player's peer asks the host. The host performs the zone move.
## Debug doors for M1. destination_zone is "store", "lot", or "border".

@export var destination_zone: String = "lot"

var _local_player_inside: bool = false


const _Strings = preload("res://ui/strings.gd")


func _ready() -> void:
	add_to_group("prompt_sources")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	collision_layer = 0
	collision_mask = 2
	monitoring = true


## The prompt while the local player stands on the pad, or empty.
func prompt() -> Dictionary:
	if not _local_player_inside:
		return {}
	return {"text": _Strings.UI["prompt_gate_%s" % destination_zone], "at": global_position + Vector3(0.0, 1.4, 0.0)}


func _unhandled_input(event: InputEvent) -> void:
	if not _local_player_inside or not event.is_action_pressed("interact"):
		return
	Net.request_zone_move(_zone_from_name(destination_zone))
	get_viewport().set_input_as_handled()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("players") and body.is_multiplayer_authority():
		_local_player_inside = true


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("players") and body.is_multiplayer_authority():
		_local_player_inside = false


func _zone_from_name(zone_name: String) -> Net.Zone:
	match zone_name:
		"lot":
			return Net.Zone.LOT
		"border":
			return Net.Zone.BORDER
		_:
			return Net.Zone.STORE
