extends Control

## Authority: local, cosmetic. One small "[E]  Hide" pill floating over whatever
## interact would act on right now (docs/FEEL.md, "How characters play"), in
## place of instructions in the HUD. The local player decides first
## (player.gd interaction_hint), then anything in the "prompt_sources" group that
## the player is standing in (job posts, zone gates, the store clerk).
##
## It lives in screen space (icons chunk F): a dark rounded pill whose key is a
## keycap image (ui/icons.gd), drawn at the point the hint names, projected
## through this peer's camera every frame after the camera has moved. It hides
## when that point is behind the camera, while a window is open, and while the
## moment has you (ui/hud_mode.gd, through current_hint). It never pops: it fades
## and grows in, fades out where it was, bumps when its words change, and glides
## (never jumps) from one thing to the next.
##
## Camera3D.unproject_position already answers in canvas units under the
## canvas_items stretch, UI scale included (it measures get_visible_rect(), which
## the root window's content_scale_factor shrinks), so the point is used as is:
## dividing by content_scale_factor (gap-specs/critic.md C8) would misplace it at
## any UI scale but 1.0. icons_test checks it at three scales.

const _Strings = preload("res://ui/strings.gd")
const _HudMode = preload("res://ui/hud_mode.gd")
const _Icons = preload("res://ui/icons.gd")
const _Overheads = preload("res://ui/overheads.gd")

# The pill's look (presentation, not tuning).
const PILL_COLOR := Color(0.08, 0.07, 0.08, 0.72)
const PILL_RADIUS: int = 10
const PILL_MARGIN := Vector2(10, 6)
const TEXT_COLOR := Color(1.0, 0.97, 0.88)
const FONT_SIZE: int = 22

## What the prompt offers now as plain text ("" when nothing): the hint, not the
## pill's fade or whether its point is on screen. For tests.
var current_text: String = ""

var _pill: PanelContainer
var _label: RichTextLabel
## The bbcode the label holds, so it is only set when it changes.
var _shown_rich: String = ""
## 0 hidden .. 1 fully up.
var _alpha: float = 0.0
## Whether the last change was toward showing (the grow-in) or away (the fade-out).
var _rising: bool = false
## The world point it is over (kept while it fades out, so it fades where it was).
var _at := Vector3.ZERO
var _has_at: bool = false
## Screen offset easing back to zero after the anchor jumped to another thing.
var _glide := Vector2.ZERO
## Where the pill's center was drawn last frame.
var _last_center := Vector2.ZERO
var _bump: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# After the players and cameras have moved, so it sits on this frame's view.
	process_priority = 1000
	_pill = PanelContainer.new()
	_pill.name = "Pill"
	_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = PILL_COLOR
	box.set_corner_radius_all(PILL_RADIUS)
	box.content_margin_left = PILL_MARGIN.x
	box.content_margin_right = PILL_MARGIN.x
	box.content_margin_top = PILL_MARGIN.y
	box.content_margin_bottom = PILL_MARGIN.y
	box.anti_aliasing = true
	_pill.add_theme_stylebox_override("panel", box)
	add_child(_pill)
	_label = RichTextLabel.new()
	_label.name = "Text"
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.scroll_active = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	_label.add_theme_color_override("default_color", TEXT_COLOR)
	_pill.add_child(_label)
	_pill.visible = false


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	var hint: Dictionary = {}
	if camera != null and Net.current_state() == Net.State.IN_SESSION and not _window_open():
		hint = _current_hint()
	present(hint, camera, delta)


## One frame of the pill for a hint ({} for none) seen through a camera. _process
## feeds it the live hint; icons_test feeds it its own with processing off.
func present(hint: Dictionary, camera: Camera3D, delta: float) -> void:
	var want := 0.0
	current_text = text_for(hint) if not hint.is_empty() else ""
	if camera != null and not hint.is_empty() and _in_view(camera, hint["at"] as Vector3):
		want = 1.0
		_show(hint, camera)
	if want > _alpha:
		_rising = true
		_alpha = minf(want, _alpha + delta / Constants.ICONS_PROMPT_FADE_IN)
	elif want < _alpha:
		_rising = false
		_alpha = maxf(want, _alpha - delta / Constants.ICONS_PROMPT_FADE_OUT)
	if _alpha <= 0.0 or camera == null or not _has_at or not _Overheads.in_front(camera, _at):
		# Fading out over a point that has gone behind you: gone at once, there's
		# nowhere on screen left to fade.
		_alpha = 0.0
		_pill.visible = false
		return
	_glide *= exp(-Constants.ICONS_PROMPT_GLIDE_RATE * delta)
	_bump *= exp(-Constants.ICONS_PROMPT_BUMP_RATE * delta)
	_place(screen_point(camera, _at) + _glide)
	_pill.visible = true


