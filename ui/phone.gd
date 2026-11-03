extends PanelContainer

## Authority: local. The crew phone (docs/SPINE.md, "The phone"). Tab takes it
## out and puts it away. Four apps: Texts (job requests you can take from here,
## referrals, the clerk), Clients (everyone you work for and how they feel about
## you), Map (the neighborhoods and what opens them), and Crew (the rank, XP,
## and perks). Everything it shows comes from net/town/town.gd, the day clock,
## and Campaign; taking a job asks the job board, like walking up to it.
## Every app wears its icons (gap-specs/icons.json chunk E; docs/GAME.md, "Icons"):
## app tiles in the dock, the app's tile in the header, an avatar on every text,
## heart rows for clients, hood pins on the map, the crew's rank badge and a
## badge-and-unlock ladder. A tapped tile bounces with ui_pop.

const _Strings = preload("res://ui/strings.gd")
const _Ranks = preload("res://core/ranks.gd")
const _Hoods = preload("res://net/town/neighborhoods.gd")
const _Icons = preload("res://ui/icons.gd")
const _Look = preload("res://ui/catalog_look.gd")
const BEZEL := Color(0.1, 0.1, 0.12)
const SCREEN := Color(0.96, 0.95, 0.92)
const INK := Color(0.15, 0.15, 0.17)
const SOFT := Color(0.45, 0.45, 0.5)
const ORANGE := Color(0.93, 0.47, 0.13)
const GREEN := Color(0.2, 0.6, 0.3)
const BUBBLE := Color(0.88, 0.9, 0.95)
const BUBBLE_JOB := Color(1.0, 0.92, 0.8)
## gap-specs/critic.md fixes the order: texts, clients, map, crew, deliveries
## (shops chunk 8), closet (shops chunk 7).
const APPS: Array[String] = ["texts", "clients", "map", "crew", "closet"]
const HEART := Color(0.85, 0.25, 0.3)
## How wide a line of words is on the screen; a text's words leave room for its avatar.
const LINE_WIDTH: float = 300.0
const TEXT_WIDTH: float = LINE_WIDTH - _Icons.SIZE_AVATAR - 8.0
## Icon sizes inside the apps, in pixels of height.
const HEADER_ICON_PX: float = 28.0
const DOCK_TILE := Vector2(64, 64)
const DOCK_FONT: int = 12
const HEART_PX: float = 16.0
const LIKES_PX: float = 18.0
const PIN_PX: float = 28.0
const LOCK_PX: float = 18.0
const CREW_BADGE_PX: float = 72.0
const STAT_PX: float = 18.0
const LADDER_PX: float = 20.0

var _app: String = "texts"
var _header: Label
var _header_icon: Control
var _list: VBoxContainer
var _scroll: ScrollContainer
var _tabs: Dictionary = {}
var _dirty: bool = true
## How many of the town's texts the phone has shown.
var _seen: int = 0


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
	top.add_theme_constant_override("separation", 8)
	column.add_child(top)
	# The open app's own tile, beside its name (swapped in _rebuild).
	_header_icon = _Icons.rect(_Icons.for_app(_app), HEADER_ICON_PX)
	_header_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_header_icon)
	_header = _text("", 22, INK)
	_header.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_header)
	var close := Button.new()
	close.text = _Strings.UI["phone_close_x"]
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
		# A home-screen tile: the app's icon over its name.
		var button := Button.new()
		button.text = _Strings.UI["phone_tab_" + app]
		button.icon = _Icons.texture(_Icons.for_app(app))
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.custom_minimum_size = DOCK_TILE
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", DOCK_FONT)
		button.add_theme_constant_override("icon_max_width", _Icons.SIZE_DOCK)
		button.pressed.connect(func() -> void:
			_bounce(button)
			_Look.sfx(self, "ui_pop")
			show_app(app)
		)
		dock.add_child(button)
		_tabs[app] = button
	_hook_world.call_deferred()


func _hook_world() -> void:
	# The town and the board come and go with the session: hook the ones there
	# now, and every one added later.
	for existing: Node in [get_tree().get_first_node_in_group("town"), get_tree().get_first_node_in_group("job_board"), get_tree().get_first_node_in_group("hires"), get_tree().get_first_node_in_group("shops")]:
		if existing != null:
			_watch(existing)
	get_tree().node_added.connect(func(node: Node) -> void:
		if node.name == "Town" or node.name == "JobBoard" or node.name == "Hires" or node.name == "Shops":
			_watch(node)
	)
	Campaign.unlocks_changed.connect(_mark_dirty)
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


