# REQ-0005: Fly rods that shape the cast

Status: draft

## Problem

The angler fishes with one invisible rod. Every cast reaches the same distance, every timing window is the same width, and any fish can be landed on any tackle. The story starts with Dad's old rod and grows toward streamers and big fish, so the rod needs to be a piece of content that changes how you fish, and adding a new rod should be one data file.

## Player story

As a player, I pick a rod and feel it: Dad's old glass rod is soft and forgiving but can't reach the far seam, a fast rod throws a long line but punishes sloppy timing, and a heavy rod lands the big fish that snap a light one.

As the designer, I add a rod by making one `.tres` in the tackle folder, and it shows up in the game.

## Feel goals

* Changing rods is felt within one cast: the meter's perfect band is wider or narrower, and the distance ruler tops out at a different place.
* What a rod does is readable on screen when you pick it: name, fly types, longest cast, biggest fish, and how forgiving it is.
* Today's feel is kept as one of the rods (the 5-weight), so nothing that feels right now is lost.

## Scope

### T1. The tackle folder

Flies and rods are grouped as **tackle**, the things you fish with:

* `data/flies/` moves to `data/tackle/flies/`; rods go in `data/tackle/rods/`.
* `scripts/fishing/fly_pattern.gd` moves to `scripts/tackle/fly_pattern.gd`, next to the new `scripts/tackle/fly_rod.gd`.
* Ids don't change (an id is the file name, not the path), so future saves are unaffected. `tools/build_catalog.gd`, `tests/data_test.gd`, the catalog and ARCHITECTURE.md section 2 follow the move.

Traver wrote "TOOLS". In this repo `tools/` already means developer scripts (the catalog builder, the test runner), so `data/tools/` would read as two different things. "Tackle" is the angler's word for rods, reels, lines and flies. If Traver prefers TOOLS, it's `data/tools/` with the same structure (open question 1).

### T2. Fly type on flies

* `FlyPattern.type`: an enum `DRY`, `NYMPH`, `STREAMER`, default `DRY`. The three flies today are dries.
* This is only a label for now. Nymph and streamer fishing (sinking line, retrieve) are later REQs.

### T3. The rod

`FlyRod` (`Resource`, `data/tackle/rods/<id>.tres`), with field names proposed for review:

| Field | Meaning | Read by |
|---|---|---|
| `id`, `display_name`, `description` | as on flies | catalog, the rod message |
| `weight` | rod weight, 1 to 10 (a "4-weight"); shown in the name, not used in maths | display |
| `fly_types` | which fly types it can throw (checkboxes: Dry, Nymph, Streamer) | fly box |
| `max_line_m` | most line it can carry: caps the cast's line out | casting |
| `forgiveness` | multiplies the timing windows (perfect and okay) and the overlap band. 1.0 is today | casting |
| `rated_length_in` | biggest fish (inches) it fights at full strength | fight |

1. **Compatibility.** The fly box only offers flies whose type the rod can throw. Changing rods re-ties the first compatible fly if the current one doesn't fit. A rod with no compatible fly in the box says so and won't start a cast while fishing (practice mode still casts).
2. **Durability.** A fish longer than `rated_length_in` loads the rod: the fight's tension is multiplied by `1 + overload × (length / rated - 1)`, so a fish 25% over the rating snaps the tippet noticeably sooner. `overload` is one tuning number (proposed 2.0); where it lives is settled in the engineering review. Below the rating nothing changes. When it bites, a fish that's too big gets a message: "That's a lot of fish for a 4-weight." Rods don't break; a broken rod needs owned gear and saves (open question 3). Fish length uses the existing `min_length_in` / `max_length_in`, so no new field on `FishSpecies`.
3. **Casting distance.** `CastModel` asks for `max_line()`, the smaller of the rule set's own cap and the rod's `max_line_m`. Every rule set calls it instead of reading `line_max` directly. Under "Count the false casts", a rod with `max_line_m` below the Long step simply can't reach Long.
4. **Casting forgiveness.** `CastModel.perfect_window()` and `ok_window()` multiply the rule set's answer by the rod's `forgiveness`, so it works under every rule set, and the meter draws the wider or narrower bands.

### T4. Three starter rods

