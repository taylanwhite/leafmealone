extends "res://net/components/hide_spot.gd"

## Authority: local look for a hiding spot. A solid box the crew can't see
## through or walk through, drawn as what it is (props/yard_models.gd): planks
## make a shed, metal a wheelie dumpster, foliage a hedge.
## Who is inside is decided by the host in net/components/hide_spot.gd.

const _Strings = preload("res://ui/strings.gd")
const _YardModels = preload("res://props/yard_models.gd")
const MODEL_BY_SURFACE: Dictionary = {"planks": "shed", "metal": "dumpster", "foliage": "hedge"}

@export var size := Vector3(1.6, 2.0, 1.6)
@export var color := Color(0.42, 0.36, 0.3)
@export var label := "Hiding spot"
## What it is made of, from props/surfaces.gd.
@export var surface := "planks"

var _label: Label3D


func _ready() -> void:
	super()
	var body := StaticBody3D.new()
	body.name = "Body"
	body.position.y = size.y * 0.5
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	var view := _YardModels.node(str(MODEL_BY_SURFACE.get(surface, "shed")), color, size)
	view.name = "Look"
	add_child(view)
	_label = Label3D.new()
	_label.position.y = size.y + 0.5
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 30
	_label.outline_size = 8
	add_child(_label)
	occupant_changed.connect(func(_peer_id: int) -> void: _refresh_label())
	_refresh_label()


func _refresh_label() -> void:
	# What E does here is shown by ui/interaction_prompt.gd. The sign only says
	# when someone is already inside; a free spot needs no sign floating over it.
	_label.text = _Strings.UI["hide_taken"]
	_label.visible = occupant != 0
