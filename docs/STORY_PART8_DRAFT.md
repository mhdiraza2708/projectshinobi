# Part 8 (draft): The Long Ink

**Status:** outline only. Nothing here is in the game. A mission's spoken
lines each need a recorded voice (a test checks it), so this waits for
voice credits, and it should be read and changed before any line is
recorded, because every line costs. All names and events are original.

## Where Part 7 leaves everyone

Mikage keeps the Ledger and has to put it right. Names come home. The
trouble this arc starts from: **the Court erased the worst of a war, not
just the names.** As the Ledger is corrected, people don't only get their
names back. They get the grudges back that the forgetting was hiding.

## The idea

*Remembering is not the same as being forgiven.* Part 7 was about being
forgotten. Part 8 is about the other half: some things were forgotten on
purpose, and some of the people who now remember them are not wrong to be
angry. The enemy is not a monster. It is a reasonable grief with a plan.

## New people (each needs a voice, a model and a style)

| Id | Name | Who | Nature | Role |
|---|---|---|---|---|
| `ginjiro` | Ginjiro, the Remembering | A ferry-master who got his village back, and the sons he had forgotten were lost to the war | lightning | The arc's antagonist. Calm, courteous, never cruel. Wants the founders' war *recorded*, in full, in public. |
| `ume` | Ume | A child of the returned, who has never known the war | water | Stands where you stood in Part 1: new, loud and certain. A mirror for the player. |

Everyone from Part 7 returns. Mikage is a companion for the first time
(she fights as an ally, water, with a ward she can put on you).

## The missions

Each mission lists the *kind* of play it adds. The four new kinds (escort,
search, rules duel, non-lethal) are built and tested; see "The newer mission
kinds" in [STORY.md](STORY.md). What is missing is the dialogue and its voices.

| # | Mission | Island | What happens | New play |
|---|---|---|---|---|
| 25 | **Names Coming Home** | Emberwood | A festival of returning names, lit by the seventh lantern. Tobi's brother is among the first. Mikage is awkward in daylight. Ginjiro arrives, politely, and asks to read the war's page aloud. Hisame says no. | Quiet opener. Walk and talk, three small tasks (carry lanterns). |
| 26 | **The Ferry at Dusk** | Old Dam | Ginjiro's ferry is the only way across the sea to the Court's vault. You escort Ume across while his followers watch from the banks. | **Escort** (new beat): a companion with health follows a route, enemies target them first. |
| 27 | **Founders' Cairns** | Autumn Wood | Three cairns hold the war's record. Find them before Ginjiro does, and decide what is read and what is not. | **Search** (new beat): find N marked spots without a map pin; a fight at each. |
| 28 | **Rules of the Ford** | Frozen Road | Ginjiro offers a duel to the old rules: no jutsu, katana and kunai only, so no one can say it was won by cheating. | **Rules duel** (new beat option): `"rules": "blades"` locks jutsu for the fight. Boss: Ginjiro (lightning) with `sweep` and `chain`. |
| 29 | **The Reading** | Five Winds | The page is read aloud at the summit, by someone. A crowd of the returned, angry and right. You hold the stairs without hurting them. | **Defend without killing** (new beat): `"nonlethal": true`; crowd members stagger and flee instead of falling. |
| 30 | **What We Keep** | Emberwood | The last fight is with the Ledger itself: every grudge on one page, given a shape. Mikage is on your side of it. Then the council, and what the academy decides to remember. | Boss: the Ledger (all seven specials in sequence: the capstone). A choice at the end changes one line of the epilogue. |

## Boss kits (using what exists now)

- **Ginjiro** (mission 28): `chain` (his ferry-pole strikes), `sweep`
  (the pole turning), `ward` below 0.5 (a debt he refuses to drop).
  Phases: lightning, then water as he remembers a drowning.
- **The Ledger** (mission 30): `ward` from the start (a page you must
  break), `call` (the names of those it was written for), `pull`
  (the weight of everything remembered), `sweep` and `quake` at the end.

## Rough cost, so we can decide

- Six missions, about 130 spoken lines in total, roughly 9,000 characters.
- With acting directions that is about **9,000 to 10,000 ElevenLabs
  credits**, plus two new voices to cast and audition (about 600 credits).
- Code: done (escort, search, rules duel, non-lethal), with tests.

## Questions that need an answer before anything is recorded

1. Is Ginjiro right enough to be uncomfortable? (The draft says yes: the
   player can't just beat him and call it solved.)
2. Should mission 30 end with a real choice, or one fixed ending?
3. Do you want Ume at all? She adds a voice to cast; the arc still works
   without her if the escort is Mikage or Tobi instead.
