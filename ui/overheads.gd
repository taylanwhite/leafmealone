extends Node

## Authority: local presentation (R2b, docs/GAME.md "What's on screen during the
## encounter"). The words that float over heads: the NICE BOYS' bark bubbles and
## everyone's name tags (players' Nameplate, the crew's and the hired hands'
## Label). Every frame, for this peer's camera:
##
##   - a bubble stays inside the screen (it glides in from an edge instead of
##     being cut off) and wraps as a line, not a column of single words;
##   - a name tag fades out while something solid stands between you and it
##     (a van's wall or roof, a house), while its owner sits in the van, while
##     it would sit on a bubble, and while it would sit on a nearer tag (two
##     heads in a two-shot show one tag, the nearer one).
##
## And for a NICE BOY's bark, present() picks how it shows, ONCE: a bubble over
## him when he's on screen, far enough off and in plain view, else a subtitle on
## the caption stack (captions on, within earshot). Never both.
##
## Tags fade through GeometryInstance3D.transparency, so this never fights the
## alpha their owners set (crew_member._fade_tag, the talking tint).

const _QuipPlayer = preload("res://ui/quip_player.gd")
const _HudMode = preload("res://ui/hud_mode.gd")
## The bark Label3D's look while it's a bubble (font pixels; presentation).
const BUBBLE_LINE_SPACING: float = -4.0
## Anyone else with a Visual/Label tag and a Visual/Bark bubble joins this group.
const SPEAKERS := "overhead_speakers"
## Where a body's head is over its feet (m): walls are checked against it.
const HEAD_HEIGHT: float = 1.55

## What each tag's fade is now (Label3D instance id -> 0..1 shown).
var _shown: Dictionary = {}
## Each bubble's fade for walls (instance id -> 0..1 shown).
var _bubble_shown: Dictionary = {}
## Each bubble's screen-space nudge back inside the screen (instance id -> px).
var _nudge: Dictionary = {}
## Last frame's screen rects, for tests and the recorder: [{kind, rect, alpha}].
var last_rects: Array[Dictionary] = []


func _ready() -> void:
	# After the crew and players have set their own tag alpha this frame.
	# (and after the cameras have moved, so a bubble is placed for this frame's view).
	process_priority = 1000


func _process(delta: float) -> void:
	last_rects.clear()
	var camera := get_viewport().get_camera_3d()
	if camera == null or Net.current_state() != Net.State.IN_SESSION:
		return
	var view := get_viewport().get_visible_rect().size
	var bubbles: Array[Rect2] = []
	for crew: Node in _speakers():
		var bark := crew.get_node_or_null("Visual/Bark") as Label3D
		if bark == null:
			continue
		setup_bubble(bark)
		if not bark.is_visible_in_tree():
			_nudge.erase(bark.get_instance_id())
			_bubble_shown.erase(bark.get_instance_id())
			continue
		var rect := _place_bubble(bark, camera, view, delta)
		if rect.size != Vector2.ZERO:
			bubbles.append(rect)
			last_rects.append({"kind": "bubble", "rect": rect, "alpha": 1.0, "text": bark.text})
	# Tags, nearest first: a nearer tag keeps its place and a farther one that
	# would sit on it steps aside.
	var tags: Array[Dictionary] = []
	for entry: Dictionary in _tags():
		var tag := entry["tag"] as Label3D
		if not tag.is_inside_tree():
			continue
		var depth := camera.global_position.distance_to(tag.global_position)
		tags.append({"tag": tag, "owner": entry["owner"], "hide": bool(entry["hide"]), "depth": depth})
	tags.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["depth"]) < float(b["depth"]))
	var kept: Array[Rect2] = []
	var seen: Dictionary = {}
	# While the moment has you (held, escorted, in the van) nobody's name is
	# needed on screen; in the Annex your crew's names are.
	var why := _HudMode.reason(get_tree(), Net.local_peer_id())
	var staged := why != &"" and why != &"annex"
	for entry: Dictionary in tags:
		var tag := entry["tag"] as Label3D
		setup_tag(tag)
		var id := tag.get_instance_id()
		seen[id] = true
		var want := 1.0
		var rect := Rect2()
		if bool(entry["hide"]) or not tag.visible or staged:
			want = 0.0
		elif not in_front(camera, tag.global_position):
			want = 0.0
		else:
			rect = screen_rect(tag, camera, view)
			if _blocked(tag, entry["owner"] as Node, camera):
				want = 0.0
			else:
				for other: Rect2 in bubbles + kept:
					if rect.grow(Constants.R2B_HUD_TAG_GAP).intersects(other):
						want = 0.0
						break
		var shown := move_toward(float(_shown.get(id, want)), want, delta / Constants.R2B_HUD_TAG_FADE)
		_shown[id] = shown
		tag.transparency = 1.0 - shown
		# Only a tag that's really up holds its place against the farther ones.
		if want > 0.0 and tag.visible and tag.modulate.a > 0.05 and rect.size != Vector2.ZERO:
			kept.append(rect)
			last_rects.append({"kind": "tag", "rect": rect, "alpha": shown * tag.modulate.a, "text": tag.text})
	for id: Variant in _shown.keys():
		if not seen.has(id):
			_shown.erase(id)


