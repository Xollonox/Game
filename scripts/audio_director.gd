extends Node
## Autoloaded audio director: music state, ambience beds and interface sounds.
##
## Two ambience beds run under the arena (crowd + open-air wind) and the music
## crossfades between the menu theme and the fight theme, so entering a duel
## has an audible threshold rather than a hard cut. Every stream loops
## natively (AudioStreamOggVorbis.loop), so nothing here relies on a timer
## restarting playback.
##
## Music and ambience are CC0 tracks (see assets/CREDITS.md); UI clicks come
## from Kenney's CC0 interface set.

const MUSIC_MENU := "res://assets/audio/Loop_The_Old_Tower_Inn.ogg"
const MUSIC_FIGHT := "res://assets/audio/Loop_Rejoicing.ogg"
const AMB_CROWD := "res://assets/audio/Ambience_Crowd.ogg"
const AMB_WIND := "res://assets/audio/Forest_Ambience.ogg"

const UI_CLICKS := [
	"res://assets/audio/ui/click1.ogg",
	"res://assets/audio/ui/click2.ogg",
	"res://assets/audio/ui/click3.ogg",
]
const UI_HOVERS := [
	"res://assets/audio/ui/switch1.ogg",
	"res://assets/audio/ui/switch2.ogg",
]

const FADE := 1.1

var _music: AudioStreamPlayer
var _crowd: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _ui: AudioStreamPlayer
var _clicks: Array[AudioStream] = []
var _hovers: Array[AudioStream] = []
var _ui_index := 0
var _current_music := ""


func _ready() -> void:
	# Music must survive the pause menu, which pauses the rest of the tree.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	add_child(_music)
	_crowd = AudioStreamPlayer.new()
	_crowd.name = "Crowd"
	add_child(_crowd)
	_wind = AudioStreamPlayer.new()
	_wind.name = "Wind"
	add_child(_wind)
	_ui = AudioStreamPlayer.new()
	_ui.name = "UI"
	add_child(_ui)

	for path in UI_CLICKS:
		if ResourceLoader.exists(path):
			_clicks.append(load(path))
	for path in UI_HOVERS:
		if ResourceLoader.exists(path):
			_hovers.append(load(path))

	_crowd.stream = _looped(AMB_CROWD)
	_wind.stream = _looped(AMB_WIND)
	GameState.settings_changed.connect(_apply_volumes)
	_apply_volumes()


func _looped(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var s: AudioStream = load(path)
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	elif s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = true
	# WAV loops are set in the .import (edit/loop_mode): setting loop_end at
	# runtime to the full frame count points one frame past the buffer and
	# the mixer crashes when it wraps.
	return s


func _apply_volumes() -> void:
	_music.volume_db = _db(GameState.master * GameState.music)
	_crowd.volume_db = _db(GameState.master * GameState.ambience * 0.5) - 6.0
	_wind.volume_db = _db(GameState.master * GameState.ambience * 0.35) - 8.0
	_ui.volume_db = _db(GameState.master * 0.8) - 4.0


static func _db(linear: float) -> float:
	return linear_to_db(maxf(linear, 0.0008))


## Crossfades to a new track; re-requesting the current track is a no-op, so
## callers can be careless about calling this every time a scene loads.
func play_music(path: String) -> void:
	if path == _current_music and _music.playing:
		return
	_current_music = path
	var target := _looped(path)
	if target == null:
		return
	if not _music.playing:
		_music.stream = target
		_music.volume_db = -40.0
		_music.play()
		var t := create_tween()
		t.tween_property(_music, "volume_db", _db(GameState.master * GameState.music), FADE)
		return
	var tween := create_tween()
	tween.tween_property(_music, "volume_db", -40.0, FADE * 0.5)
	tween.tween_callback(func():
		_music.stream = target
		_music.play())
	tween.tween_property(_music, "volume_db", _db(GameState.master * GameState.music), FADE * 0.5)


func play_menu_music() -> void:
	play_music(MUSIC_MENU)


func play_fight_music() -> void:
	play_music(MUSIC_FIGHT)


func start_ambience() -> void:
	_wind.pitch_scale = 1.0
	if _crowd.stream and not _crowd.playing:
		_crowd.play()
	if _wind.stream and not _wind.playing:
		_wind.play()


func stop_ambience() -> void:
	_crowd.stop()
	_wind.stop()


func ui_click() -> void:
	if _clicks.is_empty():
		return
	_ui.stream = _clicks[_ui_index % _clicks.size()]
	_ui_index += 1
	_ui.pitch_scale = randf_range(0.97, 1.04)
	_ui.play()


func ui_hover() -> void:
	if _hovers.is_empty():
		return
	_ui.stream = _hovers[_ui_index % _hovers.size()]
	_ui_index += 1
	_ui.pitch_scale = randf_range(1.22, 1.30)
	_ui.volume_db = _db(GameState.master * 0.35) - 10.0
	_ui.play()


## The crowd reacts: a swell of the crowd bed, scaled by how much it liked it.
func crowd_cheer(strength: float) -> void:
	if not _crowd.stream:
		return
	if not _crowd.playing:
		_crowd.play()
	var base := _db(GameState.master * GameState.ambience)
	var t := create_tween()
	t.tween_property(_crowd, "volume_db", base + lerpf(2.0, 7.0, clampf(strength, 0.0, 1.0)), 0.35)
	t.tween_interval(1.2 + strength)
	t.tween_property(_crowd, "volume_db", base, 2.5)


## The Hollow: no crowd, no music — only the wind, slowed until it groans.
func hollow_ambience() -> void:
	_crowd.stop()
	play_music("res://assets/audio/Hollow_Drone.wav")
	if _wind.stream:
		_wind.pitch_scale = 0.55
		_wind.volume_db = _db(GameState.master * GameState.ambience) + 3.0
		if not _wind.playing:
			_wind.play()


func restore_ambience() -> void:
	_wind.pitch_scale = 1.0
	_apply_volumes()
