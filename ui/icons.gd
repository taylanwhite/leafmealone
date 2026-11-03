extends RefCounted

## Authority: local, cosmetic. The one loader for UI icons (docs/DECISIONS.md,
## "UI icons are committed PNGs"): every icon is assets/icons/<id>.png, made by
## tools/studio/icon_studio.gd from the recipe of the same id in
## tools/studio/icon_recipes.gd, and never hand-edited. Use it like _Strings:
##
##   const _Icons = preload("res://ui/icons.gd")
##   box.add_child(_Icons.rect(_Icons.for_task("mow_lawn"), _Icons.SIZE_ROW))
##
## A missing or unknown icon is never an error for the caller: texture() gives
## null (with one warning per id), rect() gives an empty spacer of the same size,
## bbcode() gives "", and rich() falls back to the plain "[E]" text, so a layout
## never jumps and text still reads.
##
## Id naming, so other features get icons by construction (docs/ART.md, "Icons"):
##   tool_<Constants.TOOL_PRICES key>   task_<Constants.TASK_TOOLS key>
##   upgrade_<Campaign upgrade id>      item_<yard model kind>
##   app_<phone app id>                 rank_<0..8>  (tier / Ranks.TIERS_PER_RANK)
##   mood_<Strings.MOOD_NAMES key>      season_<Seasons.IDS entry>
##   hood_<neighborhoods HOODS id>      brand_<name>
##   key_<lowercased key name>          mouse_left / mouse_right / wheel_up ...
## A new tool, task, app, hood, mood, season or prompt key adds its id to IDS and
## a recipe to icon_recipes.RECIPES, then runs the generator with --only=<id>.
##
## String tokens (gap-specs/critic.md C4): {key:<InputMap action>} and
## {icon:<id>} inside Strings.UI values. RichTextLabels call rich(); Labels,
## Label3Ds and logs call plain().

const _Ranks = preload("res://core/ranks.gd")
const _Seasons = preload("res://core/seasons.gd")
const _Strings = preload("res://ui/strings.gd")
const _InputLabels = preload("res://core/input_labels.gd")

const DIR := "res://assets/icons/"
## No icon is bigger than this on either side (icons_test checks it).
const MAX_PX: int = 256

# Shared layout sizes, in pixels of height.
const SIZE_ROW: int = 20
const SIZE_HUD: int = 22
const SIZE_PROMPT_KEY: int = 30
const SIZE_AVATAR: int = 28
const SIZE_DOCK: int = 40
const SIZE_BADGE: int = 64
const SIZE_CARD: int = 84

