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
var _drill_agent := {}
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
var _glow: Node2D  # 加算合成で描く光（ビーム・噴射・照準）
var _carrier_pos := Vector2.INF


func _ready() -> void:
	_glow = Node2D.new()
	_glow.material = Fx.additive()
	_glow.z_index = 2
	_glow.draw.connect(_draw_glow)
	add_child(_glow)


func _shake(amount: float) -> void:
	var m := get_parent()
	if m != null and m.has_method("shake"):
		m.shake(amount)


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


## pos から goal へ進む。まっすぐ行けなければ、掘り跡（外とつながった空き）を通る道を探して進む。
## 道が見つからないときだけ、まっすぐ進む（止まってしまわないための保険）。
func _fly(agent: Dictionary, pos: Vector2, goal: Vector2, speed: float) -> Vector2:
	if planet.line_clear(pos, goal):
		agent["path"] = PackedVector2Array()
		return pos.move_toward(goal, speed)
	var path: PackedVector2Array = agent.get("path", PackedVector2Array())
	if path.is_empty() or path[path.size() - 1].distance_to(goal) > Planet.CELL:
		path = planet.find_path(pos, goal)
		agent["path"] = path
		if path.is_empty():
			return pos.move_toward(goal, speed)
	var wp := path[0]
	var np := pos.move_toward(wp, speed)
	if np.distance_to(wp) < 0.5:
		path.remove_at(0)
		agent["path"] = path
	return np



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
			_drill_pos = hp if _drill_pos == Vector2.INF else _fly(_drill_agent, _drill_pos, hp, 70.0 * mv * delta)
			_drill_pulse += delta
			if _drill_pulse >= 0.5 and _drill_pos.distance_to(hp) < Planet.CELL:
				_drill_pulse = 0.0
				_drill_flash = 1.0
				planet.hit_area(drill_c, Planet.CELL * 2.5, drill * 0.5)
				Audio.play("drill")
				if fx_layer != null:
					Fx.sparks(fx_layer, drill_c, Neon.ORANGE, 8, 90.0)
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
				Audio.play("laser")
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
		var home := planet.nearest_open(focus + Vector2.from_angle(_t * 0.8 + TAU * k / maxf(1.0, n)) * 14.0)
		if tgt >= 0:
			home = planet.hover_point(tgt, Planet.CELL * 2.5)
			if (d["pos"] as Vector2).distance_to(home) < Planet.CELL * 1.5:
				planet.hit(tgt, drone_dps / n * delta)
		d["pos"] = _fly(d, d["pos"], home, 90.0 * mv * delta)

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
			Audio.play("bomb")
			_shake(3.0)
			if fx_layer != null:
				Fx.explosion(fx_layer, b["to"], Planet.CELL * 5.0, true)
				Fx.burst(fx_layer, b["to"], Neon.MAGENTA, 16, 160.0)

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
			b["pos"] = _fly(b, b["pos"], tp, 120.0 * mv * delta)
			if (b["pos"] as Vector2).distance_to(tp) < 4.0:
				planet.hit(tgt, sw / _bots.size() * delta)

	# 母艦：機体の集まる場所の少し上空に浮かぶ
	var up := (focus - planet.position).normalized() if focus.distance_to(planet.position) > 1.0 else Vector2.UP
	var ch := focus + up * 46.0 + up.orthogonal() * sin(_t * 0.4) * 10.0
	_carrier_pos = ch if _carrier_pos == Vector2.INF else _carrier_pos.lerp(ch, clampf(delta * 1.5, 0.0, 1.0))
	for tp in _taps.duplicate():
		tp["t"] = float(tp["t"]) + delta * 1.5
		if float(tp["t"]) >= 1.0:
			_taps.erase(tp)
	queue_redraw()
	_glow.queue_redraw()


func tap_effect(p: Vector2) -> void:
	_taps.append({"pos": p, "t": 0.0})


