extends Node
## 音（Autoload）。BGM のループ再生と、効果音の再生。
## 効果音は同じ音が短い間に重なりすぎないよう間引き、音程を少しずらして単調さを避ける。
## 音のオン・オフと音量は user://settings.cfg に保存する。

const SETTINGS_PATH := "user://settings.cfg"
const SFX := {
	"break": ["res://assets/audio/break_000.ogg", "res://assets/audio/break_001.ogg", "res://assets/audio/break_002.ogg", "res://assets/audio/break_003.ogg"],
	"ore_metal": ["res://assets/audio/ore_metal.ogg"],
	"ore_crystal": ["res://assets/audio/ore_crystal.ogg"],
	"laser": ["res://assets/audio/laser.ogg"],
	"drill": ["res://assets/audio/drill.ogg"],
	"bomb": ["res://assets/audio/bomb.ogg"],
	"blast": ["res://assets/audio/blast.ogg"],
	"cache": ["res://assets/audio/cache.ogg"],
	"relic": ["res://assets/audio/relic.ogg"],
	"clear": ["res://assets/audio/clear.ogg"],
	"skill": ["res://assets/audio/skill.ogg"],
	"move": ["res://assets/audio/move.ogg"],
	"click": ["res://assets/audio/ui_click1.ogg"],
	"buy": ["res://assets/audio/ui_switch2.ogg"],
	"open": ["res://assets/audio/ui_switch33.ogg"],
}
## 音ごとの音量（dB）と、次に鳴らせるまでの最短間隔（秒）
const MIX := {
	"break": [-14.0, 0.07], "ore_metal": [-12.0, 0.09], "ore_crystal": [-9.0, 0.09], "laser": [-20.0, 0.25],
	"drill": [-15.0, 0.2], "bomb": [-8.0, 0.15], "blast": [-7.0, 0.2], "cache": [-6.0, 0.3],
	"relic": [-4.0, 0.5], "clear": [-3.0, 1.0], "skill": [-8.0, 0.1], "move": [-12.0, 0.4],
	"click": [-8.0, 0.04], "buy": [-10.0, 0.05], "open": [-10.0, 0.1],
}
const VOICES := 14

var enabled := true
var music_db := -10.0

var _streams := {}
var _last := {}
var _voices: Array = []
var _next_voice: int = 0
var _bgm: AudioStreamPlayer
var _jingle_t: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		enabled = bool(cfg.get_value("audio", "enabled", true))
	for k in SFX:
		var arr: Array = []
		for p in SFX[k]:
			arr.append(load(p))
		_streams[k] = arr
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_voices.append(p)
	_bgm = AudioStreamPlayer.new()
	var music: AudioStreamOggVorbis = load("res://assets/audio/bgm_lost_in_space.ogg")
	music.loop = true
	_bgm.stream = music
	_bgm.volume_db = music_db
	add_child(_bgm)
	_apply()


func _process(delta: float) -> void:
	# ジングル（遺物・惑星破壊）の間は BGM を少し下げる
	_jingle_t = maxf(0.0, _jingle_t - delta)
	var target := music_db - (9.0 if _jingle_t > 0.0 else 0.0)
	_bgm.volume_db = lerpf(_bgm.volume_db, target, clampf(delta * 4.0, 0.0, 1.0))


func _apply() -> void:
	AudioServer.set_bus_mute(0, not enabled)
	if not _bgm.playing:
		_bgm.play()


func set_enabled(on: bool) -> void:
	enabled = on
	_apply()
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("audio", "enabled", enabled)
	cfg.save(SETTINGS_PATH)


## 効果音を鳴らす。gain は音量の上乗せ（dB）。
func play(id: String, gain: float = 0.0, pitch_spread: float = 0.08) -> void:
	if not enabled or not _streams.has(id):
		return
	var now := Time.get_ticks_msec() / 1000.0
	var mix: Array = MIX.get(id, [-10.0, 0.05])
	if now - float(_last.get(id, -10.0)) < float(mix[1]):
		return
	_last[id] = now
	var arr: Array = _streams[id]
	var p: AudioStreamPlayer = _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	p.stream = arr[randi() % arr.size()]
	p.volume_db = float(mix[0]) + gain
	p.pitch_scale = 1.0 + randf_range(-pitch_spread, pitch_spread)
	p.play()
	if id == "relic" or id == "clear":
		_jingle_t = 2.5 if id == "relic" else 5.0
