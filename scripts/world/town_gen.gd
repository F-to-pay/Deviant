class_name TownGen
extends RefCounted
## Город между этапами: площадь с лавками, дома, улицы от входа к порталу.
## Вид зависит от следующей зоны: цвета — её биома, застройка — поле "town_style" биома:
##  plain — обычные дома и редкие камни, grid — кварталы по сетке, junk — дома и кучи хлама,
##  swamp — меньше домов, лужи. Имя — половинка из "town" биома + SUFFIXES; переводятся ключи
##  "Dust-" и "-ville" (в переводе дефисы тоже убираются: "Пыле-" + "-град" = «Пылеград»).
## Результат — тот же словарь, что у ZoneGen.generate (Zone.setup его ест), плюс:
##  "town": true, "stalls": [[вид лавки, клетка перед прилавком], ...], "name": имя города,
##  "center": клетка центра площади (в стартовом городе там камень перезапуска; на самой клетке может быть пруд или памятник);
##  "paved": клетки мостовой (1 — улица/площадь; рисует TerrainChunk). Пусто — генерация не удалась.

const FLOOR := Zone.FLOOR
const ROCK := Zone.ROCK
const PIT := Zone.PIT

const SUFFIXES := ["ville", "burg", "hole", "stead", "wick"]
## Виды лавок — см. Stall.KINDS. В стартовом городе (перед зоной 1) ещё три: выбор героя,
## реликвии (мета-перки) и настраиваемый старт.
const STALLS := ["shop", "perks", "workshop", "guild", "healer"]
const START_STALLS := ["heroes", "relics", "custom"]


static func generate(next_level: int, rng: RandomNumberGenerator) -> Dictionary:
	var biome: Dictionary = Biomes.for_level(next_level)
	var start := next_level == 1
	# неудача (лавки не встали) бывает в ~8% попыток, в стартовом городе с 7 лавками — в ~25%: пробуем ещё
	for attempt in 40:
		var d := _try(next_level, rng, biome, attempt >= 10, start)
		if not d.is_empty():
			return d
	return {}


## Имя города: половинка от биома + окончание.
static func make_name(biome: Dictionary, rng: RandomNumberGenerator) -> String:
	var parts: Array = biome.get("town", ["New"])
	var a := str(parts[rng.randi() % parts.size()])
	var b := str(SUFFIXES[rng.randi() % SUFFIXES.size()])
	# ключи перевода с дефисом ("Dust-", "-ville"), чтобы не путались с обычными словами
	return (U.t(a + "-") + U.t("-" + b)).replace("-", "")


## Рабочая карта города на время одной попытки генерации (не попадает в результат).
class _Plan extends RefCounted:
	var w := 0
	var h := 0
	var grid := PackedByteArray()
	var keep := PackedByteArray()     # что нельзя застраивать: 1 — улица, 2 — площадь
	var c := Vector2i.ZERO            # центр площади
	var pw := 0                       # полуширина и полувысота площади
	var ph := 0
	var sp := Vector2i.ZERO           # вход
	var pt := Vector2i.ZERO           # портал
	var stalls: Array = []            # [[вид лавки, клетка покупателя], ...]


## Одна попытка. Порядок бросков rng — часть результата (сид даёт тот же город), поэтому фазы идут строго в этом порядке.
## Пустой словарь — не вышло (лавки не влезли, портал или лавка недостижимы): вызывающий пробует снова.
## sparse — аварийный режим: почти без застройки (если площадь не уместила лавки).
## start — стартовый город: больше и площадь шире (7 лавок).
static func _try(next_level: int, rng: RandomNumberGenerator, biome: Dictionary, sparse: bool, start: bool) -> Dictionary:
	var t := _Plan.new()
	_init_map(t, rng, start)
	_lay_plaza(t, rng, start)
	_lay_gates_and_streets(t, rng)
	if not sparse:
		_build_houses(t, rng, str(biome.get("town_style", "plain")))
	_center_feature(t, rng)
	if not _place_stalls(t, rng, start):
		return {}
	return _finish(t, next_level, rng, biome)


## Размер, пол и скальная рамка в 2 клетки.
static func _init_map(t: _Plan, rng: RandomNumberGenerator, start: bool) -> void:
	t.w = rng.randi_range(54, 60) if start else rng.randi_range(46, 54)
	t.h = rng.randi_range(42, 46) if start else rng.randi_range(38, 44)
	t.grid.resize(t.w * t.h)
	t.grid.fill(FLOOR)
	for y in t.h:
		for x in t.w:
			if x < 2 or y < 2 or x >= t.w - 2 or y >= t.h - 2:
				t.grid[y * t.w + x] = ROCK
	t.keep.resize(t.w * t.h)
	t.keep.fill(0)


