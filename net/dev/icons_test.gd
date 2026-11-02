extends Node

## Authority: local (run on the host alone). --icons-test checks the icon set
## (ui/icons.gd, assets/icons/, tools/studio/icon_recipes.gd; gap-specs/icons.json
## chunk C, adjusted by gap-specs/critic.md C4, C5, C9, C10 and C32):
##   ids          every Icons.IDS id loads, at most MAX_PX on a side; an unknown
##                id gives null (the fallback), not an error
##   recipes      icon_recipes.RECIPES has exactly the IDS keys, both ways, so the
##                generator can rebuild every icon
##   coverage     every tool, task, upgrade, phone app (and the reserved ones),
##                rank tier, mood, season, neighborhood and rank unlock (UNLOCKS,
##                and EXTRA_UNLOCKS that aren't shop items) has an icon, and
##                every rebindable action's key has a keycap; a rebound key
##                shows its own cap at once
##   tokens       every {key:a} / {icon:x} in ui/strings.gd names a real action
##                with a keycap or a real icon; plain() leaves no token behind;
##                rich() draws the keycap, plain() the "[E]" text; '[' is escaped
##   window_icon  project.godot names app_icon.png, and app_icon.ico is a real
##                .ico with at least 4 sizes
## The checks of the UI that shows the icons (shop, board, phone, hud, prompt),
## of the prompt string's tokens and of the shop catalog's icons are written here
## too, but they belong to later chunks. Until a check's chunk lands it is in
## PENDING: it still runs, and its findings go in result["pending"], but it can't
## fail the test. The chunk that builds it deletes its PENDING line (critic.md:
## icons:D, icons:E and icons:F turn on theirs; icons:F turns on prompt_format
## once settings:4 has tokenized the prompt; icons:catalog turns on catalog).
## It never renders, so it runs headless. Each check prints an [IconsTest] line.

const _Icons = preload("res://ui/icons.gd")
const _Strings = preload("res://ui/strings.gd")
const _Ranks = preload("res://core/ranks.gd")
const _Seasons = preload("res://core/seasons.gd")
const _Hoods = preload("res://net/town/neighborhoods.gd")
const _Phone = preload("res://ui/phone.gd")
const RECIPES_PATH := "res://tools/studio/icon_recipes.gd"
const ICO_PATH := "res://assets/icons/app_icon.ico"
const APP_ICON_PATH := "res://assets/icons/app_icon.png"

## Check -> the chunk that turns it on (and deletes its line here).
const PENDING: Dictionary = {
	"shop": "icons:D",
	"board": "icons:D",
	"phone": "icons:E",
	"hud": "icons:E",
	"prompt": "icons:F",
	"prompt_format": "settings:4, then icons:F",
	"catalog": "icons:catalog",
}
## The actions a prompt names most; they need a keycap whatever Settings lists.
const PROMPT_ACTIONS: Array[StringName] = [
	&"interact", &"take", &"drop", &"primary", &"secondary", &"phone", &"pause",
	&"push_to_talk", &"jump", &"sprint", &"crouch",
]
## Apps the phone will grow into (critic.md C10), on top of phone.gd APPS.
const RESERVED_APPS: Array[String] = ["hires", "shop", "deliveries", "properties", "closet"]
## How long the UI (the game_ui, phone, town and day_clock groups) may take to come up.
const UI_TIMEOUT_SECONDS: float = 15.0
## How long the checks may take once the UI is up before the watchdog ends the run.
const RUN_TIMEOUT_SECONDS: float = 15.0
## Every check, in the order _run runs them (the watchdog's "not reached" list).
const CHECK_ORDER: Array[String] = [
	"ids", "recipes", "coverage", "tokens", "prompt_format", "catalog", "window_icon",
	"shop", "board", "phone", "hud", "prompt",
]
## Frames a window gets to build and lay out before it is measured.
const LAYOUT_FRAMES: int = 3
## A window must fit the design resolution with this margin on each axis.
const FIT_MARGIN_PX: float = 16.0
## The .ico must carry at least this many sizes (16, 32, 48, 256).
const ICO_MIN_IMAGES: int = 4
const PROMPT_KEY_PX: int = 30

