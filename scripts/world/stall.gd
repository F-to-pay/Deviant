class_name Stall
extends Node2D
## Лавка в городе: прилавок 3×2 клетки (в сетке зоны — камень), торговец за ним.
## Позиция узла — клетка перед прилавком, где стоит игрок. [interact] рядом — окно лавки (HUD).
## Лавка с "menu" открывает экран меню (Menu.open_town) — торговля, герои, задания;
## без "menu" — окно-заглушка в HUD с репликой и списком того, что тут будет ("soon").
## heroes, relics, custom — только в стартовом городе (TownGen.START_STALLS).

## title — вывеска, lines — реплики торговца (случайная при каждом разговоре, видна и на экране лавки).
const KINDS := {
	"shop": {"title": "Gun Shop", "color": Color(1.0, 0.62, 0.25), "menu": "shop",
		"lines": ["Everything's used. Some of it was used on people.",
			"No refunds. No questions. No warranty.",
			"Selling? I'll give you a quarter. Take it or leave it."]},
	"perks": {"title": "Mystic", "color": Color(0.78, 0.45, 1.0), "menu": "mystic",
		"lines": ["The spirits offer three gifts. You may take one. Greedy spirits.",
			"I see a perk in your future. It costs money.",
			"Choose wisely. Or don't, I get paid either way."]},
	"workshop": {"title": "Workshop", "color": Color(0.45, 0.75, 1.0), "menu": "workshop",
		"lines": ["Bring me a gun and I'll make it worse. Sorry, better.",
			"Old gun, new tricks. Same price as a new gun, almost.",
			"Don't ask what I did to the last one."]},
	"guild": {"title": "Guild", "color": Color(0.5, 0.9, 0.45), "menu": "guild",
		"lines": ["The Guild pays in ancient coins. Don't ask where we get them.",
			"Contracts are paid the moment they're done. We have ways of knowing.",
			"Sign here. Die somewhere else."]},
	"heroes": {"title": "Recruiter", "color": Color(0.4, 0.85, 1.0), "menu": "heroes",
		"lines": ["Pick a hero. Any hero. They all die the same."]},
	"relics": {"title": "Relic Keeper", "color": Color(0.45, 0.95, 0.95),
		"lines": ["Ancient coins buy ancient secrets. Not today, though.",
			"The relics are cursed. Also unfinished.",
			"Come back when the developer remembers me."],
		"soon": ["Unlock perks for ancient coins"]},
	"custom": {"title": "Oddsmaker", "color": Color(1.0, 0.82, 0.35), "menu": "custom",
		"lines": ["Let's bend the rules a little."]},
}
const TALK_DIST := 70.0     # ближе — можно заговорить
const CLOSE_DIST := 140.0   # дальше — окно закрывается само

var kind := "shop"
var t := 0.0
var highlight := false


func info() -> Dictionary:
	return KINDS.get(kind, KINDS["shop"])


func color() -> Color:
	return info()["color"]


func title() -> String:
	return U.t(str(info()["title"]))


## Случайная реплика торговца (уже переведённая).
func line() -> String:
	var ls: Array = info()["lines"]
	return U.t(str(ls[randi() % ls.size()]))


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _draw() -> void:
	var col := color()
	var wood := Color(0.42, 0.28, 0.17)
	var dark := Color(0.16, 0.11, 0.08)
	var bob := sin(t * 2.2) * 1.5
	# тень и задняя стенка (закрывает «скалу» прилавка в сетке)
	draw_rect(Rect2(-62, -24, 124, 14), Color(0, 0, 0, 0.3))
	draw_rect(Rect2(-60, -106, 120, 84), dark)
	# столбы навеса
	draw_rect(Rect2(-58, -96, 6, 74), wood.darkened(0.2))
	draw_rect(Rect2(52, -96, 6, 74), wood.darkened(0.2))
	# торговец
	var skin := Color(0.85, 0.68, 0.52)
	draw_rect(Rect2(-14, -62 + bob, 28, 26), col.darkened(0.45))
	draw_circle(Vector2(0, -70 + bob), 11.0, skin)
	draw_rect(Rect2(-12, -82 + bob, 24, 6), col.darkened(0.2))       # шапка
	draw_circle(Vector2(-4, -71 + bob), 1.6, dark)
	draw_circle(Vector2(4, -71 + bob), 1.6, dark)
	# прилавок
	draw_rect(Rect2(-56, -44, 112, 24), wood)
	draw_rect(Rect2(-56, -44, 112, 5), wood.lightened(0.25))
	draw_rect(Rect2(-56, -44, 112, 24), dark, false, 2.0)
	_draw_goods(col)
	# полосатый навес с фестонами
	var stripes := 6
	for i in stripes:
		var x0 := -64.0 + 128.0 * float(i) / float(stripes)
		var c := col if i % 2 == 0 else Color(0.95, 0.92, 0.85)
		draw_rect(Rect2(x0, -112, 128.0 / float(stripes) + 0.5, 22), c)
		draw_circle(Vector2(x0 + 64.0 / float(stripes), -90), 64.0 / float(stripes), c)
	draw_rect(Rect2(-64, -112, 128, 22), dark, false, 2.0)
	if highlight:
		draw_arc(Vector2(0, -8), 26.0 + sin(t * 5.0) * 2.0, 0.0, TAU, 24, Color(col, 0.7), 2.0)
	U.draw_text_c(self, U.font_bold(), Vector2(0, -122), title(), 16, col.lightened(0.2))


