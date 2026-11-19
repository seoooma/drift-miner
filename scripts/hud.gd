extends CanvasLayer
## 画面表示。上：所持クレジットと惑星の進み具合。中：惑星（タップで手掘り）。
## 下：採掘ツールの一覧（Lv・毎秒ダメージ・強化ボタン）。
## パネル：強化カード、スキル、帰還、ラン中のカード、放置報酬。

const BUY_MODES := [1, 10, 0]  # 0 = 買えるだけ

var main: Node = null

var _theme: Theme
var _overlay: Control
var _data_label: Label
var _credit_label: Label
var _rate_label: Label
var _planet_label: Label
var _toast: Label
var _toast_time: float = 0.0
var _banner: Label
var _banner_time: float = 0.0
var _side: VBoxContainer
var _tool_panel: PanelContainer
var _tool_rows := {}
var _buy_btn: Button
var _buy_mode: int = 0
var _panels: Array = []
var _backdrops: Array = []
var _card_panel: PanelContainer
var _card_box: VBoxContainer
var _skill_panel: PanelContainer
var _skill_box: VBoxContainer
var _msg_panel: PanelContainer
var _msg_box: VBoxContainer
var _top_h: float = 112.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_theme = _make_theme()

	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)

	_data_label = _make_label(18)
	_data_label.modulate = Color(0.75, 0.9, 1.0)
	_credit_label = _make_label(30)
	_credit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rate_label = _make_label(15)
	_rate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rate_label.modulate = Color(1.0, 0.75, 0.4)
	_planet_label = _make_label(14)
	_planet_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_side = VBoxContainer.new()
	_side.add_theme_constant_override("separation", 8)
	add_child(_side)
	for spec in [["スキル", _open_skills], ["カード", _open_run_cards], ["帰還", _open_prestige]]:
		var b := _button(spec[0], Vector2(70, 44), 15)
		b.pressed.connect(spec[1])
		_side.add_child(b)

	_build_tool_panel()

	_toast = _make_label(18)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner = _make_label(28)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_card_panel = _make_panel()
	_card_box = _panel_box(_card_panel)
	_skill_panel = _make_panel()
	_skill_box = _panel_box(_skill_panel)
	_msg_panel = _make_panel()
	_msg_box = _panel_box(_msg_panel)


# ---------------------------------------------------------------- 部品


