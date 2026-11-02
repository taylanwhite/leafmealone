extends RefCounted

## Local presentation. The one place a key binding becomes text ("E", "Left
## click", "Wheel up"), read straight from the live InputMap, so it follows
## rebinding (core/settings.gd); an explicit slot reads Settings' slots when the
## autoload is there. Strings.keyed() and the
## icons (ui/icons.gd key_id) both read it. Static only.

const _Strings = preload("res://ui/strings.gd")


## The label of one of action's bindings. slot -1 (the default) is the first
## bound key or button, which is what a prompt names; 0 and 1 are the Settings
## slots the Keys tab shows (an empty slot 0 reads unbound even when slot 1 is
## bound), or the InputMap's events in order for an action Settings doesn't
## keep. An action with nothing bound reads Strings.UI["key_unbound"].
static func label(action: StringName, slot := -1) -> String:
	if not InputMap.has_action(action):
		return _Strings.UI["key_unbound"]
	if slot >= 0:
		var settings := _settings()
		if settings != null and bool(settings.call("has_slots", action)):
			var code := str(settings.call("binding", action, slot))
			var event: InputEvent = settings.call("code_to_event", code) if code != "" else null
			return event_label(event) if event != null else _Strings.UI["key_unbound"]
	var events: Array[InputEvent] = []
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey or event is InputEventMouseButton:
			events.append(event)
	if events.is_empty():
		return _Strings.UI["key_unbound"]
	if slot < 0:
		return event_label(events[0])
	if slot >= events.size():
		return _Strings.UI["key_unbound"]
	return event_label(events[slot])


## The Settings autoload, or null (a tool script, or before autoloads exist).
static func _settings() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var node := tree.root.get_node_or_null("Settings")
	return node if node != null and node.has_method("has_slots") else null


## A key or mouse button event as a player reads it. Keys are physical (the
## same spot on every layout), shown as the letter the player's layout puts there.
static func event_label(event: InputEvent) -> String:
	if event is InputEventMouseButton:
		var key := "key_mouse_%d" % (event as InputEventMouseButton).button_index
		return str(_Strings.UI.get(key, _Strings.UI["key_unbound"]))
	if event is InputEventKey:
		var key_event := event as InputEventKey
		var physical := key_event.physical_keycode
		var code := key_event.keycode if physical == KEY_NONE else physical
		if code == KEY_NONE:
			return _Strings.UI["key_unbound"]
		var text := ""
		# Headless has no keyboard layout (and complains if asked); then, or when
		# the layout has nothing there, the physical key's own name.
		if physical != KEY_NONE and DisplayServer.get_name() != "headless":
			var on_layout := DisplayServer.keyboard_get_keycode_from_physical(physical)
			if on_layout != KEY_NONE:
				text = OS.get_keycode_string(on_layout)
		if text == "":
			text = OS.get_keycode_string(code)
		if text == "":
			return _Strings.UI["key_unbound"]
		return str(_Strings.KEY_NAMES.get(text, text))
	return _Strings.UI["key_unbound"]
