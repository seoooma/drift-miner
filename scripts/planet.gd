class_name Planet
extends Node2D
## 巨大なピクセル惑星。マスごとに耐久とブロックの種類を持ち、削られると欠けていく。
## 形・地殻の色・鉱脈・遺物や宝箱の位置はシードと惑星の特性から毎回ランダムに作る。
## 深いマスほど指数的に硬く、価値も高い。

signal cell_broken(world_pos: Vector2, value: float, block: int)
signal cleared
signal relic_lost(world_pos: Vector2, block: int)  # 埋まった遺物・宝箱が爆発に巻き込まれて壊れた

const CELL := 8.0
const RADIUS := 56
const DEPTH_W := 40.0  # 狙う点数で、深さをどれだけ嫌うか（大きいほど表面を広く削る）
const FIRST_RADIUS := 38  # 最初の惑星だけ小さくして、ループ全体を早めに見せる
const WIDEN_K := 0.2  # 特性で鉱石が増えるとき、鉱脈の境目をずらす強さ
## 鉱石の塗りの暗さ（darkened の量）。価値の順に明るくする
const ORE_DARK := {1: 0.74, 2: 0.6, 3: 0.46, 4: 0.36, 8: 0.6}

var radius_cells: int = RADIUS
var size: int = 0
var hp := PackedFloat32Array()
var max_hp := PackedFloat32Array()
var depth := PackedFloat32Array()
var block := PackedByteArray()
var alive_count: int = 0
var total_cells: int = 0
var done: bool = false
var outer: float = 0.0  # いま残っている一番外側のマスまでの距離（ワールド単位）
var buried: Array = []  # 遺物・宝箱のマス番号
var air := PackedByteArray()  # 1 = 惑星の外とつながった空き（機体が入れる所）

var _img: Image
var _tex: ImageTexture
var _base_colors := PackedColorArray()
var _dirty := false
var _outer_t: float = 0.0
var _glow := Color.WHITE
var fill_color := Neon.TERRAIN_BASE  # 岩の塗り（ミニマップでも使う）
var _t: float = 0.0
var _cells: Sprite2D  # マス目（シェーダーで平らな塗りと輪郭線を描く）
var _marks: Node2D  # 遺物・宝箱の目印（マス目の上に描く）
var _shader_mat: ShaderMaterial
var _dealt: float = 0.0  # 直近に与えたダメージ（残り時間の見込みに使う）
var _rate_t: float = 0.0
var damage_rate: float = 0.0  # 実際に岩に入っている毎秒のダメージ（ならした値）
var _rem_t: float = 0.0
var remaining_hp: float = 0.0  # クリアまでに削る必要のある耐久の合計（2秒ごとに計算）
var cleared_hp: float = 0.0  # これまでに削った耐久（クリアに必要な分のうち）
var hunt_cell: int = -1  # プレイヤーが掘りに行くと決めた、埋まった遺物・宝箱（なければ -1）
var signal_pos := Vector2.INF  # ここから SIGNAL_R マス以内の埋まった遺物・宝箱は「気配」が見える
const SIGNAL_R := 12.0
var _exploding := false
var _need_total: float = 0.0  # クリアに必要な耐久の合計（作ったときの値）


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_cells = Sprite2D.new()
	_cells.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = load("res://shaders/cells.gdshader")
	_cells.material = _shader_mat
	add_child(_cells)
	_marks = Node2D.new()
	_marks.draw.connect(_draw_marks)
	add_child(_marks)


