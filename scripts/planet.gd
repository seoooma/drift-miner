class_name Planet
extends Node2D
## ピクセルの惑星。マス目ごとに耐久と鉱石の種類を持ち、削られると欠けていく。
## 形・地殻の色・鉱脈の配置はシードから毎回ランダムに作る。

signal cell_broken(world_pos: Vector2, value: float, ore: int)
signal cleared

const CELL := 8.0

var radius_cells: int = 22
var size: int = 0
var hp := PackedFloat32Array()
var max_hp := PackedFloat32Array()
var ore := PackedByteArray()
var alive_count: int = 0
var total_cells: int = 0
var done: bool = false

var _img: Image
var _tex: ImageTexture
var _base_colors := PackedColorArray()
var _dirty := false
var _crust := Color.WHITE
var _mantle := Color.WHITE
var _glow := Color.WHITE


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func generate(seed_value: int, boss: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	radius_cells = 27 if boss else rng.randi_range(19, 23)
	size = radius_cells * 2 + 1
	var n := size * size
	hp.resize(n)
	max_hp.resize(n)
	ore.resize(n)
	_base_colors.resize(n)
	alive_count = 0
	done = false

	var hue := rng.randf()
	_crust = Color.from_hsv(hue, rng.randf_range(0.35, 0.6), rng.randf_range(0.45, 0.6))
	_mantle = Color.from_hsv(fmod(hue + rng.randf_range(0.05, 0.15), 1.0), 0.45, 0.32)
	_glow = Color.from_hsv(fmod(hue + 0.5, 1.0), 0.6, 1.0)

	var shape := FastNoiseLite.new()
	shape.seed = seed_value
	shape.frequency = 0.9
	var veins := FastNoiseLite.new()
	veins.seed = seed_value + 11
	veins.frequency = 0.12
	var rich := 1.6 if GameState.rich_ores() else 1.0
	var base_hp := GameState.cell_hp()
	for y in size:
		for x in size:
			var i := y * size + x
			var d := Vector2(x - radius_cells, y - radius_cells)
			var ang := d.angle()
			# 外周を少しでこぼこにする
			var edge := radius_cells - 0.5 + shape.get_noise_2d(cos(ang) * 2.0, sin(ang) * 2.0) * 2.2
			var r := d.length()
			if r > edge:
				hp[i] = 0.0
				max_hp[i] = 0.0
				ore[i] = 255
				continue
			var depth := r / edge
			var o := 0
			var v := veins.get_noise_2d(x, y)
			if depth < 0.2:
				o = 5
			elif v > 0.5 - 0.06 * (rich - 1.0) and depth < 0.8 and rng.randf() < 0.45 * rich:
				o = 4
			elif v > 0.4 and rng.randf() < 0.6 * rich:
				o = 3
			elif v > 0.3:
				o = 2
			elif v < -0.38:
				o = 1
			ore[i] = o
			var h := base_hp * float(GameState.ORES[o]["hp"]) * (1.0 + (1.0 - depth) * 0.6)
			hp[i] = h
			max_hp[i] = h
			_base_colors[i] = _cell_color(o, depth, rng)
			alive_count += 1
	total_cells = alive_count

	_img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var i := y * size + x
			_img.set_pixel(x, y, _base_colors[i] if hp[i] > 0.0 else Color(0, 0, 0, 0))
	_tex = ImageTexture.create_from_image(_img)
	queue_redraw()


func _cell_color(o: int, depth: float, rng: RandomNumberGenerator) -> Color:
	var c: Color
	if o == 0:
		c = _crust.lerp(_mantle, smoothstep(0.55, 0.95, 1.0 - depth))
	else:
		c = GameState.ORE_COLORS[o]
		c = c.darkened(0.15)
	return c.darkened(rng.randf_range(0.0, 0.12))


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


func progress() -> float:
	if total_cells == 0:
		return 1.0
	return float(total_cells - alive_count) / float(total_cells)


func needed() -> int:
	return int(ceil(total_cells * GameState.clear_ratio()))


func broken() -> int:
	return total_cells - alive_count


## from から to へ進んで最初に当たる生きたマス（なければ -1）
func raycast(from: Vector2, to: Vector2) -> int:
	var dist := from.distance_to(to)
	var steps := int(dist / (CELL * 0.5)) + 1
	for s in steps + 1:
		var p := from.lerp(to, float(s) / steps)
		var i := cell_at(p)
		if is_alive(i):
			return i
	return -1


## 外から中心へ向かって、指定の角度で最初に当たる表面のマス。
func surface_cell(angle: float) -> int:
	var from := position + Vector2.from_angle(angle) * (world_radius() + CELL * 4.0)
	return raycast(from, position)


func random_surface_cell() -> int:
	for k in 6:
		var i := surface_cell(randf() * TAU)
		if i >= 0:
			return i
	return -1


## マス i に damage を与える。砕けたら true。
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
		var o := int(ore[i])
		var v := GameState.cell_value() * float(GameState.ORES[o]["value"])
		cell_broken.emit(cell_center(i), v, o)
		if broken() >= needed():
			done = true
			cleared.emit()
		return true
	# ひび：耐久が減るほど明るく
	var k := 1.0 - hp[i] / max_hp[i]
	_img.set_pixel(x, y, _base_colors[i].lerp(Color(1, 0.95, 0.85), k * 0.45))
	_dirty = true
	return false


## 半径 r（ワールド単位）内の生きたマスに damage を分けて与える。
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
			if is_alive(i) and cell_center(i).distance_to(center) <= r:
				cells.append(i)
	if cells.is_empty():
		return
	var each := damage / cells.size()
	for i in cells:
		hit(i, each)


## 残りのマスの価値の合計（割れたときのボーナスに使う）
func remaining_value() -> float:
	var s := 0.0
	for i in hp.size():
		if hp[i] > 0.0:
			s += GameState.cell_value() * float(GameState.ORES[int(ore[i])]["value"])
	return s


func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		_tex.update(_img)
		queue_redraw()


func _draw() -> void:
	if _tex == null:
		return
	var r := world_radius()
	# 大気の光
	for k in 5:
		draw_circle(Vector2.ZERO, r + 10.0 + k * 7.0, Color(_glow, 0.035))
	var half := (size * CELL) * 0.5
	draw_texture_rect(_tex, Rect2(-half, -half, size * CELL, size * CELL), false)
