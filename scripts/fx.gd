class_name Fx
extends RefCounted
## 演出。破片・火花・発光・衝撃波・爆発のアニメーション・数値ポップ。
## 画像は Kenney の CC0 素材（assets/fx）。発光するものは加算合成で重ねる。
## view_scale はカメラの倍率の逆数。寄りの画面でも文字や破片が大きくなりすぎないようにする。

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


static func _k() -> float:
	return clampf(view_scale * 1.2, 0.15, 1.0)


## 破片：ブロックの色の小さなかけらが飛び散る
static func burst(parent: Node, pos: Vector2, col: Color, amount: int = 24, speed: float = 160.0) -> void:
	var k := _k()
	var p := CPUParticles2D.new()
	p.position = pos
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 0.8
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.texture = tex("res://assets/fx/circle_05.png")
	speed *= k
	p.initial_velocity_min = speed * 0.35
	p.initial_velocity_max = speed
	p.damping_min = speed * 0.6
	p.damping_max = speed
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.scale_amount_min = 0.05 * k * 1.6
	p.scale_amount_max = 0.12 * k * 1.6
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	p.color = col
	var grad := Gradient.new()
	grad.set_color(0, Color(1.4, 1.4, 1.4, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = grad
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


## 火花：加算合成の明るい光の粒
static func sparks(parent: Node, pos: Vector2, col: Color, amount: int = 10, speed: float = 120.0) -> void:
	var k := _k()
	var p := CPUParticles2D.new()
	p.position = pos
	p.material = additive()
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = amount
	p.lifetime = 0.5
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.texture = tex("res://assets/fx/star_04.png")
	p.initial_velocity_min = speed * k * 0.4
	p.initial_velocity_max = speed * k
	p.damping_min = speed * k
	p.damping_max = speed * k * 1.5
	p.scale_amount_min = 0.06 * k * 1.6
	p.scale_amount_max = 0.14 * k * 1.6
	p.color = col
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = grad
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


## 光の広がり（ふわっと明るくなって消える）
static func flash(parent: Node, pos: Vector2, col: Color, radius: float, dur: float = 0.35) -> void:
	var s := Sprite2D.new()
	s.texture = tex("res://assets/fx/circle_05.png")
	s.material = additive()
	s.position = pos
	s.modulate = col
	var base := radius * 2.0 / 64.0
	s.scale = Vector2.ONE * base * 0.4
	s.z_index = 5
	parent.add_child(s)
	var t := s.create_tween().set_parallel(true)
	t.tween_property(s, "scale", Vector2.ONE * base, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_property(s, "modulate:a", 0.0, dur).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(s.queue_free)


## 衝撃波の輪
static func ring(parent: Node, pos: Vector2, col: Color, radius: float, dur: float = 0.45) -> void:
	var s := Sprite2D.new()
	s.texture = tex("res://assets/fx/circle_03.png")
	s.material = additive()
	s.position = pos
	s.modulate = col
	var base := radius * 2.0 / 128.0
	s.scale = Vector2.ONE * base * 0.15
	s.z_index = 5
	parent.add_child(s)
	var t := s.create_tween().set_parallel(true)
	t.tween_property(s, "scale", Vector2.ONE * base, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(s, "modulate:a", 0.0, dur)
	t.chain().tween_callback(s.queue_free)


## 爆発のアニメーション（9コマ）。sonic は爆雷用の衝撃波型。
static func explosion(parent: Node, pos: Vector2, radius: float, sonic: bool = false) -> void:
	var frames := SpriteFrames.new()
	frames.set_animation_loop("default", false)
	frames.set_animation_speed("default", 22.0)
	var dir := "sonic" if sonic else "explosion"
	for i in 9:
		frames.add_frame("default", tex("res://assets/fx/%s/%02d.png" % [dir, i]))
	var a := AnimatedSprite2D.new()
	a.sprite_frames = frames
	a.position = pos
	a.rotation = randf() * TAU
	a.scale = Vector2.ONE * radius * 2.0 / 128.0
	a.z_index = 6
	parent.add_child(a)
	a.play("default")
	a.animation_finished.connect(a.queue_free)
	flash(parent, pos, Color(1.0, 0.7, 0.35, 0.9) if not sonic else Color(0.8, 0.6, 1.0, 0.9), radius * 1.8, 0.4)
	smoke(parent, pos, radius)


## 土煙
static func smoke(parent: Node, pos: Vector2, radius: float) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.one_shot = true
	p.explosiveness = 0.8
	p.amount = 6
	p.lifetime = 1.1
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.texture = tex("res://assets/fx/smoke_04.png")
	p.initial_velocity_min = radius * 0.3
	p.initial_velocity_max = radius * 0.9
	p.damping_min = radius * 0.5
	p.damping_max = radius
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.scale_amount_min = radius / 128.0 * 0.6
	p.scale_amount_max = radius / 128.0 * 1.1
	p.color = Color(0.55, 0.5, 0.6, 0.55)
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.8))
	grad.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = grad
	p.z_index = 4
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


static func popup(parent: Node, pos: Vector2, text: String, col: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	var k := clampf(view_scale * 0.8, 0.1, 1.0)
	l.scale = Vector2(k, k) * 0.6
	l.position = pos + Vector2(-20, -30) * k
	l.z_index = 20
	parent.add_child(l)
	var t := l.create_tween()
	t.set_parallel(true)
	t.tween_property(l, "scale", Vector2(k, k), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "position:y", l.position.y - 45.0 * k, 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.45)
	t.chain().tween_callback(l.queue_free)
