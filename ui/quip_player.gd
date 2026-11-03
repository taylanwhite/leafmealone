extends Node

## Local presentation. Plays draft workbook lines with a cooldown and a per-session cap.
## The line is a caption at the bottom left, styled by the player's Settings
## (interface: captions on or off, caption_size, caption_backdrop); with captions
## off the babble still plays. Anchored to the corner, not placed, so it stays on
## screen at every UI scale.

const _Strings: Script = preload("res://ui/strings.gd")
const _Director = preload("res://net/run_events/director.gd")
## The caption's look at the normal caption size (presentation, docs/DECISIONS.md
## "Tuning vs. presentation"): font size, distance from the bottom-left corner
## (x right, y up), the widest it gets before it wraps, and the backdrop box.
const FONT_SIZE: int = 22
const CORNER_OFFSET := Vector2(80.0, 100.0)
const MAX_WIDTH: float = 760.0
## The gap kept to the hotbar's slot row, and the narrowest it wraps at to keep it.
const BAND_GAP: float = 16.0
const BAND_MIN_WIDTH: float = 340.0
const _Hotbar = preload("res://ui/hotbar_hud.gd")
const _HudMode = preload("res://ui/hud_mode.gd")
const _TextFit = preload("res://ui/text_fit.gd")
const BACKDROP_COLOR := Color(0.0, 0.0, 0.0, 0.55)
const BACKDROP_RADIUS: int = 10
const BACKDROP_MARGIN := Vector2(14.0, 8.0)

var _label: Label
var _hide_at: float = 0.0
var _played: Dictionary = {}
var _last_at: Dictionary = {}
var _seen_lot: bool = false
var _director: Node
var _last_roster: int = 0


func _ready() -> void:
	_label = Label.new()
	_label.name = "Caption"
	_label.visible = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Its bottom edge sits CORNER_OFFSET.y above the screen's bottom and it grows
	# upward, so a wrapped line or a big caption size never runs off the screen.
	_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_label.offset_left = CORNER_OFFSET.x
	_label.offset_right = CORNER_OFFSET.x
	_label.offset_top = -CORNER_OFFSET.y
	_label.offset_bottom = -CORNER_OFFSET.y
	_label.add_theme_color_override("font_color", Color(0.949, 0.902, 0.788))
	_label.add_theme_color_override("font_shadow_color", Color(0.165, 0.141, 0.110))
	_label.add_theme_constant_override("shadow_offset_x", 2)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_label)
	_style_caption()
	Settings.changed.connect(_on_settings_changed)
	get_viewport().size_changed.connect(_fit_width)
	if not Net.player_zone_changed.is_connected(_on_zone):
		Net.player_zone_changed.connect(_on_zone)
	if not Campaign.unlocks_changed.is_connected(_on_unlocks):
		Campaign.unlocks_changed.connect(_on_unlocks)
	if not Campaign.payout_ready.is_connected(_on_payout):
		Campaign.payout_ready.connect(_on_payout)


func _process(delta: float) -> void:
	if _label.visible and Time.get_ticks_msec() / 1000.0 > _hide_at:
		_label.visible = false
	# R2b: a corner quip already up when the moment takes you goes with the HUD.
	if _label.visible and _HudMode.cinematic(get_tree(), Net.local_peer_id()):
		_label.visible = false
	if _label.visible:
		_clear_heat()
		_clear_goal(delta)
	_play_waiting()
	_watch_director()
	_watch_cleanup()
	_watch_annex()


## R2c: a corner quip whose trigger came while the moment had you (a store
## arrival while you're still buckled in) waits for the yard HUD to be back,
## then plays, unless it's been waiting longer than R2C_HUD_QUIP_WAIT_MAX.
## Only the latest waits. (R2b dropped them for good.)
var _waiting_trigger: String = ""
var _waiting_since: float = 0.0


