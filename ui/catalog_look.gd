extends RefCounted

## Authority: local, cosmetic. The sticker-catalog look the store's paper windows
## share (gap-specs/icons.json chunk D; docs/GAME.md, "Icons"): the brand header,
## the wallet with its cash icon, an item's shelf (the item icon on a tinted
## shelf, stamped OWNED with a check or dimmed behind a lock), the price row,
## a row of task badges, star rows, and the hover bounce and buy pop. Used like
## _Icons, through a preload, by ui/shop_window.gd, ui/job_board_window.gd,
## ui/payout_window.gd and ui/day_summary.gd, so a redesigned card (shops chunk 4's
## tabs and tier cards) gets the same look by calling these instead of hand-rolling
## TextureRects. Every icon goes through _Icons.rect, so it carries meta "icon"
## (net/dev/icons_test.gd reads it) and a missing icon is an empty spacer.

const _Icons = preload("res://ui/icons.gd")

## The ink the paper windows print in (the same as shop_window.gd's INK).
const INK := Color(0.17, 0.14, 0.11)

## The shelf an item sits on, and the item on it.
const SHELF_HEIGHT: float = 92.0
const SHELF_RADIUS: int = 10
const SHELF_MARGIN: int = 4
## How much lighter than the item's swatch color its shelf is.
const SHELF_LIGHTEN: float = 0.55
## The OWNED check and the rank lock stamped in the shelf's top-right corner.
const STAMP_PX: float = 26.0
const STAMP_INSET: float = 4.0
## A shelf whose item the crew's rank can't buy yet shows the item this faint.
const LOCKED_ALPHA: float = 0.45
## The price tag stuck on a shelf's corner.
const TAG_PAPER := Color(1.0, 0.99, 0.95)
const TAG_RADIUS: int = 6
const TAG_MARGIN_X: int = 6
const TAG_MARGIN_Y: int = 1
## How much of a shelf's left the price tag keeps for itself (px) at least: the
## item is centered in the rest. A wider tag ($1200) keeps its own width plus
## TAG_GAP, once it is laid out.
const TAG_ROOM: int = 72
const TAG_GAP: int = 4
## The brand mark beside a window's title, the cash icon beside the wallet.
const BRAND_PX: float = 40.0
const WALLET_PX: float = 22.0
## Icons in a card's price and pay rows, and its "Unlocks:" task badges.
const PRICE_PX: float = 18.0
const BADGE_ROW_PX: float = 20.0
## A tool the crew lacks, and its lock, on a job card's task line.
const MISSING_TOOL_PX: float = 16.0
const MISSING_TOOL_ALPHA: float = 0.55
## A row of star icons (a review, the crew rating).
const STAR_PX: float = 18.0


## The window's title with the brand's mark in front: Homie Depot's orange circle.
static func brand_title(brand_id: String, title: Label) -> HBoxContainer:
	var row := _Icons.row(brand_id, title, BRAND_PX)
	row.size_flags_horizontal = title.size_flags_horizontal
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return row


## The wallet in a window's header: [cash] $340.
static func wallet(label: Label) -> HBoxContainer:
	return _Icons.row("cash", label, WALLET_PX)


