extends PanelContainer

## Authority: local. The crew phone (docs/SPINE.md, "The phone"). Tab takes it
## out and puts it away. Four apps: Texts (job requests you can take from here,
## referrals, the clerk), Clients (everyone you work for and how they feel about
## you), Map (the neighborhoods and what opens them), and Crew (the rank, XP,
## and perks). Everything it shows comes from net/town/town.gd, the day clock,
## and Campaign; taking a job asks the job board, like walking up to it.

const _Strings = preload("res://ui/strings.gd")
const _Ranks = preload("res://core/ranks.gd")
const _Hoods = preload("res://net/town/neighborhoods.gd")
const BEZEL := Color(0.1, 0.1, 0.12)
const SCREEN := Color(0.96, 0.95, 0.92)
const INK := Color(0.15, 0.15, 0.17)
const SOFT := Color(0.45, 0.45, 0.5)
const ORANGE := Color(0.93, 0.47, 0.13)
const GREEN := Color(0.2, 0.6, 0.3)
const BUBBLE := Color(0.88, 0.9, 0.95)
const BUBBLE_JOB := Color(1.0, 0.92, 0.8)
const APPS: Array[String] = ["texts", "clients", "map", "crew"]

var _app: String = "texts"
var _header: Label
var _list: VBoxContainer
var _scroll: ScrollContainer
var _tabs: Dictionary = {}
var _dirty: bool = true
var _unread: int = 0


func _ready() -> void:
	add_to_group("phone")
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(380, 600)
	add_theme_stylebox_override("panel", _box(BEZEL, 34, Color(0.25, 0.25, 0.28), 3, 14))
	var screen := PanelContainer.new()
	screen.add_theme_stylebox_override("panel", _box(SCREEN, 24, SCREEN, 0, 12))
	add_child(screen)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	screen.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	_header = _text("", 22, INK)
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_header)
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(close_phone)
	top.add_child(close)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	_scroll.add_child(_list)
	var dock := HBoxContainer.new()
	dock.alignment = BoxContainer.ALIGNMENT_CENTER
	dock.add_theme_constant_override("separation", 6)
	column.add_child(dock)
	for app: String in APPS:
		var button := Button.new()
		button.text = _Strings.UI["phone_tab_" + app]
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 15)
		button.pressed.connect(func() -> void: show_app(app))
		dock.add_child(button)
		_tabs[app] = button
	_hook_world.call_deferred()


func _hook_world() -> void:
	# The town and the board come and go with the session: hook the ones there
	# now, and every one added later.
	for existing: Node in [get_tree().get_first_node_in_group("town"), get_tree().get_first_node_in_group("job_board"), get_tree().get_first_node_in_group("hires")]:
		if existing != null:
			_watch(existing)
	get_tree().node_added.connect(func(node: Node) -> void:
		if node.name == "Town" or node.name == "JobBoard" or node.name == "Hires":
			_watch(node)
	)
	Campaign.rank_changed.connect(_mark_dirty)


func _watch(node: Node) -> void:
	if node.has_signal("texted") and not node.is_connected("texted", _on_texted):
		node.connect("texted", _on_texted)
	if node.has_signal("changed") and not node.is_connected("changed", _mark_dirty):
		node.connect("changed", _mark_dirty)
	if node.has_signal("offers_changed") and not node.is_connected("offers_changed", _mark_dirty):
		node.connect("offers_changed", _mark_dirty)


func _mark_dirty() -> void:
	_dirty = true


func _on_texted(_text_entry: Dictionary) -> void:
	_dirty = true
	if not visible:
		_unread += 1


# _input, not _unhandled_input: Tab must work even while one of the phone's
# own buttons has focus, and Esc puts the phone away before it pauses.
func _input(event: InputEvent) -> void:
	if Net.current_state() != Net.State.IN_SESSION:
		return
	if event.is_action_pressed("phone"):
		if visible:
			close_phone()
		else:
			open_phone()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("pause"):
		close_phone()
		get_viewport().set_input_as_handled()


## How many texts came in while the phone was away (the HUD shows it).
func unread() -> int:
	return _unread


func open_phone(app: String = "") -> void:
	visible = true
	_unread = 0
	# Held in the right hand: anchored to the right edge, 40 px in, centered up and down.
	set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	offset_right = -40.0
	offset_left = -40.0 - custom_minimum_size.x
	offset_top = -custom_minimum_size.y * 0.5
	offset_bottom = custom_minimum_size.y * 0.5
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show_app(app if app != "" else _app)


func close_phone() -> void:
	visible = false
	var ui := get_tree().get_first_node_in_group("game_ui")
	if ui != null:
		ui.call("recapture_mouse")


func show_app(app: String) -> void:
	_app = app
	for key: String in _tabs:
		(_tabs[key] as Button).button_pressed = key == app
	_dirty = true
	_rebuild()


func _process(_delta: float) -> void:
	if visible and _dirty:
		_rebuild()


