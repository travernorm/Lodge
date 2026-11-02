# REQ-0003: Fly choice affects the bite

Status: implemented (approved by Traver, 2026-11-02)

## Problem

The fly box does nothing. The game starts with one fly (the Parachute Adams), the other two sit unused in `data/flies/`, and even if you could change flies every trout would take them all the same. Each fish file lists a favourite fly (`preferred_flies`), and nothing reads it. So there's no reason to look at the water, read a fish's description or change flies, and "match the hatch", the heart of dry fly fishing, has no first step.

## Player story

As a player, I want the fly I tie on to matter to the trout I'm fishing to, so that picking from the fly box is a real decision I can learn to get right.

## Feel goals

* The right fly makes a clear, visible difference: about double the odds of the wrong one on a highly selective fish.
* The wrong fly still catches fish sometimes, never zero. A good drift is still the main skill.
* Highly selective fish care a lot; fish with low selectivity (brook trout) barely care.
* The odds line says plainly whether the fly matched, so the player learns the rule by fishing.
* You can always find out what a trout eats without guessing: its description, and later the hatch, the journal and perception checks.

## Scope

The simplest version: match **what the fly imitates** against **what the trout is eating**, scaled by **that species' selectivity**. No hatch, clock or sizes yet.

**Data (one new data class, two change):**

* **New `Insect` resource**, one `.tres` per bug in `data/insects/` (id, display name, kind such as mayfly, caddis or attractor). It's the one shared thing a fly, a fish's diet and, later, a hatch all point at, so they can't disagree. Only the bugs in use now get files: `caddis`, `pmd`, `baetis`, `march_brown`, `mahogany`, `callibaetis`, plus `attractor` for a fly that copies nothing. Ids come from the hatch table in SPECIES_AND_CONDITIONS.md.
* `FlyPattern` gets `imitates: Array[Insect]`. A generalist fly lists several; a specific one lists one.
* `FishSpecies` gets `diet` (insect id → how much it wants it, 0 to 1; a stand-in until hatches exist) and `selectivity` (0 to 1: how much it cares that the fly looks like its food. 0 takes anything drifted well; 1 takes only the right bug). `diet` is the Dictionary format agreed for SPECIES_AND_CONDITIONS.md, and it's a Dictionary of ids rather than resources because Godot 4.3 has no typed dictionaries.
* `FishSpecies.preferred_flies` is removed. It's unused, and `diet` replaces it with something that scales to hundreds of flies.

**Starting values:**

| Fly | Imitates |
|---|---|
| Elk Hair Caddis | `caddis` |
| Parachute Adams | `baetis`, `pmd`, `march_brown`, `mahogany`, `callibaetis` (it "passes for most mayflies") |
| Royal Wulff | `attractor` |

| Fish | Diet | Selectivity |
|---|---|---|
| Redband | `pmd` 1.0, `baetis` 1.0, `caddis` 0.5 (it "sips mayflies") | 0.5 |
| Cutthroat | `caddis` 1.0 | 0.6 |
| Brook | `attractor` 1.0, `caddis` 1.0, `pmd` 1.0 ("brook trout love it anyway") | 0.2 |

**The rule:**

```
appetite = the fish's highest diet weight among the bugs the fly imitates (0 if none)
fly match = 1 − selectivity × (1 − appetite)
```

So the right bug is ×1, a bug it half wants sits between, and a bug it doesn't eat gets ×(1 − selectivity). What the three flies get:

| | Elk Hair Caddis | Parachute Adams | Royal Wulff |
|---|---|---|---|
| Redband | ×0.75 | ×1 | ×0.5 |
| Cutthroat | ×1 | ×0.4 | ×0.4 |
| Brook | ×1 | ×1 | ×1 |

