extends Node3D

## Authority: local, cosmetic. The Snak-o-Matic (docs/GAME.md "Shops"; gap
## shops chunk 6): Homie Depot's vending machine on the store's front wall, the
## shop with no keeper. Always open, 1.5x prices, and now and then it keeps
## your money. Every peer builds its own from Constants.SHOP_SITES (levels/
## dressing/shop_sites.gd); buying goes through World/Shops like any shop.
##
## The machine shows what happened from the replicated shop state, so everyone
## at the store sees the same thing and nothing here is networked. Every slot
## sells one item (shop_models.vending_slot_item: cans of warm Turbo, rolls of
## bags, sandwiches), and the shelf is built from Shops.stock and
## Shops.vending_stuck, so a late joiner sees the same gaps and the same stuck
## snack as everyone else:
## - a snack sold (an item's stock in Shops.stock went down): the front one of
##   that item's top slot drops off its coil, falls to the bottom and the machine
##   clunks as it lands (the buyer's snack_eater then has it hop out of the flap
##   into their hand); the slot fills back up at the next restock;
## - money eaten (Shops.vending_stuck got longer): the coil of that item turns,
##   the snack tips forward and sticks there, hanging, the clunk, then the sad
##   trombone, and the screen thanks you for your donation. It hangs there till
##   the morning (a new Shops.stock_day refills every slot).
## Nothing is read until Shops has its real state (Shops.synced): a client's
## defaults before the first snapshot would look like a day of sales.
## Its screen is a little green marquee scrolling KEEPER_LINES.snak_o_matic:
## a hello when you walk up, a line when you open it and when it sells you
## something. E at the machine opens its window (ui/ui_root.gd open_shop).

const _ShopModels = preload("res://props/shop_models.gd")
const _MeshKit = preload("res://props/mesh_kit.gd")
const _Stylized = preload("res://props/stylized.gd")
const _LowPoly = preload("res://props/low_poly.gd")
const _Strings = preload("res://ui/strings.gd")
const SHOP_ID: String = "snak_o_matic"
## The marquee: how many letters show at once, and how fast it scrolls
## (letters/s). In a fixed-width face at SCREEN_PIXEL, six letters are 15 cm,
## inside the bezel's black (shop_models _vending_machine).
const SCREEN_CHARS: int = 6
const SCROLL_RATE: float = 7.0
const SCREEN_PIXEL: float = 0.0014
const SCREEN_GREEN := Color(0.45, 1.0, 0.55)
## How far a stuck snack tips forward on its coil (rad).
const STUCK_TIP: float = 0.95

## The last line on the screen and why (tests and the probe read them).
var last_line: String = ""
var last_trigger: String = ""

var _fronts: Array[Node3D] = []
var _screen: Label3D
var _line_left: float = 0.0
var _scroll: float = 0.0
## What the shelf last showed: stock per item, the stuck count, the stock day
## (_day_seen -1 until Shops is synced and the shelf is first built).
var _stock_seen: Dictionary = {}
var _stuck_seen: int = 0
var _day_seen: int = -1
## The newest stuck snack (tests read it), null when none hangs.
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
			snack.set_meta("item", _ShopModels.vending_slot_item(row, slot))
			add_child(snack)
			_fronts.append(snack)
	_glass(front)
	var title := _LowPoly.text_sign(self, str(_Strings.SHOP_UI["sign_snak_o_matic"]), Vector3(0.0, _ShopModels.VENDING_HEADER_Y, front - 0.04), 34, Color(0.75, 0.2, 0.12), PI)
	title.outline_size = 0
	title.pixel_size = 0.0034
	_screen = Label3D.new()
	_screen.name = "Screen"
	# A fixed-width face, so a line of Ms is as wide as a line of Is: an LCD.
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Courier New", "DejaVu Sans Mono", "monospace"])
	_screen.font = mono
	_screen.font_size = 30
	_screen.pixel_size = SCREEN_PIXEL
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
	if _shops == null or not is_instance_valid(_shops):
		_shops = get_tree().get_first_node_in_group("shops")
		_day_seen = -1
	if _shops == null or _day_seen >= 0 or not bool(_shops.get("synced")):
		return
	# The first real state (a client's first snapshot, or the host's own): the
	# shelf as it stands, with nothing played. A peer that joins mid-day sees the
	# empty slots already empty and the stuck snack already hanging.
	_refill()