func _rebuild() -> void:
	_dirty = false
	for child: Node in _list.get_children():
		child.queue_free()
	_header.text = _Strings.UI["phone_tab_" + _app]
	var town := get_tree().get_first_node_in_group("town")
	match _app:
		"texts":
			_texts(town)
		"clients":
			_clients(town)
		"map":
			_map(town)
		"crew":
			_crew()


# ---------------------------------------------------------------- apps

func _texts(town: Node) -> void:
	if town == null or (town.get("texts") as Array).is_empty():
		_list.add_child(_text(_Strings.UI["phone_no_texts"], 16, SOFT))
		return
	var texts: Array = (town.get("texts") as Array).duplicate()
	texts.reverse()
	var requests: Array = town.get("requests")
	var board := get_tree().get_first_node_in_group("job_board")
	var picked := int((board.call("current") as Dictionary).get("house_id", -1)) if board != null else -1
	# Once a job is on (Chefty's out, or a yard is waiting), the pick is set.
	var world := get_tree().get_first_node_in_group("world")
	var locked := world != null and bool(world.call("job_locked"))
	# Only a client's newest text carries the button.
	var answered := {}
	for entry: Variant in texts:
		var message := entry as Dictionary
		var is_job := str(message.get("kind", "")) in ["request", "referral"] and requests.has(int(message.get("house", -1))) and not answered.has(int(message.get("house", -1)))
		if is_job:
			answered[int(message.get("house", -1))] = true
		var bubble := PanelContainer.new()
		bubble.add_theme_stylebox_override("panel", _box(BUBBLE_JOB if is_job else BUBBLE, 14, BUBBLE, 0, 10))
		var column := VBoxContainer.new()
		bubble.add_child(column)
		var head := "%s  ·  Day %d %s" % [str(message.get("from", "")), int(message.get("day", 1)), str(message.get("time", ""))]
		column.add_child(_text(head, 13, SOFT))
		var body := _text(str(message.get("text", "")), 16, INK)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size.x = 300
		column.add_child(body)
		if is_job:
			var house_id := int(message.get("house", -1))
			if house_id == picked:
				column.add_child(_text(_Strings.UI["phone_job_up_next"], 14, GREEN))
			elif not locked:
				var take := Button.new()
				take.focus_mode = Control.FOCUS_NONE
				take.text = _Strings.UI["phone_take_job"]
				take.size_flags_horizontal = Control.SIZE_SHRINK_END
				take.pressed.connect(func() -> void: _take(house_id))
				column.add_child(take)
		_list.add_child(bubble)


func _take(house_id: int) -> void:
	var board := get_tree().get_first_node_in_group("job_board")
	if board == null:
		return
	var offers: Array = board.get("offers")
	for index: int in offers.size():
		if int((offers[index] as Dictionary).get("house_id", -1)) == house_id:
			board.call("request_choose", index)
	_dirty = true


func _clients(town: Node) -> void:
	if town == null:
		return
	var clock := get_tree().get_first_node_in_group("day_clock")
	var today := int(clock.get("day")) if clock != null else 1
	for hood: Dictionary in _Hoods.HOODS:
		var shown := false
		for entry: Variant in (town.get("houses") as Array):
			var house := entry as Dictionary
			if str(house["hood"]) != str(hood["id"]) or not bool(house.get("known", false)):
				continue
			if not shown:
				_list.add_child(_text(str(hood["name"]), 15, ORANGE))
				shown = true
			var house_id := int(house["id"])
			var owner: Dictionary = house["owner"]
			var card := VBoxContainer.new()
			card.add_child(_text(_Strings.UI["phone_client_line"] % [str(town.call("owner_name", house_id)), str(town.call("address", house_id))], 16, INK))
			card.add_child(_text(_hearts(float(house.get("relationship", 0.0))), 15, Color(0.85, 0.25, 0.3)))
			if bool(house.get("poached", false)):
				card.add_child(_text(_Strings.UI["phone_poached"], 14, Color(0.1, 0.5, 0.25)))
			var last := int(house.get("last_day", -1))
			var last_text: String = _Strings.UI["phone_last_never"]
			if last == today:
				last_text = _Strings.UI["phone_last_today"]
			elif last >= 0:
				last_text = _Strings.UI["phone_last_days"] % (today - last)
			var likes := str(owner.get("likes", ""))
			var likes_text := str(_Strings.UI.get("task_" + likes, "")) if likes != "" else ""
			var detail := _Strings.UI["phone_client_detail"] % [_picky(float(owner.get("standards", 0.3))), likes_text if likes_text != "" else "no favorite job", int(house.get("jobs", 0)), last_text]
			var detail_label := _text(detail, 13, SOFT)
			detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			detail_label.custom_minimum_size.x = 300
			card.add_child(detail_label)
			var blurb: Dictionary = _Hoods.PERSONALITIES.get(str(owner.get("personality", "")), {})
			if not blurb.is_empty():
				var blurb_label := _text(str(blurb["blurb"]), 13, SOFT)
				blurb_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				blurb_label.custom_minimum_size.x = 300
				card.add_child(blurb_label)
			_list.add_child(card)


