class_name FishSpecies
extends Resource
## One kind of fish. Each species is a .tres file in data/fish/. It describes
## only the fish; where it lives and how many is each stretch's spawn table
## (Stretch.spawn), so a species can live in any river (R12).

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
@export var color := Color("4a5a3a")

@export_group("Biting")
## Chance it bites a perfect pass: the fly comes through its lane after a
## delicate landing nearby, with no drag, and matches its food. The bite rules
## (DriftPastRules) split it into lane, landing and drift shares.
@export_range(0.0, 1.0) var bite_chance := 0.6
## What it's feeding on: each entry is a bug (data/insects/) and how much it
## wants it, 0 to 1. A stand-in until hatches exist; later the hatch raises the
## weight of whatever is coming off.
@export var diet: Array[DietEntry] = []
## How much it cares that the fly looks like its food. 0 takes anything drifted
## well; 1 takes only the right bug. A fly it doesn't eat keeps
## (1 - selectivity) of the odds under the bite rules.
@export_range(0.0, 1.0) var selectivity := 0.5

@export_group("Hook set")
## Seconds after the take. Set sooner and you pull the fly away; later and it spits the fly.
@export var set_min := 0.15
@export var set_max := 0.6

@export_group("Fight")
## How hard it pulls on a run. Around 1.0 will snap the tippet under full pressure.
@export_range(0.0, 1.5) var pull := 0.7
## Higher means it takes longer to tire.
@export var toughness := 1.0
@export var min_length_in := 8.0
@export var max_length_in := 14.0


## How much this fish wants `fly`: its highest diet weight among the bugs the
## fly imitates. Returns {appetite (0 to 1), insect (the best match, or null)}.
func appetite_for(fly: FlyPattern) -> Dictionary:
	var best := {"appetite": 0.0, "insect": null}
	if fly == null:
		return best
	for insect in fly.imitates:
		if insect == null:
			continue
		var want := wants(insect)
		if want > best.appetite:
			best = {"appetite": want, "insect": insect}
	return best


## How much it wants one bug, 0 to 1 (0 when it isn't in the diet).
func wants(insect: Insect) -> float:
	var best := 0.0
	for entry in diet:
		if entry != null and entry.insect == insect:
			best = maxf(best, clampf(entry.weight, 0.0, 1.0))
	return best


## The fly match factor: 1 - selectivity x (1 - appetite). The right bug is x1,
## a bug it doesn't eat is x(1 - selectivity). No fly tied on counts as x1.
func fly_match(fly: FlyPattern) -> float:
	if fly == null:
		return 1.0
	return 1.0 - selectivity * (1.0 - float(appetite_for(fly).appetite))
