extends Node

## Authority: host (and only local state). --settings-test checks the Settings
## autoload (core/settings.gd; gap-specs/settings.json chunk 1, adjusted by
## gap-specs/critic.md C2, C4 and C15):
##   path         this run uses settings_test_<port>.cfg, never the player's file
##   save_path    (save:guard) this dev run's campaign save is campaign_test_<port>.json;
##                a player's flags (--host --join= --name= --no-steam --town-map)
##                keep the real save and every other flag, --port= and unknown ones
##                included, makes a dev session; a dev session may never write the
##                real save, its .tmp or its .bak. (Engine flags Godot consumes, such
##                as --fixed-fps or --quit-after, never reach scripts and are not
##                detected: automated runs carry a dev user flag too.)
##   real_save    (save:guard, at the end) after a save_now() that lands in the test
##                save, the player's real campaign.json, its .bak and settings.cfg
##                have the same modified time and bytes as when the test began
##   buses        Master, Music, Sfx, Ambience, UI, Chatter and Voice exist and send right
##   defaults     preset high, 0.003 rad/px look, FOV 75 on both cameras, UI scale 1,
##                and the world's sun and ambient occlusion as shared_look.gd sets them
##   volumes      a volume sets its bus in decibels; 0 mutes it, 1 unmutes it
##   routing      bags play on Sfx, babble and the player's mouth on Chatter
##   look         sensitivity and invert Y turn mouse motion into yaw and pitch
##                (headless can't capture the mouse, so there the motion goes
##                straight into player._look and _unhandled_input isn't exercised;
##                a windowed run takes the real path)
##   fov          a new field of view reaches both cameras at once
##   bindings     rebinding, swapping on conflict, mouse and wheel bindings, the
##                wheel refused for held actions, pause never left unbound (also
##                when a reset strips it), per-slot labels, reset
##   toggle       toggle crouch latches on a press and off on the next
##   persistence  saved values and bindings come back on reload; unsaved ones don't,
##                and a persist-false value never reaches the file via another save
##   migration    an old file with only [audio] music keeps it, and gets a version
##   corrupt      an empty-parsing and an unparseable file both load defaults
##   interface    UI scale, caption size, voice mode, the music key, clamping, presets
##   window       the Settings window (settings:3, check 15): it opens and counts as
##                a window, all five tabs build, the Keys tab has a row per action
##                with a real name, a slot listens and takes a real key press (with
##                a swap and a stamp), Esc cancels listening and then closes, a
##                preset redraws the video controls, a new display mode reverts
##                unless kept, and opening from pause hides and restores the pause
##                buttons
##   strings      (settings:4, check 16) every string names keys with {key:<action>}
##                tokens of real actions and never hard-codes one ("left click",
##                "(Tab)", "E to ..."); keyed() leaves no token; every action has
##                a name; rebound keys show in the prompt, a phone line, the voice
##                panel and the goal line; the menu and signs read from Strings
##   captions     (settings:4) the quip caption and a homeowner's follow caption
##                size, backdrop and on/off (off still babbles); at 125% UI scale
##                the caption and the lobby stay on screen
## The checks for graphics (settings:2) join later. Each step prints a
## [SettingsTest] line.
## The test deletes its settings file at the start and the end.

const _Buses = preload("res://audio/buses.gd")
const _Bank = preload("res://audio/sound_bank.gd")
const _Strings = preload("res://ui/strings.gd")
const _InputLabels = preload("res://core/input_labels.gd")
const _Sfx = preload("res://audio/sfx.gd")
const _Prompt = preload("res://ui/interaction_prompt.gd")
const _Homeowner = preload("res://npcs/homeowner.gd")
const _QuipPlayer = preload("res://ui/quip_player.gd")
const _RunCues = preload("res://ui/run_cues.gd")
const _CommandLine = preload("res://net/command_line.gd")
const _Campaign = preload("res://net/campaign.gd")
## Flags a player launches with: a session with only these keeps the real save.
const PLAYER_ARG_SETS: Array = [
	[],
	["--host", "--name=Taylan", "--no-steam"],
	["--join=192.168.1.20", "--name=Deb", "--no-steam"],
	["--host", "--no-steam", "--town-map"],
]
## Each makes a dev session, alone or next to the player's flags (W6: driving:D's
## windowed runs wrote the real save with these).
const DEV_ARGS: Array[String] = [
	"--start-zone=lot", "--lot=2", "--job-seed=777", "--all-tasks", "--all-tools", "--rank=22",
	"--open-phone=map", "--screenshot=build/x", "--tour", "--bot", "--remote-play=build/play",
	"--scenario=caught", "--observer", "--fixed-step=30", "--smoke-test", "--smoke-client",
	"--run-seconds=30", "--measure=x.json", "--mute-audio", "--sim-lag=100", "--sim-loss=2",
	"--voice-test", "--hood=lakeside", "--yard-size=1", "--heat=40", "--start-hour=8",
	"--clock-scale=0.02", "--start-day=7", "--legacy-map", "--warp-rides", "--walk-straight",
	"--bot-stay", "--open-shop", "--open-board", "--open-settings=keys", "--end-day-at=20",
	"--ride-at=5", "--run-event-at=10", "--fill-pockets", "--drive-test", "--settings-test",
	"--playtest-tools-test", "--port=7777", "--port=9150", "--frobnicate",
]
const _CaptionStack = preload("res://ui/caption_stack.gd")
## Hard-coded key names a player-facing string may not carry (settings:4, check
## 16): "left click", "(Tab)", "Hold G", "E to ...", "A and D", "[E]". Keys are
## {key:<action>} tokens, so they follow rebinding.
const HARD_CODED_KEYS: Array[String] = [
	"(?i)\\b(left|right|middle) click\\b",
	"\\((Tab|Esc|Shift|Space|Ctrl|Enter|[A-WZ])\\)",
	"\\b(Hold|hold|Press|press|Tap|tap) (Tab|Esc|Shift|Space|Ctrl|Enter|[A-Z])\\b(?![a-z'])",
	"(^|[.:;!?] |\\(|\\s{2})(Tab|Esc|[A-Z])\\s+(to|at|and [A-Z]|steps|throws|take|stops)\\b",
	"\\[(Tab|Esc|Shift|Space|Ctrl|Enter|[A-Z])\\]",
]
## Strings that name keys on purpose: the key names themselves (input_labels'
## words), and the Keys tab's hint, whose Esc and Backspace are hard-wired.
const KEY_NAME_PATHS: Array[String] = ["UI/key_", "UI/keys_", "KEY_NAMES/"]
## How long the test waits for the session, the world and the player.
const START_TIMEOUT_SECONDS: float = 30.0
## How close a measured angle or volume has to be.
const ANGLE_EPSILON: float = 1e-4
const DB_EPSILON: float = 0.05

static var result: Dictionary = {}

var _started: bool = false
var _waited: float = 0.0
var _failed: Array[String] = []
var _checks: int = 0


func _process(delta: float) -> void:
	if _started or not Net.is_host():
		return
	_waited += delta
	var ready := Net.current_state() == Net.State.IN_SESSION and get_tree().get_first_node_in_group("world") != null and _me() != null
	if not ready:
		if _waited > START_TIMEOUT_SECONDS:
			_started = true
			_failed.append("start: no session, world or local player after %d s" % int(START_TIMEOUT_SECONDS))
			_finish()
		return
	_started = true
	_run()


