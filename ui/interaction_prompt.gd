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
## (never jumps) from one thing to the next. A hint's optional "source" says which
## thing it is over (a node, or any value that names it), so two bags a hand apart
## still glide and a thing moving fast is still followed exactly; a hint with no
## source falls back to "its point jumped more than ICONS_PROMPT_RETARGET_M".
## It steps up out of the way of anyone talking (the NICE BOYS' bubbles from
## ui/overheads.gd, and any Label3D in the AVOID_GROUP: a keeper's or a
## homeowner's caption and name).
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
## Label3Ds in this group (words over someone's head) are kept clear of the pill.
const AVOID_GROUP := "prompt_avoid"

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
## Which thing the last hint was over (identity_of), or null when it didn't say.
var _identity: Variant = null
## Screen offset keeping it clear of words over someone's head, eased.
var _dodge := Vector2.ZERO
## Coming up from nothing: the dodge starts where it's wanted, no glide.
var _dodge_fresh: bool = true
## How far the pill was last pushed to keep it inside the screen (px).
var _edge_shift := Vector2.ZERO


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
	if _window_open():
		# A window takes the screen: the pill goes with the world behind it, at
		# once (a fade would show for a frame or two over the window's edge).
		current_text = ""
		_alpha = 0.0
		_pill.visible = false
		return
	var hint: Dictionary = {}
	if camera != null and Net.current_state() == Net.State.IN_SESSION:
		hint = _current_hint()
	present(hint, camera, delta)


## One frame of the pill for a hint ({} for none) seen through a camera. _process
## feeds it the live hint; icons_test feeds it its own with processing off.
func present(hint: Dictionary, camera: Camera3D, delta: float) -> void:
	var want := 0.0
	current_text = text_for(hint) if not hint.is_empty() else ""
	# R2c hud: a hint whose point is off screen (over the head of someone nose
	# to nose with you, a stamp behind you) isn't drawn hanging at the edge, and
	# none is printed over the job panel, the day and rank or the cash rows:
	# text on text reads as neither (a friend's "Grab" over "Today's job").
	if camera != null and not hint.is_empty() and _in_view(camera, hint["at"] as Vector3) \
			and on_screen(get_viewport(), hint["at"] as Vector3, camera) and not _over_panels(camera, hint["at"] as Vector3):
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
	var settle := exp(-Constants.ICONS_PROMPT_GLIDE_RATE * delta)
	_glide *= settle
	_bump *= exp(-Constants.ICONS_PROMPT_BUMP_RATE * delta)
	var center := screen_point(camera, _at) + _glide
	var dodge := _dodge_for(center, _avoid_rects(camera))
	_dodge = dodge if _dodge_fresh else dodge + (_dodge - dodge) * settle
	_dodge_fresh = false
	# Fading out it goes with its point, off the edge if that's where it's going,
	# rather than being pushed along the edge into the HUD's corners.
	_place(center + _dodge, want > 0.0)
	_pill.visible = true


## A hint to show this frame: new words bump the pill, a new anchor makes it glide.
func _show(hint: Dictionary, camera: Camera3D) -> void:
	var rich := rich_for(hint)
	var at := hint["at"] as Vector3
	var identity: Variant = identity_of(hint)
	if _alpha <= 0.0 or not _has_at:
		# Coming up from nothing: straight onto its spot, no glide from the last one.
		_glide = Vector2.ZERO
		_bump = 0.0
		_dodge_fresh = true
	else:
		# Another thing (by what the hints say they're over, else by the jump):
		# glide over from where it was drawn. The same thing, however fast it
		# moved, is followed exactly.
		var other: bool = identity != _identity if identity != null and _identity != null else at.distance_to(_at) > Constants.ICONS_PROMPT_RETARGET_M
		if other:
			_glide = _last_center - _dodge - screen_point(camera, at)
		if rich != _shown_rich:
			_bump = Constants.ICONS_PROMPT_BUMP
	_identity = identity
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


