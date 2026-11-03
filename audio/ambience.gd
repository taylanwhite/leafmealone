extends Node

## Local presentation. The neighborhood's background sound around the local
## player: a breeze through the trees, birds now and then, a dog a few yards
## over, and a car going by on the lot's street. Nothing here is shared. Its
## players sit on the Ambience bus (audio/buses.gd), and its tuning is
## Constants.AMBIENCE_*. The music, and M, are the music director's
## (audio/music_director.gd, under UIRoot/Audio).

const _Sfx = preload("res://audio/sfx.gd")
const _Bank = preload("res://audio/sound_bank.gd")
const _Neighborhood = preload("res://levels/dressing/neighborhood.gd")


var _wind: AudioStreamPlayer
## Satellite Annex B's office through the wall (R2 chunk 5): typewriters, and a
## bed set_bed() asks for (the van's cab: its radio, when it has one).
var _office: AudioStreamPlayer
var _beds: Dictionary = {}
var _waits: Dictionary = {}
var _car: AudioStreamPlayer3D
var _car_t: float = -1.0
var _car_from := Vector3.ZERO
var _car_to := Vector3.ZERO


func _ready() -> void:
	add_to_group("ambience")
	# Nobody hears a headless run (tests, bots), so don't play anything there.
	if Net.is_automated() or DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_wind = _loop_player("wind_loop", Constants.AMBIENCE_WIND_DB)
	_office = _loop_player("typewriter_bed", -80.0)
	_waits = {
		"bird": _between(Constants.AMBIENCE_FIRST_BIRD),
		"dog": _between(Constants.AMBIENCE_DOG_GAP),
		"car": _between(Constants.AMBIENCE_FIRST_CAR),
		"office_phone": _between(Constants.AMBIENCE_OFFICE_PHONE_GAP),
		"cooler": _between(Constants.AMBIENCE_OFFICE_GLUG_GAP),
	}
	_car = AudioStreamPlayer3D.new()
	_car.stream = load(_Bank.files("car_pass")[0])
	_car.bus = _Bank.bus("car_pass")
	_car.unit_size = Constants.AMBIENCE_UNIT_SIZE
	_car.max_distance = Constants.AMBIENCE_MAX_DISTANCE
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


