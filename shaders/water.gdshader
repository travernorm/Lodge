// Paints the river from a WaterLook (scripts/river/water_look.gd).
// The field texture is the RiverField baked one texel per cell:
// R, G = current (m/s, encoded around 0.5), B = depth (0..1), A = wet.
// See scripts/river/water_view.gd.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D field : filter_linear, repeat_disable;
uniform vec2 field_cells = vec2(1.0);
uniform float cell_px = 2.0;
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

void fragment() {
	vec2 p = floor(world_px) + 0.5;
	vec4 f = texture(field, (p / cell_px + 0.5) / field_cells);
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

	vec4 c = flowing(mid_tex, p, v_px, w1) * mid_tint;
	c = mix(c, flowing(deep_tex, p, v_px, w1) * deep_tint, weight(depth + n, deep_start, deep_softness, p));
	c = mix(c, flowing(white_tex, p, v_px, w1) * white_tint, weight(speed + n, white_start, white_softness, p + vec2(1.0, 2.0)));
	float shallow = shallow_amount * (1.0 - smoothstep(0.0, shallow_depth + 0.0001, depth));
	c.rgb = mix(c.rgb, shallow_tint.rgb, dither ? step(bayer4(p + vec2(3.0, 0.0)), shallow) : shallow);
	COLOR = vec4(c.rgb, 1.0);
}
