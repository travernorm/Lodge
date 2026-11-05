# Lodge architecture

**Status: adopted (2026-11-03).** This is the map every change is checked against, whoever writes it. The rules in section 1 are numbered (R1 to R12) so tests, reviews and PRs can cite them. Most are enforced by `tests/architecture_test.gd`, which runs in CI on every PR. Where today's code still breaks a rule, the debt is written down in section 9 with a cap that can only go down.

The audit behind this version, with evidence and a comparison to how larger games are built, is in [ARCHITECTURE_AUDIT.md](ARCHITECTURE_AUDIT.md). New to Godot's vocabulary (nodes, scenes, signals, autoloads, resources)? Read [GODOT_PRIMER.md](GODOT_PRIMER.md) first. Fish behaviour in detail is in [FISH_LOGIC.md](FISH_LOGIC.md).

## How to use this document

**Before writing code** (any agent or person):

1. Find where the change goes in section 5, and which system owns it in section 3.
2. Check it against the rules in section 1. If it needs to break one, stop and say so in the REQ or PR; don't work around it.
3. If it touches a file in the debt ledger (section 9), don't add to that debt. Paying some back in passing is welcome, if it's in scope.

**In the same PR:**

* A new script goes in the class index (section 11). A new data folder goes in section 2 and in `tests/data_test.gd`. The test fails otherwise.
* A new link between systems goes in section 3 and in the system map in [DEVELOPMENT_PROCESS.md](DEVELOPMENT_PROCESS.md).
* If debt went down, lower its cap in `tests/architecture_test.gd` and section 9. Raising a cap needs Traver's OK, stated in the PR.
* Fill in the PR template's Architecture section.

Changes to game code still go through [DEVELOPMENT_PROCESS.md](DEVELOPMENT_PROCESS.md): each migration step in section 10 is its own REQ and PR.

---

## 1. Layers and rules

Every script belongs to exactly one layer. A layer may use the layers **below** it, never above.

```
  ┌──────────────────────────────────────────────────────────────┐
  │ 4. VIEWS        draw and play sounds; read state, change none│  Node2D / Control
  │    CastView, LineView, FishView, Hud, CatchCard ...          │
  ├──────────────────────────────────────────────────────────────┤
  │ 3. SESSION      owns the phase, reads input, wires models    │  Node
  │    FishingSession (one per stretch), its modes (practice)    │
  ├──────────────────────────────────────────────────────────────┤
  │ 2. MODELS       the rules; no nodes, no Input, no drawing    │  RefCounted
  │    CastModel, DriftModel, Fish, FightModel, RiverField ...   │
  ├──────────────────────────────────────────────────────────────┤
  │ 1. DATA         content and tuning, edited in the inspector  │  Resource (.tres)
  │    FlyPattern, Insect, FishSpecies, Stretch, CastRules ...   │
  └──────────────────────────────────────────────────────────────┘
     SERVICES (autoloads, usable from layers 3 and 4 only):
     Controls (today), Clock and SaveGame (planned)
     GAME STATE (planned): one GameState model, owned by the game root, saved by SaveGame
```

A script whose base class is `RefCounted` or `Resource` is layer 1 or 2. A script whose base class is a `Node` is layer 3 or 4. The test tells them apart that way.