## Every name tag in the world now: {tag, owner, hide}. hide: its owner sits in
## the Courtesy Shuttle (the tag would poke through the roof).
func _tags() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var me := str(Net.local_peer_id())
	var shuttle := get_tree().get_first_node_in_group("nice_shuttle")
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == me:
			continue
		var plate := node.get_node_or_null("Visual/Nameplate") as Label3D
		if plate == null:
			continue
		var riding := shuttle != null and shuttle.has_method("seat_info") and not (shuttle.call("seat_info", str(node.name).to_int()) as Dictionary).is_empty()
		out.append({"tag": plate, "owner": node, "hide": riding})
	for group: String in ["nice_crew", "crew_hands", SPEAKERS]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var label := node.get_node_or_null("Visual/Label") as Label3D
			if label == null:
				continue
			out.append({"tag": label, "owner": node, "hide": in_van(node)})
	return out


## Everyone whose Visual/Bark is a bubble: the NICE BOYS, and anything else that
## joins SPEAKERS (the HUD test's stand-ins).
func _speakers() -> Array[Node]:
	var out: Array[Node] = get_tree().get_nodes_in_group("nice_crew")
	out.append_array(get_tree().get_nodes_in_group(SPEAKERS))
	return out


## A NICE BOY sitting in a van (or climbing in or out): his tag stays down.
static func in_van(crew: Node) -> bool:
	if not "mode" in crew or crew.get_script() == null:
		return false
	# Read from his own script (no preload: crew_member.gd preloads this file).
	var modes: Dictionary = (crew.get_script() as Script).get_script_constant_map().get("Mode", {})
	var mode := int(crew.get("mode"))
	# Climbing out too: his tag comes up once he's on the curb.
	for name_of: String in ["SEATED", "HOP_IN", "HOP_OUT"]:
		if modes.has(name_of) and mode == int(modes[name_of]):
			return true
	return false


## Something solid between the camera and a tag's owner (his head, not the tag:
## a tag floats over a van's roof while he sits inside it), him and you aside.
func _blocked(tag: Label3D, owner: Node, camera: Camera3D) -> bool:
	var space := tag.get_world_3d().direct_space_state
	if space == null:
		return false
	var target := tag.global_position
	if owner is Node3D:
		var visual := owner.get_node_or_null("Visual") as Node3D
		var feet := visual.global_position if visual != null else (owner as Node3D).global_position
		target = feet + Vector3.UP * HEAD_HEIGHT
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, target, 1)
	var exclude: Array[RID] = []
	if owner is CollisionObject3D:
		exclude.append((owner as CollisionObject3D).get_rid())
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()) and node is CollisionObject3D:
			exclude.append((node as CollisionObject3D).get_rid())
	query.exclude = exclude
	if not space.intersect_ray(query).is_empty():
		return true
	return through_moving_van(get_tree(), camera.global_position, target)


## Whether the line from one point to another passes through a Courtesy Shuttle
## on the move. A driving van's Solid is off every layer (shuttle._set_solid, so
## it never shoves anyone), so the layer-1 ray misses it; its five boxes are
## tested here instead, or a tag drawn over the world would show through it.
static func through_moving_van(tree: SceneTree, from: Vector3, to: Vector3) -> bool:
	for shuttle: Node in tree.get_nodes_in_group("nice_shuttle"):
		for trip: Node in shuttle.get_children():
			var solid := trip.get_node_or_null("VanLook/Solid") as CollisionObject3D
			if solid == null or solid.collision_layer != 0 or not solid.is_inside_tree():
				continue
			for child: Node in solid.get_children():
				var shape := child as CollisionShape3D
				if shape == null or not (shape.shape is BoxShape3D):
					continue
				var half := (shape.shape as BoxShape3D).size * 0.5
				var into := shape.global_transform.affine_inverse()
				if segment_hits_box(into * from, into * to, half):
					return true
	return false