## Товар на прилавке — чтобы лавки различались издали.
func _draw_goods(col: Color) -> void:
	match kind:
		"shop":
			for i in 3:
				var x := -44.0 + float(i) * 32.0
				draw_rect(Rect2(x, -52, 22, 7), Color(0.25, 0.25, 0.28))
				draw_rect(Rect2(x + 2, -46, 6, 6), Color(0.25, 0.25, 0.28))
				draw_rect(Rect2(x, -52, 22, 2), col)
		"perks":
			var pulse := 1.0 + sin(t * 3.0) * 0.15
			draw_circle(Vector2(30, -52), 12.0 * pulse, Color(col, 0.25))
			draw_circle(Vector2(30, -52), 7.0, col.lightened(0.3))
			draw_rect(Rect2(-46, -54, 8, 10), Color(0.9, 0.85, 0.7))
			draw_rect(Rect2(-43, -60, 2, 6), Color(1.0, 0.8, 0.3))
		"workshop":
			draw_circle(Vector2(-30, -50), 9.0, Color(0.55, 0.58, 0.62))
			draw_circle(Vector2(-30, -50), 4.0, Color(0.16, 0.11, 0.08))
			draw_rect(Rect2(14, -52, 30, 5), Color(0.6, 0.62, 0.66))
			draw_rect(Rect2(40, -56, 7, 12), Color(0.6, 0.62, 0.66))
		"heroes":
			# три фигурки — «кого берёшь?»
			for i in 3:
				var hc: Color = Heroes.color(str(Heroes.ORDER[i % Heroes.ORDER.size()]))
				var x := -36.0 + float(i) * 36.0
				draw_circle(Vector2(x, -52), 6.0, hc)
				draw_arc(Vector2(x, -52), 6.0, 0.0, TAU, 12, hc.lightened(0.4), 1.5)
		"relics":
			var glow := 1.0 + sin(t * 2.5) * 0.2
			draw_circle(Vector2(-28, -52), 10.0 * glow, Color(col, 0.2))
			var pts := PackedVector2Array()
			for i in 6:
				pts.append(Vector2(-28, -52) + Vector2.from_angle(TAU * float(i) / 6.0 + PI / 6.0) * 7.0)
			draw_colored_polygon(pts, Color(0.2, 0.6, 0.75))
			draw_rect(Rect2(14, -56, 26, 12), Color(0.55, 0.45, 0.3))
		"custom":
			# кости
			for i in 2:
				var x := -30.0 + float(i) * 40.0
				draw_rect(Rect2(x, -60, 14, 14), Color(0.95, 0.93, 0.88))
				draw_circle(Vector2(x + 4, -56), 1.6, Color(0.1, 0.1, 0.1))
				draw_circle(Vector2(x + 10, -50), 1.6, Color(0.1, 0.1, 0.1))
		"guild":
			draw_rect(Rect2(-40, -60, 30, 18), Color(0.9, 0.84, 0.65))
			for i in 3:
				draw_rect(Rect2(-36, -56 + float(i) * 5.0, 22, 2), Color(0.4, 0.3, 0.2))
			# «!» над торговцем — квестодатель же
			var y := -100.0 + sin(t * 4.0) * 3.0
			draw_rect(Rect2(20, y, 6, 14), Color(1.0, 0.85, 0.2))
			draw_rect(Rect2(20, y + 17, 6, 5), Color(1.0, 0.85, 0.2))
