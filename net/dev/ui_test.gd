extends Node

## Authority: local (host). --ui-test (p1-ui, docs/GAME.md "Windows sit in the
## middle of the screen" and "Words hung in the world"; port 7833): the windows
## and the words from crew playtest 1, on the host at the store:
##   board     the job board opens inside the screen, centered, and stays the same
##             size through refreshes (crew-07)
##   clamp     a window bigger than the screen is drawn smaller, inside it
##   payout    a long receipt then a short one: the second is shorter, centered,
##             inside the screen (NB-06); a watcher gets no split line and no card
##   words     prompts are a keycap and a verb ("Grab", "Put down", "Look"); the
##             crew rating says "(1 job)"; the leaf bag's card is one line (NB-10)
##   phone     Marty's day-1 text is the first one up; Take it is orange (NB-11)
##   shop      a sale shows no toast; the keeper's line isn't over his head while
##             his window shows it (NB-10)
##   counter   opening his window eases your view round onto Marty (NB-M1); a sign
##             behind him isn't printed on his face, one beside him shows
##   signs     a world sign faces you, shows in open sky, fades over the HUD, at the
##             screen's edge, behind a nearer one and under a stage camera (nb9,
##             NB-09, lagduo-10); over the clock and the heat bar it fades for the
##             panel alone (well inside the edges), and the heat bar and the dash,
##             whose own size is zero, count as panels
## Each step prints a [UiTest] line.

const _WindowFit = preload("res://ui/window_fit.gd")
const _Overheads = preload("res://ui/overheads.gd")
const _Strings = preload("res://ui/strings.gd")
const _HotbarHud = preload("res://ui/hotbar_hud.gd")
const _BoardWindow = preload("res://ui/job_board_window.gd")
const _ShopWindow = preload("res://ui/shop_window.gd")
## A sign counts as shown under this transparency and gone over the other.
const SHOWN_UNDER: float = 0.25
const GONE_OVER: float = 0.9
## How long a sign's fade gets to settle (s).
const SETTLE: float = 0.7

static var result: Dictionary = {}

var _started: bool = false
var _ok: bool = true
var _steps: Dictionary = {}


func _process(_delta: float) -> void:
	if _started or not Net.is_host() or _me() == null or _ui() == null or get_tree().get_first_node_in_group("job_board") == null:
		return
	_started = true
	_run()


func _run() -> void:
	# The store dressed and the board's offers up.
	await get_tree().create_timer(3.0).timeout
	await _check_board()
	await _check_clamp()
	await _check_payout()
	_check_words()
	await _check_phone()
	await _check_shop()
	await _check_counter()
	await _check_signs()
	result = {"ok": _ok, "done": true, "steps": _steps}
	print("[UiTest] all ok: %s" % _ok)


func _step(name: String, ok: bool, detail: String) -> void:
	_steps[name] = ok
	_ok = _ok and ok
	print("[UiTest] %s %s: %s" % [name, "ok" if ok else "FAIL", detail])


func _frames(count: int) -> void:
	for _index: int in count:
		await get_tree().process_frame


func _view() -> Vector2:
	return get_viewport().get_visible_rect().size


func _centered(window: Control) -> bool:
	var drawn_center := window.position + window.size * 0.5
	return drawn_center.distance_to(_view() * 0.5) <= 2.0


# ---------------------------------------------------------------- windows

func _check_board() -> void:
	var ui := _ui()
	ui.call("open_job_board")
	await _frames(3)
	var window := ui.get_node("JobBoardWindow") as Control
	var first := window.size
	var inside := _WindowFit.inside(window, Constants.UI_WINDOW_MARGIN_PX - 1.0)
	var centered := _centered(window)
	# The board refreshing while it's up (a teammate picks a job) leaves it be.
	for _round: int in 3:
		window.call("_refresh")
		await _frames(2)
	var same := window.size.is_equal_approx(first) and _WindowFit.inside(window, Constants.UI_WINDOW_MARGIN_PX - 1.0) and _centered(window)
	_step("board", window.visible and inside and centered and same, "%s at %s in %s: inside %s, centered %s, same after refreshes %s (%s)" % [first, window.position, _view(), inside, centered, same, window.size])
	window.call("close_window")


