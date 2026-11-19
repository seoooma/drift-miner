extends Node
## ラン全体の状態（資源・建物キット・燃料・セクター・レベル・カード）と、
## ランをまたいで残るスキルツリー（メタ進行）を保持する Autoload。

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
const XP_VALUE := {"plate": 1.0, "wire": 0.5, "circuit": 4.0, "qcore": 15.0}

## 建物。recipe があるものは母船の補給圏内に自動で建つ工場。
const BUILDINGS := {
	"miner": {"name": "採掘機", "cost": {"plate": 4}},
	"hub": {"name": "ドローンハブ", "cost": {}},
	"smelter": {"name": "製鉄炉", "recipe": {"in": {"iron_ore": 2}, "out": {"plate": 1}, "time": 2.0}},
	"wiremill": {"name": "伸線機", "recipe": {"in": {"copper_ore": 1}, "out": {"wire": 2}, "time": 2.0}},
	"assembler": {"name": "組立機", "recipe": {"in": {"plate": 1, "wire": 3}, "out": {"circuit": 1}, "time": 4.0}},
	"quantum": {"name": "量子炉", "recipe": {"in": {"crystal": 2, "circuit": 1}, "out": {"qcore": 1}, "time": 6.0}},
}
const FACTORIES := ["smelter", "wiremill", "assembler", "quantum"]

## 母艦のスキルツリー（ランをまたいで残る）。req は前提スキル。
const SKILLS := [
	{"id": "start_plate", "tier": 1, "name": "初期資材", "desc": "鉄板 +20 を持って出撃", "cost": 5, "req": ""},
	{"id": "drill", "tier": 1, "name": "強化ドリル", "desc": "自機の採掘 +50%", "cost": 5, "req": ""},
	{"id": "start_fuel", "tier": 1, "name": "予備タンク", "desc": "最大燃料 +25", "cost": 6, "req": ""},
	{"id": "smelt_line", "tier": 2, "name": "製鉄ライン", "desc": "製鉄炉 +1 で出撃", "cost": 10, "req": "start_plate"},
	{"id": "mass_miner", "tier": 2, "name": "採掘機の量産", "desc": "採掘機 +3、設置上限 +3", "cost": 10, "req": "drill"},
	{"id": "forecast", "tier": 2, "name": "隕石予報", "desc": "隕石の予告 2.5秒→4秒", "cost": 8, "req": "start_fuel"},
	{"id": "assembly_line", "tier": 3, "name": "組立ライン", "desc": "組立機・伸線機 +1 で出撃", "cost": 16, "req": "smelt_line"},
	{"id": "drones", "tier": 3, "name": "ドローン増設", "desc": "各ハブのドローン +1", "cost": 16, "req": "mass_miner"},
	{"id": "stability", "tier": 3, "name": "安定航法", "desc": "不安定化の猶予 +45秒", "cost": 14, "req": "forecast"},
	{"id": "quantum", "tier": 4, "name": "量子炉の設計図", "desc": "カードに量子炉が出る（セクター5〜で必須）", "cost": 22, "req": "assembly_line"},
	{"id": "factory_speed", "tier": 4, "name": "高効率工場", "desc": "全工場の速度 +25%", "cost": 24, "req": "drones"},
	{"id": "more_cards", "tier": 4, "name": "選択肢の拡張", "desc": "強化カードの選択肢 +1", "cost": 22, "req": "stability"},
	{"id": "start_quantum", "tier": 5, "name": "量子ライン", "desc": "量子炉 +1 で出撃", "cost": 35, "req": "quantum"},
	{"id": "data_boost", "tier": 5, "name": "観測ログ", "desc": "得られる研究データ +50%", "cost": 30, "req": "factory_speed"},
	{"id": "reroll", "tier": 5, "name": "再抽選", "desc": "カード選択時に1回引き直せる", "cost": 28, "req": "more_cards"},
]

