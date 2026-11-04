extends Node3D

## Local presentation. A vehicle's engine (gap-specs/audio.json chunk 7, critic
## C13; docs/DECISIONS.md "Audio: the engine and the board are components"). Hang
## it under the drawn body of a truck and it makes the engine from what the truck
## says it is doing; nothing here is networked, every peer reads its own copy.
##
## The state, each physics tick: state_source if set, else parent.engine_state()
## if the parent has one, else "on while the parent moves". It is
## {on, throttle (-1..1), speed (m/s), skidding}; a missing speed is read off how
## fast this node moved, so a vehicle drawn along a path needs to say only on.
##
##   on rising       engine_start (the crank), then the loops
##   on falling      the idle sags in pitch and fades (it switches off, it
##                   doesn't drive away)
##   speed           idle crossfades into the rev loop by ENGINE_REV_FULL_SHARE of
##                   top_speed, the rev climbs through the profile's gears
##   throttle        pushes the crossfade and the pitch a little (revving in place)
##   skidding        skid, once when it starts, again every skid_repeat s while it
##                   lasts (0: once a slide) above CHEFTY_SKID_MIN_SPEED_SHARE
## Aboard (this peer's player sits in the vehicle that owns state_source, by its
## seat_of()), the loops carry ENGINE_ABOARD_UNIT_SIZE m before they fade and
## aren't muffled by distance: the drivable Chefty's chase camera hangs back
## farther the faster it goes, and the driver heard the engine get quieter as it
## floored it (play: rec_a7_drive_1p, -23 dB idling, -30 dB flat out).
## start() and arrive() are for a caller that knows the moment better (the legacy
## ride's arrival: skid unless one just played, then door_slam).
## Headless and automated runs make no players, but the one-shots still go to Sfx,
## which logs them (--audio-test).

const _Bank = preload("res://audio/sound_bank.gd")
const _SfxScript = preload("res://audio/sfx.gd")
const SILENT_DB: float = -80.0

## A key of Constants.ENGINE_PROFILES ("chefty", "van").
@export var profile: StringName = &"chefty"
## Speed (m/s) where the rev loop is at the top of its range.
var top_speed: float = Constants.CHEFTY_TOP_SPEED
## Returns the state dictionary; unset, the parent's engine_state() is read.
var state_source: Callable = Callable()
## Seconds between skids while a slide lasts; 0 skids once per slide.
var skid_repeat: float = Constants.CHEFTY_SKID_REPEAT

var _idle: AudioStreamPlayer3D
var _rev: AudioStreamPlayer3D
var _primed: bool = false
var _on: bool = false
var _speed: float = 0.0
var _last_pos := Vector3.INF
var _skidding: bool = false
var _skid_left: float = 0.0
var _since_skid: float = INF
var _since_start: float = INF
## Switching off: how far through (0..1), -1 when not.
var _stop_t: float = -1.0
var _mix: Dictionary = {}
var _default_filter_db: float = -24.0


func _ready() -> void:
	# After whatever moves the body this tick (a ride's path, the drive's view).
	process_physics_priority = 200
	if position == Vector3.ZERO:
		position = Constants.ENGINE_SOUND_AT
	if _silent():
		return
	_idle = _loop("engine_idle", "Idle")
	_rev = _loop("engine_rev", "Rev")


func _exit_tree() -> void:
	for player: AudioStreamPlayer3D in [_idle, _rev]:
		if player != null:
			player.stop()
			player.stream = null


func _physics_process(delta: float) -> void:
	var state := read_state(delta)
	var on := bool(state.get("on", false))
	_since_skid += delta
	_since_start += delta
	if not _primed:
		# Already running when this peer first sees it: no crank. (A late joiner
		# whose state arrives after this first tick is told by prime_running().)
		_primed = true
		_on = on
		_speed = float(state.get("speed", 0.0))
	elif on and not _on:
		start()
	elif not on and _on:
		_stop_t = 0.0
	_on = on
	_step_skid(delta, state)
	_step_loops(delta, state)
	_step_reach(delta)


## The engine catches: the crank, once (not again within ENGINE_START_GAP_SECONDS).
func start() -> void:
	_stop_t = -1.0
	if _since_start < Constants.ENGINE_START_GAP_SECONDS:
		return
	_since_start = 0.0
	_play("engine_start")


