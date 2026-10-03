class_name EyeArtMode
extends Node
## The player's eye art, opened in battle (hold the page shift and press
## Charge: LB + Y, or Ctrl + R). Opening costs chakra; for a few seconds the
## eye art's pattern shows in the irises and its "active" perks add to the
## player's (data/eye_arts.json), then it closes and recovers. After the
## chapter named by "awaken_after" the eye opens in its awakened form
## instead: its own pattern, name and stronger perks.
##
## The first opening in each area plays a close-up cinematic (EyeSequence);
## later ones just flash, so a fight isn't interrupted every time.

signal changed

## Abilities an open form can have (data/eye_arts.json "ability").
## mirror_return: guarding absorbs enemy jutsu (up to MIRROR_HOLD); the
## open-eye chord throws them all back at MIRROR_POWER times their power.
const ABILITIES := {"mirror_return": "Guard to absorb enemy jutsu, then %s + %s to throw them back"}
const MIRROR_HOLD := 3
const MIRROR_POWER := 1.5

enum Phase { READY, ACTIVE, RECOVERING }

## The open form's perks, which Perks adds to the clan's and eye art's.
static var boost: Dictionary = {}
## Areas (scene instance ids) where the cinematic already played, per form.
static var _seen: Dictionary = {}

var player: Player
var phase := Phase.READY
## Seconds left open, or recovering.
var time_left := 0.0
## Whether the form now open is the awakened one.
var awakened := false
## The pattern on the player's irises (null if the model has none).
var pattern: ShaderMaterial
## Jutsu the Mirror Eye has absorbed: {element, power, speed, radius, style}.
var held: Array[Dictionary] = []

var _glow: OmniLight3D
var _fade: Tween
## The irises' centres in the Head bone's rest frame, [between, one eye]
## (empty until measured; [ZERO, ZERO] if the model has no iris mesh).
var _irises_in_head: Array[Vector3] = []
## Seconds Second Look has added to this opening.
var _extended := 0.0


func _ready() -> void:
	name = "EyeArtMode"
	player = get_parent() as Player
	if player and player.model:
		player.model.model_loaded.connect(_on_model_loaded)


func _exit_tree() -> void:
	if boost.size() > 0 and phase == Phase.ACTIVE:
		boost = {}


## The player's eye art ({} without one).
static func art() -> Dictionary:
	return Perks.active_eye_art()


## Whether the eye has awakened: the chapter in "awaken_after" is cleared.
static func awakening_unlocked() -> bool:
	var after := Perks.awaken_after()
	return after != "" and Game.chapter_done(after)


## The form the eye opens in now: "active", or "awakened" once unlocked.
static func form() -> Dictionary:
	var a := art()
	if a.is_empty():
		return {}
	return a.get("awakened" if awakening_unlocked() else "active", {})


func seconds() -> float:
	return float(form().get("seconds", 10.0)) * (1.0 + Perks.value(&"eye_time"))


func cost() -> float:
	return float(form().get("cost", 25.0)) * maxf(0.2, 1.0 + Perks.value(&"eye_cost"))


## Seconds the eye rests after closing.
static func cooldown() -> float:
	return Perks.eye_cooldown() * maxf(0.2, 1.0 + Perks.value(&"eye_cooldown"))


## Whether the eye is being held open past its time on chakra (Unclosing Eye).
func sustaining() -> bool:
	return phase == Phase.ACTIVE and time_left <= 0.0


