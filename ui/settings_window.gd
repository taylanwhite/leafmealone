extends PanelContainer

## Authority: local. The Settings window, "Form 7-B: Personal Preferences": a
## Homie Depot catalog card (ui/ui_style.gd) with five tabs, Sound, Controls,
## Keys, Video and Interface (gap-specs/settings.json chunk 3, with critic.md C3's
## ambience, song breaks and now playing). Every control writes through the
## Settings autoload (core/settings.gd), which applies it live and saves it, and
## every control redraws from Settings.changed, so a quality preset moves every
## video control and a reset moves its tab. Nothing here is networked.
##
## Keys: click a slot and it waits for the next key, mouse button or wheel tick,
## caught in _input before the GUI or the game sees it. Esc cancels, Backspace
## clears the slot (both hard-wired, so a rebound pause can't trap you), a key
## another action has swaps (Settings.bind), and refusals say why in the footer.
## Esc (the pause action) while not waiting closes the window, before it can
## toggle pause. A new display mode waits Constants.DISPLAY_REVERT_SECONDS for
## "Keep" and reverts by itself.
##
## ui/ui_root.gd builds it (open_settings / close_settings) with its dim
## backdrop; the test (net/dev/settings_test.gd) reads current_tab(),
## row_count(), row_labels(), binding_text() and is_listening().

signal closed()

const _Strings = preload("res://ui/strings.gd")
const _Style = preload("res://ui/ui_style.gd")
const TABS: Array[String] = ["sound", "controls", "keys", "video", "interface"]
## The Settings section each tab resets ("keys" resets the bindings).
const TAB_SECTIONS: Dictionary = {"sound": "audio", "controls": "controls", "keys": "keys", "video": "video", "interface": "interface"}
const LABEL_WIDTH: float = 230.0
const READOUT_WIDTH: float = 64.0
const SLOT_WIDTH: float = 180.0
const ROW_FONT: int = 18
## Previews played when a volume slider is let go (the music plays by itself).
const PREVIEWS: Dictionary = {"sfx_volume": "bag", "chatter_volume": "babble", "ambience_volume": "bird"}

## The dim layer behind the card; ui_root makes it and hands it over.
var backdrop: Control
## Whether this opening came from the pause buttons (closing brings them back).
var from_pause: bool = false

var _tab: String = "sound"
var _tab_buttons: Dictionary = {}
var _scroll: ScrollContainer
var _content: VBoxContainer
var _notice: Label
var _reset: Button
var _keep: Button
var _revert: Button
## "section/key" -> {"control", "readout", "format", "values"} for the open tab.
var _rows: Dictionary = {}
var _labels: PackedStringArray = PackedStringArray()
## "action/slot" -> the slot's card button, on the Keys tab.
var _slots: Dictionary = {}
var _listen_action: StringName = &""
var _listen_slot: int = -1
var _dragging: String = ""
var _revert_left: float = 0.0


