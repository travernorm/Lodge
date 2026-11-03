# Development Process

How changes to Lodge are planned, built, tested and handed off. Lodge is a Godot 4.3 fly fishing game in `travernorm/Lodge`, built for the Steam Deck first and Switch later, with a browser build on GitHub Pages. Traver plays on a Mac with a PS5 DualSense and pulls with GitHub Desktop.

Follow these steps in order, scaled to the change. The top priority throughout is **regression safety across systems**: a change to one part of the game (casting, the river, fish, UI) must not quietly break another. See [Cross-system safety](#cross-system-safety).

## Choosing a track

* **Small change** (bug fix, a tuning number in a `.tres`, a typo, a new fly or fish file that uses existing fields, a small UI tweak): skip the REQ. Go straight to Steps 4 to 8: fix it, run all the tests, open a PR, hand off.
* **Feel experiment** (Traver wants to try something by hand before deciding, like the casting rule sets): build two or three variants side by side behind a toggle or as swappable data, with the simplest version first and its odds or rules visible on screen. Traver plays them and picks. Then either delete the losers or keep them as data, and follow the small or feature track to finish the winner.
* **Feature or structural change** (a new mechanic or system, a new screen or menu, a change to how systems talk to each other, the scene tree, a data class's fields, the input map, saves, or anything touching two or more systems): follow the full process below.
* If unsure, ask Traver which track in one line.

## Ownership model

* **Step 1 is collaborative.** Traver works with you as Product Owner to define requirements, back and forth.
* **Steps 2, 2a and 3 are autonomous.** Once Traver approves the initial requirement, run them without waiting.
* **Stop before Step 4 for review.** Hand Traver the revised REQ, plus a quick mockup screenshot when the change is visual. For feel, a mockup can't show it, so offer a feel experiment instead. Traver must explicitly approve before game code is written.
* **Steps 4 to 8 are autonomous** after that approval.
* **Quality over speed.** Do each step thoroughly. Show your work briefly at step transitions.
* **Step 8 ends with a handoff.** Traver decides when to merge.

## Lenses

* **Player feel.** Does it feel tactile on a controller, especially the R/L bumper cast and right-stick work? Is it readable at 320×200 on a 7-inch screen? Is the simplest version first, with its rules or odds visible, before depth is layered on? Does it keep the solitary, cabin-core, river-first tone?
* **Engine and performance.** Godot 4.3 with the GL Compatibility renderer, so no compute shaders and nothing that blocks the Switch port. A steady 60 fps on the Deck. The web build is single-threaded. Logic is frame-rate independent (uses `delta`) and survives `Engine.time_scale` changes. Randomness goes through a seedable `RandomNumberGenerator` so tests are repeatable. Heavy work (like river hydraulics) is baked offline, not simulated live.
* **Architecture.** Does it fit the existing patterns? Gameplay numbers and content are data (`.tres` in `data/`), not code. Rules live in plain models that can be tested without the scene (`cast_model.gd`, `drift_model.gd`, `fight_model.gd`, `river_field.gd`), with scene glue kept thin. Actions go through the `Controls` autoload. Systems talk through signals and a few named methods, listed in the [system map](#system-map). Avoid growing already-large files (see `docs/refactor-backlog.md`). The layers, owners, contracts and numbered rules (R1 to R12) are in `docs/ARCHITECTURE.md`; check a change against it, and update it in the same PR when a system or link changes. `tests/architecture_test.gd` enforces most of the rules and holds the debt ledger.

## Standing rules

* **Save data.** There are no saves yet. When saves arrive: every save file carries a `version`, and any format change ships with a migration and a test that loads a saved fixture from each older version (`tests/fixtures/saves/`). Content ids (`FlyPattern.id`, `FishSpecies.id`) will be stored in saves and the catch log, so never rename or reuse an id; add a new one instead. A data file's id must match its file name (enforced by `tests/data_test.gd`).
* **Controller and keyboard parity.** Every action has both a controller binding and a keyboard key, and no button or key is bound twice (enforced by `tests/data_test.gd`). Change bindings only in `tools/setup_input_map.gd`, then regenerate `project.godot` (CI fails if they drift). Update the controls table in `README.md` and the header in `scripts/controls.gd` in the same PR. No mouse-only UI. Name buttons both ways in handoffs (R1 / R bumper, Cross / A).
* **Web build.** `main` must keep exporting and running in the browser. That means single-threaded, nothing that needs threads or GDExtension, `user://` treated as browser storage, no reliance on rumble (it's a no-op there), and a controller that only connects after a button press. Check the browser build for any change to rendering, input, audio or file access.
* **Steam Deck.** The game renders at 320×200 and scales ×4 to 1280×800, with nearest filtering and pixel snapping. It uses the Linux x86_64 export and the Deck's Gamepad template. Text must stay legible at that size (8 px font minimum). Changes to feel, input, performance or the export are checked on the Deck, or the PR says they haven't been yet.
* **Switch, later.** Keep to GL Compatibility, modest asset sizes, and no plugins or native extensions without discussing it first.
* **Original content.** Art, sound, fonts and text are original or properly licensed, with the license noted when added.
* **Game code needs approval.** Outside an approved REQ or a small-track fix, only tests, CI, tools and docs change without asking.
* **The architecture debt ledger only shrinks.** The caps in `tests/architecture_test.gd` (mirrored in ARCHITECTURE.md section 9) can be lowered by any PR that pays debt back, and must be when the test says so. Raising a cap or adding an entry needs Traver's explicit OK in the PR, with the reason in its Architecture section.
* **Every handoff says how to get it:** in GitHub Desktop, **Fetch origin**, then **Pull origin**, then open Godot and press **Cmd+B**. After a merge to `main`, it's also playable at https://travernorm.github.io/Lodge/.

---

## Cross-system safety

This is the part of the process that matters most. Lodge's systems are tightly linked, since the fish lie in the river the fly drifts on, after a cast whose rule set practice mode can swap, so a local change can break something two systems away.

### System map

| System | Main files | Other systems that depend on it | Covered by |
|---|---|---|---|
| **Casting** | `scripts/casting/`, `data/cast_rules/`, `data/cast_tuning.tres` (reads the rigged rod: line cap, forgiveness) | Fishing (the `landed` signal, `fly_pos`, the flight target), Practice (`landed`, `collapsed`, swapping `rules`), debug overlay, the rod pose in the stream scene | `cast_test`, `cast_rules_test`, `smoke_test`, `playthrough_test` |
| **River** | `scripts/river/river_field.gd`, `scripts/stream_scene.gd`, `scripts/river/water_view.gd` + `data/looks/` (the water look) | Drift (`flow_at`), fish lies, line drift when fishing is off, water drawing (`WaterView` bakes the field into its shader), read-the-water view, `is_water` for landings | `river_test`, `water_view_test`, `smoke_test`, `data_test` (lie areas cover water, looks complete) |
| **Fishing** | `scripts/fishing/`, `data/insects/`, `data/tackle/flies/`, `data/fish/`, `data/take_rules/` | River (stocked from `Stretch.spawn`, lies from the field), Casting (`line_target`, `can_pick_up` for the rod and pick-ups), debug overlay, Practice (turns `enabled` off). Bite rules (`DriftPastRules`, the only set) read the drift (`DriftModel.slip`), the cast's presentation and the tied-on fly (fly box → `FishSpecies.diet` through `data/insects/`) | `fishing_test`, `caught_fish_test`, `mend_feed_test`, `take_rules_test`, `match_fly_test`, `data_test`, `smoke_test`, `playthrough_test` |
| **UI and modes** | `scripts/casting/cast_practice.gd`, `scripts/debug_overlay.gd`, on-screen messages | Uses all of the above | `smoke_test`, `playthrough_test` |
| **Input** | `tools/setup_input_map.gd`, `project.godot`, `scripts/controls.gd` | Everything | `data_test` (parity, every `Controls` action exists), CI input-map check, every test that plays through input |
| **Tackle** | `scripts/tackle/`, `data/tackle/flies/`, `data/tackle/rods/` | Casting (`CastModel.rod`: longest line, timing windows), Fishing (the tied-on fly for the bite rules, the rod's rating for the fight), Practice (ruler runs to the rod's line), the HUD | `rod_test`, `match_fly_test`, `data_test` (rods valid, the starting rod throws a fly), `playthrough_test` (rod pass) |
| **Content catalog** | `data/catalog.tres`, `scripts/data/catalog.gd`, `tools/build_catalog.gd`; the sheets in `content/` with `tools/import_content.gd` and `tools/content_sheets.gd` | Fishing (the fly box is the catalog's fly list), later spawn tables, the journal and saves. The sheets read the archetype scripts' exported fields and write their data folders | `catalog_test`, `data_test` (catalog matches the folders), `content_test` (sheets match the data, bad cells caught), `architecture_test` (no script names a content file) |
| **Scene wiring** | `scenes/main.tscn` (the stretch), `cast_practice.gd` (rule set chassis) | Everything | `data_test` (every list points at real data, every rule set is reachable), `smoke_test` |

Keep this table current. A PR that adds a system, or a new dependency between two systems (a signal, or one system calling into another), adds a row or a column entry here and a test that fails if that link breaks.

### Test layers

All tests run headless from `tools/run_tests.sh` and in CI on every PR.

1. **Architecture check** (`architecture_test`): reads the source and fails on a broken layer rule (models touching the tree, nodes reaching into siblings, writes to shared data, untyped data links, unseeded randomness, new autoloads, oversized files, scripts or data folders missing from ARCHITECTURE.md). Each failure names its rule.
2. **Unit tests** per system (`cast_test`, `cast_rules_test`, `fishing_test`, `river_test`): the models' rules on their own, fast and exact.
3. **Contract tests** across file sets (`data_test`): every file in `data/insects`, `data/tackle/flies`, `data/tackle/rods`, `data/fish` and `data/cast_rules` loads as the right class with valid fields; ids match file names and are unique; every stretch's spawn table names real species; every fly imitates real insects and every diet names real ones, and every fish has a fly that fully matches it; the scene's fly box, spawn table and rule set chassis point at real data and every rule set file is reachable in game; every action has a controller binding and a key with no doubled bindings. These read folders, so new data is covered automatically. `content_test` checks the content sheets in `content/` agree with those files and that the importer catches bad cells.
4. **Smoke test** (`smoke_test`): the main scene loads and one full catch plays through the real input system.
5. **Integration playthrough** (`playthrough_test`): plays the real scene through input across systems: a catch under every rule set with no false casts and with one, walking the bank between catches, the debug views cycled during a drift and a fight, practice mode under every rule set (no bites, every landing scored), and B reeling in.
6. **Manual playtest** (below), on the keyboard and the DualSense.

The runner also fails a test that prints a `SCRIPT ERROR` or engine `ERROR:` even if it exits 0, because Godot can log a broken script and carry on.

### Rules

* **Run everything, every time.** Before pushing, run `tools/run_tests.sh` (about a minute). Never run only the suite for the system you changed.
* **New logic gets a unit test. A new system gets a pass in the playthrough.** A new data folder gets covered in `data_test`. A new mode or screen gets toggled in the playthrough while other systems are mid-action (during a drift, during a fight).
* **A failing test in another system is a finding, not an obstacle.** Don't change another system's test to make it pass unless the behaviour change is intended and the PR says so plainly. Never skip or delete a test to get green.
* **Tests use real input** (`Input.action_press`, `Input.parse_input_event`) where they can, seed their random numbers, and wait on game time, not frames.
* **Content goes in data.** Tests should read data folders rather than list files, so adding a fly or fish doesn't mean editing tests.

### Manual playtest (about 5 minutes)

On the keyboard and on the DualSense:

1. Cast Short, Middle and Long. The rhythm and the rumble "tug" feel right.
2. Catch the trout: drift, rise, set, fight, catch card.
3. Strike at nothing, and reel in with B (Circle).
4. Practice mode (T / L3), cycle every rule set (Tab / R3), back to fishing.
5. Cycle the debug views (F1 / Create) during a drift.
6. If rendering, input, audio or files changed, the same in the browser build.
7. If feel, input, performance or the export changed, the same on the Deck, or say it's untested there.

### Pull requests and conflicts

Several PRs are often open at once and have conflicted before. To keep that manageable:

* **One goal per PR, kept small.** Branch from the latest `main`.
* **Merge the latest `main` into the branch** before opening the PR and again before handoff, then re-run all tests. Use a merge, not a rebase, so GitHub Desktop pulls stay simple.
* **Know the hot files**, the ones most PRs touch: `scenes/main.tscn`, `README.md`, `scripts/fishing/fishing_controller.gd`, `tests/smoke_test.gd`, `project.godot`. Touch them only when needed, keep edits small, and list in the PR which other open PRs touch the same files.
* **Put new tests in new files or new functions.** The runner finds every `tests/*_test.gd`, so a new suite needs no CI edit. Grow `smoke_test` only when the core catch changes; add other cross-system passes to `playthrough_test` as their own function.
* **`project.godot` is generated.** On an input-map conflict, take either side, re-run `tools/setup_input_map.gd`, and commit the result. Don't hand-merge it.
* **`.tscn` and `.tres` conflicts:** re-make the change in the Godot editor on top of `main` rather than hand-merging resource ids.
* **CI on a PR tests the PR merged into `main` as of the last push.** After another PR merges, an open PR's green check can be stale. When one PR merges, merge `main` into the other open PRs, re-run tests, and fix anything that broke before asking Traver to merge them.
* **Say the merge order** in the handoff when open PRs overlap. If one PR depends on another, base it on that branch and say so.

---

## Step 1: Requirements (Product Owner) [Collaborative]

* Define requirements with Traver iteratively, and challenge complexity. Start from the simplest playable version.
* Continue until Traver confirms it is complete.
* Output: `docs/requirements/REQ-####-kebab-title.md`, status `draft`, from `docs/requirements/_template.md` (problem, player story, feel goals, scope, out of scope, systems touched, acceptance criteria, playtest checks, open questions).

**Gate:** Traver approves the requirement.

## Step 2: Engineering review (Engineer)

* Find ambiguities, missing acceptance criteria and unstated assumptions.
* Evaluate input timing windows, frame-rate and `time_scale` independence, randomness and test determinism, data and save compatibility, the web and Deck builds, performance, and licensing of any assets.
* **Fill in "Systems touched"** from the system map: which systems change, which depend on them, and which tests and playthrough passes will prove nothing else broke.
* Record questions and answers in the REQ. Known issues must be resolved in Step 3.

## Step 2a: Architecture review (System Architect) [Optional]

**Include when** the change adds a system or shared pattern, adds a dependency between systems, changes the scene tree, a data class's fields, the input map or a save format, or has performance implications.

* Check the change against ARCHITECTURE.md rule by rule (R1 to R12) and section 5 (where new code goes). Name the layer of every new script, the owner of every new piece of state, and any debt in the ledger the change could pay back or would add to. Flag divergence from patterns, and recommend an approach with tradeoffs.
* Record the result as an "Architecture" section in the REQ.
* Reconcile with `docs/refactor-backlog.md`:
  1. **Pull in** backlog items in files this REQ already touches, when efficient. Propose them in Step 3, remove them from the backlog, and note the absorbing REQ.
  2. **Push out** out-of-scope cleanups found nearby: a one-line observation plus files, the trigger condition, and a rough effort.

## Step 3: Revise requirement

* Fold the Step 2 and 2a answers and any proposed scope changes into the REQ, and set status to `review`.
* Hand back to Traver with a short summary of what changed (and a mockup or a feel experiment if it's visual or about feel). Stop here.

## Step 4: Implementation

* Work on a feature branch from the latest `main`. Follow existing patterns. Keep commits focused.
* Put content and tuning numbers in data files, and rules in testable models.

## Step 5: Self review

* Review the diff against the REQ's acceptance criteria, the standing rules and the system map. Check that the README and `docs/TOOLING.md` still describe the game.
* Run the architecture check (the questions in `CLAUDE.md`) and fill in the PR template's Architecture section. If `architecture_test` prints a "debt paid" note, lower that cap in the test and in ARCHITECTURE.md section 9.

## Step 6: Testing

* Run `tools/run_tests.sh`; everything passes with no errors in the output.
* Add unit tests for new logic, contract checks for new data, and a playthrough pass for a new system or cross-system link.
* Merge the latest `main` and run again.
* Do the manual playtest, plus the browser and Deck checks the change calls for.

## Step 7: Ship

* Open a PR using the template. Tick the systems touched, list overlapping open PRs, and add screenshots (`tools/capture_screenshot.gd`) when it's visual.
* Update the REQ status to `implemented`, and the backlog and system map if needed.

## Step 8: Handoff

* Summarize what changed, how to try it (with DualSense and keyboard controls), what to watch for, which systems it touched and how they were checked, the merge order with other open PRs, and the GitHub Desktop pull steps. Do not merge; Traver decides.
