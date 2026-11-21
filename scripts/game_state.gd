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
	{"id": "crystal", "name": "結晶の惑星", "desc": "結晶が3倍", "rates": {B.CRYSTAL: 2.5}},
	{"id": "ruins", "name": "遺跡の惑星", "desc": "遺物と宝箱が多い", "rates": {B.RELIC: 2.5, B.CACHE: 2.0}},
	{"id": "volcanic", "name": "火山惑星", "desc": "爆薬岩が多い。連鎖で一気に崩れる", "rates": {B.VOLATILE: 4.0}},
	{"id": "shell", "name": "硬殻惑星", "desc": "硬い岩が多いが、鉱物も多い", "rates": {B.HARD: 3.0, B.IRON: 1.5, B.COPPER: 1.5, B.GOLD: 1.5}},
]

## 遺物：ブロックの中に眠っていて、掘り当てると3つの候補から1つを選ぶ。効果はその惑星の間だけ。
## 同じ遺物を重ねたときは足し算で効く（2個目で ×1.5 → ×2.0）。
const RELICS := [
	{"id": "power", "name": "古代の動力炉", "desc": "全ツールの威力 +50%"},
	{"id": "cr", "name": "黄金の秤", "desc": "獲得クレジット +50%"},
	{"id": "drone", "name": "眠れる無人機", "desc": "採掘ドローン +1機"},
	{"id": "tap", "name": "精密照準器", "desc": "採掘ドローンの威力 +100%"},
	{"id": "cost", "name": "商人の印章", "desc": "ツールの強化費用 -15%"},
	{"id": "mat", "name": "鉱脈の羅針盤", "desc": "素材の入手量 +30%"},
	{"id": "blast", "name": "爆鳴の欠片", "desc": "爆薬岩の爆発が1マス広く、威力 +100%"},
	{"id": "hard", "name": "硬岩の心臓", "desc": "硬い岩を砕くと、鉄が3つ出る"},
	{"id": "deep", "name": "深層の羅針", "desc": "深さの半分より下のマスへの威力 +100%"},
	{"id": "hoard", "name": "宝の嗅覚", "desc": "宝箱を開けると、30%の確率で遺物も見つかる"},
]
const RELIC_CHOICES := 3
const RELIC_COLOR := Color("#E070D8")  # 遺物はマゼンタ（遺物ボタンと同じ）
const CACHE_COLOR := Color("#F2E05A")  # 宝箱は黄色

