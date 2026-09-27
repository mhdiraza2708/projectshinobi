extends Node
## Voiced story lines. Autoloaded as `Voice`.
##
## Recordings are made by art/audio/make_voices.py and live at
## res://assets/audio/voice/<who>/<key>.ogg, keyed by the line exactly as
## written in the story JSON (see key()). A line without a recording, and
## every line the player speaks, is simply silent. Music ducks while a line
## plays. Exported builds ship the voices in audio_1.pck.
##   Voice.speak("hisame", "You're late, {name}.")
##   Voice.stop()

signal started(who: String)
signal finished(who: String)

const DIR := "res://assets/audio/voice/"

## Who is speaking right now, or "" when nobody is.
var speaker := ""

var _player: AudioStreamPlayer
var _bus := -1


func _ready() -> void:
	# Pauses with the game (a line stops mid-word under the pause menu).
	_player = AudioStreamPlayer.new()
	_player.bus = Sfx.BUS_VOICE
	_player.process_mode = Node.PROCESS_MODE_PAUSABLE
	_player.finished.connect(_on_finished)
	add_child(_player)
	_bus = AudioServer.get_bus_index(Sfx.BUS_VOICE)


## The recording's file name: md5 of "<who>|<text as written>", plus
## "|<nature>" when the line mentions the player's nature. Must match
## Line.key in make_voices.py.
static func key(who: String, raw: String) -> String:
	var text := "%s|%s" % [who, raw]
	if raw.contains("{nature}"):
		text += "|" + Element.display_name(int(Profile.get_value(&"affinity"))).to_lower()
	return text.md5_text().substr(0, 12)


static func path_for(who: String, raw: String) -> String:
	return DIR.path_join(who).path_join(key(who, raw) + ".ogg")


static func has_line(who: String, raw: String) -> bool:
	return ResourceLoader.exists(path_for(who, raw))


## Starts `who` saying `raw`, cutting off whatever was playing. Returns
## false (and stays silent) when there's no recording.
func speak(who: String, raw: String) -> bool:
	stop()
	if who == Story.PLAYER or not has_line(who, raw):
		return false
	_player.stream = load(path_for(who, raw))
	_player.play()
	speaker = who
	Music.duck(true)
	started.emit(who)
	return true


func stop() -> void:
	if speaker == "":
		return
	_player.stop()
	_on_finished()


func is_speaking() -> bool:
	return speaker != ""


## How loud the voice is right now, 0-1 (drives lip sync).
func level() -> float:
	if speaker == "" or _bus < 0:
		return 0.0
	var db := maxf(AudioServer.get_bus_peak_volume_left_db(_bus, 0), AudioServer.get_bus_peak_volume_right_db(_bus, 0))
	return clampf((db + 42.0) / 30.0, 0.0, 1.0)


func _on_finished() -> void:
	var who := speaker
	speaker = ""
	Music.duck(false)
	if who != "":
		finished.emit(who)
