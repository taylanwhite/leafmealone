extends Node3D

## Authority: local, cosmetic. The root of one tree made by props/trees.gd
## spawn(): it keeps what the tree is (kind, its autumn crown, variant) and, in
## group "seasonal", swaps its near ("Look") and far ("LookFar") meshes when
## core/seasons.gd says the season turned. Metas: "kind", "form" (Trees.FORMS)
## and "crown" (the crown it is wearing). Every peer does this from the day
## number alone; nothing here touches gameplay state.
##
## Building a tree's meshes takes a few milliseconds, and a season turn inside
## DayClock's day RPC would build every distinct tree at once. So the day before a
## turn, Seasons.apply_look calls prewarm_season and the trees build their next
## meshes into Trees' cache a few per frame (Constants.ART_TREE_PREWARM_MS_PER_FRAME,
## shared by every tree); the turn itself then only swaps cached meshes.

const _Trees = preload("res://props/trees.gd")

var kind := "broadleaf"
## The crown the tree wears in autumn; seasons map it to what it wears now.
var crown := "orange"
var variant := 0
## The season the meshes were built for.
var season := 0
## The season to build ahead, or -1.
var _prewarm := -1

## The frame the shared prewarm budget is for, and what is left of it (usec).
static var _budget_frame := -1
static var _budget_left := 0


func _ready() -> void:
	add_to_group("seasonal")
	set_process(_prewarm >= 0)
	# Spawned while the look was one season and added to the tree in another.
	if Seasons.current() != season:
		apply_season(Seasons.current())


## Called by Seasons.apply_look through group "seasonal".
func apply_season(next: int) -> void:
	var far := get_node_or_null("LookFar") as MeshInstance3D
	var look := get_node_or_null("Look") as MeshInstance3D
	# LookFar is Look's visibility parent. Giving the parent a new mesh walks its
	# dependents, and the renderer rejects ("dep_instance->array_index == -1") one
	# not culled yet this frame (its own mesh just changed, or it was just
	# spawned). So Look lets go of its parent across the swap.
	var parent := NodePath()
	if look != null:
		parent = look.visibility_parent
		look.visibility_parent = NodePath()
	if far != null:
		far.mesh = _Trees.mesh_for(kind, crown, variant, next, true)
	if look != null:
		look.mesh = _Trees.mesh_for(kind, crown, variant, next)
		look.visibility_parent = parent
	show_season(next)


## Called by Seasons.apply_look through group "seasonal" the day before the season
## turns to next: builds that season's meshes over the coming frames.
func prewarm_season(next: int) -> void:
	_prewarm = posmod(next, 4)
	set_process(true)


func _process(_delta: float) -> void:
	if _prewarm < 0:
		set_process(false)
		return
	var frame := Engine.get_process_frames()
	if frame != _budget_frame:
		_budget_frame = frame
		_budget_left = int(Constants.ART_TREE_PREWARM_MS_PER_FRAME * 1000.0)
	if _budget_left <= 0:
		return
	var started := Time.get_ticks_usec()
	_Trees.mesh_for(kind, crown, variant, _prewarm)
	_Trees.mesh_for(kind, crown, variant, _prewarm, true)
	_budget_left -= Time.get_ticks_usec() - started
	_prewarm = -1
	set_process(false)


## Records the season the meshes are for, and what the tree is wearing in it.
func show_season(next: int) -> void:
	season = posmod(next, 4)
	var form: Array = _Trees.seasonal_form(kind, crown, season)
	set_meta("kind", kind)
	set_meta("crown", form[1])
	set_meta("form", form[2])
