class_name ZoneGen
extends RefCounted
## Генерация открытых зон: шум -> скалы/жижа -> заливка от спавна (всё
## недостижимое замуровываем) -> портал в самой дальней точке -> паки врагов.

const FLOOR := Zone.FLOOR
const ROCK := Zone.ROCK
const PIT := Zone.PIT
const HAZARD := Zone.HAZARD


static func generate(level: int, rng: RandomNumberGenerator) -> Dictionary:
	var biome: Dictionary = Biomes.for_level(level)
	if Game.is_boss_zone(level):
		return _gen_boss(level, rng, biome)
	for attempt in 6:
		var d := _try_gen(level, rng, biome, -1.0)
		if not d.is_empty():
			return d
	return _try_gen(level, rng, biome, 0.95)


static func _d(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a).distance_to(Vector2(b))


static func _walkable(v: int) -> bool:
	return v == FLOOR or v == HAZARD


static func _try_gen(level: int, rng: RandomNumberGenerator, biome: Dictionary, th_override: float) -> Dictionary:
	var size := 90 + mini(level, 30)
	var w := size
	var h := size
	var grid := PackedByteArray()
	grid.resize(w * h)
	grid.fill(FLOOR)

	var n1 := FastNoiseLite.new()
	n1.seed = rng.randi()
	n1.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n1.frequency = float(biome["freq"])
	n1.fractal_octaves = 3
	var n2 := FastNoiseLite.new()
	n2.seed = rng.randi()
	n2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n2.frequency = 0.035
	n2.fractal_octaves = 2

	var rock_th: float = biome["rock_th"] if th_override < 0.0 else th_override
	var pit_th: float = biome["pit_th"]
	var liquid: int = biome["liquid"]
	for y in h:
		for x in w:
			var i := y * w + x
			if x < 2 or y < 2 or x >= w - 2 or y >= h - 2:
				grid[i] = ROCK
				continue
			if n1.get_noise_2d(x, y) > rock_th:
				grid[i] = ROCK
			elif n2.get_noise_2d(x, y) > pit_th:
				grid[i] = liquid

	var style: String = biome["style"]
	if style == "ruins":
		_add_ruins(grid, w, h, rng)
	elif style == "scrap":
		_add_scrap(grid, w, h, rng)

	# Спавн у случайного края
	var side := rng.randi_range(0, 3)
	var along := rng.randi_range(12, size - 13)
	var sp: Vector2i
	match side:
		0:
			sp = Vector2i(7, along)
		1:
			sp = Vector2i(w - 8, along)
		2:
			sp = Vector2i(along, 7)
		_:
			sp = Vector2i(along, h - 8)
	_clear_circle(grid, w, h, sp, 5)

	# Заливка: всё недостижимое — в скалу
	var dist := _bfs(grid, w, h, sp)
	var reach := 0
	for i in w * h:
		if dist[i] < 0:
			if grid[i] == FLOOR or grid[i] == HAZARD:
				grid[i] = ROCK
		else:
			reach += 1
	# th_override >= 0.9 — аварийный режим, принимаем любую карту
	if reach < int(w * h * 0.33) and th_override < 0.9:
		return {}

	# Портал — в одной из самых дальних клеток
	var maxd := 0
	for i in w * h:
		if dist[i] > maxd and grid[i] == FLOOR:
			maxd = dist[i]
	var far: Array = []
	for i in w * h:
		if grid[i] == FLOOR and dist[i] >= int(maxd * 0.88):
			far.append(i)
	var pidx: int = far[rng.randi() % far.size()]
	var portal := Vector2i(pidx % w, pidx / w)
	_clear_circle(grid, w, h, portal, 2)

	# Кандидаты под паки врагов и сундуки
	var cands: Array = []
	for i in w * h:
		if grid[i] == FLOOR and dist[i] >= 14:
			cands.append(i)
	U.shuffle(cands, rng)

	var packs: Array = []
	var want := mini(20 + level, 42)
	for i in cands:
		if packs.size() >= want:
			break
		var c := Vector2i(int(i) % w, int(i) / w)
		if _d(c, portal) < 5.0:
			continue
		var ok := true
		for p in packs:
			if _d(c, p) < 8.0:
				ok = false
				break
		if ok:
			packs.append(c)

	var chests: Array = []
	var want_chests := rng.randi_range(3, 6)
	for k in range(cands.size() - 1, -1, -1):
		if chests.size() >= want_chests:
			break
		var i: int = cands[k]
		var c := Vector2i(i % w, i / w)
		if _d(c, portal) < 4.0:
			continue
		var ok := true
		for p in chests:
			if _d(c, p) < 16.0:
				ok = false
				break
		if ok:
			chests.append(c)

	return {"w": w, "h": h, "level": level, "grid": grid, "biome": biome, "boss": false,
		"spawn": sp, "portal": portal, "packs": packs, "chests": chests,
		"decor": _make_decor(grid, w, h, rng, 380)}


