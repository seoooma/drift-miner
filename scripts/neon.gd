class_name Neon
extends RefCounted
## 見た目の決まりごと（テーマ）を一か所にまとめたもの。
## 黒い宇宙に細い線、色はネオンの差し色として控えめに使う。
## グラデーション・ベベル・光沢・影・角の丸みは使わない。光は線と演出にだけ、
## 同じ色を約40%の濃さで太く重ねて（加算合成で）にじませる。

# ---- 色
const BG := Color("#000000")
const PANEL := Color("#050608")
const LINE := Color("#E8ECEF")
const TEXT := Color("#E6E6E6")
const MUTED := Color("#7C828C")
const TRACK := Color("#1A1D22")
const CYAN := Color("#4FD8E8")
const MAGENTA := Color("#E070D8")
const LIME := Color("#9BE86A")
const ORANGE := Color("#F2A23A")
const YELLOW := Color("#F2E05A")
const RED := Color("#E8504A")

const GLOW_ALPHA := 0.4
const GLOW_PX := 6.0  # にじみの太さ（画面のピクセル）

## 地形の塗り（惑星ごとに色相だけ変える、ごく暗い単色）
const TERRAIN_BASE := Color("#121A2A")

## ツールの差し色（アイコンだけに使う）
const TOOL_COLORS := {"drone": CYAN, "cutter": ORANGE, "laser": RED, "bomb": MAGENTA, "lance": LIME, "swarm": YELLOW}

# ---- 文字
const FONT_PATH := "res://fonts/ui_font.tres"
const SHADOW := Color(0, 0, 0, 0.9)

static var _font: Font


static func font() -> Font:
	if _font == null:
		_font = load(FONT_PATH)
	return _font


static func glow(c: Color) -> Color:
	return Color(c, c.a * GLOW_ALPHA)


## 文字を読みやすくする 1px の影だけ付ける（太い縁取りはしない）
static func plain_text(c: Control, size: int, col: Color = TEXT) -> void:
	c.add_theme_font_size_override("font_size", size)
	c.add_theme_font_size_override("normal_font_size", size)
	c.add_theme_color_override("font_color", col)
	c.add_theme_color_override("default_color", col)
	c.add_theme_constant_override("outline_size", 0)
	c.add_theme_color_override("font_shadow_color", SHADOW)
	c.add_theme_constant_override("shadow_offset_x", 1)
	c.add_theme_constant_override("shadow_offset_y", 1)
	c.add_theme_constant_override("shadow_outline_size", 0)


# ---- 線

## にじみ付きの線。下に太くて薄い線（加算）を敷き、上に細い線を引く。
## w は線の太さ（描く座標系の単位）。glow_w はにじみの太さ。
static func glow_line(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, w: float, glow_w: float) -> void:
	ci.draw_line(a, b, glow(col), glow_w)
	ci.draw_line(a, b, col, w)


static func glow_poly(ci: CanvasItem, pts: PackedVector2Array, col: Color, w: float, glow_w: float) -> void:
	ci.draw_polyline(pts, glow(col), glow_w)
	ci.draw_polyline(pts, col, w)


## 揺らぐ輪：半径に ±jitter のノイズを乗せた円。seed を数フレームごとに変えると震えて見える。
static func jitter_ring(center: Vector2, r: float, jitter: float, seed: int, segs: int = 40) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var pts := PackedVector2Array()
	for i in segs:
		var a := TAU * i / segs
		pts.append(center + Vector2.from_angle(a) * (r + rng.randf_range(-jitter, jitter)))
	pts.append(pts[0])
	return pts


## HUD の角かっこ（左上と右下の L 字）
static func brackets(ci: CanvasItem, rect: Rect2, col: Color, arm: float = 8.0, w: float = 2.0) -> void:
	var p := rect.position
	var e := rect.end
	var h := w * 0.5
	ci.draw_line(Vector2(p.x + h, p.y), Vector2(p.x + h, p.y + arm), col, w)
	ci.draw_line(Vector2(p.x, p.y + h), Vector2(p.x + arm, p.y + h), col, w)
	ci.draw_line(Vector2(e.x - h, e.y), Vector2(e.x - h, e.y - arm), col, w)
	ci.draw_line(Vector2(e.x, e.y - h), Vector2(e.x - arm, e.y - h), col, w)


## 枠線（角は直角）。内側に収まるよう半分ずらす。
static func frame(ci: CanvasItem, rect: Rect2, col: Color, w: float = 1.0) -> void:
	ci.draw_rect(rect.grow(-w * 0.5), col, false, w)


# ---- 線のアイコン（自作）。中心 c、大きさ s（幅）、線の太さ w。

