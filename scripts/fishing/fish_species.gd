class_name FishSpecies
extends Resource
## One kind of fish. Each species is a .tres file in data/fish/.

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
@export var color := Color("4a5a3a")

@export_group("Where it lives")
## Area of the test stream (screen px) where this fish picks its lie.
@export var lie_area := Rect2(0, 60, 320, 80)

@export_group("Biting")
## Chance it bites a delicate cast landing right by it. Fair landings get 60% of
## this and splashy ones 25%, and it falls off with distance out to bite_range.
@export_range(0.0, 1.0) var bite_chance := 0.6
## Casts landing farther than this (px) from the fish never get a bite.
@export var bite_range := 40.0
## Fly ids this fish likes. Not used for bites yet; kept for when the fly box returns.
@export var preferred_flies := PackedStringArray()

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
