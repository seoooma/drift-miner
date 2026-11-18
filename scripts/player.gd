class_name Player
extends Node2D
## プレイヤー機。WASD/スティックで移動、マウス/タッチで狙った小惑星を採掘。
## 採掘機の近くを通ると貯まった資源を自動で回収する。

const ACCEL := 700.0
const MAX_SPEED := 340.0
const DRAG := 1.6
const MINE_RANGE := 230.0
const MINE_RATE := 6.0
const IDLE_BURN := 0.6
const THRUST_BURN := 0.9
const COLLECT_RANGE := 200.0
const COLLECT_RATE := 30.0

var velocity := Vector2.ZERO
var main: Node = null
var touch: Node = null  # TouchControls（スマホ操作）
var world_radius: float = 2200.0
var camera: Camera2D

## 狙っている小惑星（範囲外も含む）と、実際に掘っているか
var aim_target: Asteroid = null
var mining: bool = false
var collecting: Array = []

var _particles: CPUParticles2D
var _popup_acc := {}
var _shake: float = 0.0
var _lead := Vector2.ZERO


func _ready() -> void:
	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	add_child(camera)
	camera.make_current()

	_particles = CPUParticles2D.new()
	_particles.top_level = true
	_particles.amount = 24
	_particles.lifetime = 0.45
	_particles.spread = 180.0
	_particles.gravity = Vector2.ZERO
	_particles.initial_velocity_min = 60.0
	_particles.initial_velocity_max = 140.0
	_particles.scale_amount_min = 2.0
	_particles.scale_amount_max = 3.5
	_particles.emitting = false
	add_child(_particles)


func collect_range() -> float:
	return COLLECT_RANGE * GameState.collect_mult


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _process(delta: float) -> void:
	_update_camera(delta)
	if not GameState.alive:
		_particles.emitting = false
		return
	var use_touch: bool = touch != null and touch.active
	camera.zoom = Vector2(0.8, 0.8) if use_touch else Vector2.ONE

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
	if use_touch and touch.move_vector != Vector2.ZERO:
		input = touch.move_vector

	velocity += input * ACCEL * delta
	velocity -= velocity * DRAG * delta * (0.3 if input != Vector2.ZERO else 1.0)
	velocity = velocity.limit_length(MAX_SPEED)
	position += velocity * delta
	if position.length() > world_radius:
		position = position.normalized() * world_radius
		velocity *= 0.5

	GameState.burn_fuel((IDLE_BURN + THRUST_BURN * input.length()) * delta * main.zone_burn_mult(position))

	# 照準：狙った位置の近くの小惑星に吸い付く（指で隠れないよう、照準は小惑星側に描く）
	var aim := get_global_mouse_position()
	var want_mine: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var slack := 12.0
	if use_touch:
		want_mine = touch.aiming
		aim = touch.aim_world()
		slack = 90.0 / camera.zoom.x
	aim_target = main.lock_target(aim, slack) if (want_mine or not use_touch) else null

	var face := aim
	if not want_mine:
		face = global_position + (velocity if velocity.length() > 20.0 else Vector2.from_angle(rotation))
	elif aim_target != null:
		face = aim_target.global_position
	rotation = lerp_angle(rotation, (face - global_position).angle(), clampf(delta * 14.0, 0.0, 1.0))

	mining = false
	if want_mine and aim_target != null and in_range(aim_target):
		mining = true
		var a := aim_target
		var col := a.color()
		var kind := a.kind
		var hit_pos := a.global_position
		var got := a.extract(MINE_RATE * GameState.mine_mult * delta, true)
		GameState.add_res(kind, got)
		_accumulate_popup(kind, got, hit_pos, col)
		_particles.global_position = hit_pos + (global_position - hit_pos).normalized() * a.radius * 0.8
		_particles.color = col
		_particles.direction = (global_position - hit_pos).normalized()
	_particles.emitting = mining

	_collect(delta)
	queue_redraw()


