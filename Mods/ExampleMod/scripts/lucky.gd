extends RefCounted
## Скрипт перка "Lucky" из примера. Игра вызывает apply(gun, rng) при выдаче перка.
## gun — объект Gun (свойства — см. scripts/weapons/gun.gd), rng — генератор случайных чисел пушки.

func apply(g, rng) -> void:
	g.crit_chance += 0.15
	g.crit_mult += rng.randf_range(0.2, 1.0)
