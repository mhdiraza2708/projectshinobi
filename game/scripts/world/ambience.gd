class_name Ambience
extends Node3D
## Life in the air around the player: embers and ash drifting over the Ashen
## Pass, red maple leaves falling in Autumn Wood, light snow on the Frozen
## Road, fine mist by Old Dam's water, wind streaks across Five Winds, pollen
## and petals in Emberwood by day, and a few fireflies near the ground on any
## island at night.
##
## The particles fill a box around the player that moves with them (each
## stays where it was born, so nothing travels along with you), which takes
## only a few hundred in all, from one or two emitters. A change of island,
## hour or weather fades the old set out and the new one in. Lower graphics
## presets get fewer, and the lowest none. The game scene feeds it the
## island, the hour and the weather (set_context), so it serves free roam and
## a story chapter on a single island alike.

## What drifts through each island's air. Two kinds at most; the second gives
## way to the fireflies at night.
const SETS := {
	"ashen_pass": ["embers", "ash"],
	"autumn_wood": ["leaves"],
	"frozen_road": ["snow"],
	"old_dam": ["mist"],
	"five_winds": ["wind"],
	"emberwood": ["pollen", "petals"],
}
## Kinds that belong to daylight.
const BY_DAY: PackedStringArray = ["pollen", "petals"]
## Fireflies' colour where it isn't the usual yellow-green.
const FIREFLY_COLORS := {"ashen_pass": Color(1.0, 0.62, 0.25), "frozen_road": Color(0.7, 0.9, 1.0)}
## How each hour's light colours the particles that are lit (the glowing ones
## keep their colour).
const LIGHT := {
	"dawn": Color(1.0, 0.88, 0.94),
	"day": Color(1.0, 1.0, 1.0),
	"dusk": Color(1.0, 0.78, 0.56),
	"night": Color(0.28, 0.36, 0.62),
}
## Seconds a set takes to fade in or out, and for the light's colour to ease.
const FADE := 1.6
const LIGHT_EASE := 1.5
## Half the width of the box the particles fill, in metres.
const RADIUS := 11.0
## The box leads the player by this many seconds of their running, so there
## is air ahead of you as well as around you.
const LEAD_TIME := 0.8
## Further than this in a frame is a jump (a teleport, a respawn, the world
## shifting under a chapter), not running: the particles start over.
const JUMP := 30.0
## Outlines (across, along; one metre long) of the flat shapes that tumble down.
const LEAF: Array[Vector2] = [Vector2(0, 0.5), Vector2(-0.18, 0.28), Vector2(-0.3, 0.05), Vector2(-0.2, -0.22),
	Vector2(0, -0.5), Vector2(0.2, -0.22), Vector2(0.3, 0.05), Vector2(0.18, 0.28)]
const PETAL: Array[Vector2] = [Vector2(0, 0.5), Vector2(-0.3, 0.25), Vector2(-0.4, -0.1), Vector2(-0.2, -0.4),
	Vector2(0, -0.5), Vector2(0.2, -0.4), Vector2(0.4, -0.1), Vector2(0.3, 0.25)]
const FLAKE: Array[Vector2] = [Vector2(-0.4, 0.3), Vector2(0.1, 0.5), Vector2(0.45, 0.1), Vector2(0.3, -0.4),
	Vector2(-0.2, -0.5), Vector2(-0.5, -0.1)]

## What the air is around, set by the game scene (see set_context).
var follow: Node3D
var island := ""
var time_of_day := "day"
var weather := "none"

static var _dot_texture: Texture2D

var _emitters: Array[Emitter] = []
var _wanted := PackedStringArray()
var _density := 0.0
var _dirty := true
var _light := Color.WHITE
var _placed := false
var _last := Vector3.ZERO
var _lead := Vector3.ZERO
var _ground := 0.0


