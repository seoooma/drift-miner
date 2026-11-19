extends Node
## ゲームの状態（Autoload）。
## 惑星（ラン）：クレジット、ツールのレベル、見つけた遺物、掘った跡。惑星を割ると次の惑星でリセット。
## 永続：素材（鉄・銅・金・結晶）とスキルツリー。素材はブロックを砕くと手に入り、スキルの強化に使う。

signal changed

const SAVE_PATH := "user://drift_miner_v3.cfg"
const CLEAR_RATIO := 0.95
const OFFLINE_RATE := 0.5
const OFFLINE_CAP_H := 2.0

## 採掘ツール。dps は Lv1 の毎秒ダメージ。Lv25 ごとに威力が上がる（基本 ×2）。
## ドローン以外はスキルツリーで解放する。
const TOOLS := [
	{"id": "drone", "name": "採掘ドローン", "desc": "近くの鉱石を自動で狙い、ビームで削る", "dps": 2.0, "cost": 6.0, "growth": 1.11, "color": Color(0.35, 0.9, 1.0)},
	{"id": "cutter", "name": "パルスドリル", "desc": "一番よい鉱脈に降りて、周りごと砕く", "dps": 18.0, "cost": 150.0, "growth": 1.12, "color": Color(1.0, 0.62, 0.25)},
	{"id": "laser", "name": "精密レーザー", "desc": "上空の衛星から価値の高いマスを撃ち抜く", "dps": 140.0, "cost": 4000.0, "growth": 1.13, "color": Color(1.0, 0.3, 0.4)},
	{"id": "bomb", "name": "重力爆雷", "desc": "狙った場所の周りに落ちて広く砕く", "dps": 1100.0, "cost": 1.2e5, "growth": 1.14, "color": Color(0.8, 0.45, 1.0)},
	{"id": "lance", "name": "コアランス", "desc": "狙った場所から中心核へまっすぐ掘り進む", "dps": 9000.0, "cost": 4.0e6, "growth": 1.15, "color": Color(0.45, 1.0, 0.5)},
	{"id": "swarm", "name": "ナノスウォーム", "desc": "小さな機械が狙った場所の近くに散らばって食べる", "dps": 80000.0, "cost": 1.5e8, "growth": 1.16, "color": Color(1.0, 0.9, 0.35)},
]

## 素材（スキルツリーの通貨。惑星を割っても残る）
const MATS := ["iron", "copper", "gold", "crystal"]
const MAT_NAMES := {"iron": "鉄", "copper": "銅", "gold": "金", "crystal": "結晶"}
const MAT_COLORS := {"iron": Color(0.78, 0.82, 0.9), "copper": Color(0.95, 0.55, 0.3), "gold": Color(1.0, 0.85, 0.25), "crystal": Color(0.85, 0.45, 1.0)}

## ブロックの種類。hp と value は岩を1とした倍率。mat は砕くと出る素材。
enum B { ROCK, IRON, COPPER, GOLD, CRYSTAL, CORE, RELIC, CACHE, VOLATILE, HARD }
const BLOCKS := {
	B.ROCK: {"name": "岩", "hp": 1.0, "value": 1.0, "mat": ""},
	B.IRON: {"name": "鉄鉱石", "hp": 1.3, "value": 1.5, "mat": "iron"},
	B.COPPER: {"name": "銅鉱石", "hp": 1.4, "value": 2.0, "mat": "copper"},
	B.GOLD: {"name": "金鉱石", "hp": 1.8, "value": 4.0, "mat": "gold"},
	B.CRYSTAL: {"name": "結晶", "hp": 2.5, "value": 8.0, "mat": "crystal"},
	B.CORE: {"name": "核", "hp": 2.0, "value": 3.0, "mat": ""},
	B.RELIC: {"name": "遺物", "hp": 3.0, "value": 5.0, "mat": ""},
	B.CACHE: {"name": "宝箱", "hp": 1.5, "value": 1.0, "mat": ""},
	B.VOLATILE: {"name": "爆薬岩", "hp": 0.8, "value": 1.0, "mat": ""},
	B.HARD: {"name": "硬い岩", "hp": 6.0, "value": 1.2, "mat": ""},
}
const BLOCK_COLORS := {
	B.IRON: Color(0.72, 0.76, 0.86), B.COPPER: Color(0.92, 0.52, 0.28), B.GOLD: Color(1.0, 0.82, 0.22),
	B.CRYSTAL: Color(0.82, 0.42, 1.0), B.CORE: Color(1.0, 0.42, 0.22), B.VOLATILE: Color(0.75, 0.16, 0.12),
	B.HARD: Color(0.22, 0.22, 0.27),
}

