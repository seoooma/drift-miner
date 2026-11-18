class_name Miner
extends Node2D
## 小惑星に取り付ける自動採掘機。放置で資源を掘り続ける。

const BASE_RATE := 1.5

var _spin: float = 0.0


func _process(delta: float) -> void:
	var asteroid := get_parent() as Asteroid
	if asteroid == null or not asteroid.is_alive():
		return
	var got := asteroid.extract(BASE_RATE * GameState.miner_mult * delta)
	GameState.add_res(asteroid.kind, got)
	_spin += delta * 3.0 * GameState.miner_mult
	queue_redraw()


func _draw() -> void:
	var col := Color(1.0, 0.85, 0.3)
	draw_rect(Rect2(-7, -7, 14, 14), col)
	for i in 3:
		var dir := Vector2.from_angle(_spin + TAU * i / 3.0)
		draw_line(dir * 7.0, dir * 15.0, col, 3.0)