static var result: Dictionary = {}

var _started: bool = false
var _waited: float = 0.0
var _run_waited: float = 0.0
## The check _run is in, "" when none is.
var _running: String = ""
## Every finding, by check name; a check passed when its list is empty.
var _found: Dictionary = {}
var _out: Dictionary = {}


func _process(delta: float) -> void:
	_waited += delta
	if _started:
		_run_waited += delta
		if _run_waited > RUN_TIMEOUT_SECONDS and not result.get("done", false):
			_watchdog()
		return
	var tree := get_tree()
	var ready := Net.current_state() == Net.State.IN_SESSION
	for group: String in ["game_ui", "phone", "town", "day_clock"]:
		ready = ready and tree.get_first_node_in_group(group) != null
	if not ready:
		if _waited > UI_TIMEOUT_SECONDS:
			_started = true
			_finish("ui never came up")
		return
	_started = true
	_run()


func _run() -> void:
	await get_tree().create_timer(0.5).timeout
	_check(_begin("ids"), _ids())
	_check(_begin("recipes"), _recipes())
	_check(_begin("coverage"), _coverage())
	_check(_begin("tokens"), _tokens())
	_check(_begin("prompt_format"), _prompt_format())
	_check(_begin("catalog"), _catalog())
	_check(_begin("window_icon"), _window_icon())
	_check(_begin("shop"), await _shop())
	_check(_begin("board"), await _board())
	_check(_begin("phone"), await _phone())
	_check(_begin("hud"), await _hud())
	_check(_begin("prompt"), _prompt())
	_running = ""
	if not result.get("done", false):
		_finish("")


## Names the check about to run, so the watchdog can tell which one stalled.
func _begin(check_name: String) -> String:
	_running = check_name
	return check_name


## A check that hit a script error never returns, and _run dies with it. After
## RUN_TIMEOUT_SECONDS this ends the run anyway: the stalled check and any not
## reached get one gap each, so a stalled PENDING check still can't fail the run,
## while a live check that stalled or never ran fails it with an error.
func _watchdog() -> void:
	var stalled := _running
	if stalled != "":
		_found[stalled] = ["aborted (script error?)"]
		print("[IconsTest] %s: aborted" % stalled)
	var error := ""
	for check_name: String in CHECK_ORDER:
		if _found.has(check_name):
			continue
		_found[check_name] = ["not reached"]
		if not PENDING.has(check_name) and error == "":
			error = "%s was not reached" % check_name
	if stalled != "" and not PENDING.has(stalled):
		error = "%s aborted" % stalled
	_finish(error)


# ---------------------------------------------------------------- checks

func _ids() -> Variant:
	var missing: Array[String] = []
	var oversize: Array[String] = []
	for id: String in _Icons.IDS:
		var found := _Icons.texture(id)
		if found == null:
			missing.append(id)
			continue
		var w := found.get_width()
		var h := found.get_height()
		if w <= 0 or h <= 0 or w > _Icons.MAX_PX or h > _Icons.MAX_PX:
			oversize.append("%s %dx%d" % [id, w, h])
	_out["ids"] = _Icons.IDS.size()
	_out["missing"] = missing
	_out["oversize"] = oversize
	var gaps: Array[String] = []
	gaps.append_array(missing)
	gaps.append_array(oversize)
	# The fallback: an unknown id is null (it warns once), never an error.
	if _Icons.texture("no_such_icon") != null or _Icons.has("no_such_icon"):
		gaps.append("no_such_icon resolved")
	if _Icons.texture("") != null:
		gaps.append("the empty id resolved")
	return gaps


