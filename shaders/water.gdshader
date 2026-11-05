// Paints the river from a WaterLook (scripts/river/water_look.gd).
// The field texture is the RiverField baked one texel per cell:
// R, G = current (m/s, encoded around 0.5), B = depth (0..1), A = wet.
// The edges texture holds distance to the bank (R) and to the nearest rock (G).
// See scripts/river/water_view.gd.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D field : filter_linear, repeat_disable;
uniform vec2 field_cells = vec2(1.0);
uniform float cell_px = 2.0;
// Where the field texture's first cell sits (world px): 0 for a whole
// stretch, the chunk's corner for a chunk of a section (REQ-0014).
uniform vec2 field_origin = vec2(0.0);
uniform float flow_range = 10.0;
uniform float water_speed = 1.0;

uniform sampler2D deep_tex : source_color, filter_nearest, repeat_enable;
uniform sampler2D mid_tex : source_color, filter_nearest, repeat_enable;
uniform sampler2D white_tex : source_color, filter_nearest, repeat_enable;
uniform vec4 deep_tint : source_color = vec4(1.0);
uniform vec4 mid_tint : source_color = vec4(1.0);
uniform vec4 white_tint : source_color = vec4(1.0);
uniform vec4 shallow_tint : source_color = vec4(0.49, 0.75, 0.86, 1.0);

uniform float deep_start = 0.6;
uniform float deep_softness = 0.18;
uniform float white_start = 0.7;
uniform float white_softness = 0.12;
uniform float shallow_depth = 0.12;
uniform float shallow_amount = 0.35;
uniform float edge_noise = 0.12;
uniform float edge_noise_px = 24.0;
uniform bool dither = false;
uniform float motion = 0.35;
uniform float motion_cycle = 3.0;
uniform float px_per_m = 8.0;
// Rain dimples (REQ-0009 version C), 0 = none. Set by WaterView.set_rain().
uniform float rain = 0.0;
uniform float rain_cell_px = 6.0;

// Palette look: colour by depth, textures add only their light/dark pattern.
uniform bool use_palette = false;
uniform sampler2D palette : source_color, filter_linear, repeat_disable;
uniform float texture_detail = 1.0;
uniform vec4 deep_mean : source_color = vec4(1.0);
uniform vec4 mid_mean : source_color = vec4(1.0);
uniform float wash_clear = 0.0;
// Riverbed seen through clear shallows.
uniform float bed_depth = 0.35;
uniform vec4 sand_tint : source_color = vec4(0.85, 0.8, 0.61, 1.0);
uniform float sand_amount = 0.0;
uniform vec4 stone_tint : source_color = vec4(0.44, 0.56, 0.6, 1.0);
uniform float stone_amount = 0.0;
uniform float stone_px = 8.0;
uniform float stone_density = 0.5;
// Foam lines along banks and around rocks.
uniform sampler2D edges : filter_linear, repeat_disable;
uniform float edge_range = 3.0;
uniform vec4 foam_tint : source_color = vec4(0.9, 0.96, 0.97, 1.0);
uniform float bank_foam = 0.0;
uniform float bank_foam_w = 0.35;
uniform float rock_foam = 0.0;
uniform float rock_foam_w = 0.3;
uniform float foam_surge = 0.6;

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

float bayer4(vec2 p) {
	const float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
		3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	return (m[x + y * 4] + 0.5) / 16.0;
}

// How far into the next texture this pixel is: smooth, or a crisp
// checkerboard when dither is on.
float weight(float v, float start, float soft, vec2 p) {
	float w = smoothstep(start - soft, start + soft + 0.0001, v);
	return dither ? step(bayer4(p), w) : w;
}

// A repeating texture drifting with the current. Two copies run half a cycle
// apart and trade places, so the texture keeps moving without stretching.
vec4 flowing(sampler2D tex, vec2 p, vec2 v_px, float w1) {
	vec2 size = vec2(textureSize(tex, 0));
	float t = TIME / motion_cycle;
	vec2 o1 = floor(v_px * fract(t) * motion_cycle * motion);
	vec2 o2 = floor(v_px * fract(t + 0.5) * motion_cycle * motion);
	vec4 a = texture(tex, (p - o1) / size);
	vec4 b = texture(tex, (p - o2) / size + 0.5);
	return mix(b, a, w1);
}

// A rain drop's ring on the surface: each cell of the water gets a drop now
// and then, at a random spot, that opens into a small ring and fades.
float dimple(vec2 p) {
	vec2 cell = floor(p / rain_cell_px);
	if (hash(cell + 0.37) > rain * 0.7) {
		return 0.0;
	}
	float t = fract(TIME * 0.9 + hash(cell + 7.1));
	if (t > 0.5) {
		return 0.0;
	}
	vec2 centre = cell * rain_cell_px + 1.0 + floor(vec2(hash(cell + 3.3), hash(cell + 5.7)) * (rain_cell_px - 2.0)) + 0.5;
	float r = t * 4.0;
	return abs(length(p - centre) - r) < 0.5 ? 1.0 - t * 2.0 : 0.0;
}

