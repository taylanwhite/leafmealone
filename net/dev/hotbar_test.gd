extends Node

## Authority: host. --hotbar-test checks the pockets (net/components/hotbar.gd,
## player/pockets.gd) the way a player uses them: pickups land in slots and come
## out into your hands, number keys and the wheel switch (as real input events,
## so Pockets._unhandled_input sees them), the selected number again puts your
## hands away, G only drops what's in hand, signs stack and the next one comes
## out, big things fill both hands and refuse a switch, pockets slow you a
## little, and leaving the yard or being caught empties them. Step 9 checks the
## holds (chunk C): hands on the real grips of the sign, gnome, trash can and
## wheelbarrow, the arms reaching them. Steps 13a-f check the bar on screen
## (ui/hotbar_hud.gd, chunk B) through its model: slots, icons, the hint, the hands
## card, the refusal shake and toasts, the goal line's "Press [1] for the rake",
## and that it hides under the pause buttons and Settings. It ends with a known set of pockets that
## CI compares with a client's view (probe "hotbar", grip_ok included).
## Each step prints a [HotbarTest] line and records a boolean in result["steps"].

const _Hotbar = preload("res://net/components/hotbar.gd")
const _Strings = preload("res://ui/strings.gd")
const _PropLooks = preload("res://props/prop_looks.gd")
const _HotbarHud = preload("res://ui/hotbar_hud.gd")
const PROP_SCENE: PackedScene = preload("res://props/yard_prop.tscn")
## How long to wait for the client to join, so it sees the whole run.
const CLIENT_WAIT_SECONDS: float = 12.0
## Windowed with --screenshot: how long step 9 shows each hold for the capture.
const HOLD_LINGER_SECONDS: float = 4.0

static var result: Dictionary = {}

var _started: bool = false
var _refusals: Array[String] = []
var _notices: Array[String] = []
var _ok: bool = true


func _process(_delta: float) -> void:
	if _started or not Net.is_host() or _me() == null or get_tree().get_first_node_in_group("job_lot") == null:
		return
	if get_tree().get_first_node_in_group("hotbar") == null or _me().get_node_or_null("Pockets") == null:
		return
	_started = true
	result["steps"] = {}
	_run()


