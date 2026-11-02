class_name Seasons
extends RefCounted

## The seasons (docs/SPINE.md, "Seasons"): the endless loop. The town keeps
## needing different work as the year turns. Pure data and math from the day
## number, the same on every peer. Autumn is the game's home season: the most
## leaves and the colors the art was made for.

const NAMES: Array[String] = ["Autumn", "Winter", "Spring", "Summer"]
## The same seasons as ids, in the same order: the one list every system keys
## on (Catalog item "seasons", icons' for_season).
const IDS: Array[String] = ["autumn", "winter", "spring", "summer"]

## How much of a yard's leaves come back, by season.
const LEAVES: Array[float] = [1.0, 0.3, 0.45, 0.25]
## Work clients ask for more often, by season (one is added to a job when the crew can do it).
const FAVORED: Array = [
	["clean_gutters", "clear_roof"],
	["clean_gutters", "clear_roof", "power_wash", "wash_windows"],
	["pull_weeds", "mow_lawn", "trim_hedges", "pick_litter"],
	["mow_lawn", "skim_pool", "paint_fence", "wash_windows", "trim_hedges"],
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
## One line when it turns, for the day's summary.
const ARRIVALS: Array[String] = [
	"Autumn is back. Leaves everywhere. You're welcome.",
	"Winter. Fewer leaves, frozen gutters, and everybody pays a little extra.",
	"Spring. Weeds, mowing, and hedges with ambitions.",
	"Summer. Mowing, pools, and fences that need paint.",
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
	return NAMES[posmod(season, 4)]


## True on the first day of a season (not day 1).
static func turns_on(day: int) -> bool:
	return day > 1 and of_day(day) != of_day(day - 1)


## Every peer: tint the foliage for this day's season (props/stylized.gd reads it).
static func apply_look(day: int) -> void:
	RenderingServer.global_shader_parameter_set("season_foliage", FOLIAGE[of_day(day)])
