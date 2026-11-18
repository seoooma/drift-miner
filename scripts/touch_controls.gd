extends CanvasLayer
## スマホ用のタッチ操作。
## 画面左側：バーチャルスティックで移動。右側：押した場所の近くの小惑星を採掘（吸い付き照準）。
## 右端のボタン：ワープ。建設モード中は、タップした場所に建物を置く。使えないときは半透明、使えるときは光る。
## タッチが一度でも検出されると有効になり、以後プレイヤーはマウスの代わりにこちらを読む。

const STICK_RADIUS := 80.0
const STICK_AREA := 0.4  # 画面幅のうちスティック用に使う左側の割合

var main: Node = null
var active: bool = false
var move_vector := Vector2.ZERO
var aiming: bool = false
var aim_screen := Vector2.ZERO

var _stick_index: int = -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _aim_index: int = -1
var _draw_node: Node2D
var _buttons: Dictionary = {}


func _ready() -> void:
	active = DisplayServer.is_touchscreen_available()
	_draw_node = Node2D.new()
	add_child(_draw_node)
	_draw_node.draw.connect(_on_draw)
	_buttons["warp"] = _make_button("ワープ", -50.0)
	_set_visible(active)


func _make_button(text: String, y: float) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 28)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.12)
	sb.border_color = Color(1, 1, 1, 0.5)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(20)
	l.add_theme_stylebox_override("normal", sb)
	l.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	l.offset_left = -200
	l.offset_right = -24
	l.offset_top = y
	l.offset_bottom = y + 100
	l.pivot_offset = Vector2(88, 50)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _set_visible(v: bool) -> void:
	_draw_node.visible = v
	for b in _buttons.values():
		b.visible = v


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if not active:
			active = true
			_set_visible(true)
		if event.pressed:
			for id in _buttons:
				var b: Label = _buttons[id]
				if b.get_global_rect().grow(12.0).has_point(event.position):
					_press_button(id, b)
					get_viewport().set_input_as_handled()
					return
			if main != null and main.hud.is_over_ui(event.position):
				return
			var w := get_viewport().get_visible_rect().size.x
			if main != null and main.placing != "" and event.position.x >= w * STICK_AREA:
				main.try_place_at(get_viewport().get_canvas_transform().affine_inverse() * event.position)
				get_viewport().set_input_as_handled()
				return
			if event.position.x < w * STICK_AREA and _stick_index == -1:
				_stick_index = event.index
				_stick_origin = event.position
				_stick_pos = event.position
				move_vector = Vector2.ZERO
			elif _aim_index == -1:
				_aim_index = event.index
				aiming = true
				aim_screen = event.position
		else:
			_release(event.index)
	elif event is InputEventScreenDrag:
		if event.index == _stick_index:
			_stick_pos = event.position
			var d: Vector2 = _stick_pos - _stick_origin
			move_vector = (d / STICK_RADIUS).limit_length(1.0)
			if d.length() < 12.0:
				move_vector = Vector2.ZERO
		elif event.index == _aim_index:
			aim_screen = event.position


func _release(index: int) -> void:
	if index == _stick_index:
		_stick_index = -1
		move_vector = Vector2.ZERO
	if index == _aim_index:
		_aim_index = -1
		aiming = false


## 一時停止（パーク選択など）をまたいだときにタッチ状態を消す。
func reset() -> void:
	_release(_stick_index)
	_release(_aim_index)


func _press_button(id: String, b: Label) -> void:
	var t := b.create_tween()
	b.scale = Vector2(0.88, 0.88)
	t.tween_property(b, "scale", Vector2.ONE, 0.15)
	if main == null:
		return
	match id:
		"warp":
			main.try_warp()


func aim_world() -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * aim_screen


func _process(_delta: float) -> void:
	if not active or main == null:
		return
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
	var can_warp: bool = main.gate_in_range() != null and GameState.can_afford(GameState.warp_cost())
	_style(_buttons["warp"], can_warp, Color(0.3, 1.0, 0.6), pulse)
	_draw_node.queue_redraw()


func _style(b: Label, enabled: bool, col: Color, pulse: float) -> void:
	b.modulate.a = 1.0 if enabled else 0.4
	var sb: StyleBoxFlat = b.get_theme_stylebox("normal")
	sb.border_color = col if enabled else Color(1, 1, 1, 0.5)
	sb.bg_color = Color(col, 0.15 + 0.2 * pulse) if enabled else Color(1, 1, 1, 0.1)


func _on_draw() -> void:
	var size := get_viewport().get_visible_rect().size
	var base := _stick_origin if _stick_index != -1 else Vector2(160, size.y - 170)
	var knob := base + move_vector * STICK_RADIUS
	_draw_node.draw_circle(base, STICK_RADIUS, Color(1, 1, 1, 0.08))
	_draw_node.draw_arc(base, STICK_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.3), 2.0)
	_draw_node.draw_circle(knob, 30.0, Color(1, 1, 1, 0.35))
	if aiming:
		_draw_node.draw_arc(aim_screen, 20.0, 0.0, TAU, 24, Color(1.0, 1.0, 1.0, 0.3), 2.0)
