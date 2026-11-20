class_name Fx
extends RefCounted
## 演出。小さな四角い粒、揺らぐ輪（範囲攻撃・爆発）、数値ポップ。
## 光は線と演出にだけ。太く薄い線を加算合成で下に敷いて、にじみを作る（毎フレームのぼかしは使わない）。
## view_scale はカメラの倍率の逆数（画面 1px がワールドで何単位か）。太さや文字の大きさを画面のピクセルで決めるのに使う。

static var view_scale: float = 1.0
static var _cache := {}
static var _add_mat: CanvasItemMaterial


static func tex(path: String) -> Texture2D:
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]


static func additive() -> CanvasItemMaterial:
	if _add_mat == null:
		_add_mat = CanvasItemMaterial.new()
		_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add_mat


## 光の素材（Kenney「Particle Pack」、CC0）。白一色で、濃さだけを持つ。加算合成で重ねる。
const HALO := "res://assets/fx/halo.png"  # 柔らかい丸い光
const GLINT := "res://assets/fx/glint.png"  # 十字のきらめき
const STREAK := "res://assets/fx/streak.png"  # 横に伸びる細い光


## 光の画像を一瞬だけ置いて、広げながら消す。size は直径（ワールドの単位）。
static func _light(parent: Node, path: String, pos: Vector2, col: Color, size: float, peak: float, dur: float, grow: float = 1.4, spin: float = 0.0) -> void:
	var t: Texture2D = tex(path)
	var s := Sprite2D.new()
	s.texture = t
	s.material = additive()
	s.position = pos
	s.z_index = 4
	var k := size / float(t.get_width())
	s.scale = Vector2(k, k)
	s.modulate = Color(col, peak)
	if spin != 0.0:
		s.rotation = randf() * TAU
	parent.add_child(s)
	var tw := s.create_tween().set_parallel(true)
	tw.tween_property(s, "scale", Vector2(k, k) * grow, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(s, "modulate:a", 0.0, dur).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	if spin != 0.0:
		tw.tween_property(s, "rotation", s.rotation + spin, dur)
	tw.chain().tween_callback(s.queue_free)


## にじみ：線の演出の下に敷く、柔らかい光のふくらみ（控えめ）
static func halo(parent: Node, pos: Vector2, col: Color, radius: float, dur: float = 0.4, peak: float = 0.3) -> void:
	_light(parent, HALO, pos, col, radius * 2.0, peak, dur, 1.5)


## きらめき：十字の光が少し回りながら消える。大きさは画面のピクセルで決める。
static func glint(parent: Node, pos: Vector2, col: Color, size_px: float = 26.0, dur: float = 0.5) -> void:
	_light(parent, GLINT, pos, col, px(size_px), 0.9, dur, 0.7, 0.6)


## 横に走る細い光（爆発や大きな出来事に）
static func streak(parent: Node, pos: Vector2, col: Color, width: float, dur: float = 0.45) -> void:
	_light(parent, STREAK, pos, col, width, 0.6, dur, 1.6)


## 画面のピクセル数をワールドの長さにする
static func px(n: float) -> float:
	return n * view_scale


static func _k() -> float:
	return clampf(view_scale * 1.2, 0.15, 1.0)


static func _pixels(parent: Node, pos: Vector2, col: Color, amount: int, speed: float, size_px: float, life: float, add: bool) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	if add:
		p.material = additive()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = maxi(1, amount)
	p.lifetime = life
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	# 画像なし = 1単位の四角。大きさで画面上の 2〜3px にする
	p.initial_velocity_min = speed * 0.3
	p.initial_velocity_max = speed
	p.damping_min = speed * 0.8
	p.damping_max = speed * 1.4
	p.scale_amount_min = px(size_px * 0.7)
	p.scale_amount_max = px(size_px)
	p.color = col
	var grad := Gradient.new()
	grad.set_offset(0, 0.0)
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_offset(1, 1.0)
	grad.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = grad
	p.z_index = 5
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


## 破片：ブロックの色の小さな四角い粒が飛び散ってすぐ消える
static func burst(parent: Node, pos: Vector2, col: Color, amount: int = 24, speed: float = 160.0) -> void:
	_pixels(parent, pos, col.lightened(0.25), amount, speed * _k(), 2.0, 0.45, false)


## 火花：加算合成の明るい四角い粒
static func sparks(parent: Node, pos: Vector2, col: Color, amount: int = 10, speed: float = 120.0) -> void:
	_pixels(parent, pos, col, amount, speed * _k(), 2.0, 0.35, true)


## 光の広がり：細い四角の枠が広がって消える。下に柔らかい光と十字のきらめきを添える。
static func flash(parent: Node, pos: Vector2, col: Color, radius: float, dur: float = 0.35) -> void:
	var n := Node2D.new()
	n.position = pos
	n.material = additive()
	n.z_index = 5
	var w := px(1.5)
	n.set_meta("k", 0.0)
	n.draw.connect(func():
		var k: float = n.get_meta("k")
		var r := radius * (0.3 + 0.7 * ease(k, 0.4))
		var c := Color(col, col.a * (1.0 - k))
		var rect := Rect2(-r, -r, r * 2.0, r * 2.0)
		n.draw_rect(rect, Neon.glow(c), false, w * 4.0)
		n.draw_rect(rect, c, false, w))
	parent.add_child(n)
	halo(parent, pos, col, radius * 1.5, dur * 1.2, 0.35)
	glint(parent, pos, col.lightened(0.4), 30.0 + minf(radius / maxf(view_scale, 0.001), 80.0) * 0.5, dur * 1.6)
	var t := n.create_tween()
	t.tween_method(func(k: float):
		n.set_meta("k", k)
		n.queue_redraw(), 0.0, 1.0, dur)
	t.tween_callback(n.queue_free)


## 衝撃波の輪：±3px の揺らぎを持った細い輪。数フレームごとに形が変わり、広がって消える。
static func ring(parent: Node, pos: Vector2, col: Color, radius: float, dur: float = 0.45) -> void:
	var n := Node2D.new()
	n.position = pos
	n.material = additive()
	n.z_index = 5
	var w := px(1.5)
	var jit := px(3.0)
	var base_seed := randi()
	n.set_meta("k", 0.0)
	n.draw.connect(func():
		var k: float = n.get_meta("k")
		var r := radius * (0.15 + 0.85 * ease(k, 0.35))
		var c := Color(col, col.a * (1.0 - k * k))
		# 約4フレーム（1/15秒）ごとに揺らぎを作り直す
		var pts := Neon.jitter_ring(Vector2.ZERO, r, jit, base_seed + int(k * dur * 15.0))
		Neon.glow_poly(n, pts, c, w, w * 4.0))
	parent.add_child(n)
	var t := n.create_tween()
	t.tween_method(func(k: float):
		n.set_meta("k", k)
		n.queue_redraw(), 0.0, 1.0, dur)
	t.tween_callback(n.queue_free)


## 爆発：揺らぐ輪を二重にして、四角い粒を散らす。sonic は爆雷用（マゼンタ）。
## 中心に柔らかい光のふくらみと、横に走る細い光を一瞬だけ重ねる。
static func explosion(parent: Node, pos: Vector2, radius: float, sonic: bool = false) -> void:
	var col := Neon.MAGENTA if sonic else Neon.ORANGE
	ring(parent, pos, col, radius, 0.4)
	ring(parent, pos, Color(Neon.LINE, 0.7), radius * 0.6, 0.3)
	sparks(parent, pos, col, 14, radius * 3.0)
	halo(parent, pos, col, radius * 0.9, 0.5, 0.35)
	streak(parent, pos, col.lightened(0.3), radius * 3.0, 0.4)


## 数値ポップ：11〜13px の等幅の文字が、0.8秒ほどで上がりながら消える
static func popup(parent: Node, pos: Vector2, text: String, col: Color) -> void:
	var l := Label.new()
	l.text = text
	Neon.plain_text(l, 12, col)
	var k := view_scale
	l.scale = Vector2(k, k)
	l.position = pos + Vector2(-4, -18) * k
	l.z_index = 20
	parent.add_child(l)
	var t := l.create_tween()
	t.set_parallel(true)
	t.tween_property(l, "position:y", l.position.y - 26.0 * k, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.45)
	t.chain().tween_callback(l.queue_free)
