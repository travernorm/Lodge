class_name WorldRoot
extends Node
## The game's root (REQ-0014): plays one section of river at a time from the
## world map, and when the angler walks into a section's exit, fades out,
## swaps in the next section at its arrival point with the same day, tackle
## and catches, and fades back in. Each section is scenes/main.tscn with its
## stretch set; the world root calls it down and listens for section_exit.

## How long each half of the fade lasts (s): well under a second in all.
const FADE_S := 0.3

@export var world: WorldMap = preload("res://data/world.tres")
@export var section_scene: PackedScene = preload("res://scenes/main.tscn")

## The section being played (a stream scene).
var section: Node
var _fade := ColorRect.new()
var _swapping := false


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade)
	_enter(world.start, Vector2.INF, null)


## Swaps to `link.to`, behind a fade.
func _on_section_exit(link: SectionLink) -> void:
	if _swapping:
		return
	_swapping = true
	var out := create_tween()
	out.tween_property(_fade, ^"color:a", 1.0, FADE_S)
	await out.finished
	var old := section
	_enter(link.to, link.arrive_at, old)
	old.queue_free()
	var back := create_tween()
	back.tween_property(_fade, ^"color:a", 0.0, FADE_S)
	await back.finished
	_swapping = false


## Makes and adds the section for `stretch`, the angler at `arrive_at` (m;
## INF for its angler_start), carrying the day from `old` when there is one.
func _enter(stretch: Stretch, arrive_at: Vector2, old: Node) -> void:
	var next := section_scene.instantiate()
	next.stretch = stretch
	next.arrive_at = arrive_at
	next.links = world.links_from(stretch)
	if old != null and old.fishing() != null and next.fishing() != null:
		next.fishing().take_session(old.fishing())
	next.section_exit.connect(_on_section_exit)
	if old != null:
		remove_child(old)
	add_child(next)
	section = next
