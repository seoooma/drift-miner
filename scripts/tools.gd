class_name Tools
extends Node2D
## 採掘ツールの動きと描画。ツールごとに違う削り方をする。
## 威力（毎秒ダメージ）は GameState から毎フレーム読む。

var planet: Planet = null
var fx_layer: Node2D = null

var _t: float = 0.0
var _cutter_angle: float = 0.0
var _cutter_pos := Vector2.ZERO
var _laser_angle: float = 0.0
var _laser_hit := Vector2.INF
var _lance_angle: float = 0.0
var _lance_hit := Vector2.INF
var _bomb_timer: float = 1.0
var _bombs: Array = []  # {"from", "to", "t", "dmg"}
var _drone_hits: Array = []
var _bots: Array = []  # {"pos", "target"}
var _taps: Array = []  # {"pos", "t"}


func reset_for(p: Planet) -> void:
	planet = p
	_cutter_angle = randf() * TAU
	_cutter_pos = p.position + Vector2.from_angle(_cutter_angle) * p.world_radius()
	_laser_angle = randf() * TAU
	_lance_angle = randf() * TAU
	_bombs.clear()
	for b in _bots:
		b["target"] = -1


func _process(delta: float) -> void:
	_t += delta
	if planet == null or planet.done:
		queue_redraw()
		return
	var gs := GameState
	var c := planet.position
	var r := planet.world_radius()

	# 採掘ドローン：周回しながら、自分から中心へ向かう線上の表面を削る
	var drone_dps := gs.tool_dps("drone")
	_drone_hits.clear()
	if drone_dps > 0.0:
		var n := gs.drone_count()
		for k in n:
			var a := _t * 0.45 + TAU * k / n
			var dp := c + Vector2.from_angle(a) * (r + 34.0)
			var i := planet.raycast(dp, c)
			if i >= 0:
				planet.hit(i, drone_dps / n * delta)
				_drone_hits.append([dp, planet.cell_center(i)])
			else:
				_drone_hits.append([dp, Vector2.INF])

	# 回転カッター：地表を転がりながら周囲を切る
	var cut := gs.tool_dps("cutter")
	if cut > 0.0:
		_cutter_angle += delta * 0.32
		var i := planet.surface_cell(_cutter_angle)
		if i >= 0:
			_cutter_pos = _cutter_pos.lerp(planet.cell_center(i), clampf(delta * 4.0, 0.0, 1.0))
			planet.hit_area(_cutter_pos, Planet.CELL * 2.6, cut * delta)

	# 掃射レーザー：衛星から地表をなぎ払う
	var las := gs.tool_dps("laser")
	_laser_hit = Vector2.INF
	if las > 0.0:
		_laser_angle += delta * 0.12
		var sat := c + Vector2.from_angle(_laser_angle) * (r + 90.0)
		var aim := c + Vector2.from_angle(_laser_angle + PI * 0.5) * sin(_t * 1.1) * r * 0.85
		var i := planet.raycast(sat, aim + (aim - sat).normalized() * r * 2.0)
		if i >= 0:
			_laser_hit = planet.cell_center(i)
			planet.hit_area(_laser_hit, Planet.CELL * 1.6, las * delta)

	# 重力爆雷：一定間隔で落ちて広く砕く
	var bomb := gs.tool_dps("bomb")
	if bomb > 0.0:
		_bomb_timer -= delta
		if _bomb_timer <= 0.0:
			_bomb_timer = 2.0
			var i := planet.random_surface_cell()
			if i >= 0:
				var to := planet.cell_center(i)
				var from := c + (to - c).normalized() * (r + 160.0)
				_bombs.append({"from": from, "to": to, "t": 0.0, "dmg": bomb * 2.0})
	for b in _bombs.duplicate():
		b["t"] = float(b["t"]) + delta * 2.2
		if float(b["t"]) >= 1.0:
			_bombs.erase(b)
			planet.hit_area(b["to"], Planet.CELL * 4.5, float(b["dmg"]))
			if fx_layer != null:
				Fx.burst(fx_layer, b["to"], Color(0.8, 0.5, 1.0), 26, 180.0)

	# コアランス：中心へ一直線に掘り進む
	var lan := gs.tool_dps("lance")
	_lance_hit = Vector2.INF
	if lan > 0.0:
		_lance_angle += delta * 0.04
		var from := c + Vector2.from_angle(_lance_angle) * (r + 120.0)
		var i := planet.raycast(from, c - Vector2.from_angle(_lance_angle) * r)
		if i >= 0:
			_lance_hit = planet.cell_center(i)
			planet.hit_area(_lance_hit, Planet.CELL * 1.2, lan * delta)

	# ナノスウォーム：小さな機械が表面のあちこちを食べる
	var sw := gs.tool_dps("swarm")
	if sw > 0.0:
		while _bots.size() < 28:
			_bots.append({"pos": c + Vector2.from_angle(randf() * TAU) * (r + 60.0), "target": -1})
		for b in _bots:
			var tgt := int(b["target"])
			if not planet.is_alive(tgt):
				b["target"] = planet.random_surface_cell()
				continue
			var tp := planet.cell_center(tgt)
			b["pos"] = (b["pos"] as Vector2).move_toward(tp, 260.0 * delta)
			if (b["pos"] as Vector2).distance_to(tp) < 4.0:
				planet.hit(tgt, sw / _bots.size() * delta)

	for tp in _taps.duplicate():
		tp["t"] = float(tp["t"]) + delta * 3.0
		if float(tp["t"]) >= 1.0:
			_taps.erase(tp)
	queue_redraw()


