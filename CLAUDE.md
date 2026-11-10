# Lodge: notes for AI agents

Lodge is a Godot 4.3 fly fishing game (GL Compatibility, 320×200 ×4) for the Steam Deck first, Switch later, with a browser build. Traver is the product owner and decides every merge.

## Read before changing anything

1. [docs/DEVELOPMENT_PROCESS.md](docs/DEVELOPMENT_PROCESS.md): tracks (small, feel experiment, feature), approvals, testing, PRs.
2. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): layers, rules R1 to R12, where new code goes, the debt ledger.
3. For fish behaviour, [docs/FISH_LOGIC.md](docs/FISH_LOGIC.md). For Godot vocabulary, [docs/GODOT_PRIMER.md](docs/GODOT_PRIMER.md). For any art, sprite, texture or shader look, [docs/ART_GUIDE.md](docs/ART_GUIDE.md).

## Hard rules

* **Game code needs approval.** Outside an approved REQ or a small-track fix, only tests, CI, tools and docs change without asking.
* **Fit the architecture.** Rules in pure models (`RefCounted`), content in `.tres` data, drawing in views, one owner per value, call down and signal up, metres in models. Cite the rule (R1 to R12) when a change bends one, and stop to ask rather than work around it.
* **The debt ledger only shrinks.** `tests/architecture_test.gd` lists today's exceptions with caps. Never raise a cap or add an entry without Traver's explicit OK in the PR. When your change pays debt back, lower the cap in the test and in ARCHITECTURE.md section 9.
* **Keep the map current in the same PR.** New script: add it to ARCHITECTURE.md's class index. New data folder: describe it in section 2 and load it in `tests/data_test.gd`. New link between systems: the system map in DEVELOPMENT_PROCESS.md.
* **Run everything.** `tools/run_tests.sh` runs every suite, including the architecture check. Never skip, delete or loosen a test to get green.
* **Branches and merges.** Branch from the latest `main`, merge (don't rebase) `main` in before handoff, keep hot files (`scenes/main.tscn`, `README.md`, `fishing_controller.gd`, `smoke_test.gd`, `project.godot`) edits small, and never merge a PR yourself.

## Architecture check (every PR that touches `scripts/`, `data/` or `scenes/`)

Answer these in the PR template's Architecture section:

1. Which layer is each new or changed script in, and does it use only layers below it? (R1)
2. Does every piece of state you added have exactly one writer? (R2)
3. Did any node reach into a parent or sibling, or read a property by name? (R3)
4. Is any data written at runtime, or linked by id strings instead of typed references? (R4, R5)
5. Any new strings standing in for types, autoloads, unseeded randomness or pixel units in a model? (R6, R7, R8, R11)
6. Does any file pass 400 lines, and did the ledger move? (R9)
7. Is everything new on the map? (R10)
8. Does a kind of thing (species, fly) now carry data about a place? (R12)
