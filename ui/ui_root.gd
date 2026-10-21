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

const _Strings = preload("res://ui/strings.gd")


func _ready() -> void:
	add_to_group("game_ui")
	_cleanup = Label.new()
	_cleanup.position = Vector2(16, 16)
	_cleanup.add_theme_color_override("font_shadow_color", Color.BLACK)
	_cleanup.add_theme_constant_override("shadow_offset_x", 1)
	_cleanup.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_cleanup)
	if Net.is_automated():
		hide()
		return
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
	Net.state_changed.connect(_on_state_changed)
	Net.session_ended.connect(_on_session_ended)
	_on_state_changed(Net.current_state())


func _process(_delta: float) -> void:
	if _cleanup == null:
		return
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
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_leave.visible = true
		_voice_button.visible = true
		if _crew_button != null:
			_crew_button.visible = Net.is_host()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_leave.visible = false
		_voice_button.visible = false
		_voice_panel.visible = false
		if _crew_button != null:
			_crew_button.visible = false
	get_viewport().set_input_as_handled()


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


func open_store() -> void:
	_shop.call("open")


func open_job_board() -> void:
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
			clerk.call("chatter")
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
	_leave.visible = false
	if _crew_button != null:
		_crew_button.visible = false


func _on_leave_pressed() -> void:
	Net.leave()
	_show_menu()


func _on_state_changed(next_state: Net.State) -> void:
	_ended.visible = false
	_connecting.visible = next_state == Net.State.CONNECTING
	_menu.visible = next_state == Net.State.OFFLINE
	if _lobby != null:
		_lobby.visible = next_state == Net.State.LOBBY
	_leave.visible = false
	if _voice_button != null:
		_voice_button.visible = false
		_voice_panel.visible = false
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
	_leave.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _show_ended(reason: String) -> void:
	_menu.visible = false
	_connecting.visible = false
	_leave.visible = false
	_ended_reason.text = reason
	_ended.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
