class_name LeafPalette
extends RefCounted

## Authority: local, cosmetic. Which leaves lie where, and what colour they are:
## pure functions of a cell, a slot and the season, identical on every peer.
##
## - h(x, z, k): an integer avalanche hash. Every per-leaf choice (where in the
##   cell, which way it points, its size, colour, dryness) comes from it, so a
##   uniform carpet has no stripes (the old renderer's linear hash drew
##   corduroy).
## - Looks: what falls from a yard's trees. A look is a crown (Constants.
##   LEAF_PALETTES) and a species (LeafMeshes: maple, oak, oval). A broadleaf
##   drops maples (even variants) or oaks (odd), a birch small ovals, a willow
##   long thin ovals; pines and cypresses drop nothing.
## - cell_looks(): each cell's look, picked among the trees within
##   Constants.LEAF_SOURCE_REACH weighted by distance (a deep rust drift under
##   the red maple, butter ovals under the birch), and the yard's mix past them.
## - flake(): one hero leaf's colours, age and species for a season. Autumn is
##   the showpiece; winter is wet dark brown under snow; spring is last year's
##   grey-brown plus blossom petals under the trees that blossom; summer a few
##   greens with some yellow.
## - litter(): the skin's colours per look for a season (leaves/leaf_shaders.gd).

const MAPLE: int = 0
const OAK: int = 1
const OVAL: int = 2
## The shader takes at most this many looks.
const MAX_LOOKS: int = 16
## Leaves fall where no tree stands over them (a yard without trees): a maple
## and oak mix in the home colours.
const DEFAULT_SOURCES: Array = [
	{"crown": "orange", "kind": "broadleaf", "variant": 0},
	{"crown": "red", "kind": "broadleaf", "variant": 1},
	{"crown": "yellow", "kind": "broadleaf", "variant": 0},
]
## Trees that blossom in spring, and what petals they drop (props/trees.gd SPRING_CROWNS).
const PETALS: Dictionary = {"red": "blossom_pink", "yellow": "blossom_white"}
## Summer: trees that turn warm in autumn wear deep green (props/trees.gd SUMMER_DEEP).
const SUMMER_DEEP: Array[String] = ["red", "rust", "orange"]


## Integer avalanche hash of a cell and a slot: 0 .. 2^31 - 1, the same on every peer.
static func h(x: int, z: int, k: int) -> int:
	var v := ((x & 0xffff) * 0x27d4eb2d) ^ ((z & 0xffff) * 0x165667b1) ^ ((k & 0xffff) * 0x9e3779b1)
	v &= 0xffffffff
	v = ((v ^ (v >> 15)) * 0x2c1b3c6d) & 0xffffffff
	v = ((v ^ (v >> 12)) * 0x297a2d39) & 0xffffffff
	# Every product stays under 2^63, so GDScript's 64-bit ints never overflow.
	v = ((v ^ (v >> 15)) * 0x045d9f3b) & 0xffffffff
	v ^= v >> 13
	return v & 0x7fffffff


## A float in [0, 1) from the hash, one per salt.
static func unit(x: int, z: int, k: int, salt: int) -> float:
	return float(h(x, z, k * 97 + salt * 7919 + 13)) / 2147483648.0


## Where slot k of cell (x, z) lies, relative to the cell's centre: offset
## (Vector2, meters), yaw, two tilts (radians) and length (meters). Higher
## slots sit nearer the centre so a pile's top stays round.
static func slot(x: int, z: int, k: int) -> Dictionary:
	var spread := Constants.LEAF_HERO_SPREAD * (1.0 - 0.45 * float(k) / float(maxi(Constants.LEAF_HERO_MAX, 1)))
	var radius := spread * sqrt(unit(x, z, k, 1))
	var angle := TAU * unit(x, z, k, 2)
	return {
		"offset": Vector2(cos(angle), sin(angle)) * radius,
		"yaw": TAU * unit(x, z, k, 3),
		"tilt_x": (unit(x, z, k, 4) * 2.0 - 1.0) * 0.25,
		"tilt_z": (unit(x, z, k, 5) * 2.0 - 1.0) * 0.25,
		"size": lerpf(Constants.LEAF_SIZE.x, Constants.LEAF_SIZE.y, unit(x, z, k, 6)),
	}


