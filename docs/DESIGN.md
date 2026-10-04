# Project Shinobi: Design Document

## 1. Reality check (read this first)

**"AAA" describes a budget, not a quality bar you can aim for.** AAA games
are made by hundreds of people over three to six years, with budgets from
tens of millions to hundreds of millions of dollars. The Naruto *Ultimate
Ninja Storm* series was built by a full studio (CyberConnect2) using licensed
assets. A solo developer, even with AI help, will not match that. Aiming for
it anyway leads to an unfinished project.

What *is* achievable: a **polished, stylised, focused** game, with the
production values of a strong indie or "AA" title. Stylised anime cel-shading
suits this genre anyway and is far cheaper than photorealism. The plan below
aims there: a small amount of content, finished to a high standard, rather
than a huge amount that never ships.

**"All the jutsu in the Naruto universe" is not a realistic content target.**
Fan wikis list well over a thousand techniques. Many of them are one-off plot
devices (time-space ninjutsu, reanimation, and so on) that would each need
their own gameplay system. The architecture here makes adding a jutsu cheap
(one JSON entry when its *form* already exists). Even so, each technique still
needs VFX, sound, animation and balancing. A good launch target is 30–50 jutsu
that each feel distinct.

## 2. Intellectual property

Naruto (the names, characters, villages, clan abilities, specific techniques
like Rasengan or Chidori, and the art style of specific characters) is owned
by Masashi Kishimoto and Shueisha and licensed to Bandai Namco for games.
**A game using that IP cannot be sold, and a free fan game can still be taken
down.** This has happened to many fan projects.

This project is therefore an **original shinobi setting**:

- Game *mechanics* are not protected by copyright, so hand seals, chakra
  natures, an elemental advantage cycle, and weaving to cast are all usable.
- The 12 seals are named after the Chinese zodiac, which is public domain.
- Every jutsu name, description and seal sequence here is original. Canon seal
  sequences are deliberately not copied.
- Characters, villages and story must be original too.
- Generic Japanese terms are fine as categories: the eye techniques are
  called *dojutsu* (瞳術, "eye technique") and sword work *kenjutsu* (剣術).
  What stays off-limits is canon *named* abilities (no Sharingan, Byakugan,
  Rinnegan and so on); every dojutsu here has its own original name.

If you ever get an official licence, the data-driven design means a reskin is
mostly a data and art swap.

## 3. Pillars

1. **Hands are the weapon.** Casting is a skill: weaving seals quickly under
   pressure is the core mastery curve. Quick-cast slots keep it accessible.
2. **Readable elemental combat.** Fire > Wind > Lightning > Earth > Water >
   Fire. A matchup hit shows WEAK!/RESIST and is worth ±50%.
3. **Plays great on any device.** Keyboard/mouse and controller are equal,
   first-class citizens, and remapping and accessibility are built in from day
   one, not bolted on at the end.

## 4. Tech choices

