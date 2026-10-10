class_name BossSpecials
extends Node
## A boss's signature attacks, running beside its ordinary fighting. Each is
## shown before it lands (a mark on the ground, a gathering ring) and hurts
## only if you are still where it falls, so they are about moving, not about
## health. Data lives on the boss beat or bounty:
##   {"kind": "quake" | "ring" | "chain", "every": seconds between uses,
##    "below": health share under which it starts (1 = from the start),
##    "count", "radius", "damage", "delay" (seconds of warning)}
##
## quake  - marks fall round you and where you stand; leave them.
## ring   - a shockwave runs out from the boss along the ground; jump or
##          dash through it.
## chain  - the boss blinks to strike points round you one after another.
## Only one special runs at a time.

const KINDS: Array[String] = ["quake", "ring", "chain"]
## Defaults for what a spec leaves out.
const DEFAULTS := {
	"quake": {"every": 9.0, "below": 1.0, "count": 4, "radius": 3.6, "damage": 16.0, "delay": 1.15},
	"ring": {"every": 11.0, "below": 1.0, "count": 1, "radius": 24.0, "damage": 18.0, "delay": 0.9},
	"chain": {"every": 12.0, "below": 1.0, "count": 3, "radius": 3.2, "damage": 16.0, "delay": 0.7},
}
## How fast a ring runs out (m/s) and how thick it is.
const RING_SPEED := 13.0
const RING_THICKNESS := 1.7
## The ring clears you if your feet are this far above it.
const RING_CLEARANCE := 1.2

var boss: EnemyShinobi
var specs: Array = []

var _left: Array[float] = []
var _busy := false


## The spec with its defaults filled in.
static func full(spec: Dictionary) -> Dictionary:
	var out: Dictionary = (DEFAULTS.get(str(spec.get("kind", "")), DEFAULTS["quake"]) as Dictionary).duplicate()
	out.merge(spec, true)
	return out


static func errors_in(spec: Variant) -> Array[String]:
	var out: Array[String] = []
	if not spec is Dictionary:
		out.append("a special must be an object")
		return out
	if not KINDS.has(str((spec as Dictionary).get("kind", ""))):
		out.append("unknown special kind '%s'" % (spec as Dictionary).get("kind", ""))
	return out


func _ready() -> void:
	name = "Specials"
	for i in specs.size():
		specs[i] = full(specs[i])
		_left.append(float(specs[i]["every"]) * randf_range(0.5, 0.9))


func _process(delta: float) -> void:
	if not is_instance_valid(boss) or boss.stats == null or boss.stats.is_dead() or _busy:
		return
	if boss.state == EnemyShinobi.State.SPAWNING or boss.state == EnemyShinobi.State.DEFEATED:
		return
	if not is_instance_valid(boss.target) or boss.get_parent() == null:
		return
	var share := boss.stats.health / maxf(boss.stats.max_health, 1.0)
	for i in specs.size():
		if share > float(specs[i]["below"]):
			continue
		_left[i] -= delta
		if _left[i] <= 0.0:
			_left[i] = float(specs[i]["every"]) * randf_range(0.85, 1.15)
			_run(specs[i])
			return


## Runs a special now (the schedule calls it; tests do too).
func _run(spec: Dictionary) -> void:
	_busy = true
	match str(spec["kind"]):
		"quake":
			await _quake(spec)
		"ring":
			await _ring(spec)
		"chain":
			await _chain(spec)
	_busy = false


func is_busy() -> bool:
	return _busy


# --- The attacks ------------------------------------------------------------------------

func _quake(spec: Dictionary) -> void:
	var player := boss.target as Node3D
	var radius := float(spec["radius"])
	var delay := float(spec["delay"])
	var centres: Array[Vector3] = [_on_ground(player.global_position)]
	for i in int(spec["count"]) - 1:
		var a := randf() * TAU
		centres.append(_on_ground(player.global_position + Vector3(cos(a), 0.0, sin(a)) * randf_range(4.0, 9.0)))
	var colour := Element.color(boss.element)
	for c in centres:
		Vfx.ground_mark(boss.get_parent(), c, colour.lerp(Color(1, 0.2, 0.15), 0.5), radius, delay)
	await get_tree().create_timer(delay, false).timeout
	if not is_instance_valid(boss) or boss.stats.is_dead():
		return
	for c in centres:
		Vfx.area_blast(boss.get_parent(), c, boss.element, radius)
		_hurt_in_circle(c, radius, float(spec["damage"]))


