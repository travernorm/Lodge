class_name HabitatEntry
extends Resource
## One line of a fish's habitat (FishSpecies.habitat, REQ-0010): a kind of
## water and how much it likes it, 0 to 1. In the fish sheet it reads like the
## diet: Pool:1;Pocket:0.8.

@export var type: WaterTypeRules.WaterType = WaterTypeRules.WaterType.RUN
@export_range(0.0, 1.0) var weight := 1.0
