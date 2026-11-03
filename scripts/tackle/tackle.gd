class_name Tackle
extends RefCounted
## What the angler has rigged up: one rod and one fly (REQ-0005). The only
## writer of which rod and fly are on (R2). The fishing node owns one and hands
## the rod to the cast and the fight.
##
## The fly box only offers flies the rod can throw (FlyRod.throws()). Changing
## rods keeps the fly if the new rod throws it, otherwise ties on the first one
## it does. With no fly it can throw, fly() is null.

## Every rod and fly there is, in catalog order. Read-only data.
var rods: Array[FlyRod] = []
var flies: Array[FlyPattern] = []
var rod_index := 0
## Index into `flies`, or -1 when the rod throws none of them.
var fly_index := -1


func _init(p_rods: Array[FlyRod], p_flies: Array[FlyPattern]) -> void:
	rods = p_rods
	flies = p_flies
	_fit_fly()


## The rod that's rigged, or null with no rods at all.
func rod() -> FlyRod:
	return rods[rod_index] if rod_index < rods.size() else null


## The fly that's tied on, or null when the rod throws none in the box.
func fly() -> FlyPattern:
	return flies[fly_index] if fly_index >= 0 and fly_index < flies.size() else null


## Whether the rigged rod throws `fly`. With no rods at all, every fly works.
func fits(p_fly: FlyPattern) -> bool:
	var r := rod()
	return p_fly != null and (r == null or r.throws(p_fly))


## The flies this rod throws, in fly box order.
func usable_flies() -> Array[FlyPattern]:
	var out: Array[FlyPattern] = []
	for f in flies:
		if fits(f):
			out.append(f)
	return out


## Ties on the next fly the rod throws. Returns false when there's no other.
func next_fly() -> bool:
	for step in range(1, flies.size() + 1):
		var i := posmod(fly_index + step, flies.size())
		if i != fly_index and fits(flies[i]):
			fly_index = i
			return true
	return false


## Rigs the next rod, then keeps the fly if it fits or ties on the first that
## does. Returns false when there's no other rod.
func next_rod() -> bool:
	if rods.size() < 2:
		return false
	rod_index = (rod_index + 1) % rods.size()
	_fit_fly()
	return true


## Y: ties on the next fly and says so.
func cycle_fly() -> String:
	if next_fly():
		return tied_on_text()
	return "Just the one fly for this rod." if fly() != null else "No fly in the box suits this rod."


## L2: rigs the next rod and says what it does.
func cycle_rod() -> String:
	if not next_rod():
		return "Just the one rod for now."
	var r := rod()
	if fly() == null:
		return "%s: %s. No fly in the box suits it." % [r.display_name, r.types_text()]
	return r.stats_text()


## "Tied on a Parachute Adams (mayfly)."
func tied_on_text() -> String:
	var f := fly()
	if f == null:
		return "No fly in the box suits this rod."
	var kinds := f.kinds_text()
	return "Tied on a %s%s." % [f.display_name, " (%s)" % kinds if kinds != "" else ""]


func _fit_fly() -> void:
	if fly_index >= 0 and fly_index < flies.size() and fits(flies[fly_index]):
		return
	fly_index = -1
	for i in flies.size():
		if fits(flies[i]):
			fly_index = i
			return