func _run() -> void:
	await get_tree().create_timer(0.5).timeout
	var me := _me()
	var defaults := _snapshot_bindings()
	var real_before := _real_files()
	_wipe()
	_check("path", _path())
	_check("save_path", _save_path())
	_check("buses", _buses())
	_check("defaults", _defaults(me))
	_check("volumes", _volumes())
	_check("routing", _routing(me))
	_check("look", await _look(me))
	_check("fov", _fov(me))
	_check("bindings", _bindings(defaults))
	_check("toggle", await _toggle())
	_check("persistence", _persistence())
	_check("migration", _migration())
	_check("corrupt", _corrupt(defaults))
	_check("interface", _interface())
	_check("window", await _window())
	_check("strings", await _strings())
	_check("captions", await _captions())
	_wipe()
	_check("real_save", _real_save(real_before))
	_finish()


func _check(check_name: String, ok: bool) -> void:
	_checks += 1
	print("[SettingsTest] %s: %s" % [check_name, ok])
	if not ok and not _failed.any(func(line: String) -> bool: return line.begins_with(check_name)):
		_failed.append(check_name)


func _fail(check_name: String, why: String) -> bool:
	_failed.append("%s: %s" % [check_name, why])
	print("[SettingsTest] %s FAILED: %s" % [check_name, why])
	return false


func _finish() -> void:
	result = {"ok": _failed.is_empty(), "checks": _checks, "failed": _failed.duplicate(), "done": true}
	print("[SettingsTest] done, ok=%s, %d checks, failed %s" % [result["ok"], _checks, _failed])


## A clean slate: no file, defaults loaded, nothing waiting to be saved.
func _wipe() -> void:
	if FileAccess.file_exists(Settings.path()):
		DirAccess.remove_absolute(Settings.path())
	Settings.reload()


# ---------------------------------------------------------------- checks

func _path() -> bool:
	var want := "settings_test_%d.cfg" % int(Net.dev_options().get("port"))
	if not Settings.path().ends_with(want):
		return _fail("path", "%s does not end with %s" % [Settings.path(), want])
	return true


func _save_path() -> bool:
	var want := _Campaign.TEST_SAVE_PATH % int(Net.dev_options().get("port"))
	if Campaign.save_path() != want:
		return _fail("save_path", "this run saves to %s, not %s" % [Campaign.save_path(), want])
	if not bool(Net.dev_options().call("is_dev_session")):
		return _fail("save_path", "a --settings-test run is not a dev session")
	if _Campaign.resolve_save_path(false, false, Constants.DEFAULT_PORT) != _Campaign.SAVE_PATH:
		return _fail("save_path", "a player's session does not get the real save")
	if _Campaign.resolve_save_path(true, false, 7777) != _Campaign.DEV_SAVE_PATH:
		return _fail("save_path", "a dev session without --port does not get campaign_dev.json")
	for args: Array in PLAYER_ARG_SETS:
		var line := _CommandLine.new()
		line.parse(PackedStringArray(args))
		if not line.dev_flags.is_empty():
			return _fail("save_path", "player flags %s count as dev flags %s" % [args, line.dev_flags])
	for flag: String in DEV_ARGS:
		for base: Array in PLAYER_ARG_SETS:
			var line := _CommandLine.new()
			line.parse(PackedStringArray(base + [flag]))
			if not line.dev_flags.has(flag):
				return _fail("save_path", "%s next to %s is not a dev flag" % [flag, base])
	var real := _Campaign.SAVE_PATH
	for path: String in [real, real + ".tmp", real + ".bak", ProjectSettings.globalize_path(real)]:
		if not _Campaign.write_forbidden(path, true):
			return _fail("save_path", "a dev session may write %s" % path)
	if _Campaign.write_forbidden(want, true) or _Campaign.write_forbidden(_Campaign.DEV_SAVE_PATH, true):
		return _fail("save_path", "a dev session may not write its own test save")
	if _Campaign.write_forbidden(real, false):
		return _fail("save_path", "a player's session may not write the real save")
	return true


## The player's real files: whether each exists, and its modified time and MD5.
func _real_files() -> Dictionary:
	var files := {}
	for path: String in [_Campaign.SAVE_PATH, _Campaign.SAVE_PATH + ".bak", Settings.REAL_PATH]:
		var exists := FileAccess.file_exists(path)
		files[path] = [exists, FileAccess.get_modified_time(path) if exists else 0, FileAccess.get_md5(path) if exists else ""]
	return files


func _real_save(before: Dictionary) -> bool:
	Campaign.save_now()
	if not FileAccess.file_exists(Campaign.save_path()):
		return _fail("real_save", "save_now() wrote nothing to %s" % Campaign.save_path())
	var after := _real_files()
	for path: String in before:
		if str(before[path]) != str(after[path]):
			return _fail("real_save", "%s changed during a dev run: %s -> %s" % [path, before[path], after[path]])
	return true


func _buses() -> bool:
	for bus: StringName in [_Buses.MASTER, _Buses.MUSIC, _Buses.SFX, _Buses.AMBIENCE, _Buses.UI, _Buses.CHATTER, _Buses.VOICE]:
		if AudioServer.get_bus_index(bus) < 0:
			return _fail("buses", "no %s bus" % bus)
	for entry: Array in _Buses.LAYOUT:
		var send := AudioServer.get_bus_send(AudioServer.get_bus_index(entry[0]))
		if send != entry[1]:
			return _fail("buses", "%s sends to %s, not %s" % [entry[0], send, entry[1]])
	return true


func _defaults(me: Node3D) -> bool:
	var ok := true
	if str(Settings.get_value("video", "preset")) != "high":
		ok = _fail("defaults", "preset is %s" % Settings.get_value("video", "preset"))
	if not Settings.look_scale().is_equal_approx(Vector2(0.003, 0.003)):
		ok = _fail("defaults", "look scale %s" % Settings.look_scale())
	for camera: Camera3D in _cameras(me):
		if not is_equal_approx(camera.fov, 75.0):
			ok = _fail("defaults", "%s fov %.1f" % [camera.name, camera.fov])
	if _cameras(me).size() != 2:
		ok = _fail("defaults", "found %d player cameras, not 2" % _cameras(me).size())
	if not is_equal_approx(get_tree().root.content_scale_factor, 1.0):
		ok = _fail("defaults", "UI scale %.2f" % get_tree().root.content_scale_factor)
	var world := get_tree().get_first_node_in_group("world")
	var sun := world.get_node_or_null("Sun") as DirectionalLight3D
	if sun == null or not sun.shadow_enabled or not is_equal_approx(sun.directional_shadow_max_distance, 90.0):
		ok = _fail("defaults", "the sun's shadows aren't shared_look's (on, 90 m)")
	var environment := world.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if environment == null or environment.environment == null or not environment.environment.ssao_enabled:
		ok = _fail("defaults", "ambient occlusion isn't on")
	return ok


