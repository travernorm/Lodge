# Tooling

## What to install

| Tool | Why | Cost |
|---|---|---|
| [Godot 4.3+](https://godotengine.org/download) (standard build) | Engine. Light, strong 2D and pixel-art support, good gamepad handling, exports to Linux for Steam Deck. | Free |
| Godot export templates | Needed to export builds. In Godot: **Editor → Manage Export Templates → Download and Install**. | Free |
| [Aseprite](https://www.aseprite.org/) or [LibreSprite](https://libresprite.github.io/) | Pixel art and sprite animation (fish, flies, the angler, tiles). Aseprite is the standard; LibreSprite is a free fork. | ~$20 / free |
| Git + [GitHub Desktop](https://desktop.github.com/) (optional) | Version control and syncing with this repo. | Free |
| An Xbox-style controller | Lets you test the Deck control scheme on a PC before moving builds over. | — |

Later, worth adding when sound comes in: [Bfxr](https://www.bfxr.net/) or [ChipTone](https://sfbgames.itch.io/chiptone) for retro sound effects, and [Audacity](https://www.audacityteam.org/) for editing.

## Resolution and look

- The game renders at **320×200** and scales by whole numbers. 320×200 is exactly 1/4 of the Steam Deck's 1280×800 screen, so pixels stay crisp with no letterboxing on the Deck.
- Textures use nearest-neighbour filtering, and 2D transforms snap to whole pixels.
- The renderer is **GL Compatibility**, which is light on the Deck's battery and is also the path that ports most easily to Switch.

## Controls are defined in code

`tools/setup_input_map.gd` is the source of truth for the input map. To change a binding, edit that file and run:

```
godot --headless --path . --script res://tools/setup_input_map.gd
```

That rewrites the `[input]` section of `project.godot`. Game code refers to actions through the `Controls` autoload (`Controls.CAST_BACK`, `Controls.rod_vector()`, and so on) rather than typing raw action strings.

## Tuning the cast

All the casting feel numbers live in `data/cast_tuning.tres`. Open it in Godot and edit them in the inspector, then press F5 to try the result. The ones you'll most likely touch:

- **Stroke timing:** `base_stroke_time` and `stroke_time_per_m` set how long each stroke should be held. `perfect_window` and `ok_window` set how forgiving that is, and `drop_time` sets how late you can be before the line falls.
- **Bumper overlap:** `overlap_good_min`/`overlap_good_max` is the overlap that feels right, `tailing_overlap` is where it becomes a fault, and `gap_grace` is how long you can let go of both bumpers.
- **Line:** `line_start`, `line_max`, and how much line a clean false cast adds.

With the debug overlay open, you can read the real hold and overlap times from the Deck and set the windows from them. If you change the rules rather than just the numbers, run the cast tests afterwards.

## Trying different casting rules

The cast is split in two. `scripts/casting/cast_model.gd` runs the bumper state machine (back cast, overlap, forward cast, false casts, delivery). A **rule set** (`CastRules`, in `scripts/casting/cast_rules.gd`) decides what the rhythm means: how long each stroke should be, how a stroke is scored, how a false cast changes the line, and how far the delivery goes. Each rule set is a `.tres` file in `data/cast_rules/`:

- `classic.tres` plays like the original cast and reads its numbers from `data/cast_tuning.tres`.
- `count_false_casts.tres` (`TieredCastRules`, the default): `tempo` (the beat at Short), `tempo_per_step` (how much the beat stretches per step up), the window fractions, `step_lengths` (line for Short, Middle, Long) and `climb_quality` (how clean a false cast must be to climb a step).
- `find_your_tempo.tres` (`TempoCastRules`): the allowed tempo range, `line_gain` per false cast, and `follow` (how much the beat drifts toward your good strokes).

To tune one, open its file in the inspector, change the numbers, and run the game with **T** for practice mode and **Tab** to pick the rule set.

To try a new idea, add a script in `scripts/casting/rules/` that `extends CastRules` and overrides any of `start_line`, `stroke_ideal`, `perfect_window`, `ok_window`, `score_stroke`, `after_false_cast` and `delivery_reach`. Give it a `class_name`, create a `.tres` from it in `data/cast_rules/` with a `display_name` and `description`, and add it to the `chassis` list on the **Practice** node in `scenes/main.tscn`. The Short/Middle/Long boundaries are `SHORT_MAX` and `MIDDLE_MAX` in `cast_rules.gd`. Add a case for it to `tests/cast_rules_test.gd` (each rule set must land Short with no false casts and Long with five clean ones).

The **Cast** node's `rules` property picks the rule set the game starts with.

## Adding flies and fish

Insects, flies, rods and fish are data files, so adding one doesn't need code. The quickest way is a content sheet (below): one row per thing in a spreadsheet. You can also duplicate a `.tres` in Godot's FileSystem panel and edit it in the inspector, then run `tools/import_content.gd -- --export` so the sheets catch up.

- **New fly:** a row in `content/flies.csv`: a new `id`, `display_name`, colours, `fly_type` (Dry, Nymph or Streamer) and the insects it `imitates`. It joins the fly box at the end.
- **New rod:** a row in `content/rods.csv`: the fly types it throws, `max_line_m` (its longest line), `forgiveness` (1 is the baseline timing windows) and `rated_length_in` (fish longer than this snap the tippet sooner). L2 / R cycles rods in catalog order.
- **New fish:** a row in `content/fish.csv`: `bite_chance` (the odds for a perfect pass), `diet` and `selectivity`, the hook-set window (`set_min`/`set_max`), `pull` (around 1.0 snaps the tippet under full pressure), `toughness` and the size range. A species says nothing about where it lives: to put it in a river, add a `SpawnEntry` to that stretch's `spawn` list in `data/stretches/`.
- **Bite odds:** `DriftPastRules` (`data/take_rules/`) splits `bite_chance` into lane, landing and drift shares, and `selectivity` sets how much a fly that isn't on the diet costs.

## Content sheets

`content/` holds one spreadsheet per kind, as CSV: `insects.csv`, `flies.csv`, `rods.csv` and `fish.csv`. Each row is one file in `data/`, and the columns are that kind's fields, named as in the inspector. Open them in Numbers, Excel or Google Sheets (File, Import), edit, save as CSV, then run:

```sh
godot --headless --path . --script res://tools/import_content.gd
```

Every cell is checked before anything is written. If any is wrong, the tool lists each problem with its sheet, row and column (for example `fish.csv row 4 (redband), diet: no Insect 'pmdd' (known: attractor, baetis, ...)`) and writes nothing. Otherwise it rewrites only the files whose rows changed, creates files for new rows, and rebuilds the catalog when something is new. Run `tools/run_tests.sh` afterwards: the data tests check the rest (every fish has a fly that matches it, and so on).

How to fill a cell:

| Field | Write it as | Example |
|---|---|---|
| Text, numbers | As is. Commas are fine; the app quotes them. | `0.65` |
| Colour | html hex | `8a8a8a` |
| Fly type, rod fly types | The inspector's names; several joined with `;` | `Dry`, `Dry;Nymph` |
| A link, or a list of links | ids joined with `;` | `pmd;baetis` |
| A diet | `insect:weight` pairs joined with `;` | `pmd:1;caddis:0.5` |
| Empty | Keeps what the file has (or the default, for a new row) | |

* **Ids** are lower case with `_`, unique, and the file name. Never rename one: a rename makes a new file and leaves the old one.
* **Order:** a sheet can link to anything in the sheets before it (insects, then flies, then rods, then fish), including rows added in the same import.
* **Deleting a row doesn't delete the file.** The tool lists files with no row; delete those by hand.
* **New fields show up by themselves.** The columns are read from the scripts, so after adding an `@export` run `-- --export` to add its column. Ranges come from `@export_range`.
* `-- --check` prints what an import would change and writes nothing. `-- --export` rewrites the sheets from `data/`.
* `tests/content_test.gd` fails while the sheets and `data/` disagree, so they can't drift apart.
* Stretches aren't in a sheet: spawn tables and river features are edited in the inspector.

The drift and fight feel constants sit at the top of `scripts/fishing/drift_model.gd` and `scripts/fishing/fight_model.gd`, each with a comment. They're in metres and metres per second.

## Testing on the Steam Deck

The Deck runs Linux, so export the **Steam Deck (Linux x86_64)** preset.

1. In Godot: **Project → Export → Steam Deck (Linux x86_64) → Export Project**. This writes `build/linux/Lodge.x86_64`.
2. Copy the file to the Deck. Easy options are a USB stick, [Warpinator](https://github.com/linuxmint/warpinator) or [KDE Connect](https://kdeconnect.kde.org/) over Wi-Fi, or a shared network folder.
3. On the Deck, switch to **Desktop Mode**. Right-click the file, choose **Properties → Permissions**, and tick **Is executable**.
4. In Steam (desktop mode): **Games → Add a Non-Steam Game to My Library**, then browse to the file.
5. Return to Gaming Mode and launch it from your library. Under the game's controller settings, pick the **Gamepad** template so R1/L1 and the sticks arrive as a standard pad.

Open the debug overlay with View (Create on a PS5 pad). Use it to check that the bumpers and sticks register, and to read real hold and overlap timings while tuning the cast.

## Checks

- `tests/smoke_test.gd` verifies every input action exists, loads the main scene, then plays a whole catch through the input system: a cast, the trout rising, the hook set and the fight.
- `tests/cast_test.gd` tests the cast rhythm on its own: clean casts, false casts adding line, collapses, ticking the grass, tailing loops, early strokes, aim and pick-ups.
- `tests/recast_test.gd` checks that every new cast, including a pick-up off the water, starts back at Short for every rule set.
- `tests/cast_rules_test.gd` plays casts under each rule set: no false casts lands Short and five clean ones land Long for every set, the tiered steps, sloppy false casts not climbing, and the tempo rules accepting any steady beat but not a broken one.
- `tests/fishing_test.gd` tests the stick gestures (mend loop, hook-set flick), drift and mending, the bite odds (including that 2,000 simulated casts bite at the advertised rate), rises, hook-set timing, and fight outcomes.
- `tests/river_test.gd` tests the river field's hydraulics: thalweg, conservation, the boulder's cushion, pocket and seams.
- `tests/data_test.gd` checks the contracts between file sets: every fly, fish and rule set file loads and is valid, the scene's fly box, stocking and rule set list point at real files, every rule set can be picked in game, and every action has both a controller binding and a key.
- `tests/playthrough_test.gd` plays the real scene across systems: a catch under every rule set, walking the bank, the debug views during a drift and a fight, practice mode under every rule set, and reeling in.

  Run them all with one command. It also checks the input map matches `tools/setup_input_map.gd`, and fails a test that prints a script error even if it exits cleanly:

  ```
  tools/run_tests.sh               # everything
  tools/run_tests.sh playthrough   # just the tests whose name contains "playthrough"
  ```

  On a Mac it finds Godot in `/Applications`. Otherwise set `GODOT=/path/to/godot`. Any new `tests/*_test.gd` file is picked up automatically. See [DEVELOPMENT_PROCESS.md](DEVELOPMENT_PROCESS.md) for when to add tests and how changes are checked across systems.

- GitHub Actions runs all of them on every pull request (`.github/workflows/godot-check.yml`).
- `tools/capture_screenshot.gd` plays a scripted cast and saves screenshots. It needs a display; on a headless Linux machine, wrap it in `xvfb-run`.

## Web build

`export_presets.cfg` has a **Web** preset (single-threaded, so it runs on GitHub Pages without special headers). `.github/workflows/web.yml` exports it and publishes it to GitHub Pages on every push to `main`, or when run by hand from the Actions tab. It needs one setting: **Settings → Pages → Source: GitHub Actions**. To build it locally, install the Godot export templates (Editor → Manage Export Templates), then **Project → Export → Web**, and serve `build/web/` with any static server (for example `python3 -m http.server` in that folder). Opening `index.html` straight from disk doesn't work.

## Platform notes

- **Steam Deck / PC:** Linux export now. Windows and macOS presets can be added whenever they're needed.
- **Switch:** Godot can't export to Switch directly. Console builds go through a porting partner (for example W4 Games or Lone Wolf Technology) once the game is far enough along to pitch. Keeping to GL Compatibility and modest asset sizes keeps that path open.
