extends CanvasLayer
## 画面表示。上：素材・クレジット・惑星の進み具合。中：惑星（タップで手掘り）。
## 下（横持ちでは右）：採掘ツールの一覧。パネル：スキルツリー、遺物、惑星クリア、放置報酬。

const BUY_MODES := [1, 10, 0]  # 0 = 買えるだけ

var main: Node = null

var _theme: Theme
var _overlay: Control
var _mat_label: RichTextLabel
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
var _tree_panel: PanelContainer
var _tree_box: VBoxContainer
var _tree_sel: String = "drone_pow"
var _tree_scroll_y: float = 0.0
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

	_mat_label = RichTextLabel.new()
	_mat_label.bbcode_enabled = true
	_mat_label.fit_content = true
	_mat_label.scroll_active = false
	_mat_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_mat_label.add_theme_font_size_override("normal_font_size", 14)
	_mat_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_mat_label.add_theme_constant_override("outline_size", 4)
	_mat_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mat_label)
	_credit_label = _make_label(28)
	_credit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rate_label = _make_label(14)
	_rate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rate_label.modulate = Color(1.0, 0.75, 0.4)
	_planet_label = _make_label(14)
	_planet_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_side = VBoxContainer.new()
	_side.add_theme_constant_override("separation", 8)
	add_child(_side)
	for spec in [["スキル", _open_tree], ["遺物", _open_relics]]:
		var b := _button(spec[0], Vector2(70, 44), 15)
		b.pressed.connect(spec[1])
		_side.add_child(b)

	_build_tool_panel()

	_toast = _make_label(17)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner = _make_label(26)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_tree_panel = _make_panel()
	_tree_box = _panel_box(_tree_panel)
	_msg_panel = _make_panel()
	_msg_box = _panel_box(_msg_panel)


# ---------------------------------------------------------------- 部品


