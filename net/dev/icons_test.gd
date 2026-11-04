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
##   catalog      every Catalog item has its own icon (icons:catalog), every kit
##                kind at every tier, every junk type, every tier's chip
##   shop         every card of every shop's every tab (meta "item_id") shows that
##                item's own icon on its catalog shelf (Icons.for_shop_item,
##                ui/catalog_look.gd), the header has the brand mark and the
##                wallet's cash icon, and it fits 1280x720 at UI scales 0.75, 1
##                and 1.5
##   board        every job board offer card has task badges and a cash pay line
##   receipt      the payout receipt shows the bag, task, mood, bill, water, cash,
##                star, bonus, xp and split icons, and fits
##   summary      the day summary shows an icon on every line, the rank badge on a
##                RANK UP, the unlock's and season's icons, and fits
##   phone        every dock tile has its app icon, the crew app the rank badge,
##                the map one pin per neighborhood, every Orders row its item's
##                icon, every text bubble an avatar
##   hud          the day HUD's rank badge, the cash row, a task row's badge and
##                the heat meter's siren
##   prompt       the interaction prompt is a screen-space pill (a Control with a
##                RichTextLabel): its key is a keycap (key_e, or the hint's own
##                "key"), names are escaped, it sits centered on its point and
##                inside the screen, glides (never jumps) to a new thing, hides
##                behind the camera and while a window is open, and lands on its
##                point at UI scales 0.8 and 1.25 too (icons chunk F)
##   coin         a money popup carries a spinning cash coin left of its text,
##                turning in place (icons chunk F)
## A check written ahead of the chunk that builds what it checks goes in PENDING:
## it still runs, and its findings go in result["pending"], but it can't fail the
## test. The chunk that builds it deletes its PENDING line (icons:catalog turned
## on the last one, catalog).
## It never renders, so it runs headless. Each check prints an [IconsTest] line.

const _Icons = preload("res://ui/icons.gd")
const _Strings = preload("res://ui/strings.gd")
const _Ranks = preload("res://core/ranks.gd")
const _Seasons = preload("res://core/seasons.gd")
const _Hoods = preload("res://net/town/neighborhoods.gd")
const _Phone = preload("res://ui/phone.gd")
const _Prompt = preload("res://ui/interaction_prompt.gd")
const _WindowFit = preload("res://ui/window_fit.gd")
const RECIPES_PATH := "res://tools/studio/icon_recipes.gd"
const ICO_PATH := "res://assets/icons/app_icon.ico"
const APP_ICON_PATH := "res://assets/icons/app_icon.png"

## Check -> the chunk that turns it on (and deletes its line here). Empty since
## icons:catalog turned on the last one.
const PENDING: Dictionary = {}
## Icons more than one Catalog item may show (_catalog): they're the same thing
## (the Snak-o-Matic's bag roll, Lunch Money's trucker cap is the trucker hat).
const SHARED_ICONS: Array[String] = ["supply_lawn_bags"]
## The shop and its cards fit the screen at each of these UI scales (Settings'
## interface scale, the root's content_scale_factor).
const UI_SCALES: Array[float] = [0.75, 1.0, 1.5]
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
	"shop", "board", "receipt", "summary", "phone", "hud", "prompt", "coin",
]
## Frames a window gets to build and lay out before it is measured.
const LAYOUT_FRAMES: int = 3
## A window must fit the design resolution with this margin on each axis.
const FIT_MARGIN_PX: float = 16.0
## The .ico must carry at least this many sizes (16, 32, 48, 256).
const ICO_MIN_IMAGES: int = 4
const PROMPT_KEY_PX: int = 30
## The coin is sampled six times this far apart (inside its popup's 1.6 s life).
const COIN_SAMPLE_SECONDS: float = 0.07

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
	_check(_begin("receipt"), await _receipt())
	_check(_begin("summary"), await _summary())
	_check(_begin("phone"), await _phone())
	_check(_begin("hud"), await _hud())
	_check(_begin("prompt"), await _prompt())
	_check(_begin("coin"), await _coin())
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


