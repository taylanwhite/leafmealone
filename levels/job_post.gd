extends Area3D

## Authority: the local player asks. The host runs the depart or finish.
## action_name is "depart" at the truck or "finish" on the lot.

@export var action_name: String = "depart"

var _inside: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	collision_layer = 0
	collision_mask = 2
	monitoring = true


func _unhandled_input(event: InputEvent) -> void:
	if not _inside or not event.is_action_pressed("interact"):
		return
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		return
	if action_name == "finish":
		world.call("request_finish")
	elif action_name == "store":
		var ui := get_tree().get_first_node_in_group("game_ui")
		if ui != null:
			ui.call("open_store")
	else:
		world.call("request_depart")
	get_viewport().set_input_as_handled()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("players") and body.is_multiplayer_authority():
		_inside = true


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("players") and body.is_multiplayer_authority():
		_inside = false
