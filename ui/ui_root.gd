extends CanvasLayer

## Authority: local. Menu, connecting state, and mouse capture for this peer only.

@onready var _menu: Control = %Menu
@onready var _name_field: LineEdit = %NameField
@onready var _address_field: LineEdit = %AddressField
@onready var _connecting: Label = %Connecting
@onready var _ended: Control = %SessionEnded
@onready var _ended_reason: Label = %EndedReason
@onready var _leave: Button = %LeaveButton


func _ready() -> void:
	if Net.is_automated():
		hide()
		return
	%HostButton.pressed.connect(_on_host_pressed)
	%JoinButton.pressed.connect(_on_join_pressed)
	%QuitButton.pressed.connect(_on_quit_pressed)
	%BackButton.pressed.connect(_show_menu)
	_leave.pressed.connect(_on_leave_pressed)
	Net.state_changed.connect(_on_state_changed)
	Net.session_ended.connect(_on_session_ended)
	_on_state_changed(Net.current_state())


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


func _on_host_pressed() -> void:
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
	_leave.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _show_ended(reason: String) -> void:
	_menu.visible = false
	_connecting.visible = false
	_leave.visible = false
	_ended_reason.text = reason
	_ended.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
