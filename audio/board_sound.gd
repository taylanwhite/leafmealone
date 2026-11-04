extends Node3D

## Local presentation. A skateboard's sound (gap-specs/audio.json chunk 7, critic
## C13; docs/DECISIONS.md "Audio: the engine and the board are components"). Hang
## it on the drawn board and it rolls and grinds from the rider's board_state():
## {on_board, speed (m/s along the ground), on_ground, grinding}, read from
## state_source if set, else from parent.board_state().
##
##   rolling   board_roll_loop, louder and higher with speed (SKATE_ROLL_DB,
##             SKATE_ROLL_PITCH up to SKATE_MAX_PUSH_SPEED), cut the moment the
##             board leaves the ground or starts grinding
##   grinding  board_grind_loop, louder with speed (SKATE_GRIND_DB)
##   pop(), land(impact 0..1), bail()   board_pop, board_land, wipeout
## With auto_edges on it pops and lands by itself on on_ground's edges (a landing
## is as heavy as the air was long), so a board needs nothing but this attached.
## player/skate_view.gd turns auto_edges off: it plays the pop and the landing on
## the frames the drawn board does them, and hands this the drawn state.
## Headless runs make no players; the one-shots still reach Sfx, which logs them.

const _Bank = preload("res://audio/sound_bank.gd")
const _SfxScript = preload("res://audio/sfx.gd")

## Returns board_state()'s dictionary; unset, the parent's board_state() is read.
var state_source: Callable = Callable()
## Pop and land by themselves on on_ground's edges.
var auto_edges: bool = true

var _roll: AudioStreamPlayer3D
var _grind: AudioStreamPlayer3D
var _primed: bool = false
var _was_on: bool = false
var _was_ground: bool = true
var _air_time: float = 0.0
var _mix: Dictionary = {}


func _ready() -> void:
	if _silent():
		return
	_roll = _loop("board_roll_loop", "Roll")
	_grind = _loop("board_grind_loop", "Grind")


func _exit_tree() -> void:
	for player: AudioStreamPlayer3D in [_roll, _grind]:
		if player != null:
			player.stop()
			player.stream = null


## Every frame, after the physics ticks that moved the board.
func _process(delta: float) -> void:
	var state := read_state()
	var on := bool(state.get("on_board", false))
	var ground := bool(state.get("on_ground", true))
	if not _primed:
		_primed = true
	elif auto_edges and on and _was_on:
		if _was_ground and not ground:
			pop()
		elif not _was_ground and ground:
			land(clampf(_air_time / Constants.BOARD_LAND_FULL_AIR, 0.0, 1.0))
	_air_time = 0.0 if ground or not on else _air_time + delta
	_was_on = on
	_was_ground = ground
	_mix = mix(state)
	if _roll != null:
		var ease := 1.0 - exp(-Constants.BOARD_LOOP_FADE * delta)
		_drive(_roll, float(_mix["roll_db"]), float(_mix["roll_pitch"]), ease)
		_drive(_grind, float(_mix["grind_db"]), 1.0, ease)


func read_state() -> Dictionary:
	if state_source.is_valid():
		return state_source.call()
	if get_parent() != null and get_parent().has_method("board_state"):
		return get_parent().call("board_state")
	return {}


## The loops' targets for a state: dB (BOARD_SILENT_DB when not heard) and the
## roll's pitch.
static func mix(state: Dictionary) -> Dictionary:
	var on := bool(state.get("on_board", false))
	var ground := bool(state.get("on_ground", true))
	var grinding := on and bool(state.get("grinding", false))
	var speed := float(state.get("speed", 0.0))
	var share := clampf(speed / Constants.SKATE_MAX_PUSH_SPEED, 0.0, 1.0)
	var rolling := on and ground and not grinding and speed > Constants.BOARD_ROLL_MIN_SPEED
	return {
		"roll_db": lerpf(Constants.SKATE_ROLL_DB.x, Constants.SKATE_ROLL_DB.y, share) if rolling else Constants.BOARD_SILENT_DB,
		"roll_pitch": lerpf(Constants.SKATE_ROLL_PITCH.x, Constants.SKATE_ROLL_PITCH.y, share),
		"grind_db": lerpf(Constants.SKATE_GRIND_DB.x, Constants.SKATE_GRIND_DB.y, share) if grinding else Constants.BOARD_SILENT_DB,
	}


func current_mix() -> Dictionary:
	return _mix.duplicate()


## The tail cracks: an ollie, or hopping off.
func pop(db := 0.0) -> void:
	_play("board_pop", db)


## Four wheels back down; impact 0 (a hop) to 1 (a big air).
func land(impact := 1.0) -> void:
	_play("board_land", lerpf(Constants.BOARD_LAND_DB.x, Constants.BOARD_LAND_DB.y, clampf(impact, 0.0, 1.0)))


func bail() -> void:
	_play("wipeout")


func _drive(player: AudioStreamPlayer3D, db: float, pitch: float, ease: float) -> void:
	if player.stream == null:
		return
	var wanted := db > Constants.BOARD_SILENT_DB
	if wanted and not player.playing:
		player.volume_db = Constants.BOARD_SILENT_DB
		player.play(randf() * player.stream.get_length())
	if not player.playing:
		return
	player.volume_db = lerpf(player.volume_db, db, ease)
	player.pitch_scale = maxf(0.05, lerpf(player.pitch_scale, pitch, ease))
	if not wanted and player.volume_db <= Constants.BOARD_SILENT_DB + 1.0:
		player.stop()


func _loop(id: String, node_name: String) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = node_name
	player.stream = _SfxScript.looped(id)
	player.bus = _Bank.bus(id)
	player.unit_size = Constants.SFX_UNIT_SIZE
	player.max_distance = Constants.SKATE_SOUND_MAX_DISTANCE
	player.volume_db = Constants.BOARD_SILENT_DB
	add_child(player)
	return player


func _play(id: String, db := 0.0) -> void:
	var sfx := get_tree().get_first_node_in_group("sfx") if is_inside_tree() else null
	if sfx != null:
		sfx.call("play_on", id, self, db, true, get_instance_id())


func _silent() -> bool:
	return Net.is_automated() or DisplayServer.get_name() == "headless"
