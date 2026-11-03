extends Control

## Authority: local, cosmetic. The hotbar along the bottom of the screen
## (docs/GAME.md, "the hotbar"), drawn from what this player carries: five dark
## slots, the selected one raised with a Homie Depot orange rim, each with its
## key, its icon (ui/icons.gd; a colored chip with a four-letter tag when there is
## none), a stack badge, a tier tag, a paint or gas strip and the hose's
## hooked-up dot. After a switch the item's name shows above the bar with a use
## hint under it (the rake's hint stays while it's in hand: it is the old rake
## hint). A big thing in both arms slides a hands card up over the shrunken,
## dimmed slots. A refusal shakes the bar and flashes it red; emptied pockets
## get a toast. It reads replicated prop state and Player/Pockets only, so it
## never sends anything.
##
## The bar owns the bottom center up to the job goal line (Constants
## HOTBAR_GOAL_LINE_Y); it hides with any window (Ui.any_window_open: the shop,
## board, phone, a receipt, pause, Settings), in a Chefty seat, at Annex B,
## and off the yard when the pockets are empty (shown_when).

const _Hotbar = preload("res://net/components/hotbar.gd")
const _Icons = preload("res://ui/icons.gd")
const _Strings = preload("res://ui/strings.gd")
const _UiStyle = preload("res://ui/ui_style.gd")
const _ToolTiers = preload("res://core/tool_tiers.gd")

const SLOT_COLOR := Color(0.08, 0.06, 0.05, 0.62)
const SLOT_RADIUS: int = 10
const SELECT_BORDER: int = 3
const REFUSE_COLOR := Color(0.92, 0.2, 0.15)
const PAINT_COLOR := Color(0.35, 0.55, 0.95)
const HOSE_COLOR := Color(0.3, 0.65, 1.0)
const GAS_COLOR := Color(0.95, 0.55, 0.15)
const TEXT_COLOR := Color(0.97, 0.93, 0.84)
const NAME_COLOR := Color(1.0, 0.96, 0.85)
const TOAST_COLOR := Color(1.0, 0.72, 0.62)
const OUTLINE_COLOR := Color(0.1, 0.07, 0.04)
## Chips for things without an icon: the tool colors of the Homie Depot shelf
## (ui/shop_window.gd), and close cousins for the rest.
const CHIP_COLORS: Dictionary = {
	"leaf_blower": Color(0.95, 0.55, 0.15), "lawn_mower": Color(0.2, 0.55, 0.3), "ladder": Color(0.75, 0.75, 0.72),
	"hose": Color(0.25, 0.6, 0.35), "pressure_washer": Color(0.95, 0.8, 0.2), "hedge_trimmer": Color(0.85, 0.25, 0.2),
	"paint_roller": Color(0.35, 0.55, 0.85), "rake": Color(0.62, 0.45, 0.25), "turf_sign": Color(0.1, 0.55, 0.28),
	"gas_can": Color(0.8, 0.15, 0.12), "leaf_bag": Color(0.55, 0.42, 0.28), "gnome": Color(0.75, 0.2, 0.2),
	"trash": Color(0.4, 0.45, 0.5), "wheelbarrow": Color(0.3, 0.5, 0.75),
}
## Kinds whose use hint stays up the whole time they're in hand (the rake's is
## the game's core keys); every other hint shows with the name after a switch.
const HINT_STAYS: Array[String] = ["rake"]

# Text sizes (px at the 1280x720 design size).
const KEY_FONT: int = 12
const KEY_MIN_FONT: int = 7   # a long key name ("Mouse 4") shrinks down to this
const CHIP_FONT: int = 15
const BADGE_FONT: int = 13
const TAG_FONT: int = 11
const NAME_FONT: int = 16
const HINT_FONT: int = 12
const HINT_KEY_PX: float = 15.0
const TOAST_FONT: int = 16
const CARD_TITLE_FONT: int = 17
const CARD_LINE_FONT: int = 14
## A card line too long for the card shrinks down to this size before it is cut.
const CARD_MIN_FONT: int = 10
const CARD_WIDTH: float = 480.0
const CARD_HEIGHT: float = 70.0
const CARD_ICON: float = 54.0
const CARD_SLIDE_PX: float = 36.0
const ICON_INSET: float = 7.0
const STRIP_HEIGHT: float = 3.0
const NAME_FADE_SECONDS: float = 0.3

