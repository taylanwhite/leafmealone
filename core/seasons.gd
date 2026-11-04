class_name Seasons
extends RefCounted

## The seasons (docs/SPINE.md, "Seasons"): the endless loop. The town keeps
## needing different work as the year turns. Pure data and math from the day
## number, the same on every peer. Autumn is the game's home season: the most
## leaves and the colors the art was made for. Their names and the day summary's
## line when one turns are writing, so they live in ui/strings.gd (SEASON_NAMES,
## SEASON_ARRIVALS), in this file's order.

const _Strings = preload("res://ui/strings.gd")

## The seasons as ids, autumn first: the one list every system keys on (Catalog
## item "seasons", icons' for_season).
const IDS: Array[String] = ["autumn", "winter", "spring", "summer"]

## How much of a yard's leaves come back, by season.
const LEAVES: Array[float] = [1.0, 0.3, 0.45, 0.25]
## Work clients ask for more often, by season (one is added to a job when the crew can do it).
## shops:9: the seasonal sack work (Constants.SEASONAL_TASKS) is asked for only
## here, last in each list: salt in winter, seed and feed in spring, feed in summer.
const FAVORED: Array = [
	["clean_gutters", "clear_roof"],
	["clean_gutters", "clear_roof", "power_wash", "wash_windows", "salt_walk"],
	["pull_weeds", "mow_lawn", "trim_hedges", "pick_litter", "seed_lawn", "fertilize_lawn"],
	["mow_lawn", "skim_pool", "paint_fence", "wash_windows", "trim_hedges", "fertilize_lawn"],
]
## Pay on top, by season: nobody wants to be out in the cold.
const PAY_BONUS: Array[float] = [0.0, 0.15, 0.0, 0.05]
## What tree crowns and grass shift toward (rgb), and how far (a).
const FOLIAGE: Array[Color] = [
	Color(1.0, 1.0, 1.0, 0.0),
	Color(0.86, 0.9, 0.97, 0.88),
	Color(0.5, 0.74, 0.32, 0.7),
	Color(0.34, 0.58, 0.24, 0.8),
]


## Which season a day is in: 0 autumn, 1 winter, 2 spring, 3 summer.
static func of_day(day: int) -> int:
	var length := maxi(1, Constants.SEASON_DAYS)
	return int(float(maxi(day, 1) - 1) / float(length)) % 4


## The year a day is in, from 1.
static func year_of(day: int) -> int:
	var length := maxi(1, Constants.SEASON_DAYS)
	return int(float(maxi(day, 1) - 1) / float(length * 4)) + 1


static func name_of(season: int) -> String:
	return _Strings.SEASON_NAMES[posmod(season, 4)]


## True on the first day of a season (not day 1).
static func turns_on(day: int) -> bool:
	return day > 1 and of_day(day) != of_day(day - 1)


## How much snow settles on upward faces, by season (shader global season_snow:
## props/surfaces.gd everywhere, props/stylized.gd where a material opts in).
const SNOW: Array[float] = [0.0, 0.85, 0.0, 0.0]
## How many flowers dot the lawns, by season (shader global season_bloom, read by
## the grass and lawn_stripes surfaces). A surface can keep a floor of its own
## (Dandelion Acres keeps its dandelions all year).
const BLOOM: Array[float] = [0.0, 0.0, 0.8, 0.15]

## The season the look was last set to on this peer, and whether it was set yet.
static var _current := 0
static var _applied := false


## Every peer: set the look for this day's season. The shader globals tint the
## foliage (props/stylized.gd) and lay snow and flowers (props/surfaces.gd). When
## the season actually changes, or on the first call, every node in group
## "seasonal" gets apply_season(season) to restyle itself, and the day before a
## turn prewarm_season(next), when it has one, to get ready. Cosmetic and local.
static func apply_look(day: int) -> void:
	var season := of_day(day)
	RenderingServer.global_shader_parameter_set("season_foliage", FOLIAGE[season])
	RenderingServer.global_shader_parameter_set("season_snow", SNOW[season])
	RenderingServer.global_shader_parameter_set("season_bloom", BLOOM[season])
	var tree := Engine.get_main_loop() as SceneTree
	# The day before a turn, nodes may build tomorrow's look ahead, spread over
	# frames (props/tree_node.gd), so the turn itself only swaps.
	# prewarm_season is optional for a "seasonal" node.
	if tree != null and turns_on(day + 1):
		for node: Node in tree.get_nodes_in_group("seasonal"):
			if node.has_method("prewarm_season"):
				node.call("prewarm_season", of_day(day + 1))
	if _applied and season == _current:
		return
	_current = season
	_applied = true
	if tree != null:
		tree.call_group("seasonal", "apply_season", season)


## The season the look is showing on this peer (autumn until apply_look runs).
static func current() -> int:
	return _current


## The first day of a season in year one, for the studio and tests.
static func first_day_of(season: int) -> int:
	return 1 + posmod(season, 4) * maxi(1, Constants.SEASON_DAYS)
