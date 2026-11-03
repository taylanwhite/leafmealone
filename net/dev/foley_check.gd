extends RefCounted

## --audio-test's foley check (gap audio chunk 6; docs/GAME.md "Foley: what the
## crew sounds like"), run on the lot by net/dev/audio_test.gd. Headless runs
## make no players, but every play lands in Sfx.log and Sfx.placed, which is
## what this reads. Stand-in bodies and props (the inner classes below) carry
## the replicated fields the foley nodes watch, so each rule is driven exactly:
##   steps         a footstep where each foot comes down (the stride crossing a
##                 contact), never two closer than FOLEY_STEP_MIN_SECONDS, hushed
##                 crouched, a teammate's under your own, none in the air, carried,
##                 or shuffling under FOLEY_STEP_MIN_SPEED
##   body          paint_splat, splash, grab_yoink, throw_big, foot_pop, the wind-up's
##                 loop and land_thump, each where it happened; a body that arrives
##                 already painted makes no sound
##   props         ladder_clack at its top, ladder_crash when a knocked-over one stops
##                 tumbling (none when taken down by hand), hose_click, bag_plop,
##                 pickup_heavy off the ground (into hands, or pocketed and drawn in
##                 one tick, the hotbar's way) but nothing out of a pocket, a sign's
##                 first pull and then an ordinary pickup
##   task_sounds   task_looks.work_fx plays its TASK_SOUNDS id at the spot, held to
##                 its gap per patch; the mower's borrowed bursts and the mower's
##                 own task are silent
##   ambience      night, crickets by the hour, and who hears an owl, the PA, a
##                 cart and a neighbor's mower (audio/ambience.gd wants)
##   say_routing   a non-voice id from player.say rides the head through Sfx (the
##                 horn); H off a ride doesn't honk
##   live_foley    every player in the session has its Foley node

const _SfxScript = preload("res://audio/sfx.gd")
const _PlayerFoley = preload("res://audio/player_foley.gd")
const _PropFoley = preload("res://audio/prop_foley.gd")
const _Ambience = preload("res://audio/ambience.gd")
const _Bank = preload("res://audio/sound_bank.gd")
const STEP_IDS: Array[String] = ["step", "step_hard", "step_grass", "step_leaves", "step_leaves_deep", "step_leaves_pile"]
## A fake peer id for the stand-in body (never a real one).
const STUB_PEER: int = 424242


class StubBody extends Node3D:
	var _phase: float = 0.0
	var _speed: float = 4.0
	var _sit_pose: int = 0
	var _in_air: bool = false


class StubPlayer extends CharacterBody3D:
	var anim_state: int = 1
	var coat: int = 0
	var carried_by: int = 0
	var thrown: bool = false
	var foot_hurt: int = 0
	var winding: bool = false
	var _ride: Node3D = null

	func is_body_drawn() -> bool:
		return true

	func is_hidden() -> bool:
		return false

	func is_riding_visual() -> bool:
		return false

	func is_staged() -> bool:
		return false

	func is_sleeping() -> bool:
		return false

	func is_climbing() -> bool:
		return false

	func pockets() -> Node:
		return null


class StubProp extends Node3D:
	var kind: String = "ladder"
	var ladder_top := Vector3.ZERO
	var hose_source: String = ""
	var stored_bags: int = 0
	var held_by: int = 0
	var pocketed_by: int = 0
	var tier: String = "heavy"

	func weight_tier() -> String:
		return tier


static func run(test: Node) -> Dictionary:
	var checks := {}
	var tree := test.get_tree()
	var world := tree.get_first_node_in_group("world") as Node3D
	var me := _me(tree)
	if world == null or me == null:
		return {"world": false}
	var at := me.global_position + Vector3(3.0, 0.0, 3.0)
	checks["steps"] = await _steps(tree, world, at)
	checks["body"] = await _body(tree, world, at)
	checks["props"] = await _props(tree, world, at + Vector3(0.0, 0.0, 3.0))
	checks["task_sounds"] = _task_sounds(tree, at)
	checks["ambience"] = _ambience()
	checks["say_routing"] = await _say_routing(tree, me)
	var players := tree.get_nodes_in_group("players")
	var with_foley := 0
	for node: Node in players:
		if node.get_node_or_null("Visual/CartoonBody/Foley") != null:
			with_foley += 1
	print("[AudioTest] foley: %d of %d players have their Foley" % [with_foley, players.size()])
	checks["live_foley"] = players.size() > 0 and with_foley == players.size()
	return checks


