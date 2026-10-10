class_name EnemyShinobi
extends CharacterBody3D
## A hostile shinobi. In the trials they are chakra clones summoned by the
## trial scroll, so defeat is a puff of smoke.
##
## They fight with the player's tools: kunai, strikes and woven jutsu. Every
## attack announces itself: a thrower stops and glints before the kunai
## leaves, a striker winds up under a "!", a weaver's seals appear above its
## head (and an area jutsu marks the ground it will hit), so you can read
## what's coming. A hit at least as big as its rank's `interrupt` value breaks
## a weave (a kunai is enough for a genin). In a crowd they take turns (see
## AttackTokens) instead of all attacking at once.

signal defeated(enemy: EnemyShinobi)
## A story boss crossed one of its `phases` health thresholds.
signal phase_reached(phase: Dictionary)
## A hit from `by` broke this fighter's weave.
signal interrupted(by: Node)

enum State { SPAWNING, FIGHT, WEAVING, WINDUP, AIMING, GUARDING, DODGING, STAGGERED, DEFEATED }

## Per rank: `windup` is how long a striker winds up before its first blow,
## `aim` how long a thrower holds still before the kunai leaves, `poise` how
## much damage in quick succession it takes before it reels, and `engage` the
## seconds between its runs in to fight up close.
const RANKS := {
	&"genin": {
		"title": "Genin", "health": 80.0, "run": 5.0, "seal_time": 0.46, "interrupt": 4.5,
		"power": 0.55, "melee": 6.0, "windup": 0.5, "combo": 2, "think": Vector2(0.7, 1.3),
		"dodge": 0.15, "guard": 0.0, "range": 7.0, "kunai_cd": Vector2(2.2, 3.6),
		"jutsu_cd": Vector2(4.0, 6.5), "max_cost": 15.0,
		"aim": 0.55, "poise": 14.0, "engage": Vector2(7.0, 11.0),
	},
	&"chunin": {
		"title": "Chunin", "health": 130.0, "run": 5.8, "seal_time": 0.34, "interrupt": 6.0,
		"power": 0.65, "melee": 8.0, "windup": 0.42, "combo": 3, "think": Vector2(0.5, 1.0),
		"dodge": 0.35, "guard": 0.3, "range": 9.0, "kunai_cd": Vector2(1.6, 2.8),
		"jutsu_cd": Vector2(3.0, 5.0), "max_cost": 26.0,
		"aim": 0.45, "poise": 22.0, "engage": Vector2(5.0, 8.0),
	},
	&"jonin": {
		"title": "Jonin", "health": 240.0, "run": 6.4, "seal_time": 0.26, "interrupt": 10.0,
		"power": 0.75, "melee": 10.0, "windup": 0.4, "combo": 3, "think": Vector2(0.35, 0.8),
		"dodge": 0.5, "guard": 0.45, "range": 10.0, "kunai_cd": Vector2(1.2, 2.2),
		"jutsu_cd": Vector2(2.2, 3.8), "max_cost": 100.0,
		"aim": 0.38, "poise": 40.0, "engage": Vector2(3.5, 6.0),
	},
}

