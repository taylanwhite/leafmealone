extends Node

## Authority: local, cosmetic. One small "[E]  Hide"-style prompt floating over
## whatever interact would act on right now (docs/FEEL.md, "How characters play"), in
## place of instructions in the HUD. The local player decides first
## (player.gd interaction_hint), then anything in the "prompt_sources" group that
## the player is standing in (job posts, zone gates, the store clerk).

const _Strings = preload("res://ui/strings.gd")
const _HudMode = preload("res://ui/hud_mode.gd")
const _Overheads = preload("res://ui/overheads.gd")
## Screen size of the prompt text, independent of distance.
const PIXEL_SIZE: float = 0.0016

var _label: Label3D
## How far the prompt is faded in (0..1).
var _alpha: float = 0.0


func _process(_delta: float) -> void:
	var world := get_tree().get_first_node_in_group("world") as Node3D
	if world == null or Net.current_state() != Net.State.IN_SESSION:
		_hide()
		return
	if _label == null or not is_instance_valid(_label):
		_label = _make_label()
		world.add_child(_label)
	var hint := _current_hint()
	# R2c: a prompt whose spot is off screen (over the head of someone nose to
	# nose with you, a stamp behind you) isn't drawn hanging at the edge.
	if not hint.is_empty() and not on_screen(get_viewport(), hint["at"]):
		hint = {}
	# Nor printed over the job panel, the day and rank, or the cash rows: text on
	# text reads as neither (a friend's "Grab" over "Today's job").
	if not hint.is_empty() and _over_panels(text_for(hint), hint["at"]):
		hint = {}
	# R2c: in and out with a short fade, never popping on or off; a new hint
	# while one shows just takes its place.
	if hint.is_empty():
		_alpha = move_toward(_alpha, 0.0, _delta / Constants.R2C_HUD_PROMPT_FADE)
	else:
		_alpha = move_toward(_alpha, 1.0, _delta / Constants.R2C_HUD_PROMPT_FADE)
		_label.text = text_for(hint)
		_label.global_position = hint["at"]
	_label.transparency = 1.0 - _alpha
	_label.visible = _alpha > 0.0


## What a hint reads as: "[E]  Hide", naming the player's own key. The hint's
## optional "key" is the action that does it (interact when absent; a chauffeur
## or shop prompt may name another, critic.md C8). A hint marked "plain" is a
## notice, not an action, so it gets no key in front, but any {key:} tokens in
## its text still name the player's keys.
static func text_for(hint: Dictionary) -> String:
	var text := str(hint.get("text", ""))
	if not bool(hint.get("plain", false)):
		text = _Strings.UI["prompt_format"] % [str(hint.get("key", "interact")), text]
	return _Strings.keyed(text)


func _current_hint() -> Dictionary:
	return current_hint(get_tree())


## What the prompt shows now ({} for nothing). R2b: while the moment has you
## (ui/hud_mode.gd: held, caught, escorted, in the van) there is no prompt at
## all; in Annex B only the Annex's own (a window's stamp, a bell).
static func current_hint(tree: SceneTree) -> Dictionary:
	var why := _HudMode.reason(tree, Net.local_peer_id())
	if why == &"annex":
		for source: Node in tree.get_nodes_in_group("annex"):
			if source.is_in_group("prompt_sources"):
				var hint: Dictionary = source.call("prompt")
				if not hint.is_empty():
					return hint
		return {}
	if why != &"":
		return {}
	# R2c: not while a stage camera swings you back, nor just after (nothing pops
	# on mid-swing), and not through someone else's camera (a spectator's view:
	# the prompt is about where your own body stands).
	if _HudMode.overlays_held(tree, Net.local_peer_id()) or not own_view(tree):
		return {}
	for node: Node in tree.get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()) and node.has_method("interaction_hint"):
			var hint: Dictionary = node.call("interaction_hint")
			if not hint.is_empty():
				return hint
	for source: Node in tree.get_nodes_in_group("prompt_sources"):
		var hint: Dictionary = source.call("prompt")
		if not hint.is_empty():
			return hint
	return {}


## Whether a prompt at this point lands inside the screen (less a margin), in
## front of the camera drawing now.
static func on_screen(viewport: Viewport, at: Vector3) -> bool:
	var camera := viewport.get_camera_3d()
	if camera == null:
		return true
	if not _Overheads.in_front(camera, at):
		return false
	var view := viewport.get_visible_rect().size
	var px := camera.unproject_position(at)
	var margin := Constants.R2C_HUD_PROMPT_EDGE
	return px.x >= margin and px.y >= margin and px.x <= view.x - margin and px.y <= view.y - margin


## The yard HUD's corner panels a prompt never prints over (UIRoot children).
const PANELS: Array[String] = ["TaskList", "DayHud", "HudRows"]


func _over_panels(text: String, at: Vector3) -> bool:
	var camera := get_viewport().get_camera_3d()
	var ui := get_tree().get_first_node_in_group("game_ui")
	if camera == null or ui == null or _label == null:
		return false
	var view := get_viewport().get_visible_rect().size
	var px := camera.unproject_position(at)
	var size := _Overheads.text_size_px(_label, text, camera, view)
	var rect := Rect2(px - size * 0.5, size)
	for name_of: String in PANELS:
		var panel := ui.get_node_or_null(name_of) as Control
		if panel == null or not panel.is_visible_in_tree() or panel.modulate.a < 0.05:
			continue
		# What's drawn in it, piece by piece (a full-screen holder counts for nothing).
		for child: Node in [panel] + panel.find_children("*", "Control", true, false):
			var control := child as Control
			if not control.is_visible_in_tree() or control.size.x <= 0.0 or control.size.y <= 0.0:
				continue
			var box := control.get_global_rect()
			if box.size.x * box.size.y > view.x * view.y * Constants.R2C_HUD_PANEL_HOLDER_SHARE:
				continue
			if rect.intersects(box):
				return true
	return false


## Whether the camera drawing now is this peer's own (first person, over the
## shoulder or its stage camera), not a spectator's or anyone else's.
static func own_view(tree: SceneTree) -> bool:
	var camera := tree.root.get_viewport().get_camera_3d()
	if camera == null:
		return true
	for node: Node in tree.get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node.is_ancestor_of(camera)
	return true


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
