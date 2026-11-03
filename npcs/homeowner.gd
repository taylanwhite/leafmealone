extends Node3D

## Authority: host decides the mood and the pay. Every peer plays the scene.
## The homeowner waits by the truck (Taylan, 2026-10-19, docs/GAME.md). Talk to
## them when you're done: they react to how clean the yard is, how long you took,
## and a little randomness, with a caption over their head, a goofy noise, and
## body language to match (the line: a bill they're owed, else usually their own
## personality's, Strings.homeowner_pool). Then they hold out the cash, and whoever grabs it
## settles the job: the crew is paid the bags' value times the mood's multiplier
## (Constants.HOMEOWNER_PAY_BY_MOOD), split by contribution, and Chefty heads home.
## Lives in the lot scene, so every peer has it at the same path.

enum Phase { WAITING, REACTING, OFFERING, PAID }

const _Strings = preload("res://ui/strings.gd")
const _CartoonBody = preload("res://player/cartoon_body.gd")
const _CharacterLife = preload("res://player/character_life.gd")
const _LowPoly = preload("res://props/low_poly.gd")
const _MoneyPopup = preload("res://ui/money_popup.gd")
const _Economy = preload("res://core/economy.gd")
## How close you must be to talk or take the cash, in meters.
const TALK_REACH: float = 2.8
## How long they react before holding out the cash.
const REACT_SECONDS: float = 2.6
const CAPTION_SECONDS: float = 8.0
## The caption's size on screen at the normal caption size; Settings'
## caption_scale() multiplies it, like the store clerk's (presentation).
const CAPTION_PIXEL_SIZE: float = 0.0011
## Gesture, sound, and face for each mood.
const STAGING: Dictionary = {
	"thrilled": {"gesture": "cheer", "sound": "vo_ah", "mood": "raised"},
	"happy": {"gesture": "wave", "sound": "babble", "mood": "raised"},
	"fine": {"gesture": "shuffle", "sound": "babble", "mood": "neutral"},
	"slow": {"gesture": "watch", "sound": "vo_huh", "mood": "angry"},
	"messy": {"gesture": "look_around", "sound": "vo_eh", "mood": "angry"},
	"nothing": {"gesture": "scratch", "sound": "vo_huh", "mood": "worried"},
}

var _phase: int = Phase.WAITING
var _amount: int = 0
var _body: Node3D
var _caption: Label3D
var _caption_left: float = 0.0
var _voice: AudioStreamPlayer3D
var _cash: Node3D
var _cash_label: Label3D
var _rng := RandomNumberGenerator.new()
## Host: how this job is being settled, for the payout receipt.
var _settlement: Dictionary = {}


func _ready() -> void:
	add_to_group("prompt_sources")
	add_to_group("homeowner")
	_rng.randomize()
	_body = _CartoonBody.new()
	_body.name = "CartoonBody"
	# A different homeowner for every job's yard (levels/lots/job_lot.gd).
	var job_seed := int(get_parent().get("job_seed")) if get_parent() != null and "job_seed" in get_parent() else 0
	_body.call("dress_from_seed", job_seed if job_seed != 0 else Campaign.current_lot_index() * 7919 + 3)
	add_child(_body)
	_body.call("build")
	var life := _CharacterLife.new()
	life.name = "Life"
	life.root = self
	life.body = _body
	life.role = "clerk"
	_body.add_child(life)
	var tag := Label3D.new()
	_tag = tag
	tag.text = _client_name()
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 36
	tag.outline_size = 8
	tag.position.y = 2.2
	add_child(tag)
	# The interact pill keeps clear of their name and lines (ui/interaction_prompt.gd).
	tag.add_to_group("prompt_avoid")
	_caption = Label3D.new()
	_caption.name = "Caption"
	_caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# The same size on screen however close you stand: you talk to them up close.
	_caption.fixed_size = true
	_caption.pixel_size = CAPTION_PIXEL_SIZE
	_caption.font_size = 30
	_caption.outline_size = 10
	_caption.width = 520.0
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_caption.position.y = 2.25
	_caption.modulate = Color(1.0, 0.97, 0.85)
	_caption.no_depth_test = true
	_caption.visible = false
	add_child(_caption)
	_caption.add_to_group("prompt_avoid")
	_voice = AudioStreamPlayer3D.new()
	_voice.position.y = 1.6
	_voice.unit_size = 4.0
	_voice.bus = preload("res://audio/sound_bank.gd").bus("babble")
	add_child(_voice)
	_build_cash()
	if not Net.is_host() and multiplayer.multiplayer_peer != null:
		_rpc_request_state.rpc_id(1)


