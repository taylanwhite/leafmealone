extends Node

## Local presentation. The neighborhood's background sound around the local
## player: a breeze through the trees, birds now and then by day, a dog a few
## yards over, a car going by on the lot's street, a neighbor mowing a few yards
## over (by day), and at night (from AMBIENCE_NIGHT_FROM_HOUR) crickets fading
## in and an owl now and then. At Homie Depot: its hum through the sliding doors,
## the PA's ding-dong while it's open, a shopping cart rattling across the lot
## (audio chunk 6; docs/GAME.md "Foley"). Nothing here is shared. Its players
## sit on the Ambience bus (audio/buses.gd), and its tuning is
## Constants.AMBIENCE_*. The music, and M, are the music director's
## (audio/music_director.gd, under UIRoot/Audio).
##
## Each neighborhood's own sounds (art chunk 9; docs/GAME.md "What each
## neighborhood sounds like"), by the hood the yard or the town street you're on
## is in (the job lot's meta hood_style, TownMap.region_of):
##   - the set pieces' loops, from group "ambient_emitters" (meta ambient, the
##     loop's id; ambient_line [a, b] for a source along a line, like a lake's
##     shore, heard from its nearest point; ambient_sync, ambient_phase for a loop
##     that keeps time with what you see; ambient_level() for how loud now;
##     ambient_frozen / ambient_freezes for water that's ice): the nearest
##     AMBIENCE_EMITTER_VOICES within AMBIENCE_EMITTER_REACH play, fading in and
##     out as you move. Mansion Hill's fountains, Lakeside's shore, Oak Hollow's
##     lawn sprinklers (props/sprinkler_jet.gd) and a summer lawn's.
##   - one-shots (Constants.AMBIENCE_HOOD_SHOTS) at the hours people make them,
##     from a real porch or back yard near you (group "porches",
##     levels/town/house_builder.gd) or out on the water: Maple Row's wind chimes,
##     Dandelion Acres' screen doors and chained dog, Oak Hollow's disapproving
##     whistle (office hours only), Lakeside's loon.

const _Sfx = preload("res://audio/sfx.gd")
const _Bank = preload("res://audio/sound_bank.gd")
const _Neighborhood = preload("res://levels/dressing/neighborhood.gd")
const _HoodStyles = preload("res://levels/town/hood_styles.gd")


var _wind: AudioStreamPlayer
## Satellite Annex B's office through the wall (R2 chunk 5): typewriters, and a
## bed set_bed() asks for (the van's cab: its radio, when it has one).
var _office: AudioStreamPlayer
var _beds: Dictionary = {}
var _waits: Dictionary = {}
## Night's crickets (2D, faded by the hour) and Homie Depot's hum at its doors.
var _crickets: AudioStreamPlayer
var _hum: AudioStreamPlayer3D
var _car: AudioStreamPlayer3D
var _car_t: float = -1.0
var _car_from := Vector3.ZERO
var _car_to := Vector3.ZERO
## art:9: the hood you're in ("" outside one), the emitter loops' voices
## ({player, emitter (a WeakRef or null), id}), the emitters picked at the last
## scan, the houses near you, and each hood one-shot's wait.
var hood_now: String = ""
var _voices: Array[Dictionary] = []
var _picked: Array = []
var _porches: Array[Node3D] = []
var _hood_waits: Dictionary = {}
var _emitter_scan: float = 0.0
var _loops: Dictionary = {}


