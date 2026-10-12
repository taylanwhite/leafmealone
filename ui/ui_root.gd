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
var _store: VBoxContainer
var _store_label: Label
var _payout: VBoxContainer
var _payout_label: Label


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
	_cleanup.text = "Cleanup %d%%\nHold left click to rake a patch clear. Right click bags a pile." % int(round(fraction * 100.0))
	if _lobby != null and _lobby.visible:
		var lines: PackedStringArray = PackedStringArray()
		for peer_id: int in Net.peer_ids():
			var ready := "ready" if Net.is_player_ready(peer_id) else "not ready"
			lines.append("%s  %s" % [Net.player_name(peer_id), ready])
		_lobby_players.text = "\n".join(lines)
		_start_button.visible = Net.is_host()


func _unhandled_input(event: InputEvent) -> void:
	if Net.is_automated() or not event.is_action_pressed("pause"):
		return
	if Net.current_state() == Net.State.OFFLINE:
		return
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_leave.visible = true
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_leave.visible = false
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
	_lobby.add_child(title)
	_lobby.add_child(_lobby_players)
	_lobby.add_child(ready)
	_lobby.add_child(invite)
	_lobby.add_child(_start_button)
	_lobby.add_child(leave)
	add_child(_lobby)


func open_store() -> void:
	_refresh_store()
	_store.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _build_store() -> void:
	_store = VBoxContainer.new()
	_store.position = Vector2(460, 160)
	_store.visible = false
	_store.add_theme_constant_override("separation", 8)
	_store_label = Label.new()
	var buy := Button.new()
	buy.text = "Buy rake tune-up"
	buy.pressed.connect(func() -> void: Campaign.request_purchase(Campaign.RAKE_UPGRADE))
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func() -> void:
		_store.visible = false
		if Net.current_state() == Net.State.IN_SESSION:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	)
	_store.add_child(_store_label)
	_store.add_child(buy)
	_store.add_child(close)
	add_child(_store)
	Campaign.credits_changed.connect(func(_peer_id: int, _amount: int) -> void:
		if _store.visible:
			_refresh_store()
	)
	Campaign.unlocks_changed.connect(func() -> void:
		if _store.visible:
			_refresh_store()
	)


func _refresh_store() -> void:
	var owned := Campaign.is_unlocked(Campaign.RAKE_UPGRADE)
	var status := "Owned" if owned else "Not owned"
	_store_label.text = "Your credits: %d\nRake tune-up: %d credits\nRaking becomes %.2fx\n%s" % [
		Campaign.credits(Net.local_peer_id()),
		Balance.BASELINE_TIER_1_TOOL_COST,
		Balance.TOOL_THROUGHPUT_GROWTH_MULTIPLIER,
		status,
	]


func _build_payout() -> void:
	_payout = VBoxContainer.new()
	_payout.position = Vector2(380, 120)
	_payout.visible = false
	_payout.add_theme_constant_override("separation", 8)
	_payout_label = Label.new()
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func() -> void: _payout.visible = false)
	_payout.add_child(_payout_label)
	_payout.add_child(close)
	add_child(_payout)


func _on_payout(results: Array[Dictionary]) -> void:
	var lines: PackedStringArray = PackedStringArray(["Payout"])
	for row: Dictionary in results:
		lines.append("%s  leaves %.0f  share %d%%  %d credits" % [
			str(row["name"]),
			float(row["leaves"]),
			int(round(float(row["share"]) * 100.0)),
			int(row["credits"]),
		])
	_payout_label.text = "\n".join(lines)
	_payout.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


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
