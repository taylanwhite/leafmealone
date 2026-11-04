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
	_build_solid()
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
			# Just under the offered handful, not over the face (P1 lens: half a meter
			# up, the pill sat on her face; on the cash, it hid the cash). The drop
			# grows with distance, so it's about the pill's height on screen and the
			# pill stays in the picture up close.
			var cam := get_viewport().get_camera_3d()
			var away := cam.global_position.distance_to(_cash.global_position) if cam != null else Constants.HOMEOWNER_FACE_METERS
			return {"text": _Strings.UI["prompt_take_cash"] % _amount, "at": _cash.global_position - Vector3(0.0, Constants.HOMEOWNER_PROMPT_DROP * away, 0.0)}
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
		# In reach, the pill says the amount; the price over their head is for
		# everyone further off (one "$9" on screen, not two).
		_cash_label.visible = not _local_in_reach()
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
	# Into the talker's view (the one who asked, not whoever's nearest), the same
	# spot on every peer.
	host_stage_for(peer_id)
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


## Host: something the crew did out front got to them (driving chunk C3: Chefty
## parked on the lawn, "lawn_park"; the horn in their yard, "horn"): they yell
## a line from that Strings.HOMEOWNER_LINES pool. With costs_mood, their mood at
## payday drops a step (thrilled, happy, fine, slow) for each.
func host_grumble(pool: String, costs_mood: bool) -> void:
	if not Net.is_host() or _phase == Phase.PAID:
		return
	if costs_mood:
		grumbles += 1
	var lines: Array = _Strings.homeowner_pool(pool)
	_rpc_yell.rpc(pool, _rng.randi() % lines.size())


## Host: how many mood steps the crew has cost themselves (host_grumble).
var grumbles: int = 0
## Every peer: the yells heard, for tests ([pool, ...]).
var yells_seen: Array[String] = []
## The mood ladder a grumble steps down (messy and nothing stay as they are).
const MOOD_LADDER: Array[String] = ["thrilled", "happy", "fine", "slow"]


@rpc("authority", "call_local", "reliable")
func _rpc_yell(pool: String, line_index: int) -> void:
	yells_seen.append(pool)
	var lines: Array = _Strings.homeowner_pool(pool)
	show_caption(str(lines[clampi(line_index, 0, lines.size() - 1)]), Constants.HOMEOWNER_YELL_SECONDS)
	_body.set("mood", "angry")
	_body.call("gesture", "point")
	_speak("vo_huh")


## A mood stepped down the ladder once per grumble.
static func grumbled(mood: String, steps: int) -> String:
	var at := MOOD_LADDER.find(mood)
	if at < 0 or steps <= 0:
		return mood
	return MOOD_LADDER[mini(at + steps, MOOD_LADDER.size() - 1)]


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
	# Whatever the crew did out front, they haven't forgotten (host_grumble).
	return grumbled(mood, grumbles)


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
	if not Net.is_host():
		return
	var asker := multiplayer.get_remote_sender_id()
	# Where they stand and where they're headed (a joiner mid-talk sees her where
	# everyone else does).
	_rpc_walk_sync.rpc_id(asker, _home, position, _shared_want if _shared_want.is_finite() else position, _talker)
	if _phase == Phase.OFFERING:
		_rpc_offer_with.rpc_id(asker, _amount)


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
	# In reach, the pill says the amount (_process keeps this up to date).
	_cash_label.visible = not _local_in_reach()


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
	# The snatch is the money's sound here; a coin on top of it piled four sounds
	# onto one frame (rec_a5_pay2_1p frame 18, with the babble and Chefty).
	_MoneyPopup.pop(get_tree(), _cash.global_position + Vector3(0.0, 0.4, 0.0), _amount, false)
	_cash.visible = false
	_cash_label.visible = false
	_stage_to = Vector3.INF
	_talker = 0
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
	# The amount over their head, small (P1 lens, NB-M2: a giant "$10" on the cash
	# covered her whole chest and the offered handful it was meant to label).
	_cash_label = Label3D.new()
	_cash_label.name = "Price"
	_cash_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_cash_label.font_size = Constants.HOMEOWNER_PRICE_FONT
	_cash_label.pixel_size = Constants.HOMEOWNER_PRICE_PIXEL
	_cash_label.outline_size = 10
	_cash_label.modulate = Color(0.7, 1.0, 0.6)
	_cash_label.position.y = Constants.HOMEOWNER_PRICE_Y
	_cash_label.visible = false
	add_child(_cash_label)
	_cash_label.add_to_group("prompt_avoid")
	_cash.visible = false


