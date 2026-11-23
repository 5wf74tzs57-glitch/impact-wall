shader_type spatial;
// A friendly: the same silhouette in blue, with a smiley face on the head.
// Hitting it costs points. UV is the position on the face in meters + 0.5.

uniform vec4 body_color : source_color = vec4(0.16, 0.45, 0.85, 1.0);
uniform vec4 face_color : source_color = vec4(1.0, 0.86, 0.25, 1.0);
uniform vec4 ink_color : source_color = vec4(0.08, 0.08, 0.14, 1.0);

const vec2 HEAD_CENTER = vec2(0.0, 0.31);
const float HEAD_RADIUS = 0.15;

float torso_sd(vec2 p) {
	vec2 pts[6] = vec2[](vec2(-0.30, -0.45), vec2(0.30, -0.45), vec2(0.30, 0.05),
		vec2(0.18, 0.16), vec2(-0.18, 0.16), vec2(-0.30, 0.05));
	float d = -1.0;
	for (int i = 0; i < 6; i++) {
		vec2 a = pts[i];
		vec2 b = pts[(i + 1) % 6];
		vec2 e = normalize(b - a);
		d = max(d, dot(p - a, vec2(e.y, -e.x)));
	}
	return d;
}

void fragment() {
	vec2 p = UV - vec2(0.5);
	p.y = -p.y;
	vec3 c = body_color.rgb;
	vec2 h = p - HEAD_CENTER;
	float head_d = length(h) - HEAD_RADIUS;
	if (head_d < 0.0) {
		c = face_color.rgb;
		// Eyes.
		if (length(h - vec2(-0.05, 0.035)) < 0.02 || length(h - vec2(0.05, 0.035)) < 0.02) {
			c = ink_color.rgb;
		}
		// Smile.
		vec2 m = h - vec2(0.0, 0.01);
		float d = length(m);
		if (m.y < -0.02 && d > 0.07 && d < 0.095) {
			c = ink_color.rgb;
		}
	}
	if (min(torso_sd(p), head_d) > -0.018) {
		c = ink_color.rgb; // Outline.
	}
	// A white star badge on the chest, so friendlies read at a distance.
	vec2 s = p - vec2(0.0, -0.12);
	float a = atan(s.y, s.x);
	float star = 0.07 + 0.035 * cos(5.0 * (a - 1.5708));
	if (length(s) < star) {
		c = vec3(1.0);
	}
	ALBEDO = c;
	ROUGHNESS = 0.8;
}
