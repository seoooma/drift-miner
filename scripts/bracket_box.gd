class_name BracketBox
extends StyleBox
## ボタンの枠：黒い長方形に細い枠線、左上と右下に HUD 風の角かっこ（L 字の差し色）。
## 角は丸めず、塗りに光は付けない。角かっこにだけ薄いにじみを重ねる。

var fill := Neon.BG
var border := Neon.MUTED
var border_w := 1.0
var accent := Neon.CYAN
var arm := 8.0
var accent_w := 2.0


func _init(f: Color = Neon.BG, b: Color = Neon.MUTED, a: Color = Neon.CYAN) -> void:
	fill = f
	border = b
	accent = a
	content_margin_left = 10
	content_margin_right = 10
	content_margin_top = 6
	content_margin_bottom = 6


func _draw(ci: RID, rect: Rect2) -> void:
	var rs := RenderingServer
	if fill.a > 0.0:
		rs.canvas_item_add_rect(ci, rect, fill)
	if border.a > 0.0 and border_w > 0.0:
		var r := rect.grow(-border_w * 0.5)
		var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position])
		rs.canvas_item_add_polyline(ci, pts, PackedColorArray([border]), border_w)
	if accent.a > 0.0:
		var p := rect.position
		var e := rect.end
		var h := accent_w * 0.5
		var g := Neon.glow(accent)
		for col_w in [[g, accent_w * 3.0], [accent, accent_w]]:
			var c: Color = col_w[0]
			var w: float = col_w[1]
			rs.canvas_item_add_line(ci, Vector2(p.x + h, p.y), Vector2(p.x + h, p.y + arm), c, w)
			rs.canvas_item_add_line(ci, Vector2(p.x, p.y + h), Vector2(p.x + arm, p.y + h), c, w)
			rs.canvas_item_add_line(ci, Vector2(e.x - h, e.y), Vector2(e.x - h, e.y - arm), c, w)
			rs.canvas_item_add_line(ci, Vector2(e.x, e.y - h), Vector2(e.x - arm, e.y - h), c, w)
