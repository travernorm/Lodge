@tool
class_name BankLook
extends Resource
## How the shoreline looks (REQ-0013): the land between the water and the
## grass. BankView paints it from the river field with BankZones deciding where
## each kind of ground goes. Traver tunes it in the Inspector, like the water
## and grass looks.
##
## From the water out: a thin wet line, dry gravel (wide on the inside of a
## bend, the point bar), a sand fringe, then the grassy ground. On the outside
## of a bend the cut bank face replaces them: `cut_bank` is a strip that
## repeats along the bank, grass lip at the top, mud at the bottom.
##
## Art: empty texture slots draw placeholder pebbles in the tint instead.

## The cut bank face strip (repeats along the bank). Empty = no face, gravel instead.
@export var cut_bank: Texture2D
## Seamless textures for each ground; empty = placeholder pebbles in the tint.
@export var wet_stones: Texture2D
@export var gravel: Texture2D
@export var sand: Texture2D

@export_group("Colours")
## Multiplies a texture, or is the placeholder colour when there is none.
@export var wet_tint := Color("5e5644")
@export var gravel_tint := Color("8a7e62")
@export var sand_tint := Color("a8976d")
## The plain ground under the grass, and the odd lighter tuft in it.
@export var ground_tint := Color("4b6b3a")
@export var tuft_tint := Color("5f8446")
@export_range(0.0, 0.3) var tuft_density := 0.025
## Placeholder pebbles: how many cells hold one (0 to 1) and the cell size (m).
@export_range(0.0, 1.0) var pebble_density := 0.45
@export_range(0.25, 2.0) var pebble_size_m := 0.375

@export_group("Widths")
## The wet line at the water's edge (m).
@export_range(0.0, 2.0) var wet_width_m := 0.25
## Dry gravel along a straight bank (m from the water).
@export_range(0.0, 4.0) var gravel_width_m := 0.75
## Extra gravel on a point bar (m, at the tightest bend).
@export_range(0.0, 8.0) var point_bar_m := 3.0
## The sand fringe at the outer edge of the gravel (m).
@export_range(0.0, 2.0) var sand_width_m := 0.3

@export_group("Cut bank")
## How strongly a bank must be on the outside of a bend (bend 0 to 1) before
## the face starts, and where it reaches full height.
@export_range(0.0, 1.0) var cut_bend_start := 0.2
@export_range(0.0, 1.0) var cut_bend_full := 0.5
## The face's full height on screen (m). 2 m shows a 16 px strip pixel for pixel.
@export_range(0.5, 4.0) var face_height_m := 2.0
## The top of the strip (m) kept whole where the face tapers off: the grass lip.
@export_range(0.0, 2.0) var lip_m := 0.625
## Narrower than this (m), the face gives way to gravel.
@export_range(0.0, 2.0) var min_face_m := 0.375

@export_group("Edges")
## How ragged the edges between grounds are (m either way) and the size of the wobble (m).
@export_range(0.0, 1.0) var edge_noise_m := 0.25
@export_range(0.25, 8.0) var edge_noise_size_m := 1.5
