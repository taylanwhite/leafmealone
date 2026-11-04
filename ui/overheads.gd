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
##
## p1-ui ("Words hung in the world", docs/GAME.md): the world's signs (SIGNS:
## Chefty's name and load, a gate pad's words) are tags too, in the same
## nearest-first line (Patrice's name in front of Chefty's load shows, the load
## steps aside), always facing you (billboard: never mirrored from behind) and
## never taller than P1_SIGN_LINE_MAX of the view. And every tag and sign fades
## out while its words would touch a screen edge (never cut off) or a HUD panel
## (never printed over the cash rows, the job panel, the clock, the bar), and
## while a stage shot or the van's cabin camera has the view.

const _QuipPlayer = preload("res://ui/quip_player.gd")
const _HudMode = preload("res://ui/hud_mode.gd")
const _TextFit = preload("res://ui/text_fit.gd")
## The bark Label3D's look while it's a bubble (font pixels; presentation).
const BUBBLE_LINE_SPACING: float = -4.0
## Anyone else with a Visual/Label tag and a Visual/Bark bubble joins this group.
const SPEAKERS := "overhead_speakers"
## R2c: things that hide a tag or a bubble behind them without a layer-1 collider
## (a box_size box from their origin up), besides the hiding spots.
const VIEW_BLOCKERS := "overhead_view_blockers"
## Where a body's head is over its feet (m): walls are checked against it.
const HEAD_HEIGHT: float = 1.55
## p1-ui: Label3Ds hung in the world that aren't anyone's name (Chefty's,
## ride.gd and chefty_drive.gd; the gate pads', levels/zone_gate.gd) join this.
const SIGNS := "overhead_signs"
## p1-ui: the UIRoot pieces words in the world keep off (besides the hotbar's own
## rects, ui/hotbar_hud.gd screen_rects).
const HUD_PIECES: Array[String] = ["HudRows", "TaskList", "DayHud", "HeatMeter", "JobGoal", "DriveHud"]
## p1-ui: the cameras that are a moment, not your eyes (player/stage_cam.gd's
## StageCam, props/nice_van.gd's CabinCam rig): no tags or signs while one draws.
const STAGE_CAMERAS: Array[StringName] = [&"StageCam", &"CabinCam"]

