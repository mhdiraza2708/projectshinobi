# Story mode: writing chapters

The story is six **chapters** of **missions**. Each mission is a JSON file
in `game/data/story/` that lists **beats** (dialogue, tutorial tasks, fights,
boss fights, characters entering and leaving) played in order; its `part`
says which chapter it belongs to (`parts.json` names the chapters). In the
open world each mission waits at a pillar of light on its island, the
tracker tells you where to go (`objective`), and arriving starts it: no
card, no teleport, and when it ends you're back in the world with the next
objective. Adding or editing a mission is a data change: no code, and no
Godot editor needed.

| Chapter | # | Mission | Island | What happens |
|---|---|---|---|---|
| 一 The Graduation | 1 | The Graduation Trial | Emberwood | Sensei Hisame's tutorial: kunai, seals, the element circle, guarding, a first clone. Asahi challenges you. |
| | 2 | The Night Before | Emberwood | Tobi and Hisame tell you what the vault guards; Asahi, on the wall, about his mother. |
| | 3 | Lightning at Noon | Emberwood | Boss duel with Asahi (lightning). The vault alarm rings. |
| | 4 | The Empty Vault | Emberwood | The Scroll of Five Natures is stolen. Hold the yard. Kagerou's name. |
| 二 The Ashen Trail | 5 | Ash on the Wind | Ashen Pass | Asahi meets you at the burned island; a clone patrol; lanterns at the shrine. |
| | 6 | The Ashen Pass | Ashen Pass | Ambush at the shrine. Boss: Iwao (earth). |
| | 7 | Kagerou | Ashen Pass | Kagerou changes nature at 80/60/40/20%; answer each. He keeps the last seal. |
| 三 The Windward Watch | 8 | Rain Lessons | Emberwood | Interrupt drill; Tsumugi of the Windward Watch arrives and duels you. |
| | 9 | The Hunter's Road | Autumn Wood | Tsumugi on the Watch and the Nue's making; break scouts' weaves; an ambush. |
| | 10 | The Autumn Wood | Autumn Wood | Clone waves beside Asahi; plans for Iwao's dam. |
| 四 The Old Dam | 11 | Below the Dam | Old Dam | Chiyo the dam keeper on Iwao; clear the spillway; Hisame's plan. |
| | 12 | The Old Dam | Old Dam | Survive beside Tsumugi while Hisame breaks the barrier; Iwao (earth, then water). |
| 五 Kagerou's Reason | 13 | The Frozen Road | Frozen Road | Renji saw a man who melted the snow; a fire-clone ambush. |
| | 14 | Kagerou's Reason | Frozen Road | Kagerou's story, and a duel on his terms. |
| | 15 | What the Scroll Remembers | Emberwood | Hisame teaches the Five-Nature Seal; Asahi admits he's scared. |
| 六 Nue | 16 | The Climb | Five Winds | Up the leap stones; five pillar guardians, one per nature, with Asahi and Tsumugi. |
| | 17 | Nue | Five Winds | The possessed giant; seal it with the Five-Nature Seal. |
| | 18 | Noon, Again | Emberwood | What became of everyone, and Asahi's rematch (lightning, then wind). |

The Nue is a spirit from Japanese folklore (public domain). All story content is original. Keep it that way: see the IP section in
[DESIGN.md](DESIGN.md).

## Characters: `characters.json`

```json
"hisame": {
	"name": "Hisame",
	"title": "Sensei",
	"kanji": "雨",
	"element": "water",
	"voice": {"speaker": "af_heart", "speed": 0.95},
	"style": {
		"tints": {"body": "#b3c4dc", "outfit": "#1f3552", "hair": "#d9e0ea"},
		"headband": "cloth", "headband_color": "#2f5fb3",
		"scarf": true, "scarf_color": "#1f3552",
		"back": "ninjato", "mask": false, "pouch": true,
		"expression": "relaxed", "height": 1.05
	}
}
```

- `kanji` is the character's seal in the dialogue box.
- `voice` is how their lines are recorded: `speaker` (a Kokoro voice such
  as `af_heart`, `af_bella`, `bf_emma`, `am_michael`, `am_fenrir`, or a blend
  like `"am_michael*0.5+am_onyx*0.5"`), `speed` (1 = normal, higher is
  faster) and optional `effect` (`spirit`: doubled and hollow).
- `style` uses the same keys as the Customize screen (see
  `game/autoload/profile.gd`). Colour slots are hair, eyes, skin, outfit,
  lower, shoes, accessory and body. Models without recognisable material
  names only use `body`.
