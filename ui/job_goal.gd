extends Label

## Authority: local. One line near the bottom of the screen, quiet since
## driving:K (goal() below). It used to say what to do next at every step (board
## Chefty, grab the rake, bag it, carry it, talk to the homeowner); x1:text cut
## all of that (Taylan: "Our players are not idiots"), so the yard, Chefty, the
## homeowner and the prompts teach the loop (docs/GAME.md "Writing for players"),
## and driving:K moved its last job, where the job is, onto the phone's map. It
## reads state every peer already has, so it never sends anything. It pops a
## little when the line changes.

const _Strings = preload("res://ui/strings.gd")
const POP_SECONDS: float = 0.25

var _pop: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Its bottom sits just above the hotbar's band (ui/hotbar_hud.gd), and it
	# grows upward, so a taller line never runs down into the bar.
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_bottom = -Constants.HOTBAR_GOAL_LINE_Y
	offset_top = offset_bottom
	add_theme_font_size_override("font_size", 22)
	add_theme_color_override("font_color", Color(1.0, 0.93, 0.62))
	add_theme_color_override("font_outline_color", Color(0.12, 0.08, 0.04))
	add_theme_constant_override("outline_size", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	var next := ""
	if Net.current_state() == Net.State.IN_SESSION:
		# goal() gives the string as written; its {key:} tokens become the player's keys here.
		next = _Strings.keyed(goal(get_tree(), Net.local_peer_id()))
	if next != text:
		text = next
		_pop = POP_SECONDS
	visible = text != ""
	_pop = maxf(0.0, _pop - delta)
	pivot_offset = size * 0.5
	scale = Vector2.ONE * (1.0 + 0.18 * (_pop / POP_SECONDS))


## What the line says for this player right now: nothing, anywhere, since
## driving:K. The last thing it said, where the job is ("14 Maple Row · 470 m ↗"
## at the store and in town), is the phone's map now (ui/town_map_view.gd: the
## pin, the way there by road and how far) and the beacon over the curb in the
## world (levels/lots/site_marker.gd); Taylan's "just make it realistic" took the
## HUD off the drive. The label stays, quiet, so the HUD's layout (the caption
## stack, the overheads) and any line a later chunk truly needs have their place.
static func goal(_tree: SceneTree, _peer_id: int) -> String:
	return ""