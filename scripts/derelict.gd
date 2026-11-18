class_name Derelict
extends Node2D
## 漂流物。近づくと開いて、ランダムな報酬（まれに罠）が出る。

var discovered: bool = false
var roll: float = 0.0
var _t: float = 0.0


func setup(data: Dictionary) -> void:
	position = data["pos"]
	roll = data["roll"]
	visible = false


## 中身を決めて返す：{"kind": 種類, "amount": 量, "text": 表示}
func open() -> Dictionary:
	var m := GameState.salvage_mult
	if roll < 0.2:
		return {"kind": "crystal", "amount": (4.0 + floor(roll * 20.0)) * m}
	elif roll < 0.4:
		return {"kind": "fuel", "amount": 30.0 * m}
	elif roll < 0.55:
		return {"kind": "plate", "amount": 12.0 * m}
	elif roll < 0.7:
		return {"kind": "kit", "amount": m}
	elif roll < 0.85:
		return {"kind": "map", "amount": 0.0}
	return {"kind": "trap", "amount": 15.0}


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var blink := 0.5 + 0.5 * sin(_t * 5.0)
	rotation = _t * 0.4
	draw_rect(Rect2(-14, -14, 28, 28), Color(0.25, 0.3, 0.35))
	draw_rect(Rect2(-14, -14, 28, 28), Color(0.7, 0.85, 1.0), false, 2.0)
	draw_circle(Vector2.ZERO, 4.0, Color(1.0, 1.0, 0.5, blink))
	draw_arc(Vector2.ZERO, 26.0 + blink * 6.0, 0.0, TAU, 32, Color(1.0, 1.0, 0.6, 0.25 * blink), 2.0)
