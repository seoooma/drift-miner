class_name Player
extends Node2D
## プレイヤー機（オートパイロット）。
## 状況を見て「次にやること」を自分で決め、移動・採掘・回収・漂流物の回収・ゲートへの移動を行う。
## プレイヤーは航路とカードを選ぶだけで、操縦はしない。

const ACCEL := 620.0
const MAX_SPEED := 320.0
const MINE_RANGE := 230.0
const MINE_RATE := 6.0
const IDLE_BURN := 0.6
const THRUST_BURN := 0.9
const COLLECT_RANGE := 200.0
const COLLECT_RATE := 30.0
const THINK_INTERVAL := 0.4
const CELL := 420.0

var velocity := Vector2.ZERO
var main: Node = null
var touch: Node = null
var world_radius: float = 2200.0
var camera: Camera2D

## いまの行動（HUD に表示する）
var status: String = "待機"
var mine_target: Asteroid = null
var mining: bool = false
var collecting: Array = []

var _goal := Vector2.ZERO
var _goal_node: Node2D = null
var _goal_stop: float = 40.0
var _think: float = 0.0
var _visited := {}
var _explore_goal := Vector2.INF
var _particles: CPUParticles2D
var _popup_acc := {}
var _shake: float = 0.0
var _lead := Vector2.ZERO


func _ready() -> void:
	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 4.0
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


## 新しいセクターに入ったときに呼ぶ。
func reset_sector() -> void:
	velocity = Vector2.ZERO
	_visited.clear()
	_explore_goal = Vector2.INF
	mine_target = null
	_goal_node = null
	_think = 0.0
	status = "周辺を調査"


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
	camera.zoom = Vector2(0.52, 0.52) if use_touch else Vector2(0.75, 0.75)

	_visited[_cell_of(position)] = true
	_think -= delta
	if _think <= 0.0:
		_think = THINK_INTERVAL
		_decide()

	# 目標へ向かう（近づくと減速）
	var target := _goal
	if _goal_node != null and is_instance_valid(_goal_node):
		target = _goal_node.global_position
	var dodge := _meteor_dodge()
	var thrust := 0.0
	var to := target - position
	var dist := to.length()
	var desired := Vector2.ZERO
	if dodge != Vector2.ZERO:
		desired = dodge * MAX_SPEED
	elif dist > _goal_stop:
		var spd := minf(MAX_SPEED, (dist - _goal_stop) * 1.6 + 40.0)
		desired = to / dist * spd
	var steer := (desired - velocity).limit_length(ACCEL * delta)
	velocity += steer
	thrust = clampf(steer.length() / (ACCEL * delta + 0.001), 0.0, 1.0) if desired != Vector2.ZERO else 0.0
	velocity = velocity.limit_length(MAX_SPEED)
	position += velocity * delta
	if position.length() > world_radius:
		position = position.normalized() * world_radius
		velocity *= 0.5

	GameState.burn_fuel((IDLE_BURN + THRUST_BURN * thrust) * delta * main.zone_burn_mult(position))

	# 採掘：目標の小惑星が範囲内なら掘る。範囲内に他の小惑星しかなくても、ついでに掘る
	mining = false
	var a := mine_target
	if a == null or not is_instance_valid(a) or not a.is_alive() or not in_range(a):
		a = _nearest_in_range()
	var face := position + (velocity if velocity.length() > 20.0 else Vector2.from_angle(rotation))
	if a != null:
		mining = true
		face = a.global_position
		var col := a.color()
		var kind := a.kind
		var hit_pos := a.global_position
		var got := a.extract(MINE_RATE * GameState.ship_mine_mult * delta, true)
		GameState.add_ore(kind, got)
		_accumulate_popup(kind, got, hit_pos, col)
		_particles.global_position = hit_pos + (global_position - hit_pos).normalized() * a.radius * 0.8
		_particles.color = col
		_particles.direction = (global_position - hit_pos).normalized()
		_mine_beam_target = a
	else:
		_mine_beam_target = null
	_particles.emitting = mining
	rotation = lerp_angle(rotation, (face - global_position).angle(), clampf(delta * 10.0, 0.0, 1.0))

	_collect(delta)
	queue_redraw()


var _mine_beam_target: Asteroid = null


# ---------------------------------------------------------------- 判断


func _decide() -> void:
	var gs := GameState
	mine_target = null
	_goal_node = null
	_goal_stop = 40.0

	# 1. 航路が決まっていればゲートへ
	var gate: WarpGate = main.route_gate
	if gate != null and is_instance_valid(gate):
		_goal_node = gate
		_goal_stop = 30.0
		status = "ゲートへ移動中（%dm）" % int(position.distance_to(gate.position))
		return

	var fuel_frac := gs.fuel / gs.max_fuel

	# 2. 燃料が少なければ氷を掘る
	if fuel_frac < 0.4:
		var ice := _nearest_asteroid(["ice"], 99999.0)
		if ice != null:
			_mine(ice, "氷を採掘して燃料を補給")
			return

	# 3. ハブが届かない採掘機に貯まった鉱石を回収
	var m := _best_uncovered_miner()
	if m != null:
		_goal_node = m
		_goal_stop = 60.0
		status = "採掘機から鉱石を回収"
		return

	# 4. 見つけた漂流物を開ける（燃料に余裕がある時だけ）
	if fuel_frac > 0.25:
		var d: Derelict = main.nearest_derelict(position, 1100.0)
		if d != null:
			_goal_node = d
			_goal_stop = 0.0
			status = "漂流物を調べる"
			return

	# 5. ワープの資源がそろったのにゲートが未発見なら、信号の方へ探索
	if gs.can_afford(gs.warp_cost()) and not main.any_gate_found():
		var g: WarpGate = main.nearest_hidden_gate(position)
		if g != null:
			_goal = g.position
			status = "ゲートの信号を追跡"
			return

	# 6. 足りない鉱石を掘る
	for k in main.needed_ores():
		var a := _nearest_asteroid([k], 1400.0)
		if a != null:
			_mine(a, "%sを採掘" % _kind_name(String(a.kind)))
			return

	# 7. 未踏の宙域を探索
	_explore()


