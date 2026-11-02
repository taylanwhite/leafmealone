extends RefCounted

## Data and pure math for tool tiers and fuel (docs/GAME.md "Shops", tool tiers;
## gap-specs shops chunk 3). The same on every peer: a prop's tier and fuel are
## replicated (net/components/net_prop.gd), and everything here reads only them
## and core/constants.gd ("# ---- shops": TOOL_TIER_*, MK3_PERKS, GAS_TOOLS,
## FUEL_BURN_PER_SECOND). The host uses it for work, heat, fuel and pull-starts;
## every peer for the engine sound and the prompts. No numbers live here.
##
## Tiers are Catalog's ints: 0 used, 1 stock, 2 Mk II, 3 Mk III (-1, nobody owns
## one, never reaches a prop).


## A prop's tier, clamped to the tier tables (stock for anything without one).
static func tier_of(prop: Object) -> int:
	if prop == null or not "tier" in prop:
		return Catalog.TIER_STOCK
	return clampi(int(prop.get("tier")), Catalog.TIER_USED, Catalog.TIER_MK3)


static func _at(table: Array[float], tier: int) -> float:
	return table[clampi(tier, 0, table.size() - 1)]


## How much faster a tool at this tier works (Constants.TOOL_TIER_SPEED).
static func speed(tier: int) -> float:
	return _at(Constants.TOOL_TIER_SPEED, tier)


## Its share of the noise heat a stock one makes (Constants.TOOL_TIER_NOISE).
static func noise(tier: int) -> float:
	return _at(Constants.TOOL_TIER_NOISE, tier)


## Its share of a stock one's fuel use.
static func fuel_use(tier: int) -> float:
	return _at(Constants.TOOL_TIER_FUEL, tier)


## How much farther it reaches.
static func reach(tier: int) -> float:
	return _at(Constants.TOOL_TIER_REACH, tier)


## Its engine's volume next to a stock one's, in dB.
static func volume_db(tier: int) -> float:
	return _at(Constants.TOOL_TIER_VOLUME_DB, tier)


## Its engine's pitch (Constants.TOOL_TIER_PITCH): used rattly, Mk III purring.
static func pitch(tier: int) -> float:
	return _at(Constants.TOOL_TIER_PITCH, tier)


## The Mk III perk for this tool (Constants.MK3_PERKS), or `otherwise` below Mk III.
static func perk(tool: String, tier: int, otherwise: float = 1.0) -> float:
	if tier < Catalog.TIER_MK3 or not Constants.MK3_PERKS.has(tool):
		return otherwise
	return float(Constants.MK3_PERKS[tool])


## Whether this kind of tool burns gas.
static func is_gas_tool(kind: String) -> bool:
	return Constants.GAS_TOOLS.has(kind)


## Whether a prop can run: anything that doesn't burn gas, or a gas tool with
## some left in the tank.
static func has_fuel(prop: Object) -> bool:
	if prop == null:
		return false
	if not is_gas_tool(str(prop.get("kind"))):
		return true
	return float(prop.get("fuel")) > 0.0


## How much of a tank (out of 100) a running gas tool burns per second.
static func burn_per_second(kind: String, tier: int) -> float:
	return float(Constants.FUEL_BURN_PER_SECOND.get(kind, 0.0)) * fuel_use(tier)


## The chance one pull starts a mower, after `pulls` failed ones. The Mk III
## always catches (its perk is the chance).
static func start_chance(tier: int, pulls: int) -> float:
	if tier >= Catalog.TIER_MK3 and Constants.MK3_PERKS.has("lawn_mower"):
		return float(Constants.MK3_PERKS["lawn_mower"])
	return clampf(Constants.MOWER_START_CHANCE + Constants.MOWER_START_GAIN * float(pulls) + _at(Constants.TOOL_TIER_START_BONUS, tier), 0.0, 1.0)


## How far a hooked-up hose stretches before it snaps loose (m). The Mk III's
## perk is its whole length.
static func hose_length(tier: int) -> float:
	return perk("hose", tier, Constants.HOSE_LENGTH * reach(tier))


## How much of the washer's tank a second of spraying uses (out of 100).
static func washer_use(tier: int) -> float:
	return Constants.WASHER_USE_PER_SECOND / perk("pressure_washer", tier)


## How many seconds of paint a dipped roller holds.
static func roller_seconds(tier: int) -> float:
	return Constants.ROLLER_PAINT_SECONDS * perk("paint_roller", tier)


## How many hedge spots one trimmer pass cuts at once (the Mk III cuts a
## double-wide swath).
static func trimmer_spots(tier: int) -> int:
	return maxi(1, int(round(perk("hedge_trimmer", tier))))


## How much faster you climb this ladder: its tier's speed, and the Mk III's perk.
static func climb_speed(tier: int) -> float:
	return perk("ladder", tier, speed(tier))


## How many cells a blower puff shoves the leaves (the Mk III shoves them farther).
static func blower_cells(tier: int) -> int:
	return maxi(1, int(round(float(Constants.BLOWER_CELLS) * perk("leaf_blower", tier))))


## What a tool at a tier is called on its prompt: "Leaf blower Mk II" (the
## catalog's names, ui/strings.gd SHOP_UI item_<id>).
static func tool_name(tool: String, tier: int) -> String:
	var id := Catalog.tool_item(tool, tier)
	if tier == Catalog.TIER_STOCK or id == "":
		return preload("res://ui/strings.gd").item_name(tool)
	return preload("res://ui/strings.gd").shop_item_name(id)


## How many gallons a gas can prop holds: its `water` is the share of a full
## can (Constants.GAS_CAN_CARRY), out of 100.
static func can_gallons(can: Object) -> float:
	if can == null:
		return 0.0
	return clampf(float(can.get("water")), 0.0, 100.0) / 100.0 * Constants.GAS_CAN_CARRY


## How many gallons are still out on the job among these nodes (the host's
## "job_tools" group): what's left in the gas tools' tanks and in the gas can,
## skipping anything already on its way out. world._return_job_gas puts it back
## in the supply after the job; Shops' save counts it as the crew's meanwhile.
static func gas_out(nodes: Array) -> float:
	var gallons := 0.0
	for node: Variant in nodes:
		if not node is Node or (node as Node).is_queued_for_deletion():
			continue
		var kind := str((node as Node).get("kind"))
		if kind == "gas_can":
			gallons += can_gallons(node as Node)
		elif is_gas_tool(kind):
			gallons += clampf(float((node as Node).get("fuel")), 0.0, 100.0) / 100.0 * Constants.GAS_PER_TANK
	return gallons


## A gas can's name on its prompt: "Gas can (2.5 gal)".
static func can_label(gallons: float) -> String:
	return str(preload("res://ui/strings.gd").SHOP_UI["prop_gas_can"]) % gallons


## The `water` that means this many gallons in a gas can.
static func can_water(gallons: float) -> float:
	return clampf(gallons / maxf(Constants.GAS_CAN_CARRY, 0.001) * 100.0, 0.0, 100.0)
