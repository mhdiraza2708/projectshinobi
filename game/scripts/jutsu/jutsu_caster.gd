class_name JutsuCaster
extends Node3D
## Turns a jutsu (or a woven seal sequence) into an effect in the world.
## Sits at the caster's hands; its -Z axis is the default aim direction.

signal cast_succeeded(jutsu: JutsuDefinition)
## `jutsu` is null for a misfire (sequence that matches nothing).
## reason: &"misfire", &"cooldown" or &"chakra".
signal cast_failed(jutsu: JutsuDefinition, reason: StringName)

## Chakra lost when a sequence matches no jutsu.
const MISFIRE_CHAKRA := 4.0
## Angle between projectiles in a multi-shot fan.
const FAN_SPREAD := deg_to_rad(11.0)
## How much cheaper jutsu of the caster's own chakra nature are.
const AFFINITY_DISCOUNT := 0.2

@export var stats: Stats
## The body casting; never hit by its own techniques.
@export var body: Node3D
## The caster's chakra nature (Element.*): jutsu of this nature cost less.
var affinity := Element.NONE

var _cooldowns: Dictionary = {}


func _process(delta: float) -> void:
	for id: StringName in _cooldowns.keys():
		_cooldowns[id] -= delta
		if _cooldowns[id] <= 0.0:
			_cooldowns.erase(id)


func cooldown_left(id: StringName) -> float:
	return _cooldowns.get(id, 0.0)


## Chakra this caster pays for `jutsu`, after the affinity discount.
func cost_of(jutsu: JutsuDefinition) -> float:
	if affinity != Element.NONE and jutsu.element == affinity:
		return jutsu.chakra_cost * (1.0 - AFFINITY_DISCOUNT)
	return jutsu.chakra_cost


## &"" if `jutsu` can be cast right now, otherwise the reason it can't.
func block_reason(jutsu: JutsuDefinition) -> StringName:
	if cooldown_left(jutsu.id) > 0.0:
		return &"cooldown"
	if stats.chakra < cost_of(jutsu):
		return &"chakra"
	return &""


func cast_sequence(sequence: Array, target: Node3D = null) -> JutsuDefinition:
	if sequence.is_empty():
		return null
	var jutsu := JutsuRegistry.find_by_seals(sequence)
	if jutsu == null:
		stats.spend_chakra(minf(MISFIRE_CHAKRA, stats.chakra))
		cast_failed.emit(null, &"misfire")
		return null
	return jutsu if cast(jutsu, target) else null


func cast(jutsu: JutsuDefinition, target: Node3D = null) -> bool:
	var reason := block_reason(jutsu)
	if reason != &"":
		cast_failed.emit(jutsu, reason)
		return false
	stats.spend_chakra(cost_of(jutsu))
	if jutsu.cooldown > 0.0:
		_cooldowns[jutsu.id] = jutsu.cooldown

	var power := jutsu.power * (1.0 + stats.modifier(&"attack_power"))
	match jutsu.form:
		JutsuDefinition.Form.PROJECTILE:
			_spawn_projectiles(jutsu, power, target)
		JutsuDefinition.Form.AREA:
			_blast(jutsu, power)
		JutsuDefinition.Form.WALL:
			_raise_wall(jutsu)
		JutsuDefinition.Form.BUFF:
			stats.add_modifier(StringName(jutsu.buff_stat), jutsu.power, jutsu.duration)
			_aura(jutsu)
		JutsuDefinition.Form.HEAL:
			stats.heal(jutsu.power)
			Vfx.burst(_world_parent(), _body().global_position + Vector3.UP, Color(0.5, 1.0, 0.6), 1.8, 0.6)
	var sound := cast_sound(jutsu)
	if sound != &"":
		Sfx.play_at(sound, global_position)
	cast_succeeded.emit(jutsu)
	return true


## The sound of `jutsu` leaving the caster's hands (&"" if the effect makes
## its own, like a wall rising).
static func cast_sound(jutsu: JutsuDefinition) -> StringName:
	if jutsu.visual == &"kunai":
		return &"kunai_throw"
	match jutsu.form:
		JutsuDefinition.Form.BUFF: return &"buff"
		JutsuDefinition.Form.HEAL: return &"heal"
		JutsuDefinition.Form.WALL: return &""
	return StringName("cast_" + Element.NAMES[jutsu.element])


func aim_direction(target: Node3D) -> Vector3:
	if is_instance_valid(target):
		var to_target := target.global_position + Vector3.UP - global_position
		if to_target.length() > 0.5:
			return to_target.normalized()
	return -global_basis.z.normalized()


func _flat_forward() -> Vector3:
	var f := -_body().global_basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD


func _body() -> Node3D:
	return body if body else self


func _world_parent() -> Node:
	var scene := get_tree().current_scene
	return scene if scene else get_tree().root


func _spawn_projectiles(jutsu: JutsuDefinition, power: float, target: Node3D) -> void:
	var aim := aim_direction(target)
	for i in jutsu.count:
		var offset := (i - (jutsu.count - 1) * 0.5) * FAN_SPREAD
		var p := JutsuProjectile.new()
		p.power = power
		p.element = jutsu.element
		p.speed = jutsu.speed
		p.max_range = jutsu.max_range
		p.radius = jutsu.radius
		p.direction = aim.rotated(Vector3.UP, offset).normalized()
		p.caster = _body()
		p.style = jutsu.visual
		p.homing_rate = jutsu.homing
		# Only the centre shot of a fan homes, so the spread stays readable.
		p.target = target if offset == 0.0 else null
		_world_parent().add_child(p)
		p.global_position = global_position


func _blast(jutsu: JutsuDefinition, power: float) -> void:
	var center := _body().global_position + _flat_forward() * jutsu.max_range
	center.y = Combat.ground_height(get_world_3d(), center, _body().global_position.y) + 0.5
	var exclude: Array[RID] = []
	if _body() is CollisionObject3D:
		exclude.append((_body() as CollisionObject3D).get_rid())
	for victim in Combat.hittables_in_sphere(get_world_3d(), center, jutsu.radius, exclude):
		Combat.apply_hit(victim, power, jutsu.element, _body())
	Vfx.burst(_world_parent(), center, Element.color(jutsu.element), jutsu.radius, 0.45)
	Sfx.play_at(&"explosion", center)


func _raise_wall(jutsu: JutsuDefinition) -> void:
	var forward := _flat_forward()
	var pos := _body().global_position + forward * jutsu.max_range
	pos.y = Combat.ground_height(get_world_3d(), pos, _body().global_position.y)
	var wall := JutsuWall.new()
	wall.element = jutsu.element
	wall.half_width = jutsu.radius
	wall.duration = jutsu.duration
	wall.transform = Transform3D(Basis.looking_at(forward, Vector3.UP), pos)
	_world_parent().add_child(wall)


func _aura(jutsu: JutsuDefinition) -> void:
	var aura := Vfx.sphere(1.1, Vfx.glow_material(Element.color(jutsu.element), 1.5, 0.18))
	aura.position = Vector3.UP * 0.95
	aura.scale = Vector3(0.8, 1.1, 0.8)
	_body().add_child(aura)
	var mat := aura.material_override as StandardMaterial3D
	var tw := aura.create_tween()
	tw.tween_interval(maxf(0.0, jutsu.duration - 0.5))
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.5)
	tw.tween_callback(aura.queue_free)
