class_name SiteMarker
extends Node3D
## A slim pillar of light over something to do at a place of interest (a
## shrine to attune, a relic to take), seen from a distance and pooled on the
## ground at its foot. Quieter than the story's pillar.

const HEIGHT := 46.0

var color := Color("8fd8ff")

var _light: OmniLight3D
var _time := 0.0


func _ready() -> void:
	name = "Marker"
	var tube := CylinderMesh.new()
	tube.bottom_radius = 0.55
	tube.top_radius = 0.7
	tube.height = HEIGHT
	tube.radial_segments = 24
	tube.rings = 6
	tube.cap_top = false
	tube.cap_bottom = false
	var m := ShaderMaterial.new()
	m.shader = QuestBeacon.BEAM_SHADER
	m.set_shader_parameter(&"color", color)
	m.set_shader_parameter(&"strength", 0.55)
	m.set_shader_parameter(&"height", HEIGHT)
	m.set_shader_parameter(&"edge_power", 1.8)
	m.set_shader_parameter(&"widen", 0.002)
	var beam := MeshInstance3D.new()
	beam.mesh = tube
	beam.material_override = m
	beam.position.y = HEIGHT * 0.5 - 0.5
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * 4.5
	ground.mesh = plane
	var g := ShaderMaterial.new()
	g.shader = QuestBeacon.GROUND_SHADER
	g.set_shader_parameter(&"color", color)
	ground.material_override = g
	ground.position.y = 0.08
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.light_energy = 1.4
	_light.omni_range = 7.0
	_light.position.y = 1.6
	add_child(_light)


func _process(delta: float) -> void:
	_time += delta
	_light.light_energy = 1.4 + 0.25 * sin(_time * 1.9)
