class_name HUD
extends CanvasLayer
## Интерфейс: держит состояние экранов (пауза, смерть, инвентарь) и сообщения.
## Работает и на паузе (PROCESS_MODE_ALWAYS).

const DEATH_TITLES := ["WASTED", "YOU DIED. AGAIN.", "SKILL ISSUE", "WRONG GUNS", "WELL, THAT HAPPENED", "YOU HAVE DIED (officially)"]

var fade := 0.0
var root: HudDraw
var inv: InventoryUI
var cursor: CursorDraw
var messages: Array = []
var banner_text := ""
var banner_sub := ""
var banner_t := 0.0
var help_t := 0.0
var dead_screen := false
var death_title := ""
var new_record := false
var paused := false
var death_t := 0.0


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = HudDraw.new()
	root.hud = self
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inv = InventoryUI.new()
	inv.hud = self
	add_child(inv)
	inv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inv.visible = false
	cursor = CursorDraw.new()
	cursor.follow_aim = true
	cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cursor)
	cursor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Game.message.connect(_on_message)


func on_run_start() -> void:
	dead_screen = false
	paused = false
	inv.visible = false
	messages.clear()
	help_t = 14.0
	get_tree().paused = false


func zone_banner(level: int, biome_name: String, boss_title: String) -> void:
	if boss_title != "":
		banner_text = U.t("ZONE %d — BOSS") % level
		banner_sub = boss_title
	else:
		banner_text = U.t("ZONE %d") % level
		banner_sub = biome_name
	banner_t = 3.2


func show_death(record: bool) -> void:
	dead_screen = true
	new_record = record
	death_t = 0.0
	death_title = DEATH_TITLES[randi() % DEATH_TITLES.size()]
	inv.visible = false


func _on_message(text: String, color: Color) -> void:
	messages.append([text, color, 4.0])
	if messages.size() > 6:
		messages.remove_at(0)


func toggle_inventory() -> void:
	if dead_screen:
		return
	inv.visible = not inv.visible
	get_tree().paused = inv.visible
	Game.main.music.set_muffled(inv.visible)
	Sfx.ui("ui/open" if inv.visible else "ui/close", -8.0)
	if inv.visible:
		inv.queue_redraw()


func toggle_pause() -> void:
	if dead_screen:
		return
	paused = not paused
	get_tree().paused = paused
	Game.main.music.set_paused(paused)
	if paused:
		Game.main.menu.open_pause()
	else:
		Game.main.menu.close()


func _unhandled_input(event: InputEvent) -> void:
	if dead_screen:
		if death_t > 0.6 and (event.is_action_pressed("reload") or event.is_action_pressed("restart") or event.is_action_pressed("interact")):
			dead_screen = false
			get_viewport().set_input_as_handled()
			Game.main.start_run()
		elif death_t > 0.6 and event.is_action_pressed("pause"):
			get_viewport().set_input_as_handled()
			Game.main.to_menu()
		return
	if event.is_action_pressed("pause"):
		if inv.visible:
			toggle_inventory()
		else:
			toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory") and not paused:
		toggle_inventory()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug"):
		Game.debug = not Game.debug


func _process(delta: float) -> void:
	for m in messages:
		m[2] -= delta
	var keep: Array = []
	for m in messages:
		if float(m[2]) > 0.0:
			keep.append(m)
	messages = keep
	if banner_t > 0.0:
		banner_t -= delta
	if help_t > 0.0 and not get_tree().paused:
		help_t -= delta
	if dead_screen:
		death_t += delta
	cursor.visible = not Game.main.menu.visible and not (inv.visible and Controls.mode != "kbm")
	root.queue_redraw()
	cursor.queue_redraw()
