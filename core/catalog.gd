class_name Catalog
extends RefCounted

## Everything the shops sell (docs/GAME.md, "Shops"; docs/DECISIONS.md,
## 2026-11-01 "shops are one host node over a data catalog"). Pure data, the
## same on every peer: ids, which shop and tab, and what kind of thing each one
## is. No numbers live here: prices, stock, and effects are in core/constants.gd
## (SHOP_PRICES, TOOL_PRICES x TOOL_TIER_PRICE, SUPPLY_PER_ITEM, BUFFS, ...).
## Display text is ui/strings.gd SHOP_UI ("item_<id>", "item_blurb_<id>").
##
## Item fields:
##   shop, tab   where it's sold (SHOPS)
##   kind        tool | tier | upgrade | used_tool | consumable | snack | cosmetic | truck_cosmetic
##               | truck_gear (the crew's, on Chefty) | service (Marty's Body Shop: bought, not owned)

##               | gear (yours to keep, never a job tool: the skateboard)
##   tool, tier  for tools: which tool, and 0 used / 1 stock / 2 Mk II / 3 Mk III
##   needs       ids; owning any one of them is required first
##   supply      the crew supply a consumable adds to (Constants.SUPPLY_PER_ITEM says how much)
##   buff        the buff a snack gives (Constants.BUFFS); "sandwich" rolls full or queasy
##   slot        cosmetics: hat | shirt | paint | decal
##   style       hats: the CartoonBody hat_style it wears
##   seasons     sold only in these seasons (ids of Seasons.IDS)
##   gate        the rank unlock that puts it on sale; default "shop:<id>" (open from the start
##               unless core/ranks.gd lists it)
##   model       what a shelf shows (props/shop_models.gd, props/yard_models.gd)

## Season ids are core/seasons.gd's Seasons.IDS (Seasons.of_day() indexes it);
## Catalog keeps no list of its own.

## Tool tiers, as ints everywhere (Campaign.tool_tier).
const TIER_NONE: int = -1
const TIER_USED: int = 0
const TIER_STOCK: int = 1
const TIER_MK2: int = 2
const TIER_MK3: int = 3

## Kinds a player owns once bought (they go in the player's unlock list).
const OWNED_KINDS: Array[String] = ["tool", "tier", "upgrade", "used_tool", "cosmetic", "truck_cosmetic", "truck_gear", "gear"]

const SHOPS: Dictionary = {
	"homie_depot": {"keeper": "marty", "tabs": ["tools", "upgrades", "supplies", "workwear", "truck", "gear"]},
	"rustys": {"keeper": "rusty", "tabs": ["sell", "used", "oddities"], "gate": "feature:salvage"},
	"lunch_money": {"keeper": "dot", "tabs": ["menu"], "gate": "feature:lunch_money"},
	"snak_o_matic": {"keeper": "", "tabs": ["snacks"]},
}

const TOOLS: Array[String] = [
	"leaf_blower", "lawn_mower", "ladder", "hose", "hedge_trimmer", "pressure_washer", "paint_roller",
]

