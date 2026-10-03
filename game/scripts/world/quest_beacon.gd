class_name QuestBeacon
extends Node3D
## The pillar of light where the next story chapter begins: seen from across
## the sea, a seal turning on the ground at its foot. Stand in it and press
## Interact to begin the chapter.

var chapter_id := ""
var label := ""

var _seal: MeshInstance3D
var _time := 0.0


func _ready() -> void:
	name = "StoryBeacon"
	var gold := Color("f2c96b")
	var pillar := MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = 0.9
	tube.bottom_radius = 1.6
	tube.height = 160.0
	tube.radial_segments = 16
	pillar.mesh = tube
	pillar.material_override = _far_only(Vfx.glow_material(gold, 1.4, 0.22))
	pillar.position.y = 80.0
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pillar)
	var core := MeshInstance3D.new()
	var thin := CylinderMesh.new()
	thin.top_radius = 0.25
	thin.bottom_radius = 0.45
	thin.height = 160.0
	core.mesh = thin
	core.material_override = _far_only(Vfx.glow_material(gold.lightened(0.4), 2.4, 0.6))
	core.position.y = 80.0
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)
	_seal = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 3.0
	disc.bottom_radius = 3.0
	disc.height = 0.04
	_seal.mesh = disc
	_seal.material_override = Vfx.glow_material(gold, 1.2, 0.35)
	_seal.position.y = 0.06
	add_child(_seal)
	var light := OmniLight3D.new()
	light.light_color = gold
	light.light_energy = 2.0
	light.omni_range = 10.0
	light.position.y = 2.0
	add_child(light)


## The pillar is for finding the place from afar: it fades away up close so
## it never fills the camera when you stand in it.
static func _far_only(m: StandardMaterial3D) -> StandardMaterial3D:
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 6.0
	m.distance_fade_max_distance = 22.0
	return m


func _process(delta: float) -> void:
	_time += delta
	_seal.rotation.y += delta * 0.4
	_seal.scale = Vector3.ONE * (1.0 + 0.05 * sin(_time * 2.0))