## How many texts came in since the phone was last out (the HUD shows it),
## the welcome texts of a new game included.
func unread() -> int:
	var town := get_tree().get_first_node_in_group("town")
	if town == null or visible:
		return 0
	return maxi(0, (town.get("texts") as Array).size() - _seen)


func open_phone(app: String = "") -> void:
	visible = true
	var town := get_tree().get_first_node_in_group("town")
	_seen = (town.get("texts") as Array).size() if town != null else 0
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
	_swap_icon(_header_icon, _Icons.for_app(_app))
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
		"closet":
			_closet()


# ---------------------------------------------------------------- apps

## Closet (shops chunk 7): the hats and shirts you own, each with Wear, and your
## own look (what your name gives you) to go back to. Wearing one asks the host
## (Shops.request_equip); everyone sees it go on.
func _closet() -> void:
	var shops := get_tree().get_first_node_in_group("shops")
	if shops == null:
		return
	var me := Net.local_peer_id()
	var look: Dictionary = shops.call("look_of", me)
	# What you have on is the greyed-out Wearing button in its row; no summary
	# line restating it (W8).
	var any := false
	for slot: String in ["hat", "shirt"]:
		var owned: Array[String] = []
		for id: String in Catalog.ITEMS:
			var entry: Dictionary = Catalog.ITEMS[id]
			if str(entry.get("kind", "")) == "cosmetic" and str(entry.get("slot", "")) == slot and bool(shops.call("owns", me, id)):
				owned.append(id)
		if owned.is_empty():
			continue
		any = true
		_list.add_child(_text(str(_Strings.SHOP_UI["closet_hats" if slot == "hat" else "closet_shirts"]), 15, ORANGE))
		owned.push_front("")
		for id: String in owned:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			row.set_meta("closet_item", id)
			if id != "":
				var icon_id := _Icons.for_shop_item(StringName(id))
				var picture := _Icons.rect(icon_id, STAT_PX * 1.5)
				if icon_id == "shirt":
					picture.modulate = Constants.SHIRT_DYES[clampi(int(Catalog.item(id).get("shirt", 0)), 0, Constants.SHIRT_DYES.size() - 1)] if typeof(Catalog.item(id).get("shirt", 0)) == TYPE_INT else Color(0.82, 0.98, 0.16)
				row.add_child(picture)
			var label := _text(_Strings.shop_item_name(id) if id != "" else str(_Strings.SHOP_UI["closet_own_look"]), 15, INK)
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(label)
			var wearing := str(look.get(slot, "")) == id
			var wear := Button.new()
			wear.focus_mode = Control.FOCUS_NONE
			wear.text = str(_Strings.SHOP_UI["shop_wearing"] if wearing else _Strings.SHOP_UI["closet_wear"])
			wear.disabled = wearing
			var item := id
			var which := slot
			wear.pressed.connect(func() -> void:
				_Look.sfx(self, "ui_pop")
				shops.call("request_equip", which, item)
			)
			row.add_child(wear)
			_list.add_child(row)
	if not any:
		var empty := _text(str(_Strings.SHOP_UI["closet_empty"]), 15, SOFT)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size.x = LINE_WIDTH
		_list.add_child(empty)

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
		bubble.set_meta("text_bubble", true)
		# Who it's from, as a face: Homie Depot's mark, a client card, TurfMasters...
		var from_row := HBoxContainer.new()
		from_row.add_theme_constant_override("separation", 8)
		bubble.add_child(from_row)
		var avatar := _Icons.rect(str(_Icons.TEXT_AVATARS.get(str(message.get("kind", "")), "app_texts")), _Icons.SIZE_AVATAR)
		avatar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		from_row.add_child(avatar)
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		from_row.add_child(column)
		var head := str(_Strings.UI["phone_text_head"]) % [str(message.get("from", "")), int(message.get("day", 1)), str(message.get("time", ""))]
		column.add_child(_text(head, 13, SOFT))
		var body := _text(str(message.get("text", "")), 16, INK)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size.x = TEXT_WIDTH
		column.add_child(body)
		if is_job:
			var house_id := int(message.get("house", -1))
			# In the connected town "up next" means its yard is waiting at the house;
			# a pick whose yard isn't loaded yet (the last job's yard is still up)
			# keeps its button.
			var waiting := world == null or not bool(world.call("is_town_map")) or int(world.call("job_site_house")) == house_id
			if house_id == picked and waiting:
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
			card.add_child(_heart_row(float(house.get("relationship", 0.0))))
			if bool(house.get("poached", false)):
				var poached := _text(_Strings.UI["phone_poached"], 14, Color(0.1, 0.5, 0.25))
				poached.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				poached.custom_minimum_size.x = LINE_WIDTH - LIKES_PX - 6.0
				card.add_child(_icon_line("brand_turfmasters", poached, LIKES_PX))
			var last := int(house.get("last_day", -1))
			var last_text: String = _Strings.UI["phone_last_never"]
			if last == today:
				last_text = _Strings.UI["phone_last_today"]
			elif last >= 0:
				last_text = _Strings.UI["phone_last_days"] % (today - last)
			var likes := str(owner.get("likes", ""))
			var likes_text := str(_Strings.UI.get("task_" + likes, "")) if likes != "" else ""
			var detail := _Strings.UI["phone_client_detail"] % [_picky(float(owner.get("standards", 0.3))), likes_text if likes_text != "" else str(_Strings.UI["phone_no_favorite"]), int(house.get("jobs", 0)), last_text]
			var detail_label := _text(detail, 13, SOFT)
			detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			if likes_text != "":
				# Their favorite job's badge leads the line that names it.
				detail_label.custom_minimum_size.x = LINE_WIDTH - LIKES_PX - 6.0
				card.add_child(_icon_line(_Icons.for_task(likes), detail_label, LIKES_PX))
			else:
				detail_label.custom_minimum_size.x = LINE_WIDTH
				card.add_child(detail_label)
			var blurb := str(_Strings.PERSONALITY_BLURBS.get(str(owner.get("personality", "")), ""))
			if blurb != "":
				var blurb_label := _text(blurb, 13, SOFT)
				blurb_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				blurb_label.custom_minimum_size.x = LINE_WIDTH
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
		var opens_at := _Ranks.tier_of("hood:" + hood_id)
		if open and known > 0:
			line = _Strings.UI["phone_hood_open"] % [str(hood["name"]), known]
		elif open:
			line = _Strings.UI["phone_hood_waiting"] % str(hood["name"])
			color = SOFT
		else:
			line = _Strings.UI["phone_hood_locked"] % [str(hood["name"]), _Ranks.title(opens_at)]
			color = SOFT
		var label := _text(line, 17, color)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var row := _Icons.row(_Icons.for_hood(hood_id), label, PIN_PX)
		if not open:
			# Faded pin, a lock, and the badge of the rank that opens it.
			(row.get_child(0) as Control).modulate = Color(1.0, 1.0, 1.0, 0.55)
			for icon: Control in [_Icons.rect("lock", LOCK_PX), _Icons.rect(_Icons.for_rank(opens_at), LADDER_PX)]:
				icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				row.add_child(icon)
		_list.add_child(row)
		var blurb := _text(str(_Strings.HOOD_BLURBS.get(hood_id, "")), 13, SOFT)
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		blurb.custom_minimum_size.x = LINE_WIDTH
		_list.add_child(blurb)


