class_name River
extends Resource
## A river as the world knows it (REQ-0014): its sections in order, upstream
## first, and the links between them. Each section is a Stretch with its own
## map; walking off one end of a section fades into the next.

@export var display_name := ""
## Its sections, upstream first.
@export var sections: Array[Stretch] = []
## The ways between them, each one direction.
@export var links: Array[SectionLink] = []


## The links that leave `section`.
func links_from(section: Stretch) -> Array[SectionLink]:
	var out: Array[SectionLink] = []
	for link in links:
		if link.from == section:
			out.append(link)
	return out