func _volumes() -> bool:
	var ok := true
	var sfx := AudioServer.get_bus_index(_Buses.SFX)
	var music := AudioServer.get_bus_index(_Buses.MUSIC)
	var ambience := AudioServer.get_bus_index(_Buses.AMBIENCE)
	Settings.set_value("audio", "sfx_volume", 0.5, false)
	if absf(AudioServer.get_bus_volume_db(sfx) - (-6.02)) > DB_EPSILON:
		ok = _fail("volumes", "Sfx at half is %.2f dB" % AudioServer.get_bus_volume_db(sfx))
	Settings.set_value("audio", "ambience_volume", 0.25, false)
	if absf(AudioServer.get_bus_volume_db(ambience) - (-12.04)) > DB_EPSILON:
		ok = _fail("volumes", "Ambience at a quarter is %.2f dB" % AudioServer.get_bus_volume_db(ambience))
	Settings.set_value("audio", "music_volume", 0.0, false)
	if not AudioServer.is_bus_mute(music):
		ok = _fail("volumes", "Music at 0 isn't muted")
	Settings.set_value("audio", "music_volume", 1.0, false)
	if AudioServer.is_bus_mute(music) or absf(AudioServer.get_bus_volume_db(music)) > DB_EPSILON:
		ok = _fail("volumes", "Music back at 1 is muted or not 0 dB")
	Settings.reset_section("audio")
	if absf(AudioServer.get_bus_volume_db(sfx)) > DB_EPSILON:
		ok = _fail("volumes", "reset left Sfx at %.2f dB" % AudioServer.get_bus_volume_db(sfx))
	return ok


func _routing(me: Node3D) -> bool:
	var ok := true
	if _Bank.bus("bag") != _Buses.SFX:
		ok = _fail("routing", "bag plays on %s" % _Bank.bus("bag"))
	if _Bank.bus("babble") != _Buses.CHATTER:
		ok = _fail("routing", "babble plays on %s" % _Bank.bus("babble"))
	me.call("say", "vo_yelp")
	var mouth := me.get_node_or_null("Visual/Head/Mouth") as AudioStreamPlayer3D
	if mouth == null or mouth.bus != _Buses.CHATTER:
		ok = _fail("routing", "the mouth is %s" % ("missing" if mouth == null else "on " + mouth.bus))
	# A remote player's voice, when there is one (host-only runs have none).
	for node: Node in get_tree().get_nodes_in_group("players"):
		var voice := node.get_node_or_null("Visual/Head/Voice") as AudioStreamPlayer3D
		if node != me and voice != null and voice.bus != _Buses.VOICE:
			ok = _fail("routing", "%s's voice is on %s" % [node.name, voice.bus])
	return ok


func _look(me: Node3D) -> bool:
	var ok := true
	Settings.set_value("controls", "sensitivity", 2.0, false)
	Settings.set_value("controls", "invert_y", true, false)
	var turn := await _turn(me)
	if absf(turn.x - (-0.06)) > ANGLE_EPSILON or absf(turn.y - 0.06) > ANGLE_EPSILON:
		ok = _fail("look", "2x inverted turned yaw %.5f, pitch %.5f (want -0.06, +0.06)" % [turn.x, turn.y])
	Settings.set_value("controls", "invert_y", false, false)
	turn = await _turn(me)
	if absf(turn.y - (-0.06)) > ANGLE_EPSILON:
		ok = _fail("look", "2x pitch %.5f (want -0.06)" % turn.y)
	Settings.reset_section("controls")
	me.set("head_pitch", 0.0)
	return ok


## Feeds 10 px of mouse motion right and down, and returns (yaw, pitch) turned.
func _turn(me: Node3D) -> Vector2:
	me.set("head_pitch", 0.0)
	await get_tree().physics_frame
	var yaw := float(me.get("body_yaw"))
	var pitch := float(me.get("head_pitch"))
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(10.0, 10.0)
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		me.call("_unhandled_input", motion)
	else:
		# Headless has no mouse to capture; hand the motion straight to the look.
		me.set("_look", motion.relative)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	return Vector2(float(me.get("body_yaw")) - yaw, float(me.get("head_pitch")) - pitch)


func _fov(me: Node3D) -> bool:
	var ok := true
	Settings.set_value("controls", "fov", 90.0, false)
	for camera: Camera3D in _cameras(me):
		if not is_equal_approx(camera.fov, 90.0):
			ok = _fail("fov", "%s fov %.1f after setting 90" % [camera.name, camera.fov])
	Settings.reset_section("controls")
	for camera: Camera3D in _cameras(me):
		if not is_equal_approx(camera.fov, 75.0):
			ok = _fail("fov", "%s fov %.1f after reset" % [camera.name, camera.fov])
	return ok


