extends Node2D
## 背景の星とセクターの境界線。

var world_radius: float = 2200.0
var _stars: Array = []


func regenerate(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_stars.clear()
	for i in 900:
		var r := world_radius * 1.4
		_stars.append([Vector2(rng.randf_range(-r, r), rng.randf_range(-r, r)), rng.randf_range(0.5, 2.0), rng.randf_range(0.2, 0.8)])
	queue_redraw()


func _draw() -> void:
	for s in _stars:
		draw_circle(s[0], s[1], Color(1, 1, 1, s[2]))
	draw_arc(Vector2.ZERO, world_radius, 0.0, TAU, 128, Color(1.0, 0.3, 0.3, 0.35), 3.0)
