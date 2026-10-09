class_name VfxWarmup
extends SubViewport
## Sets off every jutsu's effects once, out of sight, while the title is up.
##
## The first time a material is drawn the graphics driver compiles its
## shader, and the game stood still for that: a freeze on each jutsu's first
## cast. Here each element's projectile, impact, blast, wall and aura (and
## the strikes, sparks and smoke every fight uses) are drawn in a small
## viewport of their own that nobody sees, a group at a time so the title
## stays responsive. Sounds are held off meanwhile.

signal finished

## How long each group of effects plays (long enough for the parts that
## start late, like a blast's second ring).
const HOLD_TIME := 0.45
const ELEMENTS := [Element.NONE, Element.FIRE, Element.WIND, Element.LIGHTNING, Element.EARTH, Element.WATER]

## Done this session: every shader it covers is compiled.
static var done := false

var _groups: Array[Callable] = []
var _holder: Node3D
var _hold := 0.0


## Only where something is really drawn (not headless, not already done).
static func wanted() -> bool:
	return not done and DisplayServer.get_name() != "headless"


func _ready() -> void:
	name = "VfxWarmup"
	own_world_3d = true
	size = Vector2i(256, 144)
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Drawn the way the game is, so the compiled variants are the ones it uses.
	var main := get_tree().root
	msaa_3d = main.msaa_3d
	screen_space_aa = main.screen_space_aa
	use_taa = main.use_taa
	use_debanding = main.use_debanding
	scaling_3d_mode = main.scaling_3d_mode
	var world := main.find_world_3d()
	if world and world.environment:
		var env := WorldEnvironment.new()
		env.environment = world.environment
		add_child(env)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.rotation = Vector3(-0.9, 0.5, 0.0)
	add_child(sun)
	var camera := Camera3D.new()
	add_child(camera)
	camera.look_at_from_position(Vector3(0, 1.6, 7.5), Vector3(0, 0.8, 0))
	camera.current = true

	for element: int in ELEMENTS:
		_groups.append(_element.bind(element))
	_groups.append(_combat)
	Sfx.world_muted = true


func _exit_tree() -> void:
	Sfx.world_muted = false


func _process(delta: float) -> void:
	_hold -= delta
	if _hold > 0.0:
		return
	if _holder:
		_holder.queue_free()
		_holder = null
	if _groups.is_empty():
		done = true
		finished.emit()
		queue_free()
		return
	_holder = Node3D.new()
	add_child(_holder)
	(_groups.pop_front() as Callable).call(_holder)
	_hold = HOLD_TIME


## One nature's jutsu: in flight (and as a blade wave), landing, as an area,
## a wall and an aura.
func _element(holder: Node3D, element: int) -> void:
	_projectile(holder, element, &"", Vector3(-2.5, 1.2, 0))
	_projectile(holder, element, &"crescent", Vector3(-2.5, 2.4, -1))
	Vfx.impact(holder, Vector3(0, 1.2, 0), element)
	Vfx.area_blast(holder, Vector3(2.5, 0.5, 0), element, 2.5)
	Vfx.flash(holder, Vector3(0, 1.5, 1.5), Element.color(element).lightened(0.4), 1.3, 0.16, &"glow")
	var aura := Vfx.aura(element, HOLD_TIME * 2.0)
	aura.position = Vector3(-1.5, 0, -1.5)
	holder.add_child(aura)
	var wall := JutsuWall.new()
	wall.element = element
	wall.half_width = 1.5
	wall.duration = HOLD_TIME
	wall.position = Vector3(0, 0, -3)
	holder.add_child(wall)


## What every fight shows: kunai, strikes, sparks, smoke, healing and the
## chakra auras.
func _combat(holder: Node3D) -> void:
	var steel := Color(1.0, 0.9, 0.7)
	_projectile(holder, Element.NONE, &"kunai", Vector3(-2.5, 1.2, 0))
	Vfx.slash(holder, Transform3D(Basis.IDENTITY, Vector3(0, 1.2, 1)), steel)
	Vfx.hit_spark(holder, Vector3(1, 1.2, 1))
	Vfx.blade_sparks(holder, Vector3(-1, 1.2, 1), Vector3.UP)
	Vfx.kunai_hit(holder, Vector3(0, 1, 2), Vector3.FORWARD)
	Vfx.smoke_puff(holder, Vector3(0, 1, 0))
	Vfx.dust(holder, Vector3(0, 0.2, 0))
	Vfx.debris(holder, Vector3(0, 0.3, 0), Color(0.5, 0.45, 0.4))
	Vfx.shockwave(holder, Vector3(0, 0.1, 0), steel)
	Vfx.ground_mark(holder, Vector3(0, 0.05, 1), steel)
	Vfx.bolt(holder, Vector3(-2, 2, 0), Vector3(2, 0.5, 0), Element.color(Element.LIGHTNING))
	Vfx.heal(holder, Vector3(-2, 0, -1))
	holder.add_child(Vfx.charge_aura(Color(0.5, 0.7, 1.0)))
	var boss := Vfx.boss_aura(Color(0.8, 0.2, 0.2))
	boss.position = Vector3(2, 0, -1)
	holder.add_child(boss)


## A projectile that hangs where it's put (it never flies into anything).
func _projectile(holder: Node3D, element: int, style: StringName, at: Vector3) -> void:
	var p := JutsuProjectile.new()
	p.element = element
	p.style = style
	p.speed = 0.0
	p.radius = 0.35
	p.direction = Vector3.LEFT
	p.position = at
	holder.add_child(p)
	# Not a real one: nothing should try to dodge or swallow it.
	p.remove_from_group(&"projectiles")
