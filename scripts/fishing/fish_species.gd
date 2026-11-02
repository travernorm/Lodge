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

@export_group("What it eats")
## Fly ids this fish takes readily.
@export var preferred_flies := PackedStringArray()
## Chance it takes a preferred fly on a clean drift.
@export_range(0.0, 1.0) var take_chance := 0.85
## Chance it takes any other fly.
@export_range(0.0, 1.0) var off_pattern_take := 0.15
## Drag above this and it refuses.
@export_range(0.0, 1.0) var drag_tolerance := 0.25

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
