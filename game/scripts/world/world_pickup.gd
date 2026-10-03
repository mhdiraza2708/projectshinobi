class_name WorldPickup
extends Node3D
## Something a gather quest wants, lying in the world: a glint that bobs and
## turns, with a thin light above it so you can spot it from a distance.
## Walk into it to pick it up (OpenWorld).

var item := "kunai"
var quest := ""

var _body: Node3D
var _time := 0.0


func _ready() -> void:
	var c := Color(str(Quests.ITEMS.get(item, {}).get("color", "#ffffff")))
	_body = Node3D.new()
	add_child(_body)
	match item:
		"kunai":
			var blade := MeshInstance3D.new()
			var prism := PrismMesh.new()
			prism.size = Vector3(0.12, 0.42, 0.03)
			blade.mesh = prism
			blade.material_override = Vfx.glow_material(c, 1.2, 1.0)
			blade.rotation.z = PI
			_body.add_child(blade)
			var grip := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.05, 0.22, 0.05)
			grip.mesh = box
			grip.material_override = Vfx.glow_material(Color("3a2a22"), 0.4, 1.0)
			grip.position.y = 0.3
			_body.add_child(grip)
		"seal":
			var tag := MeshInstance3D.new()
			var quad := BoxMesh.new()
			quad.size = Vector3(0.16, 0.42, 0.01)
			tag.mesh = quad
			tag.material_override = Vfx.glow_material(c, 1.1, 1.0)
			_body.add_child(tag)
			var mark := MeshInstance3D.new()
			var dot := BoxMesh.new()
			dot.size = Vector3(0.08, 0.08, 0.015)
			mark.mesh = dot
			mark.material_override = Vfx.glow_material(UiKit.CRIMSON, 1.6, 1.0)
			_body.add_child(mark)
		_:
			for i in 3:
				var leaf := MeshInstance3D.new()
				var prism := PrismMesh.new()
				prism.size = Vector3(0.16, 0.3, 0.02)
				leaf.mesh = prism
				leaf.material_override = Vfx.glow_material(c, 1.3, 1.0)
				leaf.rotation = Vector3(0.0, TAU * i / 3.0, 0.35)
				_body.add_child(leaf)
	var beam := MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = 0.04
	tube.bottom_radius = 0.12
	tube.height = 6.0
	beam.mesh = tube
	beam.material_override = Vfx.glow_material(c, 1.2, 0.25)
	beam.position.y = 3.0
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	var light := OmniLight3D.new()
	light.light_color = c
	light.light_energy = 0.8
	light.omni_range = 3.0
	add_child(light)


func _process(delta: float) -> void:
	_time += delta
	_body.position.y = 0.12 * sin(_time * 2.2)
	_body.rotation.y += delta * 1.6


## Picked up: a flash and it's gone.
func collect() -> void:
	var c := Color(str(Quests.ITEMS.get(item, {}).get("color", "#ffffff")))
	Vfx.flash(get_parent(), global_position, c, 1.4, 0.2)
	Vfx.sparks(get_parent(), global_position, c, 10, 4.0)
	Sfx.play(&"ui_select", 2.0)
	queue_free()