func _mine(a: Asteroid, text: String) -> void:
	mine_target = a
	_goal_node = a
	_goal_stop = a.radius + MINE_RANGE * 0.55
	status = text


func _explore() -> void:
	if _explore_goal == Vector2.INF or position.distance_to(_explore_goal) < 120.0 or _visited.has(_cell_of(_explore_goal)):
		_explore_goal = _pick_unvisited()
	_goal = _explore_goal
	status = "未踏の宙域を探索"


func _pick_unvisited() -> Vector2:
	var best := Vector2.ZERO
	var best_score := INF
	var n := int(world_radius / CELL)
	for x in range(-n, n + 1):
		for y in range(-n, n + 1):
			var c := Vector2i(x, y)
			if _visited.has(c):
				continue
			var p := Vector2(x, y) * CELL
			if p.length() > world_radius - 100.0:
				continue
			# 自機から近く、母船からも離れすぎない場所を優先
			var s := p.distance_to(position) + p.length() * 0.35 + randf() * 120.0
			if s < best_score:
				best_score = s
				best = p
	if best_score == INF:
		_visited.clear()
		return Vector2.from_angle(randf() * TAU) * world_radius * 0.6
	return best


func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x / CELL), roundi(p.y / CELL))


func _kind_name(kind: String) -> String:
	match kind:
		"iron":
			return "鉄鉱石"
		"copper":
			return "銅鉱石"
		"crystal":
			return "結晶"
	return "氷"


func _nearest_asteroid(kinds: Array, max_core_dist: float) -> Asteroid:
	var best: Asteroid = null
	var best_d := INF
	for c in main.asteroid_layer.get_children():
		var ast := c as Asteroid
		if not ast.discovered or not ast.is_alive() or not (ast.kind in kinds):
			continue
		if ast.position.length() > max_core_dist:
			continue
		# 採掘機付きの小惑星は後回し
		var d := ast.position.distance_to(position) + (400.0 if ast.has_miner else 0.0)
		if d < best_d:
			best = ast
			best_d = d
	return best


func _nearest_in_range() -> Asteroid:
	var best: Asteroid = null
	var best_d := INF
	for c in main.asteroid_layer.get_children():
		var ast := c as Asteroid
		if not ast.discovered or not ast.is_alive() or not in_range(ast):
			continue
		var d := ast.position.distance_to(position)
		if d < best_d:
			best = ast
			best_d = d
	return best


func _best_uncovered_miner() -> Miner:
	var best: Miner = null
	var best_s := INF
	for c in main.miners():
		var mm := c as Miner
		if main.hub_covers(mm.global_position):
			continue
		if mm.stored < mm.capacity() * 0.6:
			continue
		var s := mm.global_position.distance_to(position)
		if s < best_s:
			best = mm
			best_s = s
	return best


## 隕石の予告円の中にいたら、外へ逃げる方向を返す。
func _meteor_dodge() -> Vector2:
	for c in main.fx_layer.get_children():
		if c is Meteor:
			var off: Vector2 = position - (c as Meteor).position
			if off.length() < Meteor.RADIUS + 30.0:
				status = "隕石を回避"
				return off.normalized() if off.length() > 1.0 else Vector2.RIGHT
	return Vector2.ZERO


# ---------------------------------------------------------------- 回収と表示


func _accumulate_popup(kind: String, got: float, pos: Vector2, col: Color) -> void:
	var acc: float = float(_popup_acc.get(kind, 0.0)) + got
	if acc >= 4.0:
		var real := kind.trim_prefix("c_")
		var label := "燃料" if real == "ice" else _kind_name(real)
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
			GameState.add_ore(miner.kind, got)
			collecting.append(miner)
			_accumulate_popup("c_" + miner.kind, got, miner.global_position, Asteroid.COLORS[miner.kind])


func in_range(a: Asteroid) -> bool:
	return global_position.distance_to(a.global_position) - a.radius <= MINE_RANGE


func _update_camera(delta: float) -> void:
	_lead = _lead.lerp(velocity * 0.2, clampf(delta * 2.0, 0.0, 1.0))
	var off := _lead
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 30.0)
		off += Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
	camera.offset = off


func _draw() -> void:
	draw_arc(Vector2.ZERO, MINE_RANGE, 0.0, TAU, 64, Color(1, 1, 1, 0.05), 1.0)
	for m in collecting:
		if is_instance_valid(m):
			draw_line(Vector2.ZERO, to_local(m.global_position), Color(1.0, 0.9, 0.4, 0.5), 2.0)
	var a := _mine_beam_target
	if mining and a != null and is_instance_valid(a):
		var end := to_local(a.global_position)
		var w := 3.0 + sin(Time.get_ticks_msec() * 0.05) * 1.5
		draw_line(Vector2.ZERO, end, Color(1.0, 0.4, 0.3, 0.9), w)
		draw_circle(end, 6.0, Color(1.0, 0.7, 0.3, 0.8))
	var hull := PackedVector2Array([Vector2(18, 0), Vector2(-12, -11), Vector2(-6, 0), Vector2(-12, 11)])
	draw_colored_polygon(hull, Color(0.85, 0.9, 1.0))
	if velocity.length() > 30.0:
		var flick := 4.0 + randf() * 3.0
		draw_circle(to_local(global_position - velocity.normalized() * 12.0), flick, Color(0.4, 0.7, 1.0, 0.8))
