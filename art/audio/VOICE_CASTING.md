# Voice casting (ElevenLabs): where it stands, and how to resume

Recorded 2026-10. Paused because the account's monthly quota (64,832
credits) was used up; resume when it resets. Voices are ElevenLabs library
voices used through the `eleven_v4` model with **audio tags** in the text
(`[angrily]`, `[sighs]`, `[pause]`, ...). The tagged text for every line is
in `directions.json`; `directions.py` builds it and checks that stripping
the tags gives back the game's exact line.

## Cast

| Character | Voice (id) | Lines | State |
|---|---|---|---|
| Asahi | VALF Anime Protagonist Charismatic (`unWb9iRIK7Xxf4A5Hfis`) | | in game |
| Iwao | Adam, Brooding Dark Tough American (`IRHApOXLvnW57QJPQH2P`) | 20 | in game, directed |
| Mikage | Izumi, Sultry and Demanding Diva (`cENJycK4Wg62xVikqkaA`) | 20 | in game, directed |
| Kurogane | Gideon, Rugged Gravelly Northern (`q1h5HGdnfVxp4TXTJRNN`) | 12 | in game, directed |
| Hisame | Yuki, Gentle and Precise, Japanese accent (`DiHqGqDdN8tWkUxlsPeg`) | 95 | **approved, not recorded** |
| Kagerou | DYLO, Dark Anime Hero (`JjsQrIrIBD6TZ656NQfi`) | 30 | **approved, not recorded** |
| Nue | Hellin, Deep Intense British Gaming and Horror (`vfaqCOvlrKi4Zp7C2IAm`) | 6 | **approved, not recorded** (keep the `spirit` effect from `characters.json`) |
| Tobi | Jett, Gritty Spunky Young Hero (`6IwYbsNENZgAB1dtBZDp`) | 15 | **approved, not recorded** (4 takes made, not imported) |
| Renji | Callum, Husky Trickster (`N2lVS1w4EtoT3dr4eOWO`) | 13 | **approved, not recorded** (1 take made, not imported) |
| Tsumugi | none approved | 53 | old voice (Lyan) in game; owner called it too synthetic |
| Chiyo | none approved | 11 | old voice in game |
| Sumi | none approved | 16 | old voice (Cameo) in game |
| Shirou | none approved | 9 | old voice (Romulus II) in game; round-3 candidates never recorded |

Rejected by ear (do not retry): Ember, Cat (Tsumugi); Morganna (Chiyo);
Sakura, Minerva (Sumi); Gerald, Dominic (Kagerou); and narrator-style
voices in general. The owner's complaint is that most voices
sound like an AI reading; what passed (Adam, Izumi, Gideon, Yuki, DYLO,
Hellin, Jett, Callum) are character-acting voices, not narrators.
Untried candidates for Shirou: Hideo (`FMgBdHe1YV2Xi0B9anXW`, Japanese
accent), B. Hardscrabble Oxley (`zQzvQBubVkDWYuqJYMFn`).

## Cost

About 1 credit per character of text, tags included; Izumi costs about
double. Approved-but-unrecorded work is roughly 13,000 credits (Hisame
~8,000, Kagerou ~2,500, Tobi and Renji ~2,300, Nue under 500). Failed
requests are not charged.

## How to resume

1. Generate each line with `creative_generate_speech`, model `eleven_v4`,
   the voice id above, `generations_count` 1, and the `prompt` from
   `directions.json` (`directions.json[who][i]["prompt"]`). Three at a time
   is fine; more can hit rate limits.
2. Poll `creative_get_flow_run_status` (at most 20 session ids per call).
   Large results are written to a file; save it as JSON.
3. `python3 art/audio/fetch_elevenlabs.py <who> <voice_id> <status.json> <out_dir>`
   downloads the takes (it skips files already on disk, so move stale ones
   aside first).
4. `python3 art/audio/import_elevenlabs.py <who> <out_dir>/<who>` masters
   them into `game/assets/audio/voice/<who>/`.
5. `godot --headless --path game --import`, then
   `godot --headless --path game res://tests/test_runner.tscn -- --filter=voice`
   (8 tests).
6. Commit one character at a time.

Tobi's and Renji's approved takes: Tobi line 10 ("Seven lanterns...") and
Renji line 1 ("A man walked past my lantern...") came from the audition
files and can simply be regenerated.

## New story dialogue

Every spoken story line must have a recording (a test checks it). New
missions, such as `docs/STORY_PART8_DRAFT.md`, cannot ship until their lines
are voiced, and each new character needs a voice cast and approved by ear.
