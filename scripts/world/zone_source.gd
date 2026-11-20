class_name ZoneSource
extends RefCounted
## Откуда берутся данные зон и городов. Метод возвращает словарь, который ест `Zone.setup` (формат — см. `ZoneGen.generate`:
## w, h, level, grid, biome, boss, spawn, portal, packs, chests, decor, ...; у города ещё town, stalls, paved, name).
## Пустой словарь — не вышло. Источник по умолчанию — процедурная генерация (`ProceduralZoneSource`); карты редактора и
## постоянный мир «Диаблоида» — наследники с теми же двумя методами, подставляются в `ZoneLoader.source`.


## Обычная или боссовая зона уровня level.
func zone(_level: int, _rng: RandomNumberGenerator) -> Dictionary:
	return {}


## Город перед зоной next_level.
func town(_next_level: int, _rng: RandomNumberGenerator) -> Dictionary:
	return {}
