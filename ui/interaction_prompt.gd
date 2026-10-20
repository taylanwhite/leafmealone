extends Node

## Authority: local, cosmetic. One small "[E]  Hide"-style prompt floating over
## whatever E would act on right now (docs/FEEL.md, "How characters play"), in
## place of instructions in the HUD. The local player decides first
## (player.gd interaction_hint), then anything in the "prompt_sources" group that
## the player is standing in (job posts, zone gates, the store clerk).

const _Strings = preload("res://ui/strings.gd")
## Screen size of the prompt text, independent of distance.
const PIXEL_SIZE: float = 0.0016

var _label: Label3D


func _process(_delta: float) -> void:
	var world := get_tree().get_first_node_in_group("world") as Node3D
	if world == null or Net.current_state() != Net.State.IN_SESSION:
		_hide()
		return
	if _label == null or not is_instance_valid(_label):
		_label = _make_label()
		world.add_child(_label)
	var hint := _current_hint()
	if hint.is_empty():
		_label.visible = false
		return
	_label.text = _Strings.UI["prompt_format"] % str(hint["text"])
	_label.global_position = hint["at"]
	_label.visible = true


func _current_hint() -> Dictionary:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()) and node.has_method("interaction_hint"):
			var hint: Dictionary = node.call("interaction_hint")
			if not hint.is_empty():
				return hint
	for source: Node in get_tree().get_nodes_in_group("prompt_sources"):
		var hint: Dictionary = source.call("prompt")
		if not hint.is_empty():
			return hint
	return {}


func _make_label() -> Label3D:
	var label := Label3D.new()
	label.name = "InteractionPrompt"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.pixel_size = PIXEL_SIZE
	label.font_size = 28
	label.outline_size = 10
	label.modulate = Color(1.0, 0.97, 0.88)
	label.outline_modulate = Color(0.08, 0.07, 0.08)
	label.no_depth_test = true
	label.render_priority = 10
	label.visible = false
	return label


func _hide() -> void:
	if _label != null and is_instance_valid(_label):
		_label.visible = false
