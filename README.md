# Lodge

A cabin-core fly fishing game. A laid-off father inherits his late dad's cabin, rod and fly box in the Oregon Cascades, learns the river, and grows a guiding lodge. The game is built for Steam Deck first, with a Game Boy-inspired look and tactile bumper-and-stick casting.

| Drifting a Royal Wulff over trout | Fish on | Landed |
|---|---|---|
| ![Fly drifting on the pool with trout shadows below](docs/screenshots/drift.png) | ![Fighting a fish with the tension meter](docs/screenshots/fight.png) | ![Catch card for a brook trout](docs/screenshots/caught.png) |

## Current milestone: dry fly minigame

1. **Tooling and project skeleton** (done). Godot project, Deck control map, placeholder stream, controller debug overlay.
2. **Casting** (done). Hold R for the back cast, overlap into L for the forward cast, and alternate R/L to shoot line for distance.
3. **Drift, rise, set and fight** (this step). The fly drifts on the current, the right stick mends, a fish rises, you flick to set, then hold and play line tension. 3 flies and 3 trout.
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

1. **Pick a fly.** Press **Y** while reeled in to cycle the fly box. Each trout has a favourite:
   - **Westslope Cutthroat** hold in the riffle and like the **Elk Hair Caddis**. They rise slowly, so wait a beat before setting.
   - **Redband Rainbows** sit on the seam where the riffle meets the pool and like the **Parachute Adams**. They run hard.
   - **Brook Trout** tuck along the slow far edge of the pool and go for the **Royal Wulff**. They strike fast.
2. **Cast upstream of a fish.** Trout face into the current (left), so land the fly upstream and let it drift down to them. You can see their faint shadows. A splashy landing near a fish spooks it.
3. **Mend.** The belly of your line drifts faster than the fly and starts to drag it, which shows as a V-wake behind the fly. **Loop the right stick** (about half a circle) to flip the belly back upstream. Mend too early and you yank the fly.
4. **Set the hook.** When a fish rises and the fly disappears, **flick the right stick up**. Too soon pulls the fly away, and too late means it spits the fly. Each species has its own timing.
5. **Fight.** **Push the right stick** to put pressure on, and watch the tension bar. Ease off when it runs, or the tippet snaps. Push sideways against a run to tire it faster. Give it no pressure at all and it throws the hook. Once it's tired, reel it close to land it.

## Controls

| Steam Deck / Xbox pad | Keyboard | Action |
|---|---|---|
| R bumper | E | Back cast (hold to time it) |
| L bumper | Q | Forward cast (overlap with R) |
| Right stick | I J K L | Rod tip: mend, set the hook, strip |
| Left stick / D-pad | W A S D | Walk the bank |
| Right stick loop | — | Mend the line |
| Right stick flick up | I (tap) | Set the hook |
| Right stick hold | I J K L | Pressure while fighting |
| Y | F | Change fly (when reeled in) |
| A | Space | Interact / perception check |
| B | Backspace | Back / reel in |
| Menu (Start) | Esc | Pause |
| View (Select) | F1 | Toggle controller debug overlay |

The debug overlay starts hidden. With it open, press A to test rumble. The top strip shows the last 2 seconds of R and L presses, plus hold times and overlap in milliseconds, so the cast rhythm can be tuned with real numbers.

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
data/fish/*.tres            Trout species: habitat, favourite flies, hook-set window, fight
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