## 惑星の特性（毎回ランダム）。rates はブロックの出やすさの倍率。
const TRAITS := [
	{"id": "plain", "name": "標準惑星", "desc": "特徴のない惑星", "rates": {}},
	{"id": "iron", "name": "鉄の惑星", "desc": "鉄鉱石が2倍", "rates": {B.IRON: 2.0}},
	{"id": "copper", "name": "銅の惑星", "desc": "銅鉱石が2倍", "rates": {B.COPPER: 2.0}},
	{"id": "gold", "name": "黄金の惑星", "desc": "金鉱石が2倍", "rates": {B.GOLD: 2.0}},
	{"id": "crystal", "name": "結晶の惑星", "desc": "結晶が2.5倍", "rates": {B.CRYSTAL: 2.5}},
	{"id": "ruins", "name": "遺跡の惑星", "desc": "遺物と宝箱が多い", "rates": {B.RELIC: 2.5, B.CACHE: 2.0}},
	{"id": "volcanic", "name": "火山惑星", "desc": "爆薬岩が多い。連鎖で一気に崩れる", "rates": {B.VOLATILE: 4.0}},
	{"id": "shell", "name": "硬殻惑星", "desc": "硬い岩が多いが、鉱物も多い", "rates": {B.HARD: 3.0, B.IRON: 1.5, B.COPPER: 1.5, B.GOLD: 1.5}},
]

## 遺物：ブロックの中に眠っていて、砕くとその惑星の間だけ効果が出る（ランダム）
const RELICS := [
	{"id": "power", "name": "古代の動力炉", "desc": "全ツールの威力 ×1.5"},
	{"id": "cr", "name": "黄金の秤", "desc": "獲得クレジット ×1.5"},
	{"id": "drone", "name": "眠れる無人機", "desc": "採掘ドローン +2機"},
	{"id": "tap", "name": "巨人の槌", "desc": "タップの威力 ×4"},
	{"id": "cost", "name": "商人の印章", "desc": "ツールの強化費用 -15%"},
	{"id": "mat", "name": "鉱脈の羅針盤", "desc": "素材の入手量 ×1.3"},
]

