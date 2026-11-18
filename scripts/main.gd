extends Node2D
## ゲーム全体の進行。セクター生成、探索（霧）、採掘機、危険、漂流物、ワープを管理する。

const WORLD_RADIUS := 2200.0
const BASE_SCAN := 420.0
const GATE_RANGE := 140.0
const WARP_REFUEL := 30.0
const SALVAGE_PER_MINER := 4.0
const ZONE_BURN := 2.5
const DERELICT_RANGE := 60.0

const StarfieldScript := preload("res://scripts/starfield.gd")
const HudScript := preload("res://scripts/hud.gd")
const TouchScript := preload("res://scripts/touch_controls.gd")

var starfield: Node2D
var asteroid_layer: Node2D
var object_layer: Node2D
var miner_layer: Node2D
var fx_layer: Node2D
var player: Player
var hud: CanvasLayer
var touch: CanvasLayer
var gates: Array = []

var _meteor_timer: float = 0.0
var _rng := RandomNumberGenerator.new()
var _pending_gate: WarpGate = null
var _tips_shown := {}


func _ready() -> void:
	randomize()
	GameState.new_run()

	starfield = StarfieldScript.new()
	starfield.world_radius = WORLD_RADIUS
	add_child(starfield)

	asteroid_layer = Node2D.new()
	add_child(asteroid_layer)
	object_layer = Node2D.new()
	add_child(object_layer)
	miner_layer = Node2D.new()
	add_child(miner_layer)

	player = Player.new()
	player.main = self
	player.world_radius = WORLD_RADIUS
	add_child(player)

	fx_layer = Node2D.new()
	add_child(fx_layer)

	touch = TouchScript.new()
	touch.main = self
	add_child(touch)
	player.touch = touch

	hud = HudScript.new()
	hud.main = self
	add_child(hud)

	GameState.run_over.connect(_on_run_over)
	build_sector()


func build_sector() -> void:
	for layer in [asteroid_layer, object_layer, miner_layer, fx_layer]:
		for c in layer.get_children():
			c.queue_free()
	gates.clear()
	GameState.start_sector()
	_rng.seed = GameState.sector_seed() + 7

	var data := SectorGenerator.generate(GameState.sector_seed(), GameState.sector, GameState.sector_type, WORLD_RADIUS)
	for d in data["asteroids"]:
		var a := Asteroid.new()
		a.setup(d)
		a.depleted.connect(_on_asteroid_depleted)
		asteroid_layer.add_child(a)
	var gate_data: Array = data["gates"]
	if GameState.is_final_sector():
		gate_data = [gate_data[1]]  # 最終セクターは遠いゲート1つだけ
	for g in gate_data:
		var gate := WarpGate.new()
		object_layer.add_child(gate)
		gate.setup(g)
		gates.append(gate)
		if GameState.oracle:
			_discover_gate(gate, false)
	for d in data["derelicts"]:
		var dr := Derelict.new()
		dr.setup(d)
		object_layer.add_child(dr)

	var info: Dictionary = SectorGenerator.TYPES[GameState.sector_type]
	starfield.regenerate(GameState.sector_seed(), info["tint"], data["zones"])

	player.position = Vector2.ZERO
	player.velocity = Vector2.ZERO
	_meteor_timer = _next_meteor_delay()

	var title := "セクター %d：%s" % [GameState.sector, info["name"]]
	if GameState.is_final_sector():
		title = "最終セクター %d：%s" % [GameState.sector, info["name"]]
	var desc := String(info["desc"])
	hud.banner(title, desc)


func scan_radius() -> float:
	var r := BASE_SCAN * GameState.scan_mult
	if GameState.sector_type == "nebula":
		r *= 0.65
	return r


func _next_meteor_delay() -> float:
	if GameState.sector <= 1:
		return INF
	var base := maxf(10.0, 28.0 - GameState.sector * 1.8)
	if GameState.sector_type == "radiation":
		base *= 0.7
	return _rng.randf_range(base * 0.7, base * 1.3)


func _process(delta: float) -> void:
	if not GameState.alive:
		return
	GameState.sector_time += delta

	# 探索：スキャン範囲に入ったものだけ見えるようになる
	var scan := scan_radius()
	for a in asteroid_layer.get_children():
		var ast := a as Asteroid
		if not ast.discovered and ast.position.distance_to(player.position) < scan + ast.radius:
			ast.discovered = true
			ast.visible = true
	for o in object_layer.get_children():
		if o is WarpGate:
			var g := o as WarpGate
			if not g.discovered and g.position.distance_to(player.position) < scan + 50.0:
				_discover_gate(g, true)
		elif o is Derelict:
			var d := o as Derelict
			if not d.discovered and d.position.distance_to(player.position) < scan:
				d.discovered = true
				d.visible = true
				_tip("derelict", "漂流物を発見。近づくと中身を回収できます")
			if d.discovered and d.position.distance_to(player.position) < DERELICT_RANGE:
				_open_derelict(d)

	if starfield.in_zone(player.position):
		_tip("zone", "放射線域！燃料の減りが速くなります")

	# 隕石
	_meteor_timer -= delta
	if _meteor_timer <= 0.0:
		_spawn_meteor()
		_meteor_timer = _next_meteor_delay()

	_update_tips()


