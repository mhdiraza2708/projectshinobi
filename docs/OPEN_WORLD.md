# The open world

Free roam happens in one of two worlds. The **continent** (one streamed
landmass, `ContinentWorld`) is the default; the **sea of islands** (the
original; six islands in a sea, `Archipelago`) is a choice. Choose in the
pause menu (Accessibility tab, "World": applies next time you enter the
world), or run with `--world=continent` / `--world=islands`. Each layout keeps its own saved
position, so switching never strands you; quests, story progress, XP and
attunements are shared.

## How the continent is built

- `ContinentLand` (`scripts/world/continent/`) is a pure function of (x, z):
  height, biome paint, roads, rivers, lakes. The same every time; 4096 m
  square; the six story regions stand on flat pads (`pad_height`).
- `Continent` streams it round the player as chunks of several levels of
  detail, collision only near. `ContinentScatter` plants trees and boulders
  (and keeps out of roads, rivers, lakes, region yards and site footprints).
- `ContinentWorld` extends `Archipelago`, so `OpenWorld`, the story and the
  quests run on it unchanged: `offset(id)` is a region's pad, `focus_on(id)`
  rebases the world so a chapter's region is at the origin, `on_island`,
  `island_near` and `on_water` answer the same questions. Each region is an
  `Island` in *overlay* mode (`ground_at`, `surface_fn`): its authored props
  and colliders, standing on the continent's ground instead of its own.
- The ground comes up where the world will place the player and follows them
  only afterwards (`ground_ready`, `follow_player`, `settle_ground`). Fast
  travel and respawn wait for ground at the destination.

## Places of interest (`ContinentSites`)

About sixty sites planned from the land (the same every time, nothing to
save): level dry ground, spread along the roads and out in the wilds, clear
of the regions.

| Kind | What it is | What you do |
|---|---|---|
| camp | raiders' camp, a fire and shacks | come near: they ambush you in waves (danger and the story tier set who) |
| shrine | torii, shrine, lanterns, a blue light | Interact to attune: rest, XP once, and it is a fast-travel destination |
| village | houses, fences, lanterns, a board | Interact at the board for a contract |
| ruin | broken gate, fallen pillars, a gold light | walk over the relic |
| lair | a banner, a burnt gate, a hut | a wanted shinobi (`data/bounties.json`) speaks, then duels you (signature attacks) |

A contract names a camp (every third: a wanted shinobi's lair) near the
board and pays double. Found sites show on the map; shrines you attuned to
join the Travel list. State is kept in the slot's `sites` record
(`found` / `done`); `world.contract`, `relics`, `bounties` count progress.

Finishing a quarter, half, three quarters and all of a kind pays a growing
bonus (`SiteActivities.milestone`). The Quests tab lists the tally.

Side quests (`data/quests.json`, 24 of them, three or more on every region)
unlock with the story and each other; their positions are in the region's own
metres, so they work on both layouts (a test checks every spot is walkable).

Code: `SiteBuilder` (layouts from the island props), `SiteNode`, `SiteMarker`,
`WorldSites` (streams sites by distance, state), `SiteActivities` (what to
do), `Bounties` (data loader).

## Not yet

- Five Winds' leap stones, islets and gulls (the island layout only).
- Per-region ground palettes and paths on the pads (the continent is Emberwood
  green everywhere; region yards are bare earth).
- Music for the wilds (it plays the sea track between regions).
- Roaming patrols, weather by region, collectibles beyond relics.
- Performance on real hardware has not been measured (the work here ran on
  CPU rendering only).
