class_name WorldMap
extends Control
## The archipelago as an ink-wash chart (the pause menu's Map tab): every
## island drawn from its real ground, named once you've been there (a "?"
## until then), with you, the story's pillar of light, people who have
## something for you and the tracked objective marked on it.

## Metres per pixel of the chart's image.
const METRES_PER_PIXEL := 4.0
## How far past the outermost islands the chart reaches.
const MARGIN := 110.0
## More below: names are written under the islands, Emberwood's included.
const LABEL_ROOM := 110.0

var world: OpenWorld

static var _image_cache: Dictionary = {}
var _texture: Texture2D
var _bounds := Rect2()


func _init() -> void:
	# Fits the pause menu's page without scrolling (at 16:9 the page shows
	# about 475 pixels of height).
	custom_minimum_size = Vector2(430, 460)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The chart's extent in archipelago metres (x, z).
static func bounds() -> Rect2:
	var r := Rect2()
	var first := true
	for id: String in Archipelago.LAYOUT:
		var at: Vector2 = Archipelago.LAYOUT[id]
		if first:
			r = Rect2(at, Vector2.ZERO)
			first = false
		else:
			r = r.expand(at)
	return r.grow_individual(MARGIN, MARGIN, MARGIN, MARGIN + LABEL_ROOM)


func bind(w: OpenWorld) -> void:
	world = w
	_bounds = bounds()
	_texture = chart(world.archipelago)
	queue_redraw()


## Paints the islands once per world (cached): pale land darkening with
## height, a darker ink line along every coast, the sea left as paper.
static func chart(arch: Archipelago) -> Texture2D:
	var key := arch.get_instance_id()
	if _image_cache.has(key):
		return _image_cache[key]
	var b := bounds()
	var w := int(b.size.x / METRES_PER_PIXEL)
	var h := int(b.size.y / METRES_PER_PIXEL)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var land := Color("b9a47c")
	var high := Color("6e5f4a")
	var coast := Color(UiKit.INK, 0.85)
	for id: String in Archipelago.LAYOUT:
		var island: Island = arch.islands.get(id)
		if island == null:
			continue
		var c: Vector2 = Archipelago.LAYOUT[id]
		var reach := float(island.preset["coast"]) + 30.0
		var x0 := int((c.x - reach - b.position.x) / METRES_PER_PIXEL)
		var x1 := int((c.x + reach - b.position.x) / METRES_PER_PIXEL)
		var y0 := int((c.y - reach - b.position.y) / METRES_PER_PIXEL)
		var y1 := int((c.y + reach - b.position.y) / METRES_PER_PIXEL)
		var sea := island.water_level
		for py in range(maxi(y0, 0), mini(y1, h)):
			for px in range(maxi(x0, 0), mini(x1, w)):
				var lx := b.position.x + px * METRES_PER_PIXEL - c.x
				var lz := b.position.y + py * METRES_PER_PIXEL - c.y
				var above := island.height_at(lx, lz) - sea
				if above < 0.2:
					continue
				var col := land.lerp(high, clampf(above / 30.0, 0.0, 1.0))
				# The shore gets an ink line.
				if above < 1.4:
					col = col.lerp(coast, 0.75)
				img.set_pixel(px, py, col)
	var tex := ImageTexture.create_from_image(img)
	_image_cache[key] = tex
	return tex


## A point in the archipelago (metres, x and z) on the chart.
func to_chart(p: Vector2) -> Vector2:
	var scale := minf(size.x / _bounds.size.x, size.y / _bounds.size.y)
	var used := _bounds.size * scale
	var offset := (size - used) * 0.5
	return offset + (p - _bounds.position) * scale


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	if world == null or _texture == null:
		return
	var top_left := to_chart(_bounds.position)
	var bottom_right := to_chart(_bounds.end)
	# The sea: a pale wash with a few ink waves.
	draw_rect(Rect2(top_left, bottom_right - top_left), Color("cfd8d0", 0.55))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 40:
		var at := top_left + Vector2(rng.randf(), rng.randf()) * (bottom_right - top_left)
		draw_arc(at, 6.0, PI * 1.1, PI * 1.9, 6, Color(UiKit.INK, 0.18), 1.5)
	draw_texture_rect(_texture, Rect2(top_left, bottom_right - top_left), false)
	draw_rect(Rect2(top_left, bottom_right - top_left), Color(UiKit.INK, 0.6), false, 2.0)
	var bold := UiKit.font(&"bold")
	var brush := UiKit.font(&"brush")
	for id: String in Archipelago.LAYOUT:
		var at := to_chart(Archipelago.LAYOUT[id]) + Vector2(0, 46)
		if world.discovered(id):
			var label := Island.display_name(id)
			var kanji: String = OpenWorld.ISLAND_KANJI.get(id, "")
			draw_string(brush, at + Vector2(-12, -2), kanji, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UiKit.CRIMSON_DARK)
			var w := bold.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			draw_string(bold, at + Vector2(-w * 0.5, 18), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiKit.INK)
		else:
			draw_string(bold, at + Vector2(-5, 6), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(UiKit.INK, 0.5))
	# People with something for you.
	for who: String in world.wanted_people():
		var place: Dictionary = world.wanted_people()[who]
		if place["marker"] != "!":
			continue
		var p := _island_point(place["island"], Vector2(place["at"][0], place["at"][1]))
		draw_circle(p, 6.0, UiKit.GOLD)
		draw_string(bold, p + Vector2(-3, 5), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiKit.INK)
	# The story's pillar.
	var c := Quests.main_chapter(world.story)
	if not c.is_empty():
		var p := _island_point(str(c["island"]), c["player_at"])
		draw_line(p, p - Vector2(0, 26), Color("f2c96b"), 4.0)
		draw_circle(p, 5.0, Color("f2c96b"))
	# The tracked objective.
	var o := world.objective()
	if o["at"] is Vector3:
		var q := to_chart(_flat(world.archipelago.to_local(o["at"])))
		var r := 9.0
		var pts := PackedVector2Array([q + Vector2(0, -r), q + Vector2(r, 0), q + Vector2(0, r), q + Vector2(-r, 0), q + Vector2(0, -r)])
		draw_polyline(pts, UiKit.CRIMSON, 3.0, true)
	# You: an arrow the way you face.
	var me := world.archipelago.to_local(world.player.global_position)
	var face := -world.player.global_basis.z
	var dir := Vector2(face.x, face.z).normalized() if Vector2(face.x, face.z).length() > 0.01 else Vector2.UP
	var mp := to_chart(Vector2(me.x, me.z))
	var arrow := PackedVector2Array([mp + dir * 12.0, mp + dir.rotated(2.5) * 8.0, mp + dir.rotated(-2.5) * 8.0])
	draw_colored_polygon(arrow, UiKit.CRIMSON)
	draw_polyline(PackedVector2Array([arrow[0], arrow[1], arrow[2], arrow[0]]), UiKit.INK, 2.0, true)


func _island_point(id: String, local: Vector2) -> Vector2:
	return to_chart(Archipelago.LAYOUT.get(id, Vector2.ZERO) + local)


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