func _run() -> void:
	await get_tree().create_timer(1.5).timeout
	var waited := 0.0
	while Net.peer_ids().size() < 2 and waited < CLIENT_WAIT_SECONDS:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	print("[HotbarTest] players: %d" % Net.peer_ids().size())
	var me := _me()
	var pockets := me.get_node("Pockets")
	pockets.connect("refused", func(reason: String) -> void: _refusals.append(reason))
	pockets.connect("notice", func(kind: String) -> void: _notices.append(kind))
	var rake := _prop("rake")
	var blower := _prop("leaf_blower")
	var trimmer := _prop("hedge_trimmer")
	var roller := _prop("paint_roller")
	var hose := _prop("hose")
	var gnome := _prop("gnome")
	if rake == null or blower == null or trimmer == null or roller == null or hose == null or gnome == null:
		_finish_with_error("missing a prop: rake %s blower %s trimmer %s roller %s hose %s gnome %s" % [rake != null, blower != null, trimmer != null, roller != null, hose != null, gnome != null])
		return
	await _go_to(Vector3(0.0, 0.1, 6.0), 0.0)

	# 1. The rake: slot 1, in hand.
	await _grab(rake)
	_step("1 rake held in slot 1", _holds(rake) and int(rake.get("pocket_slot")) == 0 and int(pockets.get("selected")) == 0)

	# 2. The blower: slot 2, in hand; the rake goes in its pocket, rides along, and isn't solid.
	await _grab(blower)
	var rake_away := int(rake.get("pocketed_by")) == _id() and int(rake.get("held_by")) == 0
	var blower_in := _holds(blower) and int(blower.get("pocket_slot")) == 1
	var not_solid := int(rake.get("collision_layer")) == 0
	await _teleport(me.global_position + Vector3(3.0, 0.0, 0.0), 0.0)
	await _ticks(6)
	var follows := rake.global_position.distance_to(me.global_position) < 1.5
	_step("2 blower held in slot 2, rake pocketed (%s), not solid (%s), follows (%.2f m)" % [rake_away, not_solid, rake.global_position.distance_to(me.global_position)], blower_in and rake_away and not_solid and follows)

	# 3. Trimmer, roller, hose: slots 3, 4, 5. One in hand (the hose), four pocketed.
	await _grab(trimmer)
	await _grab(roller)
	await _grab(hose)
	var slots_right := int(trimmer.get("pocket_slot")) == 2 and int(roller.get("pocket_slot")) == 3 and int(hose.get("pocket_slot")) == 4
	_step("3 five pockets: slots right %s, held %d, pocketed %d, hose in hand %s" % [slots_right, _held_count(), _pocketed_count(), _holds(hose)], slots_right and _held_count() == 1 and _pocketed_count() == 4 and _holds(hose))
	await _check_hud_bar()

	# 4. Pockets full: a sign won't go in, and the player hears why.
	var signs: Array[Node3D] = []
	var props := get_tree().get_first_node_in_group("runtime_props")
	for index: int in 3:
		var sign := PROP_SCENE.instantiate() as Node3D
		sign.name = "HotbarTestSign%d" % index
		sign.set("kind", "turf_sign")
		sign.set("label", _Strings.item_name("turf_sign"))
		sign.set("color", Color(0.1, 0.55, 0.28))
		# Rival signs, as world.gd plants them, so the town's watcher counts them pulled.
		sign.add_to_group("turf_signs")
		props.add_child(sign, true)
		sign.global_position = me.global_position + Vector3(-1.5 - float(index) * 0.8, 0.5, 1.5)
		signs.append(sign)
	await _ticks(3)
	_refusals.clear()
	await _grab(signs[0])
	var refused_full := await _wait_for(func() -> bool: return _refusals.has("full"), 10)
	var not_pulled := not bool(signs[0].get_meta("pulled", false))
	_step("4 pockets full: refused %s, sign still loose %s, not pulled %s" % [refused_full, bool(signs[0].call("is_loose")), not_pulled], refused_full and bool(signs[0].call("is_loose")) and not_pulled)
	var hud := _hud()
	var shook := hud != null and float(hud.get("shake_left")) > 0.0 and str(hud.get("toast_text")) == _Strings.keyed(str(_Strings.UI["hotbar_full"]))
	_step("13b HUD: the refusal shook the bar and said '%s'" % (str(hud.get("toast_text")) if hud != null else "no HUD"), shook)

	# 5. Keys: 1 draws the rake, the wheel steps to the blower, 2 again is bare hands.
	await _tap(&"slot_1")
	var key_one := _holds(rake) and int(hose.get("pocketed_by")) == _id()
	await _tap(&"slot_next")
	var wheel := _holds(blower)
	await _tap(&"slot_2")
	var bare := _held_count() == 0 and _pocketed_count() == 5 and int(pockets.get("selected")) == -1
	_step("5 key 1 -> rake %s, wheel -> blower %s, 2 again -> bare hands %s" % [key_one, wheel, bare], key_one and wheel and bare)
	# The goal line points at the pocketed rake: "Press [1] for the rake".
	var goal := str(preload("res://ui/job_goal.gd").goal(get_tree(), _id()))
	var want_goal := str(_Strings.UI["goal_draw_rake"]) % _Strings.keyed("{key:slot_1}")
	_step("13c goal line with the rake pocketed: '%s'" % goal, goal == want_goal)

	# 6. Key 3, then tap G: the trimmer is set down in front, solid, out of its slot.
	await _tap(&"slot_3")
	var trimmer_out := _holds(trimmer)
	await _hold_g(0.08)
	await _ticks(20)
	var offset := trimmer.global_position - me.global_position
	var flat := Vector2(offset.x, offset.z).length()
	var forward := -me.global_basis.z
	var in_front := Vector2(offset.x, offset.z).normalized().dot(Vector2(forward.x, forward.z).normalized()) > 0.5
	var set_down := bool(trimmer.call("is_loose")) and int(trimmer.get("pocket_slot")) == -1 and int(trimmer.get("collision_layer")) == 1
	var slot_empty := (_slots()[2] as Array).is_empty() and _held_count() == 0
	_step("6 trimmer drawn %s, set down %s at %.2f m in front %s, slot 3 empty %s" % [trimmer_out, set_down, flat, in_front, slot_empty], trimmer_out and set_down and flat >= 0.8 and flat <= 2.0 and in_front and slot_empty)

	# 7. Three signs stack in slot 3; throw one, the next comes out.
	for sign: Node3D in signs:
		await _grab(sign)
	var stacked := (_slots()[2] as Array).size() == 3 and _in_hand() != null and str(_in_hand().get("kind")) == "turf_sign"
	# Signs that went straight into the stack (never in hand) count as pulled too.
	var all_pulled := await _wait_for(func() -> bool:
		for sign: Node3D in signs:
			if not bool(sign.get_meta("pulled", false)):
				return false
		return true, 10)
	_step("7a three signs stacked %s, all counted pulled by the town %s" % [stacked, all_pulled], stacked and all_pulled)
	await _go_to(Vector3(0.0, 0.1, 12.5), PI)
	var thrown := _in_hand() as Node3D
	var start := me.global_position
	Input.action_press(&"drop")
	await _seconds(0.6)
	Input.action_release(&"drop")
	var next_out := await _wait_for(func() -> bool: return _in_hand() != null and _in_hand() != thrown and str(_in_hand().get("kind")) == "turf_sign", 10)
	var farthest := 0.0
	var watched := 0.0
	while watched < 2.0 and thrown != null and is_instance_valid(thrown):
		await get_tree().physics_frame
		watched += get_physics_process_delta_time()
		farthest = maxf(farthest, Vector2(thrown.global_position.x - start.x, thrown.global_position.z - start.z).length())
	var left_two := (_slots()[2] as Array).size() == 2
	_step("7 stacked %s, thrown %.1f m, two left %s, next drawn %s" % [stacked, farthest, left_two, next_out], stacked and farthest > 2.0 and left_two and next_out)
	await _frames(3)
	var stack_badge := _hud_slot(2)
	_step("13d HUD: slot 3 shows %s x%d" % [stack_badge.get("kind", "?"), int(stack_badge.get("count", 0))], str(stack_badge.get("kind", "")) == "turf_sign" and int(stack_badge.get("count", 0)) == 2)

	# 8. The gnome fills both hands: the sign goes in its pocket, a switch is refused,
	# and setting the gnome down brings a sign back out.
	await _go_to(Vector3(0.0, 0.1, 6.0), 0.0)
	var sign_before := _in_hand()
	await _grab(gnome)
	var hugged := _holds(gnome) and int(gnome.get("pocket_slot")) == -1 and sign_before != null and int(sign_before.get("pocketed_by")) == _id()
	await _frames(3)
	var card: Dictionary = (_hud().get("last_model") as Dictionary).get("hands", {}) if _hud() != null else {}
	var card_ok := str(card.get("kind", "")) == "gnome" and str(card.get("title", "")).contains(str(_Strings.UI["item_gnome"])) and str(card.get("line", "")) != ""
	_refusals.clear()
	await _tap(&"slot_1")
	var no_switch := _refusals.has("arms_full") and _holds(gnome)
	var said := str(_hud().get("toast_text")) if _hud() != null else ""
	_step("13e HUD: hands card '%s' / '%s', switch refused with '%s'" % [card.get("title", ""), card.get("line", ""), said], card_ok and said == _Strings.keyed(str(_Strings.UI["hotbar_arms_full"])))
	await _hold_g(0.08)
	await _ticks(6)
	var sign_back := bool(gnome.call("is_loose")) and _in_hand() != null and str(_in_hand().get("kind")) == "turf_sign"
	_step("8 gnome hugged %s, switch refused %s, set down and sign back %s" % [hugged, no_switch, sign_back], hugged and no_switch and sign_back)

	# 8b. Carrying a teammate fills both arms: hands away, then neither a key nor a
	# direct ask draws anything until they're set down.
	await _tap(&"slot_3")
	var hands_away := _held_count() == 0 and int(pockets.get("selected")) == -1
	me.call("set_carry_state", 424242, 0)
	await _tap(&"slot_1")
	var key_blocked := _held_count() == 0
	get_tree().get_first_node_in_group("hotbar").call("request_select", 0)
	await _ticks(6)
	var host_blocked := _held_count() == 0
	me.call("set_carry_state", 0, 0)
	await _ticks(3)
	await _tap(&"slot_3")
	var sign_again := _in_hand() != null and str(_in_hand().get("kind")) == "turf_sign"
	_step("8b hands away %s; carrying: key blocked %s, host refused %s; set down, sign drawn %s" % [hands_away, key_blocked, host_blocked, sign_again], hands_away and key_blocked and host_blocked and sign_again)

	# 9. Holds (chunk C): the hands land on the real grips, the arms reach them,
	# and the gnome, trash can, sign and wheelbarrow sit the way HOLDS says.
	await _check_holds()

	# 10. Pockets weigh a quarter.
	var expected := _expected_speed()
	var speed := float(me.call("carry_speed_scale"))
	_step("10 speed %.4f, expected %.4f" % [speed, expected], absf(speed - expected) <= 0.001 and speed < 1.0)

	# 11. Leaving the yard mid-job leaves everything there; a capture empties pockets too.
	if not Campaign.is_job_open():
		Campaign.mark_job_open()
	var mine := _Hotbar.items_of(get_tree(), _id())
	_notices.clear()
	Net.move_player_to_zone(_id(), Net.Zone.STORE)
	var left_ok := await _wait_for(func() -> bool: return _all_loose_on_pad(mine) and _notices.has("left"), 60)
	_step("11a left the yard with %d things: all loose on the yard and told %s" % [mine.size(), left_ok], left_ok and mine.size() >= 5)
	var left_toast := str(_hud().get("toast_text")) if _hud() != null else ""
	_step("13f HUD: told '%s'" % left_toast, left_toast == _Strings.keyed(str(_Strings.UI["hotbar_left"])))
	Net.move_player_to_zone(_id(), Net.Zone.LOT)
	await _seconds(0.6)
	await _go_to(Vector3(-4.0, 0.1, 6.0), 0.0)
	await _grab(rake)
	await _grab(blower)
	var director := get_tree().get_first_node_in_group("run_director")
	if director == null:
		_step("11b capture path: no run director", false)
	else:
		# The real catch's drop (net/run_events/encounter.gd at the end of the cite):
		# the itemized row, one by one, 0.6 m apart across the pair's facing, no toast.
		# The catch itself would start the van ride, which isn't this test's business.
		_notices.clear()
		var caught := _Hotbar.items_of(get_tree(), _id())
		var origin := (_me() as Node3D).global_position + Vector3(1.0, 0.0, 0.0)
		get_tree().get_first_node_in_group("hotbar").call("host_empty_pockets", _id(), "itemized", origin, Vector3(0.0, 0.0, -1.0))
		var itemized := await _wait_for(func() -> bool: return _all_loose_on_pad(caught), 90)
		await _seconds(1.2)
		var row_ok := caught.size() == 2
		if row_ok:
			var a := (caught[0] as Node3D).global_position
			var b := (caught[1] as Node3D).global_position
			var gap := Vector2(a.x - b.x, a.z - b.z).length()
			# Across a -Z facing the row runs along x, 0.6 m apart, from the origin.
			var line := absf(a.z - b.z)
			row_ok = absf(gap - Constants.CATCH_ROW_SPACING) < 0.3 and line < 0.35
			print("[HotbarTest] itemized row: %s and %s, %.2f m apart (%.2f off the line)" % [a, b, gap, line])
		_step("11b caught with %d things: itemized in a row %s, no toast %s" % [caught.size(), itemized and row_ok, _notices.is_empty()], itemized and row_ok and _notices.is_empty())

	# 12. A known set for the client to agree on: rake in hand (slot 1), blower in
	# slot 2, two signs in slot 3.
	await _go_to(Vector3(4.0, 0.1, 6.0), 0.0)
	await _grab(rake)
	await _grab(blower)
	var loose_signs: Array[Node3D] = []
	for sign: Node3D in signs:
		if is_instance_valid(sign) and bool(sign.call("is_loose")):
			loose_signs.append(sign)
	for index: int in mini(2, loose_signs.size()):
		await _grab(loose_signs[index])
	await _tap(&"slot_1")
	var final_slots := _Hotbar.snapshot(get_tree()).get(Net.player_name(_id()), {}) as Dictionary
	var want := [["rake", 1], ["leaf_blower", 1], ["turf_sign", 2], ["", 0], ["", 0]]
	await _ticks(10)
	final_slots = _Hotbar.snapshot(get_tree()).get(Net.player_name(_id()), {}) as Dictionary
	var final_ok := JSON.stringify(final_slots.get("slots", [])) == JSON.stringify(want) and str(final_slots.get("hand", "")) == "rake" and bool(final_slots.get("grip_ok", false))
	_step("12 final pockets %s, hand %s, grip_ok %s" % [JSON.stringify(final_slots.get("slots", [])), final_slots.get("hand", ""), final_slots.get("grip_ok", false)], final_ok)
	await _seconds(1.0)
	result["ok"] = _ok
	result["done"] = true
	print("[HotbarTest] all ok: %s" % _ok)


