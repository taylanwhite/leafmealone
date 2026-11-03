extends Node

## Authority: local. --remote-play=<dir> lets an agent play the game by hand,
## one move at a time, the way a person at the keyboard would. The game watches
## <dir>/cmd.json; each new command (a higher "id") is a list of steps: hold a
## key, tap it, turn the mouse, click the screen, wait. Every step goes in as a
## real input event (Input.parse_input_event), so the game can't tell it from a
## keyboard and mouse. After the steps it saves a screenshot and writes
## <dir>/result.json: what's on screen (the prompt, the goal line, the HUD),
## where the player is, what they hold, and the clock. tools/play.ps1 sends one
## command and waits for the result. docs/PLAYTEST.md is the playtesting guide.
##
## Steps, as arrays:
##   ["hold", action, seconds]   press an input action, wait, release it
##   ["tap", action]             press and release on the next frame
##   ["down", action] / ["up", action]
##   ["look", dx, dy]            turn: mouse motion in pixels (right, down)
##   ["click", x, y]             left mouse click at a screen position
##   ["wait", seconds]
##   ["text", "..."]             type into whatever has focus
## Playtesting (docs/PLAYTEST.md):
##   ["record_start", fps, label]  start recording this window (net/dev/recorder.gd);
##                                 it keeps going across commands until record_stop
##   ["record_stop"]               stop, and write the frames, sheet and events
##   ["record", seconds, fps, label]  record while waiting this long
##   ["scenario", name]            jump to a moment (net/dev/scenarios.gd; host only;
##                                 "list" lists them)
##   ["follow", who, distance, height, yaw, mode]  a spectator camera orbiting a
##                                 player ("me", "host", "other", a peer id or a
##                                 name) or "crew", "van", "chefty"; yaw in degrees,
##                                 0 behind them, 180 in front; mode "body" (turns
##                                 with them, the default) or "world"
##   ["cam", x, y, z, look_x, look_y, look_z]  a fixed camera
##   ["follow_off"] / ["cam_off"]  back to the player's own camera
##   ["hud", true|false]           show or hide the HUD, for clean shots
## Actions are the names in project.godot's input map (move_forward, interact,
## primary, secondary, drop, jump, sprint, crouch, phone, pause, the pockets
## slot_1 ... slot_5, slot_next and slot_prev, ...). The result's "hotbar" says
## what's in the pockets: the selected slot (-1 bare hands), each slot's kind
## ("" empty) and the big thing in both arms ("" none).
## With --observer (a client, tools/play.ps1 -Observer) this peer parks its own
## player at the store, out of the raid, and follows the host by default. The
## host's remote play keeps the observer in the host's zone wherever the host goes
## (_shadow_observers), so it watches the moment as someone there would.

const _RecorderScript = preload("res://net/dev/recorder.gd")
const _ScenariosScript = preload("res://net/dev/scenarios.gd")
## The observer's default view of the host: distance, height, yaw (degrees).
const OBSERVER_VIEW := [5.5, 2.4, 35.0]
## The name tools/play.ps1 gives the observer (--name=Observer); the host knows it by it.
const OBSERVER_NAME: String = "Observer"
## The observer is safe from the NICE BOYS until this server time (s): for good.
const OBSERVER_SAFE_UNTIL: float = 1.0e9
## How far in front of whatever blocks it the spectator camera stops, in meters.
const SPECTATOR_CLEARANCE: float = 0.3
## How long the first command waits for the world and the player.
const READY_WAIT_SECONDS: float = 40.0

var _dir: String = ""
var _last_id: int = 0
var _busy: bool = false
var _poll: float = 0.0
var _ready_checked: bool = false
var _recorder: Node
var _spectator: Camera3D
var _previous_camera: Camera3D
## {who, distance, height, yaw, mode} while following, or {} (a fixed shot or off).
var _follow: Dictionary = {}
var _fixed_shot: bool = false
var _finished_recordings: Array = []
var _observer_parked: bool = false


func _ready() -> void:
	_dir = str(Net.dev_options().get("remote_play"))
	DirAccess.make_dir_recursive_absolute(_dir)
	# A fresh start: nothing old in the mailbox gets replayed.
	var stale := _dir.path_join("cmd.json")
	if FileAccess.file_exists(stale):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(stale))
		if typeof(parsed) == TYPE_DICTIONARY:
			_last_id = int((parsed as Dictionary).get("id", 0))
	_recorder = _RecorderScript.new()
	_recorder.name = "Recorder"
	_recorder.set("state_source", _state)
	add_child(_recorder)
	# After everything that moves, so a followed player is where they're drawn.
	process_priority = 1000
	print("[RemotePlay] reading %s (last id %d)" % [_dir.path_join("cmd.json"), _last_id])
	# tools/play.ps1 waits for this before its first command, so that command
	# isn't mistaken for a stale one from before the launch.
	var ready := FileAccess.open(_dir.path_join("ready.json"), FileAccess.WRITE)
	if ready != null:
		ready.store_string(JSON.stringify({"pid": OS.get_process_id(), "last_id": _last_id}))
		ready.close()


