extends Node3D

## Authority: local, cosmetic. The Snak-o-Matic (docs/GAME.md "Shops"; gap
## shops chunk 6): Homie Depot's vending machine on the store's front wall, the
## shop with no keeper. Always open, 1.5x prices, and now and then it keeps
## your money. Every peer builds its own from Constants.SHOP_SITES (levels/
## dressing/shop_sites.gd); buying goes through World/Shops like any shop.
##
## The machine shows what happened from the replicated shop state, so everyone
## at the store sees the same thing and nothing here is networked:
## - a snack sold (its stock in Shops.stock went down): the front snack of a
##   slot of its kind drops off its coil, falls to the bottom and the machine
##   clunks as it lands; the slot fills back up at the next restock;
## - money eaten (Shops.vending_eaten went up): the coil turns, the snack tips
##   forward and sticks there, hanging, the clunk, then the sad trombone, and
##   the screen thanks you for your donation. It hangs there till the morning.
## Its screen is a little green marquee scrolling KEEPER_LINES.snak_o_matic:
## a hello when you walk up, a line when you open it and when it sells you
## something. E at the machine opens its window (ui/ui_root.gd open_shop).

const _ShopModels = preload("res://props/shop_models.gd")
const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const _LowPoly = preload("res://props/low_poly.gd")
const _Strings = preload("res://ui/strings.gd")
const SHOP_ID: String = "snak_o_matic"
## The marquee: how many letters show at once, and how fast it scrolls (letters/s).
const SCREEN_CHARS: int = 8
const SCROLL_RATE: float = 7.0
const SCREEN_GREEN := Color(0.45, 1.0, 0.55)
## How far a stuck snack tips forward on its coil (rad).
const STUCK_TIP: float = 0.55

## The last line on the screen and why (tests and the probe read them).
var last_line: String = ""
var last_trigger: String = ""

var _fronts: Array[Node3D] = []
var _screen: Label3D
var _line_left: float = 0.0
var _scroll: float = 0.0
var _stock_seen: int = -1
var _eaten_seen: int = -1
var _stuck: Node3D
var _drops: Array[Dictionary] = []
var _local_was_near: bool = false
var _greeted_day: int = -1
var _greeted_at: float = -1000.0
var _shops: Node


func _ready() -> void:
	add_to_group("prompt_sources")
	add_to_group("vending_machines")
	add_child(_ShopModels.node("vending_machine"))
	var size := _ShopModels.VENDING_SIZE
	var front := -size.z * 0.5
	# The front snack of every slot, its own node so it can fall.
	for row: int in _ShopModels.VENDING_ROWS:
		for slot: int in _ShopModels.VENDING_SLOTS:
			var kit := _MeshKit.new()
			_ShopModels.vending_snack(kit, row, slot, Vector3.ZERO)
			var snack := _Stylized.instance(kit.commit(), {"roughness": 0.6, "specular": 0.3})
			snack.name = "Snack_%d_%d" % [row, slot]
			snack.position = _ShopModels.vending_slot(row, slot, 0)
			snack.set_meta("home", snack.position)
			snack.set_meta("can", _ShopModels.vending_slot_is_can(row, slot))
			add_child(snack)
			_fronts.append(snack)
	_glass(front)
	var title := _LowPoly.text_sign(self, str(_Strings.SHOP_UI["sign_snak_o_matic"]), Vector3(0.0, _ShopModels.VENDING_HEADER_Y, front - 0.04), 34, Color(0.75, 0.2, 0.12), PI)
	title.outline_size = 0
	title.pixel_size = 0.0034
	_screen = Label3D.new()
	_screen.name = "Screen"
	_screen.font_size = 30
	_screen.pixel_size = 0.0016
	_screen.outline_size = 0
	_screen.modulate = SCREEN_GREEN
	_screen.double_sided = false
	_screen.rotation.y = PI
	var win := _ShopModels.VENDING_WINDOW
	_screen.position = Vector3((win.end.x + size.x * 0.5) * 0.5, win.end.y - 0.14, front - 0.032)
	add_child(_screen)
	# A soft glow from inside, so it reads at night like a vending machine does.
	var light := OmniLight3D.new()
	light.light_color = Color(0.85, 0.95, 1.0)
	light.light_energy = 0.6
	light.omni_range = 2.2
	light.position = Vector3(-0.1, 1.3, front - 0.4)
	light.shadow_enabled = false
	add_child(light)
	var body := StaticBody3D.new()
	body.name = "Solid"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = Vector3(0.0, size.y * 0.5, 0.0)
	body.add_child(shape)
	add_child(body)
	_show_idle()


