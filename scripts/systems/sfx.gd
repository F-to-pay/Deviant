class_name Sfx
extends Node
## Звуковые эффекты. Сканирует sfx/ игры и включённых модов (Mods/<мод>/sfx/): каждая папка — «банк»,
## из которого берётся случайный файл (sfx/guns/pistol/*.wav -> ключ "guns/pistol"), а каждый файл
## доступен и по своему пути без расширения ("reload/pistol"). Файлы модов добавляются в банки;
## чтобы заменить банк целиком — "replace_sfx": ["guns/pistol"] в mod.json.
## Звук выстрела основы — sfx/guns/<id основы>/, громкость/питч/перезарядка — поле "sound" в archetypes.json,
## поправка марки — "sound" в makers.json.
## Пул голосов с кражей самого старого, лимит одинаковых звуков и минимальный интервал —
## чтобы пулемёт и кассетные бомбы не превращали звук в кашу.

const VOICES_2D := 28
const VOL_STEP := 0.1

var banks := {}               # ключ -> Array[AudioStream]

var _pool: Array = []         # AudioStreamPlayer2D
var _key_of: Array = []       # что играет в голосе
var _started: Array = []      # когда запущен (для кражи)
var _last := {}               # ключ -> время последнего запуска
var _ui_pool: Array = []      # несколько непозиционных голосов: длинный звук босса не обрывается кликом
var _ui_next := 0
var _reload: AudioStreamPlayer
var _bus := -1
var _ui_bus := -1             # отдельная шина для звуков интерфейса (ключи "ui/...")
var _t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bus = _ensure_bus("SFX")
	_ui_bus = _ensure_bus("UI")
	for i in VOICES_2D:
		var p := AudioStreamPlayer2D.new()
		p.bus = "SFX"
		p.max_distance = 2200.0
		p.attenuation = 1.5
		p.process_mode = Node.PROCESS_MODE_PAUSABLE   # на паузе звуки замирают
		add_child(p)
		_pool.append(p)
		_key_of.append("")
		_started.append(-1.0)
	for i in 4:
		var u := AudioStreamPlayer.new()
		u.bus = "SFX"
		add_child(u)
		_ui_pool.append(u)
	_reload = AudioStreamPlayer.new()
	_reload.bus = "SFX"
	_reload.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_reload)
	rescan()
	_apply_volume()
	Game.settings_changed.connect(_on_setting)


func _process(delta: float) -> void:
	_t += delta


# --- Общий API -----------------------------------------------------------------

## Позиционный звук. Возвращает false, если отсечён лимитом.
func play_at(key: String, pos: Vector2, vol_db: float = 0.0, pitch: float = 1.0, vary: float = 0.05,
		max_same: int = 3, min_gap: float = 0.03) -> bool:
	var s := _pick(key)
	if s == null:
		return false
	if _t - float(_last.get(key, -9.0)) < min_gap:
		return false
	var same := 0
	var free := -1
	var oldest := 0
	for i in _pool.size():
		var p: AudioStreamPlayer2D = _pool[i]
		if not p.playing:
			if free < 0:
				free = i
			continue
		if _key_of[i] == key:
			same += 1
		if float(_started[i]) < float(_started[oldest]):
			oldest = i
	if same >= max_same:
		# свой же самый старый голос уступает место — очередь звучит ровно, а не копится
		free = _oldest_of(key)
	elif free < 0:
		free = oldest      # пул забит — крадём самый старый голос
	var v: AudioStreamPlayer2D = _pool[free]
	v.stream = s
	v.global_position = pos
	v.volume_db = vol_db
	v.pitch_scale = maxf(0.05, pitch * (1.0 + randf_range(-vary, vary)))
	v.play()
	_key_of[free] = key
	_started[free] = _t
	_last[key] = _t
	return true


## Непозиционный звук интерфейса.
func play_ui(key: String, vol_db: float = 0.0, pitch: float = 1.0, min_gap: float = 0.03) -> void:
	var s := _pick(key)
	if s == null:
		return
	if _t - float(_last.get("ui:" + key, -9.0)) < min_gap:
		return
	_last["ui:" + key] = _t
	var u: AudioStreamPlayer = _ui_pool[_ui_next]
	_ui_next = (_ui_next + 1) % _ui_pool.size()
	u.bus = "UI" if key.begins_with("ui/") else "SFX"
	u.stream = s
	u.volume_db = vol_db
	u.pitch_scale = pitch
	u.play()


## Короткий вызов из любого места: Sfx.at("hit/wall", pos, -12) — без проверки, что main есть.
static func at(key: String, pos: Vector2, vol_db: float = 0.0, pitch: float = 1.0, vary: float = 0.06,
		max_same: int = 3, min_gap: float = 0.04) -> void:
	if Game.main != null and Game.main.sfx != null:
		Game.main.sfx.play_at(key, pos, vol_db, pitch, vary, max_same, min_gap)


static func ui(key: String, vol_db: float = 0.0, pitch: float = 1.0, min_gap: float = 0.03) -> void:
	if Game.main != null and Game.main.sfx != null:
		Game.main.sfx.play_ui(key, vol_db, pitch, min_gap)


# --- Игровые события -----------------------------------------------------------

## Звуки «чужого» снаряда поверх выстрела (гибриды, моды «Реактивный», «Гранатный»).
const KIND_LAYER := {GunData.K_ROCKET: "guns/rocket", GunData.K_GRENADE: "guns/launcher", GunData.K_SHELL: "guns/mortar"}