## The latest model() of this player's bar, for tests and remote play.
var last_model: Dictionary = {}
## The toast showing now ("" when none), and the refusal shake left (s), for tests.
var toast_text: String = ""
var shake_left: float = 0.0

var _pockets: Node = null
var _lift: Array[float] = []
var _card: float = 0.0
var _name_left: float = 0.0
var _name_text: String = ""
var _toast_left: float = 0.0
var _toast_total: float = 1.0
var _last_hand: int = 0
var _last_selected: int = -99
var _hint: RichTextLabel
var _hint_source: String = ""
var _card_hint: RichTextLabel
var _card_hint_source: String = ""
var _slot_box: StyleBoxFlat
var _rim_box: StyleBoxFlat
var _chip_box: StyleBoxFlat
var _card_box: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot_box = _UiStyle.box(SLOT_COLOR, SLOT_RADIUS, Color(0, 0, 0, 0), 0, 0)
	_rim_box = _UiStyle.box(Color(0, 0, 0, 0), SLOT_RADIUS, _UiStyle.ORANGE, SELECT_BORDER, 0)
	_rim_box.draw_center = false
	_chip_box = _UiStyle.box(Color.WHITE, 7, Color(0, 0, 0, 0), 0, 0)
	_card_box = _UiStyle.box(Color(0.08, 0.06, 0.05, 0.86), 12, _UiStyle.ORANGE, 2, 0)
	_hint = _rich(HINT_FONT)
	_card_hint = _rich(CARD_LINE_FONT - 1)
	# A rebind changes the keycaps the cached hint lines were built with.
	Settings.bindings_changed.connect(_forget_hints)


## Drop the cached hint bbcode so the next frame rebuilds it with today's keys.
func _forget_hints() -> void:
	_hint_source = ""
	_card_hint_source = ""


func _rich(font_size: int) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("normal_font_size", font_size)
	label.add_theme_color_override("default_color", TEXT_COLOR)
	label.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	label.add_theme_constant_override("outline_size", 4)
	label.visible = false
	add_child(label)
	return label


# ---------------------------------------------------------------- what the bar shows

## Everything the bar draws for this player, from replicated state (pure: tests
## and remote play read it too):
##   shown     the bar is up (shown_when)
##   selected  the selected slot, -1 for bare hands (Pockets.selected, predicted)
##   slots     capacity entries: {kind, count, name, icon, abbr, tier, paint, gas,
##             hooked}, kind "" for an empty slot
##   hand      the kind in hand, "" for none
##   name      what's in hand (or about to be), or "Bare hands"
##   hint      that thing's use hint, with {key:} tokens
##   hands     the big thing in both arms: {kind, name, icon, abbr, title, line,
##             hint}, or {} when the arms are free
static func model(tree: SceneTree, peer_id: int) -> Dictionary:
	var player := _player(tree, peer_id)
	var pockets: Node = player.get_node_or_null("Pockets") if player != null else null
	var selected := int(pockets.get("selected")) if pockets != null else -1
	var raw := _Hotbar.slots_of(tree, peer_id)
	var slots: Array = []
	for slot: Array in raw:
		slots.append(slot_view(slot))
	var hand := _Hotbar.in_hand(tree, peer_id)
	var arms := _Hotbar.arms_item(tree, peer_id)
	# What's coming out: what's in hand, else the selected slot's first (the
	# prediction runs ahead of the host by a round trip).
	var showing: Node = hand
	if showing == null and selected >= 0 and selected < raw.size() and not (raw[selected] as Array).is_empty():
		showing = (raw[selected] as Array)[0]
	var kind := str(showing.get("kind")) if showing != null else ""
	return {
		"shown": bar_shown(tree, peer_id),
		"selected": selected,
		"slots": slots,
		"hand": str(hand.get("kind")) if hand != null else "",
		"name": item_label(showing) if showing != null else str(_Strings.UI["hotbar_fists"]),
		"hint": hint_for(kind),
		"hands": hands_view(arms) if arms != null else {},
	}