# ---------------------------------------------------------------- the HUD (step 13)

## 13a: the bar (ui/hotbar_hud.gd, under UIRoot) shows the five pockets with
## their icons, the hose selected and in hand with its hint, the roller's paint
## strip; it hides under the pause buttons and under Settings opened from them
## (any_window_open), and comes back when they close; and the visibility rule
## (shown_when) keeps it off in Border Return and a Chefty seat, and off the yard
## unless something's carried.
func _check_hud_bar() -> void:
	await _frames(3)
	var hud := _hud()
	if hud == null:
		_step("13a HUD: no UIRoot/HotbarHud", false)
		return
	var shown_model: Dictionary = hud.get("last_model")
	var kinds: Array = []
	var icons := true
	for view: Dictionary in shown_model.get("slots", []):
		kinds.append(view.get("kind", ""))
		icons = icons and str(view.get("icon", "")) != ""
	var want := ["rake", "leaf_blower", "hedge_trimmer", "paint_roller", "hose"]
	var bar_ok := bool(shown_model.get("shown", false)) and JSON.stringify(kinds) == JSON.stringify(want) and int(shown_model.get("selected", -9)) == 4
	var hand_ok := str(shown_model.get("hand", "")) == "hose" and str(shown_model.get("hint", "")) == str(_Strings.UI["tool_blurb_hose"])
	var paint_ok := float((shown_model["slots"] as Array)[3].get("paint", -1.0)) >= 0.0
	var ui := get_tree().get_first_node_in_group("game_ui")
	var hides := ui != null
	var settings_hides := ui != null
	var back := ui != null
	if ui != null:
		ui.call("open_pause")
		await _frames(3)
		hides = not bool((hud.get("last_model") as Dictionary).get("shown", true))
		ui.call("open_settings", true, "sound")
		await _frames(3)
		settings_hides = bool(ui.call("any_window_open")) and not bool((hud.get("last_model") as Dictionary).get("shown", true))
		ui.call("close_settings")
		await _frames(3)
		ui.call("close_pause")
		await _frames(3)
		# Back up once nothing's open. Headless (CI) it must be: no window, bar up. A
		# windowed run that loses focus reopens the pause buttons by itself (ui_root
		# _notification), so there it only checks the bar agrees with the windows.
		var open_now := bool(ui.call("any_window_open"))
		var shown_now := bool((hud.get("last_model") as Dictionary).get("shown", false))
		if DisplayServer.get_name() == "headless":
			back = not open_now and shown_now
		else:
			back = open_now != shown_now
	var base := {"in_session": true, "zone": Net.Zone.LOT, "window_open": false, "seated": false, "carrying": false}
	var rule := bool(_HotbarHud.shown_when(base))
	rule = rule and not bool(_HotbarHud.shown_when(base.merged({"zone": Net.Zone.BORDER, "carrying": true}, true)))
	rule = rule and not bool(_HotbarHud.shown_when(base.merged({"seated": true}, true)))
	rule = rule and not bool(_HotbarHud.shown_when(base.merged({"zone": Net.Zone.STORE}, true)))
	rule = rule and bool(_HotbarHud.shown_when(base.merged({"zone": Net.Zone.STORE, "carrying": true}, true)))
	_step("13a HUD: bar %s %s icons %s, hose in hand with its hint %s, paint strip %s; hides under pause %s and Settings %s, back after %s; rule %s" % [kinds, bar_ok, icons, hand_ok, paint_ok, hides, settings_hides, back, rule], bar_ok and icons and hand_ok and paint_ok and hides and settings_hides and back and rule)


