# REQ-0007: 640x400 resolution

Status: review (Traver decided on 2026-11-03 to double the resolution; this REQ covers how)

## Problem

At 320x200, the art Traver is making, such as the PixelLab water textures and the concept art, has to be shrunk so far that it loses its detail. The art is drawn at roughly 2 to 3 times our screen density.

## Player story

As a player, I want the river and the angler drawn with enough detail to look like the concept art, while it still reads as pixel art.

## Feel goals

- Same framing as now: one screen is still 40 m by 25 m, so casting distances, walking and the camera feel the same.
- Still crisp pixel art: integer 2x scale to the Deck's 1280x800, with no blur.
- Text stays readable on a 7-inch screen: at least 16 px at the new size, which is the same physical size as 8 px today.

## Scope

1. **Viewport:** `project.godot` becomes 640x400, with integer stretch, and the window stays 1280x800. This is a `tools/setup_input_map.gd`-style edit; regenerate the file, don't hand-edit it.
2. **World scale:** `WorldScale.PX_PER_M` goes from 8 to 16, so every model in metres is unchanged. `stream_scene.VIEW` and the units docs are updated to match.
3. **Pixel constants:** every hard-coded pixel size that isn't in metres gets doubled or moved to metres. That covers the rod length, look-ahead, walking speed, rock and log line widths, the angler drawing, rise rings, and the debug overlay lanes.
4. **HUD and text:** font size 8 becomes 16 everywhere (about 20 `draw_string` calls). Panel boxes and offsets are doubled. This is also the natural time to switch to a real pixel font at 16 px, which is the small fix from the visuals plan.
5. **Tests:** `units_test` and `data_test` expectations are updated for 16 px/m. A new test checks that the viewport is 640x400 and that `PX_PER_M` is 16.

## Out of scope

- New art (REQ-0006 and later).
- Changing how much river fits on screen (we keep 40 x 25 m).

## Systems touched

| System | Changes? | Depends on the change? | How it's checked |
|---|---|---|---|
| Casting | Pixel constants, cast HUD text | Yes | Playthrough: cast Short, Middle, Long; units_test |
| River | Drawing scale, streaks | Yes | river_test, playthrough |
| Fishing | HUD text and boxes | Yes | playthrough catch |
| UI and modes | All text, practice mode, debug views | Yes | Cycle every debug view and practice mode |
| Input | No | No | input drift check |
| Saves | No (metres only) | No | n/a |

## Acceptance criteria

- With the same inputs, the cast distances, drift and catch outcomes match today's exactly, because the models are in metres (existing tests pass unchanged).
- The viewport is 640x400, and `PX_PER_M` is 16 (test).
- No text is drawn below 16 px (test: search for draw_string font sizes).
- 60 fps on the Deck, and the web build runs.

## Playtest checks

Cast Short, Middle and Long; land a fish; strike at nothing; reel in; switch practice mode; cycle the debug views. Check that the text reads on the Deck and in the browser.

## Engineering review

- **Hot files:** `project.godot`, `fishing_controller.gd`. Keep the edits mechanical, and check open PRs #37 and #38 for pixel assumptions before merging.
- **Performance:** four times as many pixels. The water texture bake doubles in each direction (`_make_stretch_texture` goes from about 960x600 to 1920x1200 for the demo stretch). Check load time on the Deck. If it's slow, bake at 8 px/m and draw it scaled 2x.
- **Web:** fine at 640x400. The canvas is still 1280x800.

## Open questions

1. Is keeping the same 40 x 25 m view correct? The alternative is keeping 8 px/m and showing four times as much river at the same detail as today.
