extends CanvasLayer
## 画面表示。燃料バー、在庫、目標、建設、方向ガイド、メッセージ、パーク選択、ゲームオーバー、母艦。
## スマホ（タッチ）では縦持ち・横持ちに合わせて配置を組み替える。

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
var _build_bar: HBoxContainer
var _build_buttons := {}
var _menu_panel: PanelContainer
var _menu_grid: GridContainer
var _menu_buttons := {}
var _ship_panel: PanelContainer
var _ship_box: VBoxContainer
var _backdrops: Array = []
var _top_offset: float = 52.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)

	_info = _make_label(19, Vector2(20, 52))
	_goal = _make_label(20, Vector2.ZERO)
	_goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_goal.modulate = Color(1.0, 0.95, 0.7)

	_help = _make_label(15, Vector2.ZERO)
	_help.text = "WASD:移動  左クリック長押し:採掘  1〜6:建設  右クリック:取消  E:ワープ"
	_help.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_help.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_help.offset_right = -16
	_help.offset_top = 12
	_help.modulate = Color(1, 1, 1, 0.55)

	_toast = _make_label(22, Vector2.ZERO)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_banner = _make_label(36, Vector2.ZERO)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# 建設バー（PC用、画面下中央）
	_build_bar = HBoxContainer.new()
	_build_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_build_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_build_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_build_bar.offset_bottom = -10
	_build_bar.add_theme_constant_override("separation", 6)
	add_child(_build_bar)
	for b in GameState.BUILD_ORDER:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(118, 88)
		btn.add_theme_font_size_override("font_size", 17)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(func(): main.toggle_placing(b))
		_build_bar.add_child(btn)
		_build_buttons[b] = btn

	# 建設メニュー（スマホ用）
	_menu_panel = _make_panel()
	var menu_box := VBoxContainer.new()
	menu_box.add_theme_constant_override("separation", 10)
	_menu_panel.add_child(menu_box)
	var menu_title := Label.new()
	menu_title.text = "建設"
	menu_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_title.add_theme_font_size_override("font_size", 24)
	menu_box.add_child(menu_title)
	_menu_grid = GridContainer.new()
	_menu_grid.add_theme_constant_override("h_separation", 8)
	_menu_grid.add_theme_constant_override("v_separation", 8)
	menu_box.add_child(_menu_grid)
	for b in GameState.BUILD_ORDER:
		var mb := Button.new()
		mb.add_theme_font_size_override("font_size", 18)
		mb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		mb.focus_mode = Control.FOCUS_NONE
		mb.pressed.connect(func():
			_menu_panel.visible = false
			main.toggle_placing(b))
		_menu_grid.add_child(mb)
		_menu_buttons[b] = mb
	var close := Button.new()
	close.text = "閉じる"
	close.custom_minimum_size = Vector2(0, 60)
	close.add_theme_font_size_override("font_size", 20)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func(): _menu_panel.visible = false)
	menu_box.add_child(close)

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
	_over_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_over_label.add_theme_font_size_override("font_size", 22)
	over_box.add_child(_over_label)
	var back := Button.new()
	back.text = "母艦へ戻る"
	back.custom_minimum_size = Vector2(0, 72)
	back.add_theme_font_size_override("font_size", 24)
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(func(): main.open_mothership())
	over_box.add_child(back)
	_over_hint = Label.new()
	_over_hint.text = "（Rキーでも戻れます）"
	_over_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_hint.modulate = Color(1, 1, 1, 0.6)
	over_box.add_child(_over_hint)

	_ship_panel = _make_panel()
	_ship_box = VBoxContainer.new()
	_ship_box.add_theme_constant_override("separation", 8)
	_ship_panel.add_child(_ship_box)


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
	var back := ColorRect.new()
	back.color = Color(0.0, 0.01, 0.04, 0.7)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.visible = false
	add_child(back)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	panel.visible = false
	_backdrops.append([back, panel])
	return panel


func _touch() -> bool:
	return main != null and main.touch.active


