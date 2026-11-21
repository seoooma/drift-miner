extends Node
## ゲームの状態（Autoload）。
## 惑星（ラン）：クレジット、ツールのレベル、見つけた遺物、掘った跡。惑星を割ると次の惑星でリセット。
## 永続：素材（鉄・銅・金・結晶）とスキルツリー。素材はブロックを砕くと手に入り、スキルの強化に使う。

signal changed

const SAVE_PATH := "user://drift_miner_v3.cfg"
const CLEAR_RATIO := 0.95
const OFFLINE_CAP_H := 10.0
const OFFLINE_RATE := 0.6
## 星系：10惑星で1つ。惑星10を割ると次の星系が開き、星核（恒久通貨）が手に入る。
const GALAXY_SIZE := 10
## 惑星の硬さは「基本の曲線」を、今の力で割ったときの見込み時間が MIN_T〜MAX_T 秒に収まるよう寄せる。
const MIN_T := 14.0 * 60.0
const MAX_T := 30.0 * 60.0
const PLANET_G := 25.0  # 基本の曲線で、星系の中の惑星が1つ進むごとの硬さ
const GALAXY_HP := 2.0  # 星系が1つ進むごとの硬さ
const GALAXY_CR := 0.25  # 星系が1つ進むごとの獲得クレジット（+25%）
const EST_EFF := 0.3  # 見込みの計算で、表示の威力のうち実際に岩に入る割合
const EST_CAP := 6.0 * 3600.0
## 見込みと実際の時間のずれ（実際 ÷ 見込み）。割るたびに実際の時間で直していく。
## 遊び方（スキルの買い方・遺物・タップ）で速さが変わるので、その人に合わせる。
const EST_BIAS0 := 0.15
## 星核で買う、上限のない強化
const CORE_UPS := [
	{"id": "pow", "name": "核の出力", "desc": "全ツールの威力 +20%", "cost": 1.0, "growth": 1.35},
	{"id": "mat", "name": "核の選鉱", "desc": "素材の入手量 +15%", "cost": 1.0, "growth": 1.35},
	{"id": "cr", "name": "核の相場", "desc": "獲得クレジット +25%", "cost": 1.0, "growth": 1.35},
]

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

## 属性：攻撃ごとに属性があり、ブロックとの相性で削る速さが変わる（強い ×2、弱い ×0.5）。
## 岩・核の外側の大半はどの属性でも等倍なので、全体のペースは大きくは変わらない。
const ELEMS := ["heat", "shock", "volt"]
const ELEM_NAMES := {"": "無", "heat": "熱", "shock": "衝撃", "volt": "電磁"}
const ELEM_COLORS := {"": Color("#E8ECEF"), "heat": Color("#F2A23A"), "shock": Color("#4FD8E8"), "volt": Color("#F2E05A")}
const ELEM_STRONG := 2.0
const ELEM_WEAK := 0.5
const AFFINITY := {
	"heat": {B.IRON: ELEM_STRONG, B.COPPER: ELEM_STRONG, B.VOLATILE: ELEM_STRONG, B.HARD: ELEM_WEAK},
	"shock": {B.HARD: ELEM_STRONG, B.CRYSTAL: ELEM_STRONG, B.GOLD: ELEM_WEAK},
	"volt": {B.GOLD: ELEM_STRONG, B.CORE: ELEM_STRONG, B.CRYSTAL: ELEM_WEAK},
}
const ELEM_DESC := {
	"": "どのブロックにも等倍",
	"heat": "鉄・銅・爆薬岩に強い／硬い岩に弱い",
	"shock": "硬い岩・結晶に強い／金に弱い",
	"volt": "金・核に強い／結晶に弱い",
}
## ツールのもともとの属性（武器パーツで変えられる）
const TOOL_ELEM := {"drone": "", "cutter": "shock", "laser": "heat", "bomb": "shock", "lance": "volt", "swarm": "heat"}

