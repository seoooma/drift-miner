extends Node2D
## ゲーム全体の進行（オートモード）。
## 自機はオートパイロットで動き、建物はキットに合わせて自動で建つ。
## プレイヤーが決めるのは「レベルアップ時の強化カード」「ワープの航路」「ゲーム速度」だけ。

const WORLD_RADIUS := 2200.0
const BASE_SCAN := 420.0
const GATE_RANGE := 90.0
const WARP_REFUEL := 30.0
const ZONE_BURN := 2.5
const DERELICT_RANGE := 60.0
const BUILD_INTERVAL := 0.5
const MINER_MAX_DIST := 1300.0
const ROUTE_SNOOZE := 25.0
const SPEEDS := [1.0, 2.0, 3.0]

const StarfieldScript := preload("res://scripts/starfield.gd")
const HudScript := preload("res://scripts/hud.gd")
const TouchScript := preload("res://scripts/touch_controls.gd")

var starfield: Node2D
var asteroid_layer: Node2D
var object_layer: Node2D
var building_layer: Node2D
var miner_layer: Node2D
var fx_layer: Node2D
var core: ShipCore
var player: Player
var hud: CanvasLayer
var touch: CanvasLayer
var gates: Array = []

## プレイヤーが選んだ行き先のゲート（null なら未選択）
var route_gate: WarpGate = null
var speed_index: int = 0
## 強化カードを自動で選ぶか
var auto_pick: bool = false

var _meteor_timer: float = 0.0
var _build_timer: float = 0.0
var _route_snooze: float = 0.0
var _known_gates: int = 0
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

	touch = TouchScript.new()
	touch.main = self
	add_child(touch)
	player.touch = touch

	hud = HudScript.new()
	hud.main = self
	add_child(hud)

	GameState.run_over.connect(_on_run_over)
	if touch.active:
		get_tree().root.size_changed.connect(_apply_mobile_scale)
		_apply_mobile_scale()
	build_sector()
	open_mothership()


## スマホでは画面の短い辺を 450 として扱い、文字とボタンを大きく表示する。
func _apply_mobile_scale() -> void:
	var win := get_window()
	var s := DisplayServer.window_get_size()
	if s.x <= 0 or s.y <= 0:
		return
	var short_side := 450
	if s.y > s.x:
		win.content_scale_size = Vector2i(short_side, int(short_side * float(s.y) / s.x))
	else:
		win.content_scale_size = Vector2i(int(short_side * float(s.x) / s.y), short_side)


# ---------------------------------------------------------------- 母艦とラン


func open_mothership() -> void:
	get_tree().paused = true
	Engine.time_scale = 1.0
	hud.show_mothership()


func launch_run() -> void:
	GameState.new_run()
	_tips_shown.clear()
	build_sector(true)
	hud.hide_panels()
	Engine.time_scale = SPEEDS[speed_index]
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
	route_gate = null
	_route_snooze = 0.0
	_known_gates = 0
	_build_timer = 0.0
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
	player.reset_sector()
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


func toggle_speed() -> void:
	speed_index = (speed_index + 1) % SPEEDS.size()
	Engine.time_scale = SPEEDS[speed_index]


func speed() -> float:
	return SPEEDS[speed_index]


func toggle_auto_pick() -> void:
	auto_pick = not auto_pick