## A hint to show this frame: new words bump the pill, a new anchor makes it glide.
func _show(hint: Dictionary, camera: Camera3D) -> void:
	var rich := rich_for(hint)
	var at := hint["at"] as Vector3
	if _alpha <= 0.0 or not _has_at:
		# Coming up from nothing: straight onto its spot, no glide from the last one.
		_glide = Vector2.ZERO
		_bump = 0.0
	else:
		if at.distance_to(_at) > Constants.ICONS_PROMPT_RETARGET_M:
			_glide = _last_center - screen_point(camera, at)
		if rich != _shown_rich:
			_bump = Constants.ICONS_PROMPT_BUMP
	if rich != _shown_rich:
		_shown_rich = rich
		_label.text = rich
	_at = at
	_has_at = true


## Whether a hint's point is where the pill can sit over it: in front of the
## camera and close enough to the screen that the pill, centered on it, would
## still be at least partly on screen. Past that it fades out rather than
## pinning itself to an edge (into the HUD's corners) over nothing you can see;
## inside it, the pill is pushed fully onto the screen.
func _in_view(camera: Camera3D, at: Vector3) -> bool:
	if not _Overheads.in_front(camera, at):
		return false
	var half := _pill.get_combined_minimum_size() * 0.5
	var view := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).grow_individual(half.x, half.y, half.x, half.y)
	return view.has_point(screen_point(camera, at))


## Centers the pill on a screen point, kept inside the screen, with the
## grow-in, fade and bump.
func _place(center: Vector2) -> void:
	var size := _pill.get_combined_minimum_size()
	_pill.size = size
	_pill.pivot_offset = size * 0.5
	var view := get_viewport().get_visible_rect().size
	var edge := Constants.ICONS_PROMPT_EDGE_PX
	var top_left := center - size * 0.5
	top_left.x = clampf(top_left.x, edge, maxf(edge, view.x - size.x - edge))
	top_left.y = clampf(top_left.y, edge, maxf(edge, view.y - size.y - edge))
	_pill.position = top_left.round()
	_last_center = top_left + size * 0.5
	var grow := _ease_out_back(_alpha) if _rising else _alpha
	var scale_now := lerpf(Constants.ICONS_PROMPT_APPEAR_SCALE, 1.0, grow) + _bump
	_pill.scale = Vector2.ONE * scale_now
	_pill.modulate.a = _alpha


## Where a world point is on this canvas (see the header on UI scale).
static func screen_point(camera: Camera3D, at: Vector3) -> Vector2:
	return camera.unproject_position(at)


## What a hint reads as in plain text: "[E]  Hide", naming the player's own key.
## The hint's optional "key" is the action that does it (interact when absent; a
## chauffeur or shop prompt may name another, critic.md C8). A hint marked
## "plain" is a notice, not an action, so it gets no key in front, but any
## {key:} tokens in its text still name the player's keys.
static func text_for(hint: Dictionary) -> String:
	return _Strings.keyed(_tokened(hint))


## The same as RichTextLabel markup: the keys are keycaps SIZE_PROMPT_KEY tall.
static func rich_for(hint: Dictionary) -> String:
	return _Icons.rich(_tokened(hint), _Icons.SIZE_PROMPT_KEY)


static func _tokened(hint: Dictionary) -> String:
	var text := str(hint.get("text", ""))
	if not bool(hint.get("plain", false)):
		text = _Strings.UI["prompt_format"] % [str(hint.get("key", "interact")), text]
	# A key alone ("just the key over the thing") carries no trailing gap.
	return text.strip_edges()


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


func _window_open() -> bool:
	var ui := get_tree().get_first_node_in_group("game_ui")
	return ui != null and ui.has_method("any_window_open") and bool(ui.call("any_window_open"))


## 0..1 -> 0..1 with a small overshoot past 1 before it settles (easeOutBack).
static func _ease_out_back(t: float) -> float:
	var u := t - 1.0
	return 1.0 + 2.70158 * u * u * u + 1.70158 * u * u
