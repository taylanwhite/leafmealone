extends Node

## Authority: local. The "Settings" autoload: this machine's player preferences
## (volumes, look, field of view, hold or toggle, key bindings, video and
## interface), kept in user://settings.cfg. Nothing here is networked, and the
## file is separate from the campaign save (docs/DECISIONS.md, "Player settings").
## Dev, test, bot and smoke runs use user://settings_test_<port>.cfg instead, so a
## test never reads or writes the player's real file.
##
## Every change applies live and is written Constants.SETTINGS_SAVE_DELAY later.
## Other code reads values with get_value(), listens to changed, and never keeps
## a config file of its own. Bindings are codes: "key:<physical keycode>",
## "mouse:<button index>" (4 to 7 are the wheel), or "" for an empty slot.
##
## settings:2 (gap-specs/settings.json) adds the render and display application;
## until then the video keys are stored, validated and handed to
## levels/graphics_quality.gd when that script exists.

signal changed(section: StringName, key: StringName, value: Variant)
signal bindings_changed()

const FILE_VERSION: int = 1
const REAL_PATH := "user://settings.cfg"
const TEST_PATH := "user://settings_test_%d.cfg"
const GRAPHICS_QUALITY_PATH := "res://levels/graphics_quality.gd"
const _Buses = preload("res://audio/buses.gd")
const _Strings = preload("res://ui/strings.gd")
const _InputLabels = preload("res://core/input_labels.gd")

## Every value's default, by section. Numbers come from Constants; the video
## defaults are the "high" preset, the shipped look.
const DEFAULTS: Dictionary = {
	"audio": {
		"master_volume": 1.0,
		"music_volume": 1.0,
		"sfx_volume": 1.0,
		"ambience_volume": 1.0,
		"chatter_volume": 1.0,
		"voice_volume": 1.0,
		# The legacy key from audio/ambience.gd, kept so old files still work.
		"music": true,
		"music_rests": true,
		# Net.VoiceMode: 0 push to talk, 1 open mic.
		"voice_mode": 0,
	},
	"controls": {
		"sensitivity": 1.0,
		"invert_y": false,
		"fov": Constants.FOV_DEFAULT,
		"toggle_sprint": false,
		"toggle_crouch": false,
	},
	"video": {
		"preset": "high",
		# 0 windowed, 1 borderless fullscreen, 2 exclusive fullscreen.
		"window_mode": 0,
		# 0 off, 1 on, 2 adaptive.
		"vsync": 1,
		# An index into Constants.FPS_CAPS (0 is unlimited).
		"max_fps": 0,
		"render_scale": 1.0,
		# 0 bilinear, 1 FSR 1.0.
		"upscaler": 0,
		# 0 off, 1 FXAA, 2 MSAA 2x, 3 MSAA 4x.
		"aa": 0,
		"shadows": 3,
		"ssao": true,
		"glow": true,
		"outline": 1,
		"grass": 3,
		"brightness": 1.0,
	},
	"interface": {
		"ui_scale": 1.0,
		"captions": true,
		# An index into Constants.CAPTION_SCALES.
		"caption_size": 1,
		"caption_backdrop": false,
		"show_fps": false,
	},
}
## The bus each volume key sets.
const VOLUME_BUSES: Dictionary = {
	"master_volume": _Buses.MASTER,
	"music_volume": _Buses.MUSIC,
	"sfx_volume": _Buses.SFX,
	"ambience_volume": _Buses.AMBIENCE,
	"chatter_volume": _Buses.CHATTER,
	"voice_volume": _Buses.VOICE,
}
const PRESETS: Array[String] = ["low", "medium", "high", "ultra", "custom"]
## A volume at or below this mutes its bus.
const MUTE_BELOW: float = 0.001
## An event on every device (InputMap matches it from any keyboard or mouse).
const ALL_DEVICES: int = -1
## The wheel's mouse buttons, which have no held state.
const WHEEL_BUTTONS: Array[int] = [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]