static func _stub_player(world: Node3D, at: Vector3, coat := 0) -> Array:
	var player := StubPlayer.new()
	player.name = str(STUB_PEER)
	player.coat = coat
	var visual := Node3D.new()
	visual.name = "Visual"
	player.add_child(visual)
	var body := StubBody.new()
	body.name = "CartoonBody"
	visual.add_child(body)
	var foley := _PlayerFoley.new()
	foley.name = "Foley"
	foley.player = player
	foley.body = body
	body.add_child(foley)
	world.add_child(player)
	player.global_position = at
	return [player, body]


static func _wait(tree: SceneTree, seconds: float) -> void:
	await tree.create_timer(seconds).timeout
	await tree.physics_frame


static func _stub_steps() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in _PlayerFoley.steps:
		if int(entry["peer"]) == STUB_PEER:
			out.append(entry)
	return out


## One foot down: the stride moved on past the next contact.
static func _stride(body: StubBody) -> void:
	body._phase = (floorf((body._phase - PI * 0.5) / PI) + 1.0) * PI + PI * 0.5 + 0.1


static func _steps(tree: SceneTree, world: Node3D, at: Vector3) -> bool:
	var made := _stub_player(world, at)
	var player: StubPlayer = made[0]
	var body: StubBody = made[1]
	_PlayerFoley.steps.clear()
	await _wait(tree, 0.05)
	for _step: int in 4:
		_stride(body)
		await _wait(tree, Constants.FOLEY_STEP_MIN_SECONDS + 0.05)
	var walked := _stub_steps().size()
	# Two feet down inside FOLEY_STEP_MIN_SECONDS: only the first sounds.
	_stride(body)
	await tree.physics_frame
	_stride(body)
	await _wait(tree, Constants.FOLEY_STEP_MIN_SECONDS + 0.05)
	var quick := _stub_steps().size() - walked
	player.anim_state = _PlayerFoley.ANIM_CROUCH
	_stride(body)
	await _wait(tree, Constants.FOLEY_STEP_MIN_SECONDS + 0.05)
	var crouched := _stub_steps().back() as Dictionary if _stub_steps().size() == walked + quick + 1 else {}
	player.anim_state = 1
	var heard := _stub_steps().size()
	body._speed = Constants.FOLEY_STEP_MIN_SPEED * 0.5
	_stride(body)
	await _wait(tree, Constants.FOLEY_STEP_MIN_SECONDS + 0.05)
	body._speed = 4.0
	player.anim_state = _PlayerFoley.ANIM_AIR
	_stride(body)
	await _wait(tree, Constants.FOLEY_STEP_MIN_SECONDS + 0.05)
	player.anim_state = 1
	player.carried_by = 7
	_stride(body)
	await _wait(tree, Constants.FOLEY_STEP_MIN_SECONDS + 0.05)
	player.carried_by = 0
	var silent := _stub_steps().size() == heard
	# A teammate's feet, under your own.
	player.set_multiplayer_authority(STUB_PEER + 1)
	_stride(body)
	await _wait(tree, Constants.FOLEY_STEP_MIN_SECONDS + 0.05)
	var other := _stub_steps().back() as Dictionary if _stub_steps().size() == heard + 1 else {}
	var ids_ok := true
	for entry: Dictionary in _stub_steps():
		ids_ok = ids_ok and STEP_IDS.has(str(entry["id"]))
	var placed_ok := false
	for id: String in STEP_IDS:
		placed_ok = placed_ok or _placed_near(id, body.global_position, 0.2)
	player.queue_free()
	var crouch_ok := not crouched.is_empty() and is_equal_approx(float(crouched["db"]), Constants.FOLEY_STEP_DB + Constants.FOLEY_STEP_CROUCH_DB)
	var other_ok := not other.is_empty() and is_equal_approx(float(other["db"]), Constants.FOLEY_STEP_DB + Constants.FOLEY_STEP_OTHER_DB)
	print("[AudioTest] foley steps: walked %d of 4, quick feet %d of 2, crouched %s, silent shuffling/in the air/carried %s, a teammate's %s, ids %s, placed at the feet %s" % [walked, quick, crouched, silent, other, ids_ok, placed_ok])
	return walked == 4 and quick == 1 and crouch_ok and silent and other_ok and ids_ok and placed_ok