func _accumulate_popup(kind: String, got: float, pos: Vector2, col: Color) -> void:
	var acc: float = float(_popup_acc.get(kind, 0.0)) + got
	if acc >= 3.0:
		var real := kind.trim_prefix("c_")
		var label := "燃料" if real == "ice" else String(GameState.RES_NAMES[real])
		var shown := int(acc * 0.5 * GameState.ice_fuel_mult) if real == "ice" else int(acc)
		Fx.popup(main.fx_layer, pos, "+%d %s" % [shown, label], col.lightened(0.3))
		acc = 0.0
	_popup_acc[kind] = acc


func _collect(delta: float) -> void:
	collecting.clear()
	var r := collect_range()
	for m in main.miners():
		var miner := m as Miner
		if miner.stored <= 0.01 or miner.global_position.distance_to(global_position) > r:
			continue
		var got := miner.take(COLLECT_RATE * delta)
		if got > 0.0:
			GameState.add_res(miner.kind, got)
			collecting.append(miner)
			_accumulate_popup("c_" + miner.kind, got, miner.global_position, Asteroid.COLORS[miner.kind])


func in_range(a: Asteroid) -> bool:
	return global_position.distance_to(a.global_position) - a.radius <= MINE_RANGE


func _update_camera(delta: float) -> void:
	_lead = _lead.lerp(velocity * 0.25, clampf(delta * 3.0, 0.0, 1.0))
	var off := _lead
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 30.0)
		off += Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
	camera.offset = off


func _draw() -> void:
	# 採掘範囲と回収範囲
	draw_arc(Vector2.ZERO, MINE_RANGE, 0.0, TAU, 64, Color(1, 1, 1, 0.06), 1.0)
	# 回収ビーム
	for m in collecting:
		if is_instance_valid(m):
			draw_line(Vector2.ZERO, to_local(m.global_position), Color(1.0, 0.9, 0.4, 0.5), 2.0)
	# 照準と採掘ビーム
	if aim_target != null and is_instance_valid(aim_target):
		var end := to_local(aim_target.global_position)
		var r := aim_target.radius + 12.0
		var ok := in_range(aim_target)
		var rc := Color(1.0, 0.6, 0.3, 0.9) if ok else Color(0.6, 0.6, 0.6, 0.7)
		var spin := Time.get_ticks_msec() * 0.003
		for i in 4:
			var a0 := spin + TAU * i / 4.0
			draw_arc(end, r, a0, a0 + 0.9, 8, rc, 3.0)
		if mining:
			var w := 3.0 + sin(Time.get_ticks_msec() * 0.05) * 1.5
			draw_line(Vector2(14, 0).rotated(0), end, Color(1.0, 0.4, 0.3, 0.9), w)
			draw_circle(end, 6.0, Color(1.0, 0.7, 0.3, 0.8))
	# タッチ時：「採掘機」ボタンで設置される先を予告
	if touch != null and touch.active and GameState.alive:
		var nf: Asteroid = main.nearest_free_asteroid()
		if nf != null:
			var c := to_local(nf.global_position)
			var rr := nf.radius + 18.0
			for i in 12:
				var a0 := TAU * i / 12.0 + Time.get_ticks_msec() * 0.001
				draw_arc(c, rr, a0, a0 + 0.25, 4, Color(1.0, 0.85, 0.3, 0.55), 2.0)
	# 機体
	var hull := PackedVector2Array([Vector2(18, 0), Vector2(-12, -11), Vector2(-6, 0), Vector2(-12, 11)])
	draw_colored_polygon(hull, Color(0.85, 0.9, 1.0))
	if velocity.length() > 30.0:
		var flick := 4.0 + randf() * 3.0
		draw_circle(to_local(global_position - velocity.normalized() * 12.0), flick, Color(0.4, 0.7, 1.0, 0.8))
