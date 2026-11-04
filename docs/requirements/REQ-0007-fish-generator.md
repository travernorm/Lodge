# REQ-0007: Fish generator

Status: review

## Problem

Every stretch is stocked by hand today. `Stretch.spawn` says "two redbands, one cutthroat, one brook", every fish gets a random length inside its species range, and each one takes a lie from the river field. The fish are the same every visit no matter the season, the time of day or the weather, and the bugs in the river play no part. To fill many stretches with many species, a stretch needs to describe *what could live here and how common it is*, and one generator needs to turn that plus today's conditions into the fish in the water.

## Player story

As a player, I want each visit to a stretch to hold a believable, slightly different set of fish, where what I find depends on the river, the season, the time of day and the weather, so that reading the conditions and the water pays off and a stretch never feels solved.

## Feel goals

* The river looks alive in the right way: more rises at a good hatch on an overcast evening, fewer on a bright noon in the 70s.
* Big fish are rare and sit in the best water. Scarce species feel scarce.
* Nothing is hidden: the conditions, the hatch and the seed are readable in the debug overlay (F1 / Create), and the same seed always gives the same river.

## Scope

The simplest version that's worth playing.

### 1. The generator (one script for any stretch)

A pure model, `FishGenerator`, with one entry point:

```
generate(stretch, river_field, conditions, rng) -> Array[FishPlan]
```

It reads only data and the river field, so it runs on any stretch that has the schema filled in, in the game, in tests and from a command-line tool. It scans the river field once per stretch for candidate lies and caches them, so generating again (or 1,000 times in a test) is cheap. It works in four steps:

1. **Who can be here.** Each spawn entry is eligible if the season and day are inside its window and the water temperature band is inside the species' range.
2. **How many.** Count the lies above the lie threshold (the stretch's capacity), then fill `stretch.fish_per_100m × river length`, capped by capacity.
3. **Which species.** For each fish, pick an eligible species weighted by its scarcity (`SpawnEntry.abundance`).
4. **Size and lie.** Roll a length skewed toward the small end of the species range, so the top inch or two is rare. Sort fish by length and give the biggest the best lies (with a little noise), pairing fish sorted by length with lies sorted by score.

A `FishPlan` is a small value (species, length, lie). The fishing node turns each plan into a `Fish`, so `Fish` stops rolling its own length and lie. A fish that breaks off returns to its planned lie; a landed fish is gone for the session, as today.

### 2. The river schema (on the `Stretch`, the place)

| Field | What it holds |
|---|---|
| `spawn: Array[SpawnEntry]` | Each entry: `species`, `abundance` (0 to 1, how common), and a season window (`from` and `to` as season + day, default all year). Replaces today's fixed `count`. |
| `fish_per_100m` | How rich the water is. The demo stretch is tuned so it holds about what it does today (5 fish). |
| `hatches: Array[HatchEntry]` | The insects in this river: `insect`, season window, the slots it comes off in, the weathers that turn it on or off, and `strength` (0 to 1). |
| `spring_fed` | Water temperature stays in the 40s to 50s all year instead of following the air. |

### 3. The weather and date schema (a `Conditions` value)

`Conditions` holds season, day (1 to 30), slot (Dawn to Night), weather (Sunny, Overcast, Rain, Snow, Storm), air band and water band. Water band follows the rule in SPECIES_AND_CONDITIONS.md: the day's air high minus 2 bands, kept between the 30s and 70s, unless the stretch is spring-fed.

There's no clock yet (ARCHITECTURE step G), so for this REQ the conditions are **rolled once per scene load from the seed**, using the season temperature ranges and weather odds in SPECIES_AND_CONDITIONS.md (those tables become a `data/calendar.tres`). A debug option fixes them for testing. When `Clock` arrives it builds the same `Conditions` and nothing in the generator changes.

### 4. What the conditions change that you can see

* **Who's there** (season windows, water temperature), from step 1 above.
* **The hatch.** The active hatch is every `HatchEntry` that's in season, in this slot, and allowed by this weather. It's shown on the debug overlay.
* **How often fish rise.** Each fish's rise rate (today's dimple timer) is scaled by an *activity* number: the strongest active hatch the species eats (from its diet), times a slot and weather factor from `data/calendar.tres`, with a floor so a fish with no hatch still rises now and then. This is the only tell for fish, so it's what makes the conditions readable. Bite odds don't change in this REQ.