| Choice | Why |
|---|---|
| **Godot 4.7** (GDScript) | Free and open source with no royalties. The whole project is plain text, so it diffs, merges and can be reviewed or edited by AI tools. It runs headless for automated tests and CI. Forward+ renderer for high-end looks. |
| **VRoid Studio → VRM** for characters | Free, anime-quality, fully rigged characters with spring-bone hair and cloth. They are imported by the MIT [godot-vrm](https://github.com/V-Sekai/godot-vrm) addon with the MToon anime shader. See [CHARACTERS.md](CHARACTERS.md). |
| **Mixamo** for locomotion clips | Free motion-capture animation, retargeted to Godot's humanoid profile. Hand seals stay procedural (IK), since no library has them. |
| **Blender 4.5 LTS**, scripted | `art/blender/build_assets.py` generates environment blockouts reproducibly and exports glTF. They get replaced by Poly Haven (CC0) and bought kits. |
| **Cel shading** | Characters use MToon. Blockout props use toon diffuse/specular + inverted-hull outlines (`scripts/world/toon.gd`). |
| **JSON jutsu data** | Easy to author in bulk, validated strictly on load (unknown keys, bad seals and duplicate sequences are all errors). |

Honest trade-off: Unreal Engine 5 has better out-of-the-box visual fidelity.
But its Blueprints and assets are binary, it needs a heavyweight toolchain,
and it is much harder to automate and test. For a small team that is the
wrong trade.

## 5. Core systems

### Input (`game/scripts/input`, `game/autoload/settings.gd`, `input_device.gd`)
- Gameplay actions are defined once in `DefaultBindings.table()`. Each action
  has a label, a menu group, bindings, and *contexts*.
- Actions conflict only if they share a context. This lets WASD mean
  "move" in the field and "seal direction" while weaving.
- Keys are bound by **physical** position, so AZERTY/QWERTZ players get the
  same layout.
- Player overrides are saved in `user://settings.cfg`. Rebinding onto an
  in-use input swaps the two actions.
- `InputDevice` tracks the last device touched, detects the pad family for
  glyphs, and handles rumble (respecting the vibration setting).

### Jutsu (`game/scripts/jutsu`, `game/autoload/jutsu_registry.gd`, `game/data/jutsu`)
- `Seal`: 12 seals, input as bank × direction (see [CONTROLS.md](CONTROLS.md)).
- `SealWeaver`: a pure state machine (begin, add seal, timeout, finish,
  cancel), with no engine input inside. It is fully unit-tested.
- `JutsuDefinition`: one technique. The **form** decides behaviour:

  | Form | Behaviour | Example |
  |---|---|---|
  | projectile | Flies forward (fans out if `count` > 1), homes gently on the lock-on target | Ember Volley |
  | area | Instant burst, either around the caster or `range` metres ahead | Quake Stomp |
  | wall | Rises from the ground and blocks projectiles for `duration` seconds | Stone Bulwark |
  | buff | Temporary modifier to move speed, damage reduction or attack power | Storm Mantle |
  | heal | Restores health | Mending Palm |
  | summon | Chakra doubles of the caster fight on its side for `duration` seconds (`count`, `health`, `power` = how hard they hit relative to a chunin) | Shade Clones |

  Future forms: substitution, trap/seal, genjutsu (status effects),
  transformation, beam/channelled, and clash (two projectiles colliding and
  resolving by element).

  Shade Clones reuse the enemy shinobi AI on the player's team: each clone is
  an `EnemyShinobi` wearing the player's look, following its owner and
  picking foes. Enemies target them like anyone else, so they draw fire.

- `JutsuRegistry` loads every `*.json` file and rejects bad data, duplicate
  ids and duplicate seal sequences.
- `JutsuCaster` spends chakra, tracks cooldowns, and spawns the form's
  effect. Projectile collision is swept in sub-steps, so fast jutsu can't
  tunnel through targets. A sequence that matches nothing is a **misfire**
  and costs a little chakra.

### Clans, eye arts, loadouts and saves
- **Clans and eye arts** (`Perks`, `game/data/clans.json`, `eye_arts.json`)
  are data. Each grants named perks: fractions (`max_health`, `chakra_regen`,
  `move_speed`, `dash_cooldown`, `damage`, `damage_<element>`, `cost`, `heal`,
  `guard`, `cast_speed`, `clone_time`, `lock_range`, `homing`,
  `enemy_seal_slow`) and flags (`clones`, `reads_natures`, `dodge_focus`,
  `perfect_guard`). `Perks.value()` adds the clan's and the chosen eye art's;
  the game reads it where it matters (player stats, caster cost and damage,
  lock-on, enemy weaving). The loader rejects unknown perks and elements.
  A clan lists which eye arts it allows. **Every clan and eye art is original**:
  no canon clans, no named dojutsu (see section 2). Rename or retune them in
  the JSON.
- **Skill trees** (`SkillTrees`, `game/data/skill_trees.json`,
  `SkillTreePanel`): XP (`Game.add_xp`) comes from defeated enemies (by rank,
  bosses more; not clones, allies or dismissed foes), story chapters (a first
  clear is worth 5x a replay) and trial wins (plus a bonus for a record).
  Level L needs `first + step * (L - 1)` XP to reach L+1, to a cap of 80;
  each level is one point. A tree with `needs_eye_art` (Dojutsu) only
  takes points from a character with an eye art. The screen (`SkillScreen`)
  is the tree on paper (`SkillTreePanel`) over a SubViewport stage
  (`SkillStage`) with the player's model in a per-tree pose and camera.
  Each tree is 8 nodes on a 3-column, 5-tier grid:
  `requires` is any one of the listed nodes, and a tier also needs
  `tier_points` already spent in that tree. A node's `perks` (the same keys
  as clans, plus `max_chakra`, `charge_speed`, `ult_gain`, `nature_damage`,
  the eye's `eye_time`, `eye_cost`, `eye_cooldown`, `eye_power`, the
  blade's `strike_damage`, `strike_speed`, `strike_reach`, `finisher`,
  `strike_chakra`, and the flags `counter_strike`, `guard_break`,
  `blade_wave`,
  `second_wind`, `twin_weave`, `shadow_bloom`, `eye_flash`, `eye_extend`,
  `eye_sustain`) are multiplied by its
  rank and added in `Perks.value()`, so they apply wherever perks already do;
  the player re-reads them the moment a rank is learned. XP and ranks live in
  the slot's `records.cfg`; a reset refunds everything. All names original.