## What the render settings last asked the engine for (settings:2 fills it), for tests.
var last_render: Dictionary = {}
## The display mode and vsync last asked for, and whether they were applied (settings:2).
var last_display: Dictionary = {}

var _values: Dictionary = {}
## What the file should hold: _values minus anything last set with persist false
## (a slider preview, a display mode waiting for "Keep"). save_now writes this.
var _stored: Dictionary = {}
## action (String) -> PackedStringArray of Constants.BINDING_SLOTS codes.
var _slots: Dictionary = {}
var _default_slots: Dictionary = {}
## Toggle sprint and crouch: whether each is latched on.
var _latched: Dictionary = {"sprint": false, "crouch": false}
var _dirty: bool = false
var _save_timer: Timer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_Buses.ensure()
	_snapshot_defaults()
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = Constants.SETTINGS_SAVE_DELAY
	_save_timer.timeout.connect(save_now)
	add_child(_save_timer)
	_load()
	_apply_all()
	# A crouch toggled in a menu or the last session doesn't carry into the next.
	Net.state_changed.connect(func(_state: Variant) -> void: release_toggles())


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _dirty:
		save_now()


func _exit_tree() -> void:
	if _dirty:
		save_now()


## The file this run reads and writes. Any dev, test or automation session
## (net/command_line.gd is_dev_session(), the same rule as the campaign save)
## uses its own test file, so tests start from defaults.
func path() -> String:
	var options := Net.dev_options()
	if bool(options.call("is_dev_session")):
		return TEST_PATH % int(options.get("port"))
	return REAL_PATH


# ---------------------------------------------------------------- values

func get_value(section: String, key: String) -> Variant:
	var table: Dictionary = _values.get(section, {})
	if table.has(key):
		return table[key]
	return (DEFAULTS.get(section, {}) as Dictionary).get(key)


## The value the file holds (or will hold at the next save) for section/key. A
## value set with persist false reads its old, saved value here until a
## persisted set; a revert is set_value(section, key, saved_value(...), false).
func saved_value(section: String, key: String) -> Variant:
	var table: Dictionary = _stored.get(section, {})
	if table.has(key):
		return table[key]
	return (DEFAULTS.get(section, {}) as Dictionary).get(key)


## Sets one value, clamped to its range, and applies only what it affects.
## persist false changes it for this run only: no later save writes it, until
## the same key is set again with persist true (or its section is reset).
func set_value(section: String, key: String, value: Variant, persist := true) -> void:
	if not DEFAULTS.has(section) or not (DEFAULTS[section] as Dictionary).has(key):
		push_warning("[Settings] no setting %s/%s" % [section, key])
		return
	var clean: Variant = _coerce(section, key, value)
	var old: Variant = get_value(section, key)
	(_values[section] as Dictionary)[key] = clean
	if section == "video" and key != "preset" and _goes_custom(_values["video"], key, clean):
		_values["video"]["preset"] = "custom"
		changed.emit(&"video", &"preset", "custom")
	_apply(section, key)
	if typeof(old) != typeof(clean) or old != clean:
		changed.emit(StringName(section), StringName(key), clean)
	if persist:
		(_stored[section] as Dictionary)[key] = clean
		if section == "video" and key != "preset" and _goes_custom(_stored["video"], key, clean):
			_stored["video"]["preset"] = "custom"
		_mark_dirty()


## Every value in section back to its default ("keys" resets the bindings).
func reset_section(section: String) -> void:
	if section == "keys":
		reset_bindings()
		return
	if not DEFAULTS.has(section):
		return
	for key: String in DEFAULTS[section]:
		var value: Variant = DEFAULTS[section][key]
		var old: Variant = get_value(section, key)
		(_values[section] as Dictionary)[key] = value
		if old != value:
			changed.emit(StringName(section), StringName(key), value)
	_stored[section] = (DEFAULTS[section] as Dictionary).duplicate(true)
	_apply_section(section)
	_mark_dirty()


