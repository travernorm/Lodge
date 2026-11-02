class_name DriftPastRules
extends TakeRules
## "Drift past": a fish judges the fly as it drifts past, not where it landed.
##
## When the fly comes within window_m of a fish, that's a pass. The fish rolls
## once per pass, as the fly is closest to it (right away if the fly landed on
## top of it). The chance is the species' bite_chance, split three ways:
##
##   In lane    the fly came through the fish's window at all
##   Landing    a delicate landing near the fish (a fair one gets half). A
##              landing far upstream doesn't count either way, and a splashy
##              one is never punished, so casting onto a fish is fine
##   Drift      the fly rode the current through the pass, judged by its worst
##              moment: drag, skating or the jolt of an early mend all move the
##              fly differently from the water under it (DriftModel.slip)

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


func rolls_on_landing() -> bool:
	return false


func landing_odds(_fish: Fish, _at: Vector2, presentation: String, _fly: FlyPattern = null) -> Dictionary:
	return {"chance": 0.0, "text": "%s landing" % presentation}


func window() -> float:
	return window_m


## The tied-on fly doesn't matter under these rules.
func pass_odds(fish: Fish, landed_at: Vector2, presentation: String, worst_slip: float, _fly: FlyPattern = null) -> Dictionary:
	var s := shares(fish, landed_at, presentation, worst_slip)
	var chance := clampf(s.sum, 0.0, 1.0)
	return {"chance": chance, "text": "%s = %d%%" % [s.text, _pct(chance)]}


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


func rise_delay() -> Vector2:
	return rise_delay_s


static func _pct(x: float) -> int:
	return roundi(x * 100.0)
