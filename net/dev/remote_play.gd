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
## Scripted play (R2b tools: a whole sequence runs in the game, with no round
## trips, so the agent's thinking time never eats game time; tools/play.ps1
## -Script sends a file of these):
##   ["until", key, value, timeout] wait until what's on screen says so: key is a
##                                 field of the result (zone, raid, prompt, goal,
##                                 holding, camera, hidden, annex.stage, ... dotted
##                                 for nested ones), value a piece of its text (case
##                                 doesn't matter; "!x" waits until it isn't x);
##                                 an error after timeout seconds (default 15)
##   ["mark", text]                a note on this frame of the recording ("mark"
##                                 event) and in the result's "marks", with times
##   ["face", x, z]                turn to face a point (eased, like a hand)
##   ["goto", x, z, timeout]       turn and walk there (move_forward) until within
##                                 half a meter; or ["goto", path] for a node under
##                                 World (e.g. BorderZone/AnnexSet/Windows/B/Counter)
##                                 or a name a player would walk to (tools:crew):
##                                 a teammate ("goto Bot2"), "chefty" (behind its
##                                 tailgate), a group ("job_board", "homeowner") or
##                                 the nearest loose thing of a kind ("rake",
##                                 "leaf_bag"); by name it stops at arm's length
##                                 (GOTO_NAMED_STOP), not inside the thing.
##   ["call_raid"]                 (host) the NICE BOYS are called now through the
##                                 run director's own warning, nothing reset or
##                                 placed: a raid in a crew session (tools:crew)
## The result's "crew" lists everyone else (not the observer) as this window knows
## them: zone, position and what they hold, so a script can wait on a teammate.

##   ["drive", x, z, timeout, top]  at Chefty's wheel: drive there along the roads
##                                 (W/S and A/D as eased strengths, slowing for
##                                 corners), up to top m/s (driving:E2)
## A "look" bigger than LOOK_EASE_ABOVE pixels is eased over several frames (a
## hand on a mouse), so the recorder's cam_snap flags mean the game, not the agent.
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
## The spectator camera (R2b tools): a sphere this big is swept from the subject
## out to the camera, against colliders and against the drawn shapes (trees'
## crowns, hedges, lamp posts, the van have little or no collision): it never
## sits inside anything. It pulls in at once, eases back out at this speed (m/s),
## never closer than the minimum, and turns toward its yaw at this rate (1/s), so
## a subject that spins round never whips it.
const SPECTATOR_RADIUS: float = 0.22
const SPECTATOR_MIN_DISTANCE: float = 0.7
const SPECTATOR_EASE_OUT: float = 2.5
const SPECTATOR_TURN_RATE: float = 3.0
## The subject moving farther than this in one frame was teleported: the
## spectator cuts with it (and says so to the recorder: a cam_cut, not a snap).
const SPECTATOR_CUT_METERS: float = 2.0
## Blocked, the camera rises by the first of these (m) with at least
## SPECTATOR_ROOM_ENOUGH of its distance clear (else the roomiest), easing up and
## down at SPECTATOR_LIFT_RATE (m/s).
const SPECTATOR_LIFTS: Array[float] = [0.0, 1.5, 3.0]
const SPECTATOR_ROOM_ENOUGH: float = 0.85
const SPECTATOR_LIFT_RATE: float = 2.0
## A pair's other side must have this much more room (m) before the camera swings over.
const SPECTATOR_SIDE_STICK: float = 1.0
## The camera keeps this far from anyone else's body axis (m).
const SPECTATOR_PERSON_METERS: float = 0.45
## How fast the aim point follows a change of who's in the shot (1/s).
const SPECTATOR_AIM_RATE: float = 6.0
## A NICE BOY (or, following one, a player) this close is the subject's partner
## (the escort, the two-shot): the shot frames both, and a yaw that would line them
## up within SPECTATOR_LINED_DEGREES of the view axis turns side-on instead.
const SPECTATOR_PAIR_METERS: float = 2.4
const SPECTATOR_LINED_DEGREES: float = 40.0
## Drawn shapes the sweep stops at: rebuilt this often (s), within this radius of
## the subject (m); a shape wider than the span (ground, roads, whole lots) or
## smaller than the min is skipped; boxes shrink by this much (a crown's box is
## bigger than its leaves).
const OCCLUDER_REFRESH_SECONDS: float = 3.0
const OCCLUDER_RADIUS: float = 45.0
const OCCLUDER_MAX_SPAN: float = 14.0
const OCCLUDER_MIN_SPAN: float = 0.3
const OCCLUDER_SHRINK: float = 0.85
## Narrower than this (m), a shape only keeps the camera out of itself; wider, it
## also pulls the camera in when it blocks the view.
const OCCLUDER_THIN_SPAN: float = 1.2
## A tree (props/trees.gd) is a trunk this wide (in its build scale, like its
## collider) up to this share of its height, and a crown above that.
const TREE_TRUNK_RADIUS: float = 0.35
const TREE_CROWN_FROM: float = 0.35
## A MultiMesh with more instances than this counts as one box (or is skipped).
const OCCLUDER_MULTIMESH_MAX: int = 600
## look: pixels in one frame at most before it's eased, and how many a frame then.
const LOOK_EASE_ABOVE: float = 100.0
const LOOK_PIXELS_PER_FRAME: float = 30.0
## goto: arrived within this (m); walks while facing within this (radians).
const GOTO_ARRIVE_METERS: float = 0.5
## A goto by a name (a teammate, "job_board", "rake") stops this far short (m):
## in reach of E, not standing in it.
const GOTO_NAMED_STOP: float = 1.3

## The drive step (driving:E2): done within this far of the point and stopped; a
## waypoint counts as passed this close; it steers for a point this far plus half
## its speed (m/s as m) down the route; sharp corners at this speed (m/s).
const DRIVE_ARRIVE_METERS: float = 5.0
const DRIVE_WAYPOINT_METERS: float = 7.0
const DRIVE_LOOK_METERS: float = 7.0
const DRIVE_CORNER_SPEED: float = 7.0
const GOTO_WALK_RADIANS: float = 0.5
## until, goto: the default timeout (s).
const UNTIL_SECONDS: float = 15.0
## How long the first command waits for the world and the player.
const READY_WAIT_SECONDS: float = 40.0
## A peer is dropped after this many ms of silence in a remote-play session.
const DEV_PEER_TIMEOUT_MS: int = 20000