## 線画の機体。下に太く薄い線（にじみ）、上に細い線。size はワールド単位の全長。
func _ship(id: String, pos: Vector2, rot: float, size: float, col: Color, w_px: float = 1.5) -> void:
	var pts := Neon.ship(id, pos, size, rot)
	var w := Fx.px(w_px)
	draw_polyline(pts, Color(col, 0.25), w * 4.0)
	draw_polyline(pts, col, w)


## 光る細い線（レーザー・ビーム）。w_px は画面のピクセル。
func _beam(a: Vector2, b: Vector2, col: Color, w_px: float) -> void:
	var w := Fx.px(w_px)
	_glow.draw_line(a, b, Neon.glow(col), w * 4.0)
	_glow.draw_line(a, b, col, w)


## 当たった所の小さな明るい点
func _hit_dot(p: Vector2, col: Color, r_px: float = 2.0) -> void:
	_glow.draw_circle(p, Fx.px(r_px * 2.5), Neon.glow(col))
	_glow.draw_circle(p, Fx.px(r_px), Color(1, 1, 1, 0.95))


## 揺らぐ輪（範囲攻撃）。約4フレームごとに形を作り直す。
func _jring(c: Vector2, r: float, col: Color, salt: int = 0) -> void:
	var pts := Neon.jitter_ring(c, r, Fx.px(3.0), int(_t * 15.0) * 7919 + salt)
	Neon.glow_poly(_glow, pts, col, Fx.px(1.5), Fx.px(6.0))


func _draw() -> void:
	if planet == null:
		return
	var gs := GameState
	var c := planet.position

	# 母艦
	if _carrier_pos != Vector2.INF and not planet.done:
		var up := (_carrier_pos - c).normalized()
		_ship("carrier", _carrier_pos, (-up).angle(), 12.0, Neon.LINE)

	# ドローン
	for d in _drones:
		var dp: Vector2 = d["pos"]
		var tgt := int(d["target"])
		var dir := (dp - c).normalized() * -1.0
		if planet.is_alive(tgt):
			dir = (planet.cell_center(tgt) - dp).normalized()
		_ship("drone", dp, dir.angle(), 5.5, Neon.CYAN)

	# パルスドリル
	if gs.tool_level("cutter") > 0 and _drill_pos != Vector2.INF:
		var aim := planet.cell_center(_drill_target) if planet.is_alive(_drill_target) else _drill_pos + Vector2.DOWN * 8.0
		var dir := (aim - _drill_pos).normalized() if _drill_pos.distance_to(aim) > 0.5 else Vector2.DOWN
		_ship("cutter", _drill_pos - dir * 2.0, dir.angle(), 8.0 + _drill_flash * 1.5, Neon.LINE)

	# レーザー衛星（胴と2枚のパネル）
	if gs.tool_level("laser") > 0 and _sat_pos != Vector2.INF:
		var rot := sin(_t * 0.6) * 0.3
		_ship("laser", _sat_pos, rot, 8.0, Neon.LINE)
		var ax := Vector2.from_angle(rot)
		for sgn in [-1.0, 1.0]:
			var pc: Vector2 = _sat_pos + ax * 4.5 * sgn
			var panel := PackedVector2Array([pc + Vector2(-1.8, -1.5).rotated(rot), pc + Vector2(1.8, -1.5).rotated(rot), pc + Vector2(1.8, 1.5).rotated(rot), pc + Vector2(-1.8, 1.5).rotated(rot), pc + Vector2(-1.8, -1.5).rotated(rot)])
			draw_polyline(panel, Neon.LINE, Fx.px(1.0))

	# 爆雷
	for b in _bombs:
		var from: Vector2 = b["from"]
		var to: Vector2 = b["to"]
		var p: Vector2 = from.lerp(to, ease(float(b["t"]), 2.0))
		_ship("bomb", p, (to - from).angle(), 5.0, Neon.LINE)

	# ランスの基地
	if _lance_hit != Vector2.INF:
		_ship("lance", _lance_from, _t * 0.5, 10.0, Neon.LINE)

	# スウォーム（小さな四角）
	if gs.tool_level("swarm") > 0:
		var s := Fx.px(2.0)
		for b in _bots:
			draw_rect(Rect2((b["pos"] as Vector2) - Vector2(s, s) * 0.5, Vector2(s, s)), Neon.LINE)