## Opens the eye if it can: returns whether it did.
func try_open() -> bool:
	var a := art()
	if a.is_empty():
		player.feedback.emit("You have no eye art", &"info")
		return false
	if phase == Phase.ACTIVE:
		return false
	if phase == Phase.RECOVERING:
		player.feedback.emit("%s recovering: %ds" % [a["name"], ceili(time_left)], &"info")
		return false
	if UltimateSequence.active != null or EyeSequence.active != null or Cutscene.active != null:
		return false
	if not player.stats.spend_chakra(cost()):
		player.feedback.emit("Not enough chakra to open the %s" % a["name"], &"info")
		return false
	awakened = awakening_unlocked()
	phase = Phase.ACTIVE
	time_left = seconds()
	boost = (form().get("perks", {}) as Dictionary).duplicate()
	# Inner Light: the open form's perks run stronger.
	var power := 1.0 + Perks.value(&"eye_power")
	for key: String in boost:
		boost[key] = float(boost[key]) * power
	_extended = 0.0
	player.refresh_perks()
	if Perks.has(&"eye_flash"):
		_flash()
	pattern = EyePattern.attach(player.model, a)
	_set_pattern(0.0, 1.0 if awakened else 0.0, 0.0)
	_add_glow(Color(str(a["color"])))
	var key := "%d:%s" % [_area_id(), "awakened" if awakened else "active"]
	if not _seen.has(key):
		_seen[key] = true
		EyeSequence.begin(player, self)
	else:
		_quick_open()
	changed.emit()
	return true


## The open form's ability ("" for none).
func ability() -> String:
	return str(form().get("ability", "")) if phase == Phase.ACTIVE and awakened else ""


## A projectile is about to hit the player: the awakened Mirror Eye takes it
## in if the player is guarding. Returns whether it was absorbed.
func try_absorb(p: JutsuProjectile) -> bool:
	if ability() != "mirror_return" or player.state != Player.State.GUARDING or p.style == &"kunai":
		return false
	if held.size() >= MIRROR_HOLD:
		return false
	held.append({"element": p.element, "power": p.power, "speed": p.speed, "radius": p.radius, "style": p.style})
	var c := Color(str(art()["color"]))
	var facing := (p.global_position - player.global_position)
	facing.y = 0.0
	Vfx.shockwave(player.get_parent(), p.global_position, c, 1.2, 0.35, facing.normalized() if facing.length() > 0.01 else Vector3.FORWARD)
	Vfx.flash(player.get_parent(), p.global_position, c, 1.3, 0.2)
	Sfx.play(&"guard", 0.0, 0.1)
	player.feedback.emit("Absorbed (%d/%d)" % [held.size(), MIRROR_HOLD], &"info")
	changed.emit()
	return true


## Throws everything the Mirror Eye holds back at the player's target.
## Returns whether anything was thrown.
func release() -> bool:
	if ability() != "mirror_return" or held.is_empty():
		return false
	var target := player.aim_target()
	var world := player.get_parent()
	var aim := player.caster.aim_direction(target)
	var origin := player.global_position + Vector3.UP * 1.2 + aim * 0.8
	for i in held.size():
		var h: Dictionary = held[i]
		var p := JutsuProjectile.new()
		p.element = int(h["element"])
		p.power = float(h["power"]) * MIRROR_POWER * Perks.damage_multiplier(p.element)
		p.speed = float(h["speed"]) * 1.2
		p.radius = float(h["radius"])
		p.style = h["style"]
		p.max_range = 40.0
		p.caster = player
		p.target = target
		p.homing_rate = 6.0
		p.direction = aim.rotated(Vector3.UP, (i - (held.size() - 1) * 0.5) * JutsuCaster.FAN_SPREAD).normalized()
		world.add_child(p)
		p.global_position = origin
	Vfx.shockwave(world, origin, Color(str(art()["color"])), 1.6, 0.4, aim)
	Sfx.play(StringName("cast_" + Element.NAMES[int(held[0]["element"])]), 2.0)
	if player.animator:
		player.animator.cast()
	player.feedback.emit("Returned %d jutsu" % held.size(), &"info")
	held.clear()
	changed.emit()
	return true


## Opening Flash: every foe close by is knocked off balance.
func _flash() -> void:
	var c := Color(str(art()["color"]))
	var world := player.get_parent()
	Vfx.shockwave(world, player.global_position + Vector3.UP * 0.3, c, SkillTrees.EYE_FLASH_RADIUS, 0.45)
	Vfx.flash(world, player.global_position + Vector3.UP * 1.5, c, 3.0, 0.25)
	for foe in player.get_tree().get_nodes_in_group(&"enemies"):
		if foe is EnemyShinobi and not foe.is_defeated() \
				and foe.global_position.distance_to(player.global_position) <= SkillTrees.EYE_FLASH_RADIUS:
			foe.stagger()


