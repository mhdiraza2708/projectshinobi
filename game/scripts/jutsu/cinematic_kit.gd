class_name CinematicKit
extends RefCounted
## What the in-fight cinematics (ultimates, eye arts) share: stopping the
## world around the player while the camera looks at them, and the brush
## title card.


## Stops every fighter and projectile in `world` where it is (time stands
## still for everyone but the player) and hides the name tags. Returns what
## thaw() needs to start them again.
static func freeze(world: Node) -> Dictionary:
	var frozen := {}
	var tags: Array = []
	var stopped: Array[Node] = []
	stopped.append_array(world.find_children("*", "EnemyShinobi", true, false))
	stopped.append_array(world.find_children("*", "JutsuProjectile", true, false))
	stopped.append_array(world.find_children("*", "TrainingDummy", true, false))
	for n in stopped:
		frozen[n] = [n.process_mode, (n as CollisionObject3D).disable_mode if n is CollisionObject3D else 0]
		# Frozen, but still there to be hit (a disabled body otherwise leaves
		# the physics world).
		if n is CollisionObject3D:
			(n as CollisionObject3D).disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
		n.process_mode = Node.PROCESS_MODE_DISABLED
	# Name tags and health numbers would clutter the shots.
	for tag in world.find_children("*", "Label3D", true, false):
		if (tag as Label3D).visible:
			tag.visible = false
			tags.append(tag)
	return {"nodes": frozen, "tags": tags}


## Starts again what freeze() stopped (the shot may have finished some off).
static func thaw(state: Dictionary) -> void:
	var frozen: Dictionary = state.get("nodes", {})
	# Untyped: a blow may have finished some of them off.
	for n: Variant in frozen.keys():
		if is_instance_valid(n):
			(n as Node).process_mode = frozen[n][0]
			if n is CollisionObject3D:
				(n as CollisionObject3D).disable_mode = frozen[n][1]
	frozen.clear()
	for tag: Variant in state.get("tags", []):
		if not is_instance_valid(tag):
			continue
		# Not over someone just defeated.
		var owner_node := (tag as Node).get_parent()
		if not (owner_node.has_method(&"is_defeated") and owner_node.is_defeated()):
			(tag as Label3D).visible = true
	(state.get("tags", []) as Array).clear()


## A brush title card on the right of the screen: a small `tag` line, a big
## `kanji` and the `title`. It slams in, holds for `hold` seconds, then fades.
static func title_card(parent: Node, tag: String, kanji: String, title: String, color: Color, hold: float) -> CanvasLayer:
	var card := CanvasLayer.new()
	card.layer = 31
	parent.add_child(card)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(root)
	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 1.0
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_top = -190
	box.offset_bottom = 190
	box.offset_right = -70
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", -14)
	root.add_child(box)
	var tag_label := UiKit.label(tag, 30, UiKit.GOLD, &"display", 10)
	tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(tag_label)
	var big := UiKit.label(kanji, 190, color.lightened(0.25), &"brush", 26)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(big)
	var title_label := UiKit.label(title.to_upper(), 54, UiKit.PAPER, &"display", 14)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(title_label)
	# Slams in from the right, holds, then fades.
	box.modulate.a = 0.0
	box.pivot_offset = Vector2(600, 190)
	box.scale = Vector2(1.35, 1.35)
	var tw := box.create_tween().set_parallel()
	tw.tween_property(box, "modulate:a", 1.0, 0.18)
	tw.tween_property(box, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(maxf(0.1, hold - 0.55))
	tw.chain().tween_property(box, "modulate:a", 0.0, 0.25)
	return card


## A title card's text, for tests.
static func card_text(card: CanvasLayer) -> String:
	if not is_instance_valid(card):
		return ""
	var parts := PackedStringArray()
	for l in card.find_children("*", "Label", true, false):
		parts.append((l as Label).text)
	return " ".join(parts)
