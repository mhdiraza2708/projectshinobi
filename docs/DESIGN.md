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
| **Blender 4.5 LTS**, scripted | `art/blender/build_assets.py` generates blockout models reproducibly and exports glTF. Real art replaces them later, keeping the same node names (the procedural animator looks up `Hips`, `Torso`, `Head`, `ArmL/R`, `LegL/R`). |
| **Cel shading** | Toon diffuse/specular + inverted-hull outlines (`scripts/world/toon.gd`). A custom anime shader (ramp textures, face shadow maps) is an M2 upgrade. |
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

  Future forms: clone, substitution, summon, trap/seal, genjutsu (status
  effects), transformation, beam/channelled, and clash (two projectiles
  colliding and resolving by element).

- `JutsuRegistry` loads every `*.json` file and rejects bad data, duplicate
  ids and duplicate seal sequences.
- `JutsuCaster` spends chakra, tracks cooldowns, and spawns the form's
  effect. Projectile collision is swept in sub-steps, so fast jutsu can't
  tunnel through targets. A sequence that matches nothing is a **misfire**
  and costs a little chakra.

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
| M2 Feel | Real animation (rigged character, ideally mocap/Mixamo-style clips), hit-stop, VFX pass, audio, camera polish | ⏳ |
| M3 Opponent | One AI shinobi that weaves, guards, dashes and uses walls. The goal is to prove the combat loop is fun 1v1. | ⏳ |
| M4 Content | 30–50 jutsu, new forms (clone, substitution, summon), 2–3 arenas | ⏳ |
| M5 Structure | Decide the game type: arena fighter, or action-RPG with a story. This decides everything after it. | ⏳ |

**Open decision for M5:** an arena fighter (like *Storm*) needs far less
content than an open-world RPG, and is the realistic scope for a small team.