## What each tag's fade is now (Label3D instance id -> 0..1 shown).
var _shown: Dictionary = {}
## Each bubble's fade for walls (instance id -> 0..1 shown).
var _bubble_shown: Dictionary = {}
## Each bubble's screen-space nudge back inside the screen (instance id -> px).
var _nudge: Dictionary = {}
## R2c: since when (msec) each tag has had nothing in its way (instance id -> msec).
var _clear_since: Dictionary = {}
## Last frame's screen rects, for tests and the recorder: [{kind, rect, alpha}].
var last_rects: Array[Dictionary] = []
## p1-ui: the HUD panels' screen rects tags and signs kept off last frame (tests).
var last_hud: Array[Rect2] = []
## p1-ui: how many frames running each tag has been heading off the screen or onto
## the HUD (instance id -> frames).
var _heading_off: Dictionary = {}
## R2c: the camera drawn last frame and where it was (bubbles go across a cut).
var _last_camera: int = 0
var _last_view: Transform3D = Transform3D.IDENTITY
## R2c: each tag's screen centre last frame and its velocity on screen (px/s), so
## a tag closing on another fast steps aside early enough (instance id -> value).
var _tag_px: Dictionary = {}
var _tag_vel: Dictionary = {}


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
	var cut := _camera_cut(camera)
	var bubbles: Array[Rect2] = []
	# R2c: bubbles nearest first, so a farther one steps out of a nearer one's way.
	var barks: Array[Dictionary] = []
	for crew: Node in _speakers():
		var bark := crew.get_node_or_null("Visual/Bark") as Label3D
		if bark == null:
			continue
		setup_bubble(bark)
		if not bark.is_visible_in_tree():
			_nudge.erase(bark.get_instance_id())
			_bubble_shown.erase(bark.get_instance_id())
			continue
		barks.append({"bark": bark, "depth": camera.global_position.distance_to(bark.global_position)})
	barks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["depth"]) < float(b["depth"]))
	for entry: Dictionary in barks:
		var bark := entry["bark"] as Label3D
		fit_size(bark, camera, view, Constants.R2C_HUD_BUBBLE_LINE_MIN, Constants.R2C_HUD_BUBBLE_LINE_MAX)
		var rect := _place_bubble(bark, camera, view, delta, bubbles, cut)
		if rect.size != Vector2.ZERO:
			bubbles.append(rect)
			last_rects.append({"kind": "bubble", "rect": rect, "alpha": 1.0 - bark.transparency, "text": bark.text})
	_fit_counts(camera, view)
	# Tags, nearest first: a nearer tag keeps its place and a farther one that
	# would sit on it steps aside.
	var tags: Array[Dictionary] = []
	for entry: Dictionary in _tags():
		var tag := entry["tag"] as Label3D
		if not tag.is_inside_tree():
			continue
		var depth := camera.global_position.distance_to(tag.global_position)
		# R2c: a tag that's up keeps its place unless the other head is clearly
		# nearer (two heads side by side in a two-shot swapped "nearer" every few
		# frames, and the two tags cross-faded over each other).
		var rank := depth - (Constants.R2C_HUD_TAG_KEEP_M if float(_shown.get(tag.get_instance_id(), 0.0)) > 0.5 else 0.0)
		tags.append({"tag": tag, "owner": entry["owner"], "hide": bool(entry["hide"]), "depth": depth, "rank": rank, "sign": bool(entry.get("sign", false))})
	tags.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["rank"]) < float(b["rank"]))
	var kept: Array[Rect2] = []
	var kept_vel: Array[Vector2] = []
	for rect: Rect2 in bubbles:
		kept.append(rect)
		kept_vel.append(Vector2.ZERO)
	var seen: Dictionary = {}
	# While the moment has you (held, escorted, in the van) nobody's name is
	# needed on screen; in the Annex your crew's names are. R2c: nor while the
	# camera swings back to you (hud_mode overlays_held), nor while you're hidden
	# (you look out through leaves; a name over them would give away where he
	# stands, text doing the world's job).
	# p1-ui: nor while a stage shot or the van's cabin camera has the view.
	var staged := _HudMode.overlays_held(get_tree(), Net.local_peer_id()) or _me_hidden() or stage_camera(camera)
	var hud := hud_rects()
	last_hud = hud
	for entry: Dictionary in tags:
		var tag := entry["tag"] as Label3D
		var sign := bool(entry["sign"])
		if sign:
			setup_sign(tag)
		setup_tag(tag)
		var id := tag.get_instance_id()
		seen[id] = true
		var want := 1.0
		var rect := Rect2()
		# A player's tag fades out as you come close (R2c): up close you know who it is.
		# A sign's own fade (ui/near_label.gd: Chefty's up close) counts the same way.
		var near := 1.0
		if entry["owner"] != null and (entry["owner"] as Node).is_in_group("players"):
			near = smoothstep(Constants.R2C_HUD_TAG_NEAR_GONE_M, Constants.R2C_HUD_TAG_NEAR_FULL_M, float(entry["depth"]))
		elif "own_alpha" in tag:
			near = float(tag.get("own_alpha"))
		# R2c: drawn means drawn: a tag whose owner's Visual is hidden (a ghosted
		# observer) is neither shown nor in anyone's way.
		var drawn := tag.is_visible_in_tree()
		var touching := false
		var vel := Vector2.ZERO
		var cap := 1.0
		if bool(entry["hide"]) or not drawn or staged or near <= 0.0:
			want = 0.0
		elif not in_front(camera, tag.global_position):
			want = 0.0
		else:
			# A readable size whatever the lens or the distance (R2c). A sign is only
			# capped (it may shrink with distance like the thing it hangs on); one that
			# sizes itself (ui/near_label.gd) is left to it.
			if not sign:
				fit_size(tag, camera, view, Constants.R2C_HUD_TAG_LINE_MIN, Constants.R2C_HUD_TAG_LINE_MAX)
			elif not ("own_alpha" in tag):
				fit_size(tag, camera, view, 0.0, Constants.P1_SIGN_LINE_MAX)
			rect = screen_rect(tag, camera, view)
			vel = _screen_velocity(id, rect, delta, cut)
			# p1-ui: off the HUD and inside the screen, now and where it's heading (the
			# fade has to be done before it gets there, or a fast turn cut it in half).
			# Heading there for P1_LABEL_AHEAD_FRAMES frames running, so one jerk of the
			# view doesn't blink it.
			var ahead := Rect2(rect.position + vel * Constants.R2B_HUD_TAG_FADE, rect.size)
			var heading := 0 if clear_of_hud(ahead, view, hud) else int(_heading_off.get(id, 0)) + 1
			_heading_off[id] = heading
			var off_hud := clear_of_hud(rect, view, hud) and heading < Constants.P1_LABEL_AHEAD_FRAMES
			# A turn that speeds up gets there sooner than the fade: what's left of
			# it is at most the share of the fade's time still to go before it
			# touches, so it reaches nothing exactly as it arrives (it went 0.63 to
			# gone in one frame on a quick turn).
			# And one creeping up on it is fading by where it is, over the last
			# P1_LABEL_FADE_PX.
			cap = room_share(rect, view, hud)
			if heading >= Constants.P1_LABEL_AHEAD_FRAMES and cap > 0.0:
				cap = minf(cap, time_left_share(rect, vel * Constants.R2B_HUD_TAG_FADE, view, hud))
			# Already over a panel or across an edge: gone at once (never drawn cut off).
			touching = not clear_of_hud(rect, view, hud, 0.0)
			if _blocked(tag, entry["owner"] as Node, camera) or not off_hud:
				want = 0.0
			else:
				# R2c: with room to spare, so a tag closing on another has faded
				# before they touch (the fade used to finish over the other's letters):
				# the faster the two close on screen, the earlier it steps aside.
				for index: int in kept.size():
					var other := kept[index]
					var apart := rect.get_center() - other.get_center()
					var closing := maxf(0.0, -(vel - kept_vel[index]).dot(apart.normalized())) if apart.length() > 0.5 else 0.0
					var lead := minf(Constants.R2C_HUD_TAG_CLEAR_MAX, closing * Constants.R2B_HUD_TAG_FADE)
					if rect.grow(maxf(Constants.R2B_HUD_TAG_GAP, Constants.R2C_HUD_TAG_CLEAR + lead)).intersects(other):
						want = 0.0
						touching = touching or rect.grow(Constants.R2B_HUD_TAG_GAP).intersects(other)
		# R2c: a tag comes back only once it's been clear for a moment, so one
		# grazing a hedge's edge or another tag doesn't blink half on and off.
		var now := Time.get_ticks_msec()
		if want <= 0.0:
			_clear_since.erase(id)
		else:
			if not _clear_since.has(id):
				_clear_since[id] = now
			if float(_shown.get(id, 0.0)) < 0.5 and now - int(_clear_since[id]) < int(Constants.R2C_HUD_TAG_DWELL * 1000.0):
				want = 0.0
		var shown := minf(move_toward(float(_shown.get(id, want)), want, delta / Constants.R2B_HUD_TAG_FADE), cap)
		# Last resort (a cut, a head that jumped): letters never print on letters,
		# even if the fade isn't done.
		if touching:
			shown = 0.0
		_shown[id] = shown
		if "screen_alpha" in tag:
			# A sign that fades itself up close (ui/near_label.gd) takes this on top.
			tag.set("screen_alpha", shown)
		else:
			tag.transparency = 1.0 - shown * near
		# R2c: a tag still fading out holds its place too, so a farther one never
		# fades in through it (two tags printed over each other).
		if drawn and tag.modulate.a > 0.05 and rect.size != Vector2.ZERO and shown * near > 0.05:
			kept.append(rect)
			kept_vel.append(vel)
			last_rects.append({"kind": "sign" if sign else "tag", "rect": rect, "alpha": shown * near * tag.modulate.a, "text": tag.text})
	for id: Variant in _shown.keys():
		if not seen.has(id):
			_shown.erase(id)
			_clear_since.erase(id)
			_tag_px.erase(id)
			_tag_vel.erase(id)
			_heading_off.erase(id)


