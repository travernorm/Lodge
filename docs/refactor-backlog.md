# Refactor backlog

Cleanups noticed but not done yet. When a REQ touches these files, consider pulling the item in (and note the REQ here when it's absorbed).

| Item | Files | Do it when | Effort |
|---|---|---|---|
| `fishing_controller.gd` mixes drift, fish events, the fight, the fly box, the catch card and all its drawing (440 lines). Split drawing and the catch card out. | `scripts/fishing/fishing_controller.gd` | The next fishing feature, or when it passes ~500 lines | M |
| Tests reach into private fields (`_time`, `_rng`, `_flight_to`) and compare `fishing.phase` with bare numbers. Add small public accessors (game time, a seed hook, the landing target) and use `Phase` names. | `tests/*.gd`, `cast_controller.gd`, `fishing_controller.gd` | The next change to those controllers (needs game-code approval) | S |
| `smoke_test.gd` and `playthrough_test.gd` duplicate their input helpers (`_wait`, `_tap`, `_stick`, the cast sequence). Move them into a shared `tests/support/` helper. | `tests/smoke_test.gd`, `tests/playthrough_test.gd` | After the open PRs that edit `smoke_test.gd` merge, so it doesn't conflict | S |
| The test stream builds its river field at load time from hand-written rules. Replace it with a baked field. | `scripts/stream_scene.gd`, `scripts/river/` | River plan step 3 (the bake prototype) | L |
