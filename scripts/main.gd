extends Node2D
## ゲームの進行。巨大惑星の生成と保存、砕いたブロックの報酬（クレジット・素材・遺物・宝箱）、
## 惑星クリアと次の惑星、自動強化、機体の集まる場所 (focus) と寄りのカメラを受け持つ。
## タップは攻撃ではなく「移動先の指定」。機体はそこへ移動し、周りを掘り尽くすと自動の探索に戻る。

const VIEW_CELLS := 20.0  # 画面の短い辺に並ぶマスの数（ブロック1つ ≒ 画面幅の1/20）

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


func _ready() -> void:
	randomize()
	touch_ui = DisplayServer.is_touchscreen_available() or "--touch" in OS.get_cmdline_user_args()

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
	if GameState.offline_gain > 0.0:
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
	tools.focus = focus
	tools.dest = _focus_goal if _manual else Vector2.INF
	var tr := gs.trait_def()
	hud.banner("惑星 %d：%s" % [gs.planet, tr["name"]], String(tr["desc"]) if saved.is_empty() else "")


func _process(delta: float) -> void:
	_fx_budget = minf(20.0, _fx_budget + delta * 24.0)
	_update_focus(delta)
	_fit_camera(delta)
	var gs := GameState
	if gs.skill_level("auto_buy") > 0:
		_auto_t += delta
		if _auto_t >= 0.5:
			_auto_t = 0.0
			_auto_buy()
	_pop_t -= delta
	if _pop_t <= 0.0 and _pop_acc > 0.0:
		Fx.popup(fx_layer, _pop_pos, "+" + gs.fmt(_pop_acc), Color(0.85, 1.0, 0.9))
		_pop_acc = 0.0
		_pop_t = 0.35
	_mat_pop_t -= delta
	if _mat_pop_t <= 0.0 and not _mat_pop.is_empty():
		_mat_pop_t = 0.5
		for m in _mat_pop:
			var e: Array = _mat_pop[m]
			Fx.popup(fx_layer, e[1] + Vector2(0, -6), "+%s %s" % [gs.fmt(e[0]), gs.MAT_NAMES[m]], gs.MAT_COLORS[m])
		_mat_pop.clear()


## 機体の集まる場所を決める。移動先が指定されていればそこへ向かい、着いてから
## 周りを掘り尽くすまで留まる。それ以外は、探索範囲の中で一番「おいしい」マス
## （鉱石・遺物・浅い所）の前へ移っていく。どちらも外とつながった空きだけを通る。
func _update_focus(delta: float) -> void:
	if planet.done:
		return
	var gs := GameState
	_focus_t -= delta
	if _focus_t <= 0.0:
		_focus_t = 0.5
		if _manual and focus.distance_to(_focus_goal) < Planet.CELL and planet.targets_near(focus, 6).is_empty():
			_manual = false
		if not _manual:
			var t := planet.targets_near(focus, gs.scan_radius(), 0.6)
			var i := int(t[0]) if not t.is_empty() else planet.nearest_exposed(focus)
			if i >= 0:
				_focus_goal = planet.hover_point(i, Planet.CELL)
	var sp := 70.0 if _manual else maxf(18.0, focus.distance_to(_focus_goal) * 1.5)
	focus = focus.move_toward(_focus_goal, sp * gs.move_mult() * delta)
	tools.focus = focus
	tools.dest = _focus_goal if _manual else Vector2.INF


## 惑星の一部だけが大きく映るよう、狙いの中心にカメラを寄せる。
func _fit_camera(delta: float) -> void:
	var area: Rect2 = hud.planet_area()
	var target := minf(area.size.x, area.size.y) / (VIEW_CELLS * Planet.CELL)
	_zoom = target if _zoom <= 0.0 else lerpf(_zoom, target, clampf(delta * 3.0, 0.0, 1.0))
	camera.zoom = Vector2(_zoom, _zoom)
	Fx.view_scale = 1.0 / _zoom
	var vp := get_viewport().get_visible_rect().size
	var goal := focus - (area.get_center() - vp * 0.5) / _zoom
	camera.position = goal if camera.position == Vector2.ZERO else camera.position.lerp(goal, clampf(delta * 3.0, 0.0, 1.0))
	# 画面の揺れ
	_shake = maxf(0.0, _shake - delta * 18.0)
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake / _zoom * 2.0