## スキルマップ。基地から5つの系統が放射状に広がり、系統のあいだも橋でつながる網の目。
## links のどれか（逆向きも含む）が Lv1 以上なら習得できる。pos はマップ上の座標。
## stat があるのは小さなノード（同じ stat の合計で効く）。cost は Lv0 のときの素材。
const SKILLS := [
	{"id": "base", "name": "母艦", "desc": "すべての始まり。機体はこの船から出て働く", "max": 1, "cost": {}, "growth": 1.0, "links": [], "pos": Vector2(0, 0), "branch": "", "stat": "", "amt": 0.0},
	{"id": "a1", "name": "出力強化", "desc": "全ツールの威力 +15%", "max": 3, "cost": {"iron": 30}, "growth": 1.6, "links": ["base"], "pos": Vector2(0, -118), "branch": "A", "stat": "pow", "amt": 0.15},
	{"id": "drone_pow", "name": "ドローン出力", "desc": "採掘ドローンの威力 +60%", "max": 15, "cost": {"iron": 48}, "growth": 1.45, "links": ["a1"], "pos": Vector2(0, -236), "branch": "A", "stat": "", "amt": 0.0},
	{"id": "drone_count", "name": "ドローン増設", "desc": "採掘ドローン +1機（1機ごとに同じ威力で掘る）", "max": 5, "cost": {"copper": 72}, "growth": 2.2, "links": ["drone_pow"], "pos": Vector2(-68, -347), "branch": "A", "stat": "", "amt": 0.0},
	{"id": "a2", "name": "ドローン調整", "desc": "採掘ドローンの威力 +25%", "max": 3, "cost": {"copper": 60}, "growth": 1.6, "links": ["drone_pow"], "pos": Vector2(68, -347), "branch": "A", "stat": "dpow", "amt": 0.25},
	{"id": "a3", "name": "ドローン調整", "desc": "採掘ドローンの威力 +25%", "max": 3, "cost": {"gold": 36}, "growth": 1.6, "links": ["drone_count"], "pos": Vector2(-106, -460), "branch": "A", "stat": "dpow", "amt": 0.25},
	{"id": "resonance", "name": "共振増幅", "desc": "全ツールの威力 ×1.45", "max": 20, "cost": {"gold": 48}, "growth": 1.4, "links": ["a2"], "pos": Vector2(74, -466), "branch": "A", "stat": "", "amt": 0.0},
	{"id": "thrust", "name": "推進器", "desc": "機体の移動速度 +40%", "max": 3, "cost": {"iron": 120, "copper": 60}, "growth": 1.9, "links": ["a3"], "pos": Vector2(-113, -579), "branch": "A", "stat": "", "amt": 0.0},
	{"id": "a4", "name": "出力強化", "desc": "全ツールの威力 +15%", "max": 3, "cost": {"crystal": 30}, "growth": 1.6, "links": ["resonance"], "pos": Vector2(82, -584), "branch": "A", "stat": "pow", "amt": 0.15},
	{"id": "overdrive", "name": "過負荷運転", "desc": "全ツールの威力 ×2.5", "max": 5, "cost": {"crystal": 60}, "growth": 2.0, "links": ["thrust", "a4"], "pos": Vector2(-12, -708), "branch": "A", "stat": "", "amt": 0.0},
	{"id": "cutter", "name": "パルスドリル", "desc": "パルスドリルを解放", "max": 1, "cost": {"iron": 144}, "growth": 1.0, "links": ["base"], "pos": Vector2(112, -36), "branch": "B", "stat": "", "amt": 0.0},
	{"id": "b1", "name": "部品の規格化", "desc": "ツールの強化費用 -4%", "max": 3, "cost": {"iron": 60}, "growth": 1.6, "links": ["cutter"], "pos": Vector2(224, -73), "branch": "B", "stat": "cost", "amt": 0.04},
	{"id": "laser", "name": "精密レーザー", "desc": "精密レーザーを解放", "max": 1, "cost": {"iron": 360, "copper": 180}, "growth": 1.0, "links": ["b1"], "pos": Vector2(337, -109), "branch": "B", "stat": "", "amt": 0.0},
	{"id": "bomb", "name": "重力爆雷", "desc": "重力爆雷を解放", "max": 1, "cost": {"copper": 480, "gold": 120}, "growth": 1.0, "links": ["laser"], "pos": Vector2(424, -207), "branch": "B", "stat": "", "amt": 0.0},
	{"id": "b2", "name": "出力強化", "desc": "全ツールの威力 +15%", "max": 3, "cost": {"gold": 36}, "growth": 1.6, "links": ["laser"], "pos": Vector2(466, -74), "branch": "B", "stat": "pow", "amt": 0.15},
	{"id": "lance", "name": "コアランス", "desc": "コアランスを解放", "max": 1, "cost": {"gold": 480, "crystal": 96}, "growth": 1.0, "links": ["bomb"], "pos": Vector2(539, -240), "branch": "B", "stat": "", "amt": 0.0},
	{"id": "b3", "name": "部品の規格化", "desc": "ツールの強化費用 -4%", "max": 3, "cost": {"crystal": 30}, "growth": 1.6, "links": ["b2"], "pos": Vector2(581, -102), "branch": "B", "stat": "cost", "amt": 0.04},
	{"id": "swarm", "name": "ナノスウォーム", "desc": "ナノスウォームを解放", "max": 1, "cost": {"gold": 1440, "crystal": 480}, "growth": 1.0, "links": ["lance", "b3"], "pos": Vector2(673, -219), "branch": "B", "stat": "", "amt": 0.0},
	{"id": "mastery", "name": "ツール熟練", "desc": "Lv25ごとの倍率 ×2 → +0.25", "max": 4, "cost": {"crystal": 240}, "growth": 2.0, "links": ["swarm"], "pos": Vector2(786, -255), "branch": "B", "stat": "", "amt": 0.0},
	{"id": "cr_gain", "name": "鑑定術", "desc": "獲得クレジット +35%", "max": 20, "cost": {"iron": 60}, "growth": 1.4, "links": ["base"], "pos": Vector2(69, 95), "branch": "C", "stat": "", "amt": 0.0},
	{"id": "discount", "name": "量産体制", "desc": "ツールの強化費用 -5%", "max": 10, "cost": {"copper": 96}, "growth": 1.55, "links": ["cr_gain"], "pos": Vector2(167, 167), "branch": "C", "stat": "", "amt": 0.0},
	{"id": "c1", "name": "相場観", "desc": "獲得クレジット +10%", "max": 3, "cost": {"iron": 60}, "growth": 1.6, "links": ["cr_gain"], "pos": Vector2(107, 210), "branch": "C", "stat": "cr", "amt": 0.1},
	{"id": "start_cr", "name": "初期資金", "desc": "惑星に着いたときのクレジット ×4", "max": 6, "cost": {"gold": 72}, "growth": 2.0, "links": ["discount"], "pos": Vector2(250, 250), "branch": "C", "stat": "", "amt": 0.0},
	{"id": "c2", "name": "相場観", "desc": "獲得クレジット +10%", "max": 3, "cost": {"copper": 60}, "growth": 1.6, "links": ["c1"], "pos": Vector2(161, 315), "branch": "C", "stat": "cr", "amt": 0.1},
	{"id": "offline", "name": "放置報酬", "desc": "閉じている間の報酬 +30%・上限 +1時間", "max": 6, "cost": {"gold": 96}, "growth": 1.8, "links": ["start_cr", "c2"], "pos": Vector2(277, 382), "branch": "C", "stat": "", "amt": 0.0},
	{"id": "c3", "name": "部品の規格化", "desc": "ツールの強化費用 -4%", "max": 3, "cost": {"crystal": 30}, "growth": 1.6, "links": ["offline"], "pos": Vector2(410, 424), "branch": "C", "stat": "cost", "amt": 0.04},
	{"id": "interest", "name": "複利運用", "desc": "10秒ごとに所持クレジットの1%を得る", "max": 3, "cost": {"crystal": 120}, "growth": 2.5, "links": ["offline"], "pos": Vector2(277, 521), "branch": "C", "stat": "", "amt": 0.0},
	{"id": "mat_find", "name": "鉱脈探知", "desc": "素材の入手量 +10%", "max": 15, "cost": {"iron": 72, "copper": 24}, "growth": 1.45, "links": ["base"], "pos": Vector2(-69, 95), "branch": "D", "stat": "", "amt": 0.0},
	{"id": "d1", "name": "選鉱", "desc": "素材の入手量 +5%", "max": 3, "cost": {"iron": 60}, "growth": 1.6, "links": ["mat_find"], "pos": Vector2(-139, 191), "branch": "D", "stat": "mat", "amt": 0.05},
	{"id": "vision", "name": "透視スキャン", "desc": "埋まった遺物と宝箱が光って見える", "max": 1, "cost": {"copper": 240}, "growth": 1.0, "links": ["d1"], "pos": Vector2(-161, 315), "branch": "D", "stat": "", "amt": 0.0},
	{"id": "d2", "name": "選鉱", "desc": "素材の入手量 +5%", "max": 3, "cost": {"copper": 60}, "growth": 1.6, "links": ["d1"], "pos": Vector2(-250, 250), "branch": "D", "stat": "mat", "amt": 0.05},
	{"id": "relic_luck", "name": "遺物の勘", "desc": "遺物と宝箱が出やすくなる +40%", "max": 5, "cost": {"gold": 120}, "growth": 1.8, "links": ["vision"], "pos": Vector2(-214, 421), "branch": "D", "stat": "", "amt": 0.0},
	{"id": "refine", "name": "精錬", "desc": "素材が2倍になる確率 +10%", "max": 5, "cost": {"gold": 144, "crystal": 36}, "growth": 1.8, "links": ["d2"], "pos": Vector2(-334, 334), "branch": "D", "stat": "", "amt": 0.0},
	{"id": "core_bonus", "name": "核の回収", "desc": "惑星を割ったとき、集めた素材の +20% を追加で得る", "max": 5, "cost": {"crystal": 144}, "growth": 2.0, "links": ["relic_luck", "refine"], "pos": Vector2(-347, 477), "branch": "D", "stat": "", "amt": 0.0},
	{"id": "auto_scan", "name": "自動探索", "desc": "周りに鉱石がないとき、遠くの鉱脈を探して移動する（探索範囲 +8マス）", "max": 5, "cost": {"iron": 120}, "growth": 1.9, "links": ["base"], "pos": Vector2(-112, -36), "branch": "E", "stat": "", "amt": 0.0},
	{"id": "auto_buy", "name": "自動強化・高速", "desc": "自動強化が、買えるだけまとめて素早く買うようになる", "max": 1, "cost": {"copper": 300, "iron": 300}, "growth": 1.0, "links": ["auto_scan"], "pos": Vector2(-224, -73), "branch": "E", "stat": "", "amt": 0.0},
	{"id": "e1", "name": "姿勢制御", "desc": "機体の移動速度 +25%", "max": 3, "cost": {"copper": 60}, "growth": 1.6, "links": ["auto_buy"], "pos": Vector2(-350, -55), "branch": "E", "stat": "move", "amt": 0.25},
	{"id": "blast", "name": "誘爆制御", "desc": "爆薬岩の爆発の範囲と威力が上がる", "max": 5, "cost": {"gold": 96}, "growth": 1.8, "links": ["auto_buy"], "pos": Vector2(-315, -161), "branch": "E", "stat": "", "amt": 0.0},
	{"id": "e2", "name": "出力強化", "desc": "全ツールの威力 +15%", "max": 3, "cost": {"gold": 36}, "growth": 1.6, "links": ["e1", "blast"], "pos": Vector2(-449, -146), "branch": "E", "stat": "pow", "amt": 0.15},
	{"id": "navigator", "name": "航路選択", "desc": "次の惑星を候補から選べる（Lv2で3択）", "max": 2, "cost": {"crystal": 72}, "growth": 3.0, "links": ["e2"], "pos": Vector2(-561, -182), "branch": "E", "stat": "", "amt": 0.0},
	{"id": "x_ab", "name": "出力強化", "desc": "全ツールの威力 +15%", "max": 3, "cost": {"gold": 36}, "growth": 1.6, "links": ["a2", "laser"], "pos": Vector2(229, -315), "branch": "X", "stat": "pow", "amt": 0.15},
	{"id": "x_bc", "name": "部品の規格化", "desc": "ツールの強化費用 -4%", "max": 3, "cost": {"gold": 36}, "growth": 1.6, "links": ["laser", "c2"], "pos": Vector2(370, 120), "branch": "X", "stat": "cost", "amt": 0.04},
	{"id": "x_cd", "name": "相場観", "desc": "獲得クレジット +10%", "max": 3, "cost": {"gold": 36}, "growth": 1.6, "links": ["start_cr", "vision"], "pos": Vector2(0, 389), "branch": "X", "stat": "cr", "amt": 0.1},
	{"id": "x_de", "name": "選鉱", "desc": "素材の入手量 +5%", "max": 3, "cost": {"gold": 36}, "growth": 1.6, "links": ["vision", "e1"], "pos": Vector2(-370, 120), "branch": "X", "stat": "mat", "amt": 0.05},
	{"id": "x_ea", "name": "姿勢制御", "desc": "機体の移動速度 +25%", "max": 3, "cost": {"gold": 36}, "growth": 1.6, "links": ["e1", "drone_count"], "pos": Vector2(-229, -315), "branch": "X", "stat": "move", "amt": 0.25},
	{"id": "y_ab", "name": "出力強化", "desc": "全ツールの威力 +15%", "max": 3, "cost": {"crystal": 30}, "growth": 1.6, "links": ["a4", "b3"], "pos": Vector2(388, -535), "branch": "X", "stat": "pow", "amt": 0.15},
	{"id": "y_cd", "name": "選鉱", "desc": "素材の入手量 +5%", "max": 3, "cost": {"crystal": 30}, "growth": 1.6, "links": ["interest", "core_bonus"], "pos": Vector2(0, 661), "branch": "X", "stat": "mat", "amt": 0.05},
	# 要石：各系統の端にある、代償つきの大きなノード。同時に付けられるのは1つだけ（外すと素材は全額戻る）
	{"id": "k_drone", "name": "共鳴群", "desc": "採掘ドローン1機ごとの威力 ×機数。ほかのツールの威力 ×0.5", "max": 1, "cost": {"gold": 600, "crystal": 240}, "growth": 1.0, "links": ["overdrive"], "pos": Vector2(-12, -850), "branch": "A", "stat": "", "amt": 0.0, "key": true},
	{"id": "k_heavy", "name": "重機運用", "desc": "ドローン以外のツールの威力 ×5。採掘ドローンの威力 ×0.2", "max": 1, "cost": {"gold": 600, "crystal": 240}, "growth": 1.0, "links": ["mastery"], "pos": Vector2(910, -300), "branch": "B", "stat": "", "amt": 0.0, "key": true},
	{"id": "k_loan", "name": "先行投資", "desc": "惑星に着いたときのクレジット ×50。獲得クレジット ×0.6", "max": 1, "cost": {"gold": 600, "crystal": 240}, "growth": 1.0, "links": ["interest", "y_cd"], "pos": Vector2(300, 680), "branch": "C", "stat": "", "amt": 0.0, "key": true},
	{"id": "k_relic", "name": "遺物狩り", "desc": "遺物と宝箱が3倍出る（次に作られる惑星から）。素材の入手量 ×0.7", "max": 1, "cost": {"gold": 600, "crystal": 240}, "growth": 1.0, "links": ["core_bonus"], "pos": Vector2(-470, 630), "branch": "D", "stat": "", "amt": 0.0, "key": true},
	{"id": "k_drift", "name": "無人航行", "desc": "タップで移動先を決められなくなる。自動探索の範囲 ×2・機体の移動速度 ×2", "max": 1, "cost": {"gold": 600, "crystal": 240}, "growth": 1.0, "links": ["navigator"], "pos": Vector2(-700, -228), "branch": "E", "stat": "", "amt": 0.0, "key": true},

]
## スキルの段階。マップの中心からの距離で内・中・外に分かれ、最高到達の惑星で解放される。
const TIER_R := [380.0, 620.0]
const TIER_PLANET := [1, 3, 5]