func _play_waiting() -> void:
	if _waiting_trigger == "":
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _waiting_since > Constants.R2C_HUD_QUIP_WAIT_MAX:
		_waiting_trigger = ""
		return
	if _HudMode.cinematic(get_tree(), Net.local_peer_id()):
		return
	var ui := get_parent()
	if ui != null and ui.has_method("yard_hud_alpha") and float(ui.call("yard_hud_alpha")) < 0.99:
		return
	var trigger := _waiting_trigger
	_waiting_trigger = ""
	_try(trigger)


## The quip that would wait (for tests): its trigger, or "".
func waiting_trigger() -> String:
	return _waiting_trigger


## R2c: the corner quip and the goal line never print over each other: when the
## quip (pushed right by the heat meter) would share the goal line's band, it
## glides up to sit above the goal line, and back down once it's gone.
func _clear_goal(delta: float) -> void:
	var view := _label.get_viewport_rect().size
	var rest := view.y - CORNER_OFFSET.y
	var bottom := rest
	var goal := get_parent().get_node_or_null("JobGoal") as Control if get_parent() != null else null
	if goal != null and goal.is_visible_in_tree() and goal.modulate.a > 0.05 and goal.size.x > 0.0:
		var g := goal.get_global_rect().grow(Constants.R2C_HUD_QUIP_GOAL_GAP)
		# Its size from its offsets and its text (on the frame its text is set the
		# Label hasn't grown to it yet).
		var mine := _label.get_global_rect()
		var tall := maxf(mine.size.y, _label.get_combined_minimum_size().y)
		var at_rest := Rect2(mine.position.x, rest - tall, _label.offset_right - _label.offset_left, tall)
		if at_rest.intersects(g):
			bottom = minf(rest, g.position.y)
	var target := bottom - view.y
	var height := _label.offset_bottom - _label.offset_top
	var now := _label.offset_bottom
	if absf(now - target) < 0.5:
		now = target
	else:
		now = lerpf(now, target, 1.0 - exp(-Constants.R2C_HUD_QUIP_GLIDE * delta))
	_label.offset_bottom = now
	_label.offset_top = now - height


func _on_zone(peer_id: int, zone: Net.Zone) -> void:
	if peer_id != Net.local_peer_id():
		return
	if zone == Net.Zone.LOT and not _seen_lot:
		_seen_lot = true
		_try("first_lot")
	elif zone == Net.Zone.STORE:
		if _seen_lot:
			_try("return_store")
		else:
			_try("store_arrival")


func _on_unlocks() -> void:
	_try("tool_purchase")


func _on_payout(_results: Array[Dictionary]) -> void:
	var fields := get_tree().get_nodes_in_group("leaf_field")
	if fields.is_empty():
		return
	if float(fields[0].call("cleaned_fraction")) >= 0.999:
		_try("full_clear")


## When this player last arrived on a yard; the jab about slow progress waits
## until they've had a fair go at it.
var _on_lot_since: float = -1.0


func _watch_cleanup() -> void:
	if Net.player_zone(Net.local_peer_id()) != Net.Zone.LOT:
		_on_lot_since = -1.0
		return
	if _on_lot_since < 0.0:
		_on_lot_since = Net.server_time()
	if Net.server_time() - _on_lot_since < Constants.QUIP_LOW_CLEANUP_AFTER:
		return
	var fields := get_tree().get_nodes_in_group("leaf_field")
	if fields.is_empty():
		return
	if float(fields[0].call("cleaned_fraction")) < 0.08:
		_try("low_cleanup")



func _watch_director() -> void:
	var director := get_tree().get_first_node_in_group("run_director")
	if director == null:
		return
	if _director != director:
		_director = director
		if not director.phase_changed.is_connected(_on_phase):
			director.phase_changed.connect(_on_phase)
		# R2 chunk 2's director says who was caught the moment it happens.
		if director.has_signal("peer_caught") and not director.is_connected("peer_caught", on_peer_caught):
			director.connect("peer_caught", on_peer_caught)
	if director.has_signal("peer_caught"):
		return
	# Before that: whoever is new in the cohort.
	var roster: Array = director.call("cohort_roster")
	if roster.size() > _last_roster:
		for peer_id: Variant in roster:
			if not _known_caught.has(int(peer_id)):
				on_peer_caught(int(peer_id))
	_known_caught.clear()
	for peer_id: Variant in roster:
		_known_caught[int(peer_id)] = true
	_last_roster = roster.size()


