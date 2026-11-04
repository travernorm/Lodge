# Fly art

Each `<fly id>.png` is one row of 8 square views of a fly, its head (the hook eye) pointing S, SE, E, NE, N, NW, W, SW on screen. `FlyPattern.sprite_sheet` links a fly to its sheet and `FlyView` draws it. The sheets are imported with mipmaps on (see the `.import` files), so they stay clean drawn small: keep that setting for new sheets.

* `parachute_adams.png`: Traver's Parachute Adams sheet (2026-11-03).
* `elk_hair_caddis.png` and `pale_morning_dun.png`: Traver's 8 single-view PNGs (2026-11-03), laid side by side in the order above.

To swap in new art, paint a sheet in the same layout and drop it over the file, or point a fly's `sprite_sheet` at a new one. The single-view originals are in the project files under `art/flies/`.

Before shipping, confirm that the generating tool's terms allow commercial use, and record that here.

All three sheets had their empty margins trimmed (each view cut to the same square around the fly, every painted pixel kept), so the fly fills more of its icon. No pixel was repainted.
