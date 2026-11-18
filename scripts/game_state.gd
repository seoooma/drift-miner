extends Node
## ラン全体の状態（資源・建物キット・燃料・セクター・パーク）と、
## ランをまたいで残る研究（メタ進行）を保持する Autoload。

signal run_over(reason: String, victory: bool)

const FINAL_SECTOR := 10
const SAVE_PATH := "user://drift_miner.cfg"

## 不安定化：セクター到着から猶予秒数の後、燃料消費が毎秒 RAMP ずつ増える（上限 MAX）。
const INSTABILITY_GRACE := 150.0
const INSTABILITY_RAMP := 0.012
const INSTABILITY_MAX := 3.0

const ITEMS := {
	"iron_ore": {"name": "鉄鉱石", "short": "鉄鉱", "color": Color(0.72, 0.75, 0.85)},
	"copper_ore": {"name": "銅鉱石", "short": "銅鉱", "color": Color(0.95, 0.55, 0.3)},
	"crystal": {"name": "結晶", "short": "結晶", "color": Color(0.9, 0.45, 1.0)},
	"plate": {"name": "鉄板", "short": "鉄板", "color": Color(0.85, 0.88, 0.95)},
	"wire": {"name": "銅線", "short": "銅線", "color": Color(1.0, 0.7, 0.4)},
	"circuit": {"name": "回路", "short": "回路", "color": Color(0.45, 1.0, 0.6)},
	"qcore": {"name": "量子コア", "short": "量子", "color": Color(0.5, 0.85, 1.0)},
}
const RAW_ITEMS := ["iron_ore", "copper_ore", "crystal"]
const MADE_ITEMS := ["plate", "wire", "circuit", "qcore"]

## 建物の定義。recipe があるものは母船の補給圏内に置く工場。
const BUILDINGS := {
	"miner": {"name": "採掘機", "cost": {"plate": 3}, "desc": "小惑星に設置。鉱石を掘って貯める"},
	"hub": {"name": "ドローンハブ", "cost": {"plate": 6, "wire": 6}, "desc": "周囲の採掘機から母船へ自動輸送"},
	"smelter": {"name": "製鉄炉", "cost": {"iron_ore": 12}, "desc": "鉄鉱石2 → 鉄板1（2秒）",
		"recipe": {"in": {"iron_ore": 2}, "out": {"plate": 1}, "time": 2.0}},
	"wiremill": {"name": "伸線機", "cost": {"plate": 4}, "desc": "銅鉱石1 → 銅線2（2秒）",
		"recipe": {"in": {"copper_ore": 1}, "out": {"wire": 2}, "time": 2.0}},
	"assembler": {"name": "組立機", "cost": {"plate": 8, "wire": 6}, "desc": "鉄板1＋銅線3 → 回路1（4秒）",
		"recipe": {"in": {"plate": 1, "wire": 3}, "out": {"circuit": 1}, "time": 4.0}},
	"quantum": {"name": "量子炉", "cost": {"circuit": 6, "plate": 10}, "desc": "結晶2＋回路1 → 量子コア1（6秒）",
		"recipe": {"in": {"crystal": 2, "circuit": 1}, "out": {"qcore": 1}, "time": 6.0}, "research": "quantum"},
}
const BUILD_ORDER := ["miner", "hub", "smelter", "wiremill", "assembler", "quantum"]

## 母艦の研究（ランをまたいで残る）
const RESEARCH := [
	{"id": "start_plate", "name": "初期資材", "desc": "鉄板 +15 を持って出撃", "cost": 6},
	{"id": "drill", "name": "強化ドリル", "desc": "手掘り速度 +50%", "cost": 8},
	{"id": "start_fuel", "name": "予備タンク", "desc": "最大燃料 +25", "cost": 10},
	{"id": "kit_assembler", "name": "組立機キット", "desc": "組立機を1台持って出撃", "cost": 12},
	{"id": "miner_storage", "name": "大型ホッパー", "desc": "採掘機の貯蔵量 +50%", "cost": 12},
	{"id": "forecast", "name": "隕石予報", "desc": "隕石の予告時間 2.5秒→4秒", "cost": 12},
	{"id": "kit_hub", "name": "ハブキット", "desc": "ドローンハブを1台持って出撃", "cost": 15},
	{"id": "quantum", "name": "量子炉の設計図", "desc": "量子炉を建設可能に（セクター5〜で必須）", "cost": 20},
	{"id": "stability", "name": "安定航法", "desc": "不安定化の猶予 +45秒", "cost": 20},
	{"id": "drones", "name": "ドローン増設", "desc": "各ハブのドローン +1", "cost": 25},
	{"id": "factory_speed", "name": "高効率工場", "desc": "全工場の速度 +25%", "cost": 30},
	{"id": "perk_pool", "name": "実験的強化", "desc": "ワープ時の強化候補に上位パークを追加", "cost": 30},
]