static func _body(tree: SceneTree, world: Node3D, at: Vector3) -> bool:
	# Arriving already painted (a late join) says nothing.
	var late := _stub_player(world, at + Vector3(2.0, 0.0, 0.0), 1)
	var splats_before := _SfxScript.log.count("paint_splat")
	await _wait(tree, 0.1)
	var late_quiet := _SfxScript.log.count("paint_splat") == splats_before
	(late[0] as Node).queue_free()
	var made := _stub_player(world, at)
	var player: StubPlayer = made[0]
	var body: StubBody = made[1]
	await _wait(tree, 0.05)
	var chest := body.global_position + Vector3.UP * 1.1
	var heard := {}
	player.coat = 1
	await _wait(tree, 0.05)
	heard["paint_splat"] = _placed_near("paint_splat", chest, 0.05)
	player.coat = 2
	await _wait(tree, 0.05)
	heard["splash"] = _placed_near("splash", chest, 0.05)
	player.coat = 0
	player.carried_by = 3
	await _wait(tree, 0.05)
	heard["grab_yoink"] = _placed_near("grab_yoink", chest, 0.05)
	player.carried_by = 0
	player.thrown = true
	await _wait(tree, 0.05)
	heard["throw_big"] = _placed_near("throw_big", chest, 0.05)
	# Thrown, the body flies knocked flat: it thumps the tick its fall stops.
	var thrown_thumps := _SfxScript.log.count("land_thump")
	player.velocity = Vector3(0.0, -5.0, 0.0)
	await _wait(tree, 0.1)
	player.velocity = Vector3.ZERO
	await _wait(tree, 0.05)
	heard["thrown_lands"] = _SfxScript.log.count("land_thump") == thrown_thumps + 1
	player.thrown = false
	await _wait(tree, Constants.SFX_DEFAULT_GAP_MS / 1000.0)
	player.foot_hurt = 2
	await _wait(tree, 0.05)
	heard["foot_pop"] = not _placed("foot_pop").is_empty()
	var windups := _SfxScript.log.count("punch_windup")
	player.winding = true
	await _wait(tree, 0.05)
	heard["punch_windup"] = _SfxScript.log.count("punch_windup") == windups + 1
	player.winding = false
	var thumps := _SfxScript.log.count("land_thump")
	player.anim_state = _PlayerFoley.ANIM_AIR
	player.velocity = Vector3(0.0, -(Constants.LAND_THUMP_SPEED + 3.0), 0.0)
	await _wait(tree, 0.3)
	player.anim_state = 1
	player.velocity = Vector3.ZERO
	await _wait(tree, 0.05)
	heard["land_thump"] = _SfxScript.log.count("land_thump") == thumps + 1
	# A hop (falling slowly) doesn't thump.
	player.anim_state = _PlayerFoley.ANIM_AIR
	player.velocity = Vector3(0.0, -2.0, 0.0)
	await _wait(tree, 0.3)
	player.anim_state = 1
	player.velocity = Vector3.ZERO
	await _wait(tree, 0.05)
	heard["hop_quiet"] = _SfxScript.log.count("land_thump") == thumps + 1
	player.queue_free()
	var ok := late_quiet
	for key: String in heard:
		ok = ok and bool(heard[key])
	print("[AudioTest] foley body: late join quiet %s, %s" % [late_quiet, heard])
	return ok


static func _stub_prop(world: Node3D, at: Vector3, kind: String) -> StubProp:
	var prop := StubProp.new()
	prop.kind = kind
	var foley := _PropFoley.new()
	foley.name = "PropFoley"
	foley.prop = prop
	prop.add_child(foley)
	world.add_child(prop)
	prop.global_position = at
	return prop


