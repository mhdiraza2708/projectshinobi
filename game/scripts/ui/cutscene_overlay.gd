class_name CutsceneOverlay
extends CanvasLayer
## What a cutscene puts over the picture: letterbox bars that slide in and
## out, a title caption, the "hold to skip" prompt filling as you hold, and a
## full-screen fade (to black for scene changes, white for flashes).

## Bar height as a share of the screen.
const BAR := 0.11
const SLIDE := 0.45

var _top: ColorRect
var _bottom: ColorRect
var _caption: VBoxContainer
var _title: Label
var _sub: Label
var _skip: HBoxContainer
var _skip_fill: ColorRect
var _skip_back: ColorRect
var _fade: ColorRect
var _bars := 0.0
var _bars_target := 0.0


func _init() -> void:
	# Over the world and the HUD, under dialogue (12) so lines stay readable.
	layer = 11


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_fade = ColorRect.new()
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.color = Color(0, 0, 0, 0)
	root.add_child(_fade)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0.02, 0.02, 0.03)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		root.add_child(bar)
		if top:
			_top = bar
		else:
			_bottom = bar

	_caption = VBoxContainer.new()
	_caption.set_anchors_preset(Control.PRESET_CENTER)
	_caption.anchor_top = 0.62
	_caption.anchor_bottom = 0.62
	_caption.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_caption.alignment = BoxContainer.ALIGNMENT_CENTER
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.modulate.a = 0.0
	root.add_child(_caption)
	_title = UiKit.label("", 56, UiKit.PAPER, &"bold", 10)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_child(_title)
	_sub = UiKit.label("", 26, UiKit.GOLD, &"bold", 6)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_child(_sub)

	_skip = HBoxContainer.new()
	_skip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_skip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_skip.offset_right = -28
	_skip.offset_bottom = -14
	_skip.add_theme_constant_override(&"separation", 8)
	_skip.alignment = BoxContainer.ALIGNMENT_END
	_skip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_skip)
	_skip.add_child(InputGlyph.for_action(&"pause", 26.0))
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_skip.add_child(col)
	col.add_child(UiKit.label("Hold to skip", 18, UiKit.PAPER_DARK, &"bold"))
	_skip_back = ColorRect.new()
	_skip_back.color = Color(1, 1, 1, 0.15)
	_skip_back.custom_minimum_size = Vector2(110, 4)
	col.add_child(_skip_back)
	_skip_fill = ColorRect.new()
	_skip_fill.color = UiKit.CRIMSON
	_skip_fill.size = Vector2(0, 4)
	_skip_back.add_child(_skip_fill)
	_skip.modulate.a = 0.0
	_layout()


func _process(delta: float) -> void:
	_bars = move_toward(_bars, _bars_target, delta / SLIDE)
	_layout()


func _layout() -> void:
	var h := get_viewport().get_visible_rect().size.y * BAR * ease(_bars, -2.0)
	_top.offset_bottom = h
	_bottom.offset_top = -h
	_skip.modulate.a = minf(_skip.modulate.a, _bars) if _bars < 1.0 else _skip.modulate.a


func show_bars() -> void:
	_bars_target = 1.0
	create_tween().tween_property(_skip, "modulate:a", 0.85, 0.4).set_delay(0.6)


func hide_bars() -> void:
	_bars_target = 0.0
	_skip.modulate.a = 0.0


## True once the bars are fully in (or fully out).
func bars_settled() -> bool:
	return is_equal_approx(_bars, _bars_target)


## 0-1: how far the skip button has been held.
func set_skip_progress(p: float) -> void:
	_skip_fill.size = Vector2(_skip_back.size.x * clampf(p, 0.0, 1.0), _skip_back.size.y)


## A caption (place, time, a chapter's title) that fades in, holds and goes.
func caption(title: String, sub: String, seconds: float) -> void:
	_title.text = title
	_sub.text = sub
	_sub.visible = sub != ""
	var tw := create_tween()
	tw.tween_property(_caption, "modulate:a", 1.0, 0.6)
	tw.tween_interval(maxf(seconds - 1.4, 0.2))
	tw.tween_property(_caption, "modulate:a", 0.0, 0.8)


func caption_alpha() -> float:
	return _caption.modulate.a


## Fades the screen to `alpha` of `color` over `seconds`.
func fade_to(alpha: float, seconds: float, color := Color.BLACK) -> void:
	_fade.color = Color(color, _fade.color.a)
	if seconds <= 0.0:
		_fade.color.a = alpha
		return
	create_tween().tween_property(_fade, "color:a", alpha, seconds)


func fade_alpha() -> float:
	return _fade.color.a


## A quick full-screen flash of `color` that fades away.
func flash(color: Color, seconds: float) -> void:
	var f := ColorRect.new()
	f.set_anchors_preset(Control.PRESET_FULL_RECT)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.color = color
	_fade.get_parent().add_child(f)
	var tw := f.create_tween()
	tw.tween_property(f, "color:a", 0.0, seconds).set_ease(Tween.EASE_IN)
	tw.tween_callback(f.queue_free)