func _ready() -> void:
	add_to_group("ambience")
	# Nobody hears a headless run (tests, bots), so don't play anything there.
	if Net.is_automated() or DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_wind = _loop_player("wind_loop", Constants.AMBIENCE_WIND_DB)
	_office = _loop_player("typewriter_bed", -80.0)
	_crickets = _loop_player("crickets_loop", -80.0)
	_hum = _store_hum()
	_waits = {
		"bird": _between(Constants.AMBIENCE_FIRST_BIRD),
		"dog": _between(Constants.AMBIENCE_DOG_GAP),
		"car": _between(Constants.AMBIENCE_FIRST_CAR),
		"office_phone": _between(Constants.AMBIENCE_OFFICE_PHONE_GAP),
		"cooler": _between(Constants.AMBIENCE_OFFICE_GLUG_GAP),
		"owl": _between(Constants.AMBIENCE_OWL_GAP),
		"pa_chime": _between(Constants.AMBIENCE_PA_FIRST),
		"cart_rattle": _between(Constants.AMBIENCE_CART_GAP),
		"distant_mower": _between(Constants.AMBIENCE_MOWER_GAP),
	}
	_car = AudioStreamPlayer3D.new()
	_car.stream = load(_Bank.files("car_pass")[0])
	_car.bus = _Bank.bus("car_pass")
	_car.unit_size = Constants.AMBIENCE_UNIT_SIZE
	_car.max_distance = Constants.AMBIENCE_MAX_DISTANCE
	add_child(_car)
	for id: String in Constants.AMBIENCE_HOOD_SHOTS:
		_hood_waits[id] = _between(Constants.AMBIENCE_HOOD_FIRST)
	for index: int in Constants.AMBIENCE_EMITTER_VOICES:
		var voice := AudioStreamPlayer3D.new()
		voice.name = "Emitter%d" % index
		voice.volume_db = -80.0
		add_child(voice)
		_voices.append({"player": voice, "emitter": null, "id": ""})


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
	var hour := _hour()
	var store_open := _store_open()
	# Crickets come up with the evening, outdoors; a blink to the Annex drops them.
	var crickets := crickets_db(hour) if outdoors else -80.0
	_crickets.volume_db = move_toward(_crickets.volume_db, crickets, Constants.AMBIENCE_CRICKETS_FADE_DB_PER_SECOND * delta)
	for key: String in _waits:
		_waits[key] = float(_waits[key]) - delta
	if float(_waits["bird"]) <= 0.0:
		_waits["bird"] = _between(Constants.AMBIENCE_BIRD_GAP)
		if zone != Net.Zone.TRANSIT and not is_night(hour):
			var up := Vector3(0.0, _between(Constants.AMBIENCE_BIRD_HEIGHT), 0.0)
			_one_shot("bird", me.global_position + _around(Constants.AMBIENCE_BIRD_RANGE) + up, 0.0)
	_neighborhood(me, zone, hour, store_open, in_hood)
	if float(_waits["dog"]) <= 0.0:
		_waits["dog"] = _between(Constants.AMBIENCE_DOG_GAP)
		if in_hood:
			_one_shot("dog", me.global_position + _around(Constants.AMBIENCE_DOG_RANGE), 0.0)
	if float(_waits["car"]) <= 0.0:
		_waits["car"] = _between(Constants.AMBIENCE_CAR_GAP)
		if in_hood and _car_t < 0.0:
			_start_car(me.global_position)
	_annex_office(zone, delta)
	# art:9: the hood's own sounds.
	hood_now = _hood_of(me, zone)
	# Heard from where the camera is (the 3D sound listens there too), so a
	# spectator's or a far third-person view hears what it sees.
	var ear := _ear(me)
	_emitter_scan -= delta
	if _emitter_scan <= 0.0:
		_emitter_scan = Constants.AMBIENCE_EMITTER_SCAN_SECONDS
		_scan_emitters(ear)
		_scan_porches(ear)
	_step_voices(delta, ear)
	_hood_shots(delta, ear, hour)
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


