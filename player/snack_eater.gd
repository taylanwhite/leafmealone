extends Node

## Authority: local, cosmetic. A player eating a snack and wearing it after
## (docs/GAME.md "Shops", "Snacks: what you see"; gap shops chunk 6). A child of
## the player's CartoonBody, on every peer, so it runs after the body each tick
## and everyone sees the same thing. Nothing here is networked: it reads
## World/Shops, whose snapshot already carries each player's last snack
## (Shops.snacks: item, the buff it gave, the server time it was handed over)
## and their buffs with server-time expiries.
##
## A new snack in the snapshot: the hand-over first (Constants.
## SNACK_HANDOVER_SECONDS on the server clock from the sale, so every peer sees
## it at once).
## The food is this node's from the start: it sits in Dot's hand as she reaches
## it out through the hatch (npcs/store_clerk.gd aims her arm at the buyer), or
## waits in the machine's tray after the snack clunks down; the buyer's hand
## goes out to meet it (CartoonBody.reach_at, and the first-person arms'
## reach_at for your own view), and for the last SNACK_PASS seconds it travels
## from the giver to that hand. It lands there at the size it was, and the
## same hand carries it straight on to the mouth: the body eats it (player/snack_gestures.gd
## "eat": three bites, a munch and a shrink on each, chewing between) or drinks
## it ("drink": the cup tips, the head goes back, a slurp and an "ahh"). Your
## own first-person arms bring the same food up into view (player/
## first_person_arms.gd reads the same gesture clock). Then the snack shows what
## it did: full, a pat on the belly; Turbo Juice, a full-body shudder; queasy,
## a burp.
##
## The food goes in the right hand, which lets go of whatever it held for the
## while (CartoonBody.hands_off; a rake stays in the left). If the right hand
## holds something on its own (the gas can, a sign, a ladder), the left hand
## takes the snack instead (the body's "snack_side" meta: snack_gestures.gd and
## the first-person arms mirror for it).
##
## While a buff runs, the body wears it, no words needed: Turbo has wide eyes
## and a buzz in the head; the crash yawns once, then heavy lids and a head
## that keeps nodding off; burnt coffee twitches an eye now and then; queasy
## goes green in the face. The HUD shows your own as icons (ui/buff_hud.gd).

const _ShopModels = preload("res://props/shop_models.gd")
const _SnackGestures = preload("res://player/snack_gestures.gd")
const _PropLooks = preload("res://props/prop_looks.gd")
## Where the food sits from the hand: a little in toward the mouth (body space).
const FOOD_OFFSET := Vector3(-0.02, 0.03, 0.03)
## The hot dog's and the sandwich's half length along Z, bitten from +Z.
const FOOD_HALF_LENGTH: float = 0.085
## Where the food sits from your own first-person right hand (head space).
const FP_FOOD_OFFSET := Vector3(-0.035, 0.045, -0.02)

var player: Node3D
var body: Node3D

## The snack being eaten: {item, buff, drink, wait, t, bites} ({} when not).
var _eating: Dictionary = {}
var _seen_at: float = -1.0
var _food: MeshInstance3D
var _fp_food: MeshInstance3D
## The food on its way to you during the hand-over (world space, seen by all).
var _pass: MeshInstance3D
var _shown_buffs: Dictionary = {}
var _twitch_in: float = 2.0
var _twitch_left: float = 0.0
var _time: float = 0.0
var _tinted: bool = false
var _green: float = 0.0
var _shops: Node
## The gestures and sounds this played, in order (tests and the probe read it).
var log_lines: Array[String] = []


func _ready() -> void:
	_SnackGestures.register()
	# A snack already in the snapshot when this body is made is old news.
	var shops := _shops_node()
	if shops != null and player != null:
		var snack: Dictionary = shops.call("snack_of", player.name.to_int())
		if not snack.is_empty():
			_seen_at = float(snack.get("at", -1.0))


## The snack in hand right now ("" for none), for tests.
func eating() -> String:
	return str(_eating.get("item", ""))


