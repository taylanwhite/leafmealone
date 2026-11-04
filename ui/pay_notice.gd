extends Label

## Authority: local. Pay a crewmate (shops chunk 8), on screen and in the
## world. Sits top left (ui/ui_root.gd): under the HUD's wallet block when that
## shows, in its place when it doesn't (at the store).
## When a crewmate pays you, it says who ("Sam sent you $20") for
## Constants.PAY_NOTICE_SECONDS, fading out: the wallet's number only says how
## much. The payer gets no line (their wallet and the bill leaving their hand say
## it). Every payment between two players standing near each other also plays
## in the world on every peer (player/cash_toss.gd); this node is the one place
## that hears Shops.gave and starts it.

const _Strings = preload("res://ui/strings.gd")
const _CashToss = preload("res://player/cash_toss.gd")

## The HUD's top-left block (ui_root's HudRows), to sit under.
var rows: Control
## Space between the block and this line (px).
const GAP: float = 6.0
const FONT_SIZE: int = 20

var _left: float = 0.0
var _shops: Node


func _ready() -> void:
	name = "PayNotice"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Cash green, outlined so it reads over the store's orange as well as the sky.
	add_theme_font_size_override("font_size", FONT_SIZE)
	add_theme_color_override("font_color", Color(0.7, 1.0, 0.62))
	add_theme_color_override("font_outline_color", Color(0.05, 0.12, 0.05))
	add_theme_constant_override("outline_size", 6)
	_find_shops()
	get_tree().node_added.connect(func(node: Node) -> void:
		if node.name == "Shops":
			_find_shops.call_deferred()
	)


func _find_shops() -> void:
	var shops := get_tree().get_first_node_in_group("shops")
	if shops == null or (is_instance_valid(_shops) and shops == _shops):
		return
	_shops = shops
	shops.connect("gave", _on_gave)


func _on_gave(from_peer: int, to_peer: int, amount: int) -> void:
	_CashToss.toss(get_tree(), from_peer, to_peer)
	if to_peer != Net.local_peer_id():
		return
	text = str(_Strings.SHOP_UI["pay_crewmate_got"]) % [Net.player_name(from_peer), amount]
	_left = Constants.PAY_NOTICE_SECONDS
	visible = true
	modulate.a = 1.0


func _process(delta: float) -> void:
	if _left <= 0.0:
		return
	_left = maxf(_left - delta, 0.0)
	modulate.a = clampf(_left / Constants.PAY_NOTICE_FADE, 0.0, 1.0)
	if rows != null and is_instance_valid(rows):
		position = rows.position + Vector2(0.0, rows.size.y + GAP if rows.visible else 0.0)
	if _left <= 0.0:
		visible = false