var _dir: String = ""
var _last_id: int = 0
var _busy: bool = false
var _poll: float = 0.0
var _ready_checked: bool = false
var _recorder: _RecorderScript
var _marks: Array = []
var _spec_yaw: float = NAN
var _spec_dist: float = -1.0
var _spec_last_at := Vector3.INF
var _spec_aim_shift := Vector3.ZERO
var _spec_lift: float = 0.0
## The vehicle the subject rides in (a van's Trip holder, Chefty), or null.
var _spec_ride: Node = null
var _spec_subject: Node = null
var _spec_why: String = ""
## The look point is inside the ridden vehicle's box (a seat): its shell is then
## the subject's own, and the camera stays outside it.
var _spec_inside_ride: bool = false
var _spec_debug: bool = OS.has_environment("PLAYTEST_SPECTATOR_DEBUG")
var _spec_target_id: int = 0
var _occluders: Array[AABB] = []
## One Array of GeometryInstance3D per thing that moves (a van, Chefty).
var _occluder_movers: Array = []
var _occluders_at_msec: int = -1000000
var _occluders_center := Vector3.INF
var _loosened: Dictionary = {}
var _occluder_trips: int = -1
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
	_recorder.state_source = _state
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


## Remote play's windows stall now and then (a town block's first build took 5 s
## on a loaded machine, R2b tools), and ENet drops a peer after about 5 s of
## silence ("Host left"): a session with remote play waits this long instead, on
## both ends (the host for its clients, a client for the host). Dev only, local.
func _loosen_timeouts() -> void:
	var peer: Variant = multiplayer.multiplayer_peer
	if peer != null and not (peer is ENetMultiplayerPeer) and "inner" in peer:
		peer = peer.get("inner")
	if not (peer is ENetMultiplayerPeer) or (peer as ENetMultiplayerPeer).get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	var others: Array[int] = []
	if multiplayer.is_server():
		for peer_id: int in multiplayer.get_peers():
			others.append(peer_id)
	else:
		others.append(1)
	for peer_id: int in others:
		if _loosened.has(peer_id):
			continue
		var link := (peer as ENetMultiplayerPeer).get_peer(peer_id)
		if link != null:
			link.set_timeout(32, DEV_PEER_TIMEOUT_MS, DEV_PEER_TIMEOUT_MS * 3)
			_loosened[peer_id] = true


func _process(delta: float) -> void:
	_loosen_timeouts()
	_update_spectator(delta)
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
				await _look(float(step[1]), float(step[2]) if step.size() > 2 else 0.0)
			"until":
				var waited_out: String = await _until(_word(step[1]) if step.size() > 1 else "", _word(step[2]) if step.size() > 2 else "", float(step[3]) if step.size() > 3 else UNTIL_SECONDS)
				if waited_out != "":
					errors.append(waited_out)
			"mark":
				var text := " ".join(step.slice(1).map(func(part: Variant) -> String: return _word(part)))
				_recorder.note(text)
				_marks.append({"text": text, "game_seconds": snappedf(Net.server_time(), 0.01), "recording": _recorder.recording})
			"face":
				var spot := _point_of(step.slice(1))
				if spot == Vector3.INF:
					errors.append("face needs x z, or a node path under World")
				else:
					await _face(spot)
			"goto":
				var spot := _point_of(step.slice(1))
				if spot == Vector3.INF:
					errors.append("goto needs x z, or a node path under World")
				else:
					# goto x z [timeout], or goto path [timeout]
					var named := step.size() > 1 and typeof(step[1]) == TYPE_STRING
					var timeout_at := 2 if named else 3
					# A name (not a node path under World) stops at arm's length.
					var world := get_tree().get_first_node_in_group("world")
					var by_name := named and (world == null or world.get_node_or_null(NodePath(str(step[1]))) == null)
					# "chefty" is already a place to stand (behind the tailgate, inside
					# the store's boarding area), not a thing to stop short of.
					by_name = by_name and str(step[1]).to_lower() != "chefty"
					var went: String = await _goto(spot, float(step[timeout_at]) if step.size() > timeout_at else UNTIL_SECONDS, GOTO_NAMED_STOP if by_name else GOTO_ARRIVE_METERS)
					var truck := get_tree().get_first_node_in_group("chefty") as Node3D
					if named and str(step[1]).to_lower() == "chefty" and truck != null:
						# Then look at the truck, as anyone boarding does: walking up
						# beside a friend left you facing them, and E picked them up.
						await _face(truck.call("body_position") if truck.has_method("body_position") else truck.global_position)
					if went != "":
						errors.append(went)
			"call_raid":
				# tools:crew: the NICE BOYS called now, the way the heat calls them
				# (the director's warning, then the van), with nothing reset or
				# placed: for a crew session. Host only; QUIET only.
				var director := get_tree().get_first_node_in_group("run_director")
				if not Net.is_host() or director == null or int(director.call("phase")) != 0:
					errors.append("call_raid: host only, with no raid on")
				else:
					director.call("force_event")

			"drive":
				# drive x z [timeout] [top speed m/s]: at Chefty's wheel, along the roads (driving:E2).
				var went_by_road: String = await _drive(Vector3(float(step[1]), 0.0, float(step[2])), float(step[3]) if step.size() > 3 else 90.0, float(step[4]) if step.size() > 4 else Constants.CHEFTY_TOP_SPEED)
				if went_by_road != "":
					errors.append(went_by_road)
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
				# A new shot is the agent's cut, not a snap.
				if _spectator != null and _spectator.current:
					_recorder.note_cut("follow %s" % " ".join(step.slice(1).map(func(part: Variant) -> String: return _word(part))))
				_spec_target_id = 0
				_follow = {
					"who": _word(step[1]) if step.size() > 1 else "me",
					"distance": float(step[2]) if step.size() > 2 else 4.0,
					"height": float(step[3]) if step.size() > 3 else 1.8,
					"yaw": float(step[4]) if step.size() > 4 else 0.0,
					"mode": str(step[5]) if step.size() > 5 else "body",
				}
				_fixed_shot = false
				_spectate_on()
				_update_spectator(0.0)
				if _follow_target() == null:
					errors.append("nothing to follow called %s" % _follow["who"])
			"cam":
				if step.size() < 7:
					errors.append("cam needs x, y, z, look_x, look_y, look_z")
				else:
					_follow = {}
					_fixed_shot = true
					_recorder.note_cut("cam")
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
	# A take stopped in this command is written on its own thread while the game
	# runs on (net/dev/recorder.gd); the answer waits for its files.
	await _recorder.wait_written()
	# Let the screen catch up with the last input before the picture.
	await get_tree().process_frame
	await get_tree().process_frame
	var shot := _dir.path_join("shot_%04d.png" % id)
	if DisplayServer.get_name() == "headless":
		# Nothing is drawn (a -BotsHeadless bot): no picture, and no engine error
		# from asking the dummy renderer for one.
		shot = ""
	else:
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
	if not _marks.is_empty():
		report["marks"] = _marks.duplicate()
		_marks.clear()
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


