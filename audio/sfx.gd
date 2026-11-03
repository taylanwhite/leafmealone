extends Node

## Local presentation. The sound-effects player, the node in group "sfx" at
## UIRoot/Audio/Sfx (made by audio/audio_root.gd, so menus have sound too).
## Every id comes from audio/sound_bank.gd: its files (sounds are synthesized by
## tools/make_sfx.py and tools/make_loops.py), its bus, and its gap. Frequent
## sounds have variants and every play gets a slight pitch wobble, so repeats
## don't sound like the same file over and over.
##   play(id, db)                    2D, heard the same everywhere (UI, HUD cues)
##   play_at(id, at, db, wobble, source, pitch)
##                                   positional, heard only near where it happened;
##                                   source keys the gap throttle (two players'
##                                   rakes don't silence each other; 0 = the id
##                                   alone), pitch multiplies the wobble
##   play_on(id, node, db, wobble)   positional and moving with node (a truck)
## The bank can give an id its own wobble, volume jitter, reach and a shuffle bag
## of variants (audio/sound_bank.gd). Its child LeafAudio (audio/leaf_audio.gd)
## plays the rake and leaf sounds from the leaf field's stroke events.
## Headless runs (tests, bots) make no players, but every play is still logged
## (log), and the positional ones also land in placed, with where they played.

const _Bank = preload("res://audio/sound_bank.gd")
const _LeafAudio = preload("res://audio/leaf_audio.gd")
## How many recent plays log keeps.
const LOG_SIZE: int = 200

## The ids played most recently, oldest first, for tests and the probe.
static var log: Array[String] = []
## Ids something asked for that sound_bank.gd doesn't have (each once).
static var unknown: Array[String] = []
## The recent positional plays, oldest first, kept even headless so tests can
## tell a positional sound from a 2D one: {"id", "kind" ("at" or "on"), "at"
## (where it played), "node" (the path it rides on, "" for "at"), "db" and
## "pitch" (what the caller asked for, before the bank's own)}.
static var placed: Array[Dictionary] = []
## Dev only: the playtest recorder's hook (net/dev/recorder.gd), called the
## moment a play is accepted, so the recorder files it under the frame it
## happened in: (id, "", ZERO) for every play, then (id, "at" or "on", where)
## for a positional one.
static var on_play: Callable = Callable()

var _next_msec: Dictionary = {}
var _last_variant: Dictionary = {}
## id -> the variants (0-based) still in its shuffle bag.
var _bags: Dictionary = {}


func _ready() -> void:
	add_to_group("sfx")
	var leaf_audio := _LeafAudio.new()
	leaf_audio.name = "LeafAudio"
	add_child(leaf_audio)


func _exit_tree() -> void:
	for child: Node in get_children():
		if child is AudioStreamPlayer:
			var player := child as AudioStreamPlayer
			player.stop()
			player.stream = null
			player.free()


func play(id: String, db := 0.0) -> void:
	if not _accept(id) or _silent():
		return
	var stream := _stream(id)
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = _Bank.bus(id)
	player.volume_db = _Bank.db(id) + db + _jitter(id)
	var range_ := _Bank.wobble(id)
	player.pitch_scale = randf_range(range_.x, range_.y)
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()


## A one-shot heard from where it happened (the bank's reach, by default
## Constants.SFX_MAX_DISTANCE). Without a world (the menu) it plays 2D instead.
## source keys the gap throttle with the id (a raker's peer id, say), so one
## source's repeats are held to the id's gap and other sources still play.
func play_at(id: String, at: Vector3, db := 0.0, wobble := true, source := 0, pitch := 1.0) -> void:
	var world := get_tree().get_first_node_in_group("world") as Node3D
	if world == null:
		play(id, db)
		return
	if not _accept(id, source):
		return
	_note_placed(id, "at", at, "", db, pitch)
	if _silent():
		return
	var player := _player_3d(id, db, wobble, pitch)
	if player == null:
		return
	world.add_child(player)
	player.global_position = at
	player.play()
	_start_now(player)


## A one-shot that rides along with node, like a truck pulling away.
## wobble false keeps the pitch exact, for a sound timed to an animation.
func play_on(id: String, node: Node3D, db := 0.0, wobble := true) -> void:
	if node == null or not node.is_inside_tree():
		play(id, db)
		return
	if not _accept(id):
		return
	_note_placed(id, "on", node.global_position, str(node.get_path()), db)
	if _silent():
		return
	var player := _player_3d(id, db, wobble)
	if player == null:
		return
	node.add_child(player)
	player.play()
	_start_now(player)


## A sound set to loop forever, for engines, sprays, wind, and music. The files
## are made seamless by tools/make_loops.py. Takes a bank id or a res:// path.
## Each caller gets its own copy; the sample data itself is shared.
static func looped(id_or_path: String) -> AudioStream:
	var path := id_or_path if id_or_path.begins_with("res://") else _Bank.files(id_or_path)[0]
	if not id_or_path.begins_with("res://") and not _Bank.has(id_or_path):
		_note_unknown(id_or_path)
	var wav := load(path) as AudioStreamWAV if ResourceLoader.exists(path) else null
	if wav == null:
		return null
	var copy := wav.duplicate() as AudioStreamWAV
	copy.loop_mode = AudioStreamWAV.LOOP_FORWARD
	copy.loop_begin = 0
	copy.loop_end = int(round(wav.get_length() * wav.mix_rate))
	return copy


