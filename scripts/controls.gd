extends Node
## Lodge control names and stick helpers, loaded as the `Controls` autoload.
##
## Steam Deck / Xbox-style layout:
##   L bumper (LB)   cast_back     hold to time the back cast
##   R bumper (RB)   cast_forward  overlap with L to shoot the forward cast
##   Right stick     rod_*         mend loops, set the hook, strip and twitch the fly
##   X (Square)      mend          flip the line's belly upstream, same as a stick loop
##   Left stick/D-pad move_*       walk the bank
##   A               interact      sets the hook while fishing; later perception checks, talk
##   Y               change_fly    open the fly box (next fly) while reeled in
##   L2 (L trigger)  change_rod    next rod while reeled in (a stand-in for a gear screen)
##   B               back          cancel or reel in
##   Start/Menu      pause
##   L3 (click left stick)   practice_mode  casting practice range on/off
##   R3 (click right stick)  cycle_rules    switch casting rule set
##   Select/View     toggle_debug  cycle debug views (controller, read the water)
##
## Keyboard fallbacks (for working on a laptop): WASD move, IJKL rod, Q = L bumper,
## E = R bumper, M mend, Space interact / set hook, Backspace back, F change fly, R change rod, Esc pause, F1 debug,
## T practice mode, Tab switch casting rules.

const CAST_BACK := &"cast_back"
const CAST_FORWARD := &"cast_forward"
const MEND := &"mend"
const INTERACT := &"interact"
const CHANGE_FLY := &"change_fly"
const CHANGE_ROD := &"change_rod"
const PRACTICE_MODE := &"practice_mode"
const CYCLE_RULES := &"cycle_rules"
const BACK := &"back"
const PAUSE := &"pause"
const TOGGLE_DEBUG := &"toggle_debug"

const ALL_ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down",
	&"rod_left", &"rod_right", &"rod_up", &"rod_down",
	CAST_BACK, CAST_FORWARD, MEND, INTERACT, CHANGE_FLY, CHANGE_ROD, BACK, PAUSE, TOGGLE_DEBUG, PRACTICE_MODE, CYCLE_RULES,
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
