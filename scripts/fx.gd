class_name Fx
extends RefCounted
## 演出。小さな四角い粒、光の筋の火花、砕けた瞬間の閃き、揺らぐ輪（範囲攻撃・爆発）、数値ポップ、画面の衝撃波。
## 光は線と演出にだけ。太く薄い線を加算合成で下に敷いて、にじみを作る（毎フレームのぼかしは使わない）。
## view_scale はカメラの倍率の逆数（画面 1px がワールドで何単位か）。太さや文字の大きさを画面のピクセルで決めるのに使う。

static var view_scale: float = 1.0
static var impact: ImpactFx  # 画面の衝撃波・色ずれ・閃光（main が作る。なければ何もしない）
static var _cache := {}
static var _add_mat: CanvasItemMaterial
static var _fade: Gradient
static var _shrink: Curve
static var _spark_tex: ImageTexture


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


## 粒の色の変化（不透明 → 透明）。毎回作らず使い回す
static func _fade_grad() -> Gradient:
	if _fade == null:
		_fade = Gradient.new()
		_fade.set_offset(0, 0.0)
		_fade.set_color(0, Color(1, 1, 1, 1))
		_fade.set_offset(1, 1.0)
		_fade.set_color(1, Color(1, 1, 1, 0))
	return _fade


## 粒の大きさの変化（すぐには縮まず、最後に小さくなって消える）
static func _shrink_curve() -> Curve:
	if _shrink == null:
		_shrink = Curve.new()
		_shrink.add_point(Vector2(0.0, 1.0))
		_shrink.add_point(Vector2(0.6, 0.75))
		_shrink.add_point(Vector2(1.0, 0.1))
	return _shrink


## 火花の光の筋（幅2・長さ10、進む向きの先が明るい）。進む向きに伸ばして描く
static func _streak_tex() -> ImageTexture:
	if _spark_tex == null:
		var img := Image.create(2, 10, false, Image.FORMAT_RGBA8)
		for y in 10:
			var a := pow(float(y + 1) / 10.0, 1.6)
			for x in 2:
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_spark_tex = ImageTexture.create_from_image(img)
	return _spark_tex


static func _particles(pos: Vector2, col: Color, amount: int, life: float, add: bool) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = pos
	if add:
		p.material = additive()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = maxi(1, amount)
	p.lifetime = life
	p.lifetime_randomness = 0.35
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.color = col
	p.color_ramp = _fade_grad()
	p.scale_amount_curve = _shrink_curve()
	p.z_index = 5
	return p


static func _emit(parent: Node, p: CPUParticles2D) -> void:
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


## 破片：ブロックの色の小さな四角い粒が、回りながら飛び散って縮んで消える
static func burst(parent: Node, pos: Vector2, col: Color, amount: int = 24, speed: float = 160.0) -> void:
	speed *= _k()
	var p := _particles(pos, col.lightened(0.25), amount, 0.5, false)
	# 画像なし = 1単位の四角。大きさで画面上の 2〜3px にする
	p.initial_velocity_min = speed * 0.3
	p.initial_velocity_max = speed
	p.damping_min = speed * 0.8
	p.damping_max = speed * 1.4
	p.scale_amount_min = px(1.6)
	p.scale_amount_max = px(3.0)
	p.angle_max = 360.0
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	_emit(parent, p)


## 火花：加算合成の細い光の筋。進む向きに伸び、減速しながら短くなって消える（粒の尾）
static func sparks(parent: Node, pos: Vector2, col: Color, amount: int = 10, speed: float = 120.0) -> void:
	speed *= _k() * 1.3
	var p := _particles(pos, col, amount, 0.38, true)
	p.texture = _streak_tex()
	p.particle_flag_align_y = true
	p.initial_velocity_min = speed * 0.45
	p.initial_velocity_max = speed
	p.damping_min = speed * 0.6
	p.damping_max = speed * 1.0
	# 筋の長さが画面の 8〜16px になるように（画像の長さは10）
	p.scale_amount_min = px(8.0) / 10.0
	p.scale_amount_max = px(16.0) / 10.0
	_emit(parent, p)


