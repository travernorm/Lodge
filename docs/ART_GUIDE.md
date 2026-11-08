# Art guide

How Lodge gets good art without anyone drawing by hand. Traver generates and picks; Claude prepares, cleans, imports, wires and shows the result in the real engine. Every art thread follows the checklist at the end.

Read with [TOOLING.md](TOOLING.md) (how to tune the looks in the Inspector) and [ARCHITECTURE.md](ARCHITECTURE.md) (art is drawn by views, tuned in `.tres` looks, never decided in models).

## 1. The pipeline

```
Brief (Claude)  ->  Generate (Traver, PixelLab)  ->  Pick (Traver)
   ->  Clean + check (Claude, in code, no repainting)  ->  Import + wire (Claude)
   ->  In-engine screenshot (Claude)  ->  Tune in the Inspector (Traver)
```

* **Brief.** Claude writes the exact PixelLab settings and prompt from section 4, with the size from section 3, before Traver opens PixelLab.
* **Generate.** Traver runs it and makes 4 or more candidates. Generating is cheap; picking is where taste goes in.
* **Pick.** Traver picks one, or says what is wrong in words ("too saturated", "hat too big"). Claude turns that into the next prompt.
* **Clean and check.** Claude snaps to the palette, hardens alpha, slices and aligns (section 5). Claude never repaints or invents pixels. If an asset needs fixing by hand, it goes back to PixelLab (inpaint) instead.
* **Import and wire.** Godot import settings from section 6, a `SOURCE.md` entry, and the slot in a look `.tres` so Traver can swap it later without code.
* **Show.** Only real in-engine screenshots (`tools/capture_screenshot.gd` under `xvfb-run`, or a small capture script for the view). Never a Python or hand-built mockup presented as the look: Traver rejected those (PR #41). If something is a placeholder, say so before showing it.

## 2. Art direction

* **Cabin core, PNW, a little uncanny.** Warm, quiet and solitary by day; mist, deep shade and a hint of mystery at dusk and night (Bigfoot tracks, old trail markers, lights in the trees). The mystery comes from light and fog, not from monsters.
* **View.** Low top-down, three-quarter, for everything on the map. Side-on only for close-ups (the fly box, a caught fish card, portraits).
* **Light.** One light direction for the whole game: from the top left. Shadows fall down and to the right. Ask for it in every prompt.
* **Outline.** Characters and props: a selective dark outline using `outline` (18 22 27), lighter where light hits. Ground textures, water and tiles: no outline.
* **Shading.** Medium shading, medium detail. Highly detailed AI output turns to mush when shrunk.
* **Colour.** Everything snaps to the season palette (section 3). Accents (`jacket_d`, `lupine`, `pink`, `balsam`) are rare and mark things worth looking at: the angler, a fly, a flower that hints at a hatch.
* **Water and land are drawn by shaders from river data**, not painted as maps. PixelLab makes the textures and tiles that the shaders and tile layers lay down; a PixelLab "map" is concept art only.

## 3. Sizes, scale and palette

### Scale

The game draws at **320x200, 8 px per metre** today (`scripts/world_scale.gd`). The planned move is **640x400 at 16 px per metre** (x2 on the Deck). **Author all art at 16 px per metre now**, so nothing is redrawn when the resolution doubles. Until then, views draw it at half size with mipmaps (as `AnglerView` and `FlyView` do), and the switch only changes a draw size and the import setting.

| Asset | Canvas (px) | Notes |
|---|---|---|
| Angler, NPCs | 48x48 | About 1.8 m tall = ~29 px of figure at 16 px/m, plus room for hat and rod hand. 8 directions. Feet on the same baseline in every cell. |
| Walk / cast / fight frames | 48x48 per frame | Same canvas and baseline as idle. 6 to 8 frames per direction. |
| Water, gravel, sand, wet stones | 64x64 seamless | 4 m square. Must tile on all four sides (section 5). |
| Bank face strip | 64x16 (or 128x16) | Tiles left to right only. Grass lip top, earth and roots middle, mud bottom. |
| Shore transitions (Wang / terrain) | 16x16 per tile | One tileset per pair of grounds, e.g. grass over gravel. |
| Grass clumps, reeds, flowers | 16x16 to 32x32 | Base at the bottom edge. 3 to 6 variants per kind so repeats don't show. |
| Rocks, logs, stumps | 16x16 to 64x32 | Base at the bottom edge, shadow inside the canvas, down-right. |
| Trees | 64x96 to 96x128 | Trunk base centred at the bottom. |
| Cabin, lodge, buildings | 128x128 to 192x160 | One building per image. |
| Flies on the water | 48x48 per view, 8 views | Order S, SE, E, NE, N, NW, W, SW, hook eye at the head. |
| Fly box / caught fish close-ups | 32x32 fly, 64x32 to 96x48 fish | Side-on. |
| Portraits | 64x64 | Chest up, facing right. |
| UI icons | 16x16 or 24x24 | Readable at 1x. Text in the game is at least 8 px (16 px at 640x400). |

Always generate at the **final** size, or at an exact whole multiple and shrink with nearest neighbour. Never resize by a fraction.

### Palette

`art/lodge-spring.gpl` in the project files is the spring palette: 27 colours named by role (`wat0` to `wat4`, `foam`, `fir0`, `grass0` to `grass4`, `soil0`, `soil1`, `rock0` to `rock2`, `grav1`, `grav2`, `skin`, `hat`, `jacket_d`, accents, and `outline`). Load it in Aseprite and give it to PixelLab as the colour palette for every generation.

* Other seasons get their own `.gpl` with the **same names in the same order**, so a season change can be a palette swap (a shader that maps spring colours to autumn ones) instead of new art.
* An asset may use only palette colours after cleanup. If a generation needs a colour the palette lacks, that is a palette change: propose it to Traver, don't sneak it in.

## 4. PixelLab

PixelLab's terms (checked 2026-11-08, [pixellab.ai/termsofservice](https://www.pixellab.ai/termsofservice)) say you own what you make and may use it commercially; the one limit is not using outputs to train other models. Record the tool and date in each folder's `SOURCE.md`.

### Which tool for which asset

| Asset | PixelLab tool |
|---|---|
| Angler, NPCs, animals | Character creator, 8 directions, then its animate tool (walk, idle, cast) |
| Flies | Create image for one view, then Rotate to make the 8 directions from it |
| Seamless ground and water | Create image with the "tileable" option, or Tileset (top-down) when two grounds must blend |
| Shore and path transitions | Tileset (top-down Wang tiles): lower ground + upper ground + transition |
| Props, trees, buildings | Create image (Bitforge) with a style image |
| Fixing one detail | Inpaint on the picked image (never repaint by hand) |

### Settings for every generation

* **Style image:** our own approved art, never someone else's picture. Use `assets/angler/idle.png` (south view) for characters and props, a current water or bank tile for ground. This is what keeps assets looking like one game.
* **Palette:** `lodge-spring.gpl` (or the season's palette), forced.
* **View:** low top-down (close-ups: side).
* **Outline:** selective outline for characters and props, lineless for ground and tiles.
* **Shading:** medium. **Detail:** medium.
* **Size:** from the table in section 3.
* **Seeds:** note the seed of every picked image in `SOURCE.md`, so variants can be made later from the same start.

### Prompt templates

Fill in the `<...>` parts. Keep the fixed tail; it is the house style.

Fixed tail (append to every prompt):
> `, pixel art, cabin-core Pacific Northwest, muted natural colours, light from the top left, soft shadow down and to the right, clean readable silhouette, no text`

* **Character:** `<age> <person> wearing <clothes>, <one distinguishing detail>, standing relaxed, full body` + tail.
  Example: `old fishing guide wearing a waxed canvas jacket and wool beanie, grey beard, standing relaxed, full body`.
* **Animation (from a picked character):** `<action> loop, <n> frames, feet planted` e.g. `overhead fly cast, rod back then forward, 8 frames, feet planted`.
* **Fly (one view, then rotate):** `<fly name> dry fly seen from above floating on water, <body colour> body, <wing> wing, <hackle> hackle, hook eye pointing up` + tail.
* **Ground texture:** `seamless top-down texture of <ground>, <scale cue>, evenly lit, no single object stands out` + tail.
  Example: `seamless top-down texture of wet river stones, fist-sized rounded stones, evenly lit, no single object stands out`.
* **Transition tileset:** lower `<ground>`, upper `<ground>`, transition `<what the edge looks like>`, e.g. lower `river gravel`, upper `short meadow grass`, transition `grass roots spilling over gravel`.
* **Prop:** `<object>, <material and age>, sitting on the ground, shadow down right` + tail, e.g. `fallen pine log, moss on top, bark peeling`.
* **Building:** `<building>, <material>, <one story detail>, three-quarter top-down view` + tail, e.g. `small 1970s log cabin, cedar shake roof, porch with a rocking chair and a lantern`.
* **Close-up fish (side):** `<species> side view, <markings>, <colours>, facing right, mouth closed` + tail, e.g. `redband rainbow trout side view, crimson stripe and black spots, olive back, facing right`.

**Ask for what you want, not what you don't.** "Evenly lit" works better than "no harsh shadows". When an output is close, change one setting at a time (seed, then detail, then the prompt).

### PixelLab from Claude directly (optional)

PixelLab runs an MCP server (`https://api.pixellab.ai/mcp`, setup at pixellab.ai/vibe-coding) with tools to create a character, animate it, make a top-down Wang tileset and make isometric tiles. Connected with Traver's API token, Claude could generate batches of candidates itself and Traver would only pick. That spends Traver's PixelLab credits and needs Traver to set it up; it's Traver's call.

## 5. Cleanup and checks Claude does in code

Only these steps. None of them paints a new pixel; each either removes, snaps or moves what PixelLab made.

1. **Find the true pixel size.** AI output is sometimes drawn at 2x or 3x. Detect the block size and shrink by that whole number, nearest neighbour.
2. **Harden alpha.** Every pixel fully opaque or fully clear (threshold at 50%). Soft edges blur when the game scales.
3. **Snap to the palette.** Map each colour to the nearest palette colour in a perceptual space (OKLab), not raw RGB, which turns greens grey. Report how far the worst colour moved; if many moved far, the generation is off-palette and goes back to PixelLab instead.
4. **Remove orphans.** Single opaque pixels with no opaque neighbour, and stray background specks.
5. **Align.** Feet or base on the same baseline in every frame and direction, horizontally centred. Trim nothing that is painted.
6. **Slice and lay out.** Into the sheet layout the view expects: one row per direction in the order S, SE, E, NE, N, NW, W, SW, frames left to right, equal square cells.
7. **Seam check (textures).** Tile the image 3x3 and compare the edge rows and columns; any texture that shows a seam goes back to PixelLab or uses its tileable option, rather than being blended by hand.
8. **Read check.** Render the asset at its in-game size (today half size) over the real background in Godot and look: does the silhouette read? Too much detail is the usual failure.
9. **Record.** Add a line to the folder's `SOURCE.md`: what it is, who made it, tool, date, seed, and every step above that changed it.

Keep originals untouched in the project files under `art/<kind>/`; the repo gets only the cleaned version in `assets/<kind>/`.

## 6. Godot 4.3 import and drawing

Project settings already set the right defaults: nearest filtering (`default_texture_filter=0`), `snap_2d_transforms_to_pixel=true`, integer stretch of a 320x200 viewport, GL Compatibility. Keep them.

Per texture (the `.import` file, or the Import dock):

* **Compress mode: Lossless.** Never VRAM compression for pixel art.
* **Mipmaps: off** for art drawn 1:1. **On** only for art drawn smaller than authored (today the angler and flies, with `TEXTURE_FILTER_LINEAR_WITH_MIPMAPS` on the view). Turn these off again when the game moves to 640x400 and they draw 1:1.
* **Fix alpha border: on.**
* **Repeat:** seamless textures sampled by a shader set `repeat_enable` on the sampler (`uniform sampler2D tex : repeat_enable, filter_nearest;`) or `texture_repeat` on the node.

Drawing:

* Only whole-number scales and positions. Rotating pixel art (except the 8-direction sheets, which are pre-drawn) breaks it.
* Sprite sheets: `Sprite2D` with `hframes`/`vframes`, or `AtlasTexture` regions; animations in a `SpriteFrames` resource when a view needs them.
* Transition tiles: a `TileSet` with a terrain set (match corners and sides) on a `TileMapLayer`, so Godot picks the right tile from the ground under each cell.
* Camera: move the camera in whole pixels; smoothing that leaves sub-pixel offsets makes sprites shimmer.
* Draw order: y-sort by the base of each sprite, which is why every prop's base sits on the bottom edge of its canvas.

## 7. Shaders, light and mood

Today's shaders: `shaders/water.gdshader` (WaterView), `shaders/bank.gdshader` (BankView), `shaders/weather_grade.gdshader` (WeatherView), plus the grass in GrassView. Each is tuned through a look `.tres` (`data/looks/`, `data/bank_looks/`, `data/grass_looks/`, `data/weather_looks/`). New effects follow the same pattern: the shader draws, a look resource holds every number and texture, and Traver tunes it live in the Inspector.

Rules for every shader:

* `shader_type canvas_item`, and only what WebGL 2 supports (the web build and GL Compatibility).
* **Stay on the pixel grid.** Snap the coordinates you sample with to whole pixels (`floor(px) / size`) so effects move a pixel at a time, never smear.
* **Stay in the palette.** Blend between textures with a dither (ordered Bayer or noise threshold) instead of mixing colours, so every on-screen colour is still a palette colour. The water's `dither` slider already works this way.
* Animate with `TIME` or a uniform, and cap the motion: slow movement reads as calm.

Techniques by subject:

* **Water.** Texture per pixel chosen by depth and speed from the river field, scrolling along the flow (flow mapping with two phases that cross-fade so it never visibly resets), foam where the water is fast, dimples for rain. Rise rings and the fly's wake are small sprites on top, not shader work.
* **Foliage.** Sway the top of each grass or reed sprite with a wind uniform and a per-clump phase, base fixed; push away from the angler. Trees sway only their crown sprite and only a pixel or two.
* **Weather.** Colour grade per weather and time of day (today's `weather_grade`). For rain and snow use `CPUParticles2D` (the safe choice on Compatibility and the web) with 1 to 2 px streaks; cloud shadows as a slow noise mask.
* **Light.** Skip real-time 2D lights where possible; they cost on the Deck. Fake light instead: an additive glow sprite for a cabin window or lantern, a warm grade at dawn and dusk, a cold blue grade at night with the glow sprites left bright. A gradient map from the palette (dark to light ramp per hue) keeps graded colours in palette.
* **Mood.** Morning mist as a slow scrolling noise band over the water, thinning toward noon. God rays as a few soft additive sprites through the trees at dawn. Fireflies at dusk in summer (tiny particles). At night most of the screen goes dark blue, and only lanterns, the moon on the water and the odd unexplained light in the trees stay bright: that is where the Dredge-like mystery lives.

## 8. Checklist for every art thread

1. Name the asset, its size from section 3, and where it shows in game.
2. Write the PixelLab brief: tool, settings, style image, palette, prompt from the templates.
3. Traver generates candidates and picks one (or says in words what to change).
4. Save the originals to the project files under `art/<kind>/`.
5. Clean up in code (section 5): pixel size, alpha, palette snap (report the worst move), orphans, baseline, sheet layout, seams.
6. Import with section 6 settings; record the source in `SOURCE.md`.
7. Put it in a look `.tres` slot (or the data field that points at it) so Traver can swap it without code.
8. Take an in-engine screenshot at the real size over the real background. No mockups. Say "placeholder" if any part of it is.
9. Run `tools/run_tests.sh`; if the asset needed new code, follow the usual track (small fix or REQ).
10. Open the PR with the screenshot and how to tune it in the Inspector. Traver decides.
