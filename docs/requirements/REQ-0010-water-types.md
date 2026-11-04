# REQ-0010: Water types per lie

Status: draft

## Problem

The river field scores every cell as a lie, but it can't say what *kind* of water a lie is. So every species goes anywhere: a brook trout is as likely in the fast seam as in a slow pocket. FISH_LOGIC.md promises that reading the water tells you who lives there ("browns in pools, redbands in seams"), and REQ-0007 left it for the river thread. Without it, new river features change where fish sit but never *which* fish sit there.

It also leaves half the demo stretch empty, because lie scoring only rewards feeding water. REQ-0011 (fish generator thread) fixes that with a resting score for deep, slow, covered water like the cut-bank pool. This REQ builds on it and doesn't change lie scores.

## Player story

As a player, I want each kind of water (riffle, run, pool, tail-out, pocket, seam, eddy) to hold the fish that favour it, so that when I learn a stream I can look at a piece of water and guess what's in it.

## Feel goals

* Water types match what an angler would call them by eye: fast and shallow at the head is a riffle, the deep slow bend is a pool, the slack behind a boulder is a pocket.
* A species turns up mostly in its favourite water, but not only there. A brook trout in a riffle is a surprise, not an impossibility.
* Nothing is hidden: the read-the-water debug view (F1 / Create) tints each water type with a legend, and each fish's lie shows its type.

## Scope

### 1. Water types (river)

Seven types, as an enum: **Riffle, Run, Pool, Tail-out, Pocket, Seam, Eddy.** Every wet cell gets exactly one. They come from the layers the field already has (speed, depth, seam strength, solid cells, flow direction), checked in this order, first match wins:

| Type | Rule (thresholds are data, tuned by eye) |
|---|---|
| Eddy | The water runs back upstream (flow against the river's downstream direction). |
| Pocket | Slow water within about 1.5 m downstream of something solid, in otherwise fast water. |
| Seam | Seam strength above a threshold. |
| Pool | Deep and slow. |
| Tail-out | Getting shallower downstream, just below a pool. |
| Riffle | Shallow and fast. |
| Run | Everything else. |

The classifier names no feature kind, so any feature added later (a logjam, a plunge pool) gets typed water for free. Thresholds live in one data file, `data/water_types.tres`, so Traver can tune them in the Inspector.

### 2. Habitat (fish)

Each species gets a **habitat** list: water type and how much it likes it, 0 to 1, in the same shape as its diet. Types it doesn't list get a small floor (default 0.2), so fish still stray. In the sheet, the `habitat` column reads like the diet column: `pool:1;pocket:0.8;seam:0.4`.

Starting habitats for today's three species (tunable):

| Species | Habitat |
|---|---|
| Redband | seam 1, riffle 0.8, run 0.6 |
| Westslope cutthroat | riffle 1, run 0.8, tail-out 0.6 |
| Brook | pocket 1, pool 0.8, eddy 0.6 |

### 3. Generation

The fish generator (REQ-0007) changes its species and size steps (it takes lies from REQ-0011):


* **Which species.** Each lie picks its species weighted by *abundance × habitat for that lie's water type*, instead of abundance alone.
* **Size and lie.** Sizes are still rolled leaning small and the biggest go to the best lies. Each fish rolls a size *rank* (0 to 1), the best lies get the highest ranks, and a fish's length is that rank within its own species' range. So "big fish in the best water" still holds across species.

Fish count, season, temperature, hatch and activity don't change. Bite odds don't change.

## Out of scope

* Undercut banks and other cover (the "cover features" option, next).
* Resting and feeding lies, and fish moving between water types with mood.
* Water type changing bite odds, rise rate or fight.
* New species or flies (content wave still on hold); existing species only gain a habitat.
* Showing water types to the player outside the debug view (that's an art question for later).

## Systems touched

| System | Changes? | Depends on the change? | How it's checked |
|---|---|---|---|
| Casting | No | No | `cast_test`, playthrough |
| River | Yes: new classifier and thresholds data | Fishing reads it | New `water_types_test`, `river_test` fixture unchanged |
| Fishing | Yes: species pick and size rank in `FishGenerator`; `FishSpecies.habitat` | | `fish_generator_test` additions, `playthrough_test` catch in two water types |
| UI and modes | Debug view only: water type tint, legend, lie type | | Playtest, `playthrough_test` cycles debug views |
| Input | No | | Input map drift check |
| Saves | No | | |

## Acceptance criteria

1. Every wet cell of the demo stretch has exactly one water type, and every type except Tail-out appears at least once. *(test)*
2. Hand-picked spots on the demo stretch get the right type: the head riffle, the boulder pockets, the eddy, the bend pool. *(test)*
3. The classifier is deterministic and the river fixture (`demo_field.txt`) doesn't change. *(test)*
4. Once REQ-0011 has merged, brook trout (pocket, pool) show up in the cut-bank pool, and redbands (seam, riffle) mostly upstream. *(test)*
5. On a test stretch with two equally common species, one liking only pools and one only riffles, at least 70% of each species' fish over 200 runs sit in its water. *(test)*
6. A species with no habitat list behaves exactly as today (all types weight 1). *(test)*
7. REQ-0007's "biggest fish on a better lie than the median" still holds in 80% of runs. *(existing test)*
8. `content/fish.csv` round-trips the `habitat` column, and the importer rejects an unknown water type. *(test)*
9. The F1 view tints each type and shows a legend; text is at least 8 px. *(playtest)*

## Playtest checks

* F1 / Create to the read-the-water view: do the tints match how you'd read the water by eye? Note any spot that looks wrong.
* Reload a few times: redbands mostly on seams and riffles, brookies in pockets and the pool.
* Usual pass on keyboard and DualSense: cast Short, Middle, Long; land a fish; strike at nothing; reel in; switch practice mode and rule sets; cycle debug views.

## Open questions

1. **The seven types.** Riffle, Run, Pool, Tail-out, Pocket, Seam, Eddy now, and Undercut with cover features later. (Recommended.)
2. **Fish off their water.** Unlisted types get 0.2, so strays happen. Or 0, so a species never leaves its listed water. (Recommended: 0.2.)
3. **One type per cell.** A seam through a pool counts as Seam, not both. (Recommended: one type, simplest to read and to tune.)

## Architecture

*Review against ARCHITECTURE.md R1 to R12, on `main` at eaaa121.*

**1. New scripts and layers (R1, R10).** All use only lower layers. Each goes in the class index.

| Script | Class | Layer | System |
|---|---|---|---|
| `scripts/river/water_type_rules.gd` | `WaterTypeRules` | Data | River. Holds the `WaterType` enum and the thresholds; `data/water_types.tres` is its only file. The enum sits in data so `FishSpecies` never depends on a model, as `Calendar` does for seasons. |
| `scripts/river/water_types.gd` | `WaterTypes` | Model (value) | River. `classify(field, rules)` returns one; `type_at(p)` samples it. |
| `scripts/fishing/habitat_entry.gd` | `HabitatEntry` | Data (kind) | Fishing. `type: WaterTypeRules.WaterType`, `weight`. |

**2. Owners (R2, R3).** `FishGenerator` builds the `WaterTypes` once in `_init`, beside its lie cache, and owns it. `FishPlan` gains `water_type`, written once by the generator. The debug overlay reads the generator's `WaterTypes` through the fishing node it already finds, so no new reach.

**3. Rule checks.**

* **R9:** the classifier is its own script, so `river_field.gd` (617 of 623) isn't touched. `fishing_controller.gd` (613 of 614) gets no new lines; if the overlay needs one getter, a line moves out to make room. No cap is raised.
* **R12:** habitat is a trait of the kind (what water a brook trout likes), so it belongs on `FishSpecies`. Which water a stretch has stays the place's business, from its shape and features.
* **R6:** water types are an enum, never strings; the sheet turns names into the enum at the importer edge, as with insects.
* **R5:** `HabitatEntry` is typed, so `DEBT_LOOSE` stays empty.
* **R4, R8:** nothing writes to data at runtime; the classifier uses no randomness, and species picks keep the generator's existing seeded stream.
* **R11:** thresholds are in metres and fractions of `WATER_SPEED`.

**4. Data and content.** `data/water_types.tres` is a single file like `calendar.tres`, loaded in `data_test` (thresholds in range, types in order) and not in the catalog. The three species files and `content/fish.csv` gain habitats. ARCHITECTURE section 2, the class index and the system map row "River → Fishing" are updated in the same PR.

**5. Risks.**

* **Order.** REQ-0011 (resting lies) lands first. This REQ reads its lie layers and never writes them.
* **Wrong-looking types.** Thresholds tuned on one stretch may misread others. That's why they're data and the F1 view shows them.
* **Tail-out may not show** on the demo stretch if the pool shallows too gently; criterion 1 allows that rather than forcing the river to change.
* **Hot files.** No edit to `main.tscn`, `project.godot` or `fishing_controller.gd` is planned. `smoke_test` and `playthrough_test` get new functions only.