## スキルツリー。pos は（列, 段）。parent を Lv1 以上にすると開放。cost は Lv0 のときの素材。
const SKILLS := [
	{"id": "base", "name": "採掘基地", "desc": "すべての始まり", "max": 1, "cost": {}, "growth": 1.0, "parent": "", "pos": Vector2i(2, 0)},
	# 列0：採掘力
	{"id": "drone_pow", "name": "ドローン出力", "desc": "採掘ドローンの威力 +60%", "max": 15, "cost": {"iron": 48}, "growth": 1.45, "parent": "base", "pos": Vector2i(0, 1)},
	{"id": "drone_count", "name": "ドローン増設", "desc": "採掘ドローン +1機", "max": 5, "cost": {"copper": 72}, "growth": 2.2, "parent": "drone_pow", "pos": Vector2i(0, 2)},
	{"id": "tap_pow", "name": "手掘り強化", "desc": "タップの威力 ×2", "max": 8, "cost": {"iron": 72, "copper": 36}, "growth": 1.7, "parent": "drone_count", "pos": Vector2i(0, 3)},
	{"id": "resonance", "name": "共振増幅", "desc": "全ツールの威力 +30%", "max": 20, "cost": {"gold": 48}, "growth": 1.4, "parent": "tap_pow", "pos": Vector2i(0, 4)},
	{"id": "overdrive", "name": "過負荷運転", "desc": "全ツールの威力 ×2", "max": 5, "cost": {"crystal": 60}, "growth": 2.0, "parent": "resonance", "pos": Vector2i(0, 5)},
	# 列1：ツールの解放
	{"id": "cutter", "name": "パルスドリル", "desc": "パルスドリルを解放", "max": 1, "cost": {"iron": 144}, "growth": 1.0, "parent": "base", "pos": Vector2i(1, 1)},
	{"id": "laser", "name": "精密レーザー", "desc": "精密レーザーを解放", "max": 1, "cost": {"iron": 360, "copper": 180}, "growth": 1.0, "parent": "cutter", "pos": Vector2i(1, 2)},
	{"id": "bomb", "name": "重力爆雷", "desc": "重力爆雷を解放", "max": 1, "cost": {"copper": 480, "gold": 120}, "growth": 1.0, "parent": "laser", "pos": Vector2i(1, 3)},
	{"id": "lance", "name": "コアランス", "desc": "コアランスを解放", "max": 1, "cost": {"gold": 480, "crystal": 96}, "growth": 1.0, "parent": "bomb", "pos": Vector2i(1, 4)},
	{"id": "swarm", "name": "ナノスウォーム", "desc": "ナノスウォームを解放", "max": 1, "cost": {"gold": 1440, "crystal": 480}, "growth": 1.0, "parent": "lance", "pos": Vector2i(1, 5)},
	{"id": "mastery", "name": "ツール熟練", "desc": "Lv25ごとの倍率 ×2 → +0.25", "max": 4, "cost": {"crystal": 240}, "growth": 2.0, "parent": "swarm", "pos": Vector2i(1, 6)},
	# 列2：経済
	{"id": "cr_gain", "name": "鑑定術", "desc": "獲得クレジット +35%", "max": 20, "cost": {"iron": 60}, "growth": 1.4, "parent": "base", "pos": Vector2i(2, 1)},
	{"id": "discount", "name": "量産体制", "desc": "ツールの強化費用 -5%", "max": 10, "cost": {"copper": 96}, "growth": 1.55, "parent": "cr_gain", "pos": Vector2i(2, 2)},
	{"id": "start_cr", "name": "初期資金", "desc": "惑星に着いたときのクレジット ×4", "max": 6, "cost": {"gold": 72}, "growth": 2.0, "parent": "discount", "pos": Vector2i(2, 3)},
	{"id": "offline", "name": "放置報酬", "desc": "閉じている間の報酬 +30%・上限 +1時間", "max": 6, "cost": {"gold": 96}, "growth": 1.8, "parent": "start_cr", "pos": Vector2i(2, 4)},
	{"id": "interest", "name": "複利運用", "desc": "10秒ごとに所持クレジットの1%を得る", "max": 3, "cost": {"crystal": 120}, "growth": 2.5, "parent": "offline", "pos": Vector2i(2, 5)},
	# 列3：探査
	{"id": "mat_find", "name": "鉱脈探知", "desc": "素材の入手量 +10%", "max": 15, "cost": {"iron": 72, "copper": 24}, "growth": 1.45, "parent": "base", "pos": Vector2i(3, 1)},
	{"id": "vision", "name": "透視スキャン", "desc": "埋まった遺物と宝箱が光って見える", "max": 1, "cost": {"copper": 240}, "growth": 1.0, "parent": "mat_find", "pos": Vector2i(3, 2)},
	{"id": "relic_luck", "name": "遺物の勘", "desc": "遺物と宝箱が出やすくなる +40%", "max": 5, "cost": {"gold": 120}, "growth": 1.8, "parent": "vision", "pos": Vector2i(3, 3)},
	{"id": "refine", "name": "精錬", "desc": "素材が2倍になる確率 +10%", "max": 5, "cost": {"gold": 144, "crystal": 36}, "growth": 1.8, "parent": "relic_luck", "pos": Vector2i(3, 4)},
	{"id": "core_bonus", "name": "核の回収", "desc": "惑星を割ったとき、集めた素材の +20% を追加で得る", "max": 5, "cost": {"crystal": 144}, "growth": 2.0, "parent": "refine", "pos": Vector2i(3, 5)},
	# 列4：自動化と航路
	{"id": "auto_tap", "name": "自動タップ", "desc": "毎秒1回、自動で手掘りする", "max": 5, "cost": {"iron": 120}, "growth": 1.9, "parent": "base", "pos": Vector2i(4, 1)},
	{"id": "auto_buy", "name": "自動強化", "desc": "一番安いツールを自動で強化", "max": 1, "cost": {"copper": 300, "iron": 300}, "growth": 1.0, "parent": "auto_tap", "pos": Vector2i(4, 2)},
	{"id": "blast", "name": "誘爆制御", "desc": "爆薬岩の爆発の範囲と威力が上がる", "max": 5, "cost": {"gold": 96}, "growth": 1.8, "parent": "auto_buy", "pos": Vector2i(4, 3)},
	{"id": "navigator", "name": "航路選択", "desc": "次の惑星を候補から選べる（Lv2で3択）", "max": 2, "cost": {"crystal": 72}, "growth": 3.0, "parent": "blast", "pos": Vector2i(4, 4)},
]
const BRANCHES := ["採掘力", "ツール", "経済", "探査", "自動化"]

