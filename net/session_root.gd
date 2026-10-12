extends Node3D

## Authority: host spawns the world. Clients receive it from WorldSpawner.
## WorldRoot stays empty until a session starts so the menu is not standing in the yard.

const WORLD_SCENE: PackedScene = preload("res://levels/world.tscn")


func _ready() -> void:
	%WorldRoot.child_entered_tree.connect(_on_world_entered)
	Net.state_changed.connect(_on_state_changed)
	if Net.is_host() and Net.current_state() == Net.State.IN_SESSION:
		_spawn_world()


func _on_state_changed(next_state: Net.State) -> void:
	if next_state == Net.State.OFFLINE:
		for child: Node in %WorldRoot.get_children():
			child.queue_free()
	elif next_state == Net.State.IN_SESSION and Net.is_host():
		_spawn_world()


func _on_world_entered(_node: Node) -> void:
	Net.notify_world_arrived()


func _spawn_world() -> void:
	if %WorldRoot.get_child_count() > 0:
		return
	var world := WORLD_SCENE.instantiate()
	world.name = "World"
	%WorldRoot.add_child(world, true)
