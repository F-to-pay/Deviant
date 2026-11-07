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
var flow: PackedInt32Array
var _flow_touched: PackedInt32Array
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
	flow = PackedInt32Array()
	flow.resize(w * h)
	flow.fill(-1)
	_flow_touched = PackedInt32Array()
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
func ray_clear(a: Vector2, b: Vector2, for_move: bool = false) -> bool:
	var d := b - a
	var dist := d.length()
	if dist < 1.0:
		return true
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


# --- Поле потока (BFS от игрока) ---------------------------------------------------

@warning_ignore("integer_division")
func update_flow(target: Vector2, max_dist: int = 32) -> void:
	for i in _flow_touched:
		flow[i] = -1
	_flow_touched.resize(0)
	var c := cell_at(target)
	if not in_bounds(c.x, c.y):
		return
	var start := idx(c.x, c.y)
	var queue := PackedInt32Array([start])
	flow[start] = 0
	_flow_touched.append(start)
	var head := 0
	while head < queue.size():
		var cur := queue[head]
		head += 1
		var d := flow[cur]
		if d >= max_dist:
			continue
		var cx := cur % w
		var cy := cur / w
		for k in 4:
			var nx := cx
			var ny := cy
			if k == 0:
				nx += 1
			elif k == 1:
				nx -= 1
			elif k == 2:
				ny += 1
			else:
				ny -= 1
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var ni := ny * w + nx
			if flow[ni] != -1:
				continue
			var v := grid[ni]
			if v == ROCK or v == PIT:
				continue
			flow[ni] = d + 1
			queue.append(ni)
			_flow_touched.append(ni)


## Направление «вниз по полю» к игроку. ZERO — если вне поля.
func flow_dir(p: Vector2) -> Vector2:
	var c := cell_at(p)
	if not in_bounds(c.x, c.y):
		return Vector2.ZERO
	var cur := flow[idx(c.x, c.y)]
	if cur < 0:
		return Vector2.ZERO
	var best := cur
	var best_c := c
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nx := c.x + dx
			var ny := c.y + dy
			if not in_bounds(nx, ny) or blocks_move_cell(nx, ny):
				continue
			if dx != 0 and dy != 0 and (blocks_move_cell(c.x + dx, c.y) or blocks_move_cell(c.x, c.y + dy)):
				continue
			var v := flow[idx(nx, ny)]
			if v >= 0 and v < best:
				best = v
				best_c = Vector2i(nx, ny)
	if best_c == c:
		return Vector2.ZERO
	return (cell_center(best_c) - p).normalized()


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
