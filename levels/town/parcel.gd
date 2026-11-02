extends Node3D

## Authority: local, cosmetic. The root of anything the neighborhood builders
## make that changes with the season (levels/town/lot_builder.gd parcels, the
## Lakeside lake from levels/town/set_pieces.gd, a whole block from
## levels/town/block_builder.gd). It joins group "seasonal", so
## core/seasons.gd apply_look calls apply_season(season) on every peer the
## morning a season turns, and it rebuilds its season decor (or swaps its
## water) from the data it was built with. Nothing here is networked: the day
## number every peer already has decides the season.
##
## role:
##   "parcel"  SeasonDressing.decorate(self, decor, style, season, seed, lights)
##             (none for a detail "far" parcel: the far LOD stays bare)
##   "block"   SeasonDressing.block_decor(self, season, decor)
##   "lake"    the water's material (lake or frozen) and the winter fishing shanty
##   ""        nothing (a plain holder)
##
## A parcel or block is decorated exactly once per season: its builder calls
## dress() when everything else is built. A season turn before that (a block
## built over several frames) only moves season, which dress() then uses.

const _SeasonDressing = preload("res://levels/town/season_dressing.gd")
const _HoodStyles = preload("res://levels/town/hood_styles.gd")
const _Water = preload("res://props/water_surface.gd")
const _PropCatalog = preload("res://props/prop_catalog.gd")

## Emitted by a block when its last parcel is built (levels/town/block_builder.gd).
signal built

var role := ""
var hood := "maple_row"
var seed_value := 0
var season := 0
## What the decor is placed from (the parcel's decor dict, or the block's).
var decor: Dictionary = {}
## Parcels: whether string lights may go up (never on the job house: a future
## hang-lights task owns those).
var lights := true
## Parcels: the LotBuilder detail it was built at ("far" gets no season decor).
var detail := "full"
## True once the builder has called dress() (the lake: once its water is built).
var dressed := false


func _ready() -> void:
	add_to_group("seasonal")
	# Built off the tree in one season, added in another: catch up. A parcel
	# still being built catches up in dress() instead.
	if dressed and role != "" and Seasons.current() != season:
		apply_season(Seasons.current())


## The builder's last step: the season decor for season, replacing any.
func dress() -> void:
	dressed = true
	_redecorate()


## Restyle for season (0 autumn, 1 winter, 2 spring, 3 summer). Cosmetic and local.
func apply_season(next: int) -> void:
	if next == season and dressed and (has_node("SeasonDecor") or detail == "far"):
		return
	season = next
	if role == "lake":
		_lake(season)
		dressed = true
		return
	if dressed:
		_redecorate()


func _redecorate() -> void:
	match role:
		"parcel":
			_drop_decor()
			if detail != "far":
				_SeasonDressing.decorate(self, decor, _HoodStyles.style(hood), season, seed_value, lights)
		"block":
			_drop_decor()
			_SeasonDressing.block_decor(self, season, decor)
		"lake":
			_lake(season)


## Removes every season decor holder (by name or group), so none is ever left behind.
func _drop_decor() -> void:
	for child: Node in get_children():
		if child.name == &"SeasonDecor" or child.is_in_group("season_decor"):
			remove_child(child)
			child.queue_free()


## The lake's water freezes in winter, and the fishing shanty comes out.
func _lake(next: int) -> void:
	var water := get_node_or_null("Water") as MeshInstance3D
	if water != null:
		var kind := _Water.lake_kind(next)
		water.material_override = _Water.material(kind)
		water.set_meta("water_kind", kind)
	_drop_decor()
	if next != 1:
		var holder := Node3D.new()
		holder.name = "SeasonDecor"
		add_child(holder)
		return
	var winter := Node3D.new()
	winter.name = "SeasonDecor"
	add_child(winter)
	winter.add_to_group("season_decor")
	winter.add_to_group("art_signature:season_winter")
	var shanty: Vector3 = decor.get("shanty", Vector3(24.0, 0.0, -70.0))
	var placed := _PropCatalog.place(winter, "fishing_shanty", Transform3D(Basis(Vector3.UP, 0.4), shanty), Color.WHITE, {"season": next})
	placed.add_to_group("season_decor")
	placed.add_to_group("art_signature:season_winter")