## パーツ（ローグライク要素）：宝箱や硬い岩から、ランダムな効果つきのパーツが3択で出る。
## 枠は各ツールの武器パーツ1つずつと、母艦の「反応炉」「機体フレーム」。同じ枠に付けると入れ替わる。
## 付けたパーツは星系の間ずっと残り、星系を制覇したときや周回で外れる。
const PART_SLOTS := ["drone", "cutter", "laser", "bomb", "lance", "swarm", "reactor", "frame"]
const SLOT_NAMES := {"reactor": "反応炉", "frame": "機体フレーム"}
const PART_BASE := {
	"drone": ["照準モジュール", "ビーム発振器"], "cutter": ["ドリルビット", "衝角"], "laser": ["集光レンズ", "照射炉"],
	"bomb": ["炸薬コア", "重力殻"], "lance": ["穿孔ヘッド", "加速管"], "swarm": ["群体AI", "分解酵素"],
	"reactor": ["反応炉", "出力変換器"], "frame": ["機体フレーム", "貨物区画"],
}
const ELEM_PREFIX := {"": "", "heat": "灼熱の", "shock": "重撃の", "volt": "電磁の"}
const RARITY_NAMES := ["ふつう", "レア", "エピック"]
const RARITY_COLORS := [Color("#E8ECEF"), Color("#4FD8E8"), Color("#E070D8")]
const RARITY_W := [70.0, 25.0, 5.0]  # 出る重み
const RARITY_MODS := [1, 2, 3]  # 効果の数
const RARITY_K := [1.0, 1.4, 2.0]  # 効果の強さ
## 効果。base は「ふつう」のときの中央値（±40%でぶれる）
const PART_MODS := {
	"pow": {"text": "威力 +%d%%", "base": 0.35, "weapon": true},
	"strong": {"text": "弱点を突いたとき +%d%%", "base": 0.5, "weapon": true},
	"ore": {"text": "鉱石への威力 +%d%%", "base": 0.6, "weapon": true},
	"deep": {"text": "深い所への威力 +%d%%", "base": 0.5, "weapon": true},
	"all": {"text": "全ツールの威力 +%d%%", "base": 0.2, "weapon": false},
	"heat": {"text": "熱属性の威力 +%d%%", "base": 0.35, "weapon": false},
	"shock": {"text": "衝撃属性の威力 +%d%%", "base": 0.35, "weapon": false},
	"volt": {"text": "電磁属性の威力 +%d%%", "base": 0.35, "weapon": false},
	"cr": {"text": "獲得クレジット +%d%%", "base": 0.25, "weapon": false},
	"mat": {"text": "素材の入手量 +%d%%", "base": 0.15, "weapon": false},
	"cost": {"text": "強化費用 -%d%%", "base": 0.06, "weapon": false},
	"move": {"text": "移動速度 +%d%%", "base": 0.3, "weapon": false},
}
const REACTOR_MODS := ["all", "heat", "shock", "volt"]
const FRAME_MODS := ["cr", "mat", "cost", "move"]
const PART_CHANCE_CACHE := 0.35  # 宝箱からパーツが出る確率
const PART_CHANCE_HARD := 0.006  # 硬い岩からパーツが出る確率
const PART_COLOR := Color("#9BE86A")  # パーツの札と画面の差し色

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
	{"id": "offline", "name": "放置報酬", "desc": "閉じている間に掘る速さ +30%・上限 +1時間", "max": 6, "cost": {"gold": 96}, "growth": 1.8, "links": ["start_cr", "c2"], "pos": Vector2(277, 382), "branch": "C", "stat": "", "amt": 0.0},
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
var pm: float = 1.0
var est_bias: float = EST_BIAS0
var est_start: float = 0.0  # この惑星に着いたときの見込み（秒、ずれの補正前）
var offline_used: bool = false  # この惑星で閉じていた間の採掘があった（ずれの補正に使わない）  # この惑星の硬さの倍率（惑星に着いたときに決めて保存する）
var compare_time: float = 0.0  # 惑星クリアの画面で比べる、前の惑星の所要時間
var parts := {}  # 枠 → パーツ（星系の間残る）

