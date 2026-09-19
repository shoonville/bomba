shader_type canvas_item;

// The marbled swirl (STYLE.md §4): domain-warped noise banded into the screen's palette.
// Procedural, no texture asset. Slow drift so menus feel alive without being busy.

uniform vec4 col_a : source_color = vec4(0.42, 0.28, 0.62, 1.0);
uniform vec4 col_b : source_color = vec4(0.34, 0.58, 0.68, 1.0);
uniform vec4 col_c : source_color = vec4(0.80, 0.72, 0.36, 1.0);
uniform vec4 col_d : source_color = vec4(0.18, 0.12, 0.26, 1.0);
uniform float scale = 2.2;
uniform float speed = 0.05;
uniform float warp = 1.6;
uniform float bands = 5.0;
uniform float value_ceiling = 0.85;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(dot(hash2(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0)), dot(hash2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), u.x),
		mix(dot(hash2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)), dot(hash2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV * scale;
	float t = TIME * speed;
	vec2 q = vec2(fbm(uv + vec2(0.0, t)), fbm(uv + vec2(5.2, 1.3) - t));
	vec2 r = vec2(fbm(uv + warp * q + vec2(1.7, 9.2) + 0.3 * t), fbm(uv + warp * q + vec2(8.3, 2.8) - 0.2 * t));
	float f = clamp(fbm(uv + warp * r) * 2.2 + 0.5, 0.0, 1.0);
	float band = floor(f * bands) / bands;
	vec3 col = mix(col_d.rgb, col_a.rgb, smoothstep(0.0, 0.35, band));
	col = mix(col, col_b.rgb, smoothstep(0.35, 0.65, band));
	col = mix(col, col_c.rgb, smoothstep(0.65, 1.0, band) * 0.85);
	// thin ink seams between bands
	float seam = abs(fract(f * bands) - 0.5);
	col = mix(col_d.rgb, col, smoothstep(0.015, 0.05, seam));
	float mx = max(col.r, max(col.g, col.b));
	if (mx > value_ceiling) {
		col *= value_ceiling / mx;
	}
	COLOR = vec4(col, 1.0);
}
