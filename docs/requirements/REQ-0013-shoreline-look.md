# REQ-0013: A shoreline that matches the water and grass

Status: draft (2026-11-05, waiting on Traver)

## Problem

The water (REQ-0006, PR #55) and the bank grass (REQ-0012) are now textured, lit and moving, but the strip of land between them is still two flat colours painted pixel by pixel in `stream_scene._make_stretch_texture`: a tan gravel band and a brown cut-bank band on the outside of bends, with hard stair-step edges. It reads as a placeholder next to everything around it.

![The shoreline today](img/REQ-0013-shoreline-today.png)

## Player story

As a player, I want the river's edge to look like a real bank, wet stones at the waterline, dry gravel and sand above, an earth cut bank under the grass on the outside of a bend, so that the edge of the water reads at a glance and the whole scene feels like one place.

## Feel goals

- **One picture.** The bank uses the same palette and pixel density as the water and grass, with no hard stair-step edges between them.
- **Readable zones.** From the water out: a thin wet line that is darker than the dry stones, then dry gravel and sand, then a soft, ragged edge where grass takes over. Point bars on the inside of a bend are wide and pebbly; the outside of a bend is a dark earth face with an overhanging grass lip.
- **Calm.** The bank doesn't move. It must not compete with the water or the rise rings for attention.
- **Cheap.** One draw for the bank, baked once per stretch, 60 fps on the Deck, works in the web build.

## Scope

- **`BankView`**: a new view (layer: views, beside `WaterView` and `GrassView`) that draws all the land the stream scene now paints as gravel and cut bank, plus the gravel bars. One quad with a shader, like `WaterView`. It reads the field's existing `shore` and `bend` layers and the `GravelBar` features through `setup`, baked to a texture once, so nothing is simulated live.
- **Texture slots, not code-painted art.** The shader tiles small seamless textures picked per pixel by zone: **wet stones**, **dry gravel**, **sand**, **cut bank earth**, with noise-blended joins and an optional palette snap (the same tricks as the water look). Traver makes the textures in PixelLab or Aseprite on the spring palette. Until they arrive a plain noise placeholder stands in, and the PR says so clearly.
- **`BankLook`** resource in `data/bank_looks/spring.tres`: the four textures, zone widths in metres (wet line, gravel band, grass fringe), the cut-bank threshold on `bend`, tints, edge raggedness, palette snap on or off. Traver tunes it in the Inspector, like the water and grass looks.
- **Two looks to compare, as data:** `spring.tres` (A, soft blended joins) and `spring_crisp.tres` (B, dithered joins, closer to the clear water's B). Picked on the stream scene's `BankView` node; no new toggle.
- **The stream scene stops painting the bank.** `_make_stretch_texture` paints only grass (and the old flat water when the clear water is off). This moves lines out of `stream_scene.gd`, which sits at 449 of its 451-line R9 cap, so the cap goes down.

## Out of scope

Rocks, logs, reeds and cattails on the bank as separate sprites; seasonal looks (spring only); footprints; wet sand that changes with rain or water level; the old non-stretch test screen; walking speed or fish behaviour on gravel.

## Systems touched

| System | Changes? | Depends on the change? | How it's checked |
|---|---|---|---|
| Casting | No | No | `playthrough_test` unchanged |
| River | Yes: new `BankView` and `BankLook`; the stream scene stops painting gravel and cut bank | Water view (unchanged, draws underneath), grass view (grows where gravel isn't; unchanged) | new `bank_view_test`: zones land where the field says (wet next to water, cut bank only on outside bends, no bank pixels over water); `data_test` loads every bank look; `water_view_test`, `grass_test` unchanged |
| Fishing | No | No | `playthrough_test` unchanged |
| Weather look | No: the grade already tints everything drawn below it | | `weather_view_test` unchanged |
| UI and modes | No | | |
| Input | No | | |
| Saves | No | | |

## Acceptance criteria

- Every land pixel the stream scene used to paint gravel or cut bank is drawn by `BankView`, and no `BankView` pixel lies on water (automated).
- The wet line sits against the water, and the cut bank only appears where `bend` says outside of a bend (automated).
- The look comes only from `BankLook` data; swapping the `.tres` changes it with no code change (automated: both looks load and render).
- `stream_scene.gd` gets shorter and its R9 cap goes down (automated).
- All suites pass in `tools/run_tests.sh`.
- In-engine screenshots of a riffle, the bend and a point bar, with Traver's textures if they're in, in the PR (playtest).

## Playtest checks

Walk the whole near bank and the bend on keyboard and DualSense. Check the wet line under the clear water's foam, the cut bank under the grass on the bend, and the point bar. Cycle the weather (R2 / F2) to see the bank under rain and storm. Check the browser build (rendering changed). Not checked on the Deck unless Traver does.

## Open questions

1. **Textures:** will Traver make the four bank textures (wet stones, dry gravel, sand, cut bank earth) in PixelLab, or should a placeholder go in first and the textures follow? Suggested size: 64×64 seamless, top-down 3/4, spring palette.
2. Should the cut bank show a visible vertical earth face (a lip with roots and shadow), or stay a flat top-down dark band?
3. Two looks (A soft, B crisp) or only one?
