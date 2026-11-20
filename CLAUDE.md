# Deviant — карта проекта для разработчика (и для ИИ-ассистента)

Бесконечный top-down диаблоид-аркада с абсурдными процедурными пушками. Godot **4.7** (код совместим с 4.4+),
GDScript со статической типизацией. Пользовательская документация — README.md, для модеров — Mods/README.md.
Здесь — как устроено и что трогать.

## Проверка после правок (обязательно)

```
godot --headless --path . --quit          # загрузить проект: все ошибки разбора/компиляции скриптов вылезут в консоль
godot --headless --path . --import        # после нового class_name (иначе «Identifier not declared»: кэш классов в .godot)
godot --headless --path . -s res://tests/unit_core.gd   # формулы, профиль, настройки, сохранение; в конце «fails=0»
godot --headless --path . -s res://tests/smoke.gd       # настоящий забег: зоны 1..400, убийства, город (отпечаток для сравнения)
godot --headless --path . -s res://tests/controls_state.gd   # режимы ввода, подписи, прицел, очередь навыка/выстрела
godot --headless --path . -s res://tests/gen_fingerprint.gd  # отпечаток ZoneGen / TownGen по многим сидам: любая правка генераторов обязана оставить его прежним (порядок бросков rng — часть результата)
godot --headless --path . -s res://tests/proj_fingerprint.gd # пушки разных типов стреляют по спящим врагам и в героя: отпечаток для правок Projectiles
godot --headless --path . -s res://tests/zone_source.gd      # ZoneLoader берёт карты из подставляемого ZoneSource
godot --headless --path . -s res://tests/skip_zone.gd        # пропуск зон платит бюджет судьи
godot --headless --path . -s res://tests/console_commands.gd # команды консоли отладчика (пишет в deviant.cfg: сделай копию!)
godot --headless --path . -s res://tests/ui_screens.gd  # дерево узлов всех экранов (en/ru) + нажатия в лавках: отпечаток для сравнения при правках меню
godot --headless --path . -s res://tests/ui_actions.gd  # Esc-навигация, настройки, привязка клавиш, справочник, язык (пишет в deviant.cfg: сделай копию!)
```
Одна сломанная строка в любом скрипте каскадом ломает всё, что на него ссылается (ошибка может показать на
`main.gd`, а виноват `inventory_ui.gd`). В игре: «Моды» → «Отладчик модов (F8)» → перезапуск, команда `validate`.

## Скелет

- **Одна сцена** `scenes/main.tscn` с узлом `Main` (`scripts/main.gd`). Всё остальное создаётся кодом в `Main._ready()`:
  `Zone` (z −10), слой лута (z −2), слой врагов, `Player` (z 1), `Projectiles` (z 5), `FX` (z 6),
  `Camera2D`, `HUD` (CanvasLayer 10), `Music`, `Sfx`, `Menu` (20), `TouchControls` (12),
  а при старте — `Warmup` (99/100). `DebugConsole` — 50 (только с включённым отладчиком).
  Ввод (`Controls`) — не здесь, а потомок автозагрузки (`Game.controls`). Сам `Main` небольшой: узлы, переходы между зонами (`next_zone`, `skip_zone`),
  кадр (`_physics_process`: сетка попаданий, пробуждение врагов). Остальное — компоненты-RefCounted с ссылкой `main`:
  `Main.loader` (`ZoneLoader`: загрузка зон/городов, расстановка врагов; карты берёт из `loader.source`, `ZoneSource`), `Main.loot` (`Loot`), `Main.interact`
  (`Interact`: что рядом, E/F), `Main.rewards` (`Rewards`: убийства, смерть). Состояние мира (`zone`, `enemies`, `player`, `near_*`, `stalls`, `portal`, `boss`, `town`) — на `Main`.
