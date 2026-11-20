class_name ProceduralZoneSource
extends ZoneSource
## Процедурные зоны и города: `ZoneGen` и `TownGen` (сид забега даёт ту же карту).


func zone(level: int, rng: RandomNumberGenerator) -> Dictionary:
	return ZoneGen.generate(level, rng)


func town(next_level: int, rng: RandomNumberGenerator) -> Dictionary:
	return TownGen.generate(next_level, rng)
