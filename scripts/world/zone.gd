class_name Zone
extends Node2D
## Открытая зона на клеточной сетке: коллизии кругов, лучи видимости,
## поле потока для навигации врагов, туман для миникарты.

const T := 40.0
const FLOOR := 0
const ROCK := 1
const PIT := 2
const HAZARD := 3
const CHUNK := 16

var w: int = 0
var h: int = 0
var level: int = 1
var grid: PackedByteArray
var explored: PackedByteArray
var _astar := {}             # класс размера -> AStarGrid2D (см. find_path)
var biome: Dictionary = {}
var decor: Array = []
var chunks: Array = []
var minimap_img: Image
var minimap_tex: ImageTexture
var anim_t := 0.0


func setup(data: Dictionary) -> void:
	w = data["w"]
	h = data["h"]
	level = data["level"]
	grid = data["grid"]
	biome = data["biome"]
	decor = data["decor"]
	explored = PackedByteArray()
	explored.resize(w * h)
	explored.fill(0)
	_build_paths()
	for c in chunks:
		c.queue_free()
	chunks.clear()
	for cy in range(0, h, CHUNK):
		for cx in range(0, w, CHUNK):
			var ch := TerrainChunk.new()
			ch.zone = self
			ch.x0 = cx
			ch.y0 = cy
			ch.x1 = mini(cx + CHUNK, w)
			ch.y1 = mini(cy + CHUNK, h)
			add_child(ch)
			chunks.append(ch)
	minimap_img = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	minimap_img.fill(Color(0, 0, 0, 0))
	minimap_tex = ImageTexture.create_from_image(minimap_img)
	queue_redraw()


func _draw() -> void:
	if w == 0:
		return
	# Пол одним прямоугольником — чанки рисуют поверх только «рельеф».
	draw_rect(Rect2(0, 0, w * T, h * T), biome["floor"])


# --- Сетка ----------------------------------------------------------------------

func in_bounds(cx: int, cy: int) -> bool:
	return cx >= 0 and cy >= 0 and cx < w and cy < h


func idx(cx: int, cy: int) -> int:
	return cy * w + cx


func get_cell(cx: int, cy: int) -> int:
	if cx < 0 or cy < 0 or cx >= w or cy >= h:
		return ROCK
	return grid[cy * w + cx]


func cell_at(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / T), floori(p.y / T))


func cell_center(c: Vector2i) -> Vector2:
	return Vector2((float(c.x) + 0.5) * T, (float(c.y) + 0.5) * T)


func world_size() -> Vector2:
	return Vector2(w * T, h * T)


func blocks_move_cell(cx: int, cy: int) -> bool:
	var v := get_cell(cx, cy)
	return v == ROCK or v == PIT


func blocks_shot_at(p: Vector2) -> bool:
	return get_cell(floori(p.x / T), floori(p.y / T)) == ROCK


func is_hazard_at(p: Vector2) -> bool:
	return get_cell(floori(p.x / T), floori(p.y / T)) == HAZARD


# --- Коллизии ---------------------------------------------------------------------

func circle_blocked(p: Vector2, r: float) -> bool:
	var x0 := floori((p.x - r) / T)
	var x1 := floori((p.x + r) / T)
	var y0 := floori((p.y - r) / T)
	var y1 := floori((p.y + r) / T)
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			if blocks_move_cell(cx, cy):
				var nx := clampf(p.x, cx * T, (cx + 1) * T)
				var ny := clampf(p.y, cy * T, (cy + 1) * T)
				var dx := p.x - nx
				var dy := p.y - ny
				if dx * dx + dy * dy < r * r:
					return true
	return false


## Двигает круг с раздельными осями — скольжение вдоль стен.
func move_circle(p: Vector2, motion: Vector2, r: float) -> Vector2:
	if motion.length_squared() < 0.0001:
		return p
	if circle_blocked(p, r):
		return p + motion  # застряли — выпускаем, пусть выберется
	var steps := maxi(1, ceili(motion.length() / 6.0))
	var step := motion / float(steps)
	var cur := p
	for i in steps:
		var nx := Vector2(cur.x + step.x, cur.y)
		if not circle_blocked(nx, r):
			cur = nx
		var ny := Vector2(cur.x, cur.y + step.y)
		if not circle_blocked(ny, r):
			cur = ny
	return cur


## Прямая видимость. for_move = ещё и пропасти считаются преградой.
## r > 0 (для движения): «толстый» луч — ещё два по краям тела, чтобы не тереться об углы.
func ray_clear(a: Vector2, b: Vector2, for_move: bool = false, r: float = 0.0) -> bool:
	var d := b - a
	var dist := d.length()
	if dist < 1.0:
		return true
	if r > 0.0:
		var side := d.orthogonal().normalized() * r * 0.9
		if not ray_clear(a + side, b + side, for_move) or not ray_clear(a - side, b - side, for_move):
			return false
	var n := ceili(dist / (T * 0.5))
	for i in range(1, n):
		var p := a + d * (float(i) / float(n))
		var v := get_cell(floori(p.x / T), floori(p.y / T))
		if v == ROCK or (for_move and v == PIT):
			return false
	return true