## Writes a quality preset's video keys ("low", "medium", "high", "ultra").
func apply_preset(preset_name: String) -> bool:
	if not Constants.GRAPHICS_PRESETS.has(preset_name):
		return false
	var preset: Dictionary = Constants.GRAPHICS_PRESETS[preset_name]
	var video: Dictionary = _values["video"]
	var stored: Dictionary = _stored["video"]
	for key: String in preset:
		var clean: Variant = _coerce("video", key, preset[key])
		stored[key] = clean
		if video[key] != clean:
			video[key] = clean
			changed.emit(&"video", StringName(key), clean)
	stored["preset"] = preset_name
	if video["preset"] != preset_name:
		video["preset"] = preset_name
		changed.emit(&"video", &"preset", preset_name)
	_apply_video()
	_mark_dirty()
	return true


func save_now() -> Error:
	_save_timer.stop()
	var file := ConfigFile.new()
	file.set_value("meta", "version", FILE_VERSION)
	for section: String in DEFAULTS:
		for key: String in DEFAULTS[section]:
			file.set_value(section, key, saved_value(section, key))
	# Only the bindings that differ from the project's, so a changed default
	# still reaches players who never touched that action.
	for action: String in _slots:
		if _slots[action] != _default_slots.get(action):
			file.set_value("keys", action, _slots[action])
	var error := file.save(path())
	if error != OK:
		push_warning("[Settings] could not save %s: %s" % [path(), error_string(error)])
	_dirty = false
	return error


## Reads the file again, dropping unsaved changes, and applies everything.
func reload() -> void:
	_save_timer.stop()
	_dirty = false
	_load()
	_apply_all()
	for section: String in DEFAULTS:
		for key: String in DEFAULTS[section]:
			changed.emit(StringName(section), StringName(key), get_value(section, key))
	bindings_changed.emit()


# ---------------------------------------------------------------- readers

## Radians of turn per pixel of mouse motion: x for yaw, y for pitch (negative
## when the look is inverted).
func look_scale() -> Vector2:
	var turn := Constants.MOUSE_SENSITIVITY_BASE * float(get_value("controls", "sensitivity"))
	return Vector2(turn, -turn if bool(get_value("controls", "invert_y")) else turn)


func fov() -> float:
	return float(get_value("controls", "fov"))


func caption_scale() -> float:
	var index := clampi(int(get_value("interface", "caption_size")), 0, Constants.CAPTION_SCALES.size() - 1)
	return Constants.CAPTION_SCALES[index]


## Whether a held action is on. Sprint and crouch honor the hold/toggle choice;
## everything else is Input.is_action_pressed. Bots press actions through
## Input, which is the hold path (toggles are off by default).
func is_held(action: StringName) -> bool:
	var toggle_key := _toggle_key(action)
	if toggle_key != "" and bool(get_value("controls", toggle_key)):
		return bool(_latched.get(String(action), false))
	return Input.is_action_pressed(action)


func _input(event: InputEvent) -> void:
	if event.is_echo():
		return
	for action: String in _latched:
		if not event.is_action_pressed(action):
			continue
		if not bool(get_value("controls", _toggle_key(StringName(action)))):
			continue
		# Typing a name into a text box isn't crouching.
		var focus := get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit:
			continue
		_latched[action] = not bool(_latched[action])


## Unlatches toggle sprint and crouch. Called when the session state changes and
## when the local player spawns (player/player.gd).
func release_toggles() -> void:
	for action: String in _latched:
		_latched[action] = false


func _toggle_key(action: StringName) -> String:
	if action == &"sprint":
		return "toggle_sprint"
	if action == &"crouch":
		return "toggle_crouch"
	return ""


# ---------------------------------------------------------------- bindings

## Every action a player can rebind: the Constants.KEYBIND_GROUPS order, then any
## other non-ui_ action in the InputMap (a later feature's actions land there).
func rebindable_actions() -> Array[StringName]:
	var actions: Array[StringName] = []
	for group: Dictionary in Constants.KEYBIND_GROUPS:
		for action: StringName in group["actions"]:
			if InputMap.has_action(action) and not actions.has(action):
				actions.append(action)
	for action: StringName in InputMap.get_actions():
		var text := String(action)
		if text.begins_with("ui_") or text.contains("/") or actions.has(action):
			continue
		actions.append(action)
	return actions


