class_name Hud
extends CanvasLayer
## In-game HUD: vitals, seal-weaving panel with hints, quick-cast slots,
## lock-on reticle, feedback banner and a device-aware controls strip.

const MAX_HINTS := 5

var player: Player

var _health_bar: ProgressBar
var _health_text: Label
var _chakra_bar: ProgressBar
var _chakra_text: Label
var _buffs: Label
var _weave_panel: PanelContainer
var _weave_window: ProgressBar
var _seal_row: HBoxContainer
var _hints: VBoxContainer
var _banner: Label
var _banner_tween: Tween
var _slots: Array[Label] = []
var _controls_strip: Label
var _reticle: Label


func _init() -> void:
	layer = 5


func bind(p: Player) -> void:
	player = p
	_build()
	player.stats.health_changed.connect(_on_health)
	player.stats.chakra_changed.connect(_on_chakra)
	player.weaver.started.connect(_refresh_weave)
	player.weaver.seal_added.connect(func(_s: int, _q: Array[int]) -> void: _refresh_weave())
	player.weaver.broken.connect(_refresh_weave)
	player.weaver.finished.connect(func(_q: Array[int]) -> void: _refresh_weave())
	player.weaver.cancelled.connect(_refresh_weave)
	player.feedback.connect(show_banner)
	player.quick_slots_changed.connect(_refresh_slots)
	InputDevice.device_changed.connect(func(_d: Binding.Device) -> void: _refresh_all_glyphs())
	Settings.bindings_changed.connect(_refresh_all_glyphs)
	Settings.value_changed.connect(func(_k: StringName, _v: Variant) -> void: _refresh_weave())
	_on_health(player.stats.health, player.stats.max_health)
	_on_chakra(player.stats.chakra, player.stats.max_chakra)
	_refresh_all_glyphs()
	_refresh_weave()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiKit.theme()
	add_child(root)

	# Vitals, top-left.
	var vitals := PanelContainer.new()
	vitals.position = Vector2(32, 28)
	root.add_child(vitals)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 6)
	vitals.add_child(vbox)
	_health_bar = UiKit.bar(UiKit.HEALTH)
	_health_text = UiKit.label("", 20)
	_chakra_bar = UiKit.bar(UiKit.CHAKRA)
	_chakra_text = UiKit.label("", 20)
	for pair in [[UiKit.label("HEALTH", 18, UiKit.MUTED), _health_text, _health_bar],
			[UiKit.label("CHAKRA", 18, UiKit.MUTED), _chakra_text, _chakra_bar]]:
		var row := HBoxContainer.new()
		row.add_child(pair[0])
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
		row.add_child(pair[1])
		vbox.add_child(row)
		vbox.add_child(pair[2])
	_buffs = UiKit.label("", 20, Color(0.8, 0.95, 1.0))
	vbox.add_child(_buffs)

	# Feedback banner, top-centre.
	_banner = UiKit.label("", 40)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.position.y = 90
	_banner.modulate.a = 0.0
	root.add_child(_banner)

	# Weave panel, bottom-centre.
	_weave_panel = PanelContainer.new()
	_weave_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_weave_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_weave_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_weave_panel.position.y -= 150
	root.add_child(_weave_panel)
	var wv := VBoxContainer.new()
	wv.add_theme_constant_override(&"separation", 8)
	_weave_panel.add_child(wv)
	wv.add_child(UiKit.label("WEAVING", 20, UiKit.ACCENT))
	_weave_window = UiKit.bar(UiKit.ACCENT, 520)
	_weave_window.custom_minimum_size.y = 8
	wv.add_child(_weave_window)
	_seal_row = HBoxContainer.new()
	_seal_row.add_theme_constant_override(&"separation", 10)
	wv.add_child(_seal_row)
	_hints = VBoxContainer.new()
	wv.add_child(_hints)

	# Quick-cast slots, bottom-right.
	var slots_panel := PanelContainer.new()
	slots_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	slots_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	slots_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	slots_panel.position += Vector2(-32, -72)
	root.add_child(slots_panel)
	var sv := VBoxContainer.new()
	slots_panel.add_child(sv)
	sv.add_child(UiKit.label("QUICK CAST", 18, UiKit.MUTED))
	for i in 4:
		var l := UiKit.label("", 22)
		_slots.append(l)
		sv.add_child(l)

	# Controls strip, bottom-left.
	_controls_strip = UiKit.label("", 20, UiKit.MUTED)
	_controls_strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_controls_strip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_controls_strip.position += Vector2(32, -24)
	root.add_child(_controls_strip)

	_reticle = UiKit.label("◇", 44, UiKit.ACCENT)
	_reticle.visible = false
	root.add_child(_reticle)


func _process(_delta: float) -> void:
	if player == null:
		return
	if player.weaver.is_weaving:
		_weave_window.value = player.weaver.window_remaining() * 100.0
	_refresh_slots()
	_refresh_buffs()
	var cam := get_viewport().get_camera_3d()
	var target := player.lock_target
	_reticle.visible = is_instance_valid(target) and cam != null \
		and not cam.is_position_behind(target.global_position + Vector3.UP)
	if _reticle.visible:
		var screen := cam.unproject_position(target.global_position + Vector3.UP * 1.2)
		_reticle.position = screen - _reticle.size * 0.5