## The cell whose look slot k of cell (x, z) takes: up to
## Constants.LEAF_LOOK_JITTER_CELLS away (the litter shader jitters the same
## distance), so tree colours blend leaf by leaf. Clamped to the grid.
static func look_cell(x: int, z: int, k: int, width: int, depth: int) -> Vector2i:
	var reach := Constants.LEAF_LOOK_JITTER_CELLS
	var jx := clampi(x + int(round((unit(x, z, k, 50) * 2.0 - 1.0) * reach)), 0, width - 1)
	var jz := clampi(z + int(round((unit(x, z, k, 51) * 2.0 - 1.0) * reach)), 0, depth - 1)
	return Vector2i(jx, jz)


## Where a leaf with no hero slot (one rising out of the skin or diving into it)
## lies in cell (x, z), relative to its centre: inside the cell, never past
## Constants.LEAF_SKIN_POINT_SPREAD of its size from the centre on either axis.
static func skin_offset(x: int, z: int, k: int, cell_size: float) -> Vector2:
	var reach := Constants.LEAF_SKIN_POINT_SPREAD * cell_size
	return Vector2(unit(x, z, k, 8) * 2.0 - 1.0, unit(x, z, k, 9) * 2.0 - 1.0) * reach


## The species a tree drops, and how wide its leaf is drawn: [species, width
## scale], or [] for trees that drop nothing.
static func species_of(kind: String, variant: int) -> Array:
	match kind:
		"pine", "cypress":
			return []
		"birch":
			return [OVAL, 1.0]
		"willow":
			return [OVAL, Constants.LEAF_WILLOW_WIDTH]
	return [MAPLE if posmod(variant, 2) == 0 else OAK, 1.0]


## The looks of a yard and each cell's look. sources: [{at: Vector2 (field
## local xz), crown, kind, variant}]; cells are width x depth, cell (0, 0)'s
## centre at first (field local xz), cell_size apart. Returns {looks: [{crown,
## species, width}], cells: PackedByteArray (look index per cell), mix: [look
## indices of the open-lawn mix]}.
static func cell_looks(sources: Array, width: int, depth: int, first: Vector2, cell_size: float) -> Dictionary:
	var looks: Array = []
	var keys: Array = []
	var dropping: Array = []
	for source: Dictionary in sources:
		var species := species_of(str(source.get("kind", "broadleaf")), int(source.get("variant", 0)))
		if species.is_empty():
			continue
		var crown := str(source.get("crown", "orange"))
		if not Constants.LEAF_PALETTES.has(crown):
			crown = "orange"
		var key := "%s|%d|%.2f" % [crown, int(species[0]), float(species[1])]
		var index := keys.find(key)
		if index < 0:
			if looks.size() >= MAX_LOOKS:
				index = 0
			else:
				keys.append(key)
				looks.append({"crown": crown, "species": int(species[0]), "width": float(species[1])})
				index = looks.size() - 1
		dropping.append({"at": source.get("at", Vector2.INF), "look": index})
	if looks.is_empty():
		for source: Dictionary in DEFAULT_SOURCES:
			var species := species_of(str(source["kind"]), int(source["variant"]))
			looks.append({"crown": str(source["crown"]), "species": int(species[0]), "width": float(species[1])})
			dropping.append({"at": Vector2.INF, "look": looks.size() - 1})
	var mix: Array = []
	for drop: Dictionary in dropping:
		mix.append(int(drop["look"]))
	var cells := PackedByteArray()
	cells.resize(width * depth)
	var reach := Constants.LEAF_SOURCE_REACH
	var sigma2 := 2.0 * Constants.LEAF_SOURCE_SPREAD * Constants.LEAF_SOURCE_SPREAD
	for z: int in depth:
		for x: int in width:
			var at := first + Vector2(float(x), float(z)) * cell_size
			var total := 0.0
			var weights: Array[float] = []
			for drop: Dictionary in dropping:
				var where: Vector2 = drop["at"]
				var weight := 0.0
				if where != Vector2.INF:
					var distance := at.distance_to(where)
					if distance <= reach:
						weight = exp(-distance * distance / sigma2)
				weights.append(weight)
				total += weight
			var roll := unit(x, z, 0, 40)
			var pick := int(mix[int(roll * float(mix.size())) % mix.size()])
			# Close to a tree its leaves win; out on the open lawn the yard's mix.
			var open_share := clampf(Constants.LEAF_OPEN_LAWN_SHARE / maxf(total, 0.0001), 0.0, 1.0)
			if total > 0.0 and unit(x, z, 0, 41) >= open_share:
				var aim := unit(x, z, 0, 42) * total
				for index: int in weights.size():
					aim -= weights[index]
					if aim <= 0.0:
						pick = int(dropping[index]["look"])
						break
			cells[x + z * width] = pick
	return {"looks": looks, "cells": cells, "mix": mix}


