class_name Planet
extends Node2D
## 巨大なピクセル惑星。マスごとに耐久とブロックの種類を持ち、削られると欠けていく。
## 形・地殻の色・鉱脈・遺物や宝箱の位置はシードと惑星の特性から毎回ランダムに作る。
## 深いマスほど指数的に硬く、価値も高い。

signal cell_broken(world_pos: Vector2, value: float, block: int)
signal cleared

const CELL := 8.0
const RADIUS := 56

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
var _t: float = 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func generate(seed_value: int, trait_rates: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	radius_cells = RADIUS
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

	var hue := rng.randf()
	var crust := Color.from_hsv(hue, rng.randf_range(0.35, 0.55), rng.randf_range(0.42, 0.55))
	var mantle := Color.from_hsv(fmod(hue + rng.randf_range(0.04, 0.12), 1.0), 0.5, 0.3)
	var deep := Color.from_hsv(fmod(hue + 0.08, 1.0), 0.6, 0.18)
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
			if dp > 0.9:
				b = GameState.B.CORE
			elif roll < 0.0012 * r_relic * (0.5 + dp):
				b = GameState.B.RELIC
			elif roll < 0.0012 * r_relic * (0.5 + dp) + 0.0035 * r_cache:
				b = GameState.B.CACHE
			elif roll < 0.006 * r_vol + 0.0047:
				b = GameState.B.VOLATILE
			elif v > 0.42 and dp > 0.35 and rng.randf() < 0.5 * r_cr:
				b = GameState.B.CRYSTAL
			elif v2 > 0.38 and rng.randf() < 0.55 * r_au * (0.4 + dp):
				b = GameState.B.GOLD
			elif v > 0.2 and rng.randf() < 0.6 * r_cu:
				b = GameState.B.COPPER
			elif v2 < -0.25 and rng.randf() < 0.7 * r_iron:
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


func _cell_color(b: int, dp: float, crust: Color, mantle: Color, deep: Color, rng: RandomNumberGenerator) -> Color:
	var c: Color
	if b == GameState.B.ROCK or b == GameState.B.RELIC or b == GameState.B.CACHE:
		# 遺物と宝箱は見た目では岩と区別できない（掘り当てるまで分からない）
		c = crust.lerp(mantle, smoothstep(0.05, 0.4, dp)).lerp(deep, smoothstep(0.45, 0.9, dp))
	else:
		c = GameState.BLOCK_COLORS[b]
		c = c.darkened(0.1 + dp * 0.25)
	return c.darkened(rng.randf_range(0.0, 0.1))


func _redraw_all() -> void:
	for y in size:
		for x in size:
			var i := y * size + x
			if hp[i] <= 0.0:
				_img.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				var k := 1.0 - hp[i] / max_hp[i]
				_img.set_pixel(x, y, _base_colors[i].lerp(Color(1, 0.95, 0.85), k * 0.45))
	if _tex == null:
		_tex = ImageTexture.create_from_image(_img)
	else:
		_tex.update(_img)
	queue_redraw()


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
		var v := GameState.cell_value(depth[i]) * float(GameState.BLOCKS[b]["value"])
		cell_broken.emit(cell_center(i), v, b)
		if b == GameState.B.VOLATILE:
			_explode(i)
		if broken() >= needed() and not done:
			done = true
			cleared.emit()
		return true
	var k := 1.0 - hp[i] / max_hp[i]
	_img.set_pixel(x, y, _base_colors[i].lerp(Color(1, 0.95, 0.85), k * 0.45))
	_dirty = true
	return false


## 爆薬岩：周りのマスに大きなダメージ（連鎖する）
func _explode(i: int) -> void:
	var lv := GameState.skill_level("blast")
	var r := CELL * (2.5 + 0.5 * lv)
	var dmg := max_hp[i] * 5.0 * (1.0 + 0.5 * lv)
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
				hit(j, dmg)
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
			scored.append([priority(i) * 3.0 - d * dist_w - depth[i] * 80.0, i])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	var out: Array = []
	for e in scored:
		out.append(e[1])
	return out


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
	_outer_t -= delta
	if _outer_t <= 0.0:
		_outer_t = 1.0
		_update_outer()
	if _dirty:
		_dirty = false
		_tex.update(_img)
	queue_redraw()


func _draw() -> void:
	if _tex == null:
		return
	for k in 6:
		draw_circle(Vector2.ZERO, outer + 8.0 + k * 9.0, Color(_glow, 0.03))
	var half := (size * CELL) * 0.5
	draw_texture_rect(_tex, Rect2(-half, -half, size * CELL, size * CELL), false)
	# 表面に出てきた遺物・宝箱は光る（透視スキャンがあれば埋まっていても見える）
	var see_all := GameState.skill_level("vision") > 0
	var blink := 0.5 + 0.5 * sin(_t * 5.0)
	for i in buried:
		if hp[i] <= 0.0:
			continue
		if not see_all and not is_exposed(i):
			continue
		var p := cell_center(i) - position
		var is_relic: bool = int(block[i]) == GameState.B.RELIC
		var col := Color(0.4, 1.0, 0.9) if is_relic else Color(1.0, 0.85, 0.3)
		draw_rect(Rect2(p - Vector2(CELL, CELL) * 0.5, Vector2(CELL, CELL)), Color(col, 0.35 + 0.5 * blink))
		draw_rect(Rect2(p - Vector2(CELL, CELL) * 0.5, Vector2(CELL, CELL)), col, false, 1.5)
