extends Control

## Authority: local. The wind-up bar while you hold G with something in hand
## (player.gd _step_wind_up): it fills green to orange as the throw builds to
## full power. Hold on past that and it turns red and shakes as you strain,
## with a second bar creeping across toward the moment you faint and drop it.

const WIDTH: float = 280.0
const HEIGHT: float = 18.0
const LOW := Color(0.45, 0.85, 0.35)
const HIGH := Color(1.0, 0.6, 0.15)
const STRAIN := Color(0.95, 0.2, 0.15)

var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Covers the screen and draws in screen space, near the bottom middle.
func _process(delta: float) -> void:
	_time += delta
	position = Vector2.ZERO
	size = get_viewport_rect().size
	queue_redraw()


func _draw() -> void:
	var player := _own_player()
	if player == null:
		return
	var seconds := float(player.call("wind_up_seconds"))
	if seconds < Constants.THROW_TAP_SECONDS:
		return
	var view := get_viewport_rect().size
	var shake := Vector2.ZERO
	var straining := seconds >= Constants.THROW_STRAIN_SECONDS
	if straining:
		var hard := clampf((seconds - Constants.THROW_STRAIN_SECONDS) / (Constants.THROW_FAINT_SECONDS - Constants.THROW_STRAIN_SECONDS), 0.0, 1.0)
		shake = Vector2(sin(_time * 70.0), cos(_time * 53.0)) * (2.0 + hard * 4.0)
	var origin := Vector2((view.x - WIDTH) * 0.5, view.y - 112.0) + shake
	draw_rect(Rect2(origin - Vector2(4.0, 4.0), Vector2(WIDTH + 8.0, HEIGHT + 8.0)), Color(0.08, 0.06, 0.05, 0.7))
	var share := clampf(seconds / Constants.THROW_CHARGE_SECONDS, 0.0, 1.0)
	var fill := LOW.lerp(HIGH, share)
	if straining:
		fill = HIGH.lerp(STRAIN, 0.5 + 0.5 * sin(_time * 18.0))
	draw_rect(Rect2(origin, Vector2(WIDTH * share, HEIGHT)), fill)
	if straining:
		var toward_faint := clampf((seconds - Constants.THROW_STRAIN_SECONDS) / (Constants.THROW_FAINT_SECONDS - Constants.THROW_STRAIN_SECONDS), 0.0, 1.0)
		draw_rect(Rect2(origin + Vector2(0.0, HEIGHT - 5.0), Vector2(WIDTH * toward_faint, 5.0)), Color(1.0, 1.0, 1.0, 0.9))


func _own_player() -> Node:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node
	return null