## Every icon id the game may ask for. icon_recipes.RECIPES has exactly these keys.
const IDS: PackedStringArray = [
	# Tools (256, 3D).
	"tool_leaf_blower", "tool_lawn_mower", "tool_ladder", "tool_hose",
	"tool_pressure_washer", "tool_hedge_trimmer", "tool_paint_roller",
	# Items (256, 3D).
	"item_rake", "item_leaf_bag", "item_wheelbarrow", "item_gnome", "item_trash",
	"item_hydrant", "item_paint_bucket", "item_water_tank", "item_turf_sign",
	"item_chefty", "item_van",
	# Gear (256, 3D): yours to keep, gear_<catalog id> (driving G1).
	"gear_skateboard",
	# Upgrades: the base model with a "+" sticker.
	"upgrade_rake_tier_1", "upgrade_rake_tier_2", "upgrade_wheelbarrow_tier_1",
	# Task badges (256): a disc in the work family's color with a 3D vignette.
	"task_rake_leaves", "task_pick_litter", "task_pull_weeds", "task_mow_lawn",
	"task_clean_gutters", "task_wash_windows", "task_power_wash", "task_trim_hedges",
	"task_paint_fence", "task_clear_roof", "task_skim_pool",
	# Rank badges (256): a shield with a 3D emblem, Rake Rookie to The Lawnfather.
	"rank_0", "rank_1", "rank_2", "rank_3", "rank_4", "rank_5", "rank_6", "rank_7", "rank_8",
	# Stats (128, flat).
	"cash", "star", "star_empty", "xp", "heat", "clock", "day", "night", "cleanup",
	"heart", "heart_empty", "lock", "check", "close", "warning", "bill", "water",
	"bonus", "medical", "split", "unread", "voice", "hidden", "phone", "perk",
	# Phone apps (128, rounded tiles). deliveries is shown as "Orders" (critic C10).
	"app_texts", "app_clients", "app_map", "app_crew", "app_deliveries", "app_closet",
	"app_hires", "app_shop", "app_properties",
	# Moods, seasons, neighborhood pins (128, flat).
	"mood_thrilled", "mood_happy", "mood_fine", "mood_slow", "mood_messy",
	"season_autumn", "season_winter", "season_spring", "season_summer",
	"hood_maple_row", "hood_dandelion_acres", "hood_birchwood_commons",
	"hood_oak_hollow", "hood_lakeside", "hood_mansion_hill",
	# Brands (128, flat).
	"brand_homie_depot", "brand_chefty", "brand_turfmasters",
	"brand_rustys", "brand_lunch_money", "brand_snak_o_matic",
	# Snacks and what they do to you (128, flat; shops chunk 6): the shop cards'
	# snack_<item>, and the HUD's buff_<Constants.BUFFS id> (ui/buff_hud.gd).
	"snack_hot_dog", "snack_turbo_juice", "snack_coffee", "snack_vend_sandwich", "snack_vend_turbo",
	"buff_full", "buff_turbo", "buff_crash", "buff_coffee", "buff_queasy",
	# Workwear and Chefty's paint (256, models; shops chunk 7): hat_<style>, the
	# white "shirt" and "paint_swatch" the caller tints, decal_<x>.
	"hat_hd_cap", "hat_beanie", "hat_bucket", "hat_hard", "hat_cowboy", "hat_chef",
	"hat_crown", "hat_cone", "hat_propeller", "hat_viking", "hat_trucker",
	"shirt", "paint_swatch",
	"decal_stripes", "decal_googly", "decal_flames", "decal_leaves", "decal_rust",

	# Chefty's gear and Marty's Body Shop (128, flat; driving C3).
	"gear_chefty_net", "service_repair",
	# Keycaps (64 tall; 128 wide for the long keys) and mouse glyphs: every key a
	# player can rebind to (critic C5), so a rebound prompt still has its cap.
	"key_a", "key_b", "key_c", "key_d", "key_e", "key_f", "key_g", "key_h", "key_i",
	"key_j", "key_k", "key_l", "key_m", "key_n", "key_o", "key_p", "key_q", "key_r",
	"key_s", "key_t", "key_u", "key_v", "key_w", "key_x", "key_y", "key_z",
	"key_0", "key_1", "key_2", "key_3", "key_4", "key_5", "key_6", "key_7", "key_8", "key_9",
	"key_f1", "key_f2", "key_f3", "key_f4", "key_f5", "key_f6", "key_f7", "key_f8",
	"key_f9", "key_f10", "key_f11", "key_f12",
	"key_tab", "key_esc", "key_space", "key_shift", "key_ctrl", "key_alt", "key_enter",
	"key_backspace", "key_up", "key_down", "key_left", "key_right",
	"mouse_left", "mouse_right", "mouse_middle", "mouse_4", "mouse_5", "wheel_up", "wheel_down",
	# The window and app icon (256).
	"app_icon",
]

## Who a phone text is from, by its message kind -> the avatar id.
const TEXT_AVATARS: Dictionary = {
	"lead": "brand_homie_depot", "intro": "brand_homie_depot",
	"request": "app_clients", "referral": "app_clients", "won_back": "app_clients",
	"poached": "brand_turfmasters", "rival": "brand_turfmasters",
	"hire": "app_hires", "delivery": "app_deliveries", "tow": "item_chefty",
	"rusty": "brand_rustys",
}

## Key labels (core/input_labels.gd event_label) whose keycap id isn't just the
## label lowercased: "Esc" is already key_esc, "Escape" covers an unmapped name.
const KEY_IDS: Dictionary = {
	"Escape": "esc", "Kp Enter": "enter", "BackSpace": "backspace",
}
## Mouse button index -> id (its plain-text label is Strings.UI "key_mouse_<index>").
const MOUSE_IDS: Dictionary = {
	MOUSE_BUTTON_LEFT: "mouse_left", MOUSE_BUTTON_RIGHT: "mouse_right",
	MOUSE_BUTTON_MIDDLE: "mouse_middle", MOUSE_BUTTON_XBUTTON1: "mouse_4",
	MOUSE_BUTTON_XBUTTON2: "mouse_5", MOUSE_BUTTON_WHEEL_UP: "wheel_up",
	MOUSE_BUTTON_WHEEL_DOWN: "wheel_down",
}
## feature:<id> unlocks -> the icon that stands for them.
const FEATURE_ICONS: Dictionary = {
	"hiring": "app_hires", "rival": "brand_turfmasters", "garage": "app_properties",
	"barn": "app_properties", "warehouse": "app_properties", "lawnfather": "rank_8",
	"lunch_money": "brand_lunch_money", "salvage": "brand_rustys",
	"truck_paint": "item_chefty", "deliveries": "app_deliveries",
}