| Rod | Types | Longest line | Forgiveness | Rated to |
|---|---|---|---|---|
| Dad's glass 4-weight (tied on at the start) | Dry | 10.25 m (top of Middle) | 1.3 | 16 in |
| Graphite 5-weight (today's numbers) | Dry, Nymph | 14.75 m | 1.0 | 20 in |
| Fast 7-weight | Dry, Streamer | 18 m | 0.75 | 28 in |

Every rod throws dries for now so every rod can fish today's flies. Compatibility is visible in the rod message and unit tested now, and it bites in play once the first nymph or streamer fly is added (data only).

### T5. Picking a rod

* **Change rod**: a new action, L2 (left trigger) on the controller and **R** on the keyboard, between casts, like changing flies. It cycles the catalog's rods and shows the rod's stats for a few seconds. This is a stand-in until a gear screen or the cabin rod rack exists (open question 2).
* A small `Tackle` model (`scripts/tackle/tackle.gd`, `RefCounted`) owns what's tied on: the current rod and fly, cycling, and the compatibility filter. It takes the fly box index out of `fishing_controller.gd`, which shrinks that file (R9 debt paid back) and is a first step toward step D's `FlyBox`.
* The catalog gains `rods` and `rod(id)`. The rod order in the catalog is the cycle order, so Dad's rod is first.

## Out of scope

* Nymph and streamer mechanics, new flies, new fish.
* Owning gear, buying rods, broken rods, saves, a gear menu.
* Reels, lines, leaders and tippet as separate tackle.
* Rod art. The rod pose keeps today's look; length or colour per rod can come with the visuals work.

## Systems touched

| System | Changes? | Depends on the change? | How it's checked |
|---|---|---|---|
| Casting | Line cap and timing windows read the rod | Practice ruler, meter bands | `cast_test`, `cast_rules_test`, new `rod_test`: each rule set with each starter rod |
| River | No | — | `river_test` |
| Fishing | Fly box filtered by rod; fight tension reads the rod | Bite odds unchanged | `fishing_test`, `match_fly_test`, new `rod_test` (overload maths, filter), playthrough |
| UI and modes | Rod message; practice ruler tops out at the rod's line | — | playthrough: change rod mid-session, in practice and fishing |
| Input | New `change_rod` action | Every input test | `data_test` parity, input drift check, README controls table |
| Content catalog | Rods added; flies move folder | Fly box | `catalog_test`, `data_test` |
| Saves | None exist yet; ids unchanged | — | `data_test` ids |

## Acceptance criteria

* A new `.tres` in `data/tackle/rods/` plus a catalog rebuild adds a rod with no code change (test with a fixture rod).
* With the 5-weight tied on, every cast, window and fight number is identical to today (test: same strokes, same results).
* `forgiveness` 1.3 widens the perfect and okay windows by 1.3 under all three rule sets (test).
* No rule set can put out more line than the rod's `max_line_m` (test, every rule set × every rod).
* The fly box never ties on a fly whose type the rod can't throw (test with a fixture nymph fly).
* A fish over `rated_length_in` reaches snap tension sooner under the same pressure; at or under it, the fight is unchanged (test).
* The playthrough lands a fish with each starter rod and switches rods in practice mode.
* `fishing_controller.gd` gets shorter and its R9 cap goes down.

## Playtest checks

Keyboard and DualSense: change rod (L2 / R) and read its stats; with Dad's rod, cast Short and Middle and feel the wider window, and try for Long; with the 7-weight, reach Long and feel the tighter window; hook a fish over 16 in on Dad's rod and feel the tippet go sooner; check practice mode's ruler with each rod. Browser build: the rod list isn't empty.

## Open questions

1. **Folder name:** "tackle" (recommended, avoids the clash with the repo's `tools/` folder and is the angler's word) or "tools" as written?
2. **Picking a rod:** a Change rod button now (recommended, L2 / R, so the rods can be compared by hand), or only Dad's rod in game until a gear screen exists?
3. **Durability:** oversized fish snap the tippet sooner, and rods never break (recommended for now), or should a rod break and be lost? Breaking needs owned gear and saves first.
4. **Starter rods:** are the three above, with these numbers, the right first set? They're data, so tuning them later is a small change.
