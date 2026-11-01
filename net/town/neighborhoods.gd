extends RefCounted

## Authority: data. The town's neighborhoods, in the order they open
## (docs/SPINE.md, "The town"). Each one opens with its rank unlock
## ("hood:<id>" in core/ranks.gd) and a referral from someone you already work
## for. Further up the list: bigger yards, richer clients who expect more, and
## noise that draws the NICE BOYS faster.
##
##   houses     how many homes take work here
##   sizes      chance of a small, regular, or big yard
##   standards  how picky the homeowners are, 0 (anything goes) to 1 (inspector)
##   budget     pay multiplier
##   heat       how much faster noise heats the crew here
##   streets    street names for the addresses
##   look       the neighborhood's dressing (levels/dressing/neighborhood.gd)

const HOODS: Array[Dictionary] = [
	{
		"id": "maple_row", "name": "Maple Row", "houses": 7,
		"sizes": [0.55, 0.4, 0.05], "standards": Vector2(0.15, 0.45), "budget": 1.0, "heat": 1.0,
		"streets": ["Maple Row", "Acorn Court", "Sycamore Lane"],
		"blurb": "Bungalows, old trees, and neighbors who all know each other's business.",
		"look": {"siding": [Color(0.86, 0.8, 0.66), Color(0.7, 0.78, 0.84), Color(0.84, 0.72, 0.62)], "trees": 1.0},
	},
	{
		"id": "dandelion_acres", "name": "Dandelion Acres", "houses": 8,
		"sizes": [0.3, 0.6, 0.1], "standards": Vector2(0.05, 0.3), "budget": 0.85, "heat": 0.9,
		"streets": ["Dandelion Loop", "Thistle Way", "Clover Bend"],
		"blurb": "A mobile-home park with huge shared lawns. Cash only, no questions.",
		"look": {"siding": [Color(0.9, 0.88, 0.8), Color(0.62, 0.74, 0.66), Color(0.86, 0.66, 0.5)], "trees": 0.7},
	},
	{
		"id": "birchwood_commons", "name": "Birchwood Commons", "houses": 8,
		"sizes": [0.15, 0.55, 0.3], "standards": Vector2(0.3, 0.6), "budget": 1.3, "heat": 1.1,
		"streets": ["Birchwood Drive", "Cedar Crossing", "Willow Run"],
		"blurb": "Newer two-stories, first pools, and a lot of opinions about edging.",
		"look": {"siding": [Color(0.92, 0.9, 0.86), Color(0.78, 0.8, 0.76), Color(0.66, 0.7, 0.78)], "trees": 0.9},
	},
	{
		"id": "oak_hollow", "name": "Oak Hollow", "houses": 9,
		"sizes": [0.05, 0.55, 0.4], "standards": Vector2(0.55, 0.8), "budget": 1.6, "heat": 1.25,
		"streets": ["Oak Hollow Circle", "Covenant Court", "Bylaw Bend"],
		"blurb": "The HOA. Everything is a violation, including you.",
		"look": {"siding": [Color(0.9, 0.88, 0.84), Color(0.88, 0.86, 0.82), Color(0.86, 0.84, 0.8)], "trees": 1.1},
	},
	{
		"id": "lakeside", "name": "Lakeside", "houses": 8,
		"sizes": [0.0, 0.4, 0.6], "standards": Vector2(0.5, 0.8), "budget": 1.9, "heat": 1.3,
		"streets": ["Shoreline Drive", "Heron Point", "Dockside Lane"],
		"blurb": "Pools, boathouses, and hedges as long as a ferry.",
		"look": {"siding": [Color(0.94, 0.94, 0.92), Color(0.62, 0.72, 0.8), Color(0.8, 0.74, 0.64)], "trees": 1.2},
	},
	{
		"id": "mansion_hill", "name": "Mansion Hill", "houses": 7,
		"sizes": [0.0, 0.2, 0.8], "standards": Vector2(0.7, 0.95), "budget": 2.5, "heat": 1.5,
		"streets": ["Summit Drive", "Gilded Gate", "Old Money Road"],
		"blurb": "Estates. Celebrity clients. Lawyers on retainer for the gnome incidents.",
		"look": {"siding": [Color(0.95, 0.93, 0.88), Color(0.82, 0.8, 0.76), Color(0.7, 0.66, 0.6)], "trees": 1.3},
	},
]

## Homeowners. Names are mixed on purpose: the town is everybody.
const FIRST_NAMES: Array[String] = [
	"Barb", "Gary", "Linda", "Doug", "Patrice", "Wendell", "Marisol", "Dale", "Agnes",
	"Reggie", "Tammy", "Hal", "Bev", "Kenji", "Priya", "Otis", "Rhonda", "Lou",
	"Gloria", "Earl", "Deb", "Sully", "Imani", "Walt", "Connie", "Ravi", "Phyllis",
	"Mitch", "Yolanda", "Gus", "Noreen", "Teddy", "Ingrid", "Clive", "Rosalind", "Bud",
]
const LAST_NAMES: Array[String] = [
	"Featherstone", "Pemberton", "McAllister", "Okafor", "Nguyen", "Delgado", "Kowalski",
	"Haverford", "Thistlewood", "Brambleby", "Gupta", "Lindqvist", "Moreau", "Abernathy",
	"Fairweather", "Oduya", "Castellanos", "Whitlock", "Ashby", "Hollis", "Van Buren",
	"Pickering", "Tanaka", "Oyelaran", "Brightwater", "Szabo", "Marchetti", "Dunwoody",
]

## Personalities: lines in ui/strings.gd CLIENT_LINES, and a nudge to how they judge and pay.
const PERSONALITIES: Dictionary = {
	"easygoing": {"standards": -0.15, "budget": 0.0, "blurb": "Easy to please. Easy to forget to pay you."},
	"chatty": {"standards": 0.0, "budget": 0.05, "blurb": "Will tell you about their knee. Tips well."},
	"grumpy": {"standards": 0.1, "budget": 0.0, "blurb": "Has never been happy. Might be, for you."},
	"neat_freak": {"standards": 0.2, "budget": 0.1, "blurb": "Counts the leaves. Pays for perfect."},
	"nosy": {"standards": 0.05, "budget": 0.0, "blurb": "Watches from the window. Knows everyone."},
	"penny_pincher": {"standards": 0.0, "budget": -0.15, "blurb": "Has a coupon for you. Expired."},
}


static func count() -> int:
	return HOODS.size()


static func index_of(hood_id: String) -> int:
	for index: int in HOODS.size():
		if str(HOODS[index]["id"]) == hood_id:
			return index
	return -1


static func get_hood(hood_id: String) -> Dictionary:
	var index := index_of(hood_id)
	return HOODS[index] if index >= 0 else HOODS[0]


static func name_of(hood_id: String) -> String:
	return str(get_hood(hood_id)["name"])