### 5. Repeatable from the command line

`tools/generate_fish.gd` runs the generator on any stretch and prints the result:

```
godot --headless -s tools/generate_fish.gd -- --stretch demo_freestone --season summer --day 12 --slot dusk --weather overcast --seed 42
```

It prints the conditions, the active hatch, and one row per fish (species, length, lie, lie score). With `--runs 100` it prints a summary (fish per species, average and biggest length) so you can tune a new stretch's scarcity numbers before playing it.

### 6. Seeds

One seed per scene load, shown in the debug overlay. The generator gets its own `RandomNumberGenerator` stream from that seed, so the take rolls and the cast don't change what's generated (R8).

## Answering "anything else I'm missing?"

Inputs worth adding. **In scope** means this REQ, **later** means a REQ of its own.

| Input | Why it matters | Here? |
|---|---|---|
| Water temperature | What fish actually feel; turns trout off in a heat wave, keeps spring creeks fishing | **In scope** (derived from the date and weather) |
| Time-of-day slot | Hatches and rises happen at set times (PMD mornings, caddis at dusk) | **In scope** |
| Lie quality from the river | Puts fish where real fish would be, biggest in the best water | **In scope** (existing lie scores) |
| Fish density per stretch | How many fish a stretch holds, separate from which species | **In scope** |
| Size skew | Makes trophies rare instead of every size equally likely | **In scope** |
| A seed | Repeatable tests, and a bug report can name the river it saw | **In scope** |
| Already-caught fish | Landed fish stay out for the session | **In scope** (kept from today) |
| Water type per lie (riffle, run, pool, seam, eddy, undercut) | Browns in pools, redbands in seams. Needs the river field to classify water | Later (river thread) |
| Water level and clarity | Runoff, low summer water, coloured water after rain | Later |
| Trophy fish placed by hand | "The big brown under the cabin boulder" | Later |
| Persistence and depletion | Keep a stretch's fish between visits; kept fish refill slowly | Later (needs saves) |
| Schooling (whitefish, salmon) | Some species hold in groups | Later |
| Mood and hatch-matched bite odds | Hatch raises what fish want and how picky they are | Later (FISH_LOGIC steps 5 and 6) |

## Out of scope

* A real clock, the passage of days, or a calendar on screen. Conditions are fixed for a visit.
* Weather or season visuals (sky, light, snow).
* Changes to bite odds, the fight or selectivity.
* New species, flies or insects (content wave W1 is on hold). The demo stretch gets hatch entries for the insects that already exist.
* Saving populations between visits.
* Water types per lie.

## Systems touched

| System | Changes? | Depends on the change? | How it's checked |
|---|---|---|---|
| Casting | No | No | `cast_test`, `playthrough_test` unchanged |
| River | `Stretch` gains fields; `SpawnEntry` changes; new `HatchEntry` | Fishing reads them | `river_test` (field fixture unchanged), `data_test` |
| Fishing | Stocking moves to the generator; `Fish` takes a plan; rise rate reads activity | Debug overlay | New `fish_generator_test`, `fishing_test`, `caught_fish_test`, `smoke_test`, `playthrough_test` |
| UI and modes | Debug overlay shows seed, conditions, hatch | No | `playthrough_test` (debug views cycled) |
| Input | No | No | `data_test` |
| Saves | No (none yet). New ids (season, slot, weather) are enums, not saved | No | n/a |
| Content catalog | No new kinds; `data/calendar.tres` is a single file | No | `data_test` |

## Acceptance criteria

