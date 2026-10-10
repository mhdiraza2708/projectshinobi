# Prompts for more world props

The continent's places of interest (camps, shrines, villages, ruins, lairs)
are built from a small kit of props (`game/assets/models/`: house, fence,
gate, shrine, lantern, pillar, rock, dead tree...). These are the props that
would make them look like more than the kit, as prompts for a text-to-3D
model (Tripo and similar). None can be entered: they are single objects.

**How to make and add them**

- One object per generation, no ground or base, neutral background; ask for a
  *stylized, hand-painted, low-poly look* so they sit with the existing props.
- Export **GLB**, no rig (these are static; a rigged export is not needed).
- 1 unit = 1 metre; the sizes below are the real-world sizes to aim for (the
  game scales them).
- Save as `game/assets/models/<name>.glb` with the name in the first column,
  then ask for them to be wired into the site layouts (`SiteBuilder`); the
  loader already accepts `.glb` as well as `.gltf`.

| Name | Where it goes | Prompt |
|---|---|---|
| `tent_canvas` | camps (replaces the small shacks) | A weathered canvas field tent for a bandit camp, patched cloth over a wooden ridge pole, two wooden stakes and ropes, about 4 m long and 2.5 m high, stylized low-poly game prop |
| `banner_pole` | lairs, camps | A tall wooden war-banner pole with a tattered crimson cloth banner and a small iron spike on top, about 5 m high, stylized game prop |
| `campfire_stones` | camps | A ring of stones with stacked logs and charcoal in the middle, unlit, about 1.5 m across, stylized game prop |
| `crates_barrels` | camps, villages | A small cluster of two wooden crates and two barrels with rope, about 1.5 m across, stylized game prop |
| `hand_cart` | villages, camps | A rustic wooden two-wheeled hand cart with a few sacks on it, about 2.5 m long, stylized game prop |
| `jizo_statue` | roadsides, shrines | A small roadside stone jizo statue wearing a faded red bib, on a short stone base, about 1 m high, moss at the base, stylized game prop |
| `torii_small` | wayside shrines | A small vermilion wooden torii gate, weathered, about 3.5 m wide and 3.5 m tall, stylized game prop |
| `signpost` | roads | A wooden direction signpost with two angled arms and carved plates, about 2 m high, stylized game prop |
| `hay_bales` | villages | Three round straw bales stacked, tied with rope, about 1.5 m high, stylized game prop |
| `stone_well` | village centre | A round stone well with a small wooden roof and a bucket on a rope, about 2 m high, stylized game prop |
| `net_rack` | river and lake villages | A wooden rack for drying fishing nets with nets hanging from it, about 3 m wide and 2 m high, stylized game prop |
| `ishidoro_large` | shrines | A large stone garden lantern (ishidoro) on a tiered base with moss, about 2 m high, stylized game prop |
| `grave_markers` | ruins | A small cluster of weathered stone grave markers and a wooden sotoba plank leaning on one, about 2 m across, stylized game prop |
| `broken_statue` | ruins | A broken stone warrior statue on a plinth, head missing and one arm fallen beside it, vines on the stone, about 3 m high, stylized game prop |
| `bell_frame` | shrines, the "Last Bell" quest | A bronze temple bell hanging from a heavy wooden frame with a striking log, about 3 m high, stylized game prop |
| `ema_rack` | shrines | A wooden rack hung with rows of small votive wishing plaques (ema), about 2 m wide, stylized game prop |
| `footbridge` | rivers, lakes | A simple arched wooden footbridge with low rails, about 6 m long and 2 m wide, stylized game prop |
| `rowboat` | lakes, river banks | A small wooden rowboat pulled up on its side with two oars, about 4 m long, stylized game prop |
| `cairn_stack` | trail markers, the "Broken Cairns" lair | A tall balanced stack of flat stones as a trail cairn, about 1.5 m high, stylized game prop |
| `prayer_flags` | mountains, Five Winds | A line of faded prayer flags strung between two short wooden posts, about 5 m long, stylized game prop |

Rules the game keeps: nothing the player can walk into, nothing taller than a
pillar (6 m), nothing that needs a skeleton. Anything bigger than that is a
landmark, and is better made in Blender (`art/`) so it can have collision.