- The id `player` is reserved: it is you, with your name and nature.
- New kanji need to be in the UI font. Run `make fonts` after adding them.
  The tests fail if you forget.

## Chapters

```json
{
	"id": "ch1_graduation",
	"number": 1,
	"title": "The Graduation Trial",
	"location": "Emberwood Academy yard",
	"time": "dawn",
	"summary": "Optional one-liner.",
	"dummies": true,
	"player_at": [0, 4],
	"beats": [ ... ]
}
```

- `number`: missions play in order 1, 2, 3… and each unlocks when the one
  before it is cleared.
- `part`: the chapter (in `parts.json`) the mission belongs to. Missions run
  chapter by chapter.
- `objective`: what the tracker says while the mission waits ("Follow the
  clones' trail west across the sea to the Ashen Pass").
- `time`: `dawn`, `day`, `dusk` or `night` (night lights the lanterns).
- `weather`: `none`, `rain`, `storm` (rain with lightning and thunder),
  `snow` or `leaves`.
- `part`: which part of the story the chapter belongs to (headers in the
  chapter list).
- `island`: where the chapter happens (default `emberwood`). In the open
  world you walk there: a pillar of light marks the chapter's `player_at`,
  and it plays where you stand. A replay from the title's chapter list
  teleports you there by a summoning seal instead, and away again when it
  ends. See **Islands** below.
- `music`: the track for the mission's talking and lessons (see **Music**
  below). Left out, they play the island's own theme.
- `dummies`: keep the training dummies (default false).
- Positions are `[x, z]` in metres. Every island has a flat clearing about
  40 m across, centred on `[0, 0]`, and an invisible wall about 38 m out.
  Keep characters within 15 m of the centre.

## Difficulty: the world grows harder

Fighters keep pace with the player, who grows through the skill trees all
the way. A fighter's **tier** is its chapter's `part` minus one
(`scripts/enemies/enemy_tier.gd`), so nothing needs adding to a mission:
part 1's enemies are exactly their rank's table, and each part after makes
every fighter

- tougher: +14% health, +8% poise and +6% harder to interrupt per part;
- stronger and faster: +9% damage and +3% run speed per part;
- sharper: 5% quicker to think, seal, throw and run in, 6% quicker between
  jutsu, a little more dodging and guarding, and 15% more reach for strong
  jutsu per part.

By part 6 that is about 70% more health and 45% more damage than part 1. A
boss's written `health` is multiplied the same way. The tell before a blow
shrinks by only 3% a part, so it stays readable. Practice clones (the
`drill` of a task) and Trials mode are not scaled. Open-world quest fights
use the furthest part you have cleared a chapter of.

**Difficulty and New Game+.** On top of the story's climb, the Difficulty
setting (pause menu, Accessibility tab) adds tiers: Hard +2, Nightmare +4.
When every chapter is cleared the Quests tab offers **New Game+**: the story,
quests, world and its places start over, skills, level and looks stay, and
every round adds three more tiers (the ceiling is tier 9). The tell before a
blow never drops below 0.3 s. Boss signature attacks (quakes, a running
shockwave ring, blinking strike chains; `scripts/enemies/boss_specials.gd`)
are written on the boss beat as `"specials"` and scale the same way:

```json
"specials": [{"kind": "ring", "every": 13, "below": 0.85, "damage": 16},
             {"kind": "chain", "every": 16, "below": 0.45, "count": 3, "damage": 16}]
```

`kind` is `quake`, `ring` or `chain`; `every` the seconds between uses;
`below` the health share under which it starts; `count`, `radius`, `damage`
and `delay` (the warning) have defaults per kind.

## Islands

Each island is built when the chapter starts, from a preset in
`game/scripts/world/island.gd` (`Island.PRESETS`): the terrain around the
clearing, its colours, the sea, landmarks at fixed spots and trees and rocks
scattered by seed.

| Island | Chapters | Look |
|---|---|---|
| `emberwood` | 1, 2, 3, 6 | Green hills, the academy's houses and shrine, torii, bamboo, pines |
| `ashen_pass` | 4, 5 | Grey ash, dead trees, a broken torii before an abandoned shrine |
| `autumn_wood` | 7 | Red and gold maples, a forest shrine |
| `old_dam` | 8 | A stone dam with a reservoir behind it and a waterfall |
| `frozen_road` | 9 | Snow, snowy pines, a lantern-lined road to a shrine |
| `five_winds` | 10 | A summit above the sea, ringed by five pillars with glowing orbs, one per nature |

