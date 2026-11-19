extends CanvasLayer
## 画面表示（オートモード）。
## 常時：燃料・経験値バー、在庫、自動操縦の状況、生産ライン、速度とおまかせの切替。
## 選択画面：強化カード、航路、ゲームオーバー、母艦のスキルツリー。

var main: Node = null

var _overlay: Control
var _info: Label
var _status: Label
var _toast: Label
var _toast_time: float = 0.0
var _banner: Label
var _banner_time: float = 0.0
var _card_panel: PanelContainer
var _card_box: VBoxContainer
var _route_panel: PanelContainer
var _route_box: VBoxContainer
var _over_panel: PanelContainer
var _over_label: Label
var _over_hint: Label
var _ship_panel: PanelContainer
var _ship_box: VBoxContainer
var _speed_btn: Button
var _auto_btn: Button
var _buttons: HBoxContainer
var _backdrops: Array = []
var _card_cb: Callable
var _rerolled := false


var _theme: Theme


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_theme = _make_theme()

	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)

	_info = _make_label(17, Vector2(16, 70))
	_status = _make_label(16, Vector2.ZERO)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_toast = _make_label(20, Vector2.ZERO)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_banner = _make_label(34, Vector2.ZERO)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# 右下：速度とおまかせ
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 8)
	add_child(_buttons)
	_auto_btn = _small_button()
	_auto_btn.pressed.connect(func(): main.toggle_auto_pick())
	_buttons.add_child(_auto_btn)
	_speed_btn = _small_button()
	_speed_btn.pressed.connect(func(): main.toggle_speed())
	_buttons.add_child(_speed_btn)

	_card_panel = _make_panel()
	_card_box = VBoxContainer.new()
	_card_box.add_theme_constant_override("separation", 10)
	_card_panel.add_child(_card_box)

	_route_panel = _make_panel()
	_route_box = VBoxContainer.new()
	_route_box.add_theme_constant_override("separation", 10)
	_route_panel.add_child(_route_box)

	_over_panel = _make_panel()
	var over_box := VBoxContainer.new()
	over_box.add_theme_constant_override("separation", 16)
	_over_panel.add_child(over_box)
	_over_label = Label.new()
	_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_over_label.add_theme_font_size_override("font_size", 20)
	over_box.add_child(_over_label)
	var back := Button.new()
	back.text = "母艦へ戻る"
	back.custom_minimum_size = Vector2(0, 68)
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


