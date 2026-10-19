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
	var own_camera := get_viewport().get_camera_3d()
	var above := _overhead_camera()
	if above != null:
		above.current = true
		await _shoot("%s/%s_%03d_above.png" % [_dir, label, _index])
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


## A camera high above this peer's own player, looking down at it.
func _overhead_camera() -> Camera3D:
	var own_name := str(Net.local_peer_id())
	var player: Node3D = null
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == own_name:
			player = node as Node3D
	if player == null:
		return null
	if _above == null:
		_above = Camera3D.new()
		_above.name = "CaptureOverhead"
		add_child(_above)
	var target := player.global_position
	_above.look_at_from_position(target + OVERHEAD_OFFSET, target, Vector3.UP)
	return _above