func _process(delta: float) -> void:
	if not GameState.alive:
		return
	GameState.sector_time += delta

	_update_discovery()

	_meteor_timer -= delta
	if _meteor_timer <= 0.0:
		_spawn_meteor()
		_meteor_timer = _next_meteor_delay()

	if GameState.sector_time > GameState.instability_grace - 15.0:
		_tip("instab", "まもなく宙域が不安定化。燃料の減りが加速します")
	if starfield.in_zone(player.position):
		_tip("zone", "放射線域！燃料の減りが速くなります")

	_build_timer -= delta
	if _build_timer <= 0.0:
		_build_timer = BUILD_INTERVAL
		_auto_build()

	# ゲートに着いたらワープ
	if route_gate != null and is_instance_valid(route_gate) and player.position.distance_to(route_gate.position) < GATE_RANGE:
		_warp(route_gate)
		return

	# 決めることがあれば一時停止して選ばせる（レベルアップ → 航路の順）
	if hud.any_panel():
		return
	if GameState.pending_levels > 0:
		_offer_level_cards()
		return
	_route_snooze -= delta
	var found := discovered_gates()
	if found.size() > _known_gates:
		_known_gates = found.size()
		_route_snooze = 0.0
	if route_gate == null and not found.is_empty() and _route_snooze <= 0.0 and GameState.can_afford(GameState.warp_cost()):
		_offer_routes(found)
	elif route_gate == null and GameState.quantum_blocked() and not _tips_shown.has("blocked") and GameState.sector_time > 20.0:
		_tips_shown["blocked"] = true
		get_tree().paused = true
		hud.show_blocked()


func _update_discovery() -> void:
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
			if d.is_queued_for_deletion():
				continue
			if not d.discovered and d.position.distance_to(player.position) < scan:
				d.discovered = true
				d.visible = true
			if d.discovered and d.position.distance_to(player.position) < DERELICT_RANGE:
				_open_derelict(d)


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


# ---------------------------------------------------------------- オートパイロット用の問い合わせ


func discovered_gates() -> Array:
	var out: Array = []
	for g in gates:
		if g.discovered:
			out.append(g)
	return out


func any_gate_found() -> bool:
	return not discovered_gates().is_empty()


func nearest_hidden_gate(p: Vector2) -> WarpGate:
	var best: WarpGate = null
	var best_d := INF
	for g in gates:
		if not g.discovered and g.position.distance_to(p) < best_d:
			best = g
			best_d = g.position.distance_to(p)
	return best


func nearest_derelict(p: Vector2, max_dist: float) -> Derelict:
	var best: Derelict = null
	var best_d := max_dist
	for o in object_layer.get_children():
		if o is Derelict and o.discovered and not o.is_queued_for_deletion():
			var d: float = o.position.distance_to(p)
			if d < best_d:
				best = o
				best_d = d
	return best


## いま足りない鉱石を、必要な順に返す。
func needed_ores() -> Array:
	var gs := GameState
	var iron := (float(gs.items["iron_ore"]) + float(gs.items["plate"]) * 2.0) / 2.0
	var copper := (float(gs.items["copper_ore"]) + float(gs.items["wire"]) / 2.0) / 1.5
	var out: Array = ["iron", "copper"] if iron <= copper else ["copper", "iron"]
	if _wants_crystal() and float(gs.items["crystal"]) < 10.0:
		out.push_front("crystal")
	return out


func _wants_crystal() -> bool:
	return built_count("quantum") > 0 or GameState.kit_count("quantum") > 0


func hub_covers(p: Vector2) -> bool:
	for b in building_layer.get_children():
		if b is DroneHub and not b.is_queued_for_deletion() and (b as DroneHub).covers(p):
			return true
	return false


func miners() -> Array:
	var out: Array = []
	for m in miner_layer.get_children():
		if not m.is_queued_for_deletion():
			out.append(m)
	return out


func built_count(btype: String) -> int:
	var n := 0
	for layer in [building_layer, miner_layer]:
		for b in layer.get_children():
			if not b.is_queued_for_deletion() and String(b.get("btype")) == btype:
				n += 1
	return n


func zone_burn_mult(p: Vector2) -> float:
	return ZONE_BURN if starfield.in_zone(p) else 1.0


# ---------------------------------------------------------------- 自動建設


## キットを自動で配置する。1回に1つずつ建てるので、少しずつ工場が育っていく。
func _auto_build() -> void:
	for f in GameState.FACTORIES:
		if GameState.kit_count(f) > 0:
			var p := _factory_slot()
			if p != Vector2.INF:
				GameState.add_kit(f, -1)
				var mc := Machine.new()
				mc.position = p
				building_layer.add_child(mc)
				mc.setup(f)
				_built_fx(p)
			return
	if GameState.kit_count("hub") > 0 and _place_hub():
		return
	_place_miner()