func _map(town: Node) -> void:
	for hood: Dictionary in _Hoods.HOODS:
		var hood_id := str(hood["id"])
		var known := 0
		if town != null:
			for entry: Variant in (town.get("houses") as Array):
				if str((entry as Dictionary)["hood"]) == hood_id and bool((entry as Dictionary).get("known", false)):
					known += 1
		var open: bool = town != null and bool(town.call("is_hood_open", hood_id))
		var line := ""
		var color := INK
		if open and known > 0:
			line = _Strings.UI["phone_hood_open"] % [str(hood["name"]), known]
		elif open:
			line = _Strings.UI["phone_hood_waiting"] % str(hood["name"])
			color = SOFT
		else:
			line = _Strings.UI["phone_hood_locked"] % [str(hood["name"]), _Ranks.title(_Ranks.tier_of("hood:" + hood_id))]
			color = SOFT
		_list.add_child(_text(line, 17, color))
		var blurb := _text(str(hood["blurb"]), 13, SOFT)
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		blurb.custom_minimum_size.x = 300
		_list.add_child(blurb)


func _crew() -> void:
	var tier := Campaign.crew_tier()
	_list.add_child(_text(_Ranks.title(tier), 24, ORANGE))
	var need := _Ranks.xp_for_tier(tier)
	var into := _Ranks.xp_into_tier(Campaign.crew_xp())
	_list.add_child(_text(_Strings.UI["hud_xp"] % [into, need, Campaign.pending_xp()], 15, INK))
	var next := _Ranks.unlock_at(tier + 1)
	if next != "":
		var line := _text(_Strings.UI["phone_next_unlock"] % [_Strings.unlock_name(next), _Ranks.title(tier + 1)], 15, INK)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size.x = 300
		_list.add_child(line)
	var perks := PackedStringArray()
	for unlock: String in _Ranks.unlocks_through(tier):
		if unlock.begins_with("perk:"):
			perks.append(_Strings.unlock_name(unlock))
	if not perks.is_empty():
		var perk_label := _text(_Strings.UI["phone_perks"] % ", ".join(perks), 13, SOFT)
		perk_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		perk_label.custom_minimum_size.x = 300
		_list.add_child(perk_label)
	_hires()
	_list.add_child(HSeparator.new())
	# The ladder ahead: the next few tiers and what each brings.
	for ahead: int in range(tier + 1, tier + 6):
		var unlock := _Ranks.unlock_at(ahead)
		if unlock == "":
			continue
		var row := _text("%s: %s" % [_Ranks.title(ahead), _Strings.unlock_name(unlock)], 13, SOFT)
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.custom_minimum_size.x = 300
		_list.add_child(row)


## The crew's hired hands (net/crew/hires.gd): who, how good, what they cost,
## and buttons to hire one more or let one go.
func _hires() -> void:
	var hires := get_tree().get_first_node_in_group("hires")
	if hires == null:
		return
	_list.add_child(HSeparator.new())
	var slots := int(hires.call("slots"))
	if slots <= 0:
		_list.add_child(_text(_Strings.UI["phone_hires_locked"] % _Ranks.title(_Ranks.tier_of("feature:hiring")), 14, SOFT))
		return
	var hands: Array = hires.get("hands")
	_list.add_child(_text(_Strings.UI["phone_hires_title"] % [hands.size(), slots], 17, INK))
	for entry: Variant in hands:
		var hand := entry as Dictionary
		var row := HBoxContainer.new()
		var line := _text(_Strings.UI["phone_hire_line"] % [str(hand["name"]), int(round(float(hand["skill"]) * 100.0)), int(hand["wage"]), int(hand.get("bags", 0))], 14, INK)
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(line)
		var fire := Button.new()
		fire.text = _Strings.UI["phone_fire"]
		fire.focus_mode = Control.FOCUS_NONE
		var hand_name := str(hand["name"])
		fire.pressed.connect(func() -> void: hires.call("request_fire", hand_name))
		row.add_child(fire)
		_list.add_child(row)
	if bool(hires.call("can_hire")):
		var hire := Button.new()
		hire.text = _Strings.UI["phone_hire"] % [Constants.HIRE_SIGNING_FEE, Constants.HIRE_DAILY_WAGE]
		hire.focus_mode = Control.FOCUS_NONE
		hire.disabled = Campaign.credits(Net.local_peer_id()) < Constants.HIRE_SIGNING_FEE
		hire.pressed.connect(func() -> void: hires.call("request_hire"))
		_list.add_child(hire)


# ---------------------------------------------------------------- bits

func _hearts(relationship: float) -> String:
	var full := int(round(relationship / 20.0))
	return "♥".repeat(full) + "♡".repeat(5 - full)


func _picky(standards: float) -> String:
	if standards < 0.25:
		return "easy to please"
	if standards < 0.5:
		return "a little picky"
	if standards < 0.75:
		return "picky"
	return "impossible"


func _text(value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _box(color: Color, radius: int, border: Color, border_width: int, margin: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.border_color = border
	box.set_border_width_all(border_width)
	box.content_margin_left = margin
	box.content_margin_right = margin
	box.content_margin_top = margin
	box.content_margin_bottom = margin
	return box