## A segment against a box centered on the origin (half its size each way): slabs.
static func segment_hits_box(a: Vector3, b: Vector3, half: Vector3) -> bool:
	var enter := 0.0
	var leave := 1.0
	var along := b - a
	for axis: int in 3:
		if absf(along[axis]) < 0.000001:
			if absf(a[axis]) > half[axis]:
				return false
			continue
		var t1 := (-half[axis] - a[axis]) / along[axis]
		var t2 := (half[axis] - a[axis]) / along[axis]
		enter = maxf(enter, minf(t1, t2))
		leave = minf(leave, maxf(t1, t2))
		if enter > leave:
			return false
	return true


# ---------------------------------------------------------------- bubbles

## The bark label as a bubble: a wide line that grows upward from over his
## head (so a second line never runs down onto his name tag).
static func setup_bubble(bark: Label3D) -> void:
	if bark.has_meta("r2b_home"):
		return
	bark.set_meta("r2b_home", bark.position)
	bark.width = Constants.R2B_HUD_BUBBLE_WIDTH
	bark.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bark.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	bark.line_spacing = BUBBLE_LINE_SPACING
	bark.no_depth_test = true
	bark.render_priority = 6


## A name tag drawn over the world: it shows whole or fades whole (walls fade it,
## _blocked), never half cut by a roof edge.
static func setup_tag(tag: Label3D) -> void:
	if tag.has_meta("r2b_tag"):
		return
	tag.set_meta("r2b_tag", true)
	tag.no_depth_test = true
	tag.render_priority = 5


## Puts a showing bubble back over his head, then nudges it (gliding) back
## inside the screen if it would hang off an edge. Returns its screen rect.
func _place_bubble(bark: Label3D, camera: Camera3D, view: Vector2, delta: float) -> Rect2:
	var parent := bark.get_parent() as Node3D
	var home: Vector3 = bark.get_meta("r2b_home", bark.position)
	var anchor := parent.to_global(home) if parent != null else bark.global_position
	if not in_front(camera, anchor):
		bark.position = home
		return Rect2()
	var at := camera.unproject_position(anchor)
	var size := text_size_px(bark, bark.text, camera, view)
	# Bottom-anchored: the text sits above the anchor point, centered on it.
	var rect := Rect2(at.x - size.x * 0.5, at.y - size.y, size.x, size.y)
	var want := clamp_shift(rect, view, Constants.R2B_HUD_SAFE_MARGIN)
	var id := bark.get_instance_id()
	var nudge: Vector2 = _nudge.get(id, want)
	nudge = nudge.lerp(want, 1.0 - exp(-Constants.R2B_HUD_BUBBLE_GLIDE * delta))
	# The glide only ever eases it back over its head; it never hangs off an edge
	# while the view swings.
	nudge += clamp_shift(Rect2(rect.position + nudge, rect.size), view, Constants.R2B_HUD_SAFE_MARGIN)
	_nudge[id] = nudge
	# Screen pixels back to world metres at his distance, along the camera's axes.
	var depth := maxf(0.05, -(camera.global_transform.affine_inverse() * anchor).z)
	var per_px := 2.0 * depth * tan(deg_to_rad(camera.fov) * 0.5) / maxf(1.0, view.y)
	var shift := camera.global_basis.x * nudge.x * per_px - camera.global_basis.y * nudge.y * per_px
	bark.global_position = anchor + shift
	# Drawn over the world (a roof or a tree never cuts a line in half), so it
	# fades out instead while something solid stands between you and him.
	var hidden := _blocked(bark, bark.get_parent().get_parent() if bark.get_parent() != null else null, camera)
	var shown := move_toward(float(_bubble_shown.get(id, 0.0 if hidden else 1.0)), 0.0 if hidden else 1.0, delta / Constants.R2B_HUD_TAG_FADE)
	_bubble_shown[id] = shown
	bark.transparency = 1.0 - shown
	if shown < 0.05:
		return Rect2()
	return Rect2(rect.position + nudge, rect.size)


## How far (px) a rect must move to sit inside the screen less a margin (zero
## when it already does; a rect bigger than the room keeps its top-left in).
static func clamp_shift(rect: Rect2, view: Vector2, margin: float) -> Vector2:
	var shift := Vector2.ZERO
	if rect.position.x < margin:
		shift.x = margin - rect.position.x
	elif rect.end.x > view.x - margin:
		shift.x = maxf(view.x - margin - rect.end.x, margin - rect.position.x)
	if rect.position.y < margin:
		shift.y = margin - rect.position.y
	elif rect.end.y > view.y - margin:
		shift.y = maxf(view.y - margin - rect.end.y, margin - rect.position.y)
	return shift


