extends CanvasLayer

## Authority: local. Menu, connecting state, and mouse capture for this peer only.

@onready var _menu: Control = %Menu
@onready var _name_field: LineEdit = %NameField
@onready var _address_field: LineEdit = %AddressField
@onready var _connecting: Label = %Connecting
@onready var _ended: Control = %SessionEnded
@onready var _ended_reason: Label = %EndedReason
@onready var _leave: Button = %LeaveButton

## Top-left: [cash] $340, [leaf] 42.0%, [Chefty] 4/50 (on a job), then _status
## for the crew, crossing and voice lines (icons chunk E).
var _hud_rows: VBoxContainer
var _wallet_label: Label
var _cleanup_label: Label
var _chefty_row: Control
var _chefty_label: Label
var _status: Label
var _task_list: Control
var _lobby: VBoxContainer
var _lobby_players: Label
var _start_button: Button
var _shop: PanelContainer
var _job_board: PanelContainer
var _payout: PanelContainer
var _crew_button: Button
var _voice_button: Button
var _voice_panel: PanelContainer
var _settings: PanelContainer
var _settings_backdrop: ColorRect
var _settings_button: Button
var _fps: Label

const _Strings = preload("res://ui/strings.gd")
const _Icons = preload("res://ui/icons.gd")
## The lobby column's width, in UI pixels (presentation).
const LOBBY_WIDTH: float = 320.0
## Where the HUD rows start, and the gap between them and the job list under them.
const HUD_AT := Vector2(16, 16)
const HUD_ROW_GAP: int = 4
const TASK_LIST_GAP: float = 10.0
## The job list never sits higher than this (its old spot, under three rows).
const TASK_LIST_MIN_Y: float = 104.0
## The icons on the pause stack's Call-the-NICE-BOYS and Voice buttons.
const BUTTON_ICON_PX: int = 24


func _ready() -> void:
	add_to_group("game_ui")
	_scene_text()
	# The mixer buses exist in every run, so a player's .bus always resolves.
	preload("res://audio/buses.gd").ensure()
	_build_hud_rows()
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
	var heat := preload("res://ui/heat_meter.gd").new()
	heat.name = "HeatMeter"
	add_child(heat)
	var goal := preload("res://ui/job_goal.gd").new()
	goal.name = "JobGoal"
	add_child(goal)
	var meter := preload("res://ui/throw_meter.gd").new()
	meter.name = "ThrowMeter"
	add_child(meter)
	# The pockets along the bottom (ui/hotbar_hud.gd); the rake's hint lives in its
	# hint line now (critic C6). It hides itself with any window (any_window_open).
	var hotbar := preload("res://ui/hotbar_hud.gd").new()
	hotbar.name = "HotbarHud"
	add_child(hotbar)
	var task_list := preload("res://ui/task_list.gd").new()
	task_list.name = "TaskList"
	add_child(task_list)
	_task_list = task_list
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
	# Chefty's dash while you sit in it (the connected town).
	var drive_hud := preload("res://ui/drive_hud.gd").new()
	drive_hud.name = "DriveHud"
	add_child(drive_hud)
	%HostButton.pressed.connect(_on_host_pressed)
	var dev_host := Button.new()
	dev_host.text = _Strings.UI["menu_dev_host"]
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
	_crew_button.text = _Strings.UI["pause_call_crew"]
	_crew_button.visible = false
	_crew_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_crew_button.offset_left = -110.0
	_crew_button.offset_right = 110.0
	_crew_button.offset_top = -112.0
	_crew_button.offset_bottom = -72.0
	_crew_button.pressed.connect(_on_call_crew_pressed)
	_button_icon(_crew_button, "heat")
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
	_button_icon(_voice_button, "voice")
	add_child(_voice_button)
	_build_settings()
	Net.state_changed.connect(_on_state_changed)
	Net.session_ended.connect(_on_session_ended)
	_on_state_changed(Net.current_state())