func generate(seed_value: int, trait_rates: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	radius_cells = FIRST_RADIUS if GameState.planet == 1 else RADIUS
	size = radius_cells * 2 + 1
	var n := size * size
	hp.resize(n)
	max_hp.resize(n)
	depth.resize(n)
	block.resize(n)
	_base_colors.resize(n)
	buried.clear()
	alive_count = 0
	done = false
	hunt_cell = -1
	_need_total = 0.0
	remaining_hp = 0.0
	damage_rate = 0.0
	_dealt = 0.0
	_rem_t = 0.0

	var hue := rng.randf()
	# 岩は惑星ごとに色相だけ変えた、ごく暗い単色（例 #121A2A）
	var base_h := Neon.TERRAIN_BASE.h
	# 岩の色相は青〜青緑〜灰の狭い範囲に収め、鉱石の色（橙・黄・紫）と重ならないようにする
	var crust := Color.from_hsv(fmod(base_h + (hue - 0.5) * 0.16 + 1.0, 1.0), Neon.TERRAIN_BASE.s, Neon.TERRAIN_BASE.v)
	fill_color = crust
	var mantle := crust
	var deep := crust
	_glow = Color.from_hsv(fmod(hue + 0.5, 1.0), 0.6, 1.0)

	var shape := FastNoiseLite.new()
	shape.seed = seed_value
	shape.frequency = 0.8
	var veins := FastNoiseLite.new()
	veins.seed = seed_value + 11
	veins.frequency = 0.09
	var veins2 := FastNoiseLite.new()
	veins2.seed = seed_value + 23
	veins2.frequency = 0.07
	var hard := FastNoiseLite.new()
	hard.seed = seed_value + 37
	hard.frequency = 0.05

	var luck := GameState.relic_luck()
	var r_iron := float(trait_rates.get(GameState.B.IRON, 1.0))
	var r_cu := float(trait_rates.get(GameState.B.COPPER, 1.0))
	var r_au := float(trait_rates.get(GameState.B.GOLD, 1.0))
	var r_cr := float(trait_rates.get(GameState.B.CRYSTAL, 1.0))
	var r_relic := float(trait_rates.get(GameState.B.RELIC, 1.0)) * luck
	var r_cache := float(trait_rates.get(GameState.B.CACHE, 1.0)) * luck
	var r_vol := float(trait_rates.get(GameState.B.VOLATILE, 1.0))
	var r_hard := float(trait_rates.get(GameState.B.HARD, 1.0))

	for y in size:
		for x in size:
			var i := y * size + x
			var d := Vector2(x - radius_cells, y - radius_cells)
			var ang := d.angle()
			var edge := radius_cells - 0.5 + shape.get_noise_2d(cos(ang) * 2.0, sin(ang) * 2.0) * 3.0
			var r := d.length()
			if r > edge:
				hp[i] = 0.0
				max_hp[i] = 0.0
				block[i] = 255
				continue
			var dp := clampf(1.0 - r / edge, 0.0, 1.0)
			depth[i] = dp
			var b: int = GameState.B.ROCK
			var v := veins.get_noise_2d(x, y)
			var v2 := veins2.get_noise_2d(x, y)
			var roll := rng.randf()
			# 遺物・宝箱・爆薬岩は確率を積み上げて判定する（どれかが増えても、ほかが減らない）
			var p_relic := 0.0012 * r_relic * (0.5 + dp)
			var p_cache := 0.0035 * r_cache
			var p_vol := 0.006 * r_vol
			if dp > 0.9:
				b = GameState.B.CORE
			elif roll < p_relic:
				b = GameState.B.RELIC
			elif roll < p_relic + p_cache:
				b = GameState.B.CACHE
			elif roll < p_relic + p_cache + p_vol:
				b = GameState.B.VOLATILE
			elif v > 0.42 - _widen(0.5, r_cr) and dp > 0.35 and rng.randf() < 0.5 * r_cr:
				b = GameState.B.CRYSTAL
			elif v2 > 0.38 - _widen(0.55, r_au) and rng.randf() < 0.55 * r_au * (0.4 + dp):
				b = GameState.B.GOLD
			elif v > 0.2 - _widen(0.6, r_cu) and rng.randf() < 0.6 * r_cu:
				b = GameState.B.COPPER
			elif v2 < -0.25 + _widen(0.7, r_iron) and rng.randf() < 0.7 * r_iron:
				b = GameState.B.IRON
			elif hard.get_noise_2d(x, y) > 0.45 - 0.1 * (r_hard - 1.0) and dp > 0.1:
				b = GameState.B.HARD
			block[i] = b
			var h := GameState.cell_hp(dp) * float(GameState.BLOCKS[b]["hp"])
			hp[i] = h
			max_hp[i] = h
			if b == GameState.B.RELIC or b == GameState.B.CACHE:
				buried.append(i)
			_base_colors[i] = _cell_color(b, dp, crust, mantle, deep, rng)
			alive_count += 1
	total_cells = alive_count

	_img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	_redraw_all()
	_rebuild_air()
	_update_outer()


## 鉱脈の出やすさを上げる特性で、確率が1を超えて頭打ちになる分を、鉱脈の広さで補う。
## p はもとの確率、r は倍率。p*r が1を超えるときだけ、鉱脈の境目をずらす量を返す。
func _widen(p: float, r: float) -> float:
	if p * r <= 1.0:
		return 0.0
	return WIDEN_K * (p * r - 1.0)


func _cell_color(b: int, _dp: float, crust: Color, _mantle: Color, _deep: Color, _rng: RandomNumberGenerator) -> Color:
	# 遺物と宝箱は見た目では岩と区別できない（掘り当てるまで分からない）
	if b == GameState.B.ROCK or b == GameState.B.RELIC or b == GameState.B.CACHE:
		return crust
	if b == GameState.B.HARD:
		return crust.lightened(0.06)
	if b == GameState.B.CORE:
		return Color(GameState.BLOCK_COLORS[b], 1.0).darkened(0.72)
	# 鉱石・爆発するマスは暗めの色。アルファ 0.9 を目印に、シェーダーが内側の明るい縁を描く。
	# 価値の高い鉱石ほど明るくして、目が先に行くようにする（鉄が一番暗く、結晶が一番明るい）。
	var c: Color = (GameState.BLOCK_COLORS[b] as Color).darkened(ORE_DARK.get(b, 0.62))
	c.a = 0.9
	return c


func _redraw_all() -> void:
	for y in size:
		for x in size:
			var i := y * size + x
			if hp[i] <= 0.0:
				_img.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				var k := 1.0 - hp[i] / max_hp[i]
				_img.set_pixel(x, y, _damaged(i, k))
	if _tex == null or _tex.get_width() != size:
		_tex = ImageTexture.create_from_image(_img)
	else:
		_tex.update(_img)
	if _cells != null:
		_cells.texture = _tex
		_cells.scale = Vector2(CELL, CELL)
		_shader_mat.set_shader_parameter("grid", Vector2(size, size))
	queue_redraw()


## 削られたマスは少し明るくなる（平らな色のまま。アルファは目印なので保つ）
func _damaged(i: int, k: float) -> Color:
	var c := _base_colors[i]
	var out := c.lerp(Neon.LINE, k * 0.18)
	out.a = c.a
	return out


## 保存しておいた掘った跡を戻す
func restore(saved: PackedFloat32Array) -> void:
	if saved.size() != hp.size():
		return
	alive_count = 0
	for i in hp.size():
		if max_hp[i] <= 0.0:
			continue
		hp[i] = minf(saved[i], max_hp[i])
		if hp[i] > 0.0:
			alive_count += 1
	var still: Array = []
	for i in buried:
		if hp[i] > 0.0:
			still.append(i)
	buried = still
	done = broken() >= needed()
	_update_remaining()
	_rem_t = 2.0
	_redraw_all()
	_rebuild_air()
	_update_outer()


## 惑星の外とつながった空きを調べ直す（外周から塗りつぶす）
func _rebuild_air() -> void:
	air.resize(hp.size())
	air.fill(0)
	var q: Array = []
	for y in size:
		for x in size:
			if x == 0 or y == 0 or x == size - 1 or y == size - 1:
				var i := y * size + x
				if hp[i] <= 0.0 and air[i] == 0:
					air[i] = 1
					q.append(i)
	_flood(q)


func _flood(q: Array) -> void:
	while not q.is_empty():
		var i: int = q.pop_back()
		var x := i % size
		var y := i / size
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + o.x
			var ny: int = y + o.y
			if nx < 0 or ny < 0 or nx >= size or ny >= size:
				continue
			var j := ny * size + nx
			if air[j] == 0 and hp[j] <= 0.0:
				air[j] = 1
				q.append(j)


## 砕けたマスが外とつながっていれば、そこから先の空きも外とつなぐ
func _open_cell(i: int) -> void:
	var x := i % size
	var y := i / size
	var touch := x == 0 or y == 0 or x == size - 1 or y == size - 1
	if not touch:
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if air[(y + o.y) * size + x + o.x] == 1:
				touch = true
				break
	if touch:
		air[i] = 1
		_flood([i])


## その場所に機体が入れるか（惑星の外か、外とつながった掘り跡）
func is_open(world_pos: Vector2) -> bool:
	var i := cell_at(world_pos)
	return i < 0 or air[i] == 1


## マス i の空いている側の向き（外とつながった隣のマスの方向の平均）
func open_dir(i: int) -> Vector2:
	var x := i % size
	var y := i / size
	var v := Vector2.ZERO
	for oy in [-1, 0, 1]:
		for ox in [-1, 0, 1]:
			if ox == 0 and oy == 0:
				continue
			var nx: int = x + ox
			var ny: int = y + oy
			if nx < 0 or ny < 0 or nx >= size or ny >= size or air[ny * size + nx] == 1:
				v += Vector2(ox, oy).normalized()
	return v.normalized() if v.length() > 0.01 else outward(i)


## マス i を狙うときに機体が浮かぶ位置（空いている側、入れる所だけ）
func hover_point(i: int, dist: float) -> Vector2:
	var c := cell_center(i)
	var d := open_dir(i)
	var k := dist
	while k > CELL * 0.6:
		var p := c + d * k
		if is_open(p):
			return p
		k -= CELL * 0.5
	return c + d * CELL


## a から b までまっすぐ、入れる場所だけを通って行けるか
func line_clear(a: Vector2, b: Vector2) -> bool:
	var d := a.distance_to(b)
	var n := int(d / (CELL * 0.5)) + 1
	for k in range(1, n + 1):
		if not is_open(a.lerp(b, float(k) / n)):
			return false
	return true


## from から to への、入れる場所だけを通る道（マスの中心の並び）。見つからなければ空。
## 探す広さは limit マスまで（遠すぎる道は探さない）。
func find_path(from: Vector2, to: Vector2, limit: int = 2500) -> PackedVector2Array:
	var out := PackedVector2Array()
	var s0 := _grid_of(from)
	var g0 := _grid_of(to)
	if s0 == g0:
		out.append(to)
		return out
	var prev := {s0: -1}
	var q: Array = [s0]
	var head := 0
	var found := false
	while head < q.size() and q.size() < limit:
		var c: int = q[head]
		head += 1
		if c == g0:
			found = true
			break
		var x := c % size
		var y := c / size
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + o.x
			var ny: int = y + o.y
			if nx < 0 or ny < 0 or nx >= size or ny >= size:
				continue
			var j := ny * size + nx
			if prev.has(j) or (air[j] == 0 and j != g0):
				continue
			prev[j] = c
			q.append(j)
	if not found:
		return out
	var cells: Array = []
	var c := g0
	while c != -1:
		cells.push_front(c)
		c = prev[c]
	# 見通しのきく所は飛ばして、なめらかにする
	var pts: Array = []
	for i in cells:
		pts.append(cell_center(i))
	pts[pts.size() - 1] = to
	var cur := from
	var k := 0
	while k < pts.size():
		var far := k
		for m in range(pts.size() - 1, k, -1):
			if line_clear(cur, pts[m]):
				far = m
				break
		out.append(pts[far])
		cur = pts[far]
		k = far + 1
	return out


func _grid_of(p: Vector2) -> int:
	var q := (p - position) / CELL + Vector2(radius_cells + 0.5, radius_cells + 0.5)
	return clampi(int(floor(q.y)), 0, size - 1) * size + clampi(int(floor(q.x)), 0, size - 1)


## p から一番近い、外に面した生きているマス（なければ -1）。近くに候補がないときの保険。
func nearest_exposed(p: Vector2) -> int:
	var q := (p - position) / CELL + Vector2(radius_cells, radius_cells)
	var cx := clampi(int(round(q.x)), 0, size - 1)
	var cy := clampi(int(round(q.y)), 0, size - 1)
	for r in range(0, size):
		for y in range(maxi(0, cy - r), mini(size, cy + r + 1)):
			for x in range(maxi(0, cx - r), mini(size, cx + r + 1)):
				if absi(x - cx) != r and absi(y - cy) != r:
					continue
				var i := y * size + x
				if hp[i] > 0.0 and is_exposed(i):
					return i
	return -1


## world_pos が岩の中なら、外向きにたどって一番近い入れる場所を返す
func nearest_open(world_pos: Vector2) -> Vector2:
	if is_open(world_pos):
		return world_pos
	var best := Vector2.INF
	var c0 := cell_at(world_pos)
	var cx := c0 % size
	var cy := c0 / size
	for r in range(1, size):
		var bd := INF
		for y in range(cy - r, cy + r + 1):
			for x in range(cx - r, cx + r + 1):
				if absi(x - cx) != r and absi(y - cy) != r:
					continue
				var p := position + Vector2(x - radius_cells, y - radius_cells) * CELL
				if x < 0 or y < 0 or x >= size or y >= size or air[y * size + x] == 1:
					var d := p.distance_squared_to(world_pos)
					if d < bd:
						bd = d
						best = p
		if best != Vector2.INF:
			return best
	return world_pos


func world_radius() -> float:
	return radius_cells * CELL


func cell_center(i: int) -> Vector2:
	var x := i % size
	var y := i / size
	return position + Vector2(x - radius_cells, y - radius_cells) * CELL


func cell_at(world_pos: Vector2) -> int:
	var p := (world_pos - position) / CELL + Vector2(radius_cells + 0.5, radius_cells + 0.5)
	var x := int(floor(p.x))
	var y := int(floor(p.y))
	if x < 0 or y < 0 or x >= size or y >= size:
		return -1
	return y * size + x


func is_alive(i: int) -> bool:
	return i >= 0 and i < hp.size() and hp[i] > 0.0


func is_exposed(i: int) -> bool:
	var x := i % size
	var y := i / size
	for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = x + o.x
		var ny: int = y + o.y
		if nx < 0 or ny < 0 or nx >= size or ny >= size or air[ny * size + nx] == 1:
			return true
	return false


func progress() -> float:
	if total_cells == 0:
		return 1.0
	return float(total_cells - alive_count) / float(total_cells)


func needed() -> int:
	return int(ceil(total_cells * GameState.CLEAR_RATIO))


func broken() -> int:
	return total_cells - alive_count


func raycast(from: Vector2, to: Vector2) -> int:
	var dist := from.distance_to(to)
	var steps := int(dist / (CELL * 0.5)) + 1
	for s in steps + 1:
		var p := from.lerp(to, float(s) / steps)
		var i := cell_at(p)
		if is_alive(i):
			return i
	return -1


func surface_cell(angle: float) -> int:
	var from := position + Vector2.from_angle(angle) * (outer + CELL * 3.0)
	return raycast(from, position)


func random_surface_cell() -> int:
	for k in 6:
		var i := surface_cell(randf() * TAU)
		if i >= 0:
			return i
	return -1


func hit(i: int, damage: float) -> bool:
	if not is_alive(i) or done:
		return false
	if depth[i] > 0.5 and GameState.relic_count("deep") > 0:
		damage *= 1.0 + GameState.relic_count("deep")
	_dealt += minf(damage, hp[i])
	hp[i] -= damage
	var x := i % size
	var y := i / size
	if hp[i] <= 0.0:
		hp[i] = 0.0
		alive_count -= 1
		_img.set_pixel(x, y, Color(0, 0, 0, 0))
		_dirty = true
		_open_cell(i)
		var b := int(block[i])
		if _exploding and (b == GameState.B.RELIC or b == GameState.B.CACHE):
			# 埋まったまま爆発に巻き込まれた遺物・宝箱は壊れて、ただの岩になる
			relic_lost.emit(cell_center(i), b)
			b = GameState.B.ROCK
		var v := GameState.cell_value(depth[i]) * float(GameState.BLOCKS[b]["value"])
		cell_broken.emit(cell_center(i), v, b)
		if b == GameState.B.VOLATILE:
			_explode(i)
		if broken() >= needed() and not done:
			done = true
			cleared.emit()
		return true
	var k := 1.0 - hp[i] / max_hp[i]
	_img.set_pixel(x, y, _damaged(i, k))
	_dirty = true
	return false


## 爆薬岩：周りのマスに大きなダメージ（連鎖する）
func _explode(i: int) -> void:
	var lv := GameState.skill_level("blast")
	var rb := GameState.relic_count("blast")
	var r := CELL * (2.5 + 0.5 * lv + rb)
	var dmg := max_hp[i] * 5.0 * (1.0 + 0.5 * lv) * (1.0 + rb)
	var c := cell_center(i)
	call_deferred("_explode_at", c, r, dmg)


func _explode_at(c: Vector2, r: float, dmg: float) -> void:
	if done:
		return
	var rc := int(ceil(r / CELL))
	var c0 := cell_at(c)
	if c0 < 0:
		return
	var cx := c0 % size
	var cy := c0 / size
	for y in range(cy - rc, cy + rc + 1):
		for x in range(cx - rc, cx + rc + 1):
			if x < 0 or y < 0 or x >= size or y >= size:
				continue
			var j := y * size + x
			if is_alive(j) and cell_center(j).distance_to(c) <= r:
				_exploding = true
				hit(j, dmg)
				_exploding = false
	var main := get_parent()
	if main != null and main.has_method("on_explosion"):
		main.on_explosion(c, r)


## 範囲攻撃。外に面しているマスだけに当たる（岩の内側には届かない）。
func hit_area(center: Vector2, r: float, damage: float) -> void:
	var cells: Array = []
	var rc := int(ceil(r / CELL))
	var c0 := cell_at(center)
	if c0 < 0:
		return
	var cx := c0 % size
	var cy := c0 / size
	for y in range(cy - rc, cy + rc + 1):
		for x in range(cx - rc, cx + rc + 1):
			if x < 0 or y < 0 or x >= size or y >= size:
				continue
			var i := y * size + x
			if is_alive(i) and cell_center(i).distance_to(center) <= r and is_exposed(i):
				cells.append(i)
	if cells.is_empty():
		return
	var each := damage / cells.size()
	for i in cells:
		hit(i, each)


## 狙う優先度。価値の高い鉱石や遺物ほど高い。硬い岩は後回し。
func priority(i: int) -> float:
	var b := int(block[i])
	var B: Dictionary = GameState.B
	if b == B["RELIC"]:
		return 7.0 if is_exposed(i) else 0.0
	if b == B["CACHE"]:
		return 6.0 if is_exposed(i) else 0.0
	if b == B["CRYSTAL"]:
		return 5.0
	if b == B["GOLD"]:
		return 4.0
	if b == B["COPPER"] or b == B["IRON"]:
		return 2.5
	if b == B["VOLATILE"]:
		return 2.0
	if b == B["HARD"]:
		return -3.0
	return 0.0


## p の周り（半径 r マス）で、表面に出ている生きたマスを「狙う順」に並べて返す。
## 近さ・鉱石の価値・浅さで点数を付ける（深い所より表面を広く削っていく）。
func targets_near(p: Vector2, r: int, dist_w: float = 1.0) -> Array:
	var c0 := cell_at(p)
	var cx: int
	var cy: int
	if c0 < 0:
		var q := (p - position) / CELL + Vector2(radius_cells, radius_cells)
		cx = int(q.x)
		cy = int(q.y)
	else:
		cx = c0 % size
		cy = c0 / size
	var scored: Array = []
	for y in range(maxi(0, cy - r), mini(size, cy + r + 1)):
		for x in range(maxi(0, cx - r), mini(size, cx + r + 1)):
			var i := y * size + x
			if hp[i] <= 0.0 or not is_exposed(i):
				continue
			var d := Vector2(x - cx, y - cy).length()
			if d > r:
				continue
			scored.append([score_at(i, d, dist_w), i])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	var out: Array = []
	for e in scored:
		out.append(e[1])
	return out


## マス i の「狙う点数」（targets_near と同じ式）。p から近く、価値が高く、浅いほど高い。
func score(i: int, p: Vector2, dist_w: float = 1.0) -> float:
	return score_at(i, cell_center(i).distance_to(p) / CELL, dist_w)


## d はマス単位の距離。遺物を掘りに行っている間は、深さを気にせず、その遺物に近いマスほど先に削る。
func score_at(i: int, d: float, dist_w: float) -> float:
	if hunt_cell >= 0 and is_alive(hunt_cell):
		return priority(i) * 3.0 - d * dist_w * 0.3 - cell_center(i).distance_to(cell_center(hunt_cell)) / CELL * 4.0
	return priority(i) * 3.0 - d * dist_w - depth[i] * DEPTH_W


## 掘りに行っている遺物へ一番近い、外に面したマス（なければ -1）
func hunt_front() -> int:
	if hunt_cell < 0 or not is_alive(hunt_cell):
		return -1
	if is_exposed(hunt_cell):
		return hunt_cell
	var hx := hunt_cell % size
	var hy := hunt_cell / size
	var best := -1
	var bd := INF
	for r in range(1, size):
		for y in range(maxi(0, hy - r), mini(size, hy + r + 1)):
			for x in range(maxi(0, hx - r), mini(size, hx + r + 1)):
				if absi(x - hx) != r and absi(y - hy) != r:
					continue
				var i := y * size + x
				if hp[i] > 0.0 and is_exposed(i):
					var d := Vector2(x - hx, y - hy).length()
					if d < bd:
						bd = d
						best = i
		if best >= 0:
			return best
	return -1


## p の近く（r マス以内）に埋まっている遺物・宝箱（なければ -1）
func buried_near(p: Vector2, r: float) -> int:
	var best := -1
	var bd := r * CELL
	for i in buried:
		if hp[i] <= 0.0:
			continue
		var d := cell_center(i).distance_to(p)
		if d <= bd:
			bd = d
			best = i
	return best


## 惑星の中心から外向きの向き（そのマスの「空」の方向）
func outward(i: int) -> Vector2:
	var v := cell_center(i) - position
	return v.normalized() if v.length() > 1.0 else Vector2.UP


func remaining_value() -> float:
	var s := 0.0
	for i in hp.size():
		if hp[i] > 0.0:
			s += GameState.cell_value(depth[i]) * float(GameState.BLOCKS[int(block[i])]["value"])
	return s


## クリアまでに削る必要のある耐久。残りのマスのうち、柔らかい順に必要な数だけ足す
## （一番硬い5%は掘らなくてよい）。
func _update_remaining() -> void:
	var left := needed() - broken()
	if left <= 0:
		remaining_hp = 0.0
		_ensure_need_total()
		cleared_hp = _need_total
		return
	var arr := PackedFloat32Array()
	for i in hp.size():
		if max_hp[i] > 0.0:
			if hp[i] > 0.0:
				arr.append(hp[i])
	arr.sort()
	var s := 0.0
	for k in mini(left, arr.size()):
		s += arr[k]
	remaining_hp = s
	_ensure_need_total()
	cleared_hp = maxf(0.0, _need_total - remaining_hp)


## 閉じていた間の採掘。ダメージ budget を、柔らかいマス（削りかけ・浅い所）から順に使って砕く。
## 遺物と宝箱は残す（戻ってから自分で掘り当てる）。爆薬岩は爆発せずに砕ける。
## クリアに必要な数に届いたらそこで止める。報酬は返り値で渡し、main.gd が入れる。
func offline_dig(budget: float) -> Dictionary:
	var gs := GameState
	var order: Array = []
	for i in hp.size():
		if hp[i] > 0.0:
			var b := int(block[i])
			if b != gs.B.RELIC and b != gs.B.CACHE:
				order.append(i)
	order.sort_custom(func(a: int, c: int) -> bool: return hp[a] < hp[c])
	var cr := 0.0
	var ores := {}
	var n := 0
	var left := needed() - broken()
	for i in order:
		if left <= 0 or budget <= 0.0:
			break
		var h := hp[i]
		if depth[i] > 0.5 and gs.relic_count("deep") > 0:
			h /= 1.0 + gs.relic_count("deep")
		if h > budget:
			hp[i] -= budget * (hp[i] / h)
			budget = 0.0
			break
		budget -= h
		hp[i] = 0.0
		alive_count -= 1
		left -= 1
		n += 1
		var b := int(block[i])
		cr += gs.cell_value(depth[i]) * float(gs.BLOCKS[b]["value"])
		if String(gs.BLOCKS[b]["mat"]) != "":
			ores[b] = int(ores.get(b, 0)) + 1
	done = broken() >= needed()
	_redraw_all()
	_rebuild_air()
	_update_outer()
	_update_remaining()
	return {"cr": cr, "ores": ores, "cells": n}


func _ensure_need_total() -> void:
	if _need_total > 0.0:
		return
	var all := PackedFloat32Array()
	for i in max_hp.size():
		if max_hp[i] > 0.0:
			all.append(max_hp[i])
	all.sort()
	var full := 0.0
	for k in mini(needed(), all.size()):
		full += all[k]
	_need_total = full


## 耐久で見た進み具合（0〜1）
func hp_progress() -> float:
	if _need_total <= 0.0:
		return 0.0
	return clampf(1.0 - remaining_hp / _need_total, 0.0, 1.0)


## 今のペースのままなら、あと何秒で割れるか（分からなければ -1）
func eta() -> float:
	if damage_rate <= 0.0 or remaining_hp <= 0.0:
		return -1.0
	return remaining_hp / damage_rate


func _update_outer() -> void:
	var best := 0.0
	for i in hp.size():
		if hp[i] > 0.0:
			var x := i % size - radius_cells
			var y := i / size - radius_cells
			var d2 := float(x * x + y * y)
			if d2 > best:
				best = d2
	outer = maxf(sqrt(best) * CELL, CELL * 3.0)


func _process(delta: float) -> void:
	_t += delta
	_rate_t += delta
	if _rate_t >= 1.0:
		var r := _dealt / _rate_t
		damage_rate = r if damage_rate <= 0.0 else lerpf(damage_rate, r, 0.25)
		_dealt = 0.0
		_rate_t = 0.0
	_rem_t -= delta
	if _rem_t <= 0.0:
		_rem_t = 2.0
		_update_remaining()
	_outer_t -= delta
	if _outer_t <= 0.0:
		_outer_t = 1.0
		_update_outer()
	if _dirty:
		_dirty = false
		_tex.update(_img)
	_marks.queue_redraw()


func _draw() -> void:
	pass


## 遺物（マゼンタ）と宝箱（黄）。表面に出てきたものは四角い枠で点滅する。
## 埋まっているものは、母艦の近く（SIGNAL_R マス以内）にあると、広がる輪の「気配」が見える。
## 透視スキャンがあれば、遠くても枠が薄く見える。掘りに行っている遺物には、二重の枠を出す。
func _draw_marks() -> void:
	var see_all := GameState.skill_level("vision") > 0
	var blink := 0.5 + 0.5 * sin(_t * 5.0)
	var px := Fx.view_scale
	for i in buried:
		if hp[i] <= 0.0:
			continue
		var exposed := is_exposed(i)
		var p := cell_center(i) - position
		var is_relic: bool = int(block[i]) == GameState.B.RELIC
		var col: Color = GameState.RELIC_COLOR if is_relic else GameState.CACHE_COLOR
		var near := signal_pos != Vector2.INF and cell_center(i).distance_to(signal_pos) <= SIGNAL_R * CELL
		if not exposed and (near or i == hunt_cell):
			# 気配：マスの中心から広がって消える輪（マスごとに時間をずらす）
			var ph := fmod(_t * 0.6 + float(i % 97) * 0.13, 1.0)
			_marks.draw_arc(p, CELL * (0.3 + 1.6 * ph), 0.0, TAU, 24, Color(col, 0.55 * (1.0 - ph)), px * 1.5)
			_marks.draw_circle(p, px * 2.0, Color(col, 0.5 + 0.4 * blink))
		if i == hunt_cell:
			var hr := Rect2(p - Vector2(CELL, CELL), Vector2(CELL, CELL) * 2.0)
			_marks.draw_rect(hr, Color(col, 0.5 + 0.5 * blink), false, px * 1.5)
		if not see_all and not exposed:
			continue
		var a := (0.5 + 0.5 * blink) * (1.0 if exposed else 0.45)
		var r := Rect2(p - Vector2(CELL, CELL) * 0.5, Vector2(CELL, CELL)).grow(-px)
		_marks.draw_rect(r, Color(col, 0.18 * a))
		_marks.draw_rect(r, Color(Neon.glow(col), a * 0.4), false, px * 4.0)
		_marks.draw_rect(r, Color(col, a), false, px * 1.5)
		_marks.draw_line(r.position, r.end, Color(col, a * 0.8), px)
