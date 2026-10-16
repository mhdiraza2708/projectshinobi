class_name BossSpecials
extends Node
## A boss's signature attacks, running beside its ordinary fighting. Each is
## shown before it lands (a mark on the ground, a gathering ring) and hurts
## only if you are still where it falls, so they are about moving, not about
## health. Data lives on the boss beat or bounty:
##   {"kind": "quake" | "ring" | "chain" | "sweep" | "pull" | "ward" | "call"
##             | "walls" | "tide",
##    "every": seconds between uses,
##    "below": health share under which it starts (1 = from the start),
##    "count", "radius", "damage", "delay" (seconds of warning)}
##
## quake  - marks fall round you and where you stand; leave them.
## ring   - a shockwave runs out from the boss along the ground; jump or
##          dash through it.
## chain  - the boss blinks to strike points round you one after another.
## sweep  - a blade of light turns round the boss at knee height; jump it.
## pull   - the boss drags you in, then bursts; get out (dash away) before it does.
## ward   - the boss raises a seal ward that turns almost every blow aside;
##          hit it hard enough, all at once, to break it and leave the boss reeling.
## call   - the boss calls shinobi of its own nature to its side.
## walls  - slabs of rock rise round the arena (one between you and the boss):
##          cover from its jutsu, and a wall in your way. They sink after a while.
## tide   - a flood comes in from the edge and closes on the middle; stay on dry
##          ground. It drains again.
## Only one special runs at a time (walls stand on after theirs has finished).

const KINDS: Array[String] = ["quake", "ring", "chain", "sweep", "pull", "ward", "call", "walls", "tide"]
## Defaults for what a spec leaves out.
const DEFAULTS := {
	"quake": {"every": 9.0, "below": 1.0, "count": 4, "radius": 3.6, "damage": 16.0, "delay": 1.15},
	"ring": {"every": 11.0, "below": 1.0, "count": 1, "radius": 24.0, "damage": 18.0, "delay": 0.9},
	"chain": {"every": 12.0, "below": 1.0, "count": 3, "radius": 3.2, "damage": 16.0, "delay": 0.7},
	# radius = the blade's length; duration = seconds for `turns` full turns.
	"sweep": {"every": 13.0, "below": 1.0, "turns": 1.0, "radius": 11.0, "damage": 20.0, "delay": 1.0, "duration": 2.8},
	# radius = the burst; duration = seconds of dragging; strength = m/s; range = how far it reaches.
	"pull": {"every": 15.0, "below": 1.0, "radius": 4.8, "damage": 22.0, "delay": 0.6, "duration": 2.2,
		"strength": 7.5, "range": 22.0},
	# reduction = share of damage the ward turns aside; force = damage that breaks it;
	# duration = seconds before it fades on its own.
	"ward": {"every": 24.0, "below": 1.0, "radius": 2.6, "damage": 0.0, "delay": 0.8, "duration": 9.0,
		"reduction": 0.9, "force": 80.0},
	# count = slabs (the first stands between you and the boss, the rest round you at
	# `radius` m); width = a slab's width; duration = seconds they stand; damage = to
	# anyone on the spot where one rises.
	"walls": {"every": 20.0, "below": 1.0, "count": 3, "radius": 6.0, "damage": 10.0, "delay": 1.1,
		"duration": 14.0, "width": 4.5},
	# radius = how far out the flood starts; to = the dry circle it closes to; rise = seconds
	# to close; duration = seconds before it drains; damage = per second in the water.
	"tide": {"every": 30.0, "below": 1.0, "radius": 15.0, "to": 6.0, "damage": 7.0, "delay": 1.4,
		"duration": 10.0, "rise": 4.0},
	# count = shinobi per call; duration = seconds they stay; max = most alive at once.
	"call": {"every": 22.0, "below": 1.0, "count": 2, "radius": 3.0, "damage": 0.0, "delay": 0.7,
		"duration": 24.0, "max": 4},
}
## How fast a ring runs out (m/s) and how thick it is.
const RING_SPEED := 13.0
const RING_THICKNESS := 1.7
## The ring clears you if your feet are this far above it.
const RING_CLEARANCE := 1.2
## How wide the sweeping blade is (m either side of its line).
const SWEEP_THICKNESS := 0.9
## The sweeping blade clears you if your feet are this far above it.
const SWEEP_CLEARANCE := 1.2
## The boss stops dragging you in this close.
const PULL_STOP := 1.6

