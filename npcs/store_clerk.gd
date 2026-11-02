extends Node3D

## Authority: local, cosmetic. Marty, the Homie Depot clerk behind the counter
## (docs/FEEL.md, "How characters deal with shops"; docs/GAME.md, "2026-11-01,
## the cast"): a deadpan lifer who takes the store far too seriously. Turns to
## face whoever is closest, says something when you walk up (a caption over his
## head with his babble), and opens the shop window when you press E across the
## counter. Every peer has its own copy: nothing about the clerk is shared state,
## and buying goes through Shops on the host.
##
## What he says comes from Strings.KEEPER_LINES[KEEPER][trigger]:
##   greet       walking up to the counter
##   morning     the first time you walk up on a new day, before noon
##   night       walking up during quiet hours
##   after_raid  the first time you walk up after the NICE BOYS took you over the border
##   open        opening the shop window
##   closed      opening the shop window after hours
##   buy         a purchase the host confirmed in his window (ui/shop_window.gd
##               `bought`, which waits for Shops.result "ok"; ui/ui_root.gd calls it)
## Shops' generic keepers take this trigger logic over later (critic C19).

const _Strings = preload("res://ui/strings.gd")
const _CartoonBody = preload("res://player/cartoon_body.gd")
const _CharacterLife = preload("res://player/character_life.gd")
## Every trigger KEEPER_LINES must have lines for (net/dev/cast_test.gd checks).
const TRIGGERS: Array[String] = ["greet", "morning", "night", "open", "buy", "after_raid", "closed"]
## Whose lines these are in Strings.KEEPER_LINES, and whose hours (Constants.SHOP_HOURS).
const KEEPER: String = "marty"
const SHOP: String = "homie_depot"
## How close the local player must be to shop, across the counter, in meters.
const SHOP_REACH: float = 3.0
## How close someone must be for the clerk to look at them and greet them.
const NOTICE_RANGE: float = 7.0
const GREET_COOLDOWN_SECONDS: float = 8.0
const APRON := Color(0.93, 0.47, 0.13)
## The caption's size on screen at the normal caption size (Settings.caption_scale()).
## Presentation, not tuning: it matches the homeowner caption (docs/DECISIONS.md).
const CAPTION_PIXEL_SIZE: float = 0.0011

## The last line he said on this peer, and why (for tests and the probe).
var last_line: String = ""
var last_trigger: String = ""

var _body: Node3D
var _voice: AudioStreamPlayer3D
var _caption: Label3D
var _caption_left: float = 0.0
var _tag: Label3D
var _greeted_at: float = -1000.0
var _local_was_near: bool = false
## The day of the last greet, so the first one of a day can be "morning".
var _greeted_day: int = -1
## The local player was taken over the border and Marty hasn't said his after-raid line yet.
var _was_raided: bool = false


func _ready() -> void:
	add_to_group("prompt_sources")
	add_to_group("store_clerk")
	_body = _CartoonBody.new()
	_body.name = "CartoonBody"
	_body.set("shirt", APRON)
	_body.set("pants", Color(0.28, 0.3, 0.38))
	_body.set("skin", _CartoonBody.SKIN_TONES[2])
	_body.set("hat_style", "cap")
	_body.set("hat_color", APRON.darkened(0.2))
	add_child(_body)
	_body.call("build")
	var life := _CharacterLife.new()
	life.name = "Life"
	life.root = self
	life.body = _body
	life.role = "clerk"
	_body.add_child(life)
	_tag = Label3D.new()
	_tag.text = _Strings.UI["clerk_name"]
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.font_size = 40
	_tag.outline_size = 8
	_tag.position.y = 2.25
	add_child(_tag)
	# Styled like the homeowner's caption: the same size on screen however close you stand.
	_caption = Label3D.new()
	_caption.name = "Caption"
	_caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_caption.fixed_size = true
	_caption.pixel_size = CAPTION_PIXEL_SIZE
	_caption.font_size = 30
	_caption.outline_size = 10
	_caption.width = 520.0
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_caption.position.y = 2.3
	_caption.modulate = Color(1.0, 0.97, 0.85)
	_caption.no_depth_test = true
	_caption.visible = false
	add_child(_caption)
	_voice = AudioStreamPlayer3D.new()
	_voice.position.y = 1.6
	_voice.unit_size = 4.0
	_voice.bus = preload("res://audio/sound_bank.gd").bus("babble")
	add_child(_voice)
	Net.player_zone_changed.connect(_on_zone_changed)


