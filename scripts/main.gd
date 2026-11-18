extends Node2D
## ゲーム全体の進行。セクター生成、探索（霧）、建物の設置、危険、漂流物、ワープ、母艦を管理する。

const WORLD_RADIUS := 2200.0
const BASE_SCAN := 420.0
const GATE_RANGE := 140.0
const WARP_REFUEL := 30.0
const ZONE_BURN := 2.5
const DERELICT_RANGE := 60.0
const PLACE_RANGE := 750.0

const StarfieldScript := preload("res://scripts/starfield.gd")
const HudScript := preload("res://scripts/hud.gd")
const TouchScript := preload("res://scripts/touch_controls.gd")

var starfield: Node2D
var asteroid_layer: Node2D
var object_layer: Node2D
var building_layer: Node2D
var miner_layer: Node2D
var fx_layer: Node2D
var preview: Node2D
var core: ShipCore
var player: Player
var hud: CanvasLayer
var touch: CanvasLayer
var gates: Array = []
var placing: String = ""

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

	core = ShipCore.new()
	add_child(core)

	asteroid_layer = Node2D.new()
	add_child(asteroid_layer)
	object_layer = Node2D.new()
	add_child(object_layer)
	building_layer = Node2D.new()
	add_child(building_layer)
	miner_layer = Node2D.new()
	add_child(miner_layer)

	player = Player.new()
	player.main = self
	player.world_radius = WORLD_RADIUS
	add_child(player)

	fx_layer = Node2D.new()
	add_child(fx_layer)
	preview = Node2D.new()
	preview.draw.connect(_draw_preview)
	add_child(preview)

	touch = TouchScript.new()
	touch.main = self
	add_child(touch)
	player.touch = touch

	hud = HudScript.new()
	hud.main = self
	add_child(hud)

	GameState.run_over.connect(_on_run_over)
	build_sector()
	open_mothership()


# ---------------------------------------------------------------- 母艦とラン


func open_mothership() -> void:
	get_tree().paused = true
	touch.reset()
	hud.show_mothership()


func launch_run() -> void:
	GameState.new_run()
	_tips_shown.clear()
	placing = ""
	build_sector(true)
	hud.hide_panels()
	get_tree().paused = false


func build_sector(clear_buildings: bool = true) -> void:
	for layer in [asteroid_layer, object_layer, fx_layer]:
		for c in layer.get_children():
			c.queue_free()
	if clear_buildings:
		for layer in [building_layer, miner_layer]:
			for c in layer.get_children():
				c.queue_free()
	gates.clear()
	placing = ""
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

	player.position = Vector2(0, 90)
	player.velocity = Vector2.ZERO
	_meteor_timer = _next_meteor_delay()

	var title := "セクター %d：%s" % [GameState.sector, info["name"]]
	if GameState.is_final_sector():
		title = "最終セクター %d：%s" % [GameState.sector, info["name"]]
	hud.banner(title, String(info["desc"]))


func scan_radius() -> float:
	var r := BASE_SCAN * GameState.scan_mult
	if GameState.sector_type == "nebula":
		r *= 0.65
	return r


func _next_meteor_delay() -> float:
	if GameState.sector <= 1:
		return INF
	var base := maxf(14.0, 34.0 - GameState.sector * 2.0)
	if GameState.sector_type == "radiation":
		base *= 0.7
	return _rng.randf_range(base * 0.7, base * 1.3)


func _process(delta: float) -> void:
	preview.queue_redraw()
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

	_meteor_timer -= delta
	if _meteor_timer <= 0.0:
		_spawn_meteor()
		_meteor_timer = _next_meteor_delay()

	if GameState.sector_time > GameState.instability_grace - 15.0:
		_tip("instab", "まもなく宙域が不安定化。燃料の減りが加速します")


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


# ---------------------------------------------------------------- 次にやること


func built_count(btype: String) -> int:
	var n := 0
	for layer in [building_layer, miner_layer]:
		for b in layer.get_children():
			if not b.is_queued_for_deletion() and String(b.get("btype")) == btype:
				n += 1
	return n


func next_step() -> String:
	var gs := GameState
	var need := gs.warp_cost()
	var lack_c := int(need.get("circuit", 0)) - gs.count("circuit")
	var lack_q := int(need.get("qcore", 0)) - gs.count("qcore")
	var s := ""
	if lack_c > 0 or lack_q > 0:
		if built_count("smelter") == 0:
			s = "製鉄炉を母船の青い円の中に建てる"
		elif built_count("miner") == 0:
			s = "採掘機を小惑星に置く（灰＝鉄、橙＝銅）"
		elif built_count("wiremill") == 0:
			s = "伸線機を建てる（銅鉱石→銅線）"
		elif built_count("assembler") == 0:
			s = "組立機を建てる（鉄板8・銅線6）"
		elif lack_c > 0:
			s = "回路を作る（あと%d）" % lack_c
		elif not gs.building_unlocked("quantum"):
			s = "量子コアが必要。母艦で「量子炉の設計図」を研究"
		elif built_count("quantum") == 0:
			s = "量子炉を建てる（回路6・鉄板10）"
		else:
			s = "量子コアを作る（あと%d）" % lack_q
	var found := false
	for g in gates:
		if g.discovered:
			found = true
	if s == "":
		return "ゲートへ向かってワープ！" if found else "ゲートを探す（外側へ）"
	return s if found else s + "／ゲートを探す"


