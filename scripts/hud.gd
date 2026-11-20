extends CanvasLayer
## 画面表示。上：素材・クレジット・惑星の進み具合。中：惑星（タップで手掘り）。
## 下（横持ちでは右）：採掘ツールの一覧。パネル：スキルツリー、遺物、惑星クリア、放置報酬。

const BUY_MODES := [1, 10, 0]  # 0 = 買えるだけ

var main: Node = null

var _theme: Theme
var _overlay: Control
var _credit_label: Label
var _rate_label: Label
var _planet_label: RichTextLabel
var _toast: Label
var _toast_time: float = 0.0
var _banner: Label
var _banner_time: float = 0.0
var _side: VBoxContainer
var _sound_btn: Button
var _skill_btn: Button
var _dot_t: float = 0.0
var _tool_panel: PanelContainer
var _tool_rows := {}
var _buy_btn: Button
var _buy_mode: int = 0
var _panels: Array = []
var _backdrops: Array = []
var _tree_panel: PanelContainer
var _tree_box: VBoxContainer
var _tree_sel: String = "drone_pow"
var _map: SkillMap = null
var _map_off := Vector2(0, -120)
var _map_zoom: float = 0.8
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

	_credit_label = _make_label(30)
	_credit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rate_label = _make_label(13)
	_rate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rate_label.add_theme_color_override("font_color", Neon.ORANGE)
	_planet_label = RichTextLabel.new()
	_planet_label.bbcode_enabled = true
	_planet_label.fit_content = true
	_planet_label.scroll_active = false
	_planet_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_planet_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Neon.plain_text(_planet_label, 12)
	add_child(_planet_label)

	# 左のボタン（スキル・遺物・音）：黒い四角に差し色の枠と白い線のアイコン
	_side = VBoxContainer.new()
	_side.add_theme_constant_override("separation", 10)
	add_child(_side)
	var skill_btn := _icon_button("skill", "スキル", Neon.CYAN)
	skill_btn.pressed.connect(_open_tree)
	_skill_btn = skill_btn
	var relic_btn := _icon_button("relic", "遺物", Neon.MAGENTA)
	relic_btn.pressed.connect(_open_relics)
	_sound_btn = _icon_button("sound", "音 ON", Neon.ORANGE)
	_sound_btn.pressed.connect(func():
		Audio.set_enabled(not Audio.enabled)
		_update_sound_btn())
	_update_sound_btn()

	_build_tool_panel()

	_toast = _make_label(15)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner = _make_label(18)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# お知らせは黒い帯に細い枠を付けて、演出の上でも読めるようにする
	for pair in [[_toast, Neon.CYAN], [_banner, Neon.YELLOW]]:
		var sb := _box(Color(0, 0, 0, 0.88), Color(pair[1], 0.8), 1)
		sb.set_content_margin_all(10)
		(pair[0] as Label).add_theme_stylebox_override("normal", sb)
		(pair[0] as Label).modulate.a = 0.0

	_tree_panel = _make_panel()
	_tree_box = _panel_box(_tree_panel)
	_msg_panel = _make_panel()
	_msg_box = _panel_box(_msg_panel)


# ---------------------------------------------------------------- 部品