func _size() -> Vector2:
	return _overlay.get_viewport().get_visible_rect().size


func _narrow() -> bool:
	return _size().x < 700.0


func any_panel() -> bool:
	return _any_panel()


func _any_panel() -> bool:
	return _perk_panel.visible or _over_panel.visible or _ship_panel.visible or _menu_panel.visible


## 画面座標が UI（建設バーやパネル）の上か。
func is_over_ui(screen_pos: Vector2) -> bool:
	if _any_panel():
		return true
	return _build_bar.visible and _build_bar.get_global_rect().grow(6.0).has_point(screen_pos)


func pointer_over_ui() -> bool:
	return is_over_ui(_overlay.get_viewport().get_mouse_position())


func toggle_build_menu() -> void:
	if not GameState.alive:
		return
	_menu_panel.visible = not _menu_panel.visible
	if _menu_panel.visible:
		_clear_messages()


## 画面サイズと入力方法に合わせて配置を決める（毎フレーム呼んでも軽い）。
func _layout() -> void:
	var size := _size()
	var mobile := _touch()
	var narrow := size.x < 700.0
	_top_offset = 74.0 if narrow else 52.0
	_info.position = Vector2(16, _top_offset)
	_info.add_theme_font_size_override("font_size", 17 if mobile else 19)
	_help.visible = not mobile

	var info_bottom := _top_offset + _info.get_combined_minimum_size().y
	if mobile:
		_goal.position = Vector2(16, info_bottom + 2)
		_goal.size = Vector2(minf(size.x - 32.0, 560.0), 0)
		_goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	else:
		_goal.size = Vector2(size.x - 40.0, 0)
		_goal.position = Vector2(20, size.y - 140)
		_goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_toast.add_theme_font_size_override("font_size", 19 if mobile else 22)
	if mobile and narrow:
		_toast.size = Vector2(size.x - 40.0, 0)
		_toast.position = Vector2(20, size.y * 0.6)
	elif mobile:
		# 横持ち：スティックとボタンの間、画面下寄り
		_toast.size = Vector2(maxf(200.0, size.x - 420.0), 0)
		_toast.position = Vector2((size.x - _toast.size.x) * 0.5, size.y - 120.0)
	else:
		_toast.size = Vector2(size.x - 40.0, 0)
		_toast.position = Vector2(20, size.y * 0.16)
	_banner.add_theme_font_size_override("font_size", 26 if narrow else 36)
	_banner.size = Vector2(size.x - 40.0, 0)
	_banner.position = Vector2(20, size.y * 0.28)

	var panel_w := minf(560.0, size.x - 24.0)
	_perk_panel.custom_minimum_size = Vector2(panel_w, 0)
	_over_panel.custom_minimum_size = Vector2(panel_w, 0)
	_menu_panel.custom_minimum_size = Vector2(minf(640.0, size.x - 24.0), 0)
	var cols := 2 if size.x < 700.0 else 3
	_menu_grid.columns = cols
	var bw := (minf(640.0, size.x - 24.0) - 16.0 - 8.0 * (cols - 1)) / cols
	for b in _menu_buttons:
		(_menu_buttons[b] as Button).custom_minimum_size = Vector2(bw, 84)
	_ship_panel.custom_minimum_size = Vector2(minf(940.0, size.x - 24.0), 0)


func _process(delta: float) -> void:
	for pair in _backdrops:
		pair[0].visible = pair[1].visible
	_layout()
	var gs := GameState
	var info: Dictionary = SectorGenerator.TYPES[gs.sector_type]
	var raw: PackedStringArray = []
	for k in gs.RAW_ITEMS:
		raw.append("%s %d" % [gs.ITEMS[k]["short"], gs.count(k)])
	var made: PackedStringArray = []
	for k in gs.MADE_ITEMS:
		made.append("%s %d" % [gs.ITEMS[k]["short"], gs.count(k)])
	var lines: PackedStringArray = [
		"セクター %d/%d  %s" % [gs.sector, gs.FINAL_SECTOR, info["name"]],
		"  ".join(raw),
		"  ".join(made),
		"ワープ：%s" % gs.cost_text(gs.warp_cost()),
	]
	_info.text = "\n".join(lines)
	_goal.text = main.next_step() if main != null and gs.alive and not _any_panel() else ""
	_build_bar.visible = gs.alive and not _any_panel() and not _touch()
	_update_build_buttons()

	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)
	if _banner_time > 0.0:
		_banner_time -= delta
		_banner.modulate.a = clampf(_banner_time, 0.0, 1.0)
	_overlay.queue_redraw()