# --- 永続 ---
var mats := {}
var skills := {}
var best_planet: int = 1
var cores: float = 0.0  # 星核（星系を割ると手に入る）
var core_lv := {}  # 星核の強化のレベル
var offline_secs: float = 0.0
var prev_time: float = 0.0  # 前に割った惑星の所要時間（秒）
var respec_ready: bool = false  # 惑星を割るたびに1回、スキルを全額返却で振り直せる
var pending_clear: bool = false  # 惑星を割って、次の惑星を選ぶ画面のまま（閉じても続きから）
var clear_extra := {}  # その画面に出す、核の回収ボーナス
var auto_on: bool = false  # 自動強化の入り切り（最初から使える。スキルで速くなる）
var tips := {}  # 最初の案内で済んだもの（buy・skill・tap）

## main.gd が保存の直前に掘った跡を渡すための関数
var hp_provider: Callable
var rate_provider: Callable  # main.gd が保存の直前に、実際に岩に入っている毎秒のダメージを渡す
var damage_rate_saved: float = 0.0

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
	if x >= 1000.0:
		return "%.2e" % x  # 単位の表より大きい（ふつうは来ない）
	if x >= 100.0:
		return "%d%s" % [int(x), SUFFIX[e]]
	return "%.2f%s" % [x, SUFFIX[e]]


# ---------------------------------------------------------------- 惑星


func start_planet(p: int, t: String) -> void:
	var prev_pm := pm
	var advancing := p == planet + 1
	planet = p
	trait_id = t
	run_seed = randi()
	tool_levels = {}
	for td in TOOLS:
		tool_levels[td["id"]] = 0
	tool_levels["drone"] = 1
	relics = []
	if local_planet() == 1:
		parts = {}  # 新しい星系に入ったとき（制覇・周回）はパーツが外れる
	pm = 1.0
	pm = choose_pm()
	if advancing and p > 1:
		# 見込みは硬さにあまり左右されないことがあるので、前の惑星からの伸びも抑える（1〜1万倍）
		pm = clampf(pm, prev_pm, prev_pm * 1.0e4)
	est_start = estimate_time(pm)
	offline_used = false
	credits = 20.0 * pow(4.0, skill_level("start_cr")) * pow(planet_mult(), 0.5) * (50.0 if has_key("k_loan") else 1.0)
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


## 惑星ごとの硬さ（着いたときに choose_pm で決めた値）
func planet_mult() -> float:
	return pm


func galaxy() -> int:
	return (planet - 1) / GALAXY_SIZE + 1


## 星系の中で何番目の惑星か（1〜10）
func local_planet() -> int:
	return (planet - 1) % GALAXY_SIZE + 1


func galaxy_cr_mult(g: int = 0) -> float:
	return 1.0 + GALAXY_CR * ((galaxy() if g <= 0 else g) - 1)


func galaxy_hp_mult(g: int = 0) -> float:
	return pow(GALAXY_HP, (galaxy() if g <= 0 else g) - 1)


## 開いている一番先の星系
func galaxy_best() -> int:
	return (best_planet - 1) / GALAXY_SIZE + 1


func place_name(p: int = 0) -> String:
	var n := planet if p <= 0 else p
	return "星系 %d・惑星 %d" % [(n - 1) / GALAXY_SIZE + 1, (n - 1) % GALAXY_SIZE + 1]


## 基本の曲線：星系の中で1つ進むごとに PLANET_G 倍、星系が1つ進むごとに GALAXY_HP 倍。
## そのうえで、今の力で割ったときの見込み時間が MIN_T〜MAX_T に収まるよう寄せる。
## （スキルや星核で強くなると速く割れるが、一瞬で終わったり、何時間も詰まったりはしない）
func choose_pm() -> float:
	if planet == 1 and best_planet <= 1:
		return 1.0
	var base := pow(PLANET_G, local_planet() - 1) * galaxy_hp_mult()
	var lo := _pm_for_time(MIN_T)
	var hi := _pm_for_time(MAX_T)
	return clampf(base, lo, maxf(lo, hi))


