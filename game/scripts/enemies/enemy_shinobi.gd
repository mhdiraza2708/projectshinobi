class_name EnemyShinobi
extends CharacterBody3D
## A hostile shinobi. In the trials they are chakra clones summoned by the
## trial scroll, so defeat is a puff of smoke.
##
## They fight with the player's tools: kunai, strikes and woven jutsu. While
## one weaves, its seals appear above its head, so you can read what's coming
## and interrupt it: a hit at least as big as its rank's `interrupt` value
## breaks the weave (a kunai is enough for a genin).

signal defeated(enemy: EnemyShinobi)
## A story boss crossed one of its `phases` health thresholds.
signal phase_reached(phase: Dictionary)

enum State { SPAWNING, FIGHT, WEAVING, WINDUP, GUARDING, DODGING, STAGGERED, DEFEATED }

const RANKS := {
	&"genin": {
		"title": "Genin", "health": 80.0, "run": 5.0, "seal_time": 0.46, "interrupt": 4.5,
		"power": 0.55, "melee": 6.0, "windup": 0.45, "combo": 2, "think": Vector2(0.7, 1.3),
		"dodge": 0.15, "guard": 0.0, "range": 7.0, "kunai_cd": Vector2(2.2, 3.6),
		"jutsu_cd": Vector2(4.0, 6.5), "max_cost": 15.0,
	},
	&"chunin": {
		"title": "Chunin", "health": 130.0, "run": 5.8, "seal_time": 0.34, "interrupt": 6.0,
		"power": 0.65, "melee": 8.0, "windup": 0.36, "combo": 3, "think": Vector2(0.5, 1.0),
		"dodge": 0.35, "guard": 0.3, "range": 9.0, "kunai_cd": Vector2(1.6, 2.8),
		"jutsu_cd": Vector2(3.0, 5.0), "max_cost": 22.0,
	},
	&"jonin": {
		"title": "Jonin", "health": 240.0, "run": 6.4, "seal_time": 0.26, "interrupt": 10.0,
		"power": 0.75, "melee": 10.0, "windup": 0.3, "combo": 3, "think": Vector2(0.35, 0.8),
		"dodge": 0.5, "guard": 0.45, "range": 10.0, "kunai_cd": Vector2(1.2, 2.2),
		"jutsu_cd": Vector2(2.2, 3.8), "max_cost": 100.0,
	},
}

const SPAWN_TIME := 0.9
const DODGE_SPEED := 15.0
const DODGE_TIME := 0.22
const STAGGER_TIME := 0.55
const GUARD_TIME := 0.9
const MELEE_REACH := 1.1
## Enemies steer back toward the arena centre beyond this radius.
const ARENA_RADIUS := 22.0
const GRAVITY := 24.0
const BAR_SIZE := Vector2i(120, 12)

@export var rank := &"genin"
@export var element := Element.FIRE
## Empty = pick from the character roster.
@export var model_path := ""
## Story bosses: a name instead of "<Nature> <Rank>", a portrait kanji, a
## health pool, a look, and phases [{at: 0-1 health share, element: int or
## -1, say: String, summon: [[rank, element], ...]}] handled by whoever
## listens to phase_reached.
var title_override := ""
var kanji_override := ""
var health_override := 0.0
var style_override: Dictionary = {}
var phases: Array = []
## Who to fight (normally the player).
var target: Node3D
## Combat team (see Combat.same_team); also this node's group.
var team := &"enemies"
var state := State.SPAWNING

var stats: Stats
var caster: JutsuCaster
var model: CharacterModel
var jutsu_list: Array[JutsuDefinition] = []

var _r: Dictionary
var _state_time := 0.0
var _think := 0.0
var _kunai_cd := 0.0
var _jutsu_cd := 0.0
var _melee_cd := 0.0
var _strafe_sign := 1.0
var _rush := 0.0
var _combo := 0
var _dodge_dir := Vector3.RIGHT
var _last_projectile_rolled := 0
var _weave: JutsuDefinition
var _weave_index := 0
var _seal_timer := 0.0
var _kunai: JutsuDefinition
var _name_label: Label3D
var _seal_label: Label3D
var _bar: Sprite3D
var _bar_image: Image
var _ring: MeshInstance3D
var _next_phase := 0


