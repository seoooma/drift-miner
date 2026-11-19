extends Node2D
## 背景。暗い方眼と、ゆっくり瞬く星。

var _stars: Array = []
var _t: float = 0.0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 260:
		_stars.append([Vector2(rng.randf_range(-1400, 1400), rng.randf_range(-1400, 1400)), rng.randf_range(0.8, 2.2), rng.randf() * TAU])


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var step := 64.0
	var ext := 1400.0
	var gc := Color(0.35, 0.5, 0.7, 0.06)
	var x := -ext
	while x <= ext:
		draw_line(Vector2(x, -ext), Vector2(x, ext), gc, 1.0)
		draw_line(Vector2(-ext, x), Vector2(ext, x), gc, 1.0)
		x += step
	for s in _stars:
		var a := 0.35 + 0.35 * sin(_t * 1.3 + float(s[2]))
		draw_circle(s[0], s[1], Color(0.85, 0.9, 1.0, a))