func _build_sub(b: String) -> String:
	if not GameState.building_unlocked(b):
		return "未研究"
	var kits := GameState.kit_count(b)
	if kits > 0:
		return "キット×%d" % kits
	var parts: PackedStringArray = []
	var cost: Dictionary = GameState.BUILDINGS[b]["cost"]
	for k in cost:
		parts.append("%s%d" % [GameState.ITEMS[k]["short"], int(cost[k])])
	return " ".join(parts)


func _update_build_buttons() -> void:
	if main == null:
		return
	for b in GameState.BUILD_ORDER:
		var def: Dictionary = GameState.BUILDINGS[b]
		var can: bool = main.can_start_placing(b)
		var sub := _build_sub(b)
		var btn: Button = _build_buttons[b]
		btn.text = "%s\n%s" % [def["name"], sub]
		btn.modulate = Color(1, 1, 1, 1.0 if can else 0.45)
		if main.placing == b:
			btn.modulate = Color(1.0, 0.9, 0.4)
		if _menu_panel.visible:
			var mb: Button = _menu_buttons[b]
			mb.text = "%s（%s）\n%s" % [def["name"], sub, def["desc"]]
			mb.modulate = Color(1, 1, 1, 1.0 if can else 0.45)


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
	var narrow := size.x < 700.0

	# 燃料バー
	var frac := gs.fuel / gs.max_fuel
	var bar := Rect2(16, 14, minf(420.0, size.x - 32.0 if narrow else size.x * 0.35), 26)
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
	_overlay.draw_string_outline(font, bar.position + Vector2(10, 20), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, 4, Color(0, 0, 0, 0.8))
	_overlay.draw_string(font, bar.position + Vector2(10, 20), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)

	# 不安定化（狭い画面ではバーの下に出す）
	var inst := gs.instability()
	var ipos := Vector2(16, bar.end.y + 24) if narrow else Vector2(bar.end.x + 16, 36)
	if inst > 1.0:
		var txt := "不安定化 ×%.1f" % inst
		var c := Color(1.0, 0.4, 0.3).lerp(Color.WHITE, 0.3 * (0.5 + 0.5 * sin(t * 6.0)))
		_overlay.draw_string_outline(font, ipos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, 4, Color(0, 0, 0, 0.8))
		_overlay.draw_string(font, ipos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, c)
	else:
		var left := int(gs.instability_grace - gs.sector_time)
		_overlay.draw_string(font, ipos, "安定 残り%d秒" % left, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(1, 1, 1, 0.6))

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


func _wide_button(text: String, h: float, font_size: int, w: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	# 折り返しには幅が要る（幅0だと1文字ずつ折り返して縦に伸びる）
	b.custom_minimum_size = Vector2(w if w > 0.0 else minf(560.0, _size().x - 24.0) - 16.0, h)
	b.add_theme_font_size_override("font_size", font_size)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.focus_mode = Control.FOCUS_NONE
	return b


func show_perk_choice(options: Array, packed: int) -> void:
	_clear_messages()
	_menu_panel.visible = false
	for c in _perk_box.get_children():
		c.queue_free()
	var title := Label.new()
	title.text = "ワープ成功！強化を1つ選んでください"
	if packed > 0:
		title.text += "\n（建物 %d 個を畳んで積み込みました）" % packed
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 22)
	title.custom_minimum_size = Vector2(minf(560.0, _size().x - 24.0) - 16.0, 0)
	_perk_box.add_child(title)
	var size := _size()
	var cols := 2 if size.y < 600.0 and options.size() > 2 else 1
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_perk_box.add_child(grid)
	var inner := minf(560.0, size.x - 24.0) - 16.0
	var bw := (inner - 8.0 * (cols - 1)) / cols
	for p in options:
		var b := _wide_button("%s\n%s" % [p["name"], p["desc"]], 72, 18, bw)
		b.pressed.connect(_on_perk_pressed.bind(String(p["id"])))
		grid.add_child(b)
	var skip := _wide_button("受け取らずに燃料 +25", 52, 18)
	skip.pressed.connect(_on_perk_pressed.bind(""))
	_perk_box.add_child(skip)
	_perk_panel.visible = true


