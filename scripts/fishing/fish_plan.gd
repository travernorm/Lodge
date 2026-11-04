class_name FishPlan
extends RefCounted
## One fish the generator placed (REQ-0007): what it is, how big, where it
## holds and how keen it is to rise today. The fishing node turns each plan
## into a Fish.

var species: FishSpecies
var length_in := 0.0
## Its home lie (m). A fish that breaks off comes back here.
var lie := Vector2.ZERO
## The river field's lie score there, 0 to 1.
var lie_score := 0.0
## On a resting lie (deep, slow, covered) rather than a feeding lie
## (REQ-0011). Resting fish are slow to come up for a dry fly.
var resting := false
## 0 to 1: how often it rises (FishGenerator.activity()).
var activity := 1.0
## The kind of water its lie is in (a WaterTypeRules.WaterType), or
## WaterTypes.NONE (REQ-0010).
var water_type := WaterTypes.NONE


func _init(p_species: FishSpecies = null, p_length_in := 0.0, p_lie := Vector2.ZERO,
		p_lie_score := 0.0, p_activity := 1.0, p_water_type := WaterTypes.NONE) -> void:
	species = p_species
	length_in = p_length_in
	lie = p_lie
	lie_score = p_lie_score
	activity = p_activity
	water_type = p_water_type