func _loop_player(id: String, db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = _Sfx.looped(id)
	player.bus = _Bank.bus(id)
	player.volume_db = db
	add_child(player)
	player.play()
	return player


func _process(delta: float) -> void:
	var me := _local_player()
	if me == null:
		return
	var zone := Net.player_zone(me.name.to_int())
	# Wind is quieter in transit and at the border's lanes.
	# Out in the connected town (driving chunk D) sounds like the neighborhood:
	# the yard's dogs and passing cars wherever there are houses.
	var in_hood := zone == Net.Zone.LOT or (zone == Net.Zone.TOWN and _hood_index(me.global_position) >= 0)
	var outdoors := zone == Net.Zone.LOT or zone == Net.Zone.STORE or zone == Net.Zone.TOWN
	_wind.volume_db = Constants.AMBIENCE_WIND_DB + (0.0 if outdoors else Constants.AMBIENCE_WIND_AWAY_DB)
	for key: String in _waits:
		_waits[key] = float(_waits[key]) - delta
	if float(_waits["bird"]) <= 0.0:
		_waits["bird"] = _between(Constants.AMBIENCE_BIRD_GAP)
		if zone != Net.Zone.TRANSIT:
			var up := Vector3(0.0, _between(Constants.AMBIENCE_BIRD_HEIGHT), 0.0)
			_one_shot("bird", me.global_position + _around(Constants.AMBIENCE_BIRD_RANGE) + up, 0.0)
	if float(_waits["dog"]) <= 0.0:
		_waits["dog"] = _between(Constants.AMBIENCE_DOG_GAP)
		if in_hood:
			_one_shot("dog", me.global_position + _around(Constants.AMBIENCE_DOG_RANGE), 0.0)
	if float(_waits["car"]) <= 0.0:
		_waits["car"] = _between(Constants.AMBIENCE_CAR_GAP)
		if in_hood and _car_t < 0.0:
			_start_car(me.global_position)
	_annex_office(zone, delta)
	if _car_t >= 0.0:
		_car_t += delta / Constants.AMBIENCE_CAR_SECONDS
		_car.global_position = _car_from.lerp(_car_to, clampf(_car_t, 0.0, 1.0))
		if _car_t >= 1.0:
			_car_t = -1.0


## Satellite Annex B (the BORDER zone): typewriters through the wall, a phone
## ringing in the back office now and then, the water cooler's glug.
func _annex_office(zone: int, delta: float) -> void:
	var inside := zone == Net.Zone.BORDER
	_office.volume_db = move_toward(_office.volume_db, Constants.AMBIENCE_OFFICE_DB if inside else -80.0, Constants.AMBIENCE_OFFICE_FADE_DB_PER_SECOND * delta)
	if float(_waits["office_phone"]) <= 0.0:
		_waits["office_phone"] = _between(Constants.AMBIENCE_OFFICE_PHONE_GAP)
		if inside:
			_one_shot("office_phone", _annex_point("Windows/B", Vector3(0.0, 1.4, -1.6)), 0.0)
	if float(_waits["cooler"]) <= 0.0:
		_waits["cooler"] = _between(Constants.AMBIENCE_OFFICE_GLUG_GAP)
		if inside:
			_one_shot("glug", _annex_point("Cooler", Vector3(0.0, 1.0, 0.0)), -6.0)


## A point near one of the Annex's nodes (set-dressing, so it may not be there).
func _annex_point(path: String, offset: Vector3) -> Vector3:
	var world := get_tree().get_first_node_in_group("world")
	var node := world.get_node_or_null("BorderZone/AnnexSet/%s" % path) as Node3D if world != null else null
	if node == null:
		var me := _local_player()
		return me.global_position + offset if me != null else offset
	return node.global_transform * offset


## A bed of sound the music director asks for (MusicDirector.set_ambience):
## &"van_cab" plays the cab's radio when the van chunk has registered it.
func set_bed(bed: StringName, on: bool) -> void:
	var id := "radio_babble" if bed == &"van_cab" else String(bed)
	if on and not _beds.has(bed) and _Bank.has(id) and _wind != null:
		_beds[bed] = _loop_player(id, -10.0)
	elif not on and _beds.has(bed):
		var player: AudioStreamPlayer = _beds[bed]
		_beds.erase(bed)
		player.stop()
		player.stream = null
		player.queue_free()


## A car drives along the far lane of the lot's street, past the yard. In the
## connected town, along the street of whichever neighborhood you're in, past you.
func _start_car(near: Vector3) -> void:
	var world := get_tree().get_first_node_in_group("world")
	var lot := world.get_node_or_null("LotZone") as Node3D if world != null else null
	if lot == null:
		return
	var direction := 1.0 if randf() < 0.5 else -1.0
	var hood := _hood_index(near) if TownMap.enabled(get_tree()) else -1
	if hood >= 0:
		var street_z := TownMap.STREET_Z[hood] - 2.2
		_car_from = Vector3(near.x - Constants.AMBIENCE_CAR_RUN * direction, 0.6, street_z)
		_car_to = Vector3(near.x + Constants.AMBIENCE_CAR_RUN * direction, 0.6, street_z)
	else:
		var lane := _Neighborhood.STREET.y - 2.2
		_car_from = lot.to_global(Vector3(-Constants.AMBIENCE_CAR_RUN * direction, 0.6, lane))
		_car_to = lot.to_global(Vector3(Constants.AMBIENCE_CAR_RUN * direction, 0.6, lane))
	_car_t = 0.0
	_car.global_position = _car_from
	_car.pitch_scale = randf_range(0.9, 1.1)
	_car.play()


## One of the id's variants, out in the neighborhood.
func _one_shot(id: String, at: Vector3, db: float) -> void:
	var paths := _Bank.files(id)
	var player := AudioStreamPlayer3D.new()
	player.stream = load(paths[randi_range(0, paths.size() - 1)])
	player.bus = _Bank.bus(id)
	player.volume_db = db + _Bank.db(id)
	player.unit_size = Constants.AMBIENCE_UNIT_SIZE
	player.max_distance = Constants.AMBIENCE_MAX_DISTANCE
	player.pitch_scale = randf_range(0.94, 1.06)
	player.finished.connect(player.queue_free)
	add_child(player)
	player.global_position = at
	player.play()


## The connected town's neighborhood street pos is on or by (TownMap.region_of),
## as its index in TownMap.STREET_Z, or -1 (the store, the country, the legacy world).
func _hood_index(pos: Vector3) -> int:
	if not TownMap.enabled(get_tree()):
		return -1
	var region := TownMap.region_of(pos)
	for index: int in TownMap.STREET_Z.size():
		if TownMap.hood_id_of(TownMap.first_house_of(index)) == region:
			return index
	return -1


func _between(range_value: Vector2) -> float:
	return randf_range(range_value.x, range_value.y)


func _around(distance: Vector2) -> Vector3:
	var angle := randf() * TAU
	return Vector3(cos(angle), 0.0, sin(angle)) * _between(distance)


func _local_player() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as Node3D
	return null