const SPAWN_TIME := 0.9
## When a spawning fighter shows through its smoke.
const SPAWN_SHOW := 0.15
const DODGE_SPEED := 15.0
const DODGE_TIME := 0.22
const STAGGER_TIME := 0.55
const GUARD_TIME := 0.9
## Seconds a fighter that guarded won't raise its guard again, so holding a
## combo on it isn't a wall of blocks.
const GUARD_REST := 2.5
const MELEE_REACH := 1.1
## Follow-up blows of a combo come this much sooner than the first.
const COMBO_FOLLOW := 0.8
## How long a runner-in keeps coming before it gives up.
const RUSH_TIME := 3.0
## Within this distance (m) a fighter that has the turn swings.
const RUSH_STRIKE_RANGE := 2.2
## Reeling from a stagger, a fighter shrugs off further staggers this long (it
## still takes the damage), so a flurry can't hold it down for good.
const ARMOR_TIME := 1.0
## Boss poise is this much deeper than its rank's.
const BOSS_POISE := 1.6
## Seconds unhurt before poise is whole again.
const POISE_REST := 1.6
## A light hit stops a fighter's own moves this long and pushes it back by
## this many m/s per point of damage (within RECOIL_PUSH_RANGE).
const RECOIL_TIME := 0.16
const RECOIL_PUSH := 0.5
const RECOIL_PUSH_RANGE := Vector2(1.5, 5.0)
## How hard a recoil slide is braked (m/s^2).
const RECOIL_DRAG := 16.0
## A stagger throws the fighter back this fast (m/s) and slows it by RECOIL_DRAG.
const STAGGER_PUSH := 6.0
## Thrown kunai turn toward their mark this quickly (rad/s): a dash sideways beats them.
const KUNAI_HOMING := 1.4
## Fast enemy jutsu home less so a late dash still beats them: the cap is
## HOMING_SPEED / speed within HOMING_CAP_RANGE.
const HOMING_SPEED := 36.0
const HOMING_CAP_RANGE := Vector2(0.5, 1.3)
## The arm cocks this long before a kunai leaves.
const THROW_CUE := 0.16
## The colour of a thrower's tell.
const AIM_COLOR := Color(0.88, 0.94, 1.0)
## Fighters hold their range within this share either way, so a crowd
## doesn't stand in one ring.
const RANGE_SPREAD := 0.18
## Teammates closer than this angle (rad) around the target push each other apart.
const SPREAD_ANGLE := 0.75
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
## Story character id whose recorded lines move this fighter's mouth.
var voice_id := ""
var phases: Array = []
## Who to fight (normally the player).
var target: Node3D
## Combat team (see Combat.same_team); also this node's group. &"player"
## makes an ally that fights the player's enemies.
var team := &"enemies"
## Re-pick the nearest opponent from time to time (off after stand_down()).
var hunt := true
## Practice clone: only weaves (slowly, weakly) so it can be interrupted.
var drill := false
## A Shade Clone: wears the look of `clone_of` (the player's, via the
## Profile), vanishes after `lifetime` seconds, and keeps close to its owner
## between fights. `damage_scale` is how much of a rank's damage it deals.
var clone_of: Node3D
## Shadow Bloom (skill tree): a clone bursts for this much when it goes.
var bloom_power := 0.0
## Sent away rather than beaten (no XP for the player).
var _dismissed := false
var lifetime := 0.0
var damage_scale := 1.0
## Body scale for oversized bosses.
var size := 1.0
## A glowing aura in this colour (alpha 0 = none), for possessed bosses.
var aura_color := Color(0, 0, 0, 0)
var state := State.SPAWNING

var stats: Stats
var caster: JutsuCaster
var model: CharacterModel
var jutsu_list: Array[JutsuDefinition] = []

var _r: Dictionary
var _state_time := 0.0
## Physics frame this fighter last began an attack (-1 = never), for AttackTokens.
var _attack_frame := -1
## Stagger and recoil: poise left, seconds unhurt, immunity to reeling, and the stun of a light hit.
var _max_poise := 1.0
var _poise := 1.0
var _poise_rest := 0.0
var _armor := 0.0
var _recoil := 0.0
var _guard_rest := 0.0
## Seconds until the next run in to fight up close.
var _engage := 0.0
var _range_bias := 1.0
var _cued := false
var _tamed: Dictionary = {}
var _lean: Tween
var _flare: Tween
var _danger: MeshInstance3D
var _danger_edge: MeshInstance3D
var _danger_jutsu: JutsuDefinition
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
var _hint_label: Label3D
var _hint_timer := 0.0
var _seal_label: Label3D
var _bar: Sprite3D
var _bar_image: Image
var _ring: MeshInstance3D
var _next_phase := 0
var _life_left := 0.0


func _ready() -> void:
	_r = RANKS.get(rank, RANKS[&"genin"]).duplicate()
	if drill:
		_r["seal_time"] = 0.6
		_r["power"] = 0.25
		_r["jutsu_cd"] = Vector2(1.2, 2.0)
		_r["dodge"] = 0.0
		_r["guard"] = 0.0
	_life_left = lifetime
	_max_poise = float(_r["poise"]) * (BOSS_POISE if is_boss() else 1.0)
	_poise = _max_poise
	_range_bias = randf_range(1.0 - RANGE_SPREAD, 1.0 + RANGE_SPREAD)
	var engage: Vector2 = _r["engage"]
	_engage = randf_range(engage.x, engage.y)
	_r["power"] = float(_r["power"]) * damage_scale
	_r["melee"] = float(_r["melee"]) * damage_scale
	if not is_ally():
		# Seal Eye: rivals' hands are slower to read.
		_r["seal_time"] = float(_r["seal_time"]) * (1.0 + Perks.value(&"enemy_seal_slow"))
	add_to_group(team)
	collision_layer = Combat.LAYER_TARGETS
	collision_mask = Combat.BODY_MASK | Combat.LAYER_PLAYER

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35 * size
	capsule.height = 1.75 * size
	shape.shape = capsule
	shape.position.y = 0.875 * size
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
	model.use_profile = clone_of != null
	if clone_of == null:
		var rivals: Array[String] = []
		if model_path == "" and style_override.is_empty() and rank != &"jonin":
			rivals = rival_models(element)
		if not rivals.is_empty():
			# The rank and file of a nature wear its masked rival.
			model.model_path = rivals.pick_random()
			model.style = RIVAL_STYLE.duplicate()
		else:
			model.model_path = model_path if model_path != "" else pick_model()
			model.style = (style_override if not style_override.is_empty() else style_for(element, rank)).duplicate()
		model.style["height"] = float(model.style.get("height", 1.0)) * size
	model.voice_id = voice_id
	add_child(model)
	if aura_color.a > 0.0:
		add_child(Vfx.boss_aura(aura_color, size))

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
	_kunai.homing = KUNAI_HOMING
	jutsu_list = jutsu_for(element, _r["max_cost"])

	_build_overhead()
	_think = randf_range(0.6, 1.2)
	_kunai_cd = randf_range(1.0, 2.0)
	_jutsu_cd = randf_range(1.5, 3.0)
	_strafe_sign = 1.0 if randf() < 0.5 else -1.0
	Vfx.smoke_puff(get_parent(), global_position + Vector3.UP, 1.0 * size)
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


