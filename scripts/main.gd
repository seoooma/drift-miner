extends Node2D
## ゲームの進行。巨大惑星の生成と保存、砕いたブロックの報酬（クレジット・素材・遺物・宝箱）、
## 惑星クリアと次の惑星、自動強化、機体の集まる場所 (focus) と寄りのカメラを受け持つ。
## タップは攻撃ではなく「移動先の指定」。機体はそこへ移動し、周りを掘り尽くすと自動の探索に戻る。

const VIEW_CELLS := 20.0  # 画面の短い辺に並ぶマスの数（ブロック1つ ≒ 画面幅の1/20）
## 自動で動くときの落ち着き。着いたら DWELL 秒は周りの鉱石を掘り、新しい候補は
## 今の場所の一番よいマスより SWITCH_RATIO（最低 SWITCH_MARGIN 点）よいときだけ乗り換える。
## （留まる時間を長くするほど落ち着くが、稼ぎは落ちる。2秒で稼ぎはほぼ変わらない）
const DWELL := 2.0
const SWITCH_MARGIN := 1.5
const SWITCH_RATIO := 0.15
const AUTO_SPEED_MAX := 90.0
const LEAD := 0.35  # カメラを行き先の方へ寄せる割合
const LEAD_MAX := 6.0  # 寄せる最大（マス）

const HudScript := preload("res://scripts/hud.gd")
const BackdropScript := preload("res://scripts/backdrop.gd")

var backdrop: CanvasLayer
var planet: Planet
var tools: Tools
var fx_layer: Node2D
var camera: Camera2D
var hud: CanvasLayer
var touch_ui: bool = false

var _pop_acc: float = 0.0
var _pop_pos := Vector2.ZERO
var _pop_t: float = 0.0
var _mat_pop := {}
var _mat_pop_t: float = 0.0
var _auto_t: float = 0.0
var _zoom: float = 0.0
var focus := Vector2.ZERO  # ツールが狙う中心（ワールド座標）
var _focus_goal := Vector2.ZERO
var _focus_t: float = 0.0
var _shake: float = 0.0  # 揺れの強さ（トラウマ、0〜1）。揺れの量はこれの2乗で、時間とともに減る
var _shake_t: float = 0.0
var _shake_noise: FastNoiseLite
var _punch: float = 0.0  # 一瞬だけ寄る量（大きな出来事で、カメラが「押される」）
var _fx_budget: float = 20.0  # 1秒に出せる破片演出の数（多すぎると重くなる）
var _manual := false  # プレイヤーが指定した移動先へ向かっている／そこを掘っている
var _dwell: float = 0.0  # 今の場所に着いてからの時間
var _speed: float = 0.0
var bot := false  # 確認用の自動プレイ（--bot）。強化とスキルを自動で買い、惑星を割ったら次へ進む
var _bot_t: float = 0.0
var _intro: float = 0.0  # 着陸の演出の残り秒数（惑星全体から寄っていく）
const INTRO := 1.8
var _outro: float = -1.0  # 惑星を割った後、全体まで引いていく演出の経過秒数（-1 はなし）
var _hunt_auto := false  # 透視スキャンで自動的に遺物を掘りに行っている


func _ready() -> void:
	randomize()
	touch_ui = DisplayServer.is_touchscreen_available() or "--touch" in OS.get_cmdline_user_args()
	bot = "--bot" in OS.get_cmdline_user_args()
	if bot:
		GameState.auto_on = true

	backdrop = BackdropScript.new()
	add_child(backdrop)
	planet = Planet.new()
	add_child(planet)
	tools = Tools.new()
	add_child(tools)
	fx_layer = Node2D.new()
	add_child(fx_layer)
	tools.fx_layer = fx_layer
	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()

	hud = HudScript.new()
	hud.main = self
	add_child(hud)

	planet.cell_broken.connect(_on_cell_broken)
	planet.cleared.connect(_on_cleared)
	planet.relic_lost.connect(_on_relic_lost)
	GameState.hp_provider = func() -> PackedFloat32Array: return planet.hp
	GameState.rate_provider = func() -> float: return planet.damage_rate

	if touch_ui:
		get_tree().root.size_changed.connect(_apply_mobile_scale)
		_apply_mobile_scale()
	build_planet(GameState.saved_hp)
	if GameState.pending_clear and planet.done:
		# 惑星を割った画面で閉じていたときは、その画面から続ける
		get_tree().paused = true
		var nx: Array = GameState.next_traits if not GameState.next_traits.is_empty() else GameState.roll_next_traits()
		hud.show_clear(GameState.clear_extra, nx)
	elif GameState.offline_secs > 0.0:
		_offline_dig(GameState.offline_secs)
	if "--galaxy" in OS.get_cmdline_user_args():
		hud.call_deferred("_open_galaxy")  # 確認用：星系の画面を開いた状態で始める


