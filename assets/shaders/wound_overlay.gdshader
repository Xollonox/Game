shader_type spatial;
// Blood that stays where the blade went in. Drawn as a material overlay on
// every visible mesh of a fighter; wound centres are world positions updated
// each frame from the rig bodies they were struck on (w = radius).
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;

uniform vec4 wounds[6];
uniform int count = 0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	float m = 0.0;
	for (int i = 0; i < 6; i++) {
		if (i >= count) break;
		vec3 d = wpos - wounds[i].xyz;
		// Runs downward: stretch the stain below the wound.
		d.y = d.y > 0.0 ? d.y * 1.6 : d.y * 0.45;
		float r = wounds[i].w;
		float edge = r * (0.75 + 0.5 * noise(wpos * 38.0));
		m = max(m, smoothstep(edge, edge * 0.45, length(d)));
	}
	float speck = step(0.8, noise(wpos * 90.0)) * 0.35;
	ALBEDO = mix(vec3(0.16, 0.012, 0.01), vec3(0.3, 0.02, 0.015), noise(wpos * 20.0));
	ROUGHNESS = 0.22;
	SPECULAR = 0.6;
	ALPHA = clamp(m * (0.88 + speck), 0.0, 0.92);
}
