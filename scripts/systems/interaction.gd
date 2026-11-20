class_name Interact
extends RefCounted
## Что рядом с героем и что делает «E» / «F»: подбор пушки, замена, сундук, камень перезапуска, лавка.
## `update_near()` каждый кадр заполняет `Main.near_*` (их читают HUD и подсказки), `use(swap)` — действие. Экземпляр — `Main.interact`.

var main: Main


func _init(m: Main) -> void:
	main = m


## E — подобрать в рюкзак, F — заменить текущую пушку.
func use(swap: bool) -> void:
	if main.player.dead or main.transitioning:
		return
	if main.near_item != null and is_instance_valid(main.near_item):
		var it := main.near_item
		var g: Gun = it.gun
		if swap:
			var old := main.player.gun()
			main.player.guns[main.player.active] = g
			main.player.on_gun_changed()
			main.loot.remove_item(it)
			if old != null:
				main.loot.drop_gun(old, main.player.position + main.player.aim * 20.0, true)
			Game.say(U.t("Equipped: ") + g.gun_name, g.rarity_color())
			Sfx.ui("pickup/gun", -4.0)
		else:
			if main.player.add_gun(g):
				main.loot.remove_item(it)
				Game.say(U.t("Picked up: ") + g.gun_name, g.rarity_color())
				Sfx.ui("pickup/gun", -4.0)
			else:
				if Game.controls.mode == "touch":
					Game.say(U.t("Backpack full! Swap with current or scrap for ammo"), Color(1.0, 0.5, 0.4))
				else:
					Game.say(U.t("Backpack full! [%s] — swap with current, [%s] — scrap for ammo") % [
						Game.controls.label("swap"), Game.controls.label("scrap")], Color(1.0, 0.5, 0.4))
				Sfx.ui("ui/error", -6.0)
				return
		Game.state.note_gun(g)
		return
	if main.near_chest != null and is_instance_valid(main.near_chest) and not main.near_chest.opened:
		main.loot.open_chest(main.near_chest)
		return
	if main.near_reset:
		main.restart_from_stone()
		return
	if main.near_stall != null and is_instance_valid(main.near_stall):
		var scr := str(main.near_stall.info().get("menu", ""))
		if scr != "":
			main.hud.close_stall()
			main.menu.open_town(scr, main.near_stall.line(), main.near_stall.color())
		elif main.hud.stall == main.near_stall:
			main.hud.close_stall()
		else:
			main.hud.open_stall(main.near_stall)


func update_near() -> void:
	var prev := main.near_item
	main.near_item = null
	main.near_chest = null
	if main.player.dead:
		return
	var best := 70.0
	for o in main.loot.items:
		var it: GroundItem = o
		var d := it.position.distance_to(main.player.position)
		if d < best:
			best = d
			main.near_item = it
	if prev != main.near_item:
		if prev != null and is_instance_valid(prev):
			prev.highlight = false
		if main.near_item != null:
			main.near_item.highlight = true
	if main.near_item == null:
		for o in main.loot.chests:
			var c: Chest = o
			if not c.opened and c.position.distance_to(main.player.position) < 60.0:
				main.near_chest = c
				break
	var was_reset := main.near_reset
	main.near_reset = main.near_item == null and main.near_chest == null and main.reset_stone != null and \
		is_instance_valid(main.reset_stone) and main.reset_stone.position.distance_to(main.player.position) < ResetStone.TALK_DIST
	if was_reset != main.near_reset and main.reset_stone != null and is_instance_valid(main.reset_stone):
		main.reset_stone.highlight = main.near_reset
	var prev_stall := main.near_stall
	main.near_stall = null
	if main.near_item == null and main.near_chest == null and not main.near_reset:
		for o in main.stalls:
			var st: Stall = o
			if st.position.distance_to(main.player.position) < Stall.TALK_DIST:
				main.near_stall = st
				break
	if prev_stall != main.near_stall:
		if prev_stall != null and is_instance_valid(prev_stall):
			prev_stall.highlight = false
		if main.near_stall != null:
			main.near_stall.highlight = true
	# отошёл от лавки — окно закрывается
	if main.hud.stall != null and (not is_instance_valid(main.hud.stall) or main.hud.stall.position.distance_to(main.player.position) > Stall.CLOSE_DIST):
		main.hud.close_stall()
