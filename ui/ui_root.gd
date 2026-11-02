extends CanvasLayer

## Authority: local. Menu, connecting state, and mouse capture for this peer only.

@onready var _menu: Control = %Menu
@onready var _name_field: LineEdit = %NameField
@onready var _address_field: LineEdit = %AddressField
@onready var _connecting: Label = %Connecting
@onready var _ended: Control = %SessionEnded
@onready var _ended_reason: Label = %EndedReason
@onready var _leave: Button = %LeaveButton

var _cleanup: Label
var _lobby: VBoxContainer
var _lobby_players: Label
var _start_button: Button
var _shop: PanelContainer
var _job_board: PanelContainer
var _payout: PanelContainer
var _crew_button: Button
var _voice_button: Button
var _rake_hint: Label
var _voice_panel: PanelContainer
var _settings: PanelContainer
var _settings_backdrop: ColorRect
var _settings_button: Button
var _fps: Label

const _Strings = preload("res://ui/strings.gd")


func _ready() -> void:
	add_to_group("game_ui")
	# The mixer buses exist in every run, so a player's .bus always resolves.
	preload("res://audio/buses.gd").ensure()
	_cleanup = Label.new()
	_cleanup.position = Vector2(16, 16)
	_cleanup.add_theme_color_override("font_shadow_color", Color.BLACK)
	_cleanup.add_theme_constant_override("shadow_offset_x", 1)
	_cleanup.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_cleanup)
	if Net.is_automated():
		hide()
		return
	# Sound for the whole app, menu included (audio/audio_root.gd): UIRoot/Audio/Sfx.
	var audio := preload("res://audio/audio_root.gd").new()
	audio.name = "Audio"
	add_child(audio)
	var quips := preload("res://ui/quip_player.gd").new()
	quips.name = "Quips"
	add_child(quips)
	var cues := preload("res://ui/run_cues.gd").new()
	cues.name = "RunCues"
	add_child(cues)
	var prompt := preload("res://ui/interaction_prompt.gd").new()
	prompt.name = "InteractionPrompt"
	add_child(prompt)
	_rake_hint = Label.new()
	_rake_hint.text = _Strings.UI["hud_rake_hint"]
	_rake_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_rake_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_rake_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rake_hint.position.y -= 34.0
	_rake_hint.add_theme_font_size_override("font_size", 15)
	_rake_hint.modulate = Color(1.0, 1.0, 1.0, 0.75)
	_rake_hint.add_theme_color_override("font_shadow_color", Color.BLACK)
	_rake_hint.add_theme_constant_override("shadow_offset_x", 1)
	_rake_hint.add_theme_constant_override("shadow_offset_y", 1)
	_rake_hint.visible = false
	add_child(_rake_hint)
	var heat := preload("res://ui/heat_meter.gd").new()
	heat.name = "HeatMeter"
	add_child(heat)
	var goal := preload("res://ui/job_goal.gd").new()
	goal.name = "JobGoal"
	add_child(goal)
	var meter := preload("res://ui/throw_meter.gd").new()
	meter.name = "ThrowMeter"
	add_child(meter)
	var task_list := preload("res://ui/task_list.gd").new()
	task_list.name = "TaskList"
	add_child(task_list)
	# The spine (docs/SPINE.md): the clock and rank, the day's summary, the phone.
	var day_hud := preload("res://ui/day_hud.gd").new()
	day_hud.name = "DayHud"
	add_child(day_hud)
	var summary := preload("res://ui/day_summary.gd").new()
	summary.name = "DaySummary"
	add_child(summary)
	var phone := preload("res://ui/phone.gd").new()
	phone.name = "Phone"
	add_child(phone)
	%HostButton.pressed.connect(_on_host_pressed)
	var dev_host := Button.new()
	dev_host.text = "Dev host (ENet)"
	dev_host.pressed.connect(_on_dev_host_pressed)
	%Menu.get_node("Panel").add_child(dev_host)
	_build_lobby()
	_build_store()
	_build_payout()
	Campaign.payout_ready.connect(_on_payout)
	%JoinButton.pressed.connect(_on_join_pressed)
	%QuitButton.pressed.connect(_on_quit_pressed)
	%BackButton.pressed.connect(_show_menu)
	_leave.pressed.connect(_on_leave_pressed)
	_crew_button = Button.new()
	_crew_button.text = "Call the NICE BOYS"
	_crew_button.visible = false
	_crew_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_crew_button.offset_left = -110.0
	_crew_button.offset_right = 110.0
	_crew_button.offset_top = -112.0
	_crew_button.offset_bottom = -72.0
	_crew_button.pressed.connect(_on_call_crew_pressed)
	add_child(_crew_button)
	_voice_panel = preload("res://ui/voice_panel.gd").new()
	_voice_panel.name = "VoicePanel"
	add_child(_voice_panel)
	_voice_button = Button.new()
	_voice_button.text = _Strings.UI["voice_button"]
	_voice_button.visible = false
	_voice_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_voice_button.offset_left = -110.0
	_voice_button.offset_right = 110.0
	_voice_button.offset_top = -160.0
	_voice_button.offset_bottom = -120.0
	_voice_button.pressed.connect(func() -> void: _voice_panel.call("open"))
	add_child(_voice_button)
	_build_settings()
	Net.state_changed.connect(_on_state_changed)
	Net.session_ended.connect(_on_session_ended)
	_on_state_changed(Net.current_state())


