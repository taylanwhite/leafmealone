extends Node

## Authority: owning peer for input; every peer can ask what this player carries.
## The player's side of the hotbar (net/components/hotbar.gd): keys 1 to 5 and
## the scroll wheel pick a slot, pressing the selected number again puts your
## hands away. The selection is predicted here for an instant response (the HUD
## highlight, the tick), but what is actually in hand is the host's call and
## comes back through the props' replicated held_by and pocketed_by, which every
## gameplay check keeps reading. Built on every peer by player.gd; headless-safe.

signal selection_changed(slot: int)
signal refused(reason: String)
signal notice(kind: String)

const _Hotbar = preload("res://net/components/hotbar.gd")
const _SoundBank = preload("res://audio/sound_bank.gd")

## The selected slot, -1 for bare hands. Predicted on the owner; corrected by the
## host (on_selected) and adopted from what's in hand once the prediction is old.
var selected: int = 0

var _player: Node
var _predict_until: int = 0
var _last_hand: Node = null


func _ready() -> void:
	_player = get_parent()


func _peer_id() -> int:
	return _player.name.to_int() if _player != null else 0


func _is_mine() -> bool:
	return _player != null and multiplayer.multiplayer_peer != null and _player.is_multiplayer_authority()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_mine():
		return
	var slot := -2
	var count := _Hotbar.capacity(_peer_id())
	for index: int in count:
		var action := StringName("slot_%d" % (index + 1))
		if InputMap.has_action(action) and event.is_action_pressed(action):
			slot = index
	if event.is_action_pressed(&"slot_next"):
		slot = _step(1)
	elif event.is_action_pressed(&"slot_prev"):
		slot = _step(-1)
	if slot == -2 or _blocked():
		return
	get_viewport().set_input_as_handled()
	select(slot)


## The slot one step along from the selection, wrapping. From bare hands, next is
## the first slot and previous the last.
func _step(direction: int) -> int:
	var count := _Hotbar.capacity(_peer_id())
	if selected < 0:
		return 0 if direction > 0 else count - 1
	return posmod(selected + direction, count)


## Slot keys do nothing while a window has the mouse, or while hidden, in a pile,
## asleep, carried, carrying a teammate, thrown, or winding up a throw.
func _blocked() -> bool:
	var ui := get_tree().get_first_node_in_group("game_ui")
	if ui != null and ui.has_method("any_window_open") and bool(ui.call("any_window_open")):
		return true
	if bool(_player.call("is_hidden")) or bool(_player.call("is_sleeping")):
		return true
	if int(_player.get("carried_by")) != 0 or int(_player.get("carrying")) != 0 or bool(_player.get("thrown")):
		return true
	return float(_player.call("wind_up_seconds")) >= 0.0


## Pick a slot (-1 puts your hands away). Pressing the selected one again also
## puts them away. With both arms full you can't switch: "eh?".
func select(slot: int) -> void:
	if arms_item() != null:
		if _player.has_method("say"):
			_player.call("say", "vo_eh")
		refused.emit("arms_full")
		return
	var target := -1 if slot >= 0 and slot == selected else slot
	selected = target
	_predict_until = Time.get_ticks_msec() + int(Constants.HOTBAR_PREDICT_SECONDS * 1000.0)
	selection_changed.emit(selected)
	_sound("slot_tick")
	var hotbar := get_tree().get_first_node_in_group("hotbar")
	if hotbar != null:
		hotbar.call("request_select", target)


func _process(_delta: float) -> void:
	if not _is_mine():
		return
	var hand := in_hand()
	# Once the prediction is old, what's actually in hand says which slot is selected.
	if Time.get_ticks_msec() >= _predict_until and hand != null and _Hotbar.is_pocketable(str(hand.get("kind"))):
		var slot := int(hand.get("pocket_slot"))
		if slot >= 0 and slot != selected:
			selected = slot
			selection_changed.emit(selected)
	if hand != _last_hand:
		var was := _last_hand
		_last_hand = hand
		if hand != null and is_instance_valid(hand) and _Hotbar.is_pocketable(str(hand.get("kind"))):
			_sound("draw")
		elif hand == null and was != null and is_instance_valid(was) and int(was.get("pocketed_by")) == _peer_id():
			_sound("pocket")


# ---------------------------------------------------------------- queries (every peer)

## capacity entries, each the props in that slot (net/components/hotbar.gd slots_of).
func slots() -> Array:
	return _Hotbar.slots_of(get_tree(), _peer_id())


## The big item in both hands, or null.
func arms_item() -> Node:
	return _Hotbar.arms_item(get_tree(), _peer_id())


## Whatever is in hand, or null.
func in_hand() -> Node:
	return _Hotbar.in_hand(get_tree(), _peer_id())


## The first slot holding this kind, or -1.
func slot_of_kind(kind: String) -> int:
	var all := slots()
	for index: int in all.size():
		var slot: Array = all[index]
		if not slot.is_empty() and str(slot[0].get("kind")) == kind:
			return index
	return -1


## What's in the pockets (not in hand) weighs, in kg, at full weight.
func pocket_weight_kg() -> float:
	var kg := 0.0
	for item: Node in _Hotbar.items_of(get_tree(), _peer_id()):
		if int(item.get("pocketed_by")) == _peer_id() and item.has_method("weight_kg"):
			kg += float(item.call("weight_kg"))
	return kg


## How many things are in the pockets (not in hand).
func pocketed_count() -> int:
	var count := 0
	for item: Node in _Hotbar.items_of(get_tree(), _peer_id()):
		if int(item.get("pocketed_by")) == _peer_id():
			count += 1
	return count


# ---------------------------------------------------------------- from the host (hotbar.gd)

func on_refused(reason: String) -> void:
	if _player != null and _player.has_method("say"):
		_player.call("say", "vo_eh")
	refused.emit(reason)


func on_selected(slot: int) -> void:
	_predict_until = 0
	if slot != selected:
		selected = slot
		selection_changed.emit(selected)


func on_notice(kind: String) -> void:
	notice.emit(kind)


## A local sound, once audio/sound_bank.gd has it (hotbar chunk B adds slot_tick,
## pocket, draw and jangle); silent until then, so no unknown ids get logged.
func _sound(id: String) -> void:
	if not _SoundBank.has(id):
		return
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play", id)
