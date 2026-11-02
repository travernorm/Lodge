class_name TakeRules
extends Resource
## A "chassis" for bites: the rules that decide whether a trout takes the fly.
## Like the casting rule sets, these are swappable so different rules can be
## played side by side (X / Square, or R, while reeled in). Their numbers live
## in data/take_rules/*.tres.
##
## This base class is the original "Landing roll": one roll the moment the fly
## lands, from how close it landed to the fish and how softly. The drift after
## that doesn't matter. DriftPastRules (scripts/fishing/rules/) rolls as the fly
## drifts past each fish instead, and MatchFlyRules also weighs the fly.

## Shown when you switch rules.
@export var display_name := "Landing roll"
@export_multiline var description := ""


## True: each fish rolls once when the fly lands (landing_odds()).
## False: each fish rolls as the fly drifts past it (pass_odds()).
func rolls_on_landing() -> bool:
	return true


## The odds for a fly landing at `at` (m). Returns {chance, text}: text spells
## the odds out for the screen. `fly` is what's tied on (null if nothing); these
## rules ignore it.
func landing_odds(fish: Fish, at: Vector2, presentation: String, _fly: FlyPattern = null) -> Dictionary:
	var chance := fish.bite_chance_for(at, presentation)
	return {"chance": chance, "text": "%s landing  %d%%" % [presentation, roundi(chance * 100.0)]}


## How close (m) the fly has to come for a pass to count. Unused here.
func window() -> float:
	return 0.0


## The odds for a fly drifting past `fish`. Unused here.
func pass_odds(_fish: Fish, _landed_at: Vector2, _presentation: String, _worst_slip: float, _fly: FlyPattern = null) -> Dictionary:
	return {"chance": 0.0, "text": ""}


## Seconds from a successful roll to the rise.
func rise_delay() -> Vector2:
	return Fish.BITE_DELAY