const ITEMS: Dictionary = {
	# ---- Homie Depot: tools. Stock tools keep their old ids, so old saves keep them.
	"leaf_blower": {"shop": "homie_depot", "tab": "tools", "kind": "tool", "tool": "leaf_blower", "tier": 1, "model": "leaf_blower"},
	"lawn_mower": {"shop": "homie_depot", "tab": "tools", "kind": "tool", "tool": "lawn_mower", "tier": 1, "model": "lawn_mower"},
	"ladder": {"shop": "homie_depot", "tab": "tools", "kind": "tool", "tool": "ladder", "tier": 1, "model": "ladder"},
	"hose": {"shop": "homie_depot", "tab": "tools", "kind": "tool", "tool": "hose", "tier": 1, "model": "hose"},
	"hedge_trimmer": {"shop": "homie_depot", "tab": "tools", "kind": "tool", "tool": "hedge_trimmer", "tier": 1, "model": "hedge_trimmer"},
	"pressure_washer": {"shop": "homie_depot", "tab": "tools", "kind": "tool", "tool": "pressure_washer", "tier": 1, "model": "pressure_washer"},
	"paint_roller": {"shop": "homie_depot", "tab": "tools", "kind": "tool", "tool": "paint_roller", "tier": 1, "model": "paint_roller"},
	# Mk II: needs the tool (new or used). Mk III: needs any lower tier.
	"leaf_blower_mk2": {"shop": "homie_depot", "tab": "tools", "kind": "tier", "tool": "leaf_blower", "tier": 2, "needs": ["leaf_blower", "leaf_blower_used"], "model": "leaf_blower"},
	"lawn_mower_mk2": {"shop": "homie_depot", "tab": "tools", "kind": "tier", "tool": "lawn_mower", "tier": 2, "needs": ["lawn_mower", "lawn_mower_used"], "model": "lawn_mower"},
	"ladder_mk2": {"shop": "homie_depot", "tab": "tools", "kind": "tier", "tool": "ladder", "tier": 2, "needs": ["ladder", "ladder_used"], "model": "ladder"},
	"hose_mk2": {"shop": "homie_depot", "tab": "tools", "kind": "tier", "tool": "hose", "tier": 2, "needs": ["hose", "hose_used"], "model": "hose"},
	"hedge_trimmer_mk2": {"shop": "homie_depot", "tab": "tools", "kind": "tier", "tool": "hedge_trimmer", "tier": 2, "needs": ["hedge_trimmer", "hedge_trimmer_used"], "model": "hedge_trimmer"},
	"pressure_washer_mk2": {"shop": "homie_depot", "tab": "tools", "kind": "tier", "tool": "pressure_washer", "tier": 2, "needs": ["pressure_washer", "pressure_washer_used"], "model": "pressure_washer"},
	"paint_roller_mk2": {"shop": "homie_depot", "tab": "tools", "kind": "tier", "tool": "paint_roller", "tier": 2, "needs": ["paint_roller", "paint_roller_used"], "model": "paint_roller"},
	"leaf_blower_mk3": {"shop": "homie_depot", "tab": "tools", "kind": "tier", "tool": "leaf_blower", "tier": 3, "needs": ["leaf_blower", "leaf_blower_used", "leaf_blower_mk2"], "model": "leaf_blower"},
	"lawn_mower_mk3": {"shop": "homie_depot", "tab": "tools", "kind": "tier", "tool": "lawn_mower", "tier": 3, "needs": ["lawn_mower", "lawn_mower_used", "lawn_mower_mk2"], "model": "lawn_mower"},
	"ladder_mk3": {"shop": "homie_depot", "tab": "tools", "kind": "tier", "tool": "ladder", "tier": 3, "needs": ["ladder", "ladder_used", "ladder_mk2"], "model": "ladder"},
	"hose_mk3": {"shop": "homie_depot", "tab": "tools", "kind": "tier", "tool": "hose", "tier": 3, "needs": ["hose", "hose_used", "hose_mk2"], "model": "hose"},
	"hedge_trimmer_mk3": {"shop": "homie_depot", "tab": "tools", "kind": "tier", "tool": "hedge_trimmer", "tier": 3, "needs": ["hedge_trimmer", "hedge_trimmer_used", "hedge_trimmer_mk2"], "model": "hedge_trimmer"},
	"pressure_washer_mk3": {"shop": "homie_depot", "tab": "tools", "kind": "tier", "tool": "pressure_washer", "tier": 3, "needs": ["pressure_washer", "pressure_washer_used", "pressure_washer_mk2"], "model": "pressure_washer"},
	"paint_roller_mk3": {"shop": "homie_depot", "tab": "tools", "kind": "tier", "tool": "paint_roller", "tier": 3, "needs": ["paint_roller", "paint_roller_used", "paint_roller_mk2"], "model": "paint_roller"},
	# ---- Homie Depot: upgrades.
	"rake_tier_1": {"shop": "homie_depot", "tab": "upgrades", "kind": "upgrade", "model": "rake"},
	"rake_tier_2": {"shop": "homie_depot", "tab": "upgrades", "kind": "upgrade", "needs": ["rake_tier_1"], "model": "rake"},
	"wheelbarrow_tier_1": {"shop": "homie_depot", "tab": "upgrades", "kind": "upgrade", "model": "wheelbarrow"},
	# ---- Homie Depot: supplies, for the whole crew.
	"lawn_bags": {"shop": "homie_depot", "tab": "supplies", "kind": "consumable", "supply": "lawn_bags", "model": "bag_roll"},
	"big_bags": {"shop": "homie_depot", "tab": "supplies", "kind": "consumable", "supply": "big_bags", "model": "bag_roll_big"},
	"gas_can": {"shop": "homie_depot", "tab": "supplies", "kind": "consumable", "supply": "gas", "model": "gas_can"},
	"fertilizer": {"shop": "homie_depot", "tab": "supplies", "kind": "consumable", "supply": "fertilizer", "seasons": ["spring", "summer"], "model": "fertilizer_bag"},
	"grass_seed": {"shop": "homie_depot", "tab": "supplies", "kind": "consumable", "supply": "grass_seed", "seasons": ["spring"], "model": "grass_seed"},
	"rock_salt": {"shop": "homie_depot", "tab": "supplies", "kind": "consumable", "supply": "rock_salt", "seasons": ["winter"], "model": "rock_salt"},
	# ---- Homie Depot: workwear.
	"hat_hd_cap": {"shop": "homie_depot", "tab": "workwear", "kind": "cosmetic", "slot": "hat", "style": "hd_cap"},
	"hat_beanie": {"shop": "homie_depot", "tab": "workwear", "kind": "cosmetic", "slot": "hat", "style": "beanie"},
	"hat_bucket": {"shop": "homie_depot", "tab": "workwear", "kind": "cosmetic", "slot": "hat", "style": "bucket"},
	"hat_hard": {"shop": "homie_depot", "tab": "workwear", "kind": "cosmetic", "slot": "hat", "style": "hard"},
	"hat_cowboy": {"shop": "homie_depot", "tab": "workwear", "kind": "cosmetic", "slot": "hat", "style": "cowboy"},
	"hat_chef": {"shop": "homie_depot", "tab": "workwear", "kind": "cosmetic", "slot": "hat", "style": "chef"},
	"hat_crown": {"shop": "homie_depot", "tab": "workwear", "kind": "cosmetic", "slot": "hat", "style": "crown"},
	"shirt_0": {"shop": "homie_depot", "tab": "workwear", "kind": "cosmetic", "slot": "shirt", "shirt": 0},
	"shirt_1": {"shop": "homie_depot", "tab": "workwear", "kind": "cosmetic", "slot": "shirt", "shirt": 1},
	"shirt_2": {"shop": "homie_depot", "tab": "workwear", "kind": "cosmetic", "slot": "shirt", "shirt": 2},
	"shirt_3": {"shop": "homie_depot", "tab": "workwear", "kind": "cosmetic", "slot": "shirt", "shirt": 3},
	"shirt_4": {"shop": "homie_depot", "tab": "workwear", "kind": "cosmetic", "slot": "shirt", "shirt": 4},
	"shirt_5": {"shop": "homie_depot", "tab": "workwear", "kind": "cosmetic", "slot": "shirt", "shirt": 5},
	"shirt_6": {"shop": "homie_depot", "tab": "workwear", "kind": "cosmetic", "slot": "shirt", "shirt": 6},
	"shirt_7": {"shop": "homie_depot", "tab": "workwear", "kind": "cosmetic", "slot": "shirt", "shirt": 7},
	"shirt_hivis": {"shop": "homie_depot", "tab": "workwear", "kind": "cosmetic", "slot": "shirt", "shirt": "hivis"},
	# ---- Homie Depot: Chefty's paint and decals (crew-wide: everyone sees the truck).
	"paint_classic": {"shop": "homie_depot", "tab": "truck", "kind": "truck_cosmetic", "slot": "paint", "gate": "feature:truck_paint"},
	"paint_mint": {"shop": "homie_depot", "tab": "truck", "kind": "truck_cosmetic", "slot": "paint", "gate": "feature:truck_paint"},
	"paint_sunset": {"shop": "homie_depot", "tab": "truck", "kind": "truck_cosmetic", "slot": "paint", "gate": "feature:truck_paint"},
	"paint_pink": {"shop": "homie_depot", "tab": "truck", "kind": "truck_cosmetic", "slot": "paint", "gate": "feature:truck_paint"},
	"paint_black": {"shop": "homie_depot", "tab": "truck", "kind": "truck_cosmetic", "slot": "paint", "gate": "feature:truck_paint"},
	"paint_gold": {"shop": "homie_depot", "tab": "truck", "kind": "truck_cosmetic", "slot": "paint"},
	"decal_stripes": {"shop": "homie_depot", "tab": "truck", "kind": "truck_cosmetic", "slot": "decal", "gate": "feature:truck_paint"},
	"decal_googly": {"shop": "homie_depot", "tab": "truck", "kind": "truck_cosmetic", "slot": "decal", "gate": "feature:truck_paint"},
	"decal_flames": {"shop": "homie_depot", "tab": "truck", "kind": "truck_cosmetic", "slot": "decal", "gate": "feature:truck_paint"},
	"decal_leaves": {"shop": "homie_depot", "tab": "truck", "kind": "truck_cosmetic", "slot": "decal", "gate": "feature:truck_paint"},
	# ---- Homie Depot: Chefty's gear (crew-wide, like paint) and Marty's Body Shop
	# (driving chunk C3). A repair is bought one per dent (net/shops/shops.gd).
	"chefty_net": {"shop": "homie_depot", "tab": "truck", "kind": "truck_gear"},
	"chefty_repair": {"shop": "homie_depot", "tab": "truck", "kind": "service"},

	# ---- Homie Depot: gear (driving G1). Personal, bought once, never a job tool.
	"skateboard": {"shop": "homie_depot", "tab": "gear", "kind": "gear", "model": "skateboard"},
	# ---- Rusty's Salvage & Pawn: used tools (on sale once the tool is), and oddities.
	"leaf_blower_used": {"shop": "rustys", "tab": "used", "kind": "used_tool", "tool": "leaf_blower", "tier": 0, "gate": "shop:leaf_blower", "model": "leaf_blower"},
	"lawn_mower_used": {"shop": "rustys", "tab": "used", "kind": "used_tool", "tool": "lawn_mower", "tier": 0, "gate": "shop:lawn_mower", "model": "lawn_mower"},
	"ladder_used": {"shop": "rustys", "tab": "used", "kind": "used_tool", "tool": "ladder", "tier": 0, "gate": "shop:ladder", "model": "ladder"},
	"hose_used": {"shop": "rustys", "tab": "used", "kind": "used_tool", "tool": "hose", "tier": 0, "gate": "shop:hose", "model": "hose"},
	"hedge_trimmer_used": {"shop": "rustys", "tab": "used", "kind": "used_tool", "tool": "hedge_trimmer", "tier": 0, "gate": "shop:hedge_trimmer", "model": "hedge_trimmer"},
	"pressure_washer_used": {"shop": "rustys", "tab": "used", "kind": "used_tool", "tool": "pressure_washer", "tier": 0, "gate": "shop:pressure_washer", "model": "pressure_washer"},
	"paint_roller_used": {"shop": "rustys", "tab": "used", "kind": "used_tool", "tool": "paint_roller", "tier": 0, "gate": "shop:paint_roller", "model": "paint_roller"},
	"hat_cone": {"shop": "rustys", "tab": "oddities", "kind": "cosmetic", "slot": "hat", "style": "cone"},
	"hat_propeller": {"shop": "rustys", "tab": "oddities", "kind": "cosmetic", "slot": "hat", "style": "propeller"},
	"hat_viking": {"shop": "rustys", "tab": "oddities", "kind": "cosmetic", "slot": "hat", "style": "viking"},
	"decal_rust": {"shop": "rustys", "tab": "oddities", "kind": "truck_cosmetic", "slot": "decal", "gate": "feature:truck_paint"},
	# ---- Lunch Money.
	"hot_dog": {"shop": "lunch_money", "tab": "menu", "kind": "snack", "buff": "full"},
	"turbo_juice": {"shop": "lunch_money", "tab": "menu", "kind": "snack", "buff": "turbo"},
	"coffee": {"shop": "lunch_money", "tab": "menu", "kind": "snack", "buff": "coffee"},
	"hat_lunch_money": {"shop": "lunch_money", "tab": "menu", "kind": "cosmetic", "slot": "hat", "style": "trucker"},
	# ---- The Snak-o-Matic (prices x Constants.VENDING_PRICE_SCALE).
	"vend_bags": {"shop": "snak_o_matic", "tab": "snacks", "kind": "consumable", "supply": "lawn_bags", "model": "bag_roll"},
	"vend_sandwich": {"shop": "snak_o_matic", "tab": "snacks", "kind": "snack", "buff": "sandwich"},
	"vend_turbo": {"shop": "snak_o_matic", "tab": "snacks", "kind": "snack", "buff": "turbo"},
}