## 閉じていた間も、保存したときのペースで実際に掘り進める（上限10時間＋スキル）。
## 削った跡はそのまま惑星に残り、クリアに届いていれば戻った直後に割れる。
func _offline_dig(secs: float) -> void:
	var gs := GameState
	gs.offline_secs = 0.0
	if gs.damage_rate_saved <= 0.0 or planet.done:
		return
	var before := planet.hp_progress()
	var budget := gs.damage_rate_saved * secs * gs.offline_eff()
	var r := planet.offline_dig(budget)
	gs.offline_used = true
	var cr := float(r["cr"])
	gs.earn(cr, false)
	var got := {}
	var ores: Dictionary = r["ores"]
	for b in ores:
		var m := String(gs.BLOCKS[b]["mat"])
		got[m] = float(got.get(m, 0.0)) + gs.add_mat(m, _mat_amount() * int(ores[b]))
	hud.show_offline(secs, before, planet.hp_progress(), cr, got, planet.done)
	gs.save()
	if bot:
		print("[bot] offline %.1fh cells=%d prog %.1f%%->%.1f%% cr=%s" % [secs / 3600.0, int(r["cells"]), 100.0 * before, 100.0 * planet.hp_progress(), gs.fmt(cr)])
	if planet.done:
		await get_tree().create_timer(0.6).timeout
		_on_cleared()


## スマホでは画面の短い辺を 450 として扱い、文字とボタンを大きく表示する。
func _apply_mobile_scale() -> void:
	var win := get_window()
	var s := DisplayServer.window_get_size()
	if s.x <= 0 or s.y <= 0:
		return
	var short_side := 450
	if s.y > s.x:
		win.content_scale_size = Vector2i(short_side, int(short_side * float(s.y) / s.x))
	else:
		win.content_scale_size = Vector2i(int(short_side * float(s.x) / s.y), short_side)


func build_planet(saved: PackedFloat32Array = PackedFloat32Array()) -> void:
	for c in fx_layer.get_children():
		c.queue_free()
	var gs := GameState
	planet.position = Vector2.ZERO
	planet.generate(hash("%d:%d" % [gs.run_seed, gs.planet]), gs.trait_def()["rates"])
	if not saved.is_empty():
		planet.restore(saved)
	tools.reset_for(planet)
	_zoom = 0.0
	planet.modulate = Color.WHITE
	_outro = -1.0
	_intro = 0.0 if gs.pending_clear else INTRO
	_hunt_auto = false
	var top := planet.surface_cell(-PI * 0.5 + randf_range(-0.6, 0.6))
	focus = planet.hover_point(top, Planet.CELL) if top >= 0 else planet.position
	_focus_goal = focus
	_manual = false
	_focus_t = 0.0
	_dwell = 0.0
	_speed = 0.0
	tools.focus = focus
	tools.dest = Vector2.INF
	tools.auto_dest = Vector2.INF
	var tr := gs.trait_def()
	if gs.pending_clear:
		return
	hud.banner("%s：%s" % [gs.place_name(), tr["name"]], String(tr["desc"]) if saved.is_empty() else "")
	if bot and saved.is_empty():
		print("[bot] start %s pm=%s est=%.1f raw=%.1f bias=%.2f min" % [gs.place_name(), gs.fmt(gs.pm), gs.est_start * gs.est_bias / 60.0, gs.est_start / 60.0, gs.est_bias])


