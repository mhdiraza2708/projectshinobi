extends Node
## Background music. Autoloaded as `Music`.
##
## Tracks are the Ogg loops in res://assets/audio/music, made by
## art/audio/make_music.py, and are played by file name:
##   Music.play(&"battle")   # crossfades from whatever is playing
##   Music.stop()            # fades out
##   Music.duck(true)        # quieter while someone speaks
## A track that comes back picks up where it left off. Exported builds ship
## the music in audio_1.pck; without it the game is simply silent.
##
## Which track suits which place is decided here too: island_theme() for
## exploring and battle_for() for fights. The open world adds the sea and the
## night (OpenWorld.track_for) and the story its own picks (docs/STORY.md).

signal changed(track: StringName)

const DIR := "res://assets/audio/music/"
## Every track the game can ask for, one Ogg each in DIR (a test checks).
const TRACKS: Array[StringName] = [
	&"title", &"calm", &"battle", &"boss", &"autumn_wood", &"ashen_pass", &"old_dam", &"frozen_road",
	&"five_winds", &"night", &"sea", &"battle2", &"tension", &"sorrow",
]
## What plays while you explore each island (Emberwood's is "calm").
const ISLAND_THEMES := {
	"emberwood": &"calm", "autumn_wood": &"autumn_wood", "ashen_pass": &"ashen_pass",
	"old_dam": &"old_dam", "frozen_road": &"frozen_road", "five_winds": &"five_winds",
}
## The two fight themes: fight number 0 gets the first, 1 the second, and so on.
const BATTLES: Array[StringName] = [&"battle", &"battle2"]
const FADE := 1.4
const SILENT_DB := -50.0
## How far music drops under a voice line.
const DUCK_DB := -9.0
## Positions older than this are forgotten: a track heard long ago restarts.
const RESUME_WITHIN_MSEC := 90000

## The track playing (or fading in), or &"" for none.
var current: StringName = &""

var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _ducked := false
var _positions: Dictionary = {}   # track -> [seconds, ticks when left]
var _tweens: Array[Tween] = [null, null]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = Sfx.BUS_MUSIC
		p.volume_db = SILENT_DB
		add_child(p)
		_players.append(p)


func has_track(track: StringName) -> bool:
	return ResourceLoader.exists(DIR + track + ".ogg")


## The exploration theme of an island (calm for one without a theme of its own).
func island_theme(island: String) -> StringName:
	return ISLAND_THEMES.get(island, &"calm")


## The battle theme for the `count`th fight, so fights take turns.
func battle_for(count: int) -> StringName:
	return BATTLES[absi(count) % BATTLES.size()]


func tracks() -> PackedStringArray:
	var out := PackedStringArray()
	for f in ResourceLoader.list_directory(DIR):
		if f.get_extension() == "ogg":
			out.append(f.get_basename())
	return out


func is_playing() -> bool:
	return current != &""


## Crossfades to `track`. Playing the current track again changes nothing.
func play(track: StringName, fade := FADE) -> void:
	if track == current:
		return
	if not has_track(track):
		# Missing audio pack or a typo: stay quiet rather than fail.
		stop(fade)
		return
	_fade_out(_active, fade)
	_active = 1 - _active
	var p := _players[_active]
	var stream: AudioStream = load(DIR + track + ".ogg")
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	p.stream = stream
	p.volume_db = SILENT_DB
	var from := 0.0
	var last: Array = _positions.get(track, [])
	if not last.is_empty() and Time.get_ticks_msec() - int(last[1]) < RESUME_WITHIN_MSEC:
		from = float(last[0])
	p.play(from)
	_fade(_active, _level(), fade)
	current = track
	changed.emit(track)


func stop(fade := FADE) -> void:
	if current == &"":
		return
	_fade_out(_active, fade)
	current = &""
	changed.emit(&"")


## Lowers the music while a voice line plays (and brings it back after).
func duck(on: bool) -> void:
	if on == _ducked:
		return
	_ducked = on
	if current != &"":
		_fade(_active, _level(), 0.25)


func is_ducked() -> bool:
	return _ducked


func _level() -> float:
	return DUCK_DB if _ducked else 0.0


func _fade_out(index: int, fade: float) -> void:
	var p := _players[index]
	if not p.playing:
		return
	if current != &"":
		_positions[current] = [p.get_playback_position(), Time.get_ticks_msec()]
	_fade(index, SILENT_DB, fade, true)


func _fade(index: int, to_db: float, seconds: float, then_stop := false) -> void:
	if _tweens[index] and _tweens[index].is_valid():
		_tweens[index].kill()
	var p := _players[index]
	var tw := create_tween()
	tw.tween_property(p, "volume_db", to_db, maxf(seconds, 0.01))
	if then_stop:
		tw.tween_callback(p.stop)
	_tweens[index] = tw