| # | Rule | Enforced by |
|---|---|---|
| **R1** | **Models and data are pure.** Layers 1 and 2 never use the tree (`get_node`, `get_tree`, `get_parent`), `Input`, `Controls`, drawing, node callbacks (`_ready`, `_process`, `_draw`), pixels (`to_px`) or the wall clock (`Time`, `OS`). They get what they need as arguments (the stick vector, the flow as a `Callable`, a seeded RNG) and answer with return values or signals. | Test |
| **R2** | **One owner per value.** Each piece of state (the phase, the fly's position, the hooked fish, the fly box) is written by exactly one object. Everyone else reads it or asks the owner. | Review |
| **R3** | **Call down, signal up.** The owner calls methods on its children; children tell the owner things with signals. A node never climbs to its parent, never fetches a sibling with `get_node`, and never reads properties by name (`.get(&"river")`). Groups are fine for optional, read-only lookups (the debug overlay). | Test (ledger) |
| **R4** | **Data is read-only at runtime.** A `FishSpecies` describes every redband; a runtime `Fish` holds what's true of *this* one. Nothing writes to a loaded resource's fields. Tests that need different numbers duplicate the resource first. | Test |
| **R5** | **Data links are typed references; ids only at the save boundary.** One data file points at another with a typed export (`Array[Insect]`), never a dictionary or array of id strings. Ids (`StringName`) are for what's saved and for looking things up in the catalog. | Test (ledger) |
| **R6** | **No strings as types.** Phases, presentations, fish events and outcomes are enums or small typed classes, not `"Delicate"` or `&"take"`. | Review |
| **R7** | **Autoloads are few and agreed.** Only `Controls` today. `Clock` and `SaveGame` are planned. Anything else is Traver's call. No gameplay rule lives in an autoload. | Test |
| **R8** | **One clock, seeded dice.** Randomness comes from a `RandomNumberGenerator` that someone seeds and passes in, never `randf()` or `randomize()`. Game time comes from one owner (the session today, `Clock` later), passed into models. | Test (ledger) |
| **R9** | **Small files, split along layers.** A script past 400 lines is split: drawing into views, rules into models. | Test (ledger) |
| **R10** | **Everything is on the map.** Every script is in the class index (section 11). Every data folder is described in section 2 and loaded by `tests/data_test.gd`. Every link between systems is in the system map. | Test |
| **R11** | **Metres in models and data.** Models and data use metres and metres per second. Only views and the stream scene's layout convert, through `WorldScale` (8 px per metre). | Test (as part of R1) |
| **R12** | **Kinds and places are separate.** Data that describes a *kind* of thing (a species, a fly) says nothing about *where* it is. Where things live, and how many, belongs to the *place* (a `Stretch`'s spawn table). | Review |

The rules marked "Review" can't be checked from the text reliably. The PR template asks about them.

---

## 2. Data architecture

### Kinds of data

| Kind | Example | Lives in | Changes at runtime? |
|---|---|---|---|
| **Archetype** (what a kind of thing is) | `FishSpecies`, `FlyPattern`, `FlyRod`, `Insect` | `data/<kind>/<id>.tres` | Never (R4) |
| **Rule set** (swappable logic and its numbers) | `CastRules` and subclasses, `DriftPastRules`, `CastTuning` | `data/cast_rules/`, `data/take_rules/`, `data/cast_tuning.tres` | Never |
| **Place** (a location and what's in it) | `Stretch`: shape, features, which species live there | `data/stretches/` | Never |
| **Runtime state** (this fish, this drift) | `Fish`, `DriftModel`, `FightModel` | Models, created by the session | Every frame |
| **Saved state** (what persists) | catch journal, fly box, stretch populations, day | `GameState` (planned) | Saved with a version |

The data folders today, each covered by `tests/data_test.gd`:

* `data/insects/`: `Insect`, the shared key between flies, diets and (later) hatches.
* `data/tackle/`: tackle, the things you fish with (REQ-0005).
  * `data/tackle/flies/`: `FlyPattern`, each pointing at the insects it imitates, with a fly type (dry, nymph, streamer) and its art (`assets/flies/<id>.png`, 8 views in a row).
  * `data/tackle/rods/`: `FlyRod`: which fly types it throws, its longest line, timing forgiveness and the fish length it's rated for.
* `data/fish/`: `FishSpecies`, with diet, selectivity, hook-set window, fight stats, sizes.
* `data/cast_rules/`: the casting rule sets (one `CastRules` per file).
* `data/take_rules/`: the bite rules (`DriftPastRules`).
* `data/stretches/`: `Stretch`, one per river location (today the demo freestone).
* `data/looks/`: `WaterLook`, how the water is painted: the deep, mid and white water textures (in `assets/water/`), tints, and where each one shows by depth and speed. `WaterView` paints it from the river field A look can also set a palette (water colour by depth, the textures then add only their light and dark pattern), the riverbed seen through the shallows (sand and stones) and foam lines along banks and rocks. `water_clear.tres` is the game's look, `water_clear_crisp.tres` the same with pixel dithering, and `water_spring.tres` the first textured look.
* `data/cast_tuning.tres`: casting numbers shared by every rule set.
* `data/cast_looks/`: `CastLook`, how the rod and the angler's arm move through a cast on screen (a feel experiment): which version starts (Off, A rod sweep, B cutout arm), the rod's stop angles, its bend, and B's fixed angles. `CastPose` does the sums; the cast node holds the version on trial and `AnglerView` draws it.
* `data/grass_looks/`: `GrassLook`, how the tall grass looks and moves (REQ-0012): clump sprites (a placeholder clump of blades until Traver's art), size and density, how it reacts to the angler (the variant on trial, push radius, lean, spring-back, trail, rustle) and the wind per weather. `GrassView` draws it in every `GrassPatch` of the stretch. `spring.tres` is the game's look.
* `data/weather_looks/`: `WeatherLook`, how the weather and the time of day look on screen (REQ-0009): a `WeatherStyle` per weather (grade, rain or snow, cloud shadows, rain dimples, lightning) and a tint and brightness per slot. `WeatherView` paints it from the day's `Conditions`.
* `data/calendar.tres`: `Calendar`, the year's rules (REQ-0007): how each slot lowers the air, how the water follows it, and how keen fish are in each slot and weather. Not in the catalog; the fishing node takes it as an export.
* `data/water_types.tres`: `WaterTypeRules`, how the river's water is sorted into riffle, run, pool, tail-out, pocket, seam and eddy (REQ-0010), plus the `WaterType` enum and the stray weight for water a species doesn't list. Not in the catalog; code reaches it through `WaterTypeRules.shared()`.
* `data/climates/`: `Climate`, one per region (REQ-0008; today `central_oregon.tres`): each season's highs, weather odds and persistence (how long spells last), how far the high wanders a day, how each weather lowers it, when storms hit, and how hard rain, snow and storms fall. A new region is a new file. Not in the catalog; the fishing node takes one as an export until regions exist.
* `data/catalog.tres`: the index of every fish, fly, insect and stretch (generated, see below).

The content sheets in `content/` (`insects.csv`, `flies.csv`, `rods.csv`, `fish.csv`) are the spreadsheet view of the archetype folders: one row per file, one column per exported field. `tools/import_content.gd` checks every cell and writes the `.tres` files; the game never reads the sheets (the folder has a `.gdignore`), and `tests/content_test.gd` keeps them in step with `data/`. See TOOLING.md, "Content sheets". The river sheets (`rivers.csv`, `river_markers.csv`, REQ-0014) write one `Stretch` per named section through `tools/import_river.gd`, with a preview plate per section in `docs/rivers/`; `tests/river_import_test.gd` keeps them in step. See TOOLING.md, "River sheets".

### References and ids

* **Between data files:** typed resource references (R5). `FlyPattern.imitates: Array[Insect]` is the model to copy. Godot keeps them valid when files move, and the inspector shows a picker instead of a text box. Godot 4.3 has no typed dictionaries, so a weighted link is a small entry resource (for example a `DietEntry` with `insect: Insect` and `weight: float`).
* **Ids:** every archetype has an `id` that matches its file name (`data_test` checks). Ids are never renamed or reused, because saves will store them.
* **At the save boundary:** saved state stores ids only, never resources or nodes. Loading looks the id up in the catalog.

### The catalog (REQ-0004)

`data/catalog.tres` (`Catalog`) lists every fish, fly, rod, insect and stretch by kind. Code that needs "all flies" or "the fly with this id" asks `Catalog.shared()`, and no script names a content file (`architecture_test`, R5). It's written by `tools/build_catalog.gd` from the `data/<kind>/` folders rather than scanned at runtime, because exported builds rename files to `.remap`. The tool keeps the current order and adds new files at the end, and the fly box and rod rack use catalog order. `data_test` fails if the catalog and the folders disagree, so a new file can't be forgotten: **add a file, run the tool, commit both.** Rule sets (`data/cast_rules/`, `data/take_rules/`) aren't in it; they're picked by hand.

### Game state and saves (planned, step D)

One `GameState` model holds everything that persists: the day, the `CatchJournal` (`CatchRecord`s of ids), the `FlyBox`, each stretch's population. The game root owns it; sessions read and change it through methods. `SaveGame` (autoload) writes it as a dictionary with a `version`, and every format change ships with a migration and a fixture test (DEVELOPMENT_PROCESS.md, standing rules).

### Units

Decided 2026-11-02 ([REQ-0001](requirements/REQ-0001-world-units-in-metres.md)): metres in models and data (R11), 8 px per metre, so one screen is 40 m by 25 m. Field names carry their unit (`size_m`, `stroke_time_per_m`). Controllers still hold some positions in pixels (`Cast.fly_pos`, the rod tip) and convert at their edges; step B moves world positions to metres.

---

## 3. Systems

Each system lists what it **owns** (writes), what it **reads**, what it **emits**, and how today's code compares.

### 3.1 The fishing loop

Every style (dry, nymph, streamer) runs the same stages. What changes between styles is the line model and the take rules.

```
 Cast ──landed──▶ Line on the water ──FlyState──▶ Fish decide ──take──▶ Hook set ──hooked──▶ Fight ──landed──▶ Journal
 CastModel        DriftModel (dry)                Fish + take rules     HookSetModel         FightModel         CatchJournal
 + CastRules      later: DepthDriftModel (nymph), (one roll per drift   (timing window)      + species data     CatchRecord
                  RetrieveModel (streamer)         past each fish)
```

One **FishingSession** owns which stage is active, as one enum:

```
IDLE ──bumpers──▶ CASTING ──landed in water──▶ ON_WATER ──take──▶ TAKE ──set in window──▶ FIGHT ──landed──▶ LANDED ──card closed──▶ IDLE
                     │ collapsed / snagged         │ reel in, drift ends     │ too early / late        │ snapped / threw hook
                     └────────────▶ IDLE ◀─────────┴─────────────────────────┴────────────────────────┘
```

*Today:* the phase is split across `CastModel.State`, `FishingController.Phase`, `Fish.State` and `Practice.active`, and the three nodes check each other's flags (debt R3, step B).

**The one shared contract: `FlyState`** (planned, step B). A small typed value every line model produces and every fish reads. Fish never look at the cast, the line or a controller, which is what lets nymphs and streamers arrive later as a new line model plus new take rules.

```gdscript
class_name FlyState extends RefCounted
var pattern: FlyPattern      # what's tied on
var pos: Vector2             # world position (m)
var depth: float             # 0 = in the film (dry)
var velocity: Vector2        # m/s
var drag: float              # 0..1
var landing: Presentation    # enum: DELICATE, FAIR, SPLASHY
var since_landing: float
var on_water: bool
```

### 3.2 Casting

*Owned by the casting thread. This covers boundaries, not the rhythm.*

* **Owns:** the bumper stroke state machine, line out, false-cast count, aim, delivery offset, landing quality.
* **Reads:** bumper states and aim (passed in), `CastTuning`, the active `CastRules`, and the rigged `FlyRod` (`CastModel.rod`, set by Fishing's `Tackle`): `max_line()` replaces the rule set's longest line and `forgiveness()` scales the timing windows and overlap band (REQ-0005).
* **Emits:** `landed(presentation, quality)`, `collapsed(reason)`, feedback text.
* **Today:** `CastModel` and the `CastRules` chassis fit (the chassis is the template for any swappable rules). `cast_controller.gd` asks Fishing `can_pick_up()`, `can_cast()` and `line_target()`, owns the coaching text everyone writes to, and writes `fly_pos`, which Fishing also writes (R2, R3). `CastModel` calls `randomize()` when no RNG is passed (R8). **Target:** a `CastView`; the session feeds the model and decides when casting is allowed.

### 3.3 Line and fly on the water

* **Owns:** the `FlyState` and the line's shape (tip, belly, slack).
* **Reads:** the rod tip, right-stick gestures (`StickGestures`), the river's flow.
* **Emits:** `mended(ok)`, `drift_ended`.
* **Today:** `DriftModel` fits, including mends that feed line. `fishing_controller.gd` drives it and copies its fly into `Cast.fly_pos` every frame.

### 3.4 River and stretches

*Owned by the river hydraulics thread.*

* **Owns:** one `RiverField` per stretch: velocity, depth, seams, lie scores, water and rock masks. Read-only to everyone else: `flow_at`, `depth_at`, `lie_at`, `is_water`, `pick_lie`. The field's `lie` is a feeding score (slow water with fast water close by). `RestingLies` (REQ-0011) scores resting water from the field's layers: deep, slow and covered, highest on the outside of a bend (the cut bank). It never writes to the field, and `score_at` is the better of the two.
* **Data:** `Stretch`: shape, a spawn table (`SpawnEntry`: species, abundance, season window), how rich it is (`fish_per_100m`), a hatch table (`HatchEntry`: insect, season window, slots, weathers, strength), `spring_fed`, and a list of features (`RiverFeature`, one script per kind in `scripts/river/features/`: `Boulder`, `FallenLog`, `Eddy`, `GravelBar`, `GrassPatch`, `GrassBank`). The field runs the features through hooks (`blocks`, `shape_flow`, `calm`, `swirl`, `prepare`) and names no kind, so a new kind is one new script and a new feature in a river is one entry (REQ-0004 C3). Views draw boulders and logs with their own art and outline any other kind from its `footprint()`. Tall grass (REQ-0012): `GrassField` grows clumps on land in each `GrassPatch` (an oval) and `GrassBank` (a band along the whole river, `width_m` back from the water, read from the field's `shore` and `bend` layers), the first entry winning where they overlap, and springs them away from the angler; `Wind` (from the day's `Conditions`) leans them; `GrassView` draws them, the stream scene putting it under the angler and telling it where he stands. Built at load today; baked offline later (backlog). `tests/fixtures/demo_field.txt` records the demo stretch's water so `river_test` catches any unintended change; re-record it with `tools/record_field_fixture.gd` only when a change to the water is intended.
* **Today:** `stream_scene.gd` (449 lines) builds the field, walks the angler, runs the camera, generates textures and draws the water (R9). `AnglerView` (`scripts/angler_view.gd`) draws the angler from Traver's sprite (`assets/angler/idle.png`, 8 views in a row in the fly sheets' order; `walk.png`, one row of walk frames per view, played while his feet move) and the rod, bent during a cast, with a cutout forearm on a Skeleton2D for cast look B; the stream scene owns it and tells it where the angler stands and faces. Fishing reads `river` and `stretch` from it by name (R3). **Target:** a `RiverView`, an `Angler` node and a camera owner, with the field and stretch handed to the session (step A2, agreed with the river thread).

### 3.5 Flies and the fly box

* **Data:** `FlyPattern` (id, name, colours, `imitates: Array[Insect]`, `fly_type`, `sprite_sheet`) and `FlyRod` (REQ-0005), both in `data/tackle/` and `scripts/tackle/`. Later fly fields (size, sink rate) each need a REQ.
* **Model:** `Tackle` (`scripts/tackle/tackle.gd`) is the one writer of which rod and fly are rigged. The fly box offers only flies the rod throws (`FlyRod.throws()`); changing rods keeps the fly if it fits.
* **Model (planned, step D):** `FlyBox`: which patterns you have, how many, which is tied on. Emits `fly_changed`.
* **Today:** `fishing_controller.gd` owns one `Tackle`, built from the catalog, and hands its rod to the cast and the fight. Owned gear (how many of each) comes with `FlyBox` in step D.
* **View:** `FlyView` (`scripts/tackle/fly_view.gd`) draws a fly from its art, `FlyPattern.sprite_sheet` (8 views in a row in `assets/flies/`, the hook eye as the head). On the water the fly faces the rod tip; the fly box shows it side on. A fly with no art draws as a few pixels in its colours. The cast node and the fishing node each own one. `FlyBoxView` (`scripts/tackle/fly_box_view.gd`) draws the fly box corner of the HUD (the fly's picture, its name, the rod) and owns its own `FlyView` for the picture.

### 3.6 Fish

The design is in [FISH_LOGIC.md](FISH_LOGIC.md): generation (per season or visit), mood (per game hour), take (one roll per drift past the fish). Time, season and weather build one shared `Conditions` snapshot; fish read the hatch and the water, not the clock.

| Part | Kind | Holds |
|---|---|---|
| `FishSpecies` | Data | What's true of every fish of the kind: diet, selectivity, hook-set window, fight stats, sizes, temperature range, habitat (`HabitatEntry`: water type and weight). Later light preference. Not where it lives (R12). |
| `Fish` | Model | This fish: length, lie, state; later mood, hunger, wariness, refusals. |
| `DriftPastRules` | Rule set | The bite roll: lane, landing and drift shares × fly match. The only bite rules since 2026-11-02. |
| `FishGenerator` | Model | Stocks a stretch for one day from its spawn and hatch tables, the `Conditions` and the river's lies (REQ-0007). |
| `FishPlan` | Model (value) | One generated fish: species, length, lie, lie score, activity. |
| `Population` (planned) | Model | The generated fish, kept between visits (needs saves). |
| `MoodRules` (planned) | Rule set | `Conditions` plus a fish's own state into mood and feeding depth. |

* **Today:** `FishGenerator` (REQ-0007) stocks a stretch for one day. It reads the stretch's spawn table (`SpawnEntry`: abundance and season window), `fish_per_100m`, the hatch table, the day's `Conditions` and the river's lies (scanned once). Its lies are the better of feeding and resting (`RestingLies`), and each reach of about 40 m along the river gets its share of fish by length (REQ-0011). It returns `FishPlan`s: species, length leaning small, the biggest fish on the best lies, whether the lie is a resting one (resting fish take a dry fly at `DriftPastRules.resting_dry_factor`), and an activity that scales how often each fish rises. A fish built from a plan returns to its own lie after a break-off. `tools/generate_fish.gd` runs it on any stretch from the command line. A species carries nothing about any place, and its diet is typed `DietEntry`s. Presentation arrives as a string and fish events are `StringName`s (R6, step C). The hook-set window check lives in `Fish.try_set()` (step C).

### 3.7 Hook set and fight

* **Hook set (planned, step C):** `HookSetModel`, tiny and pure: opens a window on a take, returns `HOOKED`, `TOO_EARLY` or `TOO_LATE`.
* **Fight:** `FightModel` fits. A fish longer than the rod's `rated_length_in` multiplies the fight's tension (`FightModel.load_for()`, REQ-0005). Its glue (fish position, rumble, bursts, the meter) is in `fishing_controller.gd`; it moves to the session and views in steps A and B.

### 3.8 Catch journal

* **Planned (step D):** `CatchJournal` of `CatchRecord`s: `species_id`, `fly_id`, `length_in`, `stretch_id`, day, time of day, season. Ids only. Feeds the catch card, the collection, the market, the fishing report.
* **Today:** `catches: Array[Dictionary]` holding resources, inside `fishing_controller.gd`. Nothing saves yet, so this is the cheapest moment to fix it.

### 3.9 Conditions (planned, step G)

Design target in [SPECIES_AND_CONDITIONS.md](SPECIES_AND_CONDITIONS.md): four 30-day seasons, six day slots, 10°F temperature bands, five weathers, hatches.

* `Calendar` (data, `data/calendar.tres`): the `Season`, `Slot` and `Weather` enums and the year's numbers. `SeasonWindow` (data): a span of the year, used by spawn and hatch entries.
* `Conditions` (REQ-0007): season, day, slot, weather, `intensity` (REQ-0008), air and water bands. It's the one value fish, the fish generator and the weather views read. *Today* the fishing node owns it: each load it builds a year from its seed and picks a day from it (`stock(conditions, seed)`, or an exported fixed day), and the debug overlay shows it with the spell, the hatch and the seed. One seed splits into the year, the day, the generator's streams and the take rolls (R8). The owner emits `conditions_changed(conditions)` whenever it changes. `set_conditions(c)` changes the slot or weather on the same water: the fish stay and only the hatch and their activity change; fish restock only for a new place.
* `WeatherGenerator` (REQ-0008): `year(climate, calendar, seed)` gives a `WeatherYear` of 120 `WeatherDay`s: spells from the climate's persistence, highs on a seasonal curve with a slow daily wander, storms only in the climate's storm slots, and a daily intensity. `WeatherYear.conditions(season, day, slot, spring_fed)` hands out `Conditions`. `tools/weather_year.gd` prints a year and a summary.
* `Clock` autoload (planned): day, slot, season. The only global time; it will hold the `WeatherYear`, walk it a slot at a time and emit the same `conditions_changed`, and nothing that reads them changes.

### 3.10 Modes and later systems

* **Practice** is a session configuration (fish off, target scorer on), not a sibling that flips flags on other nodes. *Today:* `cast_practice.gd` sets `Fishing.enabled`, swaps `Cast.rules` and calls `Cast.reel_in_line()` (R3, step B). Guiding clients will be another mode.
* **Fly tying, perception checks, the lodge:** each arrives as data plus a model, talking to others through ids and signals (`recipe_unlocked(id)`), never direct calls.

---

## 4. Target scene tree

```
Game (Node)                         owns GameState, pause and menus; loads stretches
├─ Stretch: CabinCreek (scene)      one per river location
│  ├─ RiverView (Node2D)            water, banks, rocks, streaks; reads the RiverField
│  ├─ FishingSession (Node)         phase, input, models, the RNG streams; no drawing
│  ├─ FishLayer (Node2D)            one FishView per Fish
│  ├─ LineView (Node2D)             line on the water, the fly, rings
│  ├─ CastView (Node2D)             line in the air, timing meter
│  ├─ Angler (Node2D)               walking, rod pose
│  └─ Camera2D                      owned by the stretch, follows the angler
├─ Weather (CanvasLayer)            the weather's grade, rain and snow (WeatherView)
├─ Hud (CanvasLayer)                fly box, catch count, coaching text, fight meter, catch card
├─ Screens (CanvasLayer)            journal, fly box, game menu with controls (backlog)
└─ DebugLayer (CanvasLayer)         finds things through groups
Autoloads: Controls, Clock, SaveGame
```

`Hud` listens to session signals. Coaching text has one owner (`Hud.say(text, quality)`).

---

## 5. Where new code goes

| I want to add... | It goes in | Not in |
|---|---|---|
| A fly, fish, rule set or tuning number | A `.tres` in `data/` | Code constants |
| A rule (odds, timing, physics, scoring) | A model (layer 2) with a unit test | A node script |
| A choice between rule variants | A strategy resource like `CastRules` | `if` branches on a mode flag |
| Where a species lives, or how many | The `Stretch`'s spawn table (R12) | `FishSpecies` |
| A link from one data file to another | A typed export, or an entry resource with a weight (R5) | A dictionary of ids |
| Something on screen | A view that reads state and listens to signals | The session or a model |
| A reaction to an event | Connect to the owner's signal in the session | Polling another node |
| A new phase | The session's phase enum and a model | A boolean on an existing node |
| Something saved | A record of ids in `GameState`, with a version | Resources or nodes in the save |
| Something global | An autoload, only after Traver agrees (R7) | Any gameplay rule |
| A new input | `tools/setup_input_map.gd`, `Controls`, the README table | Raw action strings |

---

## 6. Godot patterns we use, and why

* **Resources as data, `RefCounted` as rules.** Content is edited in the inspector and tested headless. Models run without a scene, so tests are fast and exact.
* **Strategy resources ("chassis").** A rule set is a `Resource` subclass with the same methods; swapping the file swaps the rules. This is how feel experiments stay cheap.
* **Signals up, calls down.** The owner wires its children in `_ready`. It keeps the tree rearrangeable and the dependencies one-way.
* **Groups for tools.** Debug views find nodes by group, so they're optional and never in the gameplay path.
* **Headless tests.** Every check, including this architecture test, runs from `tools/run_tests.sh` and in CI.

---

## 7. Fits and drifts, at a glance

| Area | Status |
|---|---|
| Pure models with unit tests (`CastModel`, `DriftModel`, `FightModel`, `Fish`, `RiverField`, `StickGestures`) | **Fits** (R1 checked) |
| Data as `.tres` with contract tests; ids match file names | **Fits** |
| Casting rule chassis; bite rules as a resource | **Fits** |
| `Controls` the only autoload; controller and keyboard parity | **Fits** (R7 checked) |
| Metres in models and data | **Fits** (R11 checked) |
| `fishing_controller.gd` (615 lines) and `stream_scene.gd` (449) do too much | **Drifts** (R9, steps A, A2) |
| Cast, Fishing and Practice reach into each other; no single phase owner | **Drifts** (R2, R3, step B) |
| `fly_pos` written by two nodes; world positions still in pixels in controllers | **Drifts** (R2, R11, step B) |
| Presentation strings, fish event `StringName`s | **Drifts** (R6, step C) |
| Catches as dictionaries of resources; no catalog or game state | **Drifts** (R5, step D) |
| Spawn table on `Stretch`; typed `DietEntry` diets | **Fits** (R5, R12, REQ-0004 C2) |
| One seed per load for the day, the fish and the take rolls (REQ-0007); `randomize()` left in `cast_model.gd`; a `_time` per controller | **Minor** (R8, step G) |
| `FlyPattern.draw_at()` | **Minor** (R1 debt until fly art) |

---

## 8. Keeping it true

`tests/architecture_test.gd` reads the source as text and checks R1, R3, R4, R5, R7, R8, R9, R10 and R11. Each failure names its rule. It has a **debt ledger**: code that breaks a rule today is listed with a cap.

* No entry means a cap of zero. New code can't add debt.
* A cap can only go down. When a refactor pays debt back, the test prints a note and the PR lowers the cap.
* Raising a cap or adding an entry needs Traver's explicit OK in the PR.

The rules marked "Review" (R2, R6, R12) are checked by the PR template's Architecture section and by self review (DEVELOPMENT_PROCESS.md Step 5).

---

## 9. Debt ledger (mirrors the test)

| Rule | File | Cap today | Paid back by |
|---|---|---|---|
| R3 | `scripts/fishing/fishing_controller.gd` | 4 reaches | Step B |
| R3 | `scripts/casting/cast_controller.gd` | 2 reaches | Step B |
| R3 | `scripts/casting/cast_practice.gd` | 3 reaches | Step B |
| R8 | `scripts/casting/cast_model.gd` (`randomize`) | 1 | Step G |
| R9 | `scripts/fishing/fishing_controller.gd` | 614 lines | Step A |
| R9 | `scripts/stream_scene.gd` | 451 lines | Step A2 |
| R9 | `scripts/river/river_field.gd` | 623 lines | Split builder from queries (river thread) |

By design, not debt: `scripts/world_scale.gd` converts to pixels (it is the conversion).

---

## 10. Migration plan

Small steps, each its own REQ and PR, each leaving the game playing the same unless the REQ says otherwise. `playthrough_test.gd` is the safety net. Each step names the debt it pays.

| Step | What | Pays | Depends on |
|---|---|---|---|
| **0** | This document, the audit, `architecture_test.gd`, agent guidance (this PR). | — | — |
| **A** | Split views out of `fishing_controller.gd`: `Hud` (fly box, count, coaching text, fight meter), `CatchCard`, `LineView`, `FishView`. | R9 | — |
| **A2** | Split `stream_scene.gd`: `RiverView`, `Angler`, camera owner. Agree with the river thread; pairs with REQ-0002's camera work. | R9 | River thread |
| **B** | `FishingSession` owns the phase and wires Cast, Fishing and the views. Practice becomes a session mode. `FlyState` with the line model its only writer; world positions in metres. | R2, R3, R11 | A; casting thread agrees the wiring |
| **C** | Enums for presentation and fish events; `HookSetModel`. | R6 | B, casting thread (changes `landed`'s argument type) |
| **D** | ~~`data/catalog.tres`~~ (done in REQ-0004 C1); `GameState` with `CatchJournal` (ids) and `FlyBox`. | R5 | A |
| **E** | ~~Data hygiene: spawn table, `DietEntry`, remove `bite_range_m` and the landing roll~~ (done in REQ-0004 C2). | R5, R12 | — |
| **F** | Folders by layer (`scripts/<system>/models`, `views`, ...), done in the Godot editor so references follow. Optional, after B. | — | B |
| **G** | `Clock` and `Conditions`; one seed per day split into RNG streams (generation, mood, take, cast) and shown in the debug overlay; then `MoodRules` and `Population`. *`Conditions`, the seed streams for generation and take, and `FishGenerator` were done in REQ-0007; `Clock`, the cast stream, `MoodRules` and `Population` remain.* | R8 | E |
| **Later** | Nymph (`DepthDriftModel`), streamer (`RetrieveModel`), hatches, tying, saves. Each adds a model and data, not edits to existing models. | — | The above |

Every step is a refactor of game code, so each needs Traver's go-ahead like any feature. Only step G and later change what a player sees.

**Coordination.** The casting thread owns `scripts/casting/` and the rule sets (steps B and C touch its wiring). The river thread owns `scripts/river/` and the field in `stream_scene.gd` (steps A2 and E's spawn table).

---

## 11. Class index

Every script, its layer and its system. `architecture_test.gd` fails if a script is missing here.

| Script | Class | Layer | System |
|---|---|---|---|
| `scripts/angler_view.gd` | `AnglerView` | View | Angler (drawing) |
| `scripts/casting/cast_controller.gd` | (node) | Session + view, to split | Casting |
| `scripts/casting/cast_look.gd` | `CastLook` | Data (look) | Casting (rod and arm drawing) |
| `scripts/casting/cast_model.gd` | `CastModel` | Model | Casting |
| `scripts/casting/cast_pose.gd` | `CastPose` | Model (static helper) | Casting (rod and arm drawing) |
| `scripts/casting/cast_practice.gd` | (node) | Mode + view, to become a session mode | UI and modes |
| `scripts/casting/cast_rules.gd` | `CastRules` | Rule set (data) | Casting |
| `scripts/casting/cast_tuning.gd` | `CastTuning` | Data | Casting |
| `scripts/casting/rules/tempo_rules.gd` | `TempoCastRules` | Rule set (data) | Casting |
| `scripts/casting/rules/tiered_rules.gd` | `TieredCastRules` | Rule set (data) | Casting |
| `scripts/conditions/calendar.gd` | `Calendar` | Data | Conditions |
| `scripts/conditions/climate.gd` | `Climate` | Data (place: a region) | Conditions (weather) |
| `scripts/conditions/conditions.gd` | `Conditions` | Model (value; a `Resource` so a fixed day can be set in the inspector) | Conditions |
| `scripts/conditions/season_window.gd` | `SeasonWindow` | Data | Conditions |
| `scripts/conditions/weather_day.gd` | `WeatherDay` | Model (value) | Conditions (weather) |
| `scripts/conditions/weather_generator.gd` | `WeatherGenerator` | Model | Conditions (weather) |
| `scripts/conditions/weather_look.gd` | `WeatherLook` | Data (look) | Conditions (weather drawing) |
| `scripts/conditions/weather_mix.gd` | `WeatherMix` | Model | Conditions (weather drawing) |
| `scripts/conditions/weather_style.gd` | `WeatherStyle` | Data (look) | Conditions (weather drawing) |
| `scripts/conditions/weather_view.gd` | `WeatherView` | View | Conditions (weather drawing) |
| `scripts/conditions/wind.gd` | `Wind` | Model | Conditions (wind over the land) |
| `scripts/conditions/weather_year.gd` | `WeatherYear` | Model (value) | Conditions (weather) |
| `scripts/controls.gd` | `Controls` (autoload) | Service | Input |
| `scripts/data/catalog.gd` | `Catalog` | Data (index) | All content |
| `scripts/debug_overlay.gd` | (node) | View | UI and modes |
| `scripts/fishing/diet_entry.gd` | `DietEntry` | Data | Fishing (fish, diets) |
| `scripts/fishing/drift_model.gd` | `DriftModel` | Model | Fishing (line) |
| `scripts/fishing/fight_model.gd` | `FightModel` | Model | Fishing (fight) |
| `scripts/fishing/fish.gd` | `Fish` | Model | Fishing (fish) |
| `scripts/fishing/fish_generator.gd` | `FishGenerator` | Model | Fishing (fish) |
| `scripts/fishing/fish_plan.gd` | `FishPlan` | Model (value) | Fishing (fish) |
| `scripts/fishing/fish_species.gd` | `FishSpecies` | Data | Fishing (fish) |
| `scripts/fishing/habitat_entry.gd` | `HabitatEntry` | Data | Fishing (fish, habitat) |
| `scripts/fishing/fishing_controller.gd` | (node) | Session + views, to split | Fishing |
| `scripts/fishing/insect.gd` | `Insect` | Data | Fishing (flies, diets) |
| `scripts/fishing/rules/drift_past_rules.gd` | `DriftPastRules` | Rule set (data) | Fishing (take) |
| `scripts/fishing/stick_gestures.gd` | `StickGestures` | Model | Fishing (line) |
| `scripts/river/features/boulder.gd` | `Boulder` | Data (river feature) | River |
| `scripts/river/features/eddy.gd` | `Eddy` | Data (river feature) | River |
| `scripts/river/features/fallen_log.gd` | `FallenLog` | Data (river feature) | River |
| `scripts/river/features/grass_bank.gd` | `GrassBank` | Data (river feature) | River (grass) |
| `scripts/river/features/grass_patch.gd` | `GrassPatch` | Data (river feature) | River (grass) |
| `scripts/river/features/gravel_bar.gd` | `GravelBar` | Data (river feature) | River |
| `scripts/river/grass_field.gd` | `GrassField` | Model | River (grass) |
| `scripts/river/grass_look.gd` | `GrassLook` | Data (look) | River (grass drawing) |
| `scripts/river/grass_view.gd` | `GrassView` | View | River (grass drawing) |
| `scripts/river/hatch_entry.gd` | `HatchEntry` | Data (place) | River, fish |
| `scripts/river/river_feature.gd` | `RiverFeature` | Data (base for river features) | River |
| `scripts/river/resting_lies.gd` | `RestingLies` | Model | River (lies) |
| `scripts/river/river_field.gd` | `RiverField` | Model | River |
| `scripts/river/spawn_entry.gd` | `SpawnEntry` | Data (place) | River, fish |
| `scripts/river/stretch.gd` | `Stretch` | Data | River |
| `scripts/river/water_look.gd` | `WaterLook` | Data (look) | River (drawing) |
| `scripts/river/water_type_rules.gd` | `WaterTypeRules` | Data | River (water types) |
| `scripts/river/water_types.gd` | `WaterTypes` | Model (value) | River (water types) |
| `scripts/river/water_view.gd` | `WaterView` | View | River (drawing) |
| `scripts/stream_scene.gd` | (node) | Scene root + views, to split | River, scene wiring |
| `scripts/tackle/fly_pattern.gd` | `FlyPattern` | Data | Tackle (flies) |
| `scripts/tackle/fly_box_view.gd` | `FlyBoxView` | View | Tackle (fly box HUD) |
| `scripts/tackle/fly_rod.gd` | `FlyRod` | Data | Tackle (rods) |
| `scripts/tackle/fly_view.gd` | `FlyView` | View | Tackle (flies, drawing) |
| `scripts/tackle/tackle.gd` | `Tackle` | Model | Tackle (what's rigged) |
| `scripts/world_scale.gd` | `WorldScale` | Model (static helper) | Units |

---

## 12. Decision log

Newest last. Read these before changing something that looks odd.

| Date | Decision | Why |
|---|---|---|
| 2026-11-01 | Godot 4.3, GL Compatibility, 320×200 ×4 | Steam Deck first, Switch later, crisp pixels. |
| 2026-11-02 | Rules in `RefCounted` models, content in `.tres` | Testable headless; hundreds of flies and fish as data. |
| 2026-11-02 | Casting rules as swappable resources | Compare feel side by side; Traver picked Count the false casts. |
| 2026-11-02 | River flow baked offline, sampled at runtime | No compute shaders on GL Compatibility; cheap on Deck and Switch. |
| 2026-11-02 | Start simple: one fish, one fly, visible odds | Hidden multi-condition bite rules felt broken in playtest. |
| 2026-11-02 | Metres in models and data, 8 px per metre | Traver's call (REQ-0001). |
| 2026-11-02 | Fish logic: generation, mood, take | Brainstorm with Traver. See FISH_LOGIC.md. |
| 2026-11-02 | Drift past is the one bite rules, with fly match | Traver's pick after playing the variants (REQ-0003). |
| 2026-11-03 | Numbered rules, enforced by `architecture_test.gd` with a debt ledger that only shrinks | Audit (ARCHITECTURE_AUDIT.md): the draft's rules weren't enforced and the code was drifting from them. |
| 2026-11-03 | Typed references between data, ids only in saves; a catalog; kinds separate from places | Audit: matches how larger data-driven games stay consistent as content grows. |
| 2026-11-03 | Adding content means adding a data file, never editing code (REQ-0004: catalog, spawn tables, river feature kit) | Traver: the architecture should make content cheap to add at scale. |
| 2026-11-03 | Flies and rods are "tackle" (`data/tackle/`, `scripts/tackle/`); a rod sets fly types, longest line, forgiveness and fish rating (REQ-0005) | Traver asked for rods grouped with flies; "tackle" avoids clashing with the repo's `tools/`. |
| 2026-11-04 | Weather comes from a seeded year per region's `Climate`: spells, a seasonal curve for highs, afternoon storms and an intensity; a weather change keeps the fish and re-rolls only the hatch (REQ-0008) | Traver: build out the weather generator; insects follow the weather, fish restock only for a new place. |
| 2026-11-04 | A seeded fish generator stocks any stretch from its spawn and hatch tables and the day's conditions; conditions are rolled per load until the clock exists (REQ-0007) | Traver: a repeatable generator for any stretch, driven by the river and the weather and date. |

## 13. Open questions for Traver

1. Does the reprioritised order (A, A2, B, then D and E, then G) suit you, and should step A start next?
2. Should the debt ledger allow small growth for a feature that must touch a big file before its split lands, or always block? (Recommended: block, and do the split first.)
3. The fish logic questions at the end of [FISH_LOGIC.md](FISH_LOGIC.md).