## A Label3D's text as it lands on screen (px), wrapped at its width. A
## fixed_size label is the same size at any distance.
static func text_size_px(label: Label3D, text: String, camera: Camera3D, view: Vector2) -> Vector2:
	var font := label.font if label.font != null else ThemeDB.fallback_font
	var wrap := label.width if label.autowrap_mode != TextServer.AUTOWRAP_OFF else -1.0
	var px := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, wrap, label.font_size)
	px += Vector2.ONE * float(label.outline_size)
	var world := px * label.pixel_size
	var tan_half := tan(deg_to_rad(camera.fov) * 0.5)
	if label.fixed_size:
		return world * view.y / (2.0 * tan_half)
	var depth := maxf(0.05, camera.global_position.distance_to(label.global_position))
	return world * view.y / (2.0 * depth * tan_half)


## False when `point` is behind the camera or on its near plane, measured with
## the transform unproject_position itself uses (get_camera_transform, which
## physics interpolation can put a tick away from the node's global transform:
## is_position_behind alone let a point at depth 0 through, and unproject then
## threw "p.d == 0" in the soak's bots; R2b integration).
static func in_front(camera: Camera3D, point: Vector3) -> bool:
	if camera.is_position_behind(point):
		return false
	var local := camera.get_camera_transform().affine_inverse() * point
	return -local.z > camera.near


## A Label3D's rect on screen now (centered on its position); empty when it
## isn't in front of the camera.
static func screen_rect(label: Label3D, camera: Camera3D, view: Vector2) -> Rect2:
	if not in_front(camera, label.global_position):
		return Rect2()
	var at := camera.unproject_position(label.global_position)
	var size := text_size_px(label, label.text, camera, view)
	if label.vertical_alignment == VERTICAL_ALIGNMENT_BOTTOM:
		return Rect2(at.x - size.x * 0.5, at.y - size.y, size.x, size.y)
	return Rect2(at - size * 0.5, size)


# ---------------------------------------------------------------- one bark, shown once

## How a NICE BOY's line shows on this peer, decided once when he says it:
## &"bubble" (over him: on screen, in plain view, not in your face), else
## &"subtitle" (the caption stack, with captions on and within earshot), else
## &"bubble" anyway (no captions: the bubble is there if you turn to look).
## Sets the bubble up or pushes the subtitle; never both.
static func present(speaker: Node3D, bark: Label3D, text: String, seconds: float) -> StringName:
	var how := choose(speaker, bark, text)
	if how == &"subtitle":
		if bark != null:
			bark.visible = false
		var stack := speaker.get_tree().get_first_node_in_group("caption_stack")
		if stack != null and stack.has_method("push"):
			stack.call("push", &"subtitle", text, seconds)
	elif bark != null:
		setup_bubble(bark)
		bark.text = text
		bark.visible = true
	return how


static func choose(speaker: Node3D, bark: Label3D, text: String) -> StringName:
	if not speaker.is_inside_tree():
		return &"bubble"
	var camera := speaker.get_viewport().get_camera_3d()
	if camera == null:
		return &"bubble"
	var captions := _QuipPlayer.captions_on()
	var hear := camera.global_position.distance_to(speaker.global_position) <= Constants.CREW_BARK_HEAR_METERS
	if bubble_fits(speaker, bark, text, camera):
		return &"bubble"
	return &"subtitle" if captions and hear else &"bubble"


## Whether his line reads as a bubble from this camera: he's in front, his
## head in the picture, far enough off that the bubble isn't over his face (the
## two-shot), nothing solid between, and the bubble fits above him on screen.
static func bubble_fits(speaker: Node3D, bark: Label3D, text: String, camera: Camera3D) -> bool:
	if bark == null:
		return false
	setup_bubble(bark)
	var parent := bark.get_parent() as Node3D
	var home: Vector3 = bark.get_meta("r2b_home", bark.position)
	var anchor := parent.to_global(home) if parent != null else bark.global_position
	if not in_front(camera, anchor):
		return false
	if camera.global_position.distance_to(anchor) < Constants.R2B_HUD_BUBBLE_MIN_M:
		return false
	var view := speaker.get_viewport().get_visible_rect().size
	var at := camera.unproject_position(anchor)
	var margin := Constants.R2B_HUD_SAFE_MARGIN
	if at.x < margin or at.x > view.x - margin or at.y > view.y - margin:
		return false
	var size := text_size_px(bark, text, camera, view)
	if at.y - size.y < margin:
		return false
	var space := speaker.get_world_3d().direct_space_state
	if space != null:
		var query := PhysicsRayQueryParameters3D.create(camera.global_position, anchor, 1)
		if speaker is CollisionObject3D:
			query.exclude = [(speaker as CollisionObject3D).get_rid()]
		if not space.intersect_ray(query).is_empty():
			return false
	if through_moving_van(speaker.get_tree(), camera.global_position, anchor):
		return false
	return true