var _known_caught: Dictionary = {}


## x1:text, the free teammate's radio. While crewmates are at Annex B and this
## player isn't, a RADIO line every so often says how it's going in there
## (Strings.ANNEX_QUIPS teammate_dispatch), and one more as each one's form goes
## through (teammate_out). A caught player whose own form went through is free
## again and listens too. It is the one thing they can't see from the yard, so
## it gets words; it never says what to do. The annex's own "X is at Annex B"
## opens the visit (net/annex/annex.gd).
## The annex elapsed when this player started listening (-1: not listening), and
## the dispatches since then (they set the schedule).
var _dispatch_visit: float = -1.0
var _dispatches: int = 0
## Dispatches heard this whole visit, across stints in and out of the room:
## they pick the line (so none repeats) and hold the visit's cap.
var _dispatch_heard: int = 0
## Teammates heard about this visit: peer id -> true once their "out" line played.
var _dispatch_out: Dictionary = {}
## The visit's seed (-1 between visits).
var _dispatch_seed: int = -1


func _watch_annex() -> void:
	var annex := get_tree().get_first_node_in_group("annex")
	var me := Net.local_peer_id()
	if annex == null or not bool(annex.call("is_active")):
		# The visit ended (closing time lets everyone out at once, with no "out"
		# stage this player sees): whoever was still inside is on the way home.
		for peer_id: Variant in _dispatch_out:
			if not bool(_dispatch_out[peer_id]):
				_dispatch(&"teammate_out", int(peer_id), _dispatch_seed + int(peer_id))
		_dispatch_out.clear()
		_dispatch_visit = -1.0
		_dispatch_heard = 0
		_dispatch_seed = -1
		return
	var seed_value := int(annex.call("seed_value"))
	if seed_value != _dispatch_seed:
		# A new visit.
		_dispatch_seed = seed_value
		_dispatch_heard = 0
		_dispatch_visit = -1.0
	var roster: Array[int] = annex.call("roster")
	var visitors: Array[int] = annex.call("visitors")
	# Riders still inside and visitors are in the room and can see for
	# themselves. A rider whose form went through is back outside, on the roster
	# as "out", and hears about whoever is still in there like any free player.
	var in_room := visitors.has(me) or (roster.has(me) and str(annex.call("stage_of", me)) != "out")
	if roster.is_empty() or in_room:
		_dispatch_out.clear()
		_dispatch_visit = -1.0
		return
	var elapsed := float(annex.call("elapsed"))
	var fresh := _dispatch_visit < 0.0 or elapsed < _dispatch_visit
	if fresh:
		# This player starts listening now: at the start of a visit, or partway
		# through one (back from the room, a late join). The schedule runs from
		# here, so nothing that was "due" before they were listening plays at once.
		_dispatch_visit = elapsed
		_dispatches = 0
		_dispatch_out.clear()
	var inside: Array[int] = []
	for peer_id: int in roster:
		if peer_id == me:
			continue
		if str(annex.call("stage_of", peer_id)) == "out":
			# Only a release this player didn't already know about gets a line:
			# anyone already out when they started listening is old news.
			if not bool(_dispatch_out.get(peer_id, false)):
				_dispatch_out[peer_id] = true
				if not fresh:
					_dispatch(&"teammate_out", peer_id, seed_value + peer_id)
		else:
			_dispatch_out[peer_id] = false
			inside.append(peer_id)
	if inside.is_empty() or _dispatch_heard >= Constants.ANNEX_DISPATCH_MAX or not dispatch_due(elapsed - _dispatch_visit, _dispatches):
		return
	var who := inside[_dispatch_heard % inside.size()]
	_dispatches += 1
	_dispatch_heard += 1
	# Consecutive salts over the whole visit: pick_seeded wraps them round the
	# pool, so no line repeats in a visit, even across trips into the room.
	_dispatch(&"teammate_dispatch", who, seed_value + _dispatch_heard)