const PERKS := [
	{"id": "greedy_drill", "name": "貪欲ドリル", "desc": "手掘り速度 +100%\n代償：燃料消費 +20%"},
	{"id": "ice_refinery", "name": "氷精製炉", "desc": "氷→燃料の変換 2倍\n代償：工場の速度 -15%"},
	{"id": "collector", "name": "回収アーム", "desc": "採掘機からの直接回収範囲 +100%"},
	{"id": "big_storage", "name": "大型コンテナ", "desc": "採掘機の貯蔵量 +100%"},
	{"id": "fuel_eff", "name": "省エネ推進器", "desc": "燃料消費 -20%"},
	{"id": "big_tank", "name": "大型タンク", "desc": "最大燃料 +40（全回復）"},
	{"id": "scanner", "name": "広域スキャナー", "desc": "探索範囲 +50%"},
	{"id": "oracle", "name": "予知スキャナー", "desc": "ゲートの位置が最初から分かる"},
	{"id": "stabilizer", "name": "安定化装置", "desc": "不安定化の猶予 +30秒"},
	{"id": "overclock", "name": "オーバークロック", "desc": "工場の速度 +30%\n代償：燃料消費 +10%"},
	{"id": "kit_miner", "name": "採掘機パック", "desc": "採掘機キット +3"},
	{"id": "fast_drones", "name": "高速ドローン", "desc": "ドローンの速度 +50%"},
]
const ADVANCED_PERKS := [
	{"id": "kit_factory", "name": "工場コンテナ", "desc": "製鉄炉・伸線機・組立機のキット +1ずつ"},
	{"id": "salvage", "name": "回収業者", "desc": "漂流物の中身 2倍"},
	{"id": "crystal_drill", "name": "結晶ドリル", "desc": "採掘機が結晶も通常速度で掘る"},
]

# --- ラン中の状態 ---
var seed_base: int = 0
var sector: int = 1
var sector_type: String = "standard"
var sector_time: float = 0.0
var items := {}
var kits := {}
var fuel: float = 100.0
var max_fuel: float = 100.0
var alive: bool = true
var perks: Array[String] = []
var produced := {}
var derelicts_opened: int = 0

var mine_mult: float = 1.0
var miner_mult: float = 1.0
var factory_mult: float = 1.0
var fuel_burn_mult: float = 1.0
var scan_mult: float = 1.0
var ice_fuel_mult: float = 1.0
var collect_mult: float = 1.0
var storage_mult: float = 1.0
var drone_speed_mult: float = 1.0
var instability_grace: float = INSTABILITY_GRACE
var oracle: bool = false
var crystal_drill: bool = false
var salvage_mult: float = 1.0

# --- ランをまたいで残る状態 ---
var data_points: int = 0
var research := {}
var best_score: int = 0
var runs_played: int = 0
var best_sector: int = 0
var last_data_gain: int = 0


func _ready() -> void:
	_load()


func has_research(id: String) -> bool:
	return research.has(id)


func buy_research(id: String) -> bool:
	for r in RESEARCH:
		if r["id"] == id and not research.has(id) and data_points >= int(r["cost"]):
			data_points -= int(r["cost"])
			research[id] = true
			_save()
			return true
	return false


func new_run(seed_value: int = -1) -> void:
	seed_base = seed_value if seed_value >= 0 else randi()
	sector = 1
	sector_type = "standard"
	items = {}
	for k in ITEMS:
		items[k] = 0.0
	kits = {"miner": 3, "smelter": 1, "wiremill": 1}
	items["plate"] = 6.0
	max_fuel = 100.0
	alive = true
	perks.clear()
	produced = {}
	derelicts_opened = 0
	mine_mult = 1.0
	miner_mult = 1.0
	factory_mult = 1.0
	fuel_burn_mult = 1.0
	scan_mult = 1.0
	ice_fuel_mult = 1.0
	collect_mult = 1.0
	storage_mult = 1.0
	drone_speed_mult = 1.0
	instability_grace = INSTABILITY_GRACE
	oracle = false
	crystal_drill = false
	salvage_mult = 1.0
	# 研究の効果
	if has_research("start_plate"):
		items["plate"] += 15.0
	if has_research("drill"):
		mine_mult *= 1.5
	if has_research("start_fuel"):
		max_fuel += 25.0
	if has_research("kit_assembler"):
		add_kit("assembler", 1)
	if has_research("kit_hub"):
		add_kit("hub", 1)
	if has_research("miner_storage"):
		storage_mult *= 1.5
	if has_research("stability"):
		instability_grace += 45.0
	if has_research("factory_speed"):
		factory_mult *= 1.25
	fuel = max_fuel
	start_sector()


func start_sector() -> void:
	sector_time = 0.0