func _process(_delta: float) -> void:
	if _cleanup == null:
		return
	if _fps != null:
		_fps.visible = bool(Settings.get_value("interface", "show_fps"))
		if _fps.visible:
			_fps.text = _Strings.UI["fps_label"] % roundi(Engine.get_frames_per_second())
	var fields := get_tree().get_nodes_in_group("leaf_field")
	if fields.is_empty() or Net.current_state() != Net.State.IN_SESSION:
		_cleanup.visible = false
		return
	_cleanup.visible = true
	var fraction: float = fields[0].call("cleaned_fraction")
	var truck_line := ""
	var chefty := get_tree().get_first_node_in_group("chefty")
	if chefty != null:
		truck_line = "\nChefty %d/%d bags" % [int(chefty.call("bag_count")), Constants.TRUCK_BAG_CAPACITY]
	var crew_line := ""
	var director := get_tree().get_first_node_in_group("run_director")
	if director != null:
		var status := str(director.call("status_line"))
		if status != "":
			crew_line = "\n" + status
	var crossing := get_tree().get_first_node_in_group("border_return")
	if crossing != null:
		var crossing_status := str(crossing.call("status_line"))
		if crossing_status != "":
			crew_line += "\n" + crossing_status
	crew_line += _voice_line()
	# What E does is shown over the thing itself (ui/interaction_prompt.gd), so the HUD stays short.
	if _rake_hint != null:
		_rake_hint.visible = Net.player_zone(Net.local_peer_id()) == Net.Zone.LOT
	_cleanup.text = (str(_Strings.UI["hud_wallet"]) % Campaign.credits(Net.local_peer_id())) + "\nCleanup %.1f%%%s%s" % [
		fraction * 100.0,
		truck_line,
		crew_line,
	]
	if _lobby != null and _lobby.visible:
		var lines: PackedStringArray = PackedStringArray()
		for peer_id: int in Net.peer_ids():
			var ready := "ready" if Net.is_player_ready(peer_id) else "not ready"
			var talking: String = _Strings.UI["lobby_talking"] if Net.is_player_speaking(peer_id) else ""
			lines.append("%s  %s%s" % [Net.player_name(peer_id), ready, talking])
		_lobby_players.text = "\n".join(lines)
		_start_button.visible = Net.is_host()


## "Talking" while this player's voice is going out, or the push-to-talk hint,
## after a line saying so while hiding.
func _voice_line() -> String:
	var line := ""
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()) and bool(node.call("is_hidden")):
			line = "\n" + str(_Strings.UI["hud_hidden"])
	if not Net.voice_available():
		return line
	return line + _voice_part()


func _voice_part() -> String:
	if Net.is_player_speaking(Net.local_peer_id()):
		return "\n" + str(_Strings.UI["hud_talking"])
	if Net.voice_mode() == Net.VoiceMode.PUSH_TO_TALK:
		return "\n" + str(_Strings.UI["hud_push_to_talk"])
	return ""


func _unhandled_input(event: InputEvent) -> void:
	if Net.is_automated() or not event.is_action_pressed("pause"):
		return
	if Net.current_state() == Net.State.OFFLINE:
		return
	if _leave.visible:
		close_pause()
	else:
		open_pause()
	get_viewport().set_input_as_handled()