func _ready() -> void:
	visible = false
	add_to_group("settings_window")
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", _Style.box(_Style.PAPER, 18, _Style.ORANGE, 6, 18))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	column.add_child(_Style.text(_Strings.UI["settings_title"], 34, _Style.ORANGE))
	column.add_child(_Style.text(_Strings.UI["settings_subtitle"], 16, _Style.INK.lightened(0.3)))
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	column.add_child(tabs)
	for tab: String in TABS:
		var pill := _Style.pill(_Strings.UI["settings_tab_" + tab], tab == _tab)
		pill.pressed.connect(func() -> void:
			_play_sfx("ui_pop")
			show_tab(tab)
		)
		tabs.add_child(pill)
		_tab_buttons[tab] = pill
	var sheet := PanelContainer.new()
	sheet.add_theme_stylebox_override("panel", _Style.box(_Style.CARD, 12, _Style.INK.lightened(0.7), 2, 8))
	sheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(sheet)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sheet.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 8)
	_scroll.add_child(_content)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	column.add_child(footer)
	_reset = _Style.button(_Strings.UI["settings_reset_tab"], _Style.INK)
	_reset.pressed.connect(_reset_tab)
	footer.add_child(_reset)
	_notice = _Style.text("", 15, _Style.ORANGE.darkened(0.2))
	_notice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_notice.custom_minimum_size = Vector2(120.0, 0.0)
	footer.add_child(_notice)
	_keep = _Style.button(_Strings.UI["display_keep_button"], _Style.ORANGE)
	_keep.visible = false
	_keep.pressed.connect(_keep_display)
	footer.add_child(_keep)
	_revert = _Style.button(_Strings.UI["display_revert_button"], _Style.INK)
	_revert.visible = false
	_revert.pressed.connect(_revert_display)
	footer.add_child(_revert)
	var done := _Style.button(_Strings.UI["settings_done"], _Style.ORANGE)
	done.pressed.connect(func() -> void:
		_play_sfx("ui_pop")
		close_window()
	)
	footer.add_child(done)
	Settings.changed.connect(_on_setting_changed)
	Settings.bindings_changed.connect(_refresh_slots)
	get_tree().root.size_changed.connect(func() -> void:
		if visible:
			_fit()
	)


func open(tab := "sound", came_from_pause := false) -> void:
	from_pause = came_from_pause
	visible = true
	if backdrop != null:
		backdrop.visible = true
	_set_notice("")
	show_tab(tab)
	_fit()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_window() -> void:
	if not visible:
		return
	_stop_listening()
	# Closing while a new display mode waits for "Keep" is not a keep.
	if _revert_left > 0.0:
		_revert_display()
	visible = false
	if backdrop != null:
		backdrop.visible = false
	closed.emit()


## Centered by anchors at its full size, or smaller when a big UI scale leaves
## less screen (the rows scroll).
func _fit() -> void:
	var view := get_viewport_rect().size
	var margin := Constants.SETTINGS_WINDOW_MARGIN * 2.0
	custom_minimum_size = Vector2(minf(Constants.SETTINGS_WINDOW_SIZE.x, view.x - margin), minf(Constants.SETTINGS_WINDOW_SIZE.y, view.y - margin))
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	reset_size()


func current_tab() -> String:
	return _tab


## How many setting rows (or key rows) the open tab has.
func row_count() -> int:
	return _labels.size()


func row_labels() -> PackedStringArray:
	return _labels.duplicate()


func is_listening() -> bool:
	return _listen_action != &""


## What a key slot's card shows right now (the Keys tab), else its label.
func binding_text(action: StringName, slot: int) -> String:
	var key := "%s/%d" % [action, slot]
	if _slots.has(key):
		return (_slots[key] as Button).text
	return Settings.key_label(action, slot)


func show_tab(tab: String) -> void:
	if not TABS.has(tab):
		tab = "sound"
	_stop_listening()
	_tab = tab
	for name_text: String in _tab_buttons:
		_Style.set_pill(_tab_buttons[name_text], name_text == tab)
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_rows.clear()
	_labels.clear()
	_slots.clear()
	match tab:
		"sound":
			_sound_tab()
		"controls":
			_controls_tab()
		"keys":
			_keys_tab()
		"video":
			_video_tab()
		"interface":
			_interface_tab()
	_reset.text = _Strings.UI["keys_reset_all" if tab == "keys" else "settings_reset_tab"]
	_scroll.scroll_vertical = 0
	if _revert_left <= 0.0:
		_set_notice("")


# ---------------------------------------------------------------- tabs

