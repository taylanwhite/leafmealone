extends RefCounted

## Authority: data. How each neighborhood looks (docs/GAME.md, "2026-11-01, the
## neighborhood looks"): which house archetypes it builds
## (levels/town/house_archetypes.gd), its palettes and materials, fences, trees,
## ground, street, props, set pieces, and signs. One dictionary per hood id, the
## same ids as net/town/neighborhoods.gd; unknown ids fall back to maple_row.
## Everything here is a pure input to the builders, so a house's look follows
## from its hood, seed, and size on every peer and needs nothing saved.
##
## Keys:
##   archetypes       {stories: [[archetype, weight], ...]} the job house and neighbors
##   neighbor_archetypes  extra archetypes for neighbors only (A-frames, glass cubes)
##   uniformity       0-1: how often a neighbor reuses the block's first archetype and size
##   frontage         meters of street per neighbor parcel
##   walls, roofs     [[Color, surface], ...] palettes (props/surfaces.gd patterns)
##   trims, doors     [Color, ...]
##   accents          [Color, ...] the second material: mobile-home stripes, stone veneer, brick
##   fence_front      [[kind, weight], ...] front-yard fences (none, picket, ...)
##   fence_side       what runs between yards: hedge|privacy|boxwood|long_hedge|chainlink|none
##   job_fence        {kind, fresh, faded, surface} the job yard's paintable fence
##   bed_edge         concrete|brick|tire|stone|timber
##   shed             Color (optional): the job yard's shed, a hiding spot (default weathered wood)
##   trees            {kinds, crowns ([[id, w]]), height (m), per_parcel, street_trees, identical}
##   ground           {color, surface, stripe, flowers (all-year flower floor), dirt (patchiness)}
##   street           {surface, lines (Surfaces.ROAD_LINES id), sidewalk, grass_strip,
##                     curb, lamp, lamp_spacing, poles, speed_bumps}
##   mailbox          mailbox kind (props/prop_catalog.gd, art chunk 3)
##   bins             chance a parcel has its bins out
##   cars             [[kind, weight], ...]; car_colors [Color, ...]
##   yard_props       [[kind, chance, max], ...] front and side yard clutter
##   backyard         {pool, trampoline, swing_set, ...} chances
##   set_pieces       ids for levels/town/set_pieces.gd (art chunk 5)
##   signs            Strings.SIGNS keys the hood shows (ui/strings.gd, art chunk 3)
##   signature        {group: min count} the art test expects under the block
##   decor            seasonal decorating style: classic|homemade|approved|pro|dock
##   chalk            sidewalk chalk drawings
##   back_boundary    wood_fence|cinderblock|stone_wall|hoa_wall|iron

const FALLBACK := "maple_row"

