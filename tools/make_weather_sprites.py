#!/usr/bin/env python3
"""Writes the rain, snow and splash sprite sheets in assets/weather/ (REQ-0015).

These are a few pixels each, placed by hand below in three colours of the
spring palette (foam, foam2, wat4). Run from the repo root:
    python3 tools/make_weather_sprites.py
Needs Pillow. Re-import in Godot afterwards.
"""
import math
from PIL import Image

FOAM = (233, 246, 250, 255)
FOAM2 = (195, 229, 238, 255)
WAT4 = (124, 192, 220, 255)
OUT = "assets/weather/"

# Rain: 4 drops across (short and faint to long and bright; the game's far
# layer uses the first two, the near layer the last two), 4 leans down
# (0, 12, 24 and 36 degrees to the right; the game mirrors them for the left).
CELL = 16
RAIN = [
    [FOAM2, WAT4, WAT4],
    [FOAM2, FOAM2, WAT4, WAT4, WAT4],
    [FOAM, FOAM, FOAM2, FOAM2, FOAM2, WAT4, WAT4, WAT4],
    [FOAM, FOAM, FOAM, FOAM2, FOAM2, FOAM2, FOAM2, WAT4, WAT4, WAT4, WAT4],
]


def rain_sheet():
    img = Image.new("RGBA", (CELL * 4, CELL * 4), (0, 0, 0, 0))
    for row in range(4):
        lean = math.radians(12 * row)
        dx, dy = math.sin(lean), math.cos(lean)
        for v, drop in enumerate(RAIN):
            # Head (first colour) leads, low in the cell; the tail trails behind it.
            n = len(drop)
            hx = CELL // 2 + dx * (n - 1) / 2
            hy = CELL // 2 + dy * (n - 1) / 2
            for i, col in enumerate(drop):
                x = int(math.floor(hx - dx * i + 0.5))
                y = int(math.floor(hy - dy * i + 0.5))
                img.putpixel((v * CELL + x, row * CELL + y), col)
    img.save(OUT + "rain.png")


# Snow: 4 flakes across, small to large. '#' foam, '+' foam2, '.' empty.
SNOW = [
    ["+"],
    ["#"],
    [".+.",
     "+#+",
     ".+."],
    ["..+..",
     ".+#+.",
     "+###+",
     ".+#+.",
     "..+.."],
]
# A drop landing, seen from above: 4 frames, impact to gone.
SPLASH = [
    ["#"],
    [".#.",
     "#.#",
     ".#."],
    [".+++.",
     "+...+",
     "+...+",
     ".+++."],
    [".+.+.",
     ".....",
     "+...+",
     ".....",
     ".+.+."],
]
KEY = {"#": FOAM, "+": FOAM2, ".": None}


def strip(shapes, cell, name, faint_last=False):
    img = Image.new("RGBA", (cell * len(shapes), cell), (0, 0, 0, 0))
    for i, shape in enumerate(shapes):
        ox = i * cell + (cell - len(shape[0])) // 2
        oy = (cell - len(shape)) // 2
        for y, line in enumerate(shape):
            for x, ch in enumerate(line):
                col = KEY[ch]
                if col is not None:
                    if faint_last and i == len(shapes) - 1:
                        col = WAT4
                    img.putpixel((ox + x, oy + y), col)
    img.save(OUT + name)


if __name__ == "__main__":
    rain_sheet()
    strip(SNOW, 8, "snow.png")
    strip(SPLASH, 8, "splash.png", faint_last=True)
