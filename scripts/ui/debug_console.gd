class_name DebugConsole
extends CanvasLayer
## Отладчик модов: журнал DebugLog + командная строка. Открывается по F8.
## Создаётся, только если в меню «Моды» включён отладчик (после перезапуска игры).
## Пока открыт — игра на паузе. Закрыт, но есть предупреждения/ошибки — в углу значок.

const COLORS := {"info": "#a8b0c0", "print": "#d0d0d0", "warn": "#ffcc55", "error": "#ff6655", "tr": "#88aaff", "cmd": "#77ee99"}
const HELP := [
	"help                          — this list",
	"clear                         — clear the log",
	"validate                      — check all loaded data again",
	"reload                        — re-read data, translations, sounds, music of all mods",
	"lang <code>                   — switch language (en, ru, ...)",
	"list arch|makers|perks|legendaries|langs|mods",
	"give <arch|random> [maker|random] [rarity 0-5]   — drop a gun next to you (in a run)",
	"perk <perk_id> [arch]         — drop a rare gun with this perk",
	"legendary <id>                — drop this legendary",
	"missing [lang]                — strings seen in game without translation",
]

var panel: PanelContainer
var log_view: RichTextLabel
var input: LineEdit
var badge: Label
var only_problems: CheckButton
var cursor: CursorDraw
var _ver := -1
var _paused_by_me := false
var _history: Array = []
var _hist_i := 0


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.05, 0.94)
	sb.border_color = Color(1.0, 0.55, 0.2, 0.8)
	sb.border_width_bottom = 2
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.offset_bottom = 520

	var vb := VBoxContainer.new()
	panel.add_child(vb)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	vb.add_child(top)
	var title := Label.new()
	title.text = U.t("Mod debugger") + "  [F8]"
	title.add_theme_font_override("font", U.font_bold())
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.6, 0.25))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	only_problems = CheckButton.new()
	only_problems.text = U.t("Problems only")
	only_problems.toggled.connect(func(_on: bool) -> void: _ver = -1)
	top.add_child(only_problems)
	for pair in [["Validate", _cmd_validate], ["Copy", _copy], ["Clear", _clear]]:
		var b := Button.new()
		b.text = U.t(str(pair[0]))
		b.pressed.connect(pair[1])
		top.add_child(b)

	log_view = RichTextLabel.new()
	log_view.bbcode_enabled = true
	log_view.scroll_following = true
	log_view.selection_enabled = true
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_view.add_theme_font_size_override("normal_font_size", 14)
	vb.add_child(log_view)

	input = LineEdit.new()
	input.placeholder_text = U.t("command — type help")
	input.text_submitted.connect(_on_submit)
	input.gui_input.connect(_on_input_key)
	vb.add_child(input)

	badge = Label.new()
	badge.add_theme_font_size_override("font_size", 14)
	badge.add_theme_constant_override("outline_size", 4)
	badge.add_theme_color_override("font_outline_color", Color.BLACK)
	root.add_child(badge)
	badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	badge.offset_left = -360
	badge.offset_top = 6
	badge.offset_right = -10
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	cursor = CursorDraw.new()
	cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cursor)
	cursor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	panel.visible = false
	cursor.visible = false
	DebugLog.info("mod debugger on — F8 to open, type help", "debug")


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("mod_console"):
		toggle()
		get_viewport().set_input_as_handled()
	elif panel.visible and event.is_action_pressed("pause"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	panel.visible = not panel.visible
	cursor.visible = panel.visible
	var tree := get_tree()
	if panel.visible:
		_ver = -1
		if not tree.paused:
			tree.paused = true
			_paused_by_me = true
		input.grab_focus.call_deferred()
	else:
		input.release_focus()
		if _paused_by_me:
			tree.paused = false
			_paused_by_me = false


func _process(_delta: float) -> void:
	var w := DebugLog.warns
	var e := DebugLog.errors
	badge.visible = not panel.visible and (w > 0 or e > 0)
	if badge.visible:
		badge.text = U.t("Mods") + ": %s%s — F8" % [("⚠ %d  " % w) if w > 0 else "", ("✖ %d" % e) if e > 0 else ""]
		badge.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35) if e > 0 else Color(1.0, 0.8, 0.35))
	if panel.visible:
		cursor.queue_redraw()
		if _ver != DebugLog.version:
			_ver = DebugLog.version
			_redraw_log()


func _redraw_log() -> void:
	var lines := PackedStringArray()
	for en in DebugLog.snapshot():
		var lvl := str(en["level"])
		if only_problems.button_pressed and not (lvl in ["warn", "error"]):
			continue
		var col := str(COLORS.get(lvl, "#ffffff"))
		var src := str(en["src"])
		var n := int(en["n"])
		var txt := str(en["text"]).replace("[", "[lb]")
		lines.append("[color=%s]%s%s%s[/color]" % [col, ("[%s] " % src).replace("[", "[lb]") if src != "" else "",
			txt, ("  ×%d" % n) if n > 1 else ""])
	log_view.text = "\n".join(lines)


# --- Команды -----------------------------------------------------------------------