## Masked rivals made for the game: "<nature>_<name>.glb" in RIVAL_DIR
## (Tripo models, see docs/CHARACTERS.md). Genin and chunin of that nature
## wear one; jonin and story characters keep a face.
const RIVAL_DIR := "res://assets/characters/rivals"
## Rivals come dressed: their own colours, mask and gear.
const RIVAL_STYLE := {"tints": {}, "headband": "none", "mask": false, "scarf": false,
	"back": "none", "pouch": false}


static func rival_models(nature: int) -> Array[String]:
	var out: Array[String] = []
	if nature <= Element.NONE or nature >= Element.NAMES.size() or not DirAccess.dir_exists_absolute(RIVAL_DIR):
		return out
	var prefix := Element.NAMES[nature] + "_"
	var files := Array(ResourceLoader.list_directory(RIVAL_DIR))
	files.sort()
	for file: String in files:
		if file.begins_with(prefix) and file.get_extension().to_lower() in ["glb", "vrm", "fbx"]:
			out.append(RIVAL_DIR.path_join(file))
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


func is_ally() -> bool:
	return team == &"player"


## Stops fighting for good (a trial or fight ended).
func stand_down() -> void:
	hunt = false
	target = null


## The nearest opponent still standing; the player counts as a little
## nearer, so enemies favour them over allies.
func pick_target() -> Node3D:
	var foes := &"enemies" if is_ally() else &"player"
	var best: Node3D = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group(foes):
		var n := node as Node3D
		if n == null or n == self or (n.has_method("is_down") and n.is_down()) \
				or (n.has_method("is_defeated") and n.is_defeated()):
			continue
		var d := global_position.distance_to(n.global_position) * (0.75 if n is Player else 1.0)
		if d < best_d:
			best_d = d
			best = n
	if best == null and clone_of != null:
		# Nobody fights back: a clone takes on whatever else can be hit
		# (practice dummies).
		for node in get_tree().get_nodes_in_group(&"lockable"):
			var n := node as Node3D
			if n == null or n == self or n is EnemyShinobi:
				continue
			var d := global_position.distance_to(n.global_position)
			if d < best_d and d < 30.0:
				best_d = d
				best = n
	return best


## Stays near its owner with the others of its kind, facing where they face.
func _follow_owner(delta: float) -> void:
	if not is_instance_valid(clone_of):
		_decelerate(delta)
		return
	var seat := clone_of.global_position + Vector3(sin(float(get_instance_id() % 628) / 100.0), 0.0,
		cos(float(get_instance_id() % 628) / 100.0)) * 2.6
	var to := seat - global_position
	to.y = 0.0
	if to.length() > 1.2:
		var run: float = _r["run"] * clampf(to.length() / 4.0, 0.4, 1.4)
		_move(to.normalized() * run, delta)
		rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), 1.0 - exp(-8.0 * delta))
	else:
		_decelerate(delta)


## Hawk Eye shows an arrow over rivals: gold up = your nature beats theirs,
## grey down = it doesn't.
func _update_hint() -> void:
	if _hint_label == null:
		return
	var show := not is_ally() and state != State.DEFEATED and Perks.has(&"reads_natures")
	_hint_label.visible = show
	if not show:
		return
	var mult := Element.multiplier(int(Profile.get_value(&"affinity")), element)
	_hint_label.text = "▲" if mult > 1.0 else ("▼" if mult < 1.0 else "")
	_hint_label.modulate = Color("e3a23a") if mult > 1.0 else Color(0.7, 0.72, 0.78)


## What floats over the head: clones only get a shade mark, so a pair
## standing together doesn't print their owner's name over each other.
func label_text() -> String:
	return "影" if clone_of != null else display_name()