func _box(bg: Color, border: Color, bw: int = 2, radius: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
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
	panel.set_content_margin_all(12)
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
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	return box


func _clear(box: Container) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _size() -> Vector2:
	return _overlay.get_viewport().get_visible_rect().size


## 横長の画面ではスキルツリーを横に広げ、詳細を右側に置く
func _tree_wide() -> bool:
	var s := _size()
	return s.x > s.y and s.x >= 760.0


func _tree_w() -> float:
	return minf(1000.0, _size().x - 20.0) if _tree_wide() else _panel_w()


func _panel_w() -> float:
	return minf(560.0, _size().x - 20.0)


func _title(box: Container, text: String, font_size: int = 22, col: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.custom_minimum_size = Vector2(_panel_w() - 24.0, 0)
	l.modulate = col
	box.add_child(l)
	return l


func _wide(box: Container, text: String, h: float, font_size: int) -> Button:
	var b := _button(text, Vector2(_panel_w() - 24.0, h), font_size)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(b)
	return b


func _mat_bb(cost: Dictionary, check: bool) -> String:
	var gs := GameState
	var parts: PackedStringArray = []
	for m in cost:
		var ok := float(gs.mats.get(m, 0.0)) + 0.001 >= float(cost[m])
		var col: String = (gs.MAT_COLORS[m] as Color).to_html(false)
		var num := gs.fmt(float(cost[m]))
		if check and not ok:
			num = "[color=#ff6a5a]%s[/color]" % num
		parts.append("[color=#%s]■[/color]%s %s" % [col, gs.MAT_NAMES[m], num])
	return "  ".join(parts)


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
	_banner_time = 3.0


func relic_found(r: Dictionary) -> void:
	banner("遺物を発見：%s" % r["name"], String(r["desc"]))


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
	if not GameState.tool_unlocked(id):
		_tree_sel = id
		_open_tree()
		return
	if GameState.buy_tool(id, _buy_count(id)):
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
		var btn: Button = r["btn"]
		var lv := gs.tool_level(id)
		if not gs.tool_unlocked(id):
			(r["name"] as Label).text = String(td["name"])
			(r["dps"] as Label).text = ""
			(r["sub"] as Label).text = "スキルツリーで解放（%s）" % gs.cost_text(gs.skill_cost(id))
			btn.text = "未解放\nツリーへ"
			btn.disabled = false
			(r["row"] as PanelContainer).modulate.a = 0.5
			continue
		var n := _buy_count(id)
		var cost := gs.upgrade_cost(id, n)
		(r["name"] as Label).text = String(td["name"]) + ("  Lv %d" % lv if lv > 0 else "")
		(r["dps"] as Label).text = "毎秒 %s" % gs.fmt(gs.tool_dps(id)) if lv > 0 else ""
		if lv > 0:
			var gain := gs.tool_dps_at(id, lv + n) - gs.tool_dps(id)
			(r["sub"] as Label).text = "+%s／次の強化段階まで %d" % [gs.fmt(gain), 25 - lv % 25]
		else:
			(r["sub"] as Label).text = String(td["desc"])
		btn.text = ("強化 ×%d\n%s" % [n, gs.fmt(cost)]) if lv > 0 else ("配備\n%s" % gs.fmt(cost))
		btn.disabled = cost > gs.credits
		(r["row"] as PanelContainer).modulate.a = 1.0
		(r["bar"] as Control).queue_redraw()


# ---------------------------------------------------------------- 配置


func _portrait() -> bool:
	var s := _size()
	return s.y >= s.x


func planet_area() -> Rect2:
	var s := _size()
	if _portrait():
		var bottom := _tool_panel.position.y - 4.0
		return Rect2(Vector2(0, _top_h), Vector2(s.x, maxf(120.0, bottom - _top_h)))
	return Rect2(Vector2(0, _top_h), Vector2(_tool_panel.position.x - 4.0, s.y - _top_h))


func _layout() -> void:
	var s := _size()
	_top_h = 104.0
	_mat_label.position = Vector2(12, 8)
	_mat_label.size = Vector2(150, 0)
	_credit_label.position = Vector2(0, 4)
	_credit_label.size = Vector2(s.x, 0)
	_rate_label.position = Vector2(0, 42)
	_rate_label.size = Vector2(s.x, 0)
	_planet_label.size = Vector2(190, 0)
	_planet_label.position = Vector2(s.x - 202.0, 8)
	_side.position = Vector2(10, _top_h + 6.0)
	if _portrait():
		var ph := clampf(s.y * 0.4, 250.0, 500.0)
		_tool_panel.position = Vector2(8, s.y - ph - 8.0)
		_tool_panel.size = Vector2(s.x - 16.0, ph)
	else:
		var pw := clampf(s.x * 0.42, 360.0, 560.0)
		_tool_panel.position = Vector2(s.x - pw - 8.0, _top_h)
		_tool_panel.size = Vector2(pw, s.y - _top_h - 8.0)
	var area := planet_area()
	_toast.size = Vector2(area.size.x - 40.0, 0)
	_toast.position = Vector2(area.position.x + 20.0, area.end.y - 64.0)
	_banner.size = Vector2(area.size.x - 40.0, 0)
	_banner.position = Vector2(area.position.x + 20.0, area.position.y + area.size.y * 0.3)
	for p in _panels:
		(p as PanelContainer).custom_minimum_size = Vector2(_tree_w() if p == _tree_panel else _panel_w(), 0)


func _process(delta: float) -> void:
	for pair in _backdrops:
		pair[0].visible = pair[1].visible
	_layout()
	var gs := GameState
	var lines: PackedStringArray = []
	for m in gs.MATS:
		lines.append("[color=#%s]■[/color] %s %s" % [(gs.MAT_COLORS[m] as Color).to_html(false), gs.MAT_NAMES[m], gs.fmt(float(gs.mats[m]))])
	_mat_label.text = "\n".join(lines)
	_credit_label.text = gs.fmt(gs.credits) + " CR"
	_rate_label.text = "毎秒 %s ダメージ" % gs.fmt(gs.total_dps())
	if main != null:
		var p: Planet = main.planet
		var t := int(gs.planet_time)
		_planet_label.text = "惑星 %d：%s\n掘削 %.1f%%\n経過 %d:%02d" % [gs.planet, gs.trait_def()["name"], 100.0 * minf(1.0, float(p.broken()) / maxf(1.0, p.needed())), t / 60, t % 60]
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
	var p: Planet = main.planet
	# 惑星が上まで映るので、上の情報欄に暗い帯を敷いて読みやすくする
	_overlay.draw_rect(Rect2(0, 0, s.x, _top_h), Color(0.02, 0.03, 0.07, 0.72))
	_overlay.draw_rect(Rect2(0, _top_h, s.x, 2), Color(1, 1, 1, 0.08))
	var bar := Rect2(12, 92, s.x - 24.0, 8)
	var frac := clampf(float(p.broken()) / maxf(1.0, p.needed()), 0.0, 1.0)
	_overlay.draw_rect(bar, Color(1, 1, 1, 0.08))
	_overlay.draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Color(0.45, 0.95, 0.55))
	_draw_minimap(p)


## 惑星エリアの右上に、惑星全体の小さな地図と「いま見ている範囲」を描く。
func _draw_minimap(p: Planet) -> void:
	var tex: Texture2D = p.get("_tex")
	if tex == null:
		return
	var area := planet_area()
	var m := 92.0
	var box := Rect2(area.end.x - m - 10.0, area.position.y + 8.0, m, m)
	var c := box.get_center()
	_overlay.draw_circle(c, m * 0.5 + 3.0, Color(0.02, 0.03, 0.08, 0.75))
	_overlay.draw_arc(c, m * 0.5 + 3.0, 0.0, TAU, 40, Color(1, 1, 1, 0.25), 1.0)
	_overlay.draw_texture_rect(tex, box, false)
	var world := p.size * Planet.CELL
	var k := m / world
	var cam: Camera2D = main.camera
	var view := area.size / cam.zoom.x
	var vc: Vector2 = cam.position + (area.get_center() - _size() * 0.5) / cam.zoom.x
	var vr := Rect2(c + (vc - p.position - view * 0.5) * k, view * k)
	_overlay.draw_rect(vr, Color(1, 1, 1, 0.8), false, 1.0)
	_overlay.draw_circle(c + (main.focus - p.position) * k, 2.5, Color(1.0, 0.9, 0.4))


# ---------------------------------------------------------------- スキルツリー


func _open_tree() -> void:
	get_tree().paused = true
	_tree_scroll_y = 0.0
	_build_tree()
	_tree_panel.visible = true


var _after_tree := Callable()


func _close() -> void:
	if _tree_panel.visible and _after_tree.is_valid():
		var cb := _after_tree
		_after_tree = Callable()
		cb.call()
		return
	hide_panels()
	get_tree().paused = false


func _build_tree() -> void:
	var keep_scroll := _tree_scroll_y
	_clear(_tree_box)
	var gs := GameState
	_title(_tree_box, "スキルツリー", 22)
	var mats := RichTextLabel.new()
	mats.bbcode_enabled = true
	mats.fit_content = true
	mats.scroll_active = false
	mats.add_theme_font_size_override("normal_font_size", 14)
	mats.custom_minimum_size = Vector2(_tree_w() - 24.0, 0)
	var have := {}
	for m in gs.MATS:
		have[m] = gs.mats[m]
	mats.text = "[center]所持：" + _mat_bb(have, false) + "[/center]"
	_tree_box.add_child(mats)

	var s := _size()
	var wide := _tree_wide()
	var tree_w := (_tree_w() - 24.0) * 0.6 if wide else _panel_w() - 24.0
	var side_w := (_tree_w() - 24.0) - tree_w - 10.0 if wide else _panel_w() - 24.0
	var body: BoxContainer = HBoxContainer.new() if wide else VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	_tree_box.add_child(body)
	var cols := 5
	var inner := tree_w - 12.0
	var cw := inner / cols
	var nw := cw - 8.0
	var nh := 58.0
	var rh := nh + 22.0
	var rows := 0
	for sk in gs.SKILLS:
		rows = maxi(rows, (sk["pos"] as Vector2i).y + 1)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(tree_w, clampf(s.y - 150.0, 200.0, 620.0) if wide else clampf(s.y - 380.0, 180.0, 520.0))
	body.add_child(scroll)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 8)
	body.add_child(side)
	var canvas := Control.new()
	canvas.custom_minimum_size = Vector2(inner, rows * rh + 40.0)
	scroll.add_child(canvas)
	var pos_of := func(sk: Dictionary) -> Vector2:
		var p: Vector2i = sk["pos"]
		return Vector2(p.x * cw + 4.0, 8.0 + p.y * rh + (24.0 if p.y >= 1 else 0.0))
	# 系統の見出し
	for k in cols:
		var hl := Label.new()
		hl.text = gs.BRANCHES[k]
		hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hl.add_theme_font_size_override("font_size", 12)
		hl.modulate = Color(0.6, 0.85, 1.0)
		hl.position = Vector2(k * cw, 8.0 + rh + 4.0)
		hl.size = Vector2(cw, 16)
		canvas.add_child(hl)
	# 枝（親子の線）
	canvas.draw.connect(func():
		for sk in gs.SKILLS:
			var par := String(sk["parent"])
			if par == "":
				continue
			var a: Vector2 = pos_of.call(gs.skill_def(par)) + Vector2(nw * 0.5, nh)
			var b: Vector2 = pos_of.call(sk) + Vector2(nw * 0.5, 0)
			var lit := gs.skill_level(String(sk["id"])) > 0
			var col := Color(0.45, 0.95, 0.6, 0.9) if lit else (Color(0.6, 0.75, 0.9, 0.5) if gs.skill_open(String(sk["id"])) else Color(0.4, 0.4, 0.45, 0.35))
			if absf(a.x - b.x) < 1.0:
				canvas.draw_line(a, b, col, 2.0)
			else:
				var mid := a.y + 8.0
				canvas.draw_polyline(PackedVector2Array([a, Vector2(a.x, mid), Vector2(b.x, mid), b]), col, 2.0))
	for sk in gs.SKILLS:
		var id := String(sk["id"])
		var lv := gs.skill_level(id)
		var mx := int(sk["max"])
		var open := gs.skill_open(id)
		var b := _button("%s\n%s" % [sk["name"], ("Lv %d/%d" % [lv, mx]) if mx > 1 else ("習得済み" if lv > 0 else "未習得")], Vector2(nw, nh), 11)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.position = pos_of.call(sk)
		b.size = Vector2(nw, nh)
		var border := Color(0.45, 0.95, 0.6) if lv >= mx else (Color(0.4, 0.8, 1.0) if gs.can_buy_skill(id) else (Color(0.6, 0.65, 0.75) if open else Color(0.3, 0.3, 0.35)))
		var bg := Color(0.08, 0.18, 0.12) if lv > 0 else Color(0.04, 0.05, 0.07)
		var w := 3 if id == _tree_sel else 2
		if id == _tree_sel:
			border = Color(1.0, 0.9, 0.4)
		b.add_theme_stylebox_override("normal", _box(bg, border, w, 4))
		b.add_theme_stylebox_override("hover", _box(bg.lightened(0.05), border.lightened(0.2), w, 4))
		if not open:
			b.modulate = Color(1, 1, 1, 0.45)
		b.pressed.connect(func():
			_tree_sel = id
			_tree_scroll_y = scroll.scroll_vertical
			_build_tree())
		canvas.add_child(b)
	scroll.ready.connect(func(): scroll.scroll_vertical = int(keep_scroll))
	scroll.set_deferred("scroll_vertical", int(keep_scroll))

	# 選んだスキルの詳細
	var sel := gs.skill_def(_tree_sel)
	if sel.is_empty():
		sel = gs.SKILLS[0]
	var sid := String(sel["id"])
	var detail := PanelContainer.new()
	var ds := _box(Color(0.05, 0.06, 0.09), Color(1.0, 0.9, 0.4, 0.6), 2, 8)
	ds.set_content_margin_all(10)
	detail.add_theme_stylebox_override("panel", ds)
	side.add_child(detail)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 4)
	detail.add_child(dv)
	var dt := Label.new()
	dt.text = "%s　Lv %d/%d" % [sel["name"], gs.skill_level(sid), int(sel["max"])]
	dt.add_theme_font_size_override("font_size", 17)
	dv.add_child(dt)
	var dd := Label.new()
	dd.text = String(sel["desc"]) + ("（1レベルごと）" if int(sel["max"]) > 1 else "")
	dd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dd.custom_minimum_size = Vector2(side_w - 24.0, 0)
	dd.add_theme_font_size_override("font_size", 14)
	dd.modulate = Color(1, 1, 1, 0.8)
	dv.add_child(dd)
	var dc := RichTextLabel.new()
	dc.bbcode_enabled = true
	dc.fit_content = true
	dc.scroll_active = false
	dc.add_theme_font_size_override("normal_font_size", 14)
	dc.custom_minimum_size = Vector2(side_w - 24.0, 0)
	if gs.skill_maxed(sid):
		dc.text = "[color=#73f29a]最大レベル[/color]"
	elif not gs.skill_open(sid):
		dc.text = "[color=#ff8a7a]先に「%s」を習得[/color]" % gs.skill_def(String(sel["parent"]))["name"]
	else:
		dc.text = "必要：" + _mat_bb(gs.skill_cost(sid), true)
	dv.add_child(dc)

	var row: BoxContainer = VBoxContainer.new() if wide else HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	side.add_child(row)
	var bw := side_w if wide else (side_w - 12.0) / 3.0
	var buy := _button("強化", Vector2(bw, 48), 17)
	buy.disabled = not gs.can_buy_skill(sid)
	buy.pressed.connect(func():
		if gs.buy_skill(sid):
			_tree_scroll_y = scroll.scroll_vertical
			_build_tree())
	row.add_child(buy)
	var all := _button("まとめて強化", Vector2(bw, 48), 15)
	all.pressed.connect(func():
		var n := gs.buy_all_skills()
		_tree_scroll_y = scroll.scroll_vertical
		_build_tree()
		toast("%d 回強化した" % n if n > 0 else "素材が足りない"))
	row.add_child(all)
	var close := _button("閉じる", Vector2(bw, 48), 17)
	close.pressed.connect(_close)
	row.add_child(close)