func _hud() -> Node:
	var ui := get_tree().get_first_node_in_group("game_ui")
	return ui.get_node_or_null("HotbarHud") if ui != null else null


## The HUD's view of one slot, or {}.
func _hud_slot(index: int) -> Dictionary:
	var hud := _hud()
	if hud == null:
		return {}
	var slots: Array = (hud.get("last_model") as Dictionary).get("slots", [])
	return slots[index] if index < slots.size() else {}


# ---------------------------------------------------------------- holds (step 9)

## 9a the sign in hand, 9b the gnome, 9c the trash can, 9d the wheelbarrow, 9e
## the right arm pointing at its grip. Each big thing is set down again after,
## which brings the sign back out.
func _check_holds() -> void:
	var me := _me()
	var body := me.get_node_or_null("Visual/CartoonBody") as Node3D
	if body == null:
		_step("9 holds: no CartoonBody on the host's player", false)
		return
	await _ticks(10)
	var sign := _in_hand() as Node3D
	var sign_ok := sign != null and str(sign.get("kind")) == "turf_sign" and _grips_on(sign, me, body, 1)
	_step("9a sign in hand: right hand on its wire, left hand free %s" % sign_ok, sign_ok)
	await _linger()
	var gnome := _prop("gnome")
	# Each hold on a clear spot of its own, so what was set down before isn't in
	# the way (or in the screenshots).
	await _go_to(Vector3(-6.0, 0.1, 9.0), 0.0)
	await _grab(gnome)
	await _ticks(10)
	var look := gnome.get_node_or_null("Visual/Look") as Node3D
	var ahead := -me.global_basis.z
	var upright := look != null and look.global_basis.y.normalized().dot(Vector3.UP) > 0.95
	var facing := look != null and (-look.global_basis.z).normalized().dot(Vector3(ahead.x, 0.0, ahead.z).normalized()) > 0.8
	var hugged := _holds(gnome) and _grips_on(gnome, me, body, 2)
	var aimed := _arm_on_grip(body, _PropLooks.grip_points(gnome, me)[0])
	_step("9b gnome hugged %s, upright %s, facing ahead %s" % [hugged, upright, facing], hugged and upright and facing)
	_step("9e right arm points at its grip %s" % aimed, aimed)
	await _linger()
	await _hold_g(0.08)
	await _ticks(6)
	var trash := _prop("trash")
	await _go_to(Vector3(-3.5, 0.1, 9.0), 0.0)
	await _grab(trash)
	await _ticks(10)
	var by_handles := _holds(trash) and _grips_on(trash, me, body, 2)
	_step("9c trash can by its side handles %s" % by_handles, by_handles)
	await _linger()
	await _hold_g(0.08)
	await _ticks(6)
	var barrow := _prop("wheelbarrow")
	await _go_to(Vector3(-1.0, 0.1, 9.0), 0.0)
	await _grab(barrow)
	await _ticks(10)
	var ground := me.global_position.y
	var tray := barrow.get_node_or_null("Visual/Look") as Node3D
	var on_wheel := tray != null and absf(tray.global_position.y - ground) <= 0.15
	var grips := _PropLooks.grip_points(barrow, me)
	var lifted := true
	var heights := ""
	for point: Vector3 in grips:
		lifted = lifted and point.is_finite() and point.y - ground >= 0.65 and point.y - ground <= 0.95
		heights += " %.2f" % (point.y - ground if point.is_finite() else -1.0)
	var pushed := _holds(barrow) and _grips_on(barrow, me, body, 2)
	_step("9d wheelbarrow on its wheel %s (base %.2f m up), handles lifted to%s m %s, hands on them %s" % [on_wheel, tray.global_position.y - ground if tray != null else -1.0, heights, lifted, pushed], on_wheel and lifted and pushed)
	await _linger()
	await _hold_g(0.08)
	await _ticks(6)
	# The shouldered ladder (a hand through a rung) and the pushed mower (both on the bar).
	var others := ""
	var others_ok := true
	for entry: Array in [["ladder", 1, 2.0], ["lawn_mower", 2, 4.5]]:
		await _go_to(Vector3(float(entry[2]), 0.1, 9.0), 0.0)
		var thing := _prop(str(entry[0]))
		if thing == null:
			others += " %s missing" % entry[0]
			others_ok = false
			continue
		await _grab(thing)
		await _ticks(10)
		var on := _holds(thing) and _grips_on(thing, me, body, int(entry[1]))
		others += " %s %s" % [entry[0], on]
		others_ok = others_ok and on
		await _linger()
		await _hold_g(0.08)
		await _ticks(6)
	_step("9g%s" % others, others_ok)
	var sign_back := _in_hand() != null and str(_in_hand().get("kind")) == "turf_sign"
	_step("9f set down, sign back in hand %s" % sign_back, sign_back)