## Logs the play unless the id played too recently (from this source, when one
## is given). False when throttled.
func _accept(id: String, source := 0) -> bool:
	if not _Bank.has(id):
		_note_unknown(id)
	var now := Time.get_ticks_msec()
	var key := id if source == 0 else "%s:%d" % [id, source]
	if int(_next_msec.get(key, 0)) > now:
		return false
	_next_msec[key] = now + _Bank.gap_ms(id)
	log.append(id)
	if log.size() > LOG_SIZE:
		log.pop_front()
	if on_play.is_valid():
		on_play.call(id, "", Vector3.ZERO)
	return true


static func _note_placed(id: String, kind: String, at: Vector3, node_path: String, db := 0.0, pitch := 1.0) -> void:
	placed.append({"id": id, "kind": kind, "at": at, "node": node_path, "db": db, "pitch": pitch})
	if placed.size() > LOG_SIZE:
		placed.pop_front()
	if on_play.is_valid():
		on_play.call(id, kind, at)


## Nobody hears a headless run or the smoke test, so nothing is made there.
func _silent() -> bool:
	return Net.is_automated() or DisplayServer.get_name() == "headless"


static func _note_unknown(id: String) -> void:
	if not unknown.has(id):
		unknown.append(id)
		push_warning("[Sfx] '%s' is not in audio/sound_bank.gd" % id)


func _player_3d(id: String, db: float, wobble: bool, pitch := 1.0) -> AudioStreamPlayer3D:
	var stream := _stream(id)
	if stream == null:
		return null
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	configure_3d(player, id, db, wobble, pitch)
	player.finished.connect(player.queue_free)
	# Let go of the stream if the world goes first, or it outlives the engine at quit.
	player.tree_exiting.connect(func() -> void:
		player.stop()
		player.stream = null
	)
	return player


## Godot starts an AudioStreamPlayer3D's sound on its next internal physics
## tick, not in play(): asked for from _process or a network message, it starts a
## whole frame late (33 ms at 30 fps; measured in R1b, docs/DECISIONS.md "Audio:
## positional sounds start when asked"). Running that tick's notification now
## starts it in the very next mix, the way a 2D player does; the real tick later
## only updates its panning.
static func _start_now(player: AudioStreamPlayer3D) -> void:
	if player.is_inside_tree():
		player.notification(Node.NOTIFICATION_INTERNAL_PHYSICS_PROCESS)


## Sets a positional player up for id from the bank: its bus, volume (plus db
## and the id's jitter), reach, its loudest up close, and pitch (pitch times the
## id's wobble). Static and stream-free so --audio-test can check it headless.
static func configure_3d(player: AudioStreamPlayer3D, id: String, db: float, wobble: bool, pitch := 1.0) -> void:
	player.bus = _Bank.bus(id)
	player.volume_db = _Bank.db(id) + db + _jitter(id)
	player.unit_size = _Bank.unit_size(id)
	player.max_distance = _Bank.max_distance(id)
	# Godot caps distance gain plus volume at max_db (3 dB unless set), which
	# flattens every trim on a sound heard up close; an id with near_db is
	# capped relative to its own volume instead, so its trims survive.
	if _Bank.has_near_db(id):
		player.max_db = player.volume_db + _Bank.near_db(id)
	# Godot also low-passes a sound by how far under full volume it is (-24 dB at
	# 5 kHz by default, its volume trim included), which takes a quiet crackle's
	# clicks away even up close; an id with muffle_db is muffled at most that much.
	if _Bank.has_muffle_db(id):
		player.attenuation_filter_db = _Bank.muffle_db(id)
	var range_ := _Bank.wobble(id)
	player.pitch_scale = maxf(0.05, pitch * (randf_range(range_.x, range_.y) if wobble else 1.0))


## A random variant's stream, never the same one twice in a row. Ids missing
## from the bank still play if <id>.wav exists.
func _stream(id: String) -> AudioStream:
	var paths := _Bank.files(id)
	var pick := 0
	if paths.size() > 1:
		if _Bank.shuffle(id):
			pick = pick_variant(id, paths.size())
		else:
			pick = randi_range(0, paths.size() - 1)
			if pick == int(_last_variant.get(id, -1)):
				pick = (pick + 1) % paths.size()
		_last_variant[id] = pick
	if not ResourceLoader.exists(paths[pick]):
		return null
	return load(paths[pick]) as AudioStream


## The next variant (0-based) from id's shuffle bag: every variant once per
## refill, in a random order, and never the one just played across a refill.
func pick_variant(id: String, count: int) -> int:
	var bag: Array = _bags.get(id, [])
	if bag.is_empty():
		for index: int in count:
			bag.append(index)
		bag.shuffle()
		# The bag is drawn from the back: keep the one just played off the top.
		var last := int(_last_variant.get(id, -1))
		if count > 1 and int(bag.back()) == last:
			bag.push_front(bag.pop_back())
	var pick := int(bag.pop_back())
	_bags[id] = bag
	_last_variant[id] = pick
	return pick


## A random volume nudge within the id's db_jitter (0 for most ids).
static func _jitter(id: String) -> float:
	var j := _Bank.db_jitter(id)
	return randf_range(-j, j) if j > 0.0 else 0.0