func display_name() -> String:
	if clone_of != null:
		return "影 %s" % Profile.get_value(&"name")
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
	_ring.material_override = _ring_material(c)
	_name_label.text = label_text()
	_name_label.modulate = c.lightened(0.35)
	# Changing nature: a flare of the new colour.
	Vfx.flash(get_parent(), global_position + Vector3.UP, c.lightened(0.3), 2.4 * size, 0.25, &"glow")
	Vfx.shockwave(get_parent(), global_position, c, 2.6 * size, 0.5)
	Vfx.sparks(get_parent(), global_position + Vector3.UP, c.lightened(0.2), 16, 7.0)


## A soft glow in the nature's colour on the ground under the fighter.
static func _ring_material(c: Color) -> StandardMaterial3D:
	var m := Vfx.surface_material(Vfx.tex(&"glow"), true)
	m.albedo_color = Color(c, 0.75)
	return m


func is_defeated() -> bool:
	return state == State.DEFEATED


## Leaves in a puff of smoke without counting as defeated (an ally
## stepping out of the story).
func leave() -> void:
	_bloom()
	state = State.DEFEATED
	remove_from_group(&"lockable")
	remove_from_group(team)
	Vfx.smoke_puff(get_parent(), global_position + Vector3.UP, 1.0 * size)
	Sfx.play_at(&"smoke", global_position + Vector3.UP, -3.0)
	queue_free()


## Shadow Bloom: a clone's last act is a burst of its nature around it.
func _bloom() -> void:
	if bloom_power <= 0.0 or state == State.DEFEATED or not is_inside_tree():
		return
	var power := bloom_power
	bloom_power = 0.0
	var at := global_position + Vector3.UP
	var exclude: Array[RID] = [get_rid()]
	for victim in Combat.hittables_in_sphere(get_world_3d(), at, SkillTrees.SHADOW_BLOOM_RADIUS, exclude):
		if Combat.apply_hit(victim, power, element, self) > 0.0 and clone_of is Player:
			(clone_of as Player).notify_hit(victim, &"jutsu")
	Vfx.area_blast(get_parent(), at, element, SkillTrees.SHADOW_BLOOM_RADIUS)


## Vanishes at once, whatever state it is in (a boss's clones when it falls).
func dismiss() -> void:
	if state != State.DEFEATED:
		_dismissed = true
		stats.health = 0.0
		_on_died()


# --- Loop ----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if lifetime > 0.0 and state != State.DEFEATED:
		_life_left -= delta
		if _life_left <= 0.0:
			leave()
			return
		# A clone about to fade flickers.
		model.visible = _life_left > 1.5 or int(_life_left * 8.0) % 2 == 0
	_hint_timer -= delta
	if _hint_timer <= 0.0:
		_hint_timer = 0.5
		_update_hint()
	_state_time += delta
	_kunai_cd -= delta
	_jutsu_cd -= delta
	_melee_cd -= delta
	_rush -= delta
	_armor -= delta
	_guard_rest -= delta
	_engage -= delta
	_poise_rest += delta
	if _poise_rest >= POISE_REST:
		_poise = _max_poise

	match state:
		State.SPAWNING:
			_decelerate(delta)
			# Hidden in the smoke until the animator has posed it (a freshly
			# loaded model stands in a T-pose for its first frames).
			if model:
				model.visible = _state_time >= SPAWN_SHOW
			if _state_time >= SPAWN_TIME:
				_enter(State.FIGHT)
		State.FIGHT: _fight(delta)
		State.WEAVING: _weaving(delta)
		State.WINDUP: _windup(delta)
		State.AIMING: _aiming(delta)
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
			velocity.x = move_toward(velocity.x, 0.0, RECOIL_DRAG * delta)
			velocity.z = move_toward(velocity.z, 0.0, RECOIL_DRAG * delta)
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
		State.SPAWNING:
			# Out of the smoke, it can be locked on to (and hit).
			if not is_ally() and new_state != State.DEFEATED:
				add_to_group(&"lockable")
		State.GUARDING:
			stats.guard_multiplier = 1.0
			_guard_rest = GUARD_REST
		State.DODGING: stats.is_invulnerable = false
		State.WEAVING:
			_seal_label.text = ""
			_hide_danger()
		State.WINDUP, State.AIMING: _seal_label.text = ""
		State.STAGGERED:
			# Back on its feet: whole again, and not to be knocked down at once.
			_armor = ARMOR_TIME
			_poise = _max_poise
	state = new_state
	_state_time = 0.0
	_cued = false
	if new_state == State.GUARDING:
		stats.guard_multiplier = 0.3


func _target_ok() -> bool:
	if not is_instance_valid(target) or not target.is_inside_tree():
		return false
	if target.has_method("is_defeated") and target.is_defeated():
		return false
	return not (target.has_method("is_down") and target.is_down())


