# Refactor backlog

Cleanups noticed but not done yet. When a REQ touches these files, consider pulling the item in (and note the REQ here when it's absorbed).

| Item | Files | Do it when | Effort |
|---|---|---|---|
| `fishing_controller.gd` mixes drift, fish events, the fight, the fly box, the catch card and all its drawing (615 lines on 2026-11-03, past the trigger). Split drawing and the catch card out. This is ARCHITECTURE.md step A, capped in the debt ledger. | `scripts/fishing/fishing_controller.gd` | Now: needs a REQ and Traver's go-ahead | M |
| Tests reach into private fields (`_time`, `_rng`, `_flight_to`) and compare `fishing.phase` with bare numbers. Add small public accessors (game time, the landing target; the seed hook is `stock(conditions, seed)` since REQ-0007) and use `Phase` names. | `tests/*.gd`, `cast_controller.gd`, `fishing_controller.gd` | The next change to those controllers (needs game-code approval) | S |
| `smoke_test.gd` and `playthrough_test.gd` duplicate their input helpers (`_wait`, `_tap`, `_stick`, the cast sequence). Move them into a shared `tests/support/` helper. | `tests/smoke_test.gd`, `tests/playthrough_test.gd` | After the open PRs that edit `smoke_test.gd` merge, so it doesn't conflict | S |
| The test stream builds its river field at load time from hand-written rules. Replace it with a baked field. | `scripts/stream_scene.gd`, `scripts/river/` | River plan step 3 (the bake prototype) | L |
| `FishGenerator` and `RiverField.pick_lie()` both scan the field's lie layer cell by cell. A `RiverField.lie_cells(area, min_score)` query would give them one shared scan. | `scripts/river/river_field.gd`, `scripts/fishing/fish_generator.gd` | When `river_field.gd` is split (builder from queries, river thread) | S |
