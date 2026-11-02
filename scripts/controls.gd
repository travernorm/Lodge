extends Node
## Lodge control names and stick helpers, loaded as the `Controls` autoload.
##
## Steam Deck / Xbox-style layout:
##   R bumper (RB)   cast_back     hold to time the back cast
##   L bumper (LB)   cast_forward  overlap with R to shoot the forward cast
##   Right stick     rod_*         mend loops, set the hook, strip and twitch the fly
##   Left stick/D-pad move_*       walk the bank
##   A               interact      perception checks, talk, confirm
##   Y               change_fly    open the fly box (next fly) while reeled in
##   B               back          cancel or reel in
##   Start/Menu      pause
##   Select/View     toggle_debug  controller debug overlay
##
## Keyboard fallbacks (for working on a laptop): WASD move, IJKL rod, E = R bumper,
## Q = L bumper, Space interact, Backspace back, F change fly, Esc pause, F1 debug.

const CAST_BACK := &"cast_back"
const CAST_FORWARD := &"cast_forward"
const INTERACT := &"interact"
const CHANGE_FLY := &"change_fly"
const BACK := &"back"
const PAUSE := &"pause"
const TOGGLE_DEBUG := &"toggle_debug"

const ALL_ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down",
	&"rod_left", &"rod_right", &"rod_up", &"rod_down",
	CAST_BACK, CAST_FORWARD, INTERACT, CHANGE_FLY, BACK, PAUSE, TOGGLE_DEBUG,
]


func move_vector() -> Vector2:
	return Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")


## Right stick. This drives the rod tip: mending, hook sets and retrieves.
func rod_vector() -> Vector2:
	return Input.get_vector(&"rod_left", &"rod_right", &"rod_up", &"rod_down")


func pad_name() -> String:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		return "keyboard"
	return Input.get_joy_name(pads[0])


## Short rumble. Silently does nothing without a pad.
func rumble(weak: float, strong: float, seconds: float) -> void:
	for pad in Input.get_connected_joypads():
		Input.start_joy_vibration(pad, weak, strong, seconds)