## 見込み時間が t 秒になる硬さ（二分探索、対数で）
func _pm_for_time(t: float) -> float:
	var a := 0.0
	var b := 60.0
	for k in 22:
		var m := (a + b) * 0.5
		if estimate_time(pow(10.0, m)) * est_bias > t:
			b = m
		else:
			a = m
	return pow(10.0, a)


## 硬さ p の惑星を、今のスキル（遺物なし）で割るのにかかる時間の見込み（秒、最大2時間）。
## 浅い順に掘り、一番安いツールから強化していく、ゆるい計算。
func estimate_time(p: float) -> float:
	var r := 38.0 if planet == 1 else 56.0
	var n_total := PI * r * r
	var dmax := 1.0 - sqrt(1.0 - CLEAR_RATIO)
	const NB := 40
	var cnt := PackedFloat32Array()
	var hpc := PackedFloat32Array()
	var val := PackedFloat32Array()
	var csum := 0.0
	for k in NB:
		var d := dmax * (k + 0.5) / NB
		cnt.append(1.0 - d)
		csum += 1.0 - d
	var cm := pow(1.35, skill_level("cr_gain")) * (1.0 + stat("cr")) * (0.6 if has_key("k_loan") else 1.0) * galaxy_cr_mult() * core_mult("cr")
	for k in NB:
		var d := dmax * (k + 0.5) / NB
		cnt[k] = cnt[k] / csum * n_total * CLEAR_RATIO
		hpc.append(2.0 * p * pow(10.0, d * 5.2) * 1.2)
		val.append(2.0 * p * pow(10.0, d * 5.2) * 0.55 * cm / pow(p, 0.45) * 1.4)
	var ids: Array = []
	for td in TOOLS:
		if tool_unlocked(String(td["id"])):
			ids.append(String(td["id"]))
	var lv := {}
	for id in ids:
		lv[id] = 1 if id == "drone" else 0
	var cr := 20.0 * pow(4.0, skill_level("start_cr")) * pow(p, 0.5) * (50.0 if has_key("k_loan") else 1.0)
	var cmul := cost_mult()
	var t := 0.0
	var dt := 10.0
	var b := 0
	var part := 0.0  # いまのバケツの、削りかけのマスに入ったダメージ
	while b < NB and t < EST_CAP:
		# 強化：一番安いツールを、2番目に安いツールの値段に届くまで（または資金が尽きるまで）まとめて買う
		for guard in 200:
			var best := ""
			var bc := INF
			var second := INF
			for id in ids:
				var td := tool_def(id)
				var c := float(td["cost"]) * cmul * pow(float(td["growth"]), int(lv[id]))
				if c < bc:
					second = bc
					bc = c
					best = id
				elif c < second:
					second = c
			if best == "" or bc > cr:
				break
			var g := float(tool_def(best)["growth"])
			var n_aff := int(floor(log(1.0 + cr * (g - 1.0) / bc) / log(g)))
			var n_cmp := int(ceil(log(maxf(second / bc, 1.0001)) / log(g))) if second < INF else n_aff
			var nb := maxi(1, mini(n_aff, n_cmp))
			cr -= bc * (pow(g, nb) - 1.0) / (g - 1.0)
			lv[best] = int(lv[best]) + nb
		var dps := 0.0
		for id in ids:
			dps += tool_dps_at(id, int(lv[id]))
		var dmg := dps * EST_EFF * dt + part
		part = 0.0
		while b < NB and dmg > 0.0:
			var need := hpc[b] * cnt[b]
			if dmg >= need:
				dmg -= need
				cr += val[b] * cnt[b]
				b += 1
			else:
				var k := floorf(dmg / hpc[b])
				cnt[b] -= k
				cr += val[b] * k
				part = dmg - k * hpc[b]
				dmg = 0.0
		t += dt
		dt = maxf(10.0, t * 0.02)
	return t