# ---------------------------------------------------------------- 漂流物と危険


func _open_derelict(d: Derelict) -> void:
	var r := d.open()
	var pos := d.global_position
	var col := Color(1.0, 1.0, 0.6)
	var amt := float(r["amount"])
	GameState.derelicts_opened += 1
	match String(r["kind"]):
		"crystal":
			GameState.add_item("crystal", amt)
			hud.toast("漂流物：結晶 +%d" % int(amt))
			col = Asteroid.COLORS["crystal"]
		"plate":
			GameState.add_item("plate", amt)
			hud.toast("漂流物：鉄板 +%d" % int(amt))
		"fuel":
			GameState.fuel = minf(GameState.max_fuel, GameState.fuel + amt)
			hud.toast("漂流物：燃料 +%d" % int(amt))
			col = Asteroid.COLORS["ice"]
		"kit":
			var choices := ["miner", "hub", "smelter", "wiremill", "assembler"]
			var b: String = choices[_rng.randi() % choices.size()]
			GameState.add_kit(b, int(amt))
			hud.toast("漂流物：%sのキット +%d" % [GameState.BUILDINGS[b]["name"], int(amt)])
		"map":
			for g in gates:
				if not g.discovered:
					_discover_gate(g, false)
			hud.toast("漂流物：星図を入手。ゲートの位置が判明！")
		"trap":
			GameState.damage_fuel(amt)
			hud.toast("罠だった！燃料 -%d" % int(amt))
			col = Color(1.0, 0.3, 0.2)
			player.shake(10.0)
	Fx.burst(fx_layer, pos, col, 30, 200.0)
	d.queue_free()


func _all_buildings() -> Array:
	var out: Array = []
	for layer in [building_layer, miner_layer]:
		for b in layer.get_children():
			if not b.is_queued_for_deletion():
				out.append(b)
	return out


func _spawn_meteor() -> void:
	var target := player.position + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.0, 160.0)
	var bs := _all_buildings()
	if not bs.is_empty() and _rng.randf() < 0.6:
		var b: Node2D = bs[_rng.randi() % bs.size()]
		target = b.global_position + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.0, 70.0)
	var meteor := Meteor.new()
	meteor.position = target
	meteor.impacted.connect(_on_meteor_impact)
	fx_layer.add_child(meteor)
	_tip("meteor", "隕石の落下予告！範囲内の建物は壊れます")


func _on_meteor_impact(m: Meteor) -> void:
	var p := m.global_position
	Fx.burst(fx_layer, p, Color(1.0, 0.5, 0.3), 40, 260.0)
	var lost := 0
	for b in _all_buildings():
		if b.global_position.distance_to(p) < Meteor.RADIUS:
			Fx.burst(fx_layer, b.global_position, Color(1.0, 0.85, 0.3), 16)
			_remove_building(b)
			lost += 1
	if player.position.distance_to(p) < Meteor.RADIUS:
		GameState.damage_fuel(12.0)
		player.shake(14.0)
		hud.toast("被弾！燃料 -12")
	elif player.position.distance_to(p) < 700.0:
		player.shake(5.0)
	if lost > 0:
		hud.toast("隕石で建物が %d 個壊れました" % lost)


func _remove_building(b: Node) -> void:
	if b is Miner:
		var mm := b as Miner
		if mm.asteroid != null and is_instance_valid(mm.asteroid):
			mm.asteroid.has_miner = false
	if b is DroneHub:
		(b as DroneHub).release()
	b.queue_free()


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


func gate_in_range() -> WarpGate:
	for g in gates:
		if g.discovered and player.position.distance_to(g.position) <= GATE_RANGE:
			return g
	return null


# ---------------------------------------------------------------- 建設


func can_start_placing(btype: String) -> bool:
	if not GameState.building_unlocked(btype):
		return false
	return GameState.kit_count(btype) > 0 or GameState.can_afford(GameState.BUILDINGS[btype]["cost"])


func toggle_placing(btype: String) -> void:
	if placing == btype:
		placing = ""
		return
	if not GameState.building_unlocked(btype):
		hud.toast("母艦で研究すると建てられます")
		return
	if not can_start_placing(btype):
		hud.toast("資源不足（必要：%s）" % GameState.cost_text(GameState.BUILDINGS[btype]["cost"]))
		return
	placing = btype
	match btype:
		"miner":
			hud.toast("採掘機を置く小惑星をタップ（ボタンをもう一度で取消）")
		"hub":
			hud.toast("ハブを置く場所をタップ（黄色い円の範囲から運ぶ）")
		_:
			hud.toast("母船の青い円の中をタップして設置（ボタンをもう一度で取消）")


