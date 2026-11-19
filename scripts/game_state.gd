extends Node
## ゲームの状態（Autoload）。
## ラン：クレジット、ツールのレベル、いまの惑星、強化カード。帰還（プレステージ）でリセットされる。
## メタ：研究データとスキル。帰還しても残る。どちらも保存し、閉じていた間の放置報酬も計算する。

signal changed

const SAVE_PATH := "user://drift_miner_idle.cfg"
const PLANETS_PER_GALAXY := 5
const BOSS_TIME := 40.0
const CLEAR_RATIO := 0.85
const OFFLINE_RATE := 0.5
const OFFLINE_CAP_H := 2.0

## 採掘ツール。dps は Lv1 のときの毎秒ダメージ。Lv25 ごとに2倍。
const TOOLS := [
	{"id": "drone", "name": "採掘ドローン", "desc": "惑星のまわりを回り、表面を削る", "dps": 3.0, "cost": 8.0, "growth": 1.12, "color": Color(0.35, 0.9, 1.0)},
	{"id": "cutter", "name": "回転カッター", "desc": "地表を転がりながら周囲を切り崩す", "dps": 22.0, "cost": 120.0, "growth": 1.13, "color": Color(1.0, 0.62, 0.25)},
	{"id": "laser", "name": "掃射レーザー", "desc": "衛星から地表をなぎ払う貫通ビーム", "dps": 160.0, "cost": 2200.0, "growth": 1.14, "color": Color(1.0, 0.3, 0.4)},
	{"id": "bomb", "name": "重力爆雷", "desc": "一定間隔で落ちて広い範囲を砕く", "dps": 1200.0, "cost": 4.0e4, "growth": 1.15, "color": Color(0.8, 0.45, 1.0)},
	{"id": "lance", "name": "コアランス", "desc": "中心核へまっすぐ穴を掘り進む", "dps": 9500.0, "cost": 8.0e5, "growth": 1.16, "color": Color(0.45, 1.0, 0.5)},
	{"id": "swarm", "name": "ナノスウォーム", "desc": "無数の微小機械が全面を少しずつ食べる", "dps": 80000.0, "cost": 1.6e7, "growth": 1.17, "color": Color(1.0, 0.9, 0.35)},
]

## 鉱石の種類。hp と value は岩を1とした倍率。
const ORES := [
	{"name": "岩", "hp": 1.0, "value": 1.0},
	{"name": "鉄", "hp": 1.2, "value": 2.0},
	{"name": "銅", "hp": 1.3, "value": 3.0},
	{"name": "金", "hp": 1.6, "value": 8.0},
	{"name": "結晶", "hp": 2.5, "value": 20.0},
	{"name": "核", "hp": 3.0, "value": 6.0},
]
const ORE_COLORS := [Color(0, 0, 0), Color(0.75, 0.78, 0.85), Color(0.95, 0.55, 0.3), Color(1.0, 0.85, 0.25), Color(0.85, 0.45, 1.0), Color(1.0, 0.45, 0.25)]

## 惑星を割るたびに3枚から1枚選ぶ強化カード（ランの間だけ有効）
const CARDS := [
	{"id": "tool_boost", "name": "%s 強化", "desc": "%sの威力 ×1.6", "w": 6, "rare": 0},
	{"id": "all_dps", "name": "総合出力", "desc": "全ツールの威力 +30%", "w": 4, "rare": 0},
	{"id": "value", "name": "鉱石鑑定", "desc": "獲得クレジット +35%", "w": 4, "rare": 0},
	{"id": "discount", "name": "値切り交渉", "desc": "ツールの強化費用 -12%", "w": 3, "rare": 0},
	{"id": "tap", "name": "手掘りの達人", "desc": "タップの威力 ×2.5", "w": 2, "rare": 0},
	{"id": "rich", "name": "鉱脈探知", "desc": "金と結晶が出やすくなる", "w": 2, "rare": 1},
	{"id": "jackpot", "name": "大当たり", "desc": "砕いた岩の6%がクレジット ×10", "w": 2, "rare": 1},
	{"id": "interest", "name": "複利運用", "desc": "10秒ごとに所持クレジットの2%を得る", "w": 1, "rare": 1},
	{"id": "quick", "name": "崩壊促進", "desc": "惑星が早く割れる（必要量 -8%）", "w": 1, "rare": 1, "max": 2},
	{"id": "boss_time", "name": "時間延長", "desc": "巨大惑星の制限時間 +15秒", "w": 2, "rare": 0, "max": 3},
	{"id": "overclock", "name": "過負荷運転", "desc": "全ツールの威力 ×2\n代償：強化費用 +25%", "w": 1, "rare": 2},
]

