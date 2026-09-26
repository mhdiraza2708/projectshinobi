# Story mode: writing chapters

Story mode is chapter-based: each chapter is a JSON file in
`game/data/story/` that lists **beats** (dialogue, tutorial tasks, fights,
boss fights, characters entering and leaving) played in order. Adding or
editing a chapter is a data change: no code, and no Godot editor needed.

Part One, *The Stolen Scroll*, has five chapters:

| # | Chapter | Time | What happens |
|---|---|---|---|
| 一 | The Graduation Trial | dawn | Sensei Hisame's tutorial: kunai, seals, the element circle, guarding, a first clone. Asahi challenges you. |
| 二 | Lightning at Noon | day | Boss duel with Asahi (lightning). The vault alarm rings. |
| 三 | The Empty Vault | dusk | The Scroll of Five Natures is stolen. Hold the yard against two waves of clones. Enter Kagerou's name. |
| 四 | The Ashen Pass | night | Ambush at the abandoned shrine. Boss: Iwao (earth), who summons stone clones. |
| 五 | Kagerou | night | Final boss. Kagerou changes nature at 80/60/40/20% health, so answer each one with the nature that beats it. |

Part Two, *The Last Seal*:

| # | Chapter | Time / weather | What happens |
|---|---|---|---|
| 六 | Rain Lessons | day, rain | Interrupt drill: break a practice clone's weave three times. Tsumugi (wind hunter) arrives and duels you. |
| 七 | The Autumn Wood | dusk, leaves | Fight clone waves beside Asahi. Plans for Iwao's dam. |
| 八 | The Old Dam | night, storm | Survive 45 s beside Tsumugi while Hisame breaks the barrier, then Iwao (earth, then water). |
| 九 | Kagerou's Reason | dusk, snow | Kagerou's story, and a duel on his terms. |
| 十 | Nue | night, storm | A possessed, oversized Kagerou cycles all five natures while your allies hold the clones. Seal it with the Five-Nature Seal (Rat, Tiger, Dragon, Snake, Boar). |

The Nue is a spirit from Japanese folklore (public domain). All story content is original. Keep it that way: see the IP section in
[DESIGN.md](DESIGN.md).

## Characters: `characters.json`

```json
"hisame": {
	"name": "Hisame",
	"title": "Sensei",
	"kanji": "雨",
	"element": "water",
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

- `number`: chapters play in order 1, 2, 3… and each unlocks when the one
  before it is cleared.
- `time`: `dawn`, `day`, `dusk` or `night` (night lights the lanterns).
- `weather`: `none`, `rain`, `storm` (rain with lightning and thunder),
  `snow` or `leaves`.
- `part`: which part of the story the chapter belongs to (headers in the
  chapter list).
- `dummies`: keep the training dummies (default false).
- Positions are `[x, z]` in metres. The arena is roughly 30 m across, centred
  on `[0, 0]`. The torii gate is at `[0, -24]`.

## Beats

| Beat | Keys | What it does |
|---|---|---|
| `enter` | `who`, `at` | The character appears in a puff of smoke and faces you. |
| `exit` | `who` | They leave in a puff of smoke. |
| `say` | `lines` | Dialogue. Each line is `[who, text]` or `[who, text, mood]`. The mood is one of neutral, angry, happy, relaxed or sad. Speakers must be on stage (or `player`). |
| `task` | `text`, `goal`, optional `count`, `jutsu`, `enemies` | A tutorial objective. The goal is one of `kunai_hit`, `strike_hit`, `jutsu_hit`, `weak_hit`, `cast` (optionally a specific `jutsu`), `guard`, `dash`, `charge`, `lock_on` or `interrupt`. `enemies` adds practice clones that only weave, slowly, so you can interrupt them; they come back if they fall. |
| `fight` | `waves`, optional `text` | Waves of clones: `[{"element": "wind", "enemies": ["genin", "chunin"]}]`. |
| `boss` | `who`, `rank`, `health`, optional `element`, `taunt`, `at`, `phases`, `size` (1.35 = oversized), `aura` (colour) | A named boss fight with a health bar. If the character is on stage, they step into the fight from where they stand. |
| `ally` | `who`, `rank`, optional `health`, `at` | The character fights beside you, hunting the nearest enemy, until an `exit` (or until you talk to them again). If they're beaten they retreat; a retried fight brings them back. |
| `survive` | `seconds`, `enemies` (`[[rank, element], ...]`), optional `max_alive`, `text` | Hold out: enemies keep arriving (up to `max_alive` at once) until the timer runs out. |
| `wait` | `seconds` | A pause with control. |
| `banner` | `text` | A big banner (for example "End of Part One"). |

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

## Checking your work

```sh
make test
```

`tests/unit/test_story.gd` loads every chapter and fails with a readable
message for unknown keys, characters, goals, elements or ranks, for a
speaker who isn't on stage, or for an exit without an entrance. It also
plays chapter 1 start to finish.

## Limits (honest)

- Every chapter happens in the same arena, relit for the time of day. New
  locations need new level art.
- Characters use the placeholder model, tinted and geared differently,
  unless you add VRoid models to the roster (see
  [CHARACTERS.md](CHARACTERS.md)). Story characters draw from the same
  roster.
- Conversations have no animation beyond a gesture and a facial
  expression, and there's no voice acting.
- Choices and branches aren't supported. Chapters are linear.
