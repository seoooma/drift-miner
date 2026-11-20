class_name Tools
extends Node2D
## 採掘ツールの動きと描画。どのツールも機体の集まる場所 (focus) の近くで、
## 外に面した価値の高いマスを自動で選んで削る。回転や周回はしない。
## 同じマスを取り合わないよう、狙いは機体ごとに分担する（範囲攻撃のツールは
## 互いに離れた場所、ドローンとスウォームはまだ誰も狙っていないマス）。
## 機体は外とつながった空きだけを飛び、まだ掘っていない岩の中には入らない。
## 威力（毎秒ダメージ）は GameState から毎フレーム読む。

var planet: Planet = null
var fx_layer: Node2D = null
var focus := Vector2.ZERO  # main.gd が毎フレーム入れる
var dest := Vector2.INF  # プレイヤーが指定した移動先（なければ INF）

var _t: float = 0.0
var _targets: Array = []  # 狙う順に並んだマス番号
var _scan_t: float = 0.0
var _drones: Array = []  # {"pos", "target"}
var _claimed := {}  # マス番号 → 狙っている機体がいる
var _drill_pos := Vector2.INF
var _drill_target: int = -1
var _drill_pulse: float = 0.0
var _drill_flash: float = 0.0
var _sat_pos := Vector2.INF
var _laser_target: int = -1
var _laser_t: float = 0.0
var _laser_hit := Vector2.INF
var _lance_from := Vector2.INF
var _lance_hit := Vector2.INF
var _bomb_timer: float = 1.0
var _bombs: Array = []  # {"from", "to", "t", "dmg"}
var _bots: Array = []  # {"pos", "target"}
var _taps: Array = []  # {"pos", "t"}


func reset_for(p: Planet) -> void:
	planet = p
	_targets.clear()
	_scan_t = 0.0
	_drones.clear()
	_bots.clear()
	_bombs.clear()
	_drill_pos = Vector2.INF
	_drill_target = -1
	_sat_pos = Vector2.INF
	_laser_target = -1
	_claimed.clear()


## 狙いの中心が変わったらすぐ選び直す（タップしたとき）
func rescan() -> void:
	_scan_t = 0.0
	_laser_target = -1
	_drill_target = -1
	for d in _drones:
		d["target"] = -1
	for b in _bots:
		b["target"] = -1


func _sky(i: int) -> Vector2:
	return planet.outward(i)


func _pick(k: int) -> int:
	if _targets.is_empty():
		return -1
	return int(_targets[k % _targets.size()])


## まだ誰も狙っていないマスを、狙う順に探す。avoid の近く（r 以内）は避ける。
## 空いているマスがなければ、狙われていても一番よいマスを返す。
func _pick_free(avoid: Array = [], r: float = 0.0, from: int = 0, limit: int = 0) -> int:
	var n := _targets.size() if limit <= 0 else mini(limit, _targets.size())
	for k in range(from, n):
		var i := int(_targets[k])
		if _claimed.has(i) or not planet.is_alive(i):
			continue
		var c := planet.cell_center(i)
		var near := false
		for a in avoid:
			if (a as Vector2) != Vector2.INF and c.distance_to(a) < r:
				near = true
				break
		if not near:
			return i
	return _pick(from)


## pos から goal へ進む。途中が岩なら、惑星の外向きに逃げてから回り込む。
func _fly(pos: Vector2, goal: Vector2, speed: float) -> Vector2:
	var np := pos.move_toward(goal, speed)
	if planet.is_open(np):
		return np
	return _escape(pos, speed)


func _escape(pos: Vector2, speed: float) -> Vector2:
	var out := (pos - planet.position).normalized()
	for a in [0.0, 0.6, -0.6, 1.2, -1.2]:
		var np := pos + out.rotated(a) * speed
		if planet.is_open(np):
			return np
	return pos + out * speed