## Windowed with --screenshot, each hold stays up long enough for net/dev/capture.gd
## to catch it in first person and from outside (a selfie). Headless: no wait.
func _linger() -> void:
	if str(Net.dev_options().get("screenshot_dir")) != "" and DisplayServer.get_name() != "headless":
		await _seconds(HOLD_LINGER_SECONDS)


## The held prop's grips: exactly `hands` of them real, each on the model (within
## 0.08 m of its look's world bounds) and within reach of its shoulder.
func _grips_on(prop: Node3D, holder: Node3D, body: Node3D, hands: int) -> bool:
	var points := _PropLooks.grip_points(prop, holder)
	var bounds := _look_bounds(prop)
	var real := 0
	for side: int in points.size():
		var point := points[side]
		if not point.is_finite():
			continue
		real += 1
		var on_model := bounds.size != Vector3.ZERO and _distance_to_box(point, bounds) <= 0.08
		var shoulder: Vector3 = body.call("shoulder_position", side)
		var in_reach := shoulder.distance_to(point) <= Constants.HOLD_GRIP_REACH
		if not on_model or not in_reach:
			print("[HotbarTest] %s grip %d: %.3f m off the model, %.2f m from the shoulder" % [prop.get("kind"), side, _distance_to_box(point, bounds), shoulder.distance_to(point)])
			return false
	return real == hands