## One slot: its first item (the one that comes out) and how many are stacked.
static func slot_view(slot: Array) -> Dictionary:
	if slot.is_empty():
		return {"kind": "", "count": 0}
	var item: Node = slot[0]
	var kind := str(item.get("kind"))
	var view := {
		"kind": kind,
		"count": slot.size(),
		"name": item_label(item),
		"icon": icon_for(kind),
		"abbr": str(_Strings.UI.get("hotbar_abbr_" + kind, kind.left(4).to_upper())),
		"tier": int(item.get("tier")) if Constants.TOOL_PRICES.has(kind) else Catalog.TIER_STOCK,
		"paint": -1.0,
		"gas": -1.0,
		"hooked": kind == "hose" and str(item.get("hose_source")) != "",
	}
	if kind == "paint_roller":
		view["paint"] = clampf(float(item.get("water")) / 100.0, 0.0, 1.0)
	elif kind == "gas_can":
		view["gas"] = clampf(float(item.get("water")) / 100.0, 0.0, 1.0)
	elif _ToolTiers.is_gas_tool(kind):
		view["gas"] = clampf(float(item.get("fuel")) / 100.0, 0.0, 1.0)
	return view


## The hands card for a big thing: "Lawn mower · 24 kg", then what's in it (a
## wheelbarrow's bags, a bag's worth), its own line (the gnome, the trash can) or
## its tank, and the G keys.
static func hands_view(item: Node) -> Dictionary:
	var kind := str(item.get("kind"))
	var name := item_label(item)
	var kg := roundi(float(item.call("weight_kg"))) if item.has_method("weight_kg") else 0
	var line := ""
	match kind:
		"wheelbarrow":
			line = str(_Strings.UI["hotbar_barrow"]) % [int(item.get("stored_bags")), Campaign.wheelbarrow_capacity(), int(item.get("stored_value"))]
		"leaf_bag":
			line = str(_Strings.UI["hotbar_bag"]) % int(item.get("value"))
		_:
			if _ToolTiers.is_gas_tool(kind):
				line = str(_Strings.UI["hotbar_gas"]) % roundi(float(item.get("fuel")))
			elif _Strings.UI.has("hint_" + kind):
				line = str(_Strings.UI["hint_" + kind])
			elif _Strings.UI.has("tool_blurb_" + kind):
				line = str(_Strings.UI["tool_blurb_" + kind])
	return {
		"kind": kind,
		"name": name,
		"icon": icon_for(kind),
		"abbr": str(_Strings.UI.get("hotbar_abbr_" + kind, kind.left(4).to_upper())),
		"title": str(_Strings.UI["hotbar_weight"]) % [name, kg],
		"line": _Strings.keyed(line),
		"hint": str(_Strings.UI["hotbar_arms_hint"]),
	}


## What a carried thing is called: a tool by its own label (it carries its tier,
## "Leaf blower Mk II"), everything else by its kind (Strings.item_name).
static func item_label(item: Node) -> String:
	var kind := str(item.get("kind"))
	var label := str(item.get("label"))
	if Constants.TOOL_PRICES.has(kind) and label != "":
		return label
	return _Strings.item_name(kind)


## The one-line use hint for a kind in hand, with {key:} tokens: the rake's keys,
## a tool's shop blurb, the gnome's, trash can's, sign's and gas can's own lines,
## and bare hands.
static func hint_for(kind: String) -> String:
	if kind == "":
		return str(_Strings.UI["hint_hands"])
	if kind == "rake":
		return str(_Strings.UI["hud_rake_hint"])
	if _Strings.UI.has("hint_" + kind):
		return str(_Strings.UI["hint_" + kind])
	return str(_Strings.UI.get("tool_blurb_" + kind, ""))