func _process(delta: float) -> void:
	_t += delta
	if planet == null or planet.done:
		queue_redraw()
		return
	var gs := GameState
	var mv := gs.move_mult()

	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.25
		_targets = planet.targets_near(focus, 9)
	while not _targets.is_empty() and not planet.is_alive(int(_targets[0])):
		_targets.pop_front()

	# 誰がどのマスを狙っているか（毎フレーム作り直す）
	_claimed.clear()
	for d in _drones:
		if planet.is_alive(int(d["target"])):
			_claimed[int(d["target"])] = true
	for b in _bots:
		if planet.is_alive(int(b["target"])):
			_claimed[int(b["target"])] = true

	# パルスドリル：一番よい候補に降りて、一定間隔で周りごと砕く
	var drill := gs.tool_dps("cutter")
	var drill_c := Vector2.INF
	if drill > 0.0:
		if not planet.is_alive(_drill_target) or not planet.is_exposed(_drill_target):
			_drill_target = _pick_free()
		if _drill_target >= 0:
			drill_c = planet.cell_center(_drill_target)
			var hp := planet.hover_point(_drill_target, Planet.CELL)
			_drill_pos = hp if _drill_pos == Vector2.INF else _fly(_drill_pos, hp, 70.0 * mv * delta)
			_drill_pulse += delta
			if _drill_pulse >= 0.5 and _drill_pos.distance_to(hp) < Planet.CELL:
				_drill_pulse = 0.0
				_drill_flash = 1.0
				planet.hit_area(drill_c, Planet.CELL * 2.5, drill * 0.5)
	_drill_flash = maxf(0.0, _drill_flash - delta * 4.0)

	# 精密レーザー：上空の衛星から、ドリルと離れた価値の高いマスを撃ち抜く
	var las := gs.tool_dps("laser")
	_laser_hit = Vector2.INF
	if las > 0.0:
		var up := (focus - planet.position).normalized() if focus.distance_to(planet.position) > 1.0 else Vector2.UP
		var sat_home := focus + up * 62.0 + up.orthogonal() * sin(_t * 0.7) * 20.0
		_sat_pos = sat_home if _sat_pos == Vector2.INF else _sat_pos.lerp(sat_home, clampf(delta * 2.0, 0.0, 1.0))
		_laser_t -= delta
		if not planet.is_alive(_laser_target) or _laser_t <= 0.0:
			_laser_t = 1.2
			_laser_target = _pick_free([drill_c], Planet.CELL * 4.0)
		if _laser_target >= 0:
			_laser_hit = planet.cell_center(_laser_target)
			planet.hit_area(_laser_hit, Planet.CELL * 1.6, las * delta)

	# 採掘ドローン：1機ずつ、まだ誰も狙っていないマスに取り付いてビームで削る
	var drone_dps := gs.tool_dps("drone")
	var n := gs.drone_count() if drone_dps > 0.0 else 0
	while _drones.size() < n:
		_drones.append({"pos": focus, "target": -1})
	while _drones.size() > n:
		_drones.pop_back()
	var busy := [drill_c, _laser_hit]
	for k in _drones.size():
		var d: Dictionary = _drones[k]
		var tgt := int(d["target"])
		if not planet.is_alive(tgt) or planet.cell_center(tgt).distance_to(focus) > Planet.CELL * 12.0:
			_claimed.erase(tgt)
			tgt = _pick_free(busy, Planet.CELL * 2.0)
			d["target"] = tgt
			if tgt >= 0:
				_claimed[tgt] = true
		var home := focus + Vector2.from_angle(_t * 0.8 + TAU * k / maxf(1.0, n)) * 14.0
		if tgt >= 0:
			home = planet.hover_point(tgt, Planet.CELL * 2.5)
			if (d["pos"] as Vector2).distance_to(home) < Planet.CELL * 1.5:
				planet.hit(tgt, drone_dps / n * delta)
		d["pos"] = _fly(d["pos"], home, 90.0 * mv * delta)

	# 重力爆雷：ほかの機体が掘っていない候補へ落ちて広く砕く
	var bomb := gs.tool_dps("bomb")
	if bomb > 0.0:
		_bomb_timer -= delta
		if _bomb_timer <= 0.0 and not _targets.is_empty():
			_bomb_timer = 2.0
			var i := _pick_free([drill_c, _laser_hit], Planet.CELL * 5.0, randi() % mini(4, _targets.size()))
			var to := planet.cell_center(i)
			var from := to + planet.open_dir(i) * 110.0
			_bombs.append({"from": from, "to": to, "t": 0.0, "dmg": bomb * 2.0})
	for b in _bombs.duplicate():
		b["t"] = float(b["t"]) + delta * 2.2
		if float(b["t"]) >= 1.0:
			_bombs.erase(b)
			planet.hit_area(b["to"], Planet.CELL * 4.5, float(b["dmg"]))
			if fx_layer != null:
				Fx.burst(fx_layer, b["to"], Color(0.8, 0.5, 1.0), 26, 180.0)

	# コアランス：機体の集まる場所から惑星の中心核へまっすぐ掘り進む
	var lan := gs.tool_dps("lance")
	_lance_hit = Vector2.INF
	if lan > 0.0:
		var c := planet.position
		var dir := (c - focus).normalized() if focus.distance_to(c) > 1.0 else Vector2.DOWN
		_lance_from = focus - dir * 70.0
		var i := planet.raycast(_lance_from, c + dir * Planet.CELL)
		if i >= 0 and planet.is_exposed(i):
			_lance_hit = planet.cell_center(i)
			planet.hit_area(_lance_hit, Planet.CELL * 1.2, lan * delta)

	# ナノスウォーム：小さな機械が1匹ずつ別のマスに散らばって食べる
	var sw := gs.tool_dps("swarm")
	if sw > 0.0:
		while _bots.size() < 28:
			_bots.append({"pos": focus, "target": -1})
		for b in _bots:
			var tgt := int(b["target"])
			if not planet.is_alive(tgt):
				tgt = _pick_free([], 0.0, 0, 40)
				b["target"] = tgt
				if tgt >= 0:
					_claimed[tgt] = true
				continue
			var tp := planet.hover_point(tgt, Planet.CELL * 0.7)
			b["pos"] = _fly(b["pos"], tp, 120.0 * mv * delta)
			if (b["pos"] as Vector2).distance_to(tp) < 4.0:
				planet.hit(tgt, sw / _bots.size() * delta)

	for tp in _taps.duplicate():
		tp["t"] = float(tp["t"]) + delta * 1.5
		if float(tp["t"]) >= 1.0:
			_taps.erase(tp)
	queue_redraw()