## 系統の名前と色（マップの見出し）
const BRANCHES := {
	"A": {"name": "採掘力", "color": Color(0.35, 0.9, 1.0), "angle": -90.0},
	"B": {"name": "ツール", "color": Color(1.0, 0.55, 0.3), "angle": -18.0},
	"C": {"name": "経済", "color": Color(1.0, 0.85, 0.3), "angle": 54.0},
	"D": {"name": "探査", "color": Color(0.8, 0.5, 1.0), "angle": 126.0},
	"E": {"name": "自動化", "color": Color(0.45, 1.0, 0.55), "angle": 198.0},
}

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
var compare_time: float = 0.0  # 惑星クリアの画面で比べる、前の惑星の所要時間

# --- 永続 ---
var mats := {}
var skills := {}
var best_planet: int = 1
var offline_gain: float = 0.0
var offline_secs: float = 0.0
var prev_time: float = 0.0  # 前に割った惑星の所要時間（秒）
var respec_ready: bool = false  # 惑星を割るたびに1回、スキルを全額返却で振り直せる
var pending_clear: bool = false  # 惑星を割って、次の惑星を選ぶ画面のまま（閉じても続きから）
var clear_extra := {}  # その画面に出す、核の回収ボーナス
var auto_on: bool = false  # 自動強化の入り切り（最初から使える。スキルで速くなる）
var tips := {}  # 最初の案内で済んだもの（buy・skill・tap）

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
	credits = 20.0 * pow(4.0, skill_level("start_cr")) * pow(planet_mult(), 0.5) * (50.0 if has_key("k_loan") else 1.0)
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
	pending_clear = false
	clear_extra = {}


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
	return pow(1.35, skill_level("cr_gain")) * (1.0 + stat("cr")) * (1.0 + 0.5 * relic_count("cr")) * (0.6 if has_key("k_loan") else 1.0)