var _tag: Label3D


## The town's house for this yard (net/town/town.gd), found by the yard's seed so
## every peer agrees without waiting on anything. -1 for a test yard.
func _house_id() -> int:
	var town := get_tree().get_first_node_in_group("town")
	var job_seed := int(get_parent().get("job_seed")) if get_parent() != null and "job_seed" in get_parent() else 0
	if town == null or job_seed == 0:
		return -1
	return int(town.call("house_by_seed", job_seed))


func _client_name() -> String:
	var house_id := _house_id()
	if house_id < 0:
		return _Strings.UI["homeowner_name"]
	return str(get_tree().get_first_node_in_group("town").call("owner_name", house_id))


## Their personality (net/town/neighborhoods.gd PERSONALITIES), "" for a test yard.
func _personality() -> String:
	var house_id := _house_id()
	if house_id < 0:
		return ""
	var entry: Dictionary = get_tree().get_first_node_in_group("town").call("house", house_id)
	return str((entry.get("owner", {}) as Dictionary).get("personality", ""))


## How picky this homeowner is, 0 to 1 (0.3 for a test yard).
func _standards() -> float:
	var house_id := _house_id()
	if house_id < 0:
		return 0.3
	return float(get_tree().get_first_node_in_group("town").call("standards", house_id))


## Pay multiplier: the neighborhood, the owner, and the crew's perks.
func _budget() -> float:
	var house_id := _house_id()
	if house_id < 0:
		return 1.0
	return float(get_tree().get_first_node_in_group("town").call("budget", house_id))


## The prompt while the local player is close enough.
func prompt() -> Dictionary:
	if not _local_in_reach():
		return {}
	# Joined after they paid (the town keeps a paid yard up): the yard's stage
	# says so, though this peer never saw the payment.
	var lot := get_parent()
	if lot != null and lot.has_method("is_paid") and bool(lot.call("is_paid")):
		return {}
	match _phase:
		Phase.WAITING:
			return {"text": _Strings.UI["prompt_talk"], "at": global_position + Vector3(0.0, 2.9, 0.0)}
		Phase.OFFERING:
			return {"text": _Strings.UI["prompt_take_cash"] % _amount, "at": _cash.global_position + Vector3(0.0, 0.5, 0.0)}
	return {}


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or not _local_in_reach():
		return
	if _phase == Phase.WAITING:
		_ask(true)
	elif _phase == Phase.OFFERING:
		_ask(false)
	else:
		return
	get_viewport().set_input_as_handled()


func _ask(talk: bool) -> void:
	if Net.is_host():
		if talk:
			_handle_talk(Net.local_peer_id())
		else:
			_handle_take(Net.local_peer_id())
	elif talk:
		_rpc_request_talk.rpc_id(1)
	else:
		_rpc_request_take.rpc_id(1)


func _process(delta: float) -> void:
	_turn_toward_nearest(delta)
	# The town can arrive a moment after the yard does.
	if _tag != null and _tag.text == _Strings.UI["homeowner_name"]:
		_tag.text = _client_name()
	_caption_left = maxf(0.0, _caption_left - delta)
	# The player's caption settings: off hides the words (the voice still plays),
	# and the size follows caption_size.
	_caption.visible = _caption_left > 0.0 and bool(Settings.get_value("interface", "captions"))
	_caption.pixel_size = CAPTION_PIXEL_SIZE * Settings.caption_scale()
	# Their name steps aside while they talk, so the two don't pile up.
	if _tag != null:
		_tag.visible = not _caption.visible
	if _phase == Phase.OFFERING:
		# Keep the hands out, and let the cash bob so it reads as "take this".
		if _body.call("current_gesture") != "offer":
			_body.call("gesture", "offer")
		_cash.position.y = 1.05 + sin(Time.get_ticks_msec() * 0.005) * 0.03
	_beckon(delta)


var _beckon_left: float = 0.0
## The wait after the next wave (s): it grows each wave, and a new bag in Chefty
## (more than _beckon_loaded's dollars) starts it over.
var _beckon_gap: float = Constants.HOMEOWNER_BECKON_SECONDS
var _beckon_loaded: int = 0