func _ring(spec: Dictionary) -> void:
	var centre := _on_ground(boss.global_position)
	var delay := float(spec["delay"])
	var colour := Element.color(boss.element)
	Vfx.ground_mark(boss.get_parent(), centre, colour.lerp(Color(1, 0.2, 0.15), 0.5), 3.0, delay)
	await get_tree().create_timer(delay, false).timeout
	if not is_instance_valid(boss) or boss.stats.is_dead():
		return
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.92
	torus.outer_radius = 1.0
	torus.rings = 40
	torus.ring_segments = 6
	ring.mesh = torus
	ring.material_override = Vfx.glow_material(colour, 3.0, 0.85)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	boss.get_parent().add_child(ring)
	ring.global_position = centre + Vector3.UP * 0.25
	var r := 1.0
	var reach := float(spec["radius"])
	var hit := false
	var player := boss.target as Node3D
	while r < reach and is_instance_valid(ring) and is_instance_valid(boss):
		await get_tree().physics_frame
		r += RING_SPEED * get_physics_process_delta_time()
		ring.scale = Vector3(r, 1.0, r)
		if hit or not is_instance_valid(player):
			continue
		var flat := Vector2(player.global_position.x - centre.x, player.global_position.z - centre.z).length()
		if absf(flat - r) < RING_THICKNESS and player.global_position.y < centre.y + RING_CLEARANCE:
			hit = true
			_hurt(float(spec["damage"]))
	if is_instance_valid(ring):
		ring.queue_free()


func _chain(spec: Dictionary) -> void:
	var player := boss.target as Node3D
	var radius := float(spec["radius"])
	var delay := float(spec["delay"])
	var colour := Element.color(boss.element)
	for i in int(spec["count"]):
		if not is_instance_valid(boss) or boss.stats.is_dead() or not is_instance_valid(player):
			return
		var a := randf() * TAU
		var at := _on_ground(player.global_position + Vector3(cos(a), 0.0, sin(a)) * randf_range(3.5, 6.0))
		Vfx.ground_mark(boss.get_parent(), at, colour.lerp(Color(1, 0.2, 0.15), 0.4), radius, delay)
		Vfx.bolt(boss.get_parent(), boss.global_position + Vector3.UP, at + Vector3.UP, colour, 0.06, delay)
		await get_tree().create_timer(delay, false).timeout
		if not is_instance_valid(boss) or boss.stats.is_dead():
			return
		Vfx.flash(boss.get_parent(), boss.global_position + Vector3.UP, colour, 2.0, 0.2)
		boss.global_position = at + Vector3.UP * 0.1
		Vfx.area_blast(boss.get_parent(), at, boss.element, radius)
		_hurt_in_circle(at, radius, float(spec["damage"]))


# --- Helpers ---------------------------------------------------------------------------

func _hurt_in_circle(centre: Vector3, radius: float, damage: float) -> void:
	var player := boss.target as Node3D
	if not is_instance_valid(player):
		return
	var flat := Vector2(player.global_position.x - centre.x, player.global_position.z - centre.z).length()
	if flat <= radius and absf(player.global_position.y - centre.y) < 2.5:
		_hurt(damage)


func _hurt(damage: float) -> void:
	var amount := damage * (1.0 + EnemyTier.POWER * float(boss.tier))
	Combat.apply_hit(boss.target, amount, boss.element, boss)


## The ground under a point (the point itself where there is none).
func _on_ground(p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 30.0, p + Vector3.DOWN * 60.0, Combat.LAYER_WORLD)
	var hit := boss.get_world_3d().direct_space_state.intersect_ray(q)
	return (hit["position"] as Vector3) if not hit.is_empty() else p