func _physics_process(delta: float) -> void:
	if player == null or body == null or not is_instance_valid(body):
		return
	_time += delta
	var shops := _shops_node()
	if shops == null:
		return
	var peer := player.name.to_int()
	var snack: Dictionary = shops.call("snack_of", peer)
	if not snack.is_empty() and float(snack.get("at", -1.0)) != _seen_at:
		_seen_at = float(snack.get("at", -1.0))
		var since := Net.server_time() - _seen_at
		if since < Constants.SNACK_SHOW_WINDOW:
			_start(snack, since)
	_step_eating(delta)
	_wear_buffs(delta, shops.call("buffs_left", peer) as Dictionary)


func _start(snack: Dictionary, since: float) -> void:
	_finish_food()
	_let_go()
	var item := str(snack.get("item", ""))
	var shop := str(Catalog.item(item).get("shop", ""))
	var handover := float(Constants.SNACK_HANDOVER_SECONDS.get(shop, 0.0))
	var side := _free_side()
	body.set_meta("snack_side", side)
	_eating = {
		"item": item, "buff": str(snack.get("buff", "")), "drink": _ShopModels.DRINKS.has(item),
		"shop": shop, "handover": handover, "side": side,
		"wait": maxf(handover - since, 0.0), "t": -1.0, "bites": 0, "sipped": false, "after": false,
		# Handed over (seen from the giver's hand on): it arrives full size. A
		# snapshot too late for any of that just has it come up from your side.
		"handed": false,
	}


## Which hand takes the snack: the right, unless it holds something the left
## doesn't (a one-handed hold), then the left.
func _free_side() -> int:
	var held := player.call("_held_prop") as Node3D if player.has_method("_held_prop") else null
	if held == null:
		return 1
	var grips := _PropLooks.grip_points(held, player)
	return 0 if grips[0].is_finite() and not grips[1].is_finite() else 1


## The body's hold and reach arrays are [right, left]; arm sides are 1 right, 0 left.
static func _rl(side: int) -> int:
	return 0 if side == 1 else 1


func _step_eating(delta: float) -> void:
	if _eating.is_empty():
		return
	var side := int(_eating["side"])
	if float(_eating["wait"]) > 0.0:
		_eating["wait"] = float(_eating["wait"]) - delta
		_step_handover(maxf(float(_eating["wait"]), 0.0))
		if float(_eating["wait"]) > 0.0:
			return
	var drink := bool(_eating["drink"])
	var gesture_name := "drink" if drink else "eat"
	var length := float(_SnackGestures.SECONDS[gesture_name])
	if float(_eating["t"]) < 0.0:
		_eating["t"] = 0.0
		body.call("gesture", gesture_name)
		_note("gesture " + gesture_name)
		_make_food(str(_eating["item"]), side)
		_free_pass()
	else:
		_eating["t"] = float(_eating["t"]) + delta
	var s := float(_eating["t"])
	# The hand that took it carries it on to the mouth: the reach hands over to
	# the gesture's lift as it rises, and the hold stays off till the hand's down.
	var reach := 1.0 - _SnackGestures.lift(s, length) if bool(_eating["handed"]) and s < _SnackGestures.RAISE_SECONDS else 0.0
	_set_reach(side, Vector3.INF if reach <= 0.0 else _reach_point(side), reach)
	(body.get("hands_off") as Array)[_rl(side)] = s < length
	# The bites and the sip happen on the gesture's own clock.
	if not drink:
		var bites: Array[float] = Constants.SNACK_EAT_BITES
		while int(_eating["bites"]) < bites.size() and s >= bites[int(_eating["bites"])]:
			_eating["bites"] = int(_eating["bites"]) + 1
			_sound("munch")
			_note("munch")
			# Chewing between bites.
			body.call("talk", 0.32)
	elif not bool(_eating["sipped"]) and s >= Constants.SNACK_DRINK_SIP.x:
		_eating["sipped"] = true
		_sound("slurp")
		_note("slurp")
	_place_food(s, length, drink)
	if s >= length and not bool(_eating["after"]):
		_eating["after"] = true
		_finish_food()
		_after(str(_eating["buff"]))
	if s >= length + 0.2:
		_eating = {}
		_let_go()


