extends CanvasLayer
## スマホ用のタッチ操作。
## 画面左側：バーチャルスティックで移動。右側：押している場所を採掘。
## 右下のボタン：採掘機の設置とワープ。
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
	_buttons["warp"] = _make_button("ワープ", Vector2(-380, -130))
	_buttons["miner"] = _make_button("採掘機\n設置", Vector2(-190, -130))
	_set_visible(active)


func _make_button(text: String, offset: Vector2) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 22)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.12)
	sb.border_color = Color(1, 1, 1, 0.4)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(16)
	l.add_theme_stylebox_override("normal", sb)
	l.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	l.offset_left = offset.x
	l.offset_top = offset.y
	l.offset_right = offset.x + 170
	l.offset_bottom = offset.y + 100
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
				if (_buttons[id] as Label).get_global_rect().has_point(event.position):
					_press_button(id)
					get_viewport().set_input_as_handled()
					return
			var w := get_viewport().get_visible_rect().size.x
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


func _press_button(id: String) -> void:
	if main == null:
		return
	match id:
		"miner":
			main.try_place_miner_nearest()
		"warp":
			main.try_warp()


func aim_world() -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * aim_screen


func _process(_delta: float) -> void:
	if active:
		_draw_node.queue_redraw()


func _on_draw() -> void:
	var size := get_viewport().get_visible_rect().size
	var base := _stick_origin if _stick_index != -1 else Vector2(150, size.y - 150)
	var knob := base + move_vector * STICK_RADIUS
	_draw_node.draw_circle(base, STICK_RADIUS, Color(1, 1, 1, 0.08))
	_draw_node.draw_arc(base, STICK_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.3), 2.0)
	_draw_node.draw_circle(knob, 30.0, Color(1, 1, 1, 0.35))
	if aiming:
		_draw_node.draw_arc(aim_screen, 36.0, 0.0, TAU, 32, Color(1.0, 0.6, 0.3, 0.7), 3.0)
