class_name ImpactFx
extends Node2D
## 衝撃の画面効果（shaders/impact.gdshader）を受け持つ。惑星と演出の上、HUD の下に、画面全体を覆う形で描く。
## 衝撃波（同時に4つまで）・色ずれ・閃光のどれかが動いている間だけ表示する。何もないときは描かないので負担はない。
## 時間は普通の delta で進める（ヒットストップの間は止まる）。

const MAX_WAVES := 4

var _mat: ShaderMaterial
var _waves: Array = []  # [world_pos, max_r（短い辺に対する割合）, strength, t, dur]
var _aberr: float = 0.0
var _flash := Color(0, 0, 0, 0)
var _flash_dur: float = 0.3
var _flash_t: float = 0.0


func _ready() -> void:
	z_index = 100
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/impact.gdshader")
	material = _mat
	visible = false


## 画面の一点（ワールド座標）から広がる衝撃波。radius_world はおおよその広がり。
func wave(world_pos: Vector2, radius_world: float, strength: float = 1.0, dur: float = 0.5) -> void:
	var vp := get_viewport_rect().size
	var short := minf(vp.x, vp.y)
	var r_screen := radius_world * get_canvas_transform().get_scale().x
	var r := clampf(r_screen / short, 0.08, 1.2)
	if _waves.size() >= MAX_WAVES:
		# いちばん弱い（＝古い・小さい）ものと入れ替える
		var weakest := 0
		for k in _waves.size():
			if _wave_now(_waves[k]) < _wave_now(_waves[weakest]):
				weakest = k
		if _wave_now(_waves[weakest]) > strength:
			return
		_waves.remove_at(weakest)
	_waves.append([world_pos, r, strength, 0.0, dur])
	visible = true


func _wave_now(w: Array) -> float:
	return float(w[2]) * (1.0 - float(w[3]) / float(w[4]))


## 色ずれ（0〜1）。すぐに戻る
func aberrate(amount: float) -> void:
	_aberr = clampf(maxf(_aberr, amount), 0.0, 1.0)
	visible = true


## 画面全体に色を一瞬足す
func flash(col: Color, amount: float, dur: float = 0.3) -> void:
	_flash = Color(col, maxf(amount, _flash.a))
	_flash_dur = dur
	_flash_t = 0.0
	visible = true


func _process(delta: float) -> void:
	if not visible:
		return
	for w in _waves.duplicate():
		w[3] = float(w[3]) + delta
		if float(w[3]) >= float(w[4]):
			_waves.erase(w)
	_aberr = maxf(0.0, _aberr - delta * 2.5)
	var fa := 0.0
	if _flash.a > 0.0:
		_flash_t += delta
		var k := clampf(_flash_t / _flash_dur, 0.0, 1.0)
		fa = _flash.a * (1.0 - k) * (1.0 - k)
		if k >= 1.0:
			_flash.a = 0.0
	if _waves.is_empty() and _aberr <= 0.0 and fa <= 0.0:
		visible = false
		return
	var vp := get_viewport_rect().size
	var ct := get_canvas_transform()
	var arr := PackedVector4Array()
	arr.resize(MAX_WAVES)
	for k in _waves.size():
		var w: Array = _waves[k]
		var e := float(w[3]) / float(w[4])
		var sp: Vector2 = ct * (w[0] as Vector2)
		var grow := 1.0 - pow(1.0 - e, 3.0)  # 速く出て、ゆっくり止まる
		arr[k] = Vector4(sp.x / vp.x, sp.y / vp.y, float(w[1]) * (0.1 + 0.9 * grow), float(w[2]) * (1.0 - e) * (1.0 - e))
	_mat.set_shader_parameter("waves", arr)
	_mat.set_shader_parameter("aspect", vp.x / maxf(vp.y, 1.0))
	_mat.set_shader_parameter("aberration", _aberr * _aberr)
	_mat.set_shader_parameter("flash_col", Color(_flash.r, _flash.g, _flash.b, fa))
	queue_redraw()


func _draw() -> void:
	# 画面全体を覆う四角（カメラの逆の変換で、画面の座標をこのノードの座標に戻して描く）
	draw_set_transform_matrix(get_global_transform_with_canvas().affine_inverse())
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color.WHITE)