## Local, cosmetic (x1:text): bags in Chefty and nobody's asked to be paid yet,
## so they wave you over while you're on the yard but not at their side: at
## once, then less and less often (Constants.HOMEOWNER_BECKON_*), and soon again
## when another bag lands. The goal line used to say "talk to the homeowner";
## this is the world saying it. Reads only what every peer has (Chefty's load,
## the phase).
func _beckon(delta: float) -> void:
	_beckon_left = maxf(0.0, _beckon_left - delta)
	if _phase != Phase.WAITING:
		return
	var chefty := get_tree().get_first_node_in_group("chefty")
	var loaded := int(chefty.call("bag_value")) if chefty != null else 0
	if loaded > _beckon_loaded:
		# Another bag: they noticed. The next wave comes soon, and the gaps start
		# over from the quick one.
		# The truck's value counts a tossed bag while it's still in the air, so the
		# wave waits for it to land and be noticed.
		_beckon_gap = Constants.HOMEOWNER_BECKON_SECONDS
		_beckon_left = clampf(_beckon_left, Constants.HOMEOWNER_BECKON_NOTICE_SECONDS, Constants.HOMEOWNER_BECKON_SECONDS * 0.5)
	_beckon_loaded = loaded
	if loaded <= 0 or _beckon_left > 0.0 or bool(_body.call("is_gesturing")):
		return
	var lot := get_parent()
	if lot != null and lot.has_method("is_paid") and bool(lot.call("is_paid")):
		return
	var me: Node3D = null
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			me = node as Node3D
	if me == null or Net.player_zone(Net.local_peer_id()) != Net.Zone.LOT:
		return
	var away := _flat_distance(me)
	if away <= TALK_REACH or away > Constants.HOMEOWNER_BECKON_METERS:
		return
	_beckon_left = _beckon_gap
	_beckon_gap = minf(_beckon_gap * Constants.HOMEOWNER_BECKON_BACKOFF, Constants.HOMEOWNER_BECKON_MAX_SECONDS)
	_body.call("gesture", "wave")
	# The first wave gets a "yoo-hoo" babble, so you look up; after that the waves are quiet.
	if not _beckoned:
		_beckoned = true
		_speak("babble")


var _beckoned: bool = false


# ---------------------------------------------------------------- host

func _handle_talk(peer_id: int) -> void:
	if _phase != Phase.WAITING or not _in_reach(peer_id):
		return
	var chefty := get_tree().get_first_node_in_group("chefty")
	var value := int(chefty.call("bag_value")) if chefty != null else 0
	# Every other task they asked for pays its share of Constants.TASK_PAY by how much got done.
	var task_lines: Array = []
	var task_value := 0
	var tasks := get_tree().get_first_node_in_group("job_tasks")
	if tasks != null:
		for task: String in (tasks.get("active") as PackedStringArray):
			if not Constants.TASK_PAY.has(task):
				continue
			var done := float(tasks.call("progress", task))
			var pay := int(round(float(Constants.TASK_PAY[task]) * done))
			task_value += pay
			task_lines.append([task, int(round(done * 100.0)), pay])
	var mood := _judge(value + task_value)
	# Their water isn't free.
	var water_fee := int(round(float(tasks.get("water_fee")))) if tasks != null else 0
	var bills_owed: Dictionary = tasks.get("bills") if tasks != null else {}
	var pool := choose_pool(mood, bills_owed, water_fee, _personality(), _rng)
	var lines: Array = _Strings.homeowner_pool(pool)
	var line_index := _rng.randi() % lines.size()
	# Whatever the crew broke or hurt comes off too: a new hose, a new gnome, medical bills.
	var bills: Dictionary = (tasks.get("bills") as Dictionary).duplicate() if tasks != null else {}
	var bills_total := int(tasks.call("bills_total")) if tasks != null else 0
	# Richer neighborhoods and better-off owners pay more for the same work.
	var budget := _budget()
	var amount := _Economy.job_pay(value, task_value, mood, budget, water_fee, bills_total)
	_settlement = {"bags_value": value, "tasks": task_lines, "mood": mood, "multiplier": float(Constants.HOMEOWNER_PAY_BY_MOOD.get(mood, 1.0)), "water_fee": water_fee, "bills": bills, "paid": amount}
	_rpc_react.rpc(mood, line_index, amount, pool)
	if mood == "nothing":
		return
	get_tree().create_timer(REACT_SECONDS).timeout.connect(func() -> void:
		if _phase == Phase.REACTING:
			_rpc_offer.rpc()
	)


