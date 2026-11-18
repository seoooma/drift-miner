class_name SectorGenerator
extends RefCounted
## シード値から小惑星帯を生成する。
## ノイズで密集地帯を作り、セクターの種類ごとに分布・資源・危険を変える。
## ゲートは「近いが平凡」「遠いが報酬が大きい」の2つを置き、行き先の種類を先に決めておく。

const TYPES := {
	"standard": {"name": "標準宙域", "desc": "", "tint": Color(1, 1, 1)},
	"ice_field": {"name": "氷原", "desc": "氷が多く、結晶が少ない", "tint": Color(0.6, 0.85, 1.0)},
	"nebula": {"name": "結晶星雲", "desc": "結晶が豊富。ただし視界が狭い", "tint": Color(0.9, 0.55, 1.0)},
	"sparse": {"name": "疎空域", "desc": "小惑星は少ないが大きい", "tint": Color(1.0, 0.9, 0.6)},
	"ring": {"name": "小惑星リング", "desc": "資源が環状に集まる", "tint": Color(0.7, 1.0, 0.7)},
	"radiation": {"name": "放射線帯", "desc": "放射線域が多い。結晶2倍", "tint": Color(1.0, 0.5, 0.45)},
}
const SAFE_TYPES := ["standard", "ice_field", "sparse", "ring"]
const RICH_TYPES := ["nebula", "radiation", "ring", "sparse"]


static func type_name(t: String) -> String:
	return String(TYPES[t]["name"])


static func generate(seed_value: int, sector: int, sector_type: String, world_radius: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = rng.randf_range(0.0009, 0.0018)

	var count_mult := 1.0
	var radius_mult := 1.0
	var ice_mult := 1.0
	var crystal_mult := 1.0
	var zone_count := 0 if sector <= 1 else rng.randi_range(1, 2)
	match sector_type:
		"ice_field":
			ice_mult = 2.2
			crystal_mult = 0.5
		"nebula":
			crystal_mult = 3.0
		"sparse":
			count_mult = 0.45
			radius_mult = 1.5
		"radiation":
			crystal_mult = 2.0
			zone_count = 5

	# 後半ほど氷（燃料）が乏しくなる
	var ice_chance := maxf(0.08, 0.22 - 0.012 * sector) * ice_mult
	var target_count := int(75.0 * count_mult)

	var asteroids: Array = []
	var attempts := 0
	while asteroids.size() < target_count and attempts < target_count * 60:
		attempts += 1
		var p := Vector2(rng.randf_range(-world_radius, world_radius), rng.randf_range(-world_radius, world_radius))
		var dist := p.length()
		if dist > world_radius or dist < 220.0:
			continue
		var density := (noise.get_noise_2dv(p) + 1.0) * 0.5
		if sector_type == "ring":
			density *= clampf(1.0 - absf(dist - world_radius * 0.55) / (world_radius * 0.18), 0.05, 1.0) * 1.6
		if rng.randf() > density * density * 1.8:
			continue
		var radius := rng.randf_range(18.0, 55.0) * radius_mult
		var overlaps := false
		for other in asteroids:
			if p.distance_to(other["pos"]) < radius + float(other["radius"]) + 18.0:
				overlaps = true
				break
		if overlaps:
			continue

		var depth := dist / world_radius
		var crystal_chance := (0.03 + depth * 0.12) * crystal_mult
		var roll := rng.randf()
		var kind := "iron"
		if roll < crystal_chance:
			kind = "crystal"
		elif roll < crystal_chance + ice_chance:
			kind = "ice"

		var amount := radius * rng.randf_range(1.4, 2.4)
		if kind == "crystal":
			amount *= 0.35
			radius *= 0.8

		asteroids.append({
			"pos": p,
			"radius": radius,
			"kind": kind,
			"amount": amount,
			"shape_seed": rng.randi(),
		})

	# ゲート：近い方（平凡）と遠い方（報酬大）。方向はずらす。
	var a1 := rng.randf() * TAU
	var a2 := a1 + rng.randf_range(PI * 0.6, PI * 1.4)
	var gates: Array = [
		{
			"pos": Vector2.from_angle(a1) * world_radius * rng.randf_range(0.42, 0.55),
			"next_type": SAFE_TYPES[rng.randi() % SAFE_TYPES.size()],
			"rich": false,
		},
		{
			"pos": Vector2.from_angle(a2) * world_radius * rng.randf_range(0.85, 0.93),
			"next_type": RICH_TYPES[rng.randi() % RICH_TYPES.size()],
			"rich": true,
		},
	]
	for g in gates:
		var gp: Vector2 = g["pos"]
		asteroids = asteroids.filter(func(a): return gp.distance_to(a["pos"]) > float(a["radius"]) + 120.0)

	# 放射線域：中にいると燃料消費が増える
	var zones: Array = []
	for i in zone_count:
		var zp := Vector2.from_angle(rng.randf() * TAU) * world_radius * rng.randf_range(0.3, 0.85)
		zones.append({"pos": zp, "radius": rng.randf_range(180.0, 320.0)})

	# 漂流物：中身はランダムの寄り道ポイント
	var derelicts: Array = []
	var d_count := rng.randi_range(2, 3)
	var tries := 0
	while derelicts.size() < d_count and tries < 200:
		tries += 1
		var dp := Vector2.from_angle(rng.randf() * TAU) * world_radius * rng.randf_range(0.35, 0.9)
		var ok := true
		for a in asteroids:
			if dp.distance_to(a["pos"]) < float(a["radius"]) + 40.0:
				ok = false
				break
		if ok:
			derelicts.append({"pos": dp, "roll": rng.randf()})

	return {"asteroids": asteroids, "gates": gates, "zones": zones, "derelicts": derelicts}