## The hand-over, left seconds before the food reaches your hand: it sits with
## the giver (Dot's hand, the tray), your hand goes out for it, and for the last
## SNACK_PASS seconds it comes across to you.
func _step_handover(left: float) -> void:
	var side := int(_eating["side"])
	var handover := float(_eating["handover"])
	var pass_spec: Vector2 = Constants.SNACK_PASS.get(str(_eating["shop"]), Vector2(0.25, 0.05))
	var from: Variant = _giver_point()
	if from == null:
		# Nobody to hand it over here: it comes up from your side as you eat.
		return
	if not bool(_eating["handed"]):
		if left < pass_spec.x or left > handover:
			# Heard of too late to see it come across.
			return
		_eating["handed"] = true
	(body.get("hands_off") as Array)[_rl(side)] = left < Constants.SNACK_REACH_SECONDS
	var reach := clampf(1.0 - left / Constants.SNACK_REACH_SECONDS, 0.0, 1.0)
	_set_reach(side, from as Vector3, reach)
	if _pass == null or not is_instance_valid(_pass):
		_pass = _ShopModels.food(str(_eating["item"]))
		_pass.name = "SnackPass"
		_pass.top_level = true
		add_child(_pass)
	var facing := body.global_basis.orthonormalized()
	var at: Vector3 = from
	var basis := facing.rotated(Vector3.UP, PI)
	var giver := _giver()
	if giver != null:
		basis = (giver as Node3D).global_basis.orthonormalized()
		if str(_eating["shop"]) == "snak_o_matic":
			basis = basis.rotated(Vector3.UP, PI)
	var size := 1.0
	# The machine's snack waits behind the flap till it hops out.
	var hidden := str(_eating["shop"]) == "snak_o_matic" and left > pass_spec.x
	if left <= pass_spec.x:
		var u := 1.0 - left / maxf(pass_spec.x, 0.01)
		var eased := u * u * (3.0 - 2.0 * u)
		at = (from as Vector3).lerp(_receive_point(side), eased) + Vector3.UP * pass_spec.y * sin(PI * u)
		basis = basis.slerp(facing, eased)
		if str(_eating["shop"]) == "snak_o_matic":
			# Out of the flap: it grows from the dark as it comes out.
			size = lerpf(0.55, 1.0, clampf(u / 0.35, 0.0, 1.0))
	_pass.global_transform = Transform3D(basis.scaled(Vector3.ONE * size), at)
	_pass.visible = not hidden

## The shop handing it over: Dot's keeper node, or the vending machine (null: none here).
func _giver() -> Node:
	match str(_eating.get("shop", "")):
		"lunch_money":
			for node: Node in get_tree().get_nodes_in_group("shopkeepers"):
				if str(node.get("shop_id")) == "lunch_money" and node.has_method("hand_point") and (node as Node3D).visible:
					return node
		"snak_o_matic":
			return get_tree().get_first_node_in_group("vending_machines")
	return null


## Where the food is with the giver: in Dot's hand, or the machine's tray (world).
func _giver_point() -> Variant:
	var giver := _giver()
	if giver == null:
		return null
	return giver.call("hand_point") if giver.has_method("hand_point") else giver.call("tray_point")


## Where your hand reaches for: the giver's point while it's there.
func _reach_point(side: int) -> Vector3:
	var from: Variant = _giver_point()
	return from as Vector3 if from != null else _receive_point(side)


## Where the food sits in the hand that takes it (world): your own first-person
## hand when it's you looking, else this body's hand.
func _receive_point(side: int) -> Vector3:
	var arms := _fp_arms()
	if arms != null and arms.visible:
		return arms.to_global((arms.call("hand_point", side) as Vector3) + _mirrored(FP_FOOD_OFFSET, side))
	var hand := body.call("pose_part", "prop_hand" if side == 1 else "prop_hand_l") as Node3D
	if hand == null:
		return player.global_position + Vector3.UP * 1.1
	return hand.global_position + body.global_basis.orthonormalized() * _mirrored(FOOD_OFFSET, side)


## Both the body's reach and your first-person arms' for this hand.
func _set_reach(side: int, point: Vector3, weight: float) -> void:
	var rl := _rl(side)
	(body.get("reach_at") as Array)[rl] = point
	(body.get("reach_weight") as Array)[rl] = weight if point.is_finite() else 0.0
	var arms := _fp_arms()
	if arms != null:
		arms.set("reach_side", side)
		arms.set("reach_at", point)
		arms.set("reach_weight", weight if point.is_finite() else 0.0)


