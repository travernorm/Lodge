class_name SpawnEntry
extends Resource
## One line of a stretch's spawn table (Stretch.spawn): which species lives in
## this water and how many. The species itself carries nothing about any place,
## so one species can live in many stretches (R12, REQ-0004 C2). Each fish
## takes its own lie from the river field.

@export var species: FishSpecies
@export_range(1, 20) var count := 1
