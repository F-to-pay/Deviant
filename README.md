# Deviant

An endless Diablo-like arcade shooter with Borderlands-style guns pushed into the absurd.
Top-down, twin-stick. The hero has no levels — all progression lives in the guns and the enemies.

## Running

1. Godot **4.4+** (written against 4.4–4.7 syntax). Renderer: Mobile (Vulkan); the web build falls back to Compatibility automatically.
2. **Music is not in the repository** (~150 MB). Download it once: `python tools/fetch_music.py` — it reads
   `music/SOURCES.txt` and fetches every track from Wikimedia Commons (all public domain / CC0).
   `--quality 0` re-encodes with ffmpeg to ~64 kbit/s for smaller builds. Without music the game just plays silently.
3. `Import` → pick `project.godot` → F5.
4. Export: the `data/` and `lang/` folders (JSON) must end up in the build — if they don't, add `data/*, lang/*`
   to "Filters to export non-resource files". Put the `Mods/` folder next to the exe (it is not packed into the build).
5. Android: JDK 17 + Android SDK (`platform-tools`, `build-tools`, `platforms`), paths in Editor Settings → Export → Android,
   and a release keystore in the Android preset (or export with "Export With Debug").

On start there is a loading screen (`systems/warmup.gd`). It warms up everything once that would otherwise
stutter mid-fight: compiles mod scripts, loads music in the background, rasterizes every glyph in every size/outline
the game draws, draws each kind of primitive so Vulkan compiles its shaders up front, and generates and draws one gun
of every type, maker, perk and legendary. It runs again after mods are toggled or rescanned.
New text size in code → add it to `Warmup.REGULAR` / `Warmup.BOLD`.

The project is under git: `git log` for history, tag `pre-refactor` — the state before data/translation/mods were split out.

There are no graphics assets: everything is geometry, procedural gun icons and the system font.
The only assets are audio: music in `music/` (classical recordings from Wikimedia Commons, public domain / CC0, list in
`music/SOURCES.txt`) and effects in `sfx/` (CC0: Free Firearm Sound Library, Kenney, OpenGameArt — `sfx/SOURCES.txt`).

## Controls

| Action | Keyboard & mouse | Gamepad |
|---|---|---|
| Move / aim / shoot | WASD, mouse, LMB | left stick (or D-pad), right stick, RT |
| Dodge (invulnerable, 4 s cooldown; 0.5 s if you actually dodged something) | Space / Shift / RMB | A / LT |
| Reload | R | X |
| Switch weapon | 1–4, wheel, Q — last one | LB / RB, left stick click — last one |
| Pick up to backpack / open chest | E | Y |
| Swap current gun with the one on the ground | F | right stick click |
| Scrap the gun on the ground for ammo | X | B |
| Inventory (pauses) | Tab / I | Back (stick moves a pointer, A — take/drag, Y — slot ↔ backpack) |
| Pause menu / debug overlay | Esc / F3 | Start |
| Music volume / mute | − and + (or numpad) / M | |
| Sound volume | [ and ] | |
| Mod debugger (if enabled in the Mods menu) | F8 | |

Everything except music/sound/debug keys can be rebound: Settings → Controls (keyboard and gamepad columns,
stored in the `binds` setting, `core/input_setup.gd`). Menus are navigable with A / B / D-pad / left stick.
The game detects what you are playing with (`systems/controls.gd`) and adapts hints, aiming and the cursor.

**Touch** (`ui/touch_controls.gd`): a move stick on the left, an aim stick on the right (tilt it to shoot), buttons for
dodge, reload, weapon switch, backpack and pause; Take / Swap / Scrap next to a gun on the ground, Open next to a chest.
Options in Settings → Controls:
- **Layout editor** — drag every control, change the size of each one (− / + next to the selected control);
  stored in `touch_layout`. Plus a global size slider.
