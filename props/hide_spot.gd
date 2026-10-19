extends "res://net/components/hide_spot.gd"

## Authority: local look for a hiding spot. A solid box the crew can't see
## through or walk through, with a label. Gray box until the art pass replaces it.
## Who is inside is decided by the host in net/components/hide_spot.gd.

const _Strings = preload("res://ui/strings.gd")

@export var size := Vector3(1.6, 2.0, 1.6)
@export var color := Color(0.42, 0.36, 0.3)
@export var label := "Hiding spot"

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
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.material_override = material
	body.add_child(view)
	add_child(body)
	_label = Label3D.new()
	_label.position.y = size.y + 0.5
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 56
	_label.outline_size = 10
	add_child(_label)
	occupant_changed.connect(func(_peer_id: int) -> void: _refresh_label())
	_refresh_label()


func _refresh_label() -> void:
	var hint: String = _Strings.UI["hide_taken"] if occupant != 0 else _Strings.UI["hide_hint"]
	_label.text = "%s\n%s" % [label, hint]