## Solid to people (P1 lens, crew-17: walking into her put the camera through her
## face), the way the Annex staff are: a capsule and a wider head ball on the
## pad-wall layer, which people mask and thrown things and rays don't. It rides
## along as they step about.
func _build_solid() -> void:
	var solid := AnimatableBody3D.new()
	solid.name = "Solid"
	solid.sync_to_physics = false
	solid.collision_layer = Constants.PAD_WALL_LAYER
	solid.collision_mask = 0
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = Constants.HOMEOWNER_SOLID_RADIUS
	capsule.height = Constants.HOMEOWNER_SOLID_HEIGHT
	shape.shape = capsule
	shape.position = Vector3(0.0, Constants.HOMEOWNER_SOLID_HEIGHT * 0.5, 0.0)
	solid.add_child(shape)
	var head := CollisionShape3D.new()
	var ball := SphereShape3D.new()
	ball.radius = Constants.HOMEOWNER_SOLID_HEAD_RADIUS
	head.shape = ball
	head.position = Vector3(0.0, Constants.HOMEOWNER_SOLID_HEAD_Y, 0.0)
	solid.add_child(head)
	add_child(solid)


func _turn_toward_nearest(delta: float) -> void:
	var nearest: Node3D = null
	var best := 8.0
	for node: Node in get_tree().get_nodes_in_group("players"):
		var body := node as Node3D
		# Talking with someone: it's them she faces, whoever else walks up.
		if body != null and _talker != 0 and (_phase == Phase.REACTING or _phase == Phase.OFFERING) and node.name == str(_talker):
			nearest = body
			break
		if body != null and _flat_distance(body) < best:
			nearest = body
			best = _flat_distance(body)
	if nearest == null:
		return
	var to := nearest.global_position - global_position
	rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), clampf(delta * 4.0, 0.0, 1.0))


# ---------------------------------------------------------------- stepping about
# P1 lens (docs/GAME.md, "Nobody's face at the lens"): they keep a polite
# distance and, when they answer you, step round to where you're looking (NB-05:
# Patrice talked from half off the left edge of the screen for four seconds).
# The host decides where she goes (who's too close, who asked) and sends each
# new destination (_rpc_walk, lot space); every peer walks her there the same
# way, so the spot the host checks reach against is the spot every player sees
# (P1 lens review: each peer picking its own nearest player put her up to 2.4 m
# apart). A joiner gets where she is and where she's headed (_rpc_walk_sync).

## Where they wait (in the lot's space), where they're stepping to (INF: nowhere
## in particular), and how fast they're walking now.
var _home := Vector3.ZERO
var _stage_to := Vector3.INF
var _back_to := Vector3.INF
var _walk_speed: float = 0.0
var _left_at := Vector3.INF
## Who she's answering (a peer id, 0: nobody): she faces them while she talks.
var _talker: int = 0
## Host: the destination last sent (lot space), when, and one waiting to go.
var _shared_want := Vector3.INF
var _shared_at: float = -INF
var _share_pending: bool = false
## Clients: the destination the host last sent.
var _net_want := Vector3.INF