static func _arch_sound(arch: String) -> Dictionary:
	var s: Variant = GunData.ARCH.get(arch, {}).get("sound", {})
	return s if s is Dictionary else {}


func gun_shot(g: Gun, pos: Vector2) -> void:
	var arch := g.archetype
	var snd := _arch_sound(arch)
	var mk: Variant = GunData.MAKERS.get(g.maker, {}).get("sound", {})
	var msnd: Dictionary = mk if mk is Dictionary else {}
	var vol := float(snd.get("vol", -6.0)) + float(msnd.get("vol", 0.0))
	var pitch := float(snd.get("pitch", 1.0)) * float(msnd.get("pitch", 1.0))
	# чем выше скорострельность, тем тише каждый выстрел
	vol -= clampf(log(maxf(g.fire_rate, 1.0) / 4.0) / log(2.0) * 2.0, 0.0, 6.0)
	play_at("guns/" + arch, pos, vol, pitch, 0.05, 4, 0.025)
	# гибриды и моды: снаряд другого типа добавляет свой звук поверх
	var own_kind := int(GunData.ARCH.get(arch, {}).get("kind", 0))
	if g.proj_kind != own_kind and KIND_LAYER.has(g.proj_kind):
		play_at(str(KIND_LAYER[g.proj_kind]), pos, vol - 5.0, 1.1, 0.05, 2, 0.06)


func explosion(pos: Vector2, r: float, big: bool) -> void:
	var key := "explosion_big" if big else "explosion"
	var vol := -9.0 + clampf(r / 30.0, 0.0, 7.0)
	var pitch := clampf(1.3 - r / 260.0, 0.65, 1.3)
	play_at(key, pos, vol, pitch, 0.08, 4, 0.05)


## Перезарядка: звук ускоряется, если перезарядка короче записи (Шабаш).
func reload_start(g: Gun) -> void:
	var s := _pick(str(_arch_sound(g.archetype).get("reload", "reload/rifle")))
	if s == null:
		return
	_reload.stream = s
	_reload.volume_db = -4.0
	var slen := s.get_length()
	_reload.pitch_scale = clampf(slen / maxf(g.reload_time, 0.1), 1.0, 1.6)
	_reload.play()


func reload_done(g: Gun) -> void:
	_reload.stop()
	var key := str(_arch_sound(g.archetype).get("reload_done", "reload/done"))
	play_ui(key, -6.0, randf_range(0.95, 1.05))


func reload_cancel() -> void:
	_reload.stop()


func empty_click() -> void:
	play_ui("ui/empty", -4.0, randf_range(0.95, 1.05))


# --- Громкость -------------------------------------------------------------------

func volume_text() -> String:
	return "%d%%" % roundi(float(Game.setting("sfx_volume")) * 100.0)


func _unhandled_input(event: InputEvent) -> void:
	var volume := float(Game.setting("sfx_volume"))
	if event.is_action_pressed("sfx_up"):
		_set_volume(volume + VOL_STEP)
	elif event.is_action_pressed("sfx_down"):
		_set_volume(volume - VOL_STEP)
	else:
		return
	get_viewport().set_input_as_handled()
	Game.say(U.t("Sounds: ") + volume_text(), Color(0.75, 0.9, 1.0))


func _on_setting(key: String) -> void:
	if key == "sfx_volume" or key == "ui_volume":
		_apply_volume()


func _set_volume(v: float) -> void:
	Game.set_setting("sfx_volume", clampf(snappedf(v, 0.01), 0.0, 1.0))


func _apply_volume() -> void:
	_set_bus(_bus, float(Game.setting("sfx_volume")))
	_set_bus(_ui_bus, float(Game.setting("ui_volume")))


static func _set_bus(idx: int, v: float) -> void:
	AudioServer.set_bus_mute(idx, v <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))


static func _ensure_bus(bus_name: String) -> int:
	var i := AudioServer.get_bus_index(bus_name)
	if i < 0:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus_name)
		AudioServer.set_bus_send(i, "Master")
	return i


# --- Служебное ------------------------------------------------------------------

func _oldest_of(key: String) -> int:
	var best := -1
	for i in _pool.size():
		if _key_of[i] == key and (_pool[i] as AudioStreamPlayer2D).playing:
			if best < 0 or float(_started[i]) < float(_started[best]):
				best = i
	return maxi(best, 0)


func _pick(key: String) -> AudioStream:
	var arr: Array = banks.get(key, [])
	if arr.is_empty():
		return null
	return arr[randi() % arr.size()]


## Перечитать звуки игры и модов (при старте и после включения/выключения модов).
func rescan() -> void:
	banks.clear()
	var replace := {}       # корень мода -> ключи банков, которые он заменяет
	for m in Mods.list:
		if bool(m["enabled"]):
			var info: Dictionary = m["info"]
			var rl: Variant = info.get("replace_sfx", [])
			replace[str(m["path"])] = rl if rl is Array else []
	var cleared := {}
	for f in Mods.files("sfx", Mods.AUDIO_EXTS, true):
		var rel := str(f[0])
		var full := str(f[1])
		var key := rel.get_base_dir()
		for root in replace:
			if full.begins_with(str(root)) and (replace[root] as Array).has(key) and not cleared.has(root + key):
				cleared[root + key] = true
				banks.erase(key)
		var s := Mods.load_audio(full)
		if s == null:
			continue
		_add(key, s)                       # банк папки
		_add(rel.get_basename(), s)        # конкретный файл


func _add(key: String, s: AudioStream) -> void:
	if key == "":
		return
	if not banks.has(key):
		banks[key] = []
	(banks[key] as Array).append(s)