func _discover_gate(g: WarpGate, announce: bool) -> void:
	g.discovered = true
	g.visible = true
	if announce:
		if GameState.is_final_sector():
			hud.toast("最終ゲートを発見！")
		elif g.rich:
			hud.toast("遠方ゲートを発見：%s・強化4択" % SectorGenerator.type_name(g.next_type))
		else:
			hud.toast("ゲートを発見：%s・強化2択" % SectorGenerator.type_name(g.next_type))


func _tip(id: String, text: String) -> void:
	if _tips_shown.has(id):
		return
	_tips_shown[id] = true
	hud.toast(text, 3.5)


func _update_tips() -> void:
	if GameState.runs_played > 0:
		return
	var t := GameState.sector_time
	if GameState.sector == 1:
		if t > 4.0:
			_tip("mine", "小惑星を長押しで採掘。水色の氷は燃料になります")
		if t > 14.0 and float(GameState.res["iron"]) >= 10.0:
			_tip("miner", "鉄が貯まりました。採掘機を置くと自動で掘ります")
		if t > 30.0 and not miners().is_empty():
			_tip("collect", "採掘機は満杯で止まります。近くを通ると回収できます")
	if t > GameState.instability_grace - 10.0:
		_tip("instab", "まもなく宙域が不安定化。燃料の減りが加速します")


func _open_derelict(d: Derelict) -> void:
	var r := d.open()
	var pos := d.global_position
	var col := Color(1.0, 1.0, 0.6)
	match String(r["kind"]):
		"crystal":
			GameState.res["crystal"] = float(GameState.res["crystal"]) + float(r["amount"])
			hud.toast("漂流物：結晶 +%d" % int(r["amount"]))
			col = Asteroid.COLORS["crystal"]
		"iron":
			GameState.res["iron"] = float(GameState.res["iron"]) + float(r["amount"])
			hud.toast("漂流物：鉄 +%d" % int(r["amount"]))
			col = Asteroid.COLORS["iron"]
		"fuel":
			GameState.fuel = minf(GameState.max_fuel, GameState.fuel + float(r["amount"]))
			hud.toast("漂流物：燃料 +%d" % int(r["amount"]))
			col = Asteroid.COLORS["ice"]
		"map":
			for g in gates:
				if not g.discovered:
					_discover_gate(g, false)
			hud.toast("漂流物：星図を入手。ゲートの位置が判明！")
		"trap":
			GameState.damage_fuel(float(r["amount"]))
			hud.toast("罠だった！燃料 -%d" % int(r["amount"]))
			col = Color(1.0, 0.3, 0.2)
			player.shake(10.0)
	Fx.burst(fx_layer, pos, col, 30, 200.0)
	d.queue_free()


func _spawn_meteor() -> void:
	var target := player.position + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.0, 160.0)
	var ms := miners()
	if not ms.is_empty() and _rng.randf() < 0.5:
		var m: Node2D = ms[_rng.randi() % ms.size()]
		target = m.global_position + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.0, 60.0)
	var meteor := Meteor.new()
	meteor.position = target
	meteor.impacted.connect(_on_meteor_impact)
	fx_layer.add_child(meteor)
	_tip("meteor", "隕石の落下予告！赤い円から離れてください")


func _on_meteor_impact(m: Meteor) -> void:
	var p := m.global_position
	Fx.burst(fx_layer, p, Color(1.0, 0.5, 0.3), 40, 260.0)
	var lost := 0
	for mm in miners():
		if mm.global_position.distance_to(p) < Meteor.RADIUS:
			Fx.burst(fx_layer, mm.global_position, Color(1.0, 0.85, 0.3), 16)
			if mm.asteroid != null and is_instance_valid(mm.asteroid):
				mm.asteroid.has_miner = false
			mm.queue_free()
			lost += 1
	if player.position.distance_to(p) < Meteor.RADIUS:
		GameState.damage_fuel(12.0)
		player.shake(14.0)
		hud.toast("被弾！燃料 -12")
	elif player.position.distance_to(p) < 700.0:
		player.shake(5.0)
	if lost > 0:
		hud.toast("隕石で採掘機が %d 台壊れました" % lost)