A new island is a new entry in `PRESETS`: colours, `hills` (height), `coast`
(radius), `open_dir` (the low side, for a sea view), `props` (landmarks),
`scatter` (trees and rocks) and optional `paths`, `carve`, `reservoir`,
`waterfall` or `plateau`. Props come from `game/assets/models/`, built by
`art/blender/build_assets.py`. Preview an island from the air with
`--demo=island:<id>` (see the screenshot command in the README).

## Beats

| Beat | Keys | What it does |
|---|---|---|
| `enter` | `who`, `at` | The character appears in a puff of smoke and faces you. |
| `exit` | `who` | They leave in a puff of smoke. |
| `say` | `lines`, optional `music` | Dialogue. Each line is `[who, text]` or `[who, text, mood]`. The mood is one of neutral, angry, happy, relaxed or sad. Speakers must be on stage (or `player`). |
| `task` | `text`, `goal`, optional `count`, `jutsu`, `enemies`, `music` | A tutorial objective. The goal is one of `kunai_hit`, `strike_hit`, `jutsu_hit`, `weak_hit`, `cast` (optionally a specific `jutsu`), `guard`, `dash`, `charge`, `lock_on` or `interrupt`. `enemies` adds practice clones that only weave, slowly, so you can interrupt them; they come back if they fall. |
| `fight` | `waves`, optional `text` | Waves of clones: `[{"element": "wind", "enemies": ["genin", "chunin"]}]`. |
| `boss` | `who`, `rank`, `health`, optional `element`, `taunt`, `at`, `phases`, `size` (1.35 = oversized), `aura` (colour) | A named boss fight with a health bar. If the character is on stage, they step into the fight from where they stand. |
| `ally` | `who`, `rank`, optional `health`, `at` | The character fights beside you, hunting the nearest enemy, until an `exit` (or until you talk to them again). If they're beaten they retreat; a retried fight brings them back. |
| `survive` | `seconds`, `enemies` (`[[rank, element], ...]`), optional `max_alive`, `text` | Hold out: enemies keep arriving (up to `max_alive` at once) until the timer runs out. |
| `wait` | `seconds` | A pause with control. |
| `banner` | `text` | A big banner (for example "End of Part One"). |
| `scene` | `steps` | A cutscene (see below). |

### Cutscenes: the `scene` beat

A `scene` is a short film played under letterbox bars: `{"do": "scene",
"steps": [...]}`. Steps run one after another; add `"async": true` to run
one alongside the steps after it. **Hold Pause to skip**: everyone ends up
where the scene would have left them (and time of day, weather and music
changes still happen). Dialogue inside a scene advances by itself.

Each step has one action key plus its options. Points are `[x, z]` on the
ground, `[x, y, z]` in the air, or a character on stage (`"hisame"`,
`"player"`).

| Step | Options | What it does |
|---|---|---|
| `{"wait": 1.5}` | | Pause. |
| `{"cam": "<shot>"}` | `on`, `seconds`, `dist`, `height`, `side`, `fov`, `blend` | A camera shot: `close`, `mid`, `wide`, `low` (framings of one character, pushing slowly in), `over` (`from` + `on`, over a shoulder), `two` (`on: [a, b]`), `orbit` (`on`, `radius`, `degrees`), or `free` (`at` → `to`, `look` → `look_to`). Cuts by default, or glides from the last shot over `blend` seconds. Keep free cameras inside the clearing: trees ring it. |
| `{"say": [[who, text, mood], ...]}` | | Lines, voiced, advancing on their own. Speakers must be on stage. |
| `{"enter": "who"}` | `at`, `from` ([x, y, z] to start somewhere else), `facing`, `puff` (false: no smoke) | Brings a character on. |
| `{"exit": "who"}` | `puff` | Sends them off. |
| `{"move": "who"}` | `to`, `run` | Walk (or run) there. Works on `player` too. |
| `{"leap": "who"}` | `to`, `from`, `height`, `seconds` | A bounding leap, landing in dust. |
| `{"face": "who"}` | `to` | Turn towards someone or a point. |
| `{"pose": "who"}` | `as` (`idle`, `weave`, `guard`, `charge`), `seconds` | Hold a pose. |
| `{"weave": "who"}` | `seals` (`["rat", "tiger", ...]`) | Hands seals flash above their head, then a flare. |
| `{"cast": "who"}` | `element`, `at`, `kind` (`projectile`, `blast`, `bolt`) | A technique for show (nobody is hurt). |
| `{"fx": "<kind>"}` | `at`, `from`, `to`, `on`, `element`, `color`, `seconds`, `size` | `flash`, `shake`, `lightning`, `blast`, `smoke`, `dust`, `aura` (`on`), `beam` (`from` → `to`). |
| `{"grow": "who"}` | `scale`, `seconds` | Change size. |
| `{"music": "calm"}`, `{"sfx": "thunder"}` | | Change the music (or `"none"`), play a sound. |
| `{"time": "dawn"}`, `{"weather": "rain"}` | | Relight the scene. |
| `{"fade": "out"}` | `seconds`, `color` | Fade to black (or `"in"`). |
| `{"title": "Place"}` | `sub`, `seconds` | A caption. |

