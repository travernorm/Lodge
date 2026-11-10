# REQ-0015: Living light, storms and textured rain and snow

Status: approved by Traver 2026-11-09; built (not yet played on device, Deck or browser)

## Problem

Weather you can see (REQ-0009) gave each weather and time slot one fixed colour grade. The picture holds still: the light at minute ten of a visit is the light at minute one. Cloud shadows, lightning and falling rain exist only in the trial's versions B and C, which Traver hasn't seen on screen, and they are plain: the shadows are a flat darkening, lightning is a white flash over everything, rain is a one-pixel line and snow a one-pixel dot.

## Player story

As a player, I want the light on the river to move, with cloud shadows sliding over the water, the afternoon going gold and then blue, and a storm that builds, cracks with lightning and passes, so that the river feels like a real place and I can read the sky while I fish.

## Feel goals

- **The light is never still, and never busy.** Change is slow enough that you notice it after a minute, not every second. Lightning is the only sudden thing.
- **Warm light, cool shadow.** Sun patches lean warm and cloud shadow leans blue, instead of the whole screen just getting darker.
- **A storm has a shape.** It darkens and the wind picks up, the rain comes, lightning flickers, then it eases.
- **Fishing stays readable.** The fly, line and rise rings are as easy to see in a storm at dusk as at sunny noon.
- **Rain and snow have depth.** Near drops are bigger and faster than far ones, rain splashes where it lands, and snow drifts.

## Scope

One look, not a three-way trial. The A / B / C versions from REQ-0009 are retired and their best parts become the base that this builds on.

### 1. Light that follows the time of day

- A new pure model, `SkyLight`, turns a **time of day** (a number running from dawn to night, not just the slot) plus the weather and its intensity into the light: a sun colour, a shadow colour, how bright, how much cloud, how fast the clouds move.
- The look holds one **light key** per slot (Dawn, Morning, Noon, Afternoon, Dusk, Night), each with a highlight tint, a shadow tint and a brightness (saturation and contrast stay with the weather). `SkyLight` blends smoothly between neighbouring keys, so late afternoon slides into dusk instead of snapping.
- Highlights and shadows are tinted separately (bright pixels take the sun colour, dark pixels the shadow colour). This is what gives gold light with blue shadows at dusk and silver-blue moonlight at night.
- Where the time of day comes from is open question 1. The light only reads one number, so it works the same whichever answer is chosen.

### 2. Clouds that pass over

- Cloud shadows are a slow, soft-edged pattern fixed to the ground (they stay put as the camera moves) and drift with the `Wind` model's direction, faster as the wind rises.
- **Cover** comes from the weather: Sunny has a few well-separated clouds with crisp, clearly moving shadows; Overcast is nearly solid, so the light is flat and the shadows almost vanish; Rain is solid and darker; Storm is heavy, dark and fast.
- Cover also **breathes** over a minute or two (seeded, R8), so a sunny day has stretches of full sun and stretches where a big cloud dims the whole reach. This is the "light shifts as clouds pass" moment.
- In a cloud's shadow the picture takes the shadow tint and loses a little saturation; in sun it takes the highlight tint. Shadow edges are stepped (sun, half shadow, full shadow) so they stay pixel-crisp and don't shimmer as they move.
- The cloud shadow falls on the water the same way, so the bright riffles dim under a cloud. (As built: this comes from the one full-screen light pass; the water shader itself is unchanged.)

### 3. Storms with lightning

- **Build and pass.** When the weather turns to Storm the cloud cover, darkness and wind ease in over about ten seconds (the wind already eases, REQ-0012) and ease out again when it ends.
- **A strike is light, not a white screen.** The camera looks down, so there is no sky to draw a bolt in. A strike is two to four quick flickers (each 40 to 90 ms) followed by a half-second fade. During a flicker the picture switches to a cold, high-contrast grade: highlights jump to blue-white, shadows stay dark, cloud shadows vanish. The scene is lit, not erased, so you can still see the fly.
- **Near and far.** Most strikes are far (a dim flicker). About one in five is near (bright, and the light comes from one side of the screen). Strikes per minute scale with the storm's intensity.
- **Afterglow.** For a second after a near strike the picture is slightly darker than before, as if your eyes were adjusting.
- **Flash safety.** Brightness is capped, flickers never come faster than three a second, and the look has a `flash_strength` slider that goes to zero. A player-facing "reduce flashes" setting arrives with the game menu.
- Strike timing comes from a seeded model (`LightningModel`), so tests can play a storm back exactly and thunder can follow it when sound arrives.

