extends CanvasLayer
## 背景。画面に固定した層に、宇宙の地模様（Kenney の CC0 背景タイル）、星雲の光、
## 3段の星（カメラの動きに少しずつ遅れてついてくる視差）を描く。

const STARS := 220

var _stars: Array = []  # [位置(0..1), 深さ, 大きさ, 位相]
var _t: float = 0.0
var _canvas: Control
var _bg: Texture2D
var _star_tex: Texture2D
var _glow: Texture2D


func _ready() -> void:
	layer = -10
	_bg = load("res://assets/sprites/bg_tile.png")
	_star_tex = load("res://assets/fx/star_06.png")
	_glow = load("res://assets/fx/circle_05.png")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in STARS:
		_stars.append([Vector2(rng.randf(), rng.randf()), rng.randf_range(0.05, 0.45), rng.randf_range(0.6, 1.8), rng.randf() * TAU])
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_bg)
	add_child(_canvas)


func _process(delta: float) -> void:
	_t += delta
	_canvas.queue_redraw()


func _cam() -> Vector2:
	var c := get_viewport().get_camera_2d()
	return c.global_position if c != null else Vector2.ZERO


func _draw_bg() -> void:
	var s := _canvas.size
	var cam := _cam()
	# 地模様のタイル（暗くして、ごく弱い視差）
	var ts := 256.0
	var off := Vector2(fposmod(-cam.x * 0.05, ts), fposmod(-cam.y * 0.05, ts))
	var y := -ts + off.y
	while y < s.y:
		var x := -ts + off.x
		while x < s.x:
			_canvas.draw_texture_rect(_bg, Rect2(x, y, ts, ts), false, Color(0.32, 0.34, 0.5))
			x += ts
		y += ts
	# 星雲の光
	for n in [[Vector2(0.2, 0.25), Color(0.35, 0.2, 0.6, 0.35), 1.1], [Vector2(0.85, 0.7), Color(0.1, 0.35, 0.55, 0.3), 1.3], [Vector2(0.55, 1.05), Color(0.5, 0.15, 0.35, 0.25), 1.0]]:
		var p: Vector2 = (n[0] as Vector2) * s - cam * 0.02
		var r: float = maxf(s.x, s.y) * float(n[2])
		_canvas.draw_texture_rect(_glow, Rect2(p - Vector2(r, r) * 0.5, Vector2(r, r)), false, n[1])
	# 星
	for st in _stars:
		var depth: float = st[1]
		var p := Vector2(fposmod((st[0] as Vector2).x * s.x - cam.x * depth * 0.25, s.x), fposmod((st[0] as Vector2).y * s.y - cam.y * depth * 0.25, s.y))
		var tw := 0.55 + 0.45 * sin(_t * (0.8 + depth * 2.0) + float(st[3]))
		var sz: float = float(st[2]) * (1.0 + depth * 2.0)
		if sz > 2.2:
			var g := sz * 4.0
			_canvas.draw_texture_rect(_star_tex, Rect2(p - Vector2(g, g) * 0.5, Vector2(g, g)), false, Color(0.85, 0.9, 1.0, 0.5 * tw))
		_canvas.draw_circle(p, sz * 0.5, Color(0.9, 0.93, 1.0, 0.35 + 0.5 * tw))