## Where a snack comes out: the tray behind the push flap (world space).
func tray_point() -> Vector3:
	return to_global(_ShopModels.VENDING_TRAY)


## What the replicated state says happened since the last look.
func _watch() -> void:
	if _shops == null or not is_instance_valid(_shops) or _day_seen < 0:
		return
	if int(_shops.get("stock_day")) != _day_seen:
		# A new morning: the machine's restocked, and whatever was stuck came loose.
		_refill()
		return
	var stock := _stock()
	var sold := false
	for item: Variant in stock:
		for _unit: int in maxi(int(_stock_seen.get(item, 0)) - int(stock[item]), 0):
			_drop(str(item), false)
			sold = true
	if sold:
		say_line("buy")
	var stuck: Array = _shops.get("vending_stuck")
	for index: int in range(_stuck_seen, stuck.size()):
		_drop(str(stuck[index]), true)
		_show(str(_Strings.SHOP_UI["shop_result_eaten"]).to_upper(), "eaten")
	_stock_seen = stock
	_stuck_seen = stuck.size()


## Today's stock per item, as Shops has it.
func _stock() -> Dictionary:
	return ((_shops.get("stock") as Dictionary).get(SHOP_ID, {}) as Dictionary).duplicate()


## The shelf from the state, with nothing played: each item's slots as full as
## its stock (sold ones gone from the top down, _pick's order) and what the
## machine ate today hanging on the next coils down. The same slots on every peer.
func _refill() -> void:
	_drops.clear()
	_stuck = null
	_day_seen = int(_shops.get("stock_day"))
	_stock_seen = _stock()
	var stuck: Array = _shops.get("vending_stuck")
	_stuck_seen = stuck.size()
	for snack: Node3D in _fronts:
		snack.position = snack.get_meta("home")
		snack.rotation = Vector3.ZERO
		snack.visible = true
		snack.set_meta("gone", false)
	for item: Variant in _stock_seen:
		var slots := _slots_of(str(item))
		var sold := clampi(slots.size() - int(_stock_seen[item]), 0, slots.size())
		for index: int in sold:
			slots[index].visible = false
			slots[index].set_meta("gone", true)
	for item: Variant in stuck:
		var snack := _pick(str(item))
		if snack != null:
			snack.set_meta("gone", true)
			_stick(snack, 1.0, 0.0)
			_stuck = snack


## An item's front snacks in the order they go: from the top shelf down.
func _slots_of(item: String) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for index: int in range(_fronts.size() - 1, -1, -1):
		if str(_fronts[index].get_meta("item", "")) == item:
			out.append(_fronts[index])
	return out


## A snack of this item falls (stuck: tips and hangs instead). The clunk lands with it.
func _drop(item: String, stuck: bool) -> void:
	var snack := _pick(item)
	if snack == null:
		_clunk(stuck)
		return
	snack.set_meta("gone", true)
	if stuck:
		_stuck = snack
	_drops.append({"node": snack, "t": 0.0, "stuck": stuck, "from": snack.get_meta("home"), "landed": false})


## The next front snack of this item still on its coil: from the top down, so
## you can see the gap.
func _pick(item: String) -> Node3D:
	for snack: Node3D in _slots_of(item):
		if snack.visible and not bool(snack.get_meta("gone", false)):
			return snack
	return null


## A stuck snack's pose: turn of the coil 0..1, plus a wobble (rad).
func _stick(snack: Node3D, turn: float, wobble: float) -> void:
	var home: Vector3 = snack.get_meta("home")
	# Out over the shelf's edge, leaning on the glass: its top toward you.
	snack.position = home + Vector3(0.0, -0.025 * turn, -0.035 * turn)
	snack.rotation.x = -(STUCK_TIP * turn * turn + wobble)


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
			_stick(snack, turn, wobble)
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
