extends Node

## Authority: local. --remote-play=<dir> lets an agent play the game by hand,
## one move at a time, the way a person at the keyboard would. The game watches
## <dir>/cmd.json; each new command (a higher "id") is a list of steps: hold a
## key, tap it, turn the mouse, click the screen, wait. Every step goes in as a
## real input event (Input.parse_input_event), so the game can't tell it from a
## keyboard and mouse. After the steps it saves a screenshot and writes
## <dir>/result.json: what's on screen (the prompt, the goal line, the HUD),
## where the player is, what they hold, and the clock. tools/play.ps1 sends one
## command and waits for the result.
##
## Steps, as arrays:
##   ["hold", action, seconds]   press an input action, wait, release it
##   ["tap", action]             press and release on the next frame
##   ["down", action] / ["up", action]
##   ["look", dx, dy]            turn: mouse motion in pixels (right, down)
##   ["click", x, y]             left mouse click at a screen position
##   ["wait", seconds]
##   ["text", "..."]             type into whatever has focus
## Actions are the names in project.godot's input map (move_forward, interact,
## primary, secondary, drop, jump, sprint, crouch, phone, pause, the pockets
## slot_1 ... slot_5, slot_next and slot_prev, ...). The result's "hotbar" says
## what's in the pockets: the selected slot (-1 bare hands), each slot's kind
## ("" empty) and the big thing in both arms ("" none).

var _dir: String = ""
var _last_id: int = 0
var _busy: bool = false
var _poll: float = 0.0


func _ready() -> void:
	_dir = str(Net.dev_options().get("remote_play"))
	DirAccess.make_dir_recursive_absolute(_dir)
	# A fresh start: nothing old in the mailbox gets replayed.
	var stale := _dir.path_join("cmd.json")
	if FileAccess.file_exists(stale):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(stale))
		if typeof(parsed) == TYPE_DICTIONARY:
			_last_id = int((parsed as Dictionary).get("id", 0))
	print("[RemotePlay] reading %s (last id %d)" % [_dir.path_join("cmd.json"), _last_id])


func _process(delta: float) -> void:
	_poll -= delta
	if _busy or _poll > 0.0:
		return
	_poll = 0.1
	var path := _dir.path_join("cmd.json")
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var command := parsed as Dictionary
	var id := int(command.get("id", 0))
	if id <= _last_id:
		return
	_last_id = id
	_busy = true
	_run(id, command.get("steps", []) as Array)