## Which thing a hint is over and what it offers there, or null when the hint
## has no "source" (a node is named by its instance id).
static func identity_of(hint: Dictionary) -> Variant:
	var source: Variant = hint.get("source")
	if source == null:
		return null
	if source is Object:
		source = (source as Object).get_instance_id()
	return [source, str(hint.get("text", ""))]


## Where words over someone's head are on screen now: the NICE BOYS' bubbles
## (ui/overheads.gd's last rects) and every showing Label3D in AVOID_GROUP.
func _avoid_rects(camera: Camera3D) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var overheads := get_parent().get_node_or_null("Overheads") if get_parent() != null else null
	if overheads != null:
		for entry: Dictionary in overheads.get("last_rects"):
			if str(entry.get("kind")) == "bubble":
				out.append(entry["rect"] as Rect2)
	var view := get_viewport().get_visible_rect().size
	for node: Node in get_tree().get_nodes_in_group(AVOID_GROUP):
		var label := node as Label3D
		if label == null or not label.is_visible_in_tree() or label.text == "" or label.transparency > 0.95:
			continue
		var rect := _Overheads.screen_rect(label, camera, view)
		if rect.size != Vector2.ZERO:
			out.append(rect)
	return out


## How far to move a pill centered here so it sits clear of those rects: up
## above one it would touch, or below it when above would leave the screen.
func _dodge_for(center: Vector2, rects: Array[Rect2]) -> Vector2:
	var size := _pill.get_combined_minimum_size()
	var gap := Constants.ICONS_PROMPT_AVOID_GAP_PX
	var shift := Vector2.ZERO
	for rect: Rect2 in rects:
		var pill := Rect2(center + shift - size * 0.5, size)
		if not pill.intersects(rect.grow(gap)):
			continue
		var up := rect.position.y - gap - pill.end.y
		if pill.position.y + up >= Constants.ICONS_PROMPT_EDGE_PX:
			shift.y += up
		else:
			shift.y += rect.end.y + gap - pill.position.y
	return shift


## Centers the pill on a screen point, kept inside the screen, with the
## grow-in, fade and bump.
func _place(center: Vector2, keep_inside: bool = true) -> void:
	var size := _pill.get_combined_minimum_size()
	_pill.size = size
	_pill.pivot_offset = size * 0.5
	var view := get_viewport().get_visible_rect().size
	var edge := Constants.ICONS_PROMPT_EDGE_PX
	var top_left := center - size * 0.5
	if keep_inside:
		var inside := Vector2(clampf(top_left.x, edge, maxf(edge, view.x - size.x - edge)), clampf(top_left.y, edge, maxf(edge, view.y - size.y - edge)))
		_edge_shift = inside - top_left
	# While fading out the last push stays as it was (no jump), and no new one.
	top_left += _edge_shift
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


func _window_open() -> bool:
	var ui := get_tree().get_first_node_in_group("game_ui")
	return ui != null and ui.has_method("any_window_open") and bool(ui.call("any_window_open"))


## Whether a prompt at this point lands inside the screen (less a margin), in
## front of the camera drawing now (or the one given).
static func on_screen(viewport: Viewport, at: Vector3, through: Camera3D = null) -> bool:
	var camera := through if through != null else viewport.get_camera_3d()
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


func _over_panels(camera: Camera3D, at: Vector3) -> bool:
	var ui := get_tree().get_first_node_in_group("game_ui")
	if camera == null or ui == null:
		return false
	var view := get_viewport().get_visible_rect().size
	var size := _pill.get_combined_minimum_size()
	var rect := Rect2(screen_point(camera, at) - size * 0.5, size)
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


## 0..1 -> 0..1 with a small overshoot past 1 before it settles (easeOutBack).
static func _ease_out_back(t: float) -> float:
	var u := t - 1.0
	return 1.0 + 2.70158 * u * u * u + 1.70158 * u * u