## The right arm's -Y points at the right grip.
func _arm_on_grip(body: Node3D, grip: Vector3) -> bool:
	if not grip.is_finite():
		return false
	var shoulder: Vector3 = body.call("shoulder_position", 0)
	var arm: Vector3 = body.call("arm_direction", 0)
	var dot := arm.dot((grip - shoulder).normalized())
	print("[HotbarTest] right arm . grip = %.3f" % dot)
	return dot > 0.9


func _look_bounds(prop: Node3D) -> AABB:
	var look := prop.get_node_or_null("Visual/Look") as Node3D
	var total := AABB()
	var first := true
	if look == null:
		return total
	for node: Node in look.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var box := mesh.global_transform * mesh.get_aabb()
		total = box if first else total.merge(box)
		first = false
	return total


func _distance_to_box(point: Vector3, box: AABB) -> float:
	var inside := point.clamp(box.position, box.end)
	return point.distance_to(inside)


# ---------------------------------------------------------------- helpers

func _step(label: String, passed: bool) -> void:
	print("[HotbarTest] %s: %s" % [label, passed])
	(result["steps"] as Dictionary)[label.get_slice(" ", 0)] = passed
	_ok = _ok and passed


func _finish_with_error(message: String) -> void:
	print("[HotbarTest] error: %s" % message)
	result["error"] = message
	result["ok"] = false
	result["done"] = true