func _bindings(defaults: Dictionary) -> bool:
	var ok := true
	var r := Settings.bind(&"interact", 0, "key:R")
	var codes := _codes(&"interact")
	if not bool(r["ok"]) or not codes.has("key:%d" % KEY_R) or codes.has("key:%d" % KEY_E):
		ok = _fail("bindings", "interact after binding R: %s %s" % [r, codes])
	if not InputMap.event_is_action(_key_event(KEY_R), &"interact"):
		ok = _fail("bindings", "an R press isn't interact")
	if _Strings.keyed("{key:interact}") != "[R]" or _Strings.keyed("Press {key:interact} {icon:hand}now") != "Press [R] now":
		ok = _fail("bindings", "keyed gives %s" % _Strings.keyed("{key:interact}"))
	# The floating prompt names the player's key, and a hint's own "key" (critic C8).
	var hide_text := str(_Strings.UI["prompt_hide"])
	var prompt := _Prompt.text_for({"text": hide_text})
	var take_prompt := _Prompt.text_for({"text": hide_text, "key": "take"})
	# A plain line with a key in it (hud_hidden, which this used, went with R2 chunk 3).
	var hidden := "Hold {key:interact}"
	var plain := _Prompt.text_for({"text": hidden, "plain": true})
	if prompt != "[R]  " + hide_text or take_prompt != "[F]  " + hide_text or plain != hidden.replace("{key:interact}", "[R]") or plain == hidden:
		ok = _fail("bindings", "prompts read '%s', '%s', '%s'" % [prompt, take_prompt, plain])
	print("[SettingsTest] with interact on R the prompt reads '%s'" % prompt)
	r = Settings.bind(&"interact", 0, "key:F")
	if not bool(r["ok"]) or str(r["swapped_with"]) != "take" or str(r["notice"]) == "" or Settings.binding(&"take", 0) != "key:%d" % KEY_R or Settings.binding(&"interact", 0) != "key:%d" % KEY_F:
		ok = _fail("bindings", "F swap: %s, take %s, interact %s" % [r, Settings.binding(&"take", 0), Settings.binding(&"interact", 0)])
	print("[SettingsTest] swap notice: %s" % r["notice"])
	r = Settings.bind(&"jump", 1, "mouse:%d" % MOUSE_BUTTON_XBUTTON1)
	if not bool(r["ok"]) or not InputMap.event_is_action(_mouse_event(MOUSE_BUTTON_XBUTTON1), &"jump"):
		ok = _fail("bindings", "Mouse 4 to jump: %s" % r)
	# Wheel up may already be another action's (hotbar's slot_prev, critic C15): then it swaps.
	r = Settings.bind(&"toggle_camera", 1, "mouse:%d" % MOUSE_BUTTON_WHEEL_UP)
	var wheel := "mouse:%d" % MOUSE_BUTTON_WHEEL_UP
	if not bool(r["ok"]) or Settings.binding(&"toggle_camera", 1) != wheel:
		ok = _fail("bindings", "wheel up to the camera: %s" % r)
	elif str(r["swapped_with"]) != "" and _codes(StringName(str(r["swapped_with"]))).has(wheel):
		ok = _fail("bindings", "%s kept wheel up after the swap" % r["swapped_with"])
	var sprint_before := _codes(&"sprint")
	r = Settings.bind(&"sprint", 0, "mouse:%d" % MOUSE_BUTTON_WHEEL_DOWN)
	if bool(r["ok"]) or str(r["notice"]) == "" or _codes(&"sprint") != sprint_before:
		ok = _fail("bindings", "the wheel bound sprint: %s" % r)
	# An explicit slot's label is that Settings slot, even with slot 0 emptied.
	Settings.clear_binding(&"jump", 0)
	var mouse_4 := _InputLabels.event_label(_mouse_event(MOUSE_BUTTON_XBUTTON1))
	if _InputLabels.label(&"jump", 0) != _Strings.UI["key_unbound"] or _InputLabels.label(&"jump", 1) != mouse_4 or Settings.key_label(&"jump", 1) != mouse_4 or _InputLabels.label(&"jump") != mouse_4:
		ok = _fail("bindings", "jump labels: slot 0 %s, slot 1 %s, first %s" % [_InputLabels.label(&"jump", 0), _InputLabels.label(&"jump", 1), _InputLabels.label(&"jump")])
	r = Settings.clear_binding(&"pause", 0)
	if bool(r["ok"]) or Settings.binding(&"pause", 0) == "":
		ok = _fail("bindings", "pause lost its last key: %s" % r)
	# Pause gets its default back when a reset strips it, and that key leaves
	# whoever had taken it, so no key is on two actions.
	Settings.reset_bindings()
	var escape := Settings.default_binding(&"pause", 0)
	Settings.bind(&"pause", 0, "key:%d" % KEY_E)
	Settings.bind(&"take", 0, escape)
	Settings.reset_action(&"interact")
	var shared := _shared_codes()
	if Settings.binding(&"pause", 0) != escape or not shared.is_empty() or InputMap.event_is_action(Settings.code_to_event(escape), &"take"):
		ok = _fail("bindings", "after the pause reset: pause %s, take %s, shared %s" % [Settings.binding(&"pause", 0), Settings.binding(&"take", 0), shared])
	print("[SettingsTest] interact reads %s, take %s; refusals: %s" % [Settings.key_label(&"interact"), Settings.key_label(&"take"), r["notice"]])
	Settings.reset_bindings()
	if Settings.binding(&"interact", 0) != "key:%d" % KEY_E or Settings.binding(&"take", 0) != "key:%d" % KEY_F:
		ok = _fail("bindings", "reset left interact %s, take %s" % [Settings.binding(&"interact", 0), Settings.binding(&"take", 0)])
	var now := _snapshot_bindings()
	if now != defaults:
		ok = _fail("bindings", "after reset the InputMap differs from the project's")
	if Settings.rebindable_actions().size() < 18 or Settings.rebindable_actions().any(func(a: StringName) -> bool: return String(a).begins_with("ui_")):
		ok = _fail("bindings", "rebindable actions: %s" % [Settings.rebindable_actions()])
	return ok


func _toggle() -> bool:
	var ok := true
	Settings.set_value("controls", "toggle_crouch", true, false)
	await _press(&"crouch", true)
	await _press(&"crouch", false)
	if not Settings.is_held(&"crouch"):
		ok = _fail("toggle", "one tap didn't latch crouch")
	await _press(&"crouch", true)
	await _press(&"crouch", false)
	if Settings.is_held(&"crouch"):
		ok = _fail("toggle", "a second tap didn't let go")
	Settings.set_value("controls", "toggle_crouch", false, false)
	Input.action_press(&"crouch")
	var held := Settings.is_held(&"crouch")
	Input.action_release(&"crouch")
	if not held or Settings.is_held(&"crouch"):
		ok = _fail("toggle", "hold mode doesn't follow the key")
	if Settings.is_held(&"sprint"):
		ok = _fail("toggle", "sprint is held with nothing pressed")
	Settings.reset_section("controls")
	return ok


func _persistence() -> bool:
	var ok := true
	Settings.set_value("controls", "sensitivity", 1.7)
	Settings.bind(&"interact", 0, "key:R")
	if Settings.save_now() != OK:
		return _fail("persistence", "save failed")
	var file := ConfigFile.new()
	if file.load(Settings.path()) != OK:
		return _fail("persistence", "the saved file doesn't load")
	var saved_keys: Variant = file.get_value("keys", "interact", PackedStringArray())
	if not is_equal_approx(float(file.get_value("controls", "sensitivity", 0.0)), 1.7) or saved_keys.size() < 1 or str(saved_keys[0]) != "key:82":
		ok = _fail("persistence", "file has sensitivity %s, interact %s" % [file.get_value("controls", "sensitivity", null), saved_keys])
	if file.has_section_key("keys", "take"):
		ok = _fail("persistence", "an untouched action was written")
	# A value set with persist false stays out of the file, even when another
	# key's save writes it (a slider preview, a display mode awaiting "Keep").
	Settings.set_value("controls", "fov", 90.0, false)
	Settings.set_value("video", "shadows", 2, false)
	Settings.set_value("controls", "invert_y", true)
	Settings.save_now()
	file = ConfigFile.new()
	file.load(Settings.path())
	if not is_equal_approx(float(file.get_value("controls", "fov", 0.0)), Constants.FOV_DEFAULT) or int(file.get_value("video", "shadows", -1)) != 3 or str(file.get_value("video", "preset", "")) != "high" or not bool(file.get_value("controls", "invert_y", false)):
		ok = _fail("persistence", "a transient value reached the file: fov %s, shadows %s, preset %s, invert %s" % [file.get_value("controls", "fov", null), file.get_value("video", "shadows", null), file.get_value("video", "preset", null), file.get_value("controls", "invert_y", null)])
	if not is_equal_approx(Settings.fov(), 90.0) or not is_equal_approx(float(Settings.saved_value("controls", "fov")), Constants.FOV_DEFAULT) or str(Settings.get_value("video", "preset")) != "custom":
		ok = _fail("persistence", "live fov %s, saved fov %s, live preset %s" % [Settings.fov(), Settings.saved_value("controls", "fov"), Settings.get_value("video", "preset")])
	Settings.set_value("controls", "fov", 90.0)
	Settings.save_now()
	file = ConfigFile.new()
	file.load(Settings.path())
	if not is_equal_approx(float(file.get_value("controls", "fov", 0.0)), 90.0):
		ok = _fail("persistence", "fov set again with persist didn't save: %s" % file.get_value("controls", "fov", null))
	Settings.set_value("controls", "sensitivity", 0.5, false)
	Settings.bind(&"interact", 0, "key:%d" % KEY_T)
	Settings.reload()
	if not is_equal_approx(float(Settings.get_value("controls", "sensitivity")), 1.7):
		ok = _fail("persistence", "reload gave sensitivity %s" % Settings.get_value("controls", "sensitivity"))
	if not InputMap.event_is_action(_key_event(KEY_R), &"interact") or InputMap.event_is_action(_key_event(KEY_T), &"interact"):
		ok = _fail("persistence", "reload didn't bring R back to interact")
	Settings.reset_bindings()
	Settings.reset_section("controls")
	Settings.reset_section("video")
	Settings.save_now()
	return ok


