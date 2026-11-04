class_name SpawnEntry
extends Resource
## One line of a stretch's spawn table (Stretch.spawn): a species that lives in
## this water, how common it is here and when it's here (REQ-0007). The
## species itself carries nothing about any place, so one species can live in
## many stretches (R12). FishGenerator turns the table into fish.

@export var species: FishSpecies
## How common it is here, 0 to 1. Each fish picks among the species that are
## here today, weighted by this.
@export_range(0.01, 1.0) var abundance := 0.5
## When in the year it's in this water (a salmon run, say). Empty means all
## year.
@export var window: SeasonWindow