## An item's data, or {} for an id nobody sells.
static func item(id: String) -> Dictionary:
	return ITEMS.get(id, {}) as Dictionary


static func has_item(id: String) -> bool:
	return ITEMS.has(id)


## The ids a shop's tab lists, in catalog order (the order shelves fill in).
static func items_for(shop: String, tab: String = "") -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in ITEMS:
		var entry: Dictionary = ITEMS[id]
		if str(entry.get("shop", "")) == shop and (tab == "" or str(entry.get("tab", "")) == tab):
			out.append(id)
	return out


## What an item costs, in dollars: tools are the base price times their tier's
## share, everything else is Constants.SHOP_PRICES, and the Snak-o-Matic marks
## it all up. -1 for something nobody sells.
static func price(id: String) -> int:
	var entry := item(id)
	if entry.is_empty():
		return -1
	var base := -1.0
	if entry.has("tool") and entry.has("tier"):
		var tool := str(entry["tool"])
		var tier := int(entry["tier"])
		if not Constants.TOOL_PRICES.has(tool) or tier < 0 or tier >= Constants.TOOL_TIER_PRICE.size():
			return -1
		base = float(Constants.TOOL_PRICES[tool]) * Constants.TOOL_TIER_PRICE[tier]
	elif Constants.SHOP_PRICES.has(id):
		base = float(Constants.SHOP_PRICES[id])
	else:
		return -1
	if str(entry.get("shop", "")) == "snak_o_matic":
		base *= Constants.VENDING_PRICE_SCALE
	return roundi(base)