## Second Look: a landed hit keeps the eye open a little longer.
func on_hit_landed() -> void:
	if phase != Phase.ACTIVE or sustaining() or not Perks.has(&"eye_extend"):
		return
	var add := minf(SkillTrees.EYE_EXTEND_PER_HIT, SkillTrees.EYE_EXTEND_MAX - _extended)
	if add > 0.0:
		_extended += add
		time_left += add
		changed.emit()


## Closes the eye now (time ran out, or the player went down).
func close() -> void:
	if phase != Phase.ACTIVE:
		return
	held.clear()
	phase = Phase.RECOVERING
	time_left = cooldown()
	boost = {}
	player.refresh_perks()
	if pattern:
		_tween_pattern(0.0, 0.35)
	if is_instance_valid(_glow):
		_glow.queue_free()
	changed.emit()


func _process(delta: float) -> void:
	if player == null or phase == Phase.READY:
		return
	# The clock stands still while a cinematic plays.
	if UltimateSequence.active != null or EyeSequence.active != null:
		return
	time_left -= delta
	if phase == Phase.ACTIVE:
		if player.stats.is_dead() or player.is_down():
			close()
		elif time_left <= 0.0:
			# Unclosing Eye: past its time the eye burns chakra to stay open.
			var drain := SkillTrees.EYE_SUSTAIN_DRAIN * delta
			if Perks.has(&"eye_sustain") and player.stats.chakra >= drain:
				time_left = 0.0
				player.stats.chakra -= drain
				player.stats.chakra_changed.emit(player.stats.chakra, player.stats.max_chakra)
			else:
				close()
		elif is_instance_valid(_glow):
			_glow.light_energy = 0.5 + 0.2 * sin(Time.get_ticks_msec() * 0.006)
	elif time_left <= 0.0:
		phase = Phase.READY
		time_left = 0.0
		changed.emit()


## How far through its phase the eye is (for the HUD): open time left, or
## how far it has recovered.
func ratio() -> float:
	match phase:
		Phase.ACTIVE:
			return 1.0 if sustaining() else clampf(time_left / maxf(seconds(), 0.01), 0.0, 1.0)
		Phase.RECOVERING:
			return clampf(1.0 - time_left / maxf(cooldown(), 0.01), 0.0, 1.0)
	return 1.0


## Sets the iris pattern's shader values (the cinematic animates these).
func _set_pattern(intensity: float, awake: float, spin: float) -> void:
	if pattern == null:
		return
	pattern.set_shader_parameter(&"intensity", intensity)
	pattern.set_shader_parameter(&"awakened", awake)
	pattern.set_shader_parameter(&"spin", spin)


func _tween_pattern(to: float, seconds_: float) -> void:
	if _fade and _fade.is_valid():
		_fade.kill()
	var mat := pattern
	var from: float = mat.get_shader_parameter(&"intensity")
	_fade = create_tween()
	_fade.tween_method(func(v: float) -> void: mat.set_shader_parameter(&"intensity", v), from, to, seconds_)
	if to <= 0.0:
		_fade.tween_callback(func() -> void:
			if phase != Phase.ACTIVE and is_instance_valid(player):
				EyePattern.detach(player.model)
				pattern = null)