## スキル（研究データで強化、帰還しても残る）。req は前提スキルとそのレベル。
const SKILLS := [
	{"id": "power", "name": "採掘効率", "desc": "全ツールの威力 +25%", "max": 30, "cost": 1.0, "growth": 1.35, "req": "", "rl": 0, "color": Color(1.0, 0.4, 0.35)},
	{"id": "appraise", "name": "鉱石鑑定", "desc": "獲得クレジット +20%", "max": 30, "cost": 1.0, "growth": 1.35, "req": "", "rl": 0, "color": Color(1.0, 0.85, 0.3)},
	{"id": "seed", "name": "初期資金", "desc": "出発時のクレジット ×5", "max": 8, "cost": 2.0, "growth": 1.8, "req": "", "rl": 0, "color": Color(0.5, 1.0, 0.55)},
	{"id": "drones", "name": "ドローン増設", "desc": "採掘ドローン +1機", "max": 5, "cost": 3.0, "growth": 2.0, "req": "power", "rl": 2, "color": Color(0.35, 0.9, 1.0)},
	{"id": "tapper", "name": "精密掘削", "desc": "タップの威力 ×1.5", "max": 10, "cost": 2.0, "growth": 1.5, "req": "appraise", "rl": 2, "color": Color(1.0, 0.6, 0.3)},
	{"id": "thrift", "name": "量産体制", "desc": "ツールの強化費用 -4%", "max": 10, "cost": 3.0, "growth": 1.6, "req": "seed", "rl": 2, "color": Color(0.6, 1.0, 0.8)},
	{"id": "choices", "name": "選択肢の拡張", "desc": "強化カードの選択肢 +1", "max": 2, "cost": 12.0, "growth": 4.0, "req": "drones", "rl": 2, "color": Color(0.85, 0.5, 1.0)},
	{"id": "reroll", "name": "再抽選", "desc": "惑星ごとにカードを引き直せる回数 +1", "max": 3, "cost": 8.0, "growth": 3.0, "req": "tapper", "rl": 3, "color": Color(0.95, 0.45, 0.9)},
	{"id": "autobuy", "name": "自動強化", "desc": "一番安いツールを自動で強化", "max": 1, "cost": 15.0, "growth": 1.0, "req": "thrift", "rl": 3, "color": Color(0.4, 0.8, 1.0)},
	{"id": "idle", "name": "放置報酬", "desc": "閉じている間の報酬 +25%・上限 +1時間", "max": 6, "cost": 6.0, "growth": 1.9, "req": "autobuy", "rl": 1, "color": Color(0.7, 0.75, 1.0)},
	{"id": "boss", "name": "巨大惑星対策", "desc": "巨大惑星の制限時間 +10秒", "max": 4, "cost": 8.0, "growth": 2.2, "req": "choices", "rl": 1, "color": Color(1.0, 0.5, 0.5)},
	{"id": "research", "name": "観測ログ", "desc": "帰還時の研究データ +15%", "max": 20, "cost": 10.0, "growth": 1.5, "req": "reroll", "rl": 1, "color": Color(0.5, 0.9, 1.0)},
]