## R2c: how a tag moves on screen (px/s, smoothed), from its rect's centre last
## frame. Zero across a camera cut.
func _screen_velocity(id: int, rect: Rect2, delta: float, cut: bool) -> Vector2:
	var centre := rect.get_center()
	var vel := Vector2.ZERO
	if _tag_px.has(id) and not cut and delta > 0.0:
		var now := (centre - (_tag_px[id] as Vector2)) / delta
		vel = (_tag_vel.get(id, now) as Vector2).lerp(now, 0.5)
	_tag_px[id] = centre
	_tag_vel[id] = vel
	return vel


## Whether this peer's own player is hidden (in a hedge, a bin, a shed, a pile).
func _me_hidden() -> bool:
	return local_hidden(get_tree())


static func local_hidden(tree: SceneTree) -> bool:
	for node: Node in tree.get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node.has_method("is_hidden") and bool(node.call("is_hidden"))
	return false


## R2c: keeps one line of a label between lo and hi shares of the view's height
## for this camera, whatever the lens (a 40 degree two-shot doubles a fixed-size
## label) or the distance (a tag a metre away), by scaling its pixel size from
## its own. Only changes it when it really changes (a new pixel size rebuilds the
## text's mesh).
static func fit_size(label: Label3D, camera: Camera3D, view: Vector2, lo: float, hi: float) -> void:
	if camera == null or camera.projection != Camera3D.PROJECTION_PERSPECTIVE:
		return
	if not label.has_meta("r2c_base_px"):
		label.set_meta("r2c_base_px", label.pixel_size)
	var base := float(label.get_meta("r2c_base_px"))
	var line := float(label.font_size) * base
	var tan_half := tan(deg_to_rad(camera.fov) * 0.5)
	var share := line / (2.0 * tan_half)
	if not label.fixed_size:
		share /= maxf(0.05, camera.global_position.distance_to(label.global_position))
	var want := base * _TextFit.clamp_scale(share, lo, hi)
	if absf(label.pixel_size - want) > base * Constants.R2C_HUD_FIT_STEP:
		label.pixel_size = want