func earn(amount: float, track: bool = true) -> void:
	credits += amount
	if track:
		_income_acc += amount


func mat_mult() -> float:
	return (1.0 + 0.1 * skill_level("mat_find") + stat("mat")) * (1.0 + 0.3 * relic_count("mat")) * (0.7 if has_key("k_relic") else 1.0)


func add_mat(m: String, amount: float) -> float:
	var a := amount * mat_mult()
	if randf() < 0.1 * skill_level("refine"):
		a *= 2.0
	mats[m] = float(mats.get(m, 0.0)) + a
	mats_this_planet[m] = float(mats_this_planet.get(m, 0.0)) + a
	return a


func relic_count(id: String) -> int:
	return relics.count(id)


func relic_def(id: String) -> Dictionary:
	for r in RELICS:
		if r["id"] == id:
			return r
	return RELICS[0]


## 掘り当てた遺物の候補（重ならない3つ）
func roll_relic_choices() -> Array:
	var pool: Array = []
	for r in RELICS:
		pool.append(String(r["id"]))
	pool.shuffle()
	return pool.slice(0, RELIC_CHOICES)


func add_relic(id: String) -> Dictionary:
	relics.append(id)
	changed.emit()
	return relic_def(id)


func relic_luck() -> float:
	return (1.0 + 0.4 * skill_level("relic_luck")) * (3.0 if has_key("k_relic") else 1.0)


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
	compare_time = prev_time
	prev_time = planet_time
	respec_ready = true
	pending_clear = true
	clear_extra = extra
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
	return pow(1.45, skill_level("resonance")) * (1.0 + stat("pow")) * pow(2.5, skill_level("overdrive")) * (1.0 + 0.5 * relic_count("power"))