## The icon id for a kind when that icon exists (critic C9: Icons.for_kind), else "".
static func icon_for(kind: String) -> String:
	var id := _Icons.for_kind(kind)
	return id if _Icons.has(id) else ""


## Whether the bar is up for this player right now.
static func bar_shown(tree: SceneTree, peer_id: int) -> bool:
	var player := _player(tree, peer_id)
	var ui := tree.get_first_node_in_group("game_ui")
	return shown_when({
		"in_session": Net.current_state() == Net.State.IN_SESSION and player != null,
		"zone": Net.player_zone(peer_id),
		"window_open": ui != null and ui.has_method("any_window_open") and bool(ui.call("any_window_open")),
		"seated": player != null and player.has_method("in_vehicle") and bool(player.call("in_vehicle")),
		"carrying": not _Hotbar.items_of(tree, peer_id).is_empty(),
	})


## The visibility rule: never with a window up (pause and Settings included), in
## a Chefty seat (the drive HUD has the bottom right), or at Annex B; always
## on the yard; anywhere else only while carrying something.
static func shown_when(state: Dictionary) -> bool:
	if not bool(state.get("in_session", false)) or bool(state.get("window_open", false)) or bool(state.get("seated", false)):
		return false
	var zone := int(state.get("zone", Net.Zone.STORE))
	if zone == Net.Zone.BORDER:
		return false
	return zone == Net.Zone.LOT or bool(state.get("carrying", false))


static func _player(tree: SceneTree, peer_id: int) -> Node:
	for node: Node in tree.get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node
	return null


# ---------------------------------------------------------------- frame by frame

func _process(delta: float) -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	var peer_id := Net.local_peer_id()
	if Net.current_state() != Net.State.IN_SESSION or peer_id == 0:
		last_model = {}
		_hint.visible = false
		_card_hint.visible = false
		# Nothing from the last session carries into the next one.
		toast_text = ""
		_toast_left = 0.0
		shake_left = 0.0
		_name_left = 0.0
		_last_selected = -99
		_forget_hints()
		_attach(null)
		queue_redraw()
		return
	var player := _player(get_tree(), peer_id)
	_attach(player.get_node_or_null("Pockets") if player != null else null)
	last_model = model(get_tree(), peer_id)
	var slots: Array = last_model["slots"]
	var selected := int(last_model["selected"])
	var hand := _Hotbar.in_hand(get_tree(), peer_id)
	var hand_id := hand.get_instance_id() if hand != null else 0
	# A switch (or a draw, a pickup, a drop): the name comes up again.
	if _last_selected != -99 and (selected != _last_selected or hand_id != _last_hand) and (last_model["hands"] as Dictionary).is_empty():
		_name_left = Constants.HOTBAR_NAME_SECONDS
		_name_text = str(last_model["name"])
	_last_selected = selected
	_last_hand = hand_id
	_name_left = maxf(0.0, _name_left - delta)
	shake_left = maxf(0.0, shake_left - delta)
	_toast_left = maxf(0.0, _toast_left - delta)
	if _toast_left <= 0.0:
		toast_text = ""
	while _lift.size() < slots.size():
		_lift.append(0.0)
	var step := delta / maxf(Constants.HOTBAR_SELECT_SECONDS, 0.001)
	for index: int in slots.size():
		_lift[index] = move_toward(_lift[index], 1.0 if index == selected else 0.0, step)
	var arms := not (last_model["hands"] as Dictionary).is_empty()
	_card = move_toward(_card, 1.0 if arms else 0.0, delta / maxf(Constants.HOTBAR_CARD_SECONDS, 0.001))
	_place_hints()
	queue_redraw()


## Follow the local player's Pockets (a new player node after a rejoin gets a new one).
func _attach(pockets: Node) -> void:
	if pockets == _pockets:
		return
	if _pockets != null and is_instance_valid(_pockets):
		_pockets.disconnect("refused", _on_refused)
		_pockets.disconnect("notice", _on_notice)
	_pockets = pockets
	if _pockets != null:
		_pockets.connect("refused", _on_refused)
		_pockets.connect("notice", _on_notice)