## Whether Settings keeps slots for action (core/input_labels.gd asks).
func has_slots(action: StringName) -> bool:
	return _slots.has(String(action))


## The code in one of action's slots ("" when empty).
func binding(action: StringName, slot: int) -> String:
	var codes: PackedStringArray = _slots.get(String(action), PackedStringArray())
	if slot < 0 or slot >= codes.size():
		return ""
	return codes[slot]


## What a prompt calls action's key: slot -1 is the first bound one.
func key_label(action: StringName, slot := -1) -> String:
	if slot < 0:
		return _InputLabels.label(action)
	var code := binding(action, slot)
	if code == "":
		return _Strings.UI["key_unbound"]
	return _InputLabels.event_label(code_to_event(code))


## Binds event (an InputEvent or a code) to action's slot. A key another action
## already uses swaps: that action gets this slot's old key. The wheel can't
## bind a held action, and pause always keeps a binding.
## Returns {ok, swapped_with (the other action, or ""), notice (text, or "")}.
func bind(action: StringName, slot: int, event: Variant) -> Dictionary:
	var code := str(event) if event is String or event is StringName else event_to_code(event as InputEvent)
	var name_text := String(action)
	if not _slots.has(name_text) or slot < 0 or slot >= Constants.BINDING_SLOTS:
		return _bind_result(false, "", "")
	var parsed := code_to_event(code)
	if parsed == null:
		return _bind_result(false, "", "")
	code = event_to_code(parsed)
	var old := binding(action, slot)
	if old == code:
		return _bind_result(true, "", "")
	if _is_wheel(code) and Constants.HOLD_ACTIONS.has(action):
		return _bind_result(false, "", _Strings.UI["notice_needs_hold"] % action_name(action))
	var holder := _holder_of(code, action, slot)
	var other: StringName = holder[0]
	if other != &"":
		if _is_wheel(old) and Constants.HOLD_ACTIONS.has(other):
			return _bind_result(false, "", _Strings.UI["notice_needs_hold"] % action_name(other))
		if other == &"pause" and other != action and old == "" and _bound_count(&"pause") <= 1:
			return _bind_result(false, "", _Strings.UI["notice_keep_pause"])
		_set_code(String(other), int(holder[1]), old)
	_set_code(name_text, slot, code)
	_apply_bindings([action, other] if other != &"" else [action])
	_mark_dirty()
	bindings_changed.emit()
	if other == &"" or other == action:
		return _bind_result(true, "", "")
	var key_text := _InputLabels.event_label(parsed)
	var notice := ""
	if old != "":
		notice = _Strings.UI["notice_swapped"] % [key_text, action_name(other), action_name(other), _InputLabels.event_label(code_to_event(old))]
	else:
		notice = _Strings.UI["notice_took"] % [key_text, action_name(other), action_name(other)]
	return _bind_result(true, String(other), notice)


## Empties one slot. Refused when it is pause's last binding.
func clear_binding(action: StringName, slot: int) -> Dictionary:
	if binding(action, slot) == "":
		return _bind_result(true, "", "")
	if action == &"pause" and _bound_count(action) <= 1:
		return _bind_result(false, "", _Strings.UI["notice_keep_pause"])
	_set_code(String(action), slot, "")
	_apply_bindings([action])
	_mark_dirty()
	bindings_changed.emit()
	return _bind_result(true, "", "")


## One action back to the project's keys. Another action using one of them loses it.
func reset_action(action: StringName) -> void:
	var text := String(action)
	if not _default_slots.has(text):
		return
	_slots[text] = (_default_slots[text] as PackedStringArray).duplicate()
	var touched := _drop_conflicts([text])
	touched.append(action)
	_apply_bindings(touched)
	_mark_dirty()
	bindings_changed.emit()