## The interaction prompt as the game formats it: since settings:4, prompt_format
## is a "{key:%s}  %s" string (live from W5; icons:F keeps it passing).
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
## (critic.md C9 and C32; the art is the icons:catalog chunk's), and its own:
## no two items share one unless they're the same thing (the Snak-o-Matic's
## roll of bags is a roll of bags; shirt dyes share the tinted shirt; a hat sold
## twice is one hat). Every kit kind at every tier (Icons.for_kit), every junk
## type and the jackpot flamingo (Icons.for_junk), and every tier's chip too.
func _catalog() -> Variant:
	var gaps: Array[String] = []
	var users: Dictionary = {}
	for item_id: Variant in Catalog.ITEMS:
		var id := _Icons.for_shop_item(StringName(str(item_id)))
		if id == "" or not _Icons.has(id):
			gaps.append("%s ('%s')" % [item_id, id])
		elif not _Icons.is_tinted(id):
			(users.get_or_add(id, []) as Array).append(str(item_id))
	for id: Variant in users:
		var sharing: Array = users[id]
		if sharing.size() > 1 and not SHARED_ICONS.has(str(id)):
			gaps.append("%s is the icon of %s" % [id, sharing])
	for kind: String in Constants.KIT_KINDS:
		var ids: Array[String] = []
		for tier: int in [Catalog.TIER_USED, Catalog.TIER_STOCK, Catalog.TIER_MK2, Catalog.TIER_MK3]:
			var id := _Icons.for_kit(kind, tier)
			_need(gaps, "kit %s tier %d" % [kind, tier], id)
			if ids.has(id):
				gaps.append("kit %s tier %d shares %s" % [kind, tier, id])
			ids.append(id)
			# The shop's card for that tier shows that same picture.
			var item := Catalog.tool_item(kind, tier)
			if item != "" and Catalog.has_item(item) and _Icons.for_shop_item(StringName(item)) != id:
				gaps.append("%s's card is %s, its kit icon %s" % [item, _Icons.for_shop_item(StringName(item)), id])
		if _Icons.for_tier_badge(Catalog.TIER_STOCK) != "":
			gaps.append("stock has a tier chip")
	for tier: int in [Catalog.TIER_USED, Catalog.TIER_MK2, Catalog.TIER_MK3]:
		_need(gaps, "tier chip %d" % tier, _Icons.for_tier_badge(tier))
	for type: Variant in Constants.JUNK_TYPES:
		_need(gaps, "junk " + str(type), _Icons.for_junk(str(type)))
		_need(gaps, "junk item junk_" + str(type), _Icons.for_shop_item(StringName("junk_" + str(type))))
	_need(gaps, "the jackpot flamingo", _Icons.for_shop_item(&"junk_flamingo_vintage"))
	for paint: Variant in Constants.CHEFTY_PAINTS:
		if not Catalog.has_item(str(paint)):
			gaps.append("paint %s isn't sold" % paint)
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
		return gaps
	if shop.has_method("_items") and card_count != (shop.call("_items") as Array).size():
		gaps.append("%d cards for %d items" % [card_count, (shop.call("_items") as Array).size()])
	if card_count == 0:
		gaps.append("no shop cards")
	for id: String in ["brand_homie_depot", "cash"]:
		if not _icons_under(shop).has(id):
			gaps.append("no %s icon in the window" % id)
	var fits := _fits(shop)
	_out["shop_fits"] = fits
	_out["shop_size"] = [shop.size.x, shop.size.y]
	if not fits:
		gaps.append("shop is %s, the window %s" % [shop.size, _design_size()])
	# icons:catalog: every tab of every shop, each card in the catalog look (its
	# item's own icon on a shelf, ui/catalog_look.gd, the job board's look).
	var shown_items := 0
	var tabs_seen := 0
	for shop_id: Variant in Catalog.SHOPS:
		for tab: Variant in (Catalog.SHOPS[shop_id] as Dictionary)["tabs"]:
			shop.call("open_shop", str(shop_id), str(tab))
			await _frames(LAYOUT_FRAMES)
			tabs_seen += 1
			shown_items += _shop_cards(cards, "%s/%s" % [shop_id, tab], gaps)
	_out["shop_tabs"] = tabs_seen
	_out["shop_item_icons"] = shown_items
	# The window fits the screen at every UI scale (WindowFit draws it smaller
	# rather than off the edge), with its cards' icons still there.
	shop.call("open_shop", "homie_depot", "tools")
	var root := get_tree().root
	var scale_was := root.content_scale_factor
	var scales: Dictionary = {}
	for ui_scale: float in UI_SCALES:
		root.content_scale_factor = ui_scale
		await _frames(LAYOUT_FRAMES)
		var inside := _WindowFit.inside(shop, Constants.UI_WINDOW_MARGIN_PX - 1.0)
		scales[str(ui_scale)] = {"inside": inside, "scale": snappedf(shop.scale.x, 0.001), "canvas": get_viewport().get_visible_rect().size}
		if not inside:
			gaps.append("at UI scale %.2f the shop runs off the screen" % ui_scale)
	root.content_scale_factor = scale_was
	await _frames(1)
	_out["shop_scales"] = scales
	if shop.has_method("close_window"):
		shop.call("close_window")
	return gaps


