class_name WarpGate
extends Node2D
## 次のセクターへ進むためのワープゲート。

var discovered: bool = false
var _t: float = 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var pulse := 0.5 + 0.5 * sin(_t * 3.0)
	draw_arc(Vector2.ZERO, 46.0, _t, _t + TAU * 0.8, 48, Color(0.3, 1.0, 0.6), 4.0)
	draw_arc(Vector2.ZERO, 34.0, -_t * 1.5, -_t * 1.5 + TAU * 0.6, 48, Color(0.3, 1.0, 0.6, 0.7), 3.0)
	draw_circle(Vector2.ZERO, 14.0 + pulse * 6.0, Color(0.6, 1.0, 0.8, 0.5))
