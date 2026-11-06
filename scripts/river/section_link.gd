class_name SectionLink
extends Resource
## A way from one section of river to another (REQ-0014): walk into `exit` in
## section `from` and, after a short fade, arrive at `arrive_at` in section
## `to`. One link is one direction; the way back is another link.
##
## Links live on the River, not on each Stretch, so two sections that lead to
## each other don't load each other in a loop. Metres, in each section's own map.

## The section this link leaves.
@export var from: Stretch
## Where the angler leaves (m): a band at the edge of `from`'s map.
@export var exit := Rect2()
## The section it leads to.
@export var to: Stretch
## Where the angler arrives in `to` (m), on dry land and clear of its exits.
@export var arrive_at := Vector2.ZERO