func _box(bg: Color, border: Color, bw: int = 2, radius: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


func _make_theme() -> Theme:
	var th := Theme.new()
	th.set_stylebox("normal", "Button", _box(Color(0.05, 0.07, 0.1, 0.95), Color(0.4, 0.75, 0.9, 0.85)))
	th.set_stylebox("hover", "Button", _box(Color(0.08, 0.12, 0.18, 0.95), Color(0.6, 0.9, 1.0)))
	th.set_stylebox("pressed", "Button", _box(Color(0.15, 0.25, 0.32, 0.95), Color(0.85, 1.0, 1.0)))
	th.set_stylebox("disabled", "Button", _box(Color(0.04, 0.05, 0.07, 0.9), Color(0.3, 0.35, 0.4, 0.6)))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_disabled_color", "Button", Color(0.6, 0.65, 0.7))
	var panel := _box(Color(0.03, 0.04, 0.06, 0.97), Color(0.45, 0.85, 0.6), 3, 14)
	panel.set_content_margin_all(14)
	th.set_stylebox("panel", "PanelContainer", panel)
	return th


func _make_label(font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _button(text: String, min_size: Vector2, font_size: int) -> Button:
	var b := Button.new()
	b.theme = _theme
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", font_size)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _make_panel() -> PanelContainer:
	var back := ColorRect.new()
	back.color = Color(0.0, 0.0, 0.02, 0.72)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	_panels.append(panel)
	return panel


func _panel_box(panel: PanelContainer) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	return box


func _clear(box: Container) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _size() -> Vector2:
	return _overlay.get_viewport().get_visible_rect().size


func _panel_w() -> float:
	return minf(520.0, _size().x - 24.0)


func _title(box: Container, text: String, font_size: int = 22, col: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.custom_minimum_size = Vector2(_panel_w() - 28.0, 0)
	l.modulate = col
	box.add_child(l)
	return l


func _wide(box: Container, text: String, h: float, font_size: int) -> Button:
	var b := _button(text, Vector2(_panel_w() - 28.0, h), font_size)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(b)
	return b


func any_panel() -> bool:
	for p in _panels:
		if p.visible:
			return true
	return false


func hide_panels() -> void:
	for p in _panels:
		p.visible = false


func toast(text: String, duration: float = 2.5) -> void:
	_toast.text = text
	_toast_time = duration


func banner(title: String, sub: String) -> void:
	_banner.text = title if sub == "" else "%s\n%s" % [title, sub]
	_banner_time = 2.5


# ---------------------------------------------------------------- ツール一覧


func _build_tool_panel() -> void:
	_tool_panel = PanelContainer.new()
	_tool_panel.theme = _theme
	var sb := _box(Color(0.02, 0.03, 0.05, 0.96), Color(0.9, 0.55, 0.25, 0.9), 2, 4)
	sb.set_content_margin_all(8)
	_tool_panel.add_theme_stylebox_override("panel", sb)
	add_child(_tool_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_tool_panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := Label.new()
	t.text = "採掘ツール"
	t.add_theme_font_size_override("font_size", 17)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	_buy_btn = _button("", Vector2(96, 34), 15)
	_buy_btn.pressed.connect(func(): _buy_mode = (_buy_mode + 1) % BUY_MODES.size())
	head.add_child(_buy_btn)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for td in GameState.TOOLS:
		var id := String(td["id"])
		var col: Color = td["color"]
		var row := PanelContainer.new()
		var rs := _box(Color(0.04, 0.05, 0.07), Color(col, 0.75), 2, 3)
		rs.set_content_margin_all(8)
		row.add_theme_stylebox_override("panel", rs)
		list.add_child(row)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		row.add_child(h)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 2)
		h.add_child(info)
		var top := HBoxContainer.new()
		info.add_child(top)
		var name := Label.new()
		name.add_theme_font_size_override("font_size", 16)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(name)
		var dps := Label.new()
		dps.add_theme_font_size_override("font_size", 14)
		dps.modulate = Color(0.85, 0.9, 0.95)
		top.add_child(dps)
		var sub := Label.new()
		sub.add_theme_font_size_override("font_size", 13)
		sub.modulate = Color(1, 1, 1, 0.6)
		info.add_child(sub)
		var bar := Control.new()
		bar.custom_minimum_size = Vector2(0, 6)
		bar.draw.connect(func():
			var w := bar.size.x
			bar.draw_rect(Rect2(0, 0, w, 6), Color(1, 1, 1, 0.08))
			bar.draw_rect(Rect2(0, 0, w * GameState.milestone_frac(id), 6), col))
		info.add_child(bar)
		var btn := _button("", Vector2(104, 54), 15)
		btn.pressed.connect(_on_buy.bind(id))
		h.add_child(btn)
		_tool_rows[id] = {"name": name, "dps": dps, "sub": sub, "bar": bar, "btn": btn, "row": row}


func _buy_count(id: String) -> int:
	var mode: int = BUY_MODES[_buy_mode]
	if mode == 0:
		return maxi(1, GameState.affordable(id, 0))
	return mode


func _on_buy(id: String) -> void:
	var n := _buy_count(id)
	if GameState.buy_tool(id, n):
		var row: PanelContainer = _tool_rows[id]["row"]
		var tw := row.create_tween()
		row.modulate = Color(1.6, 1.6, 1.6)
		tw.tween_property(row, "modulate", Color.WHITE, 0.25)


func _update_tools() -> void:
	var gs := GameState
	var mode: int = BUY_MODES[_buy_mode]
	_buy_btn.text = "購入 ×%d" % mode if mode > 0 else "購入 最大"
	for td in gs.TOOLS:
		var id := String(td["id"])
		var r: Dictionary = _tool_rows[id]
		var lv := gs.tool_level(id)
		var n := _buy_count(id)
		var cost := gs.upgrade_cost(id, n)
		(r["name"] as Label).text = String(td["name"]) + ("  Lv %d" % lv if lv > 0 else "")
		(r["dps"] as Label).text = "毎秒 %s" % gs.fmt(gs.tool_dps(id)) if lv > 0 else ""
		if lv > 0:
			var gain := gs.tool_dps_at(id, lv + n) - gs.tool_dps(id)
			(r["sub"] as Label).text = "+%s／次の×2まで %d" % [gs.fmt(gain), 25 - lv % 25]
		else:
			(r["sub"] as Label).text = String(td["desc"])
		var btn: Button = r["btn"]
		btn.text = ("強化 ×%d\n%s" % [n, gs.fmt(cost)]) if lv > 0 else ("解放\n%s" % gs.fmt(cost))
		btn.disabled = cost > gs.credits
		(r["row"] as PanelContainer).modulate.a = 1.0 if lv > 0 or cost <= gs.credits * 4.0 else 0.55
		(r["bar"] as Control).queue_redraw()


# ---------------------------------------------------------------- 配置


func _portrait() -> bool:
	var s := _size()
	return s.y >= s.x


## 惑星を表示する画面上の領域（main.gd がカメラを合わせる）
func planet_area() -> Rect2:
	var s := _size()
	if _portrait():
		var bottom := _tool_panel.position.y - 6.0
		return Rect2(Vector2(0, _top_h), Vector2(s.x, maxf(120.0, bottom - _top_h)))
	return Rect2(Vector2(0, _top_h), Vector2(_tool_panel.position.x - 6.0, s.y - _top_h))


func _layout() -> void:
	var s := _size()
	_top_h = 112.0
	_data_label.position = Vector2(14, 10)
	_credit_label.position = Vector2(0, 6)
	_credit_label.size = Vector2(s.x, 0)
	_rate_label.position = Vector2(0, 46)
	_rate_label.size = Vector2(s.x, 0)
	_planet_label.size = Vector2(170, 0)
	_planet_label.position = Vector2(s.x - 184.0, 10)
	_side.position = Vector2(10, _top_h + 4.0)
	if _portrait():
		var ph := clampf(s.y * 0.44, 260.0, 520.0)
		_tool_panel.position = Vector2(8, s.y - ph - 8.0)
		_tool_panel.size = Vector2(s.x - 16.0, ph)
	else:
		var pw := clampf(s.x * 0.42, 360.0, 560.0)
		_tool_panel.position = Vector2(s.x - pw - 8.0, _top_h)
		_tool_panel.size = Vector2(pw, s.y - _top_h - 8.0)
	var area := planet_area()
	_toast.size = Vector2(area.size.x - 40.0, 0)
	_toast.position = Vector2(area.position.x + 20.0, area.end.y - 70.0)
	_banner.size = Vector2(area.size.x - 40.0, 0)
	_banner.position = Vector2(area.position.x + 20.0, area.position.y + area.size.y * 0.32)
	for p in _panels:
		(p as PanelContainer).custom_minimum_size = Vector2(_panel_w(), 0)


func _process(delta: float) -> void:
	for pair in _backdrops:
		pair[0].visible = pair[1].visible
	_layout()
	var gs := GameState
	_data_label.text = "◆ %s" % gs.fmt(gs.data)
	_credit_label.text = gs.fmt(gs.credits) + " CR"
	_rate_label.text = "毎秒 %s ダメージ" % gs.fmt(gs.total_dps())
	if main != null:
		var p: Planet = main.planet
		var lines := "銀河 %d・惑星 %d\n%d / %d" % [gs.galaxy(), gs.planet_in_galaxy(), p.broken(), p.needed()]
		if gs.is_boss():
			lines += "\n残り %d秒" % int(ceil(maxf(main.boss_left, 0.0)))
		_planet_label.text = lines
		_planet_label.modulate = Color(1.0, 0.55, 0.5) if gs.is_boss() else Color(0.85, 0.9, 1.0)
	_update_tools()
	var real := delta / maxf(Engine.time_scale, 0.01)
	if _toast_time > 0.0:
		_toast_time -= real
		_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)
	if _banner_time > 0.0:
		_banner_time -= real
		_banner.modulate.a = clampf(_banner_time, 0.0, 1.0)
	_overlay.queue_redraw()


func _draw_overlay() -> void:
	if main == null:
		return
	var s := _size()
	var gs := GameState
	var p: Planet = main.planet
	# 惑星の進み具合（割れるまで）
	var bar := Rect2(14, 76, s.x - 28.0, 10)
	var frac := clampf(float(p.broken()) / maxf(1.0, p.needed()), 0.0, 1.0)
	_overlay.draw_rect(bar, Color(1, 1, 1, 0.08))
	_overlay.draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Color(0.45, 0.95, 0.55))
	if gs.is_boss():
		var tb := Rect2(14, 90, s.x - 28.0, 6)
		var tf := clampf(main.boss_left / gs.boss_time(), 0.0, 1.0)
		_overlay.draw_rect(tb, Color(1, 1, 1, 0.08))
		_overlay.draw_rect(Rect2(tb.position, Vector2(tb.size.x * tf, tb.size.y)), Color(1.0, 0.4, 0.35))
	# 銀河の中の位置（5つの点、5つ目が巨大惑星）
	for k in gs.PLANETS_PER_GALAXY:
		var c := Vector2(s.x * 0.5 - 48.0 + k * 24.0, 102)
		var cur := k + 1 == gs.planet_in_galaxy()
		var done := k + 1 < gs.planet_in_galaxy()
		var rr := 7.0 if k == gs.PLANETS_PER_GALAXY - 1 else 5.0
		var col := Color(0.45, 0.95, 0.55) if done else (Color(1, 1, 1) if cur else Color(1, 1, 1, 0.25))
		if k == gs.PLANETS_PER_GALAXY - 1 and not done:
			col = Color(1.0, 0.45, 0.4, 1.0 if cur else 0.5)
		if cur:
			_overlay.draw_circle(c, rr, col)
		else:
			_overlay.draw_arc(c, rr, 0.0, TAU, 16, col, 2.0)


# ---------------------------------------------------------------- 強化カード


func show_cards(options: Array, rerolls: int) -> void:
	_clear(_card_box)
	var gs := GameState
	_title(_card_box, "惑星を破壊した！", 24, Color(0.6, 1.0, 0.65))
	_title(_card_box, "強化を1つ選ぶ（このランの間だけ有効）", 15, Color(1, 1, 1, 0.7))
	for c in options:
		var tag: String = ["", "【レア】", "【伝説】"][int(c["rare"])]
		var b := _wide(_card_box, "%s%s\n%s" % [tag, c["name"], c["desc"]], 74, 17)
		var col: Color = c.get("color", [Color(0.4, 0.75, 0.9), Color(0.85, 0.5, 1.0), Color(1.0, 0.8, 0.3)][int(c["rare"])])
		var sb := _box(Color(0.05, 0.06, 0.09), col, 2, 8)
		b.add_theme_stylebox_override("normal", sb)
		b.pressed.connect(func(): main.on_card_chosen(String(c["key"])))
	if rerolls > 0:
		var rr := _wide(_card_box, "引き直す（残り%d回）" % rerolls, 46, 16)
		rr.pressed.connect(func(): main.reroll_cards())
	_card_panel.visible = true
	if gs.planet_in_galaxy() == gs.PLANETS_PER_GALAXY - 1:
		toast("次は巨大惑星。制限時間内に割ろう", 3.0)


# ---------------------------------------------------------------- スキル


func _open_skills() -> void:
	get_tree().paused = true
	_build_skills()
	_skill_panel.visible = true


func _close() -> void:
	hide_panels()
	get_tree().paused = false


func _build_skills() -> void:
	_clear(_skill_box)
	var gs := GameState
	_title(_skill_box, "スキル　◆ %s" % gs.fmt(gs.data), 22)
	_title(_skill_box, "研究データ（◆）は「帰還」で手に入る。スキルは帰還しても残る", 13, Color(1, 1, 1, 0.65))
	var s := _size()
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(_panel_w() - 28.0, clampf(s.y - 300.0, 160.0, 560.0))
	_skill_box.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	var tw := (_panel_w() - 28.0 - 12.0 - 12.0) / 3.0
	for sk in gs.SKILLS:
		var id := String(sk["id"])
		var col: Color = sk["color"]
		var lv := gs.skill_level(id)
		var open := gs.skill_open(id)
		var tag := ""
		if gs.skill_maxed(id):
			tag = "最大"
		elif not open:
			tag = "要：%s Lv%d" % [gs.skill_def(String(sk["req"]))["name"], int(sk["rl"])]
		else:
			tag = "◆ %s" % gs.fmt(gs.skill_cost(id))
		var b := _button("%s\nLv %d/%d\n%s\n%s" % [sk["name"], lv, int(sk["max"]), sk["desc"], tag], Vector2(tw, 132), 12)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var border := col if open else Color(0.35, 0.35, 0.4)
		b.add_theme_stylebox_override("normal", _box(Color(col, 0.08) if lv > 0 else Color(0.04, 0.05, 0.07), border, 2, 4))
		b.add_theme_stylebox_override("disabled", _box(Color(0.03, 0.03, 0.05), Color(border, 0.45), 2, 4))
		b.disabled = not gs.can_buy_skill(id)
		b.pressed.connect(func():
			if gs.buy_skill(id):
				_build_skills())
		grid.add_child(b)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_skill_box.add_child(row)
	var all := _button("まとめて強化", Vector2((_panel_w() - 36.0) * 0.5, 50), 16)
	all.pressed.connect(func():
		var n := gs.buy_all_skills()
		_build_skills()
		toast("%d 回強化した" % n if n > 0 else "研究データが足りない"))
	row.add_child(all)
	var close := _button("閉じる", Vector2((_panel_w() - 36.0) * 0.5, 50), 16)
	close.pressed.connect(_close)
	row.add_child(close)


# ---------------------------------------------------------------- 帰還・カード一覧・放置報酬


func _open_prestige() -> void:
	get_tree().paused = true
	_clear(_msg_box)
	var gs := GameState
	var g := gs.prestige_gain()
	_title(_msg_box, "母艦へ帰還する？", 24)
	var text := "このランの最高到達：銀河 %d・惑星 %d\n" % [(gs.best_planet_run - 1) / 5 + 1, (gs.best_planet_run - 1) % 5 + 1]
	if g > 0:
		text += "帰還すると研究データ ◆%s を得る。\nクレジット・ツール・カードはリセットされ、惑星1からやり直す。" % gs.fmt(g)
	else:
		text += "研究データは銀河2（惑星6）まで進むと得られる。"
	_title(_msg_box, text, 15, Color(1, 1, 1, 0.8))
	if g > 0:
		var go := _wide(_msg_box, "帰還する（◆+%s）" % gs.fmt(g), 56, 19)
		go.pressed.connect(func(): main.do_prestige())
	var back := _wide(_msg_box, "続ける", 48, 17)
	back.pressed.connect(_close)
	_msg_panel.visible = true


func _open_run_cards() -> void:
	get_tree().paused = true
	_clear(_msg_box)
	var gs := GameState
	_title(_msg_box, "このランの強化カード", 22)
	var list := gs.card_summary()
	_title(_msg_box, "まだ無し。惑星を割ると選べる" if list.is_empty() else "\n".join(list), 16, Color(1, 1, 1, 0.85))
	_title(_msg_box, "威力 ×%.2f・獲得 ×%.2f・費用 ×%.2f" % [gs.dps_mult(), gs.value_mult(), gs.cost_mult()], 14, Color(0.6, 1.0, 0.7))
	var back := _wide(_msg_box, "閉じる", 48, 17)
	back.pressed.connect(_close)
	_msg_panel.visible = true


func show_offline(gain: float, secs: float) -> void:
	get_tree().paused = true
	_clear(_msg_box)
	_title(_msg_box, "おかえりなさい", 24)
	var h := int(secs) / 3600
	var m := (int(secs) % 3600) / 60
	var t := ("%d時間%d分" % [h, m]) if h > 0 else ("%d分" % m)
	_title(_msg_box, "離れていた %s の間も採掘を続けていた\n+%s CR" % [t, GameState.fmt(gain)], 17, Color(1.0, 0.85, 0.4))
	var ok := _wide(_msg_box, "受け取る", 52, 18)
	ok.pressed.connect(_close)
	_msg_panel.visible = true
