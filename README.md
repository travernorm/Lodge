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
| View (Select) | F1 | Toggle controller debug overlay |

The debug overlay starts hidden. Opening it gives a short rumble to test the controller's haptics. The top strip shows the last 2 seconds of R and L presses, plus hold times and overlap in milliseconds, so the cast rhythm can be tuned with real numbers.

## Project layout

```
scenes/main.tscn            Test stream scene (entry point)
scripts/controls.gd         `Controls` autoload: action names and stick helpers
scripts/stream_scene.gd     Placeholder river, current model (flow_at), angler and rod
scripts/casting/            Cast rhythm logic (cast_model.gd), scene glue and drawing
                            (cast_controller.gd), tunables (cast_tuning.gd)
data/cast_tuning.tres       Casting feel numbers; edit in the Godot inspector
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
tests/fishing_test.gd       Headless tests for gestures, drift, rises, hook sets and fights
export_presets.cfg          Linux x86_64 export for Steam Deck
docs/TOOLING.md             Tools, Steam Deck testing, conventions
```

See [docs/TOOLING.md](docs/TOOLING.md) for the full setup, including how to get builds onto a Steam Deck.
