class_name DriftPastRules
extends Resource
## The bite rules: whether a trout takes the fly. Their numbers live in
## data/take_rules/drift_past.tres.
##
## "Drift past": a fish judges the fly as it drifts past, not where it landed.
## When the fly comes within window_m of a fish, that's a pass. The fish rolls
## once per pass, as the fly is closest to it (right away if the fly landed on
## top of it). The chance is the species' bite_chance, split three ways, then
## multiplied by how well the tied-on fly matches what the fish is eating
## (REQ-0003):
##
##   In lane    the fly came through the fish's window at all
##   Landing    a delicate landing near the fish (a fair one gets half). A
##              landing far upstream doesn't count either way, and a splashy
##              one is never punished, so casting onto a fish is fine
##   Drift      the fly rode the current through the pass, judged by its worst
##              moment: drag, skating or the jolt of an early mend all move the
##              fly differently from the water under it (DriftModel.slip)
##
##   take = (Lane + Landing + Drift) x Fly match
##   Fly match = 1 - selectivity x (1 - appetite)
##
## appetite is the fish's highest diet weight among the bugs the fly imitates
## (FishSpecies.appetite_for), so the right bug is x1 and a bug it doesn't eat
## keeps (1 - selectivity). The fly is a gate ("does this look like food?"),
## not one more bonus, so it scales the other three.

## Shown on screen (debug view).
@export var display_name := "Drift past"
@export_multiline var description := ""
## The fish's window (m): the fly has to come this close.
@export var window_m := 1.0
## A landing this close (m) to the fish counts for the landing share.
@export var landing_near_m := 3.0
## Shares of the species' bite_chance. They add up to 1, so a delicate,
## drag-free drift past the fish gets the full bite_chance.
@export var lane_share := 1.0 / 3.0
@export var delicate_share := 1.0 / 3.0
@export var fair_share := 1.0 / 6.0
@export var drift_share := 1.0 / 3.0
## Slip (m/s, the fly's speed against the water under it). At or under
## slip_free the drift is clean; at slip_full and over it earns nothing.
## The drag wake shows from about 0.8 m/s.
@export var slip_free := 0.3
@export var slip_full := 0.8
## Seconds from a successful roll to the rise: quick, so the fish comes up
## while the fly is still beside it.
@export var rise_delay_s := Vector2(0.2, 0.5)
## A fish on a resting lie (deep, slow, covered) is slow to come up: a dry
## fly's odds are multiplied by this. Nymphs and streamers go down to it, so
## they keep full odds (REQ-0011).
@export_range(0.0, 1.0) var resting_dry_factor := 0.5


## How close (m) the fly has to come for a pass to count.
func window() -> float:
	return window_m


## The odds for a fly drifting past `fish`: {chance, match, text}. text spells
## the odds out for the screen. `fly` is what's tied on (null if nothing, which
## counts as a match).
func pass_odds(fish: Fish, landed_at: Vector2, presentation: String, worst_slip: float, fly: FlyPattern = null) -> Dictionary:
	var s := shares(fish, landed_at, presentation, worst_slip)
	var match_factor := fish.species.fly_match(fly)
	var rest := resting_factor(fish, fly)
	var chance := clampf(s.sum * match_factor * rest, 0.0, 1.0)
	var rest_text := " × Resting lie %s" % _factor(rest) if rest < 1.0 else ""
	return {
		"chance": chance,
		"match": match_factor,
		"text": "(%s) × %s %s%s = %d%%" % [s.text, match_label(fish, fly), _factor(match_factor), rest_text, _pct(chance)],
	}


## resting_dry_factor for a dry fly over a fish on a resting lie, else 1.
## Nothing tied on counts as a dry.
func resting_factor(fish: Fish, fly: FlyPattern) -> float:
	if not fish.resting or (fly != null and fly.fly_type != FlyPattern.Type.DRY):
		return 1.0
	return resting_dry_factor


## The three shares for a pass, added up: {lane, landing, drift, sum, text}.
## text spells out the sum, e.g. "Lane 20 + Delicate 20 + No drag 20".
func shares(fish: Fish, landed_at: Vector2, presentation: String, worst_slip: float) -> Dictionary:
	var base := fish.species.bite_chance
	var lane := base * lane_share
	var landing := 0.0
	if landed_at.distance_to(fish.lie) <= landing_near_m:
		if presentation == "Delicate":
			landing = base * delicate_share
		elif presentation == "Fair":
			landing = base * fair_share
	var clean := 1.0 - clampf((worst_slip - slip_free) / maxf(slip_full - slip_free, 0.001), 0.0, 1.0)
	var drift := base * drift_share * clean
	var landing_label := presentation if landing > 0.0 else "Landing"
	var drift_label := "No drag" if clean >= 1.0 else ("Drag" if clean <= 0.0 else "Some drag")
	return {
		"lane": lane, "landing": landing, "drift": drift, "sum": lane + landing + drift,
		"text": "Lane %d + %s %d + %s %d" % [_pct(lane), landing_label, _pct(landing), drift_label, _pct(drift)],
	}


## Seconds from a successful roll to the rise.
func rise_delay() -> Vector2:
	return rise_delay_s


## The bug that matched ("PMD"), or "No match" when the fish eats none of what
## the fly imitates. With nothing tied on, "Any fly".
static func match_label(fish: Fish, fly: FlyPattern) -> String:
	if fly == null:
		return "Any fly"
	var best := fish.species.appetite_for(fly)
	var insect: Insect = best.insect
	return insect.display_name if insect != null else "No match"


static func _pct(x: float) -> int:
	return roundi(x * 100.0)


## 1 -> "1", 0.5 -> "0.5", 0.75 -> "0.75".
static func _factor(x: float) -> String:
	var r := snappedf(x, 0.01)
	if is_equal_approx(r, roundf(r)):
		return str(roundi(r))
	return ("%.2f" % r).rstrip("0")