func _migration() -> bool:
	var ok := true
	Settings.save_now()
	_write("[audio]\nmusic=false\n")
	Settings.reload()
	if bool(Settings.get_value("audio", "music")) or not is_equal_approx(float(Settings.get_value("controls", "sensitivity")), 1.0):
		ok = _fail("migration", "music %s, sensitivity %s" % [Settings.get_value("audio", "music"), Settings.get_value("controls", "sensitivity")])
	Settings.save_now()
	var file := ConfigFile.new()
	file.load(Settings.path())
	if int(file.get_value("meta", "version", 0)) != Settings.FILE_VERSION or bool(file.get_value("audio", "music", true)):
		ok = _fail("migration", "the next save has version %s, music %s" % [file.get_value("meta", "version", null), file.get_value("audio", "music", null)])
	Settings.reset_section("audio")
	return ok


func _corrupt(defaults: Dictionary) -> bool:
	var ok := true
	Settings.save_now()
	# ConfigFile reads "garbage{{" as an empty file: defaults by the normal path.
	_write("garbage{{")
	Settings.reload()
	if not bool(Settings.get_value("audio", "music")) or str(Settings.get_value("video", "preset")) != "high" or _snapshot_bindings() != defaults:
		ok = _fail("corrupt", "a garbage file didn't give defaults")
	# This one fails to parse, so it takes the unreadable-file path, and the
	# sensitivity before the bad line must not leak through.
	# The engine logs ConfigFile's parse error (twice: the probe and the reload) to
	# stderr, where ci_local shows it as if something broke; it's this step's
	# point, so it's muted for these two loads only (fx-net).
	_write("[controls]\nsensitivity=2.0\n[audio]\nmusic=@@@\n")
	var printing := Engine.print_error_messages
	Engine.print_error_messages = false
	var probe := ConfigFile.new()
	var parsed := probe.load(Settings.path())
	Settings.reload()
	Engine.print_error_messages = printing
	if parsed == OK:
		ok = _fail("corrupt", "the unparseable file parsed, so the unreadable path isn't tested")
	if not bool(Settings.get_value("audio", "music")) or not is_equal_approx(float(Settings.get_value("controls", "sensitivity")), 1.0) or _snapshot_bindings() != defaults:
		ok = _fail("corrupt", "an unparseable file gave music %s, sensitivity %s" % [Settings.get_value("audio", "music"), Settings.get_value("controls", "sensitivity")])
	return ok


func _interface() -> bool:
	var ok := true
	Settings.set_value("interface", "ui_scale", 1.25, false)
	if not is_equal_approx(get_tree().root.content_scale_factor, 1.25):
		ok = _fail("interface", "UI scale 1.25 gave %.2f" % get_tree().root.content_scale_factor)
	Settings.set_value("interface", "caption_size", 2, false)
	if not is_equal_approx(Settings.caption_scale(), 1.3):
		ok = _fail("interface", "large captions scale %.2f" % Settings.caption_scale())
	Settings.reset_section("interface")
	if not is_equal_approx(get_tree().root.content_scale_factor, 1.0):
		ok = _fail("interface", "reset UI scale is %.2f" % get_tree().root.content_scale_factor)
	Settings.set_value("audio", "voice_mode", int(Net.VoiceMode.VOICE_ACTIVATION), false)
	if Net.voice_mode() != Net.VoiceMode.VOICE_ACTIVATION:
		ok = _fail("interface", "voice mode didn't reach Net")
	Settings.set_value("audio", "voice_mode", int(Net.VoiceMode.PUSH_TO_TALK), false)
	# Out of range clamps; a bad type keeps the default.
	Settings.set_value("controls", "fov", 500.0, false)
	Settings.set_value("controls", "sensitivity", -3.0, false)
	Settings.set_value("video", "shadows", "lots", false)
	if not is_equal_approx(Settings.fov(), Constants.FOV_RANGE.y) or not is_equal_approx(float(Settings.get_value("controls", "sensitivity")), Constants.SENSITIVITY_RANGE.x) or int(Settings.get_value("video", "shadows")) != 3:
		ok = _fail("interface", "clamping: fov %s, sensitivity %s, shadows %s" % [Settings.fov(), Settings.get_value("controls", "sensitivity"), Settings.get_value("video", "shadows")])
	# Presets: one hand-changed option makes it custom; a preset writes its keys.
	Settings.set_value("video", "shadows", 2, false)
	var custom := str(Settings.get_value("video", "preset")) == "custom"
	Settings.apply_preset("low")
	var low := str(Settings.get_value("video", "preset")) == "low" and int(Settings.get_value("video", "shadows")) == 1 and not bool(Settings.get_value("video", "ssao"))
	Settings.apply_preset("high")
	var high := str(Settings.get_value("video", "preset")) == "high" and int(Settings.get_value("video", "shadows")) == 3 and bool(Settings.get_value("video", "ssao"))
	if not (custom and low and high):
		ok = _fail("interface", "presets: custom %s, low %s, high %s" % [custom, low, high])
	Settings.reset_section("controls")
	Settings.reset_section("video")
	return ok