- **Автозагрузка `Game`** (`core/game.gd`, без class_name) — тонкий координатор: держит ссылки `main`, `rng` и части состояния,
  склеивает их там, где нужны эффекты (`add_xp`, `new_run`, `record_death`, `select_hero`, `add_meta`, `say`, `load_content()` /
  `reload_content()`, `save()`). Сами данные и правила — в отдельных классах `core/`:
  - `Settings` (`Game.settings`: `get_value` / `set_value`, сигнал `changed`, `DEFAULTS`) — настройки;
  - `Profile` (`Game.profile`: `meta_coins`, `hero`, `heroes_open`, рекорды `best_*`, последний пользовательский старт `custom`; сигнал `changed` → `Game.save()`) — что переживает забег;
  - `RunState` (`Game.state`: монеты, опыт, `hero_level`, `tree`, счётчики, `zone_level`, `in_town`, `seed_value`) — состояние забега, сбрасывается `reset()`;
  - `Game.run` — параметры забега (словарь, ключи `RunConfig.DEFAULTS`); `RunConfig` — статические правила: этапы (`TOWN_EVERY`), рейтинг, `counts_for_records`, `seed_from`;
  - `Balance` — статические числа и кривые: опыт (`xp_need`), сложность (`enemy_hp_mult(level, hp_mult)`, `gun_dmg_mult`), экономика (`econ`, `coins_for`, `money`) — без обращений к `Game`;
  - `Save` — чтение/запись `user://deviant.cfg` (`Profile` + `Settings`).
  - `Game.controls` (`Controls`) — ввод игрока, `Game.debug_log` (`DebugLog`) — журнал отладчика: это тоже экземпляры, не статика; статических переменных с состоянием в проекте почти нет (кроме таблиц данных `GunData`, `EnemyData`, `Codex`, `I18n`, `Mods`, заполняемых при загрузке контента).
- **Порядок старта:** `Game._ready` → `InputSetup.setup()` → загрузка настроек → `load_content()`
  (`Mods.scan`, `GunData`, `EnemyData`, `Codex`, `I18n`) → применение настроек → `Main._ready` строит мир →
  `Warmup` (экран загрузки: скрипты модов, музыка, глифы шрифтов, шейдеры, все пушки) → `Main.to_menu()`.