static func _gen_boss(level: int, rng: RandomNumberGenerator, biome: Dictionary) -> Dictionary:
	var w := 46
	var h := 46
	var grid := PackedByteArray()
	grid.resize(w * h)
	grid.fill(FLOOR)
	for y in h:
		for x in w:
			if x < 2 or y < 2 or x >= w - 2 or y >= h - 2:
				grid[y * w + x] = ROCK
	# Колонны-укрытия кольцом вокруг центра
	var center := Vector2(w * 0.5, h * 0.5)
	var n := 6 + rng.randi_range(0, 3)
	var off := rng.randf() * TAU
	for k in n:
		var p := center + Vector2.from_angle(off + TAU * float(k) / float(n)) * rng.randf_range(10.0, 15.0)
		var px := int(p.x)
		var py := int(p.y)
		for yy in range(py - 1, py + 1):
			for xx in range(px - 1, px + 1):
				if xx > 2 and yy > 2 and xx < w - 3 and yy < h - 3:
					grid[yy * w + xx] = ROCK
	var sp := Vector2i(w / 2, h - 7)
	_clear_circle(grid, w, h, sp, 3)
	return {"w": w, "h": h, "level": level, "grid": grid, "biome": biome, "boss": true,
		"spawn": sp, "boss_cell": Vector2i(w / 2, h / 2 - 4), "portal": Vector2i(-1, -1),
		"packs": [], "chests": [], "decor": _make_decor(grid, w, h, rng, 90)}


static func _clear_circle(grid: PackedByteArray, w: int, h: int, c: Vector2i, r: int) -> void:
	for y in range(c.y - r, c.y + r + 1):
		for x in range(c.x - r, c.x + r + 1):
			if x < 2 or y < 2 or x >= w - 2 or y >= h - 2:
				continue
			if (x - c.x) * (x - c.x) + (y - c.y) * (y - c.y) <= r * r:
				grid[y * w + x] = FLOOR


static func _bfs(grid: PackedByteArray, w: int, h: int, start: Vector2i) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(w * h)
	dist.fill(-1)
	var s := start.y * w + start.x
	dist[s] = 0
	var queue := PackedInt32Array([s])
	var head := 0
	while head < queue.size():
		var cur := queue[head]
		head += 1
		var cx := cur % w
		var cy := cur / w
		for k in 4:
			var nx := cx + (1 if k == 0 else (-1 if k == 1 else 0))
			var ny := cy + (1 if k == 2 else (-1 if k == 3 else 0))
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var ni := ny * w + nx
			if dist[ni] != -1 or not _walkable(grid[ni]):
				continue
			dist[ni] = dist[cur] + 1
			queue.append(ni)
	return dist


## Руины: прямоугольные «здания» с проломами.
static func _add_ruins(grid: PackedByteArray, w: int, h: int, rng: RandomNumberGenerator) -> void:
	for b in 26:
		var bw := rng.randi_range(6, 14)
		var bh := rng.randi_range(6, 12)
		var bx := rng.randi_range(4, w - bw - 5)
		var by := rng.randi_range(4, h - bh - 5)
		for y in range(by, by + bh):
			for x in range(bx, bx + bw):
				var edge := x == bx or y == by or x == bx + bw - 1 or y == by + bh - 1
				var i := y * w + x
				if edge:
					if rng.randf() < 0.8:
						grid[i] = ROCK
				else:
					grid[i] = FLOOR
		# двери
		for d in 3:
			var side := rng.randi_range(0, 3)
			var dx := bx + rng.randi_range(1, bw - 3)
			var dy := by + rng.randi_range(1, bh - 3)
			for k in 2:
				var x := dx + k
				var y := dy + k
				match side:
					0:
						y = by
					1:
						y = by + bh - 1
					2:
						x = bx
					_:
						x = bx + bw - 1
				grid[y * w + x] = FLOOR


## Свалка: кучи хлама.
static func _add_scrap(grid: PackedByteArray, w: int, h: int, rng: RandomNumberGenerator) -> void:
	for b in 140:
		var cx := rng.randi_range(4, w - 5)
		var cy := rng.randi_range(4, h - 5)
		var r := rng.randi_range(1, 2)
		for y in range(cy - r, cy + r + 1):
			for x in range(cx - r, cx + r + 1):
				if rng.randf() < 0.75:
					grid[y * w + x] = ROCK


static func _make_decor(grid: PackedByteArray, w: int, h: int, rng: RandomNumberGenerator, n: int) -> Array:
	var out: Array = []
	for i in n:
		var x := rng.randi_range(2, w - 3)
		var y := rng.randi_range(2, h - 3)
		if grid[y * w + x] != FLOOR:
			continue
		var p := Vector2((float(x) + rng.randf()) * Zone.T, (float(y) + rng.randf()) * Zone.T)
		out.append([p, rng.randi_range(0, 4), rng.randf_range(0.7, 1.3)])
	return out
