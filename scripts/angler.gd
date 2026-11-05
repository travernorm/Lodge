class_name Angler
extends Node2D
## The angler on the bank (step A2, split from stream_scene.gd): where he
## stands, walking along the bank and over bridges without stepping into the
## water (Footing), and turning to face the river. His sprite and rod are
## drawn by an AnglerView child.
##
## The stream scene owns him: it hands him the river with setup(), the stick
## each frame with step(), and the rod to draw with show_rod(). He reads the
## river and changes nothing else. Positions are pixels (the scene's space);
## the river is asked in metres through WorldScale.

## Walking speed (px/s, 8 px = 1 m). 60 = 7.5 m/s, raised 1.5x from 40 so the bank feels less sluggish.
const SPEED := 60.0
## How quickly the angler turns to face the water (per second).
const TURN_SPEED := 4.0

## Where his feet are (px).
var feet := Vector2.ZERO
## Which way he faces (unit vector, screen space).
var facing := Vector2.UP
## Draws him (Traver's sprite) and the rod.
var view: AnglerView

var _river: RiverField
## The world's size (px), and whether the river winds (a stretch) or is the
## one-screen test stream, where he only walks along the near bank.
var _world := Vector2.ZERO
var _winding := false


func _init() -> void:
	view = AnglerView.add_to(self)


func setup(river: RiverField, world: Vector2, winding: bool, start: Vector2) -> void:
	_river = river
	_world = world
	_winding = winding
	feet = start
	facing = water_direction() if winding else Vector2.UP


## One frame of walking: `move` is the stick (-1..1 per axis); `can_walk` is
## false while line is out.
func step(delta: float, move: Vector2, can_walk: bool) -> void:
	if not can_walk:
		move = Vector2.ZERO
	if not _winding:
		feet.x = clampf(feet.x + move.x * SPEED * delta, 12.0, _world.x - 12.0)
		return
	_walk(move * SPEED * delta)
	if can_walk:
		var target := water_direction()
		facing = Vector2.from_angle(lerp_angle(facing.angle(), target.angle(), minf(1.0, TURN_SPEED * delta)))


## Which way he faces, as an angle from straight up the screen.
func facing_angle() -> float:
	return Vector2.UP.angle_to(facing)


func hand_position() -> Vector2:
	return feet + Vector2(3, -9)


## Draws him with the rod from his hand to `tip` (px); `butt` and `arm` pose
## the rod during a cast (cast look B).
func show_rod(tip: Vector2, butt: Vector2, arm: bool) -> void:
	view.show_angler(feet, facing, hand_position(), tip, butt, arm)


## The direction from his hand to the middle of the nearest river; on a
## bridge deck, downstream.
func water_direction() -> Vector2:
	var me := WorldScale.vec_to_m(hand_position())
	var k := _river.nearest_centre(me)
	if k < 0:
		return Vector2.UP
	if Footing.on_deck(_river, WorldScale.vec_to_m(feet)):
		return _river.centre_dir[k]
	var dir := _river.centre[k] - me
	return dir.normalized() if dir.length() > 0.01 else Vector2.UP


## Walks, sliding along the bank instead of into the water.
func _walk(move: Vector2) -> void:
	for axis in [Vector2(move.x, 0.0), Vector2(0.0, move.y)]:
		var next: Vector2 = feet + axis
		if axis != Vector2.ZERO and _walkable(next):
			feet = next


func _walkable(p: Vector2) -> bool:
	if p.x < 8.0 or p.y < 20.0 or p.x > _world.x - 8.0 or p.y > _world.y - 4.0:
		return false
	for o in [Vector2(-3, 0), Vector2(3, 0), Vector2(0, -4)]:
		if not Footing.can_stand(_river, WorldScale.vec_to_m(p + o)):
			return false
	return true
