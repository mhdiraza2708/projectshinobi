# Characters: VRoid Studio → game

The game loads the player character from a **VRM** file, the format
[VRoid Studio](https://vroid.com/en/studio) exports. Until you add one, a
placeholder (Godette, CC-BY) is used.

Nothing in the character is hard-coded. At load time the game:

- turns the model to face forward (VRM models face the other way),
- rescales it if it was authored at an odd scale (normal VRoid heights are
  left alone),
- keeps the VRM's anime shader (MToon), hair and skirt physics (spring
  bones), and facial expressions,
- poses it procedurally (idle, run, sprint, jump, dash, guard, charge, strike
  and the **hand-seal pose**) with IK. This works on any humanoid rig, so
  there are no per-character animation files to author.

## Make your shinobi

1. **Install VRoid Studio** (free, Windows/macOS). It's available from
   vroid.com or on Steam.
2. **Create a new model** and design it:
   - *Face / Hair:* the hair editor's guide tools make spiky or swept anime
     hair. Hair is the single biggest factor in how "anime" the character reads.
   - *Outfit:* start from a bodysuit or jacket preset, then use **Edit
     Texture** to paint a ninja look: dark bodysuit, jacket, wraps on the
     forearms and shins, a scarf. Accessories cover headbands and pouches.
     Outfit textures made by other people (for example on Booth) have their own
     licences, so check them before using one.
   - Keep the design **original**. Don't recreate Naruto characters: see
     the IP section in [DESIGN.md](DESIGN.md).
3. **Export:** *Camera/Exporter → Export → VRM*. VRM 0.0 and 1.0 both work.
   Recommended settings:
   - Polygon reduction: off (or light) for the player character.
   - Materials: reduce to around 8. Texture atlas: 2048.
   - Fill in the metadata: title, your name as author, and the usage
     permissions you want.
4. **Save the file as `game/assets/characters/player.vrm`.**
5. Open the project in Godot (it imports the file automatically) or run
   `make import`, then `make run`. Your character replaces the placeholder.

To try it without committing, the file can live there untracked. **The repo
is public**, so a committed `.vrm` can be downloaded by anyone. If that
matters, add `game/assets/characters/player.vrm` to `.gitignore` or make the
repository private.

## Animations: Mixamo

Out of the box the character is animated procedurally. For motion-captured
movement, add Mixamo clips. The game plays them on your VRoid character and
**still layers the hand-seal pose on top** (no animation library has seals).

1. Sign in at [mixamo.com](https://www.mixamo.com) (free Adobe account).
2. Find clips. Titles change over time, so search for terms like *idle* or
   *fighting idle*, *running*, *fast run*/*sprint*, *jump* or *falling*,
   *block*, *power up*, *dash*/*roll*. For anything that travels (run,
   sprint, dash), tick **In Place**: the game moves the character itself.
3. Download each clip with **Format: FBX**, **Skin: Without Skin**, **30 fps**.
4. Rename the files to the slots you want. Every slot is optional:

   | File | Used for | Without it |
   |---|---|---|
   | `idle.fbx` + `run.fbx` | standing, running (both needed) | procedural |
   | `sprint.fbx` | sprinting | `run` sped up |
   | `jump.fbx` | in the air | procedural |
   | `guard.fbx` | guarding | procedural |
   | `charge.fbx` | charging chakra | procedural |
   | `dash.fbx` | dashing | procedural |

5. Put them in `game/assets/animations/mixamo/` and run **`make animations`**.
   This configures Godot's humanoid retargeting for each clip and re-imports
   it. If you'd rather do it in the editor, select the FBX, go to *Import →
   Skeleton3D → Retarget*, set **Bone Map** to
   `assets/animations/mixamo_bone_map.tres`, turn on rename bones and unique
   node `GeneralSkeleton`, and set rest fixer to **Overwrite Axis**.
6. Run the game.

Licence note: Adobe's terms, as I understand them, let you use Mixamo
animations in your game royalty-free but not redistribute the raw files.
This repo is public, so `.gitignore` excludes the FBX files in that folder
by default. Check Adobe's current terms yourself.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Model stands in a T-pose | The rig isn't humanoid-mapped. Check *Project → Project Settings → Plugins* has **VRM** and **Godot-MToon-Shader** enabled, then reimport the file. |
| Model is invisible or pink | The MToon shader addon is disabled. Enable it as above. |
| "rig has no 'X' bone" warning | Only for non-VRM models. Retarget the skeleton to Godot's humanoid profile in the import dock (*Skeleton3D → Retarget → Bone Map → SkeletonProfileHumanoid*). |
| Character slides across the ground or drifts while running | The clip wasn't downloaded **In Place**. Re-download it with that box ticked. |
| Log says "…is not retargeted; run `make animations`" | The clip was added without the retarget settings. Run `make animations`. |
| Colours look washed out in screenshots from CI | CI renders with a software OpenGL renderer. Judge lighting in the editor or the game on a real GPU. |

## How it works (for programmers)

- `scripts/character/character_model.gd` loads `player.vrm` if it exists,
  else `default/godette.vrm`. It also fixes facing and scale and attaches the
  poser.
- `scripts/character/humanoid_poser.gd` is a `SkeletonModifier3D`. Poses are
  authored in a canonical frame (facing −Z, sizes in arm and leg lengths)
  and solved with two-bone IK, so the same data fits T-pose and A-pose rigs of
  any proportions. It runs after animation clips, which lets it layer the
  hand seals on top of Mixamo locomotion.
- `scripts/character/character_animator.gd` picks clips by player state,
  crossfades them, scales run playback to movement speed, and tells the
  poser which states the clips cover.
- `tools/setup_mixamo.gd` writes the retarget settings into each clip's
  `.import` file. `tests/unit/test_clips.gd` runs the whole path on
  Mixamo-format fixtures made by `art/blender/make_mixamo_fixtures.py`.
- `tests/unit/test_character.gd` checks, on a real VRM, that the model faces
  forward, arms hang at idle, palms meet for seals, guard raises the
  forearms, and the run cycle alternates feet.