## The pause buttons: Leave Session, Voice, Settings, and (for the host) the NICE BOYS.
func open_pause() -> void:
	if Net.is_automated() or Net.current_state() != Net.State.IN_SESSION:
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_leave.visible = true
	_voice_button.visible = true
	_settings_button.visible = true
	if _crew_button != null:
		_crew_button.visible = Net.is_host()


func close_pause() -> void:
	_hide_pause_buttons()
	recapture_mouse()


func _hide_pause_buttons() -> void:
	_leave.visible = false
	if _voice_button != null:
		_voice_button.visible = false
		_voice_panel.visible = false
	if _settings_button != null:
		_settings_button.visible = false
	if _crew_button != null:
		_crew_button.visible = false


## The Settings window (ui/settings_window.gd), from the main menu, the lobby, or
## the pause buttons (from_pause: the pause buttons step aside and come back when
## it closes). tab is one of its TABS.
func open_settings(from_pause := false, tab := "sound") -> void:
	if _settings == null:
		return
	if from_pause:
		_hide_pause_buttons()
	_settings.call("open", tab, from_pause)


func close_settings() -> void:
	if _settings != null:
		_settings.call("close_window")


func _on_settings_closed() -> void:
	if bool(_settings.get("from_pause")) and Net.current_state() == Net.State.IN_SESSION:
		open_pause()
	else:
		recapture_mouse()


## Closes the window without bringing the pause buttons back (the state changed).
func _dismiss_settings() -> void:
	if _settings != null and _settings.visible:
		_settings.set("from_pause", false)
		_settings.call("close_window")


## The window and its backdrop come last, so they draw over the HUD and catch
## keys first; the buttons that open it sit in the main menu (above Quit), the
## lobby and the pause stack (above Voice). The FPS counter is top center
## (critic.md C7: the corners belong to the day HUD and rank badge).
func _build_settings() -> void:
	var menu_button := Button.new()
	menu_button.text = _Strings.UI["menu_settings"]
	menu_button.pressed.connect(func() -> void: open_settings())
	var panel := %Menu.get_node("Panel")
	panel.add_child(menu_button)
	panel.move_child(menu_button, (%QuitButton as Node).get_index())
	var lobby_button := Button.new()
	lobby_button.text = _Strings.UI["lobby_settings"]
	lobby_button.pressed.connect(func() -> void: open_settings())
	_lobby.add_child(lobby_button)
	_lobby.move_child(lobby_button, _start_button.get_index())
	_settings_button = Button.new()
	_settings_button.text = _Strings.UI["pause_settings"]
	_settings_button.visible = false
	_settings_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_settings_button.offset_left = -110.0
	_settings_button.offset_right = 110.0
	_settings_button.offset_top = -208.0
	_settings_button.offset_bottom = -168.0
	_settings_button.pressed.connect(func() -> void: open_settings(true))
	add_child(_settings_button)
	_fps = Label.new()
	_fps.visible = false
	_fps.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_fps.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_fps.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fps.offset_top = 4.0
	_fps.add_theme_font_size_override("font_size", 13)
	_fps.add_theme_color_override("font_shadow_color", Color.BLACK)
	_fps.add_theme_constant_override("shadow_offset_x", 1)
	_fps.add_theme_constant_override("shadow_offset_y", 1)
	_fps.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fps)
	_settings_backdrop = ColorRect.new()
	_settings_backdrop.name = "SettingsBackdrop"
	_settings_backdrop.color = Color(0.0, 0.0, 0.0, 0.45)
	_settings_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings_backdrop.visible = false
	add_child(_settings_backdrop)
	_settings = preload("res://ui/settings_window.gd").new()
	_settings.name = "SettingsWindow"
	_settings.set("backdrop", _settings_backdrop)
	add_child(_settings)
	_settings.connect("closed", _on_settings_closed)


## Tabbing out of the game pauses it on purpose, so the mouse is yours and
## coming back shows where you are. (Not while an agent plays by remote.)
func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_OUT or _leave == null:
		return
	if str(Net.dev_options().get("remote_play")) != "" or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	open_pause()