## The glass over the window, a little blue and shiny.
func _glass(front: float) -> void:
	var win := _ShopModels.VENDING_WINDOW
	var glass := MeshInstance3D.new()
	glass.name = "Glass"
	var quad := QuadMesh.new()
	quad.size = win.size
	glass.mesh = quad
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.75, 0.9, 1.0, 0.07)
	material.roughness = 0.05
	material.metallic_specular = 0.9
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.material_override = material
	glass.set_meta("keep_material", true)
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glass.position = Vector3(win.position.x + win.size.x * 0.5, win.position.y + win.size.y * 0.5, front - 0.002)
	add_child(glass)


## How many front snacks still sit on their coils (not sold, not stuck).
func front_count() -> int:
	return _fronts.filter(func(snack: Node3D) -> bool: return not bool(snack.get_meta("gone", false))).size()


## "Use the Snak-o-Matic" while the local player stands at it.
func prompt() -> Dictionary:
	if not _local_in_reach():
		return {}
	return {"text": _Strings.SHOP_UI["prompt_vending"], "at": global_position + Vector3(0.0, 2.25, 0.0)}


## Show a line from KEEPER_LINES.snak_o_matic on the screen (trigger as a keeper's).
func say_line(trigger: String) -> void:
	var by_trigger: Dictionary = _Strings.KEEPER_LINES.get("snak_o_matic", {})
	var lines: Array = by_trigger.get(trigger, by_trigger.get("greet", []))
	if lines.is_empty():
		return
	_show(str(lines[randi() % lines.size()]), trigger)


func _show(line: String, trigger: String) -> void:
	last_line = line
	last_trigger = trigger
	_line_left = Constants.VEND_SCREEN_LINE_SECONDS + float(line.length()) / SCROLL_RATE
	_scroll = 0.0


func _show_idle() -> void:
	_screen.text = ""


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or not _local_in_reach():
		return
	var ui := get_tree().get_first_node_in_group("game_ui")
	if ui == null or bool(ui.call("any_window_open")):
		return
	say_line("open")
	ui.call("open_shop", SHOP_ID)
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_hook()
	_watch()
	_step_drops(delta)
	_marquee(delta)
	var near := _local_in_reach()
	if near and not _local_was_near and Time.get_ticks_msec() / 1000.0 - _greeted_at > Constants.KEEPER_GREET_COOLDOWN_SECONDS:
		_greeted_at = Time.get_ticks_msec() / 1000.0
		_greet()
	_local_was_near = near


func _greet() -> void:
	var clock := get_tree().get_first_node_in_group("day_clock")
	var day := int(clock.get("day")) if clock != null else 1
	var hour := float(clock.call("hour")) if clock != null else Constants.DAY_START_HOUR
	var trigger := "greet"
	if day != _greeted_day and hour < Constants.CLERK_MORNING_UNTIL_HOUR:
		trigger = "morning"
	elif clock != null and bool(clock.call("is_quiet_hours")):
		trigger = "night"
	_greeted_day = day
	say_line(trigger)


## The green marquee: the line scrolls past SCREEN_CHARS at a time, then the
## screen goes back to its blinking cursor.
func _marquee(delta: float) -> void:
	if _line_left <= 0.0:
		var blink := int(Time.get_ticks_msec() / 600) % 2 == 0
		_screen.text = "$_" if blink else "$"
		return
	_line_left -= delta
	_scroll += delta * SCROLL_RATE
	# In from the right, across, and out the left.
	var padded := " ".repeat(SCREEN_CHARS) + last_line + " ".repeat(SCREEN_CHARS)
	var start := mini(int(_scroll), maxi(padded.length() - SCREEN_CHARS, 0))
	if start >= padded.length() - SCREEN_CHARS:
		_line_left = 0.0
	_screen.text = padded.substr(start, SCREEN_CHARS)


func _hook() -> void:
	if _shops != null and is_instance_valid(_shops):
		return
	_shops = get_tree().get_first_node_in_group("shops")
	if _shops == null:
		return
	_stock_seen = _stock_count()
	_eaten_seen = int(_shops.get("vending_eaten"))
	# A peer that joins mid-day sees the empty slots already empty.
	_refill(_stock_count())


## What the replicated state says happened since the last look.
func _watch() -> void:
	if _shops == null or not is_instance_valid(_shops):
		return
	var count := _stock_count()
	var eaten := int(_shops.get("vending_eaten"))
	if count > _stock_seen:
		# A new morning: the machine's restocked, and whatever was stuck came loose.
		_refill(count)
	elif count < _stock_seen:
		for _sold: int in _stock_seen - count:
			_drop(false)
		say_line("buy")
	if eaten > _eaten_seen and _eaten_seen >= 0:
		_drop(true)
		_show(str(_Strings.SHOP_UI["shop_result_eaten"]).to_upper(), "eaten")
	_stock_seen = count
	_eaten_seen = eaten


