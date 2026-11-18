class_name WarpGate
extends Node2D
## 次のセクターへ進むためのワープゲート。行き先の種類と報酬を表示する。

var discovered: bool = false
var next_type: String = "standard"
var rich: bool = false
var _t: float = 0.0
var _label: Label


func setup(data: Dictionary) -> void:
	position = data["pos"]
	next_type = data["next_type"]
	rich = data["rich"]
	discovered = false
	visible = false
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 5)
	_label.size = Vector2(260, 60)
	_label.position = Vector2(-130, 56)
	add_child(_label)
	_refresh_label()


func perk_count() -> int:
	return 4 if rich else 2


func _refresh_label() -> void:
	if GameState.is_final_sector():
		_label.text = "最終ゲート\nくぐれば帰還成功"
	else:
		_label.text = "行き先：%s\n強化 %d択" % [SectorGenerator.type_name(next_type), perk_count()]


func color() -> Color:
	if GameState.is_final_sector():
		return Color(1.0, 0.9, 0.3)
	return Color(1.0, 0.75, 0.3) if rich else Color(0.3, 1.0, 0.6)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var c := color()
	var pulse := 0.5 + 0.5 * sin(_t * 3.0)
	var r := 54.0 if rich else 46.0
	draw_arc(Vector2.ZERO, r, _t, _t + TAU * 0.8, 48, c, 4.0)
	draw_arc(Vector2.ZERO, r - 12.0, -_t * 1.5, -_t * 1.5 + TAU * 0.6, 48, Color(c, 0.7), 3.0)
	draw_circle(Vector2.ZERO, 14.0 + pulse * 6.0, Color(c.lightened(0.4), 0.5))