## Whether the next dispatch is due, sent of them already played this visit and
## elapsed seconds since this player started listening (the visit's start, or
## when they came out of the room or joined): the first at ANNEX_DISPATCH_FIRST, then one
## every ANNEX_DISPATCH_GAP, ANNEX_DISPATCH_MAX at most. (net/dev/cast_test.gd)
static func dispatch_due(elapsed: float, sent: int) -> bool:
	return sent < Constants.ANNEX_DISPATCH_MAX and elapsed >= Constants.ANNEX_DISPATCH_FIRST + Constants.ANNEX_DISPATCH_GAP * float(sent)


## One radio line about peer_id, picked from the visit's seed so every free
## player hears the same one.
func _dispatch(kind: StringName, peer_id: int, salt: int) -> void:
	var shown := Net.player_name(peer_id)
	var pool: Array = _Strings.ANNEX_QUIPS.get(String(kind), [])
	if shown == "" or pool.is_empty() or _HudMode.cinematic(get_tree(), Net.local_peer_id()):
		return
	var stack := get_tree().get_first_node_in_group("caption_stack")
	if stack != null:
		stack.call("push", &"radio", _Strings.pick_seeded(pool, salt) % shown, Constants.QUIP_CAPTION_SECONDS, 1)
	# The run cues' radio crackle (ui/run_cues.gd), not a babble: it's the radio.
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play", "radio")


## A crewmate was caught: "They took Pat." with their real name, but only for a
## player who didn't see it (too far, or no line of sight from this camera to
## them), and never for the one caught.
func on_peer_caught(peer_id: int) -> void:
	var me := Net.local_peer_id()
	if peer_id == me or peer_id <= 0:
		return
	if saw_catch(get_tree(), peer_id):
		return
	var shown := Net.player_name(peer_id)
	if shown == "":
		return
	# The workbook row's session cap still holds (Q-006: once a session).
	if int(_played.get("Q-006", 0)) >= _max_session("Q-006"):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_at.get("Q-006", -1000.0)) < Constants.QUIP_COOLDOWN_SECONDS:
		return
	_last_at["Q-006"] = now
	_played["Q-006"] = int(_played.get("Q-006", 0)) + 1
	var line: String = _Strings.pick_seeded(_Strings.TEAMMATE_CAPTURED, int(Net.server_time() * 10.0) + peer_id)
	stack_caption(&"teammate", line % [shown, shown], 2)


## Whether this peer saw peer_id get caught: within TEAMMATE_SEEN_METERS of them
## and nothing solid between this camera and their chest.
static func saw_catch(tree: SceneTree, peer_id: int) -> bool:
	var me: Node3D = null
	var them: Node3D = null
	for node: Node in tree.get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			me = node as Node3D
		elif node.name == str(peer_id):
			them = node as Node3D
	if me == null or them == null:
		return false
	var camera := tree.root.get_viewport().get_camera_3d()
	var eye := camera.global_position if camera != null else me.global_position + Vector3.UP * 1.6
	var chest := them.global_position + Vector3.UP * 1.2
	if eye.distance_to(chest) > Constants.TEAMMATE_SEEN_METERS:
		return false
	var space := them.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(eye, chest, 1)
	var exclude: Array[RID] = []
	for node: Node3D in [me, them]:
		if node is CollisionObject3D:
			exclude.append((node as CollisionObject3D).get_rid())
	query.exclude = exclude
	return space.intersect_ray(query).is_empty()