func milestone_mult() -> float:
	return 2.0 + 0.25 * skill_level("mastery")


func tool_dps_at(id: String, lv: int) -> float:
	if lv <= 0:
		return 0.0
	var t := tool_def(id)
	var d := float(t["dps"]) * lv * pow(milestone_mult(), lv / 25) * dps_mult()
	if id == "drone":
		d *= (1.0 + 0.6 * skill_level("drone_pow") + stat("dpow")) * (1.0 + 1.0 * relic_count("tap"))
		# 表示も計算も、ドローン全体の威力（1機ごとの威力 × 機数）
		d *= drone_count()
		if has_key("k_drone"):
			d *= drone_count()
		if has_key("k_heavy"):
			d *= 0.2
	else:
		if has_key("k_drone"):
			d *= 0.5
		if has_key("k_heavy"):
			d *= 5.0
	return d


func tool_dps(id: String) -> float:
	if not tool_unlocked(id):
		return 0.0
	return tool_dps_at(id, tool_level(id))


func total_dps() -> float:
	var s := 0.0
	for t in TOOLS:
		s += tool_dps(String(t["id"]))
	return s


func cost_mult() -> float:
	return pow(0.95, skill_level("discount")) * maxf(0.3, 1.0 - stat("cost")) * pow(0.85, relic_count("cost"))


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