## Hands back as they were: no reach, holds back on.
func _let_go() -> void:
	if body == null or not is_instance_valid(body):
		return
	for side: int in 2:
		_set_reach(side, Vector3.INF, 0.0)
		(body.get("hands_off") as Array)[_rl(side)] = false
	_free_pass()


func _free_pass() -> void:
	if _pass != null and is_instance_valid(_pass):
		_pass.queue_free()
	_pass = null


## An offset for the right hand, mirrored for the left.
static func _mirrored(offset: Vector3, side: int) -> Vector3:
	return offset if side == 1 else Vector3(-offset.x, offset.y, offset.z)


## What the snack did, played as soon as it's down.
func _after(buff_id: String) -> void:
	match buff_id:
		"full":
			body.call("gesture", "belly_pat")
			_note("gesture belly_pat")
		"turbo":
			body.call("gesture", "turbo_shake")
			_note("gesture turbo_shake")
		"queasy":
			body.call("gesture", "burp")
			_say("vo_burp")
			_note("burp")


func _make_food(item: String, side: int) -> void:
	var hand := body.call("pose_part", "prop_hand" if side == 1 else "prop_hand_l") as Node3D
	if hand != null:
		_food = _ShopModels.food(item)
		_food.name = "Snack"
		hand.add_child(_food)
		# Your own body's copy stays out of your own first-person view.
		body.call("_on_head_layer", _food)
	var arms := _fp_arms()
	if arms != null:
		_fp_food = _ShopModels.food(item)
		_fp_food.name = "SnackFP"
		_fp_food.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		arms.add_child(_fp_food)


## Holds the food in the hand, facing the mouth: bitten down from the mouth's
## end, or tipped to the lips.
func _place_food(s: float, length: float, drink: bool) -> void:
	var remain := 1.0
	if not drink:
		remain = 1.0 - float(_eating["bites"]) / float(Constants.SNACK_EAT_BITES.size())
	var tip := _SnackGestures.sip_tip(s) if drink else 0.0
	var up := _SnackGestures.lift(s, length)
	var side := int(_eating["side"])
	# Handed over, it's in the hand full size from the start. Otherwise it comes
	# into the hand as it leaves the side. A drink, done, goes as it gets back there.
	var grown := 1.0 if bool(_eating["handed"]) else clampf(up / 0.2, 0.0, 1.0)
	if drink and s >= length * 0.5:
		grown = clampf(up / 0.15, 0.0, 1.0)
	var bitten := Basis.IDENTITY.scaled(Vector3(1.0, 1.0, maxf(remain, 0.001)))
	var tipped := Basis(Vector3.RIGHT, tip * 1.7)
	var shape := (tipped if drink else bitten).scaled(Vector3.ONE * grown)
	var shift := Vector3.ZERO if drink else Vector3(0.0, 0.0, -FOOD_HALF_LENGTH * (1.0 - remain))
	if _food != null and is_instance_valid(_food):
		var hand := _food.get_parent() as Node3D
		var facing := body.global_basis.orthonormalized()
		_food.global_transform = Transform3D(facing * shape, hand.global_position + facing * (_mirrored(FOOD_OFFSET, side) + shift))
		_food.visible = remain > 0.0
	if _fp_food != null and is_instance_valid(_fp_food):
		var arms := _fp_food.get_parent() as Node3D
		# The arms put it on the hand after they move it (first_person_arms.gd).
		_fp_food.set_meta("from_hand", Transform3D(shape, _mirrored(FP_FOOD_OFFSET, side) + shift))
		# On the hand now too, so the frame it's made in it's already there.
		_fp_food.transform = Transform3D(shape, (arms.call("hand_point", side) as Vector3) + _mirrored(FP_FOOD_OFFSET, side) + shift)
		_fp_food.visible = remain > 0.0 and arms.visible


func _finish_food() -> void:
	for food: MeshInstance3D in [_food, _fp_food]:
		if food != null and is_instance_valid(food):
			food.queue_free()
	_food = null
	_fp_food = null