func _sound_tab() -> void:
	for key: String in ["master_volume", "music_volume", "sfx_volume", "ambience_volume", "chatter_volume", "voice_volume"]:
		_slider_row("row_" + key, "audio", key, 0.0, 1.0, 0.05, "percent")
	_toggle_row("row_music", "audio", "music")
	_toggle_row("row_music_rests", "audio", "music_rests")
	_choice_row("row_voice_mode", "audio", "voice_mode", [
		[_Strings.keyed(_Strings.UI["voice_mode_push"]), int(Net.VoiceMode.PUSH_TO_TALK)],
		[_Strings.keyed(_Strings.UI["voice_mode_open"]), int(Net.VoiceMode.VOICE_ACTIVATION)],
	])
	# The music director comes with the soundtrack (audio chunk 3); until then
	# there is nothing to name.
	var director := get_tree().get_first_node_in_group("music_director")
	if director != null and director.has_method("now_playing_title"):
		var title := str(director.call("now_playing_title"))
		var row := _row("row_now_playing")
		var playing := _Style.text(title if title != "" else _Strings.UI["now_playing_none"], ROW_FONT, _Style.INK.lightened(0.25))
		playing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(playing)


func _controls_tab() -> void:
	_slider_row("row_sensitivity", "controls", "sensitivity", Constants.SENSITIVITY_RANGE.x, Constants.SENSITIVITY_RANGE.y, 0.05, "times")
	_toggle_row("row_invert_y", "controls", "invert_y")
	_slider_row("row_fov", "controls", "fov", Constants.FOV_RANGE.x, Constants.FOV_RANGE.y, 1.0, "degrees")
	var hold_or_toggle := [[_Strings.UI["choice_hold"], false], [_Strings.UI["choice_toggle"], true]]
	_choice_row("row_toggle_sprint", "controls", "toggle_sprint", hold_or_toggle)
	_choice_row("row_toggle_crouch", "controls", "toggle_crouch", hold_or_toggle)


func _keys_tab() -> void:
	var hint := _Style.text(_Strings.UI["keys_hint"], 15, _Style.INK.lightened(0.3))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(hint)
	var listed: Array[StringName] = []
	var actions := Settings.rebindable_actions()
	var groups: Array = []
	for group: Dictionary in Constants.KEYBIND_GROUPS:
		var members: Array[StringName] = []
		for action: StringName in group["actions"]:
			if actions.has(action) and not listed.has(action):
				members.append(action)
				listed.append(action)
		groups.append([str(group["id"]), members])
	var others: Array[StringName] = []
	for action: StringName in actions:
		if not listed.has(action):
			others.append(action)
	groups.append(["other", others])
	for group: Array in groups:
		var members: Array[StringName] = group[1]
		if members.is_empty():
			continue
		_content.add_child(_Style.text(_Strings.UI["keys_group_" + str(group[0])], 20, _Style.ORANGE.darkened(0.15)))
		for action: StringName in members:
			_key_row(action)


func _video_tab() -> void:
	var presets: Array = []
	for preset: String in Settings.PRESETS:
		presets.append([_Strings.UI["preset_" + preset], preset])
	_choice_row("row_preset", "video", "preset", presets)
	_choice_row("row_window_mode", "video", "window_mode", [
		[_Strings.UI["display_windowed"], 0], [_Strings.UI["display_borderless"], 1], [_Strings.UI["display_exclusive"], 2],
	])
	_choice_row("row_vsync", "video", "vsync", [
		[_Strings.UI["vsync_off"], 0], [_Strings.UI["vsync_on"], 1], [_Strings.UI["vsync_adaptive"], 2],
	])
	var caps: Array = []
	for index: int in Constants.FPS_CAPS.size():
		var cap := Constants.FPS_CAPS[index]
		caps.append([_Strings.UI["fps_unlimited"] if cap <= 0 else _Strings.UI["fps_cap"] % cap, index])
	_choice_row("row_max_fps", "video", "max_fps", caps)
	_slider_row("row_render_scale", "video", "render_scale", Constants.RENDER_SCALE_RANGE.x, Constants.RENDER_SCALE_RANGE.y, 0.05, "percent")
	_choice_row("row_upscaler", "video", "upscaler", [[_Strings.UI["upscaler_bilinear"], 0], [_Strings.UI["upscaler_fsr"], 1]])
	_choice_row("row_aa", "video", "aa", [
		[_Strings.UI["aa_off"], 0], [_Strings.UI["aa_fxaa"], 1], [_Strings.UI["aa_msaa2"], 2], [_Strings.UI["aa_msaa4"], 3],
	])
	_choice_row("row_shadows", "video", "shadows", _levels(Constants.SHADOW_LEVELS.size()))
	_toggle_row("row_ssao", "video", "ssao")
	_toggle_row("row_glow", "video", "glow")
	_choice_row("row_outline", "video", "outline", [[_Strings.UI["outline_off"], 0], [_Strings.UI["outline_on"], 1], [_Strings.UI["outline_bold"], 2]])
	_choice_row("row_grass", "video", "grass", _levels(Constants.GRASS_LEVELS.size()))
	_slider_row("row_brightness", "video", "brightness", Constants.BRIGHTNESS_RANGE.x, Constants.BRIGHTNESS_RANGE.y, 0.05, "percent")