- **Fixed sticks** — sticks stay in place instead of following the finger.
- **Tap to shoot** — instead of the right stick, a finger on the right side shoots at the point under it.
- **Auto-aim** (touch and gamepad) — shooting without manual aim targets the nearest enemy.
- **Auto-fire at visible enemies** (touch and gamepad) — shoots on its own while an enemy is on screen and in line of sight.
- Touch controls: Auto (when playing with fingers) / Always / Off.

To try touch on a PC without a touchscreen: enable `input_devices/pointing/emulate_touch_from_mouse` in Project Settings
and set touch controls to "Always".

## Menus and settings

The game starts in the main menu: New game, Custom start, Codex, Settings, Mods, Quit, language switch.
The background is a parade of random guns from the real generator (`ui/menu_bg.gd`); later it will be replaced by a demo with an AI player.

**Custom start** (`Game.RUN_DEFAULTS` / `Game.custom`, the last choice is saved in `[custom]`):
- difficulty: presets Easy (enemy health 80%, damage 50%) / Normal / Hard (120% / 120%) and manual sliders 10–200%;
- full heal on entering a new zone; no regular enemies (regular packs → champions, leader escorts too);
- chests on/off; hardcore — no health orbs and no Vampiric perk (legendary lifesteal is zeroed);
- chaos — all gun rarities equally likely, all enemy types available from zone 1 and equally likely,
  and every pack is 1/4 regular / champions / leader / **boss** (a wandering one: sleeps until you come close,
  smaller loot, no rift);
- starting gun: type and maker (or random); seed — a number or any text, empty — random.

**Rating** (any run) = points × multiplier. Points = (zone − 1) × 100 + kills + bosses × 250.
Multiplier = enemy health × enemy damage × (1 + bonuses): hardcore +100%, elites only +50%, chaos +25%,
no chests +25%, heal between zones −50% (`Game.RATING_BONUS`, `POINTS_*`). Easy ×0.4, Normal ×1, Hard ×1.44.
The multiplier is shown in Custom start and in the pause menu; rating and best rating — on the death screen and in the main menu.

The seed and the differences from a normal game are shown in the pause menu and on the death screen; R repeats the run with the
same parameters (a given seed gives the same world and loot). Best zone/kills only count with default settings.

Esc in game — pause menu (resume / settings / codex / main menu); on the death screen Esc goes to the main menu.

Settings (`Game.DEFAULTS`, stored in `user://deviant.cfg`, section `[settings]`): master volume, music (+ mute), game sounds,
interface sounds, fullscreen, V-Sync, screen shake (0–150%), damage numbers, FPS, interface size, screen-edge margins
(sides / top-bottom) and the phone's safe area (`ui/ui_fit.gd`), gun card position for guns on the ground
(right / left / above the gun). A new setting = a key in `DEFAULTS`, a `_slider`/`_check` line in `Menu._build_settings()`
and reading it via `Game.setting("key")`.

## Languages

The source language is English: strings in code and in `data/*.json` are the translation keys. Translations are
`lang/<code>.json` — Russian (`lang/ru.json`) and Norwegian Bokmål (`lang/nb.json`) are built in; the codex and the
modding guide are in all three languages. Mods can extend them or add new languages. The switch is the button under
Quit in the main menu (cycles through all languages found; setting `language`, defaults to the system language).
- In code: `U.t("Text")`; format strings are translated before substitution: `U.t("Zone %d") % n`.
- In a translation, nouns have a lower-case form and a gender (`{"text", "lower", "g"}`), adjectives have gender forms
  (`{"m", "f", "n"}`); word order in gun and enemy names is the language's `templates`. Details in `Mods/README.md`.
- Gun names are stored as "parts" (`Gun.name_parts`) and assembled by `GunGen.build_name()` in the current language —
  switching language mid-run renames guns you already have.
- A missing string is shown in English. TranslationServer is not used (its fallback locale leaked another language).

## Data and mods

