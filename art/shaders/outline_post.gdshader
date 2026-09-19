shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

// Full-screen pass drawn on a quad under the camera (STYLE.md §3, §8):
//  - dark ink line work from depth + normal discontinuities: silhouettes AND interior edges
//  - value ceiling so nothing reaches full brightness
//  - ordered dither + static paper grain. No bloom, no blur, no lens effects.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest;
uniform vec4 ink : source_color = vec4(0.14, 0.09, 0.06, 1.0);
uniform float line_width : hint_range(0.5, 6.0) = 1.0;
uniform float depth_threshold : hint_range(0.01, 2.0) = 0.35;
uniform float depth_distance_scale : hint_range(0.0, 0.2) = 0.03;
uniform float normal_threshold : hint_range(0.0, 1.0) = 0.42;
uniform float value_ceiling : hint_range(0.5, 1.0) = 0.85;
uniform float dither_strength : hint_range(0.0, 0.1) = 0.006;
uniform float grain_strength : hint_range(0.0, 0.2) = 0.012;
uniform float sky_distance = 350.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float linear_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).x;
	vec3 ndc = vec3(uv * 2.0 - 1.0, d);
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return -v.z / v.w;
}

vec3 view_normal(vec2 uv) {
	return normalize(texture(normal_tex, uv).rgb * 2.0 - 1.0);
}

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int idx = x + y * 4;
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[idx] + 0.5) / 16.0 - 0.5;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float d0 = linear_depth(uv, INV_PROJECTION_MATRIX);
	// Drawn line weight: heavier up close, lighter in the distance, like a pen at two scales.
	vec2 px = line_width * mix(1.3, 0.8, clamp(d0 / 40.0, 0.0, 1.0)) / VIEWPORT_SIZE;
	float dl = linear_depth(uv - vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	float dr = linear_depth(uv + vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	float du = linear_depth(uv - vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	float dd = linear_depth(uv + vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	float dmin = min(min(dl, dr), min(du, dd));
	// Only the nearer side of a discontinuity draws the line, so lines hug the front object.
	float ddepth = max(max(d0 - dl, d0 - dr), max(d0 - du, d0 - dd));
	ddepth = max(ddepth, 0.0);
	float depth_edge = step(depth_threshold * (1.0 + dmin * depth_distance_scale), ddepth);
	// Also catch the far-side pixel of thin objects against far backgrounds.
	float ddepth2 = max(max(dl - d0, dr - d0), max(du - d0, dd - d0));
	depth_edge = max(depth_edge, step(depth_threshold * (1.0 + d0 * depth_distance_scale), ddepth2) * step(d0, sky_distance));

	float normal_edge = 0.0;
	if (d0 < sky_distance) {
		vec3 n0 = view_normal(uv);
		float dn = max(max(1.0 - dot(n0, view_normal(uv - vec2(px.x, 0.0))), 1.0 - dot(n0, view_normal(uv + vec2(px.x, 0.0)))),
			max(1.0 - dot(n0, view_normal(uv - vec2(0.0, px.y))), 1.0 - dot(n0, view_normal(uv + vec2(0.0, px.y)))));
		normal_edge = step(normal_threshold, dn);
	}
	float edge = max(depth_edge, normal_edge);

	vec3 col = texture(screen_tex, uv).rgb;
	col = mix(col, ink.rgb, edge * ink.a);

	// Value ceiling for surfaces, applied in linear light (the ceiling is an sRGB value). The sky
	// is exempt: reference cloud highlights reach V 0.97 (STYLE.md appendix).
	float ceiling_lin = pow(value_ceiling, 2.2);
	float mx = max(col.r, max(col.g, col.b));
	if (d0 < sky_distance && mx > ceiling_lin) {
		col *= ceiling_lin / mx;
	}
	// Print texture: ordered dither and a static grain.
	vec2 pixel = uv * VIEWPORT_SIZE;
	col += bayer4(pixel) * dither_strength;
	col += (hash12(floor(pixel * 0.5)) - 0.5) * grain_strength * 0.5;
	ALBEDO = max(col, vec3(0.0));
}
