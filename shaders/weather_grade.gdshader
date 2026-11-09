// The light over the whole picture (REQ-0009, REQ-0015): the weather's and
// the time of day's colour grade (one tint for the bright parts, another for
// the dark), cloud shadows drifting over the ground, and lightning. Reads the
// screen drawn so far, so it sits above the river and below the HUD and debug
// layers. See scripts/conditions/weather_view.gd.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen : hint_screen_texture, filter_nearest;
// The light on the bright parts of the picture and on the dark parts.
uniform vec4 tint = vec4(1.0);
uniform vec4 shadow_tint = vec4(1.0);
uniform float brightness = 1.0;
uniform float saturation = 1.0;
uniform float contrast = 1.0;
// Cloud shadows: how dark and cool one is, and how much of the sky is cloud.
uniform float clouds = 0.0;
uniform float cover = 0.0;
// Where the screen's top-left corner is in the world (px), less the clouds'
// drift, so the shadows stay on the ground as the camera moves.
uniform vec2 world_origin = vec2(0.0);
uniform float cloud_px = 112.0;
// Lightning: how bright, which side it comes from (-1 left, 1 right, 0 all
// round), and how much darker the picture sits just afterwards.
uniform float flash = 0.0;
uniform float flash_side = 0.0;
uniform float afterglow = 0.0;

varying vec2 screen_px;

void vertex() {
	screen_px = VERTEX;
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

// How deep in cloud shadow a spot on the ground is: 0 sun, 0.5 the soft edge,
// 1 full shadow. Stepped, so the edge stays crisp pixels.
float cloud_shade(vec2 world) {
	vec2 w = world / cloud_px;
	float n = value_noise(w) * 0.55 + value_noise(w * 2.03 + 17.0) * 0.3 + value_noise(w * 4.1 + 41.0) * 0.15;
	float edge = mix(0.8, 0.2, cover);
	float s = smoothstep(edge - 0.05, edge + 0.05, n);
	return clamp(floor(s * 3.0) * 0.5, 0.0, 1.0);
}

void fragment() {
	vec3 raw = texture(screen, SCREEN_UV).rgb;
	vec3 c = raw;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	c = (c - 0.5) * contrast + 0.5;
	l = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 lit = c * mix(shadow_tint.rgb, tint.rgb, smoothstep(0.2, 0.7, l));
	if (clouds > 0.0 && cover > 0.0) {
		float shade = cloud_shade(floor(screen_px + world_origin)) * clouds;
		vec3 dim = mix(vec3(l), c, 0.85) * shadow_tint.rgb * 0.68;
		lit = mix(lit, dim, shade);
	}
	c = lit * brightness;
	if (flash > 0.0) {
		// Lit from above: bright things jump to blue-white, dark things stay dark.
		float from_side = flash_side > 0.0 ? SCREEN_UV.x : 1.0 - SCREEN_UV.x;
		float k = flash * mix(1.0, 0.55 + 0.7 * from_side, abs(flash_side));
		float rl = dot(raw, vec3(0.299, 0.587, 0.114));
		vec3 pale = mix(vec3(rl), raw, 0.5);
		vec3 struck = max((pale - 0.35) * 1.9 + 0.35, vec3(0.0)) * vec3(0.8, 0.92, 1.15) + vec3(0.05, 0.07, 0.13);
		c = mix(c, struck, clamp(k, 0.0, 1.0));
	}
	c *= 1.0 - afterglow;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