## "eh?": a shake, a red flash, and why ("Pockets full", "Hands full").
func _on_refused(reason: String) -> void:
	shake_left = Constants.HOTBAR_SHAKE_SECONDS
	var key := "hotbar_arms_full" if reason == "arms_full" else "hotbar_full"
	_toast(_Strings.keyed(str(_Strings.UI[key])), Constants.HOTBAR_TOAST_SECONDS)


## Emptied pockets: the NICE BOYS took inventory, or you walked off the job.
func _on_notice(kind: String) -> void:
	var key := "hotbar_confiscated" if kind == "confiscated" else "hotbar_left"
	_toast(_Strings.keyed(str(_Strings.UI[key])), Constants.HOTBAR_NOTICE_SECONDS)


func _toast(text: String, seconds: float) -> void:
	toast_text = text
	_toast_left = seconds
	_toast_total = seconds
	_name_left = 0.0


func _shake() -> Vector2:
	if shake_left <= 0.0:
		return Vector2.ZERO
	var share := shake_left / Constants.HOTBAR_SHAKE_SECONDS
	return Vector2(sin(shake_left * TAU * Constants.HOTBAR_SHAKE_HZ) * Constants.HOTBAR_SHAKE_PX * share, 0.0)


## Half the width of the slot row with a selected slot grown, centered on the
## screen: other bottom-band text (the quip caption) keeps left of it.
static func slots_half_width() -> float:
	var slots := float(Constants.HOTBAR_SLOTS)
	return (Constants.HOTBAR_SLOT_PX * slots * Constants.HOTBAR_SELECT_SCALE + Constants.HOTBAR_SLOT_GAP * (slots - 1.0)) * 0.5


## The bar's top (px above the bottom edge) with the selected slot raised and grown.
func _bar_top() -> float:
	return Constants.HOTBAR_BOTTOM_MARGIN + Constants.HOTBAR_SLOT_PX * (1.0 + (Constants.HOTBAR_SELECT_SCALE - 1.0) * 0.5) + Constants.HOTBAR_SELECT_RAISE


## The hint line just above the bar, and the G keys inside the hands card.
func _place_hints() -> void:
	var view := size
	var shown := bool(last_model.get("shown", false))
	var hint := str(last_model.get("hint", ""))
	var kind := str(last_model.get("hand", ""))
	var stays := HINT_STAYS.has(kind)
	var hint_alpha := 0.0
	if shown and _card < 0.5 and hint != "" and toast_text == "":
		if stays:
			hint_alpha = 0.8
		elif _name_left > 0.0:
			hint_alpha = clampf(_name_left / NAME_FADE_SECONDS, 0.0, 1.0)
	_hint.visible = hint_alpha > 0.0
	if _hint.visible:
		if hint != _hint_source:
			_hint_source = hint
			_hint.text = "[center]%s[/center]" % _Icons.rich(hint, HINT_KEY_PX)
		_hint.modulate.a = hint_alpha
		_hint.size = Vector2(view.x - 32.0, 0.0)
		_hint.reset_size()
		_hint.size.x = view.x - 32.0
		_hint.position = Vector2(16.0, view.y - _bar_top() - 2.0 - _hint.size.y) + _shake()
	var hands: Dictionary = last_model.get("hands", {})
	_card_hint.visible = shown and _card > 0.01 and not hands.is_empty()
	if _card_hint.visible:
		var source := str(hands["hint"])
		if source != _card_hint_source:
			_card_hint_source = source
			_card_hint.text = _Icons.rich(source, HINT_KEY_PX)
		var card := _card_rect()
		_card_hint.modulate.a = _card
		_card_hint.reset_size()
		_card_hint.position = card.position + Vector2(CARD_ICON + 20.0, card.size.y - _card_hint.size.y - 6.0)