## An item's shelf: its icon (SIZE_CARD tall) on a panel tinted from the item's old
## swatch color, with an OWNED check or, when the rank can't buy it yet, a lock over
## a faded item. The icon node is the shelf's meta "shelf_icon", for hover() and pop().
## A price_tag() goes in the shelf's bottom-left corner, like a sticker on the shelf edge.
static func shelf(icon_id: String, tint: Color, owned: bool, locked: bool, tag: Control = null) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0.0, SHELF_HEIGHT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = tint.lightened(SHELF_LIGHTEN)
	box.set_corner_radius_all(SHELF_RADIUS)
	box.border_color = tint.lightened(SHELF_LIGHTEN * 0.5)
	box.border_width_bottom = 3
	box.set_content_margin_all(SHELF_MARGIN)
	panel.add_theme_stylebox_override("panel", box)
	var icon := _Icons.rect(icon_id, _Icons.SIZE_CARD)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if locked and not owned:
		icon.modulate = Color(1.0, 1.0, 1.0, LOCKED_ALPHA)
	if tag != null:
		# icons:catalog: the item stands right of its tag, so the tag never covers
		# the chip in the icon's corner (a tool's USED / II / III, the can's GAS).
		var room := MarginContainer.new()
		room.mouse_filter = Control.MOUSE_FILTER_IGNORE
		room.add_theme_constant_override("margin_left", TAG_ROOM)
		room.add_child(icon)
		panel.add_child(room)
		# The tag's width comes from its digits and the theme's font, known only
		# once it is laid out: widen the room to clear it.
		tag.resized.connect(func() -> void:
			if is_instance_valid(room):
				room.add_theme_constant_override("margin_left", maxi(TAG_ROOM, STAMP_INSET + int(ceil(tag.size.x)) + TAG_GAP))
		)
	else:
		panel.add_child(icon)
	panel.set_meta("shelf_icon", icon)
	if not owned and not locked and tag == null:
		return panel
	# The panel lays every child over its whole rect; stamps and tags are anchored in it.
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(overlay)
	if owned or locked:
		var stamp := _Icons.rect("check" if owned else "lock", STAMP_PX)
		stamp.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		stamp.offset_left = -stamp.custom_minimum_size.x - STAMP_INSET
		stamp.offset_right = -STAMP_INSET
		stamp.offset_top = STAMP_INSET
		stamp.offset_bottom = STAMP_INSET + STAMP_PX
		overlay.add_child(stamp)
	if tag != null:
		# Pinned to the bottom-left corner at zero size; it grows up and right to fit.
		tag.anchor_left = 0.0
		tag.anchor_right = 0.0
		tag.anchor_top = 1.0
		tag.anchor_bottom = 1.0
		tag.offset_left = STAMP_INSET
		tag.offset_right = STAMP_INSET
		tag.offset_top = -STAMP_INSET
		tag.offset_bottom = -STAMP_INSET
		tag.grow_horizontal = Control.GROW_DIRECTION_END
		tag.grow_vertical = Control.GROW_DIRECTION_BEGIN
		overlay.add_child(tag)
	return panel


## A price or pay line with the cash icon in front: [cash] $180.
static func price_row(label: Label) -> HBoxContainer:
	return _Icons.row("cash", label, PRICE_PX)


## A paper price tag, [cash] $180, for a shelf's corner (shelf(..., tag)).
static func price_tag(label: Label) -> PanelContainer:
	var tag := PanelContainer.new()
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = TAG_PAPER
	box.set_corner_radius_all(TAG_RADIUS)
	box.border_color = INK.lightened(0.55)
	box.set_border_width_all(1)
	box.content_margin_left = TAG_MARGIN_X
	box.content_margin_right = TAG_MARGIN_X
	box.content_margin_top = TAG_MARGIN_Y
	box.content_margin_bottom = TAG_MARGIN_Y
	tag.add_theme_stylebox_override("panel", box)
	tag.add_child(_Icons.row("cash", label, PRICE_PX))
	return tag


## A wrapping row of task badges, one per task id ("rake_leaves"), after an
## optional lead label ("Unlocks:"). Each badge's tooltip is its task's name
## (names, in the same order), so the words are a hover away.
static func task_badges(tasks: PackedStringArray, names: PackedStringArray = PackedStringArray(), lead: Label = null, px: float = BADGE_ROW_PX) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flow.add_theme_constant_override("h_separation", 3)
	flow.add_theme_constant_override("v_separation", 3)
	if lead != null:
		flow.add_child(lead)
	for index: int in tasks.size():
		var badge := _Icons.rect(_Icons.for_task(tasks[index]), px)
		if index < names.size():
			badge.tooltip_text = names[index]
			# PASS, not STOP: the card under it still sees the hover.
			badge.mouse_filter = Control.MOUSE_FILTER_PASS
		flow.add_child(badge)
	return flow