func _window() -> bool:
	var ok := true
	var ui := get_tree().get_first_node_in_group("game_ui")
	var window := get_tree().get_first_node_in_group("settings_window") as Control
	if ui == null or window == null:
		return _fail("window", "no game UI or no settings window")
	ui.call("open_settings")
	await get_tree().process_frame
	if not window.visible or not bool(ui.call("any_window_open")):
		ok = _fail("window", "open_settings: visible %s, any_window_open %s" % [window.visible, ui.call("any_window_open")])
	# Keyboard focus moves onto the form, and game keys stop at it: the world
	# behind (the clerk, the board, a zone gate, the camera) hears nothing.
	if not bool(window.call("_focus_inside")):
		ok = _fail("window", "open left keyboard focus on %s" % get_viewport().gui_get_focus_owner())
	var ear := _Ear.new()
	add_child(ear)
	await _key(KEY_E)
	await _key(KEY_J)
	var heard_open := ear.heard
	ui.call("close_settings")
	await _key(KEY_J)
	var heard_closed := ear.heard - heard_open
	ear.queue_free()
	if heard_open != 0 or heard_closed != 1:
		ok = _fail("window", "behind the open window the world heard %d keys (closed: %d)" % [heard_open, heard_closed])
	ui.call("open_settings")
	await get_tree().process_frame
	var tabs: Array = window.get("TABS")
	if tabs.size() != 5:
		ok = _fail("window", "%d tabs, not 5" % tabs.size())
	for tab: String in tabs:
		window.call("show_tab", tab)
		if str(window.call("current_tab")) != tab or int(window.call("row_count")) == 0:
			ok = _fail("window", "tab %s: current %s, %d rows" % [tab, window.call("current_tab"), window.call("row_count")])
	# The Keys tab: one row per rebindable action, each with its own name.
	window.call("show_tab", "keys")
	var actions := Settings.rebindable_actions()
	var labels: PackedStringArray = window.call("row_labels")
	if labels.size() != actions.size():
		ok = _fail("window", "the Keys tab has %d rows for %d actions" % [labels.size(), actions.size()])
	for action: StringName in actions:
		if not _Strings.UI.has("action_%s" % action) or not labels.has(str(_Strings.UI["action_%s" % action])):
			ok = _fail("window", "no named row for %s" % action)
	for label: String in labels:
		if label.begins_with("action_"):
			ok = _fail("window", "row label %s is a missing string" % label)
	print("[SettingsTest] the Keys tab lists %d actions" % labels.size())
	# Listening: a real G press goes to interact, and drop (G) gets interact's old key.
	var interact_old := Settings.binding(&"interact", 0)
	var drop_old := Settings.binding(&"drop", 0)
	window.call("listen", &"interact", 0)
	if not bool(window.call("is_listening")) or str(window.call("binding_text", &"interact", 0)) != _Strings.UI["keys_listening"]:
		ok = _fail("window", "listen didn't wait for a key")
	var stamps := _Sfx.log.count("ui_stamp")
	await _key(KEY_G)
	var g_text := _InputLabels.event_label(_key_event(KEY_G))
	if drop_old != "key:%d" % KEY_G or Settings.binding(&"interact", 0) != drop_old or Settings.binding(&"drop", 0) != interact_old:
		ok = _fail("window", "G while listening: interact %s, drop %s (was %s, %s)" % [Settings.binding(&"interact", 0), Settings.binding(&"drop", 0), interact_old, drop_old])
	if bool(window.call("is_listening")) or str(window.call("binding_text", &"interact", 0)) != g_text or str(window.call("binding_text", &"drop", 0)) != _InputLabels.event_label(Settings.code_to_event(interact_old)):
		ok = _fail("window", "after G the slots read %s and %s" % [window.call("binding_text", &"interact", 0), window.call("binding_text", &"drop", 0)])
	if _Sfx.log.count("ui_stamp") <= stamps:
		ok = _fail("window", "no stamp for the new binding")
	print("[SettingsTest] the footer says: %s" % (window.get("_notice") as Label).text)
	# A left click away from the waiting slot cancels; one on the slot binds Left click.
	var before_click := _snapshot_bindings()
	window.call("listen", &"interact", 1)
	await _click(Vector2(2.0, 2.0))
	if bool(window.call("is_listening")) or _snapshot_bindings() != before_click or not window.visible:
		ok = _fail("window", "a click away: listening %s, bindings changed %s" % [window.call("is_listening"), _snapshot_bindings() != before_click])
	window.call("listen", &"interact", 1)
	for frame: int in 3:
		await get_tree().process_frame
	var card := (window.get("_slots") as Dictionary)["interact/1"] as Control
	# Input arrives in window pixels; the stretch transform takes it to the canvas.
	var on_card := get_viewport().get_final_transform() * (card.get_global_transform_with_canvas() * (card.size * 0.5))
	await _click(on_card)
	var left_code := Settings.event_to_code(_mouse_event(MOUSE_BUTTON_LEFT))
	if bool(window.call("is_listening")) or Settings.binding(&"interact", 1) != left_code:
		ok = _fail("window", "a click on the waiting slot: listening %s, interact/1 is %s" % [window.call("is_listening"), Settings.binding(&"interact", 1)])
	Settings.reset_bindings()
	# Esc while listening cancels, and changes nothing; Esc again closes.
	var before := _snapshot_bindings()
	window.call("listen", &"interact", 1)
	await _key(KEY_ESCAPE)
	if bool(window.call("is_listening")) or _snapshot_bindings() != before or not window.visible:
		ok = _fail("window", "Esc while listening: listening %s, window %s, bindings changed %s" % [window.call("is_listening"), window.visible, _snapshot_bindings() != before])
	await _key(KEY_ESCAPE)
	if window.visible or bool(ui.call("any_window_open")):
		ok = _fail("window", "a second Esc left the window open")
	Settings.reset_bindings()
	# A preset moves every video control; a new display mode waits for Keep.
	ui.call("open_settings", false, "video")
	Settings.apply_preset("low")
	var rows: Dictionary = window.get("_rows")
	if (rows["video/shadows"]["control"] as OptionButton).selected != 1 or (rows["video/preset"]["control"] as OptionButton).selected != 0 or (rows["video/ssao"]["control"] as CheckButton).button_pressed:
		ok = _fail("window", "the low preset didn't redraw the video tab")
	Settings.apply_preset("high")
	if (rows["video/shadows"]["control"] as OptionButton).selected != 3 or not (rows["video/ssao"]["control"] as CheckButton).button_pressed:
		ok = _fail("window", "the high preset didn't redraw the video tab")
	window.call("_choose", "video", "window_mode", 1)
	var waiting := int(Settings.get_value("video", "window_mode")) == 1 and int(Settings.saved_value("video", "window_mode")) == 0 and (window.get("_keep") as Button).visible
	window.call("_revert_display")
	var reverted := int(Settings.get_value("video", "window_mode")) == 0 and not (window.get("_keep") as Button).visible
	window.call("_choose", "video", "window_mode", 1)
	window.call("_keep_display")
	var kept := int(Settings.saved_value("video", "window_mode")) == 1
	if not (waiting and reverted and kept):
		ok = _fail("window", "display revert: waiting %s, reverted %s, kept %s" % [waiting, reverted, kept])
	Settings.reset_section("video")
	# Nobody presses Keep: the countdown runs out and the mode goes back.
	var saved_mode := int(Settings.saved_value("video", "window_mode"))
	window.call("_choose", "video", "window_mode", 1)
	window.set("_revert_left", 0.05)
	await get_tree().create_timer(0.25).timeout
	await get_tree().process_frame
	var timed_out := int(Settings.get_value("video", "window_mode")) == saved_mode and not (window.get("_keep") as Button).visible
	# Closing the form while a mode waits is not a keep either.
	window.call("_choose", "video", "window_mode", 1)
	ui.call("close_settings")
	var closed_reverted := int(Settings.get_value("video", "window_mode")) == saved_mode and int(Settings.saved_value("video", "window_mode")) == saved_mode and not (window.get("_keep") as Button).visible
	if not (timed_out and closed_reverted):
		ok = _fail("window", "display revert by itself: countdown %s, on close %s" % [timed_out, closed_reverted])
	# From pause: the pause buttons step aside, and come back on close.
	ui.call("open_pause")
	var leave := ui.get("_leave") as Button
	var settings_button := ui.get("_settings_button") as Button
	if not settings_button.visible:
		ok = _fail("window", "the pause buttons have no Settings button")
	settings_button.pressed.emit()
	await get_tree().process_frame
	if not window.visible or leave.visible or settings_button.visible:
		ok = _fail("window", "from pause: window %s, leave %s, settings button %s" % [window.visible, leave.visible, settings_button.visible])
	ui.call("close_settings")
	if window.visible or not leave.visible or not settings_button.visible:
		ok = _fail("window", "closing from pause: window %s, leave %s" % [window.visible, leave.visible])
	ui.call("close_pause")
	return ok