1. Same stretch, conditions and seed give the same fish, every time. *(test)*
2. A species outside its season window or temperature range never appears. *(test)*
3. Over 1,000 seeded runs, each species' share matches its abundance within 3%. *(test)*
4. The number of fish follows `fish_per_100m` and never exceeds the lies available; no two fish closer than the lie gap. *(test)*
5. The biggest fish of a generation sits on a higher-scoring lie than the median fish in at least 80% of runs. *(test)*
6. Lengths stay inside each species' range, and the top 10% of the range shows up in under 10% of fish. *(test)*
7. The active hatch matches the stretch's hatch table for given conditions (season, slot, weather). *(test)*
8. A species that eats the active hatch rises more often than in the same conditions with no hatch. *(test)*
9. `tools/generate_fish.gd` runs on every stretch in the catalog with no errors. *(test, runs in `run_tests.sh`)*
10. The demo stretch still plays: a fish can be found, hooked and landed under default conditions. *(smoke and playthrough)*
11. The debug overlay shows the seed, the conditions and the active hatch. *(playtest)*

## Playtest checks

* Load the stretch a few times: the fish and the conditions change, and the overlay (F1 / Create) shows why.
* Force a summer noon in the 70s, then an overcast dusk with caddis on: the river should look clearly busier in the second.
* Land a fish; it stays gone for the session. Break one off; it comes back to the same lie.
* Keyboard and DualSense, plus the browser build (the generator runs at load, so check load time).

## Open questions

Answered by Traver on 2026-11-04 (all as recommended):

1. **Fish per screen.** Keep the demo stretch about as rich as today (5 fish over 120 × 75 m), so the change is in *which* fish, not how many.
2. **Conditions before the clock.** Roll them randomly each load from the seed; a debug option can pin them.
3. **Water temperature.** Air high minus 2 bands, kept between the 30s and 70s, with a `spring_fed` switch per stretch.
4. **Scarcity.** `abundance` is a 0 to 1 weight per spawn entry, not a fixed count.

## Architecture

*Step 2a review, 2026-11-04, against ARCHITECTURE.md R1 to R12. Line numbers are from `main` at 58e3bf6.*

**1. New scripts and layers (R1, R10).** Everything uses only lower layers. A new `scripts/conditions/` folder will also hold `Clock` later.

| Script | Class | Layer | System |
|---|---|---|---|
| `scripts/conditions/calendar.gd` | `Calendar` | Data | Conditions. Holds the `Season`, `Slot` and `Weather` enums, the season air ranges, the weather odds and the activity factors for slot and weather. `data/calendar.tres` is its only file. |
| `scripts/conditions/season_window.gd` | `SeasonWindow` | Data | Conditions. `from`/`to` as season + day, and `contains(season, day)`, which wraps across winter. A null window means all year. |
| `scripts/conditions/conditions.gd` | `Conditions` | Model (value) | Conditions. Has `roll(calendar, rng, spring_fed)` and `describe()`. |
| `scripts/river/hatch_entry.gd` | `HatchEntry` | Data (place) | River, fish |
| `scripts/fishing/fish_generator.gd` | `FishGenerator` | Model | Fishing (fish) |
| `scripts/fishing/fish_plan.gd` | `FishPlan` | Model (value) | Fishing (fish) |

* The enums live in `Calendar`, which is data, so `HatchEntry` and `FishSpecies` never depend on a model. For the same reason, "is this hatch active" is answered in the model, not in `HatchEntry`.
* `tools/generate_fish.gd` is a tool: it goes in TOOLING.md, finds stretches through `Catalog.shared()`, and turns `--season summer` into the enum at the command-line edge.

**2. Owners (R2, R3).** Until `Clock` exists, the fishing node owns the seed, the `Conditions` and the fish, as the session will later. Each `Fish` owns its `activity`, which is set once when the fish is built.