## 閉じていた間の掘る速さ（保存したときの実際のペースに対する割合）
func offline_eff() -> float:
	return OFFLINE_RATE * (1.0 + 0.3 * skill_level("offline"))


func core_mult(id: String) -> float:
	var amt := {"pow": 0.2, "mat": 0.15, "cr": 0.25}
	return 1.0 + float(amt.get(id, 0.0)) * int(core_lv.get(id, 0))


func core_cost(id: String) -> float:
	for c in CORE_UPS:
		if c["id"] == id:
			return ceilf(float(c["cost"]) * pow(float(c["growth"]), int(core_lv.get(id, 0))))
	return INF


func buy_core(id: String) -> bool:
	var c := core_cost(id)
	if c > cores + 0.001:
		return false
	cores -= c
	core_lv[id] = int(core_lv.get(id, 0)) + 1
	save()
	changed.emit()
	return true


## 星系の最後の惑星を割ったときに手に入る星核の数
func cores_for_clear() -> float:
	return 2.0 + float(galaxy())


## 星系を選び直す（周回）。その星系の惑星1から始める。開いている星系だけ。
func can_warp(g: int) -> bool:
	return g >= 1 and g <= galaxy_best()


## 深さ（0=表面, 1=中心）ごとの1マスの耐久。深いほど指数的に硬い。
func cell_hp(depth: float) -> float:
	return 2.0 * planet_mult() * pow(10.0, depth * 5.2)


func cell_value(depth: float) -> float:
	# 先の惑星ほど「硬さの割に安い」。スキルで地力を上げないと時間がかかる
	return cell_hp(depth) * 0.55 * cr_mult() / pow(planet_mult(), 0.45)


func cr_mult() -> float:
	return (1.0 + part_stat("cr")) * pow(1.35, skill_level("cr_gain")) * (1.0 + stat("cr")) * (1.0 + 0.5 * relic_count("cr")) * (0.6 if has_key("k_loan") else 1.0) * galaxy_cr_mult() * core_mult("cr")


func earn(amount: float, track: bool = true) -> void:
	credits += amount
	if track:
		_income_acc += amount


func mat_mult() -> float:
	return (1.0 + part_stat("mat")) * (1.0 + 0.1 * skill_level("mat_find") + stat("mat")) * (1.0 + 0.3 * relic_count("mat")) * (0.7 if has_key("k_relic") else 1.0) * core_mult("mat")


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
	if local_planet() == GALAXY_SIZE:
		cores += cores_for_clear()
	if not offline_used and est_start > 0.0 and planet_time > 60.0:
		var ratio := clampf(planet_time / est_start, 0.02, 50.0)
		est_bias = clampf(exp(lerpf(log(est_bias), log(ratio), 0.35)), 0.02, 50.0)
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
	return pow(1.45, skill_level("resonance")) * (1.0 + stat("pow")) * pow(2.5, skill_level("overdrive")) * (1.0 + 0.5 * relic_count("power")) * core_mult("pow")


func milestone_mult() -> float:
	return 2.0 + 0.25 * skill_level("mastery")


func tool_dps_at(id: String, lv: int) -> float:
	if lv <= 0:
		return 0.0
	var t := tool_def(id)
	var d := float(t["dps"]) * lv * pow(milestone_mult(), lv / 25) * dps_mult() * part_pow(id)
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
	return maxf(0.5, 1.0 - part_stat("cost")) * pow(0.95, skill_level("discount")) * maxf(0.3, 1.0 - stat("cost")) * pow(0.85, relic_count("cost"))


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
	return (1.0 + part_stat("move")) * (1.0 + 0.4 * skill_level("thrust") + stat("move")) * (2.0 if has_key("k_drift") else 1.0)