## The buffs this player has on: a look for each, and a yawn as the crash hits.
func _wear_buffs(delta: float, running: Dictionary) -> void:
	for buff_id: Variant in running:
		if not _shown_buffs.has(buff_id) and str(buff_id) == "crash":
			var seconds := float((Constants.BUFFS["crash"] as Dictionary)["seconds"])
			# Only a crash that just hit gets the yawn (not one already running on join).
			if seconds - float(running[buff_id]) < Constants.SNACK_SHOW_WINDOW:
				body.call("gesture", "stretch")
				_say("vo_yawn")
				_note("yawn")
	_shown_buffs = running
	var eyes: Array[Node3D] = []
	for part: String in ["eye_l", "eye_r"]:
		var eye := body.call("pose_part", part) as Node3D
		if eye != null:
			eyes.append(eye)
	var face := body.call("pose_part", "face") as Node3D
	if running.has("turbo"):
		# Wide eyes (not mid-blink) and a buzz in the head.
		for eye: Node3D in eyes:
			if eye.scale.y > 0.5:
				eye.scale.y = maxf(eye.scale.y, Constants.BUFF_TURBO_EYES)
		if face != null:
			face.position += Vector3(sin(_time * 71.0), cos(_time * 83.0), 0.0) * Constants.BUFF_TURBO_JITTER
	if running.has("crash"):
		# Heavy lids, and the head nodding off and jerking back up.
		for eye: Node3D in eyes:
			eye.scale.y = minf(eye.scale.y, Constants.BUFF_CRASH_EYES)
		if face != null:
			var drift := fposmod(_time, 2.6) / 2.6
			face.rotation.x -= Constants.BUFF_CRASH_NOD * drift * drift
	if running.has("coffee"):
		_twitch_in -= delta
		if _twitch_in <= 0.0:
			_twitch_in = randf_range(Constants.BUFF_COFFEE_TWITCH.x, Constants.BUFF_COFFEE_TWITCH.y)
			_twitch_left = 0.14
		if _twitch_left > 0.0:
			_twitch_left -= delta
			if eyes.size() > 1:
				eyes[1].scale.y = 0.35
	_queasy_face(running.has("queasy"), delta)


## Green in the face while queasy, coming on once the sandwich is down and
## draining away as it passes (the head only, and never over paint or water:
## those coat the whole body and win).
func _queasy_face(queasy: bool, delta: float) -> void:
	var coated := int(player.get("coat")) != 0 if "coat" in player else false
	var want := 1.0 if queasy and _eating.is_empty() and not coated else 0.0
	if want == _green and not _tinted:
		return
	_green = move_toward(_green, want, delta / Constants.BUFF_QUEASY_FADE_SECONDS)
	if coated:
		_tinted = false
		return
	var face := body.call("pose_part", "face") as Node3D
	if face == null:
		return
	for child: Node in face.get_children():
		var mesh := child as MeshInstance3D
		if mesh != null:
			var tint := Constants.BUFF_QUEASY_TINT
			tint.a *= _green
			mesh.set_instance_shader_parameter("tint", tint)
			# The head is the first mesh; the eyes and hat keep their colors.
			break
	_tinted = _green > 0.0

func _sound(id: String) -> void:
	var sfx := get_tree().get_first_node_in_group("sfx") if is_inside_tree() else null
	if sfx == null:
		return
	var mouth := body.call("pose_part", "mouth") as Node3D
	var at := mouth.global_position if mouth != null else player.global_position + Vector3.UP * 1.5
	sfx.call("play_at", id, at)


func _say(id: String) -> void:
	if player.has_method("say"):
		player.call("say", id)


func _note(what: String) -> void:
	log_lines.append(what)
	if log_lines.size() > 32:
		log_lines.remove_at(0)


func _fp_arms() -> Node3D:
	if not player.is_multiplayer_authority():
		return null
	var arms := player.get_node_or_null("%Head/Arms") as Node3D
	return arms if arms != null and arms.has_method("hand_point") else null


func _shops_node() -> Node:
	if _shops == null or not is_instance_valid(_shops):
		_shops = get_tree().get_first_node_in_group("shops") if is_inside_tree() else null
	return _shops