func _ready() -> void:
	_r = RANKS.get(rank, RANKS[&"genin"])
	add_to_group(&"lockable")
	add_to_group(team)
	collision_layer = Combat.LAYER_TARGETS
	collision_mask = Combat.BODY_MASK | Combat.LAYER_PLAYER

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.75
	shape.shape = capsule
	shape.position.y = 0.875
	add_child(shape)

	stats = Stats.new()
	stats.name = "Stats"
	stats.max_health = health_override if health_override > 0.0 else float(_r["health"])
	stats.chakra_regen = 8.0
	stats.affinity = element
	add_child(stats)
	stats.health_changed.connect(func(_c: float, _m: float) -> void: _draw_bar())
	stats.damaged.connect(_on_damaged)
	stats.died.connect(_on_died)

	model = CharacterModel.new()
	model.name = "Model"
	model.use_profile = false
	model.model_path = model_path if model_path != "" else pick_model()
	model.style = style_override if not style_override.is_empty() else style_for(element, rank)
	add_child(model)

	caster = JutsuCaster.new()
	caster.name = "Caster"
	caster.position = Vector3(0, 1.2, -0.6)
	caster.stats = stats
	caster.body = self
	caster.affinity = element
	caster.power_scale = _r["power"]
	add_child(caster)

	_kunai = JutsuDefinition.new()
	_kunai.id = &"enemy_kunai"
	_kunai.display_name = "Kunai"
	_kunai.power = 6.0
	_kunai.speed = 28.0
	_kunai.max_range = 30.0
	_kunai.radius = 0.12
	_kunai.chakra_cost = 0.0
	_kunai.cooldown = 0.0
	_kunai.visual = &"kunai"
	_kunai.homing = 2.5
	jutsu_list = jutsu_for(element, _r["max_cost"])

	_build_overhead()
	_think = randf_range(0.6, 1.2)
	_kunai_cd = randf_range(1.0, 2.0)
	_jutsu_cd = randf_range(1.5, 3.0)
	_strafe_sign = 1.0 if randf() < 0.5 else -1.0
	Vfx.burst(get_parent(), global_position + Vector3.UP, Color(0.85, 0.85, 0.9), 1.4, 0.5)
	Sfx.play_at(&"smoke", global_position)


## The look of a clone of `nature`: element-tinted, masked, metal headband.
static func style_for(nature: int, rank_id: StringName) -> Dictionary:
	var c := Element.color(nature)
	return {
		"tints": {
			"body": Color(0.62, 0.62, 0.68).lerp(c, 0.35),
			"outfit": Color(0.22, 0.22, 0.27).lerp(c, 0.3),
			"lower": Color(0.2, 0.2, 0.24),
			"hair": Color(0.3, 0.3, 0.34).lerp(c, 0.5),
		},
		"headband": "hachigane",
		"headband_color": c.darkened(0.25),
		"mask": true,
		"mask_color": Color("1a1a20"),
		"scarf": rank_id != &"genin",
		"scarf_color": c.darkened(0.35),
		"back": "ninjato" if rank_id == &"jonin" else "none",
		"pouch": true,
		"expression": "angry",
		# Every clone wears the same hooded shinobi outfit, dyed by nature.
		"outfit_from": "hairsample_male",
	}


## Offensive jutsu of `nature` costing at most `max_cost`.
static func jutsu_for(nature: int, max_cost: float) -> Array[JutsuDefinition]:
	var out: Array[JutsuDefinition] = []
	for j in JutsuRegistry.all():
		if j.element == nature and j.chakra_cost <= max_cost and \
				(j.form == JutsuDefinition.Form.PROJECTILE or j.form == JutsuDefinition.Form.AREA):
			out.append(j)
	if out.is_empty() and JutsuRegistry.get_jutsu(&"chakra_bolt"):
		out.append(JutsuRegistry.get_jutsu(&"chakra_bolt"))
	return out


