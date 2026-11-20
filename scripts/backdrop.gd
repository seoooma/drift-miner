extends CanvasLayer
## 背景。画面に固定した層に、黒の上の薄い方眼（1px・白4%・約40px 間隔）と、
## ごく小さな暗い星を少しだけ描く。方眼はカメラの動きにゆっくりついてくる。
## そのうちいくつかは、ときどき十字にきらめく（Kenney「Particle Pack」の光の画像、加算合成）。

const GRID := 40.0
const STARS := 36
const TWINKLES := 6
const TWINKLE_COLORS := [Color(1, 1, 1), Color(1, 1, 1), Neon.CYAN, Color(1, 1, 1), Neon.MAGENTA, Color(1, 1, 1)]

var _stars: Array = []  # [位置(0..1), 深さ, 明るさ]
var _canvas: Control
var _last_cam := Vector2.INF
var _last_size := Vector2.ZERO
var _twinkles: Array = []  # [Sprite2D, 星の番号, 周期, 位相, 大きさ(px)]
var _t := 0.0


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
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var tex: Texture2D = load("res://assets/fx/glint.png")
	for i in TWINKLES:
		var sp := Sprite2D.new()
		sp.texture = tex
		sp.material = add
		sp.modulate = Color(TWINKLE_COLORS[i % TWINKLE_COLORS.size()], 0.0)
		add_child(sp)
		_twinkles.append([sp, i * 5 + 2, rng.randf_range(5.0, 11.0), rng.randf(), rng.randf_range(10.0, 18.0)])


func _process(delta: float) -> void:
	_t += delta
	var cam := _cam()
	_update_twinkles(cam)
	# カメラが動いたときだけ描き直す
	if cam.distance_squared_to(_last_cam) > 0.01 or _canvas.size != _last_size:
		_last_cam = cam
		_last_size = _canvas.size
		_canvas.queue_redraw()


## きらめく星：ふだんは見えず、周期ごとに一瞬だけ光る
func _update_twinkles(cam: Vector2) -> void:
	var s := _canvas.size
	for tw in _twinkles:
		var sp: Sprite2D = tw[0]
		var p := _star_pos(_stars[tw[1]], s, cam)
		sp.position = p.floor() + Vector2(0.5, 0.5)
		var ph := fposmod(_t / float(tw[2]) + float(tw[3]), 1.0)
		var a := pow(maxf(0.0, sin(ph * TAU)), 12.0) * 0.8
		sp.modulate.a = a
		var k: float = float(tw[4]) / float(sp.texture.get_width()) * (0.6 + 0.4 * a)
		sp.scale = Vector2(k, k)


func _star_pos(st: Array, s: Vector2, cam: Vector2) -> Vector2:
	var d: float = st[1]
	return Vector2(fposmod((st[0] as Vector2).x * s.x - cam.x * d * 0.25, s.x), fposmod((st[0] as Vector2).y * s.y - cam.y * d * 0.25, s.y))


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
		var p := _star_pos(st, s, cam)
		_canvas.draw_rect(Rect2(p.floor(), Vector2.ONE), Color(1, 1, 1, float(st[2])))
