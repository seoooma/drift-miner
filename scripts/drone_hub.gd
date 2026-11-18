class_name DroneHub
extends Node2D
## ドローンハブ。範囲内の採掘機から鉱石を取りに行き、母船へ運ぶ。
## ハブの位置・母船までの距離・採掘機の数のバランスで輸送量が決まる。

const RANGE := 480.0
const CARRY := 10.0
const SPEED := 230.0

var btype: String = "hub"
var main: Node = null
var drones: Array = []  # 各要素：{"pos", "state", "target", "load", "kind"}
var _t: float = 0.0


func _ready() -> void:
	for i in GameState.drones_per_hub():
		drones.append({"pos": global_position, "state": "idle", "target": null, "load": 0.0, "kind": ""})


func _process(delta: float) -> void:
	_t += delta
	if not GameState.alive or main == null:
		return
	var speed := SPEED * GameState.drone_speed_mult
	var core_pos: Vector2 = main.core.global_position
	for d in drones:
		match String(d["state"]):
			"idle":
				var m: Miner = _pick_miner()
				if m != null:
					m.reserved += CARRY
					d["target"] = m
					d["state"] = "to_miner"
				else:
					d["pos"] = (d["pos"] as Vector2).move_toward(global_position, speed * delta)
			"to_miner":
				var m = d["target"]
				if m == null or not is_instance_valid(m) or m.is_queued_for_deletion():
					d["state"] = "idle"
					continue
				d["pos"] = (d["pos"] as Vector2).move_toward(m.global_position, speed * delta)
				if (d["pos"] as Vector2).distance_to(m.global_position) < 4.0:
					d["load"] = m.take(CARRY)
					d["kind"] = m.kind
					m.reserved = maxf(0.0, m.reserved - CARRY)
					d["target"] = null
					d["state"] = "to_core" if float(d["load"]) > 0.0 else "idle"
			"to_core":
				d["pos"] = (d["pos"] as Vector2).move_toward(core_pos, speed * delta)
				if (d["pos"] as Vector2).distance_to(core_pos) < 6.0:
					GameState.add_ore(String(d["kind"]), float(d["load"]))
					d["load"] = 0.0
					d["state"] = "idle"
	queue_redraw()


func _pick_miner() -> Miner:
	var best: Miner = null
	var best_amt := 2.0
	for m in main.miners():
		var mm := m as Miner
		if mm.global_position.distance_to(global_position) > RANGE:
			continue
		var avail := mm.stored - mm.reserved
		if avail > best_amt:
			best = mm
			best_amt = avail
	return best


func release() -> void:
	for d in drones:
		var m = d["target"]
		if m != null and is_instance_valid(m):
			m.reserved = maxf(0.0, m.reserved - CARRY)


func _draw() -> void:
	draw_arc(Vector2.ZERO, RANGE, 0.0, TAU, 96, Color(1.0, 0.9, 0.5, 0.12), 2.0)
	var body := PackedVector2Array([Vector2(0, -18), Vector2(16, 0), Vector2(0, 18), Vector2(-16, 0)])
	draw_colored_polygon(body, Color(0.35, 0.3, 0.15))
	var o := body.duplicate()
	o.append(body[0])
	draw_polyline(o, Color(1.0, 0.85, 0.4), 2.0)
	for d in drones:
		var p := to_local(d["pos"])
		var loaded: bool = float(d["load"]) > 0.0
		var c: Color = Asteroid.COLORS.get(String(d["kind"]), Color.WHITE) if loaded else Color(1.0, 0.9, 0.6)
		draw_circle(p, 5.0 if loaded else 3.5, c)
		draw_arc(p, 8.0, _t * 6.0, _t * 6.0 + 2.0, 6, Color(1, 1, 1, 0.5), 1.5)