func reset_bindings() -> void:
	for action: String in _default_slots:
		_slots[action] = (_default_slots[action] as PackedStringArray).duplicate()
	_apply_bindings(rebindable_actions())
	_mark_dirty()
	bindings_changed.emit()


## The project's own bindings for action, as codes (what reset puts back).
func default_binding(action: StringName, slot: int) -> String:
	var codes: PackedStringArray = _default_slots.get(String(action), PackedStringArray())
	return codes[slot] if slot >= 0 and slot < codes.size() else ""


## An action's name as the Keys tab and notices show it.
func action_name(action: StringName) -> String:
	return str(_Strings.UI.get("action_%s" % action, String(action).capitalize()))


static func event_to_code(event: InputEvent) -> String:
	if event is InputEventKey:
		var key := event as InputEventKey
		var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		return "key:%d" % code if code != KEY_NONE else ""
	if event is InputEventMouseButton:
		var button := (event as InputEventMouseButton).button_index
		return "mouse:%d" % button if button > 0 else ""
	return ""


## The event a code stands for, or null. "key:R" (a key's name) also works.
static func code_to_event(code: String) -> InputEvent:
	var parts := code.split(":", false, 1)
	if parts.size() != 2:
		return null
	if parts[0] == "key":
		var keycode := int(parts[1]) if parts[1].is_valid_int() else int(OS.find_keycode_from_string(parts[1]))
		if keycode <= 0:
			return null
		var key := InputEventKey.new()
		key.device = ALL_DEVICES
		key.physical_keycode = keycode as Key
		return key
	if parts[0] == "mouse" and parts[1].is_valid_int():
		var index := int(parts[1])
		if index < MOUSE_BUTTON_LEFT or index > MOUSE_BUTTON_XBUTTON2:
			return null
		var button := InputEventMouseButton.new()
		button.device = ALL_DEVICES
		button.button_index = index as MouseButton
		return button
	return null


## Packed arrays are values in GDScript, so a slot is changed by storing the array back.
func _set_code(action: String, slot: int, code: String) -> void:
	var codes: PackedStringArray = _slots[action]
	codes[slot] = code
	_slots[action] = codes


func _bind_result(ok: bool, swapped_with: String, notice: String) -> Dictionary:
	return {"ok": ok, "swapped_with": swapped_with, "notice": notice}


func _is_wheel(code: String) -> bool:
	if not code.begins_with("mouse:"):
		return false
	return WHEEL_BUTTONS.has(int(code.trim_prefix("mouse:")))


## [action, slot] of whoever else holds code, or [&"", -1].
func _holder_of(code: String, action: StringName, slot: int) -> Array:
	for other: String in _slots:
		var codes: PackedStringArray = _slots[other]
		for index: int in codes.size():
			if codes[index] == code and not (StringName(other) == action and index == slot):
				return [StringName(other), index]
	return [&"", -1]


func _bound_count(action: StringName) -> int:
	var count := 0
	for code: String in _slots.get(String(action), PackedStringArray()):
		if code != "":
			count += 1
	return count


## The actions in winners keep their codes; any other action holding one of them
## loses it. Pause falls back to its default keys if it would end up empty, and
## those keys then come off every other action, winners included (pause always
## keeps a key). Returns the actions that changed.
func _drop_conflicts(winners: Array) -> Array[StringName]:
	var taken: Dictionary = {}
	for action: String in winners:
		for code: String in _slots[action]:
			if code != "":
				taken[code] = true
	var touched: Array[StringName] = []
	for action: String in _slots:
		if winners.has(action):
			continue
		var codes: PackedStringArray = _slots[action]
		for index: int in codes.size():
			if codes[index] != "" and taken.has(codes[index]):
				_set_code(action, index, "")
				if not touched.has(StringName(action)):
					touched.append(StringName(action))
	if _bound_count(&"pause") == 0 and _default_slots.has("pause"):
		_slots["pause"] = (_default_slots["pause"] as PackedStringArray).duplicate()
		if not touched.has(&"pause"):
			touched.append(&"pause")
		for code: String in _slots["pause"]:
			if code == "":
				continue
			for action: String in _slots:
				if action == "pause":
					continue
				var codes: PackedStringArray = _slots[action]
				var index := codes.find(code)
				if index >= 0:
					_set_code(action, index, "")
					if not touched.has(StringName(action)):
						touched.append(StringName(action))
	return touched


