# Architecture audit, 2026-11-03

An audit of [ARCHITECTURE.md](ARCHITECTURE.md) (the 2026-11-02 draft) and the game's code and data on `main` at `343a5cd`, against how well-run data-driven games are built. The findings changed ARCHITECTURE.md (now adopted, with numbered rules) and added `tests/architecture_test.gd`. Nothing here changes game code: each fix is a migration step that needs its own REQ.

## Verdict

The foundations are better than most projects this size. Rules live in pure, unit-tested models; content is data with contract tests; feel experiments use swappable rule resources; units are real; CI fails on any script error. The weak spots are the usual ones for a fast-moving prototype: two scripts that do everything, nodes that reach into each other, and a design doc whose rules nobody checked. In one day `fishing_controller.gd` grew from 440 to 615 lines, and the doc's "Today" notes went stale (it still cites PR #7 as open). For a project written mostly by fresh AI sessions, the second problem matters most: a rule that isn't checked by a test will erode.

## What's already best in class

| Practice | Where | Why it matters |
|---|---|---|
| Rules in pure `RefCounted` models | `CastModel`, `DriftModel`, `FightModel`, `Fish`, `RiverField`, `StickGestures` | Testable headless, deterministic, portable. All pass the new purity check. |
| Content as `.tres` with contract tests | `data/`, `tests/data_test.gd` | Ids match file names; diets and `imitates` checked against real insects; new files covered automatically. |
| Strategy resources for rule variants | `CastRules`, `DriftPastRules` | Cheap feel experiments; the losing variant is deleted, not left behind a flag. |
| Typed references between data | `FlyPattern.imitates: Array[Insect]` | Survives renames; the inspector shows a picker. The model for the rest of the data. |
| Real units | `WorldScale`, REQ-0001 | Data can hold real-world numbers; multi-screen stretches don't need retuning. |
| One input service, parity tests | `Controls`, `data_test` | Every action on both controller and keyboard; bindings generated, never hand-edited. |
| Errors fail CI even on exit 0 | `tools/run_tests.sh` | Catches Godot's "log and carry on" failures. |
| A decision log | ARCHITECTURE.md | Later sessions know why odd-looking things are the way they are. |

## Findings

Severity is about long-term cost if left alone. Each finding names the rule it breaks in the new ARCHITECTURE.md and the step that fixes it.