func _box(bg: Color, border: Color, bw: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


## パネルとボタンの見た目（角丸・縁取り）。
func _make_theme() -> Theme:
	var th := Theme.new()
	th.set_stylebox("normal", "Button", _box(Color(0.08, 0.12, 0.2, 0.95), Color(0.35, 0.55, 0.8, 0.8)))
	th.set_stylebox("hover", "Button", _box(Color(0.12, 0.18, 0.3, 0.95), Color(0.55, 0.8, 1.0)))
	th.set_stylebox("pressed", "Button", _box(Color(0.2, 0.3, 0.45, 0.95), Color(0.8, 0.95, 1.0)))
	th.set_stylebox("disabled", "Button", _box(Color(0.06, 0.08, 0.12, 0.9), Color(0.3, 0.35, 0.45, 0.6)))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_disabled_color", "Button", Color(0.75, 0.8, 0.9, 0.85))
	var panel := _box(Color(0.02, 0.04, 0.09, 0.96), Color(0.3, 0.5, 0.75, 0.9), 2)
	panel.set_content_margin_all(14)
	th.set_stylebox("panel", "PanelContainer", panel)
	return th


func _make_label(font_size: int, pos: Vector2) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _small_button() -> Button:
	var b := Button.new()
	b.theme = _theme
	b.custom_minimum_size = Vector2(104, 58)
	b.add_theme_font_size_override("font_size", 18)
	b.focus_mode = Control.FOCUS_NONE
	return b


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
	panel.theme = _theme
	center.add_child(panel)
	panel.visible = false
	_backdrops.append([back, panel])
	return panel


func _touch() -> bool:
	return main != null and main.touch.active


func _size() -> Vector2:
	return _overlay.get_viewport().get_visible_rect().size


func any_panel() -> bool:
	return _card_panel.visible or _route_panel.visible or _over_panel.visible or _ship_panel.visible


func _panel_w() -> float:
	return minf(560.0, _size().x - 24.0)


## 画面サイズに合わせて配置を決める（毎フレーム呼んでも軽い）。
func _layout() -> void:
	var size := _size()
	var narrow := size.x < 700.0
	_info.position = Vector2(16, 70)
	var bsize := _buttons.get_combined_minimum_size()
	_buttons.position = Vector2(size.x - bsize.x - 14.0, size.y - bsize.y - 14.0)
	if narrow:
		# 縦持ち：状況表示はボタンの上に全幅で
		_status.size = Vector2(size.x - 32.0, 0)
		_status.position = Vector2(16, _buttons.position.y - _status.get_combined_minimum_size().y - 8.0)
	else:
		_status.size = Vector2(maxf(200.0, size.x - bsize.x - 60.0), 0)
		_status.position = Vector2(16, size.y - _status.get_combined_minimum_size().y - 14.0)

	_toast.size = Vector2(size.x - 40.0, 0)
	_toast.position = Vector2(20, size.y * (0.58 if narrow else 0.2))
	_banner.add_theme_font_size_override("font_size", 26 if narrow else 34)
	_banner.size = Vector2(size.x - 40.0, 0)
	_banner.position = Vector2(20, size.y * 0.3)

	var pw := _panel_w()
	_card_panel.custom_minimum_size = Vector2(pw, 0)
	_route_panel.custom_minimum_size = Vector2(pw, 0)
	_over_panel.custom_minimum_size = Vector2(pw, 0)
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
	var warp: PackedStringArray = []
	var cost := gs.warp_cost()
	for k in cost:
		warp.append("%s %d/%d" % [gs.ITEMS[k]["short"], mini(gs.count(k), int(cost[k])), int(cost[k])])
	var warp_line := "ワープ準備：" + "  ".join(warp)
	if main != null and main.route_gate != null:
		warp_line = "ワープ準備：完了（ゲートへ移動中）"
	elif gs.can_afford(cost):
		warp_line = "ワープ準備：完了"
	_info.text = "\n".join([
		"セクター %d/%d  %s" % [gs.sector, gs.FINAL_SECTOR, info["name"]],
		"  ".join(raw),
		"  ".join(made),
		warp_line,
	])

	_info.visible = not _ship_panel.visible
	var running: bool = main != null and gs.alive and not any_panel()
	_status.visible = running
	_buttons.visible = running
	if running:
		_status.text = "自動操縦：%s\n%s" % [main.player.status, _line_text()]
		_speed_btn.text = "速度 ×%d" % int(main.speed())
		_auto_btn.text = "おまかせ\n%s" % ("ON" if main.auto_pick else "OFF")
		_auto_btn.add_theme_font_size_override("font_size", 15)
		_auto_btn.modulate = Color(1.0, 0.9, 0.5) if main.auto_pick else Color.WHITE

	if _toast_time > 0.0:
		_toast_time -= delta / maxf(Engine.time_scale, 0.01)
		_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)
	if _banner_time > 0.0:
		_banner_time -= delta / maxf(Engine.time_scale, 0.01)
		_banner.modulate.a = clampf(_banner_time, 0.0, 1.0)
	_overlay.queue_redraw()


func _line_text() -> String:
	var parts: PackedStringArray = []
	parts.append("採掘機 %d/%d" % [main.built_count("miner"), GameState.miner_cap])
	for b in ["hub", "smelter", "wiremill", "assembler", "quantum"]:
		var n: int = main.built_count(b)
		if n > 0:
			parts.append("%s×%d" % [GameState.BUILDINGS[b]["name"], n])
	return "  ".join(parts)


func toast(text: String, duration: float = 2.5) -> void:
	_toast.text = text
	_toast_time = duration


func banner(title: String, sub: String) -> void:
	_banner.text = title if sub == "" else "%s\n%s" % [title, sub]
	_banner_time = 3.0