## 設置できるかを調べ、理由（空文字ならOK）を返す。
func placement_problem(btype: String, p: Vector2) -> String:
	if btype == "miner":
		var a := lock_target(p, 30.0)
		if a == null:
			return "小惑星を選んでください"
		if a.has_miner:
			return "この小惑星には設置済みです"
		return ""
	if p.distance_to(player.position) > PLACE_RANGE:
		return "自機から遠すぎます"
	if p.distance_to(core.position) < ShipCore.BODY_RADIUS + 30.0:
		return "母船に重なっています"
	if btype != "hub" and p.distance_to(core.position) > ShipCore.SUPPLY_RADIUS:
		return "工場は母船の青い円の中に置いてください"
	for a in asteroid_layer.get_children():
		var ast := a as Asteroid
		if ast.is_alive() and ast.position.distance_to(p) < ast.radius + 24.0:
			return "小惑星に重なっています"
	for b in building_layer.get_children():
		if not b.is_queued_for_deletion() and b.global_position.distance_to(p) < 44.0:
			return "他の建物に重なっています"
	return ""


func try_place_at(p: Vector2) -> void:
	if placing == "":
		return
	var btype := placing
	var problem := placement_problem(btype, p)
	if problem != "":
		hud.toast(problem)
		return
	if GameState.kit_count(btype) > 0:
		GameState.add_kit(btype, -1)
	elif not GameState.pay(GameState.BUILDINGS[btype]["cost"]):
		hud.toast("資源不足")
		placing = ""
		return
	var where := p
	match btype:
		"miner":
			var a := lock_target(p, 30.0)
			var m := Miner.new()
			miner_layer.add_child(m)
			m.setup(a)
			a.has_miner = true
			where = a.global_position
		"hub":
			var h := DroneHub.new()
			h.position = p
			h.main = self
			building_layer.add_child(h)
		_:
			var mc := Machine.new()
			mc.position = p
			building_layer.add_child(mc)
			mc.setup(btype)
	Fx.burst(fx_layer, where, Color(1.0, 0.85, 0.3), 14, 120.0)
	if not can_start_placing(btype):
		placing = ""


func _draw_preview() -> void:
	if placing == "":
		return
	var t := Time.get_ticks_msec() * 0.001
	if placing == "miner":
		for a in asteroid_layer.get_children():
			var ast := a as Asteroid
			if ast.discovered and ast.is_alive() and not ast.has_miner:
				var rr := ast.radius + 16.0
				for i in 10:
					var a0 := TAU * i / 10.0 + t
					preview.draw_arc(ast.position, rr, a0, a0 + 0.3, 4, Color(1.0, 0.85, 0.3, 0.6), 2.0)
		return
	if placing != "hub":
		preview.draw_arc(core.position, ShipCore.SUPPLY_RADIUS, 0.0, TAU, 96, Color(0.4, 0.8, 1.0, 0.5 + 0.3 * sin(t * 5.0)), 4.0)
	if not touch.active:
		var mp := get_global_mouse_position()
		var ok := placement_problem(placing, mp) == ""
		var c := Color(0.4, 1.0, 0.5, 0.7) if ok else Color(1.0, 0.3, 0.3, 0.7)
		if placing == "hub":
			preview.draw_arc(mp, DroneHub.RANGE, 0.0, TAU, 96, Color(1.0, 0.9, 0.5, 0.35), 2.0)
		preview.draw_rect(Rect2(mp - Vector2(15, 15), Vector2(30, 30)), c, false, 2.0)


# ---------------------------------------------------------------- 入力


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_E:
				try_warp()
			KEY_ESCAPE:
				placing = ""
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
				var i: int = event.physical_keycode - KEY_1
				if i < GameState.BUILD_ORDER.size():
					toggle_placing(GameState.BUILD_ORDER[i])
	elif event is InputEventMouseButton and event.pressed and not touch.active:
		if event.button_index == MOUSE_BUTTON_LEFT and placing != "":
			try_place_at(get_global_mouse_position())
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			placing = ""


# ---------------------------------------------------------------- ワープ


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
	# 建物は畳んでキットに戻し、次のセクターで再配置する
	var packed := 0
	for b in _all_buildings():
		if b is Miner:
			var mm := b as Miner
			GameState.add_ore(mm.kind, mm.stored)
		GameState.add_kit(String(b.get("btype")), 1)
		_remove_building(b)
		packed += 1
	placing = ""
	_pending_gate = g
	get_tree().paused = true
	touch.reset()
	hud.show_perk_choice(GameState.roll_perks(g.perk_count()), packed)


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
	build_sector(false)
	get_tree().paused = false


func _on_run_over(reason: String, victory: bool) -> void:
	get_tree().paused = true
	placing = ""
	touch.reset()
	hud.show_game_over(reason, victory)