func _on_health(current: float, maximum: float) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current
	_health_text.text = "%d / %d" % [ceili(current), int(maximum)]


func _on_chakra(current: float, maximum: float) -> void:
	_chakra_bar.max_value = maximum
	_chakra_bar.value = current
	_chakra_text.text = "%d / %d" % [floori(current), int(maximum)]


func _refresh_buffs() -> void:
	var parts := PackedStringArray()
	for stat: String in JutsuDefinition.BUFF_STATS:
		var left := player.stats.modifier_time_left(StringName(stat))
		if left > 0.0:
			parts.append("%s %.0fs" % [stat.capitalize(), ceilf(left)])
	if player.state == Player.State.GUARDING:
		parts.append("Guarding")
	if player.state == Player.State.CHARGING:
		parts.append("Charging chakra")
	_buffs.text = "   ".join(parts)


func _refresh_weave() -> void:
	if _weave_panel == null:
		return
	var weaver := player.weaver
	_weave_panel.visible = weaver.is_weaving
	if not weaver.is_weaving:
		return
	for c in _seal_row.get_children():
		c.queue_free()
	if weaver.sequence.is_empty():
		_seal_row.add_child(UiKit.label("Enter seals, then release %s to cast" % InputDevice.glyph(&"weave")
			if Settings.get_value(&"weave_mode") == "hold"
			else "Enter seals, then press %s again to cast" % InputDevice.glyph(&"weave"), 22, UiKit.MUTED))
	for seal in weaver.sequence:
		var chip := PanelContainer.new()
		var chip_box := VBoxContainer.new()
		chip.add_child(chip_box)
		chip_box.add_child(UiKit.label(Seal.display_name(seal), 26))
		chip_box.add_child(UiKit.label(UiKit.seal_glyph(seal), 18, UiKit.MUTED))
		_seal_row.add_child(chip)

	for c in _hints.get_children():
		c.queue_free()
	if not Settings.get_value(&"seal_hints"):
		return
	var exact := JutsuRegistry.find_by_seals(weaver.sequence)
	if exact:
		_hints.add_child(UiKit.label("✓ %s  (%s)" % [exact.display_name, UiKit.jutsu_tag(exact)], 22,
			Element.color(exact.element).lightened(0.3)))
	var shown := 0
	for j in JutsuRegistry.completions(weaver.sequence):
		if j == exact:
			continue
		if shown >= MAX_HINTS:
			break
		var next_seal: int = j.seals[weaver.sequence.size()]
		_hints.add_child(UiKit.label("%s  →  next: %s  [%s]" % [
			j.display_name, Seal.display_name(next_seal), UiKit.seal_glyph(next_seal)], 20, UiKit.MUTED))
		shown += 1
	if exact == null and shown == 0 and not weaver.sequence.is_empty():
		_hints.add_child(UiKit.label("No jutsu uses this sequence", 20, UiKit.FAIL))


func _refresh_slots() -> void:
	for i in _slots.size():
		var id: StringName = player.quick_slots[i] if i < player.quick_slots.size() else &""
		var j := JutsuRegistry.get_jutsu(id)
		var glyph := InputDevice.glyph(StringName("quick_cast_%d" % (i + 1)))
		if j == null:
			_slots[i].text = "[%s]  —" % glyph
			continue
		var cd := player.caster.cooldown_left(j.id)
		var status := " (%.1fs)" % cd if cd > 0.0 else ""
		if cd <= 0.0 and player.stats.chakra < j.chakra_cost:
			status = " (low chakra)"
		_slots[i].text = "[%s]  %s%s" % [glyph, j.display_name, status]
		_slots[i].modulate = Color(1, 1, 1, 0.45) if status != "" else Color.WHITE


func _refresh_all_glyphs() -> void:
	var g := func(a: StringName) -> String: return InputDevice.glyph(a)
	_controls_strip.text = "Weave %s   Strike %s   Kunai %s   Dash %s   Guard %s   Charge %s   Lock %s   Menu %s" % [
		g.call(&"weave"), g.call(&"attack"), g.call(&"throw_tool"), g.call(&"evade"),
		g.call(&"guard"), g.call(&"charge_chakra"), g.call(&"lock_on"), g.call(&"pause")]
	_refresh_slots()
	_refresh_weave()


func show_banner(text: String, kind: StringName = &"info") -> void:
	_banner.text = text
	_banner.add_theme_color_override(&"font_color", UiKit.FAIL if kind == &"fail" else UiKit.TEXT)
	_banner.add_theme_font_size_override(&"font_size", 44 if kind == &"cast" else 30)
	# Recentre after the text changes width.
	_banner.reset_size()
	_banner.position.x = (_banner.get_parent_area_size().x - _banner.size.x) * 0.5
	if _banner_tween:
		_banner_tween.kill()
	_banner.modulate.a = 1.0
	_banner_tween = create_tween()
	_banner_tween.tween_interval(1.1)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.5)