## 画面を揺らす（爆発など）
func shake(amount: float) -> void:
	_shake = clampf(maxf(_shake, amount), 0.0, 12.0)


func _auto_buy() -> void:
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
		gs.buy_tool(best)


func _mat_amount() -> float:
	return pow(1.3, GameState.planet - 1)


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
			Fx.sparks(fx_layer, pos, col.lightened(0.3), 6 if b == gs.B.IRON or b == gs.B.COPPER else 12, 80.0)
		if show and (b == gs.B.GOLD or b == gs.B.CRYSTAL):
			Fx.flash(fx_layer, pos, Color(col, 0.7), Planet.CELL * 2.5, 0.3)
			Audio.play("ore_crystal")
		else:
			Audio.play("ore_metal")
	elif b == gs.B.RELIC:
		var r := gs.add_random_relic()
		Fx.burst(fx_layer, pos, Color(0.4, 1.0, 0.9), 40, 220.0)
		Fx.sparks(fx_layer, pos, Color(0.5, 1.0, 0.95), 24, 160.0)
		Fx.ring(fx_layer, pos, Color(0.4, 1.0, 0.9), Planet.CELL * 8.0)
		Fx.flash(fx_layer, pos, Color(0.4, 1.0, 0.9), Planet.CELL * 6.0, 0.6)
		Audio.play("relic")
		hud.relic_found(r)
	elif b == gs.B.CACHE:
		var cr := gs.cell_value(planet.depth[planet.cell_at(pos)] if planet.cell_at(pos) >= 0 else 0.0) * 80.0
		gs.earn(cr)
		var mats: Array = gs.MATS.slice(0, mini(gs.MATS.size(), 1 + gs.planet))
		var mm: String = mats[randi() % mats.size()]
		var got := gs.add_mat(mm, _mat_amount() * randf_range(4.0, 10.0))
		Fx.burst(fx_layer, pos, Color(1.0, 0.85, 0.3), 36, 200.0)
		Fx.sparks(fx_layer, pos, Color(1.0, 0.9, 0.5), 20, 140.0)
		Fx.ring(fx_layer, pos, Color(1.0, 0.85, 0.3), Planet.CELL * 6.0)
		Audio.play("cache")
		Fx.popup(fx_layer, pos, "宝箱！ +%s CR・%s +%s" % [gs.fmt(cr), gs.MAT_NAMES[mm], gs.fmt(got)], Color(1.0, 0.9, 0.4))
	else:
		Audio.play("break")


func on_explosion(c: Vector2, r: float) -> void:
	if _fx_budget < 3.0:
		return
	_fx_budget -= 3.0
	Fx.explosion(fx_layer, c, r * 1.3)
	Fx.burst(fx_layer, c, Color(1.0, 0.45, 0.2), 18, r * 4.0)
	Audio.play("blast")
	shake(4.0)


func _on_cleared() -> void:
	var gs := GameState
	var bonus := planet.remaining_value() * 0.5
	gs.earn(bonus)
	var extra := gs.finish_planet()
	Fx.burst(fx_layer, focus, Color(1.0, 0.85, 0.5), 120, 520.0)
	Fx.explosion(fx_layer, focus, Planet.CELL * 14.0)
	Fx.ring(fx_layer, focus, Color(1.0, 0.85, 0.5), Planet.CELL * 30.0, 0.9)
	Fx.flash(fx_layer, focus, Color(1.0, 0.9, 0.7), Planet.CELL * 40.0, 1.0)
	Fx.popup(fx_layer, focus, "惑星を破壊！", Color(1.0, 0.9, 0.5))
	Audio.play("clear")
	shake(12.0)
	await get_tree().create_timer(1.2).timeout
	get_tree().paused = true
	hud.show_clear(extra, gs.roll_next_traits())
	gs.save()


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
	_focus_goal = planet.nearest_open(world_pos)
	# 何もない宇宙を指したときは、その真下の地表へ降りる
	if planet.targets_near(_focus_goal, 6).is_empty():
		var i := planet.raycast(_focus_goal, planet.position)
		if i < 0 or not planet.is_exposed(i):
			i = planet.nearest_exposed(_focus_goal)
		if i >= 0:
			_focus_goal = planet.hover_point(i, Planet.CELL)
	_manual = true
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