func _process(delta: float) -> void:
	_fx_budget = minf(20.0, _fx_budget + delta * 24.0)
	_update_focus(delta)
	_fit_camera(delta)
	var gs := GameState
	if gs.auto_on:
		# 自動強化：最初は1.5秒に1回。スキル「自動強化・高速」で、0.5秒ごとに買えるだけ買う
		var fast := gs.skill_level("auto_buy") > 0
		_auto_t += delta
		if _auto_t >= (0.5 if fast else 1.5):
			_auto_t = 0.0
			for k in (200 if fast else 1):
				if not _auto_buy():
					break
	if bot:
		_bot_t += delta
		if _bot_t >= 30.0:
			_bot_t = 0.0
			gs.buy_all_skills()
			# 近くに気配があれば、プレイヤーのようにタップして掘りに行く
			var hb := planet.buried_near(focus, Planet.SIGNAL_R)
			if hb >= 0 and planet.hunt_cell < 0 and not planet.is_exposed(hb):
				set_destination(planet.cell_center(hb))
				print("[bot] hunt cell %d (%s)" % [hb, "relic" if int(planet.block[hb]) == gs.B.RELIC else "cache"])
			print("[bot] planet %d t=%.0fs prog=%.1f%% hp=%.1f%% dps=%s rate=%s cr=%s" % [gs.planet, gs.planet_time, 100.0 * planet.progress(), 100.0 * planet.hp_progress(), gs.fmt(gs.total_dps()), gs.fmt(planet.damage_rate), gs.fmt(gs.credits)])
	_pop_t -= delta
	if _pop_t <= 0.0 and _pop_acc > 0.0:
		Fx.popup(fx_layer, _pop_pos, "+%s CR" % gs.fmt(_pop_acc), Color(Color.WHITE, 0.85))
		_pop_acc = 0.0
		_pop_t = 0.35
	_mat_pop_t -= delta
	if _mat_pop_t <= 0.0 and not _mat_pop.is_empty():
		_mat_pop_t = 0.5
		for m in _mat_pop:
			var e: Array = _mat_pop[m]
			Fx.popup(fx_layer, e[1] + Vector2(0, -6), "+%s %s" % [gs.fmt(e[0]), gs.MAT_NAMES[m]], gs.MAT_COLORS[m])
		_mat_pop.clear()


## 機体の集まる場所（母艦の真下）を決める。移動先が指定されていればそこへ向かい、着いてから
## 周りを掘り尽くすまで留まる。それ以外は、探索範囲の中で一番「おいしい」マス
## （鉱石・遺物・浅い所）の前へ移っていく。どちらも外とつながった空きだけを通る。
## 自動のときは、着いたらしばらく留まり、はっきりよい候補が出たときだけ乗り換える。
func _update_focus(delta: float) -> void:
	if planet.done:
		return
	var gs := GameState
	var arrived := focus.distance_to(_focus_goal) < Planet.CELL
	if arrived:
		_dwell += delta
	planet.signal_pos = focus
	_focus_t -= delta
	if _focus_t <= 0.0:
		_focus_t = 0.5
		if planet.hunt_cell >= 0:
			# 遺物を掘りに行っている間は、その遺物に一番近い掘り口の前へ移っていく
			var front := planet.hunt_front()
			if front < 0:
				planet.hunt_cell = -1
				_manual = false
				_hunt_auto = false
			else:
				var g := planet.hover_point(front, Planet.CELL)
				if g.distance_to(_focus_goal) > Planet.CELL * 0.5:
					_focus_goal = g
					tools.rescan()
		elif _manual and arrived and planet.targets_near(focus, 6).is_empty():
			_manual = false
		if not _manual and planet.hunt_cell < 0:
			_pick_auto_goal(arrived)
	var goal_sp := 70.0 if _manual else clampf(focus.distance_to(_focus_goal) * 0.8, 18.0, AUTO_SPEED_MAX)
	_speed = move_toward(_speed, goal_sp, 160.0 * delta)
	focus = focus.move_toward(_focus_goal, _speed * gs.move_mult() * delta)
	tools.focus = focus
	tools.dest = _focus_goal if _manual else Vector2.INF
	tools.auto_dest = _focus_goal if not _manual and focus.distance_to(_focus_goal) > Planet.CELL * 1.5 else Vector2.INF


