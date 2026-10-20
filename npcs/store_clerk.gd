extends Node3D

## Authority: local, cosmetic. The Homie Depot clerk behind the counter
## (docs/FEEL.md, "How characters deal with shops"). Turns to face whoever is
## closest, babbles when you walk up, and opens the shop window when you press
## E across the counter. Name and personality are design decisions, so the name
## tag says [CLERK NAME] until the workbook has one. Every peer has its own
## copy: nothing about the clerk is shared state, and buying goes through
## Campaign on the host.

const _Strings = preload("res://ui/strings.gd")
const _CartoonBody = preload("res://player/cartoon_body.gd")
## How close the local player must be to shop, across the counter, in meters.
const SHOP_REACH: float = 3.0
## How close someone must be for the clerk to look at them and greet them.
const NOTICE_RANGE: float = 7.0
const GREET_COOLDOWN_SECONDS: float = 8.0
const APRON := Color(0.93, 0.47, 0.13)

var _body: Node3D
var _voice: AudioStreamPlayer3D
var _greeted_at: float = -1000.0
var _local_was_near: bool = false


func _ready() -> void:
	add_to_group("prompt_sources")
	add_to_group("store_clerk")
	_body = _CartoonBody.new()
	_body.name = "CartoonBody"
	_body.set("shirt", APRON)
	_body.set("pants", Color(0.28, 0.3, 0.38))
	_body.set("skin", _CartoonBody.SKIN_TONES[2])
	_body.set("hat_style", "cap")
	_body.set("hat_color", APRON.darkened(0.2))
	add_child(_body)
	_body.call("build")
	var tag := Label3D.new()
	tag.text = _Strings.UI["clerk_name"]
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 40
	tag.outline_size = 8
	tag.position.y = 2.25
	add_child(tag)
	_voice = AudioStreamPlayer3D.new()
	_voice.position.y = 1.6
	_voice.unit_size = 4.0
	add_child(_voice)


## The shop prompt while the local player is across the counter.
func prompt() -> Dictionary:
	if not _local_in_reach():
		return {}
	return {"text": _Strings.UI["prompt_shop"], "at": global_position + Vector3(0.0, 2.6, 0.0)}


## Babble something, with the mouth moving. Called on greeting, opening, and buying.
func chatter() -> void:
	if Net.is_automated():
		return
	var stream := load("res://assets/audio/sfx/babble_%d.wav" % randi_range(1, 5)) as AudioStream
	if stream == null:
		return
	_voice.stream = stream
	_voice.pitch_scale = randf_range(0.95, 1.08)
	_voice.play()
	_body.call("talk", stream.get_length() / _voice.pitch_scale)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or not _local_in_reach():
		return
	var ui := get_tree().get_first_node_in_group("game_ui")
	if ui != null:
		ui.call("open_store")
		chatter()
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var nearest := _nearest_player()
	if nearest != null:
		# Turn toward them. Bodies face -Z, so look away from the target to face it.
		var to := nearest.global_position - global_position
		var yaw := atan2(-to.x, -to.z)
		rotation.y = lerp_angle(rotation.y, yaw, clampf(delta * 4.0, 0.0, 1.0))
	var near := _local_in_reach()
	var now := Time.get_ticks_msec() / 1000.0
	if near and not _local_was_near and now - _greeted_at > GREET_COOLDOWN_SECONDS:
		_greeted_at = now
		chatter()
	_local_was_near = near


func _local_in_reach() -> bool:
	var local := _player(Net.local_peer_id())
	return local != null and _flat_distance(local) <= SHOP_REACH


func _nearest_player() -> Node3D:
	var best: Node3D = null
	var best_distance := NOTICE_RANGE
	for node: Node in get_tree().get_nodes_in_group("players"):
		var body := node as Node3D
		if body == null:
			continue
		var distance := _flat_distance(body)
		if distance < best_distance:
			best = body
			best_distance = distance
	return best


func _player(peer_id: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node as Node3D
	return null


func _flat_distance(body: Node3D) -> float:
	return Vector2(body.global_position.x - global_position.x, body.global_position.z - global_position.z).length()