func _check_clamp() -> void:
	var big := PanelContainer.new()
	big.custom_minimum_size = _view() + Vector2(400.0, 300.0)
	_ui().add_child(big)
	_WindowFit.fit(big, true)
	await _frames(1)
	var ok := big.scale.x < 1.0 and _WindowFit.inside(big, Constants.UI_WINDOW_MARGIN_PX - 1.0)
	_step("clamp", ok, "a %s window on a %s screen drawn at %.2f, inside %s" % [big.size, _view(), big.scale.x, _WindowFit.inside(big)])
	big.queue_free()


func _check_payout() -> void:
	var ui := _ui()
	var payout := ui.get_node("PayoutWindow") as Control
	Net.set_watcher(999, true)
	var crew: Array[Dictionary] = [
		{"peer_id": Net.local_peer_id(), "name": "Tester", "credits": 40},
		{"peer_id": 999, "name": "Watcher", "credits": 0},
	]
	var tasks: Array = []
	for task: String in ["pick_litter", "pull_weeds", "mow_lawn", "clean_gutters", "wash_windows", "power_wash", "trim_hedges"]:
		tasks.append([task, 100, 20])
	var long := {"bags_value": 90, "tasks": tasks, "multiplier": 1.25, "mood": "happy", "bills": {"hose": 12, "gnome": 8}, "water_fee": 3, "paid": 200, "stars": 4, "bonus": 0.1, "xp": 40}
	payout.call("show_payout", crew, long)
	await get_tree().create_timer(Constants.RECEIPT_PRINT_DELAY + Constants.RECEIPT_FEED_SECONDS + 0.3).timeout
	var tall := payout.size.y * payout.scale.y
	var watcher_row := _has_text(payout, "Watcher")
	payout.call("show_payout", crew.slice(0, 1), {"bags_value": 9, "paid": 9, "mood": "fine"})
	await get_tree().create_timer(Constants.RECEIPT_PRINT_DELAY + Constants.RECEIPT_FEED_SECONDS + 0.3).timeout
	var short := payout.size.y * payout.scale.y
	var ok := short < tall * 0.75 and _WindowFit.inside(payout, Constants.UI_WINDOW_MARGIN_PX - 1.0) and _centered(payout) and not watcher_row
	_step("payout", ok, "a long receipt %.0f px tall, then a short one %.0f px at %s (inside %s, centered %s); a watcher's split line %s" % [tall, short, payout.position, _WindowFit.inside(payout), _centered(payout), watcher_row])
	payout.call("close_window")
	# A watcher's own screen gets no payday card.
	Net.set_watcher(Net.local_peer_id(), true)
	ui.call("_on_payout", crew.slice(0, 1))
	await _frames(1)
	var shown := payout.visible
	Net.set_watcher(Net.local_peer_id(), false)
	Net.set_watcher(999, false)
	_step("payout_watcher", not shown, "a watcher's screen shows the card: %s" % shown)
	payout.call("close_window")


func _has_text(root: Node, text: String) -> bool:
	for child: Node in root.get_children():
		if child is Label and (child as Label).text == text:
			return true
		if _has_text(child, text):
			return true
	return false


# ---------------------------------------------------------------- words