func _snapshot_defaults() -> void:
	_default_slots = {}
	for action: StringName in rebindable_actions():
		var codes := PackedStringArray()
		for event: InputEvent in InputMap.action_get_events(action):
			var code := event_to_code(event)
			if code != "" and codes.size() < Constants.BINDING_SLOTS and not codes.has(code):
				codes.append(code)
		while codes.size() < Constants.BINDING_SLOTS:
			codes.append("")
		_default_slots[String(action)] = codes


## Puts the slots into the InputMap, keeping any event that isn't a key or a
## mouse button (a gamepad's), and lets go of each action so nothing sticks.
func _apply_bindings(actions: Array) -> void:
	for action: Variant in actions:
		var name_text := String(action)
		if name_text == "" or not InputMap.has_action(StringName(name_text)) or not _slots.has(name_text):
			continue
		for event: InputEvent in InputMap.action_get_events(StringName(name_text)):
			if event is InputEventKey or event is InputEventMouseButton:
				InputMap.action_erase_event(StringName(name_text), event)
		for code: String in _slots[name_text]:
			var event := code_to_event(code)
			if event != null:
				InputMap.action_add_event(StringName(name_text), event)
		Input.action_release(StringName(name_text))
		if _latched.has(name_text):
			_latched[name_text] = false


# ---------------------------------------------------------------- file

func _load() -> void:
	_read_file()
	_stored = _values.duplicate(true)


func _read_file() -> void:
	_values = DEFAULTS.duplicate(true)
	_slots = {}
	for action: String in _default_slots:
		_slots[action] = (_default_slots[action] as PackedStringArray).duplicate()
	var file_path := path()
	if not FileAccess.file_exists(file_path):
		return
	var file := ConfigFile.new()
	var error := file.load(file_path)
	if error != OK:
		push_warning("[Settings] %s is unreadable (%s); using defaults" % [file_path, error_string(error)])
		return
	for section: String in DEFAULTS:
		for key: String in DEFAULTS[section]:
			if file.has_section_key(section, key):
				(_values[section] as Dictionary)[key] = _coerce(section, key, file.get_value(section, key))
	var overridden: Array = []
	if file.has_section("keys"):
		for action: String in file.get_section_keys("keys"):
			if not _slots.has(action):
				continue
			var stored: Variant = file.get_value("keys", action)
			if not (stored is PackedStringArray or stored is Array):
				continue
			var codes := PackedStringArray()
			for index: int in Constants.BINDING_SLOTS:
				var code := str(stored[index]) if index < stored.size() else ""
				var event := code_to_event(code)
				codes.append(event_to_code(event) if event != null else "")
			_slots[action] = codes
			overridden.append(action)
	# One at a time, so two saved actions on one key (a hand-edited file) can't
	# both keep it: the later one wins.
	for action: String in overridden:
		_drop_conflicts([action])


func _mark_dirty() -> void:
	_dirty = true
	if _save_timer != null and _save_timer.is_inside_tree():
		_save_timer.start()


## A value of the default's type, inside its range.
func _coerce(section: String, key: String, value: Variant) -> Variant:
	var fallback: Variant = DEFAULTS[section][key]
	match typeof(fallback):
		TYPE_BOOL:
			return bool(value) if typeof(value) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT] else fallback
		TYPE_FLOAT:
			if not typeof(value) in [TYPE_INT, TYPE_FLOAT]:
				return fallback
			var limits := _float_range(section, key)
			return clampf(float(value), limits.x, limits.y)
		TYPE_INT:
			if not typeof(value) in [TYPE_INT, TYPE_FLOAT]:
				return fallback
			return clampi(int(value), 0, _int_max(key))
		TYPE_STRING:
			var text := str(value)
			if key == "preset" and not PRESETS.has(text):
				return fallback
			return text
	return fallback