var boss: EnemyShinobi
var specs: Array = []

var _left: Array[float] = []
var _busy := false
## While a tide is in: the radius (m) of the dry circle round its middle
## (INF when there is none), for the HUD and for tests.
var tide_safe_radius := INF
## Shinobi this boss has called that are still about.
var _calls: Array[EnemyShinobi] = []


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
		"sweep":
			await _sweep(spec)
		"pull":
			await _pull(spec)
		"ward":
			await _ward(spec)
		"call":
			await _call(spec)
		"walls":
			await _walls(spec)
		"tide":
			await _tide(spec)
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


## A blade of light turns round the boss at knee height. Low and wide: jump it.
func _sweep(spec: Dictionary) -> void:
	var player := boss.target as Node3D
	var centre := _on_ground(boss.global_position)
	var length := float(spec["radius"])
	var delay := float(spec["delay"])
	var duration := maxf(float(spec["duration"]), 0.2)
	var colour := Element.color(boss.element)
	var angle := randf() * TAU
	var pivot := Node3D.new()
	var blade := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(length, 0.22, SWEEP_THICKNESS * 0.7)
	blade.mesh = box
	blade.position = Vector3(length * 0.5, 0.0, 0.0)
	blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(blade)
	boss.get_parent().add_child(pivot)
	pivot.global_position = centre + Vector3.UP * 0.45
	pivot.rotation.y = angle
	# The blade shows faintly where it will start, then lights.
	blade.material_override = Vfx.glow_material(colour, 1.2, 0.3)
	Vfx.ground_mark(boss.get_parent(), centre, colour.lerp(Color(1, 0.2, 0.15), 0.5), 2.4, delay)
	await get_tree().create_timer(delay, false).timeout
	if not is_instance_valid(boss) or boss.stats.is_dead() or not is_instance_valid(pivot):
		if is_instance_valid(pivot):
			pivot.queue_free()
		return
	blade.material_override = Vfx.glow_material(colour, 3.5, 0.9)
	var total := TAU * float(spec["turns"])
	var swept := 0.0
	var hit := false
	while swept < total and is_instance_valid(boss) and not boss.stats.is_dead():
		await get_tree().physics_frame
		var step := total / duration * get_physics_process_delta_time()
		swept += step
		angle += step
		pivot.rotation.y = angle
		if hit or not is_instance_valid(player):
			continue
		# The blade's long side is the pivot's local +X: (cos a, 0, -sin a) in the world.
		var along := Vector3(cos(angle), 0.0, -sin(angle))
		var rel := player.global_position - centre
		var reach := rel.x * along.x + rel.z * along.z
		var off := Vector2(rel.x - along.x * reach, rel.z - along.z * reach).length()
		if reach > 0.0 and reach < length and off < SWEEP_THICKNESS \
				and player.global_position.y < centre.y + SWEEP_CLEARANCE:
			hit = true
			_hurt(float(spec["damage"]))
	if is_instance_valid(pivot):
		pivot.queue_free()


## The boss drags you toward itself, then bursts. Dash out before it does.
func _pull(spec: Dictionary) -> void:
	var player := boss.target as Node3D
	var centre := _on_ground(boss.global_position)
	var radius := float(spec["radius"])
	var delay := float(spec["delay"])
	var duration := float(spec["duration"])
	var colour := Element.color(boss.element)
	Vfx.flash(boss.get_parent(), boss.global_position + Vector3.UP, colour, 3.0, delay)
	await get_tree().create_timer(delay, false).timeout
	if not is_instance_valid(boss) or boss.stats.is_dead():
		return
	# The burst is marked for the whole of the pull, so it can be read.
	Vfx.ground_mark(boss.get_parent(), centre, colour.lerp(Color(1, 0.2, 0.15), 0.5), radius, duration)
	var left := duration
	while left > 0.0 and is_instance_valid(boss) and not boss.stats.is_dead() and is_instance_valid(player):
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		left -= dt
		var toward := centre - player.global_position
		toward.y = 0.0
		var dist := toward.length()
		if dist > PULL_STOP and dist < float(spec["range"]):
			(player as CharacterBody3D).move_and_collide(toward.normalized() * float(spec["strength"]) * dt)
	if not is_instance_valid(boss) or boss.stats.is_dead():
		return
	Vfx.area_blast(boss.get_parent(), centre, boss.element, radius)
	_hurt_in_circle(centre, radius, float(spec["damage"]))