func _on_asteroid_depleted(a: Asteroid) -> void:
	Fx.burst(fx_layer, a.global_position, a.color(), 24, 150.0 + a.radius * 2.0)
	if a.global_position.distance_to(player.position) < 600.0:
		player.shake(6.0)


func zone_burn_mult(p: Vector2) -> float:
	return ZONE_BURN if starfield.in_zone(p) else 1.0


func miners() -> Array:
	var out: Array = []
	for m in miner_layer.get_children():
		if not m.is_queued_for_deletion():
			out.append(m)
	return out


## 狙った位置に吸い付く小惑星（外周からの距離が slack 以内で一番近いもの）。
func lock_target(p: Vector2, slack: float) -> Asteroid:
	var best: Asteroid = null
	var best_d := INF
	for a in asteroid_layer.get_children():
		var ast := a as Asteroid
		if not ast.discovered or not ast.is_alive():
			continue
		var d := ast.position.distance_to(p) - ast.radius
		if d <= slack and d < best_d:
			best = ast
			best_d = d
	return best


## 採掘範囲内で、まだ採掘機が無い一番近い小惑星。
func nearest_free_asteroid() -> Asteroid:
	var best: Asteroid = null
	var best_d := INF
	for a in asteroid_layer.get_children():
		var ast := a as Asteroid
		if not ast.discovered or not ast.is_alive() or ast.has_miner or not player.in_range(ast):
			continue
		var d := ast.position.distance_to(player.position)
		if d < best_d:
			best = ast
			best_d = d
	return best


func gate_in_range() -> WarpGate:
	for g in gates:
		if g.discovered and player.position.distance_to(g.position) <= GATE_RANGE:
			return g
	return null


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_B:
				try_place_miner()
			KEY_E:
				try_warp()


func try_place_miner() -> void:
	var a := lock_target(get_global_mouse_position(), 12.0)
	if a == null or a.has_miner or not player.in_range(a):
		a = nearest_free_asteroid()
	if a == null:
		hud.toast("近くに設置できる小惑星がありません")
		return
	_place_miner_on(a)


## タッチ用：近くの空いている小惑星に自動で設置する。
func try_place_miner_nearest() -> void:
	try_place_miner()


func _place_miner_on(a: Asteroid) -> void:
	if a.has_miner:
		hud.toast("この小惑星には設置済みです")
		return
	var cost := GameState.miner_cost()
	if not GameState.pay(cost):
		hud.toast("資源不足（必要：%s）" % GameState.cost_text(cost))
		return
	GameState.miners_built += 1
	var m := Miner.new()
	miner_layer.add_child(m)
	m.setup(a)
	a.has_miner = true
	Fx.burst(fx_layer, a.global_position, Color(1.0, 0.85, 0.3), 14, 120.0)
	hud.toast("採掘機を設置（次は %s）" % GameState.cost_text(GameState.miner_cost()))


func try_warp() -> void:
	var g := gate_in_range()
	if g == null:
		hud.toast("ワープゲートに近づいてください")
		return
	var cost := GameState.warp_cost()
	if not GameState.pay(cost):
		hud.toast("ワープに必要：%s" % GameState.cost_text(cost))
		return
	if GameState.is_final_sector():
		GameState.end_run("帰還成功", true)
		return
	# 置いていく採掘機は撤収して鉄を少し回収
	var salvage := 0.0
	for m in miners():
		salvage += SALVAGE_PER_MINER + m.stored
	if salvage > 0.0:
		GameState.res["iron"] = float(GameState.res["iron"]) + salvage
	_pending_gate = g
	get_tree().paused = true
	touch.reset()
	hud.show_perk_choice(GameState.roll_perks(g.perk_count()), int(salvage))


func on_perk_chosen(id: String) -> void:
	hud.hide_panels()
	if id == "":
		GameState.fuel = minf(GameState.max_fuel, GameState.fuel + 25.0)
	else:
		GameState.apply_perk(id)
	GameState.sector_type = _pending_gate.next_type if _pending_gate != null else "standard"
	_pending_gate = null
	GameState.sector += 1
	GameState.fuel = minf(GameState.max_fuel, GameState.fuel + WARP_REFUEL)
	build_sector()
	get_tree().paused = false


func _on_run_over(reason: String, victory: bool) -> void:
	get_tree().paused = true
	touch.reset()
	hud.show_game_over(reason, victory)


func restart() -> void:
	GameState.new_run()
	_tips_shown.clear()
	build_sector()
	hud.hide_panels()
	get_tree().paused = false