## Check 16 (settings:4): every string names keys only with {key:<action>} tokens
## that name real actions, never a hard-coded key; keyed() leaves no token
## behind; every rebindable action has a name; and the display code shows the
## player's own keys once they are rebound (interact R, phone J, push to talk K).
func _strings() -> bool:
	var ok := true
	var texts: Array = []
	var constants := (_Strings as Script).get_script_constant_map()
	for key: String in constants:
		_texts_in(constants[key], key, texts)
	var token := RegEx.create_from_string("\\{key:([a-z0-9_]+)\\}")
	var hard: Array[RegEx] = []
	for pattern: String in HARD_CODED_KEYS:
		hard.append(RegEx.create_from_string(pattern))
	var tokens := 0
	for entry: Array in texts:
		var path := str(entry[0])
		# A "{key:%s}" is a format slot for an action name (prompt_format), not a key.
		var text := str(entry[1]).replace("{key:%s}", "")
		for found: RegExMatch in token.search_all(text):
			tokens += 1
			if not InputMap.has_action(StringName(found.get_string(1))):
				ok = _fail("strings", "%s names no action '%s'" % [path, found.get_string(1)])
		var shown := _Strings.keyed(text)
		if shown.contains("{key:") or shown.contains("{icon:"):
			ok = _fail("strings", "keyed() left a token in %s: %s" % [path, shown])
		if KEY_NAME_PATHS.any(func(prefix: String) -> bool: return path.begins_with(prefix)):
			continue
		for regex: RegEx in hard:
			var hit := regex.search(text)
			if hit != null:
				ok = _fail("strings", "%s hard-codes a key ('%s'): %s" % [path, hit.get_string().strip_edges(), text])
				break
	for action: StringName in Settings.rebindable_actions():
		if not _Strings.UI.has("action_%s" % action):
			ok = _fail("strings", "no Strings.UI action_%s for the Keys tab" % action)
	print("[SettingsTest] %d strings read, %d key tokens" % [texts.size(), tokens])
	# The display sites, with keys rebound.
	Settings.bind(&"interact", 0, "key:%d" % KEY_R)
	Settings.bind(&"phone", 0, "key:%d" % KEY_J)
	Settings.bind(&"push_to_talk", 0, "key:%d" % KEY_K)
	var ui := get_tree().get_first_node_in_group("game_ui")
	var phone := get_tree().get_first_node_in_group("phone")
	if phone != null:
		var line := phone.call("_text", _Strings.UI["phone_close"], 14, Color.WHITE) as Label
		if not line.text.contains("[J]"):
			ok = _fail("strings", "a phone line reads '%s'" % line.text)
		line.free()
	var panel := ui.get("_voice_panel") as Control
	panel.call("open")
	var mode := panel.get("_mode") as OptionButton
	var push_text := mode.get_item_text(mode.get_item_index(Net.VoiceMode.PUSH_TO_TALK))
	panel.visible = false
	if not push_text.contains("[K]"):
		ok = _fail("strings", "the voice panel's push to talk reads '%s'" % push_text)
	# x1:text: the goal lines name no keys any more; an interact prompt does.
	var goal := _Prompt.text_for({"text": _Strings.UI["prompt_dip"]})
	if not goal.contains("[R]"):
		ok = _fail("strings", "the dip prompt reads '%s'" % goal)
	# The scenes' words come from Strings now (ui_root.tscn, world.tscn).
	if (ui.get("_leave") as Button).text != _Strings.UI["pause_leave"] or (ui.get_node("%HostButton") as Button).text != _Strings.UI["menu_host_steam"]:
		ok = _fail("strings", "the menu buttons read '%s' and '%s'" % [(ui.get("_leave") as Button).text, (ui.get_node("%HostButton") as Button).text])
	var world := get_tree().get_first_node_in_group("world")
	var gate := world.get_node_or_null("StoreZone/ToLot/Label") as Label3D
	if gate != null and gate.text != _Strings.UI["gate_sign_lot"]:
		ok = _fail("strings", "the lot gate's sign reads '%s'" % gate.text)
	var board := world.get_node_or_null("StoreZone/Board/Label") as Label3D
	if board != null and (board.text == "" or board.text.contains("{")):
		ok = _fail("strings", "the board sign reads '%s'" % board.text)
	print("[SettingsTest] rebound: '%s' / '%s' / '%s'" % [_Prompt.text_for({"text": _Strings.UI["prompt_board"]}), push_text, goal])
	Settings.reset_bindings()
	return ok


## Every string under value (a Strings constant), as [path, text].
func _texts_in(value: Variant, path: String, out: Array) -> void:
	match typeof(value):
		TYPE_STRING, TYPE_STRING_NAME:
			out.append([path, str(value)])
		TYPE_DICTIONARY:
			for key: Variant in value:
				_texts_in(value[key], "%s/%s" % [path, str(key)], out)
		TYPE_ARRAY:
			for index: int in (value as Array).size():
				_texts_in(value[index], "%s/%d" % [path, index], out)