## 機体の移動速度の倍率
func move_mult() -> float:
	return (1.0 + 0.4 * skill_level("thrust") + stat("move")) * (2.0 if has_key("k_drift") else 1.0)


## 自動探索で鉄・銅などの鉱脈を探しに行く範囲（マス）
func scan_radius() -> int:
	return (16 + 8 * skill_level("auto_scan")) * (2 if has_key("k_drift") else 1)


func drone_count() -> int:
	return 1 + skill_level("drone_count") + relic_count("drone")


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


## 小さなノードの効果の合計（stat ごと）
func stat(name: String) -> float:
	var t := 0.0
	for sk in SKILLS:
		if sk["stat"] == name:
			t += float(sk["amt"]) * skill_level(String(sk["id"]))
	return t


var _adj := {}


## つながっているノード（links の逆向きも含む）
func skill_links(id: String) -> Array:
	if _adj.is_empty():
		for sk in SKILLS:
			_adj[String(sk["id"])] = []
		for sk in SKILLS:
			for l in sk["links"]:
				(_adj[String(sk["id"])] as Array).append(String(l))
				(_adj[String(l)] as Array).append(String(sk["id"]))
	return _adj.get(id, [])


func skill_open(id: String) -> bool:
	if id == "base":
		return true
	for l in skill_links(id):
		if skill_level(String(l)) > 0:
			return true
	return false


func skill_maxed(id: String) -> bool:
	return skill_level(id) >= int(skill_def(id)["max"])


func can_afford_mats(cost: Dictionary) -> bool:
	for m in cost:
		if float(mats.get(m, 0.0)) + 0.001 < float(cost[m]):
			return false
	return true


func is_key(id: String) -> bool:
	return bool(skill_def(id).get("key", false))


