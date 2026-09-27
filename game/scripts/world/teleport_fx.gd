class_name TeleportFx
extends Node3D
## The summoning that carries you between islands: a seal glowing on the
## ground, a pillar of light and a sparkle of chakra. `arrive()` fades it
## out from full strength; `depart()` builds it up (await `peaked`, the
## moment to cut away).

signal peaked

const CIRCLE_SHADER := preload("res://assets/shaders/summon_circle.gdshader")
const PILLAR_SHADER := preload("res://assets/shaders/light_pillar.gdshader")

var color := Color(0.55, 0.8, 1.0)
var strength := 0.0:
	set(value):
		strength = value
		for m: ShaderMaterial in _materials:
			m.set_shader_parameter(&"strength", value)
		if _light:
			_light.light_energy = value * 3.0

var _materials: Array[ShaderMaterial] = []
var _light: OmniLight3D
var _sparks: CPUParticles3D


func _ready() -> void:
	var circle := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(5.0, 5.0)
	circle.mesh = plane
	circle.material_override = _material(CIRCLE_SHADER)
	circle.position.y = 0.06
	circle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(circle)
	var pillar := MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = 1.3
	tube.bottom_radius = 1.0
	tube.height = 14.0
	tube.cap_top = false
	tube.cap_bottom = false
	tube.radial_segments = 24
	pillar.mesh = tube
	pillar.material_override = _material(PILLAR_SHADER)
	pillar.position.y = 7.0
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pillar)
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.omni_range = 9.0
	_light.position.y = 1.5
	add_child(_light)
	_sparks = CPUParticles3D.new()
	_sparks.amount = 60
	_sparks.lifetime = 1.2
	_sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_sparks.emission_ring_radius = 1.2
	_sparks.emission_ring_inner_radius = 0.2
	_sparks.emission_ring_height = 0.1
	_sparks.emission_ring_axis = Vector3.UP
	_sparks.direction = Vector3.UP
	_sparks.spread = 12.0
	_sparks.gravity = Vector3.ZERO
	_sparks.initial_velocity_min = 3.0
	_sparks.initial_velocity_max = 7.0
	_sparks.scale_amount_min = 0.5
	_sparks.scale_amount_max = 1.0
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.04
	spark_mesh.height = 0.08
	spark_mesh.radial_segments = 6
	spark_mesh.rings = 3
	spark_mesh.material = Vfx.glow_material(color, 3.0)
	_sparks.mesh = spark_mesh
	_sparks.emitting = false
	_sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sparks)
	strength = strength


func _material(shader: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter(&"color", color)
	m.set_shader_parameter(&"strength", strength)
	_materials.append(m)
	return m


## Appears at full strength and fades away, then frees itself.
func arrive(seconds := 1.4) -> void:
	strength = 1.0
	_sparks.emitting = true
	Sfx.play_at(&"teleport", global_position + Vector3.UP, -2.0)
	var tw := create_tween()
	tw.tween_interval(0.25)
	tw.tween_property(self, "strength", 0.0, seconds).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void: _sparks.emitting = false)
	tw.tween_interval(_sparks.lifetime)
	tw.tween_callback(queue_free)


## Builds up to full strength; emits `peaked` when it's time to cut away.
func depart(seconds := 1.3) -> void:
	strength = 0.0
	_sparks.emitting = true
	Sfx.play_at(&"teleport", global_position + Vector3.UP, -2.0)
	var tw := create_tween()
	tw.tween_property(self, "strength", 1.4, seconds).set_ease(Tween.EASE_IN)
	tw.tween_callback(peaked.emit)
