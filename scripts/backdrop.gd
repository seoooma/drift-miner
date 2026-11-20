extends CanvasLayer
## 背景。画面に固定した層に、黒の上の薄い方眼（1px・白4%・約40px 間隔）と、
## ごく小さな暗い星を少しだけ描く。方眼はカメラの動きにゆっくりついてくる。

const GRID := 40.0
const STARS := 36

var _stars: Array = []  # [位置(0..1), 深さ, 明るさ]
var _canvas: Control
var _last_cam := Vector2.INF
var _last_size := Vector2.ZERO


func _ready() -> void:
	layer = -10
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in STARS:
		_stars.append([Vector2(rng.randf(), rng.randf()), rng.randf_range(0.05, 0.3), rng.randf_range(0.2, 0.5)])
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_bg)
	add_child(_canvas)


func _process(_delta: float) -> void:
	# カメラが動いたときだけ描き直す
	var cam := _cam()
	if cam.distance_squared_to(_last_cam) > 0.01 or _canvas.size != _last_size:
		_last_cam = cam
		_last_size = _canvas.size
		_canvas.queue_redraw()


func _cam() -> Vector2:
	var c := get_viewport().get_camera_2d()
	return c.global_position if c != null else Vector2.ZERO


func _draw_bg() -> void:
	var s := _canvas.size
	var cam := _cam()
	_canvas.draw_rect(Rect2(Vector2.ZERO, s), Neon.BG)
	var gc := Color(1, 1, 1, 0.04)
	var off := Vector2(fposmod(-cam.x * 0.15, GRID), fposmod(-cam.y * 0.15, GRID))
	var x := off.x
	while x < s.x:
		_canvas.draw_rect(Rect2(floorf(x), 0, 1, s.y), gc)
		x += GRID
	var y := off.y
	while y < s.y:
		_canvas.draw_rect(Rect2(0, floorf(y), s.x, 1), gc)
		y += GRID
	for st in _stars:
		var d: float = st[1]
		var p := Vector2(fposmod((st[0] as Vector2).x * s.x - cam.x * d * 0.25, s.x), fposmod((st[0] as Vector2).y * s.y - cam.y * d * 0.25, s.y))
		_canvas.draw_rect(Rect2(p.floor(), Vector2.ONE), Color(1, 1, 1, float(st[2])))
