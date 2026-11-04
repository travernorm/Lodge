class_name WaterTypeRules
extends Resource
## How the river field's water is sorted into types an angler would name
## (REQ-0010): riffle, run, pool, tail-out, pocket, seam, eddy. Its one file is
## data/water_types.tres, so the thresholds can be tuned in the Inspector.
## WaterTypes does the sorting; species say which types they like
## (FishSpecies.habitat).
##
## Speeds are fractions of RiverField.WATER_SPEED; depth is the field's relative
## depth (0..1); distances are metres. WaterTypes checks eddy, pocket, seam,
## pool, tail-out and riffle in that order, first match wins; Run is the rest.

enum WaterType { RIFFLE, RUN, POOL, TAIL_OUT, POCKET, SEAM, EDDY }

## On-screen names, in enum order.
const LABELS: Array[String] = ["Riffle", "Run", "Pool", "Tail-out", "Pocket", "Seam", "Eddy"]

## A species' liking (0..1) for a water type its habitat doesn't list, so fish
## still turn up off their favourite water now and then.
@export_range(0.0, 1.0, 0.05) var stray_weight := 0.2

@export_group("Eddy")
## Water running back upstream at least this fast is an eddy.
@export_range(0.0, 0.2, 0.005) var eddy_back_speed := 0.02

@export_group("Pocket")
## Slow water no more than this far (m) downstream of something solid.
@export_range(0.25, 5.0, 0.25) var pocket_reach := 4.0
## Slower than this counts as slack behind the rock.
@export_range(0.0, 1.0, 0.01) var pocket_speed := 0.3

@export_group("Seam")
## Seam strength (0..1) from here up is a seam.
@export_range(0.0, 1.0, 0.01) var seam_min := 0.35

@export_group("Pool")
@export_range(0.0, 1.0, 0.01) var pool_depth := 0.6
@export_range(0.0, 1.0, 0.01) var pool_speed := 0.4

@export_group("Tail-out")
## Water at least this deep that shallows by tail_drop over tail_look metres
## downstream, with a pool within tail_reach metres upstream.
@export_range(0.0, 1.0, 0.01) var tail_min_depth := 0.2
@export_range(0.0, 1.0, 0.01) var tail_drop := 0.05
@export_range(0.5, 5.0, 0.25) var tail_look := 2.0
@export_range(1.0, 20.0, 0.5) var tail_reach := 8.0

@export_group("Riffle")
@export_range(0.0, 1.0, 0.01) var riffle_depth := 0.35
@export_range(0.0, 1.0, 0.01) var riffle_speed := 0.3


## The one rules file, loaded once (like Catalog.shared()).
const PATH := "res://data/water_types.tres"
static var _shared: WaterTypeRules


static func shared() -> WaterTypeRules:
	if _shared == null:
		_shared = load(PATH)
	return _shared


## The name shown on screen ("Tail-out").
static func label(t: int) -> String:
	return LABELS[t] if t >= 0 and t < LABELS.size() else "Bank"