func _interface_tab() -> void:
	_slider_row("row_ui_scale", "interface", "ui_scale", Constants.UI_SCALE_RANGE.x, Constants.UI_SCALE_RANGE.y, 0.05, "percent")
	_toggle_row("row_captions", "interface", "captions")
	_choice_row("row_caption_size", "interface", "caption_size", [
		[_Strings.UI["caption_small"], 0], [_Strings.UI["caption_medium"], 1], [_Strings.UI["caption_large"], 2],
	])
	_toggle_row("row_caption_backdrop", "interface", "caption_backdrop")
	_toggle_row("row_show_fps", "interface", "show_fps")


## Off, Low, Medium, High, Ultra (as many as there are levels).
func _levels(count: int) -> Array:
	var names := ["level_off", "level_low", "level_medium", "level_high", "level_ultra"]
	var out: Array = []
	for index: int in mini(count, names.size()):
		out.append([_Strings.UI[names[index]], index])
	return out


# ---------------------------------------------------------------- rows

## A row: the 230 px label, then whatever the caller adds.
func _row(label_key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := _Style.text(_Strings.UI[label_key], ROW_FONT, _Style.INK)
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0.0)
	label.clip_text = true
	row.add_child(label)
	_content.add_child(row)
	_labels.append(label.text)
	return row


func _slider_row(label_key: String, section: String, key: String, min_value: float, max_value: float, step: float, format: String) -> void:
	var row := _row(label_key)
	var slider := _Style.slider(min_value, max_value, step)
	slider.custom_minimum_size = Vector2(200.0, 26.0)
	row.add_child(slider)
	var readout := _Style.text("", ROW_FONT, _Style.INK.lightened(0.15))
	readout.custom_minimum_size = Vector2(READOUT_WIDTH, 0.0)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(readout)
	_rows["%s/%s" % [section, key]] = {"control": slider, "readout": readout, "format": format}
	_refresh_row(section, key)
	slider.value_changed.connect(func(value: float) -> void:
		readout.text = _readout(format, value)
		_play_sfx("ui_tick")
		# UI scale waits for the drag to end, or the window rescales under the mouse.
		if key == "ui_scale" and _dragging == key:
			return
		Settings.set_value(section, key, value)
	)
	slider.drag_started.connect(func() -> void: _dragging = key)
	slider.drag_ended.connect(func(_changed: bool) -> void:
		_dragging = ""
		if key == "ui_scale":
			Settings.set_value(section, key, slider.value)
		if PREVIEWS.has(key):
			_play_sfx(PREVIEWS[key])
	)


func _toggle_row(label_key: String, section: String, key: String) -> void:
	var row := _row(label_key)
	var toggle := _Style.check()
	row.add_child(toggle)
	_rows["%s/%s" % [section, key]] = {"control": toggle}
	_refresh_row(section, key)
	toggle.toggled.connect(func(on: bool) -> void:
		_play_sfx("ui_tick")
		Settings.set_value(section, key, on)
	)