### 4. Textured rain and snow

- **Sprites instead of lines and dots.** Each weather style gets a small sprite sheet per kind: rain streaks (4 variants, each at 4 leans so wind can slant them without rotating pixels), snowflakes (4 variants, small to large) and a rain splash (4 frames). They are in `assets/weather/`.
- **Two depths.** A far layer (smaller, slower, dimmer, more of them) and a near layer (bigger, faster, fewer). Still under the 400 cap in total.
- **Rain lands.** Drops end in a tiny splash ring where they land, on top of the dimples the water shader already draws.
- **Snow drifts.** Flakes sway on their own phase and lean with the wind; big flakes fall slower.
- **Gusts.** Slant and speed follow the `Wind` model, so a storm's rain comes in sheets with the same gusts that move the grass.
- **Wet ground.** In rain the bank and gravel darken and deepen slightly (a `wetness` number to the bank shader) and dry out over a minute afterwards.
- The sprites were made by Claude, a few pixels each in palette colours (question 3). The PixelLab briefs in the appendix remain for when Traver wants to replace them.

### Tuning

Everything above is a field on the weather look (`data/weather_looks/default.tres`), tuned live in the Inspector as today. R2 / F2 still steps the weather. With the debug overlay open, R2 / F2 instead moves the time of day on half a slot, and in a storm also strikes, so every light can be seen without waiting. `tools/capture_weather.gd` saves a still of any weather and time.

## Out of scope

Sound (thunder, rain), lightning sending the player off the water, wind moving the line or fly, snow settling on the ground, sprites casting long sun shadows, lantern and window lights, seasonal light sets, saving anything. A real game clock is out of scope unless Traver picks it in question 1.

## Systems touched

| System | Changes? | Depends on the change? | How it's checked |
|---|---|---|---|
| Casting | No | Draws under the weather layer | playthrough_test |
| River | Bank shader and `BankView.set_wetness`: `wetness`. `GrassView` emits `wind_blew` | WeatherView takes the wind | bank_test, grass_test, weather_view_test |
| Fishing | No (question 1, option B would add a clock that changes the slot) | Emits `conditions_changed` as today | fishing_test |
| Conditions | New `SkyLight` and `LightningModel` models; `WeatherLook` and `WeatherStyle` gain fields; `WeatherMix.Version` removed; new `WeatherFallView` | WeatherView, WaterView, BankView | new sky_light_test, lightning_test; weather_view_test updated |
| UI and modes | Debug overlay open: R2 / F2 scrubs the time of day | No | playthrough_test |
| Input | No new action | No | input drift check |
| Saves | No | No | n/a |

## Acceptance criteria

- The light at a slot's midpoint equals that slot's key, and halfway between two slots it is their even blend (sky_light_test).
- The same seed gives the same cloud cover over time and the same strike times (sky_light_test, lightning_test).
- No strike has flickers closer than 1/3 s apart or brighter than the cap, and `flash_strength` 0 gives no flash (lightning_test).
- A storm's cover, darkness and strike rate rise with intensity; Sunny and Overcast never strike (sky_light_test).
- Never more than 400 drops or flakes on screen, both layers together (weather_view_test).
- `default.tres` has a light key for every slot and a style for every weather (data_test).
- Every existing suite still passes (tools/run_tests.sh), with the version-trial tests replaced, and the PR says so.

## Playtest checks

