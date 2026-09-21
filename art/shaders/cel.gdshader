shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_disabled, ambient_light_disabled;

// Two-band cel shading (STYLE.md §2). Shadow is a hue shift toward the location's cool band,
// never a darkening toward black. No specular, no ambient occlusion; edges come from line work.
//
// The print layer (STYLE.md §3 interior line work; §8: silhouette-only outlines read as generic
// toon shading, and flat fields must still carry drawn detail): optional, world-space, all off by
// default, turned on per surface by CelMaterial.with_print() from tuning/palette.json "print".
//  - seams: ink lines on a grid in metres (paving slabs, wall panels, storeys), projected on the
//    plane the surface faces most, with a flat value step per cell so no two slabs match exactly;
//    a seam thinner than a pixel fades out instead of sparkling;
//  - mottle: hard-edged blotches of the shaded tone (regolith, worn plazas), two-tone like the
//    clouds, never a gradient.

uniform vec4 albedo : source_color = vec4(0.80, 0.70, 0.50, 1.0);
uniform vec4 shadow_tint : source_color = vec4(0.66, 0.70, 0.86, 1.0);
uniform float band_threshold : hint_range(0.0, 1.0) = 0.32;
uniform float band_softness : hint_range(0.0, 0.2) = 0.01;
uniform float lit_level : hint_range(0.0, 2.0) = 1.0;
uniform float shadow_level : hint_range(0.0, 1.5) = 0.7;
uniform float emission_strength : hint_range(0.0, 2.0) = 0.0;
uniform vec4 emission_color : source_color = vec4(1.0);
uniform vec2 seam_size = vec2(0.0, 0.0);                       // metres between seams; 0 = none
uniform float seam_width : hint_range(0.0, 0.5) = 0.05;        // metres
uniform float seam_strength : hint_range(0.0, 1.0) = 0.85;     // how far a seam goes to the ink
uniform vec4 seam_ink : source_color = vec4(0.14, 0.09, 0.06, 1.0);
uniform float seam_base_y = 0.0;                               // storey seams count up from here
uniform float cell_jitter : hint_range(0.0, 0.3) = 0.0;        // flat value step per cell (±)
uniform float mottle_size : hint_range(0.0, 60.0) = 0.0;       // metres; 0 = none
uniform float mottle_strength : hint_range(0.0, 1.0) = 0.0;    // how far a blotch goes to shade
uniform float mottle_threshold : hint_range(0.0, 1.0) = 0.55;  // higher = fewer, smaller blotches

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec3 col = albedo.rgb;
	if (seam_size.x > 0.0 || mottle_size > 0.0) {
		vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec3 wn = abs(normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz));
		// Floors and ceilings print on XZ; walls on the upright plane they face.
		vec2 uv = wp.xz;
		if (wn.y < 0.5) {
			uv = (wn.x > wn.z) ? vec2(wp.z, wp.y - seam_base_y) : vec2(wp.x, wp.y - seam_base_y);
		}
		if (seam_size.x > 0.0) {
			vec2 g = uv / seam_size;
			vec2 cell = floor(g);
			vec2 dm = min(fract(g), 1.0 - fract(g)) * seam_size;
			float d = min(dm.x, dm.y);
			// One pixel's footprint in metres on this surface: the line is drawn at its width, at
			// least a pixel wide, and fades as it drops under a pixel so distance never sparkles.
			float px = max(fwidth(d), 1e-4);
			float half_w = max(seam_width * 0.5, px * 0.5);
			float line = 1.0 - smoothstep(half_w - px * 0.5, half_w + px * 0.5, d);
			float fade = clamp(seam_width / (2.0 * px), 0.0, 1.0);
			col *= 1.0 + (hash21(cell + 7.0) - 0.5) * 2.0 * cell_jitter;
			col = mix(col, seam_ink.rgb, line * seam_strength * fade);
		}
		if (mottle_size > 0.0) {
			float n = vnoise(uv / mottle_size) * 0.65 + vnoise(uv / mottle_size * 2.7 + 11.0) * 0.35;
			float fw = max(fwidth(n), 1e-4);
			float blotch = smoothstep(mottle_threshold - fw, mottle_threshold + fw, n);
			col = mix(col, col * shadow_tint.rgb * 0.92, blotch * mottle_strength);
		}
	}
	ALBEDO = col;
	EMISSION = emission_color.rgb * emission_strength;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float band = smoothstep(band_threshold - band_softness, band_threshold + band_softness, ndl * ATTENUATION);
	// Godot multiplies DIFFUSE_LIGHT by ALBEDO after light() and hands LIGHT_COLOR in times PI, so
	// the bands are written without ALBEDO and the lit band undoes the PI (measured 2026-09-20: with
	// ALBEDO here every surface rendered as albedo squared and the shadow band fell toward black).
	vec3 lit = LIGHT_COLOR / PI * lit_level;
	vec3 shade = shadow_tint.rgb * shadow_level;
	DIFFUSE_LIGHT += mix(shade, lit, band);
}
