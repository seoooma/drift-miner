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
		b.custom_minimum_size = Vector2(44, 44)
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
			(c as Button).position = Vector2(size.x - 52.0, 8.0 + k * 50.0)
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
	var font := Neon.font()
	draw_rect(Rect2(Vector2.ZERO, size), Neon.BG)
	# 背景の方眼（薄い 1px の線）
	var c0 := _to_screen(Vector2.ZERO)
	var step := 40.0 * zoom
	var gc := Color(1, 1, 1, 0.04)
	var gx := fposmod(c0.x, step)
	while gx < size.x:
		draw_rect(Rect2(floorf(gx), 0, 1, size.y), gc)
		gx += step
	var gy := fposmod(c0.y, step)
	while gy < size.y:
		draw_rect(Rect2(0, floorf(gy), size.x, 1), gc)
		gy += step
	# 系統の名前
	for br in gs.BRANCHES:
		var d: Dictionary = gs.BRANCHES[br]
		var p := _to_screen(Vector2.from_angle(deg_to_rad(float(d["angle"]))) * 118.0 * 8.0)
		var txt := String(d["name"])
		var fs := int(16 * clampf(zoom, 0.7, 1.3))
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		draw_string(font, p - Vector2(w * 0.5, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(d["color"], 0.8))
	# つながり（細い線。習得済み同士は系統の色で、薄いにじみを付ける）
	for sk in gs.SKILLS:
		var a := String(sk["id"])
		for l in sk["links"]:
			var b := String(l)
			var la := gs.skill_level(a) > 0
			var lb := gs.skill_level(b) > 0
			var pa := _to_screen(sk["pos"])
			var pb := _to_screen(gs.skill_def(b)["pos"])
			if la and lb:
				var col := _branch_col(sk)
				draw_line(pa, pb, Neon.glow(col), 5.0)
				draw_line(pa, pb, col, 1.5)
			elif la or lb:
				draw_line(pa, pb, Color(Neon.LINE, 0.55), 1.0)
			else:
				draw_line(pa, pb, Color(Neon.MUTED, 0.35), 1.0)
	# ノード：黒い四角に細い枠。習得済みは系統の色、買えるものは点滅する水色。
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
		var rect := Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0)
		draw_rect(rect, Neon.BG)
		var ring := Color(Neon.MUTED, 0.6)
		var rw := 1.0
		if lv >= mx:
			ring = bc
			rw = 2.0
		elif gs.can_buy_skill(id):
			ring = Neon.CYAN.lerp(Color.WHITE, pulse * 0.4)
			rw = 2.0
		elif lv > 0:
			ring = bc
			rw = 1.5
		elif open:
			ring = Color(Neon.LINE, 0.8)
		if rw >= 1.5:
			draw_rect(rect, Neon.glow(ring), false, rw * 3.0)
		draw_rect(rect.grow(-rw * 0.5), ring, false, rw)
		# 小さな四角い色見本（左上）
		var chip := maxf(3.0, r * 0.3)
		draw_rect(Rect2(rect.position + Vector2(3, 3), Vector2(chip, chip)), Color(bc, 1.0 if lv > 0 else 0.35))
		if lv > 0:
			var inner := rect.grow(-r * 0.45)
			draw_rect(inner, Color(bc, 0.85 if lv >= mx else 0.45))
		if id == sel:
			Neon.brackets(self, rect.grow(6.0), Neon.YELLOW, r * 0.7, 2.0)
		var alpha := 1.0 if open or lv > 0 else 0.45
		if String(sk["stat"]) == "":
			var fs := int(11 * clampf(zoom, 0.8, 1.3))
			var name := String(sk["name"])
			var w := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var tp := p + Vector2(-w * 0.5, r + fs + 4.0)
			draw_string(font, tp + Vector2(1, 1), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Neon.SHADOW)
			draw_string(font, tp, name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(Neon.TEXT, alpha))
			if mx > 1:
				var lt := "%d/%d" % [lv, mx]
				var lfs := int(10 * clampf(zoom, 0.8, 1.3))
				var lw := font.get_string_size(lt, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs).x
				draw_string(font, Vector2(rect.end.x - lw - 2.0, rect.position.y - 3.0), lt, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs, Color(Neon.CYAN, alpha))
