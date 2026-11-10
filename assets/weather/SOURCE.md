# Weather sprites

Rain, snow and splash sheets for the weather look (REQ-0015), used by `data/weather_looks/default.tres` and drawn pixel for pixel by `WeatherFallView`.

* `rain.png`: 16 px cells, 4 drops across (short and faint to long and bright; the far layer uses the first two, the near layer the last two) by 4 leans down (0, 12, 24 and 36 degrees to the right; the game mirrors them for wind from the right).
* `snow.png`: 8 px cells, 4 flakes in a row, small to large.
* `splash.png`: 8 px cells, 4 frames in a row of a drop landing, seen from above.

Made by Claude on 2026-11-09 with `tools/make_weather_sprites.py`, which places each pixel by hand in three spring palette colours (`foam`, `foam2`, `wat4`). Traver agreed to this for these few-pixel sprites; larger art still follows docs/ART_GUIDE.md. No outside source or licence.

To change one, edit the shapes in the tool and run it, or drop a PNG in the same layout over the file. A different layout works too: set the variants, slant rows and frames on the weather style.