## items: [[text, value], ...], value being what Settings stores.
func _choice_row(label_key: String, section: String, key: String, items: Array) -> void:
	var row := _row(label_key)
	var texts := PackedStringArray()
	var values: Array = []
	for item: Array in items:
		texts.append(str(item[0]))
		values.append(item[1])
	var choice := _Style.choice(texts)
	row.add_child(choice)
	_rows["%s/%s" % [section, key]] = {"control": choice, "values": values}
	_refresh_row(section, key)
	choice.item_selected.connect(func(index: int) -> void:
		_play_sfx("ui_pop")
		_choose(section, key, values[index])
	)


func _choose(section: String, key: String, value: Variant) -> void:
	if section == "video" and key == "preset":
		if not Settings.apply_preset(str(value)):
			Settings.set_value(section, key, value)
		return
	if section == "video" and key == "window_mode":
		_change_display(int(value))
		return
	Settings.set_value(section, key, value)


## A row for one action on the Keys tab: its name, two slot cards, and reset.
func _key_row(action: StringName) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := _Style.text(Settings.action_name(action), ROW_FONT, _Style.INK)
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0.0)
	label.clip_text = true
	row.add_child(label)
	_labels.append(label.text)
	for slot: int in Constants.BINDING_SLOTS:
		var card := _Style.card_button(Settings.key_label(action, slot))
		card.custom_minimum_size = Vector2(SLOT_WIDTH, 34.0)
		card.clip_text = true
		card.pressed.connect(func() -> void: listen(action, slot))
		row.add_child(card)
		_slots["%s/%d" % [action, slot]] = card
	var reset := _Style.button(_Strings.UI["keys_reset_row"], _Style.SOFT)
	reset.custom_minimum_size = Vector2(40.0, 34.0)
	reset.tooltip_text = _Strings.UI["notice_row_reset"] % Settings.action_name(action)
	reset.pressed.connect(func() -> void:
		_play_sfx("ui_pop")
		_stop_listening()
		Settings.reset_action(action)
		_set_notice(_Strings.UI["notice_row_reset"] % Settings.action_name(action))
	)
	row.add_child(reset)
	_content.add_child(row)


func _readout(format: String, value: float) -> String:
	match format:
		"percent":
			return _Strings.UI["readout_percent"] % roundi(value * 100.0)
		"times":
			return _Strings.UI["readout_times"] % value
		"degrees":
			return _Strings.UI["readout_degrees"] % roundi(value)
	return str(value)


## Shows the setting's current value on its control, without firing the control.
func _refresh_row(section: String, key: String) -> void:
	var row: Dictionary = _rows.get("%s/%s" % [section, key], {})
	if row.is_empty():
		return
	var value: Variant = Settings.get_value(section, key)
	var control: Control = row["control"]
	if control is HSlider:
		(control as HSlider).set_value_no_signal(float(value))
		(row["readout"] as Label).text = _readout(str(row["format"]), float(value))
	elif control is CheckButton:
		(control as CheckButton).set_pressed_no_signal(bool(value))
	elif control is OptionButton:
		var values: Array = row["values"]
		for index: int in values.size():
			if typeof(values[index]) == typeof(value) and values[index] == value:
				(control as OptionButton).select(index)
				break


func _on_setting_changed(section: StringName, key: StringName, _value: Variant) -> void:
	if visible:
		_refresh_row(String(section), String(key))


func _reset_tab() -> void:
	_play_sfx("ui_pop")
	_stop_listening()
	var section := str(TAB_SECTIONS.get(_tab, ""))
	if section == "video" and _revert_left > 0.0:
		_clear_revert()
	Settings.reset_section(section)
	_set_notice(_Strings.UI["notice_tab_reset"])


# ---------------------------------------------------------------- keys

## Waits for the next key, mouse button or wheel tick for action's slot.
func listen(action: StringName, slot: int) -> void:
	_stop_listening()
	var key := "%s/%d" % [action, slot]
	if not _slots.has(key):
		return
	_listen_action = action
	_listen_slot = slot
	var card: Button = _slots[key]
	card.text = _Strings.UI["keys_listening"]
	_Style.paint_card(card, true)
	_reveal(card)
	_play_sfx("ui_pop")