// Stones on the bed: one maybe-stone per cell of a jittered grid. Returns
// x = inside a stone (0/1), y = +1 on its lit upper-left rim, -1 on its
// shaded lower-right rim, 0 inside.
vec2 stones(vec2 p) {
	vec2 g = p / stone_px;
	vec2 cell = floor(g);
	vec2 best = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = cell + vec2(float(x), float(y));
			if (hash(c + 11.3) > stone_density) {
				continue;
			}
			vec2 centre = (c + 0.2 + 0.6 * vec2(hash(c + 1.7), hash(c + 4.1))) * stone_px;
			float r = stone_px * (0.22 + 0.28 * hash(c + 9.2));
			vec2 d = p - centre;
			// Squash a little so stones are not perfect circles.
			d.x *= 0.8 + 0.4 * hash(c + 2.9);
			if (length(d) < r) {
				// +1 on the lit upper-left rim, -1 on the shaded lower-right.
				float rim = length(d - vec2(1.0, 1.0)) >= r ? 1.0
					: (length(d + vec2(1.0, 1.0)) >= r ? -1.0 : 0.0);
				best = vec2(1.0, rim);
			}
		}
	}
	return best;
}

// A foam line hugging an edge `dist` metres away: a bright core `w` wide that
// surges in and out, with a soft glow beyond it.
float foam_line(float dist, float w, vec2 p) {
	float wave = value_noise(p / 14.0 + vec2(TIME * foam_surge * 0.35, 0.0));
	float surge = 0.6 + 0.4 * sin(TIME * foam_surge * 6.2832 + wave * 9.0);
	// Wobble the line so it frays instead of tracing the bank exactly.
	dist += (value_noise(p / 5.0) - 0.5) * w * 1.5;
	float core = 1.0 - step(w * surge, dist);
	float glow = 0.45 * (1.0 - smoothstep(0.0, w * 3.0, dist)) * (0.6 + 0.4 * wave);
	float a = max(core, glow);
	return dither ? step(bayer4(p + vec2(1.0, 3.0)), a) : a;
}

void fragment() {
	vec2 p = floor(world_px) + 0.5;
	vec4 f = texture(field, ((p - field_origin) / cell_px + 0.5) / field_cells);
	if (f.a < 0.35) {
		discard;
	}
	vec2 flow = (f.rg - 0.5) * 2.0 * flow_range;
	float depth = f.b;
	float speed = length(flow) / water_speed;
	float n = (value_noise(p / edge_noise_px) - 0.5) * 2.0 * edge_noise;

	float phase = fract(TIME / motion_cycle);
	float w1 = 1.0 - abs(1.0 - 2.0 * phase);
	if (dither) {
		w1 = step(bayer4(p + vec2(2.0, 1.0)), w1);
	}
	vec2 v_px = flow * px_per_m;

	vec4 c;
	vec4 wash = flowing(white_tex, p, v_px, w1) * white_tint;
	float w_white = weight(speed + n, white_start, white_softness, p + vec2(1.0, 2.0));
	if (use_palette) {
		// The bed first, then the water's own colour over it, then the surface.
		float d = clamp(depth + n * 0.5, 0.0, 1.0);
		vec3 water = texture(palette, vec2(d, 0.5)).rgb;
		float bed = 1.0 - smoothstep(0.0, bed_depth + 0.0001, depth);
		float sand = sand_amount * bed * (0.55 + 0.45 * value_noise(p / 10.0));
		water = mix(water, water * sand_tint.rgb * 1.6, dither ? step(bayer4(p), sand) : sand);
		vec2 st = stones(p);
		float see = stone_amount * smoothstep(0.0, 0.6, bed);
		vec3 stone = water * stone_tint.rgb;
		stone = st.y > 0.5 ? mix(water, vec3(1.0), 0.2) : (st.y < -0.5 ? stone * 0.75 : stone);
		water = mix(water, stone, st.x * see);
		vec3 pm = flowing(mid_tex, p, v_px, w1).rgb / mid_mean.rgb;
		vec3 pd = flowing(deep_tex, p, v_px, w1).rgb / deep_mean.rgb;
		vec3 pattern = mix(pm, pd, weight(depth + n, deep_start, deep_softness, p));
		c = vec4(water * mix(vec3(1.0), pattern, texture_detail), 1.0);
		float lum = dot(wash.rgb, vec3(0.3, 0.5, 0.2));
		w_white *= mix(1.0, smoothstep(0.45, 0.85, lum), wash_clear);
		c = mix(c, wash, w_white);
		vec4 e = texture(edges, ((p - field_origin) / cell_px + 0.5) / field_cells) * edge_range;
		float foam = bank_foam * foam_line(e.r, bank_foam_w, p);
		foam = max(foam, rock_foam * foam_line(e.g, rock_foam_w, p + vec2(5.0, 3.0)));
		c.rgb = mix(c.rgb, foam_tint.rgb, foam);
	} else {
		c = flowing(mid_tex, p, v_px, w1) * mid_tint;
		c = mix(c, flowing(deep_tex, p, v_px, w1) * deep_tint, weight(depth + n, deep_start, deep_softness, p));
		c = mix(c, wash, w_white);
	}
	float shallow = shallow_amount * (1.0 - smoothstep(0.0, shallow_depth + 0.0001, depth));
	c.rgb = mix(c.rgb, shallow_tint.rgb, dither ? step(bayer4(p + vec2(3.0, 0.0)), shallow) : shallow);
	if (rain > 0.0) {
		c.rgb = mix(c.rgb, vec3(1.0), 0.35 * dimple(p));
	}
	COLOR = vec4(c.rgb, 1.0);
}
