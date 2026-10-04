class_name QuestBeacon
extends Node3D
## The pillar of light where the next story chapter begins: a soft beam seen
## from across the sea, light pooled on the ground at its foot and motes
## drifting up it. Stand in it and press Interact to begin the chapter.

const BEAM_SHADER := preload("res://assets/shaders/quest_beam.gdshader")
const GROUND_SHADER := preload("res://assets/shaders/quest_ground.gdshader")
const HEIGHT := 160.0
const GOLD := Color("ffcc6b")
## The light itself, a little deeper than the motes so it keeps its colour
## against a bright sky.
const AMBER := Color("ffb040")

var chapter_id := ""
var label := ""
## Arriving starts the mission only once you've been away from it (so the
## next mission doesn't begin the instant the last one ends).
var armed := true

var _light: OmniLight3D
var _time := 0.0


func _ready() -> void:
	name = "StoryBeacon"
	# A wide soft beam and a thin bright core inside it. Both fade away up
	# close (the shader's near_fade), so standing in the pillar is clear.
	_beam(1.9, 2.3, AMBER, 0.5, 2.3, 0.004)
	_beam(0.4, 0.5, GOLD.lerp(Color.WHITE, 0.5), 0.85, 1.6, 0.0015)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * 9.0
	ground.mesh = plane
	var m := ShaderMaterial.new()
	m.shader = GROUND_SHADER
	m.set_shader_parameter(&"color", AMBER)
	ground.material_override = m
	ground.position.y = 0.08
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)

	# Motes of light rising out of the ring and up the beam.
	var motes := Vfx.particles({"texture": &"glow", "additive": true, "amount": 32, "lifetime": 7.0,
		"size": [0.14, 0.34], "ring": [2.6, Vector3.UP], "speed": [1.4, 2.8], "direction": Vector3.UP,
		"spread": 8.0, "randomness": 0.6, "tangential": [-0.05, 0.05],
		"size_curve": Vfx.curve([Vector2(0, 0.0), Vector2(0.15, 1.0), Vector2(0.8, 0.8), Vector2(1, 0.0)]),
		"colors": Vfx.gradient([Color(GOLD, 0.0), Color(GOLD.lerp(Color.WHITE, 0.4), 0.9), Color(GOLD, 0.0)], [0.0, 0.2, 1.0])})
	motes.name = "Motes"
	add_child(motes)

	_light = OmniLight3D.new()
	_light.light_color = GOLD
	_light.light_energy = 2.0
	_light.omni_range = 10.0
	_light.position.y = 2.0
	add_child(_light)


## One tube of the beam, `radius` wide at the foot.
func _beam(foot: float, top: float, color: Color, strength: float, edge_power: float, widen: float) -> void:
	var tube := CylinderMesh.new()
	tube.bottom_radius = foot
	tube.top_radius = top
	tube.height = HEIGHT
	tube.radial_segments = 32
	tube.rings = 8
	tube.cap_top = false
	tube.cap_bottom = false
	var m := ShaderMaterial.new()
	m.shader = BEAM_SHADER
	m.set_shader_parameter(&"color", color)
	m.set_shader_parameter(&"strength", strength)
	m.set_shader_parameter(&"height", HEIGHT)
	m.set_shader_parameter(&"edge_power", edge_power)
	m.set_shader_parameter(&"widen", widen)
	var beam := MeshInstance3D.new()
	beam.mesh = tube
	beam.material_override = m
	# Its foot a little under the ground, so no seam shows there.
	beam.position.y = HEIGHT * 0.5 - 1.0
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)


func _process(delta: float) -> void:
	_time += delta
	_light.light_energy = 2.0 + 0.3 * sin(_time * 1.7)
