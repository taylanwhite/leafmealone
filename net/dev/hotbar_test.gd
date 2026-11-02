extends Node

## Authority: host. --hotbar-test checks the pockets (net/components/hotbar.gd,
## player/pockets.gd) the way a player uses them: pickups land in slots and come
## out into your hands, number keys and the wheel switch (as real input events,
## so Pockets._unhandled_input sees them), the selected number again puts your
## hands away, G only drops what's in hand, signs stack and the next one comes
## out, big things fill both hands and refuse a switch, pockets slow you a
## little, and leaving the yard or being caught empties them. It ends with a
## known set of pockets that CI compares with a client's view (probe "hotbar").
## Holds and grips are hotbar chunk C; step 9 of the spec is theirs.
## Each step prints a [HotbarTest] line and records a boolean in result["steps"].

const _Hotbar = preload("res://net/components/hotbar.gd")
const _Strings = preload("res://ui/strings.gd")
const PROP_SCENE: PackedScene = preload("res://props/yard_prop.tscn")
## How long to wait for the client to join, so it sees the whole run.
const CLIENT_WAIT_SECONDS: float = 12.0

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

	# 4. Pockets full: a sign won't go in, and the player hears why.
	var signs: Array[Node3D] = []
	var props := get_tree().get_first_node_in_group("runtime_props")
	for index: int in 3:
		var sign := PROP_SCENE.instantiate() as Node3D
		sign.name = "HotbarTestSign%d" % index
		sign.set("kind", "turf_sign")
		sign.set("label", _Strings.item_name("turf_sign"))
		sign.set("color", Color(0.1, 0.55, 0.28))
		props.add_child(sign, true)
		sign.global_position = me.global_position + Vector3(-1.5 - float(index) * 0.8, 0.5, 1.5)
		signs.append(sign)
	await _ticks(3)
	_refusals.clear()
	await _grab(signs[0])
	var refused_full := await _wait_for(func() -> bool: return _refusals.has("full"), 10)
	_step("4 pockets full: refused %s, sign still loose %s" % [refused_full, bool(signs[0].call("is_loose"))], refused_full and bool(signs[0].call("is_loose")))

	# 5. Keys: 1 draws the rake, the wheel steps to the blower, 2 again is bare hands.
	await _tap(&"slot_1")
	var key_one := _holds(rake) and int(hose.get("pocketed_by")) == _id()
	await _tap(&"slot_next")
	var wheel := _holds(blower)
	await _tap(&"slot_2")
	var bare := _held_count() == 0 and _pocketed_count() == 5 and int(pockets.get("selected")) == -1
	_step("5 key 1 -> rake %s, wheel -> blower %s, 2 again -> bare hands %s" % [key_one, wheel, bare], key_one and wheel and bare)

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

	# 8. The gnome fills both hands: the sign goes in its pocket, a switch is refused,
	# and setting the gnome down brings a sign back out.
	await _go_to(Vector3(0.0, 0.1, 6.0), 0.0)
	var sign_before := _in_hand()
	await _grab(gnome)
	var hugged := _holds(gnome) and int(gnome.get("pocket_slot")) == -1 and sign_before != null and int(sign_before.get("pocketed_by")) == _id()
	_refusals.clear()
	await _tap(&"slot_1")
	var no_switch := _refusals.has("arms_full") and _holds(gnome)
	await _hold_g(0.08)
	await _ticks(6)
	var sign_back := bool(gnome.call("is_loose")) and _in_hand() != null and str(_in_hand().get("kind")) == "turf_sign"
	_step("8 gnome hugged %s, switch refused %s, set down and sign back %s" % [hugged, no_switch, sign_back], hugged and no_switch and sign_back)

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
	Net.move_player_to_zone(_id(), Net.Zone.LOT)
	await _seconds(0.6)
	await _go_to(Vector3(-4.0, 0.1, 6.0), 0.0)
	await _grab(rake)
	await _grab(blower)
	var director := get_tree().get_first_node_in_group("run_director")
	if director == null:
		_step("11b capture path: no run director", false)
	else:
		# The real capture path's drop (director.note_capture calls it); note_capture
		# itself would start Border Return, which isn't this test's business.
		_notices.clear()
		var caught := _Hotbar.items_of(get_tree(), _id())
		director.call("_release_held", _id())
		var confiscated := await _wait_for(func() -> bool: return _all_loose_on_pad(caught) and _notices.has("confiscated"), 60)
		_step("11b caught with %d things: confiscated %s" % [caught.size(), confiscated], confiscated and caught.size() == 2)

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
	var final_ok := JSON.stringify(final_slots.get("slots", [])) == JSON.stringify(want) and str(final_slots.get("hand", "")) == "rake"
	_step("12 final pockets %s, hand %s" % [JSON.stringify(final_slots.get("slots", [])), final_slots.get("hand", "")], final_ok)
	await _seconds(1.0)
	result["ok"] = _ok
	result["done"] = true
	print("[HotbarTest] all ok: %s" % _ok)


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
