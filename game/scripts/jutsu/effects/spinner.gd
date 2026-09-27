class_name Spinner
extends Node3D
## Turns steadily round an axis (whirling blades, rings).

var axis := Vector3.UP
var speed := 6.0


func _process(delta: float) -> void:
	rotate_object_local(axis, speed * delta)
