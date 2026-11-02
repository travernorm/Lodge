## What changed

<!-- One or two sentences, in player terms. Link the REQ if there is one. -->

## Systems touched

<!-- Tick every system this PR changes. The checks below say what to re-run for each. -->

- [ ] Casting (cast model, rule sets, `data/cast_rules/`, `data/cast_tuning.tres`)
- [ ] River (river field, flow, lies)
- [ ] Fishing (drift, fish, fight, `data/flies/`, `data/fish/`)
- [ ] UI / debug views / practice mode
- [ ] Input map (`tools/setup_input_map.gd`, `project.godot`)
- [ ] Save data
- [ ] Build / CI / export presets

## How it was tested

- [ ] `tools/run_tests.sh` passes locally (all suites, including the playthrough)
- [ ] New logic has tests; a new system has a pass in `tests/playthrough_test.gd`
- [ ] Played it: keyboard and controller
- [ ] Browser build checked (if it touches rendering, input, audio or files)
- [ ] Steam Deck checked, or noted as not yet (if it touches feel, input, performance or export)

## Shared files

<!-- Did this edit a hot file other open PRs also touch (scenes/main.tscn, README.md,
fishing_controller.gd, smoke_test.gd, project.godot)? Name the PRs it may conflict with. -->

## Try it

Fetch origin, then Pull origin in GitHub Desktop, open Godot and press Cmd+B. Or play the browser build after merge.
