class_name TrainingDummy
extends StaticBody3D
## A lock-on-able target with an elemental affinity. Shows floating damage
## numbers with WEAK!/RESIST so players learn the element cycle by doing.

@export_enum("none", "fire", "wind", "lightning", "earth", "water") var affinity := "none"
@export var max_health := 150.0
@export var reset_delay := 2.0

var stats: Stats

var _label: Label3D
var _model: Node3D
var _wobble := 0.0


func _ready() -> void:
	collision_layer = Combat.LAYER_TARGETS
	collision_mask = 0
	add_to_group(&"lockable")

	stats = Stats.new()
	stats.name = "Stats"
	stats.max_health = max_health
	stats.chakra_regen = 0.0
	stats.affinity = Element.from_name(affinity)
	add_child(stats)
	stats.health_changed.connect(func(_c: float, _m: float) -> void: _refresh_label())
	stats.damaged.connect(_on_damaged)
	stats.died.connect(_on_died)

	_model = get_node_or_null("Model")
	if _model:
		Toon.apply(_model)

	var color := Element.color(stats.affinity)
	var ring := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.75
	disc.bottom_radius = 0.75
	disc.height = 0.03
	ring.mesh = disc
	ring.material_override = Vfx.glow_material(color, 1.2, 0.55)
	ring.position.y = 0.02
	add_child(ring)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 2.7
	_label.pixel_size = 0.01
	_label.font_size = 36
	_label.outline_size = 10
	_label.modulate = color.lightened(0.3)
	_label.no_depth_test = true
	add_child(_label)
	_refresh_label()


func take_hit(amount: float, element: int, _source: Node) -> float:
	return stats.take_damage(amount, element)


func _process(delta: float) -> void:
	if _model and _wobble > 0.0:
		_wobble = maxf(0.0, _wobble - delta * 3.0)
		_model.rotation.z = sin(_wobble * 30.0) * _wobble * 0.15


func _refresh_label() -> void:
	var title := "Training Dummy" if stats.affinity == Element.NONE \
		else "%s Dummy" % Element.display_name(stats.affinity)
	_label.text = "%s\n%d / %d" % [title, ceili(stats.health), int(stats.max_health)]


func _on_damaged(amount: float, element: int, multiplier: float) -> void:
	_wobble = 1.0
	var text := str(roundi(amount))
	if multiplier > 1.0:
		Sfx.play_at(&"weak_hit", global_position + Vector3.UP * 1.5)
		text += "  WEAK!"
	elif multiplier < 1.0:
		text += "  RESIST"
	var pop := Label3D.new()
	pop.text = text
	pop.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	pop.no_depth_test = true
	pop.pixel_size = 0.01
	pop.font_size = 56 if multiplier > 1.0 else 44
	pop.outline_size = 14
	pop.modulate = Element.color(element).lightened(0.2)
	add_child(pop)
	pop.position = Vector3(randf_range(-0.4, 0.4), 2.0, 0.0)
	var tw := pop.create_tween().set_parallel(true)
	tw.tween_property(pop, "position:y", 3.1, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(pop, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tw.chain().tween_callback(pop.queue_free)


func _on_died() -> void:
	_label.text = "Broken! Resetting…"
	Sfx.play_at(&"enemy_down", global_position + Vector3.UP)
	await get_tree().create_timer(reset_delay).timeout
	if is_inside_tree():
		stats.restore()