## A roster character other than the player's own, else the placeholder.
## With `key` (a story character id) the pick is always the same one.
static func pick_model(key := "") -> String:
	var mine: String = Profile.get_value(&"model")
	if mine == "":
		mine = CharacterModel.DEFAULT_MODEL
	var options: Array[String] = []
	for entry in CharacterModel.roster():
		var path: String = entry["path"]
		if path != CharacterModel.USER_MODEL and path != mine and path != CharacterModel.PLACEHOLDER_MODEL:
			options.append(path)
	if options.is_empty():
		return CharacterModel.PLACEHOLDER_MODEL
	if key != "":
		return options[absi(hash(key)) % options.size()]
	return options.pick_random()


func display_name() -> String:
	if title_override != "":
		return "%s %s" % [Element.kanji(element), title_override]
	return "%s %s %s" % [Element.kanji(element), Element.display_name(element), _r["title"]]


func is_boss() -> bool:
	return title_override != ""


## Switches chakra nature mid-fight: weakness, jutsu, colours and name.
func set_element(nature: int) -> void:
	element = nature
	stats.affinity = nature
	caster.affinity = nature
	jutsu_list = jutsu_for(nature, _r["max_cost"])
	var c := Element.color(nature)
	_ring.material_override = Vfx.glow_material(c, 1.2, 0.45)
	_name_label.text = display_name()
	_name_label.modulate = c.lightened(0.35)
	Vfx.burst(get_parent(), global_position + Vector3.UP, c, 1.3, 0.35)


func is_defeated() -> bool:
	return state == State.DEFEATED


## Vanishes at once, whatever state it is in (a boss's clones when it falls).
func dismiss() -> void:
	if state != State.DEFEATED:
		stats.health = 0.0
		_on_died()


# --- Loop ----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_state_time += delta
	_kunai_cd -= delta
	_jutsu_cd -= delta
	_melee_cd -= delta
	_rush -= delta

	match state:
		State.SPAWNING:
			_decelerate(delta)
			if _state_time >= SPAWN_TIME:
				_enter(State.FIGHT)
		State.FIGHT: _fight(delta)
		State.WEAVING: _weaving(delta)
		State.WINDUP: _windup(delta)
		State.GUARDING:
			_decelerate(delta)
			_face_target(delta)
			if _state_time >= GUARD_TIME:
				_enter(State.FIGHT)
		State.DODGING:
			velocity.x = _dodge_dir.x * DODGE_SPEED
			velocity.z = _dodge_dir.z * DODGE_SPEED
			stats.is_invulnerable = _state_time < DODGE_TIME * 0.6
			if _state_time >= DODGE_TIME:
				_enter(State.FIGHT)
		State.STAGGERED:
			_decelerate(delta)
			if _state_time >= STAGGER_TIME:
				_enter(State.FIGHT)
		State.DEFEATED:
			_decelerate(delta)

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	move_and_slide()
	_update_animator()


func _enter(new_state: State) -> void:
	match state:
		State.GUARDING: stats.guard_multiplier = 1.0
		State.DODGING: stats.is_invulnerable = false
		State.WEAVING, State.WINDUP: _seal_label.text = ""
	state = new_state
	_state_time = 0.0
	if new_state == State.GUARDING:
		stats.guard_multiplier = 0.3


func _target_ok() -> bool:
	if not is_instance_valid(target) or not target.is_inside_tree():
		return false
	return not (target.has_method("is_down") and target.is_down())


func _fight(delta: float) -> void:
	if not _target_ok():
		_decelerate(delta)
		return
	var to := target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var fwd := to / maxf(dist, 0.01)
	_face_target(delta)

	if _incoming_projectile() and randf() < float(_r["dodge"]):
		_dodge()
		return

	# Hold a preferred distance and circle; close in when rushing.
	var desired: float = 1.4 if _rush > 0.0 else float(_r["range"])
	var side := fwd.cross(Vector3.UP) * _strafe_sign
	var dir := side * 0.7
	if dist > desired + 1.5:
		dir = fwd + side * 0.2
	elif dist < desired - 1.5:
		dir = -fwd * 0.8 + side * 0.5
	dir += _separation()
	if global_position.length() > ARENA_RADIUS:
		dir += -Vector3(global_position.x, 0, global_position.z).normalized()
	var speed: float = _r["run"] * (1.15 if _rush > 0.0 else 1.0)
	_move(dir.limit_length(1.0) * speed, delta)

	if dist < 2.2 and _melee_cd <= 0.0:
		_start_windup()
		return
	_think -= delta
	if _think > 0.0:
		return
	var span: Vector2 = _r["think"]
	_think = randf_range(span.x, span.y)
	if randf() < 0.3:
		_strafe_sign = -_strafe_sign
	if _jutsu_cd <= 0.0:
		var j := _pick_jutsu(dist)
		if j:
			_start_weave(j)
			return
	if _kunai_cd <= 0.0 and dist > 3.5 and dist < 26.0:
		_throw_kunai()
	elif _melee_cd <= 0.0 and _rush <= 0.0 and randf() < 0.3:
		_rush = 3.0