## The shop prompt while the local player is across the counter.
func prompt() -> Dictionary:
	if not _local_in_reach():
		return {}
	return {"text": _Strings.UI["prompt_shop"], "at": global_position + Vector3(0.0, 2.6, 0.0)}


## Say a line for this trigger (TRIGGERS): a caption over his head, with babble.
func say_line(trigger: String) -> void:
	var by_trigger: Dictionary = _Strings.KEEPER_LINES.get(KEEPER, {})
	var lines: Array = by_trigger.get(trigger, by_trigger.get("greet", []))
	if lines.is_empty():
		chatter()
		return
	last_trigger = trigger
	last_line = str(lines[randi() % lines.size()])
	_caption.text = last_line
	_caption_left = Constants.CLERK_CAPTION_SECONDS
	chatter()


## Babble something, with the mouth moving. Called with every line.
func chatter() -> void:
	if Net.is_automated():
		return
	var stream := load("res://assets/audio/sfx/babble_%d.wav" % randi_range(1, 5)) as AudioStream
	if stream == null:
		return
	_voice.stream = stream
	_voice.pitch_scale = randf_range(0.95, 1.08)
	_voice.play()
	_body.call("talk", stream.get_length() / _voice.pitch_scale)


## Which line walking up to the counter gets right now.
func greet_trigger() -> String:
	var clock := get_tree().get_first_node_in_group("day_clock")
	var day := int(clock.get("day")) if clock != null else 1
	var hour := float(clock.call("hour")) if clock != null else Constants.DAY_START_HOUR
	if day != _greeted_day and hour < Constants.CLERK_MORNING_UNTIL_HOUR:
		return "morning"
	if _was_raided:
		return "after_raid"
	if clock != null and bool(clock.call("is_quiet_hours")):
		return "night"
	return "greet"


## Which line opening the shop window gets: "closed" after hours, else "open".
func open_trigger() -> String:
	var shops := get_tree().get_first_node_in_group("shops")
	if shops != null and not bool(shops.call("is_open", SHOP)):
		return "closed"
	return "open"


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or not _local_in_reach():
		return
	var ui := get_tree().get_first_node_in_group("game_ui")
	if ui != null:
		ui.call("open_store")
		say_line(open_trigger())
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var nearest := _nearest_player()
	if nearest != null:
		# Turn toward them. Bodies face -Z, so look away from the target to face it.
		var to := nearest.global_position - global_position
		var yaw := atan2(-to.x, -to.z)
		rotation.y = lerp_angle(rotation.y, yaw, clampf(delta * 4.0, 0.0, 1.0))
	var near := _local_in_reach()
	var now := Time.get_ticks_msec() / 1000.0
	if near and not _local_was_near and now - _greeted_at > GREET_COOLDOWN_SECONDS:
		_greeted_at = now
		_greet()
	_local_was_near = near
	_caption_left = maxf(0.0, _caption_left - delta)
	var captions_on := bool(Settings.get_value("interface", "captions"))
	_caption.visible = _caption_left > 0.0 and captions_on
	_caption.pixel_size = CAPTION_PIXEL_SIZE * Settings.caption_scale()
	# His name steps aside while he talks, so the two don't pile up.
	_tag.visible = not _caption.visible


func _greet() -> void:
	var trigger := greet_trigger()
	var clock := get_tree().get_first_node_in_group("day_clock")
	_greeted_day = int(clock.get("day")) if clock != null else 1
	# A morning greet wins over the raid; the after-raid line waits for the next greet.
	if trigger == "after_raid":
		_was_raided = false
	say_line(trigger)


func _on_zone_changed(peer_id: int, zone: int) -> void:
	if peer_id == Net.local_peer_id() and zone == Net.Zone.BORDER:
		_was_raided = true


func _local_in_reach() -> bool:
	var local := _player(Net.local_peer_id())
	return local != null and _flat_distance(local) <= SHOP_REACH


func _nearest_player() -> Node3D:
	var best: Node3D = null
	var best_distance := NOTICE_RANGE
	for node: Node in get_tree().get_nodes_in_group("players"):
		var body := node as Node3D
		if body == null:
			continue
		var distance := _flat_distance(body)
		if distance < best_distance:
			best = body
			best_distance = distance
	return best


func _player(peer_id: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node as Node3D
	return null


func _flat_distance(body: Node3D) -> float:
	return Vector2(body.global_position.x - global_position.x, body.global_position.z - global_position.z).length()