## 自動探索で鉄・銅などの鉱脈を探しに行く範囲（マス）
func scan_radius() -> int:
	return (16 + 8 * skill_level("auto_scan")) * (2 if has_key("k_drift") else 1)


func drone_count() -> int:
	return 1 + skill_level("drone_count") + relic_count("drone")


# ---------------------------------------------------------------- 属性とパーツ


## ツールの属性（武器パーツの属性が優先）
func tool_elem(id: String) -> String:
	var p: Dictionary = parts.get(id, {})
	if p.has("elem"):
		return String(p["elem"])
	return String(TOOL_ELEM.get(id, ""))


## 属性とブロックの相性（×2 / ×0.5 / ×1）
func affinity(elem: String, b: int) -> float:
	if elem == "":
		return 1.0
	return float((AFFINITY.get(elem, {}) as Dictionary).get(b, 1.0))


## 付けているパーツの効果の合計。slot を渡すとその枠だけ
func part_stat(k: String, slot: String = "") -> float:
	var t := 0.0
	for sl in parts:
		if slot != "" and sl != slot:
			continue
		for m in (parts[sl] as Dictionary).get("mods", []):
			if String(m["k"]) == k:
				t += float(m["v"])
	return t


## パーツによる、ツールの表示の威力の倍率（どのマスにも効く分）
func part_pow(id: String) -> float:
	var e := tool_elem(id)
	var m := (1.0 + part_stat("pow", id)) * (1.0 + part_stat("all"))
	if e != "":
		m *= 1.0 + part_stat(e)
	return m


## マスに当てたときの倍率（相性と、武器パーツの条件つきの効果）。tool が "" なら属性なし
func hit_mult(tool: String, b: int, dp: float) -> float:
	if tool == "":
		return 1.0
	var a := affinity(tool_elem(tool), b)
	var m := a
	if a > 1.0:
		m *= 1.0 + part_stat("strong", tool)
	if String(BLOCKS[b]["mat"]) != "":
		m *= 1.0 + part_stat("ore", tool)
	if dp > 0.5:
		m *= 1.0 + part_stat("deep", tool)
	return m


func slot_name(slot: String) -> String:
	if SLOT_NAMES.has(slot):
		return String(SLOT_NAMES[slot])
	return String(tool_def(slot).get("name", slot))


func is_weapon_slot(slot: String) -> bool:
	return not SLOT_NAMES.has(slot)


## パーツを付けられる枠（解放済みのツールと母艦の2枠）
func open_slots() -> Array:
	var out: Array = []
	for sl in PART_SLOTS:
		if not is_weapon_slot(sl) or tool_unlocked(sl):
			out.append(sl)
	return out


## ランダムなパーツを1つ作る。先の星系ほど少しレアが出やすい
func roll_part(slot: String = "") -> Dictionary:
	if slot == "":
		var sl := open_slots()
		slot = String(sl[randi() % sl.size()])
	var w := RARITY_W.duplicate()
	w[1] = float(w[1]) * (1.0 + 0.15 * (galaxy() - 1))
	w[2] = float(w[2]) * (1.0 + 0.3 * (galaxy() - 1))
	var roll := randf() * (float(w[0]) + float(w[1]) + float(w[2]))
	var rar := 0
	if roll > float(w[0]):
		rar = 1 if roll <= float(w[0]) + float(w[1]) else 2
	var p := {"slot": slot, "rarity": rar}
	var pool: Array
	var elem := ""
	if is_weapon_slot(slot):
		# 武器パーツは属性を持つ（6割はツールのもとの属性と違う属性になる）
		elem = String(TOOL_ELEM.get(slot, ""))
		if elem == "" or randf() < 0.6:
			elem = String(ELEMS[randi() % ELEMS.size()])
		p["elem"] = elem
		pool = ["pow", "strong", "ore", "deep"]
	else:
		pool = (REACTOR_MODS if slot == "reactor" else FRAME_MODS).duplicate()
	pool.shuffle()
	var mods: Array = []
	for k in mini(int(RARITY_MODS[rar]), pool.size()):
		var id := String(pool[k])
		var v := float(PART_MODS[id]["base"]) * float(RARITY_K[rar]) * randf_range(0.6, 1.4)
		v = roundf(v * 100.0) / 100.0
		mods.append({"k": id, "v": maxf(0.01, v)})
	p["mods"] = mods
	var bases: Array = PART_BASE[slot]
	p["name"] = String(ELEM_PREFIX.get(elem, "")) + String(bases[randi() % bases.size()])
	return p