# --- 惑星（ラン） ---
var run_seed: int = 0
var planet: int = 1
var trait_id: String = "plain"
var credits: float = 0.0
var tool_levels := {}
var relics: Array = []
var mats_this_planet := {}
var planet_time: float = 0.0
var saved_hp := PackedFloat32Array()
var income_rate: float = 0.0
var next_traits: Array = []

# --- 永続 ---
var mats := {}
var skills := {}
var best_planet: int = 1
var offline_gain: float = 0.0
var offline_secs: float = 0.0

## main.gd が保存の直前に掘った跡を渡すための関数
var hp_provider: Callable

var _save_t: float = 0.0
var _interest_t: float = 0.0
var _income_acc: float = 0.0
var _income_t: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for m in MATS:
		mats[m] = 0.0
	skills["base"] = 1
	start_planet(1, "plain")
	_load()


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	planet_time += delta
	_income_t += delta
	if _income_t >= 5.0:
		income_rate = lerpf(income_rate, _income_acc / _income_t, 0.5)
		_income_acc = 0.0
		_income_t = 0.0
	if skill_level("interest") > 0:
		_interest_t += delta
		if _interest_t >= 10.0:
			_interest_t = 0.0
			earn(credits * 0.01 * skill_level("interest"), false)
	_save_t += delta
	if _save_t >= 5.0:
		_save_t = 0.0
		save()


# ---------------------------------------------------------------- 数字


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


# ---------------------------------------------------------------- 惑星


func start_planet(p: int, t: String) -> void:
	planet = p
	trait_id = t
	run_seed = randi()
	credits = 20.0 * pow(4.0, skill_level("start_cr")) * pow(planet_mult(), 0.5)
	tool_levels = {}
	for td in TOOLS:
		tool_levels[td["id"]] = 0
	tool_levels["drone"] = 1
	relics = []
	mats_this_planet = {}
	for m in MATS:
		mats_this_planet[m] = 0.0
	planet_time = 0.0
	saved_hp = PackedFloat32Array()
	income_rate = 0.0
	next_traits = []


func trait_def(id: String = "") -> Dictionary:
	var k := trait_id if id == "" else id
	for t in TRAITS:
		if t["id"] == k:
			return t
	return TRAITS[0]


## 惑星ごとの硬さ。1つ進むごとに 60 倍。
func planet_mult() -> float:
	return pow(60.0, planet - 1)


## 深さ（0=表面, 1=中心）ごとの1マスの耐久。深いほど指数的に硬い。
func cell_hp(depth: float) -> float:
	return 2.0 * planet_mult() * pow(10.0, depth * 5.2)


func cell_value(depth: float) -> float:
	# 先の惑星ほど「硬さの割に安い」。スキルで地力を上げないと時間がかかる
	return cell_hp(depth) * 0.55 * cr_mult() / pow(planet_mult(), 0.45)


func cr_mult() -> float:
	return pow(1.35, skill_level("cr_gain")) * pow(1.5, relic_count("cr"))


func earn(amount: float, track: bool = true) -> void:
	credits += amount
	if track:
		_income_acc += amount


func mat_mult() -> float:
	return (1.0 + 0.1 * skill_level("mat_find")) * pow(1.3, relic_count("mat"))


