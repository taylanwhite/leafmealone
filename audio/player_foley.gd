extends Node

## Local presentation. What a player's body sounds like (gap audio chunk 6;
## docs/GAME.md "Foley: what the crew sounds like"), on every peer, from state
## that already replicates, heard where it happens. player.gd _dress_up adds one
## under every player as "Foley", next to the CartoonBody it listens to.
##   footsteps   one where each foot comes down: the drawn body's walk cycle
##               (CartoonBody._phase, the same one that swings its legs) crosses
##               a foot's contact. The ground picks the sound (leaves by depth,
##               the lawn, pavement and porches), crouching hushes them,
##               sprinting stamps a little, and a teammate's sit under your own.
##               Never two from one body closer than FOLEY_STEP_MIN_SECONDS.
##               A full set of pockets jangles every HOTBAR_JANGLE_EVERY steps.
##   coat        paint_splat (paint) or splash (water) as it lands on you
##   carried_by  grab_yoink as a teammate hoists you
##   thrown      throw_big as you leave their hands
##   winding     punch_windup, a windmill whir held while the punch winds up
##   foot_hurt   foot_pop the moment the mower takes a foot (2)
##   landing     land_thump when the body comes down faster than LAND_THUMP_SPEED
## Nothing here touches gameplay state; the first tick only reads the state, so a
## body that arrives already painted (a late join) doesn't splat.

const _Sfx = preload("res://audio/sfx.gd")
const _Bank = preload("res://audio/sound_bank.gd")
## player.gd's AnimState values.
const ANIM_SPRINT: int = 2
const ANIM_CROUCH: int = 3
const ANIM_AIR: int = 4
const ANIM_KNOCKED: int = 5

var player: CharacterBody3D
var body: Node3D

## Every footstep this peer has played from any body (tests and the recorder
## read Sfx's log; this keeps the surface too): {"peer", "id", "db"}.
static var steps: Array[Dictionary] = []

var _primed: bool = false
var _last_phase: float = NAN
## Game seconds this node has run, and when the last footstep sounded: the step
## gap is game time, so a slowed or fixed-step run spaces steps as a player hears
## them at full speed.
var _clock: float = 0.0
var _last_step_at: float = -100.0
var _step_count: int = 0
var _coat: int = 0
var _carried_by: int = 0
var _thrown: bool = false
var _foot_hurt: int = 0
var _air_seconds: float = 0.0
var _fall_speed: float = 0.0
var _thrown_fall: bool = false
var _winding: bool = false
var _windup: AudioStreamPlayer3D


func _exit_tree() -> void:
	if _windup != null:
		_windup.stop()
		_windup.stream = null


## The body animates on physics ticks, so its stride is read on the same ticks.
func _physics_process(delta: float) -> void:
	if player == null or body == null or not is_instance_valid(body):
		return
	_clock += delta
	var coat := int(player.get("coat"))
	var carried_by := int(player.get("carried_by"))
	var thrown := bool(player.get("thrown"))
	var foot_hurt := int(player.get("foot_hurt"))
	var winding := bool(player.get("winding"))
	if not _primed:
		_primed = true
		_coat = coat
		_carried_by = carried_by
		_thrown = thrown
		_foot_hurt = foot_hurt
		_last_phase = float(body.get("_phase"))
		return
	if coat != _coat:
		if coat == 1:
			_play("paint_splat", _chest(), 0.0, _peer())
		elif coat == 2:
			_play("splash", _chest(), 0.0, _peer())
		_coat = coat
	if carried_by != _carried_by:
		if _carried_by == 0:
			_play("grab_yoink", _chest(), 0.0, _peer())
		_carried_by = carried_by
	if thrown != _thrown:
		if thrown:
			_play("throw_big", _chest(), 0.0, _peer())
		_thrown = thrown
	if foot_hurt != _foot_hurt:
		if foot_hurt >= 2 and _foot_hurt < 2:
			_play("foot_pop", body.global_position + Vector3.UP * 0.2, 0.0, _peer())
		_foot_hurt = foot_hurt
	_windup_loop(winding, delta)
	_landing(delta)
	_footsteps()


# ---------------------------------------------------------------- footsteps

func _footsteps() -> void:
	var phase := float(body.get("_phase"))
	var last := _last_phase
	_last_phase = phase
	if is_nan(last) or phase == last:
		return
	# A foot comes down where a leg's swing is at its end: sin(phase) = +-1.
	if floori((phase - PI * 0.5) / PI) == floori((last - PI * 0.5) / PI):
		return
	if not _stepping():
		return
	if _clock - _last_step_at < Constants.FOLEY_STEP_MIN_SECONDS:
		return
	_last_step_at = _clock
	var id := surface_id(player, body.global_position)
	var db := Constants.FOLEY_STEP_DB + (0.0 if player.is_multiplayer_authority() else Constants.FOLEY_STEP_OTHER_DB)
	var anim := int(player.get("anim_state"))
	if anim == ANIM_CROUCH:
		db += Constants.FOLEY_STEP_CROUCH_DB
	elif anim == ANIM_SPRINT:
		db += Constants.FOLEY_STEP_SPRINT_DB
	var at := body.global_position + Vector3.UP * 0.05
	# Out of earshot (a teammate at the store while you're on the yard): no player
	# made at all, so four crews' feet don't churn sound nodes nobody hears.
	var cam := get_viewport().get_camera_3d()
	if not _silent() and cam != null and cam.global_position.distance_to(at) > Constants.FOLEY_STEP_MAX_DISTANCE:
		return
	_play(id, at, db, _peer())
	steps.append({"peer": _peer(), "id": id, "db": db})
	if steps.size() > _Sfx.LOG_SIZE:
		steps.pop_front()
	# A full set of pockets (the hotbar) jangles every few steps.
	_step_count += 1
	var pockets: Node = player.call("pockets") if player.has_method("pockets") else null
	if pockets != null and _step_count % Constants.HOTBAR_JANGLE_EVERY == 0 and int(pockets.call("pocketed_count")) >= Constants.HOTBAR_JANGLE_AT:
		_play("jangle", body.global_position + Vector3.UP * 0.9, Constants.HOTBAR_JANGLE_DB + db - Constants.FOLEY_STEP_DB, _peer())


