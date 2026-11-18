extends CanvasLayer
## 画面表示。燃料バー、資源、目標、方向ガイド、メッセージ、パーク選択、ゲームオーバー。

const SIGNAL_RANGE := 1300.0

var main: Node = null

var _overlay: Control
var _info: Label
var _goal: Label
var _help: Label
var _toast: Label
var _toast_time: float = 0.0
var _banner: Label
var _banner_time: float = 0.0
var _perk_panel: PanelContainer
var _perk_box: VBoxContainer
var _over_panel: PanelContainer
var _over_label: Label
var _over_hint: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)

	_info = _make_label(20, Vector2(20, 52))
	_goal = _make_label(22, Vector2(20, 0))
	_goal.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_goal.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_goal.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_goal.offset_bottom = -60
	_goal.modulate = Color(1.0, 0.95, 0.7)

	_help = _make_label(16, Vector2.ZERO)
	_help.text = "WASD:移動  左クリック長押し:採掘  B:採掘機  E:ワープ"
	_help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_help.offset_left = 20
	_help.offset_top = -34
	_help.modulate = Color(1, 1, 1, 0.6)

	_toast = _make_label(24, Vector2.ZERO)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.offset_top = 96

	_banner = _make_label(40, Vector2.ZERO)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.offset_top = -160

	_perk_panel = _make_panel()
	_perk_box = VBoxContainer.new()
	_perk_box.add_theme_constant_override("separation", 10)
	_perk_panel.add_child(_perk_box)

	_over_panel = _make_panel()
	var over_box := VBoxContainer.new()
	over_box.add_theme_constant_override("separation", 16)
	_over_panel.add_child(over_box)
	_over_label = Label.new()
	_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_label.add_theme_font_size_override("font_size", 26)
	over_box.add_child(_over_label)
	var retry := Button.new()
	retry.text = "もう一度遊ぶ"
	retry.custom_minimum_size = Vector2(0, 72)
	retry.add_theme_font_size_override("font_size", 24)
	retry.pressed.connect(func(): main.restart())
	over_box.add_child(retry)
	_over_hint = Label.new()
	_over_hint.text = "（Rキーでもリスタート）"
	_over_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_hint.modulate = Color(1, 1, 1, 0.6)
	over_box.add_child(_over_hint)


func _make_label(font_size: int, pos: Vector2) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _make_panel() -> PanelContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)
	panel.visible = false
	return panel


func _touch() -> bool:
	return main != null and main.touch.active


func _process(delta: float) -> void:
	var gs := GameState
	var info: Dictionary = SectorGenerator.TYPES[gs.sector_type]
	var lines: PackedStringArray = [
		"セクター %d/%d  %s" % [gs.sector, gs.FINAL_SECTOR, info["name"]],
		"鉄 %d   結晶 %d" % [int(gs.res["iron"]), int(gs.res["crystal"])],
		"採掘機：%s" % gs.cost_text(gs.miner_cost()),
		"ワープ：%s" % gs.cost_text(gs.warp_cost()),
	]
	_info.text = "\n".join(lines)
	_goal.text = _goal_text()

	if _touch():
		_help.text = "左：スティックで移動　右：押して採掘"
		_info.add_theme_font_size_override("font_size", 26)

	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)
	if _banner_time > 0.0:
		_banner_time -= delta
		_banner.modulate.a = clampf(_banner_time, 0.0, 1.0)
	_overlay.queue_redraw()


func _goal_text() -> String:
	if not GameState.alive or main == null:
		return ""
	var any_found := false
	for g in main.gates:
		if g.discovered:
			any_found = true
	var need := GameState.warp_cost()
	if not GameState.can_afford(need):
		var miss: PackedStringArray = []
		for k in need:
			var lack := int(need[k]) - int(GameState.res[k])
			if lack > 0:
				miss.append("%s あと%d" % [GameState.RES_NAMES[k], lack])
		var s := "ワープ費用を集める（%s）" % "・".join(miss)
		if not any_found:
			s += "／ゲートを探す"
		return s
	if not any_found:
		return "ゲートを探す（外側へ）"
	return "ゲートへ向かってワープ！"


