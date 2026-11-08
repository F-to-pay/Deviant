class_name GunPreview
extends Control
## Карточка пушки внутри экранов меню (лавки): та же GunCard, что и в игре, со сравнением.

var gun: Gun = null
var cmp: Gun = null


func _init() -> void:
	custom_minimum_size = Vector2(GunCard.W, 600)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_gun(g: Gun, compare: Gun = null) -> void:
	gun = g
	cmp = compare
	if g != null:
		custom_minimum_size.y = maxf(600.0, GunCard.height(g))
	queue_redraw()


func _draw() -> void:
	if gun != null:
		GunCard.draw_card(self, gun, Vector2.ZERO, cmp)