# --- ラン ---
var run_seed: int = 0
var credits: float = 0.0
var total_earned: float = 0.0
var tool_levels := {}
var planet: int = 1
var best_planet_run: int = 1
var cards := {}  # id -> 回数（tool_boost は "tool_boost:drone" など）
var income_rate: float = 0.0  # 直近の毎秒獲得量（放置報酬の計算に使う）

# --- メタ ---
var data: float = 0.0
var skills := {}
var best_planet: int = 1
var prestiges: int = 0
var offline_gain: float = 0.0
var offline_secs: float = 0.0

var _save_t: float = 0.0
var _interest_t: float = 0.0
var _income_acc: float = 0.0
var _income_t: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	reset_run()
	_load()


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	_income_t += delta
	if _income_t >= 5.0:
		income_rate = lerpf(income_rate, _income_acc / _income_t, 0.5)
		_income_acc = 0.0
		_income_t = 0.0
	if card_count("interest") > 0:
		_interest_t += delta
		if _interest_t >= 10.0:
			_interest_t = 0.0
			earn(credits * 0.02 * card_count("interest"), false)
	_save_t += delta
	if _save_t >= 5.0:
		_save_t = 0.0
		save()


# ---------------------------------------------------------------- 数字の表示


const SUFFIX := ["", "K", "M", "B", "T", "aa", "ab", "ac", "ad", "ae", "af", "ag", "ah"]


static func fmt(x: float) -> String:
	if x < 1000.0:
		if x < 10.0 and absf(x - roundf(x)) > 0.05:
			return "%.1f" % x
		return str(int(x))
	var e := 0
	while x >= 1000.0 and e < SUFFIX.size() - 1:
		x /= 1000.0
		e += 1
	if x >= 100.0:
		return "%d%s" % [int(x), SUFFIX[e]]
	return "%.2f%s" % [x, SUFFIX[e]]


# ---------------------------------------------------------------- ラン


func reset_run() -> void:
	run_seed = randi()
	credits = 15.0 * pow(5.0, skill_level("seed"))
	total_earned = 0.0
	tool_levels = {}
	for t in TOOLS:
		tool_levels[t["id"]] = 0
	tool_levels["drone"] = 1
	planet = 1
	best_planet_run = 1
	cards = {}
	income_rate = 0.0


func galaxy() -> int:
	return (planet - 1) / PLANETS_PER_GALAXY + 1


func planet_in_galaxy() -> int:
	return (planet - 1) % PLANETS_PER_GALAXY + 1


func is_boss() -> bool:
	return planet_in_galaxy() == PLANETS_PER_GALAXY


func boss_time() -> float:
	return BOSS_TIME + 10.0 * skill_level("boss") + 15.0 * card_count("boss_time")


## 1マスの基本耐久。惑星ごとに 1.5 倍で硬くなる。
func cell_hp() -> float:
	return 1.2 * pow(1.5, planet - 1) * (2.5 if is_boss() else 1.0)


## 1マスを砕いたときの基本クレジット。
func cell_value() -> float:
	return 0.9 * pow(1.47, planet - 1) * value_mult() * (2.0 if is_boss() else 1.0)


func clear_ratio() -> float:
	return CLEAR_RATIO - 0.08 * card_count("quick")


func rich_ores() -> bool:
	return card_count("rich") > 0


func value_mult() -> float:
	return pow(1.2, skill_level("appraise")) * pow(1.35, card_count("value"))


func earn(amount: float, track: bool = true) -> void:
	credits += amount
	total_earned += amount
	if track:
		_income_acc += amount


# ---------------------------------------------------------------- ツール


func tool_def(id: String) -> Dictionary:
	for t in TOOLS:
		if t["id"] == id:
			return t
	return {}


func tool_level(id: String) -> int:
	return int(tool_levels.get(id, 0))


func dps_mult() -> float:
	var m := pow(1.25, skill_level("power")) * pow(1.3, card_count("all_dps"))
	m *= pow(2.0, card_count("overclock"))
	return m