## The one-shots that come and go with where you are and the hour (wants()):
## an owl, the store's PA and its carts, a neighbor's mower.
func _neighborhood(me: Node3D, zone: int, hour: float, store_open: bool, in_hood: bool) -> void:
	for id: String in ["owl", "pa_chime", "cart_rattle", "distant_mower"]:
		if float(_waits[id]) > 0.0:
			continue
		_waits[id] = _between({"owl": Constants.AMBIENCE_OWL_GAP, "pa_chime": Constants.AMBIENCE_PA_GAP,
				"cart_rattle": Constants.AMBIENCE_CART_GAP, "distant_mower": Constants.AMBIENCE_MOWER_GAP}[id])
		if not wants(id, zone, hour, store_open, in_hood):
			continue
		match id:
			"owl":
				var up := Vector3(0.0, _between(Constants.AMBIENCE_OWL_HEIGHT), 0.0)
				_sfx_at(id, me.global_position + _around(Constants.AMBIENCE_OWL_RANGE) + up, 0.0)
			"pa_chime":
				_sfx_at(id, _store_point(Constants.AMBIENCE_STORE_DOORS), 0.0)
			"cart_rattle":
				_sfx_at(id, me.global_position + _around(Constants.AMBIENCE_CART_RANGE), 0.0)
			"distant_mower":
				_sfx_at(id, me.global_position + _around(Constants.AMBIENCE_MOWER_RANGE), Constants.AMBIENCE_MOWER_DB)


## Whether the neighborhood plays id now (pure, for --audio-test): an owl at
## night wherever there are trees, the PA while Homie Depot is open and you're
## there, carts on its lot by day, a neighbor's mower by day where there are houses.
static func wants(id: String, zone: int, hour: float, store_open: bool, in_hood: bool) -> bool:
	match id:
		"owl":
			return is_night(hour) and (in_hood or zone == Net.Zone.STORE)
		"pa_chime":
			return zone == Net.Zone.STORE and store_open
		"cart_rattle":
			return zone == Net.Zone.STORE and not is_night(hour)
		"distant_mower":
			return in_hood and hour < Constants.AMBIENCE_MOWER_UNTIL_HOUR
		"bird":
			return zone != Net.Zone.TRANSIT and not is_night(hour)
	return false


static func is_night(hour: float) -> bool:
	return hour >= Constants.AMBIENCE_NIGHT_FROM_HOUR


## The crickets' level at this hour: silent by day, fading up over
## AMBIENCE_NIGHT_FADE_HOURS from AMBIENCE_NIGHT_FROM_HOUR to AMBIENCE_CRICKETS_DB.
static func crickets_db(hour: float) -> float:
	var share := clampf((hour - Constants.AMBIENCE_NIGHT_FROM_HOUR) / Constants.AMBIENCE_NIGHT_FADE_HOURS, 0.0, 1.0)
	return -80.0 if share <= 0.0 else maxf(-80.0, Constants.AMBIENCE_CRICKETS_DB + linear_to_db(share))


func _hour() -> float:
	var clock := get_tree().get_first_node_in_group("day_clock")
	return float(clock.call("hour")) if clock != null else Constants.DAY_START_HOUR


func _store_open() -> bool:
	var shops := get_tree().get_first_node_in_group("shops")
	if shops != null and shops.has_method("is_open"):
		return bool(shops.call("is_open", "homie_depot"))
	var hours: Vector2 = Constants.SHOP_HOURS.get("homie_depot", Vector2(Constants.DAY_START_HOUR, Constants.QUIET_HOURS_START))
	var hour := _hour()
	return hour >= hours.x and hour < hours.y


## A point in the store's space (StoreZone), in the world.
func _store_point(local: Vector3) -> Vector3:
	var world := get_tree().get_first_node_in_group("world")
	var store := world.get_node_or_null("StoreZone") as Node3D if world != null else null
	return store.to_global(local) if store != null else local