- DualSense and keyboard: step through all five weathers, scrub the day from dawn to night in each, trigger near and far strikes. Cast Short, Middle and Long in a storm at dusk and at night: the fly, line and rings stay readable.
- Sit on a sunny day for two minutes and watch clouds pass.
- Drag the look's sliders with the game running.
- Browser build: no shader errors, rain and snow fall.
- Steam Deck: 60 fps in a full storm. Not checked until Traver tries it.

## Open questions

1. **What moves the time of day?** Answered by Traver, 2026-11-09: **A, look only.**
   - **A. Look only (chosen).** During a visit the light drifts from the start of its slot to the end over a set time (say ten minutes) and holds there. Nothing about the fish or hatch changes.
   - **B. A real clock.** The day advances while you fish and crossing into the next slot changes the hatch and fish activity. This is the "Clock" other REQs have deferred; it touches Fishing and needs its own REQ, built before or after this one.
2. **Retire versions A / B / C** and make the full look the only one? Recommended: yes. Traver, 2026-11-09: go with the recommendations.
3. **Who makes the rain and snow sprites?** Traver, 2026-11-09: Claude makes them. They are a few pixels each, placed by `tools/make_weather_sprites.py` in palette colours, and each is a slot Traver can swap.
4. **Lightning as light only**, with no bolt drawn? Recommended: yes, since the camera looks down. A bolt reflected in the water could be added later. Traver, 2026-11-09: go with the recommendations.

Found while building, not changed here: the fly box, catch count and coaching text are drawn under the weather layer, so they dim at night and in a storm along with the river. Moving them above the light is a small follow-up if Traver wants it.

## Architecture review

- **Layers (R1).** `SkyLight` and `LightningModel` are pure models (`RefCounted`, layer 2) beside `Wind` in `scripts/conditions/`. `WeatherLook` and `WeatherStyle` are data. `WeatherView` stays a view and only paints what the models say.
- **One writer (R2).** `WeatherView` owns its `SkyLight` and steps it. The time of day has one writer: the view's own visit timer under option A, the clock under option B.
- **Call down, signal up (R3).** `WeatherView` emits `ground_wet`, connected in `main.tscn` to `BankView.set_wetness`, the same way `rain_on_water` reaches the water. The wind keeps its one owner (`GrassView`), which emits `wind_blew`, connected to `WeatherView.set_wind`. No sibling reads.
- **Seeded randomness (R8).** Cloud breathing and strikes use seeded RNGs.
- **Metres (R11).** Cloud size and drift, fall speed and sprite sizes are in metres or seconds in the models and converted through `WorldScale` in the view.
- **Line caps (R9).** The falling layers moved to a `WeatherFallView` child, so `weather_view.gd` went from 244 lines to about 220. No ledger entry changes.
- **Web and Deck.** Still one full-screen pass plus sprites drawn in batches; canvas shaders only, no real-time lights, no GPU particles.
- **Hot files.** `scenes/main.tscn` (two signal connections), `README.md` (the R2 / F2 row and two tool lines). `project.godot`, `fishing_controller.gd` and `smoke_test.gd` untouched.
- **Map.** New scripts are in the class index; WeatherView to BankView and GrassView to WeatherView are in the system map.

## Appendix: PixelLab briefs for rain and snow

Per [ART_GUIDE.md](../ART_GUIDE.md). These are drawn pixel for pixel on screen (not at half size), so generate at these sizes. Lineless, flat shading, transparent background, palette forced to `lodge-spring.gpl`, using `foam`, `foam2` and `wat4` only.

| Sheet | Size | Prompt |
|---|---|---|
| Rain streaks | 4 cells of 8x16 in a row | `single thin falling raindrop streak, slightly slanted, pale blue-white, transparent background, pixel art, no text` (4 variants: short, long, faint, doubled) |
| Rain splash on land | 4 frames of 8x8 in a row | `tiny raindrop splash on the ground seen from above, 4 frame animation from impact to gone, pale blue-white, transparent background, pixel art, no text` |
| Snowflakes | 4 cells of 8x8 in a row | `single small soft snowflake seen from above, white, transparent background, pixel art, no text` (4 variants from 2 px to 6 px across) |
