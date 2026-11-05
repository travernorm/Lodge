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

## Changing how the water looks

The water is painted by `WaterView` (`scripts/river/water_view.gd`) from a **water look**, `data/looks/water_spring.tres`. The river's shape lives in the stretch (`data/stretches/`), and the look only decides how that shape is painted, so the dark texture always sits on the real deep water and the white water on the real fast water.

1. Open `scenes/main.tscn`. The water shows in the editor viewport (the `Water` node builds its own copy of the river from `preview_stretch`).
2. Double-click `data/looks/water_spring.tres` (or click the `Water` node and open its `look`). Everything in the Inspector updates the viewport live:
   - **Deep, Mid, White**: drag a PNG from the FileSystem dock into a slot. Use seamless tiles, about 64x64, made in PixelLab and cleaned up in Aseprite. The starting tiles are in `assets/water/`.
   - **Tints**: multiply each texture by a colour. White leaves it as drawn.
   - **Where each texture shows**: `deep_start` is the depth where deep water takes over (0 = dry, 1 = deepest), `white_start` is the speed where white water takes over (1 = the fastest water), and each has a softness. `shallow_depth` and `shallow_amount` add the tint along the edges.
   - **Edges**: `edge_noise` makes the borders wobble, and `dither` switches between smooth blends and a crisp pixel checkerboard.
   - **Motion**: `motion` is how fast the textures travel with the current (0 = still), and `motion_cycle` is how often the moving texture quietly resets.
3. Save, and press Cmd+B to see it in the game.

To go back to the old flat colours, clear the `look` slot on the `Water` node. A new season or river can have its own look: duplicate the file in `data/looks/` and point the `Water` node at it.

## Changing how the shoreline looks

The land of a stretch (the wet line at the water, gravel, point bars, sand, the cut bank on the outside of bends, and the ground the grass grows on) is painted by `BankView` (`scripts/river/bank_view.gd`) from a **bank look**, `data/bank_looks/spring.tres` (REQ-0013).

1. Open `scenes/main.tscn`. The bank shows in the editor viewport (the `Bank` node builds its own river from `preview_stretch`).
2. Double-click `data/bank_looks/spring.tres` (or click the `Bank` node and open its `look`):
   - **Cut Bank**: the face strip that repeats along the bank, grass lip at the top and mud at the bottom. Make it as wide as you like and about 16 px tall (`face_height_m` 2 m shows 16 px pixel for pixel). Today's is `assets/bank/cut_bank.png`.
   - **Wet Stones, Gravel, Sand**: drag seamless 64x64 tiles in. Empty slots draw placeholder pebbles in the matching tint.
   - **Colours**: tints for each ground (they multiply a texture), and the ground and tuft colours under the grass.
   - **Widths**: the wet line, the gravel along a straight bank, how much wider a point bar gets, and the sand fringe, all in metres.
   - **Cut bank**: how far round a bend the face starts and reaches full height, its height, and the grass lip kept where it tapers.
   - **Edges**: how ragged the edges between grounds are.
3. Save, and press Cmd+B to see it in the game.

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
- **New fish:** a row in `content/fish.csv`: `bite_chance` (the odds for a perfect pass), `diet` and `selectivity`, the hook-set window (`set_min`/`set_max`), `pull` (around 1.0 snaps the tippet under full pressure), `toughness` and the size range. `water_min_f`/`water_max_f` set the water it can live in (30 to 70, the lower °F of each band). `habitat` says which kinds of water it likes (`Pocket:1;Pool:0.8`); types it leaves out get a small stray weight, and an empty habitat likes all water. A species says nothing about where it lives: to put it in a river, add a `SpawnEntry` to that stretch's `spawn` list in `data/stretches/`.
- **Bite odds:** `DriftPastRules` (`data/take_rules/`) splits `bite_chance` into lane, landing and drift shares, and `selectivity` sets how much a fly that isn't on the diet costs.

## Stocking a stretch with fish

Each load, the fish generator (REQ-0007) stocks the stretch for one day: it rolls the day from a seed (season, day, time slot, weather, air and water temperature) and places fish from the stretch's data. To fill a new stretch, set these in the inspector on its `.tres` in `data/stretches/`:

- `spawn`: a `SpawnEntry` per species, with its `abundance` (0 to 1, how common it is here) and an optional season `window` (Spring 1 to Winter 30 when empty).
- `fish_per_100m`: how many fish per 100 m of river. The demo's 2.7 gives 5 fish.
- `hatches`: a `HatchEntry` per insect, with its season `window`, the `slots` and `weathers` it comes off in, and its `strength`. Fish that eat a hatch that's on rise more often.
- `spring_fed`: water that stays in the 40s and 50s all year.