func _crew() -> void:
	var tier := Campaign.crew_tier()
	# The crew's rank badge, big, beside its title.
	var title := _text(_Ranks.title(tier), 24, ORANGE)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_child(_Icons.row(_Icons.for_rank(tier), title, CREW_BADGE_PX))
	var need := _Ranks.xp_for_tier(tier)
	var into := _Ranks.xp_into_tier(Campaign.crew_xp())
	_list.add_child(_Icons.row("xp", _text(_Strings.UI["hud_xp"] % [into, need, Campaign.pending_xp()], 15, INK), STAT_PX))
	var next := _Ranks.unlock_at(tier + 1)
	if next != "":
		var line := _text(_Strings.UI["phone_next_unlock"] % [_Strings.unlock_name(next), _Ranks.title(tier + 1)], 15, INK)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size.x = LINE_WIDTH - STAT_PX - 6.0
		_list.add_child(_icon_line(_Icons.for_unlock(next), line, STAT_PX))
	var perks := PackedStringArray()
	for unlock: String in _Ranks.unlocks_through(tier):
		if unlock.begins_with("perk:"):
			perks.append(_Strings.unlock_name(unlock))
	if not perks.is_empty():
		var perk_label := _text(_Strings.UI["phone_perks"] % ", ".join(perks), 13, SOFT)
		perk_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		perk_label.custom_minimum_size.x = LINE_WIDTH - STAT_PX - 6.0
		_list.add_child(_icon_line("perk", perk_label, STAT_PX))
	_hires()
	_list.add_child(HSeparator.new())
	# The ladder ahead: the next few tiers, each as its rank's badge, what it
	# brings, and the words.
	for ahead: int in range(tier + 1, tier + 6):
		var unlock := _Ranks.unlock_at(ahead)
		if unlock == "":
			continue
		var words := _text("%s: %s" % [_Ranks.title(ahead), _Strings.unlock_name(unlock)], 13, SOFT)
		words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		words.custom_minimum_size.x = LINE_WIDTH - LADDER_PX * 2.0 - 12.0
		var row := _icon_line(_Icons.for_rank(ahead), words, LADDER_PX)
		var brings := _Icons.rect(_Icons.for_unlock(unlock), LADDER_PX)
		brings.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(brings)
		row.move_child(brings, 1)
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
		var locked := _text(_Strings.UI["phone_hires_locked"] % _Ranks.title(_Ranks.tier_of("feature:hiring")), 14, SOFT)
		var row := _Icons.row("app_hires", locked, STAT_PX)
		(row.get_child(0) as Control).modulate = Color(1.0, 1.0, 1.0, 0.55)
		_list.add_child(row)
		return
	var hands: Array = hires.get("hands")
	_list.add_child(_Icons.row("app_hires", _text(_Strings.UI["phone_hires_title"] % [hands.size(), slots], 17, INK), HEADER_ICON_PX))
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