## The rank unlock that puts an item on sale (Campaign.has_unlock). Items the
## ranks never list are on sale from the start.
static func gate_of(id: String) -> String:
	var entry := item(id)
	if entry.has("gate"):
		return str(entry["gate"])
	return "shop:" + id


## The rank unlock a whole shop opens with, or "" when it's open from the start.
static func shop_gate(shop: String) -> String:
	return str((SHOPS.get(shop, {}) as Dictionary).get("gate", ""))


## The item id for a tool at a tier: "hose_used", "hose", "hose_mk2", "hose_mk3".
static func tool_item(tool: String, tier: int) -> String:
	match tier:
		TIER_USED:
			return tool + "_used"
		TIER_STOCK:
			return tool
		TIER_MK2:
			return tool + "_mk2"
		TIER_MK3:
			return tool + "_mk3"
	return ""


## Whether an item is on the shelf this season (an int from Seasons.of_day, or an id).
## Items without seasons are always in.
static func is_in_season(id: String, season: Variant) -> bool:
	var seasons: Array = item(id).get("seasons", [])
	if seasons.is_empty():
		return true
	var season_id := str(season)
	if typeof(season) == TYPE_INT:
		season_id = Seasons.IDS[posmod(int(season), Seasons.IDS.size())]
	return seasons.has(season_id)


## Whether owning this item puts it in the player's unlock list.
static func is_owned_kind(id: String) -> bool:
	return OWNED_KINDS.has(str(item(id).get("kind", "")))
