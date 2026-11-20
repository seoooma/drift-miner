extends CanvasLayer
## 画面の質感（Autoload）。いちばん上の層に、ごく弱い走査線と周辺減光を乗算で重ねる（shaders/screen.gdshader）。
## 入力は受けない。一時停止中も表示し続ける。

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	var r := ColorRect.new()
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/screen.gdshader")
	r.material = m
	add_child(r)