func _bar(rect: Rect2, frac: float, col: Color, label: String, font: Font) -> void:
	_overlay.draw_rect(rect, Color(0, 0, 0, 0.5))
	_overlay.draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(frac, 0.0, 1.0), rect.size.y)), col)
	_overlay.draw_rect(rect, Color(1, 1, 1, 0.5), false, 2.0)
	var fs := 16 if rect.size.y >= 22.0 else 13
	var tp := rect.position + Vector2(8, rect.size.y * 0.5 + fs * 0.36)
	_overlay.draw_string_outline(font, tp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.8))
	_overlay.draw_string(font, tp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _draw_overlay() -> void:
	var size := _overlay.size
	var font := _overlay.get_theme_default_font()
	var gs := GameState
	var t := Time.get_ticks_msec() * 0.001
	var narrow := size.x < 700.0
	if _ship_panel.visible:
		return

	# 燃料バー
	var frac := gs.fuel / gs.max_fuel
	var w := minf(420.0, size.x - 32.0 if narrow else size.x * 0.35)
	var col := Color(0.4, 0.85, 1.0)
	if frac < 0.15:
		col = Color(1.0, 0.25, 0.2).lerp(Color(1, 1, 1), 0.3 * (0.5 + 0.5 * sin(t * 12.0)))
	elif frac < 0.3:
		col = Color(1.0, 0.8, 0.2)
	var burn: float = (Player.IDLE_BURN + 0.45) * gs.fuel_burn_mult * gs.instability()
	var secs := int(gs.fuel / maxf(burn, 0.01))
	_bar(Rect2(16, 12, w, 24), frac, col, "燃料 %d/%d  残り約%d秒" % [int(gs.fuel), int(gs.max_fuel), secs], font)
	# 経験値バー（生産するとたまる）
	_bar(Rect2(16, 40, w, 18), gs.xp / gs.xp_needed(), Color(0.55, 1.0, 0.55), "Lv %d  次の強化まで %d%%" % [gs.level, int(100.0 * (1.0 - gs.xp / gs.xp_needed()))], font)

	# 不安定化（バーの右、狭い画面では在庫の下）
	var inst := gs.instability()
	var ipos := Vector2(size.x - 200.0, 30) if not narrow else Vector2(size.x - 170.0, 86)
	var txt := "安定 残り%d秒" % int(gs.instability_grace - gs.sector_time)
	var c := Color(1, 1, 1, 0.6)
	if inst > 1.0:
		txt = "不安定化 ×%.1f" % inst
		c = Color(1.0, 0.4, 0.3).lerp(Color.WHITE, 0.3 * (0.5 + 0.5 * sin(t * 6.0)))
	_overlay.draw_string_outline(font, ipos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, 4, Color(0, 0, 0, 0.8))
	_overlay.draw_string(font, ipos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, c)

	if main == null or not gs.alive:
		return

	if frac < 0.15:
		var a := 0.25 + 0.2 * sin(t * 8.0)
		for i in 6:
			var ew := 6.0 + i * 6.0
			var cc := Color(1.0, 0.1, 0.1, a * (1.0 - i / 6.0) * 0.5)
			_overlay.draw_rect(Rect2(0, 0, size.x, ew), cc)
			_overlay.draw_rect(Rect2(0, size.y - ew, size.x, ew), cc)
			_overlay.draw_rect(Rect2(0, 0, ew, size.y), cc)
			_overlay.draw_rect(Rect2(size.x - ew, 0, ew, size.y), cc)

	# 方向ガイド：見つけたゲートと母船
	var xf: Transform2D = _overlay.get_viewport().get_canvas_transform()
	var ppos: Vector2 = main.player.global_position
	for g in main.gates:
		if g.discovered:
			var label := "ゲート %dm" % int(ppos.distance_to(g.global_position))
			if g == main.route_gate:
				label = "目的地 %dm" % int(ppos.distance_to(g.global_position))
			_edge_arrow(xf * g.global_position, g.color(), label, size, font)
	_edge_arrow(xf * main.core.global_position, Color(0.5, 0.8, 1.0), "母船", size, font)


func _edge_arrow(screen_pos: Vector2, col: Color, text: String, size: Vector2, font: Font) -> void:
	var margin := 56.0
	if Rect2(Vector2.ZERO, size).grow(-24.0).has_point(screen_pos):
		return
	var rect := Rect2(Vector2(margin, margin + 120), size - Vector2(margin * 2, margin * 2 + 240))
	var center := rect.get_center()
	var dir := (screen_pos - center).normalized()
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
	_overlay.draw_string_outline(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.8))
	_overlay.draw_string(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)


func _clear_messages() -> void:
	_banner_time = 0.0
	_banner.modulate.a = 0.0
	_toast_time = 0.0
	_toast.modulate.a = 0.0