## 砕けた瞬間の白い閃き：マスの大きさの白い四角が一瞬光り、細い枠が外へ広がって消える（約0.15秒）
static func pop(parent: Node, pos: Vector2, col: Color, size: float) -> void:
	var n := Node2D.new()
	n.position = pos
	n.material = additive()
	n.z_index = 5
	var w := px(1.0)
	n.set_meta("k", 0.0)
	n.draw.connect(func():
		var k: float = n.get_meta("k")
		var h := size * 0.5 * (1.0 - 0.35 * k)
		if k < 0.5:
			var a := 1.0 - k / 0.5
			n.draw_rect(Rect2(-h, -h, h * 2.0, h * 2.0), Color(1, 1, 1, 0.55 * a))
		var r := size * 0.5 * (1.0 + 0.9 * ease(k, 0.4))
		n.draw_rect(Rect2(-r, -r, r * 2.0, r * 2.0), Color(col, 0.8 * (1.0 - k)), false, w))
	parent.add_child(n)
	var t := n.create_tween()
	t.tween_method(func(k: float):
		n.set_meta("k", k)
		n.queue_redraw(), 0.0, 1.0, 0.16)
	t.tween_callback(n.queue_free)


## 爆発の芯：白く熱い円が一瞬で縮みながら色に冷めていく（数フレームの「衝撃の瞬間」）
static func core(parent: Node, pos: Vector2, col: Color, radius: float, dur: float = 0.14) -> void:
	var n := Node2D.new()
	n.position = pos
	n.material = additive()
	n.z_index = 6
	n.set_meta("k", 0.0)
	n.draw.connect(func():
		var k: float = n.get_meta("k")
		var r := radius * (1.0 - 0.6 * k)
		n.draw_circle(Vector2.ZERO, r, Color(col, 0.35 * (1.0 - k)))
		n.draw_circle(Vector2.ZERO, r * 0.55, Color(Color.WHITE.lerp(col, k), 0.9 * (1.0 - k))))
	parent.add_child(n)
	var t := n.create_tween()
	t.tween_method(func(k: float):
		n.set_meta("k", k)
		n.queue_redraw(), 0.0, 1.0, dur)
	t.tween_callback(n.queue_free)


## 画面の衝撃波（歪み）。strength は 0〜1 くらい
static func shockwave(pos: Vector2, radius: float, strength: float = 0.6, dur: float = 0.5) -> void:
	if impact != null and is_instance_valid(impact):
		impact.wave(pos, radius, strength, dur)


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
		# 出た瞬間は内側がうっすら光る
		if k < 0.2:
			n.draw_circle(Vector2.ZERO, r, Color(col, col.a * 0.16 * (1.0 - k / 0.2)))
		# 約4フレーム（1/15秒）ごとに揺らぎを作り直す
		var pts := Neon.jitter_ring(Vector2.ZERO, r, jit, base_seed + int(k * dur * 15.0))
		# 太く出て、広がりながら細くなる
		var th := w * (1.0 + 2.0 * (1.0 - k))
		Neon.glow_poly(n, pts, c, th, th * 3.5))
	parent.add_child(n)
	var t := n.create_tween()
	t.tween_method(func(k: float):
		n.set_meta("k", k)
		n.queue_redraw(), 0.0, 1.0, dur)
	t.tween_callback(n.queue_free)


