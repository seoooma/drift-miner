class_name Player
extends Node2D
## プレイヤー機。WASDで移動、マウスの方向を向き、左クリック長押しで採掘。

const ACCEL := 700.0
const MAX_SPEED := 340.0
const DRAG := 1.6
const MINE_RANGE := 230.0
const MINE_RATE := 6.0
const IDLE_BURN := 0.8
const THRUST_BURN := 0.9

var velocity := Vector2.ZERO
var main: Node = null
var touch: Node = null  # TouchControls（スマホ操作）
var world_radius: float = 2200.0
var _target: Asteroid = null


func _ready() -> void:
	var cam := Camera2D.new()
	add_child(cam)
	cam.make_current()


func _process(delta: float) -> void:
	if not GameState.alive:
		return
	var input := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		input.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		input.y += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		input.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		input.x += 1.0
	input = input.normalized()
	var use_touch: bool = touch != null and touch.active
	if use_touch and touch.move_vector != Vector2.ZERO:
		input = touch.move_vector

	velocity += input * ACCEL * delta
	velocity -= velocity * DRAG * delta * (0.3 if input != Vector2.ZERO else 1.0)
	velocity = velocity.limit_length(MAX_SPEED)
	position += velocity * delta
	if position.length() > world_radius:
		position = position.normalized() * world_radius
		velocity *= 0.5

	var aim := get_global_mouse_position()
	var mining: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if use_touch:
		mining = touch.aiming
		if touch.aiming:
			aim = touch.aim_world()
		elif velocity.length() > 20.0:
			aim = global_position + velocity
		else:
			aim = global_position + Vector2.from_angle(rotation)
	rotation = (aim - global_position).angle()
	GameState.burn_fuel((IDLE_BURN + (THRUST_BURN if input != Vector2.ZERO else 0.0)) * delta)

	_target = null
	if mining and main != null:
		var a: Asteroid = main.asteroid_at(aim, 1.6 if use_touch else 1.1)
		if a != null and in_range(a):
			_target = a
			var got := a.extract(MINE_RATE * GameState.mine_mult * delta)
			GameState.add_res(a.kind, got)
	queue_redraw()


func in_range(a: Asteroid) -> bool:
	return global_position.distance_to(a.global_position) - a.radius <= MINE_RANGE


func _draw() -> void:
	# 採掘範囲
	draw_arc(Vector2.ZERO, MINE_RANGE, 0.0, TAU, 64, Color(1, 1, 1, 0.06), 1.0)
	# 採掘ビーム
	if _target != null and is_instance_valid(_target):
		var end := to_local(_target.global_position)
		draw_line(Vector2(14, 0), end, Color(1.0, 0.4, 0.3, 0.9), 3.0)
		draw_circle(end, 6.0, Color(1.0, 0.7, 0.3, 0.8))
	# 機体
	var hull := PackedVector2Array([Vector2(18, 0), Vector2(-12, -11), Vector2(-6, 0), Vector2(-12, 11)])
	draw_colored_polygon(hull, Color(0.85, 0.9, 1.0))
	if velocity.length() > 30.0:
		draw_circle(Vector2(-10, 0), 4.0, Color(0.4, 0.7, 1.0, 0.8))
	# ワープゲートの方向（発見済みのとき）
	if main != null and main.gate.discovered:
		var dir := to_local(main.gate.global_position).normalized()
		var tip := dir * 70.0
		draw_line(dir * 40.0, tip, Color(0.3, 1.0, 0.6, 0.8), 2.0)
		draw_circle(tip, 4.0, Color(0.3, 1.0, 0.6, 0.8))