## One set of particles and how far it has faded in (or out, once its target
## is 0 it frees itself).
class Emitter:
	var kind := ""
	var island := ""
	var density := 1.0
	var node: CPUParticles3D
	var material: BaseMaterial3D
	var lit := true
	var fade := 0.0
	var target := 1.0
	var shown := Color(0, 0, 0, -1)


func _init() -> void:
	name = "Ambience"


func _ready() -> void:
	Settings.value_changed.connect(_on_setting_changed)


## A graphics option may have changed how much air to fill.
func _on_setting_changed(_key: StringName, _value: Variant) -> void:
	_dirty = true


## The kinds of particles in the air of an island at a time of day (dawn, day,
## dusk or night) in a weather. Rain and storms bring their own, snow and
## falling leaves stand in for the island's own.
static func kinds(island_id: String, time: String, weather_kind := "none") -> PackedStringArray:
	var out := PackedStringArray()
	if not SETS.has(island_id) or weather_kind in ["rain", "storm"]:
		return out
	for kind: String in SETS[island_id]:
		if (kind == "snow" and weather_kind == "snow") or (kind == "leaves" and weather_kind == "leaves"):
			continue
		if time == "night" and BY_DAY.has(kind):
			continue
		if time == "night" and not out.is_empty():
			break
		out.append(kind)
	if time == "night" and weather_kind != "snow":
		out.append("fireflies")
	return out


## How much of the air to fill at the current graphics settings: none on the
## Low preset, a little less than all on the plainer lighting, all above.
static func density() -> float:
	if Graphics.matching_preset() == "low":
		return 0.0
	return 0.75 if Graphics.level() == "standard" else 1.0


## Sets the island, the hour and the weather the air belongs to (the game
## scene calls this every frame; nothing happens unless something changed).
func set_context(island_id: String, time: String, weather_kind := "none") -> void:
	if island_id == island and time == time_of_day and weather_kind == weather and not _dirty:
		return
	island = island_id
	time_of_day = time
	weather = weather_kind
	_dirty = false
	_density = density()
	_wanted = kinds(island, time_of_day, weather) if _density > 0.0 else PackedStringArray()
	for e: Emitter in _emitters:
		var current := e.density == _density and e.island == island
		e.target = 1.0 if current and _wanted.has(e.kind) else 0.0
	for kind in _wanted:
		if not _emitters.any(func(e: Emitter) -> bool: return e.kind == kind and e.target > 0.0):
			_emitters.append(_spawn(kind))


## The kinds in the air now (those fading out aren't counted).
func active() -> PackedStringArray:
	var out := PackedStringArray()
	for e: Emitter in _emitters:
		if e.target > 0.0:
			out.append(e.kind)
	return out


## The emitter for a kind, or null.
func emitter(kind: String) -> CPUParticles3D:
	for e: Emitter in _emitters:
		if e.kind == kind and e.target > 0.0:
			return e.node
	return null


## Finishes every fade at once (screenshots, tests).
func settle() -> void:
	_light = LIGHT.get(time_of_day, Color.WHITE)
	for e: Emitter in _emitters.duplicate():
		e.fade = e.target
		if e.target == 0.0:
			_drop(e)
		else:
			_paint(e)


func _process(delta: float) -> void:
	if follow == null or not is_instance_valid(follow) or not follow.is_inside_tree():
		return
	_track(delta)
	_light = _light.lerp(LIGHT.get(time_of_day, Color.WHITE), 1.0 - exp(-delta / LIGHT_EASE))
	for e: Emitter in _emitters.duplicate():
		e.fade = move_toward(e.fade, e.target, delta / FADE)
		if e.target == 0.0 and e.fade == 0.0:
			_drop(e)
		else:
			_paint(e)


# --- Following the player -------------------------------------------------------

