class_name SectorGenerator
extends RefCounted
## シード値から小惑星帯を生成する。ノイズで密集地帯（小惑星帯）を作り、
## 中心から離れるほど・セクターが進むほどレア鉱石（結晶）が出やすくなる。


static func generate(seed_value: int, sector: int, world_radius: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.0012

	var asteroids: Array = []
	var target_count: int = 70 + sector * 8
	var attempts: int = 0
	while asteroids.size() < target_count and attempts < target_count * 40:
		attempts += 1
		var p := Vector2(rng.randf_range(-world_radius, world_radius), rng.randf_range(-world_radius, world_radius))
		var dist := p.length()
		if dist > world_radius or dist < 220.0:
			continue
		# ノイズ値が高い場所ほど置かれやすい → 帯状・塊状の分布になる
		var density := (noise.get_noise_2dv(p) + 1.0) * 0.5
		if rng.randf() > density * density * 1.8:
			continue
		var radius := rng.randf_range(18.0, 55.0)
		var overlaps := false
		for other in asteroids:
			if p.distance_to(other["pos"]) < radius + float(other["radius"]) + 18.0:
				overlaps = true
				break
		if overlaps:
			continue

		var depth := dist / world_radius
		var crystal_chance := 0.03 + sector * 0.015 + depth * 0.08
		var roll := rng.randf()
		var kind := "iron"
		if roll < crystal_chance:
			kind = "crystal"
		elif roll < crystal_chance + 0.22:
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

	var gate_angle := rng.randf() * TAU
	var gate_pos := Vector2.from_angle(gate_angle) * world_radius * rng.randf_range(0.7, 0.9)
	# ゲート周辺の小惑星は取り除く
	asteroids = asteroids.filter(func(a): return gate_pos.distance_to(a["pos"]) > float(a["radius"]) + 120.0)

	return {"asteroids": asteroids, "gate": gate_pos}