## Already running when this peer first hears of it (a late joiner told of a
## honk-and-wait that started before it came): the loops, no crank, whenever the
## state first says on.
func prime_running() -> void:
	_primed = true
	_on = true
	_stop_t = -1.0
	_since_start = INF


## Pulled up: the brakes (unless they just squealed) and a door.
func arrive() -> void:
	if _since_skid > Constants.ENGINE_ARRIVE_SKID_GAP:
		_skid()
	_play("door_slam")


## The state as this node sees it this tick (speed smoothed; read off its own
## movement when the state has none).
func read_state(delta: float) -> Dictionary:
	var state: Dictionary = {}
	if state_source.is_valid():
		state = state_source.call()
	elif get_parent() != null and get_parent().has_method("engine_state"):
		state = get_parent().call("engine_state")
	var here := global_position if is_inside_tree() else Vector3.ZERO
	var moved := 0.0
	if _last_pos != Vector3.INF and delta > 0.0:
		moved = here.distance_to(_last_pos) / delta
	_last_pos = here
	if moved > Constants.ENGINE_TELEPORT_SPEED:
		moved = _speed
	var raw := float(state.get("speed", moved))
	_speed = lerpf(_speed, raw, 1.0 - exp(-Constants.ENGINE_SPEED_SMOOTH * delta))
	var out := state.duplicate()
	out["speed"] = _speed
	if not out.has("on"):
		out["on"] = moved > 0.5
	return out


## The two loops' volume (dB, before the profile's reach) and pitch for a speed
## and throttle: equal-power crossfade from idle to rev by
## ENGINE_REV_FULL_SHARE, the rev stepping through the profile's gears.
static func mix(speed: float, throttle: float, top: float, profile_id: StringName) -> Dictionary:
	var p := profile_of(profile_id)
	var share := clampf(absf(speed) / maxf(top, 0.1), 0.0, 1.0)
	var push := clampf(throttle, 0.0, 1.0)
	var w := clampf((share + push * Constants.ENGINE_THROTTLE_SHARE) / Constants.ENGINE_REV_FULL_SHARE, 0.0, 1.0)
	w = w * w * (3.0 - 2.0 * w)
	var idle_gain := cos(w * PI * 0.5)
	var rev_gain := sin(w * PI * 0.5)
	var gears := maxi(1, int(p["gears"]))
	var in_gear := share * float(gears) - minf(floorf(share * float(gears)), float(gears - 1))
	var climb := share * (1.0 - Constants.ENGINE_GEAR_SPAN) + in_gear * Constants.ENGINE_GEAR_SPAN
	var idle_pitch: Vector2 = p["idle_pitch"]
	var rev_pitch: Vector2 = p["rev_pitch"]
	var rev_db: Vector2 = p["rev_db"]
	return {
		"idle_db": float(p["idle_db"]) + linear_to_db(maxf(idle_gain, 0.0001)),
		"rev_db": lerpf(rev_db.x, rev_db.y, share) + linear_to_db(maxf(rev_gain, 0.0001)),
		"idle_pitch": lerpf(idle_pitch.x, idle_pitch.y, w),
		"rev_pitch": lerpf(rev_pitch.x, rev_pitch.y, climb) + push * Constants.ENGINE_THROTTLE_PITCH,
	}


static func profile_of(profile_id: StringName) -> Dictionary:
	return Constants.ENGINE_PROFILES.get(String(profile_id), Constants.ENGINE_PROFILES["chefty"])


## What the loops are aiming at now (for the jukebox and the tests).
func current_mix() -> Dictionary:
	return _mix.duplicate()


func is_running() -> bool:
	return _on


# ---------------------------------------------------------------- inside

func _step_skid(delta: float, state: Dictionary) -> void:
	var share := absf(float(state["speed"])) / maxf(top_speed, 0.1)
	var sliding := bool(state.get("skidding", false)) and share > Constants.CHEFTY_SKID_MIN_SPEED_SHARE
	if not sliding:
		_skidding = false
		_skid_left = 0.0
		return
	_skid_left -= delta
	if not _skidding or (skid_repeat > 0.0 and _skid_left <= 0.0):
		_skid()
		_skid_left = skid_repeat
	_skidding = true


func _skid() -> void:
	_since_skid = 0.0
	_play("skid")


