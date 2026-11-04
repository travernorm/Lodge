# Angler art

`idle.png` is one row of 8 square 48 px views of the angler (the man in waders, red and black wool jacket, cap), facing S, SE, E, NE, N, NW, W, SW on screen: the same order as the fly sheets. `AnglerView` (`scripts/angler_view.gd`) draws it at half size, his feet at the bottom edge of each cell. It is imported with mipmaps on (see the `.import` file) so it stays clean drawn small: keep that setting.

* `idle.png`: Traver's PixelLab "Idle" rotations (2026-11-04, 48x48, low top-down, 8 directions), laid side by side in the order above. No pixel was repainted or trimmed.

* `walk.png`: Traver's PixelLab walk (2026-11-04, 8 GIFs of 8 frames, one per direction, 68x68 canvases). One row per direction in the order above, 8 frames left to right, each frame cut to the middle 48x48 of its canvas so the feet line up with `idle.png`. Every painted pixel kept, none repainted. `AnglerView` steps the frames with the distance he walks (`WALK_CYCLE_PX` per cycle). The original GIFs are in the project files under `art/angler/walk/`.

To swap in new art, paint a sheet in the same layout and drop it over the file. A cast animation would be a new sheet and a change to `AnglerView`.

Before shipping, confirm that the generating tool's terms allow commercial use, and record that here.