const STYLES: Dictionary = {
	"maple_row": {
		"archetypes": {1: [["bungalow", 4], ["cottage", 3], ["classic", 2]], 2: [["foursquare", 4], ["cottage", 2], ["classic", 2]]},
		"neighbor_archetypes": {},
		"uniformity": 0.1,
		"frontage": 44.0,
		"walls": [
			[Color(0.86, 0.79, 0.62), "siding"], [Color(0.62, 0.72, 0.8), "siding"], [Color(0.82, 0.6, 0.5), "siding"],
			[Color(0.73, 0.8, 0.62), "siding"], [Color(0.58, 0.32, 0.26), "brick"],
		],
		"roofs": [[Color(0.36, 0.25, 0.22), "shingles"], [Color(0.3, 0.32, 0.36), "shingles"], [Color(0.45, 0.27, 0.2), "shingles"], [Color(0.28, 0.3, 0.26), "shingles"]],
		"trims": [Color(0.95, 0.94, 0.9), Color(0.95, 0.94, 0.9), Color(0.22, 0.34, 0.26)],
		"doors": [Color(0.62, 0.16, 0.14), Color(0.18, 0.26, 0.42), Color(0.2, 0.36, 0.26), Color(0.12, 0.12, 0.13)],
		"accents": [Color(0.58, 0.32, 0.26), Color(0.52, 0.3, 0.25)],
		"fence_front": [["picket", 6], ["none", 3]],
		"fence_side": "hedge",
		"job_fence": {"kind": "picket", "fresh": Color(0.97, 0.96, 0.92), "faded": Color(0.72, 0.68, 0.6), "surface": "planks"},
		"bed_edge": "brick",
		"trees": {"kinds": [["broadleaf", 8], ["pine", 1]], "crowns": [["red", 4], ["orange", 4], ["rust", 2], ["turning", 1]], "height": Vector2(9.0, 11.0), "per_parcel": Vector2i(1, 2), "street_trees": true, "identical": false},
		"ground": {"color": Color(0.38, 0.55, 0.24), "surface": "grass", "stripe": 0.0, "flowers": 0.0, "dirt": 0.15},
		"street": {"surface": "road", "lines": "double_yellow", "sidewalk": "concrete", "grass_strip": false, "curb": "concrete", "lamp": "acorn", "lamp_spacing": 24.0, "poles": false, "speed_bumps": false},
		"mailbox": "mailbox_post",
		"bins": 0.4,
		"cars": [["car_sedan", 5], ["car_wagon", 2], ["car_hatch", 2]],
		"car_colors": [Color(0.42, 0.48, 0.44), Color(0.55, 0.5, 0.42), Color(0.36, 0.42, 0.52), Color(0.6, 0.32, 0.28)],
		"yard_props": [["kid_bike", 0.35, 1], ["red_wagon", 0.25, 1], ["birdbath", 0.3, 1], ["bbq_kettle", 0.3, 1], ["porch_swing", 0.5, 1], ["gnome", 0.15, 2]],
		"backyard": {"pool": 0.0, "trampoline": 0.1, "swing_set": 0.3, "garden_bed": 0.4, "clothesline": 0.1},
		"set_pieces": ["neighborhood_watch_sign"],
		"signs": ["maple_entrance", "watch_maple"],
		"signature": {"art_signature:watch_sign": 1, "art_signature:porch_swing": 1},
		"decor": "classic",
		"chalk": true,
		"back_boundary": "wood_fence",
	},
	"dandelion_acres": {
		"archetypes": {1: [["single_wide", 5], ["double_wide", 2]], 2: [["double_wide", 4], ["single_wide", 2]]},
		"neighbor_archetypes": {},
		"uniformity": 0.3,
		"frontage": 22.0,
		"walls": [
			[Color(0.7, 0.85, 0.78), "corrugated"], [Color(0.92, 0.74, 0.76), "corrugated"], [Color(0.95, 0.88, 0.62), "corrugated"],
			[Color(0.68, 0.8, 0.9), "corrugated"], [Color(0.92, 0.9, 0.82), "corrugated"],
		],
		"roofs": [[Color(0.86, 0.86, 0.84), "corrugated"], [Color(0.62, 0.64, 0.66), "corrugated"], [Color(0.6, 0.4, 0.3), "corrugated"]],
		"trims": [Color(0.94, 0.94, 0.9), Color(0.82, 0.8, 0.74)],
		"doors": [Color(0.92, 0.92, 0.88), Color(0.5, 0.36, 0.26), Color(0.3, 0.42, 0.6)],
		"accents": [Color(0.3, 0.52, 0.66), Color(0.72, 0.3, 0.3), Color(0.36, 0.56, 0.4), Color(0.86, 0.6, 0.24)],
		"fence_front": [["none", 6], ["weathered_picket", 2], ["chainlink", 2]],
		"fence_side": "chainlink",
		"job_fence": {"kind": "weathered_picket", "fresh": Color(0.95, 0.93, 0.86), "faded": Color(0.6, 0.56, 0.48), "surface": "planks"},
		"bed_edge": "tire",
		# A rusty tin shed, the door held shut with a bungee.
		"shed": Color(0.58, 0.38, 0.26),
		"trees": {"kinds": [["broadleaf", 5], ["pine", 2]], "crowns": [["yellow", 3], ["turning", 3], ["rust", 2]], "height": Vector2(6.0, 8.5), "per_parcel": Vector2i(0, 1), "street_trees": false, "identical": false},
		"ground": {"color": Color(0.5, 0.56, 0.28), "surface": "grass", "stripe": 0.0, "flowers": 0.6, "dirt": 0.55},
		"street": {"surface": "gravel", "lines": "none", "sidewalk": "none", "grass_strip": false, "curb": "none", "lamp": "none", "lamp_spacing": 30.0, "poles": true, "speed_bumps": false},
		"mailbox": "mailbox_cluster",
		"bins": 0.7,
		"cars": [["car_pickup", 4], ["car_hatch", 3], ["car_on_blocks", 1]],
		"car_colors": [Color(0.62, 0.22, 0.18), Color(0.82, 0.8, 0.74), Color(0.3, 0.36, 0.42), Color(0.5, 0.46, 0.3)],
		"yard_props": [["junk_pile", 0.5, 1], ["flamingo", 0.6, 3], ["kiddie_pool", 0.3, 1], ["clothesline", 0.5, 1], ["lawn_chair_plastic", 0.6, 3], ["satellite_dish", 0.5, 1], ["propane_tank", 0.6, 1], ["tire_stack", 0.3, 1]],
		"backyard": {"pool": 0.0, "trampoline": 0.15, "swing_set": 0.2, "garden_bed": 0.3, "clothesline": 0.4},
		"set_pieces": ["entrance_arch", "park_office", "cluster_mailboxes", "power_poles"],
		"signs": ["dandelion_entrance", "dandelion_speed", "dandelion_office", "dandelion_mail"],
		"signature": {"art_signature:mobile_home": 1, "art_signature:junk_pile": 2, "art_signature:power_pole": 4, "art_signature:entrance_arch": 1},
		"decor": "homemade",
		"chalk": false,
		"back_boundary": "cinderblock",
	},
	"birchwood_commons": {
		"archetypes": {1: [["split_level", 4], ["colonial_new", 2]], 2: [["colonial_new", 5], ["split_level", 2]]},
		"neighbor_archetypes": {},
		"uniformity": 0.4,
		"frontage": 44.0,
		"walls": [
			[Color(0.92, 0.91, 0.87), "siding"], [Color(0.82, 0.84, 0.8), "siding"], [Color(0.76, 0.8, 0.84), "siding"],
			[Color(0.88, 0.84, 0.76), "siding"],
		],
		"roofs": [[Color(0.26, 0.27, 0.29), "shingles"], [Color(0.38, 0.32, 0.28), "shingles"], [Color(0.32, 0.34, 0.36), "shingles"]],
		"trims": [Color(0.97, 0.97, 0.95)],
		"doors": [Color(0.14, 0.14, 0.16), Color(0.5, 0.14, 0.14), Color(0.2, 0.28, 0.4)],
		"accents": [Color(0.62, 0.58, 0.52), Color(0.56, 0.52, 0.48), Color(0.68, 0.62, 0.54)],
		"fence_front": [["none", 1]],
		"fence_side": "privacy",
		"job_fence": {"kind": "privacy", "fresh": Color(0.78, 0.6, 0.42), "faded": Color(0.6, 0.55, 0.48), "surface": "planks"},
		"bed_edge": "timber",
		"trees": {"kinds": [["birch", 6], ["broadleaf", 2]], "crowns": [["yellow", 4], ["orange", 2], ["turning", 2]], "height": Vector2(4.0, 6.5), "per_parcel": Vector2i(1, 2), "street_trees": true, "identical": false},
		"ground": {"color": Color(0.36, 0.58, 0.26), "surface": "grass", "stripe": 0.0, "flowers": 0.0, "dirt": 0.05},
		"street": {"surface": "road", "lines": "none", "sidewalk": "concrete", "grass_strip": true, "curb": "concrete", "lamp": "cobra", "lamp_spacing": 30.0, "poles": false, "speed_bumps": false},
		"mailbox": "mailbox_post",
		"bins": 0.5,
		"cars": [["car_minivan", 4], ["car_suv", 4], ["car_sedan", 1]],
		"car_colors": [Color(0.78, 0.78, 0.8), Color(0.94, 0.94, 0.94), Color(0.12, 0.12, 0.13), Color(0.5, 0.52, 0.56)],
		"yard_props": [["basketball_hoop", 0.5, 1], ["landscape_rocks", 0.5, 2], ["staked_sapling_stakes", 0.6, 2], ["solar_light", 0.4, 6]],
		"backyard": {"pool": 0.55, "trampoline": 0.5, "swing_set": 0.5, "bbq_gas": 0.7, "garden_bed": 0.2},
		"set_pieces": ["monument_sign", "pool_sign"],
		"signs": ["birchwood_entrance", "birchwood_pool", "birchwood_sod"],
		"signature": {"art_signature:pool_inground": 2, "art_signature:trampoline": 1, "art_signature:monument_sign": 1},
		"decor": "classic",
		"chalk": true,
		"back_boundary": "wood_fence",
	},
	"oak_hollow": {
		# The joke is sameness: one model, three Approved Beiges, one brown door
		# (and the block's one rebel teal door, rebel_door below).
		"archetypes": {1: [["hoa_standard", 1]], 2: [["hoa_standard", 1]]},
		"neighbor_archetypes": {},
		"uniformity": 0.95,
		"frontage": 44.0,
		"walls": [[Color(0.86, 0.82, 0.74), "siding"], [Color(0.84, 0.8, 0.72), "siding"], [Color(0.88, 0.85, 0.78), "siding"]],
		"roofs": [[Color(0.42, 0.34, 0.28), "shingles"]],
		"trims": [Color(0.97, 0.96, 0.93)],
		"doors": [Color(0.42, 0.28, 0.18)],
		"rebel_door": Color(0.12, 0.58, 0.58),
		"accents": [Color(0.8, 0.76, 0.68)],
		"fence_front": [["none", 1]],
		"fence_side": "boxwood",
		"job_fence": {"kind": "vinyl", "fresh": Color(0.9, 0.9, 0.88), "faded": Color(0.8, 0.79, 0.72), "surface": "plain"},
		"bed_edge": "stone",
		"trees": {"kinds": [["broadleaf", 1]], "crowns": [["red", 1]], "height": Vector2(7.0, 7.0), "per_parcel": Vector2i(1, 1), "street_trees": true, "identical": true},
		"ground": {"color": Color(0.32, 0.56, 0.24), "surface": "lawn_stripes", "stripe": 0.14, "flowers": 0.0, "dirt": 0.0},
		"street": {"surface": "road", "lines": "white_edges", "sidewalk": "pavers", "grass_strip": true, "curb": "concrete", "lamp": "acorn", "lamp_spacing": 20.0, "poles": false, "speed_bumps": true},
		"mailbox": "mailbox_brick",
		"bins": 0.0,
		"cars": [["car_sedan", 6], ["golf_cart", 1]],
		"car_colors": [Color(0.74, 0.75, 0.77)],
		"yard_props": [["hoa_flag", 0.6, 2], ["urn_planter", 0.4, 2]],
		"backyard": {"pool": 0.3, "trampoline": 0.0, "swing_set": 0.0, "patio_set": 0.7, "garden_bed": 0.2},
		"set_pieces": ["hoa_gatehouse", "hoa_rules_board", "rebel_flamingo"],
		"signs": ["hoa_entrance", "hoa_rules", "hoa_violation", "hoa_gate", "hoa_slow"],
		"signature": {"art_signature:hoa_sign": 1, "art_signature:gatehouse": 1, "art_signature:violation_flag": 3, "art_signature:speed_bump": 2},
		"decor": "approved",
		"chalk": false,
		"back_boundary": "hoa_wall",
	},
	"lakeside": {
		"archetypes": {1: [["lake_cabin", 3], ["lake_house", 1]], 2: [["lake_house", 4], ["lake_cabin", 1]]},
		"neighbor_archetypes": {1: [["a_frame", 2]], 2: [["a_frame", 1]]},
		"uniformity": 0.15,
		"frontage": 46.0,
		"walls": [
			[Color(0.62, 0.44, 0.3), "shakes"], [Color(0.36, 0.42, 0.36), "board_batten"], [Color(0.78, 0.76, 0.7), "board_batten"],
			[Color(0.55, 0.38, 0.28), "shakes"],
		],
		"roofs": [[Color(0.22, 0.38, 0.28), "corrugated"], [Color(0.25, 0.27, 0.28), "corrugated"], [Color(0.55, 0.2, 0.16), "corrugated"]],
		"trims": [Color(0.94, 0.93, 0.88), Color(0.28, 0.24, 0.2)],
		"doors": [Color(0.55, 0.36, 0.22), Color(0.2, 0.36, 0.3), Color(0.62, 0.2, 0.16)],
		"accents": [Color(0.6, 0.58, 0.54), Color(0.52, 0.5, 0.46)],
		"fence_front": [["none", 3], ["split_rail", 2]],
		"fence_side": "long_hedge",
		"shed": Color(0.44, 0.32, 0.24),
		"job_fence": {"kind": "split_rail", "fresh": Color(0.62, 0.44, 0.3), "faded": Color(0.56, 0.52, 0.46), "surface": "planks"},
		"bed_edge": "stone",
		"trees": {"kinds": [["pine", 4], ["willow", 2], ["birch", 2]], "crowns": [["yellow", 3], ["orange", 2], ["red", 1]], "height": Vector2(8.0, 12.0), "per_parcel": Vector2i(1, 3), "street_trees": false, "identical": false},
		"ground": {"color": Color(0.36, 0.52, 0.26), "surface": "grass", "stripe": 0.0, "flowers": 0.0, "dirt": 0.1},
		"street": {"surface": "road", "lines": "double_yellow", "sidewalk": "none", "grass_strip": false, "curb": "none", "lamp": "post_lantern", "lamp_spacing": 36.0, "poles": false, "speed_bumps": false},
		"mailbox": "mailbox_lighthouse",
		"bins": 0.3,
		"cars": [["car_suv_kayak", 4], ["car_suv", 2], ["boat_trailer", 1]],
		"car_colors": [Color(0.24, 0.36, 0.3), Color(0.6, 0.6, 0.62), Color(0.2, 0.24, 0.32)],
		"yard_props": [["adirondack", 0.6, 2], ["kayak_rack", 0.4, 1], ["hammock", 0.3, 1]],
		"backyard": {"pool": 0.15, "hot_tub": 0.3, "fire_pit": 0.6},
		"set_pieces": ["lake", "docks", "lakeside_sign"],
		"signs": ["lakeside_entrance", "lakeside_no_wake"],
		"signature": {"art_signature:lake": 1, "art_signature:dock": 3, "art_signature:boat": 2, "art_signature:long_hedge": 2},
		"decor": "dock",
		"chalk": false,
		"back_boundary": "wood_fence",
	},
	"mansion_hill": {
		"archetypes": {1: [["estate", 1]], 2: [["estate", 1]]},
		"neighbor_archetypes": {1: [["modern_glass", 1]], 2: [["modern_glass", 1]]},
		"uniformity": 0.2,
		# One estate per two normal lots; 60, not 88, to fit the town's slots
		# (gap-specs/critic.md C25: TownMap.SLOT_SPACING).
		"frontage": 60.0,
		"walls": [
			[Color(0.93, 0.88, 0.78), "stucco"], [Color(0.9, 0.84, 0.72), "stucco"], [Color(0.96, 0.94, 0.9), "stucco"],
			[Color(0.75, 0.72, 0.66), "stone"],
		],
		"roofs": [[Color(0.72, 0.38, 0.24), "roof_tiles"], [Color(0.62, 0.3, 0.2), "roof_tiles"], [Color(0.3, 0.32, 0.36), "roof_tiles"]],
		"trims": [Color(0.97, 0.96, 0.92), Color(0.86, 0.82, 0.74)],
		"doors": [Color(0.12, 0.12, 0.13), Color(0.34, 0.2, 0.12), Color(0.16, 0.24, 0.2)],
		"accents": [Color(0.86, 0.82, 0.74), Color(0.78, 0.74, 0.66)],
		"fence_front": [["iron", 1]],
		"fence_side": "hedge",
		# The pool house's little sister.
		"shed": Color(0.9, 0.86, 0.76),
		"job_fence": {"kind": "iron", "fresh": Color(0.08, 0.08, 0.09), "faded": Color(0.48, 0.3, 0.2), "surface": "metal"},
		"bed_edge": "stone",
		"trees": {"kinds": [["cypress", 4], ["broadleaf", 2]], "crowns": [["red", 2], ["orange", 2], ["yellow", 1]], "height": Vector2(8.0, 12.0), "per_parcel": Vector2i(2, 4), "street_trees": true, "identical": false},
		"ground": {"color": Color(0.26, 0.5, 0.24), "surface": "lawn_stripes", "stripe": 0.12, "flowers": 0.0, "dirt": 0.0},
		"street": {"surface": "road", "lines": "none", "sidewalk": "pavers", "grass_strip": true, "curb": "granite", "lamp": "lantern", "lamp_spacing": 28.0, "poles": false, "speed_bumps": false},
		"mailbox": "mailbox_fancy",
		"bins": 0.0,
		"cars": [["car_luxury", 4], ["car_convertible", 3], ["golf_cart", 1]],
		"car_colors": [Color(0.1, 0.1, 0.11), Color(0.94, 0.94, 0.94), Color(0.5, 0.08, 0.1), Color(0.14, 0.22, 0.4)],
		"yard_props": [["topiary_ball", 0.8, 4], ["topiary_spiral", 0.5, 2], ["lion_statue", 0.5, 2], ["urn_planter", 0.6, 4], ["fountain_tiered", 0.5, 1]],
		"backyard": {"pool": 0.8, "tennis_court": 0.2, "putting_green": 0.4, "gazebo": 0.4},
		"set_pieces": ["terrace", "estate_gates", "topiary_rake", "summit_sign"],
		"signs": ["mansion_gate", "mansion_private", "mansion_lawn"],
		"signature": {"art_signature:fountain": 2, "art_signature:estate_gate": 2, "art_signature:topiary_rake": 1, "art_signature:terrace": 1},
		"decor": "pro",
		"chalk": false,
		"back_boundary": "stone_wall",
	},
}


