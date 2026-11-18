class_name Fx
extends RefCounted
## 図形だけで作る演出（破片、数値ポップ）。


static func burst(parent: Node, pos: Vector2, col: Color, amount: int = 24, speed: float = 160.0) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 0.7
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.damping_min = speed * 0.6
	p.damping_max = speed
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.5
	p.color = col
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


static func popup(parent: Node, pos: Vector2, text: String, col: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	l.position = pos + Vector2(-20, -30)
	l.z_index = 20
	parent.add_child(l)
	var t := l.create_tween()
	t.set_parallel(true)
	t.tween_property(l, "position:y", l.position.y - 45.0, 0.8).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.3)
	t.chain().tween_callback(l.queue_free)
