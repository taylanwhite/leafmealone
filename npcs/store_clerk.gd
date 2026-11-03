extends Node3D

## Authority: local, cosmetic. A shopkeeper behind a counter (docs/FEEL.md, "How
## characters deal with shops"; docs/GAME.md "Shops" and "2026-11-01, the cast"):
## Marty at Homie Depot, Rusty at Rusty's Salvage & Pawn, Dot at Lunch Money
## (shop_id picks which; Catalog.SHOPS names the keeper, KEEPERS dresses them).
## Turns to face whoever is closest, says something when you walk up (a caption
## over the head with babble), and opens their shop's window when you press E at
## the counter. Every peer has its own copy: nothing about a keeper is shared
## state, and buying goes through Shops on the host. levels/dressing/shop_sites.gd
## puts one at each shop's Constants.SHOP_SITES keeper spot.
##
## Opening hours (Constants.SHOP_HOURS): while their shop is closed Rusty and Dot
## go home (hidden), and the counter's prompt reads "Closed. Opens 7 AM". Marty
## never goes home (he doesn't know how; the crew sleeps by his side wall), so
## after hours he stands behind a shuttered register: E still opens his window,
## on the CLOSED shutter, and gets his "closed" line. A keeper whose shop the
## crew's rank hasn't opened yet isn't there at all.
##
## What a keeper says comes from Strings.KEEPER_LINES[keeper][trigger]:
##   greet       walking up to the counter
##   morning     the first time you walk up on a new day, before noon
##   night       walking up during quiet hours
##   after_raid  the first time you walk up after the NICE BOYS took you to Annex B
##   open        opening the shop window
##   closed      opening the shop window after hours
##   buy         a purchase the host confirmed in their window (on_sale: ui/ui_root.gd
##               calls it on ui/shop_window.gd `bought`, which waits for Shops.result "ok")

const _Strings = preload("res://ui/strings.gd")
const _CartoonBody = preload("res://player/cartoon_body.gd")
const _CharacterLife = preload("res://player/character_life.gd")
## Every trigger KEEPER_LINES must have lines for (net/dev/cast_test.gd checks).
const TRIGGERS: Array[String] = ["greet", "morning", "night", "open", "buy", "after_raid", "closed"]
const APRON := Color(0.93, 0.47, 0.13)
## How each keeper looks: shirt, pants, skin (CartoonBody.SKIN_TONES index), hat
## style and color; and whether they stay behind the counter after closing.
## Rusty is all denim overalls and a rust-red cap; Dot wears the white Lunch
## Money top and a yellow cap (her paper hat comes with the hats, shops chunk 7).
const KEEPERS: Dictionary = {
	"marty": {"shirt": APRON, "pants": Color(0.28, 0.3, 0.38), "skin": 2, "hat": "cap", "hat_color": Color(0.74, 0.38, 0.1), "after_hours": true},
	"rusty": {"shirt": Color(0.3, 0.42, 0.62), "pants": Color(0.26, 0.36, 0.55), "skin": 1, "hat": "cap", "hat_color": Color(0.55, 0.22, 0.12), "after_hours": false},
	"dot": {"shirt": Color(0.96, 0.95, 0.9), "pants": Color(0.2, 0.2, 0.24), "skin": 3, "hat": "cap", "hat_color": Color(0.98, 0.8, 0.2), "after_hours": false},
}
## The caption's size on screen at the normal caption size (Settings.caption_scale()).
## Presentation, not tuning: it matches the homeowner caption (docs/DECISIONS.md).
const CAPTION_PIXEL_SIZE: float = 0.0011

## Which shop this keeper runs (a Catalog.SHOPS id). Set before adding it.
var shop_id: String = "homie_depot"
## Whose lines and look these are (Catalog.SHOPS[shop_id].keeper), set in _ready.
var keeper: String = "marty"
## The last line said on this peer, and why (for tests and the probe).
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
## The local player was taken to Annex B (Zone.BORDER) and the keeper hasn't said the after-raid line yet.
var _was_raided: bool = false


func _ready() -> void:
	keeper = str((Catalog.SHOPS.get(shop_id, {}) as Dictionary).get("keeper", "marty"))
	if not KEEPERS.has(keeper):
		keeper = "marty"
	add_to_group("prompt_sources")
	add_to_group("shopkeepers")
	if shop_id == "homie_depot":
		add_to_group("store_clerk")
	var look: Dictionary = KEEPERS[keeper]
	_body = _CartoonBody.new()
	_body.name = "CartoonBody"
	_body.set("shirt", look["shirt"])
	_body.set("pants", look["pants"])
	_body.set("skin", _CartoonBody.SKIN_TONES[int(look["skin"])])
	_body.set("hat_style", look["hat"])
	_body.set("hat_color", look["hat_color"])
	add_child(_body)
	_body.call("build")
	var life := _CharacterLife.new()
	life.name = "Life"
	life.root = self
	life.body = _body
	life.role = "clerk"
	_body.add_child(life)
	_tag = Label3D.new()
	_tag.text = str(_Strings.SHOP_UI.get("keeper_" + keeper, keeper))
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
	visible = is_present()


## The shop prompt while the local player is at the counter: "Shop", or
## "Closed. Opens 7 AM" after hours. That one is a plain notice (no key label)
## only when nobody's behind the counter; Marty stays after hours and E still
## gets you his shutter and a closed line, so his keeps the key. Nothing for a
## shop the rank hasn't opened.
func prompt() -> Dictionary:
	if not _local_in_reach() or not _unlocked():
		return {}
	var at := global_position + Vector3(0.0, 2.6, 0.0)
	if not is_open():
		var shops := _shops()
		var opens := str(shops.call("opens_text", shop_id)) if shops != null else ""
		return {"text": str(_Strings.SHOP_UI["prompt_shop_closed"]) % opens, "at": at, "plain": not is_present()}
	return {"text": _Strings.UI["prompt_shop"], "at": at}