## One tab's cards: each names its item (meta "item_id") and shows that item's own
## icon on its shelf. Counting every icon under the grid would let the price tags'
## cash icons and the task badges stand in for missing item icons.
func _shop_cards(cards: Control, where: String, gaps: Array[String]) -> int:
	var shown := 0
	for card: Node in cards.get_children():
		if card.is_queued_for_deletion():
			continue
		if not card.has_meta("item_id"):
			gaps.append("%s: a card (%s) has no item_id meta" % [where, card.name])
			continue
		var item_id := StringName(card.get_meta("item_id"))
		var want := _Icons.for_shop_item(item_id)
		var shelf := card.get_meta("shelf") as Control if card.has_meta("shelf") else null
		if want == "":
			gaps.append("%s: %s has no shop icon id" % [where, item_id])
		elif shelf == null or not shelf.has_meta("shelf_icon"):
			gaps.append("%s: %s's card has no catalog shelf" % [where, item_id])
		elif not _icons_under(shelf).has(want):
			gaps.append("%s: %s's shelf doesn't show %s" % [where, item_id, want])
		else:
			shown += 1
	return shown


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
	var paid := offers.filter(func(card: Node) -> bool: return _icons_under(card).has("cash")).size()
	if paid < offers.size():
		gaps.append("%d of %d offer cards have a cash icon on the pay line" % [paid, offers.size()])
	if board.has_method("close_window"):
		board.call("close_window")
	else:
		board.visible = false
	return gaps


## The payout receipt (icons chunk D): a made-up settlement on this peer's own
## window (nothing is paid; show_payout only draws) carries the bag, task, mood,
## bill, water, cash, star, bonus, xp and split icons.
func _receipt() -> Variant:
	var gaps: Array[String] = []
	var ui := get_tree().get_first_node_in_group("game_ui")
	var payout := ui.get_node_or_null("PayoutWindow") as Control
	if payout == null or not payout.has_method("show_payout"):
		gaps.append("no PayoutWindow")
		return gaps
	var settlement := {
		"bags_value": 40, "tasks": [["mow_lawn", 100, 25]], "multiplier": 1.2, "mood": "happy",
		"bills": {"hose": 15, "medical": 30}, "water_fee": 4, "paid": 61, "stars": 4.0,
		"bonus": 0.1, "xp": 12,
	}
	var results: Array[Dictionary] = [{"name": "Tester", "credits": 61}]
	payout.call("show_payout", results, settlement)
	await _frames(LAYOUT_FRAMES)
	var shown := _icons_under(payout)
	for id: String in ["item_leaf_bag", "task_mow_lawn", "mood_happy", "tool_hose", "medical", "water", "cash", "star", "bonus", "xp", "split"]:
		if not shown.has(id):
			gaps.append("receipt has no %s icon" % id)
	_out["receipt_icons"] = shown.size()
	if not _fits(payout):
		gaps.append("receipt is %s, the window %s" % [payout.size, _design_size()])
	payout.visible = false
	return gaps


