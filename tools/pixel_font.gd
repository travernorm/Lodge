extends RefCounted
## A tiny 3x5 pixel font for labelling images that tools write headless
## (river preview plates), where no font can be rasterised. Capitals, digits
## and a few marks; anything else is drawn as a space.

const W := 3
const H := 5
const GLYPHS := {
	"0": ["111", "101", "101", "101", "111"], "1": ["010", "110", "010", "010", "111"],
	"2": ["111", "001", "111", "100", "111"], "3": ["111", "001", "111", "001", "111"],
	"4": ["101", "101", "111", "001", "001"], "5": ["111", "100", "111", "001", "111"],
	"6": ["111", "100", "111", "101", "111"], "7": ["111", "001", "010", "010", "010"],
	"8": ["111", "101", "111", "101", "111"], "9": ["111", "101", "111", "001", "111"],
	"A": ["010", "101", "111", "101", "101"], "B": ["110", "101", "110", "101", "110"],
	"C": ["011", "100", "100", "100", "011"], "D": ["110", "101", "101", "101", "110"],
	"E": ["111", "100", "110", "100", "111"], "F": ["111", "100", "110", "100", "100"],
	"G": ["011", "100", "101", "101", "011"], "H": ["101", "101", "111", "101", "101"],
	"I": ["111", "010", "010", "010", "111"], "J": ["001", "001", "001", "101", "010"],
	"K": ["101", "101", "110", "101", "101"], "L": ["100", "100", "100", "100", "111"],
	"M": ["101", "111", "111", "101", "101"], "N": ["110", "101", "101", "101", "101"],
	"O": ["010", "101", "101", "101", "010"], "P": ["110", "101", "110", "100", "100"],
	"Q": ["010", "101", "101", "110", "011"], "R": ["110", "101", "110", "101", "101"],
	"S": ["011", "100", "010", "001", "110"], "T": ["111", "010", "010", "010", "010"],
	"U": ["101", "101", "101", "101", "111"], "V": ["101", "101", "101", "101", "010"],
	"W": ["101", "101", "111", "111", "101"], "X": ["101", "101", "010", "101", "101"],
	"Y": ["101", "101", "010", "010", "010"], "Z": ["111", "001", "010", "100", "111"],
	"-": ["000", "000", "111", "000", "000"], ".": ["000", "000", "000", "000", "010"],
	":": ["000", "010", "000", "010", "000"], "/": ["001", "001", "010", "100", "100"],
	"(": ["010", "100", "100", "100", "010"], ")": ["010", "001", "001", "001", "010"],
}


## Width in pixels of `text` drawn at `scale`.
static func width(text: String, scale := 1) -> int:
	return maxi(text.length() * (W + 1) - 1, 0) * scale


## Draws `text` with its top-left at `at`, with a one-pixel dark outline so it
## reads on water and grass alike.
static func draw(img: Image, at: Vector2i, text: String, color: Color, scale := 1,
		outline := Color(0, 0, 0, 0.75)) -> void:
	var up := text.to_upper()
	for pass_n in 2:
		var x := at.x
		for ch in up:
			var rows: Array = GLYPHS.get(ch, [])
			for r in rows.size():
				for c in W:
					if String(rows[r])[c] != "1":
						continue
					var px := x + c * scale
					var py := at.y + r * scale
					if pass_n == 0:
						_fill(img, Rect2i(px - 1, py - 1, scale + 2, scale + 2), outline)
					else:
						_fill(img, Rect2i(px, py, scale, scale), color)
			x += (W + 1) * scale


static func _fill(img: Image, r: Rect2i, color: Color) -> void:
	var clip := r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if clip.size.x > 0 and clip.size.y > 0:
		img.fill_rect(clip, color)
