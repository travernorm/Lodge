// The weather's colour grade over the whole picture (REQ-0009), plus version
// C's drifting cloud shadows and lightning flash. Reads the screen drawn so
// far, so it sits above the river and below the HUD and debug layers.
// See scripts/conditions/weather_view.gd.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform vec4 tint = vec4(1.0);
uniform float brightness = 1.0;
uniform float saturation = 1.0;
uniform float contrast = 1.0;
uniform float flash = 0.0;
uniform float clouds = 0.0;
// Where the screen's top-left corner is in the world (px), plus the clouds'
// drift, so the shadows stay on the ground as the camera moves.
uniform vec2 world_origin = vec2(0.0);
uniform float cloud_px = 96.0;

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

void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	c = (c - 0.5) * contrast + 0.5;
	c *= tint.rgb * brightness;
	if (clouds > 0.0) {
		vec2 w = floor(screen_px + world_origin) / cloud_px;
		float n = value_noise(w) * 0.65 + value_noise(w * 2.03 + 17.0) * 0.35;
		c *= 1.0 - 0.3 * clouds * smoothstep(0.5, 0.62, n);
	}
	c = mix(c, vec3(1.0), clamp(flash, 0.0, 1.0));
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
