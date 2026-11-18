extends Node2D
## ゲーム全体の進行。セクター生成、探索（霧）、採掘機の設置、ワープを管理する。

const WORLD_RADIUS := 2200.0
const BASE_SCAN := 420.0
const GATE_RANGE := 140.0
const WARP_REFUEL := 30.0

const StarfieldScript := preload("res://scripts/starfield.gd")
const HudScript := preload("res://scripts/hud.gd")

var starfield: Node2D
var asteroid_layer: Node2D
var gate: WarpGate
var player: Player
var hud: CanvasLayer


func _ready() -> void:
	randomize()
	GameState.new_run()

	starfield = StarfieldScript.new()
	starfield.world_radius = WORLD_RADIUS
	add_child(starfield)

	asteroid_layer = Node2D.new()
	add_child(asteroid_layer)

	gate = WarpGate.new()
	add_child(gate)

	player = Player.new()
	player.main = self
	player.world_radius = WORLD_RADIUS
	add_child(player)

	hud = HudScript.new()
	hud.main = self
	add_child(hud)

	GameState.run_over.connect(_on_run_over)
	build_sector()


func build_sector() -> void:
	for c in asteroid_layer.get_children():
		c.queue_free()
	var data := SectorGenerator.generate(GameState.sector_seed(), GameState.sector, WORLD_RADIUS)
	for d in data["asteroids"]:
		var a := Asteroid.new()
		a.setup(d)
		asteroid_layer.add_child(a)
	gate.position = data["gate"]
	gate.discovered = false
	gate.visible = false
	player.position = Vector2.ZERO
	player.velocity = Vector2.ZERO
	starfield.regenerate(GameState.sector_seed())
	hud.toast("セクター %d に到着" % GameState.sector)


func _process(_delta: float) -> void:
	# 探索：スキャン範囲に入ったものだけ見えるようになる
	var scan := BASE_SCAN * GameState.scan_mult
	for a in asteroid_layer.get_children():
		var ast := a as Asteroid
		if not ast.discovered and ast.position.distance_to(player.position) < scan + ast.radius:
			ast.discovered = true
			ast.visible = true
	if not gate.discovered and gate.position.distance_to(player.position) < scan + 50.0:
		gate.discovered = true
		gate.visible = true
		hud.toast("ワープゲートを発見！")


func asteroid_at(p: Vector2) -> Asteroid:
	for a in asteroid_layer.get_children():
		var ast := a as Asteroid
		if ast.discovered and ast.is_alive() and ast.position.distance_to(p) <= ast.radius * 1.1:
			return ast
	return null


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_B:
				try_place_miner()
			KEY_E:
				try_warp()


func try_place_miner() -> void:
	var a := asteroid_at(get_global_mouse_position())
	if a == null:
		hud.toast("採掘機を置く小惑星にカーソルを合わせてください")
		return
	if a.has_miner:
		hud.toast("この小惑星には設置済みです")
		return
	if not player.in_range(a):
		hud.toast("遠すぎます")
		return
	var cost := GameState.miner_cost()
	if not GameState.pay(cost):
		hud.toast("資源不足（必要：%s）" % GameState.cost_text(cost))
		return
	var m := Miner.new()
	m.rotation = -a.rotation
	a.add_child(m)
	a.has_miner = true
	hud.toast("自動採掘機を設置")


func try_warp() -> void:
	if not gate.discovered or player.position.distance_to(gate.position) > GATE_RANGE:
		hud.toast("ワープゲートに近づいてください")
		return
	var cost := GameState.warp_cost()
	if not GameState.pay(cost):
		hud.toast("ワープに必要：%s" % GameState.cost_text(cost))
		return
	get_tree().paused = true
	hud.show_perk_choice(GameState.roll_perks(3))


func on_perk_chosen(id: String) -> void:
	GameState.apply_perk(id)
	GameState.sector += 1
	GameState.fuel = minf(GameState.max_fuel, GameState.fuel + WARP_REFUEL)
	build_sector()
	get_tree().paused = false


func _on_run_over(reason: String) -> void:
	get_tree().paused = true
	hud.show_game_over(reason)


func restart() -> void:
	GameState.new_run()
	build_sector()
	hud.hide_panels()
	get_tree().paused = false
