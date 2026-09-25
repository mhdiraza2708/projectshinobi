class_name Hud
extends CanvasLayer
## In-game HUD in the ink-and-scroll style: vitals scroll, talisman weave
## panel with a burning fuse, quick-cast slots, cast banner, shuriken
## lock-on marker and a device-aware control legend.

const MAX_HINTS := 4
const LEGEND := [
	[&"weave", "Weave"], [&"attack", "Strike"], [&"throw_tool", "Kunai"], [&"evade", "Dash"],
	[&"guard", "Guard"], [&"charge_chakra", "Charge"], [&"lock_on", "Lock on"], [&"pause", "Menu"],
]

var player: Player

var _health_bar: InkBar
var _health_text: Label
var _chakra_bar: InkBar
var _chakra_text: Label
var _buffs: Label
var _banner: BrushBanner
var _weave_panel: PaperPanel
var _fuse: FuseBar
var _instruction: HBoxContainer
var _talismans: HBoxContainer
var _hints: VBoxContainer
var _slot_rows: Array[Dictionary] = []
var _reticle: ShurikenReticle
var _shown_sequence: Array[int] = []


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
	player.caster.cast_succeeded.connect(_on_cast)
	player.feedback.connect(func(text: String, kind: StringName) -> void:
		if kind != &"cast":
			show_banner(text, kind))
	player.quick_slots_changed.connect(_refresh_slots)
	InputDevice.device_changed.connect(func(_d: Binding.Device) -> void: _refresh_weave(true))
	Settings.bindings_changed.connect(func() -> void: _refresh_weave(true))
	Settings.value_changed.connect(func(_k: StringName, _v: Variant) -> void: _refresh_weave(true))
	_on_health(player.stats.health, player.stats.max_health)
	_on_chakra(player.stats.chakra, player.stats.max_chakra)
	_refresh_slots()
	_refresh_weave(true)


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiKit.theme()
	add_child(root)

	# --- Vitals scroll, top-left ---------------------------------------------
	var vitals := PaperPanel.new()
	vitals.seed = 3.0
	vitals.margin = Vector4(22, 18, 40, 18)
	vitals.position = Vector2(34, 26)
	root.add_child(vitals)
	var vrow := HBoxContainer.new()
	vrow.add_theme_constant_override(&"separation", 18)
	vitals.add_child(vrow)
	vrow.add_child(Hanko.make("忍", 88.0))
	var bars := VBoxContainer.new()
	bars.add_theme_constant_override(&"separation", 2)
	vrow.add_child(bars)
	_health_bar = InkBar.new()
	_health_bar.ink_color = UiKit.HEALTH
	_health_text = UiKit.label("", 20, UiKit.INK, &"bold")
	_chakra_bar = InkBar.new()
	_chakra_bar.ink_color = UiKit.CHAKRA
	_chakra_bar.seed = 7.0
	_chakra_text = UiKit.label("", 20, UiKit.INK, &"bold")
	bars.add_child(_vital_row("体", "HEALTH", _health_text))
	bars.add_child(_health_bar)
	bars.add_child(_vital_row("気", "CHAKRA", _chakra_text))
	bars.add_child(_chakra_bar)
	_buffs = UiKit.label("", 17, UiKit.CRIMSON_DARK, &"bold")
	bars.add_child(_buffs)

	# --- Cast banner, top-centre -------------------------------------------
	_banner = BrushBanner.new()
	_banner.anchor_left = 0.5
	_banner.anchor_right = 0.5
	_banner.offset_left = -BrushBanner.BAND_SIZE.x * 0.5
	_banner.offset_right = BrushBanner.BAND_SIZE.x * 0.5
	_banner.offset_top = 150
	_banner.offset_bottom = 150 + BrushBanner.BAND_SIZE.y
	root.add_child(_banner)

	# --- Weave panel, bottom-centre ------------------------------------------
	_weave_panel = PaperPanel.new()
	_weave_panel.seed = 11.0
	_weave_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_weave_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_weave_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_weave_panel.offset_bottom = -40
	root.add_child(_weave_panel)
	var wv := VBoxContainer.new()
	wv.add_theme_constant_override(&"separation", 10)
	wv.custom_minimum_size.x = 640
	_weave_panel.add_child(wv)
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 10)
	header.add_child(UiKit.label("印", 38, UiKit.CRIMSON, &"brush"))
	header.add_child(UiKit.label("WEAVING", 28, UiKit.INK, &"display"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_instruction = HBoxContainer.new()
	_instruction.add_theme_constant_override(&"separation", 6)
	header.add_child(_instruction)
	wv.add_child(header)
	_fuse = FuseBar.new()
	_fuse.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wv.add_child(_fuse)
	_talismans = HBoxContainer.new()
	_talismans.add_theme_constant_override(&"separation", 10)
	_talismans.custom_minimum_size.y = Talisman.SIZE.y
	wv.add_child(_talismans)
	_hints = VBoxContainer.new()
	_hints.add_theme_constant_override(&"separation", 4)
	wv.add_child(_hints)

	# --- Quick-cast slots, bottom-right ----------------------------------------
	var slots := PaperPanel.new()
	slots.seed = 5.0
	slots.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	slots.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	slots.grow_vertical = Control.GROW_DIRECTION_BEGIN
	slots.offset_right = -30
	slots.offset_bottom = -30
	root.add_child(slots)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override(&"separation", 6)
	slots.add_child(sv)
	var sh := HBoxContainer.new()
	sh.add_child(UiKit.label("術", 28, UiKit.CRIMSON, &"brush"))
	sh.add_child(UiKit.label("QUICK CAST", 20, UiKit.INK, &"display"))
	sv.add_child(sh)
	for i in 4:
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 10)
		row.custom_minimum_size = Vector2(330, 38)
		var glyph := InputGlyph.for_action(StringName("quick_cast_%d" % (i + 1)), 32.0)
		var stamp := Hanko.make("無", 34.0)
		var name_label := UiKit.label("", 20, UiKit.INK, &"bold")
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var status := UiKit.label("", 17, UiKit.CRIMSON, &"bold")
		row.add_child(glyph)
		row.add_child(stamp)
		row.add_child(name_label)
		row.add_child(status)
		sv.add_child(row)
		_slot_rows.append({"row": row, "stamp": stamp, "name": name_label, "status": status})

	# --- Control legend, bottom-left -------------------------------------------
	var legend_bg := PanelContainer.new()
	var legend_box := StyleBoxFlat.new()
	legend_box.bg_color = Color(UiKit.INK, 0.62)
	legend_box.set_corner_radius_all(6)
	legend_box.content_margin_left = 14
	legend_box.content_margin_right = 14
	legend_box.content_margin_top = 10
	legend_box.content_margin_bottom = 10
	legend_bg.add_theme_stylebox_override(&"panel", legend_box)
	legend_bg.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	legend_bg.grow_vertical = Control.GROW_DIRECTION_BEGIN
	legend_bg.offset_left = 30
	legend_bg.offset_bottom = -30
	legend_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(legend_bg)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 26)
	grid.add_theme_constant_override(&"v_separation", 6)
	legend_bg.add_child(grid)
	for entry in LEGEND:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override(&"separation", 8)
		cell.add_child(InputGlyph.for_action(entry[0], 28.0))
		cell.add_child(UiKit.label(entry[1], 18, UiKit.PAPER, &"bold"))
		grid.add_child(cell)

	_reticle = ShurikenReticle.new()
	_reticle.visible = false
	root.add_child(_reticle)