func _float_range(section: String, key: String) -> Vector2:
	if section == "audio":
		return Vector2(0.0, 1.0)
	match key:
		"sensitivity":
			return Constants.SENSITIVITY_RANGE
		"fov":
			return Constants.FOV_RANGE
		"render_scale":
			return Constants.RENDER_SCALE_RANGE
		"brightness":
			return Constants.BRIGHTNESS_RANGE
		"ui_scale":
			return Constants.UI_SCALE_RANGE
	return Vector2(0.0, 1.0)


## The highest index an int setting allows.
func _int_max(key: String) -> int:
	match key:
		"voice_mode":
			return Net.VoiceMode.size() - 1
		"window_mode", "vsync":
			return 2
		"max_fps":
			return Constants.FPS_CAPS.size() - 1
		"upscaler":
			return 1
		"aa":
			return 3
		"shadows":
			return Constants.SHADOW_LEVELS.size() - 1
		"grass":
			return Constants.GRASS_LEVELS.size() - 1
		"outline":
			return Constants.OUTLINE_WIDTHS.size() - 1
		"caption_size":
			return Constants.CAPTION_SCALES.size() - 1
	return 0


## Whether a video key a preset sets, changed by hand to value, makes video's
## (a _values or _stored table) preset "custom".
func _goes_custom(video: Dictionary, key: String, value: Variant) -> bool:
	var current := str(video["preset"])
	if current == "custom" or not Constants.GRAPHICS_PRESETS.has(current):
		return false
	var preset: Dictionary = Constants.GRAPHICS_PRESETS[current]
	return preset.has(key) and _coerce("video", key, preset[key]) != value


# ---------------------------------------------------------------- applying

func _apply_all() -> void:
	_apply_bindings(rebindable_actions())
	for section: String in DEFAULTS:
		_apply_section(section)


func _apply_section(section: String) -> void:
	match section:
		"audio":
			_apply_audio()
			_apply_voice_mode()
		"controls":
			release_toggles()
		"video":
			_apply_video()
		"interface":
			_apply_interface()


func _apply(section: String, key: String) -> void:
	match section:
		"audio":
			if key == "voice_mode":
				_apply_voice_mode()
			elif VOLUME_BUSES.has(key):
				_apply_audio()
		"controls":
			if key == "toggle_sprint":
				_latched["sprint"] = false
			elif key == "toggle_crouch":
				_latched["crouch"] = false
		"video":
			_apply_video()
		"interface":
			if key == "ui_scale":
				_apply_interface()


func _apply_audio() -> void:
	var muted_run := bool(Net.dev_options().get("mute_audio"))
	for key: String in VOLUME_BUSES:
		var index := AudioServer.get_bus_index(VOLUME_BUSES[key])
		if index < 0:
			continue
		var level := float(get_value("audio", key))
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(level, MUTE_BELOW)))
		var mute := level <= MUTE_BELOW
		# --mute-audio (net/dev/dev_tools.gd) keeps Master muted whatever the file says.
		if VOLUME_BUSES[key] == _Buses.MASTER and muted_run:
			mute = true
		AudioServer.set_bus_mute(index, mute)


func _apply_voice_mode() -> void:
	Net.set_voice_mode(int(get_value("audio", "voice_mode")) as Net.VoiceMode)


## The world's look (sun shadows, ambient occlusion, glow, grass, outlines)
## comes from levels/graphics_quality.gd, made by settings:2.
func _apply_video() -> void:
	if not ResourceLoader.exists(GRAPHICS_QUALITY_PATH) or not is_inside_tree():
		return
	var quality: Script = load(GRAPHICS_QUALITY_PATH)
	for world: Node in get_tree().get_nodes_in_group("world"):
		quality.call("apply", world)


func _apply_interface() -> void:
	if is_inside_tree():
		get_tree().root.content_scale_factor = float(get_value("interface", "ui_scale"))
