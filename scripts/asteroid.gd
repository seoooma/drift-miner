class_name Asteroid
extends Node2D
## 採掘できる小惑星。形はシードからランダム生成した多角形。

signal depleted(asteroid: Asteroid)

const COLORS := {
	"iron": Color(0.72, 0.75, 0.85),
	"copper": Color(0.95, 0.55, 0.3),
	"ice": Color(0.55, 0.85, 1.0),
	"crystal": Color(0.9, 0.45, 1.0),
}

var kind: String = "iron"
var radius: float = 30.0
var amount: float = 50.0
var max_amount: float = 50.0
var discovered: bool = false
var has_miner: bool = false
var _points := PackedVector2Array()
var _shake: float = 0.0


func setup(data: Dictionary) -> void:
	position = data["pos"]
	radius = data["radius"]
	kind = data["kind"]
	amount = data["amount"]
	max_amount = amount
	var rng := RandomNumberGenerator.new()
	rng.seed = data["shape_seed"]
	var n := rng.randi_range(9, 14)
	for i in n:
		var d := radius * rng.randf_range(0.75, 1.1)
		_points.append(Vector2.from_angle(TAU * i / n) * d)
	rotation = rng.randf() * TAU
	visible = false


func color() -> Color:
	return COLORS[kind]


## 最大 want だけ掘り出し、実際に掘れた量を返す。枯渇したら消える。
func extract(want: float, hit: bool = false) -> float:
	if amount <= 0.0:
		return 0.0
	var got := minf(want, amount)
	amount -= got
	if hit:
		_shake = 0.12
	queue_redraw()
	if amount <= 0.0:
		depleted.emit(self)
		queue_free()
	return got


func is_alive() -> bool:
	return amount > 0.0 and not is_queued_for_deletion()


func _process(delta: float) -> void:
	if _shake > 0.0:
		_shake -= delta
		var s := 1.0 + 0.05 * sin(Time.get_ticks_msec() * 0.06)
		scale = Vector2(s, s)
		if _shake <= 0.0:
			scale = Vector2.ONE


func _draw() -> void:
	var c := color()
	draw_colored_polygon(_points, c.darkened(0.6))
	var outline := _points.duplicate()
	outline.append(_points[0])
	draw_polyline(outline, c, 2.0)
	# 残量ゲージ
	var frac := amount / max_amount
	draw_arc(Vector2.ZERO, radius + 7.0, 0.0, TAU * frac, 32, Color(c, 0.6), 2.0)