## Keeps the box around the player, leading a little in the direction they
## run, and steady in height while they jump.
func _track(delta: float) -> void:
	var at := follow.global_position
	if not _placed:
		_snap()
		return
	if at.distance_to(_last) > JUMP:
		_snap()
		_refill()
		return
	var run := (at - _last) / maxf(delta, 0.0001)
	run.y = 0.0
	_last = at
	_lead = _lead.lerp(run * LEAD_TIME, 1.0 - exp(-delta / 0.6)).limit_length(RADIUS * 0.6)
	_ground = lerpf(_ground, at.y, 1.0 - exp(-delta))
	global_position = Vector3(at.x + _lead.x, _ground, at.z + _lead.z)


func _snap() -> void:
	if follow != null and is_instance_valid(follow) and follow.is_inside_tree():
		_last = follow.global_position
	elif is_inside_tree():
		_last = global_position
	_ground = _last.y
	_lead = Vector3.ZERO
	if is_inside_tree():
		global_position = _last
	else:
		position = _last
	_placed = true


## After a jump the particles are left far behind: start the sets again
## around the player.
func _refill() -> void:
	var old := _emitters.duplicate()
	_emitters.clear()
	for e: Emitter in old:
		e.node.free()
		if e.target > 0.0:
			var fresh := _spawn(e.kind)
			fresh.fade = e.fade
			_emitters.append(fresh)


# --- Emitters -------------------------------------------------------------------

func _spawn(kind: String) -> Emitter:
	if not _placed:
		_snap()
	var spec := _spec(kind, island)
	spec["amount"] = maxi(2, roundi(float(spec["amount"]) * _density))
	var p := Vfx.particles(spec)
	var box: Vector3 = spec["box"]
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = box
	p.position = Vector3(0.0, spec["y"], 0.0)
	# Flat shapes turn about the vertical as they fall.
	p.particle_flag_rotate_y = spec.has("mesh") and spec.has("spin")
	if spec.has("initial"):
		p.color_initial_ramp = spec["initial"]
	# Start as if it had been falling a while, so the air isn't empty.
	p.preprocess = p.lifetime
	var e := Emitter.new()
	e.kind = kind
	e.island = island
	e.density = _density
	e.node = p
	e.lit = spec.get("lit", true)
	# Each emitter fades on its own copy of the (shared) material.
	if p.mesh is PrimitiveMesh:
		e.material = ((p.mesh as PrimitiveMesh).material as BaseMaterial3D).duplicate()
		(p.mesh as PrimitiveMesh).material = e.material
	else:
		e.material = (p.mesh.surface_get_material(0) as BaseMaterial3D).duplicate()
		p.mesh.surface_set_material(0, e.material)
	if spec.get("dot", false):
		e.material.albedo_texture = _dot()
	# Fade out what drifts right past the lens (a leaf a hand's breadth from the
	# camera would fill the screen).
	var near: Array = spec.get("fade_from", [1.2, 3.5])
	e.material.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	e.material.distance_fade_min_distance = near[0]
	e.material.distance_fade_max_distance = near[1]
	add_child(p)
	_paint(e)
	return e


func _paint(e: Emitter) -> void:
	var c := _light if e.lit else Color.WHITE
	var now := Color(c.r, c.g, c.b, e.fade)
	if now.is_equal_approx(e.shown):
		return
	e.shown = now
	e.material.albedo_color = now
	e.node.visible = e.fade > 0.0


func _drop(e: Emitter) -> void:
	_emitters.erase(e)
	e.node.queue_free()