func _built_fx(p: Vector2) -> void:
	Fx.burst(fx_layer, p, Color(1.0, 0.85, 0.3), 14, 120.0)


## 母船のまわりの円周上で、空いている場所を内側から探す。
func _factory_slot() -> Vector2:
	for ring in [110.0, 175.0, 240.0, 305.0, 370.0]:
		var n := int(TAU * ring / 62.0)
		for i in n:
			var p: Vector2 = Vector2.from_angle(TAU * i / n + ring * 0.01) * ring
			if _free_at(p, 26.0):
				return p
	return Vector2.INF


func _free_at(p: Vector2, r: float) -> bool:
	for a in asteroid_layer.get_children():
		var ast := a as Asteroid
		if ast.is_alive() and ast.position.distance_to(p) < ast.radius + r:
			return false
	for b in building_layer.get_children():
		if not b.is_queued_for_deletion() and b.global_position.distance_to(p) < r + 24.0:
			return false
	return true


## ハブはドローンが届かない採掘機の中心あたりに置く。最初の1台は母船の隣。
func _place_hub() -> bool:
	var target := Vector2.ZERO
	if built_count("hub") == 0:
		if miners().is_empty():
			return false
		target = Vector2(0, -80)
	else:
		var sum := Vector2.ZERO
		var n := 0
		for m in miners():
			if not hub_covers(m.global_position):
				sum += m.global_position
				n += 1
		if n == 0:
			return false
		target = sum / n
	for i in 12:
		var p := target + Vector2.from_angle(i * 2.4) * (i * 22.0)
		if _free_at(p, 22.0):
			GameState.add_kit("hub", -1)
			var h := DroneHub.new()
			h.position = p
			h.main = self
			building_layer.add_child(h)
			_built_fx(p)
			hud.toast("ドローンハブを設置")
			return true
	return false


func _place_miner() -> void:
	var gs := GameState
	if built_count("miner") >= gs.miner_cap:
		return
	var use_kit := gs.kit_count("miner") > 0
	# キットが無ければ鉄板で作る。ただし回路に使う分は残しておく
	var reserve := 6.0 if built_count("assembler") > 0 else 0.0
	if not use_kit and float(gs.items["plate"]) < 4.0 + reserve:
		return
	var wanted: Array = needed_ores()
	var best: Asteroid = null
	var best_s := INF
	for c in asteroid_layer.get_children():
		var a := c as Asteroid
		if not a.discovered or not a.is_alive() or a.has_miner or a.kind == "ice":
			continue
		if not (a.kind in wanted) or a.amount < 25.0:
			continue
		var d := a.position.length()
		if d > MINER_MAX_DIST:
			continue
		var s := d - a.amount * 0.5
		if not hub_covers(a.position):
			s += 350.0
		s += wanted.find(a.kind) * 250.0
		if s < best_s:
			best = a
			best_s = s
	if best == null:
		return
	if use_kit:
		gs.add_kit("miner", -1)
	else:
		gs.pay(gs.BUILDINGS["miner"]["cost"])
	var m := Miner.new()
	miner_layer.add_child(m)
	m.setup(best)
	best.has_miner = true
	_built_fx(best.global_position)


# ---------------------------------------------------------------- 選択（カード・航路）


func _offer_level_cards() -> void:
	var opts := GameState.roll_cards(GameState.card_choices())
	if auto_pick:
		_apply_level_card(String(_auto_choice(opts)["id"]))
		return
	get_tree().paused = true
	hud.show_cards("レベル %d！強化を1つ選ぶ" % (GameState.level - GameState.pending_levels + 1), opts, "", _on_level_card, GameState.has_skill("reroll"))


func _on_level_card(id: String) -> void:
	_apply_level_card(id)
	get_tree().paused = false


func _apply_level_card(id: String) -> void:
	GameState.pending_levels = maxi(0, GameState.pending_levels - 1)
	if id != "":
		GameState.apply_card(id)
		var c := _card(id)
		hud.toast("強化：%s" % c.get("name", id))


func _card(id: String) -> Dictionary:
	for c in GameState.CARDS:
		if c["id"] == id:
			return c
	return {}


