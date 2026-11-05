class_name CastLook
extends Resource
## How the angler's rod (and arm) move through a cast on screen: a feel
## experiment with versions side by side. CastPose does the sums, AnglerView
## draws. Edit data/cast_looks/*.tres in the Inspector. Practice mode steps the
## style live (Square / M while the line is in).
##
## Angles are the rod's tilt in its casting plane, in degrees from straight up:
## positive leans toward the target (in front of him), negative behind him. On a
## clock face with the target on the left, 50 is about 10 o'clock and -35 about
## 1 o'clock.

enum Style {
	SNAP,    ## Today: the rod jumps between three poses.
	SWEEP,   ## A: the rod sweeps smoothly through the stroke and bends under load.
	CUTOUT,  ## B: a cutout forearm and the rod snap together to a few fixed angles.
}

## Which version the game starts on.
@export var style := Style.SNAP

@export_group("Stroke")
## Where the forward stroke stops (and the back stroke starts).
@export_range(0.0, 90.0) var forward_stop_deg := 50.0
## Where the back stroke stops.
@export_range(-90.0, 0.0) var back_stop_deg := -35.0
## How much further back the rod drifts while a back cast is held past its ideal.
@export_range(0.0, 45.0) var late_drift_deg := 15.0
## How low the rod follows through as the fly flies out.
@export_range(0.0, 90.0) var follow_through_deg := 75.0
## Ease of each stroke: 1 is even speed; higher starts slow and snaps to the stop.
@export_range(1.0, 4.0) var stroke_ease := 2.2

@export_group("Projection")
## How much the rod's height shows as screen "up" (the camera looks down from
## behind and above): 0 is straight down, 1 is side on.
@export_range(0.0, 1.0) var height_show := 0.8
## How far the casting plane tilts out to his rod side (0 = straight overhead).
@export_range(0.0, 1.0) var side_lean := 0.35

@export_group("A: sweep")
## How far the tip lags behind the butt mid-stroke, in degrees: the rod bends
## under the line's load, most in the middle of the stroke.
@export_range(0.0, 40.0) var max_bend_deg := 16.0

@export_group("B: cutout")
## The fixed angles the forearm and rod snap to, from the back stop forward.
@export var snap_angles_deg := PackedFloat32Array([-35.0, -5.0, 25.0, 50.0, 75.0])


## The name shown on screen for a style.
static func style_name(s: Style) -> String:
	return ["Off: snap poses (today)", "A: rod sweep", "B: cutout arm"][s]
