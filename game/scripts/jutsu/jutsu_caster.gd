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
## Multiplies the power of everything this caster makes (enemy tuning).
var power_scale := 1.0
## The player's clan and eye art shape what they cast (cost, damage, healing,
## homing); everyone else's don't.
var use_perks := false

var _cooldowns: Dictionary = {}
var _clones: Array[EnemyShinobi] = []


func _process(delta: float) -> void:
	for id: StringName in _cooldowns.keys():
		_cooldowns[id] -= delta
		if _cooldowns[id] <= 0.0:
			_cooldowns.erase(id)


func cooldown_left(id: StringName) -> float:
	return _cooldowns.get(id, 0.0)


## Chakra this caster pays for `jutsu`, after the affinity discount.
func cost_of(jutsu: JutsuDefinition, instant := false) -> float:
	var cost := jutsu.chakra_cost
	if affinity != Element.NONE and jutsu.element == affinity:
		cost *= 1.0 - AFFINITY_DISCOUNT
	if use_perks:
		cost *= maxf(0.2, 1.0 + Perks.value(&"cost"))
	# Skipping the seals costs extra chakra.
	return cost * (1.0 + Loadouts.INSTANT_SURCHARGE) if instant else cost


## &"" if `jutsu` can be cast right now, otherwise the reason it can't.
func block_reason(jutsu: JutsuDefinition, instant := false) -> StringName:
	if cooldown_left(jutsu.id) > 0.0:
		return &"cooldown"
	if stats.chakra < cost_of(jutsu, instant):
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


## `instant`: no seals were woven (a quick-cast slot set to Instant), which
## costs a surcharge.
func cast(jutsu: JutsuDefinition, target: Node3D = null, instant := false) -> bool:
	var reason := block_reason(jutsu, instant)
	if reason != &"":
		cast_failed.emit(jutsu, reason)
		return false
	stats.spend_chakra(cost_of(jutsu, instant))
	if jutsu.cooldown > 0.0:
		_cooldowns[jutsu.id] = jutsu.cooldown

	var power := jutsu.power * power_scale * (1.0 + stats.modifier(&"attack_power"))
	if use_perks:
		power *= Perks.damage_multiplier(jutsu.element)
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
			stats.heal(jutsu.power * ((1.0 + Perks.value(&"heal")) if use_perks else 1.0))
			Vfx.heal(_world_parent(), _body().global_position)
		JutsuDefinition.Form.SUMMON:
			_summon(jutsu)
		JutsuDefinition.Form.RUSH:
			_rush(jutsu, power, target)
	var sound := cast_sound(jutsu)
	if sound != &"":
		Sfx.play_at(sound, global_position)
	# A burst of chakra at the hands as the technique leaves them.
	if jutsu.visual != &"kunai" and jutsu.form in [JutsuDefinition.Form.PROJECTILE, JutsuDefinition.Form.AREA]:
		var hands := global_position + aim_direction(target) * 0.5
		Vfx.flash(_world_parent(), hands, Element.color(jutsu.element).lightened(0.4), 1.3, 0.16, &"glow")
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
		JutsuDefinition.Form.SUMMON: return &"smoke"
		JutsuDefinition.Form.RUSH: return &""
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


func _spawn_projectiles(jutsu: JutsuDefinition, power: float, target: Node3D, echo := false) -> void:
	var aim := aim_direction(target)
	if use_perks and not echo and jutsu.visual != &"kunai" and Perks.has(&"twin_weave"):
		get_tree().create_timer(SkillTrees.TWIN_WEAVE_DELAY, false).timeout.connect(func() -> void:
			if is_instance_valid(self) and is_inside_tree():
				_spawn_projectiles(jutsu, power * SkillTrees.TWIN_WEAVE_POWER,
					target if is_instance_valid(target) else null, true))
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
		if echo:
			p.radius *= 0.75
		p.homing_rate = jutsu.homing * ((1.0 + Perks.value(&"homing")) if use_perks else 1.0)
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
		if Combat.apply_hit(victim, power, jutsu.element, _body()) > 0.0 and _body().has_method(&"notify_hit"):
			_body().notify_hit(victim, &"jutsu")
	Vfx.area_blast(_world_parent(), center, jutsu.element, jutsu.radius)
	Sfx.play_at(&"explosion", center, -4.0)


## Gathers the technique in the caster's hand; the body (if it can rush)
## then drives it forward. See JutsuRush.
func _rush(jutsu: JutsuDefinition, power: float, target: Node3D) -> void:
	var rush := JutsuRush.new()
	rush.caster = _body()
	rush.target = target
	rush.element = jutsu.element
	rush.power = power
	rush.speed = jutsu.speed
	rush.distance = jutsu.max_range
	rush.radius = jutsu.radius
	rush.gather_time = jutsu.duration
	_body().add_child(rush)
	if _body().has_method(&"begin_rush"):
		_body().begin_rush(rush)


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


## Clones standing right now (the caster's earlier ones vanish when it casts
## again, so there are never more than a cast's worth).
func clones() -> Array[EnemyShinobi]:
	var alive: Array[EnemyShinobi] = []
	for c in _clones:
		if is_instance_valid(c) and not c.is_defeated():
			alive.append(c)
	_clones = alive
	return _clones


## Doubles of the caster step out around them and fight on their side.
func _summon(jutsu: JutsuDefinition) -> void:
	for old in clones():
		old.leave()
	_clones.clear()
	var owner_body := _body()
	var count := jutsu.count + (int(Perks.value(&"clones")) if use_perks else 0)
	var time := jutsu.duration * ((1.0 + Perks.value(&"clone_time")) if use_perks else 1.0)
	var nature := affinity if affinity != Element.NONE else Element.FIRE
	for i in count:
		var c := EnemyShinobi.new()
		c.rank = &"chunin"
		c.team = &"player"
		c.element = nature
		c.clone_of = owner_body
		c.lifetime = time
		c.health_override = jutsu.health
		c.damage_scale = jutsu.power
		if use_perks and Perks.has(&"shadow_bloom"):
			c.bloom_power = SkillTrees.SHADOW_BLOOM_POWER
		var angle := owner_body.rotation.y + TAU * (i + 0.5) / count
		var pos := owner_body.global_position + Vector3(sin(angle), 0.0, cos(angle)) * 2.4
		pos.y = Combat.ground_height(get_world_3d(), pos, owner_body.global_position.y)
		c.position = pos
		_world_parent().add_child(c)
		_clones.append(c)
	Vfx.shockwave(_world_parent(), owner_body.global_position, Color(0.55, 0.62, 0.85), 2.6, 0.5)


func _aura(jutsu: JutsuDefinition) -> void:
	# One aura at a time: a new buff replaces the old glow.
	var old := _body().get_node_or_null(^"Aura")
	if old:
		old.name = "AuraOld"
		old.queue_free()
	_body().add_child(Vfx.aura(jutsu.element, jutsu.duration))
	Vfx.shockwave(_world_parent(), _body().global_position, Element.color(jutsu.element), 1.8, 0.5)