func add_mat(m: String, amount: float) -> float:
	var a := amount * mat_mult()
	if randf() < 0.1 * skill_level("refine"):
		a *= 2.0
	mats[m] = float(mats.get(m, 0.0)) + a
	mats_this_planet[m] = float(mats_this_planet.get(m, 0.0)) + a
	return a


func relic_count(id: String) -> int:
	return relics.count(id)


func add_random_relic() -> Dictionary:
	var r: Dictionary = RELICS[randi() % RELICS.size()]
	relics.append(String(r["id"]))
	changed.emit()
	return r


func relic_luck() -> float:
	return 1.0 + 0.4 * skill_level("relic_luck")


## 惑星を割ったときの処理。追加の素材を返す。
func finish_planet() -> Dictionary:
	var extra := {}
	var k := 0.2 * skill_level("core_bonus")
	for m in MATS:
		var a := float(mats_this_planet.get(m, 0.0)) * k
		if a > 0.0:
			mats[m] = float(mats[m]) + a
			extra[m] = a
	best_planet = maxi(best_planet, planet + 1)
	return extra


## 次の惑星の候補（航路選択スキルで増える）
func roll_next_traits() -> Array:
	var n := 1 + skill_level("navigator")
	var pool := TRAITS.duplicate()
	pool.shuffle()
	next_traits = []
	for i in mini(n, pool.size()):
		next_traits.append(String(pool[i]["id"]))
	return next_traits


# ---------------------------------------------------------------- ツール


func tool_def(id: String) -> Dictionary:
	for t in TOOLS:
		if t["id"] == id:
			return t
	return {}


func tool_unlocked(id: String) -> bool:
	return id == "drone" or skill_level(id) > 0


func tool_level(id: String) -> int:
	return int(tool_levels.get(id, 0))


func dps_mult() -> float:
	return pow(1.3, skill_level("resonance")) * pow(2.0, skill_level("overdrive")) * pow(1.5, relic_count("power"))


func milestone_mult() -> float:
	return 2.0 + 0.25 * skill_level("mastery")


func tool_dps_at(id: String, lv: int) -> float:
	if lv <= 0:
		return 0.0
	var t := tool_def(id)
	var d := float(t["dps"]) * lv * pow(milestone_mult(), lv / 25) * dps_mult()
	if id == "drone":
		d *= 1.0 + 0.6 * skill_level("drone_pow")
	return d


func tool_dps(id: String) -> float:
	return tool_dps_at(id, tool_level(id))


func total_dps() -> float:
	var s := 0.0
	for t in TOOLS:
		s += tool_dps(String(t["id"]))
	return s


func cost_mult() -> float:
	return pow(0.95, skill_level("discount")) * pow(0.85, relic_count("cost"))


func upgrade_cost(id: String, n: int = 1) -> float:
	var t := tool_def(id)
	var g := float(t["growth"])
	var base := float(t["cost"]) * cost_mult() * pow(g, tool_level(id))
	if n == 1:
		return base
	return base * (pow(g, n) - 1.0) / (g - 1.0)


func affordable(id: String, cap: int) -> int:
	var n := 0
	while (cap == 0 or n < cap) and n < 1000:
		if upgrade_cost(id, n + 1) > credits:
			break
		n += 1
	return n


func buy_tool(id: String, n: int = 1) -> bool:
	if n <= 0 or not tool_unlocked(id):
		return false
	var c := upgrade_cost(id, n)
	if c > credits:
		return false
	credits -= c
	tool_levels[id] = tool_level(id) + n
	changed.emit()
	return true


func milestone_frac(id: String) -> float:
	return float(tool_level(id) % 25) / 25.0


func tap_damage() -> float:
	return maxf(3.0, total_dps() * 0.05) * pow(2.0, skill_level("tap_pow")) * pow(4.0, relic_count("tap"))


func drone_count() -> int:
	return 1 + skill_level("drone_count") + 2 * relic_count("drone")


# ---------------------------------------------------------------- スキルツリー


func skill_def(id: String) -> Dictionary:
	for s in SKILLS:
		if s["id"] == id:
			return s
	return {}


func skill_level(id: String) -> int:
	return int(skills.get(id, 0))


func skill_cost(id: String) -> Dictionary:
	var s := skill_def(id)
	var out := {}
	var g := pow(float(s["growth"]), skill_level(id))
	for m in s["cost"]:
		out[m] = ceilf(float(s["cost"][m]) * g)
	return out