## Opening without the cinematic: the pattern spins in with a flash.
func _quick_open() -> void:
	var c := Color(str(art()["color"]))
	Sfx.play(&"buff", -2.0)
	Vfx.flash(player.get_parent(), player.global_position + Vector3.UP * 1.5, c, 1.6, 0.3)
	if pattern == null:
		return
	var mat := pattern
	var tw := create_tween()
	tw.tween_method(func(k: float) -> void:
		mat.set_shader_parameter(&"intensity", k)
		mat.set_shader_parameter(&"spin", (1.0 - k) * TAU * 1.5), 0.0, 1.0, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


## A faint light of the eye art's colour at the eyes while it's open.
func _add_glow(c: Color) -> void:
	if is_instance_valid(_glow):
		_glow.queue_free()
	_glow = OmniLight3D.new()
	_glow.name = "EyeGlow"
	_glow.light_color = c
	_glow.light_energy = 0.6
	_glow.omni_range = 0.7
	_glow.shadow_enabled = false
	player.add_child(_glow)
	_glow.position = player.to_local(eye_point()) + Vector3(0, 0, -0.12)


## Between the player's eyes, in world space: the centre of the iris mesh,
## carried by the head (the eye bones sit higher, at the eyeballs' pivots).
func eye_point() -> Vector3:
	var at := _iris_point(0)
	if at != Vector3.INF:
		return at
	var skel := player.model.skeleton if player.model else null
	if skel:
		var l := skel.find_bone(&"LeftEye")
		var r := skel.find_bone(&"RightEye")
		if l >= 0 and r >= 0:
			return skel.global_transform * ((skel.get_bone_global_pose(l).origin + skel.get_bone_global_pose(r).origin) * 0.5)
		var head := skel.find_bone(&"Head")
		if head >= 0:
			return skel.global_transform * skel.get_bone_global_pose(head).origin + Vector3.UP * 0.07
	return player.global_position + Vector3.UP * 1.45


## The centre of one iris in world space (for the extreme close-up), or
## between the eyes if the model's irises can't be told apart.
func iris_point() -> Vector3:
	var at := _iris_point(1)
	return at if at != Vector3.INF else eye_point()


## World position of _irises_in_head[i] on the posed head (INF: unknown).
func _iris_point(i: int) -> Vector3:
	var skel := player.model.skeleton if player.model else null
	if skel == null:
		return Vector3.INF
	if _irises_in_head.is_empty():
		_irises_in_head = _measure_irises(skel)
	var head := skel.find_bone(&"Head")
	if head < 0 or _irises_in_head[i] == Vector3.ZERO:
		return Vector3.INF
	return skel.global_transform * (skel.get_bone_global_pose(head) * _irises_in_head[i])


## Where the irises are relative to the Head bone at rest: [between them,
## the one on the character's left]; ZERO where unknown.
func _measure_irises(skel: Skeleton3D) -> Array[Vector3]:
	var none: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	var head := skel.find_bone(&"Head")
	if head < 0:
		return none
	for node in player.model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or mi.has_meta(&"gear"):
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m == null or not "iris" in m.resource_name.to_lower():
				continue
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
			if verts.is_empty():
				continue
			var lo := verts[0]
			var hi := verts[0]
			for v in verts:
				lo = lo.min(v)
				hi = hi.max(v)
			var mid := (lo + hi) * 0.5
			# One eye: the vertices on the +X side of the face.
			var one_lo := Vector3(INF, INF, INF)
			var one_hi := -one_lo
			for v in verts:
				if v.x > mid.x:
					one_lo = one_lo.min(v)
					one_hi = one_hi.max(v)
			var one := (one_lo + one_hi) * 0.5 if one_lo.x != INF else mid
			# Bind-pose mesh space to skeleton space, then into the head's rest frame.
			var to_head := skel.get_bone_global_rest(head).affine_inverse() \
				* (skel.global_transform.affine_inverse() * mi.global_transform)
			var out: Array[Vector3] = [to_head * mid, to_head * one]
			return out
	return none


func _on_model_loaded() -> void:
	_irises_in_head.clear()
	# A new model (wardrobe change) needs the pattern put back on its irises.
	if phase == Phase.ACTIVE:
		pattern = EyePattern.attach(player.model, art())
		_set_pattern(1.0, 1.0 if awakened else 0.0, 0.0)


func _area_id() -> int:
	var scene := get_tree().current_scene if is_inside_tree() else null
	return scene.get_instance_id() if scene else 0


## Forgets which areas have shown the cinematic (tests).
static func reset_seen() -> void:
	_seen.clear()
