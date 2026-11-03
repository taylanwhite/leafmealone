extends Node3D

## Authority: local, cosmetic. A handful of catalog props that change with the
## season (art chunk 8: the country road's hay bales, which turn into snow piles
## in winter and are gone in spring). In group "seasonal": core/seasons.gd calls
## apply_season on every peer the morning a season turns, and it swaps its
## pieces for that season's. Nothing collides, nothing is networked.
##
##   var set := SeasonSet.new()
##   set.pieces = [[autumn pieces], [winter], [spring], [summer]]
##   parent.add_child(set)
##
## Each piece is [kind, at (in this node's space), yaw, scale].

const _PropCatalog = preload("res://props/prop_catalog.gd")

var pieces: Array = [[], [], [], []]
var season: int = -1


func _ready() -> void:
	add_to_group("seasonal")
	apply_season(Seasons.current())


func apply_season(next: int) -> void:
	next = posmod(next, 4)
	if next == season:
		return
	season = next
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	if season >= pieces.size():
		return
	for piece: Array in pieces[season]:
		var view := _PropCatalog.node(str(piece[0]))
		add_child(view)
		view.position = piece[1]
		view.rotation.y = float(piece[2])
		view.scale = Vector3.ONE * float(piece[3])