| # | Sev. | Finding | Evidence | Rule | Fix |
|---|---|---|---|---|---|
| F1 | High | **Two god nodes.** `fishing_controller.gd` holds drift glue, fish events, the hook set, the fight glue, the fly box, the catch log, the HUD, the catch card and the odds display. `stream_scene.gd` builds the river, walks the angler, runs the camera, makes textures and draws water. | 615 and 445 lines (cap in the old doc: ~300). `fishing_controller.gd` is a hot file in nearly every PR. | R9 | Steps A, A2 |
| F2 | High | **No owner for the fishing loop.** Cast, Fishing and Practice find each other with `get_parent()` and `get_node()`, call each other's methods and flip each other's flags. Fishing reads `river` and `stretch` from the scene by name (`.get(&"river")`), so a rename breaks it silently at runtime. | 9 reaches across 3 files; 35 `_cast.` uses in `fishing_controller.gd`, 19 in `cast_practice.gd`. | R2, R3 | Step B |
| F3 | High | **Two writers for the fly; pixels at the edges.** `Cast.fly_pos` is written by both Cast and Fishing. Controllers still place things in pixels and convert to metres at each call. | `fishing_controller.gd` converts with `WorldScale` in about a dozen places. | R2, R11 | Step B (`FlyState`) |
| F4 | Med | **Placement on the archetype.** `FishSpecies.lie_area_m` says where a species lives on *the test screen*. A species shared across many stretches can't carry that. `bite_range_m` and `Fish.bite_chance_for()` are left over from the dropped landing roll; only tests read them. | `fish_species.gd`, `fish.gd` header comment. | R12 | Step E (spawn table on `Stretch`) |
| F5 | Med | **Mixed reference styles.** `FlyPattern.imitates` holds typed `Insect` refs, but `FishSpecies.diet` is an untyped dictionary of insect id to weight. A typo there is only caught by `data_test`, and the inspector shows a free-text box. | `fish_species.gd:25` | R5 | Step E (`DietEntry` resource) |
| F6 | Med | **No catalog.** Code and tests find content by listing folders. That works in the editor, but exported builds rename resources to `.remap`, so runtime folder listing is fragile, and there's no one place to look up "the fly with id X" when loading a save. | `data_test._load_dir`, `DirAccess` | R5 | Step D |
| F7 | Med | **No game state or save model.** Catches are dictionaries holding resources inside a node. Saving them would serialize resource paths, which break on any move. Nothing saves yet, so this is the cheapest moment to fix. | `fishing_controller.gd` `catches` | R5 | Step D |
| F8 | Med | **Strings as types.** Presentation is `"Delicate"`, fish events are `&"take"`, `&"dimple"`. A typo is a silent bug. | `fish.gd` header, `DriftPastRules` | R6 | Step C |
| F9 | Low | **Unseeded randomness and several clocks.** `fishing_controller.gd` and `cast_model.gd` call `randomize()`; each controller keeps its own `_time`. Fine now; it blocks replays, repeatable bug reports and the day clock. | `fishing_controller.gd:96`, `cast_model.gd:84` | R8 | Step G |
| F10 | Low | **Drawing inside data and controllers.** `FlyPattern.draw_at()`; every node draws in `_draw()`. Fine for rectangles; when real art arrives, sprites and `AnimationPlayer` replace it. | `fly_pattern.gd` | R1 | Paid for flies: `FlyView` draws fly art (fly sprites PR) |
| F11 | Low | **`RiverField` builds and answers.** The builder half goes away when the bake lands (backlog). | 645 lines | R9 | River thread |
| F12 | Process | **Rules without enforcement.** The draft proposed `architecture_test.gd` in section 9 but it was never built, and the doc's "Today" notes drifted within a day. | ARCHITECTURE.md draft §6, §9 | R10 | Step 0 (this PR) |
| F13 | Low | **Tests poke private fields and write to shared data.** Tests read `_rng`, `_time`, `_flight_to`, and set `species.bite_chance` on loaded resources. Each test runs in its own process, so it doesn't leak today, but it ties tests to internals. | `smoke_test.gd:64`, `playthrough_test.gd:57` | R4 | Backlog item |

## Compared with best in class

| Practice in larger games | Lodge before | Lodge now |
|---|---|---|
| Layered architecture with one-way dependencies, checked by tooling | Written down, not checked | Checked by `architecture_test.gd` (R1, R3) |
| One owner per state machine (a game mode / session object) | Phase split across 4 places | Planned, step B; new reaches blocked |
| Archetype data separate from placement (spawn tables on locations) | Lie area on species | Rule R12, step E |
| Typed references inside content, ids only in saves, a content registry | Mixed | Rule R5, steps D, E; new loose exports blocked |
| A single versioned save model | None yet | Planned, step D, before any save exists |
| Deterministic simulation: one clock, seeded RNG streams | Mostly (models take an RNG) | Rule R8; new unseeded rolls blocked |
| Architecture fitness functions with ratchets (debt can only go down) | None | Debt ledger in the test, mirrored in ARCHITECTURE.md §9 |
| An architecture decision record | Decision log | Kept, with this audit's entries |

## What changed in this PR

* **ARCHITECTURE.md rewritten and adopted:** a "how to use this" section, numbered rules R1 to R12 with how each is enforced, a new data architecture section (kinds of data, references and ids, catalog, game state, units), refreshed "Today" notes, the debt ledger, a reprioritised migration plan where each step names the debt it pays, and a class index of every script.
* **`tests/architecture_test.gd`:** checks R1, R3, R4, R5, R7, R8, R9, R10 and R11 from the source text, with a ledger that only shrinks. It passes on today's code and fails on any new debt.
* **Agent guidance:** `CLAUDE.md` at the repo root, an architecture check in DEVELOPMENT_PROCESS.md Steps 2a and 5, and an Architecture section in the PR template.

## Recommended next step

Step A: split the views out of `fishing_controller.gd`. It's the hottest file, it pays the biggest debt, it changes no behaviour, and it makes step B much smaller. It needs a REQ and Traver's go-ahead.
