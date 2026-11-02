class_name Insect
extends Resource
## One kind of bug a trout eats, or `attractor` for flies that copy nothing.
## Each is a .tres file in data/insects/. It's the one shared key that a fly
## (FlyPattern.imitates), a fish's diet (FishSpecies.diet) and, later, a hatch
## all point at, so they can't disagree. Ids come from the hatch table in
## docs/SPECIES_AND_CONDITIONS.md; never rename or reuse one.

@export var id: StringName
## Shown on the odds line when a fly matches, e.g. "PMD 1".
@export var display_name := ""
## The family, lower case, shown when you tie a fly on: mayfly, caddis,
## stonefly, terrestrial, attractor ...
@export var kind := ""