## 自動の行き先を決める。今の場所（_focus_goal）の周り6マスに鉱石・遺物などが残っている間は、
## 着いてから DWELL 秒は動かず、その後もはっきりよい候補（SWITCH_RATIO・最低 SWITCH_MARGIN 点）が
## 見つかったときだけ移る。周りが岩だけなら、岩どうしの小さな差では動かず、鉱石が見つかるか
## 周りを掘り尽くしたときに移る。
func _pick_auto_goal(arrived: bool) -> void:
	var gs := GameState
	# 透視スキャンがあれば、近くに埋まった遺物・宝箱を自分で掘りに行く
	if gs.skill_level("vision") > 0:
		var b := planet.buried_near(focus, float(gs.scan_radius()))
		if b >= 0 and not planet.is_exposed(b):
			planet.hunt_cell = b
			_hunt_auto = true
			return
	var near := planet.targets_near(_focus_goal, 6)
	var t := planet.targets_near(focus, gs.scan_radius(), 0.6)
	if near.is_empty():
		var i := int(t[0]) if not t.is_empty() else planet.nearest_exposed(focus)
		if i >= 0:
			_set_goal(i)
		return
	if not arrived or t.is_empty():
		return
	var best := int(t[0])
	var near_ore := planet.priority(int(near[0])) > 0.0
	if near_ore and _dwell < DWELL:
		return
	var cur := planet.score(int(near[0]), focus, 0.6)
	var nb := planet.score(best, focus, 0.6)
	if nb > cur + maxf(SWITCH_MARGIN, absf(cur) * SWITCH_RATIO):
		_set_goal(best)


func _set_goal(i: int) -> void:
	var g := planet.hover_point(i, Planet.CELL)
	if g.distance_to(_focus_goal) > 1.0:
		_dwell = 0.0
	_focus_goal = g


## 画面の中心にする点。行き先が決まっていれば、そちらへ少し寄せる。
func view_point() -> Vector2:
	var lead := (_focus_goal - focus) * LEAD
	return focus + lead.limit_length(Planet.CELL * LEAD_MAX)


## いま向かっている先（着いていれば INF）。manual は指定した移動先かどうか。
func heading() -> Dictionary:
	if planet.done or focus.distance_to(_focus_goal) <= Planet.CELL * 1.5:
		return {}
	return {"pos": _focus_goal, "manual": _manual}


## 惑星の一部だけが大きく映るよう、狙いの中心にカメラを寄せる。
## 掘るほど少しずつ引いていく（20マス → 28マス）。着陸のときは惑星全体から寄り、割った後は全体まで引く。
func _fit_camera(delta: float) -> void:
	var area: Rect2 = hud.planet_area()
	var short := minf(area.size.x, area.size.y)
	var cells := VIEW_CELLS + 8.0 * planet.progress()
	var center := view_point()
	var whole := (planet.radius_cells * 2.0 + 6.0)
	var direct := false
	if _intro > 0.0:
		_intro = maxf(0.0, _intro - delta)
		var k := 1.0 - _intro / INTRO
		k = k * k * (3.0 - 2.0 * k)
		cells = lerpf(whole, cells, k)
		center = planet.position.lerp(center, k)
		direct = true
	elif _outro >= 0.0:
		_outro += delta
		var k := clampf(_outro / 1.2, 0.0, 1.0)
		k = k * k * (3.0 - 2.0 * k)
		cells = lerpf(cells, whole * 1.4, k)
		center = center.lerp(planet.position, k)
		direct = true
	var target := short / (cells * Planet.CELL)
	_zoom = target if _zoom <= 0.0 or direct else lerpf(_zoom, target, clampf(delta * 3.0, 0.0, 1.0))
	_punch = lerpf(_punch, 0.0, clampf(delta * 9.0, 0.0, 1.0))
	camera.zoom = Vector2(_zoom, _zoom) * (1.0 + _punch)
	Fx.view_scale = 1.0 / _zoom
	var vp := get_viewport().get_visible_rect().size
	var goal := center - (area.get_center() - vp * 0.5) / _zoom
	camera.position = goal if camera.position == Vector2.ZERO or direct else camera.position.lerp(goal, clampf(delta * 3.0, 0.0, 1.0))
	# 画面の揺れ：なめらかなノイズで、強さの2乗だけ動かす（小さな揺れは控えめ、大きな揺れははっきり）。
	# ほんの少しだけ傾けもする。毎フレームの乱数より、目が疲れにくく今風の揺れになる。
	_ensure_impact()
	_shake = maxf(0.0, _shake - delta * 1.6)
	_shake_t += delta
	var amt := _shake * _shake
	if amt > 0.0001:
		var nx := _shake_noise.get_noise_2d(_shake_t * 90.0, 0.0)
		var ny := _shake_noise.get_noise_2d(0.0, _shake_t * 90.0 + 50.0)
		var nr := _shake_noise.get_noise_2d(_shake_t * 90.0 + 100.0, 100.0)
		camera.offset = Vector2(nx, ny) * amt * 26.0 / _zoom
		camera.rotation = nr * amt * 0.02
	else:
		camera.offset = Vector2.ZERO
		camera.rotation = 0.0