## The day summary card (icons chunk D): a made-up summary with a rank-up, an
## unlock, a season turn and a town morning shows an icon on every line. The card
## is hidden directly, so its closed signal (the morning stinger) never fires.
func _summary() -> Variant:
	var gaps: Array[String] = []
	var ui := get_tree().get_first_node_in_group("game_ui")
	var card := ui.get_node_or_null("DaySummary") as Control
	if card == null or not card.has_method("show_summary"):
		gaps.append("no DaySummary")
		return gaps
	var tier := _Ranks.TIERS_PER_RANK * 2
	var summary := {
		# The day before winter starts, so the arrival line is winter's (net/day/day_clock.gd).
		"day": _Seasons.first_day_of(1) - 1, "jobs": 2, "cash": 120, "stars": 8.0, "xp_banked": 300, "tier": tier,
		"title": _Ranks.title(tier),
		"rank_ups": [{"tier": tier, "title": _Ranks.title(tier), "unlock": "shop:ladder", "extras": []}],
		"season": _Strings.SEASON_ARRIVALS[1],
		"wages": {"wages": 50, "quit": ["Gus"]},
		"town": {"opened": [str(_Hoods.HOODS[1]["name"])], "poached": ["a client"], "missed": 1, "requests": 2},
	}
	card.call("show_summary", summary)
	await _frames(LAYOUT_FRAMES)
	var shown := _icons_under(card)
	var want: Array[String] = ["night", "check", "cash", "star", "xp", "bill", "warning",
		_Icons.for_rank(tier), "bonus", _Icons.for_unlock("shop:ladder"), _Icons.for_season(1),
		_Icons.for_hood(str(_Hoods.HOODS[1]["id"])), "brand_turfmasters", "app_texts"]
	for id: String in want:
		if not shown.has(id):
			gaps.append("summary has no %s icon" % id)
	_out["summary_icons"] = shown.size()
	if not _fits(card):
		gaps.append("summary is %s, the window %s" % [card.size, _design_size()])
	card.visible = false
	var ui_root := get_tree().get_first_node_in_group("game_ui")
	if ui_root != null and ui_root.has_method("recapture_mouse"):
		ui_root.call("recapture_mouse")
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
	# Orders (icons:catalog): every row's picture is its item's own icon. Nothing
	# to check while the crew's rank hasn't opened the app.
	phone.call("show_app", "deliveries")
	await _frames(LAYOUT_FRAMES)
	var rows := _with_meta(phone, "order_row")
	var bare_rows: Array[String] = []
	for row: Node in rows:
		var id := str(row.get_meta("order_row"))
		if not _icons_under(row).has(_Icons.for_shop_item(StringName(id))):
			bare_rows.append(id)
	_out["order_rows"] = rows.size()
	if not bare_rows.is_empty():
		gaps.append("order rows without their item's icon: %s" % [bare_rows])
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
	# The status lines under the rows draw their keys as keycaps (icons:catalog).
	if not (ui.get("_status") is RichTextLabel):
		gaps.append("ui_root's status lines aren't a RichTextLabel, so their keys are '[E]' text")
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
	# The words: a keycap for the key, the hint's own key, a bare key, escaped names.
	var hide := {"text": "Hide"}
	if not _Prompt.rich_for(hide).contains("key_e.png"):
		gaps.append("rich_for(Hide) has no key_e.png: %s" % _Prompt.rich_for(hide))
	if _Prompt.text_for(hide) != "[E]  Hide":
		gaps.append("text_for(Hide) is '%s'" % _Prompt.text_for(hide))
	if not _Prompt.rich_for({"text": "Ride along", "key": "take"}).contains("key_f.png"):
		gaps.append("a hint's own key isn't its keycap")
	var bare := _Prompt.rich_for({"text": "{key:interact}", "plain": true})
	if not bare.contains("key_e.png") or bare.ends_with(" "):
		gaps.append("a bare key reads '%s'" % bare)
	if not _Prompt.rich_for({"text": "Grab [x]Bob"}).contains("[lb]x]Bob"):
		gaps.append("a name's '[' isn't escaped: %s" % _Prompt.rich_for({"text": "Grab [x]Bob"}))
	# The pill, driven by hand with the live prompt held still.
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		gaps.append("no camera to project through")
		return gaps
	var pill := prompt.get_node_or_null("Pill") as Control
	var label := _of_class(prompt, "RichTextLabel")[0] as RichTextLabel
	if pill == null:
		gaps.append("no Pill under InteractionPrompt")
		return gaps
	prompt.process_mode = Node.PROCESS_MODE_DISABLED
	# The yard's own words over heads (the homeowner's name) would move the pill
	# out of their way; the placement checks want it where its point is.
	var avoided := get_tree().get_nodes_in_group(_Prompt.AVOID_GROUP)
	for node: Node in avoided:
		node.remove_from_group(_Prompt.AVOID_GROUP)
	var ahead := camera.global_position - camera.global_basis.z * 4.0
	var here := ahead + camera.global_basis.x * 0.6
	for _frame: int in 3:
		prompt.call("present", {"text": "Hide", "at": here}, camera, 1.0)
	await _frames(1)
	var off := _pill_center(pill).distance_to(camera.unproject_position(here))
	_out["prompt_off_px"] = snappedf(off, 0.01)
	if not pill.visible or pill.modulate.a < 0.99 or off > 1.5:
		gaps.append("the pill is %s at alpha %.2f, %.1f px off its point" % ["up" if pill.visible else "hidden", pill.modulate.a, off])
	if not label.text.contains("key_e.png"):
		gaps.append("the pill's text has no keycap: %s" % label.text)
	# Another thing: it glides over, never jumps.
	var there := ahead - camera.global_basis.x * 0.9
	var from := _pill_center(pill)
	prompt.call("present", {"text": "Hide", "at": there}, camera, 1.0 / 30.0)
	var first_step := _pill_center(pill).distance_to(from)
	var gap_px := from.distance_to(camera.unproject_position(there))
	for _frame: int in 30:
		prompt.call("present", {"text": "Hide", "at": there}, camera, 1.0 / 30.0)
	var settled := _pill_center(pill).distance_to(camera.unproject_position(there))
	_out["prompt_glide"] = {"first_step_px": snappedf(first_step, 0.1), "gap_px": snappedf(gap_px, 0.1), "settled_px": snappedf(settled, 0.1)}
	if first_step > gap_px * 0.6 or settled > 1.5:
		gaps.append("retarget moved %.1f px of %.1f on its first frame, %.1f px off after 1 s" % [first_step, gap_px, settled])
	# Two things a hand apart (two bags, a clump of weeds): the hints say which
	# thing they're over, so it still glides, however close they are.
	var near_a := ahead + camera.global_basis.x * 0.15
	var near_b := ahead - camera.global_basis.x * 0.15
	for _frame: int in 30:
		prompt.call("present", {"text": "Pick up", "at": near_a, "source": "bag:1"}, camera, 1.0 / 30.0)
	var near_from := _pill_center(pill)
	prompt.call("present", {"text": "Pick up", "at": near_b, "source": "bag:2"}, camera, 1.0 / 30.0)
	var near_step := _pill_center(pill).distance_to(near_from)
	var near_gap := near_from.distance_to(camera.unproject_position(near_b))
	for _frame: int in 30:
		prompt.call("present", {"text": "Pick up", "at": near_b, "source": "bag:2"}, camera, 1.0 / 30.0)
	var near_settled := _pill_center(pill).distance_to(camera.unproject_position(near_b))
	_out["prompt_near_glide"] = {"first_step_px": snappedf(near_step, 0.1), "gap_px": snappedf(near_gap, 0.1), "settled_px": snappedf(near_settled, 0.1)}
	if near_gap < 10.0 or near_step > near_gap * 0.6 or near_settled > 1.5:
		gaps.append("two things 0.3 m apart: moved %.1f px of %.1f on the first frame, %.1f px off after 1 s" % [near_step, near_gap, near_settled])
	# One thing moving fast (Chefty at full speed, a hitch frame): followed
	# exactly, every frame, never trailing behind on a glide.
	var worst_follow := 0.0
	for step: int in 6:
		var moving := ahead + camera.global_basis.x * (-1.5 + 0.6 * float(step)) + camera.global_basis.y * 0.3
		prompt.call("present", {"text": "Pick up", "at": moving, "source": "bag:2"}, camera, 1.0 / 30.0)
		worst_follow = maxf(worst_follow, _pill_center(pill).distance_to(camera.unproject_position(moving)))
	_out["prompt_follow_px"] = snappedf(worst_follow, 0.01)
	if worst_follow > 1.5:
		gaps.append("a thing moving 0.6 m a frame is trailed by %.1f px" % worst_follow)
	# Words over someone's head (a keeper's line) right where the pill would
	# be: it steps up out of their way, gliding, and sits clear of them.
	var line := Label3D.new()
	line.text = "New day, new leaves."
	line.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	line.fixed_size = true
	line.pixel_size = 0.0012
	line.font_size = 30
	line.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	get_tree().get_first_node_in_group("world").add_child(line)
	line.global_position = ahead - camera.global_basis.y * 0.05
	for _frame: int in 30:
		prompt.call("present", {"text": "Shop", "at": ahead, "source": "keeper"}, camera, 1.0 / 30.0)
	var clear_before := _pill_rect(pill)
	line.add_to_group(_Prompt.AVOID_GROUP)
	var view_size := get_viewport().get_visible_rect().size
	var line_rect := preload("res://ui/overheads.gd").screen_rect(line, camera, view_size)
	prompt.call("present", {"text": "Shop", "at": ahead, "source": "keeper"}, camera, 1.0 / 30.0)
	var dodge_step := _pill_rect(pill).position.distance_to(clear_before.position)
	for _frame: int in 30:
		prompt.call("present", {"text": "Shop", "at": ahead, "source": "keeper"}, camera, 1.0 / 30.0)
	var dodged := _pill_rect(pill)
	_out["prompt_avoid"] = {"line": [line_rect.position, line_rect.end], "pill_before": [clear_before.position, clear_before.end], "pill_after": [dodged.position, dodged.end], "first_step_px": snappedf(dodge_step, 0.1)}
	if not clear_before.intersects(line_rect):
		gaps.append("the avoid check's line doesn't sit on the pill to begin with")
	elif dodged.intersects(line_rect) or dodged.end.y > line_rect.position.y:
		gaps.append("the pill sits on a keeper's line: pill %s, line %s" % [dodged, line_rect])
	elif dodge_step > (clear_before.end.y - line_rect.position.y) * 0.6 + Constants.ICONS_PROMPT_AVOID_GAP_PX:
		gaps.append("the pill jumped %.1f px out of a line's way in one frame" % dodge_step)
	line.queue_free()
	await _frames(1)
	# Behind the camera: gone.
	prompt.call("present", {"text": "Hide", "at": camera.global_position + camera.global_basis.z * 3.0}, camera, 1.0)
	if pill.visible:
		gaps.append("the pill shows a point behind the camera")
	# Far off the side of the screen: it fades, it doesn't pin itself to the edge.
	for _frame: int in 3:
		prompt.call("present", {"text": "Hide", "at": here}, camera, 1.0)
	for _frame: int in 2:
		prompt.call("present", {"text": "Hide", "at": ahead + camera.global_basis.x * 40.0}, camera, 1.0)
	if pill.visible:
		gaps.append("the pill pins itself to the edge for a point far off screen")
	# UI scale: a point dead ahead lands mid-screen at every scale.
	var root := get_tree().root
	var scale_was := root.content_scale_factor
	var scales: Dictionary = {}
	for ui_scale: float in [0.8, 1.25]:
		root.content_scale_factor = ui_scale
		await _frames(2)
		for _frame: int in 3:
			prompt.call("present", {"text": "Hide", "at": ahead}, camera, 1.0)
		var mid := get_viewport().get_visible_rect().size * 0.5
		var miss := _pill_center(pill).distance_to(mid)
		scales[str(ui_scale)] = {"off_px": snappedf(miss, 0.01), "canvas": [mid.x * 2.0, mid.y * 2.0]}
		if miss > 1.5:
			gaps.append("at UI scale %.2f the pill is %.1f px off the screen's middle" % [ui_scale, miss])
	_out["prompt_scales"] = scales
	root.content_scale_factor = scale_was
	await _frames(1)
	prompt.call("present", {}, camera, 1.0)
	for node: Node in avoided:
		if is_instance_valid(node):
			node.add_to_group(_Prompt.AVOID_GROUP)
	prompt.process_mode = Node.PROCESS_MODE_INHERIT
	# A window takes the prompt away, live: first a live prompt up in front of
	# the camera, then the shop opens over it.
	if ui.has_method("open_store"):
		var source := AheadSource.new()
		source.name = "IconsTestPromptSource"
		source.camera = camera
		add_child(source)
		source.add_to_group("prompt_sources")
		var up_frames := 0
		while up_frames < 60 and not (str(prompt.get("current_text")) != "" and pill.visible and pill.modulate.a > 0.99):
			await _frames(1)
			up_frames += 1
		_out["prompt_live_before_shop"] = {"text": str(prompt.get("current_text")), "visible": pill.visible, "alpha": snappedf(pill.modulate.a, 0.01), "frames": up_frames}
		if str(prompt.get("current_text")) == "" or not pill.visible:
			gaps.append("no live prompt came up before the shop opened ('%s', %s)" % [prompt.get("current_text"), "up" if pill.visible else "hidden"])
		ui.call("open_store")
		await _frames(LAYOUT_FRAMES)
		if str(prompt.get("current_text")) != "" or pill.visible:
			gaps.append("the prompt stays up over the shop ('%s')" % prompt.get("current_text"))
		var shop := ui.get_node_or_null("ShopWindow")
		if shop != null and shop.has_method("close_window"):
			shop.call("close_window")
		source.queue_free()
	return gaps


