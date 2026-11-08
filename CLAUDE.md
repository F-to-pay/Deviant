# Deviant — карта проекта для разработчика (и для ИИ-ассистента)

Бесконечный top-down диаблоид-аркада с абсурдными процедурными пушками. Godot **4.7** (код совместим с 4.4+),
GDScript со статической типизацией. Пользовательская документация — README.md, для модеров — Mods/README.md.
Здесь — как устроено и что трогать.

## Проверка после правок (обязательно)

```
godot --headless --path . --quit          # загрузить проект: все ошибки разбора/компиляции скриптов вылезут в консоль
```
Одна сломанная строка в любом скрипте каскадом ломает всё, что на него ссылается (ошибка может показать на
`main.gd`, а виноват `inventory_ui.gd`). В игре: «Моды» → «Отладчик модов (F8)» → перезапуск, команда `validate`.

## Скелет

- **Одна сцена** `scenes/main.tscn` с узлом `Main` (`scripts/main.gd`). Всё остальное создаётся кодом в `Main._ready()`:
  `Zone` (z −10), слой лута (z −2), слой врагов, `Player` (z 1), `Projectiles` (z 5), `FX` (z 6), `Controls`,
  `Camera2D`, `HUD` (CanvasLayer 10), `Music`, `Sfx`, `Menu` (20), `TouchControls` (12),
  а при старте — `Warmup` (99/100). `DebugConsole` — 50 (только с включённым отладчиком).
- **Автозагрузка `Game`** (`core/game.gd`, без class_name): настройки (`DEFAULTS`, `setting()`, `set_setting()`,
  сигнал `settings_changed`), параметры забега (`run`, `RUN_DEFAULTS`), кривые сложности (`enemy_hp_mult`,
  `enemy_dmg_mult`, `gun_dmg_mult`), рейтинг, сохранение `user://deviant.cfg`, `load_content()` / `reload_content()`.
- **Порядок старта:** `Game._ready` → `InputSetup.setup()` → загрузка настроек → `load_content()`
  (`Mods.scan`, `GunData`, `EnemyData`, `Codex`, `I18n`) → применение настроек → `Main._ready` строит мир →
  `Warmup` (экран загрузки: скрипты модов, музыка, глифы шрифтов, шейдеры, все пушки) → `Main.to_menu()`.
- **Забег:** `Main.start_game(cfg)` → `start_run()` → `load_town(1)` (город) или `load_zone(level)`
  (`ZoneGen.generate` → `Zone.setup` → стаи/сундуки/портал или босс). Портал → `next_zone(level, to_town)`:
  в конце этапа (`Game.TOWN_EVERY` = 5 зон, `Game.town_before`) — сначала город (`TownGen` + `Stall`), из него — в зону.
  Смерть → `HUD` экран смерти → `start_run` или меню.

## Подсистемы и где они