func _fight(delta: float) -> void:
	if not _target_ok() and hunt:
		target = pick_target()
	if not _target_ok():
		if clone_of != null:
			_follow_owner(delta)
		else:
			_decelerate(delta)
		return
	var to := target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var fwd := to / maxf(dist, 0.01)
	_face_target(delta)

	if _recoil > 0.0:
		# Rocked by a blow: sliding back, not deciding anything yet.
		_recoil -= delta
		velocity.x = move_toward(velocity.x, 0.0, RECOIL_DRAG * delta)
		velocity.z = move_toward(velocity.z, 0.0, RECOIL_DRAG * delta)
		return
	if _incoming_projectile() and randf() < float(_r["dodge"]):
		_dodge()
		return

	# Hold a preferred distance and circle; close in when rushing.
	var desired: float = 1.4 if _rush > 0.0 else float(_r["range"]) * _range_bias
	var side := fwd.cross(Vector3.UP) * _strafe_sign
	var dir := side * 0.7
	if _rush > 0.0 and dist > RUSH_STRIKE_RANGE - 0.3:
		# Straight in until it is close enough to swing.
		dir = fwd
	elif dist > desired + 1.5:
		dir = fwd + side * 0.2
	elif dist < desired - 1.5:
		dir = -fwd * 0.8 + side * 0.5
	dir += _separation() + _spacing(fwd)
	if global_position.length() > ARENA_RADIUS:
		dir += -Vector3(global_position.x, 0, global_position.z).normalized()
	var speed: float = _r["run"] * (1.15 if _rush > 0.0 else 1.0)
	_move(dir.limit_length(1.0) * speed, delta)

	if dist < RUSH_STRIKE_RANGE and _melee_cd <= 0.0 and not drill:
		if _rush > 0.0 or AttackTokens.may_attack(self, true):
			_start_windup()
			return
		# Somebody else has the blow: give them room.
		_rush = 0.0
	_think -= delta
	if _think > 0.0:
		return
	var span: Vector2 = _r["think"]
	_think = randf_range(span.x, span.y)
	if _rush > 0.0:
		# Running in: nothing else on its mind.
		return
	if hunt and randf() < 0.35:
		var better := pick_target()
		if better:
			target = better
			return
	if randf() < 0.3:
		_strafe_sign = -_strafe_sign
	if drill:
		if _jutsu_cd <= 0.0 and not jutsu_list.is_empty():
			_start_weave(jutsu_list[0])
		return
	if _jutsu_cd <= 0.0:
		var j := _pick_jutsu(dist)
		if j and AttackTokens.may_attack(self, false):
			_start_weave(j)
			return
	if _kunai_cd <= 0.0 and dist > 3.5 and dist < 26.0 and AttackTokens.may_attack(self, false):
		_start_aim()
	elif _engage <= 0.0 and _rush <= 0.0 and _melee_cd <= 0.0 and dist > 3.0:
		# Time to stop plinking and fight up close, if it's this one's turn.
		if AttackTokens.may_attack(self, true):
			_rush = RUSH_TIME
			var engage: Vector2 = _r["engage"]
			_engage = randf_range(engage.x, engage.y)
		else:
			_engage = 0.6


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
	_attack_frame = Engine.get_physics_frames()
	_enter(State.WEAVING)
	_seal_label.modulate = Element.color(element).lightened(0.25)
	_seal_label.text = "印"
	Sfx.play_at(&"weave_start", global_position)
	if j.form == JutsuDefinition.Form.AREA:
		_show_danger(j)


func _weaving(delta: float) -> void:
	_decelerate(delta)
	_face_target(delta)
	_update_danger()
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
		if caster.cast(_tamed_jutsu(_weave), target) and model.animator:
			model.animator.cast()
	var span: Vector2 = _r["jutsu_cd"]
	_jutsu_cd = randf_range(span.x, span.y)
	_enter(State.FIGHT)


## Stops and glints, arm drawn back: the cue to move before the kunai leaves.
func _start_aim() -> void:
	_attack_frame = Engine.get_physics_frames()
	_enter(State.AIMING)
	_seal_label.modulate = AIM_COLOR
	_seal_label.text = "投"
	_flare_ring(AIM_COLOR, 0.8)
	Vfx.flash(get_parent(), global_position + Vector3.UP * 1.3 - global_basis.z * 0.4, AIM_COLOR, 0.9 * size, 0.22)
	Sfx.play_at(&"dash", global_position + Vector3.UP, -9.0)