How keen fish are in each slot and weather is in `data/calendar.tres`. The weather itself (each season's temperatures, weather odds and spells) is a region's climate in `data/climates/` (REQ-0008); the tool uses `central_oregon`.

Try a stretch from the command line before playing it:

```
godot --headless --path . --script res://tools/generate_fish.gd -- --stretch demo_freestone --season summer --day 12 --slot dusk --weather overcast --seed 42
godot --headless --path . --script res://tools/generate_fish.gd -- --stretch demo_freestone --runs 200
```

The first prints the day, the hatch and every fish (species, length, lie, lie score, activity). The second prints each species' share, average and biggest length over 200 days. Leave out any day option to roll it. A seed with no day options gives the same day and fish as the game with that seed, which the debug overlay (View / F1) shows. In the game, set `fixed_seed` or `fixed_conditions` on the Fishing node to pin a day.

## Weather years

`tools/weather_year.gd` prints a year of weather from a climate in `data/climates/` (REQ-0008), so a climate can be tuned before playing it:

```
godot --headless --path . --script res://tools/weather_year.gd -- --climate central_oregon --seed 42
godot --headless --path . --script res://tools/weather_year.gd -- --years 100
```

The first prints one row per day (weather, intensity, high, where it sits in its spell, and when a storm hits) and a summary. The second prints only the summary over 100 years: each weather's share of each season, the average spell in days, and the average high early (days 1 to 10) and late (21 to 30) in the season. To make spells longer or shorter, change the climate's `persistence`.

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
| A habitat | `type:weight` pairs joined with `;` (Riffle, Run, Pool, Tail Out, Pocket, Seam, Eddy; `tail_out` works too) | `Pocket:1;Pool:0.8` |
| Empty | Keeps what the file has (or the default, for a new row) | |

* **Ids** are lower case with `_`, unique, and the file name. Never rename one: a rename makes a new file and leaves the old one.
* **Order:** a sheet can link to anything in the sheets before it (insects, then flies, then rods, then fish), including rows added in the same import.
* **Deleting a row doesn't delete the file.** The tool lists files with no row; delete those by hand.
* **New fields show up by themselves.** The columns are read from the scripts, so after adding an `@export` run `-- --export` to add its column. Ranges come from `@export_range`.
* `-- --check` prints what an import would change and writes nothing. `-- --export` rewrites the sheets from `data/`.
* `tests/content_test.gd` fails while the sheets and `data/` disagree, so they can't drift apart.
* Rivers have their own sheets; see "River sheets" below. A stretch that isn't from a river sheet (the demo) is edited in the inspector.

## River sheets

A river is written as distance markers, the way a guide describes it ("at 340 m, a log on river left"), in two sheets in `content/` (REQ-0014):

* `rivers.csv`, one row per river: `id`, `name`, `width_m`, `start_heading_deg` (0 flows right, 90 flows down the screen), `fish_per_100m`, `spring_fed` (yes or no), `spawn` (`redband:0.6;brook:0.2`), `hatches_like` (a stretch whose hatch table the river shares), `grass_bank_m`, `notes`.
* `river_markers.csv`, one row per thing along a river: `river`, `at_m` (metres downstream from the top), `length_m` (for things that run along the river), `kind`, `side` (`left`, `right` or `mid`, facing downstream), `offset_m` (in from that bank; on land, back from the water), `size_m`, `value`, `note`.

| Kind | What it does | `value` |
|---|---|---|
| `section` | Starts a named section; each becomes `data/stretches/<river>_<section>.tres` | The name: `Upper Fall` |
| `end` | Where the river's rows stop | |
| `bend` | Turns the river over `length_m` | `left 60`, `right 90` |
| `water` | Sets the depth over `length_m` | `riffle`, `run`, `pocket`, `pool`, `tail_out`, `plunge` |
| `boulder`, `eddy`, `gravel_bar` | A feature in the water; `size_m` is its radius | eddy: strength (0 to 2) |
| `log` | A fallen log from that bank, angled downstream; `size_m` is its length | |
| `grass` | A patch of tall grass on that bank; `size_m` is its reach along the bank | density |
| `angler_start` | Where the angler starts, on that bank | |
| `waterfall`, `bridge`, `cabin`, `ford`, `trail`, `inflow`, `boat_launch`, `width`, `reach_break` | Planned: drawn on the plate and listed, built by REQ-0014 step 3 and later | |

Then run:

```sh
godot --headless --path . --script res://tools/import_river.gd
```

Every row is checked first (an unknown kind or fish, a bend with no angle, a marker past the river's end), and nothing is written if any is wrong. It writes each section's stretch, rebuilds the catalog when a section is new, and draws a preview plate per section in `docs/rivers/`: a top-down map from the real river field with every marker labelled by its distance, planned kinds in red. `-- --check` writes nothing; `-- --plates` redraws the plates only.

* The sheet is the source of truth for a generated stretch: an import overwrites it, so move things in the sheet, not in the inspector. `tests/river_import_test.gd` fails while a sheet and its stretch disagree.
* From Google Sheets: File, Download, CSV, one tab per file, saved over the file in `content/`.

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
- `tests/caught_fish_test.gd` checks that a landed fish stays out of the water for the session, never rises or bites, and frees its lie, while one that breaks off comes back.
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