static var _cache: Dictionary = {}
static var _warned: Dictionary = {}
static var _token: RegEx


# ---------------------------------------------------------------- loading

## The icon's texture, or null when there is no such icon (warns once per id).
static func texture(id: String) -> Texture2D:
	# "" is "no icon wanted" (an unbound key, an unmapped unlock), not a mistake.
	if id == "":
		return null
	if _cache.has(id):
		return _cache[id]
	var found: Texture2D = null
	var file := path(id)
	if ResourceLoader.exists(file):
		found = load(file) as Texture2D
	if found == null and not _warned.has(id):
		_warned[id] = true
		push_warning("[Icons] no icon '%s' (%s)" % [id, file])
	_cache[id] = found
	return found


static func has(id: String) -> bool:
	return id != "" and ResourceLoader.exists(path(id))


static func path(id: String) -> String:
	return DIR + id + ".png"


# ---------------------------------------------------------------- ids from game data

## A prop or yard-model kind: a tool when the shop sells it, else an item.
static func for_kind(kind: String) -> String:
	return for_tool(kind) if Constants.TOOL_PRICES.has(kind) else "item_" + kind


static func for_tool(tool_id: String) -> String:
	return "tool_" + tool_id


## A core/catalog.gd item id -> its icon, by the item's kind, in the id families
## of gap-specs/critic.md (contracts, "Icons"):
##   tool, tier, used_tool  tool_<tool> (the tier_used / tier_2 / tier_3 overlays
##                          go on top of it at the call site)
##   upgrade                upgrade_<id>
##   consumable             supply_<supply>  ("gas_can" is supply_gas)
##   snack                  snack_<id>
##   cosmetic hat           hat_<style>      (the item id already is)
##   cosmetic shirt         shirt            (tinted by the caller)
##   truck paint            paint_swatch     (tinted by the caller)
##   truck decal            decal_<x>        (the item id)
##   gear                   gear_<id>        (the skateboard, driving G1)
## Anything else (an id the catalog doesn't know) is "", "no icon", not a guess.
## The supply, snack, hat, shirt, paint and decal art is the icons:catalog chunk's.
static func for_shop_item(item_id: StringName) -> String:
	var id := String(item_id)
	var entry := Catalog.item(id)
	if entry.is_empty():
		return for_tool(id) if Constants.TOOL_PRICES.has(id) else ""
	match str(entry.get("kind", "")):
		"tool", "tier", "used_tool":
			return for_tool(str(entry.get("tool", id)))
		"upgrade":
			return "upgrade_" + id
		"consumable":
			return "supply_" + str(entry.get("supply", id))
		"snack":
			return "snack_" + id
		# Chefty's gear and Marty's Body Shop (driving C3; critic.md icon ids).
		"truck_gear":
			return "gear_" + id
		"service":
			return "service_repair"

		"gear":
			return "gear_" + id
		"cosmetic", "truck_cosmetic":
			match str(entry.get("slot", "")):
				"hat":
					return "hat_" + str(entry.get("style", id.trim_prefix("hat_")))
				"shirt":
					return "shirt"
				"paint":
					return "paint_swatch"
				"decal":
					return id
	return ""


static func for_task(task_id: String) -> String:
	return "task_" + task_id


## A crew tier's rank badge: one per rank, rank_8 for The Lawnfather and past it.
static func for_rank(tier: int) -> String:
	return "rank_%d" % clampi(tier / _Ranks.TIERS_PER_RANK, 0, _Ranks.NAMES.size())


static func for_mood(mood: String) -> String:
	return "mood_" + mood


static func for_app(app: String) -> String:
	return "app_" + app


## A season index (Seasons.of_day): 0 autumn ... 3 summer.
static func for_season(index: int) -> String:
	return "season_" + _Seasons.IDS[posmod(index, _Seasons.IDS.size())]


static func for_hood(hood_id: String) -> String:
	return "hood_" + hood_id


