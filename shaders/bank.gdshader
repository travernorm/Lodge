shader_type canvas_item;
// The shoreline (REQ-0013), drawn by BankView. The data texture is the river
// field baked one texel per cell: R = metres from the water, G = cut bank face
// height, B = how far gravel reaches past this point, A = wet. Each pixel
// picks its ground the way BankZones.zone() does, with a wobble added so the
// edges are ragged: the face, then the wet line, gravel, sand, plain ground.

uniform sampler2D data : filter_linear, repeat_disable;
uniform vec2 field_cells = vec2(1.0);
uniform float cell_px = 2.0;
// Where the data texture's first cell sits (world px): 0 for a whole
// stretch, the chunk's corner for a chunk of a section (REQ-0014).
uniform vec2 field_origin = vec2(0.0);
uniform float px_per_m = 8.0;
uniform float shore_range = 8.0;
uniform float face_range = 4.0;
uniform float reach_low = -2.0;
uniform float reach_range = 8.0;

uniform sampler2D face_tex : source_color, filter_nearest, repeat_enable;
uniform sampler2D wet_tex : source_color, filter_nearest, repeat_enable;
uniform sampler2D gravel_tex : source_color, filter_nearest, repeat_enable;
uniform sampler2D sand_tex : source_color, filter_nearest, repeat_enable;
uniform bool has_wet = false;
uniform bool has_gravel = false;
uniform bool has_sand = false;

uniform vec4 wet_tint : source_color = vec4(0.37, 0.34, 0.27, 1.0);
uniform vec4 gravel_tint : source_color = vec4(0.54, 0.49, 0.38, 1.0);
uniform vec4 sand_tint : source_color = vec4(0.66, 0.59, 0.43, 1.0);
uniform vec4 ground_tint : source_color = vec4(0.29, 0.42, 0.23, 1.0);
uniform vec4 tuft_tint : source_color = vec4(0.37, 0.52, 0.27, 1.0);
uniform float tuft_density = 0.025;
uniform float pebble_density = 0.45;
uniform float pebble_px = 3.0;

// Rain on the ground (REQ-0015): 0 dry to 1 soaked, darker and richer.
uniform float wetness = 0.0;
uniform float wet_m = 0.25;
uniform float sand_m = 0.3;
uniform float face_height_m = 2.0;
uniform float lip_m = 0.625;
uniform float min_face_m = 0.375;
uniform float edge_noise_m = 0.25;
uniform float edge_noise_px = 12.0;

varying vec2 world_px;

void vertex() {
	world_px = VERTEX;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Placeholder ground until a texture is set: the tint with a scatter of small
// pebbles, each a lit top over a shadowed underside.
vec4 pebbles(vec2 p, vec4 base) {
	vec2 cell = floor(p / pebble_px);
	if (hash(cell) >= pebble_density) {
		return base;
	}
	vec2 o = floor(vec2(hash(cell + 3.1), hash(cell + 7.7)) * (pebble_px - 1.0));
	vec2 q = floor(p - cell * pebble_px - o);
	if (q.y == 0.0 && q.x >= 0.0 && q.x <= 1.0) {
		return vec4(min(base.rgb * 1.22, vec3(1.0)), 1.0);
	}
	if (q.y == 1.0 && q.x >= 0.0 && q.x <= 1.0) {
		return vec4(base.rgb * 0.7, 1.0);
	}
	return base;
}

vec4 ground(sampler2D tex, bool has_tex, vec4 tint, vec2 p) {
	if (has_tex) {
		return texture(tex, p / vec2(textureSize(tex, 0))) * tint;
	}
	return pebbles(p, tint);
}

void fragment() {
	vec2 p = floor(world_px) + 0.5;
	vec2 uv = ((p - field_origin) / cell_px + 0.5) / field_cells;
	vec4 f = texture(data, uv);
	if (f.a >= 0.35) {
		discard;  // water: the WaterView paints it
	}
	float shore = f.r * shore_range;
	float face = f.g * face_range;
	float reach = f.b * reach_range + reach_low;
	float n = (value_noise(p / edge_noise_px) - 0.5) * 2.0 * edge_noise_m;

	if (face >= min_face_m && shore + n < face) {
		// The strip runs along the bank: across it by distance from the water,
		// along it by x on a bank that runs across the screen, y on one that
		// runs up it. The grass lip stays whole where the face tapers off.
		vec2 ex = vec2(1.0 / field_cells.x, 0.0);
		vec2 ey = vec2(0.0, 1.0 / field_cells.y);
		float gx = texture(data, uv + ex).r - texture(data, uv - ex).r;
		float gy = texture(data, uv + ey).r - texture(data, uv - ey).r;
		float u = abs(gy) >= abs(gx) ? p.x : p.y;
		float from_top = face - shore;
		float v = from_top < lip_m ? from_top / face_height_m : 1.0 - shore / face_height_m;
		vec2 ts = vec2(textureSize(face_tex, 0));
		float row = clamp(floor(v * ts.y), 0.0, ts.y - 1.0);
		COLOR = texture(face_tex, vec2(floor(u) / ts.x, (row + 0.5) / ts.y));
	} else if (shore + n < wet_m) {
		COLOR = ground(wet_tex, has_wet, wet_tint, p);
	} else if (n < reach - sand_m) {
		COLOR = ground(gravel_tex, has_gravel, gravel_tint, p);
	} else if (n < reach) {
		COLOR = ground(sand_tex, has_sand, sand_tint, p);
	} else {
		COLOR = hash(p) < tuft_density ? tuft_tint : ground_tint;
	}
	if (wetness > 0.0) {
		float grey = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
		COLOR.rgb = mix(COLOR.rgb, mix(vec3(grey), COLOR.rgb, 1.15) * 0.84, wetness);
	}
}
