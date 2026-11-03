# Godot in plain terms

A short guide to how a Godot game is put together, written for Lodge. Read it alongside [ARCHITECTURE.md](ARCHITECTURE.md), which says how Lodge uses each of these pieces.

## The six building blocks

### 1. Nodes

A **node** is one thing in the game that does one job. A `Node2D` has a position on screen. A `Sprite2D` shows a picture. A `Timer` counts down. An `AudioStreamPlayer` plays a sound. A `CanvasLayer` draws on top of everything else (good for the HUD).

Nodes live in a **tree**: every node has one parent and any number of children. A child moves with its parent, is drawn with it, and is deleted with it. Every frame, Godot walks the tree and calls each node's `_process(delta)`, where `delta` is the seconds since the last frame.

In Lodge today: `Main` (the stream) is the parent, and `Cast`, `Fishing`, `Practice` and `DebugLayer` are its children.

### 2. Scenes

A **scene** is a saved branch of the tree, stored as a `.tscn` file. It's a reusable template. You can open it on its own, test it on its own, and drop copies of it into other scenes ("instancing").

A good rule of thumb: **if you'd want more than one of it, or want to test it alone, make it its own scene.** A fish, a fly on the water, the catch card, the fly box screen and a river stretch are all good candidates. Lodge currently has one scene, `scenes/main.tscn`, which is fine for a prototype but won't scale.

### 3. Scripts

A **script** (`.gd`, written in GDScript) adds behaviour to a node. One node gets at most one script. The script `extends` the node type it's attached to (`extends Node2D`).

Scripts don't have to be attached to nodes. A script that `extends RefCounted` is a plain object: no position, no tree, no `_process`. It just holds data and logic. These are perfect for **rules**, because a test can create one, feed it numbers and check the answer, with no scene, no screen and no controller. Lodge's `CastModel`, `DriftModel`, `FightModel`, `Fish` and `RiverField` are all like this, and that's the single best thing about the current code.

`class_name CastModel` at the top of a script gives it a global name, so other scripts can write `CastModel.new()` without loading a path.

### 4. Signals

A **signal** is a node or object announcing that something happened: `landed`, `collapsed`, `fish_hooked`. Anyone interested **connects** to it. The announcer doesn't know or care who's listening.

```gdscript
# In CastModel:
signal landed(presentation: String, quality: float)
...
landed.emit("Delicate", 0.9)

# In the fishing code:
cast.model.landed.connect(_on_landed)
```

Signals are how you keep systems from knowing too much about each other. The casting code can announce `landed` without knowing that fishing, practice mode and (later) sound effects all care.

The usual rule is **"call down, signal up"**: a parent may call methods on its children directly (it owns them), but a child tells its parent things by emitting a signal. Siblings shouldn't call each other at all; their parent connects them.

### 5. Autoloads

An **autoload** is a node Godot creates once, before any scene, and keeps alive for the whole game. Any script can reach it by name. Lodge has one: `Controls`, which every script uses to read input.

Autoloads are convenient, which is exactly why they're dangerous. Every autoload is a global that any code can read and change, so a bug can come from anywhere. Keep them few and boring: input, the save file, the game clock and calendar, audio. **Never put gameplay rules in an autoload**, and never let one hold a reference to something in the current scene.

### 6. Resources

A **Resource** is a data object saved as a `.tres` file and edited in the Godot inspector. You define the fields in a script (`extends Resource`, with `@export var` fields) and then make as many files as you like. Lodge uses these for flies (`data/tackle/flies/`), fish species (`data/fish/`), casting rule sets (`data/cast_rules/`) and cast tuning.

Resources are how a game with 100 fish and hundreds of flies stays manageable: each new fish is a file, not code. Two things to know:

* **A loaded resource is shared.** Every script that loads `redband.tres` gets the same object. Treat them as read-only at runtime. If something needs to change per fish (its length, its hunger), put that on a separate runtime object (`Fish`), not on the species resource.
* **A resource can carry a script with logic**, which makes it a swappable strategy. `CastRules` does this: each rule set is a resource whose script answers "how long should this stroke be?". That's how the three casting chassis sit side by side.

## Two more tools

**Groups** are tags on nodes. `add_to_group(&"fishing")` lets any script find that node with `get_tree().get_first_node_in_group(&"fishing")`. Good for loose, optional lookups like the debug overlay. Bad as the main way systems talk, because nothing checks that the group exists or what it offers.

**Static typing** (`var fish: Fish`, `func bite_chance() -> float`) makes Godot catch mistakes when the script loads instead of at the moment the line runs. Lodge already types most things. Keep it that way, especially with AI writing code, since a typed mistake fails a test immediately.

## How growing Godot games go wrong

These are the common ways a Godot project gets hard to change. Each one has a note on where Lodge stands.

| Pitfall | What it looks like | Lodge today |
|---|---|---|
| **The god script** | One script does input, rules, drawing and UI. Every feature touches it, so every PR conflicts with every other. | `fishing_controller.gd` (440 lines) is heading this way. It's already on the refactor backlog. |
| **Reaching across the tree** | `get_node("../Cast").model.state` or `get_parent().get_parent()`. Moving a node breaks code far away, silently. | `Fishing` and `Practice` reach into `Cast` this way, and `Cast` reaches back into `Fishing`. |
| **Two owners for one value** | Two scripts both write the same variable, so nobody knows who's right. | The fly's position is written by both `Cast` and `Fishing`. |
| **Autoload sprawl** | Ten global singletons all calling each other; a "GameManager" that knows everything. | Clean: only `Controls`. |
| **Event bus soup** | One global node with 50 signals that anything can emit. Easy to add, impossible to follow. | Not present. Avoid it. |
| **Strings as types** | `"Delicate"`, `"rising"`, `"Short"` passed around. A typo is a silent bug. | Presentation and fish events are strings. |
| **Mutating shared resources** | Changing `species.bite_chance` at runtime changes it for every fish, and in the editor. | Clean so far. |
| **Rules inside nodes** | Logic that only runs with the scene loaded, so it can only be tested by playing. | Mostly clean: rules are in models. Bite odds still have constants inside `Fish`. |
| **Screen pixels as world units** | Fine for one screen, painful when the river spans many. | Everything is in screen px, and code reads `stream.VIEW` and `BANK_TOP`. |
| **Saving object references** | Saving a whole resource or node instead of its id. Breaks when data changes. | The catch log stores resources, not ids. No saves yet, so it's cheap to fix now. |

## Why this matters more with AI writing the code

An AI assistant writes good code locally but has no memory between sessions. It will happily add a fourth way of doing something that already has three. What keeps a codebase coherent is the same thing that keeps a team of new hires coherent:

1. **A written map** of the systems, who owns what, and which way dependencies point (ARCHITECTURE.md).
2. **Small files with one job**, so a change has an obvious home.
3. **Rules checked by tests, not by memory.** A boundary that a test enforces stays; a boundary that's only written down erodes. `tools/run_tests.sh` and `tests/data_test.gd` already do this for data and input. ARCHITECTURE.md proposes doing it for the layer rules too.
4. **A decision log**, so a later session can see *why* something is the way it is before "fixing" it.