func _physics_process(delta: float) -> void:
	var parent := get_parent() as Node3D
	if parent == null or not is_inside_tree():
		return
	# Placed somewhere new by someone else (a scenario, a test): that's home now.
	if not _left_at.is_finite() or position.distance_to(_left_at) > 0.5:
		_home = position
		_stage_to = Vector3.INF
		_back_to = Vector3.INF
		_net_want = Vector3.INF
		_shared_want = Vector3.INF
		_walk_speed = 0.0
	if Net.is_host() or multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		_host_steps(delta)
	else:
		_walk(_net_want, delta)
	_left_at = position


## Host: where she should be heading this tick, walked, and shared.
func _host_steps(delta: float) -> void:
	var parent := get_parent() as Node3D
	var nearest := _nearest_player()
	var away := _flat_distance(nearest) if nearest != null else INF
	# On the way round into the talker's view the path can cut a little inside the
	# polite distance; only someone really close (HOMEOWNER_KEEP_STAGED_METERS)
	# turns that into a step back.
	var too_close := Constants.HOMEOWNER_KEEP_STAGED_METERS if _stage_to.is_finite() else Constants.HOMEOWNER_KEEP_METERS * Constants.HOMEOWNER_KEEP_TRIGGER
	if nearest != null and away < too_close:
		# Someone's walked right up: a step back, so they're not in your face. The
		# step is kept till it's taken (no stopping dead the moment it's enough).
		var from := parent.to_local(nearest.global_position)
		var out := Vector3(position.x - from.x, 0.0, position.z - from.z)
		if out.length() < 0.01:
			out = transform.basis.z
		_back_to = position + out.normalized() * (Constants.HOMEOWNER_KEEP_METERS - away)
		_stage_to = Vector3.INF
	var want := Vector3.INF
	if _back_to.is_finite():
		want = _back_to
	elif _stage_to.is_finite() and (_phase == Phase.REACTING or _phase == Phase.OFFERING or away < Constants.HOMEOWNER_HOME_AFTER_METERS):
		want = _stage_to
	elif away > Constants.HOMEOWNER_HOME_AFTER_METERS:
		_stage_to = Vector3.INF
		want = _home
	# Where she ends up this tick when there's nowhere to go: where she stopped.
	var heading := want
	if _walk(want, delta):
		_back_to = Vector3.INF
	_share_want(heading if heading.is_finite() else position, false)


## Host: sends a new destination to everyone (at most every
## HOMEOWNER_WALK_SHARE_SECONDS while someone keeps crowding her; the latest one
## always goes out).
func _share_want(want: Vector3, now: bool) -> void:
	var changed := not _shared_want.is_finite() or want.distance_to(_shared_want) > 0.05
	if not changed and not _share_pending and not now:
		return
	if changed:
		_shared_want = want
		_share_pending = true
	var clock := Time.get_ticks_msec() / 1000.0
	if not now and clock - _shared_at < Constants.HOMEOWNER_WALK_SHARE_SECONDS:
		return
	_share_pending = false
	_shared_at = clock
	if multiplayer.multiplayer_peer != null and Net.is_host() and multiplayer.get_peers().size() > 0:
		_rpc_walk.rpc(_shared_want, _talker)


## Host, when someone talks to them: the talker is peer_id (whoever asked, not
## whoever's nearest); they step to HOMEOWNER_FACE_METERS in front of that
## player's eyes, so the line, the gesture and the cash happen in the middle of
## the talker's screen. Sent to every peer at once.
func host_stage_for(peer_id: int) -> void:
	var parent := get_parent() as Node3D
	var talker: Node3D = null
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			talker = node as Node3D
	if talker == null or parent == null or _flat_distance(talker) > TALK_REACH + 0.5:
		return
	_talker = peer_id
	var yaw := float(talker.get("body_yaw")) if "body_yaw" in talker else talker.global_rotation.y
	var ahead := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var spot := talker.global_position + ahead * Constants.HOMEOWNER_FACE_METERS
	_stage_to = parent.to_local(Vector3(spot.x, global_position.y, spot.z))
	_back_to = Vector3.INF
	_share_want(_stage_to, true)


## Every peer but the host: where she's headed now (lot space), and who she's talking to.
@rpc("authority", "call_remote", "reliable")
func _rpc_walk(want: Vector3, talker: int) -> void:
	_net_want = want
	_talker = talker