## 画面を揺らす（爆発など）。amount は 0〜12 くらい（12 で最大）
func shake(amount: float) -> void:
	_shake = clampf(maxf(_shake, amount / 12.0) + amount / 60.0, 0.0, 1.0)


## カメラを一瞬だけ寄せて戻す（衝撃で押されたように）。amount は倍率の増え（0.02〜0.08）
func punch(amount: float) -> void:
	_punch = maxf(_punch, amount)


## 衝撃の画面効果のノード（惑星と演出の上、HUD の下）を用意する
func _ensure_impact() -> void:
	if Fx.impact != null and is_instance_valid(Fx.impact):
		return
	camera.ignore_rotation = false
	_shake_noise = FastNoiseLite.new()
	_shake_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_shake_noise.frequency = 0.05
	Fx.impact = ImpactFx.new()
	add_child(Fx.impact)


func _auto_buy() -> bool:
	var gs := GameState
	var best := ""
	var best_c := INF
	for t in gs.TOOLS:
		var id := String(t["id"])
		if not gs.tool_unlocked(id):
			continue
		var c := gs.upgrade_cost(id)
		if c < best_c:
			best = id
			best_c = c
	if best != "" and best_c <= gs.credits:
		gs.mark_tip("buy")
		return gs.buy_tool(best)
	return false


## 1ブロックの素材の量。先の惑星ほど多い（スキル費用の伸びに追いつくよう 1.6 倍ずつ）。
func _mat_amount() -> float:
	return pow(1.6, GameState.planet - 1)


func _on_cell_broken(pos: Vector2, value: float, b: int) -> void:
	var gs := GameState
	gs.earn(value)
	_pop_acc += value
	_pop_pos = pos
	var m := String(gs.BLOCKS[b]["mat"])
	var col: Color = gs.BLOCK_COLORS.get(b, Color(0.6, 0.55, 0.6))
	var show := _fx_budget >= 1.0
	if show:
		_fx_budget -= 1.0
		Fx.burst(fx_layer, pos, col, 5, 70.0)
		Fx.pop(fx_layer, pos, col.lightened(0.3), Planet.CELL)
	if m != "":
		var got := gs.add_mat(m, _mat_amount())
		var e: Array = _mat_pop.get(m, [0.0, pos])
		_mat_pop[m] = [float(e[0]) + got, pos]
		if show:
			_absorb(pos, col.lightened(0.3), 2 if b == gs.B.IRON or b == gs.B.COPPER else 4)
		if show:
			Fx.sparks(fx_layer, pos, col.lightened(0.3), 6 if b == gs.B.IRON or b == gs.B.COPPER else 12, 80.0)
		if show and (b == gs.B.GOLD or b == gs.B.CRYSTAL):
			Fx.flash(fx_layer, pos, Color(col, 0.7), Planet.CELL * 0.9, 0.3)
			Audio.play("ore_crystal")
		else:
			Audio.play("ore_metal")
	elif b == gs.B.RELIC:
		_relic_fx(pos)
		hud.offer_relics(gs.roll_relic_choices())
	elif b == gs.B.CACHE:
		var cr := gs.cell_value(planet.depth[planet.cell_at(pos)] if planet.cell_at(pos) >= 0 else 0.0) * 80.0
		gs.earn(cr)
		var mats: Array = gs.MATS.slice(0, mini(gs.MATS.size(), 1 + gs.planet))
		var mm: String = mats[randi() % mats.size()]
		var got := gs.add_mat(mm, _mat_amount() * randf_range(4.0, 10.0))
		Fx.burst(fx_layer, pos, Neon.ORANGE, 30, 200.0)
		Fx.sparks(fx_layer, pos, Neon.YELLOW, 16, 140.0)
		Fx.ring(fx_layer, pos, Neon.ORANGE, Planet.CELL * 6.0)
		_absorb(pos, Neon.YELLOW, 8)
		Audio.play("cache")
		_big_hit(pos, Neon.YELLOW, 0.06)
		Fx.popup(fx_layer, pos, "宝箱！ +%s CR・%s +%s" % [gs.fmt(cr), gs.MAT_NAMES[mm], gs.fmt(got)], Neon.YELLOW)
		if randf() < 0.3 * gs.relic_count("hoard"):
			_relic_fx(pos)
			hud.offer_relics(gs.roll_relic_choices())
	elif b == gs.B.HARD and gs.relic_count("hard") > 0:
		var got := gs.add_mat("iron", _mat_amount() * 3.0 * gs.relic_count("hard"))
		var e: Array = _mat_pop.get("iron", [0.0, pos])
		_mat_pop["iron"] = [float(e[0]) + got, pos]
		Audio.play("break")
	else:
		Audio.play("break")


