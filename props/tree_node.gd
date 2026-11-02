extends Node3D

## Authority: local, cosmetic. The root of one tree made by props/trees.gd
## spawn(): it keeps what the tree is (kind, its autumn crown, variant) and, in
## group "seasonal", swaps its near ("Look") and far ("LookFar") meshes when
## core/seasons.gd says the season turned. Metas: "kind", "form" (Trees.FORMS)
## and "crown" (the crown it is wearing). Every peer does this from the day
## number alone; nothing here touches gameplay state.

const _Trees = preload("res://props/trees.gd")

var kind := "broadleaf"
## The crown the tree wears in autumn; seasons map it to what it wears now.
var crown := "orange"
var variant := 0
## The season the meshes were built for.
var season := 0


func _ready() -> void:
	add_to_group("seasonal")
	# Spawned while the look was one season and added to the tree in another.
	if Seasons.current() != season:
		apply_season(Seasons.current())


## Called by Seasons.apply_look through group "seasonal".
func apply_season(next: int) -> void:
	var look := get_node_or_null("Look") as MeshInstance3D
	if look != null:
		look.mesh = _Trees.mesh_for(kind, crown, variant, next)
	var far := get_node_or_null("LookFar") as MeshInstance3D
	if far != null:
		far.mesh = _Trees.mesh_for(kind, crown, variant, next, true)
	show_season(next)


## Records the season the meshes are for, and what the tree is wearing in it.
func show_season(next: int) -> void:
	season = posmod(next, 4)
	var form: Array = _Trees.seasonal_form(kind, crown, season)
	set_meta("kind", kind)
	set_meta("crown", form[1])
	set_meta("form", form[2])