func _recipes() -> Variant:
	var gaps: Array[String] = []
	var script := load(RECIPES_PATH) as Script
	if script == null:
		gaps.append("%s does not load" % RECIPES_PATH)
		_out["recipe_gaps"] = gaps
		return gaps
	var recipes: Dictionary = script.get_script_constant_map().get("RECIPES", {})
	for id: String in _Icons.IDS:
		if not recipes.has(id):
			gaps.append("no recipe for " + id)
	for id: Variant in recipes:
		if not _Icons.IDS.has(str(id)):
			gaps.append("recipe %s is not in IDS" % id)
	_out["recipe_gaps"] = gaps
	return gaps


func _coverage() -> Variant:
	var gaps: Array[String] = []
	for tool_id: String in Constants.TOOL_PRICES:
		_need(gaps, "tool " + tool_id, _Icons.for_tool(tool_id))
		_need(gaps, "kind " + tool_id, _Icons.for_kind(tool_id))
	for task_id: String in Constants.TASK_TOOLS:
		_need(gaps, "task " + task_id, _Icons.for_task(task_id))
	_need(gaps, "rake_leaves", _Icons.for_task("rake_leaves"))
	for upgrade: StringName in [Campaign.RAKE_UPGRADE, Campaign.WHEELBARROW_UPGRADE]:
		_need(gaps, "upgrade " + String(upgrade), _Icons.for_shop_item(upgrade))
	var apps: Array[String] = []
	apps.append_array(_Phone.APPS)
	for app: String in RESERVED_APPS:
		if not apps.has(app):
			apps.append(app)
	for app: String in apps:
		_need(gaps, "app " + app, _Icons.for_app(app))
	for tier: int in _Ranks.NAMES.size() * _Ranks.TIERS_PER_RANK + 4:
		_need(gaps, "rank tier %d" % tier, _Icons.for_rank(tier))
	for mood: Variant in _Strings.MOOD_NAMES:
		_need(gaps, "mood " + str(mood), _Icons.for_mood(str(mood)))
	for index: int in _Seasons.IDS.size():
		_need(gaps, "season " + _Seasons.IDS[index], _Icons.for_season(index))
	for hood: Dictionary in _Hoods.HOODS:
		_need(gaps, "hood " + str(hood["id"]), _Icons.for_hood(str(hood["id"])))
	for unlock: String in _Ranks.UNLOCKS:
		_need(gaps, "unlock " + unlock, _Icons.for_unlock(unlock))
	for tier: Variant in _Ranks.EXTRA_UNLOCKS:
		for unlock: String in _Ranks.EXTRA_UNLOCKS[tier]:
			# Shop items' art (supplies, hats, paint ...) is icons:catalog's: see _catalog().
			if not unlock.begins_with("shop:"):
				_need(gaps, "extra unlock " + unlock, _Icons.for_unlock(unlock))
	for kind: Variant in _Icons.TEXT_AVATARS:
		_need(gaps, "text avatar " + str(kind), str(_Icons.TEXT_AVATARS[kind]))
	var actions: Array[StringName] = []
	actions.append_array(PROMPT_ACTIONS)
	if Settings.has_method("rebindable_actions"):
		for action: StringName in Settings.call("rebindable_actions"):
			if not actions.has(action):
				actions.append(action)
	for action: StringName in actions:
		if not InputMap.has_action(action):
			continue
		var id := _Icons.key_id(action)
		if id == "" or not _Icons.has(id):
			gaps.append("key for %s (%s, '%s')" % [action, _Icons.key_label(action), id])
	gaps.append_array(_rebind())
	_out["coverage_gaps"] = gaps
	return gaps


## A rebound key shows its own cap and its own text at once (critic.md C5).
func _rebind() -> Array[String]:
	var gaps: Array[String] = []
	var saved: Array[InputEvent] = InputMap.action_get_events(&"interact")
	InputMap.action_erase_events(&"interact")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_R
	InputMap.action_add_event(&"interact", event)
	var cap := _Icons.key_id(&"interact")
	var text := _Strings.keyed("{key:interact}")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_WHEEL_UP
	InputMap.action_erase_events(&"interact")
	InputMap.action_add_event(&"interact", mouse)
	var wheel := _Icons.key_id(&"interact")
	InputMap.action_erase_events(&"interact")
	for old: InputEvent in saved:
		InputMap.action_add_event(&"interact", old)
	if cap != "key_r":
		gaps.append("rebound to R, the cap is '%s'" % cap)
	if text != "[R]":
		gaps.append("rebound to R, the text is '%s'" % text)
	if wheel != "wheel_up":
		gaps.append("rebound to the wheel, the cap is '%s'" % wheel)
	if _Icons.key_id(&"interact") != "key_e":
		gaps.append("interact not back on E after the rebind check")
	return gaps