## A task line on a job card: its badge, its words and, when the crew lacks the
## tool, that tool's icon faded behind a lock.
static func task_line(task: String, label: Label, missing_tool: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge := _Icons.rect(_Icons.for_task(task), _Icons.SIZE_ROW)
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(badge)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	if missing_tool != "":
		var tool := _Icons.rect(_Icons.for_tool(missing_tool), MISSING_TOOL_PX)
		tool.modulate = Color(1.0, 1.0, 1.0, MISSING_TOOL_ALPHA)
		tool.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(tool)
		var lock := _Icons.rect("lock", MISSING_TOOL_PX)
		lock.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(lock)
	return row


## Five star icons, filled to the nearest whole star (the same rounding as
## Strings.stars, the plain-text version).
static func stars(rating: float, px: float = STAR_PX) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 1)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var filled := clampi(int(round(rating)), 0, 5)
	for index: int in 5:
		row.add_child(_Icons.rect("star" if index < filled else "star_empty", px))
	return row


## Hovering a card bounces its shelf icon up a little, with the UI tick.
static func hover(card: Control, shelf_panel: Control) -> void:
	if not shelf_panel.has_meta("shelf_icon"):
		return
	var icon := shelf_panel.get_meta("shelf_icon") as Control
	if icon == null:
		return
	card.mouse_entered.connect(func() -> void:
		_tween_scale(icon, Vector2.ONE * Constants.ICONS_HOVER_SCALE, Constants.ICONS_HOVER_SECONDS)
		sfx(card, "ui_tick")
	)
	card.mouse_exited.connect(func() -> void:
		_tween_scale(icon, Vector2.ONE, Constants.ICONS_HOVER_SECONDS)
	)


## A squash-and-stretch pop on an icon: wide and short, tall and thin, settle.
## Shown when the host confirms a buy; the register sound is audio/cue_hooks.gd's
## (critic C11), so this is silent. from_seconds starts it part-way through: a
## card redrawn mid-pop carries on rather than popping again (shop_window).
static func pop(icon: Control, from_seconds: float = 0.0) -> void:
	if icon == null or not icon.is_inside_tree():
		return
	icon.pivot_offset = icon.size * 0.5
	var stretch := Constants.ICONS_POP_STRETCH
	var step := Constants.ICONS_POP_SECONDS / 3.0
	var tween := _fresh_tween(icon)
	tween.tween_property(icon, "scale", Vector2(1.0 + stretch, 1.0 - stretch), step)
	tween.tween_property(icon, "scale", Vector2(1.0 - stretch * 0.5, 1.0 + stretch * 0.5), step)
	tween.tween_property(icon, "scale", Vector2.ONE, step).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if from_seconds > 0.0:
		tween.custom_step(from_seconds)


## Plays a UI sound through the sfx group (audio/sfx.gd), when there is one.
static func sfx(from: Node, id: String) -> void:
	if from == null or not from.is_inside_tree():
		return
	var player := from.get_tree().get_first_node_in_group("sfx")
	if player != null:
		player.call("play", id)


static func _tween_scale(icon: Control, to: Vector2, seconds: float) -> void:
	if not icon.is_inside_tree():
		return
	icon.pivot_offset = icon.size * 0.5
	var tween := _fresh_tween(icon)
	tween.tween_property(icon, "scale", to, seconds).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## One tween per icon: a new one replaces the running one, so hovering on and off
## quickly never leaves two fighting over the scale.
static func _fresh_tween(icon: Control) -> Tween:
	# has_meta first: get_meta's null default counts as "no default", and errors.
	var running := icon.get_meta("catalog_tween") as Tween if icon.has_meta("catalog_tween") else null
	if running != null and running.is_valid():
		running.kill()
	var tween := icon.create_tween()
	icon.set_meta("catalog_tween", tween)
	return tween
