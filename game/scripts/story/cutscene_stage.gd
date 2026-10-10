class_name CutsceneStage
extends Node
## What a Cutscene needs from the place it plays in, for films that are not
## story beats (a fight's opening in the open world): the player, the HUD,
## the dialogue box, the node the action happens under, and no people on
## stage but whoever the film names (see Cutscene.extra). StoryDirector has
## the same members, so a Cutscene plays under either.

var player: Player
var hud: Hud
var dialogue: DialogueBox
var stage: Node3D
var story: Story
var npcs: Dictionary = {}


func add_npc(_who: String, _at: Vector2, _quiet := false, _from: Variant = null) -> Node3D:
	return null


func remove_npc(_who: String, _puff := true) -> void:
	pass