func meteor_warning() -> float:
	return 4.0 if has_research("forecast") else 2.5


func drones_per_hub() -> int:
	return 3 if has_research("drones") else 2


## セクターごとのシード。同じラン・同じセクターなら同じ地形になる。
func sector_seed() -> int:
	return hash("%d:%d" % [seed_base, sector])


func item_name(k: String) -> String:
	return String(ITEMS[k]["name"])


func count(k: String) -> int:
	return int(floor(float(items.get(k, 0.0)) + 0.001))


## 鉱石を受け取る。氷はその場で燃料に精製される。
func add_ore(kind: String, amount: float) -> void:
	if amount <= 0.0:
		return
	if kind == "ice":
		fuel = minf(max_fuel, fuel + amount * 0.5 * ice_fuel_mult)
		return
	var key := kind if kind == "crystal" else kind + "_ore"
	add_item(key, amount)


func add_item(k: String, amount: float) -> void:
	items[k] = float(items.get(k, 0.0)) + amount


func note_produced(k: String, amount: float) -> void:
	produced[k] = float(produced.get(k, 0.0)) + amount


func add_kit(b: String, n: int) -> void:
	kits[b] = int(kits.get(b, 0)) + n


func kit_count(b: String) -> int:
	return int(kits.get(b, 0))


func building_unlocked(b: String) -> bool:
	var def: Dictionary = BUILDINGS[b]
	return not def.has("research") or has_research(String(def["research"]))


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


func data_gain(victory: bool) -> int:
	var g := (sector - 1) * 6
	g += int(float(produced.get("circuit", 0.0)) * 0.5)
	g += int(float(produced.get("qcore", 0.0)) * 3.0)
	g += derelicts_opened * 2
	if victory:
		g += 40
	return maxi(g, 2)


func end_run(reason: String, victory: bool) -> void:
	if not alive:
		return
	alive = false
	runs_played += 1
	best_sector = maxi(best_sector, sector)
	last_data_gain = data_gain(victory)
	data_points += last_data_gain
	var s := score(victory)
	if s > best_score:
		best_score = s
	_save()
	run_over.emit(reason, victory)


func score(victory: bool = false) -> int:
	var s := (sector - 1) * 1000 + int(fuel) * 5
	for k in MADE_ITEMS:
		s += int(float(produced.get(k, 0.0))) * (1 if k in ["plate", "wire"] else 20)
	if victory:
		s += 5000
	return s


func is_final_sector() -> bool:
	return sector >= FINAL_SECTOR


func warp_cost() -> Dictionary:
	var c := {"circuit": 2 + sector}
	if sector >= 5:
		c["qcore"] = sector - 3
	if is_final_sector():
		for k in c:
			c[k] = int(ceil(float(c[k]) * 1.5))
	return c


func can_afford(cost: Dictionary) -> bool:
	for k in cost:
		if float(items.get(k, 0.0)) + 0.001 < float(cost[k]):
			return false
	return true


func pay(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for k in cost:
		items[k] = float(items[k]) - float(cost[k])
	return true


func cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k in cost:
		parts.append("%s %d" % [item_name(k), int(cost[k])])
	return " / ".join(parts)


func roll_perks(n: int) -> Array:
	var pool: Array = []
	var all: Array = PERKS.duplicate()
	if has_research("perk_pool"):
		all.append_array(ADVANCED_PERKS)
	for p in all:
		if p["id"] in ["oracle", "crystal_drill", "salvage"] and p["id"] in perks:
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
		"ice_refinery":
			ice_fuel_mult *= 2.0
			factory_mult *= 0.85
		"collector":
			collect_mult *= 2.0
		"big_storage":
			storage_mult *= 2.0
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
		"overclock":
			factory_mult *= 1.3
			fuel_burn_mult *= 1.1
		"kit_miner":
			add_kit("miner", 3)
		"fast_drones":
			drone_speed_mult *= 1.5
		"kit_factory":
			add_kit("smelter", 1)
			add_kit("wiremill", 1)
			add_kit("assembler", 1)
		"salvage":
			salvage_mult = 2.0
		"crystal_drill":
			crystal_drill = true


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best_score = int(cfg.get_value("stats", "best_score", 0))
		runs_played = int(cfg.get_value("stats", "runs_played", 0))
		best_sector = int(cfg.get_value("stats", "best_sector", 0))
		data_points = int(cfg.get_value("meta", "data_points", 0))
		var r: Array = cfg.get_value("meta", "research", [])
		for id in r:
			research[String(id)] = true


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("stats", "best_score", best_score)
	cfg.set_value("stats", "runs_played", runs_played)
	cfg.set_value("stats", "best_sector", best_sector)
	cfg.set_value("meta", "data_points", data_points)
	cfg.set_value("meta", "research", research.keys())
	cfg.save(SAVE_PATH)