func _step_loops(delta: float, state: Dictionary) -> void:
	var target := mix(float(state["speed"]), float(state.get("throttle", 0.0)), top_speed, profile)
	if _stop_t >= 0.0:
		_stop_t = minf(_stop_t + delta / Constants.ENGINE_STOP_SECONDS, 1.0)
		var fade := linear_to_db(maxf(1.0 - _stop_t, 0.0001))
		target["idle_db"] = float(target["idle_db"]) + fade
		target["rev_db"] = float(target["rev_db"]) + fade
		target["idle_pitch"] = float(target["idle_pitch"]) * lerpf(1.0, Constants.ENGINE_STOP_PITCH, _stop_t)
		target["rev_pitch"] = float(target["rev_pitch"]) * lerpf(1.0, Constants.ENGINE_STOP_PITCH, _stop_t)
	elif not _on or _since_start < Constants.ENGINE_START_CATCH_SECONDS:
		# Off, or still cranking: the loops come in where the crank catches.
		target["idle_db"] = SILENT_DB
		target["rev_db"] = SILENT_DB
	_mix = target
	if _idle == null:
		if _stop_t >= 1.0:
			_stop_t = -1.0
		return
	var sounding := _on or (_stop_t >= 0.0 and _stop_t < 1.0)
	if not sounding:
		_stop_t = -1.0
		for player: AudioStreamPlayer3D in [_idle, _rev]:
			if player.playing:
				player.stop()
		return
	var ease := 1.0 - exp(-Constants.ENGINE_SMOOTH * delta)
	_drive(_idle, float(target["idle_db"]), float(target["idle_pitch"]), ease)
	_drive(_rev, float(target["rev_db"]), float(target["rev_pitch"]), ease)


## Eases the loops' reach toward the aboard one or the profile's.
func _step_reach(delta: float) -> void:
	if _idle == null:
		return
	var aboard := is_aboard()
	var p := profile_of(profile)
	var want := Constants.ENGINE_ABOARD_UNIT_SIZE if aboard else float(p["unit_size"])
	var ease := 1.0 - exp(-Constants.ENGINE_SMOOTH * delta)
	for player: AudioStreamPlayer3D in [_idle, _rev]:
		player.unit_size = lerpf(player.unit_size, want, ease)
		player.attenuation_filter_db = 0.0 if aboard else _default_filter_db


## True when this peer's player is in a seat of the vehicle whose state this
## reads (state_source's object, else the parent's vehicle), by its seat_of().
func is_aboard() -> bool:
	var vehicle: Object = state_source.get_object() if state_source.is_valid() else null
	if vehicle == null and get_parent() != null:
		vehicle = get_parent().get("vehicle") if "vehicle" in get_parent() else get_parent()
	if vehicle == null or not vehicle.has_method("seat_of"):
		return false
	return int(vehicle.call("seat_of", Net.local_peer_id())) >= 0


func _drive(player: AudioStreamPlayer3D, db: float, pitch: float, ease: float) -> void:
	if player.stream == null:
		return
	if not player.playing:
		# From silence (it eases up from there), at a random place in the loop, so
		# two trucks side by side don't putt in step.
		player.volume_db = SILENT_DB if db <= SILENT_DB + 1.0 or _since_start < 2.0 * Constants.ENGINE_START_CATCH_SECONDS else db
		player.pitch_scale = maxf(0.05, pitch)
		player.play(randf() * player.stream.get_length())
		return
	# The crossfade stays smooth in dB; the gear steps get a short slide, not a jump.
	player.volume_db = lerpf(player.volume_db, db, ease)
	player.pitch_scale = maxf(0.05, lerpf(player.pitch_scale, pitch, ease))


func _loop(id: String, node_name: String) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = node_name
	player.stream = _SfxScript.looped(id)
	player.bus = _Bank.bus(id)
	var p := profile_of(profile)
	player.unit_size = float(p["unit_size"])
	player.max_distance = float(p["max_distance"])
	player.volume_db = SILENT_DB
	_default_filter_db = player.attenuation_filter_db
	add_child(player)
	return player


func _play(id: String) -> void:
	var sfx := get_tree().get_first_node_in_group("sfx") if is_inside_tree() else null
	if sfx != null:
		sfx.call("play_on", id, self, 0.0, true, get_instance_id())


func _silent() -> bool:
	return Net.is_automated() or DisplayServer.get_name() == "headless"
