shader_type spatial;
// The red person-silhouette target with a bullseye on the chest.
// UV is the position on the face in meters + 0.5 (see
// tools/blender/make_person_target.py), so shapes here are in real units.
// Keep the bullseye numbers in step with RangeTarget.BULL_* and the scoring.

uniform vec4 body_color : source_color = vec4(0.78, 0.12, 0.1, 1.0);
uniform vec4 outline_color : source_color = vec4(0.18, 0.03, 0.03, 1.0);
uniform vec4 ring_color : source_color = vec4(1.0, 0.96, 0.9, 1.0);

const vec2 HEAD_CENTER = vec2(0.0, 0.31);
const float HEAD_RADIUS = 0.15;
const vec2 BULL_CENTER = vec2(0.0, -0.12);

// Signed distance to the torso outline (negative inside).
float torso_sd(vec2 p) {
	vec2 pts[6] = vec2[](vec2(-0.30, -0.45), vec2(0.30, -0.45), vec2(0.30, 0.05),
		vec2(0.18, 0.16), vec2(-0.18, 0.16), vec2(-0.30, 0.05));
	float d = -1.0;
	for (int i = 0; i < 6; i++) {
		vec2 a = pts[i];
		vec2 b = pts[(i + 1) % 6];
		vec2 e = normalize(b - a);
		vec2 n = vec2(e.y, -e.x); // outward for counter-clockwise points
		d = max(d, dot(p - a, n));
	}
	return d;
}

void fragment() {
	vec2 p = UV - vec2(0.5);
	p.y = -p.y;
	vec3 c = body_color.rgb;
	float edge = min(torso_sd(p), length(p - HEAD_CENTER) - HEAD_RADIUS);
	if (edge > -0.018) {
		c = outline_color.rgb;
	}
	float r = length(p - BULL_CENTER);
	if (r < 0.05 || (r > 0.098 && r < 0.112) || (r > 0.158 && r < 0.172)) {
		c = ring_color.rgb;
	}
	ALBEDO = c;
	ROUGHNESS = 0.8;
}
