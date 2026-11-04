# REQ-0008: Weather generator

Status: draft

## Problem

Today the weather is a dice roll per scene load (REQ-0007): a random season, day, slot and weather, and a high picked anywhere in the season's range. Each day knows nothing about the day before, so it can't give a cold snap, a wet week or a run of hot summer afternoons, and late spring is as cold as early spring. The weather lives inside `Calendar`, so a second region (Alaska, the Keys) would have to share Central Oregon's climate. When the `Clock` arrives it needs something to ask "what's the weather on Summer 12", and the weather visuals need more than a weather name to draw drizzle or a downpour.

## Player story

As a player, I want the weather to behave like a real season, with spells that last a few days, highs that warm through spring and cool through fall, and storms that build in the afternoon, so that I can read the sky, plan a trip, and learn which days fish well.

## Feel goals

* Weather comes in spells. A rainy day is often followed by another; a summer heat run lasts.
* The year has a shape: Spring 1 feels like late winter, Spring 30 like early summer.
* A summer storm day starts sunny and turns in the afternoon.
* The same seed always gives the same year, and the debug overlay (F1 / Create) shows the day, the spell and the seed.

## Scope

### 1. A climate per region (data)

A new `Climate` resource holds a region's weather. `data/climates/central_oregon.tres` is the first, and every stretch uses it until regions exist. It takes over the weather numbers that are in `Calendar` today (season highs, weather odds, weather temperature drops), so `Calendar` keeps only the enums, the slot drops and the fish activity factors.

| Field | What it holds |
|---|---|
| `high_min_f`, `high_max_f` | The season's coldest and warmest daily high (moved from `Calendar`). |
| `weather_odds` (one list per season) | How often each weather comes up (moved from `Calendar`). Stays the long-run share. |
| `persistence` (per season, 0 to 1) | Chance tomorrow simply keeps today's weather before the odds are rolled. 0 is today's behaviour; about 0.5 gives spells of 2 to 3 days. |
| `swing_bands` | How far the high wanders day to day, in bands (1 = at most one band up or down). |
| `storm_slots` | The slots a storm can hit; earlier slots on a storm day take `before_storm` (Sunny for the high desert). |
| `intensity_min`, `intensity_max` (per weather) | The range a day's rain, snow or storm strength is rolled from. |

### 2. The generator (one model)

`WeatherGenerator` is a pure model: `year(climate, seed) -> WeatherYear`, 120 `WeatherDay`s.

1. **Weather by day.** Day 1 rolls from the season odds. Each later day keeps yesterday's weather with `persistence`, otherwise rolls the odds. This keeps each weather's long-run share at its odds while making spells.
2. **Highs by day.** A smooth curve through the year, passing each season's middle at day 15, plus a wander of at most `swing_bands` a day, kept inside the season's range. Weather drops apply on top (as today).
3. **Within the day.** A storm day uses `before_storm` until the first storm slot. Every other day has one weather all day.
4. **Intensity.** Rolled once per day for Rain, Snow and Storm; 0 for Sunny and Overcast.

`WeatherYear.conditions(season, day, slot, spring_fed) -> Conditions` hands out the same `Conditions` value as today. Water temperature keeps the REQ-0007 rule (high minus 2 bands, 30s to 70s, or 40s to 50s when spring-fed).

### 3. Conditions (the shape other systems read)

`Conditions` keeps season, day, slot, weather, air and water, and gains `intensity` (0 to 1). The weather visuals (REQ-0009) read only this, never the generator. The fish generator doesn't change.

Whoever owns the current `Conditions` emits `conditions_changed(conditions)` whenever it changes, so views repaint without polling. Today that's the fishing node, once per `stock()`; later it's the `Clock`, once per slot, with the same signal.

### 4. Before the clock

The fishing node still picks the day per load. It builds the year from the load seed, picks a season, day and slot from it, and asks the year for that slot's `Conditions`. The debug overlay adds the spell ("rain, day 2 of 3") and the intensity. When `Clock` arrives it holds the year and walks it, and nothing that reads `Conditions` changes.

### 5. Repeatable from the command line

`tools/weather_year.gd --seed 42` prints a year: one row per day with weather, intensity and high, plus a summary of each season's weather shares and average spell length, so a climate can be tuned before playing. `tools/generate_fish.gd` takes its day from the same generator.

## Out of scope

* The `Clock`, days passing, a calendar or forecast on screen.
* Weather visuals (the sibling thread).
* Wind, water level, clarity after rain, runoff.
* Storm feeding bursts and lightning sending you off the water (with `MoodRules`).
* Changes to fish activity, bite odds or hatches.
* Saving the year.

## Systems touched

