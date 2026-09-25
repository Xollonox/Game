extends Node
## Autoloaded player settings, persisted to `user://settings.cfg`.
##
## Kept deliberately small: the three mix levels, a graphics preset (Low /
## Medium / High / Ultra, see apply_video) with automatic resolution scaling,
## and the blood toggle. The arena and the audio director read
## these, so a change made in the pause menu applies immediately and survives
## a reload — including on the web build, where Godot maps user:// onto
## IndexedDB.

signal settings_changed

const PATH := "user://settings.cfg"

var master := 0.85
var music := 0.55
var ambience := 0.75
enum Quality { LOW, MEDIUM, HIGH, ULTRA }
const QUALITY_NAMES := ["Low", "Medium", "High", "Ultra"]
## The graphics preset. Defaults by platform the first time (see _default_quality).
var quality: int = Quality.HIGH
## Lower the 3D resolution on its own when the frame rate drops, and raise it
## back when there is headroom: keeps the fight smooth on weak devices.
var auto_resolution := true
var blood := true

## Shadows and full particle budgets (Medium and up).
var quality_high: bool:
	get:
		return quality >= Quality.MEDIUM

# Per preset: 3D render scale ceiling, shadow atlas size (0 = off), soft
# shadow filter, MSAA, particle budget.
const _PRESETS := [
	{"scale": 0.7, "shadow": 0, "soft": 0, "msaa": Viewport.MSAA_DISABLED, "fx": 0.45},
	{"scale": 0.85, "shadow": 1024, "soft": 1, "msaa": Viewport.MSAA_DISABLED, "fx": 0.7},
	{"scale": 1.0, "shadow": 2048, "soft": 2, "msaa": Viewport.MSAA_2X, "fx": 1.0},
	{"scale": 1.0, "shadow": 4096, "soft": 3, "msaa": Viewport.MSAA_4X, "fx": 1.25},
]
const _MIN_SCALE := 0.5
var render_scale := 1.0
var _fps_avg := 60.0
var _slow_t := 0.0
var _fast_t := 0.0
var _has_saved := false


func _ready() -> void:
	load_settings()
	if not _has_saved:
		quality = _default_quality()
	load_run()
	apply_video()


## First-run guess: phones get Low, the web Medium, desktops High. Automatic
## resolution then trims it to what the device actually sustains.
func _default_quality() -> int:
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		return Quality.LOW
	if OS.has_feature("web"):
		return Quality.MEDIUM
	return Quality.HIGH


func preset() -> Dictionary:
	return _PRESETS[clampi(quality, 0, _PRESETS.size() - 1)]


## Particle budget multiplier for the current preset.
func fx_scale() -> float:
	return float(preset()["fx"])


## Pushes the preset into the renderer: render scale, MSAA, shadow atlas and
## filter. Scene-side settings (the sun's shadow, environment effects) are
## read by the scenes on settings_changed.
func apply_video() -> void:
	var p := preset()
	render_scale = float(p["scale"])
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = render_scale
		vp.msaa_3d = p["msaa"]
		# FXAA is nearly free and hides the stair-stepping a lowered
		# resolution brings.
		if _has_fxaa():
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if render_scale < 1.0 or quality == Quality.LOW \
				else Viewport.SCREEN_SPACE_AA_DISABLED
	if int(p["shadow"]) > 0:
		RenderingServer.directional_shadow_atlas_set_size(int(p["shadow"]), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(int(p["soft"]))
	RenderingServer.positional_soft_shadow_filter_set_quality(int(p["soft"]))
	_slow_t = 0.0
	_fast_t = 0.0


## Automatic resolution: a frame rate held under ~83 % of the target (60, or
## the display's own refresh rate if lower) steps the 3D resolution down (to
## half at worst); sustained headroom steps it back up to the preset's own
## scale. The HUD and text always render at full resolution.
func _process(delta: float) -> void:
	if not auto_resolution or delta <= 0.0 or DisplayServer.get_name() == "headless":
		return
	_fps_avg = lerpf(_fps_avg, 1.0 / delta, 1.0 - exp(-delta * 2.0))
	var hz := DisplayServer.screen_get_refresh_rate()
	var target := minf(60.0, hz * 0.98) if hz > 1.0 else 60.0
	var ceiling := float(preset()["scale"])
	if _fps_avg < target * 0.83 and render_scale > _MIN_SCALE:
		_slow_t += delta
		_fast_t = 0.0
		if _slow_t > 1.5:
			_set_scale(render_scale - 0.1)
	elif _fps_avg > target * 0.96 and render_scale < ceiling:
		_fast_t += delta
		_slow_t = 0.0
		if _fast_t > 5.0:
			_set_scale(minf(ceiling, render_scale + 0.05))
	else:
		_slow_t = 0.0
		_fast_t = 0.0


func _set_scale(s: float) -> void:
	render_scale = clampf(s, _MIN_SCALE, 1.0)
	_slow_t = 0.0
	_fast_t = 0.0
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_scale = render_scale
		if render_scale < 1.0 and _has_fxaa():
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA


## Screen-space AA exists in Forward+ / Mobile, not in the web renderer.
func _has_fxaa() -> bool:
	return RenderingServer.get_current_rendering_method() != "gl_compatibility"


## Steps to the next preset (the settings button cycles Low → Ultra).
func cycle_quality() -> void:
	quality = (quality + 1) % _PRESETS.size()
	apply()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	master = cfg.get_value("audio", "master", master)
	music = cfg.get_value("audio", "music", music)
	ambience = cfg.get_value("audio", "ambience", ambience)
	_has_saved = cfg.has_section_key("video", "quality") or cfg.has_section_key("video", "quality_high")
	if cfg.has_section_key("video", "quality"):
		quality = int(cfg.get_value("video", "quality", quality))
	elif cfg.has_section_key("video", "quality_high"):
		quality = Quality.HIGH if cfg.get_value("video", "quality_high", true) else Quality.LOW
	auto_resolution = cfg.get_value("video", "auto_resolution", auto_resolution)
	blood = cfg.get_value("video", "blood", blood)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master)
	cfg.set_value("audio", "music", music)
	cfg.set_value("audio", "ambience", ambience)
	cfg.set_value("video", "quality", quality)
	cfg.set_value("video", "auto_resolution", auto_resolution)
	cfg.set_value("video", "blood", blood)
	cfg.save(PATH)


