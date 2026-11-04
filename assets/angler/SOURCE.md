# Angler art

`idle.png` is one row of 8 square 48 px views of the angler (the man in waders, red and black wool jacket, cap), facing S, SE, E, NE, N, NW, W, SW on screen: the same order as the fly sheets. `AnglerView` (`scripts/angler_view.gd`) draws it at half size, his feet at the bottom edge of each cell. It is imported with mipmaps on (see the `.import` file) so it stays clean drawn small: keep that setting.

* `idle.png`: Traver's PixelLab "Idle" rotations (2026-11-04, 48x48, low top-down, 8 directions), laid side by side in the order above. No pixel was repainted or trimmed.

To swap in new art, paint a sheet in the same layout and drop it over the file. Walk or cast animations would be new sheets and a change to `AnglerView`.

Before shipping, confirm that the generating tool's terms allow commercial use, and record that here.