func _relic_fx(pos: Vector2) -> void:
	var c: Color = GameState.RELIC_COLOR
	Fx.burst(fx_layer, pos, c, 30, 220.0)
	Fx.sparks(fx_layer, pos, c, 20, 160.0)
	Fx.ring(fx_layer, pos, c, Planet.CELL * 8.0)
	Fx.flash(fx_layer, pos, c, Planet.CELL * 3.0, 0.6)
	_absorb(pos, c, 8)
	Audio.play("relic")
	_big_hit(pos, c, 0.08)


## まれな大きな出来事（遺物・宝箱）の手応え：一瞬止めて、芯が光り、画面が波打ち、カメラが少し寄る
func _big_hit(pos: Vector2, col: Color, stop: float) -> void:
	ScreenFx.hitstop(stop)
	Fx.core(fx_layer, pos, col, Planet.CELL * 1.6, 0.2)
	Fx.shockwave(pos, Planet.CELL * 10.0, 0.8, 0.55)
	if Fx.impact != null:
		Fx.impact.aberrate(0.35)
	punch(0.035)
	shake(3.0)


## 埋まったままの遺物・宝箱が爆発に巻き込まれて壊れた
func _on_relic_lost(pos: Vector2, b: int) -> void:
	var gs := GameState
	var is_relic := b == gs.B.RELIC
	Fx.burst(fx_layer, pos, Neon.MUTED, 16, 120.0)
	Fx.popup(fx_layer, pos, "遺物が爆発で壊れた…" if is_relic else "宝箱が爆発で壊れた…", Neon.RED)


## 砕いた所から母艦へ、光の粒が吸い込まれる（数値は砕いた瞬間に入っている。見た目だけ）
func _absorb(pos: Vector2, col: Color, n: int) -> void:
	Fx.absorb(fx_layer, pos, tools.carrier_pos, col, n, tools.carrier_pulse)


func on_explosion(c: Vector2, r: float) -> void:
	if _fx_budget < 3.0:
		return
	_fx_budget -= 3.0
	Fx.explosion(fx_layer, c, r * 1.3)
	Fx.burst(fx_layer, c, Neon.ORANGE, 14, r * 4.0)
	Audio.play("blast")
	shake(4.0)
	punch(0.015)


func _on_cleared() -> void:
	var gs := GameState
	var bonus := planet.remaining_value() * 0.5
	gs.earn(bonus)
	var galaxy_done := gs.local_planet() == gs.GALAXY_SIZE
	var extra := gs.finish_planet()
	Fx.burst(fx_layer, focus, Neon.LINE, 90, 520.0)
	Fx.explosion(fx_layer, focus, Planet.CELL * 14.0)
	Fx.ring(fx_layer, focus, Neon.YELLOW, Planet.CELL * 30.0, 0.9)
	Fx.ring(fx_layer, focus, Neon.CYAN, Planet.CELL * 20.0, 0.7)
	Fx.popup(fx_layer, focus, "星系 %d を制覇！" % gs.galaxy() if galaxy_done else "惑星を破壊！", Neon.YELLOW, 18)
	Audio.play("clear")
	shake(12.0)
	# とどめの一撃：一瞬止めて、白く光り、色がずれ、大きな衝撃波が画面を走る
	ScreenFx.hitstop(0.14)
	Fx.core(fx_layer, focus, Neon.YELLOW, Planet.CELL * 5.0, 0.3)
	Fx.shockwave(focus, Planet.CELL * 30.0, 1.0, 0.9)
	if Fx.impact != null:
		Fx.impact.flash(Color(1.0, 0.95, 0.8), 0.5, 0.45)
		Fx.impact.aberrate(0.7)
	punch(0.08)
	# 全体まで引いて、残った塊が外へ飛び散る
	_outro = 0.0
	planet.hunt_cell = -1
	await get_tree().create_timer(1.0).timeout
	_shatter()
	var tw := create_tween()
	tw.tween_property(planet, "modulate", Color(1, 1, 1, 0.08), 1.2)
	await get_tree().create_timer(1.6).timeout
	get_tree().paused = true
	hud.show_clear(extra, gs.roll_next_traits())
	gs.save()
	if bot:
		print("[bot] CLEAR %s (planet %d) in %.1f min cores=%s" % [gs.place_name(), gs.planet, gs.planet_time / 60.0, gs.fmt(gs.cores)])
		gs.buy_all_skills()
		for k in 50:
			var any := false
			for c in gs.CORE_UPS:
				if gs.buy_core(String(c["id"])):
					any = true
			if not any:
				break
		go_next(String(gs.next_traits[0]))


