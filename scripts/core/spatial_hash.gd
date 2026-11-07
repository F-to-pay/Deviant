class_name SpatialHash
extends RefCounted
## Пространственный хэш для быстрого поиска врагов рядом с точкой.
## Пересобирается каждый физический кадр (врагов в активной зоне — десятки).

var cell: float = 96.0
var _map: Dictionary = {}


func clear() -> void:
	_map.clear()


func insert(obj: Node2D) -> void:
	var k := Vector2i(floori(obj.position.x / cell), floori(obj.position.y / cell))
	if _map.has(k):
		_map[k].append(obj)
	else:
		_map[k] = [obj]


## Все объекты в клетках, задетых кругом. Точную дистанцию проверяет вызывающий.
func query(pos: Vector2, radius: float) -> Array:
	var out: Array = []
	var x0 := floori((pos.x - radius) / cell)
	var x1 := floori((pos.x + radius) / cell)
	var y0 := floori((pos.y - radius) / cell)
	var y1 := floori((pos.y + radius) / cell)
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			var k := Vector2i(x, y)
			if _map.has(k):
				out.append_array(_map[k])
	return out
