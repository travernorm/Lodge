# REQ-0011: Resting lies, and fish along the whole river

Status: draft

## Problem

On the demo stretch every fish lands in the upper half. The river field's lie score is a *feeding* score: slow water with fast water close by. Only the boulder pocket water, the first pool and the eddy score that well. The bend, the cut-bank pool and the tail-out never go above 0.44, and the generator only uses lies scoring 0.4 or more. Over 300 generated days, 1,496 of 1,500 fish sat in the upper half. Real trout also hold in **resting lies**: deep, slow water with cover, like an undercut bank on the outside of a bend.

## Player story

As a player, I want to find fish all along the river, including under the cut bank, so that walking down the stretch and reading each kind of water pays off.

## Feel goals

* A fish in the cut-bank pool is normal, not a surprise.
* Every screen of river has some fish, and the biggest fish still sit in the best water.
* The read-the-water view (View / F1, second press) marks resting lies as well as feeding lies, so it's clear why a fish is there.

## Scope

1. **A resting-lie score.** A new pure model, `RestingLies`, scores every cell of the field from 0 to 1. Its score is depth × slowness × cover:
   * depth: smoothstep from 0.4 to 0.75 of the reach's deepest water
   * slowness: 1 below the comfortable holding speed, 0 above the too-fast one (`RiverField.HOLD_SPEED`)
   * cover: 0.6 plus 0.4 × how far the cell is toward the outside of a bend (the cut-bank side)

   It reads the field's public layers and doesn't change the field, the water or `river_field.gd`. In a prototype on the demo stretch it gives about 180 cells of 0.4 or more in the cut-bank pool (best 0.85), where the feeding score has none.
2. **The generator uses both scores.** A cell's lie score is the higher of its feeding and resting scores. `FishPlan` says which kind of lie the fish is on.
3. **Fish along the whole river (spread by reach).** The river is cut into reaches of about one screen (40 m along the centreline). Each reach gets its share of `fish_count()` by length, rounded so the total stays the same. A reach with no lie scoring 0.4 or more passes its share to the nearest reach that has one. Within a reach, fish pick lies as today, with better lies more likely and 3 m apart. The biggest fish still go to the best lies across the whole stretch.
4. **The read-the-water view** draws resting lies in a second colour next to today's feeding lies.

## Out of scope

* Fish moving between a resting and a feeding lie with the time of day or the hatch (that comes with mood, FISH_LOGIC.md).
* Water types per lie and species habitat (REQ-0010, river features thread). REQ-0010 builds on this REQ's scores.
* New features in the lower section (river features thread, small track).
* Changing the water, the feeding score or the field fixture.

## Systems touched

| System | Changes? | Depends on the change? | How it's checked |
|---|---|---|---|
| Casting | No | No | `cast_test`, `playthrough_test` |
| River | New `RestingLies` (reads the field); read-the-water view draws it | Fishing | New `resting_lies_test`; `river_test` and the water fixture unchanged |
| Fishing | `FishGenerator` takes candidates from max(feed, rest), by reach | Debug overlay | `fish_generator_test` (new spread and resting checks), `smoke_test`, `playthrough_test` |
| UI and modes | Read-the-water view | No | `playthrough_test` (debug views cycled) |
| Input | No | No | `data_test` |
| Saves | No | No | n/a |

## Acceptance criteria

1. Every cell's resting score is between 0 and 1, and it's 0 on land, on rock and in water that's too fast to hold in. *(test)*
2. On the demo stretch, the cut-bank pool (tenths 6 and 7 of the river) has resting lies scoring 0.4 or more. *(test)*
3. Over 300 seeded days, every reach that has a lie scoring 0.4 or more holds fish on at least half of the days. No reach gets more than twice its share by length. *(test)*
4. The total number of fish is still `fish_count()` (5 on the demo), 3 m apart, and the biggest fish still sits on at least the median lie in 80% of days. *(test, existing)*
5. The water fixture and `river_test` are unchanged. *(test)*
6. Fish on resting lies can be hooked and landed like any other. *(playthrough)*

## Playtest checks

* Walk the whole stretch on a few loads. There are rises in the lower pools and along the cut bank, not just at the top.
* Open the read-the-water view at the bend. The resting lies show along the cut bank.
* Keyboard and DualSense. Watch the load time in the browser build (one more pass over the field at load).

## Open questions

1. **Reach length:** one screen (40 m, recommended), or two?
2. **Feeding versus resting.** Should a resting lie count the same as a feeding lie (recommended for now), or a little less, so the very best fish still favour feeding water until mood arrives?

## Architecture

*Self-review against ARCHITECTURE.md R1 to R12.*

* **Layers (R1):** `scripts/river/resting_lies.gd` (`RestingLies`) is a model (`RefCounted`). It reads `RiverField` (a model) and writes nothing back. `FishGenerator` builds one per stretch. The read-the-water view (debug overlay, layer 4) reads it.
* **Owner (R2):** `RestingLies` owns its `rest` layer, and only it writes it. The generator owns its candidate list.
* **Reach (R3):** the generator takes it as an argument, and the overlay finds it through the fishing node's existing group lookup, so no new reaches.
* **R4, R5, R6, R8, R11:** no data is written, nothing new is linked, and there are no strings as types. The reach split uses the generator's existing seeded lie stream. Everything is in metres.
* **R9:** `river_field.gd` is at 617 of 623 lines, so the score goes in its own script, and neither `river_field.gd` nor `stream_scene.gd` grows. The overlay change is a few lines in `debug_overlay.gd`.
* **R10:** the new script goes in the class index, and the system map's River row gains `RestingLies`.
* **R12:** no kind of thing gains place data.
* **Coordination:** the river features thread (REQ-0010, PR #51) agreed that this REQ owns lie scoring. It will read `RestingLies.rest` and weight species by water type on top of these candidates. Names agreed: their `WaterTypes` and `WaterTypeRules`, and this REQ's `RestingLies`.
