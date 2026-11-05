# REQ-0014: Rivers in sections (the Upper Fall)

Status: approved by Traver 2026-11-05 (with the recommended answers). Step 1 (the river importer) merged in PR #60; step 2 (the split) is built.

Plan and review behind it: [River world: architecture review and authoring workflow](https://claude.ai/artifact/VvvhbTgccer9SNRCr27RXR).

## Problem

The game has one river: a 120 x 75 m demo stretch (about 200 m of creek) that the angler can only fish from the near bank. The Fall River needs to be 4 to 5 times longer, fishable from both banks, and joined to other water, ending at the Deschutes. Today one stretch is one map, built whole at load, with no way to cross the water or leave the map.

## Player story

As a player, I want to start at the cabin under a big waterfall, cross the footbridge, and fish my way down the Upper Fall on both banks without loading screens, then pass a short transition into the Lower Fall, so that the river feels like a place I explore and learn.

## Feel goals

- **One river, not a set of rooms.** Inside a section the camera scrolls without a seam, a pause or a pop.
- **Transitions are rare and earned.** Only between sections, at a natural landmark (a falls, a road bridge, a mouth), under a second of fade.
- **A big first view.** The Upper Fall opens on the foot of a tall waterfall (inspired by Tumalo Falls; we see the base, not the whole drop), its plunge pool, and a walking bridge just below. Placeholder art until Traver's art arrives, labelled as such.
- **The tutorial is the cabin reach** under the falls.

## Decisions so far (Traver, 2026-11-05)

1. A river is split into named **sections** (Upper Fall, Lower Fall, Upper Deschutes). Each section scrolls seamlessly; a short transition sits between sections.
2. The Upper Fall starts at a waterfall, with a walking bridge right below; placeholder art for now.
3. The Deschutes is 4x the Fall River's width (64 m). Not built in this REQ.
4. River sheets live in the repo (`content/`); the importer also reads a CSV exported from a Google Sheet.
5. The cabin reach under the waterfall is the tutorial.

## Scope

Built in three PRs, in this order. Each leaves the game playable.

**PR 1: River importer and preview plates (tool, no game code).**
- `content/rivers.csv` (one row per river) and `content/river_markers.csv` (one row per distance marker), as in the plan's template. Distances are metres downstream; river left and right face downstream.
- `tools/import_river.gd` with `--check` (lists problems by river and distance: a feature off the water, overlapping features, a bad kind) with the sheet as the source of truth for a generated stretch (moves are made in the sheet; an export from the Inspector back to the sheet can follow if it's missed).
- It writes one `Stretch` per section in `data/stretches/` and a preview plate per section (a top-down map labelled by distance) to `docs/rivers/` for review. Planned kinds (waterfall, bridge, cabin, ford, trail ...) are drawn on the plate in red and built by step 3.

**PR 2: Split before growing (refactor, no change on screen).**
- `river_field.gd` split into a builder and the read-only queries (pays down its R9 cap).
- Step A2: `stream_scene.gd` split into `RiverView`, an `Angler` node and a camera owner (pays down its R9 cap). The recorded water fixture must not change.

**PR 3: Sections, chunks, links and the Upper Fall.**
- **Chunks.** A section's field is built in chunks about one screen across, with an overlap so the water matches at every seam. The scene keeps the chunks around the camera built and drops far ones, a little work per frame (the web build is single-threaded). Baking chunks offline stays on the backlog and drops in later without changing the data.
- **New data.** `River` (its sections in order, the river it flows into and where, and defaults every section shares: spawn table, hatches, fish per 100 m, water look). `SectionLink` on a `Stretch`: an exit, the section it leads to (a typed reference, R5) and where the angler arrives. `WorldMap`: the rivers and the starting section.
- **New features, one script each in the kit.** `Bridge`: a deck across the water the angler can walk and cast from; the water runs under it. `Waterfall`: a band across the top of the river that blocks walking and casting, with white water and a plunge pool (depth from the sheet).
- **Footing.** A small model answers "can the angler stand here?": dry land or a bridge deck. Wading comes later (REQ-0015).
- **Fish per chunk.** `FishGenerator` stocks each chunk when it is built, seeded by the day and the chunk, with `fish_per_100m` over that chunk's river length. Caught fish stay gone for the session.
- **Content.** The Upper Fall from Traver's sheet: waterfall, plunge pool, footbridge, cabin reach (tutorial), then the reaches below. The current demo stretch becomes the placeholder Lower Fall, linked from the Upper Fall's downstream end, until its own sheet rows exist.

## Out of scope

Wading, fords and depth in metres (REQ-0015). The Deschutes, inflows, width keys, boats. Screen size (its own REQ: the rules are in metres, so it doesn't touch this one). Final waterfall, bridge and cabin art. Saves. The tutorial's teaching steps (this REQ only places it).

## Systems touched

| System | Changes? | Depends on the change? | How it's checked |
|---|---|---|---|
| Casting | No | Lands on bridge decks as on land; can't land above the falls | `cast_test`, `playthrough_test` |
| River | Yes: chunked field, `River`, `SectionLink`, `WorldMap`, `Bridge`, `Waterfall`, importer | Everything that reads the field | `river_test` (chunk-built field matches a whole build within tolerance; fixture unchanged), new `section_test`, `data_test` (every section, link and river loads; features in the water) |
| Fishing | Yes: stocking per chunk | Drift and lies read the chunk under the fly | `fish_generator_test` (same seed gives the same fish per chunk), `playthrough_test` (catch in two chunks) |
| Tall grass, water look | Built per chunk | | `grass_test`, `water_view_test` |
| UI and modes | Transition fade; debug overlay shows the section and chunk | | `playthrough_test` (walk across a seam and through a transition) |
| Input | No new bindings | | input parity check |
| Saves | No | | |
| Content catalog | New sheets and importer | | new `river_import_test` (sheet matches the data, bad rows caught) |

## Acceptance criteria

- `tools/import_river.gd --check` passes on the repo's sheets and catches each bad-row case (automated).
- A chunk-built field matches the whole-built field within a small tolerance for velocity, depth and lies, including at seams (automated).
- The angler walks the Upper Fall from the bridge to its downstream end with no frame over 16.7 ms on the Deck from chunk building (playtest; automated timing on CI as a guide).
- The angler can cross the footbridge and fish from both banks and from the deck (automated walk plus playtest).
- Nothing can be walked onto or cast above the waterfall (automated).
- Walking off the downstream end fades into the Lower Fall at its arrival point, and back (automated).
- Same day and seed gives the same fish in every chunk, however the player walks (automated).

## Playtest checks

DualSense and keyboard: start under the falls, cross the bridge, cast Short, Middle and Long from both banks and from the deck, land a fish in two different chunks, walk the whole Upper Fall watching for hitches at seams, pass into the Lower Fall and back. Browser build: the same walk, watching for hitches.

## Open questions (answered by Traver, 2026-11-05: "This works")

1. How long is the Upper Fall? About 500 m of river, half of the Fall River.
2. Who writes the Upper Fall rows? Traver, in the sheet; Claude seeded a first draft (`content/river_markers.csv`) for Traver to edit.
3. Is the old demo stretch fine as the placeholder Lower Fall until its rows exist? Yes.