## 爆発：白く熱い芯が一瞬光り、揺らぐ輪を二重にして、光の筋を散らす。sonic は爆雷用（マゼンタ）。
## 中心に柔らかい光のふくらみと、横に走る細い光を一瞬だけ重ね、画面にも小さな衝撃波の歪みを出す。
static func explosion(parent: Node, pos: Vector2, radius: float, sonic: bool = false) -> void:
	var col := Neon.MAGENTA if sonic else Neon.ORANGE
	core(parent, pos, col, radius * 0.45)
	ring(parent, pos, col, radius, 0.4)
	ring(parent, pos, Color(Neon.LINE, 0.7), radius * 0.6, 0.3)
	sparks(parent, pos, col.lightened(0.2), 18, radius * 3.0)
	halo(parent, pos, col, radius * 0.9, 0.5, 0.35)
	streak(parent, pos, col.lightened(0.3), radius * 3.0, 0.4)
	shockwave(pos, radius * 1.6, 0.35 if sonic else 0.5, 0.45)


## 数値ポップ：等幅の文字が、小さく出て一瞬大きく弾み（オーバーシュート）、上がりながら消える（約0.8秒）
## size は文字の大きさ（画面のピクセル）。大きな出来事には大きめに。
static func popup(parent: Node, pos: Vector2, text: String, col: Color, size: int = 12) -> void:
	var l := Label.new()
	l.text = text
	Neon.plain_text(l, size, col)
	var k := view_scale
	l.pivot_offset = l.get_combined_minimum_size() * Vector2(0.0, 0.5)
	l.scale = Vector2(k, k) * 0.4
	l.position = pos + Vector2(-4, -18) * k
	l.z_index = 20
	parent.add_child(l)
	var drift := randf_range(-4.0, 4.0) * k
	var t := l.create_tween()
	t.set_parallel(true)
	t.tween_property(l, "scale", Vector2(k, k), 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_property(l, "position", l.position + Vector2(drift, -26.0 * k), 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.45)
	t.chain().tween_callback(l.queue_free)


## 回収：小さな四角い粒が、光の尾を引きながらゆるい弧を描いて target（母艦の位置を返す関数）へ吸い込まれる。
## 着いたら on_arrive を呼ぶ（母艦を一瞬光らせる）。
static func absorb(parent: Node, from: Vector2, target: Callable, col: Color, amount: int, on_arrive: Callable = Callable()) -> void:
	var n := Node2D.new()
	n.material = additive()
	n.z_index = 6
	var seeds: Array = []
	for i in amount:
		seeds.append([Vector2.from_angle(randf() * TAU) * randf_range(2.0, 6.0), randf_range(-1.0, 1.0), randf_range(0.0, 0.25)])
	var dur := 0.7
	var s := px(2.5)
	n.set_meta("k", 0.0)
	n.draw.connect(func():
		var k: float = n.get_meta("k")
		var to: Vector2 = target.call()
		if to == Vector2.INF:
			return
		for sd in seeds:
			var kk := clampf((k - float(sd[2])) / (1.0 - float(sd[2])), 0.0, 1.0)
			if kk <= 0.0 or kk >= 1.0:
				continue
			var a: Vector2 = from + (sd[0] as Vector2)
			var side := (to - a).orthogonal().normalized() * a.distance_to(to) * 0.25 * float(sd[1])
			var e := ease(kk, 2.4)
			var p := a.lerp(to, e) + side * sin(e * PI)
			var c := Color(col, 0.9 * (1.0 - kk * 0.4))
			# 少し前の位置からの尾（速く動くほど長く伸びる）
			var e0 := ease(maxf(0.0, kk - 0.09), 2.4)
			var p0 := a.lerp(to, e0) + side * sin(e0 * PI)
			n.draw_line(p0, p, Color(col, 0.35 * (1.0 - kk * 0.4)), s * 0.8)
			n.draw_rect(Rect2(p - Vector2(s, s) * 1.5, Vector2(s, s) * 3.0), Neon.glow(c))
			n.draw_rect(Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), c))
	parent.add_child(n)
	var t := n.create_tween()
	t.tween_method(func(k: float):
		n.set_meta("k", k)
		n.queue_redraw(), 0.0, 1.0, dur)
	t.tween_callback(func():
		if on_arrive.is_valid():
			on_arrive.call()
		n.queue_free())