func _tokens() -> Variant:
	var gaps: Array[String] = []
	var tokens := RegEx.create_from_string("\\{(key|icon):([a-z0-9_]+)\\}")
	var texts: Array[Array] = []
	var strings: Script = _Strings
	_strings_in(strings.get_script_constant_map(), "Strings", texts)
	var count := 0
	for entry: Array in texts:
		var where := str(entry[0])
		var text := str(entry[1])
		var found := tokens.search_all(text)
		if found.is_empty():
			continue
		for token: RegExMatch in found:
			count += 1
			var value := token.get_string(2)
			if token.get_string(1) == "key":
				if not InputMap.has_action(StringName(value)):
					gaps.append("%s: no action '%s'" % [where, value])
				elif _Icons.for_action(StringName(value)) == "":
					gaps.append("%s: no keycap for '%s'" % [where, value])
			elif not _Icons.IDS.has(value):
				gaps.append("%s: no icon '%s'" % [where, value])
		var plain := _Icons.plain(text)
		if tokens.search(plain) != null or plain.contains("{key:") or plain.contains("{icon:"):
			gaps.append("%s: plain() left a token: %s" % [where, plain])
	var sample := "{key:interact}  Hide"
	var rich := _Icons.rich(sample, PROMPT_KEY_PX)
	if not rich.contains("key_e.png"):
		gaps.append("rich(%s) has no key_e.png: %s" % [sample, rich])
	if _Icons.plain(sample) != "[E]  Hide":
		gaps.append("plain(%s) is '%s'" % [sample, _Icons.plain(sample)])
	if _Icons.rich("a[b", PROMPT_KEY_PX) != "a[lb]b":
		gaps.append("rich('a[b') is '%s', not escaped" % _Icons.rich("a[b", PROMPT_KEY_PX))
	if _Icons.rich("{key:no_such_action}", PROMPT_KEY_PX).contains("[img"):
		gaps.append("a token naming no action drew a picture")
	_out["tokens"] = count
	_out["token_gaps"] = gaps
	return gaps


## The interaction prompt as the game formats it: settings:4 turns prompt_format
## into a "{key:%s}  %s" string; until then it hard-codes its key.
func _prompt_format() -> Variant:
	var gaps: Array[String] = []
	var format := str(_Strings.UI.get("prompt_format", ""))
	if not format.contains("{key:%s}"):
		gaps.append("prompt_format '%s' has no {key:%%s} token yet" % format)
		return gaps
	var text := format % ["interact", "Hide"]
	if not _Icons.rich(text, PROMPT_KEY_PX).contains("key_e.png"):
		gaps.append("rich(prompt_format) has no key_e.png")
	if _Icons.plain(text) != "[E]  Hide":
		gaps.append("plain(prompt_format) is '%s'" % _Icons.plain(text))
	return gaps


## Every Catalog item, and every shop item a rank unlocks, has an icon
## (critic.md C9 and C32; the art is the icons:catalog chunk's).
func _catalog() -> Variant:
	var gaps: Array[String] = []
	for item_id: Variant in Catalog.ITEMS:
		var id := _Icons.for_shop_item(StringName(str(item_id)))
		if id == "" or not _Icons.has(id):
			gaps.append("%s ('%s')" % [item_id, id])
	for tier: Variant in _Ranks.EXTRA_UNLOCKS:
		for unlock: String in _Ranks.EXTRA_UNLOCKS[tier]:
			if unlock.begins_with("shop:"):
				var id := _Icons.for_unlock(unlock)
				if id == "" or not _Icons.has(id):
					gaps.append("%s ('%s')" % [unlock, id])
	_out["catalog_gaps"] = gaps
	return gaps