func _process(delta: float) -> void:
	if _hud_rows == null:
		return
	if _fps != null:
		_fps.visible = bool(Settings.get_value("interface", "show_fps"))
		if _fps.visible:
			_fps.text = _Strings.UI["fps_label"] % roundi(Engine.get_frames_per_second())
	var fields := get_tree().get_nodes_in_group("leaf_field")
	if fields.is_empty() or Net.current_state() != Net.State.IN_SESSION:
		_hud_rows.visible = false
		return
	_hud_rows.visible = true
	var fraction: float = fields[0].call("cleaned_fraction")
	_set_text(_wallet_label, str(_Strings.UI["cash_amount"]) % Campaign.credits(Net.local_peer_id()))
	_set_text(_cleanup_label, str(_Strings.UI["hud_cleanup_amount"]) % (fraction * 100.0))
	var chefty := get_tree().get_first_node_in_group("chefty")
	_chefty_row.visible = chefty != null
	if chefty != null:
		_set_text(_chefty_label, str(_Strings.UI["hud_chefty_amount"]) % [int(chefty.call("bag_count")), Constants.TRUCK_BAG_CAPACITY])
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
	# What interact does is shown over the thing itself (ui/interaction_prompt.gd), so
	# the HUD stays short. The hiding, push-to-talk and crossing lines name keys with
	# {key:} tokens; the status block is a Label, so they read as "[E]".
	crew_line = _Icons.plain(crew_line.trim_prefix("\n"))
	_status.visible = crew_line != ""
	_set_text(_status, crew_line)
	_follow_task_list(delta)
	if _lobby != null and _lobby.visible:
		var lines: PackedStringArray = PackedStringArray()
		for peer_id: int in Net.peer_ids():
			var ready: String = _Strings.UI["lobby_ready"] if Net.is_player_ready(peer_id) else _Strings.UI["lobby_not_ready"]
			var talking: String = _Strings.UI["lobby_talking"] if Net.is_player_speaking(peer_id) else ""
			lines.append("%s  %s%s" % [Net.player_name(peer_id), ready, talking])
		_lobby_players.text = "\n".join(lines)
		_start_button.visible = Net.is_host()


## The top-left block: three icon rows and the status lines under them. Built in
## automated runs too (hidden with the rest of the UI), so _hud_rows always exists.
func _build_hud_rows() -> void:
	_hud_rows = VBoxContainer.new()
	_hud_rows.name = "HudRows"
	_hud_rows.position = HUD_AT
	_hud_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_rows.add_theme_constant_override("separation", HUD_ROW_GAP)
	add_child(_hud_rows)
	_wallet_label = _hud_label()
	_hud_rows.add_child(_Icons.row("cash", _wallet_label, _Icons.SIZE_HUD))
	_cleanup_label = _hud_label()
	_hud_rows.add_child(_Icons.row("cleanup", _cleanup_label, _Icons.SIZE_HUD))
	_chefty_label = _hud_label()
	# brand_chefty, not item_chefty: the side-on truck is a sliver at 22 px, the
	# chef-hat grille reads.
	_chefty_row = _Icons.row("brand_chefty", _chefty_label, _Icons.SIZE_HUD)
	_chefty_row.visible = false
	_hud_rows.add_child(_chefty_row)
	_status = _hud_label()
	_status.visible = false
	_hud_rows.add_child(_status)


func _hud_label() -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label


## Sets a label's text only when it changed (no relayout every frame).
func _set_text(label: Label, text: String) -> void:
	if label.text != text:
		label.text = text


## The job list sits under the HUD rows, gliding down when a status line appears
## (the NICE BOYS, hiding, talking) and back up when it goes, instead of hiding
## under them or jumping.
func _follow_task_list(delta: float) -> void:
	if _task_list == null:
		return
	var target := maxf(TASK_LIST_MIN_Y, _hud_rows.position.y + _hud_rows.get_combined_minimum_size().y + TASK_LIST_GAP)
	if not _task_list.visible:
		_task_list.position.y = target
		return
	_task_list.position.y = lerpf(_task_list.position.y, target, 1.0 - exp(-Constants.ICONS_HUD_FOLLOW_RATE * delta))