func _on_perk_pressed(id: String) -> void:
	_perk_panel.visible = false
	main.on_perk_chosen(id)


func show_game_over(reason: String, victory: bool) -> void:
	_clear_messages()
	_menu_panel.visible = false
	var gs := GameState
	var s := gs.score(victory)
	var head := "帰還成功！" if victory else "ゲームオーバー：%s" % reason
	var best := "自己ベスト更新！" if s >= gs.best_score else "自己ベスト %d" % gs.best_score
	var made := "鉄板 %d・銅線 %d・回路 %d・量子コア %d" % [
		int(gs.produced.get("plate", 0.0)), int(gs.produced.get("wire", 0.0)),
		int(gs.produced.get("circuit", 0.0)), int(gs.produced.get("qcore", 0.0))]
	_over_label.text = "%s\n到達セクター %d / %d\nスコア %d（%s）\n生産：%s\n研究データ +%d（合計 %d）" % [
		head, gs.sector, gs.FINAL_SECTOR, s, best, made, gs.last_data_gain, gs.data_points]
	_over_hint.visible = not _touch()
	_over_panel.visible = true


func show_mothership() -> void:
	_clear_messages()
	_perk_panel.visible = false
	_over_panel.visible = false
	_menu_panel.visible = false
	_layout()
	for c in _ship_box.get_children():
		c.queue_free()
	var gs := GameState
	var size := _size()
	var panel_w := minf(940.0, size.x - 24.0)
	var title := Label.new()
	title.text = "母艦　研究データ %d" % gs.data_points
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	_ship_box.add_child(title)
	var sub := Label.new()
	sub.text = "研究データで技術を解放し、より奥のセクターを目指そう。最高到達 %d・自己ベスト %d" % [gs.best_sector, gs.best_score]
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(panel_w - 16.0, 0)
	sub.add_theme_font_size_override("font_size", 15)
	sub.modulate = Color(1, 1, 1, 0.7)
	_ship_box.add_child(sub)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(panel_w - 16.0, clampf(size.y - 210.0, 150.0, 430.0))
	_ship_box.add_child(scroll)
	var grid := GridContainer.new()
	var cols := 1 if size.x < 560.0 else (2 if size.x < 1000.0 else 3)
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	var bw := (panel_w - 16.0 - 12.0 - 8.0 * (cols - 1)) / cols
	for r in gs.RESEARCH:
		var id := String(r["id"])
		var owned := gs.has_research(id)
		var tag := "解放済み" if owned else "データ %d" % int(r["cost"])
		var b := _wide_button("%s（%s）\n%s" % [r["name"], tag, r["desc"]], 70, 16, bw)
		b.disabled = owned or gs.data_points < int(r["cost"])
		if owned:
			b.modulate = Color(0.6, 1.0, 0.7)
		b.pressed.connect(func():
			if gs.buy_research(id):
				show_mothership())
		grid.add_child(b)
	var go := _wide_button("出撃する", 64, 26, panel_w - 16.0)
	go.pressed.connect(func(): main.launch_run())
	_ship_box.add_child(go)
	_ship_panel.visible = true


func hide_panels() -> void:
	_perk_panel.visible = false
	_over_panel.visible = false
	_ship_panel.visible = false
	_menu_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if _over_panel.visible and event is InputEventKey and event.pressed and event.physical_keycode == KEY_R:
		main.open_mothership()