| System | Changes? | Depends on the change? | How it's checked |
|---|---|---|---|
| Casting | No | No | `cast_test`, `playthrough_test` unchanged |
| River | No | No | `river_test` |
| Fishing | `stock()` takes its day from the year; overlay lines | No | `fish_generator_test`, `smoke_test`, `playthrough_test` |
| Conditions | New `Climate`, `WeatherGenerator`, `WeatherYear`, `WeatherDay`; `Calendar` loses its weather fields; `Conditions` gains `intensity` | Fishing, weather visuals, tools | New `weather_generator_test`, `data_test` |
| UI and modes | Debug overlay shows spell and intensity | No | `playthrough_test` (debug views cycled) |
| Input | No | No | `data_test` |
| Saves | No (none yet) | No | n/a |

## Acceptance criteria

1. The same climate and seed give the same year. *(test)*
2. Over 100 seeded years, each weather's share per season matches its odds within 3%. *(test)*
3. With persistence 0.5, the average spell is clearly longer than with 0 (at least 1.5 times). *(test)*
4. The high never moves more than `swing_bands` from one day to the next before weather, and stays inside the season's range. *(test)*
5. Average highs rise through spring and fall through fall. *(test)*
6. On a storm day, no slot before the first storm slot is Storm. *(test)*
7. Intensity is 0 for Sunny and Overcast and inside the climate's range otherwise. *(test)*
8. Every climate in `data/climates/` loads, has one number per season and weather, and its odds add up to 1. *(data_test)*
9. `tools/weather_year.gd` runs on every climate with no errors. *(test)*
10. The demo stretch still plays: a fish can be found, hooked and landed. *(smoke and playthrough)*

## Playtest checks

* Run `tools/weather_year.gd` with a few seeds: spells look believable, spring warms, summer storms show up in the afternoon.
* Load the stretch a few times: the overlay shows the day, the spell and the intensity, and fishing still works.
* Keyboard and DualSense, plus the browser build (the year is built at load, so check load time).

## Open questions

1. **Spells.** How long should a typical spell be? Recommended: persistence about 0.5 (2 to 3 days on average), tuned in the climate file.
2. **Climate per region.** Move the weather numbers out of `Calendar` into `data/climates/` now, so Alaska or the Keys is one new file later? Recommended: yes.
3. **Weather within a day.** Only storms change during a day (sunny morning, afternoon storm), or should rain also clear or set in partway? Recommended: storms only for now.
4. **Intensity.** Add `intensity` to `Conditions` for the weather visuals (drizzle vs downpour)? Recommended: yes.

## Architecture

*Review against ARCHITECTURE.md R1 to R12, on `main` at 0c8f5c5.*

**New scripts and layers (R1, R10).** All in `scripts/conditions/`, using only lower layers.

| Script | Class | Layer |
|---|---|---|
| `climate.gd` | `Climate` | Data (place). One file per region in the new `data/climates/` folder. |
| `weather_day.gd` | `WeatherDay` | Model (value): weather per slot, intensity, high, spell length. |
| `weather_year.gd` | `WeatherYear` | Model (value): 120 days and `conditions()`. |
| `weather_generator.gd` | `WeatherGenerator` | Model: `year(climate, seed)`. |

* **R2, R3.** The fishing node owns the year until `Clock` exists, as it owns `Conditions` today. Views (overlay, weather visuals) listen to `conditions_changed` (signal up) or read `fishing.conditions` through the existing group lookup. No new reaches. The signal replaces the `day_stocked` signal REQ-0009 proposed, so there's one.
* **R4, R5.** Nothing writes to the climate at runtime. The fishing node exports `climate: Climate` (a typed reference), like `calendar` today.
* **R6.** Weather and slots stay `Calendar` enums. `storm_slots` is export flags, checked against the enum order in `data_test` like hatch slots.
* **R8.** The year gets its own stream from the load seed, so the take rolls and the fish don't shift when a climate is tuned. `Conditions.roll()` is replaced by the year.
* **R9.** `fishing_controller.gd` is at 613 of its 615 cap. The change there is a swap inside `stock()` and stays within the cap. The overlay lines go in `FishGenerator.describe_day` (187 lines).
* **R12.** Climate is a place's data (a region), not a kind's. When regions exist, a region names its climate; until then the fishing node's export does.
* **Map updates in the same PR:** class index, section 2 (`data/climates/`), section 3.9, the system map's Conditions row, TOOLING.md for the new tool, and `data_test` loads the new folder.
* **Debt.** No ledger change.
* **Risk.** `generate_fish.gd` and `fish_generator_test` build days with `Conditions.at()`; that stays, so pinned-day tests don't move. Seeds give different rolled days than before, so any test relying on a particular rolled day re-pins.