## Host: which Strings.homeowner_pool() the reaction comes from. Whatever the crew
## broke comes up first, most of the time; then the water bill; otherwise they
## usually talk like themselves (Strings.PERSONALITY_LINES). Static so
## net/dev/cast_test.gd can roll it with a seeded rng.
static func choose_pool(mood: String, bills_owed: Dictionary, water_fee: int, personality: String, rng: RandomNumberGenerator) -> String:
	var pool := mood
	if mood != "nothing" and not bills_owed.is_empty() and rng.randf() < Constants.HOMEOWNER_BILL_LINE_CHANCE:
		var reasons: Array = bills_owed.keys()
		var reason := "bill_%s" % str(reasons[rng.randi() % reasons.size()])
		if _Strings.HOMEOWNER_LINES.has(reason):
			pool = reason
	elif mood != "nothing" and bills_owed.is_empty() and water_fee > 0 and rng.randf() < Constants.HOMEOWNER_WATER_LINE_CHANCE:
		pool = "bill_water"
	if pool == mood and personality != "" and rng.randf() < Constants.HOMEOWNER_PERSONALITY_LINE_CHANCE:
		pool = "%s/%s" % [personality, mood]
	return pool


## How the homeowner feels about the job. No bags delivered means no pay.
func _judge(value: int) -> String:
	if value <= 0:
		return "nothing"
	var field := get_tree().get_first_node_in_group("leaf_field")
	# Picky owners want it cleaner before they're happy, and call it a mess sooner.
	var standards := _standards()
	var clean_enough := _Economy.clean_enough_at(standards)
	var messy_below := _Economy.messy_below_at(standards)
	# How done the whole job is: the leaves and every task asked for, weighed alike.
	var clean := float(field.call("cleaned_fraction")) if field != null else 0.0
	var tasks := get_tree().get_first_node_in_group("job_tasks")
	if tasks != null:
		var parts := [clampf(clean / clean_enough, 0.0, 1.0)]
		for task: String in (tasks.get("active") as PackedStringArray):
			if Constants.TASK_PAY.has(task):
				parts.append(float(tasks.call("progress", task)))
		var total := 0.0
		for part: float in parts:
			total += part
		clean = total / float(parts.size()) * clean_enough
	var patience := Constants.HOMEOWNER_PATIENCE_MINUTES
	if Campaign.has_perk("sweet_talk"):
		patience *= Constants.SWEET_TALK_PATIENCE
	var slow := Campaign.job_minutes() > patience
	var mood := "fine"
	if clean < messy_below:
		mood = "messy"
	elif slow:
		mood = "slow"
	elif clean >= clean_enough:
		mood = "thrilled" if _rng.randf() < Constants.HOMEOWNER_THRILLED_CHANCE else "happy"
	else:
		mood = "happy" if _rng.randf() < Constants.HOMEOWNER_HAPPY_CHANCE else "fine"
	# Some days people are just in a mood, either way.
	var roll := _rng.randf()
	if roll < 0.12:
		mood = ["happy", "thrilled"][_rng.randi() % 2]
	elif roll > 0.9:
		mood = ["slow", "fine"][_rng.randi() % 2]
	return mood