## Homie Depot humming behind its sliding doors: a positional loop, always on,
## heard only near the doors.
func _store_hum() -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.stream = _Sfx.looped("store_hum_loop")
	player.bus = _Bank.bus("store_hum_loop")
	player.volume_db = Constants.AMBIENCE_STORE_HUM_DB + _Bank.db("store_hum_loop")
	player.unit_size = Constants.AMBIENCE_STORE_HUM_UNIT_SIZE
	player.max_distance = Constants.AMBIENCE_STORE_HUM_MAX_DISTANCE
	add_child(player)
	player.global_position = _store_point(Constants.AMBIENCE_STORE_DOORS)
	player.play()
	return player


## A neighborhood one-shot through Sfx (logged; the bank sets its reach).
func _sfx_at(id: String, at: Vector3, db: float) -> void:
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play_at", id, at, db)


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


# ---------------------------------------------------------------- art:9 each hood's own sounds

func _ear(me: Node3D) -> Vector3:
	var viewport := get_viewport()
	var camera := viewport.get_camera_3d() if viewport != null else null
	return camera.global_position if camera != null else me.global_position


## The hood the local player is in: the job yard's (its lot's meta hood_style)
## on a yard, the town's region on a town street, else "".
func _hood_of(me: Node3D, zone: int) -> String:
	if zone == Net.Zone.LOT:
		var lot := get_tree().get_first_node_in_group("job_lot")
		return str(lot.get_meta("hood_style", "")) if lot != null else ""
	if zone == Net.Zone.TOWN and TownMap.enabled(get_tree()):
		var region := str(TownMap.region_of(me.global_position))
		return region if _HoodStyles.ids().has(region) else ""
	return ""


## Whether the hood one-shot id happens now (pure, for --art-test): in one of its
## hoods, in its hours of the clock, and never a loon in winter (they've gone south).
static func hood_wants(id: String, hood: String, hour: float, season: int) -> bool:
	var spec: Dictionary = Constants.AMBIENCE_HOOD_SHOTS.get(id, {})
	if spec.is_empty() or not (spec["hoods"] as Array).has(hood):
		return false
	var hours: Vector2 = spec["hours"]
	if hour < hours.x or hour >= hours.y:
		return false
	return not (id == "loon" and season == 1)


## How loud an emitter plays now, 0..1: silent while its water is frozen, else
## what it says (a sprinkler's pressure), else full.
static func emitter_level(emitter: Node) -> float:
	if bool(emitter.get_meta("ambient_frozen", false)):
		return 0.0
	if bool(emitter.get_meta("ambient_freezes", false)) and Seasons.current() == 1:
		return 0.0
	if emitter.has_method("ambient_level"):
		return clampf(float(emitter.call("ambient_level")), 0.0, 1.0)
	return 1.0


## Where an emitter is heard from by a listener at: the nearest point of its
## line, or its own place.
static func emitter_point(emitter: Node3D, at: Vector3) -> Vector3:
	if emitter.has_meta("ambient_line"):
		var line: PackedVector3Array = emitter.get_meta("ambient_line")
		if line.size() >= 2:
			var xform := emitter.global_transform
			return Geometry3D.get_closest_point_to_segment(at, xform * line[0], xform * line[1])
	return emitter.global_position


## The nearest sounding emitters within reach, nearest first (at most VOICES).
func _scan_emitters(at: Vector3) -> void:
	var found: Array = []
	for node: Node in get_tree().get_nodes_in_group("ambient_emitters"):
		var emitter := node as Node3D
		if emitter == null or not emitter.is_inside_tree() or not _Bank.has(str(emitter.get_meta("ambient", ""))):
			continue
		if emitter_level(emitter) <= 0.0:
			continue
		var distance := emitter_point(emitter, at).distance_to(at)
		if distance <= Constants.AMBIENCE_EMITTER_REACH:
			found.append([distance, emitter])
	found.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	_picked.clear()
	for entry: Array in found.slice(0, Constants.AMBIENCE_EMITTER_VOICES):
		_picked.append(entry[1])
	# A voice keeps its emitter while it's still picked; the rest fade out, and a
	# newly picked emitter takes a voice that has gone quiet.
	var wanted := _picked.duplicate()
	for voice: Dictionary in _voices:
		var emitter: Object = (voice["emitter"] as WeakRef).get_ref() if voice["emitter"] != null else null
		if emitter != null and wanted.has(emitter):
			wanted.erase(emitter)
			_resync(voice, emitter as Node3D)
		else:
			voice["emitter"] = null
	for emitter: Node3D in wanted:
		for voice: Dictionary in _voices:
			var player: AudioStreamPlayer3D = voice["player"]
			if voice["emitter"] == null and (not player.playing or player.volume_db <= -59.0):
				_start_voice(voice, emitter, at)
				break


