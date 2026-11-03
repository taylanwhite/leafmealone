extends Node

## Local presentation. The buttons' sounds (gap-specs/audio.json chunk 5;
## docs/GAME.md "UI, store, phone and day sounds"): every BaseButton in the app,
## the ones there now and every one added later, and every slider. A child of
## UIRoot/Audio (audio/audio_root.gd), alive for the whole app.
##   a press           ui_click (a toggle-mode button: ui_tab)
##   the pointer over  ui_hover, very quiet (UI_HOVER_GAP_MS between ticks)
##   a disabled button clicked anyway   ui_deny: the button can't, and says so
##   a slider let go   ui_tick (critic C12: ui_slider is ui_tick)
##   an OptionButton's pick  ui_click
## A button (or any node above it) picks its own with the meta &"ui_sound":
##   &"back"  ui_back (a Close or an X)      &"tab"  ui_tab
##   &"deny"  ui_deny                        &"click" ui_click
##   &"none"  nothing (the window plays its own, like Settings and the phone's dock)
##   any other bank id (&"pin", &"phone_take") plays that id instead of the click
## The nearest meta wins: a button's own over its window's. Plays only on this
## peer, through Sfx.play (2D, the UI bus); nobody else hears your menus.

const _Bank = preload("res://audio/sound_bank.gd")
const META := &"ui_sound"
## Marks a control as hooked, so a button moved between parents isn't hooked twice.
const HOOKED := &"_ui_sounds_hooked"
const KINDS: Dictionary = {&"back": "ui_back", &"tab": "ui_tab", &"deny": "ui_deny", &"click": "ui_click"}


func _ready() -> void:
	for found: Node in get_tree().root.find_children("*", "Control", true, false):
		_hook(found)
	get_tree().node_added.connect(_hook)


## The sound a press of button makes, "" for none (a pure function of its metas,
## for the test).
static func press_id(button: BaseButton) -> String:
	var kind := _meta_of(button)
	if kind == &"none":
		return ""
	if KINDS.has(kind):
		return str(KINDS[kind])
	if kind != &"" and _Bank.has(String(kind)):
		return String(kind)
	return "ui_tab" if button.toggle_mode else "ui_click"


## Whether the pointer passing over control ticks (not inside a "none" window).
static func hovers(control: Control) -> bool:
	return _meta_of(control) != &"none"


## The nearest &"ui_sound" meta: the control's own, else its parents'.
static func _meta_of(control: Node) -> StringName:
	var node := control
	while node != null:
		if node.has_meta(META):
			return StringName(node.get_meta(META))
		node = node.get_parent()
	return &""


func _hook(node: Node) -> void:
	if not (node is BaseButton or node is Slider) or node.has_meta(HOOKED):
		return
	node.set_meta(HOOKED, true)
	var control := node as Control
	control.mouse_entered.connect(func() -> void: _hover(control))
	if node is Slider:
		(node as Slider).drag_ended.connect(func(changed: bool) -> void:
			if changed and hovers(control):
				_play("ui_tick")
		)
		return
	var button := node as BaseButton
	button.pressed.connect(func() -> void: _play(press_id(button)))
	button.gui_input.connect(func(event: InputEvent) -> void: _maybe_deny(button, event))
	if node is OptionButton:
		(node as OptionButton).item_selected.connect(func(_index: int) -> void:
			if hovers(control):
				_play("ui_click")
		)


func _hover(control: Control) -> void:
	if not control.is_visible_in_tree() or not hovers(control):
		return
	if control is BaseButton and (control as BaseButton).disabled:
		return
	_play("ui_hover")


## A click on a greyed-out button: it can't, and it says so with a dull 'bup-bup'
## (no words: the button already looks it).
func _maybe_deny(button: BaseButton, event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if button.disabled and hovers(button):
		_play("ui_deny")


func _play(id: String) -> void:
	if id == "":
		return
	var sfx := get_tree().get_first_node_in_group("sfx") if is_inside_tree() else null
	if sfx != null:
		sfx.call("play", id)
