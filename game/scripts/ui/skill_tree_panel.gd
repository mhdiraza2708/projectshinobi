class_name SkillTreePanel
extends VBoxContainer
## The skill screen's paper (SkillScreen): your level and XP, points to
## spend, and one skill tree at a time drawn as ink seals joined by brush
## lines. Press a
## node (A / click) to learn a rank; the card on the right says what it does
## now and next, and what it still needs. Points can be taken back for free.
## Fully navigable with a controller: the D-pad walks the tree, up from the
## top reaches the tree tabs and the reset buttons.

const NODE_SIZE := 68.0
const CAPSTONE_SIZE := 86.0
const COL_STEP := 168.0
const TIER_STEP := 76.0
const GUTTER := 92.0

signal tree_changed(id: String)

var tree_id := ""
## The tree tabs on the paper (the skill screen draws its own above it).
var show_tabs := true
## The full screen's layout: the tree larger, with its card beneath it.
var screen_mode := false
const SCREEN_SCALE := 1.22

var _level: Label
var _xp_bar: InkBar
var _xp_text: Label
var _points: Label
var _tree_buttons: Dictionary = {}
var _reset_tree: Button
var _reset_all: Button
var _canvas: TreeCanvas
var _nodes: Dictionary = {}
var _card_kanji: Label
var _card_name: Label
var _card_rank: Label
var _card_lines: Label
var _card_need: Label
var _card_hint: Label
var _blurb: Label
var _shown := ""
var _confirm_reset := false


func _init() -> void:
	add_theme_constant_override(&"separation", 10)


func _ready() -> void:
	tree_id = SkillTrees.trees()[0]["id"] if not SkillTrees.trees().is_empty() else ""
	_build()
	Game.skills_changed.connect(refresh)
	Game.xp_gained.connect(func(_a: int, _r: String) -> void: refresh())
	refresh()


# --- Layout ----------------------------------------------------------------------

func _build() -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 8)
	add_child(head)
	for t in SkillTrees.trees():
		var b := Button.new()
		b.add_theme_font_size_override(&"font_size", 22)
		b.pressed.connect(_show_tree.bind(str(t["id"])))
		b.visible = show_tabs
		head.add_child(b)
		_tree_buttons[t["id"]] = b
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	_level = UiKit.label("", 34, UiKit.CRIMSON, &"display")
	_level.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_level)
	var xp := VBoxContainer.new()
	xp.add_theme_constant_override(&"separation", 0)
	xp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_xp_bar = InkBar.new()
	_xp_bar.ink_color = UiKit.GOLD
	_xp_bar.seed = 7.0
	_xp_bar.custom_minimum_size = Vector2(260, 20)
	xp.add_child(_xp_bar)
	_xp_text = UiKit.label("", 15, UiKit.INK_SOFT, &"bold")
	xp.add_child(_xp_text)
	head.add_child(xp)
	_points = UiKit.label("", 24, UiKit.INK, &"bold")
	_points.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_points)
	var edge := Control.new()
	edge.custom_minimum_size.x = 12
	head.add_child(edge)

	var resets := HBoxContainer.new()
	resets.add_theme_constant_override(&"separation", 8)
	_reset_tree = Button.new()
	_reset_tree.pressed.connect(func() -> void:
		SkillTrees.reset(tree_id)
		Sfx.ui(&"ui_back"))
	resets.add_child(_reset_tree)
	_reset_all = Button.new()
	_reset_all.pressed.connect(func() -> void:
		if not _confirm_reset:
			_confirm_reset = true
			_reset_all.text = "Press again to reset all"
			return
		_confirm_reset = false
		SkillTrees.reset()
		Sfx.ui(&"ui_back"))
	_reset_all.focus_exited.connect(func() -> void:
		_confirm_reset = false
		refresh())
	resets.add_child(_reset_all)

	var body: BoxContainer = VBoxContainer.new() if screen_mode else HBoxContainer.new()
	body.add_theme_constant_override(&"separation", 12 if screen_mode else 28)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	_canvas = TreeCanvas.new()
	var canvas_size := Vector2(GUTTER + COL_STEP * (SkillTrees.COLUMNS - 1) + CAPSTONE_SIZE + 24,
		TIER_STEP * 4 + CAPSTONE_SIZE + 14)
	_canvas.custom_minimum_size = canvas_size
	if screen_mode:
		# Scaled up on the big screen; the holder reserves the scaled size.
		var holder := Control.new()
		holder.custom_minimum_size = canvas_size * SCREEN_SCALE
		holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_canvas.scale = Vector2.ONE * SCREEN_SCALE
		holder.add_child(_canvas)
		body.add_child(holder)
	else:
		body.add_child(_canvas)

	var card := VBoxContainer.new()
	card.add_theme_constant_override(&"separation", 6)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if screen_mode:
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(card)
	_blurb = UiKit.label("", 17, UiKit.INK_SOFT, &"bold")
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_blurb.custom_minimum_size.x = 900 if screen_mode else 520
	card.add_child(_blurb)
	var title := HBoxContainer.new()
	title.add_theme_constant_override(&"separation", 14)
	_card_kanji = UiKit.label("", 64, UiKit.INK, &"brush")
	title.add_child(_card_kanji)
	var names := VBoxContainer.new()
	names.add_theme_constant_override(&"separation", -4)
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_card_name = UiKit.label("", 30, UiKit.CRIMSON, &"display")
	names.add_child(_card_name)
	_card_rank = UiKit.label("", 18, UiKit.INK_SOFT, &"bold")
	names.add_child(_card_rank)
	title.add_child(names)
	card.add_child(title)
	for l: Label in [UiKit.label("", 20, UiKit.INK, &"bold"), UiKit.label("", 18, UiKit.CRIMSON_DARK, &"bold"),
			UiKit.label("", 17, UiKit.INK_SOFT, &"bold")]:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 900 if screen_mode else 520
		card.add_child(l)
	_card_lines = card.get_child(2)
	_card_need = card.get_child(3)
	_card_hint = card.get_child(4)
	var push := Control.new()
	push.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(push)
	card.add_child(resets)
	_show_tree(tree_id, false)