## Where the hands card sits, sliding up from behind the bar as it comes in.
func _card_rect() -> Rect2:
	var view := size
	var slots_top := Constants.HOTBAR_BOTTOM_MARGIN + Constants.HOTBAR_SLOT_PX * Constants.HOTBAR_ARMS_SLOT_SCALE
	var eased := 1.0 - pow(1.0 - _card, 3.0)
	var bottom := view.y - slots_top - 4.0 + (1.0 - eased) * CARD_SLIDE_PX
	return Rect2(Vector2((view.x - CARD_WIDTH) * 0.5, bottom - CARD_HEIGHT) + _shake(), Vector2(CARD_WIDTH, CARD_HEIGHT))


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if last_model.is_empty():
		return
	var font := get_theme_default_font()
	if bool(last_model.get("shown", false)):
		_draw_slots(font)
		if _card > 0.01 and not (last_model["hands"] as Dictionary).is_empty():
			_draw_card(font, last_model["hands"])
		elif _name_left > 0.0 and toast_text == "":
			var alpha := clampf(_name_left / NAME_FADE_SECONDS, 0.0, 1.0)
			_line(font, _name_text, NAME_FONT, NAME_COLOR, alpha)
	# A toast shows even with the bar down (caught on the way to Annex B,
	# walked off to the store), but never over a window.
	if toast_text != "" and not _window_open():
		_line(font, toast_text, TOAST_FONT, TOAST_COLOR, clampf(_toast_left / NAME_FADE_SECONDS, 0.0, 1.0))


## A centered line of text in the band between the bar and the job goal line.
func _line(font: Font, text: String, font_size: int, color: Color, alpha: float) -> void:
	var view := size
	var baseline := view.y - _bar_top() - 2.0 - float(HINT_FONT) - 8.0
	var at := Vector2(0.0, baseline) + _shake()
	var faded := color
	faded.a *= alpha
	var outline := OUTLINE_COLOR
	outline.a *= alpha
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, view.x, font_size, 5, outline)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, view.x, font_size, faded)


func _draw_slots(font: Font) -> void:
	var view := size
	var slots: Array = last_model["slots"]
	var selected := int(last_model["selected"])
	var eased_card := 1.0 - pow(1.0 - _card, 3.0)
	var scale_all := lerpf(1.0, Constants.HOTBAR_ARMS_SLOT_SCALE, eased_card)
	var alpha := lerpf(1.0, Constants.HOTBAR_ARMS_DIM, eased_card)
	var slot := Constants.HOTBAR_SLOT_PX * scale_all
	var gap := Constants.HOTBAR_SLOT_GAP * scale_all
	var count := slots.size()
	var width := slot * count + gap * maxf(0.0, count - 1.0)
	var left := (view.x - width) * 0.5
	var top := view.y - Constants.HOTBAR_BOTTOM_MARGIN - slot
	var shake := _shake()
	var flash := shake_left / Constants.HOTBAR_SHAKE_SECONDS if Constants.HOTBAR_SHAKE_SECONDS > 0.0 else 0.0
	for index: int in count:
		var lift := 1.0 - pow(1.0 - (_lift[index] if index < _lift.size() else 0.0), 3.0)
		var grow := 1.0 + (Constants.HOTBAR_SELECT_SCALE - 1.0) * lift
		var center := Vector2(left + index * (slot + gap) + slot * 0.5, top + slot * 0.5 - Constants.HOTBAR_SELECT_RAISE * lift * (1.0 - eased_card)) + shake
		var rect := Rect2(center - Vector2.ONE * slot * grow * 0.5, Vector2.ONE * slot * grow)
		_slot_box.bg_color = Color(SLOT_COLOR, SLOT_COLOR.a * alpha).lerp(Color(REFUSE_COLOR, 0.55 * alpha), flash * 0.5)
		draw_style_box(_slot_box, rect)
		_draw_slot(font, slots[index], rect, index, alpha, scale_all)
		if index == selected and lift > 0.01:
			_rim_box.border_color = Color(_UiStyle.ORANGE.lerp(REFUSE_COLOR, flash), alpha * lift)
			draw_style_box(_rim_box, rect)
	if eased_card > 0.5:
		var tag := str(_Strings.UI["hotbar_hands_full_tag"])
		var at := Vector2(0.0, top + slot * 0.5 + TAG_FONT * 0.4) + shake
		draw_string_outline(font, at, tag, HORIZONTAL_ALIGNMENT_CENTER, view.x, TAG_FONT + 2, 5, OUTLINE_COLOR)
		draw_string(font, at, tag, HORIZONTAL_ALIGNMENT_CENTER, view.x, TAG_FONT + 2, _UiStyle.ORANGE)


