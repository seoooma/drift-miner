class_name Miner
extends Node2D
## 自動採掘機。小惑星を掘って内部に貯め、プレイヤーが近づくと回収される。
## 貯蔵が満杯になると止まるので、巡回して回収する「物流」の判断が生まれる。
## 小惑星が枯渇した後も、貯蔵分が残っていれば回収できる。

const BASE_RATE := 1.5
const BASE_STORAGE := 20.0

var asteroid: Asteroid = null
var kind: String = "iron"
var stored: float = 0.0
var _spin: float = 0.0


func setup(a: Asteroid) -> void:
	asteroid = a
	kind = a.kind
	global_position = a.global_position


func capacity() -> float:
	return BASE_STORAGE * GameState.storage_mult


func rate() -> float:
	var r := BASE_RATE * GameState.miner_mult
	if kind == "ice":
		r *= 0.5
	elif kind == "crystal" and not GameState.crystal_drill:
		r *= 0.4
	return r


func is_working() -> bool:
	return asteroid != null and is_instance_valid(asteroid) and asteroid.is_alive() and stored < capacity()


func is_full() -> bool:
	return stored >= capacity() - 0.01


func _process(delta: float) -> void:
	if is_working():
		stored += asteroid.extract(minf(rate() * delta, capacity() - stored))
		_spin += delta * 3.0 * GameState.miner_mult
	elif stored <= 0.01 and (asteroid == null or not is_instance_valid(asteroid) or not asteroid.is_alive()):
		queue_free()
	queue_redraw()


## 回収：最大 want を取り出す。
func take(want: float) -> float:
	var got := minf(want, stored)
	stored -= got
	return got


func _draw() -> void:
	var c: Color = Asteroid.COLORS[kind]
	var body := Color(1.0, 0.85, 0.3) if is_working() else Color(0.6, 0.55, 0.4)
	draw_rect(Rect2(-7, -7, 14, 14), body)
	for i in 3:
		var dir := Vector2.from_angle(_spin + TAU * i / 3.0)
		draw_line(dir * 7.0, dir * 15.0, body, 3.0)
	# 貯蔵ゲージ（満杯は点滅）
	var frac := stored / capacity()
	var col := c
	if is_full():
		col.a = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.01)
	draw_arc(Vector2.ZERO, 20.0, -PI / 2, -PI / 2 + TAU * frac, 24, col, 4.0)
