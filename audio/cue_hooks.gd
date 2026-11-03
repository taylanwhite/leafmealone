extends Node

## Local presentation. Listens to the game and fires the music director's
## stingers and the game-event sounds (docs/GAME.md "the soundtrack"). Every
## hook is an event or a replicated value this peer already has, so it adds no
## traffic (docs/DECISIONS.md "Audio: a local music director"):
##   the day ends (DayClock.day_ended)    Clock Out, then Promoted! for a rank-up,
##                                        then New Season when the summary says so
##   the summary card closes              Rise and Rake, then (once it's done) one buzz for
##                                        the night's texts
##   a text (Town.texted)                 New Client for a referral, a lead or a
##                                        client won back; a droop when TurfMasters
##                                        poach one; a buzz for the rest (one per
##                                        PHONE_BUZZ_GAP_SECONDS; a pop instead with
##                                        the phone out; held while the summary is up)
##   a confirmed buy (Shops.result "ok")  the register (never a refused one)
##   a payout (Campaign.payout_ready)     Paid
##   a task reaches done                  a ding, on the yard
##   quiet hours begin, the clock closes  two soft bongs, a yawn
##   the NICE BOYS take you               Busted, at the catch's bark (R2)
##   through the Annex's turnstile        Made It Back (R2)
## The game sounds (register, phone_buzz, ...) are audio chunk 5's (tools/sfx_ui.py,
## registered in audio/sound_bank.gd); every cue is also logged (cue_log), and one
## whose id isn't registered is only logged, never played.

const _Bank = preload("res://audio/sound_bank.gd")
const _Tracks = preload("res://audio/music_tracks.gd")
const LOG_SIZE: int = 200
## Text kinds that mean work is coming (net/town/town.gd _text).
const NEW_CLIENT_KINDS: Array[String] = ["referral", "lead", "won_back"]

## Every cue this peer fired, stingers and sounds alike, oldest first.
static var cue_log: Array[String] = []

## Texts that just came in: [{kind, at (msec)}], waiting CUE_TEXT_SETTLE_SECONDS.
var _incoming: Array[Dictionary] = []
## Kinds held while the day summary is up, played when it closes.
var _held: Array[String] = []
var _next_buzz_msec: int = 0
## msec when the morning's held buzz plays (after its stingers), or 0.
var _morning_buzz_at: int = 0
var _task_wait: float = 0.0
## task -> whether it was done at the last look; cleared when the job changes.
var _tasks_done: Dictionary = {}
var _tasks_key: String = ""
## -1 unknown, else 0/1: the last look at the clock.
var _was_quiet: int = -1
var _was_closed: int = -1


func _ready() -> void:
	for group: String in ["day_clock", "town", "shops", "day_summary"]:
		var existing := get_tree().get_first_node_in_group(group)
		if existing != null:
			_hook(existing)
	get_tree().node_added.connect(func(node: Node) -> void:
		if node.name in ["DayClock", "Town", "Shops", "DaySummary"]:
			_hook(node)
		elif node.name in ["Encounter", "RunDirector", "Annex"]:
			# Their groups are joined in _ready, a moment after they're added.
			_hook_r2.call_deferred()
	)
	Campaign.payout_ready.connect(func(_results: Array[Dictionary]) -> void: _stinger(&"st_job_paid"))
	Net.player_zone_changed.connect(_on_zone_changed)
	Net.state_changed.connect(func(_next_state: Net.State) -> void:
		_incoming.clear()
		_held.clear()
		_morning_buzz_at = 0
		_tasks_done.clear()
		_was_quiet = -1
		_was_closed = -1
	)


func _hook(node: Node) -> void:
	_connect(node, "day_ended", _on_day_ended)
	_connect(node, "texted", _on_texted)
	_connect(node, "result", _on_shop_result)
	_connect(node, "closed", _on_summary_closed)


func _connect(node: Node, signal_name: String, callable: Callable) -> void:
	if node.has_signal(signal_name) and not node.is_connected(signal_name, callable):
		node.connect(signal_name, callable)


func _process(delta: float) -> void:
	_settle_texts()
	_busted_due()
	_morning_buzz_due()
	if Net.current_state() != Net.State.IN_SESSION:
		return
	_task_wait += delta
	if _task_wait >= Constants.CUE_TASK_POLL_SECONDS:
		_task_wait = 0.0
		_watch_tasks()
		_watch_clock()