func _vital_row(kanji: String, title: String, value_label: Label) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	row.add_child(UiKit.label(kanji, 26, UiKit.INK, &"brush"))
	var t := UiKit.label(title, 16, UiKit.INK_SOFT, &"bold")
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(t)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(value_label)
	return row


func _process(_delta: float) -> void:
	if player == null:
		return
	if player.weaver.is_weaving:
		_fuse.ratio = player.weaver.window_remaining()
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
	_health_bar.set_ratio(current / maximum)
	_health_text.text = "%d / %d" % [ceili(current), int(maximum)]


func _on_chakra(current: float, maximum: float) -> void:
	_chakra_bar.set_ratio(current / maximum)
	_chakra_text.text = "%d / %d" % [floori(current), int(maximum)]


func _on_cast(jutsu: JutsuDefinition) -> void:
	if jutsu.id == &"kunai":
		return
	_banner.show_text(jutsu.display_name, &"cast", jutsu.element)


func show_banner(text: String, kind: StringName = &"info") -> void:
	_banner.show_text(text, kind)


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
	_buffs.text = "  ·  ".join(parts)
	_buffs.visible = not parts.is_empty()


func _refresh_weave(force := false) -> void:
	if _weave_panel == null:
		return
	var weaver := player.weaver
	_weave_panel.visible = weaver.is_weaving
	if not weaver.is_weaving:
		_shown_sequence.clear()
		return
	_fuse.lit = float(Settings.get_value(&"seal_timeout_scale")) > 0.0 and not weaver.sequence.is_empty()

	for c in _instruction.get_children():
		c.queue_free()
	var hold: bool = Settings.get_value(&"weave_mode") == "hold"
	_instruction.add_child(UiKit.label("Release" if hold else "Press", 18, UiKit.INK_SOFT, &"bold"))
	_instruction.add_child(InputGlyph.for_action(&"weave", 28.0))
	_instruction.add_child(UiKit.label("to cast" if hold else "again to cast", 18, UiKit.INK_SOFT, &"bold"))

	# Only stamp the newest talisman; rebuild everything when the sequence
	# was reset or the device changed.
	var seq := weaver.sequence
	var appended := seq.size() == _shown_sequence.size() + 1 and seq.slice(0, _shown_sequence.size()) == _shown_sequence
	if force or not appended:
		for c in _talismans.get_children():
			c.queue_free()
		for s in seq:
			_talismans.add_child(Talisman.make(s, false))
	else:
		for c in _talismans.get_children():
			if not c is Talisman:
				c.queue_free()
		_talismans.add_child(Talisman.make(seq[-1], true))
	_shown_sequence = seq.duplicate()
	if seq.is_empty():
		_talismans.add_child(UiKit.label("Enter seals…", 22, UiKit.INK_SOFT, &"bold"))

	for c in _hints.get_children():
		c.queue_free()
	if not Settings.get_value(&"seal_hints"):
		return
	var exact := JutsuRegistry.find_by_seals(seq)
	if exact:
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 10)
		row.add_child(Hanko.make(Element.kanji(exact.element), 32.0, _element_stamp(exact.element)))
		row.add_child(UiKit.label(exact.display_name, 24, UiKit.CRIMSON, &"display"))
		row.add_child(UiKit.label(UiKit.jutsu_tag(exact), 17, UiKit.INK_SOFT, &"bold"))
		_hints.add_child(row)
	var shown := 0
	for j in JutsuRegistry.completions(seq):
		if j == exact:
			continue
		if shown >= MAX_HINTS:
			break
		var next_seal: int = j.seals[seq.size()]
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 8)
		row.add_child(Hanko.make(Element.kanji(j.element), 26.0, _element_stamp(j.element)))
		var name_label := UiKit.label(j.display_name, 19, UiKit.INK, &"bold")
		name_label.custom_minimum_size.x = 190
		row.add_child(name_label)
		row.add_child(UiKit.label("next", 16, UiKit.INK_SOFT, &"body"))
		row.add_child(UiKit.label(Seal.kanji(next_seal), 22, UiKit.INK, &"brush"))
		row.add_child(UiKit.label(Seal.display_name(next_seal), 17, UiKit.INK_SOFT, &"bold"))
		row.add_child(UiKit.seal_glyphs(next_seal, 26.0))
		_hints.add_child(row)
		shown += 1
	if exact == null and shown == 0 and not seq.is_empty():
		_hints.add_child(UiKit.label("No jutsu uses this sequence", 19, UiKit.CRIMSON, &"bold"))


func _refresh_slots() -> void:
	for i in _slot_rows.size():
		var r: Dictionary = _slot_rows[i]
		var id: StringName = player.quick_slots[i] if i < player.quick_slots.size() else &""
		var j := JutsuRegistry.get_jutsu(id)
		if j == null:
			r["name"].text = "—"
			r["status"].text = ""
			continue
		r["name"].text = j.display_name
		(r["stamp"] as Hanko).text = Element.kanji(j.element)
		(r["stamp"] as Hanko).color = _element_stamp(j.element)
		var cd := player.caster.cooldown_left(j.id)
		var status := "%.1fs" % cd if cd > 0.0 else ""
		if cd <= 0.0 and player.stats.chakra < j.chakra_cost:
			status = "low chakra"
		r["status"].text = status
		(r["row"] as Control).modulate = Color(1, 1, 1, 0.5) if status != "" else Color.WHITE


static func _element_stamp(element: int) -> Color:
	return UiKit.CRIMSON if element == Element.NONE else Element.color(element).darkened(0.35)
