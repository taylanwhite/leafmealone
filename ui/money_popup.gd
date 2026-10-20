extends Label3D

## Authority: local, cosmetic. A "+$9" that pops up, floats, and fades where money
## was made: a bag filled, bags loaded into the truck, the homeowner's cash taken.

const RISE_METERS: float = 1.2
const LIFE_SECONDS: float = 1.6
const GREEN := Color(0.55, 1.0, 0.45)

var _age: float = 0.0
var _start := Vector3.ZERO


## Pop "+$amount" at a world position, under the world node so it lives with the scene.
static func pop(tree: SceneTree, at: Vector3, amount: int) -> void:
	if amount <= 0 or Net.is_automated():
		return
	var world := tree.get_first_node_in_group("world") as Node3D
	if world == null:
		return
	var popup: Label3D = load("res://ui/money_popup.gd").new()
	popup.text = "+$%d" % amount
	world.add_child(popup)
	popup.global_position = at
	popup._start = at


func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	fixed_size = true
	pixel_size = 0.0022
	font_size = 34
	outline_size = 10
	modulate = GREEN
	outline_modulate = Color(0.05, 0.15, 0.05)
	no_depth_test = true
	render_priority = 12


func _process(delta: float) -> void:
	_age += delta
	var t := clampf(_age / LIFE_SECONDS, 0.0, 1.0)
	# Pops a little bigger first, then floats up and fades.
	var pop_scale := 1.0 + 0.4 * maxf(0.0, 1.0 - _age * 6.0)
	scale = Vector3.ONE * pop_scale
	global_position = _start + Vector3(0.0, RISE_METERS * (1.0 - pow(1.0 - t, 2.0)), 0.0)
	modulate.a = 1.0 - smoothstep(0.6, 1.0, t)
	outline_modulate.a = modulate.a
	if t >= 1.0:
		queue_free()
