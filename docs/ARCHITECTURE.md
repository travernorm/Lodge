# Lodge architecture

**Status: draft for Traver's review.** Nothing in here has been built yet unless the "Today" column says so. Changes to game code still go through [DEVELOPMENT_PROCESS.md](DEVELOPMENT_PROCESS.md): each migration step below becomes its own REQ and PR.

This is the map every change should be checked against, whoever writes it. If you're new to Godot's vocabulary (nodes, scenes, signals, autoloads, resources), read [GODOT_PRIMER.md](GODOT_PRIMER.md) first.

It covers fishing first (fish behaviour in detail is in [FISH_LOGIC.md](FISH_LOGIC.md)): casting, the line and fly on the water, the river, flies, fish and rises, the hook set, the fight and the catch journal, then how nymphing, streamers, fly tying and seasons plug in later. Walking the land, perception checks, the lodge sim and expansions will get their own sections when they're designed.

---

## 1. Four layers, one direction

Every script in Lodge belongs to exactly one layer. A layer may use the layers **below** it, never above.

```
  ┌──────────────────────────────────────────────────────────────┐
  │ 4. VIEWS        draw and play sounds; read state, change none│  Node2D / Control
  │    CastView, LineView, FishView, Hud, CatchCard, FlyBoxScreen│
  ├──────────────────────────────────────────────────────────────┤
  │ 3. SESSION      owns the phase, reads input, wires models    │  Node
  │    FishingSession (one per stretch), PracticeMode            │
  ├──────────────────────────────────────────────────────────────┤
  │ 2. MODELS       the rules; no nodes, no Input, no drawing    │  RefCounted
  │    CastModel, DriftModel, FishBrain, FightModel, RiverField, │
  │    CatchJournal, FlyBox ...                                  │
  ├──────────────────────────────────────────────────────────────┤
  │ 1. DATA         content and tuning, edited in the inspector  │  Resource (.tres)
  │    FlyPattern, FishSpecies, CastRules, TakeRules, Season ... │
  └──────────────────────────────────────────────────────────────┘
     SERVICES (autoloads, usable from layers 3 and 4 only):
     Controls (today), Clock, SaveGame (later)
```

The rules that make this work:

1. **Models never touch the tree.** No `get_node`, `get_tree`, `get_parent`, `Input`, `Controls`, autoloads or drawing in layer 2. They get everything they need as arguments (the stick vector, the flow as a `Callable`, a seeded `RandomNumberGenerator`) and report back by return value or signal. This is what makes them testable without playing. *Today: true for every model. Section 9 proposes a test that keeps it true.*
2. **One owner per value.** Each piece of state (the phase, the fly's position, the hooked fish, the fly box) is written by exactly one object. Everyone else reads it or asks the owner to change it.
3. **Call down, signal up.** The session calls methods on its models and views. Models and views tell the session things with signals. Siblings never call each other; the session connects them.
4. **Data is read-only at runtime.** A `FishSpecies` describes every redband. A runtime `Fish` holds what's true of *this* redband (its length, its lie, its mood).
5. **Ids, not objects, cross into saves.** Anything stored (journal, fly box, progress) stores `StringName` ids and looks the resource up through a registry.
6. **No strings as types.** Phases, presentations and fish events are enums or small typed classes, not `"Delicate"` or `&"take"`.

---

## 2. The fishing loop as a pipeline

Every fishing style (dry, nymph, streamer) runs the same six stages. What changes between styles is which model handles stage 2 and which rules decide stage 3.

```
 Cast ──landed──▶ Line on the water ──FlyState every frame──▶ Fish decide ──take──▶ Hook set ──hooked──▶ Fight ──landed──▶ Journal
 CastModel        DriftModel (dry)                          Fish (mood, lies)      HookSetModel         FightModel          CatchJournal
 + CastRules      DepthDriftModel (nymph, later)            + TakeRules            (timing window)      + species data      CatchRecord
                  RetrieveModel (streamer, later)           (one roll per drift
                                                             past each fish)
```

The **FishingSession** owns which stage is active:

```
IDLE ──bumpers──▶ CASTING ──landed in water──▶ ON_WATER ──take──▶ TAKE ──set in window──▶ FIGHT ──landed──▶ LANDED ──card closed──▶ IDLE
                     │ collapsed / snagged         │ reel in, drift ends     │ too early / late        │ snapped / threw hook
                     └────────────▶ IDLE ◀─────────┴─────────────────────────┴────────────────────────┘
```

One enum, one owner. Today this state is split across `CastModel.State`, `FishingController.Phase`, `Fish.State` and `Practice.active`, and the scripts check each other's flags to work out where they are.

### The one shared contract: `FlyState`

The single most important seam is between "where is the fly and how is it moving" and "does a fish want it". Make it a small typed value that every line model produces and every fish reads:

```gdscript
class_name FlyState extends RefCounted
var pattern: FlyPattern      # what's tied on
var pos: Vector2             # world position
var depth: float             # 0 = in the surface film (dry). Nymphs sink, streamers swim
var velocity: Vector2        # actual movement of the fly
var drag: float              # 0..1: how unnaturally it's moving against the current
var landing: Presentation    # how it arrived: DELICATE, FAIR, SPLASHY (an enum)
var since_landing: float
var on_water: bool
```

Fish never look at the cast, the line, or the controller. They only see a `FlyState`, the river, and the conditions. That's what lets nymph and streamer fishing arrive later as a new line model plus new take rules, without rewriting fish.

---

## 3. Systems

Each system lists what it **owns** (writes), **reads**, **emits**, its **data**, and how today's code compares.

### 3.1 Casting

*Owned by the casting thread. This document describes boundaries only, not the rhythm.*

* **Owns:** the R/L stroke state machine, line out, false-cast count, aim, the delivery offset and landing quality.
* **Reads:** bumper states and the aim stick (passed in by the session), `CastTuning`, the active `CastRules`.
* **Emits:** `delivered(offset, quality)`, `landed(presentation, quality)`, `collapsed(reason)`, `feedback(text, quality)`.
* **Data:** `data/cast_tuning.tres`, `data/cast_rules/*.tres` (a swappable strategy resource, one per rule set).
* **Today:** `CastModel` and `CastRules` fit this exactly; the chassis pattern is the template for other swappable rules below. Drift is in `cast_controller.gd`: it asks `Fishing.can_pick_up()` and `Fishing.line_target()`, runs its own fallback drift when Fishing is missing, owns the coaching text everyone else writes to, and writes `fly_pos` that Fishing also writes. **Target:** `CastController` becomes `CastView` (drawing the line in the air, meter, rings) and the session feeds the model input and decides when casting is allowed.

### 3.2 Line and fly on the water

* **Owns:** the `FlyState` and the line's shape (tip, belly, slack) while the fly is on the water.
* **Reads:** the rod tip, the right stick's gestures (mend, strip, twitch), the river's flow (and depth, for nymphs).
* **Emits:** `mended(ok)`, `drift_ended`.
* **Models by style:**
  * Dry fly: `DriftModel` (today). Belly bows, drag builds, a mend flips it.
  * Nymph, later: `DepthDriftModel`. Same belly and mend, plus sink rate from the fly's weight and depth from `RiverField.depth_at()`. Strike indicator replaces the visible fly.
  * Streamer, later: `RetrieveModel`. The fly swings on a tight line and moves when you strip or jerk the right stick.
* **Today:** `DriftModel` fits. It's driven from `fishing_controller.gd`, which copies its fly position into `Cast.fly_pos` each frame. `StickGestures` is a good small model; keep it and give it strip and twitch later.

### 3.3 River

*Owned by the river hydraulics thread.*

* **Owns:** one baked `RiverField` per stretch and water level: velocity, depth, seams, lie scores, water and rock masks.
* **Reads:** nothing at runtime (baked offline, per the approved plan). The session picks which field from the stretch and the season's water level.
* **Offers:** `flow_at`, `depth_at`, `seam_at`, `lie_at`, `is_water`, `pick_lie`. Read-only.
* **Today:** `RiverField` fits. Drift is that `stream_scene.gd` builds it at load, wraps its methods, and exposes screen constants (`VIEW`, `BANK_TOP`, `BANK_BOTTOM`) that fishing code reads directly. **Target:** a `Stretch` resource bundles the baked field(s), bounds, art and spawn table, and nothing outside the river and its view reads screen constants.

### 3.4 Flies and the fly box

* **Owns:** `FlyBox` model: which patterns you have, how many of each, which is tied on.
* **Data:** `FlyPattern` (today: id, name, description, colours). Later fields, each needing a REQ because it changes a data class: `style` (dry, emerger, nymph, streamer), `size`, `imitates` (an insect id), `sink_rate`, `profile`.
* **Emits:** `fly_changed(pattern)`.
* **Today:** the fly box is an exported array plus an index inside `fishing_controller.gd`, and the HUD for it is drawn there too. `FlyPattern.draw_at()` mixes drawing into data; acceptable while flies are three rectangles, but it should become a sprite or a `FlyView` once there's real art.

### 3.5 Fish

The full design is in [FISH_LOGIC.md](FISH_LOGIC.md). In short, fish logic runs in three steps, slowest to fastest:

1. **Generation** (per season or visit): which species, how many and how big, from the stretch's lies and water types, the season, the water temperature and the species table. The biggest fish take the best lies. The population is **kept** between visits, so spooked, released and kept fish all leave a mark.
2. **Mood** (per game hour): how keen each fish is (0 to 1), and whether it's looking up or down. The **hatch** is the main driver. Then the species' response to temperature, light and season, then its own hunger and wariness.
3. **Take** (one roll per drift past the fish): `mood × lane × landing × drift × fly match`, with a floor and a ceiling. The result is a take, a refusal, an ignore or a spook, and each one shows the player something.

Time of day, season and weather are not stored on each fish. They build one shared `Conditions` snapshot (section 3.9), which gives the hatch and the water temperature. Mood reads those, and the take's fly match reads the hatch again.

How that splits into code:

| Part | Kind | Holds |
|---|---|---|
| `FishSpecies` | Data | Everything true of every fish of this kind: habitat preference per water type, temperature range, light preference, diet, selectivity, seasonal presence and activity, hook-set window, fight stats, size range. |
| `Fish` | Model | This one fish: length, resting lie, feeding lie, mood, hunger, wariness, refusals, presentations since its last take, and its state (holding, interested, rising, taken, hooked, spooked, gone). |
| `Population` | Model | The fish in one stretch: generates them from the `Stretch` data and the river field, keeps them between visits, refills slowly. |
| `MoodRules` | Data with logic | Turns `Conditions` plus a fish's own state into its mood and feeding depth. |
| `TakeRules` | Data with logic (like `CastRules`) | The roll: given the `Fish`, a `FlyState` and the `Conditions`, returns the chance, each factor (so they can be shown on screen) and the outcome. Holds the floor, the ceiling and the streak protection. |

`TakeRules` is a swappable chassis, the same pattern as the casting rule sets, so each layer can be played before the next goes on. The order is in FISH_LOGIC.md ("Building it up"): today's odds, then drift, then refusals and streak protection, then one hatch with fly match, then mood by time of day, then generation from lies, then seasons and weather.

* **Lies** come from the river: `RiverField.pick_lie()` (open PR #7 starts this), later with separate resting and feeding scores, which need the river thread's agreement. Not from a screen rectangle.
* **Randomness** in fish logic lives in three places only: generation, mood's small drift, and the take roll with its spook check. All of them use a seeded `RandomNumberGenerator`.
* **Emits** (as an enum, not strings): `NATURAL_RISE`, `RISING`, `TOOK`, `REFUSED`, `SPOOKED`, `SPAT`.
* **Today:** `fish.gd` holds the runtime fish well, but the bite formula is constants inside it (`PRESENTATION_FACTOR`, `CLOSE_RANGE`). It rolls once per cast, not once per presentation. Presentation arrives as a string, events are `StringName`s, and the hook-set window check lives here too. `lie_area` is a screen `Rect2`, and each fish is rerolled when it comes back.

### 3.6 Hook set

* **Model:** `HookSetModel`, tiny and pure: opens a window on `TOOK`, takes a set input with its timestamp, returns `HOOKED`, `TOO_EARLY`, `TOO_LATE`. The window comes from the species and, later, the style (nymph takes are subtler; streamer takes are a jolt you strip-set).
* **Today:** `Fish.try_set()` does this. Moving it out is small and lets styles change the set without touching fish.

### 3.7 Fight

* **Model:** `FightModel` (today). Pressure from the stick, tension, stamina, runs and rests, side pressure.
* **Reads:** the species' fight stats, later the rod and tippet strength (gear as data).
* **Emits:** `run_started`, result `LANDED`, `SNAPPED`, `THREW_HOOK`.
* **Today:** the model fits well. Its glue (fish position on screen, rumble, splash bursts, the meter) is in `fishing_controller.gd`; the target moves the glue to the session and the drawing to `FishView` and `Hud`.

### 3.8 Catch journal

* **Owns:** `CatchJournal` model, a list of `CatchRecord`s plus derived facts (species seen, personal bests, first catch on each fly).
* **CatchRecord:** `species_id`, `fly_id`, `length_in`, `stretch_id`, `game_day`, `time_of_day`, `season`, `water_level`, `style`. Ids only, so it can be saved and survives data changes.
* **Feeds:** the catch card, the journal screen, the "catch them all" collection, the market (selling fish), and later lodge reputation.
* **Today:** `catches: Array[Dictionary]` holding resource references, inside `fishing_controller.gd`. Nothing saves yet, so this is the cheapest moment to fix it, before the save format exists.

### 3.9 Conditions: time, seasons, weather, hatches (later)

The design target (four 30-day seasons, six time slots, 10°F temperature bands, five weathers, the hatch calendar and the species palette) is in [SPECIES_AND_CONDITIONS.md](SPECIES_AND_CONDITIONS.md).

* **Service:** `Clock` autoload: game day, time of day, season. The only global clock; models get the time passed in.
* **Value:** `Conditions` (season, time of day, weather, water temperature, water level, the active hatch and its stage), rebuilt by the session about once per game hour. It's the one place time, season and weather turn into things fish respond to: the hatch and the water. `MoodRules`, `TakeRules`, `Population` and the river all read it; none of them read the clock directly.
* **Data:** `Season` resources with hatch tables and water ranges (`Hatch`: insect id, stages, time window, intensity by weather), and seasonal activity on `FishSpecies`.
* **Visible in the world:** views read `Conditions` to show the season (Stardew-style), and the hatch is drawn as bugs on the water, so the information fish use is information the player can see.

### 3.10 Fly tying (later)

* **Data:** `Material` (id, name, where found), `Recipe` (fly id, materials and counts, how it's unlocked).
* **Model:** `TyingBench`: given the inventory and a recipe, can you tie it, and what changes. Adds to `FlyBox`.
* **Links:** perception checks and exploration unlock recipes and give materials; the journal and observed hatches suggest which flies to tie. Keep tying and exploration talking through ids and signals (`recipe_unlocked(id)`), never direct calls.

### 3.11 Modes: practice, tutorial, guiding

* Practice mode is a different **session configuration**, not a sibling that flips flags on other nodes: the session runs with fish disabled and a target scorer added.
* **Today:** `cast_practice.gd` sets `Fishing.enabled`, writes `Cast.rules` and `Cast.model.rules`, and calls `Cast.reel_in_line()`. It works, but it's a third node reaching into two others. Guiding clients later will be another mode, so the pattern is worth fixing once.

---

## 4. Target scene tree

```
Game (Node)                         top-level: loads stretches, owns the pause and menus
├─ Stretch: CabinCreek (scene)      one per river location; swapped when you walk off-screen
│  ├─ RiverView (Node2D)            water, banks, rocks, streaks; reads the RiverField
│  ├─ FishingSession (Node)         phase, input, models; no drawing
│  ├─ FishLayer (Node2D)            one FishView per Fish
│  ├─ LineView (Node2D)             line on the water, the fly, rings
│  ├─ CastView (Node2D)             line in the air, timing meter
│  └─ Angler (Node2D)               walking, rod pose
├─ Hud (CanvasLayer)                fly box, catch count, coaching text, fight meter, catch card
├─ Screens (CanvasLayer)            journal, fly box, tying bench, game menu (backlog item 1)
└─ DebugLayer (CanvasLayer)         unchanged: finds things through groups
Autoloads: Controls, Clock, SaveGame
```

`Hud` listens to session signals; it never asks the cast or fishing nodes for state. Coaching text gets one owner (`Hud.say(text, quality)`) instead of everyone calling `Cast.show_message()`.

---

## 5. Units and space

**Decided (Traver, 2026-11-02): models and data work in metres.** Cast reach, line out, drift, fight distance, bite range, river cells and current speeds are all in metres and metres per second. Only views convert to pixels, through one constant in a small static class, `WorldScale.PX_PER_M`. That makes multi-screen stretches, scrolling, zoom and the Switch possible without retuning every number, and lets the river bake use real cell sizes.

The approved scale is **8 px per metre**: one screen is 40 m by 25 m and the test creek is about 11 m wide. At that scale today's casting distances already match a real small stream (Short up to 6 m, Middle up to 10 m, line max about 15 m). Water speeds don't: they're tuned for the screen and come out several times faster than a real riffle. The switch converts every number exactly, so the game plays the same, and slowing the water toward real speeds is a separate feel experiment afterwards.

The plan, the scale and the per-system steps are in [REQ-0001](requirements/REQ-0001-world-units-in-metres.md). It needs the casting and river threads to agree, and Traver's approval, before game code changes.

---

## 6. Where the current code fits and drifts

| # | Area | Fits or drifts | Notes |
|---|---|---|---|
| 1 | Models (`CastModel`, `DriftModel`, `FightModel`, `Fish`, `RiverField`, `StickGestures`) | **Fits** | Pure `RefCounted`, no tree access, unit tested. Keep this. |
| 2 | Data as `.tres`, `data_test.gd` contracts | **Fits** | Ids match file names, folders auto-covered. |
| 3 | `CastRules` chassis | **Fits** | The template for `TakeRules` and style strategies. |
| 4 | `Controls` autoload, input parity tests | **Fits** | Only autoload; stays that way until `Clock` and `SaveGame`. |
| 5 | Seeded RNG passed into models | **Mostly fits** | Controllers call `randomize()` and tests poke `_rng` (backlog item). |
| 6 | `fishing_controller.gd` does drift glue, fish events, hook set glue, the fight, the fly box, the catch log, HUD and card drawing | **Drifts** | God script, and a hot file in every open PR. Split first. |
| 7 | `Cast` ⇄ `Fishing` ⇄ `Practice` call each other via `get_node` | **Drifts** | Two-way dependency between siblings; no single phase owner. |
| 8 | Fly position written by both `Cast` and `Fishing` | **Drifts** | Should be one `FlyState` owned by the line model. |
| 9 | Presentation as `String`, fish events as `StringName` | **Drifts** | Make enums. |
| 10 | Bite rule constants inside `Fish`, rolled once per cast | **Partly fixed** | A first `TakeRules` chassis landed early (2026-11-02, Traver's call): "Landing roll" (the old roll) and "Drift past" (one roll per pass, data in `data/take_rules/`). It reads `DriftModel` and the presentation string directly until `FlyState` (step B) exists. See FISH_LOGIC.md. |
| 11 | `FishSpecies.lie_area` is a screen rectangle | **Drifts** | PR #7 moves lies to the river field. |
| 12 | Fishing code reads `stream.VIEW`, `BANK_TOP`, `BANK_BOTTOM`, and every rule measures in pixels | **Drifts** | Screen constants and units leaking into rules. REQ-0001 moves rules to metres. |
| 13 | `catches` holds resources in dictionaries | **Drifts** | Needs `CatchRecord` with ids before saves. |
| 14 | Coaching text owned by `cast_controller.gd` | **Drifts** | Move to `Hud`. |
| 15 | Each controller keeps its own `_time` | **Minor** | Fine until pause and time of day; then `Clock`. |
| 16 | `FlyPattern.draw_at()` | **Minor** | Drawing inside data; fine until real fly art. |
| 17 | Debug overlay finds nodes by group | **Fits** | Right tool for optional, read-only lookups. |

---

## 7. Migration plan

Small steps, each its own REQ and PR, each leaving the game playing the same unless the REQ says otherwise. The tests (`tools/run_tests.sh`, especially `playthrough_test.gd`) are the safety net: steps A to D should pass them unchanged.

| Step | What | Behaviour change | Depends on |
|---|---|---|---|
| **0** | This document and the primer. Add the layer check (section 9) as a test. | None | — |
| **A** | Split views out of `fishing_controller.gd`: `Hud` (fly box, catch count, coaching text, fight meter), `CatchCard`, `LineView`, `FishView`. Absorbs the backlog item. | None | PR #5 merged (it edits the same file) |
| **B** | Add `FishingSession` as the single phase owner. `Cast` stops calling `Fishing`; `Practice` becomes a session mode. Introduce `FlyState` and make the line model its only writer. | None | A |
| **C** | Enums for presentation and fish events; move `try_set` into `HookSetModel`. | None | B, coordinated with the casting thread (it changes the `landed` signal's argument type) |
| **D** | `CatchRecord` and `CatchJournal` with ids; a `FlyBox` model. | None visible | A |
| **E** | `TakeRules` chassis with today's odds as the default (numbers moved into data), then the first layers from FISH_LOGIC.md as feel experiments: drift, then refusals and streak protection. The chassis and the drift layer were built ahead of B and C (2026-11-02); they move onto `FlyState` when B lands. | Only in the experiments | B, C, PR #7 merged |
| **F** | Metres in models and data ([REQ-0001](requirements/REQ-0001-world-units-in-metres.md): `WorldScale`, then river, casting, fishing), then a `Stretch` resource. | None (exact conversion) | Casting and river threads' agreement. Can start before A; its fishing step pairs well with A |
| **G** | `Clock` autoload and `Conditions` with one fixed hatch, then `MoodRules` by time of day, then `Population` from lies. | Yes, layer by layer | E, F |
| **Later** | Nymph (`DepthDriftModel`), streamer (`RetrieveModel`), hatches, fly tying, saves. Each is a REQ that adds a model and data, not edits to existing models. | Yes | The above |

Steps A, B and D are refactors of game code, so they need Traver's go-ahead like any feature. Step E is the first one a player would notice.

### Coordination

* **Casting thread:** owns `scripts/casting/` and the rule sets. Step B changes how `cast_controller.gd` is wired (input passed in, no calls into Fishing) and step C changes the `landed` signal's argument type. Both need to land between casting PRs, agreed with that thread first.
* **River thread:** owns `scripts/river/` and `stream_scene.gd`'s field. Step F (units, `Stretch`) is theirs to agree to. `pick_lie` from PR #7 is exactly the hook fish lies need.
* **Open PRs today:** #5 (hook-set animation) and #7 (fish pick lies) both edit `fishing_controller.gd` and `fish.gd`. No refactor of those files should start until both merge.

---

## 8. Where does new code go?

| I want to add... | It goes in | Not in |
|---|---|---|
| A new fly, fish, rule set or tuning number | A `.tres` in `data/` (covered by `data_test.gd` automatically) | Code constants |
| A rule (odds, timing, physics, scoring) | A model in layer 2, with a unit test | A node script |
| A choice between rule variants | A strategy resource like `CastRules` / `TakeRules` | `if` branches on a mode flag |
| Something on screen | A view node that reads state and listens to signals | The session or a model |
| A reaction to something happening | Connect to the owning model's signal in the session | Polling another node's variables |
| A new phase in the fishing loop | The session's phase enum and a new model | A boolean flag on an existing node |
| Something saved | A record with ids in a model, saved through `SaveGame` with a version | Resources or nodes in the save |
| Something global (clock, save, audio) | An autoload, only after discussing it | Any gameplay rule |
| A new input | `tools/setup_input_map.gd`, a constant in `Controls`, the README table | Raw action strings |

**File size:** split any script heading past ~300 lines along the layer lines above. **New class:** add it to this document's section 3 in the same PR.

---

## 9. Keeping it true: tests that enforce the layers

Rules that only live in a document erode, especially when each change is written by a fresh AI session. Proposed `tests/architecture_test.gd` (tests can be added without a REQ), which reads the source files and fails if:

1. Any model script (`*_model.gd`, `fish.gd`, `river_field.gd`, `stick_gestures.gd`, rule scripts, future `scripts/**/models/`) mentions `get_node`, `get_tree`, `get_parent`, `Input.`, `Controls.`, `_draw` or `draw_`. *All of them pass today.*
2. Any script assigns to a field of a loaded `FishSpecies`, `FlyPattern` or `CastTuning` (a text check for `species.<field> =` and the like), since shared data must stay read-only.
3. A script in `scripts/` other than the session calls `get_node` on a sibling system. *Fails today on purpose for `Cast`, `Fishing` and `Practice`; starts as an allow-list that step B empties.*
4. The project has an autoload not listed in this document.
5. A script passes ~400 lines (a warning list, with `fishing_controller.gd` allowed until step A).

---

## 10. Decision log

Short entries, newest last. A later session reads these before changing something that looks odd.

| Date | Decision | Why |
|---|---|---|
| 2026-11-01 | Godot 4.3, GL Compatibility, 320×200 ×4 | Steam Deck first, Switch later, crisp pixels. |
| 2026-11-02 | Rules in `RefCounted` models, content in `.tres` | Testable headless; 100 fish and hundreds of flies as data. |
| 2026-11-02 | Casting rules as swappable resources (chassis) | Compare feel side by side; Traver picked Count the false casts. |
| 2026-11-02 | River flow baked offline, sampled at runtime | No compute shaders on GL Compatibility; cheap on Deck and Switch. |
| 2026-11-02 | Start simple: one fish, one fly, visible odds | Hidden multi-condition bite rules felt broken in playtest. |
| draft | Four layers, one phase owner, `FlyState` contract, `TakeRules` chassis, ids in saves | This document. Traver said it "seems okay" (2026-11-02). |
| 2026-11-02 | Models and data use metres; views convert with `WorldScale.PX_PER_M` = 8 px/m (approved) | Traver's call. Multi-screen stretches, real-world data and the river bake all need real units. See REQ-0001. |
| draft | Fish logic in three steps: generation, mood, take. Conditions feed the hatch and water, which feed mood; one take roll per presentation with a floor, a ceiling, refusals and streak protection | Brainstorm with Traver, 2026-11-02. See FISH_LOGIC.md. |

## 11. Open questions for Traver

1. Does the migration order make sense, and should step A (splitting `fishing_controller.gd`) start as soon as PRs #5 and #7 merge?
2. ~~Metres in models?~~ Decided: metres (2026-11-02). Scale approved at 8 px per metre (REQ-0001).
3. The fish logic questions at the end of [FISH_LOGIC.md](FISH_LOGIC.md).
