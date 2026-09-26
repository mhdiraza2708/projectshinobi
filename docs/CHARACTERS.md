# Characters: VRoid Studio → game

Characters are **VRM** files, the format
[VRoid Studio](https://vroid.com/en/studio) exports. The game ships nine
VRoid Studio sample characters that pixiv released under **CC0** (Shino,
Shibu, Darkness Shibu, Fumiriya, Victoria, Vita, Vivi, Kai and Nene), plus
the low-poly Godette as a light fallback. The default is Kai.

## Wardrobe: mix and match

Customize → **Look** has three pickers:

- **Face & body**: which character you are (face, head, skeleton).
- **Hair**: any character's hair, or your own.
- **Outfit**: any character's clothes (and the body under them), or your own.

These are the characters' real VRoid meshes, not stand-ins. The wardrobe
copies the chosen parts with their skin weights, rebinds them to your
skeleton by bone name, and carries over the hair and skirt joints and their
spring bones, so borrowed hair still sways. Recolour each part on the
**Colours** tab (hair, eyes, skin, outfit, lower, shoes). New players get a
dark shinobi dye on their outfit; pick white for the original colours.

Limits: parts come from characters of different builds, so a borrowed
outfit can be slightly loose or tight on another body. Only characters that
keep hair and clothes on separate materials can swap (every VRoid export
does; Godette doesn't). Any VRoid character you add to the roster joins the
wardrobe automatically.

Bundled models were shrunk to 1024 px textures with
`art/characters/prepare_vrm.py` (about half the file size, no visible
difference at game distance). Do the same for your own exports if size
matters: `python art/characters/prepare_vrm.py in.vrm out.vrm`.

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

### No Godot installed? Let CI build it for you

1. Export your VRoid character as `.vrm` (step 3 above).
2. On GitHub, open `game/assets/characters/roster/` (or `game/assets/characters/`
   for `player.vrm`) on your branch → **Add file → Upload files** → drop
   the `.vrm` → **Commit changes**.
3. Wait for the **CI** run on that commit to finish (Actions tab, about
   10 minutes). Download the **ProjectShinobi-Windows** artifact. Your
   character is in it: pick it under Customize → Look.

The same public-repo warning applies: anyone can download a committed `.vrm`.

### A ninja recipe for VRoid Studio

A starting point that reads as "shinobi" at game-camera distance. None of
it copies a specific anime character.

- **Hair:** start from a short spiky or swept preset, then use hair guides to
  push 5–8 large clumps back and up. Big, readable shapes beat many thin
  strands, because the camera is 4 m away. Pick a hair colour that contrasts
  with the outfit.
- **Face:** slightly narrower eyes and a flatter brow read as focused. Raise
  eye highlight size a little so the eyes don't go dead under game lighting.
- **Body:** default proportions are fine. The gear fitter measures the body,
  so height and build can vary.
- **Outfit:** a bodysuit or fitted top plus trousers. In *Edit Texture*
  paint a dark base (navy, charcoal, deep green), one accent colour, and
  bandage wraps on the forearms and shins. Leave the head and neck bare: the
  game adds the headband, mask and scarf, so you can recolour them in game.
- **Export:** as in step 3. Around 8 materials and a 2048 atlas keep it light.

Make two or three variants (different hair and colours from the same base)
and upload them all to `roster/`. That gives you a roster to choose from, and
enemies can use them later.

## In-game customization

Pause (Esc / Start) → **Customize** opens a screen with
your character standing on the right. Rotate it with the right stick or by
dragging with the mouse. Every change applies live and is saved to
`user://profile.cfg`.

| Tab | What you can change |
|---|---|
| 姿 **Look** | Which character (roster), height (90–110%), default facial expression |
| 色 **Colours** | A tint per material slot the model has: hair (brows follow), eyes, skin, outfit, lower, shoes, accessories |
| 装 **Gear** | Headband (cloth or metal-plated hachigane), face mask, scarf, ninjato on the back, kunai pouch, each with colours where it makes sense. Gear size and headband height sliders help with unusual heads. |
| 名 **Identity** | Name (or **Random** for a generated ninja name, handy on a controller) and chakra nature |

**The limits, honestly:**
- Face, hair shape and body shape come from VRoid Studio. To change those,
  make another character in VRoid and add it to the roster (below).
- Colours *multiply* the model's own textures. They shift and darken, but
  can't turn dark hair blond. For light colours, author light textures in
  VRoid and tint them here.
- Gear is fitted automatically: the game measures each character's head,
  neck, torso and thigh from its skinned mesh. Very large hairstyles can
  still clip. The fit sliders exist for that.

**Chakra nature** is gameplay, not cosmetic: jutsu of your nature cost 20%
less chakra.

### Adding characters to the roster

- `game/assets/characters/player.vrm` is listed as "Your character".
- Any `.vrm` in `game/assets/characters/roster/` is listed by file name.
  For example, export one VRoid character in two outfits, as
  `roster/kaze_day.vrm` and `roster/kaze_night.vrm`.
- The placeholder Godette is always available.

Colour slots are found from material names. VRoid tags them (`_HAIR`,
`_CLOTH`, `_SKIN`, `_EYE` and so on), and most VRM models use similar words.
If a model's naming isn't recognised, it gets a single whole-model
**Body** colour instead.

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

- `scripts/character/character_model.gd` loads the profile's chosen model,
  or `player.vrm` if one exists, else `default/godette.vrm`. It fixes facing
  and scale, attaches the poser, and applies the profile live.
- `autoload/profile.gd` stores the customization. `scripts/character/character_styler.gd`
  classifies materials into colour slots and tints per-character copies.
  `scripts/character/character_gear.gd` measures body regions from skinned
  vertices (dominant bone per vertex, in the canonical frame) and fits gear
  to them on `BoneAttachment3D`s. `scripts/ui/customize_menu.gd` is the screen.
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
