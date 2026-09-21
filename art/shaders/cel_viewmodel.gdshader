shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_disabled, ambient_light_disabled;

// The cel shader with the viewmodel depth trick: clip-space depth is squashed toward the near
// plane so the gun never pokes through walls, while the parts of the gun still depth-test
// against each other. Forward+ uses reversed Z (near = 1.0).

uniform vec4 albedo : source_color = vec4(0.80, 0.70, 0.50, 1.0);
uniform vec4 shadow_tint : source_color = vec4(0.74, 0.78, 0.94, 1.0);
uniform float band_threshold : hint_range(0.0, 1.0) = 0.32;
uniform float band_softness : hint_range(0.0, 0.2) = 0.01;
uniform float lit_level : hint_range(0.0, 2.0) = 1.0;
uniform float shadow_level : hint_range(0.0, 1.5) = 0.7;
uniform float emission_strength : hint_range(0.0, 2.0) = 0.0;
uniform vec4 emission_color : source_color = vec4(1.0);
uniform float depth_squash : hint_range(0.0, 1.0) = 0.96;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	clip.z = mix(clip.z, clip.w, depth_squash);
	POSITION = clip;
}

void fragment() {
	ALBEDO = albedo.rgb;
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