func _handle_take(peer_id: int) -> void:
	if _phase != Phase.OFFERING or not _in_reach(peer_id):
		return
	_rpc_paid.rpc(peer_id)
	var world := get_tree().get_first_node_in_group("world")
	if world != null:
		world.call("finish_with_pay", _amount, _settlement)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_talk() -> void:
	if Net.is_host():
		_handle_talk(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_take() -> void:
	if Net.is_host():
		_handle_take(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_state() -> void:
	if Net.is_host() and _phase == Phase.OFFERING:
		_rpc_offer_with.rpc_id(multiplayer.get_remote_sender_id(), _amount)


# ---------------------------------------------------------------- every peer

@rpc("authority", "call_local", "reliable")
func _rpc_react(mood: String, line_index: int, amount: int, pool: String = "") -> void:
	_amount = amount
	_phase = Phase.WAITING if mood == "nothing" else Phase.REACTING
	# pool is "<mood>", "bill_<reason>" or "<personality>/<mood>" (Strings.homeowner_pool).
	var lines: Array = _Strings.homeowner_pool(pool if pool != "" else mood)
	show_caption(str(lines[clampi(line_index, 0, lines.size() - 1)]))
	var staging: Dictionary = STAGING.get(mood, STAGING["fine"])
	_body.set("mood", staging["mood"])
	_body.call("gesture", staging["gesture"])
	_speak(str(staging["sound"]))


@rpc("authority", "call_local", "reliable")
func _rpc_offer() -> void:
	_offer(_amount)


@rpc("authority", "call_remote", "reliable")
func _rpc_offer_with(amount: int) -> void:
	_offer(amount)


func _offer(amount: int) -> void:
	_amount = amount
	_phase = Phase.OFFERING
	_cash_label.text = _Strings.UI["cash_amount"] % amount
	_cash.visible = true


@rpc("authority", "call_local", "reliable")
func _rpc_paid(peer_id: int) -> void:
	_phase = Phase.PAID
	# The cash snatched out of their hand, the bills fluttering (audio:5): where it
	# happens for anyone watching, and in the taker's own hands for the taker, who is
	# on Chefty a frame later (a sound left at the curb would be out of earshot).
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null and peer_id == Net.local_peer_id():
		sfx.call("play", "cash_grab")
	elif sfx != null:
		sfx.call("play_at", "cash_grab", _cash.global_position)
	_MoneyPopup.pop(get_tree(), _cash.global_position + Vector3(0.0, 0.4, 0.0), _amount)
	_cash.visible = false
	_body.set("mood", "raised")
	_body.call("gesture", "wave")
	# Seeded by the amount, which every peer has, so they all hear the same goodbye.
	show_caption(_Strings.pick_seeded(_Strings.HOMEOWNER_LINES["paid"], _amount), Constants.HOMEOWNER_PAID_CAPTION_SECONDS)
	_speak("babble")


## Puts line over their head for seconds (hidden, but still timed, when the player
## turned captions off; _process applies the caption settings every frame).
func show_caption(line: String, seconds: float = CAPTION_SECONDS) -> void:
	_caption.text = line
	_caption_left = seconds


func _speak(sound: String) -> void:
	if Net.is_automated():
		return
	var file := "babble_%d" % _rng.randi_range(1, 5) if sound == "babble" else sound
	var stream := load("res://assets/audio/sfx/%s.wav" % file) as AudioStream
	if stream == null:
		return
	_voice.stream = stream
	_voice.pitch_scale = _rng.randf_range(0.9, 1.1)
	_voice.play()
	_body.call("talk", stream.get_length() / _voice.pitch_scale)


# ---------------------------------------------------------------- helpers

## A fat wad of bills in their hands, with the amount floating over it.
func _build_cash() -> void:
	_cash = Node3D.new()
	_cash.name = "Cash"
	_cash.position = Vector3(0.0, 1.05, -0.5)
	add_child(_cash)
	var green := Color(0.42, 0.62, 0.35)
	for index: int in 3:
		var bills := _LowPoly.box(_cash, Vector3(0.32, 0.05, 0.16), Vector3(0.0, float(index) * 0.05, 0.0), green.lightened(float(index) * 0.06))
		bills.rotation.y = float(index - 1) * 0.12
		_LowPoly.paint(bills, "fabric")
	_LowPoly.box(_cash, Vector3(0.06, 0.16, 0.17), Vector3(0.0, 0.05, 0.0), Color(0.9, 0.85, 0.7))
	_cash_label = Label3D.new()
	_cash_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_cash_label.font_size = 64
	_cash_label.outline_size = 12
	_cash_label.modulate = Color(0.7, 1.0, 0.6)
	_cash_label.position.y = 0.3
	_cash.add_child(_cash_label)
	_cash.visible = false


func _turn_toward_nearest(delta: float) -> void:
	var nearest: Node3D = null
	var best := 8.0
	for node: Node in get_tree().get_nodes_in_group("players"):
		var body := node as Node3D
		if body != null and _flat_distance(body) < best:
			nearest = body
			best = _flat_distance(body)
	if nearest == null:
		return
	var to := nearest.global_position - global_position
	rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), clampf(delta * 4.0, 0.0, 1.0))


func _local_in_reach() -> bool:
	return _in_reach(Net.local_peer_id())


func _in_reach(peer_id: int) -> bool:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return _flat_distance(node as Node3D) <= TALK_REACH
	return false


func _flat_distance(body: Node3D) -> float:
	return Vector2(body.global_position.x - global_position.x, body.global_position.z - global_position.z).length()