## Switches the tree shown (and builds its nodes).
func show_tree(id: String, focus := true) -> void:
	_show_tree(id, focus)


func _show_tree(id: String, focus := true) -> void:
	var changed := id != tree_id
	tree_id = id
	for c in _canvas.get_children():
		_canvas.remove_child(c)
		c.queue_free()
	_nodes.clear()
	var t := SkillTrees.tree(id)
	if t.is_empty():
		return
	_canvas.color = Color(str(t["color"]))
	_canvas.links.clear()
	_canvas.tiers.clear()
	for tier in range(2, 6):
		var need := SkillTrees.tier_points(tier)
		if need > 0:
			_canvas.tiers.append([_row_y(tier) + NODE_SIZE * 0.5, need])
	for n: Dictionary in t["nodes"]:
		var b := SkillNodeButton.new()
		b.node_id = n["id"]
		b.kanji = n["kanji"]
		b.color = _canvas.color
		b.capstone = int(n["tier"]) == 5
		var s := CAPSTONE_SIZE if b.capstone else NODE_SIZE
		b.size = Vector2(s, s)
		b.custom_minimum_size = b.size
		b.position = _center(n) - b.size * 0.5
		b.pressed.connect(_learn.bind(str(n["id"])))
		b.focus_entered.connect(_show_node.bind(str(n["id"])))
		b.mouse_entered.connect(_show_node.bind(str(n["id"])))
		_canvas.add_child(b)
		_nodes[n["id"]] = b
		for req: String in n["requires"]:
			_canvas.links.append([req, n["id"]])
	_canvas.centers = {}
	for id2: String in _nodes:
		_canvas.centers[id2] = _center(SkillTrees.node(id2))
	_wire_focus()
	_blurb.text = str(t["blurb"])
	_shown = str(t["nodes"][0]["id"])
	refresh()
	if focus:
		(_nodes[_shown] as Control).grab_focus()
	if changed:
		tree_changed.emit(id)


func _row_y(tier: int) -> float:
	return 6.0 + (tier - 1) * TIER_STEP


func _center(n: Dictionary) -> Vector2:
	var tier := int(n["tier"])
	var s := CAPSTONE_SIZE if tier == 5 else NODE_SIZE
	return Vector2(GUTTER + int(n["col"]) * COL_STEP + CAPSTONE_SIZE * 0.5, _row_y(tier) + s * 0.5)