## How much of the yard HUD shows now (ui_root.gd's cinematic fade), 1 without one.
static func yard_alpha(tree: SceneTree) -> float:
	var ui := tree.get_first_node_in_group("game_ui")
	if ui != null and ui.has_method("yard_hud_alpha"):
		return smoothstep(0.0, 1.0, float(ui.call("yard_hud_alpha")))
	return 1.0


## R2c: the floating counts on things (the wheelbarrow's "0/4  $0", a bag's
## price) are HUD hung in the world: never bigger than R2C_HUD_COUNT_LINE_MAX of
## the view, fading out as you come close (the bags in the barrow say it), and
## easing out with the yard HUD while the moment has you. Their owner still
## decides when they show (net_prop.gd _refresh_label); this only sets their
## size and transparency.
func _fit_counts(camera: Camera3D, view: Vector2) -> void:
	var hud := yard_alpha(get_tree())
	for node: Node in get_tree().get_nodes_in_group("props"):
		var label := node.get_node_or_null("Visual/Label") as Label3D
		if label == null or not label.visible:
			continue
		fit_size(label, camera, view, 0.0, Constants.R2C_HUD_COUNT_LINE_MAX)
		var away := camera.global_position.distance_to(label.global_position)
		var near := smoothstep(Constants.R2C_HUD_COUNT_NEAR_GONE_M, Constants.R2C_HUD_COUNT_NEAR_FULL_M, away)
		label.transparency = 1.0 - near * hud


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
		# Asleep on a cot: no name over the pillow (crew-06).
		var asleep := node.has_method("is_sleeping") and bool(node.call("is_sleeping"))
		out.append({"tag": plate, "owner": node, "hide": riding or asleep})
	for group: String in ["nice_crew", "crew_hands", SPEAKERS]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var label := node.get_node_or_null("Visual/Label") as Label3D
			if label == null:
				continue
			out.append({"tag": label, "owner": node, "hide": in_van(node)})
	# R2c: the homeowner's name too (it hung over the catch's two-shot); p1-ui: and
	# the shopkeepers' ("Marty" cut in half at the screen's edge).
	for group: String in ["homeowner", "shopkeepers"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var tag := node.get("_tag") as Label3D if "_tag" in node else null
			if tag != null and is_instance_valid(tag):
				out.append({"tag": tag, "owner": node, "hide": false})
	# p1-ui: the world's signs, in the same line (no owner: walls are checked
	# against the sign itself).
	for node: Node in get_tree().get_nodes_in_group(SIGNS):
		var sign := node as Label3D
		if sign != null and sign.is_inside_tree():
			out.append({"tag": sign, "owner": null, "hide": false, "sign": true})
	return out


## p1-ui: a sign hung in the world always faces the camera (from behind it read
## mirrored: "Back to Homie Depot" through the catch's swing, nb9).
static func setup_sign(sign: Label3D) -> void:
	if sign.has_meta("p1_sign"):
		return
	sign.set_meta("p1_sign", true)
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED


## p1-ui: whether a camera is a moment's rather than your eyes (a stage shot, the
## van's cabin camera rig): no tags or signs over it.
static func stage_camera(camera: Camera3D) -> bool:
	# The camera itself or the rig it hangs in, a few levels up at most.
	var node: Node = camera
	for _level: int in 4:
		if node == null:
			break
		if STAGE_CAMERAS.has(node.name):
			return true
		node = node.get_parent()
	return false


## p1-ui: where the HUD is on screen now (the cash and cleanup rows, the job
## panel, the clock and rank, heat, the goal line, the dash, the bar and the
## hands card), each as drawn; a piece eased out (the cinematic HUD) isn't there.
func hud_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var ui := get_parent()
	if ui == null:
		return out
	for piece: String in HUD_PIECES:
		var node := ui.get_node_or_null(piece) as Control
		if node == null or not node.is_visible_in_tree() or node.modulate.a * node.self_modulate.a < 0.05:
			continue
		var rect := drawn_rect(node)
		if rect.size.x > 1.0 and rect.size.y > 1.0:
			out.append(rect)
	var hotbar := ui.get_node_or_null("HotbarHud")
	if hotbar != null and hotbar.has_method("screen_rects"):
		out.append_array(hotbar.call("screen_rects") as Array[Rect2])
	return out


## p1-ui: where a HUD piece is drawn. A plain Control whose children are placed by
## hand (the heat meter, Chefty's dash) keeps its own size at zero, so its rect is
## the union of its shown children's.
static func drawn_rect(node: Control) -> Rect2:
	var rect := node.get_global_rect()
	if rect.size.x > 1.0 and rect.size.y > 1.0:
		return rect
	var union := Rect2()
	for child: Node in node.get_children():
		var part := child as Control
		if part == null or not part.visible or part.size.x <= 0.0 or part.size.y <= 0.0:
			continue
		var child_rect := part.get_global_rect()
		union = child_rect if union.size == Vector2.ZERO else union.merge(child_rect)
	return union


## p1-ui: how much room a tag's words have before the edge or HUD margin, as a
## share of P1_LABEL_FADE_PX (1 with that much or more, 0 at the margin).
static func room_share(rect: Rect2, view: Vector2, hud: Array[Rect2]) -> float:
	var fade := Constants.P1_LABEL_FADE_PX
	if clear_of_hud(rect.grow(fade), view, hud):
		return 1.0
	if not clear_of_hud(rect, view, hud):
		return 0.0
	var low := 0.0
	var high := fade
	for _step: int in 6:
		var mid := (low + high) * 0.5
		if clear_of_hud(rect.grow(mid), view, hud):
			low = mid
		else:
			high = mid
	return low / fade


## p1-ui: how far along `ahead` (a screen offset: where the words will be one
## fade's time from now) they can go and still be clear of the edges and the HUD,
## 0 to 1.
static func time_left_share(rect: Rect2, ahead: Vector2, view: Vector2, hud: Array[Rect2]) -> float:
	var low := 0.0
	var high := 1.0
	if clear_of_hud(Rect2(rect.position + ahead, rect.size), view, hud):
		return 1.0
	for _step: int in 8:
		var mid := (low + high) * 0.5
		if clear_of_hud(Rect2(rect.position + ahead * mid, rect.size), view, hud):
			low = mid
		else:
			high = mid
	return low


## p1-ui: whether a tag's words sit inside the screen, P1_LABEL_EDGE_PX in from
## every edge, and P1_LABEL_HUD_GAP_PX clear of every HUD panel.
static func clear_of_hud(rect: Rect2, view: Vector2, hud: Array[Rect2], scale := 1.0) -> bool:
	if rect.size == Vector2.ZERO:
		return true
	var edge := Constants.P1_LABEL_EDGE_PX * scale
	if not Rect2(Vector2.ONE * edge, view - Vector2.ONE * edge * 2.0).encloses(rect):
		return false
	for panel: Rect2 in hud:
		if rect.grow(Constants.P1_LABEL_HUD_GAP_PX * scale).intersects(panel):
			return false
	return true


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
	if through_hide_spot(get_tree(), camera.global_position, target):
		return true
	# p1-ui: a sign (no owner) behind someone isn't printed on them.
	if owner == null and through_body(get_tree(), camera.global_position, target):
		return true
	return through_moving_van(get_tree(), camera.global_position, target)


## p1-ui: whether the line passes through someone's body (another player, a keeper,
## a NICE BOY, a hired hand, a homeowner), from knee to crown: few of them have a
## layer-1 collider the ray would meet.
func through_body(tree: SceneTree, from: Vector3, to: Vector3) -> bool:
	var me := str(Net.local_peer_id())
	for group: String in ["players", "nice_crew", "crew_hands", "homeowner", "shopkeepers"]:
		for node: Node in tree.get_nodes_in_group(group):
			var body := node as Node3D
			if body == null or (group == "players" and node.name == me) or not body.is_visible_in_tree():
				continue
			var visual := body.get_node_or_null("Visual") as Node3D
			var feet := visual.global_position if visual != null else body.global_position
			var points := Geometry3D.get_closest_points_between_segments(from, to, feet + Vector3.UP * Constants.P1_SIGN_BODY_SPAN_M.x, feet + Vector3.UP * Constants.P1_SIGN_BODY_SPAN_M.y)
			# Only someone between you and the sign, not past it.
			if points[0].distance_to(points[1]) < Constants.P1_SIGN_BODY_RADIUS_M and points[0].distance_to(to) > Constants.P1_SIGN_BODY_RADIUS_M:
				return true
	return false


## R2c: whether the line passes through a hiding spot's box (a hedge, a bin, a
## shed): leaves have no layer-1 collider, so the ray alone let a tag or a bubble
## show through a hedge.
static func through_hide_spot(tree: SceneTree, from: Vector3, to: Vector3) -> bool:
	var spots: Array[Node] = tree.get_nodes_in_group("hide_spots")
	# Anything else solid to the eye without a collider can join VIEW_BLOCKERS
	# with a box_size (its box from its origin up, like a hiding spot's).
	spots.append_array(tree.get_nodes_in_group(VIEW_BLOCKERS))
	for spot: Node in spots:
		var node := spot as Node3D
		if node == null or not node.is_inside_tree() or not ("box_size" in node):
			continue
		var half: Vector3 = (node.get("box_size") as Vector3) * 0.5
		var into := node.global_transform.affine_inverse()
		var lift := Vector3(0.0, half.y, 0.0)
		if segment_hits_box(into * from - lift, into * to - lift, half):
			return true
	return false


## Whether the line from one point to another passes through a Courtesy Shuttle
## on the move. A driving van's Solid is off every layer (shuttle._set_solid, so
## it never shoves anyone), so the layer-1 ray misses it; its five boxes are
## tested here instead, or a tag drawn over the world would show through it.
## R2c: a parked one's Solid isn't on layer 1 either (a NICE BOY climbing in kept
## his bubble over the van's roof once he was inside), so it's tested too.
static func through_moving_van(tree: SceneTree, from: Vector3, to: Vector3) -> bool:
	for shuttle: Node in tree.get_nodes_in_group("nice_shuttle"):
		for trip: Node in shuttle.get_children():
			var solid := trip.get_node_or_null("VanLook/Solid") as CollisionObject3D
			if solid == null or not solid.is_inside_tree() or solid.collision_layer & 1 != 0:
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
	if not bark.has_meta("r2c_base_px"):
		bark.set_meta("r2c_base_px", bark.pixel_size)
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
func _place_bubble(bark: Label3D, camera: Camera3D, view: Vector2, delta: float, others: Array[Rect2] = [], cut: bool = false) -> Rect2:
	var parent := bark.get_parent() as Node3D
	var home: Vector3 = bark.get_meta("r2b_home", bark.position)
	var anchor := parent.to_global(home) if parent != null else bark.global_position
	if not in_front(camera, anchor):
		bark.position = home
		_bubble_shown[bark.get_instance_id()] = 0.0
		bark.transparency = 1.0
		return Rect2()
	var at := camera.unproject_position(anchor)
	var size := text_size_px(bark, bark.text, camera, view)
	# Bottom-anchored: the text sits above the anchor point, centered on it.
	var rect := Rect2(at.x - size.x * 0.5, at.y - size.y, size.x, size.y)
	var want := clamp_shift(rect, view, Constants.R2B_HUD_SAFE_MARGIN)
	# R2c: out of the way of the nearer bubbles already placed (two NICE BOYS
	# talking at once used to print over each other): up over the other, or below
	# it when there's no room above.
	want += avoid_shift(Rect2(rect.position + want, rect.size), others, view)
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
	# R2c: the bubble was chosen for the view when he spoke. Once his head leaves
	# the picture or he's in your face, it goes instead of hanging pinned in a
	# corner ("After you!" over the van's ceiling after the iris), and across a
	# camera cut it's simply gone from the new shot, no fade.
	var lost := not keeps_bubble(camera, anchor, view)
	if cut and not lost:
		# A new shot keeps it only as present() would have placed it there: his head
		# well inside the picture and the bubble whole above it, unclamped.
		var margin := Constants.R2B_HUD_SAFE_MARGIN
		lost = rect.position.y < margin or at.x < margin or at.x > view.x - margin or at.y > view.y - margin
	var shown := move_toward(float(_bubble_shown.get(id, 0.0 if hidden or lost else 1.0)), 0.0 if hidden or lost else 1.0, delta / Constants.R2B_HUD_TAG_FADE)
	if cut and (lost or hidden):
		shown = 0.0
	_bubble_shown[id] = shown
	bark.transparency = 1.0 - shown
	if shown < 0.05:
		return Rect2()
	return Rect2(rect.position + nudge, rect.size)


## R2c: whether a bubble already up still belongs in this view: the point over
## his head is in the picture and he isn't in your face. (A bubble whose text
## would hang off an edge still glides back inside: that's its anchor in view.)
static func keeps_bubble(camera: Camera3D, anchor: Vector3, view: Vector2) -> bool:
	if not in_front(camera, anchor):
		return false
	if camera.global_position.distance_to(anchor) < Constants.R2C_HUD_BUBBLE_KEEP_M:
		return false
	var at := camera.unproject_position(anchor)
	return Rect2(Vector2.ZERO, view).has_point(at)


## R2c: whether the view cut this frame (another camera, or this one jumped or
## swung further than any move or turn would in a frame): the iris's cut into the
## van, a stage shot taking over.
func _camera_cut(camera: Camera3D) -> bool:
	var xf := camera.global_transform
	var cut := camera.get_instance_id() != _last_camera
	if not cut:
		var turned := (-_last_view.basis.z).angle_to(-xf.basis.z)
		cut = _last_view.origin.distance_to(xf.origin) > Constants.R2C_HUD_CUT_MOVE_M or turned > Constants.R2C_HUD_CUT_TURN
	_last_camera = camera.get_instance_id()
	_last_view = xf
	return cut


## How far (px) a bubble's rect must move to clear the rects already placed
## (R2c): up above each it touches, or, when that would leave the screen,
## down below it. Zero when it touches none.
static func avoid_shift(rect: Rect2, others: Array[Rect2], view: Vector2) -> Vector2:
	var gap := Constants.R2C_HUD_BUBBLE_GAP
	var margin := Constants.R2B_HUD_SAFE_MARGIN
	var moved := rect
	for _pass: int in 4:
		var hit := false
		for other: Rect2 in others:
			if not moved.intersects(other.grow(gap)):
				continue
			hit = true
			var up := other.position.y - gap - moved.end.y
			if moved.position.y + up >= margin:
				moved.position.y += up
			else:
				moved.position.y = other.end.y + gap
		if not hit:
			break
	moved.position.y = clampf(moved.position.y, margin, maxf(margin, view.y - margin - moved.size.y))
	return moved.position - rect.position


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
	fit_size(bark, camera, view, Constants.R2C_HUD_BUBBLE_LINE_MIN, Constants.R2C_HUD_BUBBLE_LINE_MAX)
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
	# R2c: hidden, you hear him through the leaves (a subtitle); a bubble hung over
	# the hedge would point at where he stands.
	if through_hide_spot(speaker.get_tree(), camera.global_position, anchor) or local_hidden(speaker.get_tree()):
		return false
	return true
