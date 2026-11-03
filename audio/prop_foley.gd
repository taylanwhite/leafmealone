extends Node

## Local presentation. What a yard prop sounds like when it's handled (gap audio
## chunk 6; docs/GAME.md "Foley: what the crew sounds like"), on every peer, from
## its replicated state, heard where it happens. props/prop_looks.gd dress()
## adds one to every prop as "PropFoley", next to its ToolSound.
##   ladder_top  ZERO to set: ladder_clack where its top meets the gutter. Set to
##               ZERO with nobody holding it (knocked over): ladder_crash when it
##               hits the ground (its tumble stops turning), never later than
##               Constants.FOLEY_LADDER_FALL_SECONDS.y.
##   hose_source "" to a source: hose_click (hooked up)
##   stored_bags up: bag_plop (a bag into the wheelbarrow)
##   held_by     0 to someone, off the ground (never out of a pocket, critic C12;
##               the hotbar has its draw): pickup_light or pickup_heavy by its
##               weight, and a TurfMasters sign's first pull is a sign_pull.
## The first tick only reads the state, so a prop that arrives already set up or
## held (a late join, a spawn into someone's hands) makes no sound.

var prop: Node3D

var _primed: bool = false
var _ladder_set: bool = false
var _hose: String = ""
var _bags: int = 0
var _held: int = 0
var _sign_pulled: bool = false
## A knocked-over ladder on its way down: seconds since, and its last rotation.
var _falling: float = -1.0
var _window: float = 0.0
var _last_rotation := Vector3.ZERO


func _process(delta: float) -> void:
	if prop == null or not is_instance_valid(prop):
		return
	var kind := str(prop.get("kind"))
	var ladder_set := Vector3(prop.get("ladder_top")) != Vector3.ZERO
	var hose := str(prop.get("hose_source"))
	var bags := int(prop.get("stored_bags"))
	var held := int(prop.get("held_by"))
	if not _primed:
		_primed = true
		_ladder_set = ladder_set
		_hose = hose
		_bags = bags
		_held = held
		_sign_pulled = held != 0 or int(prop.get("pocketed_by")) != 0
		return
	if kind == "ladder":
		_ladder(ladder_set, held, delta)
	if hose != _hose:
		if _hose == "" and hose != "":
			_play("hose_click", prop.global_position + Vector3.UP * 0.3)
		_hose = hose
	if bags != _bags:
		if bags > _bags:
			_play("bag_plop", prop.global_position + Vector3.UP * 0.5)
		_bags = bags
	if held != _held:
		if _held == 0 and held != 0 and not bool(prop.get_meta("drawn_from_pocket", false)):
			_picked_up(kind)
		_held = held


func _picked_up(kind: String) -> void:
	if kind == "turf_sign" and not _sign_pulled:
		_sign_pulled = true
		_play("sign_pull", prop.global_position)
		return
	_sign_pulled = true
	var tier := str(prop.call("weight_tier")) if prop.has_method("weight_tier") else "light"
	_play("pickup_light" if tier == "light" else "pickup_heavy", prop.global_position + Vector3.UP * 0.3)


func _ladder(ladder_set: bool, held: int, delta: float) -> void:
	if ladder_set != _ladder_set:
		if ladder_set:
			_play("ladder_clack", Vector3(prop.get("ladder_top")))
		elif held == 0:
			_falling = 0.0
			_window = 0.0
			_last_rotation = prop.rotation
		_ladder_set = ladder_set
	if _falling < 0.0:
		return
	# Taken down by hand after all (its holder arrived a packet later): no crash.
	if held != 0:
		_falling = -1.0
		return
	_falling += delta
	_window += delta
	var landed := false
	# The rotation replicates in steps, so the tumble is measured over a window.
	if _window >= Constants.FOLEY_LADDER_WINDOW:
		var turned := (prop.rotation - _last_rotation).length()
		_last_rotation = prop.rotation
		_window = 0.0
		landed = _falling >= Constants.FOLEY_LADDER_FALL_SECONDS.x and turned < Constants.FOLEY_LADDER_SETTLE_RAD
	if landed or _falling >= Constants.FOLEY_LADDER_FALL_SECONDS.y:
		_falling = -1.0
		_play("ladder_crash", prop.global_position + Vector3.UP * 0.5)


func _play(id: String, at: Vector3) -> void:
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play_at", id, at, 0.0, true, prop.get_instance_id() % 100000 + 1)