func random_free_near(p: Vector2, rmin: float, rmax: float) -> Vector2:
	for i in 30:
		var q := p + Vector2.from_angle(randf() * TAU) * lerpf(rmin, rmax, randf())
		var c := cell_at(q)
		if get_cell(c.x, c.y) == FLOOR and not circle_blocked(q, 18.0):
			return q
	return p


# --- Поиск пути (AStarGrid2D) -------------------------------------------------------
## Враги ходят по A* (движок, C++). Сетки — по «размеру» врага: класс k = сколько клеток в ширину
## ему нужно (тело диаметром до k·T). Для класса k клетка проходима, если свободен блок k×k,
## начинающийся с неё; центр врага на пути — центр этого блока. Так громила не лезет в щель в 1 клетку.
## Класс 1 и 2 строятся при загрузке зоны, 3 (босс) — при первом запросе.

const PATH_CLASS_MAX := 3


## Класс размера по радиусу: сколько клеток нужно телу в ширину.
static func size_class(r: float) -> int:
	return clampi(ceili((r * 2.0 + 2.0) / T), 1, PATH_CLASS_MAX)


func _build_paths() -> void:
	_astar.clear()
	for k in [1, 2]:
		_astar[k] = _make_astar(k)


func _make_astar(k: int) -> AStarGrid2D:
	var g := AStarGrid2D.new()
	g.region = Rect2i(0, 0, w, h)
	g.cell_size = Vector2(T, T)
	g.offset = Vector2(T * 0.5 * float(k), T * 0.5 * float(k))
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.update()
	for cy in h:
		for cx in w:
			if not _block_free(cx, cy, k):
				g.set_point_solid(Vector2i(cx, cy), true)
	return g


func _block_free(cx: int, cy: int, k: int) -> bool:
	if cx + k > w or cy + k > h:
		return false
	for dy in k:
		for dx in k:
			if blocks_move_cell(cx + dx, cy + dy):
				return false
	return true


## Ближайшая проходимая клетка сетки k к точке (поиск по расширяющимся кольцам).
func _nearest_open(g: AStarGrid2D, p: Vector2, k: int) -> Vector2i:
	var c := cell_at(p - Vector2(T * 0.5 * float(k - 1), T * 0.5 * float(k - 1)))
	for r in 4:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var q := Vector2i(c.x + dx, c.y + dy)
				if g.is_in_boundsv(q) and not g.is_point_solid(q):
					return q
	return Vector2i(-1, -1)


## Путь из точки from к точке to для тела радиусом r: точки центров (мировые координаты),
## первая — где стоишь. Цель недостижима — путь до ближайшего к ней места. Пусто — пути нет.
func find_path(from: Vector2, to: Vector2, r: float) -> PackedVector2Array:
	var k := size_class(r)
	if not _astar.has(k):
		_astar[k] = _make_astar(k)
	var g: AStarGrid2D = _astar[k]
	var a := _nearest_open(g, from, k)
	var b := _nearest_open(g, to, k)
	if a.x < 0 or b.x < 0:
		return PackedVector2Array()
	return g.get_point_path(a, b, true)


# --- Миникарта ----------------------------------------------------------------------

func explore(p: Vector2, r: int) -> void:
	var c := cell_at(p)
	var changed := false
	var r2 := r * r
	for y in range(maxi(0, c.y - r), mini(h, c.y + r + 1)):
		for x in range(maxi(0, c.x - r), mini(w, c.x + r + 1)):
			var dx := x - c.x
			var dy := y - c.y
			if dx * dx + dy * dy > r2:
				continue
			var i := y * w + x
			if explored[i] == 0:
				explored[i] = 1
				minimap_img.set_pixel(x, y, _mini_color(grid[i]))
				changed = true
	if changed:
		minimap_tex.update(minimap_img)


func is_explored(p: Vector2) -> bool:
	var c := cell_at(p)
	if not in_bounds(c.x, c.y):
		return false
	return explored[idx(c.x, c.y)] == 1


func _mini_color(v: int) -> Color:
	var col: Color
	if v == ROCK:
		col = biome["rock_top"]
	elif v == PIT:
		col = Color(biome["liq"]).lightened(0.05)
	elif v == HAZARD:
		col = biome["liq"]
	else:
		col = Color(biome["floor"]).lightened(0.12)
	col.a = 0.9
	return col