* Generation goes through a new public `stock(conditions, seed)` on the fishing node.
* `_ready` calls it with a fresh seed, plus either rolled conditions or an exported `fixed_conditions`. Tests call it with pinned values.
* It reuses the existing `river` and `stretch` reaches, so it adds no R3 reach. `stream_scene.gd` is at its 460-line cap and isn't touched.
* The debug overlay reads `fishing.conditions` and `fishing.seed` through its existing group lookup.

**3. Rule checks.**

* **R6:** season, slot and weather are enums. `HatchEntry` slots and weathers are export flags, and `data_test` checks that the flags match the enum order.
* **R12:** the water temperature range is a trait of the kind, so it goes on `FishSpecies` as `water_min_f`/`water_max_f` (the lower °F of each band, 30 to 70). Abundance and the season window describe the place, so they go on `SpawnEntry`.
* **R5:** `HatchEntry.insect: Insect` and `SpawnEntry.window: SeasonWindow` are typed references.
* **R4:** the generator writes to no resource.
* **R8:** one root seed per load is split into named streams: conditions, generate and take. The take stream replaces the fishing node's `randomize()`.
* **R11:** density is per 100 m of river, measured along the centreline inside the map (`Stretch.river_length_m()`).

**4. Debt: this pays some back.**

* **R8:** the `randomize()` cap for `fishing_controller.gd` goes from 1 to 0.
* **R9:** stocking, `_lies_except` and `stocking` leave `fishing_controller.gd`, so it drops by 8 or more lines, and the 615 cap is lowered to match.
* **`Fish` gets simpler:** it no longer picks its own lie or length.

**5. Data and content.**

* **`demo_freestone.tres`:** the two redband entries merge into one. Abundance is about redband 0.6, cutthroat 0.2 and brook 0.2. `fish_per_100m` is about 2.7, which gives 5 fish over about 185 m of river. Hatch entries are added for the six existing insects.
* **`content/fish.csv`:** gains `water_min_f` and `water_max_f`, re-exported with the importer.
* **`data_test`:** loses its `count` and `stocked()` checks. It gains checks for abundance range, no duplicate species per stretch, window days from 1 to 30, real hatch insects, `fish_per_100m > 0`, temperature min ≤ max, and that `calendar.tres` weather odds sum to 1 per season.
* **No new data folder.** `calendar.tres` is a single file like `cast_tuning.tres` and isn't in the catalog.
* **Doc updates in the same PR:** ARCHITECTURE sections 2, 3.6, 3.9, 7, 9 and 11, the decision log, and the system map row "Conditions → Fishing".

**6. Risks and the tradeoffs chosen.**

* **Speed.** `RiverField.pick_lie()` scans every cell on each call, which is too slow to repeat. The generator caches the candidate lies once per stretch. The river thread is asked for a small `lie_cells(area, min_score)` query instead of reading the field's arrays directly.
* **Determinism.** The same seed gives the same fish on the same build. That isn't promised across platforms. Each stage has its own sub-stream, so tuning lies doesn't reshuffle species. The fish count rounds deterministically.
* **Break-offs.** Today `respawn()` gives a broken-off fish a new lie and length. It will return to its planned lie, as FISH_LOGIC.md says.
* **Activity floor.** Without one, a fish with no hatch would never rise and would have no tell.
* **Tests that assume a particular fish:** `smoke_test` (5 fish), `playthrough_test` (`fish[0]`, seeding after load) and `caught_fish_test` (`_lies_except`). They pin seed and conditions through `stock()`. The lie test becomes "a break-off returns to the same lie".
* **Criterion 9.** `fish_generator_test` calls the tool's `run(args)` on every catalog stretch, because the runner only runs `tests/*_test.gd`.
* **One-screen test stream.** It has no stretch, so it gets no fish, as today. The conditions still show.

**7. Backlog.**

* **Pulled in:** the "seed hook" half of the test-accessors item.
* **Pushed out:** step A (splitting `fishing_controller.gd`), `Clock`, `MoodRules`, persistent populations, `cast_model.gd`'s `randomize` (the casting thread's), the shared test input helper, and the baked field.
* **Added for the river thread:** the `lie_cells` query on `RiverField`.