## Captions (settings:4): the quip caption, the run-event cue caption and a homeowner's follow caption_size,
## caption_backdrop and captions on/off (off: no words, the babble still plays),
## and the quip caption and the lobby stay on screen at the biggest UI scale.
func _captions() -> bool:
	var ok := true
	var ui := get_tree().get_first_node_in_group("game_ui")
	var quips := ui.get_node_or_null("Quips")
	var caption := quips.get_node_or_null("Caption") as Label if quips != null else null
	if caption == null:
		return _fail("captions", "no UIRoot/Quips/Caption")
	Settings.reset_section("interface")
	quips.call("show_caption", "Testing. The leaves have filed an appeal.")
	await get_tree().process_frame
	if not caption.visible or caption.get_theme_font_size("font_size") != _QuipPlayer.FONT_SIZE or caption.has_theme_stylebox_override("normal"):
		ok = _fail("captions", "default caption: visible %s, size %d, backdrop %s" % [caption.visible, caption.get_theme_font_size("font_size"), caption.has_theme_stylebox_override("normal")])
	# Large, with a backdrop, at the biggest UI scale: still all on screen.
	Settings.set_value("interface", "caption_size", 2, false)
	Settings.set_value("interface", "caption_backdrop", true, false)
	Settings.set_value("interface", "ui_scale", Constants.UI_SCALE_RANGE.y, false)
	quips.call("show_caption", "A long one, to wrap: the leaves have filed an appeal, the appeal has been denied, and the leaves have retained counsel, who is also a leaf.")
	for frame: int in 3:
		await get_tree().process_frame
	var big := roundi(_QuipPlayer.FONT_SIZE * Constants.CAPTION_SCALES[2])
	if caption.get_theme_font_size("font_size") != big or not caption.has_theme_stylebox_override("normal"):
		ok = _fail("captions", "large with backdrop: size %d (want %d), backdrop %s" % [caption.get_theme_font_size("font_size"), big, caption.has_theme_stylebox_override("normal")])
	# The run-event radio and all-clear captions (on the caption stack since R2)
	# follow the same settings.
	var cues := ui.get_node_or_null("RunCues")
	var stack := ui.get_node_or_null("CaptionStack")
	var cue: Label = null
	if cues == null or stack == null:
		ok = _fail("captions", "no UIRoot/RunCues or UIRoot/CaptionStack")
	else:
		cues.call("_show_caption", "RADIO: testing, testing.")
		await get_tree().process_frame
		cue = stack.call("line_label", int(cues.get("_caption_id"))) as Label
		var cue_big := roundi(float(_CaptionStack.FONT_SIZES[&"radio"]) * Constants.CAPTION_SCALES[2])
		if cue == null:
			ok = _fail("captions", "the radio line isn't on the caption stack")
			cue = Label.new()
			add_child(cue)
		if not cue.visible or cue.get_theme_font_size("font_size") != cue_big or not cue.has_theme_stylebox_override("normal"):
			ok = _fail("captions", "cue caption large with backdrop: visible %s, size %d (want %d), backdrop %s" % [cue.visible, cue.get_theme_font_size("font_size"), cue_big, cue.has_theme_stylebox_override("normal")])
	var screen := caption.get_viewport_rect()
	# Anchored, not placed: its bottom edge is the corner offset above the screen's
	# bottom, or (R2c) lifted clear above the goal line when the two would share a band.
	var rest_y := screen.end.y - _QuipPlayer.CORNER_OFFSET.y
	var goal := ui.get_node_or_null("JobGoal") as Control
	var goal_up := goal != null and goal.is_visible_in_tree() and goal.modulate.a > 0.05 and goal.size.x > 0.0
	var at_rest := absf(caption.get_global_rect().end.y - rest_y) <= 1.0
	var lifted := goal_up and caption.get_global_rect().end.y < rest_y and not caption.get_global_rect().intersects(goal.get_global_rect())
	if not screen.encloses(caption.get_global_rect()) or not (at_rest or lifted) or goal_up and caption.get_global_rect().intersects(goal.get_global_rect()):
		ok = _fail("captions", "at UI scale %.2f the caption %s leaves the screen %s" % [Constants.UI_SCALE_RANGE.y, caption.get_global_rect(), screen])
	var lobby := ui.get_node_or_null("Lobby") as Control
	if lobby != null:
		lobby.visible = true
		for frame: int in 2:
			await get_tree().process_frame
		if not screen.encloses(lobby.get_global_rect()) or lobby.get_global_rect().get_center().distance_to(screen.get_center()) > 1.0:
			ok = _fail("captions", "at UI scale %.2f the lobby %s leaves the screen %s" % [Constants.UI_SCALE_RANGE.y, lobby.get_global_rect(), screen])
		lobby.visible = false
	print("[SettingsTest] at UI scale %.2f: screen %s, caption %s, lobby %s" % [Constants.UI_SCALE_RANGE.y, screen, caption.get_global_rect(), lobby.get_global_rect() if lobby != null else Rect2()])
	# Captions off: no words, but the babble still plays (after Sfx's repeat gap).
	await get_tree().create_timer(Constants.SFX_DEFAULT_GAP_MS / 1000.0 + 0.1).timeout
	Settings.set_value("interface", "captions", false, false)
	quips.call("show_caption", "Nobody reads this.")
	await get_tree().process_frame
	if caption.visible or _Sfx.log.is_empty() or _Sfx.log.back() != "babble":
		ok = _fail("captions", "captions off: visible %s, last sound %s" % [caption.visible, _Sfx.log.back() if not _Sfx.log.is_empty() else "none"])
	if cue != null:
		cues.call("_show_caption", "RADIO: nobody reads this either.")
		await get_tree().process_frame
		cue = stack.call("line_label", int(cues.get("_caption_id"))) as Label
		if cue != null and cue.visible and cue.modulate.a > 0.0:
			ok = _fail("captions", "cue caption shows with captions off")
	# A homeowner's caption: hidden while off, then the large size once on.
	var homeowner := _Homeowner.new()
	homeowner.name = "CaptionHomeowner"
	add_child(homeowner)
	homeowner.global_position = Vector3(0.0, -40.0, 0.0)
	homeowner.call("show_caption", "Is that my gnome?")
	await get_tree().process_frame
	var head := homeowner.get_node_or_null("Caption") as Label3D
	var hidden_off := head != null and not head.visible
	Settings.set_value("interface", "captions", true, false)
	await get_tree().process_frame
	if not hidden_off or head == null or not head.visible or not is_equal_approx(head.pixel_size, _Homeowner.CAPTION_PIXEL_SIZE * Constants.CAPTION_SCALES[2]):
		ok = _fail("captions", "homeowner: hidden while off %s, shown %s, pixel size %s" % [hidden_off, head != null and head.visible, head.pixel_size if head != null else 0.0])
	homeowner.queue_free()
	Settings.reset_section("interface")
	await get_tree().process_frame
	if caption.get_theme_font_size("font_size") != _QuipPlayer.FONT_SIZE or caption.has_theme_stylebox_override("normal"):
		ok = _fail("captions", "reset left size %d, backdrop %s" % [caption.get_theme_font_size("font_size"), caption.has_theme_stylebox_override("normal")])
	if cue != null and is_instance_valid(cue):
		if cue.get_theme_font_size("font_size") != int(_CaptionStack.FONT_SIZES[&"radio"]) or cue.has_theme_stylebox_override("normal"):
			ok = _fail("captions", "reset left the cue caption at size %d, backdrop %s" % [cue.get_theme_font_size("font_size"), cue.has_theme_stylebox_override("normal")])
		stack.call("drop", int(cues.get("_caption_id")))
	caption.visible = false
	return ok


# ---------------------------------------------------------------- helpers

func _me() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as Node3D
	return null


func _cameras(me: Node3D) -> Array[Camera3D]:
	var cameras: Array[Camera3D] = []
	for camera_path: String in ["Visual/Head/FirstPerson", "CameraRig/OverShoulder"]:
		var camera := me.get_node_or_null(camera_path) as Camera3D
		if camera != null:
			cameras.append(camera)
	return cameras


## Codes bound to more than one rebindable action in the InputMap.
func _shared_codes() -> Array[String]:
	var owner: Dictionary = {}
	var shared: Array[String] = []
	for action: StringName in Settings.rebindable_actions():
		for code: String in _codes(action):
			if owner.has(code) and owner[code] != action and not shared.has(code):
				shared.append(code)
			owner[code] = action
	return shared


## Every rebindable action's key and mouse codes, as the InputMap has them now.
func _snapshot_bindings() -> Dictionary:
	var snapshot: Dictionary = {}
	for action: StringName in Settings.rebindable_actions():
		snapshot[String(action)] = _codes(action)
	return snapshot


func _codes(action: StringName) -> Array[String]:
	var codes: Array[String] = []
	for event: InputEvent in InputMap.action_get_events(action):
		var code := Settings.event_to_code(event)
		if code != "":
			codes.append(code)
	return codes


func _key_event(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	return event


func _mouse_event(button: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	return event


## Presses or lets go of action the way a key does, and lets the frame see it.
func _press(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)
	await get_tree().process_frame
	await get_tree().process_frame


## A real left click (press and release) at a viewport position.
func _click(at: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := _mouse_event(MOUSE_BUTTON_LEFT)
		event.pressed = pressed
		event.position = at
		event.global_position = at
		Input.parse_input_event(event)
		await get_tree().process_frame
	await get_tree().process_frame


## A node behind the Settings window that counts the key presses it hears.
class _Ear extends Node:
	var heard: int = 0

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and (event as InputEventKey).pressed:
			heard += 1


## A real key press and release through Input, the way a keyboard sends it.
func _key(keycode: Key) -> void:
	var press := _key_event(keycode)
	Input.parse_input_event(press)
	await get_tree().process_frame
	await get_tree().process_frame
	var release := _key_event(keycode)
	release.pressed = false
	Input.parse_input_event(release)
	await get_tree().process_frame


func _write(text: String) -> void:
	var file := FileAccess.open(Settings.path(), FileAccess.WRITE)
	file.store_string(text)
	file.close()