## 割れた惑星の残りが、中心から外へ飛び散る（残ったマスから最大90か所）
func _shatter() -> void:
	var gs := GameState
	var alive: Array = []
	for i in planet.hp.size():
		if planet.hp[i] > 0.0:
			alive.append(i)
	alive.shuffle()
	for k in mini(90, alive.size()):
		var i: int = alive[k]
		var b := int(planet.block[i])
		var col: Color = gs.BLOCK_COLORS.get(b, Neon.LINE)
		Fx.burst(fx_layer, planet.cell_center(i), col, 3, 260.0 + 200.0 * planet.depth[i])
	Fx.ring(fx_layer, planet.position, Neon.LINE, planet.world_radius() * 1.6, 1.0)
	Fx.flash(fx_layer, planet.position, Neon.YELLOW, planet.world_radius() * 0.6, 0.8)
	Fx.shockwave(planet.position, planet.world_radius() * 1.4, 1.0, 1.1)
	if Fx.impact != null:
		Fx.impact.aberrate(0.8)
	Audio.play("blast")
	shake(10.0)


func go_next(trait_id: String) -> void:
	var gs := GameState
	gs.start_planet(gs.planet + 1, trait_id)
	hud.hide_panels()
	get_tree().paused = false
	build_planet()
	gs.save()


## 開いている星系の惑星1へ移る（周回）。今の惑星の進み具合・ツール・遺物は手放す。
func warp(g: int) -> void:
	var gs := GameState
	if not gs.can_warp(g):
		return
	gs.start_planet((g - 1) * gs.GALAXY_SIZE + 1, "plain")
	hud.hide_panels()
	get_tree().paused = false
	build_planet()
	gs.save()


## タップした場所を機体の移動先にする。岩の中なら、一番近い入れる場所に直す。
func set_destination(world_pos: Vector2) -> void:
	if planet.done:
		return
	if GameState.has_key("k_drift"):
		hud.toast("無人航行中は、移動先を決められない")
		return
	# 埋まった遺物・宝箱の気配の近くをタップしたら、それを掘りに行く
	var hb := planet.buried_near(world_pos, 3.0)
	if hb >= 0 and not planet.is_exposed(hb):
		planet.hunt_cell = hb
		_hunt_auto = false
		_manual = true
		GameState.mark_tip("tap")
		GameState.mark_tip("hunt")
		_focus_t = 0.0
		tools.tap_effect(planet.cell_center(hb))
		Audio.play("move")
		hud.toast("遺物の気配を掘りに行く" if int(planet.block[hb]) == GameState.B.RELIC else "宝箱の気配を掘りに行く")
		return
	planet.hunt_cell = -1
	_focus_goal = planet.nearest_open(world_pos)
	# 何もない宇宙を指したときは、その真下の地表へ降りる
	if planet.targets_near(_focus_goal, 6).is_empty():
		var i := planet.raycast(_focus_goal, planet.position)
		if i < 0 or not planet.is_exposed(i):
			i = planet.nearest_exposed(_focus_goal)
		if i >= 0:
			_focus_goal = planet.hover_point(i, Planet.CELL)
	_manual = true
	GameState.mark_tip("tap")
	_dwell = 0.0
	_focus_t = 0.5
	tools.tap_effect(_focus_goal)
	Audio.play("move")
	tools.rescan()


func _unhandled_input(event: InputEvent) -> void:
	var pressed := false
	var pos := Vector2.ZERO
	if event is InputEventScreenTouch and event.pressed:
		pressed = true
		pos = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not touch_ui:
		pressed = true
		pos = event.position
	if pressed and hud.planet_area().has_point(pos) and not hud.any_panel():
		set_destination(get_canvas_transform().affine_inverse() * pos)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		GameState.save()
