extends TestCase
## Voice acting: every story line has a recording, playback follows the
## dialogue box, music ducks under it, and speakers' mouths move.


## Every [who, raw text] a story character says aloud.
func _spoken(story: Story) -> Array:
	var out := []
	for c: Dictionary in story.chapters:
		for b: Dictionary in c["beats"]:
			match b["do"]:
				"say":
					for line: Dictionary in b["lines"]:
						if line["who"] != Story.PLAYER:
							out.append([line["who"], line["text"]])
				"scene":
					for step: Dictionary in b["steps"]:
						if step["action"] == "say":
							for line: Dictionary in step["lines"]:
								if line["who"] != Story.PLAYER:
									out.append([line["who"], line["text"]])
				"boss":
					if b["taunt"] != "":
						out.append([b["who"], b["taunt"]])
					for phase: Dictionary in b["phases"]:
						if phase["say"] != "":
							out.append([b["who"], phase["say"]])
				"ally":
					out.append([b["who"], StoryDirector.ALLY_RETREAT_LINE])
	return out


func test_every_story_line_is_recorded() -> void:
	var story := Story.load_all()
	var lines := _spoken(story)
	assert_true(lines.size() > 100, "found the story's lines")
	var missing := PackedStringArray()
	for pair: Array in lines:
		var natures := [Element.FIRE, Element.WIND, Element.LIGHTNING, Element.EARTH, Element.WATER] \
			if String(pair[1]).contains("{nature}") else [int(Profile.get_value(&"affinity"))]
		for nature: int in natures:
			Profile.set_value(&"affinity", nature)
			if not Voice.has_line(pair[0], pair[1]):
				missing.append("%s: %s" % pair)
	assert_true(missing.is_empty(),
		"%d lines unrecorded (run art/audio/make_voices.py): %s" % [missing.size(), ", ".join(missing.slice(0, 3))])


func test_every_speaking_character_has_a_voice() -> void:
	var story := Story.load_all()
	for pair: Array in _spoken(story):
		var voice: Dictionary = story.characters[pair[0]]["voice"]
		assert_true(voice.has("speaker"), "%s has a voice" % pair[0])
		# Kokoro voice names ("af_heart"), optionally blended ("a*0.5+b*0.5").
		var ok := RegEx.create_from_string("^[a-z]{2}_[a-z]+(\\*[0-9.]+)?(\\+[a-z]{2}_[a-z]+(\\*[0-9.]+)?)*$")
		assert_true(voice.get("speaker") is String and ok.search(voice["speaker"]) != null,
			"%s: speaker names a Kokoro voice" % pair[0])


func test_player_and_unknown_lines_stay_silent() -> void:
	assert_false(Voice.speak(Story.PLAYER, "Tiger, then Ox."))
	assert_false(Voice.speak("hisame", "A line nobody wrote."))
	assert_false(Voice.is_speaking())


func test_dialogue_speaks_each_line_and_ducks_the_music() -> void:
	var story := Story.load_all()
	var box := DialogueBox.new()
	root.add_child(box)
	Music.play(&"calm", 0.05)
	var said := []
	Voice.started.connect(func(who: String) -> void: said.append(who))
	var first: Array = []
	for pair: Array in _spoken(story):
		if pair[0] == "hisame" and not String(pair[1]).contains("{nature}"):
			first = pair
			break
	box.play([{"who": "player", "text": "Ready.", "mood": ""},
		{"who": first[0], "text": first[1], "mood": ""}], story)
	assert_false(Voice.is_speaking(), "the player's line is silent")
	box._text.visible_ratio = 1.0
	box.advance()
	assert_eq(Voice.speaker, "hisame", "Hisame's line plays")
	assert_true(Music.is_ducked(), "music dips under the voice")
	box._text.visible_ratio = 1.0
	box.advance()
	assert_false(Voice.is_speaking(), "closing the dialogue stops the voice")
	assert_false(Music.is_ducked())
	assert_eq(said, ["hisame"])


func test_speaking_characters_move_their_mouths() -> void:
	var npc := StoryNpc.new()
	npc.who = "hisame"
	npc.model_name = "victoria_rubin"
	root.add_child(npc)
	await physics_frames(2)
	var model := npc.model
	assert_eq(model.voice_id, "hisame")
	assert_true(model.has_talking_mouth(), "VRoid mouth shapes found")
	model.set_mouth_open(1.0)
	var opened := 0.0
	for entry: Array in model._mouth:
		opened = maxf(opened, (entry[0] as MeshInstance3D).get_blend_shape_value(entry[1]))
	assert_true(opened > 0.4, "mouth opens")
	model.set_mouth_open(0.0)
	for entry: Array in model._mouth:
		assert_near((entry[0] as MeshInstance3D).get_blend_shape_value(entry[1]), 0.0)