## The speed carry_speed_scale should give: what's in hand at its weight (rolling
## things lighter), plus a quarter of what's pocketed.
func _expected_speed() -> float:
	var kg := 0.0
	var hand := _in_hand()
	if hand != null:
		kg = float(hand.call("weight_kg"))
		if Constants.ROLLING_KINDS.has(str(hand.get("kind"))):
			kg *= Constants.ROLLING_WEIGHT_SHARE
	for item: Node in _Hotbar.items_of(get_tree(), _id()):
		if int(item.get("pocketed_by")) == _id():
			kg += float(item.call("weight_kg")) * Constants.POCKET_WEIGHT_SHARE
	return maxf(Constants.CARRY_SPEED_FLOOR, 1.0 - kg * Constants.CARRY_SLOWDOWN_PER_KG)


## Every one of these is loose, inside the yard's pad.
func _all_loose_on_pad(items: Array[Node]) -> bool:
	var world := get_tree().get_first_node_in_group("world")
	var zone := world.get_node_or_null("LotZone") as Node3D if world != null else null
	if zone == null:
		return false
	var rect: Rect2 = Constants.PAD_RECTS.get("LotZone", Rect2(-20.0, -20.0, 40.0, 40.0))
	for item: Node in items:
		if not is_instance_valid(item) or not bool(item.call("is_loose")):
			return false
		var local := (item as Node3D).global_position - zone.global_position
		if not rect.has_point(Vector2(local.x, local.z)):
			return false
	return true