# ---------------------------------------------------------------- 遺物・惑星クリア・放置報酬


func _open_relics() -> void:
	get_tree().paused = true
	_clear(_msg_box)
	var gs := GameState
	_title(_msg_box, "この惑星で見つけた遺物", 22)
	if gs.relics.is_empty():
		_title(_msg_box, "まだ無し。岩の中に埋まっていて、掘り当てると光る。\n効果はこの惑星にいる間だけ続く", 15, Color(1, 1, 1, 0.75))
	else:
		var counts := {}
		for r in gs.relics:
			counts[r] = int(counts.get(r, 0)) + 1
		for rd in gs.RELICS:
			var id := String(rd["id"])
			if counts.has(id):
				_title(_msg_box, "%s ×%d\n%s" % [rd["name"], counts[id], rd["desc"]], 15, Color(0.5, 1.0, 0.9))
	var tr := gs.trait_def()
	_title(_msg_box, "惑星の特性：%s（%s）" % [tr["name"], tr["desc"]], 14, Color(1, 0.85, 0.5))
	var back := _wide(_msg_box, "閉じる", 48, 17)
	back.pressed.connect(_close)
	_msg_panel.visible = true


func show_clear(extra: Dictionary, next: Array) -> void:
	_clear(_msg_box)
	var gs := GameState
	var t := int(gs.planet_time)
	_title(_msg_box, "惑星 %d を破壊した！" % gs.planet, 24, Color(0.6, 1.0, 0.65))
	_title(_msg_box, "所要時間 %d分%02d秒・遺物 %d個" % [t / 60, t % 60, gs.relics.size()], 15, Color(1, 1, 1, 0.75))
	var got := RichTextLabel.new()
	got.bbcode_enabled = true
	got.fit_content = true
	got.scroll_active = false
	got.add_theme_font_size_override("normal_font_size", 15)
	got.custom_minimum_size = Vector2(_panel_w() - 24.0, 0)
	got.text = "[center]この惑星で集めた素材\n%s%s[/center]" % [_mat_bb(gs.mats_this_planet, false), ("\n核の回収ボーナス " + _mat_bb(extra, false)) if not extra.is_empty() else ""]
	_msg_box.add_child(got)
	_title(_msg_box, "クレジットとツールは次の惑星でリセット。素材とスキルは残る", 13, Color(1, 1, 1, 0.6))
	_title(_msg_box, "次の惑星（ずっと硬くなる）" if next.size() == 1 else "次の惑星を選ぶ", 17)
	for tid in next:
		var tr := gs.trait_def(String(tid))
		var b := _wide(_msg_box, "惑星 %d：%s\n%s" % [gs.planet + 1, tr["name"], tr["desc"]], 64, 16)
		b.pressed.connect(func(): main.go_next(String(tid)))
	var tree := _wide(_msg_box, "先にスキルツリーを見る", 44, 15)
	tree.pressed.connect(func():
		_after_tree = func(): show_clear(extra, next)
		_build_tree()
		_msg_panel.visible = false
		_tree_panel.visible = true)
	_tree_panel.visible = false
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