## The D-pad walks the tree: up and down to the nearest node a tier away,
## left and right along the tier; up from the top reaches the tree tabs.
func _wire_focus() -> void:
	var tab: Button = _tree_buttons[tree_id] if show_tabs else null
	for id: String in _nodes:
		var b: SkillNodeButton = _nodes[id]
		var n := SkillTrees.node(id)
		var up := _nearest(n, -1)
		var down := _nearest(n, 1)
		b.focus_neighbor_top = b.get_path_to(_nodes[up] if up != "" else (tab if tab else b))
		b.focus_neighbor_bottom = b.get_path_to(_nodes[down] if down != "" else b)
		var left := _beside(n, -1)
		var right := _beside(n, 1)
		b.focus_neighbor_left = b.get_path_to(_nodes[left] if left != "" else b)
		b.focus_neighbor_right = b.get_path_to(_nodes[right] if right != "" else b)
	for t: String in _tree_buttons:
		var first: String = SkillTrees.tree(tree_id)["nodes"][0]["id"]
		(_tree_buttons[t] as Button).focus_neighbor_bottom = (_tree_buttons[t] as Button).get_path_to(_nodes[first])
	# Right from the tree's right-hand side reaches the reset buttons.
	for id: String in _nodes:
		var b: SkillNodeButton = _nodes[id]
		if _beside(SkillTrees.node(id), 1) == "":
			b.focus_neighbor_right = b.get_path_to(_reset_tree)
	_reset_tree.focus_neighbor_left = _reset_tree.get_path_to(_nodes[SkillTrees.tree(tree_id)["nodes"][0]["id"]])


func _nearest(n: Dictionary, direction: int) -> String:
	var best := ""
	var best_d := INF
	for id: String in _nodes:
		var o := SkillTrees.node(id)
		if int(o["tier"]) != int(n["tier"]) + direction:
			continue
		var d := absf(float(o["col"]) - float(n["col"]))
		if d < best_d:
			best_d = d
			best = id
	return best


func _beside(n: Dictionary, direction: int) -> String:
	var best := ""
	var best_d := INF
	for id: String in _nodes:
		var o := SkillTrees.node(id)
		var d := (int(o["col"]) - int(n["col"])) * direction
		if int(o["tier"]) == int(n["tier"]) and d > 0 and d < best_d:
			best_d = d
			best = id
	return best


# --- State -----------------------------------------------------------------------

func refresh() -> void:
	if _level == null:
		return
	var level := SkillTrees.level()
	_level.text = "Lv %d" % level
	_xp_bar.set_ratio_instant(SkillTrees.level_progress())
	if level >= SkillTrees.max_level():
		_xp_text.text = "%d XP · the highest level" % Game.xp()
	else:
		_xp_text.text = "%d / %d XP to level %d" % [Game.xp() - SkillTrees.xp_for_level(level),
			SkillTrees.xp_to_next(level), level + 1]
	var free := SkillTrees.points_free()
	_points.text = "%d skill point%s" % [free, "" if free == 1 else "s"]
	_points.add_theme_color_override(&"font_color", UiKit.CRIMSON if free > 0 else UiKit.INK_SOFT)
	for id: String in _tree_buttons:
		var t := SkillTrees.tree(id)
		var b: Button = _tree_buttons[id]
		b.text = "%s  %s · %d" % [t["kanji"], str(t["name"]).trim_prefix("Way of ").trim_prefix("the "),
			SkillTrees.points_spent(id)]
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0, 0, 0, 0)
		box.border_width_bottom = 4 if id == tree_id else 0
		box.border_color = Color(str(t["color"]))
		box.content_margin_left = 12
		box.content_margin_right = 12
		box.content_margin_top = 4
		box.content_margin_bottom = 4
		b.add_theme_stylebox_override(&"normal", box)
		b.add_theme_color_override(&"font_color", UiKit.INK if id == tree_id else UiKit.INK_SOFT)
	_reset_tree.text = "Reset %s" % str(SkillTrees.tree(tree_id).get("name", "")).trim_prefix("Way of ").trim_prefix("the ")
	_reset_tree.disabled = SkillTrees.points_spent(tree_id) == 0
	if not _confirm_reset:
		_reset_all.text = "Reset all"
	_reset_all.disabled = SkillTrees.points_spent() == 0
	for id: String in _nodes:
		var b: SkillNodeButton = _nodes[id]
		b.rank = SkillTrees.rank(id)
		b.ranks = int(SkillTrees.node(id)["ranks"])
		b.state = SkillTrees.can_learn(id)
		b.queue_redraw()
	_canvas.ranks = {}
	for id: String in _nodes:
		_canvas.ranks[id] = SkillTrees.rank(id)
	_canvas.spent = SkillTrees.points_spent(tree_id)
	_canvas.queue_redraw()
	_show_node(_shown)


