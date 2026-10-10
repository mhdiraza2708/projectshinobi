class_name LeapStone
extends Area3D
## A seal stone that throws a shinobi in a great arc to its partner (the foot
## and the summit of Five Winds). Step on it to leap.

const LEAP_TIME := 1.4
const ARC := 14.0
const COOLDOWN := 1.5

## Where it throws you, in its parent's (the archipelago's) space.
var target_local := Vector3.ZERO
var _cool := 0.0
var _ring: MeshInstance3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = Combat.LAYER_PLAYER
	monitoring = true
	var shape := CylinderShape3D.new()
	shape.radius = 2.2
	shape.height = 3.0
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 1.0
	add_child(col)
	# A glowing seal ring on the ground, and a faint column of light.
	_ring = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 2.2
	disc.bottom_radius = 2.2
	disc.height = 0.06
	_ring.mesh = disc
	_ring.material_override = Vfx.glow_material(Color("9fd8ff"), 1.6, 0.55)
	_ring.position.y = 0.05
	add_child(_ring)
	var beam := MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = 0.6
	tube.bottom_radius = 1.4
	tube.height = 9.0
	beam.mesh = tube
	beam.material_override = Vfx.glow_material(Color("9fd8ff"), 0.6, 0.18)
	beam.position.y = 4.5
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_cool = maxf(0.0, _cool - delta)
	if _ring:
		_ring.rotation.y += delta * 0.6


func _on_body_entered(body: Node) -> void:
	if body is Player and _cool <= 0.0:
		leap(body)


## Throws `who` to the partner stone in an arc.
func leap(who: Player) -> void:
	_cool = COOLDOWN
	var from := who.global_position
	var to := (get_parent() as Node3D).to_global(target_local) + Vector3.UP * 0.3
	who.input_enabled = false
	who.velocity = Vector3.ZERO
	Vfx.shockwave(get_parent(), from, Color("9fd8ff"), 3.5, 0.5)
	Sfx.play(&"dash")
	var peak := maxf(from.y, to.y) + ARC
	var tw := who.create_tween()
	tw.tween_method(func(t: float) -> void:
		if not is_instance_valid(who):
			return
		var p := from.lerp(to, t)
		# A parabola through the peak.
		p.y = lerpf(from.y, to.y, t) + (peak - maxf(from.y, to.y)) * 4.0 * t * (1.0 - t) \
			+ (maxf(from.y, to.y) - lerpf(from.y, to.y, t)) * 4.0 * t * (1.0 - t)
		who.global_position = p
		who.velocity = Vector3.ZERO, 0.0, 1.0, LEAP_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	if is_instance_valid(who):
		who.input_enabled = true
		Vfx.shockwave(who.get_parent(), who.global_position, Color("9fd8ff"), 2.5, 0.4)
