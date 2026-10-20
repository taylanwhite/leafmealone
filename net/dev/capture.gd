extends Node

## Authority: local. Saves a PNG of this window every --screenshot-every
## seconds into the --screenshot directory, with the F3 overlay showing.
## Needs a real window, so it does nothing in a headless run.

var _dir: String = ""
var _every: float = 5.0
var _wait: float = 0.0
var _index: int = 0
var _busy: bool = false
var _above: Camera3D
## Screenshots skipped because the window could not draw.
var skipped: int = 0

## Where the overhead camera sits relative to the player, in meters.
const OVERHEAD_OFFSET := Vector3(0.0, 28.0, 14.0)
## Where the wide establishing shot sits relative to the zone's center, in meters.
const WIDE_OFFSET := Vector3(26.0, 13.0, 30.0)
## How far in front of the player the selfie camera stands, in meters.
const SELFIE_DISTANCE: float = 3.2


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_warning("[Capture] screenshots need a window; skipped in a headless run")
		set_process(false)
		return
	var options := Net.dev_options()
	_dir = str(options.get("screenshot_dir"))
	_every = maxf(0.5, float(options.get("screenshot_every")))
	DirAccess.make_dir_recursive_absolute(_dir)


func _process(delta: float) -> void:
	_wait += delta
	if _wait < _every or _busy:
		return
	_wait = 0.0
	_save()


func _save() -> void:
	_busy = true
	for overlay: Node in get_tree().get_nodes_in_group("debug_overlay"):
		overlay.set("visible", true)
	var label := Net.player_name(Net.local_peer_id())
	if label == "":
		label = "peer"
	label = label.to_snake_case()
	await _shoot("%s/%s_%03d.png" % [_dir, label, _index])
	# Then the same moment from above, so every player in this zone is in frame.
	var own_camera := _own_camera()
	var above := _overhead_camera()
	if above != null:
		above.current = true
		await _shoot("%s/%s_%03d_above.png" % [_dir, label, _index])
		# And an angled wide shot of the whole zone, the way a person judges the art.
		var zone := _zone_center()
		if zone != Vector3.INF:
			above.look_at_from_position(zone + WIDE_OFFSET, zone + Vector3(0.0, 1.5, 0.0), Vector3.UP)
			await _shoot("%s/%s_%03d_wide.png" % [_dir, label, _index])
		# And a selfie: a few meters in front of this player's own character.
		var player := _own_player()
		if player != null:
			var face := player.global_position + Vector3(0.0, 1.45, 0.0)
			var forward := -player.global_basis.z
			above.look_at_from_position(face + forward * SELFIE_DISTANCE + Vector3(0.6, 0.25, 0.0), face, Vector3.UP)
			await _shoot("%s/%s_%03d_selfie.png" % [_dir, label, _index])
		above.current = false
		if own_camera != null:
			own_camera.current = true
	_index += 1
	_busy = false


func _shoot(path: String) -> void:
	# macOS stops drawing a covered or minimized window, and waiting for a frame
	# that never comes would stop every later screenshot.
	if not DisplayServer.window_can_draw():
		skipped += 1
		if skipped == 1:
			push_warning("[Capture] window cannot draw (covered or minimized); skipping screenshots until it can")
		return
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(path)
	if error != OK:
		push_error("[Capture] cannot save %s: %s" % [path, error_string(error)])


## Center of the zone this peer is in, or INF in transit.
func _zone_center() -> Vector3:
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		return Vector3.INF
	var zone_names := {Net.Zone.STORE: "StoreZone", Net.Zone.LOT: "LotZone", Net.Zone.BORDER: "BorderZone"}
	var zone_name: String = zone_names.get(Net.player_zone(Net.local_peer_id()), "")
	var zone := world.get_node_or_null(zone_name) as Node3D
	return zone.global_position if zone != null else Vector3.INF


## The player's own active camera, found on the player, not whatever is current:
## a skipped capture can leave the capture camera current.
func _own_camera() -> Camera3D:
	var player := _own_player()
	if player == null:
		return get_viewport().get_camera_3d()
	for node: Node in player.find_children("*", "Camera3D", true, false):
		if (node as Camera3D).current:
			return node as Camera3D
	return player.get_node_or_null("Visual/Head/FirstPerson") as Camera3D


func _own_player() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as Node3D
	return null


## A camera high above this peer's own player, looking down at it.
func _overhead_camera() -> Camera3D:
	var player := _own_player()
	if player == null:
		return null
	if _above == null:
		_above = Camera3D.new()
		_above.name = "CaptureOverhead"
		add_child(_above)
	var target := player.global_position
	_above.look_at_from_position(target + OVERHEAD_OFFSET, target, Vector3.UP)
	return _above