func has_key(id: String) -> bool:
	return skill_level(id) > 0


## いま付けている要石（なければ ""）
func active_key() -> String:
	for s in SKILLS:
		if bool(s.get("key", false)) and skill_level(String(s["id"])) > 0:
			return String(s["id"])
	return ""


## スキルの段階（0=内, 1=中, 2=外）。要石はいつも外。
func skill_tier(id: String) -> int:
	if is_key(id):
		return 2
	var r := (skill_def(id)["pos"] as Vector2).length()
	if r < TIER_R[0]:
		return 0
	return 1 if r < TIER_R[1] else 2


func tier_planet(id: String) -> int:
	return TIER_PLANET[skill_tier(id)]


func tier_ok(id: String) -> bool:
	return best_planet >= tier_planet(id)


func can_buy_skill(id: String) -> bool:
	if is_key(id) and active_key() != "":
		return false
	return skill_open(id) and tier_ok(id) and not skill_maxed(id) and can_afford_mats(skill_cost(id))


## Lv0 から今のレベルまでに使った素材の合計
func skill_spent(id: String) -> Dictionary:
	var s := skill_def(id)
	var out := {}
	for k in skill_level(id):
		var g := pow(float(s["growth"]), k)
		for m in s["cost"]:
			out[m] = float(out.get(m, 0.0)) + ceilf(float(s["cost"][m]) * g)
	return out


func _refund(id: String) -> void:
	var back := skill_spent(id)
	for m in back:
		mats[m] = float(mats.get(m, 0.0)) + float(back[m])
	skills[id] = 0


## 要石を外す。素材は全額戻る。
func remove_key(id: String) -> bool:
	if not is_key(id) or skill_level(id) <= 0:
		return false
	_refund(id)
	save()
	changed.emit()
	return true


## スキルを全部外して素材を全額戻す（惑星を割るたびに1回）
func respec() -> bool:
	if not respec_ready:
		return false
	for s in SKILLS:
		var id := String(s["id"])
		if id != "base" and skill_level(id) > 0:
			_refund(id)
	respec_ready = false
	save()
	changed.emit()
	return true


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


func tip_done(id: String) -> bool:
	return bool(tips.get(id, false))


func mark_tip(id: String) -> void:
	if not tip_done(id):
		tips[id] = true
		changed.emit()


func cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for m in cost:
		parts.append("%s %s" % [MAT_NAMES[m], fmt(float(cost[m]))])
	return "  ".join(parts)


## 素材の合計が一番少ないスキルから、買えるだけ買う（小さなノードは後回し）。
func buy_all_skills() -> int:
	var n := 0
	while n < 500:
		var best := ""
		var best_c := INF
		for s in SKILLS:
			var id := String(s["id"])
			if is_key(id) or not can_buy_skill(id):
				continue
			var tot := 0.0
			for m in skill_cost(id):
				tot += float(skill_cost(id)[m])
			if String(s["stat"]) != "":
				tot *= 3.0  # 小さなノードより、大きなノードを先に
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
	cfg.set_value("run", "pending_clear", pending_clear)
	cfg.set_value("run", "clear_extra", clear_extra)
	cfg.set_value("run", "next_traits", next_traits)
	cfg.set_value("meta", "auto_on", auto_on)
	cfg.set_value("meta", "tips", tips)
	cfg.set_value("meta", "prev_time", prev_time)
	cfg.set_value("meta", "respec_ready", respec_ready)
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
	pending_clear = bool(cfg.get_value("run", "pending_clear", false))
	clear_extra = cfg.get_value("run", "clear_extra", {})
	next_traits = cfg.get_value("run", "next_traits", [])
	auto_on = bool(cfg.get_value("meta", "auto_on", false))
	tips = cfg.get_value("meta", "tips", {})
	if not cfg.has_section_key("meta", "tips") and int(cfg.get_value("meta", "best_planet", 1)) > 1:
		tips = {"buy": true, "skill": true, "tap": true}  # 前から遊んでいる人には最初の案内を出さない
	prev_time = float(cfg.get_value("meta", "prev_time", 0.0))
	respec_ready = bool(cfg.get_value("meta", "respec_ready", false))
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
		if offline_gain > 0.0 and not pending_clear:
			earn(offline_gain, false)
		else:
			offline_gain = 0.0