- **Забег:** `Main.start_game(cfg)` → `start_run()` → `Main.loader.load_town(1)` (город) или `load_zone(level)`
  (`ZoneGen.generate` → `Zone.setup` → стаи/сундуки/портал или босс). Портал → `next_zone(level, to_town)`:
  в конце этапа (`RunConfig.TOWN_EVERY` = 5 зон, `RunConfig.town_before`) — сначала город (`TownGen` + `Stall`), из него — в зону.
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
| Торговля, Мистик, Мастерская | цены и товар — `systems/shops.gd` (`make_town` при входе в город → `Main.town`), перки Мистика — перки навыков `Heroes.PERKS` (что даёт — `Player.perk()`, `skill_dmg_mult`, `Skills`); пересборка пушки — `GunGen.rebuild` (подтягивать уровень нельзя — пушки должны устаревать; исключение — белые, `Gun.sync_level`: при входе в зону/город (`Main.sync_white_guns`) и при подборе (`Player.add_gun`) они получают уровень зоны, `Game.white_level()`); экраны — `ShopScreen` / `MysticScreen` / `WorkshopScreen` (`ui/screens/`) |
| Опыт героя и «судья» | `Game.add_xp`, `Balance.xp_need / enemy_xp`, `RunState.gain_xp` (уровень = 5 очков дерева), `systems/director.gd` (судья: бюджет `LEVELS_PER_ZONE` = 1,5 уровня за зону, любит элиток `ELITE_LOVE`, после расстановки `finish_zone()` считает `xp_scale`; награда за убийство — `director.kill_xp`, не `Balance.enemy_xp`; F3), `Main.director` |
| Дерево навыков игрока | `systems/level_tree.gd` (`LevelTree`: очки, покупка, `stat(имя)`), данные — `data/skill_branches.json` + `data/skill_tree.json` (моды правят по id), состояние забега — `Game.state.tree`; экраны — `TreeScreen` (по экрану на ветку), клавиша `skill_tree`; читают эффекты `Player`, `Projectiles.fire_gun`, `Enemy.hurt`, `Skills.hit`, `Main.drop_coins` / `_mark_bounty`, `GunGen.roll_rarity` |
| Задания Гильдии | `systems/quests.gd` (`TYPES`, `active`, `progress(тип)` — зовётся из `Main`); экран — `GuildScreen`, строки на HUD — `HudDraw._draw_zone_info` |
| Фляги лечения | `Player.flasks` / `drink()` / `FLASK_MAX`, `FLASK_HEAL`; дроп — `Main.loot.spawn_flask` (`world/flask_drop.gd`); Лекарь — `Shops.heal_price` / `flask_price`, экран `HealerScreen` |
| Монеты | `Game.state.coins` (забег, `RunConfig.START_COINS`, `coin_value`), `Game.profile.meta_coins` (древние, мета, сохраняются в `[meta]` deviant.cfg сразу); `world/coin.gd`; дроп — `Main.loot.drop_coins`, зовут `Rewards.on_enemy_killed` / `_boss_dead` и `Loot.open_chest` |
| Игрок | `entities/player.gd` (движение, рывок, навык героя `_use_skill`, оружие, патроны, рюкзак) |
| Герои и навыки | `entities/heroes.gd` (`LIST`: имя, цена в древних монетах, навык и числа); выбор — `Game.profile.hero`, открытые — `Game.profile.heroes_open` (`[meta]` deviant.cfg); экран Вербовщика — `HeroesScreen`; турель Инженера — `entities/turret.gd` (бросок и обойма — `Player._make_turret_spec`, мина — `Projectiles.throw_turret`), враги выбирают цель через `Main.target_for` (герой или ближайшая турель; `Enemy._target`, параметры `player: Actor`) |
| Ввод | `core/input_setup.gd` (действия, умолчания kb/pad, переназначение), `systems/controls.gd` (`Game.controls`: чем играют `mode`, прицел `aim_world`, огонь, автоприцел/автоогонь, подписи кнопок `label`), `ui/touch_controls.gd` |
| HUD | `ui/hud.gd` (состояние), `ui/hud_draw.gd` (всё рисуется в `_draw`), `ui/inventory_ui.gd`, `ui/cursor_draw.gd` |
| Меню | `ui/menu.gd` (`Menu`) — оболочка: режимы main/pause/town, навигация (`show_screen`, `back`, `open_town`), Esc, перестройка при смене языка (`rebuild`). Каждый экран — свой класс в `ui/screens/` (`MainScreen`, `PauseScreen`, `SettingsScreen`, `ControlsScreen`, `ReleaseScreen`, `CustomScreen`, `HeroesScreen`, `ShopScreen`, `MysticScreen`, `WorkshopScreen`, `GuildScreen`, `HealerScreen`, `TreeScreen`, `ModsScreen`, `CodexScreen`) на основе `ui/menu_screen.gd` (`MenuScreen`: `build` / `refresh` / хуки `on_back`, `on_town_open`, `process`...); общие виджеты, цвета и тема — статический `ui/menu_kit.gd` (`MenuKit`) |
| Размер интерфейса и отступы | `ui/ui_fit.gd` |
| Звук / музыка | `systems/sfx.gd` (банки из `sfx/`), `systems/music.gd` (категории, фоновая подгрузка) |
| Переводы | `core/i18n.gd`, `core/util.gd` (`U.t`), `lang/ru.json` (норвежский — отдельный замороженный мод `Mods/Norwegian/`) |
| Моды | `core/mods.gd` (слои, скрипты, `validate`), `core/debug_log.gd` (`Game.debug_log`: `warn` / `error` / `info`), `ui/debug_console.gd` |
| Справочник и гайд | `systems/codex.gd`, `data/codex.json`, `data/guide.json` |
| Прогрев | `systems/warmup.gd` |

## Правила проекта

- **Нет сцен и ассетов-картинок:** узлы создаются кодом, графика — `draw_*` в `_draw()`.
- **Строки:** исходник — английский, всегда через `U.t("Text")`; форматирование после перевода: `U.t("Zone %d") % n`.
  Каждую новую строку добавить в **`lang/ru.json`** (у существительных `{text, lower, g}`,
  у прилагательных `{m, f, n}`). Пропуски видно командой отладчика `missing ru`.