## おまかせ選択：足りない工程を優先し、なければ重みの大きいものを選ぶ。
func _auto_choice(opts: Array) -> Dictionary:
	var best: Dictionary = opts[0]
	var best_s := -INF
	for c in opts:
		var id := String(c["id"])
		var s := float(c["w"]) + randf()
		if GameState.fuel / GameState.max_fuel < 0.35 and id in ["fuel_eff", "big_tank", "ice_refinery"]:
			s += 6.0
		if id == "add_quantum" and GameState.sector >= 3 and built_count("quantum") == 0:
			s += 8.0
		if id.begins_with("add_"):
			s += 1.5
		if s > best_s:
			best = c
			best_s = s
	return best


func _offer_routes(found: Array) -> void:
	get_tree().paused = true
	hud.show_routes(found)


## 航路の選択。gate が null なら探索を続ける。
func on_route_chosen(gate: WarpGate) -> void:
	hud.hide_panels()
	if gate == null:
		_route_snooze = ROUTE_SNOOZE
	elif GameState.pay(GameState.warp_cost()):
		route_gate = gate
		hud.toast("航路決定。ゲートへ向かいます")
	get_tree().paused = false


## 先へ進めないときに、ランを切り上げて母艦へ帰る。
func retreat() -> void:
	hud.hide_panels()
	get_tree().paused = false
	GameState.end_run("母艦へ帰還", false)


func keep_going() -> void:
	hud.hide_panels()
	get_tree().paused = false


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
			if GameState.has_skill("quantum"):
				choices.append("quantum")
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
	_tip("meteor", "隕石の落下予告！壊れた工場は自動で建て直します")


func _on_meteor_impact(m: Meteor) -> void:
	var p := m.global_position
	Fx.burst(fx_layer, p, Color(1.0, 0.5, 0.3), 40, 260.0)
	var lost := 0
	for b in _all_buildings():
		if b.global_position.distance_to(p) < Meteor.RADIUS:
			Fx.burst(fx_layer, b.global_position, Color(1.0, 0.85, 0.3), 16)
			# 工場とハブはキットに戻って建て直される。採掘機は失われる
			if not (b is Miner):
				GameState.add_kit(String(b.get("btype")), 1)
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


# ---------------------------------------------------------------- ワープ


func _warp(g: WarpGate) -> void:
	route_gate = null
	if GameState.is_final_sector():
		GameState.end_run("帰還成功", true)
		return
	# 建物は畳んでキットに戻し、次のセクターで自動的に再配置する
	for b in _all_buildings():
		if b is Miner:
			var mm := b as Miner
			GameState.add_ore(mm.kind, mm.stored)
		GameState.add_kit(String(b.get("btype")), 1)
		_remove_building(b)
	_pending_gate = g
	var n: int = g.perk_count() + (1 if GameState.has_skill("more_cards") else 0)
	var opts := GameState.roll_cards(n)
	if auto_pick:
		_on_warp_card(String(_auto_choice(opts)["id"]))
		return
	get_tree().paused = true
	var title := "ワープ成功！%s へ。強化を1つ選ぶ" % SectorGenerator.type_name(g.next_type)
	hud.show_cards(title, opts, "受け取らずに燃料 +25", _on_warp_card, GameState.has_skill("reroll"))


func _on_warp_card(id: String) -> void:
	hud.hide_panels()
	if id == "":
		GameState.fuel = minf(GameState.max_fuel, GameState.fuel + 25.0)
	else:
		GameState.apply_card(id)
	GameState.sector_type = _pending_gate.next_type if _pending_gate != null else "standard"
	_pending_gate = null
	GameState.sector += 1
	GameState.fuel = minf(GameState.max_fuel, GameState.fuel + WARP_REFUEL)
	build_sector(false)
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_SPACE and GameState.alive and not hud.any_panel():
			toggle_speed()


func _on_run_over(reason: String, victory: bool) -> void:
	get_tree().paused = true
	route_gate = null
	Engine.time_scale = 1.0
	hud.show_game_over(reason, victory)