## How to make a kind, in the terms Vfx.particles takes, plus "box" (half
## extents of where they appear), "y" (that box's height above the player's
## feet), "lit" (the hour's light colours them), "initial" (a gradient each
## particle picks its colour from), "dot" (a crisp disc, not a soft glow) and
## "fade_from" ([gone, solid] metres from the camera). Counts are for the
## fullest setting.
static func _spec(kind: String, island_id := "") -> Dictionary:
	var steady := Vfx.curve([Vector2(0, 1), Vector2(1, 1)])
	match kind:
		"embers":
			return {"texture": &"glow", "additive": true, "amount": 56, "lifetime": 5.0, "size": [0.12, 0.22],
				"colors": Vfx.gradient([Color(1.0, 0.9, 0.5, 0.0), Color(1.0, 0.62, 0.2, 1.0),
					Color(0.95, 0.3, 0.08, 0.75), Color(0.45, 0.1, 0.05, 0.0)], [0.0, 0.08, 0.6, 1.0]),
				"speed": [0.2, 1.0], "direction": Vector3(0.4, 1.0, 0.15), "spread": 45.0,
				"gravity": Vector3(0.6, 0.45, 0.15), "damping": 0.15, "randomness": 0.6,
				"box": Vector3(RADIUS, 1.2, RADIUS), "y": 1.0, "lit": false}
		"ash":
			return {"mesh": _shape(FLAKE, 60.0), "amount": 90, "lifetime": 9.0, "size": [0.07, 0.13],
				"size_curve": steady, "spin": [-200.0, 200.0],
				"colors": Vfx.gradient([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.0)],
					[0.0, 0.1, 0.85, 1.0]),
				"initial": Vfx.gradient([Color(0.42, 0.4, 0.38), Color(0.7, 0.68, 0.64), Color(0.3, 0.29, 0.28)]),
				"speed": [0.1, 0.5], "direction": Vector3(0.6, -0.4, 0.2), "spread": 60.0,
				"gravity": Vector3(0.5, -0.6, 0.15), "damping": 0.8,
				"box": Vector3(RADIUS, 3.0, RADIUS), "y": 4.0}
		"leaves":
			return {"mesh": _shape(LEAF, 60.0), "amount": 120, "lifetime": 5.5, "size": [0.22, 0.38],
				"size_curve": steady, "spin": [-220.0, 220.0],
				"colors": Vfx.gradient([Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.0)],
					[0.0, 0.08, 0.85, 1.0]),
				"initial": Vfx.gradient([Color(0.72, 0.1, 0.07), Color(0.88, 0.3, 0.08), Color(0.95, 0.55, 0.12),
					Color(0.62, 0.08, 0.06)]),
				"speed": [0.2, 0.8], "direction": Vector3(0.5, -0.3, 0.2), "spread": 40.0,
				"gravity": Vector3(0.5, -1.0, 0.15), "damping": 0.8,
				"box": Vector3(RADIUS, 2.5, RADIUS), "y": 5.0}
		"snow":
			return {"texture": &"glow", "dot": true, "amount": 320, "lifetime": 6.0, "size": [0.06, 0.11], "size_curve": steady,
				"colors": Vfx.gradient([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.0)],
					[0.0, 0.08, 0.9, 1.0]),
				"speed": [0.2, 0.6], "direction": Vector3(0.3, -1.0, 0.1), "spread": 30.0,
				"gravity": Vector3(0.1, -1.2, 0.05), "damping": 1.0,
				"box": Vector3(RADIUS, 2.0, RADIUS), "y": 6.0}
		"mist":
			var white := Color(0.82, 0.88, 0.92)
			return {"texture": &"glow", "amount": 26, "lifetime": 9.0, "size": [3.0, 5.0],
				"size_curve": steady,
				"colors": Vfx.gradient([Color(white, 0.0), Color(white, 0.2), Color(white, 0.2), Color(white, 0.0)],
					[0.0, 0.25, 0.7, 1.0]),
				"speed": [0.1, 0.35], "direction": Vector3(1.0, 0.0, 0.3), "spread": 60.0,
				"box": Vector3(RADIUS, 0.5, RADIUS), "y": 1.4, "fade_from": [2.5, 7.0]}
		"wind":
			return {"mesh": Vfx.streak_mesh(1.0, 0.07), "amount": 34, "lifetime": 1.1, "size": [1.0, 2.2],
				"size_curve": steady, "align": true,
				"colors": Vfx.gradient([Color(0.95, 0.97, 1.0, 0.0), Color(0.95, 0.97, 1.0, 0.55),
					Color(0.95, 0.97, 1.0, 0.55), Color(0.95, 0.97, 1.0, 0.0)], [0.0, 0.2, 0.7, 1.0]),
				"speed": [11.0, 17.0], "direction": Vector3(1.0, -0.04, 0.35), "spread": 4.0,
				"box": Vector3(RADIUS, 2.5, RADIUS), "y": 2.5}
		"pollen":
			return {"texture": &"glow", "amount": 70, "lifetime": 8.0, "size": [0.1, 0.18], "size_curve": steady,
				"colors": Vfx.gradient([Color(1.0, 0.93, 0.55, 0.0), Color(1.0, 0.93, 0.55, 1.0),
					Color(1.0, 0.93, 0.55, 1.0), Color(1.0, 0.93, 0.55, 0.0)], [0.0, 0.15, 0.85, 1.0]),
				"speed": [0.1, 0.4], "direction": Vector3.UP, "spread": 180.0,
				"gravity": Vector3(0.15, 0.02, 0.05), "damping": 0.2,
				"box": Vector3(RADIUS, 1.4, RADIUS), "y": 1.6}
		"petals":
			return {"mesh": _shape(PETAL, 60.0), "amount": 50, "lifetime": 9.0, "size": [0.14, 0.22],
				"size_curve": steady, "spin": [-150.0, 150.0],
				"colors": Vfx.gradient([Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.0)],
					[0.0, 0.1, 0.85, 1.0]),
				"initial": Vfx.gradient([Color(1.0, 0.75, 0.82), Color(1.0, 0.9, 0.92), Color(0.95, 0.62, 0.75)]),
				"speed": [0.1, 0.5], "direction": Vector3(0.5, -0.3, 0.2), "spread": 50.0,
				"gravity": Vector3(0.3, -0.35, 0.1), "damping": 0.7,
				"box": Vector3(RADIUS, 2.5, RADIUS), "y": 4.5}
		_:
			var glow: Color = FIREFLY_COLORS.get(island_id, Color(0.8, 1.0, 0.35))
			# They blink: bright, dim, bright again at their own pace.
			var on := Color(glow, 1.0)
			var off := Color(glow, 0.12)
			return {"texture": &"glow", "additive": true, "amount": 26, "lifetime": 7.0, "size": [0.2, 0.32],
				"size_curve": steady,
				"colors": Vfx.gradient([Color(glow, 0.0), on, off, on, off, on, off, Color(glow, 0.0)],
					[0.0, 0.1, 0.25, 0.4, 0.55, 0.7, 0.85, 1.0]),
				"speed": [0.15, 0.6], "direction": Vector3.UP, "spread": 180.0, "damping": 0.1,
				"box": Vector3(RADIUS * 0.8, 0.8, RADIUS * 0.8), "y": 1.2, "lit": false}


## A small crisp disc (snowflakes), where the effects kit only has soft glows.
static func _dot() -> Texture2D:
	if _dot_texture == null:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		for y in 32:
			for x in 32:
				var r := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(16.0, 16.0)) / 16.0
				img.set_pixel(x, y, Color(1, 1, 1, clampf((0.95 - r) / 0.3, 0.0, 1.0)))
		_dot_texture = ImageTexture.create_from_image(img)
	return _dot_texture


## A flat shape (leaf, petal, flake) one metre long, tipped back `tilt`
## degrees so it shows its face from above as well as from the side. White at
## its middle and a little darker at the edge; the particle's colour does the
## rest.
static func _shape(outline: Array[Vector2], tilt: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := cos(deg_to_rad(tilt))
	var s := sin(deg_to_rad(tilt))
	for i in outline.size():
		for v: Array in [[Vector2.ZERO, 1.0], [outline[i], 0.8], [outline[(i + 1) % outline.size()], 0.8]]:
			var at: Vector2 = v[0]
			st.set_color(Color(v[1], v[1], v[1]))
			st.add_vertex(Vector3(at.x, at.y * c, at.y * s))
	st.set_material(Vfx.surface_material(null, false))
	return st.commit()