func _show_node(id: String) -> void:
	var n := SkillTrees.node(id)
	if n.is_empty():
		return
	_shown = id
	var r := SkillTrees.rank(id)
	var ranks := int(n["ranks"])
	_card_kanji.text = str(n["kanji"])
	_card_kanji.add_theme_color_override(&"font_color", _canvas.color.darkened(0.15) if r > 0 else UiKit.INK)
	_card_name.text = str(n["name"])
	_card_rank.text = "%sRank %d / %d" % ["Final skill · " if int(n["tier"]) == 5 else "", r, ranks]
	var lines := PackedStringArray()
	if r > 0:
		lines.append("Now: " + ", ".join(Perks.describe(SkillTrees.perks_at(id, r))))
	if r < ranks:
		lines.append(("Next: " if r > 0 else "") + ", ".join(Perks.describe(SkillTrees.perks_at(id, r + 1))))
	_card_lines.text = "\n".join(lines)
	var need := ""
	match SkillTrees.can_learn(id):
		SkillTrees.NEEDS_NODE:
			var names := (n["requires"] as Array).map(func(q: String) -> String: return str(SkillTrees.node(q)["name"]))
			need = "Learn %s first." % " or ".join(PackedStringArray(names))
		SkillTrees.NEEDS_POINTS:
			need = "Spend %d points in this tree to open this tier (%d so far)." % [
				SkillTrees.tier_points(int(n["tier"])), SkillTrees.points_spent(str(n["tree"]))]
		SkillTrees.NO_POINTS:
			need = "No skill points left: fights, chapters and trials give XP, and every level gives a point."
		SkillTrees.NEEDS_EYE:
			need = "Only a shinobi born with an eye art can walk this way (choose one in Customize → Eyes)."
	_card_need.text = need
	var hint := ""
	if SkillTrees.can_learn(id) == SkillTrees.OK:
		hint = "%s  learn a rank" % InputDevice.glyph(&"ui_accept") if InputDevice.current == Binding.Device.GAMEPAD \
			else "Click or Enter: learn a rank"
	for key: String in n["perks"]:
		if Perks.FLAG_TEXT.has(key) and Perks.base_value(StringName(key)) > 0.0:
			hint += ("\n" if hint != "" else "") + "Your clan or eye art already gives you this."
	_card_hint.text = hint


func _learn(id: String) -> void:
	_shown = id
	if SkillTrees.learn(id):
		Sfx.ui(&"ui_select")
		(_nodes[id] as SkillNodeButton).pop()
	else:
		Sfx.ui(&"ui_back")
		_show_node(id)


## The tree drawn behind the nodes: brush lines between linked nodes (inked
## once the lower one is learned) and each tier's point gate down the left.
class TreeCanvas extends Control:
	var color := UiKit.CRIMSON
	var links: Array = []
	var centers: Dictionary = {}
	var ranks: Dictionary = {}
	var tiers: Array = []
	var spent := 0

	func _draw() -> void:
		for link: Array in links:
			if not centers.has(link[0]) or not centers.has(link[1]):
				continue
			var a: Vector2 = centers[link[0]]
			var b: Vector2 = centers[link[1]]
			# Inked once both ends are learned, faint once the way is open.
			var lit := int(ranks.get(link[0], 0)) > 0 and int(ranks.get(link[1], 0)) > 0
			var c := color.darkened(0.1) if lit else Color(UiKit.INK, 0.22)
			if not lit and int(ranks.get(link[0], 0)) > 0:
				c = Color(color, 0.55)
			draw_line(a, b, Color(c, c.a * 0.35), 12.0 if lit else 6.0, true)
			draw_line(a, b, c, 5.0 if lit else 3.0, true)
		var f := UiKit.font(&"bold")
		for gate: Array in tiers:
			var y: float = gate[0]
			var open := spent >= int(gate[1])
			var c := Color(UiKit.INK, 0.55) if open else UiKit.CRIMSON_DARK
			draw_dashed_line(Vector2(4, y), Vector2(SkillTreePanel.GUTTER - 18, y), Color(c, 0.4), 2.0, 6.0)
			var pts := int(gate[1])
			draw_string(f, Vector2(4, y - 8), "%d pt%s" % [pts, "" if pts == 1 else "s"], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, c)
