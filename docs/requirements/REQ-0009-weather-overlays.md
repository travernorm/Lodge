# REQ-0009: Weather you can see

Status: review (Traver answered the open questions on 2026-11-04; waiting for the go-ahead to build)

## Problem

Every visit already rolls a weather (Sunny, Overcast, Rain, Snow, Storm) and a time slot (REQ-0007; slot-by-slot weather and `intensity` come from REQ-0008, the weather generator), and the fish react to both. But the screen looks the same in all of them, so the player can't read the day by looking, only from the debug text.

## Player story

As a player, I want to see at a glance that it's a grey dawn, a rainy afternoon or a snowy dusk, so that the river feels alive and I can guess how the fish will behave.

## Feel goals

- Readable in one look, even on the Deck's small screen: you never have to check a label to know the weather.
- The fly, the line and the rise rings stay as easy to see as on a sunny day. Weather sets a mood, it never hides the fishing.
- Calm, not busy. Rain and snow fall softly; a storm is the only loud one.

## Scope: a feel experiment with three variants

All three read the same `Conditions` the fish use, and each adds to the one before. Traver plays them and picks one, and the losers are deleted.

| Variant | What you see |
|---|---|
| **A. Grade** | The whole picture is tinted per weather and per time slot: brightness, colour, saturation, contrast. Overcast is flatter and greyer, dusk is warmer, night is dark blue. One full-screen shader, no art. |
| **B. Grade + falling weather** | A, plus rain streaks, snowflakes, and slanted, heavier rain in a storm, as particles over the river. |
| **C. Grade + falling + on the water** | B, plus the water reacts: rain dimples the surface, slow cloud shadows drift over it when overcast, and lightning flashes the screen in a storm. Done inside the existing water shader. |

- **Intensity.** Particle amount, ripple strength and grade depth scale with the weather's `intensity` (0 to 1) from REQ-0008, so a drizzle and a downpour look different. If the weather changes at a slot, the view cross-fades over a few seconds.
- **`WeatherLook`** resource, `data/looks/weather.tres`: one `WeatherStyle` per weather (tint, brightness, saturation, contrast, particle amount, size, speed, slant, water ripple and cloud strength, flash rate) and a tint per time slot. Traver tunes everything in the Inspector, like the water look.
- **Particle sprites are texture slots.** Traver makes the rain streak, snowflake and splash ring in PixelLab or Aseprite and drags them in. Until then a plain one-pixel streak and dot stand in, and the PR says so.
- **`WeatherView`** node on its own `Weather` canvas layer in `scenes/main.tscn`, above the river and below the HUD and debug layers. It owns the variant and draws only.
- **Debug key: R2 / F2 cycles the weather.** It changes the real day's weather, so the hatch follows it (a rain day brings the rain hatches), but the fish already in the stretch stay as they are. Moving to another location still restocks the fish as today. With the debug overlay open, R2 / F2 cycles the variant instead. The current weather, slot and variant show in the corner while it's being cycled.

## Out of scope

Changing the weather during a visit, wind that moves the fly, sound, seasonal water looks (a spring look is the only one), and saving anything. The weather generator itself is the sibling "Build out the weather generator" work.

## Systems touched

| System | Changes? | Depends on the change? | How it's checked |
|---|---|---|---|
| Casting | No | Draws under the overlay | playthrough_test |
| River | Variant C: two new water shader inputs (rain, clouds), off by default | No | water_view_test |
| Fishing | Emits `conditions_changed(conditions)` (shared with REQ-0008) when it stocks the stretch or the debug key changes the weather; the debug change keeps the fish and recomputes the hatch | WeatherView listens | fishing_test, new weather_view_test |
| UI and modes | New `Weather` canvas layer and `WeatherView` | Debug overlay still on top | playthrough_test cycles weathers and debug views |
| Input | New `debug_weather` action, R2 / F2 | No | controls_test, input drift check, README table |
| Saves | No | No | n/a |

## Acceptance criteria

- Each weather and slot gives the grade written in `weather.tres` (weather_view_test).
- The debug key cycles all five weathers, and with the debug overlay open, the three variants (weather_view_test).
- Cycling the weather changes the day's weather and the active hatch, and leaves the stretch's fish untouched (fishing_test).
- `weather.tres` has a style for every weather and a tint for every slot (data_test).
- Variant A costs one full-screen pass; B and C stay under 400 particles on screen (weather_view_test checks the cap).
- Every existing suite still passes (tools/run_tests.sh).

## Playtest checks

- On DualSense and keyboard: cycle through all five weathers in each variant, cast Short, Middle and Long, and check the fly, line and rings stay readable in Storm and Snow at night.
- Open `data/looks/weather.tres` and drag the sliders with the game running.
- Browser build: rain and snow fall, no shader errors.
- Steam Deck: holds 60 fps in Storm with variant C. Not checked until Traver tries it.

## Open questions

Answered by Traver, 2026-11-04:

1. **Debug key.** Yes, R2 / F2.
2. **Preview or real day?** The weather change is real for the insects (the hatch follows the new weather) but not for the fish. Switching location restocks the fish.
3. **Art.** Plain placeholders are fine for now.

## Architecture review

- **Layers (R1).** `WeatherLook` and `WeatherStyle` are data (layer 1). `WeatherView` is a view (layer 3) and reads `Conditions`, never a clock.
- **One writer (R2).** Fishing still owns `conditions`, so the debug key asks Fishing to change the weather rather than writing it. The variant belongs to `WeatherView` alone.
- **Ledger (R9).** `fishing_controller.gd` is at 613 of its 615-line cap, so the weather change and signal go in a small helper rather than growing that file.
- **Call down, signal up (R3).** Fishing signals `day_stocked`; the stream scene connects it to `WeatherView` and hands `WaterView` the rain and cloud values (variant C). No node reaches a sibling.
- **Typed data (R4, R5).** Styles are typed sub-resources keyed by `Calendar.Weather`, not by strings.
- **Pixels (R11).** Particle speeds and sizes are in metres and converted through `WorldScale` in the view.
- **Web and Deck.** CPU particles and canvas shaders only, which work in GL Compatibility and WebGL2. No new plugins.
- **Hot files.** `scenes/main.tscn` (one layer added), `project.godot` (one action, regenerated by `tools/setup_input_map.gd`), `README.md` (one controls row), `fishing_controller.gd` (one signal), `smoke_test.gd` untouched.
- **Map.** New scripts go in the class index, `data/looks/weather.tres` in section 2 and data_test, and Fishing → WeatherView in the system map.