- **Loadouts** (`Loadouts`): presets of 8 quick-cast slots, each slot a jutsu
  and a cast style (`weave` forms the seals for you, `instant` skips them for
  +35% chakra). They live in the Profile, so they are saved per slot.
- **Saves** (`SaveSlots`, `Profile`, `Game`): ten slot folders under
  `user://saves/slot_N/` hold `profile.cfg` (the shinobi) and `records.cfg`
  (story progress, trial times, play time). With no slot active nothing is
  written. Settings stay global in `user://settings.cfg`. A pre-slot
  `user://profile.cfg` is migrated into slot 1 on first run.

- **Ultimates** (`Ultimates`, `UltimateSequence`, `game/data/ultimates.json`):
  the meter (0-100) fills from damage dealt (0.35/pt, a shade clone's counts
  for its owner, through `Combat.apply_hit`), damage taken (0.6/pt),
  interrupts (+10) and perfect guards (+8). Unleashing one freezes every
  fighter, projectile and dummy (process disabled, collisions kept so the
  blow can find them), plays a close-up and a wide shot, deals `power` to
  everyone within `radius` of the target, then restores the world. Each
  ultimate is data (name, kanji, nature, `style` = meteor, cyclone, chain,
  fist, wave or shades, power, radius); styles are code. All names original.

### Open world (`game/scripts/world/archipelago.gd`, `open_world.gd`, `game/scripts/quests`)
- **Archipelago** places every island preset at a `LAYOUT` offset (a summit
  is lifted by its `plateau` so its own sea level meets the shared one) and
  builds them nearest first, one a frame. Islands built with `open_world`
  skip their own sea, wall and horizon, make every tree solid and fade
  scenery past 520 m. One sea mesh follows the player; a
  `WorldBoundaryShape3D` at `SEA_LEVEL` makes the sea walkable. Leap stones
  (`LeapStone`) arc the player up and down Five Winds' cliffs.
- **Chapters in place:** chapters are written with their island at the
  origin, so `focus_on(id)` shifts the whole archipelago (and the player) to
  put it there, an `ArenaWall` rings the clearing, and the chapter plays as
  written. `return_to_world()` lifts the wall and resumes free roam.
- **Quests** (`Quests`, `game/data/quests.json`): the main quest is the next
  chapter not cleared (a `QuestBeacon` pillar at its `player_at`); side
  quests have a giver, an island, a `requires` (chapter or quest) and a type:
  `gather` (items at seeded spots on dry land), `defeat` (TrialDirector waves
  at a spot, which now take a `center` and per-enemy natures), `duel` (the
  giver becomes a named foe) or `deliver` (talk to `to` on another island).
  State lives in the slot's records (`quests` section); XP on completion.
  `OpenWorld` keeps one figure per person and decides what talking to them
  means; `QuestTracker` draws the tracked objective, an edge-pinned marker,
  the Interact prompt and island arrival cards.