## A joiner: where she waits, where she is, where she's headed, who she's talking to.
@rpc("authority", "call_remote", "reliable")
func _rpc_walk_sync(home: Vector3, at: Vector3, want: Vector3, talker: int) -> void:
	_home = home
	position = Vector3(at.x, position.y, at.z)
	_left_at = position
	_net_want = want
	_talker = talker
	_walk_speed = 0.0


## Walks toward want (lot space; INF stays put): within HOMEOWNER_STAGE_RADIUS of
## home, short of anything solid on the way, easing in and out. CartoonBody
## animates the walk from the motion. True once there (or nowhere to go).
func _walk(want: Vector3, delta: float) -> bool:
	var goal := position
	if want.is_finite():
		var off := Vector3(want.x - _home.x, 0.0, want.z - _home.z).limit_length(Constants.HOMEOWNER_STAGE_RADIUS)
		goal = Vector3(_home.x + off.x, position.y, _home.z + off.z)
		goal = _clear_path(goal)
	var to := Vector3(goal.x - position.x, 0.0, goal.z - position.z)
	var moving := _walk_speed > 0.05
	if to.length() < (0.04 if moving else Constants.HOMEOWNER_STEP_MIN_METERS):
		_walk_speed = 0.0
		return true
	# Ease in, and slow down for the last stretch rather than stopping dead.
	var top := minf(Constants.HOMEOWNER_WALK_SPEED, to.length() / maxf(Constants.HOMEOWNER_WALK_EASE_SECONDS, 0.01))
	_walk_speed = move_toward(_walk_speed, top, delta * Constants.HOMEOWNER_WALK_SPEED / maxf(Constants.HOMEOWNER_WALK_EASE_SECONDS, 0.01))
	position += to.normalized() * minf(_walk_speed * delta, to.length())
	return false


## goal pulled back short of the first solid thing (a fence, the house, Chefty)
## between them and it, at chest height.
func _clear_path(goal: Vector3) -> Vector3:
	var parent := get_parent() as Node3D
	var world := get_world_3d()
	if parent == null or world == null:
		return goal
	var chest := Vector3(0.0, 1.0, 0.0)
	var from := global_position + chest
	var to := parent.to_global(goal) + chest
	if from.distance_to(to) < 0.05:
		return goal
	var query := PhysicsRayQueryParameters3D.create(from, to + (to - from).normalized() * Constants.HOMEOWNER_SOLID_RADIUS, 1 | Constants.VEHICLE_LAYER)
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return goal
	var stop: Vector3 = hit["position"]
	var back := from.distance_to(stop) - Constants.HOMEOWNER_SOLID_RADIUS
	if back <= 0.0:
		return position
	return parent.to_local(from + (to - from).normalized() * back - chest)


## The nearest player within 8 m on the yard (not a watcher), or null.
func _nearest_player() -> Node3D:
	var nearest: Node3D = null
	var best := 8.0
	for node: Node in get_tree().get_nodes_in_group("players"):
		var body := node as Node3D
		if body == null or (str(node.name).is_valid_int() and Net.is_watcher(int(str(node.name)))):
			continue
		var away := _flat_distance(body)
		if away < best:
			nearest = body
			best = away
	return nearest


## Where they're stepping to (world space, INF for nowhere) and how fast. For tests.
func stepping_to() -> Vector3:
	var parent := get_parent() as Node3D
	return parent.to_global(_stage_to) if parent != null and _stage_to.is_finite() else Vector3.INF


func walk_speed() -> float:
	return _walk_speed


func _local_in_reach() -> bool:
	return _in_reach(Net.local_peer_id())


func _in_reach(peer_id: int) -> bool:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return _flat_distance(node as Node3D) <= TALK_REACH
	return false


func _flat_distance(body: Node3D) -> float:
	return Vector2(body.global_position.x - global_position.x, body.global_position.z - global_position.z).length()