## A jutsu that suits the distance and can be paid for, or null.
func _pick_jutsu(dist: float) -> JutsuDefinition:
	var usable: Array[JutsuDefinition] = []
	for j in jutsu_list:
		if caster.block_reason(j) != &"":
			continue
		if j.form == JutsuDefinition.Form.PROJECTILE and dist <= j.max_range * 0.85 and dist > 3.0:
			usable.append(j)
		elif j.form == JutsuDefinition.Form.AREA and absf(dist - j.max_range) <= j.radius * 0.8:
			usable.append(j)
	return usable.pick_random() if not usable.is_empty() else null


# --- Actions ---------------------------------------------------------------------

func _start_weave(j: JutsuDefinition) -> void:
	_weave = j
	_weave_index = 0
	_seal_timer = float(_r["seal_time"]) * 0.6
	_enter(State.WEAVING)
	_seal_label.modulate = Element.color(element).lightened(0.25)
	_seal_label.text = "印"
	Sfx.play_at(&"weave_start", global_position)


func _weaving(delta: float) -> void:
	_decelerate(delta)
	_face_target(delta)
	_seal_timer -= delta
	if _seal_timer > 0.0:
		return
	if _weave_index < _weave.seals.size():
		var seal := _weave.seals[_weave_index]
		_weave_index += 1
		var shown := ""
		for i in _weave_index:
			shown += Seal.kanji(_weave.seals[i])
		_seal_label.text = shown
		Sfx.play_at(StringName("seal_%d" % (Seal.bank_of(seal) + 1)), global_position + Vector3.UP)
		if model.animator:
			model.animator.seal_flick()
		_seal_timer = _r["seal_time"]
		return
	if _target_ok():
		_face_now(target.global_position - global_position)
		caster.cast(_weave, target)
	var span: Vector2 = _r["jutsu_cd"]
	_jutsu_cd = randf_range(span.x, span.y)
	_enter(State.FIGHT)


func _throw_kunai() -> void:
	_face_now(target.global_position - global_position)
	if model.animator:
		model.animator.throw()
	caster.cast(_kunai, target)
	var span: Vector2 = _r["kunai_cd"]
	_kunai_cd = randf_range(span.x, span.y)


func _start_windup() -> void:
	_rush = 0.0
	_combo = 0
	_enter(State.WINDUP)
	_seal_label.modulate = UiKit.CRIMSON.lightened(0.2)
	_seal_label.text = "!"


func _windup(delta: float) -> void:
	_decelerate(delta)
	_face_target(delta)
	var windup: float = _r["windup"] * (1.0 if _combo == 0 else 0.7)
	if _state_time < windup:
		return
	_melee_hit()
	_combo += 1
	var close := _target_ok() and global_position.distance_to(target.global_position) < 2.6
	if _combo < int(_r["combo"]) and close:
		_state_time = 0.0
		return
	_melee_cd = randf_range(1.2, 2.2)
	_enter(State.FIGHT)


func _melee_hit() -> void:
	if model.animator:
		model.animator.strike()
	Sfx.play_at(&"strike_whoosh", global_position, -3.0, 0.1)
	var forward := -global_basis.z
	velocity += forward * 3.0
	var center := global_position + forward * MELEE_REACH + Vector3.UP * 1.1
	var landed := false
	for victim in Combat.hittables_in_sphere(get_world_3d(), center, 0.9, [get_rid()]):
		if Combat.apply_hit(victim, _r["melee"], Element.NONE, self) > 0.0:
			landed = true
	if landed:
		Sfx.play_at(&"strike_hit", center, 0.0, 0.1)


