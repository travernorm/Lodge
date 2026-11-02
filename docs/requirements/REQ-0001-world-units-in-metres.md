# REQ-0001: World units in metres

Status: implemented (approved by Traver 2026-11-02 at 8 px per metre; landed in PRs #14, #15, #16 and #19)

Traver decided on 2026-11-02 that game rules should use metres, not screen pixels. This REQ plans the switch. It needs the casting and river threads to agree, and Traver's approval, before any game code changes.

## Problem

Every rule in the game measures in screen pixels: cast reach, line out, drift slack, bite range, fight distance, river cells and current speeds. That works on one 320×200 screen, but breaks down as soon as:

* a stretch of river is wider than one screen, or the camera scrolls or zooms;
* real-world facts need to go in as data (a 10 m cast, a 1 m/s riffle, a fish that darts 1 m for food);
* the Switch or a different window size wants a different scale;
* the river bake (river thread) needs a real cell size in metres to give believable eddies.

## Player story

As a player, I want distances and speeds to feel like a real creek, so that what I learn about reading water and casting carries over to the next river.

## Feel goals

**Nothing should feel different after the switch.** This REQ is a change of units, not of tuning. Every number converts exactly, and the game plays the same. Retuning toward real-world values is a separate feel experiment afterwards (see "Follow-up").

## Scope

1. **One scale constant.** A small static class `WorldScale` (not an autoload) holds `PX_PER_M` and two helpers, `to_px()` and `to_m()`. Proposed value: **8 px per metre**. See "The scale" below.
2. **Models and data work in metres and metres per second.** `CastModel`, `CastRules` and its subclasses, `CastTuning`, `DriftModel`, `FightModel`, `Fish`, `FishSpecies`, `RiverField`, `StickGestures` (unitless already) and every `.tres` that holds a distance or speed.
3. **Views convert.** Only drawing code and the stream scene's layout turn metres into pixels, through `WorldScale`. The world's origin stays at the screen's top-left for now; a `Stretch` offset comes later.
4. **Field names say their unit.** Any exported field or constant with a distance or speed gets an `_m` or `_mps` suffix when its meaning changes (for example `stroke_time_per_px` becomes `stroke_time_per_m`). Fields stay where they are; ids never change.
5. **Tests compare in metres.** Assertions that use pixel values are converted. Their thresholds convert by the same factor, so every test checks the same behaviour.

## Out of scope

* Retuning anything toward real-world values.
* Multi-screen stretches, scrolling and the `Stretch` resource (ARCHITECTURE.md step F, after this).
* Changing the 320×200 render size or the art.
* Sprite sizes. Fish and flies stay drawn bigger than life so they read on a 7-inch screen.

## The scale

8 px per metre makes one screen **40 m long and 25 m tall**, with the test stream's water (y 58 to 148) about **11 m wide**. That's a believable small Eastern Oregon tributary. The current casting distances then come out like this:

| Today | In metres | Real small-stream casting |
|---|---|---|
| Line start 24 px | 3 m | Rod tip plus leader: about right |
| Short up to 48 px | up to 6 m | Short cast: 4 to 6 m |
| Middle up to 82 px | up to 10 m | Middle cast: 7 to 10 m |
| Line max 118 px | 14.75 m | A long small-stream cast: 12 to 15 m |
| Redband bite range 40 px | 5 m | |
| River cell 2 px | 0.25 m | Fine for a creek bake |

So the casting numbers already land close to real life at this scale. The river thread asked Traver how many metres a screen should cover; this is the proposal, and `PX_PER_M` is one constant if the answer changes.

**One finding from the conversion:** current speeds are much faster than a real creek at this scale. The riffle thalweg (55 px/s) becomes about 6.9 m/s, and the "foam" speed (36 px/s) about 4.5 m/s. A real riffle runs about 1 to 1.5 m/s. The pixel speeds were tuned so drift reads well on screen, which is normal for games. This REQ keeps them as they are. Whether to slow the water toward real speeds (and how that changes drift and mending) is the first follow-up experiment.

## Systems touched

| System | Changes? | Depends on the change? | How it's checked |
|---|---|---|---|
| Casting | Yes: `CastTuning`, `CastRules`, the rule sets' step lengths, `CastModel` reach and line out. Owned by the casting thread. | Fishing (landing point), Practice (target distances) | `cast_test`, `cast_rules_test`, `playthrough_test` (catch under every rule set, practice hits Short/Middle/Long) |
| River | Yes: `RiverField` cell size, speeds, lie thresholds; `stream_scene.gd` layout. Owned by the river thread. | Drift, fish lies, read-the-water view, water drawing | `river_test`, `data_test` (lies in water), `smoke_test` |
| Fishing | Yes: `DriftModel`, `FightModel`, `Fish`, `FishSpecies` fields and the fish `.tres` files | Casting (line target), debug overlay | `fishing_test`, `data_test`, `smoke_test`, `playthrough_test` |
| UI and modes | Views convert; practice target rings and the stroke log | — | `smoke_test`, `playthrough_test`, screenshots before and after |
| Input | No | — | — |
| Saves | No (none yet) | — | — |

## Plan: four small PRs, in order

Each PR plays exactly the same as before it, and passes every test.

1. **`WorldScale` and the views.** Add the class and a test for it. Nothing uses it yet except a new `tests/units_test.gd` that checks `to_px(to_m(x)) == x`. It changes no behaviour, but it is still game code, so it waits for approval with the rest.
2. **River (owned by the river thread, which has agreed; lands after PR #7 merges, since #7 touches `river_field.gd`, `fish.gd` and `fishing_controller.gd`).** The lie thresholds (`HOLD_SPEED`, `FOOD_SPEED`) are re-expressed relative to one water-speed constant, so the later speed experiment changes a single number. `RiverField` and the stream scene work in metres. The stream scene draws through `WorldScale`. `flow_at()` takes and returns metres; a thin pixel wrapper stays on the stream scene for one PR so casting and fishing keep working. Best done before the river thread's bake prototype, so the bake is in metres from day one.
3. **Casting (owned by the casting thread, which has agreed).** Land it right after PR #5 merges; no other casting code PRs are in flight. Everything that converts:
   * `CastTuning`: `line_start`, `line_max`, `line_gain_min`, `line_gain_max`, and `stroke_time_per_px`, renamed to `stroke_time_per_m`.
   * `CastRules.SHORT_MAX` and `MIDDLE_MAX` (48 and 82 px).
   * `TieredCastRules.step_lengths` (36, 66, 100 px).
   * `TempoCastRules`: line start, line max and line gain.
   * `CastModel` reach and line out.
   * `CastPractice.TARGET_REACH` (32, 65, 100 px) and its ruler drawing.
   * Pixel thresholds in `tests/cast_test.gd` and `tests/cast_rules_test.gd` (for example "falls short by more than 10 px").
   * The README's rule-set table, which quotes pixel values.
4. **Fishing.** `DriftModel`, `FightModel`, `Fish`, `FishSpecies` and the fish files. Fishing reads the river in metres directly, so the lie-area conversion in `Fish.respawn()` and the test-side conversions go. `lie_area` and `bite_range` become `lie_area_m` and `bite_range_m`.
   * *As built:* `stream_scene.flow_at()` and `is_water()` stay as **pixel helpers** rather than being removed. The cast controller still places the fly in screen pixels, and so do the streaks, so these are the right edge for those callers. `fishing_controller.gd` converts at its own edges, the cast's fly position and the drawing. Moving the controllers' positions into world metres belongs with the camera and scrolling work (REQ-0002) and ARCHITECTURE.md step B.

Before each PR: screenshots before and after (`tools/capture_screenshot.gd`) to show nothing moved, and the full `tools/run_tests.sh`.

## Acceptance criteria

* No model or data script contains a pixel value or a `px` comment (a check in `tests/architecture_test.gd`, proposed in ARCHITECTURE.md section 9). Automated.
* Only view scripts and the stream scene call `WorldScale.to_px()`. Automated, same test.
* Every existing test passes, with thresholds converted, not loosened. Automated.
* Screenshots of the cast, drift, fight and read-the-water view match before and after. Manual.
* The catch, Short/Middle/Long in practice, and the fight feel the same on keyboard and DualSense. Playtest.

## Playtest checks

The standard manual playtest from DEVELOPMENT_PROCESS.md after each of steps 2 to 4: cast Short, Middle and Long, land a fish, strike at nothing, reel in, switch practice mode and rule sets, cycle the debug views. Browser build after step 2 (rendering). No Deck check needed, since nothing about feel or performance should change; the PR says so.

## Follow-up (separate, after this REQ)

* **Feel experiment: water speed.** Two or three variants: today's speeds, real speeds (riffle about 1.2 m/s), and halfway. Drift, drag build-up and mend timing all change with it. Traver plays them and picks.
* **`Stretch` and scrolling** (ARCHITECTURE.md step F).

## Open questions

1. **For Traver** (the casting and river threads both agree): is 8 px per metre (a 40 m by 25 m screen, an 11 m wide creek) right?
2. ~~For the casting thread: any objection to the rename?~~ Answered 2026-11-02: no objection, 8 px/m sounds right, and the casting thread will own step 3 right after PR #5 merges.
3. ~~For the river thread: should the bake wait?~~ Answered 2026-11-02: yes, the bake prototype waits for step 2. 8 px/m answers the river thread's scale question.