## The plain-text hearts, for logs and anything that can't show icons.
func _hearts(relationship: float) -> String:
	var full := _heart_count(relationship)
	return "♥".repeat(full) + "♡".repeat(5 - full)


func _heart_count(relationship: float) -> int:
	return clampi(int(round(relationship / 20.0)), 0, 5)


## Five heart icons, filled to how the client feels about the crew (0 to 100).
func _heart_row(relationship: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var full := _heart_count(relationship)
	for index: int in 5:
		row.add_child(_Icons.rect("heart" if index < full else "heart_empty", HEART_PX))
	return row


## An icon in front of a line that may wrap: the icon sits by its first line.
func _icon_line(id: String, label: Label, px: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := _Icons.rect(id, px)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(icon)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return row


## Points an icon made by Icons.rect at another id (the header's app tile).
func _swap_icon(icon: Control, id: String) -> void:
	var view := icon as TextureRect
	if view == null or str(icon.get_meta("icon", "")) == id:
		return
	var found := _Icons.texture(id)
	if found == null:
		return
	view.texture = found
	view.set_meta("icon", id)


## A tapped dock tile dips and springs back, like a home-screen icon.
func _bounce(tile: Control) -> void:
	tile.pivot_offset = tile.size * 0.5
	var running := tile.get_meta("bounce") as Tween if tile.has_meta("bounce") else null
	if running != null and running.is_valid():
		running.kill()
	var tween := tile.create_tween()
	tile.set_meta("bounce", tween)
	tween.tween_property(tile, "scale", Vector2.ONE * Constants.ICONS_DOCK_PRESS_SCALE, Constants.ICONS_DOCK_PRESS_SECONDS).set_ease(Tween.EASE_OUT)
	tween.tween_property(tile, "scale", Vector2.ONE, Constants.ICONS_DOCK_SETTLE_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _picky(standards: float) -> String:
	# UI picky_0 (under a quarter) to picky_3 (three quarters and up).
	var level := clampi(int(floor(standards * 4.0)), 0, 3)
	return str(_Strings.UI["picky_%d" % level])


func _text(value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	# Texts and lines may name keys ({key:phone}); the player reads their own.
	label.text = _Strings.keyed(value)
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