func apply() -> void:
	apply_video()
	settings_changed.emit()
	save_settings()


# ------------------------------------------------------------------ run -----
## The persistent run: who you are, how far you have climbed, what you carry,
## and whose blood is on your hands (the Hollow remembers). Saved to
## user://run.cfg after every bout so a closed tab resumes where it left off.

const RUN_PATH := "user://run.cfg"

var run: Dictionary = {}


func has_run() -> bool:
	return not run.is_empty() and not run.get("over", false)


func new_run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	run = {
		"seed": rng.randi(),
		"bout": 0,
		"renown": 0,
		"player": Armory.starting_kit(rng),
		"slain": [],
		"slain_total": 0,
		"hollow_debt": [],
		"returns": 0,
		"best_bout": 0,
		"over": false,
		"mode": "arena",
		"purse": Shop.STARTING_PURSE,
	}
	Shop.ensure(run)
	save_run()


func load_run() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(RUN_PATH) != OK:
		return
	var r = cfg.get_value("run", "data", {})
	if r is Dictionary:
		run = r
		if not run.is_empty():
			Shop.ensure(run)


func save_run() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("run", "data", run)
	cfg.save(RUN_PATH)


func player_spec() -> Dictionary:
	var p: Dictionary = (run.get("player", {}) as Dictionary).duplicate(true)
	p["garments"] = Shop.garments_for(run)
	return p


## A bout was won: renown and coin, record the fallen, advance.
func bout_won(renown_gain: int, fallen: Array, coin := 0) -> void:
	run["renown"] = int(run.get("renown", 0)) + renown_gain
	run["purse"] = int(run.get("purse", 0)) + coin
	run["bout"] = int(run.get("bout", 0)) + 1
	run["best_bout"] = maxi(int(run.get("best_bout", 0)), int(run["bout"]))
	var slain: Array = run.get("slain", [])
	for s in fallen:
		slain.append(s)
	# The Hollow only keeps the most recent dead: a bounded, readable debt.
	while slain.size() > 8:
		slain.pop_front()
	run["slain"] = slain
	run["slain_total"] = int(run.get("slain_total", 0)) + fallen.size()
	save_run()


func set_weapon(weapon_id: String, shield: bool) -> void:
	Shop.ensure(run)
	if not weapon_id in (run["owned"] as Array):
		(run["owned"] as Array).append(weapon_id)
	var p: Dictionary = run.get("player", {})
	p["weapon"] = weapon_id
	p["shield"] = shield
	run["player"] = p
	save_run()


## Death in the arena: the dead you made wait below.
func enter_hollow() -> void:
	var slain: Array = run.get("slain", [])
	var debt := slain.slice(maxi(0, slain.size() - 5))
	if debt.size() < 2:
		# Even the innocent are met by something.
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		while debt.size() < 2:
			debt.append(Armory.roll_fighter(maxi(0, Tournament.rank_for_bout(int(run.get("bout", 0))) - 1), rng))
	run["hollow_debt"] = debt
	run["mode"] = "hollow"
	save_run()


## The debt is paid: back to the living, at a price in renown.
func return_from_hollow() -> void:
	run["mode"] = "arena"
	run["returns"] = int(run.get("returns", 0)) + 1
	run["renown"] = maxi(0, int(run.get("renown", 0)) - 15)
	run["slain"] = []
	run["hollow_debt"] = []
	save_run()


func end_run() -> void:
	run["over"] = true
	run["mode"] = "over"
	save_run()