## Turn the mouse. Up to LOOK_EASE_ABOVE pixels is one move; more is eased in
## and out over several frames like a hand on a mouse (R2b tools: one big step
## turned the camera 60 degrees in a frame, and the recorder flagged the agent's
## own input as a cam_snap).
func _look(dx: float, dy: float) -> void:
	var parts := look_steps(Vector2(dx, dy))
	for index: int in parts.size():
		if index > 0:
			await get_tree().process_frame
		_motion(parts[index])


## The per-frame mouse moves for a look of `total` pixels (smoothstep-eased).
static func look_steps(total: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var biggest := maxf(absf(total.x), absf(total.y))
	if biggest <= LOOK_EASE_ABOVE:
		out.append(total)
		return out
	var frames := int(ceil(biggest / LOOK_PIXELS_PER_FRAME))
	var done := Vector2.ZERO
	for index: int in frames:
		var s := smoothstep(0.0, 1.0, float(index + 1) / float(frames))
		var reached := total * s
		out.append(reached - done)
		done = reached
	return out


func _motion(relative: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.relative = relative
	motion.position = get_viewport().get_visible_rect().size * 0.5
	Input.parse_input_event(motion)


## until: wait for a field of what's on screen (_state(), dotted for nested ones)
## to contain a piece of text ("!text": to stop containing it). "" when it did.
func _until(key: String, want: String, timeout: float) -> String:
	if key == "":
		return "until needs a field and a value (until zone BORDER 20)"
	var negate := want.begins_with("!")
	var needle := want.trim_prefix("!").to_lower()
	var waited := 0.0
	while waited <= timeout:
		var have := state_value(_state(), key).to_lower()
		if have.contains(needle) != negate:
			return ""
		await get_tree().process_frame
		waited += get_process_delta_time()
	return "until %s %s: still '%s' after %.1f s" % [key, want, state_value(_state(), key), timeout]


## A field of a _state() report by dotted path, as text ("" when there's none).
static func state_value(state: Dictionary, key: String) -> String:
	var value: Variant = state
	for part: String in key.split("."):
		if typeof(value) != TYPE_DICTIONARY or not (value as Dictionary).has(part):
			return ""
		value = (value as Dictionary)[part]
	return str(value)


## A step's point: x z (world meters), or a node path under World.
func _point_of(args: Array) -> Vector3:
	if args.is_empty():
		return Vector3.INF
	if typeof(args[0]) == TYPE_STRING and not str(args[0]).is_valid_float():
		var world := get_tree().get_first_node_in_group("world")
		var node := world.get_node_or_null(NodePath(str(args[0]))) as Node3D if world != null else null
		if node == null:
			return named_point(str(args[0]))
		return node.global_position
	if args.size() < 2:
		return Vector3.INF
	var me := _player_node(Net.local_peer_id())
	return Vector3(float(args[0]), me.global_position.y if me != null else 0.0, float(args[1]))


## tools:crew: face and goto by what a player would walk to: a teammate's name
## (goto Bot2), "chefty" (its bed's tailgate side), or a group's first node
## ("homeowner", "job_board", "hide_spots" ...). Vector3.INF when there's none.
func named_point(word: String) -> Vector3:
	var lowered := word.to_lower()
	for peer_id: int in Net.peer_ids():
		if Net.player_name(peer_id).to_lower() == lowered:
			var body := _player_node(peer_id)
			return body.global_position if body != null else Vector3.INF
	if lowered == "chefty":
		var truck := get_tree().get_first_node_in_group("chefty")
		if truck == null:
			return Vector3.INF
		# Behind the tailgate, where people stand to load it and to board it: the
		# place there furthest from everyone else, so two players sent there don't
		# end up standing in each other (bodies pass through each other).
		var bed: Transform3D = truck.call("bed_transform") if truck.has_method("bed_transform") else (truck as Node3D).global_transform
		var best := bed * Vector3(0.0, 0.0, 2.9)
		var roomiest := -1.0
		for side: float in [0.0, -1.1, 1.1]:
			var spot := bed * Vector3(side, 0.0, 2.9)
			var room := INF
			for peer_id: int in Net.peer_ids():
				var body := _player_node(peer_id)
				if peer_id == Net.local_peer_id() or body == null or Net.player_name(peer_id) == OBSERVER_NAME:
					continue
				room = minf(room, Vector2(body.global_position.x - spot.x, body.global_position.z - spot.z).length())
			if room > roomiest + 0.3:
				roomiest = room
				best = spot
		return best
	var first := get_tree().get_first_node_in_group(word) as Node3D
	if first != null:
		return first.global_position
	# A loose thing by its kind, the nearest one: "rake", "leaf_bag", "gnome".
	var me := _player_node(Net.local_peer_id())
	var best := Vector3.INF
	for node: Node in get_tree().get_nodes_in_group("props"):
		var prop := node as Node3D
		if prop == null or str(node.get("kind")) != lowered or (node.has_method("is_loose") and not bool(node.call("is_loose"))):
			continue
		if me == null or not best.is_finite() or prop.global_position.distance_to(me.global_position) < best.distance_to(me.global_position):
			best = prop.global_position
	return best


## The yaw error to face a point (radians, positive = turn left).
func _yaw_error(to: Vector3) -> float:
	var me := _player_node(Net.local_peer_id())
	if me == null:
		return 0.0
	var flat := Vector3(to.x - me.global_position.x, 0.0, to.z - me.global_position.z)
	if flat.length() < 0.01:
		return 0.0
	var want := atan2(-flat.x, -flat.z)
	var have := float(me.get("body_yaw")) if me.get("body_yaw") != null else me.global_rotation.y
	return wrapf(want - have, -PI, PI)


## Turn to face a point with the mouse, eased.
func _face(to: Vector3) -> void:
	var per_pixel := Settings.look_scale().x
	if absf(per_pixel) < 0.000001:
		return
	await _look(-_yaw_error(to) / per_pixel, 0.0)


## Walk to a point the way a player would: turn with the mouse, hold
## move_forward while roughly facing it. "" when there, else why not.
func _goto(to: Vector3, timeout: float, arrive: float = GOTO_ARRIVE_METERS) -> String:
	var me := _player_node(Net.local_peer_id())
	if me == null:
		return "goto: no player"
	var per_pixel := Settings.look_scale().x
	var walking := false
	var waited := 0.0
	var outcome := ""
	while true:
		var left := Vector2(to.x - me.global_position.x, to.z - me.global_position.z).length()
		if left <= arrive:
			break
		if waited > timeout:
			outcome = "goto: still %.1f m away after %.1f s" % [left, timeout]
			break
		var error := _yaw_error(to)
		if absf(per_pixel) > 0.000001 and absf(error) > 0.02:
			# A steady hand: at most LOOK_PIXELS_PER_FRAME a frame.
			var pixels := clampf(-error / per_pixel, -LOOK_PIXELS_PER_FRAME, LOOK_PIXELS_PER_FRAME)
			_motion(Vector2(pixels, 0.0))
		var should_walk := absf(error) < GOTO_WALK_RADIANS
		if should_walk != walking:
			walking = should_walk
			_action("move_forward", walking)
		await get_tree().process_frame
		waited += get_process_delta_time()
	if walking:
		_action("move_forward", false)
	return outcome


## Drive Chefty to a point the way a player at the wheel would (driving:E2's
## drive takes): W and S, A and D eased to a strength like a gamepad stick,
## along TownMap.route's roads, slowing for corners and pulling up at the end.
## Steers for a point a speed-dependent way down the route. "" when there.
func _drive(to: Vector3, timeout: float, top: float) -> String:
	var chefty := get_tree().get_first_node_in_group("chefty") as Node3D
	if chefty == null or not chefty.has_method("body_transform"):
		return "drive: no drivable Chefty"
	if int(chefty.call("driver")) != Net.local_peer_id():
		return "drive: not at Chefty's wheel"
	var start: Vector3 = (chefty.call("body_transform") as Transform3D).origin
	var route := TownMap.route(start, to)
	route.insert(0, Vector3(start.x, 0.0, start.z))
	route.append(Vector3(to.x, 0.0, to.z))
	var index := 1
	var waited := 0.0
	var outcome := ""
	while true:
		var here: Vector3 = (chefty.call("body_transform") as Transform3D).origin
		here.y = 0.0
		var speed := float(chefty.call("speed"))
		var left := Vector2(to.x - here.x, to.z - here.z).length()
		if left < DRIVE_ARRIVE_METERS and speed < 1.0:
			break
		if waited > timeout:
			outcome = "drive: still %.0f m away after %.0f s" % [left, timeout]
			break
		while index < route.size() - 1 and Vector2(route[index].x - here.x, route[index].z - here.z).length() < DRIVE_WAYPOINT_METERS:
			index += 1
		# The point to steer for: this far down the route from the next waypoint back.
		var ahead := DRIVE_LOOK_METERS + speed * 0.5
		var target := route[index]
		var from := here
		for next: int in range(index, route.size()):
			var piece := Vector2(route[next].x - from.x, route[next].z - from.z).length()
			target = route[next]
			if piece >= ahead:
				target = from + (route[next] - from).normalized() * ahead
				break
			ahead -= piece
			from = route[next]
		var heading := float(chefty.call("yaw"))
		var want := atan2(-(target.x - here.x), -(target.z - here.z))
		var error := wrapf(want - heading, -PI, PI)
		var steer := clampf(-error * 2.2, -1.0, 1.0)
		# Slow for a sharp corner coming up, and pull up at the end.
		var want_speed := top
		if index < route.size() - 1:
			var into := (route[index] - here).normalized()
			var out := (route[index + 1] - route[index]).normalized()
			var corner := acos(clampf(into.dot(out), -1.0, 1.0))
			var gap := Vector2(route[index].x - here.x, route[index].z - here.z).length()
			if corner > 0.5:
				want_speed = minf(want_speed, lerpf(DRIVE_CORNER_SPEED, top, clampf((gap - 8.0) / 45.0, 0.0, 1.0)))
		want_speed = minf(want_speed, maxf(left - 2.0, 0.0) * 0.6)
		var throttle := clampf((want_speed - speed) * 0.4, -1.0, 1.0)
		_axis("move_forward", maxf(throttle, 0.0))
		_axis("move_back", maxf(-throttle, 0.0))
		_axis("move_right", maxf(steer, 0.0))
		_axis("move_left", maxf(-steer, 0.0))
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	for action_name: String in ["move_forward", "move_back", "move_left", "move_right"]:
		_axis(action_name, 0.0)
	return outcome


func _axis(action_name: String, strength: float) -> void:
	var event := InputEventAction.new()
	event.action = action_name
	event.pressed = strength > 0.01
	event.strength = strength if event.pressed else 0.0
	Input.parse_input_event(event)


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


func _update_spectator(delta: float) -> void:
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
	# A new subject, or one teleported (a scenario, a zone move): cut with it.
	var cut := target.get_instance_id() != _spec_target_id or not _spec_last_at.is_finite() or at.origin.distance_to(_spec_last_at) > SPECTATOR_CUT_METERS
	if cut and _spec_target_id != 0 and _spec_last_at.is_finite():
		_recorder.note_cut("the followed %s moved %.1f m in a frame" % [target.get_parent().name if target.name == "Visual" else target.name, at.origin.distance_to(_spec_last_at)])
	_spec_target_id = target.get_instance_id()
	_spec_last_at = at.origin
	var facing := 0.0
	if str(_follow["mode"]) != "world":
		var owner_body := target.get_parent() if target.name == "Visual" or target.name == "Body" else target
		facing = float(owner_body.get("body_yaw")) if owner_body != null and owner_body.get("body_yaw") != null else at.basis.get_euler().y
	var want := facing + deg_to_rad(float(_follow["yaw"]))
	var look := at.origin + Vector3(0.0, 1.2, 0.0)
	# Arm in arm (the escort) or face to face (the two-shot): frame both, side-on.
	var partner := _pair_partner(target)
	_spec_ride = _subject_ride(target)
	var ride_box := _ride_box()
	var inside := ride_box.size != Vector3.ZERO and ride_box.has_point(at.origin + Vector3(0.0, 1.2, 0.0))
	if inside != _spec_inside_ride and not cut and _spec_target_id != 0:
		# Into a vehicle's seat or out of it: the shot moves to its outside (or
		# back) in a cut, never through its walls.
		cut = true
		_recorder.note_cut("the followed subject %s a vehicle" % ("sat down in" if inside else "got out of"))
	_spec_inside_ride = inside
	if partner.is_finite():
		look = (look + partner + Vector3(0.0, 1.2, 0.0)) * 0.5
		want = side_on_yaw(want, Vector3(partner.x - at.origin.x, 0.0, partner.z - at.origin.z))
		# A pair has two good sides: the one with room (the van's side is cramped).
		var here := _room_toward(look, want)
		var there := _room_toward(look, want + PI)
		var keep := 0.0 if is_nan(_spec_yaw) else SPECTATOR_SIDE_STICK
		if absf(angle_difference(_spec_yaw if not is_nan(_spec_yaw) else want, want + PI)) < PI * 0.5:
			there += keep
		else:
			here += keep
		if there > here:
			want += PI
	# The aim follows the subject rigidly; only the shift toward a partner (who
	# steps in or out of the shot) glides, never jumps.
	var aim_shift := look - (at.origin + Vector3(0.0, 1.2, 0.0))
	if cut or is_nan(_spec_yaw):
		_spec_yaw = want
		_spec_aim_shift = aim_shift
	else:
		_spec_yaw = lerp_angle(_spec_yaw, want, 1.0 - exp(-SPECTATOR_TURN_RATE * delta))
		_spec_aim_shift = _spec_aim_shift.lerp(aim_shift, 1.0 - exp(-SPECTATOR_AIM_RATE * delta))
	look = at.origin + Vector3(0.0, 1.2, 0.0) + _spec_aim_shift
	var flat_offset := Basis(Vector3.UP, _spec_yaw) * Vector3(0.0, 0.0, float(_follow["distance"]))
	var base_height := float(_follow["height"]) - 1.2
	# Something low in the way (a parked car, a doorway, a hedge): crane up over
	# it rather than dive in to film from inside someone's face. The lowest lift
	# with nearly all its room wins, else the roomiest; it eases.
	var want_lift := 0.0
	var best_room := -1.0
	for lift: float in SPECTATOR_LIFTS:
		var probe := flat_offset + Vector3(0.0, base_height + lift, 0.0)
		var room := _clear_distance(look, probe.normalized(), probe.length())
		if room >= probe.length() * SPECTATOR_ROOM_ENOUGH:
			want_lift = lift
			break
		if room > best_room + 0.25:
			best_room = room
			want_lift = lift
	_spec_lift = want_lift if cut else move_toward(_spec_lift, want_lift, SPECTATOR_LIFT_RATE * delta)
	var offset := flat_offset + Vector3(0.0, base_height + _spec_lift, 0.0)
	var full := offset.length()
	if full < 0.01:
		return
	var out := offset / full
	var clear := _clear_distance(look, out, full)
	if cut or _spec_dist < 0.0 or clear < _spec_dist:
		# Pulled in at once: the camera never sits inside anything.
		_spec_dist = clear
	else:
		_spec_dist = minf(clear, _spec_dist + SPECTATOR_EASE_OUT * delta)
	# Riding: never inside the vehicle's shell.
	_spec_dist = maxf(_spec_dist, _ride_exit_distance(look, out))
	var place := look + out * maxf(_spec_dist, SPECTATOR_MIN_DISTANCE)
	# PLAYTEST_SPECTATOR_DEBUG=1 in the environment: what holds the camera in, 3x a second.
	if _spec_debug and Engine.get_process_frames() % 10 == 0:
		print("[SpecDebug] t=%.2f look=%s out=%s full=%.2f clear=%.2f dist=%.2f lift=%.2f ride=%s partner=%s why=%s" % [Net.server_time(), look, out, full, clear, _spec_dist, _spec_lift, _spec_ride, partner, _spec_why])
	if absf(out.dot(Vector3.UP)) > 0.999:
		place += Vector3(0.01, 0.0, 0.01)
	_spectator.look_at_from_position(place, look, Vector3.UP)


## The ridden vehicle's whole box now (AABB() when none).
func _ride_box() -> AABB:
	if _spec_ride == null or not is_instance_valid(_spec_ride):
		return AABB()
	for mover: Array in _occluder_movers:
		if mover[0] != _spec_ride:
			continue
		var whole := AABB()
		var first := true
		for node: Variant in mover[1]:
			var shape := node as GeometryInstance3D
			if shape == null or not is_instance_valid(shape) or not shape.is_visible_in_tree():
				continue
			var box := shape.global_transform * shape.get_aabb()
			whole = box if first else whole.merge(box)
			first = false
		return whole
	return AABB()


## How far out along `out` from `look` the ridden vehicle's box ends (plus a
## margin), or 0 when the subject rides nothing or the look is outside it.
func _ride_exit_distance(look: Vector3, out: Vector3) -> float:
	var whole := _ride_box()
	if not _spec_inside_ride or not whole.has_point(look):
		return 0.0
	var exit := INF
	for axis: int in 3:
		if absf(out[axis]) > 0.0001:
			var bound := whole.end[axis] if out[axis] > 0.0 else whole.position[axis]
			exit = minf(exit, (bound - look[axis]) / out[axis])
	return exit + SPECTATOR_CLEARANCE if exit < INF else 0.0


## How much room the camera has out along a yaw from the look point (m).
func _room_toward(look: Vector3, yaw: float) -> float:
	var offset := Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, float(_follow["distance"])) + Vector3(0.0, float(_follow["height"]) - 1.2, 0.0)
	return _clear_distance(look, offset.normalized(), offset.length())


## The yaw (offset direction from the subject, Basis(UP, yaw) * +Z) to film a
## pair from: `want` unless that lines them up within SPECTATOR_LINED_DEGREES of
## the view axis, then the side-on yaw nearest to it.
static func side_on_yaw(want: float, axis: Vector3) -> float:
	axis.y = 0.0
	if axis.length() < 0.2:
		return want
	axis = axis.normalized()
	var view := Vector3(sin(want), 0.0, cos(want))
	if absf(view.dot(axis)) < cos(deg_to_rad(SPECTATOR_LINED_DEGREES)):
		return want
	var side := Vector3(-axis.z, 0.0, axis.x)
	if side.dot(view) < 0.0:
		side = -side
	return atan2(side.x, side.z)


## What the subject is riding in: the Courtesy Shuttle van they're seated in (its
## Trip holder) or Chefty. The camera films that from outside, as anyone outside
## sees it (R2b tools: it stopped at a seat inside and filmed through heads).
func _subject_ride(target: Node3D) -> Node:
	var subject := target.get_parent() if target.name == "Visual" else target
	_spec_subject = subject
	# Following the van or Chefty itself: that's the subject's own box.
	for mover: Array in _occluder_movers:
		var root := mover[0] as Node
		if is_instance_valid(root) and (root == target or root.is_ancestor_of(target)):
			return root
	if subject == null or not subject.is_in_group("players") or not str(subject.name).is_valid_int():
		return null
	var peer_id := int(str(subject.name))
	var shuttle := get_tree().get_first_node_in_group("nice_shuttle")
	if shuttle != null:
		var seat: Dictionary = shuttle.call("seat_info", peer_id)
		if not seat.is_empty():
			return shuttle.get_node_or_null("Trip%d" % int(seat["trip"]))
	for truck: Node in get_tree().get_nodes_in_group("chefty"):
		if truck.has_method("seat_of") and int(truck.call("seat_of", peer_id)) >= 0:
			return truck
	return null


## The subject's partner, where one stands within SPECTATOR_PAIR_METERS: a NICE
## BOY next to a followed player, or the player next to a followed NICE BOY.
## Vector3.INF when there's none.
func _pair_partner(target: Node3D) -> Vector3:
	var subject := target.get_parent() as Node3D if target.name == "Visual" else target
	if subject == null:
		return Vector3.INF
	var others: Array[Node] = []
	if subject.is_in_group("players"):
		others = get_tree().get_nodes_in_group("crew")
	elif subject.is_in_group("crew"):
		for player: Node in get_tree().get_nodes_in_group("players"):
			var visual := player.get_node_or_null("Visual") as Node3D
			if visual != null and visual.visible:
				others.append(player)
	var best := SPECTATOR_PAIR_METERS
	var found := Vector3.INF
	for other: Node in others:
		var body := other as Node3D
		if body == null or body == subject:
			continue
		var gap := body.global_position.distance_to(subject.global_position)
		if gap < best:
			best = gap
			found = body.global_position
	return found


## How far out along `out` from `look` the camera can sit, up to `full`: a
## sphere swept against colliders, and the segment against the drawn shapes
## nearby (_occluders), stopping SPECTATOR_CLEARANCE short of the first.
func _clear_distance(look: Vector3, out: Vector3, full: float) -> float:
	var clear := full
	_spec_why = "none"
	var space := _spectator.get_world_3d().direct_space_state if _spectator.is_inside_tree() else null
	var excluded: Array[RID] = []
	if space != null:
		for group: String in ["players", "crew", "props"]:
			for node: Node in get_tree().get_nodes_in_group(group):
				if node is CollisionObject3D:
					excluded.append((node as CollisionObject3D).get_rid())
		# The vehicle the subject rides is the subject's own shell, not in the way.
		if _spec_ride != null and is_instance_valid(_spec_ride) and _spec_inside_ride:
			if _spec_ride is CollisionObject3D:
				excluded.append((_spec_ride as CollisionObject3D).get_rid())
			for body: Node in _spec_ride.find_children("*", "CollisionObject3D", true, false):
				excluded.append((body as CollisionObject3D).get_rid())
		# Line of sight: a wall, a house, a parked car between pulls the camera in.
		# Something thin (a trunk, a post) may cross the view for a moment; it's
		# only kept out of the camera itself, below. Thin is the shape the ray hit,
		# not its whole body: the connected town's solids are one StaticBody3D
		# (levels/town/town_colliders.gd) whose yard tree trunks and lamp posts used
		# to count as wide as its ground, so a trunk the followed truck drove past
		# pulled the camera into its bed (driving:E review, rec_drive_3p #376).
		var from := look
		for attempt: int in 8:
			var ray := PhysicsRayQueryParameters3D.create(from, look + out * clear)
			ray.exclude = excluded
			var hit := space.intersect_ray(ray)
			if hit.is_empty():
				break
			var collider := hit.get("collider") as CollisionObject3D
			if collider != null and _thin_collider(collider):
				excluded.append(collider.get_rid())
				continue
			if collider != null and _thin_hit_shape(collider, int(hit.get("shape", -1))):
				# Go on from just past it (a ray starting inside a shape ignores it).
				from = (hit["position"] as Vector3) + out * 0.02
				continue
			clear = minf(clear, look.distance_to(hit["position"] as Vector3) - SPECTATOR_CLEARANCE)
			_spec_why = "wall %s" % (collider.name if collider != null else "?")
			break
	_refresh_occluders(look)
	var to := look + out * clear
	var boxes: Array[AABB] = _occluders.duplicate()
	# A vehicle the subject sits in (a van seat) is the subject's own box: the
	# camera stays outside it, filming the van as anyone outside sees it, instead
	# of stopping at a seat inside and filming the cabin through heads (R2b tools).
	for mover: Array in _occluder_movers:
		if not is_instance_valid(mover[0]) or (mover[0] == _spec_ride and _spec_inside_ride):
			continue
		for node: Variant in mover[1]:
			var shape := node as GeometryInstance3D
			if shape != null and is_instance_valid(shape) and shape.is_visible_in_tree():
				# A vehicle's panels fill their boxes: no shrinking.
				boxes.append(shape.global_transform * shape.get_aabb())
	var thin: Array[AABB] = []
	for box: AABB in boxes:
		if maxf(box.size.x, box.size.z) < OCCLUDER_THIN_SPAN:
			thin.append(box)
			continue
		if box.has_point(look):
			continue
		var grown := box.grow(SPECTATOR_RADIUS)
		if grown.has_point(look):
			grown = box
		var hit: Variant = grown.intersects_segment(look, to)
		if hit != null:
			clear = minf(clear, look.distance_to(hit as Vector3) - SPECTATOR_CLEARANCE)
			to = look + out * clear
			_spec_why = "box %s" % box
	# Never inside anything: a thin thing the camera would sit in keeps it on the
	# near side of it; and a collider round the camera's spot (a trunk) the same.
	for box: AABB in thin:
		var grown := box.grow(SPECTATOR_RADIUS)
		if grown.has_point(look) or not grown.has_point(look + out * clear):
			continue
		var hit: Variant = grown.intersects_segment(look, look + out * clear)
		if hit != null:
			clear = minf(clear, look.distance_to(hit as Vector3) - SPECTATOR_CLEARANCE)
			_spec_why = "inside %s" % box
	if space != null:
		var sphere := SphereShape3D.new()
		sphere.radius = SPECTATOR_RADIUS
		var at_spot := PhysicsShapeQueryParameters3D.new()
		at_spot.shape = sphere
		at_spot.transform = Transform3D(Basis.IDENTITY, look + out * clear)
		at_spot.exclude = excluded.slice(0, excluded.size())
		if not space.intersect_shape(at_spot, 1).is_empty():
			var sweep := PhysicsShapeQueryParameters3D.new()
			sweep.shape = sphere
			sweep.transform = Transform3D(Basis.IDENTITY, look)
			sweep.motion = out * clear
			sweep.exclude = at_spot.exclude
			var fractions := space.cast_motion(sweep)
			# 0: the subject's own spot is inside something already; leave it.
			if fractions.size() == 2 and fractions[0] > 0.0 and fractions[0] < 1.0:
				clear = minf(clear, clear * fractions[0] - SPECTATOR_CLEARANCE * 0.5)
				_spec_why = "inside a collider"
	# Never inside someone's head: a person the camera would sit in (the van's
	# driver, a NICE BOY walking past) keeps it on the near side of them. Someone
	# merely between the camera and the subject doesn't pull it in.
	for group: String in ["crew", "players"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			var visual := node.get_node_or_null("Visual") as Node3D
			if body == null or body == _spec_subject or (visual != null and not visual.visible):
				continue
			var at := visual.global_position if visual != null else body.global_position
			var spot := look + out * clear
			if Vector2(spot.x - at.x, spot.z - at.z).length() < SPECTATOR_PERSON_METERS and spot.y > at.y - 0.2 and spot.y < at.y + 2.1:
				clear = minf(clear, (at - look).dot(out) - SPECTATOR_PERSON_METERS)
				_spec_why = "person %s" % node.name
	return maxf(clear, SPECTATOR_MIN_DISTANCE)


## A collider no wider than OCCLUDER_THIN_SPAN (a trunk, a post, a pole): it may
## cross the view, but the camera never sits in it.
static func _thin_collider(body: CollisionObject3D) -> bool:
	var shapes := body.find_children("*", "CollisionShape3D", false, false)
	if shapes.is_empty():
		return false
	var scale := body.global_basis.get_scale()
	for node: Node in shapes:
		if _shape_width((node as CollisionShape3D).shape) * maxf(scale.x, scale.z) >= OCCLUDER_THIN_SPAN:
			return false
	return true


## The one shape of body a ray hit (its shape index) is thin, though the body
## may hold wide ones too (the town's single static body).
static func _thin_hit_shape(body: CollisionObject3D, shape_index: int) -> bool:
	if shape_index < 0:
		return false
	var owner_id := body.shape_find_owner(shape_index)
	var owner := body.shape_owner_get_owner(owner_id) as CollisionShape3D
	if owner == null:
		return false
	var scale := owner.global_basis.get_scale()
	return _shape_width(owner.shape) * maxf(scale.x, scale.z) < OCCLUDER_THIN_SPAN


## A shape's width across (m, unscaled); INF for one we can't tell.
static func _shape_width(shape: Shape3D) -> float:
	if shape is CylinderShape3D:
		return (shape as CylinderShape3D).radius * 2.0
	if shape is CapsuleShape3D:
		return (shape as CapsuleShape3D).radius * 2.0
	if shape is SphereShape3D:
		return (shape as SphereShape3D).radius * 2.0
	if shape is BoxShape3D:
		return maxf((shape as BoxShape3D).size.x, (shape as BoxShape3D).size.z)
	return INF


## The drawn shapes near the subject, as boxes: trees, hedges, posts, fences,
## parked things. What moves (the Courtesy Shuttle's vans, Chefty) is kept as
## nodes and boxed every frame. People and props are left out.
func _refresh_occluders(center: Vector3) -> void:
	var now := Time.get_ticks_msec()
	# A van that just turned up (a new trip) counts at once.
	var trips := 0
	for shuttle: Node in get_tree().get_nodes_in_group("nice_shuttle"):
		trips += shuttle.get_child_count()
	if trips == _occluder_trips and now - _occluders_at_msec < int(OCCLUDER_REFRESH_SECONDS * 1000.0) and _occluders_center.is_finite() and _occluders_center.distance_to(center) < OCCLUDER_RADIUS * 0.5:
		return
	_occluder_trips = trips
	_occluders_at_msec = now
	_occluders_center = center
	_occluders.clear()
	_occluder_movers.clear()
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		return
	var started := Time.get_ticks_usec()
	# People and props aren't in the way; what moves is boxed every frame instead.
	var skip := {}
	for group: String in ["players", "crew", "props"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			for found: Node in node.find_children("*", "GeometryInstance3D", true, false):
				skip[found.get_instance_id()] = true
	# Each Courtesy Shuttle van (its Trip holder) and Chefty: one list of shapes each.
	var movers: Array[Node] = []
	for shuttle: Node in get_tree().get_nodes_in_group("nice_shuttle"):
		for child: Node in shuttle.get_children():
			if child is Node3D:
				movers.append(child)
	for truck: Node in get_tree().get_nodes_in_group("chefty"):
		movers.append(truck)
	for mover: Node in movers:
		var meshes: Array = []
		for found: Node in mover.find_children("*", "GeometryInstance3D", true, false):
			skip[found.get_instance_id()] = true
			if _occluder_kind(found):
				meshes.append(found)
		if not meshes.is_empty():
			_occluder_movers.append([mover, meshes])
	for found: Node in world.find_children("*", "GeometryInstance3D", true, false):
		if skip.has(found.get_instance_id()) or not _occluder_kind(found):
			continue
		var shape := found as GeometryInstance3D
		if shape.global_position.distance_to(center) > OCCLUDER_RADIUS + OCCLUDER_MAX_SPAN or not shape.is_visible_in_tree():
			continue
		if shape is MultiMeshInstance3D:
			_add_multimesh(shape as MultiMeshInstance3D, center)
		elif _is_tree_look(shape):
			_add_tree(shape, center)
		else:
			_add_box(shape.global_transform * shape.get_aabb(), center)
	var spent := float(Time.get_ticks_usec() - started) / 1000.0
	if spent > 30.0:
		print("[RemotePlay] spectator: %d shapes nearby took %.0f ms to gather" % [_occluders.size(), spent])


func _add_multimesh(shape: MultiMeshInstance3D, center: Vector3) -> void:
	var multimesh := shape.multimesh
	if multimesh == null or multimesh.mesh == null:
		return
	var count := multimesh.visible_instance_count if multimesh.visible_instance_count >= 0 else multimesh.instance_count
	if count > OCCLUDER_MULTIMESH_MAX:
		return
	var piece := multimesh.mesh.get_aabb()
	for index: int in count:
		_add_box(shape.global_transform * multimesh.get_instance_transform(index) * piece, center)


## A tree's drawn mesh (props/trees.gd: a "Look"/"LookFar" under a tree root).
static func _is_tree_look(shape: Node) -> bool:
	var root := shape.get_parent()
	return root != null and (shape.name == &"Look" or shape.name == &"LookFar") and "kind" in root and "crown" in root


## A tree is two boxes, its trunk and its crown, not one: a camera may sit under
## a crown or beside a trunk, never inside the leaves.
func _add_tree(shape: GeometryInstance3D, center: Vector3) -> void:
	var box := shape.global_transform * shape.get_aabb()
	if box.get_center().distance_to(center) > OCCLUDER_RADIUS:
		return
	var middle := box.get_center()
	var trunk := TREE_TRUNK_RADIUS * (shape.get_parent() as Node3D).global_basis.get_scale().x
	_occluders.append(AABB(Vector3(middle.x - trunk, box.position.y, middle.z - trunk), Vector3(trunk * 2.0, box.size.y * TREE_CROWN_FROM, trunk * 2.0)))
	var crown_bottom := box.position.y + box.size.y * TREE_CROWN_FROM
	var keep := Vector3(box.size.x * OCCLUDER_SHRINK, box.end.y - crown_bottom, box.size.z * OCCLUDER_SHRINK)
	_occluders.append(AABB(Vector3(middle.x - keep.x * 0.5, crown_bottom, middle.z - keep.z * 0.5), keep))


func _add_box(box: AABB, center: Vector3) -> void:
	var span := maxf(box.size.x, box.size.z)
	if span > OCCLUDER_MAX_SPAN or maxf(span, box.size.y) < OCCLUDER_MIN_SPAN or box.size.y < 0.25:
		return
	if box.get_center().distance_to(center) > OCCLUDER_RADIUS:
		return
	_occluders.append(_shrunk(box))


static func _occluder_kind(node: Node) -> bool:
	return node is MeshInstance3D or node is MultiMeshInstance3D


static func _shrunk(box: AABB) -> AABB:
	var keep := box.size * Vector3(OCCLUDER_SHRINK, 1.0, OCCLUDER_SHRINK)
	return AABB(box.get_center() - keep * 0.5, keep)


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
		"crew2", "crew3", "crew4":
			# One NICE BOY by name (van_straggler_far's straggler is Crew2).
			for each: Node in get_tree().get_nodes_in_group("crew"):
				if str(each.name).to_lower() == who:
					node = each
		"van":
			# The Courtesy Shuttle's van (net/run_events/shuttle.gd): the raid's, else any trip's.
			var shuttle := get_tree().get_first_node_in_group("nice_shuttle")
			if shuttle == null:
				return null
			var look := shuttle.call("van_look") as Node3D
			if look == null:
				for trip_id: Variant in shuttle.call("trip_ids"):
					var holder := shuttle.get_node_or_null("Trip%d" % int(trip_id)) as Node3D
					if holder != null and holder.visible:
						look = holder
			return look
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
	# R2c: the friend's window draws the observer as a ghost too (its takes had an
	# "Observer" tag hanging in the yard, and "[E] Grab Observer").
	if not Net.is_host() and Net.current_state() == Net.State.IN_SESSION:
		for peer_id: int in Net.peer_ids():
			if peer_id != Net.local_peer_id() and Net.player_name(peer_id) == OBSERVER_NAME:
				_ghost(_player_node(peer_id))
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
## it is never someone the NICE BOYS can take (the director's own safe list). It
## is a watcher (Net.set_watcher): left out of the zone rosters, so it never
## boards Chefty home, keeps a raid rolling or witnesses a long toss, and
## watching changes nothing it films. Riding (TRANSIT) or crossing (BORDER) the
## host leaves it at the store, as before: the Courtesy Shuttle and Annex B have
## rosters of their own. Not in the connected town, where zones follow where people stand.
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
		if not Net.is_watcher(peer_id):
			Net.set_watcher(peer_id, true)
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
		# The Gutter Shredder (driving G1): on the board, how fast, what the board is
		# doing, and the trick line up on screen ("until skate.on true" waits for it).
		if bool(player.get("on_board")) or bool(player.get("wipeout")):
			var popup := get_tree().get_first_node_in_group("trick_popup")
			var body := player as CharacterBody3D
			out["skate"] = {
				"on": bool(player.get("on_board")), "trick": int(player.get("skate_trick")),
				"wipeout": bool(player.get("wipeout")), "air": int(player.get("anim_state")) == 7,
				"speed": snappedf(Vector2(body.velocity.x, body.velocity.z).length(), 0.1),
				"line": str(popup.call("showing")) if popup != null else "",
			}
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
	# The connected town's streaming (driving chunk E): levels, builds, frames, draw calls.
	if get_tree().get_first_node_in_group("town_streamer") != null:
		var streamed: Dictionary = preload("res://levels/town/town_streamer.gd").stats
		out["streamer"] = {
			"lod": [streamed.get("chunks_lod0", 0), streamed.get("chunks_lod1", 0), streamed.get("chunks_skyline", 0)],
			"builds": streamed.get("builds", 0), "max_build_ms": snappedf(float(streamed.get("max_build_ms", 0.0)), 0.1),
			"max_frame_ms": snappedf(float(streamed.get("max_frame_ms", 0.0)), 0.1), "pending": streamed.get("pending", 0),
			"draw_calls": streamed.get("draw_calls", 0), "draw_calls_max": streamed.get("draw_calls_max", 0),
			"phase_ms": streamed.get("phase_ms", {}),
			"queue": preload("res://levels/build_queue.gd").stats.duplicate(),
		}
	# tools:crew: everyone else in the session, as this screen knows them (a crew
	# session's bots and the Friend), so a script can wait on a teammate.
	var others := {}
	for peer_id: int in Net.peer_ids():
		if peer_id == me or Net.player_name(peer_id) == OBSERVER_NAME:
			continue
		var body := _player_node(peer_id)
		var mate := {"zone": Net.Zone.keys()[Net.player_zone(peer_id)]}
		if body != null:
			mate["position"] = [snappedf(body.global_position.x, 0.1), snappedf(body.global_position.z, 0.1)]
			var their: Node = body.call("_held_prop") if body.has_method("_held_prop") else null
			mate["holding"] = str(their.get("kind")) if their != null else ""
		others[Net.player_name(peer_id)] = mate
	if not others.is_empty():
		out["crew"] = others
	var director := get_tree().get_first_node_in_group("run_director")
	if director != null and int(director.call("phase")) != 0:
		out["raid"] = ["QUIET", "WARNING", "CHASE", "DEPARTING"][clampi(int(director.call("phase")), 0, 3)]
		out["raid_status"] = str(director.call("status_line"))
	var annex := get_tree().get_first_node_in_group("annex")
	if annex != null and bool(annex.call("is_active")):
		out["annex"] = annex.call("status")
	# The music: its track, and while hiding is asking for the chase's "hide!"
	# section, whether the song is really playing inside it (R2c hide).
	var music := get_tree().get_first_node_in_group("music_director")
	if music != null and music.has_method("section_requested"):
		var song := {"track": str(music.get("_track"))}
		if bool(music.call("section_requested", &"hide")):
			song["hide"] = true
			var decks: Array = music.get("_decks")
			if not decks.is_empty():
				var deck: AudioStreamPlayer = (decks[int(music.get("_front"))] as Dictionary)["player"]
				var tracks := preload("res://audio/music_tracks.gd")
				var span: Array = tracks.section_seconds(str(song["track"]), "hide")
				var at := deck.get_playback_position() - tracks.lead_seconds(str(song["track"]))
				song["at"] = snappedf(at, 0.01)
				song["in_hide"] = span.size() >= 2 and at >= float(span[0]) - 0.05 and at <= float(span[1]) + 0.05
		out["music"] = song
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		out["camera"] = "%s/%s" % [camera.get_parent().name, camera.name] if camera.get_parent() != null else str(camera.name)
	out["xp"] = "%d banked, %d pending" % [Campaign.crew_xp(), Campaign.pending_xp()]
	return out