## 光るもの（加算合成）：照準・ビーム・範囲攻撃の輪・当たった点
func _draw_glow() -> void:
	if planet == null:
		return
	var gs := GameState
	var c := planet.position
	var hair := Fx.px(1.0)

	# 機体の集まる場所（うっすらした照準）
	if not planet.done:
		var fc := Color(Neon.CYAN, 0.18 + 0.06 * sin(_t * 3.0))
		_glow.draw_arc(focus, Planet.CELL * 9.0, 0.0, TAU, 64, fc, hair)

	# 移動先の目印（四角の角かっこ）
	if dest != Vector2.INF:
		var pc := Color(Neon.LIME, 0.7 + 0.3 * sin(_t * 6.0))
		var r := 6.0 + 1.0 * sin(_t * 4.0)
		Neon.brackets(_glow, Rect2(dest - Vector2(r, r), Vector2(r, r) * 2.0), pc, r * 0.8, Fx.px(1.5))
		Neon.brackets(_glow, Rect2(dest - Vector2(r, r), Vector2(r, r) * 2.0), Neon.glow(pc), r * 0.8, Fx.px(5.0))
		_glow.draw_rect(Rect2(dest - Vector2(hair, hair), Vector2(hair, hair) * 2.0), pc)

	# 母艦のエンジン
	if _carrier_pos != Vector2.INF and not planet.done:
		var up := (_carrier_pos - c).normalized()
		_hit_dot(_carrier_pos + up * 6.0, Neon.CYAN, 1.0 + 0.4 * sin(_t * 20.0))

	# ドローンのビーム
	var dc := Neon.CYAN
	for d in _drones:
		var dp: Vector2 = d["pos"]
		var tgt := int(d["target"])
		if planet.is_alive(tgt):
			var tp := planet.cell_center(tgt)
			if dp.distance_to(tp) < Planet.CELL * 4.0:
				_beam(dp, tp, dc, 1.0)
				_hit_dot(tp, dc, 1.2)

	# パルスドリル：砕くたびに揺らぐ輪
	if gs.tool_level("cutter") > 0 and _drill_pos != Vector2.INF:
		if _drill_flash > 0.0 and planet.is_alive(_drill_target):
			var aim := planet.cell_center(_drill_target)
			_jring(aim, Planet.CELL * 2.5 * (1.2 - _drill_flash * 0.5), Color(Neon.ORANGE, _drill_flash), 1)

	# レーザー：細い赤い線と、当たった所の明るい点
	if gs.tool_level("laser") > 0 and _sat_pos != Vector2.INF:
		if _laser_hit != Vector2.INF:
			_beam(_sat_pos, _laser_hit, Neon.RED, 1.5)
			_hit_dot(_laser_hit, Neon.RED, 2.0)

	# 爆雷：落ちる先の揺らぐ輪
	for b in _bombs:
		var k := float(b["t"])
		_jring(b["to"], Planet.CELL * 4.5 * (1.0 - k * 0.5), Color(Neon.MAGENTA, 0.45 + 0.4 * k), 2)

	# ランス
	if _lance_hit != Vector2.INF:
		_beam(_lance_from, _lance_hit, Neon.LIME, 2.0)
		_hit_dot(_lance_hit, Neon.LIME, 2.5)

	# タップした場所の波紋
	for tp in _taps:
		var k := float(tp["t"])
		_glow.draw_arc(tp["pos"], 3.0 + k * 14.0, 0.0, TAU, 32, Color(Neon.LIME, 1.0 - k), Fx.px(1.5))