func _window_icon() -> Variant:
	var gaps: Array[String] = []
	var icon := str(ProjectSettings.get_setting("application/config/icon", ""))
	if icon != APP_ICON_PATH:
		gaps.append("config/icon is '%s'" % icon)
	if not ResourceLoader.exists(APP_ICON_PATH):
		gaps.append(APP_ICON_PATH + " missing")
	var native := str(ProjectSettings.get_setting("application/config/windows_native_icon", ""))
	if native != ICO_PATH:
		gaps.append("config/windows_native_icon is '%s'" % native)
	var bytes := FileAccess.get_file_as_bytes(ICO_PATH)
	if bytes.size() < 6:
		gaps.append("%s unreadable (%d bytes)" % [ICO_PATH, bytes.size()])
	else:
		if bytes[0] != 0 or bytes[1] != 0 or bytes[2] != 1 or bytes[3] != 0:
			gaps.append("%s header is %02x %02x %02x %02x" % [ICO_PATH, bytes[0], bytes[1], bytes[2], bytes[3]])
		var images := bytes.decode_u16(4)
		_out["ico_images"] = images
		if images < ICO_MIN_IMAGES:
			gaps.append("%s has %d images" % [ICO_PATH, images])
	_out["window_icon"] = gaps.is_empty()
	return gaps


# ---------------------------------------------------------------- UI checks (pending until D to F)

func _shop() -> Variant:
	var gaps: Array[String] = []
	var ui := get_tree().get_first_node_in_group("game_ui")
	var shop := ui.get_node_or_null("ShopWindow") as Control
	if shop == null or not ui.has_method("open_store"):
		gaps.append("no ShopWindow")
		return gaps
	ui.call("open_store")
	await _frames(LAYOUT_FRAMES)
	var cards := shop.get("_cards") as Control
	var card_count := cards.get_child_count() if cards != null else 0
	_out["shop_cards"] = card_count
	if cards == null:
		gaps.append("no cards grid")
	elif shop.has_method("_items") and card_count != (shop.call("_items") as Array).size():
		gaps.append("%d cards for %d items" % [card_count, (shop.call("_items") as Array).size()])
	var shelf: Array[String] = _icons_under(cards)
	_out["shop_icons"] = shelf.size()
	if card_count == 0 or shelf.size() < card_count:
		gaps.append("%d shelf icons for %d cards" % [shelf.size(), card_count])
	for id: String in ["brand_homie_depot", "cash"]:
		if not _icons_under(shop).has(id):
			gaps.append("no %s icon in the window" % id)
	var fits := _fits(shop)
	_out["shop_fits"] = fits
	if not fits:
		gaps.append("shop is %s, the window %s" % [shop.size, _design_size()])
	if shop.has_method("close_window"):
		shop.call("close_window")
	return gaps


func _board() -> Variant:
	var gaps: Array[String] = []
	var ui := get_tree().get_first_node_in_group("game_ui")
	var board := ui.get_node_or_null("JobBoardWindow") as Control
	if board == null or not ui.has_method("open_job_board"):
		gaps.append("no JobBoardWindow")
		return gaps
	ui.call("open_job_board")
	await _frames(LAYOUT_FRAMES)
	var cards := board.get("_board_cards") as Control
	var offers: Array[Node] = []
	if cards != null:
		offers = cards.get_children()
	_out["board_cards"] = offers.size()
	if offers.is_empty():
		gaps.append("no offer cards")
	var badged := 0
	for card: Node in offers:
		if _icons_under(card).any(func(id: String) -> bool: return id.begins_with("task_")):
			badged += 1
	_out["board_badges"] = badged
	if badged < offers.size():
		gaps.append("%d of %d offer cards have a task badge" % [badged, offers.size()])
	if board.has_method("close_window"):
		board.call("close_window")
	else:
		board.visible = false
	return gaps