func _aiming(delta: float) -> void:
	_decelerate(delta)
	_face_target(delta)
	var aim: float = _r["aim"]
	# The arm cocks just before it lets go, so the whip is the release.
	if not _cued and _state_time >= aim - THROW_CUE:
		_cued = true
		if model.animator:
			model.animator.throw()
	if _state_time < aim:
		return
	if _target_ok():
		_throw_kunai()
	_enter(State.FIGHT)


func _throw_kunai() -> void:
	_face_now(target.global_position - global_position)
	caster.cast(_kunai, target)
	var span: Vector2 = _r["kunai_cd"]
	_kunai_cd = randf_range(span.x, span.y)


func _start_windup() -> void:
	_rush = 0.0
	_combo = 0
	_attack_frame = Engine.get_physics_frames()
	_flare_ring(UiKit.CRIMSON.lightened(0.15), 1.25)
	Vfx.flash(get_parent(), global_position + Vector3.UP * 1.2, UiKit.CRIMSON.lightened(0.3), 1.0 * size, 0.2)
	_enter(State.WINDUP)
	_seal_label.modulate = UiKit.CRIMSON.lightened(0.2)
	_seal_label.text = "!"


func _windup(delta: float) -> void:
	_decelerate(delta)
	_face_target(delta)
	var windup: float = _r["windup"] * (1.0 if _combo == 0 else COMBO_FOLLOW)
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
	Vfx.slash(get_parent(), Transform3D(global_basis, global_position + Vector3.UP * 1.1),
		Element.color(element), 1.9 * size, randf_range(-0.7, 0.7))
	var landed := false
	for victim in Combat.hittables_in_sphere(get_world_3d(), center, 0.9, [get_rid()]):
		if Combat.apply_hit(victim, _r["melee"], Element.NONE, self) > 0.0:
			landed = true
			var at := (victim as Node3D).global_position + Vector3.UP * 1.1 - forward * 0.4 if victim is Node3D else center
			Vfx.hit_spark(get_parent(), at, Element.color(element), 1.0, forward)
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
		if p == null or not is_instance_valid(p.caster) or p.caster == self or Combat.same_team(p.caster, self):
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


## Slides sideways, around the target, away from a teammate that stands on
## nearly the same bearing, so a crowd fans out instead of queueing in a line.
## `fwd` points at the target.
func _spacing(fwd: Vector3) -> Vector3:
	var push := Vector3.ZERO
	var side := fwd.cross(Vector3.UP)
	for node in get_tree().get_nodes_in_group(team):
		var other := node as EnemyShinobi
		if other == null or other == self or other.target != target or other.state == State.DEFEATED:
			continue
		var mine := global_position - target.global_position
		var theirs := other.global_position - target.global_position
		mine.y = 0.0
		theirs.y = 0.0
		if mine.length() < 0.5 or theirs.length() < 0.5:
			continue
		var gap := mine.angle_to(theirs)
		if gap >= SPREAD_ANGLE:
			continue
		# Which side of me they stand on, along my circling direction.
		var lateral := (other.global_position - global_position).dot(side)
		var share := 1.0 - gap / SPREAD_ANGLE
		push += side * (-signf(lateral) if absf(lateral) > 0.05 else _strafe_sign) * share
	return push


# --- Taking hits -------------------------------------------------------------------

func take_hit(amount: float, hit_element: int, source: Node) -> float:
	if state == State.SPAWNING or state == State.DEFEATED:
		return 0.0
	var dealt := stats.take_damage(amount, hit_element)
	if dealt <= 0.0 or stats.is_dead():
		return dealt
	var interrupt: float = _r["interrupt"]
	_poise_rest = 0.0
	if state == State.WEAVING and dealt >= interrupt:
		_interrupted()
		interrupted.emit(source)
		if source is Player:
			(source as Player).gain_ultimate(Ultimates.PER_INTERRUPT)
		return dealt
	var reeling := _armor > 0.0 or state == State.STAGGERED
	if not reeling:
		_poise -= dealt
	var committed := state == State.WINDUP or state == State.AIMING
	if dealt >= interrupt * 2.5 or (not reeling and (_poise <= 0.0 or (committed and dealt >= interrupt * 1.5))):
		_stagger(source)
	elif state == State.FIGHT and source is Player and _guard_rest <= 0.0 and randf() < float(_r["guard"]):
		_enter(State.GUARDING)
		Sfx.play_at(&"guard", global_position + Vector3.UP, -3.0)
	elif state != State.GUARDING:
		_recoil_from(dealt, source)
	return dealt


func _interrupted() -> void:
	_pop("Interrupted!", UiKit.GOLD, 40)
	Sfx.play_at(&"seal_break", global_position + Vector3.UP)
	_jutsu_cd = maxf(_jutsu_cd, 1.5)
	_stagger()


