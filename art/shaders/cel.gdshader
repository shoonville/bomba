shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_disabled, ambient_light_disabled;

// Two-band cel shading (STYLE.md §2). Shadow is a hue shift toward the location's cool band,
// never a darkening toward black. No specular, no ambient occlusion; edges come from line work.

uniform vec4 albedo : source_color = vec4(0.80, 0.70, 0.50, 1.0);
uniform vec4 shadow_tint : source_color = vec4(0.66, 0.70, 0.86, 1.0);
uniform float band_threshold : hint_range(0.0, 1.0) = 0.32;
uniform float band_softness : hint_range(0.0, 0.2) = 0.01;
uniform float lit_level : hint_range(0.0, 2.0) = 1.0;
uniform float shadow_level : hint_range(0.0, 1.5) = 0.84;
uniform float emission_strength : hint_range(0.0, 2.0) = 0.0;
uniform vec4 emission_color : source_color = vec4(1.0);

void fragment() {
	ALBEDO = albedo.rgb;
	EMISSION = emission_color.rgb * emission_strength;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float band = smoothstep(band_threshold - band_softness, band_threshold + band_softness, ndl * ATTENUATION);
	vec3 lit = ALBEDO * LIGHT_COLOR * lit_level;
	vec3 shade = ALBEDO * shadow_tint.rgb * shadow_level;
	DIFFUSE_LIGHT += mix(shade, lit, band);
}
