class_name Talisman
extends Control
## An ofuda (paper talisman) for one woven seal: zodiac kanji, seal name,
## and the input that produces it. Slaps down like a stamp when added.

const SIZE := Vector2(96, 150)

var seal := Seal.RAT


static func make(seal_index: int, animate := true) -> Talisman:
	var t := Talisman.new()
	t.seal = seal_index
	if animate:
		t.ready.connect(t._stamp)
	return t


func _init() -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = SIZE * 0.5


func _ready() -> void:
	var glyphs := UiKit.seal_glyphs(seal, 26.0)
	add_child(glyphs)
	glyphs.position = Vector2(0, SIZE.y - 38)
	glyphs.size = Vector2(SIZE.x, 30)


func _stamp() -> void:
	scale = Vector2.ONE * 1.35
	rotation = deg_to_rad(randf_range(-6.0, 6.0))
	modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "rotation", deg_to_rad(randf_range(-2.0, 2.0)), 0.16)
	tw.tween_property(self, "modulate:a", 1.0, 0.08)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, SIZE)
	draw_rect(r, UiKit.PAPER)
	# Double vermilion border, like a printed charm.
	draw_rect(r.grow(-5), UiKit.CRIMSON, false, 3.0)
	draw_rect(r.grow(-10), UiKit.CRIMSON, false, 1.0)
	var brush := UiKit.font(&"brush")
	var fs := 60
	var k := Seal.kanji(seal)
	var w := brush.get_string_size(k, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(brush, Vector2((SIZE.x - w) * 0.5, 72), k, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiKit.INK)
	var bold := UiKit.font(&"bold")
	var name_text := Seal.display_name(seal).to_upper()
	var nfs := 15
	var nw := bold.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs).x
	draw_string(bold, Vector2((SIZE.x - nw) * 0.5, 100), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs, UiKit.CRIMSON)