func _phone() -> Variant:
	var gaps: Array[String] = []
	var phone := get_tree().get_first_node_in_group("phone") as Control
	for method: String in ["open_phone", "show_app", "close_phone"]:
		if phone == null or not phone.has_method(method):
			gaps.append("the phone has no %s()" % method)
	if not gaps.is_empty():
		return gaps
	phone.call("open_phone", "crew")
	await _frames(LAYOUT_FRAMES)
	var tabs: Dictionary = phone.get("_tabs") if phone.get("_tabs") is Dictionary else {}
	var bare: Array[String] = []
	for app: Variant in tabs:
		var button := tabs[app] as Button
		if button == null or button.icon == null:
			bare.append(str(app))
	_out["phone_tab_icons"] = not tabs.is_empty() and bare.is_empty()
	if tabs.is_empty() or not bare.is_empty():
		gaps.append("tabs without an icon: %s" % [bare])
	var badge := _icons_under(phone).any(func(id: String) -> bool: return id.begins_with("rank_"))
	_out["crew_badge"] = badge
	if not badge:
		gaps.append("no rank badge on the crew app")
	phone.call("show_app", "map")
	await _frames(LAYOUT_FRAMES)
	var pins := _icons_under(phone).filter(func(id: String) -> bool: return id.begins_with("hood_")).size()
	_out["map_pins"] = pins
	if pins != _Hoods.HOODS.size():
		gaps.append("%d hood pins for %d hoods" % [pins, _Hoods.HOODS.size()])
	phone.call("show_app", "texts")
	await _frames(LAYOUT_FRAMES)
	# A bubble is a node with meta "text_bubble"; its avatar is an icon under it.
	var bubbles := _with_meta(phone, "text_bubble")
	var bare_bubbles := bubbles.filter(func(bubble: Node) -> bool: return _icons_under(bubble).is_empty()).size()
	var town := get_tree().get_first_node_in_group("town")
	var texts := (town.get("texts") as Array).size() if town != null and town.get("texts") is Array else 0
	_out["texts_avatars"] = bubbles.size() - bare_bubbles
	if texts > 0 and (bubbles.is_empty() or bare_bubbles > 0):
		gaps.append("%d texts, %d bubbles, %d without an avatar" % [texts, bubbles.size(), bare_bubbles])
	phone.call("close_phone")
	return gaps


func _hud() -> Variant:
	var gaps: Array[String] = []
	var ui := get_tree().get_first_node_in_group("game_ui")
	var day_hud := ui.get_node_or_null("DayHud")
	var badge: TextureRect = null
	if day_hud != null:
		badge = day_hud.get("_rank_badge") as TextureRect
	_out["hud_rank_badge"] = badge != null and badge.texture != null
	if badge == null or badge.texture == null:
		gaps.append("day_hud has no rank badge")
	var rows := ui.get("_hud_rows") as Node
	if rows == null or not _icons_under(rows).has("cash"):
		gaps.append("ui_root _hud_rows has no cash icon")
	var list := preload("res://ui/task_list.gd").new() as Node
	add_child(list)
	if not list.has_method("_task_line"):
		gaps.append("task_list has no _task_line()")
	else:
		var line := list.call("_task_line", "mow_lawn", 0.5) as Node
		if line == null or not _icons_under(line).has("task_mow_lawn"):
			gaps.append("task_list row has no task_mow_lawn badge")
		if line != null and line.get_parent() == null:
			line.free()
	list.queue_free()
	var heat := ui.get_node_or_null("HeatMeter")
	if heat == null or not _icons_under(heat).has("heat"):
		gaps.append("heat_meter has no heat icon")
	return gaps


func _prompt() -> Variant:
	var ui := get_tree().get_first_node_in_group("game_ui")
	var prompt := ui.get_node_or_null("InteractionPrompt")
	var ok := prompt is Control and not _of_class(prompt, "RichTextLabel").is_empty()
	_out["prompt"] = ok
	var gaps: Array[String] = []
	if not ok:
		gaps.append("InteractionPrompt is a %s, not a Control with a RichTextLabel" % (prompt.get_class() if prompt != null else "missing node"))
	return gaps