## A small icon on a pause-stack button, left of its words.
func _button_icon(button: Button, id: String) -> void:
	button.icon = _Icons.texture(id)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", BUTTON_ICON_PX)


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


## Whether the pause menu is up (the music director muffles the music then):
## the pause buttons, or the Settings window opened from them (which hides the
## buttons until it closes).
func pause_open() -> bool:
	if _leave != null and _leave.visible:
		return true
	return _settings != null and _settings.visible and bool(_settings.get("from_pause"))


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


## The words the scene used to carry (ui_root.tscn keeps none of its own, so
## every one is in ui/strings.gd).
func _scene_text() -> void:
	(%Menu.get_node("Panel/Title") as Label).text = _Strings.UI["menu_title"]
	_name_field.placeholder_text = _Strings.UI["menu_name_placeholder"]
	(%HostButton as Button).text = _Strings.UI["menu_host_steam"]
	_address_field.placeholder_text = _Strings.UI["menu_address_placeholder"]
	(%JoinButton as Button).text = _Strings.UI["menu_join"]
	(%QuitButton as Button).text = _Strings.UI["menu_quit"]
	_connecting.text = _Strings.UI["menu_connecting"]
	(%BackButton as Button).text = _Strings.UI["menu_back"]
	_leave.text = _Strings.UI["pause_leave"]


func _build_lobby() -> void:
	_lobby = VBoxContainer.new()
	_lobby.name = "Lobby"
	# Centered by anchors, growing both ways, so it stays on screen at every UI
	# scale (Settings interface.ui_scale shrinks the logical screen).
	_lobby.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_lobby.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_lobby.grow_vertical = Control.GROW_DIRECTION_BOTH
	_lobby.custom_minimum_size = Vector2(LOBBY_WIDTH, 0.0)
	_lobby.visible = false
	_lobby.add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = _Strings.UI["lobby_title"]
	_lobby_players = Label.new()
	var ready := Button.new()
	ready.text = _Strings.UI["lobby_ready_button"]
	ready.pressed.connect(func() -> void: Net.set_ready(not Net.is_player_ready(Net.local_peer_id())))
	var invite := Button.new()
	invite.text = _Strings.UI["lobby_invite"]
	invite.pressed.connect(func() -> void: Net.invite_friends())
	_start_button = Button.new()
	_start_button.text = _Strings.UI["lobby_start"]
	_start_button.pressed.connect(func() -> void: Net.start_session())
	var leave := Button.new()
	leave.text = _Strings.UI["lobby_leave"]
	leave.pressed.connect(_on_leave_pressed)
	var voice := Button.new()
	voice.text = _Strings.UI["voice_button"]
	voice.pressed.connect(func() -> void: _voice_panel.call("open"))
	_button_icon(voice, "voice")
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
	open_shop("homie_depot")


## A shop's window (ui/shop_window.gd), on a tab and an item when given (the
## shelves open it on the item you looked at).
func open_shop(shop_id: String, tab: String = "", item: String = "") -> void:
	_shop.call("open_shop", shop_id, tab, item)


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
	# The shop's keeper reacts when you buy something there.
	_shop.connect("bought", func(_item_id: StringName) -> void:
		var shop_id := str(_shop.get("shop_id"))
		for keeper: Node in get_tree().get_nodes_in_group("shopkeepers"):
			if str(keeper.get("shop_id")) == shop_id:
				keeper.call("on_sale")
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
		_show_ended(str(_Strings.UI["error_host"]) % error_string(error))


func _on_dev_host_pressed() -> void:
	Net.set_local_name(_name_field.text)
	var error := Net.host(Net.Transport.ENET)
	if error != OK:
		_show_ended(str(_Strings.UI["error_host"]) % error_string(error))


func _on_join_pressed() -> void:
	Net.set_local_name(_name_field.text)
	var error := Net.join_enet(_address_field.text.strip_edges())
	if error != OK:
		_show_ended(str(_Strings.UI["error_join"]) % error_string(error))


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