func _check_words() -> void:
	var prompts := [str(_Strings.UI["prompt_grab_player"]), str(_Strings.UI["prompt_put_down_player"]), str(_Strings.SHOP_UI["prompt_look_at"])]
	var plain := prompts.all(func(text: Variant) -> bool: return not str(text).contains("%") and str(text).split(" ").size() <= 2)
	var counts := [_BoardWindow.rating_count_text(1), _BoardWindow.rating_count_text(3)]
	var plural: bool = counts[0] == "(1 job)" and counts[1] == "(3 jobs)"
	# The bag's hands card: one line with its weight and worth.
	var bag_script := GDScript.new()
	bag_script.source_code = "extends Node\nvar kind := \"leaf_bag\"\nvar value := 9\nvar label := \"\"\nfunc weight_kg() -> float:\n\treturn 7.0\n"
	bag_script.reload()
	var bag := Node.new()
	bag.set_script(bag_script)
	var card: Dictionary = _HotbarHud.hands_view(bag)
	bag.free()
	var one_line := str(card.get("line", "x")) == "" and str(card.get("title", "")).contains("7 kg") and str(card.get("title", "")).contains("$9")
	_step("words", plain and plural and one_line, "prompts %s; ratings %s; the bag's card \"%s\" / \"%s\"" % [prompts, counts, card.get("title"), card.get("line")])


func _check_phone() -> void:
	var phone := get_tree().get_first_node_in_group("phone")
	var town := get_tree().get_first_node_in_group("town")
	if phone == null or town == null:
		_step("phone", false, "no phone (%s) or town (%s)" % [phone, town])
		return
	phone.call("open_phone", "texts")
	await _frames(3)
	var list := phone.get("_list") as Node
	var intro := ""
	for entry: Variant in town.get("texts"):
		if str((entry as Dictionary).get("kind", "")) == "intro":
			intro = str((entry as Dictionary).get("text", ""))
	var first := list.get_child(0) if list.get_child_count() > 0 else null
	var on_top := first != null and intro != "" and _has_text(first, _Strings.keyed(intro))
	var orange := false
	var takes := 0
	for button: Node in _buttons(list):
		if (button as Button).text != str(_Strings.UI["phone_take_job"]):
			continue
		takes += 1
		var box := (button as Button).get_theme_stylebox("normal") as StyleBoxFlat
		orange = box != null and box.bg_color.is_equal_approx(_ShopWindow.ORANGE)
	_step("phone", on_top and (orange or takes == 0), "Marty's welcome first: %s; %d Take it buttons, orange %s" % [on_top, takes, orange])
	phone.call("close_phone")
	await get_tree().create_timer(0.6).timeout


