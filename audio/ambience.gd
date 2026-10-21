extends Node

## Local presentation. The neighborhood's background sound around the local
## player: a breeze through the trees, birds now and then, a dog a few yards
## over, a car going by on the lot's street, and a laid-back music loop that M
## turns off and on (remembered between sessions). Nothing here is shared.

const _Sfx = preload("res://audio/sfx.gd")
const _Neighborhood = preload("res://levels/dressing/neighborhood.gd")

const SETTINGS_PATH := "user://settings.cfg"
const WIND_DB := -14.0
const MUSIC_DB := -15.0
## Seconds between one-shots, as a random range.
const BIRD_GAP := Vector2(3.0, 9.0)
const DOG_GAP := Vector2(25.0, 70.0)
const CAR_GAP := Vector2(14.0, 35.0)
## How far along the street a passing car starts and ends, either side of the lot.
const CAR_RUN := 55.0
const CAR_SECONDS := 4.0

var _wind: AudioStreamPlayer
var _music: AudioStreamPlayer
var _music_on: bool = true
var _waits: Dictionary = {}
var _car: AudioStreamPlayer3D
var _car_t: float = -1.0
var _car_from := Vector3.ZERO
var _car_to := Vector3.ZERO


func _ready() -> void:
	# Nobody hears a headless run (tests, bots), so don't play anything there.
	if Net.is_automated() or DisplayServer.get_name() == "headless":
		set_process(false)
		set_process_unhandled_input(false)
		return
	_wind = _loop_player("wind_loop", WIND_DB)
	_music = _loop_player("music_loop", MUSIC_DB)
	var settings := ConfigFile.new()
	if settings.load(SETTINGS_PATH) == OK:
		_music_on = bool(settings.get_value("audio", "music", true))
	if not _music_on:
		_music.stop()
	_waits = {"bird": randf_range(1.0, 4.0), "dog": randf_range(DOG_GAP.x, DOG_GAP.y), "car": randf_range(4.0, CAR_GAP.y)}
	_car = AudioStreamPlayer3D.new()
	_car.stream = load("res://assets/audio/sfx/car_pass.wav")
	_car.unit_size = 10.0
	_car.max_distance = 80.0
	add_child(_car)


## Let go of every sound on the way out, or they outlive the engine at quit.
func _exit_tree() -> void:
	for child: Node in get_children():
		if child is AudioStreamPlayer:
			(child as AudioStreamPlayer).stop()
			(child as AudioStreamPlayer).stream = null
		elif child is AudioStreamPlayer3D:
			(child as AudioStreamPlayer3D).stop()
			(child as AudioStreamPlayer3D).stream = null
		child.free()


func _loop_player(sound_name: String, db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = _Sfx.looped(sound_name)
	player.volume_db = db
	add_child(player)
	player.play()
	return player


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_music"):
		_music_on = not _music_on
		if _music_on:
			_music.play()
		else:
			_music.stop()
		var settings := ConfigFile.new()
		settings.load(SETTINGS_PATH)
		settings.set_value("audio", "music", _music_on)
		settings.save(SETTINGS_PATH)


func _process(delta: float) -> void:
	var me := _local_player()
	if me == null:
		return
	var zone := Net.player_zone(me.name.to_int())
	# Wind is quieter in transit and at the border's lanes.
	_wind.volume_db = WIND_DB if zone == Net.Zone.LOT or zone == Net.Zone.STORE else WIND_DB - 8.0
	for key: String in _waits:
		_waits[key] = float(_waits[key]) - delta
	if float(_waits["bird"]) <= 0.0:
		_waits["bird"] = randf_range(BIRD_GAP.x, BIRD_GAP.y)
		if zone != Net.Zone.TRANSIT:
			_one_shot("bird_%d" % randi_range(1, 4), me.global_position + _around(8.0, 22.0) + Vector3(0.0, randf_range(4.0, 9.0), 0.0), -6.0)
	if float(_waits["dog"]) <= 0.0:
		_waits["dog"] = randf_range(DOG_GAP.x, DOG_GAP.y)
		if zone == Net.Zone.LOT:
			_one_shot("dog", me.global_position + _around(25.0, 40.0), -4.0)
	if float(_waits["car"]) <= 0.0:
		_waits["car"] = randf_range(CAR_GAP.x, CAR_GAP.y)
		if zone == Net.Zone.LOT and _car_t < 0.0:
			_start_car()
	if _car_t >= 0.0:
		_car_t += delta / CAR_SECONDS
		_car.global_position = _car_from.lerp(_car_to, clampf(_car_t, 0.0, 1.0))
		if _car_t >= 1.0:
			_car_t = -1.0


## A car drives along the far lane of the lot's street, past the yard.
func _start_car() -> void:
	var world := get_tree().get_first_node_in_group("world")
	var lot := world.get_node_or_null("LotZone") as Node3D if world != null else null
	if lot == null:
		return
	var lane := _Neighborhood.STREET.y - 2.2
	var direction := 1.0 if randf() < 0.5 else -1.0
	_car_from = lot.to_global(Vector3(-CAR_RUN * direction, 0.6, lane))
	_car_to = lot.to_global(Vector3(CAR_RUN * direction, 0.6, lane))
	_car_t = 0.0
	_car.global_position = _car_from
	_car.pitch_scale = randf_range(0.9, 1.1)
	_car.play()


func _one_shot(sound_name: String, at: Vector3, db: float) -> void:
	var player := AudioStreamPlayer3D.new()
	player.stream = load("res://assets/audio/sfx/%s.wav" % sound_name)
	player.volume_db = db
	player.unit_size = 12.0
	player.max_distance = 90.0
	player.pitch_scale = randf_range(0.94, 1.06)
	player.finished.connect(player.queue_free)
	add_child(player)
	player.global_position = at
	player.play()


func _around(near: float, far: float) -> Vector3:
	var angle := randf() * TAU
	return Vector3(cos(angle), 0.0, sin(angle)) * randf_range(near, far)


func _local_player() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as Node3D
	return null
