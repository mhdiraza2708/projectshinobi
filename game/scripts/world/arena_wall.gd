class_name ArenaWall
extends StaticBody3D
## An invisible ring that keeps a story chapter's fights in its clearing (the
## open world has no walls otherwise). Centred on the origin, where a
## chapter's island is moved before it plays.

var radius := 38.0


func _ready() -> void:
	name = "ArenaWall"
	collision_layer = Combat.LAYER_WORLD
	var segments := 48
	var width := TAU * radius / segments + 0.4
	for s in segments:
		var ang := TAU * s / segments
		var shape := BoxShape3D.new()
		shape.size = Vector3(width, 40.0, 1.0)
		var col := CollisionShape3D.new()
		col.shape = shape
		col.position = Vector3(cos(ang) * radius, 10.0, sin(ang) * radius)
		col.rotation.y = -ang + PI * 0.5
		add_child(col)
