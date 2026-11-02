# Lodge

A cabin-core fly fishing game. A laid-off father inherits his late dad's cabin, rod and fly box in the Oregon Cascades, learns the river, and grows a guiding lodge. The game is built for Steam Deck first, with a Game Boy-inspired look and tactile bumper-and-stick casting.

| Fly on the water, 46% bite chance | Fish on | Landed |
|---|---|---|
| ![Fly on the pool with the trout's shadow nearby](docs/screenshots/drift.png) | ![Fighting a fish with the tension meter](docs/screenshots/fight.png) | ![Catch card for a redband rainbow](docs/screenshots/caught.png) |

## Current milestone: dry fly minigame

1. **Tooling and project skeleton** (done). Godot project, Deck control map, placeholder stream, controller debug overlay.
2. **Casting** (done). Hold R for the back cast, overlap into L for the forward cast, and alternate R/L to shoot line for distance.
3. **Rise, set and fight** (this step). One trout, one fly, a simple bite chance per cast, flick to set, then play line tension.
4. **Tune on the Deck.** Timing windows, rumble, and how readable the bite cue is.

## Play in the browser

The latest `main` is published at **https://travernorm.github.io/Lodge/** after every merge (`.github/workflows/web.yml`). Click the game once so it gets the keyboard, then use the keyboard controls below. A controller works too in Chrome or Edge: press a button after the page loads so the browser connects it. Rumble isn't available in the browser.

## Quick start

1. Install [Godot 4.3 or newer](https://godotengine.org/download) (the standard build, not .NET).
2. In Godot, choose **Import**, then pick this folder's `project.godot`.
3. Press **F5** to run. Plug in a controller or use the keyboard fallbacks below.

## How to cast

1. **Hold R.** The back cast unrolls behind you and the meter by the angler fills. A light rumble "tug" marks the moment the line straightens, and the fill turns green.
2. **Press L while still holding R, then let go of R.** That slight overlap (about 20 to 200 ms) shoots the forward cast. Letting go of R before pressing L collapses the cast. Holding both too long throws a tailing loop, or a wind knot if you really hang on.
3. **Hold L.** The line unrolls forward over the water. Then either:
   - **overlap back into R** for a false cast. Each clean false cast shoots more line (the dotted cross shows where it would land), or
   - **let go of L** to deliver the fly.
4. While casting, the **left stick swings your aim** upstream or downstream.
5. The fly lands **Delicate**, **Fair** or **Splashy** depending on your timing, then drifts on the current. **R** picks it up for another cast, and **B** reels in.

The longer the line, the longer each stroke needs, just like a real cast. Strokes that are too early fall short and splash down. Strokes that are too late drop the line onto the grass or the water.

## Casting practice and rule sets

![Practice mode: Short / Middle / Long target, the distance ruler, results and the stroke log](docs/screenshots/practice-mode.png)

Press **T** (or click the **left stick, L3**) for practice mode. Fish stop biting, and a target ring asks for a **Short**, **Middle** or **Long** cast in turn. The faint ruler by the rod marks where each distance band starts. Each landing is scored as a hit or a miss, the fly reels itself in, and the next target comes up. Press **T / L3** again to go back to fishing.

The **stroke log** (top right) shows every back (B) and forward (F) stroke of the cast as a bar. The bar's length is how long you held the bumper, the white tick is what the rules wanted, and the colour is the score (green perfect, yellow okay, red poor). The stroke you're holding right now grows in grey, so you can see your rhythm against the target as you cast.

Press **Tab** (or click the **right stick, R3**) to switch between casting rule sets. They all use the same bumpers and overlap, but turn your rhythm into distance differently:

| Rule set | Rhythm | How you get distance |
|---|---|---|
| **Count the false casts** (default) | A steady beat: 0.42 s at Short, stretching by 0.05 s with each step up | 0 false casts is Short, 1 is Middle, 2 or more is Long. A sloppy false cast doesn't climb a step |
| **Classic** | Strokes get longer as line goes out | Each clean false cast shoots 4 to 16 px of line. About 0 false casts is Short, 2 is Middle, 4 is Long |
| **Find your tempo** | Your first back cast sets the beat, fast or slow | Each false cast adds line in proportion to how well it kept your beat |

A bad delivery stroke still falls short of the line you have out, in every rule set. The numbers for each rule set live in `data/cast_rules/`, so they can be tuned in the Godot inspector. Fishing uses whichever rule set is selected, so you can also fish with each one. The game starts with Count the false casts (the `rules` property on the **Cast** node).

## How to fish

For now the stream holds **one Redband Rainbow** in the middle of the pool, and you have **one fly**, a Parachute Adams. Watch for the rings where it rises on its own to find it.

1. **Cast near the fish.** When the fly lands you'll see your chance of a bite. A delicate landing right by the fish gives the best odds (60%). Fair landings get about 60% of that and splashy ones 25%, and the chance falls off with distance until about 40 px out, where it's zero.
2. **Wait for the rise.** If the fish bites, it comes up for the fly a second or two later and the fly disappears.
3. **Set the hook.** Press **Space** (or **Cross / A** on a controller, or flick the right stick up). You have about a second.
4. **Fight.** **Hold Space** or **push the right stick** to pull it in, and watch the tension bar. Don't let the line go slack for long or it throws the hook. Pushing sideways against a run tires it faster. Reel it in close once it's tired to land it.

You can also mend the line by looping the right stick, but drag doesn't affect bites yet. More flies (`data/flies/`) and two more trout (`data/fish/`) are already set up as data and can be added back when we want more depth.

## Controls

| Steam Deck / Xbox pad | Keyboard | Action |
|---|---|---|
| R bumper | E | Back cast (hold to time it) |
| L bumper | Q | Forward cast (overlap with R) |
| Right stick | I J K L | Rod tip: mend, set the hook, strip |
| Left stick / D-pad | W A S D | Walk the bank |
| Right stick loop | — | Mend the line |
| A or right stick flick up | Space | Set the hook |
| Right stick hold | Space or I J K L | Pressure while fighting |
| Y | F | Change fly (when reeled in) |
| A | Space | Set the hook (later: interact / perception check) |
| B | Backspace | Back / reel in |
| Menu (Start) | Esc | Pause |
| View (Select) | F1 | Cycle debug views: controller, read the water, hidden |
| Left stick click (L3) | T | Casting practice on/off |
| Right stick click (R3) | Tab | Switch casting rule set |

The debug views start hidden. The first press opens the controller view and gives a short rumble to test the controller's haptics. Its top strip shows the last 2 seconds of R and L presses, plus hold times and overlap in milliseconds, so the cast rhythm can be tuned with real numbers.

## The river

![Read-the-water debug view: current arrows, the thalweg, seams and trout lies around the boulder](docs/screenshots/read-the-water.png)

The stream's current comes from a river field (`scripts/river/river_field.gd`) that follows real hydraulic rules: the same water passes every cross-section, so the shallow riffle runs fast and the deep pool runs slow; the fastest water follows the thalweg (the deepest line) and the banks are slow; and the boulder at the head of the pool makes a slow cushion in front, a slack pocket behind and a seam off each side. The field also scores where a trout would hold: slow, deep-enough water with fast water close by. The drift, the foam streaks and the water colour all read the same field.

Press **View / F1** twice for the read-the-water view. It draws the current, the thalweg, seams and trout lies, and shows the speed of the lane your fly is drifting in. For now the field is built from those rules when the scene loads; later it will be baked from a water solver in the editor, using the same layers.

## Project layout

```
scenes/main.tscn            Test stream scene (entry point)
scripts/controls.gd         `Controls` autoload: action names and stick helpers
scripts/stream_scene.gd     Placeholder river (bed, boulder, flow_at), angler and rod
scripts/river/river_field.gd  River field: current, depth, seams and trout lies on a grid
scripts/casting/            Cast rhythm logic (cast_model.gd), scene glue and drawing
                            (cast_controller.gd), tunables (cast_tuning.gd)
                            Swappable rule sets (cast_rules.gd, rules/), practice mode
                            (cast_practice.gd)
data/cast_tuning.tres       Casting feel numbers; edit in the Godot inspector
data/cast_rules/*.tres      Casting rule sets and their numbers (Classic, Count the
                            false casts, Find your tempo)
scripts/fishing/            Drift and mending (drift_model.gd), fish behaviour (fish.gd),
                            fight (fight_model.gd), stick gestures, and the scene glue
                            (fishing_controller.gd)
data/flies/*.tres           Fly patterns (FlyPattern)
data/fish/*.tres            Trout species: habitat, bite odds, hook-set window, fight
scripts/debug_overlay.gd    Bumper timeline, stick readouts, rumble test
tools/setup_input_map.gd    Source of truth for the input map (regenerates project.godot)
tools/capture_screenshot.gd Plays a scripted catch and saves screenshots
tests/smoke_test.gd         Headless check: a scripted cast, drift, hook set and fight end in a catch
tests/cast_test.gd          Headless tests for the cast rhythm
tests/cast_rules_test.gd    Headless tests for each casting rule set (Short/Middle/Long)
tests/fishing_test.gd       Headless tests for gestures, drift, rises, hook sets and fights
tests/river_test.gd         Headless tests for the river's hydraulics (thalweg, conservation, boulder)
export_presets.cfg          Linux x86_64 export for Steam Deck
docs/TOOLING.md             Tools, Steam Deck testing, conventions
```

See [docs/TOOLING.md](docs/TOOLING.md) for the full setup, including how to get builds onto a Steam Deck.