func _draw_slot(font: Font, view: Dictionary, rect: Rect2, index: int, alpha: float, scale_all: float) -> void:
	var text_color := Color(TEXT_COLOR, 0.85 * alpha)
	var kind := str(view.get("kind", ""))
	# The slot's key, top left: its binding as Settings names it ("1", "Q",
	# "Mouse 4"). A long name shrinks to fit the slot rather than lying with the
	# slot's number.
	var key := _Icons.key_label(StringName("slot_%d" % (index + 1)))
	var key_size := maxi(8, roundi(KEY_FONT * scale_all))
	var key_room := rect.size.x - 10.0
	while key_size > KEY_MIN_FONT and font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, key_size).x > key_room:
		key_size -= 1
	draw_string(font, rect.position + Vector2(5.0, 4.0 + key_size), key, HORIZONTAL_ALIGNMENT_LEFT, -1, key_size, text_color)
	if kind == "":
		if index == int(last_model.get("selected", -1)) and _Icons.has("hand"):
			_draw_icon(_Icons.texture("hand"), rect.grow(-ICON_INSET * 1.6), Color(1, 1, 1, 0.35 * alpha))
		return
	var inner := rect.grow(-ICON_INSET * scale_all)
	var icon := str(view.get("icon", ""))
	if icon != "":
		_draw_icon(_Icons.texture(icon), inner, Color(1, 1, 1, alpha))
	else:
		_chip_box.bg_color = Color(CHIP_COLORS.get(kind, Color.GRAY), alpha)
		var chip := inner.grow(-3.0 * scale_all)
		draw_style_box(_chip_box, chip)
		var chip_size := maxi(8, roundi(CHIP_FONT * scale_all))
		var baseline := chip.position.y + chip.size.y * 0.5 + chip_size * 0.35
		draw_string_outline(font, Vector2(chip.position.x, baseline), str(view["abbr"]), HORIZONTAL_ALIGNMENT_CENTER, chip.size.x, chip_size, 4, Color(OUTLINE_COLOR, alpha))
		draw_string(font, Vector2(chip.position.x, baseline), str(view["abbr"]), HORIZONTAL_ALIGNMENT_CENTER, chip.size.x, chip_size, Color(Color.WHITE, alpha))
	var badge_size := maxi(8, roundi(BADGE_FONT * scale_all))
	var bottom := rect.end.y - STRIP_HEIGHT - 6.0
	# A stack: "×3", bottom right.
	if int(view.get("count", 0)) > 1:
		var badge := str(_Strings.UI["hotbar_stack"]) % int(view["count"])
		var at := Vector2(rect.position.x, bottom)
		draw_string_outline(font, at, badge, HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 5.0, badge_size, 4, Color(OUTLINE_COLOR, alpha))
		draw_string(font, at, badge, HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 5.0, badge_size, Color(Color.WHITE, alpha))
	# A tool's tier: USED, II or III, bottom left.
	var tier := int(view.get("tier", Catalog.TIER_STOCK))
	if tier != Catalog.TIER_STOCK and _Strings.UI.has("hotbar_tier_%d" % tier):
		var tag := str(_Strings.UI["hotbar_tier_%d" % tier])
		var tag_size := maxi(7, roundi(TAG_FONT * scale_all))
		var at := rect.position + Vector2(5.0, rect.size.y - STRIP_HEIGHT - 6.0)
		draw_string_outline(font, at, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tag_size, 4, Color(OUTLINE_COLOR, alpha))
		draw_string(font, at, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tag_size, Color(_UiStyle.ORANGE.lightened(0.3), alpha))
	# The roller's paint and a gas tool's (or the can's) gas: a thin strip along the bottom.
	var strip := -1.0
	var strip_color := PAINT_COLOR
	if float(view.get("paint", -1.0)) >= 0.0:
		strip = float(view["paint"])
	elif float(view.get("gas", -1.0)) >= 0.0:
		strip = float(view["gas"])
		strip_color = GAS_COLOR
	if strip >= 0.0:
		var track := Rect2(rect.position.x + 6.0, rect.end.y - STRIP_HEIGHT - 3.0, rect.size.x - 12.0, STRIP_HEIGHT)
		draw_rect(track, Color(0.0, 0.0, 0.0, 0.5 * alpha))
		draw_rect(Rect2(track.position, Vector2(track.size.x * strip, track.size.y)), Color(strip_color, alpha))
	# A hooked-up hose: a blue dot, top right.
	if bool(view.get("hooked", false)):
		draw_circle(Vector2(rect.end.x - 9.0, rect.position.y + 9.0), 4.5 * scale_all, Color(HOSE_COLOR, alpha))


