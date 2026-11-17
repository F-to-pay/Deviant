# Changelog

## 0.1.1

### Heroes
- **Engineer** (35 ancient coins). Skill — a turret, lobbed like a mortar shell to the aim point (10 s cooldown). It takes all the rounds left in your
  active gun's magazine and you reload (free for a Synergis gun), has your health and shoots the nearest visible enemies with a copy of your gun.
  Enemies go for whichever is closer — the turret or you. It stands until smashed, but is destroyed the moment the magazine runs dry. Its bullets deal 50% of the gun's damage and it fires at the gun's effective range. Taking a hit knocks nearby enemies away and stuns them for 1 s.
  At most as many turrets as skill charges; a new one beyond the limit removes the oldest. Skill perks: Extra Hand, Economy (+40% rounds), Mad Scientist (a random Synergis gun
  one rarity higher, nothing taken from your reserve, once), Element. Grievous Wounds is now offered only to the Pioneer, Sheriff and Assassin.
- Enemies and bosses now pick the nearest target (`Main.target_for`): the hero or a turret.

### Touch controls
- **Aimed skills.** On touch the Pioneer's grenade and the Assassin's slash get their own aim stick: hold the Skill button and drag, release to throw / strike.
  A preview is drawn while you aim (landing circle and range ring for the grenade, strike sector for the slash). A plain tap uses the gun's aim, as before.
  The Sheriff's blessing has no direction and still fires instantly.
- **Tap a weapon slot** at the bottom of the screen to select that gun.

### Bosses
- Fixed bosses running into walls: the charge now only starts with a clear line to you and enough room ahead,
  stops before obstacles, and otherwise the boss walks to a good position along the A* path first (and skips the charge if it can't get one in 3 s).
- Fixed the boss pathfinding failing in tight arenas (the search for the nearest free spot is now wider for large bodies).
- New boss **Anti-Player** (from zone 10, 50% instead of the usual boss): a mirror of you that shoots the best gun you found from its effective range (max 15 m), backs off and dashes, and uses your hero's skill. Its health grows with the zone like any enemy's.
- New boss pattern **Seekers**: a ring of slow orbs (8, 12 when enraged) that curve towards you at about 10° per second. Described in the Codex.

### Zones and pacing
- Zones are smaller and have fewer enemies, aiming at ~4 minutes per zone instead of ~6:
  map side `64 + zone` (max 88) instead of `90 + zone` (max 120); packs `14 + zone/2` (max 28) instead of `20 + zone` (max 42).
- Coin income per zone is unchanged: every kill pays proportionally more (`Game.COIN_REF_ENEMIES`).

### Legendaries
- **Granny's Surprise** and **Monday** are always made by Dandy; Monday has at least 85% accuracy.
- **Bee Swarm** is always made by Errosion and always has acid.
- **Toaster of Fate**: the bullet ring now deals 100% damage (was 40%).
- **Neighbor with a Hammer Drill**: ricochets no longer reduce damage (new special `bounce_keep`).
- **Hedgehog in the Fog**: fixed the base order, it now fires grenades with the SMG pattern instead of plain SMG bullets.
- **Quantum** perk reworked: projectiles blink only to the nearest enemy ahead (up to 260 px) and stop right in front of it; no more overshooting and no hit-list reset.
- **Black hole** (Pocket Singularity, Gravity perk) is weaker as crowd control: smaller radius (120), half the pull, 1.2 s, max 4 at once, nearby holes merge instead of stacking, and elites resist the pull.
- Legendary modding: new `maker` and `min_accuracy` fields, new special `bounce_keep` (see the guide).

### Experience (groundwork, no gameplay effect yet)
- XP is counted per run: an enemy gives `1 + 0.1 × (level − 1)` (elites and bosses weighted), a level needs `40 × L^1.1`.
  Summoned enemies give no XP.
- New `Director` (`scripts/systems/director.gd`) measures how much XP each zone holds. Debug overlay (F3) shows `LV / XP` and the zone's XP pool.

### Balance and other changes in this build
- Synergis guns (infinite ammo) now use their own ammo type, energy: no ammo drops or sells for them any more, and the starter Synergis no longer fills the reserve of its base type. Hybrid names (mortar-machine gun and so on) are unchanged; recycling a Synergis still gives rounds of its base type.
- Guns with infinite ammo (Synergis) no longer roll perks that spend more rounds per shot for more damage or projectiles (Double-Barreled and the like): with free ammo the cost was zero.
- Workshop no longer raises a gun's level (guns are meant to go stale); it still rerolls perks and raises rarity.
- Skill changes: grenade explosion damage is flat across its radius; smoke grenade ticks 5 times a second; skill hits build up less elemental effect.
- Gun generator: shotguns roll a random pellet count with the same total volley damage; a mortar in a hybrid always makes the shot arc.
- Enemy types have innate element resistances (that element is 50% weaker on them): brute — cryo, kamikaze — fire, gunner / spreader / mortarman — shock, shaman — curse, runner / charger — acid. Shown in the Codex enemy table.
- Skill elements now work like guns: 35% chance per hit, build-up scales with the skill's cooldown. Pioneer's grenade 35 → 30 damage; Poison perk +30% → +50%.
- Android export preset now includes x86_64.

*Not in this build:* meta perks (Relic Keeper), run saves, XP level effects.