## Reads the director's phase, not its status text: the text is writing and can
## change (it once said "are here" while this looked for "is here", so Q-009 never
## played).
func _on_phase(_status: String) -> void:
	if _director == null:
		return
	var phase := int(_director.call("phase"))
	# Raid quips share the caption stack with the radio, so they never overlap it.
	if phase == _Director.Phase.WARNING:
		_try("run_warning", true)
	elif phase == _Director.Phase.CHASE:
		_try("crew_arrival", true)


## A line on the caption stack (ui/caption_stack.gd) with its babble.
func stack_caption(kind: StringName, line: String, priority: int = 0) -> void:
	var stack := get_tree().get_first_node_in_group("caption_stack")
	if stack != null:
		stack.call("push", kind, _Strings.keyed(line), Constants.QUIP_CAPTION_SECONDS, priority)
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play", "babble")


## A LINES row's max_session by id (1 when the row is missing).
static func _max_session(id: String) -> int:
	for row: Dictionary in _Strings.LINES:
		if str(row["id"]) == id:
			return int(row["max_session"])
	return 1


func _try(trigger: String, on_stack: bool = false) -> void:
	# R2b: no corner quip while the moment has you (held, in the van, at the
	# Annex). R2c: it waits for the moment to end (_play_waiting) instead of being
	# dropped for good; its play count isn't spent until it plays.
	if not on_stack and _HudMode.cinematic(get_tree(), Net.local_peer_id()):
		_waiting_trigger = trigger
		_waiting_since = Time.get_ticks_msec() / 1000.0
		return
	for row: Dictionary in _Strings.LINES:
		if str(row["trigger"]) != trigger:
			continue
		var id := str(row["id"])
		var played := int(_played.get(id, 0))
		if played >= int(row["max_session"]):
			return
		var now := Time.get_ticks_msec() / 1000.0
		if now - float(_last_at.get(id, -1000.0)) < Constants.QUIP_COOLDOWN_SECONDS:
			return
		_played[id] = played + 1
		_last_at[id] = now
		if on_stack:
			stack_caption(&"quip", str(row["line"]))
		else:
			show_caption(str(row["line"]))
		return


## Shows line as the caption (unless the player turned captions off) and plays
## the babble that goes with it: characters never speak real words, so the
## caption carries the joke (docs/ART.md, "Audio").
func show_caption(line: String) -> void:
	_label.text = _Strings.keyed(line)
	_hide_at = Time.get_ticks_msec() / 1000.0 + Constants.QUIP_CAPTION_SECONDS
	_style_caption()
	_label.visible = captions_on()
	if _label.visible:
		# Placed clear of the heat meter and the goal line from its first frame.
		_label.offset_bottom = -CORNER_OFFSET.y
		_label.offset_top = _label.offset_bottom
		_clear_heat()
		_clear_goal(1000.0)
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play", "babble")


static func captions_on() -> bool:
	return bool(Settings.get_value("interface", "captions"))


func _on_settings_changed(section: StringName, _key: StringName, _value: Variant) -> void:
	if section == &"interface":
		_style_caption()
		if not captions_on():
			_label.visible = false


## Size and backdrop from Settings: the font at FONT_SIZE times caption_scale(),
## and a dark rounded box behind it when caption_backdrop is on.
func _style_caption() -> void:
	_label.add_theme_font_size_override("font_size", roundi(FONT_SIZE * Settings.caption_scale()))
	apply_backdrop(_label)
	_soft_plate(_label)
	_fit_width()


## R2b: the caption stack's soft plate behind the words when the dark backdrop is
## off, so the corner line reads over bright leaves and sky too.
static func _soft_plate(label: Label) -> void:
	var plate := label.get_node_or_null("Plate") as Panel
	if plate == null:
		plate = Panel.new()
		plate.name = "Plate"
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.show_behind_parent = true
		label.add_child(plate)
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.06, 0.05, 0.05, Constants.R2B_HUD_PLATE_ALPHA)
		box.set_corner_radius_all(Constants.R2B_HUD_PLATE_FEATHER)
		box.anti_aliasing_size = 6.0
		plate.add_theme_stylebox_override("panel", box)
	var pad := Constants.R2B_HUD_PLATE_PAD
	plate.set_anchors_preset(Control.PRESET_FULL_RECT)
	plate.offset_left = -pad.x
	plate.offset_right = pad.x
	plate.offset_top = -pad.y
	plate.offset_bottom = pad.y
	plate.visible = not bool(Settings.get_value("interface", "caption_backdrop"))