func _dodge() -> void:
	var side := Vector3.UP.cross(-global_basis.z).normalized()
	_dodge_dir = side * (1.0 if randf() < 0.5 else -1.0)
	Sfx.play_at(&"dash", global_position, -2.0)
	_enter(State.DODGING)


## True the first time a hostile projectile is seen heading this way.
func _incoming_projectile() -> bool:
	for node in get_tree().get_nodes_in_group(&"projectiles"):
		var p := node as JutsuProjectile
		if p == null or p.caster == self or Combat.same_team(p.caster, self):
			continue
		if p.get_instance_id() == _last_projectile_rolled:
			continue
		var to_me := global_position + Vector3.UP - p.global_position
		var d := to_me.length()
		if d < 7.0 and d > 0.5 and p.direction.dot(to_me / d) > 0.85:
			_last_projectile_rolled = p.get_instance_id()
			return true
	return false


func _separation() -> Vector3:
	var push := Vector3.ZERO
	for node in get_tree().get_nodes_in_group(team):
		var other := node as Node3D
		if other == self or other == null:
			continue
		var away := global_position - other.global_position
		away.y = 0.0
		var d := away.length()
		if d < 2.4 and d > 0.01:
			push += away / d * (2.4 - d) / 2.4
	return push


# --- Taking hits -------------------------------------------------------------------

func take_hit(amount: float, hit_element: int, source: Node) -> float:
	if state == State.SPAWNING or state == State.DEFEATED:
		return 0.0
	var dealt := stats.take_damage(amount, hit_element)
	if dealt <= 0.0 or stats.is_dead():
		return dealt
	var interrupt: float = _r["interrupt"]
	if state == State.WEAVING and dealt >= interrupt:
		_interrupted()
	elif dealt >= interrupt * 2.5 or (state == State.WINDUP and dealt >= interrupt * 1.5):
		_stagger()
	elif state == State.FIGHT and source is Player and randf() < float(_r["guard"]):
		_enter(State.GUARDING)
		Sfx.play_at(&"guard", global_position + Vector3.UP, -3.0)
	return dealt


func _interrupted() -> void:
	_pop("Interrupted!", UiKit.GOLD, 40)
	Sfx.play_at(&"seal_break", global_position + Vector3.UP)
	_jutsu_cd = maxf(_jutsu_cd, 1.5)
	_stagger()


func _stagger() -> void:
	_rush = 0.0
	_enter(State.STAGGERED)
	if _target_ok():
		var away := global_position - target.global_position
		away.y = 0.0
		velocity += away.normalized() * 3.0


func _check_phases() -> void:
	while _next_phase < phases.size() and not stats.is_dead():
		var phase: Dictionary = phases[_next_phase]
		if stats.health > float(phase.get("at", 0.0)) * stats.max_health:
			return
		_next_phase += 1
		if int(phase.get("element", -1)) >= 0 and int(phase["element"]) != element:
			set_element(int(phase["element"]))
		# Break off: a substitution-style hop away to regroup.
		_weave = null
		_enter(State.STAGGERED)
		if _target_ok():
			var away := global_position - target.global_position
			away.y = 0.0
			var hop := away.normalized().rotated(Vector3.UP, randf_range(-0.8, 0.8)) * 3.5
			Vfx.burst(get_parent(), global_position + Vector3.UP, Color(0.9, 0.9, 0.92), 1.6, 0.4)
			global_position += hop
			Sfx.play_at(&"smoke", global_position)
		phase_reached.emit(phase)


func _on_damaged(amount: float, hit_element: int, multiplier: float) -> void:
	_check_phases.call_deferred()
	var text := str(roundi(amount))
	if multiplier > 1.0:
		text += "  WEAK!"
		Sfx.play_at(&"weak_hit", global_position + Vector3.UP * 1.5)
	elif multiplier < 1.0:
		text += "  RESIST"
	_pop(text, Element.color(hit_element).lightened(0.2), 52 if multiplier > 1.0 else 40)