func _build_lobby() -> void:
	_lobby = VBoxContainer.new()
	_lobby.position = Vector2(460, 180)
	_lobby.visible = false
	_lobby.add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "Lobby"
	_lobby_players = Label.new()
	var ready := Button.new()
	ready.text = "Ready"
	ready.pressed.connect(func() -> void: Net.set_ready(not Net.is_player_ready(Net.local_peer_id())))
	var invite := Button.new()
	invite.text = "Invite Friends"
	invite.pressed.connect(func() -> void: Net.invite_friends())
	_start_button = Button.new()
	_start_button.text = "Start"
	_start_button.pressed.connect(func() -> void: Net.start_session())
	var leave := Button.new()
	leave.text = "Leave Session"
	leave.pressed.connect(_on_leave_pressed)
	var voice := Button.new()
	voice.text = _Strings.UI["voice_button"]
	voice.pressed.connect(func() -> void: _voice_panel.call("open"))
	_lobby.add_child(title)
	_lobby.add_child(_lobby_players)
	_lobby.add_child(ready)
	_lobby.add_child(invite)
	_lobby.add_child(voice)
	_lobby.add_child(_start_button)
	_lobby.add_child(leave)
	add_child(_lobby)


## Whether any window that wants the mouse is up: the shop, the job board, a
## receipt, the day's summary, the phone, Settings, or the pause buttons.
func any_window_open() -> bool:
	for window: Control in [_shop, _job_board, _payout, _leave, _settings]:
		if window != null and window.visible:
			return true
	for group: String in ["phone", "day_summary"]:
		var node := get_tree().get_first_node_in_group(group) as Control
		if node != null and node.visible:
			return true
	return false


## A window closed: take the mouse back for looking around, unless another one is still up.
func recapture_mouse() -> void:
	if Net.current_state() == Net.State.IN_SESSION and not any_window_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func open_store() -> void:
	_shop.call("open")


## Once someone's looked at the job board, the goal line stops pointing at the phone.
var board_seen: bool = false


func open_job_board() -> void:
	board_seen = true
	if _job_board != null:
		_job_board.call("open")


func _build_store() -> void:
	_shop = preload("res://ui/shop_window.gd").new()
	_shop.name = "ShopWindow"
	add_child(_shop)
	_job_board = preload("res://ui/job_board_window.gd").new()
	_job_board.name = "JobBoardWindow"
	add_child(_job_board)
	# The clerk reacts when you buy something.
	_shop.connect("bought", func(_item_id: StringName) -> void:
		var clerk := get_tree().get_first_node_in_group("store_clerk")
		if clerk != null:
			clerk.call("say_line", "buy")
	)


func _build_payout() -> void:
	_payout = preload("res://ui/payout_window.gd").new()
	_payout.name = "PayoutWindow"
	add_child(_payout)


func _on_payout(results: Array[Dictionary]) -> void:
	_payout.call("show_payout", results, Campaign.last_settlement())


func _on_host_pressed() -> void:
	Net.set_local_name(_name_field.text)
	if not Net.steam_available():
		_show_ended(Net.steam_unavailable_reason())
		return
	var error := Net.host(Net.Transport.STEAM)
	if error != OK:
		_show_ended("Could not host: %s" % error_string(error))


func _on_dev_host_pressed() -> void:
	Net.set_local_name(_name_field.text)
	var error := Net.host(Net.Transport.ENET)
	if error != OK:
		_show_ended("Could not host: %s" % error_string(error))


func _on_join_pressed() -> void:
	Net.set_local_name(_name_field.text)
	var error := Net.join_enet(_address_field.text.strip_edges())
	if error != OK:
		_show_ended("Could not join: %s" % error_string(error))


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_call_crew_pressed() -> void:
	var director := get_tree().get_first_node_in_group("run_director")
	if director != null and Net.is_host():
		director.call("force_event")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_hide_pause_buttons()


func _on_leave_pressed() -> void:
	Net.leave()
	_show_menu()


func _on_state_changed(next_state: Net.State) -> void:
	_ended.visible = false
	_connecting.visible = next_state == Net.State.CONNECTING
	_menu.visible = next_state == Net.State.OFFLINE
	if _lobby != null:
		_lobby.visible = next_state == Net.State.LOBBY
	_dismiss_settings()
	_hide_pause_buttons()
	if next_state == Net.State.IN_SESSION:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_session_ended(reason: String) -> void:
	_show_ended(reason)


func _show_menu() -> void:
	_ended.visible = false
	_connecting.visible = false
	_menu.visible = true
	if _lobby != null:
		_lobby.visible = false
	_dismiss_settings()
	_leave.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _show_ended(reason: String) -> void:
	_menu.visible = false
	_connecting.visible = false
	_dismiss_settings()
	_leave.visible = false
	_ended_reason.text = reason
	_ended.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