func _buttons(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child: Node in root.get_children():
		if child is Button:
			out.append(child)
		out.append_array(_buttons(child))
	return out


# ---------------------------------------------------------------- the counter

func _check_shop() -> void:
	var ui := _ui()
	var marty := _keeper("homie_depot")
	ui.call("open_shop", "homie_depot")
	await _frames(2)
	var window := ui.get_node("ShopWindow") as Control
	window.call("_on_shop_result", "ok", "lawn_bags", 0)
	await _frames(3)
	var toast := str(window.call("toast_text"))
	var said := marty != null and str(marty.call("current_line")) != ""
	var caption := marty.get("_caption") as Label3D if marty != null else null
	var hidden_up := caption != null and not caption.visible
	window.call("close_window")
	await _frames(2)
	# The line the window showed isn't put back over his head; his next one is.
	var not_again := caption != null and not caption.visible
	marty.call("say", "Next line, please.")
	await _frames(2)
	var captions_on := bool(Settings.get_value("interface", "captions"))
	var back := not_again and caption != null and (caption.visible or not captions_on or not bool(marty.call("is_present")))
	var inside := _WindowFit.inside(window, Constants.UI_WINDOW_MARGIN_PX - 1.0)
	_step("shop", toast == "" and said and hidden_up and back and inside, "toast \"%s\"; Marty said a line %s; over his head while the window's up %s, his next line after it closes (not that one again) %s; window inside %s" % [toast, said, not hidden_up, back, inside])


func _check_counter() -> void:
	var marty := _keeper("homie_depot") as Node3D
	var me := _me()
	if marty == null:
		_step("counter", false, "no Marty")
		return
	var zone := marty.get_parent() as Node3D
	var counter: Vector3 = (Constants.SHOP_SITES["homie_depot"] as Dictionary)["counter"]
	me.global_position = zone.to_global(counter + Vector3(0.8, 0.0, 1.0))
	me.set("body_yaw", float(me.get("body_yaw")) + 1.4)
	me.set("head_pitch", -0.6)
	await get_tree().create_timer(0.3).timeout
	marty.call("frame_for", me)
	await get_tree().create_timer(Constants.P1_COUNTER_FRAME_SECONDS + 0.3).timeout
	var camera := get_viewport().get_camera_3d()
	var face := marty.global_position + Vector3.UP * float((marty.get_script() as Script).get_script_constant_map().get("KEEPER_FACE_M", 1.5))
	var at := camera.unproject_position(face) if not camera.is_position_behind(face) else Vector2(-1.0, -1.0)
	var view := _view()
	var framed := absf(at.x - view.x * 0.5) < view.x * 0.08 and absf(at.y - view.y * 0.5) < view.y * 0.2
	var pitch := float(me.get("head_pitch"))
	_step("counter", framed and absf(pitch) <= Constants.P1_COUNTER_PITCH_MAX + 0.01, "Marty's face at %s on a %s screen, pitch %.2f" % [at, view, pitch])
	# A sign behind him isn't printed on his face ("To the lot" was); beside him it shows.
	var sign := _sign("To the lot")
	var away := (face - camera.global_position).normalized()
	sign.global_position = face + away * 3.0
	await get_tree().create_timer(SETTLE).timeout
	var behind_gone := sign.transparency > GONE_OVER
	sign.global_position = face + away * 3.0 + camera.global_transform.basis.x * 1.6 + Vector3.UP * 0.8
	await get_tree().create_timer(SETTLE + 0.4).timeout
	var beside_shown := sign.transparency < SHOWN_UNDER
	_step("sign_behind", behind_gone and beside_shown, "behind Marty gone %s; beside him shown %s (%.2f)" % [behind_gone, beside_shown, sign.transparency])
	sign.queue_free()
	me.set("head_pitch", 0.0)


func _keeper(shop: String) -> Node:
	for keeper: Node in get_tree().get_nodes_in_group("shopkeepers"):
		if str(keeper.get("shop_id")) == shop:
			return keeper
	return null


# ---------------------------------------------------------------- signs

func _check_signs() -> void:
	var me := _me()
	# Up at the open sky, so nothing solid stands between the camera and the signs.
	me.set("head_pitch", 0.7)
	await get_tree().create_timer(0.4).timeout
	var camera := get_viewport().get_camera_3d()
	var view := _view()
	var far := _sign("Back to Homie Depot")
	var near := _sign("Chefty 0/50 bags")
	far.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	near.visible = false
	far.global_position = camera.project_position(view * 0.5, 7.0)
	await get_tree().create_timer(SETTLE).timeout
	var open_sky := far.transparency < SHOWN_UNDER and far.billboard == BaseMaterial3D.BILLBOARD_ENABLED
	_step("sign_shows", open_sky, "in open sky: transparency %.2f, billboard %d" % [far.transparency, far.billboard])
	far.visible = false
	await _check_sign_hud(camera, view)
	far.visible = true
	# Half off the right edge.
	far.global_position = camera.project_position(Vector2(view.x - 6.0, view.y * 0.5), 7.0)
	await get_tree().create_timer(SETTLE).timeout
	_step("sign_edge", far.transparency > GONE_OVER, "at the right edge: transparency %.2f" % far.transparency)
	# A nearer one in front of it: the nearer shows, the farther steps aside.
	far.global_position = camera.project_position(view * 0.5, 9.0)
	near.global_position = camera.project_position(view * 0.5 + Vector2(10.0, 4.0), 4.0)
	near.visible = true
	await get_tree().create_timer(SETTLE).timeout
	_step("sign_overlap", near.transparency < SHOWN_UNDER and far.transparency > GONE_OVER, "nearer %.2f, farther %.2f" % [near.transparency, far.transparency])
	# A stage camera takes the view: no words hung in the world.
	near.visible = false
	far.global_position = camera.project_position(view * 0.5, 7.0)
	await get_tree().create_timer(SETTLE).timeout
	var stage := Camera3D.new()
	stage.name = "StageCam"
	stage.fov = camera.fov
	add_child(stage)
	stage.global_transform = camera.global_transform
	stage.make_current()
	await get_tree().create_timer(SETTLE).timeout
	var staged_gone := far.transparency > GONE_OVER
	camera.make_current()
	stage.queue_free()
	await get_tree().create_timer(SETTLE + 0.4).timeout
	_step("sign_stage", staged_gone and far.transparency < SHOWN_UNDER, "under a StageCam gone %s, back after %.2f" % [staged_gone, far.transparency])
	far.queue_free()
	near.queue_free()
	me.set("head_pitch", 0.0)


## Over each HUD panel, well inside the screen's edges, a short sign fades for the
## panel's sake alone. The heat meter places its children by hand (its own size
## is zero), so it's checked to count at all. (Chefty's drive panel is gone since
## p1-dash put the dash in the cab, so it is no longer a piece to check.)
func _check_sign_hud(camera: Camera3D, view: Vector2) -> void:
	var ui := _ui()
	var counted: Array[String] = []
	for piece: String in ["HeatMeter"]:
		var node := ui.get_node_or_null(piece) as Control
		if node != null and _Overheads.drawn_rect(node).size.x > 1.0 and _Overheads.drawn_rect(node).size.y > 1.0:
			counted.append(piece)
	_step("hud_pieces", counted.size() == 1 and ui.get_node_or_null("DriveHud") == null, "drawn rects found for %s (heat %s; no drive panel %s)" % [counted, _Overheads.drawn_rect(ui.get_node("HeatMeter")), ui.get_node_or_null("DriveHud") == null])
	var panels: Dictionary = {}
	for piece: String in ["DayHud", "HeatMeter"]:
		var node := ui.get_node_or_null(piece) as Control
		if node != null and node.is_visible_in_tree():
			panels[piece] = _Overheads.drawn_rect(node)
	var hotbar := ui.get_node_or_null("HotbarHud")
	if hotbar != null:
		var bars: Array[Rect2] = hotbar.call("screen_rects")
		if not bars.is_empty():
			panels["HotbarHud"] = bars[0]
	var small := _sign("Lot B")
	var details: Array[String] = []
	var ok := panels.has("HeatMeter") and panels.has("DayHud")
	for piece: String in panels:
		var panel := panels[piece] as Rect2
		# Away from the panel first, so its fade starts from shown.
		small.global_position = camera.project_position(view * 0.5, 7.0)
		await get_tree().create_timer(SETTLE).timeout
		var shown_before := small.transparency < SHOWN_UNDER
		small.global_position = camera.project_position(panel.get_center(), 7.0)
		await _frames(2)
		var rect := _Overheads.screen_rect(small, camera, view)
		# Inside the edges: only the panel can be what hides it.
		var inside := _Overheads.clear_of_hud(rect, view, [], 1.0)
		await get_tree().create_timer(SETTLE).timeout
		var gone := small.transparency > GONE_OVER
		ok = ok and shown_before and inside and gone
		details.append("%s %s: sign %s inside the edges %s, shown before %s, transparency %.2f" % [piece, panel, rect, inside, shown_before, small.transparency])
	small.queue_free()
	_step("sign_hud", ok, "; ".join(details))


func _sign(text: String) -> Label3D:
	var sign := Label3D.new()
	sign.text = text
	sign.font_size = 56
	sign.outline_size = 10
	sign.add_to_group(_Overheads.SIGNS)
	get_tree().get_first_node_in_group("world").add_child(sign)
	return sign


# ---------------------------------------------------------------- lookups

func _ui() -> Node:
	return get_tree().get_first_node_in_group("game_ui")


func _me() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as Node3D
	return null