## Scrolls a key slot into view once a tab built this frame has its layout.
func _reveal(card: Control) -> void:
	for frame: int in 2:
		await get_tree().process_frame
	if is_instance_valid(card) and card.is_inside_tree() and visible:
		_scroll.ensure_control_visible(card)


func _stop_listening() -> void:
	if _listen_action == &"":
		return
	var key := "%s/%d" % [_listen_action, _listen_slot]
	_listen_action = &""
	_listen_slot = -1
	if _slots.has(key):
		var card: Button = _slots[key]
		_Style.paint_card(card, false)
	_refresh_slots()


func _refresh_slots() -> void:
	for key: String in _slots:
		var parts := key.split("/")
		var action := StringName(parts[0])
		var slot := int(parts[1])
		if action == _listen_action and slot == _listen_slot:
			continue
		(_slots[key] as Button).text = Settings.key_label(action, slot)


## Hands a captured key or button to Settings: a binding stamps and says what
## swapped; a refusal says why and keeps waiting for another key.
func _accept(event: InputEvent) -> void:
	var action := _listen_action
	var slot := _listen_slot
	var result := Settings.bind(action, slot, event)
	if not bool(result["ok"]):
		_set_notice(str(result["notice"]))
		_play_sfx("ui_tick")
		return
	_stop_listening()
	_play_sfx("ui_stamp")
	var notice := str(result["notice"])
	if notice == "":
		notice = _Strings.UI["notice_stamped"] % [Settings.action_name(action), Settings.key_label(action, slot)]
	_set_notice(notice)


func _clear_listened() -> void:
	var action := _listen_action
	var result := Settings.clear_binding(action, _listen_slot)
	_stop_listening()
	if bool(result["ok"]):
		_play_sfx("ui_pop")
		_set_notice(_Strings.UI["notice_cleared"] % Settings.action_name(action))
	else:
		_set_notice(str(result["notice"]))


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _listen_action != &"":
		if event is InputEventKey:
			var key := event as InputEventKey
			if key.pressed and not key.echo:
				var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
				if code == KEY_ESCAPE:
					_stop_listening()
				elif code == KEY_BACKSPACE:
					_clear_listened()
				else:
					_accept(key)
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton:
			if (event as InputEventMouseButton).pressed:
				_accept(event)
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause"):
		close_window()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("phone"):
		# The phone stays in your pocket while the form is out.
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- display

## A new display mode applies now but isn't saved until "Keep"; it reverts by itself.
func _change_display(mode: int) -> void:
	var saved := int(Settings.saved_value("video", "window_mode"))
	Settings.set_value("video", "window_mode", mode, false)
	if mode == saved:
		_clear_revert()
		return
	_revert_left = Constants.DISPLAY_REVERT_SECONDS
	_keep.visible = true
	_revert.visible = true
	_show_countdown()


func _process(delta: float) -> void:
	if _revert_left <= 0.0:
		return
	_revert_left -= delta
	if _revert_left <= 0.0:
		_revert_display()
		return
	_show_countdown()


func _show_countdown() -> void:
	_set_notice(_Strings.UI["display_keep"] % ceili(_revert_left))


func _keep_display() -> void:
	_play_sfx("ui_stamp")
	Settings.set_value("video", "window_mode", Settings.get_value("video", "window_mode"))
	_clear_revert()


func _revert_display() -> void:
	Settings.set_value("video", "window_mode", Settings.saved_value("video", "window_mode"), false)
	_clear_revert()


func _clear_revert() -> void:
	_revert_left = 0.0
	_keep.visible = false
	_revert.visible = false
	_set_notice("")


# ---------------------------------------------------------------- helpers

func _set_notice(text: String) -> void:
	_notice.text = text


## The window's sounds go through the sfx node (audio/sfx.gd), on the UI bus
## (audio/sound_bank.gd); headless and smoke runs only log them.
func _play_sfx(id: String) -> void:
	if not is_inside_tree():
		return
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play", id)