func _start_voice(voice: Dictionary, emitter: Node3D, at: Vector3) -> void:
	var id := str(emitter.get_meta("ambient"))
	var player: AudioStreamPlayer3D = voice["player"]
	if not _loops.has(id):
		_loops[id] = _Sfx.looped(id)
	var stream: AudioStream = _loops[id]
	if stream == null:
		return
	voice["emitter"] = weakref(emitter)
	voice["id"] = id
	player.stream = stream
	player.bus = _Bank.bus(id)
	player.unit_size = _Bank.unit_size(id)
	player.max_distance = _Bank.max_distance(id)
	player.attenuation_filter_db = Constants.AMBIENCE_EMITTER_MUFFLE_DB
	player.volume_db = -60.0
	player.global_position = emitter_point(emitter, at)
	player.play(_loop_position(emitter, stream))


## Where in its loop an emitter's voice should be: a synced one (a sprinkler) at
## the server time's point, so the tick lands on the step you see (allowing for
## the audio's own latency); any other anywhere.
func _loop_position(emitter: Node3D, stream: AudioStream) -> float:
	var length := stream.get_length()
	if emitter.has_meta("ambient_sync"):
		var sync := float(emitter.get_meta("ambient_sync"))
		return fposmod(Net.server_time() + float(emitter.get_meta("ambient_phase", 0.0)) + AudioServer.get_output_latency(), maxf(sync, 0.01))
	return randf() * maxf(length - 0.05, 0.0)


## A synced voice drifting off its emitter's time gets put back.
func _resync(voice: Dictionary, emitter: Node3D) -> void:
	var player: AudioStreamPlayer3D = voice["player"]
	if not emitter.has_meta("ambient_sync") or not player.playing or player.stream == null:
		return
	var want := _loop_position(emitter, player.stream)
	var length := maxf(float(emitter.get_meta("ambient_sync")), 0.01)
	var off := fposmod(player.get_playback_position() - want + length * 0.5, length) - length * 0.5
	if absf(off) > Constants.AMBIENCE_EMITTER_RESYNC_SECONDS:
		player.seek(want)


## Every frame: each voice follows its emitter (a shore's nearest point moves
## with you) at its level, or fades out and stops.
func _step_voices(delta: float, at: Vector3) -> void:
	for voice: Dictionary in _voices:
		var player: AudioStreamPlayer3D = voice["player"]
		if not player.playing:
			continue
		var emitter := (voice["emitter"] as WeakRef).get_ref() as Node3D if voice["emitter"] != null else null
		var target := -60.0
		if emitter != null and emitter.is_inside_tree():
			var id := str(voice["id"])
			var level := emitter_level(emitter)
			target = -60.0 if level <= 0.001 else _Bank.db(id) + float(Constants.AMBIENCE_EMITTER_DB.get(id, 0.0)) + linear_to_db(level)
			player.global_position = emitter_point(emitter, at)
		elif emitter == null and voice["emitter"] != null:
			voice["emitter"] = null
		player.volume_db = move_toward(player.volume_db, target, Constants.AMBIENCE_EMITTER_FADE_DB_PER_SECOND * delta)
		if voice["emitter"] == null and player.volume_db <= -59.5:
			player.stop()