## An unlock id from Ranks.UNLOCKS or EXTRA_UNLOCKS ("shop:ladder", "perk:night_owl").
static func for_unlock(unlock: String) -> String:
	var parts := unlock.split(":", true, 1)
	if parts.size() < 2:
		return ""
	match parts[0]:
		"shop":
			return for_shop_item(StringName(parts[1]))
		"hood":
			return for_hood(parts[1])
		"perk":
			return "perk"
		"feature":
			return str(FEATURE_ICONS.get(parts[1], ""))
	return ""


# ---------------------------------------------------------------- keys

## The keycap or mouse id for the binding a prompt names ("key_e", "mouse_left"),
## or "" when nothing is bound. It reads the same binding as the text does
## (core/input_labels.gd, the one key-name source, critic C4/C5), so a rebound
## key shows its own cap at once. A key's id is its label lowercased ("Esc" ->
## key_esc, "F3" -> key_f3); one without a cap (a numpad key, a letter another
## layout puts there) gives an id has() says no to, and rich() prints its text.
static func key_id(action: StringName) -> String:
	var event := _InputLabels.event_of(action)
	if event is InputEventMouseButton:
		return str(MOUSE_IDS.get((event as InputEventMouseButton).button_index, ""))
	if event is InputEventKey:
		var text := _InputLabels.event_label(event)
		if text == _Strings.UI["key_unbound"]:
			return ""
		return "key_" + str(KEY_IDS.get(text, text.to_lower())).replace(" ", "_")
	return ""


## The icon id for an action's key when that icon exists, else "".
static func for_action(action: StringName) -> String:
	var id := key_id(action)
	return id if has(id) else ""


## What a key reads as in plain text, the way Settings shows it: "E", "Tab",
## "Left click", or the unbound mark. Never the internal action id.
static func key_label(action: StringName) -> String:
	return _InputLabels.label(action)


# ---------------------------------------------------------------- nodes and text

## An icon px tall (its width follows the icon's shape), with meta "icon" = id.
## A missing icon gives an empty Control of the same size so layouts don't jump.
static func rect(id: String, px: float) -> Control:
	var found := texture(id)
	if found == null:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(px, px)
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		spacer.set_meta("icon", id)
		return spacer
	var view := TextureRect.new()
	view.texture = found
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.custom_minimum_size = Vector2(px * _aspect(found), px)
	view.set_meta("icon", id)
	return view


## An icon and a label side by side, centered on each other.
static func row(id: String, label: Control, px: float) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := rect(id, px)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(label)
	return box


## RichTextLabel markup for the icon at px tall, or "" when it is missing.
static func bbcode(id: String, px: float) -> String:
	var found := texture(id)
	if found == null:
		return ""
	return "[img=%dx%d]%s[/img]" % [roundi(px * _aspect(found)), roundi(px), path(id)]


## Text with {key:action} and {icon:id} tokens as RichTextLabel markup: keycaps and
## icons px tall. Everything else is literal, so '[' (in a player's name, say) is
## escaped. A key without a cap falls back to the text Strings.keyed gives it
## ("[E]", "[Left click]"), and a token naming no action stays as written, as it
## does there.
static func rich(text: String, px: float) -> String:
	var out := ""
	var at := 0
	for found: RegExMatch in _tokens().search_all(text):
		out += _escape(text.substr(at, found.get_start() - at))
		var kind := found.get_string(1)
		var value := found.get_string(2)
		if kind == "key" and not InputMap.has_action(StringName(value)):
			out += _escape(found.get_string())
		elif kind == "key":
			var cap := bbcode(for_action(StringName(value)), px)
			out += cap if cap != "" else _escape("[%s]" % key_label(StringName(value)))
		else:
			out += bbcode(value, px)
		at = found.get_end()
	return out + _escape(text.substr(at))


## Text with its tokens as plain text: {key:a} is "[E]", {icon:x} is dropped. For
## Labels, Label3Ds, logs and tests. An alias of Strings.keyed (critic C4), the
## one plain-text key renderer.
static func plain(text: String) -> String:
	return _Strings.keyed(text)


## The same token grammar Strings.keyed reads.
static func _tokens() -> RegEx:
	if _token == null:
		_token = RegEx.create_from_string("\\{(key|icon):([a-z0-9_]+)\\}")
	return _token


static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")


static func _aspect(found: Texture2D) -> float:
	return float(found.get_width()) / maxf(1.0, float(found.get_height()))
