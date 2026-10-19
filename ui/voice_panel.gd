extends PanelContainer

## Authority: local. Voice settings: push-to-talk or open mic, and each other
## player's volume and mute. Volume and mute only change what this player hears.

const _Strings = preload("res://ui/strings.gd")
## Highest volume a slider allows, as a multiple of normal.
const MAX_VOLUME: float = 2.0

var _rows: VBoxContainer
var _unavailable: Label
var _mode: OptionButton


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(420, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var title := Label.new()
	title.text = _Strings.UI["voice_title"]
	box.add_child(title)
	_unavailable = Label.new()
	_unavailable.text = _Strings.UI["voice_unavailable"]
	box.add_child(_unavailable)
	_mode = OptionButton.new()
	_mode.add_item(_Strings.UI["voice_mode_push"], Net.VoiceMode.PUSH_TO_TALK)
	_mode.add_item(_Strings.UI["voice_mode_open"], Net.VoiceMode.VOICE_ACTIVATION)
	_mode.item_selected.connect(func(index: int) -> void:
		Net.set_voice_mode(_mode.get_item_id(index) as Net.VoiceMode)
	)
	box.add_child(_mode)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	box.add_child(_rows)
	var close := Button.new()
	close.text = _Strings.UI["voice_close"]
	close.pressed.connect(func() -> void: visible = false)
	box.add_child(close)
	Net.player_joined.connect(func(_peer_id: int) -> void: _rebuild_if_open())
	Net.player_left.connect(func(_peer_id: int) -> void: _rebuild_if_open())


func open() -> void:
	_unavailable.visible = not Net.voice_available()
	_mode.select(_mode.get_item_index(Net.voice_mode()))
	_rebuild()
	visible = true
	reset_size()
	position = (get_viewport_rect().size - size) * 0.5


func _rebuild_if_open() -> void:
	if visible:
		_rebuild()


func _rebuild() -> void:
	for child: Node in _rows.get_children():
		child.queue_free()
	var others := Net.peer_ids().filter(func(peer_id: int) -> bool: return peer_id != Net.local_peer_id())
	if others.is_empty():
		var nobody := Label.new()
		nobody.text = _Strings.UI["voice_nobody"]
		_rows.add_child(nobody)
		return
	for peer_id: int in others:
		_rows.add_child(_row(peer_id))


func _row(peer_id: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = Net.player_name(peer_id)
	label.custom_minimum_size = Vector2(140, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = MAX_VOLUME
	slider.step = 0.05
	slider.value = Net.player_volume(peer_id)
	slider.custom_minimum_size = Vector2(160, 0)
	slider.value_changed.connect(func(value: float) -> void: Net.set_player_volume(peer_id, value))
	row.add_child(slider)
	var mute := CheckBox.new()
	mute.text = _Strings.UI["voice_mute"]
	mute.button_pressed = Net.is_player_muted(peer_id)
	mute.toggled.connect(func(pressed: bool) -> void: Net.set_player_muted(peer_id, pressed))
	row.add_child(mute)
	return row