## Whether this body is walking on its own feet right now: drawn, on the ground,
## moving, and not carried, flying, seated, hidden, up a ladder or asleep.
func _stepping() -> bool:
	if not body.is_visible_in_tree() or not bool(player.call("is_body_drawn")):
		return false
	var anim := int(player.get("anim_state"))
	if anim == ANIM_AIR or anim == ANIM_KNOCKED or bool(body.get("_in_air")):
		return false
	if float(body.get("_speed")) < Constants.FOLEY_STEP_MIN_SPEED or int(body.get("_sit_pose")) != 0:
		return false
	if int(player.get("carried_by")) != 0 or bool(player.get("thrown")):
		return false
	# Seated is no walk; a staged body (the NICE BOYS' escort) walks for real.
	if bool(player.call("is_hidden")) or (bool(player.call("is_riding_visual")) and not bool(player.call("is_staged"))):
		return false
	if player.get("_ride") != null or bool(player.call("is_sleeping")) or bool(player.call("is_climbing")):
		return false
	return true


## What the ground at pos sounds like underfoot for this player: leaves by how
## deep they are (LeafAudio.step_id), the job's lawn, else something hard (the
## store's lot, a porch, a roof, the street).
static func surface_id(who: Node3D, pos: Vector3) -> String:
	if pos.y > 0.6:
		return "step_hard"
	var tree := who.get_tree()
	var zone := Net.player_zone(who.name.to_int())
	if zone != Net.Zone.LOT and zone != Net.Zone.TOWN:
		return "step_hard"
	var field := tree.get_first_node_in_group("leaf_field")
	if field != null:
		var density := int(field.call("sample_world", pos))
		if density >= Constants.STEP_LEAVES_DENSITY:
			return LeafAudio.step_id(density)
	var tasks := tree.get_first_node_in_group("job_tasks")
	if tasks != null and bool(tasks.call("is_lawn", pos)):
		return "step_grass"
	return "step_hard"


# ---------------------------------------------------------------- the rest of the body

## A hard landing: the most the body fell by while it was in the air (velocity
## replicates, so a teammate's landing thumps on every peer).
func _landing(delta: float) -> void:
	var anim := int(player.get("anim_state"))
	var falling := -float((player.get("velocity") as Vector3).y)
	# Thrown, the body flies knocked flat (not AIR): it lands the tick its fall
	# stops, whatever the speed (a thrown teammate always hits the lawn hard).
	if bool(player.get("thrown")):
		if falling > Constants.FOLEY_THROWN_FALLING:
			_thrown_fall = true
		elif _thrown_fall and falling < Constants.FOLEY_THROWN_LANDED:
			_thrown_fall = false
			_play("land_thump", body.global_position + Vector3.UP * 0.1, 0.0, _peer())
		return
	_thrown_fall = false
	if anim == ANIM_AIR:
		_air_seconds += delta
		_fall_speed = maxf(_fall_speed, falling)
		return
	if _air_seconds >= Constants.FOLEY_LAND_MIN_AIR_SECONDS and _fall_speed > Constants.LAND_THUMP_SPEED and int(player.get("carried_by")) == 0:
		_play("land_thump", body.global_position + Vector3.UP * 0.1, 0.0, _peer())
	_air_seconds = 0.0
	_fall_speed = 0.0


## The punch wind-up's whir, faded in while winding and out after.
func _windup_loop(winding: bool, delta: float) -> void:
	if winding and not _winding:
		var sfx := _sfx()
		if sfx != null and sfx.has_method("note_loop"):
			sfx.call("note_loop", "punch_windup", _chest())
	_winding = winding
	if _silent():
		return
	if _windup == null:
		if not winding:
			return
		_windup = AudioStreamPlayer3D.new()
		_windup.name = "Windup"
		_windup.stream = _Sfx.looped("punch_windup")
		_Sfx.configure_3d(_windup, "punch_windup", Constants.FOLEY_WINDUP_DB, false)
		_windup.volume_db = -60.0
		body.add_child(_windup)
		_windup.position = Vector3(0.0, 1.3, 0.0)
	var target := Constants.FOLEY_WINDUP_DB + _Bank.db("punch_windup") if winding else -60.0
	_windup.volume_db = move_toward(_windup.volume_db, target, Constants.FOLEY_LOOP_FADE_DB_PER_SECOND * delta)
	if winding and not _windup.playing:
		_windup.play()
	elif not winding and _windup.playing and _windup.volume_db <= -59.0:
		_windup.stop()


func _chest() -> Vector3:
	return body.global_position + Vector3.UP * 1.1


func _peer() -> int:
	return player.name.to_int()


func _play(id: String, at: Vector3, db := 0.0, source := 0) -> void:
	var sfx := _sfx()
	if sfx != null:
		sfx.call("play_at", id, at, db, true, source)


func _sfx() -> Node:
	return get_tree().get_first_node_in_group("sfx")


func _silent() -> bool:
	return Net.is_automated() or DisplayServer.get_name() == "headless"