## A prompt source that always offers one, just in front of the camera.
class AheadSource extends Node:
	var camera: Camera3D

	func prompt() -> Dictionary:
		if camera == null or not is_instance_valid(camera):
			return {}
		return {"text": "Test", "at": camera.global_position - camera.global_basis.z * 3.0}


## The pill's rect as laid out (before its grow and bump scale).
func _pill_rect(pill: Control) -> Rect2:
	return Rect2(pill.position, pill.size)


## The middle of the pill as drawn (scale is about its pivot, the middle).
func _pill_center(pill: Control) -> Vector2:
	return pill.position + pill.size * 0.5


## A money popup's coin: the cash icon, left of the text, spinning in place.
func _coin() -> Variant:
	var gaps: Array[String] = []
	var world := get_tree().get_first_node_in_group("world") as Node3D
	if world == null:
		gaps.append("no world to pop money in")
		return gaps
	var popup := load("res://ui/money_popup.gd").new() as Label3D
	popup.text = str(_Strings.UI["popup_cash"]) % 9
	world.add_child(popup)
	var coin := popup.get_node_or_null("Coin") as GeometryInstance3D
	var material := coin.material_override as ShaderMaterial if coin != null else null
	if material == null or material.get_shader_parameter("coin") != _Icons.texture("cash"):
		gaps.append("the popup has no cash coin")
		popup.queue_free()
		return gaps
	# Its place beside the text is one per-instance value the spin never touches
	# (money_popup.gd COIN_SHADER), so it turns in place; its width is the spin.
	var shifts: Array[float] = []
	var widths: Array[float] = []
	for _frame: int in 6:
		await get_tree().create_timer(COIN_SAMPLE_SECONDS).timeout
		if not is_instance_valid(coin):
			break
		shifts.append(float(coin.get_instance_shader_parameter("shift")))
		widths.append(float(coin.get_instance_shader_parameter("spin")))
	_out["coin"] = {"shifts": shifts, "widths": widths}
	if shifts.is_empty() or shifts.max() >= 0.0:
		gaps.append("the coin isn't left of the text: %s" % [shifts])
	elif shifts.max() - shifts.min() > 1e-6:
		gaps.append("the coin slides as it spins: %s" % [shifts])
	if not widths.is_empty() and widths.max() - widths.min() < 0.05:
		gaps.append("the coin doesn't spin: widths %s" % [widths])
	if is_instance_valid(popup):
		popup.queue_free()
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
