extends Node3D

## Authority: host spawns the world. Clients receive it from WorldSpawner.
## WorldRoot stays empty until a session starts so the menu is not standing in the yard.
## The host also picks the world's mode (the connected town or the legacy separate
## zones) and sends it in the spawn data, so every peer builds the same world
## before world._ready and clients never need a flag (docs/DECISIONS.md 2026-11-01).

const WORLD_SCENE: PackedScene = preload("res://levels/world.tscn")


func _ready() -> void:
	# Every peer: the spawner calls this to build the world from the host's spawn data.
	$WorldSpawner.spawn_function = _make_world
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
	var data := {"town_map": wants_town_map()}
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		$WorldSpawner.spawn(data)
	else:
		%WorldRoot.add_child(_make_world(data), true)


## Host: --legacy-map wins, then --town-map, then Constants.TOWN_MAP_DEFAULT.
static func wants_town_map() -> bool:
	var args := Net.dev_options()
	if bool(args.get("legacy_map")):
		return false
	if bool(args.get("town_map")):
		return true
	return Constants.TOWN_MAP_DEFAULT


## Every peer: builds the world (not yet in the tree) from the spawn data.
func _make_world(data: Variant) -> Node:
	var world := WORLD_SCENE.instantiate()
	world.name = "World"
	var mode: Dictionary = data if data is Dictionary else {}
	world.set("town_map", bool(mode.get("town_map", false)))
	return world
