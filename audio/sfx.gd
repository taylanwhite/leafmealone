extends Node

## Local presentation. The sound-effects player, the node in group "sfx" at
## UIRoot/Audio/Sfx (made by audio/audio_root.gd, so menus have sound too).
## Every id comes from audio/sound_bank.gd: its files (sounds are synthesized by
## tools/make_sfx.py and tools/make_loops.py), its bus, and its gap. Frequent
## sounds have variants and every play gets a slight pitch wobble, so repeats
## don't sound like the same file over and over.
##   play(id, db)                    2D, heard the same everywhere (UI, HUD cues)
##   play_at(id, at, db, wobble)     positional, heard only near where it happened
##   play_on(id, node, db, wobble)   positional and moving with node (a truck)
## Headless runs (tests, bots) make no players, but every play is still logged
## (log), and the positional ones also land in placed, with where they played.

const _Bank = preload("res://audio/sound_bank.gd")
## How many recent plays log keeps.
const LOG_SIZE: int = 200

## The ids played most recently, oldest first, for tests and the probe.
static var log: Array[String] = []
## Ids something asked for that sound_bank.gd doesn't have (each once).
static var unknown: Array[String] = []
## The recent positional plays, oldest first, kept even headless so tests can
## tell a positional sound from a 2D one: {"id", "kind" ("at" or "on"), "at"
## (where it played), "node" (the path it rides on, "" for "at")}.
static var placed: Array[Dictionary] = []
## Dev only: the playtest recorder's hook (net/dev/recorder.gd), called the
## moment a play is accepted, so the recorder files it under the frame it
## happened in: (id, "", ZERO) for every play, then (id, "at" or "on", where)
## for a positional one.
static var on_play: Callable = Callable()

var _next_msec: Dictionary = {}
var _last_variant: Dictionary = {}


func _ready() -> void:
	add_to_group("sfx")


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
	player.volume_db = _Bank.db(id) + db
	player.pitch_scale = randf_range(Constants.SFX_PITCH_WOBBLE.x, Constants.SFX_PITCH_WOBBLE.y)
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()


## A one-shot heard from where it happened (Constants.SFX_MAX_DISTANCE reach).
## Without a world (the menu) it plays 2D instead.
func play_at(id: String, at: Vector3, db := 0.0, wobble := true) -> void:
	var world := get_tree().get_first_node_in_group("world") as Node3D
	if world == null:
		play(id, db)
		return
	if not _accept(id):
		return
	_note_placed(id, "at", at, "")
	if _silent():
		return
	var player := _player_3d(id, db, wobble)
	if player == null:
		return
	world.add_child(player)
	player.global_position = at
	player.play()


## A one-shot that rides along with node, like a truck pulling away.
## wobble false keeps the pitch exact, for a sound timed to an animation.
func play_on(id: String, node: Node3D, db := 0.0, wobble := true) -> void:
	if node == null or not node.is_inside_tree():
		play(id, db)
		return
	if not _accept(id):
		return
	_note_placed(id, "on", node.global_position, str(node.get_path()))
	if _silent():
		return
	var player := _player_3d(id, db, wobble)
	if player == null:
		return
	node.add_child(player)
	player.play()


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


## Logs the play unless the id played too recently. False when throttled.
func _accept(id: String) -> bool:
	if not _Bank.has(id):
		_note_unknown(id)
	var now := Time.get_ticks_msec()
	if int(_next_msec.get(id, 0)) > now:
		return false
	_next_msec[id] = now + _Bank.gap_ms(id)
	log.append(id)
	if log.size() > LOG_SIZE:
		log.pop_front()
	if on_play.is_valid():
		on_play.call(id, "", Vector3.ZERO)
	return true


static func _note_placed(id: String, kind: String, at: Vector3, node_path: String) -> void:
	placed.append({"id": id, "kind": kind, "at": at, "node": node_path})
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


func _player_3d(id: String, db: float, wobble: bool) -> AudioStreamPlayer3D:
	var stream := _stream(id)
	if stream == null:
		return null
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.bus = _Bank.bus(id)
	player.volume_db = _Bank.db(id) + db
	player.unit_size = Constants.SFX_UNIT_SIZE
	player.max_distance = Constants.SFX_MAX_DISTANCE
	if wobble:
		player.pitch_scale = randf_range(Constants.SFX_PITCH_WOBBLE.x, Constants.SFX_PITCH_WOBBLE.y)
	player.finished.connect(player.queue_free)
	# Let go of the stream if the world goes first, or it outlives the engine at quit.
	player.tree_exiting.connect(func() -> void:
		player.stop()
		player.stream = null
	)
	return player


## A random variant's stream, never the same one twice in a row. Ids missing
## from the bank still play if <id>.wav exists.
func _stream(id: String) -> AudioStream:
	var paths := _Bank.files(id)
	var pick := 0
	if paths.size() > 1:
		pick = randi_range(0, paths.size() - 1)
		if pick == int(_last_variant.get(id, -1)):
			pick = (pick + 1) % paths.size()
		_last_variant[id] = pick
	if not ResourceLoader.exists(paths[pick]):
		return null
	return load(paths[pick]) as AudioStream
