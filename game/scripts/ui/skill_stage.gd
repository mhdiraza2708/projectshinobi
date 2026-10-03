class_name SkillStage
extends SubViewport
## The 3D half of the skill screen: your own shinobi on a dark stage, a
## brushed enso glowing behind them in the tree's colour, embers drifting up.
## Each tree has its stance (guard for the Body, gathering chakra for Chakra,
## a seal for the Mind, cutting the air for Kenjutsu) and its camera; the
## Dojutsu tree pushes in on the face and opens your dojutsu in the irises.

const ENSO := preload("res://assets/shaders/skill_enso.gdshader")

## Per tree: the stance, and where the camera sits and looks.
const SHOTS := {
	"body": {"pose": HumanoidPoser.Pose.GUARD, "cam": Vector3(0.0, 1.05, 3.5), "look": Vector3(0.0, 0.95, 0.0), "fov": 34.0},
	"chakra": {"pose": HumanoidPoser.Pose.CHARGE, "cam": Vector3(0.35, 0.95, 3.4), "look": Vector3(0.0, 0.9, 0.0), "fov": 36.0},
	"mind": {"pose": HumanoidPoser.Pose.WEAVE, "cam": Vector3(-0.3, 1.2, 3.0), "look": Vector3(0.0, 1.05, 0.0), "fov": 34.0},
	"kenjutsu": {"pose": HumanoidPoser.Pose.LOCOMOTION, "cam": Vector3(0.7, 0.85, 3.1), "look": Vector3(0.0, 1.0, 0.0), "fov": 38.0},
	"eye": {"pose": HumanoidPoser.Pose.LOCOMOTION, "cam": Vector3(0.0, 1.5, 1.15), "look": Vector3(0.0, 1.47, 0.0), "fov": 30.0},
}
## Where the character stands in frame: the camera is shifted right so they
## stand left of centre, beside the tree.
const H_OFFSET := 0.95
const EYE_H_OFFSET := 0.28

var model: CharacterModel
var camera: Camera3D
var tree_id := "body"

var _enso: MeshInstance3D
var _rim: SpotLight3D
var _embers: CPUParticles3D
var _floor_ring: MeshInstance3D
var _move: Tween
var _time := 0.0
var _eye: ShaderMaterial
## Kenjutsu: seconds to the next cut, and which cut of the combo it is.
var _cut_left := 0.6
var _cut := 0
## Where a camera move starts.
var _from := Transform3D.IDENTITY


func _init() -> void:
	own_world_3d = true
	transparent_bg = false
	msaa_3d = Viewport.MSAA_2X
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("121016")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("3a3440")
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color("1a161e")
	env.fog_density = 0.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-28.0), deg_to_rad(28.0), 0.0)
	key.light_energy = 1.1
	key.light_color = Color("f3e6d4")
	key.shadow_enabled = true
	add_child(key)
	_rim = SpotLight3D.new()
	_rim.position = Vector3(0.0, 2.6, -2.2)
	_rim.spot_range = 7.0
	_rim.spot_angle = 50.0
	_rim.light_energy = 9.0
	add_child(_rim)
	_rim.look_at(Vector3(0.0, 1.0, 0.0))
	var fill := OmniLight3D.new()
	fill.position = Vector3(1.6, 1.4, 2.2)
	fill.omni_range = 6.0
	fill.light_energy = 0.35
	fill.light_color = Color("9fb3d9")
	add_child(fill)

	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = 6.0
	floor_mesh.bottom_radius = 6.0
	floor_mesh.height = 0.05
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color("1c1920")
	floor_mat.roughness = 0.35
	floor_mat.metallic_specular = 0.6
	var ground := MeshInstance3D.new()
	ground.mesh = floor_mesh
	ground.material_override = floor_mat
	ground.position.y = -0.025
	add_child(ground)

	_enso = _ring(Vector3(0.0, 1.25, -1.8), 3.2, 0.4, 0.035, Vector3.ZERO)
	_floor_ring = _ring(Vector3(0.0, 0.01, 0.0), 2.4, 0.42, 0.02, Vector3(-PI / 2.0, 0.0, 0.0))

	_embers = CPUParticles3D.new()
	_embers.amount = 60
	_embers.lifetime = 4.0
	_embers.preprocess = 4.0
	_embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_embers.emission_box_extents = Vector3(2.2, 0.2, 1.2)
	_embers.position = Vector3(0.0, 0.1, -0.6)
	_embers.direction = Vector3.UP
	_embers.spread = 18.0
	_embers.gravity = Vector3(0.0, 0.25, 0.0)
	_embers.initial_velocity_min = 0.2
	_embers.initial_velocity_max = 0.6
	_embers.scale_amount_min = 0.5
	_embers.scale_amount_max = 1.2
	var quad := QuadMesh.new()
	quad.size = Vector2(0.025, 0.025)
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	em.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	em.vertex_color_use_as_albedo = true
	quad.material = em
	_embers.mesh = quad
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.0))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	fade.add_point(0.2, Color(1, 1, 1, 0.9))
	_embers.color_ramp = fade
	add_child(_embers)

	model = CharacterModel.new()
	model.use_profile = true
	model.model_loaded.connect(func() -> void:
		_eye = null
		_pose(false))
	add_child(model)
	model.rotation.y = PI + deg_to_rad(12.0)

	camera = Camera3D.new()
	camera.current = true
	add_child(camera)
	show_tree(tree_id, false)