## ラン中の強化カード（レベルアップとワープ時に選ぶ）
const CARDS := [
	{"id": "add_smelter", "name": "製鉄炉 増設", "desc": "製鉄炉が1台増える", "w": 3},
	{"id": "add_wiremill", "name": "伸線機 増設", "desc": "伸線機が1台増える", "w": 3},
	{"id": "add_assembler", "name": "組立機 増設", "desc": "組立機が1台増える", "w": 3},
	{"id": "add_quantum", "name": "量子炉 増設", "desc": "量子炉が1台増える", "w": 3, "skill": "quantum"},
	{"id": "add_miners", "name": "採掘機パック", "desc": "採掘機 +3、設置上限 +3", "w": 3},
	{"id": "add_hub", "name": "ドローンハブ 増設", "desc": "ドローンハブが1台増える", "w": 2},
	{"id": "smelt_speed", "name": "高温炉", "desc": "製鉄炉の速度 +40%", "w": 2},
	{"id": "wire_speed", "name": "精密伸線", "desc": "伸線機の速度 +40%", "w": 2},
	{"id": "asm_speed", "name": "自動組立", "desc": "組立機の速度 +40%", "w": 2},
	{"id": "q_speed", "name": "量子共鳴", "desc": "量子炉の速度 +50%", "w": 2, "skill": "quantum"},
	{"id": "miner_rate", "name": "採掘機の改良", "desc": "採掘機の速度 +40%", "w": 2},
	{"id": "storage", "name": "大型ホッパー", "desc": "採掘機の貯蔵 +60%", "w": 1},
	{"id": "drone_speed", "name": "高速ドローン", "desc": "ドローンの速度 +50%", "w": 2},
	{"id": "drone_carry", "name": "積載拡張", "desc": "ドローンの積載 +50%", "w": 2},
	{"id": "ship_drill", "name": "掘削レーザー", "desc": "自機の採掘 +60%", "w": 2},
	{"id": "fuel_eff", "name": "省エネ推進器", "desc": "燃料消費 -20%", "w": 2},
	{"id": "ice_refinery", "name": "氷精製炉", "desc": "氷→燃料の変換 2倍", "w": 1},
	{"id": "big_tank", "name": "大型タンク", "desc": "最大燃料 +40（全回復）", "w": 1},
	{"id": "scanner", "name": "広域スキャナー", "desc": "探索範囲 +50%", "w": 1},
	{"id": "stabilizer", "name": "安定化装置", "desc": "不安定化の猶予 +30秒", "w": 1},
	{"id": "oracle", "name": "予知スキャナー", "desc": "ゲートの位置が最初から分かる", "w": 1, "once": true},
	{"id": "overdrive", "name": "オーバードライブ", "desc": "全工場 +35%\n代償：燃料消費 +20%", "w": 1},
	{"id": "crystal_drill", "name": "結晶ドリル", "desc": "採掘機が結晶も全速で掘る", "w": 2, "skill": "quantum", "once": true},
	{"id": "salvager", "name": "回収業者", "desc": "漂流物の中身 2倍", "w": 1, "once": true},
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
var cards_taken: Array[String] = []
var produced := {}
var derelicts_opened: int = 0
var level: int = 1
var xp: float = 0.0
var pending_levels: int = 0

var ship_mine_mult: float = 1.0
var miner_mult: float = 1.0
var factory_mult: float = 1.0
var type_mult := {}
var fuel_burn_mult: float = 1.0
var scan_mult: float = 1.0
var ice_fuel_mult: float = 1.0
var storage_mult: float = 1.0
var drone_speed_mult: float = 1.0
var drone_carry_mult: float = 1.0
var miner_cap: int = 6
var instability_grace: float = INSTABILITY_GRACE
var oracle: bool = false
var salvage_mult: float = 1.0
var crystal_drill: bool = false
var collect_mult: float = 1.0

# --- ランをまたいで残る状態 ---
var data_points: int = 0
var skills := {}
var best_score: int = 0
var runs_played: int = 0
var best_sector: int = 0
var last_data_gain: int = 0


func _ready() -> void:
	_load()


func has_skill(id: String) -> bool:
	return skills.has(id)


func skill_def(id: String) -> Dictionary:
	for s in SKILLS:
		if s["id"] == id:
			return s
	return {}


func skill_available(id: String) -> bool:
	var s := skill_def(id)
	var req := String(s.get("req", ""))
	return req == "" or has_skill(req)


func buy_skill(id: String) -> bool:
	var s := skill_def(id)
	if s.is_empty() or has_skill(id) or not skill_available(id) or data_points < int(s["cost"]):
		return false
	data_points -= int(s["cost"])
	skills[id] = true
	_save()
	return true


func new_run(seed_value: int = -1) -> void:
	seed_base = seed_value if seed_value >= 0 else randi()
	sector = 1
	sector_type = "standard"
	items = {}
	for k in ITEMS:
		items[k] = 0.0
	items["plate"] = 8.0
	kits = {"miner": 4, "hub": 1, "smelter": 1, "wiremill": 1, "assembler": 1}
	max_fuel = 100.0
	alive = true
	cards_taken.clear()
	produced = {}
	derelicts_opened = 0
	level = 1
	xp = 0.0
	pending_levels = 0
	ship_mine_mult = 1.0
	miner_mult = 1.0
	factory_mult = 1.0
	type_mult = {}
	fuel_burn_mult = 1.0
	scan_mult = 1.0
	ice_fuel_mult = 1.0
	storage_mult = 1.0
	drone_speed_mult = 1.0
	drone_carry_mult = 1.0
	miner_cap = 6
	instability_grace = INSTABILITY_GRACE
	oracle = false
	salvage_mult = 1.0
	crystal_drill = false
	# スキルの効果
	if has_skill("start_plate"):
		items["plate"] += 20.0
	if has_skill("drill"):
		ship_mine_mult *= 1.5
	if has_skill("start_fuel"):
		max_fuel += 25.0
	if has_skill("smelt_line"):
		add_kit("smelter", 1)
	if has_skill("mass_miner"):
		add_kit("miner", 3)
		miner_cap += 3
	if has_skill("assembly_line"):
		add_kit("assembler", 1)
		add_kit("wiremill", 1)
	if has_skill("stability"):
		instability_grace += 45.0
	if has_skill("factory_speed"):
		factory_mult *= 1.25
	if has_skill("start_quantum"):
		add_kit("quantum", 1)
	fuel = max_fuel
	start_sector()


func start_sector() -> void:
	sector_time = 0.0


func meteor_warning() -> float:
	return 4.0 if has_skill("forecast") else 2.5


func drones_per_hub() -> int:
	return 3 if has_skill("drones") else 2


func card_choices() -> int:
	return 4 if has_skill("more_cards") else 3


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
	add_xp(float(XP_VALUE.get(k, 0.0)) * amount)


func xp_needed() -> float:
	return 12.0 * pow(float(level), 1.35)


func add_xp(amount: float) -> void:
	xp += amount
	while xp >= xp_needed():
		xp -= xp_needed()
		level += 1
		pending_levels += 1


func add_kit(b: String, n: int) -> void:
	kits[b] = int(kits.get(b, 0)) + n


func kit_count(b: String) -> int:
	return int(kits.get(b, 0))


func speed_of(btype: String) -> float:
	return factory_mult * float(type_mult.get(btype, 1.0))


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
	var g := float((sector - 1) * 6)
	g += float(produced.get("circuit", 0.0)) * 0.4
	g += float(produced.get("qcore", 0.0)) * 2.0
	g += derelicts_opened * 1.0
	g += level * 0.5
	if victory:
		g += 40.0
	if has_skill("data_boost"):
		g *= 1.5
	return maxi(int(g), 3)


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
	var s := (sector - 1) * 1000 + int(fuel) * 5 + level * 50
	for k in MADE_ITEMS:
		s += int(float(produced.get(k, 0.0))) * (1 if k in ["plate", "wire"] else 20)
	if victory:
		s += 5000
	return s


## 量子コアが要るのに、このランでは作れない状態か。
func quantum_blocked() -> bool:
	return warp_cost().has("qcore") and not has_skill("quantum") and count("qcore") < int(warp_cost()["qcore"])


func is_final_sector() -> bool:
	return sector >= FINAL_SECTOR


func warp_cost() -> Dictionary:
	# 後半ほど急に重くなる。前のセクターの在庫だけでは素通りできない
	var c := {"circuit": int(round(3.0 + 2.0 * sector + 0.9 * sector * sector))}
	if sector >= 5:
		c["qcore"] = (sector - 4) * 3
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


func roll_cards(n: int) -> Array:
	var pool: Array = []
	for c in CARDS:
		if c.has("skill") and not has_skill(String(c["skill"])):
			continue
		if c.get("once", false) and String(c["id"]) in cards_taken:
			continue
		pool.append(c)
	var out: Array = []
	while out.size() < n and not pool.is_empty():
		var total := 0.0
		for c in pool:
			total += float(c["w"])
		var r := randf() * total
		for i in pool.size():
			r -= float(pool[i]["w"])
			if r <= 0.0:
				out.append(pool[i])
				pool.remove_at(i)
				break
	return out


func apply_card(id: String) -> void:
	cards_taken.append(id)
	match id:
		"add_smelter":
			add_kit("smelter", 1)
		"add_wiremill":
			add_kit("wiremill", 1)
		"add_assembler":
			add_kit("assembler", 1)
		"add_quantum":
			add_kit("quantum", 1)
		"add_miners":
			add_kit("miner", 3)
			miner_cap += 3
		"add_hub":
			add_kit("hub", 1)
		"smelt_speed":
			type_mult["smelter"] = float(type_mult.get("smelter", 1.0)) * 1.4
		"wire_speed":
			type_mult["wiremill"] = float(type_mult.get("wiremill", 1.0)) * 1.4
		"asm_speed":
			type_mult["assembler"] = float(type_mult.get("assembler", 1.0)) * 1.4
		"q_speed":
			type_mult["quantum"] = float(type_mult.get("quantum", 1.0)) * 1.5
		"miner_rate":
			miner_mult *= 1.4
		"storage":
			storage_mult *= 1.6
		"drone_speed":
			drone_speed_mult *= 1.5
		"drone_carry":
			drone_carry_mult *= 1.5
		"ship_drill":
			ship_mine_mult *= 1.6
		"fuel_eff":
			fuel_burn_mult *= 0.8
		"ice_refinery":
			ice_fuel_mult *= 2.0
		"big_tank":
			max_fuel += 40.0
			fuel = max_fuel
		"scanner":
			scan_mult *= 1.5
		"stabilizer":
			instability_grace += 30.0
		"oracle":
			oracle = true
		"overdrive":
			factory_mult *= 1.35
			fuel_burn_mult *= 1.2
		"salvager":
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
		var r: Array = cfg.get_value("meta", "skills", [])
		for id in r:
			skills[String(id)] = true


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("stats", "best_score", best_score)
	cfg.set_value("stats", "runs_played", runs_played)
	cfg.set_value("stats", "best_sector", best_sector)
	cfg.set_value("meta", "data_points", data_points)
	cfg.set_value("meta", "skills", skills.keys())
	cfg.save(SAVE_PATH)
