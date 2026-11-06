class_name WorldMap
extends Resource
## Every river in the game and where a new game starts (REQ-0014).
## data/world.tres is the one the game loads.

@export var rivers: Array[River] = []
## The section a new game starts in, at its angler_start.
@export var start: Stretch


## The links that leave `section`, from whichever river holds it.
func links_from(section: Stretch) -> Array[SectionLink]:
	var out: Array[SectionLink] = []
	for r in rivers:
		out.append_array(r.links_from(section))
	return out


## The river a section belongs to, or null.
func river_of(section: Stretch) -> River:
	for r in rivers:
		if section in r.sections:
			return r
	return null