## 宝箱などから出るパーツの3択（同じ枠に偏らないよう、なるべく別の枠から）
func roll_part_choices() -> Array:
	var sl := open_slots()
	sl.shuffle()
	var out: Array = []
	for k in 3:
		out.append(roll_part(String(sl[k % sl.size()])))
	return out


func part_lines(p: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	if p.has("elem"):
		out.append("属性 %s" % ELEM_NAMES[String(p["elem"])])
	for m in p.get("mods", []):
		out.append(String(PART_MODS[String(m["k"])]["text"]) % int(round(float(m["v"]) * 100.0)))
	return out


## パーツのよさの目安（自動で選ぶときに使う）
func part_score(p: Dictionary) -> float:
	if p.is_empty():
		return 0.0
	var s := 0.0
	for m in p.get("mods", []):
		s += float(m["v"]) / float(PART_MODS[String(m["k"])]["base"])
	return s


func equip_part(p: Dictionary) -> void:
	parts[String(p["slot"])] = p
	changed.emit()


func part_count() -> int:
	return parts.size()


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
	if rate_provider.is_valid():
		damage_rate_saved = float(rate_provider.call())
	var cfg := ConfigFile.new()
	cfg.set_value("run", "seed", run_seed)
	cfg.set_value("run", "planet", planet)
	cfg.set_value("run", "trait", trait_id)
	cfg.set_value("run", "credits", credits)
	cfg.set_value("run", "tools", tool_levels)
	cfg.set_value("run", "relics", relics)
	cfg.set_value("run", "parts", parts)
	cfg.set_value("run", "mats_this_planet", mats_this_planet)
	cfg.set_value("run", "time", planet_time)
	cfg.set_value("run", "hp", saved_hp)
	cfg.set_value("run", "income_rate", income_rate)
	cfg.set_value("run", "pm", pm)
	cfg.set_value("run", "rate", damage_rate_saved)
	cfg.set_value("run", "est_start", est_start)
	cfg.set_value("run", "offline_used", offline_used)
	cfg.set_value("meta", "est_bias", est_bias)
	cfg.set_value("meta", "cores", cores)
	cfg.set_value("meta", "core_lv", core_lv)
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
	parts = cfg.get_value("run", "parts", {})
	var mtp: Dictionary = cfg.get_value("run", "mats_this_planet", {})
	for k in mtp:
		mats_this_planet[k] = float(mtp[k])
	planet_time = float(cfg.get_value("run", "time", 0.0))
	saved_hp = cfg.get_value("run", "hp", PackedFloat32Array())
	income_rate = float(cfg.get_value("run", "income_rate", 0.0))
	pm = float(cfg.get_value("run", "pm", pow(60.0, planet - 1)))
	damage_rate_saved = float(cfg.get_value("run", "rate", 0.0))
	est_start = float(cfg.get_value("run", "est_start", 0.0))
	offline_used = bool(cfg.get_value("run", "offline_used", false))
	est_bias = float(cfg.get_value("meta", "est_bias", EST_BIAS0))
	cores = float(cfg.get_value("meta", "cores", 0.0))
	core_lv = cfg.get_value("meta", "core_lv", {})
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
		# 閉じていた間の採掘は、惑星を作った後に main.gd が実際のマスを削って進める
		offline_secs = minf(away, (OFFLINE_CAP_H + skill_level("offline")) * 3600.0)
		if pending_clear:
			offline_secs = 0.0
