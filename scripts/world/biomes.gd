class_name Biomes
extends RefCounted
## Биомы зон. liquid: 2 = пропасть/вода (непроходимо, но пули летят),
## 3 = опасная жижа (проходимо, жжёт). style: noise / ruins / scrap.

const LIST := [
	{"name": "Пыльная пустошь", "floor": Color(0.34, 0.29, 0.22), "floor2": Color(0.39, 0.33, 0.25),
		"rock": Color(0.5, 0.39, 0.28), "rock_top": Color(0.64, 0.52, 0.38),
		"liquid": 2, "liq": Color(0.07, 0.05, 0.04), "liq2": Color(0.16, 0.12, 0.09),
		"deco": Color(0.5, 0.45, 0.36), "rock_th": 0.3, "pit_th": 0.45, "freq": 0.05, "style": "noise", "hazard_el": -1},
	{"name": "Токсичные топи", "floor": Color(0.16, 0.21, 0.14), "floor2": Color(0.19, 0.25, 0.16),
		"rock": Color(0.26, 0.31, 0.2), "rock_top": Color(0.38, 0.45, 0.27),
		"liquid": 3, "liq": Color(0.32, 0.7, 0.12), "liq2": Color(0.5, 0.9, 0.25),
		"deco": Color(0.35, 0.5, 0.25), "rock_th": 0.34, "pit_th": 0.3, "freq": 0.055, "style": "noise", "hazard_el": 2},
	{"name": "Ледяная равнина", "floor": Color(0.58, 0.66, 0.74), "floor2": Color(0.64, 0.72, 0.8),
		"rock": Color(0.33, 0.43, 0.58), "rock_top": Color(0.78, 0.87, 0.96),
		"liquid": 2, "liq": Color(0.08, 0.17, 0.3), "liq2": Color(0.2, 0.35, 0.5),
		"deco": Color(0.85, 0.92, 1.0), "rock_th": 0.32, "pit_th": 0.4, "freq": 0.045, "style": "noise", "hazard_el": -1},
	{"name": "Лавовые поля", "floor": Color(0.17, 0.12, 0.11), "floor2": Color(0.21, 0.14, 0.12),
		"rock": Color(0.29, 0.21, 0.19), "rock_top": Color(0.42, 0.3, 0.26),
		"liquid": 3, "liq": Color(0.95, 0.38, 0.05), "liq2": Color(1.0, 0.7, 0.2),
		"deco": Color(0.5, 0.25, 0.15), "rock_th": 0.33, "pit_th": 0.36, "freq": 0.05, "style": "noise", "hazard_el": 0},
	{"name": "Неоновые руины", "floor": Color(0.09, 0.07, 0.14), "floor2": Color(0.12, 0.09, 0.19),
		"rock": Color(0.2, 0.14, 0.32), "rock_top": Color(0.85, 0.3, 0.95),
		"liquid": 2, "liq": Color(0.01, 0.0, 0.04), "liq2": Color(0.3, 0.1, 0.5),
		"deco": Color(0.3, 0.8, 0.95), "rock_th": 0.55, "pit_th": 0.5, "freq": 0.04, "style": "ruins", "hazard_el": -1},
	{"name": "Ржавая свалка", "floor": Color(0.24, 0.21, 0.19), "floor2": Color(0.28, 0.24, 0.21),
		"rock": Color(0.45, 0.28, 0.18), "rock_top": Color(0.6, 0.4, 0.26),
		"liquid": 2, "liq": Color(0.05, 0.05, 0.06), "liq2": Color(0.18, 0.16, 0.2),
		"deco": Color(0.55, 0.5, 0.45), "rock_th": 0.42, "pit_th": 0.47, "freq": 0.06, "style": "scrap", "hazard_el": -1},
]


static func for_level(level: int) -> Dictionary:
	if level == 1:
		return LIST[0]
	return LIST[(level - 1 + Game.biome_offset) % LIST.size()]