## One hero leaf of a cell whose look is looks[look] in season (0 autumn, 1
## winter, 2 spring, 3 summer): {centre: Color, rim: Color, age: float,
## species: int, width: float, scale: float (of its length), loose: float}.
## Colours are sRGB; age 0 fresh .. 1 dry brown (the shader browns it).
static func flake(looks: Array, mix: Array, look: int, season: int, x: int, z: int, k: int) -> Dictionary:
	var own: Dictionary = looks[clampi(look, 0, looks.size() - 1)]
	var shown := own
	# Strays: another of the yard's trees' colour, on this tree's leaf shape.
	if unit(x, z, k, 20) < Constants.LEAF_STRAY_SHARE and mix.size() > 1:
		shown = looks[int(mix[int(unit(x, z, k, 21) * float(mix.size())) % mix.size()])]
	var crown := str(shown["crown"])
	var species := int(own["species"])
	var width := float(own["width"])
	var scale := 1.0
	var age := 0.0
	var pair: Array = Constants.LEAF_PALETTES.get(crown, Constants.LEAF_PALETTES["orange"])
	var value := lerpf(Constants.LEAF_VALUE_JITTER.x, Constants.LEAF_VALUE_JITTER.y, unit(x, z, k, 22))
	var dry := unit(x, z, k, 23) < Constants.LEAF_DRY_SHARE
	var which := posmod(season, 4)
	var ages: Vector2 = Constants.LEAF_SEASON_AGES[which]
	match which:
		0:
			age = Constants.LEAF_DRY_AGE if dry else lerpf(ages.x, ages.y, unit(x, z, k, 24))
		1:
			age = lerpf(ages.x, ages.y, unit(x, z, k, 24))
		2:
			pair = Constants.LEAF_PALETTES["last_year"]
			age = Constants.LEAF_SPRING_AGES.y if dry else Constants.LEAF_SPRING_AGES.x
			var petal := str(PETALS.get(str(own["crown"]), ""))
			if petal != "" and unit(x, z, k, 25) < Constants.LEAF_PETAL_SHARE:
				pair = Constants.LEAF_PALETTES[petal]
				species = OVAL
				width = 1.0
				scale = Constants.LEAF_PETAL_SCALE
				age = 0.0
				value = 1.0
		3:
			var green := "deep_green" if SUMMER_DEEP.has(str(own["crown"])) else "green"
			pair = Constants.LEAF_PALETTES["yellow" if unit(x, z, k, 25) < Constants.LEAF_SUMMER_YELLOW_SHARE else green]
			age = lerpf(ages.x, ages.y, unit(x, z, k, 24))
	var centre: Color = pair[0]
	var rim: Color = pair[1]
	var loose := unit(x, z, k, 26) * Constants.LEAF_SETTLED_LOOSE_MAX
	if unit(x, z, k, 27) < Constants.LEAF_LOOSE_SHARE:
		loose = lerpf(Constants.LEAF_LOOSE_RANGE.x, Constants.LEAF_LOOSE_RANGE.y, unit(x, z, k, 26))
	return {
		"centre": Color(centre.r * value, centre.g * value, centre.b * value),
		"rim": Color(rim.r * value, rim.g * value, rim.b * value),
		"age": age,
		"species": species,
		"width": width,
		"scale": scale,
		"loose": loose,
	}


## The skin's colours for each look in season: one entry per look,
## {centre, rim, alt_centre, alt_rim, alt_share, age_lo, age_hi}. alt is the
## odd one out (summer's yellows); strays and dry leaves are the shader's.
static func litter(looks: Array, season: int) -> Array:
	var out: Array = []
	for look: Dictionary in looks:
		var crown := str(look["crown"])
		var pair: Array = Constants.LEAF_PALETTES.get(crown, Constants.LEAF_PALETTES["orange"])
		var alt: Array = pair
		var share := 0.0
		var ages: Vector2 = Constants.LEAF_SEASON_AGES[posmod(season, 4)]
		match posmod(season, 4):
			2:
				pair = Constants.LEAF_PALETTES["last_year"]
				alt = pair
			3:
				pair = Constants.LEAF_PALETTES["deep_green" if SUMMER_DEEP.has(crown) else "green"]
				alt = Constants.LEAF_PALETTES["yellow"]
				share = Constants.LEAF_SUMMER_YELLOW_SHARE
		out.append({"centre": pair[0], "rim": pair[1], "alt_centre": alt[0], "alt_rim": alt[1], "alt_share": share, "age_lo": ages.x, "age_hi": ages.y})
	return out
