class_name LoadoutPanel
extends VBoxContainer
## Edits jutsu loadouts: pick a preset, rename, copy or delete it, choose what
## each of the eight quick-cast slots holds and whether it is woven or
## instant. What you edit is what you carry: the shown preset is the equipped
## one. Used by the pause menu's Jutsu Scroll and by character creation.
##
## Flow: pick a slot, then press Equip on a jutsu. The next empty slot is
## picked for you, so filling a preset is one press per jutsu.

## Show each jutsu's seals and description (the pause menu has room for them).
var detailed := false

var _slot := 0
var _message := ""
var _confirm_delete := false
## Set while this panel is the one changing the profile (it rebuilds itself).
var _busy := false


func _init(is_detailed := false) -> void:
	detailed = is_detailed
	add_theme_constant_override(&"separation", 12)


func _ready() -> void:
	Profile.changed.connect(_on_profile_changed)
	refresh()


func _on_profile_changed(key: StringName) -> void:
	if _busy:
		return
	if key in [&"", &"loadouts", &"loadout", &"ultimate", &"affinity"]:
		_confirm_delete = false
		refresh()


## Rebuilds from the saved presets, keeping controller focus where it was.
func refresh() -> void:
	var focus := _focus_key()
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var presets := Loadouts.all()
	var equipped := Loadouts.index()
	_slot = clampi(_slot, 0, Loadouts.SLOTS - 1)
	add_child(_section("Loadout"))
	add_child(_preset_row(presets, equipped))
	add_child(_section("Quick-cast slots"))
	add_child(_slot_grid(presets[equipped]))
	add_child(_hint("Weave: the seals are formed for you, as in a quick-cast. Instant: no seals at all, for %d%% more chakra."
		% roundi(Loadouts.INSTANT_SURCHARGE * 100.0)))
	if _message != "":
		add_child(UiKit.label(_message, 18, UiKit.CRIMSON_DARK, &"bold"))
	add_child(_section("Ultimate"))
	add_child(_hint("Fighting fills the ultimate meter: landing blows, taking them, interrupting weaves. When it's full, press %s."
		% InputDevice.glyph(&"ultimate")))
	var equipped_ult := Ultimates.equipped()
	for u in Ultimates.all():
		add_child(_ultimate_row(u, u["id"] == equipped_ult.get("id", "")))
	add_child(_section("Jutsu · filling slot %d" % (_slot + 1)))
	for j in JutsuRegistry.all():
		add_child(_catalog_row(j, presets[equipped]))
	if focus != "":
		_refocus.call_deferred(focus)


# --- Presets -------------------------------------------------------------------