func tap_effect(p: Vector2) -> void:
	_taps.append({"pos": p, "t": 0.0})


func _draw() -> void:
	if planet == null:
		return
	var gs := GameState

	# 狙いの中心（うっすらした照準）
	if not planet.done:
		var fc := Color(1, 1, 1, 0.18 + 0.06 * sin(_t * 3.0))
		draw_arc(focus, Planet.CELL * 9.0, 0.0, TAU, 48, fc, 1.0)
		for k in 4:
			var a := TAU * k / 4.0 + _t * 0.3
			draw_line(focus + Vector2.from_angle(a) * Planet.CELL * 8.2, focus + Vector2.from_angle(a) * Planet.CELL * 9.8, Color(1, 1, 1, 0.4), 1.0)

	# プレイヤーが指定した移動先
	if dest != Vector2.INF:
		var pc := Color(0.5, 1.0, 0.8, 0.7 + 0.3 * sin(_t * 6.0))
		var bob := Vector2(0, -6.0 - 2.0 * sin(_t * 4.0))
		draw_arc(dest, 5.0, 0.0, TAU, 20, pc, 1.5)
		draw_colored_polygon(PackedVector2Array([dest + bob, dest + bob + Vector2(-4, -6), dest + bob + Vector2(4, -6)]), pc)

	# ドローン
	var dc: Color = gs.TOOLS[0]["color"]
	for d in _drones:
		var dp: Vector2 = d["pos"]
		var tgt := int(d["target"])
		var dir := Vector2.DOWN
		if planet.is_alive(tgt):
			var tp := planet.cell_center(tgt)
			dir = (tp - dp).normalized()
			if dp.distance_to(tp) < Planet.CELL * 4.0:
				draw_line(dp, tp, Color(dc, 0.85), 1.2 + sin(_t * 30.0) * 0.4)
				draw_circle(tp, 1.8, Color(1, 1, 1, 0.9))
		var body := PackedVector2Array([dp + dir * 4.5, dp + dir.rotated(2.4) * 4.0, dp + dir.rotated(-2.4) * 4.0])
		draw_colored_polygon(body, dc)

	# パルスドリル
	if gs.tool_level("cutter") > 0 and _drill_pos != Vector2.INF:
		var cc: Color = gs.TOOLS[1]["color"]
		var p := _drill_pos
		var aim := planet.cell_center(_drill_target) if planet.is_alive(_drill_target) else p + Vector2.DOWN * 8.0
		var up := (p - aim).normalized() if p.distance_to(aim) > 0.5 else Vector2.UP
		var tip := p - up * 4.0
		var top := p + up * 8.0
		draw_colored_polygon(PackedVector2Array([tip, top + up.orthogonal() * 4.0, top - up.orthogonal() * 4.0]), cc)
		draw_rect(Rect2(top - Vector2(4, 4), Vector2(8, 8)), cc.darkened(0.3))
		if _drill_flash > 0.0:
			draw_arc(aim, Planet.CELL * 2.5 * (1.2 - _drill_flash * 0.5), 0.0, TAU, 24, Color(cc, _drill_flash), 2.0)

	# レーザー
	if gs.tool_level("laser") > 0 and _sat_pos != Vector2.INF:
		var lc: Color = gs.TOOLS[2]["color"]
		var sat := _sat_pos
		draw_rect(Rect2(sat - Vector2(4, 4), Vector2(8, 8)), lc.darkened(0.3))
		draw_line(sat + Vector2(-9, 0), sat + Vector2(9, 0), lc, 2.0)
		if _laser_hit != Vector2.INF:
			draw_line(sat, _laser_hit, Color(lc, 0.35), 4.0)
			draw_line(sat, _laser_hit, Color(1, 0.85, 0.9), 1.2)
			draw_circle(_laser_hit, 3.0 + sin(_t * 40.0) * 1.0, Color(lc, 0.8))

	# 爆雷
	var bc: Color = gs.TOOLS[3]["color"]
	for b in _bombs:
		var p: Vector2 = (b["from"] as Vector2).lerp(b["to"], float(b["t"]))
		draw_circle(p, 4.0, bc)
		draw_arc(b["to"], Planet.CELL * 4.5 * (1.0 - float(b["t"]) * 0.5), 0.0, TAU, 24, Color(bc, 0.5), 1.5)

	# ランス
	if _lance_hit != Vector2.INF:
		var nc: Color = gs.TOOLS[4]["color"]
		draw_line(_lance_from, _lance_hit, Color(nc, 0.3), 6.0)
		draw_line(_lance_from, _lance_hit, Color(0.85, 1.0, 0.85), 1.8)
		draw_circle(_lance_from, 5.0, nc)

	# スウォーム
	if gs.tool_level("swarm") > 0:
		var sc: Color = gs.TOOLS[5]["color"]
		for b in _bots:
			draw_circle(b["pos"], 1.3, sc)

	# タップ
	for tp in _taps:
		var k := float(tp["t"])
		draw_arc(tp["pos"], 3.0 + k * 12.0, 0.0, TAU, 20, Color(1, 1, 1, 1.0 - k), 1.5)