## Площадь — прямоугольник или овал около центра.
static func _lay_plaza(t: _Plan, rng: RandomNumberGenerator, start: bool) -> void:
	t.c = Vector2i(t.w / 2 + rng.randi_range(-3, 3), t.h / 2 + rng.randi_range(-2, 2))
	t.pw = rng.randi_range(12, 13) if start else rng.randi_range(8, 10)
	t.ph = rng.randi_range(8, 9) if start else rng.randi_range(6, 7)
	var oval := rng.randf() < 0.45
	for y in range(t.c.y - t.ph, t.c.y + t.ph + 1):
		for x in range(t.c.x - t.pw, t.c.x + t.pw + 1):
			if oval:
				var dx := float(x - t.c.x) / (float(t.pw) + 0.5)
				var dy := float(y - t.c.y) / (float(t.ph) + 0.5)
				if dx * dx + dy * dy > 1.0:
					continue
			t.keep[y * t.w + x] = 2


## Вход и портал — на противоположных краях; улицы: вход -> площадь -> портал, плюс 1–2 переулка в стороны.
static func _lay_gates_and_streets(t: _Plan, rng: RandomNumberGenerator) -> void:
	var w := t.w
	var h := t.h
	var c := t.c
	var side := rng.randi_range(0, 3)
	match side:
		0:
			t.sp = Vector2i(5, c.y + rng.randi_range(-4, 4))
			t.pt = Vector2i(w - 6, c.y + rng.randi_range(-4, 4))
		1:
			t.sp = Vector2i(w - 6, c.y + rng.randi_range(-4, 4))
			t.pt = Vector2i(5, c.y + rng.randi_range(-4, 4))
		2:
			t.sp = Vector2i(c.x + rng.randi_range(-6, 6), 5)
			t.pt = Vector2i(c.x + rng.randi_range(-6, 6), h - 6)
		_:
			t.sp = Vector2i(c.x + rng.randi_range(-6, 6), h - 6)
			t.pt = Vector2i(c.x + rng.randi_range(-6, 6), 5)
	_road(t.keep, w, h, t.sp, c, rng)
	_road(t.keep, w, h, c, t.pt, rng)
	for i in rng.randi_range(1, 2):
		var to := Vector2i(rng.randi_range(4, w - 5), rng.randi_range(4, h - 5))
		_road(t.keep, w, h, c, to, rng)


## Застройка по `town_style` биома: дома (в сетке — кварталами 7×6) и мелочь — камни, хлам, лужи.
static func _build_houses(t: _Plan, rng: RandomNumberGenerator, style: String) -> void:
	var w := t.w
	var h := t.h
	var grid := t.grid
	var want := 14 if style == "swamp" else rng.randi_range(24, 34)
	var placed := 0
	for i in 300:
		if placed >= want:
			break
		var bw := rng.randi_range(3, 6)
		var bh := rng.randi_range(3, 5)
		var bx := rng.randi_range(3, w - bw - 3)
		var by := rng.randi_range(3, h - bh - 3)
		if style == "grid":   # кварталы по сетке 7×6
			bx = clampi(3 + (bx / 7) * 7, 3, w - bw - 3)
			by = clampi(3 + (by / 6) * 6, 3, h - bh - 3)
			bw = 5
			bh = 4
		if _rect_free(grid, t.keep, w, bx - 1, by - 1, bw + 2, bh + 2):
			for y in range(by, by + bh):
				for x in range(bx, bx + bw):
					grid[y * w + x] = ROCK
			placed += 1
	# мелочь: камни, хлам, лужи
	var bits := 30 if style == "junk" else 10
	for i in bits:
		var x := rng.randi_range(3, w - 4)
		var y := rng.randi_range(3, h - 4)
		var r := 1 if style == "junk" else 0
		if not _rect_free(grid, t.keep, w, x - r - 1, y - r - 1, r * 2 + 3, r * 2 + 3):
			continue
		for yy in range(y - r, y + r + 1):
			for xx in range(x - r, x + r + 1):
				if style != "junk" or rng.randf() < 0.75:
					grid[yy * w + xx] = PIT if style == "swamp" else ROCK


## Посреди площади: пруд, памятник или ничего.
static func _center_feature(t: _Plan, rng: RandomNumberGenerator) -> void:
	var c := t.c
	var feature := rng.randi_range(0, 2)
	if feature == 0:
		for y in range(c.y - 1, c.y + 2):
			for x in range(c.x - 2, c.x + 3):
				if absi(x - c.x) + absi(y - c.y) <= 2:
					t.grid[y * t.w + x] = PIT
	elif feature == 1:
		for y in range(c.y - 1, c.y + 1):
			for x in range(c.x - 1, c.x + 1):
				t.grid[y * t.w + x] = ROCK


