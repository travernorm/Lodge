# REQ-0012: Tall grass that sways

Status: approved by Traver 2026-11-05; built (feel experiment, waiting for Traver to pick a variant and for the clump sprites)

## Problem

The land around the river is a flat green fill. Nothing on the bank reacts to the angler or to the weather, so walking to a spot feels like sliding over a map, and a storm only changes the colour of the screen.

## Player story

As a player, I want to wade through tall bank grass that parts around me and springs back, and to see it bend and ripple in the wind on a stormy day, so that the bank feels alive and I can read the weather from the land as well as the water.

## Feel goals

- **Tall and soft.** Clumps of long, broad, tapered blades that curve over at the tip, taller than the angler's knees, as in Traver's reference: dark green at the base fading to bright green at the tip, overlapping in a dense tuft. The reference also shows a short, flattened version of the same blades, which is the look of grass that has been walked over (variant B).
- **It notices you.** Blades near the angler lean away as they walk through, then spring back over about a second, with a little overshoot. Standing still, the grass settles.
- **The wind is readable.** Calm days have almost no motion, just a faint breath. In a Storm the whole field bends one way and waves of gusts roll across it. Rain sits in between.
- **It never hides the fishing.** Grass grows on the land only, never over the water, the fly or the rise rings. The angler's legs may be hidden in it, the body never.
- **Cheap.** One draw for the whole field, 60 fps on the Deck, works in the web build.

## Scope: a feel experiment with three push variants

Wind is the same in all three. Only the reaction to the angler differs, and Traver plays each and picks one.

| Variant | What you see when walking through |
|---|---|
| **A. Lean** | Blades within about 1 m lean away from the angler while they are close and spring straight again as they leave. Simplest. |
| **B. Part and trail** | As A, but the blades flatten (the reference's short clump) and stay down for a moment after the angler passes, so a short trail shows where they walked, then they stand back up. |
| **C. Rustle** | Blades don't lean far; they shake and shiver as the angler brushes past, like a sound you can see. |

- **Where it grows.** A new `GrassPatch` river feature (like a boulder or a gravel bar) marks an area of bank in metres, with a density. The demo stretch gets a few patches along the near bank and one meadow by the bend. Grass never grows on water or gravel.
- **`GrassLook`** resource, `data/grass_looks/spring.tres` (its own folder, as `data/looks/` holds water looks): clump sprites, blade height in metres, density, base and tip tint, how far blades lean from the angler, spring-back time, and a wind strength per `Calendar.Weather`. Traver tunes it in the Inspector, like the water look.
- **Wind.** A small pure model, `Wind` (`RefCounted`, seeded), turns the current `Conditions` (weather and its `intensity` 0 to 1) into a strength, a direction and gusts. Storm at full intensity is the strongest. Changing the weather with R2 / F2 changes the wind, easing over a few seconds.
- **`GrassView`** draws the whole field as one batch with a shader that bends each blade's top: wind plus the push from the angler. It gets the angler's position through a signal from the river scene, so it doesn't reach into it.
- **Art is texture slots.** The clump sprites come from Traver (PixelLab or Aseprite, on the spring palette). Until they arrive a plain placeholder blade stands in, and the PR says so clearly. No code-painted art is presented as the look.
- **Variant toggle.** The debug overlay gains a Grass view (View / F1 four times). There, R2 / F2 cycles A, B and C instead of the weather looks, and the top-left corner shows the variant and the wind strength.

## Out of scope

Grass that slows walking, scares fish or hides the angler from fish; grass on the far bank of the test screen; seasonal looks (spring only); trees, bushes, reeds and cattails; wind that moves the fly or line; sound; saves.

## Systems touched

| System | Changes? | Depends on the change? | How it's checked |
|---|---|---|---|
| Casting | No | No | playthrough_test unchanged |
| River | Yes: new `GrassPatch` feature, demo stretch gains patches | Grass placement | data_test loads the stretch and every grass look; new grass_test checks no grass lies on water |
| Fishing | No | No | playthrough_test unchanged |
| Weather / Conditions | Read only: `Wind` reads `Conditions` | Wind strength | new wind_test: sunny < rain < storm, seeded gusts repeat |
| Angler / river scene | Emits the angler's position | Grass push | new grass_test: blades near the angler lean, far ones don't, they recover |
| UI and modes | Debug overlay shows the grass variant | | playthrough_test cycles the variants |
| Input | Reuses an existing debug key with the overlay open; no new binding unless Traver wants one | | input parity check |
| Saves | No | | |

`stream_scene.gd` is at 450 of its 451-line R9 cap, so the hookup there must be paid for by moving a few lines out (the bank ground drawing is the natural candidate), not by raising the cap.

## Acceptance criteria

- Grass appears only inside `GrassPatch` areas on land (automated).
- On a Sunny day the wind strength is near zero; Storm at intensity 1 is the maximum; Rain is in between (automated).
- The same seed gives the same gusts (automated).
- Blades within the push radius lean away from the angler and return to rest within the spring-back time once the angler leaves (automated, on the model).
- 60 fps on the Deck with the demo stretch's grass on screen (playtest).
- The browser build shows the grass and the sway (playtest).

## Playtest checks

- Walk through a patch with the left stick and WASD in each variant A, B, C.
- Cycle the weather with R2 / F2 to Storm and back; the field should bend and gust, then settle.
- Cast Short, Middle and Long from inside a patch; the fly and line stay visible.
- Check on the Deck (fps) and in the browser.

## Open questions

1. **Reference.** Answered: Traver uploaded the reference (kept outside the repo, as it isn't licensed for the game). Tall curved blades, plus a short flattened set.
2. **Who makes the clumps?** Answered: Traver is making them in PixelLab (3 or 4 tall clumps, about 8×14 px at 320×200, plus a flattened clump). A placeholder blade fills in until then.
3. **Wind on calm days.** Answered: yes, Sunny and Overcast get a faint breeze; Storm is the strongest.
4. **Resolution.** The game still renders at 320×200 ×4. Sizes here are in metres, so they carry over if that changes to 640×400.