# ---------------------------------------------------------------- the day

func _on_day_ended(summary: Dictionary) -> void:
	# The night's texts came in just before the card: they wait for it.
	for text: Dictionary in _incoming:
		_held.append(str(text["kind"]))
	_incoming.clear()
	_stinger(&"st_day_end")
	if not (summary.get("rank_ups", []) as Array).is_empty():
		_stinger(&"st_rank_up")
	if summary.has("season"):
		_stinger(&"st_season")


func _on_summary_closed() -> void:
	_stinger(&"st_morning")
	var after := _Tracks.seconds(&"st_morning")
	if _held.any(func(kind: String) -> bool: return NEW_CLIENT_KINDS.has(kind)):
		_stinger(&"st_new_client")
		after += _Tracks.seconds(&"st_new_client")
	# The buzz waits for the stingers to finish (audio:5): a phone rattling under
	# the kazoo rooster was neither.
	if not _held.is_empty():
		_morning_buzz_at = Time.get_ticks_msec() + int((after + Constants.CUE_BUZZ_AFTER_STINGERS) * 1000.0)
	_held.clear()


## The held morning buzz, once its stingers are done.
func _morning_buzz_due() -> void:
	if _morning_buzz_at > 0 and Time.get_ticks_msec() >= _morning_buzz_at:
		_morning_buzz_at = 0
		_next_buzz_msec = 0
		_buzz()


func _watch_clock() -> void:
	var clock := get_tree().get_first_node_in_group("day_clock")
	if clock == null:
		return
	var quiet := 1 if bool(clock.call("is_quiet_hours")) else 0
	var closed := 1 if bool(clock.call("is_closed")) else 0
	if _was_quiet == 0 and quiet == 1:
		_sound("quiet_chime")
	if _was_closed == 0 and closed == 1:
		_sound("closing_yawn")
	_was_quiet = quiet
	_was_closed = closed


# ---------------------------------------------------------------- texts

func _on_texted(text: Dictionary) -> void:
	_incoming.append({"kind": str(text.get("kind", "")), "at": Time.get_ticks_msec()})


## A text waits a moment in case the day summary is right behind it (the
## morning's texts come in the same frame as the card); then it plays, or waits
## for the card to close.
func _settle_texts() -> void:
	if _incoming.is_empty():
		return
	var now := Time.get_ticks_msec()
	var settle := int(Constants.CUE_TEXT_SETTLE_SECONDS * 1000.0)
	while not _incoming.is_empty() and now - int(_incoming[0]["at"]) >= settle:
		var kind := str(_incoming.pop_front()["kind"])
		if _summary_open():
			_held.append(kind)
		else:
			_text_cue(kind)


func _text_cue(kind: String) -> void:
	if NEW_CLIENT_KINDS.has(kind):
		_stinger(&"st_new_client")
	if kind == "poached":
		_sound("text_bad")
	elif _phone_open():
		_sound("text_pop")
	else:
		_buzz()


func _buzz() -> void:
	var now := Time.get_ticks_msec()
	if now < _next_buzz_msec:
		return
	_next_buzz_msec = now + int(Constants.PHONE_BUZZ_GAP_SECONDS * 1000.0)
	_sound("phone_buzz")


# ---------------------------------------------------------------- money and work

func _on_shop_result(code: String, item_id: String, _amount: int) -> void:
	# Paying a crewmate isn't a purchase (shops has its own sound for that).
	# A sale to Rusty rings the register too (shops chunk 5).
	if (code == "ok" or code == "sold") and item_id != "give":
		_sound("register")


func _watch_tasks() -> void:
	var tasks := get_tree().get_first_node_in_group("job_tasks")
	if tasks == null:
		return
	var active: PackedStringArray = tasks.get("active")
	var key := ",".join(active)
	if key != _tasks_key:
		# A new job: what's already done doesn't ding.
		_tasks_key = key
		_tasks_done.clear()
	var on_lot := Net.player_zone(Net.local_peer_id()) == Net.Zone.LOT
	for task: String in active:
		var done := is_done(float(tasks.call("progress", task)))
		if _tasks_done.has(task) and done and not bool(_tasks_done[task]) and on_lot:
			_sound("task_done")
		_tasks_done[task] = done


