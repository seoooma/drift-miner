class_name ShipCore
extends Node2D
## 母船。セクターの中心にあり、資源の倉庫になる。工場はこの補給圏内にしか置けない。

const SUPPLY_RADIUS := 400.0
const BODY_RADIUS := 46.0

var _t: float = 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, SUPPLY_RADIUS, Color(0.4, 0.7, 1.0, 0.025))
	var dash := 48
	for i in dash:
		if i % 2 == 0:
			var a0 := TAU * i / dash + _t * 0.05
			draw_arc(Vector2.ZERO, SUPPLY_RADIUS, a0, a0 + TAU / dash, 4, Color(0.4, 0.7, 1.0, 0.35), 2.0)
	var hexp := PackedVector2Array()
	for i in 6:
		hexp.append(Vector2.from_angle(TAU * i / 6.0 + PI / 6.0) * BODY_RADIUS)
	draw_colored_polygon(hexp, Color(0.15, 0.22, 0.32))
	var outline := hexp.duplicate()
	outline.append(hexp[0])
	draw_polyline(outline, Color(0.5, 0.8, 1.0), 3.0)
	draw_circle(Vector2.ZERO, 12.0 + 3.0 * sin(_t * 2.0), Color(0.5, 0.85, 1.0, 0.7))