func _run(id: int, steps: Array) -> void:
	var errors: Array = []
	for raw: Variant in steps:
		if typeof(raw) != TYPE_ARRAY or (raw as Array).is_empty():
			continue
		var step := raw as Array
		match str(step[0]):
			"hold":
				_action(str(step[1]), true)
				await _seconds(float(step[2]) if step.size() > 2 else 0.3)
				_action(str(step[1]), false)
			"tap":
				_action(str(step[1]), true)
				await get_tree().physics_frame
				await get_tree().physics_frame
				_action(str(step[1]), false)
			"down":
				_action(str(step[1]), true)
			"up":
				_action(str(step[1]), false)
			"look":
				_look(float(step[1]), float(step[2]) if step.size() > 2 else 0.0)
			"click":
				await _click(Vector2(float(step[1]), float(step[2])))
			"wait":
				await _seconds(float(step[1]))
			"text":
				for character: String in str(step[1]):
					var key := InputEventKey.new()
					key.unicode = character.unicode_at(0)
					key.pressed = true
					Input.parse_input_event(key)
			_:
				errors.append("unknown step %s" % str(step[0]))
		await get_tree().process_frame
	# Let the screen catch up with the last input before the picture.
	await get_tree().process_frame
	await get_tree().process_frame
	var shot := _dir.path_join("shot_%04d.png" % id)
	if not DisplayServer.window_can_draw():
		RenderingServer.force_draw(false)
	else:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shot)
	var report := _state()
	report["id"] = id
	report["shot"] = shot
	report["errors"] = errors
	var file := FileAccess.open(_dir.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	_busy = false


func _action(action_name: String, pressed: bool) -> void:
	if not InputMap.has_action(action_name):
		push_warning("[RemotePlay] no input action %s" % action_name)
		return
	var event := InputEventAction.new()
	event.action = action_name
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(event)


func _look(dx: float, dy: float) -> void:
	# A few small moves, like a hand on a mouse, instead of one jump.
	var steps := maxi(1, int(ceil(maxf(absf(dx), absf(dy)) / 40.0)))
	for index: int in steps:
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(dx, dy) / float(steps)
		motion.position = get_viewport().get_visible_rect().size * 0.5
		Input.parse_input_event(motion)


func _click(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	await get_tree().process_frame
	for pressed: bool in [true, false]:
		var button := InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTON_LEFT
		button.pressed = pressed
		button.position = at
		button.global_position = at
		Input.parse_input_event(button)
		await get_tree().process_frame


func _seconds(seconds: float) -> void:
	await get_tree().create_timer(maxf(seconds, 0.0)).timeout


## What a person would read off the screen, plus where they are.
func _state() -> Dictionary:
	var out := {}
	var me := Net.local_peer_id()
	out["zone"] = Net.Zone.keys()[Net.player_zone(me)]
	out["cash"] = Campaign.credits(me)
	out["mouse"] = ["visible", "hidden", "captured", "confined", "confined_hidden"][Input.mouse_mode]
	var player: Node3D = null
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(me):
			player = node as Node3D
	if player != null:
		var p := player.global_position
		out["position"] = [snappedf(p.x, 0.1), snappedf(p.y, 0.1), snappedf(p.z, 0.1)]
		out["facing_deg"] = int(round(rad_to_deg(player.global_rotation.y)))
		var held: Node = player.call("_held_prop") if player.has_method("_held_prop") else null
		out["holding"] = str(held.get("kind")) if held != null else ""
		var hotbar := preload("res://net/components/hotbar.gd")
		var kinds: Array = []
		for slot: Array in hotbar.slots_of(get_tree(), me):
			kinds.append(str(slot[0].get("kind")) if not slot.is_empty() else "")
		var pockets := player.get_node_or_null("Pockets")
		var arms := hotbar.arms_item(get_tree(), me)
		out["hotbar"] = {
			"selected": int(pockets.get("selected")) if pockets != null else -1,
			"slots": kinds,
			"hands": str(arms.get("kind")) if arms != null else "",
		}
		if player.has_method("interaction_hint"):
			var hint: Dictionary = player.call("interaction_hint")
			if not hint.is_empty():
				out["prompt"] = str(hint["text"])
	if not out.has("prompt"):
		for source: Node in get_tree().get_nodes_in_group("prompt_sources"):
			var hint: Dictionary = source.call("prompt")
			if not hint.is_empty():
				out["prompt"] = str(hint["text"])
				break
	var ui := get_tree().get_first_node_in_group("game_ui")
	if ui != null:
		var goal := ui.get_node_or_null("JobGoal") as Label
		if goal != null and goal.visible:
			out["goal"] = goal.text
		var windows: Array = []
		for name_of: String in ["ShopWindow", "JobBoardWindow", "PayoutWindow", "DaySummary", "Phone"]:
			var window := ui.get_node_or_null(name_of) as Control
			if window != null and window.visible:
				windows.append(name_of)
		out["windows"] = windows
	var clock := get_tree().get_first_node_in_group("day_clock")
	if clock != null:
		out["clock"] = "Day %d %s" % [int(clock.get("day")), str(clock.call("clock_text"))]
	var field := get_tree().get_first_node_in_group("leaf_field")
	if field != null:
		out["cleaned"] = snappedf(float(field.call("cleaned_fraction")), 0.001)
	var truck := get_tree().get_first_node_in_group("chefty")
	if truck != null:
		out["truck"] = "%d bags $%d" % [int(truck.call("bag_count")), int(truck.call("bag_value"))]
	var heat := get_tree().get_first_node_in_group("heat")
	if heat != null:
		out["heat"] = snappedf(float(heat.get("heat")), 0.1)
	out["xp"] = "%d banked, %d pending" % [Campaign.crew_xp(), Campaign.pending_xp()]
	return out