func toast(text: String, duration: float = 2.5) -> void:
	_toast.text = text
	_toast_time = duration


func banner(title: String, sub: String) -> void:
	_banner.text = title if sub == "" else "%s\n%s" % [title, sub]
	_banner_time = 3.0


func _draw_overlay() -> void:
	var size := _overlay.size
	var font := _overlay.get_theme_default_font()
	var gs := GameState
	var t := Time.get_ticks_msec() * 0.001

	# 燃料バー
	var frac := gs.fuel / gs.max_fuel
	var bar := Rect2(20, 16, minf(420.0, size.x * 0.35), 26)
	var col := Color(0.4, 0.85, 1.0)
	if frac < 0.15:
		col = Color(1.0, 0.25, 0.2).lerp(Color(1, 1, 1), 0.3 * (0.5 + 0.5 * sin(t * 12.0)))
	elif frac < 0.3:
		col = Color(1.0, 0.8, 0.2)
	_overlay.draw_rect(bar, Color(0, 0, 0, 0.5))
	_overlay.draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), col)
	_overlay.draw_rect(bar, Color(1, 1, 1, 0.5), false, 2.0)
	var burn: float = (main.player.IDLE_BURN + 0.45) * gs.fuel_burn_mult * gs.instability() if main != null else 1.0
	var secs := int(gs.fuel / maxf(burn, 0.01))
	var label := "燃料 %d/%d  残り約%d秒" % [int(gs.fuel), int(gs.max_fuel), secs]
	_overlay.draw_string_outline(font, bar.position + Vector2(10, 20), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 4, Color(0, 0, 0, 0.8))
	_overlay.draw_string(font, bar.position + Vector2(10, 20), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)

	# 不安定化
	var inst := gs.instability()
	var x := bar.end.x + 16
	if inst > 1.0:
		var txt := "不安定化 ×%.1f" % inst
		var c := Color(1.0, 0.4, 0.3).lerp(Color.WHITE, 0.3 * (0.5 + 0.5 * sin(t * 6.0)))
		_overlay.draw_string_outline(font, Vector2(x, 36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 4, Color(0, 0, 0, 0.8))
		_overlay.draw_string(font, Vector2(x, 36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, c)
	else:
		var left := int(gs.instability_grace - gs.sector_time)
		var txt2 := "安定 残り%d秒" % left
		_overlay.draw_string(font, Vector2(x, 36), txt2, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.6))

	if main == null or not gs.alive:
		return

	# 低燃料時の画面縁
	if frac < 0.15:
		var a := 0.25 + 0.2 * sin(t * 8.0)
		for i in 6:
			var w := 6.0 + i * 6.0
			var cc := Color(1.0, 0.1, 0.1, a * (1.0 - i / 6.0) * 0.5)
			_overlay.draw_rect(Rect2(0, 0, size.x, w), cc)
			_overlay.draw_rect(Rect2(0, size.y - w, size.x, w), cc)
			_overlay.draw_rect(Rect2(0, 0, w, size.y), cc)
			_overlay.draw_rect(Rect2(size.x - w, 0, w, size.y), cc)

	# 方向ガイド
	var xf: Transform2D = _overlay.get_viewport().get_canvas_transform()
	var ppos: Vector2 = main.player.global_position
	for g in main.gates:
		var d: float = ppos.distance_to(g.global_position)
		if g.discovered:
			_edge_arrow(xf * g.global_position, g.color(), "ゲート %dm" % int(d), size, font)
		elif d < SIGNAL_RANGE:
			# 未発見：信号。遠いほど方向がぶれる
			var err := (d / SIGNAL_RANGE) * 0.7 * sin(t * 0.7 + g.global_position.x)
			var dir: Vector2 = (g.global_position - ppos).normalized().rotated(err)
			_edge_arrow(xf * (ppos + dir * 5000.0), Color(g.color(), 0.5), "微弱な信号", size, font)
	if frac < 0.35:
		var ice: Asteroid = _nearest_ice(ppos)
		if ice != null:
			_edge_arrow(xf * ice.global_position, Asteroid.COLORS["ice"], "氷", size, font)


func _nearest_ice(p: Vector2) -> Asteroid:
	var best: Asteroid = null
	var best_d := INF
	for a in main.asteroid_layer.get_children():
		var ast := a as Asteroid
		if ast.kind == "ice" and ast.discovered and ast.is_alive():
			var d := ast.position.distance_to(p)
			if d < best_d:
				best = ast
				best_d = d
	return best


func _edge_arrow(screen_pos: Vector2, col: Color, text: String, size: Vector2, font: Font) -> void:
	var margin := 56.0
	var rect := Rect2(Vector2(margin, margin + 40), size - Vector2(margin * 2, margin * 2 + 40))
	if rect.has_point(screen_pos):
		return
	var center := size * 0.5
	var dir := (screen_pos - center).normalized()
	# 中心から画面端の矩形へ投影
	var tx := INF
	var ty := INF
	if dir.x != 0.0:
		tx = ((rect.end.x if dir.x > 0 else rect.position.x) - center.x) / dir.x
	if dir.y != 0.0:
		ty = ((rect.end.y if dir.y > 0 else rect.position.y) - center.y) / dir.y
	var p := center + dir * minf(absf(tx), absf(ty))
	var tri := PackedVector2Array([p + dir * 18.0, p + dir.rotated(2.5) * 14.0, p + dir.rotated(-2.5) * 14.0])
	_overlay.draw_colored_polygon(tri, col)
	var tp := p - dir * 30.0 + Vector2(-40, 6)
	tp.x = clampf(tp.x, 8.0, size.x - 140.0)
	tp.y = clampf(tp.y, 24.0, size.y - 8.0)
	_overlay.draw_string_outline(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color(0, 0, 0, 0.8))
	_overlay.draw_string(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)


func _clear_messages() -> void:
	_banner_time = 0.0
	_banner.modulate.a = 0.0
	_toast_time = 0.0
	_toast.modulate.a = 0.0


func show_perk_choice(options: Array, salvage: int) -> void:
	_clear_messages()
	for c in _perk_box.get_children():
		c.queue_free()
	var title := Label.new()
	title.text = "ワープ成功！強化を1つ選んでください"
	if salvage > 0:
		title.text += "\n（置いていく採掘機を撤収：鉄 +%d）" % salvage
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	_perk_box.add_child(title)
	for p in options:
		var b := Button.new()
		b.text = "%s\n%s" % [p["name"], p["desc"]]
		b.custom_minimum_size = Vector2(0, 76)
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(_on_perk_pressed.bind(String(p["id"])))
		_perk_box.add_child(b)
	var skip := Button.new()
	skip.text = "受け取らずに燃料 +25"
	skip.custom_minimum_size = Vector2(0, 52)
	skip.add_theme_font_size_override("font_size", 18)
	skip.pressed.connect(_on_perk_pressed.bind(""))
	_perk_box.add_child(skip)
	_perk_panel.visible = true


func _on_perk_pressed(id: String) -> void:
	_perk_panel.visible = false
	main.on_perk_chosen(id)


func show_game_over(reason: String, victory: bool) -> void:
	_clear_messages()
	var gs := GameState
	var s := gs.score(victory)
	var head := "帰還成功！" if victory else "ゲームオーバー：%s" % reason
	var best := "自己ベスト更新！" if s >= gs.best_score else "自己ベスト %d" % gs.best_score
	_over_label.text = "%s\n到達セクター %d / %d\nスコア %d\n%s" % [head, gs.sector, gs.FINAL_SECTOR, s, best]
	_over_hint.visible = not _touch()
	_over_panel.visible = true


func hide_panels() -> void:
	_perk_panel.visible = false
	_over_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if _over_panel.visible and event is InputEventKey and event.pressed and event.physical_keycode == KEY_R:
		main.restart()
