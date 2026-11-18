class_name Meteor
extends Node2D
## 隕石の落下。赤い円で予告し、時間が来ると範囲内の採掘機を壊し、自機の燃料を削る。

signal impacted(meteor: Meteor)

const WARN_TIME := 2.5
const RADIUS := 110.0

var _t: float = 0.0
var _done: bool = false


func _process(delta: float) -> void:
	_t += delta
	if not _done and _t >= WARN_TIME:
		_done = true
		impacted.emit(self)
		queue_free()
	queue_redraw()


func _draw() -> void:
	var k := clampf(_t / WARN_TIME, 0.0, 1.0)
	var blink := 0.5 + 0.5 * sin(_t * (8.0 + k * 20.0))
	draw_circle(Vector2.ZERO, RADIUS, Color(1.0, 0.2, 0.15, 0.08 + 0.12 * blink))
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 48, Color(1.0, 0.3, 0.2, 0.8), 2.0)
	draw_arc(Vector2.ZERO, RADIUS * k, 0.0, TAU, 48, Color(1.0, 0.6, 0.3, 0.9), 3.0)
	draw_line(Vector2(-14, -14), Vector2(14, 14), Color(1, 0.4, 0.3), 3.0)
	draw_line(Vector2(-14, 14), Vector2(14, -14), Color(1, 0.4, 0.3), 3.0)