| Что | Файлы |
|---|---|
| Пушки: таблицы из JSON | `weapons/gun_data.gd` (ARCH, MAKERS, MODS=перки, LEGENDARIES, RARITIES, имена) ← `data/*.json` |
| Операции над статами (`["mul","damage",1.3]`, `if`) | `weapons/gun_ops.gd` (+ `describe()` для справочника) |
| Генератор | `weapons/gun_gen.gd`: редкость → тип/гибрид → марка → перки → легендарка → разброс → `_finalize` (уровень, пределы, имя) |
| Пушка (все статы) | `weapons/gun.gd`; рисунок — `weapons/gun_icon.gd`; карточка — `ui/gun_card.gd` |
| Снаряды — **данные, не узлы** | `systems/projectiles.gd` (`Proj`, `fire_gun`, `_step`, взрывы, деление, кассеты, вихри) |
| Урон, цепи, взрывы | `systems/combat.gd`; статусы (огонь/кислота/холод/шок/проклятие) — `entities/actor.gd` |
| Враги | `entities/enemy_data.gd` (TYPES, AFFIXES, стаи — **в коде**), `entities/enemy.gd` (`_behave` — `match etype`), `entities/boss.gd` |
| Поиск пути | `world/zone.gd` `find_path()` — AStarGrid2D по классам размера тела (`size_class`) |
| Карта | `world/zone_gen.gd` (генерация), `world/zone.gd` (сетка T=40, коллизии `move_circle`, лучи `ray_clear`, миникарта), `world/biomes.gd` |
| Город между этапами | `world/town_gen.gd` (площадь, улицы, дома по `town_style` биома, имя), `world/stall.gd` (лавки: `KINDS` — вывеска, реплики, `menu` — экран меню; без него — окно-заглушка `HudDraw._draw_stall`) |
| Торговля, Мистик, Мастерская | цены и товар — `systems/shops.gd` (`make_town` при входе в город → `Main.town`), перки Мистика — перки навыков `Heroes.PERKS` (что даёт — `Player.perk()`, `skill_dmg_mult`, `Skills`); пересборка пушки — `GunGen.rebuild` / `upgrade_level`; экраны — `Menu._build_shop/_mystic/_workshop` |
| Задания Гильдии | `systems/quests.gd` (`TYPES`, `active`, `progress(тип)` — зовётся из `Main`); экран — `Menu._build_guild`, строки на HUD — `HudDraw._draw_zone_info` |
| Фляги лечения | `Player.flasks` / `drink()` / `FLASK_MAX`, `FLASK_HEAL`; дроп — `Main.spawn_flask` (`world/flask_drop.gd`); Лекарь — `Shops.heal_price` / `flask_price`, экран `Menu._build_healer` |
| Монеты | `Game.coins` (забег, `START_COINS`, `coin_value`), `Game.meta_coins` (древние, мета, сохраняются в `[meta]` deviant.cfg сразу); `world/coin.gd`; дроп — `Main.drop_coins` в `on_enemy_killed` / `open_chest` / `_boss_dead` |
| Игрок | `entities/player.gd` (движение, рывок, навык героя `_use_skill`, оружие, патроны, рюкзак) |
| Герои и навыки | `entities/heroes.gd` (`LIST`: имя, цена в древних монетах, навык и числа); выбор — `Game.hero`, открытые — `Game.heroes_open` (`[meta]` deviant.cfg); экран Вербовщика — `Menu._build_heroes` |
| Ввод | `core/input_setup.gd` (действия, умолчания kb/pad, переназначение), `systems/controls.gd` (чем играют, прицел, огонь, автоприцел/автоогонь), `ui/touch_controls.gd` |
| HUD | `ui/hud.gd` (состояние), `ui/hud_draw.gd` (всё рисуется в `_draw`), `ui/inventory_ui.gd`, `ui/cursor_draw.gd` |
| Меню | `ui/menu.gd` — все экраны (главное, пауза, настройки, управление, настраиваемый старт, моды, справочник) на Control-ах |
| Размер интерфейса и отступы | `ui/ui_fit.gd` |
| Звук / музыка | `systems/sfx.gd` (банки из `sfx/`), `systems/music.gd` (категории, фоновая подгрузка) |
| Переводы | `core/i18n.gd`, `core/util.gd` (`U.t`), `lang/ru.json`, `lang/nb.json` |
| Моды | `core/mods.gd` (слои, скрипты, `validate`), `core/debug_log.gd`, `ui/debug_console.gd` |
| Справочник и гайд | `systems/codex.gd`, `data/codex.json`, `data/guide.json` |
| Прогрев | `systems/warmup.gd` |

## Правила проекта

- **Нет сцен и ассетов-картинок:** узлы создаются кодом, графика — `draw_*` в `_draw()`.
- **Строки:** исходник — английский, всегда через `U.t("Text")`; форматирование после перевода: `U.t("Zone %d") % n`.
  Каждую новую строку добавить в **`lang/ru.json` и `lang/nb.json`** (у существительных `{text, lower, g}`,
  у прилагательных `{m, f, n}`). Пропуски видно командой отладчика `missing ru`.
- **Новая настройка:** ключ в `Game.DEFAULTS` + строка `_slider`/`_check` в `Menu` (`_build_settings` или
  `_build_controls`) + чтение `Game.setting("key")`; реакция на изменение — `Game.settings_changed`.