# ---------------------------------------------------------------- helpers

func _need(gaps: Array[String], what: String, id: String) -> void:
	if id == "" or not _Icons.has(id):
		gaps.append("%s ('%s')" % [what, id])


## Every String in a constant table, as [path, text], walking dictionaries and arrays.
func _strings_in(value: Variant, where: String, into: Array[Array]) -> void:
	if value is String or value is StringName:
		into.append([where, str(value)])
	elif value is Dictionary:
		for key: Variant in value:
			_strings_in(value[key], "%s.%s" % [where, key], into)
	elif value is Array or value is PackedStringArray:
		for index: int in (value as Array).size() if value is Array else (value as PackedStringArray).size():
			_strings_in(value[index], "%s[%d]" % [where, index], into)


## The "icon" meta of every node under root (root included) that shows a texture.
func _icons_under(root: Node) -> Array[String]:
	var ids: Array[String] = []
	if root == null:
		return ids
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.has_meta("icon") and node is TextureRect and (node as TextureRect).texture != null:
			ids.append(str(node.get_meta("icon")))
		stack.append_array(node.get_children())
	return ids


func _with_meta(root: Node, meta: StringName) -> Array[Node]:
	var nodes: Array[Node] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.has_meta(meta):
			nodes.append(node)
		stack.append_array(node.get_children())
	return nodes


func _of_class(root: Node, type: String) -> Array[Node]:
	var nodes: Array[Node] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.is_class(type):
			nodes.append(node)
		stack.append_array(node.get_children())
	return nodes


func _design_size() -> Vector2:
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 1280)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 720)))


func _fits(window: Control) -> bool:
	var room := _design_size() - Vector2(FIT_MARGIN_PX, FIT_MARGIN_PX)
	return window.size.x > 0.0 and window.size.x <= room.x and window.size.y <= room.y


func _frames(count: int) -> void:
	for _frame: int in count:
		await get_tree().process_frame


## Checks return Variant and this takes it untyped on purpose: a check that hits a
## script error returns null (a typed Array[String] return would come back empty,
## a false pass, and a typed parameter would turn null into an error that kills
## _run), and null becomes a gap here.
func _check(check_name: String, returned: Variant) -> void:
	var gaps: Array[String] = []
	if returned is Array:
		for gap: Variant in returned:
			gaps.append(str(gap))
	else:
		gaps.append("returned %s, not a gap list (script error?)" % type_string(typeof(returned)))
	_found[check_name] = gaps
	var note := " (pending: %s)" % PENDING[check_name] if PENDING.has(check_name) else ""
	print("[IconsTest] %s: %s%s" % [check_name, "ok" if gaps.is_empty() else "%d gaps" % gaps.size(), note])
	for gap: String in gaps.slice(0, 12):
		print("[IconsTest]   %s" % gap)
	if gaps.size() > 12:
		print("[IconsTest]   ... and %d more" % (gaps.size() - 12))


func _finish(error: String) -> void:
	var failed: Array[String] = []
	var pending: Dictionary = {}
	for check_name: String in _found:
		var gaps: Array = _found[check_name]
		if PENDING.has(check_name):
			pending[check_name] = {"chunk": PENDING[check_name], "passed": gaps.is_empty(), "gaps": gaps.size()}
		elif not gaps.is_empty():
			failed.append(check_name)
	result = _out.duplicate(true)
	for key: String in ["missing", "oversize", "recipe_gaps", "coverage_gaps", "token_gaps", "catalog_gaps"]:
		if not result.has(key):
			result[key] = []
	result["checks"] = _found.size()
	result["failed"] = failed
	result["pending"] = pending
	result["error"] = error
	result["ok"] = error == "" and failed.is_empty() and bool(result.get("window_icon", false))
	result["done"] = true
	print("[IconsTest] done, ok=%s, failed %s, pending %s%s" % [result["ok"], failed, pending.keys(), (", error: " + error) if error != "" else ""])
