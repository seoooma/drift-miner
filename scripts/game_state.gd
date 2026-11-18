extends Node
## ラン全体の状態（資源・燃料・セクター・パーク）を保持する Autoload。

signal run_over(reason: String)

const RES_NAMES := {"iron": "鉄", "ice": "氷", "crystal": "結晶"}

const PERKS := [
	{"id": "mine_speed", "name": "強化ドリル", "desc": "手掘りの速度 +50%"},
	{"id": "miner_speed", "name": "高速採掘機", "desc": "自動採掘機の速度 +50%"},
	{"id": "fuel_eff", "name": "省エネ推進器", "desc": "燃料消費 -25%"},
	{"id": "cheap_miner", "name": "簡易設計図", "desc": "採掘機のコスト -30%"},
	{"id": "big_tank", "name": "大型タンク", "desc": "最大燃料 +40（全回復）"},
	{"id": "scanner", "name": "広域スキャナー", "desc": "探索範囲 +50%"},
]

var seed_base: int = 0
var sector: int = 1
var res := {"iron": 0.0, "crystal": 0.0}
var fuel: float = 100.0
var max_fuel: float = 100.0
var alive: bool = true
var perks: Array[String] = []

var mine_mult: float = 1.0
var miner_mult: float = 1.0
var fuel_burn_mult: float = 1.0
var miner_cost_mult: float = 1.0
var scan_mult: float = 1.0


func new_run(seed_value: int = -1) -> void:
	seed_base = seed_value if seed_value >= 0 else randi()
	sector = 1
	res = {"iron": 0.0, "crystal": 0.0}
	max_fuel = 100.0
	fuel = max_fuel
	alive = true
	perks.clear()
	mine_mult = 1.0
	miner_mult = 1.0
	fuel_burn_mult = 1.0
	miner_cost_mult = 1.0
	scan_mult = 1.0


## セクターごとのシード。同じラン・同じセクターなら同じ地形になる。
func sector_seed() -> int:
	return hash("%d:%d" % [seed_base, sector])


func add_res(kind: String, amount: float) -> void:
	if amount <= 0.0:
		return
	if kind == "ice":
		# 氷はその場で燃料に精製される
		fuel = minf(max_fuel, fuel + amount * 0.8)
	else:
		res[kind] = float(res.get(kind, 0.0)) + amount


func burn_fuel(amount: float) -> void:
	if not alive:
		return
	fuel -= amount * fuel_burn_mult
	if fuel <= 0.0:
		fuel = 0.0
		alive = false
		run_over.emit("燃料切れ")


func miner_cost() -> Dictionary:
	return {"iron": int(ceil(10.0 * miner_cost_mult))}


func warp_cost() -> Dictionary:
	return {"iron": 20 + sector * 15, "crystal": 1 + sector * 2}


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
	var pool := PERKS.duplicate()
	pool.shuffle()
	return pool.slice(0, n)


func apply_perk(id: String) -> void:
	perks.append(id)
	match id:
		"mine_speed":
			mine_mult *= 1.5
		"miner_speed":
			miner_mult *= 1.5
		"fuel_eff":
			fuel_burn_mult *= 0.75
		"cheap_miner":
			miner_cost_mult *= 0.7
		"big_tank":
			max_fuel += 40.0
			fuel = max_fuel
		"scanner":
			scan_mult *= 1.5