## The houses near enough to be a one-shot's porch.
func _scan_porches(at: Vector3) -> void:
	_porches.clear()
	var reach := Constants.AMBIENCE_PORCH_RANGE.y + Constants.AMBIENCE_PORCH_SCAN_MARGIN
	for node: Node in get_tree().get_nodes_in_group("porches"):
		var house := node as Node3D
		if house != null and house.is_inside_tree() and house.global_position.distance_to(at) < reach:
			_porches.append(house)


func _hood_shots(delta: float, at: Vector3, hour: float) -> void:
	for id: String in _hood_waits:
		_hood_waits[id] = float(_hood_waits[id]) - delta
		if float(_hood_waits[id]) > 0.0:
			continue
		var spec: Dictionary = Constants.AMBIENCE_HOOD_SHOTS[id]
		_hood_waits[id] = _between(spec["gap"]) * (float(spec["night_gap"]) if is_night(hour) else 1.0)
		if not hood_wants(id, hood_now, hour, Seasons.current()):
			continue
		var from := _shot_point(str(spec["from"]), at)
		if from != Vector3.INF:
			_sfx_at(id, from, 0.0)


## Where a hood one-shot comes from: a porch or a back yard of a house in
## AMBIENCE_PORCH_RANGE of you (somewhere about there when there's none), or out
## on the nearest water (none without a lake).
func _shot_point(from: String, at: Vector3) -> Vector3:
	match from:
		"porch", "yard":
			var choices: Array[Vector3] = []
			for house: Node3D in _porches:
				if not is_instance_valid(house) or not house.is_inside_tree():
					continue
				var door: Vector3 = house.get_meta("door", Vector3(0.0, 1.0, 4.0))
				var local := door + Vector3(0.0, 0.5, 0.9)
				if from == "yard":
					local = Vector3(door.x * 0.4, 0.6, -float(house.get_meta("depth", 8.0)) * 0.5 - 4.0)
				var point := house.global_transform * local
				var distance := point.distance_to(at)
				if distance >= Constants.AMBIENCE_PORCH_RANGE.x and distance <= Constants.AMBIENCE_PORCH_RANGE.y:
					choices.append(point)
			if not choices.is_empty():
				return choices[randi() % choices.size()]
			return at + _around(Vector2(Constants.AMBIENCE_PORCH_RANGE.x + 6.0, Constants.AMBIENCE_PORCH_RANGE.y * 0.7)) + Vector3(0.0, 1.0, 0.0)
		"water":
			var best := Vector3.INF
			var best_distance := Constants.AMBIENCE_FAR_MAX_DISTANCE
			for node: Node in get_tree().get_nodes_in_group("ambient_emitters"):
				var shore := node as Node3D
				if shore == null or not shore.has_meta("ambient_out") or emitter_level(shore) <= 0.0:
					continue
				var edge := emitter_point(shore, at)
				var distance := edge.distance_to(at)
				if distance < best_distance:
					best_distance = distance
					var out := (shore.global_transform.basis * (shore.get_meta("ambient_out") as Vector3)).normalized()
					var along := out.cross(Vector3.UP).normalized() * randf_range(-Constants.AMBIENCE_LOON_ALONG, Constants.AMBIENCE_LOON_ALONG)
					best = edge + out * _between(Constants.AMBIENCE_LOON_OUT) + along + Vector3(0.0, 0.4, 0.0)
			return best
	return Vector3.INF


## What the emitter voices are playing now: [[id, volume_db, distance], ...] (tests).
func emitter_voices() -> Array:
	var out: Array = []
	var me := _local_player()
	for voice: Dictionary in _voices:
		var player: AudioStreamPlayer3D = voice["player"]
		if player.playing:
			out.append([str(voice["id"]), snappedf(player.volume_db, 0.1), snappedf(player.global_position.distance_to(me.global_position), 0.1) if me != null else -1.0])
	return out