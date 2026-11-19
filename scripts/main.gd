extends Node2D
## ゲームの進行。巨大惑星の生成と保存、砕いたブロックの報酬（クレジット・素材・遺物・宝箱）、
## 惑星クリアと次の惑星、タップ掘り、自動タップ・自動強化、狙いの中心 (focus) と寄りのカメラを受け持つ。

const VIEW_CELLS := 20.0  # 画面の短い辺に並ぶマスの数（ブロック1つ ≒ 画面幅の1/20）
const MANUAL_HOLD := 10.0  # タップした場所を狙い続ける秒数

const HudScript := preload("res://scripts/hud.gd")
const BackdropScript := preload("res://scripts/backdrop.gd")

var backdrop: Node2D
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
var _tap_t: float = 0.0
var _zoom: float = 0.0
var focus := Vector2.ZERO  # ツールが狙う中心（ワールド座標）
var _focus_goal := Vector2.ZERO
var _focus_t: float = 0.0
var _manual_t: float = 0.0


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
	focus = planet.cell_center(top) if top >= 0 else planet.position
	_focus_goal = focus
	_manual_t = 0.0
	_focus_t = 0.0
	tools.focus = focus
	var tr := gs.trait_def()
	hud.banner("惑星 %d：%s" % [gs.planet, tr["name"]], String(tr["desc"]) if saved.is_empty() else "")


func _process(delta: float) -> void:
	_update_focus(delta)
	_fit_camera(delta)
	var gs := GameState
	if gs.skill_level("auto_buy") > 0:
		_auto_t += delta
		if _auto_t >= 0.5:
			_auto_t = 0.0
			_auto_buy()
	var taps := gs.skill_level("auto_tap")
	if taps > 0 and not planet.done:
		_tap_t += delta
		if _tap_t >= 1.0 / taps:
			_tap_t = 0.0
			var i := planet.random_surface_cell()
			if i >= 0:
				tap_at(planet.cell_center(i))
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


## 狙いの中心を決める。タップした直後はそこを狙い続け、それ以外は
## 近くで一番「おいしい」マス（鉱石・遺物・浅い所）へ少しずつ移っていく。
func _update_focus(delta: float) -> void:
	if planet.done:
		return
	_manual_t -= delta
	_focus_t -= delta
	if _focus_t <= 0.0:
		_focus_t = 0.5
		var near := planet.targets_near(focus, 5)
		if _manual_t > 0.0 and not near.is_empty():
			_focus_goal = focus
		else:
			_manual_t = 0.0
			var t := planet.targets_near(focus, 20)
			if not t.is_empty():
				_focus_goal = planet.cell_center(int(t[0]))
			else:
				var i := planet.raycast(focus, planet.position)
				if i < 0:
					i = planet.random_surface_cell()
				if i >= 0:
					_focus_goal = planet.cell_center(i)
	if _manual_t <= 0.0:
		focus = focus.move_toward(_focus_goal, maxf(18.0, focus.distance_to(_focus_goal) * 1.5) * delta)
	tools.focus = focus


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
	if m != "":
		var got := gs.add_mat(m, _mat_amount())
		var e: Array = _mat_pop.get(m, [0.0, pos])
		_mat_pop[m] = [float(e[0]) + got, pos]
		if b == gs.B.GOLD or b == gs.B.CRYSTAL:
			Fx.burst(fx_layer, pos, gs.BLOCK_COLORS[b], 8, 90.0)
	elif b == gs.B.RELIC:
		var r := gs.add_random_relic()
		Fx.burst(fx_layer, pos, Color(0.4, 1.0, 0.9), 40, 220.0)
		hud.relic_found(r)
	elif b == gs.B.CACHE:
		var cr := gs.cell_value(planet.depth[planet.cell_at(pos)] if planet.cell_at(pos) >= 0 else 0.0) * 80.0
		gs.earn(cr)
		var mats: Array = gs.MATS.slice(0, mini(gs.MATS.size(), 1 + gs.planet))
		var mm: String = mats[randi() % mats.size()]
		var got := gs.add_mat(mm, _mat_amount() * randf_range(4.0, 10.0))
		Fx.burst(fx_layer, pos, Color(1.0, 0.85, 0.3), 36, 200.0)
		Fx.popup(fx_layer, pos, "宝箱！ +%s CR・%s +%s" % [gs.fmt(cr), gs.MAT_NAMES[mm], gs.fmt(got)], Color(1.0, 0.9, 0.4))


func on_explosion(c: Vector2, r: float) -> void:
	Fx.burst(fx_layer, c, Color(1.0, 0.45, 0.2), 30, r * 4.0)


func _on_cleared() -> void:
	var gs := GameState
	var bonus := planet.remaining_value() * 0.5
	gs.earn(bonus)
	var extra := gs.finish_planet()
	Fx.burst(fx_layer, focus, Color(1.0, 0.85, 0.5), 120, 520.0)
	Fx.popup(fx_layer, focus, "惑星を破壊！", Color(1.0, 0.9, 0.5))
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


func tap_at(world_pos: Vector2) -> void:
	if planet.done:
		return
	planet.hit_area(world_pos, Planet.CELL * 1.8, GameState.tap_damage())
	tools.tap_effect(world_pos)


## プレイヤーがタップした場所を、しばらく狙いの中心にする。
func set_focus(world_pos: Vector2) -> void:
	focus = world_pos
	_focus_goal = world_pos
	_manual_t = MANUAL_HOLD
	_focus_t = 0.0
	tools.focus = focus
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
		var wp := get_canvas_transform().affine_inverse() * pos
		set_focus(wp)
		tap_at(wp)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		GameState.save()