static func _props(tree: SceneTree, world: Node3D, at: Vector3) -> bool:
	var heard := {}
	var ladder := _stub_prop(world, at, "ladder")
	await _wait(tree, 0.05)
	var top := at + Vector3(0.0, 3.5, -1.0)
	ladder.ladder_top = top
	await _wait(tree, 0.05)
	heard["ladder_clack"] = _placed_near("ladder_clack", top, 0.05)
	# Knocked over: it tumbles for a while, then lies still.
	var crashes := _SfxScript.log.count("ladder_crash")
	ladder.ladder_top = Vector3.ZERO
	for _tick: int in 12:
		ladder.rotation.x += 0.12
		await tree.create_timer(0.03).timeout
	var early := _SfxScript.log.count("ladder_crash") != crashes
	await _wait(tree, 0.4)
	heard["ladder_crash"] = not early and _SfxScript.log.count("ladder_crash") == crashes + 1
	# Taken down by hand: no crash.
	ladder.ladder_top = top
	await _wait(tree, 0.25)
	ladder.held_by = 1
	ladder.ladder_top = Vector3.ZERO
	await _wait(tree, Constants.SFX_DEFAULT_GAP_MS / 1000.0 + 1.2)
	heard["ladder_by_hand_quiet"] = _SfxScript.log.count("ladder_crash") == crashes + 1
	ladder.queue_free()
	var hose := _stub_prop(world, at + Vector3(1.0, 0.0, 0.0), "hose")
	var barrow := _stub_prop(world, at + Vector3(2.0, 0.0, 0.0), "wheelbarrow")
	await _wait(tree, 0.05)
	hose.hose_source = "spigot"
	barrow.stored_bags = 1
	barrow.held_by = 1
	await _wait(tree, 0.05)
	heard["hose_click"] = not _placed("hose_click").is_empty()
	heard["bag_plop"] = not _placed("bag_plop").is_empty()
	heard["pickup_heavy"] = not _placed("pickup_heavy").is_empty()
	# Out of a pocket is the hotbar's draw, never a pickup.
	hose.pocketed_by = 1
	await _wait(tree, 0.2)
	var pickups := _SfxScript.log.count("pickup_light") + _SfxScript.log.count("pickup_heavy")
	hose.pocketed_by = 0
	hose.held_by = 1
	await _wait(tree, 0.2)
	heard["draw_quiet"] = _SfxScript.log.count("pickup_light") + _SfxScript.log.count("pickup_heavy") == pickups
	hose.queue_free()
	# Off the ground the hotbar's way: pocketed, then drawn, in one tick. Heard once.
	var can := _stub_prop(world, at + Vector3(1.5, 0.0, 1.0), "gas_can")
	await _wait(tree, 0.05)
	var heavies := _SfxScript.log.count("pickup_heavy")
	can.pocketed_by = 1
	can.pocketed_by = 0
	can.held_by = 1
	await _wait(tree, 0.2)
	heard["pocket_pickup"] = _SfxScript.log.count("pickup_heavy") == heavies + 1
	can.queue_free()
	barrow.queue_free()
	# A TurfMasters sign: its first pull out of the lawn, then just a sign.
	var sign_prop := _stub_prop(world, at + Vector3(3.0, 0.0, 0.0), "turf_sign")
	sign_prop.tier = "light"
	await _wait(tree, 0.05)
	var pulls := _SfxScript.log.count("sign_pull")
	var lights := _SfxScript.log.count("pickup_light")
	sign_prop.held_by = 1
	await _wait(tree, 0.2)
	sign_prop.held_by = 0
	await _wait(tree, 0.05)
	sign_prop.held_by = 1
	await _wait(tree, 0.05)
	heard["sign_pull"] = _SfxScript.log.count("sign_pull") == pulls + 1 and _SfxScript.log.count("pickup_light") == lights + 1
	sign_prop.queue_free()
	var ok := true
	for key: String in heard:
		ok = ok and bool(heard[key])
	print("[AudioTest] foley props: %s" % heard)
	return ok


static func _task_sounds(tree: SceneTree, at: Vector3) -> bool:
	var looks := tree.get_first_node_in_group("task_looks")
	var own: Node = null
	# A lot without a job has no task looks: a bare one does for work_fx.
	if looks == null:
		own = preload("res://levels/lots/task_looks.gd").new()
		tree.get_first_node_in_group("world").add_child(own)
		looks = own
	var spot := at + Vector3(10.0, 0.5, 10.0)
	var before := _SfxScript.log.count("litter_crinkle")
	looks.call("work_fx", "pick_litter", spot)
	var played := _SfxScript.log.count("litter_crinkle") == before + 1 and _placed_near("litter_crinkle", spot, 0.05)
	looks.call("work_fx", "pick_litter", spot + Vector3(0.3, 0.0, 0.0))
	var held := _SfxScript.log.count("litter_crinkle") == before + 1
	looks.call("work_fx", "pick_litter", spot + Vector3(6.0, 0.0, 0.0), false)
	var mower_quiet := _SfxScript.log.count("litter_crinkle") == before + 1
	var all_before := _SfxScript.log.size()
	var last_before: String = _SfxScript.log.back() if not _SfxScript.log.is_empty() else ""
	looks.call("work_fx", "mow_lawn", spot + Vector3(-6.0, 0.0, 0.0))
	var mow_quiet: bool = (_SfxScript.log.back() if not _SfxScript.log.is_empty() else "") == last_before and _SfxScript.log.size() <= all_before
	var mapped := true
	var sounds: Dictionary = preload("res://levels/lots/task_looks.gd").TASK_SOUNDS
	for task: String in sounds:
		mapped = mapped and _Bank.has(str(sounds[task]))
	if own != null:
		own.queue_free()
	print("[AudioTest] foley task sounds: plays %s, held to its gap %s, borrowed bursts quiet %s, the mower quiet %s, every id registered %s" % [played, held, mower_quiet, mow_quiet, mapped])
	return played and held and mower_quiet and mow_quiet and mapped


