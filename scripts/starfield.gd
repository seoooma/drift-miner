extends Node2D
## 背景の星、放射線域、セクター境界。セクターの種類で色味が変わる。

var world_radius: float = 2200.0
var tint := Color.WHITE
var zones: Array = []
var _stars: Array = []
var _t: float = 0.0


func regenerate(seed_value: int, new_tint: Color, new_zones: Array) -> void:
	tint = new_tint
	zones = new_zones
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_stars.clear()
	for i in 900:
		var r := world_radius * 1.4
		_stars.append([Vector2(rng.randf_range(-r, r), rng.randf_range(-r, r)), rng.randf_range(0.5, 2.0), rng.randf_range(0.2, 0.8)])
	# 星雲っぽいぼかし
	for i in 14:
		var r := world_radius
		_stars.append([Vector2(rng.randf_range(-r, r), rng.randf_range(-r, r)), rng.randf_range(250.0, 600.0), -1.0])
	queue_redraw()


func in_zone(p: Vector2) -> bool:
	for z in zones:
		if p.distance_to(z["pos"]) < float(z["radius"]):
			return true
	return false


func _process(delta: float) -> void:
	_t += delta
	if not zones.is_empty():
		queue_redraw()


func _draw() -> void:
	var haze := tint.darkened(0.2)
	for s in _stars:
		if s[2] < 0.0:
			for i in 5:
				draw_circle(s[0], s[1] * (1.0 - i * 0.18), Color(haze, 0.01))
	for s in _stars:
		if s[2] >= 0.0:
			draw_circle(s[0], s[1], Color(tint.lerp(Color.WHITE, 0.6), s[2]))
	for z in zones:
		var pulse := 0.5 + 0.5 * sin(_t * 2.0)
		draw_circle(z["pos"], z["radius"], Color(1.0, 0.25, 0.2, 0.07 + 0.04 * pulse))
		draw_arc(z["pos"], z["radius"], 0.0, TAU, 64, Color(1.0, 0.35, 0.25, 0.5), 2.0)
	draw_arc(Vector2.ZERO, world_radius, 0.0, TAU, 128, Color(1.0, 0.3, 0.3, 0.35), 3.0)