func _draw_card(font: Font, hands: Dictionary) -> void:
	var rect := _card_rect()
	var alpha := _card
	var fill := _card_box.bg_color
	_card_box.bg_color = Color(fill, 0.86 * alpha)
	_card_box.border_color = Color(_UiStyle.ORANGE, alpha)
	draw_style_box(_card_box, rect)
	var icon_rect := Rect2(rect.position + Vector2(10.0, (rect.size.y - CARD_ICON) * 0.5), Vector2.ONE * CARD_ICON)
	var icon := str(hands.get("icon", ""))
	if icon != "":
		_draw_icon(_Icons.texture(icon), icon_rect, Color(1, 1, 1, alpha))
	else:
		_chip_box.bg_color = Color(CHIP_COLORS.get(str(hands["kind"]), Color.GRAY), alpha)
		draw_style_box(_chip_box, icon_rect.grow(-4.0))
		var baseline := icon_rect.position.y + icon_rect.size.y * 0.5 + CHIP_FONT * 0.35
		draw_string(font, Vector2(icon_rect.position.x, baseline), str(hands["abbr"]), HORIZONTAL_ALIGNMENT_CENTER, icon_rect.size.x, CHIP_FONT, Color(Color.WHITE, alpha))
	var text_left := rect.position.x + CARD_ICON + 20.0
	var text_width := rect.end.x - text_left - 10.0
	draw_string(font, Vector2(text_left, rect.position.y + 8.0 + CARD_TITLE_FONT), str(hands["title"]), HORIZONTAL_ALIGNMENT_LEFT, text_width, CARD_TITLE_FONT, Color(NAME_COLOR, alpha))
	var line := str(hands.get("line", ""))
	if line != "":
		var line_size := CARD_LINE_FONT
		while line_size > CARD_MIN_FONT and font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, line_size).x > text_width:
			line_size -= 1
		draw_string(font, Vector2(text_left, rect.position.y + 12.0 + CARD_TITLE_FONT + CARD_LINE_FONT), line, HORIZONTAL_ALIGNMENT_LEFT, text_width, line_size, Color(TEXT_COLOR, 0.85 * alpha))


## An icon fit inside rect, keeping its shape.
func _draw_icon(texture: Texture2D, rect: Rect2, tint: Color) -> void:
	if texture == null:
		return
	var aspect := float(texture.get_width()) / maxf(1.0, float(texture.get_height()))
	var fit := rect.size
	if aspect >= 1.0:
		fit.y = rect.size.x / aspect
	else:
		fit.x = rect.size.y * aspect
	fit = fit.min(rect.size)
	draw_texture_rect(texture, Rect2(rect.position + (rect.size - fit) * 0.5, fit), false, tint)


func _window_open() -> bool:
	var ui := get_tree().get_first_node_in_group("game_ui")
	return ui != null and ui.has_method("any_window_open") and bool(ui.call("any_window_open"))
