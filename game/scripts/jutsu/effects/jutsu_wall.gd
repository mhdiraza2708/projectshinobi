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

	if element == Element.WATER:
		_build_water(size)
	else:
		_build_stone(size)
	# It bursts up out of the ground.
	Vfx.dust(get_parent(), global_position, half_width * 0.8)
	Vfx.debris(get_parent(), global_position + Vector3.UP * 0.2, Element.color(element).darkened(0.3), 12, 6.0)

	Sfx.play_at(&"wall_rise", global_position)
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


## A row of rough stone slabs, uneven at the top.
func _build_stone(size: Vector3) -> void:
	var count := maxi(2, ceili(size.x / 0.9))
	var slab_w := size.x / count
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(global_position)
	var base := Element.color(element).lerp(Color(0.46, 0.43, 0.4), 0.65)
	for i in count:
		var h := HEIGHT * rng.randf_range(0.82, 1.08)
		var box := BoxMesh.new()
		box.size = Vector3(slab_w * rng.randf_range(0.95, 1.12), h, size.z * rng.randf_range(0.85, 1.1))
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.position = Vector3(-size.x * 0.5 + slab_w * (i + 0.5), h * 0.5, rng.randf_range(-0.06, 0.06))
		mi.rotation = Vector3(rng.randf_range(-0.06, 0.06), rng.randf_range(-0.12, 0.12), rng.randf_range(-0.07, 0.07))
		var mat := Toon.flat(base.lightened(rng.randf_range(-0.08, 0.12)), 1.0)
		mat.next_pass = Toon.outline(0.02)
		mi.material_override = mat
		add_child(mi)


## A standing curtain of water pouring down, with spray and mist.
func _build_water(size: Vector3) -> void:
	var box := BoxMesh.new()
	box.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.position.y = HEIGHT * 0.5
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://assets/shaders/water.gdshader")
	mat.set_shader_parameter(&"deep", Color(0.25, 0.55, 0.85))
	mat.set_shader_parameter(&"shallow", Color(0.85, 0.95, 1.0))
	mat.set_shader_parameter(&"falling", 1.0)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var spray := Vfx.particles({"texture": &"glow", "amount": 40, "lifetime": 0.8, "size": [0.08, 0.18],
		"speed": [1.0, 3.0], "direction": Vector3.UP, "spread": 50.0, "gravity": Vector3(0, -9, 0),
		"colors": Vfx.gradient([Color(0.9, 0.97, 1.0), Color(0.5, 0.8, 1.0, 0.0)])})
	spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	spray.emission_box_extents = Vector3(size.x * 0.5, 0.05, size.z * 0.5)
	spray.position.y = HEIGHT
	add_child(spray)
	var mist := Vfx.particles({"texture": &"smoke", "atlas": true, "additive": false, "amount": 10,
		"lifetime": 1.2, "size": [0.6, 1.0], "speed": [0.3, 0.8], "direction": Vector3.UP, "spread": 60.0,
		"colors": Vfx.gradient([Color(0.85, 0.93, 1.0, 0.0), Color(0.85, 0.93, 1.0, 0.4), Color(0.85, 0.93, 1.0, 0.0)], [0, 0.3, 1.0])})
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	mist.emission_box_extents = Vector3(size.x * 0.5, 0.05, size.z * 0.6)
	mist.position.y = 0.2
	add_child(mist)

