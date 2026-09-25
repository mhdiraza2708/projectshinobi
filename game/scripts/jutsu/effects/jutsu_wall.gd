class_name JutsuWall
extends StaticBody3D
## A barrier that rises out of the ground, blocks projectiles and bodies for
## `duration` seconds, then sinks back down.

const HEIGHT := 3.0
const THICKNESS := 0.8
const RISE_TIME := 0.22

var element := Element.EARTH
var half_width := 2.0
var duration := 5.0


func _ready() -> void:
	collision_layer = Combat.LAYER_WALLS
	collision_mask = 0

	var size := Vector3(half_width * 2.0, HEIGHT, THICKNESS)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = HEIGHT * 0.5
	add_child(shape)

	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position.y = HEIGHT * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Element.color(element).darkened(0.25)
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.roughness = 0.9
	if element == Element.WATER:
		mat.albedo_color.a = 0.65
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = Element.color(element)
		mat.emission_energy_multiplier = 0.6
	mi.material_override = mat
	add_child(mi)

	# Rise from below ground, hold, then sink and free.
	var rest_y := position.y
	position.y = rest_y - HEIGHT - 0.2
	var tw := create_tween()
	tw.tween_property(self, "position:y", rest_y, RISE_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(duration)
	tw.tween_property(self, "position:y", rest_y - HEIGHT - 0.2, 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
