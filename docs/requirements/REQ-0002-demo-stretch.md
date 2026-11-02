# REQ-0002: A demo stretch of river to explore

Status: approved (Traver, 2026-11-02)

## Problem

The demo is one screen with one riffle, one pool, one boulder and one trout. There's nothing to explore and only one place to cast, so reading the water isn't much of a skill yet.

## Player story

As a player, I want to walk a real-feeling stretch of creek with different kinds of water, so that I learn to read each one and find where the trout are holding.

## Feel goals

* Each kind of water is readable on sight: broken riffle, rock-studded pocket water, a dark cut bank, a swirling eddy, a smooth pool, a glassy tail-out.
* Walking down the bank feels like scouting. You stop, look, pick a spot and cast.
* Trout are where a real angler would look for them, and every lie has a visible tell.
* Fishing in one spot plays exactly as it does today.

## Scope

A fictional freestone stretch (Traver picked layout A, 2026-11-02), about 120 m by 75 m (three screens by three screens) that winds across the map instead of running straight. The river is 16 m bank to bank (Traver, 2026-11-02), so a middle cast covers the near half and the far bank takes a long cast. See the [layout plate](img/REQ-0002-layout.png) and the [layout study](https://claude.ai/artifact/FERiMT8rSgAPnKUsidz7bW).

1. **Head riffle:** wide, shallow and fast, with foam, entering from the left.
2. **Pocket water:** four boulders, each with its own cushion, pocket and seams.
3. **First pool** (head, body, tail): the channel bends down the screen. The pool head has a circulating eddy along the near bank (see the [eddy prototype](img/REQ-0002-eddy.png)) and a fallen log lies along the outside of the bend.
4. **Crossover riffle:** the thalweg crosses from one bank to the other.
5. **Deep cut-bank pool on a hard bend:** the end of the stretch swings hard into the outside bank and turns sharply back up the screen. The fast, deep water hugs the outside bank, which is cut and undercut all along the bend. The inside of the bend is a gravel point bar you can walk out on. This is the deepest water on the stretch and the home of the biggest trout.
6. **Exit run:** the river leaves the top of the map after the bend.

How it works:

* **A `Stretch` resource** holds the layout as data: banks, thalweg depth along the river, rocks, logs and the point bar. That's ARCHITECTURE.md step F. The same file will later feed the solver bake.
* **The river field** handles curving banks, current that follows the bends, and the thalweg pushed to the outside of a bend. It still uses rules for now.
* **The eddy is a real circulation**, not a slow patch:
    * It's built from a stream function, the same maths a solver uses for swirling flow. The water in it goes around in closed loops and never piles up or vanishes.
    * Along the near bank the water runs back upstream. It swings out at the top of the eddy and joins the main current along the eddy line, then curls back in at the bottom.
    * The eddy line is the strongest seam on the stretch.
    * Foam and drifting food get trapped and circle in the eddy, so it shows a slowly turning foam mat.
    * A fly dropped in it drifts upstream, swings out to the eddy line and comes back around. Mending works against that reversed current, just as on a real river.
    * Trout in the eddy face into its current, so they point downstream. That's a real tell for the player.
    * The later solver bake will produce the same thing on its own, and the stamped eddy is the stand-in until then.
* **The camera** scrolls smoothly in both directions (across and up/down) with the angler, so a drifting fly never has to cross a screen cut. Water can run any direction on screen.
* **The angler** walks one bank path along the river, including out onto the point bar. There's no wading yet.
* **Five trout** each take the best free lie, keeping a few metres apart. Bigger fish get the better lies.
* **The read-the-water view** covers the whole stretch and scrolls with the camera.

## Out of scope

* The solver bake (next river step; it will replace the stamped eddy).
* Wading, crossing to the far bank, and casting upstream or downstream from midstream.
* Water levels and seasons, new species, and art beyond the current primitives.
* Saving fish between visits (`Population`, FISH_LOGIC.md).

## Systems touched

| System | Changes? | Depends on the change? | How it's checked |
|---|---|---|---|
| River | Yes: `Stretch` resource, field supports curved banks, bends, logs and an eddy | Drift, fish lies, water drawing, read-the-water view | `river_test` (bend, cut bank, eddy, pockets), `data_test` (stretch data valid) |
| Fishing | Yes: several fish, one per lie, lies chosen over the whole stretch | Bite odds unchanged | `fishing_test`, `playthrough_test` (catch in two different water types) |
| Casting | Only the camera offset (casts work in world space) | Landing point | `cast_test`, `playthrough_test` |
| UI and modes | Camera follow, debug views scroll | | `smoke_test`, screenshots |
| Input | No | | |
| Saves | No | | |

This lands after REQ-0001's fishing step, so everything is already in metres.

## Acceptance criteria

* In the hard bend, the fastest and deepest water runs along the outside (cut) bank, and the point bar side is shallow. Automated.
* Every boulder has a slower pocket behind it and a seam on each side. Automated.
* Water inside the eddy runs upstream along the near bank. Automated.
* A fly dropped in the eddy comes back around near where it started within one loop, and doesn't drift out downstream. Automated.
* The eddy's flow has no sources or sinks (zero divergence, within grid error). Automated.
* The eddy line scores as a strong seam, and trout lies form along it. Automated.
* Foam streaks that enter the eddy circle it instead of passing through. Screenshot.
* Five trout spawn on five different lies, at least 3 m apart, all in water. Automated.
* The playthrough lands a fish in the pocket water and another in the pool. Automated.
* The game stays at 60 fps with the read-the-water view on. Playtest on the Deck.

## Playtest checks

Walk the whole stretch both ways. Find each trout using only the water (read-the-water view off), then check with it on. Cast the cut-bank pool from the point bar. Drop a fly in the eddy and watch it ride back upstream and circle; drift one down the eddy line. Keyboard and DualSense, plus the browser build.

## As built

* `Stretch` resource (`scripts/river/stretch.gd`) and the demo data in `data/stretches/demo_freestone.tres`. `main.tscn` loads it; without a stretch the stream scene falls back to the one-screen test creek.
* `RiverField.build_stretch()` lays the river along a Catmull-Rom centreline. Bends push the thalweg outward from the curvature. Logs slow the water beside them. The eddy is a Gaussian stream-function vortex that turns back upstream along its nearer bank. The build takes about a second when the scene loads.
* The picture shows cut banks (earth) on the outside of bends and point bars (gravel) on the inside, drawn from the same field.
* The angler walks in 2D on dry land and always faces the nearest water. `CastModel.facing_angle` turns the cast, the rod poses and the practice targets, and the left stick still aims right as the angler sees it. The drift's bow and mends follow the local current (`DriftModel.downstream`), so in the eddy you mend against the reversed current.
* Five trout (three redband, a cutthroat and a brook) each take a lie at least 3 m from the others. Trout are drawn facing into the current at their lie.
* The camera smooth-scrolls with the angler and looks a little toward the water. HUD text stays fixed on screen.
* Tests: `river_test` covers the hard bend, every boulder, the eddy (reversed current, a closed loop, zero divergence, the eddy-line seam and lie) and five trout lies. `data_test` validates stretches, `cast_test` and `fishing_test` check casting and mending when the river runs another way, and `smoke_test` plays a catch on the stretch.
* Not yet: bigger fish taking the better lies, a playthrough catch in two different water types, and a Deck fps check.

## Open questions

1. ~~Scrolling or flip-screen?~~ Decided (Traver, 2026-11-02): smooth scrolling.
2. ~~Layout?~~ Decided (Traver, 2026-11-02): freestone A, with a deep cut-bank pool on a hard bend at the end.
3. **Water in any direction:** assumed yes (2D scrolling) since the hard bend turns the river back up the screen.
4. **Trout count:** five, or a different number?
5. **Can the angler reach the far bank?** Recommended: not yet. Near bank and point bar only.
