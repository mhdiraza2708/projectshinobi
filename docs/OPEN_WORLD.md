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

## On the road (`WorldEncounters`)

Between the places, the wilds are not empty. Every 300-500 m you travel
outside a region, something waits about 60 m ahead of you, on dry, level
ground clear of the regions, the places, rivers and lakes. All but the
ambush stand under a slim pillar of light (red for a rescue, the duelist's
nature colour, gold for a pilgrim or a cache) so you can see them coming:

| Kind | What happens | Pays |
|---|---|---|
| ambush | raiders spring out as you pass (one wave, two later in the story) | XP |
| rescue | raiders have a traveller cornered; they wait until you come near. Save the traveller and they tell you of the nearest place you haven't found (it goes on your map) | XP, a place |
| duelist | a wandering shinobi stands in the road, speaks, and duels you (a signature attack, health by story tier) | more XP |
| pilgrim | someone resting by the way; talk to them and they mark a place on your map | a little XP, a place |
| cache | a dropped bundle of supplies | XP, wounds bound, chakra full |

One at a time, never during a chapter; walk 170 m away from one you never
reached and it goes. Losing a road fight ends it (the road is long). The
slot counts each kind seen through (`world.encounters`). Fights run through
OpenWorld's quest fights and duels under the `road:` prefix.

## Getting to the work

The map's Travel list starts with **Go to: <tracked objective>**: the next
mission's pillar or the tracked side quest's place, found or not. You land
a few metres short, facing it; for a mission, arriving begins it.

Side quests (`data/quests.json`, 24 of them, three or more on every region)
unlock with the story and each other; their positions are in the region's own
metres, so they work on both layouts (a test checks every spot is walkable).

Code: `SiteBuilder` (layouts from the island props), `SiteNode`, `SiteMarker`,
`WorldSites` (streams sites by distance, state), `SiteActivities` (what to
do), `Bounties` (data loader).

## Music

`OpenWorld.track_for` picks it each frame from where you stand and the hour:

- inside a **village, shrine or ruin** (`WorldSites.place_near`: its grounds
  plus a margin, held a little longer once you are in): `village`, `shrine`
  or `hollow`;
- otherwise in a **region** (`Music.island_theme` by day, `Music.island_night`
  after dark: every region has a night piece of its own);
- out in the **wilds**: `road` by day, `road_night` after dark (the island
  layout keeps `sea` and `night`).

Fights choose their own: a camp plays `camp`, a named rival or a wanted
shinobi `duel`, and the other quest fights take turns at `battle`, `battle2`
and `battle3`. See [STORY.md](STORY.md#music) for the story's picks.

## Not yet

- Five Winds' leap stones, islets and gulls (the island layout only).
- Per-region ground palettes and paths on the pads (the continent is Emberwood
  green everywhere; region yards are bare earth).
- Roaming patrols you can see from afar, weather by region, collectibles
  beyond relics. (Road encounters are placed ahead of you, not walking the
  roads on their own.)
- Performance on real hardware has not been measured (the work here ran on
  CPU rendering only).