func _preset_row(presets: Array, equipped: int) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	box.add_child(row)

	var prev := _button("<", _equip.bind(wrapi(equipped - 1, 0, presets.size())), "prev")
	prev.tooltip_text = "Previous loadout"
	prev.disabled = presets.size() < 2
	row.add_child(prev)

	var name_edit := LineEdit.new()
	name_edit.text = presets[equipped]["name"]
	name_edit.max_length = Loadouts.MAX_NAME
	name_edit.custom_minimum_size = Vector2(160, 44)
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.add_theme_font_override(&"font", UiKit.font(&"bold"))
	name_edit.add_theme_color_override(&"font_color", UiKit.INK)
	var edit_box := StyleBoxFlat.new()
	edit_box.bg_color = Color(UiKit.PAPER).darkened(0.05)
	edit_box.border_width_bottom = 2
	edit_box.border_color = UiKit.INK
	edit_box.content_margin_left = 10
	name_edit.add_theme_stylebox_override(&"normal", edit_box)
	name_edit.set_meta(&"focus_key", "name")
	name_edit.tooltip_text = "Rename this loadout"
	# Renaming doesn't rebuild the panel: it would take the cursor away.
	name_edit.text_changed.connect(func(t: String) -> void:
		_busy = true
		Loadouts.rename(equipped, t)
		_busy = false)
	row.add_child(name_edit)

	var next := _button(">", _equip.bind(wrapi(equipped + 1, 0, presets.size())), "next")
	next.tooltip_text = "Next loadout"
	next.disabled = presets.size() < 2
	row.add_child(next)
	row.add_child(UiKit.label("%d / %d" % [equipped + 1, presets.size()], 20, UiKit.INK_SOFT, &"bold"))
	var edge := Control.new()
	edge.custom_minimum_size.x = 6
	row.add_child(edge)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override(&"separation", 8)
	box.add_child(actions)
	var full := presets.size() >= Loadouts.MAX_PRESETS
	var copy := _button("Copy", _copy.bind(equipped), "copy")
	copy.disabled = full
	actions.add_child(copy)
	var blank := _button("New empty", _new_empty, "blank")
	blank.disabled = full
	actions.add_child(blank)
	actions.add_child(_button("Restore starters", _restore_starters, "restore"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	var delete := _button("Really delete?" if _confirm_delete else "Delete", _delete.bind(equipped), "delete")
	delete.disabled = presets.size() < 2
	actions.add_child(delete)
	return box


func _equip(i: int) -> void:
	_message = ""
	Loadouts.equip(i)


func _copy(i: int) -> void:
	_message = "Copied. Edit the new loadout freely."
	Loadouts.duplicate_preset(i)


func _new_empty() -> void:
	_message = "A new empty loadout."
	Loadouts.add("", false)


func _restore_starters() -> void:
	_message = "The starter loadouts are back."
	_slot = 0
	_busy = true
	Profile.set_value(&"loadouts", Loadouts.starters())
	_busy = false
	Profile.set_value(&"loadout", 0)


func _delete(i: int) -> void:
	if not _confirm_delete:
		_confirm_delete = true
		refresh()
		return
	_message = "Deleted."
	Loadouts.remove(i)


# --- Slots ---------------------------------------------------------------------

func _slot_grid(preset: Dictionary) -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 18)
	grid.add_theme_constant_override(&"v_separation", 6)
	for i in Loadouts.SLOTS:
		grid.add_child(_slot_cell(preset, i))
	return grid


func _slot_cell(preset: Dictionary, i: int) -> Control:
	var jutsu := JutsuRegistry.get_jutsu(Loadouts.jutsu_in(preset, i))
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var pick := _button("%d  %s" % [i + 1, jutsu.display_name if jutsu else "empty"], _pick_slot.bind(i), "slot%d" % i)
	pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
	pick.add_theme_font_size_override(&"font_size", 20)
	pick.clip_text = true
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.custom_minimum_size = Vector2(120, 44)
	pick.tooltip_text = "Fill quick-cast slot %d" % (i + 1)
	if i == _slot:
		pick.add_theme_stylebox_override(&"normal", _selected_box())
	if jutsu == null:
		pick.add_theme_color_override(&"font_color", UiKit.INK_SOFT)
	row.add_child(pick)

	var instant := Loadouts.style_in(preset, i) == Loadouts.INSTANT
	var style := _button("Instant" if instant else "Weave", _toggle_style.bind(i, instant), "style%d" % i)
	style.custom_minimum_size = Vector2(92, 44)
	style.disabled = jutsu == null
	style.tooltip_text = "Cast style: Weave (seals formed for you) or Instant (no seals, +%d%% chakra)" \
		% roundi(Loadouts.INSTANT_SURCHARGE * 100.0)
	row.add_child(style)

	var clear := _button("×", _clear_slot.bind(i), "clear%d" % i)
	clear.custom_minimum_size = Vector2(40, 44)
	clear.disabled = jutsu == null
	clear.tooltip_text = "Empty this slot"
	row.add_child(clear)
	return row


func _pick_slot(i: int) -> void:
	_slot = i
	_message = ""
	refresh()


func _toggle_style(i: int, was_instant: bool) -> void:
	_message = ""
	Loadouts.set_style(i, Loadouts.WEAVE if was_instant else Loadouts.INSTANT)


func _clear_slot(i: int) -> void:
	_message = ""
	Loadouts.assign(i, &"")


# --- Jutsu catalog -------------------------------------------------------------

func _catalog_row(j: JutsuDefinition, preset: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	var stamp_color := UiKit.CRIMSON if j.element == Element.NONE else Element.color(j.element).darkened(0.35)
	var stamp := Hanko.make(Element.kanji(j.element), 48.0 if detailed else 40.0, stamp_color)
	stamp.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(stamp)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override(&"separation", 2)
	var title := HBoxContainer.new()
	title.add_theme_constant_override(&"separation", 12)
	title.add_child(UiKit.label(j.display_name, 22, UiKit.INK, &"display"))
	info.add_child(title)
	var tag := UiKit.label(UiKit.jutsu_tag(j), 16, UiKit.INK_SOFT, &"bold")
	info.add_child(tag)
	if detailed:
		var seals := HBoxContainer.new()
		seals.add_theme_constant_override(&"separation", 6)
		for i in j.seals.size():
			if i > 0:
				seals.add_child(UiKit.label("›", 22, UiKit.INK_SOFT, &"bold"))
			var s: int = j.seals[i]
			seals.add_child(UiKit.label(Seal.kanji(s), 24, UiKit.CRIMSON, &"brush"))
			seals.add_child(UiKit.label(Seal.display_name(s), 17, UiKit.INK, &"bold"))
			seals.add_child(UiKit.seal_glyphs(s, 24.0))
		info.add_child(seals)
	if j.description != "":
		var d := UiKit.label(j.description, 16, UiKit.INK_SOFT, &"body")
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size.x = 200
		d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(d)
	row.add_child(info)

	var held: int = (preset["slots"] as Array).find(String(j.id))
	var equip := _button("Equip" if held < 0 else "Slot %d" % (held + 1), _equip_to_slot.bind(j), "equip_%s" % j.id)
	equip.custom_minimum_size = Vector2(104, 44)
	equip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	equip.disabled = held == _slot
	equip.tooltip_text = "Put %s on quick-cast slot %d" % [j.display_name, _slot + 1]
	if held >= 0:
		equip.add_theme_stylebox_override(&"normal", _selected_box())
	row.add_child(equip)
	return row


func _ultimate_row(u: Dictionary, is_equipped: bool) -> Control:
	var element: int = u["element_id"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	var stamp_color := UiKit.CRIMSON if element == Element.NONE else Element.color(element).darkened(0.35)
	var stamp := Hanko.make(Element.kanji(element), 40.0, stamp_color)
	stamp.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(stamp)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override(&"separation", 2)
	var title := HBoxContainer.new()
	title.add_theme_constant_override(&"separation", 12)
	title.add_child(UiKit.label(u["name"], 22, UiKit.INK, &"display"))
	var kanji := UiKit.label(u["kanji"], 24, UiKit.CRIMSON, &"brush")
	kanji.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.add_child(kanji)
	info.add_child(title)
	info.add_child(UiKit.label("%s · power %d · reach %d m" % [
		"Any nature" if element == Element.NONE else Element.display_name(element) + " nature",
		int(u["power"]), roundi(float(u["radius"]))], 16, UiKit.INK_SOFT, &"bold"))
	var blurb := UiKit.label(u["blurb"], 16, UiKit.INK_SOFT, &"body")
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size.x = 200
	blurb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(blurb)
	row.add_child(info)
	var allowed := Ultimates.allowed(u, int(Profile.get_value(&"affinity")))
	var label := "Equipped" if is_equipped else ("Equip" if allowed else "%s only" % Element.display_name(element))
	var b := _button(label, _equip_ultimate.bind(str(u["id"])), "ult_%s" % u["id"])
	b.custom_minimum_size = Vector2(120, 44)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.disabled = is_equipped or not allowed
	if is_equipped:
		b.add_theme_stylebox_override(&"disabled", _selected_box())
	b.tooltip_text = "Your nature can't learn this one" if not allowed else ""
	row.add_child(b)
	return row


func _equip_ultimate(id: String) -> void:
	_message = "%s is your ultimate." % Ultimates.get_ultimate(id).get("name", id)
	Profile.set_value(&"ultimate", id)


func _equip_to_slot(j: JutsuDefinition) -> void:
	_message = "%s is on quick-cast slot %d." % [j.display_name, _slot + 1]
	_busy = true
	Loadouts.assign(_slot, j.id)
	_busy = false
	# Move on to the next empty slot, if there is one.
	var after := Loadouts.active()
	for step in range(1, Loadouts.SLOTS):
		var s := (_slot + step) % Loadouts.SLOTS
		if Loadouts.jutsu_in(after, s) == &"":
			_slot = s
			break
	_confirm_delete = false
	refresh()


# --- Widgets -------------------------------------------------------------------

func _section(title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	var mark := Hanko.make("", 12.0)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(mark)
	row.add_child(UiKit.label(title.to_upper(), 21, UiKit.CRIMSON, &"display"))
	return row


func _hint(text: String) -> Label:
	var l := UiKit.label(text, 16, UiKit.INK_SOFT, &"body")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 300
	return l


func _button(text: String, on_press: Callable, focus_key: String) -> Button:
	var b := Button.new()
	b.text = text
	b.set_meta(&"focus_key", focus_key)
	b.pressed.connect(on_press)
	return b


func _selected_box() -> StyleBoxFlat:
	var on := StyleBoxFlat.new()
	on.bg_color = Color(UiKit.CRIMSON, 0.16)
	on.border_color = UiKit.CRIMSON
	on.set_border_width_all(2)
	on.content_margin_left = 14
	on.content_margin_right = 14
	on.content_margin_top = 6
	on.content_margin_bottom = 6
	return on


func _focus_key() -> String:
	if not is_inside_tree():
		return ""
	var owner := get_viewport().gui_get_focus_owner()
	if owner and is_ancestor_of(owner) and owner.has_meta(&"focus_key"):
		return str(owner.get_meta(&"focus_key"))
	return ""


func _refocus(key: String) -> void:
	if not is_inside_tree():
		return
	for c in find_children("*", "Control", true, false):
		var ctl := c as Control
		if ctl.has_meta(&"focus_key") and ctl.get_meta(&"focus_key") == key and ctl.is_visible_in_tree():
			if ctl is BaseButton and (ctl as BaseButton).disabled:
				continue
			ctl.grab_focus()
			return