- **Day and night:** `OpenWorld.clock` runs a `DAY_LENGTH` day through
  `PHASES`; a change calls `transition_time()`, which crossfades the sky
  shader (`prev_panorama` + `blend`) and eases the sun, ambient and fog.
  Each sky's `LOOKS` entry (`skies.gd`) also grades it to the hour: a sun
  colour and height of its own (dusk's is low and orange), a `tint` over
  the whole sky and a `horizon_tint` near the horizon, the sun's halo and
  the fog colour. The shader lowers the photo's sun to the game's with a
  vertical squeeze (`elevations`), so the disc, the clouds around it and
  the light agree.
- **Ambient life:** `Ambience` (a child of the game scene) is told the
  island under the player, the hour and the weather every frame
  (`ambient_island()` is the story island, or the one underfoot in free
  roam) and keeps one or two particle emitters in a box around the player:
  embers and ash, leaves, snow, mist, wind, pollen and petals, and
  fireflies at night. Sets fade over `FADE` seconds, start over after a
  jump (fast travel, a chapter shifting the world), and shrink with the
  graphics preset (`Ambience.density()`: none on Low).
- **Map and travel:** `WorldMap` paints a chart from every island's real
  heights once per world (4 m a pixel). Islands are `discovered` when you
  set foot on them (saved in records); `fast_travel()` uses the summoning
  seal to set you by a discovered island's clearing.

### Combat (`game/scripts/combat`, `game/scripts/player`)
- `Stats`: health, chakra (passive regen plus much faster regen while
  charging), elemental affinity, guard multiplier, i-frames, and timed
  modifiers that refresh rather than stack.
- `Player`: a state machine (FREE, WEAVING, AUTO_WEAVING, CHARGING,
  GUARDING, DASHING). While weaving, the character plants their feet and
  field actions are ignored, which is what lets the seal inputs reuse the
  movement keys and face buttons. A hit of 10+ damage interrupts a weave.
- Anything with `take_hit(amount, element, source)` can be damaged.

### Adding a jutsu
Add an entry to the matching `game/data/jutsu/<element>.json` file:

```json
{
  "id": "tide_lance",
  "name": "Tide Lance",
  "description": "A spear of high-pressure water.",
  "rank": "C",
  "element": "water",
  "form": "projectile",
  "seals": ["rat", "snake", "ram"],
  "chakra_cost": 15,
  "cooldown": 2.5,
  "power": 18,
  "speed": 32,
  "range": 30,
  "radius": 0.35
}
```

Then run the tests. They fail if the entry is invalid or collides with an
existing sequence.

## 6. Roadmap

| Milestone | Goal | Status |
|---|---|---|
| M0 Foundation | Input layer, seal weaving, jutsu data and validation, tests, CI | ✅ |
| M1 Training ground | Playable third-person slice: movement, strikes, kunai, all 5 jutsu forms, dummies with element affinities, HUD, pause menu with rebinding and accessibility options | ✅ |
| M2 Feel | Real animation (rigged character, ideally mocap/Mixamo-style clips), hit-stop, VFX pass, audio, camera polish | 🟡 VRM characters, IK poses, Mixamo support and synthesised sound effects are done. Still needed: hit-stop, VFX and music. |
| M3 Opponent | AI shinobi that weave (readable and interruptible), guard, dodge, throw and strike. The goal is to prove the combat loop is fun. | 🟡 Trial of the Five Natures (5 waves) is playable. Walls and heals for enemies, and a real 1v1 duel, are still to do. |
| M4 Content | 30–50 jutsu, new forms (clone, substitution, summon), 2–3 arenas | ⏳ |
| M5 Structure | Decided: a **chapter-based story game** (scene, fight, scene), plus Trials and Training as side modes. Not open-world. | 🟡 Part One (5 chapters) is playable. Still needed: more locations, then Part Two. |

**Open decision for M5:** an arena fighter (like *Storm*) needs far less
content than an open-world RPG, and is the realistic scope for a small team.