func _wide_button(text: String, h: float, font_size: int, w: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	# 折り返しには幅が要る（幅0だと1文字ずつ折り返して縦に伸びる）
	b.custom_minimum_size = Vector2(w if w > 0.0 else _panel_w() - 16.0, h)
	b.add_theme_font_size_override("font_size", font_size)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.focus_mode = Control.FOCUS_NONE
	return b


func _title(box: VBoxContainer, text: String, font_size: int = 22) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.custom_minimum_size = Vector2(_panel_w() - 16.0, 0)
	box.add_child(l)
	return l


# ---------------------------------------------------------------- 強化カード


## カードを並べて1枚選ばせる。callback(id) を呼ぶ（skip_text の選択肢は id ""）。
func show_cards(title: String, options: Array, skip_text: String, callback: Callable, can_reroll: bool) -> void:
	_card_cb = callback
	_rerolled = not can_reroll
	_build_cards(title, options, skip_text)


func _build_cards(title: String, options: Array, skip_text: String) -> void:
	_clear_messages()
	for c in _card_box.get_children():
		c.queue_free()
	_title(_card_box, title)
	var size := _size()
	var cols := 2 if size.y < 600.0 and options.size() > 2 else 1
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_card_box.add_child(grid)
	var inner := _panel_w() - 16.0
	var bw := (inner - 8.0 * (cols - 1)) / cols
	for p in options:
		var b := _wide_button("%s\n%s" % [p["name"], p["desc"]], 70, 18, bw)
		b.pressed.connect(_on_card_pressed.bind(String(p["id"])))
		grid.add_child(b)
	if not _rerolled:
		var rr := _wide_button("引き直す（スキル：再抽選）", 48, 17)
		rr.pressed.connect(func():
			_rerolled = true
			_build_cards(title, GameState.roll_cards(options.size()), skip_text))
		_card_box.add_child(rr)
	if skip_text != "":
		var skip := _wide_button(skip_text, 48, 17)
		skip.pressed.connect(_on_card_pressed.bind(""))
		_card_box.add_child(skip)
	_card_panel.visible = true


func _on_card_pressed(id: String) -> void:
	_card_panel.visible = false
	_card_cb.call(id)


# ---------------------------------------------------------------- 航路


func show_routes(found: Array) -> void:
	_clear_messages()
	for c in _route_box.get_children():
		c.queue_free()
	var gs := GameState
	_title(_route_box, "ワープの準備ができた！\n行き先を選ぶ")
	var note := _title(_route_box, "選ぶとワープ資源（%s）を積み込み、自動でゲートへ向かいます" % gs.cost_text(gs.warp_cost()), 15)
	note.modulate = Color(1, 1, 1, 0.7)
	var ppos: Vector2 = main.player.position
	for g in found:
		var gate := g as WarpGate
		var dist := int(ppos.distance_to(gate.position))
		var text := ""
		if gs.is_final_sector():
			text = "最終ゲート：帰還する\n距離 %dm" % dist
		else:
			var kind := "遠方ゲート（報酬大）" if gate.rich else "近いゲート"
			var info: Dictionary = SectorGenerator.TYPES[gate.next_type]
			var desc := String(info["desc"])
			text = "%s → %s\n強化%d択・距離 %dm%s" % [kind, info["name"], gate.perk_count(), dist, ("\n" + desc) if desc != "" else ""]
		var b := _wide_button(text, 80, 17)
		if gate.rich:
			b.modulate = Color(1.0, 0.92, 0.75)
		b.pressed.connect(func(): main.on_route_chosen(gate))
		_route_box.add_child(b)
	if found.size() < main.gates.size() and not gs.is_final_sector():
		var hint := _title(_route_box, "まだ見つかっていないゲートがあります", 14)
		hint.modulate = Color(1, 1, 1, 0.6)
	var wait := _wide_button("もう少し探索して資源を貯める（%d秒後にまた聞く）" % int(main.ROUTE_SNOOZE), 52, 16)
	wait.pressed.connect(func(): main.on_route_chosen(null))
	_route_box.add_child(wait)
	_route_panel.visible = true


## 量子コアが作れずワープできないときの案内。
func show_blocked() -> void:
	_clear_messages()
	for c in _route_box.get_children():
		c.queue_free()
	_title(_route_box, "この先のワープには量子コアが必要")
	var note := _title(_route_box, "母艦のスキル「量子炉の設計図」を覚えると、量子炉のカードが出るようになります。いま帰還しても研究データは持ち帰れます。", 15)
	note.modulate = Color(1, 1, 1, 0.75)
	var back := _wide_button("母艦へ帰還する", 56, 19)
	back.pressed.connect(func(): main.retreat())
	_route_box.add_child(back)
	var go := _wide_button("このまま続ける（燃料が尽きるまで生産）", 52, 16)
	go.pressed.connect(func(): main.keep_going())
	_route_box.add_child(go)
	_route_panel.visible = true


# ---------------------------------------------------------------- ゲームオーバー


func show_game_over(reason: String, victory: bool) -> void:
	_clear_messages()
	hide_panels()
	var gs := GameState
	var s := gs.score(victory)
	var head := "帰還成功！" if victory else ("母艦へ帰還しました" if reason == "母艦へ帰還" else "ゲームオーバー：%s" % reason)
	var best := "自己ベスト更新！" if s >= gs.best_score else "自己ベスト %d" % gs.best_score
	var made := "鉄板 %d・銅線 %d・回路 %d・量子コア %d" % [
		int(gs.produced.get("plate", 0.0)), int(gs.produced.get("wire", 0.0)),
		int(gs.produced.get("circuit", 0.0)), int(gs.produced.get("qcore", 0.0))]
	_over_label.text = "%s\n到達セクター %d / %d・Lv %d\nスコア %d（%s）\n生産：%s\n研究データ +%d（合計 %d）" % [
		head, gs.sector, gs.FINAL_SECTOR, gs.level, s, best, made, gs.last_data_gain, gs.data_points]
	_over_hint.visible = not _touch()
	_over_panel.visible = true


# ---------------------------------------------------------------- 母艦（スキルツリー）


func show_mothership() -> void:
	_clear_messages()
	hide_panels()
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
	sub.text = "遠征は自動で進みます。研究データでスキルを覚え、生産を効率化して奥のセクターへ。最高到達 %d・自己ベスト %d" % [gs.best_sector, gs.best_score]
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(panel_w - 16.0, 0)
	sub.add_theme_font_size_override("font_size", 14)
	sub.modulate = Color(1, 1, 1, 0.7)
	_ship_box.add_child(sub)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(panel_w - 16.0, clampf(size.y - 230.0, 150.0, 640.0))
	_ship_box.add_child(scroll)
	var tree := VBoxContainer.new()
	tree.add_theme_constant_override("separation", 6)
	scroll.add_child(tree)
	var cols := 3
	var bw := (panel_w - 16.0 - 14.0 - 6.0 * (cols - 1)) / cols
	var narrow := bw < 200.0
	var tier := 0
	var row: HBoxContainer = null
	for s in gs.SKILLS:
		if int(s["tier"]) != tier:
			tier = int(s["tier"])
			var tl := Label.new()
			tl.text = "段階 %d" % tier
			tl.add_theme_font_size_override("font_size", 14)
			tl.modulate = Color(0.7, 0.85, 1.0)
			tree.add_child(tl)
			row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			tree.add_child(row)
		var id := String(s["id"])
		var owned := gs.has_skill(id)
		var open := gs.skill_available(id)
		var tag := ""
		if owned:
			tag = "習得済み"
		elif not open:
			tag = "要：%s" % gs.skill_def(String(s["req"]))["name"]
		else:
			tag = "データ %d" % int(s["cost"])
		var b := _wide_button("%s\n%s\n%s" % [s["name"], s["desc"], tag], 96 if narrow else 84, 13 if narrow else 15, bw)
		b.disabled = owned or not open or gs.data_points < int(s["cost"])
		if owned:
			b.modulate = Color(0.6, 1.0, 0.7)
		elif not open:
			b.modulate = Color(1, 1, 1, 0.45)
		b.pressed.connect(func():
			if gs.buy_skill(id):
				show_mothership())
		row.add_child(b)
	var go := _wide_button("出撃する", 62, 26, panel_w - 16.0)
	go.pressed.connect(func(): main.launch_run())
	_ship_box.add_child(go)
	_ship_panel.visible = true


func hide_panels() -> void:
	_card_panel.visible = false
	_route_panel.visible = false
	_over_panel.visible = false
	_ship_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if _over_panel.visible and event is InputEventKey and event.pressed and event.physical_keycode == KEY_R:
		main.open_mothership()