Gun types, makers, perks, legendaries, rarities and name lists live in `data/*.json`; perk and maker effects are written as
operations on stats (`GunOps`), not code. Mods live in `Mods/<name>/` (next to the exe in an exported build),
mirror the game's layout (`data/`, `lang/`, `sfx/`, `music/`, their own `.gd`) and are toggled in the Mods menu.
Full description of the format, operations and scripts — **`Mods/README.md`**, example — `Mods/ExampleMod/`.
The mod debugger (a log of checks and errors + a console with `give`/`reload`/`validate`...) — F8; enable it in the
Mods menu, it works after a restart (`DebugLog`, `ui/debug_console.gd`).

**Codex** (main menu / pause → Codex, `systems/codex.gd`) — pages from `data/codex.json` of the game and mods:
character, damage and elements, zones and loot, gun types, makers, gun generation, perks, legendaries, enemies,
elites, bosses, rating, modding. Tables (`auto`) are built from the current data, so mod content shows up by itself.
The "How to make mods" page writes `modding_guide.txt` (`гайд_по_модам.txt` / `moddeguide.txt` in other languages)
next to the exe — the text from `data/guide.json` plus a reference of every loaded id.

## How a run works

- Every zone is an open procedural map (noise → rocks, chasms, acid/lava pools).
  Unreachable areas get walled off, the rift is placed at the point farthest from the spawn.
- Every zone = +1 level of loot and enemies. Enemy health grows 15% per zone, gun damage 14%,
  so old guns slowly go stale. Enemy damage grows linearly.
- Every 5th zone is a boss arena (random set of attack patterns, enrage at 50% HP).
- Elites like in Diablo: blue champion packs and yellow rare leaders with affixes
  (teleport, shield, orbitals, frost aura, explode on death...).
- No passive regen. Health orbs heal 10 HP, at most 2 per zone. Lifesteal is rare and capped at 4 HP/s.
  If it gets truly impossible — `ZONE_HEAL` in `main.gd` (heal on entering a zone).
- Every gun has "infinite" range (flies until it hits a wall), but past its effective range damage falls off sharply:
  +33% range → 37% damage, ×2 → 5%. Effective range is shown on the gun card.