## A seal ward: almost every blow is turned aside until enough of them land at
## once (or it fades). Breaking it leaves the boss reeling.
func _ward(spec: Dictionary) -> void:
	var reduction := clampf(float(spec["reduction"]), 0.0, 0.95)
	var duration := float(spec["duration"])
	var force := float(spec["force"])
	var colour := Element.color(boss.element)
	Vfx.ground_mark(boss.get_parent(), _on_ground(boss.global_position), colour, float(spec["radius"]) + 1.0, float(spec["delay"]))
	await get_tree().create_timer(float(spec["delay"]), false).timeout
	if not is_instance_valid(boss) or boss.stats.is_dead():
		return
	boss.stats.add_modifier(&"damage_reduction", reduction, duration)
	var shell := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = float(spec["radius"]) * 0.5
	sphere.height = sphere.radius * 2.0
	shell.mesh = sphere
	shell.material_override = Vfx.glow_material(colour.lightened(0.3), 1.6, 0.35)
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell.position = Vector3.UP * 1.0
	boss.add_child(shell)
	# What the blows would have done without the ward is what breaks it.
	var taken := [0.0]
	var count := func(amount: float, _e: int, _m: float) -> void:
		taken[0] += amount / maxf(1.0 - reduction, 0.05)
	boss.stats.damaged.connect(count)
	var left := duration
	while left > 0.0 and taken[0] < force and is_instance_valid(boss) and not boss.stats.is_dead():
		await get_tree().physics_frame
		left -= get_physics_process_delta_time()
		# The shell thins as the ward weakens.
		var weak := clampf(taken[0] / force, 0.0, 1.0)
		shell.scale = Vector3.ONE * lerpf(1.0, 0.8, weak)
	if not is_instance_valid(boss):
		return
	if boss.stats.health > 0.0:
		boss.stats.damaged.disconnect(count)
	boss.stats.clear_modifier(&"damage_reduction")
	if is_instance_valid(shell):
		shell.queue_free()
	if taken[0] >= force and not boss.stats.is_dead():
		Vfx.flash(boss.get_parent(), boss.global_position + Vector3.UP, colour.lightened(0.4), 3.2, 0.25)
		Vfx.sparks(boss.get_parent(), boss.global_position + Vector3.UP, colour, 22, 8.0)
		Sfx.play_at(&"weak_hit", boss.global_position + Vector3.UP)
		boss.stagger(boss.target)


## The boss calls shinobi of its own nature to its side.
func _call(spec: Dictionary) -> void:
	_calls.assign(_calls.filter(func(c: EnemyShinobi) -> bool: return is_instance_valid(c) and not c.is_defeated()))
	var room := int(spec["max"]) - _calls.size()
	if room <= 0 or not is_instance_valid(boss.target):
		return
	var colour := Element.color(boss.element)
	var spots: Array[Vector3] = []
	for i in mini(int(spec["count"]), room):
		var a := TAU * (float(i) + randf()) / float(maxi(int(spec["count"]), 1))
		spots.append(_on_ground(boss.global_position + Vector3(cos(a), 0.0, sin(a)) * float(spec["radius"]) * 1.4))
	for at in spots:
		Vfx.ground_mark(boss.get_parent(), at, colour, 1.4, float(spec["delay"]))
	await get_tree().create_timer(float(spec["delay"]), false).timeout
	if not is_instance_valid(boss) or boss.stats.is_dead():
		return
	for at in spots:
		var e := EnemyShinobi.new()
		e.rank = &"genin"
		e.element = boss.element
		e.tier = boss.tier
		e.target = boss.target
		e.lifetime = float(spec["duration"])
		boss.get_parent().add_child(e)
		e.global_position = at + Vector3.UP * 0.2
		_calls.append(e)
		Vfx.smoke_puff(boss.get_parent(), at + Vector3.UP, 1.0)
	Sfx.play_at(&"smoke", boss.global_position + Vector3.UP)
	if not boss.defeated.is_connected(_send_calls_away):
		boss.defeated.connect(_send_calls_away)


