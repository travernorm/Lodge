class_name DietEntry
extends Resource
## One line of a fish's diet (FishSpecies.diet): a bug it eats and how much it
## wants it, 0 to 1. A typed link to the insect file, so a typo can't slip
## through and the inspector shows a picker (R5, REQ-0004 C2). Later a hatch
## raises the weight of whatever is coming off.

@export var insect: Insect
@export_range(0.0, 1.0) var weight := 1.0