## The task list's rule: done at TASK_DONE_PERCENT (ui/task_list.gd).
static func is_done(progress: float) -> bool:
	return int(round(progress * 100.0)) >= Constants.TASK_DONE_PERCENT


# ---------------------------------------------------------------- capture
# R2 (gap-specs nice_boys C15): Busted plays at the catch's bark, CATCH_BARK_AT
# after the hand lands (the Encounter's GOTCHA stage, or the director's
# peer_caught when there is no Encounter); Made It Back as you push through
# the Annex's turnstile. Each catch fires once, whichever tells first.

## The Encounter's Stage.GOTCHA (net/run_events/encounter.gd, not preloaded).
const STAGE_GOTCHA: int = 2

## msec when the local player's Busted plays, or 0.
var _busted_at: int = 0
## msec of the last Busted, so a second report of the same catch is ignored.
var _busted_last: int = -100000


func _on_zone_changed(peer_id: int, zone: Net.Zone) -> void:
	_hook_r2()
	# Until the run director tells of a catch (peer_caught, R2 chunk 2), the old
	# trigger stands: a captured local player carried into TRANSIT is Busted.
	if peer_id != Net.local_peer_id() or zone != Net.Zone.TRANSIT:
		return
	var director := get_tree().get_first_node_in_group("run_director")
	if director == null or director.has_signal("peer_caught") or get_tree().get_first_node_in_group("nice_encounter") != null:
		return
	if director.has_method("is_captured") and bool(director.call("is_captured", peer_id)):
		var now := Time.get_ticks_msec()
		if now - _busted_last >= 5000:
			_busted_last = now
			_stinger(&"st_busted")


## Connects to the R2 nodes once they exist (they come with the world).
func _hook_r2() -> void:
	var encounter := get_tree().get_first_node_in_group("nice_encounter")
	if encounter != null:
		_connect(encounter, "stage_changed", _on_stage_changed)
	var director := get_tree().get_first_node_in_group("run_director")
	if director != null:
		_connect(director, "peer_caught", _on_peer_caught)
	var annex := get_tree().get_first_node_in_group("annex")
	if annex != null:
		_connect(annex, "rider_through_turnstile", _on_through_turnstile)


func _on_stage_changed(peer: int, stage: int) -> void:
	if peer == Net.local_peer_id() and stage == STAGE_GOTCHA:
		_caught()


func _on_peer_caught(peer: int) -> void:
	if peer == Net.local_peer_id() and get_tree().get_first_node_in_group("nice_encounter") == null:
		_caught()


func _caught() -> void:
	var now := Time.get_ticks_msec()
	if now - _busted_last < 5000:
		return
	_busted_last = now
	_busted_at = now + int(_busted_after() * 1000.0)


static func _busted_after() -> float:
	var constants: Dictionary = (Constants as Script).get_script_constant_map()
	return float(constants.get("CATCH_BARK_AT", Constants.CUE_BUSTED_AFTER_FALLBACK))


func _on_through_turnstile(peer: int) -> void:
	if peer == Net.local_peer_id():
		_stinger(&"st_made_it")


func _busted_due() -> void:
	if _busted_at > 0 and Time.get_ticks_msec() >= _busted_at:
		_busted_at = 0
		_stinger(&"st_busted")


# ---------------------------------------------------------------- helpers

func _stinger(id: StringName) -> void:
	_log(String(id))
	var music := get_tree().get_first_node_in_group("music_director")
	if music != null:
		music.call("stinger", id)


## Logs the cue, and plays it if audio/sound_bank.gd has it yet.
func _sound(id: String) -> void:
	_log(id)
	if not _Bank.has(id):
		return
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play", id)


func _log(id: String) -> void:
	cue_log.append(id)
	if cue_log.size() > LOG_SIZE:
		cue_log.pop_front()


func _summary_open() -> bool:
	var summary := get_tree().get_first_node_in_group("day_summary") as CanvasItem
	return summary != null and summary.visible


func _phone_open() -> bool:
	var phone := get_tree().get_first_node_in_group("phone") as CanvasItem
	return phone != null and phone.visible