## Slabs of rock rise: one between the player and the boss, the rest round the
## player. Anyone on the spot is struck; after that they are cover, and in the way.
func _walls(spec: Dictionary) -> void:
	var player := boss.target as Node3D
	var delay := float(spec["delay"])
	var half := float(spec["width"]) * 0.5
	var colour := Element.color(boss.element)
	var spots: Array[Vector3] = []
	var facings: Array[float] = []
	var between := (boss.global_position - player.global_position)
	between.y = 0.0
	var line := between.normalized() if between.length() > 0.5 else Vector3.FORWARD
	for i in int(spec["count"]):
		var at: Vector3
		if i == 0:
			at = player.global_position + line * minf(between.length() * 0.5, 7.0)
			facings.append(atan2(-line.x, -line.z))
		else:
			var a := randf() * TAU
			at = player.global_position + Vector3(cos(a), 0.0, sin(a)) * float(spec["radius"])
			facings.append(atan2(cos(a), sin(a)))
		spots.append(_on_ground(at))
	for at in spots:
		Vfx.ground_mark(boss.get_parent(), at, colour.lerp(Color(1, 0.2, 0.15), 0.4), half, delay)
	await get_tree().create_timer(delay, false).timeout
	if not is_instance_valid(boss) or boss.stats.is_dead():
		return
	for i in spots.size():
		_hurt_in_circle(spots[i], half * 0.7, float(spec["damage"]))
		var wall := JutsuWall.new()
		wall.element = boss.element
		wall.half_width = half
		wall.duration = float(spec["duration"])
		# Under the boss's feet in the tree, so it goes if the boss does.
		add_child(wall)
		wall.global_position = spots[i]
		wall.rotation.y = facings[i]


## A flood closes in from the edge of the arena toward its middle, then drains.
## Standing in it hurts, every half second.
func _tide(spec: Dictionary) -> void:
	var player := boss.target as Node3D
	var centre := _on_ground((boss.global_position + player.global_position) * 0.5)
	var outer := float(spec["radius"])
	var floor_r := float(spec["to"])
	var delay := float(spec["delay"])
	var rise := maxf(float(spec["rise"]), 0.2)
	var duration := maxf(float(spec["duration"]), rise)
	var colour := Element.color(Element.WATER)
	# The edge of the coming water, shown before it moves.
	Vfx.ground_mark(boss.get_parent(), centre, colour, outer, delay)
	await get_tree().create_timer(delay, false).timeout
	if not is_instance_valid(boss) or boss.stats.is_dead():
		return
	var flood := MeshInstance3D.new()
	flood.material_override = Vfx.glow_material(colour.lightened(0.1), 0.9, 0.5)
	flood.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flood)
	flood.global_position = centre + Vector3.UP * 0.12
	var t := 0.0
	var tick := 0.0
	var drain := 1.5
	while t < duration + drain and is_instance_valid(boss) and not boss.stats.is_dead():
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		tide_safe_radius = _tide_safe_radius(t, outer, floor_r, rise, duration, drain)
		flood.mesh = _annulus(tide_safe_radius, outer + 12.0)
		tick += dt
		if tick >= 0.5:
			tick = 0.0
			if is_instance_valid(player):
				var flat := Vector2(player.global_position.x - centre.x, player.global_position.z - centre.z).length()
				if flat > tide_safe_radius and player.global_position.y < centre.y + 1.0:
					_hurt(float(spec["damage"]) * 0.5)
	tide_safe_radius = INF
	if is_instance_valid(flood):
		flood.queue_free()


## The dry circle's radius `t` seconds into a flood: closing over `rise`,
## holding until `duration`, then opening again over `drain`.
static func _tide_safe_radius(t: float, outer: float, floor_r: float, rise: float, duration: float, drain: float) -> float:
	if t < rise:
		return lerpf(outer, floor_r, smoothstep(0.0, 1.0, t / rise))
	if t < duration:
		return floor_r
	return lerpf(floor_r, outer + 12.0, clampf((t - duration) / drain, 0.0, 1.0))


## A flat ring from `inner` to `outer` metres, for water over the ground.
static func _annulus(inner: float, outer: float) -> ArrayMesh:
	var segments := 48
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in segments:
		var a := TAU * float(i) / float(segments)
		verts.append(Vector3(cos(a) * inner, 0.0, sin(a) * inner))
		verts.append(Vector3(cos(a) * outer, 0.0, sin(a) * outer))
	for i in segments:
		var a0 := i * 2
		var b0 := ((i + 1) % segments) * 2
		idx.append_array([a0, a0 + 1, b0, b0, a0 + 1, b0 + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## When the boss falls, the shinobi it called leave with it.
func _send_calls_away(_who: EnemyShinobi) -> void:
	for c in _calls:
		if is_instance_valid(c):
			c.dismiss()
	_calls.clear()


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
