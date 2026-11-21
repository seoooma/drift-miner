extends CanvasLayer
## 画面の質感（Autoload）。いちばん上の層に、ごく弱い走査線と周辺減光を乗算で重ねる（shaders/screen.gdshader）。
## 入力は受けない。一時停止中も表示し続ける。ヒットストップ（一瞬だけ時間を止める）もここで受け持つ。

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	var r := ColorRect.new()
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/screen.gdshader")
	r.material = m
	add_child(r)


# ---- ヒットストップ
# 大きな出来事（遺物・宝箱・惑星の破壊）の瞬間だけ、ほんの一瞬（0.05〜0.12秒）時間をほぼ止めて「重さ」を出す。
# まれな出来事にだけ使うので、採掘の進みにはほぼ影響しない。止める時間は実時間で数える。

var _stop_until: float = 0.0
var _stop_prev: float = 1.0


func hitstop(dur: float, scale: float = 0.05) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _stop_until <= now:
		_stop_prev = Engine.time_scale
	_stop_until = maxf(_stop_until, now + dur)
	Engine.time_scale = minf(scale, _stop_prev)


func _process(_delta: float) -> void:
	if _stop_until > 0.0 and Time.get_ticks_msec() / 1000.0 >= _stop_until:
		_stop_until = 0.0
		Engine.time_scale = _stop_prev