static func _ambience() -> bool:
	var night := Constants.AMBIENCE_NIGHT_FROM_HOUR
	var cases := {
		"no owl by day": not _Ambience.wants("owl", Net.Zone.LOT, 12.0, true, true),
		"owl at night in the hood": _Ambience.wants("owl", Net.Zone.LOT, night + 1.0, false, true),
		"owl at night by the store": _Ambience.wants("owl", Net.Zone.STORE, night + 1.0, false, false),
		"no owl at the Annex": not _Ambience.wants("owl", Net.Zone.BORDER, night + 1.0, false, false),
		"PA while open": _Ambience.wants("pa_chime", Net.Zone.STORE, 10.0, true, false),
		"no PA closed": not _Ambience.wants("pa_chime", Net.Zone.STORE, 23.0, false, false),
		"no PA on the yard": not _Ambience.wants("pa_chime", Net.Zone.LOT, 10.0, true, true),
		"carts by day": _Ambience.wants("cart_rattle", Net.Zone.STORE, 10.0, true, false),
		"no carts at night": not _Ambience.wants("cart_rattle", Net.Zone.STORE, night + 1.0, true, false),
		"a mower by day": _Ambience.wants("distant_mower", Net.Zone.LOT, 10.0, true, true),
		"no mower after hours": not _Ambience.wants("distant_mower", Net.Zone.LOT, Constants.AMBIENCE_MOWER_UNTIL_HOUR + 0.1, true, true),
		"birds by day": _Ambience.wants("bird", Net.Zone.LOT, 10.0, true, true),
		"no birds at night": not _Ambience.wants("bird", Net.Zone.LOT, night + 0.1, true, true),
		"crickets off by day": _Ambience.crickets_db(12.0) <= -79.0,
		"crickets fading in": _Ambience.crickets_db(night + Constants.AMBIENCE_NIGHT_FADE_HOURS * 0.5) > -79.0 and _Ambience.crickets_db(night + Constants.AMBIENCE_NIGHT_FADE_HOURS * 0.5) < Constants.AMBIENCE_CRICKETS_DB,
		"crickets full": is_equal_approx(_Ambience.crickets_db(night + Constants.AMBIENCE_NIGHT_FADE_HOURS + 0.1), Constants.AMBIENCE_CRICKETS_DB),
	}
	var failed: Array[String] = []
	for key: String in cases:
		if not bool(cases[key]):
			failed.append(key)
	print("[AudioTest] foley ambience: %d cases, failed %s" % [cases.size(), failed])
	return failed.is_empty()


static func _say_routing(tree: SceneTree, me: Node3D) -> bool:
	var horns := _SfxScript.log.count("truck_horn")
	me.call("say", "truck_horn")
	var entry := _placed("truck_horn")
	var head := me.get_node_or_null("Visual/Head")
	var rides_head: bool = head != null and not entry.is_empty() and entry["kind"] == "on" and entry["node"] == str(head.get_path())
	var routed := _SfxScript.log.count("truck_horn") == horns + 1 and rides_head
	await tree.create_timer(Constants.SFX_DEFAULT_GAP_MS / 1000.0 + 0.05).timeout
	var off_ride := not bool(me.call("_honk"))
	print("[AudioTest] foley say routing: the horn rides the head %s, H off a ride passes %s" % [routed, off_ride])
	return routed and off_ride


static func _placed(id: String) -> Dictionary:
	for index: int in range(_SfxScript.placed.size() - 1, -1, -1):
		var entry: Dictionary = _SfxScript.placed[index]
		if entry["id"] == id:
			return entry
	return {}


static func _placed_near(id: String, where: Vector3, slack: float) -> bool:
	var entry := _placed(id)
	return not entry.is_empty() and entry["kind"] == "at" and (entry["at"] as Vector3).distance_to(where) < slack


static func _me(tree: SceneTree) -> Node3D:
	for node: Node in tree.get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as Node3D
	return null