## Puts the dark rounded caption box behind a screen caption when the player's
## caption_backdrop is on, and takes it off when it isn't. Shared with the
## run-event captions (ui/run_cues.gd) so every screen caption looks the same.
static func apply_backdrop(label: Label) -> void:
	if bool(Settings.get_value("interface", "caption_backdrop")):
		var box := StyleBoxFlat.new()
		box.bg_color = BACKDROP_COLOR
		box.set_corner_radius_all(BACKDROP_RADIUS)
		box.content_margin_left = BACKDROP_MARGIN.x
		box.content_margin_right = BACKDROP_MARGIN.x
		box.content_margin_top = BACKDROP_MARGIN.y
		box.content_margin_bottom = BACKDROP_MARGIN.y
		label.add_theme_stylebox_override("normal", box)
	else:
		label.remove_theme_stylebox_override("normal")


## R2b: the corner caption keeps clear of the heat meter that shares its corner
## (it used to run into it): beside it while the meter is up, back in the corner
## after.
func _clear_heat() -> void:
	var left := CORNER_OFFSET.x
	var heat := get_parent().get_node_or_null("HeatMeter") as Control if get_parent() != null else null
	if heat != null and heat.is_visible_in_tree() and heat.modulate.a > 0.05:
		var meter := Rect2()
		for child: Node in heat.find_children("*", "Control", true, false):
			var control := child as Control
			if control.is_visible_in_tree() and control.size.x > 0.0 and control.size.y > 0.0:
				meter = control.get_global_rect() if meter.size == Vector2.ZERO else meter.merge(control.get_global_rect())
		var mine := _label.get_global_rect()
		if meter.size != Vector2.ZERO and mine.position.y < meter.end.y and mine.end.y > meter.position.y:
			left = maxf(left, meter.end.x + BAND_GAP)
	if not is_equal_approx(_label.offset_left, left):
		var width := _label.offset_right - _label.offset_left
		_label.offset_left = left
		_label.offset_right = left + width
		_fit_width()


## As wide as the line, up to MAX_WIDTH and the room the screen has at this UI
## scale; longer lines wrap and the caption grows upward from its corner.
func _fit_width() -> void:
	var font := _label.get_theme_font("font")
	var size := _label.get_theme_font_size("font_size")
	var box := _label.get_theme_stylebox("normal")
	var padding := box.get_minimum_size().x if box != null else 0.0
	var natural := font.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + padding + 2.0
	var view_width := _label.get_viewport_rect().size.x
	var room := view_width - _label.offset_left - CORNER_OFFSET.x
	# Keep left of the hotbar's slot row (it sits in the same bottom band), but
	# never narrower than BAND_MIN_WIDTH, so a big caption stays readable.
	var left_of_bar := view_width * 0.5 - _Hotbar.slots_half_width() - BAND_GAP - _label.offset_left
	room = minf(room, maxf(left_of_bar, BAND_MIN_WIDTH))
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var width := maxf(1.0, minf(natural, minf(MAX_WIDTH, room)))
	# R2c: a wrapped quip's rows come out even, not a long row and a lone word.
	if natural > width and _label.text != "":
		width = _TextFit.balanced_width(font, _label.text, size, maxf(1.0, width - padding - 2.0)) + padding + 2.0
	_label.offset_right = _label.offset_left + width
	# Back to no height, so it settles at the new text's height, growing upward.
	_label.offset_top = _label.offset_bottom
