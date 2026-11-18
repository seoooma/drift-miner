extends CanvasLayer
## 画面表示。資源・燃料・操作説明・メッセージ・パーク選択・ゲームオーバー。

var main: Node = null

var _info: Label
var _help: Label
var _toast: Label
var _toast_time: float = 0.0
var _perk_panel: PanelContainer
var _perk_box: VBoxContainer
var _over_panel: PanelContainer
var _over_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_info = Label.new()
	_info.position = Vector2(16, 12)
	_info.add_theme_font_size_override("font_size", 18)
	add_child(_info)

	_help = Label.new()
	_help.text = "WASD:移動  左クリック長押し:採掘  B:自動採掘機を設置  E:ワープ（ゲート付近）"
	_help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_help.position = Vector2(16, -36)
	_help.modulate = Color(1, 1, 1, 0.7)
	add_child(_help)

	_toast = Label.new()
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.position.y = 80
	_toast.add_theme_font_size_override("font_size", 22)
	add_child(_toast)

	_perk_panel = _make_panel()
	_perk_box = VBoxContainer.new()
	_perk_box.add_theme_constant_override("separation", 10)
	_perk_panel.add_child(_perk_box)

	_over_panel = _make_panel()
	_over_label = Label.new()
	_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_label.add_theme_font_size_override("font_size", 24)
	_over_panel.add_child(_over_label)


func _make_panel() -> PanelContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(panel)
	panel.visible = false
	return panel


func _process(delta: float) -> void:
	var gs := GameState
	var lines: PackedStringArray = [
		"セクター %d" % gs.sector,
		"燃料 %d / %d" % [int(gs.fuel), int(gs.max_fuel)],
		"鉄 %d   結晶 %d" % [int(gs.res["iron"]), int(gs.res["crystal"])],
		"採掘機コスト：%s" % gs.cost_text(gs.miner_cost()),
		"ワープ費用：%s" % gs.cost_text(gs.warp_cost()),
	]
	_info.text = "\n".join(lines)
	_info.modulate = Color(1, 0.4, 0.4) if gs.fuel < 20.0 else Color.WHITE

	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)


func toast(text: String) -> void:
	_toast.text = text
	_toast_time = 2.5


func show_perk_choice(options: Array) -> void:
	for c in _perk_box.get_children():
		c.queue_free()
	var title := Label.new()
	title.text = "ワープ成功！強化を1つ選んでください"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	_perk_box.add_child(title)
	for p in options:
		var b := Button.new()
		b.text = "%s\n%s" % [p["name"], p["desc"]]
		b.custom_minimum_size = Vector2(0, 64)
		b.pressed.connect(_on_perk_pressed.bind(String(p["id"])))
		_perk_box.add_child(b)
	_perk_panel.visible = true


func _on_perk_pressed(id: String) -> void:
	_perk_panel.visible = false
	main.on_perk_chosen(id)


func show_game_over(reason: String) -> void:
	_over_label.text = "ゲームオーバー：%s\n到達セクター：%d\n\nRキーでリスタート" % [reason, GameState.sector]
	_over_panel.visible = true


func hide_panels() -> void:
	_perk_panel.visible = false
	_over_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if _over_panel.visible and event is InputEventKey and event.pressed and event.physical_keycode == KEY_R:
		main.restart()