## A blow too light to stagger still rocks the fighter: it slides back and
## leans away (whatever the model, with or without a hit clip), and between
## moves it loses its own for a beat. A fighter in the middle of an attack or
## guarding is nudged, not stopped.
func _recoil_from(dealt: float, source: Node) -> void:
	var push := clampf(dealt * RECOIL_PUSH, RECOIL_PUSH_RANGE.x, RECOIL_PUSH_RANGE.y)
	var away := _away_from(source)
	if state == State.FIGHT:
		_recoil = RECOIL_TIME
		_rush = 0.0
		velocity.x = away.x * push
		velocity.z = away.z * push
	else:
		velocity += away * push * 0.4
	_lean_back(dealt)


## Flat direction from `source` to this fighter (straight back if unknown).
func _away_from(source: Node) -> Vector3:
	var away := global_basis.z
	if source is Node3D and is_instance_valid(source):
		away = global_position - (source as Node3D).global_position
	elif _target_ok():
		away = global_position - target.global_position
	away.y = 0.0
	return away.normalized() if away.length() > 0.01 else global_basis.z


## The body tips back from the blow and rights itself.
func _lean_back(dealt: float) -> void:
	if model == null or state == State.DEFEATED:
		return
	if _lean:
		_lean.kill()
	model.rotation.x = clampf(0.1 + dealt * 0.015, 0.12, 0.3)
	_lean = create_tween()
	_lean.tween_property(model, "rotation:x", 0.0, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Knocked off balance by something other than a hit (Opening Flash).
func stagger() -> void:
	if state in [State.SPAWNING, State.DEFEATED]:
		return
	if state == State.WEAVING:
		_interrupted()
	else:
		_stagger()


func _stagger(source: Node = null) -> void:
	_rush = 0.0
	_recoil = 0.0
	_poise = _max_poise
	_enter(State.STAGGERED)
	if model.animator:
		model.animator.hit(true)
	_lean_back(12.0)
	var away := _away_from(source)
	velocity.x = away.x * STAGGER_PUSH
	velocity.z = away.z * STAGGER_PUSH


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
			Vfx.smoke_puff(get_parent(), global_position + Vector3.UP, 1.1 * size)
			global_position += hop
			Sfx.play_at(&"smoke", global_position)
		phase_reached.emit(phase)


func _on_damaged(amount: float, hit_element: int, multiplier: float) -> void:
	_check_phases.call_deferred()
	if model.animator and state != State.GUARDING and state != State.STAGGERED and not stats.is_dead():
		model.animator.hit()
	var text := str(roundi(amount))
	if multiplier > 1.0:
		text += "  WEAK!"
		Sfx.play_at(&"weak_hit", global_position + Vector3.UP * 1.5)
	elif multiplier < 1.0:
		text += "  RESIST"
	_pop(text, Element.color(hit_element).lightened(0.2), 52 if multiplier > 1.0 else 40)


func _on_died() -> void:
	_bloom()
	if not is_ally() and clone_of == null and not _dismissed:
		Game.add_xp(SkillTrees.enemy_xp(rank, is_boss()), "boss" if is_boss() else String(rank))
	_enter(State.DEFEATED)
	remove_from_group(&"lockable")
	remove_from_group(team)
	collision_layer = 0
	_seal_label.text = ""
	_name_label.visible = false
	_bar.visible = false
	var puff := global_position + Vector3.UP
	Vfx.smoke_puff(get_parent(), puff, 1.3 * size)
	Vfx.flash(get_parent(), puff, Element.color(element).lightened(0.4), 2.2 * size, 0.2)
	Vfx.sparks(get_parent(), puff, Element.color(element), 14, 6.0)
	Sfx.play_at(&"smoke", puff)
	Sfx.play_at(&"enemy_down", puff, -2.0)
	defeated.emit(self)
	await get_tree().create_timer(0.12).timeout
	model.visible = false
	await get_tree().create_timer(0.8).timeout
	queue_free()


# --- Attack tells ----------------------------------------------------------------

## True while an attack is under way: weaving, aiming a throw or winding up.
func is_attacking() -> bool:
	return state == State.WEAVING or state == State.WINDUP or state == State.AIMING


## True while closing in for a blow: running at the target or winding up.
func is_closing_in() -> bool:
	return state == State.WINDUP or _rush > 0.0


## Seconds since this fighter last began an attack (INF if it never has).
func since_attack_began() -> float:
	if _attack_frame < 0:
		return INF
	return float(Engine.get_physics_frames() - _attack_frame) / float(Engine.physics_ticks_per_second)


## `j` as this fighter casts it: fast shots home less, so a dash sideways
## still beats them once they've left.
func _tamed_jutsu(j: JutsuDefinition) -> JutsuDefinition:
	if is_ally() or j.form != JutsuDefinition.Form.PROJECTILE or j.speed <= 0.0:
		return j
	var cap := clampf(HOMING_SPEED / j.speed, HOMING_CAP_RANGE.x, HOMING_CAP_RANGE.y)
	if j.homing <= cap:
		return j
	if not _tamed.has(j.id):
		var copy := j.duplicate() as JutsuDefinition
		copy.homing = cap
		_tamed[j.id] = copy
	return _tamed[j.id]


## Flares the ground disc under the fighter in `color`, `grow` times its size,
## then lets it settle back to its nature's glow.
func _flare_ring(color: Color, grow: float) -> void:
	if _ring == null:
		return
	var m := _ring.material_override as StandardMaterial3D
	if _flare:
		_flare.kill()
	m.albedo_color = Color(color, 1.0)
	_ring.scale = Vector3.ONE * grow
	_flare = create_tween().set_parallel(true)
	_flare.tween_property(m, "albedo_color", Color(Element.color(element), 0.75), 0.45).set_delay(0.2)
	_flare.tween_property(_ring, "scale", Vector3.ONE, 0.45).set_delay(0.2)


## A quad lying on the ground that stays where it is put (not turning with
## the fighter).
func _ground_disc(texture: StringName, additive: bool) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	quad.orientation = PlaneMesh.FACE_Y
	var disc := MeshInstance3D.new()
	disc.mesh = quad
	disc.material_override = Vfx.surface_material(Vfx.tex(texture), additive)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.top_level = true
	add_child(disc)
	return disc


## Marks the ground an area jutsu will hit, and fills in as the seals come.
func _show_danger(j: JutsuDefinition) -> void:
	_danger_jutsu = j
	if _danger == null:
		_danger = _ground_disc(&"glow", true)
		_danger_edge = _ground_disc(&"ring", false)
	_danger.visible = true
	_danger_edge.visible = true
	_update_danger()


func _hide_danger() -> void:
	_danger_jutsu = null
	if _danger:
		_danger.visible = false
		_danger_edge.visible = false


func _update_danger() -> void:
	if _danger_jutsu == null or _weave == null:
		return
	# Exactly where JutsuCaster will centre the blast.
	var forward := -global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var at := global_position + forward * _danger_jutsu.max_range
	at.y = Combat.ground_height(get_world_3d(), at, global_position.y) + 0.07
	var seals := float(_weave.seals.size())
	var seal_time := maxf(float(_r["seal_time"]), 0.01)
	var progress := clampf((float(_weave_index) + 1.0 - clampf(_seal_timer / seal_time, 0.0, 1.0)) / (seals + 1.0), 0.0, 1.0)
	var c := UiKit.CRIMSON.lerp(Element.color(element), 0.3).lightened(0.15)
	_danger.global_position = at
	_danger.scale = Vector3.ONE * _danger_jutsu.radius
	(_danger.material_override as StandardMaterial3D).albedo_color = Color(c, lerpf(0.1, 0.5, progress))
	_danger_edge.global_position = at + Vector3.UP * 0.01
	_danger_edge.scale = Vector3.ONE * _danger_jutsu.radius
	(_danger_edge.material_override as StandardMaterial3D).albedo_color = Color(c.lightened(0.2), lerpf(0.45, 1.0, progress))


# --- Presentation ------------------------------------------------------------------

func _build_overhead() -> void:
	var c := Element.color(element)
	_ring = MeshInstance3D.new()
	var disc := QuadMesh.new()
	disc.size = Vector2(1.8, 1.8) * size
	disc.orientation = PlaneMesh.FACE_Y
	_ring.mesh = disc
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.material_override = _ring_material(c)
	_ring.position.y = 0.03
	add_child(_ring)

	_name_label = _label3d(label_text(), 30, c.lightened(0.35))
	_name_label.position.y = 2.35 * size
	add_child(_name_label)

	# Hawk Eye: who is weak to you, at a glance.
	_hint_label = _label3d("", 36, Color("e3a23a"))
	_hint_label.position.y = 2.65 * size
	_hint_label.visible = false
	add_child(_hint_label)

	_bar_image = Image.create(BAR_SIZE.x, BAR_SIZE.y, false, Image.FORMAT_RGBA8)
	_bar = Sprite3D.new()
	_bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bar.no_depth_test = true
	_bar.pixel_size = 0.009
	_bar.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_bar.position.y = 2.05 * size
	_bar.texture = ImageTexture.create_from_image(_bar_image)
	add_child(_bar)
	_draw_bar()

	_seal_label = _label3d("", 64, c)
	_seal_label.position.y = 2.85 * size
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
		_bar_image.fill_rect(Rect2i(2, 2, fill, BAR_SIZE.y - 4),
			Color("5fbf6a") if is_ally() else UiKit.HEALTH.lightened(0.15))
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