static func icon(ci: CanvasItem, id: String, c: Vector2, s: float, col: Color, w: float = 1.5) -> void:
	var h := s * 0.5
	match id:
		"skill":  # 枝分かれしたノード
			var a := c + Vector2(-h * 0.6, h * 0.55)
			var b := c + Vector2(0, -h * 0.1)
			var d1 := c + Vector2(h * 0.65, -h * 0.6)
			var d2 := c + Vector2(h * 0.65, h * 0.4)
			var d0 := c + Vector2(-h * 0.6, -h * 0.6)
			ci.draw_line(a, b, col, w)
			ci.draw_line(b, d1, col, w)
			ci.draw_line(b, d2, col, w)
			ci.draw_line(b, d0, col, w)
			for p in [a, d1, d2, d0]:
				ci.draw_rect(Rect2(p - Vector2(2.5, 2.5), Vector2(5, 5)), col, false, w)
			ci.draw_rect(Rect2(b - Vector2(3.5, 3.5), Vector2(7, 7)), col)
		"relic":  # ひし形の結晶
			var pts := PackedVector2Array([c + Vector2(0, -h * 0.85), c + Vector2(h * 0.6, -h * 0.15), c + Vector2(0, h * 0.85), c + Vector2(-h * 0.6, -h * 0.15), c + Vector2(0, -h * 0.85)])
			ci.draw_polyline(pts, col, w)
			ci.draw_line(c + Vector2(-h * 0.6, -h * 0.15), c + Vector2(h * 0.6, -h * 0.15), col, w)
			ci.draw_line(c + Vector2(0, -h * 0.85), c + Vector2(0, h * 0.85), col, w * 0.7)
		"sound", "mute":  # スピーカー
			var pts := PackedVector2Array([c + Vector2(-h * 0.75, -h * 0.25), c + Vector2(-h * 0.4, -h * 0.25), c + Vector2(0, -h * 0.65), c + Vector2(0, h * 0.65), c + Vector2(-h * 0.4, h * 0.25), c + Vector2(-h * 0.75, h * 0.25), c + Vector2(-h * 0.75, -h * 0.25)])
			ci.draw_polyline(pts, col, w)
			if id == "sound":
				ci.draw_arc(c + Vector2(h * 0.05, 0), h * 0.35, -0.9, 0.9, 8, col, w)
				ci.draw_arc(c + Vector2(h * 0.05, 0), h * 0.7, -0.9, 0.9, 10, col, w)
			else:
				ci.draw_line(c + Vector2(h * 0.25, -h * 0.3), c + Vector2(h * 0.8, h * 0.3), col, w)
				ci.draw_line(c + Vector2(h * 0.25, h * 0.3), c + Vector2(h * 0.8, -h * 0.3), col, w)
		_:
			ci.draw_polyline(ship(id, c, s * 0.9, -PI * 0.5), col, w)
			if id == "laser":
				ci.draw_line(c + Vector2(-h * 0.85, 0), c + Vector2(h * 0.85, 0), col, w)


## 機体の線画の形（向き rot は前方の角度）。s は全長。
static func ship(id: String, c: Vector2, s: float, rot: float) -> PackedVector2Array:
	var raw: Array
	match id:
		"drone":  # 矢じり
			raw = [Vector2(0.5, 0), Vector2(-0.4, 0.4), Vector2(-0.2, 0), Vector2(-0.4, -0.4), Vector2(0.5, 0)]
		"cutter":  # 先の尖った掘削機
			raw = [Vector2(0.5, 0), Vector2(0.1, 0.32), Vector2(-0.45, 0.32), Vector2(-0.45, -0.32), Vector2(0.1, -0.32), Vector2(0.5, 0)]
		"laser":  # 衛星の胴（パネルは別に線を引く）
			raw = [Vector2(0.2, 0.2), Vector2(-0.2, 0.2), Vector2(-0.2, -0.2), Vector2(0.2, -0.2), Vector2(0.2, 0.2)]
		"bomb":  # 尾翼つきの弾
			raw = [Vector2(0.5, 0), Vector2(0.2, 0.18), Vector2(-0.3, 0.18), Vector2(-0.5, 0.35), Vector2(-0.5, -0.35), Vector2(-0.3, -0.18), Vector2(0.2, -0.18), Vector2(0.5, 0)]
		"lance":  # 六角形の基地
			raw = []
			for k in 7:
				raw.append(Vector2.from_angle(TAU * k / 6.0) * 0.45)
		"swarm":  # 小さな三角
			raw = [Vector2(0.5, 0), Vector2(-0.4, 0.4), Vector2(-0.4, -0.4), Vector2(0.5, 0)]
		"carrier":  # 母艦：幅の広い V 字の船体
			raw = [Vector2(0.5, 0), Vector2(-0.1, 0.5), Vector2(-0.5, 0.5), Vector2(-0.25, 0), Vector2(-0.5, -0.5), Vector2(-0.1, -0.5), Vector2(0.5, 0)]
		_:
			raw = [Vector2(0.4, 0.4), Vector2(-0.4, 0.4), Vector2(-0.4, -0.4), Vector2(0.4, -0.4), Vector2(0.4, 0.4)]
	var out := PackedVector2Array()
	for v in raw:
		out.append(c + (v as Vector2).rotated(rot) * s)
	return out
