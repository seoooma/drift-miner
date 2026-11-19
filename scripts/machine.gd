class_name Machine
extends Node2D
## 工場。母船の倉庫から材料を取り、一定時間で製品を倉庫に戻す。

const SIZE := 30.0

var btype: String = "smelter"
var recipe: Dictionary = {}
var progress: float = 0.0
var working: bool = false
var status: String = "待機"
var _label: Label


func setup(type_id: String) -> void:
	btype = type_id
	recipe = GameState.BUILDINGS[btype]["recipe"]
	_label = Label.new()
	_label.text = String(GameState.BUILDINGS[btype]["name"])
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 4)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.size = Vector2(120, 24)
	_label.position = Vector2(-60, SIZE * 0.5 + 4)
	add_child(_label)


func out_color() -> Color:
	var out: Dictionary = recipe["out"]
	return GameState.ITEMS[out.keys()[0]]["color"]


func _process(delta: float) -> void:
	if not GameState.alive:
		return
	if not working:
		var need: Dictionary = recipe["in"]
		if GameState.pay(need):
			working = true
			progress = 0.0
			status = "稼働中"
		else:
			status = "材料不足"
	if working:
		progress += delta * GameState.speed_of(btype) / float(recipe["time"])
		if progress >= 1.0:
			var out: Dictionary = recipe["out"]
			for k in out:
				GameState.add_item(k, float(out[k]))
				GameState.note_produced(k, float(out[k]))
			working = false
			progress = 0.0
	queue_redraw()


func _draw() -> void:
	var c := out_color()
	var r := Rect2(-SIZE * 0.5, -SIZE * 0.5, SIZE, SIZE)
	draw_rect(r, c.darkened(0.7))
	draw_rect(r, c if working else Color(c, 0.4), false, 2.0)
	if working:
		draw_arc(Vector2.ZERO, SIZE * 0.32, -PI / 2, -PI / 2 + TAU * progress, 24, c, 4.0)
	else:
		# 材料不足：黄色の点滅
		var a := 0.4 + 0.4 * sin(Time.get_ticks_msec() * 0.008)
		draw_circle(Vector2(SIZE * 0.5, -SIZE * 0.5), 5.0, Color(1.0, 0.8, 0.2, a))
