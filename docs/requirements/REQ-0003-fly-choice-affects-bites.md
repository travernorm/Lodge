# REQ-0003: Fly choice affects the bite

Status: review (engineering and architecture reviews done; waiting on Traver)

## Problem

The fly box does nothing. The game starts with one fly (the Parachute Adams), the other two sit unused in `data/flies/`, and even if you could change flies every trout would take them all the same. Each fish file lists a favourite fly (`preferred_flies`), and nothing reads it. So there's no reason to look at the water, read a fish's description or change flies, and "match the hatch", the heart of dry fly fishing, has no first step.

## Player story

As a player, I want the fly I tie on to matter to the trout I'm fishing to, so that picking from the fly box is a real decision I can learn to get right.

## Feel goals

* The right fly makes a clear, visible difference: about double the odds of the wrong one on a fussy fish.
* The wrong fly still catches fish sometimes, never zero. A good drift is still the main skill.
* Fussy fish care a lot, easy fish (brook trout) barely care.
* The odds line says plainly whether the fly matched, so the player learns the rule by fishing.
* You can always find out what a trout eats without guessing: its description, and later the hatch, the journal and perception checks.

## Scope

The simplest version: match **what the fly imitates** against **what the trout is eating**, scaled by **how fussy that species is**. No hatch, clock or sizes yet.

**Data (two data classes change):**

* `FlyPattern` gets `imitates`: a list of insect ids from the hatch table in SPECIES_AND_CONDITIONS.md (`caddis`, `pmd`, `baetis` ...), or `attractor` for a fly that copies nothing. A generalist fly lists several; a specific one lists one.
* `FishSpecies` gets `eats` (insect ids it's feeding on, a stand-in until hatches exist) and `selectivity` (0 to 1, how fussy it is).
* `FishSpecies.preferred_flies` is removed. It's unused, and `eats` replaces it with something that scales to hundreds of flies.

**Starting values:**

| Fly | Imitates |
|---|---|
| Elk Hair Caddis | `caddis` |
| Parachute Adams | `baetis`, `pmd`, `march_brown`, `mahogany`, `callibaetis` (it "passes for most mayflies") |
| Royal Wulff | `attractor` |

| Fish | Eats | Selectivity | Wrong fly gets |
|---|---|---|---|
| Redband | `pmd`, `baetis` (it "sips mayflies") | 0.5 | ×0.5 |
| Cutthroat | `caddis` | 0.6 | ×0.4 |
| Brook | `attractor`, `caddis`, `pmd` ("brook trout love it anyway") | 0.2 | ×0.8 |

**The rule:** a fly matches if anything in its `imitates` is in the fish's `eats`. A match is ×1. A miss is ×(1 − selectivity).

**The fly box:** holds all three flies, Parachute Adams first (Dad's favourite), so Y / F cycles through them while reeled in. The fly box HUD and its "Y: fly box" hint already exist and appear once there's more than one fly.

**The bite rules:** a new **Match the fly** bite rules file (`data/take_rules/match_fly.tres`), built on Drift past. The three Drift past shares are added as now, then multiplied by the fly match, because the fly is a gate ("does this look like food?"), not one more thing to stack. It goes first in the bite rules list so it's the default, and Drift past and Landing roll stay one press of R / Square away for comparison.

**On screen:**

* The odds line becomes `(Lane 20 + Delicate 20 + No drag 20) × Match 1 = 60%`, or `... × No match 0.5 = 30%`. It wraps to two lines at 320 px if needed, as it does now.
* Tying on a fly says what it imitates: "Tied on an Elk Hair Caddis (caddis)."
* The README's bite rules section explains the match.

## Out of scope

* Hatches, the clock, seasons and mood. Later, the active hatch narrows what a fish `eats` and raises its selectivity when the hatch is thick (FISH_LOGIC.md steps 4 and 5).
* Fly size, stage (nymph, emerger, dun) and colour as partial matches. They are the next layer once there are enough flies for them to matter.
* Refusals (the fish rises, looks and turns away). That's FISH_LOGIC.md step 3, and it will be the best tell for a near miss. It's the recommended next REQ.
* Spooking, new flies, a fly box screen, saving the fly box.

## Systems touched

| System | Changes? | Depends on the change? | How it's checked |
|---|---|---|---|
| Casting | No | No | `cast_test`, `cast_rules_test`, playthrough (Short, Middle, Long) |
| River | No | No | `river_test`, `smoke_test` |
| Fishing | Yes: `FlyPattern` and `FishSpecies` fields, new `MatchFlyRules`, `TakeRules.pass_odds` gains the tied-on fly, a few lines in `fishing_controller.gd` (the fly box list, the bite rules list, passing the fly) | Bite rules, catch card (already names the fly), fly box HUD and message | New unit tests in `tests/match_fly_test.gd`; `take_rules_test` unchanged and passing; `data_test` contracts below |
| UI and modes | The odds line text and the tie-on message | Practice mode (no bites, unaffected) | Playthrough: a catch under every bite rules file, including the new one; practice mode under every rule set |
| Input | No | No | `data_test` parity, input-map check |
| Saves | None exist. Insect ids become content ids, so they follow the never-rename rule from now on. | | |

## Acceptance criteria

1. The fly box starts with all three flies, Parachute Adams tied on. (playthrough: Y cycles them)
2. A fly whose `imitates` overlaps a fish's `eats` gets ×1; otherwise ×(1 − selectivity). (unit test)
3. Under Match the fly, a delicate, drag-free pass in lane with a matching fly gives the species' full `bite_chance`; the same pass with a wrong fly gives `bite_chance × (1 − selectivity)`. (unit test)
4. Drift past and Landing roll odds are unchanged by the tied-on fly. (existing `take_rules_test` passes untouched, plus one new check)
5. The odds line shows the match factor, and the tie-on message names what the fly imitates. (unit test on the text; playtest)
6. Every fly imitates at least one thing; every insect id a fish eats is imitated by at least one fly in `data/flies`, so every fish has a right answer; `selectivity` is in [0, 1]. (`data_test`)
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
* **Data, not code.** Fussiness and diets are fields on the fish files; what a fly copies is on the fly files. Adding a fly or a fish stays a data-only change.
* **Docs to update in the build PR:** ARCHITECTURE.md 3.4 (`imitates` is a list, not one id) and problem #10 (bite rules now read the fly through an argument until `FlyState`); FISH_LOGIC.md "Building it up" (fly match and selectivity arrive before the hatch); the system map's Fishing row (bite rules read the tied-on fly).
* **Refactor backlog:** `fishing_controller.gd` is 636 lines, past the backlog's 500-line trigger. This REQ only changes a few lines there, so it doesn't absorb the split. Recommended instead as its own next PR (ARCHITECTURE.md step A) before refusals land, since those add more drawing.

## Open questions

1. **What decides whether a trout wants the fly?** Recommended: what it's eating, as above. Alternatives: the old favourite-fly list (exact fly or nothing, which doesn't scale past a few flies), or one hatch on the whole stretch (closest to the final game, but one fly wins everywhere until the clock exists).
2. **Multiply or add?** Recommended: multiply the fly match, as above. The alternative is a fourth equal share (each worth 15%), which makes the fly matter less.
3. **Make Match the fly the default bite rules?** Recommended: yes, with the others one press away.