func skill_open(id: String) -> bool:
	var p := String(skill_def(id)["parent"])
	return p == "" or skill_level(p) > 0


func skill_maxed(id: String) -> bool:
	return skill_level(id) >= int(skill_def(id)["max"])


func can_afford_mats(cost: Dictionary) -> bool:
	for m in cost:
		if float(mats.get(m, 0.0)) + 0.001 < float(cost[m]):
			return false
	return true


func can_buy_skill(id: String) -> bool:
	return skill_open(id) and not skill_maxed(id) and can_afford_mats(skill_cost(id))


func buy_skill(id: String) -> bool:
	if not can_buy_skill(id):
		return false
	var c := skill_cost(id)
	for m in c:
		mats[m] = float(mats[m]) - float(c[m])
	skills[id] = skill_level(id) + 1
	save()
	changed.emit()
	return true


func cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for m in cost:
		parts.append("%s %s" % [MAT_NAMES[m], fmt(float(cost[m]))])
	return "  ".join(parts)


## 素材の合計が一番少ないスキルから、買えるだけ買う。
func buy_all_skills() -> int:
	var n := 0
	while n < 500:
		var best := ""
		var best_c := INF
		for s in SKILLS:
			var id := String(s["id"])
			if not can_buy_skill(id):
				continue
			var tot := 0.0
			for m in skill_cost(id):
				tot += float(skill_cost(id)[m])
			if tot < best_c:
				best = id
				best_c = tot
		if best == "":
			break
		buy_skill(best)
		n += 1
	return n


# ---------------------------------------------------------------- 保存と放置報酬


func save() -> void:
	if hp_provider.is_valid():
		saved_hp = hp_provider.call()
	var cfg := ConfigFile.new()
	cfg.set_value("run", "seed", run_seed)
	cfg.set_value("run", "planet", planet)
	cfg.set_value("run", "trait", trait_id)
	cfg.set_value("run", "credits", credits)
	cfg.set_value("run", "tools", tool_levels)
	cfg.set_value("run", "relics", relics)
	cfg.set_value("run", "mats_this_planet", mats_this_planet)
	cfg.set_value("run", "time", planet_time)
	cfg.set_value("run", "hp", saved_hp)
	cfg.set_value("run", "income_rate", income_rate)
	cfg.set_value("meta", "mats", mats)
	cfg.set_value("meta", "skills", skills)
	cfg.set_value("meta", "best_planet", best_planet)
	cfg.set_value("meta", "saved_at", Time.get_unix_time_from_system())
	cfg.save(SAVE_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	run_seed = int(cfg.get_value("run", "seed", run_seed))
	planet = int(cfg.get_value("run", "planet", 1))
	trait_id = String(cfg.get_value("run", "trait", "plain"))
	credits = float(cfg.get_value("run", "credits", credits))
	var tl: Dictionary = cfg.get_value("run", "tools", {})
	for k in tl:
		tool_levels[k] = int(tl[k])
	relics = cfg.get_value("run", "relics", [])
	var mtp: Dictionary = cfg.get_value("run", "mats_this_planet", {})
	for k in mtp:
		mats_this_planet[k] = float(mtp[k])
	planet_time = float(cfg.get_value("run", "time", 0.0))
	saved_hp = cfg.get_value("run", "hp", PackedFloat32Array())
	income_rate = float(cfg.get_value("run", "income_rate", 0.0))
	var mm: Dictionary = cfg.get_value("meta", "mats", {})
	for k in mm:
		mats[k] = float(mm[k])
	skills = cfg.get_value("meta", "skills", {"base": 1})
	skills["base"] = 1
	best_planet = int(cfg.get_value("meta", "best_planet", 1))
	var t := float(cfg.get_value("meta", "saved_at", 0.0))
	var away := Time.get_unix_time_from_system() - t
	if t > 0.0 and away > 60.0:
		offline_secs = minf(away, (OFFLINE_CAP_H + skill_level("offline")) * 3600.0)
		offline_gain = income_rate * offline_secs * OFFLINE_RATE * pow(1.3, skill_level("offline"))
		if offline_gain > 0.0:
			earn(offline_gain, false)
