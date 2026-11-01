# Tooling

## What to install

| Tool | Why | Cost |
|---|---|---|
| [Godot 4.3+](https://godotengine.org/download) (standard build) | Engine. Light, strong 2D and pixel-art support, good gamepad handling, exports to Linux for Steam Deck. | Free |
| Godot export templates | Needed to export builds. In Godot: **Editor → Manage Export Templates → Download and Install**. | Free |
| [Aseprite](https://www.aseprite.org/) or [LibreSprite](https://libresprite.github.io/) | Pixel art and sprite animation (fish, flies, the angler, tiles). Aseprite is the standard; LibreSprite is a free fork. | ~$20 / free |
| Git + [GitHub Desktop](https://desktop.github.com/) (optional) | Version control and syncing with this repo. | Free |
| An Xbox-style controller | Lets you test the Deck control scheme on a PC before moving builds over. | — |

Later, worth adding when sound comes in: [Bfxr](https://www.bfxr.net/) or [ChipTone](https://sfbgames.itch.io/chiptone) for retro sound effects, and [Audacity](https://www.audacityteam.org/) for editing.

## Resolution and look

- The game renders at **320×200** and scales by whole numbers. 320×200 is exactly 1/4 of the Steam Deck's 1280×800 screen, so pixels stay crisp with no letterboxing on the Deck.
- Textures use nearest-neighbour filtering, and 2D transforms snap to whole pixels.
- The renderer is **GL Compatibility**, which is light on the Deck's battery and is also the path that ports most easily to Switch.

## Controls are defined in code

`tools/setup_input_map.gd` is the source of truth for the input map. To change a binding, edit that file and run:

```
godot --headless --path . --script res://tools/setup_input_map.gd
```

That rewrites the `[input]` section of `project.godot`. Game code refers to actions through the `Controls` autoload (`Controls.CAST_BACK`, `Controls.rod_vector()`, and so on) rather than typing raw action strings.

## Testing on the Steam Deck

The Deck runs Linux, so export the **Steam Deck (Linux x86_64)** preset.

1. In Godot: **Project → Export → Steam Deck (Linux x86_64) → Export Project**. This writes `build/linux/Lodge.x86_64`.
2. Copy the file to the Deck. Easy options are a USB stick, [Warpinator](https://github.com/linuxmint/warpinator) or [KDE Connect](https://kdeconnect.kde.org/) over Wi-Fi, or a shared network folder.
3. On the Deck, switch to **Desktop Mode**. Right-click the file, choose **Properties → Permissions**, and tick **Is executable**.
4. In Steam (desktop mode): **Games → Add a Non-Steam Game to My Library**, then browse to the file.
5. Return to Gaming Mode and launch it from your library. Under the game's controller settings, pick the **Gamepad** template so R1/L1 and the sticks arrive as a standard pad.

The debug overlay is on in debug exports. Use it to check that the bumpers and sticks register, and to read real hold and overlap timings while tuning the cast.

## Checks

- `tests/smoke_test.gd` verifies every input action exists, loads the main scene, runs 30 frames and sanity-checks the current model. Run it locally with:

  ```
  godot --headless --path . --script res://tests/smoke_test.gd
  ```

- GitHub Actions runs the same test on every pull request (`.github/workflows/godot-check.yml`).
- `tools/capture_screenshot.gd` renders the scene to a PNG with scripted bumper presses. It needs a display; on a headless Linux machine, wrap it in `xvfb-run`.

## Platform notes

- **Steam Deck / PC:** Linux export now. Windows and macOS presets can be added whenever they're needed.
- **Switch:** Godot can't export to Switch directly. Console builds go through a porting partner (for example W4 Games or Lone Wolf Technology) once the game is far enough along to pitch. Keeping to GL Compatibility and modest asset sizes keeps that path open.