func tool_dps_at(id: String, lv: int) -> float:
	if lv <= 0:
		return 0.0
	var t := tool_def(id)
	var d := float(t["dps"]) * lv * pow(2.0, lv / 25)
	return d * dps_mult() * pow(1.6, card_count("tool_boost:" + id))


func tool_dps(id: String) -> float:
	return tool_dps_at(id, tool_level(id))


func total_dps() -> float:
	var s := 0.0
	for t in TOOLS:
		s += tool_dps(String(t["id"]))
	return s


func cost_mult() -> float:
	var m := pow(0.96, skill_level("thrift")) * pow(0.88, card_count("discount"))
	m *= pow(1.25, card_count("overclock"))
	return m


## Lv lv から n 段強化する費用。
func upgrade_cost(id: String, n: int = 1) -> float:
	var t := tool_def(id)
	var lv := tool_level(id)
	var g := float(t["growth"])
	var base := float(t["cost"]) * cost_mult() * pow(g, lv)
	if n == 1:
		return base
	return base * (pow(g, n) - 1.0) / (g - 1.0)


## いまのクレジットで買える段数（上限 cap、0 なら無制限）。
func affordable(id: String, cap: int) -> int:
	var n := 0
	while (cap == 0 or n < cap) and n < 1000:
		if upgrade_cost(id, n + 1) > credits:
			break
		n += 1
	return n


func buy_tool(id: String, n: int = 1) -> bool:
	if n <= 0:
		return false
	var c := upgrade_cost(id, n)
	if c > credits:
		return false
	credits -= c
	tool_levels[id] = tool_level(id) + n
	changed.emit()
	return true


## 次に2倍になるレベルまでの進み具合（0〜1）
func milestone_frac(id: String) -> float:
	return float(tool_level(id) % 25) / 25.0


func tap_damage() -> float:
	return maxf(2.0, total_dps() * 0.06) * pow(1.5, skill_level("tapper")) * pow(2.5, card_count("tap"))


func drone_count() -> int:
	return 1 + skill_level("drones")


# ---------------------------------------------------------------- カード


func card_count(id: String) -> int:
	return int(cards.get(id, 0))


func card_choices() -> int:
	return 3 + skill_level("choices")


func rerolls() -> int:
	return skill_level("reroll")


## 強化カードを n 枚引く。返り値の各要素：{"key", "name", "desc", "rare"}
func roll_cards(n: int) -> Array:
	var pool: Array = []
	for c in CARDS:
		var id := String(c["id"])
		if c.has("max") and card_count(id) >= int(c["max"]):
			continue
		if id == "boss_time" and planet_in_galaxy() < 3:
			continue
		if id == "tool_boost":
			for t in TOOLS:
				if tool_level(String(t["id"])) > 0:
					pool.append({"key": "tool_boost:" + String(t["id"]), "name": String(c["name"]) % t["name"], "desc": String(c["desc"]) % t["name"], "rare": 0, "w": 2.0, "color": t["color"]})
			continue
		pool.append({"key": id, "name": c["name"], "desc": c["desc"], "rare": c["rare"], "w": float(c["w"])})
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


func take_card(key: String) -> void:
	cards[key] = card_count(key) + 1
	changed.emit()


## いまのランで取ったカードの一覧（表示用）
func card_summary() -> Array:
	var out: Array = []
	for k in cards:
		var name := String(k)
		if name.begins_with("tool_boost:"):
			name = "%s 強化" % tool_def(name.trim_prefix("tool_boost:"))["name"]
		else:
			for c in CARDS:
				if c["id"] == k:
					name = String(c["name"])
		out.append("%s ×%d" % [name, int(cards[k])])
	return out


# ---------------------------------------------------------------- 帰還とスキル