## Лавки: прилавок 3×2 клетки, лицом на юг; перед ним — клетка, где стоит покупатель. Кладёт их в t.stalls.
## false — не все лавки влезли на площадь.
static func _place_stalls(t: _Plan, rng: RandomNumberGenerator, start: bool) -> bool:
	var w := t.w
	var c := t.c
	var pw := t.pw
	var ph := t.ph
	var grid := t.grid
	var keep := t.keep
	var cands: Array = []
	for x in range(c.x - pw + 2, c.x + pw - 1):
		cands.append(Vector2i(x, c.y - ph + 3))
	for y in range(c.y - ph + 4, c.y + ph - 1):
		cands.append(Vector2i(c.x - pw + 2, y))
		cands.append(Vector2i(c.x + pw - 2, y))
	for x in range(c.x - pw + 2, c.x + pw - 1):   # нижний ряд площади
		cands.append(Vector2i(x, c.y + ph - 1))
	U.shuffle(cands, rng)
	var stalls: Array = []
	var kinds: Array = (START_STALLS + STALLS) if start else STALLS.duplicate()
	U.shuffle(kinds, rng)
	for o in cands:
		if stalls.size() >= kinds.size():
			break
		var f: Vector2i = o
		var ok := true
		for s in stalls:
			var fs: Vector2i = s[1]
			if Vector2(f).distance_to(Vector2(fs)) < 5.0:
				ok = false
				break
		# прилавок и место перед ним — на площади, не на улице и не на пруду/памятнике
		for y in range(f.y - 2, f.y + 2):
			for x in range(f.x - 1, f.x + 2):
				if keep[y * w + x] != 2 or grid[y * w + x] != FLOOR:
					ok = false
		if not ok:
			continue
		for y in range(f.y - 2, f.y):
			for x in range(f.x - 1, f.x + 2):
				grid[y * w + x] = ROCK
		stalls.append([kinds[stalls.size()], f])
	t.stalls = stalls
	return stalls.size() >= kinds.size()


## Недостижимое от входа — в камень (портал и лавки обязаны быть достижимы), мостовая на улицах и площади, итоговый словарь.
static func _finish(t: _Plan, next_level: int, rng: RandomNumberGenerator, biome: Dictionary) -> Dictionary:
	var w := t.w
	var h := t.h
	var grid := t.grid
	var sp := t.sp
	var pt := t.pt
	ZoneGen._clear_circle(grid, w, h, sp, 3)
	ZoneGen._clear_circle(grid, w, h, pt, 2)
	var dist := ZoneGen._bfs(grid, w, h, sp)
	if dist[pt.y * w + pt.x] < 0:
		return {}
	for s in t.stalls:
		var f: Vector2i = s[1]
		if dist[f.y * w + f.x] < 0:
			return {}
	# мостовая — на улицах и площади
	var paved := PackedByteArray()
	paved.resize(w * h)
	paved.fill(0)
	for i in w * h:
		if dist[i] < 0 and grid[i] == FLOOR:
			grid[i] = ROCK
		elif t.keep[i] != 0 and grid[i] == FLOOR:
			paved[i] = 1

	return {"paved": paved, "w": w, "h": h, "level": next_level, "grid": grid, "biome": biome, "boss": false, "town": true,
		"spawn": sp, "portal": pt, "center": t.c, "packs": [], "chests": [], "stalls": t.stalls, "name": make_name(biome, rng),
		"decor": ZoneGen._make_decor(grid, w, h, rng, 140)}


## Улица шириной 3 клетки буквой Г: сначала по одной оси, потом по другой (какой — случайно).
static func _road(keep: PackedByteArray, w: int, h: int, a: Vector2i, b: Vector2i, rng: RandomNumberGenerator) -> void:
	var mid := Vector2i(b.x, a.y) if rng.randf() < 0.5 else Vector2i(a.x, b.y)
	for seg in [[a, mid], [mid, b]]:
		var p: Vector2i = seg[0]
		var q: Vector2i = seg[1]
		for y in range(mini(p.y, q.y) - 1, maxi(p.y, q.y) + 2):
			for x in range(mini(p.x, q.x) - 1, maxi(p.x, q.x) + 2):
				if x >= 2 and y >= 2 and x < w - 2 and y < h - 2 and keep[y * w + x] == 0:
					keep[y * w + x] = 1


## Прямоугольник целиком свободен (пол, не улица/площадь, в границах).
static func _rect_free(grid: PackedByteArray, keep: PackedByteArray, w: int, x0: int, y0: int, rw: int, rh: int) -> bool:
	var h := grid.size() / w
	if x0 < 2 or y0 < 2 or x0 + rw > w - 2 or y0 + rh > h - 2:
		return false
	for y in range(y0, y0 + rh):
		for x in range(x0, x0 + rw):
			if keep[y * w + x] != 0 or grid[y * w + x] != FLOOR:
				return false
	return true