Dialogue spoken inside a scene is recorded by `make voices` like any other.
Preview a scene from the command line with
`--demo=scene:<chapter id>:<beat number>:<seconds>` (best with
`--fixed-fps 10`).

Text can use `{name}` (your shinobi's name), `{nature}` (your chakra
nature) and any input action in braces, such as `{weave}`, `{throw_tool}`
or `{guard}`. Those become the key or button for the device in use.

**Boss phases** trigger when health drops to a share of the maximum:

```json
"phases": [
	{"at": 0.6, "element": "lightning", "say": "Lightning! Faster than your seals!",
	 "summon": [["genin", "lightning"]]}
]
```

At each phase the boss hops away. It can switch nature (its weakness
changes, and so do its jutsu and colours), shout a line, and summon clones.
Its clones vanish when it falls.

**Defeat** in a fight or boss shows a panel, and **Retry fight** restarts
that fight, not the chapter.

## Music

The game picks the music for each beat (`game/scripts/story/story_director.gd`):

- `fight` and `survive` play a battle theme. Missions take turns: odd-numbered
  missions get `battle`, even-numbered ones `battle2`. `boss` always plays
  `boss`.
- `say` and `task` play the beat's own `music`, else the mission's `music`,
  else the island's theme: `calm` for Emberwood, and `autumn_wood`,
  `ashen_pass`, `old_dam`, `frozen_road` or `five_winds` for the others.
- Entrances, exits, banners and waits keep what is playing, and a `scene`
  can change it with a `{"music": "..."}` step.

Name a track in `music` (a chapter, a `say` or a `task`; a scene step also
takes `"none"` for silence) to colour a moment: `tension` is a low, uneasy
cue; `sorrow` a slow lament. The two Kagerou chapters and the night before
the finale use both. In free roam the music follows the place and the hour
instead: the island's theme, `sea` between islands and `night` after dark.

| Track | Where it plays |
|---|---|
| `title` | The title screen |
| `calm` | Emberwood, and the training ground |
| `autumn_wood`, `ashen_pass`, `old_dam`, `frozen_road`, `five_winds` | Exploring that island |
| `sea` | Running across the water between islands |
| `night` | Free roam after dark, anywhere |
| `battle`, `battle2` | Fights: the trial plays `battle`, quest fights take turns, story fights go by mission |
| `boss` | Boss fights |
| `tension`, `sorrow` | Story moments, chosen with `music` |

A new track is a new function in `art/audio/make_music.py` (add it to
`TRACKS`, run `make music`) and a line in `Music.TRACKS`
(`game/autoload/music.gd`); the tests fail if the two disagree.

## Voices

Every line a story character says is recorded with the Kokoro neural
voice model. Run `make voices KOKORO=path/to/folder` after adding or editing
dialogue (see `art/audio/make_voices.py` for where to get the model files).
Names espeak would misread (Hisame, Kagerou, Tsumugi...) are spelled out
phonetically in `NAMES` at the top of that script: add new ones there.
A line whose text changed plays silently until
you do, and `make test` lists what's unrecorded. The player is never voiced,
and `{name}` is left out of spoken lines. Lines with `{nature}` are recorded
once per nature.

## Checking your work

```sh
make test
```

`tests/unit/test_story.gd` loads every chapter and fails with a readable
message for unknown keys, characters, goals, elements or ranks, for a
speaker who isn't on stage, or for an exit without an entrance. It also
plays chapter 1 start to finish.

## Limits (honest)

- Islands are stylised low-poly blockouts (procedural terrain, simple
  props), not hand-built levels, and the fighting always happens in the
  central clearing.
- Characters use the placeholder model, tinted and geared differently,
  unless you add VRoid models to the roster (see
  [CHARACTERS.md](CHARACTERS.md)). Story characters draw from the same
  roster.
- Conversations are lightly animated: the speaker gestures (a talking
  idle clip), holds an expression, and opens their mouth with the voice
  (no real lip shapes).
- The voices are text-to-speech. Kokoro reads naturally and clearly (in a
  speech-recognition check its lines came back with about 6% of words wrong,
  against 12% for the old Piper voices), but it is still reading, not
  acting: shouts don't really shout and there is no crying or laughing.
- Choices and branches aren't supported. Chapters are linear.
