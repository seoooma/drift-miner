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
var _shake: float = 0.0
var _fx_budget: float = 20.0  # 1秒に出せる破片演出の数（多すぎると重くなる）
var _manual := false  # プレイヤーが指定した移動先へ向かっている／そこを掘っている
var _dwell: float = 0.0  # 今の場所に着いてからの時間
var _speed: float = 0.0
var bot := false  # 確認用の自動プレイ（--bot）。強化とスキルを自動で買い、惑星を割ったら次へ進む
var _bot_t: float = 0.0


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
	GameState.hp_provider = func() -> PackedFloat32Array: return planet.hp

	if touch_ui:
		get_tree().root.size_changed.connect(_apply_mobile_scale)
		_apply_mobile_scale()
	build_planet(GameState.saved_hp)
	if GameState.pending_clear and planet.done:
		# 惑星を割った画面で閉じていたときは、その画面から続ける
		get_tree().paused = true
		var nx: Array = GameState.next_traits if not GameState.next_traits.is_empty() else GameState.roll_next_traits()
		hud.show_clear(GameState.clear_extra, nx)
	elif GameState.offline_gain > 0.0:
		hud.show_offline(GameState.offline_gain, GameState.offline_secs)


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
	hud.banner("惑星 %d：%s" % [gs.planet, tr["name"]], String(tr["desc"]) if saved.is_empty() else "")


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
	_focus_t -= delta
	if _focus_t <= 0.0:
		_focus_t = 0.5
		if _manual and arrived and planet.targets_near(focus, 6).is_empty():
			_manual = false
		if not _manual:
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
func _fit_camera(delta: float) -> void:
	var area: Rect2 = hud.planet_area()
	var target := minf(area.size.x, area.size.y) / (VIEW_CELLS * Planet.CELL)
	_zoom = target if _zoom <= 0.0 else lerpf(_zoom, target, clampf(delta * 3.0, 0.0, 1.0))
	camera.zoom = Vector2(_zoom, _zoom)
	Fx.view_scale = 1.0 / _zoom
	var vp := get_viewport().get_visible_rect().size
	var goal := view_point() - (area.get_center() - vp * 0.5) / _zoom
	camera.position = goal if camera.position == Vector2.ZERO else camera.position.lerp(goal, clampf(delta * 3.0, 0.0, 1.0))
	# 画面の揺れ
	_shake = maxf(0.0, _shake - delta * 18.0)
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake / _zoom * 2.0


## 画面を揺らす（爆発など）
func shake(amount: float) -> void:
	_shake = clampf(maxf(_shake, amount), 0.0, 12.0)


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
		var r := gs.add_random_relic()
		Fx.burst(fx_layer, pos, Neon.CYAN, 30, 220.0)
		Fx.sparks(fx_layer, pos, Neon.CYAN, 20, 160.0)
		Fx.ring(fx_layer, pos, Neon.CYAN, Planet.CELL * 8.0)
		Fx.flash(fx_layer, pos, Neon.CYAN, Planet.CELL * 3.0, 0.6)
		_absorb(pos, Neon.CYAN, 8)
		Audio.play("relic")
		hud.relic_found(r)
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
		Fx.popup(fx_layer, pos, "宝箱！ +%s CR・%s +%s" % [gs.fmt(cr), gs.MAT_NAMES[mm], gs.fmt(got)], Neon.YELLOW)
	else:
		Audio.play("break")


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


func _on_cleared() -> void:
	var gs := GameState
	var bonus := planet.remaining_value() * 0.5
	gs.earn(bonus)
	var extra := gs.finish_planet()
	Fx.burst(fx_layer, focus, Neon.LINE, 90, 520.0)
	Fx.explosion(fx_layer, focus, Planet.CELL * 14.0)
	Fx.ring(fx_layer, focus, Neon.YELLOW, Planet.CELL * 30.0, 0.9)
	Fx.ring(fx_layer, focus, Neon.CYAN, Planet.CELL * 20.0, 0.7)
	Fx.popup(fx_layer, focus, "惑星を破壊！", Neon.YELLOW)
	Audio.play("clear")
	shake(12.0)
	await get_tree().create_timer(1.2).timeout
	get_tree().paused = true
	hud.show_clear(extra, gs.roll_next_traits())
	gs.save()
	if bot:
		print("[bot] CLEAR planet %d in %.1f min" % [gs.planet, gs.planet_time / 60.0])
		gs.buy_all_skills()
		go_next(String(gs.next_traits[0]))


func go_next(trait_id: String) -> void:
	var gs := GameState
	gs.start_planet(gs.planet + 1, trait_id)
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
