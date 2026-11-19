extends Node2D
## ゲームの進行。惑星の生成、採掘で得たクレジット、惑星クリアとカード選択、
## 巨大惑星の制限時間、タップ掘り、自動強化、画面に合わせたカメラを受け持つ。

const HudScript := preload("res://scripts/hud.gd")
const BackdropScript := preload("res://scripts/backdrop.gd")

var backdrop: Node2D
var planet: Planet
var tools: Tools
var fx_layer: Node2D
var camera: Camera2D
var hud: CanvasLayer
var touch_ui: bool = false

var boss_left: float = 0.0
var _pop_acc: float = 0.0
var _pop_pos := Vector2.ZERO
var _pop_col := Color.WHITE
var _pop_t: float = 0.0
var _auto_t: float = 0.0
var _rerolls_left: int = 0
var _jackpot_cool: float = 0.0


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

	if touch_ui:
		get_tree().root.size_changed.connect(_apply_mobile_scale)
		_apply_mobile_scale()
	new_planet()
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


func new_planet() -> void:
	for c in fx_layer.get_children():
		c.queue_free()
	var gs := GameState
	planet.position = Vector2.ZERO
	planet.generate(hash("%d:%d" % [gs.run_seed, gs.planet]), gs.is_boss())
	tools.reset_for(planet)
	boss_left = gs.boss_time() if gs.is_boss() else 0.0
	_rerolls_left = gs.rerolls()
	var title := "銀河 %d ・ 惑星 %d" % [gs.galaxy(), gs.planet_in_galaxy()]
	hud.banner(title, "巨大惑星！%d秒以内に割る" % int(boss_left) if gs.is_boss() else "")


func _process(delta: float) -> void:
	_fit_camera()
	var gs := GameState
	if gs.is_boss() and not planet.done:
		boss_left -= delta
		if boss_left <= 0.0:
			hud.toast("時間切れ…巨大惑星が再生した。ツールを強化して再挑戦！", 3.5)
			new_planet()
	if gs.skill_level("autobuy") > 0:
		_auto_t += delta
		if _auto_t >= 0.5:
			_auto_t = 0.0
			_auto_buy()
	_pop_t -= delta
	_jackpot_cool -= delta
	if _pop_t <= 0.0 and _pop_acc > 0.0:
		Fx.popup(fx_layer, _pop_pos, "+" + gs.fmt(_pop_acc), _pop_col)
		_pop_acc = 0.0
		_pop_t = 0.3


## 惑星とツールが HUD の「惑星エリア」にちょうど収まるようにカメラを合わせる。
func _fit_camera() -> void:
	var area: Rect2 = hud.planet_area()
	var need := (planet.world_radius() + 110.0) * 2.0
	var z := minf(area.size.x, area.size.y) / need
	camera.zoom = Vector2(z, z)
	var vp := get_viewport().get_visible_rect().size
	# 画面中心からエリア中心へのずれを、ワールド座標に直してカメラをずらす
	camera.position = planet.position - (area.get_center() - vp * 0.5) / z


func _auto_buy() -> void:
	var gs := GameState
	var best := ""
	var best_c := INF
	for t in gs.TOOLS:
		var id := String(t["id"])
		var c := gs.upgrade_cost(id)
		if c < best_c:
			best = id
			best_c = c
	if best != "" and best_c <= gs.credits:
		gs.buy_tool(best)


func _on_cell_broken(pos: Vector2, value: float, ore: int) -> void:
	var gs := GameState
	if gs.card_count("jackpot") > 0 and randf() < 0.06 * gs.card_count("jackpot"):
		value *= 10.0
		if _jackpot_cool <= 0.0:
			_jackpot_cool = 1.2
			Fx.popup(fx_layer, pos, "大当たり ×10", Color(1.0, 0.9, 0.3))
	gs.earn(value)
	_pop_acc += value
	_pop_pos = pos
	_pop_col = Color(0.85, 1.0, 0.9) if ore == 0 else gs.ORE_COLORS[ore].lightened(0.3)
	if ore >= 3:
		Fx.burst(fx_layer, pos, gs.ORE_COLORS[ore], 8, 90.0)


func _on_cleared() -> void:
	var gs := GameState
	var bonus := planet.remaining_value() * 0.5
	gs.earn(bonus)
	Fx.burst(fx_layer, planet.position, Color(1.0, 0.85, 0.5), 80, 420.0)
	Fx.popup(fx_layer, planet.position, "惑星を破壊！ +" + gs.fmt(bonus), Color(1.0, 0.9, 0.5))
	await get_tree().create_timer(0.9).timeout
	_offer_cards()


func _offer_cards() -> void:
	get_tree().paused = true
	hud.show_cards(GameState.roll_cards(GameState.card_choices()), _rerolls_left)


func reroll_cards() -> void:
	if _rerolls_left <= 0:
		return
	_rerolls_left -= 1
	hud.show_cards(GameState.roll_cards(GameState.card_choices()), _rerolls_left)


func on_card_chosen(key: String) -> void:
	var gs := GameState
	gs.take_card(key)
	gs.planet += 1
	gs.best_planet_run = maxi(gs.best_planet_run, gs.planet)
	gs.best_planet = maxi(gs.best_planet, gs.planet)
	hud.hide_panels()
	get_tree().paused = false
	new_planet()
	gs.save()


func tap_at(world_pos: Vector2) -> void:
	if planet.done:
		return
	planet.hit_area(world_pos, Planet.CELL * 1.8, GameState.tap_damage())
	tools.tap_effect(world_pos)


func do_prestige() -> void:
	GameState.prestige()
	hud.hide_panels()
	get_tree().paused = false
	new_planet()
	hud.toast("帰還完了。研究データでスキルを強化しよう", 3.0)


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
		tap_at(get_canvas_transform().affine_inverse() * pos)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		GameState.save()