func _on_input_key(ev: InputEvent) -> void:
	if not (ev is InputEventKey) or not ev.is_pressed() or _history.is_empty():
		return
	var k := (ev as InputEventKey).keycode
	if k == KEY_UP:
		_hist_i = maxi(0, _hist_i - 1)
		input.text = str(_history[_hist_i])
		input.caret_column = input.text.length()
		input.accept_event()
	elif k == KEY_DOWN:
		_hist_i = mini(_history.size(), _hist_i + 1)
		input.text = str(_history[_hist_i]) if _hist_i < _history.size() else ""
		input.caret_column = input.text.length()
		input.accept_event()


func _on_submit(text: String) -> void:
	var line := text.strip_edges()
	input.clear()
	if line == "":
		return
	_history.append(line)
	_hist_i = _history.size()
	DebugLog.add("cmd", "> " + line)
	var parts := line.split(" ", false)
	var cmd := parts[0].to_lower()
	var args := parts.slice(1)
	match cmd:
		"help":
			for h in HELP:
				DebugLog.add("cmd", str(h))
		"clear":
			_clear()
		"validate":
			_cmd_validate()
		"reload":
			Game.reload_content()
			if Game.main != null:
				Game.main.menu._rebuild.call_deferred()
			Mods.validate()
		"lang":
			if args.is_empty() or not I18n.langs.has(args[0]):
				_say("languages: " + ", ".join(PackedStringArray(I18n.available())))
			else:
				Game.set_setting("language", args[0])
				_say("language: " + I18n.current())
		"list":
			_cmd_list(args[0] if not args.is_empty() else "")
		"give":
			_give(args[0] if args.size() > 0 else "random", args[1] if args.size() > 1 else "random",
				int(args[2]) if args.size() > 2 else -1, "", "")
		"perk":
			if args.is_empty() or GunData.perk(args[0]).is_empty():
				_say("unknown perk — try: list perks")
			else:
				_give(args[1] if args.size() > 1 else "random", "random", GunData.R_RARE, args[0], "")
		"legendary":
			if args.is_empty():
				_say("which one? — try: list legendaries")
			else:
				_give("random", "random", GunData.R_LEGENDARY, "", args[0])
		"missing":
			var code: String = args[0] if not args.is_empty() else I18n.current()
			var d: Dictionary = DebugLog.missing_tr.get(code, {})
			_say("[%s] %d strings without translation seen so far" % [code, d.size()])
			for s in d:
				DebugLog.add("tr", "  \"%s\"" % str(s))
		_:
			_say("unknown command '%s' — type help" % cmd)


func _say(s: String) -> void:
	DebugLog.add("cmd", s)


func _cmd_validate() -> void:
	Mods.validate()


func _cmd_list(what: String) -> void:
	match what:
		"arch":
			_say("archetypes: " + ", ".join(PackedStringArray(GunData.ARCH.keys())))
		"makers":
			_say("makers: " + ", ".join(PackedStringArray(GunData.MAKERS.keys())))
		"perks":
			var ids := PackedStringArray()
			for p in GunData.MODS:
				ids.append(str(p["id"]))
			_say("perks: " + ", ".join(ids))
		"legendaries":
			var ids := PackedStringArray()
			for l in GunData.LEGENDARIES:
				ids.append(str(l["id"]))
			_say("legendaries: " + ", ".join(ids))
		"langs":
			_say("languages: " + ", ".join(PackedStringArray(I18n.available())))
		"mods":
			for m in Mods.list:
				_say("%s %s  (%s)" % ["[on] " if bool(m["enabled"]) else "[off]", str(m["id"]), str(m["path"])])
		_:
			_say("list arch|makers|perks|legendaries|langs|mods")


## Выдать пушку рядом с игроком (только в забеге).
func _give(arch: String, maker: String, rarity: int, perk: String, leg: String) -> void:
	var main: Main = Game.main
	if main == null or main.menu.visible and main.menu.mode == "main" or main.player.dead:
		_say("start a run first")
		return
	if arch != "random" and not GunData.ARCH.has(arch):
		_say("unknown archetype '%s' — try: list arch" % arch)
		return
	if maker != "random" and not GunData.MAKERS.has(maker):
		_say("unknown maker '%s' — try: list makers" % maker)
		return
	if leg != "":
		var found := false
		for l in GunData.LEGENDARIES:
			if str(l["id"]) == leg:
				found = true
		if not found:
			_say("unknown legendary '%s' — try: list legendaries" % leg)
			return
	GunGen.force_legendary = leg
	var g := GunGen.generate(maxi(1, Game.zone_level), main.rng, 0.0, 0,
		clampi(rarity, -1, GunData.R_ABSURD),
		"" if arch == "random" else arch, "" if maker == "random" else maker)
	GunGen.force_legendary = ""
	if perk != "" and not (perk in g.mods):
		GunGen._add_mod(g, perk, main.rng)
	main.drop_gun(g, main.player.position + main.player.aim * 40.0, true)
	_say("dropped: %s  [%s / %s, %s]" % [g.gun_name, g.archetype + ("+" + g.archetype2 if g.archetype2 != "" else ""),
		g.maker, ", ".join(PackedStringArray(g.mods))])


func _copy() -> void:
	var lines := PackedStringArray()
	for en in DebugLog.snapshot():
		lines.append("%s %s%s%s" % [str(en["level"]).to_upper(), ("[%s] " % str(en["src"])) if str(en["src"]) != "" else "",
			str(en["text"]), ("  x%d" % int(en["n"])) if int(en["n"]) > 1 else ""])
	DisplayServer.clipboard_set("\n".join(lines))
	_say("log copied to clipboard")


func _clear() -> void:
	DebugLog.clear()
