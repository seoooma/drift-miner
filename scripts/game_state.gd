extends Node
## ラン全体の状態（資源・燃料・セクター・パーク・スコア）を保持する Autoload。

signal run_over(reason: String, victory: bool)

const RES_NAMES := {"iron": "鉄", "ice": "氷", "crystal": "結晶"}
const FINAL_SECTOR := 10
const SAVE_PATH := "user://drift_miner.cfg"

## 不安定化：セクター到着から GRACE 秒後、燃料消費が毎秒 RAMP ずつ増える（上限 MAX）。
const INSTABILITY_GRACE := 60.0
const INSTABILITY_RAMP := 0.02
const INSTABILITY_MAX := 3.0

const PERKS := [
	{"id": "greedy_drill", "name": "貪欲ドリル", "desc": "手掘り速度 +100%\n代償：燃料消費 +20%"},
	{"id": "advance", "name": "前借り", "desc": "今すぐ 鉄 +60\n代償：ワープ費用 +25%"},
	{"id": "ice_refinery", "name": "氷精製炉", "desc": "氷→燃料の変換 2倍\n代償：採掘機の速度 -30%"},
	{"id": "collector", "name": "回収ドローン", "desc": "採掘機からの回収範囲 +100%"},
	{"id": "big_storage", "name": "大型コンテナ", "desc": "採掘機の貯蔵量 +100%"},
	{"id": "cheap_miner", "name": "量産設計", "desc": "採掘機の値上がり 1.3倍→1.15倍"},
	{"id": "fuel_eff", "name": "省エネ推進器", "desc": "燃料消費 -20%"},
	{"id": "big_tank", "name": "大型タンク", "desc": "最大燃料 +40（全回復）"},
	{"id": "scanner", "name": "広域スキャナー", "desc": "探索範囲 +50%"},
	{"id": "oracle", "name": "予知スキャナー", "desc": "ゲートの位置が最初から分かる"},
	{"id": "stabilizer", "name": "安定化装置", "desc": "不安定化の猶予 +30秒"},
	{"id": "crystal_drill", "name": "結晶ドリル", "desc": "採掘機が結晶も通常速度で掘る"},
]

var seed_base: int = 0
var sector: int = 1
var sector_type: String = "standard"
var sector_time: float = 0.0
var miners_built: int = 0
var res := {"iron": 0.0, "crystal": 0.0}
var fuel: float = 100.0
var max_fuel: float = 100.0
var alive: bool = true
var perks: Array[String] = []
var total_mined: float = 0.0
var best_score: int = 0
var runs_played: int = 0

var mine_mult: float = 1.0
var miner_mult: float = 1.0
var fuel_burn_mult: float = 1.0
var miner_cost_growth: float = 1.3
var scan_mult: float = 1.0
var ice_fuel_mult: float = 1.0
var collect_mult: float = 1.0
var storage_mult: float = 1.0
var warp_cost_mult: float = 1.0
var instability_grace: float = INSTABILITY_GRACE
var oracle: bool = false
var crystal_drill: bool = false


func _ready() -> void:
	_load()


func new_run(seed_value: int = -1) -> void:
	seed_base = seed_value if seed_value >= 0 else randi()
	sector = 1
	sector_type = "standard"
	res = {"iron": 0.0, "crystal": 0.0}
	max_fuel = 100.0
	fuel = max_fuel
	alive = true
	perks.clear()
	total_mined = 0.0
	mine_mult = 1.0
	miner_mult = 1.0
	fuel_burn_mult = 1.0
	miner_cost_growth = 1.3
	scan_mult = 1.0
	ice_fuel_mult = 1.0
	collect_mult = 1.0
	storage_mult = 1.0
	warp_cost_mult = 1.0
	instability_grace = INSTABILITY_GRACE
	oracle = false
	crystal_drill = false
	start_sector()


func start_sector() -> void:
	sector_time = 0.0
	miners_built = 0


