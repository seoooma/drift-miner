class_name SkillMap
extends Control
## スキルマップの表示。基地を中心に5系統が放射状に広がる網の目を描く。
## ドラッグで動かし、ホイール・ピンチ・+/- ボタンで拡大縮小、ノードをタップで選ぶ。

signal picked(id: String)

const NOTABLE_R := 19.0
const MINOR_R := 10.0
const LIMIT := 980.0

var sel: String = ""
var offset := Vector2.ZERO  # 画面の中央に来るマップ座標
var zoom: float = 0.8

var _press := false
var _moved: float = 0.0
var _last := Vector2.ZERO
var _t: float = 0.0
var _touches := {}
var _pinch_d: float = 0.0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	for spec in [["+", 1.25], ["-", 0.8]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(40, 40)
		b.focus_mode = Control.FOCUS_NONE
		var f: float = spec[1]
		b.pressed.connect(func(): _zoom_by(f))
		add_child(b)
	resized.connect(_place_buttons)
	_place_buttons()


func _place_buttons() -> void:
	var k := 0
	for c in get_children():
		if c is Button:
			(c as Button).position = Vector2(size.x - 48.0, 8.0 + k * 46.0)
			k += 1


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_t += delta
		queue_redraw()


func _zoom_by(f: float) -> void:
	zoom = clampf(zoom * f, 0.4, 1.8)
	queue_redraw()


func _to_screen(p: Vector2) -> Vector2:
	return size * 0.5 + (p - offset) * zoom


func _node_r(sk: Dictionary) -> float:
	return (MINOR_R if String(sk["stat"]) != "" else NOTABLE_R) * (1.25 if sk["id"] == "base" else 1.0)


func _pan(d: Vector2) -> void:
	offset -= d / zoom
	offset = offset.clamp(Vector2(-LIMIT, -LIMIT), Vector2(LIMIT, LIMIT))
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	# 2本指のピンチ（スマホ）
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		_pinch_d = 0.0
		if _touches.size() >= 2:
			_press = false
		return
	if event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() >= 2:
			var ks := _touches.keys()
			var d := (_touches[ks[0]] as Vector2).distance_to(_touches[ks[1]])
			if _pinch_d > 0.0:
				_zoom_by(d / _pinch_d)
			_pinch_d = d
		return
	if event is InputEventMagnifyGesture:
		_zoom_by(event.factor)
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_by(1.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_by(0.9)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_press = _touches.size() < 2
				_moved = 0.0
				_last = event.position
			else:
				if _press and _moved < 12.0:
					_pick_at(event.position)
				_press = false
		accept_event()
	elif event is InputEventMouseMotion and _press:
		var d: Vector2 = event.position - _last
		_last = event.position
		_moved += d.length()
		if _moved >= 12.0:
			_pan(d)
		accept_event()


func _pick_at(p: Vector2) -> void:
	var best := ""
	var best_d := INF
	for sk in GameState.SKILLS:
		var d := _to_screen(sk["pos"]).distance_to(p)
		if d < maxf(_node_r(sk) * zoom + 8.0, 22.0) and d < best_d:
			best = String(sk["id"])
			best_d = d
	if best != "":
		sel = best
		picked.emit(best)


func _branch_col(sk: Dictionary) -> Color:
	var br := String(sk["branch"])
	if GameState.BRANCHES.has(br):
		return GameState.BRANCHES[br]["color"]
	return Color(0.85, 0.9, 1.0)


func _draw() -> void:
	var gs := GameState
	var font := get_theme_font("font", "Label")
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.025, 0.05))
	# 背景の同心円（輪）
	var c0 := _to_screen(Vector2.ZERO)
	for k in range(1, 9):
		draw_arc(c0, k * 118.0 * zoom, 0.0, TAU, 96, Color(1, 1, 1, 0.035), 1.0)
	# 系統の名前
	for br in gs.BRANCHES:
		var d: Dictionary = gs.BRANCHES[br]
		var p := _to_screen(Vector2.from_angle(deg_to_rad(float(d["angle"]))) * 118.0 * 8.0)
		var txt := String(d["name"])
		var fs := int(18 * clampf(zoom, 0.7, 1.3))
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		draw_string(font, p - Vector2(w * 0.5, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(d["color"], 0.7))
	# つながり
	for sk in gs.SKILLS:
		var a := String(sk["id"])
		for l in sk["links"]:
			var b := String(l)
			var la := gs.skill_level(a) > 0
			var lb := gs.skill_level(b) > 0
			var col := Color(0.35, 0.38, 0.45, 0.45)
			var w := 2.0
			if la and lb:
				col = _branch_col(sk).lerp(Color.WHITE, 0.2)
				w = 3.5
			elif la or lb:
				col = Color(0.6, 0.75, 0.95, 0.7)
				w = 2.5
			draw_line(_to_screen(sk["pos"]), _to_screen(gs.skill_def(b)["pos"]), col, w * clampf(zoom, 0.6, 1.4), true)
	# ノード
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	for sk in gs.SKILLS:
		var id := String(sk["id"])
		var p := _to_screen(sk["pos"])
		var r := _node_r(sk) * zoom
		if p.x < -r * 4.0 or p.y < -r * 4.0 or p.x > size.x + r * 4.0 or p.y > size.y + r * 4.0:
			continue
		var lv := gs.skill_level(id)
		var mx := int(sk["max"])
		var open := gs.skill_open(id)
		var bc := _branch_col(sk)
		var fill := Color(0.06, 0.07, 0.1)
		if lv > 0:
			fill = bc.darkened(0.45)
		draw_circle(p, r, fill)
		var ring := Color(0.3, 0.32, 0.38)
		var rw := 2.0
		if lv >= mx:
			ring = bc.lightened(0.3)
			rw = 3.0
		elif gs.can_buy_skill(id):
			ring = Color(0.45, 0.85, 1.0).lerp(Color.WHITE, pulse * 0.5)
			rw = 3.0
		elif open:
			ring = Color(0.65, 0.7, 0.8)
		draw_arc(p, r, 0.0, TAU, 32, ring, rw, true)
		# 途中のレベルは弧で見せる
		if lv > 0 and lv < mx:
			draw_arc(p, r + 4.0, -PI * 0.5, -PI * 0.5 + TAU * lv / mx, 32, bc.lightened(0.3), 2.5, true)
		if id == sel:
			draw_arc(p, r + 8.0, 0.0, TAU, 40, Color(1.0, 0.9, 0.4), 2.5, true)
		var alpha := 1.0 if open or lv > 0 else 0.45
		if String(sk["stat"]) == "":
			var fs := int(12 * clampf(zoom, 0.75, 1.3))
			var name := String(sk["name"])
			var w := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string_outline(font, p + Vector2(-w * 0.5, r + fs + 4.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.9))
			draw_string(font, p + Vector2(-w * 0.5, r + fs + 4.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, alpha))
			if mx == 1 and lv > 0:
				draw_circle(p, r * 0.3, Color(1, 1, 1, 0.9))
			var lt := "%d" % lv if mx > 1 else ""
			if lt != "":
				var lw := font.get_string_size(lt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				draw_string(font, p + Vector2(-lw * 0.5, fs * 0.35), lt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, alpha))