func _on_died() -> void:
	_enter(State.DEFEATED)
	remove_from_group(&"lockable")
	remove_from_group(team)
	collision_layer = 0
	_seal_label.text = ""
	_name_label.visible = false
	_bar.visible = false
	var puff := global_position + Vector3.UP
	Vfx.burst(get_parent(), puff, Color(0.9, 0.9, 0.92), 2.0, 0.6)
	Vfx.burst(get_parent(), puff + Vector3.UP * 0.3, Element.color(element), 1.2, 0.35)
	Sfx.play_at(&"smoke", puff)
	Sfx.play_at(&"enemy_down", puff, -2.0)
	defeated.emit(self)
	await get_tree().create_timer(0.12).timeout
	model.visible = false
	await get_tree().create_timer(0.8).timeout
	queue_free()


# --- Presentation ------------------------------------------------------------------

func _build_overhead() -> void:
	var c := Element.color(element)
	_ring = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.6
	disc.bottom_radius = 0.6
	disc.height = 0.02
	_ring.mesh = disc
	_ring.material_override = Vfx.glow_material(c, 1.2, 0.45)
	_ring.position.y = 0.02
	add_child(_ring)

	_name_label = _label3d(display_name(), 30, c.lightened(0.35))
	_name_label.position.y = 2.35
	add_child(_name_label)

	_bar_image = Image.create(BAR_SIZE.x, BAR_SIZE.y, false, Image.FORMAT_RGBA8)
	_bar = Sprite3D.new()
	_bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bar.no_depth_test = true
	_bar.pixel_size = 0.009
	_bar.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_bar.position.y = 2.05
	_bar.texture = ImageTexture.create_from_image(_bar_image)
	add_child(_bar)
	_draw_bar()

	_seal_label = _label3d("", 64, c)
	_seal_label.position.y = 2.85
	add_child(_seal_label)


func _label3d(text: String, size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = UiKit.font(&"bold")
	l.font_size = size
	l.outline_size = 10
	l.outline_modulate = Color(UiKit.INK, 0.9)
	l.modulate = color
	l.pixel_size = 0.01
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	return l


func _draw_bar() -> void:
	if _bar_image == null:
		return
	var frac := clampf(stats.health / stats.max_health, 0.0, 1.0)
	var fill := int(round((BAR_SIZE.x - 4) * frac))
	_bar_image.fill(Color(UiKit.INK, 0.85))
	_bar_image.fill_rect(Rect2i(2, 2, BAR_SIZE.x - 4, BAR_SIZE.y - 4), Color(0.25, 0.08, 0.06, 0.9))
	if fill > 0:
		_bar_image.fill_rect(Rect2i(2, 2, fill, BAR_SIZE.y - 4), UiKit.HEALTH.lightened(0.15))
	(_bar.texture as ImageTexture).update(_bar_image)


func _pop(text: String, color: Color, size: int) -> void:
	var pop := _label3d(text, size, color)
	add_child(pop)
	pop.position = Vector3(randf_range(-0.4, 0.4), 2.0, 0.0)
	var tw := pop.create_tween().set_parallel(true)
	tw.tween_property(pop, "position:y", 3.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(pop, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tw.chain().tween_callback(pop.queue_free)


func _update_animator() -> void:
	var animator := model.animator
	if animator == null:
		return
	match state:
		State.WEAVING: animator.pose = HumanoidPoser.Pose.WEAVE
		State.GUARDING: animator.pose = HumanoidPoser.Pose.GUARD
		State.DODGING: animator.pose = HumanoidPoser.Pose.DASH
		_: animator.pose = HumanoidPoser.Pose.LOCOMOTION
	animator.airborne = not is_on_floor()
	animator.speed_ratio = Vector2(velocity.x, velocity.z).length() / 7.0


# --- Movement helpers ------------------------------------------------------------

func _move(goal: Vector3, delta: float) -> void:
	velocity.x = move_toward(velocity.x, goal.x, 40.0 * delta)
	velocity.z = move_toward(velocity.z, goal.z, 40.0 * delta)


func _decelerate(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 40.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 40.0 * delta)


func _face_target(delta: float) -> void:
	if not _target_ok():
		return
	var dir := target.global_position - global_position
	if Vector2(dir.x, dir.z).length() < 0.01:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 1.0 - exp(-10.0 * delta))


func _face_now(dir: Vector3) -> void:
	if Vector2(dir.x, dir.z).length() < 0.01:
		return
	rotation.y = atan2(-dir.x, -dir.z)