## The look for hood_id, with "id" (the style used) and "fallback" (true when
## hood_id is unknown and maple_row stands in).
static func style(hood_id: String) -> Dictionary:
	var known := STYLES.has(hood_id)
	var picked: Dictionary = (STYLES[hood_id] if known else STYLES[FALLBACK]).duplicate()
	picked["id"] = hood_id if known else FALLBACK
	picked["fallback"] = not known
	return picked


static func ids() -> PackedStringArray:
	return PackedStringArray(STYLES.keys())


## One entry of a weighted list [[value, weight], ...], drawn from rng (one
## randf). An empty list gives null.
static func pick(rng: RandomNumberGenerator, weighted: Array) -> Variant:
	if weighted.is_empty():
		return null
	var total := 0.0
	for entry: Array in weighted:
		total += float(entry[1])
	var roll := rng.randf() * total
	for entry: Array in weighted:
		roll -= float(entry[1])
		if roll < 0.0:
			return entry[0]
	return (weighted[weighted.size() - 1] as Array)[0]


## The archetypes a job house (or any yard house) can be in this hood at this
## many stories.
static func archetypes_for(hood_id: String, stories: int) -> PackedStringArray:
	var found := PackedStringArray()
	for entry: Array in _weighted(style(hood_id)["archetypes"], stories):
		found.append(str(entry[0]))
	return found


## The weighted list a job house draws its archetype from.
static func archetype_weights(hood_id: String, stories: int) -> Array:
	return _weighted(style(hood_id)["archetypes"], stories)


## Neighbors may also be the hood's neighbor-only archetypes (an A-frame, a glass cube).
static func neighbor_archetype_weights(hood_id: String, stories: int) -> Array:
	var look := style(hood_id)
	var weights := _weighted(look["archetypes"], stories).duplicate()
	weights.append_array(_weighted(look["neighbor_archetypes"], stories))
	return weights


static func _weighted(by_stories: Dictionary, stories: int) -> Array:
	var key := clampi(stories, 1, 2)
	if by_stories.has(key):
		return by_stories[key]
	return by_stories.get(1, [])
