class_name MatchFlyRules
extends DriftPastRules
## "Match the fly": Drift past, then multiplied by how well the tied-on fly
## matches what the fish is eating (REQ-0003).
##
##   take = (Lane + Landing + Drift) x Fly match
##   Fly match = 1 - selectivity x (1 - appetite)
##
## appetite is the fish's highest diet weight among the bugs the fly imitates
## (FishSpecies.appetite_for), so the right bug is x1 and a bug it doesn't eat
## keeps (1 - selectivity). The fly is a gate ("does this look like food?"),
## not one more bonus, so it scales the other three.


func pass_odds(fish: Fish, landed_at: Vector2, presentation: String, worst_slip: float, fly: FlyPattern = null) -> Dictionary:
	var s := shares(fish, landed_at, presentation, worst_slip)
	var match_factor := fish.species.fly_match(fly)
	var chance := clampf(s.sum * match_factor, 0.0, 1.0)
	return {
		"chance": chance,
		"match": match_factor,
		"text": "(%s) × %s %s = %d%%" % [s.text, match_label(fish, fly), _factor(match_factor), _pct(chance)],
	}


## The bug that matched ("PMD"), or "No match" when the fish eats none of what
## the fly imitates. With nothing tied on, "Any fly".
static func match_label(fish: Fish, fly: FlyPattern) -> String:
	if fly == null:
		return "Any fly"
	var best := fish.species.appetite_for(fly)
	var insect: Insect = best.insect
	return insect.display_name if insect != null else "No match"


## 1 -> "1", 0.5 -> "0.5", 0.75 -> "0.75".
static func _factor(x: float) -> String:
	var r := snappedf(x, 0.01)
	if is_equal_approx(r, roundf(r)):
		return str(roundi(r))
	return ("%.2f" % r).rstrip("0")