## いま帰還すると得られる研究データ
func prestige_gain() -> int:
	var p := best_planet_run - 1
	if p < 5:
		return 0
	var g := pow(float(p) / 5.0, 1.8) * 2.0
	g *= pow(1.15, skill_level("research"))
	return int(g)


func prestige() -> void:
	data += prestige_gain()
	prestiges += 1
	best_planet = maxi(best_planet, best_planet_run)
	reset_run()
	save()
	changed.emit()


func skill_def(id: String) -> Dictionary:
	for s in SKILLS:
		if s["id"] == id:
			return s
	return {}


func skill_level(id: String) -> int:
	return int(skills.get(id, 0))


func skill_cost(id: String) -> float:
	var s := skill_def(id)
	return ceilf(float(s["cost"]) * pow(float(s["growth"]), skill_level(id)))


func skill_open(id: String) -> bool:
	var s := skill_def(id)
	var req := String(s["req"])
	return req == "" or skill_level(req) >= int(s["rl"])


func skill_maxed(id: String) -> bool:
	return skill_level(id) >= int(skill_def(id)["max"])


func can_buy_skill(id: String) -> bool:
	return skill_open(id) and not skill_maxed(id) and data >= skill_cost(id)


func buy_skill(id: String) -> bool:
	if not can_buy_skill(id):
		return false
	data -= skill_cost(id)
	skills[id] = skill_level(id) + 1
	save()
	changed.emit()
	return true


## 一番安いスキルから、買えるだけ買う。
func buy_all_skills() -> int:
	var n := 0
	while n < 500:
		var best := ""
		var best_c := INF
		for s in SKILLS:
			var id := String(s["id"])
			if can_buy_skill(id) and skill_cost(id) < best_c:
				best = id
				best_c = skill_cost(id)
		if best == "":
			break
		buy_skill(best)
		n += 1
	return n


# ---------------------------------------------------------------- 保存と放置報酬


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("run", "seed", run_seed)
	cfg.set_value("run", "credits", credits)
	cfg.set_value("run", "total_earned", total_earned)
	cfg.set_value("run", "tools", tool_levels)
	cfg.set_value("run", "planet", planet)
	cfg.set_value("run", "best_planet_run", best_planet_run)
	cfg.set_value("run", "cards", cards)
	cfg.set_value("run", "income_rate", income_rate)
	cfg.set_value("meta", "data", data)
	cfg.set_value("meta", "skills", skills)
	cfg.set_value("meta", "best_planet", best_planet)
	cfg.set_value("meta", "prestiges", prestiges)
	cfg.set_value("meta", "time", Time.get_unix_time_from_system())
	cfg.save(SAVE_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	run_seed = int(cfg.get_value("run", "seed", run_seed))
	credits = float(cfg.get_value("run", "credits", credits))
	total_earned = float(cfg.get_value("run", "total_earned", 0.0))
	var tl: Dictionary = cfg.get_value("run", "tools", {})
	for k in tl:
		tool_levels[k] = int(tl[k])
	planet = int(cfg.get_value("run", "planet", 1))
	best_planet_run = int(cfg.get_value("run", "best_planet_run", planet))
	cards = cfg.get_value("run", "cards", {})
	income_rate = float(cfg.get_value("run", "income_rate", 0.0))
	data = float(cfg.get_value("meta", "data", 0.0))
	skills = cfg.get_value("meta", "skills", {})
	best_planet = int(cfg.get_value("meta", "best_planet", 1))
	prestiges = int(cfg.get_value("meta", "prestiges", 0))
	var t := float(cfg.get_value("meta", "time", 0.0))
	var away := Time.get_unix_time_from_system() - t
	if t > 0.0 and away > 60.0:
		offline_secs = minf(away, (OFFLINE_CAP_H + skill_level("idle")) * 3600.0)
		offline_gain = income_rate * offline_secs * OFFLINE_RATE * pow(1.25, skill_level("idle"))
		if offline_gain > 0.0:
			earn(offline_gain, false)
