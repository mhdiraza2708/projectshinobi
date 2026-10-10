class_name SiteNode
extends Node3D
## One built place of interest: its props, and the points a game system
## needs (the camp's fire, the shrine's spot to stand at, the ruin's relic).
## Anchors are in this node's space and on the ground.

var site: Dictionary = {}
var anchors: Dictionary = {}
## The lantern props (the scene lights them at dusk).
var lanterns: Array[Node3D] = []

var _fire_light: OmniLight3D
var _marker: SiteMarker
var _time := 0.0


func _ready() -> void:
	if anchors.has("fire"):
		_build_fire(anchors["fire"])
	if anchors.has("interact"):
		_marker = _build_marker(anchors["interact"], Color("8fd8ff"))
	elif anchors.has("relic"):
		_marker = _build_marker(anchors["relic"], Color("ffd27a"))


## Where this site's thing to do is, in world space (the fire, the shrine's
## foot, the relic, the board), or the site's middle.
func spot(anchor: String) -> Vector3:
	return to_global(anchors.get(anchor, Vector3.ZERO))


## Shows or hides the pillar of light (a shrine already attuned to has none).
func set_active(on: bool) -> void:
	if is_instance_valid(_marker):
		_marker.visible = on


func _build_marker(at: Vector3, color: Color) -> SiteMarker:
	var m := SiteMarker.new()
	m.color = color
	m.position = at
	add_child(m)
	return m


func _build_fire(at: Vector3) -> void:
	var flame := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.34
	cone.height = 0.95
	flame.mesh = cone
	flame.material_override = Vfx.glow_material(SiteBuilder.FIRE, 3.0, 0.95)
	flame.position = at + Vector3(0.0, 0.5, 0.0)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flame)
	_fire_light = OmniLight3D.new()
	_fire_light.light_color = SiteBuilder.FIRE
	_fire_light.light_energy = 1.6
	_fire_light.omni_range = 11.0
	_fire_light.position = at + Vector3(0.0, 1.2, 0.0)
	add_child(_fire_light)


func _process(delta: float) -> void:
	_time += delta
	if is_instance_valid(_fire_light):
		_fire_light.light_energy = 1.6 + 0.35 * sin(_time * 11.0) + 0.2 * sin(_time * 17.3)