- **Новый размер/обводка текста в `_draw`** → добавить в `Warmup.REGULAR` / `Warmup.BOLD`, иначе фриз в бою.
- **Подсказки с кнопками** — не хардкодить «[E]»: `Controls.label("interact")` (на сенсоре — пусто, там свои кнопки).
- **Пушки/перки/марки/легендарки** — данными в `data/*.json`; новое поведение снаряда — поле в `Gun` +
  копирование в `Projectiles.fire_gun()`/`_clone()` + логика в `_step()`; тег перка — ещё в `Mods.KNOWN_TAGS`,
  `special` легендарки — в `Mods.KNOWN_SPECIALS` и `Codex.SPECIALS`.
- **Комментарии в коде — по-русски**, `##` над функцией — что делает и зачем.
- **Музыки нет в git:** `python tools/fetch_music.py` (ссылки в `music/SOURCES.txt`).

## Ловушки GDScript, на которых уже горели

- Нельзя повторно объявить локальную переменную во вложенном блоке той же функции (`var ch` дважды) —
  скрипт не компилируется.
- `await f()` от обычной (не корутины) функции, возвращающей сигнал, **не ждёт** — пиши `await get_tree().process_frame`.
- `continue` внутри `match` — избегай, перестрой условием.
- Присваивание через приведение `(ev as X).prop = v` — заводи типизированную локальную переменную.
- `:=` с выражением типа Variant не выводит тип — указывай явно (`var b: bool = ...`).
- Лямбды в `static func` — лучше обычная static-функция.
- Пауза: меню и HUD работают с `PROCESS_MODE_ALWAYS`; новые узлы интерфейса — тоже.
- Запуск из редактора: F8 — шорткат Godot «Остановить проект», игра закрывается без ошибок в журнале.
  Консоль отладчика там открывать клавишей ` (тоже `mod_console`). Новые горячие клавиши — не F5–F8.

## Где что править — быстрые ответы

| Хочу | Куда |
|---|---|
| Баланс урона/здоровья по зонам | `Game.enemy_hp_mult / enemy_dmg_mult / gun_dmg_mult` |
| Шансы редкостей, перков, гибридов | `data/rarities.json`, `GunGen.roll_rarity` |
| Новый тип пушки / марка / перк / легендарка | `data/*.json` + `lang/ru.json` + `lang/nb.json` |
| Новый враг | `EnemyData.TYPES` + ветка в `Enemy._behave` + описание в `data/codex.json` (`enemies`) |
| Свойство элитки | `EnemyData.AFFIXES` + `Enemy._tick_affixes` + `data/codex.json` (`affixes`) |
| Атака босса | `Boss.PATTERNS` / `DURATION` + обработка в `boss.gd` |
| Новый биом | `Biomes.LIST` |
| Лут и монеты с врагов/сундуков/боссов | `Main` (обработчики смерти врага/босса, `open_chest`) |
| Новый перк навыка | `Heroes.PERKS` + эффект: попадание навыком — `systems/skills.gd` (`hit`, `explode`), применение — `Player._use_skill` / `_bless_proj` + строки и справочник (`heroes`) |
| Новый вид задания | `Quests.TYPES` + вызов `Quests.progress("вид")` в нужном месте + строки |
| Новый герой / навык | `Heroes.LIST` + ветка в `Player._use_skill` (+ рисунок в `Player._draw`) + строки в `lang/*.json` + страница `heroes` в `data/codex.json` |
| Лавка, открывающая экран меню | `Stall.KINDS[...]["menu"]` → `Menu.open_town(экран)`; «Назад» — `Menu._back()` |
| Вид/имена городов | `Biomes.LIST` (`town`, `town_style`), `TownGen.SUFFIXES`; переводы ключей `"Dust-"`, `"-ville"` |
| Управление по умолчанию | `InputSetup.DEFAULTS` (+ `REBINDABLE` для меню) |
| Экранные кнопки | `TouchControls.ELEMENTS` |
| Страница справочника | `data/codex.json` |