func _ring(at: Vector3, size_m: float, radius: float, width: float, rot: Vector3) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(size_m, size_m)
	var mat := ShaderMaterial.new()
	mat.shader = ENSO
	mat.set_shader_parameter(&"noise", load("res://assets/vfx/noise.png"))
	mat.set_shader_parameter(&"radius", radius)
	mat.set_shader_parameter(&"width", width)
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = mat
	mi.position = at
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Moves to a tree: its colour, its stance, its camera.
func show_tree(id: String, animate := true) -> void:
	tree_id = id
	var t := SkillTrees.tree(id)
	var c := Color(str(t.get("color", "#c8553d")))
	for ring in [_enso, _floor_ring]:
		var mat := ring.material_override as ShaderMaterial
		mat.set_shader_parameter(&"color", c)
		# The close-up on the eyes has the ring right behind the face: dimmer.
		var energy := 1.1 if ring == _enso else 0.6
		if id == "eye":
			energy *= 0.4
		mat.set_shader_parameter(&"energy", energy)
	_rim.light_color = c.lightened(0.15)
	_embers.color = c.lightened(0.35)
	var shot: Dictionary = SHOTS.get(id, SHOTS["body"])
	var offset := EYE_H_OFFSET if id == "eye" else H_OFFSET
	if _move and _move.is_valid():
		_move.kill()
	if animate and is_inside_tree():
		_move = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		_move.tween_method(_frame.bind(shot), 0.0, 1.0, 0.6)
		_move.tween_property(camera, "h_offset", offset, 0.6)
		_move.tween_property(camera, "fov", float(shot["fov"]), 0.6)
		_from = camera.global_transform
	else:
		camera.h_offset = offset
		camera.fov = float(shot["fov"])
		camera.position = shot["cam"]
		camera.look_at(shot["look"])
	_pose(animate)



func _frame(k: float, shot: Dictionary) -> void:
	var to := Transform3D(Basis.IDENTITY, shot["cam"]).looking_at(shot["look"])
	camera.global_transform = _from.interpolate_with(to, k)


func _pose(_animate: bool) -> void:
	if model == null or model.animator == null:
		return
	var shot: Dictionary = SHOTS.get(tree_id, SHOTS["body"])
	model.animator.pose = shot["pose"]
	model.animator.speed_ratio = 0.0
	if tree_id == "mind" or tree_id == "chakra":
		model.animator.seal_flick()
	# The Eye tree opens your eye art in the irises.
	var art := Perks.active_eye_art()
	if tree_id == "eye" and not art.is_empty():
		if _eye == null:
			_eye = EyePattern.attach(model, art)
		if _eye:
			_eye.set_shader_parameter(&"intensity", 1.0)
			_eye.set_shader_parameter(&"awakened", 1.0 if EyeArtMode.awakening_unlocked() else 0.0)
	elif _eye:
		EyePattern.detach(model)
		_eye = null


func _process(delta: float) -> void:
	_time += delta
	# A slow breath of camera movement, so the stage feels alive.
	if (_move == null or not _move.is_valid()) and camera:
		var shot: Dictionary = SHOTS.get(tree_id, SHOTS["body"])
		var sway := Vector3(sin(_time * 0.35) * 0.06, sin(_time * 0.5) * 0.02, 0.0)
		camera.position = (shot["cam"] as Vector3) + sway
		camera.look_at(shot["look"])
	if model:
		model.rotation.y = PI + deg_to_rad(12.0 + sin(_time * 0.25) * 4.0)
		if tree_id == "kenjutsu":
			_cut_left -= delta
			if _cut_left <= 0.0:
				_cut_left = 0.45 if _cut < 2 else 1.6
				_cut = (_cut + 1) % 3
				_swing()


## One cut of a three-cut combo in the air, with the blade's arc.
func _swing() -> void:
	if model.animator:
		model.animator.strike(_cut)
	var facing := model.global_basis.z
	facing.y = 0.0
	var origin := Transform3D(Basis.looking_at(-facing.normalized(), Vector3.UP), model.global_position + Vector3.UP * 1.1)
	var c := Color(str(SkillTrees.tree("kenjutsu").get("color", "#8fa7bf"))).lightened(0.3)
	Vfx.slash(self, origin, c, 2.0, [0.7, -0.7, 1.35][_cut])
	if _cut == 2:
		Vfx.slash(self, origin, Color(1, 1, 1), 2.6, 1.35, 0.3)