## Whether the shop is open by the clock (Shops.is_open; open when there's no Shops).
func is_open() -> bool:
	var shops := _shops()
	return shops == null or bool(shops.call("is_open", shop_id))


## Whether this keeper is behind the counter right now: their shop is unlocked,
## and open, or it's Marty, who never leaves.
func is_present() -> bool:
	if not _unlocked():
		return false
	return is_open() or bool((KEEPERS[keeper] as Dictionary).get("after_hours", false))


## Say a line for this trigger (TRIGGERS): a caption over the head, with babble.
func say_line(trigger: String) -> void:
	var by_trigger: Dictionary = _Strings.KEEPER_LINES.get(keeper, {})
	var lines: Array = by_trigger.get(trigger, by_trigger.get("greet", []))
	if lines.is_empty():
		chatter()
		return
	last_trigger = trigger
	last_line = str(lines[randi() % lines.size()])
	_caption.text = last_line
	_caption_left = Constants.CLERK_CAPTION_SECONDS
	chatter()


## A sale the host confirmed at this keeper's shop: the "buy" line, and the
## cash drawer slamming shut right after the register (audio/cue_hooks.gd).
func on_sale() -> void:
	say_line("buy")
	if Net.is_automated() or not is_inside_tree():
		return
	get_tree().create_timer(Constants.SHOP_DRAWER_DELAY_SECONDS).timeout.connect(func() -> void:
		var sfx := get_tree().get_first_node_in_group("sfx") if is_inside_tree() else null
		if sfx != null:
			sfx.call("play_at", "cash_drawer", global_position + Vector3(0.0, 1.0, 0.0))
	)


## What this keeper is saying right now: the last line while its caption is
## still up, else "" (the shop window's header shows it, so an old line from
## earlier in the day never turns up there).
func current_line() -> String:
	return last_line if _caption_left > 0.0 else ""


## Babble something, with the mouth moving, in this keeper's voice. Called with every line.
func chatter() -> void:
	if Net.is_automated():
		return
	var stream := load("res://assets/audio/sfx/babble_%d.wav" % randi_range(1, 5)) as AudioStream
	if stream == null:
		return
	_voice.stream = stream
	_voice.pitch_scale = float(Constants.KEEPER_VOICE_PITCH.get(keeper, 1.0)) * randf_range(0.95, 1.08)
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
	return "open" if is_open() else "closed"


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or not _local_in_reach() or not is_present():
		return
	var ui := get_tree().get_first_node_in_group("game_ui")
	if ui != null and bool(ui.call("any_window_open")):
		return
	if ui != null:
		# The line first, so the window opens with it in its header.
		say_line(open_trigger())
		ui.call("open_shop", shop_id)
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	visible = is_present()
	if not visible:
		_caption_left = 0.0
		_local_was_near = false
		return
	var nearest := _nearest_player()
	if nearest != null:
		# Turn toward them. Bodies face -Z, so look away from the target to face it.
		var to := nearest.global_position - global_position
		var yaw := atan2(-to.x, -to.z)
		rotation.y = lerp_angle(rotation.y, yaw, clampf(delta * 4.0, 0.0, 1.0))
	var near := _local_in_reach()
	var now := Time.get_ticks_msec() / 1000.0
	if near and not _local_was_near and now - _greeted_at > Constants.KEEPER_GREET_COOLDOWN_SECONDS:
		_greeted_at = now
		_greet()
	_local_was_near = near
	_caption_left = maxf(0.0, _caption_left - delta)
	var captions_on := bool(Settings.get_value("interface", "captions"))
	_caption.visible = _caption_left > 0.0 and captions_on
	_caption.pixel_size = CAPTION_PIXEL_SIZE * Settings.caption_scale()
	# The name steps aside while they talk, so the two don't pile up.
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


func _unlocked() -> bool:
	var shops := _shops()
	return shops == null or bool(shops.call("is_unlocked", shop_id))


## Whether the local player stands at this shop's counter: within SHOP_REACH of
## its Constants.SHOP_SITES counter (the spot the host checks a buy against,
## net/shops/shops.gd _near_site, less the host's lag slack), or of the keeper.
func _local_in_reach() -> bool:
	var local := _player(Net.local_peer_id())
	if local == null:
		return false
	if _flat_distance(local.global_position, global_position) <= Constants.SHOP_REACH:
		return true
	var site: Dictionary = Constants.SHOP_SITES.get(shop_id, {})
	var zone := get_parent() as Node3D
	if not site.has("counter") or zone == null:
		return false
	return _flat_distance(local.global_position, zone.to_global(site["counter"])) <= Constants.SHOP_REACH


func _nearest_player() -> Node3D:
	var best: Node3D = null
	var best_distance := Constants.KEEPER_NOTICE_RANGE
	for node: Node in get_tree().get_nodes_in_group("players"):
		var body := node as Node3D
		if body == null:
			continue
		var distance := _flat_distance(body.global_position, global_position)
		if distance < best_distance:
			best = body
			best_distance = distance
	return best


func _player(peer_id: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node as Node3D
	return null


func _shops() -> Node:
	return get_tree().get_first_node_in_group("shops") if is_inside_tree() else null


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