func _box(bg: Color, border: Color, bw: int = 1, _radius: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(0)
	sb.anti_aliasing = false
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font = Neon.font()
	th.set_stylebox("normal", "Button", BracketBox.new(Neon.BG, Neon.MUTED, Neon.CYAN))
	th.set_stylebox("hover", "Button", BracketBox.new(Neon.BG, Neon.LINE, Neon.CYAN))
	th.set_stylebox("pressed", "Button", BracketBox.new(Color(Neon.CYAN, 0.15), Neon.CYAN, Neon.CYAN))
	th.set_stylebox("hover_pressed", "Button", BracketBox.new(Color(Neon.CYAN, 0.15), Neon.CYAN, Neon.CYAN))
	th.set_stylebox("disabled", "Button", BracketBox.new(Neon.BG, Color(Neon.MUTED, 0.4), Color(Neon.CYAN, 0.4)))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", Neon.TEXT)
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_pressed_color", "Button", Color.WHITE)
	th.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	th.set_color("font_disabled_color", "Button", Color(Neon.TEXT, 0.4))
	th.set_constant("outline_size", "Button", 0)
	var panel := _box(Neon.PANEL, Neon.CYAN, 1)
	panel.set_content_margin_all(16)
	th.set_stylebox("panel", "PanelContainer", panel)
	for cls in ["Label", "RichTextLabel"]:
		th.set_color("font_shadow_color", cls, Neon.SHADOW)
		th.set_constant("shadow_offset_x", cls, 1)
		th.set_constant("shadow_offset_y", cls, 1)
		th.set_constant("outline_size", cls, 0)
	th.set_color("font_color", "Label", Neon.TEXT)
	# スクロールバー：細い平らな線
	var track := _box(Neon.TRACK, Color(0, 0, 0, 0), 0)
	track.set_content_margin_all(0)
	track.content_margin_left = 2
	track.content_margin_right = 2
	var grab := _box(Color(Neon.CYAN, 0.6), Color(0, 0, 0, 0), 0)
	var grab_hi := _box(Neon.CYAN, Color(0, 0, 0, 0), 0)
	th.set_stylebox("scroll", "VScrollBar", track)
	th.set_stylebox("grabber", "VScrollBar", grab)
	th.set_stylebox("grabber_highlight", "VScrollBar", grab_hi)
	th.set_stylebox("grabber_pressed", "VScrollBar", grab_hi)
	th.set_color("default_color", "RichTextLabel", Neon.TEXT)
	return th


func _update_sound_btn() -> void:
	_sound_btn.set_meta("icon", "sound" if Audio.enabled else "mute")
	(_sound_btn.get_meta("label_node") as Label).text = "音 ON" if Audio.enabled else "音 OFF"
	_sound_btn.queue_redraw()


func _make_label(font_size: int) -> Label:
	var l := Label.new()
	Neon.plain_text(l, font_size)
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
	b.pressed.connect(func(): Audio.play("click"))
	return b


## 左に並ぶ四角いボタン（約44px）。名前は小さく下に添える。右上の赤い点はお知らせ。
func _icon_button(icon: String, label: String, accent: Color) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(46, 46)
	b.focus_mode = Control.FOCUS_NONE
	b.flat = true
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.set_meta("icon", icon)
	b.set_meta("label", label)
	b.set_meta("dot", false)
	b.pressed.connect(func(): Audio.play("click"))
	b.draw.connect(func():
		var r := Rect2(Vector2.ZERO, b.size)
		var down := b.is_pressed() or b.get_draw_mode() == BaseButton.DRAW_PRESSED
		b.draw_rect(r, Color(accent, 0.18) if down else Neon.BG)
		b.draw_rect(r.grow(-1.0), Neon.glow(accent), false, 5.0)
		b.draw_rect(r.grow(-1.0), accent, false, 2.0)
		Neon.icon(b, String(b.get_meta("icon")), r.get_center(), 24.0, Neon.LINE, 1.5)
		if bool(b.get_meta("dot")):
			b.draw_circle(Vector2(b.size.x - 1.0, 1.0), 4.5, Neon.RED))
	b.button_down.connect(b.queue_redraw)
	b.button_up.connect(b.queue_redraw)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.add_child(b)
	var l := Label.new()
	Neon.plain_text(l, 10, Neon.MUTED)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.text = label
	box.add_child(l)
	b.set_meta("label_node", l)
	_side.add_child(box)
	return b


func _make_panel() -> PanelContainer:
	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 0.8)
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
			num = "[color=#E8504A]%s[/color]" % num
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
	var sb := _box(Neon.BG, Neon.CYAN, 1)
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
	Neon.plain_text(t, 14, Neon.MUTED)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(t)
	_buy_btn = _button("", Vector2(104, 44), 13)
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
		var row := PanelContainer.new()
		var rs := _box(Neon.BG, Color(Neon.CYAN, 0.45), 1)
		rs.content_margin_left = 8
		rs.content_margin_right = 6
		rs.content_margin_top = 6
		rs.content_margin_bottom = 6
		row.add_theme_stylebox_override("panel", rs)
		list.add_child(row)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		row.add_child(h)
		# ツールの色はこの小さなアイコンにだけ使う
		var icon := Control.new()
		icon.custom_minimum_size = Vector2(22, 22)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var tc: Color = Neon.TOOL_COLORS.get(id, Neon.CYAN)
		icon.draw.connect(func():
			Neon.icon(icon, id, icon.size * 0.5, 20.0, Neon.glow(tc), 4.0)
			Neon.icon(icon, id, icon.size * 0.5, 20.0, tc, 1.5))
		h.add_child(icon)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 3)
		h.add_child(info)
		var top := HBoxContainer.new()
		info.add_child(top)
		var name := Label.new()
		Neon.plain_text(name, 14)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.clip_text = true
		name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		top.add_child(name)
		var dps := Label.new()
		Neon.plain_text(dps, 13)
		dps.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		top.add_child(dps)
		var mid := HBoxContainer.new()
		mid.add_theme_constant_override("separation", 8)
		info.add_child(mid)
		var lv := Label.new()
		Neon.plain_text(lv, 12, Neon.MUTED)
		mid.add_child(lv)
		var sub := Label.new()
		Neon.plain_text(sub, 11, Neon.MUTED)
		sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sub.clip_text = true
		sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		mid.add_child(sub)
		# 強化段階の小さな四角5つ（25レベルごとに1つ埋まる）
		var pips := Control.new()
		pips.custom_minimum_size = Vector2(5 * 6 + 4 * 2, 12)
		pips.draw.connect(func():
			var n := mini(5, GameState.tool_level(id) / 25)
			for k in 5:
				pips.draw_rect(Rect2(k * 8.0, 3.0, 6.0, 6.0), Neon.CYAN if k < n else Neon.TRACK))
		mid.add_child(pips)
		var bar := Control.new()
		bar.custom_minimum_size = Vector2(0, 4)
		bar.draw.connect(func():
			var w := bar.size.x
			bar.draw_rect(Rect2(0, 0, w, 4), Neon.TRACK)
			bar.draw_rect(Rect2(0, 0, w * GameState.milestone_frac(id), 4), Neon.CYAN))
		info.add_child(bar)
		var btn := _cost_button()
		btn.pressed.connect(_on_buy.bind(id))
		h.add_child(btn)
		_tool_rows[id] = {"name": name, "dps": dps, "lv": lv, "sub": sub, "pips": pips, "bar": bar, "btn": btn, "row": row}