func tap_effect(p: Vector2) -> void:
	_taps.append({"pos": p, "t": 0.0})


func _draw() -> void:
	if planet == null:
		return
	var gs := GameState
	var c := planet.position
	var r := planet.world_radius()

	# ドローン
	var dc: Color = gs.TOOLS[0]["color"]
	for h in _drone_hits:
		var dp: Vector2 = h[0]
		if h[1] != Vector2.INF:
			var w := 2.0 + sin(_t * 30.0) * 0.8
			draw_line(dp, h[1], Color(dc, 0.85), w)
			draw_circle(h[1], 3.5, Color(1, 1, 1, 0.9))
		var dir := (c - dp).normalized()
		var body := PackedVector2Array([dp + dir * 9.0, dp + dir.rotated(2.4) * 8.0, dp + dir.rotated(-2.4) * 8.0])
		draw_colored_polygon(body, dc)

	# カッター
	if gs.tool_level("cutter") > 0:
		var cc: Color = gs.TOOLS[1]["color"]
		var p := _cutter_pos
		for k in 3:
			var a0 := -_t * 9.0 + TAU * k / 3.0
			draw_arc(p, 20.0, a0, a0 + 1.4, 10, cc, 3.0)
			draw_line(p + Vector2.from_angle(a0) * 20.0, p + Vector2.from_angle(a0 - 0.5) * 26.0, cc, 3.0)
		draw_circle(p, 5.0, cc.lightened(0.4))

	# レーザー
	if gs.tool_level("laser") > 0:
		var lc: Color = gs.TOOLS[2]["color"]
		var sat := c + Vector2.from_angle(_laser_angle) * (r + 90.0)
		draw_rect(Rect2(sat - Vector2(7, 7), Vector2(14, 14)), lc.darkened(0.3))
		draw_line(sat + Vector2(-14, 0).rotated(_laser_angle + PI * 0.5), sat + Vector2(14, 0).rotated(_laser_angle + PI * 0.5), lc, 3.0)
		if _laser_hit != Vector2.INF:
			draw_line(sat, _laser_hit, Color(lc, 0.35), 7.0)
			draw_line(sat, _laser_hit, Color(1, 0.85, 0.9), 2.0)
			draw_circle(_laser_hit, 6.0 + sin(_t * 40.0) * 2.0, Color(lc, 0.8))

	# 爆雷
	var bc: Color = gs.TOOLS[3]["color"]
	for b in _bombs:
		var p: Vector2 = (b["from"] as Vector2).lerp(b["to"], float(b["t"]))
		draw_circle(p, 7.0, bc)
		draw_arc(b["to"], Planet.CELL * 4.5 * (1.0 - float(b["t"]) * 0.5), 0.0, TAU, 24, Color(bc, 0.5), 2.0)

	# ランス
	if _lance_hit != Vector2.INF:
		var nc: Color = gs.TOOLS[4]["color"]
		var from := c + Vector2.from_angle(_lance_angle) * (r + 120.0)
		draw_line(from, _lance_hit, Color(nc, 0.3), 10.0)
		draw_line(from, _lance_hit, Color(0.85, 1.0, 0.85), 3.0)
		draw_circle(from, 9.0, nc)

	# スウォーム
	if gs.tool_level("swarm") > 0:
		var sc: Color = gs.TOOLS[5]["color"]
		for b in _bots:
			draw_circle(b["pos"], 2.5, sc)

	# タップ
	for tp in _taps:
		var k := float(tp["t"])
		draw_arc(tp["pos"], 6.0 + k * 22.0, 0.0, TAU, 20, Color(1, 1, 1, 1.0 - k), 2.0)