func _stock_count() -> int:
	var shelf: Dictionary = (_shops.get("stock") as Dictionary).get(SHOP_ID, {}) if _shops != null else {}
	var total := 0
	for item: Variant in shelf:
		total += int(shelf[item])
	return total


## Every slot full again, or as full as today's stock (one front snack shown
## per unit left, the rest already sold).
func _refill(count: int) -> void:
	_drops.clear()
	_stuck = null
	var daily := 0
	for item: Variant in (Constants.SHOP_DAILY_STOCK.get(SHOP_ID, {}) as Dictionary):
		daily += int(Constants.SHOP_DAILY_STOCK[SHOP_ID][item])
	var gone := maxi(daily - count, 0)
	for index: int in _fronts.size():
		var snack := _fronts[index]
		snack.position = snack.get_meta("home")
		snack.rotation = Vector3.ZERO
		# What's been sold today is gone from the top down (_pick's order), the
		# same slots on every peer.
		snack.visible = index < _fronts.size() - gone
		snack.set_meta("gone", not snack.visible)


## A snack falls (stuck: tips and hangs instead). The clunk lands with it.
func _drop(stuck: bool) -> void:
	var snack := _pick()
	if snack == null:
		_clunk(stuck)
		return
	snack.set_meta("gone", true)
	if stuck:
		_stuck = snack
	_drops.append({"node": snack, "t": 0.0, "stuck": stuck, "from": snack.position, "landed": false})


## The next front snack still there: from the top down, so you can see the gap.
func _pick() -> Node3D:
	for index: int in range(_fronts.size() - 1, -1, -1):
		var snack := _fronts[index]
		if snack.visible and not bool(snack.get_meta("gone", false)):
			return snack
	return null


func _step_drops(delta: float) -> void:
	for drop: Dictionary in _drops:
		var snack: Node3D = drop["node"]
		drop["t"] = float(drop["t"]) + delta
		var t := float(drop["t"])
		var from: Vector3 = drop["from"]
		if bool(drop["stuck"]):
			# The coil turns, the snack creeps forward and tips over the edge... and stops.
			var turn := clampf(t / 0.6, 0.0, 1.0)
			var wobble := sin(clampf((t - 0.6) / 0.5, 0.0, 1.0) * PI * 3.0) * 0.12 * (1.0 - clampf((t - 0.6) / 0.5, 0.0, 1.0))
			snack.position = from + Vector3(0.0, -0.01 * turn, -0.035 * turn)
			snack.rotation.x = -(STUCK_TIP * turn * turn + wobble)
			if t >= 0.6 and not bool(drop["landed"]):
				drop["landed"] = true
				_clunk(true)
			continue
		# Off the coil: a nudge forward, then it falls to the bottom of the window.
		var floor_y := _ShopModels.VENDING_WINDOW.position.y + 0.02
		var nudge := clampf(t / 0.18, 0.0, 1.0)
		var fall := clampf((t - 0.18) / Constants.VEND_DROP_SECONDS, 0.0, 1.0)
		snack.position = from + Vector3(0.0, 0.0, -0.04 * nudge)
		snack.position.y = lerpf(from.y, floor_y, fall * fall)
		snack.rotation.x = -1.4 * fall
		if fall >= 1.0 and not bool(drop["landed"]):
			drop["landed"] = true
			_clunk(false)
		if fall >= 1.0:
			# Down the chute behind the flap.
			snack.visible = t < 0.18 + Constants.VEND_DROP_SECONDS + 0.12
	_drops = _drops.filter(func(drop: Dictionary) -> bool: return float(drop["t"]) < 2.0)


## The clunk as it lands (or sticks), and for a stuck one the sad trombone after.
func _clunk(stuck: bool) -> void:
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx == null:
		return
	var at := global_position + Vector3(0.0, 0.5, 0.0)
	sfx.call("play_at", "vend_clunk", at)
	if stuck:
		get_tree().create_timer(Constants.VEND_EAT_TROMBONE_DELAY).timeout.connect(func() -> void:
			if is_inside_tree():
				sfx.call("play_at", "vend_eat", at)
		)


## Whether the local player stands at the machine.
func _local_in_reach() -> bool:
	var me := _player(Net.local_peer_id())
	if me == null:
		return false
	var offset := me.global_position - global_position
	return Vector2(offset.x, offset.z).length() <= Constants.SHOP_REACH


func _player(peer_id: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node as Node3D
	return null