- **Новая настройка:** ключ в `Settings.DEFAULTS` + строка `_slider`/`_check` в `Menu` (`_build_settings` или
  `_build_controls`) + чтение `Game.settings.get_value("key")`; реакция на изменение — `Game.settings.changed`.
- **Новый размер/обводка текста в `_draw`** → добавить в `Warmup.REGULAR` / `Warmup.BOLD`, иначе фриз в бою.
- **Подсказки с кнопками** — не хардкодить «[E]»: `Game.controls.label("interact")` (на сенсоре — пусто, там свои кнопки).
- **Пушки/перки/марки/легендарки** — данными в `data/*.json`; новое поведение снаряда — поле в `Gun` +
  копирование в `Projectiles.fire_gun()`/`_clone()` + логика в `_step()`; тег перка — ещё в `Mods.KNOWN_TAGS`,
  `special` легендарки — в `GunData.SPECIALS` (одна запись: id → описание; по ней же проверяет `Mods.validate` и рисует справочник).
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
| Баланс урона/здоровья по зонам | `Balance.ENEMY_HP_GROWTH` / `GUN_DMG_GROWTH`, `enemy_dmg_mult`; после зоны `FLAT_FROM` (200) кривые врагов сшиты с силой «эталонной сборки» героя (`ref_*`, `FLAT_RISE`) |
| Отложенные задачи | `TODO.md` |
| Шансы редкостей, перков, гибридов | `data/rarities.json`, `GunGen.roll_rarity` |
| Новый тип пушки / марка / перк / легендарка | `data/*.json` + `lang/ru.json` |
| Новый враг | `EnemyData.TYPES` + ветка в `Enemy._behave` + описание в `data/codex.json` (`enemies`) |
| Свойство элитки | `EnemyData.AFFIXES` + `Enemy._tick_affixes` + `data/codex.json` (`affixes`) |
| Атака босса | `Boss.PATTERNS` / `DURATION` + обработка в `boss.gd` |
| Новый биом | `Biomes.LIST` |
| Лут и монеты с врагов/сундуков/боссов | `Rewards` (`systems/rewards.gd`: смерть врага/босса), `Loot` (`systems/loot.gd`: дроп, сундуки) |
| Новый перк навыка | `Heroes.PERKS` + эффект: попадание навыком — `systems/skills.gd` (`hit`, `explode`), применение — `Player._use_skill` / `_bless_proj` + строки и справочник (`heroes`) |
| Новый вид задания | `Quests.TYPES` + вызов `Quests.progress("вид")` в нужном месте + строки |
| Новый навык дерева | запись в `data/skill_tree.json` (эффекты — `stat` из `LevelTree.KNOWN_STATS`; нужен новый stat — добавить в `KNOWN_STATS` и прочитать там, где он действует) + строки `ru` |
| Новый герой / навык | `Heroes.LIST` + ветка в `Player._use_skill` (+ рисунок в `Player._draw`) + строки в `lang/*.json` + страница `heroes` в `data/codex.json` |
| Новый экран меню | класс-наследник `MenuScreen` в `ui/screens/` (`build(root)` через `_screen(root, "id")`, `refresh()`), создать в `Menu._make_screens()` (порядок = порядок построения), открыть `Menu.show_screen("id")` / `open_town("id")`; виджеты — `MenuKit`; строки — `U.t`, `ru` |
| Новый источник карт (редактор, мир «Диаблоида») | наследник `ZoneSource` (`world/zone_source.gd`: `zone(level, rng)` и `town(next_level, rng)` возвращают словарь для `Zone.setup`), подставить в `Main.loader.source` (по умолчанию `ProceduralZoneSource`) |
| Лавка, открывающая экран меню | `Stall.KINDS[...]["menu"]` → `Menu.open_town(экран)`; «Назад» — `Menu.back()` |
| Вид/имена городов | `Biomes.LIST` (`town`, `town_style`), `TownGen.SUFFIXES`; переводы ключей `"Dust-"`, `"-ville"` |
| Управление по умолчанию | `InputSetup.DEFAULTS` (+ `REBINDABLE` для меню) |
| Экранные кнопки | `TouchControls.ELEMENTS` |
| Страница справочника | `data/codex.json` |