## セクターごとのシード。同じラン・同じセクターなら同じ地形になる。
func sector_seed() -> int:
	return hash("%d:%d" % [seed_base, sector])


func add_res(kind: String, amount: float) -> void:
	if amount <= 0.0:
		return
	total_mined += amount
	if kind == "ice":
		# 氷はその場で燃料に精製される
		fuel = minf(max_fuel, fuel + amount * 0.5 * ice_fuel_mult)
	else:
		res[kind] = float(res.get(kind, 0.0)) + amount


func instability() -> float:
	var over := sector_time - instability_grace
	if over <= 0.0:
		return 1.0
	return minf(INSTABILITY_MAX, 1.0 + over * INSTABILITY_RAMP)


func burn_fuel(amount: float) -> void:
	if not alive:
		return
	fuel -= amount * fuel_burn_mult * instability()
	if fuel <= 0.0:
		fuel = 0.0
		end_run("燃料切れ", false)


func damage_fuel(amount: float) -> void:
	if not alive:
		return
	fuel = maxf(0.0, fuel - amount)
	if fuel <= 0.0:
		end_run("燃料切れ", false)


func end_run(reason: String, victory: bool) -> void:
	if not alive and not victory:
		return
	alive = false
	runs_played += 1
	var s := score(victory)
	if s > best_score:
		best_score = s
	_save()
	run_over.emit(reason, victory)


func score(victory: bool = false) -> int:
	var s := (sector - 1) * 1000 + int(total_mined) + int(fuel) * 5
	if victory:
		s += 5000
	return s


func miner_cost() -> Dictionary:
	return {"iron": int(ceil(10.0 * pow(miner_cost_growth, miners_built)))}


func is_final_sector() -> bool:
	return sector >= FINAL_SECTOR


func warp_cost() -> Dictionary:
	var iron := (25.0 + sector * 15.0) * warp_cost_mult
	var crystal := (2.0 + sector * 2.0) * warp_cost_mult
	if is_final_sector():
		iron *= 1.5
		crystal *= 1.5
	return {"iron": int(ceil(iron)), "crystal": int(ceil(crystal))}


func can_afford(cost: Dictionary) -> bool:
	for k in cost:
		if float(res.get(k, 0.0)) < float(cost[k]):
			return false
	return true


func pay(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for k in cost:
		res[k] = float(res[k]) - float(cost[k])
	return true


func cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k in cost:
		parts.append("%s %d" % [RES_NAMES[k], int(cost[k])])
	return " / ".join(parts)


func roll_perks(n: int) -> Array:
	var pool: Array = []
	for p in PERKS:
		# 一度きりの効果は重複させない
		if p["id"] in ["oracle", "crystal_drill"] and p["id"] in perks:
			continue
		pool.append(p)
	pool.shuffle()
	return pool.slice(0, n)


func apply_perk(id: String) -> void:
	perks.append(id)
	match id:
		"greedy_drill":
			mine_mult *= 2.0
			fuel_burn_mult *= 1.2
		"advance":
			res["iron"] = float(res["iron"]) + 60.0
			warp_cost_mult *= 1.25
		"ice_refinery":
			ice_fuel_mult *= 2.0
			miner_mult *= 0.7
		"collector":
			collect_mult *= 2.0
		"big_storage":
			storage_mult *= 2.0
		"cheap_miner":
			miner_cost_growth = 1.0 + (miner_cost_growth - 1.0) * 0.5
		"fuel_eff":
			fuel_burn_mult *= 0.8
		"big_tank":
			max_fuel += 40.0
			fuel = max_fuel
		"scanner":
			scan_mult *= 1.5
		"oracle":
			oracle = true
		"stabilizer":
			instability_grace += 30.0
		"crystal_drill":
			crystal_drill = true


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best_score = int(cfg.get_value("stats", "best_score", 0))
		runs_played = int(cfg.get_value("stats", "runs_played", 0))


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("stats", "best_score", best_score)
	cfg.set_value("stats", "runs_played", runs_played)
	cfg.save(SAVE_PATH)