func _process(delta: float) -> void:
	_update_spectator()
	_park_observer()
	_shadow_observers()
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
	var extra := {}
	if not _ready_checked:
		_ready_checked = true
		await _wait_until_ready()
		var start_scenario := _scenarios()
		if start_scenario != null and not (start_scenario.get("start_result") as Dictionary).is_empty():
			extra["scenario"] = start_scenario.get("start_result")
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
			"record_start":
				var started: Dictionary = _recorder.call("start", _dir, float(step[1]) if step.size() > 1 else 30.0, str(step[2]) if step.size() > 2 else "clip")
				if started.has("error"):
					errors.append(started["error"])
				extra["recording"] = started
			"record_stop":
				_stop_recording(errors)
			"record":
				var began: Dictionary = _recorder.call("start", _dir, float(step[2]) if step.size() > 2 else 30.0, str(step[3]) if step.size() > 3 else "clip")
				if began.has("error"):
					errors.append(began["error"])
				else:
					await _seconds(float(step[1]) if step.size() > 1 else 2.0)
					_stop_recording(errors)
			"scenario":
				var scenarios := _scenarios() as _ScenariosScript
				if scenarios == null:
					errors.append("no scenarios node")
				else:
					var outcome: Dictionary = await scenarios.run(str(step[1]) if step.size() > 1 else "list")
					extra["scenario"] = outcome
					if outcome.has("error"):
						errors.append("scenario %s: %s" % [str(step[1]), outcome["error"]])
			"follow":
				_follow = {
					"who": _word(step[1]) if step.size() > 1 else "me",
					"distance": float(step[2]) if step.size() > 2 else 4.0,
					"height": float(step[3]) if step.size() > 3 else 1.8,
					"yaw": float(step[4]) if step.size() > 4 else 0.0,
					"mode": str(step[5]) if step.size() > 5 else "body",
				}
				_fixed_shot = false
				_spectate_on()
				_update_spectator()
				if _follow_target() == null:
					errors.append("nothing to follow called %s" % _follow["who"])
			"cam":
				if step.size() < 7:
					errors.append("cam needs x, y, z, look_x, look_y, look_z")
				else:
					_follow = {}
					_fixed_shot = true
					_spectate_on()
					_spectator.look_at_from_position(Vector3(float(step[1]), float(step[2]), float(step[3])), Vector3(float(step[4]), float(step[5]), float(step[6])), Vector3.UP)
			"follow_off", "cam_off":
				_spectate_off()
			"hud":
				var ui := get_tree().get_first_node_in_group("game_ui")
				if ui != null:
					ui.set("visible", step.size() < 2 or not ["false", "0", "off", "no"].has(_word(step[1]).to_lower()))
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
	var image := get_viewport().get_texture().get_image()
	if image != null and not image.is_empty():
		image.save_png(shot)
	var report := _state()
	report["id"] = id
	report["shot"] = shot
	report["errors"] = errors
	report.merge(extra)
	if bool(_recorder.get("recording")):
		report["recording_now"] = true
	if not _finished_recordings.is_empty():
		report["recordings"] = _finished_recordings.duplicate()
		_finished_recordings.clear()
	if _spectator != null and _spectator.current:
		report["view"] = _follow.duplicate() if not _follow.is_empty() else {"fixed": _v(_spectator.global_position)}
	var file := FileAccess.open(_dir.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	_busy = false


func _stop_recording(errors: Array) -> void:
	var done: Dictionary = _recorder.call("stop")
	if done.has("error"):
		errors.append(done["error"])
	else:
		_finished_recordings.append(done)


func _scenarios() -> Node:
	return get_parent().get_node_or_null("Scenarios")


## The first command waits for the session, the world, this player and any
## --scenario, so a fresh launch's first picture isn't the loading screen.
func _wait_until_ready() -> void:
	var waited := 0.0
	while waited < READY_WAIT_SECONDS:
		var scenarios := _scenarios()
		var scenario_done := scenarios == null or bool(scenarios.get("start_done"))
		if Net.current_state() == Net.State.IN_SESSION and _player_node(Net.local_peer_id()) != null and scenario_done:
			return
		await get_tree().create_timer(0.25).timeout
		waited += 0.25


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


# ---------------------------------------------------------------- the spectator camera


func _spectate_on() -> void:
	if _spectator == null:
		_spectator = Camera3D.new()
		_spectator.name = "SpectatorCam"
		# Placed every frame from interpolated transforms, outside physics ticks.
		_spectator.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		_spectator.fov = Settings.fov()
		add_child(_spectator)
	if not _spectator.current:
		var now := get_viewport().get_camera_3d()
		if now != _spectator:
			_previous_camera = now
	_spectator.current = true


func _spectate_off() -> void:
	_follow = {}
	_fixed_shot = false
	if _spectator == null:
		return
	_spectator.current = false
	if is_instance_valid(_previous_camera) and _previous_camera.is_inside_tree():
		_previous_camera.current = true
	_previous_camera = null


func _update_spectator() -> void:
	if _spectator == null or (_follow.is_empty() and not _fixed_shot):
		return
	# Something else (the crossing camera, a seat) may have taken over: take it back.
	if not _spectator.current:
		_spectator.current = true
	if _follow.is_empty():
		return
	var target := _follow_target()
	if target == null:
		return
	var at := target.get_global_transform_interpolated() if target.is_physics_interpolated() else target.global_transform
	var facing := 0.0
	if str(_follow["mode"]) != "world":
		var owner_body := target.get_parent() if target.name == "Visual" or target.name == "Body" else target
		facing = float(owner_body.get("body_yaw")) if owner_body != null and owner_body.get("body_yaw") != null else at.basis.get_euler().y
	var offset := Basis(Vector3.UP, facing + deg_to_rad(float(_follow["yaw"]))) * Vector3(0.0, 0.0, float(_follow["distance"]))
	var look := at.origin + Vector3(0.0, 1.2, 0.0)
	var place := at.origin + offset + Vector3(0.0, float(_follow["height"]), 0.0)
	# Like a game's orbit camera: something solid between them and the camera
	# (a doghouse, a wall) pulls the camera in, instead of filming the inside of it.
	var space := _spectator.get_world_3d().direct_space_state if _spectator.is_inside_tree() else null
	if space != null:
		var query := PhysicsRayQueryParameters3D.create(look, place)
		var excluded: Array[RID] = []
		for node: Node in get_tree().get_nodes_in_group("players"):
			if node is CollisionObject3D:
				excluded.append((node as CollisionObject3D).get_rid())
		for node: Node in get_tree().get_nodes_in_group("crew"):
			if node is CollisionObject3D:
				excluded.append((node as CollisionObject3D).get_rid())
		query.exclude = excluded
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			var back := (place - look).normalized()
			place = (hit["position"] as Vector3) - back * SPECTATOR_CLEARANCE
			if place.distance_to(look) < 0.5:
				place = look + back * 0.5
	if place.is_equal_approx(look) or absf((place - look).normalized().dot(Vector3.UP)) > 0.999:
		place += Vector3(0.01, 0.0, 0.01)
	_spectator.look_at_from_position(place, look, Vector3.UP)


## What the spectator follows: a player's drawn body, a NICE BOY, the van or Chefty.
func _follow_target() -> Node3D:
	var who := str(_follow.get("who", "me")).to_lower()
	var node: Node = null
	match who:
		"me", "self":
			node = _player_node(Net.local_peer_id())
		"host":
			node = _player_node(1)
		"other":
			for player: Node in get_tree().get_nodes_in_group("players"):
				if player.name != str(Net.local_peer_id()):
					node = player
					break
		"crew", "nice_boy", "crew1":
			var crew := get_tree().get_nodes_in_group("crew")
			node = crew[0] if not crew.is_empty() else null
		"van":
			var world := get_tree().get_first_node_in_group("world")
			node = world.get_node_or_null("Rides/Van") if world != null else null
			return node.get_node_or_null("Body") as Node3D if node != null else null
		"chefty":
			node = get_tree().get_first_node_in_group("chefty")
			return node.get_node_or_null("Body") as Node3D if node != null and node.get_node_or_null("Body") != null else node as Node3D
		_:
			if who.is_valid_int():
				node = _player_node(int(who))
			else:
				for peer_id: int in Net.peer_ids():
					if Net.player_name(peer_id).to_lower() == who:
						node = _player_node(peer_id)
	if node == null:
		return null
	var visual := node.get_node_or_null("Visual") as Node3D
	return visual if visual != null else node as Node3D


## --observer: a client that watches. Its own player goes to the store (out of
## the raid, which only takes people on the yard) and it follows the host.
func _park_observer() -> void:
	if bool(Net.dev_options().get("observer")) and not Net.is_host():
		_ghost(_player_node(Net.local_peer_id()))
	if _observer_parked or not bool(Net.dev_options().get("observer")) or Net.is_host():
		return
	if Net.current_state() != Net.State.IN_SESSION or _player_node(Net.local_peer_id()) == null or _player_node(1) == null:
		return
	_observer_parked = true
	Net.request_zone_move(Net.Zone.STORE)
	_follow = {"who": "host", "distance": OBSERVER_VIEW[0], "height": OBSERVER_VIEW[1], "yaw": OBSERVER_VIEW[2], "mode": "body"}
	_spectate_on()
	print("[RemotePlay] observer: parked at the store, following the host")


## Host: an observer goes where the host goes. When the host changes zones the
## observer is sent after them the way the game sends anyone (a host-ordered
## teleport into the zone), so its HUD, cues, music, ambience and the quips the
## yard plays are the ones a player there gets, and the recorder's zone line says
## so. Its body is a ghost: drawn by nobody and solid to nobody on the host and on
## the observer (_ghost), so it never turns up in a shot or in anyone's way, and
## it is never someone the NICE BOYS can take (the director's own safe list), so
## watching changes nothing it films. Riding (TRANSIT) or crossing (BORDER) the
## host leaves it at the store, as before: the van and Border Return have rosters
## of their own. Not in the connected town, where zones follow where people stand.
func _shadow_observers() -> void:
	if not Net.is_host() or Net.current_state() != Net.State.IN_SESSION:
		return
	var world := get_tree().get_first_node_in_group("world")
	if world != null and world.has_method("is_town_map") and bool(world.call("is_town_map")):
		return
	var target := Net.Zone.LOT if Net.player_zone(1) == Net.Zone.LOT else Net.Zone.STORE
	var director := get_tree().get_first_node_in_group("run_director")
	for peer_id: int in Net.peer_ids():
		if peer_id == 1 or Net.player_name(peer_id) != OBSERVER_NAME:
			continue
		if director != null:
			var safe: Dictionary = director.get("_safe_until")
			safe[peer_id] = OBSERVER_SAFE_UNTIL
		_ghost(_player_node(peer_id))
		if Net.player_zone(peer_id) != target:
			Net.move_player_to_zone(peer_id, target)


## An observer's own body, here: not drawn (its name tag goes with it) and not
## solid. Every frame, since the player's own code may show it again.
static func _ghost(body: Node3D) -> void:
	if body == null:
		return
	var visual := body.get_node_or_null("Visual") as Node3D
	if visual != null and visual.visible:
		visual.visible = false
	var shape := body.get_node_or_null("Collision") as CollisionShape3D
	if shape != null and not shape.disabled and not body.is_multiplayer_authority():
		shape.disabled = true


## A step argument as a word. cmd.json is read with JSON.parse_string, which
## makes every number a float (peer id 1527381234 would read "1527381234.0"),
## so a whole number comes back as its digits.
static func _word(value: Variant) -> String:
	if typeof(value) == TYPE_FLOAT and is_finite(value) and float(value) == floorf(float(value)) and absf(float(value)) < 9.0e15:
		return str(int(value))
	return str(value)


func _player_node(peer_id: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node as Node3D
	return null


func _v(at: Vector3) -> Array:
	return [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)]


## What a person would read off the screen, plus where they are.
func _state() -> Dictionary:
	var out := {}
	var me := Net.local_peer_id()
	out["zone"] = Net.Zone.keys()[Net.player_zone(me)]
	out["cash"] = Campaign.credits(me)
	out["mouse"] = ["visible", "hidden", "captured", "confined", "confined_hidden"][Input.mouse_mode]
	var player: Node3D = _player_node(me)
	if player != null:
		var p := player.global_position
		out["position"] = [snappedf(p.x, 0.1), snappedf(p.y, 0.1), snappedf(p.z, 0.1)]
		out["facing_deg"] = int(round(rad_to_deg(player.global_rotation.y)))
		out["pitch_deg"] = int(round(rad_to_deg(float(player.get("head_pitch")))))
		var held: Node = player.call("_held_prop") if player.has_method("_held_prop") else null
		out["holding"] = str(held.get("kind")) if held != null else ""
		if player.has_method("is_hidden") and bool(player.call("is_hidden")):
			out["hidden"] = true
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
	var director := get_tree().get_first_node_in_group("run_director")
	if director != null and int(director.call("phase")) != 0:
		out["raid"] = ["QUIET", "WARNING", "CHASE"][clampi(int(director.call("phase")), 0, 2)]
		out["raid_status"] = str(director.call("status_line"))
	var crossing := get_tree().get_first_node_in_group("border_return")
	if crossing != null and str(crossing.call("status_line")) != "":
		out["border"] = str(crossing.call("status_line"))
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		out["camera"] = "%s/%s" % [camera.get_parent().name, camera.name] if camera.get_parent() != null else str(camera.name)
	out["xp"] = "%d banked, %d pending" % [Campaign.crew_xp(), Campaign.pending_xp()]
	return out