**The full take equation** (one roll per pass, when the fly comes within 1 m; B is the species' `bite_chance`):

```
take   = min(1, (Lane + Landing + Drift) × Fly match)
Lane    = B / 3
Landing = B / 3 if Delicate, B / 6 if Fair, 0 if Splashy; only for a landing within 3 m of the fish
Drift   = B / 3 × clean,  clean = 1 − clamp((worst slip − 0.3) / 0.5, 0, 1)
Fly match = 1 − selectivity × (1 − appetite),  appetite = highest diet weight among the bugs the fly imitates (0 if none)
```

Example: a redband, an Elk Hair Caddis landed Fair within 3 m, worst slip 0.55 m/s: (20 + 10 + 10) × 0.75 = 30%. Mood, refusals, spooking, a floor and ceiling, and streak protection are not in it yet (FISH_LOGIC.md).

**The fly box:** holds all three flies, Parachute Adams first (Dad's favourite), so Y / F cycles through them while reeled in. The fly box HUD and its "Y: fly box" hint already exist and appear once there's more than one fly.

**The bite rules:** a new **Match the fly** bite rules file (`data/take_rules/match_fly.tres`), built on Drift past. The three Drift past shares are added as now, then multiplied by the fly match, because the fly is a gate ("does this look like food?"), not one more thing to stack. It goes first in the bite rules list so it's the default, and Drift past and Landing roll stay one press of R / Square away for comparison.

**On screen:**

* The odds line becomes `(Lane 20 + Delicate 20 + No drag 20) × PMD 1 = 60%`, naming the bug that matched from its `Insect` display name, or `... × No match 0.5 = 30%`. It wraps to two lines at 320 px if needed, as it does now.
* Tying on a fly says what it imitates: "Tied on an Elk Hair Caddis (Caddis)."
* The README's bite rules section explains the match.

## How it fits Godot

Flies, bugs and fish species are **Resources** (`.tres` data files), not nodes, and none of this uses node groups. Groups are Godot's way to find live nodes in the scene tree (the Fishing, Stream and Cast nodes already join `fishing`, `stream` and `cast`). A fly in your box isn't a thing in the world that runs each frame, so making it a node would add tree overhead and break the rule that models never touch the tree (ARCHITECTURE.md section 1). The links between them live in the resources:

```
 data/insects/caddis.tres  ◀─────────────── Insect: the one shared key
        ▲                        ▲
        │ imitates               │ diet (id → weight)
 data/flies/*.tres          data/fish/*.tres           data/take_rules/match_fly.tres
 FlyPattern                 FishSpecies                 MatchFlyRules
        ▲                        ▲                           │
        │ tied on                │ species                   │ reads both
 Fishing node (scene)       Fish (runtime, RefCounted)  ◀────┘ pass_odds(fish, …, fly)
   flies: Array[FlyPattern]   one per trout, owned by Fishing
   fly_index
```

* **The fly box** stays an exported `Array[FlyPattern]` on the Fishing node, so it's edited in the Inspector by dragging fly files in. It becomes a `FlyBox` model when inventory arrives (ARCHITECTURE.md step D).
* **`imitates` is `Array[Insect]`**, a typed array, so the Inspector only accepts insect files and a typo can't get in.
* **`diet` keys are ids** checked by `data_test` against `data/insects/`, so a diet can't name a bug that doesn't exist.
* **The odds come only from these links.** `MatchFlyRules` gets the tied-on fly and the fish, looks up the fish's diet for each bug the fly imitates, and returns the factor and its label. Nothing about which fly suits which fish is written in code.
* **Saves and the catch log** will store the fly and insect ids, never the resources, per ARCHITECTURE.md rule 5.

## Out of scope

* Hatches, the clock, seasons and mood. Later, the active hatch raises the diet weight of whatever is hatching and raises its selectivity when the hatch is thick (FISH_LOGIC.md steps 4 and 5).
* Fly size, stage (nymph, emerger, dun) and colour as partial matches. They are the next layer once there are enough flies for them to matter.
* Refusals (the fish rises, looks and turns away). That's FISH_LOGIC.md step 3, and it will be the best tell for a near miss. It's the recommended next REQ.
* Spooking, new flies, a fly box screen, saving the fly box.

## Systems touched

| System | Changes? | Depends on the change? | How it's checked |
|---|---|---|---|
| Casting | No | No | `cast_test`, `cast_rules_test`, playthrough (Short, Middle, Long) |
| River | No | No | `river_test`, `smoke_test` |
| Fishing | Yes: new `Insect` class and `data/insects/`, `FlyPattern` and `FishSpecies` fields, new `MatchFlyRules`, `TakeRules.pass_odds` gains the tied-on fly, a few lines in `fishing_controller.gd` (the fly box list, the bite rules list, passing the fly) | Bite rules, catch card (already names the fly), fly box HUD and message | New unit tests in `tests/match_fly_test.gd`; `take_rules_test` unchanged and passing; `data_test` contracts below |
| UI and modes | The odds line text and the tie-on message | Practice mode (no bites, unaffected) | Playthrough: a catch under every bite rules file, including the new one; practice mode under every rule set |
| Input | No | No | `data_test` parity, input-map check |
| Saves | None exist. Insect ids become content ids, so they follow the never-rename rule from now on. | | |

## Acceptance criteria

1. The fly box starts with all three flies, Parachute Adams tied on. (playthrough: Y cycles them)
2. The fly match follows the rule above, including a partial diet weight, and every cell of the table above comes out as shown. (unit test)
3. Under Match the fly, a delicate, drag-free pass in lane with a matching fly gives the species' full `bite_chance`; the same pass with a wrong fly gives `bite_chance × (1 − selectivity)`. (unit test)
4. Drift past and Landing roll odds are unchanged by the tied-on fly. (existing `take_rules_test` passes untouched, plus one new check)
5. The odds line shows the match factor, and the tie-on message names what the fly imitates. (unit test on the text; playtest)
6. Every insect file loads with an id matching its file name; every fly imitates at least one insect; every diet key is a real insect id with a weight in [0, 1]; every fish has at least one fly in `data/flies` that it fully wants, so there's always a right answer; `selectivity` is in [0, 1]. (`data_test`, which reads the folders, so new bugs, flies and fish are covered automatically)
7. The playthrough catches a fish under every bite rules file, and practice mode still never bites. (`playthrough_test`)
8. No new randomness: the match is deterministic, so seeded tests replay exactly. (unit test)

## Playtest checks

On the keyboard and the DualSense:

1. Fish the redband at the head of the pool with the Parachute Adams, then the Royal Wulff (Y / F to change flies while reeled in). The odds line should show Match 1, then No match 0.5.
2. Find the brook trout and try all three flies. They should all do nearly as well.
3. Press R / Square to switch to Drift past and check the fly no longer matters.
4. The usual checks: cast Short, Middle and Long; land a fish; strike at nothing; reel in with B / Circle; practice mode and rule sets; debug views.
5. The odds line is readable at 320×200 and on the Deck (or the PR says the Deck wasn't checked). The browser build needs no check, since only text changes.

## Engineering review (2026-11-02)

* **Where the fly comes from.** Bite rules can't see the fly today. `TakeRules.pass_odds()` and `landing_odds()` gain a `fly: FlyPattern` argument, and the controller passes `current_fly()`. Base `TakeRules` and `DriftPastRules` ignore it. This is a bridge until `FlyState.pattern` exists (ARCHITECTURE.md step B), which will carry it instead.
* **No fly tied on** (an empty fly box): the match is ×1, so nothing breaks.
* **Finding: the fly box holds one fly.** `fishing_controller.gd` exports only the Parachute Adams, so Y / F says "Just the one fly in Dad's box". Scope now stocks all three.
* **Existing tests.** The smoke test and playthrough catch the first trout (a redband on the demo stretch) with the default Parachute Adams, which matches, and they set `bite_chance` to 1, so their odds don't drop. The playthrough loop over bite rules covers the new file automatically. If a seeded catch ever needs the wrong fly, the test changes flies rather than the odds changing.
* **Determinism and frame rate:** the match is a pure lookup, rolled once per pass as now. No new randomness, no per-frame work.
* **Text width:** the longest line is about 55 characters, which wraps to two lines at 8 px. The odds box already handles wrapping.
* **Ids:** insect ids reuse the hatch table's ids, so a hatch, a fly and a fish's diet share them, as SPECIES_AND_CONDITIONS.md intends. They're stored in data only, with no saves yet.
* **Web and Deck:** text only. No new assets, input or threads.

## Architecture review (2026-11-02)

* **Fits the chassis.** Match the fly is one more `TakeRules` file, the same pattern as the casting rule sets, and keeps every factor on screen.
* **Data, not code.** Selectivity and diets are fields on the fish files; what a fly copies is on the fly files. Adding a fly or a fish stays a data-only change.
* **Relational integrity.** One `Insect` file per bug is the single source the fly, the diet and later the hatch share, so renaming a bug's display name changes it everywhere and an id can't drift. This adds a `data/insects/` folder now rather than waiting for hatches, because both new fields need it.
* **Docs to update in the build PR:** ARCHITECTURE.md 3.4 (`imitates` is a list of `Insect`s, not one id) and the data layer list (add `Insect`) and problem #10 (bite rules now read the fly through an argument until `FlyState`); FISH_LOGIC.md "Building it up" (fly match and selectivity arrive before the hatch); the system map's Fishing row (bite rules read the tied-on fly).
* **Refactor backlog:** `fishing_controller.gd` is 636 lines, past the backlog's 500-line trigger. This REQ only changes a few lines there, so it doesn't absorb the split. Recommended instead as its own next PR (ARCHITECTURE.md step A) before refusals land, since those add more drawing.

## Open questions

1. **What decides whether a trout wants the fly?** Decided (Traver, 2026-11-02): what it's eating, through the shared `Insect` files and diet weights above.
2. **Multiply or add?** Decided (Traver, 2026-11-02): multiply the fly match.
3. **Make Match the fly the default bite rules?** Decided (Traver, 2026-11-02): yes, with the others one press away.
