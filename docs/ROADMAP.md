# Roadmap and handoff

Where Project Shinobi stands and what comes next, in the order it should be
done. Written so a new session can pick the work up cold.

## Where things stand

- **Playable and shipped:** the main character, the five Tripo rivals plus
  the rogue elite, Nue, and seven of the eight story characters in their own
  Tripo models (Hisame is still her VRoid model; her Tripo model is
  missing). Over-the-shoulder camera, two rush jutsu, height and headband
  size sliders, enemy difficulty that grows with the story part
  (`scripts/enemies/enemy_tier.gd`, see STORY.md), the 60-second trailer.
- **Merged but not yet the game's world:** the streamed procedural
  continent (`scripts/world/continent/`, 13 tests). It is a prototype. Try it
  with `--demo=continent_aerial` and `--demo=continent`.
- **The honest problem:** a full playthrough takes about 30 minutes (17
  missions, under two minutes each). The target is far longer, see below.

## Phase 2: the continent becomes the world

The open world is `Archipelago` (six islands in a sea, `LAYOUT`) driven by
`OpenWorld`. Story missions are written with their island at the origin;
`Archipelago.focus_on()` shifts the whole world to put the chapter's island
there. The continent has the same six regions (`ContinentLand`), each with
a flat pad, so the same trick can carry over.

Surface to replicate on the continent: `focus_on`, the `rebased` signal,
the region centres (`LAYOUT`), `islands` lookups used by `OpenWorld` (about
30 uses), the `WorldMap` and `Quests` positions, water running and the sprint
bonus, Five Winds' leap stones, and day/night and ambience per region.

1. **Drop-in world.** A continent-backed world with the Archipelago's API,
   behind a switch, regions standing where the islands' props and clearings
   are now (reuse `Island` prop lists and `model_meshes.gd`). Story missions
   play on it unchanged.
2. **Map, fast travel, quests and day/night** on the continent. Quests keep
   their island ids as region ids.
3. **Density.** Roads between regions, villages, camps, shrines, per-region
   palettes (the prototype is bright Emberwood green everywhere), landmarks
   a player can navigate by. This is what makes it feel like a world, and
   it is the largest part.
4. **Switch the default,** retire the islands, performance pass, tests.

Rough effort: several long sessions. A firm date is not possible: the real
limit is the usage windows, which have stopped this project twice.

## How long the game should be

The target is 35-40 hours for a completionist. Authored story cannot carry
that (a mission takes hours to build, voice and test), so the hours come
from layers:

- **Main story, 8-10 h:** about ten parts, ~40 longer missions with new
  mechanics (stealth, escort, chase, duels with rules), real bosses.
- **Open world, 15-20 h:** bounty contracts, enemy camps, shrines,
  collectibles, a rival-clan war that changes the map, named rivals to hunt.
  Needs phase 2.
- **Replay, 10+ h:** New Game+, a harder difficulty tier, boss rush, timed
  Trials, skill-tree completion.

## Bosses

Harder means new mechanics, not health (tiers already scale that). Each of
Asahi, Iwao, Kagerou, Tsumugi and Nue gets two or three signature mechanics
and new phases, with readable tells: rock walls and quake zones, a clone
ambush, lightning dash chains, arena changes. About a day of work each.

## Voices

Current voices are Kokoro (local, free, ~258 lines, ~16,900 characters).
They sound synthetic. Plan: a hosted voice service (ElevenLabs was
recommended: designed voices per character and a pronunciation dictionary).

1. The owner makes the account (a plan that allows **commercial use**) and a
   key with only text-to-speech and voice-reading permissions.
2. They add it to the environment as `ELEVENLABS_API_KEY` (cloud
   environment menu, Edit, Network secrets or environment variable) and allow
   the host `api.elevenlabs.io`. **Never paste the key into the chat.** Only a
   new session picks it up.
3. Audition 2-3 candidate voices for Hisame, Asahi, Kagerou and Nue on the
   same line; the owner chooses by ear (an assistant cannot hear them).
4. Record all lines into the same files (`game/assets/audio/voice/<who>/
   <key>.ogg`, keys from `art/audio/make_voices.py`) so the game needs no
   change. The shinobi terms and names already have phoneme spellings in
   `make_voices.py` (`NAMES`, `TERMS`); a pronunciation dictionary needs
   them as IPA. Check every line with speech recognition for intelligibility.

Do this last, once the script stops changing; more story means more lines.

## Known issues

- On Ashen Pass, enemies were reported stuck "in the rock walls". Fighters
  could be spawned inside or on top of rocks; fixed (`Combat.clear_spot`).
  A different cause, such as terrain slopes or knockback into rocks, was not
  reproduced; if it still happens, note where and what the enemy was doing.
- Tripo characters have no mouth shapes, so mouths do not move when they
  talk.
- A repeating sound reported in play: the trailer's was a bug (fixed). In the
  game, `charge_loop` (hold to charge chakra) is built as ~18 hits a second
  and may be what was heard; unconfirmed, and nobody here can hear it.

## Working notes

- Tests: `cd game && godot --headless --path . res://tests/test_runner.tscn
  -- --filter=NAME`; the full suite takes about 30 minutes.
- Re-import after adding a `class_name`: `godot --headless --path game
  --import`.
- GDScript lambdas capture locals by value: reassigning one inside a lambda
  does nothing. The project makes that a parse error; keep counters in a
  dictionary or array.
- Trailer: `--demo=trailer` records with the movie writer (Vulkan, about
  95 minutes); `art/trailer/` makes the audio and mixes it.
- A subagent the user interrupts cannot be resumed. Its worktree keeps its
  files, which can be committed and merged by hand (this is how the
  continent was recovered).
- New Tripo models go in `game/assets/characters/{main,rivals,bosses,cast}`;
  `make tripo` sets up their rig, then re-import.
