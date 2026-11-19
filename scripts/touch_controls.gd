extends CanvasLayer
## スマホ判定だけを受け持つ。オートモードでは移動や照準の操作は無く、
## プレイヤーはカード・航路・速度のボタンを押すだけなので、スティックは置かない。

var main: Node = null
var active: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	active = DisplayServer.is_touchscreen_available() or "--touch" in OS.get_cmdline_user_args()


func reset() -> void:
	pass