## Put the item just in front, then ask for it the way E does.
func _grab(item: Node3D) -> void:
	var me := _me()
	await get_tree().physics_frame
	item.global_position = me.global_position + Vector3(0.0, 0.4, 0.0) + (-me.global_basis.z) * 0.8
	item.set("linear_velocity", Vector3.ZERO)
	await _ticks(3)
	item.call("request_grab")
	await _ticks(3)


## A key press as a player's: press, then release next tick, through the input
## pipeline (bot_job._tap does the same).
func _tap(action: StringName) -> void:
	_send(action, true)
	await _ticks(1)
	_send(action, false)
	await _ticks(5)


func _send(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)


func _hold_g(seconds: float) -> void:
	Input.action_press(&"drop")
	await _seconds(seconds)
	Input.action_release(&"drop")
	await _ticks(3)


## Somewhere on the yard (relative to it), facing yaw.
func _go_to(local: Vector3, yaw: float) -> void:
	var lot := get_tree().get_first_node_in_group("job_lot") as Node3D
	await _teleport((lot.global_position if lot != null else Vector3.ZERO) + local, yaw)


func _teleport(at: Vector3, yaw: float) -> void:
	await get_tree().physics_frame
	_me().call("apply_network_teleport", Transform3D(Basis(Vector3.UP, yaw), at))
	await _ticks(3)


func _wait_for(check: Callable, ticks: int) -> bool:
	for _tick: int in ticks:
		if bool(check.call()):
			return true
		await get_tree().physics_frame
	return bool(check.call())


func _seconds(seconds: float) -> void:
	var waited := 0.0
	while waited < seconds:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()


## Rendered frames: the HUD updates in _process, which a slow windowed run can
## step less often than physics.
func _frames(count: int) -> void:
	for _frame: int in count:
		await get_tree().process_frame


func _ticks(count: int) -> void:
	for _tick: int in count:
		await get_tree().physics_frame


func _id() -> int:
	return Net.local_peer_id()


func _holds(item: Node) -> bool:
	return item != null and int(item.get("held_by")) == _id()


func _in_hand() -> Node:
	return _Hotbar.in_hand(get_tree(), _id())


func _slots() -> Array:
	return _Hotbar.slots_of(get_tree(), _id())


func _held_count() -> int:
	var count := 0
	for item: Node in _Hotbar.items_of(get_tree(), _id()):
		if int(item.get("held_by")) == _id():
			count += 1
	return count


func _pocketed_count() -> int:
	var count := 0
	for item: Node in _Hotbar.items_of(get_tree(), _id()):
		if int(item.get("pocketed_by")) == _id():
			count += 1
	return count


func _me() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as Node3D
	return null


func _prop(kind: String) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) == kind and not node.is_queued_for_deletion():
			return node as Node3D
	return null
