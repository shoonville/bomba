shader_type sky;

// BRC-style sky (STYLE.md appendix): a plain vertical gradient with flat two-tone cloud shapes,
// hard edges and a thin ink rim. The lit body is on the upper side of each cloud, the shadow tone
// on the underside. Procedural; no texture asset.

uniform vec4 sky_top : source_color = vec4(0.48, 0.66, 0.70, 1.0);
uniform vec4 sky_horizon : source_color = vec4(0.86, 0.72, 0.58, 1.0);
uniform vec4 cloud_lit : source_color = vec4(0.97, 0.85, 0.69, 1.0);
uniform vec4 cloud_shadow : source_color = vec4(0.37, 0.42, 0.32, 1.0);
uniform vec4 ink : source_color = vec4(0.16, 0.10, 0.06, 1.0);
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.42;
uniform float cloud_scale : hint_range(0.2, 6.0) = 2.4;
uniform float horizon_blend : hint_range(0.05, 1.0) = 0.30;
uniform float underside : hint_range(0.01, 0.3) = 0.07;
uniform float drift : hint_range(0.0, 0.05) = 0.003;
uniform float rim : hint_range(0.0, 0.05) = 0.014;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(dot(hash2(i), f), dot(hash2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), u.x),
		mix(dot(hash2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)), dot(hash2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.1 + vec2(3.7, 1.9);
		a *= 0.5;
	}
	return v * 0.5 + 0.5;
}

vec2 cloud_uv(vec3 dir) {
	// Project onto a plane above the viewer so clouds get perspective toward the horizon.
	float y = max(dir.y, 0.04);
	return dir.xz / (y + 0.35) * cloud_scale + vec2(TIME * drift, 0.0);
}

void sky() {
	vec3 dir = EYEDIR;
	float elev = dir.y;
	float t = smoothstep(0.0, 1.0, clamp(elev / horizon_blend, 0.0, 1.0));
	vec3 col = mix(sky_horizon.rgb, sky_top.rgb, t);
	if (elev < 0.0) {
		col = sky_horizon.rgb * 0.92;
	} else if (elev > 0.015) {
		float n = fbm(cloud_uv(dir));
		// Lit where the cloud continues below this point (the upper body), shadow where moving
		// down along elevation leaves the cloud (the underside). Elevation is a world axis, so
		// the split is the same from every viewpoint.
		vec3 below = normalize(dir - vec3(0.0, underside * max(dir.y, 0.15), 0.0));
		float n_below = fbm(cloud_uv(below));
		float mask = step(cloud_coverage, n);
		float lit = step(cloud_coverage + 0.02, n_below);
		vec3 cloud = mix(cloud_shadow.rgb, cloud_lit.rgb, lit);
		float edge = 1.0 - step(rim, n - cloud_coverage);
		cloud = mix(cloud, ink.rgb, edge);
		float fade = smoothstep(0.015, 0.09, elev);
		col = mix(col, cloud, mask * fade);
	}
	COLOR = col;
}