## 購入ボタン：黒い長方形に灰色の細い枠と角かっこ。上に小さく動作、値段は2行（数 / CR）。
## 押せないときは全体を40%の濃さにする。
func _cost_button() -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(92, 58)
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var normal := BracketBox.new(Neon.BG, Neon.MUTED, Neon.CYAN)
	normal.arm = 7.0
	var down := BracketBox.new(Color(Neon.CYAN, 0.15), Neon.CYAN, Neon.CYAN)
	down.arm = 7.0
	for st in ["normal", "hover", "disabled"]:
		b.add_theme_stylebox_override(st, normal)
	for st in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, down)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.set_meta("lines", ["", "", ""])
	b.pressed.connect(func(): Audio.play("click"))
	b.draw.connect(func():
		var f := Neon.font()
		var lines: Array = b.get_meta("lines")
		var w := b.size.x
		var y := 15.0
		var specs := [[String(lines[0]), 10, Neon.MUTED], [String(lines[1]), 15, Neon.TEXT], [String(lines[2]), 11, Neon.TEXT]]
		for sp in specs:
			var txt: String = sp[0]
			if txt != "":
				var fs: int = sp[1]
				var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				b.draw_string(f, Vector2((w - tw) * 0.5 + 1.0, y + 1.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Neon.SHADOW)
				b.draw_string(f, Vector2((w - tw) * 0.5, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, sp[2])
			y += 17.0 if sp[1] != 10 else 16.0)
	return b


func _set_cost(b: Button, verb: String, cost: String, unit: String, enabled: bool) -> void:
	var lines: Array = [verb, cost, unit]
	if lines != b.get_meta("lines") or b.disabled == enabled:
		b.set_meta("lines", lines)
		b.disabled = not enabled
		b.modulate.a = 1.0 if enabled else 0.4
		b.queue_redraw()


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
		Audio.play("buy", 0.0, 0.15)
		var row: PanelContainer = _tool_rows[id]["row"]
		var tw := row.create_tween()
		row.self_modulate = Color(1.8, 1.8, 1.8)
		tw.tween_property(row, "self_modulate", Color.WHITE, 0.25)


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
			(r["lv"] as Label).text = ""
			(r["sub"] as Label).text = "スキルマップで解放（%s）" % gs.cost_text(gs.skill_cost(id))
			_set_cost(btn, "", "未解放", "マップへ", true)
			(r["row"] as PanelContainer).modulate.a = 0.5
			continue
		var n := _buy_count(id)
		var cost := gs.upgrade_cost(id, n)
		(r["name"] as Label).text = String(td["name"])
		(r["lv"] as Label).text = "Lv. %d" % lv
		(r["dps"] as Label).text = "毎秒 %s" % gs.fmt(gs.tool_dps(id)) if lv > 0 else ""
		if lv > 0:
			var gain := gs.tool_dps_at(id, lv + n) - gs.tool_dps(id)
			(r["sub"] as Label).text = "+%s／次の強化段階まで %d" % [gs.fmt(gain), 25 - lv % 25]
		else:
			(r["sub"] as Label).text = String(td["desc"])
		_set_cost(btn, ("強化 ×%d" % n) if lv > 0 else "配備", gs.fmt(cost), "CR", cost <= gs.credits)
		(r["row"] as PanelContainer).modulate.a = 1.0
		(r["bar"] as Control).queue_redraw()
		(r["pips"] as Control).queue_redraw()


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
	_credit_label.position = Vector2(0, 8)
	_credit_label.size = Vector2(s.x, 0)
	_rate_label.position = Vector2(0, 46)
	_rate_label.size = Vector2(s.x, 0)
	_planet_label.size = Vector2(200, 0)
	_planet_label.position = Vector2(s.x - 212.0, 10)
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
	_credit_label.text = gs.fmt(gs.credits) + " CR"
	_rate_label.text = "毎秒 %s ダメージ" % gs.fmt(gs.total_dps())
	if main != null:
		var p: Planet = main.planet
		var t := int(gs.planet_time)
		_planet_label.text = "[right]惑星 %d：%s\n[color=#%s]掘削 %.1f%%[/color]\n経過 %d:%02d[/right]" % [gs.planet, gs.trait_def()["name"], Neon.ORANGE.to_html(false), 100.0 * minf(1.0, float(p.broken()) / maxf(1.0, p.needed())), t / 60, t % 60]
	_dot_t -= delta
	if _dot_t <= 0.0:
		_dot_t = 0.5
		var can := false
		for sk in gs.SKILLS:
			if gs.can_buy_skill(String(sk["id"])):
				can = true
				break
		if can != bool(_skill_btn.get_meta("dot")):
			_skill_btn.set_meta("dot", can)
			_skill_btn.queue_redraw()
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
	var f := Neon.font()
	# 上の情報欄は黒で塗るだけ（グラデーションや線の飾りはなし）
	_overlay.draw_rect(Rect2(0, 0, s.x, _top_h), Color(0, 0, 0, 0.92))
	# 素材：8px の四角い色見本と、小さな等幅の文字
	var y := 12.0
	for m in gs.MATS:
		var col: Color = gs.MAT_COLORS[m]
		_overlay.draw_rect(Rect2(12, y + 1.0, 8, 8), col)
		var txt := "%s %s" % [gs.MAT_NAMES[m], gs.fmt(float(gs.mats[m]))]
		_overlay.draw_string(f, Vector2(27, y + 11.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Neon.SHADOW)
		_overlay.draw_string(f, Vector2(26, y + 10.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Neon.TEXT)
		y += 17.0
	# 掘削の進み具合：2px の線
	var frac := clampf(float(p.broken()) / maxf(1.0, p.needed()), 0.0, 1.0)
	var ly := _top_h - 6.0
	_overlay.draw_rect(Rect2(12, ly, s.x - 24.0, 2), Neon.TRACK)
	if frac > 0.0:
		var fr := Rect2(12, ly, (s.x - 24.0) * frac, 2)
		_overlay.draw_rect(fr.grow(2.0), Color(Neon.glow(Neon.ORANGE), 0.25))
		_overlay.draw_rect(fr, Neon.ORANGE)
	_draw_minimap(p)


## 惑星エリアの右上に、四角い枠の小さな地図。惑星は平らな円、いまの場所は小さな点。
func _draw_minimap(p: Planet) -> void:
	var area := planet_area()
	var m := 76.0
	var box := Rect2(area.end.x - m - 10.0, area.position.y + 8.0, m, m)
	var c := box.get_center()
	_overlay.draw_rect(box, Neon.BG)
	_overlay.draw_rect(box.grow(-0.5), Neon.MUTED, false, 1.0)
	var world := p.size * Planet.CELL
	var k := (m - 12.0) / world
	var pr := maxf(2.0, p.outer * k)
	_overlay.draw_circle(c, pr, p.fill_color.lightened(0.25))
	var dot: Vector2 = c + (main.focus - p.position) * k
	_overlay.draw_circle(dot, 5.0, Neon.glow(Neon.RED))
	_overlay.draw_circle(dot, 2.5, Neon.RED)


# ---------------------------------------------------------------- スキルツリー


func _open_tree() -> void:
	Audio.play("open")
	get_tree().paused = true
	var sk := GameState.skill_def(_tree_sel)
	if not sk.is_empty():
		_map_off = (sk["pos"] as Vector2) * 0.8
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


func _keep_map() -> void:
	if is_instance_valid(_map):
		_map_off = _map.offset
		_map_zoom = _map.zoom


func _build_tree() -> void:
	_keep_map()
	_clear(_tree_box)
	var gs := GameState
	_title(_tree_box, "スキルマップ", 22)
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
	var tree_w := (_tree_w() - 24.0) * 0.64 if wide else _panel_w() - 24.0
	var side_w := (_tree_w() - 24.0) - tree_w - 10.0 if wide else _panel_w() - 24.0
	var body: BoxContainer = HBoxContainer.new() if wide else VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	_tree_box.add_child(body)
	var map := SkillMap.new()
	map.custom_minimum_size = Vector2(tree_w, clampf(s.y - 150.0, 220.0, 680.0) if wide else clampf(s.y - 390.0, 200.0, 620.0))
	map.offset = _map_off
	map.zoom = _map_zoom
	map.sel = _tree_sel
	map.picked.connect(func(id: String):
		_map_off = map.offset
		_map_zoom = map.zoom
		_tree_sel = id
		_build_tree.call_deferred())
	body.add_child(map)
	_map = map
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 8)
	body.add_child(side)
	var hint := Label.new()
	hint.text = "ドラッグで移動・+/- で拡大縮小・ノードをタップで選択"
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(1, 1, 1, 0.55)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(side_w - 4.0, 0)
	side.add_child(hint)

	# 選んだスキルの詳細
	var sel := gs.skill_def(_tree_sel)
	if sel.is_empty():
		sel = gs.SKILLS[0]
	var sid := String(sel["id"])
	var detail := PanelContainer.new()
	var ds := _box(Neon.BG, Color(Neon.YELLOW, 0.8), 1)
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
		dc.text = "[color=#9BE86A]最大レベル[/color]"
	elif not gs.skill_open(sid):
		var names: PackedStringArray = []
		for l in gs.skill_links(sid):
			names.append(String(gs.skill_def(String(l))["name"]))
		dc.text = "[color=#E8504A]つながっているスキル（%s）のどれかを先に習得[/color]" % "・".join(names)
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
			Audio.play("skill")
			_keep_map()
			_build_tree())
	row.add_child(buy)
	var all := _button("まとめて強化", Vector2(bw, 48), 15)
	all.pressed.connect(func():
		var n := gs.buy_all_skills()
		_keep_map()
		_build_tree()
		toast("%d 回強化した" % n if n > 0 else "素材が足りない"))
	row.add_child(all)
	var close := _button("閉じる", Vector2(bw, 48), 17)
	close.pressed.connect(_close)
	row.add_child(close)


# ---------------------------------------------------------------- 遺物・惑星クリア・放置報酬


func _open_relics() -> void:
	Audio.play("open")
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
				_title(_msg_box, "%s ×%d\n%s" % [rd["name"], counts[id], rd["desc"]], 15, Neon.CYAN)
	var tr := gs.trait_def()
	_title(_msg_box, "惑星の特性：%s（%s）" % [tr["name"], tr["desc"]], 14, Neon.ORANGE)
	var back := _wide(_msg_box, "閉じる", 48, 17)
	back.pressed.connect(_close)
	_msg_panel.visible = true


func show_clear(extra: Dictionary, next: Array) -> void:
	_clear(_msg_box)
	var gs := GameState
	var t := int(gs.planet_time)
	_title(_msg_box, "惑星 %d を破壊した！" % gs.planet, 24, Neon.LIME)
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
	var tree := _wide(_msg_box, "先にスキルマップを見る", 44, 15)
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
	_title(_msg_box, "離れていた %s の間も採掘を続けていた\n+%s CR" % [t, GameState.fmt(gain)], 17, Neon.ORANGE)
	var ok := _wide(_msg_box, "受け取る", 52, 18)
	ok.pressed.connect(_close)
	_msg_panel.visible = true