- **Ammo** is shared per projectile type (a hybrid uses the second type's ammo: a shotgun-grenade launcher eats grenades).
  The reserve holds 4 base magazines of a type (`RESERVE_MAGS` in `gun_data.gd`). Sources: enemy drops
  (mostly for guns in your slots) and scrapping guns (X on the ground or over a gun in the inventory).
  New guns arrive with an empty magazine (`LOOT_GUN_LOADED`). The magazine is always a multiple of rounds per shot.
- Death = start over. The best zone is saved.

## Inventory

Drag with the mouse (or a finger, or the gamepad pointer): slot ↔ slot, slot ↔ backpack (onto an occupied cell — swap),
reorder inside the backpack; to the Drop zone or outside the window — onto the ground, to Recycle — into ammo (the zone shows
how much you will get). LMB click: slot — make it active, backpack — take into the active slot. RMB — slot ↔ backpack.
X over a gun — recycle. You can't drop or recycle your last gun in hand.

## Gun generator

`rarity → type (or hybrid) → maker → perks → legendary effect → random spread → zone scaling → name`

- **10 types**: pistol, revolver, SMG, assault rifle, shotgun, sniper rifle, rocket launcher, machine gun, grenade launcher, mortar.
  - **Revolver** — slower than the pistol, hits twice as hard, its own ammo.
  - **Mortar** — uses grenades. A shell flies in an arc to the aim point (no farther than its range) and explodes
    after 1 s. Spread = deviation of the landing point. Highest damage per shot, a magazine of 1 shell.
  - **Shotgun** — 30% chance to be born a "slug gun": one projectile with the whole volley's damage (×0.85), spread ×0.12, range ×2.
- **Hybrids** (from Rare and up): firing pattern from the first type, projectile from the second.
  That's how you get a "Shotgun-Grenade Launcher": 8 grenades in a fan.
- **11 makers** with a guaranteed effect:
  | Maker | Effect |
  |---|---|
  | Synergis | −40% damage, doesn't use reserve ammo, effects proc half as often, no explosions at all |
  | Hypernova | any type fires rockets but uses its own type's ammo (an SMG — SMG ammo); damage ×2, fire rate ×0.5, ammo per shot ×2 |
  | Sabbath | reload −70%, −10% damage |
  | Chaos Forge | always a random legendary perk, −40% damage, never a legendary itself |
  | Errosion | always an element, element chance ×2, −25% damage |
  | Atlas | no effect perks, +20% damage |
  | Downpour | +60% fire rate, −20% damage |
  | Dandy | always scattering pellets (Scattering perk), −15% damage |
  | Noname | no signature effect |
  | Godforce | damage ×3, fire rate ×0.3, ammo per shot ×3, crit ×1.5 |
  | BOARDING | magazine 30%, projectile speed ×3 (same range), +40% damage, knockback ×2 |
  The starting pistol is always a Synergis.
  Hypernova, Chaos Forge, Atlas and Godforce never appear on legendaries.
- **37 perks**: grenades, rockets, ricochet, piercing, splitting, fractal splitting, boomerang, wave flight,
  chain lightning, cluster bombs, "seeding" projectiles, quantum teleport, nuke, and so on.
  Piercing, lifesteal and black holes are rare (Epic and up). Black hole chance depends on the damage of a single projectile,
  so a machine gun barely ever procs it. Bullets explode by chance, rockets and grenades always.
- Explosions: 100% damage at the center → 20% at the edge; your own explosions hurt you too, but 10 times less.
- Acid and cryo build up linearly: a second of firing any gun gives +10% (+20% with Errosion). Acid — up to +50% damage taken,
  cryo — slow up to 40%, freeze for 1.3 s at 50%. 3 s without hits — reset. Champions build up 1.5 times slower, leaders 2, bosses 3.
- **Shock**: on proc hits 2 neighbours for 35% and stuns the target for 0.5 s (champion/leader/boss — 0.33/0.25/0.17 s),
  then 1 s of stun immunity (× resistance).
- **Curse** (5th element, gun damage −20%): builds up +40% per second of hits; at 100% deals 30% of the target's missing
  health and resets. Champions/leaders/bosses build up 1.5/2/3 times slower and take that many times less (20%/15%/10% of missing).
- Every bullet ricochet cuts 30% of damage (grenade bounces don't).
- Effect perks (homing, splitting, elements, piercing...) are rolled after stat perks and stay with chance
  4 / (fire rate × projectiles per shot), up to 100%. If one fails, the slot gets a regular perk.
- **Proc coefficient** (like in Risk of Rain): every "by chance" effect — elements, explosions, chain lightning — is
  multiplied by the projectile's "weight" (damage without level scaling / 40, from 0.08 to 1).
  Small fast bullets rarely proc, heavy ones almost always. The Last Word's nuke charges from damage, not shot count.
  Guns don't give HP — only armor (−15% damage taken per perk).
- **6 rarities**, the last one is "Absurd": 5 perks with no compatibility restrictions.
- **12 legendaries** with unique effects ("Granny's Surprise", "Last Word", "Schrödinger's Cat"...).

## Music

`scripts/systems/music.gd` scans `res://music/` (with subfolders) by itself. A track's category comes from the file prefix,
otherwise from the folder name: `zone_` — zones, `boss_` — boss, `calm_` — pause and the rest after a boss, `death_` — death,
`menu_` — main menu. A new track = drop an `.ogg` with the right prefix. A nice title for the "♪ …" banner — in `Music.TITLES`.

- Zones: a shuffled playlist without repeats; a track isn't cut when moving between zones.
- Boss — its own track, after the win — a calm one. Esc switches to calm music and later resumes the interrupted track from the same spot.
- The inventory muffles the music (quieter + low-pass filter).
- The next track of each category is chosen in advance and loaded in the background (`load_threaded_request` / `WorkerThreadPool`),
  so track changes don't stutter.
- Volume — the `Music` bus (created in code along with `SFX` and `UI`), saved in `user://deviant.cfg`.
  Game sounds go to the `SFX` bus, interface sounds (all `ui/...` keys) to `UI`; each has its own slider in settings.

## Sounds

`scripts/systems/sfx.gd` scans `res://sfx/`: a folder = a bank that plays a random file
(`sfx/guns/shotgun/*` → key `guns/shotgun`), a single file is available by its path without extension (`reload/pistol`).
A new shot variant = drop a `.wav` into the type's folder. Volume/pitch per type and maker — `"sound"` in
`data/archetypes.json` and `data/makers.json`.

- The shot sound follows the type (the first one for a hybrid). If the projectile is of another kind (Hypernova rockets,
  the grenade perk) — its sound is layered quietly on top.
- Machine gun = rifle shots pitched down, Godforce — lower and louder, Downpour and BOARDING — higher.
- The higher the fire rate, the quieter each shot; at most 4 voices per key, extra ones steal their own oldest.
- Reload sounds speed up if the reload is shorter than the recording (Sabbath). An empty magazine clicks.
- Explosions: the bigger the radius, the lower and louder; `big` is a separate low-frequency bank.
- Events are bank folders: `ui/` (menu, inventory, weapon switch, recycle, error), `pickup/` (gun, legendary,
  ammo, health), `world/` (chest, rift, new zone), `hit/` (wall, enemy, body), `player/` (hurt, dodge,
  perfect dodge, death), `enemy/` (shot, shield/teleport, windup, summon, death), `boss/` (appear, enrage, death),
  `el/` (fire, shock, acid, freeze, curse), `fx/vortex`. An empty folder — the event is silent; drop a file in and it works.
  Calling from code: `Sfx.at("key", position, dB)` or `Sfx.ui("key", dB)`.

## Where things are

```
scripts/
  main.gd               root: zones, spawning, loot, camera
  core/                 Game autoload, utilities, input setup, spatial hash, i18n, mods (mod loader), debug log
  weapons/              gun_data (table loading), gun_ops (stat operations), gun_gen (generator),
                        gun (stats), gun_icon (drawing)
  systems/              projectiles (all bullets as data), combat (damage/explosions/chains), fx, music, sfx,
                        controls (input devices, aiming), codex, warmup (loading screen)
  world/                zone (grid, collisions, flow field), zone_gen, biomes, rift, chests, loot
  entities/             actor (statuses), player, enemy, boss, enemy_data
  ui/                   hud, hud_draw, gun_card, inventory_ui, cursor_draw, menu, menu_bg, touch_controls,
                        ui_fit (interface size and margins), debug_console
data/                   archetypes, makers, perks, legendaries, rarities, names, codex, guide (JSON)
lang/                   translations (ru.json, nb.json)
Mods/                   mods (+ README for modders, ExampleMod)
```

## Want more absurdity — where to dig

- A new type/maker/perk/legendary: an entry in `data/*.json` (or in a mod) + translations in `lang/*.json`.
  If it needs new projectile behaviour — a field in `Gun`, copying in `Projectiles.fire_gun()`/`_clone()`,
  logic in `_step()`; after that it can be set by operations from JSON.
- A new legendary special (`special`) — code in `player.gd`/`projectiles.gd`.
- A new enemy: an entry in `EnemyData.TYPES` + a branch in `Enemy._behave()`.
- A new biome: an entry in `Biomes.LIST`.
- Balance curves: `game.gd` → `enemy_hp_mult / enemy_dmg_mult / gun_dmg_mult`.

## Not there yet

Meta-progression between runs, zone events (traders, timed waves, mimics), character builds/passives,
saving a run mid-game, balance testing past the first dozen zones.
