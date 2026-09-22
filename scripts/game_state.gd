extends Node
## Autoloaded player settings, persisted to `user://settings.cfg`.
##
## Kept deliberately small: the three mix levels, a quality switch (shadows +
## particle budget) and the blood toggle. The arena and the audio director read
## these, so a change made in the pause menu applies immediately and survives
## a reload — including on the web build, where Godot maps user:// onto
## IndexedDB.

signal settings_changed

const PATH := "user://settings.cfg"

var master := 0.85
var music := 0.55
var ambience := 0.75
var quality_high := true
var blood := true


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	master = cfg.get_value("audio", "master", master)
	music = cfg.get_value("audio", "music", music)
	ambience = cfg.get_value("audio", "ambience", ambience)
	quality_high = cfg.get_value("video", "quality_high", quality_high)
	blood = cfg.get_value("video", "blood", blood)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master)
	cfg.set_value("audio", "music", music)
	cfg.set_value("audio", "ambience", ambience)
	cfg.set_value("video", "quality_high", quality_high)
	cfg.set_value("video", "blood", blood)
	cfg.save(PATH)


func apply() -> void:
	settings_changed.emit()
	save_settings()
